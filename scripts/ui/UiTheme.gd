class_name UiTheme
extends RefCounted

## Builds the game's Theme in code and hands it to the Window, so every screen
## picks up the same panels, buttons and bars without per-node overrides.

const BG := Color(0.086, 0.086, 0.114)
const INK := Color(0.902, 0.902, 0.925)
const DIM := Color(0.62, 0.62, 0.69)
const GOLD := Color(0.945, 0.827, 0.400)
const BLOOD := Color(0.741, 0.239, 0.239)


static func _box(bg: Color, border: Color, radius: int = 8, width: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15

	# ── Panels ────────────────────────────────────────────────────────────────
	t.set_stylebox("panel", "Panel", _box(Color(0.106, 0.106, 0.137),
			Color(0.208, 0.208, 0.259)))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.106, 0.106, 0.137),
			Color(0.208, 0.208, 0.259)))

	# ── Buttons ───────────────────────────────────────────────────────────────
	var normal := _box(Color(0.145, 0.145, 0.184), Color(0.267, 0.267, 0.329))
	var hover := _box(Color(0.216, 0.216, 0.267), GOLD.darkened(0.35))
	var pressed := _box(Color(0.106, 0.106, 0.137), GOLD.darkened(0.15))
	var disabled := _box(Color(0.114, 0.114, 0.137), Color(0.184, 0.184, 0.216))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 0.96, 0.85))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.44, 0.44, 0.49))

	# ── Labels ────────────────────────────────────────────────────────────────
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)

	# ── Health / progress bars ───────────────────────────────────────────────
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.129, 0.114, 0.125)
	bar_bg.border_color = Color(0.29, 0.24, 0.25)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(5)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = BLOOD
	bar_fill.set_corner_radius_all(5)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", INK)

	# ── Text entry ────────────────────────────────────────────────────────────
	t.set_stylebox("normal", "LineEdit", _box(Color(0.078, 0.078, 0.102),
			Color(0.243, 0.243, 0.29), 6, 1))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.078, 0.078, 0.102),
			GOLD.darkened(0.3), 6, 1))
	t.set_color("font_color", "LineEdit", INK)

	# ── Scrolling ─────────────────────────────────────────────────────────────
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.32, 0.32, 0.38)
	grabber.set_corner_radius_all(4)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.12, 0.15)
	track.set_corner_radius_all(4)
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, track)
		t.set_stylebox("grabber", cls, grabber)
		t.set_stylebox("grabber_highlight", cls, grabber)
		t.set_stylebox("grabber_pressed", cls, grabber)
	return t


## Health bars are styled per-node as well as in the theme, because a ProgressBar
## inside another styled control does not always inherit the theme's fill.
static func style_hp_bar(bar: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.153, 0.106, 0.114)
	bg.border_color = Color(0.35, 0.24, 0.26)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BLOOD
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


## A round, gold-rimmed panel for the energy orb.
static func orb_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.15, 0.09)
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(48)
	return sb


## The player's portrait panel.
static func player_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.12, 0.16)
	sb.border_color = Color(0.36, 0.32, 0.42)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	return sb
