## The loading screen frame by frame (pass 118, lane LOAD): the real Boot scene, the real title loading under it, frames
## saved at set moments of the screen's own clock (MARKS, and twice during the dissolve), so the fade-in, the slam, the
## hit, the motion and the hand-over can be checked by eye. Windowed, at a fixed 60 fps so the clock steps 1/60 a frame:
##   GODOT_TIMEOUT=240 bash tools/godot.sh --audio-driver Dummy --resolution 1080x1920 --fixed-fps 60 \
##       --path D:/_projects/88fits/game --script res://tools/load_shots.gd -- out=<dir> [tag=1080x1920] [tilt=<deg>]
##       [entrance=punch|split] [style=painted|live] [marks=0.3,0.42,...]
## Pass 119 (lane LOADUI): the marks follow the slam (each frame of the punch, the hit-stop, the shake, the glint);
## `entrance=` plays the other entrance tried; `style=` is the title's look under the dissolve (default painted, the
## game's default since pass 119); `marks=` other moments.
## then `python tools/make_loading_wallpaper.py --sheet <dir>` lays them out with the strips' measured motion.
## The canvas follows the window's shape as on a phone (aspect expand: the PC's own "keep" would letterbox a 20:9 run).
## The save is sandboxed; it quits after 900 frames or 90 s, whichever comes first.
extends SceneTree

const MARKS := [0.0, 0.2, 0.3333, 0.3667, 0.4, 0.4167, 0.4333, 0.4833, 0.5167, 0.55, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1]
const DISSOLVE_MARKS := [0.35, 0.7]
const MAX_FRAMES := 900

var _out := ""
var _tag := ""
var _tilt := 0.0
var _tilt_set := false
var _entrance := ""
var _style := "painted"
var _marks: Array = MARKS
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
		elif a.begins_with("entrance="):
			_entrance = a.substr(9)
		elif a.begins_with("style="):
			_style = a.substr(6)
		elif a.begins_with("marks="):
			_marks = []
			for m in a.substr(6).split(","):
				_marks.append(float(m))
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
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if _tag.is_empty():
		var s := root.get_visible_rect().size
		_tag = "%dx%d" % [int(s.x), int(s.y)]
	_boot = load("res://ui/Boot.tscn").instantiate()
	if not _entrance.is_empty():
		_boot.entrance = _entrance
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
	if _next < _marks.size() and t >= float(_marks[_next]) - 0.0001:
		_shot("t%04d" % roundi(float(_marks[_next]) * 1000.0), t)
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
		"plate_mid": [mat.get_shader_parameter("plate_mid").x, mat.get_shader_parameter("plate_mid").y],
		"plate_foot": [_boot.plate_rest_foot().x, _boot.plate_rest_foot().y],
		"plate_scale": mat.get_shader_parameter("plate_scale"), "split_off": mat.get_shader_parameter("split_off"),
		"plate_alpha": mat.get_shader_parameter("plate_alpha"), "speed": mat.get_shader_parameter("speed"),
		"plate_on": mat.get_shader_parameter("plate_on"), "hit_t": mat.get_shader_parameter("hit_t"),
		"flash": mat.get_shader_parameter("flash"), "glint_t": mat.get_shader_parameter("glint_t"),
		"shake": [mat.get_shader_parameter("shake").x, mat.get_shader_parameter("shake").y], "entrance": _boot.entrance,
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
		f.store_string(JSON.stringify({"tag": _tag, "tilt": _tilt, "entrance": _entrance, "style": _style, "shots": _log},
			"  "))
		f.close()
	if _save:
		_save.end_sandbox()
	quit(code)
