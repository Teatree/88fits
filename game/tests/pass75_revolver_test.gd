extends GdUnitTestSuite

## Pass 75 (Garry: "Let's work on the 3D object of the revolver. The shots still feel sluggish and jerky. Let's make it so
## the revolver does a little spin every now and then right after firing a shot. There should be much more visible impact
## on the revolver every time it shoots as well, a bigger punch."): the Revolver's and the Golden Revolver's companion
## carries `familiar.kick` and `familiar.spin`. The kick shows on the frame the round leaves and is never smoothed by the
## eased follow; it springs back past rest and settles; the gun aims along its own line to the target between shots. A
## trick spin follows the last round of a pull now and then, never within its gap, only when it ends before the next pull.
## Every other companion is as it was. The fakes below are pass48_projectiles_test's.

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
var clouds: Array = []
var toasts: Array = []
func toast(t, _c = null) -> void:
	toasts.append(str(t))
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
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func spawn_cloud(at: Vector3, w, radius: float, element: String = "poison", params: Dictionary = {}) -> void:
	var c := ElementCloud.new()
	c.slow = float(params.get("slow", 0.0))
	c.blue = w != null and w.blue_fire()
	c.params = params
	if element == "fire":
		c.setup(self, w, radius, float(w.params.get("cloud_seconds", 3.0)), w.stat("fire_damage", 4.0), 1, w.stat("fire_duration", 1.8), "fire", w.stat("fire_spread", 0.5))
	else:
		c.setup(self, w, radius, float(w.params.get("cloud_seconds", 4.0)), w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 10.0))
	c.position = Vector3(at.x, 0.0, at.z)
	add_child(c)
	clouds.append({"at": at, "r": radius, "element": element, "params": params, "node": c})
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
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

func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at`, with the real crowd, shots, effects and ground marks.
func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam}


## A tough creature on its feet where it was put, taking every hit whole.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	return i


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	var pe := ProjectileEmitter.new()
	(w["g"] as Node).add_child(pe)
	pe.setup(inst, w["g"])
	return pe


## The live shots of weapon `inst`, ghosts left out.
func _live_of(pm: ProjectileManager, inst: WeaponInstance) -> Array:
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst and not (pm.extra[j] as Dictionary).has("ghost"):
			out.append(j)
	return out


func before_test() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func _kick_of(id: String) -> Dictionary:
	var w = Registry.weapon(id)
	return (w.params.get("familiar", {}) as Dictionary).get("kick", {})


func _spin_of(id: String) -> Dictionary:
	var w = Registry.weapon(id)
	return (w.params.get("familiar", {}) as Dictionary).get("spin", {})


## A revolver emitter facing a tough creature up the screen, its companion settled for a frame.
func _revolver(w: Dictionary, id := "revolver", at := Vector3(0, 0, -6)) -> ProjectileEmitter:
	_creature(w["em"], at)
	(w["em"] as EnemyManager)._rebuild_grid()
	var pe := _emitter(w, _inst(id))
	pe.cooldown_left = 99.0
	pe._tick(DT)
	return pe


func test_both_revolvers_carry_the_kick_and_the_spin() -> void:
	for id: String in ["revolver", "golden_revolver"]:
		var k := _kick_of(id)
		var s := _spin_of(id)
		for key: String in ["back", "climb", "twist", "pop", "hz", "decay"]:
			assert_bool(k.has(key)).override_failure_message("%s kick lacks %s" % [id, key]).is_true()
			assert_float(float(k[key])).is_greater(0.0)
		for key: String in ["chance", "seconds", "turns", "gap", "hop"]:
			assert_bool(s.has(key)).override_failure_message("%s spin lacks %s" % [id, key]).is_true()
		assert_float(float(s["chance"])).is_between(0.01, 0.99)


func test_the_kick_shows_on_the_frame_the_round_leaves_unsmoothed() -> void:
	var w := _world()
	var pe := _revolver(w)
	var k := _kick_of("revolver")
	var base: Vector3 = pe._fam_base
	assert_bool(pe._fire()).is_true()
	# no tick yet: the very frame the round leaves
	assert_float(pe.punch()).is_equal_approx(1.0, 0.001)
	var fam: Node3D = pe._familiar
	assert_float(fam.scale.x).is_equal_approx(1.0 + float(k["pop"]), 0.001)
	assert_float(fam.rotation.x).is_equal_approx(float(k["climb"]), 0.001)
	# thrown back along its barrel by the whole `back`, not the few centimetres the eased follow used to let through
	var aim := Vector3(-sin(pe._aim_yaw), 0, -cos(pe._aim_yaw))
	var off: Vector3 = fam.global_position - pe._fam_base
	assert_float(off.dot(-aim)).is_equal_approx(float(k["back"]), 0.01)
	assert_float(pe._fam_base.distance_to(base)).is_less(0.05)


func test_the_kick_springs_past_rest_and_settles() -> void:
	var w := _world()
	var pe := _revolver(w)
	assert_bool(pe._fire()).is_true()
	var low := 1.0
	for f in range(60):
		pe._tick(DT)
		low = minf(low, pe.punch())
	# it swung back past rest (the barrel forward of it, the gun a little thin) ...
	assert_float(low).is_less(-0.1)
	# ... and a second later it is at rest
	assert_float(pe.punch()).is_equal(0.0)
	assert_float(pe._familiar.scale.x).is_equal_approx(1.0, 0.001)
	assert_float(absf(pe._familiar.rotation.x)).is_less(0.001)


func test_a_silver_round_kicks_harder() -> void:
	var w := _world()
	var pe := _revolver(w)
	pe._start_punch(true)
	assert_float(pe.punch()).is_equal_approx(ProjectileEmitter.SILVER_PUNCH, 0.001)
	assert_float(pe.punch()).is_greater(1.0)
	# a round on a gun still kicking stacks, capped
	pe._start_punch(true)
	assert_float(pe.punch()).is_less_equal(ProjectileEmitter.KICK_STACK_MAX + 0.001)


func test_a_trick_spin_follows_the_pull_and_ends() -> void:
	var w := _world()
	var pe := _revolver(w)
	pe.debug_force_spin()
	assert_bool(pe._fire()).is_true()
	assert_bool(pe.spinning()).is_true()
	assert_int(pe.trick_spins).is_equal(1)
	var secs := float(_spin_of("revolver")["seconds"])
	var turned := 0.0
	var t := 0.0
	while t < secs - DT:
		pe._tick(DT)
		t += DT
		turned = minf(turned, pe._familiar.rotation.x)
	# about the trigger guard, most of a turn (the last frames ease in)
	assert_float(turned).is_less(-TAU * 0.9)
	pe._tick(DT * 3.0)
	assert_bool(pe.spinning()).is_false()


func test_a_trick_spin_keeps_its_gap_and_ends_before_the_next_pull() -> void:
	var w := _world()
	var pe := _revolver(w)
	# every pull would spin
	pe.inst.params = pe.inst.params.duplicate(true)
	(pe.inst.params["familiar"]["spin"] as Dictionary)["chance"] = 1.0
	pe._since_spin = 10.0
	assert_bool(pe._fire()).is_true()
	assert_int(pe.trick_spins).is_equal(1)
	for f in range(40):
		pe._tick(DT)
	assert_bool(pe.spinning()).is_false()
	# well inside its gap: no spin
	assert_bool(pe._fire()).is_true()
	assert_int(pe.trick_spins).is_equal(1)
	# past the gap, but the next pull comes before a spin could end (a burst's last round late in the clock): no spin
	pe._since_spin = 10.0
	pe.cooldown_left = 0.2
	pe._maybe_trick_spin()
	assert_int(pe.trick_spins).is_equal(1)
	# with the time, it spins
	pe.cooldown_left = 0.9
	pe._maybe_trick_spin()
	assert_int(pe.trick_spins).is_equal(2)


func test_it_aims_along_its_own_line_to_the_target() -> void:
	var w := _world()
	var at := Vector3(3, 0, -5)
	var pe := _revolver(w, "revolver", at)
	for f in range(90):
		pe._tick(DT)
	var to: Vector3 = at - pe._fam_base
	assert_float(absf(angle_difference(pe._aim_yaw, atan2(-to.x, -to.z)))).is_less(0.05)


func test_other_companions_are_as_before() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -6))
	(w["em"] as EnemyManager)._rebuild_grid()
	var pe := _emitter(w, _inst("tommy_gun"))
	assert_bool(pe._fam_dict("kick").is_empty()).is_true()
	assert_bool(pe._fire()).is_true()
	assert_bool(pe._fam_base_set).is_false()
	assert_float(pe.punch()).is_equal(0.0)
	assert_bool(pe._familiar.scale.is_equal_approx(Vector3(1.18, 0.86, 1.18))).is_true()
