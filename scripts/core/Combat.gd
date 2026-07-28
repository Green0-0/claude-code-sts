class_name Combat
extends RefCounted

## The whole combat rules engine. It is completely UI-independent: the UI listens
## to the signals below and calls play_card / end_turn / step_enemy / resolve_choice.

signal changed
signal logged(text: String)
signal floating(target: Actor, text: String, kind: String)
signal choice_requested(request: Dictionary)
signal enemy_died(who: Actor)
signal player_turn_started
signal combat_finished(victory: bool)
signal card_flew(card: Card, from_pile: String, to_pile: String)
## A card or enemy move is being executed. Purely so the UI can animate it —
## nothing waits on it, and combat resolves whether or not anyone is listening.
## Payload: {source, target, card, name, effects, card_target}.
signal move_cast(info: Dictionary)

const HAND_LIMIT := 10

var player: Actor = null
var enemies: Array = []                ## Array[Actor]
var draw_pile: Array = []              ## Array[Card]
var hand: Array = []
var discard_pile: Array = []
var exhaust_pile: Array = []

var energy: int = 0
var energy_per_turn: int = 3
var base_draw: int = 5
var turn: int = 0
var phase: String = "start"            ## start | player | enemy | done
var rng := RandomNumberGenerator.new()
var room_type: String = "monster"
var finished: bool = false
var victory: bool = false

## Per-turn / per-combat bookkeeping
var cards_played_this_turn: int = 0
var attacks_played_this_turn: int = 0
var discards_this_turn: int = 0
var hp_loss_events: int = 0
var extra_energy_next_turn: int = 0
var extra_draw_next_turn: int = 0
var block_next_turn: int = 0
var shuffles: int = 0
var attack_counter: int = 0            ## for Pen Nib
var turn_attack_counter: int = 0       ## for Kunai / Shuriken / Ornamental Fan
var lost_hp_this_combat: bool = false
var preview_target_index: int = -1
var potions_used: int = 0

var pending_choice: Dictionary = {}
var _queue: Array = []
var _resolving: bool = false
var _enemy_order: Array = []
var _enemy_index: int = 0
var _temp_thorns: int = 0
var _preempting: bool = false      ## inside the faster side's opening attack


# ══════════════════════════════════ Setup ════════════════════════════════════
func setup(enemy_ids: Array, node_type: String, run_rng: RandomNumberGenerator) -> void:
	room_type = node_type
	rng = run_rng
	player = Actor.make_player(String(CardLibrary.character(Run.character)["name"]),
			Run.hp, Run.max_hp)
	var slot := 0
	for id in enemy_ids:
		var e := EnemyLibrary.spawn(id, rng, Run.ascension)
		e.slot = slot
		slot += 1
		enemies.append(e)
	for c in Run.deck:
		var inst: Card = c
		inst.cost_override = -99
		inst.free_this_turn = false
		inst.bonus_damage = 0
		inst.in_combat_upgrade = false
		draw_pile.append(inst)
	_shuffle(draw_pile)
	_apply_poke_player_stats()
	_apply_combat_start_relics()
	for e in enemies:
		_pick_intent(e)
	phase = "player"
	_preemptive_strike()
	if finished:
		return
	_start_player_turn()


## A player Pokemon fights with its own species' numbers: base stats and types
## for the damage formula, and Speed for how much it gets done each turn.
func _apply_poke_player_stats() -> void:
	var mon := Run.player_mon()
	if mon.is_empty():
		return
	player.poke_name = String(mon["name"])
	player.poke_stats = mon["stats"]
	player.poke_types = mon["types"]
	player.stat_scale = PokeBalance.trainer_scale(mon)
	energy_per_turn = PokeBalance.energy_for(mon)
	base_draw = PokeBalance.draw_for(mon)


## The fastest thing in the room gets the jump on you and attacks before your
## first turn. This is what Speed buys an enemy.
##
## Only the single fastest one acts, and it cannot take you below 1 HP: a pack
## of three quick Deerling would otherwise end the fight before you drew a hand,
## which is not a fight. You always get your first turn.
func _preemptive_strike() -> void:
	if player == null or not player.is_pokemon():
		return
	var fastest: Actor = null
	for e in living_enemies():
		if not e.is_pokemon() or effective_speed(e) <= effective_speed(player):
			continue
		if fastest == null or effective_speed(e) > effective_speed(fastest):
			fastest = e
	if fastest == null:
		return
	_say("%s is faster — it strikes first!" % fastest.name)
	_preempting = true
	_take_enemy_turn(fastest)
	_preempting = false
	_check_deaths()
	if _check_end():
		return
	_pick_intent(fastest)


## The lowest HP a hit may leave this actor on. Only ever 1, and only for the
## player during the pre-emptive strike.
func _hp_floor(who: Actor) -> int:
	return 1 if _preempting and who != null and who.is_player else 0


## Whether anything in hand can put a dent in anything still standing. False
## only when every card is blocked by a type immunity — a hand of Normal moves
## facing a Ghost.
func _hand_can_damage() -> bool:
	var live := living_enemies()
	if live.is_empty():
		return true
	for c in hand:
		# A Spire card has no type to be stopped by.
		if not c.is_pokemon_card():
			return true
		for eff in c.effects():
			if String(eff.get("op", "")) != "poke_damage":
				continue
			var mtype := String(eff.get("mtype", "normal"))
			for e in live:
				if e.poke_types.is_empty():
					return true
				if PokeData.effectiveness(mtype, e.poke_types) > 0.0:
					return true
	return false


func _grant_struggle() -> void:
	var id := PokeMoves.card_id("struggle")
	if not CardLibrary.has(id):
		return
	for c in hand:
		if c.id == id:
			return
	_put_in_hand(Card.create(id))
	_say("%s has no move that will land — it resorts to Struggle." % player.name)


func _apply_combat_start_relics() -> void:
	if Run.has_relic("anchor"):
		player.block += 10
	if Run.has_relic("vajra"):
		player.add_signed_status("strength", 1)
	if Run.has_relic("oddly_smooth_stone"):
		player.add_signed_status("dexterity", 1)
	if Run.has_relic("blood_vial"):
		_heal(player, 2)
	if Run.has_relic("bronze_scales"):
		player.add_status("thorns", 3)
	if Run.has_relic("mark_of_pain"):
		for i in range(2):
			draw_pile.insert(rng.randi_range(0, draw_pile.size()), Card.create("wound"))
	if Run.has_relic("philosophers_stone"):
		for e in enemies:
			e.add_signed_status("strength", 1)
	if Run.has_relic("toolbox"):
		var pool := CardLibrary.colorless_pool()
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		hand.append(Card.create(pick))
	# Innate cards start in hand.
	var innates: Array = []
	for c in draw_pile:
		if c.has_flag("innate"):
			innates.append(c)
	for c in innates:
		draw_pile.erase(c)
		hand.append(c)


func energy_bonus_relics() -> int:
	var n := 0
	for id in ["philosophers_stone", "velvet_choker", "mark_of_pain"]:
		if Run.has_relic(id):
			n += 1
	return n


func extra_draw_relics() -> int:
	var n := 0
	if Run.has_relic("snecko_eye"):
		n += 2
	return n


func first_turn_extra_draw() -> int:
	var n := 0
	if Run.has_relic("bag_of_preparation"):
		n += 2
	if Run.has_relic("ring_of_the_snake"):
		n += 2
	return n


# ═══════════════════════════════ Turn structure ══════════════════════════════
func _start_player_turn() -> void:
	turn += 1
	phase = "player"
	cards_played_this_turn = 0
	attacks_played_this_turn = 0
	discards_this_turn = 0
	turn_attack_counter = 0
	_temp_thorns = 0

	if not player.has_status("barricade") and not player.has_status("blur"):
		player.block = 0
	player.set_status("blur", 0)

	if Run.has_relic("ice_cream"):
		energy += energy_per_turn + energy_bonus_relics()
	else:
		energy = energy_per_turn + energy_bonus_relics()
	energy += extra_energy_next_turn
	extra_energy_next_turn = 0
	if Run.has_relic("lantern") and turn == 1:
		energy += 1
	if Run.has_relic("happy_flower") and turn % 3 == 0:
		energy += 1
	if player.has_status("berserk"):
		energy += player.get_status("berserk")

	if block_next_turn > 0:
		_gain_block(player, block_next_turn, true)
		block_next_turn = 0
	if Run.has_relic("horn_cleat") and turn == 2:
		_gain_block(player, 14, true)

	if player.has_status("demon_form"):
		player.add_signed_status("strength", player.get_status("demon_form"))
		_say("Demon Form grants Strength.")
	if player.has_status("noxious_fumes"):
		var psn: int = player.get_status("noxious_fumes")
		for e in living_enemies():
			_apply_status(e, "poison", psn, player)
	if player.has_status("infinite_blades"):
		for i in range(player.get_status("infinite_blades")):
			_add_card_to("shiv", "hand", false)
	if Run.has_relic("mercury_hourglass"):
		for e in living_enemies():
			_damage(e, 3, player, "attack", null)
	if player.has_status("phantasmal"):
		pass  # consumed in damage calculation, cleared at end of turn

	_tick_poison(player)
	_tick_poke_ailments(player)
	if _check_end():
		return

	# Sleep, Freeze and the rest cost the player the turn outright; Disable just
	# taxes it. Energy is already set above, so this is the last word on it.
	var stopped := incapacitated_reason(player)
	if stopped != "":
		energy = 0
		_say(stopped)
	elif player.has_status("disable"):
		energy = max(0, energy - 1)
		_say("%s is disabled — 1 less Energy." % player.name)
	if _check_end():
		return

	var to_draw := base_draw + extra_draw_next_turn + extra_draw_relics()
	extra_draw_next_turn = 0
	if turn == 1:
		to_draw += first_turn_extra_draw()
	_draw(to_draw)

	# A Normal-only deck against a Ghost has no way to win, and unlike the games
	# there is nothing to switch to. Struggle is the series' own answer to
	# having no move that will land, so it is the answer here.
	if Run.is_pokemon_run() and not _hand_can_damage():
		_grant_struggle()

	if player.has_status("brutality"):
		var n: int = player.get_status("brutality")
		_lose_hp(player, n, "Brutality")
		_draw(n)
	if player.has_status("tools_of_the_trade"):
		_draw(1)
		_request_choice({"kind": "discard", "count": 1, "from": "hand",
				"prompt": "Tools of the Trade — discard a card", "optional": false})
	if player.has_status("mayhem"):
		_play_top_of_draw(false)

	_recompute_costs()
	player_turn_started.emit()
	changed.emit()
	_check_end()


func end_turn() -> void:
	if phase != "player" or finished:
		return
	if not pending_choice.is_empty():
		return
	phase = "enemy"

	# End-of-turn player effects
	if Run.has_relic("orichalcum") and player.block == 0:
		_gain_block(player, 6, true)
	if player.has_status("metallicize"):
		_gain_block(player, player.get_status("metallicize"), true)
	if player.has_status("plated_armor"):
		_gain_block(player, player.get_status("plated_armor"), true)
	if player.has_status("combust"):
		_lose_hp(player, 1, "Combust")
		for e in living_enemies():
			_damage(e, player.get_status("combust"), player, "attack", null)
	if player.has_status("regen"):
		var r: int = player.get_status("regen")
		_heal(player, r)
		player.set_status("regen", r - 1)
	if player.has_status("wraith_form"):
		player.add_signed_status("dexterity", -1)
	if player.has_status("strength_down"):
		player.add_signed_status("strength", -player.get_status("strength_down"))
		player.set_status("strength_down", 0)
	if player.has_status("phantasmal"):
		player.set_status("phantasmal", player.get_status("phantasmal") - 1)
	if Run.has_relic("art_of_war") and attacks_played_this_turn == 0:
		extra_energy_next_turn += 1

	# Cards still in hand
	var hand_copy: Array = hand.duplicate()
	for c in hand_copy:
		match c.id:
			"burn":
				var d: int = int(c.raw_params().get("dmg", 2))
				_lose_hp(player, d, "Burn")
			"regret":
				_lose_hp(player, hand.size(), "Regret")
			"doubt":
				_apply_status(player, "weak", 1, null)
	for c in hand_copy:
		if c.has_flag("ethereal"):
			_move_card(c, "hand", "exhaust")
			_on_exhaust(c)

	if not Run.has_relic("runic_pyramid"):
		var leftovers: Array = hand.duplicate()
		for c in leftovers:
			c.free_this_turn = false
			_move_card(c, "hand", "discard")
	else:
		for c in hand:
			c.free_this_turn = false

	_decay_statuses(player)
	if _check_end():
		return

	# Enemy phase. Pokemon act in Speed order. The Spire's own cast has no Speed
	# to sort by, and sort_custom is not stable, so leave their left-to-right
	# order exactly as it was.
	_enemy_order = living_enemies()
	if Run.is_pokemon_run():
		_enemy_order.sort_custom(func(a, b): return effective_speed(a) > effective_speed(b))
	_enemy_index = 0
	for e in _enemy_order:
		_tick_poison(e)
		_tick_poke_ailments(e)
	_check_deaths()
	changed.emit()
	if _check_end():
		return


## Advance the enemy phase by one action. Returns true while work remains.
func step_enemy() -> bool:
	if finished:
		return false
	if phase != "enemy":
		return false
	while _enemy_index < _enemy_order.size():
		var e: Actor = _enemy_order[_enemy_index]
		_enemy_index += 1
		if not e.alive or e.is_dead():
			continue
		_take_enemy_turn(e)
		_check_deaths()
		if _check_end():
			return false
		changed.emit()
		return true
	_finish_enemy_phase()
	return false


func _finish_enemy_phase() -> void:
	for e in living_enemies():
		if e.has_status("ritual"):
			e.add_signed_status("strength", e.get_status("ritual"))
		if e.has_status("metallicize"):
			_gain_block(e, e.get_status("metallicize"), true)
		if e.has_status("plated_armor"):
			_gain_block(e, e.get_status("plated_armor"), true)
		if e.has_status("regen"):
			var r: int = e.get_status("regen")
			_heal(e, r)
			e.set_status("regen", r - 1)
		if e.has_status("strength_up_end"):
			e.add_signed_status("strength", e.get_status("strength_up_end"))
			e.set_status("strength_up_end", 0)
		if e.has_status("fading"):
			var f: int = e.get_status("fading") - 1
			e.set_status("fading", f)
			if f <= 0:
				e.hp = 0
		_decay_statuses(e)
		e.turn_count += 1
		_pick_intent(e)
	_check_deaths()
	if _check_end():
		return
	_start_player_turn()


func _take_enemy_turn(e: Actor) -> void:
	# An enemy's Block expires at the start of its own turn.
	e.block = 0
	var stopped := incapacitated_reason(e)
	if stopped != "":
		_say(stopped)
		return
	var move_name: String = String(e.intent.get("name", ""))
	if move_name == "":
		_pick_intent(e)
		move_name = String(e.intent.get("name", ""))
	var moves := EnemyLibrary.moves_of(e.enemy_id)
	var move: Dictionary = moves.get(move_name, {"effects": []})
	_say("%s uses %s." % [e.name, move_name])
	e.move_history.append(move_name)
	move_cast.emit({"source": e, "target": player, "card": null,
			"name": move_name, "effects": move.get("effects", []),
			"card_target": ""})
	var ctx := {"owner": e, "target": player, "params": {}, "source_card": null}
	_push_effects(move.get("effects", []), ctx)
	_run_queue()


func _pick_intent(e: Actor) -> void:
	if not e.alive or e.is_dead():
		e.intent = {}
		return
	var name := EnemyLibrary.choose_move(e, self)
	var moves := EnemyLibrary.moves_of(e.enemy_id)
	var move: Dictionary = moves.get(name, {"intent": "unknown", "effects": []})
	e.intent = {"name": name, "kind": String(move.get("intent", "unknown")),
			"effects": move.get("effects", [])}


## Damage the enemy's telegraphed attack will do: [per_hit, hits]. [0,0] if none.
func intent_damage(e: Actor) -> Array:
	if e.intent.is_empty():
		return [0, 0]
	for eff in e.intent.get("effects", []):
		var op := String(eff.get("op", ""))
		if op == "poke_damage":
			var hits: int = max(1, int(eff.get("min_hits", 1)))
			return [calc_poke_damage(int(eff.get("power", 0)),
					String(eff.get("class", "physical")),
					String(eff.get("mtype", "normal")), e, player, 1.0), hits]
		if op == "damage":
			var base := _resolve_amount(eff, "amount", {"owner": e, "params": {}})
			var times := _resolve_amount(eff, "times", {"owner": e, "params": {}})
			if times <= 0:
				times = 1
			return [calc_attack_damage(base, e, player, null, 1), times]
		if op == "divider":
			return [calc_attack_damage(6, e, player, null, 1), 6]
		if op == "multi_stab":
			return [calc_attack_damage(6, e, player, null, 1), 3 + e.turn_count % 3]
		if op == "transient_attack":
			return [calc_attack_damage(30 + 10 * e.turn_count, e, player, null, 1), 1]
	return [0, 0]


# ═══════════════════════════════ Playing cards ═══════════════════════════════
func can_play(c: Card, target_index: int = -1) -> Dictionary:
	if phase != "player" or finished:
		return {"ok": false, "why": "Not your turn."}
	if not pending_choice.is_empty():
		return {"ok": false, "why": "Resolve the current choice first."}
	if c.is_unplayable():
		if c.type() == "curse" and Run.has_relic("blue_candle"):
			pass
		else:
			return {"ok": false, "why": "This card is unplayable."}
	var cst := c.cost(self)
	if c.is_x_cost():
		if energy <= 0:
			return {"ok": false, "why": "Not enough Energy."}
	elif cst > energy:
		return {"ok": false, "why": "Not enough Energy."}
	if Run.has_relic("velvet_choker") and cards_played_this_turn >= 6:
		return {"ok": false, "why": "Velvet Choker: 6 cards per turn."}
	if c.id == "clash":
		for other in hand:
			if other != c and other.type() != "attack":
				return {"ok": false, "why": "Clash needs an all-Attack hand."}
	if c.id == "grand_finale" and draw_pile.size() > 0:
		return {"ok": false, "why": "Grand Finale needs an empty draw pile."}
	if c.needs_target() and living_enemies().size() > 0:
		if target_index < 0:
			return {"ok": false, "why": "Choose a target."}
	return {"ok": true, "why": ""}


func play_card(c: Card, target_index: int = -1) -> bool:
	var check := can_play(c, target_index)
	if not check["ok"]:
		_say(String(check["why"]))
		return false

	var target: Actor = null
	var living := living_enemies()
	if living.is_empty():
		return false
	if c.needs_target():
		target = living[clampi(target_index, 0, living.size() - 1)]
	else:
		target = living[0]

	var spent := 0
	var x_value := 0
	if c.is_x_cost():
		x_value = energy
		spent = energy
	else:
		spent = c.cost(self)
	energy -= spent

	hand.erase(c)
	cards_played_this_turn += 1
	var is_attack := c.type() == "attack"
	if is_attack:
		attacks_played_this_turn += 1
		attack_counter += 1
		turn_attack_counter += 1
	_say("You play %s." % c.display_name())

	# Curses played through Blue Candle just hurt and vanish.
	if c.is_unplayable():
		_lose_hp(player, 1, "Blue Candle")
		_move_card(c, "none", "exhaust")
		_on_exhaust(c)
		_after_card_played(c, target)
		return true

	move_cast.emit({"source": player, "target": target, "card": c,
			"name": c.display_name(), "effects": c.effects(),
			"card_target": c.effective_target_kind()})

	var params := _params_for_play(c)
	var ctx := {"owner": player, "target": target, "params": params,
			"source_card": c, "x": x_value}

	var repeats := 1
	if is_attack and player.has_status("double_tap"):
		repeats = 2
		player.set_status("double_tap", player.get_status("double_tap") - 1)
	if is_attack and Run.has_relic("pen_nib") and attack_counter % 10 == 0:
		ctx["double_damage"] = true
		_say("Pen Nib doubles the blow!")

	for i in range(repeats):
		_push_effects(c.effects(), ctx.duplicate())

	# Where the card goes once it has resolved.
	var dest := "discard"
	if c.type() == "power":
		dest = "gone"
	if c.has_flag("exhaust"):
		dest = "exhaust"
	if c.type() == "skill" and player.has_status("corruption"):
		dest = "exhaust"
	ctx["dest"] = dest
	_queue.append({"op": "_finish_card", "card": c, "dest": dest, "ctx": ctx})
	_run_queue()
	_after_card_played(c, target)
	return true


func _params_for_play(c: Card) -> Dictionary:
	var p := c.raw_params()
	match c.id:
		"body_slam":
			p["dmg"] = player.block
		"perfected_strike":
			var strikes := 0
			for card in Run.deck:
				if String(CardLibrary.get_def(card.id)["name"]).to_lower().contains("strike"):
					strikes += 1
			p["dmg"] = int(p["dmg"]) + int(p["per"]) * strikes
		"rampage", "glass_knife":
			p["dmg"] = int(p["dmg"]) + c.bonus_damage
		"shiv":
			p["dmg"] = int(p["dmg"]) + player.get_status("accuracy")
	return p


func _after_card_played(c: Card, target: Actor) -> void:
	if player.has_status("after_image"):
		_gain_block(player, player.get_status("after_image"), true)
	if player.has_status("thousand_cuts"):
		for e in living_enemies():
			_damage(e, player.get_status("thousand_cuts"), player, "attack", null)
	for h in hand:
		if h.id == "pain":
			_lose_hp(player, 1, "Pain")
	if c.type() == "skill":
		for e in living_enemies():
			if e.has_status("enrage"):
				e.add_signed_status("strength", e.get_status("enrage"))
	if c.type() == "power":
		if Run.has_relic("bird_faced_urn"):
			_heal(player, 2)
		for e in living_enemies():
			if e.has_status("curiosity"):
				e.add_signed_status("strength", e.get_status("curiosity"))
	if c.type() == "attack" and turn_attack_counter % 3 == 0:
		if Run.has_relic("kunai"):
			player.add_signed_status("dexterity", 1)
		if Run.has_relic("shuriken"):
			player.add_signed_status("strength", 1)
		if Run.has_relic("ornamental_fan"):
			_gain_block(player, 4, true)
	_recompute_costs()
	changed.emit()
	_check_end()


func _recompute_costs() -> void:
	# Corruption / cost-reduction cards are handled through modify_card_cost, this
	# just refreshes any UI listening for cost changes.
	pass


func modify_card_cost(c: Card, base: int) -> int:
	if base < 0:
		return base
	var out := base
	if c.type() == "skill" and player != null and player.has_status("corruption"):
		return 0
	match c.id:
		"blood_for_blood":
			out = max(0, out - hp_loss_events)
		"eviscerate":
			out = max(0, out - discards_this_turn)
	return out


# ═══════════════════════════ Effect queue & resolution ═══════════════════════
func _push_effects(effects: Array, ctx: Dictionary) -> void:
	for eff in effects:
		_queue.append({"eff": eff, "ctx": ctx})


func _push_effects_front(effects: Array, ctx: Dictionary) -> void:
	var items: Array = []
	for eff in effects:
		items.append({"eff": eff, "ctx": ctx})
	items.reverse()
	for it in items:
		_queue.insert(0, it)


func _run_queue() -> void:
	if _resolving:
		return
	_resolving = true
	while not _queue.is_empty():
		if not pending_choice.is_empty():
			break
		if finished:
			_queue.clear()
			break
		var item: Dictionary = _queue.pop_front()
		if item.has("op") and String(item["op"]) == "_finish_card":
			_finish_card(item["card"], String(item["dest"]))
			continue
		_apply_effect(item["eff"], item["ctx"])
		_check_deaths()
	_resolving = false
	changed.emit()
	if _queue.is_empty() and pending_choice.is_empty():
		_check_end()


func _finish_card(c: Card, dest: String) -> void:
	c.free_this_turn = false
	match dest:
		"discard":
			discard_pile.append(c)
			card_flew.emit(c, "play", "discard")
		"exhaust":
			exhaust_pile.append(c)
			card_flew.emit(c, "play", "exhaust")
			_on_exhaust(c)
		_:
			card_flew.emit(c, "play", "gone")


func _resolve_amount(eff: Dictionary, key: String, ctx: Dictionary) -> int:
	var v = eff.get(key, 0)
	if typeof(v) == TYPE_STRING:
		var s: String = v
		if s == "X":
			return int(ctx.get("x", 0))
		if s.begins_with("@"):
			var owner = ctx.get("owner", null)
			if owner != null:
				return int((owner as Actor).rolled.get(s.substr(1), 0))
			return 0
		var params: Dictionary = ctx.get("params", {})
		return int(params.get(s, 0))
	return int(v)


func _targets_for(eff: Dictionary, ctx: Dictionary) -> Array:
	var owner: Actor = ctx.get("owner", player)
	var mode := String(eff.get("target", "default"))
	# Cards like Blind+ and Trip+ upgrade from single-target to every enemy.
	var src: Card = ctx.get("source_card", null)
	if src != null and mode in ["default", "enemy"] and src.effective_target_kind() == "all":
		mode = "all"
	if owner != null and not owner.is_player:
		# Enemy effects target the player unless they say otherwise.
		match mode:
			"self": return [owner]
			"all", "player", "default": return [player]
		return [player]
	match mode:
		"self": return [player]
		"all": return living_enemies()
		"player": return [player]
		"random":
			var l := living_enemies()
			if l.is_empty():
				return []
			return [l[rng.randi_range(0, l.size() - 1)]]
	var t = ctx.get("target", null)
	if t != null and (t as Actor).alive and not (t as Actor).is_dead():
		return [t]
	var live := living_enemies()
	return [live[0]] if live.size() > 0 else []


func _apply_effect(eff: Dictionary, ctx: Dictionary) -> void:
	var op := String(eff.get("op", ""))
	var owner: Actor = ctx.get("owner", player)
	var card: Card = ctx.get("source_card", null)

	match op:
		"damage":
			var base := _resolve_amount(eff, "amount", ctx)
			var times := _resolve_amount(eff, "times", ctx)
			if times <= 0:
				times = 1
			var str_mult := 1
			if eff.has("str_mult"):
				str_mult = max(1, _resolve_amount(eff, "str_mult", ctx))
			var no_scale := bool(eff.get("no_scale", false))
			for i in range(times):
				var targets := _targets_for(eff, ctx)
				for t in targets:
					var dmg := calc_attack_damage(base, owner, t, card, str_mult, no_scale)
					if bool(ctx.get("double_damage", false)):
						dmg *= 2
					var unblocked := _damage(t, dmg, owner, "attack", card)
					if bool(eff.get("drain", false)) and unblocked > 0:
						_heal(owner, unblocked)
				_check_deaths()
		"damage_random":
			var base2 := _resolve_amount(eff, "amount", ctx)
			var times2: int = max(1, _resolve_amount(eff, "times", ctx))
			for i in range(times2):
				var l := living_enemies()
				if l.is_empty():
					break
				var t: Actor = l[rng.randi_range(0, l.size() - 1)]
				var dmg2 := calc_attack_damage(base2, owner, t, card, 1)
				_damage(t, dmg2, owner, "attack", card)
				_check_deaths()
		"block":
			var amt := _resolve_amount(eff, "amount", ctx)
			var raw := bool(eff.get("no_scale", false))
			if owner.is_player:
				_gain_block(player, calc_block(amt, player) if not raw else amt, false)
			else:
				_gain_block(owner, amt, true)
		"block_next_turn":
			block_next_turn += calc_block(_resolve_amount(eff, "amount", ctx), player)
		"block_ally":
			var amt2 := _resolve_amount(eff, "amount", ctx)
			var candidates: Array = []
			for e in living_enemies():
				if e != owner:
					candidates.append(e)
			var who: Actor = owner
			if candidates.size() > 0:
				candidates.sort_custom(func(a, b): return a.hp_ratio() < b.hp_ratio())
				who = candidates[0]
			_gain_block(who, amt2, true)
		"block_all_allies":
			var amt3 := _resolve_amount(eff, "amount", ctx)
			for e in living_enemies():
				_gain_block(e, amt3, true)
		"heal_ally":
			var amt4 := _resolve_amount(eff, "amount", ctx)
			var hurt: Array = living_enemies()
			hurt.sort_custom(func(a, b): return a.hp_ratio() < b.hp_ratio())
			if hurt.size() > 0:
				_heal(hurt[0], amt4)
		"status_all_allies":
			var st := String(eff.get("id", "strength"))
			var stacks := _resolve_amount(eff, "stacks", ctx)
			for e in living_enemies():
				_apply_status(e, st, stacks, owner)
		"status":
			var sid := String(eff.get("id", "strength"))
			var stacks2 := _resolve_amount(eff, "stacks", ctx)
			if eff.has("scale"):
				var scale_v = eff["scale"]
				var mag := int(scale_v) if typeof(scale_v) != TYPE_STRING \
						else int(ctx.get("params", {}).get(String(scale_v), 0))
				stacks2 = stacks2 * mag if stacks2 < 0 else mag
				if int(eff.get("stacks", 1)) < 0:
					stacks2 = -abs(mag)
			for t in _targets_for(eff, ctx):
				_apply_status(t, sid, stacks2, owner)
		"draw":
			_draw(_resolve_amount(eff, "amount", ctx))
		"draw_next_turn":
			extra_draw_next_turn += _resolve_amount(eff, "amount", ctx)
		"energy":
			energy += _resolve_amount(eff, "amount", ctx)
		"energy_next_turn":
			extra_energy_next_turn += _resolve_amount(eff, "amount", ctx)
		"heal":
			_heal(player, _resolve_amount(eff, "amount", ctx))
		"heal_percent":
			_heal(player, int(round(player.max_hp * _resolve_amount(eff, "amount", ctx) / 100.0)))
		"max_hp":
			var n := _resolve_amount(eff, "amount", ctx)
			Run.add_max_hp(n)
			player.max_hp += n
			player.hp += n
		"lose_hp":
			_lose_hp(player, _resolve_amount(eff, "amount", ctx),
					card.display_name() if card != null else "")
		"gain_gold":
			Run.add_gold(_resolve_amount(eff, "amount", ctx))
		"add_card":
			var count: int = max(1, _resolve_amount(eff, "count", ctx))
			for i in range(count):
				_add_card_to(String(eff.get("id", "wound")), String(eff.get("dest", "discard")),
						bool(eff.get("upgraded", false)))
		"copy_self":
			if card != null:
				var copy := card.duplicate_card()
				match String(eff.get("dest", "discard")):
					"hand": _put_in_hand(copy)
					"draw": draw_pile.push_back(copy)
					_: discard_pile.append(copy)
		"poison_random":
			var stacks3 := _resolve_amount(eff, "stacks", ctx)
			var times3: int = max(1, _resolve_amount(eff, "times", ctx))
			for i in range(times3):
				var l2 := living_enemies()
				if l2.is_empty():
					break
				_apply_status(l2[rng.randi_range(0, l2.size() - 1)], "poison", stacks3, player)
		"discard":
			var n2: int = max(1, _resolve_amount(eff, "count", ctx))
			if bool(eff.get("random", false)):
				for i in range(n2):
					if hand.is_empty():
						break
					var c2: Card = hand[rng.randi_range(0, hand.size() - 1)]
					_discard_card(c2)
			elif hand.size() > 0:
				_request_choice({"kind": "discard", "count": min(n2, hand.size()),
						"from": "hand", "prompt": "Discard %d card(s)" % n2, "optional": false})
		"exhaust":
			var n3: int = max(1, _resolve_amount(eff, "count", ctx))
			# True Grit+ lets you pick the card instead of exhausting at random.
			var pick_it := card != null and card.upgraded \
					and (card.def().get("up", {}) as Dictionary).has("choose")
			if bool(eff.get("random", false)) and not pick_it:
				for i in range(n3):
					if hand.is_empty():
						break
					var c3: Card = hand[rng.randi_range(0, hand.size() - 1)]
					_move_card(c3, "hand", "exhaust")
					_on_exhaust(c3)
			elif hand.size() > 0:
				_request_choice({"kind": "exhaust", "count": min(n3, hand.size()),
						"from": "hand", "prompt": "Exhaust %d card(s)" % n3, "optional": false})
		"exhaust_all_nonattacks":
			var per := _resolve_amount(eff, "block_each", ctx)
			var doomed: Array = []
			for c4 in hand:
				if c4.type() != "attack":
					doomed.append(c4)
			for c4 in doomed:
				_move_card(c4, "hand", "exhaust")
				_on_exhaust(c4)
				if per > 0:
					_gain_block(player, calc_block(per, player), false)
		"choose_upgrade":
			var n4 := _resolve_amount(eff, "count", ctx)
			if card != null and card.upgraded and card.id == "armaments":
				for c5 in hand:
					if c5.can_upgrade():
						c5.upgrade()
				_say("All cards in hand upgraded.")
			elif hand.size() > 0:
				var any := false
				for c5 in hand:
					if c5.can_upgrade():
						any = true
				if any:
					_request_choice({"kind": "upgrade", "count": max(1, n4), "from": "hand",
							"prompt": "Upgrade a card", "optional": false,
							"filter": "upgradable"})
		"upgrade_all_in_combat":
			for c6 in _all_cards():
				if c6.can_upgrade():
					c6.upgrade()
			_say("Your cards are transcendent!")
		"discard_to_draw":
			if discard_pile.size() > 0:
				_request_choice({"kind": "discard_to_draw",
						"count": max(1, _resolve_amount(eff, "count", ctx)),
						"from": "discard", "prompt": "Put a card on top of your draw pile",
						"optional": false})
		"hand_to_draw":
			if hand.size() > 0:
				_request_choice({"kind": "hand_to_draw",
						"count": max(1, _resolve_amount(eff, "count", ctx)),
						"from": "hand", "prompt": "Put a card on top of your draw pile",
						"optional": false})
		"exhaust_pile_to_hand":
			if exhaust_pile.size() > 0:
				_request_choice({"kind": "exhaust_to_hand",
						"count": max(1, _resolve_amount(eff, "count", ctx)),
						"from": "exhaust", "prompt": "Return a card to your hand",
						"optional": false})
		"duplicate_in_hand":
			var valid := false
			for c7 in hand:
				if c7.type() == "attack" or c7.type() == "power":
					valid = true
			if valid:
				_request_choice({"kind": "duplicate", "count": 1, "from": "hand",
						"prompt": "Duplicate an Attack or Power",
						"optional": false, "filter": "attack_power",
						"copies": max(1, _resolve_amount(eff, "count", ctx))})
		"double_block":
			var b := player.block
			_gain_block(player, b, true)
		"play_top_card":
			_play_top_of_draw(bool(eff.get("exhaust", true)))
		"random_card_to_hand":
			var want := String(eff.get("type", "attack"))
			var pool: Array = []
			for id in CardLibrary.pool_for(Run.card_color()):
				if String(CardLibrary.get_def(id)["type"]) == want:
					pool.append(id)
			if pool.is_empty():
				pool = CardLibrary.pool_for(Run.card_color())
			var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
			var nc := Card.create(pick)
			if bool(eff.get("free", false)):
				nc.free_this_turn = true
			_put_in_hand(nc)
		"clear_thorns":
			owner.set_status("thorns", 0)
			owner.set_status("defensive_mode", 0)
		"clear_block_self":
			owner.block = 0
		"flee":
			_say("%s escapes!" % owner.name)
			owner.alive = false
			owner.hp = 0
			enemy_died.emit(owner)
		"split":
			_split(owner, eff.get("into", []))
		"summon":
			_summon(owner, eff.get("options", []), int(eff.get("count", 1)))
		"divider":
			var per_hit := 6
			for i in range(6):
				var d := calc_attack_damage(per_hit, owner, player, null, 1)
				_damage(player, d, owner, "attack", null)
		"multi_stab":
			var hits := 3 + owner.turn_count % 3
			for i in range(hits):
				_damage(player, calc_attack_damage(6, owner, player, null, 1), owner, "attack", null)
		"transient_attack":
			var d2 := calc_attack_damage(30 + 10 * owner.turn_count, owner, player, null, 1)
			_damage(player, d2, owner, "attack", null)
		"haste":
			owner.add_signed_status("strength", 2)
			_gain_block(owner, 20, true)
		"rebirth":
			owner.set_status("unawakened", 0)
			owner.hp = owner.max_hp
			_say("%s rises again!" % owner.name)
		"special":
			_special(String(eff.get("id", "")), ctx)

		# ────────────────────────────── Pokemon ──────────────────────────────
		"poke_damage":
			_op_poke_damage(eff, ctx, owner, card)
		"poke_status":
			var psid := String(eff.get("id", "burn"))
			var pstacks: int = max(1, _resolve_amount(eff, "stacks", ctx))
			for t in _targets_for(eff, ctx):
				if not _roll_chance(eff, ctx, owner, t):
					continue
				_apply_status(t, psid, pstacks, owner)
		"poke_stage":
			var stat := String(eff.get("stat", "atk"))
			var change := int(eff.get("change", 0))
			for t in _targets_for(eff, ctx):
				if not _roll_chance(eff, ctx, owner, t):
					continue
				_apply_stage(t, stat, change, owner)
		"poke_heal":
			var pct := _resolve_amount(eff, "percent", ctx)
			for t in _targets_for(eff, ctx):
				_heal(t, int(round(t.max_hp * pct / 100.0)))
		"poke_recoil_self":
			var pct2 := _resolve_amount(eff, "percent", ctx)
			_lose_hp(owner, int(round(owner.max_hp * pct2 / 100.0)),
					card.display_name() if card != null else "Recoil")

		_:
			push_warning("Unknown effect op: %s" % op)


# ═══════════════════════════════ Pokemon rules ═══════════════════════════════
## Damage for one Pokemon move. The main-series formula does the heavy lifting
## (power against the attacker's offensive stat and the defender's matching
## defensive stat); type effectiveness, STAB, stat stages, burn and criticals
## are layered on top, and the result is then run through the Spire's own
## modifiers so Strength, Weak and Vulnerable still mean something.
func calc_poke_damage(power: int, damage_class: String, move_type: String,
		source: Actor, target: Actor, extra: float = 1.0) -> int:
	if power <= 0:
		return 0
	var atk_key := "spa" if damage_class == "special" else "atk"
	var def_key := "spd" if damage_class == "special" else "df"

	var attack := float(PokeBalance.NEUTRAL_DEFENSE)
	var user_types: Array = []
	if source != null:
		attack = float(source.base_stat(atk_key, 60)) * source.stat_scale
		attack *= PokeBalance.stage_multiplier(source.stage(atk_key))
		user_types = source.poke_types
		# A burned attacker hits half as hard with physical moves.
		if damage_class == "physical" and source.has_status("burn"):
			extra *= 0.5

	var defense := float(PokeBalance.NEUTRAL_DEFENSE)
	var target_types: Array = []
	if target != null:
		defense = float(target.base_stat(def_key, 60)) * target.stat_scale
		defense *= PokeBalance.stage_multiplier(target.stage(def_key))
		target_types = target.poke_types

	var type_mult := 1.0
	if not target_types.is_empty():
		type_mult = PokeData.effectiveness(move_type, target_types)
		# Foresight and friends strip an immunity but not a resistance.
		if type_mult <= 0.0 and target.has_status("identified"):
			type_mult = 1.0
	var stab := PokeData.stab_bonus(move_type, user_types)

	var dmg := PokeBalance.move_damage(power, int(attack), int(defense),
			type_mult, stab, extra)
	if dmg <= 0:
		return 0
	# Hand off to the Spire layer for Strength, Weak, Vulnerable and Flight.
	return calc_attack_damage(dmg, source, target, null, 1)


func _op_poke_damage(eff: Dictionary, ctx: Dictionary, owner: Actor, card: Card) -> void:
	var power := _resolve_amount(eff, "power", ctx)
	var damage_class := String(eff.get("class", "physical"))
	var move_type := String(eff.get("mtype", "normal"))
	var accuracy := int(eff.get("acc", 0))

	var hits := 1
	if int(eff.get("max_hits", 0)) > 1:
		hits = rng.randi_range(int(eff.get("min_hits", 2)), int(eff.get("max_hits", 2)))

	var total_dealt := 0
	for i in range(hits):
		var targets := _targets_for(eff, ctx)
		if targets.is_empty():
			break
		for t in targets:
			if not _accuracy_check(owner, t, accuracy, card):
				continue
			var extra := 1.0
			if _crit_roll(int(eff.get("crit", 0))):
				extra *= 1.5
				_say("A critical hit!")
			# Seismic Toss and friends set the number outright; Low Kick and
			# friends compute a power first and then use the normal formula.
			var dmg := 0
			if eff.has("fixed"):
				dmg = _fixed_damage(String(eff["fixed"]), move_type, owner, t)
			else:
				var pw := power
				if eff.has("formula"):
					pw = _variable_power(String(eff["formula"]), owner, t)
				dmg = calc_poke_damage(pw, damage_class, move_type, owner, t, extra)
			if dmg <= 0:
				_say("It has no effect on %s." % t.name)
				continue
			# Counter and Mirror Coat need to know what hit them last.
			t.last_hit_class = damage_class
			if bool(ctx.get("double_damage", false)):
				dmg *= 2
			if i == 0:
				_announce_matchup(move_type, t)
			var unblocked := _damage(t, dmg, owner, "attack", card)
			t.last_hit_taken = unblocked
			total_dealt += unblocked
			if String(eff.get("fixed", "")) == "user_hp":
				_lose_hp(owner, owner.hp, "Final Gambit")
		_check_deaths()

	var drain := int(eff.get("drain", 0))
	if drain > 0 and total_dealt > 0:
		_heal(owner, max(1, int(round(total_dealt * drain / 100.0))))
	var recoil := int(eff.get("recoil", 0))
	if recoil > 0 and total_dealt > 0:
		_lose_hp(owner, max(1, int(round(total_dealt * recoil / 100.0))), "Recoil")


## Moves that name their own damage. Type immunity still applies, so Night Shade
## cannot touch a Normal type.
func _fixed_damage(kind: String, move_type: String, source: Actor, target: Actor) -> int:
	if target == null:
		return 0
	if not target.poke_types.is_empty() \
			and PokeData.effectiveness(move_type, target.poke_types) <= 0.0 \
			and not target.has_status("identified"):
		return 0
	match kind:
		"flat_40":
			return 40
		"flat_20":
			return 20
		"user_level":
			return PokeBalance.LEVEL
		"psywave":
			return max(1, int(round(PokeBalance.LEVEL * rng.randf_range(0.5, 1.5))))
		"half_target_hp":
			return max(1, int(floor(target.hp / 2.0)))
		"match_user_hp":
			return max(0, target.hp - source.hp) if source != null else 0
		"user_hp":
			return source.hp if source != null else 0
		"ohko":
			# The accuracy roll has already happened, so landing it is the KO.
			_say("It's a one-hit KO!")
			return target.hp + target.block
	return 0


## Moves whose power depends on the state of the fight.
func _variable_power(kind: String, source: Actor, target: Actor) -> int:
	var src_mon := PokeData.mon(source.poke_name) if source != null else {}
	var tgt_mon := PokeData.mon(target.poke_name) if target != null else {}
	match kind:
		"target_weight":
			# Weight is in hectograms; the games' brackets top out at 120 power.
			var w := float(tgt_mon.get("weight", 500))
			if w >= 2000.0: return 120
			if w >= 1000.0: return 100
			if w >= 500.0: return 80
			if w >= 250.0: return 60
			if w >= 100.0: return 40
			return 20
		"weight_ratio":
			var mine := maxf(1.0, float(src_mon.get("weight", 500)))
			var theirs := maxf(1.0, float(tgt_mon.get("weight", 500)))
			var ratio := mine / theirs
			if ratio >= 5.0: return 120
			if ratio >= 4.0: return 100
			if ratio >= 3.0: return 80
			if ratio >= 2.0: return 60
			return 40
		"speed_ratio":
			var fast := float(maxi(1, effective_speed(source)))
			var slow := float(maxi(1, effective_speed(target)))
			var r := fast / slow
			if r >= 4.0: return 150
			if r >= 3.0: return 120
			if r >= 2.0: return 80
			if r >= 1.0: return 60
			return 40
		"inverse_speed":
			var mine2 := float(maxi(1, effective_speed(source)))
			var theirs2 := float(maxi(1, effective_speed(target)))
			return clampi(int(25.0 * theirs2 / mine2), 1, 150)
		"low_hp":
			var left := source.hp_ratio() if source != null else 1.0
			if left <= 0.05: return 200
			if left <= 0.10: return 150
			if left <= 0.20: return 100
			if left <= 0.35: return 80
			if left <= 0.68: return 40
			return 20
		"target_hp":
			return clampi(int(round(120.0 * target.hp_ratio())), 1, 120) if target != null else 1
		"friendship_high":
			return 102
		"friendship_low":
			return 52
		"target_stages":
			var raised := 0
			if target != null:
				for stat in ["atk", "df", "spa", "spd", "spe"]:
					raised += max(0, target.stage(stat))
			return clampi(60 + 20 * raised, 60, 200)
		"random_quake":
			return [10, 30, 50, 70, 90, 110, 150][rng.randi_range(0, 6)]
		"counter_physical", "counter_special", "counter_any":
			if source == null or source.last_hit_taken <= 0:
				return 0
			var wanted := "physical" if kind == "counter_physical" else "special"
			if kind != "counter_any" and source.last_hit_class != wanted:
				return 0
			# Returning damage directly would bypass the formula, so convert the
			# hit back into a rough power figure.
			var factor := 1.5 if kind == "counter_any" else 2.0
			return clampi(int(source.last_hit_taken * factor * 2), 1, 250)
	return 0


func _announce_matchup(move_type: String, target: Actor) -> void:
	if target == null or target.poke_types.is_empty():
		return
	var note := PokeData.effectiveness_text(
			PokeData.effectiveness(move_type, target.poke_types))
	if note != "":
		_say(note)


## Accuracy 0 means the move cannot miss (Swift, Aerial Ace). Everything else
## rolls, including 100-accuracy moves — those can still be dodged by a target
## that has raised its Evasion.
func _accuracy_check(source: Actor, target: Actor, accuracy: int, card: Card) -> bool:
	if accuracy <= 0:
		return true
	var chance := float(accuracy)
	if source != null:
		chance *= PokeBalance.stage_multiplier(source.stage("accuracy"))
	if target != null:
		chance /= PokeBalance.stage_multiplier(target.stage("evasion"))
	if rng.randf() * 100.0 < chance:
		return true
	var what := card.display_name() if card != null else "The attack"
	_say("%s missed %s!" % [what, target.name if target != null else "its target"])
	floating.emit(target, "Miss", "blocked")
	return false


## A move's stated crit rate is a stage, not a percentage: 0 is 1/24, 1 is 1/8.
func _crit_roll(crit_stage: int) -> bool:
	var chance := 4.17
	if crit_stage >= 3:
		chance = 100.0
	elif crit_stage == 2:
		chance = 50.0
	elif crit_stage == 1:
		chance = 12.5
	return rng.randf() * 100.0 < chance


## Chance riders ("30% chance to burn") roll here. Absent means always.
func _roll_chance(eff: Dictionary, ctx: Dictionary, source: Actor, target: Actor) -> bool:
	if not eff.has("chance"):
		return true
	var chance := _resolve_amount(eff, "chance", ctx)
	if chance >= 100:
		return true
	return rng.randf() * 100.0 < float(chance)


func _apply_stage(target: Actor, stat: String, change: int, source: Actor) -> void:
	if target == null or target.is_dead() or change == 0:
		return
	# Lowering a stat is a debuff, so Artifact can shrug it off.
	if change < 0 and target.has_status("artifact"):
		target.set_status("artifact", target.get_status("artifact") - 1)
		_say("%s's Artifact absorbs the drop." % target.name)
		return
	var before := target.stage(stat)
	var after := target.add_stage(stat, change)
	if after == before:
		_say("%s's %s won't go any %s." % [target.name, PokeMoves._stat_label(stat),
				"higher" if change > 0 else "lower"])
		return
	floating.emit(target, "%s %+d" % [PokeMoves._stat_label(stat), change], "status")
	changed.emit()


## Speed after paralysis and Speed stages, which sets turn order.
func effective_speed(who: Actor) -> int:
	if who == null:
		return 0
	var spe := float(who.base_stat("spe", 60))
	spe *= PokeBalance.stage_multiplier(who.stage("spe"))
	if who.has_status("paralysis"):
		spe *= 0.25
	return int(spe)


## Why this actor cannot act this turn, or "" if it can. Sleep and Freeze cost
## the whole turn; Flinch costs the one action; Confusion and Infatuation are
## rolled each time.
func incapacitated_reason(who: Actor) -> String:
	if who == null:
		return ""
	if who.has_status("sleep"):
		return "%s is fast asleep." % who.name
	if who.has_status("freeze"):
		# 20% thaw check each turn, as in the games.
		if rng.randf() < 0.2:
			who.set_status("freeze", 0)
			_say("%s thawed out!" % who.name)
			return ""
		return "%s is frozen solid." % who.name
	if who.has_status("flinch"):
		who.set_status("flinch", 0)
		return "%s flinched." % who.name
	if who.has_status("infatuation") and rng.randf() < 0.5:
		return "%s is immobilised by love." % who.name
	if who.has_status("confusion") and rng.randf() < 0.33:
		var self_hit := PokeBalance.base_damage(40, who.base_stat("atk", 60),
				who.base_stat("df", 60))
		_damage(who, self_hit, who, "hp_loss", null)
		return "%s hurt itself in its confusion." % who.name
	return ""


## Ailments that chip away each turn. Called alongside _tick_poison.
func _tick_poke_ailments(who: Actor) -> void:
	if who == null or who.is_dead() or not who.is_pokemon():
		return
	if who.has_status("burn"):
		var burn_dmg: int = max(1, int(round(who.max_hp * 0.0625)))
		_lose_hp(who, burn_dmg, "Burn")
		who.set_status("burn", who.get_status("burn") - 1)
	if who.has_status("trapped"):
		var trap_dmg: int = max(1, int(round(who.max_hp * 0.125)))
		_lose_hp(who, trap_dmg, "Trapped")
		who.set_status("trapped", who.get_status("trapped") - 1)
	if who.has_status("nightmare"):
		if who.has_status("sleep"):
			_lose_hp(who, max(1, int(round(who.max_hp * 0.25))), "Nightmare")
		who.set_status("nightmare", who.get_status("nightmare") - 1)
	if who.has_status("leech_seed"):
		var drained: int = max(1, int(round(who.max_hp * 0.125)))
		_lose_hp(who, drained, "Leech Seed")
		# The seed feeds whoever is on the other side of the fight.
		var beneficiary: Actor = player if not who.is_player else null
		if who.is_player:
			var live := living_enemies()
			beneficiary = live[0] if live.size() > 0 else null
		if beneficiary != null:
			_heal(beneficiary, drained)
		who.set_status("leech_seed", who.get_status("leech_seed") - 1)
	if who.has_status("drowsy"):
		var left: int = who.get_status("drowsy") - 1
		who.set_status("drowsy", left)
		if left <= 0:
			_apply_status(who, "sleep", 2, null)
			_say("%s fell asleep!" % who.name)
	for id in ["sleep", "confusion", "paralysis", "infatuation", "heal_block",
			"embargo", "disable", "identified"]:
		if who.has_status(id):
			who.set_status(id, who.get_status(id) - 1)


# ══════════════════════════════ Unique card logic ════════════════════════════
func _special(id: String, ctx: Dictionary) -> void:
	var card: Card = ctx.get("source_card", null)
	var target: Actor = ctx.get("target", null)
	var params: Dictionary = ctx.get("params", {})
	match id:
		"dropkick":
			if target != null and target.has_status("vulnerable") and not target.is_dead():
				energy += 1
				_draw(1)
		"rampage":
			if card != null:
				card.bonus_damage += int(params.get("grow", 5))
		"glass_knife":
			if card != null:
				card.bonus_damage -= 2
		"spot_weakness":
			if target != null and String(target.intent.get("kind", "")).begins_with("attack"):
				player.add_signed_status("strength", int(params.get("str", 3)))
				_say("You spot a weakness!")
			else:
				_say("The enemy is not attacking.")
		"limit_break":
			player.add_signed_status("strength", player.get_status("strength"))
		"feed":
			if target == null:
				return
			var dmg := calc_attack_damage(int(params.get("dmg", 10)), player, target, card, 1)
			var was_minion := target.is_minion
			_damage(target, dmg, player, "attack", card)
			if target.is_dead() and not was_minion and not target.is_boss:
				var gain := int(params.get("hp", 3))
				Run.add_max_hp(gain)
				player.max_hp += gain
				player.hp += gain
				_say("You feed and grow stronger! +%d Max HP." % gain)
		"hand_of_greed":
			if target == null:
				return
			var dmg2 := calc_attack_damage(int(params.get("dmg", 20)), player, target, card, 1)
			_damage(target, dmg2, player, "attack", card)
			if target.is_dead() and not target.is_minion:
				Run.add_gold(int(params.get("gold", 20)))
				_say("+%d Gold." % int(params.get("gold", 20)))
		"fiend_fire":
			var count := hand.size()
			var doomed: Array = hand.duplicate()
			for c in doomed:
				_move_card(c, "hand", "exhaust")
				_on_exhaust(c)
			for i in range(count):
				if target == null or target.is_dead():
					var l := living_enemies()
					if l.is_empty():
						break
					target = l[0]
				_damage(target, calc_attack_damage(int(params.get("dmg", 7)), player, target,
						card, 1), player, "attack", card)
		"reaper":
			var healed := 0
			for e in living_enemies():
				var d := calc_attack_damage(int(params.get("dmg", 4)), player, e, card, 1)
				healed += _damage(e, d, player, "attack", card)
			if healed > 0:
				_heal(player, healed)
				_say("You reap %d HP." % healed)
		"bane":
			if target != null and target.has_status("poison") and not target.is_dead():
				_damage(target, calc_attack_damage(int(params.get("dmg", 7)), player, target,
						card, 1), player, "attack", card)
		"catalyst":
			if target != null:
				var p := target.get_status("poison")
				target.set_status("poison", p * int(params.get("mult", 2)))
				_say("Poison surges to %d." % target.get_status("poison"))
		"sneaky_strike":
			if discards_this_turn > 0:
				energy += 2
		"heel_hook":
			if target != null and target.has_status("weak"):
				energy += 1
				_draw(1)
		"finisher":
			var n: int = max(0, attacks_played_this_turn - 1)
			for i in range(n):
				if target == null or target.is_dead():
					break
				_damage(target, calc_attack_damage(int(params.get("dmg", 6)), player, target,
						card, 1), player, "attack", card)
		"flechettes":
			var skills := 0
			for c in hand:
				if c.type() == "skill":
					skills += 1
			for i in range(skills):
				if target == null or target.is_dead():
					break
				_damage(target, calc_attack_damage(int(params.get("dmg", 4)), player, target,
						card, 1), player, "attack", card)
		"escape_plan":
			var drawn := _draw(1)
			if drawn.size() > 0 and (drawn[0] as Card).type() == "skill":
				_gain_block(player, calc_block(int(params.get("blk", 3)), player), false)
		"calculated_gamble":
			var n2 := hand.size()
			var doomed2: Array = hand.duplicate()
			for c in doomed2:
				_discard_card(c)
			_draw(n2)
		"unload":
			var doomed3: Array = []
			for c in hand:
				if c.type() != "attack":
					doomed3.append(c)
			for c in doomed3:
				_discard_card(c)
		"malaise":
			var x := int(ctx.get("x", 0))
			if card != null and card.upgraded:
				x += 1
			if target != null:
				target.add_signed_status("strength", -x)
				_apply_status(target, "weak", x, player)
		_:
			push_warning("Unknown special: %s" % id)


func _play_top_of_draw(exhaust_it: bool) -> void:
	if draw_pile.is_empty():
		_reshuffle()
	if draw_pile.is_empty():
		return
	var c: Card = draw_pile.pop_back()
	if c.is_unplayable():
		exhaust_pile.append(c)
		_on_exhaust(c)
		return
	var living := living_enemies()
	if living.is_empty():
		return
	var target: Actor = living[rng.randi_range(0, living.size() - 1)]
	_say("Havoc plays %s!" % c.display_name())
	var ctx := {"owner": player, "target": target, "params": _params_for_play(c),
			"source_card": c, "x": energy}
	_push_effects_front(c.effects(), ctx)
	if exhaust_it or c.has_flag("exhaust"):
		_queue.append({"op": "_finish_card", "card": c, "dest": "exhaust", "ctx": ctx})
	elif c.type() == "power":
		_queue.append({"op": "_finish_card", "card": c, "dest": "gone", "ctx": ctx})
	else:
		_queue.append({"op": "_finish_card", "card": c, "dest": "discard", "ctx": ctx})


func _split(who: Actor, into: Array) -> void:
	who.hp = 0
	who.alive = false
	enemy_died.emit(who)
	var slot := enemies.size()
	for id in into:
		var e := EnemyLibrary.spawn(String(id), rng, Run.ascension)
		e.hp = max(1, int(round(who.max_hp / 2.0)))
		e.max_hp = e.hp
		e.slot = slot
		slot += 1
		enemies.append(e)
		_pick_intent(e)
	_say("%s splits apart!" % who.name)


func _summon(who: Actor, options: Array, count: int) -> void:
	if options.is_empty():
		return
	var slot := enemies.size()
	for i in range(count):
		if living_enemies().size() >= 5:
			break
		var id := String(options[rng.randi_range(0, options.size() - 1)])
		var e := EnemyLibrary.spawn(id, rng, Run.ascension)
		e.is_minion = true
		e.leader = who
		e.slot = slot
		slot += 1
		enemies.append(e)
		_pick_intent(e)
	_say("%s calls for reinforcements!" % who.name)


# ═════════════════════════════════ Choices ═══════════════════════════════════
func _request_choice(req: Dictionary) -> void:
	pending_choice = req
	choice_requested.emit(req)
	changed.emit()


func choice_options() -> Array:
	if pending_choice.is_empty():
		return []
	var from := String(pending_choice.get("from", "hand"))
	var src: Array = hand
	match from:
		"discard": src = discard_pile
		"exhaust": src = exhaust_pile
		"draw": src = draw_pile
	var filter := String(pending_choice.get("filter", ""))
	var out: Array = []
	for c in src:
		match filter:
			"upgradable":
				if c.can_upgrade():
					out.append(c)
			"attack_power":
				if c.type() == "attack" or c.type() == "power":
					out.append(c)
			_:
				out.append(c)
	return out


func resolve_choice(selection: Array) -> void:
	if pending_choice.is_empty():
		return
	var req := pending_choice
	pending_choice = {}
	var kind := String(req.get("kind", ""))
	for c in selection:
		match kind:
			"discard":
				_discard_card(c)
			"exhaust":
				_move_card(c, "hand", "exhaust")
				_on_exhaust(c)
			"upgrade":
				c.upgrade()
				_say("%s upgraded." % c.display_name())
			"discard_to_draw":
				discard_pile.erase(c)
				draw_pile.push_back(c)
				_say("%s goes on top of your draw pile." % c.display_name())
			"hand_to_draw":
				hand.erase(c)
				draw_pile.push_back(c)
			"exhaust_to_hand":
				exhaust_pile.erase(c)
				_put_in_hand(c)
			"duplicate":
				var copies := int(req.get("copies", 1))
				for i in range(copies):
					var nc: Card = (c as Card).duplicate_card()
					nc.free_this_turn = c.free_this_turn
					_put_in_hand(nc)
	changed.emit()
	_run_queue()


func cancel_choice() -> void:
	if pending_choice.is_empty():
		return
	if bool(pending_choice.get("optional", false)):
		pending_choice = {}
		_run_queue()
	else:
		# The choice is compulsory, so it cannot be waived. Ask the UI to put the
		# prompt back up: leaving it pending with nothing on screen would block
		# every card and End Turn for the rest of the combat.
		choice_requested.emit(pending_choice)


## Re-raise the outstanding prompt. Lets the UI recover if it ever loses track of
## one (an old save, a screen change mid-prompt) instead of dead-ending.
func reassert_choice() -> bool:
	if pending_choice.is_empty():
		return false
	choice_requested.emit(pending_choice)
	return true


# ═════════════════════════════════ Piles ═════════════════════════════════════
func _shuffle(pile: Array) -> void:
	for i in range(pile.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pile[i]
		pile[i] = pile[j]
		pile[j] = tmp


func _reshuffle() -> void:
	if discard_pile.is_empty():
		return
	for c in discard_pile:
		draw_pile.append(c)
	discard_pile.clear()
	_shuffle(draw_pile)
	shuffles += 1
	if Run.has_relic("sundial") and shuffles % 3 == 0:
		energy += 2
		_say("The Sundial turns: +2 Energy.")
	_say("You shuffle your discard pile back in.")


func _draw(count: int) -> Array:
	var drawn: Array = []
	for i in range(count):
		if player.has_status("no_draw"):
			_say("You cannot draw any more cards this turn.")
			break
		if draw_pile.is_empty():
			_reshuffle()
		if draw_pile.is_empty():
			break
		if hand.size() >= HAND_LIMIT:
			_say("Your hand is full.")
			break
		var c: Card = draw_pile.pop_back()
		hand.append(c)
		drawn.append(c)
		card_flew.emit(c, "draw", "hand")
		_on_draw(c)
	changed.emit()
	return drawn


func _on_draw(c: Card) -> void:
	if c.type() == "status" or c.type() == "curse":
		if player.has_status("fire_breathing"):
			var d: int = player.get_status("fire_breathing")
			for e in living_enemies():
				_damage(e, d, player, "attack", null)
		if c.type() == "status" and player.has_status("evolve"):
			_draw(player.get_status("evolve"))
	if c.id == "void":
		energy = max(0, energy - 1)
		_say("The Void drains 1 Energy.")
	if c.id == "endless_agony":
		var copy := c.duplicate_card()
		_put_in_hand(copy)


func _put_in_hand(c: Card) -> void:
	if hand.size() >= HAND_LIMIT:
		discard_pile.append(c)
		_say("Hand full — %s goes to the discard pile." % c.display_name())
		return
	hand.append(c)
	card_flew.emit(c, "create", "hand")


func _add_card_to(id: String, dest: String, upgraded: bool) -> void:
	var c := Card.create(id, upgraded)
	match dest:
		"hand": _put_in_hand(c)
		"draw": draw_pile.push_back(c)
		"draw_random": draw_pile.insert(rng.randi_range(0, draw_pile.size()), c)
		_: discard_pile.append(c)
	_say("%s added to your %s." % [c.display_name(), dest.replace("_", " ")])


func _discard_card(c: Card) -> void:
	if not hand.has(c):
		return
	hand.erase(c)
	c.free_this_turn = false
	discard_pile.append(c)
	discards_this_turn += 1
	card_flew.emit(c, "hand", "discard")
	# Cards that pay off when they hit the discard pile.
	if c.id == "reflex":
		_draw(int(c.raw_params().get("cards", 2)))
	if c.id == "tactician":
		energy += int(c.raw_params().get("nrg", 1))


func _move_card(c: Card, from_pile: String, to_pile: String) -> void:
	match from_pile:
		"hand": hand.erase(c)
		"draw": draw_pile.erase(c)
		"discard": discard_pile.erase(c)
	match to_pile:
		"hand": hand.append(c)
		"draw": draw_pile.append(c)
		"discard": discard_pile.append(c)
		"exhaust": exhaust_pile.append(c)
	card_flew.emit(c, from_pile, to_pile)


func _on_exhaust(c: Card) -> void:
	if c.id == "sentinel":
		var n := int(c.raw_params().get("nrg", 2))
		energy += n
		_say("Sentinel returns %d Energy." % n)
	if player.has_status("feel_no_pain"):
		_gain_block(player, player.get_status("feel_no_pain"), true)
	if player.has_status("dark_embrace"):
		_draw(player.get_status("dark_embrace"))


func _all_cards() -> Array:
	var out: Array = []
	out.append_array(hand)
	out.append_array(draw_pile)
	out.append_array(discard_pile)
	return out


# ════════════════════════════ Numbers & damage ═══════════════════════════════
func calc_attack_damage(base: int, source: Actor, target: Actor, card: Card,
		str_mult: int = 1, no_scale: bool = false) -> int:
	var dmg := float(base)
	if source != null and not no_scale:
		dmg += float(source.get_status("strength") * str_mult)
	if source != null and source.has_status("weak") and not no_scale:
		dmg = floor(dmg * 0.75)
	if source != null and source.is_player and player.has_status("phantasmal"):
		dmg = dmg * 2.0
	if target != null and target.has_status("vulnerable"):
		dmg = floor(dmg * 1.5)
	if target != null and target.has_status("flight"):
		dmg = floor(dmg * 0.5)
	if target != null and target.has_status("slow_start"):
		dmg = floor(dmg * (1.0 + 0.1 * cards_played_this_turn))
	return max(0, int(dmg))


func calc_block(base: int, who: Actor) -> int:
	var b := float(base)
	if who != null:
		b += float(who.get_status("dexterity"))
		if who.has_status("frail"):
			b = floor(b * 0.75)
	return max(0, int(b))


func _gain_block(who: Actor, amount: int, raw: bool) -> void:
	if amount <= 0:
		return
	who.block += amount
	floating.emit(who, "+%d Block" % amount, "block")
	if who.is_player and player.has_status("juggernaut"):
		var l := living_enemies()
		if l.size() > 0:
			var t: Actor = l[rng.randi_range(0, l.size() - 1)]
			_damage(t, player.get_status("juggernaut"), player, "attack", null)
	changed.emit()


## Returns the amount of damage that got through the target's Block.
func _damage(target: Actor, amount: int, source: Actor, kind: String, card: Card) -> int:
	if target == null or target.is_dead() or amount <= 0:
		return 0
	if kind == "attack":
		target.attacked_this_combat = true
		if target.has_status("asleep"):
			target.set_status("asleep", 0)
			target.set_status("metallicize", 0)
			_pick_intent(target)
			_say("%s wakes up!" % target.name)
		if target.has_status("curl_up") and not target.has_status("curl_used"):
			target.set_status("curl_used", 1)
			var cu: int = target.get_status("curl_up")
			target.set_status("curl_up", 0)
			_gain_block(target, cu, true)
			_say("%s curls up." % target.name)
		if target.has_status("angry"):
			target.add_signed_status("strength", target.get_status("angry"))
		if target.has_status("flight"):
			target.set_status("flight", target.get_status("flight") - 1)
		if target.has_status("mode_shift"):
			var ms: int = target.get_status("mode_shift") - amount
			if ms <= 0:
				target.set_status("mode_shift", 0)
				target.set_status("defensive_mode", 1)
				_gain_block(target, 20, true)
				_pick_intent(target)
				_say("%s shifts to a defensive stance!" % target.name)
			else:
				target.set_status("mode_shift", ms)

	var remaining := amount
	if target.block > 0:
		var absorbed: int = min(target.block, remaining)
		target.block -= absorbed
		remaining -= absorbed
		if absorbed > 0:
			floating.emit(target, "-%d" % absorbed, "blocked")
	if remaining > 0:
		target.hp = max(_hp_floor(target), target.hp - remaining)
		floating.emit(target, "-%d" % remaining, "damage")
		if target.has_status("plated_armor"):
			target.set_status("plated_armor", target.get_status("plated_armor") - 1)
		if target.is_player:
			_on_player_hp_loss(remaining, true)
		# Envenom / Painful Stabs trigger only on unblocked attack damage.
		if kind == "attack" and source != null and source.is_player \
				and player.has_status("envenom"):
			_apply_status(target, "poison", player.get_status("envenom"), player)
		if kind == "attack" and source != null and not source.is_player \
				and source.has_status("painful_stabs"):
			_add_card_to("wound", "discard", false)
	else:
		floating.emit(target, "Blocked", "blocked")

	# Thorns retaliation
	if kind == "attack" and source != null and source != target:
		var thorns := target.get_status("thorns")
		if thorns > 0:
			_damage(source, thorns, target, "thorns", null)
	if target.is_player:
		Run.hp = player.hp
	return remaining


func _lose_hp(who: Actor, amount: int, reason: String) -> void:
	if amount <= 0 or who == null or who.is_dead():
		return
	who.hp = max(_hp_floor(who), who.hp - amount)
	floating.emit(who, "-%d" % amount, "damage")
	if who.is_player:
		if player.has_status("rupture") and reason != "Poison" and reason != "Burn":
			player.add_signed_status("strength", player.get_status("rupture"))
		_on_player_hp_loss(amount, false)
		Run.hp = player.hp
	if reason != "":
		_say("%s loses %d HP (%s)." % [who.name, amount, reason])
	changed.emit()


func _on_player_hp_loss(amount: int, from_attack: bool) -> void:
	hp_loss_events += 1
	if not lost_hp_this_combat:
		lost_hp_this_combat = true
		if Run.has_relic("centennial_puzzle"):
			_say("The Centennial Puzzle whirs.")
			_draw(3)


func _heal(who: Actor, amount: int) -> void:
	if amount <= 0 or who == null:
		return
	if who.has_status("heal_block"):
		_say("%s cannot be healed right now." % who.name)
		return
	var before := who.hp
	who.hp = min(who.max_hp, who.hp + amount)
	if who.hp > before:
		floating.emit(who, "+%d" % (who.hp - before), "heal")
	if who.is_player:
		Run.hp = player.hp
		Run.hp_changed.emit(Run.hp, Run.max_hp)
	changed.emit()


func _apply_status(target: Actor, id: String, stacks: int, source: Actor) -> void:
	if target == null or target.is_dead() or stacks == 0:
		return
	var debuff := Statuses.is_debuff(id) or (id in ["strength", "dexterity"] and stacks < 0)
	if debuff and target.has_status("artifact"):
		target.set_status("artifact", target.get_status("artifact") - 1)
		_say("%s's Artifact absorbs the debuff." % target.name)
		return
	target.add_signed_status(id, stacks)
	var label := Statuses.display_name(id)
	if not Statuses.is_hidden(id):
		floating.emit(target, "%s %+d" % [label, stacks], "status")
	changed.emit()


func _tick_poison(who: Actor) -> void:
	if who == null or who.is_dead():
		return
	var p := who.get_status("poison")
	if p <= 0:
		return
	who.hp = max(0, who.hp - p)
	floating.emit(who, "-%d Poison" % p, "poison")
	who.set_status("poison", p - 1)
	if who.is_player:
		Run.hp = player.hp
	changed.emit()


func _decay_statuses(who: Actor) -> void:
	for id in who.statuses.keys():
		if String(Statuses.get_def(id)["decay"]) == "turn_end":
			who.set_status(id, who.get_status(id) - 1)


# ═════════════════════════════ Death & completion ════════════════════════════
func living_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.alive and not e.is_dead():
			out.append(e)
	return out


func _check_deaths() -> void:
	for e in enemies:
		if e.alive and e.is_dead():
			e.alive = false
			_on_enemy_death(e)


func _on_enemy_death(e: Actor) -> void:
	_say("%s is defeated." % e.name)
	enemy_died.emit(e)
	if e.has_status("spore_cloud"):
		_apply_status(player, "vulnerable", e.get_status("spore_cloud"), e)
	if e.has_status("corpse_explosion"):
		for other in living_enemies():
			_damage(other, e.max_hp, player, "hp_loss", null)
	if e.has_status("unawakened"):
		e.set_status("unawakened", 0)
		e.alive = true
		e.hp = e.max_hp
		e.block = 0
		_say("%s awakens in fury!" % e.name)
		_pick_intent(e)
		return
	if e.enemy_id == "slime_boss":
		var live_after := living_enemies()
		_split(e, ["acid_slime_m", "spike_slime_m"])
	if Run.has_relic("gremlin_horn"):
		energy += 1
		_draw(1)
	# Minions flee when their leader dies.
	for other in enemies:
		if other.alive and other.is_minion and other.leader == e:
			other.alive = false
			other.hp = 0
			enemy_died.emit(other)


func _check_end() -> bool:
	if finished:
		return true
	if player.hp <= 0:
		finished = true
		victory = false
		phase = "done"
		Run.hp = 0
		combat_finished.emit(false)
		return true
	if living_enemies().is_empty():
		finished = true
		victory = true
		phase = "done"
		_on_victory()
		combat_finished.emit(true)
		return true
	return false


func _on_victory() -> void:
	if Run.has_relic("black_blood"):
		_heal(player, 12)
	elif Run.has_relic("burning_blood"):
		_heal(player, 6)
	if Run.has_relic("meat_on_the_bone") and player.hp_ratio() < 0.5:
		_heal(player, 12)
	Run.hp = player.hp
	Run.hp_changed.emit(Run.hp, Run.max_hp)
	# Reset per-combat card state so the deck is clean next fight.
	var everything: Array = _all_cards()
	everything.append_array(exhaust_pile)
	for c in everything:
		c.cost_override = -99
		c.free_this_turn = false
		c.bonus_damage = 0
	_say("Victory!")


# ═══════════════════════════════════ Potions ═════════════════════════════════
func use_potion(slot: int, target_index: int = -1) -> bool:
	if finished or phase != "player":
		return false
	if player.has_status("embargo"):
		_say("Embargo seals your potions.")
		return false
	var id := String(Run.potions[slot]) if slot < Run.potions.size() else ""
	if id == "":
		return false
	var d := PotionLibrary.get_def(id)
	var living := living_enemies()
	if living.is_empty():
		return false
	var target: Actor = living[0]
	if String(d["target"]) == "enemy":
		if target_index < 0:
			return false
		target = living[clampi(target_index, 0, living.size() - 1)]
	Run.remove_potion(slot)
	potions_used += 1
	_say("You drink the %s." % String(d["name"]))
	var ctx := {"owner": player, "target": target, "params": {}, "source_card": null}
	_push_effects(d["effects"], ctx)
	_run_queue()
	if Run.has_relic("toy_ornithopter"):
		_heal(player, 3)
	return true


# ══════════════════════════════════ Helpers ══════════════════════════════════
func _say(text: String) -> void:
	logged.emit(text)


func preview_target() -> Actor:
	var living := living_enemies()
	if living.is_empty():
		return null
	if preview_target_index >= 0 and preview_target_index < living.size():
		return living[preview_target_index]
	return living[0]


func hand_index(c: Card) -> int:
	return hand.find(c)


func pile_counts() -> Dictionary:
	return {"draw": draw_pile.size(), "discard": discard_pile.size(),
			"exhaust": exhaust_pile.size(), "hand": hand.size()}
