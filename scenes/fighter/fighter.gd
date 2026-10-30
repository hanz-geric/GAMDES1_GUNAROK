class_name Fighter
extends CharacterBody2D
## One fighter. The same scene is used for Player 1, Player 2, every CPU
## rival and Zeus; only the InputSource child and the WarriorData change
## (GDD Section 8.4). Rules follow GDD Section II.

signal health_changed(fighter: Fighter, value: float)
signal meter_changed(fighter: Fighter, value: float)

enum Phase { NONE, STARTUP, ACTIVE, RECOVERY }

const P1_COLOR := Color(0.35, 0.75, 1.0)
const P2_COLOR := Color(1.0, 0.55, 0.2)
const HIT_SPARK_SCENE := preload("res://scenes/effects/hit_spark.tscn")
const SOUNDS := {
	&"whoosh_punch": preload("res://assets/audio/sfx/whoosh_punch.wav"),
	&"whoosh_kick": preload("res://assets/audio/sfx/whoosh_kick.wav"),
	&"whoosh_special": preload("res://assets/audio/sfx/whoosh_special.wav"),
	&"hit_light": preload("res://assets/audio/sfx/hit_light.wav"),
	&"hit_heavy": preload("res://assets/audio/sfx/hit_heavy.wav"),
	&"hit_special": preload("res://assets/audio/sfx/hit_special.wav"),
	&"block": preload("res://assets/audio/sfx/block.wav"),
	&"jump": preload("res://assets/audio/sfx/jump.wav"),
	&"knockdown": preload("res://assets/audio/sfx/knockdown.wav"),
	&"thunder": preload("res://assets/audio/sfx/thunder.wav"),
	&"rifle": preload("res://assets/audio/sfx/rifle.wav"),
}

var player_index := 1
var data: WarriorData
var cpu_tier: CpuTier
var input_source: InputSource
var opponent: Fighter
var effects_layer: Node2D
var spawn_position := Vector2.ZERO

var max_health := 100.0
var health := 100.0
var meter := 0.0
var facing := 1
var input_enabled := false

var attack_name: StringName = &""
var attack_phase: Phase = Phase.NONE
## Goes up by one with every attack, so the CPU can tell attacks apart.
var attack_serial := 0
var match_damage_dealt := 0.0
var last_hit_msec := -1

var _phase_time := 0.0
var _stun_time := 0.0
var _damage_multiplier := 1.0
var _timing_scale := 1.0
var _windup_scale := 1.0

@onready var state_machine: StateMachine = $StateMachine
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var rig: PlaceholderRig = $PlaceholderRig
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var tag_label: Label = $TagLabel
@onready var audio: AudioStreamPlayer2D = $AudioStreamPlayer2D


func setup(index: int, warrior: WarriorData, source: InputSource, tier: CpuTier, alt_palette: bool) -> void:
	player_index = index
	data = warrior
	cpu_tier = tier
	if input_source != null:
		input_source.queue_free()
	input_source = source
	input_source.name = "InputSource"
	input_source.fighter = self
	add_child(input_source)

	max_health = float(warrior.max_health)
	_damage_multiplier = warrior.damage_multiplier()
	_timing_scale = warrior.timing_scale()
	_windup_scale = 1.0
	if tier != null:
		max_health = float(tier.health)
		_damage_multiplier *= tier.damage_multiplier
		_windup_scale = tier.windup_scale

	var color := P1_COLOR if index == 1 else P2_COLOR
	rig.setup(warrior, alt_palette, color.darkened(0.55))
	if warrior.sprite_frames != null:
		sprite.sprite_frames = warrior.sprite_frames
		sprite.visible = true
		rig.visible = false
	else:
		sprite.visible = false
		rig.visible = true
	if source is CpuBrain:
		tag_label.text = "CPU"
	else:
		tag_label.text = "P%d" % index
	tag_label.add_theme_color_override("font_color", color)
	health = max_health
	meter = 0.0
	match_damage_dealt = 0.0
	last_hit_msec = -1


## Connected to RoundManager.round_started (GDD 8.5): health back to full,
## fighters back to mid-distance. Meter carries over.
func _on_round_started(round_no: int) -> void:
	health = max_health
	global_position = spawn_position
	velocity = Vector2.ZERO
	input_enabled = false
	_cancel_attack()
	hurtbox.set_crouching(false)
	state_machine.force(StateMachine.State.IDLE)
	input_source.reset_for_round(round_no)
	_face_opponent()
	health_changed.emit(self, health)
	meter_changed.emit(self, meter)


## Connected to the opponent's Hitbox.hit_landed (GDD 8.5).
func _on_hit_landed(attacker: Fighter, defender: Fighter, damage: float, blocked: bool) -> void:
	if defender != self:
		return
	var attack := attacker.attack_name
	var away := 1.0 if global_position.x >= attacker.global_position.x else -1.0
	health = maxf(health - damage, 0.0)
	attacker.register_damage_dealt(damage)
	add_meter(damage * Balance.METER_PER_DAMAGE_TAKEN)
	_spawn_spark(attacker, attack, blocked)
	rig.flash()

	if blocked and health > 0.0:
		_play(&"block")
		velocity.x = away * Balance.BLOCK_PUSHBACK
	else:
		_cancel_attack()
		hurtbox.set_crouching(false)
		if health <= 0.0 or attack == &"special":
			_knock_down(away)
			_play(&"hit_special" if attack == &"special" else &"hit_heavy")
		else:
			var info: Dictionary = Balance.ATTACKS[attack]
			_stun_time = info["hitstun"]
			state_machine.force(StateMachine.State.HITSTUN)
			velocity.x = away * Balance.HIT_PUSHBACK
			_play(&"hit_light" if attack == &"punch" else &"hit_heavy")
	# A cornered defender cannot be pushed, so the attacker slides back.
	if is_cornered():
		attacker.velocity.x = -away * Balance.HIT_PUSHBACK * 0.7
	health_changed.emit(self, health)


func register_damage_dealt(damage: float) -> void:
	match_damage_dealt += damage
	last_hit_msec = Time.get_ticks_msec()
	add_meter(damage * Balance.METER_PER_DAMAGE_DEALT)


func add_meter(amount: float) -> void:
	meter = minf(meter + amount, Balance.METER_MAX)
	meter_changed.emit(self, meter)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func play_victory() -> void:
	if health > 0.0:
		_cancel_attack()
		state_machine.force(StateMachine.State.VICTORY)


# --- Queries used by Hitbox, CpuBrain and Match ----------------------------

func can_be_hit() -> bool:
	var s := state_machine.state
	return s != StateMachine.State.KNOCKDOWN and s != StateMachine.State.GETUP and s != StateMachine.State.KO


func is_blocking() -> bool:
	var s := state_machine.state
	return (s == StateMachine.State.BLOCK or s == StateMachine.State.CROUCH_BLOCK) and is_on_floor()


func is_crouching() -> bool:
	var s := state_machine.state
	return s == StateMachine.State.CROUCH or s == StateMachine.State.CROUCH_BLOCK


func is_airborne() -> bool:
	return state_machine.state == StateMachine.State.JUMP or not is_on_floor()


func is_attacking() -> bool:
	return state_machine.state == StateMachine.State.ATTACK


func is_cornered() -> bool:
	return global_position.x <= _min_x() + 6.0 or global_position.x >= _max_x() - 6.0


func attack_length(attack: StringName) -> float:
	var info: Dictionary = Balance.ATTACKS[attack]
	var scale_value: float = info["reach_scale"]
	var length := data.reach_length() * scale_value
	if attack == &"special":
		length += data.special_reach_bonus
	return length


## Centre-to-centre distance at which an attack can connect.
func attack_range(attack: StringName) -> float:
	return Balance.BODY_HALF_WIDTH * 2.0 + attack_length(attack)


## Moves the fighter sideways, staying inside the walls. Returns the
## distance actually moved (used by Match for the push box).
func nudge(amount: float) -> float:
	var before := global_position.x
	global_position.x = clampf(before + amount, _min_x(), _max_x())
	return global_position.x - before


## Attack progress from 0 to 1 across startup, active and recovery.
func attack_progress() -> float:
	if attack_name == &"":
		return 0.0
	var info: Dictionary = Balance.ATTACKS[attack_name]
	var startup: float = info["startup"]
	var active: float = info["active"]
	var recovery: float = info["recovery"]
	match attack_phase:
		Phase.STARTUP:
			return 0.35 * clampf(_phase_time / (startup * _timing_scale * _windup_scale), 0.0, 1.0)
		Phase.ACTIVE:
			return 0.35 + 0.2 * clampf(_phase_time / (active * _timing_scale), 0.0, 1.0)
		Phase.RECOVERY:
			return 0.55 + 0.45 * clampf(_phase_time / (recovery * _timing_scale), 0.0, 1.0)
	return 0.0


# --- Per-frame update -----------------------------------------------------

func _physics_process(delta: float) -> void:
	if data == null:
		return
	input_source.tick(delta)
	state_machine.tick(delta)
	if not is_on_floor():
		velocity.y += Balance.GRAVITY * delta
	match state_machine.state:
		StateMachine.State.ATTACK:
			_process_attack(delta)
		StateMachine.State.HITSTUN:
			_process_hitstun(delta)
		StateMachine.State.KNOCKDOWN:
			_process_knockdown(delta)
		StateMachine.State.GETUP:
			_process_getup(delta)
		StateMachine.State.KO, StateMachine.State.VICTORY:
			_apply_friction(delta)
		StateMachine.State.JUMP:
			_process_jump()
		_:
			_process_free(delta)
	move_and_slide()
	global_position.x = clampf(global_position.x, _min_x(), _max_x())
	_update_visuals()


func _process_free(delta: float) -> void:
	if not is_on_floor():
		state_machine.change(StateMachine.State.JUMP)
		return
	if not input_enabled:
		_apply_friction(delta)
		hurtbox.set_crouching(false)
		state_machine.change(StateMachine.State.IDLE)
		return
	_face_opponent()
	var attack := input_source.consume_attack()
	if attack != &"" and _can_use(attack):
		_start_attack(attack)
		return
	var dir := input_source.get_move_dir()
	if input_source.wants_jump():
		velocity.y = Balance.JUMP_VELOCITY
		velocity.x = dir * Balance.JUMP_FORWARD_SPEED
		hurtbox.set_crouching(false)
		state_machine.change(StateMachine.State.JUMP)
		_play(&"jump")
		return
	var crouching := input_source.wants_crouch()
	hurtbox.set_crouching(crouching)
	if input_source.wants_block():
		velocity.x = 0.0
		state_machine.change(StateMachine.State.CROUCH_BLOCK if crouching else StateMachine.State.BLOCK)
		return
	if crouching:
		velocity.x = 0.0
		state_machine.change(StateMachine.State.CROUCH)
		return
	var speed := data.walk_speed()
	if dir != 0 and dir != facing:
		speed *= Balance.BACKWALK_SCALE
	velocity.x = dir * speed
	state_machine.change(StateMachine.State.WALK if dir != 0 else StateMachine.State.IDLE)


func _process_jump() -> void:
	if is_on_floor() and state_machine.time_in_state > 0.05:
		velocity.x = 0.0
		state_machine.change(StateMachine.State.IDLE)
		_face_opponent()


func _process_hitstun(delta: float) -> void:
	_apply_friction(delta)
	_stun_time -= delta
	if _stun_time <= 0.0:
		state_machine.change(StateMachine.State.IDLE)


func _process_knockdown(delta: float) -> void:
	if is_on_floor():
		_apply_friction(delta)
	if state_machine.time_in_state >= Balance.KNOCKDOWN_TIME and is_on_floor():
		if health <= 0.0:
			state_machine.change(StateMachine.State.KO)
		else:
			state_machine.change(StateMachine.State.GETUP)


func _process_getup(delta: float) -> void:
	_apply_friction(delta)
	if state_machine.time_in_state >= Balance.GETUP_TIME:
		state_machine.change(StateMachine.State.IDLE)
		_face_opponent()


func _can_use(attack: StringName) -> bool:
	if attack == &"special":
		return meter >= Balance.SPECIAL_COST
	return true


func _start_attack(attack: StringName) -> void:
	attack_name = attack
	attack_phase = Phase.STARTUP
	_phase_time = 0.0
	attack_serial += 1
	velocity.x = 0.0
	hurtbox.set_crouching(false)
	state_machine.force(StateMachine.State.ATTACK)
	var info: Dictionary = Balance.ATTACKS[attack]
	var base_damage: float = info["base_damage"]
	var height: StringName = info["height"]
	hitbox.prepare(height, facing, attack_length(attack), base_damage * _damage_multiplier)
	if attack == &"special":
		meter -= Balance.SPECIAL_COST
		meter_changed.emit(self, meter)
		_play(&"whoosh_special")
	elif attack == &"punch":
		_play(&"whoosh_punch")
	else:
		_play(&"whoosh_kick")


func _process_attack(delta: float) -> void:
	_phase_time += delta
	var info: Dictionary = Balance.ATTACKS[attack_name]
	match attack_phase:
		Phase.STARTUP:
			if attack_name == &"special":
				velocity.x = facing * Balance.SPECIAL_LUNGE_SPEED
			else:
				_apply_friction(delta)
			var startup: float = info["startup"]
			if _phase_time >= startup * _timing_scale * _windup_scale:
				attack_phase = Phase.ACTIVE
				_phase_time = 0.0
				hitbox.activate()
				if attack_name == &"special":
					if data.weapon == &"thunderbolt":
						_play(&"thunder")
					elif data.weapon == &"rifle":
						_play(&"rifle")
		Phase.ACTIVE:
			_apply_friction(delta)
			var active: float = info["active"]
			if _phase_time >= active * _timing_scale:
				attack_phase = Phase.RECOVERY
				_phase_time = 0.0
				hitbox.deactivate()
		Phase.RECOVERY:
			_apply_friction(delta)
			var recovery: float = info["recovery"]
			if _phase_time >= recovery * _timing_scale:
				_cancel_attack()
				state_machine.change(StateMachine.State.IDLE)


func _cancel_attack() -> void:
	attack_name = &""
	attack_phase = Phase.NONE
	_phase_time = 0.0
	if hitbox != null:
		hitbox.deactivate()


func _knock_down(away: float) -> void:
	state_machine.force(StateMachine.State.KNOCKDOWN)
	velocity = Vector2(away * Balance.KNOCKDOWN_LAUNCH.x, Balance.KNOCKDOWN_LAUNCH.y)
	_play(&"knockdown")


func _apply_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)


func _face_opponent() -> void:
	if opponent == null:
		return
	var dx := opponent.global_position.x - global_position.x
	if absf(dx) > 4.0:
		facing = 1 if dx > 0.0 else -1


func _min_x() -> float:
	return Balance.WALL_THICKNESS + Balance.BODY_HALF_WIDTH


func _max_x() -> float:
	return Balance.ARENA_WIDTH - Balance.WALL_THICKNESS - Balance.BODY_HALF_WIDTH


func _spawn_spark(attacker: Fighter, attack: StringName, blocked: bool) -> void:
	var spark := HIT_SPARK_SCENE.instantiate() as HitSpark
	var height := 140.0 if attack == &"punch" else (50.0 if attack == &"kick" else 100.0)
	if is_crouching():
		height = minf(height, 80.0)
	spark.setup(blocked, attack == &"special", attacker.data.accent_color)
	var parent: Node = effects_layer if effects_layer != null else get_parent()
	parent.add_child(spark)
	var contact_x := global_position.x + (attacker.global_position.x - global_position.x) * 0.35
	spark.global_position = Vector2(contact_x, global_position.y - height)


func _play(key: StringName) -> void:
	if not SOUNDS.has(key):
		return
	audio.stream = SOUNDS[key]
	audio.play()


func _update_visuals() -> void:
	rig.scale.x = float(facing)
	sprite.flip_h = facing < 0
	var pose := _pose_name()
	var progress := attack_progress()
	if pose == &"getup":
		progress = state_machine.time_in_state / Balance.GETUP_TIME
	rig.set_pose(pose, progress, meter >= Balance.SPECIAL_COST)
	if sprite.visible and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(pose):
		if sprite.animation != pose:
			sprite.play(pose)


func _pose_name() -> StringName:
	match state_machine.state:
		StateMachine.State.WALK:
			return &"walk"
		StateMachine.State.CROUCH:
			return &"crouch"
		StateMachine.State.JUMP:
			return &"jump"
		StateMachine.State.BLOCK:
			return &"block"
		StateMachine.State.CROUCH_BLOCK:
			return &"crouch_block"
		StateMachine.State.ATTACK:
			return attack_name
		StateMachine.State.HITSTUN:
			return &"hitstun"
		StateMachine.State.KNOCKDOWN:
			return &"knockdown"
		StateMachine.State.GETUP:
			return &"getup"
		StateMachine.State.KO:
			return &"ko"
		StateMachine.State.VICTORY:
			return &"victory"
	return &"idle"
