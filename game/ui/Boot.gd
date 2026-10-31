## The first scene: the loading screen. Pass 58 made it (Garry, 2026-10-07: "for like a second or 2 right before the Main
## Menu loads I see a kind of a broken version of our Loading screen ... maybe add a loading progress bar"); pass 118
## (lane LOAD) remade it. Garry: "No icon, No progress bar. Title Drop sequence at the start and an animation of
## silhuettes of revolvers, stars, bombs, boots and other western(y) and not so western(y) item silhouettes that read
## well. They are meant to look like strips of saloon wallpaper and each strip moves slowly up-and a bit to the right,
## down-and a bit to the right ... This is meant to be the new progress bar replacement showing that the game is loading."
##
## Godot's boot splash is the plain paper now (application/boot_splash/show_image off: the engine draws only bg_color,
## W.PAPER), and on Android the system splash is the same paper with a transparent icon (tools/make_splash.py). This
## scene's first frame is that paper too, on any screen, so the hand-over from the engine cannot be seen. Then:
##   - the saloon wallpaper fades in from the paper (FADE_IN): vertical strips side by side in two tones with a pinstripe
##     between them, each carrying a tone-on-tone print of silhouettes (the strip atlas, art/ui/loading/wallpaper.png,
##     tools/make_loading_wallpaper.py); strip 1 scrolls slowly up, strip 2 down, strip 3 up ..., and the whole set
##     drifts slowly to the right (it wraps). The motion is the loading indicator: it never stops while the game loads.
##   - the game's name drops in from above on its plate (art/ui/loading/title_plate.png, set like the title screen's
##     logo) and lands with weight: a stretch as it falls, a squash and a bounce, a puff of dust, a thud (ui_stamp).
##   - the title screen loads on a thread meanwhile (ResourceLoader.load_threaded_request). It is built (its _ready: the
##     live title builds Red Canyon there, a frame of a few hundred ms) only once the plate has settled, so that frame
##     never stops the drop half way, and it draws once under this screen; then this screen dissolves into it, never
##     before MIN_SHOW of its own clock, even when the load was done sooner.
##
## Everything this screen shows is one opaque draw: one shader over one full-screen rect paints the wallpaper, the dust
## and the plate (two textures, no node per silhouette). A fade takes the same share of every pixel only when each pixel
## is drawn once (pass 58's review: layered draws showed through each other during the dissolve).
##
## The screen's clock counts each frame at most MAX_STEP, so a long frame (the engine's start in the first one, the
## title's build, its first draw) pauses the motion instead of throwing it forward; the first frame does not count at
## all, so it is the plain paper whatever its length.
##
## The camera cutout's ink band (CutoutBand) waits while this screen shows (the boot splash cannot draw it, so it would
## pop in over the paper) and fades in with the title.
extends Control

const TITLE := "res://ui/TitleScreen.tscn"
const WALLPAPER := "res://art/ui/loading/wallpaper.png"
const PLATE := "res://art/ui/loading/title_plate.png"

## The atlas's layout, in canvas px (tools/make_loading_wallpaper.py writes these lines): each strip STRIP_W wide, its
## print repeating every PERIOD, VARIANTS strips of different motif orders side by side in the texture.
const STRIP_W := 180.0
const PERIOD := 1440.0
const VARIANTS := 4
## The plate's picture in canvas px (its hard shadow and a clear margin included) and its shadow's offset.
const PLATE_SIZE := Vector2(930.0, 312.7)
const PLATE_SHADOW := 14.0

## The wallpaper's motion, canvas px a second: each strip's scroll (up, down, up ...) and the set's drift to the right.
const SCROLL := 46.0
const DRIFT := 15.0
## The strips' lean (degrees; 0 = upright). Captures with a lean are in tools/dl/p118/LOAD/; upright read better.
const TILT_DEG := 0.0
## The most strips the screen can show at once, a lean included (the shader's strip_y array).
const MAX_STRIPS := 12

## The sequence (s on the screen's clock): the wallpaper fades in from the paper, then the plate drops from above the
## screen to its rest, squashes on the landing, bounces once and settles.
const FADE_IN := 0.3
const DROP_AT := 0.3
const FALL := 0.34
const SQUASH := 0.08
const BOUNCE := 0.22
const SETTLE := 0.07
## How the plate leans into its motion: stretched along its fall, squashed on the landing, lifted by the bounce (px).
const STRETCH := 0.07
const SQUASH_Y := 0.15
const SQUASH_X := 0.08
const BOUNCE_H := 34.0
## Where the plate's middle rests, as a share of the screen's height (a little above the middle reads as the middle).
const REST_Y := 0.46
## The dust thrown up by the landing (s).
const DUST := 0.6
## The earliest the dissolve may start (s on the screen's clock): the plate has landed and been seen for a moment.
const MIN_SHOW := 1.2

## The longest frame the screen's clock counts (s). The first frame carries the engine's start (Godot's frame clock
## starts before the autoloads load), the title's build and its first draw each hold a frame; counted whole they would
## throw the drop or eat the dissolve (pass 58: on a slow phone the dissolve came close to a cut).
const MAX_STEP := 1.0 / 30.0
## The dissolve into the title (s, sine in and out).
const DISSOLVE := 0.25
## How long the title's threaded load may sit still (in progress, its progress not moving) before this screen stops
## waiting for it and loads the title at once (s).
const STALL := 10.0

## The thud as the plate lands: the first of these the sound map binds.
const THUD := ["ui_stamp", "ui_chest_knock"]

## The one draw. The wallpaper: each canvas px is turned by the lean about the screen's middle, moved left by the drift,
## and falls in a strip (index = floor(x / STRIP_W)); the strip's own vertical shift comes from strip_y (indexed from
## first_strip, set each frame from Boot.gd, which decides who goes up and who down); the atlas's masks are coloured
## with the strip's ground (two tones, alternating) and mixed in from the paper by `fade`. Then the dust
## rolling out from under the plate's foot where it landed (behind it), then the plate (its foot's middle at plate_foot, scaled about it).
const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D wallpaper : filter_linear, repeat_enable;
uniform sampler2D plate : filter_linear, repeat_disable;
uniform vec2 canvas = vec2(1080.0, 1920.0);
uniform float strip_w = 180.0;
uniform float period = 1440.0;
uniform float variants = 4.0;
uniform float drift = 0.0;
uniform float first_strip = 0.0;
uniform float strip_y[12];
uniform float tilt = 0.0;
uniform float fade = 0.0;
uniform vec4 paper = vec4(1.0);
uniform vec4 ground_a = vec4(1.0);
uniform vec4 ground_b = vec4(1.0);
uniform vec4 motif_color = vec4(0.0);
uniform vec4 accent_color = vec4(0.0);
uniform vec4 line_color = vec4(0.0);
uniform float vignette = 0.0;
uniform vec4 vignette_color = vec4(0.0);
uniform float plate_on = 0.0;
uniform vec2 plate_foot = vec2(0.0);
uniform vec2 plate_scale = vec2(1.0);
uniform vec2 plate_size = vec2(1.0);
uniform float dust_t = -1.0;
uniform vec2 dust_at = vec2(0.0);
uniform float dust_life = 0.6;
uniform vec4 dust_color = vec4(1.0);

varying vec2 pos;

void vertex() {
	pos = VERTEX;
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 mid = canvas * 0.5;
	vec2 q = pos - mid;
	float cs = cos(tilt);
	float sn = sin(tilt);
	vec2 p = vec2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y) + mid;
	float x = p.x - drift;
	float idx = floor(x / strip_w);
	int slot = clamp(int(idx - first_strip), 0, 11);
	float lx = clamp(x - idx * strip_w, 0.0, strip_w);
	float y = p.y - strip_y[slot];
	float v = mod(idx, variants);
	vec2 uv = vec2((v * strip_w + lx) / (variants * strip_w), fract(y / period));
	vec3 m = texture(wallpaper, uv).rgb;
	vec3 col = mod(idx, 2.0) < 0.5 ? ground_a.rgb : ground_b.rgb;
	col = mix(col, motif_color.rgb, m.r);
	col = mix(col, accent_color.rgb, m.g);
	col = mix(col, line_color.rgb, m.b);
	float r = length((pos - mid) / mid);
	col = mix(col, vignette_color.rgb, vignette * smoothstep(0.55, 1.35, r));
	col = mix(paper.rgb, col, fade);
	if (dust_t >= 0.0 && dust_t < dust_life) {
		float k = dust_t / dust_life;
		float ease = (1.0 - exp(-dust_t * 6.0)) / 6.0;
		float clear = 1.0;
		for (int i = 0; i < 16; i++) {
			float fi = float(i);
			float side = mod(fi, 2.0) < 0.5 ? -1.0 : 1.0;
			float j = floor(fi * 0.5) / 7.0;
			float h = hash(fi + 1.0);
			float h2 = hash(fi * 3.7 + 2.0);
			vec2 start = dust_at + vec2(side * plate_size.x * (0.06 + 0.44 * j + 0.03 * (h2 - 0.5)), -6.0 + 8.0 * h);
			vec2 vel = vec2(side * (80.0 + 520.0 * j + 140.0 * h), 30.0 + 60.0 * h2 - 260.0 * j * j * h2);
			vec2 c = start + vel * ease;
			float rad = (22.0 + 18.0 * h + 8.0 * j) * (0.75 + 1.6 * k);
			float a = pow(1.0 - k, 1.2) * 0.62;
			clear *= 1.0 - a * (1.0 - smoothstep(0.25, 1.0, length(pos - c) / rad));
		}
		col = mix(col, dust_color.rgb, 1.0 - clear);
	}
	if (plate_on > 0.5) {
		vec2 local = (pos - plate_foot) / plate_scale + vec2(plate_size.x * 0.5, plate_size.y);
		vec2 puv = local / plate_size;
		if (puv.x >= 0.0 && puv.y >= 0.0 && puv.x <= 1.0 && puv.y <= 1.0) {
			vec4 pc = texture(plate, puv);
			col = mix(col, pc.rgb, pc.a);
		}
	}
	COLOR = vec4(col, 1.0) * COLOR;
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
## The title could not be loaded at all: the screen says so under the plate, its wallpaper stops (it never waits
## silently, and never moves as if it were still loading).
var failed := false
## What happened when, in order, on the screen's clock: [name, s] ("fade_in", "landed", "settled", "loaded", "built",
## "first_frame", "dissolve") (tests: the plate lands before the dissolve; captures).
var events: Array = []
## Where the time went, in ms: "engine" (from the process start to this scene: the engine and the autoloads), "load"
## (the title's threaded load), "build" (its instancing and _ready), "first_frame" (its first frame, under this screen).
var timings := {}

var _wall: ColorRect
var _mat: ShaderMaterial
var _band: CanvasLayer
var _loading := false
var _t_load := 0
var _clock := 0.0        # the screen's own clock (s)
var _frames := 0
var _scene: PackedScene = null   # loaded, waiting for the plate to settle
var _handing := false
var _thud_done := false
var _progress := -1.0    # the threaded load's last progress, and how long it has sat still (s)
var _still := 0.0
var _dissolve_t := -1.0  # the dissolve, 0..1 (below 0: not started)
var _canvas := Vector2(1080, 1920)


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


## The one draw: a rect over the whole screen (over the paper ColorRect of Boot.tscn) with the shader and its two
## pictures, coloured from the kit's tokens (make_loading_wallpaper.py's palette() mirrors these mixes for its mock).
func _build() -> void:
	_wall = ColorRect.new()
	_wall.name = "Wallpaper"
	_wall.color = Color.WHITE
	_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_wall)
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("wallpaper", load(WALLPAPER) as Texture2D if ResourceLoader.exists(WALLPAPER) else null)
	_mat.set_shader_parameter("plate", load(PLATE) as Texture2D if ResourceLoader.exists(PLATE) else null)
	_mat.set_shader_parameter("strip_w", STRIP_W)
	_mat.set_shader_parameter("period", PERIOD)
	_mat.set_shader_parameter("variants", float(VARIANTS))
	_mat.set_shader_parameter("tilt", deg_to_rad(TILT_DEG))
	_mat.set_shader_parameter("plate_size", PLATE_SIZE)
	_mat.set_shader_parameter("dust_life", DUST)
	for k in PALETTE:
		_mat.set_shader_parameter(k, palette(k))
	_mat.set_shader_parameter("vignette", VIGNETTE)
	_wall.material = _mat
	_apply()


## The wallpaper's colours: the paper it fades in from, the two grounds of the strips, the print, the fillers and beads,
## the pinstripe, the vignette's warm shade and the dust, each a mix of two of the kit's tokens (W.gd).
const PALETTE := ["paper", "ground_a", "ground_b", "motif_color", "accent_color", "line_color", "vignette_color",
	"dust_color"]
const VIGNETTE := 0.35


static func palette(key: String) -> Color:
	match key:
		"paper", "ground_a":
			return W.PAPER
		"ground_b":
			return W.PAPER.lerp(W.AGED, 0.55)
		"motif_color":
			return W.PAPER.lerp(W.ROCK, 0.26)
		"accent_color":
			return W.PAPER.lerp(W.ROCK, 0.2)
		"line_color":
			return W.PAPER.lerp(W.INK_SOFT, 0.4)
		"vignette_color":
			return W.PAPER.lerp(W.ROCK, 0.3).lerp(W.INK, 0.12)
		"dust_color":
			return W.AGED.lerp(W.ROCK, 0.3)
	return W.PAPER


## Whether the wallpaper's atlas is there to draw (a capture may hand the shader the PNG itself).
func has_wallpaper() -> bool:
	return _mat != null and _mat.get_shader_parameter("wallpaper") != null


func _place() -> void:
	_canvas = get_viewport_rect().size
	if _mat:
		_mat.set_shader_parameter("canvas", _canvas)
		_apply()


func _process(delta: float) -> void:
	# the first frame is the plain paper, the boot splash's own colour, however long it took
	if _frames > 0 and not failed:
		_clock += minf(delta, MAX_STEP)
	_frames += 1
	_apply()
	if _dissolve_t >= 0.0:
		if _step_dissolve(delta):
			queue_free()
		return
	if failed:
		return
	if _loading:
		_watch(delta)
	if _scene != null and not _handing and is_settled():
		_handing = true
		_hand_over(_scene)


# ---------------------------------------------------------------- the sequence

## What the screen's clock reads (s; tests, captures).
func clock() -> float:
	return _clock


## The wallpaper's share over the paper, 0..1, at clock t (sine in and out).
static func fade_at(t: float) -> float:
	var k := clampf(t / FADE_IN, 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * k)


## Strip `index`'s direction: even strips scroll up (-1), odd ones down (+1).
static func strip_dir(index: int) -> float:
	return -1.0 if posmod(index, 2) == 0 else 1.0


## Strip `index`'s shift down at clock t (canvas px): a phase of its own (so neighbours never line up) plus its scroll.
static func strip_shift(index: int, t: float) -> float:
	return fposmod(index * 0.618034, 1.0) * PERIOD + strip_dir(index) * SCROLL * t


## The plate at s seconds after its drop began, Vector3(lift above its rest (px), scale x, scale y), its foot's middle
## the pivot; `fall` is how far above its rest it starts (px).
static func drop_pose(s: float, fall: float) -> Vector3:
	if s < 0.0:
		return Vector3(fall, 1.0, 1.0)
	if s < FALL:
		var u := s / FALL
		return Vector3(fall * (1.0 - u * u), 1.0 - STRETCH * 0.5 * u, 1.0 + STRETCH * u)
	s -= FALL
	if s < SQUASH:
		var q := sin(PI * s / SQUASH)
		return Vector3(0.0, 1.0 + SQUASH_X * q, 1.0 - SQUASH_Y * q)
	s -= SQUASH
	if s < BOUNCE:
		var k := s / BOUNCE
		var b := sin(PI * k)
		return Vector3(BOUNCE_H * 4.0 * k * (1.0 - k), 1.0 - 0.012 * b, 1.0 + 0.025 * b)
	s -= BOUNCE
	if s < SETTLE:
		var q := sin(PI * s / SETTLE)
		return Vector3(0.0, 1.0 + 0.025 * q, 1.0 - 0.045 * q)
	return Vector3(0.0, 1.0, 1.0)


## The plate has landed (first touched its rest) / settled (stopped moving), on the screen's clock.
func has_landed() -> bool:
	return _clock >= DROP_AT + FALL


func is_settled() -> bool:
	return _clock >= DROP_AT + FALL + SQUASH + BOUNCE + SETTLE


## Where the plate's foot rests (canvas px): its middle at REST_Y of the screen's height.
func plate_rest_foot() -> Vector2:
	return Vector2(_canvas.x * 0.5, roundf(_canvas.y * REST_Y + PLATE_SIZE.y * 0.5))


## The plate's foot and scale now (tests, captures).
func plate_pose() -> Vector3:
	var rest := plate_rest_foot()
	return drop_pose(_clock - DROP_AT, rest.y + 12.0)


## Every uniform that moves, from the screen's clock.
func _apply() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("fade", fade_at(_clock))
	# the strips the screen shows: from the leftmost one any corner of the (leaned) screen reaches
	var drift := DRIFT * _clock
	var tilt := deg_to_rad(TILT_DEG)
	var mid := _canvas * 0.5
	var lo := INF
	for c: Vector2 in [Vector2.ZERO, Vector2(_canvas.x, 0.0), Vector2(0.0, _canvas.y), _canvas]:
		var q := c - mid
		lo = minf(lo, cos(tilt) * q.x + sin(tilt) * q.y + mid.x)
	var first := floori((lo - drift) / STRIP_W) - 1
	var ys := PackedFloat32Array()
	ys.resize(MAX_STRIPS)
	for k in MAX_STRIPS:
		ys[k] = strip_shift(first + k, _clock)
	_mat.set_shader_parameter("drift", drift)
	_mat.set_shader_parameter("first_strip", float(first))
	_mat.set_shader_parameter("strip_y", ys)
	# the plate
	var pose := plate_pose()
	var rest := plate_rest_foot()
	var on := _clock >= DROP_AT
	_mat.set_shader_parameter("plate_on", 1.0 if on else 0.0)
	_mat.set_shader_parameter("plate_foot", rest - Vector2(0.0, pose.x))
	_mat.set_shader_parameter("plate_scale", Vector2(pose.y, pose.z))
	var since := _clock - DROP_AT - FALL
	_mat.set_shader_parameter("dust_t", since if since >= 0.0 else -1.0)
	_mat.set_shader_parameter("dust_at", rest)
	if since >= 0.0 and not _thud_done:
		_thud_done = true
		_note("landed")
		W.sfx_first(THUD)
	if _clock >= FADE_IN and not _has("fade_in"):
		_note("fade_in")
	if is_settled() and not _has("settled"):
		_note("settled")


func _note(what: String) -> void:
	events.append([what, _clock])


func _has(what: String) -> bool:
	for e: Array in events:
		if e[0] == what:
			return true
	return false


## When `what` happened on the screen's clock (-1: not yet; tests).
func event_time(what: String) -> float:
	for e: Array in events:
		if e[0] == what:
			return float(e[1])
	return -1.0


# ---------------------------------------------------------------- the load

## The threaded load, once a frame: loaded, the title waits for the plate to settle; failed, or sat still for
## stall_limit, it is loaded at once instead.
func _watch(delta: float) -> void:
	var progress := []
	var status := _status(progress)
	var p := float(progress[0]) if not progress.is_empty() else 0.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			timings["load"] = (Time.get_ticks_usec() - _t_load) / 1000.0
			var scene := ResourceLoader.load_threaded_get(title_path) as PackedScene
			if scene:
				_loaded(scene)
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


## The title's scene is in memory: it is built once the plate has settled (_process).
func _loaded(scene: PackedScene) -> void:
	_scene = scene
	_note("loaded")


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
	_loaded(scene)


## Nothing could bring the title up: the screen stays, its wallpaper stops (the motion means "loading"), and a line on
## a paper card under the plate says so.
func _fail() -> void:
	failed = true
	_loading = false
	push_warning("Boot: the title screen at %s could not be loaded" % title_path)
	if get_node_or_null("Error"):
		return
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", W.box(W.PAPER, 4, 6))
	card.name = "Error"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := W.serif_text("The title screen did not load. Please close the game and start it again.", 30, W.ROCK,
		600, false, HORIZONTAL_ALIGNMENT_CENTER, 40.0, true, false)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = Vector2(24.0, 18.0)
	line.size = Vector2(_canvas.x - 240.0 - 48.0, 80.0)
	card.add_child(line)
	card.position = Vector2(120.0, plate_rest_foot().y + 60.0)
	card.size = Vector2(_canvas.x - 240.0, 116.0)
	add_child(card)


## The title is loaded and the plate has settled: build the title under this screen, let it draw once, hold until
## MIN_SHOW, then dissolve into it. Each step waits a frame (the build and the first draw each hold one).
func _hand_over(scene: PackedScene) -> void:
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
	_note("built")
	t0 = Time.get_ticks_usec()
	# the title's first frame (its shaders, the stage's world) is drawn under this screen
	await get_tree().process_frame
	timings["first_frame"] = (Time.get_ticks_usec() - t0) / 1000.0
	_note("first_frame")
	while _clock < MIN_SHOW and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree():
		return
	print("Boot: engine and autoloads %d ms, title loaded in %d ms, built in %d ms, first frame %d ms, dissolve at %.2f s" % [
		int(timings.get("engine", 0)), int(timings.get("load", 0)), int(timings.get("build", 0)),
		int(timings.get("first_frame", 0)), _clock])
	_dissolve()
	handed_over.emit(title)


## Starts fading this screen away over the title (and the cutout's band in): _process steps it.
func _dissolve() -> void:
	_note("dissolve")
	_set_mouse_ignore(self)
	# the one draw covers the paper rect from here on, so every pixel of this screen is drawn once
	var paper := get_node_or_null("ColorRect") as CanvasItem
	if paper and has_wallpaper():
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
