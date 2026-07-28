class_name PokeData
extends RefCounted

## Loads the imported PokeAPI data and answers lookups against it.
##
## The three files under res://data/ are a faithful mirror of the API — base
## stats, move mechanics, learnsets, the type chart — and carry no balancing of
## their own. Everything that turns those numbers into Spire units lives in
## PokeBalance; everything that turns a move into a card lives in PokeMoves.
##
## Regenerate the files with:
##   python3 tools/fetch_pokeapi.py && python3 tools/build_data.py
##
## Loading is lazy and cached: a run that never touches a Pokemon never pays for
## the ~1.4 MB parse.

const MONS_PATH := "res://data/pokemon.json"
const MOVES_PATH := "res://data/moves.json"
const TYPES_PATH := "res://data/types.json"

## Learn-method codes, matching METHOD_CODES in tools/build_data.py.
const LEARN_LEVEL := 0
const LEARN_MACHINE := 1
const LEARN_EGG := 2
const LEARN_TUTOR := 3

static var _mons: Array = []
static var _moves: Array = []
static var _types: Array = []
static var _chart: Dictionary = {}
static var _mon_by_name: Dictionary = {}
static var _move_by_name: Dictionary = {}
static var _loaded: bool = false
static var _available: bool = false


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var mons = _read_json(MONS_PATH)
	var moves = _read_json(MOVES_PATH)
	var types = _read_json(TYPES_PATH)
	if mons == null or moves == null or types == null:
		push_warning("Pokemon data missing — run tools/fetch_pokeapi.py then tools/build_data.py")
		return
	_mons = mons
	_moves = moves
	_types = types.get("types", [])
	_chart = types.get("chart", {})
	for i in range(_mons.size()):
		_mon_by_name[String(_mons[i]["name"])] = i
	for i in range(_moves.size()):
		_move_by_name[String(_moves[i]["name"])] = i
	_available = _mons.size() > 0 and _moves.size() > 0


## False when the data files are absent, so the rest of the game can carry on
## without Pokemon content instead of erroring at startup.
static func available() -> bool:
	ensure_loaded()
	return _available


static func mons() -> Array:
	ensure_loaded()
	return _mons


static func moves() -> Array:
	ensure_loaded()
	return _moves


static func type_names() -> Array:
	ensure_loaded()
	return _types


static func mon_count() -> int:
	return mons().size()


static func mon_at(index: int) -> Dictionary:
	var list := mons()
	if index < 0 or index >= list.size():
		return {}
	return list[index]


static func move_at(index: int) -> Dictionary:
	var list := moves()
	if index < 0 or index >= list.size():
		return {}
	return list[index]


## National dex number for a species name, or 0 if it is not one of ours.
static func dex_number(name: String) -> int:
	var mon := mon(name)
	return int(mon.get("id", 0)) if not mon.is_empty() else 0


static func mon_index(name: String) -> int:
	ensure_loaded()
	return int(_mon_by_name.get(name, -1))


static func move_index(name: String) -> int:
	ensure_loaded()
	return int(_move_by_name.get(name, -1))


static func mon(name: String) -> Dictionary:
	return mon_at(mon_index(name))


static func move(name: String) -> Dictionary:
	return move_at(move_index(name))


## "pikachu" -> "Pikachu", "mr-mime" -> "Mr. Mime", "porygon-z" -> "Porygon-Z".
static func display_name(raw: String) -> String:
	var special := {
		"mr-mime": "Mr. Mime", "mr-rime": "Mr. Rime", "mime-jr": "Mime Jr.",
		"porygon-z": "Porygon-Z", "ho-oh": "Ho-Oh", "farfetchd": "Farfetch'd",
		"sirfetchd": "Sirfetch'd", "type-null": "Type: Null", "jangmo-o": "Jangmo-o",
		"hakamo-o": "Hakamo-o", "kommo-o": "Kommo-o", "nidoran-f": "Nidoran♀",
		"nidoran-m": "Nidoran♂", "flabebe": "Flabébé", "wo-chien": "Wo-Chien",
		"chien-pao": "Chien-Pao", "ting-lu": "Ting-Lu", "chi-yu": "Chi-Yu",
		"tapu-koko": "Tapu Koko", "tapu-lele": "Tapu Lele", "tapu-bulu": "Tapu Bulu",
		"tapu-fini": "Tapu Fini", "great-tusk": "Great Tusk",
	}
	if special.has(raw):
		return String(special[raw])
	var parts := raw.split("-")
	var out: Array = []
	for p in parts:
		out.append((p as String).capitalize())
	return " ".join(out)


# ═══════════════════════════════ The type chart ══════════════════════════════
## Damage multiplier for one attacking type against a defender's type list.
## Multiplies each defending type together, exactly as the games do, so a
## Ground move hits a Water/Flying Gyarados for 2.0 x 0.0 = 0.0.
static func effectiveness(attack_type: String, defend_types: Array) -> float:
	ensure_loaded()
	if attack_type == "" or defend_types.is_empty():
		return 1.0
	var row: Dictionary = _chart.get(attack_type, {})
	if row.is_empty():
		return 1.0
	var mult := 1.0
	for t in defend_types:
		mult *= float(row.get(String(t), 1.0))
	return mult


## Player-facing wording for a multiplier, or "" when it is neutral.
static func effectiveness_text(mult: float) -> String:
	if mult <= 0.0:
		return "It has no effect."
	if mult >= 3.9:
		return "It's hyper effective!"
	if mult >= 1.9:
		return "It's super effective!"
	if mult <= 0.26:
		return "It's barely effective..."
	if mult <= 0.51:
		return "It's not very effective..."
	return ""


## 1.5x when the move's type matches one of the user's own types (STAB).
static func stab_bonus(move_type: String, user_types: Array) -> float:
	return 1.5 if user_types.has(move_type) else 1.0


static func type_color(t: String) -> Color:
	match t:
		"normal": return Color(0.66, 0.65, 0.55)
		"fighting": return Color(0.76, 0.18, 0.16)
		"flying": return Color(0.66, 0.56, 0.95)
		"poison": return Color(0.64, 0.24, 0.63)
		"ground": return Color(0.89, 0.75, 0.40)
		"rock": return Color(0.71, 0.63, 0.21)
		"bug": return Color(0.65, 0.73, 0.10)
		"ghost": return Color(0.45, 0.34, 0.59)
		"steel": return Color(0.72, 0.72, 0.81)
		"fire": return Color(0.93, 0.51, 0.19)
		"water": return Color(0.39, 0.56, 0.94)
		"grass": return Color(0.48, 0.78, 0.30)
		"electric": return Color(0.97, 0.82, 0.17)
		"psychic": return Color(0.98, 0.34, 0.53)
		"ice": return Color(0.59, 0.85, 0.84)
		"dragon": return Color(0.44, 0.21, 0.99)
		"dark": return Color(0.44, 0.34, 0.28)
		"fairy": return Color(0.84, 0.52, 0.68)
	return Color(0.7, 0.7, 0.7)
