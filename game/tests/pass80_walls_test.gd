extends GdUnitTestSuite

## Pass 80, lane WALLS (Garry: "Let's make the edges of the map just sand instead of that dark orange stuff, that
## orange-dark stuff should be behind the walls. Also the textures on the mountains behind the walls look too low res and
## walls don't have any proper textures to begin with. Make the walls look like sandstone castle walls (but western),
## instead of what they are now." and "There is some z-fighting on the sign 3d. Fix it"): the ground inside the wall is
## sand to the wall's foot and the red rock lies only outside it (RedCanyon.rock_weight); the cliff rings wear a hi-res
## rock painting on their own UVs in metres (CanyonWalls.ridge, art/env/cliff_rock.png); the boundary is a western
## sandstone fort wall (CanyonWalls.fort_wall, art/env/fort_wall.png) on the same footprint, with the fence and no
## collider of its own; the map's wall_colors keys (stone, light, cap, riser, beams) are what it is drawn in; the sign's
## depth keeps the ground's share of its own depth (sign_depth.gdshader squash_h) and its nails stand clear of the wood.

const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")
const WALLS := preload("res://world/maps/red_canyon/CanyonWalls.gd")
const SIGNS := preload("res://core/systems/SignField.gd")


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()
	Run.forced_map_seed = 0


## Red Canyon built for a run on `mapdef` (the registry's own by default) with seed `ms`.
func _canyon(ms: int, mapdef: MapDef = null) -> Node3D:
	Run.forced_map_seed = ms
	Run.end()
	var md: MapDef = mapdef if mapdef else Registry.map("red_canyon")
	Run.start(Registry.character("astro"), md)
	var m: Node3D = auto_free((md.scene as PackedScene).instantiate())
	add_child(m)
	return m


## The registry's Red Canyon with its own timeline copy carrying `walls` (the registry is never touched).
func _map_with(walls: Dictionary) -> MapDef:
	var md: MapDef = Registry.map("red_canyon").duplicate()
	md.timeline = md.timeline.duplicate()
	md.timeline.wall_colors = walls
	return md


func _fort(m: Node3D) -> Node3D:
	for c in m.get_children():
		if c is Node3D and (c as Node).get_node_or_null("Wall") != null and (c as Node).get_node_or_null("Posts") != null:
			return c
	return null


func _ridges(m: Node3D) -> Array:
	var out: Array = []
	for c in m.get_children():
		var mi := c as MeshInstance3D
		if mi and mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).albedo_texture != null:
			out.append(mi)
	return out


func _mean(img: Image, step: int = 8) -> Color:
	var s := Color(0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			s += img.get_pixel(x, y)
			n += 1
	return s / float(n)


# ---------------------------------------------------------------- sand to the wall

func test_the_ground_inside_the_wall_is_sand_and_the_rock_lies_outside() -> void:
	for ms in [7, 11, 1234]:
		var m := _canyon(ms)
		var r: float = m.arena_radius
		var t := m.get_node("Terrain") as MeshInstance3D
		var arr: Array = (t.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var inside := 0
		var outside := 0
		for k in range(0, verts.size(), 3):
			var d := Vector2(verts[k].x, verts[k].z).length()
			# each quad's colour is its first corner's; the corner inside the wall's footprint by a metre: sand
			if d < r - 1.0:
				assert_float(cols[k].b).override_failure_message("seed %d: rock at %.1f m" % [ms, d]).is_equal(0.0)
				inside += 1
			elif d > r + 1.5:
				assert_float(cols[k].b).override_failure_message("seed %d: sand at %.1f m" % [ms, d]).is_equal(1.0)
				outside += 1
		assert_int(inside).is_greater(10000)
		assert_int(outside).is_greater(500)


func test_rock_weight_turns_at_the_wall() -> void:
	var m := _canyon(7)
	var r: float = m.arena_radius
	for a in [0.0, 1.0, 2.5, 4.0, 5.5]:
		var dir := Vector2(cos(a), sin(a))
		assert_float(m.rock_weight(dir * (r - 0.5))).is_equal(0.0)
		assert_float(m.rock_weight(dir * r)).is_equal(0.0)
		assert_float(m.rock_weight(dir * (r + RED_CANYON.ROCK_FROM + 0.01))).is_equal(1.0)
		assert_float(m.rock_weight(dir * 20.0)).is_equal(0.0)
	# the rim still rises to the wall (the sand drifted against it) and its bumps are soft
	assert_float(m.get("rim_bumps")).is_less(1.2)
	var foot := 0.0
	var mid := 0.0
	for k in range(24):
		var a := TAU * k / 24.0
		foot += m.height_at(cos(a) * (r - 1.5), sin(a) * (r - 1.5))
		mid += m.height_at(cos(a) * 30.0, sin(a) * 30.0)
	assert_float(foot / 24.0).is_greater(mid / 24.0 + 1.0)


# ---------------------------------------------------------------- the paintings

func test_the_paintings_exist_hi_res_mipmapped_and_grey_on_average() -> void:
	for want in [[WALLS.CLIFF_TEX, 2048], [WALLS.WALL_TEX, 1024]]:
		var tex: Texture2D = load(str(want[0]))
		assert_object(tex).override_failure_message(str(want[0])).is_not_null()
		assert_int(tex.get_width()).is_equal(int(want[1]))
		assert_int(tex.get_height()).is_equal(int(want[1]))
		var img := tex.get_image()
		# VRAM-compressed with mipmaps (a phone keeps a quarter of the memory; no shimmer far off)
		assert_bool(img.has_mipmaps()).override_failure_message(str(want[0]) + " has no mipmaps").is_true()
		assert_bool(img.is_compressed()).override_failure_message(str(want[0]) + " is not VRAM compressed").is_true()
		var src := Image.new()
		assert_int(src.load_png_from_buffer(FileAccess.get_file_as_bytes(str(want[0])))).is_equal(OK)
		var mean := _mean(src)
		# grey on average, so a colour key is the colour drawn (times the painting's light and dark)
		assert_float(maxf(maxf(mean.r, mean.g), mean.b) - minf(minf(mean.r, mean.g), mean.b)).is_less(0.03)
		assert_float(mean.v).is_between(0.6, 0.9)
		# real detail: the painting is not a soft gradient (pass 79's sandstone bands were)
		var dev := 0.0
		var n := 0
		for y in range(0, src.get_height() - 4, 16):
			for x in range(0, src.get_width() - 4, 16):
				dev += absf(src.get_pixel(x, y).get_luminance() - src.get_pixel(x + 3, y).get_luminance())
				n += 1
		assert_float(dev / n).override_failure_message("%s: %f" % [want[0], dev / n]).is_greater(0.02)


func test_the_cliffs_wear_the_rock_painting_in_metres() -> void:
	var m := _canyon(7)
	var ridges := _ridges(m)
	assert_int(ridges.size()).is_equal(3)
	for k in ridges.size():
		var mi: MeshInstance3D = ridges[k]
		var mat := mi.material_override as StandardMaterial3D
		assert_str(mat.albedo_texture.resource_path).is_equal(WALLS.CLIFF_TEX)
		assert_bool(mat.uv1_triplanar).is_false()
		assert_int(mat.texture_filter).is_equal(BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)
		var arr: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		assert_int(uv.size()).is_equal(vs.size())
		# up the face the painting runs one tile per CLIFF_TILES metres of height (strata level, nothing stretched)
		var tile: float = WALLS.CLIFF_TILES[k] if k < WALLS.CLIFF_TILES.size() else 14.0
		var checked := 0
		for j in range(0, vs.size(), 3):
			var a := vs[j]
			var b := vs[j + 1]
			if absf(b.y - a.y) > 1.0 and Vector2(b.x - a.x, b.z - a.z).length() < 2.5:
				assert_float(absf(uv[j + 1].y - uv[j].y) * tile).is_equal_approx(absf(b.y - a.y), 0.05)
				checked += 1
		assert_int(checked).is_greater(20)


# ---------------------------------------------------------------- the fort wall

func test_the_fort_wall_keeps_the_footprint_and_the_fence_and_collides_nowhere() -> void:
	var m := _canyon(11)
	var r: float = m.arena_radius
	var fort := _fort(m)
	assert_object(fort).is_not_null()
	# no collider and no obstacle of its own: the hero is stopped by the fence as before
	assert_int(fort.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	for o: Vector3 in (m.get("obstacles") as Array):
		assert_float(Vector2(o.x, o.y).length()).is_less(r - 3.0)
	# the fence: 40 invisible boxes 1.1 m inside the edge, 8 m tall, 0.5 m thick (unchanged)
	var fence := 0
	for c in m.get_children():
		if c is StaticBody3D:
			for s in (c as Node).get_children():
				if s is CollisionShape3D and (s as CollisionShape3D).shape is BoxShape3D and is_equal_approx(((s as CollisionShape3D).shape as BoxShape3D).size.y, 8.0):
					fence += 1
					assert_float(Vector2((c as Node3D).position.x, (c as Node3D).position.z).length()).is_equal_approx(r - 1.1, 0.01)
					assert_float(((s as CollisionShape3D).shape as BoxShape3D).size.z).is_equal_approx(0.5, 0.001)
	assert_int(fence).is_equal(40)
	# the wall's stone stands on the ring from the inner face (r - 0.85) out; the cap course juts a hand over the face,
	# the towers stand out past the outer face; nothing reaches into the arena past the fence's inner side
	var wall := fort.get_node("Wall") as MeshInstance3D
	var vs: PackedVector3Array = (wall.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := 0.0
	var top := -INF
	for v in vs:
		var d := Vector2(v.x, v.z).length()
		lo = minf(lo, d)
		hi = maxf(hi, d)
		top = maxf(top, v.y)
	assert_float(lo).is_greater(r - WALLS.THICK * 0.5 - WALLS.CAP_OUT - 0.01)
	assert_float(lo).is_greater(r - 1.1 - 0.25)
	assert_float(hi).is_less(r + WALLS.THICK * 0.5 + WALLS.TOWER_OUT + WALLS.CAP_OUT + 0.05)
	# the vigas jut in under the cap course (from the face, a tower's a little further out than the wall's) but stop
	# short of the fence's inner side (a MultiMesh's transforms read back as nothing headless: the numbers they come from)
	var vig := fort.get_node("Vigas") as MultiMeshInstance3D
	assert_int(vig.multimesh.instance_count).is_greater(150)
	assert_float(r - WALLS.THICK * 0.5 + WALLS.BATTER * 0.5 - WALLS.VIGA_OUT).is_greater(r - 1.1 - 0.25)
	# its walk stands about two metres over the ground at its foot, the old wall's height (1.9 to 2.75 m)
	for k in range(12):
		var a := TAU * (k + 0.3) / 12.0
		var g: float = m.height_at(cos(a) * (r - 1.0), sin(a) * (r - 1.0))
		var near_top := -INF
		for v in vs:
			var d := Vector2(v.x, v.z)
			if absf(angle_difference(atan2(d.y, d.x), a)) * r < 0.4 and absf(d.length() - (r - WALLS.THICK * 0.5 + WALLS.BATTER - WALLS.CAP_OUT)) < 0.03:
				near_top = maxf(near_top, v.y)
		# (the walk is level over a stretch and steps by STEP where the smoothed ground climbs, so over the very spot it
		# stands 1.5 to 3 m high; the old wall's blocks stood 1.9 to 2.75 m with their battlements)
		if near_top > -INF:
			assert_float(near_top - g).is_between(WALLS.WALK_H - 0.5, WALLS.WALK_H + 1.0)


func test_the_posts_stay_one_multimesh_with_the_skulls() -> void:
	var map = auto_free(RED_CANYON.new())
	var wall: Node3D = map._boundary_wall(60.0, 90)
	var posts: MultiMeshInstance3D = wall.get_node("Posts")
	assert_int(posts.multimesh.instance_count).is_equal(36)
	assert_object(wall.get_node("Wall")).is_not_null()
	assert_object(wall.get_node("Vigas")).is_not_null()
	wall.free()


func test_the_wall_is_drawn_in_the_maps_colours() -> void:
	# a distinct hue a key, so each part's vertex colours (a key times its light and shade) tell which key they are
	var walls := {"near": "#405060", "far": "#304050", "farther": "#203040", "stone": "#C04040", "light": "#40C040",
		"cap": "#4040C0", "riser": "#C0C040", "beams": "#123456"}
	var m := _canyon(7, _map_with(walls))
	var fort := _fort(m)
	var mat := (fort.get_node("Wall") as MeshInstance3D).material_override as StandardMaterial3D
	assert_str(mat.albedo_texture.resource_path).is_equal(WALLS.WALL_TEX)
	assert_bool(mat.vertex_color_use_as_albedo).is_true()
	assert_int(mat.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
	var cols: PackedColorArray = ((fort.get_node("Wall") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var seen := {}
	for c in cols:
		for k in ["stone", "light", "cap", "riser"]:
			var want := Color(str(walls[k]))
			if absf(c.h - want.h) < 0.02 and absf(c.s - want.s) < 0.05:
				seen[k] = int(seen.get(k, 0)) + 1
	for k in ["stone", "light", "cap", "riser"]:
		assert_int(int(seen.get(k, 0))).override_failure_message("no %s on the wall: %s" % [k, seen]).is_greater(50)
	# the stone's faces the most of all
	assert_int(int(seen["stone"])).is_greater(int(seen["cap"]))
	var vig := fort.get_node("Vigas") as MultiMeshInstance3D
	var vm := (vig.multimesh.mesh as CylinderMesh).material as StandardMaterial3D
	assert_bool(vm.albedo_color.is_equal_approx(Color(str(walls["beams"])))).is_true()
	var tints: Array = _ridges(m).map(func(r: MeshInstance3D) -> Color: return (r.material_override as StandardMaterial3D).albedo_color)
	for k: String in ["near", "far", "farther"]:
		var want := Color(str(walls[k]))
		assert_bool(tints.any(func(c: Color) -> bool: return c.is_equal_approx(want))).override_failure_message("no ridge in " + k).is_true()


func test_the_defaults_are_sandstone_and_the_keys_are_the_fort_walls() -> void:
	var walls: Dictionary = RED_CANYON.WALL_COLORS
	assert_array(walls.keys()).contains_exactly_in_any_order(["near", "far", "farther", "stone", "light", "cap", "riser", "beams"])
	var stone: Color = walls["stone"]
	# a warm buff sandstone: red over green over blue, a little saturated, lighter than the cliffs behind it
	assert_bool(stone.r > stone.g and stone.g > stone.b).is_true()
	assert_float(stone.s).is_between(0.12, 0.4)
	assert_float(stone.v).is_greater((walls["near"] as Color).v + 0.15)
	# the trim lighter than the stone, the walk and the shaded sides darker
	assert_float((walls["light"] as Color).v).is_greater(stone.v)
	assert_float((walls["cap"] as Color).v).is_less(stone.v)
	assert_float((walls["riser"] as Color).v).is_less((walls["cap"] as Color).v)
	# the map file names only keys the game reads
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var wc = (d as Dictionary).get("timeline_data", {}).get("wall_colors", {})
	for k in (wc as Dictionary).keys():
		assert_bool(walls.has(k)).override_failure_message("the map file names " + str(k)).is_true()


func test_the_wall_and_the_cliffs_are_scenery_for_the_outlines() -> void:
	var m := _canyon(7)
	var fort := _fort(m)
	assert_bool(SceneryStencil.is_marked((fort.get_node("Wall") as MeshInstance3D).material_override)).is_true()
	var near: MeshInstance3D = _ridges(m)[0]
	assert_bool(SceneryStencil.is_marked(near.material_override)).is_true()


# ---------------------------------------------------------------- the sign

func test_the_sign_keeps_its_own_depth_across_the_ground() -> void:
	var src := FileAccess.get_file_as_string(SIGNS.DEPTH_SHADER)
	var rx := RegEx.create_from_string("uniform float squash_h = ([0-9.]+);")
	var mt := rx.search(src)
	assert_object(mt).is_not_null()
	# enough of the ground's depth that a board's faces lie apart for the depth buffer, little enough that a board
	# pointing at the camera (1.13 m out on the drawn sign) sorts under a hero against the post's south side (0.45 m)
	var sh := float(mt.get_string(1))
	assert_float(sh).is_between(0.15, 0.35)
	var rq := RegEx.create_from_string("uniform float squash = ([0-9.]+);").search(src)
	assert_float(float(rq.get_string(1))).is_less(0.05)
	var board := SIGNS.ARM_X1 * SIGNS.SCALE
	assert_float(board * sh).is_less(0.45 - 0.05)
	# the depth is split into the run over the ground and the height
	assert_str(src).contains("z_run * squash_h + z_up * squash")


func test_the_signs_nail_heads_stand_clear_of_the_board() -> void:
	var bytes := FileAccess.get_file_as_bytes(SIGNS.MODEL)
	assert_int(bytes.decode_u32(0)).is_equal(0x46546C67)
	var json_len := bytes.decode_u32(12)
	var j: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_len).get_string_from_utf8())
	var arm := -1
	for n: Dictionary in j["nodes"]:
		if str(n["name"]) == "Arm":
			arm = int(n["mesh"])
	assert_int(arm).is_greater_equal(0)
	var lo := INF
	var hi := -INF
	for p: Dictionary in j["meshes"][arm]["primitives"]:
		var acc: Dictionary = j["accessors"][int(p["attributes"]["POSITION"])]
		lo = minf(lo, float(acc["min"][2]))
		hi = maxf(hi, float(acc["max"][2]))
	# the board 5 cm thick, the heads at least a centimetre proud on each face (were 4 mm, under the depth buffer's grain)
	assert_float(hi - lo).is_greater(SIGNS.ARM_T + 2.0 * 0.01)


func test_hell_tints_the_fort_wall_with_the_ground() -> void:
	var m := _canyon(7)
	var mat := (_fort(m).get_node("Wall") as MeshInstance3D).material_override as StandardMaterial3D
	assert_bool(mat.albedo_color.is_equal_approx(Color.WHITE)).is_true()
	m.call("_apply_hell", 1.0)
	assert_bool(mat.albedo_color.is_equal_approx(RED_CANYON.HELL_WALL)).is_true()
	m.call("_apply_hell", 0.0)
	assert_bool(mat.albedo_color.is_equal_approx(Color.WHITE)).is_true()
