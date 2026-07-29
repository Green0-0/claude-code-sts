class_name PokeCapture
extends RefCounted

## Catching a Pokemon, using the games' own formula and the imported capture
## rates.
##
## After every boss the player is handed one ball and picks something they have
## already met to throw it at. The odds are the real ones: a species' capture
## rate, how hurt it is, and the ball's multiplier. A Rattata at low health is a
## near certainty; a legendary at full health is a long shot, which is what makes
## spending the ball a decision rather than a formality.

## A ball is thrown at something already worn down, not at full health — that is
## what the boss fight before it represents. Lives here rather than on the picker
## so that both the odds shown and the throw itself read the same number, and so
## no UI script has to be a registered global class for the other to see it.
const CAPTURE_HP_FRACTION := 0.2

## Ball catch-rate multipliers, as in the games.
const BALLS := {
	"poke": {"name": "Poké Ball", "mult": 1.0,
		"desc": "The standard ball."},
	"great": {"name": "Great Ball", "mult": 1.5,
		"desc": "Half again as likely to hold."},
	"ultra": {"name": "Ultra Ball", "mult": 2.0,
		"desc": "Twice as likely to hold."},
	"master": {"name": "Master Ball", "mult": 255.0,
		"desc": "Never fails."},
}

## Which ball each boss hands over. They get better as the run goes on, which is
## what keeps late captures viable against rising capture rates.
const BALL_BY_BOSS := ["poke", "great", "ultra", "master"]


static func ball_for_boss(bosses_slain: int) -> String:
	var idx := clampi(bosses_slain, 0, BALL_BY_BOSS.size() - 1)
	return String(BALL_BY_BOSS[idx])


static func ball_def(ball: String) -> Dictionary:
	return BALLS.get(ball, BALLS["poke"])


## The games' modified catch rate:
##
##   a = ((3·MaxHP − 2·CurrentHP) / (3·MaxHP)) · captureRate · ballBonus · statusBonus
##
## `a` at or above 255 is a guaranteed catch. Status ailments help, as they do in
## the games: sleep and freeze most, the rest less.
static func catch_value(mon: Dictionary, ball: String, hp: int, max_hp: int,
		status_bonus: float = 1.0) -> float:
	var rate := float(mon.get("capture_rate", 45))
	var top := maxf(1.0, float(max_hp))
	var cur := clampf(float(hp), 1.0, top)
	var health_term := (3.0 * top - 2.0 * cur) / (3.0 * top)
	var mult := float(ball_def(ball).get("mult", 1.0))
	return health_term * rate * mult * status_bonus


## Probability the ball holds, 0-1.
##
## The games shake the ball four times, each with probability
## b = 65536 / (255/a)^0.1875; the catch is all four succeeding, which works out
## to (a/255)^0.75.
static func catch_chance(mon: Dictionary, ball: String, hp: int, max_hp: int,
		status_bonus: float = 1.0) -> float:
	var a := catch_value(mon, ball, hp, max_hp, status_bonus)
	if a >= 255.0:
		return 1.0
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
