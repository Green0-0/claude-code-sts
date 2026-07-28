extends Control

## Question-mark rooms: flavour text plus a handful of choices.

signal option_chosen(event_id: String, option_index: int)
signal finished

@onready var name_label: Label = $NameLabel
@onready var text_label: RichTextLabel = $TextLabel
@onready var options_box: VBoxContainer = $Options
@onready var result_label: Label = $ResultLabel
@onready var continue_button: Button = $ContinueButton

var event_id: String = ""


func _ready() -> void:
	continue_button.pressed.connect(func(): finished.emit())


func show_event(id: String) -> void:
	event_id = id
	var ev: Dictionary = Run.EVENTS[id]
	name_label.text = String(ev["name"])
	text_label.clear()
	text_label.append_text("[center]%s[/center]" % String(ev["text"]))
	result_label.text = ""
	continue_button.visible = false
	for child in options_box.get_children():
		child.queue_free()
	var opts: Array = ev["options"]
	for i in range(opts.size()):
		var btn := Button.new()
		btn.text = String((opts[i] as Dictionary)["label"])
		btn.custom_minimum_size = Vector2(600, 52)
		btn.add_theme_font_size_override("font_size", 17)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): option_chosen.emit(event_id, i))
		options_box.add_child(btn)


func show_result(text: String) -> void:
	result_label.text = text
	for child in options_box.get_children():
		(child as Button).disabled = true
	continue_button.visible = true
