class_name Match
extends Node2D
## One best-of-three match. Drives the single deterministic 60 Hz simulation
## tick (Design Plan v3+ Section 13.3) with hitstop impact freeze & vibration,
## cinematic Ultimate focus-zoom cutscenes, Simultaneous Dual Ultimates
## ("ULTIMATE CLASH!"), cancel-on-hit melee vs persistent projectile Ultimates,
## multi-phase champion spectacles, beam clashes, and slow-motion K.O. finish.

const PROJECTILE_SCRIPT := preload("res://scenes/match/projectile.gd")

var stage: Stage
var sim_frame := 0
var hitstop_frames := 0
var cutin_frames := 0
var _cutin_owner: Fighter
var _dual_cutin_active := false
var ko_slowmo_frames := 0
var _slowmo_tick := 0
var projectiles: Array[Projectile] = []

@onready var fighter1: Fighter = $Fighter1
@onready var fighter2: Fighter = $Fighter2
@onready var effects: Node2D = $Effects
@onready var camera_rig: CameraRig = $CameraRig
@onready var round_manager: RoundManager = $RoundManager
@onready var hud: Hud = $HUD


func _ready() -> void:
	GameState.match_started.connect(_on_match_started)


func _exit_tree() -> void:
	if GameState.match_started.is_connected(_on_match_started):
		GameState.match_started.disconnect(_on_match_started)


func _on_match_started(stage_id: StringName, p1: WarriorData, opponent: WarriorData) -> void:
	sim_frame = 0
	hitstop_frames = 0
	cutin_frames = 0
	_cutin_owner = null
	_dual_cutin_active = false
	ko_slowmo_frames = 0
	_slowmo_tick = 0
	_clear_projectiles()
	_build_stage(stage_id)
	var tier: CpuTier = GameState.current_cpu_tier()
	fighter1.setup(1, p1, PlayerInput.new(1), null, false)
	if GameState.is_arcade():
		var match_seed := hash("%s_%s_%d" % [p1.id, opponent.id, GameState.ladder_step])
		fighter2.setup(2, opponent, CpuBrain.new(tier, match_seed), tier, false)
	else:
		fighter2.setup(2, opponent, PlayerInput.new(2), null, p1 == opponent)
	fighter1.opponent = fighter2
	fighter2.opponent = fighter1
	var centre := stage.arena_width * 0.5
	fighter1.spawn_position = Vector2(centre - Balance.SPAWN_OFFSET, Balance.FLOOR_Y)
	fighter2.spawn_position = Vector2(centre + Balance.SPAWN_OFFSET, Balance.FLOOR_Y)
	for fighter: Fighter in [fighter1, fighter2]:
		fighter.arena_width = stage.arena_width
		fighter.sim_pos = fighter.spawn_position
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
	for fighter: Fighter in [fighter1, fighter2]:
		fighter.health_changed.connect(hud._on_health_changed)
		fighter.meter_changed.connect(hud._on_meter_changed)
		fighter.cooldowns_changed.connect(hud._on_cooldowns_changed)
		fighter.hit_landed.connect(hud._on_hit_landed)
		fighter.parry_landed.connect(hud._on_parry_landed)
		fighter.seize_teched.connect(hud._on_seize_teched)
		fighter.burst_triggered.connect(hud._on_burst_triggered)
		fighter.sniper_shot_landed.connect(hud.show_sniper_callout)
		fighter.guard_crushed.connect(hud.show_guard_crush_callout)
		fighter.move_executed.connect(hud.show_move_name)
		fighter.ultimate_triggered.connect(_on_ultimate_triggered)
		fighter.ultimate_interrupted.connect(_on_ultimate_interrupted)
		fighter.attack_active_started.connect(_on_attack_active_started)
		round_manager.round_started.connect(fighter._on_round_started)
	round_manager.round_started.connect(_on_round_started)
	round_manager.round_started.connect(hud._on_round_started)
	round_manager.round_timer.time_changed.connect(hud._on_time_changed)
	round_manager.round_ended.connect(hud._on_round_ended)
	round_manager.round_ended.connect(_on_round_ended)
	round_manager.round_ended.connect(GameState.on_round_ended)
	round_manager.match_ended.connect(GameState.on_match_ended)


func _on_round_started(_round_no: int) -> void:
	hitstop_frames = 0
	cutin_frames = 0
	_cutin_owner = null
	_dual_cutin_active = false
	ko_slowmo_frames = 0
	_slowmo_tick = 0
	camera_rig.clear_focus()
	_clear_projectiles()


## If a fighter is struck mid-Ultimate, cancel all melee/rush Ultimate hits AND
## any not-yet-launched delayed waves; already-fired projectiles keep flying!
func _on_ultimate_interrupted(fighter: Fighter) -> void:
	var canceled := false
	for p: Projectile in projectiles:
		if p.finished or p.owner_fighter != fighter:
			continue
		if p.cancel_on_owner_hit or p.delay_frames > 0:
			p.finished = true
			canceled = true
	if canceled:
		camera_rig.clear_focus()


func _on_ultimate_triggered(fighter: Fighter) -> void:
	if round_manager.phase != RoundManager.Phase.LIVE:
		return
	hitstop_frames = 0
	# Cinematic Super-Art stage dim + energy surge around caster!
	CombatVfx.spawn_super_backdrop(effects, fighter.sim_pos + Vector2(0, -100), fighter.data.accent_color, 1.45)
	CombatVfx.spawn_shockwave_ring(effects, fighter.sim_pos + Vector2(0, -100), fighter.data.accent_color, 235.0, 0.45, 1.0, 14.0)
	CombatVfx.spawn_radial_burst(effects, fighter.sim_pos + Vector2(0, -100), fighter.data.accent_color, 26, 580.0, 0.45)

	# Champion-specific pre-strike Ultimate ignition cinematics!
	match fighter.data.id:
		&"simo_hayha":
			if fighter.opponent != null:
				var muzzle := fighter.sim_pos + Vector2(float(fighter.facing) * 86.0, -108.0)
				var target := fighter.opponent.sim_pos + Vector2(0, -108.0)
				CombatVfx.spawn_sniper_beam(effects, muzzle, target, Color(1.0, 0.22, 0.22), 0.78, 3.5)
				CombatVfx.spawn_sniper_reticle(effects, target, Color(1.0, 0.22, 0.22), 0.78)
		&"zeus":
			CombatVfx.spawn_energy_pillar(effects, fighter.sim_pos, Color(1.0, 0.94, 0.36), 95.0, 0.48)
			CombatVfx.spawn_lightning_arc(effects, fighter.sim_pos + Vector2(0, -145), fighter.sim_pos + Vector2(-55, -580), Color(1.0, 0.94, 0.35), 0.65, 9.0, 3)
			CombatVfx.spawn_lightning_arc(effects, fighter.sim_pos + Vector2(22, -145), fighter.sim_pos + Vector2(70, -580), Color(1.0, 0.94, 0.35), 0.65, 8.0, 3)
		&"leonidas":
			CombatVfx.spawn_energy_pillar(effects, fighter.sim_pos, Color(1.0, 0.72, 0.18), 85.0, 0.42)
		&"ragnar":
			CombatVfx.spawn_ground_shatter(effects, fighter.sim_pos, Color(1.0, 0.56, 0.18), 1.15)
		&"julius_caesar":
			CombatVfx.spawn_energy_pillar(effects, fighter.sim_pos, Color(0.85, 0.42, 1.0), 90.0, 0.42)
		&"thor":
			CombatVfx.spawn_energy_pillar(effects, fighter.sim_pos, Color(0.35, 0.88, 1.0), 105.0, 0.46)
			CombatVfx.spawn_lightning_arc(effects, fighter.sim_pos + Vector2(0, -140), fighter.sim_pos + Vector2(-45, -580), Color(0.35, 0.90, 1.0), 0.62, 9.0, 3)
		&"susanoo":
			CombatVfx.spawn_energy_pillar(effects, fighter.sim_pos, Color(0.28, 0.78, 1.0), 95.0, 0.44)
			CombatVfx.spawn_slash_arc(effects, fighter.sim_pos + Vector2(0, -100), fighter.facing, Color(0.35, 0.86, 1.0), 155.0, -1.5, 1.5, 20.0, 0.36)
		&"anubis":
			CombatVfx.spawn_energy_pillar(effects, fighter.sim_pos, Color(0.76, 0.34, 1.0), 95.0, 0.46)
			if fighter.opponent != null:
				_spawn_visual("res://assets/sprites/fx/anubis_scale_glyph_frames.tres", fighter.opponent.sim_pos + Vector2(0, -210), fighter.facing, 1.85, 34, true)

	# Simultaneous Dual Ultimate Clash!
	if cutin_frames > 0 and _cutin_owner != null and _cutin_owner != fighter:
		_dual_cutin_active = true
		cutin_frames = Balance.CUTIN_FRAMES + 8
		camera_rig.clear_focus()
		camera_rig.add_shake(1.15)
		camera_rig.punch_zoom(0.28)
		hud.flash_screen(Color(1.0, 0.96, 0.65), 0.65)
		hud.play_dual_ultimate_cutin(fighter1, fighter2)
		var p1_c := fighter1.data.accent_color
		var p2_c := fighter2.data.accent_color
		var mid := (fighter1.sim_pos + fighter2.sim_pos) * 0.5 + Vector2(0, -110)
		var p1_pos := fighter1.sim_pos + Vector2(0, -110)
		var p2_pos := fighter2.sim_pos + Vector2(0, -110)
		# Colossal arena Clash Singularity: twin elemental pillars + 3 jagged arcs + dual rings!
		CombatVfx.spawn_energy_pillar(effects, Vector2(mid.x, Balance.FLOOR_Y), Color(1.0, 0.95, 0.55), 140.0, 0.65)
		CombatVfx.spawn_lightning_arc(effects, p1_pos, mid, p1_c, 0.68, 12.0, 3)
		CombatVfx.spawn_lightning_arc(effects, p2_pos, mid, p2_c, 0.68, 12.0, 3)
		CombatVfx.spawn_lightning_arc(effects, p1_pos, p2_pos, Color(1.0, 0.98, 0.72), 0.72, 10.0, 4)
		CombatVfx.spawn_shockwave_ring(effects, mid, p1_c, 340.0, 0.58, 1.0, 18.0)
		CombatVfx.spawn_shockwave_ring(effects, mid, p2_c, 260.0, 0.48, 1.0, 14.0)
		CombatVfx.spawn_radial_burst(effects, mid, Color(1.0, 0.96, 0.55), 34, 680.0, 0.52)
		CombatVfx.spawn_ground_shatter(effects, Vector2(mid.x, Balance.FLOOR_Y), Color(1.0, 0.92, 0.45), 1.35)
		return

	_cutin_owner = fighter
	_dual_cutin_active = false
	cutin_frames = Balance.CUTIN_FRAMES
	# Cinematic camera zoom right onto the caster during the cut-in flash!
	camera_rig.focus_on(fighter, 0.85, 1.38)
	camera_rig.add_shake(0.68)
	hud.flash_screen(fighter.data.accent_color, 0.36)
	hud.play_ultimate_cutin(fighter)


func _on_round_ended(_winner: int, reason: StringName) -> void:
	hitstop_frames = 0
	cutin_frames = 0
	_cutin_owner = null
	_dual_cutin_active = false
	camera_rig.clear_focus()
	for fighter: Fighter in [fighter1, fighter2]:
		fighter.sprite.offset = Vector2.ZERO
		fighter.set_input_enabled(false)
	if reason == &"KO" or reason == &"DOUBLE KO":
		ko_slowmo_frames = 44
		_slowmo_tick = 0
		camera_rig.punch_zoom(0.22)
		camera_rig.add_shake(0.98)
		hud.flash_screen(Color(1.0, 0.94, 0.72), 0.55)


func _physics_process(_delta: float) -> void:
	if stage == null:
		return
	var bits1 := fighter1.sample_input_bits()
	var bits2 := fighter2.sample_input_bits()
	step_simulation(bits1, bits2)


func _resume_sprite_safely(f: Fighter) -> void:
	if not f.sprite.visible or f.sprite.sprite_frames == null:
		return
	var anim := f.sprite.animation
	if not f.sprite.sprite_frames.has_animation(anim):
		return
	# Never restart non-looping ko/victory/knockdown animations that already finished!
	var loops := f.sprite.sprite_frames.get_animation_loop(anim)
	var last_frame := f.sprite.sprite_frames.get_frame_count(anim) - 1
	if loops or f.sprite.frame < last_frame:
		f.sprite.play()


## Runs a single deterministic 60 Hz tick from two player input bit-fields.
func step_simulation(bits1: int, bits2: int) -> void:
	sim_frame += 1

	# Dramatic Ultimate Cut-In freeze (supports Simultaneous ULTIMATE CLASH!)
	if cutin_frames > 0:
		if not _dual_cutin_active and cutin_frames > 14:
			if _cutin_owner == fighter1 and (bits2 & InputSource.ULTIMATE) != 0 and fighter2.can_counter_ultimate():
				fighter2.trigger_counter_ultimate()
			elif _cutin_owner == fighter2 and (bits1 & InputSource.ULTIMATE) != 0 and fighter1.can_counter_ultimate():
				fighter1.trigger_counter_ultimate()
		cutin_frames -= 1
		fighter1.sprite.pause()
		fighter2.sprite.pause()
		if cutin_frames == 0:
			_cutin_owner = null
			_dual_cutin_active = false
			for f: Fighter in [fighter1, fighter2]:
				_resume_sprite_safely(f)
				f.sync_visuals()
		return

	# Impact hitstop freeze frames with crunchy defender vibration!
	if hitstop_frames > 0:
		hitstop_frames -= 1
		fighter1.sprite.pause()
		fighter2.sprite.pause()
		var vib := 3.5 if (hitstop_frames % 2 == 0) else -3.5
		for f: Fighter in [fighter1, fighter2]:
			var s: StateMachine.State = f.state_machine.state
			if s == StateMachine.State.HITSTUN or s == StateMachine.State.BLOCK or s == StateMachine.State.CROUCH_BLOCK or s == StateMachine.State.PARRIED:
				f.sprite.offset.x = vib
			else:
				f.sprite.offset.x = 0.0
		if hitstop_frames == 0:
			for f: Fighter in [fighter1, fighter2]:
				f.sprite.offset = Vector2.ZERO
				_resume_sprite_safely(f)
		return

	# Dramatic Tekken-style slow-motion K.O. finish!
	if ko_slowmo_frames > 0:
		ko_slowmo_frames -= 1
		_slowmo_tick += 1
		if _slowmo_tick % 3 != 0:
			return

	round_manager.step_tick()
	fighter1.step_tick(bits1, sim_frame)
	fighter2.step_tick(bits2, sim_frame)
	_step_projectiles()
	_resolve_push_box()
	_limit_separation()
	_resolve_combat()
	_resolve_projectile_clashes()
	_resolve_projectile_hits()
	round_manager.check_ko()
	_update_z_order()
	fighter1.sync_visuals()
	fighter2.sync_visuals()


# --- AAA Champion Signature Skills & Multi-Phase Ultimate Spectacles -------

func _on_attack_active_started(attacker: Fighter, move_name: StringName) -> void:
	var id := attacker.data.id
	var dir := float(attacker.facing)
	var hand_pos := attacker.sim_pos + Vector2(dir * 58.0, -104.0)
	var floor_front := Vector2(attacker.sim_pos.x + dir * 74.0, Balance.FLOOR_Y)

	# ==================== SIMO BOLT-ACTION RIFLE HEAVY & EVASIVE SNIPE ====================
	if id == &"simo_hayha" and (move_name == &"heavy" or move_name == &"forward_heavy"):
		var muzzle := attacker.sim_pos + Vector2(dir * 92.0, -106.0)
		_spawn_visual("res://assets/sprites/fx/simo_muzzle_flash_frames.tres", muzzle, attacker.facing, 1.45, 11)
		_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
			muzzle, Vector2(dir * 1420.0, 0.0), Vector2(124, 42), 10.5, move_name,
			{"scale": 1.45, "additive": true, "knockdown": move_name == &"forward_heavy",
			 "life_frames": 62, "meter_gain": Balance.METER_GAIN_HEAVY, "trail_type": &"frost", "trail_color": Color(0.84, 0.96, 1.0)})
		attacker.sim_vel.x = -dir * 220.0 # slight recoil step back to stay at sniper distance!
		AudioManager.play_sfx(&"rifle")
		return

	# ==================== WASD + H & F+H / G+H TACTICAL ARTS ====================
	if move_name == &"back_seize":
		CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, -attacker.facing, 12)
		if id == &"simo_hayha":
			# Simo Arctic Backflip Snipe: fires a parting sniper round while leaping far away!
			var muzzle := attacker.sim_pos + Vector2(dir * 82.0, -96.0)
			_spawn_visual("res://assets/sprites/fx/simo_muzzle_flash_frames.tres", muzzle, attacker.facing, 1.4, 11)
			_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
				muzzle, Vector2(dir * 1450.0, 140.0), Vector2(118, 46), 9.5, &"back_seize",
				{"scale": 1.35, "additive": true, "life_frames": 56, "meter_gain": Balance.METER_GAIN_LIGHT + 4.0,
				 "trail_type": &"frost", "trail_color": Color(0.84, 0.96, 1.0)})
			AudioManager.play_sfx(&"rifle")
		elif id == &"zeus":
			CombatVfx.spawn_lightning_arc(effects, attacker.sim_pos + Vector2(0, -100), attacker.sim_pos + Vector2(dir * 130.0, -90), Color(1.0, 0.94, 0.35), 0.22, 6.0, 2)
		return

	if move_name == &"forward_seize" or move_name == &"feint_step" or move_name == &"power_launcher":
		var col := Color(1.0, 0.48, 0.18) if move_name == &"forward_seize" else attacker.data.accent_color
		CombatVfx.spawn_shockwave_ring(effects, hand_pos, col, 115.0, 0.24, 1.0, 8.0)
		CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, attacker.facing, 8)
		if move_name == &"power_launcher":
			CombatVfx.spawn_slash_arc(effects, hand_pos + Vector2(0, -18), attacker.facing, col, 112.0, 0.95, -1.45, 18.0, 0.22)
		return

	# ==================== FORWARD SKILLS (Forward + F+G: Blitz / Breaker / Vault!) ====================
	if move_name == &"skill_forward":
		match id:
			&"zeus":
				# Lightning Blink-Strike: flashes forward in golden electricity with sky spark!
				CombatVfx.spawn_lightning_arc(effects, attacker.sim_pos + Vector2(-dir * 120.0, -96), hand_pos + Vector2(dir * 60, 0), Color(1.0, 0.94, 0.35), 0.26, 9.0, 3)
				_spawn_visual("res://assets/sprites/fx/zeus_lightning_burst_frames.tres", hand_pos, attacker.facing, 1.85, 20)
				AudioManager.play_sfx(&"thunder", -2.0)
			&"simo_hayha":
				# Snow-Step Vault-Over: vaults high over corner pressurers with snow cloud + downward shot!
				CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, attacker.facing, 14, Color(0.88, 0.96, 1.0, 0.9))
				var muzzle := attacker.sim_pos + Vector2(dir * 60.0, -76.0)
				_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
					muzzle, Vector2(dir * 860.0, 660.0), Vector2(96, 56), 12.0, &"skill_forward",
					{"scale": 1.35, "additive": true, "rotation_deg": 36.0, "life_frames": 48, "trail_type": &"frost", "trail_color": Color(0.84, 0.96, 1.0)})
				AudioManager.play_sfx(&"rifle")
			&"leonidas":
				CombatVfx.spawn_spear_thrust(effects, hand_pos, attacker.facing, Color(1.0, 0.72, 0.2), 215.0, 0.28)
				CombatVfx.spawn_ground_shatter(effects, attacker.sim_pos, Color(1.0, 0.75, 0.22), 0.9)
			&"lapu_lapu":
				CombatVfx.spawn_slash_arc(effects, hand_pos, attacker.facing, Color(0.28, 0.98, 0.92), 118.0, -1.4, 1.3, 20.0, 0.24)
				CombatVfx.spawn_shockwave_ring(effects, hand_pos + Vector2(dir * 20, 0), Color(1.0, 0.82, 0.28), 130.0, 0.25, 1.0, 9.0)
			&"musashi":
				CombatVfx.spawn_slash_arc(effects, hand_pos, attacker.facing, Color(0.75, 0.94, 1.0), 124.0, -1.5, 1.4, 20.0, 0.24)
				_spawn_visual("res://assets/sprites/fx/musashi_slash_frames.tres", hand_pos + Vector2(dir * 45, 0), attacker.facing, 1.7, 18)
			&"thor":
				CombatVfx.spawn_lightning_arc(effects, attacker.sim_pos + Vector2(-dir * 80, -100), hand_pos + Vector2(dir * 65, 0), Color(0.35, 0.90, 1.0), 0.26, 9.0, 3)
				_spawn_visual("res://assets/sprites/fx/thor_shockwave_frames.tres", floor_front, attacker.facing, 1.85, 22, true)
				AudioManager.play_sfx(&"thunder", -2.0)
			&"susanoo":
				CombatVfx.spawn_slash_arc(effects, hand_pos, attacker.facing, Color(0.30, 0.84, 1.0), 130.0, -1.45, 1.35, 22.0, 0.24)
				_spawn_travel(attacker, "res://assets/sprites/fx/susanoo_sword_wave_frames.tres",
					hand_pos, Vector2(dir * 760.0, 0.0), Vector2(106, 128), 14.0, &"skill_forward",
					{"scale": 1.65, "additive": true, "life_frames": 52, "trail_type": &"slash", "trail_color": Color(0.30, 0.84, 1.0)})
			&"anubis":
				CombatVfx.spawn_shockwave_ring(effects, hand_pos, Color(0.78, 0.36, 1.0), 150.0, 0.26, 1.0, 10.0)
				_spawn_travel(attacker, "res://assets/sprites/fx/anubis_spirit_hand_frames.tres",
					hand_pos, Vector2(dir * 660.0, 0.0), Vector2(104, 108), 14.0, &"skill_forward",
					{"scale": 1.65, "additive": true, "life_frames": 54, "trail_type": &"fire", "trail_color": Color(0.78, 0.36, 1.0)})
			_:
				CombatVfx.spawn_shockwave_ring(effects, hand_pos + Vector2(dir * 30, 0), attacker.data.accent_color, 145.0, 0.26, 1.0, 10.0)
				CombatVfx.spawn_radial_burst(effects, hand_pos + Vector2(dir * 30, 0), attacker.data.accent_color, 16, 440.0, 0.26)
				CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, attacker.facing, 10)
		return

	# ==================== BACK SKILLS (Back + F+G: Evasive Disengage / Counter!) ====================
	if move_name == &"skill_back":
		CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, -attacker.facing, 12)
		match id:
			&"simo_hayha":
				# White Death Disengage: frost smoke cloud + massive slide back + suppressing knockback shot!
				var muzzle := attacker.sim_pos + Vector2(dir * 86.0, -104.0)
				CombatVfx.spawn_shockwave_ring(effects, attacker.sim_pos + Vector2(0, -90), Color(0.84, 0.96, 1.0), 150.0, 0.28, 1.0, 8.0)
				_spawn_visual("res://assets/sprites/fx/simo_muzzle_flash_frames.tres", muzzle, attacker.facing, 1.65, 13)
				_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
					muzzle, Vector2(dir * 1560.0, 0.0), Vector2(138, 48), 13.5, &"skill_back",
					{"scale": 1.55, "additive": true, "knockdown": true, "life_frames": 66, "trail_type": &"frost", "trail_color": Color(0.84, 0.96, 1.0)})
				AudioManager.play_sfx(&"rifle")
			&"zeus":
				# Storm-Blink Retreat + Ground Lightning Bolt!
				CombatVfx.spawn_lightning_arc(effects, attacker.sim_pos + Vector2(dir * 80, -100), attacker.sim_pos + Vector2(0, -100), Color(1.0, 0.94, 0.35), 0.24, 7.0, 2)
				_spawn_travel(attacker, "res://assets/sprites/fx/zeus_bolt_flight_frames.tres",
					hand_pos, Vector2(dir * 960.0, 0.0), Vector2(96, 54), 12.5, &"skill_back",
					{"scale": 1.65, "additive": true, "life_frames": 74, "trail_type": &"lightning", "trail_color": Color(1.0, 0.94, 0.35)})
			&"julius_caesar":
				# Rearguard Legionary cover while Caesar steps back!
				_spawn_travel(attacker, "res://assets/sprites/fx/caesar_legionary_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 24.0, Balance.FLOOR_Y - 76.0),
					Vector2(dir * 520.0, 0.0), Vector2(84, 128), 12.0, &"skill_back",
					{"additive": false, "scale": 1.55, "life_frames": 75, "trail_type": &"dust"})
			&"ragnar":
				_spawn_travel(attacker, "res://assets/sprites/fx/ragnar_axe_spin_frames.tres",
					hand_pos, Vector2(dir * 480.0, -180.0), Vector2(76, 76), 12.5, &"skill_back",
					{"gravity": 580.0, "scale": 1.5, "additive": false, "life_frames": 88, "trail_type": &"fire", "trail_color": Color(1.0, 0.62, 0.22)})
			&"lapu_lapu":
				_spawn_travel(attacker, "res://assets/sprites/fx/lapulapu_arc_frames.tres",
					hand_pos, Vector2(dir * 660.0, 0.0), Vector2(96, 114), 12.5, &"skill_back",
					{"scale": 1.6, "additive": true, "life_frames": 56, "trail_type": &"slash", "trail_color": Color(0.28, 0.98, 0.92)})
			&"thor":
				_spawn_travel(attacker, "res://assets/sprites/fx/thor_hammer_spin_frames.tres",
					hand_pos, Vector2(dir * 720.0, 0.0), Vector2(88, 88), 13.5, &"skill_back",
					{"scale": 1.6, "additive": false, "life_frames": 74, "trail_type": &"lightning", "trail_color": Color(0.35, 0.90, 1.0)})
			&"susanoo":
				_spawn_travel(attacker, "res://assets/sprites/fx/susanoo_sword_wave_frames.tres",
					hand_pos, Vector2(dir * 740.0, 0.0), Vector2(100, 122), 13.0, &"skill_back",
					{"scale": 1.65, "additive": true, "life_frames": 60, "trail_type": &"slash", "trail_color": Color(0.30, 0.84, 1.0)})
			&"anubis":
				_spawn_travel(attacker, "res://assets/sprites/fx/anubis_scale_glyph_frames.tres",
					attacker.sim_pos + Vector2(dir * 48.0, -96.0), Vector2(dir * 260.0, 0.0), Vector2(114, 114), 13.0, &"skill_back",
					{"scale": 1.75, "additive": true, "life_frames": 44, "trail_type": &"fire", "trail_color": Color(0.84, 0.44, 1.0)})
			_:
				CombatVfx.spawn_slash_arc(effects, hand_pos, attacker.facing, attacker.data.accent_color, 110.0, 1.25, -1.35, 18.0, 0.22)
				CombatVfx.spawn_shockwave_ring(effects, hand_pos, attacker.data.accent_color, 130.0, 0.24, 1.0, 8.0)
		return

	# ==================== GROUND SKILLS (F+G) ====================
	if move_name == &"skill_ground":
		match id:
			&"zeus":
				CombatVfx.spawn_lightning_arc(effects, attacker.sim_pos + Vector2(dir * 20, -115), hand_pos + Vector2(dir * 60, 0), Color(1.0, 0.94, 0.35), 0.24, 7.0, 3)
				for b in 2:
					_spawn_travel(attacker, "res://assets/sprites/fx/zeus_bolt_flight_frames.tres",
						hand_pos + Vector2(0, -12.0 + float(b) * 24.0), Vector2(dir * (940.0 + float(b) * 90.0), 0.0),
						Vector2(94, 54), 9.0, &"skill_ground",
						{"scale": 1.65, "additive": true, "delay_frames": b * 6, "life_frames": 80, "trail_type": &"lightning", "trail_color": Color(1.0, 0.94, 0.35)})
			&"ragnar":
				_spawn_travel(attacker, "res://assets/sprites/fx/ragnar_axe_spin_frames.tres",
					hand_pos, Vector2(dir * 465.0, -210.0), Vector2(76, 76), 14.0, &"skill_ground",
					{"gravity": 620.0, "scale": 1.55, "additive": false, "life_frames": 95, "trail_type": &"fire", "trail_color": Color(1.0, 0.62, 0.22), "impact_shatter": true})
			&"simo_hayha":
				var muzzle := attacker.sim_pos + Vector2(dir * 96.0, -108.0)
				_spawn_visual("res://assets/sprites/fx/simo_muzzle_flash_frames.tres", muzzle, attacker.facing, 1.65, 13)
				CombatVfx.spawn_sniper_beam(effects, muzzle, muzzle + Vector2(dir * 620.0, 0), Color(0.84, 0.96, 1.0), 0.22, 8.0)
				_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
					muzzle, Vector2(dir * 1520.0, 0.0), Vector2(134, 44), 14.5, &"skill_ground",
					{"scale": 1.55, "additive": true, "life_frames": 64, "trail_type": &"frost", "trail_color": Color(0.82, 0.96, 1.0)})
				AudioManager.play_sfx(&"rifle")
			&"musashi":
				CombatVfx.spawn_slash_arc(effects, hand_pos, attacker.facing, Color(0.7, 0.92, 1.0), 104.0, -1.4, 1.2, 18.0, 0.22)
				_spawn_travel(attacker, "res://assets/sprites/fx/musashi_slash_frames.tres",
					hand_pos + Vector2(dir * 32.0, 0.0), Vector2(dir * 580.0, 0.0), Vector2(96, 118), 13.0, &"skill_ground",
					{"scale": 1.65, "additive": true, "life_frames": 28, "trail_type": &"slash", "trail_color": Color(0.75, 0.94, 1.0)})
			&"lapu_lapu":
				CombatVfx.spawn_slash_arc(effects, hand_pos, attacker.facing, Color(0.28, 0.98, 0.92), 104.0, -1.35, 1.25, 18.0, 0.22)
				_spawn_travel(attacker, "res://assets/sprites/fx/lapulapu_arc_frames.tres",
					hand_pos, Vector2(dir * 670.0, 0.0), Vector2(98, 116), 13.0, &"skill_ground",
					{"scale": 1.65, "additive": true, "life_frames": 56, "trail_type": &"slash", "trail_color": Color(0.3, 0.98, 0.92)})
			&"leonidas":
				CombatVfx.spawn_spear_thrust(effects, hand_pos, attacker.facing, Color(1.0, 0.78, 0.22), 195.0, 0.26)
				CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, attacker.facing, 10)
			&"julius_caesar":
				CombatVfx.spawn_slash_arc(effects, hand_pos, attacker.facing, Color(0.88, 0.55, 1.0), 106.0, -1.25, 1.15, 18.0, 0.22)
				CombatVfx.spawn_spear_thrust(effects, hand_pos, attacker.facing, Color(0.92, 0.62, 1.0), 155.0, 0.22)
			&"thor":
				# Mjolnir Storm Throw!
				_spawn_travel(attacker, "res://assets/sprites/fx/thor_hammer_spin_frames.tres",
					hand_pos, Vector2(dir * 780.0, 0.0), Vector2(92, 92), 15.0, &"skill_ground",
					{"scale": 1.7, "additive": false, "life_frames": 76, "trail_type": &"lightning", "trail_color": Color(0.35, 0.90, 1.0)})
			&"susanoo":
				# Kusanagi Storm Sword Wave!
				_spawn_travel(attacker, "res://assets/sprites/fx/susanoo_sword_wave_frames.tres",
					hand_pos, Vector2(dir * 760.0, 0.0), Vector2(106, 130), 15.0, &"skill_ground",
					{"scale": 1.75, "additive": true, "life_frames": 68, "trail_type": &"slash", "trail_color": Color(0.30, 0.84, 1.0)})
			&"anubis":
				# Spirit Hand of Duat!
				_spawn_travel(attacker, "res://assets/sprites/fx/anubis_spirit_hand_frames.tres",
					hand_pos, Vector2(dir * 660.0, 0.0), Vector2(106, 112), 14.5, &"skill_ground",
					{"scale": 1.7, "additive": true, "life_frames": 68, "trail_type": &"fire", "trail_color": Color(0.78, 0.36, 1.0)})
			_:
				CombatVfx.spawn_shockwave_ring(effects, hand_pos + Vector2(dir * 25, 0), attacker.data.accent_color, 140.0, 0.26, 1.0, 10.0)
				CombatVfx.spawn_radial_burst(effects, hand_pos + Vector2(dir * 25, 0), attacker.data.accent_color, 16, 420.0, 0.26)
				CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, attacker.facing, 9)
		return

	# ==================== AIR SKILLS (W+F+G) ====================
	if move_name == &"skill_air":
		match id:
			&"zeus":
				_spawn_visual("res://assets/sprites/fx/zeus_lightning_burst_frames.tres", attacker.sim_pos + Vector2(0, -85), attacker.facing, 2.0, 22)
				CombatVfx.spawn_lightning_arc(effects, attacker.sim_pos + Vector2(0, -120), Vector2(attacker.sim_pos.x + dir * 75.0, Balance.FLOOR_Y), Color(1.0, 0.94, 0.35), 0.26, 8.0, 3)
				CombatVfx.spawn_shockwave_ring(effects, attacker.sim_pos + Vector2(0, -80), Color(1.0, 0.94, 0.38), 155.0, 0.28, 1.0, 9.0)
				AudioManager.play_sfx(&"thunder", -2.0)
			&"simo_hayha":
				var muzzle := attacker.sim_pos + Vector2(dir * 75.0, -90.0)
				_spawn_visual("res://assets/sprites/fx/simo_muzzle_flash_frames.tres", muzzle, attacker.facing, 1.5, 12)
				_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
					muzzle, Vector2(dir * 1040.0, 620.0), Vector2(102, 58), 14.0, &"skill_air",
					{"scale": 1.45, "additive": true, "rotation_deg": 30.0, "life_frames": 52, "trail_type": &"frost", "trail_color": Color(0.82, 0.96, 1.0)})
				AudioManager.play_sfx(&"rifle")
			&"ragnar":
				_spawn_visual("res://assets/sprites/fx/thor_shockwave_frames.tres", Vector2(attacker.sim_pos.x + dir * 24, Balance.FLOOR_Y - 28), attacker.facing, 1.8, 22, true)
				CombatVfx.spawn_slash_arc(effects, attacker.sim_pos + Vector2(dir * 25, -80), attacker.facing, Color(1.0, 0.62, 0.22), 112.0, -1.5, 1.5, 18.0, 0.24)
			_:
				CombatVfx.spawn_slash_arc(effects, attacker.sim_pos + Vector2(dir * 28, -82), attacker.facing, attacker.data.accent_color, 108.0, -1.4, 1.4, 16.0, 0.22)
				CombatVfx.spawn_shockwave_ring(effects, attacker.sim_pos + Vector2(dir * 20, -80), attacker.data.accent_color, 130.0, 0.25, 1.0, 8.0)
		return

	# ==================== LOW SKILLS (S+F+G) ====================
	if move_name == &"skill_low":
		match id:
			&"zeus":
				CombatVfx.spawn_ground_shatter(effects, floor_front, Color(1.0, 0.92, 0.35), 1.05)
				_spawn_travel(attacker, "res://assets/sprites/fx/zeus_ground_electricity_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 70.0, Balance.FLOOR_Y - 38.0),
					Vector2(dir * 560.0, 0.0), Vector2(112, 68), 14.0, &"skill_low",
					{"height": &"low", "knockdown": true, "scale": 1.75, "additive": true, "life_frames": 62, "trail_type": &"lightning", "trail_color": Color(1.0, 0.94, 0.35)})
				AudioManager.play_sfx(&"thunder", -4.0)
			&"julius_caesar":
				_spawn_travel(attacker, "res://assets/sprites/fx/caesar_legionary_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 32.0, Balance.FLOOR_Y - 76.0),
					Vector2(dir * 540.0, 0.0), Vector2(82, 102), 13.0, &"skill_low",
					{"height": &"low", "knockdown": true, "additive": false, "scale": 1.55, "life_frames": 68, "trail_type": &"dust"})
			&"ragnar":
				CombatVfx.spawn_ground_shatter(effects, floor_front, Color(1.0, 0.62, 0.24), 1.15)
				_spawn_travel(attacker, "res://assets/sprites/fx/thor_shockwave_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 96.0, Balance.FLOOR_Y - 36.0),
					Vector2(dir * 200.0, 0.0), Vector2(142, 80), 14.5, &"skill_low",
					{"height": &"low", "knockdown": true, "scale": 1.85, "additive": true, "life_frames": 28, "trail_type": &"fire", "trail_color": Color(1.0, 0.6, 0.2)})
			&"simo_hayha":
				var muzzle := Vector2(attacker.sim_pos.x + dir * 92.0, Balance.FLOOR_Y - 36.0)
				_spawn_visual("res://assets/sprites/fx/simo_muzzle_flash_frames.tres", muzzle, attacker.facing, 1.45, 12)
				_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
					muzzle, Vector2(dir * 1440.0, 0.0), Vector2(132, 44), 14.0, &"skill_low",
					{"height": &"low", "knockdown": true, "scale": 1.45, "additive": true, "life_frames": 60, "trail_type": &"frost", "trail_color": Color(0.82, 0.96, 1.0)})
				AudioManager.play_sfx(&"rifle")
			&"musashi":
				CombatVfx.spawn_slash_arc(effects, Vector2(attacker.sim_pos.x + dir * 58.0, Balance.FLOOR_Y - 36.0), attacker.facing, Color(0.72, 0.92, 1.0), 112.0, -0.45, 0.9, 18.0, 0.22)
				CombatVfx.spawn_dust_puff(effects, floor_front, attacker.facing, 9)
			&"lapu_lapu":
				_spawn_travel(attacker, "res://assets/sprites/fx/lapulapu_arc_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 64.0, Balance.FLOOR_Y - 42.0),
					Vector2(dir * 620.0, 0.0), Vector2(102, 70), 13.0, &"skill_low",
					{"height": &"low", "knockdown": true, "scale": 1.55, "additive": true, "life_frames": 52, "trail_type": &"slash", "trail_color": Color(0.3, 0.98, 0.92)})
			&"thor":
				CombatVfx.spawn_ground_shatter(effects, floor_front, Color(0.35, 0.90, 1.0), 1.25)
				_spawn_travel(attacker, "res://assets/sprites/fx/thor_shockwave_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 96.0, Balance.FLOOR_Y - 38.0),
					Vector2(dir * 340.0, 0.0), Vector2(150, 82), 15.0, &"skill_low",
					{"height": &"low", "knockdown": true, "scale": 1.95, "additive": true, "life_frames": 36, "trail_type": &"lightning", "trail_color": Color(0.35, 0.90, 1.0)})
				AudioManager.play_sfx(&"thunder", -3.0)
			&"susanoo":
				# Low Sea-Serpent Wave skimming across the floor!
				_spawn_travel(attacker, "res://assets/sprites/fx/susanoo_serpent_wave_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 72.0, Balance.FLOOR_Y - 46.0),
					Vector2(dir * 660.0, 0.0), Vector2(124, 78), 14.5, &"skill_low",
					{"height": &"low", "knockdown": true, "scale": 1.75, "additive": true, "life_frames": 66, "trail_type": &"slash", "trail_color": Color(0.28, 0.82, 1.0)})
			&"anubis":
				# Sands of Duat low spirit hand erupting forward!
				_spawn_travel(attacker, "res://assets/sprites/fx/anubis_spirit_hand_frames.tres",
					Vector2(attacker.sim_pos.x + dir * 72.0, Balance.FLOOR_Y - 44.0),
					Vector2(dir * 580.0, 0.0), Vector2(114, 74), 14.0, &"skill_low",
					{"height": &"low", "knockdown": true, "scale": 1.65, "additive": true, "life_frames": 62, "trail_type": &"fire", "trail_color": Color(0.78, 0.36, 1.0)})
			_:
				CombatVfx.spawn_slash_arc(effects, Vector2(attacker.sim_pos.x + dir * 48.0, Balance.FLOOR_Y - 36.0), attacker.facing, attacker.data.accent_color, 102.0, -0.5, 0.95, 16.0, 0.22)
				CombatVfx.spawn_dust_puff(effects, floor_front, attacker.facing, 10)
		return

	if move_name != &"ultimate":
		return

	# ==================== MULTI-PHASE AAA CHAMPION ULTIMATES (T) ====================
	camera_rig.add_shake(0.82)
	camera_rig.punch_zoom(0.16)
	match id:
		&"zeus":
			# THUNDERBOLT OF OLYMPUS (Projectile/Sky Type):
			# Zeus levitates in a golden storm -> 3 colossal Sky-to-Earth Thunderbolts + Energy Pillars!
			attacker.hitbox.deactivate()
			attacker.sim_vel.y = -240.0
			attacker.grounded = false
			var tx := attacker.opponent.sim_pos.x if attacker.opponent != null else (attacker.sim_pos.x + dir * 260.0)
			var pts := [
				clampf(tx, 95.0, stage.arena_width - 95.0),
				clampf(tx + dir * 78.0, 95.0, stage.arena_width - 95.0),
				clampf(tx - dir * 52.0, 95.0, stage.arena_width - 95.0),
			]
			for i in 3:
				_spawn_sky_strike(attacker, "res://assets/sprites/fx/zeus_sky_bolt_frames.tres",
					"res://assets/sprites/fx/zeus_ground_electricity_frames.tres",
					pts[i], 14.0 if i < 2 else 17.0, 10 + i * 10, i == 2)
			_spawn_visual("res://assets/sprites/fx/zeus_lightning_burst_frames.tres",
				attacker.sim_pos + Vector2(0, -115), attacker.facing, 2.5, 30)
			CombatVfx.spawn_shockwave_ring(effects, attacker.sim_pos + Vector2(0, -100), Color(1.0, 0.95, 0.4), 260.0, 0.44, 1.0, 14.0)
			hud.flash_screen(Color(1.0, 0.96, 0.50), 0.50)

		&"simo_hayha":
			# WHITE DEATH (Projectile Type):
			# Blinding arctic muzzle flare -> full-arena supersonic rail beam + 6 Mach cones + DEADEYE scaling!
			attacker.hitbox.deactivate()
			var muzzle := attacker.sim_pos + Vector2(dir * 104.0, -108.0)
			var end_pt := Vector2(stage.arena_width if dir > 0.0 else 0.0, muzzle.y)
			_spawn_visual("res://assets/sprites/fx/simo_muzzle_flash_frames.tres", muzzle, attacker.facing, 2.7, 22)
			CombatVfx.spawn_sniper_beam(effects, muzzle, end_pt, Color(0.74, 0.96, 1.0), 0.56, 28.0)
			CombatVfx.spawn_radial_burst(effects, muzzle, Color(0.88, 0.98, 1.0), 24, 580.0, 0.38)
			CombatVfx.spawn_shockwave_ring(effects, muzzle, Color(0.82, 0.96, 1.0), 170.0, 0.30, 1.0, 10.0)
			for i in 2:
				_spawn_travel(attacker, "res://assets/sprites/fx/simo_tracer_frames.tres",
					muzzle, Vector2(dir * 1950.0, 0.0), Vector2(220, 86), 17.0, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": true, "scale": 2.35,
					 "delay_frames": i * 4, "life_frames": 58, "knockdown": i == 1, "hitstun": 28,
					 "trail_type": &"frost", "trail_color": Color(0.82, 0.96, 1.0), "impact_shatter": i == 1})
			hud.flash_screen(Color(0.92, 0.98, 1.0), 0.48)

		&"julius_caesar":
			# LEGION'S MARCH (Projectile/Summon Type):
			# Purple-gold eagle surge -> 6-soldier 2-rank Roman Legion Stampede charging full-screen!
			attacker.hitbox.deactivate()
			CombatVfx.spawn_shockwave_ring(effects, attacker.sim_pos + Vector2(0, -100), Color(0.95, 0.72, 1.0), 245.0, 0.42, 1.0, 13.0)
			for wave in 6:
				var y_off := -76.0 - float(wave % 2) * 18.0
				_spawn_travel(attacker, "res://assets/sprites/fx/caesar_legionary_frames.tres",
					Vector2(attacker.sim_pos.x - dir * (34.0 + float(wave) * 52.0), Balance.FLOOR_Y + y_off),
					Vector2(dir * 630.0, 0.0), Vector2(90, 152), 7.2, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": false, "scale": 1.68,
					 "delay_frames": wave * 5, "life_frames": 140, "knockdown": wave == 5, "hitstun": 26,
					 "trail_type": &"dust", "trail_color": Color(1.0, 0.84, 0.35), "impact_shatter": wave == 5, "launch_pillar": wave == 5})

		&"musashi":
			# TWO HEAVENS STRIKE (Melee/Rush Type — CANCELABLE if Musashi gets hit!):
			# Blistering shadow dash -> 5 crisscrossing glowing X-slash anime cuts -> Heaven-Cleaving finisher!
			attacker.hitbox.deactivate()
			attacker.sim_vel.x = dir * 680.0
			CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, attacker.facing, 12)
			var base_x := attacker.sim_pos.x + dir * 135.0
			if attacker.opponent != null and absf(attacker.opponent.sim_pos.x - attacker.sim_pos.x) < 420.0:
				base_x = attacker.opponent.sim_pos.x
			for i in 5:
				var is_finisher := (i == 4)
				var sx := clampf(base_x + dir * float(i - 2) * 42.0, 90.0, stage.arena_width - 90.0)
				var sy := Balance.FLOOR_Y - 108.0 + float(i % 2) * 28.0 - 12.0
				var col := Color(1.0, 0.35, 0.42) if is_finisher else Color(0.72, 0.94, 1.0)
				_spawn_travel(attacker, "res://assets/sprites/fx/musashi_slash_frames.tres",
					Vector2(sx, sy), Vector2(dir * 160.0, 0.0), Vector2(150, 165), 8.2 if not is_finisher else 13.0, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": true, "additive": true,
					 "scale": 2.65 if is_finisher else 2.05, "rotation_deg": float(i % 2) * 28.0 - 14.0,
					 "delay_frames": i * 5 + (4 if is_finisher else 0), "life_frames": 24,
					 "knockdown": is_finisher, "hitstun": 26, "tint": col, "trail_color": col,
					 "launch_slash": true, "launch_pillar": is_finisher, "impact_shatter": is_finisher})

		&"leonidas":
			# PHALANX CHARGE (Melee/Rush Type — CANCELABLE if Leonidas gets hit!):
			# Blazing crimson-gold tunnel dash -> 3 spear shock-cones -> colossal Spartan Energy Pillar eruption!
			attacker.hitbox.deactivate()
			attacker.sim_vel.x = dir * 610.0
			CombatVfx.spawn_ground_shatter(effects, attacker.sim_pos, Color(1.0, 0.78, 0.22), 1.35)
			CombatVfx.spawn_dust_puff(effects, attacker.sim_pos, attacker.facing, 14)
			for i in 3:
				var is_finisher := (i == 2)
				_spawn_travel(attacker, "res://assets/sprites/fx/hit_spark_heavy_frames.tres",
					attacker.sim_pos + Vector2(dir * (75.0 + float(i) * 48.0), -100.0),
					Vector2(dir * 720.0, 0.0), Vector2(138, 150), 12.5 if not is_finisher else 17.5, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": true, "additive": true,
					 "scale": 2.35 if is_finisher else 1.85, "delay_frames": i * 6, "life_frames": 36,
					 "knockdown": is_finisher, "hitstun": 26,
					 "tint": Color(1.0, 0.55, 0.18) if is_finisher else Color(1.0, 0.84, 0.26),
					 "trail_type": &"fire", "trail_color": Color(1.0, 0.72, 0.18),
					 "launch_spear": true, "launch_pillar": is_finisher, "impact_shatter": is_finisher})

		&"ragnar":
			# VALHALLA'S CALL (Projectile/Hybrid Type):
			# Berserker leap -> 4 solid spinning Viking war-axes -> colossal Bifrost Earth-Breaker Pillar!
			attacker.hitbox.deactivate()
			attacker.sim_vel.y = -220.0
			attacker.grounded = false
			CombatVfx.spawn_ground_shatter(effects, floor_front, Color(1.0, 0.58, 0.2), 1.3)
			for i in 4:
				var vy := -160.0 + float(i) * 65.0
				_spawn_travel(attacker, "res://assets/sprites/fx/ragnar_axe_spin_frames.tres",
					hand_pos, Vector2(dir * (620.0 + float(i) * 70.0), vy), Vector2(98, 98), 7.8, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": false,
					 "gravity": 250.0, "scale": 1.82, "delay_frames": i * 5, "life_frames": 95,
					 "knockdown": false, "hitstun": 26, "trail_type": &"fire", "trail_color": Color(1.0, 0.58, 0.18)})
			_spawn_travel(attacker, "res://assets/sprites/fx/thor_shockwave_frames.tres",
				Vector2(attacker.sim_pos.x + dir * 135.0, Balance.FLOOR_Y - 42.0),
				Vector2(dir * 380.0, 0.0), Vector2(180, 128), 16.0, &"ultimate",
				{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": true, "scale": 2.35,
				 "delay_frames": 20, "life_frames": 36, "knockdown": true,
				 "trail_type": &"fire", "trail_color": Color(1.0, 0.68, 0.22), "launch_pillar": true, "impact_shatter": true})

		&"lapu_lapu":
			# KAMPILAN STORM (Projectile/Slash Type):
			# Tropical vortex -> 4 huge glowing cyan-gold rising/dipping Kampilan typhoon arcs!
			attacker.hitbox.deactivate()
			CombatVfx.spawn_shockwave_ring(effects, attacker.sim_pos + Vector2(0, -96), Color(0.25, 0.98, 0.92), 235.0, 0.40, 1.0, 13.0)
			for i in 4:
				var is_finisher := (i == 3)
				_spawn_travel(attacker, "res://assets/sprites/fx/lapulapu_arc_frames.tres",
					attacker.sim_pos + Vector2(dir * 62.0, -96.0 + float(i % 2) * 20.0 - 10.0),
					Vector2(dir * (720.0 + float(i) * 60.0), 0.0), Vector2(128, 152), 9.5 if not is_finisher else 14.0, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": true,
					 "scale": 2.55 if is_finisher else 2.05, "rotation_deg": float(i) * 16.0 - 18.0,
					 "delay_frames": i * 6, "life_frames": 86, "knockdown": is_finisher, "hitstun": 26,
					 "trail_type": &"slash", "trail_color": Color(0.28, 0.98, 0.92),
					 "launch_slash": true, "launch_pillar": is_finisher, "impact_shatter": is_finisher})

		&"thor":
			# RAGNAROK MJOLNIR (God Boss — Dynamic Leap + Storm Hammers + Sky Bolts + Earth Shatter!):
			attacker.hitbox.deactivate()
			for i in 3:
				_spawn_travel(attacker, "res://assets/sprites/fx/thor_hammer_spin_frames.tres",
					hand_pos + Vector2(0, -40.0 + float(i) * 24.0), Vector2(dir * (760.0 + float(i) * 70.0), 80.0),
					Vector2(104, 104), 9.5, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": false,
					 "scale": 1.95, "delay_frames": i * 5, "life_frames": 82, "knockdown": false, "hitstun": 26,
					 "trail_type": &"lightning", "trail_color": Color(0.35, 0.90, 1.0)})
			var tx := attacker.opponent.sim_pos.x if attacker.opponent != null else (attacker.sim_pos.x + dir * 240.0)
			_spawn_sky_strike(attacker, "res://assets/sprites/fx/zeus_sky_bolt_frames.tres",
				"res://assets/sprites/fx/zeus_ground_electricity_frames.tres", clampf(tx, 95.0, stage.arena_width - 95.0), 12.0, 14, false)
			_spawn_travel(attacker, "res://assets/sprites/fx/thor_shockwave_frames.tres",
				Vector2(clampf(tx, 100.0, stage.arena_width - 100.0), Balance.FLOOR_Y - 46.0),
				Vector2(dir * 320.0, 0.0), Vector2(190, 140), 16.0, &"ultimate",
				{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": true, "scale": 2.6,
				 "delay_frames": 20, "life_frames": 38, "knockdown": true,
				 "trail_type": &"lightning", "trail_color": Color(0.35, 0.90, 1.0), "launch_pillar": true, "impact_shatter": true})
			hud.flash_screen(Color(0.45, 0.90, 1.0), 0.45)

		&"susanoo":
			# OROCHI TEMPEST (God Boss — Storm Flash Dash + 3 Serpent Waves + 2 Colossal Sword Waves!):
			attacker.hitbox.deactivate()
			for i in 3:
				_spawn_travel(attacker, "res://assets/sprites/fx/susanoo_serpent_wave_frames.tres",
					attacker.sim_pos + Vector2(dir * 55.0, -76.0 - float(i % 2) * 38.0),
					Vector2(dir * (760.0 + float(i) * 65.0), 0.0), Vector2(138, 128), 9.5, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": true,
					 "scale": 2.15, "delay_frames": i * 6, "life_frames": 86, "knockdown": false, "hitstun": 26,
					 "trail_type": &"slash", "trail_color": Color(0.30, 0.84, 1.0), "launch_slash": true})
			for j in 2:
				var is_end := (j == 1)
				_spawn_travel(attacker, "res://assets/sprites/fx/susanoo_sword_wave_frames.tres",
					attacker.sim_pos + Vector2(dir * 68.0, -104.0),
					Vector2(dir * 860.0, 0.0), Vector2(142, 165), 11.5 if not is_end else 15.0, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": true,
					 "scale": 2.65 if is_end else 2.15, "delay_frames": 18 + j * 6, "life_frames": 76,
					 "knockdown": is_end, "hitstun": 28, "trail_type": &"slash", "trail_color": Color(0.45, 0.72, 1.0),
					 "launch_slash": true, "launch_pillar": is_end, "impact_shatter": is_end})
			hud.flash_screen(Color(0.35, 0.78, 1.0), 0.45)

		&"anubis":
			# SCALES OF MA'AT (God Boss — Levitating Underworld Scales + 3 Spectral Spirit Hands + Judgment Pillar!):
			attacker.hitbox.deactivate()
			var tx := attacker.opponent.sim_pos.x if attacker.opponent != null else (attacker.sim_pos.x + dir * 240.0)
			_spawn_visual("res://assets/sprites/fx/anubis_scale_glyph_frames.tres",
				Vector2(clampf(tx, 95.0, stage.arena_width - 95.0), Balance.FLOOR_Y - 220.0), attacker.facing, 2.35, 48, true)
			for i in 3:
				var is_end := (i == 2)
				_spawn_travel(attacker, "res://assets/sprites/fx/anubis_spirit_hand_frames.tres",
					attacker.sim_pos + Vector2(dir * 52.0, -96.0 + float(i % 2) * 26.0 - 12.0),
					Vector2(dir * (700.0 + float(i) * 80.0), 0.0), Vector2(138, 148), 11.5 if not is_end else 18.0, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": false, "additive": true,
					 "scale": 2.45 if is_end else 2.0, "delay_frames": 6 + i * 7, "life_frames": 84,
					 "knockdown": is_end, "hitstun": 28, "trail_type": &"fire", "trail_color": Color(0.80, 0.36, 1.0),
					 "launch_pillar": is_end, "impact_shatter": is_end})
			hud.flash_screen(Color(0.76, 0.38, 1.0), 0.45)

		_:
			# NAI KHANOM TOM (Ten Champions Flurry — Melee/Rush Type, CANCELABLE if hit!):
			# Golden Mongkhon blitz -> 7 rapid-fire golden impact strikes -> colossal Tiger-Knee Energy Pillar!
			attacker.hitbox.deactivate()
			attacker.sim_vel.x = dir * 560.0
			CombatVfx.spawn_shockwave_ring(effects, attacker.sim_pos + Vector2(0, -100), Color(1.0, 0.84, 0.22), 215.0, 0.36, 1.0, 13.0)
			for i in 7:
				var is_finisher := (i == 6)
				var y_var := -122.0 + float(i % 3) * 26.0
				var col := Color(1.0, 0.42, 0.18) if is_finisher else Color(1.0, 0.88, 0.28)
				_spawn_travel(attacker, "res://assets/sprites/fx/hit_spark_heavy_frames.tres",
					attacker.sim_pos + Vector2(dir * (62.0 + float(i) * 26.0), y_var),
					Vector2(dir * 580.0, 0.0), Vector2(122, 140), 5.2 if not is_finisher else 12.0, &"ultimate",
					{"is_ultimate": true, "cancel_on_owner_hit": true, "additive": true,
					 "scale": 2.65 if is_finisher else 1.85, "delay_frames": i * 4, "life_frames": 24,
					 "knockdown": is_finisher, "hitstun": 24, "tint": col,
					 "trail_type": &"fire", "trail_color": col,
					 "launch_pillar": is_finisher, "impact_shatter": is_finisher})


func _spawn_travel(attacker: Fighter, fx_path: String, pos: Vector2, vel: Vector2, size: Vector2, dmg: float, move_id: StringName, opts: Dictionary) -> void:
	var p := PROJECTILE_SCRIPT.new() as Projectile
	p.setup_travel(attacker, fx_path, pos, vel, size, dmg, move_id, opts)
	effects.add_child(p)
	projectiles.append(p)


func _spawn_sky_strike(attacker: Fighter, bolt_path: String, tele_path: String, target_x: float, dmg: float, delay: int, does_knockdown: bool = true) -> void:
	var p := PROJECTILE_SCRIPT.new() as Projectile
	p.setup_sky_strike(attacker, bolt_path, tele_path, target_x, dmg, delay, &"ultimate", does_knockdown)
	effects.add_child(p)
	projectiles.append(p)


func _spawn_visual(fx_path: String, pos: Vector2, dir: int, scale_val: float, life: int, additive: bool = true) -> void:
	var p := PROJECTILE_SCRIPT.new() as Projectile
	p.setup_visual(fx_path, pos, dir, scale_val, life, additive)
	effects.add_child(p)
	projectiles.append(p)


func _step_projectiles() -> void:
	var i := projectiles.size() - 1
	while i >= 0:
		var p := projectiles[i]
		p.step_tick(stage.arena_width)
		if p.finished:
			projectiles.remove_at(i)
			p.queue_free()
		i -= 1


## Dramatic Beam/Wave Clash when opposing projectiles collide mid-arena!
func _resolve_projectile_clashes() -> void:
	var count := projectiles.size()
	for i in count:
		var a := projectiles[i]
		if not a.is_active_combat() or a.kind != Projectile.Kind.TRAVEL:
			continue
		for j in range(i + 1, count):
			var b := projectiles[j]
			if not b.is_active_combat() or b.kind != Projectile.Kind.TRAVEL:
				continue
			if a.owner_fighter == b.owner_fighter:
				continue
			if a.get_rect().intersects(b.get_rect()):
				var mid := (a.sim_pos + b.sim_pos) * 0.5
				var col_a := a.owner_fighter.data.accent_color if a.owner_fighter != null else Color(0.4, 0.8, 1.0)
				var col_b := b.owner_fighter.data.accent_color if b.owner_fighter != null else Color(1.0, 0.6, 0.2)
				var both_ult := a.is_ultimate and b.is_ultimate
				CombatVfx.spawn_shockwave_ring(effects, mid, col_a, 290.0 if both_ult else 205.0, 0.46 if both_ult else 0.36, 1.0, 18.0 if both_ult else 14.0)
				CombatVfx.spawn_shockwave_ring(effects, mid, col_b, 220.0 if both_ult else 155.0, 0.40 if both_ult else 0.30, 1.0, 14.0 if both_ult else 10.0)
				CombatVfx.spawn_lightning_arc(effects, mid + Vector2(-90, -70), mid + Vector2(90, 70), Color(1.0, 0.96, 0.55), 0.42, 10.0 if both_ult else 8.0, 4)
				CombatVfx.spawn_lightning_arc(effects, mid + Vector2(-90, 70), mid + Vector2(90, -70), col_a.lerp(col_b, 0.5), 0.40, 9.0, 3)
				CombatVfx.spawn_radial_burst(effects, mid, Color(1.0, 0.94, 0.48), 32 if both_ult else 22, 640.0 if both_ult else 520.0, 0.44 if both_ult else 0.34)
				if both_ult:
					CombatVfx.spawn_energy_pillar(effects, Vector2(mid.x, Balance.FLOOR_Y), Color(1.0, 0.95, 0.52), 130.0, 0.50)
					CombatVfx.spawn_ground_shatter(effects, Vector2(mid.x, Balance.FLOOR_Y), Color(1.0, 0.92, 0.45), 1.25)
					camera_rig.punch_zoom(0.24)
					hud.flash_screen(Color(1.0, 0.97, 0.72), 0.55)
				else:
					hud.flash_screen(Color(1.0, 0.96, 0.65), 0.28)
				camera_rig.add_shake(1.05 if both_ult else 0.62)
				AudioManager.play_sfx(&"hit_special", 1.0)
				if a.is_ultimate and not b.is_ultimate:
					b.finished = true
				elif b.is_ultimate and not a.is_ultimate:
					a.finished = true
				else:
					a.finished = true
					b.finished = true
					hitstop_frames = maxi(hitstop_frames, 12 if both_ult else 7)
				break


func _resolve_projectile_hits() -> void:
	for p in projectiles:
		if p.finished or p.owner_fighter == null:
			continue
		var target := fighter2 if p.owner_fighter == fighter1 else fighter1
		var res := p.check_hit(target)
		if res == &"":
			continue
		var blocked := res == &"block"
		var hs := target.receive_projectile_hit(p.owner_fighter, p, blocked, sim_frame)
		p.register_contact()
		hitstop_frames = maxi(hitstop_frames, hs)
		camera_rig.add_shake(0.72 if p.is_ultimate else 0.32)
		if p.is_ultimate and not blocked:
			camera_rig.punch_zoom(0.12)


func _clear_projectiles() -> void:
	for p in projectiles:
		if is_instance_valid(p):
			p.queue_free()
	projectiles.clear()


func _update_z_order() -> void:
	var p1_priority := _visual_priority(fighter1)
	var p2_priority := _visual_priority(fighter2)
	if p1_priority >= p2_priority:
		fighter1.z_index = 2
		fighter2.z_index = 1
	else:
		fighter1.z_index = 1
		fighter2.z_index = 2


func _visual_priority(f: Fighter) -> int:
	match f.state_machine.state:
		StateMachine.State.SEIZE_THROW, StateMachine.State.PARRY:
			return 4
		StateMachine.State.ATTACK:
			return 3
		StateMachine.State.IDLE, StateMachine.State.WALK, StateMachine.State.DASH, StateMachine.State.JUMP, StateMachine.State.CROUCH:
			return 2
		StateMachine.State.BLOCK, StateMachine.State.CROUCH_BLOCK:
			return 1
		_:
			return 0


func _resolve_combat() -> void:
	var res1 := fighter1.evaluate_hitbox_against(fighter2)
	var res2 := fighter2.evaluate_hitbox_against(fighter1)
	if res1 == &"" and res2 == &"":
		return
	if res1 == &"grab" and res2 == &"grab":
		fighter1.consume_hitbox_hit()
		fighter2.consume_hitbox_hit()
		Fighter.resolve_seize_tech(fighter1, fighter2)
		hitstop_frames = maxi(hitstop_frames, 5)
		camera_rig.add_shake(0.25)
		return
	if res1 == &"grab" and res2 != &"":
		res1 = &""
	elif res2 == &"grab" and res1 != &"":
		res2 = &""

	if res1 != &"":
		fighter1.consume_hitbox_hit()
	if res2 != &"":
		fighter2.consume_hitbox_hit()

	_apply_combat_outcome(fighter1, fighter2, res1)
	_apply_combat_outcome(fighter2, fighter1, res2)


func _apply_combat_outcome(attacker: Fighter, defender: Fighter, outcome: StringName) -> void:
	match outcome:
		&"grab":
			attacker.start_seize_lock(defender)
			hitstop_frames = maxi(hitstop_frames, 4)
			camera_rig.add_shake(0.22)
		&"parry":
			defender.receive_parry_success(attacker)
			attacker.receive_parry_stagger(defender)
			hitstop_frames = maxi(hitstop_frames, Balance.HITSTOP_PARRY)
			camera_rig.add_shake(0.48)
			camera_rig.punch_zoom(0.12)
			hud.flash_screen(Color(1.0, 0.9, 0.3), 0.28)
		&"block":
			var hs := defender.receive_strike(attacker, true, sim_frame)
			hitstop_frames = maxi(hitstop_frames, hs)
			camera_rig.add_shake(0.18)
		&"hit":
			var was_counter := defender.is_counter_vulnerable()
			var hs := defender.receive_strike(attacker, false, sim_frame)
			hitstop_frames = maxi(hitstop_frames, hs)
			var shake := 0.26
			if attacker.hitbox.attack_name == &"ultimate":
				shake = 0.85
				camera_rig.punch_zoom(0.14)
			elif was_counter:
				shake = 0.60
				camera_rig.punch_zoom(0.11)
				hud.flash_screen(Color(1.0, 0.35, 0.15), 0.24)
			elif attacker.hitbox.knockdown or attacker.hitbox.launcher:
				shake = 0.50
				camera_rig.punch_zoom(0.07)
			camera_rig.add_shake(shake)


func _resolve_push_box() -> void:
	if fighter1.state_machine.state == StateMachine.State.SEIZE_THROW \
			or fighter2.state_machine.state == StateMachine.State.SEIZE_THROW:
		return
	var dx := fighter2.sim_pos.x - fighter1.sim_pos.x
	var dy := absf(fighter2.sim_pos.y - fighter1.sim_pos.y)
	var min_gap := Balance.BODY_HALF_WIDTH * 2.0
	if absf(dx) >= min_gap or dy > 64.0:
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


func _limit_separation() -> void:
	var dx := fighter2.sim_pos.x - fighter1.sim_pos.x
	var excess := absf(dx) - Balance.MAX_SEPARATION
	if excess <= 0.0:
		return
	var direction := 1.0 if dx > 0.0 else -1.0
	fighter1.nudge(direction * excess * 0.5)
	fighter2.nudge(-direction * excess * 0.5)


func export_state() -> Dictionary:
	return {
		"sim_frame": sim_frame,
		"hitstop_frames": hitstop_frames,
		"cutin_frames": cutin_frames,
		"ko_slowmo_frames": ko_slowmo_frames,
		"round_manager": round_manager.export_state(),
		"fighter1": fighter1.export_state(),
		"fighter2": fighter2.export_state(),
	}


func import_state(data: Dictionary) -> void:
	sim_frame = data["sim_frame"]
	hitstop_frames = data["hitstop_frames"]
	cutin_frames = data["cutin_frames"]
	ko_slowmo_frames = data["ko_slowmo_frames"]
	round_manager.import_state(data["round_manager"])
	fighter1.import_state(data["fighter1"])
	fighter2.import_state(data["fighter2"])
