class_name Match
extends Node2D
## One best-of-three match (GDD Figure 5). Builds the stage, sets up both
## fighters and wires the signals listed in GDD Section 8.5.

var stage: Stage

@onready var fighter1: Fighter = $Fighter1
@onready var fighter2: Fighter = $Fighter2
@onready var effects: Node2D = $Effects
@onready var camera_rig: CameraRig = $CameraRig
@onready var round_manager: RoundManager = $RoundManager
@onready var hud: Hud = $HUD


func _ready() -> void:
	# Run after both fighters have moved, so the push box sees this frame.
	process_physics_priority = 10
	GameState.match_started.connect(_on_match_started)


func _exit_tree() -> void:
	if GameState.match_started.is_connected(_on_match_started):
		GameState.match_started.disconnect(_on_match_started)


## Connected to GameState.match_started (GDD 8.5).
func _on_match_started(stage_id: StringName, p1: WarriorData, opponent: WarriorData) -> void:
	_build_stage(stage_id)
	var tier: CpuTier = GameState.current_cpu_tier()
	fighter1.setup(1, p1, PlayerInput.new(1), null, false)
	if GameState.is_arcade():
		fighter2.setup(2, opponent, CpuBrain.new(tier), tier, false)
	else:
		# Same warrior on both sides: Player 2 gets the alternate palette (GDD 8.2).
		fighter2.setup(2, opponent, PlayerInput.new(2), null, p1 == opponent)
	fighter1.opponent = fighter2
	fighter2.opponent = fighter1
	var centre := stage.arena_width * 0.5
	fighter1.spawn_position = Vector2(centre - Balance.SPAWN_OFFSET, Balance.FLOOR_Y)
	fighter2.spawn_position = Vector2(centre + Balance.SPAWN_OFFSET, Balance.FLOOR_Y)
	for fighter in [fighter1, fighter2]:
		fighter.global_position = fighter.spawn_position
		fighter.effects_layer = effects
	_wire_signals()
	camera_rig.follow(fighter1, fighter2, stage.arena_width)
	AudioManager.play_music(stage.music)
	round_manager.start_match(fighter1, fighter2)


func _build_stage(stage_id: StringName) -> void:
	var path: String = GameState.STAGES[stage_id]["scene"]
	var scene: PackedScene = load(path)
	stage = scene.instantiate() as Stage
	stage.name = "Stage"
	add_child(stage)
	move_child(stage, 0)
	stage.configure(GameState.ladder_step if GameState.is_arcade() else 0)


func _wire_signals() -> void:
	# hit_landed: Hitbox -> defending Fighter, HUD
	fighter1.hitbox.hit_landed.connect(fighter2._on_hit_landed)
	fighter2.hitbox.hit_landed.connect(fighter1._on_hit_landed)
	fighter1.hitbox.hit_landed.connect(hud._on_hit_landed)
	fighter2.hitbox.hit_landed.connect(hud._on_hit_landed)
	for fighter in [fighter1, fighter2]:
		# health_changed, meter_changed: Fighter -> HUD, RoundManager
		fighter.health_changed.connect(hud._on_health_changed)
		fighter.health_changed.connect(round_manager._on_health_changed)
		fighter.meter_changed.connect(hud._on_meter_changed)
		# round_started: RoundManager -> Fighters (and HUD, RoundTimer below)
		round_manager.round_started.connect(fighter._on_round_started)
	round_manager.round_started.connect(hud._on_round_started)
	# time_changed, time_up: RoundTimer -> HUD, RoundManager
	round_manager.round_timer.time_changed.connect(hud._on_time_changed)
	# round_ended: RoundManager -> HUD, Match, GameState
	round_manager.round_ended.connect(hud._on_round_ended)
	round_manager.round_ended.connect(_on_round_ended)
	round_manager.round_ended.connect(GameState.on_round_ended)
	# match_ended: RoundManager -> GameState (which opens the ResultScreen)
	round_manager.match_ended.connect(GameState.on_match_ended)


## Connected to RoundManager.round_ended: freeze both fighters.
func _on_round_ended(_winner: int, _reason: StringName) -> void:
	for fighter in [fighter1, fighter2]:
		fighter.set_input_enabled(false)


func _physics_process(_delta: float) -> void:
	if stage == null:
		return
	_resolve_push_box()
	_limit_separation()


## Grounded fighters cannot overlap; a jumping fighter can cross over the
## other one, which is how a cornered player escapes (GDD 5.4).
func _resolve_push_box() -> void:
	var dx := fighter2.global_position.x - fighter1.global_position.x
	var dy := absf(fighter2.global_position.y - fighter1.global_position.y)
	var min_gap := Balance.BODY_HALF_WIDTH * 2.0
	if absf(dx) >= min_gap or dy > 120.0:
		return
	var direction := 1.0 if dx > 0.0 else -1.0
	if is_zero_approx(dx):
		direction = float(fighter1.facing)
	var push := (min_gap - absf(dx)) * 0.5
	var moved1 := fighter1.nudge(-direction * push)
	var moved2 := fighter2.nudge(direction * push)
	var leftover := push * 2.0 - absf(moved1) - absf(moved2)
	if leftover > 0.01:
		if absf(moved1) < push:
			fighter2.nudge(direction * leftover)
		else:
			fighter1.nudge(-direction * leftover)


## Fighters can never be further apart than the screen allows (GDD 8.2).
func _limit_separation() -> void:
	var dx := fighter2.global_position.x - fighter1.global_position.x
	var excess := absf(dx) - Balance.MAX_SEPARATION
	if excess <= 0.0:
		return
	var direction := 1.0 if dx > 0.0 else -1.0
	fighter1.nudge(direction * excess * 0.5)
	fighter2.nudge(-direction * excess * 0.5)
