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
	var query := search_input.text.strip_edges()
	var matches := PokeCharacters.search(query, ROWS)
	_rows = matches

	var total := PokeData.mon_count()
	if query == "":
		hint_label.text = "%d Pokemon. Type a name, a type, or a dex number." % total
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
	btn.custom_minimum_size = Vector2(0, 54)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 14)
	btn.text = "        #%-4d %-13s %-16s  BST %3d   HP %3d  Nrg %d   %d/%d/%d/%d/%d/%d" % [
		int(mon["id"]), String(d["name"]), type_text, int(d["bst"]), int(d["max_hp"]),
		PokeBalance.energy_for(mon),
		int(stats["hp"]), int(stats["atk"]), int(stats["df"]),
		int(stats["spa"]), int(stats["spd"]), int(stats["spe"])]
	btn.tooltip_text = String(d["blurb"])
	btn.add_theme_color_override("font_color", PokeData.type_color(String(types[0])))
	btn.pressed.connect(func(): _pick(character_id))

	# The portrait sits in the gap the leading spaces above leave for it.
	var tex := PokeSprites.for_dex(int(mon["id"]))
	if tex != null:
		var icon := PokeSprites.make_rect(tex, Vector2(46, 46))
		icon.position = Vector2(5, 4)
		btn.add_child(icon)
	return btn
