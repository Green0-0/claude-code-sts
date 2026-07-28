class_name CardFx
extends Control

## Plays a card's execution: the card itself leaves the hand, ascends, and is
## delivered onto its target.
##
## Three sequences, chosen by what the card does:
##
##   ATTACK   ascends ethereally, hangs above the target, then falls in a hard
##            chop — a thrown blade landing, with the cut, a shockwave and spray.
##   BOON     a friendly status card. Same ethereal rise, then a slow settle and
##            a melt into the target, spreading rings like a stone into a lake.
##   HEX      a hostile status card. Wears the BOON animation exactly, right up
##            to the last of the landing, then drops the disguise: it snaps down
##            and breaks over the target like a cursed mirror.
##
## Everything here is cosmetic. The caller awaits `execute()` and applies the
## card's actual effect at the impact moment, so the numbers land on the hit.

signal impact                     ## emitted the instant the card connects

enum Kind {ATTACK, BOON, HEX}

const CARD_SCENE := preload("res://scenes/CardView.tscn")

## Ghost cards are drawn above the hand (HAND_Z_DRAG) but below the modals
## (Main.OVERLAY_Z), so a card picker opened mid-animation still covers them.
const FX_Z := 700

## The height a card floats to on its ascent, above where it started.
const ASCENT_RISE := 150.0
## How far above the target the card hangs before it comes down.
const HOVER_ABOVE := 165.0


static func is_enabled() -> bool:
	# The dummy display server has nothing to draw to, and the self-play harness
	# would only be slowed down by waiting on tweens.
	return DisplayServer.get_name() != "headless"


## Which sequence a card should get.
static func kind_for(card: Card, hostile: bool) -> Kind:
	if card.type() == "attack":
		return Kind.ATTACK
	return Kind.HEX if hostile else Kind.BOON


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = FX_Z
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Runs the animation and returns when the card has connected. Callers should
## apply the card's effect on the `impact` signal, or immediately after awaiting.
func execute(card: Card, combat, from: Rect2, target: Rect2, kind: Kind) -> void:
	if not is_enabled():
		impact.emit()
		return
	var ghost := _make_ghost(card, combat, from)
	match kind:
		Kind.ATTACK:
			await _attack(ghost, from, target)
		Kind.BOON:
			await _boon(ghost, from, target)
		Kind.HEX:
			await _hex(ghost, from, target)
	if is_instance_valid(ghost):
		ghost.queue_free()


func _make_ghost(card: Card, combat, from: Rect2) -> CardView:
	var ghost: CardView = CARD_SCENE.instantiate()
	add_child(ghost)
	ghost.setup(card, combat)
	ghost.interactive = false
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = from.position
	ghost.pivot_offset = CardView.CARD_SIZE * 0.5
	return ghost


## The shared opening: a soft, unhurried climb with the card going pale and
## translucent, as though it were being offered up rather than thrown.
func _ascend(ghost: CardView, from: Rect2) -> void:
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(ghost, "position",
			from.position + Vector2(0, -ASCENT_RISE), 0.46)
	t.tween_property(ghost, "scale", Vector2.ONE * 1.16, 0.46)
	t.tween_property(ghost, "rotation", 0.0, 0.46)
	t.tween_property(ghost, "modulate", Color(1.35, 1.35, 1.5, 0.62), 0.46)
	await t.finished


# ══════════════════════════════════ Attack ═══════════════════════════════════
func _attack(ghost: CardView, from: Rect2, target: Rect2) -> void:
	await _ascend(ghost, from)

	# Drift over the target and cock back, like an axe being raised.
	var hover := target.get_center() - CardView.CARD_SIZE * 0.5 - Vector2(0, HOVER_ABOVE)
	var glide := ghost.create_tween()
	glide.set_parallel(true)
	glide.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	glide.tween_property(ghost, "position", hover, 0.3)
	glide.tween_property(ghost, "rotation", -0.75, 0.3)
	glide.tween_property(ghost, "modulate", Color(1.15, 1.1, 1.15, 0.9), 0.3)
	await glide.finished

	# The chop. Short, accelerating, straight through the target.
	var land := target.get_center() - CardView.CARD_SIZE * 0.5
	var chop := ghost.create_tween()
	chop.set_parallel(true)
	chop.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	chop.tween_property(ghost, "position", land + Vector2(0, 26), 0.11)
	chop.tween_property(ghost, "rotation", 0.55, 0.11)
	chop.tween_property(ghost, "scale", Vector2(1.05, 0.86), 0.11)
	chop.tween_property(ghost, "modulate", Color(1, 1, 1, 1), 0.08)
	await chop.finished

	impact.emit()
	SlashFx.spawn(self, target, -0.72)
	_shake(11.0, 0.22)

	# The card buries itself and is gone.
	var out := ghost.create_tween()
	out.set_parallel(true)
	out.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	out.tween_property(ghost, "modulate", Color(1, 0.85, 0.85, 0.0), 0.2)
	out.tween_property(ghost, "scale", Vector2(0.82, 0.6), 0.2)
	await out.finished


# ═══════════════════════════════════ Boon ════════════════════════════════════
func _boon(ghost: CardView, from: Rect2, target: Rect2) -> void:
	await _ascend(ghost, from)
	await _settle(ghost, target)
	await _melt(ghost, target)


## The slow, gentle descent both status sequences share. The hostile one runs
## this too — that is the disguise.
func _settle(ghost: CardView, target: Rect2) -> void:
	var above := target.get_center() - CardView.CARD_SIZE * 0.5 - Vector2(0, 46)
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(ghost, "position", above, 0.52)
	t.tween_property(ghost, "scale", Vector2.ONE * 0.92, 0.52)
	t.tween_property(ghost, "modulate", Color(1.2, 1.25, 1.3, 0.7), 0.52)
	await t.finished


## Flattens the card into the target and spreads the surface out in rings.
func _melt(ghost: CardView, target: Rect2) -> void:
	var onto := target.get_center() - CardView.CARD_SIZE * 0.5
	var t := ghost.create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	t.tween_property(ghost, "position", onto, 0.26)
	t.tween_property(ghost, "scale", Vector2(1.08, 0.08), 0.26)
	t.tween_property(ghost, "modulate", Color(1.4, 1.5, 1.6, 0.0), 0.26)
	await t.finished

	impact.emit()
	RippleFx.spawn(self, target, Color(0.62, 0.9, 1.0))


# ═══════════════════════════════════ Hex ═════════════════════════════════════
func _hex(ghost: CardView, from: Rect2, target: Rect2) -> void:
	await _ascend(ghost, from)
	await _settle(ghost, target)

	# The tell: a half-beat where the descent stalls and the colour sours.
	var turn := ghost.create_tween()
	turn.set_parallel(true)
	turn.tween_property(ghost, "modulate", Color(1.1, 0.62, 0.9, 0.8), 0.1)
	turn.tween_property(ghost, "position",
			ghost.position - Vector2(0, 12), 0.1)
	await turn.finished

	# Then it drops, hard. It stays part-transparent through the landing so the
	# break happens on the target rather than behind an opaque card.
	var onto := target.get_center() - CardView.CARD_SIZE * 0.5
	var drop := ghost.create_tween()
	drop.set_parallel(true)
	drop.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	drop.tween_property(ghost, "position", onto, 0.09)
	drop.tween_property(ghost, "scale", Vector2(1.02, 0.9), 0.09)
	drop.tween_property(ghost, "modulate", Color(1.2, 0.8, 1.0, 0.62), 0.09)
	await drop.finished

	impact.emit()
	GlassCrackFx.spawn(self, target)
	_shake(7.0, 0.18)

	var out := ghost.create_tween()
	out.set_parallel(true)
	out.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	out.tween_property(ghost, "modulate", Color(0.8, 0.6, 0.9, 0.0), 0.16)
	out.tween_property(ghost, "scale", Vector2(1.15, 1.15), 0.22)
	await out.finished


# ══════════════════════════════════ Shared ═══════════════════════════════════
## Knocks the whole screen about for a moment. The parent is the CombatScreen,
## which is anchored full-rect, so its position is otherwise always zero.
func _shake(strength: float, time: float) -> void:
	var screen := get_parent() as Control
	if screen == null:
		return
	var t := screen.create_tween()
	var steps := 6
	for i in range(steps):
		var falloff := strength * (1.0 - float(i) / float(steps))
		var offset := Vector2(randf_range(-falloff, falloff), randf_range(-falloff, falloff))
		t.tween_property(screen, "position", offset, time / float(steps))
	t.tween_property(screen, "position", Vector2.ZERO, time / float(steps))
