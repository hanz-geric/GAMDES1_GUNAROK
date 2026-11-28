class_name Balance
extends RefCounted
## Every tuning number from Design Plan v3+ lives here. All combat durations
## are counted in 60 Hz frames (Section 13.3 deterministic simulation rules).

# Simulation tick (Section 13.3)
const TICK_RATE := 60
const DT := 1.0 / 60.0

# Arena & Spacing (tuned for 2x 192x128 pixel sprites so bodies never overlap)
const ARENA_WIDTH := 1600.0
const WALL_THICKNESS := 40.0
const FLOOR_Y := 620.0
const SCREEN_WIDTH := 1280.0
const MAX_SEPARATION := 1120.0 # screen width minus a 160 px margin
const SPAWN_OFFSET := 240.0 # fighters spawn at mid-distance
const BODY_HALF_WIDTH := 48.0 # minimum grounded centre-to-centre gap = 96 px
const HURTBOX_STAND_SIZE := Vector2(76.0, 170.0)
const HURTBOX_CROUCH_SIZE := Vector2(76.0, 118.0)

# Rounds (counted in 60 Hz frames; *_TIME constants are visual tween hints only)
const START_HEALTH := 100
const ROUND_TIME := 60
const ROUND_TIME_FRAMES := ROUND_TIME * TICK_RATE
const ROUNDS_TO_WIN := 2
const MAX_DRAW_REPLAYS := 2
const INTRO_CARD_FRAMES := 120 # 2.0 s
const BANNER_FRAMES := 96 # 1.6 s
const ROUND_END_FRAMES := 144 # 2.4 s
const CUTIN_FRAMES := 54 # 0.90 s dramatic Ultimate side cut-in freeze (Section 8)
const INTRO_CARD_TIME := 2.0
const BANNER_TIME := 1.6
const ROUND_END_TIME := 2.4

# Ultimate bar (tuned so active play earns Ultimates mid-match before KO!)
const METER_MAX := 100.0
const ULTIMATE_COST := 100.0
const METER_GAIN_LIGHT := 10.0
const METER_GAIN_HEAVY := 16.0
const METER_GAIN_SEIZE := 18.0
const METER_GAIN_SKILL := 14.0
const METER_GAIN_PARRY := 15.0
const METER_GAIN_BLOCKED_ATTACKER := 3.0
const METER_GAIN_BLOCKED_DEFENDER := 4.0
const METER_PER_DAMAGE_TAKEN := 0.55 # comeback meter on damage taken (Open Decision 2)

# Damage, chip, combos & counter-hits
const CHIP_RATIO := 0.25
const ULTIMATE_CHIP_RATIO := 0.50
const DAMAGE_BY_RATING := [0.85, 0.92, 1.0, 1.08, 1.15]
const COMBO_SCALING := [1.0, 0.85, 0.70, 0.58, 0.48]
const COUNTER_DAMAGE_MULT := 1.30
const COUNTER_EXTRA_HITSTUN := 8

# Hitstop (impact freeze frames for AAA crunchy game feel)
const HITSTOP_LIGHT := 3
const HITSTOP_HEAVY := 6
const HITSTOP_SKILL := 5
const HITSTOP_PARRY := 8
const HITSTOP_COUNTER := 7
const HITSTOP_ULTIMATE := 10

# Input chords, anti-spam punish, landing recovery, parry & seize
const CHORD_BUFFER_FRAMES := 4 # ~0.067 s wait for simultaneous F+G
const SKILL_CANCEL_WINDOW_FRAMES := 6 # startup frames where pressing other attack upgrades to skill
const COMBO_CANCEL_EXTRA_FRAMES := 10 # recovery frames after hit where higher-tier cancels work
const SPAM_MEMORY_FRAMES := 180 # 3.0 s decay window per move for anti-spam heat
const LANDING_RECOVERY_FRAMES := 16 # landing lag after air dive attacks (punishes W+G spam!)
const PARRY_WINDOW_FRAMES := 8 # ~0.13 s
const PARRY_HOLD_THRESHOLD_FRAMES := 15 # 0.25 s (Open Decision 12)
const PARRY_LOCKOUT_FRAMES := 18 # 0.30 s unable to block on mistimed tap
const PARRY_FAIL_ANIM_FRAMES := 10
const PARRY_SUCCESS_ANIM_FRAMES := 8
const PARRY_STAGGER_FRAMES := 32 # 0.53 s attacker stagger
const SEIZE_THROW_FRAMES := 24 # 0.40 s lock before knockdown release
const SEIZE_TECH_WINDOW_FRAMES := 9 # 0.15 s defender press-H escape window
const SEIZE_TECH_RECOVERY_FRAMES := 12
const SEIZE_TECH_PUSHBACK := 340.0

# Skill cooldowns in frames (5 directional F+G skills, start on press, reset each round)
const SKILL_COOLDOWNS := {
	&"skill_ground": 270,
	&"skill_forward": 300,
	&"skill_back": 300,
	&"skill_air": 330,
	&"skill_low": 330,
}

## Frame data for directional normals, seize, skills, and ultimate (60 Hz frames
## before speed-rating scaling).
## cancel_tier: on hit, moves cancel cleanly into any higher cancel_tier (1 -> 2 -> 3 -> 4)!
const ATTACKS := {
	# --- Light (F) directional family (Tier 1 combo starters) ---
	&"light": {
		"base_damage": 6.0, "startup": 5, "active": 5, "recovery": 9,
		"height": &"high", "hitstun": 20, "reach_scale": 1.0,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_LIGHT, "category": &"normal",
		"cancel_tier": 1, "hitstop": HITSTOP_LIGHT,
		"anim": &"light", "move_cooldown": 0,
	},
	&"forward_light": {
		"base_damage": 7.0, "startup": 8, "active": 5, "recovery": 12,
		"height": &"mid", "hitstun": 22, "reach_scale": 1.18,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_LIGHT + 2.0, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_LIGHT + 1,
		"lunge_speed": 240.0, "anim": &"light", "move_cooldown": 36,
	},
	&"back_light": {
		"base_damage": 6.0, "startup": 7, "active": 5, "recovery": 11,
		"height": &"high", "hitstun": 19, "reach_scale": 1.08,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_LIGHT, "category": &"normal",
		"cancel_tier": 1, "hitstop": HITSTOP_LIGHT,
		"lunge_speed": -170.0, "anim": &"parry", "move_cooldown": 36,
	},
	&"crouch_light": {
		"base_damage": 5.0, "startup": 5, "active": 5, "recovery": 8,
		"height": &"low", "hitstun": 19, "reach_scale": 1.02,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_LIGHT, "category": &"normal",
		"cancel_tier": 1, "hitstop": HITSTOP_LIGHT,
		"anim": &"crouch_light", "move_cooldown": 0,
	},
	&"jump_light": {
		"base_damage": 6.0, "startup": 6, "active": 8, "recovery": 10,
		"height": &"mid", "hitstun": 22, "reach_scale": 1.10,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_LIGHT, "category": &"normal",
		"cancel_tier": 1, "hitstop": HITSTOP_LIGHT,
		"air_only": true, "anim": &"light", "move_cooldown": 34,
	},
	# --- Heavy (G) directional family (Tier 2 linkers & finishers) ---
	&"heavy": {
		"base_damage": 12.0, "startup": 11, "active": 6, "recovery": 16,
		"height": &"mid", "hitstun": 24, "reach_scale": 1.15,
		"knockdown": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY,
		"anim": &"heavy", "move_cooldown": 0,
	},
	&"forward_heavy": {
		"base_damage": 14.0, "startup": 14, "active": 6, "recovery": 20,
		"height": &"mid", "hitstun": 24, "reach_scale": 1.28,
		"knockdown": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY + 2.0, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY,
		"lunge_speed": 310.0, "anim": &"heavy", "move_cooldown": 52,
	},
	&"back_heavy": {
		"base_damage": 11.0, "startup": 9, "active": 7, "recovery": 18,
		"height": &"anti_air", "hitstun": 26, "reach_scale": 1.14,
		"knockdown": false, "launcher": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY,
		"lunge_speed": -80.0, "anim": &"victory", "move_cooldown": 45,
	},
	&"crouch_heavy": {
		"base_damage": 9.0, "startup": 10, "active": 6, "recovery": 16,
		"height": &"low", "hitstun": 22, "reach_scale": 1.16,
		"knockdown": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY - 1,
		"anim": &"crouch_heavy", "move_cooldown": 38,
	},
	&"jump_heavy": {
		"base_damage": 11.0, "startup": 10, "active": 8, "recovery": 16,
		"height": &"mid", "hitstun": 22, "reach_scale": 1.18,
		"knockdown": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY,
		"air_only": true, "dive_speed": 460.0, "landing_lag": LANDING_RECOVERY_FRAMES,
		"anim": &"heavy", "move_cooldown": 54,
	},
	# --- Seize / Tactical Arts (WASD + H — all 5 directions!) ---
	&"seize": {
		"base_damage": 10.0, "startup": 10, "active": 6, "recovery": 18,
		"height": &"grab", "hitstun": 0, "reach_scale": 1.12,
		"knockdown": true, "parriable": false, "is_grab": true,
		"meter_gain": METER_GAIN_SEIZE, "category": &"normal",
		"cancel_tier": 0, "hitstop": HITSTOP_HEAVY,
		"lunge_speed": 165.0, "anim": &"seize", "move_cooldown": 38,
	},
	&"forward_seize": {
		"base_damage": 12.0, "startup": 12, "active": 7, "recovery": 18,
		"height": &"mid", "hitstun": 26, "reach_scale": 1.24,
		"knockdown": true, "guard_crush": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_SEIZE, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY + 1,
		"lunge_speed": 395.0, "anim": &"seize_throw", "move_cooldown": 56,
	},
	&"back_seize": {
		"base_damage": 8.0, "startup": 6, "active": 7, "recovery": 13,
		"height": &"mid", "hitstun": 22, "reach_scale": 1.15,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_LIGHT + 4.0, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_LIGHT + 1,
		"lunge_speed": -540.0, "hop_vel": -320.0, "evade_invuln": 10,
		"anim": &"parry", "move_cooldown": 46,
	},
	&"crouch_seize": {
		"base_damage": 9.5, "startup": 8, "active": 7, "recovery": 16,
		"height": &"low", "hitstun": 24, "reach_scale": 1.24,
		"knockdown": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY,
		"lunge_speed": 320.0, "anim": &"crouch_heavy", "move_cooldown": 48,
	},
	&"jump_seize": {
		"base_damage": 12.0, "startup": 8, "active": 9, "recovery": 14,
		"height": &"mid", "hitstun": 28, "reach_scale": 1.22,
		"knockdown": false, "launcher": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY,
		"air_only": true, "dive_speed": 560.0, "landing_lag": 12,
		"anim": &"skill_air", "move_cooldown": 50,
	},
	# --- F+H & G+H Combination Arts (full WASD x F/G/H arsenal!) ---
	&"feint_step": {
		"base_damage": 8.5, "startup": 6, "active": 6, "recovery": 11,
		"height": &"mid", "hitstun": 24, "reach_scale": 1.25,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_LIGHT + 4.0, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_LIGHT + 2,
		"lunge_speed": 490.0, "evade_invuln": 6, "anim": &"skill_ground", "move_cooldown": 44,
	},
	&"power_launcher": {
		"base_damage": 13.0, "startup": 11, "active": 7, "recovery": 18,
		"height": &"mid", "hitstun": 34, "reach_scale": 1.20,
		"knockdown": false, "launcher": true, "super_launch": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_HEAVY + 2.0, "category": &"normal",
		"cancel_tier": 2, "hitstop": HITSTOP_HEAVY + 1,
		"lunge_speed": 170.0, "anim": &"heavy", "move_cooldown": 54,
	},
	# --- 5 Directional Skills (WASD + F+G chords — Tier 3, cancelable into Ultimate!) ---
	&"skill_ground": {
		"base_damage": 15.0, "startup": 9, "active": 7, "recovery": 17,
		"height": &"mid", "hitstun": 26, "reach_scale": 1.38,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_SKILL, "category": &"skill",
		"cancel_tier": 3, "hitstop": HITSTOP_SKILL,
		"lunge_speed": 190.0, "anim": &"skill_ground", "move_cooldown": 0,
	},
	&"skill_forward": {
		"base_damage": 16.0, "startup": 10, "active": 9, "recovery": 18,
		"height": &"mid", "hitstun": 28, "reach_scale": 1.42,
		"knockdown": true, "guard_crush": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_SKILL + 2.0, "category": &"skill",
		"cancel_tier": 3, "hitstop": HITSTOP_SKILL + 1,
		"lunge_speed": 460.0, "anim": &"heavy", "move_cooldown": 0,
	},
	&"skill_back": {
		"base_damage": 13.0, "startup": 7, "active": 8, "recovery": 15,
		"height": &"mid", "hitstun": 26, "reach_scale": 1.30,
		"knockdown": false, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_SKILL, "category": &"skill",
		"cancel_tier": 3, "hitstop": HITSTOP_SKILL,
		"lunge_speed": -540.0, "hop_vel": -280.0, "evade_invuln": 11,
		"anim": &"skill_ground", "move_cooldown": 0,
	},
	&"skill_air": {
		"base_damage": 14.0, "startup": 8, "active": 10, "recovery": 14,
		"height": &"mid", "hitstun": 24, "reach_scale": 1.25,
		"knockdown": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_SKILL, "category": &"skill",
		"cancel_tier": 3, "hitstop": HITSTOP_SKILL,
		"air_only": true, "landing_lag": 12, "anim": &"skill_air", "move_cooldown": 0,
	},
	&"skill_low": {
		"base_damage": 13.0, "startup": 10, "active": 7, "recovery": 17,
		"height": &"low", "hitstun": 24, "reach_scale": 1.28,
		"knockdown": true, "parriable": true, "is_grab": false,
		"meter_gain": METER_GAIN_SKILL, "category": &"skill",
		"cancel_tier": 3, "hitstop": HITSTOP_SKILL,
		"lunge_speed": 140.0, "anim": &"skill_low", "move_cooldown": 0,
	},
	# --- Ultimate (T — Tier 4 Super Cancel Finisher with Dynamic Movement Choreography!) ---
	&"ultimate": {
		"base_damage": 35.0, "startup": 14, "active": 24, "recovery": 20,
		"height": &"mid", "hitstun": 0, "reach_scale": 1.65,
		"knockdown": true, "parriable": false, "is_grab": false,
		"meter_gain": 0.0, "flat_damage": true, "chip_ratio": ULTIMATE_CHIP_RATIO,
		"category": &"ultimate", "cancel_tier": 4, "hitstop": HITSTOP_ULTIMATE,
		"lunge_speed": 280.0, "anim": &"ultimate", "move_cooldown": 0,
	},
}

# Movement (snappy SF6/KOF feel: brisk walk, crisp arc jump, fast double-tap dash)
const WALK_SPEED_BASE := 275.0
const WALK_SPEED_PER_RATING := 42.0
const BACKWALK_SCALE := 0.88
const REACH_BASE := 76.0
const REACH_PER_RATING := 17.0
const TIMING_SCALE_BY_SPEED := [1.08, 1.03, 0.98, 0.92, 0.86]
const GRAVITY := 4100.0
const JUMP_VELOCITY := -1130.0
const DOUBLE_JUMP_VELOCITY := -980.0 # mid-air second jump to vault over opponents & corners!
const JUMP_FORWARD_SPEED := 365.0
const AIR_DRIFT_ACCEL := 1150.0
const AIR_MAX_SPEED := 385.0
const DASH_TAP_WINDOW_FRAMES := 14 # forgiving double-tap window (~0.23 s)
const DASH_FRAMES := 11
const DASH_COOLDOWN_FRAMES := 10
const DASH_FORWARD_SPEED := 760.0
const DASH_BACK_SPEED := 660.0
const BACKDASH_INVULN_FRAMES := 5 # brief backdash evade frames!
const INPUT_BUFFER_FRAMES := 6 # buffered attacks fire on frame 1 after recovery!
const GROUND_FRICTION := 3100.0
const KNOCKDOWN_FRAMES := 42 # 0.70 s
const GETUP_FRAMES := 24 # 0.40 s
const WAKEUP_INVULN_FRAMES := 12 # brief wakeup invulnerability without killing corner pressure
const BURST_METER_COST := 25.0 # Block+Seize (J+H) guard burst (FREE after 3 corner hits!)
const BURST_PUSHBACK := 540.0
const CORNER_WALL_BOUNCE_X := 220.0
const JUMP_LAND_GRACE_FRAMES := 3 # 0.05 s
const HIT_PUSHBACK := 215.0
const BLOCK_PUSHBACK := 185.0
const PARRY_PUSHBACK := 150.0
const KNOCKDOWN_LAUNCH := Vector2(325.0, -455.0)
const ANTI_AIR_LAUNCH := Vector2(145.0, -590.0)
const SUPER_LAUNCH := Vector2(130.0, -690.0) # G+H sky launcher for air-juggle combos!

# Per-champion kit specializations so every warrior plays & feels unmistakable!
const CHAMPION_KITS := {
	&"zeus": {
		"skill_ground_lunge": 90.0, "skill_forward_lunge": 620.0, "skill_back_lunge": -560.0,
		"skill_air_dive": 540.0, "skill_low_lunge": 110.0,
		"damage_bonus": 1.08, "reach_bonus": 20.0,
	},
	&"leonidas": {
		"skill_ground_lunge": 460.0, "skill_forward_lunge": 540.0, "skill_back_lunge": -320.0,
		"skill_air_dive": 560.0, "skill_low_lunge": 220.0,
		"forward_heavy_armor": true, "reach_bonus": 16.0,
	},
	&"julius_caesar": {
		"skill_ground_lunge": 290.0, "skill_forward_lunge": 460.0, "skill_back_lunge": -420.0,
		"skill_air_dive": 500.0, "skill_low_lunge": 140.0,
		"reach_bonus": 10.0,
	},
	&"ragnar": {
		"skill_ground_lunge": 120.0, "skill_forward_lunge": 520.0, "skill_back_lunge": -420.0,
		"skill_air_dive": 600.0, "skill_low_lunge": 190.0,
		"forward_heavy_armor": true, "damage_bonus": 1.06,
	},
	&"musashi": {
		"skill_ground_lunge": 320.0, "skill_forward_lunge": 640.0, "skill_back_lunge": -520.0,
		"skill_air_dive": 460.0, "skill_low_lunge": 260.0,
		"timing_bonus": 0.93, "reach_bonus": 10.0,
	},
	&"lapu_lapu": {
		"skill_ground_lunge": 280.0, "skill_forward_lunge": 520.0, "skill_back_lunge": -480.0,
		"skill_air_dive": 520.0, "skill_low_lunge": 240.0,
		"forward_heavy_armor": true, "timing_bonus": 0.95,
	},
	&"simo_hayha": {
		"skill_ground_lunge": -180.0, "skill_forward_lunge": 560.0, "skill_forward_hop": -520.0,
		"skill_back_lunge": -700.0, "skill_back_hop": -320.0,
		"skill_air_dive": -150.0, "skill_low_lunge": -160.0,
		"reach_bonus": 18.0,
	},
	&"nai_khanom_tom": {
		"skill_ground_lunge": 490.0, "skill_forward_lunge": 580.0, "skill_back_lunge": -480.0,
		"skill_air_dive": 560.0, "skill_low_lunge": 310.0,
		"timing_bonus": 0.90, "damage_bonus": 1.04,
	},
	&"thor": {
		"skill_ground_lunge": 140.0, "skill_forward_lunge": 580.0, "skill_back_lunge": -440.0,
		"skill_air_dive": 640.0, "skill_low_lunge": 180.0,
		"forward_heavy_armor": true, "damage_bonus": 1.10, "reach_bonus": 16.0,
	},
	&"susanoo": {
		"skill_ground_lunge": 240.0, "skill_forward_lunge": 640.0, "skill_back_lunge": -520.0,
		"skill_air_dive": 520.0, "skill_low_lunge": 200.0,
		"timing_bonus": 0.94, "damage_bonus": 1.08, "reach_bonus": 22.0,
	},
	&"anubis": {
		"skill_ground_lunge": 120.0, "skill_forward_lunge": 580.0, "skill_back_lunge": -560.0,
		"skill_air_dive": 540.0, "skill_low_lunge": 140.0,
		"timing_bonus": 0.94, "damage_bonus": 1.06, "reach_bonus": 24.0,
	},
}

# Arcade (GDD Sections 6.1 and II Outcome)
const ARCADE_CONTINUES := 3
const SCORE_MATCH_WIN := 1000
const SCORE_PER_HEALTH := 10
const SCORE_PERFECT := 500


static func scale_frames(base_frames: int, scale: float) -> int:
	return maxi(1, roundi(float(base_frames) * scale))


static func combo_scale(combo_hit_index: int) -> float:
	var idx := clampi(combo_hit_index - 1, 0, COMBO_SCALING.size() - 1)
	return COMBO_SCALING[idx]


## Simo Häyhä ("The White Death") distance sniper multiplier:
## Modest damage at point-blank CQC, devastating high-caliber damage at long range!
static func simo_distance_multiplier(dist: float) -> float:
	if dist >= 640.0:
		return 1.70
	if dist >= 420.0:
		return 1.40
	if dist >= 220.0:
		return 1.10
	return 0.85
