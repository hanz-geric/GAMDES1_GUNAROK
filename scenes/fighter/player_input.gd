class_name PlayerInput
extends InputSource
## Reads the named Input Map actions p1_* or p2_* once per 60 Hz tick into
## a single bit-field. Fight logic never reads the Input singleton directly
## (Design Plan v3 Section 13.3).

var player_index := 1
var _left: StringName
var _right: StringName
var _jump: StringName
var _crouch: StringName
var _light: StringName
var _heavy: StringName
var _seize: StringName
var _block: StringName
var _ultimate: StringName


func _init(index: int = 1) -> void:
	player_index = index
	var prefix := "p%d_" % index
	_left = StringName(prefix + "left")
	_right = StringName(prefix + "right")
	_jump = StringName(prefix + "jump")
	_crouch = StringName(prefix + "crouch")
	_light = StringName(prefix + "light")
	_heavy = StringName(prefix + "heavy")
	_seize = StringName(prefix + "seize")
	_block = StringName(prefix + "block")
	_ultimate = StringName(prefix + "ultimate")


func sample_bits() -> int:
	var bits := 0
	if Input.is_action_pressed(_left):
		bits |= LEFT
	if Input.is_action_pressed(_right):
		bits |= RIGHT
	if Input.is_action_pressed(_jump):
		bits |= UP
	if Input.is_action_pressed(_crouch):
		bits |= DOWN
	if Input.is_action_pressed(_light):
		bits |= LIGHT
	if Input.is_action_pressed(_heavy):
		bits |= HEAVY
	if Input.is_action_pressed(_seize):
		bits |= SEIZE
	if Input.is_action_pressed(_block):
		bits |= BLOCK
	if Input.is_action_pressed(_ultimate):
		bits |= ULTIMATE
	return bits
