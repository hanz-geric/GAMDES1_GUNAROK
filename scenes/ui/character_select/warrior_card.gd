class_name WarriorCard
extends Panel
## One portrait on the character select grid (supports Mortal & Lockable God Boss cards).

const BG := Color(0.055, 0.075, 0.14, 0.98)
const GOD_BG := Color(0.11, 0.07, 0.04, 0.98)
const GOD_LOCKED_BG := Color(0.04, 0.035, 0.06, 0.96)
const BORDER := Color(0.48, 0.34, 0.20)
const GOD_BORDER := Color(0.88, 0.68, 0.20)
const GOD_LOCKED_BORDER := Color(0.32, 0.26, 0.22)
const GOLD := Color(1.0, 0.80, 0.22)
const LOCKED_CURSOR := Color(0.95, 0.32, 0.24)
const P1_COLOR := Color(0.35, 0.75, 1.0)
const P2_COLOR := Color(1.0, 0.55, 0.2)

var warrior: WarriorData
var is_unlocked := true
var _style := StyleBoxFlat.new()
var _lock_badge: Label
var _god_tag: Label

@onready var rig: PlaceholderRig = $Rig
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var name_label: Label = $NameLabel
@onready var p1_marker: Label = $P1Marker
@onready var p2_marker: Label = $P2Marker


func _ready() -> void:
	_style.bg_color = BG
	_style.border_color = BORDER
	_style.set_border_width_all(3)
	_style.set_corner_radius_all(5)
	_style.shadow_color = Color(0, 0, 0, 0.50)
	_style.shadow_size = 5
	_style.shadow_offset = Vector2(2, 3)
	add_theme_stylebox_override("panel", _style)

	name_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.72))
	name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.08))
	name_label.add_theme_constant_override("outline_size", 4)

	p1_marker.add_theme_color_override("font_color", P1_COLOR)
	p2_marker.add_theme_color_override("font_color", P2_COLOR)
	p1_marker.add_theme_font_size_override("font_size", 16)
	p2_marker.add_theme_font_size_override("font_size", 16)

	_god_tag = Label.new()
	_god_tag.name = "GodTag"
	_god_tag.visible = false
	_god_tag.text = "GOD"
	_god_tag.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_god_tag.offset_top = 4.0
	_god_tag.offset_bottom = 22.0
	_god_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_god_tag.add_theme_font_size_override("font_size", 12)
	_god_tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_god_tag.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.02))
	_god_tag.add_theme_constant_override("outline_size", 4)
	add_child(_god_tag)

	_lock_badge = Label.new()
	_lock_badge.name = "LockBadge"
	_lock_badge.visible = false
	_lock_badge.text = "LOCKED\nDEFEAT IN ARCADE"
	_lock_badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_badge.offset_top = 20.0
	_lock_badge.offset_bottom = -28.0
	_lock_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lock_badge.add_theme_font_size_override("font_size", 13)
	_lock_badge.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	_lock_badge.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.05))
	_lock_badge.add_theme_constant_override("outline_size", 5)
	add_child(_lock_badge)


func setup(new_warrior: WarriorData, unlocked: bool = true) -> void:
	warrior = new_warrior
	is_unlocked = unlocked

	rig.setup(new_warrior, false, Color(0.06, 0.06, 0.08))
	rig.set_pose(&"idle", 0.0, false)
	if new_warrior.sprite_frames != null:
		sprite.sprite_frames = new_warrior.sprite_frames
		sprite.visible = true
		rig.visible = false
		if sprite.sprite_frames.has_animation(&"idle"):
			sprite.play(&"idle")
	else:
		sprite.visible = false
		rig.visible = true

	if new_warrior.is_boss:
		_god_tag.visible = true
		if is_unlocked:
			_style.bg_color = GOD_BG
			_style.border_color = GOD_BORDER
			name_label.text = new_warrior.display_name.to_upper()
			name_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42))
			sprite.modulate = Color.WHITE
			rig.modulate = Color.WHITE
			_lock_badge.visible = false
		else:
			_style.bg_color = GOD_LOCKED_BG
			_style.border_color = GOD_LOCKED_BORDER
			name_label.text = "???  (%s)" % new_warrior.display_name.to_upper()
			name_label.add_theme_color_override("font_color", Color(0.55, 0.50, 0.48))
			# Dramatic dark silhouette for locked Gods!
			sprite.modulate = Color(0.07, 0.06, 0.10, 0.88)
			sprite.pause()
			rig.modulate = Color(0.07, 0.06, 0.10, 0.88)
			_lock_badge.visible = true
	else:
		_god_tag.visible = false
		_lock_badge.visible = false
		_style.bg_color = BG
		_style.border_color = BORDER
		name_label.text = new_warrior.display_name.to_upper()
		sprite.modulate = Color.WHITE
		rig.modulate = Color.WHITE


## p1 and p2: 0 = not selected, 1 = cursor here, 2 = locked in
func set_cursor(p1: int, p2: int) -> void:
	p1_marker.visible = p1 > 0
	p2_marker.visible = p2 > 0
	p1_marker.text = "P1" if p1 == 1 else "P1 OK"
	p2_marker.text = "P2" if p2 == 1 else "P2 OK"

	var active := p1 > 0 or p2 > 0
	if active:
		_style.border_color = GOLD if is_unlocked else LOCKED_CURSOR
		_style.set_border_width_all(6)
	else:
		if warrior != null and warrior.is_boss:
			_style.border_color = GOD_BORDER if is_unlocked else GOD_LOCKED_BORDER
		else:
			_style.border_color = BORDER
		_style.set_border_width_all(3)

	if not is_unlocked:
		return

	var pose: StringName = &"victory" if (p1 == 2 or p2 == 2) else &"idle"
	rig.set_pose(pose, 0.0, false)
	if sprite.visible and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(pose):
		if sprite.animation != pose:
			sprite.play(pose)
