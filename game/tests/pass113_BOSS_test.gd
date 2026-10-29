extends GdUnitTestSuite

## Pass 113, lane BOSS: the bosses' bullet-heaven patterns (content/boss_attacks kind "pattern", BossAttackDef's emitter
## maths, BossPatterns on EnemyManager): the trigger (not before first_after, at first_at_hp, by first_by, then every
## cooldown from the end), the guard and spent multipliers on damage(), nothing else of his starting meanwhile (no attack,
## no summon), the boss-fight window held, the cycle resuming, every emitter's geometry (counts, the spin reversal, the
## turn, the sweep, the pulse, the ring's gap, the rose, the wall, the finale pull), each bullet hitting once for hit_frac
## of the hero's max HP, and the three contents loading and named by their bosses.

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
var rings: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(a, b, c, _d, _e = true) -> void:
	rings.append({"at": a, "r": float(b), "dur": float(c)})
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
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
var amounts: Array = []
var infos: Array = []
func take_damage(a: float, _f: Vector3, i: Dictionary = {}) -> void:
	hits += 1
	amounts.append(a)
	infos.append(i)
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

const FAKE_DIR := """extends RefCounted
var game = null
var timeline = null
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


## A fake game round a fake hero at `hero_at`, with the real crowd.
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


## A pattern made in code (gone after the test): the game's defaults with `d` over them.
func _pattern(id: String, d: Dictionary) -> BossAttackDef:
	var src := {"id": id, "name": id, "kind": "pattern"}
	src.merge(d, true)
	var a: BossAttackDef = JsonContent.build("boss_attacks", src, "res://content/boss_attacks/%s/" % id)
	a.id = id
	Registry.boss_attacks[id] = a
	_attacks_added.append(id)
	return a


## A test boss (from the King) whose script is `attacks` (gone after the test).
func _boss_def(id: String, attacks: Array) -> EnemyDef:
	var d: EnemyDef = Registry.enemy("tumbleweed_king").duplicate()
	d.id = id
	d.variance = {}
	d.boss = {"attacks": attacks, "cooldown_between": 2.0, "hp_mult_per_stage": 2.0}
	Registry.enemies[id] = d
	_added.append(id)
	return d


## A quick pattern: no first_after, due at once, a 1 s tell, 2 s of one ring a second straight at nothing, 1 s spent.
func _quick(id: String, more: Dictionary = {}) -> BossAttackDef:
	var d := {"trigger": {"first_after": 0.0, "first_at_hp": 1.0, "first_by": 0.0, "cooldown": 10.0},
		"tell": {"seconds": 1.0, "duck_db": 0.0}, "timing": {"duration": 2.0, "clear": 0.3},
		"spent": {"seconds": 1.0, "damage_taken": 1.5, "still": true}, "guard": {"share": 0.8},
		"projectile": {"look": "venom_blob", "range": 12.0, "hit_radius": 0.4},
		"emitters": [{"shape": "ring", "count": 8, "speed": 4.0, "rate": 1.0}], "hit": {"hit_frac": 0.12}, "knockback": 0.0}
	d.merge(more, true)
	return _pattern(id, d)


## The world's tick for the attack scripts, `secs` long (what EnemyManager's tick runs for them).
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


## Creature `id` at the middle, out of its spawn pop (the crowd's tick would end STATE_SPAWN in 0.35 s).
func _spawn(em: EnemyManager, id: String) -> int:
	var b := em.spawn(id, Vector3.ZERO)
	em.state[b] = EnemyManager.STATE_MOVE
	return b


func _running(em: EnemyManager, i: int) -> bool:
	return em.patterns != null and em.patterns.running(i)


func _phase(em: EnemyManager, i: int) -> int:
	return em.patterns.phase_of(i) if em.patterns != null else -1


func _started(em: EnemyManager) -> int:
	return em.patterns.started if em.patterns != null else 0


# ---------------------------------------------------------------- the content

func test_the_three_patterns_load_and_their_bosses_name_them() -> void:
	for pair: Array in [["tumbleweed_king", "royal_dust_devil"], ["gila_grande", "venom_monsoon"], ["brander", "hellbrand_mandala"]]:
		var a: BossAttackDef = Registry.boss_attack(pair[1])
		assert_object(a).is_not_null()
		assert_str(a.attack_kind).is_equal("pattern")
		assert_bool(a.doc.length() > 40).is_true()
		assert_bool(a.pattern_duration() >= 5.0).is_true()
		assert_float(a.num("tell", "seconds")).is_equal_approx(2.0, 0.001)
		assert_bool(BossAttackDef.LOOKS.has(a.text("projectile", "look")) and BossAttackFx.is_billboard(a.text("projectile", "look"))).is_true()
		assert_bool(a.emitters_full().size() >= 1).is_true()
		for e: Dictionary in a.emitters_full():
			assert_bool(BossAttackDef.EMITTER_SHAPES.has(str(e["shape"])) and BossAttackDef.EMITTER_AIMS.has(str(e["aim"]))).is_true()
		var boss: EnemyDef = Registry.enemy(pair[0])
		var names: Array = []
		for e in boss.boss.get("attacks", []):
			names.append(str((e as Dictionary).get("name", "")))
		assert_array(names).contains([pair[1]])
		# never in his attack cycle (its own trigger plays it)
		var em := EnemyManager.new()
		var resolved: Array = em.custom_resolved(boss, boss.boss.get("attacks", []))
		for r: Dictionary in resolved:
			assert_str(str(r.get("custom", r.get("name", "")))).is_not_equal(pair[1])
		assert_int(resolved.size()).is_equal(names.size() - 1)
		em.free()
		# dangerous by density: a peak of bullets in the air (no hero), and Garry's rules spelt out in the file
		var sim := a.simulate()
		assert_bool(int(sim["peak"]) >= 40 and int(sim["peak"]) <= 400).is_true()
		assert_float(a.num("trigger", "first_after")).is_equal_approx(15.0, 0.001)
		assert_float(a.num("trigger", "cooldown")).is_equal_approx(45.0, 0.001)
		assert_float(a.guard_mult()).is_equal_approx(0.2, 0.0001)
		assert_float(a.spent_mult()).is_equal_approx(1.5, 0.0001)
		assert_float(a.num("hit", "hit_frac")).is_equal_approx(0.12, 0.0001)
	# the Brander's finale: his emitters pull home in the last second
	var bm: BossAttackDef = Registry.boss_attack("hellbrand_mandala")
	assert_float(float(bm.emitters_full()[0]["finale_pull"])).is_equal_approx(1.0, 0.001)
	assert_float(bm.num("shell", "sigil_radius")).is_greater(4.0)


# ---------------------------------------------------------------- the trigger

func test_the_trigger_not_before_first_after_then_at_the_hp_or_by_first_by_then_every_cooldown() -> void:
	var a := _pattern("t113_trig", {})
	# not before 15 s, however low he is
	assert_bool(a.pattern_due(14.9, 0.1, 0, -1e9)).is_false()
	# the first: under 60% HP, or 45 s in at the latest
	assert_bool(a.pattern_due(15.0, 0.6, 0, -1e9)).is_true()
	assert_bool(a.pattern_due(20.0, 0.61, 0, -1e9)).is_false()
	assert_bool(a.pattern_due(44.9, 0.99, 0, -1e9)).is_false()
	assert_bool(a.pattern_due(45.0, 0.99, 0, -1e9)).is_true()
	# then 45 s after the last one ended, whatever his HP
	assert_bool(a.pattern_due(104.9, 0.1, 1, 60.0)).is_false()
	assert_bool(a.pattern_due(105.0, 0.9, 1, 60.0)).is_true()


func test_it_starts_only_between_attacks_and_holds_everything_else_of_his() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _pattern("t113_hold", {"trigger": {"first_after": 3.0, "first_at_hp": 0.6, "first_by": 1000.0, "cooldown": 20.0},
		"tell": {"seconds": 1.0, "duck_db": 0.0}, "timing": {"duration": 2.0, "clear": 0.3}, "spent": {"seconds": 1.0},
		"emitters": [{"shape": "ring", "count": 6, "speed": 3.0, "rate": 1.0}], "projectile": {"look": "brand_fireball"}})
	var d := _boss_def("t113_holder", [{"name": "slam", "windup": 1.5, "radius": 3.0, "damage": 10, "telegraph": "ring"},
		{"name": "spawn_ring", "windup": 0.5, "enemy": "goblin", "count": 4, "telegraph": "none"}, {"name": p.id}])
	var b := _spawn(em, d.id)
	assert_int(em.boss_index).is_equal(b)
	# full HP: past first_after nothing comes (first_by is far)
	_run_for(em, hero, 4.0)
	assert_int(em.patterns.started).is_equal(0)
	# low HP while he winds up his slam: it waits for the slam to be over
	em.state[b] = EnemyManager.STATE_MOVE
	em.atk_i[b] = 0
	em.atk_t[b] = 0.0
	em._update_attacks(b, DT, hero.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	em.hp[b] = em.max_hp[b] * 0.5
	_run_for(em, hero, 0.5)
	assert_int(em.patterns.started).is_equal(0)
	var waited := _run_until(em, hero, func() -> bool: return _started(em) > 0, 5.0)
	assert_int(em.patterns.started).is_equal(1)
	assert_bool(waited > 0.5).is_true()
	assert_int(em.patterns.phase_of(b)).is_equal(BossPatterns.TELL)
	assert_bool(em.pattern_holds()).is_true()
	# nothing else of his while it runs (tell, bullets, spent): no attack, no summon, the cycle's index unmoved
	var alive0 := em.alive_count()
	var atk0 := em.atk_i[b]
	var rings0: int = (w["g"].rings as Array).size()
	var t := 0.0
	while em.patterns.running(b) and t < 8.0:
		em._update_boss(DT, hero.global_position)
		if em.patterns.running(b):
			assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
			assert_bool(em.vel[b].length() < 0.0001).is_true()
		t += DT
	# the tell, the bullets and spent on the creatures' clock (x 1/pace, as every wind-up)
	assert_float(t).is_equal_approx((1.0 + 2.0 + 1.0) / em.pace, 0.1)
	assert_int(em.alive_count()).is_equal(alive0)
	assert_int(em.atk_i[b]).is_equal(atk0)
	assert_int((w["g"].rings as Array).size()).is_equal(rings0)
	assert_bool(em.pattern_holds()).is_false()
	# after it: his cycle resumes after his cooldown_between, and the next pattern is the cooldown away
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.atk_t[b]).is_equal_approx(2.0, 0.05)
	var s := em.patterns.schedule_of(b)
	assert_int(int(s["runs"])).is_equal(1)
	var ended := float(s["last_end"])
	var next := _run_until(em, hero, func() -> bool: return em.state[b] == EnemyManager.STATE_ATTACK, 3.0)
	assert_float(next).is_equal_approx(2.0, 0.1)
	assert_int(em.patterns.started).is_equal(1)
	# the second comes no sooner than 20 s after the first ended, and then it comes
	_run_until(em, hero, func() -> bool: return _started(em) > 1, 40.0)
	assert_int(em.patterns.started).is_equal(2)
	var s2 := em.patterns.schedule_of(b)
	assert_bool(float(s2["fight"]) - ended >= 20.0 - 0.05).is_true()


func test_the_boss_fight_window_waits_while_it_runs() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _quick("t113_win")
	var d := _boss_def("t113_winner", [{"name": p.id}])
	var b := _spawn(em, d.id)
	var dir: RefCounted = _script(FAKE_DIR).new()
	dir.game = w["g"]
	var bw := BossFightWindow.new()
	bw.dir = dir
	bw.active = true
	bw.length = 120.0
	assert_bool(bw.held()).is_false()
	_run_until(em, hero, func() -> bool: return _running(em, b), 1.0)
	assert_bool(bw.held()).is_true()
	var c0 := bw.clock
	bw.tick(1.0)
	assert_float(bw.clock).is_equal(c0)
	_run_until(em, hero, func() -> bool: return not _running(em, b), 6.0)
	assert_bool(bw.held()).is_false()
	bw.tick(1.0)
	assert_float(bw.clock).is_equal_approx(c0 + 1.0, 0.0001)


# ---------------------------------------------------------------- the guard and the payoff

func test_guarded_hits_take_a_fifth_and_spent_hits_half_again() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _quick("t113_guard")
	var d := _boss_def("t113_guarded", [{"name": p.id}])
	var b := _spawn(em, d.id)
	em.max_hp[b] = 100000.0
	em.hp[b] = 100000.0
	var before := em.hp[b]
	em.damage(b, 100.0, "")
	assert_float(before - em.hp[b]).is_equal_approx(100.0, 0.001)
	_run_until(em, hero, func() -> bool: return _running(em, b), 1.0)
	before = em.hp[b]
	em.damage(b, 100.0, "")
	assert_float(before - em.hp[b]).is_equal_approx(20.0, 0.001)
	# the bullets: still guarded
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.FIRE, 3.0)
	before = em.hp[b]
	em.damage(b, 100.0, "")
	assert_float(before - em.hp[b]).is_equal_approx(20.0, 0.001)
	# spent: half again
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.SPENT, 4.0)
	before = em.hp[b]
	em.damage(b, 100.0, "")
	assert_float(before - em.hp[b]).is_equal_approx(150.0, 0.001)
	# over: as ever
	_run_until(em, hero, func() -> bool: return not _running(em, b), 3.0)
	before = em.hp[b]
	em.damage(b, 100.0, "")
	assert_float(before - em.hp[b]).is_equal_approx(100.0, 0.001)


# ---------------------------------------------------------------- the bullets

func test_a_bullet_hits_once_for_its_share_of_max_hp_and_is_gone() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	# one bullet a volley straight at the hero (fan of one, aimed at him)
	var p := _quick("t113_hit", {"emitters": [{"shape": "fan", "count": 1, "speed": 6.0, "rate": 1.0, "aim": "hero"}],
		"timing": {"duration": 1.0, "clear": 0.3}})
	var d := _boss_def("t113_hitter", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.FIRE, 3.0)
	# (the first volley leaves on the bullets' first tick)
	_run_for(em, hero, DT)
	assert_int(int(em.patterns.runs[b]["n"])).is_equal(1)
	_run_until(em, hero, func() -> bool: return int(hero.hits) > 0, 2.0)
	assert_int(hero.hits).is_equal(1)
	assert_float(float(hero.amounts[0])).is_equal_approx(0.12 * 150.0, 0.001)
	# named for the Down! list, no push
	var info: Dictionary = hero.infos[0]
	assert_bool(str(info.get("fx", [])).contains("t113_hit") or str(info).contains("t113_hit")).is_true()
	assert_float(float(info.get("knock", -1.0))).is_equal(0.0)
	# the bullet is gone
	assert_int(int(em.patterns.runs[b]["n"])).is_equal(0)
	_run_for(em, hero, 1.0)
	assert_int(hero.hits).is_equal(1)


func test_the_bullets_burn_out_harmless_when_it_ends() -> void:
	var w := _world(Vector3(0, 0, 40))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _quick("t113_clear", {"emitters": [{"shape": "ring", "count": 12, "speed": 1.0, "rate": 2.0}], "timing": {"duration": 1.5, "clear": 0.5}})
	var d := _boss_def("t113_clearer", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.SPENT, 4.0)
	var n := int(em.patterns.runs[b]["n"])
	assert_bool(n > 0).is_true()
	# the hero walks into them: none hurts him
	hero.global_position = Vector3(0, 0, 1.2)
	_run_for(em, hero, 0.55)
	assert_int(hero.hits).is_equal(0)
	assert_int(int(em.patterns.runs[b]["n"])).is_equal(0)


func test_the_finale_pulls_the_bullets_home() -> void:
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _quick("t113_pull", {"emitters": [{"shape": "ring", "count": 10, "speed": 3.0, "rate": 1.0, "finale_pull": 1.0, "pull_speed": 7.0}],
		"timing": {"duration": 4.0, "clear": 0.5}, "projectile": {"look": "brand_fireball", "range": 30.0}})
	var d := _boss_def("t113_puller", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.FIRE and float(em.patterns.runs[b]["t"]) >= 2.9, 6.0)
	var run: Dictionary = em.patterns.runs[b]
	var far0 := _mean_dist(run)
	var n0 := int(run["n"])
	_run_until(em, hero, func() -> bool: return float(em.patterns.runs[b]["t"]) >= 3.5, 2.0)
	run = em.patterns.runs[b]
	# coming home: nearer the boss than before, none fired in the pull, the nearest already gone into him
	assert_float(_mean_dist(run)).is_less(far0)
	assert_bool(int(run["n"]) <= n0).is_true()
	var b_arr: PackedFloat32Array = run["b"]
	var vx := b_arr[BossPatterns.BVX]
	var vz := b_arr[BossPatterns.BVZ]
	var x := b_arr[BossPatterns.BX]
	var z := b_arr[BossPatterns.BZ]
	assert_bool(Vector2(vx, vz).dot(Vector2(-x, -z)) > 0.0).is_true()
	assert_float(Vector2(vx, vz).length()).is_equal_approx(7.0, 0.01)


func _mean_dist(run: Dictionary) -> float:
	var n := int(run["n"])
	var b: PackedFloat32Array = run["b"]
	var s := 0.0
	for k in range(n):
		s += Vector2(b[k * BossPatterns.B + BossPatterns.BX], b[k * BossPatterns.B + BossPatterns.BZ]).length()
	return s / float(maxi(n, 1))


# ---------------------------------------------------------------- the emitters' geometry

func test_spiral_arms_spin_and_turn_back_halfway() -> void:
	var e := BossAttackDef.emitter_full({"shape": "spiral", "arms": 3, "count": 1, "spin": 30.0, "reverse_at": 0.5})
	var v := BossAttackDef.volley(e, 0.0, 8.0, 0.0)
	assert_int(v.size()).is_equal(9)
	assert_float(rad_to_deg(v[3] - v[0])).is_equal_approx(120.0, 0.001)
	assert_float(rad_to_deg(v[6] - v[0])).is_equal_approx(240.0, 0.001)
	# turning 30 degrees a second to the halfway, back the other way after it
	assert_float(BossAttackDef.emitter_turned(e, 2.0, 8.0)).is_equal_approx(60.0, 0.001)
	assert_float(BossAttackDef.emitter_turned(e, 4.0, 8.0)).is_equal_approx(120.0, 0.001)
	assert_float(BossAttackDef.emitter_turned(e, 6.0, 8.0)).is_equal_approx(60.0, 0.001)
	# a pair on each arm over spread_deg
	var e2 := BossAttackDef.emitter_full({"shape": "spiral", "arms": 2, "count": 2, "spread_deg": 10.0})
	var v2 := BossAttackDef.volley(e2, 0.0, 8.0, 0.0)
	assert_int(v2.size()).is_equal(12)
	assert_float(rad_to_deg(v2[3] - v2[0])).is_equal_approx(10.0, 0.001)


func test_a_ring_leaves_its_gap_facing_the_aim() -> void:
	var e := BossAttackDef.emitter_full({"shape": "ring", "count": 10, "gap": 90.0})
	var v := BossAttackDef.volley(e, 0.0, 8.0, 0.0)
	assert_int(v.size()).is_equal(30)
	for j in range(0, v.size(), 3):
		var a := wrapf(rad_to_deg(v[j]), -180.0, 180.0)
		assert_bool(absf(a) >= 45.0 - 0.001).is_true()
	var full := BossAttackDef.volley(BossAttackDef.emitter_full({"shape": "ring", "count": 8}), 0.0, 8.0, 0.0)
	assert_float(rad_to_deg(full[3] - full[0])).is_equal_approx(45.0, 0.001)


func test_a_rose_opens_into_its_petals_and_breathes() -> void:
	var e := BossAttackDef.emitter_full({"shape": "rose", "count": 20, "petals": 5, "depth": 0.75, "speed": 4.0})
	var v := BossAttackDef.volley(e, 0.0, 9.0, 0.0)
	assert_int(v.size()).is_equal(60)
	# a petal's tip at full speed, a dip between two petals at speed x (1 - depth)
	assert_float(v[1]).is_equal_approx(4.0, 0.001)
	assert_float(v[2 * 3 + 1]).is_equal_approx(4.0 * 0.25, 0.001)
	assert_float(v[4 * 3 + 1]).is_equal_approx(4.0, 0.001)
	# the depth breathes between 0 and depth with bloom_hz
	var eb := BossAttackDef.emitter_full({"shape": "rose", "depth": 0.8, "bloom_hz": 0.5})
	assert_float(BossAttackDef.rose_depth(eb, 0.0)).is_equal_approx(0.8, 0.001)
	assert_float(BossAttackDef.rose_depth(eb, 1.0)).is_equal_approx(0.0, 0.001)
	# the mandala's turn: a jump of turn_deg every turn_every seconds
	var et := BossAttackDef.emitter_full({"shape": "rose", "turn_every": 3.0, "turn_deg": 36.0})
	var a0 := BossAttackDef.emitter_angle(et, 2.99, 9.0, 0.0)
	var a1 := BossAttackDef.emitter_angle(et, 3.01, 9.0, 0.0)
	assert_float(rad_to_deg(a1 - a0)).is_equal_approx(36.0, 0.001)


func test_a_sweep_swings_and_a_pulse_comes_on_every_second_sweep() -> void:
	var e := BossAttackDef.emitter_full({"shape": "sweep", "count": 3, "spread_deg": 40.0, "sweep_deg": 140.0, "sweep_hz": 0.25})
	# a quarter of a swing in: the fan's middle 70 degrees round
	assert_float(rad_to_deg(BossAttackDef.emitter_angle(e, 1.0, 7.0, 0.0))).is_equal_approx(70.0, 0.001)
	assert_float(rad_to_deg(BossAttackDef.emitter_angle(e, 3.0, 7.0, 0.0))).is_equal_approx(-70.0, 0.001)
	var v := BossAttackDef.volley(e, 0.0, 7.0, 0.0)
	assert_int(v.size()).is_equal(9)
	assert_float(rad_to_deg(v[6] - v[0])).is_equal_approx(40.0, 0.001)
	# on for 2 s of every 4 from 2 s: the second sweep, the fourth...
	var p := BossAttackDef.emitter_full({"shape": "sweep", "pulse_every": 4.0, "pulse_on": 2.0, "pulse_at": 2.0})
	assert_bool(BossAttackDef.emitter_on(p, 1.0, 7.0)).is_false()
	assert_bool(BossAttackDef.emitter_on(p, 2.5, 7.0)).is_true()
	assert_bool(BossAttackDef.emitter_on(p, 4.5, 7.0)).is_false()
	assert_bool(BossAttackDef.emitter_on(p, 6.5, 7.0)).is_true()
	# start / stop as shares of the duration, and the finale's pull silencing it
	var s := BossAttackDef.emitter_full({"start": 0.25, "stop": 0.75, "finale_pull": 1.0})
	assert_bool(BossAttackDef.emitter_on(s, 1.0, 8.0)).is_false()
	assert_bool(BossAttackDef.emitter_on(s, 3.0, 8.0)).is_true()
	assert_bool(BossAttackDef.emitter_on(s, 6.5, 8.0)).is_false()
	var f := BossAttackDef.emitter_full({"finale_pull": 1.0})
	assert_bool(BossAttackDef.pulling(f, 7.5, 8.0)).is_true()
	assert_bool(BossAttackDef.emitter_on(f, 7.5, 8.0)).is_false()
	assert_bool(BossAttackDef.pulling(f, 6.5, 8.0)).is_false()


func test_a_wall_crosses_its_aim_with_an_opening_and_volleys_keep_their_rate() -> void:
	var e := BossAttackDef.emitter_full({"shape": "wall", "count": 9, "width": 8.0, "gap": 0.0})
	var v := BossAttackDef.volley(e, 0.0, 8.0, 0.0)
	assert_int(v.size()).is_equal(27)
	assert_float(v[2]).is_equal_approx(-4.0, 0.001)
	assert_float(v[26]).is_equal_approx(4.0, 0.001)
	var g := BossAttackDef.emitter_full({"shape": "wall", "count": 9, "width": 8.0, "gap": 2.5})
	var vg := BossAttackDef.volley(g, 0.0, 8.0, 0.0, 0.5)
	assert_bool(vg.size() < 27).is_true()
	# four volleys a second over 2 s: the first at once, then one every quarter
	var times := BossAttackDef.emitter_volley_times(BossAttackDef.emitter_full({"rate": 4.0}), 2.0)
	assert_int(times.size()).is_equal(8)
	assert_float(times[0]).is_equal(0.0)


func test_the_bullets_in_the_game_follow_the_emitter_maths() -> void:
	var w := _world(Vector3(0, 0, 80))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _quick("t113_geo", {"emitters": [{"shape": "spiral", "arms": 3, "count": 1, "speed": 3.0, "rate": 4.0, "spin": 30.0}],
		"timing": {"duration": 2.0, "clear": 0.3}, "projectile": {"look": "burning_tumbleweed", "range": 40.0}})
	var d := _boss_def("t113_geom", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _phase(em, b) == BossPatterns.FIRE, 3.0)
	_run_for(em, hero, 2.0 - DT * 2.0)
	var run: Dictionary = em.patterns.runs[b]
	# about 2 s x 4 volleys x 3 arms in the air, each flying 3 m/s straight out
	assert_int(int(run["volleys"])).is_between(8, 9)
	assert_int(int(run["n"])).is_equal(int(run["volleys"]) * 3)
	var bb: PackedFloat32Array = run["b"]
	for k in range(int(run["n"])):
		var o := k * BossPatterns.B
		var vel := Vector2(bb[o + BossPatterns.BVX], bb[o + BossPatterns.BVZ])
		var at := Vector2(bb[o + BossPatterns.BX], bb[o + BossPatterns.BZ])
		assert_float(vel.length()).is_equal_approx(3.0, 0.001)
		assert_float(absf(vel.normalized().cross(at.normalized()))).is_less(0.01)
	assert_int(em.patterns.peak).is_greater_equal(int(run["n"]))


## The Level Editor's mirror (tools/level_editor/boss_model.js simulate) gives these same numbers for these same emitters:
## selftest_BOSS113.py pins them too, so the page's preview counts what the game plays.
const MIRROR_CASES := [
	[{"timing": {"duration": 6.0}, "projectile": {"range": 12.0}, "emitters": [{"shape": "spiral", "arms": 3, "count": 2, "spread_deg": 10.0, "speed": 3.0, "rate": 4.0, "spin": 30.0, "reverse_at": 0.5}]}, [96, 144, 24]],
	[{"timing": {"duration": 7.0}, "projectile": {"range": 14.0}, "emitters": [{"shape": "rose", "count": 24, "petals": 5, "depth": 0.75, "bloom_hz": 0.5, "speed": 3.0, "rate": 1.0, "turn_every": 2.0, "turn_deg": 36.0, "finale_pull": 1.0, "pull_speed": 6.0}]}, [139, 144, 6]],
	[{"timing": {"duration": 7.0}, "projectile": {"range": 15.0}, "emitters": [{"shape": "sweep", "count": 4, "spread_deg": 40.0, "speed": 2.5, "rate": 2.0, "sweep_deg": 140.0, "sweep_hz": 0.25}, {"shape": "sweep", "count": 3, "spread_deg": 30.0, "speed": 2.2, "rate": 2.0, "sweep_deg": 140.0, "sweep_hz": 0.25, "offset_deg": 45.0, "pulse_every": 4.0, "pulse_on": 2.0, "pulse_at": 2.0}]}, [66, 74, 20]],
	[{"timing": {"duration": 6.0}, "projectile": {"range": 12.0}, "emitters": [{"shape": "wall", "count": 9, "width": 8.0, "gap": 2.0, "rate": 1.0, "speed": 3.0}, {"shape": "ring", "count": 12, "gap": 60.0, "rate": 0.5, "speed": 2.0, "start": 0.2, "stop": 0.9}]}, [68, 84, 9]],
]


func test_the_level_editor_counts_what_the_game_plays() -> void:
	for k in range(MIRROR_CASES.size()):
		var c: Array = MIRROR_CASES[k]
		var a := _pattern("t113_mirror%d" % k, (c[0] as Dictionary).duplicate(true))
		var sim: Dictionary = a.simulate(1.0 / 30.0)
		var want: Array = c[1]
		assert_array([int(sim["peak"]), int(sim["fired"]), int(sim["volleys"])]).is_equal(want)
