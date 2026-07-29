# Spire — a Slay the Spire implementation in Godot 4

A complete, playable deck-building roguelike: 2 characters, 157 cards, 45 enemies,
35 relics, 20 potions, 10 events and 3 acts of branching maps — with shops,
campfires, elites, bosses and save/continue.

It also ships a second, parallel game built from imported PokeAPI data: all
**1433 Pokémon** are playable and encounterable — the 1025 numbered species, 326
alternate forms (Megas, Gigantamax, regional variants, Floette-Eternal) and the
82 units of Smogon's CAP dex — with real learnsets, the type chart, base stats
and status ailments. See [Pokémon mode](#pokémon-mode).

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
godot --headless -- --poke-test    # 386 assertions on the Pokémon layer
godot --headless -- --smoke        # one self-played run, prints a report
godot --headless -- --smoke-deep   # 8 runs, immortal player, full 3-act coverage
godot --headless -- --smoke-poke   # 8 self-played Pokémon runs
godot -- --click-test              # 44 assertions driven by synthesized clicks
godot --headless -- --shots        # save one PNG per screen to user://shots
```

`--click-test` needs a real display (the headless dummy display server does not do
mouse picking, so GUI hit-testing always misses). It synthesizes actual mouse and
key events instead of calling handlers, which is the only way to catch input-routing
and modal-dismissal bugs.

`--rules-test` pins down the numbers everything else rests on: damage scaling
order (Strength → Weak → Vulnerable → Flight), block absorption and overflow, HP
loss bypassing block, Artifact, status decay, poison, reshuffling, the hand limit,
cost modifiers, X-costs, upgrades and generated card text. It exits non-zero on
failure.

`--smoke-deep` is the integration test: it drives every screen, plays every room
type, buys from shops, resolves events and fights all three acts' bosses. The last
verified run: **8 complete 3-act clears, 185 combats, 3424 cards played, 43
enemies and 103 cards exercised, zero errors.**

`--smoke-poke` is the same harness playing Pokémon, rotating through a deliberate
spread (a frail starter, a wall, a glass cannon, a legendary, and the degenerate
learnsets — Abra, Magikarp, Ditto). Last verified run: **five complete four-act
clears, 238 combats, 4 evolutions, party reaching level 41, zero errors** —
including Magikarp, which used to die on the first floor and now evolves into
Gyarados and finishes the run.

One known hole: the eighth run (**Ditto**) does not terminate and the harness
stops on its step limit. Ditto learns nothing but Transform, so its deck falls
back to Struggle; paired with the harness's immortal player, a fight it cannot
win in reasonable time never ends. A mortal player would simply lose. It is a
harness artifact meeting the single most degenerate species, but it does mean the
run never completes.

**Run the suites one at a time.** Two of them fail spuriously against a busy
machine, in ways that look like real bugs:

* `--click-test` synthesizes mouse events, so a `--smoke-*` run in the background
  starves it and hit-testing misses. It also waits for the UI to stop being busy
  before each click (`_settle`) — under ATB the clock is pumped on a timer, so a
  click fired immediately after the previous one can land while the engine is
  still advancing and be swallowed. Without that wait the suite is flaky.
* `--poke-test` exercises save/continue, and every suite shares the one
  `user://spire_save.json`. A concurrent `--smoke-*` overwrites it mid-test.

---

## Controls

| Input | Action |
|---|---|
| Drag a card onto an enemy | Play it at that enemy |
| Drag a card onto a party panel | Play it at that team-mate |
| Drag a card upward past the hand | Play it at the default target |
| Click a card, then click an enemy | Play a targeted card |
| Click a card (untargeted) | Play it |
| `1`–`9` | Select / play the Nth card in hand |
| `C` | Engage Capture, then click the target |
| `E` or `Space` | End turn |
| Hover an enemy | Card damage numbers update for that target |
| Click Draw / Discard / Exhaust | Inspect that pile |
| Click a potion (top bar) | Drink it — right-click discards it |
| Hold, drag and flick the ball | Throw it — curve the drag to swerve it |
| `Esc` | Close the card picker, or cancel Capture |

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

## Pokémon mode

Pick **Pokémon ▸** on the title screen and search the dex by name, type or number.
Choosing a species starts a normal three-act run where you *are* that Pokémon: your
HP, Energy, draw and damage come from its base stats, your deck is its learnset, and
the dungeon is stocked with other Pokémon instead of gremlins. Ironclad and Silent
runs are untouched.

### Importing the data

The scripts under `tools/` are the whole pipeline. None of them run at play time —
the game only ever reads the four JSON files they produce.

```bash
python3 tools/fetch_pokeapi.py     # mirrors PokeAPI into .pokecache/ (~210 MB, cached)
python3 tools/fetch_showdown.py    # mirrors Smogon's data tables, for the CAP dex
python3 tools/build_data.py        # compacts both into data/*.json (2.0 MB, committed)
python3 tools/fetch_sprites.py     # 1433 sprites into assets/sprites/pokemon/
```

| File | Contents |
|---|---|
| `data/pokemon.json` | 1433 units: base stats, types, BST, weight, legendary flags, which species and form each is, and a **109 578-row learnset** (`[move, level, method]`) |
| `data/moves.json` | 839 moves: power, accuracy, PP, priority, damage class, ailment + chance, stat changes, drain/recoil, healing, multi-hit range, crit rate |
| `data/evolution.json` | 522 evolving units and the six XP curves |
| `data/types.json` | the full 18×18 effectiveness chart |

Both fetchers cache every response, so a re-run is free and deleting a cached
file is how you force a refetch. `build_data.py` keeps the data faithful — no
balancing lives in it, so the game can be retuned without touching the network.

**Alternate forms** are units in their own right, not decorations: a Mega has its
own stats, typing and art, and carries `species`/`form`/`battle_only` so the game
can tell what it is. PokeAPI keys evolution chains by species, which conflates a
species with its regional variants — its Meowth chain claims Kanto's Meowth
becomes Perrserker — so `build_data.py` splits those apart and gives each form
its own branches.

**The CAP dex** (Smogon's Create-A-Pokemon project) exists in no game, so it comes
from the Showdown simulator instead and is translated in `tools/cap.py`. Three of
its numbers — capture rate, growth curve, base experience — are single-player
values Showdown does not carry, and are estimated from how the real dex
distributes them. Its three invented moves (Paleo Wave, Shadow Strike, Polar
Flare) are hand-written into the PokeAPI move shape. CAP evolution levels are
seeded random rather than canonical: 10-20 for the first step of a three-stage
line, 30-40 otherwise.

### From Pokémon numbers to Spire numbers

Every conversion is in `PokeBalance.gd`, deliberately in one file:

* **Damage** is the main-series formula, `((2L/5+2) × power × Atk / Def) / 50 + 2`,
  at a notional level of 12 — which puts a 40-power move at about 6 damage, the
  same scale as a Strike. Type effectiveness, STAB (×1.5), stat stages, burn and
  criticals multiply on top, and the result is then passed through the Spire's own
  Strength/Weak/Vulnerable pipeline so relics still work.
* **HP** follows base HP with BST mixed in, so Blissey is a wall and Shedinja is
  paper. Elites get ×1.35 and bosses ×1.9.
* **Speed** buys tempo: ≥110 base Speed is a 4th Energy, ≥90 is a 6th card. It also
  sets initiative — anything faster than you attacks *before* your first turn, and
  the enemy phase runs fastest-first.
* **Defense / Sp. Def** are read by the damage formula, so a physical move into
  Alakazam lands much harder than a special one.
* **Cards** are priced by power (≤40 → 0 energy, ≤75 → 1, ≤110 → 2, above → 3),
  discounted for priority moves, and moves at 140+ power or 5 PP exhaust.
* **The player is a trained specimen**, not a wild one. Act 1 is stocked around
  300 BST regardless of who is playing, so a species below that band gets its
  stat line scaled toward it (`trainer_scale`, capped at 1.8×; Bulbasaur gets
  1.01×, Mewtwo exactly 1.0×). Without it a wild-statted Magikarp had 43 HP and
  hit for 3 against two foes with 157 HP between them.
* **You fight packs**, one Pokémon against two or three, every fight, for three
  acts — so player HP carries a flat `PACK_SCALE` on top. Without it the trade is
  lost on arithmetic alone, whoever you pick.

### Difficulty is not flat, by design

Because encounters are pinned to a fixed BST curve and your species is not, your
choice at the title screen *is* the difficulty setting. Mewtwo (680 BST) opens
with 141 HP and 131 damage a turn; Caterpie (195) opens with 93 HP and 12. The
picker shows BST, HP, Energy and the full stat line for exactly this reason.

The weakest handful — Magikarp, Caterpie, Metapod, Abra — will usually lose, and
that is left in rather than balanced away: it is what those species are. In the
last self-play run Bulbasaur, Snorlax, Alakazam, Mewtwo and Gyarados all cleared
three acts; Magikarp reached Act 2, and Abra and Ditto — the two with no usable
level-up moves at all — did not get far. What was fixed is the case where they
could not play at all. A wild Magikarp knows only
Tackle, and Tackle does *nothing* to a Ghost — the fight was unwinnable by rule,
not by difficulty. Now, as in the games, a Pokémon with no move that will land
resorts to **Struggle**, which is typeless and always connects. Enemies get the
same fallback, so no fight can stall forever.

### Levels, experience and evolution

Every combatant has a real level, and stats come from the main-series formula
(`floor((2·base + IV)·level/100) + level + 10` for HP, `+ 5` for the rest, with a
flat average IV of 15 and no EVs). That formula self-balances: HP and the
offensive stats grow together, so a fight at level 40 takes about as many turns
as one at level 8, which is what lets the dungeon level up alongside you.

* **Experience** uses each species' real growth curve — all six are imported, so
  a Slow-curve legendary genuinely takes longer than a Fast-curve Rattata. XP
  from a kill scales with the level felled and the role (×1.6 elite, ×2.5 boss).
* **Levelling** raises Max HP by the formula's difference and heals by the same
  amount, then checks for an evolution.
* **Evolution** comes from the imported chains — 457 evolving species, 484
  branches. Triggers a dungeon cannot reproduce (trade, stones, friendship,
  walking 10,000 steps) are folded onto level thresholds by `build_data.py`.
  Branching lines keep every branch and you pick: Eevee offers all eight.
  Evolving keeps your deck, swaps the stat line and typing, and widens the card
  pool — which is how a weak starter keeps up. Magikarp becomes Gyarados at 20.
* Declining an evolution is a real option, and the offer returns next level.

### Card rewards open up as you level

Rewards roll from what your Pokémon could plausibly know: level-up moves at or
below its level (plus a little slack), and machine/egg/tutor moves gated on an
*implied* level derived from their power — otherwise a level 5 Charmander could
be handed Fire Blast on the first floor and delete the act. Charmander's pool is
**19 moves at level 5 and 110 at level 60**, and widens again on evolution
because the evolved form's learnset counts too.

A small chance ignores the gate entirely and offers anything from the whole
learnset — **6% normally, 33% from an elite** — which is what makes elites worth
detouring for.

### Active Time Battle

Turn order is no longer an alternation. Every combatant has a charge gauge that
fills at a rate set by its **effective Speed** (base stat grown to level, times
Speed stage, quartered by paralysis); when a gauge fills, that combatant acts and
spends it, keeping any overflow. Order is emergent: over one fight a Jolteon acts
**15 times to a Slowpoke's 5**.

The engine is stepped by the UI rather than a real clock, so headless and played
runs resolve identically. Upkeep that used to happen in a batch at the end of an
enemy phase — Ritual, Metallicize, Regen, status decay, poison and ailment ticks
— is now per-actor at its own turn, so a fast enemy really does get its Ritual
strength twice as often as a slow one. The old pre-emptive-strike special case is
gone; being outsped is simply the gauge filling later. One guarantee remains: a
player who has not yet acted cannot be killed, so you always get your first turn.

### Encounters depend on BST

Nothing is hand-listed, and **nothing is ever excluded**. Every one of the 1433
species is in every encounter table; what changes is how likely each is. The
weight is a narrow bell curve over base stat total, centred on a band that climbs
with how far through the run you are, *plus* a much wider and shallower curve
underneath it. That tail is the point: it keeps a Dragonite in Act 1 possible —
rare spice rather than an arithmetic impossibility — and it is roughly 5% of
early encounters.

The band opens around **210 BST** for a normal encounter, the Caterpie and Rattata
end of the dex, and climbs on an eased curve to **680**. Measured, for a "strong"
slot:

| progress | band | rattata | caterpie | dragonite | mewtwo |
|---|---|---|---|---|---|
| start | 250 | 0.383% | 0.283% | 0.0034% | 0.0003% |
| middle | 414 | 0.018% | 0.005% | 0.0098% | 0.0003% |
| end | 700 | 0.016% | 0.011% | **1.069%** | **0.332%** |

Legendaries carry a flat rarity multiplier on top and an eightfold boost in boss
slots, so they are spice wherever they turn up and a real prospect as a late boss.

**Difficulty comes from which species the dungeon reaches for, not from bending
stats or spiking levels.** Enemy stats are never scaled down, and the role level
bonuses are deliberately tiny (+1 elite, +2 boss) — an elite is frightening
because the curve reached into its upper tail for something bigger, which is
legible, not because its level was shoved up, which is not.

Levels climb on the same progress: the dungeon fields level 5 on the first floor
and level 55 on the last, with elites +3 and bosses +6. A mob only knows moves
its level says it knows, so an Act 1 Deerling cannot open with the level-40
Double-Edge it eventually learns — and the same species met in Act 4 is genuinely
more dangerous rather than simply having more HP.

A Pokémon run is four acts rather than three, for a longer climb with room to
evolve twice. Ironclad and Silent keep their original three.

`PokeEncounters.probability(name, progress, kind)` returns the actual percentage,
and `top_candidates(progress, kind)` lists the likeliest — both are asserted on by
`--poke-test`.

### Move functionality

Moves are built from PokeAPI's structured `meta` fields, never by parsing English:
ailment and ailment chance, stat changes and their chance, drain and recoil,
healing, flinch chance, multi-hit ranges, crit rate, priority and accuracy. **654 of
798 moves** get real mechanical effects; the remainder (Metronome, Transform,
weather and terrain) have nothing this engine models and are excluded from decks
and reward pools rather than shipped as blank cards.

Computed-power moves, which PokeAPI reports with a null power, are implemented
explicitly: Low Kick and Grass Knot read the target's weight, Heavy Slam the weight
ratio, Electro Ball and Gyro Ball the Speed gap, Flail and Reversal the user's
remaining HP, Punishment the target's raised stages, Counter and Mirror Coat the
last hit taken, plus the fixed-damage family (Seismic Toss, Night Shade, Dragon
Rage, Sonic Boom, Psywave, Super Fang, Endeavor, Final Gambit) and the four OHKO
moves at their real 30% accuracy.

### Status effects

Ailments keep their series behaviour: **Burn** chips 1/16 max HP a turn and halves
physical damage dealt, **Paralysis** quarters Speed and costs Energy, **Sleep** and
**Freeze** cost the turn outright (Freeze with a 20% thaw check), **Confusion** has
a 33% chance to hurt the sufferer instead, **Flinch** eats one action, **Leech
Seed** moves HP across, **Trapped** chips 1/8 a turn, **Nightmare** only bites
while asleep, **Yawn** matures into Sleep, **Heal Block** stops healing and
**Embargo** seals potions. All seven **stat stages** are modelled at the real
±50%-per-step multipliers, capped at ±6, and Artifact can shrug off a drop.

### The party, and catching things

The player's side is a **party of up to four**. Each member is a full Pokémon in
its own right: its own species, level, experience, HP pool and **its own deck**.
`RunState` keeps the old single-character names (`character`, `deck`, `hp`,
`player_level`) as proxies onto the lead member, which is why rewards, shops,
events and the card picker all carried on working while the party grew
underneath them.

In combat every member is an Actor with its **own ATB gauge, own hand, own draw
and discard piles, and own energy**. Control passes to whoever charges first, and
`Combat.hand`/`energy` proxy through to whoever that is — so the hundred-odd
rules that say `hand` now mean "the acting member's hand" without being rewritten.
Losing a member does not lose the fight; the party fights on until all of them
are down.

**Experience is shared** with everyone still standing, Exp-Share style. A party
that levelled unevenly would stop being a party — the back two would fall off the
curve and never return.

**Cards can be aimed at team-mates.** Moves the games target at an ally (Helping
Hand, Heal Pulse, Aromatic Mist) become ally-targeted cards; clicking a party
panel throws the selected card at that member.

#### Layered hands

Every member's hand is on screen at once. The member whose gauge filled has its
fan at the front, full size and fully lit; the others sit behind it, progressively
smaller, pushed up and back, and shadowed down so they read as depth rather than
clutter. Only the acting member's cards are interactive — the rest are scenery you
can read but not misclick. When the ATB hands control over, the layers *re-sort*
rather than rebuild, so the swap is a movement.

### Capture

Capture is a **move you make in the middle of a fight**, not a prize handed out
after one. Any turn, against anything still standing, the Capture button puts the
cards down and takes you to the throwing screen. The throw costs you the turn —
win or lose — which is what makes reaching for a ball a decision instead of a free
look every round.

#### The bag is bought, not given

Bosses still hand over one ball each (Poké, Great, Ultra, Master). Everything else
is **bought from merchants**, out of a catalogue of 26 balls across four categories
and four rarities:

| Category | What they are |
|---|---|
| **Standard** | Poké, Great, Ultra, Master. Work on anything, cost accordingly. |
| **Specialist** | Net, Dive, Dusk, Quick, Timer, Nest, Repeat, Heal, Premier. Cheap, and enormous against the right target. |
| **Apricorn** | Fast, Level, Lure, Heavy, Love, Moon, Friend. Each reads one number straight off the dex page. |
| **Exotic** | Dream, Sport, Safari, Beast, Luxury, Cherish. Rare, strange, occasionally decisive. |

Most of them are **conditional**, and that is the point: a Net Ball is worth 3.5×
against a Water type and exactly 1× against a Fire one, a Fast Ball wants base
Speed 100+, a Heavy Ball wants 300 kg, a Moon Ball wants something that can still
evolve, a Quick Ball is worth five Ultra Balls on the opening turn and less than
a Poké Ball after it, and a Beast Ball is 5× on a legendary and 0.1× on anything
else. Stocking the bag is a bet on what you expect to meet. `PokeBalls.multiplier`
is the only place that judgement lives, and both the shop row and the throwing
screen read the live number off it, so what you are shown and what you roll cannot
drift apart.

The shelf drifts toward the better categories as the run goes on, so an Act 4
merchant is where a Beast Ball turns up rather than a fifth rack of Poké Balls.

#### Funding it: skipping rewards pays

Every reward you *could* take can be **turned down for a pinch of Gold** instead —
the card choice, the relic, the potion, even the boss's ball. Closing the card
picker counts as a skip and pays like one. The amounts scale with how deep the run
is, and they are deliberately enough to matter: a run that keeps skipping cards is
a run that **catches** its team rather than drafting it, and the two ways of
spending a victory are meant to compete.

#### The throw

The capture screen is a Pokémon Go throw, built out of the same vector drawing the
rest of the game uses — the ball is two half-discs, a band and a button.

* **Hold, drag, release.** The launch velocity comes off the last eighth of a
  second of the gesture, so a slow drag ending in a flick reads as a flick.
* **Swerve.** Spin is the accumulated *curvature* of the drag path — the signed
  area swept by consecutive segments. A straight flick has none; a hooked one
  curves in flight, and a curved throw is worth 1.35×. Swerving is something the
  hand does, not a button.
* **Depth.** The ball travels away from the camera as well as up, shrinking as it
  goes, with gravity easing off with distance so a good throw does not nose-dive.
* **Where it lands matters.** Three rings mark the scoring bands, drawn at exactly
  the ratios the maths uses: **Excellent** 1.85×, **Great** 1.45×, **Nice** 1.18×.
  Outside the outer ring is a miss and the ball is gone. A well-placed Great Ball
  beats a careless Ultra.

The ring rides *with* the target and scales with it, because it is that Pokémon's
sweet spot rather than a fixed hoop. Its size is the species' difficulty: a Rattata
gets a wide target, a legendary a narrow one. Some balls widen it — a Premier Ball
flies light and true, a Master Ball is nearly impossible to miss with.

The odds underneath are still the games' own formula, now with the throw folded in:

```
a = ((3·MaxHP − 2·HP) / 3·MaxHP) · captureRate · ballBonus · statusBonus
                                              · accuracyTier · curveBonus
chance = (a/255)^0.75          a ≥ 255 is a guaranteed catch
```

and the shakes are rolled the way the games roll them — four separate rolls at
`(a/255)^(3/16)`, stopping at the first failure — so a near miss really does rattle
three times before it pops open. There are critical captures too: one shake, and it
holds.

#### Resistance

**Resistance** is the mirror image of the catch rate, and it is what ties the
throwing screen back to the fight. Full health, no ailments, a rare species and a
level above your own all push it up; a nearly-fainted, sleeping Rattata is near the
floor. Everything that makes a catch likely makes resistance low.

It drives three things:

* **How the target moves** — see below.
* **How willing it is to dodge.** A furious legendary gets out of the way of most
  throws; something spent barely tries.
* **How long it puts up with you.** Patience runs from two throws for something
  furious to six for something spent, and a failed throw costs one. Run it out and
  it stops paying you any attention.

So wearing a target down is not an abstract percentage on a screen — it is visible
in how hard the thing is to hit. The fight before the throw *is* the capture.

#### Movement algorithms, one per type

Each of the 18 types has **its own movement algorithm**, written as weights over a
small set of primitives — sway, bob, parabolic leap, jolt, aerial swerve, orbit,
teleport, burrow, jitter — plus a dodge choreography. A few of them:

| Type | How it behaves |
|---|---|
| **Bug** | Jolts and leaps: fast, erratic, always half a body-length from where it was |
| **Flying** | Swerves aerially, wide unhurried figure-eights, banking as it turns |
| **Rock** | Holds nearly still, then shifts its whole weight at once |
| **Electric** | Zigzags almost too fast to follow, snapping to a new station three times a second |
| **Ghost** | Fades out and reappears elsewhere |
| **Ground** | Hunkers low and dips away underfoot |
| **Water** | Long, smooth, undulating waves |
| **Ice** | Glides, then stops dead |
| **Psychic** | Drifts in slow orbits, then blinks a body-length sideways |

A **dual type is the blend of two profiles**, weighted 62/38 toward the primary, so
a Bug/Flying genuinely jolts and leaps *and* swerves — and it says so on screen:
"Jolts and leaps, then swerves aerially." Both dodge styles survive the blend, and
it alternates between them, so a Beedrill does not only ever hop.

Resistance does not merely slow the motion down. Amplitudes shrink, leaps stop
clearing the ground, the phase begins to creep and stall so the movement *falters*
rather than playing back at half speed, breathing goes shallow and then heaves, and
a heavy species visibly sags. Sampling is a pure function of `(profile, time, seed,
resistance)` — no state, no RNG — so a paused screen resumes mid-stride and two of
the same species on screen are never in lockstep.

#### Coming and going

Engaging Capture zooms in on the enemy you clicked: the board darkens, the target
flies out of its slot in the enemy line and swells into the middle of the screen,
and the ring closes in around it from off-frame. A catch takes it out of the fight
without it being a *death* — nothing drops, no experience is banked, and nothing
that triggers on a kill fires. What you get instead is the Pokémon, joining a level
below the party (and higher still out of a Friend, Luxury or Cherish Ball) so it
arrives ready to fight rather than as a liability.

### Enemies play cards too

An enemy Pokémon is not a script any more. Each one spawns with a **deck built
from the moves its level says it knows** (two copies each, one of Struggle), its
own energy, and its own draw/hand/discard piles. On its ATB turn it refills
energy, draws back up to a hand, plays cards, then discards the rest and
reshuffles when the pile runs out — exactly the loop the player is in.

Its energy and its cards-per-turn are far below the player's, and deliberately
so: there are two or three of them to each of you, each on its own gauge, so a
player-sized enemy turn triples what an encounter puts out. Measured: with a
full turn each, runs died on the first act. One card a turn is what a single
scripted move used to be, which is the throughput the rest of the balance was
built against; elites get two and bosses three, so being able to combo is what
makes them frightening.

The card choice reuses the same scoring the scripted AI used, **including its
anti-repeat rule and its jitter**. That part is not cosmetic: without it an enemy
plays its single best attack every turn forever, which is both far more damaging
and far more monotonous than the AI it replaced. Leaving it out was worth roughly
three acts of difficulty.

An enemy also **picks its target** the way the player does. It weighs the type
matchup of the card it is actually holding, how close each of your party is to
falling, and leans toward whoever is holding the cards — but not so hard that the
back of the party is safe, which would make a party a shield rather than a team. A
move it points at itself or at a hurt team-mate flies the other way and reads as a
blessing on them rather than a hex on you.

The Spire's own 45 enemies have no decks and still resolve their one scripted
move, so that game is untouched.

### Cards do not queue behind each other

Playing a card used to lock the hand for the length of its animation. It does not
any more, and the split that made that possible is worth describing because it is
the load-bearing part of the whole thing.

`Combat.play_card` is now two halves:

* **`commit_card`** pays for the card and takes it out of the hand *immediately*.
  Nothing it does can be seen. Everything that depends on the state of the board is
  read here — Body Slam is worth the Block you had when you threw it.
* **`resolve_commit`** lands the effects, and the UI calls it on the frame the
  animation actually connects.

Because the energy is already spent and the hand is already correct, there is
nothing to wait for: the next card can be thrown into the same breath. Half a dozen
cards can be in the air at once, each striking on its own beat. Because the effects
still land on impact, the damage numbers and the blow arrive together rather than a
beat apart — a card that resolved on release would be unsatisfying, and one that
locked the hand would be slow.

A card **rises out of its own place in the fan**, not out of wherever the cursor let
go of it. A card taking off from mid-screen reads as something dropped; a card
taking off from the hand reads as something played.

The same applies to **enemies**. An enemy turn is staged — `enemy_turn_begin`,
`enemy_turn_next`, `enemy_turn_end` — so its AI commits one action at a time and the
UI launches each with a short stagger rather than waiting on it. A Pokémon spending
three cards throws three cards, overlapping, on separate beats. The turn is only
closed out once the last of them has landed, so end-of-turn upkeep never runs ahead
of the blows it is supposed to follow. `_take_enemy_turn` drives those same stages
straight through, which is what the headless harnesses use.

Two things still wait, and only two: **ending your turn** waits for the board to
settle, because an enemy must not begin its move while the last of yours is in the
air; and an enemy's own turn waits for its own cards. Both are bounded, so a lost
animation can never deadlock a fight.

#### Dropping a card on something

The drag gesture resolves **by geometry**, not by what the mouse last hovered. The
dragged card sits under the cursor for the whole drag, so leaning on `mouse_entered`
meant the enemy underneath never received one and the drop never found anything —
the line was drawn and then nothing happened. `_drop_at()` asks the board directly
what is beneath the release point: an enemy, a party panel, the acting member's own
panel, or open ground. The dragged card is also made transparent to the mouse so
the board underneath stays hoverable, which means the card can no longer report its
own mouse-up — so the release is caught in `_input`, which sees it first.

Positions come off the *event* rather than from the live cursor, which is what makes
the gesture testable: `--click-test` drags a Strike onto a Jaw Worm and asserts the
card left the hand, the energy was spent and the enemy took the hit.

### The look

Everything is drawn in code — the project ships no raster art of its own, so the
aesthetic has to come from geometry, colour and motion.

`Backdrop.gd` replaces the flat background fill with three cheap layers: a
vertical wash from plum through a warm horizon to near-black, so the screen has a
floor and a sky; slow-drifting motes in rose, violet, candlelight and witch-light,
each with its own drift and pulse so they never move as a sheet; and a vignette
that closes the corners in. Nothing in it reacts to gameplay, so it never
competes with the cards. Its RNG is fixed-seeded, so the backdrop is identical
every run.

Cards are painted by their move's own type — a yellow Thunder Shock, a red Double
Kick — with the type and damage class on the face, and the theme carries a
violet-tinted palette with generously rounded corners throughout, which is the
cheapest way to read as friendly rather than severe.

### Where it lives

```
tools/fetch_pokeapi.py   mirrors the API into .pokecache/
tools/fetch_showdown.py  mirrors Smogon's data tables, for the CAP dex
tools/showdown.py        reads Showdown's TypeScript tables as dicts
tools/cap.py             translates the CAP dex into the PokeAPI shape
tools/build_data.py      compacts the cache into data/*.json
tools/fetch_sprites.py   downloads and trims the artwork
scripts/core/
  PartyMember.gd         one Pokemon on the player's side, between fights
  PokeCapture.gd         catch rates, resistance, throw accuracy, the shake rolls
  PokeBalls.gd           the ball catalogue: categories, rarity, price, conditions
  PokeMotion.gd          one movement algorithm per type, blended for dual types
  PokeData.gd            loads data/, answers the type chart and evolution chains
  PokeBalance.gd         every Pokémon-number → Spire-number conversion
  PokeLevels.gd          the stat formula, XP curves and level maths
  PokeEvolution.gd       evolution branches, thresholds and whole-line lookups
  PokeMoves.gd           move → card definition, including computed power
  PokeMobs.gd            species → enemy definition, moveset and AI
  PokeCharacters.gd      species → playable character, deck and reward pool
  PokeEncounters.gd      BST-weighted encounter tables
scripts/ui/PokemonSelect.gd    searchable dex picker
scripts/ui/EvolutionScreen.gd  the evolution offer
scripts/ui/CaptureScreen.gd    the throwing screen: physics, rings, shakes
scripts/dev/PokeTest.gd       386 assertions over the whole layer
scripts/dev/Shot.gd           --poke-shots, one PNG per Pokémon-mode screen
```

The existing libraries delegate rather than branch everywhere: `CardLibrary`,
`EnemyLibrary` and `EncounterLibrary` each check for a Pokémon id and hand off, so
the Spire content and its tests are untouched.

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
* **A Pokémon move effect** — extend `PokeMoves._emit_*` (they read PokeAPI's
  `meta` fields) and add the matching op to `Combat._apply_effect`. Computed-power
  moves go in `PokeMoves.VARIABLE_POWER` / `FIXED_DAMAGE` plus a branch in
  `Combat._variable_power` / `_fixed_damage`.
* **Pokémon balance** — every conversion is a constant or a function in
  `PokeBalance.gd`; nothing needs refetching.
* **An enemy** — add to `EnemyLibrary.ENEMIES` with its moves, then add a branch to
  `choose_move()` and list it in an `EncounterLibrary` tier.
* **A relic** — add to `RelicLibrary.RELICS`, then hook it where it applies
  (`Combat._apply_combat_start_relics`, `_start_player_turn`, `_after_card_played`,
  `_on_victory`, …).
* **A potion** — add to `PotionLibrary.POTIONS`; it reuses the combat effect ops.
* **An event** — add to `RunState.EVENTS` and one branch in `apply_event_option()`.

After any content change, run `godot --headless -- --smoke-deep` and check the
report for errors.
