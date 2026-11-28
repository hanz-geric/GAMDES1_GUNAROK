class_name CpuBrain
extends InputSource
## Smart, human-like arcade opponent using 60 Hz frame counters and seeded RNG.
## Outputs the same per-tick input bit-field as PlayerInput (Section 13.3).
## Features: footsies, dashes, crouch-blocking lows, anti-airs, whiff punishes,
## hit-confirm chain combos, projectile defense, and Counter-Ultimate Clashes!

const GUARD_FRAMES := 34 # >= PARRY_HOLD_THRESHOLD_FRAMES so normal blocks never trigger lockout

var tier: CpuTier
var _rng := RandomNumberGenerator.new()
var _base_seed := 1337
var _round_no := 1
var _round_frames := 0
var _attack_frames := 0
var _planned_attack: StringName = &""
var _move_dir := 0
var _guard_frames := 0
var _guard_low := false
var _read_frames := -1
var _reaction_frames := -1
var _seen_attack_serial := -1
var _parry_tap_next := false
var _grab_tech_checked := false
var _dash_seq: Array[int] = []
var _shimmy_dir := 0
var _shimmy_frames := 0


func _init(cpu_tier: CpuTier, rng_seed: int = 1337) -> void:
	tier = cpu_tier
	_base_seed = rng_seed
	_rng.seed = rng_seed


func reset_for_round(round_no: int) -> void:
	_round_no = round_no
	_rng.seed = _base_seed + round_no * 7919
	_round_frames = 0
	_planned_attack = &""
	_move_dir = 0
	_guard_frames = 0
	_guard_low = false
	_read_frames = -1
	_reaction_frames = -1
	_seen_attack_serial = -1
	_parry_tap_next = false
	_grab_tech_checked = false
	_dash_seq.clear()
	_shimmy_dir = 0
	_shimmy_frames = 0
	_attack_frames = _next_gap_frames()


func sample_bits() -> int:
	_move_dir = 0
	if fighter == null or fighter.opponent == null or not fighter.input_enabled:
		return 0
	_round_frames += 1
	var opponent := fighter.opponent

	# Execute queued double-tap dash sequence (tap -> release -> tap).
	if not _dash_seq.is_empty():
		return _dash_seq.pop_front()

	# Throw-tech reaction when grabbed (higher tiers tech reliably).
	if fighter.state_machine.state == StateMachine.State.GRABBED:
		if not _grab_tech_checked:
			_grab_tech_checked = true
			if _rng.randf() < tier.capped_block_chance() * 0.65:
				return SEIZE
		return 0
	_grab_tech_checked = false

	var dx := opponent.sim_pos.x - fighter.sim_pos.x
	var dist := absf(dx)
	var toward := 1 if dx > 0.0 else -1
	var skill_lvl := tier.capped_block_chance()

	# Corner Escape Burst (Block + Seize): if corner-pinned for 3+ hits, break out cleanly!
	if fighter.is_cornered() and fighter.can_burst_escape() and fighter.corner_hits_taken >= 3 \
			and _rng.randf() < 0.22 + skill_lvl * 0.55:
		return BLOCK | SEIZE

	# Double-Jump vault over opponent when airborne and cornered!
	if not fighter.grounded and fighter.air_jumps_left > 0 and fighter.is_cornered() \
			and dist < 210.0 and _rng.randf() < 0.14 + skill_lvl * 0.25:
		return UP | (RIGHT if toward > 0 else LEFT)

	# Dramatic Counter-Ultimate! If player fires Ultimate and CPU has full meter, CLASH!
	if opponent.is_attacking() and opponent.attack_name == &"ultimate" \
			and fighter.meter >= Balance.ULTIMATE_COST \
			and _rng.randf() < 0.25 + skill_lvl * 0.60:
		return ULTIMATE

	_update_guard(opponent, dist)

	# Simo Häyhä AI: actively uses his evasive Arctic Backflip (Back+H), Disengage (Back+F+G),
	# and Snow-Step Vault-Over (Forward+F+G when cornered) to stay at lethal long range!
	if fighter.data.id == &"simo_hayha" and dist < 210.0 and fighter.grounded and _guard_frames <= 0:
		if fighter.is_cornered() and fighter.is_skill_ready(&"skill_forward") and _rng.randf() < 0.35 + skill_lvl * 0.45:
			return _compose_bits(0, &"skill_forward", false, false, false)
		if not fighter.is_cornered():
			if fighter.is_skill_ready(&"skill_back") and _rng.randf() < 0.24 + skill_lvl * 0.40:
				return _compose_bits(0, &"skill_back", false, false, false)
			if fighter.is_move_ready(&"back_seize") and _rng.randf() < 0.26 + skill_lvl * 0.40:
				return _compose_bits(0, &"back_seize", false, false, false)

	# Block incoming projectiles cleanly!
	if _has_incoming_projectile():
		if fighter.grounded and _rng.randf() < 0.20 + skill_lvl * 0.72:
			_guard_frames = maxi(_guard_frames, 22)
			_guard_low = false
		elif fighter.grounded and dist > 260.0 and _rng.randf() < 0.14:
			return UP | (RIGHT if toward > 0 else LEFT)

	# Punish airborne jump-ins / W+G dives with Rising Anti-Air (Back+G) or Air Skill!
	if opponent.is_airborne() and dist <= fighter.attack_range(&"back_heavy") + 35.0 \
			and fighter.grounded and _rng.randf() < 0.25 + skill_lvl * 0.70:
		if fighter.is_move_ready(&"back_heavy"):
			_guard_frames = 0
			return _compose_bits(0, &"back_heavy", false, false, false)
		if fighter.is_skill_ready(&"skill_air"):
			_guard_frames = 0
			return _compose_bits(0, &"skill_air", false, false, false)

	# Smart Multi-Stage Hit-Confirm Combo Cancel (Tier 1 -> Tier 2 -> Tier 3 -> Ultimate)!
	if fighter.combo_cancel_ready:
		var combo_chance := 0.42 + skill_lvl * 0.55
		if _rng.randf() < combo_chance:
			var cur_tier: int = int(Balance.ATTACKS.get(fighter.attack_name, {}).get("cancel_tier", 1))
			if fighter.meter >= Balance.ULTIMATE_COST and (cur_tier >= 2 or fighter.is_in_rage() or opponent.health <= 38.0):
				return _compose_bits(0, &"ultimate", false, false, false)
			if cur_tier == 1:
				if fighter.is_move_ready(&"forward_heavy") and _rng.randf() < 0.50:
					return _compose_bits(0, &"forward_heavy", false, false, false)
				return _compose_bits(0, &"heavy", false, false, false)
			if cur_tier == 2:
				if fighter.is_skill_ready(&"skill_ground") and _rng.randf() < 0.60:
					return _compose_bits(0, &"skill_ground", false, false, false)
				if fighter.is_skill_ready(&"skill_low") and _rng.randf() < 0.55:
					return _compose_bits(0, &"skill_low", false, false, false)

	# Whiff-Punish / Anti-Spam Punish: opponent stuck in unsafe recovery or parry fail!
	if (opponent.is_counter_vulnerable() or opponent.state_machine.state == StateMachine.State.PARRIED) \
			and _guard_frames <= 0 and fighter.grounded:
		if dist <= fighter.attack_range(&"forward_heavy") + 15.0 and _rng.randf() < 0.28 + skill_lvl * 0.65:
			if fighter.meter >= Balance.ULTIMATE_COST and _rng.randf() < 0.65:
				return _compose_bits(0, &"ultimate", false, false, false)
			if fighter.is_skill_ready(&"skill_ground") and _rng.randf() < 0.55:
				return _compose_bits(0, &"skill_ground", false, false, false)
			if fighter.is_move_ready(&"forward_heavy"):
				return _compose_bits(0, &"forward_heavy", false, false, false)
			return _compose_bits(0, &"heavy", false, false, false)
		elif dist <= 360.0 and fighter.dash_cooldown_frames <= 0 and _rng.randf() < 0.18 + skill_lvl * 0.35:
			_queue_dash(toward)
			return _dash_seq.pop_front()

	# M1, round 1: brief opening pause so the player can get bearings (GDD 5.4).
	var idle_start_frames := roundi(tier.idle_start_time * float(Balance.TICK_RATE))
	if _round_no == 1 and _round_frames < idle_start_frames:
		return _compose_bits(0, &"", _guard_frames > 0, _guard_low, _consume_parry_tap())

	var fire_attack: StringName = &""
	_attack_frames -= 1
	if _planned_attack == &"" and _attack_frames <= 0:
		_planned_attack = _choose_attack(opponent, dist)

	if _planned_attack != &"":
		var desired_range := _effective_attack_range(_planned_attack)
		if dist <= desired_range:
			fire_attack = _planned_attack
			_planned_attack = &""
			_guard_frames = 0
			_attack_frames = _next_gap_frames()
		elif _guard_frames <= 0:
			# Dash in aggressively when closing mid/long distance!
			if dist > desired_range + 130.0 and fighter.grounded and fighter.dash_cooldown_frames <= 0 \
					and _rng.randf() < 0.08 + skill_lvl * 0.18:
				_queue_dash(toward)
				return _dash_seq.pop_front()
			_move_dir = toward
		return _compose_bits(_move_dir, fire_attack, _guard_frames > 0, _guard_low, _consume_parry_tap())

	if _guard_frames > 0:
		return _compose_bits(0, &"", true, _guard_low, _consume_parry_tap())

	_move_dir = _positioning(opponent, dist, toward, skill_lvl)
	return _compose_bits(_move_dir, &"", false, false, _consume_parry_tap())


func _queue_dash(dir: int) -> void:
	var b := RIGHT if dir > 0 else LEFT
	_dash_seq = [b, 0, b]


func _has_incoming_projectile() -> bool:
	var match_node := fighter.get_parent()
	if match_node == null or not ("projectiles" in match_node):
		return false
	for p in match_node.projectiles:
		if p == null or p.finished or p.owner_fighter == fighter or p.owner_fighter == null:
			continue
		var pdx: float = fighter.sim_pos.x - p.sim_pos.x
		if absf(pdx) < 280.0 and (p.kind == Projectile.Kind.SKY_STRIKE or signf(pdx) == float(p.facing)):
			return true
	return false


func _effective_attack_range(atk: StringName) -> float:
	var id := fighter.data.id
	if atk == &"ultimate":
		return 720.0 if id in [&"zeus", &"thor", &"susanoo", &"anubis", &"simo_hayha", &"julius_caesar", &"musashi", &"lapu_lapu", &"ragnar"] else 280.0
	if id == &"simo_hayha" and (atk == &"heavy" or atk == &"forward_heavy"):
		return 640.0
	if atk == &"skill_ground" and id in [&"zeus", &"thor", &"susanoo", &"anubis", &"simo_hayha", &"ragnar", &"musashi", &"lapu_lapu"]:
		return 600.0
	if atk == &"skill_low" and id in [&"zeus", &"thor", &"susanoo", &"anubis", &"julius_caesar", &"ragnar", &"simo_hayha", &"musashi", &"lapu_lapu"]:
		return 440.0
	return fighter.attack_range(atk) - 8.0


func _update_guard(opponent: Fighter, dist: float) -> void:
	if _guard_frames > 0:
		_guard_frames -= 1
	var reaction_frames := maxi(1, roundi(tier.reaction_delay * float(Balance.TICK_RATE)))
	if opponent.attack_serial != _seen_attack_serial:
		_seen_attack_serial = opponent.attack_serial
		if opponent.is_attacking():
			_reaction_frames = reaction_frames
	if _reaction_frames >= 0:
		_reaction_frames -= 1
		if _reaction_frames < 0 and opponent.is_attacking():
			var opp_info: Dictionary = Balance.ATTACKS.get(opponent.attack_name, {})
			if opp_info.get("is_grab", false):
				# Backdash or jump to evade Seize on higher tiers!
				_guard_frames = 0
				if fighter.grounded and fighter.dash_cooldown_frames <= 0 and _rng.randf() < tier.capped_block_chance() * 0.65:
					_queue_dash(-fighter.facing)
			else:
				var is_low: bool = opp_info.get("height", &"mid") == &"low"
				_roll_defense(is_low)
	var in_threat := dist <= opponent.attack_range(&"heavy") + 36.0
	if not in_threat:
		_read_frames = -1
		return
	if _read_frames < 0:
		_read_frames = reaction_frames
	_read_frames -= 1
	if _read_frames <= 0:
		_roll_defense(opponent.is_crouching())
		_read_frames = reaction_frames + GUARD_FRAMES


func _roll_defense(prefer_low: bool) -> void:
	if _guard_frames > 0 or fighter.block_lockout_frames > 0:
		return
	var chance := tier.capped_block_chance()
	if _rng.randf() < chance:
		# Higher tiers occasionally attempt a crisp parry tap against non-low strikes.
		if not prefer_low and chance >= 0.35 and _rng.randf() < 0.28:
			_parry_tap_next = true
		else:
			_guard_frames = GUARD_FRAMES
			_guard_low = prefer_low


func _consume_parry_tap() -> bool:
	var tap := _parry_tap_next
	_parry_tap_next = false
	return tap


func _choose_attack(opponent: Fighter, dist: float) -> StringName:
	var id := fighter.data.id
	var is_zoner := id in [&"simo_hayha", &"zeus"]

	if fighter.meter >= Balance.ULTIMATE_COST and _rng.randf() < maxf(tier.special_weight, 0.55):
		return &"ultimate"
	if opponent.is_airborne() and fighter.is_move_ready(&"back_heavy") and _rng.randf() < 0.60:
		return &"back_heavy"
	if opponent.is_blocking() and dist <= fighter.attack_range(&"forward_seize") + 45.0:
		if fighter.is_move_ready(&"forward_seize") and _rng.randf() < 0.42:
			return &"forward_seize"
		if fighter.is_move_ready(&"seize") and _rng.randf() < 0.55:
			return &"seize"

	# Zoners & projectile champions open up with ranged skills at mid/long distance!
	if dist > 230.0:
		if fighter.is_skill_ready(&"skill_ground") and _rng.randf() < (0.65 if is_zoner else 0.32):
			return &"skill_ground"
		if fighter.is_skill_ready(&"skill_forward") and not is_zoner and _rng.randf() < 0.30:
			return &"skill_forward"
		if fighter.is_skill_ready(&"skill_low") and _rng.randf() < (0.45 if is_zoner else 0.24):
			return &"skill_low"
		if fighter.is_skill_ready(&"skill_air") and _rng.randf() < 0.20:
			return &"skill_air"

	# Close/mid-range combo starters, launchers & skill variety!
	if fighter.is_skill_ready(&"skill_ground") and _rng.randf() < 0.20:
		return &"skill_ground"
	if fighter.is_skill_ready(&"skill_forward") and _rng.randf() < 0.18:
		return &"skill_forward"
	if fighter.is_skill_ready(&"skill_back") and _rng.randf() < 0.14:
		return &"skill_back"
	if fighter.is_skill_ready(&"skill_low") and _rng.randf() < 0.16:
		return &"skill_low"
	if fighter.is_move_ready(&"power_launcher") and _rng.randf() < 0.14:
		return &"power_launcher"
	if fighter.is_move_ready(&"feint_step") and _rng.randf() < 0.14:
		return &"feint_step"

	var roll := _rng.randf()
	if roll < 0.22:
		return &"light"
	if roll < 0.38:
		return &"crouch_light"
	if roll < 0.52 and fighter.is_move_ready(&"forward_light"):
		return &"forward_light"
	if roll < 0.62 and fighter.is_move_ready(&"back_light"):
		return &"back_light"
	if roll < 0.74:
		return &"heavy"
	if roll < 0.85 and fighter.is_move_ready(&"forward_heavy"):
		return &"forward_heavy"
	if roll < 0.94 and fighter.is_move_ready(&"crouch_heavy"):
		return &"crouch_heavy"
	return &"seize" if fighter.is_move_ready(&"seize") else &"light"


func _positioning(opponent: Fighter, dist: float, toward: int, skill_lvl: float) -> int:
	var id := fighter.data.id
	var is_zoner := id in [&"simo_hayha", &"zeus"]
	var is_rushdown := id in [&"nai_khanom_tom", &"musashi", &"ragnar"]

	var ideal := fighter.attack_range(&"heavy") + 32.0
	if id == &"simo_hayha":
		ideal = 560.0 # Stay at lethal sniper range!
	elif id == &"zeus":
		ideal = 360.0
	elif is_rushdown:
		ideal = fighter.attack_range(&"light") - 10.0
	if tier.retreats_when_ahead and fighter.health > opponent.health + 12.0:
		ideal += 180.0
	if tier.presses_to_corner:
		ideal = fighter.attack_range(&"light") - 15.0

	# Backdash away if cornered/pressured as a zoner!
	if is_zoner and dist < 130.0 and not fighter.is_cornered() \
			and fighter.dash_cooldown_frames <= 0 and _rng.randf() < 0.05 + skill_lvl * 0.08:
		_queue_dash(-toward)
		return 0

	# Natural human-like neutral footsies shimmying when near ideal range!
	if absf(dist - ideal) <= 45.0:
		_shimmy_frames -= 1
		if _shimmy_frames <= 0:
			_shimmy_frames = _rng.randi_range(10, 24)
			var r := _rng.randf()
			_shimmy_dir = toward if r < 0.36 else (-toward if r < 0.72 else 0)
		return _shimmy_dir

	if dist > ideal + 24.0:
		return toward
	if dist < ideal - 24.0:
		return -toward
	return 0


func _next_gap_frames() -> int:
	var gap := tier.attack_gap * 0.85 # slightly livelier neutral pacing
	if _round_no >= 2:
		gap *= tier.later_round_gap_scale
	gap += _rng.randf_range(-tier.attack_gap_jitter, tier.attack_gap_jitter)
	gap = maxf(gap, tier.min_attack_gap * 0.85)
	return maxi(1, roundi(gap * float(Balance.TICK_RATE)))


func _compose_bits(dir: int, attack: StringName, hold_block: bool, crouch_block: bool, parry_tap: bool) -> int:
	var bits := 0
	if dir < 0:
		bits |= LEFT
	elif dir > 0:
		bits |= RIGHT
	if hold_block or parry_tap:
		bits |= BLOCK
		if crouch_block:
			bits |= DOWN
	var fwd_bit := RIGHT if fighter.facing >= 0 else LEFT
	var back_bit := LEFT if fighter.facing >= 0 else RIGHT
	match attack:
		&"light":
			bits = (bits & ~(LEFT | RIGHT)) | LIGHT
		&"forward_light":
			bits = (bits & ~(LEFT | RIGHT)) | fwd_bit | LIGHT
		&"back_light":
			bits = (bits & ~(LEFT | RIGHT)) | back_bit | LIGHT
		&"heavy":
			bits = (bits & ~(LEFT | RIGHT)) | HEAVY
		&"forward_heavy":
			bits = (bits & ~(LEFT | RIGHT)) | fwd_bit | HEAVY
		&"back_heavy":
			bits = (bits & ~(LEFT | RIGHT)) | back_bit | HEAVY
		&"seize":
			bits = (bits & ~(LEFT | RIGHT)) | SEIZE
		&"forward_seize":
			bits = (bits & ~(LEFT | RIGHT)) | fwd_bit | SEIZE
		&"back_seize":
			bits = (bits & ~(LEFT | RIGHT)) | back_bit | SEIZE
		&"crouch_seize":
			bits |= DOWN | SEIZE
		&"feint_step":
			bits |= LIGHT | SEIZE
		&"power_launcher":
			bits |= HEAVY | SEIZE
		&"crouch_light":
			bits |= DOWN | LIGHT
		&"crouch_heavy":
			bits |= DOWN | HEAVY
		&"skill_ground":
			bits = (bits & ~(LEFT | RIGHT)) | LIGHT | HEAVY
		&"skill_forward":
			bits = (bits & ~(LEFT | RIGHT)) | fwd_bit | LIGHT | HEAVY
		&"skill_back":
			bits = (bits & ~(LEFT | RIGHT)) | back_bit | LIGHT | HEAVY
		&"skill_air":
			bits |= UP | LIGHT | HEAVY
		&"skill_low":
			bits |= DOWN | LIGHT | HEAVY
		&"ultimate":
			bits |= ULTIMATE
	return bits
