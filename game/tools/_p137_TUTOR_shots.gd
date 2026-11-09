## Pass 137, lane TUTOR: the Trail's first steps captured: the Trail tab locked on a new save, the Results' UPGRADE grey
## through the show and highlighted after it, the Trail's BUY highlighted, and the tab's unlock frame by frame. Windowed:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p137_TUTOR_shots.gd -- out=<dir> [only=results,trail,tab]
## The highlight's clock is set by hand before each shot (a windowed capture's frames are slow); the unlock plays under a
## slow Engine.time_scale. Every wait is bounded (WATCHDOG). The save in memory goes back as it was.
extends SceneTree

const WATCHDOG := 200.0
var _out := "user://p137_tutor"
var _only: Array = []
var _save
var _keep: Dictionary = {}
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > int(WATCHDOG * 1000.0):
		print("p137_tutor: watchdog, quitting")
		Engine.time_scale = 1.0
		if _save:
			_save.data = _keep
		quit(3)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p137_tutor: ", name)


func _scene(path: String) -> Node:
	change_scene_to_file(path)
	for k in 200:
		await process_frame
		if current_scene and str(current_scene.scene_file_path) == path:
			break
	await _wait(1.0)
	return current_scene


## The highlight's clock held at `t` for a frame, then a shot.
func _hl_shot(hl: Node, t: float, name: String) -> void:
	for k in 2:
		hl.set("_t", t)
		await process_frame
	_shot(name)


func _main() -> void:
	_save = root.get_node("Save")
	_keep = _save.data.duplicate(true)
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	_save.data = _save._default()
	_save._migrate_seen()
	_save.data["gold"] = 50
	_save.data["tutorial"] = _save.tutorial_fresh()
	if _want("tab"):
		# a new save: the Trail's tab locked like STORE
		await _scene("res://ui/CollectionScreen.tscn")
		_shot("tab_0_locked_new_save")
	if _want("results"):
		_save.mark_tutorial("trail_open")
		_save.mark_tutorial("tab_unlock_shown")
		run.start(reg.character("drifter"), reg.map("red_canyon"))
		run.kills = 140
		run.damage_by_weapon = {"revolver": 2400.0, "lob_grenade": 900.0}
		run.last_result = {"gold_before": 50, "banked": 85}
		var r: Node = await _scene("res://ui/ResultsScreen.tscn")
		_shot("results_0_show_upgrade_grey")
		r.call("skip_all")
		await _frames(3)
		var hl: Node = r.find_child("TutorHighlight", false, false)
		if hl:
			await _hl_shot(hl, 0.12, "results_1_intro")
			await _hl_shot(hl, 0.3, "results_2_shine")
			await _hl_shot(hl, 0.62, "results_3_pulse")
			await _hl_shot(hl, 1.05, "results_4_touch")
		else:
			print("p137_tutor: no highlight on the Results")
		run.end()
	if _want("trail"):
		_save.mark_tutorial("trail_open")
		_save.mark_tutorial("upgrade_tapped")
		_save.mark_tutorial("tab_unlock_shown")
		var s: Node = await _scene("res://ui/TrailScreen.tscn")
		var hl2: Node = s.find_child("TutorHighlight", false, false)
		if hl2:
			await _hl_shot(hl2, 0.12, "trail_1_intro")
			await _hl_shot(hl2, 0.3, "trail_2_shine")
			await _hl_shot(hl2, 1.05, "trail_3_touch")
		else:
			print("p137_tutor: no highlight on the Trail")
	if _want("tab"):
		_save.data["tutorial"] = _save.tutorial_fresh()
		_save.mark_tutorial("trail_open")
		_save.mark_tutorial("upgrade_tapped")
		_save.mark_tutorial("buy_tapped")
		Engine.time_scale = 0.3
		var c: Node = await _scene("res://ui/CollectionScreen.tscn")
		var bar: Node = c.get("tab_bar_node")
		_shot("tab_1_pending")
		if bar and bool(bar.call("unlock_pending")):
			bar.call("play_unlock")
			for k in 10:
				await _wait(0.4)
				_shot("tab_2_unlock_%02d" % k)
		Engine.time_scale = 1.0
		await _wait(0.6)
		_shot("tab_3_after")
	Engine.time_scale = 1.0
	_save.data = _keep
	print("p137_tutor: done")
	quit(0)
