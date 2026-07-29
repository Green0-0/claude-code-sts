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

## Weights below this are dropped. Deliberately tiny: the point of the tail in
## PokeBalance.encounter_weight is that every species stays reachable, so this
## only exists to keep genuinely negligible entries out of the table.
const MIN_WEIGHT := 0.0002

## Progress is continuous but tables are cached, so it is bucketed. Twenty steps
## across a run is fine enough that the climb is smooth and coarse enough that
## the tables are built a handful of times.
const PROGRESS_STEPS := 20

static var _tables: Dictionary = {}    ## "bucket:kind" -> [{index, weight}, ...]
static var _totals: Dictionary = {}    ## "bucket:kind" -> summed weight


static func _bucket(progress: float) -> int:
	return clampi(int(round(clampf(progress, 0.0, 1.0) * PROGRESS_STEPS)), 0, PROGRESS_STEPS)


static func _key(progress: float, kind: String) -> String:
	return "%d:%s" % [_bucket(progress), kind]


## The weighted candidate list for one slot, built once per bucket and cached.
static func table(progress: float, kind: String) -> Array:
	var key := _key(progress, kind)
	if _tables.has(key):
		return _tables[key]
	var quantised := float(_bucket(progress)) / float(PROGRESS_STEPS)
	var rows: Array = []
	var total := 0.0
	var mons := PokeData.mons()
	for i in range(mons.size()):
		var w := PokeBalance.encounter_weight(mons[i], quantised, kind)
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
static func probability(mon_name: String, progress: float, kind: String) -> float:
	var key := _key(progress, kind)
	var rows := table(progress, kind)
	var total := float(_totals.get(key, 0.0))
	if total <= 0.0:
		return 0.0
	var idx := PokeData.mon_index(mon_name)
	for row in rows:
		if int(row["index"]) == idx:
			return float(row["weight"]) / total * 100.0
	return 0.0


static func _pick_index(progress: float, kind: String, rng: RandomNumberGenerator) -> int:
	var rows := table(progress, kind)
	if rows.is_empty():
		return -1
	var total := float(_totals.get(_key(progress, kind), 0.0))
	var roll := rng.randf() * total
	for row in rows:
		roll -= float(row["weight"])
		if roll <= 0.0:
			return int(row["index"])
	return int(rows[rows.size() - 1]["index"])


## One encounter: a list of enemy ids to fight together. Weak species arrive in
## groups, strong ones alone — see PokeBalance.group_size.
static func pick(progress: float, kind: String, rng: RandomNumberGenerator,
		recent: Array = []) -> Array:
	var role := "normal"
	if kind == "elite":
		role = "elite"
	elif kind == "boss":
		role = "boss"

	# A few attempts to avoid an immediate repeat, then take what we are given.
	var index := -1
	var candidates: Array = []
	for attempt in range(6):
		index = _pick_index(progress, kind, rng)
		if index < 0:
			return []
		var candidate := PokeMobs.enemy_id(String(PokeData.mon_at(index)["name"]), role)
		candidates.append(candidate)
	if index < 0:
		return []

	var mon := PokeData.mon_at(index)
	var id := PokeMobs.enemy_id(String(mon["name"]), role)
	var count := PokeBalance.group_size(mon, kind)

	var out: Array = []
	out.append(id)
	for i in range(count):
		var random_candidate = candidates[rng.randi_range(0, candidates.size() - 1)]
		print(Run.act_progress())
		if rng.randf() < Run.act_progress():
			out.append(random_candidate)
	# Mixed packs read better than three clones, so a second species joins the
	# weaker groups when there is room for one.
	
	var attempts := rng.randi_range(0, 34)
	while attempts > 0:
		attempts -= 1
		if rng.randf() >= progress:
			continue
		
		if count >= 2 and kind != "boss":
			var other := _pick_index(progress, kind, rng)
			if other >= 0 and other != index:
				out.append(PokeMobs.enemy_id(
					String(PokeData.mon_at(other)["name"]), role))
				# Optional: break early if you only need one successful result?
				# break
	return out


static func boss_for(progress: float, rng: RandomNumberGenerator) -> Array:
	return pick(progress, "boss", rng, [])


## Used by the tests and by the dex screen: the most likely species in a slot.
static func top_candidates(progress: float, kind: String, count: int = 10) -> Array:
	var rows := table(progress, kind).duplicate()
	rows.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	var out: Array = []
	for i in range(min(count, rows.size())):
		var mon := PokeData.mon_at(int(rows[i]["index"]))
		out.append({
			"name": String(mon["name"]),
			"bst": int(mon["bst"]),
			"percent": probability(String(mon["name"]), progress, kind),
		})
	return out
