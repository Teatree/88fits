extends GdUnitTestSuite

## Pass 105, lane LOOK (Garry, Stage 2 and Stage 3: the structures darkened "quite a bit less", the weapons' 3D models
## not "so dimmed", the projectiles "not at all", the barrels "highlighted a bit", the creatures' shots and the chests
## visible): what the stage's filter darkens is told by the stencil each opaque thing writes (StageStencil's table):
## sand 0, creatures 1, weapons' models 2, shots and chests 3, scenery 4, structures and barrels 5; StageLook draws one
## quad a value at its own share (the filter's `structures`, `items` beside `actors`), none for 3. Stage 1 (no filter)
## draws no quad. The map's colours are read from its file (Garry tunes them): only the rules are pinned.

const LOOK := preload("res://core/systems/StageLook.gd")


func _tl() -> WaveTimeline:
	var md: MapDef = Registry.map("red_canyon")
	return md.timeline if md else null


# ---------------------------------------------------------------- the table

func test_the_stencil_table() -> void:
	assert_int(StageStencil.SAND).is_equal(0)
	assert_int(StageStencil.ACTOR).is_equal(PickupManager.PAINTING_STENCIL)
	assert_int(StageStencil.SCENERY).is_equal(SceneryStencil.VALUE)
	assert_int(StageStencil.STRUCTURE).is_equal(SceneryStencil.STRUCTURE)
	var vals := [StageStencil.SAND, StageStencil.ACTOR, StageStencil.ITEM, StageStencil.CLEAR, StageStencil.SCENERY, StageStencil.STRUCTURE]
	var seen := {}
	for v in vals:
		seen[v] = true
	assert_int(seen.size()).is_equal(vals.size())
	# the outline reads the scenery and the structures (4 <= the stencil): nothing else sits at or above 4
	assert_int(StageStencil.STRUCTURE).is_greater(StageStencil.SCENERY)
	for v in [StageStencil.SAND, StageStencil.ACTOR, StageStencil.ITEM, StageStencil.CLEAR]:
		assert_int(v).is_less(StageStencil.SCENERY)
	var sil := (load("res://core/shaders/enemy_silhouette.gdshader") as Shader).code
	assert_str(sil).contains("stencil_mode read, compare_less_or_equal, %d;" % StageStencil.SCENERY)
	for path in ["res://core/shaders/prop_billboard.gdshader", "res://core/shaders/sign_depth.gdshader"]:
		assert_str((load(path) as Shader).code).override_failure_message(path).contains("stencil_mode write, compare_always, %d;" % StageStencil.SCENERY)
	# the gems and coins still lie only on the sand
	for path in ["res://core/shaders/gem.gdshader", "res://core/shaders/coin.gdshader", "res://core/shaders/gem_glint.gdshader"]:
		assert_str((load(path) as Shader).code).contains("stencil_mode read, compare_equal, 0;")


# ---------------------------------------------------------------- the filter's keys

func test_the_new_shares_read_and_defaulted() -> void:
	# none named: structures at STRUCTURES_DEFAULT, items at ITEMS_DEFAULT (untinted)
	var m: Array = LOOK.filter_mults({"filter": {"color": "#000000", "strength": 0.5}})
	assert_int(m.size()).is_equal(4)
	assert_float((m[0] as Color).r).is_equal_approx(0.5, 0.001)
	assert_float((m[2] as Color).r).is_equal_approx(1.0 - 0.5 * LOOK.STRUCTURES_DEFAULT, 0.001)
	assert_float((m[3] as Color).r).is_equal_approx(1.0 - 0.5 * LOOK.ITEMS_DEFAULT, 0.001)
	assert_float(LOOK.STRUCTURES_DEFAULT).is_between(0.2, 0.4)
	assert_float(LOOK.ITEMS_DEFAULT).is_equal(0.0)
	# named: read, clamped; a bad one: the default
	var n: Array = LOOK.filter_mults({"filter": {"color": "#000000", "strength": 0.8, "structures": 0.5, "items": 0.25}})
	assert_float((n[2] as Color).g).is_equal_approx(1.0 - 0.8 * 0.5, 0.001)
	assert_float((n[3] as Color).g).is_equal_approx(1.0 - 0.8 * 0.25, 0.001)
	var c: Array = LOOK.filter_mults({"filter": {"color": "#000000", "strength": 0.8, "structures": 7, "items": "x"}})
	assert_float((c[2] as Color).b).is_equal_approx(0.2, 0.001)
	assert_float((c[3] as Color).b).is_equal_approx(1.0 - 0.8 * LOOK.ITEMS_DEFAULT, 0.001)
	# no filter: white everywhere
	for col in LOOK.filter_mults({}):
		assert_that(col).is_equal(Color.WHITE)


func test_the_maps_stages() -> void:
	var tl := _tl()
	assert_object(tl).is_not_null()
	var list := LOOK.stage_list_of(tl)
	assert_int(list.size()).is_greater_equal(3)
	# Sundown: no tint, so nothing at all is drawn over it (its look is exactly as before the pass)
	for col in LOOK.filter_mults(list[0]):
		assert_that(col).is_equal(Color.WHITE)
	# Nightfall and Blood Moon: the structures lighter than the world, the items untinted, the shares from the file or the defaults
	for s in [1, 2]:
		var e: Dictionary = list[s]
		var mm: Array = LOOK.filter_mults(e)
		var f: Dictionary = e.get("filter", {})
		var k := float(f.get("strength", 0.0))
		var c: Color = WaveTimeline.color_of(f.get("color", "#ffffff"), Color.WHITE)
		var st := LOOK.share_of(f, "structures", LOOK.STRUCTURES_DEFAULT)
		assert_bool((mm[2] as Color).is_equal_approx(Color.WHITE.lerp(c, k * st))).is_true()
		assert_float((mm[2] as Color).get_luminance()).is_greater_equal((mm[0] as Color).get_luminance())
		if not f.has("items"):
			assert_that(mm[3]).is_equal(Color.WHITE)


# ---------------------------------------------------------------- the quads

func test_the_quads() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var host := Node.new()
	add_child(host)
	var sl: StageLook = LOOK.of(host)
	sl.camera = cam
	sl.set_mults(Color.WHITE, Color.WHITE, 0.0, Color.WHITE, Color.WHITE)
	assert_bool(sl.all_quads().is_empty()).is_true()
	var e := {"filter": {"color": "#3d55c8", "strength": 0.5, "structures": 0.3, "items": 0.0}}
	var m: Array = LOOK.filter_mults(e)
	sl.set_mults(m[0], m[1], 0.0, m[2], m[3])
	var q := sl.all_quads()
	assert_int(q.size()).is_equal(5)
	var want := {"sand": StageStencil.SAND, "scenery": StageStencil.SCENERY, "actors": StageStencil.ACTOR, "structures": StageStencil.STRUCTURE, "items": StageStencil.ITEM}
	for key: String in want:
		var mi := q[key] as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		assert_str(mat.shader.code).override_failure_message(key).contains("stencil_mode read, compare_equal, %d;" % want[key])
		assert_str(mat.shader.code).contains("blend_mul")
		assert_int(mat.render_priority).is_equal(LOOK.PRIORITY)
		assert_object(mi.get_parent()).is_same(cam)
	# no quad reads the shots' and chests' value
	for key: String in q:
		assert_str(((q[key] as MeshInstance3D).material_override as ShaderMaterial).shader.code).not_contains("compare_equal, %d;" % StageStencil.CLEAR)
	# drawn: the sand, the scenery (the same factor), the creatures, the structures; the items' share is 0: hidden
	for key in ["sand", "scenery", "actors", "structures"]:
		assert_bool((q[key] as MeshInstance3D).visible).override_failure_message(key).is_true()
	assert_bool((q["items"] as MeshInstance3D).visible).is_false()
	var got_s: Vector3 = ((q["structures"] as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("mult")
	assert_vector(got_s).is_equal_approx(LOOK.screen_mult(m[2]), Vector3.ONE * 0.0001)
	var got_w: Vector3 = ((q["scenery"] as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("mult")
	assert_vector(got_w).is_equal_approx(LOOK.screen_mult(m[0]), Vector3.ONE * 0.0001)
	# a share of items shows its quad
	sl.set_mults(m[0], m[1], 0.0, m[2], Color(0.9, 0.9, 0.95))
	assert_bool((q["items"] as MeshInstance3D).visible).is_true()
	# the old two-factor call: the structures take their default share of the world's factor, the items none
	sl.set_mults(Color(0.5, 0.5, 0.5), Color(0.8, 0.8, 0.8), 0.0)
	assert_bool(sl.structure_mult.is_equal_approx(Color.WHITE.lerp(Color(0.5, 0.5, 0.5), LOOK.STRUCTURES_DEFAULT))).is_true()
	assert_bool((q["items"] as MeshInstance3D).visible).is_false()
	# back to white (Sundown): every quad hidden
	sl.set_mults(Color.WHITE, Color.WHITE, 0.0)
	for key: String in q:
		assert_bool((q[key] as MeshInstance3D).visible).override_failure_message(key).is_false()
	host.queue_free()
	cam.queue_free()


# ---------------------------------------------------------------- the marking

func test_marked_materials() -> void:
	# a plain material made in code: marked in place
	var m := StandardMaterial3D.new()
	assert_object(StageStencil.marked(m, StageStencil.CLEAR)).is_same(m)
	assert_int(StageStencil.written(m)).is_equal(StageStencil.CLEAR)
	assert_int(m.stencil_compare).is_equal(BaseMaterial3D.STENCIL_COMPARE_ALWAYS)
	# asked again for the same value: itself; for the other: a copy, cached
	assert_object(StageStencil.marked(m, StageStencil.CLEAR)).is_same(m)
	var other := StageStencil.marked(m, StageStencil.ITEM)
	assert_object(other).is_not_same(m)
	assert_int(StageStencil.written(other)).is_equal(StageStencil.ITEM)
	assert_object(StageStencil.marked(m, StageStencil.ITEM)).is_same(other)
	# a see-through one, an added one, a depth-less one: left alone (drawn after the filter already)
	for k in range(3):
		var t := StandardMaterial3D.new()
		if k == 0:
			t.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		elif k == 1:
			t.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		else:
			t.no_depth_test = true
		assert_object(StageStencil.marked(t, StageStencil.CLEAR)).is_same(t)
		assert_int(t.stencil_mode).is_equal(BaseMaterial3D.STENCIL_MODE_DISABLED)
	# the scenery's and the structures' marks are kept
	var sc := SceneryStencil.mark(StandardMaterial3D.new(), SceneryStencil.STRUCTURE)
	assert_object(StageStencil.marked(sc, StageStencil.CLEAR)).is_same(sc)
	assert_int(StageStencil.written(sc)).is_equal(StageStencil.STRUCTURE)
	# a file's material: a copy, the file's resource untouched
	var file_mat := StandardMaterial3D.new()
	file_mat.take_over_path("res://tests/_p105_fake_material.tres")
	var cp := StageStencil.marked(file_mat, StageStencil.ITEM)
	assert_object(cp).is_not_same(file_mat)
	assert_int(file_mat.stencil_mode).is_equal(BaseMaterial3D.STENCIL_MODE_DISABLED)
	assert_int(StageStencil.written(cp)).is_equal(StageStencil.ITEM)
	assert_object(StageStencil.marked(file_mat, StageStencil.ITEM)).is_same(cp)


func test_marked_shaders() -> void:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { ALBEDO = vec3(1.0); }\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	assert_object(StageStencil.marked(sm, StageStencil.CLEAR)).is_same(sm)
	assert_object(sm.shader).is_not_same(sh)
	assert_str(sm.shader.code).contains("stencil_mode write, compare_always, %d;" % StageStencil.CLEAR)
	assert_int(StageStencil.written(sm)).is_equal(StageStencil.CLEAR)
	# one copy a shader and value
	var sm2 := ShaderMaterial.new()
	sm2.shader = sh
	StageStencil.marked(sm2, StageStencil.CLEAR)
	assert_object(sm2.shader).is_same(sm.shader)
	# see-through shaders and shaders with a stencil of their own are left alone
	for code in ["shader_type spatial;\nrender_mode blend_add;\nvoid fragment() { ALBEDO = vec3(1.0); }\n",
			"shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0); ALPHA = 0.5; }\n",
			"shader_type spatial;\nstencil_mode write, compare_always, 1;\nvoid fragment() { ALBEDO = vec3(1.0); }\n"]:
		var s2 := Shader.new()
		s2.code = code
		var m2 := ShaderMaterial.new()
		m2.shader = s2
		StageStencil.marked(m2, StageStencil.CLEAR)
		assert_object(m2.shader).is_same(s2)
	# an alpha scissor is opaque
	assert_bool(StageStencil.shader_is_opaque("shader_type spatial;\nvoid fragment() { ALPHA = 0.5; ALPHA_SCISSOR_THRESHOLD = 0.4; }\n")).is_true()
	# the real ones: the creatures', the gems', the filter's are never marked
	for path in ["res://core/shaders/enemy_billboard.gdshader", "res://core/shaders/gem.gdshader", "res://core/shaders/stage_filter.gdshader"]:
		var m3 := ShaderMaterial.new()
		m3.shader = load(path)
		StageStencil.marked(m3, StageStencil.CLEAR)
		assert_object(m3.shader).override_failure_message(path).is_same(load(path))


func test_tag_and_mark_tree() -> void:
	var root := Node3D.new()
	add_child(root)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.material = StandardMaterial3D.new()
	mi.mesh = box
	root.add_child(mi)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, StandardMaterial3D.new())
	mmi.multimesh.mesh = am
	root.add_child(mmi)
	var inner := Node3D.new()
	inner.set_meta(StageStencil.META, StageStencil.ITEM)
	root.add_child(inner)
	var held := MeshInstance3D.new()
	held.mesh = BoxMesh.new()
	held.material_override = StandardMaterial3D.new()
	inner.add_child(held)
	StageStencil.tag(root, StageStencil.CLEAR)
	assert_int(StageStencil.written(box.material)).is_equal(StageStencil.CLEAR)
	assert_int(StageStencil.written(mmi.multimesh.mesh.surface_get_material(0))).is_equal(StageStencil.CLEAR)
	# a tagged node inside keeps its own value
	assert_int(StageStencil.written(held.material_override)).is_equal(StageStencil.ITEM)
	root.queue_free()


func test_the_roots_by_class() -> void:
	assert_int(StageStencil.value_for(auto_free(ProjectileManager.new()))).is_equal(StageStencil.CLEAR)
	assert_int(StageStencil.value_for(auto_free(PickupManager.new()))).is_equal(StageStencil.CLEAR)
	assert_int(StageStencil.value_for(auto_free(Chest.new()))).is_equal(StageStencil.CLEAR)
	assert_int(StageStencil.value_for(auto_free(Boulder.new()))).is_equal(StageStencil.CLEAR)
	assert_int(StageStencil.value_for(auto_free(Mine.new()))).is_equal(StageStencil.ITEM)
	assert_int(StageStencil.value_for(auto_free(WeaponBehavior.new()))).is_equal(StageStencil.ITEM)
	assert_int(StageStencil.value_for(auto_free(Node3D.new()))).is_equal(-1)
	# the game's own hooks
	var game := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(game).contains("StageStencil.of(self)")
	assert_str(game).contains("StageStencil.tag(pod, StageStencil.CLEAR)")
	assert_str(game).contains("StageStencil.tag(m, StageStencil.CLEAR)")
	assert_str(FileAccess.get_file_as_string("res://core/systems/BillboardSprite.gd")).contains("SceneryStencil.scenery_shader(_mat.shader, SceneryStencil.STRUCTURE)")


## The game's StageStencil marks what is added under a tagged node, materials set after add_child included.
func test_the_watcher() -> void:
	var host := Node.new()
	add_child(host)
	var ss := StageStencil.of(host)
	assert_object(StageStencil.of(host)).is_same(ss)
	var root := Node3D.new()
	root.set_meta(StageStencil.META, StageStencil.CLEAR)
	host.add_child(root)
	var mi := MeshInstance3D.new()
	root.add_child(mi)
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mi.material_override = mat
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(StageStencil.written(mi.material_override)).is_equal(StageStencil.CLEAR)
	# a swap later is caught by the sweep
	var mat2 := StandardMaterial3D.new()
	mi.material_override = mat2
	for k in range(20):
		await get_tree().create_timer(0.1).timeout
		if StageStencil.written(mi.material_override) == StageStencil.CLEAR:
			break
	assert_int(StageStencil.written(mi.material_override)).is_equal(StageStencil.CLEAR)
	host.queue_free()


## Every weapon's visual, under an item root: every opaque material on its meshes writes ITEM (the held guns, the
## companions, the orbiters, the turret, the mines, the Salt).
func test_every_weapon_visual_is_marked() -> void:
	var n := 0
	for wdef: WeaponDef in Registry.weapons.values():
		if wdef.visual == null:
			continue
		var root := Node3D.new()
		root.set_meta(StageStencil.META, StageStencil.ITEM)
		var vis: Node3D = wdef.visual.instantiate()
		root.add_child(vis)
		StageStencil.mark_tree(root)
		for g in root.find_children("*", "MeshInstance3D", true, false):
			var mi := g as MeshInstance3D
			if mi.mesh == null:
				continue
			var mats: Array = []
			if mi.material_override:
				mats.append(mi.material_override)
			else:
				for s in range(mi.mesh.get_surface_count()):
					mats.append(mi.get_active_material(s))
			for m in mats:
				if m != null and StageStencil.is_opaque(m) and StageStencil.written(m) != -2:
					var w := StageStencil.written(m)
					assert_bool(w == StageStencil.ITEM or w >= StageStencil.SCENERY or w == StageStencil.ACTOR).override_failure_message("%s %s writes %d" % [wdef.id, mi.name, w]).is_true()
					n += 1
		root.free()
	assert_int(n).is_greater(20)


## The barrels' hoops: a MultiMesh drawing a GLB's material gets a copy of its mesh wearing a marked copy (pass 105; they
## wrote no stencil at all before), the file's material untouched.
func test_a_multimesh_of_a_files_material_is_marked() -> void:
	var mmi: MultiMeshInstance3D = auto_free(MultiMeshInstance3D.new())
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shared := StandardMaterial3D.new()
	shared.take_over_path("res://tests/_p105_hoops_material.tres")
	am.surface_set_material(0, shared)
	mmi.multimesh.mesh = am
	SceneryStencil.mark_tree(mmi, SceneryStencil.STRUCTURE)
	assert_object(mmi.multimesh.mesh).is_not_same(am)
	assert_bool(SceneryStencil.is_marked(mmi.multimesh.mesh.surface_get_material(0), SceneryStencil.STRUCTURE)).is_true()
	assert_bool(SceneryStencil.is_marked(shared, SceneryStencil.STRUCTURE)).is_false()
	assert_str(FileAccess.get_file_as_string("res://core/systems/BarrelField.gd")).contains("SceneryStencil.mark_tree(mmi, SceneryStencil.STRUCTURE)")
