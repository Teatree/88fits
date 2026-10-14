## Pass 76 (lane UI) scratch capture: the Revolver's tracer in several candidate colours (its params' tracer_color set on
## the held instance), one frame each after a pull, cropped as _p76_UI_tracer_shot.gd crops. Windowed, fixed 60 fps,
## bounded waits and a watchdog:
##   godot --audio-driver Dummy --fixed-fps 60 --resolution 1080x1920 --path game --script res://tools/_p76_UI_tracer_pick.gd -- out=<dir> colours=A33A2E,7A1F17 [alpha=0.85] [size=1.35] [frame=12]
extends SceneTree

const WATCHDOG_S := 150.0
const CROP := Vector2i(900, 1100)

var _out := "user://p76_ui_tracer_pick"
var _colours: Array = ["A33A2E"]
var _alpha := 0.85
var _size := 1.35
var _frame := 12
var _run
var _save
var g
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("colours="):
			_colours = Array(a.substr(8).split(","))
		elif a.begins_with("alpha="):
			_alpha = float(a.substr(6))
		elif a.begins_with("size="):
			_size = float(a.substr(5))
		elif a.begins_with("frame="):
			_frame = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG_S * 1000.0):
		print("p76_ui_pick: WATCHDOG, quitting")
		quit(2)
	return false


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	var keep: Dictionary = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 3, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	if g == null or not g.has_method("set_paused"):
		print("p76_ui_pick: no game scene")
		_save.data = keep
		quit(1)
		return
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = 1.0
	await _wait(3.2)
	g.hud._banner.visible = false
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	for hexc in _colours:
		_run.debug_clear_items()
		_run.debug_set_item("weapon", "revolver", 3)
		_run.build_changed.emit()
		var inst = _run.weapon_instance("revolver")
		if inst:
			inst.params["tracer_color"] = "#" + str(hexc)
			inst.params["tracer_alpha"] = _alpha
			inst.params["tracer_size"] = _size
		var em = g.enemies
		em.kill_all(false)
		var here: Vector3 = g.player.global_position
		for k in range(5):
			var s := -2.0 + 4.0 * float(k) / 4.0
			em.spawn("skeleton", here + Vector3(s, 0, -9.0 - 0.6 * float(k % 2)), null, 1.0, 400.0)
		em._rebuild_grid()
		await _wait(1.2)
		var b = g._behaviors.get("revolver")
		if b == null:
			print("p76_ui_pick: no revolver behaviour")
			break
		# the behaviour's own instance may be another copy: set it there too
		var bi = b.get("inst")
		if bi:
			bi.params["tracer_color"] = "#" + str(hexc)
			bi.params["tracer_alpha"] = _alpha
			bi.params["tracer_size"] = _size
		b.cooldown_left = 3.0 / 60.0
		for fr in range(_frame + 3):
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var a: Vector2 = cam.unproject_position(g.player.global_position)
		var t: Vector2 = cam.unproject_position(here + Vector3(0, 0, -9.0))
		var mid := (a + t) * 0.5
		var x := clampi(int(mid.x) - CROP.x / 2, 0, img.get_width() - CROP.x)
		var y := clampi(int(mid.y) - CROP.y / 2, 0, img.get_height() - CROP.y)
		img.get_region(Rect2i(x, y, CROP.x, CROP.y)).save_png(_out.path_join("c_%s.png" % str(hexc)))
		b.cooldown_left = 99.0
		await _wait(1.6)
	_save.data = keep
	print("p76_ui_pick: done -> ", _out)
	quit(0)
