extends GdUnitTestSuite

## Pass 28: the cap ramps linearly to x2.5, the roster keeps arriving through the three stages, the harpooner is one at
## a time and carries a tether, the crab swarms, the map rolls a river and an oasis per run, bushes are walk-through.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_the_cap_starts_at_twenty_skeletons_and_ends_at_one_fifty() -> void:
	# pass 29: six times the start by the end of stage 3; pass 45: a curve; pass 46: the stages are 430 s. Pass 56
	# (re-pinned): Garry draws the curve himself in the Level Editor (2026-10-07: rushes and drops on purpose, 10 at the
	# start, 150 at the end), so this checks that the game plays the curve his map file holds
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	_check_curve(tl)
	# the skeletons count half a slot each: the opening's load is twice as many bodies
	assert_float(Registry.enemy("skeleton").cap_share).is_equal_approx(0.5, 0.0001)

func test_the_roster_keeps_arriving_through_every_stage() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	# pass 56 (re-pinned): Garry places the rows himself in the Level Editor, each with its own window (2026-10-07 stage
	# 2 ends on swarms after 11:32), so the rule checked is that every stage has rows of its own, not that the roster grows
	for k in range(tl.stages):
		var a: float = float(k) * float(tl.stage_length)
		var b: float = a + float(tl.stage_length)
		var any := false
		for t in range(int(a), int(b), 5):
			if not tl.roster_at(float(t)).is_empty():
				any = true
				break
		assert_bool(any).override_failure_message("stage %d has no roster row" % (k + 1)).is_true()
	var ids: Array = []
	for r in tl.roster_at(1289.0):
		ids.append(str(r.get("enemy", "")))
	assert_bool(ids.has("sand_crab")).is_false()
	# the armadillo comes on the roster or in a swarm (pass 54: Garry's placement in the Level Editor brings it only in
	# the 12:11 swarm)
	var swarms: Array = []
	for ev in tl.events:
		if str(ev.get("type", "")) == "swarm":
			swarms.append(str(ev.get("enemy", "")))
	assert_bool(ids.has("armadillo") or swarms.has("armadillo")).is_true()
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
	# 140, then 70 (pass 33.7), the rocketeer's since pass 33.8, and 50 for both since pass 45; its armour went in pass 45;
	# pass 48 (Garry): the Vulture Raider lost 30% (35) and the harpooner kept its 50
	assert_float(t.hp).is_equal_approx(50.0, 0.001)
	assert_float(Registry.enemy("rocketeer").hp).is_equal_approx(35.0, 0.001)
	assert_float(t.damage_reduction).is_equal_approx(0.0, 0.001)
	var tether: Dictionary = t.ranged.get("tether", {})
	# pass 33.10: a leash, not a flat slow: walking away runs at `away_speed` and towards is free, and the rope is as
	# long as the throw (it was a fixed 4 m that snapped the thrower to the hero), shortening to `min_length` at most
	assert_float(float(tether.get("away_speed", 1.0))).is_equal_approx(0.7, 0.001)
	assert_float(float(tether.get("seconds", 0.0))).is_greater_equal(4.0)
	assert_float(float(tether.get("min_length", 0.0))).is_greater(1.0)


func test_the_late_swarm_is_fodder() -> void:
	# pass 33.2: the crab left the rotation; its 14:00 swarm is forty fire ants (at 20:04 since pass 46 stretched the clock)
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var found := false
	# pass 84 (lane SPAWN, re-pinned): the swarm is a "once" row now (tools/migrate_timeline.py), an old map's event still counts
	var swarms: Array = tl.events.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "swarm")
	swarms.append_array(tl.roster.filter(func(r: Dictionary) -> bool: return str(r.get("pace", "")) == "once"))
	# pass 87 (lane SGAME, re-pinned): stage 3 is 13:00 now and its times were stretched (1204 s became 1654 s): the late
	# swarm is the fire-ant swarm of stage 3's window
	for ev in swarms:
		if tl.stage_at(float(ev.get("t", 0.0))) == 2 and str(ev.get("enemy", "")) == "fire_ant":
			found = true
			assert_str(str(ev.get("enemy", ""))).is_equal("fire_ant")
			# pass 53: the ants are 0.6 of a mummy now (Garry), so the late swarm sends 24 of them, not 40
			assert_int(int(ev.get("count", 0))).is_greater_equal(20)
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


## The cap curve as the map file holds it (pass 56: Garry draws it in the Level Editor, so the tests read his points
## instead of pinning numbers that change every time he saves).
func _map_cap_curve() -> Array:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	return (d.get("timeline_data", {}) as Dictionary).get("cap_curve", [])


## The game plays that curve: its points as loaded, linear between two points (checked half way), the first point's
## value at 0:00, flat after the last, all clamped by cap_max.
func _check_curve(tl: WaveTimeline) -> void:
	var src: Array = _map_cap_curve()
	assert_int(src.size()).is_greater_equal(2)
	assert_int(tl.cap_curve.size()).is_equal(src.size())
	assert_int(tl.cap_per_stage).is_equal(0)
	assert_int(tl.cap_at(0.0, 0)).is_equal(mini(int(float(src[0][1])), tl.cap_max))
	for k in range(src.size() - 1):
		var a: Array = src[k]
		var b: Array = src[k + 1]
		if float(b[0]) <= float(a[0]):
			continue
		var mid := (float(a[0]) + float(b[0])) * 0.5
		var want := mini(int(lerpf(float(a[1]), float(b[1]), 0.5)), tl.cap_max)
		assert_int(tl.cap_at(mid, mini(int(mid / float(tl.stage_length)), 2))).override_failure_message("at %.1f s" % mid).is_equal(want)
	var last: Array = src[src.size() - 1]
	assert_int(tl.cap_at(float(last[0]) + 600.0, 2)).is_equal(mini(int(float(last[1])), tl.cap_max))
