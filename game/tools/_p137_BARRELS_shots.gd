## Pass 137 (lane BARRELS): a barrel knocked back by a round and broken by the next, at the game's real camera in a plain
## run (director stopped, the crowd gone, the old auto-aim so the Revolver holds its fire). The knock's slide and squash
## are held by hand at chosen moments (the barrels' own drawing stepped with the engine's process off: a windowed capture
## caps a frame's step); the break runs in real time. Windowed:
##   GODOT_TIMEOUT=200 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p137_BARRELS_shots.gd -- out=<dir> [seed=11] [kind=0]
## Every wait is bounded (a watchdog quits after WATCHDOG seconds). The save and the settings in memory go back as they were.
extends SceneTree

const WATCHDOG := 150.0
var _out := "user://p137_barrels"
var _seed := 11
var _kind := 0
var _save
var _settings
var _aim := true
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("seed="):
			_seed = int(a.substr(5))
		elif a.begins_with("kind="):
			_kind = int(a.substr(5))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _restore() -> void:
	if _save:
		_save.data = _keep
	if _settings:
		_settings.aim_mode = _aim


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p137_barrels: watchdog, quitting")
		_restore()
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p137_barrels: ", name)


func _go(p: Vector3) -> void:
	p.y = g.map.height_at(p.x, p.z)
	g.player.global_position = p
	g.player.velocity = Vector3.ZERO
	g.camera.snap_to(g.player)


## The knock drawn `t` seconds in, held for a few frames (the engine's own process of the barrels is off).
func _hold(bf, i: int, t: float) -> void:
	for k in range(4):
		if bf._anims.has(i):
			bf._anims[i]["t"] = t
			bf._process(0.0)
		await process_frame


func _main() -> void:
	_save = root.get_node("Save")
	_settings = root.get_node("Settings")
	_keep = _save.data.duplicate(true)
	_aim = bool(_settings.aim_mode)
	_settings.aim_mode = false
	seed(137)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": _seed, "analytics": false}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(4.0)
	g = current_scene
	g.player.god = true
	g.director.stop()
	g.enemies.kill_all(false)
	var bf = g.barrels
	var best := -1
	var best_d := INF
	var here: Vector3 = g.player.global_position
	for i in bf.pos.size():
		if bf.alive[i] != 0 and bf.light[i] == _kind:
			var d := Vector2(bf.pos[i].x - here.x, bf.pos[i].z - here.z).length()
			if d < best_d:
				best_d = d
				best = i
	if best < 0:
		print("p137_barrels: no barrel of kind ", _kind)
		_restore()
		quit(1)
		return
	var at: Vector3 = bf.pos[best]
	# the outlaw a little south-west of it, so the barrel stands above him on the screen and a round from him flies NE
	_go(at + Vector3(-1.6, 0, 3.2))
	await _wait(0.8)
	_shot("a0_rest")
	var need: int = bf.shots_to_break(bf.light[best])
	print("p137_barrels: kind ", bf.light[best], " needs ", need, " at ", at)
	var dir := Vector3(1.0, 0.0, -1.0).normalized()
	for hit in range(need - 1):
		bf.set_process(false)
		bf.shot_hit(best, dir, bf.pos[best] - dir * 2.0)
		for t in [0.03, 0.09, 0.16, 0.24, 0.36]:
			await _hold(bf, best, t)
			_shot("b%d_knock_%03d" % [hit, int(t * 1000.0)])
		bf.set_process(true)
		await _wait(0.7)
		_shot("c%d_settled" % hit)
		print("p137_barrels: hit ", hit + 1, " at ", bf.pos[best], " moved ", Vector2(bf.pos[best].x - at.x, bf.pos[best].z - at.z).length())
	# the last: it breaks as walking into it does (debris, gems, dust), in real time
	bf.shot_hit(best, dir, bf.pos[best] - dir * 2.0)
	print("p137_barrels: broken ", bf.alive[best] == 0, " shot_breaks ", bf.shot_breaks)
	for k in range(5):
		await process_frame
		await process_frame
		_shot("d_break_%d" % k)
	await _wait(0.6)
	_shot("e_after")
	_restore()
	print("p137_barrels: done")
	quit(0)
