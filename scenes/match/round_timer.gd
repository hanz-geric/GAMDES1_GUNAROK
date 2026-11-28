class_name RoundTimer
extends Node
## 60-second round clock driven by fixed 60 Hz simulation frames instead of
## a Timer node (Design Plan v3 Section 13.3).

signal time_changed(seconds: int)
signal time_up

var frames_left := Balance.ROUND_TIME_FRAMES
var seconds_left := Balance.ROUND_TIME
var running := false


func _on_round_started(_round_no: int) -> void:
	running = false
	frames_left = Balance.ROUND_TIME_FRAMES
	seconds_left = Balance.ROUND_TIME
	time_changed.emit(seconds_left)


func start() -> void:
	running = true


func stop() -> void:
	running = false


func step_tick() -> void:
	if not running:
		return
	frames_left = maxi(frames_left - 1, 0)
	var next_seconds := ceili(float(frames_left) / float(Balance.TICK_RATE))
	if next_seconds != seconds_left:
		seconds_left = next_seconds
		time_changed.emit(seconds_left)
	if frames_left <= 0:
		running = false
		time_up.emit()


func export_state() -> Dictionary:
	return {
		"frames_left": frames_left,
		"seconds_left": seconds_left,
		"running": running,
	}


func import_state(data: Dictionary) -> void:
	frames_left = data["frames_left"]
	seconds_left = data["seconds_left"]
	running = data["running"]
