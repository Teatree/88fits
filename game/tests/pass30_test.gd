extends GdUnitTestSuite

## Pass 30: pellets and spikes instead of spit, the mine crab, the boss's mutation chest, the Big Mouth laser, longer
## power-ups, blasts that hurt the crowd.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_ranged_creatures_carry_their_own_shot() -> void:
	assert_str(str(Registry.enemy("buckshot_dwarf").ranged.get("shot", ""))).is_equal("pellet")
	var cent: EnemyDef = Registry.enemy("sun_prophet")
	var volley: Dictionary = {}
	for atk in cent.boss.get("attacks", []):
		if str(atk.get("name", "")) == "spit_volley":
			volley = atk
	assert_bool(bool(volley.get("straight", false))).override_failure_message("the volley still arcs").is_true()
	assert_str(str(volley.get("shot", ""))).is_equal("shard")
	assert_float(float(volley.get("speed", 0.0))).is_greater_equal(12.0)


func test_the_crab_is_a_walking_mine() -> void:
	var c: EnemyDef = Registry.enemy("sand_crab")
	assert_str(c.brain).is_equal("kamikaze")
	assert_float(c.speed).is_less(4.0)
	assert_float(c.hp).is_less_equal(8.0)
	assert_float(float(c.kamikaze.get("damage", 0.0))).is_greater_equal(20.0)
	assert_float(float(c.kamikaze.get("radius", 0.0))).is_greater(2.0)
	# it goes off when it dies too, and that blast throws the crowd
	assert_float(float(c.death_burst.get("damage", 0.0))).is_greater(0.0)
	assert_float(float(c.death_burst.get("knockback", 0.0))).is_greater(0.0)


func test_the_boss_chest_holds_a_mutation() -> void:
	_start()
	Run.add_weapon(Registry.weapon("hornet_nest"), 3)
	var r := Run.chest_roll(true)
	assert_str(str(r.get("type", ""))).is_equal("mutation")
	var m: MutationDef = r.get("def")
	assert_str(m.weapon).is_equal("hornet_nest")
	# taking it fits the path even though the stage's pick is spent
	var held := Run.mutations_held("hornet_nest").size()
	Run.chest_take(r)
	assert_int(Run.mutations_held("hornet_nest").size()).is_equal(held + 1)


func test_the_laser_is_a_weapon_with_a_path_and_an_evolution() -> void:
	var w: WeaponDef = Registry.weapon("big_mouth")
	assert_object(w).is_not_null()
	assert_str(w.behavior).is_equal("LaserBeam")
	assert_float(float(w.base.get("duration", 0.0))).is_greater_equal(2.0)
	assert_int(int(w.base.get("pierce", 0))).is_greater_equal(10)
	assert_str(w.evolves_into).is_equal("loudmouth")
	assert_object(Registry.weapon("loudmouth")).is_not_null()
	var kinds: Array = []
	var params: Array = []
	for m: MutationDef in Registry.mutations_of("big_mouth"):
		kinds.append(m.mutation_kind)
		params.append(m.params.get("beam", {}))
	assert_bool(kinds == ["element", "volume", "motion"]).override_failure_message(str(kinds)).is_true()
	# burn, a shove on the first touch, and a pan
	assert_int(Registry.mutation("mouth_burn").weapon_effects().size()).is_greater(0)
	assert_bool(bool((Registry.mutation("mouth_knock").params.get("beam", {}) as Dictionary).get("first_knock", false))).is_true()
	assert_float(float((Registry.mutation("mouth_arch").params.get("beam", {}) as Dictionary).get("arch_deg", 0.0))).is_greater_equal(10.0)


func test_power_ups_last_twice_as_long() -> void:
	# pass 30: every power-up waits twice as long as it did (the heart was the short one at 11 s, the rest 20 s)
	for id in Registry.pickups.keys():
		var p: PickupDef = Registry.pickup(id)
		assert_float(p.lifetime).override_failure_message(id + " lifetime " + str(p.lifetime)).is_greater_equal(22.0)
	for id in ["shield", "rage", "sprint", "magnet_pulse", "nuke"]:
		assert_float(Registry.pickup(id).lifetime).is_greater_equal(40.0)
