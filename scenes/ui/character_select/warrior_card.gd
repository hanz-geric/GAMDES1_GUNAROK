
class_name WarriorCard
extends Panel
## One portrait on the character select grid.

const BG := Color(0.055, 0.075, 0.14, 0.98)
const BORDER := Color(0.48, 0.34, 0.20)
const GOLD := Color(1.0, 0.72, 0.18)
const P1_COLOR := Color(0.35, 0.75, 1.0)
const P2_COLOR := Color(1.0, 0.55, 0.2)

var warrior: WarriorData
var _style := StyleBoxFlat.new()

@onready var rig: PlaceholderRig = $Rig
@onready var name_label: Label = $NameLabel
@onready var p1_marker: Label = $P1Marker
@onready var p2_marker: Label = $P2Marker


func _ready() -> void:
	# Card background and border.
	_style.bg_color = BG
	_style.border_color = BORDER
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(5)

	_style.shadow_color = Color(0, 0, 0, 0.45)
	_style.shadow_size = 4
	_style.shadow_offset = Vector2(2, 3)

	add_theme_stylebox_override("panel", _style)

	# Warrior name.
	name_label.add_theme_color_override(
		"font_color", Color(1.0, 0.91, 0.72)
	)
	name_label.add_theme_color_override(
		"font_outline_color", Color(0.05, 0.04, 0.08)
	)
	name_label.add_theme_constant_override("outline_size", 4)

	# Player markers.
	p1_marker.add_theme_color_override("font_color", P1_COLOR)
	p2_marker.add_theme_color_override("font_color", P2_COLOR)

	p1_marker.add_theme_font_size_override("font_size", 16)
	p2_marker.add_theme_font_size_override("font_size", 16)


func setup(new_warrior: WarriorData) -> void:
	warrior = new_warrior

	name_label.text = new_warrior.display_name.to_upper()

	rig.setup(
		new_warrior,
		false,
		Color(0.06, 0.06, 0.08)
	)

	rig.set_pose(&"idle", 0.0, false)


## p1 and p2:
## 0 = not selected
## 1 = cursor here
## 2 = locked in
func set_cursor(p1: int, p2: int) -> void:
	p1_marker.visible = p1 > 0
	p2_marker.visible = p2 > 0

	p1_marker.text = "P1" if p1 == 1 else "P1 OK"
	p2_marker.text = "P2" if p2 == 1 else "P2 OK"

	if p1 > 0 and p2 > 0:
		_style.border_color = GOLD
	elif p1 > 0:
		_style.border_color = GOLD
	elif p2 > 0:
		_style.border_color = GOLD
	else:
		_style.border_color = BORDER

	_style.set_border_width_all(
		6 if (p1 > 0 or p2 > 0) else 3
	)

	rig.set_pose(
		&"victory" if (p1 == 2 or p2 == 2) else &"idle",
		0.0,
		false
	)
