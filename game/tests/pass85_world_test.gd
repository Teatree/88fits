## Pass 85, lane WORLD (Garry: "the Main Menu background still features the old sand texture. Make sure it uses the one
## that I chose ... The arrangement of environment assets can be random but it should be from a bunch of presets", "Add
## slight random colour variations to the 2.5d environment assets ... natural for that element", "Add another variant of
## a palm tree and joshua tree", "Make the teleport area a bit smaller and the teleport structure itself a bit smaller
## ... at least 3 of them on the map. 33% of the time 4 ... never teleport the Player next to another teleport ... never
## spawn close to each other"). The title wears the map's own sand; its presets parse and one is drawn; every prop kind
## has a natural tint rule within bounds, packed per spot; the new trees are variants; the Teleports: smaller, 3 or 4
## (a third of the runs 4), apart, and never landing the hero by one.
extends GdUnitTestSuite

const STAGE := preload("res://ui/TitleStage.gd")
const PROPS := "res://art/sprites/props/props.json"
const CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	STAGE.force_preset = -1
	STAGE.forget()
	get_tree().paused = false
	Run.forced_map_seed = 0
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PROPS))


func _title() -> Control:
	Settings.menu_style = "live"
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	return t


# ---------------------------------------------------------------- the title

func test_the_title_wears_the_maps_own_sand() -> void:
	Run.map = null
	var t := _title()
	await get_tree().process_frame
	var stage = t._stage
	assert_object(stage).is_not_null()
	var def: MapDef = Registry.map("red_canyon")
	var want: String = CANYON.sand_or_default(str(def.timeline.sand))
	assert_str(str(stage.map.get("sand_id"))).is_equal(want)
	# the map's def stood in only while the map was built
	assert_object(Run.map).is_null()


func test_the_presets_parse_and_stay_clear_of_the_hero() -> void:
	var sc := STAGE.scene_of("red_canyon")
	var presets := STAGE.presets_of(sc)
	assert_int(presets.size()).is_greater_equal(5)
	var man := _manifest()
	var bx: Array = sc["clear"]["x"]
	var bz: Array = sc["clear"]["z"]
	var names := {}
	for pr: Dictionary in presets:
		assert_str(str(pr.get("name", ""))).is_not_empty()
		names[pr["name"]] = true
		assert_int((pr["props"] as Array).size()).is_greater_equal(6)
		for e: Dictionary in pr["props"]:
			assert_bool(man.has(str(e["id"]))).override_failure_message(str(e["id"])).is_true()
			var x := float(e["x"])
			var z := float(e["z"])
			assert_float(Vector2(x, z).length()).is_greater(1.3)
			assert_bool(x >= float(bx[0]) and x <= float(bx[1]) and z >= float(bz[0]) and z <= float(bz[1])).is_true()
	assert_int(names.size()).is_equal(presets.size())
	# a bare `props` list is one preset (the file before pass 85)
	assert_int(STAGE.presets_of({"props": [{"id": "agave", "x": 2, "z": 2}]}).size()).is_equal(1)


func test_a_preset_is_drawn_and_a_kept_world_lays_a_fresh_one_in_the_same_slots() -> void:
	STAGE.force_preset = 2
	var t := _title()
	await get_tree().process_frame
	var stage = t._stage
	var presets := STAGE.presets_of(STAGE.scene_of("red_canyon"))
	assert_int(stage.preset_index).is_equal(2)
	assert_int(stage.composed.size()).is_equal((presets[2]["props"] as Array).size())
	var pf: PropField = stage.map.get("props")
	var base: int = pf.count() - int(stage.composed.size())
	var shadows: int = pf.shadow_count() - int(stage.composed.size())
	# again and again, as a kept world taken back does: the last preset comes off first
	for k in range(presets.size() * 3):
		STAGE.force_preset = k % presets.size()
		stage.compose()
		assert_int(stage.preset_index).is_equal(k % presets.size())
		assert_int(pf.count()).is_equal(base + stage.composed.size())
		assert_int(pf.shadow_count()).is_equal(shadows + stage.composed.size())
	# random: every draw is one of the presets
	STAGE.force_preset = -1
	var seen := {}
	for k in range(60):
		stage.compose()
		assert_int(stage.preset_index).is_between(0, presets.size() - 1)
		seen[stage.preset_index] = true
	assert_int(seen.size()).is_greater(2)


# ---------------------------------------------------------------- the tints

func test_every_prop_kind_has_a_natural_tint_rule_within_bounds() -> void:
	var pf: PropField = auto_free(PropField.new())
	add_child(pf)
	pf.setup()
	for id: String in pf.manifest.keys():
		if id.begins_with("st_") or pf.is_hidden(id) or not pf.has(id):
			continue
		var rules := pf.tint_rules(id)
		assert_int(rules.size()).override_failure_message(id + " has no tint").is_between(1, PropField.TINT_PARTS)
		for r: Dictionary in rules:
			var h: Array = r["h"]
			var s: Array = r["s"]
			var v: Array = r["v"]
			assert_float(absf(float(h[0]))).is_less_equal(PropField.TINT_MAX_H)
			assert_float(absf(float(h[1]))).is_less_equal(PropField.TINT_MAX_H)
			for x in s:
				assert_float(float(x)).is_between(PropField.TINT_S_RANGE.x, PropField.TINT_S_RANGE.y)
			for x in v:
				assert_float(float(x)).is_between(PropField.TINT_V_RANGE.x, PropField.TINT_V_RANGE.y)
	# the rocks barely move: a boulder's value within 5 % either way, its hue within 0.01
	for r: Dictionary in pf.tint_rules("boulder"):
		assert_float(float(r["v"][0])).is_greater_equal(0.95)
		assert_float(float(r["v"][1])).is_less_equal(1.05)
		assert_float(absf(float(r["h"][0]))).is_less_equal(0.01)
	# a variant without its own takes its kind's
	assert_array(pf.tint_rules("joshua_tree_d")).is_equal(pf.tint_rules("joshua_tree"))


func test_the_tint_rolls_are_packed_per_spot_and_stable() -> void:
	var seen := {}
	for k in range(400):
		var at := Vector3(float(k) * 1.37 - 200.0, 0.0, float(k % 17) * 3.1)
		var c := PropField.tint_code(at)
		assert_float(c).is_equal(PropField.tint_code(at))
		assert_float(c).is_between(0.0, 2047.0)
		assert_float(c).is_equal(floorf(c))
		var r := PropField.tint_rolls(c)
		for x in [r.x, r.y, r.z]:
			assert_float(x).is_between(0.0, 1.0)
		seen[c] = true
	assert_int(seen.size()).is_greater(250)
	# the instance carries it (custom data a), no extra draw: one MultiMesh per painting as before
	var pf: PropField = auto_free(PropField.new())
	add_child(pf)
	pf.setup()
	var mmis := pf.get_children().filter(func(c) -> bool: return c is MultiMeshInstance3D).size()
	pf.add("agave", Vector3(3, 0, 4))
	assert_int(pf.get_children().filter(func(c) -> bool: return c is MultiMeshInstance3D).size()).is_equal(mmis)


func test_the_new_palm_and_joshua_tree_are_variants() -> void:
	var man := _manifest()
	for id in ["fan_palm_b", "joshua_tree_d"]:
		assert_bool(man.has(id)).is_true()
		assert_bool(ResourceLoader.exists("res://art/sprites/props/%s.png" % id)).is_true()
	assert_str(str(man["fan_palm_b"]["variant_of"])).is_equal("fan_palm")
	assert_str(str(man["joshua_tree_d"]["variant_of"])).is_equal("joshua_tree")
	var pf: PropField = auto_free(PropField.new())
	add_child(pf)
	pf.setup()
	assert_array(pf.looks_of("fan_palm")).contains(["fan_palm_b"])
	assert_array(pf.looks_of("joshua_tree")).contains(["joshua_tree_d"])


# ---------------------------------------------------------------- the teleports

func test_the_teleport_is_smaller_and_stands_three_or_four_times() -> void:
	var t: StructureDef = Registry.structure("teleport")
	assert_float(t.radius).is_less(2.2)
	assert_float(t.height).is_less(3.2)
	assert_vector(Vector2(StructureManager.per_map_range(t))).is_equal(Vector2(3, 4))
	assert_float(StructureManager.kin_spacing(t)).is_greater_equal(25.0)
	assert_float(float(t.params["land_clear"])).is_greater_equal(10.0)
	# a third of the runs four, the rest three
	var rng := RandomNumberGenerator.new()
	rng.seed = 85
	var fours := 0
	var n := 6000
	for k in range(n):
		var c := StructureManager.per_map_count(t, rng.randf(), rng.randf())
		assert_int(c).is_between(3, 4)
		if c == 4:
			fours += 1
	assert_float(float(fours) / float(n)).is_equal_approx(float(t.params["per_map"]["max_chance"]), 0.025)
	# without max_chance the old even spread (the Totem Poles)
	var pole: StructureDef = Registry.structure("totem_pole")
	var counts := {}
	for k in range(3000):
		var c2 := StructureManager.per_map_count(pole, rng.randf(), rng.randf())
		counts[c2] = int(counts.get(c2, 0)) + 1
	assert_int(counts.size()).is_equal(3)


func _run_game(seed_: int) -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": seed_, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func test_the_teleports_stand_apart_and_never_land_the_hero_by_one() -> void:
	var g := _run_game(11)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	g.player.god = true
	var t: StructureDef = Registry.structure("teleport")
	var plan: Dictionary = Run.map.timeline.structures
	var kin := StructureManager.kin_spacing(t)
	var clear := float(t.params["land_clear"])
	for trial in range(5):
		var sm: StructureManager = g.structures
		if trial > 0:
			sm = StructureManager.new()
			g.add_child(sm)
			sm.setup(g, g.map, plan)
		var tps := sm.teleport_spots()
		assert_int(tps.size()).is_between(3, 4)
		for i in tps.size():
			var p: Vector3 = tps[i]
			assert_bool(g.map.in_water(p)).is_false()
			var others := tps.filter(func(q: Vector3) -> bool: return q != p)
			assert_float(StructureManager.nearest_distance(p, others)).is_greater_equal(kin * StructureManager.KIN_RELAX - 0.01)
		if trial > 0:
			sm.queue_free()
			await get_tree().process_frame
	# forty uses: the hero comes out clear of every Teleport, out of the water and the rocks
	var spots := g.structures.teleport_spots()
	for k in range(40):
		g.player.global_position = Vector3(0, g.map.height_at(0, 0), 0)
		g.teleport_hero(t)
		var q: Vector3 = g.player.global_position
		assert_float(StructureManager.nearest_distance(q, spots)).is_greater_equal(clear)
		assert_bool(g.map.in_water(q)).is_false()
		for o: Vector3 in g.map.obstacles:
			assert_float(Vector2(q.x - o.x, q.z - o.y).length()).is_greater_equal(o.z)
	assert_bool(g.structures.teleport_landing_ok(t, spots[0] + Vector3(clear * 0.5, 0, 0))).is_false()
