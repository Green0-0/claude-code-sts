class_name MapGen
extends RefCounted

## Procedural act map: 15 rows of nodes joined by branching paths, plus a boss.

const ROWS := 15
const COLS := 7
const PATHS := 6
const TREASURE_ROW := 8
const REST_ROW := 14

## Node: {row, col, type, next: Array[int], prev: Array[int], id: int}


static func generate(act: int, rng: RandomNumberGenerator) -> Dictionary:
	var nodes: Array = []
	var grid: Dictionary = {}          ## "row,col" -> node index

	# 1. Carve PATHS random walks from the bottom row to the top row.
	var first_cols: Array = []
	for p in range(PATHS):
		var col: int = rng.randi_range(0, COLS - 1)
		# Guarantee at least two distinct entry points.
		if p == 1:
			var tries := 0
			while col == int(first_cols[0]) and tries < 20:
				col = rng.randi_range(0, COLS - 1)
				tries += 1
		first_cols.append(col)
		var prev_idx := -1
		for row in range(ROWS):
			var key := "%d,%d" % [row, col]
			var idx: int
			if grid.has(key):
				idx = grid[key]
			else:
				idx = nodes.size()
				nodes.append({"row": row, "col": col, "type": "monster",
						"next": [], "prev": [], "id": idx})
				grid[key] = idx
			if prev_idx >= 0 and not (nodes[prev_idx]["next"] as Array).has(idx):
				(nodes[prev_idx]["next"] as Array).append(idx)
				(nodes[idx]["prev"] as Array).append(prev_idx)
			prev_idx = idx
			if row < ROWS - 1:
				var step := rng.randi_range(-1, 1)
				var next_col: int = clampi(col + step, 0, COLS - 1)
				col = next_col

	# 2. Remove crossing edges so paths read cleanly (a<b going up must not swap).
	_uncross(nodes, grid)

	# 2b. Guarantee every node can still reach the row above it. Pruning a
	#     crossing edge can otherwise leave a dead end and strand the player.
	_repair_dead_ends(nodes, grid)

	# 3. Assign room types.
	_assign_types(nodes, act, rng)

	# 4. The boss sits above the final row.
	var boss_idx := nodes.size()
	nodes.append({"row": ROWS, "col": 3, "type": "boss", "next": [], "prev": [], "id": boss_idx})
	for n in nodes:
		if int(n["row"]) == ROWS - 1:
			(n["next"] as Array).append(boss_idx)
			(nodes[boss_idx]["prev"] as Array).append(int(n["id"]))

	var starts: Array = []
	for n in nodes:
		if int(n["row"]) == 0:
			starts.append(int(n["id"]))
	starts.sort()

	return {"nodes": nodes, "starts": starts, "boss": boss_idx, "act": act}


static func _uncross(nodes: Array, grid: Dictionary) -> void:
	for row in range(ROWS - 1):
		for c in range(COLS - 1):
			var a_key := "%d,%d" % [row, c]
			var b_key := "%d,%d" % [row, c + 1]
			if not grid.has(a_key) or not grid.has(b_key):
				continue
			var a: Dictionary = nodes[grid[a_key]]
			var b: Dictionary = nodes[grid[b_key]]
			# a -> (c+1) crossing b -> c
			var a_right := -1
			var b_left := -1
			for n in a["next"]:
				if int(nodes[n]["col"]) == c + 1:
					a_right = n
			for n in b["next"]:
				if int(nodes[n]["col"]) == c:
					b_left = n
			if a_right >= 0 and b_left >= 0:
				# Drop one of the two crossing edges at random-free choice.
				(a["next"] as Array).erase(a_right)
				(nodes[a_right]["prev"] as Array).erase(int(a["id"]))
				if (a["next"] as Array).is_empty():
					(a["next"] as Array).append(b_left)
					(nodes[b_left]["prev"] as Array).append(int(a["id"]))


## Every node below the top row must have at least one upward edge, otherwise a
## path can dead-end and the run becomes unwinnable.
static func _repair_dead_ends(nodes: Array, grid: Dictionary) -> void:
	for row in range(ROWS - 1):
		for n in nodes:
			if int(n["row"]) != row or not (n["next"] as Array).is_empty():
				continue
			var col := int(n["col"])
			var best := -1
			var best_dist := 999
			for other in nodes:
				if int(other["row"]) != row + 1:
					continue
				var dist: int = absi(int(other["col"]) - col)
				if dist < best_dist:
					best_dist = dist
					best = int(other["id"])
			if best < 0:
				# No node exists on the row above: create the one straight ahead.
				best = nodes.size()
				nodes.append({"row": row + 1, "col": col, "type": "monster",
						"next": [], "prev": [], "id": best})
				grid["%d,%d" % [row + 1, col]] = best
			(n["next"] as Array).append(best)
			(nodes[best]["prev"] as Array).append(int(n["id"]))


static func _assign_types(nodes: Array, act: int, rng: RandomNumberGenerator) -> void:
	for n in nodes:
		var row := int(n["row"])
		if row == 0:
			n["type"] = "monster"
			continue
		if row == TREASURE_ROW:
			n["type"] = "treasure"
			continue
		if row == REST_ROW:
			n["type"] = "rest"
			continue
		n["type"] = ""

	for n in nodes:
		if n["type"] != "":
			continue
		var row := int(n["row"])
		var t := _roll_type(rng, row)
		var guard := 0
		while not _type_ok(nodes, n, t) and guard < 24:
			t = _roll_type(rng, row)
			guard += 1
		if guard >= 24:
			t = "monster"
		n["type"] = t


static func _roll_type(rng: RandomNumberGenerator, row: int) -> String:
	var r := rng.randf()
	if row < 5:
		# Early rows: no elites or campfires.
		if r < 0.60:
			return "monster"
		if r < 0.90:
			return "event"
		return "shop"
	if r < 0.42:
		return "monster"
	if r < 0.64:
		return "event"
	if r < 0.80:
		return "elite"
	if r < 0.92:
		return "rest"
	return "shop"


static func _type_ok(nodes: Array, n: Dictionary, t: String) -> bool:
	if t == "monster" or t == "event":
		return true
	# No two consecutive special rooms of the same kind along any path.
	for p in n["prev"]:
		if String(nodes[p]["type"]) == t:
			return false
	for p in n["next"]:
		if String(nodes[p]["type"]) == t:
			return false
	return true


static func room_label(t: String) -> String:
	match t:
		"monster": return "Monster"
		"elite": return "Elite"
		"rest": return "Rest Site"
		"shop": return "Merchant"
		"treasure": return "Treasure"
		"event": return "Unknown"
		"boss": return "Boss"
	return t.capitalize()


static func room_sigil(t: String) -> String:
	match t:
		"monster": return "☠"
		"elite": return "☠!"
		"rest": return "🔥"
		"shop": return "$"
		"treasure": return "▣"
		"event": return "?"
		"boss": return "☠☠"
	return "•"


static func room_color(t: String) -> Color:
	match t:
		"monster": return Color(0.86, 0.42, 0.38)
		"elite": return Color(0.95, 0.32, 0.30)
		"rest": return Color(0.98, 0.66, 0.32)
		"shop": return Color(0.45, 0.80, 0.95)
		"treasure": return Color(0.95, 0.83, 0.38)
		"event": return Color(0.68, 0.80, 0.55)
		"boss": return Color(0.85, 0.25, 0.45)
	return Color(0.7, 0.7, 0.7)
