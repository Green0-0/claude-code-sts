class_name Actor
extends RefCounted

## Runtime combat state for the player or a single enemy.

var name: String = "Actor"
var is_player: bool = false
var enemy_id: String = ""
var hp: int = 10
var max_hp: int = 10
var block: int = 0
var statuses: Dictionary = {}      ## id -> stacks
var rolled: Dictionary = {}        ## per-instance rolled values, referenced by "@key"
var alive: bool = true

## Pokemon-only. Empty for the Spire's own cast, and every Pokemon rule checks
## for that: a Cultist has no types to be weak to and no Defense to soak with.
var poke_name: String = ""
var poke_stats: Dictionary = {}    ## hp/atk/df/spa/spd/spe base stats
var poke_types: Array = []         ## e.g. ["water", "flying"]
## Multiplier on this actor's offensive and defensive stats. Only ever above 1
## for a player running a below-band species — see PokeBalance.trainer_scale.
var stat_scale: float = 1.0
var last_hit_taken: int = 0        ## unblocked damage from the last move that hit
var last_hit_class: String = ""    ## "physical" / "special", for Counter et al

## Enemy-only
var turn_count: int = 0
var move_history: Array = []       ## names of past moves, most recent last
var intent: Dictionary = {}        ## {kind, effects, name}
var is_minion: bool = false
var is_boss: bool = false
var leader = null
var slot: int = 0

## Bookkeeping
var attacked_this_combat: bool = false


static func make_player(pname: String, cur_hp: int, maximum_hp: int) -> Actor:
	var a := Actor.new()
	a.name = pname
	a.is_player = true
	a.hp = cur_hp
	a.max_hp = maximum_hp
	return a


func get_status(id: String) -> int:
	return int(statuses.get(id, 0))


func has_status(id: String) -> bool:
	return get_status(id) > 0


func set_status(id: String, stacks: int) -> void:
	if stacks <= 0:
		statuses.erase(id)
	else:
		statuses[id] = stacks


func add_status(id: String, stacks: int) -> void:
	set_status(id, get_status(id) + stacks)


func is_pokemon() -> bool:
	return poke_name != ""


## Base stat lookup with a sane default, so shared damage code can ask any actor.
func base_stat(key: String, fallback: int = 50) -> int:
	return int(poke_stats.get(key, fallback))


## Stat stages live in the same status bag as everything else, prefixed so they
## cannot collide with a Spire power, and are signed like Strength.
func stage(stat: String) -> int:
	return int(statuses.get("stage_" + stat, 0))


func add_stage(stat: String, amount: int) -> int:
	var key := "stage_" + stat
	var next := clampi(stage(stat) + amount, -PokeBalance.MAX_STAGE, PokeBalance.MAX_STAGE)
	if next == 0:
		statuses.erase(key)
	else:
		statuses[key] = next
	return next


## Strength can be negative, so it is stored separately from the >0 rule.
func add_signed_status(id: String, stacks: int) -> void:
	if id.begins_with("stage_"):
		statuses[id] = clampi(get_status(id) + stacks,
				-PokeBalance.MAX_STAGE, PokeBalance.MAX_STAGE)
		if statuses[id] == 0:
			statuses.erase(id)
	elif id in ["strength", "dexterity"]:
		statuses[id] = get_status(id) + stacks
		if statuses[id] == 0:
			statuses.erase(id)
	else:
		add_status(id, stacks)


func is_dead() -> bool:
	return hp <= 0


func hp_ratio() -> float:
	return 0.0 if max_hp <= 0 else clampf(float(hp) / float(max_hp), 0.0, 1.0)


func status_summary() -> Array:
	var out: Array = []
	var keys: Array = statuses.keys()
	keys.sort()
	for k in keys:
		out.append({"id": k, "stacks": statuses[k]})
	return out
