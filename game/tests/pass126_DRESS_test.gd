extends GdUnitTestSuite

## Pass 126, lane DRESS (Garry: "avoid any kinds of generation elements that create big obstacles ... Our enemies don't think",
## telephone poles "cut across the whole desert", a toppled cart with a wheel or two in 75% of runs, 2-6 grave crosses, "the
## smaller Environment Rocks have no collision"). The rules across many map seeds; the numbers are read from MapDressing's
## config and the map file, so Garry's tuning never breaks them.

const DRESS := preload("res://core/systems/MapDressing.gd")
const LINE := preload("res://core/systems/TelephoneLine.gd")
const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")
## Whole maps built (a build is about 0.3 s); the cart's 75% is also rolled over 200 seeds without a build.
const SEEDS := 80
const SEED_BASE := 2000

var rows: Array = []
var cfg: Dictionary = {}


func before() -> void:
	cfg = DRESS.config_of(_map_block())
	for k in SEEDS:
		var s := SEED_BASE + k * 13
		var m := _canyon(s)
		rows.append(_row_of(m, s))
		m.free()
	Run.map_seed = 0
	Run.map = null


func _map_block():
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	return tl.get("dressing")


## Red Canyon built for map seed `s`, as a run builds it (not freed).
func _canyon(s: int) -> MapBase:
	Run.map = Registry.map("red_canyon")
	Run.map_seed = s
	var m: MapBase = (Registry.map("red_canyon").scene as PackedScene).instantiate()
	add_child(m)
	return m


## What the tests read of a built map, the map itself gone afterwards.
func _row_of(m: MapBase, s: int) -> Dictionary:
	var d: Node3D = m.get("dressing")
	var lines: Array = m.get_children().filter(func(c) -> bool: return c is LINE)
	var line: LINE = m.get_node_or_null("TelephoneLine")
	var props: PropField = m.get("props")
	var with_radius := 0
	for r: Dictionary in props.placed:
		if props.radius_of(str(r["id"])) > 0.0:
			with_radius += 1
	var wet := 0
	var off_ground := 0.0
	for p: Dictionary in line.poles:
		if p["state"] != "missing":
			if m.call("_lake_edge", p["pos"]) < 0.5:
				wet += 1
			off_ground = maxf(off_ground, absf(float(p["foot"].y) - m.height_at(p["pos"].x, p["pos"].y)))
	var cart_row: Dictionary = (d.get("cart") as Dictionary).duplicate()
	if not cart_row.is_empty():
		cart_row["river"] = m.call("_river_dist", cart_row["pos"])
		cart_row["lake"] = m.call("_lake_edge", cart_row["pos"])
		cart_row["circle"] = -1.0
		for o: Vector3 in m.obstacles:
			if Vector2(o.x, o.y).distance_to(cart_row["pos"]) < 0.01:
				cart_row["circle"] = o.z
	var cross_wet := 0
	for g: Dictionary in d.get("graves"):
		for c: Dictionary in g["crosses"]:
			if m.call("_lake_edge", c["pos"]) < 0.5:
				cross_wet += 1
	return {
		"seed": s, "lines": lines.size(), "poles": line.poles.duplicate(), "spans": line.spans.duplicate(), "way": line.waypoints,
		"radius": m.arena_radius, "bodies": line.find_children("*", "StaticBody3D", true, false).size() + d.find_children("*", "StaticBody3D", true, false).size(),
		"obstacles": m.obstacles.size(), "with_radius": with_radius, "wet": wet, "cross_wet": cross_wet, "off_ground": off_ground,
		"cart": cart_row, "graves": (d.get("graves") as Array).duplicate(),
		"meshes": d.find_children("*", "MeshInstance3D", true, false).size(), "wires": line.find_children("*", "MeshInstance3D", true, false).size(),
		"flats_c": m.flats_center, "flats_r": float(m.get("flats_radius")), "river_w": float(m.get("river_width")),
	}


func after() -> void:
	Run.map_seed = 0
	Run.map = null


# ---------------------------------------------------------------- the line

func test_one_line_from_edge_to_edge() -> void:
	var edge: float = float(cfg["telephone"]["edge_in"])
	for r: Dictionary in rows:
		assert_int(int(r["lines"])).is_equal(1)
		var poles: Array = r["poles"]
		var first: Dictionary = poles[0]
		var last: Dictionary = poles[poles.size() - 1]
		# both ends stand, next to the wall
		assert_str(str(first["state"])).is_not_equal("missing")
		assert_str(str(last["state"])).is_not_equal("missing")
		for p: Dictionary in [first, last]:
			assert_float(Vector2(p["spot"]).length()).is_equal_approx(float(r["radius"]) - edge, 0.01)
		# it crosses the desert: the chord is never a short cut across a corner
		assert_float(Vector2(first["spot"]).distance_to(last["spot"])).is_greater(float(r["radius"]) * 1.6)


func test_spans_are_nine_to_twelve_metres_and_poles_move_little() -> void:
	var span: Array = cfg["telephone"]["span"]
	for r: Dictionary in rows:
		var poles: Array = r["poles"]
		assert_int(poles.size()).is_greater_equal(8)
		for k in range(poles.size() - 1):
			var d := Vector2(poles[k]["spot"]).distance_to(poles[k + 1]["spot"])
			assert_float(d).is_between(float(span[0]) * 0.93, float(span[1]) * 1.05)
		for p: Dictionary in poles:
			assert_float(Vector2(p["pos"]).distance_to(p["spot"])).is_less_equal(LINE.NUDGE_STEP * LINE.NUDGE_STEPS + 0.01)


func test_it_usually_bends_never_sharply() -> void:
	var limit: float = float(cfg["telephone"]["max_bend_deg"])
	var bent := 0
	for r: Dictionary in rows:
		var spots := PackedVector2Array()
		for p: Dictionary in r["poles"]:
			spots.append(p["spot"])
		assert_float(LINE.sharpest_turn(r["way"])).is_less(limit)
		assert_float(LINE.sharpest_turn(spots)).is_less(limit)
		if (r["way"] as PackedVector2Array).size() > 2:
			bent += 1
	assert_int(bent).is_greater(int(rows.size() * 0.7))


func test_often_broken_and_about_half_the_spans_bare() -> void:
	var spots := 0
	var by := {"missing": 0, "snapped": 0, "leaning": 0, "standing": 0}
	var spans := 0
	var wired := 0
	var long_gap := 0
	var lean_most := 0.0
	var fallen := 0
	for r: Dictionary in rows:
		var run := 0
		for p: Dictionary in r["poles"]:
			spots += 1
			by[p["state"]] += 1
			run = run + 1 if p["state"] == "missing" else 0
			if run >= 2:
				long_gap += 1
			if p["state"] == "leaning":
				lean_most = maxf(lean_most, float(p["lean"]))
			if bool(p["fallen"]):
				fallen += 1
		for s: Dictionary in r["spans"]:
			spans += 1
			if bool(s["wired"]):
				wired += 1
				# a wire hangs only between two poles that hold it up
				assert_str(str(r["poles"][s["a"]]["state"])).is_not_equal("missing")
				assert_str(str(r["poles"][s["b"]]["state"])).is_not_equal("missing")
				assert_str(str(r["poles"][s["a"]]["state"])).is_not_equal("snapped")
				assert_str(str(r["poles"][s["b"]]["state"])).is_not_equal("snapped")
	assert_float(float(by["missing"]) / float(spots)).is_between(0.12, 0.4)
	assert_int(long_gap).is_greater(0)
	assert_int(int(by["snapped"])).is_greater(0)
	assert_int(fallen).is_greater(0)
	assert_int(int(by["leaning"])).is_greater(int(spots * 0.1))
	assert_float(lean_most).is_greater(float(cfg["telephone"]["lean_deg"][1]) * 0.7)
	var bare := 1.0 - float(wired) / float(spans)
	assert_float(bare).is_between(0.4, 0.62)


func test_poles_stand_on_the_ground_out_of_the_water() -> void:
	for r: Dictionary in rows:
		assert_int(int(r["wet"])).is_equal(0)
		assert_float(float(r["off_ground"])).is_less(0.001)


func test_the_wind_only_turns_the_shaders_amplitude() -> void:
	var m := _canyon(_seed_with_wire())
	var line: LINE = m.get_node_or_null("TelephoneLine")
	assert_float(line.wind()).is_equal(1.0)
	line.set_wind(3.5)
	assert_float(line.wind()).is_equal(3.5)
	line.set_wind(-1.0)
	assert_float(line.wind()).is_equal(0.0)
	var wires := line.get_node_or_null("Wires") as MeshInstance3D
	assert_object(wires).is_not_null()
	# one mesh for every span; its box reaches every pole with wire
	assert_float(wires.custom_aabb.size.length()).is_greater(5.0)
	m.free()


func _seed_with_wire() -> int:
	for r: Dictionary in rows:
		if (r["spans"] as Array).any(func(s: Dictionary) -> bool: return bool(s["wired"])):
			return int(r["seed"])
	return SEED_BASE


func test_a_catenary_hangs_lowest_mid_span() -> void:
	var a := Vector3(0, 5, 0)
	var b := Vector3(10, 5.4, 0)
	var pts: PackedVector3Array = LINE._catenary(a, b, 0.8)
	assert_vector(pts[0]).is_equal(a)
	assert_vector(pts[pts.size() - 1]).is_equal_approx(b, Vector3.ONE * 0.001)
	var mid := pts[pts.size() / 2]
	assert_float(mid.y).is_equal_approx(5.2 - 0.8, 0.001)


# ---------------------------------------------------------------- the cart

func test_the_cart_comes_in_about_three_runs_of_four() -> void:
	var chance: float = float(cfg["cart"]["chance"])
	var n := 0
	for k in 200:
		if DRESS.rolls_cart(9000 + k * 7, chance):
			n += 1
	assert_int(n).is_between(int(200 * (chance - 0.1)), int(200 * (chance + 0.1)))
	for r: Dictionary in rows:
		assert_bool(not (r["cart"] as Dictionary).is_empty()).is_equal(DRESS.rolls_cart(int(r["seed"]), chance))


func test_the_cart_stands_on_flat_land_with_one_or_two_wheels() -> void:
	var c: Dictionary = cfg["cart"]
	var ones := 0
	var twos := 0
	var sinks: Array = []
	var leans: Array = []
	for r: Dictionary in rows:
		var cart: Dictionary = r["cart"]
		if cart.is_empty():
			continue
		assert_float(float(cart["flat"])).is_less_equal(float(c["flat_max"]))
		var pos: Vector2 = cart["pos"]
		var keep := float(c["keep"])
		assert_float(float(cart["river"])).is_greater_equal(float(r["river_w"]) * 0.5 + 1.0 + keep)
		assert_float(float(cart["lake"])).is_greater_equal(1.2 + keep)
		assert_float(pos.length()).is_less_equal(float(r["radius"]) - 5.0)
		var fc: Vector3 = r["flats_c"]
		assert_float(pos.distance_to(Vector2(fc.x, fc.z))).is_greater(float(r["flats_r"]))
		var wheels: Array = cart["wheels"]
		assert_int(wheels.size()).is_between(1, 2)
		if wheels.size() == 1:
			ones += 1
		else:
			twos += 1
			assert_float(absf(float(wheels[0]["dist"]) - float(wheels[1]["dist"]))).is_greater_equal(float(c["wheel_apart"]))
		for w: Dictionary in wheels:
			assert_float(float(w["dist"])).is_between(float(c["wheel_dist"][0]), float(c["wheel_dist"][1]))
			assert_float(Vector2(w["pos"]).distance_to(pos)).is_equal_approx(float(w["dist"]), 0.001)
			sinks.append(float(w["sink"]))
			leans.append(float(w["lean"]))
	assert_int(ones).is_greater(5)
	assert_int(twos).is_greater(5)
	# some half sunk, some nearly out, leaning differently
	sinks.sort()
	leans.sort()
	assert_float(float(sinks[0])).is_less(0.2)
	assert_float(float(sinks[sinks.size() - 1])).is_greater(0.4)
	assert_float(float(leans[leans.size() - 1]) - float(leans[0])).is_greater(35.0)


func test_the_cart_is_about_1_1_of_the_biggest_rock_and_is_the_only_new_circle() -> void:
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/sprites/props/props.json"))
	var big: float = float(man["boulder"]["radius"]) * RED_CANYON.BOULDER_SCALE_MAX
	var big_h: float = float(man["boulder"]["height"]) * RED_CANYON.BOULDER_SCALE_MAX
	for r: Dictionary in rows:
		var cart: Dictionary = r["cart"]
		if cart.is_empty():
			continue
		assert_float(float(cart["radius"])).is_equal_approx(big * 1.1, 0.02)
		assert_float(float(cart["drawn_h"])).is_equal_approx(big_h * 1.1, 0.05)
		# its obstacle circle: as any painting's, the collider plus the 0.08 m of padding
		assert_float(float(cart["circle"])).is_equal_approx(float(cart["radius"]) + 0.08, 0.001)


func test_nothing_but_paintings_with_a_radius_has_a_circle() -> void:
	# every circle on the map is a placed painting's: no pole, wheel, cross or small rock adds one
	for r: Dictionary in rows:
		assert_int(int(r["obstacles"])).is_equal(int(r["with_radius"]))
		assert_int(int(r["bodies"])).is_equal(0)


func test_small_rocks_have_no_collision_the_big_ones_keep_theirs() -> void:
	var pf: PropField = auto_free(PropField.new())
	add_child(pf)
	pf.setup()
	assert_float(pf.radius_of("rock_small")).is_equal(0.0)
	assert_float(pf.radius_of("rock_big")).is_greater(0.0)
	assert_float(pf.radius_of("boulder")).is_greater(0.0)
	# cacti and trees keep theirs: he only named rocks
	assert_float(pf.radius_of("saguaro_big")).is_greater(0.0)
	assert_float(pf.radius_of("joshua_tree")).is_greater(0.0)


# ---------------------------------------------------------------- the graves

func test_two_to_six_grave_sites_mostly_single_sometimes_a_lump() -> void:
	var g: Dictionary = cfg["graves"]
	var counts := {}
	var sites := 0
	var lumps := 0
	var crosses := 0
	var sticks := 0
	for r: Dictionary in rows:
		var list: Array = r["graves"]
		assert_int(list.size()).is_between(int(g["sites"][0]), int(g["sites"][1]))
		counts[list.size()] = true
		assert_int(int(r["cross_wet"])).is_equal(0)
		for site: Dictionary in list:
			sites += 1
			var n: int = (site["crosses"] as Array).size()
			assert_bool(n == 1 or n == int(g["lump_count"])).is_true()
			if n > 1:
				lumps += 1
				for c: Dictionary in site["crosses"]:
					assert_float(Vector2(c["pos"]).distance_to(site["center"])).is_less_equal(float(g["lump_spread"][1]) + 0.001)
			for c: Dictionary in site["crosses"]:
				crosses += 1
				if bool(c["stick"]):
					sticks += 1
				# always a little off true
				assert_float(float(c["lean"])).is_greater_equal(float(g["tilt_deg"][0]))
				assert_float(float(c["lean"])).is_less_equal(float(g["crooked_deg"][1]))
	assert_int(counts.size()).is_greater_equal(4)
	assert_float(float(lumps) / float(sites)).is_between(0.12, 0.38)
	assert_float(float(sticks) / float(crosses)).is_between(0.0, 0.14)


func test_each_cross_looks_different_from_the_rest() -> void:
	for r: Dictionary in rows:
		var seen := {}
		var n := 0
		for site: Dictionary in r["graves"]:
			for c: Dictionary in site["crosses"]:
				if bool(c["stick"]):
					continue
				n += 1
				seen[str(c["mesh"])] = true
		# no model twice until all ten are out
		assert_int(seen.size()).is_equal(mini(n, DRESS.CROSSES.size()))


func test_the_models_are_all_there_and_different() -> void:
	var kit: Dictionary = DRESS.kit()
	for id: String in DRESS.CROSSES + DRESS.STICKS + DRESS.WHEELS + ["PoleA", "PoleB", "SnapA", "SnapB", "Fallen"]:
		assert_bool(kit.has(id)).override_failure_message("no model " + id).is_true()
		var row: Dictionary = kit.get(id, {})
		assert_int((row["v"] as PackedVector3Array).size()).is_greater(4)
		assert_int((row["c"] as PackedColorArray).size()).is_equal((row["v"] as PackedVector3Array).size())
	var sizes := {}
	for id: String in DRESS.CROSSES:
		var box := AABB((kit[id]["v"] as PackedVector3Array)[0], Vector3.ZERO)
		for p: Vector3 in kit[id]["v"]:
			box = box.expand(p)
		sizes["%.2f %.2f" % [box.size.x, box.size.y]] = true
	assert_int(sizes.size()).is_equal(DRESS.CROSSES.size())


# ---------------------------------------------------------------- the whole of it

func test_one_mesh_for_the_3d_things_and_one_for_the_wires() -> void:
	for r: Dictionary in rows:
		assert_int(int(r["meshes"])).is_equal(1)
		assert_int(int(r["wires"])).is_less_equal(1)


func test_a_seed_lays_the_same_map_and_the_scatter_never_moves() -> void:
	var s := SEED_BASE + 13
	var m1 := _canyon(s)
	var m2 := _canyon(s)
	var l1: LINE = m1.get_node("TelephoneLine")
	var l2: LINE = m2.get_node("TelephoneLine")
	assert_int(l1.poles.size()).is_equal(l2.poles.size())
	for k in l1.poles.size():
		assert_vector(Vector2(l1.poles[k]["pos"])).is_equal(Vector2(l2.poles[k]["pos"]))
		assert_str(str(l1.poles[k]["state"])).is_equal(str(l2.poles[k]["state"]))
	var d1: Node3D = m1.get("dressing")
	var d2: Node3D = m2.get("dressing")
	assert_int((d1.get("graves") as Array).size()).is_equal((d2.get("graves") as Array).size())
	assert_bool((d1.get("cart") as Dictionary).is_empty()).is_equal((d2.get("cart") as Dictionary).is_empty())
	var placed_with: Array = _spots_of(m1)
	m1.free()
	m2.free()
	# the same seed with no dressing at all: every painting the scatter lays stands where it stood
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var keep = tl.get("dressing")
	tl.set("dressing", {"telephone": {"enabled": false}, "cart": {"enabled": false}, "graves": {"enabled": false}})
	var m3 := _canyon(s)
	var placed_without: Array = _spots_of(m3)
	assert_object(m3.get_node_or_null("TelephoneLine")).is_null()
	m3.free()
	tl.set("dressing", keep)
	Run.map_seed = 0
	Run.map = null
	assert_array(placed_with).is_equal(placed_without)


func _spots_of(m: MapBase) -> Array:
	var out: Array = []
	for r: Dictionary in (m.get("props") as PropField).placed:
		if str(r["id"]) != DRESS.CART_ID:
			out.append("%s %.3f %.3f" % [r["id"], r["pos"].x, r["pos"].z])
	return out


func test_the_block_reads_like_the_other_blocks() -> void:
	# no block: the defaults, whole
	assert_dict(DRESS.config_of(null)).is_equal(DRESS.DEFAULTS)
	# a key laid over, the rest as they were, an unknown key left out
	var c: Dictionary = DRESS.config_of({"cart": {"chance": 0.25, "nonsense": 1}})
	assert_float(float(c["cart"]["chance"])).is_equal(0.25)
	assert_bool((c["cart"] as Dictionary).has("nonsense")).is_false()
	assert_float(float(c["cart"]["flat_max"])).is_equal(float(DRESS.DEFAULTS["cart"]["flat_max"]))
	# the map file's block names only keys the code knows
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var block = (d["timeline_data"] as Dictionary).get("dressing")
	if block is Dictionary:
		for section: String in (block as Dictionary).keys():
			assert_bool(DRESS.DEFAULTS.has(section)).is_true()
			for k: String in (block[section] as Dictionary).keys():
				assert_bool((DRESS.DEFAULTS[section] as Dictionary).has(k)).override_failure_message(section + "." + k).is_true()
