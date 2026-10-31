## Pass 116, lane MAP (Garry: "Change the barrels so that there are 3 kinds now. One of them produces only power ups.
## This 3rd barrel is about 60% of the amount of the EXP+Coins. Make it so the other barrels don't give any power-up
## anymore ... change them from scratch" to look like his "Barrel Variant Terrain Comparison Board"; and "every time I
## play any of the stages on any of the maps, it's always randomly generated"): the three kinds (BarrelSpawns
## CONTENT_DEFAULTS, the map's `barrels` block, pass 112's brown / black read as exp / coins), the painted billboards
## (BarrelField.SPRITES, the structures' stencil), and every stage run rolling its own layout (Run.map_seed from the run's
## own seed, fresh each run since lane REPLAY's begin_run_seed fix).
extends GdUnitTestSuite


func after_test() -> void:
	Run.forced_map_seed = 0
	Run.forced_run_seed = 0
	Run.end()


func test_three_kinds_and_only_the_powerup_barrel_throws_one() -> void:
	assert_array(BarrelSpawns.TYPES).is_equal(["exp", "coins", "powerup"])
	var e := BarrelSpawns.contents_of({}, "exp")
	var c := BarrelSpawns.contents_of({}, "coins")
	var p := BarrelSpawns.contents_of({}, "powerup")
	assert_float(float(e["powerup_chance"])).is_equal(0.0)
	assert_float(float(c["powerup_chance"])).is_equal(0.0)
	assert_float(float(p["powerup_chance"])).is_equal(1.0)
	assert_int(int(p["gems_small"]) + int(p["gems_medium"])).is_equal(0)
	assert_object(p["coins"]).is_equal(Vector2i(0, 0))
	assert_int(e["gems_small"]).is_equal(8)
	assert_object(c["coins"]).is_equal(Vector2i(1, 5))
	# the power-up barrel about 60% as common as the EXP + Coins one
	assert_float(float(p["weight"]) / float(c["weight"])).is_equal_approx(0.6, 0.001)
	# a block asking an EXP or EXP + Coins barrel for a power-up is not obeyed
	var asks := {"exp": {"powerup_chance": 1.0}, "coins": {"powerup_chance": 1.0}}
	assert_float(float(BarrelSpawns.contents_of(asks, 0)["powerup_chance"])).is_equal(0.0)
	assert_float(float(BarrelSpawns.contents_of(asks, 1)["powerup_chance"])).is_equal(0.0)


func test_pass_112_keys_migrate_on_read() -> void:
	var old := {"brown": {"gems_small": 3, "powerup_chance": 0.5}, "black": {"coins": [2, 2], "powerup_chance": 0.3,
		"powerups": [{"id": "nuke", "weight": 1}]}}
	assert_int(BarrelSpawns.contents_of(old, "exp")["gems_small"]).is_equal(3)
	assert_float(float(BarrelSpawns.contents_of(old, "exp")["powerup_chance"])).is_equal(0.0)
	assert_object(BarrelSpawns.contents_of(old, true)["coins"]).is_equal(Vector2i(2, 2))
	assert_float(float(BarrelSpawns.contents_of(old, "black")["powerup_chance"])).is_equal(0.0)
	assert_array(BarrelSpawns.contents_of(old, "powerup")["powerups"]).is_equal([{"id": "nuke", "weight": 1.0}])
	assert_bool(BarrelSpawns.respawn_of({"respawn": {"enabled": true, "black_chance": 0.5}}).has("black_chance")).is_false()


func test_the_map_file_names_the_three_kinds() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var b: Dictionary = raw["timeline_data"]["barrels"]
	for k in ["exp", "coins", "powerup"]:
		assert_bool(b.has(k)).override_failure_message(k).is_true()
	assert_bool(b.has("brown") or b.has("black")).is_false()
	assert_bool((b["respawn"] as Dictionary).has("black_chance")).is_false()


func test_kinds_are_drawn_by_their_weights() -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = 116
	var n := [0, 0, 0]
	var total := 20000
	for k in total:
		n[BarrelSpawns.pick_kind({}, dice)] += 1
	assert_float(float(n[0]) / total).is_equal_approx(0.648, 0.02)
	assert_float(float(n[1]) / total).is_equal_approx(0.22, 0.02)
	assert_float(float(n[2]) / total).is_equal_approx(0.132, 0.02)
	# a kind weighing 0 never comes
	n = [0, 0, 0]
	for k in 2000:
		n[BarrelSpawns.pick_kind({"powerup": {"weight": 0}}, dice)] += 1
	assert_int(n[2]).is_equal(0)


func _flat_field(seed_v: int) -> BarrelField:
	Run.map_seed = seed_v
	var ms := GDScript.new()
	ms.source_code = "extends MapBase\nvar flats_radius := 16.0\n"
	ms.reload()
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(ms)
	add_child(map)
	var game: Node = auto_free(Node.new())
	add_child(game)
	var field: BarrelField = auto_free(BarrelField.new())
	add_child(field)
	field.setup(game, map)
	return field


func test_the_start_barrels_are_paintings_of_each_kind_on_the_structures_stencil() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var seen := [0, 0, 0]
	for sd in [3, 11, 87, 116]:
		var f := _flat_field(sd)
		assert_int(f.pos.size()).is_equal(BarrelField.COUNT)
		for k in f.pos.size():
			seen[f.light[k]] += 1
		for t in 3:
			var mm: MultiMesh = f._mm_of(t)
			assert_object(mm).is_not_null()
			assert_object(mm.mesh).is_instanceof(QuadMesh)
		# the picture stands on the barrel's spot
		assert_bool(f.instance_transform(0).origin.is_equal_approx(f.pos[0])).is_true()
		for c in f.get_children():
			if c is MultiMeshInstance3D:
				assert_bool(SceneryStencil.is_marked((c as MultiMeshInstance3D).material_override, SceneryStencil.STRUCTURE)).is_true()
	for t in 3:
		assert_int(seen[t]).is_greater(0)
	# about 0.6 power-up barrels to every EXP + Coins one (the two always-coins spots aside)
	var ratio := float(seen[2]) / float(seen[1] - 2 * 4)
	assert_float(ratio).is_between(0.25, 1.2)
	for path in BarrelField.SPRITES:
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()


func _layout(ms: int) -> Array:
	var m: Node3D = (Registry.map("red_canyon").scene as PackedScene).instantiate()
	m.set("run_seed", ms)
	(m.get("_rng") as RandomNumberGenerator).seed = ms
	var nz: FastNoiseLite = m.get("_noise")
	nz.seed = ms
	nz.frequency = 0.045
	nz.fractal_octaves = 3
	m.set("flats_center", Vector3(0, 0, 8))
	m.call("_roll_layout")
	var out: Array = [m.call("river_points"), m.call("lakes")]
	m.free()
	return out


func test_every_stage_run_rolls_its_own_map() -> void:
	# two Nightfall starts one after the other in the same app session, as the Stages menu makes them
	var seeds: Array = []
	var layouts: Array = []
	for k in 2:
		Run.end()
		Run.begin_run_seed()
		Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
		Run.start_stage(1)
		assert_int(Run.stage).is_equal(1)
		seeds.append(Run.map_seed)
		layouts.append(_layout(Run.map_seed))
	print("MAP116: two Nightfall starts: map seeds %s; river %s vs %s" % [seeds, str(layouts[0][0]).left(80), str(layouts[1][0]).left(80)])
	assert_int(int(seeds[0])).is_not_equal(int(seeds[1]))
	assert_str(str(layouts[0][0])).is_not_equal(str(layouts[1][0]))
	# a replay forces the run's seed: the same map again
	Run.end()
	Run.forced_run_seed = 4242
	Run.begin_run_seed()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var a := Run.map_seed
	Run.end()
	Run.forced_run_seed = 4242
	Run.begin_run_seed()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_int(Run.map_seed).is_equal(a)
