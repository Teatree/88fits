## Plays sounds by id from the Registry sound map with voice limits, and runs layered music.
extends Node

const MAX_PLAYERS := 32
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

var _players: Array = []
var _last_played: Dictionary = {}   # id -> Array of msec timestamps
var _music: Dictionary = {}          # id -> AudioStreamPlayer
var _listener_pos := Vector3.ZERO
var _music_layers: Array = []


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

func play_music(ids: Array, active_layers: int = 1) -> void:
	## Starts every layer at once so they stay in sync; only the first `active_layers` are audible.
	stop_music()
	_music_layers = ids.duplicate()
	for i in range(ids.size()):
		var id: String = ids[i]
		var row := Registry.soundmap.entry(id)
		var stream: AudioStream = row.get("stream") if not row.is_empty() else null
		if stream == null:
			continue
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.mix_rate * stream.get_length())
		var p := AudioStreamPlayer.new()
		p.bus = MUSIC_BUS
		p.stream = stream
		p.volume_db = float(row.get("volume_db", 0.0)) if i < active_layers else -60.0
		add_child(p)
		p.play()
		_music[id] = p


func set_music_layers(active_layers: int) -> void:
	for i in range(_music_layers.size()):
		var p: AudioStreamPlayer = _music.get(_music_layers[i])
		if p == null:
			continue
		var target := float(Registry.soundmap.entry(_music_layers[i]).get("volume_db", 0.0)) if i < active_layers else -60.0
		var tw := create_tween()
		tw.tween_property(p, "volume_db", target, 1.5)


func stop_music() -> void:
	for p in _music.values():
		p.stop()
		p.queue_free()
	_music.clear()
	_music_layers.clear()


func pause_all(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused
	for p in _music.values():
		p.stream_paused = paused
