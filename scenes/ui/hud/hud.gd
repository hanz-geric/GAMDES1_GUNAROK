class_name Hud
extends CanvasLayer
## Fixed HUD on its own CanvasLayer. Reacts only to simulation signals/events
## and never mutates fight state (Design Plan v3 Section 13.3).
## Includes skill cooldown badges, live combo counters, counter-hit callouts,
## and the 0.90 s Ultimate side cut-in (Section 8).

const BAR_WIDTH := 400.0
const P1_COLOR := Color(0.35, 0.75, 1.0)
const P2_COLOR := Color(1.0, 0.55, 0.2)
const HEALTH_COLOR := Color(0.95, 0.82, 0.25)
const HEALTH_LOW_COLOR := Color(0.95, 0.3, 0.2)
const METER_COLOR := Color(0.4, 0.8, 1.0)
const METER_READY_COLOR := Color(1.0, 0.9, 0.35)
const MARKER_OFF := Color(0.2, 0.2, 0.24)
const MARKER_ON := Color(1.0, 0.82, 0.3)
const SKILL_READY_BG := Color(0.14, 0.24, 0.34, 0.92)
const SKILL_COOL_BG := Color(0.12, 0.11, 0.15, 0.88)
const SKILL_SLOTS := [
	{"key": &"skill_ground", "tag": "G"},
	{"key": &"skill_forward", "tag": "F"},
	{"key": &"skill_back", "tag": "B"},
	{"key": &"skill_air", "tag": "A"},
	{"key": &"skill_low", "tag": "L"},
]

var _rounds_won := [0, 0]
var _max_health := [100.0, 100.0]
var _meter_ready := [false, false]
var _meter_tweens: Array = [null, null]
var _timer_tween: Tween
var _announce_serial := 0
var _callout_serial := 0
var _combo_serial := [0, 0]
var _cooldown_panels: Array = [{}, {}]
var _cooldown_labels: Array = [{}, {}]
var _combo_labels: Array[Label] = []
var _move_labels: Array[Label] = []
var _move_serial := [0, 0]
var _health_bgs: Array[NinePatchRect] = []
var _health_trails: Array[ColorRect] = []
var _trail_tweens: Array = [null, null]
var _rage_labels: Array[Label] = []
var _screen_flash: ColorRect
var _flash_tween: Tween

# Ultimate cinema cut-in overlay nodes (supports Single AND Dual Ultimate Clash!)
var _cutin_root: Control
var _cutin_dim: ColorRect
var _letterbox_top: ColorRect
var _letterbox_bot: ColorRect
var _cutin_panels: Array[Control] = []
var _cutin_bands: Array[Polygon2D] = []
var _cutin_glows: Array[ColorRect] = []
var _cutin_top_rails: Array[Polygon2D] = []
var _cutin_bot_rails: Array[Polygon2D] = []
var _cutin_speed_lines: Array = [[], []]
var _cutin_portraits: Array[TextureRect] = []
var _cutin_titles: Array[Label] = []
var _cutin_tags: Array[Label] = []
var _cutin_clash_divider: Polygon2D
var _cutin_clash_label: Label
var _cutin_fx: CutinFxLayer
var _cutin_tween: Tween
var _letterbox_tween: Tween

@onready var root: Control = $Root
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
		_build_cooldown_icons(i)
		_build_combo_label(i)
		_build_health_trail_and_rage(i)
	_build_screen_flash()
	_build_cutin_overlay()


func _exit_tree() -> void:
	if GameState.match_started.is_connected(_on_match_started):
		GameState.match_started.disconnect(_on_match_started)


func _on_match_started(_stage: StringName, p1: WarriorData, opponent: WarriorData) -> void:
	_rounds_won = [0, 0]
	_max_health = [float(p1.max_health), float(GameState.opponent_max_health())]
	for i in 2:
		var bar: TextureProgressBar = health_bars[i]
		bar.max_value = _max_health[i]
		bar.value = _max_health[i]
		_update_markers(i)
		_combo_labels[i].visible = false
		_rage_labels[i].visible = false
	var p2_bar: TextureProgressBar = health_bars[1]
	var width := BAR_WIDTH * clampf(_max_health[1] / 100.0, 1.0, 1.35)
	p2_bar.offset_left = p2_bar.offset_right - width
	_health_bgs[1].offset_left = p2_bar.offset_left
	_health_bgs[1].offset_right = p2_bar.offset_right
	for i in 2:
		_sync_health_trail_immediate(i, _max_health[i])
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


func _on_round_started(round_no: int) -> void:
	_reset_timer_label()
	for lbl in _combo_labels:
		lbl.visible = false
	_announce("ROUND %d" % round_no, "", 0.85, &"round")
	await _wait(0.85)
	_announce("FIGHT!", "", 0.75, &"fight")


func _on_health_changed(fighter: Fighter, value: float) -> void:
	var i := fighter.player_index - 1
	var bar: TextureProgressBar = health_bars[i]
	var prev := bar.value
	bar.value = value
	var max_value: float = _max_health[i]
	var low := value > 0.0 and value <= max_value * 0.25
	bar.tint_progress = HEALTH_LOW_COLOR if low else HEALTH_COLOR
	_rage_labels[i].visible = low
	if value >= prev:
		_sync_health_trail_immediate(i, value)
	else:
		_animate_health_trail(i, value)


func flash_screen(color: Color, max_alpha: float = 0.30) -> void:
	if _screen_flash == null:
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_screen_flash.color = Color(color.r, color.g, color.b, max_alpha)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_screen_flash, "color:a", 0.0, 0.22)


func _on_meter_changed(fighter: Fighter, value: float) -> void:
	var i := fighter.player_index - 1
	var bar: TextureProgressBar = meter_bars[i]
	bar.value = value
	var is_ready := value >= Balance.ULTIMATE_COST
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


func _on_cooldowns_changed(fighter: Fighter, cooldowns: Dictionary) -> void:
	var i := fighter.player_index - 1
	var panels: Dictionary = _cooldown_panels[i]
	var labels: Dictionary = _cooldown_labels[i]
	for slot in SKILL_SLOTS:
		var key: StringName = slot["key"]
		var tag: String = slot["tag"]
		var frames: int = int(cooldowns.get(key, 0))
		var panel: ColorRect = panels[key]
		var label: Label = labels[key]
		if frames <= 0:
			panel.color = SKILL_READY_BG
			label.text = tag
			label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
		else:
			var secs := ceili(float(frames) / float(Balance.TICK_RATE))
			panel.color = SKILL_COOL_BG
			label.text = "%s %d" % [tag, secs]
			label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))


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


func _on_hit_landed(attacker: Fighter, defender: Fighter, _damage: float, blocked: bool, move_name: StringName, is_counter: bool, combo_count: int) -> void:
	var bar: TextureProgressBar = health_bars[defender.player_index - 1]
	bar.modulate = Color(1.0, 0.45, 0.45) if not blocked else Color(0.6, 0.85, 1.0)
	var tween := create_tween()
	tween.tween_property(bar, "modulate", Color.WHITE, 0.25)
	if not blocked:
		if combo_count >= 2:
			_show_combo(attacker.player_index - 1, combo_count)
		if is_counter:
			_show_callout("COUNTER!", 0.55, Color(1.0, 0.55, 0.2))
		elif move_name == &"ultimate":
			_show_callout(attacker.data.special_name.to_upper() + "!", 0.85, Color(1.0, 0.9, 0.35))


func _on_parry_landed(defender: Fighter, _attacker: Fighter) -> void:
	var bar: TextureProgressBar = meter_bars[defender.player_index - 1]
	bar.modulate = Color(1.3, 1.2, 0.4)
	var tween := create_tween()
	tween.tween_property(bar, "modulate", Color.WHITE, 0.25)
	_show_callout("PARRY!", 0.55, Color(1.0, 0.92, 0.35))


func _on_seize_teched(_attacker: Fighter, _defender: Fighter) -> void:
	_show_callout("TECH!", 0.55, Color(0.55, 0.9, 1.0))


func _on_burst_triggered(_defender: Fighter, _attacker: Fighter) -> void:
	_show_callout("BURST ESCAPE!", 0.65, Color(1.0, 0.92, 0.35))


func show_sniper_callout(text: String) -> void:
	_show_callout(text, 0.65, Color(0.75, 0.96, 1.0))


func show_guard_crush_callout() -> void:
	_show_callout("GUARD CRUSH!", 0.65, Color(1.0, 0.45, 0.18))


func show_move_name(fighter: Fighter, label_text: String) -> void:
	var i := fighter.player_index - 1
	if i < 0 or i >= _move_labels.size():
		return
	_move_serial[i] += 1
	var serial: int = _move_serial[i]
	var lbl := _move_labels[i]
	lbl.text = label_text
	lbl.visible = true
	lbl.modulate.a = 1.0
	lbl.scale = Vector2(1.25, 1.25)
	var tw := create_tween()
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.20)
	tw.tween_callback(func() -> void:
		if serial == _move_serial[i]:
			lbl.visible = false
	)


func _show_combo(attacker_idx: int, count: int) -> void:
	_combo_serial[attacker_idx] += 1
	var serial: int = _combo_serial[attacker_idx]
	var lbl := _combo_labels[attacker_idx]
	var tag := ""
	if count >= 5:
		tag = "\nGODLIKE!"
	elif count >= 4:
		tag = "\nSUPER!"
	elif count >= 3:
		tag = "\nGREAT!"
	lbl.text = "%d HITS!%s" % [count, tag]
	lbl.visible = true
	lbl.modulate.a = 1.0
	lbl.scale = Vector2(1.45, 1.45)
	var tw := create_tween()
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.95)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		if serial == _combo_serial[attacker_idx]:
			lbl.visible = false
	)


func _show_callout(text: String, duration: float, color: Color = Color.WHITE) -> void:
	if announcer.visible:
		return
	_callout_serial += 1
	var serial := _callout_serial
	sub_announcer.text = text
	sub_announcer.add_theme_color_override("font_color", color)
	sub_announcer.visible = true
	var callout := create_tween()
	callout.tween_interval(duration)
	callout.tween_callback(func() -> void:
		if serial == _callout_serial and not announcer.visible:
			sub_announcer.visible = false
	)


# --- Ultimate Cinema Cut-In (Single & Simultaneous Dual Clash!) ------------

func _configure_cutin_slot(slot: int, fighter: Fighter, dual: bool) -> void:
	var is_left := (slot == 0)
	var accent := fighter.data.accent_color
	var dark_band := fighter.data.primary_color.darkened(0.55)
	if dark_band.get_luminance() < 0.08:
		dark_band = Color(0.10, 0.12, 0.22)

	var band := _cutin_bands[slot]
	var top_rail := _cutin_top_rails[slot]
	var bot_rail := _cutin_bot_rails[slot]
	var portrait := _cutin_portraits[slot]
	var title := _cutin_titles[slot]
	var tag := _cutin_tags[slot]

	band.color = Color(dark_band.r, dark_band.g, dark_band.b, 0.96)
	_cutin_glows[slot].color = Color(accent.r, accent.g, accent.b, 0.16)
	top_rail.color = Color(accent.r, accent.g, accent.b, 1.0)
	bot_rail.color = Color(accent.r, accent.g, accent.b, 1.0)
	for line in _cutin_speed_lines[slot]:
		(line as ColorRect).visible = false

	if fighter.data.cutin_texture != null:
		portrait.texture = fighter.data.cutin_texture
		portrait.visible = true
	elif fighter.data.sprite_frames != null and fighter.data.sprite_frames.has_animation(&"idle"):
		portrait.texture = fighter.data.sprite_frames.get_frame_texture(&"idle", 0)
		portrait.visible = true
	else:
		portrait.visible = false
	portrait.flip_h = not is_left
	portrait.scale = Vector2.ONE

	title.text = fighter.data.special_name.to_upper() + "!"
	tag.text = "%s  •  %s" % [fighter.data.display_name.to_upper(), fighter.data.homeland.to_upper()]

	# Clean cinema-strip polygon (clip_children clips any bottom waist seam flush with the rail!).
	if dual:
		if is_left:
			band.polygon = PackedVector2Array([Vector2(0, 175), Vector2(675, 175), Vector2(605, 515), Vector2(0, 515)])
			top_rail.polygon = PackedVector2Array([Vector2(0, 166), Vector2(678, 166), Vector2(674, 179), Vector2(0, 179)])
			bot_rail.polygon = PackedVector2Array([Vector2(0, 511), Vector2(608, 511), Vector2(604, 524), Vector2(0, 524)])
			portrait.size = Vector2(540, 385)
			portrait.position = Vector2(20, 145)
			portrait.pivot_offset = Vector2(270, 260)
			title.size = Vector2(560, 56)
			title.position = Vector2(28, 424)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			tag.size = Vector2(560, 26)
			tag.position = Vector2(30, 478)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			band.polygon = PackedVector2Array([Vector2(68, 175), Vector2(760, 175), Vector2(760, 515), Vector2(0, 515)])
			top_rail.polygon = PackedVector2Array([Vector2(66, 166), Vector2(760, 166), Vector2(760, 179), Vector2(62, 179)])
			bot_rail.polygon = PackedVector2Array([Vector2(0, 511), Vector2(760, 511), Vector2(760, 524), Vector2(-4, 524)])
			portrait.size = Vector2(540, 385)
			portrait.position = Vector2(180, 145)
			portrait.pivot_offset = Vector2(270, 260)
			title.size = Vector2(560, 56)
			title.position = Vector2(168, 424)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.size = Vector2(560, 26)
			tag.position = Vector2(168, 478)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		# Sleek widescreen cinema bar — flush bottom edge so portrait NEVER looks chopped floating in air!
		if is_left:
			band.polygon = PackedVector2Array([Vector2(0, 175), Vector2(880, 175), Vector2(780, 515), Vector2(0, 515)])
			top_rail.polygon = PackedVector2Array([Vector2(0, 166), Vector2(885, 166), Vector2(880, 179), Vector2(0, 179)])
			bot_rail.polygon = PackedVector2Array([Vector2(0, 511), Vector2(785, 511), Vector2(779, 524), Vector2(0, 524)])
			portrait.size = Vector2(590, 415)
			portrait.position = Vector2(40, 118)
			portrait.pivot_offset = Vector2(295, 290)
			title.size = Vector2(720, 62)
			title.position = Vector2(44, 420)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			tag.size = Vector2(720, 28)
			tag.position = Vector2(46, 478)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			band.polygon = PackedVector2Array([Vector2(100, 175), Vector2(900, 175), Vector2(900, 515), Vector2(0, 515)])
			top_rail.polygon = PackedVector2Array([Vector2(96, 166), Vector2(900, 166), Vector2(900, 179), Vector2(92, 179)])
			bot_rail.polygon = PackedVector2Array([Vector2(0, 511), Vector2(900, 511), Vector2(900, 524), Vector2(-5, 524)])
			portrait.size = Vector2(590, 415)
			portrait.position = Vector2(260, 118)
			portrait.pivot_offset = Vector2(295, 290)
			title.size = Vector2(720, 62)
			title.position = Vector2(132, 420)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.size = Vector2(720, 28)
			tag.position = Vector2(132, 478)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _trigger_letterbox(hold_sec: float = 1.45) -> void:
	if _letterbox_tween != null:
		_letterbox_tween.kill()
	_letterbox_top.visible = true
	_letterbox_bot.visible = true
	_letterbox_top.offset_bottom = 0.0
	_letterbox_bot.offset_top = 720.0
	_letterbox_tween = create_tween()
	_letterbox_tween.tween_property(_letterbox_top, "offset_bottom", 62.0, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_letterbox_tween.parallel().tween_property(_letterbox_bot, "offset_top", 658.0, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_letterbox_tween.tween_interval(hold_sec)
	_letterbox_tween.tween_property(_letterbox_top, "offset_bottom", 0.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_letterbox_tween.parallel().tween_property(_letterbox_bot, "offset_top", 720.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_letterbox_tween.tween_callback(func() -> void:
		_letterbox_top.visible = false
		_letterbox_bot.visible = false
	)


func play_ultimate_cutin(fighter: Fighter) -> void:
	if _cutin_tween != null:
		_cutin_tween.kill()
	_trigger_letterbox(1.50)
	var slot := 0 if fighter.player_index == 1 else 1
	var other := 1 - slot
	_configure_cutin_slot(slot, fighter, false)
	_cutin_panels[slot].visible = true
	_cutin_panels[other].visible = false
	_cutin_clash_divider.visible = false
	_cutin_clash_label.visible = false

	var start_x := -940.0 if slot == 0 else 1340.0
	var hold_x := 0.0 if slot == 0 else 380.0
	var exit_x := -940.0 if slot == 0 else 1340.0

	_cutin_root.visible = true
	_cutin_dim.color.a = 0.0
	if _cutin_fx != null:
		_cutin_fx.start_single(slot, fighter.data.accent_color)
	_cutin_panels[slot].position = Vector2(start_x, 0.0)
	_cutin_portraits[slot].scale = Vector2(1.32, 1.32)
	_cutin_titles[slot].scale = Vector2(1.85, 1.85)
	AudioManager.play_sfx(&"special_ready", 3.5)
	flash_screen(Color(1.0, 0.98, 0.92), 0.65)

	_cutin_tween = create_tween()
	_cutin_tween.tween_property(_cutin_dim, "color:a", 0.74, 0.08)
	_cutin_tween.parallel().tween_property(_cutin_panels[slot], "position:x", hold_x, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_portraits[slot], "scale", Vector2(1.04, 1.04), 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_titles[slot], "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Impact shudder right as the panel slams in!
	_cutin_tween.tween_property(_cutin_panels[slot], "position:y", -8.0, 0.03)
	_cutin_tween.tween_property(_cutin_panels[slot], "position:y", 6.0, 0.03)
	_cutin_tween.tween_property(_cutin_panels[slot], "position:y", 0.0, 0.03)
	_cutin_tween.tween_property(_cutin_portraits[slot], "scale", Vector2(1.13, 1.13), 0.45)
	_cutin_tween.tween_property(_cutin_panels[slot], "position:x", exit_x, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_cutin_tween.parallel().tween_property(_cutin_dim, "color:a", 0.0, 0.14)
	_cutin_tween.tween_callback(func() -> void:
		if _cutin_fx != null:
			_cutin_fx.stop_fx()
		_cutin_root.visible = false
	)


func play_dual_ultimate_cutin(f1: Fighter, f2: Fighter) -> void:
	if _cutin_tween != null:
		_cutin_tween.kill()
	_trigger_letterbox(1.80)
	_configure_cutin_slot(0, f1, true)
	_configure_cutin_slot(1, f2, true)
	_cutin_panels[0].visible = true
	_cutin_panels[1].visible = true
	_cutin_clash_divider.visible = false
	_cutin_clash_label.visible = true
	_cutin_clash_label.text = "⚡ ULTIMATE CLASH! ⚡"

	_cutin_root.visible = true
	_cutin_dim.color.a = 0.0
	if _cutin_fx != null:
		_cutin_fx.start_dual(f1.data.accent_color, f2.data.accent_color)
	_cutin_panels[0].position = Vector2(-740.0, 0.0)
	_cutin_panels[1].position = Vector2(1340.0, 0.0)
	_cutin_portraits[0].scale = Vector2(1.30, 1.30)
	_cutin_portraits[1].scale = Vector2(1.30, 1.30)
	_cutin_titles[0].scale = Vector2(1.75, 1.75)
	_cutin_titles[1].scale = Vector2(1.75, 1.75)
	_cutin_clash_label.scale = Vector2(2.6, 2.6)
	_cutin_clash_label.modulate.a = 0.0
	AudioManager.play_sfx(&"special_ready", 4.5)
	flash_screen(Color(1.0, 0.96, 0.72), 0.80)

	_cutin_tween = create_tween()
	_cutin_tween.tween_property(_cutin_dim, "color:a", 0.82, 0.08)
	_cutin_tween.parallel().tween_property(_cutin_panels[0], "position:x", 0.0, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_panels[1], "position:x", 520.0, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_portraits[0], "scale", Vector2(1.04, 1.04), 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_portraits[1], "scale", Vector2(1.04, 1.04), 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_titles[0], "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_titles[1], "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cutin_tween.parallel().tween_property(_cutin_clash_label, "modulate:a", 1.0, 0.10)
	_cutin_tween.parallel().tween_property(_cutin_clash_label, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Violent clash impact vibration!
	_cutin_tween.tween_property(_cutin_panels[0], "position:y", -10.0, 0.03)
	_cutin_tween.parallel().tween_property(_cutin_panels[1], "position:y", 10.0, 0.03)
	_cutin_tween.tween_property(_cutin_panels[0], "position:y", 7.0, 0.03)
	_cutin_tween.parallel().tween_property(_cutin_panels[1], "position:y", -7.0, 0.03)
	_cutin_tween.tween_property(_cutin_panels[0], "position:y", 0.0, 0.03)
	_cutin_tween.parallel().tween_property(_cutin_panels[1], "position:y", 0.0, 0.03)
	# Intense rival stare-down push-in!
	_cutin_tween.tween_property(_cutin_portraits[0], "scale", Vector2(1.15, 1.15), 0.52)
	_cutin_tween.parallel().tween_property(_cutin_portraits[1], "scale", Vector2(1.15, 1.15), 0.52)
	_cutin_tween.parallel().tween_property(_cutin_clash_label, "scale", Vector2(1.10, 1.10), 0.52)
	_cutin_tween.tween_property(_cutin_panels[0], "position:x", -740.0, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_cutin_tween.parallel().tween_property(_cutin_panels[1], "position:x", 1340.0, 0.14).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_cutin_tween.parallel().tween_property(_cutin_clash_label, "modulate:a", 0.0, 0.12)
	_cutin_tween.parallel().tween_property(_cutin_dim, "color:a", 0.0, 0.14)
	_cutin_tween.tween_callback(func() -> void:
		if _cutin_fx != null:
			_cutin_fx.stop_fx()
		_cutin_root.visible = false
	)


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
	sub_announcer.add_theme_color_override("font_color", Color.WHITE)
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


func _build_cooldown_icons(i: int) -> void:
	var box := HBoxContainer.new()
	box.name = "SkillCooldowns%d" % (i + 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	box.offset_top = 138.0
	box.offset_bottom = 162.0
	if i == 0:
		box.offset_left = 30.0
		box.offset_right = 310.0
	else:
		box.offset_left = 970.0
		box.offset_right = 1250.0
		box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(box)

	var panels: Dictionary = _cooldown_panels[i]
	var labels: Dictionary = _cooldown_labels[i]
	for slot in SKILL_SLOTS:
		var key: StringName = slot["key"]
		var tag: String = slot["tag"]
		var panel := ColorRect.new()
		panel.custom_minimum_size = Vector2(40.0, 22.0)
		panel.color = SKILL_READY_BG
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(panel)

		var label := Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06, 1.0))
		label.add_theme_constant_override("outline_size", 3)
		label.text = tag
		panel.add_child(label)

		panels[key] = panel
		labels[key] = label


func _build_combo_label(i: int) -> void:
	var lbl := Label.new()
	lbl.name = "ComboLabel%d" % (i + 1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible = false
	lbl.offset_top = 178.0
	lbl.offset_bottom = 264.0
	if i == 0:
		lbl.offset_left = 32.0
		lbl.offset_right = 340.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		lbl.offset_left = 940.0
		lbl.offset_right = 1248.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.pivot_offset = Vector2(154.0, 32.0)
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.05, 1.0))
	lbl.add_theme_constant_override("outline_size", 10)
	root.add_child(lbl)
	_combo_labels.append(lbl)

	var mv := Label.new()
	mv.name = "MoveLabel%d" % (i + 1)
	mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mv.visible = false
	mv.offset_top = 152.0
	mv.offset_bottom = 180.0
	if i == 0:
		mv.offset_left = 32.0
		mv.offset_right = 380.0
		mv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		mv.offset_left = 900.0
		mv.offset_right = 1248.0
		mv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mv.pivot_offset = Vector2(170.0, 14.0)
	mv.add_theme_font_size_override("font_size", 19)
	mv.add_theme_color_override("font_color", Color(0.68, 0.94, 1.0) if i == 0 else Color(1.0, 0.78, 0.48))
	mv.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.06, 1.0))
	mv.add_theme_constant_override("outline_size", 6)
	root.add_child(mv)
	_move_labels.append(mv)


func _build_health_trail_and_rage(i: int) -> void:
	var bar: TextureProgressBar = health_bars[i]
	# Move bar_under texture to a dedicated NinePatchRect behind the red trail so
	# the empty portion of TextureProgressBar reveals the crimson damage chunk!
	var bg := NinePatchRect.new()
	bg.name = "HealthBarBg%d" % (i + 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture = bar.texture_under
	bg.patch_margin_left = bar.stretch_margin_left
	bg.patch_margin_top = bar.stretch_margin_top
	bg.patch_margin_right = bar.stretch_margin_right
	bg.patch_margin_bottom = bar.stretch_margin_bottom
	bg.offset_left = bar.offset_left
	bg.offset_top = bar.offset_top
	bg.offset_right = bar.offset_right
	bg.offset_bottom = bar.offset_bottom
	bar.texture_under = null
	root.add_child(bg)
	root.move_child(bg, bar.get_index())
	_health_bgs.append(bg)

	var trail := ColorRect.new()
	trail.name = "HealthTrail%d" % (i + 1)
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail.color = Color(0.95, 0.22, 0.18, 0.94)
	trail.offset_top = bar.offset_top + 4.0
	trail.offset_bottom = bar.offset_bottom - 4.0
	trail.offset_left = bar.offset_left + 4.0
	trail.offset_right = bar.offset_right - 4.0
	root.add_child(trail)
	root.move_child(trail, bar.get_index())
	_health_trails.append(trail)

	var rage := Label.new()
	rage.name = "RageLabel%d" % (i + 1)
	rage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rage.visible = false
	rage.text = "RAGE! +12% DMG"
	rage.offset_top = 92.0
	rage.offset_bottom = 112.0
	if i == 0:
		rage.offset_left = 190.0
		rage.offset_right = 400.0
		rage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		rage.offset_left = 880.0
		rage.offset_right = 1090.0
		rage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rage.add_theme_font_size_override("font_size", 15)
	rage.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	rage.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.04, 1.0))
	rage.add_theme_constant_override("outline_size", 5)
	root.add_child(rage)
	_rage_labels.append(rage)


func _sync_health_trail_immediate(i: int, value: float) -> void:
	var old_tw: Tween = _trail_tweens[i]
	if old_tw != null:
		old_tw.kill()
		_trail_tweens[i] = null
	var bar: TextureProgressBar = health_bars[i]
	var trail := _health_trails[i]
	var ratio := clampf(value / maxf(_max_health[i], 1.0), 0.0, 1.0)
	var inner_w := (bar.offset_right - bar.offset_left) - 8.0
	if i == 0:
		trail.offset_left = bar.offset_left + 4.0
		trail.offset_right = trail.offset_left + inner_w * ratio
	else:
		trail.offset_right = bar.offset_right - 4.0
		trail.offset_left = trail.offset_right - inner_w * ratio


func _animate_health_trail(i: int, value: float) -> void:
	var old_tw: Tween = _trail_tweens[i]
	if old_tw != null:
		old_tw.kill()
	var bar: TextureProgressBar = health_bars[i]
	var trail := _health_trails[i]
	var ratio := clampf(value / maxf(_max_health[i], 1.0), 0.0, 1.0)
	var inner_w := (bar.offset_right - bar.offset_left) - 8.0
	var tw := create_tween()
	tw.tween_interval(0.28)
	if i == 0:
		tw.tween_property(trail, "offset_right", bar.offset_left + 4.0 + inner_w * ratio, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(trail, "offset_left", bar.offset_right - 4.0 - inner_w * ratio, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_trail_tweens[i] = tw


func _build_screen_flash() -> void:
	_screen_flash = ColorRect.new()
	_screen_flash.name = "ScreenFlash"
	_screen_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	root.add_child(_screen_flash)


func _build_cutin_overlay() -> void:
	# Cinematic widescreen black letterbox bars for Ultimate cutscenes!
	_letterbox_top = ColorRect.new()
	_letterbox_top.name = "LetterboxTop"
	_letterbox_top.offset_left = 0.0
	_letterbox_top.offset_right = 1280.0
	_letterbox_top.offset_top = 0.0
	_letterbox_top.offset_bottom = 0.0
	_letterbox_top.color = Color(0.02, 0.02, 0.04, 0.96)
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letterbox_top.visible = false
	root.add_child(_letterbox_top)

	_letterbox_bot = ColorRect.new()
	_letterbox_bot.name = "LetterboxBot"
	_letterbox_bot.offset_left = 0.0
	_letterbox_bot.offset_right = 1280.0
	_letterbox_bot.offset_top = 720.0
	_letterbox_bot.offset_bottom = 720.0
	_letterbox_bot.color = Color(0.02, 0.02, 0.04, 0.96)
	_letterbox_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letterbox_bot.visible = false
	root.add_child(_letterbox_bot)

	_cutin_root = Control.new()
	_cutin_root.name = "UltimateCutIn"
	_cutin_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cutin_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutin_root.visible = false
	root.add_child(_cutin_root)

	_cutin_dim = ColorRect.new()
	_cutin_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cutin_dim.color = Color(0.0, 0.0, 0.0, 0.0)
	_cutin_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutin_root.add_child(_cutin_dim)

	for slot in 2:
		var panel := Control.new()
		panel.size = Vector2(900, 720)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cutin_root.add_child(panel)
		_cutin_panels.append(panel)

		var band := Polygon2D.new()
		band.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		panel.add_child(band)
		_cutin_bands.append(band)

		# Luminous energy flare behind the champion portrait
		var glow := ColorRect.new()
		glow.position = Vector2(0, 175)
		glow.size = Vector2(900, 340)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glow_mat := CanvasItemMaterial.new()
		glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = glow_mat
		band.add_child(glow)
		_cutin_glows.append(glow)

		var lines: Array[ColorRect] = []
		for s in 7:
			var line := ColorRect.new()
			line.size = Vector2(820.0 - s * 40.0, 4.0 + (s % 3) * 3.0)
			line.position = Vector2(10.0 + s * 22.0, 196.0 + s * 46.0)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			band.add_child(line)
			lines.append(line)
		_cutin_speed_lines[slot] = lines

		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(portrait)
		_cutin_portraits.append(portrait)

		# Subtle dark bottom banner strip inside the cinema bar so title text pops cleanly!
		var title_shade := ColorRect.new()
		title_shade.position = Vector2(0, 412)
		title_shade.size = Vector2(900, 110)
		title_shade.color = Color(0.03, 0.02, 0.06, 0.68)
		title_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(title_shade)

		var top_rail := Polygon2D.new()
		panel.add_child(top_rail)
		_cutin_top_rails.append(top_rail)

		var bot_rail := Polygon2D.new()
		panel.add_child(bot_rail)
		_cutin_bot_rails.append(bot_rail)

		var title := Label.new()
		title.pivot_offset = Vector2(280, 30)
		title.add_theme_font_size_override("font_size", 42)
		title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.42))
		title.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.05, 1.0))
		title.add_theme_constant_override("outline_size", 12)
		panel.add_child(title)
		_cutin_titles.append(title)

		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 17)
		tag.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
		tag.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.05, 1.0))
		tag.add_theme_constant_override("outline_size", 6)
		panel.add_child(tag)
		_cutin_tags.append(tag)

	# Live 60 FPS procedural anime speed lines, energy halos & crackling lightning fissure!
	_cutin_fx = CutinFxLayer.new()
	_cutin_fx.name = "CutinFxLayer"
	_cutin_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cutin_fx.visible = false
	_cutin_root.add_child(_cutin_fx)

	# Glowing diagonal clash divider (kept hidden in favor of live crackling lightning fissure)
	_cutin_clash_divider = Polygon2D.new()
	_cutin_clash_divider.polygon = PackedVector2Array([
		Vector2(670, 155), Vector2(688, 155), Vector2(616, 535), Vector2(598, 535)
	])
	_cutin_clash_divider.color = Color(1.0, 0.96, 0.55, 1.0)
	_cutin_clash_divider.visible = false
	_cutin_root.add_child(_cutin_clash_divider)

	_cutin_clash_label = Label.new()
	_cutin_clash_label.text = "⚡ ULTIMATE CLASH! ⚡"
	_cutin_clash_label.position = Vector2(260, 96)
	_cutin_clash_label.size = Vector2(760, 68)
	_cutin_clash_label.pivot_offset = Vector2(380, 34)
	_cutin_clash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cutin_clash_label.add_theme_font_size_override("font_size", 50)
	_cutin_clash_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.35))
	_cutin_clash_label.add_theme_color_override("font_outline_color", Color(0.10, 0.02, 0.05, 1.0))
	_cutin_clash_label.add_theme_constant_override("outline_size", 16)
	_cutin_clash_label.visible = false
	_cutin_root.add_child(_cutin_clash_label)


func _wait(seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()
