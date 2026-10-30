extends Node
## Main scene (GDD Figure 5). Shows one screen at a time inside ScreenHolder
## and owns pausing (GDD Section 8.5: pause_pressed).

signal pause_pressed

const SCREENS := {
	&"main_menu": preload("res://scenes/ui/main_menu/main_menu.tscn"),
	&"character_select": preload("res://scenes/ui/character_select/character_select.tscn"),
	&"match": preload("res://scenes/match/match.tscn"),
	&"result": preload("res://scenes/ui/result_screen/result_screen.tscn"),
	&"ending": preload("res://scenes/ui/ending_screen/ending_screen.tscn"),
	&"game_over": preload("res://scenes/ui/game_over_screen/game_over_screen.tscn"),
}

var _current: Node
var _current_key: StringName = &""

@onready var screen_holder: Node = $ScreenHolder
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	GameState.screen_requested.connect(_on_screen_requested)
	GameState.run_completed.connect(_on_run_completed)
	GameState.game_over.connect(_on_game_over)
	pause_pressed.connect(pause_menu.open)
	pause_pressed.connect(_on_pause_pressed)
	pause_menu.resume_chosen.connect(_resume)
	pause_menu.restart_chosen.connect(_on_restart_chosen)
	pause_menu.menu_chosen.connect(_on_menu_chosen)
	_show_screen(&"main_menu")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and _current_key == &"match" and not get_tree().paused:
		get_viewport().set_input_as_handled()
		pause_pressed.emit()


## Connected to GameState.screen_requested. Deferred so the old screen is
## never freed in the middle of its own input or signal handling.
func _on_screen_requested(screen: StringName) -> void:
	_show_screen.call_deferred(screen)


## Connected to GameState.run_completed (GDD 8.5).
func _on_run_completed(_score: int) -> void:
	_show_screen.call_deferred(&"ending")


## Connected to GameState.game_over (GDD 8.5).
func _on_game_over() -> void:
	_show_screen.call_deferred(&"game_over")


func _show_screen(screen: StringName) -> void:
	if _current != null:
		screen_holder.remove_child(_current)
		_current.queue_free()
	var packed: PackedScene = SCREENS[screen]
	_current = packed.instantiate()
	_current_key = screen
	screen_holder.add_child(_current)
	if screen != &"match":
		AudioManager.play_music(&"menu")


## Connected to pause_pressed (GDD 8.5: PauseMenu and the SceneTree).
func _on_pause_pressed() -> void:
	get_tree().paused = true


func _resume() -> void:
	pause_menu.close()
	get_tree().paused = false


func _on_restart_chosen() -> void:
	_resume()
	GameState.restart_match()


func _on_menu_chosen() -> void:
	_resume()
	GameState.go_to_main_menu()
