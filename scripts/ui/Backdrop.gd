extends Control

## The dungeon behind everything, drawn rather than painted.
##
## The brief is a dark fairytale that is cute rather than grim: a storybook you
## would not want to be inside. That comes from three cheap layers, all drawn in
## code because this project ships no image assets —
##
##   1. a vertical wash from plum to near-black, so the screen has a floor and a
##      sky rather than being a flat sheet;
##   2. a vignette that closes the corners in, which is what makes a scene feel
##      enclosed;
##   3. slow-drifting motes — embers, spores, will-o-wisps — that keep the frame
##      alive without ever asking to be looked at.
##
## Nothing here reacts to gameplay, so it never competes with the cards.

## The wash. Warm at the bottom, cold and deep at the top: a hell that is lit
## from below.
const SKY := Color(0.086, 0.063, 0.129)
const HORIZON := Color(0.180, 0.098, 0.180)
const FLOOR := Color(0.055, 0.043, 0.078)

## Vignette strength and how far in it reaches.
const VIGNETTE := 0.55
const VIGNETTE_START := 0.45

## Motes are the only moving part, so they are kept slow and few.
const MOTE_COUNT := 46
const MOTE_SPEED := Vector2(9.0, -15.0)
const MOTE_COLORS := [
	Color(0.98, 0.72, 0.82),   # rose
	Color(0.72, 0.62, 0.98),   # violet
	Color(0.98, 0.86, 0.62),   # candlelight
	Color(0.62, 0.92, 0.84),   # witch-light
]

var _motes: Array = []
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_seed_motes()
	set_process(true)


func _seed_motes() -> void:
	_motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED   # fixed, so the backdrop is identical every run
	for i in range(MOTE_COUNT):
		_motes.append({
			"pos": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(1.2, 3.4),
			"color": MOTE_COLORS[rng.randi_range(0, MOTE_COLORS.size() - 1)],
			"alpha": rng.randf_range(0.18, 0.55),
			# Each drifts at its own rate, so they never move as a sheet.
			"drift": rng.randf_range(0.45, 1.4),
			"phase": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	# 1. The wash, as a stack of bands. Cheaper than a gradient texture and it
	#    costs nothing to retune.
	var bands := 48
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var col: Color
		if t < 0.62:
			col = SKY.lerp(HORIZON, t / 0.62)
		else:
			col = HORIZON.lerp(FLOOR, (t - 0.62) / 0.38)
		draw_rect(Rect2(0.0, h * t, w, h / float(bands) + 1.0), col)

	# 2. Motes, drifting up and swaying.
	for m in _motes:
		var base: Vector2 = m["pos"]
		var drift: float = m["drift"]
		var x := fposmod(base.x * w + MOTE_SPEED.x * _time * drift
				+ sin(_time * 0.4 * drift + m["phase"]) * 14.0, w)
		var y := fposmod(base.y * h + MOTE_SPEED.y * _time * drift, h)
		# A soft body with a fainter halo reads as glow without a shader.
		var col: Color = m["color"]
		var pulse: float = 0.75 + 0.25 * sin(_time * 1.1 * drift + m["phase"])
		var a: float = float(m["alpha"]) * pulse
		draw_circle(Vector2(x, y), float(m["radius"]) * 2.6,
				Color(col.r, col.g, col.b, a * 0.16))
		draw_circle(Vector2(x, y), float(m["radius"]), Color(col.r, col.g, col.b, a))

	# 3. Vignette: concentric rounded frames darkening toward the edge.
	var steps := 14
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		var inset := lerpf(minf(w, h) * VIGNETTE_START, 0.0, t)
		var a := VIGNETTE * pow(t, 2.2) / float(steps) * 6.0
		draw_rect(Rect2(inset * 0.5, inset * 0.5, w - inset, h - inset),
				Color(0.02, 0.01, 0.04, a), false, maxf(1.0, inset * 0.06))
