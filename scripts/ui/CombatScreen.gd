extends Control

## Drives a single combat: lays out the hand, handles targeting, animates the
## enemy phase and reports the result back to Main.

signal combat_over(victory: bool)
signal choice_needed(request: Dictionary)
signal pile_view_requested(title: String, cards: Array)

const CARD_SCENE := preload("res://scenes/CardView.tscn")
const ENEMY_SCENE := preload("res://scenes/EnemyView.tscn")
const PLAY_LINE_Y := 470.0
const CLICK_SLOP := 12.0
## The fan overlaps itself, so hand cards need explicit z-indices to stack: later
## cards over earlier ones, the hovered one over its neighbours, the dragged one
## over everything. z_index is global, not scoped to this screen, so anything
## meant to sit above the hand must clear HAND_Z_DRAG — see Main.OVERLAY_Z.
const HAND_Z_HOVER := 400
const HAND_Z_DRAG := 500

@onready var enemy_area: Control = $EnemyArea
@onready var hand_area: Control = $HandArea
@onready var player_panel: Panel = $PlayerPanel
@onready var player_name: Label = $PlayerPanel/NameLabel
@onready var player_hp_bar: ProgressBar = $PlayerPanel/HpBar
@onready var player_hp_label: Label = $PlayerPanel/HpBar/HpLabel
@onready var player_block: Label = $PlayerPanel/BlockLabel
@onready var player_status_box: HBoxContainer = $PlayerPanel/StatusBox
@onready var player_sprite: TextureRect = $PlayerPanel/Sprite
@onready var energy_label: Label = $EnergyOrb/EnergyLabel
@onready var end_turn_button: Button = $EndTurnButton
@onready var draw_button: Button = $Piles/DrawButton
@onready var discard_button: Button = $Piles/DiscardButton
@onready var exhaust_button: Button = $Piles/ExhaustButton
@onready var combat_log: RichTextLabel = $LogPanel/CombatLog
@onready var prompt_label: Label = $PromptLabel
@onready var float_layer: Control = $FloatLayer
@onready var target_line: Line2D = $TargetLine
@onready var turn_label: Label = $TurnLabel

var combat: Combat = null
var enemy_views: Array = []          ## Array[EnemyView]
var card_views: Array = []           ## Array[CardView]
var selected_view: CardView = null
var _drag_view: CardView = null
var _drag_origin: Vector2 = Vector2.ZERO
var _drag_active: bool = false
var _hovered_enemy: EnemyView = null
var _enemy_timer: Timer = null
var _busy: bool = false
var _log_lines: Array = []
## slot index -> Array[CardView]. Every member's hand exists at once; card_views
## always points at whichever of them is currently acting.
var hand_layers: Dictionary = {}
## One compact panel per party member, so allies can be seen and targeted.
var party_views: Array = []
## The player's own ATB gauge, built to sit under its health bar.
var player_charge_bar: ProgressBar = null
var _card_anim: CardAnim = null
var _shake_origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn)
	draw_button.pressed.connect(func(): _show_pile("Draw Pile (shuffled)", _shuffled_draw()))
	discard_button.pressed.connect(func(): _show_pile("Discard Pile", combat.discard_pile if combat else []))
	exhaust_button.pressed.connect(func(): _show_pile("Exhaust Pile", combat.exhaust_pile if combat else []))
	_enemy_timer = Timer.new()
	_enemy_timer.one_shot = true
	_enemy_timer.timeout.connect(_advance_enemy_phase)
	add_child(_enemy_timer)
	target_line.visible = false
	# Above the hand fan (HAND_Z_DRAG) so a flying card is never behind one, and
	# below Main.OVERLAY_Z so the card picker still covers it.
	_card_anim = CardAnim.new()
	_card_anim.name = "CardAnim"
	_card_anim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_anim.z_index = 700
	add_child(_card_anim)
	set_process_input(true)
	$EnergyOrb.add_theme_stylebox_override("panel", UiTheme.orb_style())
	player_panel.add_theme_stylebox_override("panel", UiTheme.player_style())
	UiTheme.style_hp_bar(player_hp_bar)
	player_charge_bar = UiTheme.make_charge_bar()
	player_charge_bar.position = Vector2(player_hp_bar.position.x,
			player_hp_bar.position.y + player_hp_bar.size.y + 3)
	player_charge_bar.size = Vector2(player_hp_bar.size.x, 6)
	player_panel.add_child(player_charge_bar)


# ════════════════════════════════ Combat lifecycle ═══════════════════════════
func begin(enemy_ids: Array, room_type: String) -> void:
	_clear()
	combat = Combat.new()
	combat.changed.connect(_on_combat_changed)
	combat.logged.connect(_on_log)
	combat.floating.connect(_on_floating)
	combat.choice_requested.connect(_on_choice_requested)
	combat.combat_finished.connect(_on_combat_finished)
	combat.enemy_died.connect(_on_enemy_died)
	combat.player_turn_started.connect(_on_player_turn_started)
	combat.active_member_changed.connect(_on_active_member_changed)
	_log_lines.clear()
	combat_log.clear()
	combat.setup(enemy_ids, room_type, Run.rng)
	_build_enemy_views()
	_build_party_views()
	_rebuild_hand()
	_refresh_all()


## The ATB handed control to a different member: bring its hand to the front and
## drop the previous one back into the shadowed stack.
func _on_active_member_changed(_who: Actor) -> void:
	if combat == null:
		return
	_select(null)
	card_views = hand_layers.get(combat.player.slot_index, [])
	_layout_hand()
	_refresh_playability()
	_refresh_party()


func _clear() -> void:
	for v in enemy_views:
		v.queue_free()
	enemy_views.clear()
	for slot in hand_layers:
		for v in hand_layers[slot]:
			v.queue_free()
	hand_layers.clear()
	for v in card_views:
		if is_instance_valid(v):
			v.queue_free()
	card_views.clear()
	# Each entry is a dictionary of the panel and its parts, so the panel is what
	# has to be freed.
	for entry in party_views:
		var panel = (entry as Dictionary).get("panel", null)
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
	party_views.clear()
	selected_view = null
	_drag_view = null
	_drag_active = false
	_busy = false
	combat = null
	target_line.visible = false
	_hovered_enemy = null
	# Otherwise the last fight's targeting line ("… It's super effective!") is
	# still on screen when the next one starts.
	prompt_label.visible = false
	prompt_label.text = ""
	# Same for anything still in flight or still fading: a card mid-execution and
	# its damage numbers would otherwise hang over the next encounter.
	for layer in [_card_anim, float_layer]:
		if layer == null:
			continue
		for child in layer.get_children():
			layer.remove_child(child)
			child.queue_free()


func _build_enemy_views() -> void:
	for v in enemy_views:
		v.queue_free()
	enemy_views.clear()
	for i in range(combat.enemies.size()):
		var e: Actor = combat.enemies[i]
		var view: EnemyView = ENEMY_SCENE.instantiate()
		enemy_area.add_child(view)
		view.setup(e, combat, i)
		view.clicked.connect(_on_enemy_clicked)
		view.hover_changed.connect(_on_enemy_hover)
		enemy_views.append(view)
	_layout_enemies()


func _layout_enemies() -> void:
	var live: Array = []
	for v in enemy_views:
		if v.actor.alive and not v.actor.is_dead():
			live.append(v)
	var n := live.size()
	if n == 0:
		return
	var spacing: float = minf(210.0, (enemy_area.size.x - 40.0) / float(n))
	var total := spacing * float(n)
	var start_x := (enemy_area.size.x - total) * 0.5
	for i in range(n):
		var v: EnemyView = live[i]
		var target_pos := Vector2(start_x + spacing * i + (spacing - EnemyView.VIEW_SIZE.x) * 0.5,
				enemy_area.size.y - EnemyView.VIEW_SIZE.y)
		if v.position == Vector2.ZERO:
			v.position = target_pos
		else:
			var t := v.create_tween()
			t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			t.tween_property(v, "position", target_pos, 0.25)


# ═════════════════════════════════ The party ═════════════════════════════════
## A compact panel per member down the left, showing who is on your side, how
## hurt they are and how charged. Clicking one targets it, which is how an
## ally-aimed card finds its mark.
const PARTY_PANEL := Vector2(196, 62)


func _build_party_views() -> void:
	# Each entry is a dictionary of the panel and its parts, so the panel is what
	# has to be freed.
	for entry in party_views:
		var panel = (entry as Dictionary).get("panel", null)
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
	party_views.clear()
	if combat == null or combat.party.size() <= 1:
		return
	for i in range(combat.party.size()):
		var member: Actor = combat.party[i]
		var panel := Panel.new()
		panel.custom_minimum_size = PARTY_PANEL
		panel.size = PARTY_PANEL
		panel.position = Vector2(16, 210 + i * (PARTY_PANEL.y + 8))
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.add_theme_stylebox_override("panel", UiTheme.player_style())

		var label := Label.new()
		label.position = Vector2(8, 4)
		label.size = Vector2(PARTY_PANEL.x - 16, 20)
		label.add_theme_font_size_override("font_size", 13)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)

		var hp := ProgressBar.new()
		hp.position = Vector2(8, 26)
		hp.size = Vector2(PARTY_PANEL.x - 16, 14)
		hp.show_percentage = false
		hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.style_hp_bar(hp)
		panel.add_child(hp)

		var charge := UiTheme.make_charge_bar()
		charge.position = Vector2(8, 44)
		charge.size = Vector2(PARTY_PANEL.x - 16, 6)
		panel.add_child(charge)

		panel.gui_input.connect(func(ev): _on_party_panel_input(ev, member))
		add_child(panel)
		party_views.append({"panel": panel, "label": label, "hp": hp,
				"charge": charge, "actor": member})
	_refresh_party()


func _refresh_party() -> void:
	if combat == null:
		return
	for entry in party_views:
		var member: Actor = entry["actor"]
		var panel: Panel = entry["panel"]
		var acting := member == combat.player
		panel.visible = member.alive and not member.is_dead()
		(entry["label"] as Label).text = "%s%s" % ["▸ " if acting else "", member.name]
		(entry["label"] as Label).modulate = Color(1, 0.92, 0.62) if acting \
				else Color(0.72, 0.72, 0.78)
		var hp: ProgressBar = entry["hp"]
		hp.max_value = max(1, member.max_hp)
		hp.value = member.hp
		var charge: ProgressBar = entry["charge"]
		charge.value = combat.charge_ratio(member) * 100.0
		# The acting member's panel is lit; the rest are shadowed like their hands.
		panel.modulate = Color.WHITE if acting else Color(0.66, 0.65, 0.72)


## Clicking a party panel points the selected card at that member.
func _on_party_panel_input(event: InputEvent, member: Actor) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or combat == null:
		return
	if selected_view != null and selected_view.card.target_kind() == "ally":
		_play_at_ally(selected_view, member)


func _play_at_ally(view: CardView, member: Actor) -> void:
	if combat == null or combat.phase != "player" or _busy:
		return
	combat.ally_target = member
	_try_play(view, -1)
	combat.ally_target = null


# ═════════════════════════════════ Hand layout ═══════════════════════════════
## Every party member's hand is on screen at once, stacked in layers.
##
## The member whose gauge filled has its fan at the front, at full size and
## fully lit; the rest sit behind it, smaller, pushed up and back, and shadowed
## down so they read as context rather than clutter. Swapping who is acting
## re-sorts the layers rather than rebuilding them, so the swap is a movement
## rather than a redraw.

## How far back each inactive layer sits, and how much of its colour survives.
const LAYER_STEP := Vector2(0, -46.0)
const LAYER_SCALE := 0.78
const LAYER_SHADOW := Color(0.34, 0.33, 0.42)
const LAYER_Z := -40


func _rebuild_hand() -> void:
	# One list of views per party member, keyed by slot.
	var wanted := {}
	for a in combat.party:
		var member: Actor = a
		var uids: Array = []
		for c in member.hand:
			uids.append(c.uid)
		wanted[member.slot_index] = uids

	var current := {}
	for slot in hand_layers:
		var uids2: Array = []
		for v in hand_layers[slot]:
			uids2.append(v.card.uid)
		current[slot] = uids2

	if wanted == current:
		for slot in hand_layers:
			for v in hand_layers[slot]:
				v.combat = combat
				v.refresh()
		_layout_hand()
		_refresh_playability()
		return

	for slot in hand_layers:
		for v in hand_layers[slot]:
			v.queue_free()
	hand_layers.clear()
	card_views.clear()

	for a in combat.party:
		var member: Actor = a
		var views: Array = []
		for c in member.hand:
			var view: CardView = CARD_SCENE.instantiate()
			hand_area.add_child(view)
			view.setup(c, combat)
			view.pressed.connect(_on_card_pressed)
			view.released.connect(_on_card_released)
			view.hover_changed.connect(_on_card_hover)
			views.append(view)
		hand_layers[member.slot_index] = views
		if member == combat.player:
			card_views = views
	_layout_hand(true)
	_refresh_playability()


func _layout_hand(instant: bool = false) -> void:
	if combat == null:
		return
	# Inactive layers are ordered by how far they are from the active one, so the
	# stack reads as depth rather than as party order.
	var active_slot := combat.player.slot_index if combat.player != null else 0
	var depth := 0
	var slots: Array = hand_layers.keys()
	slots.sort()
	for slot in slots:
		if int(slot) == active_slot:
			continue
		depth += 1
		_layout_layer(hand_layers[slot], depth, instant)
	_layout_layer(hand_layers.get(active_slot, []), 0, instant)


## Lays out one member's fan. depth 0 is the acting member, at the front.
func _layout_layer(views: Array, depth: int, instant: bool) -> void:
	var n := views.size()
	if n == 0:
		return
	var active := depth == 0
	var scale_factor: float = 1.0 if active else pow(LAYER_SCALE, float(depth))
	var spacing: float = minf(168.0, maxf(70.0, (hand_area.size.x - 240.0) / float(n)))
	spacing *= scale_factor
	var center_x := hand_area.size.x * 0.5
	var base_y := hand_area.size.y - CardView.CARD_SIZE.y - 18.0
	var offset_y := LAYER_STEP.y * float(depth)

	for i in range(n):
		var v: CardView = views[i]
		var offset := float(i) - float(n - 1) * 0.5
		var norm := offset / maxf(1.0, float(n - 1) * 0.5)
		# The fan arcs upward in the middle; the outermost cards sit on base_y so
		# nothing is ever pushed off the bottom of the screen.
		v.home_position = Vector2(
				center_x + offset * spacing - CardView.CARD_SIZE.x * scale_factor * 0.5,
				base_y + offset_y - (1.0 - norm * norm) * 26.0 * scale_factor)
		v.home_rotation = offset * 0.035
		v.home_scale = scale_factor
		# Only the acting member's cards are live; the rest are scenery you can
		# read but not play, which is what keeps the layered look from being a
		# hazard.
		v.interactive = active
		v.z_index = i if active else LAYER_Z * depth + i
		v.modulate = Color.WHITE if active else LAYER_SHADOW
		if v == _drag_view and _drag_active:
			continue
		if instant:
			v.snap_home()
		elif v.selected and active:
			v.lift()
		else:
			v.tween_home()


func _refresh_playability() -> void:
	if combat == null:
		return
	for v in card_views:
		var idx := 0 if v.card.needs_target() else -1
		v.set_playable(combat.can_play(v.card, idx)["ok"])


# ═══════════════════════════════ Input handling ══════════════════════════════
func _on_card_pressed(view: CardView) -> void:
	if _busy or combat == null or combat.phase != "player":
		return
	if not combat.pending_choice.is_empty():
		return
	_drag_view = view
	_drag_origin = get_global_mouse_position()
	_drag_active = false
	view.z_index = HAND_Z_DRAG


func _on_card_released(view: CardView, at: Vector2) -> void:
	if _drag_view != view:
		return
	var travelled := at.distance_to(_drag_origin)
	target_line.visible = false
	if travelled < CLICK_SLOP:
		# Treated as a click: select, or play if no target is needed.
		_drag_view = null
		_drag_active = false
		_select(view if selected_view != view else null)
		if selected_view == view and not view.card.needs_target():
			_try_play(view, -1)
		return
	_drag_view = null
	_drag_active = false
	if view.card.needs_target():
		if _hovered_enemy != null:
			_try_play(view, _hovered_enemy.index)
		else:
			_return_card(view)
	else:
		if at.y < PLAY_LINE_Y:
			_try_play(view, -1)
		else:
			_return_card(view)


func _return_card(view: CardView) -> void:
	view.z_index = card_views.find(view)
	view.tween_home()
	_clear_target_highlight()


func _input(event: InputEvent) -> void:
	if not visible or combat == null:
		return
	if event is InputEventMouseMotion and _drag_view != null:
		var mouse := get_global_mouse_position()
		if not _drag_active and mouse.distance_to(_drag_origin) >= CLICK_SLOP:
			_drag_active = true
			_select(null)
		if _drag_active:
			_drag_view.position = hand_area.get_local_mouse_position() \
					- CardView.CARD_SIZE * 0.5
			_drag_view.rotation = 0.0
			_update_target_line(mouse)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_hotkey(event)


func _handle_hotkey(event: InputEventKey) -> void:
	if combat == null or combat.phase != "player" or not combat.pending_choice.is_empty():
		return
	if event.keycode == KEY_E or event.keycode == KEY_SPACE:
		_on_end_turn()
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var idx := event.keycode - KEY_1
		if idx < card_views.size():
			var v: CardView = card_views[idx]
			if v.card.needs_target():
				_select(v)
			else:
				_try_play(v, -1)


func _update_target_line(mouse: Vector2) -> void:
	if _drag_view == null or not _drag_view.card.needs_target():
		target_line.visible = false
		return
	target_line.visible = true
	var from := player_panel.position + player_panel.size * Vector2(1.0, 0.3)
	var to := mouse - global_position
	target_line.clear_points()
	target_line.add_point(from)
	target_line.add_point(from.lerp(to, 0.5) + Vector2(0, -60))
	target_line.add_point(to)
	target_line.default_color = Color(1.0, 0.85, 0.4, 0.9) if _hovered_enemy != null \
			else Color(0.7, 0.7, 0.75, 0.6)


func _select(view: CardView) -> void:
	if selected_view != null and selected_view != view:
		selected_view.set_selected(false)
		selected_view.tween_home()
	selected_view = view
	if view != null:
		view.set_selected(true)
		view.lift()
		if view.card.needs_target():
			prompt_label.text = "Choose a target for %s" % view.card.display_name()
			prompt_label.visible = true
	else:
		prompt_label.visible = false
	_refresh_target_preview()


func _on_enemy_clicked(view: EnemyView) -> void:
	if combat == null or combat.phase != "player":
		return
	if selected_view != null and selected_view.card.needs_target():
		_try_play(selected_view, view.index)


func _on_enemy_hover(view: EnemyView, inside: bool) -> void:
	if inside:
		_hovered_enemy = view
		if combat != null:
			combat.preview_target_index = _living_index(view)
			_refresh_hand_text()
			_show_matchup(view)
	elif _hovered_enemy == view:
		_hovered_enemy = null
		if combat != null:
			combat.preview_target_index = -1
			_refresh_hand_text()
	_refresh_target_preview()


## Calls the matchup before the card is committed, so the type chart is legible
## without having to know it by heart. The damage numbers on the cards already
## update against whoever is hovered; this names the reason.
func _show_matchup(view: EnemyView) -> void:
	if selected_view == null or combat == null:
		return
	var note := PokeMoves.matchup_note(selected_view.card, combat)
	if note == "":
		return
	prompt_label.text = "%s → %s  %s" % [selected_view.card.display_name(),
			view.actor.name, note]
	prompt_label.visible = true


func _living_index(view: EnemyView) -> int:
	var live := combat.living_enemies()
	return live.find(view.actor)


func _refresh_target_preview() -> void:
	for v in enemy_views:
		var want := false
		if _hovered_enemy == v and (_drag_active or selected_view != null):
			want = true
		v.set_targeted(want)


func _clear_target_highlight() -> void:
	for v in enemy_views:
		v.set_targeted(false)


func _refresh_hand_text() -> void:
	for v in card_views:
		v.refresh()


func _on_card_hover(view: CardView, inside: bool) -> void:
	if _drag_active:
		return
	if inside:
		if view != selected_view:
			var t := view.create_tween()
			t.set_parallel(true)
			t.tween_property(view, "position", view.home_position + Vector2(0, -26), 0.1)
			t.tween_property(view, "scale", Vector2.ONE * 1.08, 0.1)
			view.z_index = HAND_Z_HOVER
	else:
		if view != selected_view:
			view.z_index = card_views.find(view)
			view.tween_home(0.12)


# ═══════════════════════════════ Playing cards ═══════════════════════════════
func _try_play(view: CardView, target_index: int) -> void:
	if combat == null:
		return
	var check := combat.can_play(view.card, target_index)
	if not check["ok"]:
		prompt_label.text = String(check["why"])
		prompt_label.visible = true
		view.tween_home()
		return
	prompt_label.visible = false
	if selected_view == view:
		selected_view = null
	view.set_selected(false)
	if target_index >= 0 and target_index < enemy_views.size():
		for v in enemy_views:
			if v.index == target_index:
				v.flash()
	if not CardAnim.enabled:
		combat.play_card(view.card, target_index)
		_clear_target_highlight()
		return

	# The card is resolved on the frame the animation lands, so the damage
	# numbers and the blow arrive together rather than a beat apart.
	var card := view.card
	var kind := _anim_kind_for(card)
	var target_view := _view_for_index(target_index)
	var target_rect := _target_rect(kind, target_view)
	var from_pos := _to_local(view.get_global_position())
	view.visible = false
	_busy = true
	_clear_target_highlight()
	await _card_anim.play(card, combat, "", card.tint(), from_pos, target_rect, kind,
			func():
				combat.play_card(card, target_index)
				_impact_feedback(kind, target_view))
	_busy = false
	_refresh_all()


## Which choreography a card gets: attacks are executions, self-targeting status
## is a blessing, and anything status aimed at someone else is a hex.
func _anim_kind_for(card: Card) -> int:
	if card.type() == "attack":
		return CardAnim.Kind.ATTACK
	if card.effective_target_kind() in ["self", "none"]:
		return CardAnim.Kind.BLESS
	return CardAnim.Kind.HEX


func _view_for_index(target_index: int) -> Control:
	for v in enemy_views:
		if v.index == target_index and v.visible:
			return v
	for v in enemy_views:
		if v.visible:
			return v
	return null


## Where the card is headed. A blessing lands on its caster; everything else on
## whoever it was aimed at.
func _target_rect(kind: int, target_view: Control) -> Rect2:
	if kind == CardAnim.Kind.BLESS or target_view == null:
		return _local_rect(player_panel)
	return _local_rect(target_view)


func _to_local(global_pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_pos


func _local_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	return Rect2(_to_local(r.position), r.size)


## The felt part of a landing: the victim recoils, and an execution shakes the
## whole screen.
func _impact_feedback(kind: int, target_view: Control) -> void:
	if target_view != null and target_view.has_method("recoil"):
		target_view.recoil(kind == CardAnim.Kind.ATTACK)
	if kind == CardAnim.Kind.ATTACK:
		_shake(9.0, 0.22)
	elif kind == CardAnim.Kind.HEX:
		_shake(4.0, 0.16)


func _shake(amount: float, duration: float) -> void:
	if _shake_origin == Vector2.ZERO:
		_shake_origin = position
	var t := create_tween()
	var steps := 6
	for i in range(steps):
		var falloff := amount * (1.0 - float(i) / float(steps))
		t.tween_property(self, "position", _shake_origin + Vector2(
				randf_range(-falloff, falloff), randf_range(-falloff, falloff)),
				duration / float(steps))
	t.tween_property(self, "position", _shake_origin, duration / float(steps))


func _on_end_turn() -> void:
	if combat == null or _busy or combat.phase != "player" or combat.finished:
		return
	if not combat.pending_choice.is_empty():
		# Say why, and put the prompt back on screen if it went missing.
		prompt_label.text = String(combat.pending_choice.get("prompt", "Resolve the prompt"))
		prompt_label.visible = true
		combat.reassert_choice()
		return
	_select(null)
	_busy = true
	end_turn_button.disabled = true
	prompt_label.visible = false
	combat.end_turn()
	if combat.finished:
		return
	_enemy_timer.start(0.35)


## Pumps the ATB clock until it is the player's turn again.
##
## Each call lets time run to the next actor that fills its gauge. If that is an
## enemy it acts — animated first, then resolved — and the pump is scheduled
## again. If it is the player, control comes back here and the hand unlocks.
func _advance_enemy_phase() -> void:
	if combat == null or combat.finished:
		_hand_control(true)
		return

	# combat.active is set by the engine when a gauge fills. Give an enemy its
	# flourish before its effects land.
	var actor: Actor = combat.peek_enemy() if CardAnim.enabled else null
	if actor != null and not actor.intent.is_empty():
		await _animate_enemy_move(actor)
		if combat == null or combat.finished:
			_hand_control(true)
			return
	var busy := combat.step_enemy()
	_refresh_all()
	if combat.finished:
		_hand_control(true)
		return
	if busy or combat.phase != "player":
		# Somebody else is still ahead of the player in the queue.
		_enemy_timer.start(0.2 if busy else 0.05)
		return
	_hand_control(true)


func _hand_control(to_player: bool) -> void:
	_busy = not to_player
	end_turn_button.disabled = not to_player or combat == null or combat.finished


## An enemy's move gets the same choreography as a card, with a stand-in token
## for the card it does not have.
func _animate_enemy_move(actor: Actor) -> void:
	var view := _view_for_actor(actor)
	var intent := String(actor.intent.get("kind", "unknown"))
	var move_name := String(actor.intent.get("name", "…"))
	var kind := CardAnim.Kind.HEX
	if intent.begins_with("attack"):
		kind = CardAnim.Kind.ATTACK
	elif intent in ["defend", "buff", "sleep", "unknown", "escape"]:
		kind = CardAnim.Kind.BLESS

	# A blessing stays with the caster; anything else is coming for the player.
	var target_rect := _local_rect(view) if kind == CardAnim.Kind.BLESS \
			else _local_rect(player_panel)
	var from_pos := _local_rect(view).position if view != null \
			else Vector2(size.x * 0.5, 120.0)
	var tint := EnemyLibrary.intent_color(intent)
	if actor.is_pokemon() and not actor.poke_types.is_empty():
		tint = PokeData.type_color(String(actor.poke_types[0]))

	await _card_anim.play(null, combat, move_name, tint, from_pos, target_rect, kind,
			func():
				combat.step_enemy()
				_impact_feedback(kind, null if kind != CardAnim.Kind.BLESS else view)
				if kind != CardAnim.Kind.BLESS:
					_player_recoil(kind == CardAnim.Kind.ATTACK))


func _view_for_actor(a: Actor) -> Control:
	for v in enemy_views:
		if v.actor == a:
			return v
	return null


## The player has no EnemyView to recoil, so its panel takes the hit instead.
func _player_recoil(hard: bool) -> void:
	var origin := player_panel.position
	var t := player_panel.create_tween()
	t.tween_property(player_panel, "position", origin + Vector2(-14.0 if hard else -6.0, 0), 0.05)
	t.tween_property(player_panel, "position", origin, 0.16) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)


func _on_player_turn_started() -> void:
	_busy = false
	end_turn_button.disabled = false
	_on_log("[color=#e8c07a]— Turn %d —[/color]" % combat.turn)


# ══════════════════════════════════ Refresh ══════════════════════════════════
func _on_combat_changed() -> void:
	_refresh_all()


func _refresh_all() -> void:
	if combat == null:
		return
	var p := combat.player
	player_name.text = p.name
	# Flipped in the scene, so a player Pokemon faces across at the enemies.
	var art := PokeSprites.texture_for_actor(p)
	player_sprite.texture = art
	player_sprite.visible = art != null
	player_hp_bar.max_value = max(1, p.max_hp)
	player_hp_bar.value = p.hp
	player_hp_label.text = "%d / %d" % [p.hp, p.max_hp]
	player_block.visible = p.block > 0
	player_block.text = "🛡 %d" % p.block
	_refresh_party()
	if player_charge_bar != null:
		player_charge_bar.value = combat.charge_ratio(p) * 100.0
		player_charge_bar.modulate = Color(1, 1, 1).lerp(
				Color(1.0, 0.85, 0.45), combat.charge_ratio(p))
	energy_label.text = "%d/%d" % [combat.energy, combat.energy_per_turn
			+ combat.energy_bonus_relics()]
	turn_label.text = "Turn %d" % combat.turn

	for child in player_status_box.get_children():
		child.queue_free()
	for s in p.status_summary():
		var sid := String(s["id"])
		if Statuses.is_hidden(sid):
			continue
		var chip := Label.new()
		chip.text = "%s %d" % [Statuses.short_name(sid), int(s["stacks"])]
		chip.add_theme_font_size_override("font_size", 12)
		chip.add_theme_color_override("font_color", Statuses.color_of(sid))
		chip.tooltip_text = Statuses.describe(sid, int(s["stacks"]))
		player_status_box.add_child(chip)

	var counts := combat.pile_counts()
	draw_button.text = "Draw %d" % int(counts["draw"])
	discard_button.text = "Discard %d" % int(counts["discard"])
	exhaust_button.text = "Exhaust %d" % int(counts["exhaust"])

	for v in enemy_views:
		v.refresh()
	_layout_enemies()
	_rebuild_hand()
	_refresh_playability()


func _on_log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 40:
		_log_lines.pop_front()
	combat_log.clear()
	combat_log.append_text("\n".join(_log_lines))
	combat_log.scroll_to_line(max(0, combat_log.get_line_count() - 1))


func _on_floating(target: Actor, text: String, kind: String) -> void:
	var origin := Vector2.ZERO
	if target != null and target.is_player:
		origin = player_panel.position + Vector2(player_panel.size.x * 0.5, 30)
	else:
		for v in enemy_views:
			if v.actor == target:
				origin = enemy_area.position + v.position + Vector2(EnemyView.VIEW_SIZE.x * 0.5, 90)
				v.flash()
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	var col := Color(1, 1, 1)
	match kind:
		"damage": col = Color(1.0, 0.42, 0.36)
		"blocked": col = Color(0.65, 0.8, 1.0)
		"block": col = Color(0.55, 0.75, 1.0)
		"heal": col = Color(0.5, 0.95, 0.55)
		"poison": col = Color(0.55, 0.9, 0.4)
		"status": col = Color(0.95, 0.8, 0.5)
	label.add_theme_color_override("font_color", col)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 5)
	label.position = origin + Vector2(randf_range(-24, 24), 0)
	float_layer.add_child(label)
	var t := label.create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position", label.position + Vector2(0, -60), 0.9)
	t.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	t.chain().tween_callback(label.queue_free)


func _on_enemy_died(who: Actor) -> void:
	for v in enemy_views:
		if v.actor == who:
			v.death_fade()
	# New enemies can appear mid-combat (Slime Boss split, Gremlin Leader rally).
	if combat != null and combat.enemies.size() != enemy_views.size():
		call_deferred("_sync_enemy_views")


func _sync_enemy_views() -> void:
	if combat == null:
		return
	if combat.enemies.size() == enemy_views.size():
		return
	for i in range(enemy_views.size(), combat.enemies.size()):
		var e: Actor = combat.enemies[i]
		var view: EnemyView = ENEMY_SCENE.instantiate()
		enemy_area.add_child(view)
		view.setup(e, combat, i)
		view.clicked.connect(_on_enemy_clicked)
		view.hover_changed.connect(_on_enemy_hover)
		enemy_views.append(view)
	_layout_enemies()


func _on_choice_requested(request: Dictionary) -> void:
	choice_needed.emit(request)


## Experience banked over the whole fight, for the reward screen.
func xp_earned() -> int:
	return combat.xp_pool if combat != null else 0


func submit_choice(cards: Array) -> void:
	if combat != null:
		combat.resolve_choice(cards)


func _on_combat_finished(victory: bool) -> void:
	_busy = true
	end_turn_button.disabled = true
	_select(null)
	target_line.visible = false
	await get_tree().create_timer(0.7).timeout
	combat_over.emit(victory)


func _show_pile(title: String, cards: Array) -> void:
	pile_view_requested.emit(title, cards.duplicate())


func _shuffled_draw() -> Array:
	if combat == null:
		return []
	var copy: Array = combat.draw_pile.duplicate()
	copy.sort_custom(func(a, b): return a.display_name() < b.display_name())
	return copy


## Called by Main when the player drinks a potion that needs an enemy target.
func use_potion(slot: int) -> void:
	if combat == null or combat.phase != "player":
		return
	var id := String(Run.potions[slot])
	if id == "":
		return
	var d := PotionLibrary.get_def(id)
	if String(d["target"]) == "enemy":
		var idx := 0
		if _hovered_enemy != null:
			idx = _living_index(_hovered_enemy)
		combat.use_potion(slot, max(0, idx))
	else:
		combat.use_potion(slot, -1)
	_refresh_all()
