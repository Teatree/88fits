extends GdUnitTestSuite

## Pass 87, lane STOOLS (Garry: "These changes should be reflected in both the Watch tool, the analytics (posthog too) and
## the LevelEditor ... Analytics should make it easy to indicate which Stage Player was playing on and which Stage the
## data is about"): the run record names its stage and how the stage run ended (RunAnalytics.stage_header /
## stage_end_fields, the row's `en`, the stage_beaten and endless events), every PostHog event of a run carries its stage
## (Analytics.stage_props: stage_id, in_endless, endless_wave), the portal's choice is EXTRACT or "not yet", the Watch
## starts the stage chosen in its Hero Settings (only the save's unlocked ones in the save's mode), and the run sim plays
## the stage it is given (sim_run.gd stage=, its meta).

const WATCH := preload("res://tools/watch/Watch.gd")
const SETUP := preload("res://tools/watch/WatchSetup.gd")
const BOT := preload("res://tools/bot/Bot.gd")

var _save_keep: Dictionary = {}


func before_test() -> void:
	_save_keep = Save.data.duplicate(true)
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	Run.elapsed = 0.0
	Run.stage = 0
	Run.endless = false
	Run.endless_time = 0.0
	Run.stage_beaten = false
	Run.stage_next = 0
	Run.extracted = false
	Save.data = _save_keep


func _tl() -> WaveTimeline:
	return Registry.map("red_canyon").timeline


# ---------------------------------------------------------------- the run record

func test_the_record_names_the_stage_it_played() -> void:
	var tl := _tl()
	Run.start_stage(1)
	var h := RunAnalytics.stage_header()
	assert_int(int(h["stage"])).is_equal(2)
	assert_int(int(h["stage_index"])).is_equal(1)
	assert_str(str(h["stage_id"])).is_equal(tl.stage_id(1))
	assert_str(str(h["stage_name"])).is_equal(tl.stage_name(1))
	assert_float(float(h["stage_start"])).is_equal_approx(tl.stage_start(1), 0.05)
	assert_float(float(h["stage_length"])).is_equal_approx(tl.stage_len(1), 0.05)
	assert_int(int(h["stage_count"])).is_equal(tl.stage_count())
	# stage 1 of the map, and the map's last stage
	Run.start_stage(0)
	assert_str(str(RunAnalytics.stage_header()["stage_id"])).is_equal(tl.stage_id(0))
	Run.start_stage(tl.stage_count() - 1)
	assert_int(int(RunAnalytics.stage_header()["stage"])).is_equal(tl.stage_count())


func test_the_record_says_how_the_stage_run_ended() -> void:
	var ra := RunAnalytics.new()
	Run.start_stage(1)
	ra.header = {"result": "death"}
	Run.elapsed += 120.0
	Run.held_time += 30.0
	var f := ra.stage_end_fields()
	assert_str(str(f["outcome"])).is_equal("died")
	assert_bool(bool(f["boss_killed"])).is_false()
	assert_float(float(f["stage_clock"])).is_equal_approx(120.0, 0.05)
	assert_float(float(f["run_time"])).is_equal_approx(150.0, 0.05)
	assert_float(float(f["endless_s"])).is_equal(0.0)
	# the boss down, then Endless for 47 s
	Run.stage_beaten = true
	assert_str(str(ra.stage_end_fields()["outcome"])).is_equal("died_after_boss")
	Run.endless = true
	Run.endless_time = 47.25
	f = ra.stage_end_fields()
	assert_str(str(f["outcome"])).is_equal("died_endless")
	assert_bool(bool(f["boss_killed"])).is_true()
	assert_float(float(f["endless_s"])).is_equal_approx(47.3, 0.06)
	# out through the portal; a run left from the pause menu is a quit
	Run.endless = false
	Run.extracted = true
	assert_str(str(ra.stage_end_fields()["outcome"])).is_equal("extracted")
	Run.extracted = false
	ra.header = {"result": "abandon"}
	assert_str(str(ra.stage_end_fields()["outcome"])).is_equal("quit")
	# run_end carries them
	for k in ["stage_id", "outcome", "boss_killed", "stage_clock", "endless_s", "run_time"]:
		assert_bool(RunAnalytics.STAGE_END_PROPS.has(k)).is_true()
	ra.free()


# ---------------------------------------------------------------- PostHog

func test_every_event_of_a_run_names_its_stage() -> void:
	var tl := _tl()
	Run.start_stage(2)
	var p := Analytics.stage_props()
	assert_str(str(p["stage_id"])).is_equal(tl.stage_id(2))
	assert_bool(bool(p["in_endless"])).is_false()
	assert_int(int(p["endless_wave"])).is_equal(0)
	Run.endless = true
	Run.endless_time = 25.0
	p = Analytics.stage_props()
	assert_bool(bool(p["in_endless"])).is_true()
	assert_int(int(p["endless_wave"])).is_equal(Run.endless_wave())
	assert_int(int(p["endless_wave"])).is_greater(0)
	# the new events and their names
	assert_str(str(Analytics.KIND_EVENTS.get("stage_beaten", ""))).is_equal("stage_beaten")
	assert_str(str(Analytics.KIND_EVENTS.get("endless", ""))).is_equal("endless_started")
	var m: Array = Analytics.map_event({"kind": "stage_beaten", "level": 3, "stage_clock": 780.0})
	assert_str(str(m[0])).is_equal("stage_beaten")
	assert_int(int(m[1]["stage"])).is_equal(3)
	assert_bool(m[1].has("level")).is_false()
	m = Analytics.map_event({"kind": "endless", "level": 2})
	assert_str(str(m[0])).is_equal("endless_started")
	assert_int(int(m[1]["stage"])).is_equal(2)
	# the portal: EXTRACT, or "not yet" (no going on to the next stage)
	assert_str(str(Analytics.map_event({"kind": "portal", "level": 1, "extract": true})[1]["choice"])).is_equal("extract")
	assert_str(str(Analytics.map_event({"kind": "portal", "level": 1, "extract": false})[1]["choice"])).is_equal("not_yet")


# ---------------------------------------------------------------- the Watch

func test_the_watch_starts_the_stage_chosen() -> void:
	var s := SETUP.defaults_from_args({"stage": "3"})
	assert_int(int(s["stage"])).is_equal(3)
	assert_int(int(SETUP.defaults_from_args({})["stage"])).is_equal(1)
	assert_int(int(SETUP.defaults_from_args({"stage": "-2"})["stage"])).is_equal(1)
	var l := WATCH.launch_of("drifter", "red_canyon", 7, true, 2)
	assert_int(int(l["stage"])).is_equal(2)
	assert_int(int(WATCH.launch_of("drifter", "red_canyon", 7, false)["stage"])).is_equal(1)


func test_the_watch_offers_the_save_s_stages_or_every_stage() -> void:
	# tool mode: every stage; the save's mode: stage 1 and each one whose stage before is beaten
	assert_bool(SETUP.stage_open([], 2, true)).is_true()
	assert_bool(SETUP.stage_open([], 0, false)).is_true()
	assert_bool(SETUP.stage_open([], 1, false)).is_false()
	assert_bool(SETUP.stage_open([true], 1, false)).is_true()
	assert_bool(SETUP.stage_open([true], 2, false)).is_false()
	assert_bool(SETUP.stage_open([true, true], 2, false)).is_true()
	# the sandbox's stages beaten for the run
	var mdef: MapDef = Registry.map("red_canyon")
	var all: Dictionary = WATCH.stages_beaten_for("all", "red_canyon", mdef, {})
	assert_int((all["red_canyon"] as Array).size()).is_equal(mdef.timeline.stage_count())
	assert_bool((all["red_canyon"] as Array).all(func(b) -> bool: return bool(b))).is_true()
	var mine: Dictionary = WATCH.stages_beaten_for("save", "red_canyon", mdef, {"save_stages": {"red_canyon": [true, false]}})
	assert_array(mine["red_canyon"]).is_equal([true, false])
	assert_dict(WATCH.stages_beaten_for("save", "red_canyon", mdef, {})).is_empty()


func test_the_watch_s_grey_line_is_a_sim_of_the_same_stage() -> void:
	var refs := [{"hero": "drifter", "map": "red_canyon", "talents": "none", "path": "s2/result.json", "label": "s2", "stage": 2},
		{"hero": "drifter", "map": "red_canyon", "talents": "none", "path": "old/result.json", "label": "old"}]
	assert_str(str(SETUP.ref_for(refs, "drifter", "red_canyon", {}, 2).get("label", ""))).is_equal("s2")
	# a whole-run Sim from before pass 87 only for stage 1 (its start is stage 1); none for stage 3
	assert_str(str(SETUP.ref_for(refs, "drifter", "red_canyon", {}, 1).get("label", ""))).is_equal("old")
	assert_dict(SETUP.ref_for(refs, "drifter", "red_canyon", {}, 3)).is_empty()


# ---------------------------------------------------------------- the run sim

func test_the_bot_plays_on_into_endless_unless_told_to_extract() -> void:
	assert_str(str(BOT.resolve_opts({})["portal"])).is_equal("endless")
	assert_str(str(BOT.resolve_opts({"preset": "sim77"})["portal"])).is_equal("endless")
	assert_str(str(BOT.resolve_opts({"portal": "extract"})["portal"])).is_equal("extract")
	assert_str(str(BOT.resolve_opts({"portal": "go_on"})["portal"])).is_equal("endless")
	for p in BOT.PRESETS:
		assert_str(str((BOT.PRESETS[p] as Dictionary)["portal"])).is_equal("endless")


func test_the_run_sim_plays_the_stage_it_is_given() -> void:
	var f := FileAccess.open("res://tools/sim_run.gd", FileAccess.READ)
	var src := f.get_as_text()
	# the argument, the launch (Game._start_chosen_stage reads `stage`) and the player file's meta
	assert_bool(src.contains("\"stage\": _stage = maxi(int(v), 1)")).is_true()
	assert_bool(src.contains("\"stage\": _stage}")).is_true()
	assert_bool(src.contains("\"stage\": _stage, \"outcome\": _stage_outcome(reason),")).is_true()
	assert_bool(src.contains("func _stage_outcome(reason: String) -> String:")).is_true()
	assert_bool(src.contains("\"boss_killed\":")).is_true()
	assert_bool(src.contains("\"endless_s\":")).is_true()
