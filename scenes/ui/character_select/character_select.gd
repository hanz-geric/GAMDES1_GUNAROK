extends Control
## Character select (GDD Sections 4.2 and 7.3, Decision 1). Arcade: Player 1
## picks a warrior. Versus: both players pick at the same time with their own
## controls, then choose a stage. Each player confirms with punch or kick and
## cancels with block (GDD Section 8.3).

signal warrior_selected(player: int, warrior: WarriorData)

const CARD_SCENE := preload("res://scenes/ui/character_select/warrior_card.tscn")
const COLUMNS := 4

var _cards: Array[WarriorCard] = []
var _cursor := [0, 3]
var _locked := [false, false]
var _picking_stage := false
var _stage_index := 0

@onready var grid: GridContainer = $Grid
@onready var mode_label: Label = $ModeLabel
@onready var info_panels: Array = [$P1Info, $P2Info]
@onready var stage_label: Label = $StageLabel
@onready var hint_label: Label = $HintLabel


func _ready() -> void:
	warrior_selected.connect(GameState.on_warrior_selected)
	for warrior in GameState.roster:
		var card := CARD_SCENE.instantiate() as WarriorCard
		grid.add_child(card)
		card.setup(warrior)
		_cards.append(card)
	var arcade := GameState.is_arcade()
	mode_label.text = "ARCADE  |  CLIMB THE LADDER, DEFEAT ZEUS" if arcade else "2-PLAYER VERSUS"
	stage_label.visible = not arcade
	_stage_index = GameState.STAGE_ORDER.find(GameState.versus_stage)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_pressed() and not event.is_echo()):
		return
	if event.is_action_pressed(&"menu_back") and not _locked[0] and not _locked[1]:
		get_viewport().set_input_as_handled()
		AudioManager.play_sfx(&"ui_back")
		GameState.go_to_main_menu()
		return
	if _picking_stage:
		_handle_stage_input(event)
		return
	_handle_player_input(0, event)
	if not GameState.is_arcade():
		_handle_player_input(1, event)


func _handle_player_input(i: int, event: InputEvent) -> void:
	var prefix := "p%d_" % (i + 1)
	var arcade := GameState.is_arcade()
	if _locked[i]:
		if event.is_action_pressed(prefix + "block"):
			_locked[i] = false
			AudioManager.play_sfx(&"ui_back")
			_refresh()
		return
	var count := _cards.size()
	if _pressed(event, prefix + "left", arcade, &"ui_left"):
		_move(i, (_cursor[i] - 1 + count) % count)
	elif _pressed(event, prefix + "right", arcade, &"ui_right"):
		_move(i, (_cursor[i] + 1) % count)
	elif _pressed(event, prefix + "jump", arcade, &"ui_up") or _pressed(event, prefix + "crouch", arcade, &"ui_down"):
		_move(i, (_cursor[i] + COLUMNS) % count)
	elif event.is_action_pressed(prefix + "punch") or event.is_action_pressed(prefix + "kick") \
			or (arcade and event.is_action_pressed(&"ui_accept")):
		_lock(i)


func _pressed(event: InputEvent, action: String, arcade: bool, ui_action: StringName) -> bool:
	return event.is_action_pressed(action) or (arcade and event.is_action_pressed(ui_action))


func _move(i: int, index: int) -> void:
	_cursor[i] = index
	AudioManager.play_sfx(&"ui_move")
	_refresh()


func _lock(i: int) -> void:
	get_viewport().set_input_as_handled()
	_locked[i] = true
	AudioManager.play_sfx(&"ui_confirm")
	_refresh()
	if GameState.is_arcade():
		warrior_selected.emit(1, _cards[_cursor[0]].warrior)
	elif _locked[0] and _locked[1]:
		_picking_stage = true
		_refresh()


func _handle_stage_input(event: InputEvent) -> void:
	var count: int = GameState.STAGE_ORDER.size()
	if event.is_action_pressed(&"p1_left") or event.is_action_pressed(&"p2_left"):
		_stage_index = (_stage_index - 1 + count) % count
		AudioManager.play_sfx(&"ui_move")
	elif event.is_action_pressed(&"p1_right") or event.is_action_pressed(&"p2_right"):
		_stage_index = (_stage_index + 1) % count
		AudioManager.play_sfx(&"ui_move")
	elif event.is_action_pressed(&"p1_block") or event.is_action_pressed(&"p2_block"):
		_picking_stage = false
		_locked = [false, false]
		AudioManager.play_sfx(&"ui_back")
	elif event.is_action_pressed(&"p1_punch") or event.is_action_pressed(&"p2_punch") \
			or event.is_action_pressed(&"p1_kick") or event.is_action_pressed(&"p2_kick"):
		get_viewport().set_input_as_handled()
		AudioManager.play_sfx(&"ui_confirm")
		GameState.set_versus_stage(GameState.STAGE_ORDER[_stage_index])
		warrior_selected.emit(1, _cards[_cursor[0]].warrior)
		warrior_selected.emit(2, _cards[_cursor[1]].warrior)
		return
	_refresh()


func _refresh() -> void:
	var arcade := GameState.is_arcade()
	for index in _cards.size():
		var p1 := 0
		var p2 := 0
		if _cursor[0] == index:
			p1 = 2 if _locked[0] else 1
		if not arcade and _cursor[1] == index:
			p2 = 2 if _locked[1] else 1
		_cards[index].set_cursor(p1, p2)
	_fill_info(0, _cards[_cursor[0]].warrior, "PLAYER 1")
	if arcade:
		var first_rival: WarriorData = GameState.roster[(_cursor[0] + 1) % GameState.roster.size()]
		_fill_info(1, first_rival, "FIRST RIVAL")
		(info_panels[1].get_node("Status") as Label).text = "Then 4 more rivals\nand ZEUS"
	else:
		_fill_info(1, _cards[_cursor[1]].warrior, "PLAYER 2")
	var stage_id: StringName = GameState.STAGE_ORDER[_stage_index]
	stage_label.text = "STAGE:   <  %s  >" % GameState.stage_name(stage_id).to_upper()
	stage_label.modulate = Color(1.0, 0.85, 0.3) if _picking_stage else Color(0.7, 0.7, 0.7)
	if _picking_stage:
		hint_label.text = "Left / Right to change stage   |   Punch or Kick to FIGHT   |   Block to go back"
	elif arcade:
		hint_label.text = "Arrows or A / D, W / S to choose   |   Enter, F or G to confirm   |   Backspace for main menu"
	else:
		hint_label.text = "P1: A / D / W / S, confirm F, cancel H     P2: Arrows, confirm Num 1, cancel Num 3"


func _fill_info(i: int, warrior: WarriorData, header: String) -> void:
	var panel: Control = info_panels[i]
	(panel.get_node("Header") as Label).text = header
	(panel.get_node("Name") as Label).text = warrior.display_name.to_upper()
	(panel.get_node("Origin") as Label).text = "%s\n%s" % [warrior.homeland, warrior.era]
	(panel.get_node("Stats") as Label).text = "DAMAGE  %s\nREACH     %s\nSPEED     %s" % [
		_stat_bar(warrior.damage_rating), _stat_bar(warrior.reach_rating), _stat_bar(warrior.speed_rating)]
	(panel.get_node("Special") as Label).text = "Special: %s" % warrior.special_name
	var status := ""
	if _locked[i]:
		status = "LOCKED IN"
	(panel.get_node("Status") as Label).text = status


func _stat_bar(rating: int) -> String:
	return "■".repeat(rating) + "□".repeat(5 - rating)
