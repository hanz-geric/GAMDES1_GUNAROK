extends Control
## Result screen after every match (GDD Sections 4.2 and 7.3). Arcade win:
## next rival or quit. Arcade loss: retry (costs a continue) or quit.
## Versus: rematch or back to character select.

signal next_chosen
signal retry_chosen
signal quit_chosen

var _outcome: StringName = &""

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle_label: Label = $Center/VBox/Subtitle
@onready var detail_label: Label = $Center/VBox/Detail
@onready var primary_button: Button = $Center/VBox/Buttons/PrimaryButton
@onready var secondary_button: Button = $Center/VBox/Buttons/SecondaryButton


func _ready() -> void:
	next_chosen.connect(GameState.on_next_chosen)
	retry_chosen.connect(GameState.on_retry_chosen)
	quit_chosen.connect(GameState.on_quit_chosen)
	for button: Button in [primary_button, secondary_button]:
		UiStyle.style_button(button, 24)
	primary_button.pressed.connect(_on_primary_pressed)
	secondary_button.pressed.connect(_on_secondary_pressed)
	primary_button.focus_entered.connect(_on_focus_changed)
	secondary_button.focus_entered.connect(_on_focus_changed)
	_show(GameState.last_result)
	primary_button.grab_focus.call_deferred()


func _show(result: Dictionary) -> void:
	_outcome = result.get("outcome", &"")
	var p1: WarriorData = GameState.picks[0]
	match _outcome:
		&"win":
			title_label.text = "VICTORY"
			var perfect: bool = result.get("perfect", false)
			subtitle_label.text = "+%d POINTS%s" % [int(result.get("gained", 0)), "   PERFECT!" if perfect else ""]
			var next_rival: WarriorData = result.get("next")
			detail_label.text = "Next rival: %s of %s\nScore: %d" % [next_rival.display_name, next_rival.homeland, GameState.score]
			primary_button.text = "NEXT MATCH"
			secondary_button.text = "QUIT RUN"
			AudioManager.play_sfx(&"win")
		&"lose":
			title_label.text = "DEFEAT"
			title_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.25))
			subtitle_label.text = "%s falls to %s" % [p1.display_name, GameState.current_opponent().display_name]
			if GameState.continues > 0:
				detail_label.text = "Continues left: %d\nRetrying replays the same fight." % GameState.continues
				primary_button.text = "RETRY (USE 1 CONTINUE)"
			else:
				detail_label.text = "No continues left."
				primary_button.text = "CONTINUE"
			secondary_button.text = "QUIT RUN"
			AudioManager.play_sfx(&"lose")
		&"versus":
			var winner: int = result.get("winner", 1)
			var champion: WarriorData = GameState.picks[winner - 1]
			title_label.text = "PLAYER %d WINS" % winner
			subtitle_label.text = champion.display_name.to_upper()
			detail_label.text = "PERFECT!" if result.get("perfect", false) else ""
			primary_button.text = "REMATCH"
			secondary_button.text = "CHARACTER SELECT"
			AudioManager.play_sfx(&"win")
		_:
			title_label.text = "NO CONTEST"
			subtitle_label.text = "Three draws and no hits landed."
			detail_label.text = ""
			primary_button.text = "REMATCH"
			secondary_button.text = "CHARACTER SELECT"
			AudioManager.play_sfx(&"lose")


func _on_focus_changed() -> void:
	AudioManager.play_sfx(&"ui_move")


func _on_primary_pressed() -> void:
	AudioManager.play_sfx(&"ui_confirm")
	if _outcome == &"lose":
		retry_chosen.emit()
	else:
		next_chosen.emit()


func _on_secondary_pressed() -> void:
	AudioManager.play_sfx(&"ui_back")
	quit_chosen.emit()
