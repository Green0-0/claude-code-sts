class_name GlassCrackFx
extends Control

## A cursed mirror breaking over the target: a hard white flash, jagged cracks
## racing out from the point of impact with smaller branches splitting off them,
## and glass shards tumbling away.
##
## Used when a hostile status card drops its gentle disguise at the last moment.

const SPOKES := 13
const BRANCH_CHANCE := 0.75
const SHARDS := 10

var duration: float = 0.85
var extent: Rect2 = Rect2(0, 0, 190, 250)
var tint: Color = Color(0.85, 0.92, 1.0)

var _t: float = 0.0
var _cracks: Array = []        ## Array[PackedVector2Array] in local space
var _shards: Array = []        ## {poly, vel, spin, angle}
var _rng := RandomNumberGenerator.new()
var _frame: Control = null   ## the clipping frame that owns this effect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_build()
	set_process(true)


## The break is confined to the target's own card, so it reads as that card
## shattering rather than a starburst thrown over the whole board.
##
## Control.clip_contents only clips a node's *children*, never its own _draw, so
## the effect is parented inside a clipping frame cut to the target's rect. The
## frame owns the lifetime and goes when the effect does.
static func spawn(parent: Control, at: Rect2, seed_value: int = 0) -> GlassCrackFx:
	var frame := Control.new()
	frame.position = at.position
	frame.size = at.size
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)

	var fx := GlassCrackFx.new()
	fx.extent = Rect2(Vector2.ZERO, at.size)
	if seed_value != 0:
		fx._rng.seed = seed_value
	frame.add_child(fx)
	fx.position = at.size * 0.5
	fx._frame = frame
	return fx


## Cracks are generated once, then revealed over time, so they look like a single
## fracture propagating rather than a new pattern every frame.
func _build() -> void:
	var reach: float = maxf(extent.size.x, extent.size.y) * 0.55
	var angles: Array = []
	for i in range(SPOKES):
		var base_angle := TAU * float(i) / float(SPOKES) + _rng.randf_range(-0.22, 0.22)
		angles.append(base_angle)
		_cracks.append(_crack_line(Vector2.ZERO, base_angle, reach, 3))
		if _rng.randf() < BRANCH_CHANCE:
			# Branches leave the spoke partway along it, as real fractures do.
			var along := _rng.randf_range(0.35, 0.7)
			var origin := Vector2(cos(base_angle), sin(base_angle)) * reach * along
			var off := base_angle + _rng.randf_range(0.5, 1.1) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_cracks.append(_crack_line(origin, off, reach * 0.45, 2))

	# Rings joining neighbouring spokes. Radial lines alone read as scratches;
	# it is the rings between them that make it a broken mirror.
	for ring in [0.4, 0.72]:
		var web := PackedVector2Array()
		for a in angles:
			var r: float = reach * ring * _rng.randf_range(0.82, 1.18)
			web.append(_clamp_in(Vector2(cos(a), sin(a)) * r))
		web.append(web[0])
		_cracks.append(web)

	for i in range(SHARDS):
		var a := _rng.randf_range(0.0, TAU)
		var d := _rng.randf_range(10.0, reach * 0.5)
		var centre := Vector2(cos(a), sin(a)) * d
		var poly := PackedVector2Array()
		var size := _rng.randf_range(5.0, 13.0)
		for k in range(3):
			var pa := TAU * float(k) / 3.0 + _rng.randf_range(-0.4, 0.4)
			poly.append(centre + Vector2(cos(pa), sin(pa)) * size)
		_shards.append({
			"poly": poly,
			"vel": Vector2(cos(a), sin(a)) * _rng.randf_range(60.0, 170.0) + Vector2(0, -40.0),
			"spin": _rng.randf_range(-7.0, 7.0),
		})


## A jagged run of segments that wanders as it travels outward, held inside the
## card. The break belongs to the target's own face, so nothing may spill past
## its edges — and cracks that run right to the edge are what a shattered pane
## looks like anyway.
func _crack_line(from: Vector2, angle: float, length: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array([_clamp_in(from)])
	var cursor := from
	var dir := angle
	for i in range(segments):
		dir += _rng.randf_range(-0.34, 0.34)
		cursor += Vector2(cos(dir), sin(dir)) * (length / float(segments))
		pts.append(_clamp_in(cursor))
	return pts


func _clamp_in(p: Vector2) -> Vector2:
	var half := extent.size * 0.5
	return Vector2(clampf(p.x, -half.x, half.x), clampf(p.y, -half.y, half.y))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= duration:
		# Take the clipping frame with us.
		if _frame != null and is_instance_valid(_frame):
			_frame.queue_free()
		else:
			queue_free()


func _draw() -> void:
	var p: float = clampf(_t / duration, 0.0, 1.0)

	# The flash is over almost before it starts — it is what sells the impact.
	if p < 0.16:
		var f := 1.0 - p / 0.16
		draw_rect(Rect2(-extent.size * 0.5, extent.size),
				Color(1, 1, 1, f * 0.55), true)

	# Cracks race out over the first third, then linger and fade.
	var grow: float = clampf(p / 0.3, 0.0, 1.0)
	var fade: float = 1.0 if p < 0.55 else 1.0 - (p - 0.55) / 0.45
	for crack in _cracks:
		_draw_partial(crack, grow, Color(0, 0, 0, 0.75 * fade), 4.0)
		_draw_partial(crack, grow, Color(tint.r, tint.g, tint.b, 0.95 * fade), 1.8)

	# Shards tumble away under gravity.
	for s in _shards:
		var travel: float = _t
		var offset: Vector2 = _clamp_in(s["vel"] * travel + Vector2(0, 320.0 * travel * travel * 0.5))
		var angle: float = s["spin"] * travel
		var poly := PackedVector2Array()
		for v in s["poly"]:
			poly.append((v as Vector2).rotated(angle) + offset)
		draw_colored_polygon(poly, Color(tint.r, tint.g, tint.b, 0.7 * (1.0 - p)))


## Draws the first `amount` of a polyline, interpolating the final segment so the
## crack grows smoothly instead of snapping vertex to vertex.
func _draw_partial(pts: PackedVector2Array, amount: float, col: Color, width: float) -> void:
	if pts.size() < 2 or amount <= 0.0:
		return
	var span := float(pts.size() - 1) * amount
	var whole := int(floor(span))
	var out := PackedVector2Array()
	for i in range(min(whole + 1, pts.size())):
		out.append(pts[i])
	if whole + 1 < pts.size():
		out.append(pts[whole].lerp(pts[whole + 1], span - float(whole)))
	if out.size() >= 2:
		draw_polyline(out, col, width, true)
