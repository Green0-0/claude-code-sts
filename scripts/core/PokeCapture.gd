class_name PokeCapture
extends RefCounted

## Catching a Pokemon, using the games' own formula and the imported capture
## rates.
##
## Captures happen mid-fight now: any turn, you can put the cards down, pick a
## ball out of the bag and throw it at something still standing. The odds are the
## real ones — a species' capture rate, how hurt it is, what it is suffering from,
## and the ball's multiplier, which for most balls depends on the target in front
## of you (see PokeBalls).
##
## Two things layer on top of the games' maths, and both come from the throw
## itself rather than the sheet:
##
##   accuracy   how near the middle of the target the ball landed
##   curve      whether it was thrown with a swerve on it
##
## and one thing works against it: Resistance, which is roughly the inverse of
## the catch rate — high HP, no ailments, a rare species, a level above yours.
## Resistance is also what drives how the thing moves while you are aiming at it
## (see PokeMotion), so wearing a target down is visible in the fight rather than
## only in a percentage.

## Ball catch-rate multipliers now live with the balls themselves. Kept here as a
## pass-through so nothing that already asked PokeCapture has to be rewritten.
static func ball_def(ball: String) -> Dictionary:
	return PokeBalls.get_def(ball)


static func ball_for_boss(bosses_slain: int) -> String:
	return PokeBalls.ball_for_boss(bosses_slain)


## The games' modified catch rate:
##
##   a = ((3·MaxHP − 2·CurrentHP) / (3·MaxHP)) · captureRate · ballBonus · statusBonus
##
## `a` at or above 255 is a guaranteed catch. Status ailments help, as they do in
## the games: sleep and freeze most, the rest less.
static func catch_value(mon: Dictionary, ball: String, hp: int, max_hp: int,
		status_bonus: float = 1.0, ball_mult: float = -1.0) -> float:
	var rate := float(mon.get("capture_rate", 45))
	var top := maxf(1.0, float(max_hp))
	var cur := clampf(float(hp), 1.0, top)
	var health_term := (3.0 * top - 2.0 * cur) / (3.0 * top)
	# A caller that has already worked out the ball's contextual multiplier passes
	# it in; anyone who just names a ball gets its unconditional one.
	var mult := ball_mult if ball_mult >= 0.0 else float(ball_def(ball).get("mult", 1.0))
	return health_term * rate * mult * status_bonus


## Probability the ball holds, 0-1.
##
## The games shake the ball four times, each with probability
## b = 65536 / (255/a)^0.1875; the catch is all four succeeding, which works out
## to (a/255)^0.75.
static func catch_chance(mon: Dictionary, ball: String, hp: int, max_hp: int,
		status_bonus: float = 1.0, ball_mult: float = -1.0) -> float:
	var a := catch_value(mon, ball, hp, max_hp, status_bonus, ball_mult)
	return chance_from_value(a)


static func chance_from_value(a: float) -> float:
	if a >= 255.0:
		return 1.0
	if a <= 0.0:
		return 0.0
	return clampf(pow(a / 255.0, 0.75), 0.0, 1.0)


## Status multiplier for whatever the target is suffering, as in the games.
static func status_bonus_for(statuses: Dictionary) -> float:
	if statuses.has("sleep") or statuses.has("freeze"):
		return 2.5
	for id in ["paralysis", "poison", "burn"]:
		if statuses.has(id):
			return 1.5
	return 1.0


## The level a caught Pokemon joins at. It arrives ready to fight rather than as
## a level 5 liability that can never catch up — being handed a team-mate you
## cannot use is not a reward.
static func joining_level(party_level: int) -> int:
	return clampi(party_level - 1, PokeLevels.MIN_LEVEL, PokeLevels.MAX_LEVEL)


## A one-line summary of the odds, for the capture screen.
static func describe_odds(chance: float) -> String:
	var pct := chance * 100.0
	if pct >= 99.5:
		return "certain"
	if pct >= 75.0:
		return "likely (%.0f%%)" % pct
	if pct >= 40.0:
		return "even-ish (%.0f%%)" % pct
	if pct >= 15.0:
		return "unlikely (%.0f%%)" % pct
	if pct >= 1.0:
		return "a long shot (%.0f%%)" % pct
	return "almost hopeless (%.1f%%)" % pct


# ═════════════════════════════════ Resistance ════════════════════════════════
## How hard this thing is still fighting you, 0-1.
##
## Deliberately built as the mirror image of the catch rate: everything that
## makes a catch likely makes resistance low. Full health, no ailments, a rare
## species and a level above your own all push it up; a nearly-fainted, sleeping
## Rattata is near the floor.
##
## The capture screen reads this for its movement (PokeMotion), for how willing
## the target is to dodge, and for how quickly it gives up on you.
static func resistance(mon: Dictionary, hp: int, max_hp: int, statuses: Dictionary,
		level: int = 1, party_level: int = 1) -> float:
	var top := maxf(1.0, float(max_hp))
	var health := clampf(float(hp) / top, 0.0, 1.0)
	# Health is the loudest term, exactly as it is in the catch formula.
	var hp_term := 0.22 + 0.78 * health
	# Ailments take the fight out of it in the same proportions they help a catch.
	var status_term := 1.0 / maxf(1.0, status_bonus_for(statuses))
	# A species nobody catches resists hardest.
	var rate := clampf(float(mon.get("capture_rate", 45)) / 255.0, 0.012, 1.0)
	var rarity_term := 0.55 + 0.85 * (1.0 - rate)
	# And something above your weight class resists more than something below it.
	var level_term := clampf(0.75 + 0.35 * (float(max(1, level))
			/ float(max(1, party_level))), 0.6, 1.5)
	return clampf(hp_term * status_term * rarity_term * level_term, 0.05, 1.0)


static func describe_resistance(r: float) -> String:
	if r >= 0.85:
		return "furious"
	if r >= 0.65:
		return "resisting hard"
	if r >= 0.45:
		return "still struggling"
	if r >= 0.25:
		return "tiring"
	if r >= 0.12:
		return "barely resisting"
	return "spent"


## How many throws the target will put up with before it stops paying attention
## to you and the attempt is over. A furious legendary gives you two; something
## spent will stand there all day.
##
## `patience_mod` comes from the ball in hand (a Safari Ball buys you less time).
static func patience(r: float, patience_mod: int = 0) -> int:
	var base := 6 - int(round(clampf(r, 0.0, 1.0) * 4.0))
	return maxi(1, base + patience_mod)


# ══════════════════════════════════ The throw ════════════════════════════════
## Accuracy tiers, Pokemon-Go style. `ratio` is the distance from dead centre as
## a fraction of the target's radius, so 0 is perfect and 1 is the very edge.
##
## Each tier is a multiplier on the catch value, which is what makes aiming worth
## doing at all — a well-placed Great Ball beats a careless Ultra.
const ACCURACY_TIERS := [
	{"ratio": 0.18, "name": "Excellent", "mult": 1.85, "color": Color(1.0, 0.82, 0.32)},
	{"ratio": 0.42, "name": "Great", "mult": 1.45, "color": Color(0.55, 0.85, 1.0)},
	{"ratio": 0.72, "name": "Nice", "mult": 1.18, "color": Color(0.6, 0.92, 0.66)},
	{"ratio": 1.00, "name": "", "mult": 1.0, "color": Color(0.82, 0.82, 0.86)},
]

## A ball thrown with a swerve on it is worth this much more, as in Go.
const CURVE_BONUS := 1.35


static func accuracy_tier(ratio: float) -> Dictionary:
	for tier in ACCURACY_TIERS:
		if ratio <= float(tier["ratio"]):
			return tier
	return ACCURACY_TIERS[ACCURACY_TIERS.size() - 1]


## Everything one throw is worth, gathered up: the catch value, the odds it
## implies, and the words the screen puts on screen.
##
## `ctx` is a PokeBalls.context_for() dictionary. `ratio` and `curved` come from
## where the ball actually landed.
static func throw_odds(ball: String, ctx: Dictionary, ratio: float,
		curved: bool) -> Dictionary:
	var mon: Dictionary = ctx.get("mon", {})
	var statuses: Dictionary = ctx.get("statuses", {})
	var tier := accuracy_tier(ratio)
	var ball_mult := PokeBalls.multiplier(ball, ctx)
	var a := catch_value(mon, ball, int(ctx.get("hp", 1)), int(ctx.get("max_hp", 1)),
			status_bonus_for(statuses), ball_mult)
	a *= float(tier["mult"])
	if curved:
		a *= CURVE_BONUS
	return {
		"value": a,
		"chance": chance_from_value(a),
		"tier": String(tier["name"]),
		"tier_color": tier["color"],
		"tier_mult": float(tier["mult"]),
		"ball_mult": ball_mult,
		"curved": curved,
	}


## Resolves one landed throw into the shake sequence the ball actually performs.
##
## The games roll each of the four shakes separately at b = (a/255)^(3/16), and
## stop at the first failure — which is why a near-miss catch still rattles three
## times before it pops. Reproducing that rather than rolling the 75% power
## directly is the whole reason a break-free feels like a loss instead of a
## coin toss.
static func shake_rolls(a: float, rng: RandomNumberGenerator) -> Dictionary:
	if a >= 255.0:
		return {"caught": true, "shakes": 3, "critical": false}
	var per := clampf(pow(clampf(a, 0.0, 255.0) / 255.0, 0.1875), 0.0, 1.0)
	# A critical capture: one shake, and it holds. Rare, and rarer for a hard
	# catch, exactly as in the games.
	var crit_chance := clampf(a / 255.0, 0.0, 1.0) * 0.06
	if rng.randf() < crit_chance and rng.randf() < per:
		return {"caught": true, "shakes": 1, "critical": true}
	var shakes := 0
	for i in range(4):
		if rng.randf() >= per:
			return {"caught": false, "shakes": shakes, "critical": false}
		shakes += 1
	return {"caught": true, "shakes": 3, "critical": false}
