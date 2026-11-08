## Pass 136 (lane LOAD; Garry: "the first time Player starts up a game, and goes into a run, it takes quite a while for the
## first level to load ... the loading screen doesn't move while the game is loading"): the way into a run timed from the
## tap to the first frame of play, on a fresh game process (the session's first run) and again (PLAY AGAIN's route).
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --path D:/_projects/88fits/game \
##       --log-file <abs> --script res://tools/_p136_LOAD_probe.gd -- stage=1|2 out=<abs json> [idle=3] [runs=2] [tag=<name>]
## Stage 1: a fresh save's PLAY on the title (it starts stage 1). Stage 2: stage 1 marked beaten in the sandbox, PLAY opens
## the Stages menu, the Nightfall card is started (StagesScreen.start, what its tap calls). The title (and the menu) idle
## `idle` s before the tap, as a player looks at them. Each run: total (the tap to the frame the curtain opens on the
## run), the longest frame between them (the freeze), frames over 100 ms, the curtain's own timings and events, and the
## first 3 s of play after the open (its longest frame, frames over 100 ms). The Drifter. The save is sandboxed.
extends SceneTree

const SLOW_MS := 100.0
const AFTER_S := 3.0
const MAX_S := 150.0

var _out := ""
var _tag := ""
var _stage := 1
var _idle := 3.0
var _runs := 2
var _save: Node
var _state := "title"
var _state_t := 0.0
var _last_us := 0
var _run_k := 0
var _cur: Dictionary = {}
var _results: Array = []
var _curtain: Node = null
var _done := false
var _t_start := 0
## the title's and the menu's longest frame while they idle (past their first IDLE_SKIP s): what an ask ahead costs them
const IDLE_SKIP := 0.5
var _idle_max := 0.0
var _idle_over := 0
## profile=1: every node added to the tree while a run loads, timestamped (where the build frame's time goes)
var _profile := false
var _warmdbg := false
var _adds: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("out="):
			_out = s.substr(4)
		elif s.begins_with("tag="):
			_tag = s.substr(4)
		elif s.begins_with("stage="):
			_stage = int(s.substr(6))
		elif s.begins_with("idle="):
			_idle = float(s.substr(5))
		elif s.begins_with("runs="):
			_runs = int(s.substr(5))
		elif s == "profile=1":
			_profile = true
		elif s == "warmdbg=1":
			_warmdbg = true
	create_timer(MAX_S, true, false, true).timeout.connect(func() -> void:
		push_error("_p136_LOAD_probe: watchdog in state %s" % _state)
		_finish(3))
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_t_start = Time.get_ticks_msec()
	_save = root.get_node("Save")
	_save.begin_sandbox()
	_save.data["stages_beaten"] = {}
	_save.data["last_map"] = "red_canyon"
	_save.data["last_character"] = "drifter"
	if _stage >= 2:
		_save.mark_stage_beaten("red_canyon", 0)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	change_scene_to_file("res://ui/TitleScreen.tscn")
	_last_us = Time.get_ticks_usec()
	process_frame.connect(_tick)
	if _profile:
		node_added.connect(func(n: Node) -> void:
			if _state == "loading":
				_adds.append([Time.get_ticks_usec(), str(n.get_path())]))


func _find_curtain() -> Node:
	for n in root.get_children():
		if n is CanvasLayer and str(n.name).begins_with("RunCurtain") and n.get_child_count() > 0:
			return n.get_child(0)
	return null


func _touch(at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = down
	root.push_input(e, true)


func _tick() -> void:
	if _done:
		return
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0
	_last_us = now
	_state_t += dt / 1000.0
	if (_state == "title" or _state == "menu") and _state_t > IDLE_SKIP:
		_idle_max = maxf(_idle_max, dt)
		if dt > 50.0:
			_idle_over += 1
	match _state:
		"title":
			var t := current_scene
			if t == null or t.get("_play") == null or _state_t < _idle:
				return
			var play: Control = t.get("_play")
			var at := play.get_global_rect().get_center()
			if _stage >= 2:
				_touch(at, true)
				_touch(at, false)
				_go("menu")
			else:
				_begin_run()
				_touch(at, true)
				_touch(at, false)
		"menu":
			var m := current_scene
			if m == null or not m.has_method("start") or m.get_script() == null \
					or not str(m.get_script().resource_path).ends_with("StagesScreen.gd"):
				if _state_t > 20.0:
					push_error("_p136_LOAD_probe: no Stages menu")
					_finish(5)
				return
			if _state_t < _idle:
				return
			_begin_run()
			m.call("start", _stage - 1)
		"loading":
			_cur["frames"] += 1
			_cur["frame_ms"].append(dt)
			var c := _find_curtain()
			if c != null:
				_curtain = c
			if _warmdbg and current_scene != null and current_scene.get_node_or_null("Warmup") != null:
				var w := current_scene.get_node("Warmup")
				print("p136_warm: f%d steps_done %s drawn %d can_process %s paused %s" % [int(_cur["frames"]), str(w.get("_steps_done")),
					int(w.get("_drawn_frames")), str(w.can_process()), str(paused)])
			if _curtain != null and is_instance_valid(_curtain) and int(_curtain.get("phase")) == 2:
				_cur["total_ms"] = (now - int(_cur["t0"])) / 1000.0
				_cur["curtain_timings"] = (_curtain.get("timings") as Dictionary).duplicate()
				_cur["curtain_events"] = (_curtain.get("events") as Array).duplicate(true)
				_cur["curtain_clock"] = float(_curtain.call("clock"))
				_go("after")
			elif _state_t > 60.0:
				push_error("_p136_LOAD_probe: the run never opened")
				_finish(4)
		"after":
			_cur["after_ms"].append(dt)
			if _state_t >= AFTER_S:
				_close_run()
				_run_k += 1
				if _run_k >= _runs:
					_finish(0)
					return
				# the second run: PLAY AGAIN's route (ResultsScreen: Run.choose_stage, UiFx.go_run)
				_begin_run()
				root.get_node("Run").call("choose_stage", _stage - 1)
				load("res://ui/UiFx.gd").go_run(self)


func _go(s: String) -> void:
	_state = s
	_state_t = 0.0


func _begin_run() -> void:
	_curtain = null
	_cur = {"run": _run_k + 1, "stage": _stage, "t0": Time.get_ticks_usec(), "frames": 0, "frame_ms": [], "after_ms": [],
		"idle_max_ms": _idle_max, "idle_over_50": _idle_over}
	var la = load("res://core/data/LookArt.gd")
	_cur["strips_pending_at_tap"] = la.pending()
	_cur["thread_loads"] = la.thread_loads
	_idle_max = 0.0
	_idle_over = 0
	_go("loading")


func _close_run() -> void:
	var fr: Array = _cur["frame_ms"]
	var af: Array = _cur["after_ms"]
	_cur["max_frame_ms"] = _maxa(fr)
	_cur["slow_frames"] = _count_over(fr)
	_cur["after_max_ms"] = _maxa(af)
	var t_after := 0.0
	var late: Array = []
	for x in af:
		t_after += float(x)
		if float(x) > 50.0:
			late.append("%.0f ms at +%.2f s" % [float(x), t_after / 1000.0])
	_cur["after_slow_at"] = late
	if not late.is_empty():
		print("p136_load:    after the open, frames over 50 ms: %s" % str(late))
	_cur["after_slow"] = _count_over(af)
	var top := fr.duplicate()
	top.sort()
	top.reverse()
	_cur["top5"] = top.slice(0, 5)
	_cur.erase("frame_ms")
	_cur.erase("after_ms")
	_cur.erase("t0")
	_cur["frame_ms_all"] = fr
	if _profile and _adds.size() > 1:
		var gaps: Array = []
		for k in range(1, _adds.size()):
			gaps.append([(int(_adds[k][0]) - int(_adds[k - 1][0])) / 1000.0, str(_adds[k - 1][1]), str(_adds[k][1])])
		gaps.sort_custom(func(a, b): return a[0] > b[0])
		for k in range(mini(25, gaps.size())):
			print("p136_prof:   %.0f ms  after %s  before %s" % gaps[k])
		print("p136_prof:   %d nodes added, first..last %.0f ms" % [_adds.size(), (int(_adds[-1][0]) - int(_adds[0][0])) / 1000.0])
		# the time before each node's addition, by its first three path parts (gaps over 300 ms are frames, left out)
		var by := {}
		for k in range(1, _adds.size()):
			var g := (int(_adds[k][0]) - int(_adds[k - 1][0])) / 1000.0
			if g > 300.0:
				continue
			var parts := str(_adds[k][1]).split("/", false)
			var key := "/".join(parts.slice(0, mini(5 if str(_adds[k][1]).begins_with("/root/Game/World/RedCanyon") else 3, parts.size())))
			by[key] = float(by.get(key, 0.0)) + g
		var rows: Array = []
		for key in by:
			rows.append([by[key], key])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for k in range(mini(20, rows.size())):
			print("p136_prof:   by part %.0f ms  %s" % rows[k])
		_adds.clear()
	print("p136_load: %s stage %d run %d: total %.0f ms, longest frame %.0f ms, %d frames over %d ms (of %d); after the open: longest %.0f ms, %d over; curtain %s" % [
		_tag, _stage, int(_cur["run"]), float(_cur.get("total_ms", -1)), float(_cur["max_frame_ms"]), int(_cur["slow_frames"]),
		int(SLOW_MS), int(_cur["frames"]), float(_cur["after_max_ms"]), int(_cur["after_slow"]), str(_cur.get("curtain_timings", {}))])
	print("p136_load:    top frames %s; title/menu idle: longest %.0f ms, %d over 50 ms; report %s" % [str(_cur["top5"]),
		float(_cur["idle_max_ms"]), int(_cur["idle_over_50"]), str((_cur.get("curtain_timings", {}) as Dictionary).get("report", {}))])
	_results.append(_cur)


func _maxa(a: Array) -> float:
	var m := 0.0
	for x in a:
		m = maxf(m, float(x))
	return m


func _count_over(a: Array) -> int:
	var n := 0
	for x in a:
		if float(x) > SLOW_MS:
			n += 1
	return n


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"tag": _tag, "stage": _stage, "idle": _idle, "runs": _results}, "  "))
			f.close()
	print("p136_load: done, code %d, %d runs" % [code, _results.size()])
	if _save:
		_save.end_sandbox()
	quit(code)
