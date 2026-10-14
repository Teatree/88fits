extends GdUnitTestSuite

## Pass 76, lane DYNART (Garry: "Change the visuals and the naming of the Grenade to be a Dynamite Stick ... Make this a
## Look (with several candidates), so I can switch back to the grenade if I ever change my mind"): the grenade family's
## dynamite looks B, C and D beside the grenade (A). Every look names the six items the same (Dynamite Stick, Dynamite
## Bundle, Coffin Nails, Sticky, Fire in the Hole, Boomtown), wears its own icons and its own models (a stick and a bundle
## in sandy brown and in red, Boomtown's own), keeps every number of the rules, and leaves the stick's own paper and its
## spark alone under Sticky. The look the family plays is Garry's to switch (the arena's chips, the Level Editor): these
## tests wear each look in turn and never pin which one plays.

const FAMILY := ["lob_grenade", "new_equipment", "frag", "sticky", "fire_in_the_hole", "golden_pineapple"]
const NAMES := {"lob_grenade": "Dynamite Stick", "new_equipment": "Dynamite Bundle", "frag": "Coffin Nails",
	"sticky": "Sticky", "fire_in_the_hole": "Fire in the Hole", "golden_pineapple": "Boomtown"}
const LOOKS := ["B", "C", "D"]
## Boomtown's thing words in each look (what it throws: a crate, a keg, a gilded bundle).
const EVO_NOUNS := {"B": ["crate", "crates"], "C": ["keg", "kegs"], "D": ["bundle", "bundles"]}
## The keys a look may lay over the params: how the shots are drawn, never how they play.
const DRAWING := ["models", "model_form", "model_colour", "model", "model_scale", "model_metallic", "model_roughness",
	"fuse_tip", "tint", "look"]


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


func _def(id: String):
	if Registry.weapon(id) != null:
		return Registry.weapon(id)
	return Registry.mutation(id)


## Every member of the family wears look `code`.
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


## The rules of a member as text: its base stats, its levels, its effects and its params without the drawing keys.
func _rules(d) -> String:
	var p: Dictionary = (d.params as Dictionary).duplicate(true)
	for k: String in DRAWING:
		p.erase(k)
	# an evolution's own drawing key inside its `final` (the Golden Pineapple's gold tint; Boomtown draws its own colours)
	if p.get("final") is Dictionary:
		var fin: Dictionary = (p["final"] as Dictionary).duplicate(true)
		fin.erase("tint")
		p["final"] = fin
	var out := str(p)
	if d is WeaponDef:
		out += "|" + str((d as WeaponDef).base) + "|" + str((d as WeaponDef).max_level)
		for lv in (d as WeaponDef).levels:
			for e in lv:
				out += "|%s %s %s" % [e.stat, e.op, e.value]
	else:
		for e in (d as MutationDef).effects:
			out += "|%s %s %s" % [e.stat, e.op, e.value]
	return out


func test_the_family_has_the_three_dynamite_looks_beside_the_grenade() -> void:
	var codes: Array = Registry.item_look_codes("lob_grenade")
	for code: String in ["A", "B", "C", "D"]:
		assert_bool(codes.has(code)).override_failure_message("lob_grenade cannot play %s: %s" % [code, str(codes)]).is_true()
	assert_str(str(codes[0])).is_equal("A")
	var w: WeaponDef = Registry.weapon("lob_grenade")
	assert_bool(codes.has(w.variant)).override_failure_message("plays " + w.variant).is_true()
	# every member has its entry in every dynamite look, marked fresh until Garry approves one
	for id: String in FAMILY:
		var d = _def(id)
		assert_object(d).override_failure_message("no " + id).is_not_null()
		for code: String in LOOKS:
			assert_bool((d.variants as Dictionary).has(code)).override_failure_message("%s has no look %s" % [id, code]).is_true()
			assert_bool(bool((d.variants[code] as Dictionary).get("fresh", false))).override_failure_message("%s %s" % [id, code]).is_true()


func test_every_dynamite_look_names_the_family_and_wears_its_own_icons() -> void:
	for code: String in LOOKS:
		_wear(code)
		for id: String in FAMILY:
			var d = _def(id)
			assert_str(d.display_name).override_failure_message("%s in %s" % [id, code]).is_equal(str(NAMES[id]))
			assert_object(d.icon).override_failure_message("%s in %s" % [id, code]).is_not_null()
			assert_str(d.icon.resource_path).override_failure_message("%s in %s" % [id, code]).ends_with("%s_icon_%s.png" % [id, code.to_lower()])
		assert_array(TextGen.weapon_nouns(Registry.weapon("lob_grenade"))).is_equal(["stick", "sticks"])
		assert_array(TextGen.weapon_nouns(Registry.weapon("golden_pineapple"))).is_equal(EVO_NOUNS[code])
		# the words keep their numbers
		assert_str(Registry.mutation("frag").text).contains("six coffin nails")
		assert_str(Registry.mutation("new_equipment").text).contains("35%")
		var flav: String = Registry.weapon("golden_pineapple").flavour
		for part: String in ["1.3 s", "40%", "12", "4 small"]:
			assert_str(flav).override_failure_message("%s: %s" % [code, flav]).contains(part)
	# the grenade (A) keeps the old names and its painted Fire in the Hole
	_wear("A")
	assert_str(Registry.weapon("lob_grenade").display_name).is_equal("Lob Grenade")
	assert_str(Registry.weapon("golden_pineapple").display_name).is_equal("Golden Pineapple")
	assert_str(Registry.mutation("fire_in_the_hole").icon.resource_path).ends_with("fire_in_the_hole_icon.png")


func test_a_look_changes_no_rule() -> void:
	_wear("A")
	var plain := {}
	for id: String in FAMILY:
		plain[id] = _rules(_def(id))
	for code: String in LOOKS:
		_wear(code)
		for id: String in FAMILY:
			assert_str(_rules(_def(id))).override_failure_message("%s's rules move in look %s" % [id, code]).is_equal(str(plain[id]))


func test_the_shot_is_a_stick_or_a_bundle_in_sandy_brown_or_red() -> void:
	for code: String in LOOKS:
		_wear(code)
		var cases := {[]: "stick_tan", ["frag"]: "stick_red", ["new_equipment"]: "bundle_tan",
			["new_equipment", "frag"]: "bundle_red", ["frag", "new_equipment"]: "bundle_red", ["sticky"]: "stick_tan"}
		for muts in cases.keys():
			var pick := Lobber.model_choice(_inst("lob_grenade", muts, 3).params)
			assert_str(str(pick["path"])).override_failure_message("%s with %s" % [code, str(muts)]).is_equal(_glb(code, str(cases[muts])))
			assert_bool((pick["tip"] as Vector3) != Vector3.INF).override_failure_message("%s with %s: no fuse tip" % [code, str(muts)]).is_true()
		# Boomtown carries the whole path and draws its own model, its fuse tip its own
		var gp := _inst("golden_pineapple", ["new_equipment", "frag", "sticky"])
		var evo := Lobber.model_choice(gp.params)
		assert_str(str(evo["path"])).is_equal(_glb(code, "evo"))
		assert_bool((evo["tip"] as Vector3) != Vector3.INF).is_true()


func test_every_dynamite_model_is_a_mesh_with_its_tip_at_the_fuse() -> void:
	for code: String in LOOKS:
		for part: String in ["stick_tan", "stick_red", "bundle_tan", "bundle_red", "evo"]:
			var path := _glb(code, part)
			assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
			var root: Node = (load(path) as PackedScene).instantiate()
			var mesh: Mesh = null
			for c in root.find_children("*", "MeshInstance3D", true, false):
				mesh = (c as MeshInstance3D).mesh
				break
			root.free()
			assert_object(mesh).override_failure_message(path).is_not_null()
			# about the grenade shot's size: half a metre or so along its longest side
			var size := mesh.get_aabb().size
			var longest := maxf(size.x, maxf(size.y, size.z))
			assert_float(longest).override_failure_message("%s is %.2f m" % [path, longest]).is_between(0.45, 0.85)
	# the tips the looks name sit at the models' fuse ends: past the stick's +X end (it lies across its flight, so it
	# tumbles), above its middle
	for code: String in LOOKS:
		_wear(code)
		var stick := Lobber.model_choice(_inst("lob_grenade").params)
		var tip: Vector3 = stick["tip"]
		assert_float(tip.x).override_failure_message(code).is_greater(0.25)
		assert_float(tip.y).override_failure_message(code).is_greater(0.0)


func test_sticky_leaves_the_stick_its_own_paper_and_its_spark() -> void:
	for code: String in LOOKS:
		_wear(code)
		var p: Dictionary = _inst("lob_grenade", ["sticky"], 3).params
		assert_bool(p.has("tint")).override_failure_message("%s: Sticky tints the stick" % code).is_false()
		assert_bool(p.has("look")).override_failure_message("%s: Sticky's light covers the spark" % code).is_false()
		# it still sticks, as long as ever
		assert_float(float((p["sticky"] as Dictionary)["seconds"])).is_equal_approx(1.3, 0.0001)
	# the grenade keeps its glossy amber and its blinking light
	_wear("A")
	var pa: Dictionary = _inst("lob_grenade", ["sticky"], 3).params
	assert_bool(pa.has("tint")).is_true()
	assert_bool((pa.get("look", {}) as Dictionary).has("blink")).is_true()
