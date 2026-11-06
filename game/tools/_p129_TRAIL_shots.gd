## Pass 129 (lane TRAIL-UI): the Trail screen proved by eye, on the 40-level fixture (tests/fixtures/trail_screen.json,
## never the game's file) with a sandboxed save: a new save; mid-track with the line; a choice before and after; an
## optional node with its warning; three rails meeting; the dock in each state; a level done; the end plate; the
## Outlaws screen's "Reach Trail Level N" line, the Trail opened by a tap on it, and the way back. `bench=1` instead
## lays a 500-level Trail and scrolls it for 600 frames (use --fixed-fps 60): what a frame costs.
## Windowed and bounded (a watchdog quits after 170 s):
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --script res://tools/_p129_TRAIL_shots.gd -- out=<dir> [only=new,mid,...] [bench=1] [file=res://content/trail/trail.json]
extends SceneTree

const FIXTURE := "res://tests/fixtures/trail_screen.json"
const TRAIL := "res://ui/TrailScreen.tscn"
var _out := "user://p129_trail_shots"
var _only: Array = []
var _bench := false
var _file := FIXTURE
var _t0 := 0
var _save
var _trail


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a == "bench=1":
			_bench = true
		elif a.begins_with("file="):
			_file = a.substr(5)
	DirAccess.make_dir_recursive_absolute(_out)
	_t0 = Time.get_ticks_msec()
	process_frame.connect(_watch)
	process_frame.connect(_main, CONNECT_ONE_SHOT)


func _watch() -> void:
	if Time.get_ticks_msec() - _t0 > 170000:
		print("p129_trail_shots: watchdog")
		_end(2)


func _end(code: int) -> void:
	if _trail:
		_trail.load_from()
	if _save:
		_save.end_sandbox()
	quit(code)


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _frames(n: int) -> void:
	for k in range(n):
		await process_frame


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _shot(name: String) -> void:
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("p129_trail_shots: ", name)


## The save's Trail: these nodes bought, this much gold.
func _lend(bought: Array, gold: int) -> void:
	_save.data["trail"] = {"bought": bought.duplicate(), "spent": 0, "had": []}
	_save.data["gold"] = gold
	_save.data["heroes_owned"] = []
	_save.data["skins_owned"] = []
	_save.data.erase("board_note")
	_trail.refresh()


func _open(path: String = TRAIL) -> Node:
	change_scene_to_file(path)
	await _wait(0.5)
	await _frames(30)
	await _wait(0.4)
	return current_scene


## The Trail scrolled so level `l` is in the middle, node `id` chosen.
func _look(s, l: int, id: String = "") -> void:
	s.scroll.scroll_vertical = int(s._scroll_for(s._row_y(l)))
	await _frames(3)
	if id != "":
		s.select(id)
		await _wait(0.35)


func _main() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	_trail = load("res://core/systems/Trail.gd")
	var st = root.get_node("Settings")
	for k in ["debug_modal_buttons", "free_revive_button", "hit_log", "debug_panel", "debug_mode"]:
		st.set(k, false)
	if _bench:
		await _run_bench()
		_end(0)
		return
	_trail.load_from(_file)
	print("p129_trail_shots: %d nodes on %d levels from %s" % [_trail.nodes().size(), _trail.levels(), _file])
	var s
	if _want("new"):
		_lend([], 400)
		_save.data["board_note"] = {"kind": "trail_refund", "gold": 2400, "ranks": 6}
		s = await _open()
		await _shot("01_new_save")
	if _want("mid"):
		_lend(["n01", "n02", "n03a", "n04", "n05", "n06b", "n07a", "n07b"], 900)
		s = await _open()
		await _shot("02_mid_line")
		# three rails meet in the weapon's node; one of the three is still to buy
		await _look(s, 8, "n08")
		await _shot("03_meet3_locked")
		await _look(s, 4, "n04o")
		await _shot("04_optional_warn")
		await _look(s, 3, "n03b")
		await _shot("05_dock_closed")
		await _look(s, 3, "n03a")
		await _shot("06_dock_bought")
		await _look(s, 12, "n12a")
		await _shot("07_dock_locked_ahead")
	if _want("choice"):
		_lend(["n01", "n02", "n03a", "n04", "n05"], 300)
		s = await _open()
		await _look(s, 6, "n06a")
		await _shot("08_choice_before")
		s.press_buy()
		await _wait(0.6)
		await _shot("09_choice_confirm")
		var ask = null
		for c in s.get_children():
			if c.get_script() != null and str(c.get_script().get_global_name()) == "WConfirm":
				ask = c
		if ask:
			ask.confirm()
		await _wait(0.45)
		await _shot("10_choice_bought_levelup")
		await _wait(2.6)
		await _look(s, 6, "n06b")
		await _shot("11_choice_after")
	if _want("short"):
		_lend(["n01", "n02", "n03a", "n04", "n05", "n06b", "n07a", "n07b", "n07c", "n08"], 60)
		s = await _open()
		await _shot("12_four_choice_short")
	if _want("sections"):
		_lend(["n01"], 5000)
		s = await _open()
		await _look(s, 17)
		await _shot("13_sections_blend")
		await _look(s, 24, "n24")
		await _shot("14_milestone_ahead")
		await _look(s, 40)
		s.scroll.scroll_vertical = 0
		await _frames(4)
		await _shot("15_end_plate")
	if _want("done"):
		var all: Array = []
		for n in _trail.nodes():
			if not ["n03b", "n06a", "n06c", "n09b", "n09c", "n09d", "n20b", "n28b", "n28c"].has(str(n["id"])):
				all.append(str(n["id"]))
		_lend(all, 123456)
		s = await _open()
		s.scroll.scroll_vertical = 0
		await _frames(4)
		await _shot("16_all_done_top")
		await _look(s, 10, "n10o")
		await _shot("17_optionals_bought")
	if _want("nav"):
		_lend(["n01", "n02", "n03a", "n04"], 700)
		load("res://ui/HeroesScreen.gd").set("open_on", "calavera")
		s = await _open("res://ui/HeroesScreen.tscn")
		await _shot("18_outlaws_locked_line")
		var line = s.content.find_child("TrailLine", true, false)
		print("p129_trail_shots: the Outlaws line reads '%s'" % (str(line.find_child("Requirement", true, false).text) if line else "-"))
		if line:
			line.emit_signal("pressed")
		await _wait(0.9)
		await _frames(30)
		await _wait(0.5)
		print("p129_trail_shots: the tap opened %s, chosen %s" % [current_scene.scene_file_path, str(current_scene.get("selected"))])
		await _shot("19_trail_from_outlaws")
		current_scene.on_back()
		await _wait(0.9)
		await _frames(30)
		await _wait(0.5)
		print("p129_trail_shots: Back went to %s showing %s" % [current_scene.scene_file_path, str(current_scene.get("shown").id) if current_scene.get("shown") else "-"])
		await _shot("20_back_on_outlaws")
		s = await _open("res://ui/TitleScreen.tscn")
		await _shot("21_title_tab")
	print("p129_trail_shots: done")
	_end(0)


## A Trail of 500 levels (a node, now and then two, a choice of three, an optional one), bought to level 250, scrolled
## 37 px a frame for 600 frames: the frame's process time, the screen's own share, the draw calls, the nodes alive.
func _run_bench() -> void:
	var ups: Dictionary = _trail.read_file(FIXTURE)["upgrades"]
	var types: Array = ups.keys()
	var nodes: Array = []
	var bought: Array = []
	for l in range(1, 501):
		var t := str(types[l % types.size()])
		if l % 7 == 0:
			for k in 3:
				nodes.append({"id": "b%d_%d" % [l, k], "level": l, "kind": "choice", "group": "g%d" % l, "gives": {"type": "upgrade", "upgrade": t, "value": 0.01}})
			if l <= 250:
				bought.append("b%d_0" % l)
		elif l % 5 == 0:
			for k in 2:
				nodes.append({"id": "b%d_%d" % [l, k], "level": l, "kind": "node", "gives": {"type": "upgrade", "upgrade": t, "value": 0.01}})
				if l <= 250:
					bought.append("b%d_%d" % [l, k])
		else:
			nodes.append({"id": "b%d" % l, "level": l, "kind": "node", "gives": {"type": "upgrade", "upgrade": t, "value": 0.01}})
			if l <= 250:
				bought.append("b%d" % l)
			if l % 9 == 0:
				nodes.append({"id": "b%do" % l, "level": l, "kind": "optional", "gives": {"type": "upgrade", "upgrade": t, "value": 0.01}})
	var secs: Array = []
	var cols := [["f7b24a", "ef7d22", "cactus"], ["5a70d6", "2f3a8c", "moon"], ["d2b077", "9a7642", "dust"], ["c9463e", "7a2130", "skull"], ["45b3a4", "226a72", "star"]]
	for k in range(28):
		var c: Array = cols[k % cols.size()]
		secs.append({"from": 1 + k * 18, "name": "Section %d" % (k + 1), "top": c[0], "bottom": c[1], "motif": c[2]})
	_trail.load_data({"version": 1, "currency": "gold", "price": {"base": 40, "k": 1.5, "power": 2.0, "round": 10},
		"sections": secs, "upgrades": ups, "nodes": nodes, "end": {"text": "To be continued"}})
	_lend(bought, 1000000)
	var t_open := Time.get_ticks_usec()
	var s = await _open()
	print("p129_trail_shots: bench: %d nodes on %d levels, Trail Level %d, opened on level %d (scene up in %.0f ms incl. the waits)" % [
		_trail.nodes().size(), _trail.levels(), _trail.level(), s.centre_level(), (Time.get_ticks_usec() - t_open) / 1000.0])
	await _shot("bench_500_open")
	await _bench_loop(s, "500 levels")
	await _shot("bench_500_scrolled")
	# the same on the 40-level fixture, to compare
	_trail.load_from(FIXTURE)
	var some: Array = []
	for n in _trail.nodes():
		if int(n["level"]) <= 20 and not ["n03b", "n06a", "n06c", "n09b", "n09c", "n09d", "n20b"].has(str(n["id"])):
			some.append(str(n["id"]))
	_lend(some, 1000000)
	s = await _open()
	await _bench_loop(s, "40 levels")


## 120 frames at rest, then 600 frames scrolling 37 px a frame: the whole frame by the wall clock (the window is not
## synced), the screen's own laying and drawing, the draw calls and the nodes alive.
func _bench_loop(s, label: String) -> void:
	var script = load("res://ui/TrailScreen.gd")
	var rest: Array = []
	var t := Time.get_ticks_usec()
	for f in range(120):
		await process_frame
		var now := Time.get_ticks_usec()
		rest.append(float(now - t) / 1000.0)
		t = now
	var frame: Array = []
	var own: Array = []
	var dir := -37
	var max_sv := int(s._track_h - s._view_h())
	t = Time.get_ticks_usec()
	for f in range(600):
		var sv: int = s.scroll.scroll_vertical + dir
		if sv <= 0 or sv >= max_sv:
			dir = -dir
		s.scroll.scroll_vertical = clampi(sv, 0, max_sv)
		var before: int = script.get("bench_usec")
		await process_frame
		var now := Time.get_ticks_usec()
		frame.append(float(now - t) / 1000.0)
		t = now
		own.append(float(int(script.get("bench_usec")) - before) / 1000.0)
	rest.sort()
	frame.sort()
	own.sort()
	var mean := func(a: Array) -> float:
		var sum := 0.0
		for v: float in a:
			sum += v
		return sum / float(a.size())
	print("p129_trail_shots: bench %s: a frame at rest %.2f ms mean; scrolling 37 px a frame %.2f ms mean, %.2f p95, %.2f max; of that the Trail's own laying and drawing %.3f ms mean, %.3f p95, %.3f max" % [
		label, mean.call(rest), mean.call(frame), frame[569], frame[599], mean.call(own), own[569], own[599]])
	print("p129_trail_shots: bench %s: draw calls %d, nodes alive %d, tiles on the track %d (spare %d)" % [label,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		s._tiles.size(), s._spare.size()])
