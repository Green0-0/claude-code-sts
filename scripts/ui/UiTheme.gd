class_name UiTheme
extends RefCounted

## Builds the game's Theme in code and hands it to the Window, so every screen
## picks up the same panels, buttons and bars without per-node overrides.

## A softer palette than a dungeon crawler usually wears: the greys carry a
## little violet so they read as dusk rather than as soot, and the accents are
## pastel. Sprites are bright pixel art and sit better against warm dark than
## against neutral black.
const BG := Color(0.098, 0.090, 0.137)
const INK := Color(0.937, 0.925, 0.961)
const DIM := Color(0.655, 0.639, 0.729)
const GOLD := Color(0.980, 0.851, 0.502)
const BLOOD := Color(0.906, 0.435, 0.522)
const MINT := Color(0.545, 0.867, 0.749)
const PANEL := Color(0.145, 0.133, 0.192)
const PANEL_EDGE := Color(0.278, 0.255, 0.353)

## Corners are generously rounded throughout — it is the cheapest and most
## reliable way to make a UI read as friendly rather than severe.
const RADIUS := 14


static func _box(bg: Color, border: Color, radius: int = RADIUS, width: int = 2) -> StyleBoxFlat:
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
	t.set_stylebox("panel", "Panel", _box(PANEL, PANEL_EDGE))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, PANEL_EDGE))

	# ── Buttons ───────────────────────────────────────────────────────────────
	var normal := _box(Color(0.192, 0.176, 0.251), Color(0.318, 0.294, 0.404), 12)
	var hover := _box(Color(0.263, 0.239, 0.341), GOLD.darkened(0.2), 12)
	var pressed := _box(Color(0.153, 0.141, 0.208), GOLD, 12)
	var disabled := _box(Color(0.137, 0.129, 0.176), Color(0.208, 0.196, 0.251), 12)
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
	bar_bg.bg_color = Color(0.180, 0.145, 0.196)
	bar_bg.border_color = Color(0.361, 0.294, 0.396)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(8)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = BLOOD
	bar_fill.set_corner_radius_all(8)
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
	grabber.bg_color = Color(0.400, 0.373, 0.494)
	grabber.set_corner_radius_all(6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.153, 0.141, 0.196)
	track.set_corner_radius_all(6)
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
	bg.bg_color = Color(0.180, 0.145, 0.196)
	bg.border_color = Color(0.361, 0.294, 0.396)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = BLOOD
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


## A round, gold-rimmed panel for the energy orb.
static func orb_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.239, 0.196, 0.129)
	sb.border_color = GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(48)
	sb.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.25)
	sb.shadow_size = 8
	return sb


## The player's portrait panel.
static func player_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.169, 0.153, 0.224)
	sb.border_color = Color(0.404, 0.365, 0.482)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(RADIUS)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	return sb
