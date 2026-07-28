class_name CardFx
extends Control

## The drawn half of a card execution: the marks a card leaves on its target.
##
## One node, one mark, one lifetime — CardFxLayer spawns these, they draw
## themselves against a 0..1 progress value and free themselves at the end.
## Everything is vector drawing rather than textures so the shapes can be sized
## to whatever they landed on.

enum Kind {
	SLASH,      ## the hatchet gash of an attack landing
	IMPACT,     ## the shock ring and shrapnel that goes with it
	RIPPLE,     ## a blessing settling on its target, like rain on a lake
	CRACK,      ## a hostile effect biting: a cursed mirror giving way
	SHARDS,     ## glass falling out of that mirror
}

var kind: int = Kind.SLASH
var progress: float = 0.0
var tint: Color = Color(1, 1, 1)
var extent: Vector2 = Vector2(180, 250)   ## roughly the target's size
var seed_value: int = 0

var _rng := RandomNumberGenerator.new()
var _strokes: Array = []
var _shards: Array = []
var _radius: float = 80.0


## Every mark is sized off the target's *shorter* side, so it stays on the thing
## it hit. Using the diagonal instead lets a tall card's marks hang well past
## its edges and read as belonging to nothing.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radius = minf(extent.x, extent.y) * 0.5
	_rng.seed = seed_value
	match kind:
		Kind.SLASH: _build_strokes()
		Kind.CRACK: _build_cracks()
		Kind.SHARDS: _build_shards()


func set_progress(v: float) -> void:
	progress = clampf(v, 0.0, 1.0)
	queue_redraw()


# ═══════════════════════════════ Shape building ══════════════════════════════
## Three gashes at slightly different angles, the way a blade actually lands —
## one committed stroke and two lighter ones raking alongside it.
func _build_strokes() -> void:
	var reach: float = _radius * 1.5
	var base_angle := _rng.randf_range(-0.9, -0.5)
	for i in range(3):
		var angle := base_angle + _rng.randf_range(-0.22, 0.22)
		var offset := Vector2(_rng.randf_range(-0.16, 0.16),
				_rng.randf_range(-0.16, 0.16)) * extent
		var dir := Vector2(cos(angle), sin(angle))
		var length := reach * (1.0 if i == 0 else _rng.randf_range(0.55, 0.8))
		_strokes.append({
			"a": offset - dir * length * 0.5,
			"b": offset + dir * length * 0.5,
			"width": (11.0 if i == 0 else _rng.randf_range(4.0, 7.0)),
			"delay": 0.0 if i == 0 else _rng.randf_range(0.05, 0.16),
		})


## Radial fractures with branches, spreading from the point of contact.
func _build_cracks() -> void:
	var arms := _rng.randi_range(7, 9)
	var reach: float = _radius * 0.95
	for i in range(arms):
		var angle := TAU * float(i) / float(arms) + _rng.randf_range(-0.24, 0.24)
		var points: Array = [Vector2.ZERO]
		var at := Vector2.ZERO
		var steps := _rng.randi_range(3, 5)
		for s in range(steps):
			angle += _rng.randf_range(-0.35, 0.35)
			at += Vector2(cos(angle), sin(angle)) * (reach / float(steps))
			points.append(at)
		_strokes.append({"points": points, "width": _rng.randf_range(1.6, 3.2),
				"delay": _rng.randf_range(0.0, 0.12)})
		# A branch peeling off part-way along, which is what makes it read as
		# glass rather than as a starburst.
		if points.size() > 2 and _rng.randf() < 0.75:
			var from: Vector2 = points[1]
			var b_angle := angle + _rng.randf_range(0.6, 1.3) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var b: Array = [from]
			var b_at := from
			# Branches are shorter and thinner than the arm they leave.
			for s in range(2):
				b_angle += _rng.randf_range(-0.3, 0.3)
				b_at += Vector2(cos(b_angle), sin(b_angle)) * (reach * 0.22)
				b.append(b_at)
			_strokes.append({"points": b, "width": _rng.randf_range(1.0, 1.8),
					"delay": _rng.randf_range(0.1, 0.25)})


func _build_shards() -> void:
	for i in range(_rng.randi_range(9, 13)):
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(0.4, 1.0)
		_shards.append({
			"dir": Vector2(cos(angle), sin(angle)),
			"speed": speed,
			"spin": _rng.randf_range(-7.0, 7.0),
			"size": _rng.randf_range(5.0, 13.0),
		})


# ═══════════════════════════════════ Drawing ═════════════════════════════════
func _draw() -> void:
	match kind:
		Kind.SLASH: _draw_slash()
		Kind.IMPACT: _draw_impact()
		Kind.RIPPLE: _draw_ripple()
		Kind.CRACK: _draw_crack()
		Kind.SHARDS: _draw_shards()


## Each gash wipes open fast, holds, then fades — with a hot core inside a
## wider soft edge so it reads as a cut rather than a drawn line.
func _draw_slash() -> void:
	for s in _strokes:
		var local := clampf((progress - float(s["delay"])) / 0.34, 0.0, 1.0)
		if local <= 0.0:
			continue
		var fade := 1.0 - smoothstep(0.55, 1.0, progress)
		if fade <= 0.0:
			continue
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var tip: Vector2 = a.lerp(b, _ease_out(local))
		var w: float = float(s["width"])
		draw_line(a, tip, Color(tint.r, tint.g, tint.b, 0.5 * fade), w * 2.2, true)
		draw_line(a, tip, Color(1, 1, 1, 0.95 * fade), w * 0.45, true)


func _draw_impact() -> void:
	var fade := 1.0 - progress
	if fade <= 0.0:
		return
	var radius: float = _radius * 0.22 + progress * _radius * 0.95
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48,
			Color(tint.r, tint.g, tint.b, 0.75 * fade * fade), 6.0 * fade + 1.0, true)
	draw_arc(Vector2.ZERO, radius * 0.62, 0, TAU, 40,
			Color(1, 1, 1, 0.5 * fade * fade), 3.0 * fade + 1.0, true)


## Concentric rings running outward and flattening as they go, the way a drop
## spreads on still water.
func _draw_ripple() -> void:
	var rings := 4
	for i in range(rings):
		var offset := float(i) * 0.16
		var local := progress - offset
		if local <= 0.0:
			continue
		local = clampf(local / (1.0 - offset), 0.0, 1.0)
		var radius: float = _radius * 0.18 + _ease_out(local) * _radius * 0.82
		var fade: float = (1.0 - local) * (1.0 - float(i) / float(rings + 1))
		# Squashed vertically: a surface seen at an angle, not a flat circle.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48,
				Color(tint.r, tint.g, tint.b, 0.62 * fade), 3.0 * fade + 1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_crack() -> void:
	var fade := 1.0 - smoothstep(0.72, 1.0, progress)
	if fade <= 0.0:
		return
	for s in _strokes:
		var local := clampf((progress - float(s["delay"])) / 0.3, 0.0, 1.0)
		if local <= 0.0:
			continue
		var pts: Array = s["points"]
		var reveal: float = _ease_out(local) * float(pts.size() - 1)
		var w: float = float(s["width"])
		for i in range(pts.size() - 1):
			if float(i) >= reveal:
				break
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var frac: float = clampf(reveal - float(i), 0.0, 1.0)
			b = a.lerp(b, frac)
			# Dark fracture with a pale glint along it, like light caught in glass.
			draw_line(a, b, Color(0.05, 0.02, 0.08, 0.85 * fade), w * 2.0, true)
			draw_line(a, b, Color(tint.r, tint.g, tint.b, 0.9 * fade), w, true)


func _draw_shards() -> void:
	var fade := 1.0 - smoothstep(0.5, 1.0, progress)
	if fade <= 0.0:
		return
	var travel: float = _radius * 0.85
	for s in _shards:
		var dir: Vector2 = s["dir"]
		var dist: float = _ease_out(progress) * travel * float(s["speed"])
		# Gravity, so they fall away rather than floating off.
		var at: Vector2 = dir * dist + Vector2(0, progress * progress * 90.0)
		var size: float = float(s["size"])
		var spin: float = float(s["spin"]) * progress
		var pts := PackedVector2Array([
			at + Vector2(cos(spin), sin(spin)) * size,
			at + Vector2(cos(spin + 2.3), sin(spin + 2.3)) * size * 0.7,
			at + Vector2(cos(spin + 4.1), sin(spin + 4.1)) * size * 0.85,
		])
		draw_colored_polygon(pts, Color(tint.r, tint.g, tint.b, 0.8 * fade))


static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
