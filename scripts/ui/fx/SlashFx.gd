class_name SlashFx
extends Control

## The moment the blade lands: a hard diagonal gash across the target, a white
## bloom at the point of contact, and blood thrown off along the cut.
##
## The gash is drawn as a lens — wide in the middle, tapering to nothing at both
## ends — which reads as a cut rather than a drawn line. It opens fast, holds,
## then fades while the spatter keeps travelling under gravity.

const DROPS := 26
const OPEN_TIME := 0.07        ## how long the gash takes to tear open
## Half-width of the wound at its middle. Generous on purpose: a gash the width
## of a drawn line reads as a scratch, not as something buried in the target.
const GASH_WIDTH := 30.0

var tint: Color = Color(1.0, 0.96, 0.92)
var blood: Color = Color(0.72, 0.06, 0.10)
var length: float = 150.0
var angle: float = -0.62       ## radians; the arc of a downward chop
var life: float = 0.55

var _t: float = 0.0
var _drops: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


static func spawn(parent: Control, at: Vector2, size_px: float,
		seed_value: int = 0) -> SlashFx:
	var fx := SlashFx.new()
	fx.length = size_px
	parent.add_child(fx)
	fx.position = at
	fx._build(seed_value)
	return fx


func _build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 987654
	angle = rng.randf_range(-0.78, -0.45)
	_drops.clear()
	for i in range(DROPS):
		# Thrown out mostly along the cut, with a spray of scatter around it.
		var a := angle + rng.randf_range(-0.9, 0.9) + (PI if rng.randf() < 0.5 else 0.0)
		var speed := rng.randf_range(120.0, 420.0)
		_drops.append({
			"pos": Vector2(cos(angle), sin(angle)) * rng.randf_range(-0.22, 0.22) * length,
			"vel": Vector2(cos(a), sin(a)) * speed,
			"size": rng.randf_range(1.8, 4.6),
		})


func _process(delta: float) -> void:
	_t += delta
	for d in _drops:
		d["vel"] = (d["vel"] as Vector2) + Vector2(0, 900.0 * delta)
		d["pos"] = (d["pos"] as Vector2) + (d["vel"] as Vector2) * delta
	queue_redraw()
	if _t >= life:
		queue_free()


func _draw() -> void:
	var p: float = clampf(_t / life, 0.0, 1.0)
	var open: float = clampf(_t / OPEN_TIME, 0.0, 1.0)

	# White bloom at the point of impact, gone almost immediately.
	if p < 0.22:
		var f: float = 1.0 - p / 0.22
		draw_circle(Vector2.ZERO, length * 0.30 * (0.5 + p * 3.0), Color(1, 1, 1, f * 0.55))

	# The gash itself: a lens along the cut, fattest at the centre.
	var half := length * 0.5 * open
	var dir := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-dir.y, dir.x)
	# Holds its width for the first half of its life, then closes up.
	var fade: float = 1.0 - p
	var thickness := GASH_WIDTH * open * (1.0 - maxf(0.0, p - 0.45) / 0.55)

	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var steps := 16
	for i in range(steps + 1):
		var u := float(i) / float(steps)        # 0..1 along the cut
		var along := (u * 2.0 - 1.0) * half
		# sin gives the taper: zero at both tips, widest in the middle.
		var w := sin(u * PI) * thickness
		upper.append(dir * along + normal * w)
		lower.append(dir * along - normal * w)
	lower.reverse()
	var shape := upper
	shape.append_array(lower)
	if shape.size() >= 3:
		draw_colored_polygon(shape, Color(tint.r, tint.g, tint.b, fade * 0.92))
		# The wound itself, filling most of the cut — the pale edge is only the
		# torn rim around it.
		var core := PackedVector2Array()
		for i in range(steps + 1):
			var u2 := float(i) / float(steps)
			core.append(dir * ((u2 * 2.0 - 1.0) * half * 0.94)
					+ normal * sin(u2 * PI) * thickness * 0.72)
		var core_lower := PackedVector2Array()
		for i in range(steps, -1, -1):
			var u3 := float(i) / float(steps)
			core_lower.append(dir * ((u3 * 2.0 - 1.0) * half * 0.94)
					- normal * sin(u3 * PI) * thickness * 0.72)
		core.append_array(core_lower)
		if core.size() >= 3:
			draw_colored_polygon(core, Color(blood.r, blood.g, blood.b, fade * 0.85))

	for d in _drops:
		draw_circle(d["pos"], float(d["size"]) * (1.0 - p * 0.4),
				Color(blood.r, blood.g, blood.b, fade * 0.95))
