extends GdUnitTestSuite

## Pass 128, lane DYNA (Garry: "I wanted to make it sand-brown at first, then the player would upgrade it to make it red.
## Let's not do that."): the Dynamite's look B is a plain red stick from the start. Its shrapnel mutation (frag, now
## "Barbed Wire") winds barbed wire round it (`model_wire`), Sticky pours amber tar over it (`model_tar`), the Dynamite
## Bundle is three of them (`model_form`): eight models, one for every combination, chosen from the two flags whatever
## order the mutations came in (Lobber.model_key). Looks C and D still choose by `model_colour` (tan, red), and the
## evolution (Boomtown) draws its own model as before.

const TIP_STICK := Vector3(0.3589, 0.1171, -0.0229)
const TIP_BUNDLE := Vector3(0.3589, 0.2171, -0.0229)
## The three mutations that change what look B's stick wears.
const WEARS := ["new_equipment", "frag", "sticky"]


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()
	# back to the look the family plays
	for d in Registry.item_family("lob_grenade"):
		d.look_worn = "?"
	Registry.apply_item_looks()


func _wear(code: String) -> void:
	for d in Registry.item_family("lob_grenade"):
		d.wear_look(code)


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		inst.mutations.append(Registry.mutation(m))
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _glb(code: String, part: String) -> String:
	return "res://art/props/dynamite_%s_%s.glb" % [code.to_lower(), part]


## The part look B draws for a set of mutations: "<form>[_wire][_tar]".
func _part_b(muts: Array) -> String:
	var part := "bundle" if muts.has("new_equipment") else "stick"
	if muts.has("frag"):
		part += "_wire"
	if muts.has("sticky"):
		part += "_tar"
	return part


## Every order of every subset of `items`.
func _orders(items: Array) -> Array:
	var out: Array = [[]]
	for n in range(1, items.size() + 1):
		out.append_array(_perms(items, n))
	return out


func _perms(items: Array, n: int) -> Array:
	if n == 0:
		return [[]]
	var out: Array = []
	for i in range(items.size()):
		var rest: Array = items.duplicate()
		rest.remove_at(i)
		for tail: Array in _perms(rest, n - 1):
			out.append([items[i]] + tail)
	return out


func test_look_b_names_eight_models_that_are_on_disk_and_the_old_four_are_gone() -> void:
	_wear("B")
	var p: Dictionary = Registry.weapon("lob_grenade").params
	assert_bool(p.has("model_colour")).override_failure_message("look B names a colour again").is_false()
	var models: Dictionary = p["models"]
	for form: String in ["stick", "bundle"]:
		var f: Dictionary = models[form]
		for key: String in ["plain", "wire", "tar", "wire_tar"]:
			var want := _glb("B", form if key == "plain" else form + "_" + key)
			assert_str(str(f.get(key, ""))).override_failure_message("%s %s" % [form, key]).is_equal(want)
			assert_bool(ResourceLoader.exists(want)).override_failure_message(want).is_true()
		assert_bool(f.has("tan") or f.has("red")).override_failure_message(form + " still has a paper colour").is_false()
		assert_bool(f.get("tip") is Array).is_true()
	for old: String in ["stick_tan", "stick_red", "bundle_tan", "bundle_red"]:
		assert_bool(ResourceLoader.exists(_glb("B", old))).override_failure_message(_glb("B", old) + " is still there").is_false()


func test_every_combination_resolves_to_its_model_in_any_mutation_order() -> void:
	_wear("B")
	var seen := {}
	var orders := _orders(WEARS)
	# 1 + 3 + 6 + 6 orders of the three mutations
	assert_int(orders.size()).is_equal(16)
	for muts: Array in orders:
		var pick := Lobber.model_choice(_inst("lob_grenade", muts, 3).params)
		var want := _glb("B", _part_b(muts))
		assert_str(str(pick["path"])).override_failure_message("B with %s" % str(muts)).is_equal(want)
		assert_bool(ResourceLoader.exists(want)).override_failure_message(want).is_true()
		var tip: Vector3 = pick["tip"]
		var tip_want := TIP_BUNDLE if muts.has("new_equipment") else TIP_STICK
		assert_bool(tip.is_equal_approx(tip_want)).override_failure_message("B with %s: tip %s" % [str(muts), str(tip)]).is_true()
		seen[want] = true
	assert_int(seen.size()).override_failure_message(str(seen.keys())).is_equal(8)
	# the Drifter's Fire in the Hole is a rule of the blast (Mini Crits), it draws nothing: the model stays the weapon's
	for muts: Array in [[], ["frag"], ["sticky", "new_equipment"], ["frag", "sticky", "new_equipment"]]:
		var with_it: Array = ["fire_in_the_hole"] + muts
		assert_str(str(Lobber.model_choice(_inst("lob_grenade", with_it, 3).params)["path"])).is_equal(_glb("B", _part_b(muts)))


func test_every_look_b_model_is_one_mesh_of_the_sticks_size() -> void:
	for part: String in ["stick", "stick_wire", "stick_tar", "stick_wire_tar", "bundle", "bundle_wire", "bundle_tar", "bundle_wire_tar"]:
		var root: Node = (load(_glb("B", part)) as PackedScene).instantiate()
		var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).override_failure_message(part).is_equal(1)
		var mesh: Mesh = (meshes[0] as MeshInstance3D).mesh
		root.free()
		assert_object(mesh).override_failure_message(part).is_not_null()
		assert_int(mesh.get_surface_count()).override_failure_message(part).is_equal(1)
		# the Lobber's material takes the vertex colours as albedo: the mesh must carry them
		assert_bool((mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0).override_failure_message(part + " has no vertex colours").is_true()
		var size := mesh.get_aabb().size
		assert_float(maxf(size.x, maxf(size.y, size.z))).override_failure_message(part).is_between(0.6, 0.7)


func test_the_key_is_built_from_the_two_flags_and_a_named_colour_wins() -> void:
	var form := {"plain": "p", "wire": "w", "tar": "t", "wire_tar": "wt"}
	assert_str(Lobber.model_key({}, form)).is_equal("plain")
	assert_str(Lobber.model_key({"model_wire": true}, form)).is_equal("wire")
	assert_str(Lobber.model_key({"model_tar": true}, form)).is_equal("tar")
	assert_str(Lobber.model_key({"model_tar": true, "model_wire": true}, form)).is_equal("wire_tar")
	assert_str(Lobber.model_key({"model_wire": false, "model_tar": true}, form)).is_equal("tar")
	# a look that names a colour (C, D) keeps it, flags or not
	assert_str(Lobber.model_key({"model_colour": "red", "model_wire": true}, {"tan": "a", "red": "b"})).is_equal("red")
	# a form without the combination falls back to its plain model, a form from before pass 128 to "tan"
	assert_str(Lobber.model_key({"model_wire": true, "model_tar": true}, {"plain": "p", "wire": "w"})).is_equal("plain")
	assert_str(Lobber.model_key({}, {"tan": "a", "red": "b"})).is_equal("tan")
	assert_str(Lobber.model_key({"model_wire": true}, {"tan": "a", "red": "b"})).is_equal("tan")


func test_look_b_mutations_set_the_flags_and_no_colour() -> void:
	_wear("B")
	var frag: Dictionary = Registry.mutation("frag").params
	assert_bool(bool(frag.get("model_wire", false))).is_true()
	assert_bool(frag.has("model_colour")).is_false()
	var sticky: Dictionary = Registry.mutation("sticky").params
	assert_bool(bool(sticky.get("model_tar", false))).is_true()
	# as since pass 76: no amber tint over the model, no blinking light over the spark
	assert_bool(sticky.has("tint")).is_false()
	assert_bool(sticky.has("look")).is_false()
	assert_str(str(Registry.mutation("new_equipment").params.get("model_form", ""))).is_equal("bundle")
	# the rules stay: the nails' burst, the ride
	assert_int(int((frag["burst_spawn"] as Dictionary)["count"])).is_equal(6)
	assert_float(float((sticky["sticky"] as Dictionary)["seconds"])).is_equal_approx(1.3, 0.0001)


func test_look_b_words_fit_a_red_stick_in_barbed_wire() -> void:
	_wear("B")
	assert_str(Registry.weapon("lob_grenade").display_name).is_equal("Dynamite Stick")
	assert_str(Registry.mutation("new_equipment").display_name).is_equal("Dynamite Bundle")
	assert_str(Registry.mutation("frag").display_name).is_equal("Barbed Wire")
	assert_str(Registry.mutation("frag").text).contains("six wire barbs")
	# no paper colour that is gone and no nails in the words of the weapon and its four mutations
	for id: String in ["lob_grenade", "new_equipment", "frag", "sticky", "fire_in_the_hole"]:
		var d = Registry.weapon(id) if Registry.weapon(id) != null else Registry.mutation(id)
		var words: String = (str(d.display_name) + " | " + str(d.flavour) + " | " + (str(d.text) if d is MutationDef else "")).to_lower()
		for gone: String in ["nail", "sandy", "sand-brown", "tan "]:
			assert_bool(words.contains(gone)).override_failure_message("%s says '%s': %s" % [id, gone, words]).is_false()


func test_looks_c_and_d_still_choose_by_colour() -> void:
	for code: String in ["C", "D"]:
		_wear(code)
		var cases := {[]: "stick_tan", ["frag"]: "stick_red", ["sticky"]: "stick_tan", ["new_equipment"]: "bundle_tan",
			["new_equipment", "frag"]: "bundle_red", ["frag", "new_equipment"]: "bundle_red",
			["sticky", "frag", "new_equipment"]: "bundle_red", ["new_equipment", "sticky"]: "bundle_tan"}
		for muts in cases.keys():
			var pick := Lobber.model_choice(_inst("lob_grenade", muts, 3).params)
			assert_str(str(pick["path"])).override_failure_message("%s with %s" % [code, str(muts)]).is_equal(_glb(code, str(cases[muts])))
			assert_bool(ResourceLoader.exists(str(pick["path"]))).override_failure_message(str(pick["path"])).is_true()
		assert_str(Registry.mutation("frag").display_name).override_failure_message(code).is_equal("Coffin Nails")


func test_the_evolution_draws_its_own_model_as_before() -> void:
	for code: String in ["B", "C", "D"]:
		_wear(code)
		for muts: Array in [["new_equipment", "frag", "sticky"], ["sticky", "frag", "new_equipment"]]:
			var evo := Lobber.model_choice(_inst("golden_pineapple", muts).params)
			assert_str(str(evo["path"])).override_failure_message("%s with %s" % [code, str(muts)]).is_equal(_glb(code, "evo"))
			assert_bool(ResourceLoader.exists(str(evo["path"]))).is_true()
			assert_bool((evo["tip"] as Vector3) != Vector3.INF).is_true()
	_wear("B")
	var gp: WeaponDef = Registry.weapon("golden_pineapple")
	assert_str(gp.display_name).is_equal("Boomtown")
	assert_str(str(gp.params.get("model", ""))).is_equal("res://art/props/dynamite_b_evo.glb")
	assert_bool(gp.params.has("models")).override_failure_message("Boomtown chooses among models now").is_false()


func test_a_creatures_dynamite_is_the_red_stick_that_is_on_disk() -> void:
	assert_str(ProjectileManager.DYN_MODEL).is_equal("res://art/props/dynamite_b_stick.glb")
	assert_bool(ResourceLoader.exists(ProjectileManager.DYN_MODEL)).is_true()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/spit_cactus/spit_cactus.json"))
	var model := str(((d["ranged"] as Dictionary)["dynamite"] as Dictionary)["model"])
	assert_bool(ResourceLoader.exists(model)).override_failure_message(model).is_true()
