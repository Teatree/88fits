extends GdUnitTestSuite

## Pass 53, the lead's merge: the tumbleweed hooks in ProjectileManager (Thorny Weed rolls out slower over the same
## ground and comes back faster, the Dust Devil hits twice as hard on the way back and makes a second pass, Dust
## Wake's aura slows and tints what stands in it and the Dust Devil's pulls), and TextGen's words for the new Thruster
## and MissilePod rules (the Thunder Lance, the Whirlwind, the Hellfire Battery read what they do).

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

const DT := 1.0 / 60.0


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


func _kind(pm: ProjectileManager) -> int:
	var mat := StandardMaterial3D.new()
	return pm.register_kind(SphereMesh.new(), mat, 0.5)


func _creature(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	return i


## Thorny Weed: the shot leaves at 0.7 of its speed and lives 1 / 0.7 as long, so it rolls over the same ground.
func test_thorny_weed_rolls_out_slower_over_the_same_ground() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("tumbleweed", ["thorns"])
	assert_float(float(inst.params.get("out_speed_mult", 1.0))).is_equal_approx(0.7, 0.001)
	var k := _kind(pm)
	var i := pm.fire(k, Vector3(0, 0.6, 0), Vector3(6, 0, 0), 10.0, 40, 0.7, 2.0, inst, 1.0)
	assert_int(i).is_greater_equal(0)
	assert_float(pm.vel[i].length()).is_equal_approx(4.2, 0.001)
	assert_float(pm.life[i]).is_equal_approx(2.0 / 0.7, 0.001)
	# a plain weed keeps its launch speed and life
	var j := pm.fire(k, Vector3(0, 0.6, 0), Vector3(6, 0, 0), 10.0, 40, 0.7, 2.0, _inst("tumbleweed"), 1.0)
	assert_float(pm.vel[j].length()).is_equal_approx(6.0, 0.001)
	assert_float(pm.life[j]).is_equal_approx(2.0, 0.001)


## The Dust Devil's weed turns at the end of its run, comes home at 1.5 times its launch speed hitting twice as hard,
## then goes out once more before it is freed.
func test_the_dust_devil_comes_back_harder_and_makes_a_second_pass() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("dust_devil", ["thorns", "dust_wake", "boomerang"])
	assert_bool(bool(inst.params.get("return", false))).is_true()
	assert_float(float(inst.params.get("back_speed_mult", 1.0))).is_equal_approx(1.5, 0.001)
	assert_float(float(inst.params.get("return_damage_mult", 1.0))).is_equal_approx(2.0, 0.001)
	assert_bool(bool(inst.params.get("second_pass", false))).is_true()
	var k := _kind(pm)
	var i := pm.fire(k, Vector3(0, 0.6, 0), Vector3(6, 0, 0), 10.0, 80, 0.9, 1.0, inst, 1.0)
	assert_int(pm.ret[i]).is_equal(1)
	assert_int(int(pm.extra[i].get("passes", 1))).is_equal(0)
	# out at 0.8 of 6 for 1 / 0.8 s, then the turn
	assert_float(pm.vel[i].length()).is_equal_approx(4.8, 0.001)
	var steps := 0
	while pm.ret[i] == 1 and steps < 200:
		pm._physics_process(DT)
		steps += 1
	assert_int(pm.ret[i]).is_equal(2)
	assert_float(pm.vel[i].length()).is_equal_approx(9.0, 0.01)
	assert_float(pm.dmg[i]).is_equal_approx(20.0, 0.001)
	# home: the second pass leaves again from the hero at the launch damage, and the shot is still alive
	steps = 0
	while pm.ret[i] == 2 and pm.alive[i] == 1 and steps < 600:
		pm._physics_process(DT)
		steps += 1
	assert_int(pm.alive[i]).is_equal(1)
	assert_int(pm.ret[i]).is_equal(1)
	assert_int(int(pm.extra[i].get("passes", 0))).is_equal(1)
	assert_float(pm.dmg[i]).is_equal_approx(10.0, 0.001)
	assert_float((pm.pos[i] - w["hero"].global_position).length()).is_less(2.0)
	# the second turn and the way home end it
	steps = 0
	while pm.alive[i] == 1 and steps < 1200:
		pm._physics_process(DT)
		steps += 1
	assert_int(pm.alive[i]).is_equal(0)


## Dust Wake: a creature inside the wake is slowed by a fifth and tinted; nothing happens to one outside it.
func test_the_dust_wake_slows_and_tints_what_stands_in_it() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var inside := _creature(em, Vector3(1.0, 0, 0.8))
	var outside := _creature(em, Vector3(6.0, 0, 0))
	var inst := _inst("tumbleweed", ["dust_wake"])
	var au: Dictionary = inst.params.get("aura", {})
	assert_float(float(au.get("radius", 0.0))).is_equal_approx(1.6, 0.001)
	assert_float(float(au.get("slow", 0.0))).is_equal_approx(0.2, 0.001)
	var k := _kind(pm)
	var i := pm.fire(k, Vector3(0, 0.6, 0), Vector3(0.01, 0, 0), 1.0, 40, 0.7, 5.0, inst, 0.0)
	assert_bool(pm.extra[i].has("aura_t")).is_true()
	pm._physics_process(DT)
	assert_float(em.slow_f[inside]).is_equal_approx(0.2, 0.001)
	assert_float(em.slow_t[inside]).is_greater(0.0)
	assert_float(em.status_t[inside]).is_greater(0.0)
	assert_float(em.slow_t[outside]).is_equal_approx(0.0, 0.001)
	assert_float(em.status_t[outside]).is_equal_approx(0.0, 0.001)


## The Dust Devil's wake pulls what it slows toward the weed.
func test_the_dust_devils_wake_pulls() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(2.0, 0, 0))
	var inst := _inst("dust_devil", ["thorns", "dust_wake", "boomerang"])
	assert_float(float((inst.params.get("aura", {}) as Dictionary).get("pull", 0.0))).is_equal_approx(2.5, 0.001)
	var k := _kind(pm)
	pm.fire(k, Vector3(0, 0.6, 0), Vector3(0.001, 0, 0), 1.0, 80, 0.9, 5.0, inst, 0.0)
	var before := em.pos[i].x
	for _k in range(30):
		pm._physics_process(DT)
	assert_float(em.pos[i].x).is_less(before - 0.3)


## TextGen says the new rules: the Thunder Lance's sweep-and-thrust and stun, the Whirlwind's refund, the Hellfire
## Battery's bomblets, pressure and double volley.
func test_textgen_says_the_new_rules() -> void:
	var lance := _inst("thunder_lance", ["stunning_thrust", "long_spear", "pike_sweep"])
	var t := lance.description()
	assert_str(t).contains("blades sweeping together")
	assert_str(t).contains("Every other stroke is a thrust that throws harder")
	assert_str(t).contains("Every hit stuns for 0.8 s")
	assert_str(t).contains("A stunned enemy takes ×1.5")
	var whirl := _inst("whirlwind", ["critical_thinking", "flurry", "riposte"])
	assert_str(whirl.description()).contains("A critical hit gives back 20% of the cooldown")
	var battery := _inst("hellfire_battery", ["heavy_warhead", "cluster_munitions", "pressure_cooker"])
	var b := battery.description()
	assert_str(b).contains("Every blast scatters 6 bomblets")
	assert_str(b).contains("setting off their neighbours")
	assert_str(b).contains("Fires up to 80% faster")
	assert_str(b).contains("a hit vents it by half")
	assert_str(b).contains("every 4th volley fires twice")
	var spear := _inst("pike", ["stunning_thrust"])
	assert_str(spear.description()).contains("15% chance to stun for 1.0 s")
