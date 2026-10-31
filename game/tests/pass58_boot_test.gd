extends GdUnitTestSuite

## Pass 58, lane BOOT (Garry, 2026-10-07: "for like a second or 2 right before the Main Menu loads I see a kind of a
## broken version of our Loading screen ... maybe add a loading progress bar to the Loading Screen"): the loading screen
## loads the title on a thread, builds it under itself and hands over; a failed load is fetched and read again from its
## file, a load that never moves is given up on, a title that cannot load is said on the screen; a long frame neither
## throws the screen's motion nor eats the dissolve; the camera cutout's band waits while it shows and comes back.
##
## Pass 118 (lane LOAD; Garry: "No icon, No progress bar. Title Drop sequence at the start and an animation of
## silhuettes ..."): the boot splash picture and the bar are gone (tests/pass118_LOAD_test.gd holds the new screen's own
## rules: the plain paper, the strips, the drop). What stays here is the hand-over: the threaded load, the stall, the
## failure text, the dissolve, the band; the bar's bookkeeping became the screen's clock and its events.

const BootScript := preload("res://ui/Boot.gd")
const Stage := preload("res://ui/TitleStage.gd")
const TITLE := "res://ui/TitleScreen.tscn"
## Stand-in titles for the load's failures (written to user:// by the tests, removed after).
const STAND_IN := "user://p58_boot_stand_in.tscn"
const BROKEN_SCENE := "[gd_scene format=3]\n\n[node name=\"Broken\" type=\"Node\"\nthis is not a scene\n"
const GOOD_SCENE := "[gd_scene format=3]\n\n[node name=\"Good\" type=\"Control\"]\n"


## A loading screen whose threaded load never moves (its status stays in progress at a quarter).
class StuckBoot extends "res://ui/Boot.gd":
	func _request() -> int:
		return OK

	func _status(progress: Array) -> int:
		progress.append(0.25)
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS


var _keep_style := ""


func before_test() -> void:
	_keep_style = Settings.menu_style


func after_test() -> void:
	Settings.menu_style = _keep_style
	Stage.forget()
	if FileAccess.file_exists(STAND_IN):
		DirAccess.remove_absolute(STAND_IN)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## The events on the screen's clock come in this order, each once.
func _in_order(boot, names: Array) -> void:
	var last := -1.0
	for n: String in names:
		var t: float = boot.event_time(n)
		assert_float(t).override_failure_message("no %s in %s" % [n, str(boot.events)]).is_greater_equal(0.0)
		assert_float(t).override_failure_message("%s at %f, before %f (%s)" % [n, t, last, str(boot.events)]).is_greater_equal(last)
		last = t


# ---------------------------------------------------------------- the loading screen

func test_boot_starts_on_the_paper() -> void:
	var boot: Control = auto_free(load("res://ui/Boot.tscn").instantiate())
	# the first scene after the boot splash is paper too, so nothing flashes dark between them (pass 54)
	assert_bool((boot.get_node("ColorRect") as ColorRect).color.is_equal_approx(W.PAPER)).is_true()
	assert_object(boot.get_node_or_null("Wallpaper")).is_null()   # built in _ready


## The first frame carries the engine's start (Godot's frame clock starts before the autoloads load): it does not count
## at all, so the first frame is the paper; after it a long frame moves the screen's clock no further than MAX_STEP.
func test_a_long_frame_moves_the_screen_by_one_step_at_most() -> void:
	var boot = auto_free(BootScript.new())
	boot._process(5.0)
	assert_float(boot.clock()).is_equal(0.0)
	boot._process(5.0)
	assert_float(boot.clock()).is_equal_approx(BootScript.MAX_STEP, 0.00001)
	for i in 30:
		boot._process(1.0 / 60.0)
	assert_float(boot.clock()).is_equal_approx(BootScript.MAX_STEP + 0.5, 0.0001)


## The review's timing run: the frame before the dissolve carries the title's first full draw (74 ms on the PC, longer
## on a phone), and the tween had spent it on the dissolve's first step (already 20 % gone in its first frame, a cut at
## 250 ms). A step counts at most MAX_STEP, so the dissolve always takes its frames, the cover only falls (sine in and
## out) and ends at nothing.
func test_a_long_frame_does_not_eat_the_dissolve() -> void:
	var boot = auto_free(BootScript.new())
	boot._dissolve_t = 0.0
	assert_bool(boot._step_dissolve(0.5)).is_false()
	var k0 := 0.5 - 0.5 * cos(PI * BootScript.MAX_STEP / BootScript.DISSOLVE)
	assert_float(boot.modulate.a).is_equal_approx(1.0 - k0, 0.0001)
	assert_float(boot.modulate.a).is_greater(0.95)
	var frames := 1
	var prev: float = boot.modulate.a
	while not boot._step_dissolve(0.5):
		frames += 1
		assert_bool(boot.modulate.a <= prev).is_true()
		prev = boot.modulate.a
		assert_int(frames).is_less(100)
	frames += 1
	assert_int(frames).is_greater_equal(ceili(BootScript.DISSOLVE / BootScript.MAX_STEP))
	assert_float(boot.modulate.a).is_equal_approx(0.0, 0.0001)


func test_boot_hands_over_to_the_title_after_the_drop_and_dissolves() -> void:
	Settings.menu_style = "live"
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = host
	host.add_child(boot)
	# one draw over the whole screen: the paper rect, then the wallpaper's rect with its shader and its two pictures
	assert_int(boot.get_child_count()).is_equal(2)
	var wall := boot.get_node("Wallpaper") as ColorRect
	assert_object(wall).is_not_null()
	assert_bool(wall.get_rect().encloses(Rect2(Vector2.ZERO, boot.get_viewport_rect().size))).is_true()
	var mat := wall.material as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_bool(boot.has_wallpaper()).is_true()
	assert_object(mat.get_shader_parameter("plate")).is_not_null()
	# the camera cutout's band waits while the loading screen shows
	var band := get_tree().root.get_node_or_null("CutoutBand") as CanvasLayer
	if band:
		assert_bool(band.visible).is_false()
	var title: Node = await await_signal_on(boot, "handed_over", [], 30000)
	assert_object(title).is_not_null()
	assert_str(title.scene_file_path).is_equal(TITLE)
	assert_object(title.get_parent()).is_same(host)
	# the title is not left half faded: the loading screen dissolves into it
	assert_float((title as CanvasItem).modulate.a).is_equal(1.0)
	# from the dissolve on, the one draw is the whole screen: the paper rect under it is gone
	assert_bool((boot.get_node("ColorRect") as CanvasItem).visible).is_false()
	# the plate landed and settled before the title was built, and the screen held until MIN_SHOW
	_in_order(boot, ["fade_in", "landed", "settled", "built", "first_frame", "dissolve"])
	assert_float(boot.event_time("loaded")).is_greater_equal(0.0)
	assert_float(boot.event_time("dissolve")).is_greater_equal(BootScript.MIN_SHOW)
	for key in ["engine", "load", "build", "first_frame"]:
		assert_bool(boot.timings.has(key)).override_failure_message(key).is_true()
	# it dissolves and goes, and the band comes back
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()
	if band:
		assert_bool(band.visible).is_true()
		for c in band.get_children():
			if c is CanvasItem:
				assert_float((c as CanvasItem).modulate.a).is_equal(1.0)


## The review's case: after a threaded load FAILS, Godot 4.7.2 keeps the failed task under its path until it is fetched,
## and a plain load() or change_scene_to_file() of the path gives nothing, so the old fallback could never bring the
## title up. Boot fetches the failed task and reads the file again past the cache: a title that failed once (broken on
## disk for the threaded load, mended before the second) still comes up.
func test_a_failed_threaded_load_still_brings_the_title_up() -> void:
	_write(STAND_IN, BROKEN_SCENE)
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = host
	boot.title_path = STAND_IN
	var why := []
	boot.load_failed.connect(func(w: String) -> void:
		why.append(w)
		_write(STAND_IN, GOOD_SCENE))
	host.add_child(boot)
	var title: Node = await await_signal_on(boot, "handed_over", [], 10000)
	assert_object(title).is_not_null()
	assert_str(title.name).is_equal("Good")
	assert_str(title.scene_file_path).is_equal(STAND_IN)
	assert_object(title.get_parent()).is_same(host)
	assert_int(why.size()).is_equal(1)
	assert_str(str(why[0])).contains("failed")
	assert_bool(boot.failed).is_false()
	_in_order(boot, ["landed", "built", "dissolve"])
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()


## A title that cannot be read at all: the loading screen stays and says so on a card under the plate (it used to sit
## there with no word of why), and its wallpaper stops: its motion means "still loading".
func test_a_title_that_cannot_load_is_said_on_the_screen() -> void:
	_write(STAND_IN, BROKEN_SCENE)
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = host
	boot.title_path = STAND_IN
	host.add_child(boot)
	var waited := 0
	while not boot.failed and waited < 5000:
		await await_millis(50)
		waited += 50
	assert_bool(boot.failed).is_true()
	assert_object(boot.title).is_null()
	var card := boot.get_node_or_null("Error") as Control
	assert_object(card).is_not_null()
	assert_float(card.position.y).is_greater(boot.plate_rest_foot().y)
	var t0: float = boot.clock()
	await await_millis(200)
	assert_bool(is_instance_valid(boot)).is_true()
	assert_float(boot.modulate.a).is_equal(1.0)
	assert_float(boot.clock()).is_equal(t0)
	assert_float(boot.event_time("dissolve")).is_less(0.0)
	boot.free()


## A threaded load whose progress never moves (its status in progress for good) used to leave the bar creeping for
## ever: once it has sat still for stall_limit, Boot loads the title at once, past the stuck task, and hands over.
func test_a_load_that_never_moves_is_given_up_on() -> void:
	_write(STAND_IN, GOOD_SCENE)
	var host: Node = auto_free(Node.new())
	add_child(host)
	var boot: Control = StuckBoot.new()
	boot.host = host
	boot.title_path = STAND_IN
	boot.stall_limit = 0.3
	var why := []
	boot.load_failed.connect(func(w: String) -> void: why.append(w))
	host.add_child(boot)
	var title: Node = await await_signal_on(boot, "handed_over", [], 10000)
	assert_object(title).is_not_null()
	assert_str(title.name).is_equal("Good")
	assert_int(why.size()).is_equal(1)
	assert_str(str(why[0])).contains("25%")
	assert_bool(boot.timings.has("load")).is_true()
	# the stall clock runs on frame deltas, the timing on the wall clock: a frame of slack (it read 298.8 once)
	assert_float(float(boot.timings["load"])).is_greater_equal(270.0)
	_in_order(boot, ["landed", "settled", "built", "dissolve"])
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()
