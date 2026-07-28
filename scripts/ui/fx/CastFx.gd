class_name CastFx
extends Control

## Plays the execution animation for a card or an enemy move.
##
## Three routines, chosen by what the card actually does:
##
##   ATTACK   the sigil ascends softly, alpha climbing, and hangs above the
##            target — then drops in a hard chop, landing as a gash with a
##            white bloom and thrown blood.
##   BLESSING (a status the caster puts on itself) the same ascent, then a slow
##            descent, melting flat into the target and spreading rings across
##            it like the surface of a lake.
##   CURSE    (a status put on somebody else) wears the blessing's clothes —
##            the same ascent, the same soft descent — until the last of the
##            landing, where it drops sharply instead and shatters the target
##            like a cursed mirror.
##
## Everything here is cosmetic and fire-and-forget: nothing waits on it and
## nothing reads back from it, so combat resolves at its own pace and the
## headless harnesses are unaffected.

const KIND_ATTACK := "attack"
const KIND_BLESSING := "blessing"
const KIND_CURSE := "curse"

const SIGIL_SIZE := Vector2(104, 142)

## Where the sigil hangs before it comes down, relative to the target.
const HOVER_HEIGHT := 132.0

var _rng := RandomNumberGenerator.new()
var _target_node: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


## Drops anything still in flight. Sigils are freed by a tween callback, so a
## combat that ends mid-cast would otherwise leave them hanging over the next.
func clear_all() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


# ═══════════════════════════════ Classification ══════════════════════════════
## Which routine a cast should use. Anything that deals damage is an attack;
## after that it comes down to who the effect lands on.
static func classify(effects: Array, source_is_player: bool, on_self: bool) -> String:
	for eff in effects:
		var op := String(eff.get("op", ""))
		if op in ["damage", "damage_random", "poke_damage", "divider", "multi_stab",
				"transient_attack"]:
			return KIND_ATTACK
	return KIND_BLESSING if on_self else KIND_CURSE


## Works out, from an effect list, whether the cast lands on the caster.
static func targets_self(effects: Array, card_target: String) -> bool:
	if card_target in ["self", "none"]:
		return true
	var any := false
	for eff in effects:
		var mode := String(eff.get("target", "default"))
		if mode != "self":
			return false
		any = true
	return any


# ═══════════════════════════════════ Play ════════════════════════════════════
## from_pos and target_rect are in this layer's coordinates. target_node is the
## view that gets shaken on impact, and may be null.
func play(kind: String, label: String, colour: Color, from_pos: Vector2,
		target_rect: Rect2, target_node: Control = null) -> void:
	_target_node = target_node
	var sigil := _make_sigil(label, colour)
	add_child(sigil)
	sigil.position = from_pos - SIGIL_SIZE * 0.5
	sigil.modulate = Color(1, 1, 1, 0.0)
	sigil.scale = Vector2(0.72, 0.72)

	var centre := target_rect.get_center()
	match kind:
		KIND_ATTACK:
			_play_attack(sigil, colour, centre, target_rect)
		KIND_CURSE:
			_play_curse(sigil, colour, centre, target_rect)
		_:
			_play_blessing(sigil, colour, centre, target_rect)


## The ascent every routine opens with: a soft, mellow climb, alpha coming up
## from nothing. Deliberately unhurried — it is the inhale before the strike.
func _ascend(sigil: Control, tw: Tween, to: Vector2, seconds: float) -> void:
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sigil, "position", to - SIGIL_SIZE * 0.5, seconds)
	tw.tween_property(sigil, "modulate:a", 0.92, seconds * 0.7)
	tw.tween_property(sigil, "scale", Vector2(0.95, 0.95), seconds)
	tw.chain()
	tw.set_parallel(false)


func _play_attack(sigil: Control, colour: Color, centre: Vector2, rect: Rect2) -> void:
	var hover := Vector2(centre.x, rect.position.y - HOVER_HEIGHT)
	var tw := create_tween()
	_ascend(sigil, tw, hover + Vector2(0, 46.0), 0.42)

	# Hangs for a beat, tilting into the angle it will come down at.
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sigil, "position", hover - SIGIL_SIZE * 0.5, 0.16)
	tw.tween_property(sigil, "rotation", -0.42, 0.16)
	tw.tween_property(sigil, "scale", Vector2(1.05, 1.05), 0.16)
	tw.chain()

	# The chop. Fast, accelerating, straight through the target.
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(sigil, "position",
			centre - SIGIL_SIZE * 0.5 + Vector2(0, 12), 0.11)
	tw.tween_property(sigil, "rotation", 0.55, 0.11)
	tw.tween_property(sigil, "scale", Vector2(1.22, 0.86), 0.11)
	tw.chain()
	tw.set_parallel(false)
	tw.tween_callback(func(): _impact_attack(sigil, centre, rect))


func _impact_attack(sigil: Control, centre: Vector2, rect: Rect2) -> void:
	# Sized off the short edge, so an effect never sprawls past the card it hit.
	SlashFx.spawn(self, centre, _footprint(rect) * 1.15, _rng.randi())
	# The sigil is spent: it blows apart with the blow rather than settling.
	var out := create_tween()
	out.set_parallel(true)
	out.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	out.tween_property(sigil, "modulate:a", 0.0, 0.14)
	out.tween_property(sigil, "scale", Vector2(1.6, 0.4), 0.14)
	out.chain()
	out.tween_callback(sigil.queue_free)
	_shake(_target_node, 9.0)


func _play_blessing(sigil: Control, colour: Color, centre: Vector2, rect: Rect2) -> void:
	var hover := Vector2(centre.x, rect.position.y - HOVER_HEIGHT * 0.72)
	var tw := create_tween()
	_ascend(sigil, tw, hover, 0.46)

	# Sinks the whole way down, gently, dimming as it goes.
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sigil, "position", centre - SIGIL_SIZE * 0.5, 0.5)
	tw.tween_property(sigil, "modulate:a", 0.6, 0.5)
	tw.chain()

	# Melts: flattens onto the target and spreads out as it goes.
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(sigil, "scale", Vector2(1.35, 0.06), 0.26)
	tw.tween_property(sigil, "modulate:a", 0.0, 0.26)
	tw.tween_property(sigil, "position",
			centre - Vector2(SIGIL_SIZE.x * 0.5, 0), 0.26)
	tw.chain()
	tw.set_parallel(false)
	tw.tween_callback(func():
		sigil.queue_free()
		RippleFx.spawn(self, centre, colour.lightened(0.45), _footprint(rect) * 0.62))


func _play_curse(sigil: Control, colour: Color, centre: Vector2, rect: Rect2) -> void:
	var hover := Vector2(centre.x, rect.position.y - HOVER_HEIGHT * 0.72)
	var tw := create_tween()
	_ascend(sigil, tw, hover, 0.46)

	# Everything a blessing does — but it stops three-quarters of the way down.
	var feint := centre - Vector2(0, (centre.y - hover.y) * 0.28)
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sigil, "position", feint - SIGIL_SIZE * 0.5, 0.38)
	tw.tween_property(sigil, "modulate:a", 0.62, 0.38)
	tw.chain()

	# The drop the feint was hiding.
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(sigil, "position", centre - SIGIL_SIZE * 0.5, 0.09)
	tw.tween_property(sigil, "scale", Vector2(0.88, 1.28), 0.09)
	tw.tween_property(sigil, "modulate:a", 1.0, 0.05)
	tw.chain()
	tw.set_parallel(false)
	tw.tween_callback(func(): _impact_curse(sigil, centre, rect))


func _impact_curse(sigil: Control, centre: Vector2, rect: Rect2) -> void:
	CrackFx.spawn(self, centre, Color(0.86, 0.90, 1.0),
			_footprint(rect) * 0.62, _rng.randi())
	var out := create_tween()
	out.set_parallel(true)
	out.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	out.tween_property(sigil, "modulate:a", 0.0, 0.16)
	out.tween_property(sigil, "scale", Vector2(1.3, 1.3), 0.16)
	out.chain()
	out.tween_callback(sigil.queue_free)
	_shake(_target_node, 5.0)


## Effects are sized off the target's short edge, so nothing ever sprawls past
## the card it is supposed to have landed on.
func _footprint(rect: Rect2) -> float:
	return minf(rect.size.x, rect.size.y)


## Rattles the struck view and puts it back exactly where it started, so this
## can never fight the enemy-row layout for ownership of a position.
func _shake(node: Control, amount: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var base: Vector2 = node.position
	var tw := node.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var swings := 5
	for i in range(swings):
		var falloff := amount * (1.0 - float(i) / float(swings))
		var offset := Vector2(_rng.randf_range(-falloff, falloff),
				_rng.randf_range(-falloff * 0.6, falloff * 0.6))
		tw.tween_property(node, "position", base + offset, 0.035)
	tw.tween_property(node, "position", base, 0.05)


# ═══════════════════════════════════ Sigil ═══════════════════════════════════
## The flying card. Not a real CardView — at this size the rules text is
## unreadable anyway, and one panel per cast is far cheaper than a card scene.
func _make_sigil(label: String, colour: Color) -> Control:
	var root := Control.new()
	root.custom_minimum_size = SIGIL_SIZE
	root.size = SIGIL_SIZE
	root.pivot_offset = SIGIL_SIZE * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var glow := Panel.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -7
	glow.offset_top = -7
	glow.offset_right = 7
	glow.offset_bottom = 7
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(colour.r, colour.g, colour.b, 0.28)
	gsb.set_corner_radius_all(18)
	gsb.shadow_color = Color(colour.r, colour.g, colour.b, 0.55)
	gsb.shadow_size = 16
	glow.add_theme_stylebox_override("panel", gsb)
	root.add_child(glow)

	var body := Panel.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour.darkened(0.45)
	sb.border_color = colour.lightened(0.4)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(13)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 7
	body.add_theme_stylebox_override("panel", sb)
	root.add_child(body)

	var text := Label.new()
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.text = label
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 13 if label.length() < 16 else 11)
	text.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	text.add_theme_constant_override("outline_size", 4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(text)
	return root
