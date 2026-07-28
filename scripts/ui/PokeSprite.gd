class_name PokeSprite
extends Control

## One Pokemon, drawn from the imported PokeAPI sprite set.
##
## The sprites are the 96x96 front-facing pixel art from
## github.com/PokeAPI/sprites, so they are point-filtered and drawn at a whole
## multiple of their native size — anything else turns crisp pixel art into mush.
##
## Sprites face the viewer, which means they face *left* once they are stood on
## the right of a battle line. The player's is therefore mirrored so the two
## sides look at each other, exactly as the games arrange them.
##
## The soft drop shadow and the idle bob are what make a static 96px sprite feel
## alive; both are drawn here rather than baked into the art.

const SPRITE_DIR := "res://assets/pokemon/"
const NATIVE := 96.0

## Seconds for one full up-and-down of the idle bob.
const BOB_PERIOD := 2.4
const BOB_HEIGHT := 5.0

var dex_id: int = 0
var face_right: bool = false
var shadow_colour: Color = Color(0, 0, 0, 0.28)
## Space kept clear beneath the sprite for the shadow to sit in.
var foot_room: float = 12.0

var _tex: TextureRect = null
var _phase: float = 0.0
var _bob_offset: float = 0.0
var _feet_y: float = 0.0


static func exists_for(dex: int) -> bool:
	return ResourceLoader.exists(path_for(dex))


static func path_for(dex: int) -> String:
	return "%s%d.png" % [SPRITE_DIR, dex]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_tex = TextureRect.new()
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Point filtering: these are pixels, and they should look like pixels.
	_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_tex)
	resized.connect(_relayout)
	_relayout()
	# Stagger the bob so a row of the same species does not pulse in lockstep.
	_phase = randf() * BOB_PERIOD
	set_process(true)


## Sizes the sprite to a whole multiple of its native 96px and stands it on the
## floor of the box. Scaling pixel art by 1.25 is what makes it look muddy, so
## it is better to leave margin than to fill the space.
func _relayout() -> void:
	if _tex == null:
		return
	var room := Vector2(size.x, size.y - foot_room)
	var factor: float = maxf(1.0, floor(minf(room.x, room.y) / NATIVE))
	var side := NATIVE * factor
	_tex.size = Vector2(side, side)
	_feet_y = size.y - foot_room
	_tex.position = Vector2((size.x - side) * 0.5, _feet_y - side)
	queue_redraw()


## Points the sprite at a species. Returns false when there is no art for it,
## so the caller can fall back to a name label.
func show_pokemon(dex: int, look_right: bool) -> bool:
	dex_id = dex
	face_right = look_right
	if not is_node_ready():
		await ready
	if dex <= 0 or not exists_for(dex):
		_tex.texture = null
		return false
	_tex.texture = load(path_for(dex))
	_tex.flip_h = look_right
	return true


func _process(delta: float) -> void:
	if _tex == null or _tex.texture == null:
		return
	_phase = fmod(_phase + delta, BOB_PERIOD)
	_bob_offset = sin(_phase / BOB_PERIOD * TAU) * BOB_HEIGHT
	_tex.position.y = _feet_y - _tex.size.y + _bob_offset
	queue_redraw()


## A soft ellipse on the floor, tightening as the sprite rises. Sold entirely by
## the shadow shrinking in sympathy with the bob.
func _draw() -> void:
	if _tex == null or _tex.texture == null:
		return
	var lift: float = (_bob_offset + BOB_HEIGHT) / (BOB_HEIGHT * 2.0)  # 0..1
	var w: float = _tex.size.x * 0.40 * (1.0 - lift * 0.18)
	var h: float = w * 0.22
	var centre := Vector2(size.x * 0.5, _feet_y - 2.0)
	var alpha: float = shadow_colour.a * (1.0 - lift * 0.25)
	var points := PackedVector2Array()
	for i in range(28):
		var a := TAU * float(i) / 28.0
		points.append(centre + Vector2(cos(a) * w, sin(a) * h))
	draw_colored_polygon(points,
			Color(shadow_colour.r, shadow_colour.g, shadow_colour.b, alpha))
