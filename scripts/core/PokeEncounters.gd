class_name PokeEncounters
extends RefCounted

## Decides which Pokemon you meet, and how likely each one is.
##
## Every species carries a weight for every (act, encounter kind) slot, and that
## weight is a bell curve over its base stat total — see PokeBalance.BST_BANDS.
## An Act 1 "weak" slot centres on 300 BST, so Rattata and Caterpie dominate it
## and Dragonite is effectively impossible; an Act 3 boss slot centres on 660,
## where the legendaries live. Nothing is hand-listed: the whole dex is in the
## table and BST decides how often you see each entry.

## Weights below this are treated as zero, so the tail of the curve does not
## fill every table with thousands of near-impossible entries.
const MIN_WEIGHT := 0.02

static var _tables: Dictionary = {}    ## "act:kind" -> [{index, weight}, ...]
static var _totals: Dictionary = {}    ## "act:kind" -> summed weight


static func _key(act: int, kind: String) -> String:
	return "%d:%s" % [clampi(act, 1, 3), kind]


## The weighted candidate list for one slot, built once and cached.
static func table(act: int, kind: String) -> Array:
	var key := _key(act, kind)
	if _tables.has(key):
		return _tables[key]
	var rows: Array = []
	var total := 0.0
	var mons := PokeData.mons()
	for i in range(mons.size()):
		var w := PokeBalance.encounter_weight(mons[i], clampi(act, 1, 3), kind)
		if w < MIN_WEIGHT:
			continue
		rows.append({"index": i, "weight": w})
		total += w
	_tables[key] = rows
	_totals[key] = total
	return rows


## Probability of drawing a given species in a slot, as a percentage. Exposed
## because it is the number the design is actually about, and the tests assert
## on it.
static func probability(mon_name: String, act: int, kind: String) -> float:
	var key := _key(act, kind)
	var rows := table(act, kind)
	var total := float(_totals.get(key, 0.0))
	if total <= 0.0:
		return 0.0
	var idx := PokeData.mon_index(mon_name)
	for row in rows:
		if int(row["index"]) == idx:
			return float(row["weight"]) / total * 100.0
	return 0.0


static func _pick_index(act: int, kind: String, rng: RandomNumberGenerator) -> int:
	var rows := table(act, kind)
	if rows.is_empty():
		return -1
	var total := float(_totals.get(_key(act, kind), 0.0))
	var roll := rng.randf() * total
	for row in rows:
		roll -= float(row["weight"])
		if roll <= 0.0:
			return int(row["index"])
	return int(rows[rows.size() - 1]["index"])


## One encounter: a list of enemy ids to fight together. Weak species arrive in
## groups, strong ones alone — see PokeBalance.group_size.
static func pick(act: int, kind: String, rng: RandomNumberGenerator,
		recent: Array = []) -> Array:
	var role := "normal"
	if kind == "elite":
		role = "elite"
	elif kind == "boss":
		role = "boss"

	# A few attempts to avoid an immediate repeat, then take what we are given.
	var index := -1
	for attempt in range(6):
		index = _pick_index(act, kind, rng)
		if index < 0:
			return []
		var candidate := PokeMobs.enemy_id(String(PokeData.mon_at(index)["name"]), role)
		if not recent.has(candidate):
			break
	if index < 0:
		return []

	var mon := PokeData.mon_at(index)
	var id := PokeMobs.enemy_id(String(mon["name"]), role)
	var count := PokeBalance.group_size(mon, kind)

	var out: Array = []
	for i in range(count):
		out.append(id)
	# Mixed packs read better than three clones, so a second species joins the
	# weaker groups when there is room for one.
	if count >= 2 and kind != "boss" and rng.randf() < 0.5:
		var other := _pick_index(act, kind, rng)
		if other >= 0 and other != index:
			out[out.size() - 1] = PokeMobs.enemy_id(
					String(PokeData.mon_at(other)["name"]), role)
	return out


static func boss_for(act: int, rng: RandomNumberGenerator) -> Array:
	return pick(act, "boss", rng, [])


## Used by the tests and by the dex screen: the most likely species in a slot.
static func top_candidates(act: int, kind: String, count: int = 10) -> Array:
	var rows := table(act, kind).duplicate()
	rows.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	var out: Array = []
	for i in range(min(count, rows.size())):
		var mon := PokeData.mon_at(int(rows[i]["index"]))
		out.append({
			"name": String(mon["name"]),
			"bst": int(mon["bst"]),
			"percent": probability(String(mon["name"]), act, kind),
		})
	return out
