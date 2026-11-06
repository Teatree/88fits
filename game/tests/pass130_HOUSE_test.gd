## Pass 130, lane HOUSE (Garry: "whenever we do show the level of trail, we also show the stats increases as just a
## bundle (a list of comma-separated increases) ... in one build, the trail is giving one set of stat increases and in
## the other build it's giving a different set. It's important to know which is which."): the bundle, one line that
## says what a Trail gives, on the fixture tests/fixtures/trail_bundle.json (never the game's own nodes). The same file
## pins the line's two other writers, tools/level_editor/trail_bundle.js and tools/trail_bundle.py
## (tools/level_editor/selftest_HOUSE130.py), so the game, the pages and the Python tools write one wording.
##  - Trail.bundle_text on blocks: empty, percent, count, seconds, flat, word, a loss, a sum of 0, the unlocks, a block
##    with its own `types` (its own words and order), an older block without (this build's types, the file's order)
##  - Trail.tally and bundle_of on node ids; Trail.record()'s `unlocks` and its upgrades in the file's order
##  - tools/trail_arg.gd: the Trail a trail= argument names (level_of, ids_upto, bundle_of) and what apply() hands back
##  - the run record's block carries `bundle` (RunAnalytics.trail_block), the index row `trail_bundle`, run_start
##    `trail_bundle` and `build_id`, a replay's header its `trail`
##  - the replay viewer's pop-up words (ReplayViewer.trail_text) and that the Trail is a button and a pop-up there
##  - the Watch, the sim and the probe name the bundle where they name the level
extends GdUnitTestSuite

const FIXTURE := "res://tests/fixtures/trail_bundle.json"
const TRAIL_ARG := preload("res://tools/trail_arg.gd")

var _fx: Dictionary = {}


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	_fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	Trail.load_data((_fx["trail"] as Dictionary).duplicate(true))


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()


func _hold(ids: Array, spent: int = 0) -> void:
	Save.data["trail"] = {"bought": ids.duplicate(), "spent": spent, "had": []}
	Trail.refresh()


# ---------------------------------------------------------------- the line

func test_the_bundle_reads_every_fixture_block() -> void:
	assert_int((_fx["cases"] as Array).size()).is_greater(15)
	for c: Dictionary in _fx["cases"]:
		assert_str(Trail.bundle_text(c["block"])).override_failure_message("%s: got '%s', want '%s'" % [c["name"], Trail.bundle_text(c["block"]), c["want"]]).is_equal(str(c["want"]))


func test_the_bundle_in_words() -> void:
	var types := {"might": {"name": "Might", "kind": "percent", "text": "Attack damage"}, "hp": {"name": "Grit", "kind": "flat", "text": "Max HP"},
		"reroll": {"name": "Reroll", "kind": "count", "text": "Rerolls"}, "fuse": {"name": "Long Fuse", "kind": "seconds", "text": "Fuse"},
		"spirit": {"name": "Spirit Guide", "kind": "word", "text": "Totem gifts stronger"}}
	assert_str(Trail.bundle_text({})).is_equal("nothing yet")
	assert_str(Trail.bundle_text({"upgrades": {}, "types": {}, "unlocks": {}})).is_equal(Trail.BUNDLE_EMPTY)
	assert_str(Trail.bundle_text({"upgrades": {"might": 0.12, "hp": 30, "reroll": 2}, "types": types})).is_equal("Attack damage +12%, Max HP +30, Rerolls +2")
	assert_str(Trail.bundle_text({"upgrades": {"fuse": 1.5}, "types": types})).is_equal("Fuse +1.5 s")
	# a word-kind type reads by its name, never an amount
	assert_str(Trail.bundle_text({"upgrades": {"spirit": 1}, "types": types})).is_equal("Spirit Guide")
	assert_str(Trail.bundle_text({"upgrades": {"might": 0.12}, "types": types, "unlocks": {"outlaw": 2, "weapon": 1, "passive": 2, "stage": 1}})) \
		.is_equal("Attack damage +12% · unlocks: 2 outlaws, 3 items, 1 stage")
	# an older block has no `types`: this build's upgrade types, in the file's order
	assert_str(Trail.bundle_text({"upgrades": {"reroll": 2, "might": 0.12}})).is_equal("Attack damage +12%, Rerolls +2")
	# never the word the players do not read
	for c: Dictionary in _fx["cases"]:
		assert_bool(str(c["want"]).to_lower().contains("hero")).is_false()


func test_a_tally_adds_up_the_nodes() -> void:
	for c: Dictionary in _fx["tallies"]:
		var t := Trail.tally(c["ids"])
		assert_array((t["upgrades"] as Dictionary).keys()).override_failure_message(str(c["name"])).is_equal((c["upgrades"] as Dictionary).keys())
		for k: String in (c["upgrades"] as Dictionary).keys():
			assert_float(float(t["upgrades"][k])).is_equal_approx(float(c["upgrades"][k]), 0.00001)
		assert_array((t["unlocks"] as Dictionary).keys()).override_failure_message(str(c["name"])).is_equal((c["unlocks"] as Dictionary).keys())
		for k: String in (c["unlocks"] as Dictionary).keys():
			assert_int(int(t["unlocks"][k])).is_equal(int(c["unlocks"][k]))
		assert_str(Trail.bundle_of(c["ids"])).override_failure_message(str(c["name"])).is_equal(str(c["want"]))


func test_the_record_counts_the_unlocks_and_orders_the_upgrades() -> void:
	# bought out of the file's order: the reroll first, then might, an outlaw and an item
	_hold(["h1", "a1", "c1", "d2"], 500)
	var r := Trail.record()
	assert_array((r["upgrades"] as Dictionary).keys()).is_equal(["might", "reroll"])
	assert_dict(r["unlocks"]).is_equal({"outlaw": 1, "passive": 1})
	assert_str(Trail.bundle()).is_equal("Attack damage +5%, Rerolls +1 · unlocks: 1 outlaw, 1 item")
	assert_str(Trail.bundle()).is_equal(Trail.bundle_text(r))


# ---------------------------------------------------------------- a tool's trail= argument

func test_a_trail_argument_names_its_bundle() -> void:
	var levels := Trail.levels()
	assert_int(levels).is_equal(8)
	for c: Dictionary in _fx["args"]:
		var lv := TRAIL_ARG.level_of(str(c["arg"]), levels)
		assert_int(lv).override_failure_message(str(c)).is_equal(int(c["level"]))
		if lv >= 0:
			assert_array(TRAIL_ARG.ids_upto(lv, bool(c["optional"]))).override_failure_message(str(c)).is_equal(c["ids"])
		assert_str(TRAIL_ARG.bundle_of(str(c["arg"]), bool(c["optional"]))).override_failure_message(str(c)).is_equal(str(c["want"]))
	# exactly these nodes (trail_ids=) win over the argument
	assert_str(TRAIL_ARG.bundle_of("full", false, ["a2", "c1"])).is_equal("Max HP +30 · unlocks: 1 outlaw")
	# nothing in the save changed for the asking
	assert_bool(Save.data.get("trail") is Dictionary and not ((Save.data["trail"] as Dictionary).get("bought", []) as Array).is_empty()).is_false()


func test_apply_hands_back_the_bundle() -> void:
	var info := TRAIL_ARG.apply(Save, "half")
	assert_int(int(info["level"])).is_equal(4)
	assert_str(str(info["bundle"])).is_equal("Attack damage +12%, Max HP +30 · unlocks: 1 outlaw, 1 item")
	assert_str(TRAIL_ARG.line_of(info)).is_equal("half (Trail Level 4 of 8): Attack damage +12%, Max HP +30 · unlocks: 1 outlaw, 1 item")
	info = TRAIL_ARG.apply(Save, "none")
	assert_str(str(info["bundle"])).is_equal("nothing yet")
	assert_str(TRAIL_ARG.line_of(info)).is_equal("none: nothing yet")


# ---------------------------------------------------------------- the record

func test_the_run_record_carries_the_bundle() -> void:
	_hold(["a1", "a2", "b1", "c1"], 120)
	var blk := RunAnalytics.trail_block()
	assert_str(str(blk["bundle"])).is_equal("Attack damage +12%, Max HP +30 · unlocks: 1 outlaw")
	assert_dict(blk["unlocks"]).is_equal({"outlaw": 1})
	assert_str(str(blk["types"]["hp"]["text"])).is_equal("Max HP")
	# a reader without the key works it out from the block's own upgrades and types
	var older := blk.duplicate(true)
	older.erase("bundle")
	older.erase("unlocks")
	assert_str(Trail.bundle_text(older)).is_equal("Attack damage +12%, Max HP +30")
	# the record says what ITS build's Trail gave: another build's file does not change the line a record carries
	Trail.load_from()
	assert_str(Trail.bundle_text(blk)).is_equal("Attack damage +12%, Max HP +30 · unlocks: 1 outlaw")
	var src := FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd")
	assert_str(src).contains("out[\"bundle\"] = Trail.bundle_text(out)")
	assert_str(src).contains("row[\"trail_bundle\"]")
	assert_int(RunAnalytics.SCHEMA).is_equal(6)


func test_run_start_and_the_replay_carry_the_bundle() -> void:
	var an := FileAccess.get_file_as_string("res://core/autoload/Analytics.gd")
	assert_str(an).contains("\"trail_bundle\": Trail.bundle_text(trl)")
	assert_str(an).contains("\"build_id\": str(RunReplay.build_info().get(\"id\", \"\"))")
	var rr := FileAccess.get_file_as_string("res://core/systems/RunReplay.gd")
	assert_str(rr).contains("\"trail\": RunAnalytics.trail_block(),")


# ---------------------------------------------------------------- the replay viewer's pop-up

func test_the_replay_pop_up_says_the_level_the_bundle_and_each_type() -> void:
	var viewer: Script = load("res://replay/ReplayViewer.gd")
	var blk := {"level": 3, "levels": 70, "nodes": 100, "bought": ["a", "b", "c"], "spent": 1234,
		"upgrades": {"might": 0.06, "spirit": 1}, "unlocks": {"outlaw": 1},
		"types": {"might": {"name": "Might", "kind": "percent", "text": "Attack damage"}, "spirit": {"name": "Spirit Guide", "kind": "word", "text": "Totem gifts"}}}
	var words: String = viewer.trail_text(blk, true)
	assert_str(words).contains("level 3 of 70 · 3 of 100 nodes · 1,234 gold spent")
	assert_str(words).contains("[b]Gave:[/b] Attack damage +6%, Spirit Guide · unlocks: 1 outlaw")
	# one row per upgrade type: its name, its sum as its kind writes it, what it adds to
	assert_str(words).contains("[cell][b]Might[/b]    [/cell][cell]+6%    [/cell]")
	assert_str(words).contains("[cell][b]Spirit Guide[/b]    [/cell][cell]bought    [/cell]")
	assert_str(words).contains("B, Esc or a click closes this.")
	# the line the recording's build wrote wins over one worked out here
	var own := blk.duplicate(true)
	own["bundle"] = "Damage +6% (the other build's words)"
	assert_str(viewer.trail_text(own, true)).contains("[b]Gave:[/b] Damage +6% (the other build's words)")
	# a note (this build's Trail would give something else) is said in the pop-up
	assert_str(viewer.trail_text(own, true, "This build's Trail file would give those nodes something else: X")).contains("something else: X")
	# the button's hover hint: the level and the bundle, no markup
	var hint: String = viewer.trail_text(blk, false)
	assert_str(hint).is_equal("The Trail the run began with: level 3 of 70 · 3 of 100 nodes · 1,234 gold spent\nIt gave: Attack damage +6%, Spirit Guide · unlocks: 1 outlaw")
	var src := FileAccess.get_file_as_string("res://replay/ReplayViewer.gd")
	# a button and a pop-up over the view, closed from the start; B opens, B, Esc and a click close; the log has its room back
	assert_str(src).contains("board_btn.text = \"The Trail\"")
	assert_str(src).contains("var _board_open := false")
	assert_str(src).contains("board_shade.gui_input.connect(")
	assert_str(src).contains("if _board_open:\n\t\t\t\ttoggle_board()\n\t\t\telse:\n\t\t\t\tget_tree().quit(0)")
	assert_str(src).contains("log_box.custom_minimum_size = Vector2(PANEL_W - 20, 220)")
	assert_bool(src.contains("panel.add_child(board_label)")).is_false()


# ---------------------------------------------------------------- the tools name it

func test_every_tool_that_names_the_level_names_the_bundle() -> void:
	var watch := FileAccess.get_file_as_string("res://tools/watch/Watch.gd")
	assert_str(watch).contains("func trail_bundle() -> String:")
	assert_str(watch).contains("print(\"watch: the Trail gives: %s\" % trail_bundle())")
	assert_str(watch).contains("\"trail_bundle\": trail_bundle()")
	assert_str(FileAccess.get_file_as_string("res://tools/watch/WatchPanel.gd")).contains("\"the Trail gives: %s\" % str(w.trail_bundle())")
	assert_str(FileAccess.get_file_as_string("res://tools/watch/WatchSetup.gd")).contains("_bundle.text = \"Gives: \" + bundle_words()")
	assert_str(FileAccess.get_file_as_string("res://tools/sim_run.gd")).contains("\"trail_bundle\": str(_trail_info.get(\"bundle\", \"\"))")
	assert_str(FileAccess.get_file_as_string("res://tools/difficulty_probe.gd")).contains("print(\"probe: the Trail gives: %s\"")
