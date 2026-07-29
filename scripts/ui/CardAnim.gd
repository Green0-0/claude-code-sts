class_name CardAnim
extends Control

## Plays a card being executed, and tells the caller when the blow lands.
##
## Three choreographies, all opening the same way — the card rises, spinning
## about its own vertical axis, fading toward transparency as it goes:
##
##   ATTACK  the ascent ends in a white flash; the card is gone, and reappears
##           above the target's head cocked like a hatchet before chopping down
##           into it. Impact is the violent beat: gashes, spatter, recoil, shake.
##   BLESS   a self-targeting status. The card settles back down instead, and
##           melts into its owner, spreading rings across them like a lake.
##   HEX     a hostile status. Identical to BLESS — deliberately, so it reads as
##           a blessing right up to the last moment — until the final descent,
##           where it drops like a stone and shatters into the victim.
##
## The caller supplies `on_impact`, invoked on the frame the effect actually
## lands so the rules resolve in time with the picture rather than before it.

signal finished

enum Kind {ATTACK, BLESS, HEX}

const CARD_SCENE := preload("res://scenes/CardView.tscn")

## Set false by the headless harnesses and the click tests, which assert on state
## the instant they act and cannot wait ~0.8s for a flourish.
static var enabled: bool = true

## How high the card climbs, and how long each beat takes.
const RISE := 150.0
const RISE_TIME := 0.42
const CHOP_TIME := 0.11
const SETTLE_TIME := 0.34
## The card shrinks to this before the strike, so it lands as a thrown blade
## rather than a billboard falling on the target.
const BLADE_SCALE := 0.52

## How many flights are in the air right now. A count rather than a flag, because
## cards no longer wait their turn: the player can throw a second one while the
## first is still climbing, and each flight owns nothing but its own ghost.
var _active: int = 0


func is_running() -> bool:
	return _active > 0


func active_count() -> int:
	return _active


## card may be null for an enemy move, in which case `label` is drawn instead.
##
## Callers may await this or ignore it. Ignoring it is the normal case: the impact
## callback is what carries the rules, so nothing downstream needs the flight to
## be over.
func play(card: Card, combat, label: String, tint: Color, from_pos: Vector2,
		target_rect: Rect2, kind: int, on_impact: Callable) -> void:
	if not enabled:
		if on_impact.is_valid():
			on_impact.call()
		finished.emit()
		return
	_active += 1
	var ghost := _make_ghost(card, combat, label, tint)
	add_child(ghost)
	ghost.position = from_pos
	await _run(ghost, target_rect, kind, tint, on_impact)
	if is_instance_valid(ghost):
		ghost.queue_free()
	_active = max(0, _active - 1)
	finished.emit()


## Drops everything still in the air and forgets it was ever counted. Called when
## a fight ends: a card mid-flight and its damage numbers must not hang over the
## next encounter.
func abort() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_active = 0


func _run(ghost: Control, target_rect: Rect2, kind: int, tint: Color,
		on_impact: Callable) -> void:
	await _ascend(ghost, kind)
	match kind:
		Kind.ATTACK:
			await _execute(ghost, target_rect, on_impact)
		Kind.HEX:
			await _descend(ghost, target_rect, true)
			await _shatter(ghost, target_rect, on_impact)
		_:
			await _descend(ghost, target_rect, false)
			await _melt(ghost, target_rect, tint, on_impact)


# ══════════════════════════════════ Beats ════════════════════════════════════
## The shared opening: a soft, mellow climb, turning side to side.
##
## The card keeps its upright pose throughout — the spin is about its vertical
## axis, so it is scale.x that swings through zero, not rotation.
func _ascend(ghost: Control, kind: int) -> void:
	var base := ghost.scale.y
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(ghost, "position:y", ghost.position.y - RISE, RISE_TIME)
	t.tween_property(ghost, "modulate:a", 0.35 if kind == Kind.ATTACK else 0.55,
			RISE_TIME)
	t.tween_property(ghost, "scale:y", base * 1.06, RISE_TIME)
	# Two full turns on the way up.
	t.tween_method(func(a: float): ghost.scale.x = base * cos(a),
			0.0, TAU * 2.0, RISE_TIME)
	await t.finished


## The card discorporates in a bloom of white and is gone.
func _vanish(ghost: Control) -> void:
	var centre := ghost.position + ghost.size * ghost.scale * 0.5
	CombatFx.spawn(self, centre, CombatFx.Kind.FLASH, Color(1, 1, 1), 120.0, 0.30)
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.tween_property(ghost, "modulate:a", 0.0, 0.10)
	t.tween_property(ghost, "scale", ghost.scale * 1.25, 0.10)
	await t.finished
	ghost.visible = false


## ATTACK: reappear over the target, hang for a breath, then bury itself in it.
func _execute(ghost: Control, target_rect: Rect2, on_impact: Callable) -> void:
	await _vanish(ghost)

	# Smaller for the strike than it was in the hand: at full size it reads as a
	# billboard dropping on the target rather than a blade being thrown into it.
	ghost.scale = Vector2.ONE * BLADE_SCALE
	var card_size := ghost.size * ghost.scale
	var overhead := Vector2(
			target_rect.position.x + target_rect.size.x * 0.5 - card_size.x * 0.5,
			target_rect.position.y - card_size.y * 0.75)
	# Keep the wind-up on screen; a target near the top of the view would
	# otherwise cock back out of frame.
	overhead.y = maxf(overhead.y, 12.0)
	ghost.position = overhead
	ghost.scale.x = absf(ghost.scale.x)
	ghost.rotation = deg_to_rad(-38.0)     # cocked back, ready to swing
	ghost.modulate.a = 0.0
	ghost.visible = true

	# Snaps into existence rather than fading in: it should feel sudden.
	var appear := ghost.create_tween()
	appear.set_parallel(true)
	appear.tween_property(ghost, "modulate:a", 1.0, 0.07)
	appear.tween_property(ghost, "position:y", overhead.y - 16.0, 0.14) \
			.set_ease(Tween.EASE_OUT)
	await appear.finished

	# The chop. Fast, straight down, rotating through the stroke.
	var impact_point := target_rect.position + target_rect.size * Vector2(0.5, 0.42)
	var chop := ghost.create_tween()
	chop.set_parallel(true)
	chop.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUINT)
	chop.tween_property(ghost, "position",
			impact_point - Vector2(card_size.x * 0.5, card_size.y * 0.35), CHOP_TIME)
	chop.tween_property(ghost, "rotation", deg_to_rad(24.0), CHOP_TIME)
	await chop.finished

	if on_impact.is_valid():
		on_impact.call()
	CombatFx.spawn(self, impact_point, CombatFx.Kind.SLASH,
			Color(0.85, 0.09, 0.13), maxf(70.0, target_rect.size.x * 0.55), 0.45, 5)
	CombatFx.spawn(self, impact_point, CombatFx.Kind.FLASH,
			Color(1, 0.93, 0.93), 90.0, 0.18, 4)

	# The card buries itself and is left behind.
	var bury := ghost.create_tween()
	bury.set_parallel(true)
	bury.tween_property(ghost, "modulate:a", 0.0, 0.22)
	bury.tween_property(ghost, "position:y", ghost.position.y + 26.0, 0.22)
	bury.tween_property(ghost, "scale", ghost.scale * 0.82, 0.22)
	await bury.finished


## BLESS / HEX share this descent. The hex version arrives faster and lower,
## the tell that something is wrong coming only at the very end.
func _descend(ghost: Control, target_rect: Rect2, hostile: bool) -> void:
	var card_size := ghost.size * ghost.scale
	var above := Vector2(
			target_rect.position.x + target_rect.size.x * 0.5 - card_size.x * 0.5,
			target_rect.position.y - card_size.y * 0.55)
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(ghost, "position", above, SETTLE_TIME)
	t.tween_property(ghost, "modulate:a", 0.8, SETTLE_TIME)
	t.tween_method(func(a: float): ghost.scale.x = absf(ghost.scale.y) * cos(a),
			PI, TAU, SETTLE_TIME)
	await t.finished
	if hostile:
		# A half-beat of hesitation, so the drop that follows lands as a betrayal.
		await get_tree().create_timer(0.06).timeout


## BLESS: the card sinks into its owner and spreads out across them.
func _melt(ghost: Control, target_rect: Rect2, tint: Color, on_impact: Callable) -> void:
	var centre := target_rect.position + target_rect.size * Vector2(0.5, 0.45)
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	t.tween_property(ghost, "position:y", centre.y - ghost.size.y * 0.1, 0.26)
	t.tween_property(ghost, "scale:y", ghost.scale.y * 0.12, 0.26)  # melts flat
	t.tween_property(ghost, "modulate:a", 0.0, 0.26)
	await t.finished

	if on_impact.is_valid():
		on_impact.call()
	var soft := Color(tint.r, tint.g, tint.b).lightened(0.35)
	CombatFx.spawn(self, centre, CombatFx.Kind.RIPPLE, soft,
			maxf(80.0, target_rect.size.x * 0.62), 0.72, 3)
	await get_tree().create_timer(0.22).timeout


## HEX: the mask comes off. It drops hard and breaks over the victim.
func _shatter(ghost: Control, target_rect: Rect2, on_impact: Callable) -> void:
	var centre := target_rect.position + target_rect.size * Vector2(0.5, 0.45)
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	t.tween_property(ghost, "position:y", centre.y - ghost.size.y * 0.2, 0.10)
	t.tween_property(ghost, "scale", ghost.scale * Vector2(1.15, 0.9), 0.10)
	t.tween_property(ghost, "modulate", Color(0.75, 0.6, 0.95, 0.95), 0.10)
	await t.finished

	if on_impact.is_valid():
		on_impact.call()
	CombatFx.spawn(self, centre, CombatFx.Kind.CRACK, Color(0.93, 0.88, 1.0),
			maxf(85.0, target_rect.size.x * 0.7), 0.55, 5)
	CombatFx.spawn(self, centre, CombatFx.Kind.FLASH, Color(0.8, 0.7, 1.0),
			70.0, 0.20, 4)

	var gone := ghost.create_tween()
	gone.set_parallel(true)
	gone.tween_property(ghost, "modulate:a", 0.0, 0.18)
	gone.tween_property(ghost, "scale:y", ghost.scale.y * 0.2, 0.18)
	await gone.finished


# ══════════════════════════════════ Ghosts ═══════════════════════════════════
## The flying object. A real CardView for a played card so it matches what the
## player just clicked; a compact stand-in for an enemy move, which has no card.
func _make_ghost(card: Card, combat, label: String, tint: Color) -> Control:
	if card != null:
		var view: CardView = CARD_SCENE.instantiate()
		view.interactive = false
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.scale = Vector2.ONE * 0.8
		view.pivot_offset = CardView.CARD_SIZE * 0.5
		view.setup(card, combat)
		return view
	return _make_move_token(label, tint)


func _make_move_token(label: String, tint: Color) -> Control:
	var root := Panel.new()
	root.custom_minimum_size = Vector2(150, 96)
	root.size = Vector2(150, 96)
	root.pivot_offset = Vector2(75, 48)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint.darkened(0.45)
	sb.border_color = tint.lightened(0.3)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	root.add_theme_stylebox_override("panel", sb)

	var text := Label.new()
	text.text = label
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	text.add_theme_constant_override("outline_size", 4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(text)
	return root
