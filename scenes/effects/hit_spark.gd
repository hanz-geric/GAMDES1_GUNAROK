class_name HitSpark
extends Node2D
## Short hit or block effect. Drawn small and behind the fighters so it never
## hides the opponent's wind-up (GDD Section 8.2, readability risk 3).

const DURATION := 0.18

var blocked := false
var big := false
var color := Color(1.0, 0.85, 0.4)
var _life := 0.0


func setup(is_blocked: bool, is_big: bool, accent: Color) -> void:
	blocked = is_blocked
	big = is_big
	color = accent


func _process(delta: float) -> void:
	_life += delta
	if _life >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _life / DURATION
	var alpha := 1.0 - t
	var radius := (30.0 if big else 18.0) * (0.6 + t)
	if blocked:
		# Block spark: a cool ring, clearly different from a hit
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(0.6, 0.85, 1.0, alpha), 4.0)
		draw_arc(Vector2.ZERO, radius * 0.6, 0.0, TAU, 18, Color(1.0, 1.0, 1.0, alpha), 2.0)
		return
	var rays := 10 if big else 8
	for i in rays:
		var angle := i * TAU / rays + 0.3
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(direction * radius * 0.3, direction * radius, Color(color, alpha), 4.0)
	draw_circle(Vector2.ZERO, radius * 0.35, Color(1.0, 1.0, 1.0, alpha))
