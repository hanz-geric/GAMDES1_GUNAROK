extends Control
## Shown when the player runs out of continues (GDD Sections 6.1 and 7.3).

@onready var line_label: Label = $Center/VBox/Line
@onready var score_label: Label = $Center/VBox/Score
@onready var continue_button: Button = $Center/VBox/ContinueButton


func _ready() -> void:
	var rival: WarriorData = GameState.current_opponent()
	line_label.text = "Your run ended at match %d of %d, against %s." % [GameState.ladder_step + 1, GameState.LADDER.size(), rival.display_name]
	score_label.text = "SCORE   %d" % GameState.score
	UiStyle.style_button(continue_button, 24)
	continue_button.pressed.connect(_on_continue_pressed)
	continue_button.grab_focus.call_deferred()
	AudioManager.play_sfx(&"lose")


func _on_continue_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	GameState.open_character_select()
