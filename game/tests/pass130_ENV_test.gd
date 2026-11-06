extends GdUnitTestSuite
## Pass 130: Garry's picks from the environment variations and their rules (props.json `stages`, `per_run`,
## `stage_chance`; PropField.in_stage, pick_look, settle_rare; BALANCING 72.ENV).

const MANIFEST := "res://art/sprites/props/props.json"
const STAGES := ["s1", "s2", "dust", "s3"]


func _field(stage: String = "", hell: bool = false) -> PropField:
	var pf: PropField = auto_free(PropField.new())
	add_child(pf)
	pf.setup(MANIFEST, stage, hell)
	return pf


## The paintings a kind gets over many spots.
func _looks(pf: PropField, kind: String, n: int = 400) -> Dictionary:
	var out := {}
	for k in n:
		var look := pf.pick_look(kind, Vector3(float(k) * 1.37 - 200.0, 0.0, float(k % 23) * 3.1))
		out[look] = int(out.get(look, 0)) + 1
	return out


func test_the_new_paintings_are_in_the_manifest_as_variants_of_their_kinds() -> void:
	var pf := _field()
	for pair in [["barrel_cactus_d", "barrel_cactus"], ["barrel_cactus_e", "barrel_cactus"], ["mesquite_tree_d", "mesquite_tree"],
			["mesquite_tree_f", "mesquite_tree"], ["desert_bush_e", "desert_bush"], ["creosote_bush_b", "creosote_bush"],
			["creosote_bush_f", "creosote_bush"], ["brittlebush_d", "brittlebush"], ["cart_toppled_b", "cart_toppled"],
			["cart_toppled_d", "cart_toppled"], ["cart_toppled_e", "cart_toppled"]]:
		assert_bool(pf.has(pair[0])).override_failure_message("%s is not loaded" % pair[0]).is_true()
		assert_str(pf.kind_of(pair[0])).is_equal(pair[1])
		# a variant plays its kind's collider and size
		assert_float(pf.radius_of(pair[0])).is_equal_approx(pf.radius_of(pair[1]), 0.001)
		assert_float(pf.height_of(pair[0])).is_equal_approx(pf.height_of(pair[1]), 0.001)


func test_every_stage_named_in_the_manifest_is_a_stage_of_the_map() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var ids: Array = []
	for k in (tl.stage_list as Array).size():
		ids.append(tl.stage_id(k))
	assert_array(ids).is_equal(STAGES)
	var pf := _field()
	for id in pf.manifest.keys():
		var row: Dictionary = pf.manifest[id]
		for key in ["stages", "stage_chance"]:
			if not row.has(key):
				continue
			var named: Array = row[key] if row[key] is Array else (row[key] as Dictionary).keys()
			for s in named:
				assert_bool(ids.has(str(s)) or str(s) == "hell").override_failure_message("%s names stage %s" % [id, s]).is_true()


func test_the_creosote_bush_is_its_own_at_sundown_white_fluff_at_night_and_drought_twigs_after() -> void:
	var want := {"s1": "creosote_bush", "s2": "creosote_bush_b", "dust": "creosote_bush_f", "s3": "creosote_bush_f"}
	for st: String in STAGES:
		var got := _looks(_field(st, st == "s3"), "creosote_bush")
		assert_array(got.keys()).override_failure_message("creosote in %s: %s" % [st, str(got)]).is_equal([want[st]])


func test_the_brittlebush_dries_to_seedheads_in_the_dust_bowl_and_the_blood_moon() -> void:
	var want := {"s1": "brittlebush", "s2": "brittlebush", "dust": "brittlebush_d", "s3": "brittlebush_d"}
	for st: String in STAGES:
		var got := _looks(_field(st, st == "s3"), "brittlebush")
		assert_array(got.keys()).override_failure_message("brittlebush in %s: %s" % [st, str(got)]).is_equal([want[st]])


func test_the_cart_is_one_of_three_at_equal_chances_and_the_burnt_wreck_alone_in_the_blood_moon() -> void:
	for st in ["s1", "s2", "dust"]:
		var got := _looks(_field(st), "cart_toppled", 900)
		var keys := got.keys()
		keys.sort()
		assert_array(keys).is_equal(["cart_toppled", "cart_toppled_b", "cart_toppled_d"])
		for k: String in keys:
			# a third each: 300 of 900, within what a hash gives
			assert_int(int(got[k])).override_failure_message("%s in %s: %s" % [k, st, str(got)]).is_between(240, 360)
	assert_array(_looks(_field("s3", true), "cart_toppled").keys()).is_equal(["cart_toppled_e"])


func test_a_field_not_told_its_stage_lays_the_kinds_own_painting() -> void:
	var pf := _field()
	assert_array(_looks(pf, "creosote_bush").keys()).is_equal(["creosote_bush"])
	assert_array(_looks(pf, "brittlebush").keys()).is_equal(["brittlebush"])
	assert_array(_looks(pf, "cart_toppled").keys()).is_equal(["cart_toppled"])


func test_a_variant_out_of_the_stage_is_not_even_loaded() -> void:
	var pf := _field("s1")
	for id in ["creosote_bush_b", "creosote_bush_f", "brittlebush_d", "cart_toppled_e"]:
		assert_bool(pf.has(id)).override_failure_message("%s is loaded at Sundown" % id).is_false()
	# the kind's own painting always is: the scatter asks for the kind
	assert_bool(_field("s2").has("creosote_bush")).is_true()


func test_the_plain_new_variants_are_rolled_like_any_other() -> void:
	var pf := _field("s1")
	var cactus := _looks(pf, "barrel_cactus", 800)
	for id in ["barrel_cactus", "barrel_cactus_b", "barrel_cactus_d", "barrel_cactus_e"]:
		assert_int(int(cactus.get(id, 0))).override_failure_message("%s: %s" % [id, str(cactus)]).is_greater(120)
	var tree := _looks(pf, "mesquite_tree", 800)
	assert_int(int(tree.get("mesquite_tree_d", 0))).is_greater(250)
	assert_int(int(_looks(pf, "desert_bush", 800).get("desert_bush_e", 0))).is_greater(200)


func test_yellow_catkins_is_never_rolled_by_the_spot_and_stands_exactly_once_a_run() -> void:
	var pf := _field("s1")
	assert_bool(_looks(pf, "mesquite_tree", 800).has("mesquite_tree_f")).is_false()
	for k in 7:
		pf.add("mesquite_tree", Vector3(float(k) * 9.0, 0.0, 4.0), 1.0, k % 2 == 0, 0.05)
	var before := pf.placed.size()
	var laid := pf.settle_rare(4242)
	assert_int(int(laid.get("mesquite_tree_f", 0))).is_equal(1)
	assert_int(pf.placed.size()).is_equal(before)
	var rare: Array = pf.placed.filter(func(r: Dictionary) -> bool: return str(r["look"]) == "mesquite_tree_f")
	assert_int(rare.size()).is_equal(1)
	# it is still a mesquite to everything that asks (its kind, its collider), where a mesquite stood
	assert_str(str(rare[0]["id"])).is_equal("mesquite_tree")
	assert_float(float((rare[0]["pos"] as Vector3).z)).is_equal_approx(4.0, 0.001)
	# the same seed picks the same tree
	var pf2 := _field("s1")
	for k in 7:
		pf2.add("mesquite_tree", Vector3(float(k) * 9.0, 0.0, 4.0), 1.0, k % 2 == 0, 0.05)
	pf2.settle_rare(4242)
	var rare2: Array = pf2.placed.filter(func(r: Dictionary) -> bool: return str(r["look"]) == "mesquite_tree_f")
	assert_vector(rare2[0]["pos"] as Vector3).is_equal(rare[0]["pos"] as Vector3)


func test_yellow_catkins_comes_in_half_the_blood_moon_runs_and_every_other_run() -> void:
	for st: String in STAGES:
		var runs := 0
		var n := 120 if st == "s3" else 30
		for ms in n:
			var pf := _field(st, st == "s3")
			pf.add("mesquite_tree", Vector3(3.0, 0.0, 4.0))
			pf.add("mesquite_tree", Vector3(30.0, 0.0, 4.0))
			if int(pf.settle_rare(ms).get("mesquite_tree_f", 0)) == 1:
				runs += 1
		if st == "s3":
			assert_int(runs).override_failure_message("catkins in %d of 120 Blood Moon runs" % runs).is_between(40, 80)
		else:
			assert_int(runs).is_equal(n)


func test_a_run_of_each_stage_lays_what_garry_asked() -> void:
	for k in STAGES.size():
		Run.forced_map_seed = 5151
		Run.end()
		Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
		Run.start_stage(k)
		var m: Node3D = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
		add_child(m)
		var pf: PropField = m.get("props")
		assert_str(pf.stage_id).is_equal(STAGES[k])
		var seen := {}
		for r: Dictionary in pf.placed:
			seen[str(r["look"])] = int(seen.get(str(r["look"]), 0)) + 1
		assert_int(int(seen.get("mesquite_tree_f", 0))).override_failure_message("catkins in %s: %d" % [STAGES[k], int(seen.get("mesquite_tree_f", 0))]).is_less_equal(1)
		if k < 3:
			assert_int(int(seen.get("mesquite_tree_f", 0))).is_equal(1)
		assert_bool(seen.has("creosote_bush") == (k == 0)).override_failure_message("creosote in %s: %s" % [STAGES[k], str(seen.keys())]).is_true()
		assert_bool(seen.has("creosote_bush_b") == (k == 1)).is_true()
		assert_bool(seen.has("creosote_bush_f") == (k >= 2)).is_true()
		assert_bool(seen.has("brittlebush_d") == (k >= 2)).is_true()
		assert_bool(seen.has("brittlebush") == (k < 2)).is_true()
		if k == 3:
			for id in ["cart_toppled", "cart_toppled_b", "cart_toppled_d"]:
				assert_bool(seen.has(id)).is_false()
		else:
			assert_bool(seen.has("cart_toppled_e")).is_false()
	Run.forced_map_seed = 0
	Run.end()
