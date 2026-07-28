extends Control

## Character select / continue.

signal start_requested(character: String, seed_value: int)
signal continue_requested

@onready var ironclad_button: Button = $Panel/Choices/IroncladButton
@onready var silent_button: Button = $Panel/Choices/SilentButton
@onready var blurb_label: Label = $Panel/BlurbLabel
@onready var seed_input: LineEdit = $Panel/SeedRow/SeedInput
@onready var continue_button: Button = $Panel/ContinueButton
@onready var quit_button: Button = $Panel/QuitButton
@onready var ascension_spin: SpinBox = $Panel/SeedRow/AscensionSpin

var _selected: String = "ironclad"


func _ready() -> void:
	ironclad_button.pressed.connect(func(): _choose("ironclad"))
	silent_button.pressed.connect(func(): _choose("silent"))
	continue_button.pressed.connect(func(): continue_requested.emit())
	quit_button.pressed.connect(func(): get_tree().quit())
	ironclad_button.gui_input.connect(func(_e): pass)
	_update_blurb()


func refresh() -> void:
	continue_button.visible = Run.has_save()
	_update_blurb()


func _choose(id: String) -> void:
	_selected = id
	_update_blurb()
	var seed_text := seed_input.text.strip_edges()
	var seed_value := 0
	if seed_text != "":
		seed_value = int(seed_text.hash()) if not seed_text.is_valid_int() else int(seed_text)
	Run.ascension = int(ascension_spin.value)
	start_requested.emit(_selected, seed_value)


func _update_blurb() -> void:
	var c: Dictionary = CardLibrary.CHARACTERS[_selected]
	blurb_label.text = "%s — %d HP\n%s" % [c["name"], c["max_hp"], c["blurb"]]
	blurb_label.modulate = c["tint"]
