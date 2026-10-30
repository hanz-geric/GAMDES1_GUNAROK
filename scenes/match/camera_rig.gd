class_name CameraRig
extends Camera2D
## Fixed-angle side camera (GDD Section 8.2). Follows the midpoint between
## the fighters, moves only left and right, no zoom or rotation, and stops
## at the stage walls through its limits.

const VIEW_CENTRE_Y := 360.0

var _a: Node2D
var _b: Node2D


func follow(a: Node2D, b: Node2D, arena_width: float) -> void:
	_a = a
	_b = b
	limit_left = 0
	limit_right = int(arena_width)
	limit_top = 0
	limit_bottom = 720
	global_position = _target()
	reset_smoothing()
	make_current()


func _process(_delta: float) -> void:
	if _a != null and _b != null:
		global_position = _target()


func _target() -> Vector2:
	return Vector2((_a.global_position.x + _b.global_position.x) * 0.5, VIEW_CENTRE_Y)
