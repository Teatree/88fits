extends GdUnitTestSuite

## Pass 109, lane VFX: the Vulture Raider's rocket made to pop by its material (unshaded hazard stripes, a blinking nose,
## a rim, a hot halo and a black edge as grown hulls that the stage filter never dims, an x-ray through what stands in
## front of it); the Rocket Pod looks up and fires its rockets up out of its tubes (no turning cluster); the Dragon's
## Breath's particles (BreathFlames: flames and a core from the face along the facing, stopped with the breath).

const DT := 1.0 / 60.0
const POD_TEST := preload("res://tests/pass53_weapons_a_test.gd")
const BREATH_TEST := preload("res://tests/pass95_BREATH_test.gd")


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func after_test() -> void:
	Run.end()


func _world(fake_game: String, fake_hero: String) -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(fake_game))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(fake_hero))
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
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm}


func _inst(id: String, level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _creature(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, 50.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	if em.rise_t.size() > i:
		em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


# ---------------------------------------------------------------- the rocket

func test_the_rocket_material_pops_and_is_never_dimmed() -> void:
	var game: Game = auto_free(Game.new())
	var m: ShaderMaterial = game._rocket_material()
	var body := m.shader.code
	assert_str(body).contains("unshaded")
	assert_str(body).contains("hazard")
	assert_str(body).contains("blink_hz")
	# still the paint and the exhaust mask of pass 48 underneath
	assert_str(body).contains("COLOR.rgb")
	assert_str(body).contains("1.0 - COLOR.a")
	# the halo, the black edge (wider), the x-ray
	var halo := m.next_pass as ShaderMaterial
	var edge := halo.next_pass as ShaderMaterial
	var xray := edge.next_pass as ShaderMaterial
	assert_object(xray).is_not_null()
	assert_float(float(edge.get_shader_parameter("grow"))).is_greater(float(halo.get_shader_parameter("grow")))
	var hull := halo.shader.code
	assert_str(hull).contains("depth_push")
	assert_str(hull).contains("stencil_mode write, compare_always, %d;" % StageStencil.CLEAR)
	assert_str(xray.shader.code).contains("depth_test_inverted")
	assert_str(xray.shader.code).contains("compare_not_equal, %d" % StageStencil.CLEAR)
	# the body is opaque: the stage's stencil marks it CLEAR in place and keeps the passes behind it
	assert_bool(StageStencil.is_opaque(m)).is_true()
	var marked := StageStencil.marked(m, StageStencil.CLEAR)
	assert_object(marked).is_same(m)
	assert_int(StageStencil.written(m)).is_equal(StageStencil.CLEAR)
	assert_object(m.next_pass).is_same(halo)


# ---------------------------------------------------------------- the Rocket Pod

func test_the_pod_looks_up_fires_up_from_its_tubes_and_settles() -> void:
	var w := _world(POD_TEST.FAKE_GAME, POD_TEST.FAKE_HERO)
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(0, 0, -6))
	var mp := MissilePod.new()
	(w["g"] as Node).add_child(mp)
	mp.setup(_inst("rocket_pod", 1), w["g"])
	assert_float(mp.launch_pitch()).is_equal_approx(deg_to_rad(60.0), 0.001)
	assert_bool(mp._cluster_spins).is_false()
	for k in range(30):
		mp._tick(DT)
	assert_float(mp.pitch()).is_equal_approx(0.0, 0.001)
	var spin_before: float = mp._cluster.rotation.z
	var shots0 := pm.count
	assert_bool(mp._fire()).is_true()
	# the first rocket waits for the look up: none leaves on the volley's first tick
	mp._tick(DT)
	assert_int(pm.count).is_equal(shots0)
	var first_at := -1.0
	var top := 0.0
	var t := 0.0
	while t < 1.0:
		mp._tick(DT)
		t += DT
		top = maxf(top, mp.pitch())
		if first_at < 0.0 and pm.count > shots0:
			first_at = t
			# it left going up, from the open end of a tube, while the launcher looked up
			var i := -1
			for k in range(pm.alive.size()):
				if pm.alive[k] == 1:
					i = k
			assert_int(i).is_greater_equal(0)
			assert_float(pm.vel[i].normalized().y).is_greater(0.6)
			assert_float(mp.pitch()).is_greater(mp.launch_pitch() * MissilePod.RAISED_SHARE - 0.001)
	assert_float(first_at).is_greater(0.0)
	assert_float(first_at).is_less(MissilePod.RAISE_WAIT + 0.05)
	assert_float(top).is_greater(mp.launch_pitch() * 0.95)
	# the tubes never turned, and the cluster never swelled
	assert_float(mp._cluster.rotation.z).is_equal_approx(spin_before, 0.0001)
	assert_float(mp._cluster.scale.x).is_equal_approx(1.0, 0.0001)
	# settled back once the volley is over
	for k in range(120):
		mp._tick(DT)
	assert_float(mp.pitch()).is_less(0.05)


func test_the_bees_hive_does_not_look_up() -> void:
	var w := _world(POD_TEST.FAKE_GAME, POD_TEST.FAKE_HERO)
	var mp := MissilePod.new()
	(w["g"] as Node).add_child(mp)
	mp.setup(_inst("hornet_nest", 1), w["g"])
	assert_float(mp.launch_pitch()).is_equal(0.0)


# ---------------------------------------------------------------- the Dragon's Breath

func test_the_breath_throws_particles_from_the_face_along_the_facing() -> void:
	var w := _world(BREATH_TEST.FAKE_GAME, BREATH_TEST.FAKE_HERO)
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	_creature(em, Vector3(0, 0, -2.5))
	var b := FireBreath.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst("dragons_breath", 1), w["g"])
	assert_object(b.flames()).is_null()
	assert_bool(b._fire()).is_true()
	assert_bool(b.burning()).is_true()
	var bf: BreathFlames = b.flames()
	assert_object(bf).is_not_null()
	assert_bool(bf.flames is CPUParticles3D).is_true()
	assert_bool(bf.is_emitting()).is_true()
	assert_int(bf.flames.amount + bf.core.amount).is_less_equal(BreathFlames.FLAME_MAX + BreathFlames.CORE_AMOUNT)
	# the flames reach the cone's end as they die: distance v0 L (1 + END_SPEED) / 2 ~ the reach
	var reach := b.stat("range", 5.0)
	var v0: float = bf.flames.initial_velocity_max
	assert_float(v0 * BreathFlames.FLAME_LIFE * (1.0 + BreathFlames.END_SPEED) * 0.5).is_between(reach * 0.85, reach * 1.1)
	# from the face, along where he faces; turned when he turns
	b._tick(DT)
	assert_float(bf.global_position.distance_to(b.origin())).is_less(0.01)
	assert_float((-bf.global_transform.basis.z).dot(b.dir())).is_greater(0.99)
	hero.facing = PI * 0.5
	b._tick(DT)
	assert_float((-bf.global_transform.basis.z).dot(b.dir())).is_greater(0.99)
	# stops with the breath
	for k in range(int(b.last_len / DT) + 10):
		b._tick(DT)
	assert_bool(b.burning()).is_false()
	assert_bool(bf.is_emitting()).is_false()


func test_blue_flame_burns_blue_particles() -> void:
	var bf: BreathFlames = auto_free(BreathFlames.new())
	add_child(bf)
	bf.start(5.0, 50.0, false, true, 1.0)
	var c: Color = bf.flames.color_ramp.sample(0.36)
	assert_float(c.b).is_greater(c.r)
	bf.start(5.0, 50.0, false, false, 1.0)
	c = bf.flames.color_ramp.sample(0.36)
	assert_float(c.r).is_greater(c.b)
	# a ring throws them all round, flat
	bf.start(5.0, 360.0, true, false, 1.0)
	assert_float(bf.flames.spread).is_greater(150.0)
	assert_float(bf.flames.flatness).is_equal(1.0)
