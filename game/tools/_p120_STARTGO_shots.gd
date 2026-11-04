## Pass 120 (lane STARTGO): the way into a run frame by frame. The real title (Painted, or Live with style=live), a real
## finger on PLAY (a fresh stage 1: the save's beaten stages are cleared in the sandbox, so PLAY starts the run), then
## every frame of the revolver wipe, of the loading screen's reveal and of the open on the run, the loading screen at
## steps of its clock, the frames round the run's build, and the run's landing after the curtain has gone.
##   GODOT_TIMEOUT=300 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --script res://tools/_p120_STARTGO_shots.gd -- out=<dir> [style=painted|live]
##       [tag=<name>] [png=1]
## Sequences are saved as JPEG (q 0.92) and six key frames as PNG too (png=1: every frame as PNG). <tag>_shots.json logs
## every shot: the curtain's phase and clocks, the cylinder's pose, the run's landing clock. The save is sandboxed; it
## quits after MAX_FRAMES frames or 150 s, whichever comes first.
extends SceneTree

const MAX_FRAMES := 1500
const TITLE_SETTLE := 100      # frames the title gets before the tap (its entrance has played)
const LOAD_EVERY := 0.1        # the loading screen's clock between two shots once it is open
const AFTER_FRAMES := 168      # the run after the curtain: its landing
const AFTER_EVERY := 6
const KEY := ["a_title", "b_wipe_08", "b_wipe_20", "c_reveal_06", "d_load_t1000", "e_open_10"]

var _out := ""
var _tag := ""
var _style := "painted"
var _all_png := false
var _save: Node
var _stage := "title"
var _frames := 0
var _title_frames := 0
var _tap_at := Vector2.ZERO
var _curtain: Node = null
var _counts := {}
var _next_load := 0.0
var _after := 0
var _seen_built := false
var _log: Array = []
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("style="):
			_style = a.substr(6)
		elif a == "png=1":
			_all_png = true
	if _out.is_empty():
		push_error("_p120_STARTGO_shots: out=<dir> is needed")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		push_error("_p120_STARTGO_shots: watchdog")
		_finish(3))
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	# a fresh stage 1: PLAY starts the run (with stage 1 beaten it opens the Stages menu)
	_save.data["stages_beaten"] = {}
	_save.data["last_map"] = "red_canyon"
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if _tag.is_empty():
		var s := root.get_visible_rect().size
		_tag = "%s_%dx%d" % [_style, int(s.x), int(s.y)]
	change_scene_to_file("res://ui/TitleScreen.tscn")
	RenderingServer.frame_post_draw.connect(_after_draw)


func _touch(at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = down
	root.push_input(e, true)


func _find_curtain() -> Node:
	for n in root.get_children():
		if n is CanvasLayer and str(n.name).begins_with("RunCurtain") and n.get_child_count() > 0:
			return n.get_child(0)
	return null


## After each drawn frame: where the way into the run is decides whether this frame is one to keep.
func _after_draw() -> void:
	if _done:
		return
	_frames += 1
	if _frames > MAX_FRAMES:
		push_error("_p120_STARTGO_shots: not done after %d frames (stage %s)" % [MAX_FRAMES, _stage])
		_finish(4)
		return
	match _stage:
		"title":
			_title_frames += 1
			if _title_frames == TITLE_SETTLE:
				var t := current_scene
				var play: Control = t.get("_play") if t else null
				if play == null:
					push_error("_p120_STARTGO_shots: no PLAY on the title")
					_finish(5)
					return
				_shot("a_title", {})
				_tap_at = play.get_global_rect().get_center()
				_touch(_tap_at, true)
			elif _title_frames == TITLE_SETTLE + 3:
				_touch(_tap_at, false)
				_stage = "tapped"
		"tapped", "curtain":
			var c := _find_curtain()
			if c == null:
				if _stage == "curtain":
					_stage = "after"
					_shot_after()
				elif _title_frames > TITLE_SETTLE + 20:
					push_error("_p120_STARTGO_shots: the tap on PLAY raised no curtain")
					_finish(6)
				else:
					_title_frames += 1
				return
			_stage = "curtain"
			_curtain = c
			_shot_curtain(c)
		"after":
			_shot_after()


func _shot_curtain(c: Node) -> void:
	var phase := int(c.get("phase"))
	var clock: float = c.call("clock")
	var info := {"phase": phase, "wipe_clock": c.call("wipe_clock"), "clock": clock, "pose": _pose(c),
		"events": (c.get("events") as Array).duplicate(true), "blocking": c.call("blocking")}
	var g := current_scene
	if g and g.get("_spawn_t") != null:
		info["spawn_t"] = g.get("_spawn_t")
		info["spawning"] = g.get("spawning")
	match phase:
		0:
			_shot("b_wipe_%02d" % _count("b"), info)
		1:
			var built: bool = float(c.call("event_time", "built")) >= 0.0
			if clock <= 0.35:
				_shot("c_reveal_%02d" % _count("c"), info)
			elif built and not _seen_built:
				_seen_built = true
				_shot("d_built", info)
			elif clock >= _next_load:
				_shot("d_load_t%04d" % roundi(clock * 1000.0), info)
			if clock >= _next_load:
				_next_load = (floorf(clock / LOAD_EVERY) + 1.0) * LOAD_EVERY
		_:
			_shot("e_open_%02d" % _count("e"), info)


func _shot_after() -> void:
	if _after % AFTER_EVERY == 0:
		var g := current_scene
		var info := {}
		if g and g.get("_spawn_t") != null:
			info = {"spawn_t": g.get("_spawn_t"), "spawning": g.get("spawning")}
		_shot("f_run_%03d" % _after, info)
	_after += 1
	if _after >= AFTER_FRAMES:
		_finish(0)


func _count(k: String) -> int:
	var n := int(_counts.get(k, 0))
	_counts[k] = n + 1
	return n


func _pose(c: Node) -> Dictionary:
	var p: Dictionary = c.call("iris_pose")
	var m: Vector2 = p["mid"]
	return {"mode": p["mode"], "mid": [m.x, m.y], "r": p["r"], "turn": p["turn"], "chamber": p["chamber"],
		"pin": p["pin"], "shade": p["shade"]}


func _shot(name: String, info: Dictionary) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var base := "%s/%s_%s" % [_out, _tag, name]
	img.save_jpg(base + ".jpg", 0.92)
	if _all_png or KEY.has(name):
		img.save_png(base + ".png")
	var row := info.duplicate(true)
	row["file"] = (base + ".jpg").get_file()
	row["frame"] = _frames
	row["size"] = [img.get_width(), img.get_height()]
	_log.append(row)


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	var f := FileAccess.open("%s/%s_shots.json" % [_out, _tag], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"tag": _tag, "style": _style, "shots": _log}, "  "))
		f.close()
	print("_p120_STARTGO_shots: %d shots, %d frames, code %d" % [_log.size(), _frames, code])
	if _save:
		_save.end_sandbox()
	quit(code)
