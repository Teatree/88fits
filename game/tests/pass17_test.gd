extends GdUnitTestSuite


func test_desert_roster_has_seven_creatures_and_the_elite() -> void:
	var m: MapDef = Registry.map("red_canyon")
	var ids: Array = []
	for r in m.timeline.roster:
		ids.append(str(r["enemy"]))
	# the sand lizard is hidden since pass 34 (its row went to the runts, ants and armadillos); pass 45: the skeletons
	# took the goblins' two rows; pass 54: on the roster or in a swarm (Garry's placement in the Level Editor brings the
	# fire ants in the swarms only)
	for ev in m.timeline.events:
		if str(ev.get("type", "")) == "swarm":
			ids.append(str(ev.get("enemy", "")))
	# pass 56 (re-pinned): Garry places the creatures himself in the Level Editor (2026-10-07 he took the mummy, the toad,
	# the shaman and the armadillo off the roster), so this checks what the map brings, not a fixed cast: a varied roster
	# of creatures the game knows
	var distinct: Dictionary = {}
	for id in ids:
		if id == "":
			continue
		distinct[id] = true
		assert_object(Registry.enemy(id)).override_failure_message("unknown creature " + id).is_not_null()
	assert_int(distinct.size()).is_greater_equal(6)
	var elite_ts: Array = []
	for ev in m.timeline.events:
		if str(ev.get("type", "")) == "elite_boss":
			elite_ts.append(float(ev["t"]))
	assert_int(elite_ts.size()).is_greater_equal(3)
	assert_float(elite_ts[0]).is_equal(215.0)  # pass 46: the run stretched by 430/300
	assert_str(Registry.enemy("dune_scorpion").archetype).is_equal("elite")
	assert_float(float(Registry.enemy("dune_scorpion").drops.get("chest", 0.0))).is_equal(1.0)


func test_stages_get_harder() -> void:
	var t: WaveTimeline = Registry.map("red_canyon").timeline
	assert_float(t.stage_mult(1)).is_greater(1.6)
	assert_float(t.stage_mult(2)).is_greater(t.stage_mult(1) * 1.3)
	# pass 83 re-pin: the cap's shape is Garry's (his curve starts high and steps down since 2026-10-16): a cap all through
	assert_int(t.cap_at(300.0, 1)).is_greater(0)
	assert_float(t.speed_mult(2)).is_greater(t.speed_mult(1))
	assert_float(t.speed_mult(0)).is_equal(1.0)


func test_chest_roll_is_dry_until_taken() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	var before := Run.weapon_instance("peashooter").level
	# pass 47: a chest may also hold a new passive item; with every passive banished the peashooter's level is the roll
	for p: PassiveDef in Registry.passives.values():
		Run.banished.append(p.id)
	var r := Run.chest_roll()
	assert_str(str(r["type"])).is_equal("weapon")
	assert_int(Run.weapon_instance("peashooter").level).is_equal(before)
	assert_int(Run.chests_opened).is_equal(0)
	var line := Run.chest_take(r)
	assert_int(Run.weapon_instance("peashooter").level).is_equal(before + 1)
	assert_int(Run.chests_opened).is_equal(1)
	assert_str(line).contains("Lv")
	# pass 47: a chest is never sold; letting it go takes one of the stage's skips and pays nothing
	var gold := Run.run_gold
	assert_str(Run.chest_skip(Run.chest_roll())).is_not_empty()
	assert_int(Run.run_gold).is_equal(gold)
	assert_int(Run.chests_opened).is_equal(2)


func test_chest_roll_prefers_a_ready_evolution() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var w: WeaponDef = Registry.weapon("peashooter")
	var inst := Run.add_weapon(w, w.max_level)
	# pass 26: the path is the key; pass 48: all of it, the three mutations over three stages (Pea Hose is hidden, Big Peas
	# took its slot)
	Run.add_mutation("toxic_peas")
	Run.stage = 1
	Run.add_mutation("big_peas")
	Run.stage = 2
	Run.add_mutation("bouncing_peas")
	Run.stage = 0
	Run.rebuild_sheets()
	var r := Run.chest_roll()
	assert_str(str(r["type"])).is_equal("evolution")
	assert_str(str(r["id"])).is_equal(w.evolves_into)
	assert_bool(Run.has_weapon(w.evolves_into)).is_false()
	Run.chest_take(r)
	assert_bool(Run.has_weapon(w.evolves_into)).is_true()
	assert_object(inst).is_not_null()


func test_fire_content_and_both_elements_in_one_run() -> void:
	for id in ["flare_gun", "molotov", "branding_iron"]:
		var w: WeaponDef = Registry.weapon(id)
		assert_bool(w != null).override_failure_message("missing " + id).is_true()
		assert_float(float(w.base.get("fire_damage", 0.0))).is_greater(0.0)
		assert_str(WeaponInstance.new(w, 1).element()).is_equal("fire")
	assert_str(Registry.passive("kindling").element).is_equal("fire")
	assert_str(WeaponInstance.new(Registry.weapon("poison_dart"), 1).element()).is_equal("poison")
	assert_str(WeaponInstance.new(Registry.weapon("boomstick"), 1).element()).is_equal("")
	# fire is hotter per tick and shorter, and worth less in total than poison
	var f: WeaponDef = Registry.weapon("flare_gun")
	var p: WeaponDef = Registry.weapon("poison_dart")
	var fire_total: float = float(f.base["fire_damage"]) * floor(float(f.base["fire_duration"]) / 0.6)
	var poison_total: float = float(p.base["poison_damage"]) * floor(float(p.base["poison_duration"]) / 2.0)
	assert_float(float(f.base["fire_damage"]) / 0.6).is_greater(float(p.base["poison_damage"]) / 2.0)
	assert_float(fire_total).is_less(poison_total)
	# pass 36: the one-element rule is gone: a poison build is still offered fire, and the other way round
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(p, 1)
	var seen := {}
	for k in range(200):
		for card in CardPool.level_up_offer(3):
			seen[(card["def"] as ContentDef).id] = true
	assert_bool(seen.has("molotov") or seen.has("kindling")).override_failure_message("no fire offered to a poison build").is_true()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("molotov"), 1)
	Run.add_weapon(Registry.weapon("skull_rain"), 1)
	assert_bool(Run.has_weapon("molotov") and Run.has_weapon("skull_rain")).is_true()
	assert_str(Run.weapon_instance("molotov").element()).is_equal("fire")
	assert_str(Run.weapon_instance("skull_rain").element()).is_equal("poison")


func test_fire_spreads_but_never_back_to_the_host() -> void:
	var em := EnemyManager.new()
	em.height_fn = Callable()
	em._ready()
	em.register_type(Registry.enemy("goblin"))
	var a := em.spawn("goblin", Vector3(0, 0, 0))
	var b := em.spawn("goblin", Vector3(0.6, 0, 0))
	var far := em.spawn("goblin", Vector3(8, 0, 0))
	em._rebuild_grid()
	em.ignite(a, "flare_gun", 4.0, 1.8, 1.0)
	assert_bool(em.is_burning(a)).is_true()
	assert_bool(em.is_burning(b)).is_false()
	# the first tick: damage, and with a 100% spread chance the touching neighbour catches it
	em._tick_fire(a, EnemyManager.FIRE_TICK + 0.01)
	assert_bool(em.is_burning(b)).is_true()
	assert_bool(em.is_burning(far)).is_false()
	var child: Dictionary = em.fire_src[b]["flare_gun"]
	assert_int(int(child["from"])).is_equal(a)
	assert_float(float(child["spread"])).is_equal_approx(EnemyManager.CHILD_SPREAD, 0.001)
	# the host's fire burns out; the child, even at 100%, never lights its parent again
	em.fire_src[a].clear()
	child["spread"] = 1.0
	em._tick_fire(b, EnemyManager.FIRE_TICK + 0.01)
	assert_bool(em.is_burning(a)).is_false()
	em.free()
