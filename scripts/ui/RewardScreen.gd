extends Control

## Post-combat rewards: gold, a card choice, sometimes a relic or potion.

signal card_reward_requested(ids: Array, row: int)
signal finished

@onready var title_label: Label = $TitleLabel
@onready var rows_box: VBoxContainer = $Rows
@onready var proceed_button: Button = $ProceedButton

var rewards: Array = []
var _claimed: Array = []


func _ready() -> void:
	proceed_button.pressed.connect(func(): finished.emit())


func show_rewards(title: String, reward_list: Array) -> void:
	title_label.text = title
	rewards = reward_list
	_claimed.clear()
	for i in range(rewards.size()):
		_claimed.append(false)
	_rebuild()


func _rebuild() -> void:
	for child in rows_box.get_children():
		child.queue_free()
	for i in range(rewards.size()):
		var r: Dictionary = rewards[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(520, 56)
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE
		match String(r["kind"]):
			"xp":
				# Already applied when the fight ended; this row is the receipt.
				var levels := int(r.get("levels", 0))
				btn.text = "✦  %d EXP" % int(r["amount"])
				if levels > 0:
					btn.text += "   —   Level %d!" % int(r.get("level", 0))
				btn.disabled = true
			"gold":
				btn.text = "💰  %d Gold" % int(r["amount"])
			"cards":
				btn.text = "🂠  Add a card to your deck"
			"relic":
				var rid := String(r["id"])
				btn.text = "%s  %s" % [RelicLibrary.get_def(rid)["sigil"],
						RelicLibrary.display_name(rid)]
				btn.tooltip_text = String(RelicLibrary.get_def(rid)["desc"])
			"potion":
				var pid := String(r["id"])
				btn.text = "🧪  %s" % PotionLibrary.display_name(pid)
				btn.tooltip_text = String(PotionLibrary.get_def(pid)["desc"])
				if not Run.has_potion_space():
					btn.text += "   (no free slot)"
					btn.disabled = true
		if _claimed[i]:
			btn.text = "✓ " + btn.text
			btn.disabled = true
		elif not btn.disabled:
			btn.pressed.connect(_on_row_pressed.bind(i))
		rows_box.add_child(btn)


func _on_row_pressed(row: int) -> void:
	var r: Dictionary = rewards[row]
	match String(r["kind"]):
		"gold":
			Run.add_gold(int(r["amount"]))
			_claimed[row] = true
			_rebuild()
		"relic":
			Run.add_relic(String(r["id"]))
			_claimed[row] = true
			_rebuild()
		"potion":
			if Run.add_potion(String(r["id"])):
				_claimed[row] = true
				_rebuild()
		"cards":
			card_reward_requested.emit(r["ids"], row)


func mark_claimed(row: int) -> void:
	if row >= 0 and row < _claimed.size():
		_claimed[row] = true
	_rebuild()
