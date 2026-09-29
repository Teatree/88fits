extends GdUnitTestSuite

## Pass 29: the centipede a true eight-direction spitter, the rocketeer and its rocket, creatures that grow with the hero,
## the nuke, the harpooner's reach and lead, the turret stances, the wadeable oasis.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_the_idol_spits_and_turns() -> void:
	var c: EnemyDef = Registry.enemy("sun_prophet")
	var names: Array = []
	for atk in c.boss.get("attacks", []):
		names.append(str(atk.get("name", "")))
	assert_bool(names.has("spit_volley")).is_true()
	assert_bool(names.has("erupt")).is_true()
	assert_int(names.count("spit_volley")).is_greater_equal(2)


func test_the_rocketeer_is_artillery_with_a_live_limit() -> void:
	var r: EnemyDef = Registry.enemy("rocketeer")
	assert_object(r).is_not_null()
	assert_str(r.brain).is_equal("artillery")
	assert_int(r.max_alive).is_equal(1)   # pass 30: only ever one alive
	assert_float(float(r.artillery.get("stand_off", 0.0))).is_greater_equal(20.0)
	var ms: Dictionary = r.artillery.get("missile", {})
	assert_float(float(ms.get("speed", 99.0))).is_less_equal(5.0)
	# a special since pass 33.4: the specials' own clock brings him, one at a time
	var ids: Array = []
	for row in Registry.map("red_canyon").timeline.specials.get("pool", []):
		ids.append(str(row.get("enemy", "")))
	assert_bool(ids.has("rocketeer")).is_true()
	assert_bool(Registry.enemies.has("goblin_rocketeer")).is_false()


func test_creatures_grow_with_the_hero() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_float(tl.level_hp_per_level).is_greater(0.0)
	assert_float(tl.level_damage_per_level).is_greater(0.0)
	assert_float(tl.stage_mult(2)).is_greater(3.0)


func test_the_nuke_is_a_pickup_as_rare_as_the_shield() -> void:
	var n: PickupDef = Registry.pickup("nuke")
	assert_object(n).is_not_null()
	assert_str(n.effect_kind).is_equal("nuke")
	assert_float(float(n.params.get("radius", 0.0))).is_greater_equal(10.0)
	var pk: Dictionary = Registry.map("red_canyon").timeline.pickups
	var w_nuke := 0.0
	var w_shield := 0.0
	for row in pk.get("roster", []):
		if str(row.get("id", "")) == "nuke":
			w_nuke = float(row.get("weight", 0.0))
		if str(row.get("id", "")) == "shield":
			w_shield = float(row.get("weight", 0.0))
	assert_float(w_nuke).is_equal(w_shield)


func test_the_harpooner_throws_far_and_leads() -> void:
	var t: EnemyDef = Registry.enemy("harpoon_troglodyte")
	assert_float(float(t.ranged.get("range", 0.0))).is_greater_equal(16.0)
	assert_float(float(t.ranged.get("keep_distance", 0.0))).is_greater_equal(10.0)
	assert_bool(bool(t.ranged.get("lead", false))).is_true()


func test_the_turret_has_two_stances_and_no_walking() -> void:
	assert_bool(Registry.mutations.has("walking_buddy")).is_false()
	assert_bool(Registry.mutations.has("hornet_twister")).is_false()
	var styles: Array = []
	for m: MutationDef in Registry.mutations_of("turret_buddy"):
		var tp = m.params.get("turret")
		if tp is Dictionary:
			styles.append(str(tp.get("style", "")))
	assert_bool(styles.has("tower") and styles.has("bunker")).is_true()
	assert_int(Registry.mutations_of("turret_buddy").size()).is_equal(4)


func test_the_oasis_is_wadeable() -> void:
	var scene: PackedScene = Registry.map("red_canyon").scene
	Run.forced_map_seed = 5
	_start()
	var a: MapBase = auto_free(scene.instantiate())
	add_child(a)
	var lc: Vector2 = a.call("lake_center")
	var lr: float = a.call("lake_radius")
	# the pool is knee-deep: the floor sits under the shore by less than a metre, and nothing blocks the way in
	var shore := a.height_at(lc.x + lr + 2.0, lc.y)
	var middle := a.height_at(lc.x, lc.y)
	assert_float(shore - middle).is_between(0.2, 1.0)
	for o: Vector3 in a.obstacles:
		assert_bool(Vector2(o.x, o.y).distance_to(lc) > lr * 0.5 or o.z < lr * 0.5).override_failure_message("a collider in the water").is_true()
	assert_bool(bool(a.call("in_water", Vector3(lc.x, 0, lc.y)))).is_true()
	Run.forced_map_seed = 0
