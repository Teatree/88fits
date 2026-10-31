## Pass 116 lane RESULTS capture: the Results' bounty sequence (a paid poster, an unfinished one) frame by frame, and the
## Dragon's Breath's ready sign on the three stages. Windowed, bounded (WATCHDOG_S), the save in the sandbox.
## Run: GODOT_TIMEOUT=600 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p116_RESULTS_shots.gd -- out=<dir> [only=results|breath]
extends SceneTree

const WATCHDOG_S := 150.0
var _out := "user://p116_results"
var _only := ""
var _save
var _run


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func():
		print("p116_results: watchdog, quitting")
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p116_results: ", name)


func _main() -> void:
	_save = root.get_node("Save")
	_run = root.get_node("Run")
	_save.begin_sandbox()
	if _only == "" or _only == "results":
		await _results("paid", {"name": "Scorpion Hunter", "text": "Kill 60 Dune Scorpions", "have": 60, "need": 60, "done": true,
			"paid": 240, "reward": 240, "type": "kill_enemy", "target": "dune_scorpion", "still": {}})
		await _results("open", {"name": "Barrel Breaker", "text": "Break 12 barrels", "have": 7, "need": 12, "done": false,
			"paid": 0, "reward": 180, "type": "barrels", "target": "", "still": {}})
	if _only == "" or _only == "breath":
		for st in [1, 2, 3]:
			await _breath(st)
	quit(0)


func _results(tag: String, rec: Dictionary) -> void:
	var reg = root.get_node("Registry")
	_run.start(reg.character("drifter"), reg.map("red_canyon"))
	_run.last_result = {"gold_before": 1200, "banked": 150, "bounty": rec}
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await process_frame
	await process_frame
	var r = current_scene
	var guard := 0
	var seen := {}
	var t0 := Time.get_ticks_msec()
	while r and r.sequence() < 3 and Time.get_ticks_msec() - t0 < 40000:
		var n: String = r.part_name()
		var f: float = r.part_frac()
		for want in [["bounty", 0.35], ["bounty", 0.8], ["bounty_pay", 0.4], ["pop", 0.5]]:
			var key: String = "%s_%s" % [want[0], str(want[1])]
			if n == want[0] and f >= float(want[1]) and not seen.has(key):
				seen[key] = true
				await _shot("results_%s_%s" % [tag, key.replace(".", "")])
		await process_frame
		guard += 1
	await _wait(0.3)
	await _shot("results_%s_end" % tag)


func _breath(stage: int) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"character": "drifter", "weapon": "dragons_breath", "level": 1, "map": "red_canyon",
		"map_seed": 7, "spawn": false, "analytics": false, "stage": stage}))
	f.close()
	change_scene_to_file("res://game/Game.tscn")
	await _wait(2.5)
	var g = current_scene
	if g == null:
		return
	g.player.god = true
	var fb: Node = null
	for n in g.find_children("*", "FireBreath", true, false):
		fb = n
	if fb == null:
		print("p116_results: no FireBreath")
		return
	fb.cooldown_left = 0.5
	fb._ready_for = 0.0
	var guard := 0
	while guard < 300 and (fb._ready_sign == null or not fb._ready_sign.playing()):
		fb.cooldown_left = maxf(fb.cooldown_left, 0.0)
		await process_frame
		guard += 1
	await _wait(0.08)
	await _shot("breath_stage%d_a" % stage)
	await _wait(0.14)
	await _shot("breath_stage%d_b" % stage)
	await _wait(0.14)
	await _shot("breath_stage%d_c" % stage)
