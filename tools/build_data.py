#!/usr/bin/env python3
"""Turn the PokeAPI cache into the three data files the game loads.

The output stays a faithful, compact mirror of the API: base stats, the type
chart, move mechanics, learnsets. None of the Slay-the-Spire balancing lives
here — that mapping is PokeBalance.gd, so it can be retuned without a refetch.

    python3 tools/build_data.py [--cache DIR] [--out DIR]

Writes data/types.json, data/moves.json, data/pokemon.json.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

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


def build_pokemon(cache: str, limit: int, move_index: dict) -> list:
    out = []
    for dex in range(1, limit + 1):
        body = load(cache, "pokemon", dex)
        if body is None:
            continue
        species = load(cache, "pokemon-species", dex) or {}
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


def build_evolutions(cache: str, limit: int) -> dict:
    """species name -> list of branches it can evolve into."""
    chains = set()
    for dex in range(1, limit + 1):
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
    ap.add_argument("--limit", type=int, default=1025)
    args = ap.parse_args()

    cache = os.path.abspath(args.cache)
    if not os.path.isdir(cache):
        print(f"no cache at {cache} — run tools/fetch_pokeapi.py first", file=sys.stderr)
        return 1

    # Only keep moves that something can actually learn, plus Struggle, which
    # appears in no learnset but is every Pokemon's last resort.
    wanted = {"struggle"}
    for dex in range(1, args.limit + 1):
        body = load(cache, "pokemon", dex)
        if body is None:
            continue
        for entry in body.get("moves", []):
            wanted.add(entry["move"]["name"])

    print("building")
    types = build_types(cache)
    moves = build_moves(cache, wanted)
    move_index = {m["name"]: i for i, m in enumerate(moves)}
    mons = build_pokemon(cache, args.limit, move_index)

    if not mons or not moves:
        print("cache is incomplete — nothing written", file=sys.stderr)
        return 1

    evolutions = build_evolutions(cache, args.limit)
    growth = build_growth(cache)

    write_json(os.path.join(args.out, "types.json"), types)
    write_json(os.path.join(args.out, "moves.json"), moves)
    write_json(os.path.join(args.out, "pokemon.json"), mons)
    write_json(os.path.join(args.out, "evolution.json"),
               {"chains": evolutions, "growth": growth})

    learn_rows = sum(len(m["learnset"]) for m in mons)
    branches = sum(len(v) for v in evolutions.values())
    print(f"  {len(mons)} pokemon, {len(moves)} moves, {learn_rows} learnset rows")
    print(f"  {len(evolutions)} evolving species, {branches} branches, "
          f"{len(growth)} growth curves")
    return 0


if __name__ == "__main__":
    sys.exit(main())
