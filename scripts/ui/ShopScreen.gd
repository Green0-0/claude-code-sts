extends Control

## The merchant. Cards, relics, potions, balls, and one card-removal service.

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

## The ball rack, built in code because it is not one row but one row per category
## with a heading over each — a shelf rather than a shelf's worth of buttons.
var ball_section: VBoxContainer = null

var stock: Dictionary = {}


func _ready() -> void:
	leave_button.pressed.connect(func(): leave_requested.emit())
	remove_button.pressed.connect(_on_remove)
	ball_section = VBoxContainer.new()
	ball_section.name = "BallSection"
	ball_section.add_theme_constant_override("separation", 4)
	$Scroll/Content.add_child(ball_section)
	# Straight after the cards rather than at the foot of the shelf: balls are what
	# a Pokemon run is here to buy, and they should not need scrolling to find.
	$Scroll/Content.move_child(ball_section, 1)


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

	_rebuild_balls()

	var cost := int(stock["removal_cost"])
	remove_button.text = "Remove a card — %d Gold" % cost
	remove_button.disabled = Run.gold < cost


## The ball rack. Grouped by category with a heading over each, and every price
## tag carries the condition the ball is worth its multiplier under — a Net Ball
## is only a bargain if you expect to meet something wet.
func _rebuild_balls() -> void:
	for child in ball_section.get_children():
		ball_section.remove_child(child)
		child.queue_free()
	var entries: Array = stock.get("balls", [])
	if entries.is_empty():
		ball_section.visible = false
		return
	ball_section.visible = true

	var title := Label.new()
	title.text = "◓  The ball rack — %d in the bag" % Run.total_balls()
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	ball_section.add_child(title)

	var last_category := ""
	var row: HBoxContainer = null
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var id := String(entry["id"])
		var category := PokeBalls.category_of(id)
		if category != last_category:
			last_category = category
			var heading := Label.new()
			heading.text = "%s — %s" % [PokeBalls.CATEGORY_NAMES.get(category, category),
					PokeBalls.CATEGORY_BLURBS.get(category, "")]
			heading.add_theme_font_size_override("font_size", 13)
			heading.add_theme_color_override("font_color", UiTheme.DIM)
			ball_section.add_child(heading)
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			ball_section.add_child(row)
		if row == null:
			continue
		row.add_child(_make_ball_button(entry, i))


func _make_ball_button(entry: Dictionary, index: int) -> Button:
	var id := String(entry["id"])
	var d := PokeBalls.get_def(id)
	var left := int(entry["stock"]) - int(entry["sold"])
	var price := int(entry["price"])
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(214, 78)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	var held := Run.ball_count(id)
	if left <= 0:
		btn.text = "%s %s\nSOLD OUT" % [String(d["glyph"]), String(d["name"])]
		btn.disabled = true
	else:
		btn.text = "%s %s   ×%d\n%d Gold%s" % [String(d["glyph"]), String(d["name"]),
				left, price, "   (have %d)" % held if held > 0 else ""]
		btn.disabled = Run.gold < price
	btn.add_theme_color_override("font_color", PokeBalls.rarity_color(id))
	# The tooltip is where the actual decision is made, so it carries the rarity,
	# the condition and how the ball behaves in the air.
	var handling := PokeBalls.handling(id)
	var lines: Array = ["%s — %s, %s" % [String(d["name"]),
			PokeBalls.rarity_of(id), PokeBalls.category_of(id)], String(d["desc"])]
	if float(handling["sweet"]) != 1.0:
		lines.append("Sweet spot %+d%%." % int(round((float(handling["sweet"]) - 1.0) * 100.0)))
	if float(handling["drag"]) != 1.0:
		lines.append("Flies %s." % ("heavily" if float(handling["drag"]) > 1.0 else "light and fast"))
	if float(handling["curve"]) != 1.0:
		lines.append("Takes %s swerve." % ("more" if float(handling["curve"]) > 1.0 else "less"))
	if PokeBalls.join_bonus(id) > 0:
		lines.append("What it holds joins %d level(s) higher." % PokeBalls.join_bonus(id))
	if PokeBalls.heals_on_catch(id):
		lines.append("What it holds arrives fully healed.")
	btn.tooltip_text = "\n".join(lines)
	btn.pressed.connect(_buy_ball.bind(index))
	return btn


func _buy_ball(index: int) -> void:
	var entries: Array = stock.get("balls", [])
	if index < 0 or index >= entries.size():
		return
	var entry: Dictionary = entries[index]
	if int(entry["sold"]) >= int(entry["stock"]):
		return
	if not Run.spend_gold(int(entry["price"])):
		return
	entry["sold"] = int(entry["sold"]) + 1
	Run.add_ball(String(entry["id"]))
	notice.text = "You pocket a %s." % PokeBalls.display_name(String(entry["id"]))
	_rebuild()


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
