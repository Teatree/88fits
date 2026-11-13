## Pass 146: the Stranger in a real run: his idle (stepped, pass 144) and his collapse as his screen closes, cropped round
## him. Windowed at the phone's canvas, at a fixed 60 fps, bounded by a watchdog:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 --path D:/_projects/88fits/game
##       --script res://tools/_p146_STRANGER_shots.gd -- out=<dir> [took=1]
## -> <out>/idle_NN.png (every 0.1 s for 2 s), die_NN.png (every 0.1 s for 1.4 s), whole_*.png
extends SceneTree

const WATCHDOG_S := 120.0
const FRAME_CAP := 6000

var _out := "user://p146_stranger"
var _took := false
var _t0 := 0.0
var _n := 0
var g


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("took="):
			_took = a.substr(5) == "1"
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec() * 0.001
	process_frame.connect(_main, CONNECT_ONE_SHOT)
	process_frame.connect(_watchdog)


func _watchdog() -> void:
	_n += 1
	if Time.get_ticks_msec() * 0.001 - _t0 > WATCHDOG_S or _n > FRAME_CAP:
		printerr("p146_stranger: watchdog (%d frames), quitting" % _n)
		quit(2)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _crop(name: String, at: Vector3) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var c: Vector2 = g.get_viewport().get_camera_3d().unproject_position(at + Vector3(0, 1.2, 0))
	var r := Rect2i(int(c.x) - 260, int(c.y) - 330, 520, 520)
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(_out.path_join(name + ".png"))


func _main() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(3.0)
	g = current_scene
	g.player.god = true
	g.director.running = false
	var here: Vector3 = g.player.global_position
	var at: Vector3 = here + Vector3(2.5, 0, -1.5)
	at.y = g.map.height_at(at.x, at.z)
	var s = g.structures._spawn(root.get_node("Registry").structure("hooded_figure"), at)
	await _wait(0.5)
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("whole_idle.png"))
	for k in 20:
		await _crop("idle_%02d" % k, at)
		await _wait(0.1)
	s.progress = 1.0
	g.structures._use(s)
	var guard := 0
	while not g.stranger_screen.visible and guard < 120 and str(s.visual.animation) != "die":
		guard += 1
		await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("whole_screen.png"))
	if g.stranger_screen.visible:
		g.stranger_screen._finish(_took)
	for k in 14:
		await _crop("die_%02d" % k, at)
		await _wait(0.1)
	await _wait(0.5)
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("whole_after.png"))
	print("p146_stranger: done (anim %s, frame %.1f)" % [s.visual.animation, s.visual.frame])
	quit(0)
