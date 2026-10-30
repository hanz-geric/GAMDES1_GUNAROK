class_name CpuBrain
extends InputSource
## Arcade opponent. It follows the same rules as a player (hitstun, one
## attack at a time, walls, meter cost). Only its timing and its block roll
## come from its CpuTier (GDD Table B and Section 6.4). It never reads the
## player's inputs: it reacts to what it can see, after a reaction delay.

const GUARD_TIME := 0.6

var tier: CpuTier
var _rng := RandomNumberGenerator.new()
var _round_no := 1
var _round_time := 0.0
var _attack_timer := 0.0
var _planned_attack: StringName = &""
var _queued_attack: StringName = &""
var _move_dir := 0
var _guard_timer := 0.0
var _read_timer := -1.0
var _reaction_timer := -1.0
var _seen_attack_serial := -1


func _init(cpu_tier: CpuTier) -> void:
	tier = cpu_tier
	_rng.randomize()


func reset_for_round(round_no: int) -> void:
	_round_no = round_no
	_round_time = 0.0
	_planned_attack = &""
	_queued_attack = &""
	_move_dir = 0
	_guard_timer = 0.0
	_read_timer = -1.0
	_reaction_timer = -1.0
	_attack_timer = _next_gap()


func tick(delta: float) -> void:
	_queued_attack = &""
	_move_dir = 0
	if fighter == null or fighter.opponent == null or not fighter.input_enabled:
		return
	_round_time += delta
	var opponent := fighter.opponent
	var dx := opponent.global_position.x - fighter.global_position.x
	var dist := absf(dx)
	var toward := 1 if dx > 0.0 else -1
	_update_guard(delta, opponent, dist)

	# M1, round 1: hold back so the player can explore first (GDD 5.4).
	if _round_no == 1 and _round_time < tier.idle_start_time:
		return

	_attack_timer -= delta
	if _planned_attack == &"" and _attack_timer <= 0.0:
		_planned_attack = _choose_attack()
	if _planned_attack != &"":
		if dist <= fighter.attack_range(_planned_attack) - 12.0:
			_queued_attack = _planned_attack
			_planned_attack = &""
			_guard_timer = 0.0
			_attack_timer = _next_gap()
			return
		if _guard_timer <= 0.0:
			_move_dir = toward
		return
	if _guard_timer > 0.0:
		return
	_move_dir = _positioning(opponent, dist, toward)


func _update_guard(delta: float, opponent: Fighter, dist: float) -> void:
	if _guard_timer > 0.0:
		_guard_timer -= delta
	# A new attack from the opponent: roll to block after the reaction delay.
	if opponent.attack_serial != _seen_attack_serial:
		_seen_attack_serial = opponent.attack_serial
		if opponent.is_attacking():
			_reaction_timer = tier.reaction_delay
	if _reaction_timer >= 0.0:
		_reaction_timer -= delta
		if _reaction_timer < 0.0 and opponent.is_attacking():
			_roll_block()
	# A threat in range: re-read the situation every reaction delay plus the
	# guard time, so the share of blocked attacks stays under block_chance.
	var in_threat := dist <= opponent.attack_range(&"kick") + 30.0
	if not in_threat:
		_read_timer = -1.0
		return
	if _read_timer < 0.0:
		_read_timer = tier.reaction_delay
	_read_timer -= delta
	if _read_timer <= 0.0:
		_roll_block()
		_read_timer = tier.reaction_delay + GUARD_TIME


func _roll_block() -> void:
	if _guard_timer <= 0.0 and _rng.randf() < tier.capped_block_chance():
		_guard_timer = GUARD_TIME


func _choose_attack() -> StringName:
	# Fixed weights per match (GDD 6.4).
	if fighter.meter >= Balance.SPECIAL_COST and _rng.randf() < tier.special_weight:
		return &"special"
	return &"punch" if _rng.randf() < 0.5 else &"kick"


func _positioning(opponent: Fighter, dist: float, toward: int) -> int:
	var ideal := fighter.attack_range(&"kick") + 50.0
	if tier.retreats_when_ahead and fighter.health > opponent.health + 0.5:
		ideal += 260.0
	if tier.presses_to_corner:
		ideal = fighter.attack_range(&"punch") - 20.0
	if dist > ideal + 25.0:
		return toward
	if dist < ideal - 25.0:
		return -toward
	return 0


func _next_gap() -> float:
	var gap := tier.attack_gap
	if _round_no >= 2:
		gap *= tier.later_round_gap_scale
	gap += _rng.randf_range(-tier.attack_gap_jitter, tier.attack_gap_jitter)
	return maxf(gap, tier.min_attack_gap)


func get_move_dir() -> int:
	return _move_dir


func wants_block() -> bool:
	return _guard_timer > 0.0


func consume_attack() -> StringName:
	var attack := _queued_attack
	_queued_attack = &""
	return attack
