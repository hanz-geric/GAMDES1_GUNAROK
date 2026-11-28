extends Control
## Shown after Zeus is defeated: one or two lines of text and the final score
## (GDD Section 7.2, Ending), then back to character select.

@onready var line_label: Label = $Center/VBox/Line
@onready var score_label: Label = $Center/VBox/Score
@onready var continue_button: Button = $Center/VBox/ContinueButton


func _ready() -> void:
	var champion: WarriorData = GameState.picks[0]
	var defeated_god: WarriorData = GameState.last_result.get("defeated_god")
	var newly_unlocked: bool = bool(GameState.last_result.get("newly_unlocked_god", false))
	var god_name := defeated_god.display_name if defeated_god != null else "the Gods"
	var text := "The gods said no mortal could stand against %s.\n%s of %s has proven them wrong." % [god_name, champion.display_name, champion.homeland]
	if defeated_god != null and newly_unlocked:
		text += "\n\n⚡ GOD UNLOCKED: %s IS NOW PLAYABLE! ⚡" % defeated_god.display_name.to_upper()
	elif defeated_god != null:
		text += "\n\n⚡ %s HAS FALLEN — %d / %d GODS UNLOCKED ⚡" % [defeated_god.display_name.to_upper(), GameState.unlocked_god_count(), GameState.bosses.size()]
	line_label.text = text
	score_label.text = "FINAL SCORE   %d" % GameState.score
	UiStyle.style_button(continue_button, 24)
	continue_button.pressed.connect(_on_continue_pressed)
	continue_button.grab_focus.call_deferred()
	AudioManager.play_sfx(&"win")


func _on_continue_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	GameState.open_character_select()
