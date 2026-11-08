## Pass 135: the Teleport's new charge (the outlaw standing in a middle one for its 3 s), a rim Teleport by the wall, and the
## barrels' glint, at the game's real camera in a plain run with the director stopped. Windowed:
##   GODOT_TIMEOUT=200 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p135_STRUCT_shots.gd -- out=<dir> [seed=11]
## Every wait is bounded (a watchdog quits after WATCHDOG seconds). The save in memory goes back as it was.
extends SceneTree

const WATCHDOG := 150.0
var _out := "user://p135_struct"
var _seed := 11
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p135_struct: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p135_struct: ", name)


func _go(p: Vector3) -> void:
	p.y = g.map.height_at(p.x, p.z)
	g.player.global_position = p
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)


func _main() -> void:
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	seed(135)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(4.0)
	g = current_scene
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	var sm = g.structures
	var mid = null
	var rim = null
	for s in sm.items:
		if s.def.effect_kind != "teleport":
			continue
		if s.edge and rim == null:
			rim = s
		elif not s.edge and mid == null:
			mid = s
	print("p135_struct: edges ", sm.edge_spots().size(), " all ", sm.teleport_spots().size())
	if rim:
		_go(rim.global_position + Vector3(0, 0, 4.0))
		await _wait(0.6)
		_shot("rim_teleport")
	if mid:
		_go(mid.global_position + Vector3(0, 0, 4.0))
		await _wait(0.6)
		_shot("charge_0_rest")
		# the charge held at 0.95 with the outlaw out of the way (each frame, after the drain), to see the swirl itself
		# (a windowed capture runs slowly and the game caps a frame's step, so a real 3 s charge never fills here)
		for hold in [0.3, 0.6, 0.95]:
			for k in range(20):
				mid.progress = hold
				sm._tick_portal(mid, 0.016, true, 4.0)
				await process_frame
			mid.progress = hold
			sm._tick_portal(mid, 0.016, true, 4.0)
			_shot("charge_held_%02d" % int(hold * 100.0))
		mid.progress = 0.0
		await _wait(0.3)
		# into the ring: it charges over its 3 s
		_go(mid.global_position + Vector3(0.0, 0, 0.9))
		await _wait(0.75)
		_shot("charge_1")
		print("p135_struct: progress ", mid.progress, " size ", mid.portal_mat.get_shader_parameter("size"), " push ", mid.portal_mat.get_shader_parameter("push"), " at ", g.player.global_position.distance_to(mid.global_position))
		await _wait(0.75)
		_shot("charge_2")
		print("p135_struct: progress ", mid.progress, " size ", mid.portal_mat.get_shader_parameter("size"), " push ", mid.portal_mat.get_shader_parameter("push"), " at ", g.player.global_position.distance_to(mid.global_position))
		await _wait(0.75)
		_shot("charge_3")
		print("p135_struct: progress ", mid.progress, " size ", mid.portal_mat.get_shader_parameter("size"), " push ", mid.portal_mat.get_shader_parameter("push"), " at ", g.player.global_position.distance_to(mid.global_position))
		await _wait(0.5)
		_shot("charge_4")
		print("p135_struct: progress ", mid.progress, " size ", mid.portal_mat.get_shader_parameter("size"), " push ", mid.portal_mat.get_shader_parameter("push"), " at ", g.player.global_position.distance_to(mid.global_position))
	# the barrels: near the nearest one, the glint sped up so several show in a few frames, then the game's own
	var bf = g.barrels
	var best := -1
	var best_d := INF
	var here: Vector3 = g.player.global_position
	for i in bf.pos.size():
		if bf.alive[i] != 0:
			var d := Vector2(bf.pos[i].x - here.x, bf.pos[i].z - here.z).length()
			if d < best_d:
				best_d = d
				best = i
	if best >= 0:
		_go(bf.pos[best] + Vector3(1.5, 0, 3.0))
		bf.apply_glint({"strength": 0.85, "every": 1.2, "length": 0.5, "width": 0.14})
		await _wait(0.5)
		for k in range(6):
			_shot("barrel_glint_%02d" % k)
			await _wait(0.1)
	_save.data = _keep
	print("p135_struct: done")
	quit(0)
