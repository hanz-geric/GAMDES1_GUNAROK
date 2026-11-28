class_name CameraRig
extends Camera2D
## Dynamic cinematic fighting-game camera (Tekken 8 / Street Fighter 6 style):
## - Follows midpoint between fighters inside stage limits.
## - Dynamically zooms in during close-quarters combat (1.00x -> 1.09x).
## - Supports dramatic Ultimate focus lock-on zoom (zooms right onto the caster!).
## - Punches zoom & adds trauma-based screen shake on Parries, Counters, Ultimates & K.O.s.

const VIEW_CENTRE_Y := 360.0
const MIN_ZOOM := 1.0
const CLOSE_ZOOM := 1.09

var _a: Node2D
var _b: Node2D
var _shake_trauma := 0.0
var _zoom_punch := 0.0
var _focus_node: Node2D
var _focus_timer := 0.0
var _focus_zoom := 1.38
var _shake_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_shake_rng.seed = 9001


func follow(a: Node2D, b: Node2D, arena_width: float) -> void:
	_a = a
	_b = b
	_focus_node = null
	_focus_timer = 0.0
	limit_left = 0
	limit_right = int(arena_width)
	limit_top = 0
	limit_bottom = 720
	global_position = _target()
	zoom = Vector2.ONE
	offset = Vector2.ZERO
	_shake_trauma = 0.0
	_zoom_punch = 0.0
	reset_smoothing()
	make_current()


func add_shake(amount: float) -> void:
	_shake_trauma = minf(_shake_trauma + amount, 1.0)


func punch_zoom(amount: float) -> void:
	_zoom_punch = maxf(_zoom_punch, amount)


## Dramatically locks onto a fighter during Ultimate ignition for Tekken/SF cutscene punch!
func focus_on(target: Node2D, dur: float = 0.85, zoom_val: float = 1.36) -> void:
	_focus_node = target
	_focus_timer = dur
	_focus_zoom = zoom_val


func clear_focus() -> void:
	_focus_node = null
	_focus_timer = 0.0


func _process(delta: float) -> void:
	if _focus_timer > 0.0:
		_focus_timer = maxf(_focus_timer - delta, 0.0)
		if _focus_timer <= 0.0:
			_focus_node = null

	if _a != null and _b != null:
		var target_pos: Vector2
		var desired_zoom: float
		if _focus_node != null and is_instance_valid(_focus_node):
			target_pos = Vector2(_focus_node.global_position.x, clampf(_focus_node.global_position.y - 110.0, 290.0, 410.0))
			desired_zoom = _focus_zoom
		else:
			target_pos = _target()
			var dist := absf(_a.global_position.x - _b.global_position.x)
			var close_t := clampf(1.0 - (dist - 180.0) / 520.0, 0.0, 1.0)
			var base_z := lerpf(MIN_ZOOM, CLOSE_ZOOM, close_t)
			_zoom_punch = maxf(_zoom_punch - delta * 0.42, 0.0)
			desired_zoom = clampf(base_z + _zoom_punch, MIN_ZOOM, 1.28)

		global_position = global_position.lerp(target_pos, clampf(delta * 10.5, 0.0, 1.0))
		var cur := lerpf(zoom.x, desired_zoom, clampf(delta * 10.0, 0.0, 1.0))
		zoom = Vector2(cur, cur)

	if _shake_trauma > 0.0:
		_shake_trauma = maxf(_shake_trauma - delta * 3.4, 0.0)
		var mag := _shake_trauma * _shake_trauma * 20.0
		offset = Vector2(
			_shake_rng.randf_range(-mag, mag),
			_shake_rng.randf_range(-mag * 0.7, mag * 0.7)
		)
	else:
		offset = Vector2.ZERO


func _target() -> Vector2:
	return Vector2((_a.global_position.x + _b.global_position.x) * 0.5, VIEW_CENTRE_Y)
