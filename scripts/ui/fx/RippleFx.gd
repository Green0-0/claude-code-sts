class_name RippleFx
extends Control

## Concentric rings spreading across a target like the surface of a lake.
##
## Drawn rather than textured: a handful of ellipses, each starting a little
## after the one before it, widening and thinning as they go. Ellipses rather
## than circles so the rings read as a surface being looked across, not a bubble.

const RINGS := 4
const RING_DELAY := 0.13      ## seconds between one ring starting and the next
const SQUASH := 0.42          ## vertical scale — how flat the "water" looks

var tint: Color = Color(0.62, 0.90, 0.95)
var radius: float = 90.0
var life: float = 1.05

var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


## Starts a ripple centred on a point in this layer's coordinates.
static func spawn(parent: Control, at: Vector2, colour: Color,
		size_px: float = 90.0) -> RippleFx:
	var fx := RippleFx.new()
	fx.tint = colour
	fx.radius = size_px
	parent.add_child(fx)
	fx.position = at
	return fx


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= life + RING_DELAY * RINGS:
		queue_free()


func _draw() -> void:
	for i in range(RINGS):
		var start := RING_DELAY * float(i)
		if _t < start:
			continue
		var p: float = clampf((_t - start) / life, 0.0, 1.0)
		if p >= 1.0:
			continue
		# Ease out: fast at first, then settling, the way real ripples spread.
		var eased := 1.0 - pow(1.0 - p, 2.2)
		var r := radius * eased
		var alpha: float = (1.0 - p) * (1.0 - p) * 0.85
		# The leading ring is brightest; the trailing ones are its echo.
		alpha *= 1.0 - float(i) * 0.15
		var col := Color(tint.r, tint.g, tint.b, alpha)
		var width: float = maxf(1.0, 3.5 * (1.0 - p))
		_draw_ellipse(r, col, width)


func _draw_ellipse(r: float, col: Color, width: float) -> void:
	var steps := 40
	var points := PackedVector2Array()
	for i in range(steps + 1):
		var a := TAU * float(i) / float(steps)
		points.append(Vector2(cos(a) * r, sin(a) * r * SQUASH))
	draw_polyline(points, col, width, true)
