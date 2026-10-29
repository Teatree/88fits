## The first scene: the loading screen (pass 58). Garry (2026-10-07): "for like a second or 2 right before the Main Menu
## loads I see a kind of a broken version of our Loading screen - with brown lines at the top and bottom visible ...
## maybe add a loading progress bar to the Loading Screen."
##
## Godot's boot splash shows art/ui/splash.png on the paper while the engine starts; on Android the system splash (the
## hat) stays over it until the engine's main loop begins (the export's --disable_godot_splash), so both cover the
## engine's own start and the autoloads (the Registry loads every content folder there), which happen before this scene
## exists and cannot show any progress. The picture is the loading screen at 0 %: the badge, the title, the line, the
## bar's empty track and its word (tools/make_splash.py). This scene draws that same picture at exactly the place and
## size the boot splash gave it (splash_rect: the engine's own rule for the stretch mode), so the switch cannot be seen,
## and fills the bar in brass. The title screen loads on a thread (ResourceLoader.load_threaded_request) and drives the
## bar; then it is built (its _ready: the live title builds Red Canyon there) and drawn for the first time under this
## screen, which stays on top until then and dissolves into it. It used to load the title in one call inside its first
## frame, so the boot splash's picture (with its ink bands floating in the paper on a 20:9 phone) stayed up for the
## whole load.
##
## Everything this screen shows is one opaque draw: the picture stretched on past its edges (they are paper, so the paper
## reaches the screen's edges) with the bar's fill painted in by its shader. A fade takes the same share of every pixel
## only when each pixel is drawn once: with a paper rect under the picture and the bar and its word drawn over it, the
## dissolve had shown two lines across a 20:9 screen at the picture's top and foot, and the bar had outlasted the rest
## (pass 58, review).
##
## The camera cutout's ink band (CutoutBand) waits while this screen shows (the boot splash cannot draw it, so it would
## pop in over the paper) and fades in with the title.
extends Control

const TITLE := "res://ui/TitleScreen.tscn"
const SPLASH := "res://art/ui/splash.png"
## The boot splash picture's size (tools/make_splash.py).
const SPLASH_SIZE := Vector2(1080, 1920)
## The bar's outer box and the top of its word's line box, in the picture's pixels. The bar's empty look (its hard
## shadow, its ink border, its aged track) and the word are in the picture under its last line; this screen paints the
## fill into the track (written by tools/make_splash.py, which lays the picture out round them).
const BAR := Rect2(280, 1364, 520, 34)
const LABEL_Y := 1419.0
const BAR_BORDER := 4
const BAR_SHADOW := 5
const LABEL_PX := 28

## How the bar shares out the boot, by the time each part took on the PC (pass 58, Boot as the first scene: the title's
## threaded load 360-530 ms, its build 230-265 ms (its _ready; the live stage's map is most of it), its first frame
## under this screen 10-15 ms): the load fills it to LOAD_END, the title's build to BUILT, its first frame to full.
const LOAD_END := 0.65
const BUILT := 0.95
## The loader reports few real steps (three for the title: 0, a quarter, done), so between them the bar creeps on
## towards the end of the part it is in (time constant CREEP_TAU, s) but stops CREEP_STOP of the way there: it only
## reaches a part's end once that part is done. It eases to every new value over EASE_TAU, and it never goes back.
const CREEP_TAU := 0.3
const CREEP_STOP := 0.85
const EASE_TAU := 0.05
## The longest frame the bar's creep and ease and the dissolve count (s). The first frame carries the engine's start
## (Godot's frame clock starts before the autoloads load; it caps the step at 8 physics ticks, about 0.13 s), which
## jumped the bar a fifth of the way in the very first frame; the frame before the dissolve carries the title's first
## full draw (74 ms on the PC, longer on a phone compiling its shaders), which swallowed the dissolve's first third, so
## on a slow phone it came close to a cut. Now the bar starts all but empty and the dissolve always takes its frames.
const MAX_STEP := 1.0 / 30.0
## The dissolve into the title (s, sine in and out).
const DISSOLVE := 0.25
## How long the title's threaded load may sit still (in progress, its progress not moving) before this screen stops
## waiting for it and loads the title at once (s).
const STALL := 10.0

## The one draw: the picture (filtered linearly, as the boot splash's use_filter does, and clamped at its edges, so
## past them it is the paper) with the brass fill mixed into the track as the bilinear filter would mix a picture that
## had the fill in it (each axis: the two nearest texels at the filter's weights; a texel of the track holds brass up to
## the fill's end and a share of one at the end), so the fill meets the ink border exactly as the picture's own edges do
## at any scale, with nothing drawn over the picture.
const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D picture : filter_linear, repeat_disable;
uniform vec2 picture_size = vec2(1080.0, 1920.0);
// the bar's track inside its ink border (x, y, w, h in the picture's pixels), its colour in the picture, the fill
uniform vec4 track = vec4(0.0);
uniform vec4 track_color = vec4(0.0);
uniform vec4 fill_color = vec4(1.0);
uniform float fill = 0.0;

varying vec2 pic;

void vertex() {
	pic = VERTEX;
}

float brass_x(float k) {
	return k >= track.x ? clamp(track.x + track.z * fill - k, 0.0, 1.0) : 0.0;
}

float brass_y(float k) {
	return (k >= track.y && k < track.y + track.w) ? 1.0 : 0.0;
}

void fragment() {
	vec2 edge = 0.5 / picture_size;
	vec4 c = texture(picture, clamp(pic / picture_size, edge, vec2(1.0) - edge));
	vec2 t = pic - 0.5;
	vec2 k = floor(t);
	vec2 f = t - k;
	float bx = mix(brass_x(k.x), brass_x(k.x + 1.0), f.x);
	float by = mix(brass_y(k.y), brass_y(k.y + 1.0), f.y);
	c.rgb += (fill_color.rgb - track_color.rgb) * (bx * by);
	COLOR = c * COLOR;
}
"""

signal handed_over(title: Node)
## The threaded load failed or stalled; the title is loaded at once straight after (tests mend a broken scene here).
signal load_failed(why: String)

## Where the title goes: null puts it under the root as the current scene (the game); a node takes it as a child and
## the current scene is left alone (tests).
var host: Node = null
## The title once it is built (tests, captures).
var title: Node = null
## Where the title is loaded from (tests point it at scenes of their own).
var title_path := TITLE
## STALL for this screen (tests).
var stall_limit := STALL
## The title could not be loaded at all: the screen says so under its word and stays (it never waits silently).
var failed := false
## Every value the bar has drawn, in order (tests: it only grows and ends full).
var history := PackedFloat32Array()
## Where the time went, in ms: "engine" (from the process start to this scene: the engine and the autoloads), "load"
## (the title's threaded load), "build" (its instancing and _ready), "first_frame" (its first frame, under this screen).
var timings := {}

var _art: Node2D
var _splash: Node2D
var _mat: ShaderMaterial
var _cover := Rect2()   # the canvas in the picture's pixels, a little wider: where the one draw goes
var _band: CanvasLayer
var _loading := false
var _t_load := 0
var _floor := 0.0       # what has really been reached
var _creep := 0.0       # where the creep has got to
var _cap := 0.0         # how far the creep may go in the part it is in
var _shown := 0.0       # what the bar draws
var _progress := -1.0   # the threaded load's last progress, and how long it has sat still (s)
var _still := 0.0
var _dissolve_t := -1.0 # the dissolve, 0..1 (below 0: not started)


func _ready() -> void:
	# pass 114 (lane REPLAY): a replay's process (tools/replay.py: `-- replay=<file>`) opens the replay viewer, never the
	# title; a prod build never does (and carries no viewer: export filter replay/*)
	if _open_replay():
		return
	timings["engine"] = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	get_viewport().size_changed.connect(_place)
	_place()
	_band = get_node_or_null("/root/CutoutBand") as CanvasLayer
	if _band:
		_band.visible = false
	if not Registry.problems.is_empty():
		for p in Registry.problems:
			push_warning("Content: " + str(p))
	_cap = LOAD_END * CREEP_STOP
	_show(0.0)
	if not ResourceLoader.exists(title_path):
		print("Boot: no title screen at %s; registry loaded %d weapons" % [title_path, Registry.weapons.size()])
		_fail()
		return
	_t_load = Time.get_ticks_usec()
	if _request() != OK:
		_recover("the threaded request was refused", false)
		return
	_loading = true


const REPLAY_VIEWER := "res://replay/ReplayViewer.gd"


func _open_replay() -> bool:
	if Settings.is_prod():
		return false
	var want := false
	for a in OS.get_cmdline_user_args():
		if str(a).trim_prefix("--").begins_with("replay="):
			want = true
	if not want or not ResourceLoader.exists(REPLAY_VIEWER):
		return false
	var script = load(REPLAY_VIEWER)
	if script == null:
		return false
	var v: Control = script.new()
	v.name = "ReplayViewer"
	get_tree().root.add_child.call_deferred(v)
	(func() -> void:
		get_tree().current_scene = v
		queue_free()).call_deferred()
	return true


## The picture, in the picture's own pixels inside `Art`, which _place puts where the boot splash drew it. Art is a
## Node2D: a Control's position is rounded to the canvas pixel (gui/common/snap_controls_to_pixels), and the boot
## splash's rect is not (on a 1344 px phone the picture would land 0.6 px low).
func _build() -> void:
	_art = Node2D.new()
	_art.name = "Art"
	add_child(_art)
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("picture", load(SPLASH) as Texture2D if ResourceLoader.exists(SPLASH) else null)
	_mat.set_shader_parameter("picture_size", SPLASH_SIZE)
	var inner := BAR.grow(-BAR_BORDER)
	_mat.set_shader_parameter("track", Vector4(inner.position.x, inner.position.y, inner.size.x, inner.size.y))
	_mat.set_shader_parameter("track_color", W.AGED)
	_mat.set_shader_parameter("fill_color", W.BRASS)
	_mat.set_shader_parameter("fill", 0.0)
	_splash = Node2D.new()
	_splash.name = "Splash"
	_splash.material = _mat
	_splash.draw.connect(_draw_splash)
	_art.add_child(_splash)


## Whether the picture is there to draw (a capture may hand the shader the PNG itself).
func has_picture() -> bool:
	return _mat != null and _mat.get_shader_parameter("picture") != null


func _draw_splash() -> void:
	if has_picture():
		_splash.draw_rect(_cover, Color.WHITE)


## Puts the picture where Godot's boot splash drew it: the boot splash's rect in the window's pixels (splash_rect with
## the project's stretch mode), brought into the canvas through the root's stretch. The one draw then covers the whole
## canvas, its corners taken into the picture's pixels.
func _place() -> void:
	var canvas := get_viewport_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var to_canvas := get_viewport().get_final_transform().affine_inverse()
	if win.x <= 0.0 or win.y <= 0.0 or DisplayServer.get_name() == "headless":
		# no window (tests): the canvas is the screen
		win = canvas
		to_canvas = Transform2D.IDENTITY
	var mode := int(ProjectSettings.get_setting("application/boot_splash/stretch_mode", 1))
	var r := splash_rect(SPLASH_SIZE, win, mode)
	var a := to_canvas * r.position
	var b := to_canvas * r.end
	var s := Vector2((b.x - a.x) / SPLASH_SIZE.x, (b.y - a.y) / SPLASH_SIZE.y)
	if s.x <= 0.0 or s.y <= 0.0:
		return
	_art.position = a
	_art.scale = s
	var lo := -a / s
	_cover = Rect2(lo, canvas / s).grow(4.0)
	_splash.queue_redraw()


## The rect Godot 4.7.2 draws the boot splash picture in, in the window's pixels: RenderingServerTypes::
## get_splash_stretched_screen_rect (servers/rendering/rendering_server_types.h) for each stretch mode. Keep (1, the
## project's) decides by the window's shape, not the picture's: a window taller than wide fits the picture to its width
## and centres it up and down (a 20:9 phone: paper above and below; a 3:4 tablet: the picture runs off the top and the
## foot), a wider one fits its height.
static func splash_rect(img: Vector2, win: Vector2, mode: int = 1) -> Rect2:
	var r := Rect2()
	match mode:
		0:  # Disabled: the picture's own size, in the middle
			r.size = img
			r.position = ((win - img) / 2.0).floor()
		1:  # Keep
			if win.x > win.y:
				r.size = Vector2(img.x * win.y / img.y, win.y)
				r.position.x = (win.x - r.size.x) / 2.0
			else:
				r.size = Vector2(win.x, img.y * win.x / img.x)
				r.position.y = (win.y - r.size.y) / 2.0
		2:  # Keep Width
			r.size = Vector2(win.x, img.y * win.x / img.x)
			r.position.y = (win.y - r.size.y) / 2.0
		3:  # Keep Height
			r.size = Vector2(img.x * win.y / img.y, win.y)
			r.position.x = (win.x - r.size.x) / 2.0
		4:  # Cover
			if win.x / win.y > img.x / img.y:
				r.size = Vector2(win.x, img.y * win.x / img.x)
				r.position.y = (win.y - r.size.y) / 2.0
			else:
				r.size = Vector2(img.x * win.y / img.y, win.y)
				r.position.x = (win.x - r.size.x) / 2.0
		_:  # Ignore
			r.size = win
	return r


func _process(delta: float) -> void:
	if _dissolve_t >= 0.0:
		if _step_dissolve(delta):
			queue_free()
		return
	if failed:
		return
	if _loading:
		_watch(delta)
	_advance(delta)


## The threaded load, once a frame: its progress drives the bar; loaded, the title is handed over; failed, or sat still
## for stall_limit, it is loaded at once instead.
func _watch(delta: float) -> void:
	var progress := []
	var status := _status(progress)
	var p := float(progress[0]) if not progress.is_empty() else 0.0
	_reach(LOAD_END * p)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			timings["load"] = (Time.get_ticks_usec() - _t_load) / 1000.0
			var scene := ResourceLoader.load_threaded_get(title_path) as PackedScene
			if scene:
				_hand_over(scene)
			else:
				_recover("it loaded as nothing", false)
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if p != _progress:
				_progress = p
				_still = 0.0
			else:
				_still += delta
				if _still >= stall_limit:
					_loading = false
					_recover("it sat at %d%% for %.0f s" % [roundi(p * 100.0), _still], false)
		_:
			_loading = false
			_recover("it failed (status %d)" % status, true)


## The threaded request and its status (tests stand in for them to fake a load that never moves).
func _request() -> int:
	return ResourceLoader.load_threaded_request(title_path)


func _status(progress: Array) -> int:
	return ResourceLoader.load_threaded_get_status(title_path, progress)


## The threaded load went wrong: the title is loaded at once, from its file. In Godot 4.7.2 a failed task stays
## registered under its path until it is fetched, and a plain load() or change_scene_to_file() of that path returns
## nothing meanwhile (the old fallback could never bring the title up), so a failed task is fetched first (`release`;
## never a task still in progress: fetching that would wait for it), and the file is read again past the cache and past
## any task on that path (CACHE_MODE_IGNORE). A title that cannot be read even so is said on the screen.
func _recover(why: String, release: bool) -> void:
	push_warning("Boot: the title's threaded load went wrong (%s); loading it at once" % why)
	if release:
		ResourceLoader.load_threaded_get(title_path)
	load_failed.emit(why)
	var scene := ResourceLoader.load(title_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		_fail()
		return
	if not timings.has("load"):
		timings["load"] = (Time.get_ticks_usec() - _t_load) / 1000.0
	_hand_over(scene)


## Nothing could bring the title up: the screen stays, its bar where it got to, and says so under its word.
func _fail() -> void:
	failed = true
	_loading = false
	push_warning("Boot: the title screen at %s could not be loaded" % title_path)
	if _art.get_node_or_null("Error"):
		return
	var line := W.serif_text("The title screen did not load. Please close the game and start it again.", 30, W.ROCK,
		600, false, HORIZONTAL_ALIGNMENT_CENTER, 40.0, true, false)
	line.name = "Error"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = Vector2(120.0, LABEL_Y + LABEL_PX * 2.5)
	line.size = Vector2(SPLASH_SIZE.x - 240.0, 80.0)
	_art.add_child(line)


## The bar between the real steps: the creep runs on towards its cap, the bar eases to the larger of the two.
func _advance(delta: float) -> void:
	var dt := minf(delta, MAX_STEP)
	_creep = maxf(_creep, _floor)
	if _creep < _cap:
		_creep += (_cap - _creep) * (1.0 - exp(-dt / CREEP_TAU))
	var target := maxf(_floor, _creep)
	_show(_shown + (target - _shown) * (1.0 - exp(-dt / EASE_TAU)))


## A real step reached.
func _reach(v: float) -> void:
	_floor = clampf(maxf(_floor, v), 0.0, 1.0)


## The bar at what has been reached (before a step that holds the frame, so it shows what is done).
func _snap() -> void:
	_show(maxf(_floor, _creep))


func _show(v: float) -> void:
	_shown = clampf(maxf(v, _shown), 0.0, 1.0)
	if _mat:
		_mat.set_shader_parameter("fill", _shown)
	history.append(_shown)


## What the bar draws now, 0..1 (tests, captures).
func bar_value() -> float:
	return _shown


## The title is loaded: build it under this screen, let it draw once, then dissolve into it. Each step waits a frame so
## the bar shows what is done before the next step holds the frame.
func _hand_over(scene: PackedScene) -> void:
	_reach(LOAD_END)
	_snap()
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	title = scene.instantiate()
	if title.scene_file_path.is_empty():
		# loaded past the cache (_recover): the path a change of scene would have left on it
		title.scene_file_path = title_path
	if host:
		host.add_child(title)
	else:
		var root := get_tree().root
		root.add_child(title)
		# this screen stays over the title until it has drawn
		root.move_child(self, -1)
		get_tree().current_scene = title
	# this screen dissolves into the title: its own fade-in (from the window's clear colour) would show through
	if title is CanvasItem:
		(title as CanvasItem).modulate.a = 1.0
	timings["build"] = (Time.get_ticks_usec() - t0) / 1000.0
	_cap = BUILT
	_reach(BUILT)
	_snap()
	t0 = Time.get_ticks_usec()
	# the title's first frame (its shaders, the stage's world) is drawn under this screen
	await get_tree().process_frame
	timings["first_frame"] = (Time.get_ticks_usec() - t0) / 1000.0
	_cap = 1.0
	_reach(1.0)
	_snap()
	await get_tree().process_frame
	print("Boot: engine and autoloads %d ms, title loaded in %d ms, built in %d ms, first frame %d ms" % [
		int(timings.get("engine", 0)), int(timings.get("load", 0)), int(timings.get("build", 0)),
		int(timings.get("first_frame", 0))])
	_dissolve()
	handed_over.emit(title)


## Starts fading this screen away over the title (and the cutout's band in): _process steps it.
func _dissolve() -> void:
	_set_mouse_ignore(self)
	# the one draw covers the paper rect from here on, so every pixel of this screen is drawn once
	var paper := get_node_or_null("ColorRect") as CanvasItem
	if paper and has_picture():
		paper.visible = false
	if _band:
		_band.visible = true
		for c in _band.get_children():
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = 0.0
	_dissolve_t = 0.0


## One frame of the dissolve, counting at most MAX_STEP: this screen's cover eases out (sine in and out) and the band
## eases in; true once it is done.
func _step_dissolve(delta: float) -> bool:
	_dissolve_t = minf(_dissolve_t + minf(delta, MAX_STEP) / DISSOLVE, 1.0)
	var k := 0.5 - 0.5 * cos(PI * _dissolve_t)
	modulate.a = 1.0 - k
	if _band and is_instance_valid(_band):
		for c in _band.get_children():
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = k
	return _dissolve_t >= 1.0


func _set_mouse_ignore(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_set_mouse_ignore(c)


## The band comes back whatever ended this screen.
func _exit_tree() -> void:
	if _band and is_instance_valid(_band):
		_band.visible = true
		for c in _band.get_children():
			if c is CanvasItem:
				(c as CanvasItem).modulate.a = 1.0
