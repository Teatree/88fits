extends GdUnitTestSuite
## Pass 137 (lane ENV; Garry: "Slight colour differences on the environment art ... Subtle but noticeable when two stand
## next to each other ... Random at map generation, with a higher chance in clusters of obviously same-looking assets"):
## each painting's own tint rule and knobs in props.json (`tint`, `tint_chance`, `tint_cluster`, `tint_strength`), the
## strength packed with the rolls (PropField.tint_code), the cluster rule (PropField.settle_tints; BALANCING 78.ENV).

const MANIFEST := "res://art/sprites/props/props.json"
const ROCKS := ["rock_small", "rock_big", "boulder", "boulder_b"]


func _field(stage: String = "s1") -> PropField:
	var pf: PropField = auto_free(PropField.new())
	add_child(pf)
	pf.setup(MANIFEST, stage, false)
	return pf


## A scatter like the map's on its own dice: clumps of 1-4 of one painting, spots 1.5-3 m apart, clumps 25 m apart.
func _scatter(pf: PropField, map_seed: int, clumps: int = 40) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var kinds := ["desert_bush", "boulder", "dead_tree", "barrel_cactus", "rock_small", "skull", "creosote_bush", "joshua_tree"]
	for c in clumps:
		var centre := Vector3(float(c % 8) * 25.0 - 90.0, 0.0, float(c / 8) * 25.0 - 60.0)
		var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		var n := rng.randi_range(1, 4)
		for k in n:
			var a := rng.randf() * TAU
			var r := rng.randf_range(1.5, 3.0) if k > 0 else 0.0
			pf.add(kind, centre + Vector3(cos(a) * r, 0.0, sin(a) * r), rng.randf_range(0.85, 1.15), rng.randf() < 0.5, 0.0, true)


func _tints(pf: PropField) -> Array:
	return pf.placed.map(func(r: Dictionary) -> float: return float(r["tint"]))


func test_every_scenery_kind_has_its_own_rule_and_knobs() -> void:
	var pf := _field()
	for id: String in pf.manifest.keys():
		var row: Dictionary = pf.manifest[id]
		if id.begins_with("st_") or pf.is_hidden(id) or str(row.get("variant_of", "")) != "":
			continue
		assert_int(pf.tint_rules(id).size()).override_failure_message(id + " has no tint").is_between(1, PropField.TINT_PARTS)
		assert_float(float(row.get("tint_chance", -1.0))).override_failure_message(id).is_between(0.0, 1.0)
		assert_float(float(row.get("tint_cluster", -1.0))).override_failure_message(id).is_between(0.0, 1.0)
		assert_float(float(row.get("tint_strength", -1.0))).override_failure_message(id).is_between(0.1, 2.0)
	# a variant takes its kind's knobs as it takes its rule
	assert_float(pf.tint_knob("boulder_b", "tint_chance", -1.0)).is_equal(float(pf.manifest["boulder"]["tint_chance"]))
	assert_array(pf.tint_rules("creosote_bush_f")).is_equal(pf.tint_rules("creosote_bush"))


func test_the_code_packs_three_rolls_and_a_strength_under_2048() -> void:
	for k in 300:
		var at := Vector3(float(k) * 1.37 - 200.0, 0.0, float(k % 17) * 3.1)
		for level in PropField.TINT_LEVELS:
			var c := PropField.tint_code(at, k % 3, level)
			assert_float(c).is_equal(floorf(c))
			assert_float(c).is_between(0.0, 2047.0)
			assert_int(PropField.tint_level(c)).is_equal(level)
			var r := PropField.tint_rolls(c)
			for x in [r.x, r.y, r.z]:
				assert_float(x).is_between(0.0, 1.0)
			# the same spot and attempt, the same code
			assert_float(PropField.tint_code(at, k % 3, level)).is_equal(c)
	# strength 0 is the painting as painted, whatever the rolls
	var pf := _field()
	for id in ["desert_bush", "boulder", "dead_tree", "brittlebush", "skull"]:
		for e: Vector3 in pf.tint_effect(id, PropField.tint_code(Vector3(3, 0, 7), 0, 0)):
			assert_vector(e).is_equal_approx(Vector3(0, 1, 1), Vector3(0.0001, 0.0001, 0.0001))


func test_the_rocks_stay_subtle_and_the_dead_tree_only_darkens() -> void:
	var pf := _field()
	var codes: Array = []
	for q in 512:
		codes.append(float(q + 512 * PropField.TINT_FULL))
	for id: String in ROCKS:
		for code: float in codes:
			for e: Vector3 in pf.tint_effect(id, code):
				assert_float(absf(e.x)).override_failure_message("%s hue %f" % [id, e.x]).is_less_equal(0.015)
				assert_float(e.y).override_failure_message("%s sat %f" % [id, e.y]).is_between(0.9, 1.1)
				assert_float(e.z).override_failure_message("%s value %f" % [id, e.z]).is_between(0.85, 1.0)
	for code: float in codes:
		for e: Vector3 in pf.tint_effect("dead_tree", code):
			assert_float(e.z).is_between(0.8, 1.0)
			assert_float(absf(e.x)).is_less_equal(0.01)
	# the bushes reach darker than they reach lighter (Garry: "bushes darker")
	for id in ["desert_bush", "creosote_bush", "dead_shrub"]:
		var v: Vector2 = Vector2(pf.tint_rules(id)[0]["v"][0], pf.tint_rules(id)[0]["v"][1])
		assert_float(1.0 - minf(v.x, v.y)).is_greater(maxf(v.x, v.y) - 1.0)


func test_the_same_seed_lays_the_same_tints() -> void:
	var a := _field()
	_scatter(a, 77)
	a.settle_tints()
	var b := _field()
	_scatter(b, 77)
	b.settle_tints()
	assert_int(a.placed.size()).is_greater(60)
	assert_array(_tints(a)).is_equal(_tints(b))
	# settled once, settling again changes nothing
	assert_int(int(a.settle_tints()["changed"])).is_equal(0)
	# another seed, other tints
	var c := _field()
	_scatter(c, 78)
	c.settle_tints()
	assert_array(_tints(c)).is_not_equal(_tints(a))


func test_clustered_props_vary_more_often_and_differ_from_their_neighbours() -> void:
	var pf := _field()
	# 60 lone ones, 40 m apart; 60 pairs and 30 threes, the props of a clump 2 m apart
	var lone: Array = []
	var clumps: Array = []
	for k in 60:
		var id: String = ["desert_bush", "boulder", "dead_tree"][k % 3]
		pf.add(id, Vector3(float(k % 10) * 40.0 - 200.0, 0.0, float(k / 10) * 40.0 - 400.0), 1.0, false, 0.0, true)
		lone.append(pf.placed.size() - 1)
	for k in 90:
		var id: String = ["desert_bush", "boulder", "dead_tree"][k % 3]
		var c := Vector3(float(k % 10) * 40.0 - 200.0, 0.0, float(k / 10) * 40.0 + 20.0)
		var clump: Array = []
		for j in (2 if k < 60 else 3):
			pf.add(id, c + Vector3(float(j) * 2.0, 0.0, float(j % 2) * 0.7), 1.0, false, 0.0, true)
			clump.append(pf.placed.size() - 1)
		clumps.append(clump)
	var stats := pf.settle_tints()
	assert_int(int(stats["clustered"])).is_equal(60 * 2 + 30 * 3)
	var varied := func(i: int) -> bool: return PropField.tint_level(float(pf.placed[i]["tint"])) > 0
	var lone_varied := lone.filter(varied).size()
	var clumped: Array = []
	for cl: Array in clumps:
		clumped.append_array(cl)
	var clump_varied := clumped.filter(varied).size()
	var lone_share := float(lone_varied) / float(lone.size())
	var clump_share := float(clump_varied) / float(clumped.size())
	assert_float(clump_share).override_failure_message("clumped %.2f, lone %.2f" % [clump_share, lone_share]).is_greater(lone_share + 0.2)
	# in a clump, every two props read differently: never both plain, and apart in what the tint does
	var pairs := 0
	var apart := 0
	for cl: Array in clumps:
		for x in cl.size():
			for y in range(x + 1, cl.size()):
				var p: Dictionary = pf.placed[cl[x]]
				var q: Dictionary = pf.placed[cl[y]]
				pairs += 1
				assert_bool(PropField.tint_level(float(p["tint"])) == 0 and PropField.tint_level(float(q["tint"])) == 0).is_false()
				if pf.tint_distance(str(p["look"]), float(p["tint"]), float(q["tint"])) > 0.5:
					apart += 1
	# two lone ones of a painting, for comparison: as often apart as chance has it
	var lone_pairs := 0
	var lone_apart := 0
	for x in lone.size():
		for y in range(x + 3, lone.size(), 3):
			var p: Dictionary = pf.placed[lone[x]]
			var q: Dictionary = pf.placed[lone[y]]
			lone_pairs += 1
			if pf.tint_distance(str(p["look"]), float(p["tint"]), float(q["tint"])) > 0.5:
				lone_apart += 1
	var share := float(apart) / float(pairs)
	var lone_apart_share := float(lone_apart) / float(lone_pairs)
	assert_float(share).override_failure_message("clump pairs apart %.2f, lone pairs %.2f" % [share, lone_apart_share]).is_greater(0.9)
	assert_float(share).is_greater(lone_apart_share + 0.15)


func test_a_lone_prop_keeps_the_tint_it_was_laid_with_and_the_map_settles_them() -> void:
	var pf := _field()
	pf.add("boulder", Vector3(0, 0, 0), 1.0, false, 0.0, true)
	var laid := float(pf.placed[0]["tint"])
	pf.add("boulder", Vector3(60, 0, 0), 1.0, false, 0.0, true)
	pf.settle_tints()
	assert_float(float(pf.placed[0]["tint"])).is_equal(laid)
	# settle_rare (the map calls it once everything stands) settles the tints too
	var m := _field()
	_scatter(m, 5)
	var before := _tints(m)
	m.settle_rare(5)
	var ref := _field()
	_scatter(ref, 5)
	ref.settle_tints()
	assert_array(_tints(m)).is_equal(_tints(ref))
	assert_array(_tints(m)).is_not_equal(before)
	# no new draw: one MultiMesh per painting as before
	var mmis := m.get_children().filter(func(c) -> bool: return c is MultiMeshInstance3D).size()
	m.settle_tints()
	assert_int(m.get_children().filter(func(c) -> bool: return c is MultiMeshInstance3D).size()).is_equal(mmis)


func test_the_shader_reads_the_strength_from_the_code() -> void:
	var src: String = (load("res://core/shaders/prop_billboard.gdshader") as Shader).code
	assert_str(src).contains("floor(code / 512.0) / 3.0")
	assert_str(src).contains("mod(code, 8.0) / 7.0")
	assert_int(PropField.TINT_STEPS * PropField.TINT_STEPS * PropField.TINT_STEPS * PropField.TINT_LEVELS).is_less_equal(2048)
