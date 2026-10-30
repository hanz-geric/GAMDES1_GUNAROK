extends Control
## Shown after Zeus is defeated: one or two lines of text and the final score
## (GDD Section 7.2, Ending), then back to character select.

@onready var line_label: Label = $Center/VBox/Line
@onready var score_label: Label = $Center/VBox/Score
@onready var continue_button: Button = $Center/VBox/ContinueButton


func _ready() -> void:
	var champion: WarriorData = GameState.picks[0]
	line_label.text = "The gods said no mortal could stand against them.\n%s of %s has proven them wrong." % [champion.display_name, champion.homeland]
	score_label.text = "FINAL SCORE   %d" % GameState.score
	UiStyle.style_button(continue_button, 24)
	continue_button.pressed.connect(_on_continue_pressed)
	continue_button.grab_focus.call_deferred()
	AudioManager.play_sfx(&"win")


func _on_continue_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	GameState.open_character_select()
