class_name SlashFx
extends Control

## The moment a thrown blade lands: a cleaving streak across the target, a
## shockwave punched out from the point of contact, and a spray thrown off the
## edge. Paired with the chop at the end of the attack-card animation.

const DROPS := 16
const GRAVITY := 900.0

var duration: float = 0.55
var extent: Vector2 = Vector2(190, 250)
var angle: float = -0.72          ## radians; the direction the blade travelled
var blood: Color = Color(0.75, 0.09, 0.12)

var _t: float = 0.0
var _drops: Array = []            ## {pos, vel, size}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	# The spray follows the blade through, fanning out around its exit path.
	for i in range(DROPS):
		var spread := angle + _rng.randf_range(-0.9, 0.9)
		var speed := _rng.randf_range(150.0, 430.0)
		_drops.append({
			"pos": Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-14.0, 14.0)),
			"vel": Vector2(cos(spread), sin(spread)) * speed,
			"size": _rng.randf_range(2.0, 5.5),
		})
	set_process(true)


static func spawn(parent: Control, at: Rect2, blade_angle: float) -> SlashFx:
	var fx := SlashFx.new()
	fx.extent = at.size
	fx.angle = blade_angle
	parent.add_child(fx)
	fx.position = at.get_center()
	return fx


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= duration:
		queue_free()


func _draw() -> void:
	var p: float = clampf(_t / duration, 0.0, 1.0)
	var reach: float = maxf(extent.x, extent.y) * 0.5
	var dir := Vector2(cos(angle), sin(angle))
	var across := Vector2(-dir.y, dir.x)

	# The cut itself: a tapered streak that draws through fast and fades.
	var cut: float = clampf(p / 0.22, 0.0, 1.0)
	if p < 0.5:
		var alpha := 1.0 - clampf((p - 0.22) / 0.28, 0.0, 1.0)
		var half := reach * cut
		var tip := dir * half
		var tail := -dir * half
		var wide := across * lerpf(11.0, 2.0, cut)
		draw_colored_polygon(PackedVector2Array([tail, tip + wide, tip, tip - wide]),
				Color(1, 1, 1, alpha * 0.9))
		draw_line(tail, tip, Color(1.0, 0.86, 0.86, alpha), 2.5, true)

	# Shockwave ring, thrown out from the contact point.
	if p < 0.45:
		var rp := p / 0.45
		var r := rp * reach * 0.85
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40,
				Color(1, 0.92, 0.92, (1.0 - rp) * 0.55), lerpf(6.0, 1.0, rp), true)

	# The spray.
	for d in _drops:
		var pos: Vector2 = d["pos"] + d["vel"] * _t + Vector2(0, GRAVITY * _t * _t * 0.5)
		var a := 1.0 - p
		draw_circle(pos, float(d["size"]) * (1.0 - p * 0.35),
				Color(blood.r, blood.g, blood.b, a))
