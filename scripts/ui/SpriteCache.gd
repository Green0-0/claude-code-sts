class_name SpriteCache
extends RefCounted

## Loads the Pokemon sprites downloaded by tools/fetch_sprites.py.
##
## These are the front-facing sprites from https://github.com/PokeAPI/sprites,
## 96x96 with transparency, about 1 MB for the whole dex. The player's Pokemon
## is the same sprite mirrored, so the two sides face each other across the
## board — see `flip_for_player`.
##
## Textures are built straight from the PNG rather than through the import
## pipeline, so the sprites work without an editor pass and stay plain files on
## disk. Each one is loaded once and kept.

const DIR := "res://assets/sprites/pokemon"

static var _cache: Dictionary = {}     ## dex number -> Texture2D
static var _missing: Dictionary = {}   ## dex numbers already known to be absent


static func path_for(dex: int) -> String:
	return "%s/%d.png" % [DIR, dex]


static func available() -> bool:
	return FileAccess.file_exists(path_for(1))


## Texture for a dex number, or null if it was never downloaded.
static func texture_for_dex(dex: int) -> Texture2D:
	if _cache.has(dex):
		return _cache[dex]
	if _missing.has(dex):
		return null
	var path := path_for(dex)
	if not FileAccess.file_exists(path):
		_missing[dex] = true
		return null
	var img := Image.new()
	if img.load(path) != OK:
		_missing[dex] = true
		return null
	img = _trim(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[dex] = tex
	return tex


## Crops the transparent margin off a sprite.
##
## Every sprite is drawn on the same 96x96 canvas, so a Diglett occupies a tiny
## corner of it and a Wailord fills it. Left as-is they all render at wildly
## different apparent sizes; trimmed, each one fills the space it is given and
## the whole roster reads at a consistent scale.
static func _trim(img: Image) -> Image:
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return img
	if used.position == Vector2i.ZERO and used.size == img.get_size():
		return img
	var out := Image.create(used.size.x, used.size.y, false, img.get_format())
	out.blit_rect(img, used, Vector2i.ZERO)
	return out


## Texture for a species name, e.g. "pikachu".
static func texture_for(mon_name: String) -> Texture2D:
	if mon_name == "":
		return null
	var mon := PokeData.mon(mon_name)
	if mon.is_empty():
		return null
	return texture_for_dex(int(mon["id"]))


## Texture for whichever Pokemon this actor is, or null for the Spire's cast.
static func texture_for_actor(a: Actor) -> Texture2D:
	if a == null or not a.is_pokemon():
		return null
	return texture_for(a.poke_name)


## Sprites are drawn facing the viewer. The player sits on the left of the board
## looking right, so its sprite is mirrored to face the enemy; enemies are left
## as they are.
static func flip_for_player(who: Actor) -> bool:
	return who != null and who.is_player


## Configures a TextureRect to show a sprite the way this game wants it: crisp
## nearest-neighbour scaling (these are pixel art, not photographs) and centred
## without distortion.
static func dress(rect: TextureRect, tex: Texture2D, flip: bool) -> void:
	rect.texture = tex
	rect.visible = tex != null
	rect.flip_h = flip
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
