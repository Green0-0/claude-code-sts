class_name PokeLevels
extends RefCounted

## Levels, stats and experience.
##
## This replaces the flat notional level the dungeon used to be fought at. Every
## combatant now has a real level, and its stats come from the main-series
## formula, so a level 8 Rattata and a level 40 Rattata are genuinely different
## animals rather than the same numbers with a multiplier on top.
##
## The formula also self-balances: HP and the offensive stats grow together, so a
## fight at level 40 takes about as many turns as one at level 8. That is what
## lets the dungeon level up with the player without the maths drifting.

const MIN_LEVEL := 1
const MAX_LEVEL := 100

## The level a run starts at. Low enough that the first evolutions (16-20) land
## inside the run rather than after it.
const START_LEVEL := 5

## Nothing in the games has perfect stats, and a flat 15 across the board is the
## conventional "average" stand-in for individual values.
const AVERAGE_IV := 15

## How far ahead of the dungeon's level each encounter role is.
##
## Deliberately small. An elite and a boss are supposed to be frightening because
## of *what* they are — a higher-BST species out of the encounter curve's upper
## tail — not because their level was shoved up. Spiking levels is the blunt way
## to make a fight hard and it makes the curve feel arbitrary; letting the BST
## band do the work keeps it legible.
const ROLE_LEVEL_BONUS := {"normal": 0, "elite": 1, "boss": 2}


static func role_level(base_level: int, role: String) -> int:
	return clampi(base_level + int(ROLE_LEVEL_BONUS.get(role, 0)), MIN_LEVEL, MAX_LEVEL)


## Main-series stat formula, without EVs and with an average IV.
##   HP     = floor((2*base + IV) * level / 100) + level + 10
##   others = floor((2*base + IV) * level / 100) + 5
static func stat_at(base: int, level: int, is_hp: bool = false) -> int:
	var lvl := clampi(level, MIN_LEVEL, MAX_LEVEL)
	var core := int(floor(float(2 * base + AVERAGE_IV) * float(lvl) / 100.0))
	if is_hp:
		# Shedinja is the one species that famously ignores this.
		if base <= 1:
			return 1
		return core + lvl + 10
	return core + 5


## Every stat of a species at a level, as the same {hp, atk, df, spa, spd, spe}
## dictionary shape the base stats use.
static func stats_at(mon: Dictionary, level: int) -> Dictionary:
	var base: Dictionary = mon.get("stats", {})
	var out := {}
	for key in ["hp", "atk", "df", "spa", "spd", "spe"]:
		out[key] = stat_at(int(base.get(key, 50)), level, key == "hp")
	return out


# ═════════════════════════════════ Experience ════════════════════════════════
## Total XP required to have reached this level on a species' growth curve.
static func xp_for_level(growth: String, level: int) -> int:
	var table := PokeData.xp_table(growth)
	if table.is_empty():
		return 0
	var idx := clampi(level, MIN_LEVEL, MAX_LEVEL) - 1
	return int(table[mini(idx, table.size() - 1)])


## The level a given total XP corresponds to.
static func level_for_xp(growth: String, xp: int) -> int:
	var table := PokeData.xp_table(growth)
	if table.is_empty():
		return START_LEVEL
	var level := MIN_LEVEL
	for i in range(table.size()):
		if xp >= int(table[i]):
			level = i + 1
		else:
			break
	return clampi(level, MIN_LEVEL, MAX_LEVEL)


## How far through the current level a total XP figure sits, 0-1. Drives the
## experience bar.
static func level_progress(growth: String, xp: int) -> float:
	var level := level_for_xp(growth, xp)
	if level >= MAX_LEVEL:
		return 1.0
	var here := xp_for_level(growth, level)
	var next := xp_for_level(growth, level + 1)
	if next <= here:
		return 1.0
	return clampf(float(xp - here) / float(next - here), 0.0, 1.0)


## XP awarded for defeating one Pokemon, following the shape of the games'
## formula: worth more the higher level it was and the rarer the species.
static func xp_reward(mon: Dictionary, level: int, role: String = "normal") -> int:
	var base := int(mon.get("base_xp", 60))
	var gain := int(round(float(base * level) / 5.0))
	match role:
		"elite": gain = int(round(gain * 1.6))
		"boss": gain = int(round(gain * 2.5))
	return max(1, gain)
