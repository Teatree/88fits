## Pass 136, lane GUNS: the aim wedge (core/systems/AimWedge.gd, R7) on each stage, at the game's real camera in a plain run
## with the director stopped: at rest, and held at a pulse with a shot's line down it. Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p136_GUNS_shots.gd -- out=<dir> [stages=1,2,3,4] [weapon=revolver]
## Every wait is bounded (a watchdog quits after WATCHDOG seconds). The save in memory goes back as it was.
extends SceneTree

const WATCHDOG := 220.0
var _out := "user://p136_guns"
var _stages: Array = [1, 2, 3, 4]
var _weapon := "revolver"
var _save
var g
var _t0 := 0
var _keep: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("stages="):
			_stages = []
			for s in a.substr(7).split(","):
				_stages.append(int(s))
		elif a.begins_with("weapon="):
			_weapon = a.substr(7)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p136_guns: watchdog, quitting")
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p136_guns: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var st = root.get_node("Settings")
	st.set("aim_mode", true)
	st.set("show_aim", true)
	seed(136)
	for stage: int in _stages:
		var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"weapon": _weapon, "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11,
			"stage": stage, "analytics": false}))
		f.close()
		change_scene_to_file("res://game/Game.tscn")
		await _wait(4.0)
		g = current_scene
		g.player.god = true
		g.director.stop()
		g.enemies.kill_all(false)
		await _wait(1.6)
		var wedge = g.get_node_or_null("AimWedge")
		print("p136_guns: stage ", stage, " wedge ", wedge != null, " cone ", wedge.cone_deg if wedge else -1.0, " visible ", wedge.visible if wedge else false)
		for k in range(2):
			g.player.facing = [0.3, 2.7][k]
			await _wait(0.25)
			_shot("s%d_rest_%d" % [stage, k])
		# held at a pulse with the shot's line 15 degrees right of the facing
		var fwd: Vector3 = g.player.forward()
		var d := fwd.rotated(Vector3.UP, deg_to_rad(-15.0))
		for k in range(12):
			wedge.call("pulse_dir", d)
			await process_frame
		_shot("s%d_pulse" % stage)
	_save.data = _keep
	print("p136_guns: done")
	quit(0)
