extends Node

## Drives the UI with synthesized mouse events, so the real input path gets
## tested rather than the signal handlers being called directly.
##   godot --headless -- --click-test

var main: Node = null
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	main = get_parent()
	await get_tree().process_frame
	await _run()
	print("[click] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, got, want) -> void:
	if got == want:
		passed += 1
		print("[click] ok   %s = %s" % [label, str(got)])
	else:
		failed += 1
		print("[click] FAIL %s: got %s, want %s" % [label, str(got), str(want)])


func _click_at(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = pos
		click.global_position = pos
		Input.parse_input_event(click)
		await get_tree().process_frame
	await get_tree().process_frame


func _click_control(c: Control) -> void:
	await _click_at(c.get_global_rect().get_center())


func _run() -> void:
	# Start a Silent run so Survivor ("Gain 8 Block. Discard 1 card") is in the deck.
	Run.start_run("silent", 99)
	main._show(main.combat_screen)
	main.combat_screen.begin(["jaw_worm"], "monster")
	await get_tree().process_frame

	var c: Combat = main.combat_screen.combat
	var survivor := Card.create("survivor")
	c.hand.append(survivor)
	c.energy = 3
	main.combat_screen._refresh_all()
	await get_tree().process_frame

	var hand_before: int = c.hand.size()
	var discard_before: int = c.discard_pile.size()

	# Play it through the engine; the discard prompt should open the picker.
	c.play_card(survivor, 0)
	await get_tree().process_frame
	await get_tree().process_frame

	var picker = main.card_picker
	_check("picker opened", picker.visible, true)
	_check("picker mode", picker._mode, "select")
	_check("cards to choose from", picker._views.size(), hand_before - 1)
	_check("needs one card", picker._needed, 1)
	if not picker.visible or picker._views.size() == 0:
		failed += 1
		print("[click] cannot continue: picker did not open")
		return

	# What does the viewport think is under the first card?
	var first: CardView = picker._views[0]
	var point := first.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var hovered := get_viewport().gui_get_hovered_control()
	print("[click] control under card: %s (%s)" % [
			hovered.name if hovered != null else "<null>",
			hovered.get_class() if hovered != null else "-"])
	print("[click] card rect: %s  visible_in_tree: %s  mouse_filter: %d" % [
			str(first.get_global_rect()), str(first.is_visible_in_tree()),
			first.mouse_filter])

	# Click the card.
	await _click_control(first)
	_check("card selected by click", picker._selection.size(), 1)
	_check("confirm enabled", picker.confirm_button.disabled, false)

	if picker._selection.is_empty():
		print("[click] selection did not register — clicks are not reaching the card")
		return

	# Click Confirm.
	await _click_control(picker.confirm_button)
	await get_tree().process_frame
	_check("picker hidden after confirm", picker.visible, false)
	_check("choice cleared", c.pending_choice.is_empty(), true)
	# Survivor itself plus the discarded card both land in the discard pile.
	_check("two cards discarded", c.discard_pile.size(), discard_before + 2)
	_check("hand shrank by two", c.hand.size(), hand_before - 2)
	_check("block gained", c.player.block > 0, true)

	await _test_prompt_draws_above_the_hand(c)
	await _test_escape_during_mandatory_choice(c)
	await _test_picker_reopen(c)
	await _test_event_prompt()
	# Last, because it starts a fresh run: anything sharing the combat built in
	# _run() has to have finished before the deck is replaced.
	await _test_card_execution()


## Playing a card now runs an execution animation and only resolves on impact,
## which is a path the autoplay harness never takes — it calls the engine
## directly. So this drives it the way a player does: click the card, click the
## target, and check the damage lands once the animation is over rather than
## when the mouse was released.
func _test_card_execution() -> void:
	print("[click] --- card execution animation")
	Run.start_run(PokeCharacters.character_id("pikachu"), 31337)
	main._show(main.combat_screen)
	var screen = main.combat_screen
	screen.begin([PokeMobs.enemy_id("squirtle")], "monster")
	await get_tree().process_frame

	var c: Combat = screen.combat
	var foe: Actor = c.enemies[0]
	# Find an attack in hand, which is the routine with the impact.
	var attack_view = null
	for v in screen.card_views:
		if v.card.type() == "attack" and c.can_play(v.card, 0)["ok"]:
			attack_view = v
			break
	if attack_view == null:
		_check("pikachu drew an attack", 0, 1)
		return
	_check("found an attack to play", attack_view.card.type(), "attack")

	var hp_before := foe.hp
	var hand_before := c.hand.size()
	await _click_control(attack_view)          # select
	await _click_control(screen.enemy_views[0])  # commit at the target

	# Mid-flight: the card must not have resolved, and the hand must be locked.
	_check("resolution waits for impact", foe.hp, hp_before)
	_check("the hand is locked mid-execution", screen._busy, true)

	# The whole routine is under a second; give it two and then check.
	var waited := 0.0
	while screen.fx_layer.is_busy() and waited < 2.0:
		await get_tree().create_timer(0.05, true, false, true).timeout
		waited += 0.05
	await get_tree().process_frame
	await get_tree().process_frame

	_check("the animation finished", screen.fx_layer.is_busy(), false)
	_check("damage landed after impact", foe.hp < hp_before, true)
	_check("the card left the hand", c.hand.size() < hand_before, true)
	_check("the hand is playable again", screen._busy, false)


## The prompt is modal, but the hand fans itself with z_index, and z_index beats
## tree order. Unless the picker outranks the whole fan the hand paints over it,
## burying Confirm — clickable but invisible, which reads as a soft-lock.
func _test_prompt_draws_above_the_hand(c: Combat) -> void:
	print("[click] --- prompt draws above the hand")
	var picker = main.card_picker
	var survivor := Card.create("survivor")
	c.hand.append(survivor)
	c.energy = 3
	c.play_card(survivor, 0)
	await get_tree().process_frame
	_check("prompt open", picker.visible, true)

	var top: int = main.combat_screen.HAND_Z_DRAG
	for v in main.combat_screen.card_views:
		top = maxi(top, v.z_index)
	_check("picker outranks every hand card", picker.z_index > top, true)

	# And the button really is the thing under the cursor at its own centre.
	var point: Vector2 = picker.confirm_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await get_tree().process_frame
	_check("confirm is the control under the cursor",
			get_viewport().gui_get_hovered_control(), picker.confirm_button)

	if picker.visible and picker._views.size() > 0:
		await _click_control(picker._views[0])
		await _click_control(picker.confirm_button)
		await get_tree().process_frame
	_check("prompt answered", c.pending_choice.is_empty(), true)


## A mandatory prompt must not be dismissable, or the run soft-locks: the model
## still holds pending_choice, which blocks every card and End Turn.
func _test_escape_during_mandatory_choice(c: Combat) -> void:
	print("[click] --- escape during a mandatory discard")
	var survivor := Card.create("survivor")
	c.hand.append(survivor)
	c.energy = 3
	c.play_card(survivor, 0)
	await get_tree().process_frame
	var picker = main.card_picker
	_check("prompt open", picker.visible, true)
	_check("prompt is mandatory", picker.cancel_button.visible, false)

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("still open after escape", picker.visible, true)
	_check("choice still pending", c.pending_choice.is_empty(), false)

	# And the game must still be playable once the choice is answered.
	if picker.visible and picker._views.size() > 0:
		await _click_control(picker._views[0])
		await _click_control(picker.confirm_button)
		await get_tree().process_frame
	_check("recovered: no pending choice", c.pending_choice.is_empty(), true)
	_check("recovered: can end turn", c.phase, "player")


## Events have the same exposure: an option that asks you to pick a card hides the
## options and only shows Continue afterwards, so a dismissable prompt would strand
## the screen with nothing clickable.
func _test_event_prompt() -> void:
	print("[click] --- event card prompt")
	var picker = main.card_picker
	main._show(main.event_screen)
	main.event_screen.show_event("living_wall")
	await get_tree().process_frame

	var options: Array = main.event_screen.options_box.get_children()
	_check("event has options", options.size() > 0, true)
	await _click_control(options[0] as Button)
	_check("event prompt open", picker.visible, true)
	_check("event prompt mandatory", picker.cancel_button.visible, false)

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("event prompt survives escape", picker.visible, true)

	var deck_before: int = Run.deck.size()
	if picker.visible and picker._views.size() > 0:
		await _click_control(picker._views[0])
		await get_tree().process_frame
	_check("event prompt closed after picking", picker.visible, false)
	_check("card removed from deck", Run.deck.size(), deck_before - 1)
	_check("event can be left", main.event_screen.continue_button.visible, true)


## Opening the picker twice must not leave the previous batch of cards in the grid.
func _test_picker_reopen(c: Combat) -> void:
	print("[click] --- reopening the picker")
	var picker = main.card_picker
	main._on_deck_view()
	await get_tree().process_frame
	var deck_views: int = picker._views.size()
	_check("deck view populated", deck_views, Run.deck.size())
	picker._on_cancel()
	await get_tree().process_frame

	var acrobatics := Card.create("acrobatics")
	c.hand.append(acrobatics)
	c.energy = 3
	c.play_card(acrobatics, 0)
	await get_tree().process_frame
	_check("second prompt open", picker.visible, true)
	_check("grid holds only the new cards", picker.grid.get_child_count(),
			picker._views.size())
	if picker._views.size() > 0:
		var first_card: CardView = picker._views[0]
		_check("first card is on screen",
				picker.grid.get_global_rect().intersects(first_card.get_global_rect()), true)
		await _click_control(first_card)
		_check("reopened picker accepts clicks", picker._selection.size(), 1)
		await _click_control(picker.confirm_button)
		await get_tree().process_frame
	_check("second choice resolved", c.pending_choice.is_empty(), true)
