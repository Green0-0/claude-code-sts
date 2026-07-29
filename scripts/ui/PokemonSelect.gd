extends Control

## Character select for the 1025 playable Pokemon.
##
## The whole dex is far too long to list at once, so the panel shows the best
## matches for whatever is typed and says how many it is hiding. Each row is the
## information you would actually pick on: typing, base stats, BST, and the HP
## and Energy that species would run with.

signal chosen(character_id: String)
signal cancelled

const ROWS := 40

## The picker does double duty. In "start" mode it chooses who to run; in
## "capture" mode it chooses what to throw a ball at, and each row is annotated
## with the real odds of that throw landing.
var mode: String = "start"
var _ball: String = "poke"
var _candidates: Array = []

@onready var search_input: LineEdit = $Panel/SearchInput
@onready var hint_label: Label = $Panel/HintLabel
@onready var list: VBoxContainer = $Panel/Scroll/List
@onready var close_button: Button = $Panel/CloseButton

var _rows: Array = []


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_cancel)
	search_input.text_changed.connect(func(_t): _refresh())
	search_input.text_submitted.connect(_on_submit)


func open() -> void:
	mode = "start"
	_candidates = []
	visible = true
	move_to_front()
	search_input.text = ""
	_refresh()
	search_input.grab_focus()


## Opens as a capture prompt over the species the player has met.
func open_capture(candidates: Array, ball: String) -> void:
	mode = "capture"
	_ball = ball
	_candidates = candidates.duplicate()
	visible = true
	move_to_front()
	search_input.text = ""
	_refresh()
	search_input.grab_focus()


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


## Enter picks the top match, so typing "pikachu" and hitting return just works.
func _on_submit(_text: String) -> void:
	if _rows.size() > 0:
		_pick(String(_rows[0]))


func _pick(character_id: String) -> void:
	visible = false
	chosen.emit(character_id)


func request_close() -> bool:
	if not visible:
		return false
	_on_cancel()
	return true


func _refresh() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var query := search_input.text.strip_edges().to_lower()
	var matches: Array = []
	if mode == "capture":
		for name in _candidates:
			if query != "" and not String(name).contains(query):
				continue
			matches.append(PokeCharacters.character_id(String(name)))
			if matches.size() >= ROWS:
				break
	else:
		matches = PokeCharacters.search(query, ROWS)
	_rows = matches

	if mode == "capture":
		var ball_name := String(PokeCapture.ball_def(_ball)["name"])
		hint_label.text = "%s — one throw, at something you have met. %d seen." \
				% [ball_name, _candidates.size()]
	elif query == "":
		hint_label.text = "%d Pokemon. Type a name, a type, or a dex number." \
				% PokeData.mon_count()
	elif matches.is_empty():
		hint_label.text = "Nothing matches \"%s\"." % query
	else:
		hint_label.text = "Showing %d match(es) for \"%s\". Enter picks the first." \
				% [matches.size(), query]

	for id in matches:
		list.add_child(_make_row(String(id)))


func _make_row(character_id: String) -> Button:
	var d := PokeCharacters.get_def(character_id)
	var mon := PokeCharacters.mon_for(character_id)
	var stats: Dictionary = d["stats"]
	var types: Array = d["types"]

	var type_text := ""
	for t in types:
		type_text += ("/" if type_text != "" else "") + PokeData.display_name(String(t))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 46)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 14)
	btn.text = "#%-4d %-13s %-16s  BST %3d   HP %3d  Nrg %d   %d/%d/%d/%d/%d/%d" % [
		int(mon["id"]), String(d["name"]), type_text, int(d["bst"]), int(d["max_hp"]),
		PokeBalance.energy_for(mon),
		int(stats["hp"]), int(stats["atk"]), int(stats["df"]),
		int(stats["spa"]), int(stats["spd"]), int(stats["spe"])]
	if mode == "capture":
		# A ball is thrown at a weakened specimen, so the odds shown are the ones
		# the throw will actually use.
		var chance := PokeCapture.catch_chance(mon, _ball,
				int(round(int(d["max_hp"]) * PokeCapture.CAPTURE_HP_FRACTION)), int(d["max_hp"]))
		btn.text = "#%-4d %-13s %-16s  BST %3d   %s" % [
			int(mon["id"]), String(d["name"]), type_text, int(d["bst"]),
			PokeCapture.describe_odds(chance)]
	btn.tooltip_text = String(d["blurb"])
	btn.add_theme_color_override("font_color", PokeData.type_color(String(types[0])))
	btn.pressed.connect(func(): _pick(character_id))
	return btn
