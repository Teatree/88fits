extends GdUnitTestSuite

## Pass 33: the Sun Prophet replaces the Sun Idol (and its shards hit), Berserk halves every cooldown, the Oil Slick
## leaks along the throw, cel fire, the chest's shine, the Strongbox on a balloon, the rocket's line home.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var drips: Array = []
func oil_drip(at: Vector3, _w, _dp: Dictionary) -> void:
	drips.append(at)
func fx_burst(_at: Vector3, _c: Color, _s: float) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var hits: Array = []
func take_damage(amount: float, _from: Vector3, _info: Dictionary = {}) -> void:
	hits.append(amount)
func shove(_v: Vector3) -> void:
	pass
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A projectile manager on its own, with a stand-in game that records drips and a stand-in hero at `hero_at`.
func _harness(hero_at: Vector3) -> ProjectileManager:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero: Node3D = Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	pm.register_kind(BoxMesh.new(), null)
	return pm


func _step(pm: ProjectileManager, seconds: float, dt: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		pm._physics_process(dt)
		t += dt


func test_the_prophet_replaces_the_idol() -> void:
	assert_object(Registry.enemy("sun_idol")).is_null()
	var p: EnemyDef = Registry.enemy("sun_prophet")
	assert_object(p).is_not_null()
	assert_str(p.brain).is_equal("caster")
	# eight directions: the side and both diagonal walks are in the strip (mirrored for the other half)
	for k in ["run_b", "run_s", "run_bd", "run_fd"]:
		assert_bool(p.anims.has(k)).override_failure_message("no " + k).is_true()
	# the sun beam from the sky stays
	var pillars := false
	for atk in p.boss.get("attacks", []):
		if str(atk.get("name", "")) == "erupt" and bool(atk.get("pillar", false)):
			pillars = true
	assert_bool(pillars).override_failure_message("the pillars of light are gone").is_true()
	# and he is the one the map's Elite events bring
	var found := false
	for ev in Registry.map("red_canyon").timeline.events:
		if ev.get("enemy") is Array and (ev.get("enemy") as Array).has("sun_prophet"):
			found = true
	assert_bool(found).is_true()


func test_a_shard_at_head_height_hits_the_hero() -> void:
	# a shard off the prophet's staff flies 1.3 m up (the old 3D sphere let it pass over his head)
	var pm := _harness(Vector3.ZERO)
	pm.hostile_shot(0, Vector3(0, 1.3, -6.0), Vector3(0, 0, 18.0), 13.0, 0.5, 1.0, false, {"shot": "shard"})
	_step(pm, 0.6)
	assert_int(pm.game.player.hits.size()).override_failure_message("the shard flew through the hero").is_equal(1)
	# and one that passes a metre and a half to his side still misses
	var pm2 := _harness(Vector3.ZERO)
	pm2.hostile_shot(0, Vector3(1.5, 1.3, -6.0), Vector3(0, 0, 18.0), 13.0, 0.5, 1.0, false, {"shot": "shard"})
	_step(pm2, 0.6)
	assert_int(pm2.game.player.hits.size()).is_equal(0)


func test_berserk_halves_every_cooldown() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	var w: WeaponInstance = Run.weapons[0]
	var before := w.stat("cooldown", 1.0)
	var might := Run.player_sheet.get_stat("might", 1.0)
	var b: PickupDef = Registry.pickup("rage")
	assert_str(b.display_name).is_equal("Berserk")
	Run.add_timed_effects(b.id, b.display_name, b.effects, b.duration)
	assert_float(Run.haste).is_equal_approx(2.0, 0.001)
	assert_float(w.stat("cooldown", 1.0)).is_equal_approx(before * 0.5, 0.001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_greater(might)
	# the toast names it
	assert_str(TextGen.describe_effects(b.effects)).contains("weapon speed")
	Run.elapsed += b.duration + 1.0
	Run.tick_timed()
	assert_float(Run.haste).is_equal_approx(1.0, 0.001)
	assert_float(w.stat("cooldown", 1.0)).is_equal_approx(before, 0.001)


func test_the_oil_slick_leaks_along_the_throw() -> void:
	var m: MutationDef = Registry.mutation("oil_slick")
	var dp: Dictionary = m.params.get("drip", {})
	assert_float(float(dp.get("every", 0.0))).is_greater(0.0)
	var pm := _harness(Vector3(0, 0, 50.0))
	var from := Vector3(0, 1.2, 0)
	pm.lob(0, from, Vector3(0, 0, -10.0), 10.0, 8.0, 2.0, null, 2.0, {"drip": dp})
	# most of the flight, not the landing (the stand-in game has no crowd to burn)
	_step(pm, 0.8)
	var drips: Array = pm.game.drips
	assert_int(drips.size()).override_failure_message("drips: %d" % drips.size()).is_greater_equal(4)
	# in order along the throw, none at the hero's feet
	var last := -1.0
	for d: Vector3 in drips:
		var went := Vector2(d.x - from.x, d.z - from.z).length()
		assert_float(went).is_greater_equal(float(dp.get("start", 1.2)) - 0.3)
		assert_float(went).is_greater(last)
		last = went


func test_the_rocket_leaves_a_line_home() -> void:
	var pm := _harness(Vector3(0, 0, 100.0))
	var from := Vector3(0, 2.4, 0)
	var i := pm.launch_enemy_rocket(0, 3, from, Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6)
	_step(pm, 2.0)
	assert_int(pm._paths.size()).is_equal(1)
	var pts: PackedVector3Array = pm._paths[0]["pts"]
	assert_bool(pts[0].is_equal_approx(from)).is_true()
	assert_int(pts.size()).is_greater_equal(10)
	# the rocket goes; its line fades over a second and a bit
	pm._free(i)
	_step(pm, 1.5)
	assert_int(pm._paths.size()).is_equal(0)


func test_flames_are_drawn_by_the_fire_shader() -> void:
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	fx.fire(Vector3.ZERO, 1.0)
	fx._process(0.016)
	assert_int(fx._flame_mm.visible_instance_count).is_equal(1)
	fx._process(1.0)
	assert_int(fx._flame_mm.visible_instance_count).is_equal(0)


func test_a_chest_shines() -> void:
	var c: Chest = auto_free(Chest.new())
	add_child(c)
	var shines := 0
	for n in c.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
			shines += 1
	# the pool, the sunburst, the beam and the sparkles
	assert_int(shines).is_greater_equal(4)
