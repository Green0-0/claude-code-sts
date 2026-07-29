extends Control

## The evolution offer. A branching line (Eevee's eight) becomes a list; a single
## branch is still a choice, because staying unevolved is a real option — the
## earlier form levels faster and its moves come sooner.

signal chosen(index: int)

@onready var title_label: Label = $Panel/TitleLabel
@onready var hint_label: Label = $Panel/HintLabel
@onready var options_box: VBoxContainer = $Panel/Options

var _count: int = 0


func _ready() -> void:
	visible = false


func show_choice(title: String, options: Array) -> void:
	title_label.text = title
	hint_label.text = "Choose what it becomes. Its deck comes with it."
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()
	_count = options.size()
	for i in range(options.size()):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(520, 52)
		btn.add_theme_font_size_override("font_size", 17)
		btn.text = String(options[i])
		# The last entry is always "stay as you are".
		var index := i if i < options.size() - 1 else -1
		btn.pressed.connect(func(): chosen.emit(index))
		options_box.add_child(btn)
	visible = true
