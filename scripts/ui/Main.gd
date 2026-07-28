extends Node

## Screen router and run flow. Owns every screen and decides what happens next.

@onready var title_screen: Control = $Screens/TitleScreen
@onready var map_screen: Control = $Screens/MapScreen
@onready var combat_screen: Control = $Screens/CombatScreen
@onready var reward_screen: Control = $Screens/RewardScreen
@onready var shop_screen: Control = $Screens/ShopScreen
@onready var rest_screen: Control = $Screens/RestScreen
@onready var event_screen: Control = $Screens/EventScreen
@onready var gameover_screen: Control = $Screens/GameOverScreen
@onready var gameover_title: Label = $Screens/GameOverScreen/TitleLabel
@onready var gameover_stats: Label = $Screens/GameOverScreen/StatsLabel
@onready var gameover_button: Button = $Screens/GameOverScreen/RestartButton
@onready var card_picker: Control = $CardPicker
@onready var top_bar: Panel = $TopBar
@onready var toast: Label = $Toast

var current_screen: Control = null
var _picker_purpose: String = ""
var _picker_row: int = -1
var _pending_event_request: String = ""
var _room_type: String = "monster"
var _toast_timer: Timer = null


func _ready() -> void:
	get_window().theme = UiTheme.build()
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): toast.visible = false)
	add_child(_toast_timer)

	title_screen.start_requested.connect(_on_start_run)
	title_screen.continue_requested.connect(_on_continue_run)
	map_screen.node_chosen.connect(_on_map_node_chosen)
	combat_screen.combat_over.connect(_on_combat_over)
	combat_screen.choice_needed.connect(_on_combat_choice)
	combat_screen.pile_view_requested.connect(_on_pile_view)
	reward_screen.card_reward_requested.connect(_on_card_reward)
	reward_screen.finished.connect(_on_rewards_finished)
	shop_screen.leave_requested.connect(_return_to_map)
	shop_screen.removal_requested.connect(_on_shop_removal)
	rest_screen.smith_requested.connect(_on_smith)
	rest_screen.finished.connect(_return_to_map)
	event_screen.option_chosen.connect(_on_event_option)
	event_screen.finished.connect(_return_to_map)
	gameover_button.pressed.connect(_on_restart)
	card_picker.confirmed.connect(_on_picker_confirmed)
	card_picker.cancelled.connect(_on_picker_cancelled)
	top_bar.deck_view_requested.connect(_on_deck_view)
	top_bar.potion_used.connect(_on_potion_used)
	top_bar.potion_discarded.connect(_on_potion_discarded)
	top_bar.menu_requested.connect(_on_menu)

	_show(title_screen)
	title_screen.refresh()
	top_bar.visible = false

	var cli: Array = []
	cli.append_array(OS.get_cmdline_args())
	cli.append_array(OS.get_cmdline_user_args())
	if "--rules-test" in cli:
		var tester: Node = load("res://scripts/dev/RulesTest.gd").new()
		tester.name = "RulesTest"
		add_child(tester)
	elif "--smoke" in cli or "--smoke-deep" in cli or "--shots" in cli:
		var auto: Node = load("res://scripts/dev/AutoPlay.gd").new()
		auto.name = "AutoPlay"
		add_child(auto)


# ════════════════════════════════ Screen plumbing ════════════════════════════
func _show(screen: Control) -> void:
	for child in $Screens.get_children():
		(child as Control).visible = child == screen
	current_screen = screen
	top_bar.visible = screen != title_screen and screen != gameover_screen
	top_bar.potions_enabled = screen == combat_screen
	if top_bar.visible:
		top_bar.refresh()


func show_toast(text: String) -> void:
	toast.text = text
	toast.visible = true
	_toast_timer.start(2.4)


# ══════════════════════════════════ Run start ════════════════════════════════
func _on_start_run(character: String, seed_value: int) -> void:
	Run.start_run(character, seed_value, Run.ascension)
	_go_to_map()


func _on_continue_run() -> void:
	if Run.load_run():
		show_toast("Run restored — Act %d, Floor %d." % [Run.act, Run.floor_num])
		_go_to_map()
	else:
		show_toast("No save found.")


func _go_to_map() -> void:
	_show(map_screen)
	map_screen.refresh()
	Run.save_run()


func _return_to_map() -> void:
	if Run.is_dead():
		_game_over(false)
		return
	if Run.available_nodes().is_empty() and Run.current_node >= 0:
		# Past the boss: either the next act, or the end of the run.
		if Run.at_boss():
			_after_boss()
			return
	_go_to_map()


# ════════════════════════════════ Room routing ═══════════════════════════════
func _on_map_node_chosen(idx: int) -> void:
	Run.enter_node(idx)
	_room_type = String(Run.node_at(idx)["type"])
	match _room_type:
		"monster", "elite", "boss":
			_start_combat(_room_type)
		"rest":
			_show(rest_screen)
			rest_screen.refresh()
		"shop":
			_show(shop_screen)
			shop_screen.open_shop(Run.generate_shop())
		"treasure":
			_open_treasure()
		"event":
			_show(event_screen)
			event_screen.show_event(Run.pick_event())
		_:
			_start_combat("monster")
	Run.save_run()


func _start_combat(kind: String) -> void:
	var group := Run.encounter_for_node(kind)
	_show(combat_screen)
	combat_screen.begin(group, kind)
	show_toast(_describe_group(group))


func _describe_group(group: Array) -> String:
	var names: Array = []
	for id in group:
		names.append(String(EnemyLibrary.get_def(String(id))["name"]))
	return " · ".join(names)


func _open_treasure() -> void:
	var rewards: Array = []
	var rid := Run.random_relic()
	if rid != "":
		rewards.append({"kind": "relic", "id": rid})
	if Run.rng.randf() < 0.5:
		rewards.append({"kind": "gold", "amount": Run.rng.randi_range(25, 50)})
	if Run.rng.randf() < 0.4 and Run.has_potion_space():
		rewards.append({"kind": "potion", "id": PotionLibrary.random_potion(Run.rng)})
	_show(reward_screen)
	reward_screen.show_rewards("A Treasure Chest!", rewards)


# ═════════════════════════════════ Combat end ════════════════════════════════
func _on_combat_over(victory: bool) -> void:
	if not victory:
		_game_over(false)
		return
	Run.run_score += 5 if _room_type == "monster" else 25
	if _room_type == "elite":
		Run.elites_slain += 1
	var rewards: Array = []
	rewards.append({"kind": "gold", "amount": Run.combat_gold_reward(_room_type)})
	var card_count := 3
	var ids := Run.random_card_ids(card_count)
	if ids.size() > 0:
		rewards.append({"kind": "cards", "ids": ids})
	if _room_type == "elite":
		var rid := Run.random_relic()
		if rid != "":
			rewards.append({"kind": "relic", "id": rid})
	elif _room_type == "boss":
		var brid := Run.random_relic("boss")
		if brid != "":
			rewards.append({"kind": "relic", "id": brid})
	if Run.rng.randf() < (0.4 if _room_type != "boss" else 1.0) and Run.has_potion_space():
		rewards.append({"kind": "potion", "id": PotionLibrary.random_potion(Run.rng)})
	_show(reward_screen)
	reward_screen.show_rewards("Victory!" if _room_type != "boss" else "The Boss Falls!",
			rewards)
	Run.save_run()


func _on_rewards_finished() -> void:
	if _room_type == "boss":
		_after_boss()
		return
	_return_to_map()


func _after_boss() -> void:
	if Run.act >= 3:
		_game_over(true)
		return
	if Run.advance_act():
		show_toast("You descend deeper. Act %d." % Run.act)
		_go_to_map()
	else:
		_game_over(true)


func _game_over(victory: bool) -> void:
	gameover_title.text = "THE SPIRE IS SLAIN" if victory else "YOU DIED"
	gameover_title.modulate = Color(0.95, 0.85, 0.4) if victory \
			else Color(0.9, 0.35, 0.35)
	gameover_stats.text = "Act %d · Floor %d\nElites slain: %d · Bosses slain: %d\n%d Gold · %d cards · %d relics\nScore: %d" % [
			Run.act, Run.floor_num, Run.elites_slain, Run.bosses_slain,
			Run.gold, Run.deck.size(), Run.relics.size(), Run.run_score]
	Run.end_run()
	_show(gameover_screen)


func _on_restart() -> void:
	_show(title_screen)
	title_screen.refresh()


# ═══════════════════════════════ Card picker uses ════════════════════════════
func _on_combat_choice(request: Dictionary) -> void:
	_picker_purpose = "combat"
	var options: Array = combat_screen.combat.choice_options()
	var count: int = min(int(request.get("count", 1)), options.size())
	if options.is_empty() or count <= 0:
		combat_screen.submit_choice([])
		return
	card_picker.open_select(String(request.get("prompt", "Choose")), options, count,
			combat_screen.combat, bool(request.get("optional", false)))


func _on_card_reward(ids: Array, row: int) -> void:
	_picker_purpose = "reward"
	_picker_row = row
	var cards: Array = []
	for id in ids:
		var c := Card.create(String(id), Run.should_upgrade_reward_card())
		cards.append(c)
	card_picker.open_instant("Choose a card to add", cards, null, true)


func _on_shop_removal() -> void:
	_picker_purpose = "shop_removal"
	card_picker.open_instant("Remove which card?", Run.removable_cards(), null, true)


func _on_smith() -> void:
	_picker_purpose = "smith"
	card_picker.open_instant("Upgrade which card?", Run.upgradable_cards(), null, true)


func _on_deck_view() -> void:
	_picker_purpose = "view"
	var sorted: Array = Run.deck.duplicate()
	sorted.sort_custom(func(a, b): return a.display_name() < b.display_name())
	card_picker.open_view("Your Deck (%d cards)" % Run.deck.size(), sorted)


func _on_pile_view(title: String, cards: Array) -> void:
	_picker_purpose = "view"
	card_picker.open_view(title, cards, combat_screen.combat)


func _on_picker_confirmed(cards: Array) -> void:
	match _picker_purpose:
		"combat":
			combat_screen.submit_choice(cards)
		"reward":
			if cards.size() > 0:
				Run.add_card(cards[0])
				show_toast("%s added to your deck." % (cards[0] as Card).display_name())
			reward_screen.mark_claimed(_picker_row)
		"shop_removal":
			if cards.size() > 0:
				shop_screen.complete_removal(cards[0])
		"smith":
			if cards.size() > 0:
				(cards[0] as Card).upgrade()
				Run.deck_changed.emit()
				rest_screen.on_smith_done((cards[0] as Card).display_name())
		"event":
			if cards.size() > 0:
				var msg := Run.complete_event_request(_pending_event_request, cards[0])
				event_screen.show_result(msg)
	_picker_purpose = ""
	top_bar.refresh()
	Run.save_run()


func _on_picker_cancelled() -> void:
	match _picker_purpose:
		"combat":
			combat_screen.combat.cancel_choice()
		"reward":
			reward_screen.mark_claimed(_picker_row)
			show_toast("You skip the card reward.")
		"event":
			event_screen.show_result("You decide against it.")
	_picker_purpose = ""


# ══════════════════════════════════ Events ═══════════════════════════════════
func _on_event_option(event_id: String, option_index: int) -> void:
	var result := Run.apply_event_option(event_id, option_index)
	var request := String(result.get("request", ""))
	if request != "":
		_pending_event_request = request
		_picker_purpose = "event"
		var pool: Array = Run.upgradable_cards() if request == "upgrade" \
				else Run.removable_cards()
		if pool.is_empty():
			event_screen.show_result("You have no suitable cards.")
		else:
			card_picker.open_instant(String(result["log"]), pool, null, false)
	else:
		event_screen.show_result(String(result["log"]))
	top_bar.refresh()


# ══════════════════════════════════ Potions ══════════════════════════════════
func _on_potion_used(slot: int) -> void:
	var pid := String(Run.potions[slot])
	if pid == "":
		return
	var d := PotionLibrary.get_def(pid)
	if current_screen == combat_screen:
		combat_screen.use_potion(slot)
	elif not bool(d["combat_only"]):
		# Out-of-combat potions apply directly to the run state.
		for eff in d["effects"]:
			match String(eff.get("op", "")):
				"heal_percent":
					Run.heal(int(round(Run.max_hp * int(eff["amount"]) / 100.0)))
				"heal":
					Run.heal(int(eff["amount"]))
				"max_hp":
					Run.add_max_hp(int(eff["amount"]))
		Run.remove_potion(slot)
		show_toast("You drink the %s." % String(d["name"]))
	else:
		show_toast("%s can only be used in combat." % String(d["name"]))
	top_bar.refresh()


func _on_potion_discarded(slot: int) -> void:
	if String(Run.potions[slot]) == "":
		return
	show_toast("You pour out the %s." % PotionLibrary.display_name(String(Run.potions[slot])))
	Run.remove_potion(slot)
	top_bar.refresh()


func _on_menu() -> void:
	if current_screen == combat_screen:
		show_toast("You cannot flee mid-combat.")
		return
	Run.save_run()
	show_toast("Run saved.")
	_show(title_screen)
	title_screen.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if card_picker.visible:
			card_picker._on_cancel()
