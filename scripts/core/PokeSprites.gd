class_name PokeSprites
extends RefCounted

## Hands out a Pokemon's sprite from the packed atlas.
##
## assets/pokemon_atlas.png is the whole dex on one 33-column grid of 96x96
## cells, built by tools/build_atlas.py from github.com/PokeAPI/sprites. The
## layout is implicit — cell = dex - 1 — so there is no manifest to keep in
## step, and one texture covers 1025 species.
##
## Sprites are pixel art, so everything here keeps nearest-neighbour filtering:
## they are drawn at 2-4x and should stay crisp rather than turning to soup.

const ATLAS_PATH := "res://assets/pokemon_atlas.png"
const CELL := 96
const COLS := 33

static var _atlas: Texture2D = null
static var _looked_for_atlas := false
static var _cache: Dictionary = {}      ## dex -> AtlasTexture


static func atlas() -> Texture2D:
	if not _looked_for_atlas:
		_looked_for_atlas = true
		if ResourceLoader.exists(ATLAS_PATH):
			_atlas = load(ATLAS_PATH)
		else:
			push_warning("Sprite atlas missing — run tools/fetch_sprites.py "
					+ "then tools/build_atlas.py")
	return _atlas


static func available() -> bool:
	return atlas() != null


## The sprite for a dex number, or null if there is no atlas.
static func for_dex(dex: int) -> Texture2D:
	if dex <= 0:
		return null
	if _cache.has(dex):
		return _cache[dex]
	var sheet := atlas()
	if sheet == null:
		return null
	var cell := dex - 1
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = Rect2((cell % COLS) * CELL, (cell / COLS) * CELL, CELL, CELL)
	tex.filter_clip = true
	_cache[dex] = tex
	return tex


## The sprite for a species name, e.g. "pikachu".
static func for_name(mon_name: String) -> Texture2D:
	if mon_name == "":
		return null
	var mon := PokeData.mon(mon_name)
	if mon.is_empty():
		return null
	return for_dex(int(mon["id"]))


## The sprite for whoever this actor is, or null for the Spire's own cast.
static func for_actor(a) -> Texture2D:
	if a == null or not a.is_pokemon():
		return null
	return for_name(a.poke_name)


## A TextureRect set up the way this project always wants one: pixel-crisp,
## aspect-preserving, and ignoring mouse input so it never eats a click.
static func make_rect(tex: Texture2D, size: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	# expand_mode first: while it is the default KEEP_SIZE the node's minimum
	# size is the texture's own 96x96, which silently overrides any smaller size
	# asked for below and leaves the sprite spilling out of its row.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture = tex
	rect.custom_minimum_size = size
	rect.size = size
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
