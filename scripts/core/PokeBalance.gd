class_name PokeBalance
extends RefCounted

## Every conversion from Pokemon numbers to Spire numbers, in one place.
##
## PokeData is the raw import; nothing in it is tuned. This file is where base
## stats become HP pools, move power becomes card damage, and BST becomes an
## encounter probability. Retuning the game means editing the constants here,
## not refetching the API.

## Level used when something has no level of its own — the Spire's own cast, and
## any card asked to print a damage number outside a fight.
const DEFAULT_LEVEL := 12

## Defence assumed when a card has to print a damage number with no target in
## sight (deck view, shop, card reward). Roughly an average base Defense.
const NEUTRAL_DEFENSE := 80

## A stat stage is +-50% per step in the games; stages are capped at +-6.
const MAX_STAGE := 6


# ═══════════════════════════════ Unit statistics ═════════════════════════════
## HP pool for an encountered Pokemon at a level. Straight off the main-series
## formula — the level does all the scaling, so the same species is a threat at
## 40 and a pushover at 8.
static func mob_hp(mon: Dictionary, level: int) -> int:
	var base := int((mon.get("stats", {}) as Dictionary).get("hp", 50))
	return max(6, PokeLevels.stat_at(base, level, true))


## Elites and bosses take the same species and make it a wall, mirroring how the
## Spire scales a normal enemy into an act boss.
static func role_hp_multiplier(role: String) -> float:
	match role:
		"elite": return 1.35
		"boss": return 1.9
	return 1.0


## A lone Pokemon against a pack of two or three loses the trade on arithmetic
## alone — a level 5 Bulbasaur has 28 unadjusted HP against 24 damage a round.
## Player HP therefore carries a counterweight, and that counterweight **shrinks
## as the party grows**, because a full party no longer needs it: four bodies
## against three is already a fair fight.
##
## Solo runs keep the full 2.6; a party of four drops to 1.4, which is the value
## the maths actually wants once both sides are fielding a team.
const PACK_SCALE_SOLO := 2.6
const PACK_SCALE_FULL := 1.4
const PACK_SCALE_AT := 4


static func pack_scale(party_size: int) -> float:
	var n := clampi(party_size, 1, PACK_SCALE_AT)
	var t := float(n - 1) / float(max(1, PACK_SCALE_AT - 1))
	return lerpf(PACK_SCALE_SOLO, PACK_SCALE_FULL, t)


## HP a party member has at a level.
##
## There is no longer any species-strength fudge here: a weak starter keeps up by
## levelling and evolving, and by the opponent BST cap starting low (see
## bst_cap). That is the design the balance rests on, rather than a multiplier
## that quietly made Magikarp less like Magikarp.
static func player_hp(mon: Dictionary, level: int, party_size: int = 1) -> int:
	var base := int((mon.get("stats", {}) as Dictionary).get("hp", 50))
	return max(20, int(round(PokeLevels.stat_at(base, level, true)
			* pack_scale(party_size))))


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
## The main-series damage formula, at the attacker's own level.
##
##   ((2L/5 + 2) x power x Attack / Defense) / 50 + 2
##
## Attack and Defense are the level-grown stats, so both sides of the ratio rise
## together and a fight takes about as many turns at level 40 as at level 8.
## Type effectiveness, STAB and stat stages are applied by the caller so the
## combat log can explain each one separately.
static func base_damage(power: int, attack: int, defense: int,
		level: int = DEFAULT_LEVEL) -> int:
	if power <= 0:
		return 0
	var lvl_factor := 2.0 * float(level) / 5.0 + 2.0
	var atk := maxf(1.0, float(attack))
	var def := maxf(1.0, float(defense))
	var raw := (lvl_factor * float(power) * atk / def) / 50.0 + 2.0
	return max(1, int(floor(raw)))


## Damage a move does, with every multiplier folded in. Returns at least 1
## unless the matchup is a true immunity, which returns 0.
static func move_damage(power: int, attack: int, defense: int, type_mult: float,
		stab: float, extra: float = 1.0, level: int = DEFAULT_LEVEL) -> int:
	if power <= 0:
		return 0
	if type_mult <= 0.0:
		return 0
	var dmg := float(base_damage(power, attack, defense, level))
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


## The level a move is treated as being learnable at.
##
## Level-up moves say so themselves. Machine, egg and tutor moves do not — in the
## games you can teach a level 5 Charmander Fire Blast the moment you own the TM,
## which in a dungeon would simply delete the first act. So their level is
## implied from how strong they are, which keeps the reward pool opening up as
## the run goes on rather than handing out its best cards immediately.
static func learn_level(mv: Dictionary, learn_level_from_data: int, method: int) -> int:
	if method == PokeData.LEARN_LEVEL:
		return learn_level_from_data
	var power := int(mv.get("power", 0))
	if power > 0:
		return clampi(int(round(power / 2.4)), 1, 60)
	# A status move with a tiny PP pool is a big effect; a 30-PP one is chaff.
	var pp := int(mv.get("pp", 10))
	if pp <= 5:
		return 34
	if pp <= 10:
		return 22
	return 8


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
## The BST the dungeon is willing to field, as a function of how far in you are.
##
## The run opens genuinely low — around 250, the Rattata and Caterpie end of the
## dex — so a player who picked a weak starter is not immediately outclassed, and
## climbs from there. By the end it is fielding wild legendaries. Progress is
## 0 at the first floor and 1 at the last, so the slope stretches automatically
## if the run length changes.
const BST_CAP_START := 250.0
const BST_CAP_END := 720.0

## How far above the running cap each encounter kind aims. Elites and bosses are
## the reason you meet something above your weight class.
const KIND_BST_OFFSET := {"weak": -40, "strong": 0, "elite": 60, "boss": 130}

## Width of the bell curve around the target. Wider early, so the opening floors
## stay varied rather than serving the same three species.
const BST_SPREAD := 70.0


## The strongest and weakest things that exist. Aiming a band outside this range
## would centre the bell curve on nothing, and every candidate would fall below
## the minimum weight — an empty table.
const BST_FLOOR := 190.0
const BST_CEILING := 700.0


## Target BST for a slot, given how far through the run it is (0-1).
static func bst_target(progress: float, kind: String) -> float:
	var t := clampf(progress, 0.0, 1.0)
	# Eased rather than linear: the early climb is gentle, the late one steep,
	# which is what makes the last act feel like it escalates.
	var curve := t * t * 0.6 + t * 0.4
	var cap := BST_CAP_START + (BST_CAP_END - BST_CAP_START) * curve
	return clampf(cap + float(KIND_BST_OFFSET.get(kind, 0)), BST_FLOOR, BST_CEILING)


## [centre, spread] for a slot. Kept in the shape the encounter tables expect.
static func band_for_progress(progress: float, kind: String) -> Array:
	return [bst_target(progress, kind), BST_SPREAD]


## How much of the weight lives in the long tail rather than the band.
##
## A bare Gaussian falls off so fast that anything three bands away is
## arithmetically impossible, which would mean the dungeon simply cannot show you
## a Dragonite in Act 1. The curve is therefore a narrow bell for the band plus a
## much wider, much shallower one underneath it: every species stays reachable at
## every point in the run, but far-off ones are rare spice rather than routine.
## Roughly 4-6% of early encounters come out of the tail.
const TAIL_WEIGHT := 0.02
const TAIL_SPREAD := 4.0

## Legendaries and mythicals are spice wherever they appear, not a wall. They get
## rarer the further from their band you are, like everything else, and this is
## on top of that — they are never routine, but they are never impossible either.
const EXOTIC_RARITY := 0.12


## Relative likelihood of meeting this species in this slot.
##
## This is the number the whole design turns on: difficulty comes from *which*
## species the dungeon reaches for, not from bending their stats or spiking their
## level. Early on the curve sits over the Caterpie end of the dex and a Dragonite
## is a shock; late on it sits over the legendaries and a Rattata is a curiosity.
static func encounter_weight(mon: Dictionary, progress: float, kind: String) -> float:
	var band := band_for_progress(progress, kind)
	var centre := float(band[0])
	var spread := float(band[1])
	var bst := float(mon.get("bst", 400))
	var z := (bst - centre) / spread

	# Narrow bell for the band, wide shallow one for the tail.
	var w: float = exp(-0.5 * z * z)
	var tz := z / TAIL_SPREAD
	w += TAIL_WEIGHT * exp(-0.5 * tz * tz)

	var exotic := bool(mon.get("legendary", false)) or bool(mon.get("mythical", false))
	if exotic:
		w *= EXOTIC_RARITY
		# A boss slot is where you are *meant* to meet one, once the band has
		# climbed far enough that it is not a random execution.
		if kind == "boss":
			w *= 8.0
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
