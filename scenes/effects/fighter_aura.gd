class_name FighterAura
extends Node2D
## Dynamic multi-layered fighter power aura (Tekken 8 Rage / DBFZ / SF6 style).
## Wraps around the fighter with ground energy rings, rising tapered flame wisps,
## and orbiting embers in BOTH behind (-1) and in-front (+1) layers so it radiates
## organically from the warrior instead of looking pasted onto their back!

var intensity := 0.0
var primary_color := Color(1.0, 0.78, 0.25)
var core_color := Color(1.0, 0.96, 0.80)
var _time := 0.0
var _wisps: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _front_layer: Node2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = -1
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_rng.seed = 4242 + get_instance_id() % 997

	for i in 14:
		_wisps.append({
			"x": _rng.randf_range(-48.0, 48.0),
			"y": _rng.randf_range(0.0, 1.0),
			"speed": _rng.randf_range(0.75, 1.45),
			"width": _rng.randf_range(12.0, 26.0),
			"height": _rng.randf_range(38.0, 78.0),
			"phase": _rng.randf_range(0.0, TAU),
		})
	for i in 12:
		_sparks.append({
			"x": _rng.randf_range(-56.0, 56.0),
			"y": _rng.randf_range(0.0, 1.0),
			"speed": _rng.randf_range(0.9, 1.8),
			"size": _rng.randf_range(2.5, 5.5),
			"phase": _rng.randf_range(0.0, TAU),
			"front": i % 2 == 0,
		})

	_front_layer = _FrontAuraSparks.new()
	_front_layer.owner_aura = self
	_front_layer.z_index = 2
	_front_layer.material = mat
	add_child(_front_layer)


func set_aura(level: float, col: Color) -> void:
	intensity = clampf(level, 0.0, 1.0)
	primary_color = col
	core_color = col.lightened(0.65)
	visible = intensity > 0.02


func _process(delta: float) -> void:
	if intensity <= 0.02:
		return
	_time += delta
	for w in _wisps:
		var ny: float = float(w["y"]) + float(w["speed"]) * delta * (0.85 + intensity * 0.65)
		if ny > 1.0:
			ny -= 1.0
			w["x"] = _rng.randf_range(-46.0, 46.0)
		w["y"] = ny
	for s in _sparks:
		var sy: float = float(s["y"]) + float(s["speed"]) * delta * (0.9 + intensity * 0.75)
		if sy > 1.0:
			sy -= 1.0
			s["x"] = _rng.randf_range(-58.0, 58.0)
		s["y"] = sy
	queue_redraw()
	if _front_layer != null:
		_front_layer.queue_redraw()


func _draw() -> void:
	if intensity <= 0.02:
		return
	var pulse := 0.85 + 0.15 * sin(_time * 12.0)

	# 1. Soft ground-anchored energy pool & pulsing oval rings around the fighter's boots!
	draw_set_transform(Vector2(0.0, -4.0), 0.0, Vector2(1.0, 0.24))
	draw_circle(Vector2.ZERO, 66.0 * (0.85 + intensity * 0.35) * pulse, Color(primary_color.r, primary_color.g, primary_color.b, 0.22 * intensity))
	draw_circle(Vector2.ZERO, 40.0 * pulse, Color(core_color.r, core_color.g, core_color.b, 0.26 * intensity))
	var ring_r := 44.0 + fmod(_time * 85.0, 48.0)
	var ring_a := (1.0 - (ring_r - 44.0) / 48.0) * 0.55 * intensity
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(primary_color.r, primary_color.g, primary_color.b, ring_a), 3.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 2. Organic rising flame/energy wisps curving upward around the body (NOT a static flame sticker!)
	for w in _wisps:
		var prog: float = float(w["y"])
		var env := sin(prog * PI) # smooth fade-in at feet, fade-out above head
		if env <= 0.04:
			continue
		var sway := sin(_time * 9.0 + float(w["phase"]) + prog * 5.0) * 9.0
		var base_x: float = float(w["x"]) * (1.0 - prog * 0.35) + sway
		var base_y := -12.0 - prog * (155.0 + intensity * 55.0)
		var ww: float = float(w["width"]) * (1.0 - prog * 0.55) * (0.75 + intensity * 0.45)
		var hh: float = float(w["height"]) * (0.75 + intensity * 0.45)
		var poly := PackedVector2Array([
			Vector2(base_x, base_y - hh * 0.65),
			Vector2(base_x + ww * 0.55, base_y),
			Vector2(base_x, base_y + hh * 0.35),
			Vector2(base_x - ww * 0.55, base_y),
		])
		draw_colored_polygon(poly, Color(primary_color.r, primary_color.g, primary_color.b, env * 0.28 * intensity))
		var inner := PackedVector2Array([
			Vector2(base_x, base_y - hh * 0.42),
			Vector2(base_x + ww * 0.28, base_y),
			Vector2(base_x, base_y + hh * 0.22),
			Vector2(base_x - ww * 0.28, base_y),
		])
		draw_colored_polygon(inner, Color(core_color.r, core_color.g, core_color.b, env * 0.24 * intensity))

	# 3. Back-layer rising embers
	for s in _sparks:
		if bool(s["front"]):
			continue
		_draw_spark(s)


func _draw_spark(s: Dictionary) -> void:
	var prog: float = float(s["y"])
	var env := sin(prog * PI)
	if env <= 0.05:
		return
	var sx: float = float(s["x"]) + sin(_time * 8.0 + float(s["phase"])) * 12.0
	var sy := -10.0 - prog * (175.0 + intensity * 65.0)
	var sz: float = float(s["size"]) * (0.7 + intensity * 0.5)
	draw_line(Vector2(sx, sy), Vector2(sx, sy + sz * 3.2), Color(primary_color.r, primary_color.g, primary_color.b, env * 0.75 * intensity), sz * 0.9)
	draw_circle(Vector2(sx, sy), sz * 0.55, Color(1.0, 0.98, 0.9, env * 0.9 * intensity))


class _FrontAuraSparks extends Node2D:
	var owner_aura: FighterAura
	func _draw() -> void:
		if owner_aura == null or owner_aura.intensity <= 0.02:
			return
		for s in owner_aura._sparks:
			if bool(s["front"]):
				owner_aura._draw_spark(s)
