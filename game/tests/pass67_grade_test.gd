extends GdUnitTestSuite

## Pass 67, lane M (Garry: the 3D weapons "get lost in the background"): every lit material of a weapon's model is graded
## darker and richer (WeaponBehavior.grade_materials) by the map's `weapon_grade` block, a weapon's `params.grade` over
## it; the FX materials (unshaded, see-through), the textured and anything that is not a StandardMaterial3D are left
## alone; one copy per material, so MeshMerge still joins the parts; the companion glow takes its energy from the same
## block; a model of several surfaces (the Spear) is drawn through the ProjectileManager in its graded copies.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_lightning(_points) -> void:
	pass
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
"""

const DIM := Color(0.5, 0.3, 0.1)
const SURF := Color(0.2, 0.6, 0.9)
const GOLD := Color(1.0, 0.79, 0.24)
const GOLD_GLOW := Color(0.6, 0.34, 0.04)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	var b := ProjectileEmitter.new()
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


func _near(a: Color, b: Color, eps := 0.004) -> bool:
	return absf(a.r - b.r) < eps and absf(a.g - b.g) < eps and absf(a.b - b.b) < eps


## A synthetic weapon model: the root itself a mesh in a dim material shared with two parts, an unshaded part, a
## see-through one, a ShaderMaterial, a surface material on the mesh itself, a textured one, a gold that glows.
func _tree() -> Dictionary:
	var root: MeshInstance3D = auto_free(MeshInstance3D.new())
	var dim := StandardMaterial3D.new()
	dim.albedo_color = DIM
	root.mesh = BoxMesh.new()
	root.material_override = dim
	var t := {"root": root, "dim": dim}
	for nm in ["a", "b", "c", "d", "e", "f", "g", "h"]:
		var m := MeshInstance3D.new()
		m.name = nm
		m.mesh = BoxMesh.new()
		root.add_child(m)
		t[nm] = m
	(t["a"] as MeshInstance3D).material_override = dim
	(t["b"] as MeshInstance3D).material_override = dim
	var unsh := StandardMaterial3D.new()
	unsh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	unsh.albedo_color = Color(1, 0.96, 0.7)
	(t["c"] as MeshInstance3D).material_override = unsh
	var see := StandardMaterial3D.new()
	see.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	see.albedo_color = Color(1, 0.38, 0.05, 0.72)
	(t["d"] as MeshInstance3D).material_override = see
	var shader := ShaderMaterial.new()
	(t["e"] as MeshInstance3D).material_override = shader
	var surf := StandardMaterial3D.new()
	surf.albedo_color = SURF
	var fmesh := BoxMesh.new()
	fmesh.material = surf
	(t["f"] as MeshInstance3D).mesh = fmesh
	var textured := StandardMaterial3D.new()
	textured.albedo_texture = PlaceholderTexture2D.new()
	(t["g"] as MeshInstance3D).material_override = textured
	var gold := StandardMaterial3D.new()
	gold.albedo_color = GOLD
	gold.emission_enabled = true
	gold.emission = GOLD_GLOW
	gold.emission_energy_multiplier = 0.35
	(t["h"] as MeshInstance3D).material_override = gold
	t.merge({"unsh": unsh, "see": see, "shader": shader, "surf": surf, "fmesh": fmesh, "textured": textured, "gold": gold})
	return t


## The distinct values (HSV v) of the lit materials on the parts under `root`'s Held node, sorted.
func _held_values(root: Node) -> Array:
	var vals: Array = []
	for m: MeshInstance3D in root.get_node("Held").find_children("*", "MeshInstance3D", true, false):
		var mat: Material = m.material_override if m.material_override else m.get_active_material(0)
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			var v := snappedf((mat as StandardMaterial3D).albedo_color.v, 0.0001)
			if not vals.has(v):
				vals.append(v)
	vals.sort()
	return vals


func _held_meshes(root: Node) -> Array:
	return root.get_node("Held").find_children("*", "MeshInstance3D", true, false)


# ---------------------------------------------------------------- the grade itself

func test_grade_materials_grades_the_lit_materials_once_and_leaves_the_fx_alone() -> void:
	var t := _tree()
	var root: MeshInstance3D = t["root"]
	var dim: StandardMaterial3D = t["dim"]
	# the root, a, b (one material), f's surface and the gold: five swaps
	assert_int(WeaponBehavior.grade_materials(root, {"value": 0.5, "saturation": 1.5})).is_equal(5)
	# one graded copy for the three parts that shared the dim material, the source untouched
	var ga := (t["a"] as MeshInstance3D).material_override as StandardMaterial3D
	assert_object(ga).is_not_null()
	assert_bool(ga != dim).is_true()
	assert_bool((t["b"] as MeshInstance3D).material_override == ga).is_true()
	assert_bool(root.material_override == ga).is_true()
	assert_bool(_near(dim.albedo_color, DIM)).is_true()
	# value halved, saturation x1.5 (clamped at 1), the hue kept, no glow added
	assert_float(ga.albedo_color.v).is_equal_approx(DIM.v * 0.5, 0.002)
	assert_float(ga.albedo_color.s).is_equal_approx(1.0, 0.002)
	assert_float(ga.albedo_color.h).is_equal_approx(DIM.h, 0.005)
	assert_bool(ga.emission_enabled).is_false()
	# the unshaded, the see-through, the shader and the textured are the very same materials
	assert_bool((t["c"] as MeshInstance3D).material_override == t["unsh"]).is_true()
	assert_bool((t["d"] as MeshInstance3D).material_override == t["see"]).is_true()
	assert_bool((t["e"] as MeshInstance3D).material_override == t["shader"]).is_true()
	assert_bool((t["g"] as MeshInstance3D).material_override == t["textured"]).is_true()
	# a surface material goes on as a surface override, its own copy, the mesh's own untouched
	var f := t["f"] as MeshInstance3D
	var gf := f.get_surface_override_material(0) as StandardMaterial3D
	assert_object(gf).is_not_null()
	assert_bool(gf != ga).is_true()
	assert_float(gf.albedo_color.v).is_equal_approx(SURF.v * 0.5, 0.002)
	assert_bool((t["fmesh"] as BoxMesh).material == t["surf"]).is_true()
	assert_bool(_near((t["surf"] as StandardMaterial3D).albedo_color, SURF)).is_true()
	# a gold that glows: albedo and emission graded alike, the same gold, its energy kept
	var gh := (t["h"] as MeshInstance3D).material_override as StandardMaterial3D
	assert_bool(gh != t["gold"]).is_true()
	assert_bool(gh.emission_enabled).is_true()
	assert_float(gh.albedo_color.v).is_equal_approx(GOLD.v * 0.5, 0.002)
	assert_float(gh.emission.v).is_equal_approx(GOLD_GLOW.v * 0.5, 0.002)
	assert_float(gh.emission.h).is_equal_approx(GOLD_GLOW.h, 0.005)
	assert_float(gh.emission_energy_multiplier).is_equal_approx(0.35, 0.0001)
	assert_bool(_near((t["gold"] as StandardMaterial3D).emission, GOLD_GLOW)).is_true()
	# the alpha rides along
	assert_float(ga.albedo_color.a).is_equal_approx(1.0, 0.0001)


func test_the_identity_grade_changes_nothing() -> void:
	var t := _tree()
	var root: MeshInstance3D = t["root"]
	for g in [{"value": 1.0, "saturation": 1.0}, {}, {"glow": 0.3}]:
		assert_int(WeaponBehavior.grade_materials(root, g)).override_failure_message(str(g)).is_equal(0)
	assert_bool((t["a"] as MeshInstance3D).material_override == t["dim"]).is_true()
	assert_bool(root.material_override == t["dim"]).is_true()
	assert_object((t["f"] as MeshInstance3D).get_surface_override_material(0)).is_null()
	assert_bool((t["h"] as MeshInstance3D).material_override == t["gold"]).is_true()
	assert_int(WeaponBehavior.grade_materials(null, {"value": 0.5})).is_equal(0)
	# the grade's maths at 1 / 1 gives a colour back as it was
	assert_bool(_near(WeaponBehavior.grade_color(DIM, 1.0, 1.0), DIM, 0.001)).is_true()
	assert_bool(_near(WeaponBehavior.grade_color(GOLD, 1.0, 1.0), GOLD, 0.001)).is_true()


func test_kind_mesh_copies_a_mesh_only_when_a_surface_wears_an_override() -> void:
	var am := ArrayMesh.new()
	var box := BoxMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	var m0 := StandardMaterial3D.new()
	var m1 := StandardMaterial3D.new()
	am.surface_set_material(0, m0)
	am.surface_set_material(1, m1)
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = am
	assert_bool(WeaponBehavior.kind_mesh(mi) == am).is_true()
	var o1 := StandardMaterial3D.new()
	mi.set_surface_override_material(1, o1)
	var out := WeaponBehavior.kind_mesh(mi)
	assert_bool(out != am).is_true()
	assert_int(out.get_surface_count()).is_equal(2)
	assert_bool(out.surface_get_material(0) == m0).is_true()
	assert_bool(out.surface_get_material(1) == o1).is_true()
	assert_bool(am.surface_get_material(1) == m1).is_true()
	assert_bool(out.get_aabb().is_equal_approx(am.get_aabb())).is_true()


# ---------------------------------------------------------------- where the numbers come from

func test_the_grade_is_the_maps_and_a_weapons_params_grade_wins() -> void:
	var mapdef := Registry.map("red_canyon")
	var wg: Dictionary = mapdef.weapon_grade
	assert_bool(wg.has("value") and wg.has("saturation") and wg.has("glow")).override_failure_message(str(wg)).is_true()
	assert_float(float(wg["value"])).is_between(0.5, 0.99)
	assert_float(float(wg["saturation"])).is_between(1.0, 2.0)
	assert_float(float(wg["glow"])).is_between(0.05, WeaponBehavior.GLOW)
	# the .tres carries the JSON's block (import_json -- only=maps after a hand edit)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var jwg: Dictionary = (raw as Dictionary).get("weapon_grade", {})
	for k in ["value", "saturation", "glow"]:
		assert_float(float(wg[k])).override_failure_message(str(k)).is_equal_approx(float(jwg.get(k, -1.0)), 0.0001)
	# no map: the code's own numbers, and no glow key (pass 53's GLOW keeps the companions)
	var fallback := WeaponBehavior.grade_for(null, {})
	assert_float(float(fallback["value"])).is_equal_approx(float(WeaponBehavior.GRADE["value"]), 0.0001)
	assert_float(float(fallback["saturation"])).is_equal_approx(float(WeaponBehavior.GRADE["saturation"]), 0.0001)
	assert_bool(fallback.has("glow")).is_false()
	assert_float(float(WeaponBehavior.GRADE["value"])).is_less(1.0)
	assert_float(float(WeaponBehavior.GRADE["saturation"])).is_greater_equal(1.0)
	# the map's block over the code's, a weapon's params.grade over the map's, key by key
	var from_map := WeaponBehavior.grade_for(mapdef, {})
	assert_float(float(from_map["value"])).is_equal_approx(float(wg["value"]), 0.0001)
	assert_float(float(from_map["glow"])).is_equal_approx(float(wg["glow"]), 0.0001)
	var own := WeaponBehavior.grade_for(mapdef, {"grade": {"value": 0.5}})
	assert_float(float(own["value"])).is_equal_approx(0.5, 0.0001)
	assert_float(float(own["saturation"])).is_equal_approx(float(wg["saturation"]), 0.0001)
	assert_float(float(own["glow"])).is_equal_approx(float(wg["glow"]), 0.0001)
	# a behaviour in a run reads the run's map, then its own params
	var w := _world()
	var pe := _emitter(w, _inst("boomstick"))
	assert_float(float(pe._grade()["value"])).is_equal_approx(float(wg["value"]), 0.0001)
	var hinst := _inst("boomstick")
	hinst.params["grade"] = {"value": 0.5}
	var half := _emitter(w, hinst)
	assert_float(float(half._grade()["value"])).is_equal_approx(0.5, 0.0001)
	assert_float(float(half._grade()["saturation"])).is_equal_approx(float(wg["saturation"]), 0.0001)


# ---------------------------------------------------------------- through real weapons

func test_a_real_held_gun_ends_darker_than_its_scene_glows_in_the_graded_colour_and_still_merges() -> void:
	var scene: PackedScene = Registry.weapon("boomstick").visual
	var raw: Node3D = auto_free(scene.instantiate())
	var before := _held_values(raw)
	assert_int(before.size()).is_greater_equal(2)
	var w := _world()
	var pe := _emitter(w, _inst("boomstick"))
	var value := float(Run.map.weapon_grade["value"])
	var after := _held_values(pe.visual)
	assert_int(after.size()).is_equal(before.size())
	for i in range(before.size()):
		assert_float(float(after[i])).is_equal_approx(float(before[i]) * value, 0.002)
	# the glow (pass 53) emits the graded colour at the map's energy
	var glow := float(Run.map.weapon_grade["glow"])
	var meshes := _held_meshes(pe.visual)
	assert_int(meshes.size()).is_greater(0)
	for m: MeshInstance3D in meshes:
		var sm := m.material_override as StandardMaterial3D
		assert_object(sm).override_failure_message(str(m.name)).is_not_null()
		assert_bool(sm.emission_enabled).is_true()
		assert_float(sm.emission_energy_multiplier).is_equal_approx(glow, 0.0001)
		assert_bool(_near(sm.emission, Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b))).is_true()
	# the scene's own materials are untouched: a fresh instance is as light as before
	var still := _held_values(auto_free(scene.instantiate()))
	for i in range(before.size()):
		assert_float(float(still[i])).is_equal_approx(float(before[i]), 0.0001)
	# as many parts after the merge as an ungraded gun has: one copy per material, so MeshMerge still joins them; and
	# ungraded and unlit the gun wears the scene's very colours
	var plain_inst := _inst("boomstick")
	plain_inst.params["grade"] = {"value": 1.0, "saturation": 1.0}
	plain_inst.params["glow"] = 0.0
	var plain := _emitter(w, plain_inst)
	assert_int(_held_meshes(plain.visual).size()).is_equal(meshes.size())
	var plain_vals := _held_values(plain.visual)
	for i in range(before.size()):
		assert_float(float(plain_vals[i])).is_equal_approx(float(before[i]), 0.0001)
	# params.grade through a weapon: half as bright
	var half_inst := _inst("boomstick")
	half_inst.params["grade"] = {"value": 0.5}
	var half := _emitter(w, half_inst)
	var half_vals := _held_values(half.visual)
	for i in range(before.size()):
		assert_float(float(half_vals[i])).is_equal_approx(float(before[i]) * 0.5, 0.002)
	# params.glow still wins over the map's energy
	var lit_inst := _inst("boomstick")
	lit_inst.params["glow"] = 0.6
	var lit := _emitter(w, lit_inst)
	for m: MeshInstance3D in _held_meshes(lit.visual):
		assert_float((m.material_override as StandardMaterial3D).emission_energy_multiplier).is_equal_approx(0.6, 0.0001)


func test_a_model_of_several_surfaces_is_shot_in_its_graded_copies() -> void:
	var wd: WeaponDef = Registry.weapon("spear")
	assert_object(wd).is_not_null()
	var raw: Node3D = auto_free(wd.visual.instantiate())
	var src := WeaponBehavior.projectile_source(raw)
	assert_object(src).is_not_null()
	assert_int(src.mesh.get_surface_count()).is_greater(1)
	var shaft := src.mesh.surface_get_material(0) as StandardMaterial3D
	var rest: Color = shaft.albedo_color
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var pe := _emitter(w, _inst("spear"))
	var k: Dictionary = pm.kinds[pe.projectile_kind]
	assert_object((k["mmi"] as MultiMeshInstance3D).material_override).is_null()
	var mesh: Mesh = (k["mm"] as MultiMesh).mesh
	assert_int(mesh.get_surface_count()).is_equal(src.mesh.get_surface_count())
	var value := float(Run.map.weapon_grade["value"])
	for s in range(mesh.get_surface_count()):
		var gm := mesh.surface_get_material(s) as StandardMaterial3D
		var om := src.mesh.surface_get_material(s) as StandardMaterial3D
		assert_object(gm).override_failure_message("surface %d" % s).is_not_null()
		assert_bool(gm != om).is_true()
		assert_float(gm.albedo_color.v).override_failure_message("surface %d" % s).is_equal_approx(om.albedo_color.v * value, 0.002)
	# the kind's mesh is its own copy; the model's shared mesh and materials are as the file has them
	assert_bool(mesh != src.mesh).is_true()
	assert_bool(_near(shaft.albedo_color, rest, 0.0001)).is_true()
	assert_bool(src.mesh.surface_get_material(0) == shaft).is_true()
	# the live model's own parts wear the same copies as surface overrides
	var live := WeaponBehavior.projectile_source(pe.visual)
	for s in range(mesh.get_surface_count()):
		assert_bool(live.get_surface_override_material(s) == mesh.surface_get_material(s)).is_true()
	# ungraded, the kind draws the model's mesh itself
	var plain_inst := _inst("spear")
	plain_inst.params["grade"] = {"value": 1.0, "saturation": 1.0}
	var plain := _emitter(w, plain_inst)
	assert_bool((pm.kinds[plain.projectile_kind]["mm"] as MultiMesh).mesh == src.mesh).is_true()
