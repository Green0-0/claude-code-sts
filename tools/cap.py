#!/usr/bin/env python3
"""Convert Smogon's CAP project into the same records PokeAPI produces.

CAP — Create-A-Pokemon — is Smogon's community-designed dex. Its 82 units exist
only in the Showdown simulator, so their data arrives in a different shape to
everything else and has to be translated rather than copied.

Most of the translation is mechanical (metres to decimetres, `def` to `df`,
"9L33" to "learnt at level 33"). Three things genuinely are not in the source
and are estimated here, from how the real dex distributes them; each is marked
at its constant. And three moves — Paleo Wave, Shadow Strike, Polar Flare —
exist in no game at all, so they are hand-written into the PokeAPI move shape.

Used by build_data.py; not a command-line tool of its own.
"""

from __future__ import annotations

import random
import re

import showdown

## CAP dex numbers are negative. Everything below this belongs to Pokestar
## Studios — the Black 2 movie props — which are scenery, not units.
CAP_NUM_FLOOR = -1000

## Ids for the game data. PokeAPI uses 1-1025 for species and 10001+ for its
## alternate forms, so CAP sits above both, spaced so that a unit's id still
## reads as its CAP number: Syclant is -2, and so is 20020.
CAP_ID_BASE = 20000
CAP_ID_STRIDE = 10

## Move ids likewise sit clear of PokeAPI's, which stop in the 900s.
CAP_MOVE_ID_BASE = 9000

## Showdown's learn tags: "9L33" is level 33 in gen 9, "8M" a gen 8 TM. The
## letters name the same methods PokeAPI does; S is an event distribution,
## which has no equivalent and falls through to whatever build_data.py uses for
## a method it does not recognise.
LEARN_METHODS = {"L": "level-up", "M": "machine", "E": "egg", "T": "tutor"}

STAT_KEYS = {"hp": "hp", "atk": "atk", "def": "df",
             "spa": "spa", "spd": "spd", "spe": "spe"}

## ── The three estimates ──────────────────────────────────────────────────────
## Showdown carries no capture rate, growth curve or base experience: they are
## single-player numbers, and it only simulates battles. The values below are
## the medians of the real dex grouped the same way, so a CAP unit sits where a
## game species of its shape would rather than at some invented figure.
CAPTURE_RATE_EVOLVING = 140      # median over the 454 species that can evolve
CAPTURE_RATE_FINAL = 45          # median over the 571 that cannot
XP_RATIO_EVOLVING = 0.21         # base_experience / bst, species that evolve
XP_RATIO_FINAL = 0.35            # ... that do not
XP_RATIO_POWERFUL = 0.45         # ... and are bst 550+, where the curve steepens
POWERFUL_BST = 550

## Evolution levels, as the import was specified: a three-species line evolves
## first somewhere in EARLY, a two-species line at its only step somewhere in
## LATE. A three-species line's second step is unstated, so it takes LATE too —
## it is that line's last evolution, which is what LATE describes.
EARLY_EVO_RANGE = (10, 20)
LATE_EVO_RANGE = (30, 40)
EVO_SEED = "claude-code-sts/cap-evolution"


def slug(name: str) -> str:
    """Showdown's internal id for a name: lowercase, letters and digits only."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


def load(cache: str) -> dict:
    """The four Showdown tables, with the CAP species already sifted out."""
    dex = showdown.load_table(cache, "pokedex.ts")
    species = {k: v for k, v in dex.items()
               if isinstance(v.get("num"), int) and CAP_NUM_FLOOR < v["num"] < 0}
    return {
        "species": species,
        "moves": showdown.load_table(cache, "moves.ts"),
        "text": showdown.load_table(cache, "moves-text.ts"),
        "learnsets": showdown.load_table(cache, "learnsets.ts"),
    }


def _forme_order(entry: dict, species: dict) -> int:
    """Where a forme sits among the units sharing its CAP number."""
    if not entry.get("forme"):
        return 0
    siblings = sorted(k for k, v in species.items()
                      if v["num"] == entry["num"] and v.get("forme"))
    return 1 + siblings.index(slug(entry["name"]))


def unit_id(entry: dict, species: dict) -> int:
    return (CAP_ID_BASE + abs(entry["num"]) * CAP_ID_STRIDE
            + _forme_order(entry, species))


# ═════════════════════════════════ The moves ═════════════════════════════════
## Written by hand, because these three exist in no game and so have no PokeAPI
## record to mirror. The wording follows PokeAPI's short_effect register — "one
## stage" rather than "1 stage", and its curly apostrophe — so that a CAP card
## reads like every other card.
CAP_MOVE_EFFECTS = {
    "paleo-wave": "Has a 20% chance to lower the target’s Attack by one stage.",
    "shadow-strike": "Has a 50% chance to lower the target’s Defense by one stage.",
    # Showdown's own description ends with Ramnarok's forme change, which is a
    # battle behaviour we do not model; the damage and the freeze are the parts
    # that survive the port, so only those are described.
    "polar-flare": "Has a 10% chance to freeze the target. "
                   "Cannot thaw a frozen target.",
}

## Showdown targets -> PokeAPI targets. Only the ones CAP moves actually use.
TARGETS = {
    "normal": "selected-pokemon",
    "self": "user",
    "adjacentAlly": "ally",
    "adjacentAllyOrSelf": "user-or-ally",
    "adjacentFoe": "selected-pokemon",
    "allAdjacentFoes": "all-opponents",
    "allAdjacent": "all-other-pokemon",
    "all": "entire-field",
    "allySide": "users-field",
    "foeSide": "opponents-field",
    "allyTeam": "user-and-allies",
    "randomNormal": "random-opponent",
    "scripted": "specific-move",
    "any": "selected-pokemon",
}

## Showdown status codes -> PokeAPI ailment names.
AILMENTS = {"brn": "burn", "par": "paralysis", "psn": "poison",
            "tox": "poison", "slp": "sleep", "frz": "freeze"}


def _stat_changes(boosts: dict) -> list:
    return [{"stat": STAT_KEYS.get(k, k), "change": v} for k, v in boosts.items()]


def build_moves(data: dict) -> list:
    """The CAP-only moves, as records shaped exactly like build_moves' output."""
    out = []
    for key, body in sorted(data["moves"].items()):
        if body.get("isNonstandard") != "CAP":
            continue
        name = re.sub(r"[^a-z0-9]+", "-", body["name"].lower()).strip("-")
        secondary = body.get("secondary") or {}
        boosts = secondary.get("boosts") or {}
        status = secondary.get("status") or body.get("status") or ""
        chance = int(secondary.get("chance") or 0)
        ailment = AILMENTS.get(status, "none")

        if boosts:
            category = "damage-lower" if min(boosts.values()) < 0 else "damage-raise"
        elif ailment != "none":
            category = "damage-ailment"
        else:
            category = "damage"

        text = data["text"].get(key, {})
        out.append({
            "name": name,
            "id": CAP_MOVE_ID_BASE + abs(int(body["num"])),
            "power": int(body.get("basePower") or 0),
            # Showdown writes `accuracy: true` for a move that cannot miss;
            # PokeAPI writes null, which build_data.py stores as 0.
            "acc": 0 if body.get("accuracy") is True else int(body.get("accuracy") or 0),
            "pp": int(body.get("pp") or 5),
            "prio": int(body.get("priority") or 0),
            "type": body["type"].lower(),
            "class": body["category"].lower(),
            "target": TARGETS.get(body.get("target", "normal"), "selected-pokemon"),
            "ailment": ailment,
            "ailment_chance": chance if ailment != "none" else 0,
            "category": category,
            "crit_rate": max(0, int(body.get("critRatio") or 1) - 1),
            "drain": 0,
            "healing": 0,
            "flinch_chance": chance if secondary.get("volatileStatus") == "flinch" else 0,
            "stat_chance": chance if boosts else 0,
            "min_hits": 0,
            "max_hits": 0,
            "min_turns": 0,
            "max_turns": 0,
            "effect_chance": chance,
            "stat_changes": _stat_changes(boosts),
            "effect": CAP_MOVE_EFFECTS.get(name) or text.get("desc")
                      or text.get("shortDesc", ""),
        })
    return out


# ════════════════════════════════ The species ════════════════════════════════
def _line(entry: dict, species: dict) -> list:
    """Every stage of the evolution line this unit belongs to, first to last."""
    by_name = {slug(v["name"]): v for v in species.values()}
    root, climbed = entry, {slug(entry["name"])}
    while root.get("prevo"):
        prev = by_name.get(slug(root["prevo"]))
        if prev is None or slug(prev["name"]) in climbed:
            break
        root = prev
        climbed.add(slug(root["name"]))
    chain, walked = [root], {slug(root["name"])}
    node = root
    while node.get("evos"):
        nxt = by_name.get(slug(node["evos"][0]))
        if nxt is None or slug(nxt["name"]) in walked:
            break
        chain.append(nxt)
        walked.add(slug(nxt["name"]))
        node = nxt
    return chain


def _learnset(key: str, entry: dict, data: dict, move_index: dict,
              method_code) -> list:
    """Showdown's per-generation learn tags, flattened to [move, level, method].

    Same rule as the PokeAPI side: when a move is learnt differently in several
    generations, the most recent one wins. Where one generation offers a move
    both ways — Avalanche is a Syclant TM *and* a level 33 move — the level
    wins, because "learnt at 33" is the fact the game levels a party on and a
    TM entry would throw it away.
    """
    table = data["learnsets"].get(key)
    if table is None and entry.get("baseSpecies"):
        # Formes carry no learnset; they know what they change out of.
        table = data["learnsets"].get(slug(entry["baseSpecies"]))
    entries = (table or {}).get("learnset", {})

    rows = []
    for move_id, marks in entries.items():
        idx = move_index.get(move_id)
        if idx is None:
            continue
        best = None
        for mark in marks:
            m = re.match(r"(\d+)([A-Z])(\d*)", mark)
            if not m:
                continue
            gen, letter, level = int(m.group(1)), m.group(2), m.group(3)
            rank = (gen, letter == "L")
            if best is None or rank > best[0]:
                best = (rank, letter, int(level) if level else 0)
        if best is None:
            continue
        _, letter, level = best
        method = LEARN_METHODS.get(letter, "")
        rows.append([idx, level if method == "level-up" else 0,
                     method_code(method)])
    rows.sort(key=lambda r: (r[2], r[1], r[0]))
    return rows


def build_species(data: dict, move_index: dict, method_code) -> list:
    """CAP units as pokemon.json records.

    move_index maps a Showdown move id ("aerialace") to its row in moves.json;
    method_code turns a learn method name into the integer the learnsets use,
    so that build_data.py stays the one place those codes are defined.
    """
    species = data["species"]
    out = []
    for key, entry in sorted(species.items(), key=lambda kv: (-kv[1]["num"], kv[0])):
        stats = {STAT_KEYS[k]: int(v) for k, v in entry["baseStats"].items()}
        bst = sum(stats.values())
        evolves = bool(entry.get("evos"))
        out.append({
            "id": unit_id(entry, species),
            "name": re.sub(r"[^a-z0-9]+", "-", entry["name"].lower()).strip("-"),
            "species": str(entry.get("baseSpecies", entry["name"])).lower(),
            "form": str(entry.get("forme", "")).lower(),
            # Crucibelle-Mega, Venomicon-Epilogue and Ramnarok-Radiant are all
            # reached mid-battle, by a held item or by using Polar Flare.
            "battle_only": bool(entry.get("battleOnly") or entry.get("requiredItem")
                                or entry.get("requiredMove")),
            "types": [t.lower() for t in entry["types"]],
            "stats": stats,
            "bst": bst,
            # Showdown measures in metres and kilograms, PokeAPI in decimetres
            # and hectograms.
            "height": max(1, round(float(entry.get("heightm") or 0) * 10)),
            "weight": max(1, round(float(entry.get("weightkg") or 0) * 10)),
            # No CAP unit is a game legendary, mythical or baby; those flags
            # gate encounter tiering and rightly stay off.
            "legendary": False,
            "mythical": False,
            "baby": False,
            "capture_rate": CAPTURE_RATE_EVOLVING if evolves else CAPTURE_RATE_FINAL,
            "color": str(entry.get("color", "gray")).lower(),
            # CAP has no Pokedex category; the card falls back to "Pokemon".
            "genus": "",
            # The XP curve belongs to the species, not the forme, so a Mega
            # levels on the same curve as what it Mega Evolves from.
            "growth": _growth_rate(_base_of(entry, species)),
            "base_xp": _base_xp(bst, evolves),
            "learnset": _learnset(key, entry, data, move_index, method_code),
        })
    return out


def _base_of(entry: dict, species: dict) -> dict:
    """The species entry a forme belongs to, or the entry itself."""
    if not entry.get("baseSpecies"):
        return entry
    return species.get(slug(entry["baseSpecies"]), entry)


def _growth_rate(entry: dict) -> str:
    if entry.get("prevo") or entry.get("evos"):
        return "medium-slow"          # what most game evolution lines use
    bst = sum(entry["baseStats"].values())
    return "slow" if bst >= POWERFUL_BST else "medium"


def _base_xp(bst: int, evolves: bool) -> int:
    if evolves:
        ratio = XP_RATIO_EVOLVING
    elif bst >= POWERFUL_BST:
        ratio = XP_RATIO_POWERFUL
    else:
        ratio = XP_RATIO_FINAL
    return round(bst * ratio)


# ══════════════════════════════ The evolutions ═══════════════════════════════
def build_evolutions(data: dict) -> dict:
    """{species: [{to, level, trigger}]}, at the levels the import asked for.

    The level is random within its band but seeded off the species name, so a
    rebuild produces the same dex rather than silently reshuffling every line.
    """
    species = data["species"]
    by_name = {slug(v["name"]): v for v in species.values()}
    out = {}
    for entry in species.values():
        if not entry.get("evos"):
            continue
        chain = _line(entry, species)
        position = [slug(c["name"]) for c in chain].index(slug(entry["name"]))
        # First step of a three-stage line is the early one; every other step
        # is the line's last, and lands late.
        early = len(chain) >= 3 and position == 0
        low, high = EARLY_EVO_RANGE if early else LATE_EVO_RANGE
        rng = random.Random(f"{EVO_SEED}:{slug(entry['name'])}")
        level = rng.randint(low, high)
        branches = []
        for target in entry["evos"]:
            node = by_name.get(slug(target))
            if node is None:
                continue
            branches.append({
                "to": re.sub(r"[^a-z0-9]+", "-", node["name"].lower()).strip("-"),
                "level": level,
                "trigger": "level-up",
            })
        if branches:
            out[re.sub(r"[^a-z0-9]+", "-", entry["name"].lower()).strip("-")] = branches
    return out
