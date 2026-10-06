extends GdUnitTestSuite


func before_test() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func test_add_weapon_and_level() -> void:
	var w := Run.add_weapon(Registry.weapon("peashooter"), 1)
	assert_object(w).is_not_null()
	Run.level_weapon("peashooter")
	assert_int(Run.weapon_instance("peashooter").level).is_equal(2)


func test_passive_changes_weapon_damage() -> void:
	var w := Run.add_weapon(Registry.weapon("peashooter"), 1)
	var before := w.stat("damage")
	Run.add_or_level_passive("brawn")
	assert_float(Run.weapon_instance("peashooter").stat("damage")).is_greater(before)


func test_evolution_requires_max_level_and_passive() -> void:
	var w := Run.add_weapon(Registry.weapon("boomstick"), 5)
	assert_bool(Run.evolution_ready(w)).is_false()
	# pass 48: every mutation of the path (Dragon's Breath, the lane Birdshot, Both Barrels), and the Blunderbuss
	# replaces the Doomstick (hidden, kept)
	Run.add_mutation("dragons_breath")
	Run.stage = 1
	Run.add_mutation("birdshot_lane")
	assert_bool(Run.evolution_ready(w)).is_false()
	Run.stage = 2
	Run.add_mutation("both_barrels")
	Run.stage = 0
	assert_bool(Run.evolution_ready(w)).is_true()
	var evo := Run.evolve(w)
	assert_str(evo.def.id).is_equal("blunderbuss")
	assert_bool(Run.has_weapon("boomstick")).is_false()


func test_xp_levels_up() -> void:
	var levels_before := Run.level
	Run.add_xp(Run.xp_to_next() + 1.0)
	assert_int(Run.level).is_equal(levels_before + 1)


func test_card_offer_respects_slots() -> void:
	for w in Registry.base_weapons():
		if Run.weapons.size() < Run.MAX_WEAPONS:
			Run.add_weapon(w, 8)
	var offer := CardPool.level_up_offer(3)
	for c in offer:
		# at the cap the only weapon cards are levels of what is held; passives, mutations and perks are their own kinds
		assert_bool(["passive", "mutation", "perk"].has(str(c["type"])) or Run.has_weapon(c["id"])).is_true()
