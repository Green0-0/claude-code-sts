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
var _can_cancel: bool = true        ## false for prompts that must be answered
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
	_can_cancel = can_cancel
	_combat = combat
	_selection.clear()
	title_label.text = title
	# Detach before freeing: queue_free() is deferred, so leaving the old cards
	# parented would let the grid lay the new batch out after the stale ones.
	for v in _views:
		if v.get_parent() != null:
			v.get_parent().remove_child(v)
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
			if not can_cancel:
				name_hint.text += "  This choice cannot be skipped."
		"instant":
			name_hint.text = "Click a card to choose it."
			if not can_cancel:
				name_hint.text += "  This choice cannot be skipped."
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
	# A mandatory prompt (a forced discard, exhaust, upgrade …) cannot be waived.
	# Dismissing it would leave the combat waiting on a choice with nothing on
	# screen to answer it, which locks the run.
	if not _can_cancel:
		return
	visible = false
	cancelled.emit()


## Escape and other "just close it" gestures route through here so they respect
## whether this particular prompt is dismissable.
func request_close() -> bool:
	if not _can_cancel:
		return false
	_on_cancel()
	return true


func close() -> void:
	visible = false
