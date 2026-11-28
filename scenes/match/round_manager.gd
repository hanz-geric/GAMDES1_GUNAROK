class_name RoundManager
extends Node
## Runs one best-of-three match using deterministic 60 Hz frame counters
## (no Timer nodes, no await waits, no wall-clock tiebreak — Design Plan v3
## Section 13.3).

signal round_started(round_no: int)
signal round_ended(winner: int, reason: StringName)
signal match_ended(winner: int, perfect: bool, winner_health: int)

enum Phase { IDLE, INTRO, BANNER, LIVE, ROUND_END, MATCH_OVER }

var fighters: Array[Fighter] = []
var rounds_won := [0, 0]
var round_no := 0
var draw_replays := 0
var phase: Phase = Phase.IDLE
var phase_frames := 0
var _pending_winner := 0
var _pending_no_contest := false

@onready var round_timer: RoundTimer = $RoundTimer


func _ready() -> void:
	round_timer.time_up.connect(_on_time_up)
	round_started.connect(round_timer._on_round_started)


func start_match(first: Fighter, second: Fighter) -> void:
	fighters = [first, second]
	rounds_won = [0, 0]
	round_no = 0
	draw_replays = 0
	_pending_winner = 0
	_pending_no_contest = false
	phase = Phase.INTRO
	phase_frames = Balance.INTRO_CARD_FRAMES


func step_tick() -> void:
	match phase:
		Phase.INTRO:
			phase_frames -= 1
			if phase_frames <= 0:
				_start_round()
		Phase.BANNER:
			phase_frames -= 1
			if phase_frames <= 0:
				phase = Phase.LIVE
				for fighter in fighters:
					fighter.set_input_enabled(true)
				round_timer.start()
		Phase.LIVE:
			round_timer.step_tick()
		Phase.ROUND_END:
			phase_frames -= 1
			if phase_frames <= 0:
				_finish_round_end()


## Called synchronously at the end of each 60 Hz simulation tick in Match
## so trades and double KOs resolve deterministically on the exact same frame.
func check_ko() -> void:
	if phase != Phase.LIVE or fighters.size() < 2:
		return
	var first_down := fighters[0].health <= 0.0
	var second_down := fighters[1].health <= 0.0
	if first_down and second_down:
		_end_round(0, &"DOUBLE KO")
	elif second_down:
		_end_round(1, &"KO")
	elif first_down:
		_end_round(2, &"KO")


func _start_round() -> void:
	round_no += 1
	phase = Phase.BANNER
	phase_frames = Balance.BANNER_FRAMES
	round_started.emit(round_no)


func _on_time_up() -> void:
	if phase != Phase.LIVE:
		return
	var h1 := fighters[0].health
	var h2 := fighters[1].health
	if is_equal_approx(h1, h2):
		_end_round(0, &"TIME")
	else:
		_end_round(1 if h1 > h2 else 2, &"TIME")


func _end_round(winner: int, reason: StringName) -> void:
	phase = Phase.ROUND_END
	phase_frames = Balance.ROUND_END_FRAMES
	round_timer.stop()
	for fighter in fighters:
		fighter.set_input_enabled(false)

	var no_contest := false
	if winner == 0:
		if draw_replays >= Balance.MAX_DRAW_REPLAYS:
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

	_pending_winner = winner
	_pending_no_contest = no_contest
	round_ended.emit(winner, reason)


func _finish_round_end() -> void:
	if _pending_no_contest:
		phase = Phase.MATCH_OVER
		match_ended.emit(0, false, 0)
	elif _pending_winner > 0 and rounds_won[_pending_winner - 1] >= Balance.ROUNDS_TO_WIN:
		phase = Phase.MATCH_OVER
		var loser_rounds: int = rounds_won[2 - _pending_winner]
		var health_left := ceili(fighters[_pending_winner - 1].health)
		match_ended.emit(_pending_winner, loser_rounds == 0, health_left)
	else:
		_start_round()


## More damage dealt in the match wins; if equal, the most recent hit frame wins;
## if no hit was landed at all, it is a no contest (returns 0).
func _tiebreak_winner() -> int:
	var d1 := fighters[0].match_damage_dealt
	var d2 := fighters[1].match_damage_dealt
	if not is_equal_approx(d1, d2):
		return 1 if d1 > d2 else 2
	var f1 := fighters[0].last_hit_frame
	var f2 := fighters[1].last_hit_frame
	if f1 < 0 and f2 < 0:
		return 0
	if f1 == f2:
		return 0
	return 1 if f1 > f2 else 2


func export_state() -> Dictionary:
	return {
		"rounds_won": rounds_won.duplicate(),
		"round_no": round_no,
		"draw_replays": draw_replays,
		"phase": int(phase),
		"phase_frames": phase_frames,
		"pending_winner": _pending_winner,
		"pending_no_contest": _pending_no_contest,
		"round_timer": round_timer.export_state(),
	}


func import_state(data: Dictionary) -> void:
	rounds_won = (data["rounds_won"] as Array).duplicate()
	round_no = data["round_no"]
	draw_replays = data["draw_replays"]
	phase = data["phase"] as Phase
	phase_frames = data["phase_frames"]
	_pending_winner = data["pending_winner"]
	_pending_no_contest = data["pending_no_contest"]
	round_timer.import_state(data["round_timer"])
