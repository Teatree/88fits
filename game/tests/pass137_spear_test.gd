extends GdUnitTestSuite

## Pass 137, lane SPEAR: the Spear's thrust redrawn (MeleeFx: a spearhead leading a streak). The head lands as the hit
## does, at the hit's own reach from the Outlaw: the impact star (with its shock ring) on a hit, a small glint on a miss;
## it snaps back and is gone with the stroke; Heartseeker's crit heats it red, the Thunder Lance's thrust crackles, plain
## steel neither; still one thrust quad and one star a blade, the pools capped.

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
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
"""

const DT := 1.0 / 60.0

var _aim_was := true
var _ff_was := false


func before_test() -> void:
	_aim_was = Settings.aim_mode
	_ff_was = Settings.fire_forward
	Settings.aim_mode = true


func after_test() -> void:
	Settings.aim_mode = _aim_was
	Settings.fire_forward = _ff_was


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
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
	return {"g": g, "hero": hero, "em": em}


func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	return i


func _thruster(w: Dictionary, id: String, muts: Array = [], level := 1) -> Thruster:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	var b := Thruster.new()
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## Ticks the stroke through (`secs` seconds).
func _run_for(b: Thruster, secs: float) -> void:
	var n := int(secs / DT)
	for k in range(n):
		b._tick(DT)


func _any_blade_shown(b: Thruster) -> bool:
	for bl: Node3D in b._blades:
		if bl.visible:
			return true
	return false


## The angle (degrees) between flat directions.
func _deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))))



func _entry_of(fx: MeleeFx, k := 0) -> Dictionary:
	var live: Array = fx._thrusts.filter(func(e: Dictionary) -> bool: return bool(e["live"]))
	return live[k] if k < live.size() else {}


# ---------------------------------------------------------------- the landing

func test_a_hit_lands_the_impact_star_at_the_reach_as_the_hit_lands() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(0, 0, -3.0))
	em._rebuild_grid()
	var b := _thruster(w, "pike")
	assert_bool(b._fire()).is_true()
	var fx := b.effects()
	assert_object(fx).is_not_null()
	# step until the stroke's hit: no star before it, one right on it
	var t := 0.0
	while not b._hit_done and t < 1.0:
		assert_int(fx.flashes_made).is_equal(0)
		b._tick(DT)
		t += DT
	assert_bool(b._hit_done).is_true()
	assert_int(fx.impacts_made).is_equal(1)
	assert_int(fx.glints_made).is_equal(0)
	assert_int(fx.flashes_made).is_equal(1)
	# the star stands at the hit's own reach from him, down the thrust
	var hero: Node3D = w["hero"]
	var flat := fx.last_flash_at - hero.global_position
	flat.y = 0.0
	assert_float(flat.length()).is_equal_approx(b._reach(), 0.02)
	assert_float(_deg(flat, b._dir)).is_less(0.5)


func test_a_miss_lands_a_glint_and_no_star() -> void:
	var w := _world()
	var b := _thruster(w, "pike")
	assert_bool(b._fire()).is_true()
	_run_for(b, 0.3)
	var fx := b.effects()
	assert_int(fx.thrusts_made).is_equal(1)
	assert_int(fx.impacts_made).is_equal(0)
	assert_int(fx.glints_made).is_equal(1)
	assert_int(fx.flashes_made).is_equal(1)


func test_the_head_darts_out_then_snaps_back_and_is_gone_with_the_stroke() -> void:
	var w := _world()
	var b := _thruster(w, "pike")
	b._fire()
	var fx := b.effects()
	var e := _entry_of(fx)
	assert_bool(e.is_empty()).is_false()
	var m: ShaderMaterial = e["mat"]
	var full := float(e["full"])
	# the head's point never passes the reach by more than its small overshoot, and reaches it
	var most := 0.0
	var shown_at_hit := false
	for k in range(int(0.3 / DT)):
		b._tick(DT)
		if bool(e["live"]) and (e["mi"] as MeshInstance3D).visible:
			most = maxf(most, float(m.get_shader_parameter("pt")))
		if b._hit_done and not shown_at_hit:
			shown_at_hit = true
			assert_float(float(m.get_shader_parameter("pt"))).is_greater(full * 0.95)
			assert_float(float(m.get_shader_parameter("pt_a"))).is_equal_approx(1.0, 0.001)
	assert_float(most).is_greater_equal(full * 0.99)
	assert_float(most).is_less_equal(full + 0.11)
	_run_for(b, 0.5)
	assert_bool(bool(e["live"])).is_false()
	assert_int(fx.thrusts_live()).is_equal(0)
	assert_int(fx.flashes_live()).is_equal(0)


# ---------------------------------------------------------------- each build its touch

func test_the_head_heats_with_heartseeker_and_the_thunder_lance_crackles() -> void:
	var w := _world()
	var plain := _thruster(w, "pike")
	var pl := plain._fx_thrust_look()
	assert_float(float(pl["heat"])).is_equal(0.0)
	assert_float(float(pl["crackle"])).is_equal(0.0)
	var hs := _thruster(w, "pike", ["heartseeker"])
	var heats: Array = []
	for k in range(4):
		hs._fire()
		heats.append(float(hs._fx_thrust_look()["heat"]))
		_run_for(hs, 1.0)
	# the warm-up warms the head, the 4th (the crit) is red-hot
	assert_float(float(heats[1])).is_greater(float(heats[0]))
	assert_float(float(heats[3])).is_greater_equal(0.8)
	var vt := _thruster(w, "pike", ["venom_tip"])
	assert_float(float(vt._fx_thrust_look()["heat"])).is_greater(0.0)
	var tl := _thruster(w, "thunder_lance")
	tl._fire()
	var crackles := 0
	for k in range(int(1.5 / DT)):
		tl._tick(DT)
		if tl._combo == 2 and float(tl._fx_thrust_look()["crackle"]) > 0.0:
			crackles += 1
	assert_int(crackles).is_greater(0)
	assert_int(tl.effects().thrusts_made).is_equal(2)
	assert_int(tl.tip_bolts).is_equal(1)


# ---------------------------------------------------------------- cheap

func test_one_quad_and_one_star_a_blade_and_the_pools_capped() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(0, 0, -3.0))
	em._rebuild_grid()
	var b5 := _thruster(w, "pike", [], 5)
	b5._fire()
	_run_for(b5, 0.3)
	var fx := b5.effects()
	assert_int(fx.thrusts_made).is_equal(b5._active)
	assert_int(fx.flashes_made).is_equal(b5._active)
	assert_int(fx.pool_sizes().y).is_equal(b5._active)
	var hero: Node3D = w["hero"]
	var own := MeleeFx.new()
	(w["g"] as Node).add_child(own)
	for k in range(30):
		own.thrust(hero, Vector3.FORWARD, 4.6, 0.3, 0.0, 0.08, 0.06, 0.22)
		own.tick(DT * 8.0)
	assert_int(own.pool_sizes().y).is_equal(MeleeFx.THRUST_MAX)
	assert_int(own.pool_sizes().z).is_less_equal(MeleeFx.FLASH_MAX)
	own.queue_free()
