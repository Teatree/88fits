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
var _chain: Dictionary = {}          # id or chain_group -> [msec the step was first played, step] (pass 65: chain_step; pass 67: ladder)
var _last_any: Dictionary = {}       # id -> msec of the last play (pass 65: min_gap)
var _loops: Dictionary = {}          # id -> AudioStreamPlayer of a running loop (pass 65: play_loop)


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
	# pass 77 (lane SIMRUN): the run sim's fast mode plays nothing (its gaps on real time and its pitch dice would also
	# make a headless run's random sequence hang on the machine's speed)
	if Run.sim_mode:
		return
	var row := Registry.soundmap.entry(id)
	if row.is_empty():
		return
	var stream: AudioStream = row.get("stream")
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if row.has("min_gap") and _last_any.has(id) and now - int(_last_any[id]) < int(float(row["min_gap"]) * 1000.0):
		return
	var voices: int = max(int(row.get("voices", 4)), 1)
	var stamps: Array = _last_played.get(id, [])
	stamps = stamps.filter(func(t): return now - t < 400)
	if stamps.size() >= voices:
		return
	stamps.append(now)
	_last_played[id] = stamps
	_last_any[id] = now
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
	p.pitch_scale = (1.0 + randf_range(-spread, spread)) * chain_pitch(id, row, now)
	p.play()


## The pitch factor of a quick repeat (pass 65, the VS gem "ding" climbing while gems pour in): a row with `chain_step`
## (semitones) rises that much per play that comes within `chain_window` s (default 0.35) of the one before, at most
## `chain_max` steps (default 8), and starts again from 1.0 after a pause. 1.0 for every other row.
## Pass 67, the gem tune: a row with a `ladder` (an Array of semitone offsets, a scale) plays ladder[n] at step n in
## place of step x n (the ladder's last step is the top, or `chain_max` when that is lower); `chain_group` names a
## counter the rows of one family share (the three gem sizes climb one tune); a play less than `chain_min_ms` after the
## step's first play repeats the step instead of taking the next (several gems landing in one tick play one note);
## `chain_end` says what the top does: "hold" (default, stays on the top note) or "wrap" (back to the first, climbing
## again). The counter runs on Time.get_ticks_msec, so it keeps going through a pause and starts again after a long one.
func chain_pitch(id: String, row: Dictionary, now: int) -> float:
	var ladder: Array = row["ladder"] if row.get("ladder") is Array else []
	var step := float(row.get("chain_step", 0.0))
	if ladder.is_empty() and step <= 0.0:
		return 1.0
	var win := int(float(row.get("chain_window", 0.35)) * 1000.0)
	var key := str(row.get("chain_group", id))
	var c: Array = _chain.get(key, [-100000, 0])
	var since := now - int(c[0])
	var min_ms := int(float(row.get("chain_min_ms", 0.0)))
	var reuse := min_ms > 0 and since < min_ms
	var n: int = int(c[1]) if reuse else (int(c[1]) + 1 if since <= win else 0)
	var top := int(row.get("chain_max", 8.0))
	if not ladder.is_empty():
		top = ladder.size() - 1
		if row.has("chain_max"):
			top = mini(top, int(row["chain_max"]))
	if n > top:
		n = 0 if str(row.get("chain_end", "hold")) == "wrap" else top
	if not reuse:
		_chain[key] = [now, n]
	if ladder.is_empty():
		return pow(2.0, step * float(n) / 12.0)
	return pow(2.0, float(ladder[clampi(n, 0, ladder.size() - 1)]) / 12.0)


## A looping sound by id (pass 65: the slot reel's spin) on its own player, until stop_loop; a second call while it runs
## only sets the pitch. Returns the player (null when the id has no stream).
func play_loop(id: String, pitch := 1.0) -> AudioStreamPlayer:
	if _loops.has(id) and is_instance_valid(_loops[id]):
		var q: AudioStreamPlayer = _loops[id]
		q.pitch_scale = maxf(pitch, 0.05)
		return q
	var row := Registry.soundmap.entry(id)
	var stream: AudioStream = row.get("stream") if not row.is_empty() else null
	if stream == null:
		return null
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.mix_rate * stream.get_length()))
	var p := AudioStreamPlayer.new()
	p.bus = SFX_BUS
	p.stream = stream
	p.volume_db = float(row.get("volume_db", 0.0))
	p.pitch_scale = maxf(pitch, 0.05)
	add_child(p)
	p.play()
	_loops[id] = p
	return p


## The pitch of a running loop (no-op when it is not running).
func set_loop_pitch(id: String, pitch: float) -> void:
	if _loops.has(id) and is_instance_valid(_loops[id]):
		(_loops[id] as AudioStreamPlayer).pitch_scale = maxf(pitch, 0.05)


## Whether loop `id` runs.
func loop_playing(id: String) -> bool:
	return _loops.has(id) and is_instance_valid(_loops[id])


## Stops loop `id` (safe to call when it is not running).
func stop_loop(id: String) -> void:
	if _loops.has(id):
		var p = _loops[id]
		_loops.erase(id)
		if is_instance_valid(p):
			(p as AudioStreamPlayer).stop()
			(p as AudioStreamPlayer).queue_free()


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


## Pass 106 (lane DRUM, the War Drum's moment: "everything stops, including music"): every one-shot playing now stops
## (the loops a weapon keeps hold with the paused run and go on after it).
func stop_effects() -> void:
	for p in _players:
		if p.playing:
			p.stop()


## The music held where it is (on) and given back from there (off): its stream paused, its position kept.
func hold_music(on: bool) -> void:
	for p in _music.values():
		(p as AudioStreamPlayer).stream_paused = on


## Where the track playing is, in seconds (-1 with none; tests: the moment gives the music back where it stopped).
func music_position() -> float:
	if not _music.has(_music_now):
		return -1.0
	return (_music[_music_now] as AudioStreamPlayer).get_playback_position()
