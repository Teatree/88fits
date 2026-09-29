extends GdUnitTestSuite

## Pass 24: the revive, homing missiles and their supporting items, ricochet in place of Trigger Happy, weapon tags,
## the new creatures and the second boss, fading roster weights, the softer Space Suit.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_space_suit_is_softer_early() -> void:
	var c: CharacterDef = Registry.character("astro")
	var armor := 0.0
	for e in c.trait_effects:
		if e.stat == "armor":
			armor = e.value
	assert_float(armor).is_less_equal(1.0)
	assert_float(c.level_heal).is_less_equal(0.08)


func test_trigger_happy_is_gone_and_ricochet_is_here() -> void:
	assert_bool(Registry.passives.has("trigger_happy")).is_false()
	var r: PassiveDef = Registry.passive("ricochet")
	assert_object(r).is_not_null()
	_start()
	Run.add_or_level_passive("ricochet")
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("ricochet", 0.0)).is_equal_approx(0.2, 0.001)


func test_homing_family_is_content() -> void:
	for id in ["rocket_pod", "hornet_nest"]:
		var w: WeaponDef = Registry.weapon(id)
		assert_object(w).override_failure_message("missing " + id).is_not_null()
		assert_str(w.behavior).is_equal("MissilePod")
		assert_bool(w.tags.has("homing")).is_true()
		assert_bool(w.params.has("missile")).is_true()
	assert_bool(Registry.weapons.has("missile_massacre")).is_true()
	assert_bool(Registry.weapons.has("killer_swarm")).is_true()
	for id in ["salvo", "swarm"]:
		assert_object(Registry.mutation(id)).override_failure_message("missing " + id).is_not_null()


func test_salvo_reaches_only_the_rocket_pod() -> void:
	_start()
	Run.add_weapon(Registry.weapon("rocket_pod"), 3)
	Run.add_weapon(Registry.weapon("peashooter"), 3)
	var pod := Run.weapon_instance("rocket_pod")
	var pea := Run.weapon_instance("peashooter")
	var pod_before := pod.stat_int("amount", 0)
	var pea_before := pea.stat_int("amount", 0)
	Run.add_mutation("salvo")
	assert_int(pod.stat_int("amount", 0)).is_equal(pod_before + 3)
	assert_int(pea.stat_int("amount", 0)).is_equal(pea_before)
	# the hero's own amount stays untouched: a weapon-targeted effect never leaks through the player sheet
	assert_float(Run.player_sheet.get_stat("amount", 0.0)).is_equal_approx(0.0, 0.001)


func test_new_creatures_and_the_second_boss() -> void:
	var toad: EnemyDef = Registry.enemy("horned_toad")
	assert_object(toad).is_not_null()
	assert_float(toad.armor).is_greater(0.0)
	# pass 28: the Sand Crab took the spider's place, a fast pack creature
	var crab: EnemyDef = Registry.enemy("sand_crab")
	assert_object(crab).is_not_null()
	assert_str(crab.brain).is_equal("kamikaze")   # pass 30: it carries mines now
	assert_int(crab.pack_size).is_equal(1)   # pass 32: mine crabs arrive one at a time
	assert_float(crab.speed).is_greater_equal(3.0)   # pass 30: slower, because it explodes
	var shaman: EnemyDef = Registry.enemy("dust_shaman")
	assert_str(shaman.brain).is_equal("support")
	assert_bool(shaman.support.has("heal")).is_true()
	assert_object(Registry.enemy("jackalope")).is_not_null()
	var gila: EnemyDef = Registry.enemy("gila_grande")
	assert_str(gila.archetype).is_equal("boss")
	assert_int(int(gila.drops.get("chests", 1))).is_greater_equal(2)
	assert_int(int(gila.drops.get("coins", 12))).is_greater(12)
	var names: Array = []
	for atk in gila.boss.get("attacks", []):
		names.append(str(atk.get("name", "")))
	assert_bool(names.has("burrow")).is_true()
	assert_bool(names.has("spit_volley")).is_true()


func test_stage_two_brings_new_creatures_and_the_second_boss() -> void:
	var m: MapDef = Registry.map("red_canyon")
	var tl: WaveTimeline = m.timeline
	var ids_at_100: Array = []
	for r in tl.roster_at(100.0):
		ids_at_100.append(str(r["enemy"]))
	var ids_at_400: Array = []
	for r in tl.roster_at(400.0):
		ids_at_400.append(str(r["enemy"]))
	var ids_late: Array = []
	for r in tl.roster_at(899.0):
		ids_late.append(str(r["enemy"]))
	# pass 28: arrivals are spread over all three stages (the jackalope in stage 2, the shaman only in stage 3)
	assert_bool(ids_at_100.has("jackalope")).is_false()
	assert_bool(ids_at_400.has("horned_toad")).is_true()
	# pass 33.2: the crab and the jackalope are out of the rotation, the armadillo arrives half way through stage 1
	assert_bool(ids_at_400.has("armadillo")).is_true()
	assert_bool(ids_at_400.has("sand_crab")).is_false()
	assert_bool(ids_at_400.has("dust_shaman")).is_false()
	assert_bool(ids_late.has("jackalope")).is_false()
	assert_bool(ids_late.has("dust_shaman")).is_true()
	var bosses: Array = []
	for ev in tl.events:
		if str(ev.get("type", "")) == "boss":
			bosses.append(str(ev.get("enemy", "")))
	assert_bool(bosses.has("gila_grande")).is_true()
	assert_bool(bosses.has("tumbleweed_king")).is_true()
	# goblins thin out: their weight at the end of stage 2 is a third of the start
	var goblin: Dictionary = tl.roster[0]
	assert_float(float(goblin.get("weight_late", 10.0))).is_less(float(goblin.get("weight", 10.0)))


func test_revive_returns_half_health_once() -> void:
	_start()
	assert_int(Run.revives_used).is_equal(0)
	var chances: int = 1 + Run.player_sheet.get_int("revives", 0) - Run.revives_used
	assert_int(chances).is_greater_equal(1)
	assert_int(ReviveScreen.GOLD_COST).is_greater(0)
	assert_float(ReviveScreen.SECONDS).is_greater(3.0)


func test_tommy_gun_spread_is_tighter() -> void:
	assert_float(float(Registry.weapon("tommy_gun").base["spread_deg"])).is_less_equal(8.0)
	assert_bool(ResourceLoader.exists("res://art/props/tommy_gun.glb")).is_true()
