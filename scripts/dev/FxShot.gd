extends Node

## Captures each card-execution animation as a strip of frames, so the timing
## and the impact effects can be eyeballed without playing the game.
##   godot -- --fx-shots

const OUT := "user://fx_shots"
const FRAME_GAP := 5          ## engine frames between captures (~0.08s at 60fps)
const FRAMES := 22

var main: Node = null
var cs: Node = null


func _ready() -> void:
	main = get_parent()
	cs = main.combat_screen
	DirAccess.make_dir_recursive_absolute(OUT)
	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


## Starts an animation without awaiting it, then grabs frames as it plays.
func _burst(label: String, card: Card, from: Rect2, target: Rect2, kind) -> void:
	var fx := CardFx.new()
	cs.add_child(fx)
	fx.execute(card, cs.combat, from, target, kind)
	for i in range(FRAMES):
		for f in range(FRAME_GAP):
			await get_tree().process_frame
		await _shot("%s_%02d" % [label, i])
	print("[fx] %s" % label)
	if is_instance_valid(fx):
		fx.queue_free()


func _run() -> void:
	Run.start_run(PokeCharacters.character_id("pikachu"), 20260728)
	main._show(cs)
	cs.begin([PokeMobs.enemy_id("squirtle"), PokeMobs.enemy_id("wingull")], "monster")
	await get_tree().process_frame
	await _shot("00_board")
	print("[fx] board")

	var hand_rect := Rect2(Vector2(520, 470), CardView.CARD_SIZE)
	var enemy_rect: Rect2 = cs.enemy_views[0].card_rect()
	var player_rect := Rect2(cs.player_panel.global_position, cs.player_panel.size)

	await _burst("attack", Card.create(PokeMoves.card_id("thunderbolt")),
			hand_rect, enemy_rect, CardFx.Kind.ATTACK)
	await _burst("boon", Card.create(PokeMoves.card_id("swords-dance")),
			hand_rect, player_rect, CardFx.Kind.BOON)
	await _burst("hex", Card.create(PokeMoves.card_id("thunder-wave")),
			hand_rect, enemy_rect, CardFx.Kind.HEX)
