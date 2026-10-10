## Plays sounds by id from the Registry sound map with voice limits, and runs the music: one looping track at a time,
## crossfaded. A run's music is the map's list of stage tracks (pass 64: each stage its own track, the boss's over
## them while a boss lives); the menus play one track each.
extends Node

const MAX_PLAYERS := 32
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
## seconds of crossfade when the run's music changes track (a new stage, a boss arriving or dying)
const MUSIC_FADE := 1.5
const MUSIC_SILENT_DB := -60.0

var _players: Array = []
var _last_played: Dictionary = {}   # id -> Array of msec timestamps
var _music: Dictionary = {}          # id -> AudioStreamPlayer (the track playing; one fading out may sit beside it)
var _listener_pos := Vector3.ZERO
var _music_layers: Array = []        # the ids play_music was given (the run's stage tracks, or a menu's one)
var _music_now := ""                 # the id playing
var _music_stage := 0
var _music_boss := false


func _ready() -> void:
	_ensure_bus(SFX_BUS)
	_ensure_bus(MUSIC_BUS)
	for i in range(MAX_PLAYERS):
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
	Settings.changed.connect(_apply_volumes)
	_apply_volumes()


func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, name)


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(clamp(Settings.sfx_volume, 0.0001, 1.0)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(clamp(Settings.music_volume, 0.0001, 1.0)))


func set_listener(pos: Vector3) -> void:
	_listener_pos = pos


## Play a one-shot by id. `pos` attenuates by distance from the listener; Vector3.INF = UI/non-positional.
func play(id: String, pos: Vector3 = Vector3.INF, volume_db: float = 0.0) -> void:
	var row := Registry.soundmap.entry(id)
	if row.is_empty():
		return
	var stream: AudioStream = row.get("stream")
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	var voices: int = max(int(row.get("voices", 4)), 1)
	var stamps: Array = _last_played.get(id, [])
	stamps = stamps.filter(func(t): return now - t < 400)
	if stamps.size() >= voices:
		return
	stamps.append(now)
	_last_played[id] = stamps
	var att := 0.0
	if pos != Vector3.INF:
		var d := _listener_pos.distance_to(pos)
		att = -clamp((d - 8.0) * 1.2, 0.0, 30.0)
		if att <= -30.0:
			return
	var p := _free_player()
	if p == null:
		return
	p.stream = stream
	p.volume_db = float(row.get("volume_db", 0.0)) + volume_db + att
	var spread := float(row.get("pitch_spread", 0.05))
	p.pitch_scale = 1.0 + randf_range(-spread, spread)
	p.play()


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null


# ---------------------------------------------------------------- music

## Starts the first of `ids` (a menu's track, or stage 1's of the run's list). Pass 64: the run's list is one track per
## stage (music_stage moves along it), no longer layers of one piece played together; `active_layers` > 1 starts on
## that stage's track instead.
func play_music(ids: Array, active_layers: int = 1) -> void:
	stop_music()
	_music_layers = ids.duplicate()
	_music_stage = clampi(active_layers - 1, 0, maxi(ids.size() - 1, 0))
	_music_boss = false
	if not ids.is_empty():
		_switch_music(str(ids[_music_stage]), 0.0)


## The run's track for a stage (0-based; endless stays on the last), crossfaded; held under a boss's track until the
## boss dies. Game calls it on WaveDirector.stage_started; does nothing while a menu's single track plays.
func music_stage(stage: int) -> void:
	if _music_layers.size() <= 1:
		return
	_music_stage = clampi(stage, 0, _music_layers.size() - 1)
	if not _music_boss:
		_switch_music(str(_music_layers[_music_stage]), MUSIC_FADE)


## A boss's track over the run's music while it lives (Game: WaveDirector.boss_started on, EnemyManager.boss_died off).
func music_boss(on: bool, id: String = "mu_boss") -> void:
	if _music_layers.is_empty():
		return
	_music_boss = on
	_switch_music(id if on else str(_music_layers[_music_stage]), MUSIC_FADE)


## The id of the track playing ("" for none).
func music_now() -> String:
	return _music_now


## Kept for old callers: the n-th layer is now the n-th stage's track.
func set_music_layers(active_layers: int) -> void:
	music_stage(active_layers - 1)


func _switch_music(id: String, fade: float) -> void:
	if id == _music_now and _music.has(id):
		return
	var row := Registry.soundmap.entry(id)
	var stream: AudioStream = row.get("stream") if not row.is_empty() else null
	if stream == null:
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.mix_rate * stream.get_length()))
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	for old_id in _music.keys():
		var op: AudioStreamPlayer = _music[old_id]
		_music.erase(old_id)
		if fade <= 0.0 or not is_inside_tree():
			op.stop()
			op.queue_free()
			continue
		var tw := op.create_tween()
		tw.tween_property(op, "volume_db", MUSIC_SILENT_DB, fade)
		tw.tween_callback(op.queue_free)
	var target := float(row.get("volume_db", 0.0))
	var p := AudioStreamPlayer.new()
	p.bus = MUSIC_BUS
	p.stream = stream
	p.volume_db = target if fade <= 0.0 else MUSIC_SILENT_DB
	add_child(p)
	p.play()
	if fade > 0.0:
		p.create_tween().tween_property(p, "volume_db", target, fade)
	_music[id] = p
	_music_now = id


func stop_music() -> void:
	for p in _music.values():
		p.stop()
		p.queue_free()
	_music.clear()
	_music_layers.clear()
	_music_now = ""
	_music_boss = false


func pause_all(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused
	for p in _music.values():
		p.stream_paused = paused
