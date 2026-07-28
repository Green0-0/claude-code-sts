class_name CardFxLayer
extends Control

## Plays a card's execution: the flight of the card itself, and the mark it
## leaves. Purely cosmetic — Combat has already decided what happens, this only
## decides how long it takes to look like it happened.
##
## Three routines, all opening the same way so the third can lie about which one
## you are watching:
##
##   ATTACK   the card rises weightless and lit, hangs, then comes down like a
##            thrown hatchet: hard stop, screen kick, gash, shockwave.
##   BLESSING the card rises the same way, then settles and melts into the
##            target, which rings outward like a struck pond.
##   CURSE    opens as BLESSING, note for note, until the last of the descent —
##            then drops the pretence, snaps down, and breaks the target like a
##            mirror.

signal finished

enum Mode { ATTACK, BLESSING, CURSE }

## The ascent both honest routines share, and the one the curse imitates.
const RISE_TIME := 0.42
const RISE_HEIGHT := 132.0
const HANG_TIME := 0.07

## Attack: short, so the strike reads as sudden after the drifting ascent.
const STRIKE_TIME := 0.13
const HITSTOP := 0.07

## Blessing: long and eased, the opposite of the strike.
const SETTLE_TIME := 0.5
const MELT_TIME := 0.26

## Curse: how far into the settle the mask comes off, and how fast it falls.
const BETRAYAL_AT := 0.72
const SNAP_TIME := 0.085

var _busy := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_busy() -> bool:
	return _busy


## Runs one execution and returns when the mark has faded. `card` may be null,
## in which case the plate is drawn from `label` and `colour` alone (that is the
## enemy path — an enemy's move has no Card behind it).
func execute(mode: int, from: Vector2, to: Vector2, colour: Color,
		label: String, target_size: Vector2) -> void:
	_busy = true
	var plate := _make_plate(label, colour)
	plate.position = from - plate.size * 0.5
	add_child(plate)

	match mode:
		Mode.ATTACK:
			await _run_attack(plate, from, to, colour, target_size)
		Mode.BLESSING:
			await _run_blessing(plate, from, to, colour, target_size)
		Mode.CURSE:
			await _run_curse(plate, from, to, colour, target_size)

	if is_instance_valid(plate):
		plate.queue_free()
	_busy = false
	finished.emit()


# ═════════════════════════════════ Routines ══════════════════════════════════
## Ethereal ascent. Weight comes off the card: it drifts up, pales, swells and
## turns slightly, easing out so it looks like it is being lifted rather than
## thrown.
func _ascend(plate: Control, from: Vector2, duration: float, to_alpha: float) -> void:
	var apex := from + Vector2(0, -RISE_HEIGHT)
	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(plate, "position", apex - plate.size * 0.5, duration)
	t.tween_property(plate, "scale", Vector2.ONE * 1.16, duration)
	t.tween_property(plate, "modulate", Color(1.25, 1.25, 1.3, to_alpha), duration)
	t.tween_property(plate, "rotation", randf_range(-0.09, 0.09), duration)
	await t.finished


func _run_attack(plate: Control, from: Vector2, to: Vector2, colour: Color,
		target_size: Vector2) -> void:
	await _ascend(plate, from, RISE_TIME, 0.55)
	await _wait(HANG_TIME)

	# The strike: everything the ascent gave away comes back at once. Eased IN,
	# so it is still accelerating when it arrives.
	var strike := create_tween()
	strike.set_parallel(true)
	strike.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	strike.tween_property(plate, "position", to - plate.size * 0.5, STRIKE_TIME)
	strike.tween_property(plate, "scale", Vector2(0.72, 0.72), STRIKE_TIME)
	strike.tween_property(plate, "modulate", Color(1.6, 1.5, 1.5, 1.0), STRIKE_TIME)
	strike.tween_property(plate, "rotation", randf_range(0.5, 0.9), STRIKE_TIME)
	await strike.finished

	plate.visible = false
	_kick(11.0)
	_spawn(CardFx.Kind.SLASH, to, colour.lightened(0.35), target_size, 0.36)
	_spawn(CardFx.Kind.IMPACT, to, colour.lightened(0.5), target_size, 0.3)
	_spawn(CardFx.Kind.SHARDS, to, colour.lightened(0.2), target_size, 0.45)
	# Hitstop: the whole screen holds still for a frame or two, which is what
	# sells the blow as having connected with something solid.
	await _wait(HITSTOP)
	await _wait(0.24)


func _run_blessing(plate: Control, from: Vector2, to: Vector2, colour: Color,
		target_size: Vector2) -> void:
	await _ascend(plate, from, RISE_TIME * 1.1, 0.62)
	await _settle(plate, to, 1.0)
	await _melt(plate, colour, to, target_size)


func _run_curse(plate: Control, from: Vector2, to: Vector2, colour: Color,
		target_size: Vector2) -> void:
	# Beat for beat the blessing, so there is nothing to read yet.
	await _ascend(plate, from, RISE_TIME * 1.1, 0.62)
	await _settle(plate, to, BETRAYAL_AT)

	# The tell, and then it drops. Eased IN and much faster than the descent it
	# was doing a moment ago.
	var snap := create_tween()
	snap.set_parallel(true)
	snap.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	snap.tween_property(plate, "position", to - plate.size * 0.5, SNAP_TIME)
	snap.tween_property(plate, "scale", Vector2(0.62, 0.62), SNAP_TIME)
	snap.tween_property(plate, "modulate", Color(1.0, 0.72, 1.0, 0.95), SNAP_TIME)
	snap.tween_property(plate, "rotation", randf_range(-0.35, 0.35), SNAP_TIME)
	await snap.finished

	plate.visible = false
	_kick(7.0)
	var cursed := colour.lerp(Color(0.85, 0.6, 1.0), 0.55)
	_spawn(CardFx.Kind.CRACK, to, cursed, target_size, 0.5)
	_spawn(CardFx.Kind.SHARDS, to, cursed.lightened(0.25), target_size, 0.5)
	await _wait(0.34)


## The soft descent the two status routines share. `fraction` stops it short,
## which is how the curse gets to bail out part-way down.
func _settle(plate: Control, to: Vector2, fraction: float) -> void:
	var landing := plate.position.lerp(to - plate.size * 0.5, fraction)
	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(plate, "position", landing, SETTLE_TIME * fraction)
	t.tween_property(plate, "scale", Vector2.ONE.lerp(Vector2(0.92, 0.92), fraction),
			SETTLE_TIME * fraction)
	t.tween_property(plate, "rotation", 0.0, SETTLE_TIME * fraction)
	await t.finished


## Melting: it loses height faster than width, as though soaking in, and the
## ripple starts before it has finished going.
func _melt(plate: Control, colour: Color, to: Vector2, target_size: Vector2) -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	t.tween_property(plate, "scale", Vector2(1.05, 0.08), MELT_TIME)
	t.tween_property(plate, "modulate", Color(1.4, 1.4, 1.5, 0.0), MELT_TIME)
	t.tween_property(plate, "position",
			Vector2(plate.position.x, to.y - plate.size.y * 0.1), MELT_TIME)
	_spawn(CardFx.Kind.RIPPLE, to, colour.lightened(0.45), target_size, 0.75)
	await t.finished
	await _wait(0.4)


# ═════════════════════════════════ Helpers ═══════════════════════════════════
## The flying card. Deliberately not a real CardView: at speed it is a shape and
## a colour, and a simplified plate reads better in motion than a wall of text.
func _make_plate(label: String, colour: Color) -> Control:
	var plate := Panel.new()
	plate.custom_minimum_size = Vector2(132, 182)
	plate.size = Vector2(132, 182)
	plate.pivot_offset = plate.size * 0.5
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = colour.darkened(0.35)
	sb.border_color = colour.lightened(0.45)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	plate.add_theme_stylebox_override("panel", sb)

	var text := Label.new()
	text.text = label
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_color", Color(1, 1, 1))
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	text.add_theme_constant_override("outline_size", 4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(text)
	return plate


func _spawn(kind: int, at: Vector2, colour: Color, target_size: Vector2,
		duration: float) -> CardFx:
	var fx := CardFx.new()
	fx.kind = kind
	fx.tint = colour
	fx.extent = target_size
	fx.seed_value = randi()
	fx.position = at
	add_child(fx)
	var t := create_tween()
	t.tween_method(fx.set_progress, 0.0, 1.0, duration)
	t.tween_callback(fx.queue_free)
	return fx


## A short positional shove on whatever contains us, so a hit is felt outside
## the frame it happens in. Restores exactly, so it cannot drift.
func _kick(strength: float) -> void:
	var host := get_parent() as Control
	if host == null:
		return
	var home := host.position
	var t := create_tween()
	for i in range(5):
		var falloff := strength * (1.0 - float(i) / 5.0)
		t.tween_property(host, "position",
				home + Vector2(randf_range(-falloff, falloff),
						randf_range(-falloff, falloff)), 0.035)
	t.tween_property(host, "position", home, 0.05)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# ═════════════════════════════ Choosing a routine ════════════════════════════
## Which of the three a card gets. An Attack strikes; anything else blesses or
## curses depending on which way it is pointed — a debuff aimed at someone else
## is the one that lies about it.
static func mode_for(card: Card, hostile: bool) -> int:
	if card != null and card.type() == "attack":
		return Mode.ATTACK
	return Mode.CURSE if hostile else Mode.BLESSING


## The same question for an enemy's move, which has an intent rather than a type.
static func mode_for_intent(intent_kind: String) -> int:
	if intent_kind.begins_with("attack"):
		return Mode.ATTACK
	if intent_kind in ["debuff", "strong_debuff"]:
		return Mode.CURSE
	return Mode.BLESSING
