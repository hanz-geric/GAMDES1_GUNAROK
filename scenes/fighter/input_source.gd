class_name InputSource
extends Node
## Base class for whatever drives a Fighter: a human (PlayerInput), the CPU
## (CpuBrain), or a future network peer. Reads inputs once per 60 Hz tick into
## a compact bit-field (Design Plan v3 Section 13.3).

const LEFT := 1 << 0
const RIGHT := 1 << 1
const UP := 1 << 2
const DOWN := 1 << 3
const LIGHT := 1 << 4
const HEAVY := 1 << 5
const SEIZE := 1 << 6
const BLOCK := 1 << 7
const ULTIMATE := 1 << 8

var fighter: Fighter


## Called once per 60 Hz simulation tick before the fighter steps.
## Returns a bitmask of InputSource.* flags.
func sample_bits() -> int:
	return 0


## Called at the start of every round.
func reset_for_round(_round_no: int) -> void:
	pass
