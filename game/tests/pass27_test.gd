extends GdUnitTestSuite

## Pass 27: path slots (all three on one table at set times), the centipedes, tracers, calmer variant tints, the
## (the homestead farm this pass added was replaced by the Mirror in pass 32).


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_path_slots_come_due_at_the_stage_times() -> void:
	_start()
	var times: Array = Run.map.timeline.path_times_at(0)
	# as many slots as stage 1's weapon cap was (four) and a spare; pass 47 opened all six weapon slots from the start, and
	# whether stage 1 gets more path slots for them is the map's to say (red_canyon's path_times)
	assert_int(times.size()).is_greater_equal(5)
	assert_bool(Run.path_due(float(times[0]) - 1.0)).is_false()
	assert_bool(Run.path_due(float(times[0]) + 0.1)).is_true()
	assert_bool(Run.path_due(float(times[0]) + 0.2)).override_failure_message("a slot fired twice").is_false()
	assert_bool(Run.path_due(float(times[1]) + 0.1)).is_true()
	assert_int(Run.path_slot).is_equal(2)
	# stage 2 has its own list and starts over
	Run.stage = 1
	Run.path_slot = 0
	var t2: Array = Run.map.timeline.path_times_at(1)
	assert_int(t2.size()).is_greater_equal(6)
	assert_bool(Run.path_due(float(t2[0]) + 0.1)).is_true()


func test_the_path_table_holds_the_whole_path() -> void:
	_start("astro")
	Run.add_weapon(Registry.weapon("hornet_nest"), 1)
	Run.add_weapon(Registry.weapon("orbit_saws"), 4)
	# pass 54: the weapon is drawn at random among the open paths (it was the highest level); either may come
	var w := Run.next_path_weapon()
	assert_bool(w.def.id == "orbit_saws" or w.def.id == "hornet_nest").is_true()
	w = Run.weapon_instance("orbit_saws")
	var offer := CardPool.path_offer(w)
	# three path picks and Astro's own Gyro Saws after them
	assert_int(offer.size()).is_equal(4)
	for k in range(3):
		assert_str(str(offer[k]["type"])).is_equal("mutation")
		assert_bool((offer[k]["def"] as MutationDef).is_hero()).is_false()
	assert_bool((offer[3]["def"] as MutationDef).is_hero()).is_true()
	CardPool.apply(offer[1])
	assert_int(Run.mutations_held("orbit_saws").size()).is_equal(1)
	# the saws are spent for the stage: the hive is next
	assert_str(Run.next_path_weapon().def.id).is_equal("hornet_nest")
	CardPool.apply(CardPool.path_offer(Run.next_path_weapon())[1])   # the volume pick: no element commits the run
	assert_object(Run.next_path_weapon()).is_null()
	# next stage: the two path picks left and Astro's own option, which was not taken
	Run.stage = 1
	var o2 := CardPool.path_offer(Run.weapon_instance("orbit_saws"))
	assert_int(o2.size()).is_equal(3)


func test_tracers_and_trails_are_data() -> void:
	assert_bool(bool(Registry.weapon("tommy_gun").params.get("tracer", false))).is_true()
	assert_bool(bool(Registry.weapon("chicago_typewriter").params.get("tracer", false))).is_true()


func test_variant_tints_stay_off_the_sand() -> void:
	for def: EnemyDef in Registry.enemies.values():
		var v: Dictionary = def.variance
		if v.is_empty():
			continue
		assert_float(float(v.get("tint_strength", 0.0))).override_failure_message(def.id + " tint too strong").is_less_equal(0.3)
		var sp: Dictionary = v.get("special", {})
		if sp.has("tint"):
			var c := Color(str(sp["tint"]))
			# a special is dark and saturated, never a sand yellow
			assert_float(c.v).override_failure_message(def.id + " special tint too light").is_less(0.6)
			assert_float(c.s).override_failure_message(def.id + " special tint too grey").is_greater(0.4)


func test_the_dwarf_is_fatter_and_the_centipede_is_the_elite() -> void:
	var d: EnemyDef = Registry.enemy("buckshot_dwarf")
	assert_float(d.size).is_greater_equal(1.3)
	var m: MapDef = Registry.map("red_canyon")
	for ev in m.timeline.events:
		if str(ev.get("type", "")) == "elite_boss":
			assert_bool((ev.get("enemy") as Array).has("sun_prophet")).is_true()
			assert_bool((ev.get("enemy") as Array).has("mirage_djinn")).is_false()
