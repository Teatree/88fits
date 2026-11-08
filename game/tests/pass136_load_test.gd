## Pass 136 (lane LOAD; Garry: "the first time Player starts up a game, and goes into a run, it takes quite a while for the
## first level to load ... the loading screen doesn't move while the game is loading"): the run's strips load on the
## loader threads from the tap (and from the title and the Stages menu ahead of it), the curtain builds the run once they
## have landed and opens on it once its staged warm-up is drawn, the Game's map gets a frame of its own under a curtain,
## and the way in is reported (RunCurtain.load_report, the run record's header `load`). BALANCING.md 77.LOAD.
extends GdUnitTestSuite

const Curtain := preload("res://ui/RunCurtain.gd")
const Stages := preload("res://ui/StagesScreen.gd")


func _creature_strips(n: int) -> Array:
	var out: Array = []
	for id: String in ["lesser_scorpion", "red_goblin", "dune_scorpion", "fire_ant", "bull_beetle", "tumble_imp"]:
		var d: EnemyDef = Registry.enemy(id)
		if d != null and d.strip_path() != "" and not out.has(d.strip_path()):
			out.append(d.strip_path())
		if out.size() >= n:
			break
	return out


func _settle() -> void:
	var waited := 0
	while LookArt.poll() > 0 and waited < 400:
		await get_tree().process_frame
		waited += 1


func test_an_ask_ahead_loads_on_threads_and_holds_until_the_pin() -> void:
	LookArt.clear()
	var paths := _creature_strips(2)
	assert_int(paths.size()).is_equal(2)
	var before := LookArt.loads
	assert_int(LookArt.request(paths)).is_equal(2)
	# asking again while in flight asks nothing
	assert_int(LookArt.request(paths)).is_equal(0)
	await _settle()
	assert_int(LookArt.pending()).is_equal(0)
	for p: String in paths:
		assert_bool(LookArt.is_held(p)).is_true()
		assert_bool(LookArt.is_staged(p)).is_true()
	# the pin finds them held: nothing loaded from disk on the main thread
	assert_int(LookArt.pin_only(paths)).is_equal(0)
	assert_int(LookArt.loads).is_equal(before)
	for p: String in paths:
		assert_bool(LookArt.is_pinned(p)).is_true()
		assert_bool(LookArt.is_staged(p)).is_false()
	LookArt.clear()


func test_a_staged_strip_is_never_let_go_by_the_keep_rule_until_the_pin() -> void:
	LookArt.clear()
	var paths := _creature_strips(1)
	LookArt.request(paths)
	await _settle()
	# far more than KEEP_MB of hero strips asked after it
	for id: String in DirAccess.get_directories_at("res://content/characters/"):
		var c: CharacterDef = Registry.character(id)
		if c != null and c.strip_path() != "":
			LookArt.tex(c.strip_path())
	assert_bool(LookArt.is_held(paths[0])).is_true()
	# a new ask that leaves it out lets it go to the rule
	LookArt.request([])
	assert_bool(LookArt.is_staged(paths[0])).is_false()
	LookArt.clear()


func test_tex_of_a_strip_in_flight_waits_for_that_one() -> void:
	LookArt.clear()
	var paths := _creature_strips(1)
	LookArt.request(paths)
	var t := LookArt.tex(paths[0])
	assert_object(t).is_not_null()
	assert_int(LookArt.pending()).is_equal(0)
	assert_bool(LookArt.is_held(paths[0])).is_true()
	LookArt.clear()


func test_the_next_runs_strips_are_the_ones_its_game_pins() -> void:
	var map: MapDef = Registry.map("red_canyon")
	var hero: CharacterDef = Registry.character("drifter")
	for stage in [0, 1]:
		var want: Array = RunLooks.plan_for(Registry, map, stage, false, hero)["paths"]
		var got := RunLooks.next_run_paths(get_tree(), stage, "drifter", "red_canyon")
		assert_array(got).is_equal(want)
		# the Outlaw's look last, and every creature the stage brings
		assert_str(str(got[got.size() - 1])).is_equal(Registry.played_look(hero).strip_path())
		assert_int(got.size()).is_greater(5)
	# the arena's set is its dummies
	Run.arena_next = true
	var arena := RunLooks.next_run_paths(get_tree(), 0, "drifter", "red_canyon")
	Run.arena_next = false
	var dummies: Array = RunLooks.plan_for(Registry, map, 0, true, hero)["paths"]
	assert_array(arena).is_equal(dummies)


func test_the_stages_menu_expects_the_furthest_open_stage() -> void:
	var keep: Dictionary = Save.data.duplicate(true)
	Save.data["stages_beaten"] = {}
	assert_int(Stages.likely_stage("red_canyon")).is_equal(0)
	Save.mark_stage_beaten("red_canyon", 0)
	assert_int(Stages.likely_stage("red_canyon")).is_equal(1)
	Save.data = keep
	Save._dirty = false


func test_the_title_and_the_menu_ask_ahead_after_they_have_come_in() -> void:
	var title := FileAccess.get_file_as_string("res://ui/TitleScreen.gd")
	assert_bool(title.contains("create_timer(PREFETCH_AFTER).timeout.connect(_prefetch_run)")).is_true()
	assert_bool(title.contains("RunLooks.prefetch_next(get_tree(), stage, hero, _map_id)")).is_true()
	var menu := FileAccess.get_file_as_string("res://ui/StagesScreen.gd")
	assert_bool(menu.contains("RunLooks.prefetch_next(get_tree(), likely_stage(map_id), \"\", map_id)")).is_true()


func test_the_curtain_waits_for_the_strips_at_most_strip_wait() -> void:
	var c = auto_free((load("res://ui/RunCurtain.gd") as GDScript).new())
	c.title_path = Curtain.GAME
	LookArt.clear()
	var paths := _creature_strips(1)
	LookArt.request(paths)
	# (a strip may land between two lines: then the wait ends at once, which is right too)
	c._clock = 1.2
	var first: bool = c._strips_in()
	assert_bool(first).is_equal(LookArt.pending() == 0 and first)
	c._clock = 1.2 + Curtain.STRIP_WAIT + 0.01
	assert_bool(c._strips_in()).is_true()
	if not first:
		assert_bool(c.timings.has("strips_wait")).is_true()
		assert_float(float(c.timings["strips_wait"])).is_less_equal(Curtain.STRIP_WAIT * 1000.0 + 20.0)
	await _settle()
	# a stand-in scene (the curtain's own tests) never waits on strips
	var d = auto_free((load("res://ui/RunCurtain.gd") as GDScript).new())
	d.title_path = "user://nothing.tscn"
	LookArt.request(_creature_strips(3))
	assert_bool(d._strips_in()).is_true()
	await _settle()
	LookArt.clear()


func test_the_report_says_the_way_in() -> void:
	var c = auto_free((load("res://ui/RunCurtain.gd") as GDScript).new())
	c._t_tap = Time.get_ticks_usec() - 2500000
	c._last_us = c._t_tap
	c.timings = {"load": 9.0, "build": 300.0, "first_frame": 120.0}
	c._count_frame()
	var r: Dictionary = c.load_report()
	for k in ["tap_to_open_ms", "longest_frame_ms", "slow_frames", "frames", "session_run", "load_ms", "build_ms",
			"first_frame_ms", "strips_wait_ms", "warm_wait_ms"]:
		assert_bool(r.has(k)).override_failure_message(k).is_true()
	assert_int(int(r["tap_to_open_ms"])).is_greater_equal(2500)
	assert_int(int(r["slow_frames"])).is_equal(1)
	assert_int(int(r["build_ms"])).is_equal(300)
	# the curtain's report goes into the run record's header (RunAnalytics.I, its game the run opened on)
	var src := FileAccess.get_file_as_string("res://ui/RunCurtain.gd")
	assert_bool(src.contains("ra.header[\"load\"] = r")).is_true()


func test_the_open_waits_for_a_half_built_run_and_its_warm_up() -> void:
	var c = auto_free((load("res://ui/RunCurtain.gd") as GDScript).new())
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	auto_free(holder)
	c.title = holder
	assert_bool(c._may_open()).is_true()
	var w: Warmup = Warmup.new()
	w.name = "Warmup"
	holder.add_child(w)
	w._warmed = false
	assert_bool(c._may_open()).is_false()
	w._warmed = true
	assert_bool(c._may_open()).is_true()
	# held no longer than WARM_WAIT
	w._warmed = false
	c._warm_wait_from = -1.0
	c._clock = 2.0
	assert_bool(c._may_open()).is_false()
	c._clock = 2.0 + Curtain.WARM_WAIT + 0.01
	assert_bool(c._may_open()).is_true()


func test_without_a_curtain_the_warm_up_and_the_game_build_in_one_go() -> void:
	# a Warmup out of a curtain is never "not warmed" (tools, tests, replays)
	var w: Warmup = auto_free(Warmup.new())
	assert_bool(w.warmed()).is_true()
	var game := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game.contains("if get_tree().get_first_node_in_group(&\"run_curtain\") != null:\n\t\tawait _build_pause()")).is_true()
	assert_bool(game.contains("Run.play_clock = clock0")).is_true()
	var wsrc := FileAccess.get_file_as_string("res://core/systems/Warmup.gd")
	assert_bool(wsrc.contains("if game.get_tree().get_first_node_in_group(CURTAIN_GROUP) != null:\n\t\tw._build_staged(game)")).is_true()
	assert_str(str(Warmup.CURTAIN_GROUP)).is_equal(str(Curtain.GROUP))
