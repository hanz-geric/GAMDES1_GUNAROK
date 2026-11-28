extends Control
## Character select with separate Mortal Warriors (8) and Mythic Gods (4, locked until defeated in Arcade!).
## Arcade: Player 1 picks a warrior. Versus: both players pick with their own controls, then choose a stage.

signal warrior_selected(player: int, warrior: WarriorData)

const CARD_SCENE := preload("res://scenes/ui/character_select/warrior_card.tscn")
const COLUMNS := 4

var _cards: Array[WarriorCard] = []
var _cursor := [0, 3]
var _locked := [false, false]
var _picking_stage := false
var _stage_index := 0
var _gods_header: Label
var _gods_grid: GridContainer

@onready var grid: GridContainer = $Grid
@onready var mode_label: Label = $ModeLabel
@onready var info_panels: Array = [$P1Info, $P2Info]
@onready var stage_label: Label = $StageLabel
@onready var hint_label: Label = $HintLabel


func _ready() -> void:
	warrior_selected.connect(GameState.on_warrior_selected)

	# Section 1: Mortal Warriors (2 rows of 4)
	grid.offset_top = 110.0
	grid.offset_bottom = 380.0
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_theme_constant_override("h_separation", 12)
	for warrior in GameState.mortal_roster:
		var card := CARD_SCENE.instantiate() as WarriorCard
		card.custom_minimum_size = Vector2(170, 126)
		grid.add_child(card)
		card.setup(warrior, true)
		_cards.append(card)

	# Golden Divine Divider between Mortals and Gods!
	_gods_header = Label.new()
	_gods_header.name = "GodsHeader"
	_gods_header.offset_left = 282.0
	_gods_header.offset_top = 384.0
	_gods_header.offset_right = 998.0
	_gods_header.offset_bottom = 414.0
	_gods_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gods_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gods_header.add_theme_font_size_override("font_size", 17)
	_gods_header.add_theme_color_override("font_color", Color(1.0, 0.86, 0.32))
	_gods_header.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.02))
	_gods_header.add_theme_constant_override("outline_size", 6)
	_gods_header.text = "⚡  GODS OF THE PANTHEON  —  %d / %d UNLOCKED (DEFEAT IN ARCADE)  ⚡" % [
		GameState.unlocked_god_count(), GameState.bosses.size()
	]
	add_child(_gods_header)

	# Section 2: Mythic Gods (1 row of 4, locked until defeated in Arcade Mode!)
	_gods_grid = GridContainer.new()
	_gods_grid.name = "GodsGrid"
	_gods_grid.columns = COLUMNS
	_gods_grid.offset_left = 282.0
	_gods_grid.offset_top = 418.0
	_gods_grid.offset_right = 998.0
	_gods_grid.offset_bottom = 550.0
	_gods_grid.add_theme_constant_override("h_separation", 12)
	_gods_grid.add_theme_constant_override("v_separation", 8)
	add_child(_gods_grid)

	for god in GameState.bosses:
		var card := CARD_SCENE.instantiate() as WarriorCard
		card.custom_minimum_size = Vector2(170, 126)
		_gods_grid.add_child(card)
		card.setup(god, GameState.is_warrior_unlocked(god))
		_cards.append(card)

	var arcade := GameState.is_arcade()
	mode_label.text = "ARCADE  |  CONQUER THE LADDER TO UNLOCK THE GODS" if arcade else "2-PLAYER VERSUS  |  MORTALS & UNLOCKED GODS"
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
	elif _pressed(event, prefix + "jump", arcade, &"ui_up"):
		_move(i, (_cursor[i] - COLUMNS + count) % count)
	elif _pressed(event, prefix + "crouch", arcade, &"ui_down"):
		_move(i, (_cursor[i] + COLUMNS) % count)
	elif event.is_action_pressed(prefix + "light") or event.is_action_pressed(prefix + "heavy") \
			or (arcade and event.is_action_pressed(&"ui_accept")):
		_lock(i)


func _pressed(event: InputEvent, action: String, arcade: bool, ui_action: StringName) -> bool:
	return event.is_action_pressed(action) or (arcade and event.is_action_pressed(ui_action))


func _move(i: int, index: int) -> void:
	_cursor[i] = index
	AudioManager.play_sfx(&"ui_move")
	_refresh()


func _lock(i: int) -> void:
	var card := _cards[_cursor[i]]
	if not card.is_unlocked:
		# Locked God: deny selection cleanly and flash status!
		get_viewport().set_input_as_handled()
		AudioManager.play_sfx(&"ui_back")
		var status_lbl := info_panels[i].get_node("Status") as Label
		status_lbl.modulate = Color(1.0, 0.35, 0.25)
		var tw := create_tween()
		tw.tween_property(status_lbl, "modulate", Color.WHITE, 0.28)
		return
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
	elif event.is_action_pressed(&"p1_light") or event.is_action_pressed(&"p2_light") \
			or event.is_action_pressed(&"p1_heavy") or event.is_action_pressed(&"p2_heavy"):
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
	_fill_info(0, _cards[_cursor[0]], "PLAYER 1")
	if arcade:
		var mortals := GameState.mortal_roster
		var first_rival: WarriorData = mortals[(_cursor[0] + 1) % mortals.size()]
		_fill_info_warrior(1, first_rival, true, "FIRST RIVAL")
		(info_panels[1].get_node("Status") as Label).text = "5 Mortal Rivals\n+ Final GOD BOSS"
	else:
		_fill_info(1, _cards[_cursor[1]], "PLAYER 2")
	var stage_id: StringName = GameState.STAGE_ORDER[_stage_index]
	stage_label.text = "STAGE:   <  %s  >" % GameState.stage_name(stage_id).to_upper()
	stage_label.modulate = Color(1.0, 0.85, 0.3) if _picking_stage else Color(0.7, 0.7, 0.7)
	if _picking_stage:
		hint_label.text = "Left / Right to change stage   |   Light or Heavy to FIGHT   |   Block to go back"
	elif arcade:
		hint_label.text = "Arrows or A / D, W / S to choose   |   Enter, F or G to confirm   |   Backspace for main menu"
	else:
		hint_label.text = "P1: WASD, confirm F / G, cancel J     P2: Arrows, confirm , / ., cancel R-Shift"


func _fill_info(i: int, card: WarriorCard, header: String) -> void:
	_fill_info_warrior(i, card.warrior, card.is_unlocked, header)


func _fill_info_warrior(i: int, warrior: WarriorData, unlocked: bool, header: String) -> void:
	var panel: Control = info_panels[i]
	(panel.get_node("Header") as Label).text = header
	if not unlocked:
		(panel.get_node("Name") as Label).text = "LOCKED GOD"
		(panel.get_node("Origin") as Label).text = "%s\n%s" % [warrior.display_name, warrior.homeland]
		(panel.get_node("Stats") as Label).text = "DAMAGE  ?????\nREACH     ?????\nSPEED     ?????"
		(panel.get_node("Special") as Label).text = GameState.god_unlock_hint(warrior.id)
		var status_lbl := panel.get_node("Status") as Label
		status_lbl.text = "LOCKED"
		status_lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.30))
		return

	(panel.get_node("Name") as Label).text = warrior.display_name.to_upper()
	(panel.get_node("Origin") as Label).text = "%s\n%s" % [warrior.homeland, warrior.era]
	(panel.get_node("Stats") as Label).text = "DAMAGE  %s\nREACH     %s\nSPEED     %s" % [
		_stat_bar(warrior.damage_rating), _stat_bar(warrior.reach_rating), _stat_bar(warrior.speed_rating)]
	(panel.get_node("Special") as Label).text = "Ultimate: %s" % warrior.special_name
	var status_lbl := panel.get_node("Status") as Label
	status_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	if _locked[i]:
		status_lbl.text = "LOCKED IN"
	elif warrior.is_boss:
		status_lbl.text = "GOD UNLOCKED!"
	else:
		status_lbl.text = ""


func _stat_bar(rating: int) -> String:
	return "■".repeat(rating) + "□".repeat(5 - rating)
