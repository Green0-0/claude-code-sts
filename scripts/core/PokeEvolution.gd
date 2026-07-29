class_name PokeEvolution
extends RefCounted

## Evolution, driven by the imported chains.
##
## PokeAPI describes evolutions with triggers a dungeon cannot reproduce — trade,
## held items, time of day, walking 10,000 steps. build_data.py folds every one
## of those onto a level threshold (see its evo_level), so from here everything
## is simply "at level N this becomes that". Branching lines like Eevee's eight
## keep all their branches and the player picks.
##
## Evolving is what lets a weak starter keep up: a Magikarp that reaches level 20
## becomes a Gyarados, and its whole stat line and card pool come with it.


## Branches available to a species at a given level, earliest first.
static func available(mon_name: String, level: int) -> Array:
	var out: Array = []
	for branch in PokeData.evolutions_of(mon_name):
		if level >= int(branch.get("level", 999)):
			out.append(branch)
	return out


static func can_evolve(mon_name: String, level: int) -> bool:
	return not available(mon_name, level).is_empty()


## True when this species has somewhere to go at all, at any level.
static func evolves_at_all(mon_name: String) -> bool:
	return not PokeData.evolutions_of(mon_name).is_empty()


## The next level at which something becomes available, or 0 if nothing will.
static func next_level(mon_name: String, level: int) -> int:
	var soonest := 0
	for branch in PokeData.evolutions_of(mon_name):
		var at := int(branch.get("level", 0))
		if at > level and (soonest == 0 or at < soonest):
			soonest = at
	return soonest


## The species a branch leads to, or {} if the data is missing it.
static func target(branch: Dictionary) -> Dictionary:
	return PokeData.mon(String(branch.get("to", "")))


## A one-line description of what a branch does, for the prompt that offers it.
static func describe(branch: Dictionary) -> String:
	var mon := target(branch)
	if mon.is_empty():
		return String(branch.get("to", "?"))
	var types := ""
	for t in mon["types"]:
		types += ("/" if types != "" else "") + PokeData.display_name(String(t))
	var gain := int(mon["bst"])
	return "%s — %s, BST %d" % [PokeData.display_name(String(mon["name"])), types, gain]


## Everything a species can reach further down its line, at any depth. Used to
## widen the card pool: a Charmander should be offered moves it will only learn
## once it is a Charizard, otherwise evolving late in a run is a dead end.
static func line_from(mon_name: String) -> Array:
	var out: Array = []
	var queue: Array = [mon_name]
	var seen := {mon_name: true}
	while not queue.is_empty():
		var current: String = String(queue.pop_front())
		for branch in PokeData.evolutions_of(current):
			var to := String(branch.get("to", ""))
			if to == "" or seen.has(to):
				continue
			seen[to] = true
			out.append(to)
			queue.append(to)
	return out
