## Pass 100, lane SMALL: the spawn beam's landing on each stage, windowed, to check by eye that the intro plays in the
## stage's light (Nightfall blue, Blood Moon red + hell) and that nothing switches when the run starts.
##   bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p100_SMALL_intro_shot.gd -- out=<dir> [stages=1,2,3]
## For each stage: a real launch with the beam (Run.launch_override "spawn": true, "stage": k), frames at the beam alone,
## mid-fall, the landing, and two seconds into the run, as <out>/s<k>_<label>.png. The save is sandboxed; every wait is
## bounded by a frame cap, and a watchdog quits after 150 s whatever happens.
extends SceneTree

var _out := ""
var _stages: Array = [1, 2, 3]
var _run
var _save


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"out": _out = kv[1]
			"stages":
				_stages = []
				for s in kv[1].split(","):
					_stages.append(int(s))
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("intro_shot: watchdog quit")
		quit(3))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("intro_shot: ", path)


func _main() -> void:
	_run = root.get_node("Run")
	_save = root.get_node("Save")
	if _out == "":
		printerr("intro_shot: out=<dir> is needed")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_save.begin_sandbox()
	for s: int in _stages:
		_run.launch_override = {"spawn": true, "stage": s, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}
		change_scene_to_file("res://game/Game.tscn")
		var g: Node = null
		for k in range(600):
			await process_frame
			g = current_scene
			if g and g.get("spawning") == true and g.get("player") != null:
				break
		if g == null or g.get("spawning") != true:
			printerr("intro_shot: stage %d: no landing" % s)
			quit(2)
			return
		var t0 := Time.get_ticks_msec()
		var marks := [[300, "a_beam"], [1300, "b_fall"], [2050, "c_landed"]]
		for m in marks:
			var frames := 0
			while Time.get_ticks_msec() - t0 < int(m[0]) and frames < 600:
				await process_frame
				frames += 1
			await _shot(_out.path_join("s%d_%s.png" % [s, str(m[1])]))
		var frames2 := 0
		while not bool(g.get("_run_started")) and frames2 < 900:
			await process_frame
			frames2 += 1
		var t1 := Time.get_ticks_msec()
		var frames3 := 0
		while Time.get_ticks_msec() - t1 < 2000 and frames3 < 600:
			await process_frame
			frames3 += 1
		await _shot(_out.path_join("s%d_d_run.png" % s))
		var sl: Node = g.get_node_or_null("StageLook")
		print("intro_shot: stage %d run_started %s look stage %s env %s" % [s, g.get("_run_started"), sl.get("stage") if sl else -1, sl.get("env_mult") if sl else "none"])
	if _save.has_method("end_sandbox"):
		_save.end_sandbox()
	quit(0)
