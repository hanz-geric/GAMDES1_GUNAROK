class_name RoundManager
extends Node
## Runs one best-of-three match: round start, KO and time-out checks, draws,
## and the match result (GDD Section II Outcome and Section 8.5).

signal round_started(round_no: int)
signal round_ended(winner: int, reason: StringName)
signal match_ended(winner: int, perfect: bool, winner_health: int)

var fighters: Array[Fighter] = []
var rounds_won := [0, 0]
var round_no := 0
var draw_replays := 0
var _round_live := false
var _ko_check_pending := false

@onready var round_timer: RoundTimer = $RoundTimer


func _ready() -> void:
	round_timer.time_up.connect(_on_time_up)
	round_started.connect(round_timer._on_round_started)


func start_match(first: Fighter, second: Fighter) -> void:
	fighters = [first, second]
	rounds_won = [0, 0]
	round_no = 0
	draw_replays = 0
	await _wait(Balance.INTRO_CARD_TIME)
	_start_round()


func _start_round() -> void:
	round_no += 1
	_round_live = false
	round_started.emit(round_no)
	await _wait(Balance.BANNER_TIME)
	_round_live = true
	for fighter in fighters:
		fighter.set_input_enabled(true)
	round_timer.start()


## Connected to Fighter.health_changed (GDD 8.5).
func _on_health_changed(_fighter: Fighter, value: float) -> void:
	if _round_live and value <= 0.0 and not _ko_check_pending:
		# Checked at the end of the frame so a double KO is caught.
		_ko_check_pending = true
		_check_ko.call_deferred()


func _check_ko() -> void:
	_ko_check_pending = false
	if not _round_live:
		return
	var first_down := fighters[0].health <= 0.0
	var second_down := fighters[1].health <= 0.0
	if first_down and second_down:
		_end_round(0, &"DOUBLE KO")
	elif second_down:
		_end_round(1, &"KO")
	elif first_down:
		_end_round(2, &"KO")


## Connected to RoundTimer.time_up (GDD 8.5).
func _on_time_up() -> void:
	if not _round_live:
		return
	var h1 := fighters[0].health
	var h2 := fighters[1].health
	if is_equal_approx(h1, h2):
		_end_round(0, &"TIME")
	else:
		_end_round(1 if h1 > h2 else 2, &"TIME")


func _end_round(winner: int, reason: StringName) -> void:
	_round_live = false
	round_timer.stop()
	for fighter in fighters:
		fighter.set_input_enabled(false)
	var no_contest := false
	if winner == 0:
		if draw_replays >= Balance.MAX_DRAW_REPLAYS:
			# Third draw in a match (GDD II Outcome): decide it.
			winner = _tiebreak_winner()
			if winner == 0:
				no_contest = true
				reason = &"NO CONTEST"
			else:
				reason = &"DECISION"
		else:
			draw_replays += 1
	if winner > 0:
		rounds_won[winner - 1] += 1
		fighters[winner - 1].play_victory()
	round_ended.emit(winner, reason)
	await _wait(Balance.ROUND_END_TIME)
	if no_contest:
		match_ended.emit(0, false, 0)
	elif winner > 0 and rounds_won[winner - 1] >= Balance.ROUNDS_TO_WIN:
		var loser_rounds: int = rounds_won[2 - winner]
		var health_left := ceili(fighters[winner - 1].health)
		match_ended.emit(winner, loser_rounds == 0, health_left)
	else:
		_start_round()


## More damage dealt in the match wins; if equal, the most recent hit wins;
## if no hit was landed at all, it is a no contest (returns 0).
func _tiebreak_winner() -> int:
	var d1 := fighters[0].match_damage_dealt
	var d2 := fighters[1].match_damage_dealt
	if not is_equal_approx(d1, d2):
		return 1 if d1 > d2 else 2
	var t1 := fighters[0].last_hit_msec
	var t2 := fighters[1].last_hit_msec
	if t1 < 0 and t2 < 0:
		return 0
	return 1 if t1 > t2 else 2


## Waits using a child Timer, so the wait pauses with the game and is
## dropped safely if the match is freed.
func _wait(seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()
