extends GdUnitTestSuite

## Pass 23: the level-up loop (reroll / skip / banish), the one-element rule on passives, the seven new passive
## mechanisms, named hero traits, smaller prop colliders and the boss magnet.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_every_run_starts_with_a_reroll_a_banish_and_the_stage_s_skips() -> void:
	_start()
	assert_int(Run.rerolls_left).is_greater_equal(1)
	assert_int(Run.banishes_left).is_greater_equal(1)
	# pass 47: the skips are the stage's (two at base, shared by the level-ups and the chests) and pay nothing
	# (pass47_hero_test plays one through the Game); skipping no longer pays gold
	assert_int(Run.skips_left).is_equal(Run.player_sheet.get_int("skips"))
	assert_int(Run.skips_left).is_greater_equal(2)


func test_banish_removes_one_card_and_keeps_the_others() -> void:
	_start()
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	var offer := CardPool.level_up_offer(3)
	assert_int(offer.size()).is_equal(3)
	var gone: String = offer[0]["id"]
	var kept: Array = [offer[1]["id"], offer[2]["id"]]
	Run.banished.append(gone)
	var fresh := CardPool.level_up_offer(1, kept)
	assert_int(fresh.size()).is_equal(1)
	assert_bool(kept.has(fresh[0]["id"])).is_false()
	assert_str(fresh[0]["id"]).is_not_equal(gone)
	# banished for the run: never offered again
	for k in range(20):
		for c in CardPool.level_up_offer(3):
			assert_str(c["id"]).is_not_equal(gone)


func test_venom_is_a_poison_item_and_joins_a_fire_build_too() -> void:
	assert_str(Run.element_of(Registry.passive("venom"))).is_equal("poison")
	assert_str(Run.element_of(Registry.passive("kindling"))).is_equal("fire")
	assert_str(Run.element_of(Registry.passive("haste"))).is_equal("")
	# pass 36: a fire build is offered poison too
	_start()
	Run.add_weapon(Registry.weapon("flare_gun"), 1)
	var seen := false
	for k in range(200):
		for c in CardPool.level_up_offer(3):
			if str(c["id"]) == "venom":
				seen = true
	assert_bool(seen).override_failure_message("venom never offered to a fire build").is_true()


func test_new_passives_are_content_with_their_mechanism_stats() -> void:
	var want := {"deadeye": "crit_chance", "guillotine": "execute_frac", "adrenaline": "adrenaline_speed",
		"overkill": "overkill", "ricochet": "ricochet", "field_notes": "xp_gain"}
	for id in want.keys():
		var def: PassiveDef = Registry.passive(id)
		assert_object(def).override_failure_message("missing passive " + id).is_not_null()
		var stats: Array = []
		for e in def.effects_for_level(1):
			stats.append(e.stat)
		assert_bool(stats.has(want[id])).override_failure_message("%s should touch %s, has %s" % [id, want[id], stats]).is_true()
		assert_bool(StatSheet.PLAYER_DEFAULTS.has(want[id])).override_failure_message("no default for " + want[id]).is_true()
		assert_str(TextGen.describe_effects(def.effects_for_level(1))).is_not_empty()


func test_passive_stats_reach_the_player_sheet() -> void:
	_start()
	# six passives: stage 3's cap (pass 46: four on stage 1, five on stage 2)
	Run.stage = 2
	for id in ["deadeye", "guillotine", "overkill", "ricochet", "field_notes"]:
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " found no slot").is_true()
	assert_bool(Run.add_or_level_passive("bristle")).is_true()   # thorns live on Bristle (a line in pass 26, a passive since 46)
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).is_equal_approx(0.08, 0.001)
	assert_float(Run.player_sheet.get_stat("crit_damage", 0.0)).is_equal_approx(2.0, 0.001)
	# (re-pinned in pass 95, lane PASSIVES: the items' first rungs are higher)
	assert_float(Run.player_sheet.get_stat("execute_frac", 0.0)).is_equal_approx(0.09, 0.001)
	assert_float(Run.player_sheet.get_stat("thorns", 0.0)).is_equal_approx(8.0, 0.001)
	assert_float(Run.player_sheet.get_stat("overkill", 0.0)).is_equal_approx(0.4, 0.001)
	assert_float(Run.player_sheet.get_stat("ricochet", 0.0)).is_equal_approx(0.25, 0.001)
	assert_float(Run.player_sheet.get_stat("xp_gain", 0.0)).is_equal_approx(1.08, 0.001)


func test_field_notes_scale_xp() -> void:
	_start()
	Run.add_xp(10.0)
	var plain := Run.xp
	_start()
	# pass 47: a line of four levels (+8% each, ×1.36 at the top); it was five passive levels (×1.47)
	for k in range(4):
		Run.add_or_level_passive("field_notes")
	Run.rebuild_sheets()
	Run.add_xp(10.0)
	assert_float(Run.xp).is_greater(plain * 1.3)


func test_adrenaline_stacks_on_kills_and_fades() -> void:
	_start()
	Run.add_or_level_passive("adrenaline")
	Run.rebuild_sheets()
	var base_speed := Run.player_sheet.get_stat("move_speed", 0.0)
	for k in range(25):
		Run.add_kill("goblin", "peashooter")
	assert_int(Run.adrenaline).is_equal(Run.ADRENALINE_MAX)
	Run.tick_timed()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_greater(base_speed)
	# the streak ends: the stacks go together and the sheet drops back
	Run.elapsed = Run.adrenaline_until + 0.1
	Run.tick_timed()
	assert_int(Run.adrenaline).is_equal(0)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(base_speed, 0.001)


func test_heroes_have_named_traits_and_roughly_equal_budgets() -> void:
	for id in ["astro", "drifter", "dad", "buck"]:
		var c: CharacterDef = Registry.character(id)
		assert_str(c.trait_name).override_failure_message(id + " has no trait name").is_not_empty()
		assert_str(c.trait_text).override_failure_message(id + " has no trait text").is_not_empty()
	assert_float(Registry.character("astro").level_heal).is_greater(0.0)
	assert_float(Registry.character("buck").trait_effects[0].value).is_equal_approx(-0.15, 0.001)
	# every hero's trait gives something and costs something or gives a mechanic: no hero is all downside (re-pinned in
	# pass 61: the heroes in play carry it as a stat a level, level_trait)
	for id in ["astro", "drifter", "dad"]:
		var plus := 0
		for e in Registry.character(id).trait_effects + Registry.character(id).level_trait:
			if e.value > 0.0:
				plus += 1
		assert_int(plus).override_failure_message(id + " trait gives nothing").is_greater_equal(1)


func test_prop_colliders_are_small() -> void:
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/sprites/props/props.json"))
	for id in man.keys():
		var r := float(man[id].get("radius", 0.0))
		assert_float(r).override_failure_message(id + " collider too big").is_less_equal(0.65)
	assert_float(float(man["saguaro_big"]["radius"])).is_less(0.3)


func test_boss_reward_pulls_chests() -> void:
	var pm := PickupManager.new()
	pm.alive.resize(PickupManager.MAX)   # _ready sizes the pools; the manager never enters a tree here
	var c := Chest.new()
	pm.chests.append(c)
	pm.vacuum_all(true, true)
	assert_bool(c.pulled).is_true()
	c.free()
	pm.free()


func test_multishot_is_three_real_levels() -> void:
	# pass 47: a line of four real levels (Garry: one more upgrade), each a projectile
	var m: PassiveDef = Registry.passive("multishot")
	assert_int(m.max_level).is_equal(4)
	for lv in range(1, 5):
		assert_int(m.effects_for_level(lv).size()).override_failure_message("multishot level %d is empty" % lv).is_greater_equal(1)
