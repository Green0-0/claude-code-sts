extends Node

## Development harness. Plays the game by itself so the whole flow can be
## exercised head-less.
##
##   godot --headless -- --smoke        one ordinary run
##   godot --headless -- --smoke-deep   immortal player, many runs, full coverage
##   godot --headless -- --smoke-poke   the same, played as Pokemon
##
## Deep mode keeps the player alive so every act, boss, shop and event gets hit.

const MAX_STEPS := 300000
const TIME_SCALE := 60.0

var steps: int = 0
var runs_done: int = 0
var target_runs: int = 1
var immortal: bool = false
var poke_mode: bool = false
var shots: bool = false

## A deliberate spread for Pokemon runs: a frail starter, a bulky wall, a glass
## cannon, a legendary, and the species with no usable level-up moves.
const POKE_ROTATION := ["bulbasaur", "snorlax", "alakazam", "mewtwo", "abra",
		"magikarp", "gyarados", "ditto"]
var shot_dir: String = "user://shots"
var shots_taken: Dictionary = {}
var _shot_cooldown: int = 0
var main: Node = null
var report: Dictionary = {}
var _last_signature: String = ""
var _stall: int = 0


func _ready() -> void:
	main = get_parent()
	# Card animations resolve their effects on a delay, which this harness has no
	# way to wait for — and 1900 cards at ~0.8s each would take half an hour.
	CardAnim.enabled = false
	Engine.time_scale = TIME_SCALE
	Engine.max_fps = 0
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	args.append_array(OS.get_cmdline_user_args())
	poke_mode = "--smoke-poke" in args
	immortal = "--smoke-deep" in args or poke_mode
	shots = "--shots" in args
	if shots:
		Engine.time_scale = 1.0
		immortal = true
	target_runs = 8 if immortal else 1
	report = {"combats": 0, "cards_played": 0, "turns": 0, "rooms": {}, "runs": 0,
			"enemies": {}, "cards": {}, "relics": {}, "acts_reached": 1, "errors": [],
			"evolutions": 0, "max_level": 0}
	print("[autoplay] starting (immortal=%s, runs=%d)" % [immortal, target_runs])


func _process(_delta: float) -> void:
	_tick()


func _tick() -> void:
	steps += 1
	if steps > MAX_STEPS:
		_finish("step limit reached")
		return
	var sig := _signature()
	if sig == _last_signature:
		_stall += 1
		if _stall > 4000:
			report["errors"].append("stalled at: %s" % sig)
			_finish("stalled")
			return
	else:
		_stall = 0
		_last_signature = sig

	if shots:
		_maybe_shoot()
		if _shot_cooldown > 0:
			_shot_cooldown -= 1
			return

	if main.card_picker.visible:
		_drive_picker()
		return
	var screen: Control = main.current_screen
	if screen == null:
		return
	match screen.name:
		"TitleScreen":
			if poke_mode:
				var mon: String = POKE_ROTATION[runs_done % POKE_ROTATION.size()]
				print("[autoplay] run %d as %s" % [runs_done + 1, mon])
				main._on_start_run(PokeCharacters.character_id(mon), 0)
			else:
				main._on_start_run("ironclad" if runs_done % 2 == 0 else "silent", 0)
		"MapScreen":
			_drive_map()
		"CombatScreen":
			_drive_combat()
		"RewardScreen":
			_drive_reward()
		"ShopScreen":
			_drive_shop()
		"RestScreen":
			_drive_rest()
		"EventScreen":
			_drive_event()
		"EvolutionScreen":
			_drive_evolution()
		"GameOverScreen":
			runs_done += 1
			report["runs"] = runs_done
			print("[autoplay] run %d ended — act %d floor %d" % [runs_done, Run.act,
					Run.floor_num])
			if runs_done >= target_runs:
				_finish("completed %d run(s)" % runs_done)
			else:
				main._on_restart()


## Always evolves. The alternative branch is "stay as you are", which would let
## a run coast without ever testing the evolution path.
func _drive_evolution() -> void:
	var options: Array = main.evolution_screen.options_box.get_children()
	if options.is_empty():
		return
	report["evolutions"] = int(report.get("evolutions", 0)) + 1
	(options[0] as Button).emit_signal("pressed")


func _signature() -> String:
	var s := "%s|%d" % [main.current_screen.name if main.current_screen else "?", Run.floor_num]
	if main.current_screen == main.combat_screen and main.combat_screen.combat != null:
		var c = main.combat_screen.combat
		s += "|t%d|e%d|h%d|hp%d|d%d" % [c.turn, c.energy, c.hand.size(), c.player.hp,
				c.discard_pile.size()]
	if main.card_picker.visible:
		s += "|picker%d" % main.card_picker._selection.size()
	s += "|lv%d" % Run.player_level
	return s


## Screenshot mode: one PNG per distinct screen, so the layout can be eyeballed.
func _maybe_shoot() -> void:
	var key := String(main.current_screen.name) if main.current_screen != null else "none"
	if main.card_picker.visible:
		key = "CardPicker_" + String(main.card_picker._mode)
	if main.current_screen == main.combat_screen and main.combat_screen.combat != null:
		key = "CombatScreen_t%d" % mini(3, main.combat_screen.combat.turn)
	if shots_taken.has(key):
		return
	shots_taken[key] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	# Freeze the driver first: the await below yields, and without the cooldown the
	# rest of this frame's _tick would advance the screen before the grab lands.
	_shot_cooldown = 30
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [shot_dir, shots_taken.size(), key]
	img.save_png(path)
	print("[autoplay] shot %s -> %s" % [key, ProjectSettings.globalize_path(path)])
	if shots_taken.size() >= 14:
		_finish("captured %d screens" % shots_taken.size())


func _bump(bucket: String, key: String) -> void:
	var d: Dictionary = report[bucket]
	d[key] = int(d.get(key, 0)) + 1


func _drive_picker() -> void:
	var picker = main.card_picker
	if picker._mode == "view":
		picker._on_cancel()
	elif picker._mode == "instant":
		if picker._views.size() > 0:
			picker._on_card_pressed(picker._views[randi() % picker._views.size()])
		else:
			picker._on_cancel()
	else:
		var guard := 0
		while picker._selection.size() < picker._needed and guard < 20:
			guard += 1
			var pick = null
			for v in picker._views:
				if not picker._selection.has(v.card):
					pick = v
					break
			if pick == null:
				break
			picker._on_card_pressed(pick)
		if picker._selection.size() == picker._needed:
			picker._on_confirm()
		else:
			picker._on_cancel()


func _drive_map() -> void:
	report["acts_reached"] = maxi(int(report["acts_reached"]), Run.act)
	var avail: Array = Run.available_nodes()
	if avail.is_empty():
		main._return_to_map()
		return
	# Prefer the harder / richer rooms in deep mode so they all get tested.
	var idx: int = int(avail[randi() % avail.size()])
	if immortal:
		for candidate in avail:
			var ct := String(Run.node_at(int(candidate))["type"])
			if ct in ["elite", "shop", "event", "boss"] and randf() < 0.7:
				idx = int(candidate)
				break
	var t: String = String(Run.node_at(idx)["type"])
	_bump("rooms", t)
	main._on_map_node_chosen(idx)


func _drive_combat() -> void:
	var cs = main.combat_screen
	var c = cs.combat
	if c == null or c.finished:
		return
	if not c.pending_choice.is_empty():
		return
	if c.phase != "player" or cs._busy:
		return
	if immortal:
		c.player.hp = c.player.max_hp
		Run.hp = Run.max_hp
	report["max_level"] = maxi(int(report.get("max_level", 0)), Run.player_level)
	for e in c.living_enemies():
		_bump("enemies", e.enemy_id)
	if randf() < 0.03:
		for i in range(Run.potions.size()):
			if String(Run.potions[i]) != "":
				cs.use_potion(i)
				return
	# Play the most expensive playable card first; that reaches the fancier cards.
	var best = null
	var best_cost := -99
	for card in c.hand:
		var needs: bool = card.needs_target()
		var probe: int = 0 if needs else -1
		if not c.can_play(card, probe)["ok"]:
			continue
		var cst: int = card.cost(c)
		if card.is_x_cost():
			cst = c.energy
		if cst > best_cost:
			best_cost = cst
			best = card
	if best != null:
		var target: int = 0
		if best.needs_target():
			target = randi() % maxi(1, c.living_enemies().size())
		_bump("cards", String(best.id))
		if c.play_card(best, target):
			report["cards_played"] = int(report["cards_played"]) + 1
			return
	report["turns"] = int(report["turns"]) + 1
	cs._on_end_turn()


func _drive_reward() -> void:
	var rs = main.reward_screen
	for child in rs.rows_box.get_children():
		var btn := child as Button
		if btn != null and not btn.disabled:
			btn.pressed.emit()
			return
	report["combats"] = int(report["combats"]) + 1
	for rid in Run.relics:
		_bump("relics", String(rid))
	rs.finished.emit()


func _drive_shop() -> void:
	var ss = main.shop_screen
	if immortal:
		Run.gold = maxi(Run.gold, 400)
	if randf() < 0.4:
		for i in range((ss.stock["cards"] as Array).size()):
			if not bool(ss.stock["cards"][i]["sold"]) \
					and Run.gold >= int(ss.stock["cards"][i]["price"]):
				ss._buy_card(i)
				return
	if randf() < 0.3:
		for i in range((ss.stock["relics"] as Array).size()):
			if not bool(ss.stock["relics"][i]["sold"]) \
					and Run.gold >= int(ss.stock["relics"][i]["price"]):
				ss._buy_relic(i)
				return
	if randf() < 0.3:
		for i in range((ss.stock["potions"] as Array).size()):
			if not bool(ss.stock["potions"][i]["sold"]) and Run.has_potion_space() \
					and Run.gold >= int(ss.stock["potions"][i]["price"]):
				ss._buy_potion(i)
				return
	if randf() < 0.25 and not ss.remove_button.disabled:
		ss.removal_requested.emit()
		return
	ss.leave_requested.emit()


func _drive_rest() -> void:
	var rs = main.rest_screen
	if rs.leave_button.visible:
		rs.finished.emit()
	elif not rs.smith_button.disabled and randf() < 0.5:
		rs.smith_requested.emit()
	elif not rs.rest_button.disabled:
		rs._on_rest()
	else:
		rs._lock()


func _drive_event() -> void:
	var es = main.event_screen
	if es.continue_button.visible:
		es.finished.emit()
		return
	var opts: Array = es.options_box.get_children()
	var enabled: Array = []
	for o in opts:
		if not (o as Button).disabled:
			enabled.append(o)
	if enabled.is_empty():
		es.show_result("(autoplay) no options")
		return
	(enabled[randi() % enabled.size()] as Button).pressed.emit()


func _finish(reason: String) -> void:
	set_process(false)
	print("[autoplay] finished: %s" % reason)
	print("[autoplay] steps=%d runs=%d max_act=%d" % [steps, runs_done,
			int(report["acts_reached"])])
	print("[autoplay] rooms=%s" % JSON.stringify(report["rooms"]))
	print("[autoplay] combats=%d cards_played=%d turns=%d" % [int(report["combats"]),
			int(report["cards_played"]), int(report["turns"])])
	print("[autoplay] evolutions=%d max_level=%d" % [
			int(report.get("evolutions", 0)), int(report.get("max_level", 0))])
	print("[autoplay] distinct_enemies=%d distinct_cards=%d distinct_relics=%d" % [
			(report["enemies"] as Dictionary).size(), (report["cards"] as Dictionary).size(),
			(report["relics"] as Dictionary).size()])
	print("[autoplay] enemies=%s" % JSON.stringify((report["enemies"] as Dictionary).keys()))
	print("[autoplay] cards=%s" % JSON.stringify((report["cards"] as Dictionary).keys()))
	print("[autoplay] errors=%s" % JSON.stringify(report["errors"]))
	get_tree().quit(0)
