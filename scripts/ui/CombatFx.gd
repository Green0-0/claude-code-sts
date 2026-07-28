class_name CombatFx
extends Control

## One-shot drawn effect. Everything is vector work in _draw() driven by a single
## 0..1 progress value, so there are no shaders, no textures and nothing to
## import — and each effect is legible as the geometry it actually is.
##
##   ripple   concentric rings spreading over a surface, like a stone in a lake
##   crack    a broken-mirror star, for a curse landing on its victim
##   slash    the hatchet stroke and burst of an execution
##   flash    a soft white bloom, for the moment a card discorporates

enum Kind {RIPPLE, CRACK, SLASH, FLASH}

var kind: int = Kind.RIPPLE
var tint: Color = Color(1, 1, 1)
var radius: float = 90.0
var progress: float = 0.0 : set = _set_progress
var seed_value: int = 0

var _rng := RandomNumberGenerator.new()


func _set_progress(v: float) -> void:
	progress = v
	queue_redraw()


## Runs the effect to completion and frees itself.
static func spawn(parent: Control, at: Vector2, effect_kind: int, effect_tint: Color,
		effect_radius: float, duration: float, z: int = 0) -> CombatFx:
	var fx := CombatFx.new()
	fx.kind = effect_kind
	fx.tint = effect_tint
	fx.radius = effect_radius
	fx.seed_value = randi()
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.z_index = z
	fx.position = at
	fx.size = Vector2.ZERO
	parent.add_child(fx)
	var t := fx.create_tween()
	t.tween_property(fx, "progress", 1.0, duration)
	t.tween_callback(fx.queue_free)
	return fx


func _draw() -> void:
	_rng.seed = seed_value
	match kind:
		Kind.RIPPLE: _draw_ripple()
		Kind.CRACK: _draw_crack()
		Kind.SLASH: _draw_slash()
		Kind.FLASH: _draw_flash()


## Three rings chasing each other outward, each fading as it goes — the surface
## of a lake taking a soft landing.
func _draw_ripple() -> void:
	for i in range(3):
		var offset := float(i) * 0.22
		var p := progress - offset
		if p <= 0.0 or p >= 1.0:
			continue
		var r := radius * (0.15 + 0.85 * p)
		var a := (1.0 - p) * 0.85
		var c := tint
		c.a = a
		# Flattened, because the surface is being viewed at an angle.
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, c, 2.5 + 2.0 * (1.0 - p), true)
		draw_arc(Vector2.ZERO, r * 0.98, 0.0, TAU, 48, Color(c.r, c.g, c.b, a * 0.3), 6.0, true)


## A star of jagged fractures with a bright core, plus a few shards falling away.
func _draw_crack() -> void:
	var grow: float = minf(1.0, progress * 3.0)      # snaps open, then lingers
	var fade := 1.0 - maxf(0.0, (progress - 0.55) / 0.45)
	var spokes := 9
	for i in range(spokes):
		var ang := TAU * float(i) / float(spokes) + _rng.randf_range(-0.18, 0.18)
		var len := radius * grow * _rng.randf_range(0.55, 1.0)
		# Each fracture kinks once, which is what makes it read as glass rather
		# than a starburst.
		var kink := ang + _rng.randf_range(-0.35, 0.35)
		var mid := Vector2(cos(ang), sin(ang)) * len * 0.55
		var tip := mid + Vector2(cos(kink), sin(kink)) * len * 0.45
		var c := tint
		c.a = fade
		draw_line(Vector2.ZERO, mid, c, 3.0, true)
		draw_line(mid, tip, c, 2.0, true)
		# Cross-fractures joining neighbouring spokes.
		if i % 2 == 0:
			var ang2 := TAU * float((i + 1) % spokes) / float(spokes)
			var mid2 := Vector2(cos(ang2), sin(ang2)) * len * 0.5
			draw_line(mid, mid2, Color(c.r, c.g, c.b, fade * 0.5), 1.5, true)
	var core := Color(1, 1, 1, fade * 0.9)
	draw_circle(Vector2.ZERO, radius * 0.09 * grow, core)


## The stroke itself, then the wound: two crossing gashes and a burst thrown
## outward and down from the point of impact.
func _draw_slash() -> void:
	var open: float = minf(1.0, progress * 2.6)
	var fade := 1.0 - maxf(0.0, (progress - 0.4) / 0.6)
	var len := radius * 1.15

	# Two crossing gashes, the second a beat behind the first.
	for i in range(2):
		var p: float = clampf((progress - float(i) * 0.10) * 3.2, 0.0, 1.0)
		if p <= 0.0:
			continue
		var ang := deg_to_rad(-58.0 if i == 0 else -122.0)
		var dir := Vector2(cos(ang), sin(ang))
		var half := dir * len * 0.5
		var c := Color(1, 1, 1, fade)
		draw_line(-half, -half + (half * 2.0) * p, c, 7.0 - 3.0 * float(i), true)
		draw_line(-half, -half + (half * 2.0) * p,
				Color(tint.r, tint.g, tint.b, fade * 0.8), 3.0, true)

	# Spatter: wedges thrown out along the stroke, drooping under gravity.
	var drops := 12
	for i in range(drops):
		var ang := _rng.randf_range(-PI, PI)
		var dist := radius * open * _rng.randf_range(0.3, 1.25)
		var pos := Vector2(cos(ang), sin(ang)) * dist
		pos.y += radius * 0.55 * progress * progress    # falls as it travels
		var r := _rng.randf_range(2.0, 6.0) * (1.0 - progress * 0.5)
		draw_circle(pos, r, Color(tint.r, tint.g, tint.b, fade * 0.9))


## A soft bloom, brightest at the centre.
func _draw_flash() -> void:
	var p := progress
	var r := radius * (0.4 + 1.1 * p)
	var a := (1.0 - p) * (1.0 - p)
	for i in range(5):
		var f := float(i) / 5.0
		draw_circle(Vector2.ZERO, r * (1.0 - f * 0.72),
				Color(tint.r, tint.g, tint.b, a * 0.30))
