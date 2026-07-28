extends Control

## The merchant. Cards, relics, potions and one card-removal service.

signal leave_requested
signal removal_requested

const CARD_SCENE := preload("res://scenes/CardView.tscn")

@onready var card_row: HBoxContainer = $Scroll/Content/CardRow
@onready var relic_row: HBoxContainer = $Scroll/Content/RelicRow
@onready var potion_row: HBoxContainer = $Scroll/Content/PotionRow
@onready var remove_button: Button = $Bottom/RemoveButton
@onready var leave_button: Button = $Bottom/LeaveButton
@onready var gold_label: Label = $GoldLabel
@onready var notice: Label = $Notice

var stock: Dictionary = {}


func _ready() -> void:
	leave_button.pressed.connect(func(): leave_requested.emit())
	remove_button.pressed.connect(_on_remove)


func open_shop(shop_stock: Dictionary) -> void:
	stock = shop_stock
	notice.text = ""
	_rebuild()


func _rebuild() -> void:
	gold_label.text = "💰 %d Gold" % Run.gold
	for row in [card_row, relic_row, potion_row]:
		for child in row.get_children():
			child.queue_free()

	for i in range((stock["cards"] as Array).size()):
		var entry: Dictionary = stock["cards"][i]
		var holder := VBoxContainer.new()
		holder.custom_minimum_size = Vector2(190, 300)
		var view: CardView = CARD_SCENE.instantiate()
		view.interactive = false
		holder.add_child(view)
		view.setup(Card.create(String(entry["id"])), null)
		var btn := Button.new()
		btn.text = "SOLD" if bool(entry["sold"]) else "%d Gold" % int(entry["price"])
		btn.disabled = bool(entry["sold"]) or Run.gold < int(entry["price"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_buy_card.bind(i))
		holder.add_child(btn)
		card_row.add_child(holder)

	for i in range((stock["relics"] as Array).size()):
		var entry2: Dictionary = stock["relics"][i]
		var rid := String(entry2["id"])
		var btn2 := Button.new()
		btn2.custom_minimum_size = Vector2(230, 74)
		btn2.text = "%s %s\n%s" % [RelicLibrary.get_def(rid)["sigil"],
				RelicLibrary.display_name(rid),
				"SOLD" if bool(entry2["sold"]) else "%d Gold" % int(entry2["price"])]
		btn2.tooltip_text = String(RelicLibrary.get_def(rid)["desc"])
		btn2.disabled = bool(entry2["sold"]) or Run.gold < int(entry2["price"])
		btn2.focus_mode = Control.FOCUS_NONE
		btn2.pressed.connect(_buy_relic.bind(i))
		relic_row.add_child(btn2)

	for i in range((stock["potions"] as Array).size()):
		var entry3: Dictionary = stock["potions"][i]
		var pid := String(entry3["id"])
		var btn3 := Button.new()
		btn3.custom_minimum_size = Vector2(210, 74)
		btn3.text = "🧪 %s\n%s" % [PotionLibrary.display_name(pid),
				"SOLD" if bool(entry3["sold"]) else "%d Gold" % int(entry3["price"])]
		btn3.tooltip_text = String(PotionLibrary.get_def(pid)["desc"])
		btn3.disabled = bool(entry3["sold"]) or Run.gold < int(entry3["price"])
		btn3.focus_mode = Control.FOCUS_NONE
		btn3.pressed.connect(_buy_potion.bind(i))
		potion_row.add_child(btn3)

	var cost := int(stock["removal_cost"])
	remove_button.text = "Remove a card — %d Gold" % cost
	remove_button.disabled = Run.gold < cost


func _buy_card(i: int) -> void:
	var entry: Dictionary = stock["cards"][i]
	if bool(entry["sold"]) or not Run.spend_gold(int(entry["price"])):
		return
	entry["sold"] = true
	Run.add_card(Card.create(String(entry["id"])))
	notice.text = "%s joins your deck." % CardLibrary.get_def(String(entry["id"]))["name"]
	_rebuild()


func _buy_relic(i: int) -> void:
	var entry: Dictionary = stock["relics"][i]
	if bool(entry["sold"]) or not Run.spend_gold(int(entry["price"])):
		return
	entry["sold"] = true
	Run.add_relic(String(entry["id"]))
	notice.text = "You obtain %s." % RelicLibrary.display_name(String(entry["id"]))
	_rebuild()


func _buy_potion(i: int) -> void:
	var entry: Dictionary = stock["potions"][i]
	if bool(entry["sold"]):
		return
	if not Run.has_potion_space():
		notice.text = "You have no free potion slots."
		return
	if not Run.spend_gold(int(entry["price"])):
		return
	entry["sold"] = true
	Run.add_potion(String(entry["id"]))
	notice.text = "You buy a %s." % PotionLibrary.display_name(String(entry["id"]))
	_rebuild()


func _on_remove() -> void:
	removal_requested.emit()


func complete_removal(c: Card) -> void:
	var cost := int(stock["removal_cost"])
	if not Run.spend_gold(cost):
		return
	Run.remove_card(c)
	Run.shop_removals += 1
	stock["removal_cost"] = 75 + Run.shop_removals * 25
	notice.text = "%s is removed from your deck." % c.display_name()
	_rebuild()


func refresh() -> void:
	_rebuild()
