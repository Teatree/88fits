## Pass 120, lane STARTGO (Garry: "When tapping Start let's make a smooth transition animation with like a Revolver cut
## out thing collapsing in on the center of the screen. - Proper loading screen (just reuse the same one we already have)
## for loading the game should follow as well."): ui/RunCurtain.gd, UiFx.go_run, BALANCING.md 62.STARTGO.
##  - every way into a run (the title's PLAY and ARENA, a Stages card, PLAY AGAIN, the developer menu's Arena) goes
##    through the one entry point, and UiFx.go of the run's scene too;
##  - the cylinder: nothing of the screen hidden as it starts, all ink as it snaps (a chamber at 12 o'clock), faster and
##    faster in, its turn slowing; the reveal plays it backwards and ends as the plate punches in;
##  - the curtain is a layer on the root over the cutout's band that survives the scene change (the screen left is freed
##    under the ink, the run is built under it), and goes once its cylinder has opened on the run;
##  - the run is built only after the slam has settled, never long before MIN_SHOW, and the open never starts before it;
##  - taps, drags and keys never reach what is under it until it opens;
##  - the landing's clock counts a long frame as one step (the beam is not thrown forward under the curtain), and the open
##    starts where the beam stands;
##  - Boot's own start is unchanged (its cylinder off).
extends GdUnitTestSuite

const Curtain := preload("res://ui/RunCurtain.gd")
const BootScript := preload("res://ui/Boot.gd")
const STAND_IN := "user://p120_startgo_stand_in.tscn"
const GOOD_SCENE := "[gd_scene format=3]\n\n[node name=\"Good\" type=\"Control\"]\n"
const MAP := "red_canyon"


## Hears every input event that reaches it.
class Probe extends Node:
	var got := 0

	func _input(_event: InputEvent) -> void:
		got += 1


## A loading screen whose load never finishes (Boot's own, as pass 118's tests make it).
class EndlessBoot extends "res://ui/Boot.gd":
	func _request() -> int:
		return OK

	func _status(progress: Array) -> int:
		progress.append(randf())
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS


func before_test() -> void:
	var f := FileAccess.open(STAND_IN, FileAccess.WRITE)
	f.store_string(GOOD_SCENE)
	f.close()


func after_test() -> void:
	for n in get_tree().root.get_children():
		if n is CanvasLayer and (str(n.name).begins_with("RunCurtain") or (n as CanvasLayer).layer == 100):
			n.free()
	if FileAccess.file_exists(STAND_IN):
		DirAccess.remove_absolute(STAND_IN)
	get_tree().paused = false


func _host() -> Node:
	var host: Node = auto_free(Node.new())
	add_child(host)
	return host


## A curtain closing on `old` (a node of the test's) and loading the stand-in into `host`.
func _launch(host: Node, old: Node):
	return Curtain.launch(get_tree(), STAND_IN, host, old)


func _wait_for(cond: Callable, limit_ms: int = 8000) -> bool:
	var waited := 0
	while not cond.call() and waited < limit_ms:
		await await_millis(10)
		waited += 10
	return bool(cond.call())


# ---------------------------------------------------------------- the one way in

func test_every_way_into_a_run_goes_through_the_curtain() -> void:
	for path in ["res://ui/TitleScreen.gd", "res://ui/StagesScreen.gd", "res://ui/ResultsScreen.gd", "res://ui/DevMenu.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_bool(src.contains("UiFx.go_run(get_tree())")).override_failure_message(path).is_true()
		assert_bool(src.contains("go(get_tree(), \"res://game/Game.tscn\")")).override_failure_message(path).is_false()
		assert_bool(src.contains("go(\"res://game/Game.tscn\")")).override_failure_message(path).is_false()
	var title := FileAccess.get_file_as_string("res://ui/TitleScreen.gd")
	# PLAY and ARENA both
	assert_int(title.count("UiFx.go_run(get_tree())")).is_equal(2)
	assert_str(UiFx.RUN_SCENE).is_equal("res://game/Game.tscn")
	assert_str(UiFx.RUN_CURTAIN).is_equal("res://ui/RunCurtain.gd")
	assert_str(str(UiFx.CURTAIN_GROUP)).is_equal(str(Curtain.GROUP))
	# UiFx.go of the run's scene is the curtain too
	var fx := FileAccess.get_file_as_string("res://ui/UiFx.gd")
	assert_bool(fx.contains("if path == RUN_SCENE:\n\t\tgo_run(tree)")).is_true()
	assert_str(Curtain.GAME).is_equal(UiFx.RUN_SCENE)


## One curtain at a time, and no other scene change is taken while it covers.
func test_one_curtain_and_no_other_scene_change_meanwhile() -> void:
	var host := _host()
	var old := Node.new()
	host.add_child(old)
	var c = _launch(host, old)
	assert_object(Curtain.launch(get_tree(), STAND_IN, host, null)).is_same(c)
	UiFx.go(get_tree(), "res://p120_no_such_scene.tscn")
	var fades := get_tree().root.get_children().filter(func(n: Node) -> bool: return n is CanvasLayer and n.layer == 100)
	assert_bool(fades.is_empty()).is_true()
	await await_signal_on(c, "handed_over", [], 10000)
	assert_bool(c.is_in_group(Curtain.GROUP)).is_false()


# ---------------------------------------------------------------- the cylinder

func test_the_cylinder_closes_on_the_middle_and_snaps_shut() -> void:
	assert_float(Curtain.WIPE).is_between(0.45, 0.6)
	assert_float(Curtain.REVEAL).is_equal_approx(BootScript.SLAM_AT, 0.0001)
	var canvas := Vector2(1080, 1920)
	var mid := Vector2(540, 960 + 40)
	var full := Curtain.full_radius(mid, canvas)
	# as it starts nothing of the screen is ink: every point on a 20 px grid lies inside its metal
	var c0 := Curtain.close_at(0.0)
	assert_float(float(c0["r"])).is_equal(1.0)
	assert_float(float(c0["chamber"])).is_equal(0.0)
	assert_float(float(c0["pin"])).is_equal(0.0)
	assert_float(float(c0["shade"])).is_equal(0.0)
	for y in range(0, 1921, 20):
		for x in range(0, 1081, 20):
			var sd := Curtain.cylinder_sd(Vector2(x, y), mid, full * float(c0["r"]), float(c0["turn"]), 0.0, 0.0)
			if sd > -1.0:
				assert_bool(false).override_failure_message("ink at %d,%d (%f) as it starts" % [x, y, sd]).is_true()
				return
	# half way the six chambers are holes in it and its fluted rim is on the screen
	var c5 := Curtain.close_at(0.6)
	var r5 := full * float(c5["r"])
	var holes := 0
	for i in 6:
		var a := deg_to_rad(float(c5["turn"]) + 60.0 * i)
		var at := mid + Vector2(cos(a), sin(a)) * Curtain.CHAMBER_AT * r5
		if Curtain.cylinder_sd(at, mid, r5, float(c5["turn"]), float(c5["chamber"]), float(c5["pin"])) > 0.0:
			holes += 1
	assert_int(holes).is_equal(6)
	# between two chambers, on the rim: the flute's notch is ink, just inside it is metal
	var fa := deg_to_rad(float(c5["turn"]) + 30.0)
	var notch := mid + Vector2(cos(fa), sin(fa)) * r5 * 0.97
	assert_float(Curtain.cylinder_sd(notch, mid, r5, float(c5["turn"]), 1.0, 1.0)).is_greater(0.0)
	assert_float(Curtain.cylinder_sd(mid + Vector2(cos(fa), sin(fa)) * r5 * 0.8, mid, r5, float(c5["turn"]), 1.0, 1.0)).is_less(0.0)
	# in at an even pace to the eye and never slower (each step takes the same share of its size, or more: the snap), the
	# whole cylinder on the screen from about a third of the way, the turn slowing to a stop
	var dt := 1.0 / 120.0
	var k := 0.0
	var r_prev := 1.0
	var keep_prev := 1.0
	var turn_prev := float(c0["turn"])
	var spin_prev := INF
	while k + dt <= 1.0 - dt:
		k += dt
		var c := Curtain.close_at(k)
		var keep := float(c["r"]) / r_prev
		var spin := float(c["turn"]) - turn_prev
		assert_float(keep).is_less(1.0)
		assert_float(keep).is_less_equal(keep_prev + 0.000001)
		assert_float(spin).is_greater(0.0)
		assert_float(spin).is_less_equal(spin_prev + 0.000001)
		r_prev = float(c["r"])
		keep_prev = keep
		turn_prev = float(c["turn"])
		spin_prev = spin
	assert_float(full * float(Curtain.close_at(0.4)["r"])).is_less(540.0)
	assert_float(full * float(Curtain.close_at(0.2)["r"])).is_greater(540.0)
	# at the snap: all ink, a chamber at 12 o'clock, its turn TURN_IN in all
	var c1 := Curtain.close_at(1.0)
	assert_float(float(c1["r"])).is_equal(0.0)
	assert_float(float(c1["turn"]) - float(c0["turn"])).is_equal_approx(Curtain.TURN_IN, 0.0001)
	assert_float(fposmod(float(c1["turn"]) - 270.0, 60.0)).is_equal_approx(0.0, 0.0001)
	for p: Vector2 in [mid, Vector2.ZERO, canvas, Vector2(540, 300)]:
		assert_float(Curtain.cylinder_sd(p, mid, 0.0, float(c1["turn"]), 1.0, 1.0)).is_greater(0.0)
	# a shut chamber or pin leaves no pixel, even right on its middle
	var at0 := mid + Vector2(Curtain.CHAMBER_AT * full, 0.0).rotated(deg_to_rad(float(c0["turn"])))
	assert_float(Curtain.cylinder_sd(at0, mid, full, float(c0["turn"]), 0.0, 0.0)).is_less(-1.0)
	assert_float(Curtain.cylinder_sd(mid, mid, full, float(c0["turn"]), 0.0, 0.0)).is_less(-1.0)
	# the reveal is the close played backwards, still turning the same way
	var o0 := Curtain.open_at(0.0, Curtain.SNAP_TURN, Curtain.TURN_REVEAL)
	var o1 := Curtain.open_at(1.0, Curtain.SNAP_TURN, Curtain.TURN_REVEAL)
	assert_float(float(o0["r"])).is_equal(0.0)
	assert_float(float(o1["r"])).is_equal(1.0)
	assert_float(float(o1["chamber"])).is_equal(0.0)
	assert_float(float(o1["turn"]) - float(o0["turn"])).is_equal_approx(Curtain.TURN_REVEAL, 0.0001)
	assert_float(float(Curtain.open_at(0.5, 0.0, 60.0)["r"])).is_equal_approx(float(Curtain.close_at(0.5)["r"]), 0.0001)


## The shader draws the same cylinder: Boot's one draw carries it, off unless a curtain turns it on.
func test_the_one_draw_carries_the_cylinder() -> void:
	var src: String = BootScript.SHADER
	for u in ["iris_mode", "iris_mid", "iris_r", "iris_turn", "iris_chamber", "iris_pin", "iris_shade", "iris_ink", "iris_shape"]:
		assert_bool(src.contains("uniform") and src.contains(u)).override_failure_message(u).is_true()
	assert_bool(src.contains("uniform int iris_mode = 0;")).is_true()
	assert_bool(src.contains("fwidth(sd.x)")).is_true()
	assert_bool(src.contains("vec2(0.8660254, 0.5)")).is_true()
	var cur := FileAccess.get_file_as_string("res://ui/RunCurtain.gd")
	assert_bool(cur.contains("Vector2(0.8660254, 0.5)")).is_true()
	assert_bool(cur.contains("const SHADER")).is_false()


# ---------------------------------------------------------------- the curtain over the scene change

func test_the_curtain_survives_the_scene_change() -> void:
	var host := _host()
	var old := Control.new()
	old.name = "OldScreen"
	host.add_child(old)
	var c = _launch(host, old)
	var layer := c.get_parent() as CanvasLayer
	assert_object(layer).is_not_null()
	assert_object(layer.get_parent()).is_same(get_tree().root)
	assert_int(layer.layer).is_equal(Curtain.LAYER)
	var band := get_node_or_null("/root/CutoutBand") as CanvasLayer
	if band:
		assert_int(layer.layer).is_greater(band.layer)
	assert_int(layer.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_bool(c.blocking()).is_true()
	# the cut-out shows the screen whole as it starts
	var mat := (c.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	assert_int(int(mat.get_shader_parameter("iris_mode"))).is_equal(1)
	# snapped shut: the screen left is gone, the curtain stays (ink), the root's last child
	assert_bool(await _wait_for(func() -> bool: return c.event_time("snap") >= 0.0)).is_true()
	await get_tree().process_frame
	assert_bool(is_instance_valid(old)).is_false()
	assert_bool(is_instance_valid(layer) and layer.is_inside_tree()).is_true()
	assert_int(layer.get_index()).is_equal(get_tree().root.get_child_count() - 1)
	assert_float(float(mat.get_shader_parameter("iris_r"))).is_equal(0.0)
	assert_float(c.wipe_clock()).is_greater_equal(Curtain.WIPE)
	# the run is built under it and it is still there, still covering, as the run draws its first frame
	await await_signal_on(c, "handed_over", [], 10000)
	assert_object(c.title).is_not_null()
	assert_object(c.title.get_parent()).is_same(host)
	assert_bool(is_instance_valid(layer) and layer.is_inside_tree()).is_true()
	assert_float(c.event_time("first_frame")).is_greater_equal(c.event_time("built"))
	# then it opens on the run and goes, its layer with it
	assert_int(int(mat.get_shader_parameter("iris_mode"))).is_equal(3)
	var layer_id := layer.get_instance_id()
	assert_bool(await _wait_for(func() -> bool: return not is_instance_id_valid(layer_id), 4000)).is_true()
	assert_int(host.get_child_count()).is_equal(1)


## The sequence on the curtain's clocks: the wipe, the snap, the reveal, the plate's hit, the slam settled, the run built
## (not before the slam, nor long before MIN_SHOW), its first frame, the open (never before MIN_SHOW).
func test_the_run_builds_only_after_the_slam() -> void:
	var host := _host()
	var c = _launch(host, null)
	await await_signal_on(c, "handed_over", [], 10000)
	var names := ["wipe", "snap", "reveal", "landed", "settled", "built", "first_frame", "dissolve"]
	for n: String in names:
		assert_float(c.event_time(n)).override_failure_message("no %s in %s" % [n, str(c.events)]).is_greater_equal(0.0)
	var order: Array = []
	for e: Array in c.events:
		if names.has(e[0]):
			order.append(e[0])
	assert_array(order).is_equal(names)
	# the stand-in loads at once: loaded long before it may be built
	assert_float(c.event_time("loaded")).is_less(c.event_time("landed"))
	assert_float(c.event_time("built")).is_greater_equal(c.settle_time())
	assert_float(c.event_time("built")).is_greater_equal(BootScript.MIN_SHOW - Curtain.BUILD_LEAD)
	assert_float(c.event_time("dissolve")).is_greater_equal(BootScript.MIN_SHOW)
	assert_float(c.event_time("dissolve")).is_less(BootScript.MIN_SHOW + 0.3)
	# the slam played as at the app's start: the plate at rest, nothing shaking, the loading screen whole (no paper)
	assert_bool(c.plate_pose().is_equal_approx(Vector3(0.0, 1.0, 1.0))).is_true()
	var mat := (c.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	assert_float(float(mat.get_shader_parameter("fade"))).is_equal(1.0)
	assert_bool(c._thud_done).is_true()


## The loading screen comes out of the ink, never from the paper: while it opens the wallpaper is whole inside the cut-out
## and the rest is ink.
func test_the_loading_screen_comes_out_of_the_ink() -> void:
	var host := _host()
	var c = _launch(host, null)
	var mat := (c.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	assert_bool(await _wait_for(func() -> bool: return c.phase == Curtain.Phase.LOADING and c.clock() > 0.05)).is_true()
	if c.clock() < Curtain.REVEAL:
		assert_int(int(mat.get_shader_parameter("iris_mode"))).is_equal(2)
		assert_float(float(mat.get_shader_parameter("iris_r"))).is_greater(0.0)
	assert_float(float(mat.get_shader_parameter("fade"))).is_equal(1.0)
	assert_bool(await _wait_for(func() -> bool: return c.clock() >= Curtain.REVEAL + 0.05)).is_true()
	assert_int(int(mat.get_shader_parameter("iris_mode"))).is_equal(0)
	await await_signal_on(c, "handed_over", [], 10000)


# ---------------------------------------------------------------- no taps through it

func test_taps_never_reach_what_is_under_it_until_it_opens() -> void:
	var host := _host()
	var probe: Probe = Probe.new()
	host.add_child(probe)
	var c = _launch(host, null)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = Vector2(540, 960)
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	var seen_blocked := 0
	# during the wipe, the load and while the run is built: nothing reaches the probe
	while is_instance_valid(c) and c.phase != Curtain.Phase.OPENING:
		touch.pressed = not touch.pressed
		get_tree().root.push_input(touch, true)
		get_tree().root.push_input(key, true)
		seen_blocked += 2
		await get_tree().process_frame
	assert_int(seen_blocked).is_greater(20)
	assert_int(probe.got).is_equal(0)
	# and the curtain's own rect stops a click's way to the controls (Godot's GUI)
	assert_int(c.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# from the open on, the run hears them
	touch.pressed = false
	get_tree().root.push_input(touch, true)
	assert_int(probe.got).is_greater(0)
	probe.free()


# ---------------------------------------------------------------- the run under it

func _game(extra: Dictionary = {}) -> Node:
	var d := {"weapon": "revolver", "level": 1, "character": "drifter", "map": MAP, "map_seed": 11, "analytics": false}
	d.merge(extra, true)
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var g: Node = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


## The landing's clock counts a long frame (the run's build, its first draw) as one step, so the beam still stands when the
## curtain opens; and the open starts where the beam stands on the screen.
func test_the_landing_counts_a_long_frame_as_one_step_and_the_open_starts_at_the_beam() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	var g := _game({"spawn": true})
	await get_tree().process_frame
	assert_bool(g.get("spawning")).is_true()
	var t0: float = g.get("_spawn_t")
	g.call("_tick_spawn", 2.5)
	var t1: float = g.get("_spawn_t")
	assert_float(Game.SPAWN_MAX_STEP).is_equal_approx(1.0 / 30.0, 0.00001)
	assert_float(t1 - t0).is_less_equal(Game.SPAWN_MAX_STEP * maxf(1.0, float(g.get("spawn_rate"))) + 0.00001)
	assert_float(t1).is_less(Game.SPAWN_HOLD)
	assert_bool(g.get("spawning")).is_true()
	# where the beam stands on the screen
	var canvas := get_viewport().get_visible_rect().size
	var mid := Curtain.open_mid_for(g, canvas)
	var cam: Camera3D = g.get("camera").get("camera")
	var want := cam.unproject_position(g.get("_spawn_land"))
	want = Vector2(clampf(want.x, Curtain.OPEN_MARGIN, canvas.x - Curtain.OPEN_MARGIN),
		clampf(want.y, Curtain.OPEN_MARGIN, canvas.y - Curtain.OPEN_MARGIN))
	assert_bool(mid.is_equal_approx(want)).is_true()
	assert_bool(Rect2(Vector2.ZERO, canvas).has_point(mid)).is_true()
	# a scene without a camera opens from the middle
	assert_bool(Curtain.open_mid_for(null, canvas).is_equal_approx(canvas * 0.5)).is_true()
	# the warm-up's timer is let run out before the run goes (it would call into a freed run)
	await _wait_for(func() -> bool: return g.get_node_or_null("Warmup") == null, 4000)
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func test_the_spin_is_a_sound_the_map_binds() -> void:
	var bound := false
	for id in Curtain.SPIN:
		bound = bound or not Registry.soundmap.entry(str(id)).is_empty()
	assert_bool(bound).is_true()
	assert_str(str(Curtain.SPIN[0])).is_equal("w_hip_spin")


# ---------------------------------------------------------------- Boot's own start

func test_boot_at_the_apps_start_is_unchanged() -> void:
	assert_float(BootScript.FADE_IN).is_equal(0.3)
	assert_float(BootScript.SLAM_AT).is_equal(0.3)
	assert_float(BootScript.MIN_SHOW).is_equal(1.15)
	assert_float(BootScript.DISSOLVE).is_equal(0.25)
	var b: Control = load("res://ui/Boot.tscn").instantiate()
	b.set_script(EndlessBoot)
	b.stall_limit = 1000.0
	_host().add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	var names := []
	for ch in b.get_children():
		names.append(str(ch.name))
	assert_array(names).contains_exactly(["ColorRect", "Wallpaper"])
	var mat := (b.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	# never set: the shader's own 0 (off)
	var mode = mat.get_shader_parameter("iris_mode")
	assert_bool(mode == null or int(mode) == 0).is_true()
	assert_str(b.fail_line).is_equal(Loc.t(BootScript.FAIL_LINE_KEY))
	assert_bool(b.fail_line.contains("title screen")).is_true()
	# the cutout's band still waits while it shows (the curtain leaves it alone)
	var band := get_node_or_null("/root/CutoutBand") as CanvasLayer
	if band:
		assert_bool(band.visible).is_false()
	# it fades in from the paper, as before
	assert_float(float(mat.get_shader_parameter("fade"))).is_less_equal(BootScript.fade_at(b.clock()) + 0.0001)
	b.free()
	if band:
		assert_bool(band.visible).is_true()
