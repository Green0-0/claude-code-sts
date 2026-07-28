class_name PokeSprites
extends RefCounted

## Loads the imported Pokemon artwork, cached by dex number.
##
## The files under assets/sprites/pokemon/ are the PokeAPI repository's HOME
## renders, trimmed and downscaled by tools/fetch_sprites.py. Everything here is
## optional: with the folder absent the game falls back to the type glyph it used
## before, so a checkout without the art still runs and still passes its tests.

const DIR := "res://assets/sprites/pokemon"

static var _cache: Dictionary = {}     ## dex -> Texture2D (or null when missing)
static var _available: int = -1        ## -1 unknown, 0 no, 1 yes


## Whether any artwork is installed at all.
static func available() -> bool:
	if _available < 0:
		_available = 1 if DirAccess.dir_exists_absolute(DIR) else 0
	return _available == 1


static func path_for(dex: int) -> String:
	return "%s/%d.png" % [DIR, dex]


## Texture for a dex number, or null when that sprite is not installed.
static func texture_for_dex(dex: int) -> Texture2D:
	if dex <= 0 or not available():
		return null
	if _cache.has(dex):
		return _cache[dex]
	var tex: Texture2D = null
	var path := path_for(dex)
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[dex] = tex
	return tex


static func texture_for(mon_name: String) -> Texture2D:
	var mon := PokeData.mon(mon_name)
	if mon.is_empty():
		return null
	return texture_for_dex(int(mon["id"]))


## The sprite for whichever species this actor is, or null for the Spire's cast.
static func texture_for_actor(a: Actor) -> Texture2D:
	if a == null or not a.is_pokemon():
		return null
	return texture_for(a.poke_name)
