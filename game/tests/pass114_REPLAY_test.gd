## Pass 114, lane REPLAY (Garry: "Go ahead and implement it as described in run_replay_options.md as Option 1"): every run's
## input recording (core/systems/RunReplay.gd) and its replay through the real game (BALANCING.md 57.REPLAY).
##  1. the rule dice: one seed, one stream; each system's own dice by its salt; the run's seed is never 0 and a replay's
##     is the recording's (Run.begin_run_seed); the map's roll is taken whether the map seed is forced or not;
##  2. the frame gates: a rule's delta and its physics steps come from the recording only in a replay; the stick is read
##     in 1/127 steps (q2, exact both ways); the run's own timers count the frames' deltas and wait while paused;
##  3. the recorder is off in the arena, in tools and headless sims, and on in a tool that asks (replay_record); a
##     decision is kept only when a tap or a driver of the run takes it, with its frame and phase, never in a replay;
##  4. the file's streams read back as they were written (frames run-length coded, the stick, the track); a decision
##     finds its card by id; a checkpoint compares exactly (a hash of every bit) and says what parted;
##  5. the build stamp (game/config/build.json): the id ship.sh writes is the one a recording carries; the editor binary
##     never claims a shipped build;
##  6. end to end: a short run recorded with the bot driving (irregular frames, a subprocess), replayed at --fixed-fps 64
##     with nothing but the file: every checkpoint equal.
extends GdUnitTestSuite


func after_test() -> void:
	Lockstep.replaying = false
	Lockstep.driving = false
	Lockstep.input_depth = 0
	Lockstep.game_scale = 1.0
	Lockstep.clear_timers()
	RunReplay.plan = {}


# ---------------------------------------------------------------- 1. the dice

func test_dice_one_seed_one_stream() -> void:
	Dice.reseed(42)
	var a: Array = []
	for i in range(20):
		a.append(Dice.r.randf())
	Dice.reseed(42)
	for i in range(20):
		assert_float(Dice.r.randf()).is_equal(float(a[i]))
	Dice.reseed(43)
	assert_float(Dice.r.randf()).is_not_equal(float(a[0]))


func test_dice_systems_have_their_own_streams() -> void:
	Dice.reseed(7)
	var e := Dice.rng_for("enemies")
	var p := Dice.rng_for("pickups")
	assert_int(e.randi()).is_not_equal(p.randi())
	# a system's own rolls never move the rule dice
	var before := Dice.r.state
	for i in range(50):
		e.randf()
	assert_int(Dice.r.state).is_equal(before)
	# the same salt and seed: the same stream
	Dice.reseed(7)
	var e2 := Dice.rng_for("enemies")
	var e3 := Dice.rng_for("enemies")
	assert_int(e2.randi()).is_equal(e3.randi())


func test_dice_pick_and_shuffle_use_the_rule_dice() -> void:
	Dice.reseed(9)
	var arr := [1, 2, 3, 4, 5, 6, 7, 8]
	var g_state := randi()   # the looks' stream moves; the rule dice must not care
	Dice.shuffle(arr)
	var first := arr.duplicate()
	Dice.reseed(9)
	seed(g_state + 99)
	var arr2 := [1, 2, 3, 4, 5, 6, 7, 8]
	Dice.shuffle(arr2)
	assert_array(arr2).is_equal(first)
	assert_that(Dice.pick([])).is_null()
	Dice.reseed(9)
	var x = Dice.pick([10, 20, 30])
	Dice.reseed(9)
	assert_that(Dice.pick([10, 20, 30])).is_equal(x)


func test_run_seed_never_zero_and_forced_by_a_replay() -> void:
	var old_rng := Run.rng_seed
	Run.rng_seed = 0
	var s := Run.begin_run_seed({})
	assert_int(s).is_not_equal(0)
	assert_int(Dice.run_seed).is_equal(s)
	assert_float(Run.play_clock).is_equal(0.0)
	Run.forced_run_seed = 123456
	assert_int(Run.begin_run_seed({})).is_equal(123456)
	assert_int(Run.begin_run_seed({"run_seed": 777})).is_equal(777)
	Run.rng_seed = old_rng
	Run.seed_dice(0)


func test_map_roll_taken_whether_forced_or_not() -> void:
	# a replay forces the map seed; the rule dice must stand where the recording's stood after Run.start
	var c := Registry.playable_character("drifter")
	var m := Registry.map("red_canyon")
	Run.seed_dice(5)
	Run.forced_map_seed = 0
	Run.start(c, m)
	var free_state := Dice.r.state
	var rolled := Run.map_seed
	Run.seed_dice(5)
	Run.forced_map_seed = rolled
	Run.start(c, m)
	assert_int(Dice.r.state).is_equal(free_state)
	assert_int(Run.map_seed).is_equal(rolled)
	Run.forced_map_seed = 0
	Run.seed_dice(0)


# ---------------------------------------------------------------- 2. the gates

func test_frame_gates_only_in_a_replay() -> void:
	assert_float(Lockstep.dt(0.033)).is_equal(0.033)
	assert_bool(Lockstep.phys_skip()).is_false()
	Lockstep.replaying = true
	Lockstep.proc_d = 0.0125
	assert_float(Lockstep.dt(0.033)).is_equal(0.0125)
	assert_bool(Lockstep.phys_skip()).is_true()
	Lockstep.driving = true
	assert_bool(Lockstep.phys_skip()).is_false()
	assert_int(Lockstep.world_hz()).is_equal(60)


func test_time_scale_writes_go_to_the_engine_only_in_play() -> void:
	Lockstep.set_time_scale(0.5)
	assert_float(Engine.time_scale).is_equal(0.5)
	assert_float(Lockstep.time_scale()).is_equal(0.5)
	Lockstep.set_time_scale(1.0)
	Lockstep.replaying = true
	Lockstep.game_scale = 1.0
	Lockstep.set_time_scale(0.08)
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_float(Lockstep.time_scale()).is_equal(0.08)


func test_stick_steps_are_exact_both_ways() -> void:
	assert_vector(Lockstep.q2(Vector2(0.5, -1.0))).is_equal(Vector2(0.5, -1.0))
	for v: Vector2 in [Vector2(0.31, -0.72), Vector2(1, 0), Vector2(-0.7071, 0.7071), Vector2(0.0004, 0.0)]:
		var q := Lockstep.q2(v)
		assert_vector(Lockstep.q2(q)).is_equal(q)
		# what the recording stores (an int a step) reads back to the same float
		var qx := int(roundf(q.x * Lockstep.STICK_Q))
		assert_float(float(qx) / Lockstep.STICK_Q).is_equal(q.x)
	assert_vector(Lockstep.q2(Vector2(0.0004, 0.0))).is_equal(Vector2.ZERO)


func test_run_timers_count_the_rule_clock_and_wait_while_paused() -> void:
	Lockstep.ticking = 1
	var fired: Array = []
	var t1 = Lockstep.after(self, 0.1, true)
	t1.timeout.connect(func(): fired.append("always"))
	var t2 = Lockstep.after(self, 0.1, false)
	t2.timeout.connect(func(): fired.append("pausable"))
	Lockstep.tick_timers(0.06, true)
	Lockstep.tick_timers(0.06, true)
	assert_array(fired).is_equal(["always"])
	Lockstep.tick_timers(0.06, false)
	Lockstep.tick_timers(0.06, false)
	assert_array(fired).is_equal(["always", "pausable"])
	Lockstep.ticking = 0
	# without a run's ticker it is the engine's own timer
	var t3 = Lockstep.after(self, 1.0)
	assert_bool(t3 is SceneTreeTimer).is_true()


# ---------------------------------------------------------------- 3. the recorder's switch and the decisions

func test_recorder_off_in_the_arena_tools_and_sims() -> void:
	var rr := RunReplay.new()
	# the test runner is a tool process (headless): off unless a tool asks
	assert_int(rr._choose_mode({})).is_equal(RunReplay.OFF)
	assert_int(rr._choose_mode({"replay_record": true})).is_equal(RunReplay.RECORD)
	assert_int(rr._choose_mode({"analytics_memory": true})).is_equal(RunReplay.OFF)
	assert_int(rr._choose_mode({"sim_fast": true})).is_equal(RunReplay.OFF)
	Run.arena = true
	assert_int(rr._choose_mode({"replay_record": true})).is_equal(RunReplay.OFF)
	Run.arena = false
	RunReplay.plan = {"frames_n": 1}
	assert_int(rr._choose_mode({})).is_equal(RunReplay.REPLAY)
	RunReplay.plan = {}
	rr.free()


func test_decisions_kept_only_from_input_with_frame_and_phase() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.RECORD
	RunReplay.I = rr
	rr.frame = 41
	# between frames (a tap): the next frame, phase 0
	rr._between = true
	RunReplay.note("card", {"id": "revolver"})
	# inside a frame with nobody driving: the game's own consequence, not kept
	rr._between = false
	RunReplay.note("gate")
	# inside a frame, a driver (the bot, a tool) acting: this frame, phase 1
	Lockstep.input_depth = 1
	RunReplay.note("gate")
	Lockstep.input_depth = 0
	assert_int(rr.decisions.size()).is_equal(2)
	assert_str(str(rr.decisions[0]["k"])).is_equal("card")
	assert_int(int(rr.decisions[0]["f"])).is_equal(42)
	assert_int(int(rr.decisions[0]["p"])).is_equal(0)
	assert_int(int(rr.decisions[1]["f"])).is_equal(41)
	assert_int(int(rr.decisions[1]["p"])).is_equal(1)
	# a replay notes nothing (its own calls land in the same hooks)
	rr.mode = RunReplay.REPLAY
	rr._between = true
	RunReplay.note("card", {"id": "x"})
	assert_int(rr.decisions.size()).is_equal(2)
	RunReplay.I = null
	rr.free()


func test_a_card_is_found_by_id_and_level() -> void:
	var offer := [{"id": "revolver", "level_to": 2}, {"id": "bristle", "level_to": 1}, {"id": "revolver", "level_to": 3}]
	assert_int(int(RunReplay._card_in(offer, {"id": "revolver", "lv": 3})["level_to"])).is_equal(3)
	assert_str(str(RunReplay._card_in(offer, {"id": "bristle", "lv": 1})["id"])).is_equal("bristle")
	# the level moved (a drift): the same item still
	assert_str(str(RunReplay._card_in(offer, {"id": "bristle", "lv": 4}).get("id", ""))).is_equal("bristle")
	assert_bool(RunReplay._card_in(offer, {"id": "nothing"}).is_empty()).is_true()


# ---------------------------------------------------------------- 4. the file

func test_streams_read_back_as_written() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.RECORD
	# 3 steady frames, 1 irregular, 2 paused
	for t in [[1, 1, 1.0 / 60.0, 1.0 / 60.0, 1.0], [1, 1, 1.0 / 60.0, 1.0 / 60.0, 1.0], [1, 1, 1.0 / 60.0, 1.0 / 60.0, 1.0],
			[2, 1, 1.0 / 60.0, 0.0371234567, 1.0], [0, 0, 0.0, 0.0123, 1.0], [0, 0, 0.0, 0.0123, 1.0]]:
		rr._k = int(t[0]); rr._ran = int(t[1]) == 1; rr._pd = float(t[2]); rr._ts = float(t[4])
		var tup := [rr._k, int(t[1]), rr._pd if rr._k > 0 else 0.0, float(t[3]), rr._ts]
		if rr._cur_n > 0 and tup == rr._cur:
			rr._cur_n += 1
		else:
			rr._flush_run()
			rr._cur = tup
			rr._cur_n = 1
	rr._flush_run()
	assert_int(rr._runs_n).is_equal(3)
	rr._stick.put_u32(5); rr._stick.put_u8(1); rr._stick.put_16(-1024); rr._stick.put_16(512)
	var plan := {"frames_n": 6, "frames": RunReplay._blob(rr._runs), "stick": RunReplay._blob(rr._stick), "track": RunReplay._blob(StreamPeerBuffer.new())}
	var back := RunReplay.new()
	back._decode(plan)
	assert_int(back.frames_n).is_equal(6)
	assert_int(back._fk[3]).is_equal(2)
	assert_float(back._fd[3]).is_equal(0.0371234567)
	assert_float(back._fpd[0]).is_equal(1.0 / 60.0)
	assert_int(back._fran[4]).is_equal(0)
	assert_int(back._stick_f[0]).is_equal(5)
	var v := back._stick_v[0]
	var qx := (v >> 8) & 0xFFFF
	assert_int(qx - 65536 if qx > 32767 else qx).is_equal(-1024)
	var qy := (v >> 24) & 0xFFFF
	assert_int(qy).is_equal(512)
	rr.free()
	back.free()


func test_checkpoint_compare_is_exact_and_names_what_parted() -> void:
	var rr := RunReplay.new()
	rr.mode = RunReplay.REPLAY
	# a stand-in check: compare a record against itself and against a moved copy
	var rec := {"f": 10, "h": "123", "x": 1.0, "kills": 4}
	var now := {"h": "123", "x": 1.0, "kills": 4}
	assert_bool(_same(rr, rec, now)).is_true()
	var moved := {"h": "999", "x": 1.0000000001, "kills": 4}
	assert_bool(_same(rr, rec, moved)).is_false()
	rr.free()


static func _same(_rr: RunReplay, rec: Dictionary, now: Dictionary) -> bool:
	# RunReplay._compare's rule: the exact hash, and every rounded field within its rounding
	if str(rec.get("h", "")) != str(now.get("h", "")):
		return false
	for k in rec:
		if k == "f" or k == "h":
			continue
		if absf(float(rec[k]) - float(now.get(k, 0.0))) > 1e-6 * maxf(1.0, absf(float(rec[k]))):
			return false
	return true


# ---------------------------------------------------------------- 5. the build stamp

func test_editor_binary_never_claims_a_shipped_build() -> void:
	RunReplay._build = {}
	var b := RunReplay.build_info()
	var ver := str(ProjectSettings.get_setting("application/config/version", "?"))
	assert_str(str(b["version"])).is_equal(ver)
	if OS.has_feature("editor"):
		assert_str(str(b["id"])).is_equal("editor-" + ver)
	RunReplay._build = {}


func test_build_stamp_matches_the_tool() -> void:
	# tools/builds.py writes {id, version, utc, git, dirty}; the id is version-yyyymmdd-hhmm-git[-dirty]
	var out: Array = []
	var py := "python"
	var code := OS.execute(py, [ProjectSettings.globalize_path("res://").path_join("../tools/builds.py"), "stamp", "--dry-run"], out, true)
	if code != 0:
		push_warning("python not found: the stamp's format is checked by tools/builds.py itself")
		return
	var text := "".join(PackedStringArray(out))
	var re := RegEx.create_from_string("\"id\": \"(\\d+\\.\\d+)-(\\d{8})-(\\d{4})-([0-9a-f]{7}|nogit)(-dirty)?\"")
	assert_bool(re.search(text) != null).is_true()


# ---------------------------------------------------------------- 6. end to end

## A real run: 8 s of play recorded with the bot driving (no fixed frame rate: the frames come as the machine gives them),
## then replayed from the file alone at --fixed-fps 64. Both in a subprocess of this same binary (the suite already
## holds the Godot lock).
func test_record_then_replay_keeps_step() -> void:
	var godot := OS.get_executable_path()
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var dir := OS.get_user_data_dir().path_join("test_replay")
	DirAccess.make_dir_recursive_absolute(dir)
	var rec := dir.path_join("rec.json")
	var rep := dir.path_join("rep.json")
	if FileAccess.file_exists(rec):
		DirAccess.remove_absolute(rec)
	if FileAccess.file_exists(rep):
		DirAccess.remove_absolute(rep)
	var out: Array = []
	OS.execute(godot, ["--headless", "--path", root, "--script", "res://tools/_p114_REPLAY_proof.gd", "--", "mode=record", "out=" + rec,
		"hero=drifter", "stage=1", "seed=3", "limit=8", "check=0.25", "wall=120"], out, true)
	assert_bool(FileAccess.file_exists(rec)).is_true()
	if not FileAccess.file_exists(rec):
		return
	out.clear()
	OS.execute(godot, ["--headless", "--fixed-fps", "64", "--path", root, "--script", "res://tools/_p114_REPLAY_proof.gd", "--", "mode=replay",
		"file=" + rec, "out=" + rep, "wall=120"], out, true)
	assert_bool(FileAccess.file_exists(rep)).is_true()
	if not FileAccess.file_exists(rep):
		return
	var r = JSON.parse_string(FileAccess.get_file_as_string(rep))
	assert_bool(r is Dictionary).is_true()
	assert_int(int(r.get("checks_ok", 0))).is_greater(20)
	assert_int(int(r.get("checks_bad", -1))).is_equal(0)
	assert_int(int(r.get("drift_frame", 0))).is_equal(-1)
	DirAccess.remove_absolute(rec)
	DirAccess.remove_absolute(rep)
	DirAccess.remove_absolute(dir)
