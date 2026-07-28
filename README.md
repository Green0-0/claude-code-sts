# Spire — a Slay the Spire implementation in Godot 4

A complete, playable deck-building roguelike: 2 characters, 157 cards, 45 enemies,
35 relics, 20 potions, 10 events and 3 acts of branching maps — with shops,
campfires, elites, bosses and save/continue.

Built and verified against **Godot 4.7** (any Godot 4.4+ should load it).

---

## Running it

```bash
godot --path .            # play
godot -e --path .         # open in the editor
```

The main scene is `scenes/Main.tscn`.

### Tests (no display needed)

```bash
godot --headless -- --rules-test   # 69 assertions on the combat maths
godot --headless -- --smoke        # one self-played run, prints a report
godot --headless -- --smoke-deep   # 8 runs, immortal player, full 3-act coverage
godot --headless -- --shots        # save one PNG per screen to user://shots
```

`--rules-test` pins down the numbers everything else rests on: damage scaling
order (Strength → Weak → Vulnerable → Flight), block absorption and overflow, HP
loss bypassing block, Artifact, status decay, poison, reshuffling, the hand limit,
cost modifiers, X-costs, upgrades and generated card text. It exits non-zero on
failure.

`--smoke-deep` is the integration test: it drives every screen, plays every room
type, buys from shops, resolves events and fights all three acts' bosses. The last
verified run: **8 complete 3-act clears, 221 combats, 4416 cards played, 44 of 45
enemies and 113 cards exercised, zero errors.**

---

## Controls

| Input | Action |
|---|---|
| Drag a card upward past the hand | Play it (drop it on an enemy for targeted cards) |
| Click a card, then click an enemy | Play a targeted card |
| Click a card (untargeted) | Play it |
| `1`–`9` | Select / play the Nth card in hand |
| `E` or `Space` | End turn |
| Hover an enemy | Card damage numbers update for that target |
| Click Draw / Discard / Exhaust | Inspect that pile |
| Click a potion (top bar) | Drink it — right-click discards it |
| `Esc` | Close the card picker |

---

## Architecture

The rules engine is completely separate from the UI. `Combat` never touches a node;
the UI listens to its signals. That is what makes the headless autoplay possible.

```
project.godot            autoload: Run -> scripts/core/RunState.gd
scenes/
  Main.tscn              every screen, the HUD, the card picker
  CardView.tscn          one card
  EnemyView.tscn         one enemy (health, block, intent, statuses)
scripts/core/            rules + data, no UI dependencies
  Statuses.gd            every buff/debuff definition
  CardLibrary.gd         every card, plus character definitions & starter decks
  EnemyLibrary.gd        every enemy, its moves and its AI
  EncounterLibrary.gd    which enemies appear per act and tier
  RelicLibrary.gd        relic definitions
  PotionLibrary.gd       potion definitions
  MapGen.gd              procedural act maps
  Card.gd                a card instance (upgrades, per-combat state, rules text)
  Actor.gd               combat state for the player or one enemy
  Combat.gd              the rules engine
  RunState.gd            run-level state, rewards, shops, events, save/load
scripts/ui/              screens; each one owns a node in Main.tscn
scripts/dev/AutoPlay.gd  headless self-play harness
```

### The effect system

Cards, enemy moves and potions all share one data format, so most content is pure
data with no code:

```gdscript
"bash": {
    "name": "Bash", "type": "attack", "cost": 2, "target": "enemy",
    "params": {"dmg": 8, "vuln": 2}, "up": {"dmg": 10, "vuln": 3},
    "text": "Deal {dmg} damage. Apply {vuln} Vulnerable.",
    "effects": [
        {"op": "damage", "amount": "dmg"},
        {"op": "status", "id": "vulnerable", "stacks": "vuln", "target": "enemy"},
    ],
}
```

* A numeric field may be an `int`, a **key of `params`** (resolved at play time),
  `"X"` for X-cost cards, or `"@key"` for a value rolled per enemy instance.
* `up` overrides `params` when the card is upgraded, and may also carry `cost`,
  `flags_add`, `no_exhaust`, `innate` or `target_all`.
* `text` is the single source of truth for rules text — `{dmg}` is substituted with
  the *live* number, so the card shows real damage after Strength, Weak, Vulnerable
  and Dexterity are applied to the enemy you are hovering.
* The ~19 cards with genuinely unique behaviour (Body Slam, Reaper, Fiend Fire,
  Feed, Limit Break, Catalyst, Malaise …) use `{"op": "special", "id": ...}` and are
  implemented in `Combat._special()`.

Effects resolve through a **queue** rather than a plain loop. That is what lets a
card stop mid-resolution to ask the player a question (Armaments' upgrade, Warcry's
put-back, Headbutt's retrieval, Dual Wield's copy, Exhume, every discard effect).
`Combat` raises `choice_requested`, the UI opens the card picker, and
`resolve_choice()` resumes the queue exactly where it stopped.

### What's modelled

**Combat**: energy, draw/hand/discard/exhaust piles with reshuffling, block,
targeting, X-costs, multi-hit, per-turn and per-combat counters, hand limit of 10,
`exhaust` / `ethereal` / `innate` / `unplayable` flags, status and curse cards
(Wound, Dazed, Burn, Slimed, Void, Regret, Doubt, Pain, Clumsy, Injury,
Ascender's Bane).

**Statuses** (53 visible, plus 8 internal bookkeeping flags): Strength, Dexterity,
Vulnerable, Weak, Frail, Poison, Regen,
Thorns, Metallicize, Plated Armor, Artifact, Ritual, Barricade, Demon Form,
Double Tap, Feel No Pain, Dark Embrace, Envenom, After Image, A Thousand Cuts,
Noxious Fumes, Infinite Blades, Juggernaut, Combust, Evolve, Fire Breathing,
Rupture, Corruption, Berserk, Brutality, Blur, Accuracy, Wraith Form, Mayhem,
Tools of the Trade, plus enemy-only powers (Curl Up, Angry, Spore Cloud, Flight,
Enrage, Mode Shift, Painful Stabs, Curiosity, Slow, Fading, Unawakened).

Damage order matches the original: `base + Strength → Weak (×0.75) → Vulnerable
(×1.5) → Flight (×0.5)`, flooring at each step, then Block absorbs, then Thorns
retaliates.

**Enemies** (45) with real move sets and per-enemy AI, including no-repeat rules,
telegraphed intents with live damage numbers, Gremlin Nob's Enrage, Lagavulin
sleeping behind Metallicize, the Guardian's Mode Shift, Hexaghost's 7-move cycle,
the Slime Boss splitting, Bronze Automaton spawning orbs and stunning itself after
Hyper Beam, the Awakened One's second life, Time Eater's Haste, Book of Stabbing,
Gremlin Leader's summons, healer/defender minions and fleeing Looters.

**Runs**: 3 acts × 15 rows of branching map (6 random walks, crossing edges pruned,
dead ends repaired so a path always exists), room-type constraints (no elites or
campfires in the first five rows, treasure on row 8, campfire before the boss),
rarity drift on card rewards, elite/boss relic rewards, 35 relics with real hooks,
20 potions, 10 events, a merchant with card removal, campfires, ascension levels,
and JSON save/continue.

Card pool: 74 Ironclad, 59 Silent, 13 Colorless, 5 status and 6 curse cards —
62 attacks, 61 skills and 24 powers.

---

## Design notes and deliberate simplifications

These are places where I chose a defensible approximation rather than the exact
original behaviour:

* **Slime Boss** splits when killed rather than at 50% HP; the halves spawn with
  half its max HP.
* **The Guardian's** Mode Shift threshold does not grow each time it triggers.
* **Snecko Eye** grants its extra draw but does not randomise card costs.
* **Corpse Explosion** deals the target's max HP (not its remaining poison) to the
  others.
* **Wraith Form** stands in for Intangible using large Dexterity that decays.
* Act 2 and 3 rosters are smaller than the original's, and each act has two or
  three bosses rather than the full set.
* Card rewards never offer a card already in that reward; the "bowl"/"bottle"
  relic family and card-transform events beyond Living Wall are not included.

## Extending it

Adding content usually means adding one dictionary entry:

* **A card** — add to `CardLibrary.CARDS`. It joins the reward, shop and
  random-card pools automatically based on `color` and `rarity`.
* **An enemy** — add to `EnemyLibrary.ENEMIES` with its moves, then add a branch to
  `choose_move()` and list it in an `EncounterLibrary` tier.
* **A relic** — add to `RelicLibrary.RELICS`, then hook it where it applies
  (`Combat._apply_combat_start_relics`, `_start_player_turn`, `_after_card_played`,
  `_on_victory`, …).
* **A potion** — add to `PotionLibrary.POTIONS`; it reuses the combat effect ops.
* **An event** — add to `RunState.EVENTS` and one branch in `apply_event_option()`.

After any content change, run `godot --headless -- --smoke-deep` and check the
report for errors.
