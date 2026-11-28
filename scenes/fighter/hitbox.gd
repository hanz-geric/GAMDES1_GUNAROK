class_name Hitbox
extends RefCounted
## Pure box-math attack hitbox (no Area2D physics dependency,
## Design Plan v3 Section 13.3). Evaluated symmetrically by Match each 60 Hz tick.

## Vertical centre (offset from feet y = 0) and vertical height per attack height.
const HEIGHT_Y := {
	&"high": -136.0,
	&"mid": -125.0,
	&"low": -44.0,
	&"anti_air": -168.0,
	&"grab": -95.0,
}
const HEIGHT_SIZE := {
	&"high": 62.0,
	&"mid": 210.0,
	&"low": 64.0,
	&"anti_air": 190.0,
	&"grab": 135.0,
}
## Slight inner overlap from fighter centre so point-blank hits never whiff.
const INNER_OFFSET := 8.0

var active := false
var has_hit := false
var attack_name: StringName = &""
var height: StringName = &"high"
var facing := 1
var length := 64.0
var damage := 0.0
var parriable := true
var is_grab := false
var knockdown := false
var launcher := false
var hitstun_frames := 0
var hitstop_frames := Balance.HITSTOP_LIGHT
var meter_gain := 0.0
var chip_ratio := Balance.CHIP_RATIO


func prepare(
	move_name: StringName,
	move_height: StringName,
	dir: int,
	reach: float,
	move_damage: float,
	move_parriable: bool,
	move_is_grab: bool,
	move_knockdown: bool,
	move_launcher: bool,
	move_hitstun: int,
	move_hitstop: int,
	move_meter_gain: float,
	move_chip_ratio: float
) -> void:
	attack_name = move_name
	height = move_height
	facing = dir
	length = reach
	damage = move_damage
	parriable = move_parriable
	is_grab = move_is_grab
	knockdown = move_knockdown
	launcher = move_launcher
	hitstun_frames = move_hitstun
	hitstop_frames = move_hitstop
	meter_gain = move_meter_gain
	chip_ratio = move_chip_ratio
	active = false
	has_hit = false


func activate() -> void:
	active = true
	has_hit = false


func deactivate() -> void:
	active = false


func get_rect(origin: Vector2) -> Rect2:
	var size_y: float = HEIGHT_SIZE[height]
	var centre_y: float = HEIGHT_Y[height]
	var span := (Balance.BODY_HALF_WIDTH - INNER_OFFSET) + length
	var left := origin.x + INNER_OFFSET if facing >= 0 else origin.x - INNER_OFFSET - span
	return Rect2(left, origin.y + centre_y - size_y * 0.5, span, size_y)


func export_state() -> Dictionary:
	return {
		"active": active,
		"has_hit": has_hit,
		"attack_name": attack_name,
		"height": height,
		"facing": facing,
		"length": length,
		"damage": damage,
		"parriable": parriable,
		"is_grab": is_grab,
		"knockdown": knockdown,
		"launcher": launcher,
		"hitstun_frames": hitstun_frames,
		"hitstop_frames": hitstop_frames,
		"meter_gain": meter_gain,
		"chip_ratio": chip_ratio,
	}


func import_state(data: Dictionary) -> void:
	active = data["active"]
	has_hit = data["has_hit"]
	attack_name = data["attack_name"]
	height = data["height"]
	facing = data["facing"]
	length = data["length"]
	damage = data["damage"]
	parriable = data["parriable"]
	is_grab = data["is_grab"]
	knockdown = data["knockdown"]
	launcher = data["launcher"]
	hitstun_frames = data["hitstun_frames"]
	hitstop_frames = data["hitstop_frames"]
	meter_gain = data["meter_gain"]
	chip_ratio = data["chip_ratio"]
