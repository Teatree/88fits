## The way into a run. Pass 120 (lane STARTGO; Garry: "When tapping Start let's make a smooth transition animation with
## like a Revolver cut out thing collapsing in on the center of the screen. - Proper loading screen (just reuse the same
## one we already have) for loading the game should follow as well."). Every way into a run comes here (UiFx.go_run: the
## title's PLAY and ARENA, a card of the Stages menu, PLAY AGAIN, the developer menu's Arena) and plays one move:
##   1. the wipe (WIPE s from the tap): the screen being left is seen through a revolver's cylinder seen end-on, ink round
##      it. Its fluted rim closes in from just past the screen's corners onto the middle (the middle of what lies under the
##      camera cutout's band) at an even pace to the eye (its size falls by the same share each frame: e^(-ZOOM k)) and
##      snaps shut at the end (x (1 - k^SNAP_POW)); its six chambers open as ink holes in the first CHAMBERS_IN of it and
##      the pin's hole in its middle after them; it turns TURN_IN degrees clockwise, slowing as it goes, and stops with a
##      chamber at 12 o'clock as the screen goes ink. The cylinder's spin (w_hip_spin, its
##      clicks slowing down) plays from the tap. The screen left is freed under the ink, which holds SNAP_HOLD s.
##   2. the loading screen (ui/Boot.gd's own: the wallpaper, the plate and its slam, the clock capped at MAX_STEP a frame)
##      comes out of the ink through the same cylinder opening again from the same middle (REVEAL s, the close played
##      backwards and still turning, TURN_REVEAL more): its rim runs out past the corners as the plate punches in (REVEAL
##      = SLAM_AT). Game.tscn loads on a thread from the tap (ResourceLoader.load_threaded_request); the Game is built only
##      once the slam has settled and no sooner than BUILD_LEAD before MIN_SHOW, so its long _ready frame never freezes the
##      slam and its first frame (the warm-up's draw) is drawn under this screen.
##   3. the hand-over (OPEN s): from MIN_SHOW on, once the Game has drawn its first frame, the cylinder opens a third time,
##      from where the hero's spawn beam stands (open_mid_for), and the run is seen through it while this screen goes: the
##      beam is on screen from its first frames (Game.SPAWN_MAX_STEP: the long first frames no longer throw it forward).
## The curtain is a CanvasLayer on the root (LAYER: above the cutout's band and every screen), so it survives the scene
## change. While it wipes and loads it stays the root's last child and takes every input event first (no tap, drag, key or
## click reaches the screen under it or the run being built), and UiFx.go drops any other scene change asked meanwhile (a
## second tap, the back gesture of the screen being left); from the open on, touches reach the run (a press hurries the
## landing as before). One draw: Boot's shader with its cylinder on (iris_*); BALANCING.md 62.STARTGO.
extends "res://ui/Boot.gd"

const GAME := "res://game/Game.tscn"
const SELF := "res://ui/RunCurtain.gd"
const TITLE_SCREEN := "res://ui/TitleScreen.tscn"
## The curtains up and still covering (UiFx.go asks it).
const GROUP := &"run_curtain"
## Its canvas layer: over the cutout's band (110) and UiFx's fade (100).
const LAYER := 120

## The wipe: the cylinder closes in WIPE s, then the ink holds SNAP_HOLD s.
const WIPE := 0.5
const SNAP_HOLD := 0.05
## The loading screen comes out of the ink through the cylinder in REVEAL s (the plate punches in as it is open: SLAM_AT).
const REVEAL := 0.3
## The run is seen through the cylinder opening from the spawn beam in OPEN s.
const OPEN := 0.4
## The Game is built no sooner than this before MIN_SHOW (its build and its first draw hold a frame each).
const BUILD_LEAD := 1.0 / 30.0
## The close's size: e^(-ZOOM k) x (1 - k^SNAP_POW) of the full radius at k (0..1) of the wipe: a steady pull away (the
## whole cylinder is on a portrait screen from about a third of the way) and a snap at the end.
const ZOOM := 2.5
const SNAP_POW := 6.0
## The cylinder's turn (degrees, clockwise on the screen): TURN_IN as it closes (SNAP_TURN - TURN_IN (1 - k)^1.5: slowing to
## a stop as it snaps shut, a chamber at 12 o'clock), TURN_REVEAL more as it opens on the loading screen, TURN_OPEN more on
## the run.
const TURN_IN := 240.0
const TURN_REVEAL := 60.0
const TURN_OPEN := 60.0
const SNAP_TURN := 30.0
## The cylinder's shape, shares of its radius: the chambers' middles CHAMBER_AT out and CHAMBER_R round, the flutes cut
## by circles FLUTE_R round FLUTE_AT out between them (their deepest point FLUTE_AT - FLUTE_R out), the pin's hole PIN_R.
const CHAMBER_AT := 0.58
const CHAMBER_R := 0.24
const FLUTE_AT := 1.03
const FLUTE_R := 0.15
const PIN_R := 0.08
## A shut chamber or pin is this far under nothing (canvas px; the shader's 1.5), so it leaves no pixel of ink.
const SHUT_PX := 1.5
## As it closes: the chambers open over the first CHAMBERS_IN of the wipe, the pin's hole between PIN_IN.x and PIN_IN.y of
## it; an ink shade SHADE strong lies inside the rim (a hole's edge), coming in over the first SHADE_IN.
const CHAMBERS_IN := 0.35
const PIN_IN := Vector2(0.15, 0.45)
const SHADE := 0.35
const SHADE_IN := 0.2
## On the open, an ink line this wide (canvas px) runs round the cut-out on the loading screen's side (wallpaper and sand are
## both pale: the line keeps the cylinder's shape readable over the run), thinning with the chambers as they close up.
const BORDER_PX := 6.0
## The open's middle keeps this far inside the screen's edges (canvas px).
const OPEN_MARGIN := 120.0
## The cylinder's spin from the tap: the first of these the sound map binds.
const SPIN := ["w_hip_spin", "ui_reel_tick"]
const FAIL_RUN := "The run did not load. Back to the title."

enum Phase { WIPE_IN, LOADING, OPENING }

## Where the curtain is: closing on the screen left, loading (the loading screen), opening on the run.
var phase := Phase.WIPE_IN
## The screen left, freed under the ink (UiFx.go_run: the current scene; a test's own node, or none).
var old_scene: Node = null

var _start_scene: Node = null
var _wipe_clock := 0.0
var _snapped := false
var _blocking := true
var _aborted := false
var _open_mid := Vector2.ZERO
var _open_full := 0.0


## Starts the way into a run: the curtain on its layer over everything, closing on the current scene, loading `path`.
## `host_node` (tests) takes the built scene as a child and leaves the current scene alone; `old` is then the node freed
## under the ink. One curtain at a time: a second call while one wipes or loads returns that one.
static func launch(tree: SceneTree, path: String = GAME, host_node: Node = null, old: Node = null) -> Control:
	var up := tree.get_first_node_in_group(GROUP)
	if up != null:
		return up as Control
	var layer := CanvasLayer.new()
	layer.name = "RunCurtain"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var c = (load(SELF) as GDScript).new()
	c.name = "Curtain"
	c.title_path = path
	c.host = host_node
	c.old_scene = old if host_node != null else tree.current_scene
	c.add_to_group(GROUP)
	layer.add_child(c)
	tree.root.add_child(layer)
	return c


func _ready() -> void:
	_start_scene = get_tree().current_scene
	mouse_filter = Control.MOUSE_FILTER_STOP
	fail_line = FAIL_RUN
	super._ready()
	_note("wipe")
	W.sfx_first(SPIN)


## A curtain never opens the replay viewer (Boot does, at the app's start).
func _open_replay() -> bool:
	return false


## The band is under this layer: the wipe shows it as part of the screen left, the open as part of the run.
func _hold_band() -> void:
	pass


func _report_content() -> void:
	pass


func _build() -> void:
	super._build()
	_mat.set_shader_parameter("iris_ink", W.INK)
	_mat.set_shader_parameter("iris_shape", Vector4(CHAMBER_AT, CHAMBER_R, FLUTE_AT, FLUTE_R))
	_mat.set_shader_parameter("iris_pin_r", PIN_R)
	_apply()


func _process(delta: float) -> void:
	if _aborted:
		return
	if _blocking:
		_keep_on_top()
	if not _handing and phase != Phase.OPENING and _left_alone():
		_abort("the scene was changed under it")
		return
	if phase == Phase.WIPE_IN:
		_wipe_clock += minf(delta, MAX_STEP)
		if _loading:
			_watch(delta)
		if not _snapped and _wipe_clock >= WIPE:
			_snap()
		_apply()
		if _wipe_clock >= WIPE + SNAP_HOLD:
			phase = Phase.LOADING
			_note("reveal")
		return
	super._process(delta)


## Every input event is this curtain's while it wipes and loads (it is the root's last child: it hears them first).
func _input(_event: InputEvent) -> void:
	if _blocking and is_inside_tree():
		get_viewport().set_input_as_handled()


func blocking() -> bool:
	return _blocking


## The layer stays the root's last child while it covers (a node added to the root after it would hear input first).
func _keep_on_top() -> void:
	var layer := get_parent()
	if layer == null or not layer.is_inside_tree():
		return
	var root := get_tree().root
	if layer.get_parent() == root and layer.get_index() < root.get_child_count() - 1:
		root.move_child(layer, -1)


## Someone changed the scene while the curtain closed or loaded (a tool): it goes and builds nothing.
func _left_alone() -> bool:
	var cs := get_tree().current_scene
	return cs != null and cs != _start_scene and cs != title and cs != old_scene


func _abort(why: String) -> void:
	push_warning("RunCurtain: %s; the curtain goes" % why)
	_aborted = true
	_loading = false
	if _scene == null and ResourceLoader.load_threaded_get_status(title_path) == ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_get(title_path)
	_finish()


## The cylinder has snapped shut: the screen left goes, under the ink.
func _snap() -> void:
	_snapped = true
	_note("snap")
	var old := old_scene
	old_scene = null
	if old != null and is_instance_valid(old) and old.is_inside_tree():
		if get_tree().current_scene == old:
			get_tree().current_scene = null
		old.queue_free()
	if failed:
		_back_to_title()


## Nothing could bring the run up (its scene would not load even directly): back to the title once the screen is ink.
func _fail() -> void:
	failed = true
	_loading = false
	push_warning("RunCurtain: the run's scene at %s could not be loaded; back to the title" % title_path)
	if _snapped:
		_back_to_title()


func _back_to_title() -> void:
	_finish()
	if host == null and ResourceLoader.exists(TITLE_SCREEN):
		get_tree().change_scene_to_file(TITLE_SCREEN)


# ---------------------------------------------------------------- the load (Boot's), built a little later

func _may_build() -> bool:
	return not _aborted and phase == Phase.LOADING and is_settled() and _clock >= MIN_SHOW - BUILD_LEAD


## The run under the root as the current scene, the curtain kept over it (and hearing input first).
func _place_scene(scene: Node) -> void:
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	_keep_on_top()


func _report() -> void:
	print("RunCurtain: %s loaded in %d ms, built in %d ms, first frame %d ms, open at %.2f s on the loading screen's clock" % [
		title_path.get_file(), int(timings.get("load", 0)), int(timings.get("build", 0)),
		int(timings.get("first_frame", 0)), _clock])


# ---------------------------------------------------------------- the open

## Boot dissolves here; the curtain opens its cylinder on the run instead, and lets input through.
func _dissolve() -> void:
	_note("dissolve")
	if _aborted:
		_finish()
		return
	phase = Phase.OPENING
	_blocking = false
	remove_from_group(GROUP)
	_set_mouse_ignore(self)
	_open_mid = open_mid_for(title, _canvas)
	_open_full = full_radius(_open_mid, _canvas)
	_dissolve_t = 0.0
	_apply()


## One frame of the open, counting at most MAX_STEP; true once it is done (or the run it opened on is gone).
func _step_dissolve(delta: float) -> bool:
	_dissolve_t = minf(_dissolve_t + minf(delta, MAX_STEP) / OPEN, 1.0)
	_apply()
	var gone := title == null or not is_instance_valid(title) or not title.is_inside_tree()
	if _dissolve_t >= 1.0 or gone:
		_finish()
		return true
	return false


## The curtain goes (with its layer).
func _finish() -> void:
	if not _has("open_done"):
		_note("open_done")
	_blocking = false
	if is_in_group(GROUP):
		remove_from_group(GROUP)
	var layer := get_parent()
	if layer is CanvasLayer and layer.get_child_count() == 1:
		layer.queue_free()
	else:
		queue_free()


# ---------------------------------------------------------------- the cylinder

func _apply() -> void:
	super._apply()
	if _mat == null:
		return
	# the loading screen comes out of the ink through the cylinder, never from the paper
	_mat.set_shader_parameter("fade", 1.0)
	var p := iris_pose()
	_mat.set_shader_parameter("iris_mode", int(p["mode"]))
	_mat.set_shader_parameter("iris_mid", p["mid"])
	_mat.set_shader_parameter("iris_r", float(p["r"]))
	_mat.set_shader_parameter("iris_turn", deg_to_rad(float(p["turn"])))
	_mat.set_shader_parameter("iris_chamber", float(p["chamber"]))
	_mat.set_shader_parameter("iris_pin", float(p["pin"]))
	_mat.set_shader_parameter("iris_shade", float(p["shade"]))
	# thinning with the chambers as they close up at the end (a full line round a small one read as a bubble)
	_mat.set_shader_parameter("iris_border", BORDER_PX * float(p["chamber"]) if int(p["mode"]) == 3 else 0.0)


## The cylinder now: {mode (Boot's iris_mode), mid, r (canvas px), turn (degrees), chamber, pin, shade} (tests, captures).
func iris_pose() -> Dictionary:
	var c: Dictionary
	var mid := wipe_mid()
	var mode := 0
	match phase:
		Phase.WIPE_IN:
			c = close_at(_wipe_clock / WIPE)
			mode = 1
		Phase.LOADING:
			if _clock >= REVEAL:
				c = close_at(0.0)
			else:
				c = open_at(_clock / REVEAL, SNAP_TURN, TURN_REVEAL)
				mode = 2
		_:
			c = open_at(_dissolve_t, SNAP_TURN + TURN_REVEAL, TURN_OPEN)
			mid = _open_mid
			mode = 3
	c["mode"] = mode
	c["mid"] = mid
	c["r"] = float(c["r"]) * (_open_full if mode == 3 else full_radius(mid, _canvas))
	return c


## Where the cylinder closes and opens again: the screen's middle, under the cutout's band.
func wipe_mid() -> Vector2:
	return Vector2(_canvas.x * 0.5, (W.safe_top() + _canvas.y) * 0.5)


## How long the wipe has run (s; tests, captures).
func wipe_clock() -> float:
	return _wipe_clock


## The cylinder as it closes, k 0..1 of the wipe: its radius (a share of the full one: e^(-ZOOM k) (1 - k^SNAP_POW), the
## same share smaller each frame, then the snap), its turn (degrees: SNAP_TURN - TURN_IN (1 - k)^1.5, slowing to a stop as
## it snaps), the chambers' and the pin's size (shares of theirs) and the rim's shade.
static func close_at(k: float) -> Dictionary:
	var x := clampf(k, 0.0, 1.0)
	return {"r": exp(-ZOOM * x) * (1.0 - pow(x, SNAP_POW)), "turn": SNAP_TURN - TURN_IN * pow(1.0 - x, 1.5),
		"chamber": smoothstep(0.0, CHAMBERS_IN, x), "pin": smoothstep(PIN_IN.x, PIN_IN.y, x),
		"shade": SHADE * clampf(x / SHADE_IN, 0.0, 1.0)}


## The cylinder as it opens, k 0..1: the close played backwards (fast at first, slowing as its rim runs out past the
## corners, the chambers closing up), still turning the same way: `turn` degrees more than `from_turn`, slowing.
static func open_at(k: float, from_turn: float, turn: float) -> Dictionary:
	var x := clampf(k, 0.0, 1.0)
	var c := close_at(1.0 - x)
	c["turn"] = from_turn + turn * (1.0 - (1.0 - x) * (1.0 - x))
	return c


## The radius (canvas px) at which the cylinder round `mid` hides nothing of a `canvas` screen: its flutes' deepest point
## past the corner farthest from it.
static func full_radius(mid: Vector2, canvas: Vector2) -> float:
	var far := 0.0
	for c: Vector2 in [Vector2.ZERO, Vector2(canvas.x, 0.0), Vector2(0.0, canvas.y), canvas]:
		far = maxf(far, mid.distance_to(c))
	return far / (FLUTE_AT - FLUTE_R) + 4.0


## Where the open starts: on the screen where the run's spawn beam stands (the hero's landing spot; the hero when there is
## no beam: the arena), kept OPEN_MARGIN inside the screen; the middle of the screen when the scene has no camera.
static func open_mid_for(scene: Node, canvas: Vector2) -> Vector2:
	var mid := canvas * 0.5
	if scene == null or not is_instance_valid(scene) or not scene.is_inside_tree():
		return mid
	var rig = scene.get("camera")
	var cam: Camera3D = null
	if rig is Camera3D:
		cam = rig
	elif rig is Node and (rig as Node).get("camera") is Camera3D:
		cam = (rig as Node).get("camera")
	if cam == null or not cam.is_inside_tree():
		return mid
	var at = null
	if scene.get("spawning") == true:
		at = scene.get("_spawn_land")
	elif scene.get("player") is Node3D:
		at = (scene.get("player") as Node3D).global_position
	if not (at is Vector3) or cam.is_position_behind(at):
		return mid
	var p := cam.unproject_position(at)
	return Vector2(clampf(p.x, OPEN_MARGIN, canvas.x - OPEN_MARGIN), clampf(p.y, OPEN_MARGIN, canvas.y - OPEN_MARGIN))


## The cylinder as a signed distance at `p` (canvas px; below 0 inside its metal, the cut-out the screen is seen through),
## as the shader measures it (Boot.gd's cylinder_sd): a round of radius `r` round `mid` turned `turn` degrees, its six
## chambers and the pin's hole `chamber` and `pin` of their size (0: shut, SHUT_PX under nothing).
static func cylinder_sd(p: Vector2, mid: Vector2, r: float, turn: float, chamber: float, pin: float) -> float:
	var big := maxf(r, 0.0001)
	var q := p - mid
	var d := q.length()
	var a := atan2(q.y, q.x) - deg_to_rad(turn) if d > 0.001 else 0.0
	var sector := TAU / 6.0
	a = absf(fposmod(a + sector * 0.5, sector) - sector * 0.5)
	var f := Vector2(cos(a), sin(a)) * d
	var body := d - big if r > 0.0 else 1.0e5
	var ch := f.distance_to(Vector2(CHAMBER_AT * big, 0.0)) - (CHAMBER_R * big * chamber - SHUT_PX)
	var fl := f.distance_to(Vector2(0.8660254, 0.5) * FLUTE_AT * big) - FLUTE_R * big
	var pn := d - (PIN_R * big * pin - SHUT_PX)
	return maxf(maxf(body, -fl), maxf(-ch, -pn))
