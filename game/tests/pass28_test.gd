extends GdUnitTestSuite

## Pass 28: the cap ramps linearly to x2.5, the roster keeps arriving through the three stages, the harpooner is one at
## a time and carries a tether, the crab swarms, the map rolls a river and an oasis per run, bushes are walk-through.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_the_cap_ramps_to_six_times() -> void:
	# pass 29: six times the start by the end of stage 3, still linear with the clock
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var start := tl.cap_at(0.0, 0)
	var end := tl.cap_at(900.0, 2)
	var mid := tl.cap_at(450.0, 1)
	assert_int(start).is_equal(25)
	assert_float(float(end) / float(start)).is_between(5.8, 6.2)
	# linear: the middle sits halfway
	assert_int(mid).is_between(int(float(start + end) * 0.5) - 1, int(float(start + end) * 0.5) + 1)
	assert_int(tl.cap_per_stage).is_equal(0)


func test_the_roster_keeps_arriving_through_every_stage() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var n1 := tl.roster_at(299.0).size()
	var n2 := tl.roster_at(599.0).size()
	var n3 := tl.roster_at(899.0).size()
	assert_int(n2).is_greater(n1)
	assert_int(n3).is_greater(n2)
	var ids: Array = []
	for r in tl.roster_at(899.0):
		ids.append(str(r.get("enemy", "")))
	assert_bool(ids.has("sand_crab")).is_false()
	assert_bool(ids.has("armadillo")).is_true()
	# the harpooner is a special since pass 33.4: it comes on the specials' clock, from stage 2
	var pool: Array = []
	for row in tl.specials.get("pool", []):
		pool.append(str(row.get("enemy", "")))
	assert_bool(pool.has("harpoon_troglodyte")).is_true()
	assert_bool(ids.has("trapdoor_spider")).is_false()
	assert_bool(Registry.enemies.has("trapdoor_spider")).is_false()


func test_the_harpooner_is_one_at_a_time_with_a_tether() -> void:
	var t: EnemyDef = Registry.enemy("harpoon_troglodyte")
	assert_int(t.max_alive).is_equal(1)
	assert_str(t.brain).is_equal("kite")
	# 140, then 70 (pass 33.7), and since pass 33.8 the rocketeer's health; its armour keeps it the harder of the two
	assert_float(t.hp).is_equal_approx(Registry.enemy("rocketeer").hp, 0.001)
	assert_float(t.damage_reduction).is_greater(Registry.enemy("rocketeer").damage_reduction)
	var tether: Dictionary = t.ranged.get("tether", {})
	# pass 33.10: a leash, not a flat slow: walking away runs at `away_speed` and towards is free, and the rope is as
	# long as the throw (it was a fixed 4 m that snapped the thrower to the hero), shortening to `min_length` at most
	assert_float(float(tether.get("away_speed", 1.0))).is_equal_approx(0.7, 0.001)
	assert_float(float(tether.get("seconds", 0.0))).is_greater_equal(4.0)
	assert_float(float(tether.get("min_length", 0.0))).is_greater(1.0)


func test_the_late_swarm_is_fodder() -> void:
	# pass 33.2: the crab left the rotation; its 14:00 swarm is forty fire ants
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var found := false
	for ev in tl.events:
		if str(ev.get("type", "")) == "swarm" and float(ev.get("t", 0.0)) == 840.0:
			found = true
			assert_str(str(ev.get("enemy", ""))).is_equal("fire_ant")
			assert_int(int(ev.get("count", 0))).is_greater_equal(36)
	assert_bool(found).is_true()


func test_the_map_rolls_a_river_and_an_oasis() -> void:
	var scene: PackedScene = Registry.map("red_canyon").scene
	Run.forced_map_seed = 5
	_start()
	var a: MapBase = auto_free(scene.instantiate())
	add_child(a)
	assert_int((a.call("river_points") as Array).size()).is_greater_equal(5)
	assert_float(float(a.call("lake_radius"))).is_between(5.0, 8.0)
	var la: Vector2 = a.call("lake_center")
	# the lake stays off the flats and inside the wall
	assert_float((la - Vector2(a.flats_center.x, a.flats_center.z)).length()).is_greater(a.flats_radius + 8.0)
	assert_float(la.length()).is_less(a.arena_radius - 10.0)
	# another seed, another desert
	Run.forced_map_seed = 6
	_start()
	var b: MapBase = auto_free(scene.instantiate())
	add_child(b)
	var lb: Vector2 = b.call("lake_center")
	assert_bool(la.distance_to(lb) > 0.5 or (a.call("river_points") as Array)[1] != (b.call("river_points") as Array)[1]).is_true()
	Run.forced_map_seed = 0


func test_bushes_have_no_collider() -> void:
	var pf := PropField.new()
	pf.setup()
	assert_float(pf.radius_of("desert_bush")).is_equal(0.0)
	assert_float(pf.radius_of("creosote_bush")).is_equal(0.0)
	assert_float(pf.radius_of("dead_shrub")).is_equal(0.0)
	assert_bool(pf.has("fan_palm") and pf.has("ocotillo") and pf.has("yucca")).is_true()
	pf.free()
