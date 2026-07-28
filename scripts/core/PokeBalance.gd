class_name PokeBalance
extends RefCounted

## Every conversion from Pokemon numbers to Spire numbers, in one place.
##
## PokeData is the raw import; nothing in it is tuned. This file is where base
## stats become HP pools, move power becomes card damage, and BST becomes an
## encounter probability. Retuning the game means editing the constants here,
## not refetching the API.

## The notional level the whole dungeon is fought at. It only appears in the
## damage formula, where it sets the overall scale: a Spire fight wants roughly
## 6-8 damage from an average 40-power move, which LEVEL 12 produces.
const LEVEL := 12

## Defence assumed when a card has to print a damage number with no target in
## sight (deck view, shop, card reward). Roughly an average base Defense.
const NEUTRAL_DEFENSE := 80

## A stat stage is +-50% per step in the games; stages are capped at +-6.
const MAX_STAGE := 6


# ═══════════════════════════════ Unit statistics ═════════════════════════════
## HP pool for an encountered Pokemon. Driven by base HP, with BST folded in so
## a frail-but-strong legendary is not made of paper.
static func mob_hp(mon: Dictionary) -> int:
	var base := int((mon.get("stats", {}) as Dictionary).get("hp", 50))
	var bst := int(mon.get("bst", 400))
	return max(6, int(round(base * 1.1 + bst * 0.05)))


## Elites and bosses take the same species and make it a wall, mirroring how the
## Spire scales a normal enemy into an act boss.
static func role_hp_multiplier(role: String) -> float:
	match role:
		"elite": return 1.35
		"boss": return 1.9
	return 1.0


## Act 1 is stocked around 300 BST (see BST_BANDS), and the encounter tables do
## not care who is playing. A species below that band would be permanently
## underlevelled: a wild-statted Magikarp has 43 HP and hits for 3 against two
## foes with 157 HP between them, which is not a fight, it is a formality.
##
## So the player is treated as a trained specimen rather than a wild one, and its
## whole stat line is scaled toward the band it has to face. At or above the band
## this does nothing at all — Bulbasaur gets 1.01x, Mewtwo exactly 1.0.
##
## This does not make the weakest species good. Magikarp is still far and away
## the hardest character in the game and will usually lose; it just gets to
## fight rather than be deleted on the first floor.
const TRAINED_BST := 320
const MAX_TRAINER_SCALE := 1.8


static func trainer_scale(mon: Dictionary) -> float:
	var bst := maxf(1.0, float(mon.get("bst", 400)))
	return clampf(float(TRAINED_BST) / bst, 1.0, MAX_TRAINER_SCALE)


## You are one Pokemon against a pack of two or three, every fight, for three
## acts. A player statted like a wild specimen loses that trade on maths alone —
## the encounter deals two or three times what it takes back. This is the
## counterweight, and it is why a player's HP is not simply mob_hp.
const PACK_SCALE := 1.5


## HP the player has when running this Pokemon. Flatter than mob_hp: a run has
## to survive three acts, so the spread between Shedinja and Blissey is
## compressed and everyone gets a floor.
static func player_hp(mon: Dictionary) -> int:
	var base := int((mon.get("stats", {}) as Dictionary).get("hp", 50))
	var bst := int(mon.get("bst", 400))
	var hp := int(round((base * 0.8 + bst * 0.06) * trainer_scale(mon) * PACK_SCALE)) + 15
	return max(30, hp)


## Energy per turn. Fast Pokemon get to do more each turn, which is the main
## way Speed pays off for the player.
static func energy_for(mon: Dictionary) -> int:
	var spe := int((mon.get("stats", {}) as Dictionary).get("spe", 60))
	if spe >= 110:
		return 4
	return 3


## Cards drawn per turn, again from Speed. Kept to 5-6 so hands stay readable.
static func draw_for(mon: Dictionary) -> int:
	var spe := int((mon.get("stats", {}) as Dictionary).get("spe", 60))
	return 6 if spe >= 90 else 5


## The offensive stat a move uses: Attack for physical, Sp. Atk for special.
static func offense_stat(mon_stats: Dictionary, damage_class: String) -> int:
	if damage_class == "special":
		return int(mon_stats.get("spa", 50))
	return int(mon_stats.get("atk", 50))


## The matching defensive stat on the receiving side.
static func defense_stat(mon_stats: Dictionary, damage_class: String) -> int:
	if damage_class == "special":
		return int(mon_stats.get("spd", 50))
	return int(mon_stats.get("df", 50))


## Multiplier for a stat stage, as in the games: +1 is x1.5, -1 is x0.66.
static func stage_multiplier(stage: int) -> float:
	var s := clampi(stage, -MAX_STAGE, MAX_STAGE)
	if s >= 0:
		return (2.0 + float(s)) / 2.0
	return 2.0 / (2.0 - float(s))


# ══════════════════════════════ Damage & defence ═════════════════════════════
## The main-series damage formula, scaled to Spire numbers by LEVEL.
##
##   ((2L/5 + 2) x power x Attack / Defense) / 50 + 2
##
## Type effectiveness, STAB and stat stages are applied by the caller so the
## combat log can explain each one separately.
static func base_damage(power: int, attack: int, defense: int) -> int:
	if power <= 0:
		return 0
	var lvl_factor := 2.0 * float(LEVEL) / 5.0 + 2.0
	var atk := maxf(1.0, float(attack))
	var def := maxf(1.0, float(defense))
	var raw := (lvl_factor * float(power) * atk / def) / 50.0 + 2.0
	return max(1, int(floor(raw)))


## Damage a move does, with every multiplier folded in. Returns at least 1
## unless the matchup is a true immunity, which returns 0.
static func move_damage(power: int, attack: int, defense: int, type_mult: float,
		stab: float, extra: float = 1.0) -> int:
	if power <= 0:
		return 0
	if type_mult <= 0.0:
		return 0
	var dmg := float(base_damage(power, attack, defense))
	dmg *= type_mult * stab * extra
	return max(1, int(floor(dmg)))


# ═════════════════════════════ Cards from moves ══════════════════════════════
## Energy cost. Power is the main driver; priority moves are cheaper because
## going first is their whole point, and a tiny PP pool means a big effect.
static func card_cost(mv: Dictionary) -> int:
	var power := int(mv.get("power", 0))
	var pp := int(mv.get("pp", 10))
	var prio := int(mv.get("prio", 0))
	var cls := String(mv.get("class", "status"))

	var cost := 1
	if cls == "status":
		# Status moves price off how much they do, not off damage.
		cost = 0 if pp >= 20 else 1
		if pp <= 5:
			cost = 2
	else:
		if power <= 0:
			cost = 1
		elif power <= 40:
			cost = 0
		elif power <= 75:
			cost = 1
		elif power <= 110:
			cost = 2
		else:
			cost = 3
	if prio > 0:
		cost = max(0, cost - 1)
	if prio < 0:
		cost += 1
	return clampi(cost, 0, 3)


## Rarity, which is what the reward screen weights by.
static func card_rarity(mv: Dictionary, learn_level: int, method: int) -> String:
	var power := int(mv.get("power", 0))
	if method == PokeData.LEARN_LEVEL and learn_level <= 1:
		return "basic"
	if power >= 110 or int(mv.get("pp", 10)) <= 5:
		return "rare"
	if power >= 75 or method == PokeData.LEARN_EGG or method == PokeData.LEARN_TUTOR:
		return "uncommon"
	return "common"


## Spire card type. Anything that deals damage is an Attack; a status move that
## only ever buffs the user is a Power, since it is a lasting effect.
static func card_type(mv: Dictionary) -> String:
	if String(mv.get("class", "status")) != "status":
		return "attack"
	var category := String(mv.get("category", ""))
	if category in ["net-good-stats", "field-effect", "whole-field-effect"]:
		return "power"
	return "skill"


# ══════════════════════════ Encounters, weighted by BST ══════════════════════
## Where each act and encounter kind sits on the BST curve: [centre, spread].
## An encounter's probability is a bell curve over BST around the centre, so a
## 300-BST Rattata is common in Act 1 and effectively absent from an Act 3 boss
## slot, and Dragonite is the other way round.
const BST_BANDS := {
	1: {"weak": [300, 70], "strong": [370, 80], "elite": [460, 70], "boss": [530, 60]},
	2: {"weak": [390, 80], "strong": [455, 80], "elite": [520, 70], "boss": [590, 60]},
	3: {"weak": [470, 80], "strong": [520, 80], "elite": [580, 60], "boss": [660, 60]},
}


static func band_for(act: int, kind: String) -> Array:
	var bands: Dictionary = BST_BANDS.get(clampi(act, 1, 3), BST_BANDS[1])
	return bands.get(kind, bands["weak"])


## Relative likelihood of meeting this species in this slot. A Gaussian on BST,
## which is what makes the encounter percentages "largely depend on BST".
static func encounter_weight(mon: Dictionary, act: int, kind: String) -> float:
	var band := band_for(act, kind)
	var centre := float(band[0])
	var spread := float(band[1])
	var bst := float(mon.get("bst", 400))
	var z := (bst - centre) / spread
	var w: float = exp(-0.5 * z * z)

	# Legendaries and mythicals are boss and late-elite material only. Without
	# this they would swamp the high-BST end of every Act 3 table.
	var exotic := bool(mon.get("legendary", false)) or bool(mon.get("mythical", false))
	if exotic:
		if kind == "boss":
			w *= 3.0
		elif kind == "elite" and act >= 3:
			w *= 0.5
		else:
			w = 0.0
	# Babies are always the weakest thing in the dungeon.
	if bool(mon.get("baby", false)) and kind != "weak":
		w *= 0.25
	return w


## How many of a species show up together. Weak species come in packs, which is
## both faithful and keeps low-BST encounters from being trivial.
static func group_size(mon: Dictionary, kind: String) -> int:
	if kind == "boss":
		return 1
	var bst := int(mon.get("bst", 400))
	if kind == "elite":
		return 2 if bst < 400 else 1
	if bst < 300:
		return 3
	if bst < 420:
		return 2
	return 1


## Tier label, used for the map and for pooling species by strength.
static func tier_of(bst: int) -> int:
	if bst < 330:
		return 1
	if bst < 450:
		return 2
	if bst < 540:
		return 3
	if bst < 600:
		return 4
	return 5
