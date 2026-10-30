## Pass 102, lane STEADY (Garry's phone run fell from 60 to 15-27 fps in late Endless; "Let's go with those fixes yea"):
## the world's catch-up is capped at two 60 Hz steps a frame while the game plays (Game.CATCH_UP_STEPS), and Godot
## then shortens the frame's delta by the steps it dropped, so everything on _process slows with the world; the rules
## that counted the wall clock in play count the game's own clock (Run.play_clock via Run.rule_seconds); and the run
## record's schema 4 says what each second's frames cost (WorkClock: world steps, their time, the process time, the
## rest, the world time the cap dropped) with a heat table by minute and crowd band. The dashboard, sim_avg.js and the
## CSVs are checked by tools/level_editor/selftest_STEADY102.py; the whole game at 30 fps, 60 fps and overloaded by
## game/tools/steady_check.gd.
extends GdUnitTestSuite

const FAKE_GAME := """extends Node
var enemies = null
var director = null
var player = null
var projectiles = null
var pickups = null
"""


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	RunAnalytics.I = null


func after_test() -> void:
	RunAnalytics.I = null
	Run.sim_clock = false
	Run.sim_mode = false


func _fake_game() -> Node:
	var s := GDScript.new()
	s.source_code = FAKE_GAME
	s.reload()
	var g: Node = auto_free(Node.new())
	g.set_script(s)
	add_child(g)
	return g


func _recorder(g: Node) -> RunAnalytics:
	var ra := RunAnalytics.new()
	ra.mirror = false
	ra.memory_only = true
	g.add_child(ra)
	ra.begin(g)
	return ra


func _spin(ms: int) -> void:
	var t := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < ms * 1000:
		pass


# ---------------------------------------------------------------- the cap

func test_the_catch_up_is_capped_at_two_steps_while_the_game_plays() -> void:
	# the game scene sets it (Game._ready) and puts Godot's own back for the menus (Game._exit_tree)
	var G: GDScript = load("res://game/Game.gd")
	assert_int(int(G.get_script_constant_map()["CATCH_UP_STEPS"])).is_equal(2)
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(src.contains("Engine.max_physics_steps_per_frame = CATCH_UP_STEPS")).is_true()
	assert_bool(src.contains("Engine.max_physics_steps_per_frame = int(ProjectSettings.get_setting(\"physics/common/max_physics_steps_per_frame\", 8))")).is_true()
	assert_int(int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8))).is_equal(8)
	assert_int(Engine.physics_ticks_per_second).is_equal(60)


func test_an_overlong_frame_gets_a_delta_of_at_most_the_capped_steps() -> void:
	# a 120 ms frame would owe seven 60 Hz steps: the engine runs two and the next frame's delta is two steps long, so
	# every _process (weapons, Fx, the HUD's clock, the director) moves as far as the world did
	var keep := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 2
	await get_tree().process_frame
	var pf0 := Engine.get_physics_frames()
	_spin(120)
	await get_tree().process_frame
	var steps := Engine.get_physics_frames() - pf0
	var d := get_process_delta_time()
	Engine.max_physics_steps_per_frame = keep
	assert_int(steps).is_less_equal(2)
	# (Godot's jitter fix moves a delta by up to a step; the wall frame was 120 ms)
	assert_float(d).is_less(3.0 / 60.0 + 0.002)


# ---------------------------------------------------------------- the rules' clock

func test_the_rules_count_the_games_own_clock_in_play() -> void:
	Run.sim_clock = false
	Run.sim_mode = false
	assert_float(Run.rule_seconds()).is_equal(Run.play_clock)
	assert_int(Run._rebuild_clock_ms()).is_equal(int(Run.play_clock * 1000.0))
	var c0 := Run.play_clock
	var sum := 0.0
	for k in range(5):
		await get_tree().process_frame
		sum += get_process_delta_time()
	# it advances by the frames' deltas (the autoload's own _process)
	assert_float(Run.play_clock - c0).is_equal_approx(sum, 0.05)
	assert_float(Run.play_clock - c0).is_greater(0.0)
	# a run sim still counts the run's clock
	Run.elapsed = 12.5
	Run.held_time = 0.0
	Run.sim_clock = true
	assert_float(Run.rule_seconds()).is_equal_approx(12.5, 0.0001)
	Run.elapsed = 0.0


# ---------------------------------------------------------------- the work clock

func test_the_work_clock_folds_a_second() -> void:
	var w: WorkClock = auto_free(WorkClock.new())
	w.steps_cap = 2
	w.count_lost = true
	# two overloaded frames: 50 ms wall, two steps of 10 ms (the slowest 11), 8 ms of process, the delta two steps
	w.add_frame(50000, 2, 20000, 11000, 8000, 2.0 / 60.0)
	w.add_frame(50000, 2, 20000, 11000, 8000, 2.0 / 60.0)
	# one easy frame: 16 ms, one step of 4 ms, 3 ms of process
	w.add_frame(16000, 1, 4000, 4000, 3000, 1.0 / 60.0)
	var row := {}
	w.put_second(row)
	assert_int(int(row["steps"])).is_equal(5)
	assert_int(int(row["steps_max"])).is_equal(2)
	assert_float(float(row["phys_ms"])).is_equal_approx(44.0 / 5.0, 0.006)
	assert_float(float(row["phys_max"])).is_equal_approx(11.0, 0.001)
	assert_float(float(row["proc_ms"])).is_equal_approx(19.0 / 3.0, 0.006)
	assert_float(float(row["proc_max"])).is_equal_approx(8.0, 0.001)
	# rest: (50-20-8) x 2 + (16-4-3) = 53 ms over 3 frames
	assert_float(float(row["rest_ms"])).is_equal_approx(53.0 / 3.0, 0.051)
	# lost: two frames of 50 ms whose delta was 33.3 ms
	assert_int(int(row["lost_ms"])).is_equal(33)
	assert_int(w.frames_total).is_equal(3)
	assert_int(w.steps_total).is_equal(5)
	# the next second starts over: nothing without a frame
	var row2 := {}
	w.put_second(row2)
	assert_bool(row2.is_empty()).is_true()
	# a clock that cannot see lost time (headless, --fixed-fps) leaves it out; under the cap nothing is lost either
	w.count_lost = false
	w.add_frame(50000, 2, 20000, 11000, 8000, 2.0 / 60.0)
	w.put_second(row2)
	assert_bool(row2.has("lost_ms")).is_false()
	w.count_lost = true
	var row3 := {}
	w.add_frame(40000, 1, 10000, 10000, 8000, 1.0 / 60.0)
	w.put_second(row3)
	assert_bool(row3.has("lost_ms")).is_false()


func test_the_markers_bracket_every_callback_and_count_live_frames() -> void:
	var ra := _recorder(_fake_game())
	var w := ra.work
	assert_object(w).is_not_null()
	var first: Node = w.get_node("First")
	var last: Node = w.get_node("Last")
	assert_int(first.process_priority).is_equal(-WorkClock.EDGE)
	assert_int(first.process_physics_priority).is_equal(-WorkClock.EDGE)
	assert_int(last.process_priority).is_equal(WorkClock.EDGE)
	assert_int(last.process_physics_priority).is_equal(WorkClock.EDGE)
	# ten played frames (ticked like Game._process does): the second has them
	for k in range(10):
		await get_tree().process_frame
		ra.tick(0.0)
	var row := {}
	w.put_second(row)
	assert_bool(row.has("steps")).is_true()
	assert_float(float(row["proc_ms"])).is_greater_equal(0.0)
	assert_int(int(row["steps_max"])).is_less_equal(Engine.max_physics_steps_per_frame)


# ---------------------------------------------------------------- the record

func test_schema_4_rows_and_header() -> void:
	var ra := _recorder(_fake_game())
	# pass 115 (lane DASH): schema 5 (pass115_DASH_test), re-pinned on purpose
	assert_int(RunAnalytics.SCHEMA).is_equal(5)
	assert_int(int(ra.header["schema"])).is_equal(5)
	# (the test runner plays no Game: Godot's own 8)
	assert_int(int(ra.header["frame_timing"]["max_steps"])).is_equal(Engine.max_physics_steps_per_frame)
	ra.work.add_frame(20000, 1, 6000, 6000, 5000, 1.0 / 60.0)
	ra._sample()
	var row: Dictionary = ra.samples[-1]
	for k in ["steps", "steps_max", "phys_ms", "phys_max", "proc_ms", "proc_max", "rest_ms"]:
		assert_bool(row.has(k)).override_failure_message("the row lacks " + k).is_true()
	# the test runner is headless: no lost time is counted
	assert_bool(ra.work.count_lost).is_false()
	# a second without a counted frame carries none of them
	ra._sample()
	assert_bool((ra.samples[-1] as Dictionary).has("steps")).is_false()
	assert_bool("heat" in RunAnalytics.INDEX_SKIP).is_true()


func _rows_two_minutes() -> Array:
	var rows: Array = []
	for s in range(1, 121):
		# minute one: 120 alive, 60 frames of 16.7 ms, a step 3 ms, 4 ms of process; minute two: the same crowd costs
		# more (a step 4 ms, 6 ms of process), and its last 20 s carry 230 alive at 33 ms frames with the cap biting
		var r := {"t": float(s), "alive": 120, "frames": 60, "frame_ms": 16.7, "steps": 60, "steps_max": 1, "phys_ms": 3.0,
			"proc_ms": 4.0, "rest_ms": 9.7}
		if s > 60:
			r.merge({"phys_ms": 4.0, "proc_ms": 6.0}, true)
		if s > 100:
			r.merge({"alive": 230, "frames": 30, "frame_ms": 33.3, "steps": 60, "steps_max": 2, "phys_ms": 8.0, "proc_ms": 9.0,
				"rest_ms": 8.3, "lost_ms": 40}, true)
		rows.append(r)
	return rows


func test_the_summary_folds_the_work_and_the_heat_table() -> void:
	var sm := RunAnalytics.summary(_rows_two_minutes())
	# minute two: 40 s of 60 steps at 4 ms and 20 s of 60 steps at 8 ms
	assert_array(sm["m_phys_ms"]).is_equal([3.0, 5.33])
	assert_array(sm["m_steps_max"]).is_equal([1, 2])
	assert_array(sm["m_lost_s"]).is_equal([0.0, 0.8])
	# minute one: a frame is one step of 3 ms + 4 ms of process
	assert_float(float(sm["m_work_ms"][0])).is_equal_approx(7.0, 0.001)
	assert_float(float(sm["m_steps"][0])).is_equal_approx(1.0, 0.001)
	assert_int(int(sm["heat_band"])).is_equal(50)
	var hw: Dictionary = sm["heat_work_ms"]
	var hf: Dictionary = sm["heat_frame_ms"]
	# the 100-149 band: the same crowd cost 7 ms then 10 ms of work a frame (heat, or a heavier build)
	assert_array(hw["100"]).is_equal([7.0, 10.0])
	assert_array(hf["100"]).is_equal([16.7, 16.7])
	# the 200-249 band only in minute two (20 s of it): 2 steps of 8 ms + 9 ms
	assert_array(hw["200"]).is_equal([null, 25.0])
	# (snappedf to 0.1 leaves 33.300000000000004: compared within a hair)
	assert_that(hf["200"][0]).is_null()
	assert_float(float(hf["200"][1])).is_equal_approx(33.3, 0.0001)


func test_an_older_record_folds_as_before() -> void:
	var rows: Array = []
	for s in range(1, 70):
		rows.append({"t": float(s), "alive": 20, "frames": 60, "frame_ms": 16.0, "frame_max": 18.0, "frame_p95": 17.0})
	var sm := RunAnalytics.summary(rows)
	for k in ["m_phys_ms", "m_proc_ms", "m_rest_ms", "m_work_ms", "m_steps", "m_steps_max", "m_lost_s", "heat_band", "heat_frame_ms", "heat_work_ms"]:
		assert_bool(sm.has(k)).override_failure_message("a schema 3 record's summary gained " + k).is_false()
	assert_array(sm["m_frame_ms"]).is_equal([16.0, 16.0])
	assert_bool(RunAnalytics.heat_table(rows).is_empty()).is_true()


func test_a_25_minute_record_stays_in_its_parts() -> void:
	# a full row a second for 25 minutes with every schema 4 key, as a phone writes it, goes in at most a few parts
	var rows: Array = []
	for s in range(1, 1501):
		rows.append({"t": float(s), "clock": float(s), "stage": 1, "level": 30, "alive": 200 + s % 50, "cap": 300, "hp": 300.0,
			"hp_max": 400.0, "kills": s * 4, "frames": 58 + s % 3, "frame_ms": 17.2, "frame_max": 31.5, "frame_p95": 22.1,
			"proj": 80, "pickups": 300, "steps": 61 + s % 4, "steps_max": 2, "phys_ms": 5.43 + float(s % 7) * 0.01,
			"phys_max": 9.4, "proc_ms": 6.12, "proc_max": 12.7, "rest_ms": 5.6, "lost_ms": s % 5 * 7,
			"dmg": {"revolver": 1234.5, "frisbee": 820.1}, "near3": 20, "near6": 60})
	var json := JSON.stringify({"schema": 4, "samples": rows, "events": [], "heat": RunAnalytics.heat_table(rows)})
	var parts := Analytics.record_parts(json)
	assert_int(parts.size()).is_greater(0)
	assert_int(parts.size()).is_less_equal(4)
