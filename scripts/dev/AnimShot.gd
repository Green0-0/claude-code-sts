extends Node

## Captures the card-execution animations frame by frame so they can actually be
## looked at rather than assumed.
##   godot -- --anim-shots
##
## Runs each choreography with the clock slowed right down and grabs a strip of
## frames through it, plus stills of the sprite work.

const OUT := "user://anim_shots"
const STRIP := 16             ## frames grabbed per animation
## The chop lasts 0.11s. At normal speed a strip skips straight over it, so the
## whole clock is slowed and every other frame is grabbed.
const SLOWDOWN := 0.2
const FRAMES_PER_GRAB := 2

var main: Node = null
var cs: Node = null


func _ready() -> void:
	main = get_parent()
	DirAccess.make_dir_recursive_absolute(OUT)
	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func _begin_fight() -> void:
	Run.start_run(PokeCharacters.character_id("pikachu"), 20260728)
	main._show(main.combat_screen)
	cs = main.combat_screen
	cs.begin([PokeMobs.enemy_id("squirtle"), PokeMobs.enemy_id("wingull")], "monster")
	await get_tree().process_frame
	await get_tree().process_frame


## Plays one animation and grabs a strip of frames across it.
func _capture(tag: String, card_id: String, target_index: int) -> void:
	await _begin_fight()
	var card := Card.create(card_id)
	cs.combat.hand.append(card)
	cs.combat.energy = 5
	cs._rebuild_hand()
	await get_tree().process_frame

	var view = null
	for v in cs.card_views:
		if v.card == card:
			view = v
	if view == null:
		print("[anim] %s: no view for %s" % [tag, card_id])
		return

	print("[anim] %s -> %s" % [tag, card.display_name()])
	Engine.time_scale = SLOWDOWN
	cs._try_play(view, target_index)
	for i in range(STRIP):
		for f in range(FRAMES_PER_GRAB):
			await get_tree().process_frame
		await _shot("%s_%02d" % [tag, i])
	Engine.time_scale = 1.0


func _run() -> void:
	# An attack: rise, spin, flash, reappear overhead, chop.
	await _capture("attack", PokeMoves.card_id("thunder-shock"), 0)
	# A blessing on the caster: rise, settle, melt, ripple.
	await _capture("bless", PokeMoves.card_id("growl"), -1)
	# A hex on the enemy: the blessing's opening, then the drop and the shatter.
	await _capture("hex", PokeMoves.card_id("tail-whip"), 0)

	# And the static picture, for the sprite work.
	await _begin_fight()
	await _shot("combat_idle")
	print("[anim] done")
