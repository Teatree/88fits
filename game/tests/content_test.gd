extends GdUnitTestSuite


func test_registry_has_base_content() -> void:
	assert_bool(Registry.weapons.has("boomstick")).is_true()
	assert_bool(Registry.passives.has("haste")).is_true()
	assert_bool(Registry.enemies.has("goblin")).is_true()
	assert_bool(Registry.maps.has("red_canyon")).is_true()
	# pass 46: the lines are passives (content/lines is gone as a type), and every evolution pair names the other
	assert_bool(JsonContent.TYPES.has("lines")).is_false()
	assert_bool(Registry.passives.has("energy_shield")).is_true()
	assert_array(Registry.problems).is_empty()


func test_every_weapon_evolution_resolves() -> void:
	for w in Registry.base_weapons():
		assert_bool(Registry.weapons.has(w.evolves_into)).override_failure_message("missing evolution for " + w.id).is_true()
		# pass 26: the path leads to the evolution, there is no passive key
		assert_str(w.evolves_with).is_equal("")


func test_json_roundtrip_effects() -> void:
	var d := JsonContent.load_json("res://content/weapons/boomstick/boomstick.json")
	var w: WeaponDef = JsonContent.build("weapons", d, "res://content/weapons/boomstick/")
	# pass 48: five weapon levels (pairs of the old eight folded together, tools/compress_levels.py), the same seven effects
	assert_int(w.levels.size()).is_equal(5)
	assert_int(w.max_level).is_equal(5)
	assert_int(w.effects_for_level(5).size()).is_equal(7)
	var eff: Effect = w.effects_at_level(2)[0]
	assert_str(eff.stat).is_equal("amount")


func test_timeline_cap_grows() -> void:
	var m: MapDef = Registry.map("red_canyon")
	# pass 83 re-pin: the cap is Garry's to shape in the Level Editor (his cap_curve starts at 181 and steps down and up
	# again since 2026-10-16), so only its shape is pinned: positive all through the run, never past the hard cap
	for t: float in [0.0, 60.0, 300.0, 600.0, 1200.0, 3600.0]:
		assert_int(m.timeline.cap_at(t)).is_greater(0)
	# pass 105 re-pin: Garry raised cap_max to 500 (2026-10-24, after pass 102 showed it cut his curve); the cap is in load
	# and may sit above the hard cap (in bodies), which then binds: only a positive cap within cap_max is pinned
	for t2: float in [0.0, 600.0, 3600.0]:
		assert_int(m.timeline.cap_at(t2)).is_less_equal(maxi(m.timeline.cap_max, 1))


func test_pickups_are_content() -> void:
	assert_bool(Registry.maps.has("red_canyon")).is_true()
	assert_bool(not Registry.maps.has("mossy_hollow")).is_true()
	assert_bool(Registry.characters.has("astro")).is_true()
	for id in ["heart", "rage", "sprint", "shield", "magnet_pulse"]:
		assert_bool(Registry.pickups.has(id)).override_failure_message("missing pickup " + id).is_true()
	var m: MapDef = Registry.map("red_canyon")
	assert_bool(m.timeline.pickups.has("roster")).is_true()
	for a in m.skins.keys():
		assert_bool(Registry.enemies.has(m.skins[a])).override_failure_message("desert skin " + str(a)).is_true()
	assert_bool(Registry.enemies.has(m.boss)).is_true()
	var d := JsonContent.load_json("res://content/pickups/rage/rage.json")
	var p: PickupDef = JsonContent.build("pickups", d, "res://content/pickups/rage/")
	assert_str(p.effect_kind).is_equal("buff")
	# Berserk: might and weapon speed
	assert_int(p.effects.size()).is_equal(2)
	assert_float(p.duration).is_greater(0.0)


func test_structures_are_content() -> void:
	assert_int(Registry.structures.size()).is_greater_equal(6)
	for id in ["uber_magnet", "shop", "healing_well", "loot_cache", "war_drum", "hooded_figure", "beacon", "gold_bank"]:
		assert_bool(Registry.structures.has(id)).override_failure_message("missing structure " + id).is_true()
	var drum: StructureDef = Registry.structure("war_drum")
	assert_str(drum.effect_kind).is_equal("buff")
	assert_int(drum.effects.size()).is_equal(2)
	assert_float(Registry.structure("uber_magnet").weight).is_less(Registry.structure("healing_well").weight)
	var m: MapDef = Registry.map("red_canyon")
	# pass 73: a structure that stands its own count (params.per_map, the Totem Poles) is not in the draw
	assert_int(int(m.timeline.structures.get("count", 0))).is_greater_equal(StructureManager.drawn(Registry.structures.values()).size())


func test_poison_weapons_are_content() -> void:
	for id in ["poison_dart", "rattlesnake", "skull_rain"]:
		var w: WeaponDef = Registry.weapon(id)
		assert_bool(w != null).override_failure_message("missing " + id).is_true()
		assert_float(float(w.base.get("poison_damage", 0.0))).is_greater(0.0)
	assert_bool(Registry.passives.has("venom")).is_true()
	assert_bool(Registry.weapons.has("plague_volley")).is_true()
	var inst := WeaponInstance.new(Registry.weapon("rattlesnake"), 8)
	inst.rebuild(StatSheet.new(), [])
	assert_int(inst.stat_int("poison_stacks")).is_greater(1)
	assert_str(inst.description()).contains("Poisons")


func test_shop_prices_scale_with_power() -> void:
	var pea: WeaponDef = Registry.weapon("peashooter")
	var cheap := StructureShop.price_of({"def": pea, "type": "weapon", "level_from": 0, "level_to": 1})
	var dear := StructureShop.price_of({"def": pea, "type": "weapon", "level_from": 4, "level_to": 5})
	assert_int(dear).is_greater(cheap)
	assert_int(cheap).is_greater(0)
	# pass 60 (Garry: "Player can afford like 2 items per Stage"): a price is half a stage's gold by kind and rarity
	# (StructureShop.price_of; pass60_ui_test pins the table), so a fresh common weapon costs 0.8 of the stage's base
	assert_int(cheap).is_equal(int(round(float(StructureShop.PRICE_BASE_BY_STAGE[StructureShop.price_stage() - 1]) * 0.8)))


func test_timed_buffs_apply_and_expire() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var before := Run.player_sheet.get_stat("might", 1.0)
	var rage: PickupDef = Registry.pickup("rage")
	Run.add_timed_effects(rage.id, rage.display_name, rage.effects, rage.duration)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_greater(before)
	Run.elapsed += rage.duration + 1.0
	var ended := Run.tick_timed()
	assert_int(ended.size()).is_equal(1)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal(before)


func test_weapon_instance_levels_apply() -> void:
	var w: WeaponDef = Registry.weapon("boomstick")
	var lv1 := WeaponInstance.new(w, 1)
	lv1.rebuild(StatSheet.new(), [])
	var lv8 := WeaponInstance.new(w, 8)
	lv8.rebuild(StatSheet.new(), [])
	assert_int(lv8.stat_int("amount")).is_greater(lv1.stat_int("amount"))
	assert_float(lv8.stat("damage")).is_greater(lv1.stat("damage"))
