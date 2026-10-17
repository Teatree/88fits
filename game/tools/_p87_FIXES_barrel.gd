## Pass 87, lane FIXES, scratch capture in the debug arena: a black barrel (the rare "darker" one) broken by the hero,
## its gems and its 1-5 coins, frame by frame; prints the map's barrels (black ones, the two extra) on the way. Windowed:
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p87_FIXES_barrel.gd -- out=<dir>
## Every wait is bounded (frame caps and a watchdog quitting after WATCHDOG seconds).
extends SceneTree

const WATCHDOG := 90.0
var _out := "user://p87_barrel"
var _run
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p87_barrel: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String, at: Vector3) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var cam: Camera3D = g.camera.camera
	var p: Vector2 = cam.unproject_position(at + Vector3(0, 0.5, 0))
	var r := Rect2i(int(p.x) - 300, int(p.y) - 330, 600, 560).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(_out.path_join(name + ".png"))
	var pk = g.pickups
	print("p87_barrel: ", name, " coins on the sand %d, dropped %d, gold %d" % [pk.coins, g.barrels.coins_dropped, _run.run_gold])


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
		g.camera.zoom_override = 0.55
	_run.debug_clear_items()
	_run.build_changed.emit()
	await _wait(1.0)
	g.enemies.kill_all(false)
	var bf = g.barrels
	var blacks := 0
	var line := ""
	for k in range(bf.pos.size()):
		blacks += bf.light[k]
		line += str(bf.light[k])
	print("p87_barrel: %d barrels, %d black, light %s" % [bf.pos.size(), blacks, line])
	# the nearest black barrel to the hero
	var best := -1
	var bd := INF
	for k in range(bf.pos.size()):
		if bf.light[k] == 1 and bf.alive[k] == 1:
			var d: float = bf.pos[k].distance_to(g.player.global_position)
			if d < bd:
				bd = d
				best = k
	if best < 0:
		print("p87_barrel: no black barrel")
		_save.data = _keep
		quit(2)
		return
	var at: Vector3 = bf.pos[best]
	# the hero just south of it (towards the camera), then a step onto it
	g.player.global_position = at + Vector3(0, 0.2, 3.0)
	g.camera.snap_to(g.player)
	await _wait(0.6)
	await _shot("a0_black_barrel", at)
	g.player.global_position = at + Vector3(0, 0.2, 1.1)
	var n := 0
	while bf.alive[best] == 1 and n < 120:
		await process_frame
		n += 1
	await _shot("a1_burst", at)
	await _wait(0.3)
	await _shot("a2_0.3s", at)
	await _wait(0.6)
	await _shot("a3_0.9s", at)
	# walking over the coins: the magnet takes them
	g.player.global_position = at + Vector3(0, 0.2, 0.0)
	await _wait(1.2)
	await _shot("a4_taken", at)
	_save.data = _keep
	quit(0)
