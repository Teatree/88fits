## Pass 153: the Trail's choice card (the whole choice in the pop-up, changeable there), Endless windows' pulse (quiet
## stretches, a share of the drawn rows a pulse, one tab a row a pulse, a bigger burst) and Endless's kill chests at a
## share of the stage's own rate (WaveDirector.kill_chest_ok).
extends GdUnitTestSuite

const FIX := "res://tests/fixtures/trail_screen.json"
const SCENE := "res://ui/TrailScreen.tscn"


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from(FIX)
	Nav.clear()
	Nav.navigate = func(_path: String) -> void: pass


func after_test() -> void:
	Nav.navigate = Callable()
	Nav.clear()
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()
	Run.endless = false


func _have(bought: Array, gold: int) -> void:
	Save.data["trail"] = {"bought": bought.duplicate(), "spent": 0, "had": []}
	Save.data["gold"] = gold
	Trail.refresh()


func _open() -> TrailScreen:
	var s: TrailScreen = auto_free(load(SCENE).instantiate())
	add_child(s)
	for k in 5:
		await get_tree().process_frame
	return s


# ---------------------------------------------------------------- the choice card

func test_buy_on_a_choice_opens_the_choice_card_with_every_member() -> void:
	_have(["n01", "n02"], 5000)
	var s := await _open()
	s.select("n03a")
	s.press_buy()
	var c := s.choice_card()
	assert_object(c).is_not_null()
	var opts := c.body_box.get_node("Options")
	assert_int(opts.get_child_count()).is_equal(Trail.group("n03a").size())
	assert_object(opts.get_node_or_null("Option_n03a")).is_not_null()
	assert_object(opts.get_node_or_null("Option_n03b")).is_not_null()
	# the one tapped is chosen; the line says what it closes
	assert_bool(_tile_of(opts.get_node("Option_n03a")).get("chosen")).is_true()
	assert_str((c.body_box.get_node("ChoiceNote") as WText).text).is_equal(Loc.t("ui.trail.choice_closes", {"node": TrailScreen.name_of(Trail.node("n03a")), "nodes": TrailScreen.name_of(Trail.node("n03b"))}))


func _tile_of(opt: Node) -> Node:
	for k in opt.find_children("Tile", "", true, false):
		return k
	return null


func test_a_tap_on_another_option_changes_the_choice_there_and_buy_takes_it() -> void:
	_have(["n01", "n02"], 5000)
	var s := await _open()
	s.select("n03a")
	s.press_buy()
	var c := s.choice_card()
	(c.body_box.get_node("Options/Option_n03b") as WTap).pressed.emit()
	assert_str(s.selected).is_equal("n03b")
	assert_object(s.choice_card()).is_not_null()
	assert_bool(_tile_of(c.body_box.get_node("Options/Option_n03b")).get("chosen")).is_true()
	assert_bool(_tile_of(c.body_box.get_node("Options/Option_n03a")).get("chosen")).is_false()
	assert_str((c.body_box.get_node("ChoiceNote") as WText).text).is_equal(Loc.t("ui.trail.choice_closes", {"node": TrailScreen.name_of(Trail.node("n03b")), "nodes": TrailScreen.name_of(Trail.node("n03a"))}))
	c.confirm()
	assert_str(Trail.state("n03b")).is_equal("bought")
	assert_str(Trail.state("n03a")).is_equal("closed")
	assert_object(s.choice_card()).is_null()


func test_not_now_keeps_the_gold_and_a_short_purse_buys_nothing() -> void:
	_have(["n01", "n02"], 5000)
	var s := await _open()
	s.select("n03a")
	s.press_buy()
	s.choice_card().cancel()
	assert_str(Trail.state("n03a")).is_equal("open")
	assert_int(Save.gold()).is_equal(5000)
	# a purse that pays for one member only: choosing the dearer one turns BUY grey and buys nothing
	var pa := Trail.price("n03a")
	var pb := Trail.price("n03b")
	if pa == pb:
		return
	var cheap := "n03a" if pa < pb else "n03b"
	var dear := "n03b" if cheap == "n03a" else "n03a"
	_have(["n01", "n02"], mini(pa, pb))
	s.select(cheap)
	s.press_buy()
	var c := s.choice_card()
	s.choose_option(dear)
	assert_int(int(c.button("confirm").get_meta("short"))).is_greater(0)
	c.confirm()
	assert_str(Trail.state(dear)).is_equal("open")
	assert_object(s.choice_card()).is_not_null()


# ---------------------------------------------------------------- the pulse

func test_the_pulse_reads_its_keys_and_is_off_without_them() -> void:
	var tl := WaveTimeline.new()
	tl.stage_list = [{"id": "a", "length": 100.0, "endless_window": {"length": 60, "max_count": 50, "roster": []}},
		{"id": "b", "length": 100.0, "endless_window": {"length": 60, "max_count": 50, "pulse_on": 6, "pulse_off": 3, "pulse_rows": 0.6, "pulse_burst": 1.5, "roster": []}}]
	assert_bool(bool(tl.endless_window_pulse(0)["active"])).is_false()
	var p := tl.endless_window_pulse(1)
	assert_bool(bool(p["active"])).is_true()
	assert_float(float(p["on"])).is_equal(6.0)
	assert_float(float(p["off"])).is_equal(3.0)
	assert_float(float(p["rows"])).is_equal(0.6)
	assert_float(float(p["burst"])).is_equal(1.5)


func test_a_window_is_quiet_in_its_pulse_s_off_seconds() -> void:
	var w := BossFightWindow.new()
	assert_bool(w.quiet(7.0)).is_false()
	w.pulse_on = 6.0
	w.pulse_off = 3.0
	assert_bool(w.quiet(0.0)).is_false()
	assert_bool(w.quiet(5.9)).is_false()
	assert_bool(w.quiet(6.0)).is_true()
	assert_bool(w.quiet(8.9)).is_true()
	assert_bool(w.quiet(9.0)).is_false()
	assert_bool(w.quiet(16.5)).is_true()


# ---------------------------------------------------------------- Endless's chests

func _director() -> WaveDirector:
	var d := WaveDirector.new()
	d.timeline = WaveTimeline.new()
	d.timeline.endless = {"chest_share": 0.9}
	return d


func test_the_stage_counts_its_kill_chests_and_endless_owes_them_at_its_share() -> void:
	var d := _director()
	d.phase = WaveDirector.Phase.NORMAL
	for k in 6:
		assert_bool(d.kill_chest_ok()).is_true()
	d._stage_secs = 600.0
	assert_int(int(d.chest_rate()["chests"])).is_equal(6)
	d.phase = WaveDirector.Phase.ENDLESS
	# nothing owed yet: the chest is held back
	assert_bool(d.kill_chest_ok()).is_false()
	# 0.9 x 6 chests / 600 s = one owed after 111 s
	d._chest_owed = minf(d._chest_owed + 0.9 * 6.0 / 600.0 * 112.0, 1.0)
	assert_bool(d.kill_chest_ok()).is_true()
	assert_bool(d.kill_chest_ok()).is_false()
	assert_int(int(d.chest_rate()["dropped"])).is_equal(1)
	assert_int(int(d.chest_rate()["held"])).is_equal(2)
	d.free()


func test_no_limit_below_a_minute_of_stage_or_with_a_negative_share() -> void:
	var d := _director()
	d.phase = WaveDirector.Phase.ENDLESS
	d._stage_secs = 30.0
	assert_bool(d.kill_chest_ok()).is_true()
	d._stage_secs = 600.0
	d.timeline.endless = {"chest_share": -1.0}
	assert_bool(d.kill_chest_ok()).is_true()
	assert_float(d.timeline.endless_value("chest_share")).is_equal(-1.0)
	d.timeline.endless = {}
	assert_float(d.timeline.endless_value("chest_share")).is_equal(0.9)
	d.free()


func test_the_map_paces_every_endless_window_in_pulses() -> void:
	var m := Registry.map("red_canyon")
	for i in m.timeline.stage_list.size():
		if not m.timeline.has_endless_window(i):
			continue
		var p := m.timeline.endless_window_pulse(i)
		assert_bool(bool(p["active"])).override_failure_message("stage %d's Endless window pulses" % (i + 1)).is_true()
		assert_float(float(p["burst"])).is_greater(1.0)
