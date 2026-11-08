extends GdUnitTestSuite

## Pass 136, lane PLACED (Garry on the weapons-aim proposal, R6: "Yes, but not in a cone, in a circle"): under the aim
## (Settings.aim_mode, Aim.covers) the Dynamite, the Molotov and the Skull Rain throw on spots in a circle round the
## Outlaw, scored by what the blast would catch, the best 60% of the time (Fire in the Hole 80%), apart from each other,
## on the run's aim dice, and land on the sand with nobody anywhere; the Skull Rain's cloud holds a 3D skull for its life
## (GroundSkulls); the Hammer comes down every pull; the Land Mine is flicked 2 m down the facing while he walks (the
## Jackrabbit 3 m); the Turret Buddy is set 2-3 m out on the crowd's side, facing his aim; the switch off plays as before.

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
var bolts: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
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
func fx_lightning(pts) -> void:
	bolts.append(pts)
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
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
var still := false
var fwd := Vector3.FORWARD
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return still
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
	return fwd
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func kick(_a = 0.0, _b = 0.0) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0

var _aim_was := true


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_aim_was = Settings.aim_mode
	Settings.aim_mode = true
	Dice.reseed(4242)
	Aim.reset()


func after_test() -> void:
	Settings.aim_mode = _aim_was
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "tg": tg}


func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	em.rise_t[i] = 1.0
	em.pos[i] = at
	if em.onscreen.size() > i:
		em.onscreen[i] = 1
	return i


func _inst(id: String, level := 1, muts: Array = []) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		inst.mutations.append(Registry.mutation(m))
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, inst: WeaponInstance) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## Where the lobs in flight are headed (ProjectileManager's extra.target).
func _lob_targets(pm: ProjectileManager) -> Array:
	var out: Array = []
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1 and pm.extra[i] is Dictionary and (pm.extra[i] as Dictionary).has("target"):
			out.append((pm.extra[i] as Dictionary)["target"])
	return out


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- the circle (Aim.circle_spots)

func test_every_placed_weapon_carries_an_aim_block() -> void:
	for id: String in ["lob_grenade", "molotov", "skull_rain", "hammer", "land_mine", "turret_buddy",
			"golden_pineapple", "moonshine", "grave_hail", "earthshaker", "jackrabbit_mines", "iron_bastion"]:
		var c := Aim.cfg(_inst(id))
		assert_str(str(c.get("family", ""))).override_failure_message(id).is_equal("placed")
	assert_float(float(Aim.cfg(_inst("jackrabbit_mines")).get("lay_ahead", 0.0))).is_equal(3.0)
	assert_bool(GroundSkulls.cfg(_inst("skull_rain")).is_empty()).is_false()
	assert_bool(GroundSkulls.cfg(_inst("grave_hail")).is_empty()).is_false()
	assert_bool(ResourceLoader.exists(GroundSkulls.MODEL)).is_true()


func test_spots_fill_the_circle_on_every_side() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var quad := [0, 0, 0, 0]
	var n := 400
	for k in range(n):
		var p: Vector3 = Aim.circle_spots(em, Vector3.ZERO, 2.0, 10.0, 1, 2.5)[0]
		var d := Vector2(p.x, p.z).length()
		assert_float(d).is_between(2.0 - 0.001, 10.0 + 0.001)
		quad[(1 if p.x >= 0.0 else 0) + (2 if p.z >= 0.0 else 0)] += 1
	# never all on one side: each quarter takes a fair share (25% expected)
	for q: int in quad:
		assert_int(q).is_greater(n / 8)


func test_spots_of_a_volley_keep_apart() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(50):
		var s: Array = Aim.circle_spots(em, Vector3.ZERO, 2.0, 10.0, 3, 2.0)
		assert_int(s.size()).is_equal(3)
		for a in range(3):
			for b in range(a + 1, 3):
				assert_float(_flat(s[a], s[b])).is_greater_equal(2.0 * Aim.APART - 0.001)


func test_spots_are_the_same_for_the_same_seed() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Dice.reseed(77)
	Aim.reset()
	var a: Array = Aim.circle_spots(em, Vector3.ZERO, 2.0, 10.0, 3, 2.5)
	Dice.reseed(77)
	Aim.reset()
	var b: Array = Aim.circle_spots(em, Vector3.ZERO, 2.0, 10.0, 3, 2.5)
	for k in range(3):
		assert_bool((a[k] as Vector3).is_equal_approx(b[k])).is_true()


func test_spots_lean_to_the_crowd() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(9):
		_creature(em, Vector3(6.0 + 0.3 * float(k % 3), 0, -0.3 + 0.3 * float(k / 3)))
	em._rebuild_grid()
	var near := 0
	var n := 200
	for k in range(n):
		var p: Vector3 = Aim.circle_spots(em, Vector3.ZERO, 2.0, 10.0, 1, 2.5)[0]
		if _flat(p, Vector3(6.3, 0, 0)) <= 2.5 + 0.6:
			near += 1
	# up to Aim.CROWD_SEEDED of the six candidates stand on a creature, so the best catches the crowd and is taken 60% of
	# the time, and the seeded others land there too; a spot at random would land there about 9% of the time
	assert_int(near).is_greater(int(n * 0.5))
	assert_int(near).is_less(n)


# ---------------------------------------------------------------- the Lobber

func test_dynamite_lands_dry_with_nobody_anywhere() -> void:
	var w := _world()
	var lob: Lobber = _behaviour(w, Lobber.new(), _inst("lob_grenade"))
	assert_bool(lob._fire()).is_true()
	assert_int(lob.placed_throws).is_equal(1)
	var t: Array = _lob_targets(w["pm"])
	assert_int(t.size()).is_equal(1)
	var d := _flat(t[0], (w["hero"] as Node3D).global_position)
	assert_float(d).is_between(2.0 - 0.001, 10.0 + 0.001)
	assert_int(int(Aim.dry_counts().get("lob_grenade", 0))).is_greater_equal(1)


func test_dynamite_volley_spots_keep_apart() -> void:
	var w := _world()
	var lob: Lobber = _behaviour(w, Lobber.new(), _inst("lob_grenade", 3))
	assert_int(lob.stat_int("amount", 1)).is_equal(2)
	assert_bool(lob._fire()).is_true()
	var t: Array = _lob_targets(w["pm"])
	assert_int(t.size()).is_equal(2)
	assert_float(_flat(t[0], t[1])).is_greater_equal(lob.stat("area", 2.5) * Aim.APART - 0.001)


func test_dynamite_scores_by_the_crowd_to_come() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(6):
		_creature(em, Vector3(-0.6 + 0.3 * float(k), 0, -7.0))
	em._rebuild_grid()
	var lob: Lobber = _behaviour(w, Lobber.new(), _inst("lob_grenade"))
	var s: Array = lob.placed_scores([Vector3(0, 0, -6.5), Vector3(0, 0, 6.5)], Vector3(0, 1.2, 0), Vector3.ZERO, 2.8)
	assert_float(float(s[0])).is_greater(float(s[1]))


func test_switch_off_plays_as_before() -> void:
	Settings.aim_mode = false
	var w := _world()
	var lob: Lobber = _behaviour(w, Lobber.new(), _inst("lob_grenade"))
	# nobody anywhere: the old aim holds its throw
	assert_bool(lob._fire()).is_false()
	assert_int(lob.placed_throws).is_equal(0)
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(0, 0, -6))
	em._rebuild_grid()
	assert_bool(lob._fire()).is_true()
	assert_int(lob.placed_throws).is_equal(0)
	var hm: Smasher = _behaviour(_world(), Smasher.new(), _inst("hammer"))
	assert_bool(hm._fire()).is_false()


func test_fire_in_the_hole_takes_the_best_more_often() -> void:
	assert_float(float(Aim.cfg(_inst("lob_grenade"))["best_chance"])).is_equal(0.6)
	var fith := Aim.cfg(_inst("lob_grenade", 1, ["fire_in_the_hole"]))
	assert_float(float(fith["best_chance"])).is_equal(0.8)
	assert_str(str(fith["family"])).is_equal("placed")


func test_molotov_prefers_the_unburnt() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var burning: Array = []
	for k in range(6):
		burning.append(_creature(em, Vector3(6.0 + 0.3 * float(k % 3), 0, 0.3 * float(k / 3))))
	for k in range(3):
		_creature(em, Vector3(-6.0 + 0.3 * float(k), 0, 0))
	em._rebuild_grid()
	var inst := _inst("molotov")
	for i: int in burning:
		em.ignite(i, "molotov", 4.0, 30.0, 0.0)
	var west := 0
	var east := 0
	for k in range(100):
		var p: Vector3 = Aim.circle_spots(em, Vector3.ZERO, 2.0, 10.0, 1, 2.0, 0.6, inst.element())[0]
		if _flat(p, Vector3(-5.7, 0, 0)) <= 2.6:
			west += 1
		if _flat(p, Vector3(6.3, 0, 0.15)) <= 2.6:
			east += 1
	assert_int(west).is_greater(east)


# ---------------------------------------------------------------- the skull on the sand

func test_skull_sits_for_the_cloud_and_goes() -> void:
	var w := _world()
	var g: Node = w["g"]
	var c := ElementCloud.new()
	c.params = {}
	c.setup(g, _inst("skull_rain"), 2.2, 1.5, 3.0, 1, 10.0)
	g.add_child(c)
	var gs := GroundSkulls.of(g)
	assert_object(gs).is_not_null()
	assert_int(gs.count()).is_equal(1)
	for k in range(30):
		gs._process(DT)
	# popped up and sitting
	assert_float(gs.rise_of(0)).is_greater(0.95)
	for k in range(int(1.3 / DT)):
		gs._process(DT)
	# sinking away over the cloud's last half second
	assert_float(gs.rise_of(0)).is_less(0.95)
	for k in range(30):
		gs._process(DT)
	assert_int(gs.count()).is_equal(0)


func test_no_skull_for_a_puff_or_a_fire_pool() -> void:
	var w := _world()
	var g: Node = w["g"]
	var puff := ElementCloud.new()
	puff.params = {"pool_seconds": 1.5}
	puff.setup(g, _inst("skull_rain"), 1.0, 1.5, 3.0, 1, 10.0)
	g.add_child(puff)
	var fire := ElementCloud.new()
	fire.params = {}
	fire.setup(g, _inst("molotov"), 2.0, 3.0, 4.0, 1, 1.8, "fire")
	g.add_child(fire)
	var gs := GroundSkulls.of(g)
	assert_int(gs.count()).is_equal(0)
	assert_int(GroundSkulls.place_for(g, _inst("grave_hail"), Vector3.ZERO, 2.2, 3.0)).is_greater_equal(0)
	assert_int(gs.count()).is_equal(1)


func test_many_skulls_share_one_pool() -> void:
	var w := _world()
	var g: Node = w["g"]
	var inst := _inst("skull_rain")
	for k in range(40):
		GroundSkulls.place_for(g, inst, Vector3(float(k), 0, 0), 2.2, 4.0)
	var gs := GroundSkulls.of(g)
	assert_int(gs.count()).is_equal(40)
	# one MultiMesh for the model and its tint
	assert_int(gs.get_child_count()).is_equal(1)


# ---------------------------------------------------------------- the Hammer

func test_hammer_strikes_with_nobody_near() -> void:
	var w := _world()
	var hm: Smasher = _behaviour(w, Smasher.new(), _inst("hammer"))
	assert_bool(hm._fire()).is_true()
	assert_int(hm._swings.size()).is_equal(1)
	var at: Vector3 = hm._swings[0]["at"]
	assert_float(_flat(at, Vector3.ZERO)).is_between(1.0 - 0.001, hm.stat("range", 4.6) + 0.001)


# ---------------------------------------------------------------- the Land Mine

func test_mines_are_flicked_ahead_while_he_walks() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var ml: MineLayer = _behaviour(w, MineLayer.new(), _inst("land_mine"))
	hero.set("velocity", Vector3(0, 0, -4))
	for k in range(40):
		var pts: Array = ml.aim_points(2)
		assert_float(_flat(pts[0], Vector3.ZERO)).is_equal_approx(2.0, 0.001)
		assert_float(rad_to_deg(Aim.angle_off(Vector3.ZERO, Vector3.FORWARD, pts[0]))).is_less_equal(30.001)
		assert_float(rad_to_deg(Aim.angle_off(Vector3.ZERO, Vector3.FORWARD, pts[1]))).is_less_equal(30.001)
		# the second to the other side of the facing
		assert_bool(signf((pts[0] as Vector3).x) * signf((pts[1] as Vector3).x) <= 0.0).is_true()
	# standing: at his feet
	hero.set("velocity", Vector3.ZERO)
	assert_float(_flat(ml.aim_points(1)[0], Vector3.ZERO)).is_less(0.001)
	var jr: MineLayer = _behaviour(w, MineLayer.new(), _inst("jackrabbit_mines"))
	hero.set("velocity", Vector3(0, 0, -4))
	assert_float(_flat(jr.aim_points(1)[0], Vector3.ZERO)).is_equal_approx(3.0, 0.001)


# ---------------------------------------------------------------- the Turret Buddy

func test_turret_set_on_the_crowds_side_facing_his_aim() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(8):
		_creature(em, Vector3(7.0, 0, -1.0 + 0.3 * float(k)))
	em._rebuild_grid()
	var sp: Spawner = _behaviour(w, Spawner.new(), _inst("turret_buddy"))
	var east := 0
	for k in range(20):
		assert_bool(sp._fire()).is_true()
		var t: Turret = sp._turrets[sp._turrets.size() - 1]
		var d := _flat(t.global_position, Vector3.ZERO)
		assert_float(d).is_between(2.0 - 0.001, 3.0 + 0.001)
		if t.global_position.x > 0.0:
			east += 1
		# its head starts down his facing (Vector3.FORWARD: yaw 0)
		assert_float(absf(angle_difference(t._head_yaw(), 0.0))).is_less(0.01)
	assert_int(east).is_greater(12)
