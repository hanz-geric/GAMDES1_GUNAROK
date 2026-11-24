
class_name UiStyle
extends RefCounted

const GOLD := Color(1.0, 0.82, 0.3)

const BUTTON_SIZE := Vector2(380, 58)

const ARCADE_TEXTURE: Texture2D = preload(
    "res://assets/ui/buttons/arcade_button_pixel.png"
)

const VERSUS_TEXTURE: Texture2D = preload(
    "res://assets/ui/buttons/versus_button_pixel.png"
)

const QUIT_TEXTURE: Texture2D = preload(
    "res://assets/ui/buttons/quit_button_pixel.png"
)


static func style_button(button: Button, font_size: int = 26) -> void:
	var texture: Texture2D

	match button.name:
		"ArcadeButton":
			texture = ARCADE_TEXTURE

		"VersusButton":
			texture = VERSUS_TEXTURE

		"QuitButton":
			texture = QUIT_TEXTURE

		_:
			return

	# PNG already contains the text.
	button.text = ""

	# All buttons have exactly the same dimensions.
	button.custom_minimum_size = BUTTON_SIZE
	button.size = BUTTON_SIZE

	# Center the buttons.
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Normal state.
	button.add_theme_stylebox_override(
		"normal",
		_make_box(texture, Color.WHITE)
	)

	# Hover state.
	button.add_theme_stylebox_override(
		"hover",
		_make_box(texture, Color(1.1, 1.1, 1.1))
	)

	# Pressed state.
	button.add_theme_stylebox_override(
		"pressed",
		_make_box(texture, Color(0.85, 0.85, 0.85))
	)

	# Focus state.
	button.add_theme_stylebox_override(
		"focus",
		_make_box(texture, Color.WHITE)
	)

	# Disabled state.
	button.add_theme_stylebox_override(
		"disabled",
		_make_box(texture, Color(0.5, 0.5, 0.5))
	)


static func _make_box(
	texture: Texture2D,
	tint: Color
) -> StyleBoxTexture:

	var box := StyleBoxTexture.new()

	box.texture = texture
	box.modulate_color = tint

	return box
