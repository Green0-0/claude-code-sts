class_name CrackFx
extends Control

## A cursed-mirror shatter: cracks racing out from the point of impact, with
## glass shards spinning away from it.
##
## The web is generated once from a seed so it stays put while it animates, and
## each branch has its own start time — the fracture spreads outward rather than
## appearing all at once.

const SPOKES := 9
const BRANCH_CHANCE := 0.75
const SHARDS := 14

var tint: Color = Color(0.85, 0.92, 1.0)
var radius: float = 80.0
var life: float = 0.85

var _t: float = 0.0
var _lines: Array = []     ## [{from, to, delay, width}]
var _shards: Array = []    ## [{pos, vel, spin, size}]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


static func spawn(parent: Control, at: Vector2, colour: Color,
		size_px: float = 80.0, seed_value: int = 0) -> CrackFx:
	var fx := CrackFx.new()
	fx.tint = colour
	fx.radius = size_px
	parent.add_child(fx)
	fx.position = at
	fx._build(seed_value)
	return fx


func _build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 20260728
	_lines.clear()
	_shards.clear()

	for i in range(SPOKES):
		# Spread the spokes evenly, then jitter, so it never looks like a wheel.
		var angle := TAU * float(i) / float(SPOKES) + rng.randf_range(-0.28, 0.28)
		var length := radius * rng.randf_range(0.55, 1.0)
		var tip := Vector2(cos(angle), sin(angle)) * length
		_lines.append({"from": Vector2.ZERO, "to": tip, "delay": 0.0,
				"width": rng.randf_range(1.6, 3.0)})
		# A branch part-way along, veering off like real glass.
		if rng.randf() < BRANCH_CHANCE:
			var at_t := rng.randf_range(0.35, 0.7)
			var root: Vector2 = tip * at_t
			var branch_angle := angle + rng.randf_range(-1.0, 1.0)
			var branch_len := length * rng.randf_range(0.25, 0.5)
			_lines.append({
				"from": root,
				"to": root + Vector2(cos(branch_angle), sin(branch_angle)) * branch_len,
				"delay": at_t * 0.18, "width": rng.randf_range(1.0, 1.8),
			})

	for i in range(SHARDS):
		var a := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(90.0, 240.0)
		_shards.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(a), sin(a)) * speed,
			"spin": rng.randf_range(-9.0, 9.0),
			"size": rng.randf_range(3.0, 7.5),
			"rot": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_t += delta
	for s in _shards:
		s["vel"] = (s["vel"] as Vector2) * 0.90 + Vector2(0, 420.0 * delta)
		s["pos"] = (s["pos"] as Vector2) + (s["vel"] as Vector2) * delta
		s["rot"] = float(s["rot"]) + float(s["spin"]) * delta
	queue_redraw()
	if _t >= life:
		queue_free()


func _draw() -> void:
	var p: float = clampf(_t / life, 0.0, 1.0)
	# A hard white bloom on the first frames, as the glass gives way.
	if p < 0.16:
		var flash: float = 1.0 - p / 0.16
		draw_circle(Vector2.ZERO, radius * 0.42 * (0.4 + p * 4.0),
				Color(1, 1, 1, flash * 0.5))

	for line in _lines:
		var delay := float(line["delay"])
		if _t < delay:
			continue
		# Each crack races out over its own first 200 ms, then holds and fades.
		var grow: float = clampf((_t - delay) / 0.2, 0.0, 1.0)
		var alpha: float = (1.0 - p) * 0.95
		var from: Vector2 = line["from"]
		var to: Vector2 = from + ((line["to"] as Vector2) - from) * grow
		draw_line(from, to, Color(tint.r, tint.g, tint.b, alpha), float(line["width"]), true)

	for s in _shards:
		var alpha2: float = (1.0 - p) * 0.9
		var half := float(s["size"])
		var rot := float(s["rot"])
		var centre: Vector2 = s["pos"]
		# A little triangle of glass, tumbling.
		var pts := PackedVector2Array()
		for k in range(3):
			var a := rot + TAU * float(k) / 3.0
			pts.append(centre + Vector2(cos(a), sin(a)) * half)
		draw_colored_polygon(pts, Color(tint.r, tint.g, tint.b, alpha2))
