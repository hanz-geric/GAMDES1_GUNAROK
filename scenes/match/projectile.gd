class_name Projectile
extends Node2D
## Deterministic 60 Hz projectile / wave / sky-strike FX actor (no Area2D,
## Design Plan v3 Section 13.3). Stepped explicitly by Match.step_simulation.
## Supports projectile vs melee-rush cancellation rules and multi-layer AAA CombatVfx!

enum Kind { TRAVEL, SKY_STRIKE, VISUAL_ONLY }

var owner_fighter: Fighter
var kind: Kind = Kind.TRAVEL
var sim_pos := Vector2.ZERO
var sim_vel := Vector2.ZERO
var gravity := 0.0
var facing := 1
var box_size := Vector2(70.0, 70.0)
var damage := 10.0
var height: StringName = &"mid"
var is_ultimate := false
var cancel_on_owner_hit := false # true for melee/rush Ults; false for already-fired projectiles!
var knockdown := false
var hitstun_frames := 20
var hitstop_frames := 4
var meter_gain := 6.0
var chip_ratio := Balance.CHIP_RATIO
var move_name: StringName = &"skill_ground"
var delay_frames := 0
var life_frames := 90
var hits_left := 1
var hit_cooldown := 0
var hit_interval := 8
var finished := false
var trail_type: StringName = &""
var trail_color: Color = Color(1.0, 0.88, 0.35)
var impact_shatter := false
var launch_pillar := false
var launch_slash := false
var launch_spear := false
var _active_started := false
var _tick_count := 0

var _sprite: AnimatedSprite2D
var _telegraph_sprite: AnimatedSprite2D


func setup_travel(
	attacker: Fighter,
	fx_frames_path: String,
	start_pos: Vector2,
	vel: Vector2,
	size: Vector2,
	dmg: float,
	move_id: StringName,
	opts: Dictionary = {}
) -> void:
	owner_fighter = attacker
	kind = Kind.TRAVEL
	facing = attacker.facing
	sim_pos = start_pos
	sim_vel = vel
	gravity = float(opts.get("gravity", 0.0))
	box_size = size
	damage = dmg
	move_name = move_id
	height = opts.get("height", &"mid")
	is_ultimate = bool(opts.get("is_ultimate", false))
	cancel_on_owner_hit = bool(opts.get("cancel_on_owner_hit", false))
	knockdown = bool(opts.get("knockdown", is_ultimate))
	hitstun_frames = int(opts.get("hitstun", 22))
	hitstop_frames = int(opts.get("hitstop", 5 if is_ultimate else 4))
	meter_gain = float(opts.get("meter_gain", 0.0 if is_ultimate else Balance.METER_GAIN_SKILL))
	chip_ratio = Balance.ULTIMATE_CHIP_RATIO if is_ultimate else Balance.CHIP_RATIO
	delay_frames = int(opts.get("delay_frames", 0))
	life_frames = int(opts.get("life_frames", 95))
	hits_left = int(opts.get("hits", 1))
	hit_interval = int(opts.get("hit_interval", 9))
	trail_type = opts.get("trail_type", &"")
	trail_color = opts.get("trail_color", attacker.data.accent_color)
	impact_shatter = bool(opts.get("impact_shatter", false))
	launch_pillar = bool(opts.get("launch_pillar", false))
	launch_slash = bool(opts.get("launch_slash", false))
	launch_spear = bool(opts.get("launch_spear", false))

	var scale_val: float = float(opts.get("scale", 1.75))
	var additive: bool = bool(opts.get("additive", true))
	var tint: Color = opts.get("tint", Color.WHITE)
	var rot_deg: float = float(opts.get("rotation_deg", 0.0))
	_build_sprite(fx_frames_path, scale_val, additive, tint, rot_deg)
	if delay_frames > 0:
		visible = false
	global_position = sim_pos
	z_index = 5


func setup_sky_strike(
	attacker: Fighter,
	bolt_frames_path: String,
	telegraph_frames_path: String,
	target_x: float,
	dmg: float,
	delay: int,
	move_id: StringName,
	does_knockdown: bool = true
) -> void:
	owner_fighter = attacker
	kind = Kind.SKY_STRIKE
	facing = attacker.facing
	sim_pos = Vector2(target_x, Balance.FLOOR_Y)
	box_size = Vector2(148.0, 460.0)
	damage = dmg
	move_name = move_id
	height = &"mid"
	is_ultimate = true
	cancel_on_owner_hit = false # Sky lightning already called from the heavens!
	knockdown = does_knockdown
	hitstun_frames = 28
	hitstop_frames = Balance.HITSTOP_ULTIMATE if does_knockdown else 6
	meter_gain = 0.0
	chip_ratio = Balance.ULTIMATE_CHIP_RATIO
	delay_frames = delay
	life_frames = 28
	hits_left = 1
	trail_color = Color(1.0, 0.94, 0.36)

	if ResourceLoader.exists(telegraph_frames_path):
		_telegraph_sprite = AnimatedSprite2D.new()
		_telegraph_sprite.sprite_frames = load(telegraph_frames_path)
		_telegraph_sprite.scale = Vector2(2.2, 1.7)
		_telegraph_sprite.position = Vector2(0, -48)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_telegraph_sprite.material = mat
		add_child(_telegraph_sprite)
		_telegraph_sprite.play(&"default")

	_build_sprite(bolt_frames_path, 2.65, true, Color.WHITE, 0.0)
	_sprite.position = Vector2(0, -295)
	_sprite.visible = false
	global_position = sim_pos
	z_index = 6


func setup_visual(fx_frames_path: String, pos: Vector2, dir: int, scale_val: float, frames_life: int, additive: bool = true, tint: Color = Color.WHITE) -> void:
	kind = Kind.VISUAL_ONLY
	facing = dir
	sim_pos = pos
	life_frames = frames_life
	_build_sprite(fx_frames_path, scale_val, additive, tint, 0.0)
	global_position = sim_pos
	z_index = 6


func _build_sprite(frames_path: String, scale_val: float, additive: bool, tint: Color, rot_deg: float) -> void:
	_sprite = AnimatedSprite2D.new()
	if ResourceLoader.exists(frames_path):
		_sprite.sprite_frames = load(frames_path)
	_sprite.scale = Vector2(scale_val, scale_val)
	_sprite.flip_h = facing < 0
	_sprite.rotation_degrees = rot_deg * float(facing)
	_sprite.modulate = tint
	if additive:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_sprite.material = mat
	add_child(_sprite)
	if _sprite.sprite_frames != null:
		_sprite.play(&"default")


func step_tick(arena_width: float) -> void:
	if finished:
		return
	var fx_parent := get_parent()
	if delay_frames > 0:
		delay_frames -= 1
		if kind == Kind.SKY_STRIKE and delay_frames % 5 == 0 and fx_parent != null:
			CombatVfx.spawn_shockwave_ring(fx_parent, sim_pos, trail_color, 95.0, 0.22, 0.25, 5.0)
		if delay_frames == 0:
			visible = true
			_active_started = true
			if kind == Kind.SKY_STRIKE:
				if _telegraph_sprite != null:
					_telegraph_sprite.visible = false
				if _sprite != null:
					_sprite.visible = true
					_sprite.frame = 0
					_sprite.play(&"default")
				if fx_parent != null:
					CombatVfx.spawn_energy_pillar(fx_parent, sim_pos, trail_color, 130.0, 0.34)
					CombatVfx.spawn_lightning_arc(fx_parent, Vector2(sim_pos.x, sim_pos.y - 600.0), sim_pos, trail_color, 0.34, 11.0, 4)
					CombatVfx.spawn_ground_shatter(fx_parent, sim_pos, trail_color, 1.45)
					CombatVfx.spawn_shockwave_ring(fx_parent, sim_pos, trail_color, 235.0, 0.38, 0.26, 13.0)
					CombatVfx.spawn_radial_burst(fx_parent, sim_pos + Vector2(0, -35), trail_color, 22, 540.0, 0.36)
				AudioManager.play_sfx(&"thunder", 2.5)
			else:
				if _sprite != null:
					_sprite.frame = 0
					_sprite.play(&"default")
				if fx_parent != null:
					if launch_slash:
						CombatVfx.spawn_slash_arc(fx_parent, sim_pos, facing, trail_color, 135.0, -1.45, 1.35, 22.0, 0.24)
						CombatVfx.spawn_slash_arc(fx_parent, sim_pos, -facing, Color(1.0, 1.0, 1.0), 120.0, -1.35, 1.35, 14.0, 0.22)
					if launch_spear:
						CombatVfx.spawn_spear_thrust(fx_parent, sim_pos, facing, trail_color, 220.0, 0.28)
					if launch_pillar:
						CombatVfx.spawn_energy_pillar(fx_parent, Vector2(sim_pos.x, Balance.FLOOR_Y), trail_color, 125.0, 0.38)
						CombatVfx.spawn_ground_shatter(fx_parent, Vector2(sim_pos.x, Balance.FLOOR_Y), trail_color, 1.35)
					if is_ultimate:
						CombatVfx.spawn_shockwave_ring(fx_parent, sim_pos, trail_color, 115.0, 0.24, 1.0, 8.0)
		return

	_active_started = true
	_tick_count += 1
	if hit_cooldown > 0:
		hit_cooldown -= 1

	if kind == Kind.TRAVEL:
		sim_vel.y += gravity * Balance.DT
		sim_pos += sim_vel * Balance.DT
		if fx_parent != null and trail_type != &"":
			if trail_type == &"dust" and _tick_count % 4 == 0:
				CombatVfx.spawn_dust_puff(fx_parent, Vector2(sim_pos.x, Balance.FLOOR_Y), facing, 5)
			elif trail_type == &"lightning" and _tick_count % 4 == 0:
				CombatVfx.spawn_lightning_arc(fx_parent, sim_pos, sim_pos + Vector2(-float(facing) * 75.0, -20.0), trail_color, 0.16, 5.0, 2)
			elif trail_type == &"fire" and _tick_count % 4 == 0:
				CombatVfx.spawn_radial_burst(fx_parent, sim_pos, trail_color, 6, 190.0, 0.20)
			elif trail_type == &"slash" and _tick_count % 6 == 0:
				CombatVfx.spawn_shockwave_ring(fx_parent, sim_pos, trail_color, 85.0, 0.20, 1.0, 6.0)
			elif trail_type == &"frost" and _tick_count % 3 == 0:
				CombatVfx.spawn_radial_burst(fx_parent, sim_pos, trail_color, 7, 220.0, 0.18)

		if sim_pos.y > Balance.FLOOR_Y - 12.0:
			sim_pos.y = Balance.FLOOR_Y - 12.0
			if gravity > 0.0:
				if impact_shatter and fx_parent != null:
					CombatVfx.spawn_ground_shatter(fx_parent, Vector2(sim_pos.x, Balance.FLOOR_Y), trail_color, 1.1)
					CombatVfx.spawn_shockwave_ring(fx_parent, Vector2(sim_pos.x, Balance.FLOOR_Y), trail_color, 145.0, 0.28, 0.26, 9.0)
				finished = true
		if sim_pos.x < -140.0 or sim_pos.x > arena_width + 140.0:
			finished = true

	life_frames -= 1
	if life_frames <= 0:
		finished = true
	global_position = sim_pos


func get_rect() -> Rect2:
	if kind == Kind.SKY_STRIKE:
		return Rect2(sim_pos.x - box_size.x * 0.5, sim_pos.y - box_size.y, box_size.x, box_size.y)
	return Rect2(sim_pos.x - box_size.x * 0.5, sim_pos.y - box_size.y * 0.5, box_size.x, box_size.y)


func is_active_combat() -> bool:
	return not finished and kind != Kind.VISUAL_ONLY and _active_started and hits_left > 0


func check_hit(defender: Fighter) -> StringName:
	if not is_active_combat() or hit_cooldown > 0:
		return &""
	if defender == null or defender == owner_fighter or not defender.can_be_hit():
		return &""
	if height == &"high" and defender.is_crouching():
		return &""
	if height == &"low" and defender.is_airborne():
		return &""
	if not get_rect().intersects(defender.hurtbox.get_rect(defender.sim_pos)):
		return &""
	return &"block" if defender.is_blocking() else &"hit"


func register_contact() -> void:
	hits_left -= 1
	hit_cooldown = hit_interval
	var fx_parent := get_parent()
	if fx_parent != null and is_ultimate:
		CombatVfx.spawn_shockwave_ring(fx_parent, sim_pos, trail_color, 138.0, 0.26, 1.0, 10.0)
		CombatVfx.spawn_radial_burst(fx_parent, sim_pos, trail_color, 14, 420.0, 0.28)
		if impact_shatter:
			CombatVfx.spawn_ground_shatter(fx_parent, Vector2(sim_pos.x, Balance.FLOOR_Y), trail_color, 1.25)
	if hits_left <= 0 and kind == Kind.TRAVEL:
		finished = true
