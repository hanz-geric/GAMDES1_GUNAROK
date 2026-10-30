extends Node
## Autoload (GDD Figure 5): game mode, warrior picks, Arcade ladder step,
## continues and score. It decides which screen Main shows next and starts
## each match (GDD Section 8.5).

signal screen_requested(screen: StringName)
signal match_started(stage: StringName, p1: WarriorData, opponent: WarriorData)
signal run_completed(score: int)
signal game_over

const ARCADE := 0
const VERSUS := 1

const ROSTER_PATHS := [
	"res://data/warriors/leonidas.tres",
	"res://data/warriors/julius_caesar.tres",
	"res://data/warriors/ragnar.tres",
	"res://data/warriors/musashi.tres",
	"res://data/warriors/lapu_lapu.tres",
	"res://data/warriors/crazy_horse.tres",
	"res://data/warriors/simo_hayha.tres",
	"res://data/warriors/nai_khanom_tom.tres",
]
const ZEUS_PATH := "res://data/warriors/zeus.tres"

## The six-match Arcade ladder (GDD Section 5.1, Figure 2, Table B).
const LADDER := [
	{"tier": "res://data/cpu_tiers/tier_1.tres", "stage": &"ancient_arena"},
	{"tier": "res://data/cpu_tiers/tier_2.tres", "stage": &"ancient_arena"},
	{"tier": "res://data/cpu_tiers/tier_3.tres", "stage": &"battlefield"},
	{"tier": "res://data/cpu_tiers/tier_3_soft.tres", "stage": &"battlefield"},
	{"tier": "res://data/cpu_tiers/tier_4.tres", "stage": &"battlefield"},
	{"tier": "res://data/cpu_tiers/boss.tres", "stage": &"mythic_summit"},
]

const STAGES := {
	&"ancient_arena": {"name": "Ancient Arena", "scene": "res://scenes/stages/stage_1_ancient_arena.tscn"},
	&"battlefield": {"name": "Battlefield", "scene": "res://scenes/stages/stage_2_battlefield.tscn"},
	&"mythic_summit": {"name": "Mythic Summit", "scene": "res://scenes/stages/stage_3_mythic_summit.tscn"},
}
const STAGE_ORDER := [&"ancient_arena", &"battlefield", &"mythic_summit"]

var mode := ARCADE
var roster: Array[WarriorData] = []
var zeus: WarriorData
var picks: Array = [null, null]
var versus_stage: StringName = &"ancient_arena"
var ladder_step := 0
var ladder_opponents: Array[WarriorData] = []
var continues := Balance.ARCADE_CONTINUES
var score := 0
var rounds_won_in_run := 0
var last_result: Dictionary = {}
var _tiers: Array[CpuTier] = []


func _ready() -> void:
	for path in ROSTER_PATHS:
		roster.append(load(path) as WarriorData)
	zeus = load(ZEUS_PATH) as WarriorData
	for step in LADDER:
		_tiers.append(load(step["tier"]) as CpuTier)


func is_arcade() -> bool:
	return mode == ARCADE


# --- Scene flow -------------------------------------------------------------

func start_mode(new_mode: int) -> void:
	mode = new_mode
	open_character_select()


func open_character_select() -> void:
	picks = [null, null]
	screen_requested.emit(&"character_select")


func go_to_main_menu() -> void:
	screen_requested.emit(&"main_menu")


func set_versus_stage(stage: StringName) -> void:
	versus_stage = stage


## Connected to CharacterSelect.warrior_selected.
func on_warrior_selected(player: int, warrior: WarriorData) -> void:
	picks[player - 1] = warrior
	if is_arcade():
		_start_run(warrior)
	elif picks[0] != null and picks[1] != null:
		_load_match()


func restart_match() -> void:
	_load_match()


func _start_run(warrior: WarriorData) -> void:
	# Five rivals in a fixed order that depends on the warrior picked
	# (GDD 7.3), then Zeus. No randomness (GDD 6.4).
	ladder_opponents.clear()
	var index := roster.find(warrior)
	for i in range(1, 6):
		ladder_opponents.append(roster[(index + i) % roster.size()])
	ladder_opponents.append(zeus)
	ladder_step = 0
	continues = Balance.ARCADE_CONTINUES
	score = 0
	rounds_won_in_run = 0
	_load_match()


func _load_match() -> void:
	screen_requested.emit(&"match")
	# Deferred so Main has swapped in the new Match before it is told to start.
	_emit_match_started.call_deferred()


func _emit_match_started() -> void:
	match_started.emit(current_stage(), picks[0], current_opponent())


# --- Signal handlers (GDD Section 8.5) --------------------------------------

## Connected to RoundManager.round_ended.
func on_round_ended(winner: int, _reason: StringName) -> void:
	if is_arcade() and winner == 1:
		rounds_won_in_run += 1


## Connected to RoundManager.match_ended.
func on_match_ended(winner: int, perfect: bool, winner_health: int) -> void:
	last_result = {"winner": winner, "perfect": perfect, "outcome": &"", "gained": 0}
	if is_arcade():
		if winner == 1:
			var gained := Balance.SCORE_MATCH_WIN + Balance.SCORE_PER_HEALTH * winner_health
			if perfect:
				gained += Balance.SCORE_PERFECT
			score += gained
			last_result["gained"] = gained
			last_result["outcome"] = &"win"
			if ladder_step >= LADDER.size() - 1:
				run_completed.emit(score)
				return
			last_result["next"] = ladder_opponents[ladder_step + 1]
		else:
			last_result["outcome"] = &"lose"
	else:
		last_result["outcome"] = &"versus" if winner > 0 else &"no_contest"
	screen_requested.emit(&"result")


## Connected to ResultScreen.next_chosen. Arcade: next rival. Versus: rematch.
func on_next_chosen() -> void:
	if is_arcade():
		ladder_step += 1
	_load_match()


## Connected to ResultScreen.retry_chosen.
func on_retry_chosen() -> void:
	if continues <= 0:
		game_over.emit()
		return
	continues -= 1
	_load_match()


## Connected to ResultScreen.quit_chosen.
func on_quit_chosen() -> void:
	open_character_select()


# --- Queries ----------------------------------------------------------------

func current_opponent() -> WarriorData:
	if is_arcade():
		return ladder_opponents[ladder_step]
	return picks[1]


func current_cpu_tier() -> CpuTier:
	if is_arcade():
		return _tiers[ladder_step]
	return null


func current_stage() -> StringName:
	if is_arcade():
		return LADDER[ladder_step]["stage"]
	return versus_stage


func stage_name(stage: StringName) -> String:
	return STAGES[stage]["name"]


func opponent_max_health() -> int:
	var tier := current_cpu_tier()
	if tier != null:
		return tier.health
	return current_opponent().max_health


func match_label() -> String:
	var name_text := stage_name(current_stage()).to_upper()
	if is_arcade():
		return "M%d OF %d  |  %s" % [ladder_step + 1, LADDER.size(), name_text]
	return "VERSUS  |  %s" % name_text
