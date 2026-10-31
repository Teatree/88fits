## Pass 118 (the lead). Garry: "When I am in the barrier with the Boss all other enemies outside the barrier should stop and
## look at me. They do not attack. Only ones that are inside the barrier with the hero actually attack." (EnemyManager
## onlook, BossPatterns._wall_onlookers); "Chests have a bug where one of the rays of shine shines through the middle of
## them" (Chest: the beam and the sunburst behind the chest, the lock's glint a soft sparkle).
extends GdUnitTestSuite

const DT := 1.0 / 60.0

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 150.0
var hits := 0
var fence_c := Vector3.ZERO
var fence_r := 0.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3, _c := true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h := true) -> void:
	pass
func special_push(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h := true) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(_d: Vector3) -> Vector3:
	return global_position
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

var _added: Array = []
var _attacks_added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	for id: String in _attacks_added:
		Registry.boss_attacks.erase(id)
	_attacks_added.clear()
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at: Vector3) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
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
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


## A pattern with a barrier `radius` m round the boss: due at once, a 1 s tell, 2 s of one slow ring a second, 1 s spent.
func _walled(id: String, radius: float) -> BossAttackDef:
	var d := {"id": id, "name": id, "kind": "pattern",
		"trigger": {"first_after": 0.0, "first_at_hp": 1.0, "first_by": 0.0, "cooldown": 30.0},
		"tell": {"seconds": 1.0, "duck_db": 0.0}, "timing": {"duration": 2.0, "clear": 0.3},
		"spent": {"seconds": 1.0, "damage_taken": 1.5, "still": true}, "guard": {"share": 0.8},
		"projectile": {"look": "venom_blob", "range": 30.0, "hit_radius": 0.4},
		"emitters": [{"shape": "ring", "count": 8, "speed": 4.0, "rate": 1.0}], "hit": {"hit_frac": 0.12}, "knockback": 0.0,
		"barrier": {"look": "cactus_fence", "radius_mode": "fixed", "radius": radius}}
	var a: BossAttackDef = JsonContent.build("boss_attacks", d, "res://content/boss_attacks/%s/" % id)
	a.id = id
	Registry.boss_attacks[id] = a
	_attacks_added.append(id)
	return a


func _boss_def(id: String, attacks: Array) -> EnemyDef:
	var d: EnemyDef = Registry.enemy("tumbleweed_king").duplicate()
	d.id = id
	d.variance = {}
	d.boss = {"attacks": attacks, "cooldown_between": 2.0, "hp_mult_per_stage": 2.0}
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _settled(em: EnemyManager, id: String, at: Vector3) -> int:
	var i := em.spawn(id, at)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	return i


func _tick(em: EnemyManager, secs: float) -> void:
	var t := 0.0
	while t < secs:
		em._physics_process(DT)
		t += DT


func test_outside_the_barrier_the_crowd_stands_and_watches_the_hero() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var p := _walled("t118_watch", 12.0)
	var d := _boss_def("t118_watcher_boss", [{"name": p.id}])
	var b := _settled(em, d.id, Vector3.ZERO)
	var inner := _settled(em, "goblin", Vector3(5, 0, -3))
	var outer := _settled(em, "goblin", Vector3(-20, 0, 0))
	var t := 0.0
	while t < 2.0 and not (em.patterns != null and em.patterns.wall_up(b)):
		em._physics_process(DT)
		t += DT
	assert_bool(em.patterns.wall_up(b)).is_true()
	_tick(em, 0.1)
	assert_bool(em.is_onlooker(outer)).override_failure_message("the one outside watches").is_true()
	assert_bool(em.is_onlooker(inner)).override_failure_message("the one inside fights").is_false()
	assert_bool(em.is_onlooker(b)).override_failure_message("never the boss").is_false()
	# it stands where it is, turned to the hero (east of it: the picture unmirrored), its idle playing
	var at := em.pos[outer]
	var anim0 := em.anim_t[outer]
	var in_at := em.pos[inner]
	_tick(em, 0.6)
	assert_float(em.pos[outer].distance_to(at)).is_less(0.01)
	assert_int(em.flip[outer]).is_equal(0)
	assert_float(em.anim_t[outer]).is_greater(anim0)
	assert_float(em.pos[inner].distance_to(in_at)).override_failure_message("the one inside walks at him").is_greater(0.2)
	# a wind-up it starts is dropped at once
	em.state[outer] = EnemyManager.STATE_WINDUP
	em._physics_process(DT)
	assert_int(em.state[outer]).is_equal(EnemyManager.STATE_MOVE)


func test_the_crowd_moves_again_once_the_barrier_falls() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var p := _walled("t118_fall", 12.0)
	var d := _boss_def("t118_fall_boss", [{"name": p.id}])
	var b := _settled(em, d.id, Vector3.ZERO)
	var outer := _settled(em, "goblin", Vector3(-20, 0, 0))
	var t := 0.0
	while t < 2.0 and not (em.patterns != null and em.patterns.wall_up(b)):
		em._physics_process(DT)
		t += DT
	_tick(em, 0.1)
	assert_bool(em.is_onlooker(outer)).is_true()
	# the pattern runs out (2 s of bullets, 1 s spent): the barrier falls and the flags with it
	t = 0.0
	while t < 8.0 and em.patterns.wall_up(b):
		em._physics_process(DT)
		t += DT
	assert_bool(em.patterns.wall_up(b)).is_false()
	_tick(em, 0.1)
	assert_bool(em.is_onlooker(outer)).is_false()
	assert_int(em.onlookers).is_equal(0)
	var at := em.pos[outer]
	_tick(em, 0.6)
	assert_float(em.pos[outer].distance_to(at)).is_greater(0.2)


func test_flags_no_barrier_refreshes_go_by_themselves() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var g := _settled(em, "goblin", Vector3(-8, 0, 0))
	em.onlook[g] = 1
	em.onlookers = 1
	em.onlook_tick = em._ticks
	assert_bool(em.is_onlooker(g)).is_true()
	_tick(em, 0.1)
	assert_bool(em.is_onlooker(g)).is_false()
	assert_int(em.onlookers).is_equal(0)


func _chest(boss: bool) -> Chest:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var c := Chest.new()
	c.boss = boss
	host.add_child(c)
	return c


func _quads(c: Chest, mode: int) -> Array:
	var out: Array = []
	for n in c.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
			var m: ShaderMaterial = (n as MeshInstance3D).material_override
			if m.shader == Chest.SHINE and int(m.get_shader_parameter("mode")) == mode:
				out.append(n)
	return out


func test_a_chests_light_stands_behind_it_and_its_glint_is_a_soft_sparkle() -> void:
	for boss: bool in [false, true]:
		var c := _chest(boss)
		var ks := 1.35 if boss else 1.0
		var beam: Array = _quads(c, 1)
		assert_int(beam.size()).is_equal(1)
		assert_float(float((beam[0].material_override as ShaderMaterial).get_shader_parameter("beam_back"))).is_equal_approx(Chest.BEAM_BACK * ks, 0.0001)
		var sun: Array = _quads(c, 0)
		assert_int(sun.size()).is_equal(1)
		assert_float(float((sun[0].material_override as ShaderMaterial).get_shader_parameter("push_back"))).is_equal_approx(Chest.SUN_BACK * ks, 0.0001)
		# the glint: one more mode-3 sparkle beside the six that rise; no white bars (boxes) anywhere on the chest
		assert_int(_quads(c, 3).size()).is_equal(7)
		for n in c.find_children("*", "MeshInstance3D", true, false):
			if (n as MeshInstance3D).mesh is BoxMesh:
				assert_float(((n as MeshInstance3D).mesh as BoxMesh).size.y).override_failure_message("a bar on the chest").is_less(0.1)
