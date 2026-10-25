## Pass 106 lane DRUM's capture (scratch): a real run (Drifter, Red Canyon, god mode), a pack of creatures about, the War
## Drum used beside the hero: the moment frame by frame (`mo_NNN` = NNN/100 s into it: the fade in, the first slap's
## squash and spring, the rim slap, the roll, the big slap with the words, the fade out), then the boost: the hero run
## by a real finger on the stick (`run_NNN`: the red ribbon and streaks, the ring thumping on its beat, the HUD's red
## plate with the seconds) and standing (`stand_NNN`). Windowed at the phone's canvas, at a fixed 60 fps so the moment's
## clock is the frames':
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game --script res://tools/_p106_DRUM_shot.gd -- out=<dir>
extends SceneTree

const MOMENT := [0.05, 0.12, 0.2, 0.3, 0.37, 0.4, 0.45, 0.62, 0.73, 0.86, 1.2, 1.37, 1.57, 1.6, 1.66, 1.75, 1.9, 2.05, 2.15]
const WATCHDOG_S := 90.0
const FRAME_CAP := 4000

var _out := "user://p106_drum"
var g
var _frames: Array = []
var _t0 := 0.0
var _n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec() * 0.001
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_watchdog)


func _watchdog() -> void:
	_n += 1
	if Time.get_ticks_msec() * 0.001 - _t0 > WATCHDOG_S or _n > FRAME_CAP:
		printerr("p106_drum_shot: watchdog (%d frames), quitting" % _n)
		_flush()
		quit(2)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _grab(name: String) -> void:
	await process_frame
	_frames.append([name, root.get_viewport().get_texture().get_image()])


func _flush() -> void:
	for f in _frames:
		(f[1] as Image).save_png(_out.path_join(str(f[0]) + ".png"))
	_frames.clear()


func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	root.push_input(e, true)


func _drag(at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = at
	e.relative = rel
	e.velocity = rel * 60.0
	root.push_input(e, true)


func _main() -> void:
	var save = root.get_node("Save")
	var keep: Dictionary = save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(3.0)
	g = current_scene
	g.player.god = true
	var here: Vector3 = g.player.global_position
	g.enemies.spawn_pack("skeleton", here + Vector3(6, 0, -5), 6)
	g.enemies.spawn_pack("skeleton", here + Vector3(-7, 0, 4), 5)
	await _wait(1.5)
	await _grab("before")
	var reg = root.get_node("Registry")
	var d = reg.structure("war_drum")
	var at: Vector3 = here + Vector3(3.0, 0, 1.5)
	at.y = g.map.height_at(at.x, at.z)
	var s = g.structures._spawn(d, at)
	await _wait(0.4)
	await _grab("drum_standing")
	s.progress = 1.0
	g.structures._use(s)
	var dm = g.drum_moment
	var k := 0
	var guard := 0
	while k < MOMENT.size() and dm != null and bool(dm.playing) and guard < 400:
		guard += 1
		await process_frame
		if float(dm.t) >= float(MOMENT[k]):
			_frames.append(["mo_%03d" % int(round(float(MOMENT[k]) * 100.0)), root.get_viewport().get_texture().get_image()])
			print("p106_drum_shot: mo %.2f  t %.3f  hits %d  squash %.2f" % [MOMENT[k], dm.t, dm.hits_played, dm.squash()])
			k += 1
	_flush()
	await _wait(0.3)
	await _grab("after_000")
	print("p106_drum_shot: after the moment: paused %s  boost left %.1f  haste %.2f" % [str(g.paused), root.get_node("Run").boost_left("structure:war_drum"), root.get_node("Run").haste])
	# a finger on the stick: he runs west, then north
	var from := Vector2(540, 1450)
	_touch(from, true)
	await process_frame
	var p := from
	for i in range(8):
		_drag(p + Vector2(-25, 0), Vector2(-25, 0))
		p += Vector2(-25, 0)
		await process_frame
	await _wait(0.6)
	await _grab("run_060")
	await _wait(0.25)
	await _grab("run_085")
	await _wait(0.25)
	await _grab("run_110")
	for i in range(8):
		_drag(p + Vector2(20, -25), Vector2(20, -25))
		p += Vector2(20, -25)
		await process_frame
	await _wait(0.5)
	await _grab("run_160")
	_touch(p, false)
	await _wait(0.6)
	await _grab("stand_060")
	await _wait(0.2)
	await _grab("stand_080")
	_flush()
	print("p106_drum_shot: streaks %d  beats %d  plate %s" % [g.drum_boost.streak_count(), g.drum_boost.beats, str(root.get_node("Run").boost_left("structure:war_drum"))])
	save.data = keep
	quit(0)
