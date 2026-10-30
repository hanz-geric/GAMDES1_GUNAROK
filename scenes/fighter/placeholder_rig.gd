class_name PlaceholderRig
extends Node2D
## Team-made placeholder art. It draws a warrior from simple shapes in every
## pose so the build is fully playable before the sprite sheets are done.
## When a WarriorData has SpriteFrames, Fighter hides this node and plays
## the AnimatedSprite2D instead. Drawn facing right; Fighter flips scale.x.

const THIGH := 46.0
const SHIN := 44.0
const UPPER_ARM := 34.0
const FOREARM := 32.0
const TORSO := 58.0
const HEAD_R := 15.0
const LEG_W := 13.0
const ARM_W := 11.0
const TORSO_W := 30.0
const OUTLINE_W := 5.0
const WOOD := Color(0.45, 0.3, 0.16)
const STEEL := Color(0.82, 0.84, 0.88)
const BRONZE := Color(0.74, 0.53, 0.22)

var data: WarriorData
var outline_color := Color(0.08, 0.08, 0.1)
var torso_color := Color.GRAY
var leg_color := Color.DIM_GRAY
var pose: StringName = &"idle"
var progress := 0.0
var special_ready := false
var _time := 0.0
var _flash := 0.0


class Pose:
	var hip := -90.0
	var lean := 0.05
	var rot := 0.0
	var front_upper := 0.9
	var front_lower := 2.4
	var back_upper := 0.5
	var back_lower := 2.5
	var front_thigh := 0.25
	var front_shin := 0.05
	var back_thigh := -0.25
	var back_shin := -0.05


func setup(warrior: WarriorData, alt_palette: bool, outline: Color) -> void:
	data = warrior
	outline_color = outline
	torso_color = warrior.alt_primary_color if alt_palette else warrior.primary_color
	leg_color = warrior.alt_secondary_color if alt_palette else warrior.secondary_color
	queue_redraw()


func set_pose(new_pose: StringName, new_progress: float, is_special_ready: bool) -> void:
	pose = new_pose
	progress = new_progress
	special_ready = is_special_ready


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta * 7.0, 0.0)
	queue_redraw()


# --- Poses -----------------------------------------------------------------

## 0 = guard, 1 = fully extended. Attack progress runs 0 to 0.35 in startup
## (a short pull-back, the wind-up), 0.35 to 0.55 active, then recovery.
func _extension() -> float:
	if progress < 0.35:
		return -0.3 * (progress / 0.35)
	if progress < 0.55:
		return 1.0
	return 1.0 - (progress - 0.55) / 0.45


func _compute_pose() -> Pose:
	var p := Pose.new()
	var e := _extension()
	var k := maxf(e, 0.0)
	match pose:
		&"idle":
			p.hip += sin(_time * 3.2) * 2.0
		&"walk":
			var swing := sin(_time * 10.0) * 0.45
			p.front_thigh = 0.05 + swing
			p.front_shin = -0.05 + swing * 0.5 - absf(swing) * 0.3
			p.back_thigh = 0.05 - swing
			p.back_shin = -0.05 - swing * 0.5 - absf(swing) * 0.3
			p.hip = -89.0 - absf(sin(_time * 10.0)) * 3.0
		&"crouch":
			_crouch_legs(p)
		&"crouch_block":
			_crouch_legs(p)
			_block_arms(p)
		&"jump":
			p.front_thigh = 1.3
			p.front_shin = -0.2
			p.back_thigh = 0.5
			p.back_shin = -0.8
		&"block":
			_block_arms(p)
			p.lean = -0.05
		&"punch":
			p.front_upper = lerpf(0.9, 1.62, k) + minf(e, 0.0) * 1.2
			p.front_lower = lerpf(2.4, 1.62, k) - minf(e, 0.0) * 0.5
			p.lean = 0.05 + 0.15 * e
			p.front_thigh = 0.35
			p.back_thigh = -0.35
		&"kick":
			p.front_thigh = lerpf(0.25, 1.2, k) + minf(e, 0.0)
			p.front_shin = lerpf(0.05, 1.5, k)
			p.lean = lerpf(0.05, -0.3, k)
			p.back_thigh = -0.15
		&"special":
			p.lean = 0.1 + 0.3 * k
			p.front_upper = lerpf(0.9, 1.6, k) + minf(e, 0.0) * 1.5
			p.front_lower = lerpf(2.4, 1.6, k)
			p.back_upper = lerpf(0.5, 1.4, k)
			p.back_lower = lerpf(2.5, 1.7, k)
			p.front_thigh = 0.25 + 0.7 * k
			p.front_shin = 0.15
			p.back_thigh = -0.25 - 0.6 * k
			p.back_shin = -0.3
			p.hip = -90.0 + 10.0 * k
		&"hitstun":
			p.lean = -0.35
			p.front_upper = 0.3
			p.front_lower = 0.9
			p.back_upper = -0.4
			p.back_lower = 0.4
			p.front_thigh = 0.35
			p.back_thigh = -0.1
		&"knockdown", &"ko":
			_lying(p)
		&"getup":
			_lying(p)
			p.rot = lerpf(-1.45, 0.0, clampf(progress, 0.0, 1.0))
		&"victory":
			p.front_upper = 2.9
			p.front_lower = 3.05
			p.back_upper = 0.4
			p.back_lower = 1.0
			p.lean = -0.08
	return p


func _crouch_legs(p: Pose) -> void:
	p.hip = -60.0
	p.lean = 0.25
	p.front_thigh = 1.2
	p.front_shin = -0.35
	p.back_thigh = 0.2
	p.back_shin = -1.2


func _block_arms(p: Pose) -> void:
	p.front_upper = 1.3
	p.front_lower = 3.0
	p.back_upper = 1.1
	p.back_lower = 2.9


func _lying(p: Pose) -> void:
	p.rot = -1.45
	p.lean = 0.0
	p.front_upper = 2.6
	p.front_lower = 2.9
	p.back_upper = 2.4
	p.back_lower = 2.8
	p.front_thigh = 0.15
	p.front_shin = 0.1
	p.back_thigh = -0.1
	p.back_shin = -0.05


# --- Drawing ---------------------------------------------------------------

func _dir(angle: float) -> Vector2:
	# Angles are measured from straight down; positive turns toward the front.
	return Vector2(sin(angle), cos(angle))


func _outline() -> Color:
	return outline_color.lerp(Color.WHITE, clampf(_flash, 0.0, 1.0))


func _draw() -> void:
	if data == null:
		return
	var p := _compute_pose()
	draw_set_transform(Vector2.ZERO, p.rot, Vector2.ONE)

	var up := Vector2(sin(p.lean), -cos(p.lean))
	var hip := Vector2(0.0, p.hip)
	var shoulder := hip + up * TORSO
	var head := hip + up * (TORSO + 21.0)
	var back_knee := hip + _dir(p.back_thigh) * THIGH
	var back_foot := back_knee + _dir(p.back_shin) * SHIN
	var front_knee := hip + _dir(p.front_thigh) * THIGH
	var front_foot := front_knee + _dir(p.front_shin) * SHIN
	var back_elbow := shoulder + _dir(p.back_upper) * UPPER_ARM
	var back_hand := back_elbow + _dir(p.back_lower) * FOREARM
	var front_elbow := shoulder + _dir(p.front_upper) * UPPER_ARM
	var front_hand := front_elbow + _dir(p.front_lower) * FOREARM
	var front_dir := (front_hand - front_elbow).normalized()
	var back_dir := (back_hand - back_elbow).normalized()

	var skin := data.skin_color
	var arm_color := skin if data.bare_arms else torso_color
	var shin_color := skin if data.bare_shins else leg_color
	var body_color := skin if data.bare_torso else torso_color

	if special_ready:
		var pulse := 0.5 + 0.5 * sin(_time * 8.0)
		draw_circle(hip + up * 30.0, 78.0 + pulse * 8.0, Color(data.accent_color, 0.12 + pulse * 0.1))
	if data.cape_color.a > 0.0:
		_draw_cape(shoulder, hip, up)

	# Back limbs are slightly darker so the pose reads clearly.
	_limb(shoulder, back_elbow, back_hand, ARM_W, arm_color.darkened(0.22), arm_color.darkened(0.22))
	draw_circle(back_hand, 6.5, skin.darkened(0.22))
	if data.weapon == &"dual_katana":
		_stick(back_hand + back_dir * 4.0, back_hand + back_dir * 56.0, 4.0, STEEL.darkened(0.15))
	_limb(hip, back_knee, back_foot, LEG_W, leg_color.darkened(0.22), shin_color.darkened(0.22))
	_foot(back_foot)

	_draw_torso(hip, shoulder, up, body_color)
	_limb(hip, front_knee, front_foot, LEG_W, leg_color, shin_color)
	_foot(front_foot)
	_draw_head(head)

	if data.weapon == &"spear":
		_draw_shield(back_hand)
	_limb(shoulder, front_elbow, front_hand, ARM_W, arm_color, arm_color)
	if data.weapon == &"fists":
		_draw_arm_band(shoulder, front_elbow)
	draw_circle(front_hand, 7.5, _outline())
	draw_circle(front_hand, 6.0, skin)
	_draw_weapon(front_hand, front_dir)
	_draw_attack_effects(shoulder, front_hand, front_dir, front_foot)


func _limb(a: Vector2, b: Vector2, c: Vector2, width: float, color_ab: Color, color_bc: Color) -> void:
	var o := _outline()
	var ow := width + OUTLINE_W
	draw_line(a, b, o, ow)
	draw_line(b, c, o, ow)
	draw_circle(a, ow * 0.5, o)
	draw_circle(b, ow * 0.5, o)
	draw_circle(c, ow * 0.5, o)
	draw_line(a, b, color_ab, width)
	draw_circle(a, width * 0.5, color_ab)
	draw_circle(b, width * 0.5, color_ab)
	draw_line(b, c, color_bc, width)
	draw_circle(c, width * 0.5, color_bc)


func _stick(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	draw_line(a, b, _outline(), width + 4.0)
	draw_line(a, b, color, width)


func _poly(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, _outline(), 2.0)


func _foot(foot: Vector2) -> void:
	draw_line(foot, foot + Vector2(13.0, 1.0), _outline(), 10.0)
	draw_line(foot, foot + Vector2(12.0, 1.0), Color(0.24, 0.17, 0.12), 6.0)


func _draw_torso(hip: Vector2, shoulder: Vector2, up: Vector2, color: Color) -> void:
	var o := _outline()
	draw_line(hip, shoulder, o, TORSO_W + OUTLINE_W)
	draw_circle(hip, (TORSO_W + OUTLINE_W) * 0.5 - 2.0, o)
	draw_circle(shoulder, (TORSO_W + OUTLINE_W) * 0.5, o)
	draw_line(hip, shoulder, color, TORSO_W)
	draw_circle(hip, TORSO_W * 0.5 - 2.0, color)
	draw_circle(shoulder, TORSO_W * 0.5, color)
	var across := Vector2(-up.y, up.x)
	var belt := hip + up * 8.0
	draw_line(belt - across * 15.0, belt + across * 15.0, leg_color.darkened(0.35), 6.0)
	if data.id == &"lapu_lapu":
		# Visayan tattoo lines (pintados)
		var tattoo := Color(0.18, 0.12, 0.1)
		for i in 3:
			var c := hip + up * (22.0 + i * 11.0)
			draw_line(c - across * 9.0, c + across * 9.0, tattoo, 2.0)
	elif data.id == &"leonidas":
		draw_line(shoulder - up * 6.0 - across * 12.0, shoulder - up * 6.0 + across * 12.0, BRONZE.darkened(0.3), 3.0)


func _draw_cape(shoulder: Vector2, hip: Vector2, up: Vector2) -> void:
	var sway := sin(_time * 4.0) * 4.0
	var points := PackedVector2Array([
		shoulder + Vector2(-6.0, 4.0),
		shoulder + Vector2(6.0, 2.0),
		hip + Vector2(-20.0 + sway, 20.0) - up * 4.0,
		hip + Vector2(-34.0 + sway, 10.0),
	])
	_poly(points, data.cape_color)


func _draw_head(head: Vector2) -> void:
	var o := _outline()
	draw_circle(head, HEAD_R + 2.5, o)
	draw_circle(head, HEAD_R, data.skin_color)
	var hair := data.hair_color
	var r := HEAD_R
	match data.headgear:
		&"spartan_helmet":
			draw_circle(head, r + 1.0, BRONZE)
			draw_circle(head + Vector2(7.0, 3.0), 7.5, data.skin_color)
			draw_arc(head + Vector2(-2.0, -6.0), r + 8.0, PI * 1.05, PI * 1.95, 16, o, 12.0)
			draw_arc(head + Vector2(-2.0, -6.0), r + 8.0, PI * 1.05, PI * 1.95, 16, Color(0.78, 0.1, 0.1), 9.0)
		&"laurel":
			draw_arc(head, r - 2.0, PI * 0.95, PI * 2.05, 16, hair, 7.0)
			for i in 7:
				var angle := PI + i * PI / 6.0
				draw_circle(head + Vector2(cos(angle), sin(angle)) * (r + 1.0), 3.4, Color(0.3, 0.6, 0.25))
		&"viking_helm":
			draw_line(head + Vector2(-r + 2.0, 0.0), head + Vector2(-r - 3.0, 18.0), hair, 7.0)
			_poly(PackedVector2Array([head + Vector2(-2.0, 5.0), head + Vector2(14.0, 3.0), head + Vector2(9.0, 23.0), head + Vector2(-1.0, 18.0)]), hair)
			draw_arc(head, r - 2.0, PI, TAU, 16, Color(0.5, 0.52, 0.56), 9.0)
			draw_line(head + Vector2(r - 4.0, -7.0), head + Vector2(r - 2.0, 5.0), Color(0.5, 0.52, 0.56), 4.0)
		&"topknot":
			draw_arc(head, r - 2.0, PI * 0.9, PI * 2.0, 16, hair, 7.0)
			draw_circle(head + Vector2(-3.0, -r - 4.0), 5.5, hair)
		&"putong":
			draw_arc(head, r - 2.0, PI * 0.95, PI * 2.05, 16, Color(0.75, 0.1, 0.1), 9.0)
			draw_line(head + Vector2(-r, -6.0), head + Vector2(-r - 12.0, 6.0), Color(0.75, 0.1, 0.1), 5.0)
		&"feather":
			draw_line(head + Vector2(-r + 3.0, -2.0), head + Vector2(-r + 1.0, 34.0), hair, 9.0)
			draw_arc(head, r - 2.0, PI * 0.9, PI * 1.95, 16, hair, 7.0)
			var base := head + Vector2(-r + 2.0, -r + 4.0)
			var tip := head + Vector2(-r - 10.0, -r - 22.0)
			draw_line(base, tip, Color(0.95, 0.95, 0.92), 5.0)
			draw_line(base.lerp(tip, 0.75), tip, Color(0.1, 0.1, 0.1), 5.0)
		&"winter_cap":
			draw_circle(head + Vector2(-2.0, -1.0), r + 3.0, Color(0.95, 0.96, 0.98))
			draw_circle(head + Vector2(5.0, 2.0), r * 0.62, data.skin_color)
		&"mongkhon":
			draw_arc(head, r - 2.0, PI * 0.95, PI * 2.0, 16, hair, 6.0)
			draw_arc(head + Vector2(0.0, -3.0), r - 1.0, PI * 0.9, PI * 2.1, 16, Color(0.95, 0.92, 0.85), 5.0)
			draw_line(head + Vector2(-r, -4.0), head + Vector2(-r - 14.0, -14.0), Color(0.8, 0.15, 0.15), 4.0)
		&"zeus":
			draw_circle(head + Vector2(-4.0, -2.0), r + 3.0, hair)
			draw_circle(head + Vector2(3.0, 0.0), r * 0.85, data.skin_color)
			_poly(PackedVector2Array([head + Vector2(-6.0, 3.0), head + Vector2(14.0, 1.0), head + Vector2(10.0, 27.0), head + Vector2(-2.0, 23.0)]), hair)
			draw_arc(head, r + 1.0, PI * 1.0, PI * 1.9, 16, data.accent_color, 4.0)
	draw_circle(head + Vector2(7.0, -2.0), 2.2, Color(0.05, 0.05, 0.05))


func _draw_shield(hand: Vector2) -> void:
	draw_circle(hand, 28.0, _outline())
	draw_circle(hand, 25.0, BRONZE)
	draw_circle(hand, 18.0, BRONZE.lightened(0.12))
	draw_line(hand + Vector2(-10.0, 12.0), hand + Vector2(0.0, -12.0), Color(0.55, 0.1, 0.08), 4.0)
	draw_line(hand + Vector2(0.0, -12.0), hand + Vector2(10.0, 12.0), Color(0.55, 0.1, 0.08), 4.0)


func _draw_arm_band(shoulder: Vector2, elbow: Vector2) -> void:
	# Muay Thai prajioud on the upper arm
	var mid := shoulder.lerp(elbow, 0.45)
	draw_circle(mid, 7.0, Color(0.8, 0.15, 0.15))


func _draw_weapon(hand: Vector2, d: Vector2) -> void:
	var n := Vector2(-d.y, d.x)
	match data.weapon:
		&"spear":
			_stick(hand - d * 40.0, hand + d * 92.0, 5.0, WOOD)
			var tip := hand + d * 92.0
			_poly(PackedVector2Array([tip + d * 20.0, tip + n * 6.0, tip - n * 6.0]), STEEL)
		&"gladius":
			_stick(hand + d * 4.0, hand + d * 50.0, 7.0, STEEL)
			_stick(hand - n * 8.0, hand + n * 8.0, 4.0, data.accent_color)
		&"axe":
			_stick(hand - d * 12.0, hand + d * 56.0, 5.0, WOOD)
			var end := hand + d * 52.0
			_poly(PackedVector2Array([end - d * 8.0, end + n * 18.0 - d * 14.0, end + n * 20.0 + d * 10.0, end + d * 6.0]), STEEL)
		&"dual_katana":
			_stick(hand + d * 4.0, hand + d * 88.0, 4.0, STEEL)
			_stick(hand - d * 6.0, hand + d * 6.0, 6.0, Color(0.15, 0.12, 0.2))
		&"kampilan":
			_stick(hand - d * 8.0, hand + d * 6.0, 6.0, WOOD)
			_poly(PackedVector2Array([hand + d * 6.0 + n * 3.0, hand + d * 80.0 + n * 7.0, hand + d * 86.0 + n * 2.0, hand + d * 80.0 - n * 3.0, hand + d * 6.0 - n * 3.0]), STEEL)
		&"war_club":
			_stick(hand - d * 8.0, hand + d * 44.0, 6.0, WOOD)
			var club_head := hand + d * 48.0
			draw_circle(club_head, 11.0, _outline())
			draw_circle(club_head, 8.5, Color(0.5, 0.5, 0.52))
		&"rifle":
			_stick(hand - d * 30.0, hand + d * 34.0, 9.0, WOOD)
			_stick(hand + d * 20.0, hand + d * 84.0, 4.0, Color(0.2, 0.2, 0.22))
		&"fists":
			draw_circle(hand, 8.5, _outline())
			draw_circle(hand, 7.0, Color(0.96, 0.94, 0.88))
		&"thunderbolt":
			_bolt(hand - d * 18.0, hand + d * 46.0, 3, data.accent_color, 5.0)


func _bolt(a: Vector2, b: Vector2, segments: int, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var span := b - a
	var n := Vector2(-span.y, span.x).normalized()
	var count := segments * 2
	for i in count + 1:
		var t := float(i) / float(count)
		var offset := 0.0
		if i != 0 and i != count:
			offset = 8.0 if i % 2 == 0 else -8.0
		points.append(a + span * t + n * offset)
	draw_polyline(points, Color(color, 0.45), width + 6.0)
	draw_polyline(points, color, width)
	draw_polyline(points, Color.WHITE, maxf(width - 3.0, 1.0))


func _draw_attack_effects(shoulder: Vector2, hand: Vector2, d: Vector2, foot: Vector2) -> void:
	if pose != &"punch" and pose != &"kick" and pose != &"special":
		return
	if progress < 0.35:
		# Wind-up flash at the striking hand or foot (GDD 5.4 and IX)
		var spot := foot if pose == &"kick" else hand
		var size := 8.0 + 6.0 * (progress / 0.35)
		draw_circle(spot, size + 3.0, Color(1.0, 1.0, 1.0, 0.35))
		draw_circle(spot, size * 0.6, Color(1.0, 1.0, 0.9, 0.9))
		return
	if pose != &"special" or progress >= 0.55:
		return
	var reach := data.reach_length() * 1.5 + data.special_reach_bonus
	match data.weapon:
		&"thunderbolt":
			_bolt(hand, hand + Vector2(reach, 6.0), 6, data.accent_color, 7.0)
		&"rifle":
			var muzzle := hand + d * 84.0
			draw_circle(muzzle, 14.0, Color(1.0, 0.85, 0.4, 0.9))
			draw_line(muzzle, muzzle + Vector2(reach, 0.0), Color(1.0, 0.95, 0.7, 0.85), 3.0)
		_:
			draw_arc(shoulder, 70.0, -1.2, 1.2, 20, Color(data.accent_color, 0.85), 7.0)
			draw_arc(shoulder, 82.0, -0.9, 0.9, 16, Color(1.0, 1.0, 1.0, 0.6), 3.0)
