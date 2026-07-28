class_name EnemyView
extends Control

## Visual representation of one enemy, including its telegraphed intent.

signal clicked(view: EnemyView)
signal hover_changed(view: EnemyView, inside: bool)

const VIEW_SIZE := Vector2(190, 250)

@onready var intent_label: Label = $IntentLabel
@onready var intent_detail: Label = $IntentDetail
@onready var body: Panel = $Body
@onready var name_label: Label = $Body/NameLabel
@onready var hp_bar: ProgressBar = $HpBar
@onready var hp_label: Label = $HpBar/HpLabel
@onready var block_label: Label = $BlockLabel
@onready var status_box: HBoxContainer = $StatusBox
@onready var target_ring: Panel = $TargetRing

var actor: Actor = null
var combat: Combat = null
var index: int = 0
var targeted: bool = false

var _sprite: TextureRect = null
var _sprite_home: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0


func _ready() -> void:
	custom_minimum_size = VIEW_SIZE
	size = VIEW_SIZE
	pivot_offset = VIEW_SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hover_changed.emit(self, true))
	mouse_exited.connect(func(): hover_changed.emit(self, false))
	target_ring.visible = false


func setup(a: Actor, cmb: Combat, idx: int) -> void:
	actor = a
	combat = cmb
	index = idx
	if not is_node_ready():
		await ready
	_style()
	refresh()


func _style() -> void:
	var tint := Color(0.42, 0.24, 0.28)
	if actor != null:
		if actor.is_boss:
			tint = Color(0.46, 0.16, 0.30)
		elif actor.is_minion:
			tint = Color(0.30, 0.30, 0.34)
		# A Pokemon wears its primary type, since that is what you have to plan
		# around. Bosses keep a darker shade of it.
		if actor.is_pokemon():
			tint = PokeData.type_color(String(actor.poke_types[0])).darkened(
					0.55 if actor.is_boss else 0.4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.border_color = tint.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	body.add_theme_stylebox_override("panel", sb)

	_build_sprite()
	UiTheme.style_hp_bar(hp_bar)


## The species portrait, sat on the body panel with the name tucked underneath.
## Pixel art, so it is scaled by a whole number and left unfiltered.
func _build_sprite() -> void:
	var tex := PokeSprites.for_actor(actor)
	if tex == null:
		return
	_sprite = PokeSprites.make_rect(tex, Vector2(PokeSprites.CELL * 1.5,
			PokeSprites.CELL * 1.5))
	_sprite_home = Vector2((body.size.x - _sprite.size.x) * 0.5, -14.0)
	_sprite.position = _sprite_home
	body.add_child(_sprite)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.add_theme_font_size_override("font_size", 13)
	# Idle bob, driven per-frame rather than by a looping Tween: an endless
	# tween outlives the node it animates and has to be torn down by hand.
	_bob_phase = randf() * TAU
	set_process(true)


func _process(delta: float) -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		set_process(false)
		return
	_bob_phase += delta * 1.9
	_sprite.position = _sprite_home + Vector2(0, sin(_bob_phase) * 4.5)

	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0)
	rsb.border_color = Color(1.0, 0.85, 0.35)
	rsb.set_border_width_all(3)
	rsb.set_corner_radius_all(12)
	target_ring.add_theme_stylebox_override("panel", rsb)


func refresh() -> void:
	if actor == null:
		return
	visible = actor.alive and not actor.is_dead()
	name_label.text = actor.name
	if actor.is_pokemon():
		var types := ""
		for t in actor.poke_types:
			types += ("/" if types != "" else "") + PokeData.display_name(String(t))
		name_label.text = "%s\n%s" % [actor.name, types]
	hp_bar.max_value = max(1, actor.max_hp)
	hp_bar.value = actor.hp
	hp_label.text = "%d / %d" % [actor.hp, actor.max_hp]
	block_label.visible = actor.block > 0
	block_label.text = "🛡 %d" % actor.block
	target_ring.visible = targeted

	# Intent
	var kind := String(actor.intent.get("kind", ""))
	if kind == "":
		intent_label.text = ""
		intent_detail.text = ""
	else:
		intent_label.text = EnemyLibrary.intent_symbol(kind)
		intent_label.modulate = EnemyLibrary.intent_color(kind)
		var dmg: Array = combat.intent_damage(actor) if combat != null else [0, 0]
		if int(dmg[0]) > 0:
			if int(dmg[1]) > 1:
				intent_detail.text = "%d x %d" % [int(dmg[0]), int(dmg[1])]
			else:
				intent_detail.text = str(int(dmg[0]))
		else:
			intent_detail.text = ""

	_update_tooltip()
	for child in status_box.get_children():
		child.queue_free()
	for s in actor.status_summary():
		var sid := String(s["id"])
		if Statuses.is_hidden(sid):
			continue
		var chip := Label.new()
		chip.text = "%s %d" % [Statuses.short_name(sid), int(s["stacks"])]
		chip.add_theme_font_size_override("font_size", 12)
		chip.add_theme_color_override("font_color", Statuses.color_of(sid))
		chip.tooltip_text = Statuses.describe(sid, int(s["stacks"]))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		status_box.add_child(chip)


func set_targeted(value: bool) -> void:
	targeted = value
	if target_ring != null:
		target_ring.visible = value


func flash() -> void:
	var t := create_tween()
	t.tween_property(body, "modulate", Color(1.6, 1.0, 1.0), 0.06)
	t.tween_property(body, "modulate", Color(1, 1, 1), 0.14)
	# The sprite takes the hit too: a quick squash and recoil, which is what
	# makes a number on screen feel like it landed on something alive.
	if _sprite != null:
		var s := create_tween()
		s.set_parallel(true)
		s.tween_property(_sprite, "scale", Vector2(1.18, 0.84), 0.05)
		s.chain().tween_property(_sprite, "scale", Vector2.ONE, 0.16) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func death_fade() -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.tween_property(self, "scale", Vector2(0.85, 0.85), 0.35)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		clicked.emit(self)
		accept_event()


func _update_tooltip() -> void:
	if actor == null:
		return
	var lines: Array = ["%s   %d / %d HP" % [actor.name, actor.hp, actor.max_hp]]
	var move := String(actor.intent.get("name", ""))
	if move != "":
		lines.append("Intends: %s" % move)
	for s in actor.status_summary():
		var sid := String(s["id"])
		if Statuses.is_hidden(sid):
			continue
		lines.append(Statuses.describe(sid, int(s["stacks"])))
	tooltip_text = "\n".join(lines)
