extends Control

## Campfire: rest to heal, or smith to upgrade a card.

signal smith_requested
signal finished

@onready var rest_button: Button = $Options/RestButton
@onready var smith_button: Button = $Options/SmithButton
@onready var leave_button: Button = $Options/LeaveButton
@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	rest_button.pressed.connect(_on_rest)
	smith_button.pressed.connect(func(): smith_requested.emit())
	leave_button.pressed.connect(func(): finished.emit())


func refresh() -> void:
	var heal_amount := int(round(Run.max_hp * 0.30))
	rest_button.text = "Rest — heal %d HP" % heal_amount
	rest_button.disabled = Run.hp >= Run.max_hp
	smith_button.disabled = Run.upgradable_cards().is_empty()
	leave_button.visible = false
	status_label.text = "You are at %d / %d HP." % [Run.hp, Run.max_hp]


func _on_rest() -> void:
	Run.heal(int(round(Run.max_hp * 0.30)))
	status_label.text = "You rest. HP is now %d / %d." % [Run.hp, Run.max_hp]
	_lock()


func on_smith_done(card_name: String) -> void:
	status_label.text = "%s is sharpened." % card_name
	_lock()


func _lock() -> void:
	rest_button.disabled = true
	smith_button.disabled = true
	leave_button.visible = true
	leave_button.text = "Leave"
