class_name Stage
extends Node2D
## A fixed-width arena with solid walls on both sides and no hazards
## (GDD Section II Boundaries). Stage art also carries the setting (GDD 7.2).

@export var stage_name := "Stage"
@export var music: StringName = &"ancient_arena"
@export var arena_width := 1600.0


## Called by Match before the fight. ladder_step is 0 for M1 to 5 for M6.
func configure(_ladder_step: int) -> void:
	pass
