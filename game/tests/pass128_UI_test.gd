## Pass 128, lane UI, jobs 1 to 3:
##  1. the Boss Chest's speed panel: the gold bar starts past the multiplier as drawn, whatever it reads (x1 .. x9.9);
##  2. a board's scroll never starts above its sheet's inner top edge, and the page rests where it did (ScreenBase.scroll_top);
##  3. "Heroes" are "Outlaws" in the words a person reads (the tab, the screen's name, the arena's tab, the banner's kin).
extends GdUnitTestSuite


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.end()


func test_the_gold_bar_starts_past_the_multiplier() -> void:
	for m: float in [1.0, 1.1, 1.3, 1.6, 2.0, 3.5, 9.9]:
		var ends := BossChestScreen.ROYALE_PAD + BossChestScreen.meter_mult_width(m)
		var bar := BossChestScreen.meter_bar_x(m)
		assert_float(bar).override_failure_message("x%.1f: the bar at %.1f, the multiplier ends %.1f" % [m, bar, ends]) \
			.is_greater_equal(ends + BossChestScreen.ROYALE_MULT_GAP - 0.01)
		assert_float(bar).is_greater_equal(BossChestScreen.ROYALE_BAR_X)
		# and the bar keeps most of the panel (1080 wide: 984 of panel)
		assert_float(984.0 - bar - BossChestScreen.ROYALE_PAD).is_greater(500.0)
	# x1 fits before the mock's bar: it stays where the mock has it
	assert_float(BossChestScreen.meter_bar_x(1.0)).is_equal(BossChestScreen.ROYALE_BAR_X)
	# a decimal does not
	assert_float(BossChestScreen.meter_bar_x(1.6)).is_greater(BossChestScreen.ROYALE_BAR_X)


func test_a_boards_scroll_starts_inside_its_sheet_and_the_page_rests_where_it_did() -> void:
	for path: String in ["res://ui/HeroesScreen.tscn", "res://ui/SettingsScreen.tscn",
			"res://ui/StagesScreen.tscn"]:
		var s: ScreenBase = auto_free(load(path).instantiate())
		add_child(s)
		await get_tree().process_frame
		var sheet: Control = s.board_sheet_node
		assert_object(sheet).override_failure_message(path).is_not_null()
		# the slide-in moves offset_top for 0.25 s: the rule is scroll_top()'s
		var top := s.scroll_top() + W.safe_top()
		assert_float(top).override_failure_message(path).is_greater_equal(sheet.offset_top + float(ScreenBase.SHEET_EDGE) - 0.01)
		# the page starts at board_top() as before: the margin over it is what the scroll gave up
		assert_float(top + float(s.margin.get_theme_constant("margin_top"))).override_failure_message(path) \
			.is_equal_approx(s.board_top() + W.safe_top(), 0.5)
		assert_float(s.scroll_top()).is_less_equal(s.board_top())
		s.queue_free()
		await get_tree().process_frame
	# the Outlaws screen's own numbers: the page at 200, the sheet's edge at 182 + 3
	var hs: ScreenBase = auto_free(load("res://ui/HeroesScreen.tscn").instantiate())
	add_child(hs)
	await get_tree().process_frame
	assert_float(hs.scroll_top()).is_equal(185.0)
	assert_int(hs.margin.get_theme_constant("margin_top")).is_equal(15)


func test_heroes_read_outlaws() -> void:
	var bar_script = load("res://ui/wanted/WTabBar.gd")
	assert_str(str(bar_script.WORDS["heroes"])).is_equal("OUTLAWS")
	assert_array(bar_script.TABS).contains(["heroes"])
	var tab: Array = ArenaPanel.TABS.filter(func(t: Array) -> bool: return t[0] == "hero")
	assert_str(str(tab[0][1])).is_equal("OUTLAW")
	# the arena's tab row still fits its sheet (1080 wide, 10 in at each side, the panel's padding)
	var row := 120.0
	for t: Array in ArenaPanel.TABS:
		var b: Control = auto_free(UiKit.button(str(t[1]), 21, false, 70))
		row += b.get_combined_minimum_size().x + 6.0
	assert_float(row).override_failure_message("the arena's tabs are %.0f px wide" % row).is_less(1000.0)
	# the Outlaws screen: its name and its picker's line
	var hs: Control = auto_free(load("res://ui/HeroesScreen.tscn").instantiate())
	add_child(hs)
	await get_tree().process_frame
	assert_str(str(hs.get("header").title.text)).is_equal("OUTLAWS")
	var lab: WText = hs.find_child("Heroes", true, false).get_node("Label")
	assert_str(lab.text.to_upper()).contains("OUTLAWS · ")
	# no word a person reads says hero in the content's text fields
	for d in Registry.mutations.values() + Registry.perks.values() + Registry.passives.values() + Registry.weapons.values():
		for key in ["display_name", "flavour", "text"]:
			var said = d.get(key)
			if said is String:
				assert_bool((said as String).to_lower().contains("hero")).override_failure_message("%s.%s: %s" % [d.id, key, said]).is_false()
