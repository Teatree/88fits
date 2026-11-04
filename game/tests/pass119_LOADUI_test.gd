## Pass 119, lane LOADUI.
##  - The loading screen's title (Garry: "The title drop style sucks. Make something more action game like, less bouncy
##    and stuff"): the plate punches in from big to its size, faster and faster, and stops dead (never past its size,
##    never back: no squash, no bounce); the hit is a flash held through a hit-stop, then a shake that dies out, a ring,
##    dust, chips and a glint; the title is built only once all of it is over, and the dissolve waits for MIN_SHOW.
##  - The title's look (Garry: "Let's set the "Painted" option as default for now, while keeping the buttons in the
##    Settings for the Debug version of course"): painted is the default, every save is switched to it once, the debug
##    panel's pick sticks after that, and the production build is always painted with no choice offered.
extends GdUnitTestSuite

const BootScript := preload("res://ui/Boot.gd")
const Stage := preload("res://ui/TitleStage.gd")
const DIR := "user://test_saves/pass119_loadui"
const STAND_IN := "user://p119_loadui_stand_in.tscn"
const GOOD_SCENE := "[gd_scene format=3]\n\n[node name=\"Good\" type=\"Control\"]\n"


## A loading screen whose load never finishes (it keeps loading for the length of a test).
class EndlessBoot extends "res://ui/Boot.gd":
	func _request() -> int:
		return OK

	func _status(progress: Array) -> int:
		progress.append(randf())
		return ResourceLoader.THREAD_LOAD_IN_PROGRESS


var _dir_before := ""
var _settings_before: Dictionary = {}
var _last_before := ""


func before() -> void:
	Save.flush()
	_dir_before = Save.dir
	_settings_before = Settings.to_dict()
	_last_before = str(Save.data.get("last_character", Save.DEFAULT_HERO))


func after() -> void:
	_clear()
	Save.dir = _dir_before
	Save.data = Save._default()
	Save.data["last_character"] = _last_before
	Save._dirty = false
	Settings.from_dict(_settings_before)


func after_test() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)
	Stage.forget()
	if FileAccess.file_exists(STAND_IN):
		DirAccess.remove_absolute(STAND_IN)


func _clear() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))


func _write(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _host() -> Node:
	var host: Node = auto_free(Node.new())
	add_child(host)
	return host


# ---------------------------------------------------------------- the slam

## The punch: from PUNCH_FROM times its size to its own in PUNCH, every step smaller and every step bigger than the last
## (it hits at full speed), then exactly its own size from that frame on: never under it, never back over it.
func test_the_plate_punches_in_and_stops_dead() -> void:
	assert_str(BootScript.ENTRANCE).is_equal("punch")
	assert_float(BootScript.PUNCH).is_between(0.08, 0.16)
	assert_float(BootScript.punch_scale(-0.1)).is_equal(BootScript.PUNCH_FROM)
	assert_float(BootScript.punch_scale(0.0)).is_equal(BootScript.PUNCH_FROM)
	assert_float(BootScript.PUNCH_FROM).is_greater(2.0)
	var dt := 1.0 / 240.0
	var t := 0.0
	var prev := BootScript.punch_scale(0.0)
	var step_prev := 0.0
	while t + dt < BootScript.PUNCH - 0.00001:
		t += dt
		var k := BootScript.punch_scale(t)
		var step := prev - k
		assert_float(step).override_failure_message("t %f" % t).is_greater(0.0)
		assert_float(step).override_failure_message("t %f: %f after %f" % [t, step, step_prev]).is_greater(step_prev - 0.00001)
		step_prev = step
		prev = k
	# the last step before the hit is the fastest of all
	assert_float(step_prev).is_greater((BootScript.PUNCH_FROM - 1.0) * dt / BootScript.PUNCH)
	while t < 2.0:
		t += dt
		if t >= BootScript.PUNCH:
			assert_float(BootScript.punch_scale(t)).override_failure_message("t %f" % t).is_equal(1.0)
	# clear as it begins, solid well before the hit
	assert_float(BootScript.punch_alpha(0.0)).is_equal(0.0)
	assert_float(BootScript.punch_alpha(BootScript.PUNCH * 0.5)).is_equal(1.0)
	# the other entrance tried: the halves reach their rest and stay there
	var dist := 1100.0
	assert_float(BootScript.split_offset(0.0, dist)).is_equal(dist)
	var o_prev := dist
	t = 0.0
	while t < 1.0:
		t += dt
		var o := BootScript.split_offset(t, dist)
		assert_float(o).is_less_equal(o_prev)
		assert_float(o).is_greater_equal(0.0)
		if t >= BootScript.SLIDE:
			assert_float(o).is_equal(0.0)
		o_prev = o
	# the drop's squash-and-bounce numbers are gone
	var consts: Dictionary = (BootScript as Script).get_script_constant_map()
	for gone in ["DROP_AT", "FALL", "SQUASH", "BOUNCE", "SETTLE", "STRETCH", "SQUASH_Y", "SQUASH_X", "BOUNCE_H"]:
		assert_bool(consts.has(gone)).override_failure_message(gone).is_false()


## The hit: the flash full through the hit-stop and only falling after it, the shake still through the hit-stop, then
## jolting, then dying out to nothing at HITSTOP + SHAKE; the speed lines full while the plate comes and gone soon after.
func test_the_hit_flashes_holds_shakes_and_stills() -> void:
	assert_float(BootScript.flash_at(-0.01)).is_equal(0.0)
	assert_float(BootScript.flash_at(0.0)).is_equal(BootScript.FLASH)
	assert_float(BootScript.flash_at(BootScript.HITSTOP * 0.9)).is_equal(BootScript.FLASH)
	var prev := BootScript.FLASH
	var h := BootScript.HITSTOP
	while h < 0.6:
		var f := BootScript.flash_at(h)
		assert_float(f).is_less_equal(prev)
		prev = f
		h += 1.0 / 120.0
	assert_float(prev).is_equal(0.0)
	assert_float(BootScript.flash_at(0.3)).is_equal(0.0)
	# the shake
	assert_bool(BootScript.shake_at(-0.1).is_zero_approx()).is_true()
	assert_bool(BootScript.shake_at(BootScript.HITSTOP * 0.5).is_zero_approx()).is_true()
	var most := 0.0
	h = BootScript.HITSTOP
	while h < BootScript.HITSTOP + BootScript.SHAKE:
		var s := BootScript.shake_at(h)
		assert_float(s.length()).is_less_equal(BootScript.SHAKE_PX * 1.6)
		most = maxf(most, s.length())
		h += 1.0 / 120.0
	assert_float(most).is_greater(BootScript.SHAKE_PX * 0.5)
	assert_bool(BootScript.shake_at(BootScript.HITSTOP + BootScript.SHAKE).is_zero_approx()).is_true()
	assert_bool(BootScript.shake_at(2.0).is_zero_approx()).is_true()
	# its first jolt is its biggest stretch: (1 - k)^2 shrinks it every frame after
	assert_float(BootScript.shake_at(BootScript.HITSTOP + BootScript.SHAKE * 0.8).length()).is_less(BootScript.SHAKE_PX * 0.1)
	# the speed lines
	assert_float(BootScript.speed_at(-0.01, "punch")).is_equal(0.0)
	assert_float(BootScript.speed_at(BootScript.PUNCH * 0.5, "punch")).is_equal(1.0)
	assert_float(BootScript.speed_at(BootScript.PUNCH + BootScript.LINES_OUT, "punch")).is_equal(0.0)


## The timeline: the hit at SLAM_AT + PUNCH, everything over (the title may be built) a little after a second, the
## dissolve no sooner than MIN_SHOW, which leaves the settled plate a moment on its own.
func test_the_slam_settles_before_min_show() -> void:
	var boot = auto_free(BootScript.new())
	assert_float(boot.impact_time()).is_equal_approx(BootScript.SLAM_AT + BootScript.PUNCH, 0.00001)
	assert_float(boot.settle_time()).is_greater_equal(boot.impact_time() + BootScript.GLINT_AT + BootScript.GLINT - 0.00001)
	assert_float(boot.settle_time()).is_greater_equal(boot.impact_time() + BootScript.HITSTOP + BootScript.DEBRIS - 0.00001)
	assert_float(boot.settle_time()).is_greater_equal(boot.impact_time() + BootScript.HITSTOP + BootScript.SHAKE - 0.00001)
	assert_float(boot.settle_time()).is_less_equal(BootScript.MIN_SHOW - 0.1)
	assert_float(BootScript.MIN_SHOW).is_less_equal(1.2)


## A live screen, still loading: before the hit the plate is coming (smeared, lines on), at the hit the flash and the
## thud, after the slam the plate rests whole and still, the screen does not shake, and the events say so in order.
func test_a_live_screen_slams_the_title_in() -> void:
	var boot = _endless()
	_host().add_child(boot)
	var mat := (boot.get_node("Wallpaper") as CanvasItem).material as ShaderMaterial
	var waited := 0
	while boot.clock() < BootScript.SLAM_AT + BootScript.PUNCH * 0.5 and waited < 5000:
		await await_millis(5)
		waited += 5
	if boot.clock() < BootScript.SLAM_AT + BootScript.PUNCH:
		assert_float(float(mat.get_shader_parameter("plate_on"))).is_equal(1.0)
		assert_float(float(mat.get_shader_parameter("plate_scale"))).is_greater(1.0)
		assert_float(float(mat.get_shader_parameter("speed"))).is_equal(1.0)
		assert_float(float(mat.get_shader_parameter("hit_t"))).is_less(0.0)
		assert_bool(boot._thud_done).is_false()
	while not boot.is_settled() and waited < 8000:
		await await_millis(20)
		waited += 20
	await await_millis(40)
	assert_bool(boot.is_settled()).is_true()
	assert_bool(boot._thud_done).is_true()
	var landed: float = boot.event_time("landed")
	assert_float(landed).is_between(boot.impact_time(), boot.impact_time() + 0.1)
	assert_float(boot.event_time("settled")).is_greater_equal(boot.settle_time() - 0.0001)
	assert_bool(boot.plate_pose().is_equal_approx(Vector3(0.0, 1.0, 1.0))).is_true()
	assert_float(float(mat.get_shader_parameter("plate_scale"))).is_equal(1.0)
	assert_float(float(mat.get_shader_parameter("scale_prev"))).is_equal(1.0)
	assert_float(float(mat.get_shader_parameter("plate_alpha"))).is_equal(1.0)
	assert_float(float(mat.get_shader_parameter("speed"))).is_equal(0.0)
	assert_float(float(mat.get_shader_parameter("flash"))).is_equal(0.0)
	assert_float(float(mat.get_shader_parameter("glint_t"))).is_less(0.0)
	assert_bool((mat.get_shader_parameter("shake") as Vector2).is_zero_approx()).is_true()
	assert_float(float(mat.get_shader_parameter("hit_t"))).is_greater(BootScript.HITSTOP + BootScript.DEBRIS)
	# still loading, so it waits and the wallpaper keeps moving
	assert_float(boot.event_time("dissolve")).is_less(0.0)
	boot.free()


func _endless() -> Control:
	var b: Control = load("res://ui/Boot.tscn").instantiate()
	b.set_script(EndlessBoot)
	b.stall_limit = 1000.0
	return b


## The title is built only once the slam is over, and the dissolve waits for MIN_SHOW even when the load was done at once.
func test_the_title_waits_for_the_slam() -> void:
	_write(STAND_IN, GOOD_SCENE)
	var boot: Control = load("res://ui/Boot.tscn").instantiate()
	boot.host = _host()
	boot.title_path = STAND_IN
	boot.host.add_child(boot)
	await await_signal_on(boot, "handed_over", [], 10000)
	assert_float(boot.event_time("loaded")).is_less(boot.event_time("landed"))
	assert_float(boot.event_time("settled")).is_less_equal(boot.event_time("built"))
	assert_float(boot.event_time("dissolve")).is_greater_equal(BootScript.MIN_SHOW)
	assert_float(boot.event_time("dissolve")).is_less(BootScript.MIN_SHOW + 0.5)
	await await_millis(int(BootScript.DISSOLVE * 1000.0) + 400)
	assert_bool(is_instance_valid(boot)).is_false()


## The thud and the boom under it are sounds the map binds; the slam's colours are the kit's.
func test_the_thud_and_the_boom_are_bound() -> void:
	for list: Array in [BootScript.THUD, BootScript.BOOM]:
		var bound := false
		for id in list:
			bound = bound or not Registry.soundmap.entry(str(id)).is_empty()
		assert_bool(bound).override_failure_message(str(list)).is_true()
	assert_bool(BootScript.palette("chip_ink").is_equal_approx(R.NAVY)).is_true()
	assert_bool(BootScript.palette("chip_brass").is_equal_approx(R.GOLD_TEXT)).is_true()


# ---------------------------------------------------------------- the painted title



## Every save is switched to painted once (a save from before holds "live"); the flag goes on every save, a new one too,
## and after it the save's own pick sticks.


## The production build: the title is painted whatever the save says, and Settings offers no choice even if the debug
## panel were shown; the dev build's debug panel keeps both buttons.
