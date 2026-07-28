extends Node

## Captures Pokemon-mode screens, and the card execution animations frame by
## frame, so the choreography can actually be looked at rather than guessed at.
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
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func _run() -> void:
	main.pokemon_select.open()
	await _shot("01_select")
	main.pokemon_select.search_input.text = "electric"
	main.pokemon_select._refresh()
	await _shot("02_select_electric")
	main.pokemon_select.visible = false

	Run.start_run(PokeCharacters.character_id("pikachu"), 20260728)
	main._show(main.combat_screen)
	main.combat_screen.begin([PokeMobs.enemy_id("squirtle"),
			PokeMobs.enemy_id("wingull")], "monster")
	await _shot("03_combat")

	if main.combat_screen.card_views.size() > 0:
		main.combat_screen._select(main.combat_screen.card_views[0])
		if main.combat_screen.enemy_views.size() > 0:
			main.combat_screen._on_enemy_hover(main.combat_screen.enemy_views[0], true)
		await _shot("04_targeting")
		main.combat_screen._select(null)

	main._on_deck_view()
	await _shot("05_deck")
	main.card_picker.close()

	# ── The three executions, sampled across their run ───────────────────────
	await _film("attack", CardFxLayer.Mode.ATTACK, Color(0.95, 0.82, 0.2), "Thunder Shock")
	await _film("blessing", CardFxLayer.Mode.BLESSING, Color(0.5, 0.85, 0.55), "Growl")
	await _film("curse", CardFxLayer.Mode.CURSE, Color(0.72, 0.4, 0.85), "Toxic")

	main.combat_screen.begin([PokeMobs.enemy_id("dragonite", "boss")], "boss")
	await _shot("09_boss")


## Runs one execution and photographs it at a fixed cadence. The animation is
## driven by real time, so this samples rather than steps.
func _film(label: String, mode: int, colour: Color, title: String) -> void:
	var screen = main.combat_screen
	var fx = screen.fx_layer
	var from: Vector2 = screen._hand_origin()
	var to: Vector2 = screen._actor_centre(screen.combat.enemies[0])

	fx.execute(mode, from, to, colour, title, EnemyView.VIEW_SIZE)
	var frame := 0
	while fx.is_busy() and frame < 40:
		await get_tree().create_timer(0.055, true, false, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
				"%s/fx_%s_%02d.png" % [OUT, label, frame])
		frame += 1
	print("[shot] %s: %d frames" % [label, frame])
