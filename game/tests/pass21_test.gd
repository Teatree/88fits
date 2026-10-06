extends GdUnitTestSuite


func test_new_items_are_content() -> void:
	for id in ["tommy_gun", "land_mine"]:
		assert_bool(Registry.weapons.has(id)).override_failure_message("missing " + id).is_true()
	assert_bool(bool(Registry.weapon("tommy_gun").params.get("burst", false))).is_true()
	assert_str(Registry.weapon("land_mine").behavior).is_equal("MineLayer")
	assert_bool(Registry.weapons.has("chicago_typewriter")).is_true()
	assert_bool(Registry.weapons.has("minefield")).is_true()
	for id in ["quickdraw", "haste"]:
		assert_bool(Registry.passives.has(id)).override_failure_message("missing " + id).is_true()
	assert_bool(Registry.characters.has("buck")).is_true()
	assert_bool(Registry.character("buck").specials.has("momentum")).is_true()
	assert_bool(Registry.maps.has("red_canyon")).is_true()
	assert_bool(Registry.enemies.has("sand_lizard")).is_true()
	# the tommy gun outranges the boomstick by about double and hits softer
	var tg: WeaponDef = Registry.weapon("tommy_gun")
	var bs: WeaponDef = Registry.weapon("boomstick")
	assert_float(float(tg.base["range"])).is_greater_equal(float(bs.base["range"]) * 2.0)
	assert_float(float(tg.base["damage"])).is_less(float(bs.base["damage"]))


func test_lifesteal_heals_from_damage() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	# lifesteal is Thirst (a line from pass 26, a passive since pass 46); pass 31 cut it to 1.5% a level and capped what
	# it may heal a second
	Run.add_or_level_passive("thirst")
	Run.add_or_level_passive("thirst")
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("lifesteal", 0.0)).is_equal_approx(0.03, 0.0001)
	var healed := [0.0]
	Run.lifesteal_healed.connect(func(n): healed[0] += n)
	Run.add_damage("boomstick", 100.0)
	assert_float(healed[0]).is_equal_approx(3.0, 0.0001)


func test_momentum_raises_speed_and_might_and_resets() -> void:
	Run.start(Registry.character("buck"), Registry.map("red_canyon"))
	var base_speed := Run.player_sheet.get_stat("move_speed", 3.6)
	var base_might := Run.player_sheet.get_stat("might", 1.0)
	assert_float(base_speed).is_less(3.6)   # he starts slower than the others
	Run.momentum = 1.0
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_greater(base_speed * 1.4)
	assert_float(Run.player_sheet.get_stat("might", 0.0)).is_greater(base_might * 1.3)
	Run.momentum = 0.0
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(base_speed, 0.001)


func test_pickups_drop_by_hardness() -> void:
	var t: WaveTimeline = Registry.map("red_canyon").timeline
	assert_bool(t.pickups.has("per_kill")).is_true()
	assert_bool(t.pickups.has("interval")).is_false()
	var goblin: EnemyDef = Registry.enemy("goblin")
	var boss: EnemyDef = Registry.enemy("tumbleweed_king")
	assert_float(float(t.pickups["per_kill"]) * boss.xp_mult).is_greater(float(t.pickups["per_kill"]) * goblin.xp_mult * 5.0)
