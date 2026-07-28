extends Panel

## Persistent HUD: HP, gold, act/floor, relics, potions, deck view.

signal deck_view_requested
signal potion_used(slot: int)
signal potion_discarded(slot: int)
signal menu_requested

@onready var hp_label: Label = $Bar/HpLabel
@onready var gold_label: Label = $Bar/GoldLabel
@onready var floor_label: Label = $Bar/FloorLabel
@onready var deck_button: Button = $Bar/DeckButton
@onready var relic_box: HBoxContainer = $Bar/RelicBox
@onready var potion_box: HBoxContainer = $Bar/PotionBox
@onready var menu_button: Button = $Bar/MenuButton

var potions_enabled: bool = true


func _ready() -> void:
	deck_button.pressed.connect(func(): deck_view_requested.emit())
	menu_button.pressed.connect(func(): menu_requested.emit())
	Run.gold_changed.connect(func(_g): refresh())
	Run.hp_changed.connect(func(_h, _m): refresh())
	Run.relic_gained.connect(func(_r): refresh())
	Run.deck_changed.connect(refresh)


func refresh() -> void:
	if not is_node_ready():
		return
	hp_label.text = "❤ %d / %d" % [Run.hp, Run.max_hp]
	hp_label.modulate = Color(1, 0.45, 0.45) if Run.hp_ratio_low() else Color(1, 1, 1)
	gold_label.text = "💰 %d" % Run.gold
	floor_label.text = "Act %d · Floor %d" % [Run.act, Run.floor_num]
	deck_button.text = "Deck (%d)" % Run.deck.size()

	for child in relic_box.get_children():
		child.queue_free()
	for rid in Run.relics:
		var d := RelicLibrary.get_def(rid)
		var lbl := Label.new()
		lbl.text = String(d["sigil"])
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.tooltip_text = "%s — %s" % [d["name"], d["desc"]]
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		relic_box.add_child(lbl)

	for child in potion_box.get_children():
		child.queue_free()
	for i in range(Run.potions.size()):
		var pid := String(Run.potions[i])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(34, 30)
		btn.focus_mode = Control.FOCUS_NONE
		if pid == "":
			btn.text = "·"
			btn.disabled = true
			btn.tooltip_text = "Empty potion slot"
		else:
			var pd := PotionLibrary.get_def(pid)
			btn.text = "🧪"
			btn.modulate = pd["color"]
			btn.tooltip_text = "%s — %s\n(right-click to discard)" % [pd["name"], pd["desc"]]
			btn.disabled = not potions_enabled and bool(pd["combat_only"])
			btn.pressed.connect(func(): potion_used.emit(i))
			btn.gui_input.connect(_potion_input.bind(i))
		potion_box.add_child(btn)


func _potion_input(event: InputEvent, slot: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		potion_discarded.emit(slot)
