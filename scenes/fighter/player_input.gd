class_name PlayerInput
extends InputSource
## Reads the named Input Map actions p1_* or p2_* (GDD Section 8.3), so the
## keyboard keys and the gamepad alternates both work.

var player_index := 1
var _left: StringName
var _right: StringName
var _jump: StringName
var _crouch: StringName
var _punch: StringName
var _kick: StringName
var _block: StringName
var _special: StringName


func _init(index: int = 1) -> void:
	player_index = index
	var prefix := "p%d_" % index
	_left = StringName(prefix + "left")
	_right = StringName(prefix + "right")
	_jump = StringName(prefix + "jump")
	_crouch = StringName(prefix + "crouch")
	_punch = StringName(prefix + "punch")
	_kick = StringName(prefix + "kick")
	_block = StringName(prefix + "block")
	_special = StringName(prefix + "special")


func get_move_dir() -> int:
	return int(Input.is_action_pressed(_right)) - int(Input.is_action_pressed(_left))


func wants_jump() -> bool:
	return Input.is_action_pressed(_jump)


func wants_crouch() -> bool:
	return Input.is_action_pressed(_crouch)


func wants_block() -> bool:
	return Input.is_action_pressed(_block)


func consume_attack() -> StringName:
	if Input.is_action_just_pressed(_special):
		return &"special"
	if Input.is_action_just_pressed(_kick):
		return &"kick"
	if Input.is_action_just_pressed(_punch):
		return &"punch"
	return &""
