extends Node

## Captures a handful of Pokemon-mode screens so the layout can be eyeballed.
##   godot -- --poke-shots

const OUT := "user://poke_shots"

var main: Node = null


func _ready() -> void:
	main = get_parent()
	DirAccess.make_dir_recursive_absolute(OUT)
	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	print("[shot] %s" % name)


func _run() -> void:
	# The dex picker, unfiltered and filtered.
	main.pokemon_select.open()
	await _shot("01_select")
	main.pokemon_select.search_input.text = "electric"
	main.pokemon_select._refresh()
	await _shot("02_select_electric")
	main.pokemon_select.visible = false

	# A combat as Pikachu against something Electric is good into.
	Run.start_run(PokeCharacters.character_id("pikachu"), 20260728)
	main._show(main.combat_screen)
	main.combat_screen.begin([PokeMobs.enemy_id("squirtle"),
			PokeMobs.enemy_id("wingull")], "monster")
	await _shot("03_combat")

	# With a card selected and a target hovered, so the matchup note shows.
	if main.combat_screen.card_views.size() > 0:
		main.combat_screen._select(main.combat_screen.card_views[0])
		if main.combat_screen.enemy_views.size() > 0:
			main.combat_screen._on_enemy_hover(main.combat_screen.enemy_views[0], true)
		await _shot("04_targeting")

	# The deck, which is Pikachu's learnset.
	main._on_deck_view()
	await _shot("05_deck")
	main.card_picker.close()

	# A boss, which is where the legendaries live.
	main.combat_screen.begin([PokeMobs.enemy_id("dragonite", "boss")], "boss")
	await _shot("06_boss")

	# The three cast animations, caught mid-flight. Each is sampled twice: once
	# during the ascent every routine shares, and once at the landing that tells
	# them apart.
	await _cast_shots()


## Drives one cast and photographs it at two points along its arc.
func _cast_shots() -> void:
	var cs = main.combat_screen
	Run.start_run(PokeCharacters.character_id("pikachu"), 20260728)
	cs.begin([PokeMobs.enemy_id("squirtle"), PokeMobs.enemy_id("geodude")], "monster")
	await get_tree().process_frame

	var cases := [
		{"tag": "attack", "id": PokeMoves.card_id("thunderbolt"), "target": 0},
		{"tag": "blessing", "id": PokeMoves.card_id("swords-dance"), "target": -1},
		{"tag": "curse", "id": PokeMoves.card_id("thunder-wave"), "target": 0},
	]
	var n := 7
	for c in cases:
		var card := Card.create(String(c["id"]))
		cs.combat.hand.append(card)
		cs.combat.energy = 5
		cs._rebuild_hand()
		await get_tree().process_frame
		cs.combat.play_card(card, int(c["target"]))
		# Mid-ascent, then just after the landing.
		await _wait(0.40)
		await _shot("%02d_%s_rise" % [n, String(c["tag"])])
		await _wait(0.34)
		await _shot("%02d_%s_land" % [n + 1, String(c["tag"])])
		await _wait(0.8)
		n += 2


func _wait(seconds: float) -> void:
	var t := get_tree().create_timer(seconds)
	await t.timeout
