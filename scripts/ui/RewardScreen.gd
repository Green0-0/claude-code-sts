extends Control

## Post-combat rewards: gold, a card choice, sometimes a relic or potion.
##
## Every reward you *can* refuse now pays a pinch of Gold for refusing it. That is
## deliberately a real choice rather than a consolation prize: the money is what
## buys a bag of balls, so a run that keeps skipping cards is a run that catches
## its team instead of drafting it.

signal card_reward_requested(ids: Array, row: int)
signal finished
## A reward turned down for coin, so Main can say so.
signal skipped(kind: String, gold: int)

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
		# Rolled once, here, so the offer cannot be re-rolled by looking at it.
		var r: Dictionary = rewards[i]
		if not r.has("skip_gold"):
			r["skip_gold"] = Run.skip_gold_for(String(r["kind"]))
	_rebuild()


func _rebuild() -> void:
	for child in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	for i in range(rewards.size()):
		var r: Dictionary = rewards[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
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
			"ball":
				# The boss's ball goes into the bag like a bought one, and can be
				# turned down for coin like anything else.
				var bid := String(r["id"])
				var bd := PokeBalls.get_def(bid)
				btn.text = "%s  %s — into the bag" % [String(bd["glyph"]), String(bd["name"])]
				btn.tooltip_text = String(bd["desc"])
				btn.add_theme_color_override("font_color", PokeBalls.rarity_color(bid))
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
		var settled: bool = _claimed[i]
		if settled:
			btn.text = "✓ " + btn.text
			btn.disabled = true
		elif not btn.disabled:
			btn.pressed.connect(_on_row_pressed.bind(i))
		row.add_child(btn)

		# Anything you could have taken can be turned down for coin instead. The
		# receipt rows (experience, the boss's ball) are not offers, so they have
		# nothing to refuse.
		var pinch := int(r.get("skip_gold", 0))
		if pinch > 0 and not settled:
			var skip := Button.new()
			skip.custom_minimum_size = Vector2(176, 56)
			skip.add_theme_font_size_override("font_size", 15)
			skip.focus_mode = Control.FOCUS_NONE
			skip.text = "Skip  →  💰 %d" % pinch
			skip.tooltip_text = "Walk away from this and pocket %d Gold instead. Balls are bought, not given." % pinch
			skip.add_theme_color_override("font_color", UiTheme.GOLD)
			skip.pressed.connect(_on_skip_pressed.bind(i))
			row.add_child(skip)
		rows_box.add_child(row)


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
		"ball":
			Run.add_ball(String(r["id"]))
			_claimed[row] = true
			_rebuild()
		"cards":
			card_reward_requested.emit(r["ids"], row)


## Turned down for coin. The reward is gone either way; this is the other half of
## the choice, not a way to have both.
func _on_skip_pressed(row: int) -> void:
	if row < 0 or row >= rewards.size() or _claimed[row]:
		return
	var r: Dictionary = rewards[row]
	var pinch := int(r.get("skip_gold", 0))
	Run.add_gold(pinch)
	_claimed[row] = true
	skipped.emit(String(r["kind"]), pinch)
	_rebuild()


func mark_claimed(row: int) -> void:
	if row >= 0 and row < _claimed.size():
		_claimed[row] = true
	_rebuild()


## The card picker was closed without a pick. That is a skip, so it pays like one.
func on_card_reward_declined(row: int) -> int:
	if row < 0 or row >= rewards.size() or _claimed[row]:
		mark_claimed(row)
		return 0
	var pinch := int((rewards[row] as Dictionary).get("skip_gold", 0))
	Run.add_gold(pinch)
	_claimed[row] = true
	_rebuild()
	return pinch
