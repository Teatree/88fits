extends GdUnitTestSuite

## Pass 72, lane SPEC (Garry, 2026-10-13: "Specials should be more noticeable. They should be bigger. They should have way
## more of a chance of dropping a box. They should have higher HP. They should be a limit to how many of them are there";
## "Make the outline of the enemies not appear when they're behind other enemies, only when they're behind environmental
## things"). The special's numbers (x1.5 size, x15 HP, a chest at 0.35) and their fallbacks; at most 3 alive at once (a
## roll past it comes plain, a forced one still comes), the map's max_alive (0 = no limit); the chest on a special's
## death; the stencil rule: scenery writes 2, a creature's outline reads 2, the pickups read 0.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
var toasts: Array = []
var director = null
var no_random_chests := false
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_PICKUPS := """extends Node
var chests := 0
var chest_at: Array = []
func spawn_special(_def, _at, _quiet = false) -> void:
	pass
func spawn_chest(at, _boss = false) -> void:
	chests += 1
	chest_at.append(at)
func spawn(_k, _at, _v = 0.0) -> int:
	return -1
"""

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.level = 1


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at := Vector3(0, 0, 80)) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.set("player", hero)
	var mb := MapBase.new()
	g.add_child(mb)
	g.set("map", mb)
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.set("pickups", pk)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	# colour from the first kill, as a director sets it (a crowd without one spawns plain, pass 71)
	em.colour_after_kills = 0
	return {"g": g, "hero": hero, "em": em, "map": mb, "pk": pk}


## A test creature `id` made from `from` with no jitter, its variance block `vr`; gone after the test.
func _test_def(id: String, from: String, vr: Dictionary) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = vr
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	d.drops = {}
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _row(em: EnemyManager, id: String, n: int, z: float = 0.0) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(em.spawn(id, Vector3(float(k) * 2.5 - 10.0, 0, z)))
	return out


# ---------------------------------------------------------------- 1. the numbers

func test_the_games_special_numbers_are_bigger_tougher_and_drop_chests() -> void:
	assert_float(float(EnemyDef.SPECIAL_DEFAULTS["size"])).is_equal(1.5)
	assert_float(float(EnemyDef.SPECIAL_DEFAULTS["hp"])).is_equal(15.0)
	assert_float(float(EnemyDef.SPECIAL_DEFAULTS["damage"])).is_equal(2.0)
	assert_float(float(EnemyDef.SPECIAL_DEFAULTS["chest_chance"])).is_equal(0.35)
	assert_float(EnemyDef.special_value({}, {}, "chest_chance")).is_equal(0.35)
	assert_float(EnemyDef.special_value({}, {"chest_chance": 0.5}, "chest_chance")).is_equal(0.5)
	assert_float(EnemyDef.special_value({"chest_chance": 0.1}, {"chest_chance": 0.5}, "chest_chance")).is_equal(0.1)
	# the cap: the map's, else the game's 3; 0 or below = no limit
	assert_int(EnemyDef.SPECIAL_MAX_ALIVE).is_equal(3)
	assert_int(EnemyDef.special_max_alive({})).is_equal(3)
	assert_int(EnemyDef.special_max_alive({"max_alive": 5.0})).is_equal(5)
	assert_int(EnemyDef.special_max_alive({"max_alive": 0})).is_equal(-1)


func test_every_creature_in_play_carries_x15_hp_and_x1_5_size() -> void:
	var seen := 0
	for def: EnemyDef in Registry.enemies.values():
		if float(def.variance.get("special_chance", 0.0)) <= 0.0:
			continue
		var d := _json("res://content/enemies/%s/%s.json" % [def.id, def.id])
		var sp: Dictionary = d["variance"]["special"]
		assert_float(float(sp["size"])).override_failure_message(def.id + " size").is_equal(1.5)
		assert_float(float(sp["hp"])).override_failure_message(def.id + " hp").is_equal(15.0)
		assert_float(float(sp["damage"])).override_failure_message(def.id + " damage").is_equal(2.0)
		# no creature names its own chest chance: the map's or the game's 0.35 applies
		assert_bool(sp.has("chest_chance")).override_failure_message(def.id + " chest").is_false()
		# the .tres the game plays says the same
		var dsp: Dictionary = def.variance["special"]
		assert_float(float(dsp["hp"])).is_equal(15.0)
		assert_float(float(dsp["size"])).is_equal(1.5)
		seen += 1
	assert_int(seen).is_greater_equal(21)


func test_red_canyon_caps_them_at_three_and_drops_a_chest_at_0_35() -> void:
	# Garry may change or drop the map's own numbers in the Level Editor: what applies is the map's, else the game's
	var spd: Dictionary = Registry.map("red_canyon").timeline.special_defaults
	var cap := EnemyDef.special_max_alive(spd)
	var chest := EnemyDef.special_value({}, spd, "chest_chance")
	if spd.has("max_alive"):
		assert_int(cap).is_equal(int(spd["max_alive"]) if int(spd["max_alive"]) > 0 else -1)
	else:
		assert_int(cap).is_equal(3)
	if spd.has("chest_chance"):
		assert_float(chest).is_equal(float(spd["chest_chance"]))
	else:
		assert_float(chest).is_equal(0.35)
	# the map file as this pass left it said 3 and 0.35 (read from the file; Garry's own numbers win from here on)
	var tl: Dictionary = _json("res://content/maps/red_canyon/red_canyon.json")["timeline_data"]
	if tl.has("special_defaults") and (tl["special_defaults"] as Dictionary).has("max_alive"):
		assert_float(float(tl["special_defaults"]["max_alive"])).is_greater_equal(0.0)


func test_a_special_by_the_games_defaults_is_x15_hp_and_x1_5_size() -> void:
	var sp := _test_def("p72_sp", "skeleton", {"size": 0.3, "special_chance": 1.0, "special": {"tint": "#8A1428"}})
	var pl := _test_def("p72_pl", "skeleton", {"size": 0.0, "special_chance": 0.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := em.spawn(sp.id, Vector3(0, 0, 0))
	var j := em.spawn(pl.id, Vector3(4, 0, 0))
	assert_int(em.vspecial[i]).is_equal(1)
	assert_int(em.vspecial[j]).is_equal(0)
	assert_float(em.max_hp[i] / em.max_hp[j]).is_equal_approx(15.0, 0.0001)
	assert_float(em.size[i] / sp.size).is_equal_approx(1.5, 0.0001)
	assert_float(em.radius[i] / sp.radius).is_equal_approx(1.5, 0.0001)


# ---------------------------------------------------------------- 2. at most three alive

func test_no_more_than_three_specials_live_at_once_a_roll_past_it_comes_plain() -> void:
	var sp := _test_def("p72_cap", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {"tint": "#1A4A7A"}})
	var w := _world()
	var em: EnemyManager = w["em"]
	var made := _row(em, sp.id, 6)
	var specials := 0
	for i: int in made:
		specials += em.vspecial[i]
	assert_int(specials).is_equal(3)
	assert_int(em.specials_alive).is_equal(3)
	# the first three came special, the rest plain (the plain ones are plain in every way: no glow, the plain HP)
	assert_int(em.vspecial[made[0]] + em.vspecial[made[1]] + em.vspecial[made[2]]).is_equal(3)
	assert_int(em.vspecial[made[3]]).is_equal(0)
	assert_float(em.vglow[made[3]]).is_equal(0.0)
	assert_float(em.max_hp[made[0]] / em.max_hp[made[3]]).is_equal_approx(15.0, 0.0001)
	# one dies: room for one more
	em.damage(made[0], 1e9)
	assert_int(em.specials_alive).is_equal(2)
	var k := em.spawn(sp.id, Vector3(0, 0, 6))
	assert_int(em.vspecial[k]).is_equal(1)
	assert_int(em.specials_alive).is_equal(3)
	# the dying one freed later does not count twice
	em._free(made[0])
	assert_int(em.specials_alive).is_equal(3)
	# one freed while alive (despawned) gives its place back too
	em._free(made[1])
	assert_int(em.specials_alive).is_equal(2)
	# a forced special (a Special swarm) still comes past the cap
	assert_int(em.vspecial[em.spawn(sp.id, Vector3(3, 0, 6))]).is_equal(1)
	assert_int(em.specials_alive).is_equal(3)
	em.force_special = true
	var f := em.spawn(sp.id, Vector3(6, 0, 6))
	em.force_special = false
	assert_int(em.vspecial[f]).is_equal(1)
	assert_int(em.specials_alive).is_equal(4)
	# and the next random roll comes plain
	assert_int(em.vspecial[em.spawn(sp.id, Vector3(9, 0, 6))]).is_equal(0)


func test_the_maps_max_alive_sets_the_cap_and_zero_lifts_it() -> void:
	var sp := _test_def("p72_cap2", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {}})
	var w := _world()
	var em: EnemyManager = w["em"]
	em.special_defaults = {"max_alive": 5}
	var specials := 0
	for i: int in _row(em, sp.id, 8):
		specials += em.vspecial[i]
	assert_int(specials).is_equal(5)
	em.kill_all(false)
	assert_int(em.specials_alive).is_equal(0)
	em.special_defaults = {"max_alive": 0}
	specials = 0
	for i: int in _row(em, sp.id, 8, 5.0):
		specials += em.vspecial[i]
	assert_int(specials).is_equal(8)
	assert_int(em.specials_alive).is_equal(8)


func test_the_cap_leaves_the_dice_alone_below_it() -> void:
	# the same seed rolls the same specials with and without the pass-72 cap while fewer than 3 live: the roll is made
	# first and only then refused past the cap, so nothing else in a run shifts
	var sp := _test_def("p72_dice", "skeleton", {"size": 0.0, "special_chance": 0.3, "special": {}})
	var w := _world()
	var em: EnemyManager = w["em"]
	var got: Array = []
	for cap: int in [3, 0]:
		em.special_defaults = {"max_alive": cap}
		em._rng.seed = 7272
		var seq := ""
		for k in range(40):
			var i := em.spawn(sp.id, Vector3(float(k % 10) * 2.0 - 10.0, 0, float(k / 10) * 2.0))
			seq += str(em.vspecial[i])
			# every one dies at once: never more than one alive, so the cap never binds
			em._free(i)
		got.append(seq)
	assert_str(got[0]).is_equal(got[1])
	assert_bool(got[0].contains("1")).is_true()


# ---------------------------------------------------------------- 3. the chest

func test_a_special_drops_a_chest_at_its_chance() -> void:
	var always := _test_def("p72_c1", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {"chest_chance": 1.0}})
	var never := _test_def("p72_c0", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {"chest_chance": 0.0}})
	var plain := _test_def("p72_cp", "skeleton", {"size": 0.0, "special_chance": 0.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	var pk: Node = w["pk"]
	em.special_defaults = {"max_alive": 0}
	var a := em.spawn(always.id, Vector3(0, 0, 0))
	var at: Vector3 = em.pos[a]
	em.damage(a, 1e9)
	assert_int(int(pk.chests)).is_equal(1)
	assert_bool((pk.chest_at[0] as Vector3).is_equal_approx(at)).is_true()
	assert_int(em.special_chests).is_equal(1)
	em.damage(em.spawn(never.id, Vector3(3, 0, 0)), 1e9)
	em.damage(em.spawn(plain.id, Vector3(6, 0, 0)), 1e9)
	assert_int(int(pk.chests)).is_equal(1)
	# a capture tool holding the kill chests back holds this one back too
	(w["g"] as Node).set("no_random_chests", true)
	em.damage(em.spawn(always.id, Vector3(9, 0, 0)), 1e9)
	assert_int(int(pk.chests)).is_equal(1)
	(w["g"] as Node).set("no_random_chests", false)
	# a special freed without a death (despawned, a stage cleared) drops nothing
	em._free(em.spawn(always.id, Vector3(12, 0, 0)))
	assert_int(int(pk.chests)).is_equal(1)
	# the map's default reaches a creature that names none
	var bare := _test_def("p72_cb", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {}})
	em.special_defaults = {"max_alive": 0, "chest_chance": 1.0}
	em.damage(em.spawn(bare.id, Vector3(15, 0, 0)), 1e9)
	assert_int(int(pk.chests)).is_equal(2)


func test_the_games_chest_chance_is_about_one_in_three() -> void:
	var bare := _test_def("p72_cs", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {}})
	var w := _world()
	var em: EnemyManager = w["em"]
	var pk: Node = w["pk"]
	em._rng.seed = 72
	var n := 400
	for k in range(n):
		var i := em.spawn(bare.id, Vector3(float(k % 20) * 1.5 - 15.0, 0, float(k / 20) * 1.5 - 15.0))
		assert_int(em.vspecial[i]).is_equal(1)
		em.damage(i, 1e9)
		em._free(i)
	var share := float(int(pk.chests)) / float(n)
	assert_float(share).is_between(0.28, 0.42)


# ---------------------------------------------------------------- 4. the outline: only behind scenery

func test_the_outline_reads_the_scenerys_stencil_and_scenery_writes_it() -> void:
	# (pass 105, lane LOOK, re-pinned: the scenery writes 4 and the structures and barrels 5, StageStencil's table; the
	# outline reads 4 <= the stencil, behind either)
	assert_int(SceneryStencil.VALUE).is_equal(4)
	assert_int(SceneryStencil.VALUE).is_not_equal(PickupManager.PAINTING_STENCIL)
	var sil := (load("res://core/shaders/enemy_silhouette.gdshader") as Shader).code
	assert_str(sil).contains("stencil_mode read, compare_less_or_equal, %d;" % SceneryStencil.VALUE)
	assert_str(sil).contains("depth_test_inverted")
	# the creatures and the hero write the painting's 1 (so an outline never shows over them)
	for path in ["res://core/shaders/enemy_billboard.gdshader", "res://core/shaders/sprite_billboard.gdshader"]:
		assert_str((load(path) as Shader).code).contains("stencil_mode write, compare_always, %d;" % PickupManager.PAINTING_STENCIL)
	# the props and the signs write the scenery's 2
	for path in ["res://core/shaders/prop_billboard.gdshader", "res://core/shaders/sign_depth.gdshader"]:
		assert_str((load(path) as Shader).code).override_failure_message(path).contains("stencil_mode write, compare_always, %d;" % SceneryStencil.VALUE)
	# the hero's own outline is as it was: no stencil test, drawn wherever anything stands in front of him
	assert_str((load("res://core/shaders/sprite_silhouette.gdshader") as Shader).code).not_contains("stencil_mode")
	# the pickups still lie under every painting and now every piece of scenery: they draw where nothing wrote
	for path in ["res://core/shaders/gem.gdshader", "res://core/shaders/coin.gdshader", "res://core/shaders/gem_glint.gdshader"]:
		var code: String = (load(path) as Shader).code
		assert_str(code).override_failure_message(path).contains("stencil_mode read, compare_equal, 0;")
		assert_str(code).not_contains("compare_not_equal")
	var cs: Node = auto_free(preload("res://core/systems/CoinStream.gd").new())
	var sm: StandardMaterial3D = cs.call("_shadow_material")
	assert_int(sm.stencil_compare).is_equal(BaseMaterial3D.STENCIL_COMPARE_EQUAL)
	assert_int(sm.stencil_reference).is_equal(0)


func test_painted_structures_and_the_portal_draw_as_scenery() -> void:
	var base: Shader = load("res://core/shaders/sprite_billboard.gdshader")
	# (pass 105, lane LOOK, re-pinned: a painted structure and the portal write SceneryStencil.STRUCTURE, which the stage's
	# filter darkens less and the outline still reads)
	var sc := SceneryStencil.scenery_shader(base, SceneryStencil.STRUCTURE)
	assert_object(sc).is_not_same(base)
	assert_str(sc.code).contains("stencil_mode write, compare_always, %d;" % SceneryStencil.STRUCTURE)
	assert_str(sc.code).not_contains("stencil_mode write, compare_always, %d;" % PickupManager.PAINTING_STENCIL)
	# built once, shared
	assert_object(SceneryStencil.scenery_shader(base, SceneryStencil.STRUCTURE)).is_same(sc)
	# the code is the hero's otherwise
	assert_str(sc.code.replace("compare_always, %d;" % SceneryStencil.STRUCTURE, "compare_always, %d;" % PickupManager.PAINTING_STENCIL)).is_equal(base.code)
	var bs: BillboardSprite = auto_free(BillboardSprite.new())
	bs.scenery = true
	add_child(bs)
	assert_object((bs.material_override as ShaderMaterial).shader).is_same(sc)
	assert_bool(SceneryStencil.is_marked(bs.material_override, SceneryStencil.STRUCTURE)).is_true()
	var hero: BillboardSprite = auto_free(BillboardSprite.new())
	add_child(hero)
	assert_object((hero.material_override as ShaderMaterial).shader).is_same(base)
	assert_bool(SceneryStencil.is_marked(hero.material_override)).is_false()
	# the sources that make them say so
	assert_str(FileAccess.get_file_as_string("res://core/systems/StructureManager.gd")).contains("bs.scenery = true")
	assert_str(FileAccess.get_file_as_string("res://core/systems/Portal.gd")).contains("bs.scenery = true")
	assert_str(FileAccess.get_file_as_string("res://core/systems/StructureManager.gd")).contains("SceneryStencil.mark_tree(s.visual, SceneryStencil.STRUCTURE)")


func test_the_wall_the_cliffs_and_the_barrels_are_marked() -> void:
	var rc := FileAccess.get_file_as_string("res://world/maps/red_canyon/RedCanyon.gd")
	assert_str(rc).contains("add_child(SceneryStencil.mark_tree(_boundary_wall(")
	assert_str(rc).contains("add_child(SceneryStencil.mark_tree(_ridge(arena_radius + 4.0")
	# (pass 105, lane LOOK, re-pinned: the barrels with the structures)
	assert_str(FileAccess.get_file_as_string("res://core/systems/BarrelField.gd")).contains("SceneryStencil.mark_tree(mmi, SceneryStencil.STRUCTURE)")


func test_mark_and_mark_tree() -> void:
	# a plain material: custom stencil, write, always, 2
	var m := StandardMaterial3D.new()
	SceneryStencil.mark(m)
	assert_int(m.stencil_mode).is_equal(BaseMaterial3D.STENCIL_MODE_CUSTOM)
	assert_int(m.stencil_flags & BaseMaterial3D.STENCIL_FLAG_WRITE).is_not_equal(0)
	assert_int(m.stencil_compare).is_equal(BaseMaterial3D.STENCIL_COMPARE_ALWAYS)
	assert_int(m.stencil_reference).is_equal(SceneryStencil.VALUE)
	assert_bool(SceneryStencil.is_marked(m)).is_true()
	# a see-through one is left alone (the water must never outline what wades in it)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	SceneryStencil.mark(glass)
	assert_int(glass.stencil_mode).is_equal(BaseMaterial3D.STENCIL_MODE_DISABLED)
	# a tree: an override, a primitive mesh's own material, a file's (shared) material copied onto this node only
	var root: Node3D = auto_free(Node3D.new())
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	a.material_override = StandardMaterial3D.new()
	root.add_child(a)
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.material = StandardMaterial3D.new()
	b.mesh = bm
	root.add_child(b)
	var c := MeshInstance3D.new()
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shared := StandardMaterial3D.new()
	shared.take_over_path("res://tests/_p72_shared_material.tres")
	am.surface_set_material(0, shared)
	c.mesh = am
	root.add_child(c)
	assert_object(SceneryStencil.mark_tree(root)).is_same(root)
	assert_bool(SceneryStencil.is_marked(a.material_override)).is_true()
	assert_bool(SceneryStencil.is_marked(bm.material)).is_true()
	var own: Material = c.get_surface_override_material(0)
	assert_object(own).is_not_null()
	assert_object(own).is_not_same(shared)
	assert_bool(SceneryStencil.is_marked(own)).is_true()
	assert_bool(SceneryStencil.is_marked(shared)).is_false()
