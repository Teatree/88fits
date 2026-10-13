## Pass 72 (lane RESULTS): the animated Results screen caught at every stage of its show, from a made-up run
## (tools/results_story.gd). Windowed at the phone's canvas:
## godot --audio-driver Dummy --resolution 1080x1920 --path game --script res://tools/_p72_results_shot.gd -- out=<dir> [inset=130] [only=play,down,taps]
## play: the whole show untouched, a picture at each stage; down: the run that ended in a fall (graves, the revive's
## blast); taps: one tap (faster), a second (the first sequence ends), the end. A watchdog quits after WATCHDOG seconds.
extends SceneTree

const WATCHDOG := 150.0
var _out := "user://p72_results"
var _only: Array = []
var _inset := -1
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("inset="):
			_inset = int(a.substr(6))
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(WATCHDOG, true, false, true).timeout.connect(func():
		printerr("p72_results_shot: watchdog after %d s" % int(WATCHDOG))
		quit(2))
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


## Waits until `s` seconds after the scene came in.
func _until(s: float) -> void:
	var left := s - float(Time.get_ticks_msec() - _t0) / 1000.0
	if left > 0.0:
		await _wait(left)


## Waits (at most 25 s) until the show's part `part` has come `frac` of its way, or has gone by; "" waits for the end.
func _at(part: String, frac: float) -> void:
	var order := ["gold", "breath", "chart", "sources", "pause", "scroll", "unlock", "progress", ""]
	var want := order.find(part)
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var rs = current_scene
		if rs and rs.has_method("part_name"):
			var now: String = rs.call("part_name")
			if part == "" and now == "":
				return
			if now == part and float(rs.call("part_frac")) >= frac:
				return
			if part != "" and order.find(now) > want and now != "breath":
				return
			if part != "" and now == "":
				return
		await process_frame
	printerr("p72_results_shot: waited too long for ", part)


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	var rs = current_scene
	print("p72_results_shot: %s at %.2f s (sequence %d, part %s %.2f, speed %.0f, scroll %d, show %.2f s)" % [name, float(Time.get_ticks_msec() - _t0) / 1000.0,
		int(rs.call("sequence")) if rs and rs.has_method("sequence") else -1, str(rs.call("part_name")) if rs and rs.has_method("part_name") else "?",
		float(rs.call("part_frac")) if rs and rs.has_method("part_frac") else 0.0,
		float(rs.call("speed")) if rs and rs.has_method("speed") else 0.0,
		rs.scroll.scroll_vertical if rs and rs.get("scroll") else -1, float(rs.call("show_time")) if rs and rs.has_method("show_time") else 0.0])


func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	root.push_input(e, true)


func _tap(at: Vector2) -> void:
	_touch(at, true)
	await process_frame
	_touch(at, false)
	await process_frame


func _main() -> void:
	var save = root.get_node("Save")
	save.begin_sandbox()
	if _inset >= 0:
		root.get_node("Settings").top_inset = _inset
	var suffix := "" if _inset < 0 else "_inset%d" % _inset
	if _want("play"):
		await _results(false)
		await _at("gold", 0.0)
		await _shot("a-start" + suffix)
		await _at("gold", 0.5)
		await _shot("b-gold" + suffix)
		await _at("chart", 0.5)
		await _shot("c-chart" + suffix)
		await _at("chart", 1.0)
		await _shot("d-chart-done" + suffix)
		await _at("sources", 0.5)
		await _shot("e-sources" + suffix)
		await _at("pause", 0.1)
		await _shot("f-seq1-end" + suffix)
		await _at("scroll", 0.5)
		await _shot("g-scroll" + suffix)
		await _at("unlock", 0.55)
		await _shot("h-unlock-stamp" + suffix)
		await _at("progress", 0.5)
		await _shot("i-progress" + suffix)
		await _at("", 1.0)
		await _wait(0.4)
		await _shot("j-end" + suffix)
		current_scene.scroll.scroll_vertical = 0
		await _wait(0.3)
		await _shot("k-end-top" + suffix)
	if _want("down"):
		await _results(true)
		await _at("chart", 1.0)
		await _wait(0.35)
		await _shot("m-down-chart" + suffix)
		await _at("pause", 0.1)
		await _shot("n-down-sources" + suffix)
	if _want("taps"):
		await _results(false)
		await _until(1.0)
		var mid := Vector2(540, 700)
		await _tap(mid)
		await _wait(0.4)
		await _shot("p-tap-once" + suffix)
		await _tap(mid)
		await _wait(0.1)
		await _shot("q-tap-twice" + suffix)
		await _wait(0.6)
		await _tap(mid)
		await _tap(mid)
		await _wait(0.5)
		await _shot("r-tap-end" + suffix)
	save.end_sandbox()
	quit(0)


## The Results after the made-up run (a fall or two when `died`), the clock from the moment it comes in.
func _results(died: bool) -> void:
	var run = root.get_node("Run")
	var reg = root.get_node("Registry")
	var save = root.get_node("Save")
	run.start(reg.character("drifter"), reg.map("red_canyon"))
	for pair in [["revolver", 5], ["boomstick", 4], ["molotov", 3], ["big_mouth", 3], ["turret_buddy", 2]]:
		run.add_weapon(reg.weapon(str(pair[0])), int(pair[1]))
	run.end()
	# a fresh save (the PC's own may have these unlocks done already; the sandbox puts it back)
	save.set("data", save.call("_default"))
	save.call("_migrate_seen")
	var qt = load("res://core/systems/QuestTracker.gd")
	load("res://tools/results_story.gd").fill(run, save, qt, died)
	change_scene_to_file("res://ui/ResultsScreen.tscn")
	await process_frame
	_t0 = Time.get_ticks_msec()
	await process_frame
