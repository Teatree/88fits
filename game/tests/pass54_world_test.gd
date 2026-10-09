extends GdUnitTestSuite

## Pass 54, lane WORLD: the sand and the river bed a little lighter and less orange (the painted textures and the
## terrain shader's flat tones, which Red Canyon now sets from its exports), the lake's water level for the ripples and
## the shadows, the agave walked through, the directional signs (SignField: four to six posts, one to four arms each
## pointing at the nearest structures, a used structure's name fading off its arms), the boot splash (the Godot logo
## gone) and the barrels kept out of the structures' cover bands and rings (BarrelField read a `node` field no
## structure has, so a barrel could stand behind a structure's painting).

const SIGNS := preload("res://core/systems/SignField.gd")
const IDS := ["teleport", "uber_magnet", "gold_bank", "hooded_figure", "healing_well", "loot_cache", "shop", "war_drum", "beacon"]

const FLAT_MAP := """extends MapBase
var flats_radius := 16.0
"""

const FAKE_GAME := """extends Node
var structures = null
var player = null
var paused := false
"""

const FAKE_SM := """extends Node3D
var items: Array = []
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _repo_file(rel: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("..").path_join(rel))


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.forced_map_seed = 0
	Run.end()


## A flat map (the ground at 0, the flats at the origin, the arena 66 m round) and a game holding the nine structures
## on a ring 30 to 46 m out, each its own Structure node; `ms` is the run's map seed the signs and barrels draw from.
func _world(ms: int = 54) -> Dictionary:
	Run.map_seed = ms
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(_script(FLAT_MAP))
	add_child(map)
	var game: Node = auto_free(Node.new())
	game.set_script(_script(FAKE_GAME))
	add_child(game)
	var sm: Node3D = Node3D.new()
	sm.set_script(_script(FAKE_SM))
	game.add_child(sm)
	game.structures = sm
	for k in IDS.size():
		var s := StructureManager.Structure.new()
		s.def = Registry.structure(IDS[k])
		sm.add_child(s)
		var a := TAU * float(k) / float(IDS.size()) + 0.3
		var r := 30.0 + 8.0 * float(k % 3)
		s.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		sm.items.append(s)
	return {"map": map, "game": game, "sm": sm}


func _signs(w: Dictionary) -> Node3D:
	var f: Node3D = auto_free(SIGNS.new())
	add_child(f)
	f.setup(w["game"], w["map"])
	return f


## The mean colour of a PNG on disk (the source file: a new texture is not imported until the lead imports it), by
## halving it down to 32 px.
func _png_mean(path: String) -> Color:
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))).is_equal(OK)
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() > 32:
		img.shrink_x2()
	var sum := Vector3.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
	sum /= float(img.get_width() * img.get_height())
	return Color(sum.x, sum.y, sum.z)


# ---------------------------------------------------------------- the sand

func test_the_sand_and_the_river_bed_are_lighter_and_less_orange() -> void:
	# pass 53's sand averaged (203, 162, 102): value 0.80, saturation 0.49, hue 35.6 degrees
	var sand := _png_mean("res://art/env/sand.png")
	assert_float(sand.v).is_greater(0.81)
	assert_float(sand.s).is_less(0.45)
	assert_float(sand.h * 360.0).is_between(33.0, 40.0)
	# the river bed was (158, 104, 59): value 0.62, saturation 0.63
	var bed := _png_mean("res://art/env/cracked.png")
	assert_float(bed.v).is_greater(0.65)
	assert_float(bed.s).is_less(0.6)
	assert_float(bed.v).is_less(sand.v)
	# the tool says so too (it rewrites both PNGs the same way every run); pass 61 moved both again (the sand lighter, the
	# river bed the sand a little browner: pass61_map_test pins the new palettes)
	var py := _repo_file("tools/gen_textures.py")
	assert_bool(py.contains("(206, 160, 104) -> (246, 214, 156)")).is_true()
	assert_bool(py.contains("(142, 96, 58) -> (206, 152, 98)")).is_true()


func test_red_canyon_sets_the_ground_tones_and_knows_its_water_level() -> void:
	Run.forced_map_seed = 5
	Run.end()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	# the flat tones the textures are calmed towards: the shader's defaults, and the map's exports set on the material
	var shader: Shader = load("res://core/shaders/terrain_painted.gdshader")
	# (pass 61 moved both again: pass61_map_test pins the new tones)
	assert_bool(shader.code.contains("sand_flat : source_color = vec3(0.90, 0.78, 0.58)")).is_true()
	assert_bool(shader.code.contains("cracked_flat : source_color = vec3(0.80, 0.67, 0.50)")).is_true()
	var sand_c: Color = m.get("sand_color")
	var river_c: Color = m.get("river_color")
	assert_bool(sand_c.is_equal_approx(Color(0.90, 0.78, 0.58))).is_true()
	assert_bool(river_c.is_equal_approx(Color(0.80, 0.67, 0.50))).is_true()
	# lighter and less orange than pass 53's (0.86, 0.68, 0.42) and (0.62, 0.44, 0.30)
	assert_float(sand_c.v).is_greater(Color(0.86, 0.68, 0.42).v)
	assert_float(sand_c.s).is_less(Color(0.86, 0.68, 0.42).s)
	assert_float(river_c.s).is_less(Color(0.62, 0.44, 0.30).s)
	var mat: ShaderMaterial = m.get("_terrain_mat")
	assert_object(mat).is_not_null()
	assert_bool((mat.get_shader_parameter("sand_flat") as Color).is_equal_approx(sand_c)).is_true()
	assert_bool((mat.get_shader_parameter("cracked_flat") as Color).is_equal_approx(river_c)).is_true()
	# the water: its surface is the Oasis disc's height, over the dish's floor, under the shore
	var lc: Vector2 = m.call("lake_center")
	var lr: float = m.call("lake_radius")
	var level: float = m.call("water_level")
	var lake: MeshInstance3D = m.find_child("Oasis", true, false)
	assert_float(level).is_equal_approx(lake.position.y, 0.0001)
	assert_float(level - m.height_at(lc.x, lc.y)).is_between(0.2, 0.6)
	assert_bool(bool(m.call("in_water", Vector3(lc.x, level, lc.y)))).is_true()
	assert_bool(bool(m.call("in_water", Vector3(lc.x + lr * 1.5, level, lc.y)))).is_false()


func test_a_map_without_water_answers_far_below_any_ground() -> void:
	var b := MapBase.new()
	assert_float(b.water_level()).is_less(-100.0)
	b.free()


func test_the_agave_is_walked_through() -> void:
	var pf := PropField.new()
	pf.setup()
	assert_bool(pf.has("agave")).is_true()
	assert_float(pf.radius_of("agave")).is_equal(0.0)
	pf.free()
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/sprites/props/props.json"))
	assert_float(float(man["agave"]["radius"])).is_equal(0.0)
	# gen_props rewrites the manifest from its table, so the table says 0 too
	var py := _repo_file("tools/gen_props.py")
	var line := ""
	for l in py.split("\n"):
		if l.strip_edges().begins_with("\"agave\":"):
			line = l
	assert_bool(line.contains(", 1.3, 0.0, 192, 15, ")).override_failure_message(line).is_true()


# ---------------------------------------------------------------- the signs

func test_the_sign_model_has_a_post_and_an_arm_on_the_posts_axis() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://art/props/sign.glb")
	assert_int(bytes.size()).is_greater(1000)
	assert_int(bytes.decode_u32(0)).is_equal(0x46546C67)     # "glTF"
	var json_len := bytes.decode_u32(12)
	var j: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_len).get_string_from_utf8())
	var names := {}
	for n: Dictionary in j["nodes"]:
		names[str(n["name"])] = n
	assert_bool(names.has("Post") and names.has("Arm")).is_true()
	# the arm's board runs from just behind the post's axis (its origin) to the point at +X, 0.9 m in all
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var arm_mesh: Dictionary = j["meshes"][int(names["Arm"]["mesh"])]
	var mats := {}
	for p: Dictionary in arm_mesh["primitives"]:
		var acc: Dictionary = j["accessors"][int(p["attributes"]["POSITION"])]
		lo = Vector3(minf(lo.x, acc["min"][0]), minf(lo.y, acc["min"][1]), minf(lo.z, acc["min"][2]))
		hi = Vector3(maxf(hi.x, acc["max"][0]), maxf(hi.y, acc["max"][1]), maxf(hi.z, acc["max"][2]))
		mats[str(j["materials"][int(p["material"])]["name"])] = true
	assert_float(hi.x - lo.x).is_equal_approx(0.9, 0.01)
	assert_float(hi.x).is_equal_approx(SIGNS.ARM_X1, 0.01)
	assert_float(lo.x).is_equal_approx(SIGNS.ARM_X0, 0.01)
	assert_float(hi.y - lo.y).is_equal_approx(0.16, 0.01)
	assert_float(absf(hi.y + lo.y)).is_less(0.01)
	assert_bool(mats.has("wood") and mats.has("rim") and mats.has("nail")).is_true()
	# the post: 0.14 m square, 2.6 m tall from its foot
	var post_mesh: Dictionary = j["meshes"][int(names["Post"]["mesh"])]
	var pacc: Dictionary = j["accessors"][int(post_mesh["primitives"][0]["attributes"]["POSITION"])]
	assert_float(float(pacc["max"][1])).is_equal_approx(2.6, 0.01)
	assert_float(float(pacc["min"][1])).is_equal_approx(0.0, 0.01)
	assert_float(float(pacc["max"][0]) - float(pacc["min"][0])).is_equal_approx(0.14, 0.01)
	var py := _repo_file("tools/blender_sign.py")
	assert_bool(py.contains("export_yup=True")).is_true()


func test_four_to_six_signs_stand_far_apart_and_clear() -> void:
	for ms in [54, 7, 1234]:
		var w := _world(ms)
		var map: Node3D = w["map"]
		var before: int = (map.get("obstacles") as Array).size()
		var covers: Array = BarrelField.covers_of(w["game"], map)
		var rings: Array = BarrelField.structure_rings(w["game"])
		var f := _signs(w)
		var spots: PackedVector3Array = f.get("spots")
		assert_int(spots.size()).override_failure_message("seed %d" % ms).is_between(4, 6)
		for a in spots.size():
			var p := Vector2(spots[a].x, spots[a].z)
			for b in range(a + 1, spots.size()):
				assert_float(p.distance_to(Vector2(spots[b].x, spots[b].z))).is_greater_equal(SIGNS.MIN_GAP_RELAXED)
			# off the flats and the start, inside the arena's band, clear of the rings and every cover band
			assert_float(p.length()).is_between(66.0 * SIGNS.R_MIN, 66.0 * SIGNS.R_MAX)
			assert_float(p.length()).is_greater(16.0 * SIGNS.FLATS_CLEAR)
			for g: Vector3 in rings:
				assert_float(p.distance_to(Vector2(g.x, g.y))).is_greater_equal(g.z + SIGNS.STRUCTURE_CLEAR)
			assert_bool(BarrelField.in_cover(covers, p, SIGNS.POST_R)).is_false()
		# a post is a circle the crowd steers round, appended after whatever was there
		assert_int((map.get("obstacles") as Array).size()).is_equal(before + spots.size())


func test_every_arm_points_at_its_structure() -> void:
	var w := _world()
	var f := _signs(w)
	var arms: Array = f.get("arms")
	assert_int(arms.size()).is_greater_equal(4)
	var spots: PackedVector3Array = f.get("spots")
	for rec: Dictionary in arms:
		var node: MeshInstance3D = rec["node"]
		var at: Vector3 = spots[int(rec["sign"])]
		var sp: Vector3 = (rec["structure"] as Node3D).global_position
		var want := Vector2(sp.x - at.x, sp.z - at.z).normalized()
		var x := node.global_transform.basis.x
		var got := Vector2(x.x, x.z).normalized()
		assert_float(absf(rad_to_deg(want.angle_to(got)))).override_failure_message("%s off by %.1f deg" % [rec["text"], rad_to_deg(want.angle_to(got))]).is_less(5.0)
		# the board leans up or down by 8 degrees, never sideways
		assert_float(absf(rad_to_deg(float(rec["tilt"])))).is_equal_approx(SIGNS.TILT_DEG, 0.01)
	# the turn alone: +X turned by yaw_to runs straight at the target
	var from := Vector3(3, 0, -4)
	var to := Vector3(-10, 0, 12)
	var dir := Basis(Vector3.UP, SIGNS.yaw_to(from, to)) * Vector3.RIGHT
	assert_bool(Vector2(dir.x, dir.z).normalized().is_equal_approx(Vector2(to.x - from.x, to.z - from.z).normalized())).is_true()


func test_arms_go_to_the_nearest_structures_bottom_first() -> void:
	var w := _world(7)
	var f := _signs(w)
	var spots: PackedVector3Array = f.get("spots")
	var arms: Array = f.get("arms")
	for k in spots.size():
		var mine: Array = []
		for rec: Dictionary in arms:
			if int(rec["sign"]) == k:
				mine.append(rec)
		assert_int(mine.size()).is_between(1, SIGNS.MAX_ARMS)
		# one arm a structure, the nearest ones, the nearest at the bottom
		var seen := {}
		var last_d := -1.0
		for j in mine.size():
			var rec: Dictionary = mine[j]
			var s: Node3D = rec["structure"]
			assert_bool(seen.has(s)).is_false()
			seen[s] = true
			var d := Vector2(s.global_position.x - spots[k].x, s.global_position.z - spots[k].z).length()
			assert_float(d).is_greater_equal(last_d)
			last_d = d
			assert_float(float(rec["height"])).is_equal_approx(float(SIGNS.ARM_HEIGHTS[j]), 0.001)
			assert_float((rec["node"] as Node3D).position.y).is_equal_approx(float(SIGNS.ARM_HEIGHTS[j]), 0.001)
		# the nearest ones whose bearings lie ARM_APART_DEG apart (pass 54: two boards for one road stacked their names)
		var nearest: Array = f.nearest_unused(spots[k], mine.size(), SIGNS.ARM_APART_DEG)
		for j in mine.size():
			assert_object(mine[j]["structure"]).is_same(nearest[j])
			for i in j:
				var apart := absf(rad_to_deg(angle_difference(float(mine[i]["yaw"]), float(mine[j]["yaw"]))))
				assert_float(apart).is_greater_equal(SIGNS.ARM_APART_DEG - 0.01)
	# every arm's top board stays on the post (2.6 m)
	assert_float(float(SIGNS.ARM_HEIGHTS[SIGNS.ARM_HEIGHTS.size() - 1]) + SIGNS.ARM_H * 0.5).is_less(SIGNS.POST_H)


func test_each_post_is_a_thin_collider() -> void:
	var w := _world()
	var f := _signs(w)
	var spots: PackedVector3Array = f.get("spots")
	var obstacles: Array = (w["map"] as Node3D).get("obstacles")
	for k in spots.size():
		var stand: Node3D = f.get_node("Sign%d" % k)
		var body: StaticBody3D = stand.get_node("Body")
		assert_int(body.collision_layer).is_equal(1)
		var cs: CollisionShape3D = body.get_child(0)
		var shape := cs.shape as CylinderShape3D
		assert_float(shape.radius).is_equal_approx(0.12, 0.001)
		assert_float(shape.height).is_equal_approx(2.6, 0.001)
		assert_float(cs.position.y).is_equal_approx(1.3, 0.001)
		var found := false
		for o: Vector3 in obstacles:
			if Vector2(o.x, o.y).distance_to(Vector2(spots[k].x, spots[k].z)) < 0.001 and is_equal_approx(o.z, 0.2):
				found = true
		assert_bool(found).is_true()
		# nothing of the sign casts a shadow
		for mi in stand.find_children("*", "GeometryInstance3D", true, false):
			assert_int(int((mi as GeometryInstance3D).cast_shadow)).is_equal(int(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))


func test_the_arms_point_and_carry_no_names() -> void:
	# pass 55 (Garry: "Remove the text from signs, just let them be pointers"): no tag on any arm, the word kept in the record
	assert_bool(SIGNS.SHOW_NAMES).is_false()
	for id in Registry.structures.keys():
		assert_bool(SIGNS.SHORT.has(id)).override_failure_message("no sign word for " + str(id)).is_true()
	var odd := StructureManager.Structure.new()
	var d := StructureDef.new()
	d.id = "odd_one"
	d.display_name = "Lonely Totem"
	odd.def = d
	assert_str(SIGNS.short_name(odd)).is_equal("LONELY")
	odd.free()
	for seed_v in [3, 7, 11, 54]:
		var w := _world(seed_v)
		var f := _signs(w)
		assert_int((f.get("arms") as Array).size()).is_greater(0)
		for rec: Dictionary in f.get("arms"):
			assert_int((rec["labels"] as Array).size()).is_equal(0)
			assert_str(str(rec["text"])).is_equal(SIGNS.short_name(rec["structure"]))
		assert_int(f.find_children("*", "Label3D", true, false).size()).is_equal(0)


func test_tags_made_by_hand_still_spread_clear_of_each_other() -> void:
	# the pass-54 layout stays for the day the names come back: two tags at one spot are lifted apart
	var a := Label3D.new()
	var b := Label3D.new()
	for lb: Label3D in [a, b]:
		lb.text = "TELEPORT"
		lb.font_size = SIGNS.LABEL_FONT_PX
		lb.pixel_size = SIGNS.LABEL_EM / float(SIGNS.LABEL_FONT_PX) / SIGNS.SCALE
		lb.position = Vector3(0.3, 1.6, 0.2)
	var lifted: int = SIGNS.spread_tags([{"labels": [a]}, {"labels": [b]}])
	assert_int(lifted).is_equal(1)
	var c := cos(deg_to_rad(SIGNS.CAMERA_PITCH_DEG))
	# pass 61: a height up the post counts STRETCH times in the world
	assert_float(absf(a.position.y - b.position.y) * c * SIGNS.STRETCH).is_greater_equal(SIGNS.tag_height(a))
	a.free()
	b.free()


func test_a_used_structure_blanks_the_arms_that_point_at_it() -> void:
	var w := _world()
	var f := _signs(w)
	var arms: Array = f.get("arms")
	var target: Node3D = arms[0]["structure"]
	assert_int(f.check_used(false)).is_equal(0)
	target.set("used", true)
	var n: int = f.check_used(false)
	assert_int(n).is_greater_equal(1)
	var blanked := 0
	for rec: Dictionary in arms:
		var node: MeshInstance3D = rec["node"]
		if rec["structure"] == target:
			blanked += 1
			assert_bool(bool(rec["blank"])).is_true()
			# the board a shade paler, the arm still there
			assert_bool(node.visible).is_true()
			assert_bool(_wood_colour(node).is_equal_approx(SIGNS.WOOD_SPENT)).is_true()
			assert_float(_wood_colour(node).v).is_greater(SIGNS.WOOD.v)
		else:
			assert_bool(bool(rec["blank"])).is_false()
			assert_bool(_wood_colour(node).is_equal_approx(SIGNS.WOOD)).is_true()
	assert_int(blanked).is_equal(n)
	# a second look changes nothing
	assert_int(f.check_used(false)).is_equal(0)


## The material on an arm's "wood" surface (pass 60: the sign depth ShaderMaterial, its colour in `albedo`; a plain
## StandardMaterial3D only while the shader is missing).
func _wood_material(node: MeshInstance3D) -> Material:
	for i in node.mesh.get_surface_count():
		if SIGNS.surface_key(node.mesh, i) == "wood":
			return node.get_surface_override_material(i)
	return null


func _wood_colour(node: MeshInstance3D) -> Color:
	var m := _wood_material(node)
	if m is ShaderMaterial:
		return (m as ShaderMaterial).get_shader_parameter("albedo")
	return (m as StandardMaterial3D).albedo_color


func test_a_used_structure_pales_its_arms_while_the_game_runs() -> void:
	var w := _world()
	var f := _signs(w)
	var arms: Array = f.get("arms")
	var rec: Dictionary = arms[0]
	(rec["structure"] as Node3D).set("used", true)
	# the field looks every half second
	f._process(SIGNS.POLL + 0.01)
	assert_bool(bool(rec["blank"])).is_true()
	assert_bool(_wood_colour(rec["node"]).is_equal_approx(SIGNS.WOOD_SPENT)).is_true()


func test_a_used_structure_gets_no_arm_and_no_structures_no_signs() -> void:
	var w := _world()
	var sm: Node3D = w["sm"]
	var gone: Node3D = sm.items[0]
	gone.set("used", true)
	var f := _signs(w)
	for rec: Dictionary in f.get("arms"):
		assert_object(rec["structure"]).is_not_same(gone)
	# a game without structures: nothing to point at, so no posts
	var w2 := _world()
	(w2["sm"] as Node3D).items.clear()
	var f2 := _signs(w2)
	assert_int((f2.get("spots") as PackedVector3Array).size()).is_equal(0)
	assert_int(f2.get_child_count()).is_equal(0)


func test_the_same_seed_puts_the_signs_in_the_same_places() -> void:
	var a := _signs(_world(99))
	var b := _signs(_world(99))
	assert_bool((a.get("spots") as PackedVector3Array) == (b.get("spots") as PackedVector3Array)).is_true()
	var c := _signs(_world(100))
	assert_bool((a.get("spots") as PackedVector3Array) == (c.get("spots") as PackedVector3Array)).is_false()


func test_the_meshes_built_without_the_model_face_outwards() -> void:
	for mesh: ArrayMesh in [SIGNS.post_mesh(), SIGNS.arm_mesh()]:
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			assert_int(v.size() % 3).is_equal(0)
			for t in range(0, v.size(), 3):
				# Godot draws clockwise faces: seen from the side the normal points to, the turn is clockwise
				var turn := (v[t + 1] - v[t]).cross(v[t + 2] - v[t]).dot(nrm[t])
				assert_float(turn).is_less(0.0)
	var arm := SIGNS.arm_mesh()
	assert_str(SIGNS.surface_key(arm, 0)).is_equal("wood")
	assert_str(SIGNS.surface_key(arm, 1)).is_equal("rim")
	assert_str(SIGNS.surface_key(SIGNS.post_mesh(), 0)).is_equal("post")
	var box := arm.get_aabb()
	assert_float(box.position.x).is_equal_approx(SIGNS.ARM_X0, 0.001)
	assert_float(box.end.x).is_equal_approx(SIGNS.ARM_X1, 0.001)
	assert_float(SIGNS.post_mesh().get_aabb().end.y).is_equal_approx(SIGNS.POST_H, 0.001)


func test_the_game_puts_the_signs_up_between_the_structures_and_the_barrels() -> void:
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	var s := src.find("structures.setup(self, map")
	var g := src.find("preload(\"res://core/systems/SignField.gd\").spawn(self, map)")
	var b := src.find("barrels.setup(self, map)")
	assert_int(s).is_greater(0)
	assert_int(g).is_greater(s)
	assert_int(b).is_greater(g)


# ---------------------------------------------------------------- the barrels

func test_barrels_keep_out_of_a_structures_cover_and_ring() -> void:
	var w := _world(31)
	var game: Node = w["game"]
	var map: Node3D = w["map"]
	var covers: Array = BarrelField.covers_of(game, map)
	# one band a structure: 1.8 m either side, its height / tan 46 degrees north of the foot
	assert_int(covers.size()).is_equal(IDS.size())
	var sm: Node3D = w["sm"]
	var first: Node3D = sm.items[0]
	var c0: Vector4 = covers[0]
	var cot := 1.0 / tan(deg_to_rad(BarrelField.CAMERA_PITCH_DEG))
	assert_float(c0.x).is_equal_approx(first.global_position.x, 0.001)
	assert_float(c0.y).is_equal_approx(first.global_position.z, 0.001)
	assert_float(c0.z).is_equal_approx(BarrelField.STRUCTURE_HALF_W, 0.001)
	assert_float(c0.w).is_equal_approx(float(first.get("def").height) * cot, 0.001)
	# just behind the painting is covered (the old band never counted: it read a field no structure has)
	var at := Vector2(first.global_position.x, first.global_position.z)
	assert_bool(BarrelField.in_cover(covers, at + Vector2(0.4, -1.5), BarrelField.RADIUS)).is_true()
	assert_bool(BarrelField.in_cover(covers, at + Vector2(0.0, 6.0), BarrelField.RADIUS)).is_false()
	# a whole field: every barrel clear of every band and outside every ring
	var bf: BarrelField = auto_free(BarrelField.new())
	add_child(bf)
	bf.setup(game, map)
	assert_int(bf.pos.size()).is_equal(BarrelField.COUNT)
	var rings: Array = BarrelField.structure_rings(game)
	for k in bf.pos.size():
		var p := Vector2(bf.pos[k].x, bf.pos[k].z)
		assert_bool(BarrelField.in_cover(covers, p, BarrelField.RADIUS)).override_failure_message("barrel %d behind a painting" % k).is_false()
		for g: Vector3 in rings:
			assert_float(p.distance_to(Vector2(g.x, g.y))).is_greater_equal(g.z + BarrelField.RADIUS + BarrelField.RING_CLEAR)


func test_barrels_keep_clear_of_the_signposts() -> void:
	var w := _world(12)
	var f := _signs(w)
	var bf: BarrelField = auto_free(BarrelField.new())
	add_child(bf)
	bf.setup(w["game"], w["map"])
	var spots: PackedVector3Array = f.get("spots")
	assert_int(spots.size()).is_greater_equal(4)
	for k in bf.pos.size():
		for s in spots:
			# the post's circle (0.2 m) plus the barrel's own clearance from any obstacle
			assert_float(Vector2(bf.pos[k].x - s.x, bf.pos[k].z - s.z).length()).is_greater_equal(0.2 + BarrelField.RADIUS + 0.9 - 0.001)


# ---------------------------------------------------------------- the boot splash

func test_the_boot_splash_is_ours() -> void:
	assert_str(str(ProjectSettings.get_setting("application/boot_splash/image"))).is_equal("res://art/ui/splash.png")
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	assert_bool(bg.is_equal_approx(W.PAPER)).is_true()
	assert_bool(bool(ProjectSettings.get_setting("application/boot_splash/show_image"))).is_true()
	assert_int(int(ProjectSettings.get_setting("application/boot_splash/stretch_mode"))).is_equal(1)   # Keep
	assert_int(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time"))).is_equal(0)
	# the picture: 1080 x 1920, paper in the middle and, since pass 58, at the top and the foot too (its ink bands
	# floated inside a 20:9 screen: tests/pass58_boot_test.gd), under 600 KB
	var bytes := FileAccess.get_file_as_bytes("res://art/ui/splash.png")
	assert_int(bytes.size()).is_between(1000, 600 * 1024)
	var img := Image.new()
	assert_int(img.load_png_from_buffer(bytes)).is_equal(OK)
	assert_int(img.get_width()).is_equal(1080)
	assert_int(img.get_height()).is_equal(1920)
	assert_bool(img.get_pixel(40, 300).is_equal_approx(W.PAPER)).is_true()
	assert_bool(img.get_pixel(540, 20).is_equal_approx(W.PAPER)).is_true()
	assert_bool(img.get_pixel(540, 1900).is_equal_approx(W.PAPER)).is_true()
	# Android: Godot's own boot splash off, the system splash in paper with our disc
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://export_presets.cfg")).is_equal(OK)
	assert_bool(bool(cfg.get_value("preset.0.options", "splash_screen/disable_godot_boot_splash", false))).is_true()
	var sbg: Color = cfg.get_value("preset.0.options", "splash_screen/background_color", Color())
	assert_bool(sbg.is_equal_approx(W.PAPER)).is_true()
	var icon := str(cfg.get_value("preset.0.options", "splash_screen/icon", ""))
	assert_bool(FileAccess.file_exists(icon)).override_failure_message(icon).is_true()
	# the first scene after it is paper too, so nothing flashes dark between them
	var boot: Node = load("res://ui/Boot.tscn").instantiate()
	assert_bool((boot.get_node("ColorRect") as ColorRect).color.is_equal_approx(W.PAPER)).is_true()
	boot.free()
