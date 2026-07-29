extends Control

## Drives a single combat: lays out the hand, handles targeting, animates the
## enemy phase and reports the result back to Main.

signal combat_over(victory: bool)
signal choice_needed(request: Dictionary)
signal pile_view_requested(title: String, cards: Array)
## The player has picked something to throw a ball at. Main takes it from here.
signal capture_requested(actor: Actor)

const CARD_SCENE := preload("res://scenes/CardView.tscn")
const ENEMY_SCENE := preload("res://scenes/EnemyView.tscn")
const PLAY_LINE_Y := 470.0
const CLICK_SLOP := 12.0
## How long after one of an enemy's cards takes off before the next one does.
## Long enough to read as separate throws, short enough that a three-card turn is
## not three animations end to end.
const ENEMY_CARD_STAGGER := 0.26
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
## How many cards and moves are in the air. Cards are no longer played one at a
## time: the hand unlocks the instant a card is paid for, so several flights
## overlap and this is what the few things that genuinely have to wait — ending
## the turn, closing out an enemy's turn — count down to zero.
var _flights: int = 0
var _player_panel_home: Vector2 = Vector2.ZERO
## The Capture button, and whether it is currently waiting for a target.
var capture_button: Button = null
var _capture_mode: bool = false


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
	_player_panel_home = player_panel.position
	_build_capture_button()


## Capture is a move you can reach for on any turn, so it lives on the board next
## to End Turn rather than behind a menu.
func _build_capture_button() -> void:
	capture_button = Button.new()
	capture_button.name = "CaptureButton"
	# Anchored to the right edge like End Turn, and directly above it, rather than
	# offset from its position — which is not laid out yet this early.
	capture_button.anchor_left = 1.0
	capture_button.anchor_right = 1.0
	capture_button.offset_left = -178.0
	capture_button.offset_top = 432.0
	capture_button.offset_right = -20.0
	capture_button.offset_bottom = 478.0
	capture_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	capture_button.focus_mode = Control.FOCUS_NONE
	# Above a hovered card (HAND_Z_HOVER) but below a dragged one (HAND_Z_DRAG), so
	# the fan never buries the two buttons the turn is actually driven by while a
	# card in flight still passes over them.
	capture_button.z_index = HAND_Z_HOVER + 50
	end_turn_button.z_index = HAND_Z_HOVER + 50
	capture_button.add_theme_font_size_override("font_size", 16)
	capture_button.text = "◓  Capture"
	capture_button.pressed.connect(_on_capture_pressed)
	add_child(capture_button)


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
	_rebuild_hand(true)
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
	_capture_mode = false
	_flights = 0
	combat = null
	target_line.visible = false
	_hovered_enemy = null
	# Otherwise the last fight's targeting line ("… It's super effective!") is
	# still on screen when the next one starts.
	prompt_label.visible = false
	prompt_label.text = ""
	# Same for anything still in flight or still fading: a card mid-execution and
	# its damage numbers would otherwise hang over the next encounter.
	if _card_anim != null:
		_card_anim.abort()
	if float_layer != null:
		for child in float_layer.get_children():
			float_layer.remove_child(child)
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
		v.home_position = target_pos
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
		# `home` is remembered so a recoil always springs back to the layout
		# position, even when two blows land close enough together to overlap.
		party_views.append({"panel": panel, "label": label, "hp": hp,
				"charge": charge, "actor": member, "home": panel.position})
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
	if event.button_index != MOUSE_BUTTON_LEFT or combat == null or _capture_mode:
		return
	if selected_view != null:# and selected_view.card.target_kind() == "ally":
		_play_at_ally(selected_view, member)


func _play_at_ally(view: CardView, member: Actor) -> void:
	if combat == null or combat.phase != "player" or _busy:
		return
	# Only set for the length of the commit, which `_try_play` does before it
	# returns — the flight that follows carries the target in its own token.
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


## Brings the on-screen hands into line with the party's actual hands.
##
## Views are *reused* wherever the card is still held: only the cards that left
## get freed, and only the cards that arrived get built. That matters now that
## cards are played without waiting for each other — this runs on every state
## change, several times while a flight is in the air, and a wholesale rebuild
## would snatch the card the player is dragging out from under the cursor and
## restart every neighbour's tween on top of it.
func _rebuild_hand(instant: bool = false) -> void:
	if combat == null:
		return
	# Everything currently on screen, keyed by card, so a card that merely moved
	# from one member's hand to another keeps the view it already had.
	var existing := {}
	for slot in hand_layers:
		for v in hand_layers[slot]:
			if is_instance_valid(v) and v.card != null:
				existing[v.card.uid] = v

	var next_layers := {}
	for a in combat.party:
		var member: Actor = a
		var views: Array = []
		for c in member.hand:
			var card: Card = c
			var view: CardView = existing.get(card.uid, null)
			if view != null:
				existing.erase(card.uid)
				view.combat = combat
				view.refresh()
			else:
				view = CARD_SCENE.instantiate()
				hand_area.add_child(view)
				view.setup(card, combat)
				view.pressed.connect(_on_card_pressed)
				view.released.connect(_on_card_released)
				view.hover_changed.connect(_on_card_hover)
				# A card that has just been drawn slides up from under the fan
				# rather than appearing in the middle of it.
				view.position = Vector2(
						hand_area.size.x * 0.5 - CardView.CARD_SIZE.x * 0.5,
						hand_area.size.y + 60.0)
			views.append(view)
		next_layers[member.slot_index] = views

	# Whatever is left over is no longer in anybody's hand.
	for uid in existing:
		var gone: CardView = existing[uid]
		if gone == _drag_view:
			_drag_view = null
			_drag_active = false
			target_line.visible = false
		if gone == selected_view:
			selected_view = null
			prompt_label.visible = false
		_retire_card_view(gone)

	hand_layers = next_layers
	card_views = hand_layers.get(combat.player.slot_index, [])
	_layout_hand(instant)
	_refresh_playability()


## Takes a card view off the board. A card that was played is already hidden — its
## ghost is doing the acting — so that one goes at once; anything else (discarded,
## exhausted, put back in the deck) gets a beat to leave.
func _retire_card_view(view: CardView) -> void:
	if view == null or not is_instance_valid(view):
		return
	view.interactive = false
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not view.visible:
		view.queue_free()
		return
	var t := view.create_tween()
	t.set_parallel(true)
	t.tween_property(view, "modulate:a", 0.0, 0.16)
	t.tween_property(view, "scale", view.scale * 0.8, 0.16)
	t.chain().tween_callback(view.queue_free)


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
		if not is_instance_valid(v):
			continue
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
		# A card that has been thrown is hidden while its ghost flies; moving it
		# would only fight the retirement tween.
		if not v.visible:
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
		if not is_instance_valid(v) or v.card == null:
			continue
		var idx := 0 if v.card.needs_target() else -1
		v.set_playable(combat.can_play(v.card, idx)["ok"])


# ═══════════════════════════════ Input handling ══════════════════════════════
func _on_card_pressed(view: CardView, at: Vector2) -> void:
	if _busy or combat == null or combat.phase != "player" or combat.finished:
		return
	if not combat.pending_choice.is_empty() or _capture_mode:
		return
	_drag_view = view
	_drag_origin = at
	_drag_active = false
	view.z_index = HAND_Z_DRAG


## Only ever a click. A release that ends a real drag is consumed in `_input`,
## which sees the button come up before the card's own gui_input does — and has
## to, because a dragged card lets the mouse through so the board underneath can
## be hovered, and a card the mouse passes through cannot report its own release.
func _on_card_released(view: CardView, at: Vector2) -> void:
	if _drag_view != view or _drag_active:
		return
	if at.distance_to(_drag_origin) >= CLICK_SLOP:
		_finish_drag(view, at)
		return
	_drag_view = null
	target_line.visible = false
	_select(view if selected_view != view else null)
	if selected_view == view and not view.card.needs_target():
		_try_play(view, -1)


## What letting go of a dragged card means.
##
## Resolved by geometry rather than by whatever the mouse last hovered: the card
## follows the cursor for the whole drag, so it is the thing under the pointer at
## the moment of release, and asking the board directly is the only way a drop
## ever finds anything at all.
func _finish_drag(view: CardView, at: Vector2) -> void:
	_drag_view = null
	_drag_active = false
	target_line.visible = false
	if not is_instance_valid(view):
		return
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	if combat == null or combat.phase != "player" or combat.finished:
		_return_card(view)
		return

	var drop := _drop_at(at)
	var card := view.card
	match String(drop.get("kind", "none")):
		"enemy":
			_try_play(view, int(drop["index"]) if card.needs_target() else -1)
			return
		"ally":
			# Anything can be pointed at your own side; the card decides whether
			# that means anything.
			_play_at_ally(view, drop["actor"])
			return
	if card.needs_target():
		# Let go over open ground: the throw is abandoned, not misfired.
		_return_card(view)
		prompt_label.text = "%s needs a target — drop it on one." % card.display_name()
		prompt_label.visible = true
		return
	if at.y < _play_line_y():
		_try_play(view, -1)
	else:
		_return_card(view)


## Whatever is under a point on the board: an enemy, one of your own, or nothing.
func _drop_at(global_pos: Vector2) -> Dictionary:
	for v in enemy_views:
		if not is_instance_valid(v) or not v.visible or v.actor == null:
			continue
		if not v.actor.alive or v.actor.is_dead():
			continue
		if v.get_global_rect().has_point(global_pos):
			var idx := _living_index(v)
			if idx != -1:
				return {"kind": "enemy", "index": idx, "view": v}
	for entry in party_views:
		var panel: Panel = (entry as Dictionary).get("panel", null)
		if panel != null and is_instance_valid(panel) and panel.visible \
				and panel.get_global_rect().has_point(global_pos):
			return {"kind": "ally", "actor": entry["actor"]}
	# The big panel is the acting member, and the obvious place to drop something
	# meant for yourself.
	if player_panel.get_global_rect().has_point(global_pos) and combat != null:
		return {"kind": "ally", "actor": combat.player}
	return {"kind": "none"}


## The play line in global coordinates — the screen shifts when it shakes, and a
## drop must not be judged against a stale one.
func _play_line_y() -> float:
	return (get_global_transform() * Vector2(0.0, PLAY_LINE_Y)).y


func _return_card(view: CardView) -> void:
	if not is_instance_valid(view):
		return
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.z_index = card_views.find(view)
	view.tween_home()
	_clear_target_highlight()


func _input(event: InputEvent) -> void:
	if not visible or combat == null:
		return
	if _drag_view != null and not is_instance_valid(_drag_view):
		_drag_view = null
		_drag_active = false
		target_line.visible = false
		return
	# Positions come off the event rather than from the live cursor, so a drag can
	# be driven by anything that can synthesize one — which is what makes the
	# gesture testable rather than only playable.
	if event is InputEventMouseMotion and _drag_view != null:
		var mouse: Vector2 = event.global_position
		if not _drag_active and mouse.distance_to(_drag_origin) >= CLICK_SLOP:
			_drag_active = true
			_select(null)
			# From here on the card is scenery: the board underneath it has to be
			# hoverable, or there would be nothing to aim at.
			_drag_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _drag_active:
			_drag_view.position = hand_area.get_global_transform().affine_inverse() \
					* mouse - CardView.CARD_SIZE * 0.5
			_drag_view.rotation = 0.0
			_drag_view.scale = Vector2.ONE
			var drop := _drop_at(mouse)
			_highlight_drop(drop)
			_update_target_line(mouse, drop)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed and _drag_active and _drag_view != null:
		var dragged := _drag_view
		_finish_drag(dragged, event.global_position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_hotkey(event)


func _handle_hotkey(event: InputEventKey) -> void:
	if combat == null or combat.phase != "player" or not combat.pending_choice.is_empty():
		return
	if event.keycode == KEY_ESCAPE and _capture_mode:
		_cancel_capture_mode()
		return
	if event.keycode == KEY_C:
		_on_capture_pressed()
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


## The arc from the thrower to the cursor. Drawn for anything aimed at somebody —
## an enemy or a team-mate — and gold only when it is actually over a target, so
## the line is a promise rather than decoration.
func _update_target_line(mouse: Vector2, drop: Dictionary = {}) -> void:
	if _drag_view == null or not is_instance_valid(_drag_view):
		target_line.visible = false
		return
	var card := _drag_view.card
	var aims_at_somebody := card.needs_target() \
			or card.effective_target_kind() in ["ally", "party"]
	if not aims_at_somebody:
		target_line.visible = false
		return
	var kind := String(drop.get("kind", "none"))
	var landing := kind == "enemy" or kind == "ally"
	target_line.visible = true
	var from := _player_panel_home + player_panel.size * Vector2(1.0, 0.3)
	var to := _to_local(mouse)
	target_line.clear_points()
	target_line.add_point(from)
	target_line.add_point(from.lerp(to, 0.5) + Vector2(0, -60))
	target_line.add_point(to)
	if not landing:
		target_line.default_color = Color(0.7, 0.7, 0.75, 0.55)
	elif kind == "ally":
		target_line.default_color = Color(0.55, 0.9, 0.75, 0.9)
	else:
		target_line.default_color = Color(1.0, 0.85, 0.4, 0.9)


## Lights up whatever the card is currently over, on either side of the board.
func _highlight_drop(drop: Dictionary) -> void:
	var kind := String(drop.get("kind", "none"))
	var enemy_view = drop.get("view", null)
	for v in enemy_views:
		if is_instance_valid(v):
			v.set_targeted(v == enemy_view)
	_hovered_enemy = enemy_view
	if combat != null:
		var idx := -1 if enemy_view == null else _living_index(enemy_view)
		if combat.preview_target_index != idx:
			combat.preview_target_index = idx
			_refresh_hand_text()
	var ally = drop.get("actor", null) if kind == "ally" else null
	for entry in party_views:
		var panel: Panel = (entry as Dictionary).get("panel", null)
		if panel == null or not is_instance_valid(panel):
			continue
		panel.modulate = Color(1.25, 1.2, 1.0) if entry["actor"] == ally \
				else (Color.WHITE if entry["actor"] == combat.player
						else Color(0.66, 0.65, 0.72))
	player_panel.modulate = Color(1.18, 1.16, 1.05) \
			if ally != null and combat != null and ally == combat.player else Color.WHITE


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
	if _capture_mode:
		_choose_capture_target(view)
		return
	if selected_view != null and selected_view.card.needs_target():
		var idx = _living_index(view)  # Get the current dynamic index
		if idx != -1:
			_try_play(selected_view, idx)


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
		if is_instance_valid(v):
			v.set_targeted(false)
	player_panel.modulate = Color.WHITE
	_refresh_party()


func _refresh_hand_text() -> void:
	for v in card_views:
		if is_instance_valid(v):
			v.refresh()


func _on_card_hover(view: CardView, inside: bool) -> void:
	if _drag_active or not is_instance_valid(view) or not view.visible:
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
## Throws a card, and comes straight back.
##
## The hand does not lock while a card is in the air. The card is paid for and out
## of the hand before this returns, so the next one can be thrown into the same
## breath; what waits is only the *effect*, which lands on the frame the animation
## connects. Half a dozen cards can therefore be in flight at once, each striking
## on its own beat, and none of them queues behind another.
func _try_play(view: CardView, target_index: int) -> void:
	if combat == null or not is_instance_valid(view) or view.card == null:
		return
	var card := view.card
	var check := combat.can_play(card, target_index)
	if not check["ok"]:
		prompt_label.text = String(check["why"])
		prompt_label.visible = true
		_return_card(view)
		return
	prompt_label.visible = false
	if selected_view == view:
		selected_view = null
	view.set_selected(false)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Where it is aimed and what the throw looks like are settled now: by the time
	# it lands the board may be a different shape.
	var kind := _anim_kind_for(card)
	var target_view := _view_for_living_index(target_index)
	var target_rect := _target_rect(kind, target_view)
	# It rises out of its own place in the fan rather than out of wherever the
	# cursor happened to let go of it. A card that takes off from mid-screen reads
	# as something dropped; a card that takes off from the hand reads as played.
	var from_pos := hand_area.position + view.home_position
	view.visible = false
	_clear_target_highlight()

	var token := combat.commit_card(card, target_index)
	if token.is_empty():
		# Refused after all, so put it back rather than leaving a hole in the fan.
		view.visible = true
		_return_card(view)
		return
	if target_view != null and target_view.has_method("flash"):
		target_view.flash()
	if not CardAnim.enabled:
		combat.resolve_commit(token)
		_refresh_all()
		return
	_launch_flight(card, token, kind, target_view, target_rect, from_pos,
			card.tint(), "")


## Flies one committed action to its target and lands it.
##
## Never awaited by its caller. Each flight owns its own ghost and its own token,
## so overlapping them costs nothing and resolves nothing twice — `resolve_commit`
## refuses a second call on the same token.
func _launch_flight(card: Card, token: Dictionary, kind: int, target_view: Control,
		target_rect: Rect2, from_pos: Vector2, tint: Color, label: String) -> void:
	_flights += 1
	# Held locally, so a flight that outlives its fight resolves against the
	# combat it belonged to instead of the one that replaced it.
	var cmb: Combat = combat
	await _card_anim.play(card, cmb, label, tint, from_pos, target_rect, kind,
			func():
				if cmb == null:
					return
				cmb.resolve_commit(token)
				_impact_feedback(kind, target_view))
	_flights = max(0, _flights - 1)
	if combat == cmb and combat != null:
		_refresh_all()


## Waits for everything in the air to land. Bounded, so a flight that somehow
## never finishes cannot deadlock the fight.
func _await_flights(limit: float = 3.0) -> void:
	var waited := 0.0
	while _flights > 0 and waited < limit:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05


## Which choreography a card gets: attacks are executions, self-targeting status
## is a blessing, and anything status aimed at someone else is a hex.
func _anim_kind_for(card: Card) -> int:
	if card.type() == "attack":
		return CardAnim.Kind.ATTACK
	if card.effective_target_kind() in ["self", "none"]:
		return CardAnim.Kind.BLESS
	return CardAnim.Kind.HEX


## The view for a living-enemy index.
##
## Views keep the slot they were built in, while the rules address whoever is
## still standing, so the two have to be matched through the living list rather
## than by slot — otherwise killing the front enemy sends every later card at the
## wrong picture.
func _view_for_living_index(target_index: int) -> Control:
	if target_index >= 0:
		for v in enemy_views:
			if is_instance_valid(v) and v.visible and _living_index(v) == target_index:
				return v
	for v in enemy_views:
		if is_instance_valid(v) and v.visible:
			return v
	return null


## Where the card is headed. A blessing lands on its caster; everything else on
## whoever it was aimed at.
func _target_rect(kind: int, target_view: Control) -> Rect2:
	if kind == CardAnim.Kind.BLESS or target_view == null \
			or not is_instance_valid(target_view):
		return _local_rect(player_panel)
	return _local_rect(target_view)


## Where on screen a party member is, so an enemy's blow lands on the one its AI
## actually picked rather than always on the big panel.
func _rect_for_member(who: Actor) -> Rect2:
	if who != null and combat != null and who != combat.player:
		for entry in party_views:
			var panel: Panel = (entry as Dictionary).get("panel", null)
			if entry["actor"] == who and panel != null and is_instance_valid(panel) \
					and panel.visible:
				return _local_rect(panel)
	return _local_rect(player_panel)


func _to_local(global_pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_pos


func _local_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	return Rect2(_to_local(r.position), r.size)


## The felt part of a landing: the victim recoils, and an execution shakes the
## whole screen.
func _impact_feedback(kind: int, target_view: Control) -> void:
	if target_view != null and is_instance_valid(target_view) \
			and target_view.has_method("recoil"):
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
	_cancel_capture_mode()
	_busy = true
	end_turn_button.disabled = true
	prompt_label.visible = false
	# Cards are thrown without waiting for one another, but the *turn* does not end
	# until the board has caught up: an enemy must not begin its move while the
	# last of yours is still in the air.
	await _await_flights()
	if combat == null:
		return
	if combat.finished or combat.phase != "player":
		_hand_control(not combat.finished)
		return
	combat.end_turn()
	if combat.finished:
		return
	_enemy_timer.start(0.35)


## Pumps the ATB clock until it is the player's turn again.
##
## Each call lets time run to the next actor whose gauge fills. If that is an
## enemy, its whole turn is played out here — action by action, animated, each one
## landing its own effects — and the pump is scheduled again. If it is the player,
## control comes back and the hand unlocks.
func _advance_enemy_phase() -> void:
	if combat == null or combat.finished:
		_hand_control(true)
		return

	# combat.active is set by the engine when a gauge fills; peek_enemy() reports
	# it once the floor has actually been handed over.
	var actor: Actor = combat.peek_enemy() if CardAnim.enabled else null
	if actor != null:
		await _play_enemy_turn(actor)
		if combat == null:
			return
		if not combat.finished:
			combat.finish_enemy_turn(actor)
			_refresh_all()
		if combat.finished:
			_hand_control(true)
			return
		# Straight on to whoever is next; the pacing came from the animation.
		_enemy_timer.start(0.1)
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


## One enemy's turn, played out the way the player's is.
##
## Its AI commits one action at a time and each is launched with a short stagger
## rather than waited on, so a Pokemon spending three cards throws three cards —
## overlapping, on separate beats — instead of queueing behind its own animations.
## The turn is only closed out once the last of them has landed, so end-of-turn
## upkeep never runs ahead of the blows it is supposed to follow.
func _play_enemy_turn(actor: Actor) -> void:
	if combat == null or actor == null:
		return
	var view := _view_for_actor(actor)
	var begun: Dictionary = combat.enemy_turn_begin(actor)
	_refresh_all()
	if not bool(begun.get("ok", false)):
		if String(begun.get("reason", "")) != "":
			# Asleep, frozen, flinched. It still gets a beat, so a skipped turn
			# reads as something happening rather than as a hitch.
			if view != null and is_instance_valid(view):
				view.recoil(false)
			await get_tree().create_timer(0.3).timeout
		if combat != null:
			combat.enemy_turn_end()
		return

	var launched := 0
	while true:
		if combat == null or combat.finished or not actor.alive:
			break
		if launched > 0:
			await get_tree().create_timer(ENEMY_CARD_STAGGER).timeout
			if combat == null or combat.finished:
				break
		var token: Dictionary = combat.enemy_turn_next()
		if token.is_empty():
			break
		launched += 1
		_launch_enemy_flight(actor, token)
		_refresh_all()

	await _await_flights()
	if combat != null and not combat.finished:
		combat.enemy_turn_end()
		_refresh_all()


## One of an enemy's committed actions, given the choreography a card gets — with
## the actual card when it has one, and a stand-in token when it does not.
func _launch_enemy_flight(actor: Actor, token: Dictionary) -> void:
	var view := _view_for_actor(actor)
	var card: Card = token.get("card", null)
	var intent := String(token.get("intent", "unknown"))
	var move_name := String(token.get("name", "…"))
	var victim: Actor = token.get("target", null)

	var kind := CardAnim.Kind.HEX
	if card != null:
		kind = _anim_kind_for(card)
	elif intent.begins_with("attack"):
		kind = CardAnim.Kind.ATTACK
	elif intent in ["defend", "buff", "sleep", "unknown", "escape"]:
		kind = CardAnim.Kind.BLESS
	# A card an enemy points at itself or a team-mate is a blessing on them, not a
	# hex on you, and has to fly the other way.
	if card != null and card.effective_target_kind() in ["self", "none", "ally"]:
		kind = CardAnim.Kind.BLESS

	var self_aimed := kind == CardAnim.Kind.BLESS
	var target_rect := _local_rect(view) if self_aimed and view != null \
			else _rect_for_member(victim)
	var from_pos := _local_rect(view).position if view != null \
			else Vector2(size.x * 0.5, 120.0)
	var tint := EnemyLibrary.intent_color(intent)
	if card != null:
		tint = card.tint()
	elif actor.is_pokemon() and not actor.poke_types.is_empty():
		tint = PokeData.type_color(String(actor.poke_types[0]))

	_flights += 1
	var cmb: Combat = combat
	await _card_anim.play(card, cmb, move_name, tint, from_pos, target_rect, kind,
			func():
				if cmb == null:
					return
				cmb.resolve_commit(token)
				if self_aimed:
					_impact_feedback(kind, view)
				else:
					_impact_feedback(kind, null)
					_member_recoil(victim, kind == CardAnim.Kind.ATTACK))
	_flights = max(0, _flights - 1)
	if combat == cmb and combat != null:
		_refresh_all()


func _view_for_actor(a: Actor) -> Control:
	for v in enemy_views:
		if is_instance_valid(v) and v.actor == a:
			return v
	return null


## Whichever of your own side just took the blow flinches — the acting member on
## its big panel, anybody else on their strip down the left.
func _member_recoil(who: Actor, hard: bool) -> void:
	if who == null or combat == null or who == combat.player:
		_player_recoil(hard)
		return
	for entry in party_views:
		if entry["actor"] != who:
			continue
		var panel: Panel = (entry as Dictionary).get("panel", null)
		if panel == null or not is_instance_valid(panel):
			return
		var home: Vector2 = entry.get("home", panel.position)
		var t := panel.create_tween()
		t.tween_property(panel, "position", home + Vector2(-12.0 if hard else -5.0, 0), 0.05)
		t.tween_property(panel, "position", home, 0.16) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		return
	_player_recoil(hard)


## The acting member has no EnemyView to recoil, so its panel takes the hit.
## Tweened from a remembered home rather than wherever it currently is, because
## two blows can land close enough together to overlap.
func _player_recoil(hard: bool) -> void:
	var t := player_panel.create_tween()
	t.tween_property(player_panel, "position",
			_player_panel_home + Vector2(-14.0 if hard else -6.0, 0), 0.05)
	t.tween_property(player_panel, "position", _player_panel_home, 0.16) \
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
		if is_instance_valid(v):
			v.refresh()
	_layout_enemies()
	_rebuild_hand()
	_refresh_playability()
	_refresh_capture_button()


## The Capture button says what it would cost you to press it: how many balls are
## in the bag, and whether there is anything here worth spending one on.
func _refresh_capture_button() -> void:
	if capture_button == null:
		return
	if combat == null or not Run.is_pokemon_run():
		capture_button.visible = false
		return
	capture_button.visible = true
	if _capture_mode:
		capture_button.text = "✕  Cancel"
		capture_button.disabled = false
		return
	var balls := Run.total_balls()
	capture_button.text = "◓  Capture (%d)" % balls
	capture_button.disabled = balls <= 0 or not combat.can_capture()
	capture_button.tooltip_text = "Spend your turn on a throw. %s" % (
			"No balls in the bag." if balls <= 0
			else "%d ball(s) ready." % balls)


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
	if capture_button != null:
		capture_button.disabled = true
	_cancel_capture_mode()
	_select(null)
	target_line.visible = false
	# Let whatever landed the last blow finish landing it before the screen changes.
	await _await_flights(1.2)
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


# ════════════════════════════════════ Capture ════════════════════════════════
## Reaching for a ball is a move like any other, available on any turn against
## anything still standing. Pressing the button arms it; the next enemy you click
## is the one you go after, and Main takes over from there.

func _on_capture_pressed() -> void:
	if combat == null:
		return
	if _capture_mode:
		_cancel_capture_mode()
		return
	if Run.total_balls() <= 0:
		prompt_label.text = "You have no balls. Buy some from a merchant."
		prompt_label.visible = true
		return
	if not combat.can_capture():
		prompt_label.text = "Nothing here can be caught."
		prompt_label.visible = true
		return
	_select(null)
	_capture_mode = true
	capture_button.text = "✕  Cancel"
	prompt_label.text = "Choose something to throw a ball at."
	prompt_label.visible = true
	# Only the catchable ones light up, so the choice is legible before it is made.
	for v in enemy_views:
		if is_instance_valid(v):
			v.set_targeted(combat.capture_targets().has(v.actor))


func _cancel_capture_mode() -> void:
	if not _capture_mode:
		return
	_capture_mode = false
	if capture_button != null:
		capture_button.text = "◓  Capture"
	prompt_label.visible = false
	_clear_target_highlight()


func _choose_capture_target(view: EnemyView) -> void:
	if combat == null or view == null or view.actor == null:
		return
	if not combat.capture_targets().has(view.actor):
		prompt_label.text = "%s cannot be caught." % view.actor.name
		return
	_capture_mode = false
	if capture_button != null:
		capture_button.text = "◓  Capture"
	prompt_label.visible = false
	_clear_target_highlight()
	_busy = true
	end_turn_button.disabled = true
	# Nothing should be mid-flight when the board zooms in on the target.
	await _await_flights()
	if combat == null or combat.finished or not view.actor.alive:
		_hand_control(combat != null and not combat.finished)
		return
	capture_requested.emit(view.actor)


## Where an enemy is on screen, in global coordinates. The capture screen opens by
## zooming in on exactly this rectangle, so the two pictures line up.
func enemy_rect_for(actor: Actor) -> Rect2:
	var view := _view_for_actor(actor)
	if view != null:
		return view.get_global_rect()
	return Rect2(get_global_transform() * (size * 0.5), Vector2(160, 200))


## Comes back from the throwing screen.
##
## A catch takes the target out of the fight; a throw of any kind costs the turn,
## which is what makes Capture a decision rather than a free look every round.
func resume_after_capture(result: Dictionary) -> void:
	_capture_mode = false
	if capture_button != null:
		capture_button.text = "◓  Capture"
	prompt_label.visible = false
	_clear_target_highlight()
	if combat == null:
		return
	var actor = result.get("actor", null)
	if bool(result.get("caught", false)) and actor != null:
		combat.capture_enemy(actor)
	if combat.finished:
		return
	if bool(result.get("spent_turn", false)):
		_select(null)
		_busy = true
		end_turn_button.disabled = true
		combat.spend_turn_on_capture()
		if combat.finished:
			return
		_enemy_timer.start(0.35)
	else:
		_hand_control(true)
		_refresh_all()


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
