## Pass 101, lane FPS (Garry approved pass 100's fixes 1 and 2: "Cap the phone at 60 fps", "Record frame times every
## second in the run record"): Settings.frame_cap (60 on a phone, the screen's max on the PC, a save without it takes the
## platform's default, never prod-locked, Engine.max_fps follows) and the run record's schema 3 (core/systems/RunAnalytics.gd:
## every row's frames, frame_ms, frame_max, frame_p95, proj and pickups; the header's frame_timing; summary()'s minute
## folds; an old record's rows fold as before). The dashboard, sim_avg.js and the CSVs are checked by
## tools/level_editor/selftest_FPS101.py (Node and Python).
extends GdUnitTestSuite

const FAKE_GAME := """extends Node
var enemies = null
var director = null
var player = null
var projectiles = null
var pickups = null
"""

const FAKE_COUNT := """extends Node
var count := 0
"""

var _keep_cap := 0
var _keep_engine := 0


func before_test() -> void:
	_keep_cap = Settings.frame_cap
	_keep_engine = Engine.max_fps
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	RunAnalytics.I = null


func after_test() -> void:
	Settings.frame_cap = _keep_cap
	Engine.max_fps = _keep_engine
	RunAnalytics.I = null


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _fake_game(proj: int, lying: int) -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var pm := Node.new()
	pm.set_script(_script(FAKE_COUNT))
	pm.count = proj
	g.add_child(pm)
	g.projectiles = pm
	var pk := Node.new()
	pk.set_script(_script(FAKE_COUNT))
	pk.count = lying
	g.add_child(pk)
	g.pickups = pk
	return g


func _recorder(g: Node) -> RunAnalytics:
	var ra := RunAnalytics.new()
	ra.mirror = false
	ra.memory_only = true
	g.add_child(ra)
	ra.begin(g)
	return ra


# ---------------------------------------------------------------- the cap

func test_the_cap_is_60_on_a_phone_and_the_screens_max_on_the_pc() -> void:
	assert_int(Settings.default_frame_cap(true)).is_equal(60)
	assert_int(Settings.default_frame_cap(false)).is_equal(0)
	# this process is the PC: a save without the key keeps today's behaviour (no cap but vsync's)
	Settings.from_dict({})
	assert_int(Settings.frame_cap).is_equal(Settings.default_frame_cap(OS.has_feature("mobile")))
	assert_int(Engine.max_fps).is_equal(maxi(Settings.frame_cap, 0))


func test_the_cap_reaches_the_engine_and_the_save() -> void:
	Settings.from_dict({"frame_cap": 60})
	assert_int(Settings.frame_cap).is_equal(60)
	assert_int(Engine.max_fps).is_equal(60)
	assert_int(int(Settings.to_dict()["frame_cap"])).is_equal(60)
	Settings.frame_cap = 0
	assert_int(Engine.max_fps).is_equal(0)
	assert_int(int(Settings.to_dict()["frame_cap"])).is_equal(0)
	# a value that is not a step reads as the platform's default
	Settings.frame_cap = 45
	assert_int(Settings.frame_cap).is_equal(Settings.default_frame_cap(OS.has_feature("mobile")))


func test_the_developer_menu_steps_round_60_and_max() -> void:
	assert_int(Settings.next_frame_cap(60)).is_equal(0)
	assert_int(Settings.next_frame_cap(0)).is_equal(60)
	assert_str(Settings.frame_cap_label(60)).is_equal("60")
	assert_str(Settings.frame_cap_label(0)).is_equal("MAX")
	# a setting, not a developer switch the production build holds
	assert_bool(Settings.PROD_LOCKED.has("frame_cap")).is_false()


func test_the_developer_menu_has_the_row() -> void:
	var menu: Node = auto_free(load("res://ui/DevMenu.tscn").instantiate())
	add_child(menu)
	await get_tree().process_frame
	var row: Node = menu.find_child("FrameCap", true, false)
	assert_object(row).is_not_null()
	var val: Node = row.find_child("Value", true, false)
	assert_str(str(val.get("text"))).is_equal(Settings.frame_cap_label())


# ---------------------------------------------------------------- the record

func test_schema_3_and_the_frame_timing_header() -> void:
	var ra := _recorder(_fake_game(0, 0))
	# pass 102 (lane STEADY): schema 4 (the rows' work times, pass102_steady_test); pass 115 (lane DASH): schema 5
	# (pass115_DASH_test), re-pinned on purpose
	assert_int(RunAnalytics.SCHEMA).is_equal(5)
	assert_int(int(ra.header["schema"])).is_equal(5)
	var ft: Dictionary = ra.header["frame_timing"]
	for k in ["valid", "why", "max_fps", "frame_cap", "vsync", "refresh_hz", "physics_hz"]:
		assert_bool(ft.has(k)).override_failure_message("frame_timing lacks " + k).is_true()
	# the test runner is headless: its frame clock says nothing about a player's frame rate, and the record says so
	assert_bool(bool(ft["valid"])).is_false()
	assert_str(str(ft["why"])).is_equal("headless")
	assert_int(int(ft["physics_hz"])).is_equal(Engine.physics_ticks_per_second)


func test_a_row_carries_its_seconds_frames_the_shots_and_the_pickups() -> void:
	var ra := _recorder(_fake_game(37, 412))
	# twenty frames: 10, 11, ... 29 ms
	for i in range(20):
		ra._sec_ms.append(10.0 + float(i))
	ra._sample()
	var row: Dictionary = ra.samples[-1]
	assert_int(int(row["frames"])).is_equal(20)
	assert_float(float(row["frame_ms"])).is_equal_approx(19.5, 0.001)
	assert_float(float(row["frame_max"])).is_equal_approx(29.0, 0.001)
	# nearest rank: the 19th of 20 (ceil(0.95 x 20))
	assert_float(float(row["frame_p95"])).is_equal_approx(28.0, 0.001)
	assert_int(int(row["proj"])).is_equal(37)
	assert_int(int(row["pickups"])).is_equal(412)
	# the next second starts over; a second without a frame still says it measured none
	ra._sample()
	var row2: Dictionary = ra.samples[-1]
	assert_int(int(row2["frames"])).is_equal(0)
	assert_bool(row2.has("frame_ms")).is_false()


func test_a_frame_counts_only_straight_after_the_last_ticked_one() -> void:
	var ra := _recorder(_fake_game(0, 0))
	var pf := Engine.get_process_frames()
	# the last tick was the frame before this one, 20 ms ago: a frame of 20 ms (a hitch of 400 ms counts too)
	ra._frame_last_us = Time.get_ticks_usec() - 20000
	ra._frame_last_pf = pf - 1
	ra._frame()
	assert_int(ra._sec_ms.size()).is_equal(1)
	assert_float(ra._sec_ms[0]).is_between(19.0, 60.0)
	ra._frame_last_us = Time.get_ticks_usec() - 400000
	ra._frame_last_pf = pf - 1
	ra._frame()
	assert_int(ra._sec_ms.size()).is_equal(2)
	assert_float(ra._sec_ms[1]).is_greater(399.0)
	# three frames since the last tick (a pause, a card screen): not a frame
	ra._frame_last_us = Time.get_ticks_usec() - 50000
	ra._frame_last_pf = pf - 3
	ra._frame()
	assert_int(ra._sec_ms.size()).is_equal(2)


func test_the_summary_folds_the_frames_into_minutes() -> void:
	var rows: Array = []
	for s in range(1, 121):
		# minute one: 60 frames of 16 ms; minute two: 30 frames of 33 ms, one second with a 120 ms hitch
		var r := {"t": float(s), "proj": 10 if s <= 60 else 30, "pickups": 100}
		if s <= 60:
			r.merge({"frames": 60, "frame_ms": 16.0, "frame_max": 18.0, "frame_p95": 17.0})
		else:
			r.merge({"frames": 30, "frame_ms": 33.0, "frame_max": 120.0 if s == 90 else 40.0, "frame_p95": 36.0})
		rows.append(r)
	var sm := RunAnalytics.summary(rows)
	assert_array(sm["m_frames"]).is_equal([3600, 1800])
	assert_array(sm["m_frame_ms"]).is_equal([16.0, 33.0])
	assert_array(sm["m_fps"]).is_equal([62.5, 30.3])
	assert_array(sm["m_frame_max"]).is_equal([18.0, 120.0])
	assert_array(sm["m_frame_p95"]).is_equal([17.0, 36.0])
	assert_array(sm["m_proj"]).is_equal([10, 30])
	assert_array(sm["m_pickups"]).is_equal([100, 100])


func test_an_old_record_folds_as_before() -> void:
	# a schema 2 row has no frames, no shots, no pickups: the summary carries none of the new arrays
	var rows: Array = []
	for s in range(1, 70):
		rows.append({"t": float(s), "alive": 20, "cap": 30, "hp": 80.0, "hp_max": 100.0})
	var sm := RunAnalytics.summary(rows)
	for k in ["m_frames", "m_frame_ms", "m_fps", "m_frame_max", "m_frame_p95", "m_proj", "m_pickups"]:
		assert_bool(sm.has(k)).override_failure_message("an old record's summary gained " + k).is_false()
	assert_array(sm["m_alive"]).is_equal([20, 20])


func test_run_summary_says_the_cap_and_whether_the_clock_means_anything() -> void:
	var ra := _recorder(_fake_game(0, 0))
	var p := ra._summary_props()
	assert_int(int(p["frame_cap"])).is_equal(Engine.max_fps)
	assert_bool(bool(p["frame_valid"])).is_false()
