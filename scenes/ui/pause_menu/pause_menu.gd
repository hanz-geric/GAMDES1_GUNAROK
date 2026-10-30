class_name PauseMenu
extends CanvasLayer
## Pause menu (GDD Section 4.4): resume, restart the match, or quit to the
## main menu. It keeps running while the rest of the game is paused and
## shows the key layout as a reminder (GDD Section IX).

signal resume_chosen
signal restart_chosen
signal menu_chosen

@onready var resume_button: Button = $Root/Panel/VBox/ResumeButton
@onready var restart_button: Button = $Root/Panel/VBox/RestartButton
@onready var menu_button: Button = $Root/Panel/VBox/MenuButton


func _ready() -> void:
	visible = false
	for button: Button in [resume_button, restart_button, menu_button]:
		UiStyle.style_button(button, 24)
		button.focus_entered.connect(_on_focus_changed)
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)


## Connected to Main.pause_pressed (GDD 8.5).
func open() -> void:
	visible = true
	resume_button.grab_focus()
	AudioManager.play_sfx(&"ui_confirm")


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"menu_back"):
		get_viewport().set_input_as_handled()
		_on_resume_pressed()


func _on_focus_changed() -> void:
	if visible:
		AudioManager.play_sfx(&"ui_move")


func _on_resume_pressed() -> void:
	AudioManager.play_sfx(&"ui_back")
	resume_chosen.emit()


func _on_restart_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	restart_chosen.emit()


func _on_menu_pressed() -> void:
	AudioManager.play_sfx(&"ui_back")
	menu_chosen.emit()
