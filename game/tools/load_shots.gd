## The loading screen frame by frame (pass 118, lane LOAD): the real Boot scene, the real title loading under it, frames
## saved at set moments of the screen's own clock (0, 0.15, 0.3, 0.5, 0.8, 1.2 s, and twice during the dissolve), so the
## fade-in, the drop, the landing, the motion and the hand-over can be checked by eye. Windowed, at a fixed 60 fps so
## the clock steps 1/60 a frame:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --script res://tools/load_shots.gd -- out=<dir> [tag=1080x1920] [tilt=<deg>]
## then `python tools/make_loading_wallpaper.py --sheet <dir>` lays them out with the strips' measured motion.
## The canvas follows the window's shape as on a phone (aspect expand: the PC's own "keep" would letterbox a 20:9 run).
## The save is sandboxed; it quits after 900 frames or 90 s, whichever comes first.
extends SceneTree

const MARKS := [0.0, 0.15, 0.3, 0.5, 0.7, 0.8, 1.0, 1.2]
const DISSOLVE_MARKS := [0.35, 0.7]
const MAX_FRAMES := 900

var _out := ""
var _tag := ""
var _tilt := 0.0
var _tilt_set := false
var _boot = null
var _next := 0
var _next_d := 0
var _frames := 0
var _save: Node
var _done := false
var _log: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			_out = a.substr(4)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a.begins_with("tilt="):
			_tilt = float(a.substr(5))
			_tilt_set = true
	if _out.is_empty():
		push_error("load_shots: out=<dir> is needed")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	create_timer(90.0, true, false, true).timeout.connect(func() -> void:
		push_error("load_shots: watchdog")
		_finish(3))
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_save = root.get_node("Save")
	_save.begin_sandbox()
	root.get_node("Settings").menu_style = "live"
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if _tag.is_empty():
		var s := root.get_visible_rect().size
		_tag = "%dx%d" % [int(s.x), int(s.y)]
	_boot = load("res://ui/Boot.tscn").instantiate()
	root.add_child(_boot)
	current_scene = _boot
	if _tilt_set:
		var mat := (_boot.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
		mat.set_shader_parameter("tilt", deg_to_rad(_tilt))
	RenderingServer.frame_post_draw.connect(_after_draw)


## After each drawn frame: the screen's clock decides whether this frame is one to keep.
func _after_draw() -> void:
	if _done:
		return
	_frames += 1
	if _frames > MAX_FRAMES:
		push_error("load_shots: no dissolve after %d frames" % MAX_FRAMES)
		_finish(4)
		return
	if not is_instance_valid(_boot):
		_finish(0 if _next_d >= DISSOLVE_MARKS.size() else 5)
		return
	var t: float = _boot.clock()
	if _next < MARKS.size() and t >= float(MARKS[_next]) - 0.0001:
		_shot("t%04d" % roundi(float(MARKS[_next]) * 1000.0), t)
		_next += 1
	var d: float = _boot._dissolve_t
	if _next_d < DISSOLVE_MARKS.size() and d >= float(DISSOLVE_MARKS[_next_d]):
		_shot("dissolve%02d" % roundi(float(DISSOLVE_MARKS[_next_d]) * 100.0), t)
		_next_d += 1


func _shot(name: String, t: float) -> void:
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := "%s/%s_%s.png" % [_out, _tag, name]
	img.save_png(path)
	var mat := (_boot.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	var row := {
		"file": path.get_file(), "clock": t, "frame": _frames, "fade": mat.get_shader_parameter("fade"),
		"drift": mat.get_shader_parameter("drift"), "first_strip": mat.get_shader_parameter("first_strip"),
		"strip_y": Array(mat.get_shader_parameter("strip_y") as PackedFloat32Array),
		"plate_foot": [mat.get_shader_parameter("plate_foot").x, mat.get_shader_parameter("plate_foot").y],
		"plate_scale": [mat.get_shader_parameter("plate_scale").x, mat.get_shader_parameter("plate_scale").y],
		"plate_on": mat.get_shader_parameter("plate_on"), "dust_t": mat.get_shader_parameter("dust_t"),
		"dissolve": _boot._dissolve_t, "events": _boot.events.duplicate(true), "size": [img.get_width(), img.get_height()],
	}
	_log.append(row)
	print("load_shots: %s at %.3f s (frame %d)" % [path.get_file(), t, _frames])


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	var f := FileAccess.open("%s/%s_shots.json" % [_out, _tag], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"tag": _tag, "tilt": _tilt, "shots": _log}, "  "))
		f.close()
	if _save:
		_save.end_sandbox()
	quit(code)
