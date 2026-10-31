extends GdUnitTestSuite

## Pass 115, lane BOSS: the King's thump 25% wider, the Gila 25% longer under the sand, the bullet heaven 50% faster, and a
## barrier round the boss and the hero for each bullet heaven (BossAttackDef `barrier`, BossPatterns' wall rules,
## Player.keep_in_fence, BossBarrier's look): the reach rule (it begins only with the hero within reach; due while he is
## out, it waits and begins as soon as he comes in), the wall never traps him (it never rises on him: at the rise he
## stands at least BARRIER_KEEP inside its face; at the radius +- 0.3 m it waits), he is held inside while it stands (the
## real Player, walking and shoved), the creatures kept on their side, the bullets stopped at it, the wall gone after (the
## bullets' end, the spent's end, or the boss gone). The numbers read from the files as shape rules.

const DT := 1.0 / 60.0

## Pass 114's numbers (before this pass): the King's stomp radius, the Gila's burrow (wind-up = sink + under + warn),
## and per pattern its range and every emitter's speed and pull speed.
const BEFORE := {
	"stomp_radius": 6.0,
	"burrow": {"windup": 4.0, "sink": 0.6, "warn": 0.4},
	"royal_dust_devil": {"range": 48.0, "speeds": [3.2, 2.4], "pulls": [7.0, 7.0]},
	"venom_monsoon": {"range": 44.0, "speeds": [2.8, 2.4], "pulls": [7.0, 7.0]},
	"hellbrand_mandala": {"range": 36.0, "speeds": [3.0, 2.0], "pulls": [7.5, 7.5]},
}
const LOOKS := {"royal_dust_devil": "tumbleweed_fence", "venom_monsoon": "cactus_fence", "hellbrand_mandala": "iron_fence"}

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


func _world(hero_at := Vector3(0, 0, 8)) -> Dictionary:
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


func _pattern(id: String, d: Dictionary) -> BossAttackDef:
	var src := {"id": id, "name": id, "kind": "pattern"}
	src.merge(d, true)
	var a: BossAttackDef = JsonContent.build("boss_attacks", src, "res://content/boss_attacks/%s/" % id)
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


## A quick pattern with a barrier: due at once, a 1 s tell, 2 s of one ring a second, 1 s spent; its wall a fixed
## `radius` m round the boss (the default thickness 0.8) unless `more` says otherwise.
func _walled(id: String, radius: float, more: Dictionary = {}) -> BossAttackDef:
	var d := {"trigger": {"first_after": 0.0, "first_at_hp": 1.0, "first_by": 0.0, "cooldown": 10.0},
		"tell": {"seconds": 1.0, "duck_db": 0.0}, "timing": {"duration": 2.0, "clear": 0.3},
		"spent": {"seconds": 1.0, "damage_taken": 1.5, "still": true}, "guard": {"share": 0.8},
		"projectile": {"look": "venom_blob", "range": 30.0, "hit_radius": 0.4},
		"emitters": [{"shape": "ring", "count": 8, "speed": 4.0, "rate": 1.0}], "hit": {"hit_frac": 0.12}, "knockback": 0.0,
		"barrier": {"look": "cactus_fence", "radius_mode": "fixed", "radius": radius}}
	d.merge(more, true)
	return _pattern(id, d)


func _run_for(em: EnemyManager, hero: Node3D, secs: float) -> void:
	var t := 0.0
	while t < secs:
		em._update_boss(DT, hero.global_position)
		t += DT


func _run_until(em: EnemyManager, hero: Node3D, cond: Callable, cap_s: float) -> float:
	var t := 0.0
	while t < cap_s:
		if cond.call():
			return t
		em._update_boss(DT, hero.global_position)
		t += DT
	return t


func _spawn(em: EnemyManager, id: String) -> int:
	var b := em.spawn(id, Vector3.ZERO)
	em.state[b] = EnemyManager.STATE_MOVE
	return b


func _started(em: EnemyManager) -> int:
	return em.patterns.started if em.patterns != null else 0


func _phase(em: EnemyManager, i: int) -> int:
	return em.patterns.phase_of(i) if em.patterns != null else -1


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- the numbers, from the files

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _entry(boss: String, name: String) -> Dictionary:
	var d := _json("res://content/bosses/%s/%s.json" % [boss, boss])
	for e in (d["boss"] as Dictionary)["attacks"]:
		if e is Dictionary and str(e.get("name", "")) == name:
			return e
	return {}


func test_the_kings_thump_reaches_a_quarter_further_and_its_warning_with_it() -> void:
	var st := _entry("tumbleweed_king", "stomp")
	assert_float(float(st["radius"])).is_equal_approx(BEFORE["stomp_radius"] * 1.25, 0.0001)
	# the warning ring, the wave and the hit all read the one radius (EnemyManager._stomp_start / _stomp_land and the
	# runner's "ring" telegraph): the loaded boss plays it
	var live: Dictionary = {}
	for e in Registry.enemy("tumbleweed_king").boss.get("attacks", []):
		if e is Dictionary and str(e.get("name", "")) == "stomp":
			live = e
	assert_float(float(live["radius"])).is_equal_approx(7.5, 0.0001)
	assert_str(str(live["telegraph"])).is_equal("ring")


func test_the_gila_stays_under_a_quarter_longer_and_her_warning_with_it() -> void:
	var b := _entry("gila_grande", "burrow")
	var old: Dictionary = BEFORE["burrow"]
	var under0 := float(old["windup"]) - float(old["sink"]) - float(old["warn"])
	var under := float(b["windup"]) - float(b["sink"]) - float(b["warn"])
	# the sink (seen) as it was; the wait under the sand and the ring before she erupts x1.25
	assert_float(float(b["sink"])).is_equal_approx(float(old["sink"]), 0.0001)
	# pass 116 (lane FIGHT re-pin): the red warning is at least 3 s of her time in the ground now (Garry), so the unmarked
	# wait shrank; the time in the ground as a whole keeps pass 115's x1.25
	assert_float(under).is_less(under0 * 1.25)
	assert_float(float(b["warn"])).is_greater_equal(3.0)
	# everything she spends in the ground (the wait and the warning) x1.25
	assert_float(float(b["windup"]) - float(b["sink"])).is_equal_approx((float(old["windup"]) - float(old["sink"])) * 1.25, 0.0001)


func test_the_bullet_heaven_flies_half_as_fast_again_and_each_has_its_barrier() -> void:
	for id: String in LOOKS.keys():
		var a: BossAttackDef = Registry.boss_attack(id)
		assert_object(a).is_not_null()
		var old: Dictionary = BEFORE[id]
		# the range as it was (the barrier stands just inside it)
		assert_float(a.num("projectile", "range")).is_equal_approx(float(old["range"]), 0.0001)
		var ems := a.emitters_full()
		assert_int(ems.size()).is_equal((old["speeds"] as Array).size())
		for k in range(ems.size()):
			assert_float(float(ems[k]["speed"])).is_equal_approx(float(old["speeds"][k]) * 1.5, 0.0001)
			# the Brander's finale pulls them home 50% faster too (the others pull nothing: the default)
			if float(ems[k]["finale_pull"]) > 0.0:
				assert_float(float(ems[k]["pull_speed"])).is_equal_approx(float(old["pulls"][k]) * 1.5, 0.0001)
		assert_bool(a.barrier_on()).is_true()
		assert_str(a.text("barrier", "look")).is_equal(LOOKS[id])
		assert_bool(BossAttackDef.BARRIER_LOOKS.has(a.text("barrier", "look"))).is_true()
		assert_bool(BarrierMeshes.parts(a.text("barrier", "look")).size() >= 3).is_true()
		# the lead (pass 115): the wall stands where the phone shows it, a fixed 14 m round the boss (at the bullets' 35-47 m
		# it was off screen in every normal fight); well inside the range, the hero held inside it, the reach inside that
		assert_str(a.text("barrier", "radius_mode")).is_equal("fixed")
		assert_bool(a.barrier_radius() < a.num("projectile", "range")).is_true()
		assert_bool(a.barrier_hero_limit() < a.barrier_radius()).is_true()
		assert_float(a.barrier_reach()).is_equal_approx(a.barrier_hero_limit() - BossAttackDef.BARRIER_KEEP, 0.0001)
		assert_bool(a.barrier_reach() <= a.num("projectile", "range")).is_true()
		assert_bool(a.barrier_blocks_hero() and a.barrier_blocks_creatures() and a.barrier_stops_bullets()).is_true()
		assert_bool(a.barrier_holds_spent()).is_false()
		# the bullets vanish at its inner face, inside the range: every spot inside it can be hit
		assert_float(a.bullet_reach()).is_equal_approx(a.barrier_radius() - a.barrier_half(), 0.0001)
		# rising within the tell
		assert_bool(a.num("barrier", "rise_s") + a.num("barrier", "spread_s") <= a.tell_seconds()).is_true()
		# its words say so
		assert_str(a.doc).contains("kept inside it")


# ---------------------------------------------------------------- the reach rule

func test_without_a_barrier_there_is_no_reach_rule() -> void:
	var a := _pattern("t115_plain", {"projectile": {"range": 10.0}})
	assert_bool(a.barrier_on()).is_false()
	assert_float(a.barrier_reach()).is_equal(INF)
	assert_float(a.bullet_reach()).is_equal_approx(10.0, 0.0001)
	# a look that is not one of the looks is none
	var b := _pattern("t115_odd", {"barrier": {"look": "moat"}})
	assert_bool(b.barrier_on()).is_false()


func test_the_reach_rule_waits_for_the_hero_and_begins_as_soon_as_he_comes_in() -> void:
	var w := _world(Vector3(0, 0, 14))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _walled("t115_reach", 12.0)
	# fixed 12 m: the wall's middle at 12, the hero held within 12 - 0.4 - 0.45 = 11.15, the reach 10.65
	assert_float(p.barrier_radius()).is_equal_approx(12.0, 0.0001)
	assert_float(p.barrier_hero_limit()).is_equal_approx(11.15, 0.0001)
	assert_float(p.barrier_reach()).is_equal_approx(10.65, 0.0001)
	var d := _boss_def("t115_reacher", [{"name": p.id}])
	var b := _spawn(em, d.id)
	# due at once, but he is 14 m off: it waits
	_run_for(em, hero, 1.5)
	assert_int(em.patterns.started).is_equal(0)
	assert_bool(em.patterns.reach_waits > 0).is_true()
	assert_str(str(em.patterns.schedule_of(b).get("waiting", ""))).is_equal(p.id)
	# the hero at the wall's middle +- 0.3 m (where a rising wall would catch him): it still waits
	for r: float in [12.3, 11.7, 12.0, 11.15, 10.7]:
		hero.global_position = Vector3(0, 0, r)
		_run_for(em, hero, 0.25)
		assert_int(em.patterns.started).override_failure_message("began with the hero at %.2f m" % r).is_equal(0)
	# he steps in: it begins on that tick (its clock was not reset, nothing rolled again)
	hero.global_position = Vector3(0, 0, 10.6)
	em._update_boss(DT, hero.global_position)
	assert_int(em.patterns.started).is_equal(1)
	assert_bool(em.patterns.wall_up(b)).is_true()


# ---------------------------------------------------------------- the wall never traps him, it holds him, it goes

func test_the_wall_never_rises_on_the_hero_and_holds_him_inside_then_lets_him_go() -> void:
	var w := _world(Vector3(0, 0, 9))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _walled("t115_hold", 12.0)
	var d := _boss_def("t115_holder", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _started(em) > 0, 2.0)
	assert_int(em.patterns.started).is_equal(1)
	# the hold on the hero: round where the boss stood, at the limit; he stands at least BARRIER_KEEP inside it
	assert_float(float(hero.fence_r)).is_equal_approx(p.barrier_hero_limit(), 0.0001)
	assert_vector(hero.fence_c).is_equal(em.pos[b])
	var lw: Dictionary = em.patterns.last_wall
	assert_bool(_flat(lw["hero_at"], lw["c"]) <= float(lw["hero_limit"]) - BossAttackDef.BARRIER_KEEP + 0.0001).is_true()
	assert_float(float(lw["r"])).is_equal_approx(12.0, 0.0001)
	# it stands through the tell and the bullets ...
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.FIRE, 3.0)
	assert_bool(em.patterns.wall_up(b)).is_true()
	assert_float(float(hero.fence_r)).is_greater(0.0)
	# ... and falls apart as the bullets end (hold "bullets"): he is let go
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.SPENT, 5.0)
	assert_bool(em.patterns.wall_up(b)).is_false()
	assert_float(float(hero.fence_r)).is_equal(0.0)
	assert_dict(em.patterns.standing_wall()).is_empty()


func test_hold_spent_keeps_it_up_through_his_dazed_seconds() -> void:
	var w := _world(Vector3(0, 0, 9))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _walled("t115_spent", 12.0, {"barrier": {"look": "iron_fence", "radius_mode": "fixed", "radius": 12.0, "hold": "spent"}})
	var d := _boss_def("t115_spender", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.SPENT, 6.0)
	assert_bool(em.patterns.wall_up(b)).is_true()
	assert_float(float(hero.fence_r)).is_greater(0.0)
	_run_until(em, hero, func() -> bool: return not em.patterns.running(b), 4.0)
	assert_bool(em.patterns.running(b)).is_false()
	assert_float(float(hero.fence_r)).is_equal(0.0)


func test_the_boss_gone_lets_the_hero_go() -> void:
	var w := _world(Vector3(0, 0, 9))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _walled("t115_cut", 12.0)
	var d := _boss_def("t115_cutter", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _started(em) > 0, 2.0)
	assert_float(float(hero.fence_r)).is_greater(0.0)
	em.alive[b] = 0
	_run_for(em, hero, 0.1)
	assert_float(float(hero.fence_r)).is_equal(0.0)
	assert_int(em.patterns.cancelled).is_equal(1)


func test_the_real_hero_walks_and_is_shoved_but_never_past_the_wall() -> void:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Run.character)
	p.global_position = Vector3(0, 0, 0)
	p.fence_c = Vector3(1, 0, -2)
	p.fence_r = 4.0
	# inside: untouched
	p.global_position = Vector3(2, 0, -1)
	p.keep_in_fence()
	assert_vector(p.global_position).is_equal_approx(Vector3(2, 0, -1), Vector3(0.0001, 0.0001, 0.0001))
	# put past it (a teleport, a throw): back on the circle, the way he was, his outward speed and shove dropped
	p.global_position = Vector3(1, 0.5, 7)
	p.velocity = Vector3(0, 0, 6)
	p._kb = Vector3(3, 0, 8)
	p.keep_in_fence()
	assert_float(_flat(p.global_position, p.fence_c)).is_equal_approx(4.0, 0.0001)
	assert_float(p.global_position.y).is_equal_approx(0.5, 0.0001)
	assert_float(p.velocity.z).is_less_equal(0.0001)
	assert_float(p._kb.z).is_less_equal(0.0001)
	assert_float(p._kb.x).is_equal_approx(3.0, 0.0001)
	# walking straight out at full stick, then shoved out hard: every step he stays inside
	p.global_position = Vector3(1, 0, 0)
	p.velocity = Vector3.ZERO
	p._kb = Vector3.ZERO
	# (the stick read against a fixed camera: up the stick = +z, straight at the wall)
	p.camera_yaw_fn = func() -> float: return 0.0
	p.input.wants_move = true
	p.input.stick_dir = Vector2(0, 1)
	var worst := 0.0
	for k in range(180):
		if k == 90:
			p._kb = Vector3(0, 0, 25)
		p._physics_process(DT)
		worst = maxf(worst, _flat(p.global_position, p.fence_c))
	assert_float(worst).is_less_equal(4.0 + 0.0001)
	assert_float(_flat(p.global_position, p.fence_c)).is_greater(3.9)
	# let go: he walks on out
	p.fence_r = 0.0
	for k in range(60):
		p._physics_process(DT)
	assert_float(_flat(p.global_position, p.fence_c)).is_greater(4.5)
	p.input.wants_move = false


func test_the_creatures_stay_on_their_side_while_it_stands() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _walled("t115_crowd", 12.0)
	var d := _boss_def("t115_herder", [{"name": p.id}])
	var b := _spawn(em, d.id)
	var inner := em.spawn("goblin", Vector3(8, 0, 0))
	var outer := em.spawn("goblin", Vector3(-16, 0, 0))
	em.state[inner] = EnemyManager.STATE_MOVE
	em.state[outer] = EnemyManager.STATE_MOVE
	_run_until(em, hero, func() -> bool: return _started(em) > 0, 2.0)
	assert_bool(em.patterns.wall_up(b)).is_true()
	var c: Vector3 = em.patterns.last_wall["c"]
	var h := p.barrier_half()
	# shoved across every tick (the one inside out past the wall, the one outside in past it): held on its side
	for k in range(30):
		em.pos[inner] = Vector3(c.x + 13.5, 0, c.z)
		em.pos[outer] = Vector3(c.x - 10.0, 0, c.z)
		em._update_boss(DT, hero.global_position)
		assert_float(_flat(em.pos[inner], c)).is_less_equal(12.0 - h - em.radius[inner] + 0.0001)
		assert_float(_flat(em.pos[outer], c)).is_greater_equal(12.0 + h + em.radius[outer] - 0.0001)
	assert_bool(em.patterns.wall_holds >= 60).is_true()
	# the boss in the middle is never moved by it
	assert_float(_flat(em.pos[b], c)).is_less(0.01)
	# once it is down they cross freely
	_run_until(em, hero, func() -> bool: return not em.patterns.wall_up(b), 6.0)
	em.pos[outer] = Vector3(c.x - 10.0, 0, c.z)
	em._update_boss(DT, hero.global_position)
	assert_float(_flat(em.pos[outer], c)).is_equal_approx(10.0, 0.0001)


func test_creatures_pass_lets_them_through() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _walled("t115_pass", 12.0, {"barrier": {"look": "tumbleweed_fence", "radius_mode": "fixed", "radius": 12.0, "creatures": "pass"}})
	var d := _boss_def("t115_passer", [{"name": p.id}])
	var b := _spawn(em, d.id)
	var g := em.spawn("goblin", Vector3(-16, 0, 0))
	em.state[g] = EnemyManager.STATE_MOVE
	_run_until(em, hero, func() -> bool: return _started(em) > 0, 2.0)
	var c: Vector3 = em.patterns.last_wall["c"]
	em.pos[g] = Vector3(c.x - 9.0, 0, c.z)
	em._update_boss(DT, hero.global_position)
	assert_float(_flat(em.pos[g], c)).is_equal_approx(9.0, 0.0001)
	assert_bool(em.patterns.wall_up(b)).is_true()


func test_the_bullets_stop_at_the_wall() -> void:
	var w := _world(Vector3(0, 0, 4))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	# a ring every second at 6 m/s, the range 30 m, the wall at 8 m: none flies past its inner face
	var p := _walled("t115_stop", 8.0, {"emitters": [{"shape": "ring", "count": 24, "speed": 6.0, "rate": 2.0}], "timing": {"duration": 4.0, "clear": 0.3}})
	assert_float(p.bullet_reach()).is_equal_approx(8.0 - 0.4, 0.0001)
	var d := _boss_def("t115_stopper", [{"name": p.id}])
	var b := _spawn(em, d.id)
	hero.global_position = Vector3(0, 0, 50)
	hero.dead = true
	# (he stands far off so nothing hits him: the begin is forced, the reach rule is the other test's)
	em.patterns = BossPatterns.new(em)
	em.patterns.begin(b, p, {"name": p.id}, Vector3(0, 0, 4))
	var c: Vector3 = em.pos[b]
	var far := 0.0
	var t := 0.0
	while em.patterns.phase_of(b) != BossPatterns.SPENT and t < 8.0:
		em._update_boss(DT, hero.global_position)
		var run: Dictionary = em.patterns.runs[b]
		var bb: PackedFloat32Array = run["b"]
		for k in range(int(run["n"])):
			far = maxf(far, Vector2(bb[k * BossPatterns.B] - c.x, bb[k * BossPatterns.B + 1] - c.z).length())
		t += DT
	# a bullet stops within one tick's flight past the face (it is caught the tick it crosses)
	assert_float(far).is_less_equal(8.0 - 0.4 + 6.0 * DT + 0.001)
	assert_bool(em.patterns.wall_stops > 0).is_true()
	# with bullets "pass" they fly to the range
	var q := _walled("t115_through", 8.0, {"barrier": {"look": "iron_fence", "radius_mode": "fixed", "radius": 8.0, "bullets": "pass"}})
	assert_float(q.bullet_reach()).is_equal_approx(30.0, 0.0001)


func test_the_wall_never_falls_below_its_smallest_ring_and_range_mode_follows_the_range() -> void:
	var a := _pattern("t115_small", {"projectile": {"range": 2.0}, "barrier": {"look": "iron_fence"}})
	assert_float(a.barrier_radius()).is_equal_approx(BossAttackDef.BARRIER_MIN_R + 0.4, 0.0001)
	var b2 := _pattern("t115_rng", {"projectile": {"range": 20.0}, "barrier": {"look": "iron_fence", "inset": 2.5}})
	assert_float(b2.barrier_radius()).is_equal_approx(17.5, 0.0001)
	assert_float(b2.barrier_reach()).is_equal_approx(17.5 - 0.4 - 0.45 - 0.5, 0.0001)
	# the keep_within / keep_beyond helpers the crowd's hold uses
	var c := Vector3(1, 0, 1)
	assert_vector(BossAttackDef.keep_within(Vector3(11, 3, 1), c, 4.0)).is_equal_approx(Vector3(5, 3, 1), Vector3(0.0001, 0.0001, 0.0001))
	assert_vector(BossAttackDef.keep_beyond(Vector3(2, 3, 1), c, 4.0)).is_equal_approx(Vector3(5, 3, 1), Vector3(0.0001, 0.0001, 0.0001))
	assert_vector(BossAttackDef.keep_beyond(c, c, 4.0)).is_equal_approx(Vector3(5, 0, 1), Vector3(0.0001, 0.0001, 0.0001))


## The Level Editor's mirror (tools/level_editor/boss_model.js barrierRadius, barrierHeroLimit, barrierReach,
## bulletReach, simulate; selftest_BOSS115.py runs the same cases under Node against these numbers).
const MIRROR := [
	[{"projectile": {"range": 48.0}, "barrier": {"look": "tumbleweed_fence"}}, [47.0, 46.15, 45.65, 46.6]],
	[{"projectile": {"range": 20.0}, "barrier": {"look": "cactus_fence", "radius_mode": "fixed", "radius": 14.0, "thickness": 1.2}}, [14.0, 12.95, 12.45, 13.4]],
	[{"projectile": {"range": 10.0}, "barrier": {"look": "iron_fence", "radius_mode": "fixed", "radius": 16.0, "bullets": "pass"}}, [16.0, 15.15, 10.0, 10.0]],
	[{"projectile": {"range": 30.0}, "barrier": {"look": "none"}}, [29.0, 28.15, INF, 30.0]],
]


func test_the_level_editors_mirror_numbers() -> void:
	for k in range(MIRROR.size()):
		var a := _pattern("t115_mirror_%d" % k, MIRROR[k][0])
		var want: Array = MIRROR[k][1]
		assert_float(a.barrier_radius()).is_equal_approx(float(want[0]), 0.0001)
		assert_float(a.barrier_hero_limit()).is_equal_approx(float(want[1]), 0.0001)
		if float(want[2]) == INF:
			assert_float(a.barrier_reach()).is_equal(INF)
		else:
			assert_float(a.barrier_reach()).is_equal_approx(float(want[2]), 0.0001)
		assert_float(a.bullet_reach()).is_equal_approx(float(want[3]), 0.0001)


# ---------------------------------------------------------------- the look

func test_every_look_builds_its_pieces_round_the_ring() -> void:
	var w := _world(Vector3(0, 0, 9))
	for lk: String in ["tumbleweed_fence", "cactus_fence", "iron_fence"]:
		var parts := BarrierMeshes.parts(lk)
		assert_bool(parts.size() >= 3).is_true()
		var glows := 0
		for piece: String in parts.keys():
			var m: ArrayMesh = parts[piece]
			assert_int(m.get_surface_count()).is_equal(1)
			assert_bool(m.surface_get_array_len(0) >= 12).override_failure_message("%s %s" % [lk, piece]).is_true()
			if BarrierMeshes.GLOW_PARTS.has(piece):
				glows += 1
		assert_bool(glows >= 1).is_true()
		var a := _pattern("t115_look_" + lk, {"barrier": {"look": lk, "radius_mode": "fixed", "radius": 10.0}})
		var node := BossBarrier.new()
		(w["g"] as Node).add_child(node)
		node.setup(w["g"], a, Vector3.ZERO, 10.0, Vector3(0, 0, 9))
		var seg: float = float(BarrierMeshes.SEG[lk])
		assert_int(node.stretches).is_equal(int(ceil(TAU * 10.0 / seg)))
		assert_bool(node.pieces > node.stretches).is_true()
		assert_bool(node.chunks >= 2).is_true()
		assert_bool(node.is_falling()).is_false()
		node.fall()
		assert_bool(node.is_falling()).is_true()
		node.queue_free()
