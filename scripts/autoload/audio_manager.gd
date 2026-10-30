extends Node
## Autoload: music and interface sounds (GDD Section IV, feedback for every
## loop action). Fighters play their own sounds through AudioStreamPlayer2D.

const MUSIC := {
	&"menu": preload("res://assets/audio/music/menu_theme.wav"),
	&"ancient_arena": preload("res://assets/audio/music/ancient_arena.wav"),
	&"battlefield": preload("res://assets/audio/music/battlefield.wav"),
	&"mythic_summit": preload("res://assets/audio/music/mythic_summit.wav"),
}

const SFX := {
	&"ui_move": preload("res://assets/audio/sfx/ui_move.wav"),
	&"ui_confirm": preload("res://assets/audio/sfx/ui_confirm.wav"),
	&"ui_back": preload("res://assets/audio/sfx/ui_back.wav"),
	&"intro": preload("res://assets/audio/sfx/intro.wav"),
	&"round": preload("res://assets/audio/sfx/round.wav"),
	&"fight": preload("res://assets/audio/sfx/fight.wav"),
	&"ko": preload("res://assets/audio/sfx/ko.wav"),
	&"time_up": preload("res://assets/audio/sfx/time_up.wav"),
	&"timer_tick": preload("res://assets/audio/sfx/timer_tick.wav"),
	&"special_ready": preload("res://assets/audio/sfx/special_ready.wav"),
	&"win": preload("res://assets/audio/sfx/win.wav"),
	&"lose": preload("res://assets/audio/sfx/lose.wav"),
}

const SFX_VOICES := 8

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music_key: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.volume_db = -9.0
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		add_child(player)
		_sfx_players.append(player)


func play_music(key: StringName) -> void:
	if key == _music_key and _music_player.playing:
		return
	if not MUSIC.has(key):
		return
	_music_key = key
	_music_player.stream = MUSIC[key]
	_music_player.play()


func play_sfx(key: StringName, volume_db: float = 0.0) -> void:
	if not SFX.has(key):
		return
	var player := _sfx_players[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx_players.size()
	player.stream = SFX[key]
	player.volume_db = volume_db
	player.play()


func _on_music_finished() -> void:
	# WAV files import without looping, so restart the track by hand.
	_music_player.play()
