class_name Fighter
extends Node2D
## One fighter. Reused for Player 1, Player 2, every CPU rival and Zeus.
## Deterministic 60 Hz simulation (Design Plan v3+ Section 13.3):
## - Fixed 60 Hz frame counters, pure box math, per-tick input bit-fields.
## - Hit-confirm chain combo cancels (Tier 1 -> 2 -> 3 -> 4), combo scaling.
## - Anti-spam heat + landing recovery + Counter-Hit punish system.
## - Ultimate cut-in trigger + startup invulnerability.
## - Visuals (sprite shader, ground shadow, sparks) and audio only react to events.

signal health_changed(fighter: Fighter, value: float)
signal meter_changed(fighter: Fighter, value: float)
signal cooldowns_changed(fighter: Fighter, cooldowns: Dictionary)
signal hit_landed(attacker: Fighter, defender: Fighter, damage: float, blocked: bool, move_name: StringName, is_counter: bool, combo_count: int)
signal parry_landed(defender: Fighter, attacker: Fighter)
signal parry_failed(fighter: Fighter)
signal seize_started(attacker: Fighter, defender: Fighter)
signal seize_teched(attacker: Fighter, defender: Fighter)
signal burst_triggered(defender: Fighter, attacker: Fighter)
signal sniper_shot_landed(label: String)
signal guard_crushed()
signal move_executed(fighter: Fighter, label: String)
signal ultimate_triggered(fighter: Fighter)
signal ultimate_interrupted(fighter: Fighter)
signal attack_active_started(fighter: Fighter, move_name: StringName)

enum Phase { NONE, STARTUP, ACTIVE, RECOVERY }

const ART_ID_MAP := {
	&"leonidas": "leonidas",
	&"julius_caesar": "caesar",
	&"ragnar": "ragnar",
	&"musashi": "musashi",
	&"lapu_lapu": "lapulapu",
	&"simo_hayha": "simo",
	&"nai_khanom_tom": "naikhanomtom",
	&"zeus": "zeus",
	&"thor": "thor",
	&"susanoo": "susanoo",
	&"anubis": "anubis",
}

const P1_COLOR := Color(0.35, 0.75, 1.0)
const P2_COLOR := Color(1.0, 0.55, 0.2)
const HIT_SPARK_SCENE := preload("res://scenes/effects/hit_spark.tscn")
const SPRITE_SHADER := preload("res://scenes/fighter/fighter_sprite.gdshader")
const LIGHT_FAMILY := [&"light", &"forward_light", &"back_light", &"crouch_light", &"jump_light"]
const HEAVY_FAMILY := [&"heavy", &"forward_heavy", &"back_heavy", &"crouch_heavy", &"jump_heavy"]
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
	&"parry_success": preload("res://assets/audio/sfx/special_ready.wav"),
}

# --- Configuration & scene references --------------------------------------
var player_index := 1
var data: WarriorData
var cpu_tier: CpuTier
var input_source: InputSource
var opponent: Fighter
var effects_layer: Node2D
var spawn_position := Vector2.ZERO
var arena_width := Balance.ARENA_WIDTH

# --- Plain simulation state (Section 13.3) ---------------------------------
var sim_pos := Vector2.ZERO
var sim_vel := Vector2.ZERO
var grounded := true
var max_health := 100.0
var health := 100.0
var meter := 0.0
var facing := 1
var input_enabled := false

var attack_name: StringName = &""
var attack_phase: Phase = Phase.NONE
var attack_serial := 0
var _phase_frames := 0
var _startup_frames := 1
var _active_frames := 1
var _recovery_frames := 1
var _stun_frames := 0
var seize_frames := 0

# Combo cancel & combo counter state
var combo_cancel_ready := false
var combo_cancel_frames := 0
var combo_taken := 0

# Skill cooldowns & anti-spam punish heat
var skill_cooldowns := {
	&"skill_ground": 0,
	&"skill_forward": 0,
	&"skill_back": 0,
	&"skill_air": 0,
	&"skill_low": 0,
}
var move_cooldowns := {}
var spam_heat := {} # move_name -> {"count": int, "decay": int}
var is_spam_unsafe := false
var _prev_spam_move: StringName = &""
var _prev_spam_entry: Dictionary = {}

# Double-tap dash, input buffer & anti-corner-pinning state
var dash_frames := 0
var dash_dir := 0
var dash_cooldown_frames := 0
var last_tap_dir := 0
var last_tap_frames := 0
var buffered_attack: StringName = &""
var buffer_frames := 0
var armor_active := false
var evade_invuln_frames := 0
var wakeup_invuln_frames := 0
var corner_hits_taken := 0
var burst_cooldown_frames := 0
var air_jumps_left := 1
var _landing_squash := 0.0
var _attack_punch := 0.0
var _kd_landed := false
var _ko_from_knockdown := false

# Input edge & chord buffer state
var prev_input_bits := 0
var chord_pending_bit := 0
var chord_timer := 0
var chord_crouching := false
var chord_up := false
var chord_airborne := false
var chord_move_dir := 0

# Parry & block lockout state (Section 9, Open Decision 12)
var parry_window_frames := 0
var block_hold_frames := 0
var block_lockout_frames := 0
var parry_active_hold := false
var parry_succeeded_this_hold := false

# Match tiebreak stats (frame number instead of wall clock)
var match_damage_dealt := 0.0
var last_hit_frame := -1

var _damage_multiplier := 1.0
var _timing_scale := 1.0
var _windup_scale := 1.0
var _sprite_mat: ShaderMaterial
var _sprite_flash := 0.0
var _aura: FighterAura
var _trail_tick := 0

var hitbox := Hitbox.new()
var hurtbox := Hurtbox.new()

@onready var state_machine: StateMachine = $StateMachine
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
	var kit: Dictionary = Balance.CHAMPION_KITS.get(warrior.id, {})
	_damage_multiplier = warrior.damage_multiplier() * float(kit.get("damage_bonus", 1.0))
	_timing_scale = warrior.timing_scale() * float(kit.get("timing_bonus", 1.0))
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
		_sprite_mat = ShaderMaterial.new()
		_sprite_mat.shader = SPRITE_SHADER
		_sprite_mat.set_shader_parameter(&"alt_palette", alt_palette)
		_sprite_mat.set_shader_parameter(&"alt_tint", Vector3(warrior.alt_primary_color.r, warrior.alt_primary_color.g, warrior.alt_primary_color.b))
		sprite.material = _sprite_mat
	else:
		sprite.visible = false
		sprite.material = null
		_sprite_mat = null
		rig.visible = true
	tag_label.text = "CPU" if source is CpuBrain else ("P%d" % index)
	tag_label.add_theme_color_override("font_color", color)
	_setup_aura(warrior)
	facing = 1 if index == 1 else -1
	health = max_health
	meter = 0.0
	match_damage_dealt = 0.0
	last_hit_frame = -1
	_reset_round_state()


## Connected to RoundManager.round_started: health & cooldowns reset, meter
## carries across rounds so Ultimates shine during the match, fighters reset
## face-to-face at spawn.
func _on_round_started(round_no: int) -> void:
	health = max_health
	sim_pos = spawn_position
	global_position = sim_pos
	sim_vel = Vector2.ZERO
	grounded = true
	facing = 1 if player_index == 1 else -1
	input_enabled = false
	_reset_round_state()
	state_machine.force(StateMachine.State.IDLE)
	input_source.reset_for_round(round_no)
	health_changed.emit(self, health)
	meter_changed.emit(self, meter)
	cooldowns_changed.emit(self, skill_cooldowns.duplicate())
	sync_visuals()


func _reset_round_state() -> void:
	_cancel_attack()
	hurtbox.set_crouching(false)
	_stun_frames = 0
	seize_frames = 0
	combo_taken = 0
	for k in skill_cooldowns:
		skill_cooldowns[k] = 0
	move_cooldowns.clear()
	spam_heat.clear()
	is_spam_unsafe = false
	dash_frames = 0
	dash_dir = 0
	dash_cooldown_frames = 0
	last_tap_dir = 0
	last_tap_frames = 0
	buffered_attack = &""
	buffer_frames = 0
	armor_active = false
	evade_invuln_frames = 0
	wakeup_invuln_frames = 0
	corner_hits_taken = 0
	burst_cooldown_frames = 0
	air_jumps_left = 1
	_landing_squash = 0.0
	_attack_punch = 0.0
	_kd_landed = false
	_ko_from_knockdown = false
	prev_input_bits = 0
	_clear_chord()
	_clear_parry_hold()
	block_lockout_frames = 0


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_clear_chord()
		_clear_parry_hold()


func play_victory() -> void:
	if health > 0.0:
		_cancel_attack()
		_clear_chord()
		_clear_parry_hold()
		state_machine.force(StateMachine.State.VICTORY)


# --- Queries ---------------------------------------------------------------

func can_be_hit() -> bool:
	if wakeup_invuln_frames > 0 or evade_invuln_frames > 0:
		return false
	var s := state_machine.state
	# Ultimate caster is invulnerable during cut-in & first 6 startup frames,
	# then CAN be hit/interrupted mid-Ult (unless it's an already-launched projectile!).
	if s == StateMachine.State.ATTACK and attack_name == &"ultimate" and attack_phase == Phase.STARTUP and _phase_frames < 6:
		return false
	# Brief backdash evade frames (Tekken / SF backdash feel).
	if s == StateMachine.State.DASH and dash_dir == -facing \
			and dash_frames > Balance.DASH_FRAMES - Balance.BACKDASH_INVULN_FRAMES:
		return false
	return s != StateMachine.State.KNOCKDOWN \
		and s != StateMachine.State.GETUP \
		and s != StateMachine.State.KO \
		and s != StateMachine.State.GRABBED \
		and s != StateMachine.State.SEIZE_THROW


func can_burst_escape() -> bool:
	if not input_enabled or burst_cooldown_frames > 0 or opponent == null:
		return false
	var s := state_machine.state
	if s == StateMachine.State.KO or s == StateMachine.State.KNOCKDOWN or s == StateMachine.State.GRABBED or s == StateMachine.State.SEIZE_THROW:
		return false
	var free_corner_escape := is_cornered() and corner_hits_taken >= 3
	if not free_corner_escape and meter < Balance.BURST_METER_COST:
		return false
	return s == StateMachine.State.HITSTUN or s == StateMachine.State.BLOCK or s == StateMachine.State.CROUCH_BLOCK or is_cornered()


func _trigger_burst_escape() -> void:
	var free_corner_escape := is_cornered() and corner_hits_taken >= 3
	if not free_corner_escape:
		meter = maxf(meter - Balance.BURST_METER_COST, 0.0)
		meter_changed.emit(self, meter)
	corner_hits_taken = 0
	burst_cooldown_frames = 180 # 3.0 s cooldown
	wakeup_invuln_frames = 12
	_cancel_attack()
	_clear_chord()
	_clear_parry_hold()
	_stun_frames = 0
	combo_taken = 0
	hurtbox.set_crouching(false)
	state_machine.force(StateMachine.State.IDLE if grounded else StateMachine.State.JUMP)
	# Blast opponent away cleanly + nudge self slightly out of the corner!
	var away_opp := 1.0 if opponent.sim_pos.x >= sim_pos.x else -1.0
	opponent._cancel_attack()
	opponent.sim_vel = Vector2(away_opp * Balance.BURST_PUSHBACK, -180.0)
	opponent.grounded = false
	opponent._stun_frames = 18
	opponent.state_machine.force(StateMachine.State.HITSTUN)
	if is_cornered():
		nudge(away_opp * 36.0)
	if effects_layer != null:
		CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -96), Color(1.0, 0.92, 0.35), 200.0, 0.32, 1.0, 12.0)
		CombatVfx.spawn_radial_burst(effects_layer, sim_pos + Vector2(0, -96), Color(1.0, 0.94, 0.45), 16, 480.0, 0.30)
	_flash_visual(Color(1.0, 0.94, 0.45))
	_play(&"parry_success")
	burst_triggered.emit(self, opponent)


## Allows simultaneous Dual Ultimates / Counter-Ultimates during an active cut-in!
func can_counter_ultimate() -> bool:
	if not input_enabled or meter < Balance.ULTIMATE_COST:
		return false
	var s := state_machine.state
	if s == StateMachine.State.ATTACK and attack_name == &"ultimate":
		return false
	return s != StateMachine.State.KO \
		and s != StateMachine.State.KNOCKDOWN \
		and s != StateMachine.State.GRABBED \
		and s != StateMachine.State.SEIZE_THROW


func trigger_counter_ultimate() -> void:
	_clear_chord()
	_clear_parry_hold()
	_face_opponent()
	_start_attack(&"ultimate")


func is_in_rage() -> bool:
	return health > 0.0 and health <= max_health * 0.25


func is_counter_vulnerable() -> bool:
	var s := state_machine.state
	if s == StateMachine.State.PARRY_FAIL or s == StateMachine.State.PARRIED:
		return true
	if s == StateMachine.State.ATTACK:
		if attack_phase == Phase.STARTUP:
			return true
		if attack_phase == Phase.RECOVERY and is_spam_unsafe:
			return true
	return false


func is_blocking() -> bool:
	var s := state_machine.state
	return (s == StateMachine.State.BLOCK or s == StateMachine.State.CROUCH_BLOCK) \
		and grounded and block_lockout_frames <= 0


func is_in_parry_window() -> bool:
	return is_blocking() and parry_window_frames > 0


func is_crouching() -> bool:
	var s := state_machine.state
	if s == StateMachine.State.CROUCH or s == StateMachine.State.CROUCH_BLOCK:
		return true
	if s == StateMachine.State.ATTACK and (attack_name == &"crouch_light" or attack_name == &"crouch_heavy" or attack_name == &"skill_low"):
		return true
	return false


func is_airborne() -> bool:
	return state_machine.state == StateMachine.State.JUMP or not grounded


func is_attacking() -> bool:
	return state_machine.state == StateMachine.State.ATTACK


func is_cornered() -> bool:
	return sim_pos.x <= _min_x() + 6.0 or sim_pos.x >= _max_x() - 6.0


func is_skill_ready(skill_name: StringName) -> bool:
	return int(skill_cooldowns.get(skill_name, 0)) <= 0


func is_move_ready(move_name: StringName) -> bool:
	return int(move_cooldowns.get(move_name, 0)) <= 0


func attack_length(attack: StringName) -> float:
	var info: Dictionary = Balance.ATTACKS[attack]
	var scale_value: float = info["reach_scale"]
	var kit: Dictionary = Balance.CHAMPION_KITS.get(data.id, {})
	var length := (data.reach_length() + float(kit.get("reach_bonus", 0.0))) * scale_value
	if attack == &"ultimate":
		length += data.special_reach_bonus
	return length


func attack_range(attack: StringName) -> float:
	return Balance.BODY_HALF_WIDTH * 2.0 + attack_length(attack)


func nudge(amount: float) -> float:
	var before := sim_pos.x
	sim_pos.x = clampf(before + amount, _min_x(), _max_x())
	return sim_pos.x - before


func attack_progress() -> float:
	if attack_name == &"":
		return 0.0
	match attack_phase:
		Phase.STARTUP:
			return 0.30 * clampf(float(_phase_frames) / float(maxi(1, _startup_frames)), 0.0, 1.0)
		Phase.ACTIVE:
			return 0.30 + 0.36 * clampf(float(_phase_frames) / float(maxi(1, _active_frames)), 0.0, 1.0)
		Phase.RECOVERY:
			return 0.66 + 0.34 * clampf(float(_phase_frames) / float(maxi(1, _recovery_frames)), 0.0, 1.0)
	return 0.0


# --- Single 60 Hz simulation tick (driven by Match) ------------------------

func sample_input_bits() -> int:
	if input_source == null:
		return 0
	return input_source.sample_bits()


func step_tick(bits: int, sim_frame: int) -> void:
	if data == null:
		return

	# Tick skill cooldowns.
	var cd_changed := false
	for k in skill_cooldowns:
		var cur: int = skill_cooldowns[k]
		if cur > 0:
			skill_cooldowns[k] = cur - 1
			cd_changed = true
	if cd_changed:
		cooldowns_changed.emit(self, skill_cooldowns.duplicate())

	# Tick brief per-move cooldowns.
	var expired_moves: Array[StringName] = []
	for m in move_cooldowns:
		var mcd: int = int(move_cooldowns[m]) - 1
		if mcd <= 0:
			expired_moves.append(m)
		else:
			move_cooldowns[m] = mcd
	for m in expired_moves:
		move_cooldowns.erase(m)

	# Decay anti-spam heat over 3 seconds.
	var expired_heat: Array[StringName] = []
	for h_move in spam_heat:
		var entry: Dictionary = spam_heat[h_move]
		var dec: int = int(entry["decay"]) - 1
		if dec <= 0:
			expired_heat.append(h_move)
		else:
			entry["decay"] = dec
	for h_move in expired_heat:
		spam_heat.erase(h_move)

	if dash_cooldown_frames > 0:
		dash_cooldown_frames -= 1
	if last_tap_frames > 0:
		last_tap_frames -= 1
		if last_tap_frames <= 0:
			last_tap_dir = 0
	if block_lockout_frames > 0:
		block_lockout_frames -= 1
	if wakeup_invuln_frames > 0:
		wakeup_invuln_frames -= 1
	if evade_invuln_frames > 0:
		evade_invuln_frames -= 1
	if burst_cooldown_frames > 0:
		burst_cooldown_frames -= 1
	if not is_cornered():
		corner_hits_taken = 0
	if buffer_frames > 0:
		buffer_frames -= 1
		if buffer_frames <= 0:
			buffered_attack = &""

	state_machine.step_tick()

	var pressed := bits & ~prev_input_bits
	var block_held := (bits & InputSource.BLOCK) != 0

	# Anti-Corner-Pinning Burst / Guard Reversal (Block + Seize = J+H)!
	var burst_input := ((bits & InputSource.BLOCK) != 0 and (pressed & InputSource.SEIZE) != 0) \
		or ((bits & InputSource.SEIZE) != 0 and (pressed & InputSource.BLOCK) != 0)
	if burst_input and can_burst_escape():
		_trigger_burst_escape()
		prev_input_bits = bits
		return

	# Capture 6-frame input buffer during late recovery/stun/getup so inputs never feel dropped!
	if input_enabled and (state_machine.state == StateMachine.State.HITSTUN \
			or state_machine.state == StateMachine.State.GETUP \
			or state_machine.state == StateMachine.State.PARRY \
			or (state_machine.state == StateMachine.State.ATTACK and attack_phase == Phase.RECOVERY)):
		var buf_atk := _peek_buffered_attack(bits, pressed)
		if buf_atk != &"":
			buffered_attack = buf_atk
			buffer_frames = Balance.INPUT_BUFFER_FRAMES

	# Track ongoing parry/block hold and detect mistimed tap release.
	if parry_active_hold:
		if not input_enabled or not grounded or not _is_block_state():
			_clear_parry_hold()
		elif not block_held:
			var was_short_tap := block_hold_frames < Balance.PARRY_HOLD_THRESHOLD_FRAMES
			var succeeded := parry_succeeded_this_hold
			_clear_parry_hold()
			if not succeeded and was_short_tap:
				_trigger_parry_fail()
		else:
			block_hold_frames += 1
			if parry_window_frames > 0:
				parry_window_frames -= 1

	match state_machine.state:
		StateMachine.State.ATTACK:
			_process_attack(bits, pressed)
		StateMachine.State.DASH:
			_process_dash(bits, pressed)
		StateMachine.State.SEIZE_THROW:
			_process_seize_throw(sim_frame)
		StateMachine.State.GRABBED:
			_process_grabbed(pressed)
		StateMachine.State.PARRY, StateMachine.State.PARRY_FAIL, StateMachine.State.PARRIED, StateMachine.State.HITSTUN:
			_process_timed_recovery()
		StateMachine.State.KNOCKDOWN:
			_process_knockdown()
		StateMachine.State.GETUP:
			_process_getup()
		StateMachine.State.KO, StateMachine.State.VICTORY:
			_apply_friction()
		StateMachine.State.JUMP:
			_process_jump(bits, pressed)
		_:
			_process_free(bits, pressed)

	var was_airborne := not grounded
	_integrate_kinematics()

	# Crisp landing dust puff, micro-squash & dive-impact shockwave!
	if was_airborne and grounded:
		_landing_squash = 1.0
		if effects_layer != null:
			CombatVfx.spawn_dust_puff(effects_layer, sim_pos, 0, 8)
		if state_machine.state == StateMachine.State.ATTACK:
			var info: Dictionary = Balance.ATTACKS.get(attack_name, {})
			var lag: int = int(info.get("landing_lag", 0))
			if lag > 0:
				if effects_layer != null and (attack_name == &"skill_air" or attack_name == &"jump_heavy"):
					CombatVfx.spawn_ground_shatter(effects_layer, sim_pos, data.accent_color, 0.85)
					CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos, data.accent_color, 130.0, 0.28, 0.26, 8.0)
				_cancel_attack()
				hurtbox.set_crouching(true)
				sim_vel.x *= 0.25
				_stun_frames = lag
				state_machine.force(StateMachine.State.PARRY_FAIL)

	prev_input_bits = bits


func _integrate_kinematics() -> void:
	if not grounded:
		sim_vel.y += Balance.GRAVITY * Balance.DT
	sim_pos += sim_vel * Balance.DT
	if sim_pos.y >= Balance.FLOOR_Y:
		sim_pos.y = Balance.FLOOR_Y
		sim_vel.y = 0.0
		grounded = true
		air_jumps_left = 1
	else:
		grounded = false
	sim_pos.x = clampf(sim_pos.x, _min_x(), _max_x())


func _is_block_state() -> bool:
	var s := state_machine.state
	return s == StateMachine.State.BLOCK or s == StateMachine.State.CROUCH_BLOCK


func _process_free(bits: int, pressed: int) -> void:
	combo_taken = 0
	if not grounded:
		_clear_parry_hold()
		state_machine.change(StateMachine.State.JUMP)
		return
	if not input_enabled:
		_apply_friction()
		hurtbox.set_crouching(false)
		state_machine.change(StateMachine.State.IDLE)
		_face_opponent()
		return

	_face_opponent()

	var move_dir := int((bits & InputSource.RIGHT) != 0) - int((bits & InputSource.LEFT) != 0)
	var up_held := (bits & InputSource.UP) != 0
	var crouching := (bits & InputSource.DOWN) != 0
	var block_held := (bits & InputSource.BLOCK) != 0
	var block_just := (pressed & InputSource.BLOCK) != 0

	var attack := _resolve_attack_input(bits, pressed, false)
	if attack == &"" and buffered_attack != &"" and _can_use(buffered_attack):
		attack = buffered_attack
		buffered_attack = &""
		buffer_frames = 0
	if attack != &"" and _can_use(attack):
		_clear_parry_hold()
		if Balance.ATTACKS[attack].get("air_only", false) and grounded:
			sim_vel.y = Balance.JUMP_VELOCITY * (0.72 if attack == &"skill_air" else 0.65)
			sim_vel.x = float(move_dir) * Balance.JUMP_FORWARD_SPEED
			grounded = false
		_start_attack(attack)
		return

	if up_held and chord_pending_bit == 0:
		_clear_chord()
		_clear_parry_hold()
		sim_vel.y = Balance.JUMP_VELOCITY
		sim_vel.x = float(move_dir) * Balance.JUMP_FORWARD_SPEED
		grounded = false
		hurtbox.set_crouching(false)
		state_machine.change(StateMachine.State.JUMP)
		if effects_layer != null:
			CombatVfx.spawn_dust_puff(effects_layer, sim_pos, 0, 7)
		_play(&"jump")
		return

	hurtbox.set_crouching(crouching)
	if block_held and block_lockout_frames <= 0:
		sim_vel.x = 0.0
		if block_just:
			parry_active_hold = true
			parry_succeeded_this_hold = false
			block_hold_frames = 1
			parry_window_frames = Balance.PARRY_WINDOW_FRAMES
		state_machine.change(StateMachine.State.CROUCH_BLOCK if crouching else StateMachine.State.BLOCK)
		return

	if crouching:
		sim_vel.x = 0.0
		state_machine.change(StateMachine.State.CROUCH)
		return

	var tap_dir := int((pressed & InputSource.RIGHT) != 0) - int((pressed & InputSource.LEFT) != 0)
	if tap_dir != 0:
		if tap_dir == last_tap_dir and last_tap_frames > 0 and dash_cooldown_frames <= 0:
			_start_dash(tap_dir)
			return
		last_tap_dir = tap_dir
		last_tap_frames = Balance.DASH_TAP_WINDOW_FRAMES

	var speed := data.walk_speed()
	if move_dir != 0 and move_dir != facing:
		speed *= Balance.BACKWALK_SCALE
	sim_vel.x = float(move_dir) * speed
	state_machine.change(StateMachine.State.WALK if move_dir != 0 else StateMachine.State.IDLE)


func _start_dash(dir: int) -> void:
	dash_dir = dir
	dash_frames = Balance.DASH_FRAMES
	dash_cooldown_frames = Balance.DASH_FRAMES + Balance.DASH_COOLDOWN_FRAMES
	last_tap_dir = 0
	last_tap_frames = 0
	var speed := Balance.DASH_FORWARD_SPEED if dir == facing else Balance.DASH_BACK_SPEED
	sim_vel.x = float(dir) * speed
	hurtbox.set_crouching(false)
	state_machine.force(StateMachine.State.DASH)
	if effects_layer != null:
		CombatVfx.spawn_dust_puff(effects_layer, sim_pos, dir, 9)
		if data.id == &"zeus":
			CombatVfx.spawn_lightning_arc(effects_layer, sim_pos + Vector2(0, -85), sim_pos + Vector2(-float(dir) * 90.0, -70), Color(1.0, 0.94, 0.4), 0.18, 4.5, 1)
	_play(&"whoosh_punch")


func _process_dash(bits: int, pressed: int) -> void:
	combo_taken = 0
	if not input_enabled or not grounded:
		dash_frames = 0
		state_machine.change(StateMachine.State.IDLE if grounded else StateMachine.State.JUMP)
		return
	_face_opponent()
	var attack := _resolve_attack_input(bits, pressed, false)
	if attack != &"" and _can_use(attack):
		dash_frames = 0
		if Balance.ATTACKS[attack].get("air_only", false):
			sim_vel.y = Balance.JUMP_VELOCITY * (0.72 if attack == &"skill_air" else 0.65)
			grounded = false
		_start_attack(attack)
		return
	if (bits & InputSource.UP) != 0 and chord_pending_bit == 0:
		dash_frames = 0
		sim_vel.y = Balance.JUMP_VELOCITY
		sim_vel.x = float(dash_dir) * Balance.JUMP_FORWARD_SPEED * 1.15
		grounded = false
		state_machine.change(StateMachine.State.JUMP)
		_play(&"jump")
		return
	if (bits & InputSource.BLOCK) != 0 and block_lockout_frames <= 0:
		dash_frames = 0
		sim_vel.x = 0.0
		if (pressed & InputSource.BLOCK) != 0:
			parry_active_hold = true
			parry_succeeded_this_hold = false
			block_hold_frames = 1
			parry_window_frames = Balance.PARRY_WINDOW_FRAMES
		state_machine.change(StateMachine.State.BLOCK)
		return

	var speed := Balance.DASH_FORWARD_SPEED if dash_dir == facing else Balance.DASH_BACK_SPEED
	sim_vel.x = float(dash_dir) * speed
	dash_frames -= 1
	if dash_frames <= 0:
		sim_vel.x *= 0.35
		state_machine.change(StateMachine.State.IDLE)


func _process_jump(bits: int, pressed: int) -> void:
	combo_taken = 0
	if input_enabled:
		var move_dir := int((bits & InputSource.RIGHT) != 0) - int((bits & InputSource.LEFT) != 0)
		# Crisp mid-air Double Jump to vault over opponents and escape corners!
		if (pressed & InputSource.UP) != 0 and air_jumps_left > 0 and state_machine.frames_in_state >= 4:
			air_jumps_left -= 1
			sim_vel.y = Balance.DOUBLE_JUMP_VELOCITY
			if move_dir != 0:
				sim_vel.x = float(move_dir) * Balance.JUMP_FORWARD_SPEED * 1.12
			_face_opponent()
			if effects_layer != null:
				CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -10), Color(0.92, 0.94, 1.0), 68.0, 0.20, 0.30, 6.0)
				CombatVfx.spawn_dust_puff(effects_layer, sim_pos, 0, 5)
			_play(&"jump", 1.18)
			return
		if move_dir != 0:
			sim_vel.x = clampf(sim_vel.x + float(move_dir) * Balance.AIR_DRIFT_ACCEL * Balance.DT, -Balance.AIR_MAX_SPEED, Balance.AIR_MAX_SPEED)
		var air_attack := _resolve_attack_input(bits, pressed, true)
		if air_attack != &"" and _can_use(air_attack):
			_start_attack(air_attack)
			return
	if grounded and state_machine.frames_in_state > Balance.JUMP_LAND_GRACE_FRAMES:
		sim_vel.x = 0.0
		_clear_chord()
		state_machine.change(StateMachine.State.IDLE)
		_face_opponent()


func _process_timed_recovery() -> void:
	if grounded:
		_apply_friction()
	_stun_frames -= 1
	if _stun_frames <= 0:
		hurtbox.set_crouching(false)
		state_machine.change(StateMachine.State.IDLE if grounded else StateMachine.State.JUMP)
		if grounded:
			combo_taken = 0
			_face_opponent()


func _process_knockdown() -> void:
	if grounded:
		if not _kd_landed:
			_kd_landed = true
			_landing_squash = 0.85
			if effects_layer != null:
				CombatVfx.spawn_dust_puff(effects_layer, sim_pos, 0, 12)
				CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos, Color(0.85, 0.82, 0.78), 110.0, 0.24, 0.24, 6.0)
			_play(&"knockdown", 0.92)
		_apply_friction()
	if grounded and _kd_landed:
		if health <= 0.0:
			if state_machine.frames_in_state >= 16:
				_ko_from_knockdown = true
				state_machine.change(StateMachine.State.KO)
		elif state_machine.frames_in_state >= Balance.KNOCKDOWN_FRAMES:
			state_machine.change(StateMachine.State.GETUP)


func _process_getup() -> void:
	combo_taken = 0
	corner_hits_taken = 0
	_apply_friction()
	if state_machine.frames_in_state >= Balance.GETUP_FRAMES:
		wakeup_invuln_frames = Balance.WAKEUP_INVULN_FRAMES
		state_machine.change(StateMachine.State.IDLE)
		_face_opponent()


func _process_seize_throw(sim_frame: int) -> void:
	_apply_friction()
	if opponent == null or opponent.state_machine.state != StateMachine.State.GRABBED:
		state_machine.change(StateMachine.State.IDLE)
		return
	var hold_x := clampf(sim_pos.x + float(facing) * (Balance.BODY_HALF_WIDTH * 2.0 + 4.0), _min_x(), _max_x())
	opponent.sim_pos = Vector2(hold_x, Balance.FLOOR_Y)
	opponent.sim_vel = Vector2.ZERO
	opponent.grounded = true
	seize_frames -= 1
	if seize_frames <= 0:
		var info: Dictionary = Balance.ATTACKS[&"seize"]
		var dmg: float = info["base_damage"] * _damage_multiplier
		opponent.receive_seize_throw_damage(self, dmg, info["meter_gain"], sim_frame)
		state_machine.change(StateMachine.State.IDLE)
		_face_opponent()


func _process_grabbed(pressed: int) -> void:
	sim_vel = Vector2.ZERO
	if opponent == null or opponent.state_machine.state != StateMachine.State.SEIZE_THROW:
		state_machine.change(StateMachine.State.IDLE)
		return
	if input_enabled and (pressed & InputSource.SEIZE) != 0 \
			and state_machine.frames_in_state <= Balance.SEIZE_TECH_WINDOW_FRAMES:
		resolve_seize_tech(opponent, self)


# --- Chord Buffer & Directional Normal Resolver ----------------------------

func _resolve_attack_input(bits: int, pressed: int, airborne: bool) -> StringName:
	var light_just := (pressed & InputSource.LIGHT) != 0
	var heavy_just := (pressed & InputSource.HEAVY) != 0
	var seize_just := (pressed & InputSource.SEIZE) != 0
	var ult_just := (pressed & InputSource.ULTIMATE) != 0
	var down_held := (bits & InputSource.DOWN) != 0
	var up_held := (bits & InputSource.UP) != 0
	var move_dir := int((bits & InputSource.RIGHT) != 0) - int((bits & InputSource.LEFT) != 0)

	if not airborne and ult_just and _can_use(&"ultimate"):
		_clear_chord()
		return &"ultimate"

	# Simultaneous dual-button chords (F+G Skills, F+H Shadow Step, G+H Sky Launcher!)
	if light_just and heavy_just:
		_clear_chord()
		return _chord_skill_name(airborne or up_held, down_held, move_dir)
	if light_just and seize_just and not airborne:
		_clear_chord()
		return &"feint_step"
	if heavy_just and seize_just and not airborne:
		_clear_chord()
		return &"power_launcher"

	if chord_pending_bit != 0:
		var fg_done := (chord_pending_bit == InputSource.LIGHT and heavy_just) \
			or (chord_pending_bit == InputSource.HEAVY and light_just)
		var fh_done := (chord_pending_bit == InputSource.LIGHT and seize_just) \
			or (chord_pending_bit == InputSource.SEIZE and light_just)
		var gh_done := (chord_pending_bit == InputSource.HEAVY and seize_just) \
			or (chord_pending_bit == InputSource.SEIZE and heavy_just)
		if fg_done:
			var is_air := airborne or chord_airborne or up_held or chord_up
			var is_low := down_held or chord_crouching
			var dir := move_dir if move_dir != 0 else chord_move_dir
			_clear_chord()
			return _chord_skill_name(is_air, is_low, dir)
		if fh_done and not airborne:
			_clear_chord()
			return &"feint_step"
		if gh_done and not airborne:
			_clear_chord()
			return &"power_launcher"

		chord_timer -= 1
		if chord_timer <= 0:
			var pending := chord_pending_bit
			var was_air := airborne or chord_airborne
			var was_up := up_held or chord_up
			var was_low := down_held or chord_crouching
			var dir := move_dir if move_dir != 0 else chord_move_dir
			_clear_chord()
			return _directional_normal(pending, was_air, was_up, was_low, dir)
		return &""

	if light_just or heavy_just or seize_just:
		chord_pending_bit = InputSource.LIGHT if light_just else (InputSource.HEAVY if heavy_just else InputSource.SEIZE)
		chord_timer = Balance.CHORD_BUFFER_FRAMES
		chord_crouching = down_held
		chord_up = up_held
		chord_airborne = airborne
		chord_move_dir = move_dir
	return &""


func _directional_normal(button_bit: int, airborne: bool, up_held: bool, down_held: bool, move_dir: int) -> StringName:
	if button_bit == InputSource.SEIZE:
		if airborne or up_held:
			return &"jump_seize"
		if down_held:
			return &"crouch_seize"
		if move_dir != 0 and move_dir == facing:
			return &"forward_seize"
		if move_dir != 0 and move_dir == -facing:
			return &"back_seize"
		return &"seize"
	var is_light := button_bit == InputSource.LIGHT
	if airborne or up_held:
		return &"jump_light" if is_light else &"jump_heavy"
	if down_held:
		return &"crouch_light" if is_light else &"crouch_heavy"
	if move_dir != 0 and move_dir == facing:
		return &"forward_light" if is_light else &"forward_heavy"
	if move_dir != 0 and move_dir == -facing:
		return &"back_light" if is_light else &"back_heavy"
	return &"light" if is_light else &"heavy"


func _chord_skill_name(airborne: bool, crouching: bool, move_dir: int = 0) -> StringName:
	if airborne:
		return &"skill_air"
	if crouching:
		return &"skill_low"
	if move_dir != 0 and move_dir == facing:
		return &"skill_forward"
	if move_dir != 0 and move_dir == -facing:
		return &"skill_back"
	return &"skill_ground"


func _peek_buffered_attack(bits: int, pressed: int) -> StringName:
	var down_held := (bits & InputSource.DOWN) != 0
	var up_held := (bits & InputSource.UP) != 0
	var move_dir := int((bits & InputSource.RIGHT) != 0) - int((bits & InputSource.LEFT) != 0)
	if (pressed & InputSource.ULTIMATE) != 0 and _can_use(&"ultimate"):
		return &"ultimate"
	var l := (pressed & InputSource.LIGHT) != 0
	var h := (pressed & InputSource.HEAVY) != 0
	var s := (pressed & InputSource.SEIZE) != 0
	if l and h:
		return _chord_skill_name(up_held or not grounded, down_held, move_dir)
	if l and s:
		return &"feint_step"
	if h and s:
		return &"power_launcher"
	if s:
		return _directional_normal(InputSource.SEIZE, not grounded, up_held, down_held, move_dir)
	if l:
		return _directional_normal(InputSource.LIGHT, not grounded, up_held, down_held, move_dir)
	if h:
		return _directional_normal(InputSource.HEAVY, not grounded, up_held, down_held, move_dir)
	return &""


func _clear_chord() -> void:
	chord_pending_bit = 0
	chord_timer = 0
	chord_crouching = false
	chord_up = false
	chord_airborne = false
	chord_move_dir = 0


func _clear_parry_hold() -> void:
	parry_active_hold = false
	parry_succeeded_this_hold = false
	parry_window_frames = 0
	block_hold_frames = 0


func _trigger_parry_fail() -> void:
	block_lockout_frames = Balance.PARRY_LOCKOUT_FRAMES
	_stun_frames = Balance.PARRY_FAIL_ANIM_FRAMES
	sim_vel.x = 0.0
	hurtbox.set_crouching(false)
	state_machine.force(StateMachine.State.PARRY_FAIL)
	parry_failed.emit(self)
	_play(&"whoosh_punch")


# --- Attacks, Combo Cancels & Anti-Spam Heat -------------------------------

func _can_use(attack: StringName) -> bool:
	if not Balance.ATTACKS.has(attack):
		return false
	if attack == &"ultimate":
		return meter >= Balance.ULTIMATE_COST
	if Balance.SKILL_COOLDOWNS.has(attack):
		return is_skill_ready(attack)
	if not is_move_ready(attack):
		return false
	return true


func on_hit_confirmed() -> void:
	combo_cancel_ready = true
	combo_cancel_frames = Balance.COMBO_CANCEL_EXTRA_FRAMES


func _start_attack(attack: StringName) -> void:
	var info: Dictionary = Balance.ATTACKS[attack]
	attack_name = attack
	attack_phase = Phase.STARTUP
	_phase_frames = 0
	attack_serial += 1
	combo_cancel_ready = false
	combo_cancel_frames = 0
	is_spam_unsafe = false

	_startup_frames = Balance.scale_frames(info["startup"], _timing_scale * _windup_scale)
	_active_frames = Balance.scale_frames(info["active"], _timing_scale)
	_recovery_frames = Balance.scale_frames(info["recovery"], _timing_scale)

	# Anti-spam heat: repeated use of the same move within 3 s reduces damage,
	# extends recovery (unsafe / counter-hittable!), and scales up cooldown!
	var spam_dmg_mult := 1.0
	var spam_cd_mult := 1.0
	_prev_spam_move = attack
	_prev_spam_entry = (spam_heat[attack] as Dictionary).duplicate() if spam_heat.has(attack) else {}
	if info.get("category", &"normal") == &"normal":
		var prev_count: int = int(_prev_spam_entry.get("count", 0))
		var count := prev_count + 1
		spam_heat[attack] = {"count": count, "decay": Balance.SPAM_MEMORY_FRAMES}
		if count == 2:
			spam_dmg_mult = 0.80
			_recovery_frames += 6
			spam_cd_mult = 1.5
		elif count >= 3:
			spam_dmg_mult = 0.55
			_recovery_frames += 14
			spam_cd_mult = 2.2
			is_spam_unsafe = true
			move_cooldowns[attack] = maxi(int(move_cooldowns.get(attack, 0)), 26)

	var base_cd: int = int(info.get("move_cooldown", 0))
	if base_cd > 0:
		var scaled_cd := roundi(float(base_cd) * spam_cd_mult)
		move_cooldowns[attack] = maxi(int(move_cooldowns.get(attack, 0)), scaled_cd)

	if grounded:
		sim_vel.x = 0.0
	var kit: Dictionary = Balance.CHAMPION_KITS.get(data.id, {})
	armor_active = ((attack == &"forward_heavy" or attack == &"skill_forward") and bool(kit.get("forward_heavy_armor", false)))
	evade_invuln_frames = maxi(evade_invuln_frames, int(info.get("evade_invuln", 0)))
	var hop: float = float(info.get("hop_vel", 0.0))
	if attack == &"skill_forward" and kit.has("skill_forward_hop"):
		hop = float(kit["skill_forward_hop"])
	elif attack == &"skill_back" and kit.has("skill_back_hop"):
		hop = float(kit["skill_back_hop"])
	if hop < 0.0 and grounded:
		sim_vel.y = hop
		grounded = false
		if effects_layer != null:
			CombatVfx.spawn_dust_puff(effects_layer, sim_pos, -facing, 9)
	var dive: float = float(info.get("dive_speed", 0.0))
	if attack == &"skill_air" and kit.has("skill_air_dive"):
		dive = float(kit["skill_air_dive"])
	if dive > 0.0 and not grounded:
		sim_vel.y = maxf(sim_vel.y, dive)
	elif dive < 0.0 and not grounded:
		sim_vel.y = minf(sim_vel.y, dive)
		sim_vel.x = -float(facing) * 280.0

	var low_stance := attack == &"crouch_light" or attack == &"crouch_heavy" or attack == &"skill_low"
	hurtbox.set_crouching(low_stance and grounded)
	state_machine.force(StateMachine.State.ATTACK)

	var base_dmg: float = info["base_damage"]
	var rage_mult := 1.12 if is_in_rage() else 1.0
	var final_dmg := base_dmg if info.get("flat_damage", false) else (base_dmg * _damage_multiplier * spam_dmg_mult * rage_mult)
	hitbox.prepare(
		attack,
		info["height"],
		facing,
		attack_length(attack),
		final_dmg,
		info.get("parriable", true),
		info.get("is_grab", false),
		info.get("knockdown", false),
		info.get("launcher", false),
		info.get("hitstun", 0),
		info.get("hitstop", Balance.HITSTOP_LIGHT),
		info.get("meter_gain", 0.0),
		info.get("chip_ratio", Balance.CHIP_RATIO)
	)

	if attack == &"ultimate":
		meter = maxf(meter - Balance.ULTIMATE_COST, 0.0)
		meter_changed.emit(self, meter)
		_play(&"whoosh_special")
		ultimate_triggered.emit(self)
	elif Balance.SKILL_COOLDOWNS.has(attack):
		skill_cooldowns[attack] = Balance.SKILL_COOLDOWNS[attack]
		cooldowns_changed.emit(self, skill_cooldowns.duplicate())
		_play(&"whoosh_special")
	elif attack in LIGHT_FAMILY:
		_play(&"whoosh_punch")
	else:
		_play(&"whoosh_kick")
	var label := _move_display_name(attack)
	if label != "":
		move_executed.emit(self, label)


func _move_display_name(atk: StringName) -> String:
	match atk:
		&"forward_light":
			if data.id == &"lapu_lapu": return "KAMPILAN THRUST!"
			if data.id == &"leonidas": return "SPARTAN POKE!"
			if data.id == &"musashi": return "NITEN JAB!"
			if data.id == &"simo_hayha": return "BAYONET LUNGE!"
			return "ADVANCING STRIKE!"
		&"back_light":
			if data.id == &"lapu_lapu": return "KALASAG CHECK!"
			if data.id == &"leonidas": return "SHIELD CHECK!"
			if data.id == &"simo_hayha": return "BAYONET KICK!"
			return "BACKSTEP CHECK!"
		&"forward_heavy":
			if data.id == &"lapu_lapu": return "KALASAG CLEAVE!"
			if data.id == &"leonidas": return "PHALANX DRIVE!"
			if data.id == &"musashi": return "CROSS CUT!"
			if data.id == &"simo_hayha": return "BOLT SNIPE!"
			if data.id == &"zeus": return "THUNDER SMASH!"
			if data.id == &"thor": return "MJOLNIR CRUSH!"
			return "HEAVY LUNGE!"
		&"back_heavy":
			if data.id == &"lapu_lapu": return "RISING TIDE!"
			if data.id == &"leonidas": return "SKY SPEAR!"
			if data.id == &"musashi": return "SWALLOW ANTI-AIR!"
			if data.id == &"simo_hayha": return "ANTI-AIR SHOT!"
			return "ANTI-AIR!"
		&"jump_heavy":
			if data.id == &"lapu_lapu": return "TYPHOON CRASH!"
			return "AIR CRASH!"
		&"forward_seize":
			return "KALASAG BREAKER!" if data.id == &"lapu_lapu" else "GUARD CRUSH!"
		&"back_seize":
			return "ARCTIC BACKFLIP!" if data.id == &"simo_hayha" else "EVADE STEP!"
		&"crouch_seize":
			return "TIDAL SWEEP!" if data.id == &"lapu_lapu" else "LOW SWEEP!"
		&"jump_seize":
			return "AIR SLAM!"
		&"feint_step":
			return "SHADOW STEP!"
		&"power_launcher":
			return "SKY LAUNCHER!"
		&"skill_forward":
			match data.id:
				&"zeus": return "LIGHTNING BLINK!"
				&"thor": return "BIFROST HAMMER!"
				&"susanoo": return "TEMPEST FLASH!"
				&"anubis": return "DUAT PHANTOM!"
				&"simo_hayha": return "SNOW-STEP VAULT!"
				&"leonidas": return "PHALANX RAM!"
				&"lapu_lapu": return "KALASAG CHARGE!"
				&"musashi": return "FLASH IAIDO!"
				&"ragnar": return "BERSERKER LEAP!"
				&"julius_caesar": return "IMPERIAL THRUST!"
				_: return "TIGER RUSH!"
		&"skill_back":
			match data.id:
				&"simo_hayha": return "WHITE DEATH DISENGAGE!"
				&"zeus": return "STORM BLINK!"
				&"thor": return "STORM HAMMER!"
				&"susanoo": return "GALE RETREAT!"
				&"anubis": return "UNDERWORLD PHASE!"
				&"julius_caesar": return "REARGUARD LEGION!"
				&"ragnar": return "RETREATING AXE!"
				&"lapu_lapu": return "KALASAG COUNTER!"
				_: return "EVASIVE COUNTER!"
		&"skill_ground":
			return "MACTAN WAVE!" if data.id == &"lapu_lapu" else "SIGNATURE SKILL!"
		&"skill_air":
			return "TYPHOON LEAP!" if data.id == &"lapu_lapu" else "AERIAL SKILL!"
		&"skill_low":
			return "TIDAL SLASH!" if data.id == &"lapu_lapu" else "LOW SKILL!"
	return ""


func _process_attack(bits: int, pressed: int) -> void:
	# 1. Forgiving startup-cancel into F+G skill.
	if input_enabled and attack_phase == Phase.STARTUP and _phase_frames <= Balance.SKILL_CANCEL_WINDOW_FRAMES:
		var cancel_to_skill := (attack_name in LIGHT_FAMILY and (pressed & InputSource.HEAVY) != 0) \
			or (attack_name in HEAVY_FAMILY and (pressed & InputSource.LIGHT) != 0)
		if cancel_to_skill:
			var is_air := (not grounded) or ((bits & InputSource.UP) != 0)
			var is_low := (bits & InputSource.DOWN) != 0
			var move_dir := int((bits & InputSource.RIGHT) != 0) - int((bits & InputSource.LEFT) != 0)
			var target_skill := _chord_skill_name(is_air, is_low, move_dir)
			if is_skill_ready(target_skill):
				move_cooldowns.erase(attack_name)
				if _prev_spam_entry.is_empty():
					spam_heat.erase(_prev_spam_move)
				else:
					spam_heat[_prev_spam_move] = _prev_spam_entry.duplicate()
				if target_skill == &"skill_air" and grounded:
					sim_vel.y = Balance.JUMP_VELOCITY * 0.72
					grounded = false
				_start_attack(target_skill)
				return

	# 2. AAA Hit-Confirm Chain Combo Cancel (Tier 1 -> Tier 2 -> Tier 3 -> Tier 4 Ultimate!).
	if input_enabled and combo_cancel_ready and (attack_phase == Phase.ACTIVE or (attack_phase == Phase.RECOVERY and combo_cancel_frames > 0)):
		var cur_tier: int = int(Balance.ATTACKS[attack_name].get("cancel_tier", 0))
		if cur_tier > 0:
			var next_move := _resolve_attack_input(bits, pressed, not grounded)
			if next_move != &"" and _can_use(next_move):
				var next_tier: int = int(Balance.ATTACKS[next_move].get("cancel_tier", 0))
				if next_tier > cur_tier:
					_face_opponent()
					if Balance.ATTACKS[next_move].get("air_only", false) and grounded:
						sim_vel.y = Balance.JUMP_VELOCITY * 0.68
						grounded = false
					_start_attack(next_move)
					return

	_phase_frames += 1
	var info: Dictionary = Balance.ATTACKS[attack_name]
	match attack_phase:
		Phase.STARTUP:
			var lunge: float = float(info.get("lunge_speed", 0.0))
			var kit: Dictionary = Balance.CHAMPION_KITS.get(data.id, {})
			if attack_name == &"skill_ground" and kit.has("skill_ground_lunge"):
				lunge = float(kit["skill_ground_lunge"])
			elif attack_name == &"skill_forward" and kit.has("skill_forward_lunge"):
				lunge = float(kit["skill_forward_lunge"])
			elif attack_name == &"skill_back" and kit.has("skill_back_lunge"):
				lunge = float(kit["skill_back_lunge"])
			elif attack_name == &"skill_low" and kit.has("skill_low_lunge"):
				lunge = float(kit["skill_low_lunge"])
			if not is_zero_approx(lunge):
				sim_vel.x = float(facing) * lunge
			elif grounded:
				_apply_friction()
			if _phase_frames >= _startup_frames:
				attack_phase = Phase.ACTIVE
				_phase_frames = 0
				hitbox.activate()
				_attack_punch = 1.0 if (attack_name in HEAVY_FAMILY or attack_name == &"ultimate" or Balance.SKILL_COOLDOWNS.has(attack_name) or attack_name == &"forward_seize" or attack_name == &"power_launcher") else 0.55
				_spawn_attack_vfx()
				attack_active_started.emit(self, attack_name)
				if attack_name == &"ultimate":
					if data.weapon == &"thunderbolt":
						_play(&"thunder")
					elif data.weapon == &"rifle":
						_play(&"rifle")
		Phase.ACTIVE:
			if attack_name == &"ultimate":
				_step_ultimate_choreography()
			elif grounded:
				_apply_friction()
			if _phase_frames >= _active_frames:
				attack_phase = Phase.RECOVERY
				_phase_frames = 0
				armor_active = false
				hitbox.deactivate()
		Phase.RECOVERY:
			if combo_cancel_frames > 0:
				combo_cancel_frames -= 1
			if grounded:
				_apply_friction()
			if _phase_frames >= _recovery_frames:
				_cancel_attack()
				hurtbox.set_crouching(false)
				state_machine.change(StateMachine.State.IDLE if grounded else StateMachine.State.JUMP)
				if grounded:
					_face_opponent()


## Dynamic multi-beat movement choreography during every champion's Ultimate
## so NO champion stands stiffly in place while unleashing their Super!
func _step_ultimate_choreography() -> void:
	var dir := float(facing)
	var f := _phase_frames
	match data.id:
		&"zeus":
			# Soars into the sky, hovers crackling with lightning while bolts rain down, then meteor-slams!
			if f == 1:
				sim_vel = Vector2(-dir * 120.0, -560.0)
				grounded = false
			elif f >= 4 and f <= 16:
				sim_vel.y = -Balance.GRAVITY * Balance.DT # mid-air god hover!
				sim_vel.x = move_toward(sim_vel.x, 0.0, 1200.0 * Balance.DT)
			elif f == 17:
				sim_vel = Vector2(dir * 260.0, 760.0)
		&"simo_hayha":
			# Tactical arctic backflip to create maximum sniper range -> braced recoil slide!
			if f == 1:
				sim_vel = Vector2(-dir * 620.0, -340.0)
				grounded = false
				if effects_layer != null:
					CombatVfx.spawn_dust_puff(effects_layer, sim_pos, -facing, 12)
			elif f == 12:
				sim_vel.x = -dir * 340.0
			elif grounded:
				_apply_friction()
		&"julius_caesar":
			# Advancing imperial command -> forward leap surge -> finishing gladius lunge!
			if f <= 7:
				sim_vel.x = dir * 340.0
			elif f == 9:
				sim_vel = Vector2(dir * 420.0, -290.0)
				grounded = false
			elif f == 17:
				sim_vel.x = dir * 420.0
			elif grounded:
				_apply_friction()
		&"leonidas":
			# Blistering 2-stage armored Spartan charge -> leaping spear slam!
			if f <= 10:
				sim_vel.x = dir * 680.0
			elif f == 11:
				sim_vel = Vector2(dir * 460.0, -420.0)
				grounded = false
			elif f == 18:
				sim_vel = Vector2(dir * 300.0, 720.0)
		&"musashi":
			# Anime shadow flash-dash THROUGH the opponent -> crisscrossing blade cuts!
			if f <= 6:
				sim_vel.x = dir * 880.0
			elif f == 9:
				sim_vel.x = -dir * 460.0
			elif f == 14:
				sim_vel.x = dir * 560.0
			elif grounded:
				_apply_friction()
		&"ragnar":
			# Raging Viking leap throwing war-axes from the air -> axe-first Bifrost meteor slam!
			if f == 1:
				sim_vel = Vector2(dir * 440.0, -490.0)
				grounded = false
			elif f == 14:
				sim_vel = Vector2(dir * 280.0, 780.0)
		&"lapu_lapu":
			# Whirling advancing typhoon leap & second cyclone lunge!
			if f == 1:
				sim_vel = Vector2(dir * 540.0, -300.0)
				grounded = false
			elif f == 12:
				sim_vel.x = dir * 580.0
			elif grounded:
				_apply_friction()
		&"thor":
			# Mighty Thunder-God leap skyward hurling Mjolnir -> meteor hammer slam!
			if f == 1:
				sim_vel = Vector2(dir * 380.0, -560.0)
				grounded = false
			elif f == 15:
				sim_vel = Vector2(dir * 320.0, 820.0)
		&"susanoo":
			# Blistering storm-flash dash -> whirling gale ascent -> finishing tempest cleave!
			if f <= 7:
				sim_vel.x = dir * 760.0
			elif f == 9:
				sim_vel = Vector2(dir * 340.0, -440.0)
				grounded = false
			elif f == 18:
				sim_vel = Vector2(dir * 420.0, 620.0)
		&"anubis":
			# Eerie Underworld levitation channeling Scales of Ma'at -> phantom phase lunge!
			if f == 1:
				sim_vel = Vector2(-dir * 160.0, -480.0)
				grounded = false
			elif f >= 4 and f <= 14:
				sim_vel.y = -Balance.GRAVITY * Balance.DT # spectral hover!
				sim_vel.x = move_toward(sim_vel.x, 0.0, 1200.0 * Balance.DT)
			elif f == 15:
				sim_vel = Vector2(dir * 580.0, 480.0)
		_:
			# Nai Khanom Tom: relentless 3-beat advancing blitz -> soaring Flying Tiger-Knee!
			if f == 1 or f == 7 or f == 13:
				sim_vel.x = dir * 560.0
			elif f == 18:
				sim_vel = Vector2(dir * 380.0, -520.0)
				grounded = false
			elif grounded:
				_apply_friction()


func _cancel_attack() -> void:
	attack_name = &""
	attack_phase = Phase.NONE
	_phase_frames = 0
	combo_cancel_ready = false
	combo_cancel_frames = 0
	is_spam_unsafe = false
	armor_active = false
	hitbox.deactivate()


# --- Symmetrical Hit / Parry / Seize Resolution (called by Match) ----------

func evaluate_hitbox_against(defender: Fighter) -> StringName:
	if not hitbox.active or hitbox.has_hit:
		return &""
	if defender == null or not defender.can_be_hit():
		return &""
	if (hitbox.height == &"high" or hitbox.height == &"anti_air") and defender.is_crouching():
		return &""
	if (hitbox.height == &"low" or hitbox.height == &"grab") and defender.is_airborne():
		return &""
	var attack_rect := hitbox.get_rect(sim_pos)
	var defend_rect := defender.hurtbox.get_rect(defender.sim_pos)
	if not attack_rect.intersects(defend_rect):
		return &""
	if hitbox.is_grab:
		return &"grab"
	if hitbox.parriable and defender.is_in_parry_window():
		return &"parry"
	if defender.is_blocking():
		return &"block"
	return &"hit"


func consume_hitbox_hit() -> void:
	hitbox.has_hit = true


func receive_parry_stagger(defender: Fighter) -> void:
	var away := 1.0 if sim_pos.x >= defender.sim_pos.x else -1.0
	_cancel_attack()
	_clear_chord()
	_clear_parry_hold()
	hurtbox.set_crouching(false)
	_stun_frames = Balance.PARRY_STAGGER_FRAMES
	sim_vel.x = away * Balance.PARRY_PUSHBACK
	state_machine.force(StateMachine.State.PARRIED)
	_flash_visual(Color(1.0, 0.88, 0.3))


func receive_parry_success(attacker: Fighter) -> void:
	parry_succeeded_this_hold = true
	parry_window_frames = 0
	block_lockout_frames = 0
	_stun_frames = Balance.PARRY_SUCCESS_ANIM_FRAMES
	sim_vel.x = 0.0
	state_machine.force(StateMachine.State.PARRY)
	add_meter(Balance.METER_GAIN_PARRY)
	_flash_visual(Color(1.0, 0.9, 0.3))
	_spawn_spark(attacker, attacker.hitbox.attack_name, false, true)
	if effects_layer != null:
		CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(float(facing) * 42.0, -105.0), Color(1.0, 0.92, 0.3), 135.0, 0.28, 1.0, 9.0)
		CombatVfx.spawn_radial_burst(effects_layer, sim_pos + Vector2(float(facing) * 42.0, -105.0), Color(1.0, 0.92, 0.35), 14, 380.0, 0.30)
	_play(&"parry_success")
	parry_landed.emit(self, attacker)


func start_seize_lock(defender: Fighter) -> void:
	_cancel_attack()
	_clear_chord()
	_clear_parry_hold()
	seize_frames = Balance.SEIZE_THROW_FRAMES
	sim_vel = Vector2.ZERO
	state_machine.force(StateMachine.State.SEIZE_THROW)
	defender.enter_grabbed(self)
	_play(&"hit_light")
	seize_started.emit(self, defender)


func enter_grabbed(attacker: Fighter) -> void:
	_cancel_attack()
	_clear_chord()
	_clear_parry_hold()
	hurtbox.set_crouching(false)
	sim_vel = Vector2.ZERO
	facing = -attacker.facing
	state_machine.force(StateMachine.State.GRABBED)


static func resolve_seize_tech(attacker: Fighter, defender: Fighter) -> void:
	var away_def := 1.0 if defender.sim_pos.x >= attacker.sim_pos.x else -1.0
	attacker._cancel_attack()
	defender._cancel_attack()
	attacker._clear_chord()
	defender._clear_chord()
	attacker._clear_parry_hold()
	defender._clear_parry_hold()
	attacker.seize_frames = 0
	attacker._stun_frames = Balance.SEIZE_TECH_RECOVERY_FRAMES
	defender._stun_frames = Balance.SEIZE_TECH_RECOVERY_FRAMES
	attacker.sim_vel = Vector2(-away_def * Balance.SEIZE_TECH_PUSHBACK, 0.0)
	defender.sim_vel = Vector2(away_def * Balance.SEIZE_TECH_PUSHBACK, 0.0)
	attacker.state_machine.force(StateMachine.State.HITSTUN)
	defender.state_machine.force(StateMachine.State.HITSTUN)
	attacker._flash_visual(Color(0.6, 0.9, 1.0))
	defender._flash_visual(Color(0.6, 0.9, 1.0))
	defender._spawn_spark(attacker, &"seize", true, false)
	defender._play(&"block")
	attacker.seize_teched.emit(attacker, defender)


func receive_seize_throw_damage(attacker: Fighter, damage: float, meter_gain: float, sim_frame: int) -> void:
	var away := 1.0 if sim_pos.x >= attacker.sim_pos.x else -1.0
	health = maxf(health - damage, 0.0)
	attacker.register_hit_dealt(damage, meter_gain, sim_frame)
	add_meter(damage * Balance.METER_PER_DAMAGE_TAKEN)
	_spawn_spark(attacker, &"seize", false, false)
	_flash_visual()
	_knock_down(away)
	_play(&"hit_heavy")
	health_changed.emit(self, health)
	hit_landed.emit(attacker, self, damage, false, &"seize", false, 1)


## Returns hitstop frames to apply for crunchy impact feel.
func receive_strike(attacker: Fighter, blocked: bool, sim_frame: int) -> int:
	var move_name := attacker.hitbox.attack_name
	var raw_damage := attacker.hitbox.damage
	var away := 1.0 if sim_pos.x >= attacker.sim_pos.x else -1.0
	var is_counter := (not blocked) and is_counter_vulnerable()
	var combo_num := 0
	var damage := raw_damage
	var hitstop := attacker.hitbox.hitstop_frames

	if blocked:
		damage = raw_damage * attacker.hitbox.chip_ratio
		attacker.register_chip_dealt(damage, sim_frame)
		attacker.add_meter(Balance.METER_GAIN_BLOCKED_ATTACKER)
		add_meter(Balance.METER_GAIN_BLOCKED_DEFENDER)
		hitstop = maxi(2, hitstop - 2)
	else:
		combo_taken += 1
		combo_num = combo_taken
		var scale_mult := Balance.combo_scale(combo_num)
		if is_counter:
			scale_mult *= Balance.COUNTER_DAMAGE_MULT
			hitstop = maxi(hitstop, Balance.HITSTOP_COUNTER)
		damage = raw_damage * scale_mult
		attacker.register_hit_dealt(damage, attacker.hitbox.meter_gain, sim_frame)
		attacker.on_hit_confirmed()
		add_meter(damage * Balance.METER_PER_DAMAGE_TAKEN)

	health = maxf(health - damage, 0.0)
	_spawn_spark(attacker, move_name, blocked, false, is_counter)
	_flash_visual(Color(1.0, 0.45, 0.2) if is_counter else Color.WHITE)

	var atk_info: Dictionary = Balance.ATTACKS.get(move_name, {})
	if blocked and health > 0.0:
		if bool(atk_info.get("guard_crush", false)):
			# Forward+H / Forward+F+G Guard Crush shatters turtling blockers!
			_cancel_attack()
			_clear_chord()
			_clear_parry_hold()
			hurtbox.set_crouching(false)
			_stun_frames = 22
			sim_vel.x = away * Balance.BLOCK_PUSHBACK * 1.35
			state_machine.force(StateMachine.State.PARRIED)
			_flash_visual(Color(1.0, 0.45, 0.15))
			if effects_layer != null:
				CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -104), Color(1.0, 0.45, 0.15), 165.0, 0.30, 1.0, 12.0)
				CombatVfx.spawn_radial_burst(effects_layer, sim_pos + Vector2(0, -104), Color(1.0, 0.55, 0.2), 18, 460.0, 0.30)
			_play(&"hit_heavy", 0.85)
			guard_crushed.emit()
		else:
			_play(&"block")
			sim_vel.x = away * Balance.BLOCK_PUSHBACK
	elif armor_active and health > 0.0 and move_name != &"ultimate" and not attacker.hitbox.is_grab:
		# Spartan / Berserker Armor: absorbs 1 hit cleanly without interrupting the swing!
		armor_active = false
		health = minf(max_health, health + damage * 0.45) # 45% armor damage mitigation
		_flash_visual(Color(1.0, 0.85, 0.25))
		if effects_layer != null:
			CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -100), Color(1.0, 0.85, 0.3), 105.0, 0.22, 1.0, 8.0)
		_play(&"block", 0.8)
	else:
		var was_ult := (state_machine.state == StateMachine.State.ATTACK and attack_name == &"ultimate")
		_cancel_attack()
		_clear_chord()
		_clear_parry_hold()
		hurtbox.set_crouching(false)
		ultimate_interrupted.emit(self)
		if was_ult and effects_layer != null:
			CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -105), Color(1.0, 0.32, 0.25), 140.0, 0.26, 1.0, 9.0)
		if is_counter and effects_layer != null:
			CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -105), Color(1.0, 0.45, 0.15), 130.0, 0.26, 1.0, 9.0)
			CombatVfx.spawn_radial_burst(effects_layer, sim_pos + Vector2(0, -105), Color(1.0, 0.55, 0.2), 14, 420.0, 0.30)
		if health <= 0.0 or attacker.hitbox.knockdown:
			_knock_down(away)
			_play(&"hit_special" if move_name == &"ultimate" else &"hit_heavy")
		elif attacker.hitbox.launcher:
			# Anti-air / G+H Sky Launcher pops opponent cleanly for jump & double-jump air juggles!
			var launch_v: Vector2 = Vector2(130.0, -690.0) if bool(atk_info.get("super_launch", false)) else Balance.ANTI_AIR_LAUNCH
			_stun_frames = attacker.hitbox.hitstun_frames + (Balance.COUNTER_EXTRA_HITSTUN if is_counter else 0)
			sim_vel = Vector2(away * launch_v.x, launch_v.y)
			grounded = false
			state_machine.force(StateMachine.State.HITSTUN)
			_play(&"hit_heavy")
		else:
			_stun_frames = maxi(1, attacker.hitbox.hitstun_frames + (Balance.COUNTER_EXTRA_HITSTUN if is_counter else 0))
			state_machine.force(StateMachine.State.HITSTUN)
			# Simo's Back+F Bayonet Push-Kick shoves brawlers far away to keep sniper range!
			var push_mult := 1.85 if (attacker.data.id == &"simo_hayha" and move_name == &"back_light") else (0.72 if combo_num <= 2 else 1.0)
			sim_vel.x = away * Balance.HIT_PUSHBACK * push_mult
			var pitch := clampf(1.0 + float(maxi(combo_num - 1, 0)) * 0.07, 1.0, 1.4)
			_play(&"hit_light" if move_name in LIGHT_FAMILY else &"hit_heavy", pitch)

	if is_cornered():
		# Allow rewarding 4-5 hit corner combos while still preventing infinite wall-traps!
		var recoil := (Balance.BLOCK_PUSHBACK * 0.85) if blocked else (Balance.HIT_PUSHBACK * 0.55)
		attacker.sim_vel.x = -away * recoil
		if not blocked:
			corner_hits_taken += 1
			if combo_num >= 6 and health > 0.0:
				_knock_down(-away)
	health_changed.emit(self, health)
	hit_landed.emit(attacker, self, damage, blocked, move_name, is_counter, combo_num)
	return hitstop


## Called by Match when a Projectile or Ultimate FX strikes this fighter.
func receive_projectile_hit(attacker: Fighter, proj: Projectile, blocked: bool, sim_frame: int) -> int:
	var away := 1.0 if sim_pos.x >= proj.sim_pos.x else -1.0
	var combo_num := 0
	var base_dmg := proj.damage
	var sniper_label := ""
	# Simo Häyhä ("The White Death") sniper distance scaling: deadly at long range!
	if attacker != null and attacker.data.id == &"simo_hayha":
		var shot_dist: float = absf(attacker.sim_pos.x - sim_pos.x)
		var dist_mult: float = Balance.simo_distance_multiplier(shot_dist)
		base_dmg *= dist_mult
		if not blocked:
			if shot_dist >= 640.0:
				sniper_label = "DEADEYE! +70%"
			elif shot_dist >= 420.0:
				sniper_label = "LONG SHOT! +40%"
	var damage := base_dmg
	var hitstop := proj.hitstop_frames

	if blocked:
		damage = base_dmg * proj.chip_ratio
		attacker.register_chip_dealt(damage, sim_frame)
		attacker.add_meter(Balance.METER_GAIN_BLOCKED_ATTACKER)
		add_meter(Balance.METER_GAIN_BLOCKED_DEFENDER)
		hitstop = maxi(2, hitstop - 2)
	else:
		combo_taken += 1
		combo_num = combo_taken
		var scale_mult := 1.0 if proj.is_ultimate else Balance.combo_scale(combo_num)
		damage = base_dmg * scale_mult
		attacker.register_hit_dealt(damage, proj.meter_gain, sim_frame)
		add_meter(damage * Balance.METER_PER_DAMAGE_TAKEN)
		if sniper_label != "":
			sniper_shot_landed.emit(sniper_label)
			hitstop = maxi(hitstop, 7)
			if effects_layer != null:
				CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -104), Color(0.75, 0.96, 1.0), 145.0, 0.28, 1.0, 10.0)

	health = maxf(health - damage, 0.0)
	_spawn_spark(attacker, proj.move_name, blocked, false, proj.is_ultimate or sniper_label != "")
	_flash_visual(Color(0.78, 0.96, 1.0) if sniper_label != "" else (Color(1.0, 0.9, 0.35) if proj.is_ultimate else Color.WHITE))

	if blocked and health > 0.0:
		_play(&"block")
		sim_vel.x = away * Balance.BLOCK_PUSHBACK * 0.85
	else:
		var was_ult := (state_machine.state == StateMachine.State.ATTACK and attack_name == &"ultimate")
		_cancel_attack()
		_clear_chord()
		_clear_parry_hold()
		hurtbox.set_crouching(false)
		ultimate_interrupted.emit(self)
		if was_ult and effects_layer != null:
			CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -105), Color(1.0, 0.32, 0.25), 140.0, 0.26, 1.0, 9.0)
		var is_last_hit := proj.hits_left <= 1
		if health <= 0.0 or (proj.knockdown and is_last_hit):
			_knock_down(away)
			_play(&"hit_special" if proj.is_ultimate else &"hit_heavy")
		else:
			_stun_frames = maxi(14, proj.hitstun_frames)
			state_machine.force(StateMachine.State.HITSTUN)
			sim_vel.x = away * Balance.HIT_PUSHBACK * 0.55
			var pitch := clampf(1.0 + float(maxi(combo_num - 1, 0)) * 0.08, 1.0, 1.45)
			_play(&"hit_special" if proj.is_ultimate else &"hit_heavy", pitch)

	health_changed.emit(self, health)
	hit_landed.emit(attacker, self, damage, blocked, proj.move_name, false, combo_num)
	return hitstop


func register_hit_dealt(damage: float, meter_gain: float, sim_frame: int) -> void:
	match_damage_dealt += damage
	last_hit_frame = sim_frame
	if meter_gain > 0.0:
		add_meter(meter_gain)


func register_chip_dealt(damage: float, sim_frame: int) -> void:
	match_damage_dealt += damage
	last_hit_frame = sim_frame


func add_meter(amount: float) -> void:
	meter = minf(meter + amount, Balance.METER_MAX)
	meter_changed.emit(self, meter)


func _knock_down(away: float) -> void:
	_kd_landed = false
	_ko_from_knockdown = false
	state_machine.force(StateMachine.State.KNOCKDOWN)
	var launch_x := away * Balance.KNOCKDOWN_LAUNCH.x
	# Corner wall-bounce: if knocked down pinned on the wall, bounce slightly inward instead of sticking!
	if is_cornered():
		var wall_dir := -1.0 if sim_pos.x <= _min_x() + 10.0 else 1.0
		launch_x = -wall_dir * Balance.CORNER_WALL_BOUNCE_X
	# Slightly lower launch arc on K.O. so the defeated body lands solidly on the ground instead of lingering in mid-air!
	var launch_y: float = Balance.KNOCKDOWN_LAUNCH.y * (0.68 if health <= 0.0 else 1.0)
	sim_vel = Vector2(launch_x, launch_y)
	grounded = false
	if effects_layer != null:
		CombatVfx.spawn_dust_puff(effects_layer, sim_pos, int(signf(launch_x)), 10)
		CombatVfx.spawn_ground_shatter(effects_layer, Vector2(sim_pos.x, Balance.FLOOR_Y), data.accent_color, 0.72)
	_play(&"knockdown")


func _apply_friction() -> void:
	sim_vel.x = move_toward(sim_vel.x, 0.0, Balance.GROUND_FRICTION * Balance.DT)


func _face_opponent() -> void:
	if opponent == null:
		return
	var dx := opponent.sim_pos.x - sim_pos.x
	if absf(dx) > 4.0:
		facing = 1 if dx > 0.0 else -1


func _min_x() -> float:
	return Balance.WALL_THICKNESS + Balance.BODY_HALF_WIDTH


func _max_x() -> float:
	return arena_width - Balance.WALL_THICKNESS - Balance.BODY_HALF_WIDTH


# --- Plain state export/import (Section 13.3 netcode & rollback readiness) -

func export_state() -> Dictionary:
	return {
		"sim_pos": sim_pos,
		"sim_vel": sim_vel,
		"grounded": grounded,
		"health": health,
		"meter": meter,
		"facing": facing,
		"input_enabled": input_enabled,
		"attack_name": attack_name,
		"attack_phase": int(attack_phase),
		"attack_serial": attack_serial,
		"phase_frames": _phase_frames,
		"startup_frames": _startup_frames,
		"active_frames": _active_frames,
		"recovery_frames": _recovery_frames,
		"stun_frames": _stun_frames,
		"seize_frames": seize_frames,
		"combo_cancel_ready": combo_cancel_ready,
		"combo_cancel_frames": combo_cancel_frames,
		"combo_taken": combo_taken,
		"skill_cooldowns": skill_cooldowns.duplicate(),
		"move_cooldowns": move_cooldowns.duplicate(),
		"spam_heat": spam_heat.duplicate(true),
		"is_spam_unsafe": is_spam_unsafe,
		"dash_frames": dash_frames,
		"dash_dir": dash_dir,
		"dash_cooldown_frames": dash_cooldown_frames,
		"last_tap_dir": last_tap_dir,
		"last_tap_frames": last_tap_frames,
		"prev_input_bits": prev_input_bits,
		"chord_pending_bit": chord_pending_bit,
		"chord_timer": chord_timer,
		"chord_crouching": chord_crouching,
		"chord_up": chord_up,
		"chord_airborne": chord_airborne,
		"chord_move_dir": chord_move_dir,
		"parry_window_frames": parry_window_frames,
		"block_hold_frames": block_hold_frames,
		"block_lockout_frames": block_lockout_frames,
		"parry_active_hold": parry_active_hold,
		"parry_succeeded_this_hold": parry_succeeded_this_hold,
		"match_damage_dealt": match_damage_dealt,
		"last_hit_frame": last_hit_frame,
		"state_machine": state_machine.export_state(),
		"hitbox": hitbox.export_state(),
		"hurtbox": hurtbox.export_state(),
	}


func import_state(state_data: Dictionary) -> void:
	sim_pos = state_data["sim_pos"]
	sim_vel = state_data["sim_vel"]
	grounded = state_data["grounded"]
	health = state_data["health"]
	meter = state_data["meter"]
	facing = state_data["facing"]
	input_enabled = state_data["input_enabled"]
	attack_name = state_data["attack_name"]
	attack_phase = int(state_data["attack_phase"]) as Phase
	attack_serial = state_data["attack_serial"]
	_phase_frames = state_data["phase_frames"]
	_startup_frames = state_data["startup_frames"]
	_active_frames = state_data["active_frames"]
	_recovery_frames = state_data["recovery_frames"]
	_stun_frames = state_data["stun_frames"]
	seize_frames = state_data["seize_frames"]
	combo_cancel_ready = state_data["combo_cancel_ready"]
	combo_cancel_frames = state_data["combo_cancel_frames"]
	combo_taken = state_data["combo_taken"]
	skill_cooldowns = (state_data["skill_cooldowns"] as Dictionary).duplicate()
	move_cooldowns = (state_data["move_cooldowns"] as Dictionary).duplicate()
	spam_heat = (state_data["spam_heat"] as Dictionary).duplicate(true)
	is_spam_unsafe = state_data["is_spam_unsafe"]
	dash_frames = state_data["dash_frames"]
	dash_dir = state_data["dash_dir"]
	dash_cooldown_frames = state_data["dash_cooldown_frames"]
	last_tap_dir = state_data["last_tap_dir"]
	last_tap_frames = state_data["last_tap_frames"]
	prev_input_bits = state_data["prev_input_bits"]
	chord_pending_bit = state_data["chord_pending_bit"]
	chord_timer = state_data["chord_timer"]
	chord_crouching = state_data["chord_crouching"]
	chord_up = state_data["chord_up"]
	chord_airborne = state_data["chord_airborne"]
	chord_move_dir = state_data["chord_move_dir"]
	parry_window_frames = state_data["parry_window_frames"]
	block_hold_frames = state_data["block_hold_frames"]
	block_lockout_frames = state_data["block_lockout_frames"]
	parry_active_hold = state_data["parry_active_hold"]
	parry_succeeded_this_hold = state_data["parry_succeeded_this_hold"]
	match_damage_dealt = state_data["match_damage_dealt"]
	last_hit_frame = state_data["last_hit_frame"]
	state_machine.import_state(state_data["state_machine"])
	hitbox.import_state(state_data["hitbox"])
	hurtbox.import_state(state_data["hurtbox"])
	sync_visuals()


# --- Visuals & Audio (react only; never change fight state) ----------------

func _draw() -> void:
	# Soft ground contact shadow under the fighter (stays on floor while jumping).
	var altitude := maxf(0.0, Balance.FLOOR_Y - sim_pos.y)
	var shadow_scale := clampf(1.0 - altitude / 420.0, 0.4, 1.0)
	var rx := 52.0 * shadow_scale
	var ry := 12.0 * shadow_scale
	var alpha := 0.36 * shadow_scale
	draw_set_transform(Vector2(0.0, altitude), 0.0, Vector2(1.0, ry / maxf(rx, 1.0)))
	draw_circle(Vector2.ZERO, rx, Color(0.02, 0.02, 0.05, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _spawn_attack_vfx() -> void:
	if effects_layer == null or data == null:
		return
	var dir := float(facing)
	var accent := data.accent_color
	var center := sim_pos + Vector2(dir * 54.0, -104.0)
	var is_heavy := attack_name in HEAVY_FAMILY
	var is_low := attack_name == &"crouch_light" or attack_name == &"crouch_heavy" or attack_name == &"crouch_seize" or attack_name == &"skill_low"
	if is_low:
		center = sim_pos + Vector2(dir * 56.0, -38.0)

	# Directional kinetic VFX geometry so EVERY WASD + F/G/H move looks & feels distinct across all 11 champions!
	match attack_name:
		&"forward_light":
			# Crisp piercing forward thrust/jab streak!
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 20.0, 0.0), facing, accent, 76.0, -0.52, 0.52, 13.0, 0.16)
			CombatVfx.spawn_radial_burst(effects_layer, center + Vector2(dir * 66.0, 0.0), accent.lightened(0.25), 6, 240.0, 0.16)
		&"back_light":
			# Defensive check / Shield-Check Wave (Kalasag for Lapu-Lapu, Bronze Lambda for Leonidas!)
			if data.id == &"lapu_lapu" or data.id == &"leonidas":
				var shield_col := Color(0.32, 0.96, 0.92) if data.id == &"lapu_lapu" else Color(1.0, 0.80, 0.25)
				CombatVfx.spawn_shockwave_ring(effects_layer, center + Vector2(dir * 18.0, 0.0), shield_col, 92.0, 0.20, 0.65, 9.0)
				CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 10.0, 0.0), facing, shield_col.lightened(0.2), 68.0, -0.95, 0.95, 12.0, 0.16)
			else:
				CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 12.0, -4.0), facing, accent, 64.0, 0.95, -0.95, 11.0, 0.15)
		&"jump_light":
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 12.0, 14.0), facing, accent, 68.0, -0.45, 1.05, 11.0, 0.16)
		&"crouch_light":
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 14.0, 4.0), facing, accent, 68.0, 0.45, 1.35, 10.0, 0.15)
		&"forward_heavy":
			# Heavy charging signature cleave + double crescent + dust kick!
			CombatVfx.spawn_dust_puff(effects_layer, sim_pos, -facing, 7)
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 16.0, 0.0), facing, accent, 104.0, -1.35, 1.25, 18.0, 0.22)
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 22.0, 6.0), facing, accent.lightened(0.45), 86.0, -1.15, 1.05, 9.0, 0.18)
			if data.id == &"lapu_lapu" or data.id == &"leonidas":
				CombatVfx.spawn_shockwave_ring(effects_layer, center + Vector2(dir * 26.0, 0.0), accent, 112.0, 0.22, 0.75, 9.0)
		&"back_heavy":
			# Steep rising anti-air uppercut crescent reaching into the sky!
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 12.0, -34.0), facing, accent, 98.0, 0.85, -1.55, 17.0, 0.22)
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 16.0, -42.0), facing, Color(1.0, 0.98, 0.9), 82.0, 0.55, -1.45, 8.0, 0.18)
		&"jump_heavy":
			# Crashing diagonal meteor slash!
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 18.0, 18.0), facing, accent, 96.0, -1.45, 1.15, 17.0, 0.22)
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 22.0, 22.0), facing, Color(1.0, 0.98, 0.92), 78.0, -1.25, 0.95, 8.0, 0.18)
		&"crouch_heavy", &"crouch_seize":
			# Wide ground-skimming sweep crescent + floor sparks!
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 18.0, 8.0), facing, accent, 92.0, 0.25, 1.45, 15.0, 0.20)
			CombatVfx.spawn_dust_puff(effects_layer, Vector2(sim_pos.x + dir * 64.0, Balance.FLOOR_Y), facing, 8)
		&"forward_seize":
			# Blazing Guard-Crush Breaker Wave!
			var crush_col := Color(1.0, 0.56, 0.18)
			CombatVfx.spawn_shockwave_ring(effects_layer, center + Vector2(dir * 24.0, 0.0), crush_col, 128.0, 0.24, 0.80, 12.0)
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 18.0, 0.0), facing, accent, 90.0, -1.1, 1.1, 15.0, 0.20)
		&"power_launcher":
			# Sky-piercing rising juggle uppercut!
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 14.0, -42.0), facing, accent, 108.0, 1.05, -1.65, 19.0, 0.24)
			CombatVfx.spawn_energy_pillar(effects_layer, sim_pos + Vector2(dir * 52.0, 0.0), accent, 58.0, 0.26)
		&"feint_step":
			CombatVfx.spawn_dust_puff(effects_layer, sim_pos, -facing, 10)
			CombatVfx.spawn_shockwave_ring(effects_layer, sim_pos + Vector2(0, -90), accent, 88.0, 0.20, 0.55, 7.0)
		&"light":
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 8.0, -6.0), facing, accent, 62.0, -0.85, 0.85, 10.0, 0.14)
		&"heavy":
			CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 14.0, 0.0), facing, accent, 92.0, -1.30, 1.15, 16.0, 0.20)

	# Champion-specific signature elemental accents layered on top of normals!
	match data.id:
		&"zeus":
			if is_heavy or attack_name == &"forward_light":
				var tip := center + Vector2(dir * 96.0, -42.0 if attack_name == &"back_heavy" else (30.0 if is_low else -8.0))
				CombatVfx.spawn_lightning_arc(effects_layer, sim_pos + Vector2(dir * 26.0, -112.0), tip, Color(1.0, 0.94, 0.38), 0.22, 6.0, 2)
				CombatVfx.spawn_radial_burst(effects_layer, tip, Color(1.0, 0.95, 0.55), 8, 260.0, 0.22)
		&"musashi":
			if is_heavy:
				CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(dir * 10.0, 8.0), facing, Color(0.95, 0.98, 1.0), 78.0, 1.15, -1.15, 8.0, 0.16)
		&"lapu_lapu":
			if is_heavy or attack_name in [&"forward_light", &"back_light", &"forward_seize"]:
				CombatVfx.spawn_radial_burst(effects_layer, center + Vector2(dir * 42.0, 0.0), Color(0.35, 0.98, 0.94), 8, 290.0, 0.18)
		&"nai_khanom_tom":
			if is_heavy:
				CombatVfx.spawn_shockwave_ring(effects_layer, center + Vector2(dir * 28.0, 0), Color(1.0, 0.82, 0.28), 78.0, 0.18, 1.0, 6.0)
		&"thor":
			if is_heavy or attack_name == &"forward_light":
				var tip := center + Vector2(dir * 94.0, -30.0 if attack_name == &"back_heavy" else 12.0)
				CombatVfx.spawn_lightning_arc(effects_layer, sim_pos + Vector2(dir * 22.0, -110.0), tip, Color(0.35, 0.88, 1.0), 0.22, 6.5, 2)
				if is_heavy:
					CombatVfx.spawn_shockwave_ring(effects_layer, tip, Color(0.35, 0.88, 1.0), 92.0, 0.22, 1.0, 7.0)
		&"susanoo":
			if is_heavy:
				CombatVfx.spawn_slash_arc(effects_layer, center + Vector2(0, 8), facing, Color(0.68, 0.42, 1.0), 94.0, 1.2, -1.2, 10.0, 0.18)
		&"anubis":
			if is_heavy:
				CombatVfx.spawn_radial_burst(effects_layer, center + Vector2(dir * 45.0, 0), Color(0.96, 0.78, 0.28), 10, 320.0, 0.22)


func _spawn_spark(attacker: Fighter, move_name: StringName, blocked: bool, is_parry: bool, big_override: bool = false) -> void:
	var spark := HIT_SPARK_SCENE.instantiate() as HitSpark
	var height := 105.0
	if move_name == &"light" or move_name == &"back_light":
		height = 140.0
	elif move_name == &"back_heavy":
		height = 155.0
	elif move_name == &"crouch_light" or move_name == &"crouch_heavy" or move_name == &"skill_low":
		height = 48.0
	if is_crouching():
		height = minf(height, 80.0)
	var accent := Color(1.0, 0.88, 0.25) if is_parry else attacker.data.accent_color
	var is_big := big_override or move_name == &"ultimate" or move_name == &"forward_heavy" or is_parry
	spark.setup(blocked, is_big, accent, is_parry)
	var parent: Node = effects_layer if effects_layer != null else get_parent()
	parent.add_child(spark)
	var contact_x := sim_pos.x + (attacker.sim_pos.x - sim_pos.x) * 0.35
	spark.global_position = Vector2(contact_x, sim_pos.y - height)


func _play(key: StringName, pitch: float = 1.0) -> void:
	if not SOUNDS.has(key):
		return
	audio.stream = SOUNDS[key]
	audio.pitch_scale = pitch
	audio.play()


func _setup_aura(_warrior: WarriorData) -> void:
	if _aura != null:
		_aura.queue_free()
		_aura = null
	_aura = FighterAura.new()
	_aura.name = "FighterAura"
	add_child(_aura)
	move_child(_aura, 0)


func _spawn_afterimage() -> void:
	if not sprite.visible or sprite.sprite_frames == null or effects_layer == null:
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = sprite.flip_h
	ghost.scale = sprite.scale
	ghost.global_position = global_position + sprite.position
	ghost.z_index = 0
	var c := data.accent_color
	ghost.modulate = Color(c.r, c.g, c.b, 0.55)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ghost.material = mat
	effects_layer.add_child(ghost)
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, 0.18)
	tw.tween_callback(ghost.queue_free)


func _flash_visual(color: Color = Color.WHITE) -> void:
	rig.flash(color)
	_sprite_flash = 0.85
	if _sprite_mat != null:
		_sprite_mat.set_shader_parameter(&"flash_color", Vector3(color.r, color.g, color.b))
		_sprite_mat.set_shader_parameter(&"flash_amount", _sprite_flash)


func _process(delta: float) -> void:
	if _sprite_flash > 0.0:
		_sprite_flash = maxf(_sprite_flash - delta * 6.5, 0.0)
		if _sprite_mat != null:
			_sprite_mat.set_shader_parameter(&"flash_amount", _sprite_flash)
	if _landing_squash > 0.0:
		_landing_squash = maxf(_landing_squash - delta * 9.5, 0.0)
	if _attack_punch > 0.0:
		_attack_punch = maxf(_attack_punch - delta * 11.0, 0.0)

	# Crisp AAA squash-and-stretch with feet mathematically glued to y = 0.0!
	var sx := 2.0 + _landing_squash * 0.16 + _attack_punch * 0.14
	var sy := 2.0 - _landing_squash * 0.14 - _attack_punch * 0.07
	sprite.scale = Vector2(sx, sy)
	sprite.position.y = -60.0 * sy


func _select_attack_frame(fc: int) -> int:
	if fc <= 1:
		return 0
	# True fighting-game keyframe curve:
	# Startup -> anticipation wind-up frames
	# Active  -> instant snap to peak strike/extension frames!
	# Recovery -> smooth follow-through & stance return (never rushing 4 frames in 33ms!)
	var peak_start := 1
	var peak_end := 1
	if fc == 3:
		peak_start = 1; peak_end = 1
	elif fc == 4:
		peak_start = 1; peak_end = 2
	elif fc == 5:
		peak_start = 2; peak_end = 3
	elif fc == 6:
		peak_start = 2; peak_end = 3
	else:
		# 8–10 frame Ultimates: 0..2 ignition, 3..fc-3 blazing flurry, last 2 heroic finish!
		peak_start = maxi(2, int(floor(float(fc) * 0.28)))
		peak_end = mini(fc - 2, int(floor(float(fc) * 0.78)))

	match attack_phase:
		Phase.STARTUP:
			var t := clampf(float(_phase_frames) / float(maxi(1, _startup_frames)), 0.0, 0.999)
			return clampi(int(floor(t * float(peak_start))), 0, maxi(0, peak_start - 1))
		Phase.ACTIVE:
			var t := clampf(float(_phase_frames) / float(maxi(1, _active_frames)), 0.0, 0.999)
			var span := maxi(1, peak_end - peak_start + 1)
			return clampi(peak_start + int(floor(t * float(span))), peak_start, peak_end)
		Phase.RECOVERY:
			var rec_start := mini(fc - 1, peak_end + 1)
			var span := maxi(1, fc - rec_start)
			var t := clampf(float(_phase_frames) / float(maxi(1, _recovery_frames)), 0.0, 0.999)
			return clampi(rec_start + int(floor(t * float(span))), rec_start, fc - 1)
	return 0


func sync_visuals() -> void:
	global_position = sim_pos
	queue_redraw()
	rig.scale.x = float(facing)
	sprite.flip_h = facing < 0
	var pose := _pose_name()
	var progress := attack_progress()
	if pose == &"getup":
		progress = clampf(float(state_machine.frames_in_state) / float(Balance.GETUP_FRAMES), 0.0, 1.0)
	elif pose == &"seize_throw":
		progress = clampf(float(state_machine.frames_in_state) / float(Balance.SEIZE_THROW_FRAMES), 0.0, 1.0)
	rig.set_pose(pose, progress, meter >= Balance.ULTIMATE_COST, block_lockout_frames > 0)

	if sprite.visible and sprite.sprite_frames != null:
		var anim := _resolve_sprite_anim(pose)
		if anim != &"":
			var fc := sprite.sprite_frames.get_frame_count(anim)
			if state_machine.state == StateMachine.State.ATTACK and fc >= 2:
				if sprite.animation != anim:
					sprite.animation = anim
				sprite.pause()
				sprite.frame = _select_attack_frame(fc)
			elif state_machine.state == StateMachine.State.KNOCKDOWN and fc >= 2:
				# Altitude-locked knockdown: NEVER show lying-flat frame while still in mid-air!
				if sprite.animation != anim:
					sprite.animation = anim
				sprite.pause()
				if not grounded:
					sprite.frame = 0 if sim_vel.y < -60.0 else mini(1, fc - 1)
				else:
					sprite.frame = mini(2, fc - 1) if state_machine.frames_in_state < 18 else (fc - 1)
			elif state_machine.state == StateMachine.State.KO and fc >= 2:
				# Ground-locked K.O.: stays flat on the floor without standing back up or floating!
				if sprite.animation != anim:
					sprite.animation = anim
				sprite.pause()
				if _ko_from_knockdown:
					sprite.frame = fc - 1
				elif not grounded:
					sprite.frame = mini(1, fc - 1)
				else:
					var ko_f := clampi(state_machine.frames_in_state / 6, 0, fc - 1)
					sprite.frame = ko_f
			else:
				sprite.speed_scale = _compute_sprite_speed_scale(anim)
				if sprite.animation != anim:
					sprite.play(anim)
				elif sprite.sprite_frames.get_animation_loop(anim) and not sprite.is_playing():
					sprite.play(anim)

	# Dynamic FighterAura + Shader Silhouette Rim-Glow (radiates organically from the warrior!)
	var is_ult := state_machine.state == StateMachine.State.ATTACK and attack_name == &"ultimate"
	var ult_ready := meter >= Balance.ULTIMATE_COST
	var rage := is_in_rage()
	var aura_lvl := 0.0
	var aura_col := data.accent_color
	if is_ult:
		aura_lvl = 1.0
		aura_col = data.accent_color.lightened(0.25)
	elif rage:
		aura_lvl = 0.72
		aura_col = Color(1.0, 0.28, 0.16)
	elif ult_ready:
		aura_lvl = 0.45
		aura_col = data.accent_color
	if _aura != null:
		_aura.set_aura(aura_lvl, aura_col)
	if _sprite_mat != null:
		_sprite_mat.set_shader_parameter(&"aura_intensity", aura_lvl)
		_sprite_mat.set_shader_parameter(&"aura_color", Vector3(aura_col.r, aura_col.g, aura_col.b))

	# Subtle cyan shimmer during wakeup invulnerability so anti-pinning safety is readable!
	if wakeup_invuln_frames > 0:
		sprite.modulate = Color(0.75, 0.95, 1.0, 0.78 if wakeup_invuln_frames % 4 < 2 else 1.0)
	else:
		sprite.modulate = Color.WHITE

	# Crisp AAA kinetic anticipation/lunge offset (keeps pixel art razor-sharp with ZERO ugly grounded tilt!).
	var lunge_x := 0.0
	var rot_deg := 0.0
	if state_machine.state == StateMachine.State.ATTACK:
		var prog := attack_progress()
		if attack_name == &"back_seize" or attack_name == &"skill_back" or (attack_name == &"ultimate" and data.id == &"simo_hayha" and not grounded):
			rot_deg = -float(facing) * prog * 360.0
		else:
			var is_back_move := attack_name == &"back_light" or attack_name == &"back_heavy"
			var is_big_move := attack_name in HEAVY_FAMILY or Balance.SKILL_COOLDOWNS.has(attack_name) or attack_name == &"forward_seize" or attack_name == &"power_launcher" or attack_name == &"ultimate"
			match attack_phase:
				Phase.STARTUP:
					var st := clampf(float(_phase_frames) / float(maxi(1, _startup_frames)), 0.0, 1.0)
					lunge_x = -float(facing) * (7.0 if is_big_move else 4.0) * st
				Phase.ACTIVE:
					if is_back_move:
						lunge_x = -float(facing) * 6.0
					else:
						lunge_x = float(facing) * (16.0 if is_big_move else 9.0)
				Phase.RECOVERY:
					var rt := 1.0 - clampf(float(_phase_frames) / float(maxi(1, _recovery_frames)), 0.0, 1.0)
					lunge_x = float(facing) * (10.0 if is_big_move else 5.0) * rt
	sprite.position.x = lunge_x
	sprite.rotation_degrees = rot_deg

	# Ghost afterimage trails on Dash, Heavy Lunges, Evasive Arts, Combo Arts, Skills, and Ultimates!
	var wants_trail := state_machine.state == StateMachine.State.DASH \
		or (state_machine.state == StateMachine.State.ATTACK and (
			attack_name == &"ultimate"
			or Balance.SKILL_COOLDOWNS.has(attack_name)
			or attack_name in [&"feint_step", &"back_seize", &"forward_seize", &"power_launcher", &"forward_heavy", &"back_heavy"]
		))
	if wants_trail:
		_trail_tick += 1
		if _trail_tick % 3 == 0:
			_spawn_afterimage()
	else:
		_trail_tick = 0


func _resolve_sprite_anim(pose: StringName) -> StringName:
	if sprite.sprite_frames.has_animation(pose):
		return pose
	if state_machine.state == StateMachine.State.DASH and sprite.sprite_frames.has_animation(&"walk"):
		return &"walk"
	if state_machine.state == StateMachine.State.ATTACK and Balance.ATTACKS.has(attack_name):
		var fallback: StringName = Balance.ATTACKS[attack_name].get("anim", &"light")
		if sprite.sprite_frames.has_animation(fallback):
			return fallback
	if sprite.sprite_frames.has_animation(&"idle"):
		return &"idle"
	return &""


func _compute_sprite_speed_scale(anim: StringName) -> float:
	if state_machine.state == StateMachine.State.DASH:
		return 1.8
	if state_machine.state != StateMachine.State.ATTACK:
		return 1.0
	var frame_count := sprite.sprite_frames.get_frame_count(anim)
	var base_fps := sprite.sprite_frames.get_animation_speed(anim)
	var total_sim_frames := maxi(1, _startup_frames + _active_frames + _recovery_frames)
	if frame_count <= 0 or base_fps <= 0.0:
		return 1.0
	var natural_duration := float(frame_count) / base_fps
	var desired_duration := float(total_sim_frames) * Balance.DT
	return clampf(natural_duration / desired_duration, 0.25, 4.0)


func _pose_name() -> StringName:
	match state_machine.state:
		StateMachine.State.WALK, StateMachine.State.DASH:
			return &"walk"
		StateMachine.State.CROUCH:
			return &"crouch"
		StateMachine.State.JUMP:
			return &"jump"
		StateMachine.State.BLOCK:
			return &"block"
		StateMachine.State.CROUCH_BLOCK:
			return &"crouch_block"
		StateMachine.State.PARRY:
			return &"parry"
		StateMachine.State.PARRY_FAIL:
			return &"crouch" if hurtbox.crouching else &"parry_fail"
		StateMachine.State.PARRIED:
			return &"parried"
		StateMachine.State.ATTACK:
			return attack_name
		StateMachine.State.SEIZE_THROW:
			return &"seize_throw"
		StateMachine.State.GRABBED:
			return &"grabbed"
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
