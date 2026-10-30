extends Control
## Main menu: choose Arcade or 2-Player Versus (GDD Section 4.4).

var _sounds_on := false

@onready var arcade_button: Button = $Buttons/ArcadeButton
@onready var versus_button: Button = $Buttons/VersusButton
@onready var quit_button: Button = $Buttons/QuitButton


func _ready() -> void:
	for button: Button in [arcade_button, versus_button, quit_button]:
		UiStyle.style_button(button, 28)
		button.focus_entered.connect(_on_focus_changed)
	arcade_button.pressed.connect(_on_arcade_pressed)
	versus_button.pressed.connect(_on_versus_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	arcade_button.grab_focus.call_deferred()
	_enable_sounds.call_deferred()


func _enable_sounds() -> void:
	_sounds_on = true


func _on_focus_changed() -> void:
	if _sounds_on:
		AudioManager.play_sfx(&"ui_move")


func _on_arcade_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	GameState.start_mode(GameState.ARCADE)


func _on_versus_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	GameState.start_mode(GameState.VERSUS)


func _on_quit_pressed() -> void:
	get_tree().quit()
