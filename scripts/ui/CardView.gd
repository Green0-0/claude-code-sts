class_name CardView
extends Control

## Visual representation of a single Card.

signal pressed(view: CardView)
signal released(view: CardView, at: Vector2)
signal hover_changed(view: CardView, inside: bool)

const CARD_SIZE := Vector2(184, 254)

@onready var frame: Panel = $Frame
@onready var banner: Panel = $Frame/Banner
@onready var name_label: Label = $Frame/NameLabel
@onready var cost_badge: Panel = $Frame/CostBadge
@onready var cost_label: Label = $Frame/CostBadge/CostLabel
@onready var type_label: Label = $Frame/TypeLabel
@onready var text_label: RichTextLabel = $Frame/TextLabel
@onready var art_panel: Panel = $Frame/ArtPanel
@onready var art_glyph: Label = $Frame/ArtPanel/ArtGlyph
@onready var glow: Panel = $Glow

var card: Card = null
var combat = null
var interactive: bool = true
var playable: bool = true
var selected: bool = false
var home_position: Vector2 = Vector2.ZERO
var home_rotation: float = 0.0
var home_scale: float = 1.0
var _hovering: bool = false


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	if glow != null:
		glow.visible = false
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func setup(c: Card, cmb = null) -> void:
	card = c
	combat = cmb
	if not is_node_ready():
		await ready
	refresh()


func refresh() -> void:
	if card == null:
		return
	var def := card.def()
	var ctype: String = card.type()
	var accent: Color = CardLibrary.type_tint(ctype)
	var base: Color = card.tint()

	var sb := StyleBoxFlat.new()
	sb.bg_color = base.darkened(0.55)
	sb.border_color = accent if playable else accent.darkened(0.55)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	# A soft coloured bloom instead of a hard drop shadow, so a hand of cards
	# reads as a warm fan rather than a stack of cut-outs.
	sb.shadow_color = Color(base.r, base.g, base.b, 0.35)
	sb.shadow_size = 9
	frame.add_theme_stylebox_override("panel", sb)

	var bsb := StyleBoxFlat.new()
	bsb.bg_color = base
	bsb.set_corner_radius_all(10)
	banner.add_theme_stylebox_override("panel", bsb)

	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.12, 0.12, 0.16)
	csb.border_color = accent
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(18)
	cost_badge.add_theme_stylebox_override("panel", csb)

	var asb := StyleBoxFlat.new()
	asb.bg_color = base.darkened(0.75)
	asb.border_color = base.darkened(0.35)
	asb.set_border_width_all(1)
	asb.set_corner_radius_all(10)
	art_panel.add_theme_stylebox_override("panel", asb)
	art_glyph.text = _glyph_for(ctype)
	art_glyph.modulate = accent.darkened(0.15)

	var display := card.display_name()
	name_label.text = display
	# Long names ("Master of Strategy", "Cloak and Dagger") need a smaller font to
	# fit the banner without being clipped.
	var name_size := 15
	if display.length() > 20:
		name_size = 11
	elif display.length() > 15:
		name_size = 12
	elif display.length() > 12:
		name_size = 13
	name_label.add_theme_font_size_override("font_size", name_size)
	name_label.modulate = Color(1, 0.95, 0.8) if card.upgraded else Color(1, 1, 1)

	var cst := card.cost(combat)
	if card.is_x_cost():
		cost_label.text = "X"
	elif cst == -2:
		cost_label.text = "—"
	else:
		cost_label.text = str(cst)
	if card.free_this_turn or (combat != null and cst < card.base_cost() and cst >= 0):
		cost_label.modulate = Color(0.5, 1.0, 0.6)
	else:
		cost_label.modulate = Color(1, 1, 1)

	type_label.text = card.kind_line()
	type_label.modulate = accent
	# A move's own type is the thing worth reading, so it gets the type colour.
	if card.is_pokemon_card():
		type_label.modulate = base.lightened(0.35)
		type_label.add_theme_font_size_override("font_size",
				9 if type_label.text.length() > 14 else 11)

	text_label.clear()
	text_label.push_color(Color(0.92, 0.92, 0.9))
	text_label.append_text(card.rules_text(combat))
	text_label.pop()

	_update_tooltip()
	modulate = Color(1, 1, 1) if playable else Color(0.62, 0.62, 0.66)
	if glow != null:
		glow.visible = selected
		if selected:
			var gsb := StyleBoxFlat.new()
			gsb.bg_color = Color(0, 0, 0, 0)
			gsb.border_color = Color(1, 0.92, 0.5)
			gsb.set_border_width_all(3)
			gsb.set_corner_radius_all(18)
			glow.add_theme_stylebox_override("panel", gsb)


func _glyph_for(ctype: String) -> String:
	match ctype:
		"attack": return "⚔"
		"skill": return "🛡"
		"power": return "✦"
		"status": return "≈"
		"curse": return "☠"
	return "•"


func set_playable(value: bool) -> void:
	if playable == value:
		return
	playable = value
	refresh()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	refresh()


func snap_home() -> void:
	position = home_position
	rotation = home_rotation
	scale = Vector2.ONE * home_scale


func tween_home(duration: float = 0.18) -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, "position", home_position, duration)
	t.tween_property(self, "rotation", home_rotation, duration)
	t.tween_property(self, "scale", Vector2.ONE * home_scale, duration)


func lift(amount: float = 42.0) -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, "position", home_position + Vector2(0, -amount), 0.12)
	t.tween_property(self, "rotation", 0.0, 0.12)
	t.tween_property(self, "scale", Vector2.ONE * (home_scale * 1.12), 0.12)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pressed.emit(self)
			accept_event()
		else:
			released.emit(self, get_global_mouse_position())
			accept_event()


func _on_mouse_entered() -> void:
	_hovering = true
	hover_changed.emit(self, true)


func _on_mouse_exited() -> void:
	_hovering = false
	hover_changed.emit(self, false)


## Hover text: the card face already shows the rules, so this just explains any
## keywords the card references.
func _update_tooltip() -> void:
	if card == null:
		return
	var lines: Array = ["%s — %s" % [card.display_name(), card.type().capitalize()]]
	var seen: Array = []
	for eff in card.effects():
		var sid := String(eff.get("id", ""))
		if sid == "" or seen.has(sid) or Statuses.is_hidden(sid):
			continue
		seen.append(sid)
		var stacks := 1
		var raw = eff.get("stacks", 1)
		if typeof(raw) == TYPE_STRING:
			stacks = int(card.raw_params().get(String(raw), 1))
		else:
			stacks = int(raw)
		lines.append(Statuses.describe(sid, absi(stacks)))
	tooltip_text = "\n".join(lines)
