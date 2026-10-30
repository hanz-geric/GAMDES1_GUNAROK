class_name RoundTimer
extends Timer
## 60-second round clock that never pauses during active play (GDD II).
## It does stop while the game menu is paused, like everything else.

signal time_changed(seconds: int)
signal time_up

var seconds_left := Balance.ROUND_TIME


func _ready() -> void:
	wait_time = 1.0
	one_shot = false
	timeout.connect(_on_tick)


## Connected to RoundManager.round_started (GDD 8.5).
func _on_round_started(_round_no: int) -> void:
	stop()
	seconds_left = Balance.ROUND_TIME
	time_changed.emit(seconds_left)


func _on_tick() -> void:
	seconds_left -= 1
	time_changed.emit(seconds_left)
	if seconds_left <= 0:
		stop()
		time_up.emit()
