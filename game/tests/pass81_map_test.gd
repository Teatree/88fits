extends GdUnitTestSuite

## Pass 81, lane MAP (Garry: "1. Make the water look more like water. Maybe a cheap (in terms of performance) shader.
## 2. Make the sand texture a bit better. Bit more like what it looks like in MEGABONK. 3. Do a bit of a ground texture
## shading around the water. Basically make it look more natural, like an oasis. 4. The radial animation thing that
## plays under the structures has a black line. Can you remove it."):
##  - every lake is drawn with one water shader (core/shaders/water_lake.gdshader): no screen or depth reads, a handful of
##    samples of one small noise texture, the disc's top cap only (its UV tells the shader the radius);
##  - the oasis ground: RedCanyon.oasis_wet in the terrain's vertex alpha (wet at the water, gone a few metres out, a
##    ragged edge), every terrain corner its own colour (the metre checker gone), the terrain shader shading it;
##  - the sand: a painting made tileable at the old palette's mean colour, mipmapped;
##  - the structures' progress pie has no dark clock hand any more.

const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")
const WATER := "res://core/shaders/water_lake.gdshader"
const TERRAIN := "res://core/shaders/terrain_painted.gdshader"
const LAUNCH := "user://debug_launch.json"


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	get_tree().paused = false
	Run.forced_map_seed = 0
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _canyon(ms: int) -> MapBase:
	Run.forced_map_seed = ms
	Run.end()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	return m


func _repo_file(rel: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("..").path_join(rel))


# ---------------------------------------------------------------- 1. the water

func test_every_lake_is_drawn_with_the_one_water_shader() -> void:
	for ms in [5, 88]:
		var m := _canyon(ms)
		var lakes: Array = m.call("lakes")
		var first: Material = null
		for k in lakes.size():
			var node: MeshInstance3D = m.find_child("Oasis" if k == 0 else "Oasis%d" % (k + 1), true, false)
			assert_object(node).is_not_null()
			var mat := node.material_override as ShaderMaterial
			assert_object(mat).override_failure_message("seed %d lake %d is not the water shader" % [ms, k]).is_not_null()
			assert_str(mat.shader.resource_path).is_equal(WATER)
			# under the ground marks, as the flat colour was
			assert_int(mat.render_priority).is_equal(-10)
			assert_object(mat.get_shader_parameter("noise_tex")).is_not_null()
			if first == null:
				first = mat
			# one material for every lake
			assert_bool(mat == first).is_true()
		assert_object(m.get("_water_mat")).is_same(first)


func test_the_water_shader_is_cheap() -> void:
	var code: String = (load(WATER) as Shader).code
	for bad in ["SCREEN_TEXTURE", "DEPTH_TEXTURE", "hint_screen_texture", "hint_depth_texture", "hint_normal_roughness_texture"]:
		assert_bool(code.contains(bad)).override_failure_message("the water reads the screen: " + bad).is_false()
	# a handful of samples of one small texture, nothing lit
	assert_int(code.count("texture(")).is_less_equal(4)
	assert_bool(code.contains("unshaded")).is_true()
	assert_bool(code.contains("depth_draw_never")).is_true()
	var tex := load(RED_CANYON.NOISE_TEX) as Texture2D
	assert_int(tex.get_width()).is_less_equal(256)
	assert_int(tex.get_height()).is_less_equal(256)


func test_the_disc_cap_maps_its_radius_onto_uv_as_the_shader_reads_it() -> void:
	# the shader takes the normalised radius from the top cap's UV, (0.25, 0.75) +- 0.25, and drops the sides (v < 0.5)
	# and the bottom cap (u > 0.5): if Godot's CylinderMesh ever maps it otherwise, the water loses its shore
	var m := _canyon(5)
	var node: MeshInstance3D = m.find_child("Oasis", true, false)
	var cm := node.mesh as CylinderMesh
	var arr: Array = cm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var tops := 0
	for i in verts.size():
		var v := verts[i]
		var uv := uvs[i]
		if norms[i].y > 0.9:
			tops += 1
			assert_float(uv.x).is_less_equal(0.5001)
			assert_float(uv.y).is_greater_equal(0.4999)
			var rn := (uv - Vector2(0.25, 0.75)).length() * 4.0
			assert_float(rn).is_equal_approx(Vector2(v.x, v.z).length() / cm.top_radius, 0.002)
		elif norms[i].y < -0.9:
			assert_float(uv.x).is_greater_equal(0.4999)
		else:
			assert_float(uv.y).is_less_equal(0.5001)
	assert_int(tops).is_greater(cm.radial_segments)


func test_stage_three_reddens_the_water_too() -> void:
	var m := _canyon(5)
	m.call("_apply_hell", 1.0)
	var mat: ShaderMaterial = m.get("_water_mat")
	assert_float(float(mat.get_shader_parameter("hell"))).is_equal_approx(1.0, 0.001)
	m.call("_apply_hell", 0.0)
	assert_float(float(mat.get_shader_parameter("hell"))).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------- 3. the oasis ground

func test_the_oasis_ground_lies_round_every_lake_with_a_ragged_edge() -> void:
	for ms in [5, 7, 88]:
		var m := _canyon(ms)
		for l: Dictionary in m.call("lakes"):
			var c: Vector2 = l["center"]
			var r: float = l["radius"]
			var reach: float = RED_CANYON.OASIS_REACH + RED_CANYON.OASIS_REACH_PER_R * r
			var far: float = r + reach + RED_CANYON.OASIS_WOBBLE + 0.5
			var mid := PackedFloat32Array()
			for a in range(24):
				var d := Vector2.from_angle(TAU * a / 24.0)
				# wet at the water's edge and under it, dry well past the reach
				assert_float(float(m.call("oasis_wet", c + d * r * 0.5))).is_equal_approx(1.0, 0.001)
				assert_float(float(m.call("oasis_wet", c + d * (r + RED_CANYON.OASIS_WET_TO * 0.5)))).is_equal_approx(1.0, 0.001)
				var nearest := INF
				for o: Dictionary in m.call("lakes"):
					nearest = minf(nearest, (c + d * far).distance_to(o["center"]) - float(o["radius"]) - RED_CANYON.OASIS_REACH - RED_CANYON.OASIS_REACH_PER_R * float(o["radius"]) - RED_CANYON.OASIS_WOBBLE)
				if nearest > 0.0:
					assert_float(float(m.call("oasis_wet", c + d * far))).is_equal(0.0)
				mid.append(float(m.call("oasis_wet", c + d * (r + reach * 0.55))))
			# not a ring: half way out it is wetter on some sides than on others
			var lo := 1.0
			var hi := 0.0
			for v in mid:
				lo = minf(lo, v)
				hi = maxf(hi, v)
			assert_float(hi - lo).override_failure_message("seed %d: the oasis edge is a perfect ring" % ms).is_greater(0.2)
		# and nothing of it far from every lake
		if _far_from_lakes(m, Vector2(0, 8)):
			assert_float(float(m.call("oasis_wet", Vector2(0, 8)))).is_less(0.001)


func _cdiff(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func _far_from_lakes(m: MapBase, p: Vector2) -> bool:
	for l: Dictionary in m.call("lakes"):
		if p.distance_to(l["center"]) < float(l["radius"]) * 3.0 + 6.0:
			return false
	return true


func test_every_terrain_corner_carries_its_own_colour() -> void:
	# one flat colour a quad drew a metre checker over the sand and steps round the lakes; now the colour (with the oasis
	# ground in its alpha) is the grid point's own, shared by every triangle meeting there
	var m := _canyon(5)
	var terr: MeshInstance3D = m.find_child("Terrain", true, false)
	var arr: Array = (terr.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var seen := {}
	var checked := 0
	var wet_corners := 0
	var n: int = idx.size() if idx.size() > 0 else verts.size()
	for k in range(0, n, 7):
		var i: int = idx[k] if idx.size() > 0 else k
		var v := verts[i]
		var key := Vector2i(roundi(v.x * 4.0), roundi(v.z * 4.0))
		if seen.has(key):
			assert_float(_cdiff(seen[key], cols[i])).override_failure_message("two colours at %s" % [key]).is_less(0.002)
		else:
			seen[key] = cols[i]
			# the vertex colour is kept in 8 bits a channel, 0 to 1 (the shade's 1.15 tops out at 1, as it always did)
			var want: Color = (m.call("_color_at", v.x, v.z, v.y) as Color).clamp()
			assert_float(_cdiff(want, cols[i])).is_less(0.02)
			checked += 1
			if cols[i].a > 0.9:
				wet_corners += 1
	assert_int(checked).is_greater(1000)
	assert_int(wet_corners).is_greater(10)


func test_the_terrain_shader_shades_the_oasis_and_varies_the_sand() -> void:
	var code: String = (load(TERRAIN) as Shader).code
	assert_bool(code.contains("uniform sampler2D noise_tex")).is_true()
	assert_bool(code.contains("v_col.a")).is_true()
	# the shades are tunable uniforms
	for u in ["oasis_damp", "oasis_wet", "oasis_grass", "macro_strength"]:
		assert_bool(code.contains("uniform") and code.contains(u)).is_true()
	var m := _canyon(5)
	var mat: ShaderMaterial = m.get("_terrain_mat")
	assert_object(mat.get_shader_parameter("noise_tex")).is_not_null()


# ---------------------------------------------------------------- 2. the sand

func test_the_sand_is_the_painting_tiled_at_the_old_colour_and_mipmapped() -> void:
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes("res://art/env/sand.png"))).is_equal(OK)
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	# it tiles: the wrap is no harder a step than any two neighbouring columns or rows (and none down the middle)
	var wrap := 0.0
	var adj := 0.0
	var mid := 0.0
	var wrap_y := 0.0
	for y in range(0, h, 2):
		wrap += _diff(img.get_pixel(0, y), img.get_pixel(w - 1, y))
		adj += _diff(img.get_pixel(100, y), img.get_pixel(101, y))
		mid += _diff(img.get_pixel(w / 2 - 1, y), img.get_pixel(w / 2, y))
	for x in range(0, w, 2):
		wrap_y += _diff(img.get_pixel(x, 0), img.get_pixel(x, h - 1))
	assert_float(wrap).is_less(adj * 2.0)
	assert_float(mid).is_less(adj * 2.0)
	assert_float(wrap_y).is_less(adj * 2.0)
	# no stripes left: its light and dark is calm (the old sand's luminance spread was about 0.1)
	var lum := PackedFloat32Array()
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			lum.append(img.get_pixel(x, y).get_luminance())
	var mean := 0.0
	for v in lum:
		mean += v
	mean /= lum.size()
	var sd := 0.0
	for v in lum:
		sd += (v - mean) * (v - mean)
	sd = sqrt(sd / lum.size())
	assert_float(sd).is_less(0.07)
	# the tool says so, and keeps the source painting beside it
	var py := _repo_file("tools/gen_textures.py")
	assert_bool(py.contains("sand_klein_s8102.png")).is_true()
	assert_bool(FileAccess.file_exists(ProjectSettings.globalize_path("res://").path_join("../tools/art_src/sand_klein_s8102.png"))).is_true()
	# the ground's textures and the noise are mipmapped (the far sand no longer shimmers)
	for f in ["sand", "cracked", "redrock", "noise_rgb"]:
		var imp := FileAccess.get_file_as_string("res://art/env/%s.png.import" % f)
		assert_bool(imp.contains("mipmaps/generate=true")).override_failure_message(f + " has no mipmaps").is_true()


func _diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


# ---------------------------------------------------------------- 4. the structures' ring

func _launch(d: Dictionary) -> void:
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func test_the_progress_pie_has_no_dark_hand() -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false})
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var sm: StructureManager = g.structures
	var here: Vector3 = g.player.global_position + Vector3(5, 0, 0)
	here.y = g.map.height_at(here.x, here.z)
	var s: StructureManager.Structure = sm._spawn(Registry.structure("loot_cache"), here)
	assert_object(s.hand).is_null()
	# the hero stands in its ring until the pie is part full
	g.player.global_position = here + Vector3(0.3, 0, 0.3)
	var waited := 0.0
	while waited < 3.0 and s.progress < 0.4:
		await get_tree().process_frame
		g.player.global_position = here + Vector3(0.3, 0, 0.3)
		waited += get_process_delta_time()
	assert_float(s.progress).is_greater(0.2)
	assert_bool(s.pie.visible).is_true()
	assert_object(s.hand).is_null()
	# nothing near-black drawn on the ground by the manager
	for c in sm.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).visible:
			var mat := (c as MeshInstance3D).material_override as StandardMaterial3D
			if mat:
				assert_float(mat.albedo_color.get_luminance()).override_failure_message("a dark mark: %s" % [mat.albedo_color]).is_greater(0.2)
	assert_bool(_repo_file("game/core/systems/StructureManager.gd").contains("s.hand = MeshInstance3D.new()")).is_false()
