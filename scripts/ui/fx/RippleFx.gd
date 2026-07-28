class_name RippleFx
extends Control

## Concentric rings spreading across a target, like something soft dropping into
## a still lake. Used when a friendly status card melts into whoever it blessed.
##
## The rings are squashed vertically so the surface reads as a plane being
## looked across rather than a flat circle drawn on glass.

const RINGS := 4
const SQUASH := 0.42          ## vertical scale, i.e. how oblique the "surface" is
const RING_DELAY := 0.13      ## seconds between one ring starting and the next

var duration: float = 0.95
var radius: float = 120.0
var tint: Color = Color(0.65, 0.9, 1.0)

var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


## Places the effect centred on a rect, sized to cover it.
static func spawn(parent: Control, at: Rect2, colour: Color) -> RippleFx:
	var fx := RippleFx.new()
	fx.tint = colour
	fx.radius = maxf(at.size.x, at.size.y) * 0.75
	parent.add_child(fx)
	fx.position = at.get_center()
	return fx


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= duration + RING_DELAY * RINGS:
		queue_free()


func _draw() -> void:
	for i in range(RINGS):
		var start := float(i) * RING_DELAY
		var p := (_t - start) / duration
		if p <= 0.0 or p >= 1.0:
			continue
		# Rings race outward quickly and then ease, the way real ripples do.
		var eased := 1.0 - pow(1.0 - p, 2.4)
		var r := eased * radius
		var alpha := (1.0 - p) * (1.0 - p) * 0.85
		var col := Color(tint.r, tint.g, tint.b, alpha)
		# draw_arc has no ellipse form, so build the squashed ring by hand.
		_draw_squashed_ring(r, col, lerpf(3.5, 1.0, p))


func _draw_squashed_ring(r: float, col: Color, width: float) -> void:
	var steps := 44
	var points := PackedVector2Array()
	for i in range(steps + 1):
		var a := TAU * float(i) / float(steps)
		points.append(Vector2(cos(a) * r, sin(a) * r * SQUASH))
	draw_polyline(points, col, width, true)
