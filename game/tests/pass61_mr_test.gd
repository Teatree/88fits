## Pass 61, lane MR (Garry: "Make the EXP bar 1.8 times bigger. Make sure the rainbow animation isn't broken."): the XP
## rail is 65 px (36 x 1.8), its fill 11 px in, everything under it laid out from its foot, and the level-up screen's
## rainbow copy reads the same pair. The lane's other half (the Upgrade board's rank bars and form icons) left with the
## board in pass 129.
extends GdUnitTestSuite


func _fresh_save() -> void:
	Save.data = Save._default()
	Save._migrate_seen()


func after_test() -> void:
	Settings.top_inset = -1
	Run.arena = false
	Run.end()
	HUD.band_h = float(HUD.BAND_H)


# ---------------------------------------------------------------- 1. the rail, 1.8 times

func test_the_rail_is_one_point_eight_times_its_pass_56_height() -> void:
	assert_float(HUD.RAIL_H).is_equal(roundf(36.0 * 1.8))
	assert_float(HUD.RAIL_H).is_equal(65.0)
	assert_float(HUD.RAIL_INSET).is_equal(roundf(6.0 * 1.8))
	# the fill keeps its two thirds of the rail (24 of 36 before, 43 of 65 now)
	assert_float(HUD.RAIL_H - 2.0 * HUD.RAIL_INSET).is_equal(43.0)
	# everything under it laid out from its foot, the gaps as before
	assert_float(HUD.TOP_Y).is_equal(HUD.RAIL_H + 12.0)
	assert_float(HUD.SLOT_Y).is_equal(HUD.TOP_Y + 96.0)
	assert_float(float(HUD.BAND_H)).is_equal(HUD.SLOT_Y + 94.0)
	# the level-up screen's rainbow rail is the same rail, and its header and cards moved down by what it gained
	assert_float(CardScreen.RAIL_H).is_equal(HUD.RAIL_H)
	assert_float(CardScreen.RAIL_INSET).is_equal(HUD.RAIL_INSET)
	assert_float(CardScreen.RAIL_GROWTH).is_equal(HUD.RAIL_H - 18.0)
	assert_float(CardScreen.HEADER_TOP).is_equal(110.0 + 47.0)
	assert_float(CardScreen.LIST_TOP).is_equal(470.0 + 47.0)
	# the glint grew with the fill
	assert_float(CardScreen.RAIL_GLINT).is_equal(7.0)


func test_the_hud_lays_out_under_the_thicker_rail_with_and_without_a_cutout() -> void:
	for inset: int in [0, 130]:
		Settings.top_inset = inset
		Run.start(Registry.character("astro"), Registry.map("red_canyon"))
		Run.debug_clear_items()
		Run.add_weapon(Registry.weapon("boomstick"), 2)
		var hud: HUD = auto_free(HUD.new())
		add_child(hud)
		await get_tree().process_frame
		await get_tree().process_frame
		var why := "inset %d" % inset
		var rail := hud.find_child("XpRail", false, false) as Control
		assert_float(rail.get_global_rect().position.y).override_failure_message(why).is_equal(float(inset))
		assert_float(rail.size.y).override_failure_message(why).is_equal(65.0)
		var foot := float(inset) + 65.0
		assert_float(hud._lv_plate.get_global_rect().position.y).override_failure_message(why).is_equal(foot + 12.0)
		assert_float(hud._pause_btn.get_global_rect().position.y).override_failure_message(why).is_equal(foot + 10.0)
		assert_float(hud._slots.position.y).override_failure_message(why).is_equal(foot + 108.0)
		assert_float(HUD.band_h).override_failure_message(why).is_equal(float(HUD.BAND_H) + inset)
		# nothing in the top row starts above the rail's foot
		for p: Control in [hud._lv_plate, hud._timer_plate, hud._gold_plate, hud._pause_btn]:
			assert_float(p.get_global_rect().position.y).override_failure_message(why + " " + str(p.name)).is_greater_equal(foot)
		hud.queue_free()
		Run.end()
		await get_tree().process_frame


func test_the_rainbow_rail_fills_the_new_height_and_keeps_moving() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer(CardPool.level_up_offer(3), "LEVEL 2!", false)
	await get_tree().process_frame
	var rail := cs.find_child("XpRail", false, false) as Control
	assert_float(rail.size.y).is_equal(65.0)
	assert_float(rail.size.x).is_equal(cs.get_viewport_rect().size.x)
	assert_float(cs.rail_frac()).is_equal(1.0)
	# the hues race: the colour at one spot changes as the screen's clock runs
	var t0: float = cs._rail_t
	for i in 10:
		await get_tree().process_frame
	var t1: float = cs._rail_t
	assert_float(t1).is_greater(t0)
	assert_bool(CardScreen.rail_colour(0.2, t0).is_equal_approx(CardScreen.rail_colour(0.2, t1))).is_false()
	# the header and the cards still sit under the rail's foot
	assert_float(cs.header.get_global_rect().position.y).is_greater(rail.get_global_rect().end.y)
	assert_float(cs._list.get_global_rect().position.y).is_greater(rail.get_global_rect().end.y)
	cs.visible = false
