class_name CutinFxLayer
extends Control
## Live 60 FPS AAA anime fighting-game VFX renderer for Single Ultimate Cut-Ins
## and Simultaneous Dual "ULTIMATE CLASH!" cinema overlays.
## Purely visual (reacts only to HUD trigger calls; never mutates simulation).

var active := false
var dual_mode := false
var single_slot := 0
var color_left := Color(0.35, 0.75, 1.0)
var color_right := Color(1.0, 0.55, 0.2)
var _time := 0.0
var _bolt_seed := 1
var _sparks: Array[Dictionary] = []
var _streaks: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_init_particles()


func _init_particles() -> void:
	_streaks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in 30:
		_streaks.append({
			"y": rng.randf_range(182.0, 508.0),
			"phase": rng.randf_range(0.0, 1.0),
			"speed": rng.randf_range(2.2, 4.6),
			"len": rng.randf_range(120.0, 320.0),
			"thick": rng.randf_range(2.0, 6.5),
			"alpha": rng.randf_range(0.28, 0.72),
			"hot": i % 4 == 0,
		})
	_sparks.clear()
	for i in 28:
		var ang := rng.randf_range(0.0, TAU)
		_sparks.append({
			"angle": ang,
			"speed": rng.randf_range(280.0, 740.0),
			"phase": rng.randf_range(0.0, 1.0),
			"len": rng.randf_range(22.0, 68.0),
			"thick": rng.randf_range(2.0, 4.5),
			"left": cos(ang) < 0.0,
		})


func start_single(slot: int, accent: Color) -> void:
	active = true
	dual_mode = false
	single_slot = slot
	if slot == 0:
		color_left = accent
	else:
		color_right = accent
	_time = 0.0
	visible = true
	queue_redraw()


func start_dual(c_left: Color, c_right: Color) -> void:
	active = true
	dual_mode = true
	color_left = c_left
	color_right = c_right
	_time = 0.0
	visible = true
	queue_redraw()


func stop_fx() -> void:
	active = false
	visible = false


func _process(delta: float) -> void:
	if not active:
		return
	_time += delta
	_bolt_seed = int(_time * 28.0) + 1
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	if dual_mode:
		_draw_dual_clash()
	else:
		_draw_single_cutin()


func _draw_single_cutin() -> void:
	var is_left := (single_slot == 0)
	var col := color_left if is_left else color_right
	var flare_pos := Vector2(310.0, 345.0) if is_left else Vector2(970.0, 345.0)

	# Smooth multi-layered radial energy halo behind the champion bust
	for k in range(6, 0, -1):
		var r := 65.0 + float(k) * 52.0 + sin(_time * 14.0) * 10.0
		var a := 0.055 * float(7 - k) / 6.0
		draw_circle(flare_pos, r, Color(col.r, col.g, col.b, a))
	draw_circle(flare_pos, 95.0, Color(1.0, 0.98, 0.92, 0.14))

	# High-velocity anime speed lines streaking across the cinema ribbon
	var x_min := 0.0 if is_left else 430.0
	var x_max := 850.0 if is_left else 1280.0
	var span := x_max - x_min
	var dir := 1.0 if is_left else -1.0
	for s in _streaks:
		var prog := fposmod(float(s["phase"]) + _time * float(s["speed"]), 1.0)
		var x0 := x_min + prog * span if is_left else x_max - prog * span
		var x1 := clampf(x0 + dir * float(s["len"]), x_min, x_max)
		var y := float(s["y"])
		var c: Color = Color(1.0, 0.98, 0.92, float(s["alpha"]) * 0.85) if bool(s["hot"]) else Color(col.r, col.g, col.b, float(s["alpha"]))
		draw_line(Vector2(x0, y), Vector2(x1, y), c, float(s["thick"]), true)

	# Luminous rail bloom along top and bottom borders
	var edge_top_x := 880.0 if is_left else 480.0
	var edge_bot_x := 780.0 if is_left else 380.0
	var edge_start := 0.0 if is_left else 1280.0
	draw_line(Vector2(edge_start, 173.0), Vector2(edge_top_x, 173.0), Color(col.r, col.g, col.b, 0.72), 10.0, true)
	draw_line(Vector2(edge_start, 173.0), Vector2(edge_top_x, 173.0), Color(1.0, 0.98, 0.92, 0.88), 3.0, true)
	draw_line(Vector2(edge_start, 517.0), Vector2(edge_bot_x, 517.0), Color(col.r, col.g, col.b, 0.72), 10.0, true)
	draw_line(Vector2(edge_start, 517.0), Vector2(edge_bot_x, 517.0), Color(1.0, 0.98, 0.92, 0.88), 3.0, true)
	# Glowing diagonal slash tip
	draw_line(Vector2(edge_top_x, 168.0), Vector2(edge_bot_x, 522.0), Color(col.r, col.g, col.b, 0.85), 14.0, true)
	draw_line(Vector2(edge_top_x, 168.0), Vector2(edge_bot_x, 522.0), Color(1.0, 0.99, 0.92, 0.95), 4.0, true)


func _draw_dual_clash() -> void:
	var nexus := Vector2(640.0, 345.0)
	var seam_top := Vector2(678.0, 152.0)
	var seam_bot := Vector2(602.0, 538.0)

	# Dual opposing elemental energy halos behind P1 & P2 busts
	for k in range(5, 0, -1):
		var r := 70.0 + float(k) * 48.0 + sin(_time * 16.0) * 12.0
		var a := 0.06 * float(6 - k) / 5.0
		draw_circle(Vector2(290.0, 345.0), r, Color(color_left.r, color_left.g, color_left.b, a))
		draw_circle(Vector2(990.0, 345.0), r, Color(color_right.r, color_right.g, color_right.b, a))

	# Opposing high-speed anime speed lines slamming into the center diagonal seam
	for i in _streaks.size():
		var s := _streaks[i]
		var y := float(s["y"])
		var seam_x := lerpf(seam_top.x, seam_bot.x, clampf((y - seam_top.y) / (seam_bot.y - seam_top.y), 0.0, 1.0))
		var prog := fposmod(float(s["phase"]) + _time * float(s["speed"]) * 1.25, 1.0)
		var seg_len := float(s["len"]) * 0.72
		if i % 2 == 0:
			var x0 := prog * seam_x
			var x1 := minf(x0 + seg_len, seam_x - 6.0)
			var c := Color(1.0, 0.98, 0.92, 0.65) if bool(s["hot"]) else Color(color_left.r, color_left.g, color_left.b, float(s["alpha"]))
			draw_line(Vector2(x0, y), Vector2(x1, y), c, float(s["thick"]), true)
		else:
			var x0 := 1280.0 - prog * (1280.0 - seam_x)
			var x1 := maxf(x0 - seg_len, seam_x + 6.0)
			var c := Color(1.0, 0.98, 0.92, 0.65) if bool(s["hot"]) else Color(color_right.r, color_right.g, color_right.b, float(s["alpha"]))
			draw_line(Vector2(x0, y), Vector2(x1, y), c, float(s["thick"]), true)

	# Glowing top & bottom dual rails
	draw_line(Vector2(0, 172), Vector2(seam_top.x, 172), Color(color_left.r, color_left.g, color_left.b, 0.85), 9.0, true)
	draw_line(Vector2(seam_top.x, 172), Vector2(1280, 172), Color(color_right.r, color_right.g, color_right.b, 0.85), 9.0, true)
	draw_line(Vector2(0, 518), Vector2(seam_bot.x, 518), Color(color_left.r, color_left.g, color_left.b, 0.85), 9.0, true)
	draw_line(Vector2(seam_bot.x, 518), Vector2(1280, 518), Color(color_right.r, color_right.g, color_right.b, 0.85), 9.0, true)

	# Pulsing concentric Clash shockwave rings at the collision nexus!
	for r_idx in 3:
		var rp := fposmod(_time * 2.4 + float(r_idx) * 0.33, 1.0)
		var rad := 36.0 + rp * 250.0
		var ra := (1.0 - rp) * 0.72
		var rc := color_left.lerp(color_right, float(r_idx) * 0.5)
		draw_arc(nexus, rad, 0.0, TAU, 48, Color(rc.r, rc.g, rc.b, ra * 0.75), 11.0 * (1.0 - rp) + 2.0, true)
		draw_arc(nexus, rad, 0.0, TAU, 48, Color(1.0, 0.98, 0.82, ra), 3.0, true)

	# Radiant center Clash starburst glow + halo behind "ULTIMATE CLASH!" banner
	for k in range(5, 0, -1):
		var gr := 26.0 + float(k) * 28.0 + sin(_time * 24.0) * 8.0
		draw_circle(nexus, gr, Color(1.0, 0.90, 0.38, 0.14 * float(6 - k) / 5.0))
	draw_circle(nexus, 40.0, Color(1.0, 1.0, 0.95, 0.72))
	# Horizontal flare behind the top "ULTIMATE CLASH!" title
	draw_line(Vector2(300, 130), Vector2(980, 130), Color(1.0, 0.84, 0.25, 0.36), 28.0, true)
	draw_line(Vector2(380, 130), Vector2(900, 130), Color(1.0, 0.98, 0.86, 0.52), 8.0, true)

	# Live crackling jagged multi-branch lightning fissure ripping down the diagonal center seam!
	var rng := RandomNumberGenerator.new()
	rng.seed = _bolt_seed * 7919 + 13
	_draw_jagged_fissure(seam_top, seam_bot, rng, 18.0, Color(1.0, 0.85, 0.25, 0.55), 18.0)
	_draw_jagged_fissure(seam_top, seam_bot, rng, 14.0, Color(1.0, 0.96, 0.72, 0.90), 8.0)
	_draw_jagged_fissure(seam_top, seam_bot, rng, 9.0, Color(1.0, 1.0, 1.0, 1.0), 3.5)

	# Crackling secondary lightning branches shooting left & right from the seam!
	for b in 6:
		var t := rng.randf_range(0.15, 0.85)
		var origin := seam_top.lerp(seam_bot, t)
		var side := -1.0 if (b % 2 == 0) else 1.0
		var tip := origin + Vector2(side * rng.randf_range(85.0, 195.0), rng.randf_range(-75.0, 75.0))
		var bc := color_left if side < 0.0 else color_right
		_draw_jagged_fissure(origin, tip, rng, 16.0, Color(bc.r, bc.g, bc.b, 0.75), 6.0)
		_draw_jagged_fissure(origin, tip, rng, 12.0, Color(1.0, 0.99, 0.92, 0.92), 2.2)

	# Flying Clash spark streaks blasting outward from the nexus!
	for sp in _sparks:
		var prog := fposmod(float(sp["phase"]) + _time * 2.6, 1.0)
		var ang := float(sp["angle"])
		var dir_v := Vector2(cos(ang), sin(ang))
		var d0 := 24.0 + prog * float(sp["speed"]) * 0.55
		var d1 := d0 + float(sp["len"]) * (1.0 - prog * 0.4)
		var sc := color_left if bool(sp["left"]) else color_right
		var sa := (1.0 - prog) * 0.95
		draw_line(nexus + dir_v * d0, nexus + dir_v * d1, Color(sc.r, sc.g, sc.b, sa), float(sp["thick"]) * 1.6, true)
		draw_line(nexus + dir_v * d0, nexus + dir_v * d1, Color(1.0, 0.98, 0.90, sa), float(sp["thick"]) * 0.6, true)


func _draw_jagged_fissure(from_pt: Vector2, to_pt: Vector2, rng: RandomNumberGenerator, jitter: float, col: Color, width: float) -> void:
	var segs := 10
	var perp := (to_pt - from_pt).orthogonal().normalized()
	var prev := from_pt
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var pt := from_pt.lerp(to_pt, t)
		if i < segs:
			pt += perp * rng.randf_range(-jitter, jitter)
		draw_line(prev, pt, col, width, true)
		prev = pt
