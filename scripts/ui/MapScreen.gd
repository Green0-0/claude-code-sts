extends Control

## The act map. Nodes are buttons; edges are Line2Ds drawn between them.

signal node_chosen(node_index: int)

const COL_W := 152.0
const ROW_H := 92.0
const NODE_SIZE := Vector2(56, 56)

@onready var scroll: ScrollContainer = $Scroll
@onready var canvas: Control = $Scroll/Canvas
@onready var act_label: Label = $ActLabel
@onready var hint_label: Label = $HintLabel

var _buttons: Dictionary = {}       ## node index -> Button


func refresh() -> void:
	for child in canvas.get_children():
		child.queue_free()
	_buttons.clear()

	var nodes: Array = Run.nodes()
	if nodes.is_empty():
		return
	var available: Array = Run.available_nodes()
	var rows: int = MapGen.ROWS + 1
	canvas.custom_minimum_size = Vector2(MapGen.COLS * COL_W + 120.0, rows * ROW_H + 90.0)

	# Edges first so they sit behind the buttons.
	for n in nodes:
		for nxt in n["next"]:
			var line := Line2D.new()
			line.width = 3.0
			var reachable: bool = Run.visited_nodes.has(int(n["id"])) \
					and available.has(int(nxt))
			line.default_color = Color(0.95, 0.85, 0.45, 0.95) if reachable \
					else Color(0.45, 0.45, 0.52, 0.55)
			line.add_point(_node_center(n))
			line.add_point(_node_center(nodes[int(nxt)]))
			canvas.add_child(line)

	for n in nodes:
		var idx := int(n["id"])
		var type_name := String(n["type"])
		var btn := Button.new()
		btn.text = MapGen.room_sigil(type_name)
		btn.custom_minimum_size = NODE_SIZE
		btn.size = NODE_SIZE
		btn.position = _node_center(n) - NODE_SIZE * 0.5
		btn.add_theme_font_size_override("font_size", 20)
		btn.tooltip_text = MapGen.room_label(type_name)
		btn.focus_mode = Control.FOCUS_NONE

		var is_available: bool = available.has(idx)
		var is_visited: bool = Run.visited_nodes.has(idx)
		var col: Color = MapGen.room_color(type_name)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(28)
		sb.set_border_width_all(3)
		if is_visited:
			sb.bg_color = col.darkened(0.6)
			sb.border_color = Color(1, 1, 1, 0.6)
		elif is_available:
			sb.bg_color = col.darkened(0.15)
			sb.border_color = Color(1, 0.95, 0.6)
		else:
			sb.bg_color = Color(0.16, 0.16, 0.20)
			sb.border_color = col.darkened(0.5)
		btn.add_theme_stylebox_override("normal", sb)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = sb.bg_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.add_theme_stylebox_override("disabled", sb)
		btn.disabled = not is_available
		if is_available:
			btn.pressed.connect(_on_node_pressed.bind(idx))
		canvas.add_child(btn)
		_buttons[idx] = btn

		if type_name == "boss":
			var lbl := Label.new()
			lbl.text = "BOSS"
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.add_theme_color_override("font_color", MapGen.room_color("boss"))
			lbl.position = btn.position + Vector2(-6, -26)
			canvas.add_child(lbl)

	act_label.text = "Act %d — Floor %d" % [Run.act, Run.floor_num]
	hint_label.text = "Choose your path." if not available.is_empty() \
			else "No paths remain."
	# Keep the player's current position in view.
	await get_tree().process_frame
	var focus_row: int = 0
	if Run.current_node >= 0:
		focus_row = int(Run.node_at(Run.current_node).get("row", 0))
	var target_y: float = canvas.custom_minimum_size.y - (focus_row + 3) * ROW_H
	scroll.scroll_vertical = int(clampf(target_y, 0.0,
			maxf(0.0, canvas.custom_minimum_size.y - scroll.size.y)))


func _node_center(n: Dictionary) -> Vector2:
	var row := int(n["row"])
	var col := int(n["col"])
	var rows: int = MapGen.ROWS + 1
	# Jitter keeps the map from looking like a perfect grid, seeded per node.
	var jitter_x := float((int(n["id"]) * 37) % 21) - 10.0
	return Vector2(60.0 + col * COL_W + jitter_x, (rows - row) * ROW_H)


func _on_node_pressed(idx: int) -> void:
	node_chosen.emit(idx)
