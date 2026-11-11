extends GdUnitTestSuite

## Pass 141, lane GRAV (Garry, "Polish #4" item 6: the Gravity Gun's "very sad looking brief shot on the ground when there
## are no targets" becomes a 'search', "a continuous beam 'feeling out' the ground" for about a second now and then; and it
## grabs barrels and throws them at the Outlaw, "grab, pause, throw ... when it lands it automatically breaks", only
## within "around 75% of the distance that is required for the initial enemy reach", a range that "never increases with
## Upgrades", in no text). Pinned here: the search starts on its own clock, lasts its seconds, sweeps the sand ahead and
## takes nothing; a creature coming into reach mid-search is taken at once and ends it; a barrel at 5 m is lifted, held,
## thrown and broken a little in front of him without hurting him, paying what walking into it pays; one at 6 m stands;
## the reach ignores the levels' range and the Singularity's own; a carried barrel is out of the walk-in, the rounds and
## the grid; one barrel at a time, the rest of the pull still takes creatures; the Singularity throws it the same way; the
## same throw twice lands the same; no text changes.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var hud = null
var director = null
var barrels = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func apply_pickup(_def, _at: Vector3) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var cinematic := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
var hip: Node3D = null
var hurts := 0
signal hit
func is_still() -> bool:
	return velocity.length() < 0.01
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hurts += 1
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	var dd := Vector3(d.x, 0, d.z)
	if dd.length_squared() < 0.0001:
		dd = forward()
	return global_position + Vector3(0, 0.8, 0) + dd.normalized() * 0.5
"""

const FAKE_RIG := """extends Node
var camera: Camera3D = null
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const FAKE_DIRECTOR := """extends Node
var running := true
var phase := 0
var timeline = null
"""

const DT := 1.0 / 60.0

var _keep_aim := true
var _keep_shoot := true


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_keep_aim = Settings.aim_mode
	_keep_shoot = Settings.shoot_barrels
	Settings.aim_mode = true
	Settings.shoot_barrels = true
	Aim.soft_rule = true
	Aim.reset()


func after_test() -> void:
	Settings.aim_mode = _keep_aim
	Settings.shoot_barrels = _keep_shoot
	Aim.soft_rule = true
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin facing -Z (no map: flat sand at 0), with the real crowd, shots, effects,
## marks and pickups, and a real BarrelField with a brown barrel standing at each of `spots` (its MultiMeshes made by
## hand, as pass 137's test).
func _world(spots: Array = []) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	var hip := Node3D.new()
	hero.add_child(hip)
	hip.position = Vector3(0.55, 0.7, 0)
	hero.set("hip", hip)
	g.player = hero
	var rig := Node.new()
	rig.set_script(_script(FAKE_RIG))
	g.add_child(rig)
	g.camera = rig
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	em.screen_filter_on = false
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
	var tl := WaveTimeline.new()
	tl.barrels = {}
	var d := Node.new()
	d.set_script(_script(FAKE_DIRECTOR))
	g.add_child(d)
	d.timeline = tl
	g.director = d
	var pk := PickupManager.new()
	pk.game = g
	g.add_child(pk)
	g.pickups = pk
	var bf := BarrelField.new()
	bf.game = g
	g.add_child(bf)
	g.barrels = bf
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = spots.size() + BarrelField.SPARE
	mm.visible_instance_count = spots.size()
	bf.set("_body_dark", mm)
	var k := 0
	for s: Vector3 in spots:
		bf.pos.append(Vector3(s.x, 0.0, s.z))
		bf.light.append(0)
		bf.alive.append(1)
		bf.coins.append(0)
		bf._index_in.append(k)
		bf.shadows.append(-1)
		k += 1
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "pk": pk, "bf": bf, "rig": rig}


func _inst(id: String, level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _gun(w: Dictionary, id := "gravity_gun", level := 1) -> GravityGun:
	var gun := GravityGun.new()
	(w["g"] as Node).add_child(gun)
	gun.setup(_inst(id, level), w["g"])
	return gun


## A tough, risen creature at `at`.
func _creature(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


## A flat point `d` metres out at `deg` degrees off -Z (positive to the right, +X).
static func _at(d: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(sin(a) * d, 0.0, -cos(a) * d)


## Frames of the gun's own _process (its clock, its pulls, its grip) until `done` says so or `most` frames went by.
## Returns the frames run.
func _run(gun: GravityGun, most: int, done: Callable = Callable()) -> int:
	for f in range(most):
		gun._process(DT)
		if done.is_valid() and bool(done.call()):
			return f + 1
	return most


func _loot(pk: PickupManager) -> Dictionary:
	var out := {"small": 0, "medium": 0, "coins": 0}
	for i in range(pk.alive.size()):
		if pk.alive[i] == 1:
			match pk.kind[i]:
				PickupManager.KIND_GEM_S:
					out["small"] += 1
				PickupManager.KIND_GEM_M:
					out["medium"] += 1
				PickupManager.KIND_COIN:
					out["coins"] += 1
	return out


# ---------------------------------------------------------------- the search (6.1)

func test_with_nothing_near_the_gun_searches_the_sand_for_its_seconds_and_takes_nothing() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var gun := _gun(w)
	var s: Dictionary = gun._block("search", GravityGun.SEARCH)
	assert_float(float(s["seconds"])).is_equal(1.0)
	assert_float(float(s["every"])).is_equal(3.0)
	# nothing to take: the pull is not spent (no dry shot at the sand any more), and no search before its clock is up
	assert_bool(gun._fire()).is_false()
	assert_int(gun.searches).is_equal(0)
	assert_bool(gun.searching()).is_false()
	# its first search comes half an `every` in; it lasts `seconds`
	var start := _run(gun, 400, func() -> bool: return gun.searching())
	assert_float(float(start) * DT).is_between(1.4, 1.75)
	assert_int(gun.searches).is_equal(1)
	var touched := 0
	var lasted := 0
	for f in range(200):
		gun._process(DT)
		if not gun.searching():
			break
		lasted += 1
		var end: Vector3 = gun._search["end"]
		if end != Vector3.INF:
			touched += 1
			# on the sand ahead of him: within the sweep's half angle off his facing (-Z), about `reach` out
			var off := absf(rad_to_deg(Vector2(0, -1).angle_to(Vector2(end.x, end.z))))
			assert_float(off).is_less_equal(float(s["sweep_deg"]) * 0.5 + 0.5)
			var dist := Vector2(end.x, end.z).length()
			assert_float(dist).is_between(float(s["reach"]) - float(s["wander"]) - 0.1, float(s["reach"]) + float(s["wander"]) + 0.1)
			assert_float(end.y).is_equal(0.0)
		assert_int(gun._grips.size()).is_equal(0)
		assert_int(em.alive_count()).is_equal(0)
	assert_float(float(lasted) * DT).is_between(0.97, 1.04)
	assert_int(touched).is_greater(40)
	# the beam and its glow are gone with it, and the next search waits its `every`
	assert_bool(gun._glow == null or not gun._glow.visible).is_true()
	var gap := _run(gun, 400, func() -> bool: return gun.searching())
	assert_float(float(gap) * DT).is_between(2.95, 3.2)
	assert_int(gun.searches).is_equal(2)
	# each sweep goes the other way from the last
	assert_float(float(gun._search["dir"])).is_equal(-1.0)


func test_the_search_sweeps_and_glows_where_it_touches() -> void:
	var w := _world()
	var gun := _gun(w)
	_run(gun, 400, func() -> bool: return gun.searching())
	var first := Vector3.INF
	var last := Vector3.INF
	var glowed := false
	while gun.searching():
		gun._process(DT)
		if gun.searching() and Vector3(gun._search["end"]) != Vector3.INF:
			if first == Vector3.INF:
				first = gun._search["end"]
			last = gun._search["end"]
		if gun._glow != null and gun._glow.visible:
			glowed = true
	# it swept across his facing, side to side
	var a0 := rad_to_deg(Vector2(0, -1).angle_to(Vector2(first.x, first.z)))
	var a1 := rad_to_deg(Vector2(0, -1).angle_to(Vector2(last.x, last.z)))
	assert_float(absf(a1 - a0)).is_greater(35.0)
	assert_bool(glowed).is_true()
	assert_float(gun._scan).is_greater(0.5)


func test_a_creature_coming_into_reach_mid_search_is_taken_at_once_and_ends_it() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var gun := _gun(w)
	_run(gun, 400, func() -> bool: return gun.searching())
	_run(gun, 20)
	assert_bool(gun.searching()).is_true()
	var c := _creature(em, _at(4.0, 10.0))
	var took := _run(gun, 30, func() -> bool: return not gun._grips.is_empty())
	# the gun asks again every 0.15 s while its pull is unspent
	assert_float(float(took) * DT).is_less_equal(0.17)
	assert_int(int(gun._grips[0]["i"])).is_equal(c)
	assert_bool(gun.searching()).is_false()


# ---------------------------------------------------------------- the barrels (6.2)

func test_a_barrel_at_5_m_is_thrown_and_breaks_a_little_in_front_of_the_outlaw() -> void:
	var w := _world([_at(5.0, 30.0)])
	var bf: BarrelField = w["bf"]
	var hero: Node3D = w["hero"]
	var rig: Node = w["rig"]
	var gun := _gun(w)
	var broken_before := Run.barrels_broken
	assert_float(gun.barrel_reach()).is_equal_approx(5.25, 0.0001)
	# the first pull takes it (nothing else near)
	gun._process(DT)
	assert_bool(bf.is_carried(0)).is_true()
	assert_int(int(gun._bgrip["phase"])).is_equal(GravityGun.PH_GRAB)
	# lifted, then held off the sand, never thrown before grab + hold
	var held := _run(gun, 200, func() -> bool: return int(gun._bgrip.get("phase", -1)) == GravityGun.PH_THROW)
	assert_float(float(held) * DT).is_between(0.58, 0.66)
	assert_float(bf.pos[0].y).is_greater(1.0)
	assert_int(bf.alive[0]).is_equal(1)
	# then thrown in an arc and broken where it lands
	var top := [0.0]
	var flew := _run(gun, 200, func() -> bool:
		top[0] = maxf(float(top[0]), bf.pos[0].y)
		return gun.barrel_throws > 0)
	assert_float(float(flew) * DT).is_between(0.25, 0.7)
	assert_float(float(top[0])).is_greater(1.4)
	assert_int(bf.alive[0]).is_equal(0)
	assert_bool(bf.is_carried(0)).is_false()
	assert_int(bf.broken).is_equal(1)
	assert_int(Run.barrels_broken).is_equal(broken_before + 1)
	# a little in front of him (his facing is -Z), on the sand, and it never hurt him
	var land: Vector3 = bf.pos[0]
	var ahead: float = float(gun._block("barrel", GravityGun.BARREL)["ahead"])
	assert_float(Vector2(land.x, land.z).distance_to(Vector2(0.0, -ahead))).is_less(0.01)
	assert_float(land.y).is_equal(0.0)
	assert_int(int(hero.get("hurts"))).is_equal(0)
	assert_int(int(rig.get("shakes"))).is_greater(0)
	# its contents spilled as from any broken barrel
	assert_int(int(_loot(w["pk"])["small"])).is_equal(int(BarrelSpawns.contents_of({}, 0)["gems_small"]))


func test_a_thrown_barrel_pays_what_walking_into_it_pays() -> void:
	var walk := _world([_at(4.0, 0.0)])
	var bw: BarrelField = walk["bf"]
	(walk["hero"] as Node3D).global_position = bw.pos[0]
	bw._physics_process(DT)
	assert_int(bw.alive[0]).is_equal(0)
	var thrown := _world([_at(4.0, 0.0)])
	var bt: BarrelField = thrown["bf"]
	var gun := _gun(thrown)
	_run(gun, 200, func() -> bool: return gun.barrel_throws > 0)
	assert_int(bt.alive[0]).is_equal(0)
	assert_dict(_loot(thrown["pk"])).is_equal(_loot(walk["pk"]))


func test_a_barrel_at_6_m_stands_and_the_gun_searches_instead() -> void:
	var w := _world([_at(6.0, 0.0)])
	var bf: BarrelField = w["bf"]
	var gun := _gun(w)
	_run(gun, 200)
	assert_int(bf.alive[0]).is_equal(1)
	assert_bool(bf.is_carried(0)).is_false()
	assert_bool(gun._bgrip.is_empty()).is_true()
	assert_int(gun.searches).is_equal(1)


func test_the_barrel_reach_ignores_upgrades_and_the_evolution() -> void:
	# level 5 raises the gun's range by 15%; the barrels' reach stays 0.75 x the level-1 7 m
	var w := _world([_at(5.5, 0.0)])
	var bf: BarrelField = w["bf"]
	var gun := _gun(w, "gravity_gun", 5)
	assert_float(gun.stat("range", 0.0)).is_greater(7.9)
	assert_float(gun.barrel_reach()).is_equal_approx(5.25, 0.0001)
	gun._fire()
	assert_bool(bf.is_carried(0)).is_false()
	# a range bonus on the hero's sheet does not move it either
	var inst := gun.inst
	inst.bonus_effects.append(Effect.make("range", "mul", 0.5))
	inst.rebuild(Run.player_sheet, [inst])
	assert_float(gun.stat("range", 0.0)).is_greater(10.0)
	assert_float(gun.barrel_reach()).is_equal_approx(5.25, 0.0001)
	# the Singularity (its own base range 9 m) reads the Gravity Gun's
	var w2 := _world()
	var sing := _gun(w2, "singularity")
	assert_float(sing.stat("range", 0.0)).is_equal(9.0)
	assert_float(sing.barrel_reach()).is_equal_approx(5.25, 0.0001)


func test_a_carried_barrel_is_out_of_the_walk_in_the_rounds_and_the_grid() -> void:
	var w := _world([_at(3.0, 0.0)])
	var bf: BarrelField = w["bf"]
	var hero: Node3D = w["hero"]
	var gun := _gun(w)
	assert_bool(gun._fire()).is_true()
	assert_bool(bf.is_carried(0)).is_true()
	_run(gun, 25)
	# he walks right under it: it does not break
	hero.global_position = Vector3(bf.pos[0].x, 0.0, bf.pos[0].z)
	bf._physics_process(DT)
	assert_int(bf.alive[0]).is_equal(1)
	# a round through it passes it by, the grid has no barrel there, a hit asked for by hand does nothing
	var at: Vector3 = bf.pos[0]
	assert_int(bf.shot_through(at + Vector3(-3, 0, 0), at + Vector3(3, 0, 0), 0.3, {})).is_equal(0)
	assert_bool(bf.shootable()).is_false()
	bf.shot_hit(0, Vector3.RIGHT, at)
	assert_int(bf.alive[0]).is_equal(1)
	assert_int(bf.shot_knocks).is_equal(0)
	# it still lands and breaks
	hero.global_position = Vector3.ZERO
	_run(gun, 200, func() -> bool: return gun.barrel_throws > 0)
	assert_int(bf.alive[0]).is_equal(0)
	assert_int(int(hero.get("hurts"))).is_equal(0)


func test_one_barrel_at_a_time_and_the_rest_of_the_pull_takes_creatures() -> void:
	var w := _world([_at(4.0, 60.0), _at(3.0, -60.0)])
	var em: EnemyManager = w["em"]
	var bf: BarrelField = w["bf"]
	var c := _creature(em, _at(4.0, 0.0))
	var gun := _gun(w, "gravity_gun", 2)
	assert_int(gun.stat_int("amount", 1)).is_equal(2)
	assert_bool(gun._fire()).is_true()
	# the nearer barrel, alone; the second grip is the creature
	assert_int(int(gun._bgrip["i"])).is_equal(1)
	assert_int(bf.carried.size()).is_equal(1)
	assert_int(gun._grips.size()).is_equal(1)
	assert_int(int(gun._grips[0]["i"])).is_equal(c)
	# busy until both are done
	assert_bool(gun._fire()).is_false()
	_run(gun, 200, func() -> bool: return gun.barrel_throws > 0)
	assert_int(bf.alive[1]).is_equal(0)
	assert_int(bf.alive[0]).is_equal(1)
	# with amount 1 a barrel takes the whole pull
	var w1 := _world([_at(3.0, 0.0)])
	var c1 := _creature(w1["em"] as EnemyManager, _at(4.0, 0.0))
	var g1 := _gun(w1)
	assert_bool(g1._fire()).is_true()
	assert_bool(g1._bgrip.is_empty()).is_false()
	assert_int(g1._grips.size()).is_equal(0)
	assert_int((w1["em"] as EnemyManager).held[c1]).is_equal(0)


func test_the_singularity_throws_a_barrel_the_same_way() -> void:
	var w := _world([_at(4.0, 0.0)])
	var bf: BarrelField = w["bf"]
	var hero: Node3D = w["hero"]
	var sing := _gun(w, "singularity")
	assert_bool(sing._fire()).is_true()
	assert_bool(bf.is_carried(0)).is_true()
	# in place of that pull's black hole
	assert_float(sing._charge).is_equal(0.0)
	_run(sing, 200, func() -> bool: return sing.barrel_throws > 0)
	assert_int(bf.alive[0]).is_equal(0)
	assert_float(Vector2(bf.pos[0].x, bf.pos[0].z).distance_to(Vector2(0.0, -float(sing._block("barrel", GravityGun.BARREL)["ahead"])))).is_less(0.01)
	assert_int(int(hero.get("hurts"))).is_equal(0)
	# it never searches
	_run(sing, 400)
	assert_int(sing.searches).is_equal(0)


func test_a_walking_outlaw_finds_the_barrel_in_front_of_where_he_got_to() -> void:
	var w := _world([_at(4.5, 90.0)])
	var bf: BarrelField = w["bf"]
	var hero: Node3D = w["hero"]
	var gun := _gun(w)
	gun._process(DT)
	assert_bool(bf.is_carried(0)).is_true()
	# he walks north at 4 m/s the whole time
	hero.set("velocity", Vector3(0, 0, -4.0))
	var frames := _run(gun, 200, func() -> bool:
		hero.global_position += Vector3(0, 0, -4.0) * DT
		return gun.barrel_throws > 0)
	assert_int(frames).is_less(200)
	# it came down within a stride of the spot ahead of him
	var land: Vector3 = bf.pos[0]
	var want := hero.global_position + Vector3(0, 0, -float(gun._block("barrel", GravityGun.BARREL)["ahead"]))
	assert_float(Vector2(land.x, land.z).distance_to(Vector2(want.x, want.z))).is_less(0.6)


func test_the_same_throw_twice_lands_the_same() -> void:
	var out: Array = []
	for _k in range(2):
		# the same rolls (a replay of the same seed): the gun's orbit and jitter are on the rule dice
		Dice.reseed(4242)
		Aim.reset()
		var w := _world([_at(4.0, -40.0), _at(5.2, 120.0)])
		var gun := _gun(w)
		var frames := _run(gun, 300, func() -> bool: return gun.barrel_throws > 0)
		var bf: BarrelField = w["bf"]
		out.append([frames, bf.pos[0], bf.pos[1], bf.alive[0], bf.alive[1]])
	assert_array(out[1]).is_equal(out[0])


# ---------------------------------------------------------------- no text tells of it

func test_no_text_tells_of_the_barrels_or_the_search() -> void:
	for id: String in ["gravity_gun", "singularity"]:
		var def: WeaponDef = Registry.weapon(id)
		for lv in range(1, def.max_level + 1):
			var inst := _inst(id, lv)
			var text := TextGen.weapon_description(def, inst.sheet, inst.params)
			var bare: Dictionary = inst.params.duplicate(true)
			var gv = bare.get("gravity", {})
			if gv is Dictionary:
				(gv as Dictionary).erase("search")
				(gv as Dictionary).erase("barrel")
			assert_str(TextGen.weapon_description(def, inst.sheet, bare)).is_equal(text)
			assert_str(text.to_lower()).not_contains("barrel")
			assert_str(text.to_lower()).not_contains("search")
		assert_str(def.flavour.to_lower()).not_contains("barrel")
	# the gun's own JSON holds both blocks (the Singularity reads them from its family)
	var g: Dictionary = Registry.weapon("gravity_gun").params["gravity"]
	assert_bool(g.get("search") is Dictionary and g.get("barrel") is Dictionary).is_true()
	assert_float(float((g["barrel"] as Dictionary)["reach_frac"])).is_equal(0.75)
