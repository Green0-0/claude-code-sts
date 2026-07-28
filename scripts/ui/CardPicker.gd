extends Control

## Modal card grid. Used for viewing piles and for every "choose a card" prompt.

signal confirmed(cards: Array)
signal cancelled

const CARD_SCENE := preload("res://scenes/CardView.tscn")

@onready var title_label: Label = $Panel/TitleLabel
@onready var name_hint: Label = $Panel/HintLabel
@onready var grid: GridContainer = $Panel/Scroll/CenterBox/Grid
@onready var confirm_button: Button = $Panel/Buttons/ConfirmButton
@onready var cancel_button: Button = $Panel/Buttons/CancelButton

var _mode: String = "view"          ## view | select | instant
var _needed: int = 1
var _selection: Array = []
var _views: Array = []
var _combat = null


func _ready() -> void:
	visible = false
	confirm_button.pressed.connect(_on_confirm)
	cancel_button.pressed.connect(_on_cancel)


func open_view(title: String, cards: Array, combat = null) -> void:
	_setup(title, cards, "view", 0, combat, true)


func open_select(title: String, cards: Array, count: int, combat = null,
		can_cancel: bool = false) -> void:
	_setup(title, cards, "select", count, combat, can_cancel)


func open_instant(title: String, cards: Array, combat = null,
		can_cancel: bool = true) -> void:
	_setup(title, cards, "instant", 1, combat, can_cancel)


func _setup(title: String, cards: Array, mode: String, count: int, combat,
		can_cancel: bool) -> void:
	_mode = mode
	_needed = count
	_combat = combat
	_selection.clear()
	title_label.text = title
	for v in _views:
		v.queue_free()
	_views.clear()
	for c in cards:
		var view: CardView = CARD_SCENE.instantiate()
		grid.add_child(view)
		view.setup(c, combat)
		view.pressed.connect(_on_card_pressed)
		_views.append(view)
	confirm_button.visible = mode == "select"
	confirm_button.disabled = mode == "select" and count > 0
	cancel_button.visible = can_cancel
	cancel_button.text = "Close" if mode == "view" else "Cancel"
	match mode:
		"view":
			name_hint.text = "%d card(s)." % cards.size()
		"select":
			name_hint.text = "Select %d card(s)." % count
		"instant":
			name_hint.text = "Click a card to choose it."
	visible = true
	move_to_front()


func _on_card_pressed(view: CardView) -> void:
	match _mode:
		"view":
			return
		"instant":
			visible = false
			confirmed.emit([view.card])
		"select":
			if _selection.has(view.card):
				_selection.erase(view.card)
				view.set_selected(false)
			elif _selection.size() < _needed:
				_selection.append(view.card)
				view.set_selected(true)
			confirm_button.disabled = _selection.size() != _needed
			name_hint.text = "Selected %d / %d." % [_selection.size(), _needed]


func _on_confirm() -> void:
	visible = false
	confirmed.emit(_selection.duplicate())


func _on_cancel() -> void:
	visible = false
	cancelled.emit()


func close() -> void:
	visible = false
