extends GdUnitTestSuite

## Pass 61, lane MAP (Garry: "Change the colouring of the dried up river from brown colouring of the desert to a slightly
## browner shade of the generic desert colour. Keep the topology otherwise." / "Add another type of a patch of greenery.
## This one continuing only bushes, make the bush distribution quite sparse, but the patch itself should be more
## frequent then the trees one. None of the bushes have collision." / "Make the generic desert floor sand material even
## lighter." / "Sign boards should be more tall. As in stretch them on the z axis." / "Change the App Icon. Let's just
## make the sand slightly lighter."): Red Canyon's bush patches, the sand and river tones, the river's course kept, the
## taller signs, the launcher icon's lighter sand.

const SIGNS := preload("res://core/systems/SignField.gd")
const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")
const SEEDS := [3, 5, 7, 11, 54]
const BUSHES := ["desert_bush", "creosote_bush", "dead_shrub"]

## The river's waypoints Red Canyon rolled for map seed 7 before pass 61 (v0.46), to the centimetre: the course is
## Garry's "topology", which the colour change must not move.
const RIVER_7 := [[-65.43, 30.04], [-39.49, 34.11], [-21.14, 23.13], [12.12, 31.0], [27.73, 10.16], [44.94, -15.54], [71.29, -10.08]]

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
const IDS := ["teleport", "uber_magnet", "gold_bank", "hooded_figure", "healing_well", "loot_cache", "shop", "war_drum", "beacon"]


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.forced_map_seed = 0
	Run.end()


func _repo_file(rel: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("..").path_join(rel))


## Red Canyon built for map seed `ms`, as a run builds it.
func _canyon(ms: int) -> MapBase:
	Run.forced_map_seed = ms
	Run.end()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	return m


## The mean colour of an image file on disk (the source PNG), halved down to 32 px; `rect` (fractions) crops first.
func _png_mean(path: String, rect := Rect2(0, 0, 1, 1)) -> Color:
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))).is_equal(OK)
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	img = img.get_region(Rect2i(roundi(rect.position.x * w), roundi(rect.position.y * h), roundi(rect.size.x * w), roundi(rect.size.y * h)))
	var sum := Vector3.ZERO
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
	sum /= float(img.get_width() * img.get_height())
	return Color(sum.x, sum.y, sum.z)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## pass54_world_test's world: a flat map and the nine structures on a ring, for the signs.
func _world(ms: int = 61) -> Dictionary:
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


# ---------------------------------------------------------------- the bush patches

func test_every_seed_lays_more_bush_patches_than_green_stands() -> void:
	var total_patches := 0
	var total_trees := 0
	for ms in SEEDS:
		var m := _canyon(ms)
		var patches: Array = m.call("bush_patches")
		var stands: Array = m.call("green_stands")
		var trees := stands.filter(func(s: Dictionary) -> bool: return s["kind"] == "trees").size()
		assert_int(patches.size()).override_failure_message("seed %d: %d patches" % [ms, patches.size()]).is_between(RED_CANYON.BUSH_PATCHES.x, RED_CANYON.BUSH_PATCHES.y)
		# more patches than stands of any kind, let alone tree stands
		assert_int(patches.size()).is_greater(stands.size())
		assert_int(patches.size()).is_greater(trees)
		total_patches += patches.size()
		total_trees += trees
		m.queue_free()
		await get_tree().process_frame
	assert_int(total_patches).is_greater(total_trees * 2)


func test_a_patch_is_a_few_bushes_spread_thin_and_nothing_else() -> void:
	var pf: PropField = auto_free(PropField.new())
	pf.setup()
	for ms in [5, 7]:
		var m := _canyon(ms)
		var props: PropField = m.get("props")
		var fc := Vector2(m.flats_center.x, m.flats_center.z)
		for p: Dictionary in m.call("bush_patches"):
			var c: Vector2 = p["center"]
			var bushes: Array = p["bushes"]
			assert_int(bushes.size()).is_between(1, RED_CANYON.BUSH_PER_PATCH.y)
			# clear of the flats, the lake's greenery and the river bed
			assert_float((c - fc).length()).is_greater(float(m.get("flats_radius")))
			# (pass 80, lane OASIS: every oasis, and past BUSH_LAKE_RELAX tries a patch may come to BUSH_LAKE_NEAR m + 0.6
			# of its radius off the water instead of 11 + 0.6)
			for l: Dictionary in m.call("lakes"):
				assert_float((c - (l["center"] as Vector2)).length()).is_greater_equal(float(l["radius"]) + RED_CANYON.BUSH_LAKE_NEAR + RED_CANYON.BUSH_PATCH_R * 0.6 - 0.01)
			assert_float(float(m.call("_river_dist", c))).is_greater(float(m.get("river_width")) * 0.5)
			for i in bushes.size():
				var b: Dictionary = bushes[i]
				assert_bool(str(b["id"]) in BUSHES).override_failure_message(str(b["id"])).is_true()
				var at: Vector2 = b["pos"]
				assert_float(at.distance_to(c)).is_less_equal(RED_CANYON.BUSH_PATCH_R + 0.01)
				# sparse: open sand between any two of them
				for j in i:
					var other: Vector2 = (bushes[j] as Dictionary)["pos"]
					assert_float(at.distance_to(other)).is_greater_equal(RED_CANYON.BUSH_SPACING + 0.6 - 0.01)
				# and each one is a painting the field really drew
				var found := false
				for row: Dictionary in props.placed:
					var rp: Vector3 = row["pos"]
					if str(row["id"]) == str(b["id"]) and Vector2(rp.x, rp.z).distance_to(at) < 0.001:
						found = true
				assert_bool(found).is_true()
		m.queue_free()
		await get_tree().process_frame


func test_no_bush_anywhere_has_a_collider_or_an_obstacle_circle() -> void:
	# the manifest: every bush is walked through (radius 0)
	var pf: PropField = auto_free(PropField.new())
	pf.setup()
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/sprites/props/props.json"))
	for id in BUSHES:
		assert_bool(pf.has(id)).override_failure_message(id).is_true()
		assert_float(pf.radius_of(id)).override_failure_message(id).is_equal(0.0)
		assert_float(float(man[id]["radius"])).is_equal(0.0)
	for id in RED_CANYON.BUSH_IDS:
		assert_bool(str(id[0]) in BUSHES).is_true()
	# on the map: no steering circle and no body stands on any bush (the patches' and every other region's)
	var m := _canyon(7)
	var props: PropField = m.get("props")
	var obstacles: Array = m.get("obstacles")
	var bodies: Array = []
	for c in m.get_children():
		if c is StaticBody3D:
			bodies.append(Vector2((c as Node3D).position.x, (c as Node3D).position.z))
	var bush_n := 0
	for row: Dictionary in props.placed:
		if not str(row["id"]) in BUSHES:
			continue
		bush_n += 1
		var rp: Vector3 = row["pos"]
		var at := Vector2(rp.x, rp.z)
		for o: Vector3 in obstacles:
			assert_float(Vector2(o.x, o.y).distance_to(at)).override_failure_message("an obstacle on a %s" % row["id"]).is_greater(0.01)
		for b: Vector2 in bodies:
			assert_float(b.distance_to(at)).override_failure_message("a body on a %s" % row["id"]).is_greater(0.01)
	assert_int(bush_n).is_greater(20)


func test_the_patches_leave_every_other_region_where_it_was() -> void:
	# laid last, so the shared draw that places the oasis, the stands, the river's banks and bed, the rock fields and
	# the lone bushes runs exactly as before them: the patches' bushes are the last paintings placed, in their order
	var m := _canyon(11)
	var props: PropField = m.get("props")
	var in_patches := 0
	for p: Dictionary in m.call("bush_patches"):
		in_patches += (p["bushes"] as Array).size()
	var n := props.placed.size()
	var tail: Array = props.placed.slice(n - in_patches)
	var k := 0
	for p: Dictionary in m.call("bush_patches"):
		for b: Dictionary in p["bushes"]:
			var row: Dictionary = tail[k]
			var rp: Vector3 = row["pos"]
			assert_str(str(row["id"])).is_equal(str(b["id"]))
			assert_float(Vector2(rp.x, rp.z).distance_to(b["pos"])).is_less(0.001)
			k += 1


func test_the_structures_keep_off_the_bush_patches() -> void:
	# a bush has no obstacle circle, so StructureManager keeps its rings BUSH_CLEAR off the patches' bushes by name
	var patches := [{"center": Vector2(30, 0), "radius": 7.0, "bushes": [{"id": "desert_bush", "pos": Vector2(31, 2)}]}]
	assert_bool(StructureManager.clear_of_bushes(Vector2(31, 2 + StructureManager.BUSH_CLEAR - 0.1), patches)).is_false()
	assert_bool(StructureManager.clear_of_bushes(Vector2(31, 2 + StructureManager.BUSH_CLEAR + 0.1), patches)).is_true()
	# a real run's structures: none stands on a patch's bush
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 7, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.3).timeout
	var bushes := 0
	for bp: Dictionary in g.map.call("bush_patches"):
		bushes += (bp["bushes"] as Array).size()
	assert_int(bushes).is_greater(10)
	assert_int(g.structures.items.size()).is_greater(5)
	for s: Node3D in g.structures.items:
		assert_bool(StructureManager.clear_of_bushes(Vector2(s.global_position.x, s.global_position.z), g.map.call("bush_patches"))).is_true()


# ---------------------------------------------------------------- the sand and the dry river

func test_the_sand_is_lighter_and_the_river_is_the_sand_a_little_browner() -> void:
	var m := _canyon(7)
	var sand_c: Color = m.get("sand_color")
	var river_c: Color = m.get("river_color")
	assert_bool(sand_c.is_equal_approx(Color(0.90, 0.78, 0.58))).is_true()
	assert_bool(river_c.is_equal_approx(Color(0.80, 0.67, 0.50))).is_true()
	# lighter than pass 54's sand (0.88, 0.72, 0.48), and paler
	var old_sand := Color(0.88, 0.72, 0.48)
	assert_float(sand_c.get_luminance()).is_greater(old_sand.get_luminance() + 0.04)
	assert_float(sand_c.s).is_less(old_sand.s)
	# the river: the sand's family, a step darker, a touch redder and more saturated (browner), far nearer the sand than
	# the old brown (0.66, 0.50, 0.36) was
	assert_float(river_c.v).is_less(sand_c.v)
	assert_float(river_c.h).is_less(sand_c.h)
	assert_float(river_c.s).is_greater(sand_c.s)
	assert_float(sand_c.h - river_c.h).is_less(0.03)
	var old_river := Color(0.66, 0.50, 0.36)
	assert_float(sand_c.get_luminance() - river_c.get_luminance()).is_less((old_sand.get_luminance() - old_river.get_luminance()) * 0.75)
	# the terrain material carries them, and the shader's defaults say the same
	var mat: ShaderMaterial = m.get("_terrain_mat")
	assert_bool((mat.get_shader_parameter("sand_flat") as Color).is_equal_approx(sand_c)).is_true()
	assert_bool((mat.get_shader_parameter("cracked_flat") as Color).is_equal_approx(river_c)).is_true()
	var shader: Shader = load("res://core/shaders/terrain_painted.gdshader")
	assert_bool(shader.code.contains("sand_flat : source_color = vec3(0.90, 0.78, 0.58)")).is_true()
	assert_bool(shader.code.contains("cracked_flat : source_color = vec3(0.80, 0.67, 0.50)")).is_true()


func test_the_painted_textures_follow() -> void:
	# pass 54's sand averaged (210, 175, 121) (value 0.825, saturation 0.42), its river bed (169, 120, 75)
	var sand := _png_mean("res://art/env/sand.png")
	assert_float(sand.v).is_greater(0.835)
	assert_float(sand.s).is_less(0.36)
	assert_float(sand.h * 360.0).is_between(33.0, 40.0)
	var bed := _png_mean("res://art/env/cracked.png")
	assert_float(bed.v).is_greater(0.75)
	assert_float(bed.v).is_less(sand.v)
	assert_float(bed.s).is_less(0.45)
	assert_float(bed.s).is_greater(sand.s)
	assert_float(absf(bed.h - sand.h) * 360.0).is_less(6.0)
	var py := _repo_file("tools/gen_textures.py")
	assert_bool(py.contains("lerp_color((214, 176, 130), (250, 228, 182)")).is_true()
	assert_bool(py.contains("lerp_color((176, 142, 104), (230, 198, 154), n)")).is_true()


func test_the_river_keeps_its_course() -> void:
	var m := _canyon(7)
	var pts: Array = m.call("river_points")
	var got: Array = []
	for p: Vector2 in pts:
		got.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	assert_int(pts.size()).override_failure_message("river %s" % [got]).is_equal(RIVER_7.size())
	for k in RIVER_7.size():
		var want := Vector2(float(RIVER_7[k][0]), float(RIVER_7[k][1]))
		assert_float((pts[k] as Vector2).distance_to(want)).override_failure_message("river %s" % [got]).is_less(0.011)
	# and the bed is as deep and as wide as it was: the ground at a waypoint inside the arena lies river_depth down
	assert_float(float(m.get("river_depth"))).is_equal(2.0)
	assert_float(float(m.get("river_width"))).is_equal(6.0)


# ---------------------------------------------------------------- the signs

func test_the_signs_stand_taller_and_keep_their_colliders_and_depth() -> void:
	assert_float(SIGNS.STRETCH).is_equal(1.4)
	var w := _world()
	var f := _signs(w)
	var spots: PackedVector3Array = f.get("spots")
	assert_int(spots.size()).is_greater(0)
	for k in spots.size():
		var stand: Node3D = f.get_node("Sign%d" % k)
		var look: Node3D = stand.get_node("Look")
		assert_bool(look.scale.is_equal_approx(Vector3(SIGNS.SCALE, SIGNS.SCALE * SIGNS.STRETCH, SIGNS.SCALE))).is_true()
		# the post drawn STRETCH taller, no wider
		var post: MeshInstance3D = look.get_node("Post")
		var box: AABB = post.global_transform * post.get_aabb()
		assert_float(box.size.y).is_equal_approx(post.get_aabb().size.y * SIGNS.SCALE * SIGNS.STRETCH, 0.01)
		# the collider and the steering circle as before
		var cs: CollisionShape3D = stand.get_node("Body").get_child(0)
		assert_float((cs.shape as CylinderShape3D).height).is_equal_approx(SIGNS.POST_H, 0.001)
		assert_float((cs.shape as CylinderShape3D).radius).is_equal_approx(SIGNS.POST_R, 0.001)
		# every post and arm still wears the depth material, with this sign's foot
		for mi in look.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				var mat := (mi as MeshInstance3D).get_surface_override_material(i)
				if mat == null:
					continue
				assert_bool(SIGNS.depth_material(mat)).is_true()
				assert_bool(((mat as ShaderMaterial).get_shader_parameter("foot") as Vector3).is_equal_approx(spots[k])).is_true()
	# the boards: still pointing at their structures, their lean still TILT_DEG as drawn, their height up the post kept
	for rec: Dictionary in f.get("arms"):
		var node: MeshInstance3D = rec["node"]
		var x := node.global_transform.basis.x
		var shown := rad_to_deg(atan2(x.y, Vector2(x.x, x.z).length()))
		assert_float(absf(shown)).is_equal_approx(SIGNS.TILT_DEG, 0.01)
		var sp: Vector3 = (rec["structure"] as Node3D).global_position
		var at: Vector3 = spots[int(rec["sign"])]
		var want := Vector2(sp.x - at.x, sp.z - at.z).normalized()
		assert_float(absf(want.angle_to(Vector2(x.x, x.z).normalized()))).is_less(deg_to_rad(5.0))
		assert_float(node.position.y).is_equal_approx(float(rec["height"]), 0.001)


func test_tags_still_spread_on_a_stretched_sign() -> void:
	var a := Label3D.new()
	var b := Label3D.new()
	for lb: Label3D in [a, b]:
		lb.text = "TELEPORT"
		lb.font_size = SIGNS.LABEL_FONT_PX
		lb.pixel_size = SIGNS.LABEL_EM / float(SIGNS.LABEL_FONT_PX) / SIGNS.SCALE
		lb.position = Vector3(0.3, 1.6, 0.2)
	assert_int(SIGNS.spread_tags([{"labels": [a]}, {"labels": [b]}])).is_equal(1)
	var c := cos(deg_to_rad(SIGNS.CAMERA_PITCH_DEG))
	# a height up the post counts STRETCH times on the screen, so the lift is just enough, not STRETCH times too much
	var gap := absf(a.position.y - b.position.y) * c * SIGNS.STRETCH
	assert_float(gap).is_greater_equal(SIGNS.tag_height(a))
	assert_float(gap).is_less(SIGNS.tag_height(a) + SIGNS.TAG_GAP + 0.01)
	a.free()
	b.free()


# ---------------------------------------------------------------- the launcher icon

func test_the_icon_sand_is_lighter_and_the_hat_untouched() -> void:
	# v0.46's icon_192.png: the top band of sand averaged (0.892, 0.753, 0.485), the foot (0.816, 0.603, 0.328), a patch of
	# the hat's crown (0.265, 0.161, 0.117)
	var top := _png_mean("res://icon_192.png", Rect2(0, 0, 1, 40.0 / 192.0))
	var foot := _png_mean("res://icon_192.png", Rect2(0, 160.0 / 192.0, 1, 32.0 / 192.0))
	var hat := _png_mean("res://icon_192.png", Rect2(80.0 / 192.0, 80.0 / 192.0, 30.0 / 192.0, 20.0 / 192.0))
	assert_float(top.get_luminance()).is_greater(Color(0.892, 0.753, 0.485).get_luminance() + 0.02)
	assert_float(foot.get_luminance()).is_greater(Color(0.816, 0.603, 0.328).get_luminance() + 0.02)
	# slightly: still sand, never white
	assert_float(top.s).is_greater(0.3)
	assert_float(top.get_luminance()).is_less(Color(0.892, 0.753, 0.485).get_luminance() + 0.12)
	var old_hat := Color(0.265, 0.161, 0.117)
	assert_float(absf(hat.r - old_hat.r) + absf(hat.g - old_hat.g) + absf(hat.b - old_hat.b)).override_failure_message(str(hat)).is_less(0.006)
	# the same picture at every launcher size, the adaptive plate the painting's own mean
	for p in ["res://icon.png", "res://icon_192.png", "res://icon_fg_432.png", "res://icon_bg_432.png"]:
		var img := Image.new()
		assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(p))).is_equal(OK)
	var tool := _repo_file("tools/icon_sand.py")
	assert_bool(tool.contains("icon_src_v046.png")).is_true()
