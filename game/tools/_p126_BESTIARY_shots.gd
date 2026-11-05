## Pass 126 (lane BESTIARY; Garry: "Come up with 3 fodder enemies that would fit this level"): the Dust Bowl's fodder at the
## game's real camera in the debug arena: each creature (or `only=`) walks in as a crowd from the far side (its front walk),
## from the camera's side (its back walk) and across the screen (its heading mirrors), then dies, shot a few frames apart.
## On Sundown's ground by default; stage=<k> shows that stage's look (StageLook) over it, once the map has the stage.
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p126_BESTIARY_shots.gd -- out=<dir> [only=straw_man,dust_bunny] [stage=2] [looks=straw_man:SM-A] [mix=1]
## Every wait is bounded (frame caps and a watchdog quitting after WATCHDOG seconds). The PC's save is put back.
extends SceneTree

const WATCHDOG := 240.0
const IDS := ["straw_man", "carrion_crow", "dust_bunny"]
var _out := "user://p126_bestiary"
var _only: Array = IDS.duplicate()
var _stage := -1
var _looks: Dictionary = {}
var _mix := false
var _run
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = Array(a.substr(5).split(",", false))
		elif a.begins_with("stage="):
			_stage = int(a.substr(6))
		elif a == "mix=1":
			_mix = true
		elif a.begins_with("looks="):
			for pair in a.substr(6).split(",", false):
				var kv := (pair as String).split(":")
				_looks[kv[0]] = kv[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p126_bestiary: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p126_bestiary: ", name)


## A crowd of `n` in a band centred `off` metres from the hero, up out of the ground before it returns (bounded).
func _crowd(id: String, n: int, off: Vector3, wide: float, deep: float) -> void:
	var em = g.enemies
	var here: Vector3 = g.player.global_position
	var v := str(_looks.get(id, ""))
	var ids: Array = []
	for k in range(n):
		var p := here + off + Vector3(randf_range(-wide, wide), 0.0, randf_range(-deep, deep))
		var i: int = em.spawn(id, p, null, 1.0, 400.0, v)
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
	seed(126)
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
	if _mix:
		# all three together, as a row of the stage brings them
		await _crowd("straw_man", 14, Vector3(0, 0, -7.5), 6.0, 2.0)
		await _crowd("carrion_crow", 16, Vector3(-3.0, 0, -5.5), 4.0, 1.5)
		await _crowd("dust_bunny", 24, Vector3(2.0, 0, -4.5), 5.0, 2.0)
		await _wait(0.5)
		for k in range(4):
			_shot("mix_%02d" % k)
			await _wait(0.1)
		em.kill_all(false)
		await _wait(0.3)
	for id: String in _only:
		var n: int = 16 if id != "dust_bunny" else 26
		# the far side: they walk down the screen at the hero, their front walk
		await _crowd(id, n, Vector3(0, 0, -7.0), 5.0, 2.0)
		await _wait(0.25)
		for k in range(6):
			_shot("%s_front_%02d" % [id, k])
			await _wait(0.067)
		em.kill_all(false)
		await _wait(0.3)
		# the camera's side: they walk up the screen, their back walk
		await _crowd(id, n, Vector3(0, 0, 5.0), 5.0, 1.5)
		await _wait(0.25)
		for k in range(6):
			_shot("%s_back_%02d" % [id, k])
			await _wait(0.067)
		em.kill_all(false)
		await _wait(0.3)
		# across the screen: the heading's mirror and the shadow under a body seen moving sideways
		var half: int = int(n * 0.5)
		await _crowd(id, half, Vector3(-6.0, 0, 0.0), 1.5, 3.0)
		await _crowd(id, half, Vector3(6.0, 0, 0.0), 1.5, 3.0)
		await _wait(0.25)
		for k in range(3):
			_shot("%s_side_%02d" % [id, k])
			await _wait(0.1)
		# the deaths
		em.kill_all(true)
		for k in range(8):
			await _wait(0.08)
			_shot("%s_die_%02d" % [id, k])
		await _wait(0.6)
		em.kill_all(false)
		await _wait(0.3)
	_save.data = _keep
	print("p126_bestiary: done")
	quit(0)
