## Pass 127 (lane ART): the flying Carrion Crow and the Dust Bunny's colour looks at the game's real camera under the Dust Bowl's look, in the
## debug arena: a flock close to the hero in flight (its wing beat, a few frames apart), then hovering (the arena's freeze: idle frames), then
## shot out of the air until the bodies lie; then the three bunny looks side by side. Windowed:
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game --log-file <abs> \
##       --script res://tools/_p127_ART_shots.gd -- out=<dir> [stage=2] [only=crow,bunny]
## Every wait is bounded (frame caps and a watchdog quitting after WATCHDOG seconds). The save in memory goes back as it was.
extends SceneTree

const WATCHDOG := 200.0
var _out := "user://p132_skel"
var _stage := -1
var _only := ["crow", "bunny"]
var _run
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("stage="):
			_stage = int(a.substr(6))
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p132_skel: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p132_skel: ", name)


func _crowd(id: String, look: String, n: int, off: Vector3, wide: float, deep: float) -> void:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var ids: Array = []
	for k in range(n):
		var p := here + off + Vector3(randf_range(-wide, wide), 0.0, randf_range(-deep, deep))
		var i: int = em.spawn(id, p, null, 1.0, 400.0, look)
		if i >= 0:
			ids.append(i)
	var c := 0
	while c < 240:
		var up := true
		for i in ids:
			if em.state[i] != em.STATE_MOVE:
				up = false
		if up:
			break
		await process_frame
		c += 1


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	seed(127)
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
	_run.debug_clear_items()
	_run.build_changed.emit()
	if _stage >= 0:
		load("res://core/systems/StageLook.gd").of(g).show_stage(_stage, 0.0)
	await _wait(1.0)
	var em = g.enemies
	em.kill_all(false)
	await _wait(0.3)
	await _crowd("skeleton", "SK-A", 4, Vector3(-3.0, 0, -4.5), 1.2, 1.0)
	await _crowd("skeleton", "SK-F", 4, Vector3(0.0, 0, -4.5), 1.2, 1.0)
	await _crowd("skeleton", "SK-I", 4, Vector3(3.0, 0, -4.5), 1.2, 1.0)
	await _wait(0.3)
	_shot("alive")
	em.kill_all(true)
	for k in range(4):
		await _wait(1.5)
		_shot("die_%02d" % k)
	em.kill_all(false)
	_save.data = _keep
	print("p132_skel: done")
	quit(0)
