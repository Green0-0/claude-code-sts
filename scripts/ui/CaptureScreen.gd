extends Control

## The throw. Hold the ball, drag, swerve, let go, and try to put it through the
## middle of something that does not want to be there.
##
## This is the screen the whole capture overhaul exists for. Combat hands it one
## enemy; it zooms in on that enemy, gives it its own movement algorithm (see
## PokeMotion — every type moves differently, dual types blend), and hands the
## player a physical ball with real inertia and real spin. Where the ball lands
## matters: dead centre is worth nearly twice a careless throw (PokeCapture's
## accuracy tiers), and a ball thrown with a swerve on it is worth more again.
##
## Resistance is what ties it back to the fight. A fresh, healthy, rare target
## moves fast and wide, dodges most throws, and gives up on you after two of them.
## The same target at a sliver of health with a status on it moves feebly, sags,
## barely bothers to dodge, and will stand there all afternoon. Wearing something
## down is therefore not an abstract percentage — it is visible in how hard it is
## to hit.
##
## Everything is drawn rather than imported: the ball is two half-discs, a band and
## a button, and the target ring is three arcs. That keeps the screen in the same
## vector idiom as CombatFx and means there is nothing to import.

signal finished(result: Dictionary)

# ═══════════════════════════════════ Physics ═════════════════════════════════
## Gravity on the ball, in pixels per second squared. Generous, so an underpowered
## throw visibly falls short instead of drifting.
const GRAVITY := 1150.0
## How fast the ball travels away from the camera. A throw covers the gap to the
## target plane in a little under half a second.
const DEPTH_SPEED := 2.35
## Sideways acceleration a fully spun throw gets. This is the swerve.
const CURVE_ACCEL := 900.0
## Spin below this is not a curve, just a wobble, and earns no bonus.
const CURVE_THRESHOLD := 0.32
## Air resistance, applied per second.
const DRAG := 0.62
## How much of the ball's size survives the trip to the target plane.
const DEPTH_SCALE := 0.34
## Minimum upward flick that counts as a throw at all.
const MIN_THROW_SPEED := 320.0
## Depth at which the target decides whether to get out of the way. Late enough
## that the dodge reads as a reaction rather than a prediction.
const DODGE_AT_DEPTH := 0.45

const HAND_RADIUS := 38.0
const BALL_LAYER_Z := 40


# ══════════════════════════════════ The ball ═════════════════════════════════
## A Poke Ball, drawn: a coloured upper half, a pale lower half, a dark band and
## the button. `open_amount` splits it for the moment it swallows something or
## bursts back open.
class BallNode extends Control:
	var tint: Color = Color(0.86, 0.28, 0.28)
	var radius: float = 34.0
	var open_amount: float = 0.0
	var glow: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_open(v: float) -> void:
		open_amount = clampf(v, 0.0, 1.0)
		queue_redraw()

	func set_glow(v: float) -> void:
		glow = v
		queue_redraw()

	func _half(from_angle: float, to_angle: float, offset: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var steps := 26
		for i in range(steps + 1):
			var a: float = lerpf(from_angle, to_angle, float(i) / float(steps))
			pts.append(Vector2(cos(a), sin(a)) * radius + offset)
		return pts

	func _draw() -> void:
		var split := radius * open_amount
		var band := Color(0.10, 0.09, 0.13)
		if glow > 0.0:
			draw_circle(Vector2.ZERO, radius * (1.5 + glow * 0.8),
					Color(1.0, 0.95, 0.7, 0.22 * glow))
		# Upper shell, in the ball's own colour.
		draw_colored_polygon(_half(PI, TAU, Vector2(0.0, -split)), tint)
		# Lower shell, pale.
		draw_colored_polygon(_half(0.0, PI, Vector2(0.0, split * 0.7)),
				Color(0.93, 0.93, 0.95))
		# The seam, and the button on it.
		if open_amount < 0.05:
			draw_line(Vector2(-radius, 0.0), Vector2(radius, 0.0), band, radius * 0.19)
			draw_circle(Vector2.ZERO, radius * 0.28, band)
			draw_circle(Vector2.ZERO, radius * 0.19, Color(0.96, 0.96, 0.98))
			# A highlight, so it reads as a sphere rather than a disc.
			draw_circle(Vector2(-radius * 0.34, -radius * 0.42), radius * 0.16,
					Color(1, 1, 1, 0.35))
		else:
			draw_line(Vector2(-radius, -split), Vector2(radius, -split), band,
					radius * 0.16)
			draw_line(Vector2(-radius, split * 0.7), Vector2(radius, split * 0.7),
					band, radius * 0.16)
			# Whatever is inside, spilling out.
			draw_circle(Vector2.ZERO, radius * (0.4 + open_amount * 0.9),
					Color(1.0, 0.98, 0.85, 0.55 * open_amount))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 2.0, true)


## The target ring: the sweet spot made visible.
##
## Three arcs at the exact ratios PokeCapture scores against, so what the player
## is aiming at and what the maths rewards are the same thing rather than two
## approximations of each other. Its overall size is the species' difficulty: a
## Rattata gets a wide ring, a legendary a narrow one.
class HaloNode extends Control:
	var radius: float = 140.0
	var pulse: float = 0.0
	var sweet: float = 1.0
	var tint: Color = Color(0.85, 0.85, 0.9)
	var dimmed: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_pulse(v: float) -> void:
		pulse = v
		queue_redraw()

	func _draw() -> void:
		var breathe := 1.0 + sin(pulse * 2.1) * 0.022
		var fade := 1.0 - dimmed
		# The outer boundary: outside this, a throw simply misses.
		draw_arc(Vector2.ZERO, radius * sweet * breathe, 0.0, TAU, 72,
				Color(tint.r, tint.g, tint.b, 0.30 * fade), 2.0, true)
		for tier in PokeCapture.ACCURACY_TIERS:
			var ratio := float(tier["ratio"])
			if ratio >= 1.0:
				continue
			var c: Color = tier["color"]
			c.a = 0.72 * fade
			draw_arc(Vector2.ZERO, radius * sweet * ratio * breathe, 0.0, TAU, 64, c,
					2.4, true)
		# Crosshair ticks, so the centre is findable even over a busy sprite.
		var tick := radius * sweet * 0.1
		var cc := Color(1, 1, 1, 0.45 * fade)
		draw_line(Vector2(-tick, 0), Vector2(tick, 0), cc, 1.5, true)
		draw_line(Vector2(0, -tick), Vector2(0, tick), cc, 1.5, true)


# ═══════════════════════════════════ State ══════════════════════════════════
var veil: ColorRect = null
var arena: Control = null
var halo: HaloNode = null
var mon: TextureRect = null
var mon_fallback: Label = null
var fx_layer: Control = null
var ball_layer: Control = null
var hand_ball: BallNode = null
var banner: Label = null
var caption: Label = null
var info_panel: Panel = null
var info_name: Label = null
var info_hp: ProgressBar = null
var info_hp_label: Label = null
var info_resist: ProgressBar = null
var info_resist_label: Label = null
var info_odds: Label = null
var info_patience: Label = null
var rack: VBoxContainer = null
var leave_button: Button = null
var hint_label: Label = null

## The target, as Combat described it (see Combat.capture_context).
var context: Dictionary = {}
var resistance: float = 1.0
var profile: Dictionary = {}
var mon_base_size: Vector2 = Vector2(200, 200)

var active: bool = false
var _clock: float = 0.0
var _seed: int = 0
var _rng := RandomNumberGenerator.new()

## Where the target is right now, relative to the arena centre, and how it looks.
var _mon_offset: Vector2 = Vector2.ZERO
var _mon_scale: float = 1.0
var _mon_alpha: float = 1.0

## A dodge in progress: out and back over its own duration.
var _dodge_vec: Vector2 = Vector2.ZERO
var _dodge_alpha: float = 1.0
var _dodge_scale: float = 1.0
var _dodge_left: float = 0.0
var _dodge_total: float = 0.0
var _dodges: int = 0

## The bag, the ball in hand, and how much patience is left.
var selected_ball: String = ""
var patience_left: int = 0
var throws: int = 0
var _resolving: bool = false
var _finished: bool = false

## The throw in progress.
var _dragging: bool = false
var _drag_samples: Array = []      ## [{pos: Vector2, t: float}]
var _flight: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	set_process(false)


# ══════════════════════════════════ Building ═════════════════════════════════
func _build() -> void:
	veil = ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.05, 0.05, 0.09, 1.0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	arena = Control.new()
	arena.name = "Arena"
	arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arena)

	halo = HaloNode.new()
	halo.name = "Halo"
	arena.add_child(halo)

	mon = TextureRect.new()
	mon.name = "Mon"
	mon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(mon)

	# Without the sprite pack installed there is still something to aim at.
	mon_fallback = Label.new()
	mon_fallback.name = "MonGlyph"
	mon_fallback.add_theme_font_size_override("font_size", 96)
	mon_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mon_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mon_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mon_fallback.visible = false
	arena.add_child(mon_fallback)

	fx_layer = Control.new()
	fx_layer.name = "Fx"
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)

	ball_layer = Control.new()
	ball_layer.name = "BallLayer"
	ball_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	ball_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ball_layer.z_index = BALL_LAYER_Z
	add_child(ball_layer)

	hand_ball = BallNode.new()
	hand_ball.name = "HandBall"
	hand_ball.radius = HAND_RADIUS
	ball_layer.add_child(hand_ball)

	banner = Label.new()
	banner.name = "Banner"
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 108.0
	banner.offset_bottom = 168.0
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	banner.add_theme_constant_override("outline_size", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	add_child(banner)

	caption = Label.new()
	caption.name = "Caption"
	caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	caption.offset_top = 62.0
	caption.offset_bottom = 92.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", UiTheme.DIM)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)

	_build_info()
	_build_rack()

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -32.0
	hint_label.offset_bottom = -8.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", UiTheme.DIM)
	hint_label.text = "Hold the ball, drag, and flick — curve it round the dodge. Rings score the throw."
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)

	leave_button = Button.new()
	leave_button.text = "Back to the fight"
	leave_button.custom_minimum_size = Vector2(190, 42)
	leave_button.focus_mode = Control.FOCUS_NONE
	leave_button.pressed.connect(_on_leave)
	add_child(leave_button)


func _build_info() -> void:
	info_panel = Panel.new()
	info_panel.name = "Info"
	info_panel.custom_minimum_size = Vector2(330, 222)
	info_panel.size = Vector2(330, 222)
	info_panel.add_theme_stylebox_override("panel", UiTheme.player_style())
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info_panel)

	info_name = Label.new()
	info_name.position = Vector2(14, 10)
	info_name.size = Vector2(302, 26)
	info_name.add_theme_font_size_override("font_size", 19)
	info_panel.add_child(info_name)

	info_hp = ProgressBar.new()
	info_hp.position = Vector2(14, 44)
	info_hp.size = Vector2(302, 18)
	info_hp.show_percentage = false
	info_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.style_hp_bar(info_hp)
	info_panel.add_child(info_hp)

	info_hp_label = Label.new()
	info_hp_label.position = Vector2(14, 44)
	info_hp_label.size = Vector2(302, 18)
	info_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_hp_label.add_theme_font_size_override("font_size", 12)
	info_panel.add_child(info_hp_label)

	# Resistance gets its own gauge, because it is the number the whole screen is
	# about: it is what the movement, the dodging and the patience all read from.
	info_resist_label = Label.new()
	info_resist_label.position = Vector2(14, 70)
	info_resist_label.size = Vector2(302, 20)
	info_resist_label.add_theme_font_size_override("font_size", 13)
	info_panel.add_child(info_resist_label)

	info_resist = ProgressBar.new()
	info_resist.position = Vector2(14, 94)
	info_resist.size = Vector2(302, 12)
	info_resist.custom_minimum_size = Vector2(302, 12)
	info_resist.max_value = 100.0
	info_resist.show_percentage = false
	info_resist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.13, 0.12, 0.18)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.92, 0.55, 0.42)
	fill.set_corner_radius_all(5)
	info_resist.add_theme_stylebox_override("background", bg)
	info_resist.add_theme_stylebox_override("fill", fill)
	info_panel.add_child(info_resist)

	info_odds = Label.new()
	info_odds.position = Vector2(14, 124)
	info_odds.size = Vector2(302, 62)
	info_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_odds.add_theme_font_size_override("font_size", 13)
	info_panel.add_child(info_odds)

	info_patience = Label.new()
	info_patience.position = Vector2(14, 190)
	info_patience.size = Vector2(302, 22)
	info_patience.add_theme_font_size_override("font_size", 13)
	info_panel.add_child(info_patience)


func _build_rack() -> void:
	rack = VBoxContainer.new()
	rack.name = "Rack"
	rack.add_theme_constant_override("separation", 3)
	rack.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(rack)


func _layout() -> void:
	var w: float = size.x if size.x > 0.0 else 1280.0
	var h: float = size.y if size.y > 0.0 else 720.0
	info_panel.position = Vector2(24, 92)
	rack.position = Vector2(w - 268.0, 92.0)
	rack.size = Vector2(244, h - 200.0)
	leave_button.position = Vector2(w - 214.0, h - 60.0)


func _arena_center() -> Vector2:
	var w: float = size.x if size.x > 0.0 else 1280.0
	var h: float = size.y if size.y > 0.0 else 720.0
	# High enough that there is room to throw from underneath.
	return Vector2(w * 0.5, h * 0.40)


func _hand_home() -> Vector2:
	var w: float = size.x if size.x > 0.0 else 1280.0
	var h: float = size.y if size.y > 0.0 else 720.0
	return Vector2(w * 0.5, h - 84.0)


# ═══════════════════════════════════ Opening ═════════════════════════════════
## Comes in on the target: the board darkens, the thing you clicked flies out of
## its slot in the enemy line and swells into the middle of the screen, and the
## ring snaps shut around it.
##
## `ctx` is Combat.capture_context() plus a `rect` giving where on screen the
## target currently is, which is what makes the zoom land on the right thing.
func open(ctx: Dictionary) -> void:
	context = ctx.duplicate()
	_finished = false
	_resolving = false
	throws = 0
	_dodges = 0
	_clock = 0.0
	_flight = {}
	_dragging = false
	_drag_samples.clear()
	_dodge_left = 0.0
	_dodge_vec = Vector2.ZERO
	_dodge_alpha = 1.0
	_dodge_scale = 1.0
	_mon_alpha = 1.0
	_mon_scale = 1.0
	_mon_offset = Vector2.ZERO

	var mon_def: Dictionary = context.get("mon", {})
	var types: Array = context.get("types", [])
	resistance = float(context.get("resistance", 1.0))
	profile = PokeMotion.for_types(types)
	_seed = int(mon_def.get("id", 1)) * 31 + int(context.get("hp", 1))
	_rng = RandomNumberGenerator.new()
	_rng.seed = Run.rng.randi()

	selected_ball = _default_ball()
	patience_left = PokeCapture.patience(resistance,
			int(PokeBalls.handling(selected_ball)["patience"]))

	_layout()
	visible = true
	banner.visible = false

	# The ring is the species' difficulty made visible.
	var rate := clampf(float(mon_def.get("capture_rate", 45)) / 255.0, 0.02, 1.0)
	halo.radius = lerpf(92.0, 188.0, pow(rate, 0.45))
	halo.sweet = float(PokeBalls.handling(selected_ball)["sweet"])
	halo.tint = PokeData.type_color(String(types[0])) if not types.is_empty() \
			else Color(0.8, 0.8, 0.85)
	halo.dimmed = 0.0
	halo.position = _arena_center()

	# The sprite, sized so it sits comfortably inside the widest possible ring.
	var tex: Texture2D = PokeSprites.texture_for(String(mon_def.get("name", "")))
	mon.texture = tex
	mon.visible = tex != null
	mon_fallback.visible = tex == null
	if tex != null:
		var native := Vector2(tex.get_width(), tex.get_height())
		var scale_to: float = 236.0 / maxf(1.0, native.y)
		mon_base_size = native * scale_to
	else:
		mon_base_size = Vector2(200, 200)
		mon_fallback.text = "◈"
		mon_fallback.modulate = halo.tint
		mon_fallback.size = mon_base_size
		mon_fallback.pivot_offset = mon_base_size * 0.5
	mon.size = mon_base_size
	mon.pivot_offset = mon_base_size * 0.5
	mon.modulate = Color(1, 1, 1, 1)
	mon_fallback.modulate.a = 1.0

	hand_ball.tint = PokeBalls.color_of(selected_ball)
	hand_ball.set_open(0.0)
	hand_ball.set_glow(0.0)
	hand_ball.position = _hand_home()
	hand_ball.scale = Vector2.ONE
	hand_ball.rotation = 0.0
	hand_ball.visible = true

	_refresh_rack()
	_refresh_info()
	_update_mon_transform()

	var from_rect: Rect2 = context.get("rect",
			Rect2(_arena_center() - Vector2(80, 100), Vector2(160, 200)))
	await _play_intro(from_rect)
	active = true
	set_process(true)


## Which ball to start with: the cheapest thing in the bag that is actually good
## against this target, so the rack opens on a sensible answer rather than on
## whatever happens to be first.
func _default_ball() -> String:
	var counts := Run.ball_counts()
	if counts.is_empty():
		return "poke"
	var best := ""
	var best_score := -1.0
	for id in counts:
		var bid := String(id)
		var mult := PokeBalls.multiplier(bid, context)
		# Value per Gold, so a Net Ball that happens to be right beats a hoarded
		# Master Ball as the opening suggestion.
		var score := mult / maxf(20.0, float(PokeBalls.price_of(bid)))
		if score > best_score:
			best_score = score
			best = bid
	return best if best != "" else String(counts.keys()[0])


func _play_intro(from_rect: Rect2) -> void:
	var center := _arena_center()
	var local_from := get_global_transform().affine_inverse() * from_rect.position
	var from_center := local_from + from_rect.size * 0.5

	veil.color.a = 0.0
	var target: Control = mon if mon.visible else mon_fallback
	# Starts at the size it was in the enemy line, so the swell is the zoom.
	var start_scale: float = clampf(from_rect.size.y / maxf(1.0, mon_base_size.y),
			0.25, 1.2)
	target.scale = Vector2.ONE * start_scale
	target.position = from_center - mon_base_size * 0.5
	target.modulate.a = 1.0
	halo.scale = Vector2.ONE * 2.4
	halo.dimmed = 1.0
	info_panel.modulate.a = 0.0
	rack.modulate.a = 0.0
	hand_ball.modulate.a = 0.0
	caption.modulate.a = 0.0
	leave_button.modulate.a = 0.0

	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(veil, "color:a", 0.94, 0.34)
	t.tween_property(target, "position", center - mon_base_size * 0.5, 0.42)
	t.tween_property(target, "scale", Vector2.ONE, 0.42) \
			.set_trans(Tween.TRANS_BACK)
	# The ring closes in from outside the frame — the shutter of the transition.
	t.tween_property(halo, "scale", Vector2.ONE, 0.38).set_delay(0.1)
	t.tween_method(func(v: float): halo.dimmed = v, 1.0, 0.0, 0.3).set_delay(0.16)
	t.tween_property(info_panel, "modulate:a", 1.0, 0.28).set_delay(0.24)
	t.tween_property(rack, "modulate:a", 1.0, 0.28).set_delay(0.24)
	t.tween_property(caption, "modulate:a", 1.0, 0.28).set_delay(0.24)
	t.tween_property(leave_button, "modulate:a", 1.0, 0.28).set_delay(0.24)
	t.tween_property(hand_ball, "modulate:a", 1.0, 0.24).set_delay(0.3)
	# Speed lines converging, so the zoom has some air behind it.
	CombatFx.spawn(fx_layer, center, CombatFx.Kind.RIPPLE, halo.tint, 340.0, 0.55, 2)
	CombatFx.spawn(fx_layer, center, CombatFx.Kind.FLASH, Color(1, 1, 1), 200.0, 0.3, 2)
	await t.finished


# ═════════════════════════════════ The rack ══════════════════════════════════
## What is in the bag, grouped the way the shop groups it, each row carrying what
## that ball is worth *against this target* — which for most of them is the whole
## decision.
func _refresh_rack() -> void:
	for child in rack.get_children():
		rack.remove_child(child)
		child.queue_free()
	var counts := Run.ball_counts()
	var title := Label.new()
	title.text = "The bag — %d" % Run.total_balls()
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	rack.add_child(title)
	if counts.is_empty():
		var empty := Label.new()
		empty.text = "Nothing left to throw."
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", UiTheme.DIM)
		rack.add_child(empty)
		return

	var last_category := ""
	for id in counts:
		var bid := String(id)
		var category := PokeBalls.category_of(bid)
		if category != last_category:
			last_category = category
			var heading := Label.new()
			heading.text = String(PokeBalls.CATEGORY_NAMES.get(category, category))
			heading.add_theme_font_size_override("font_size", 11)
			heading.add_theme_color_override("font_color", UiTheme.DIM)
			rack.add_child(heading)
		rack.add_child(_make_rack_row(bid, int(counts[bid])))


func _make_rack_row(bid: String, held: int) -> Button:
	var d := PokeBalls.get_def(bid)
	var mult := PokeBalls.multiplier(bid, context)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(238, 38)
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 12)
	var mark := "▸ " if bid == selected_ball else "   "
	btn.text = "%s%s %s  ×%d   %.1f×" % [mark, String(d["glyph"]), String(d["name"]),
			held, mult]
	btn.add_theme_color_override("font_color",
			UiTheme.GOLD if bid == selected_ball else PokeBalls.rarity_color(bid))
	var note := PokeBalls.condition_note(bid, context)
	btn.tooltip_text = "%s\n%s%s" % [String(d["desc"]),
			"%.2f× against this one." % mult, "\n" + note if note != "" else ""]
	btn.pressed.connect(func(): _select_ball(bid))
	return btn


func _select_ball(bid: String) -> void:
	if _resolving or _finished or Run.ball_count(bid) <= 0:
		return
	selected_ball = bid
	hand_ball.tint = PokeBalls.color_of(bid)
	hand_ball.queue_redraw()
	halo.sweet = float(PokeBalls.handling(bid)["sweet"])
	halo.queue_redraw()
	_refresh_rack()
	_refresh_info()


# ══════════════════════════════════ The panel ════════════════════════════════
func _refresh_info() -> void:
	var mon_def: Dictionary = context.get("mon", {})
	var types: Array = context.get("types", [])
	var type_text := ""
	for t in types:
		type_text += ("/" if type_text != "" else "") + PokeData.display_name(String(t))
	info_name.text = "%s   %s" % [String(context.get("name", "?")), type_text]
	info_name.add_theme_color_override("font_color",
			PokeData.type_color(String(types[0])) if not types.is_empty()
			else Color.WHITE)

	var hp := int(context.get("hp", 1))
	var max_hp := int(context.get("max_hp", 1))
	info_hp.max_value = max(1, max_hp)
	info_hp.value = hp
	info_hp_label.text = "%d / %d HP" % [hp, max_hp]

	info_resist.value = resistance * 100.0
	info_resist_label.text = "Resistance — %s" % PokeCapture.describe_resistance(resistance)

	# The two ends of what a throw could be worth, so the ball choice can be made
	# on the numbers rather than on the name.
	var best := PokeCapture.throw_odds(selected_ball, context, 0.0, true)
	var worst := PokeCapture.throw_odds(selected_ball, context, 0.9, false)
	var note := PokeBalls.condition_note(selected_ball, context)
	info_odds.text = "%s — %s at best, %s at worst.%s" % [
			PokeBalls.display_name(selected_ball),
			PokeCapture.describe_odds(float(best["chance"])),
			PokeCapture.describe_odds(float(worst["chance"])),
			"\n" + note.capitalize() if note != "" else ""]
	info_patience.text = "It will put up with %d more throw(s)." % patience_left
	info_patience.add_theme_color_override("font_color",
			Color(0.92, 0.5, 0.45) if patience_left <= 1 else UiTheme.DIM)
	caption.text = PokeMotion.describe(types, resistance)


# ══════════════════════════════════ The loop ═════════════════════════════════
func _process(delta: float) -> void:
	if not active:
		return
	_clock += delta
	halo.set_pulse(_clock)
	if not _resolving:
		_step_motion(delta)
	_update_mon_transform()
	if not _flight.is_empty():
		_step_flight(delta)


## Where the target has got to. Pure sampling of its type's movement algorithm,
## plus whatever dodge is currently playing out on top of it.
func _step_motion(delta: float) -> void:
	var s := PokeMotion.sample(profile, _clock, _seed, resistance)
	_mon_offset = s["offset"]
	_mon_scale = float(s["scale"])
	_mon_alpha = float(s["alpha"])
	if _dodge_left > 0.0:
		_dodge_left = maxf(0.0, _dodge_left - delta)
		# Out and back, so a dodge is a movement rather than a teleport to a new
		# resting place.
		var p := 1.0 - (_dodge_left / maxf(0.001, _dodge_total))
		var swing := sin(clampf(p, 0.0, 1.0) * PI)
		_mon_offset += _dodge_vec * swing
		_mon_alpha *= lerpf(1.0, _dodge_alpha, swing)
		_mon_scale *= lerpf(1.0, _dodge_scale, swing)


func _mon_center() -> Vector2:
	return _arena_center() + _mon_offset


func _update_mon_transform() -> void:
	var target: Control = mon if mon.visible else mon_fallback
	var center := _mon_center()
	target.position = center - mon_base_size * 0.5
	target.scale = Vector2.ONE * _mon_scale
	target.modulate.a = _mon_alpha
	target.rotation = 0.0
	# The ring rides with the target: it is *its* sweet spot, not a fixed hoop.
	halo.position = center
	halo.scale = Vector2.ONE * _mon_scale


# ═════════════════════════════════ Throwing ══════════════════════════════════
func _gui_input(event: InputEvent) -> void:
	if not active or _resolving or _finished:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		else:
			_release_drag(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_sample_drag(event.position)


func _begin_drag(at: Vector2) -> void:
	if not _flight.is_empty():
		return
	if Run.ball_count(selected_ball) <= 0:
		_flash_banner("No %s left." % PokeBalls.display_name(selected_ball),
				Color(0.9, 0.5, 0.45))
		return
	# Anywhere in the lower half counts as reaching for the ball — hunting for a
	# 38-pixel disc with a mouse is not the game.
	var floor_y: float = (size.y if size.y > 0.0 else 720.0) * 0.55
	if at.y < floor_y and at.distance_to(hand_ball.position) > HAND_RADIUS * 2.4:
		return
	_dragging = true
	_drag_samples = [{"pos": at, "t": _clock}]
	hand_ball.position = at
	hand_ball.set_glow(0.45)


func _sample_drag(at: Vector2) -> void:
	hand_ball.position = at
	_drag_samples.append({"pos": at, "t": _clock})
	# Only the tail of the gesture matters; a long slow drag followed by a flick
	# should read as a flick.
	while _drag_samples.size() > 24:
		_drag_samples.pop_front()
	# A little roll in the hand, so the ball feels held rather than dragged.
	if _drag_samples.size() >= 2:
		var prev: Vector2 = _drag_samples[_drag_samples.size() - 2]["pos"]
		hand_ball.rotation += (at.x - prev.x) * 0.006


func _release_drag(at: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	hand_ball.set_glow(0.0)
	var throw := _measure_throw(at)
	if throw.is_empty():
		# Not a throw: a nudge. Put the ball back rather than spending it.
		var t := create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(hand_ball, "position", _hand_home(), 0.22)
		t.parallel().tween_property(hand_ball, "rotation", 0.0, 0.22)
		return
	if not Run.spend_ball(selected_ball):
		return
	throws += 1
	_launch(throw)
	_refresh_rack()
	_refresh_info()


## Reads the gesture: how hard it was thrown, in what direction, and with how much
## spin on it. Spin is the accumulated curvature of the drag path — a straight
## flick has none, a hooked one has a lot — which is what makes swerving a thing
## the hand does rather than a button.
func _measure_throw(at: Vector2) -> Dictionary:
	if _drag_samples.size() < 2:
		return {}
	var newest: Dictionary = _drag_samples[_drag_samples.size() - 1]
	var oldest: Dictionary = _drag_samples[0]
	# Walk back to roughly the last eighth of a second of the gesture.
	for i in range(_drag_samples.size() - 1, -1, -1):
		var s: Dictionary = _drag_samples[i]
		oldest = s
		if float(newest["t"]) - float(s["t"]) >= 0.12:
			break
	var span: float = maxf(0.016, float(newest["t"]) - float(oldest["t"]))
	var vel: Vector2 = (at - (oldest["pos"] as Vector2)) / span
	if vel.y > -MIN_THROW_SPEED * 0.35 or vel.length() < MIN_THROW_SPEED:
		return {}

	# Curvature: the signed area swept by consecutive segments of the drag.
	var spin := 0.0
	var weight := 0.0
	for i in range(2, _drag_samples.size()):
		var a: Vector2 = _drag_samples[i - 2]["pos"]
		var b: Vector2 = _drag_samples[i - 1]["pos"]
		var c: Vector2 = _drag_samples[i]["pos"]
		var d1 := b - a
		var d2 := c - b
		if d1.length() < 1.0 or d2.length() < 1.0:
			continue
		spin += d1.normalized().cross(d2.normalized())
		weight += 1.0
	if weight > 0.0:
		spin = clampf(spin * 3.0 / weight * 8.0, -1.0, 1.0)
	return {"vel": vel, "spin": spin, "from": at}


func _launch(throw: Dictionary) -> void:
	var node := BallNode.new()
	node.radius = HAND_RADIUS
	node.tint = PokeBalls.color_of(selected_ball)
	node.position = throw["from"]
	ball_layer.add_child(node)
	hand_ball.visible = false

	var handling := PokeBalls.handling(selected_ball)
	var vel: Vector2 = throw["vel"]
	_flight = {
		"node": node,
		"pos": throw["from"],
		"vel": vel * 0.55,
		"z": 0.0,
		# A hard throw arrives sooner. A heavy ball takes longer about it.
		"vz": DEPTH_SPEED * clampf(vel.length() / 900.0, 0.55, 1.5)
				/ maxf(0.4, float(handling["drag"])),
		"spin": float(throw["spin"]) * float(handling["curve"]),
		"ball": selected_ball,
		"dodged": false,
	}


## A synthesised throw, for the headless harness — which has no mouse to flick.
##
## Only the *gesture* is faked. The launch velocity is solved backwards from where
## the ball should land, so the aim can be dialled in; everything after that is
## the same flight, the same dodge roll, the same landing and the same shake
## sequence a played throw gets.
func throw_at_center(spin: float = 0.4, aim_error: float = 0.0) -> bool:
	if not active or _resolving or _finished or not _flight.is_empty():
		return false
	if Run.ball_count(selected_ball) <= 0 or not Run.spend_ball(selected_ball):
		return false
	throws += 1
	var from := _hand_home()
	var aim := _mon_center() + Vector2(
			(_rng.randf() * 2.0 - 1.0) * halo.radius * aim_error,
			(_rng.randf() * 2.0 - 1.0) * halo.radius * aim_error)
	var handling := PokeBalls.handling(selected_ball)
	var vz: float = DEPTH_SPEED * 1.15 / maxf(0.4, float(handling["drag"]))
	var flight_time := 1.0 / vz
	# The integral of DRAG^t over the flight: how far one unit of launch velocity
	# actually carries once the air has had its say.
	var carry := (1.0 - pow(DRAG, flight_time)) / -log(DRAG)
	var drop := 0.5 * GRAVITY * 0.78 * flight_time * flight_time
	var v0 := (aim - from + Vector2(0.0, -drop)) / maxf(0.001, carry)

	var node := BallNode.new()
	node.radius = HAND_RADIUS
	node.tint = PokeBalls.color_of(selected_ball)
	node.position = from
	ball_layer.add_child(node)
	hand_ball.visible = false
	_flight = {
		"node": node, "pos": from, "vel": v0, "z": 0.0, "vz": vz,
		"spin": clampf(spin, -1.0, 1.0) * float(handling["curve"]),
		"ball": selected_ball, "dodged": false,
	}
	_refresh_rack()
	_refresh_info()
	return true


func _step_flight(delta: float) -> void:
	var node: BallNode = _flight["node"]
	if node == null or not is_instance_valid(node):
		_flight = {}
		return
	var pos: Vector2 = _flight["pos"]
	var vel: Vector2 = _flight["vel"]
	var z := float(_flight["z"])
	var spin := float(_flight["spin"])

	z += float(_flight["vz"]) * delta
	# Gravity eases off with depth, so a good throw does not simply nose-dive.
	vel.y += GRAVITY * delta * (1.0 - 0.45 * z)
	# The swerve.
	vel.x += spin * CURVE_ACCEL * delta
	vel *= pow(DRAG, delta)
	pos += vel * delta

	_flight["pos"] = pos
	_flight["vel"] = vel
	_flight["z"] = z
	node.position = pos
	node.scale = Vector2.ONE * lerpf(1.0, DEPTH_SCALE, clampf(z, 0.0, 1.0))
	node.rotation += (spin * 7.0 + 3.2) * delta

	# The target gets its chance to move, once, and late.
	if not bool(_flight["dodged"]) and z >= DODGE_AT_DEPTH:
		_flight["dodged"] = true
		_maybe_dodge()

	if z >= 1.0:
		_resolve_landing()
		return
	var h: float = size.y if size.y > 0.0 else 720.0
	var w: float = size.x if size.x > 0.0 else 1280.0
	if pos.y > h + 120.0 or pos.x < -160.0 or pos.x > w + 160.0:
		_resolve_miss("It sails wide.")


## The target decides whether to get out of the way. Willingness is resistance:
## something spent barely tries, which is exactly why weakening it first is worth
## the turns it costs.
func _maybe_dodge() -> void:
	var chance := PokeMotion.dodge_chance(profile, resistance)
	if _rng.randf() >= chance:
		return
	var plan := PokeMotion.dodge_plan(profile, _rng, resistance, _dodges)
	_dodges += 1
	_dodge_vec = plan["offset"]
	_dodge_alpha = float(plan["alpha"])
	_dodge_scale = float(plan["scale"])
	_dodge_total = float(plan["time"]) * 2.0
	_dodge_left = _dodge_total
	_flash_banner("It %s!" % String(plan["note"]), Color(0.75, 0.82, 0.95), 0.7)


# ════════════════════════════════ Resolution ═════════════════════════════════
func _resolve_miss(why: String) -> void:
	var node: BallNode = _flight.get("node", null)
	_flight = {}
	if node != null and is_instance_valid(node):
		var t := node.create_tween()
		t.set_parallel(true)
		t.tween_property(node, "modulate:a", 0.0, 0.25)
		t.tween_property(node, "scale", node.scale * 0.6, 0.25)
		t.chain().tween_callback(node.queue_free)
	_flash_banner(why, Color(0.82, 0.82, 0.88))
	_spend_patience()


func _resolve_landing() -> void:
	var node: BallNode = _flight["node"]
	var ball := String(_flight["ball"])
	var spin := absf(float(_flight["spin"]))
	var landing: Vector2 = _flight["pos"]
	_flight = {}

	var center := _mon_center()
	# The sweet spot rides with the target and scales with it, so a shrinking,
	# tiring Pokemon really is an easier mark.
	var hit_radius: float = maxf(24.0, halo.radius * halo.sweet * _mon_scale)
	var ratio := landing.distance_to(center) / hit_radius
	if ratio > 1.0:
		_resolve_miss("Missed — it went past.")
		return

	var curved := spin >= CURVE_THRESHOLD
	var odds := PokeCapture.throw_odds(ball, context, ratio, curved)
	# Deliberately not awaited: this is reached from _process, and the sequence
	# from here on drives itself off `_resolving`.
	_play_capture(node, ball, odds, center)


## The bit that has to feel right: the ball opens, the target is drawn into it, it
## drops, and then it rattles once for every shake the games' own four-roll model
## grants — so a near miss really does wobble three times before it pops.
func _play_capture(node: BallNode, ball: String, odds: Dictionary,
		center: Vector2) -> void:
	_resolving = true
	var tier := String(odds["tier"])
	if tier != "":
		_flash_banner("%s!" % tier, odds["tier_color"], 0.8)
		CombatFx.spawn(fx_layer, center, CombatFx.Kind.FLASH, odds["tier_color"],
				_hit_radius_hint(), 0.3, 3)
	if bool(odds["curved"]):
		CombatFx.spawn(fx_layer, center, CombatFx.Kind.RIPPLE,
				Color(0.7, 0.9, 1.0), 150.0, 0.45, 2)

	# Open, and swallow.
	node.position = center
	node.set_open(1.0)
	node.set_glow(1.0)
	var target: Control = mon if mon.visible else mon_fallback
	var suck := create_tween()
	suck.set_parallel(true)
	suck.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	suck.tween_property(target, "position", center - mon_base_size * 0.5, 0.24)
	suck.tween_property(target, "scale", Vector2.ONE * 0.05, 0.24)
	suck.tween_property(target, "modulate", Color(2.2, 2.2, 2.4, 0.0), 0.24)
	await suck.finished
	node.set_open(0.0)
	node.set_glow(0.35)

	# Drop and settle.
	var floor_y := center.y + 132.0
	var fall := node.create_tween()
	fall.tween_property(node, "position:y", floor_y, 0.26) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall.tween_property(node, "position:y", floor_y - 26.0, 0.14) \
			.set_ease(Tween.EASE_OUT)
	fall.tween_property(node, "position:y", floor_y, 0.16) \
			.set_ease(Tween.EASE_IN)
	fall.parallel().tween_property(node, "rotation", 0.0, 0.4)
	await fall.finished

	var roll := PokeCapture.shake_rolls(float(odds["value"]), _rng)
	var shakes := int(roll["shakes"])
	for i in range(shakes):
		await _wobble(node, i)
	if bool(roll["caught"]):
		await _play_caught(node, ball, bool(roll["critical"]))
		return
	await _play_broke_free(node, target, center)


## Roughly how wide the sweet spot currently is, for sizing a flash over it.
func _hit_radius_hint() -> float:
	return maxf(70.0, halo.radius * halo.sweet * _mon_scale * 0.8)


func _wobble(node: BallNode, index: int) -> void:
	var side := 1.0 if index % 2 == 0 else -1.0
	var t := node.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(node, "rotation", deg_to_rad(22.0) * side, 0.16)
	t.tween_property(node, "rotation", 0.0, 0.18)
	t.parallel().tween_property(node, "position:x", node.position.x + 7.0 * side, 0.16)
	await t.finished
	CombatFx.spawn(fx_layer, node.position, CombatFx.Kind.FLASH,
			Color(1.0, 0.95, 0.8), 44.0, 0.16, 4)
	await get_tree().create_timer(0.22).timeout


func _play_caught(node: BallNode, ball: String, critical: bool) -> void:
	_flash_banner("Gotcha!" if not critical else "A critical capture!",
			Color(1.0, 0.86, 0.42), 1.4)
	halo.dimmed = 1.0
	for i in range(3):
		CombatFx.spawn(fx_layer, node.position, CombatFx.Kind.RIPPLE,
				Color(1.0, 0.92, 0.6), 120.0 + 60.0 * i, 0.6, 3)
		await get_tree().create_timer(0.12).timeout
	CombatFx.spawn(fx_layer, node.position, CombatFx.Kind.FLASH,
			Color(1, 1, 1), 180.0, 0.4, 5)
	var t := node.create_tween()
	t.tween_property(node, "scale", node.scale * 1.25, 0.14)
	t.tween_property(node, "scale", node.scale, 0.2)
	await t.finished
	await get_tree().create_timer(0.45).timeout

	var species := String((context.get("mon", {}) as Dictionary).get("name", ""))
	var level := PokeCapture.joining_level(Run.player_level) + PokeBalls.join_bonus(ball)
	_close({
		"caught": true,
		"species": species,
		"level": clampi(level, PokeLevels.MIN_LEVEL, PokeLevels.MAX_LEVEL),
		"healed": PokeBalls.heals_on_catch(ball),
		"ball": ball,
		"spent_turn": true,
	})


func _play_broke_free(node: BallNode, target: Control, center: Vector2) -> void:
	node.set_open(1.0)
	CombatFx.spawn(fx_layer, node.position, CombatFx.Kind.CRACK,
			Color(1.0, 0.9, 0.75), 120.0, 0.45, 4)
	var burst := node.create_tween()
	burst.set_parallel(true)
	burst.tween_property(node, "modulate:a", 0.0, 0.3)
	burst.tween_property(node, "scale", node.scale * 1.5, 0.3)
	burst.chain().tween_callback(node.queue_free)

	# It comes back out where it went in, and lands angry.
	target.position = node.position - mon_base_size * 0.5
	target.scale = Vector2.ONE * 0.2
	target.modulate = Color(1.6, 1.6, 1.8, 1.0)
	var back := create_tween()
	back.set_parallel(true)
	back.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	back.tween_property(target, "position", center - mon_base_size * 0.5, 0.3)
	back.tween_property(target, "scale", Vector2.ONE, 0.3)
	back.tween_property(target, "modulate", Color(1, 1, 1, 1), 0.3)
	await back.finished
	halo.dimmed = 0.0
	_flash_banner("It broke free!", Color(0.95, 0.55, 0.45), 1.0)
	_resolving = false
	_spend_patience()


## Every throw that fails costs the target's patience. When it runs out, it stops
## paying you any attention and the attempt is over — which is the pressure that
## makes a bad throw cost something.
func _spend_patience() -> void:
	_resolving = false
	hand_ball.visible = true
	hand_ball.position = _hand_home()
	hand_ball.rotation = 0.0
	hand_ball.modulate.a = 1.0
	patience_left -= 1
	_refresh_info()
	if patience_left <= 0:
		_flash_banner("It has lost interest in you.", Color(0.85, 0.8, 0.7), 1.2)
		await get_tree().create_timer(0.9).timeout
		_close({"caught": false, "spent_turn": true, "reason": "patience"})
		return
	if Run.total_balls() <= 0:
		_flash_banner("The bag is empty.", Color(0.85, 0.8, 0.7), 1.2)
		await get_tree().create_timer(0.9).timeout
		_close({"caught": false, "spent_turn": true, "reason": "no_balls"})
		return
	if Run.ball_count(selected_ball) <= 0:
		# Reach for the next best thing rather than making the player do it.
		_select_ball(_default_ball())


func _on_leave() -> void:
	if _resolving or _finished:
		return
	# Walking away without throwing costs nothing: Capture is always *offered*, so
	# looking at the odds should not be a trap.
	_close({"caught": false, "spent_turn": throws > 0, "reason": "left"})


func _close(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	active = false
	set_process(false)
	_dragging = false
	if not _flight.is_empty():
		var node = _flight.get("node", null)
		if node != null and is_instance_valid(node):
			node.queue_free()
		_flight = {}
	# Pulls back out the way it came in.
	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(veil, "color:a", 0.0, 0.26)
	t.tween_property(arena, "modulate:a", 0.0, 0.22)
	t.tween_property(info_panel, "modulate:a", 0.0, 0.18)
	t.tween_property(rack, "modulate:a", 0.0, 0.18)
	t.tween_property(caption, "modulate:a", 0.0, 0.18)
	t.tween_property(leave_button, "modulate:a", 0.0, 0.18)
	t.tween_property(hand_ball, "modulate:a", 0.0, 0.18)
	await t.finished
	visible = false
	arena.modulate.a = 1.0
	banner.visible = false
	for child in fx_layer.get_children():
		child.queue_free()
	for child in ball_layer.get_children():
		if child != hand_ball:
			child.queue_free()
	finished.emit(result)


# ══════════════════════════════════ Banner ═══════════════════════════════════
func _flash_banner(text: String, tint: Color, hold: float = 0.55) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", tint)
	banner.visible = true
	banner.modulate.a = 1.0
	banner.scale = Vector2(0.86, 0.86)
	banner.pivot_offset = banner.size * 0.5
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(banner, "scale", Vector2.ONE, 0.18)
	t.tween_interval(hold)
	t.tween_property(banner, "modulate:a", 0.0, 0.3)


func request_close() -> bool:
	if not visible or _resolving or _finished:
		return false
	_on_leave()
	return true
