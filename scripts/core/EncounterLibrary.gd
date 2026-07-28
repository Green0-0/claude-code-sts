class_name EncounterLibrary
extends RefCounted

## Which enemies show up where. Each entry is a list of enemy ids fought together.

static var ACTS := {
1: {
	"weak": [
		["cultist"],
		["jaw_worm"],
		["red_louse", "red_louse"],
		["green_louse", "red_louse"],
		["acid_slime_s", "spike_slime_s"],
		["spike_slime_m"],
	],
	"strong": [
		["red_louse", "green_louse", "red_louse"],
		["acid_slime_m", "spike_slime_s"],
		["fungi_beast", "fungi_beast"],
		["jaw_worm", "acid_slime_s"],
		["looter"],
		["slaver_blue"],
		["slaver_red"],
		["mad_gremlin", "sneaky_gremlin", "fat_gremlin", "shield_gremlin"],
		["gremlin_wizard", "mad_gremlin", "fat_gremlin"],
		["cultist", "cultist"],
	],
	"elite": [
		["gremlin_nob"],
		["lagavulin"],
		["sentry", "sentry", "sentry"],
	],
	"boss": [
		["slime_boss"],
		["the_guardian"],
		["hexaghost"],
	],
},
2: {
	"weak": [
		["spheric_guardian"],
		["chosen"],
		["byrd", "byrd", "byrd"],
		["shelled_parasite"],
		["centurion", "mystic"],
	],
	"strong": [
		["chosen", "byrd"],
		["snake_plant"],
		["centurion", "mystic"],
		["shelled_parasite", "fungi_beast"],
		["spheric_guardian", "byrd", "byrd"],
		["slaver_blue", "slaver_red", "taskmaster"],
	],
	"elite": [
		["gremlin_leader"],
		["book_of_stabbing"],
		["taskmaster", "slaver_blue", "slaver_red"],
	],
	"boss": [
		["champ"],
		["bronze_automaton"],
	],
},
3: {
	"weak": [
		["darkling", "darkling", "darkling"],
		["orb_walker"],
		["repulsor", "spiker"],
		["transient"],
	],
	"strong": [
		["darkling", "darkling", "darkling"],
		["orb_walker", "repulsor"],
		["spiker", "spiker", "repulsor"],
		["snake_plant", "orb_walker"],
		["nemesis"],
	],
	"elite": [
		["nemesis"],
		["giant_head"],
		["spiker", "spiker", "spiker"],
	],
	"boss": [
		["awakened_one"],
		["time_eater"],
	],
},
}


static func act_data(act: int) -> Dictionary:
	return ACTS.get(clampi(act, 1, 3), ACTS[1])


## Picks an encounter, avoiding immediate repeats where possible.
##
## A Pokemon run draws from the whole dex instead, weighted by base stat total —
## see PokeEncounters. The hand-written tables above are only used by the Spire's
## own two characters.
static func pick(act: int, kind: String, rng: RandomNumberGenerator, recent: Array) -> Array:
	if Run.is_pokemon_run():
		return PokeEncounters.pick(act, kind, rng, recent)
	var pool: Array = act_data(act).get(kind, act_data(act)["weak"])
	var candidates: Array = []
	for e in pool:
		var key: String = ",".join(e)
		if not recent.has(key):
			candidates.append(e)
	if candidates.is_empty():
		candidates = pool
	var chosen: Array = candidates[rng.randi_range(0, candidates.size() - 1)]
	return chosen.duplicate()


static func boss_for(act: int, rng: RandomNumberGenerator) -> Array:
	if Run.is_pokemon_run():
		return PokeEncounters.boss_for(act, rng)
	var bosses: Array = act_data(act)["boss"]
	return (bosses[rng.randi_range(0, bosses.size() - 1)] as Array).duplicate()
