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
## Cast animations fly out of the hand, so they have to clear even a dragged
## card. Still well under Main.OVERLAY_Z, so a prompt covers them.
const CAST_Z := 700

@onready var enemy_area: Control = $EnemyArea
@onready var hand_area: Control = $HandArea
@onready var player_panel: Panel = $PlayerPanel
@onready var player_name: Label = $PlayerPanel/NameLabel
@onready var player_hp_bar: ProgressBar = $PlayerPanel/HpBar
@onready var player_hp_label: Label = $PlayerPanel/HpBar/HpLabel
@onready var player_block: Label = $PlayerPanel/BlockLabel
@onready var player_status_box: HBoxContainer = $PlayerPanel/StatusBox
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
var cast_fx: CastFx = null
var player_sprite: PokeSprite = null
var _busy: bool = false
var _log_lines: Array = []


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
	set_process_input(true)
	# Casts play above the hand fan but below the modal picker — see the z-index
	# budget at the top of this file and Main.OVERLAY_Z.
	cast_fx = CastFx.new()
	cast_fx.name = "CastFx"
	cast_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	cast_fx.z_index = CAST_Z
	add_child(cast_fx)
	$EnergyOrb.add_theme_stylebox_override("panel", UiTheme.orb_style())
	player_panel.add_theme_stylebox_override("panel", UiTheme.player_style())
	UiTheme.style_hp_bar(player_hp_bar)


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
	combat.move_cast.connect(_on_move_cast)
	_log_lines.clear()
	combat_log.clear()
	combat.setup(enemy_ids, room_type, Run.rng)
	_setup_player_sprite()
	_build_enemy_views()
	_rebuild_hand()
	_refresh_all()


func _clear() -> void:
	for v in enemy_views:
		v.queue_free()
	enemy_views.clear()
	for v in card_views:
		v.queue_free()
	card_views.clear()
	selected_view = null
	_drag_view = null
	_drag_active = false
	_busy = false
	combat = null
	target_line.visible = false
	_hovered_enemy = null
	if cast_fx != null and is_instance_valid(cast_fx):
		cast_fx.clear_all()
	# Otherwise the last fight's targeting line ("… It's super effective!") is
	# still on screen when the next one starts.
	prompt_label.visible = false
	prompt_label.text = ""


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


# ═════════════════════════════════ Hand layout ═══════════════════════════════
func _rebuild_hand() -> void:
	var wanted: Array = []
	for c in combat.hand:
		wanted.append(c.uid)
	var current: Array = []
	for v in card_views:
		current.append(v.card.uid)
	if wanted == current:
		for v in card_views:
			v.combat = combat
			v.set_playable(combat.can_play(v.card, 0 if v.card.needs_target() else -1)["ok"])
			v.refresh()
		_layout_hand()
		return

	for v in card_views:
		v.queue_free()
	card_views.clear()
	for c in combat.hand:
		var view: CardView = CARD_SCENE.instantiate()
		hand_area.add_child(view)
		view.setup(c, combat)
		view.pressed.connect(_on_card_pressed)
		view.released.connect(_on_card_released)
		view.hover_changed.connect(_on_card_hover)
		card_views.append(view)
	_layout_hand(true)
	_refresh_playability()


func _layout_hand(instant: bool = false) -> void:
	var n := card_views.size()
	if n == 0:
		return
	var spacing: float = minf(168.0, maxf(70.0, (hand_area.size.x - 240.0) / float(n)))
	var center_x := hand_area.size.x * 0.5
	var base_y := hand_area.size.y - CardView.CARD_SIZE.y - 18.0
	for i in range(n):
		var v: CardView = card_views[i]
		var offset := float(i) - float(n - 1) * 0.5
		var norm := offset / maxf(1.0, float(n - 1) * 0.5)
		# The fan arcs upward in the middle; the outermost cards sit on base_y so
		# nothing is ever pushed off the bottom of the screen.
		v.home_position = Vector2(center_x + offset * spacing - CardView.CARD_SIZE.x * 0.5,
				base_y - (1.0 - norm * norm) * 26.0)
		v.home_rotation = offset * 0.035
		v.home_scale = 1.0
		v.z_index = i
		if v == _drag_view and _drag_active:
			continue
		if instant:
			v.snap_home()
		elif v.selected:
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
	combat.play_card(view.card, target_index)
	_clear_target_highlight()


# ═══════════════════════════════ Player sprite ═══════════════════════════════
## Stands the player's Pokemon in its own panel, mirrored so it faces the enemy
## line on the right — the arrangement the games use.
##
## The panel is laid out for a name and three rows of stats across its full
## width, so making room means re-flowing it into two columns. That only happens
## for a Pokemon run: an Ironclad has no sprite and keeps the original layout
## exactly as the scene defines it.
func _setup_player_sprite() -> void:
	var mon := Run.player_mon()
	if mon.is_empty():
		return
	var dex := int(mon.get("id", 0))
	if dex <= 0 or not PokeSprite.exists_for(dex):
		return

	if player_sprite == null:
		player_sprite = PokeSprite.new()
		player_sprite.name = "PlayerSprite"
		player_sprite.shadow_colour = Color(0, 0, 0, 0.32)
		player_panel.add_child(player_sprite)
		player_panel.move_child(player_sprite, 0)
	player_sprite.position = Vector2(6, 26)
	player_sprite.size = Vector2(124, 132)
	player_sprite.show_pokemon(dex, true)

	# Stats move over to the right of the sprite.
	var left := 132.0
	var right := player_panel.size.x - 12.0
	_place(player_name, left, 10.0, right, 42.0)
	_place(player_hp_bar, left + 4.0, 48.0, right - 4.0, 76.0)
	_place(player_block, left + 4.0, 82.0, right - 4.0, 108.0)
	_place(player_status_box, left, 112.0, right, 172.0)


func _place(node: Control, l: float, t: float, r: float, b: float) -> void:
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = Vector2(l, t)
	node.size = Vector2(r - l, b - t)


# ══════════════════════════════ Cast animations ══════════════════════════════
## Turns "this card is being played" into one of CastFx's three routines. The
## engine says what happened; everything about how it looks is decided here.
func _on_move_cast(info: Dictionary) -> void:
	if cast_fx == null or not is_instance_valid(cast_fx):
		return
	var source: Actor = info.get("source", null)
	var target: Actor = info.get("target", null)
	var card: Card = info.get("card", null)
	var effects: Array = info.get("effects", [])
	if source == null:
		return

	var on_self := CastFx.targets_self(effects, String(info.get("card_target", "")))
	var kind := CastFx.classify(effects, source.is_player, on_self)

	# Who it lands on: itself, the player, or one of the enemy row.
	var landed_on: Actor = source if on_self else target
	var view := _view_for(landed_on)
	if view == null:
		return

	var global_rect: Rect2 = view.impact_rect() if view.has_method("impact_rect") \
			else view.get_global_rect()
	var inv := cast_fx.get_global_transform().affine_inverse()
	var rect := Rect2(inv * global_rect.position, global_rect.size)
	var from := _cast_origin(source)
	cast_fx.play(kind, String(info.get("name", "")), _cast_colour(card, source, effects),
			from, rect, view)


## The on-screen thing representing an actor: its enemy card, or the player panel.
func _view_for(who: Actor) -> Control:
	if who == null:
		return null
	if who.is_player:
		return player_panel
	for v in enemy_views:
		if v.actor == who and v.visible:
			return v
	return null


## Casts rise out of the hand for the player, and out of the caster for enemies.
func _cast_origin(source: Actor) -> Vector2:
	var inv := cast_fx.get_global_transform().affine_inverse()
	if source.is_player:
		var hand_rect := hand_area.get_global_rect()
		return inv * Vector2(hand_rect.get_center().x, hand_rect.position.y + 40.0)
	var view := _view_for(source)
	if view != null:
		return inv * view.get_global_rect().get_center()
	return inv * get_global_rect().get_center()


func _cast_colour(card: Card, source: Actor, effects: Array) -> Color:
	if card != null:
		return card.tint()
	# An enemy move borrows its Pokemon's type colour, or the Spire's intent hue.
	if source.is_pokemon() and not source.poke_types.is_empty():
		return PokeData.type_color(String(source.poke_types[0]))
	return EnemyLibrary.intent_color(String(source.intent.get("kind", "attack")))


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


func _advance_enemy_phase() -> void:
	if combat == null or combat.finished:
		_busy = false
		end_turn_button.disabled = false
		return
	var more := combat.step_enemy()
	_refresh_all()
	if more:
		_enemy_timer.start(0.55)
	else:
		_busy = false
		end_turn_button.disabled = combat.finished


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
	player_hp_bar.max_value = max(1, p.max_hp)
	player_hp_bar.value = p.hp
	player_hp_label.text = "%d / %d" % [p.hp, p.max_hp]
	player_block.visible = p.block > 0
	player_block.text = "🛡 %d" % p.block
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
