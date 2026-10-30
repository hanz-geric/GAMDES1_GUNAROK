class_name WarriorCard
extends Panel
## One portrait on the character select grid.

const BG := Color(0.1, 0.08, 0.14, 0.95)
const BORDER := Color(0.35, 0.3, 0.26)
const P1_COLOR := Color(0.35, 0.75, 1.0)
const P2_COLOR := Color(1.0, 0.55, 0.2)

var warrior: WarriorData
var _style := StyleBoxFlat.new()

@onready var rig: PlaceholderRig = $Rig
@onready var name_label: Label = $NameLabel
@onready var p1_marker: Label = $P1Marker
@onready var p2_marker: Label = $P2Marker


func _ready() -> void:
	_style.bg_color = BG
	_style.border_color = BORDER
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", _style)
	p1_marker.add_theme_color_override("font_color", P1_COLOR)
	p2_marker.add_theme_color_override("font_color", P2_COLOR)


func setup(new_warrior: WarriorData) -> void:
	warrior = new_warrior
	name_label.text = new_warrior.display_name.to_upper()
	rig.setup(new_warrior, false, Color(0.06, 0.06, 0.08))
	rig.set_pose(&"idle", 0.0, false)


## p1 and p2 are 0 (not here), 1 (cursor here) or 2 (locked in here).
func set_cursor(p1: int, p2: int) -> void:
	p1_marker.visible = p1 > 0
	p2_marker.visible = p2 > 0
	p1_marker.text = "P1" if p1 == 1 else "P1 OK"
	p2_marker.text = "P2" if p2 == 1 else "P2 OK"
	if p1 > 0 and p2 > 0:
		_style.border_color = Color(1.0, 0.82, 0.3)
	elif p1 > 0:
		_style.border_color = P1_COLOR
	elif p2 > 0:
		_style.border_color = P2_COLOR
	else:
		_style.border_color = BORDER
	_style.set_border_width_all(6 if (p1 > 0 or p2 > 0) else 3)
	rig.set_pose(&"victory" if (p1 == 2 or p2 == 2) else &"idle", 0.0, false)
