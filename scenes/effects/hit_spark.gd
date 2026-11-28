class_name HitSpark
extends Node2D
## Vibrant additive-glowing hit, heavy, block, and gold parry sparks.
## Visual only; never affects simulation state.

const DURATION := 0.24
const SPARK_LIGHT_PATH := "res://assets/sprites/fx/hit_spark_light_frames.tres"
const SPARK_HEAVY_PATH := "res://assets/sprites/fx/hit_spark_heavy_frames.tres"
const SPARK_BLOCK_PATH := "res://assets/sprites/fx/block_spark_frames.tres"

var blocked := false
var big := false
var parried := false
var color := Color(1.0, 0.85, 0.4)
var _life := 0.0
var _sprite: AnimatedSprite2D


func setup(is_blocked: bool, is_big: bool, accent: Color, is_parry: bool = false) -> void:
	blocked = is_blocked
	big = is_big
	parried = is_parry
	color = accent
	z_index = 7

	var path := SPARK_BLOCK_PATH if blocked else (SPARK_HEAVY_PATH if (big or parried) else SPARK_LIGHT_PATH)
	if ResourceLoader.exists(path):
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = load(path)
		var s := 1.65 if (big or parried) else 1.15
		_sprite.scale = Vector2(s, s)
		if parried:
			_sprite.modulate = Color(1.0, 0.94, 0.35)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_sprite.material = mat
		add_child(_sprite)
		_sprite.play(&"default")


func _process(delta: float) -> void:
	_life += delta
	if _life >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _life / DURATION
	var alpha := 1.0 - t
	if parried:
		var r := 44.0 + 52.0 * t
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(1.0, 0.92, 0.3, alpha * 0.85), 7.0)
		draw_arc(Vector2.ZERO, r * 0.72, 0.0, TAU, 24, Color(1.0, 1.0, 0.9, alpha), 3.0)
		return
	if _sprite != null:
		return
	var radius := (36.0 if big else 20.0) * (0.6 + t)
	if blocked:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(0.6, 0.88, 1.0, alpha), 4.5)
		return
	for i in 8:
		var angle := i * TAU / 8.0 + 0.3
		var d := Vector2(cos(angle), sin(angle))
		draw_line(d * radius * 0.3, d * radius, Color(color, alpha), 4.0)
