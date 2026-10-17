## Pass 87, lane MUMMY, scratch capture in the debug arena: the four new Dust Mummy looks (DM-F..DM-I) walking at the
## hero from the far side (their front walk) and from the camera's side (their back walk), and dying, shot a few frames
## apart. Windowed at the phone's canvas:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p87_mummy_shot.gd -- out=<dir> [looks=DM-F,DM-G]
## Every wait is bounded (frame caps and a watchdog quitting after WATCHDOG seconds).
extends SceneTree

const WATCHDOG := 120.0
var _out := "user://p87_mummy"
var _looks: Array = ["DM-F", "DM-G", "DM-H", "DM-I"]
var _run
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("looks="):
			_looks = Array(a.substr(6).split(","))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p87_mummy: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p87_mummy: ", name)


func _spawn_row(z: float) -> Array:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var ids: Array = []
	var n := _looks.size()
	for k in range(n):
		var x := (float(k) - float(n - 1) * 0.5) * 1.9
		ids.append(em.spawn("dust_mummy", here + Vector3(x, 0, z), null, 1.0, 400.0, str(_looks[k])))
	# out of the ground and walking first (bounded)
	var c := 0
	while c < 300:
		var up := true
		for i in ids:
			if em.state[i] != em.STATE_MOVE:
				up = false
		if up:
			break
		await process_frame
		c += 1
	return ids


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "peashooter", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	_run.arena_next = true
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	g = current_scene
	g.player.god = true
	if g.get("arena_panel") and g.arena_panel:
		g.arena_panel.visible = false
	g.set_paused(false)
	if g.camera:
		g.camera.zoom_override = 0.5
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(1.0)
	var em = g.enemies
	em.kill_all(false)
	# the far side: they walk down the screen at the hero, their front walk
	var ids: Array = await _spawn_row(-7.5)
	await _wait(0.3)
	for k in range(8):
		_shot("f%02d_front" % k)
		await _wait(0.07)
	em.kill_all(false)
	await _wait(0.4)
	# the camera's side: they walk up the screen, their back walk (the camera pulled back to its usual distance, or a
	# row this close to it sits under the camera)
	if g.camera:
		g.camera.zoom_override = 1.0
	ids = await _spawn_row(3.0)
	await _wait(0.3)
	for k in range(8):
		_shot("b%02d_back" % k)
		await _wait(0.07)
	# the deaths, from the back row
	em.kill_all(true)
	for k in range(8):
		await _wait(0.08)
		_shot("d%02d_die" % k)
	_save.data = _keep
	quit(0)
