extends GdUnitTestSuite

## Pass 76, lane DYN (Garry: "Make a Grenade The Drifters new fav Item ... Add a 1s explosion delay, now instead of
## exploding immediately when the Dynamite Stick lands let's have it sit there for 1 second and then explode. Make a
## slightly bigger area of effect ... Double the knockback ... the little fuse light ... That fuse should 'go out' 0.5s
## before the explosion ... New Mutation - Drifter Special ... Hitting more than 8 enemies at once with the Dynamite
## guarantees that all those enemies will get a Mini Crit"; "Peashooter ... Hide it for now"): the ground fuse
## (params.fuse: a landed shot lies on its side a second, then blows), the spark at the fuse tip (lit in flight, lying
## and riding with Sticky, out half a second before any blast), the shot's model by form and colour (params.models), the
## mass mini crits (params.mass_mini: nine caught, every one a Mini Crit; eight, none; each bomblet on its own; never the
## spikes), the numbers (area 2.8, knockback doubled), the Drifter's favourite and Fire in the Hole, the Peashooter and
## Fan the Hammer hidden.

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
func fx_burst(_at, _col, _size) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_poison(_a) -> void:
	pass
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	return null
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
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return true
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3, _c: bool = true) -> bool:
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
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0
## The numbers before pass 76: the blast "slightly bigger", the knockback doubled, read against these.
const OLD_AREA := 2.5
const OLD_KB := 7.0
const OLD_GP_KB := 9.0
## Stand-in models for the form and colour test (any GLB with a mesh does; the dynamite's own belong to lane DYNART).
const STICK_TAN := "res://art/props/barrel.glb"
const STICK_RED := "res://art/props/bone.glb"
const BUNDLE_TAN := "res://art/props/boulder.glb"
const BUNDLE_RED := "res://art/props/basketball.glb"
const ONE_MODEL := "res://art/props/golden_grenade.glb"


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero, with the real crowd, shots and effects.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = Vector3(0, 0, 30)
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
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


## The grenade with only the params given (whatever look the family plays), as its own def.
func _def_with(params: Dictionary) -> WeaponDef:
	var d: WeaponDef = Registry.weapon("lob_grenade").duplicate()
	d.params = params
	return d


func _fuse() -> Dictionary:
	return (Registry.weapon("lob_grenade").params["fuse"] as Dictionary).duplicate(true)


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	return i


func _steps(pm: ProjectileManager, secs: float) -> void:
	for n in range(int(round(secs / DT))):
		pm._physics_process(DT)


## Ticks until shot `j` lies on the sand (at most 3 s); the seconds it took, -1 when it never did.
func _until_lying(pm: ProjectileManager, j: int) -> float:
	var t := 0.0
	while t < 3.0:
		pm._physics_process(DT)
		t += DT
		if pm.alive[j] == 1 and (pm.extra[j] as Dictionary).has("lie_t"):
			return t
	return -1.0


func _lobber(w: Dictionary, inst: WeaponInstance) -> Lobber:
	var lb := Lobber.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(inst, w["g"])
	return lb


# ---------------------------------------------------------------- the numbers

func test_a_slightly_bigger_blast_and_twice_the_knockback() -> void:
	var lg: WeaponDef = Registry.weapon("lob_grenade")
	var gp: WeaponDef = Registry.weapon("golden_pineapple")
	assert_float(float(lg.base["area"])).is_equal_approx(2.8, 0.0001)
	assert_float(float(lg.base["area"])).is_greater(OLD_AREA)
	assert_float(float(lg.base["knockback"])).is_equal_approx(OLD_KB * 2.0, 0.0001)
	assert_float(float(gp.base["knockback"])).is_equal_approx(OLD_GP_KB * 2.0, 0.0001)
	# the rest of the weapon's numbers are untouched
	assert_float(float(gp.base["area"])).is_equal_approx(3.0, 0.0001)
	assert_float(float(lg.base["damage"])).is_equal_approx(25.0, 0.0001)
	assert_float(float(lg.base["cooldown"])).is_equal_approx(2.2, 0.0001)
	assert_float(float(gp.base["damage"])).is_equal_approx(45.0, 0.0001)
	assert_float(_inst("lob_grenade").stat("knockback")).is_equal_approx(14.0, 0.0001)
	# the fuse is a rule in the base params of both, so every look has it
	for d: WeaponDef in [lg, gp]:
		var fz = d.params.get("fuse")
		assert_bool(fz is Dictionary).override_failure_message(d.id).is_true()
		assert_float(float(fz["seconds"])).is_equal_approx(1.0, 0.0001)
		assert_float(float(fz["out_before"])).is_equal_approx(0.5, 0.0001)
		assert_bool(bool(fz["lie"])).is_true()
		assert_bool(fz["spark"] is Dictionary).is_true()
	# the evolution's fuse is its own, not under `final`
	assert_bool((_inst("golden_pineapple").params.get("fuse", {}) as Dictionary).has("seconds")).is_true()


# ---------------------------------------------------------------- the ground fuse

func test_a_landed_stick_lies_on_its_side_a_second_then_blows() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var inst := WeaponInstance.new(_def_with({"fuse": _fuse()}), 1)
	inst.rebuild(Run.player_sheet, [inst])
	# a tall mesh (a stick standing along Y): lying on its side shows
	var cyl := CylinderMesh.new()
	cyl.height = 1.0
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.1
	var k := pm.register_kind(cyl, null)
	var target := Vector3(4, 0, 0)
	var e := _creature(em, target + Vector3(0.6, 0, 0))
	var hp0: float = em.hp[e]
	var j := pm.lob(k, Vector3(0, 1.2, 0), target, 9.0, 25.0, inst.stat("area"), inst, 0.0, inst.params.duplicate())
	assert_bool((pm.extra[j] as Dictionary).has("fz")).is_true()
	assert_float(_until_lying(pm, j)).is_greater(0.0)
	# it came down and lies there: no blast yet, nothing hurt
	assert_int(pm.alive[j]).is_equal(1)
	assert_int(pm.lobs_exploded).is_equal(0)
	assert_float(em.hp[e]).is_equal(hp0)
	assert_bool(pm.vel[j].is_zero_approx()).is_true()
	# on its side: the mesh's long axis (Y) lies flat, and it rests on the sand rather than in it
	var up := pm.draw_basis(j) * Vector3.UP
	assert_float(absf(up.normalized().y)).is_less(0.1)
	assert_float(pm.pos[j].y).is_greater(0.0)
	# still: it neither moves nor turns while it lies, and its spot stays taken
	var p0: Vector3 = pm.pos[j]
	var b0 := pm.draw_basis(j)
	_steps(pm, 0.9)
	assert_int(pm.alive[j]).is_equal(1)
	assert_int(pm.lobs_exploded).is_equal(0)
	assert_bool(pm.pos[j].is_equal_approx(p0)).is_true()
	assert_bool(pm.draw_basis(j).is_equal_approx(b0)).is_true()
	var taken := false
	for s: Vector3 in pm.claimed_spots():
		if Vector2(s.x - target.x, s.z - target.z).length() < 0.5:
			taken = true
	assert_bool(taken).is_true()
	# a second after it landed it blows, once, where it lay
	_steps(pm, 0.15)
	assert_int(pm.lobs_exploded).is_equal(1)
	assert_int(pm.alive[j]).is_equal(0)
	assert_float(em.hp[e]).is_less(hp0)


func test_a_stick_lies_along_its_throw_and_a_squat_one_sits_up() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := WeaponInstance.new(_def_with({"fuse": _fuse()}), 1)
	inst.rebuild(Run.player_sheet, [inst])
	# long along Z (the dynamite models): it lies as it is, turned along the way it was thrown (+X), give or take
	var stick := BoxMesh.new()
	stick.size = Vector3(0.2, 0.2, 0.7)
	var j := pm.lob(pm.register_kind(stick, null), Vector3(0, 1.2, 0), Vector3(5, 0, 0), 9.0, 1.0, 2.8, inst, 0.0, inst.params.duplicate())
	assert_float(_until_lying(pm, j)).is_greater(0.0)
	var long := (pm.draw_basis(j) * Vector3.BACK).normalized()
	assert_float(absf(long.y)).is_less(0.05)
	assert_float(absf(long.dot(Vector3.RIGHT))).is_greater(cos(0.36))
	# a crate, a touch taller than wide: it sits as it is
	var crate := BoxMesh.new()
	crate.size = Vector3(0.5, 0.6, 0.55)
	var c := pm.lob(pm.register_kind(crate, null), Vector3(0, 1.2, 0), Vector3(0, 0, 5), 9.0, 1.0, 2.8, inst, 0.0, inst.params.duplicate())
	assert_float(_until_lying(pm, c)).is_greater(0.0)
	assert_float((pm.draw_basis(c) * Vector3.UP).normalized().y).is_greater(0.99)


func test_the_evolution_lies_and_its_bomblets_fuse_and_push_at_half() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var gp := _inst("golden_pineapple")
	assert_float(gp.stat("knockback")).is_equal_approx(18.0, 0.0001)
	var k := pm.register_kind(BoxMesh.new(), null)
	# nothing in reach to stick to: it lies like any stick
	var j := pm.lob(k, Vector3(0, 1.2, 0), Vector3(5, 0, 0), 9.0, gp.stat("damage"), gp.stat("area"), gp, gp.stat("knockback"), gp.params.duplicate())
	assert_float(_until_lying(pm, j)).is_greater(0.0)
	assert_int(pm.stuck[j]).is_equal(-1)
	_steps(pm, 1.05)
	assert_int(pm.lobs_exploded).is_equal(1)
	var bomblets: Array = []
	for q in range(ProjectileManager.MAX):
		if pm.alive[q] == 1 and (pm.extra[q] as Dictionary).has("is_bomblet"):
			bomblets.append(q)
	assert_int(bomblets.size()).is_equal(int(gp.params["bomblets"]))
	for q: int in bomblets:
		# pushed at half the blast's (doubled) knockback, and fused like the stick
		assert_float(pm.kb[q]).is_equal_approx(gp.stat("knockback") * 0.5, 0.0001)
		assert_bool((pm.extra[q] as Dictionary).has("fz")).is_true()
	# each one comes down and lies its own fuse out
	var lay := {}
	var t := 0.0
	while t < 3.0 and pm.lobs_exploded < 1 + bomblets.size():
		pm._physics_process(DT)
		t += DT
		for q: int in bomblets:
			if pm.alive[q] == 1 and (pm.extra[q] as Dictionary).has("lie_t"):
				lay[q] = true
	assert_int(lay.size()).is_equal(bomblets.size())
	assert_int(pm.lobs_exploded).is_equal(1 + bomblets.size())


# ---------------------------------------------------------------- the spark

func test_the_spark_burns_and_goes_out_half_a_second_before_the_blast() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := WeaponInstance.new(_def_with({"fuse": _fuse()}), 1)
	inst.rebuild(Run.player_sheet, [inst])
	var k := pm.register_kind(BoxMesh.new(), null)
	var j := pm.lob(k, Vector3(0, 1.2, 0), Vector3(5, 0, 0), 9.0, 1.0, 2.8, inst, 0.0, inst.params.duplicate())
	# in flight: lit, drawn (its glows, its twinkle and its core)
	pm._physics_process(DT)
	assert_bool(pm.fuse_lit(j)).is_true()
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(1)
	assert_int(pm._spark_mm.visible_instance_count).is_equal(ProjectileManager.SPARK_PARTS)
	assert_float(_until_lying(pm, j)).is_greater(0.0)
	# on the sand: lit while more than half a second is left
	_steps(pm, 0.45)
	assert_bool(pm.fuse_lit(j)).is_true()
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(1)
	_steps(pm, 0.1)
	assert_bool(pm.fuse_lit(j)).is_false()
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(0)
	assert_int(pm.fuses_out).is_equal(1)
	# out, and it has not blown yet; it does by the second
	assert_int(pm.alive[j]).is_equal(1)
	assert_int(pm.lobs_exploded).is_equal(0)
	_steps(pm, 0.5)
	assert_int(pm.lobs_exploded).is_equal(1)
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(0)
	assert_int(pm.fuses_out).is_equal(1)


func test_with_sticky_the_spark_rides_and_goes_out_half_a_second_before_the_ride_ends() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var inst := _inst("lob_grenade", ["sticky"])
	var ride := float((inst.params["sticky"] as Dictionary)["seconds"])
	var e := _creature(em, Vector3(6, 0, 0))
	var k := pm.register_kind(BoxMesh.new(), null)
	var j := pm.lob(k, Vector3(0, 1.2, 0), em.pos[e], 9.0, 1.0, 2.8, inst, 0.0, inst.params.duplicate())
	var n := 0
	while pm.stuck[j] < 0 and n < 200:
		pm._physics_process(DT)
		n += 1
	# caught by Sticky: it rides, it does not lie; it rides in the pose it would lie in, its spin stopped
	assert_int(pm.stuck[j]).is_equal(e)
	assert_bool((pm.extra[j] as Dictionary).has("lie_t")).is_false()
	assert_bool((pm.extra[j] as Dictionary).has("lie_b")).is_true()
	assert_float(pm.spin[j]).is_equal(0.0)
	assert_bool(pm.fuse_lit(j)).is_true()
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(1)
	_steps(pm, ride - 0.5 - 0.05)
	assert_bool(pm.fuse_lit(j)).is_true()
	_steps(pm, 0.1)
	assert_bool(pm.fuse_lit(j)).is_false()
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(0)
	assert_int(pm.stuck[j]).is_equal(e)
	assert_int(pm.lobs_exploded).is_equal(0)
	_steps(pm, 0.5)
	assert_int(pm.lobs_exploded).is_equal(1)


func test_with_sticky_and_nothing_to_stick_to_it_lies_like_a_plain_stick() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("lob_grenade", ["sticky"])
	var k := pm.register_kind(BoxMesh.new(), null)
	var j := pm.lob(k, Vector3(0, 1.2, 0), Vector3(-5, 0, 0), 9.0, 1.0, 2.8, inst, 0.0, inst.params.duplicate())
	assert_float(_until_lying(pm, j)).is_greater(0.0)
	assert_int(pm.stuck[j]).is_equal(-1)
	_steps(pm, 1.05)
	assert_int(pm.lobs_exploded).is_equal(1)


func test_the_spark_sits_at_the_fuse_tip() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	# the model's own tip, carried by the shot's turn and size in flight and lying
	var d := _def_with({"fuse": _fuse(), "models": {"stick": {"tan": STICK_TAN, "red": STICK_RED, "tip": [0.0, 0.3, -0.2]}}})
	var inst := WeaponInstance.new(d, 1)
	inst.rebuild(Run.player_sheet, [inst])
	var lb := _lobber(w, inst)
	var j := pm.lob(lb.shot_kind(), Vector3(0, 1.2, 0), Vector3(5, 0, 0), 9.0, 1.0, 2.8, inst, 0.0, inst.params.duplicate())
	pm._physics_process(DT)
	assert_bool(pm.fuse_tip(j).is_equal_approx(pm.pos[j] + pm.draw_basis(j) * Vector3(0.0, 0.3, -0.2))).is_true()
	assert_float(_until_lying(pm, j)).is_greater(0.0)
	assert_bool(pm.fuse_tip(j).is_equal_approx(pm.pos[j] + pm.draw_basis(j) * Vector3(0.0, 0.3, -0.2))).is_true()
	# no tip named: the top of the mesh (the grenade's sphere: its radius above its middle)
	var plain := WeaponInstance.new(_def_with({"fuse": _fuse()}), 1)
	plain.rebuild(Run.player_sheet, [plain])
	var sph := SphereMesh.new()
	sph.radius = 0.26
	sph.height = 0.52
	var q := pm.lob(pm.register_kind(sph, null), Vector3(0, 1.2, 0), Vector3(-5, 0, 0), 9.0, 1.0, 2.8, plain, 0.0, plain.params.duplicate())
	pm._physics_process(DT)
	assert_bool(pm.fuse_tip(q).is_equal_approx(pm.pos[q] + pm.draw_basis(q) * Vector3(0.0, 0.26, 0.0))).is_true()


func test_the_spark_is_drawn_once_in_the_warm_up() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	pm.warm_draw(Vector3(0, -8, 0))
	assert_object(pm._spark_mm).is_not_null()
	assert_int(pm._spark_mm.visible_instance_count).is_greater_equal(1)
	pm.warm_draw(Vector3.INF)
	assert_int(pm._spark_mm.visible_instance_count).is_equal(0)


func test_a_weapon_without_a_fuse_blows_as_it_lands() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var mol := _inst("molotov")
	assert_bool(ProjectileManager.fuse_of(mol).is_empty()).is_true()
	var k := pm.register_kind(BoxMesh.new(), null)
	var j := pm.lob(k, Vector3(0, 1.2, 0), Vector3(5, 0, 0), 9.0, 1.0, 2.0, mol, 0.0, mol.params.duplicate())
	assert_bool((pm.extra[j] as Dictionary).has("fz")).is_false()
	var t := 0.0
	while pm.alive[j] == 1 and t < 3.0:
		pm._physics_process(DT)
		t += DT
	assert_int(pm.lobs_exploded).is_equal(1)
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(0)


# ---------------------------------------------------------------- the model by form and colour

func test_the_shot_is_drawn_with_the_model_its_form_and_colour_choose() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var models := {"stick": {"tan": STICK_TAN, "red": STICK_RED, "tip": [0.0, 0.1, -0.3]},
		"bundle": {"tan": BUNDLE_TAN, "red": BUNDLE_RED, "tip": [0.0, 0.2, -0.3]}}
	var inst := WeaponInstance.new(_def_with({"fuse": _fuse(), "models": models}), 1)
	inst.rebuild(Run.player_sheet, [inst])
	var lb := _lobber(w, inst)
	# the defaults: the tan stick
	assert_str(lb.model_path()).is_equal(STICK_TAN)
	var k_tan := lb.projectile_kind
	var visual_kind := lb._visual_kind
	assert_int(k_tan).is_not_equal(visual_kind)
	# Dynamite Bundle's form, then Coffin Nails' colour on top: the bundle in red, whichever came first
	var bundle := MutationDef.new()
	bundle.id = "t76_bundle"
	bundle.params = {"model_form": "bundle"}
	var red := MutationDef.new()
	red.id = "t76_red"
	red.params = {"model_colour": "red"}
	var seen := {}
	for muts: Array in [[bundle], [bundle, red], [red, bundle], [red]]:
		inst.mutations = muts
		inst.rebuild(Run.player_sheet, [inst])
		lb.refresh_marks()
		seen[lb.model_path()] = lb.projectile_kind
	assert_bool(seen.has(BUNDLE_TAN)).is_true()
	assert_bool(seen.has(BUNDLE_RED)).is_true()
	assert_bool(seen.has(STICK_RED)).is_true()
	assert_int(seen.size()).is_equal(3)
	# back to the plain stick: the kind made the first time, no new one
	var n0 := pm.kinds.size()
	inst.mutations = []
	inst.rebuild(Run.player_sheet, [inst])
	lb.refresh_marks()
	assert_str(lb.model_path()).is_equal(STICK_TAN)
	assert_int(lb.projectile_kind).is_equal(k_tan)
	assert_int(pm.kinds.size()).is_equal(n0)
	# a form with no model and no params.model: the visual's own shot again
	var none := MutationDef.new()
	none.id = "t76_none"
	none.params = {"model_form": "crate"}
	inst.mutations = [none]
	inst.rebuild(Run.player_sheet, [inst])
	lb.refresh_marks()
	assert_str(lb.model_path()).is_equal("")
	assert_int(lb.projectile_kind).is_equal(visual_kind)
	# the choice itself: the form's tip, params.model and params.fuse_tip when the form or its file is missing
	assert_bool((Lobber.model_choice({"models": models, "model_form": "bundle"})["tip"] as Vector3).is_equal_approx(Vector3(0.0, 0.2, -0.3))).is_true()
	var fb := Lobber.model_choice({"models": models, "model_form": "crate", "model": ONE_MODEL, "fuse_tip": [0.0, 0.4, 0.0]})
	assert_str(str(fb["path"])).is_equal(ONE_MODEL)
	assert_bool((fb["tip"] as Vector3).is_equal_approx(Vector3(0.0, 0.4, 0.0))).is_true()
	var gone := Lobber.model_choice({"models": {"stick": {"tan": "res://art/props/t76_no_such_model.glb"}}, "model": ONE_MODEL})
	assert_str(str(gone["path"])).is_equal(ONE_MODEL)
	assert_bool((gone["tip"] as Vector3).is_finite()).is_false()


# ---------------------------------------------------------------- the mass mini crits

## A blast of `dmg` from a shot of `inst` (extra `ex`) over `n` creatures round `at`: [hp lost by each, their indices].
func _blast(w: Dictionary, inst: WeaponInstance, n: int, at: Vector3, dmg: float, ex: Dictionary = {}) -> Array:
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var ids: Array = []
	for q in range(n):
		var a := TAU * float(q) / float(maxi(n, 1))
		ids.append(_creature(em, at + Vector3(cos(a), 0, sin(a)) * 0.9))
	var hp0: Array = []
	for i: int in ids:
		hp0.append(em.hp[i])
	var k := pm.register_kind(BoxMesh.new(), null)
	var p: Dictionary = inst.params.duplicate()
	p.merge(ex, true)
	var j := pm.lob(k, at + Vector3(0, 0.3, 0), at, 9.0, dmg, 2.4, inst, 0.0, p)
	pm.pos[j] = at
	pm._explode(j)
	pm._free(j)
	var lost: Array = []
	for q in range(ids.size()):
		lost.append(float(hp0[q]) - em.hp[ids[q]])
	return [lost, ids]


func test_nine_caught_all_take_a_mini_crit_and_eight_take_none() -> void:
	var inst := _inst("lob_grenade", ["fire_in_the_hole"])
	assert_int(int((inst.params["mass_mini"] as Dictionary)["min_hits"])).is_equal(9)
	# nine in the blast: every one a Mini Crit (x1.5 with the default crit damage)
	var w9 := _world()
	var r9: Array = _blast(w9, inst, 9, Vector3(5, 0, 5), 20.0)
	var em9: EnemyManager = w9["em"]
	for q in range((r9[0] as Array).size()):
		var i: int = r9[1][q]
		assert_float(float(r9[0][q])).override_failure_message("creature %d of 9" % q).is_equal_approx(20.0 * 1.5 * (1.0 - em9.dr[i]), 0.01)
	assert_int((w9["pm"] as ProjectileManager).mass_minis).is_equal(1)
	assert_int((w9["pm"] as ProjectileManager).last_blast_caught).is_equal(9)
	# eight: none
	var w8 := _world()
	var r8: Array = _blast(w8, inst, 8, Vector3(5, 0, 5), 20.0)
	var em8: EnemyManager = w8["em"]
	for q in range((r8[0] as Array).size()):
		var i: int = r8[1][q]
		assert_float(float(r8[0][q])).is_equal_approx(20.0 * (1.0 - em8.dr[i]), 0.01)
	assert_int((w8["pm"] as ProjectileManager).mass_minis).is_equal(0)
	assert_int((w8["pm"] as ProjectileManager).last_blast_caught).is_equal(8)
	# nine without Fire in the Hole: plain hits
	var wp := _world()
	var rp: Array = _blast(wp, _inst("lob_grenade"), 9, Vector3(5, 0, 5), 20.0)
	var emp: EnemyManager = wp["em"]
	for q in range((rp[0] as Array).size()):
		assert_float(float(rp[0][q])).is_equal_approx(20.0 * (1.0 - emp.dr[rp[1][q]]), 0.01)
	assert_int((wp["pm"] as ProjectileManager).mass_minis).is_equal(0)


func test_each_bomblet_counts_on_its_own_and_the_spikes_never_mini_crit() -> void:
	var inst := _inst("lob_grenade", ["fire_in_the_hole", "frag"])
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	# a bomblet over nine: they all mini-crit
	var ra: Array = _blast(w, inst, 9, Vector3(10, 0, 0), 10.0, {"is_bomblet": true})
	for q in range((ra[0] as Array).size()):
		assert_float(float(ra[0][q])).is_equal_approx(10.0 * 1.5 * (1.0 - em.dr[ra[1][q]]), 0.01)
	assert_int(pm.mass_minis).is_equal(1)
	# another bomblet over three, far off: its own count, plain hits
	var rb: Array = _blast(w, inst, 3, Vector3(-10, 0, 0), 10.0, {"is_bomblet": true})
	for q in range((rb[0] as Array).size()):
		assert_float(float(rb[0][q])).is_equal_approx(10.0 * (1.0 - em.dr[rb[1][q]]), 0.01)
	assert_int(pm.mass_minis).is_equal(1)
	assert_int(pm.last_blast_caught).is_equal(3)
	# a full blast over nine more throws Frag's spikes: they carry no mini crit of their own
	_blast(w, inst, 9, Vector3(0, 0, -12), 10.0)
	assert_int(pm.mass_minis).is_equal(2)
	var spikes := 0
	for q in range(ProjectileManager.MAX):
		if pm.alive[q] == 1 and (pm.extra[q] as Dictionary).has("shrapnel"):
			spikes += 1
			assert_bool((pm.extra[q] as Dictionary).has("mini")).is_false()
	assert_int(spikes).is_greater(0)


func test_a_blast_counts_only_creatures_it_can_strike() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var at := Vector3(3, 0, 3)
	var ids: Array = []
	for q in range(5):
		ids.append(_creature(em, at + Vector3(0.3 * q, 0, 0)))
	assert_int(em.blast_count(at, 2.4)).is_equal(5)
	em.hidden[ids[0]] = 1
	em.state[ids[1]] = EnemyManager.STATE_DYING
	assert_int(em.blast_count(at, 2.4)).is_equal(3)
	assert_int(em.blast_count(at + Vector3(20, 0, 0), 2.4)).is_equal(0)


# ---------------------------------------------------------------- the Drifter, the Peashooter

func test_the_drifter_favours_the_dynamite_and_has_fire_in_the_hole() -> void:
	var c: CharacterDef = Registry.character("drifter")
	assert_str(c.favourite_weapon).is_equal("lob_grenade")
	assert_str(c.start_weapon).is_equal("revolver")
	var ids: Array = Registry.hero_mutations("drifter").map(func(m: MutationDef) -> String: return m.id)
	assert_array(ids).is_equal(["fire_in_the_hole"])
	var fh: MutationDef = Registry.mutation("fire_in_the_hole")
	var fan: MutationDef = Registry.mutation("fan_the_hammer")
	assert_str(fh.mutation_kind).is_equal("hero")
	assert_str(fh.weapon).is_equal("lob_grenade")
	assert_str(fh.hero).is_equal("drifter")
	assert_bool(fh.hidden).is_false()
	assert_str(fh.rarity).is_equal(fan.rarity)
	assert_float(float(fh.weight)).is_equal_approx(float(fan.weight), 0.0001)
	assert_bool(fh.has_icon()).is_true()
	assert_int(int((fh.params["mass_mini"] as Dictionary)["min_hits"])).is_equal(9)
	assert_str(fh.text).contains("nine or more")
	# a Drifter's run: the dynamite offered whatever its quest, never the Peashooter; his own mutation opens on it
	Save.data = Save._default()
	Run.start(c, Registry.map("red_canyon"))
	assert_bool(CardPool.offer_weapons().has(Registry.weapon("lob_grenade"))).is_true()
	assert_bool(CardPool.offer_weapons().has(Registry.weapon("peashooter"))).is_false()
	var g := Run.add_weapon(Registry.weapon("lob_grenade"), 3)
	var open: Array = Run.open_mutations(g).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(open.has("fire_in_the_hole")).is_true()
	assert_bool(Run.add_mutation("fire_in_the_hole")).is_true()
	assert_bool(g.params.get("mass_mini") is Dictionary).is_true()
	assert_str(g.description()).contains("9 or more")
	# the evolution keeps it, with its own fuse
	for m: String in ["new_equipment", "frag", "sticky"]:
		Run.add_mutation(m, true)
	var evo := Run.evolve(g)
	assert_object(evo).is_not_null()
	assert_str(evo.def.id).is_equal("golden_pineapple")
	assert_bool(evo.params.get("mass_mini") is Dictionary).is_true()
	assert_bool(evo.params.get("fuse") is Dictionary).is_true()


func test_the_peashooter_and_fan_the_hammer_are_out_of_play() -> void:
	var pea: WeaponDef = Registry.weapon("peashooter")
	assert_bool(pea.hidden).is_true()
	assert_bool(Registry.is_hidden(pea)).is_true()
	assert_bool(Registry.is_hidden(Registry.weapon("pea_cannon"))).is_true()
	assert_bool(Registry.mutation("fan_the_hammer").hidden).is_true()
	assert_bool(Registry.unlocked_weapons().has(pea)).is_false()
	for m: MutationDef in Registry.mutations_of("peashooter"):
		assert_bool(Registry.is_hidden(m)).override_failure_message(m.id).is_true()
	assert_bool(Registry.hero_mutations("drifter").has(Registry.mutation("fan_the_hammer"))).is_false()
	assert_bool(Registry.weapon_hero_mutations("peashooter").is_empty()).is_true()
	# kept in the content: a tool or the arena can still hand it out
	assert_object(Run.add_weapon(pea, 1)).is_not_null()


# ---------------------------------------------------------------- the words

func test_the_card_says_it_blows_a_second_after_it_lands() -> void:
	var one := _inst("lob_grenade")
	assert_str(one.description()).contains("It lies where it lands and blows a second later.")
	# a volley (level 3 throws two)
	var two := _inst("lob_grenade", [], 3)
	assert_int(two.stat_int("amount", 1)).is_equal(2)
	assert_str(two.description()).contains("Each one lies where it lands and blows a second later.")
	# with Sticky, only the one that finds nothing to stick to lies
	assert_str(_inst("lob_grenade", ["sticky"]).description()).contains("One that sticks to nothing lies where it lands")
	# the words follow the data
	assert_str(TextGen.fuse_words({"fuse": {"seconds": 0.8}})).contains("blows 0.8 s later")
	assert_str(TextGen.fuse_words({})).is_equal("")
	assert_str(TextGen.mass_mini_words({"mass_mini": {"min_hits": 12}})).contains("12 or more")
	assert_str(TextGen.mass_mini_words({})).is_equal("")
	# the Molotov says nothing of a fuse
	assert_str(_inst("molotov").description()).not_contains("lies where it lands")
