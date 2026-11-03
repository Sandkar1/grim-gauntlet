extends Node
## Sound manager (autoload "Audio").
##   Audio.play("hit")            one-shot sound effect
##   Audio.music("ambient")       cross-fades to a looping track ("" = silence)

const SFX_DIR := "res://assets/sfx/"
const MUSIC_DIR := "res://assets/music/"
const VOICES := 20

var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for f in DirAccess.get_files_at(SFX_DIR):
		var fname := f.trim_suffix(".import").trim_suffix(".remap")
		if fname.ends_with(".wav"):
			var key := fname.get_basename()
			if not _sfx.has(key):
				_sfx[key] = load(SFX_DIR + fname)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	add_child(_music_a)
	add_child(_music_b)


func play(name: String, volume_db := 0.0, pitch_var := 0.08, pitch := 1.0) -> void:
	var stream: AudioStream = _sfx.get(name)
	if stream == null:
		return
	# Avoid machine-gunning the same sample many times in one frame.
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -1000)) < 35:
		return
	_last_played[name] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = volume_db + linear_to_db(maxf(Game.sfx_volume, 0.001))
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_var, pitch_var))
	p.play()


func music(track: String, fade := 1.5) -> void:
	if track == _current_track:
		return
	_current_track = track
	var old := _music_a if _music_a.playing else _music_b
	var new := _music_b if old == _music_a else _music_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, fade)
		tw.tween_callback(old.stop)
	if track == "":
		return
	var stream = load(MUSIC_DIR + track + ".wav")
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate) - 1
	new.stream = stream
	new.volume_db = -60.0
	new.play()
	var tw2 := create_tween()
	tw2.tween_property(new, "volume_db", music_db(), fade)


func music_db() -> float:
	return linear_to_db(maxf(Game.music_volume, 0.001)) - 4.0


func refresh_music_volume() -> void:
	for p in [_music_a, _music_b]:
		if p.playing:
			p.volume_db = music_db()
