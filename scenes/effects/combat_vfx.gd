class_name CombatVfx
extends Node2D
## High-impact Anime-Fighter Combat VFX Engine (Street Fighter / Guilty Gear / Tekken feel).
## Multi-layered luminous additive bloom, tapered crescent weapon slashes, glowing
## molten ground fissures, plasma lightning bolts, supersonic Mach-cone sniper beams,
## and dramatic Super-Art flashes. Purely visual (Section 13.3).

enum Kind {
	SLASH_ARC,
	SHOCKWAVE_RING,
	GROUND_SHATTER,
	DUST_PUFF,
	LIGHTNING_ARC,
	SNIPER_BEAM,
	SNIPER_RETICLE,
	RADIAL_BURST,
	SUPER_BACKDROP,
	SPEAR_THRUST,
	ENERGY_PILLAR,
}

var kind: Kind = Kind.SHOCKWAVE_RING
var color: Color = Color(1.0, 0.85, 0.3)
var duration := 0.28
var _life := 0.0
var _radius := 90.0
var _thickness := 12.0
var _angle_a := -1.1
var _angle_b := 1.1
var _tilt_y := 1.0
var _facing := 1
var _p_from := Vector2.ZERO
var _p_to := Vector2.ZERO
var _particles: Array[Dictionary] = []
var _bolts: Array[PackedVector2Array] = []
var _cracks: Array[PackedVector2Array] = []
var _rng := RandomNumberGenerator.new()


static func _make(parent: Node, pos: Vector2, k: Kind, col: Color, dur: float, z: int, additive: bool = true) -> CombatVfx:
	var fx := CombatVfx.new()
	fx.kind = k
	fx.color = col
	fx.duration = dur
	fx.global_position = pos
	fx.z_index = z
	fx._rng.seed = int(absf(pos.x * 31.0 + pos.y * 17.0)) + int(k) * 997 + parent.get_child_count() * 131
	if additive:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		fx.material = mat
	parent.add_child(fx)
	return fx


static func spawn_slash_arc(
	parent: Node,
	pos: Vector2,
	facing: int,
	col: Color,
	radius: float = 86.0,
	angle_start: float = -1.25,
	angle_end: float = 1.05,
	thickness: float = 16.0,
	dur: float = 0.22
) -> CombatVfx:
	var fx := _make(parent, pos, Kind.SLASH_ARC, col, dur, 6, true)
	fx._facing = facing
	fx._radius = radius
	fx._angle_a = angle_start
	fx._angle_b = angle_end
	fx._thickness = thickness
	for i in 10:
		var t := float(i) / 9.0
		var ang := lerpf(angle_start, angle_end, t)
		var dir := Vector2(cos(ang) * float(facing), sin(ang))
		fx._particles.append({
			"pos": dir * (radius * fx._rng.randf_range(0.84, 1.08)),
			"vel": dir * fx._rng.randf_range(120.0, 290.0),
			"len": fx._rng.randf_range(10.0, 26.0),
			"size": fx._rng.randf_range(2.5, 5.0),
		})
	return fx


static func spawn_spear_thrust(
	parent: Node,
	pos: Vector2,
	facing: int,
	col: Color,
	length: float = 175.0,
	dur: float = 0.26
) -> CombatVfx:
	var fx := _make(parent, pos, Kind.SPEAR_THRUST, col, dur, 6, true)
	fx._facing = facing
	fx._radius = length
	for i in 14:
		fx._particles.append({
			"pos": Vector2(float(facing) * fx._rng.randf_range(14.0, length * 0.9), fx._rng.randf_range(-28.0, 28.0)),
			"vel": Vector2(float(facing) * fx._rng.randf_range(220.0, 480.0), fx._rng.randf_range(-65.0, 65.0)),
			"len": fx._rng.randf_range(14.0, 32.0),
			"size": fx._rng.randf_range(2.5, 5.0),
		})
	return fx


static func spawn_energy_pillar(
	parent: Node,
	pos: Vector2,
	col: Color,
	width: float = 110.0,
	dur: float = 0.38
) -> CombatVfx:
	var fx := _make(parent, pos, Kind.ENERGY_PILLAR, col, dur, 7, true)
	fx._radius = width
	for i in 14:
		fx._particles.append({
			"x": fx._rng.randf_range(-width * 0.6, width * 0.6),
			"y": fx._rng.randf_range(-40.0, 0.0),
			"vy": -fx._rng.randf_range(420.0, 880.0),
			"len": fx._rng.randf_range(24.0, 64.0),
			"w": fx._rng.randf_range(2.5, 5.5),
		})
	return fx


static func spawn_shockwave_ring(
	parent: Node,
	pos: Vector2,
	col: Color,
	max_radius: float = 140.0,
	dur: float = 0.30,
	tilt_y: float = 1.0,
	thickness: float = 10.0
) -> CombatVfx:
	var fx := _make(parent, pos, Kind.SHOCKWAVE_RING, col, dur, 6, true)
	fx._radius = max_radius
	fx._tilt_y = tilt_y
	fx._thickness = thickness
	return fx


static func spawn_ground_shatter(
	parent: Node,
	pos: Vector2,
	col: Color = Color(1.0, 0.85, 0.42),
	scale_mult: float = 1.0,
	dur: float = 0.58
) -> CombatVfx:
	var fx := _make(parent, pos, Kind.GROUND_SHATTER, col, dur, 4, false)
	fx._radius = 130.0 * scale_mult
	for c in 8:
		var ang := lerpf(-PI * 0.94, -PI * 0.06, float(c) / 7.0) + fx._rng.randf_range(-0.07, 0.07)
		var pts := PackedVector2Array([Vector2.ZERO])
		var cur := Vector2.ZERO
		for seg in 5:
			var step_len := fx._rng.randf_range(18.0, 34.0) * scale_mult
			cur += Vector2(cos(ang) * step_len, sin(ang) * step_len * 0.24)
			cur.y += fx._rng.randf_range(-3.0, 4.0)
			pts.append(cur)
		fx._cracks.append(pts)
	for i in 16:
		var vx := fx._rng.randf_range(-310.0, 310.0) * scale_mult
		var vy := fx._rng.randf_range(-460.0, -150.0) * scale_mult
		fx._particles.append({
			"pos": Vector2(fx._rng.randf_range(-30.0, 30.0) * scale_mult, -4.0),
			"vel": Vector2(vx, vy),
			"size": fx._rng.randf_range(4.0, 10.0) * scale_mult,
		})
	return fx


static func spawn_dust_puff(
	parent: Node,
	pos: Vector2,
	dir: int = 0,
	count: int = 8,
	col: Color = Color(0.90, 0.86, 0.78, 0.82),
	dur: float = 0.34
) -> CombatVfx:
	var fx := _make(parent, pos, Kind.DUST_PUFF, col, dur, 3, false)
	for i in count:
		var vx: float
		if dir == 0:
			vx = fx._rng.randf_range(-175.0, 175.0)
		else:
			vx = -float(dir) * fx._rng.randf_range(75.0, 240.0) + fx._rng.randf_range(-40.0, 40.0)
		var vy := fx._rng.randf_range(-110.0, -20.0)
		fx._particles.append({
			"pos": Vector2(fx._rng.randf_range(-16.0, 16.0), -fx._rng.randf_range(2.0, 10.0)),
			"vel": Vector2(vx, vy),
			"size": fx._rng.randf_range(10.0, 20.0),
		})
	return fx


static func spawn_lightning_arc(
	parent: Node,
	p_from: Vector2,
	p_to: Vector2,
	col: Color = Color(1.0, 0.94, 0.36),
	dur: float = 0.26,
	thickness: float = 7.0,
	branches: int = 3
) -> CombatVfx:
	var fx := _make(parent, Vector2.ZERO, Kind.LIGHTNING_ARC, col, dur, 7, true)
	fx._p_from = p_from
	fx._p_to = p_to
	fx._thickness = thickness
	fx._bolts.append(fx._build_jagged_bolt(p_from, p_to, 10, 28.0))
	for b in branches:
		var mid := p_from.lerp(p_to, fx._rng.randf_range(0.22, 0.78))
		var offset := Vector2(fx._rng.randf_range(-85.0, 85.0), fx._rng.randf_range(-55.0, 80.0))
		fx._bolts.append(fx._build_jagged_bolt(mid, mid + offset, 5, 16.0))
	return fx


static func spawn_sniper_beam(
	parent: Node,
	p_from: Vector2,
	p_to: Vector2,
	col: Color = Color(0.74, 0.95, 1.0),
	dur: float = 0.48,
	thickness: float = 22.0
) -> CombatVfx:
	var fx := _make(parent, Vector2.ZERO, Kind.SNIPER_BEAM, col, dur, 7, true)
	fx._p_from = p_from
	fx._p_to = p_to
	fx._thickness = thickness
	for i in 6:
		var t := 0.10 + float(i) * 0.16
		fx._particles.append({
			"pos": p_from.lerp(p_to, t),
			"size": 28.0 + float(i) * 9.0,
			"delay": float(i) * 0.022,
		})
	return fx


static func spawn_sniper_reticle(
	parent: Node,
	target_pos: Vector2,
	col: Color = Color(1.0, 0.24, 0.22),
	dur: float = 0.70
) -> CombatVfx:
	var fx := _make(parent, target_pos, Kind.SNIPER_RETICLE, col, dur, 8, true)
	fx._radius = 78.0
	return fx


static func spawn_radial_burst(
	parent: Node,
	pos: Vector2,
	col: Color,
	count: int = 18,
	speed: float = 460.0,
	dur: float = 0.34
) -> CombatVfx:
	var fx := _make(parent, pos, Kind.RADIAL_BURST, col, dur, 7, true)
	for i in count:
		var ang := (float(i) / float(maxi(1, count))) * TAU + fx._rng.randf_range(-0.18, 0.18)
		var spd := speed * fx._rng.randf_range(0.45, 1.25)
		fx._particles.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"len": fx._rng.randf_range(16.0, 42.0),
			"size": fx._rng.randf_range(2.5, 5.5),
		})
	return fx


static func spawn_super_backdrop(
	parent: Node,
	center_pos: Vector2,
	col: Color,
	dur: float = 1.25
) -> CombatVfx:
	# Dramatic Tekken/SF Super-Art stage dim + luminous speed streaks & energy core flash!
	var fx := _make(parent, center_pos, Kind.SUPER_BACKDROP, col, dur, -1, false)
	fx._radius = 360.0
	for i in 22:
		fx._particles.append({
			"y": fx._rng.randf_range(-440.0, 260.0),
			"x": fx._rng.randf_range(-1100.0, 1100.0),
			"w": fx._rng.randf_range(180.0, 520.0),
			"h": fx._rng.randf_range(2.5, 7.0),
			"spd": fx._rng.randf_range(1400.0, 2600.0) * (1.0 if i % 2 == 0 else -1.0),
		})
	return fx


func _build_jagged_bolt(a: Vector2, b: Vector2, segs: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	var delta := b - a
	var perp := Vector2(-delta.y, delta.x).normalized()
	for i in range(1, segs):
		var t := float(i) / float(segs)
		var base := a.lerp(b, t)
		var off := perp * _rng.randf_range(-jitter, jitter)
		pts.append(base + off)
	pts.append(b)
	return pts


func _process(delta: float) -> void:
	_life += delta
	if _life >= duration:
		queue_free()
		return
	match kind:
		Kind.SLASH_ARC, Kind.RADIAL_BURST, Kind.SPEAR_THRUST:
			for p in _particles:
				p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
				p["vel"] = (p["vel"] as Vector2) * 0.90
		Kind.ENERGY_PILLAR:
			for p in _particles:
				p["y"] = float(p["y"]) + float(p["vy"]) * delta
		Kind.GROUND_SHATTER:
			for p in _particles:
				var v: Vector2 = p["vel"]
				v.y += 1500.0 * delta
				p["vel"] = v
				var np: Vector2 = (p["pos"] as Vector2) + v * delta
				if np.y > 0.0:
					np.y = 0.0
					v.y *= -0.24
					v.x *= 0.6
					p["vel"] = v
				p["pos"] = np
		Kind.DUST_PUFF:
			for p in _particles:
				p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
				p["vel"] = (p["vel"] as Vector2) * 0.87
		Kind.SUPER_BACKDROP:
			for p in _particles:
				var nx: float = float(p["x"]) + float(p["spd"]) * delta
				if nx > 1200.0:
					nx = -1200.0
				elif nx < -1200.0:
					nx = 1200.0
				p["x"] = nx
	queue_redraw()


func _draw() -> void:
	var t := clampf(_life / maxf(duration, 0.001), 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - t, 3.0)
	var alpha := clampf(1.0 - pow(t, 1.65), 0.0, 1.0)

	match kind:
		Kind.SLASH_ARC:
			# Tapered luminous anime sword-crescent (thick in middle, razor sharp tips!)
			var r := _radius * (0.86 + 0.24 * ease_out)
			var segs := 20
			var outer_pts := PackedVector2Array()
			var inner_pts := PackedVector2Array()
			var core_outer := PackedVector2Array()
			var core_inner := PackedVector2Array()
			var w_max := _thickness * (1.2 - 0.8 * t)
			for i in range(segs + 1):
				var f := float(i) / float(segs)
				var taper := pow(sin(f * PI), 0.8)
				var ang := lerpf(_angle_a, _angle_b, f)
				var n := Vector2(cos(ang) * float(_facing), sin(ang))
				outer_pts.append(n * (r + w_max * taper))
				inner_pts.append(n * (r - w_max * 0.85 * taper))
				core_outer.append(n * (r + w_max * 0.42 * taper))
				core_inner.append(n * (r - w_max * 0.35 * taper))
			inner_pts.reverse()
			core_inner.reverse()
			outer_pts.append_array(inner_pts)
			core_outer.append_array(core_inner)
			draw_colored_polygon(outer_pts, Color(color.r, color.g, color.b, alpha * 0.72))
			draw_colored_polygon(core_outer, Color(1.0, 0.99, 0.94, alpha * 0.96))
			for p in _particles:
				var pos: Vector2 = p["pos"]
				var v: Vector2 = p["vel"]
				var tail := pos - v.normalized() * float(p["len"]) * (1.0 - t * 0.65)
				draw_line(tail, pos, Color(color.r, color.g, color.b, alpha * 0.85), float(p["size"]))
				draw_line(tail.lerp(pos, 0.5), pos, Color(1.0, 1.0, 0.95, alpha), float(p["size"]) * 0.5)

		Kind.SPEAR_THRUST:
			# Blazing multi-layer spear shock-cone (Leonidas Phalanx Charge!)
			var len_now := _radius * (0.45 + 0.75 * ease_out)
			var dir := float(_facing)
			var spread := 46.0 * (1.0 - t * 0.55)
			var outer_cone := PackedVector2Array([
				Vector2(dir * len_now, 0.0),
				Vector2(0.0, -spread),
				Vector2(dir * len_now * 0.28, 0.0),
				Vector2(0.0, spread),
			])
			var core_cone := PackedVector2Array([
				Vector2(dir * len_now * 0.96, 0.0),
				Vector2(dir * len_now * 0.14, -spread * 0.48),
				Vector2(dir * len_now * 0.38, 0.0),
				Vector2(dir * len_now * 0.14, spread * 0.48),
			])
			draw_colored_polygon(outer_cone, Color(color.r, color.g, color.b, alpha * 0.75))
			draw_colored_polygon(core_cone, Color(1.0, 0.98, 0.88, alpha * 0.95))
			# Twin shock rings ripping along the spear shaft
			for r_idx in 2:
				var rx := dir * len_now * (0.35 + float(r_idx) * 0.35)
				var rr := (32.0 + float(r_idx) * 14.0) * (0.7 + 0.55 * ease_out)
				draw_set_transform(Vector2(rx, 0.0), 0.0, Vector2(0.32, 1.0))
				draw_arc(Vector2.ZERO, rr, 0.0, TAU, 24, Color(color.r, color.g, color.b, alpha * 0.85), 5.0)
				draw_arc(Vector2.ZERO, rr * 0.88, 0.0, TAU, 20, Color(1.0, 1.0, 0.9, alpha), 2.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for p in _particles:
				var pos: Vector2 = p["pos"]
				var v: Vector2 = p["vel"]
				var tail := pos - v.normalized() * float(p["len"]) * (1.0 - t * 0.5)
				draw_line(tail, pos, Color(1.0, 0.92, 0.55, alpha * 0.9), float(p["size"]))

		Kind.ENERGY_PILLAR:
			# Blazing vertical sky-to-earth / eruption energy column (Zeus, Leonidas, Ragnar finishers!)
			var w := _radius * (1.15 - 0.85 * t)
			draw_rect(Rect2(-w * 0.85, -640.0, w * 1.7, 640.0), Color(color.r, color.g, color.b, alpha * 0.35))
			draw_rect(Rect2(-w * 0.48, -640.0, w * 0.96, 640.0), Color(color.r, color.g, color.b, alpha * 0.72))
			draw_rect(Rect2(-w * 0.22, -640.0, w * 0.44, 640.0), Color(1.0, 0.99, 0.92, alpha * 0.95))
			for p in _particles:
				var px: float = float(p["x"])
				var py: float = float(p["y"])
				var pl: float = float(p["len"])
				draw_line(Vector2(px, py), Vector2(px, py + pl), Color(1.0, 0.96, 0.8, alpha * 0.9), float(p["w"]))

		Kind.SHOCKWAVE_RING:
			var r := lerpf(_radius * 0.16, _radius, ease_out)
			var thick := maxf(1.5, _thickness * (1.0 - t * 0.78))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, _tilt_y))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(color.r, color.g, color.b, alpha * 0.48), thick * 2.2)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(color.r, color.g, color.b, alpha * 0.92), thick)
			draw_arc(Vector2.ZERO, r * 0.96, 0.0, TAU, 36, Color(1.0, 1.0, 0.95, alpha), thick * 0.42)
			draw_arc(Vector2.ZERO, r * 0.62, 0.0, TAU, 28, Color(color.r, color.g, color.b, alpha * 0.35), thick * 0.45)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		Kind.GROUND_SHATTER:
			var crack_a := clampf(1.35 - t * 1.35, 0.0, 1.0)
			for pts in _cracks:
				draw_polyline(pts, Color(0.05, 0.03, 0.02, crack_a * 0.95), 6.0)
				draw_polyline(pts, Color(color.r, color.g, color.b, crack_a * 0.82), 2.5)
			if t < 0.38:
				var ft := 1.0 - t / 0.38
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.25))
				draw_circle(Vector2.ZERO, _radius * 0.65 * (1.0 - ft * 0.45), Color(color.r, color.g, color.b, ft * 0.50))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for p in _particles:
				var sz := float(p["size"]) * clampf(1.1 - t * 0.75, 0.25, 1.0)
				var pos: Vector2 = p["pos"]
				draw_rect(Rect2(pos - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), Color(0.24, 0.20, 0.16, crack_a))
				draw_rect(Rect2(pos - Vector2(sz * 0.5, sz * 0.5), Vector2(sz * 0.55, sz * 0.55)), Color(color.r, color.g, color.b, crack_a * 0.75))

		Kind.DUST_PUFF:
			for p in _particles:
				var sz := float(p["size"]) * (0.65 + 0.90 * ease_out)
				var pos: Vector2 = p["pos"]
				draw_circle(pos, sz * 0.52, Color(color.r * 0.65, color.g * 0.60, color.b * 0.55, color.a * alpha * 0.55))
				draw_circle(pos + Vector2(-sz * 0.12, -sz * 0.14), sz * 0.36, Color(1.0, 0.98, 0.94, color.a * alpha * 0.52))

		Kind.LIGHTNING_ARC:
			var flicker := 1.0 if int(_life * 60.0) % 2 == 0 else 0.75
			var a := alpha * flicker
			for i in _bolts.size():
				var pts := _bolts[i]
				var w := _thickness if i == 0 else (_thickness * 0.52)
				draw_polyline(pts, Color(color.r, color.g, color.b, a * 0.45), w * 3.4)
				draw_polyline(pts, Color(color.r, color.g, color.b, a * 0.92), w * 1.45)
				draw_polyline(pts, Color(1.0, 1.0, 0.96, a), maxf(1.8, w * 0.55))

		Kind.SNIPER_BEAM:
			var w := _thickness * (1.0 - t * 0.72)
			draw_line(_p_from, _p_to, Color(color.r, color.g, color.b, alpha * 0.42), w * 3.0)
			draw_line(_p_from, _p_to, Color(color.r, color.g, color.b, alpha * 0.92), w * 1.2)
			draw_line(_p_from, _p_to, Color(1.0, 1.0, 1.0, alpha), maxf(2.5, w * 0.44))
			var dir := (_p_to - _p_from).normalized()
			var ang := dir.angle()
			for p in _particles:
				var pt := clampf((_life - float(p["delay"])) / maxf(duration - float(p["delay"]), 0.01), 0.0, 1.0)
				if pt <= 0.0:
					continue
				var r := float(p["size"]) * (0.4 + 1.55 * pt)
				var ra := (1.0 - pt) * 0.92
				draw_set_transform(p["pos"] as Vector2, ang, Vector2(0.30, 1.0))
				draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(color.r, color.g, color.b, ra * 0.85), 5.0)
				draw_arc(Vector2.ZERO, r * 0.88, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, ra), 2.5)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		Kind.SNIPER_RETICLE:
			# Simo Deadeye lock-on reticle snapping tight around the target!
			var r := lerpf(_radius * 1.6, _radius * 0.48, ease_out)
			var spin := _life * 3.2
			var col := Color(color.r, color.g, color.b, alpha * 0.95)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 3.5)
			draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 24, Color(1.0, 0.92, 0.92, alpha * 0.85), 2.0)
			for i in 4:
				var a := spin + float(i) * PI * 0.5
				var d := Vector2(cos(a), sin(a))
				draw_line(d * (r * 0.35), d * (r * 1.25), col, 3.0)
			draw_circle(Vector2.ZERO, 4.5, Color(1.0, 0.95, 0.95, alpha))

		Kind.RADIAL_BURST:
			for p in _particles:
				var pos: Vector2 = p["pos"]
				var v: Vector2 = p["vel"]
				var tail := pos - v.normalized() * float(p["len"]) * (1.0 - t * 0.6)
				var sz := float(p["size"]) * (1.0 - t * 0.6)
				draw_line(tail, pos, Color(color.r, color.g, color.b, alpha * 0.85), sz * 1.7)
				draw_line(tail.lerp(pos, 0.45), pos, Color(1.0, 1.0, 0.96, alpha), maxf(1.2, sz * 0.75))

		Kind.SUPER_BACKDROP:
			var env := clampf(minf(t * 7.5, (1.0 - t) * 3.8), 0.0, 1.0)
			draw_rect(Rect2(-2400.0, -1200.0, 4800.0, 2400.0), Color(0.02, 0.02, 0.06, env * 0.62))
			for p in _particles:
				draw_rect(Rect2(float(p["x"]), float(p["y"]), float(p["w"]), float(p["h"])), Color(color.r, color.g, color.b, env * 0.22))
			# Blinding initial Super-Art ignition flash at caster
			if t < 0.28:
				var ft := 1.0 - t / 0.28
				draw_circle(Vector2.ZERO, _radius * 0.72 * (0.4 + 0.8 * (1.0 - ft)), Color(color.r, color.g, color.b, ft * 0.35))
				draw_circle(Vector2.ZERO, _radius * 0.30 * ft, Color(1.0, 0.98, 0.92, ft * 0.55))
