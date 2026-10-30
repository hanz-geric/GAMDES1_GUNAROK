class_name Balance
extends RefCounted
## Every tuning number from GDD Sections II and VI lives here, so changes
## after a playtest happen in one place (GDD Section 8.4, risk 5 in XI).

# Arena (GDD Section II Boundaries, Section 8.2 Camera)
const ARENA_WIDTH := 1600.0
const WALL_THICKNESS := 40.0
const FLOOR_Y := 620.0
const SCREEN_WIDTH := 1280.0
const MAX_SEPARATION := 1120.0 # screen width minus a 160 px margin
const SPAWN_OFFSET := 230.0 # fighters spawn at mid-distance
const BODY_HALF_WIDTH := 28.0

# Rounds (GDD Section II Rules and Outcome)
const START_HEALTH := 100
const ROUND_TIME := 60
const ROUNDS_TO_WIN := 2
const MAX_DRAW_REPLAYS := 2
const INTRO_CARD_TIME := 2.0
const BANNER_TIME := 1.6
const ROUND_END_TIME := 2.4

# Special meter
const METER_MAX := 100.0
const SPECIAL_COST := 50.0
const METER_PER_DAMAGE_DEALT := 0.5
const METER_PER_DAMAGE_TAKEN := 1.0

# Damage. Base damage is multiplied by the warrior's damage rating.
const CHIP_RATIO := 0.25
const DAMAGE_BY_RATING := [0.85, 0.92, 1.0, 1.08, 1.15]

## Frame data for the shared move template (startup, active, recovery in
## seconds). Height: high misses crouching, low misses jumping, mid hits all.
const ATTACKS := {
	&"punch": {"base_damage": 6.0, "startup": 0.10, "active": 0.08, "recovery": 0.16,
			"height": &"high", "hitstun": 0.30, "reach_scale": 1.0},
	&"kick": {"base_damage": 10.0, "startup": 0.16, "active": 0.10, "recovery": 0.24,
			"height": &"low", "hitstun": 0.38, "reach_scale": 1.15},
	&"special": {"base_damage": 22.0, "startup": 0.30, "active": 0.14, "recovery": 0.42,
			"height": &"mid", "hitstun": 0.0, "reach_scale": 1.5},
}

# Movement (reach and speed come from the warrior's ratings)
const WALK_SPEED_BASE := 170.0
const WALK_SPEED_PER_RATING := 30.0
const BACKWALK_SCALE := 0.8
const REACH_BASE := 40.0
const REACH_PER_RATING := 12.0
const TIMING_SCALE_BY_SPEED := [1.12, 1.06, 1.0, 0.94, 0.88]
const GRAVITY := 2600.0
const JUMP_VELOCITY := -980.0
const JUMP_FORWARD_SPEED := 240.0
const SPECIAL_LUNGE_SPEED := 200.0
const KNOCKDOWN_TIME := 0.75
const GETUP_TIME := 0.45
const HIT_PUSHBACK := 260.0
const BLOCK_PUSHBACK := 200.0
const KNOCKDOWN_LAUNCH := Vector2(320.0, -420.0)

# Arcade (GDD Sections 6.1 and II Outcome)
const ARCADE_CONTINUES := 3
const SCORE_MATCH_WIN := 1000
const SCORE_PER_HEALTH := 10
const SCORE_PERFECT := 500
