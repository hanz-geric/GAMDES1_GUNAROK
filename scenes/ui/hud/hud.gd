class_name Hud
extends CanvasLayer
## Fixed HUD on its own CanvasLayer, so it never moves with the camera and
## stage art cannot cover it (GDD Section 8.2). Every color cue has a second
## cue such as a pulse, a size change or text (GDD Section IX).

const BAR_WIDTH := 400.0
const P1_COLOR := Color(0.35, 0.75, 1.0)
const P2_COLOR := Color(1.0, 0.55, 0.2)
const HEALTH_COLOR := Color(0.95, 0.82, 0.25)
const HEALTH_LOW_COLOR := Color(0.95, 0.3, 0.2)
const METER_COLOR := Color(0.4, 0.8, 1.0)
const METER_READY_COLOR := Color(1.0, 0.9, 0.35)
const MARKER_OFF := Color(0.2, 0.2, 0.24)
const MARKER_ON := Color(1.0, 0.82, 0.3)

var _rounds_won := [0, 0]
var _max_health := [100.0, 100.0]
var _meter_ready := [false, false]
var _meter_tweens: Array = [null, null]
var _timer_tween: Tween
var _announce_serial := 0

@onready var health_bars: Array = [$Root/HealthBar1, $Root/HealthBar2]
@onready var name_labels: Array = [$Root/NameLabel1, $Root/NameLabel2]
@onready var meter_bars: Array = [$Root/MeterBar1, $Root/MeterBar2]
@onready var ready_labels: Array = [$Root/ReadyLabel1, $Root/ReadyLabel2]
@onready var round_markers: Array = [$Root/RoundMarkers1, $Root/RoundMarkers2]
@onready var timer_label: Label = $Root/TimerLabel
@onready var info_label: Label = $Root/InfoLabel
@onready var announcer: Label = $Root/Announcer
@onready var sub_announcer: Label = $Root/SubAnnouncer
@onready var intro_card: Panel = $Root/IntroCard
@onready var intro_title: Label = $Root/IntroCard/IntroTitle
@onready var intro_name: Label = $Root/IntroCard/IntroName
@onready var intro_origin: Label = $Root/IntroCard/IntroOrigin


func _ready() -> void:
	GameState.match_started.connect(_on_match_started)
	announcer.visible = false
	sub_announcer.visible = false
	intro_card.visible = false
	for i in 2:
		var bar: TextureProgressBar = health_bars[i]
		bar.tint_progress = HEALTH_COLOR
		var meter: TextureProgressBar = meter_bars[i]
		meter.tint_progress = METER_COLOR
		meter.value = 0.0
		(ready_labels[i] as Label).visible = false
		(name_labels[i] as Label).add_theme_color_override("font_color", P1_COLOR if i == 0 else P2_COLOR)
		_build_markers(i)


func _exit_tree() -> void:
	if GameState.match_started.is_connected(_on_match_started):
		GameState.match_started.disconnect(_on_match_started)


## Connected to GameState.match_started (GDD 8.5). Shows the opponent intro
## card: name, homeland and era for about two seconds (GDD 7.2).
func _on_match_started(_stage: StringName, p1: WarriorData, opponent: WarriorData) -> void:
	_rounds_won = [0, 0]
	_max_health = [float(p1.max_health), float(GameState.opponent_max_health())]
	for i in 2:
		var bar: TextureProgressBar = health_bars[i]
		bar.max_value = _max_health[i]
		bar.value = _max_health[i]
		_update_markers(i)
	# Zeus's longer health bar tells the player he is stronger (GDD 7.2).
	var p2_bar: TextureProgressBar = health_bars[1]
	var width := BAR_WIDTH * clampf(_max_health[1] / 100.0, 1.0, 1.35)
	p2_bar.offset_left = p2_bar.offset_right - width
	(name_labels[0] as Label).text = p1.display_name.to_upper()
	(name_labels[1] as Label).text = opponent.display_name.to_upper()
	info_label.text = GameState.match_label()
	_show_intro(p1, opponent)


func _show_intro(p1: WarriorData, opponent: WarriorData) -> void:
	if GameState.is_arcade():
		intro_title.text = "MATCH %d   VS" % (GameState.ladder_step + 1)
		intro_name.text = opponent.display_name.to_upper()
		intro_origin.text = "%s  |  %s" % [opponent.homeland, opponent.era]
	else:
		intro_title.text = "VERSUS"
		intro_name.text = "%s  vs  %s" % [p1.display_name.to_upper(), opponent.display_name.to_upper()]
		intro_origin.text = GameState.stage_name(GameState.current_stage())
	intro_card.visible = true
	intro_card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(intro_card, "modulate:a", 1.0, 0.2)
	tween.tween_interval(Balance.INTRO_CARD_TIME - 0.45)
	tween.tween_property(intro_card, "modulate:a", 0.0, 0.2)
	tween.tween_callback(intro_card.hide)
	AudioManager.play_sfx(&"intro")


## Connected to RoundManager.round_started (GDD 8.5).
func _on_round_started(round_no: int) -> void:
	_reset_timer_label()
	_announce("ROUND %d" % round_no, "", 0.85, &"round")
	await _wait(0.85)
	_announce("FIGHT!", "", 0.75, &"fight")


## Connected to Fighter.health_changed (GDD 8.5).
func _on_health_changed(fighter: Fighter, value: float) -> void:
	var i := fighter.player_index - 1
	var bar: TextureProgressBar = health_bars[i]
	bar.value = value
	var max_value: float = _max_health[i]
	var low := value <= max_value * 0.25
	bar.tint_progress = HEALTH_LOW_COLOR if low else HEALTH_COLOR


## Connected to Fighter.meter_changed (GDD 8.5). At 50 or more the bar
## pulses and SPECIAL READY appears (GDD 5.4 and IX).
func _on_meter_changed(fighter: Fighter, value: float) -> void:
	var i := fighter.player_index - 1
	var bar: TextureProgressBar = meter_bars[i]
	bar.value = value
	var is_ready := value >= Balance.SPECIAL_COST
	if is_ready == _meter_ready[i]:
		return
	_meter_ready[i] = is_ready
	(ready_labels[i] as Label).visible = is_ready
	var old_tween: Tween = _meter_tweens[i]
	if old_tween != null:
		old_tween.kill()
	bar.modulate = Color.WHITE
	if is_ready:
		bar.tint_progress = METER_READY_COLOR
		var tween := create_tween().set_loops()
		tween.tween_property(bar, "modulate", Color(1.4, 1.4, 1.4), 0.3)
		tween.tween_property(bar, "modulate", Color.WHITE, 0.3)
		_meter_tweens[i] = tween
		AudioManager.play_sfx(&"special_ready", -4.0)
	else:
		bar.tint_progress = METER_COLOR
		_meter_tweens[i] = null


## Connected to RoundTimer.time_changed (GDD 8.5). In the last 10 seconds
## the timer turns red, grows and pulses, with a tick sound (GDD 5.4).
func _on_time_changed(seconds: int) -> void:
	timer_label.text = str(maxi(seconds, 0))
	if seconds <= 10 and seconds > 0:
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		if _timer_tween != null:
			_timer_tween.kill()
		timer_label.scale = Vector2(1.5, 1.5)
		_timer_tween = create_tween()
		_timer_tween.tween_property(timer_label, "scale", Vector2(1.2, 1.2), 0.4)
		AudioManager.play_sfx(&"timer_tick", -6.0)


## Connected to Hitbox.hit_landed (GDD 8.5). Flashes the defender's bar and
## calls out the special's name.
func _on_hit_landed(attacker: Fighter, defender: Fighter, _damage: float, blocked: bool) -> void:
	var bar: TextureProgressBar = health_bars[defender.player_index - 1]
	bar.modulate = Color(1.0, 0.45, 0.45) if not blocked else Color(0.6, 0.85, 1.0)
	var tween := create_tween()
	tween.tween_property(bar, "modulate", Color.WHITE, 0.25)
	if attacker.attack_name == &"special" and not blocked:
		sub_announcer.text = attacker.data.special_name.to_upper() + "!"
		sub_announcer.visible = true
		var callout := create_tween()
		callout.tween_interval(0.8)
		callout.tween_callback(sub_announcer.hide)


## Connected to RoundManager.round_ended (GDD 8.5).
func _on_round_ended(winner: int, reason: StringName) -> void:
	var title := "K.O."
	var sound: StringName = &"ko"
	match reason:
		&"TIME":
			title = "TIME"
			sound = &"time_up"
		&"DOUBLE KO":
			title = "DOUBLE K.O."
		&"DECISION":
			title = "DECISION"
			sound = &"time_up"
		&"NO CONTEST":
			title = "NO CONTEST"
			sound = &"time_up"
	var sub := "DRAW  -  ROUND REPLAYS"
	if winner > 0:
		_rounds_won[winner - 1] += 1
		_update_markers(winner - 1)
		sub = "%s WINS THE ROUND" % (name_labels[winner - 1] as Label).text
	elif reason == &"NO CONTEST":
		sub = "NO HITS LANDED"
	_announce(title, sub, Balance.ROUND_END_TIME - 0.3, sound)


func _announce(text: String, sub_text: String, duration: float, sound: StringName) -> void:
	_announce_serial += 1
	var serial := _announce_serial
	announcer.text = text
	announcer.visible = true
	announcer.scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.tween_property(announcer, "scale", Vector2.ONE, 0.18)
	sub_announcer.text = sub_text
	sub_announcer.visible = sub_text != ""
	AudioManager.play_sfx(sound)
	await _wait(duration)
	if serial == _announce_serial:
		announcer.visible = false
		sub_announcer.visible = false


func _reset_timer_label() -> void:
	if _timer_tween != null:
		_timer_tween.kill()
	timer_label.text = str(Balance.ROUND_TIME)
	timer_label.scale = Vector2.ONE
	timer_label.remove_theme_color_override("font_color")


func _build_markers(i: int) -> void:
	var box: HBoxContainer = round_markers[i]
	for child in box.get_children():
		child.queue_free()
	for k in Balance.ROUNDS_TO_WIN:
		var marker := ColorRect.new()
		marker.custom_minimum_size = Vector2(22.0, 14.0)
		marker.color = MARKER_OFF
		box.add_child(marker)


func _update_markers(i: int) -> void:
	var box: HBoxContainer = round_markers[i]
	var markers := box.get_children()
	for k in markers.size():
		var marker := markers[k] as ColorRect
		marker.color = MARKER_ON if k < _rounds_won[i] else MARKER_OFF


func _wait(seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()
