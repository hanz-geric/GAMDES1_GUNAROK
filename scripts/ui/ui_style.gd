class_name UiStyle
extends RefCounted
## Shared look for menu buttons. A focused button gets a thick gold border,
## so keyboard and gamepad users always see where they are (GDD Section IX).

const BG := Color(0.1, 0.08, 0.14, 0.92)
const BG_HOVER := Color(0.18, 0.14, 0.24, 0.95)
const BORDER := Color(0.55, 0.48, 0.38)
const GOLD := Color(1.0, 0.82, 0.3)


static func style_button(button: Button, font_size: int = 26) -> void:
	button.add_theme_stylebox_override("normal", _box(BG, BORDER, 2))
	button.add_theme_stylebox_override("hover", _box(BG_HOVER, BORDER, 2))
	button.add_theme_stylebox_override("pressed", _box(BG_HOVER, GOLD, 3))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), GOLD, 4))
	button.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.08, 0.08, 0.8), Color(0.3, 0.3, 0.3), 2))
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	button.add_theme_color_override("font_focus_color", GOLD)
	button.add_theme_color_override("font_hover_color", Color.WHITE)


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box
