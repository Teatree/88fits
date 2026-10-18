## Pass 87, lane SUI (the stages change, Garry 2026-10-17): the Stages menu (PLAY opens it once stage 1 is beaten; a card
## per stage with its picture, words, time to the boss and the boss; a locked one says what opens it and starts nothing;
## an open one starts its stage), the stage clear with one road and the countdown to Endless (it closes itself at 0), the
## HUD's clock showing the stage's time, the portal's count (ENDLESS IN) and Endless's time (WAVE n, the ENDLESS banner),
## and the Results naming the stage and how it ended.
extends GdUnitTestSuite

const StagesScreenScript := preload("res://ui/StagesScreen.gd")

var _keep_save: Dictionary = {}


func before_test() -> void:
	_keep_save = Save.data.duplicate(true)
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	get_tree().paused = false
	Run.arena = false
	Run.end()
	Save.data = _keep_save


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			var t := n as WText
			s += t.text + " "
			for r in t.runs:
				s += str(r[0]) + " "
	return s


func _beat(row: Array) -> void:
	Save.data["stages_beaten"] = {"red_canyon": row}


## The menu on a phone's canvas: a 1080 x 1920 viewport of its own.
func _menu() -> Control:
	var sub := SubViewport.new()
	sub.size = Vector2i(1080, 1920)
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	auto_free(sub)
	var m: Control = load("res://ui/StagesScreen.tscn").instantiate()
	sub.add_child(m)
	await _frames(3)
	return m


# ---------------------------------------------------------------- the stages of a map

func test_the_map_has_a_stage_entry_per_stage_with_its_boss() -> void:
	var m := Registry.map("red_canyon")
	var list: Array = StagesScreenScript.entries(m)
	assert_int(list.size()).is_greater_equal(3)
	# each stage names its boss, the first the map's first boss
	assert_str(str(list[0].get("boss", ""))).is_equal("tumbleweed_king")
	for e in list:
		assert_bool(Registry.enemy(str(e.get("boss", ""))) != null).override_failure_message("stage %s has no boss" % str(e)).is_true()
		assert_float(float(e.get("length", 0.0))).is_greater(0.0)


func test_a_map_without_a_stage_list_has_its_stages_of_stage_length() -> void:
	var tl := WaveTimeline.new()
	tl.stages = 3
	tl.stage_length = 430.0
	tl.events = [{"t": 430, "type": "boss", "enemy": "tumbleweed_king"}, {"t": 860, "type": "boss", "enemy": "gila_grande"},
		{"t": 1290, "type": "boss", "enemy": "brander"}]
	if "stage_list" in tl:
		tl.set("stage_list", [])
	var md := MapDef.new()
	md.timeline = tl
	var list: Array = StagesScreenScript.entries(md)
	assert_int(list.size()).is_equal(3)
	assert_str(str(list[1]["boss"])).is_equal("gila_grande")
	assert_float(float(list[2]["length"])).is_equal(430.0)


func test_stage_one_is_always_open_and_the_next_opens_when_the_one_before_is_beaten() -> void:
	_beat([false, false, false])
	assert_bool(StagesScreenScript.unlocked("red_canyon", 0)).is_true()
	assert_bool(StagesScreenScript.unlocked("red_canyon", 1)).is_false()
	assert_bool(StagesScreenScript.opens_for("red_canyon")).is_false()
	_beat([true, false, false])
	assert_bool(StagesScreenScript.unlocked("red_canyon", 1)).is_true()
	assert_bool(StagesScreenScript.unlocked("red_canyon", 2)).is_false()
	# Garry: "opens on every Play" once stage 1 is beaten
	assert_bool(StagesScreenScript.opens_for("red_canyon")).is_true()


func test_a_locked_stage_asks_for_the_boss_before_it() -> void:
	var m := Registry.map("red_canyon")
	var list: Array = StagesScreenScript.entries(m)
	# pass 88 (lane STAGEMENU): the boss is named once met (before that "Beat Stage 1": pass88_stagemenu_test)
	Save.mark_seen("enemy", str(list[0]["boss"]))
	var said: String = StagesScreenScript.requirement(m, list, 1)
	var king: EnemyDef = Registry.enemy(str(list[0]["boss"]))
	assert_str(said).starts_with("Beat ")
	assert_str(said.to_lower()).contains(king.display_name.to_lower().trim_prefix("the "))
	assert_str(StagesScreenScript.requirement(m, list, 0)).is_empty()


func test_the_difficulty_colours_run_sage_to_rock() -> void:
	var list := [{}, {}, {}]
	assert_bool(StagesScreenScript.tone(list, 0).is_equal_approx(W.SAGE)).is_true()
	assert_bool(StagesScreenScript.tone(list, 1).is_equal_approx(W.BRASS_DARK)).is_true()
	assert_bool(StagesScreenScript.tone(list, 2).is_equal_approx(W.ROCK)).is_true()
	assert_bool(StagesScreenScript.tone([{}, {"hell": true}, {}], 1).is_equal_approx(W.ROCK)).is_true()
	assert_str(StagesScreenScript.clock_text(430.0)).is_equal("7:10")
	assert_str(StagesScreenScript.clock_text(600.0)).is_equal("10:00")


# ---------------------------------------------------------------- the menu

func test_the_menu_has_a_card_per_stage_and_a_locked_one_starts_nothing() -> void:
	_beat([true, false, false])
	Save.data["last_character"] = "drifter"
	Save.data["last_map"] = "red_canyon"
	var m := await _menu()
	var cards: Array = m.call("cards")
	var n: int = StagesScreenScript.entries(Registry.map("red_canyon")).size()
	assert_int(cards.size()).is_equal(n)
	m.set("hold_start", true)
	for c: WTap in cards:
		var i := int(c.get_meta("stage"))
		var open := i <= 1
		assert_bool(bool(c.get_meta("open"))).override_failure_message("stage %d" % (i + 1)).is_equal(open)
		assert_bool(c.locked).is_equal(not open)
		m.set("started", -1)
		c.pressed.emit()
		assert_int(int(m.get("started"))).override_failure_message("stage %d" % (i + 1)).is_equal(i if open else -1)
		if not open:
			var req: Node = c.find_child("Requirement", true, false)
			assert_object(req).is_not_null()
			assert_str(_texts(req)).contains("Beat ")
			assert_object(c.find_child("Padlock", true, false)).is_not_null()
	# stage 1 beaten wears its stamp, stage 2 not yet
	assert_object((cards[0] as Node).find_child("Beaten", true, false)).is_not_null()
	assert_object((cards[1] as Node).find_child("Beaten", true, false)).is_null()
	# the chosen hero's badge in the header
	assert_object(m.get("header").find_child("Hero", true, false)).is_not_null()


func test_each_card_shows_its_name_length_and_boss() -> void:
	_beat([true, true, false])
	var list: Array = StagesScreenScript.entries(Registry.map("red_canyon"))
	# pass 88 (lane STAGEMENU): a boss is named once met (hidden before: pass88_stagemenu_test)
	for e: Dictionary in list:
		Save.mark_seen("enemy", str(e["boss"]))
	var m := await _menu()
	for c: WTap in m.call("cards"):
		var i := int(c.get_meta("stage"))
		var e: Dictionary = list[i]
		var said := _texts(c)
		assert_str(said).contains("STAGE %d" % (i + 1))
		assert_str(said).contains(str(e.get("name", "")))
		assert_str(said).contains(StagesScreenScript.clock_text(float(e["length"])))
		assert_str(said).contains(Registry.enemy(str(e["boss"])).display_name)
		if bool(c.get_meta("open")) and str(e.get("difficulty", "")) != "":
			assert_str(said).contains(str(e["difficulty"]))


# ---------------------------------------------------------------- the stage clear

func test_the_stage_clear_has_one_road_and_counts_down_to_endless() -> void:
	var pd: PortalDialog = auto_free(PortalDialog.new())
	add_child(pd)
	var left := [59.2]
	pd.seconds_source = func() -> float: return left[0]
	var said: Array = []
	var gone: Array = []
	pd.decided.connect(func(x): said.append(x))
	pd.expired.connect(func(): gone.append(true))
	pd.open(1, true, false)
	await _frames(2)
	var t := _texts(pd)
	assert_str(t).contains("STAGE 1 CLEAR")
	assert_str(t).contains("Extract")
	assert_str(t).not_contains("Continue")
	assert_str(t).not_contains("Stay")
	assert_str(t).contains("Endless")
	assert_str((pd.get("_count") as WText).text).is_equal("01:00")
	assert_bool((pd.get("_count") as WText).color.is_equal_approx(W.BRASS)).is_true()
	# its last seconds in rock
	left[0] = 7.4
	await _frames(2)
	assert_str((pd.get("_count") as WText).text).is_equal("00:08")
	assert_bool((pd.get("_count") as WText).color.is_equal_approx(W.ROCK)).is_true()
	# NOT YET still last under the cards
	var nb: WButton = pd.find_child("NotYet", true, false)
	assert_int(nb.get_index()).is_equal((pd.get("_cards") as Node).get_child_count() - 1)
	# at 0 it closes by itself, no decision
	left[0] = 0.0
	await _frames(2)
	assert_bool(pd.visible).is_false()
	assert_int(gone.size()).is_equal(1)
	assert_int(said.size()).is_equal(0)
	# EXTRACT is the one choice
	left[0] = 30.0
	pd.open(1, true, false)
	await _frames(1)
	(pd.find_child("Extract", true, false) as WTap).pressed.emit()
	assert_array(said).is_equal([true])
	assert_bool(pd.visible).is_false()


# ---------------------------------------------------------------- the HUD's clock

func test_the_clock_shows_the_portal_count_then_endless() -> void:
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	await _frames(2)
	hud.test_stage_clock = {"stage_seconds": 125.0, "endless": false}
	hud.tick(0.0)
	assert_str(hud.clock_mode()).is_equal("")
	assert_str((hud.get("_timer") as WText).text).is_equal("02:05")
	assert_str(hud.stage_tag_text()).is_empty()
	hud.test_stage_clock = {"portal_left": 41.3, "endless": false}
	hud.tick(0.0)
	assert_str(hud.clock_mode()).is_equal("portal")
	assert_str((hud.get("_timer") as WText).text).is_equal("00:42")
	assert_str(hud.stage_tag_text()).is_equal("ENDLESS IN")
	hud.test_stage_clock = {"endless": true, "endless_wave": 3, "endless_seconds": 31.0}
	hud.tick(0.0)
	assert_str(hud.clock_mode()).is_equal("endless")
	assert_str((hud.get("_timer") as WText).text).is_equal("00:31")
	assert_str(hud.stage_tag_text()).is_equal("WAVE 3")
	assert_str(hud.banner_text()).is_equal("ENDLESS")
	# the tag hangs under the clock plate, centred, clear of the slots' sides
	var tag: Control = hud.get("_stage_tag")
	var plate: Control = hud.get("_timer_plate")
	assert_float(absf(tag.position.x + tag.size.x * 0.5 - (plate.position.x + plate.size.x * 0.5))).is_less(1.5)
	assert_float(tag.size.x).is_less(220.0)
	hud.test_stage_clock = {}
	hud.tick(0.0)
	assert_str(hud.clock_mode()).is_equal("")
	# a stage-2 run's clock starts at the stage's own 00:00, whatever the map's run clock reads (lane SGAME's stage_clock)
	Run.start_stage(1)
	hud.tick(0.0)
	assert_str((hud.get("_timer") as WText).text).is_equal("00:00")
	Run.elapsed += 65.0
	hud.tick(0.0)
	assert_str((hud.get("_timer") as WText).text).is_equal("01:05")


# ---------------------------------------------------------------- the Results

func test_the_results_name_the_stage_and_how_it_ended() -> void:
	Run.start_stage(0)
	Run.extracted = true
	var s: Dictionary = ResultsScreen_story()
	assert_str(str(s["star"])).is_equal("Extracted")
	assert_str(str(s["stage"])).starts_with("Stage 1")
	assert_str(str(s["stage"])).contains("Beaten")
	assert_str(str(s["endless"])).is_empty()
	Run.extracted = false
	Run.stage_beaten = true
	Run.endless = true
	Run.endless_time = 84.0
	Run.died = true
	s = ResultsScreen_story()
	assert_str(str(s["star"])).is_equal("Fell in Endless")
	assert_str(str(s["endless"])).starts_with("Endless 01:24")
	Run.endless = false
	Run.stage_beaten = false
	s = ResultsScreen_story()
	assert_str(str(s["star"])).is_equal("Run over")
	assert_str(str(s["stage"])).not_contains("Beaten")


func ResultsScreen_story() -> Dictionary:
	return load("res://ui/ResultsScreen.gd").stage_story()
