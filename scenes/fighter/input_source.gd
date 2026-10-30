class_name InputSource
extends Node
## Base class for whatever drives a Fighter: a person (PlayerInput) or the
## CPU (CpuBrain). Fighter.tscn is reused for both (GDD Section 8.4).

var fighter: Fighter


## Called by the fighter at the start of each physics frame.
func tick(_delta: float) -> void:
	pass


func get_move_dir() -> int:
	return 0


func wants_jump() -> bool:
	return false


func wants_crouch() -> bool:
	return false


func wants_block() -> bool:
	return false


## Returns &"punch", &"kick", &"special" or &"" for this physics frame.
func consume_attack() -> StringName:
	return &""


## Called at the start of every round.
func reset_for_round(_round_no: int) -> void:
	pass
