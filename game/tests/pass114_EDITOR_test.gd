extends GdUnitTestSuite

## Pass 114, lane EDITOR: a bullet-heaven pattern's trigger may take ranges (trigger.first_after, first_by and cooldown a
## number or [min, max]), rolled from the fight's own seeded dice (first_after and first_by once per fight, the cooldown
## afresh after each attack), the cooldown counted from the moment the attack is completely over (the tell, the bullets,
## the burn-out and the spent seconds); and the three shipped patterns' new numbers as shape rules against pass 113's
## (Garry: twice as long, twice as far, a bit more space between the bullets), read from the files.

const DT := 1.0 / 60.0

## Pass 113's numbers (the attacks as lane BOSS shipped them): duration, range, and per emitter the keys the spacing reads.
const PASS113 := {
	"royal_dust_devil": {"duration": 8.0, "range": 24.0, "emitters": [
		{"shape": "spiral", "arms": 3, "count": 2, "spread_deg": 8.0, "speed": 3.2, "rate": 4.5, "start": 0.0, "stop": 1.0},
		{"shape": "ring", "count": 20, "speed": 2.4, "rate": 0.6, "gap": 80.0, "start": 0.15, "stop": 0.9}]},
	"venom_monsoon": {"duration": 7.0, "range": 22.0, "emitters": [
		{"shape": "sweep", "count": 5, "spread_deg": 56.0, "speed": 2.8, "rate": 2.8, "start": 0.0, "stop": 1.0},
		{"shape": "sweep", "count": 4, "spread_deg": 40.0, "speed": 2.4, "rate": 2.4, "start": 0.0, "stop": 1.0}]},
	"hellbrand_mandala": {"duration": 9.0, "range": 18.0, "emitters": [
		{"shape": "rose", "count": 30, "speed": 3.0, "rate": 0.85, "start": 0.0, "stop": 1.0},
		{"shape": "spiral", "arms": 5, "count": 1, "speed": 2.0, "rate": 1.5, "start": 0.1, "stop": 1.0}]},
}
## the most bullets in the air at once a shipped pattern may have (BossAttackDef.simulate; the Level Editor warns past it)
const PEAK_CAP := 600
## Pass 115 (lane BOSS): every emitter's speed 1.5 x pass 114's (Garry: "increase the speed of projectiles by 50%").
const PASS115_SPEED := 1.5

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
func fx_sand(_a, _b = 1.0) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
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
var _map_seed0 := 0
var _rng_seed0 := 0
var _run_seed0 = null


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	_map_seed0 = Run.map_seed
	_rng_seed0 = Run.rng_seed
	_run_seed0 = Run.get("run_seed")


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	for id: String in _attacks_added:
		Registry.boss_attacks.erase(id)
	_attacks_added.clear()
	Run.map_seed = _map_seed0
	Run.rng_seed = _rng_seed0
	if _run_seed0 != null:
		Run.set("run_seed", _run_seed0)
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0


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
	hero.global_position = Vector3(0, 0, 30)
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


## A quick ranged pattern: a 1 s tell, 2 s of one ring a second, 1 s spent; the trigger as `trig`.
func _ranged(id: String, trig: Dictionary) -> BossAttackDef:
	return _pattern(id, {"trigger": trig, "tell": {"seconds": 1.0, "duck_db": 0.0}, "timing": {"duration": 2.0, "clear": 0.3},
		"spent": {"seconds": 1.0, "damage_taken": 1.5, "still": true}, "guard": {"share": 0.8},
		"projectile": {"look": "venom_blob", "range": 6.0, "hit_radius": 0.3},
		"emitters": [{"shape": "ring", "count": 6, "speed": 4.0, "rate": 1.0}], "hit": {"hit_frac": 0.12}, "knockback": 0.0})


func _spawn(em: EnemyManager, id: String) -> int:
	var b := em.spawn(id, Vector3.ZERO)
	em.state[b] = EnemyManager.STATE_MOVE
	return b


## The run's seeds for a test (lane REPLAY's Run.run_seed, when it is there, put to 0 so these two decide).
func _seeds(rng_seed: int, map_seed: int) -> void:
	if "run_seed" in Run:
		Run.set("run_seed", 0)
	Run.rng_seed = rng_seed
	Run.map_seed = map_seed


func _started(em: EnemyManager) -> int:
	return em.patterns.started if em.patterns != null else 0


## Step the attack scripts until `cond` holds (or `cap_s` seconds): the seconds it took.
func _run_until(em: EnemyManager, hero: Node3D, cond: Callable, cap_s: float) -> float:
	var t := 0.0
	while t < cap_s:
		if cond.call():
			return t
		em._update_boss(DT, hero.global_position)
		t += DT
	return t


# ---------------------------------------------------------------- the ranges

func test_a_trigger_key_reads_a_number_or_a_range() -> void:
	assert_vector(BossAttackDef.range_of(12.0, 45.0)).is_equal(Vector2(12, 12))
	assert_vector(BossAttackDef.range_of(7, 45.0)).is_equal(Vector2(7, 7))
	assert_vector(BossAttackDef.range_of([10.0, 15.0], 45.0)).is_equal(Vector2(10, 15))
	# a backwards range is put in order, nothing below 0, a one-number list is that number
	assert_vector(BossAttackDef.range_of([15.0, 10.0], 45.0)).is_equal(Vector2(10, 15))
	assert_vector(BossAttackDef.range_of([-3.0, 5.0], 45.0)).is_equal(Vector2(0, 5))
	assert_vector(BossAttackDef.range_of([20], 45.0)).is_equal(Vector2(20, 20))
	# anything else plays the default
	assert_vector(BossAttackDef.range_of("soon", 45.0)).is_equal(Vector2(45, 45))
	assert_vector(BossAttackDef.range_of([1.0, 2.0, 3.0], 45.0)).is_equal(Vector2(45, 45))
	var a := _pattern("t114_keys", {"trigger": {"first_after": [10.0, 15.0], "first_by": 30.0}})
	assert_vector(a.trigger_range("first_after")).is_equal(Vector2(10, 15))
	assert_bool(a.trigger_is_range("first_after")).is_true()
	assert_bool(a.trigger_is_range("first_by")).is_false()
	# the key the file leaves out plays the game's default (45 s)
	assert_vector(a.trigger_range("cooldown")).is_equal(Vector2(45, 45))
	# without a roll the low end plays
	assert_float(a.trigger_value("first_after")).is_equal(10.0)
	assert_float(a.trigger_value("first_after", {"first_after": 13.5})).is_equal(13.5)


func test_rolls_stay_within_their_range_and_the_same_seed_rolls_the_same() -> void:
	var a := _pattern("t114_rolls", {"trigger": {"first_after": [10.0, 15.0], "first_by": [30.0, 40.0], "cooldown": [20.0, 30.0]}})
	var r1 := RandomNumberGenerator.new()
	r1.seed = 1234
	var r2 := RandomNumberGenerator.new()
	r2.seed = 1234
	var seen_lo := 99.0
	var seen_hi := 0.0
	for k in range(300):
		var x := a.roll_triggers(r1)
		var y := a.roll_triggers(r2)
		assert_dict(x).is_equal(y)
		assert_bool(float(x["first_after"]) >= 10.0 and float(x["first_after"]) <= 15.0).is_true()
		assert_bool(float(x["first_by"]) >= 30.0 and float(x["first_by"]) <= 40.0).is_true()
		assert_bool(float(x["cooldown"]) >= 20.0 and float(x["cooldown"]) <= 30.0).is_true()
		seen_lo = minf(seen_lo, float(x["first_after"]))
		seen_hi = maxf(seen_hi, float(x["first_after"]))
	# it really spreads over the range
	assert_bool(seen_lo < 10.5 and seen_hi > 14.5).is_true()
	# another seed rolls another fight
	var r3 := RandomNumberGenerator.new()
	r3.seed = 99
	r1.seed = 1234
	assert_bool(a.roll_triggers(r3) != a.roll_triggers(r1)).is_true()
	# a plain number takes no roll (the dice stay where they were)
	var b := _pattern("t114_fixed", {"trigger": {"first_after": 15.0, "first_by": 45.0, "cooldown": 45.0}})
	var r4 := RandomNumberGenerator.new()
	r4.seed = 5
	var st := r4.state
	assert_dict(b.roll_triggers(r4)).is_equal({"first_after": 15.0, "first_by": 45.0, "cooldown": 45.0})
	assert_int(r4.state).is_equal(st)


func test_pattern_due_plays_the_fights_rolls() -> void:
	var a := _pattern("t114_due", {"trigger": {"first_after": [10.0, 15.0], "first_at_hp": 0.6, "first_by": [30.0, 40.0], "cooldown": [20.0, 30.0]}})
	var rolled := {"first_after": 12.5, "first_by": 33.0, "cooldown": 24.0}
	assert_bool(a.pattern_due(12.4, 0.1, 0, -1e9, rolled)).is_false()
	assert_bool(a.pattern_due(12.5, 0.1, 0, -1e9, rolled)).is_true()
	assert_bool(a.pattern_due(32.9, 0.99, 0, -1e9, rolled)).is_false()
	assert_bool(a.pattern_due(33.0, 0.99, 0, -1e9, rolled)).is_true()
	# the next: the rolled cooldown after the last one ended
	assert_bool(a.pattern_due(83.9, 0.1, 1, 60.0, rolled)).is_false()
	assert_bool(a.pattern_due(84.0, 0.1, 1, 60.0, rolled)).is_true()


# ---------------------------------------------------------------- the runner

func test_the_runner_rolls_once_a_fight_and_the_cooldown_after_each_attack_is_completely_over() -> void:
	_seeds(0, 777)
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var p := _ranged("t114_run", {"first_after": [2.0, 4.0], "first_at_hp": 1.0, "first_by": [2.0, 4.0], "cooldown": [5.0, 9.0]})
	var d := _boss_def("t114_runner", [{"name": p.id}])
	var b := _spawn(em, d.id)
	_run_until(em, hero, func() -> bool: return _started(em) > 0, 10.0)
	assert_int(_started(em)).is_equal(1)
	var s := em.patterns.schedule_of(b)
	var r: Dictionary = (s["rolls"] as Dictionary)[p.id]
	var fa := float(r["first_after"])
	assert_bool(fa >= 2.0 and fa <= 4.0).is_true()
	# it came at the rolled moment (at full HP first_at_hp 1.0 is met at once, so first_after decides)
	assert_float(float(s["fight"])).is_equal_approx(fa, DT * 1.5)
	var start1 := float(s["fight"])
	var cd0 := float(r["cooldown"])
	assert_bool(cd0 >= 5.0 and cd0 <= 9.0).is_true()
	# the first ends: the tell, the bullets, the spent seconds (x 1/pace, the creatures' clock) and only then last_end
	_run_until(em, hero, func() -> bool: return not em.patterns.running(b), 20.0)
	var s1 := em.patterns.schedule_of(b)
	var ended := float(s1["last_end"])
	assert_float(ended - start1).is_equal_approx((1.0 + 2.0 + 1.0) / em.pace, 0.1)
	# the cooldown was rolled afresh at the end; first_after and first_by kept for the fight
	var r1: Dictionary = (s1["rolls"] as Dictionary)[p.id]
	var cd1 := float(r1["cooldown"])
	assert_bool(cd1 >= 5.0 and cd1 <= 9.0).is_true()
	assert_float(cd1).is_not_equal(cd0)
	assert_float(float(r1["first_after"])).is_equal(fa)
	# the second comes the rolled cooldown after the first was completely over
	_run_until(em, hero, func() -> bool: return _started(em) > 1, 20.0)
	assert_int(_started(em)).is_equal(2)
	var s2 := em.patterns.schedule_of(b)
	assert_float(float(s2["fight"]) - ended).is_equal_approx(cd1, DT * 1.5)


func test_the_same_run_seed_rolls_the_same_fight_and_another_seed_another() -> void:
	var got: Array = []
	for ms: int in [4242, 4242, 4243]:
		_seeds(0, ms)
		var w := _world()
		var em: EnemyManager = w["em"]
		var hero: Node3D = w["hero"]
		var p := _ranged("t114_seed_%d_%d" % [ms, got.size()], {"first_after": [10.0, 15.0], "first_at_hp": 0.6, "first_by": [30.0, 40.0], "cooldown": [20.0, 30.0]})
		var d := _boss_def("t114_seeder_%d" % got.size(), [{"name": p.id}])
		var b := _spawn(em, d.id)
		_run_until(em, hero, func() -> bool: return false, 0.2)
		var r: Dictionary = ((em.patterns.schedule_of(b)["rolls"]) as Dictionary)[p.id]
		got.append([float(r["first_after"]), float(r["first_by"]), float(r["cooldown"])])
	assert_array(got[0]).is_equal(got[1])
	assert_bool(got[0] != got[2]).is_true()
	# and the run sim's own seed comes before the map's
	assert_int(BossPatterns.seed_base()).is_equal(4243)
	_seeds(31, 4243)
	assert_int(BossPatterns.seed_base()).is_equal(31)


# ---------------------------------------------------------------- the three shipped attacks (pass 114's numbers)

## What a bullet of emitter `e` has round it: the angle to its neighbour in the volley (degrees) x the metres to the next
## volley's bullet behind it (speed / rate). Fewer bullets a ring, a wider fan or a lower rate all make it bigger.
func _room(e: Dictionary) -> float:
	var n := maxi(int(e.get("count", 1)), 1)
	var lat := 0.0
	match str(e.get("shape", "spiral")):
		"ring":
			lat = (360.0 - float(e.get("gap", 0.0))) / float(n)
		"rose":
			lat = 360.0 / float(n)
		_:
			lat = float(e.get("spread_deg", 60.0)) / float(n - 1) if n > 1 else 360.0 / float(maxi(int(e.get("arms", 1)), 1))
	return lat * float(e.get("speed", 3.0)) / maxf(float(e.get("rate", 4.0)), 0.001)


func test_the_three_attacks_last_twice_as_long_fly_twice_as_far_and_leave_more_room() -> void:
	for id: String in PASS113.keys():
		var a: BossAttackDef = Registry.boss_attack(id)
		assert_object(a).is_not_null()
		var old: Dictionary = PASS113[id]
		assert_float(a.pattern_duration()).is_equal_approx(2.0 * float(old["duration"]), 0.001)
		assert_float(a.num("projectile", "range")).is_equal_approx(2.0 * float(old["range"]), 0.001)
		var ems := a.emitters_full()
		assert_int(ems.size()).is_equal((old["emitters"] as Array).size())
		for k in range(ems.size()):
			var e: Dictionary = ems[k]
			var o: Dictionary = BossAttackDef.emitter_full(old["emitters"][k])
			assert_str(str(e["shape"])).is_equal(str(o["shape"]))
			# the pattern's shape over the longer time: its on and off shares as they were, the speed as it was (pass 115,
			# lane BOSS: Garry's "increase the speed of projectiles by 50%": 1.5 x it, pass115_BOSS_test)
			assert_float(float(e["start"])).is_equal_approx(float(o["start"]), 0.0001)
			assert_float(float(e["stop"])).is_equal_approx(float(o["stop"]), 0.0001)
			assert_float(float(e["speed"])).is_equal_approx(float(o["speed"]) * PASS115_SPEED, 0.0001)
			# about a quarter more room round every bullet (pass 115: the room along a line grows with the speed too, so
			# that part is taken out here: what pass 114 made of the counts, spreads and rates)
			var grew := _room(e) / _room(o) / PASS115_SPEED
			assert_bool(grew >= 1.2 and grew <= 1.35).override_failure_message("%s emitter %d: room x%.3f" % [id, k + 1, grew]).is_true()
		# its words name the new seconds; the most in the air at once under the cap
		assert_str(a.doc).contains("for %d s" % int(a.pattern_duration()))
		var sim := a.simulate()
		# (pass 115, the lead: the bullets stop at the 14 m wall, so fewer are in the air at once; the screen as dense)
		assert_bool(int(sim["peak"]) >= 30 and int(sim["peak"]) <= PEAK_CAP).override_failure_message("%s peak %d" % [id, int(sim["peak"])]).is_true()
