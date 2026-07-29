#!/usr/bin/env python3
"""Turn the PokeAPI cache into the four data files the game loads.

The output stays a faithful, compact mirror of the API: base stats, the type
chart, move mechanics, learnsets. None of the Slay-the-Spire balancing lives
here — that mapping is PokeBalance.gd, so it can be retuned without a refetch.

Every unit the API lists becomes a row, not just the 1025 numbered species:
megas, regional variants, Rotom's appliances and one-offs like Floette-Eternal
each fight differently enough to be worth their own entry. Smogon's CAP dex is
folded in on top, from the Showdown mirror; see cap.py for that translation.

    python3 tools/build_data.py [--cache DIR] [--out DIR]

Writes data/types.json, data/moves.json, data/pokemon.json, data/evolution.json.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import cap

## The National Dex through Gen 9. Above this are the API's alternate forms.
MAX_DEX = 1025

STAT_KEYS = {
    "hp": "hp",
    "attack": "atk",
    "defense": "df",
    "special-attack": "spa",
    "special-defense": "spd",
    "speed": "spe",
}

# Learn methods, packed as ints in the learnset triples.
METHOD_CODES = {"level-up": 0, "machine": 1, "egg": 2, "tutor": 3}
METHOD_OTHER = 4


def method_code(name: str) -> int:
    """The int a learn method packs down to. cap.py is handed this so that
    these codes stay defined in one place."""
    return METHOD_CODES.get(name, METHOD_OTHER)


def load(cache: str, kind: str, key):
    path = os.path.join(cache, kind, f"{key}.json")
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def english(entries: list, field: str) -> str:
    """PokeAPI returns every localisation in one list; take the English one."""
    for e in entries:
        if e.get("language", {}).get("name") == "en":
            return " ".join(e[field].split())
    return ""


def version_group_id(url: str) -> int:
    return int(url.rstrip("/").rsplit("/", 1)[-1])


def build_types(cache: str) -> dict:
    index = load(cache, "", "type?limit=100")
    names = [t["name"] for t in index["results"]]
    # "unknown" and "stellar" have no real chart and never appear on a species.
    names = [n for n in names if n not in ("unknown", "stellar", "shadow")]
    chart = {}
    for name in names:
        body = load(cache, "type", name)
        rel = body["damage_relations"]
        row = {}
        for other in (x["name"] for x in rel["double_damage_to"]):
            row[other] = 2.0
        for other in (x["name"] for x in rel["half_damage_to"]):
            row[other] = 0.5
        for other in (x["name"] for x in rel["no_damage_to"]):
            row[other] = 0.0
        chart[name] = row
    return {"types": names, "chart": chart}


def build_moves(cache: str, wanted: set) -> list:
    out = []
    for name in sorted(wanted):
        body = load(cache, "move", name)
        if body is None:
            continue
        meta = body.get("meta") or {}
        ailment = (meta.get("ailment") or {}).get("name", "none")
        category = (meta.get("category") or {}).get("name", "damage")
        stat_changes = [
            {"stat": STAT_KEYS.get(sc["stat"]["name"], sc["stat"]["name"]),
             "change": sc["change"]}
            for sc in body.get("stat_changes", [])
        ]
        effect = english(body.get("effect_entries", []), "short_effect")
        chance = body.get("effect_chance")
        if chance is not None:
            effect = effect.replace("$effect_chance", str(chance))
        out.append({
            "name": body["name"],
            "id": body["id"],
            # accuracy null means "cannot miss" (Swift, Aerial Ace); power null
            # means the move deals no fixed damage of its own.
            "power": body.get("power") or 0,
            "acc": body.get("accuracy") or 0,
            "pp": body.get("pp") or 5,
            "prio": body.get("priority") or 0,
            "type": (body.get("type") or {}).get("name", "normal"),
            "class": (body.get("damage_class") or {}).get("name", "status"),
            "target": (body.get("target") or {}).get("name", "selected-pokemon"),
            "ailment": ailment,
            "ailment_chance": meta.get("ailment_chance") or 0,
            "category": category,
            "crit_rate": meta.get("crit_rate") or 0,
            "drain": meta.get("drain") or 0,
            "healing": meta.get("healing") or 0,
            "flinch_chance": meta.get("flinch_chance") or 0,
            "stat_chance": meta.get("stat_chance") or 0,
            "min_hits": meta.get("min_hits") or 0,
            "max_hits": meta.get("max_hits") or 0,
            "min_turns": meta.get("min_turns") or 0,
            "max_turns": meta.get("max_turns") or 0,
            "effect_chance": chance or 0,
            "stat_changes": stat_changes,
            "effect": effect,
        })
    return out


def learnset_for(body: dict, move_index: dict) -> list:
    """Flatten version-group learn data to one [move, level, method] per move.

    A move can be learnt differently in every game; keep the most recent version
    group's entry so the learnset reflects current games rather than Gen 1.
    """
    rows = []
    for entry in body.get("moves", []):
        name = entry["move"]["name"]
        idx = move_index.get(name)
        if idx is None:
            continue
        best = None
        for det in entry.get("version_group_details", []):
            vg = version_group_id(det["version_group"]["url"])
            if best is None or vg > best[0]:
                best = (vg, det)
        if best is None:
            continue
        det = best[1]
        method = det["move_learn_method"]["name"]
        rows.append([idx, det.get("level_learned_at") or 0,
                     METHOD_CODES.get(method, METHOD_OTHER)])
    rows.sort(key=lambda r: (r[2], r[1], r[0]))
    return rows


def cached_ids(cache: str, limit: int, forms: bool = True) -> list:
    """Every unit id mirrored into the cache, species and alternate forms both.

    The cache is the authority rather than a range, so a form the API adds
    later needs only a refetch to appear here. A limit below the full dex means
    a quick test run, which drops the forms with it.
    """
    folder = os.path.join(cache, "pokemon")
    if not os.path.isdir(folder):
        return []
    ids = sorted(int(f[:-5]) for f in os.listdir(folder) if f.endswith(".json"))
    if limit < MAX_DEX:
        return [i for i in ids if i <= limit]
    return [i for i in ids if i <= limit or (i > MAX_DEX and forms)]


def species_id_of(body: dict) -> int:
    url = (body.get("species") or {}).get("url", "")
    return int(url.rstrip("/").rsplit("/", 1)[-1]) if url else 0


def build_pokemon(cache: str, ids: list, move_index: dict) -> list:
    out = []
    for dex in ids:
        body = load(cache, "pokemon", dex)
        if body is None:
            continue
        # A form has no species record of its own: the flags, the XP curve and
        # the dex category all belong to the species it is a form of.
        species = load(cache, "pokemon-species", species_id_of(body)) or {}
        form = {}
        if dex > MAX_DEX and body.get("forms"):
            form = load(cache, "pokemon-form", body["forms"][0]["name"]) or {}
        stats = {}
        for s in body.get("stats", []):
            key = STAT_KEYS.get(s["stat"]["name"])
            if key:
                stats[key] = s["base_stat"]
        if len(stats) != 6:
            continue
        types = [t["type"]["name"] for t in
                 sorted(body.get("types", []), key=lambda t: t["slot"])]
        out.append({
            "id": dex,
            "name": body["name"],
            # Which species this is, and which of its forms. Both are "" and ""
            # for a default form; "rattata"/"alola" for Alolan Rattata. The
            # evolution builder needs them, and the game can group by them.
            "species": species.get("name", body["name"]),
            "form": form.get("form_name", ""),
            # Megas, Primals, Zen Mode and the rest never exist outside a
            # battle, so an encounter that wants a wild Pokemon can skip them.
            "battle_only": bool(form.get("is_battle_only")),
            "types": types,
            "stats": stats,
            "bst": sum(stats.values()),
            "height": body.get("height") or 0,
            "weight": body.get("weight") or 0,
            "legendary": bool(species.get("is_legendary")),
            "mythical": bool(species.get("is_mythical")),
            "baby": bool(species.get("is_baby")),
            "capture_rate": species.get("capture_rate") or 0,
            "color": (species.get("color") or {}).get("name", "gray"),
            "genus": english(species.get("genera", []), "genus"),
            # Levelling needs the XP curve and what this species is worth.
            "growth": (species.get("growth_rate") or {}).get("name", "medium"),
            "base_xp": body.get("base_experience") or 60,
            "learnset": learnset_for(body, move_index),
        })
    return out


def inherit_missing_learnsets(mons: list) -> int:
    """Give a form its species' moves when the API records none for it.

    Every Gigantamax form and the newest wave of Megas ship with an empty move
    list: the API treats them as a costume the species wears rather than
    something with a movepool of its own. Taken literally that would be a unit
    with no cards, so each falls back to what its species knows — which is also
    the truth of it, since a Gigantamax Charizard is a Charizard.
    """
    default = {m["species"]: m for m in mons if m["id"] <= MAX_DEX}
    filled = 0
    for mon in mons:
        if mon["learnset"] or not mon["form"]:
            continue
        source = default.get(mon["species"])
        if source and source["learnset"]:
            mon["learnset"] = [row[:] for row in source["learnset"]]
            filled += 1
    return filled


## Evolution triggers we can express in a dungeon. Anything else (trade,
## location, time of day, a held item) is folded onto a level threshold by
## build_evolutions, since none of those exist in a Spire run.
LEVEL_TRIGGER = "level-up"
ITEM_TRIGGER = "use-item"

## Level at which a trigger we cannot reproduce is treated as firing. Stone
## evolutions in the games happen whenever you find the stone, which in dungeon
## terms is "somewhere in the middle".
FALLBACK_EVO_LEVEL = 30
TRADE_EVO_LEVEL = 37


def evo_level(detail: dict) -> int:
    """The level this evolution should happen at, in dungeon terms."""
    if detail.get("min_level"):
        return int(detail["min_level"])
    trigger = (detail.get("trigger") or {}).get("name", "")
    if trigger == "trade":
        return TRADE_EVO_LEVEL
    if detail.get("min_happiness") or detail.get("min_affection"):
        # Friendship evolutions come early in practice.
        return 22
    return FALLBACK_EVO_LEVEL


def walk_chain(node: dict, out: dict) -> None:
    """Flattens a chain into {species: [{to, level, trigger}, ...]}."""
    name = node["species"]["name"]
    branches = []
    for child in node.get("evolves_to", []):
        details = child.get("evolution_details") or [{}]
        # A branch can list several ways to evolve; take the earliest.
        best = min(details, key=evo_level)
        branches.append({
            "to": child["species"]["name"],
            "level": evo_level(best),
            "trigger": (best.get("trigger") or {}).get("name", LEVEL_TRIGGER),
        })
        walk_chain(child, out)
    if branches:
        branches.sort(key=lambda b: b["level"])
        out[name] = branches


## ── Regional forms ───────────────────────────────────────────────────────────
## PokeAPI's evolution chains are keyed by species, and a species covers all of
## its regional forms at once. So Meowth's chain claims Meowth becomes both
## Persian and Perrserker, when in truth Kanto's becomes one and Galar's the
## other. The two tables below split that apart.

## A form usually evolves into the same form of whatever its species evolves
## into — Alolan Rattata into Alolan Raticate, a small Pumpkaboo into a small
## Gourgeist — which needs no table, only a check that such a unit exists.
## These are the ones whose evolution is a species in its own right instead.
FORM_EVOLUTIONS = {
    "meowth-galar": "perrserker",
    "farfetchd-galar": "sirfetchd",
    "corsola-galar": "cursola",
    "linoone-galar": "obstagoon",
    "mr-mime-galar": "mr-rime",
    "yamask-galar": "runerigus",
    "qwilfish-hisui": "overqwil",
    "sneasel-hisui": "sneasler",
    "wooper-paldea": "clodsire",
    "basculin-white-striped": "basculegion",
    "darumaka-galar": "darmanitan-galar-standard",
    "gimmighoul-roaming": "gholdengo",
    "rockruff-own-tempo": "lycanroc-dusk",
}

## The other half of that fact: branches the API hangs off a species which only
## one of its forms can actually take. They move to the form, above.
FORM_ONLY_BRANCHES = {
    "meowth": {"perrserker"},
    "yamask": {"runerigus"},
    "sneasel": {"sneasler"},
    "wooper": {"clodsire"},
    "corsola": {"cursola"},
    "farfetchd": {"sirfetchd"},
    "linoone": {"obstagoon"},
    "mr-mime": {"mr-rime"},
    "qwilfish": {"overqwil"},
    "basculin": {"basculegion"},
}


def build_evolutions(cache: str, species_ids: list) -> dict:
    """species name -> list of branches it can evolve into."""
    chains = set()
    for dex in species_ids:
        species = load(cache, "pokemon-species", dex)
        if not species:
            continue
        url = (species.get("evolution_chain") or {}).get("url")
        if url:
            chains.add(int(url.rstrip("/").rsplit("/", 1)[-1]))
    out = {}
    for chain_id in sorted(chains):
        body = load(cache, "evolution-chain", chain_id)
        if body and body.get("chain"):
            walk_chain(body["chain"], out)
    return out


def drop_form_only_branches(chains: dict) -> None:
    """Take the form-only branches off the species, in place.

    Runs after add_form_evolutions, not before: the branch has to still be
    there for Galarian Yamask to copy Runerigus' real trigger off it.
    """
    for name, disowned in FORM_ONLY_BRANCHES.items():
        kept = [b for b in chains.get(name, []) if b["to"] not in disowned]
        if kept:
            chains[name] = kept
        else:
            chains.pop(name, None)


def branch_towards(branches: list, target: str) -> dict:
    """The species-level branch that a form's own evolution stands in for.

    Matches the target itself, or the species it is a form of — Galarian
    Darumaka's Darmanitan-Galar-Standard comes from Darumaka's Darmanitan — so
    the form keeps the real level and trigger instead of a made-up one.
    """
    for b in branches:
        if b["to"] == target or target.startswith(b["to"] + "-"):
            return b
    return branches[0] if branches else {"level": FALLBACK_EVO_LEVEL,
                                         "trigger": LEVEL_TRIGGER}


def add_form_evolutions(chains: dict, mons: list) -> None:
    """Give each form its own branches, in place. Chains stay species-keyed."""
    known = {m["name"] for m in mons}
    # FORM_EVOLUTIONS names species, and a species is not always a unit name:
    # Basculegion's default form is basculegion-male.
    default = {m["species"]: m["name"] for m in mons if m["id"] <= MAX_DEX}
    for mon in mons:
        name, form = mon["name"], mon["form"]
        if not form or name in chains:
            continue
        species_branches = chains.get(mon["species"], [])
        if name in FORM_EVOLUTIONS:
            target = FORM_EVOLUTIONS[name]
            target = default.get(target, target)
            if target not in known:
                continue
            source = branch_towards(species_branches, target)
            chains[name] = [{"to": target, "level": source["level"],
                             "trigger": source["trigger"]}]
            continue
        branches = [{"to": f"{b['to']}-{form}", "level": b["level"],
                     "trigger": b["trigger"]}
                    for b in species_branches
                    if f"{b['to']}-{form}" in known]
        if branches:
            chains[name] = branches


def name_evolutions_by_unit(chains: dict, mons: list) -> dict:
    """Rewrite species names in the chains to the unit names they stand for.

    Evolution chains talk in species — "darmanitan" — but a handful of species
    have a suffix on even their default form, and the game looks units up by
    name. So "darumaka evolves into darmanitan" has to become "... into
    darmanitan-standard", and Frillish's own chain has to be filed under
    frillish-male, or neither side of it resolves to anything.
    """
    unit_names = {m["name"] for m in mons}
    default = {m["species"]: m["name"] for m in mons if m["id"] <= MAX_DEX}
    out = {}
    # Species-keyed entries first, so that where both exist — Frillish's chain
    # and Frillish-Male's — the entry already written against the unit wins.
    for source in sorted(chains, key=lambda s: s in unit_names):
        key = source if source in unit_names else default.get(source, source)
        out[key] = [dict(b, to=default.get(b["to"], b["to"]))
                    for b in chains[source]]
    return out


def build_growth(cache: str) -> dict:
    """growth rate name -> total XP required at each level, index 0 = level 1."""
    index = load(cache, "", "growth-rate?limit=100")
    if not index:
        return {}
    out = {}
    for entry in index["results"]:
        body = load(cache, "growth-rate", entry["name"])
        if not body:
            continue
        table = [0] * 101
        for lvl in body.get("levels", []):
            n = int(lvl["level"])
            if 1 <= n <= 100:
                table[n] = int(lvl["experience"])
        out[entry["name"]] = table[1:]
    return out


def write_json(path: str, payload) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, separators=(",", ":"), sort_keys=False)
    size = os.path.getsize(path)
    print(f"  {path}  {size / 1024:.0f} KiB")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=".pokecache")
    ap.add_argument("--out", default="data")
    ap.add_argument("--limit", type=int, default=MAX_DEX)
    ap.add_argument("--no-forms", action="store_true",
                    help="species only; leave out megas, regionals and the rest")
    ap.add_argument("--no-cap", action="store_true",
                    help="leave out Smogon's CAP dex")
    args = ap.parse_args()

    cache = os.path.abspath(args.cache)
    if not os.path.isdir(cache):
        print(f"no cache at {cache} — run tools/fetch_pokeapi.py first", file=sys.stderr)
        return 1

    ids = cached_ids(cache, args.limit, not args.no_forms)

    # Only keep moves that something can actually learn, plus the three the API
    # lists in no learnset: Struggle, and the Celebrate and Hold Hands that CAP
    # units are given.
    wanted = {"struggle", "celebrate", "hold-hands"}
    for dex in ids:
        body = load(cache, "pokemon", dex)
        if body is None:
            continue
        for entry in body.get("moves", []):
            wanted.add(entry["move"]["name"])

    print("building")
    types = build_types(cache)
    moves = build_moves(cache, wanted)

    cap_data = {} if args.no_cap else cap.load(cache)
    if not args.no_cap and not cap_data.get("species"):
        print("  no Showdown mirror — run tools/fetch_showdown.py for the CAP dex",
              file=sys.stderr)
        cap_data = {}
    cap_moves = cap.build_moves(cap_data) if cap_data else []
    # Sorted by name as one list, so a move's row does not depend on where it
    # came from — the learnsets index into this by position.
    moves = sorted(moves + cap_moves, key=lambda m: m["name"])
    move_index = {m["name"]: i for i, m in enumerate(moves)}

    mons = build_pokemon(cache, ids, move_index)
    if not mons or not moves:
        print("cache is incomplete — nothing written", file=sys.stderr)
        return 1

    inherited = inherit_missing_learnsets(mons)

    species_ids = sorted({species_id_of(load(cache, "pokemon", d)) for d in ids})
    evolutions = build_evolutions(cache, species_ids)
    add_form_evolutions(evolutions, mons)
    drop_form_only_branches(evolutions)
    evolutions = name_evolutions_by_unit(evolutions, mons)

    if cap_data:
        # Showdown names moves without punctuation, so "aerialace" has to be
        # matched back to the "aerial-ace" row the learnsets index into.
        by_slug = {cap.slug(m["name"]): i for i, m in enumerate(moves)}
        mons += cap.build_species(cap_data, by_slug, method_code)
        evolutions.update(cap.build_evolutions(cap_data))

    growth = build_growth(cache)

    write_json(os.path.join(args.out, "types.json"), types)
    write_json(os.path.join(args.out, "moves.json"), moves)
    write_json(os.path.join(args.out, "pokemon.json"), mons)
    write_json(os.path.join(args.out, "evolution.json"),
               {"chains": evolutions, "growth": growth})

    learn_rows = sum(len(m["learnset"]) for m in mons)
    branches = sum(len(v) for v in evolutions.values())
    forms = sum(1 for m in mons if m["form"] and m["id"] < cap.CAP_ID_BASE)
    caps = sum(1 for m in mons if m["id"] >= cap.CAP_ID_BASE)
    print(f"  {len(mons)} pokemon "
          f"({len(mons) - forms - caps} species, {forms} forms, {caps} CAP), "
          f"{len(moves)} moves, {learn_rows} learnset rows")
    print(f"  {len(evolutions)} evolving units, {branches} branches, "
          f"{len(growth)} growth curves")
    print(f"  {inherited} forms took their species' learnset")
    return 0


if __name__ == "__main__":
    sys.exit(main())
