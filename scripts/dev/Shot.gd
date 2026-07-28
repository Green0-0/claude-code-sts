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
