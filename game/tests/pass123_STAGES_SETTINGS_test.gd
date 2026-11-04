## Pass 123, lane STAGES_SETTINGS: the Stages menu and Settings under the Royale theme (Garry, 2026-11-03: "this isnt the
## full Royale UI ... Let's continue with this up until it's matching all the choices that I made for the UI"; his build
## brief: "Stages as the mock: slate cards, a gold START on each open card, the locked card saying what opens it; times
## and bosses from data", "Move the run-history line ... to the Stages screen's header", "Settings in slate panels as the
## mock; one shared confirm pop-up (safe answer slate, destructive red, buying green)").
##  - Stages: the label and the run line under the header, a 990 px slate card a stage (its 200 px painting band, the
##    name and its STAGE tag, the difficulty tag by today's tone and word, the description, the time pill, the boss frame
##    and his name or today's "Boss not encountered yet", a gold START on each open card), the locked band and what
##    opens it, BEATEN; START and the card start the stage once each tap, a locked card starts nothing;
##  - Settings: the panels in today's order as slate panels, the choices in capitals, the 74 px rows and 96 px sliders,
##    RESET, the play data's line, the red WIPE asking through the danger confirm, the Debug panel above the wipe, the
##    one foot line and its 2 s hold, the theme row;
##  - Wanted unchanged on both screens (no new node, today's board).
extends GdUnitTestSuite

const StagesScript := preload("res://ui/StagesScreen.gd")
const SettingsScript := preload("res://ui/SettingsScreen.gd")

var _keep_save: Dictionary = {}
var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_settings_before)
	# the suites after this one are built under Wanted, the default (a test save left at royale must not carry over)


func before_test() -> void:
	_keep_save = Save.data.duplicate(true)
	Save.data = Save._default()
	Save.data["last_character"] = "drifter"
	Save.data["last_map"] = "red_canyon"


func after_test() -> void:
	Save.data = _keep_save
	if Save.sandboxed():
		Save.end_sandbox()


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


## A screen in a phone-sized SubViewport (its rects in canvas px), laid out.
func _screen(path: String) -> Control:
	var sub := SubViewport.new()
	sub.size = Vector2i(1080, 1920)
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	auto_free(sub)
	var m: Control = load(path).instantiate()
	sub.add_child(m)
	await _frames(4)
	# the board's slide in (0.25 s) and the cards' pop (UiFx.stagger) over
	await get_tree().create_timer(0.6).timeout
	return m


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			var t := n as WText
			s += t.text + " "
			for r in t.runs:
				s += str(r[0]) + " "
	return s


func _finger(c: Control, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = c.size * 0.5
	c._gui_input(e)


func _list() -> Array:
	return StagesScript.entries(Registry.map("red_canyon"))


# ---------------------------------------------------------------- Stages

func test_the_royale_stages_are_slate_cards_990_wide_with_a_painting_band() -> void:
	Save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	var m := await _screen("res://ui/StagesScreen.tscn")
	var cards: Array = m.call("cards")
	assert_int(cards.size()).is_equal(_list().size())
	assert_float(m.board_side()).is_equal(StagesScript.R_SIDE)
	assert_float(m.board_top()).is_equal(StagesScript.R_TOP)
	for c: WTap in cards:
		assert_float(c.size.x).is_equal_approx(990.0, 0.5)
		assert_str(c.box.royale_kind()).is_equal("panel")
		assert_int(c.box.border).is_equal(R.PANEL_EDGE)
		assert_int(c.box.shadow).is_equal(R.PANEL_BASE)
		# never the grey locked face (a locked card keeps the slate; its band says it)
		assert_bool(c.locked).is_false()
		var band: Control = c.find_child("Picture", true, false)
		assert_float(band.size.y).is_equal(StagesScript.R_BAND_H)
		assert_float(band.size.x).is_equal_approx(990.0 - 2.0 * R.PANEL_EDGE, 0.5)
		var nm: WText = c.find_child("Name", true, false)
		assert_bool(R.is_display(nm.font)).is_true()
		assert_int(nm.font_size).is_equal(StagesScript.R_NAME_PX)
		assert_bool(nm.color.is_equal_approx(R.CREAM)).is_true()
		assert_str(nm.text).is_equal(nm.text.to_upper())
		var tg: Control = c.find_child("Tag", true, false)
		assert_str(str(tg.get_meta("role"))).is_equal("gold")
		assert_str((tg.find_child("Word", true, false) as WText).text).is_equal("STAGE %d" % (int(c.get_meta("stage")) + 1))
	# the cards' order and gap (the mock's 30)
	assert_float((cards[1] as Control).position.y - (cards[0] as Control).position.y - (cards[0] as Control).size.y).is_equal_approx(float(StagesScript.R_GAP), 0.5)




func test_the_facts_row_has_the_time_pill_the_boss_and_start_on_open_cards() -> void:
	Save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	var list := _list()
	Save.mark_seen("enemy", str(list[0]["boss"]))
	var m := await _screen("res://ui/StagesScreen.tscn")
	var cards: Array = m.call("cards")
	for c: WTap in cards:
		var i := int(c.get_meta("stage"))
		var e: Dictionary = list[i]
		var pill: Control = c.find_child("Length", true, false)
		assert_object(pill).is_not_null()
		assert_str(str(pill.get_meta("text"))).is_equal(StagesScript.clock_text(float(e["length"])))
		assert_object(pill.find_child("Glyph_clock", true, false)).is_not_null()
		assert_str(_texts(pill)).contains(" to the boss")
		var plate: WPlate = c.find_child("BossPlate", true, false)
		assert_float(plate.side).is_equal(StagesScript.R_BOSS_PX)
		var open := bool(c.get_meta("open"))
		var sb: WButton = c.find_child("Start", true, false)
		if open:
			assert_object(sb).override_failure_message("stage %d has no START" % (i + 1)).is_not_null()
			assert_str(sb.role).is_equal(WButton.GOLD)
			assert_str(sb.label_text()).is_equal("START")
			assert_vector(sb.size).is_equal_approx(StagesScript.R_START, Vector2(0.5, 0.5))
			# START takes its own touch: the card under it never starts the stage a second time
			assert_int(sb.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
			# on the card's right, inside it
			var cr := c.get_global_rect()
			var br := sb.get_global_rect()
			assert_bool(cr.encloses(br)).is_true()
			assert_float(cr.end.x - br.end.x).is_less(40.0)
		else:
			assert_object(sb).is_null()
	# the King met: his name in gold; the Gila not met: today's words, italic, and his frame a silhouette
	var b0: WText = (cards[0] as Node).find_child("Boss", true, false)
	var king: EnemyDef = Registry.enemy(str(list[0]["boss"]))
	assert_str(b0.text).is_equal(king.display_name)
	assert_bool(b0.color.is_equal_approx(R.GOLD_TEXT)).is_true()
	var b1: WText = (cards[1] as Node).find_child("Boss", true, false)
	assert_str(b1.text).is_equal(StagesScript.BOSS_UNMET)
	assert_bool(b1.color.is_equal_approx(R.SECONDARY)).is_true()
	assert_bool(((cards[1] as Node).find_child("BossPlate", true, false) as WPlate).locked).is_true()


func test_a_locked_card_says_locked_and_what_opens_it_over_a_grey_band() -> void:
	Save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	var list := _list()
	var mp := Registry.map("red_canyon")
	var m := await _screen("res://ui/StagesScreen.tscn")
	var cards: Array = m.call("cards")
	var locked: WTap = cards[2]
	assert_bool(bool(locked.get_meta("open"))).is_false()
	var lw: WText = locked.find_child("Locked", true, false)
	assert_str(lw.text).is_equal("LOCKED")
	assert_bool(R.is_display(lw.font)).is_true()
	var req: WText = locked.find_child("Requirement", true, false)
	assert_str(req.text).is_equal(StagesScript.requirement(mp, list, 2) + " to open it")
	assert_str(req.text).is_equal("Beat Stage 2 to open it")
	var shot: CanvasItem = locked.find_child("Shot", true, false)
	assert_object(shot.material).is_same(StagesScript.lock_material())
	# open cards: no LOCKED, the painting as it is; the beaten one wears BEATEN turned -6 degrees
	assert_object((cards[0] as Node).find_child("Locked", true, false)).is_null()
	assert_object(((cards[0] as Node).find_child("Shot", true, false) as CanvasItem).material).is_null()
	var bt: Control = (cards[0] as Node).find_child("Beaten", true, false)
	assert_object(bt).is_not_null()
	assert_float(rad_to_deg(bt.rotation)).is_equal_approx(StagesScript.R_BEATEN_DEG, 0.01)
	assert_str(str(bt.get_meta("role"))).is_equal("green")
	assert_object((cards[1] as Node).find_child("Beaten", true, false)).is_null()
	# the King met: the requirement names him, as today's rule
	Save.mark_seen("enemy", str(list[0]["boss"]))
	Save.data["stages_beaten"] = {"red_canyon": [false, false, false]}
	var m2 := await _screen("res://ui/StagesScreen.tscn")
	var req2: WText = (m2.call("cards")[1] as Node).find_child("Requirement", true, false)
	assert_str(req2.text).is_equal(StagesScript.requirement(mp, list, 1) + " to open it")
	assert_str(req2.text.to_lower()).contains("tumbleweed king")


func test_start_and_the_card_start_the_stage_once_a_locked_card_nothing() -> void:
	Save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	var m := await _screen("res://ui/StagesScreen.tscn")
	m.set("hold_start", true)
	var cards: Array = m.call("cards")
	var sb: WButton = (cards[1] as Node).find_child("Start", true, false)
	_finger(sb, true)
	_finger(sb, false)
	assert_int(int(m.get("started"))).is_equal(1)
	assert_int(int(m.get("starts"))).is_equal(1)
	# a tap anywhere else on an open card starts it as today
	m.set("started", -1)
	_finger(cards[0], true)
	_finger(cards[0], false)
	assert_int(int(m.get("started"))).is_equal(0)
	assert_int(int(m.get("starts"))).is_equal(2)
	# a locked card: nothing
	m.set("started", -1)
	_finger(cards[2], true)
	_finger(cards[2], false)
	assert_int(int(m.get("started"))).is_equal(-1)
	assert_int(int(m.get("starts"))).is_equal(2)
	# an open card held: the gold inner edge, the card does not move (no press); a locked one keeps its look
	var c0: WTap = cards[0]
	assert_int(c0.box_down.inner).is_greater(0)
	assert_int(c0.box_down.press).is_equal(0)
	assert_object((cards[2] as WTap).box_down).is_same((cards[2] as WTap).box)


func test_the_header_carries_the_map_hero_label_and_the_run_line() -> void:
	Save.data["stages_beaten"] = {"red_canyon": [true, false, false]}
	Save.data["best_runs"]["red_canyon"] = {"time": 995.0, "level": 32, "stage": 3, "kills": 4864}
	assert_array(StagesScript.run_bits("red_canyon")).contains_exactly(["best 16:35", "Lv 32", "stage 3", "4,864 kills"])
	var mp := Registry.map("red_canyon")
	# the title's line, word for word (TitleScreen._refresh_map)
	assert_str(StagesScript.run_line("red_canyon")).is_equal(mp.display_name + " · best 16:35 · Lv 32 · stage 3 · 4,864 kills")
	var m := await _screen("res://ui/StagesScreen.tscn")
	assert_str(m.header.title.text).is_equal("STAGES")
	assert_object(m.header.find_child("Hero", true, false)).is_not_null()
	var top: WText = m.find_child("Top", true, false)
	assert_str(top.text).is_equal(("%s · %s" % [mp.display_name, Registry.character("drifter").display_name]).to_upper())
	var pill: Control = m.find_child("RunLine", true, false)
	assert_object(pill).is_not_null()
	assert_str(str(pill.get_meta("text"))).is_equal("best 16:35 · Lv 32 · stage 3 · 4,864 kills")
	var said := _texts(pill)
	for w in ["16:35", "Lv 32", "4,864", "kills", "stage "]:
		assert_str(said).contains(w)
	# above the first card, under the label
	assert_float(pill.get_global_rect().position.y).is_greater(top.get_global_rect().end.y)
	assert_float(pill.get_global_rect().end.y).is_less((m.call("cards")[0] as Control).get_global_rect().position.y)
	# no run yet: no pill (the title shows the map's name alone)
	Save.data["best_runs"].erase("red_canyon")
	assert_array(StagesScript.run_bits("red_canyon")).is_empty()
	assert_str(StagesScript.run_line("red_canyon")).is_equal(mp.display_name)
	var m2 := await _screen("res://ui/StagesScreen.tscn")
	assert_object(m2.find_child("RunLine", true, false)).is_null()
	# no kills: no kills word
	Save.data["best_runs"]["red_canyon"] = {"time": 600.0, "level": 47, "stage": 2}
	assert_array(StagesScript.run_bits("red_canyon")).contains_exactly(["best 10:00", "Lv 47", "stage 2"])




# ---------------------------------------------------------------- Settings

func test_the_royale_settings_are_today_s_panels_in_slate() -> void:
	Settings.debug_mode = true
	var s := await _screen("res://ui/SettingsScreen.tscn")
	assert_str(s.header.title.text).is_equal("SETTINGS")
	assert_float(s.board_side()).is_equal(SettingsScript.R_SIDE)
	assert_float(s.board_top()).is_equal(SettingsScript.R_TOP)
	var names: Array = []
	for c in s.content.get_children():
		if c.is_queued_for_deletion():
			continue
		names.append(str(c.name))
		var p := c as PanelContainer
		var b := p.get_theme_stylebox("panel") as HardBox
		assert_str(b.royale_kind()).override_failure_message(str(c.name)).is_equal("panel")
		assert_int(b.border).is_equal(R.PANEL_EDGE)
		assert_int(b.shadow).is_equal(R.PANEL_BASE)
		assert_float(p.size.x).is_equal_approx(990.0, 0.5)
	assert_array(names).contains_exactly(["CameraPanel", "SliderPanel", "FloatPanel", "HintsPanel", "AnalyticsPanel", "DebugPanel", "WipePanel"])
	# the first panel where the mock puts it, under the header
	assert_float((s.content.get_child(0) as Control).get_global_rect().position.y).is_equal_approx(SettingsScript.R_TOP, 1.0)


func test_the_choices_read_in_capitals_and_set_the_settings() -> void:
	var keep_cam := Settings.camera_mode
	var keep_size := Settings.float_size
	var s := await _screen("res://ui/SettingsScreen.tscn")
	var cam: WChoice = s.find_child("CameraChoice", true, false)
	assert_str(_texts(cam)).contains("FIXED")
	assert_str(_texts(cam)).contains("FOLLOW")
	assert_str(_texts(cam)).contains("north stays up")
	assert_str(_texts(cam)).contains("swings behind the hero")
	for t in cam.find_children("*", "WText", true, false):
		var w := t as WText
		if w.text == "FIXED" or w.text == "FOLLOW":
			assert_bool(R.is_display(w.font)).is_true()
			assert_int(w.font_size).is_equal(SettingsScript.R_CHOICE_PX)
	cam.choose(1, true)
	assert_int(Settings.camera_mode).is_equal(1)
	var fs: WChoice = s.find_child("FloatSize", true, false)
	assert_str(_texts(fs)).contains("SMALL")
	assert_str(_texts(fs)).contains("LARGE")
	fs.choose(2, true)
	assert_int(Settings.float_size).is_equal(2)
	Settings.camera_mode = keep_cam
	Settings.float_size = keep_size
	# under Wanted the words are as given
	assert_array(SettingsScript._choice_words([["Fixed", "north stays up"]])).is_equal([["FIXED", "north stays up"]])
func test_the_rows_are_74_px_the_sliders_96_white_rubik_26() -> void:
	var s := await _screen("res://ui/SettingsScreen.tscn")
	for n in ["DamageNumbers", "HealNumbers", "XpNumbers", "CoinNumbers", "AnalyticsSwitch", "SurveySwitch", "HintsSwitch"]:
		var sw: WSwitch = s.find_child(n, true, false)
		assert_object(sw).override_failure_message(n).is_not_null()
		assert_vector(sw.custom_minimum_size).is_equal(Vector2(140, SettingsScript.R_ROW_H))
		var row := sw.get_parent() as Control
		assert_float(row.size.y).override_failure_message(n).is_greater_equal(SettingsScript.R_ROW_H)
		var nm: WText = row.find_child("Name", true, false)
		assert_int(nm.font_size).is_equal(SettingsScript.R_ROW_PX)
		assert_bool(nm.color.is_equal_approx(R.WHITE)).is_true()
		assert_bool(R.is_display(nm.font)).is_false()
	for n in ["SliderRowJoysticksize", "SliderRowScreenshake", "SliderRowSound", "SliderRowMusic"]:
		var r: Control = s.find_child(n, true, false)
		assert_object(r).override_failure_message(n).is_not_null()
		assert_float(r.size.y).is_equal(SettingsScript.R_SLIDER_H)
		assert_float((r.find_child("Name", true, false) as Control).size.x).is_greater_equal(SettingsScript.R_SLIDER_LABEL_W)
		assert_int(r.find_children("*", "WSlider", true, false).size()).is_equal(1)
	# the play data's line under the switch's name, today's words
	var aline: WText = s.find_child("AnalyticsLine", true, false)
	assert_str(aline.text).is_equal(Analytics.settings_line())
	assert_int(aline.font_size).is_equal(SettingsScript.R_SUB_PX)
	assert_bool(aline.wrap).is_true()


func test_reset_says_done_and_wipe_is_red_and_asks_through_the_danger_confirm() -> void:
	var s := await _screen("res://ui/SettingsScreen.tscn")
	var reset: WButton = s.find_child("ResetHints", true, false)
	assert_str(reset.role).is_equal(WButton.SLATE)
	assert_str(reset.label_text()).is_equal("RESET")
	assert_vector(reset.custom_minimum_size).is_equal(SettingsScript.R_BUTTON)
	Save.data["hints_seen"] = ["a"]
	reset.pressed.emit()
	assert_array(Save.data["hints_seen"]).is_empty()
	assert_str(reset.label_text()).is_equal("DONE")
	var wipe: WButton = s.get("_wipe")
	assert_str(wipe.role).is_equal(WButton.RED)
	assert_str(wipe.label_text()).is_equal("WIPE")
	assert_object(wipe.get_parent().get_parent()).is_same(s.find_child("WipePanel", true, false))
	s._ask_wipe()
	await _frames(2)
	var c: WConfirm = WConfirm.current(s)
	assert_object(c).is_not_null()
	assert_str(c.button("confirm").role).is_equal(WButton.RED)
	assert_str(c.button("cancel").role).is_equal(WButton.SLATE)
	c.cancel()


func test_the_debug_panel_sits_above_the_wipe_and_follows_the_debug_mode() -> void:
	Settings.debug_mode = false
	var s := await _screen("res://ui/SettingsScreen.tscn")
	assert_object(s.find_child("DebugPanel", true, false)).is_null()
	Settings.debug_mode = true
	s._sync_debug_panel()
	await _frames(1)
	var panel: Node = s.find_child("DebugPanel", true, false)
	assert_object(panel).is_not_null()
	assert_int(panel.get_index()).is_less(s.find_child("WipePanel", true, false).get_index())
	assert_object(panel.find_child("RangedOnScreen", true, false)).is_not_null()
	Settings.debug_mode = false
	s._sync_debug_panel()
	await _frames(1)


func test_the_foot_is_one_line_and_the_version_part_takes_the_hold() -> void:
	var s := await _screen("res://ui/SettingsScreen.tscn")
	var foot: HBoxContainer = s.get("_foot")
	assert_object(foot).is_not_null()
	var v: WText = s.get("_version")
	var saved: WText = s.get("_saved_line")
	assert_object(v.get_parent()).is_same(foot)
	assert_object(saved.get_parent()).is_same(foot)
	assert_str(v.text).is_equal(SettingsScript.version_line())
	assert_str(saved.text).is_equal(s._saved_text())
	assert_str(_texts(foot)).contains(" · ")
	for t: WText in [v, saved]:
		assert_int(t.font_size).is_equal(SettingsScript.R_FOOT_PX)
		assert_bool(t.color.is_equal_approx(R.SECONDARY)).is_true()
	assert_int(v.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	# one line, centred, its top R_FOOT_UP over the foot; the board ends over it
	assert_float(foot.get_global_rect().position.y).is_equal_approx(1920.0 - SettingsScript.R_FOOT_UP, 1.0)
	assert_float(s.scroll.get_global_rect().end.y).is_less(foot.get_global_rect().position.y)
	assert_float(absf(v.get_global_rect().get_center().y - saved.get_global_rect().get_center().y)).is_less(1.0)
	# the 2 s hold: gold halfway (the kit's warning colour), soft again when the finger slides away
	var e := InputEventScreenTouch.new()
	e.pressed = true
	e.position = Vector2(10, 10)
	s._on_version_input(e)
	s._process(SettingsScript.HOLD * 0.6)
	assert_bool(v.color.is_equal_approx(R.GOLD_TEXT)).is_true()
	var d := InputEventScreenDrag.new()
	d.position = Vector2(200, 10)
	s._on_version_input(d)
	assert_bool(v.color.is_equal_approx(R.SECONDARY)).is_true()
	# the debug mode's message has the line to itself for a moment
	s._foot_message(true)
	assert_bool(saved.visible).is_false()
	assert_bool(v.wrap).is_true()
	s._foot_message(false)
	assert_bool(saved.visible).is_true()
	assert_bool(v.wrap).is_false()




func test_the_capture_and_audit_tools_carry_the_new_states() -> void:
	var shots := FileAccess.get_file_as_string("res://tools/wanted_shots.gd")
	for k in ["18d-stages-first-visit", "18e-stages-inset130-held", "05c-settings-foot", "05d-settings-debug"]:
		assert_bool(shots.contains(k)).override_failure_message(k).is_true()
	var audit := FileAccess.get_file_as_string("res://tools/touch_audit.gd")
	assert_bool(audit.contains("func _stages_settings_p123()")).is_true()
	assert_bool(audit.contains("stages_start")).is_true()
	assert_bool(audit.contains("settings_rows")).is_true()
