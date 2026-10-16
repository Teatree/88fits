extends GdUnitTestSuite

## Pass 72, lane BOSS: custom boss attacks (content/boss_attacks, BossAttackDef: the pattern and its gap rule, the
## landing times, the runner's entries; EnemyManager's custom-attack runner end to end on a fake game: the Gila Grande's
## red cactus rain telegraphs each landing spot, its spikes land on time, the hero in a gap is never hit and the hero on a
## spot is hit once; a volley, a ring and a slam made in code), and the boss HP pegged to the hero's DPS
## (WaveTimeline.boss_hp_mult, Run.recent_dps, WaveDirector.boss_dps_scale, the boss spawn, the arena untouched, Red
## Canyon's block read from the map file).

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
var _ended := false
var lines: Array = []
var rings: Array = []
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
func telegraph_line(a, b, c, d, _e) -> void:
	lines.append({"from": a, "dir": b, "length": float(c), "dur": float(d)})
func telegraph_ring(a, b, c, _d, e = true) -> void:
	rings.append({"at": a, "r": float(b), "dur": float(c), "filled": bool(e)})
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func rumble_mark(_a, _b) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
var hits := 0
var knocks: Array = []
var blasts := 0
func take_damage(a: float, _f: Vector3, i: Dictionary = {}) -> void:
	hits += 1
	knocks.append(float(i.get("knock", -1.0)))
func shove(_v: Vector3, _c := true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h := true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h := true) -> void:
	blasts += 1
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
var _keep_scaling: Dictionary = {}


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	_keep_scaling = (Registry.map("red_canyon").timeline.boss_hp_scaling as Dictionary).duplicate(true)


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	for id: String in _attacks_added:
		Registry.boss_attacks.erase(id)
	_attacks_added.clear()
	Registry.map("red_canyon").timeline.boss_hp_scaling = _keep_scaling
	Run.arena = false
	Run.elapsed = 0.0
	Run.held_time = 0.0
	Run.stage = 0
	Run.dps_reset()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at`, with the real crowd.
func _world(hero_at := Vector3(0, 0, 0)) -> Dictionary:
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


## A test creature from `from` with the given attack list (gone after the test).
func _boss_def(id: String, from: String, attacks: Array) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = {}
	d.boss = {"attacks": attacks, "cooldown_between": 2.0, "hp_mult_per_stage": 2.0}
	Registry.enemies[id] = d
	_added.append(id)
	return d


## A custom attack made in code (gone after the test).
func _attack(id: String, d: Dictionary) -> BossAttackDef:
	var src := {"id": id, "name": id}
	src.merge(d, true)
	var a: BossAttackDef = JsonContent.build("boss_attacks", src, "res://content/boss_attacks/%s/" % id)
	a.id = id
	Registry.boss_attacks[id] = a
	_attacks_added.append(id)
	return a


## Creature `i` starts the attack at `k` of its list now (its wind-up and marks), as the runner does.
func _begin(em: EnemyManager, i: int, k: int) -> void:
	em.state[i] = EnemyManager.STATE_MOVE
	em.atk_i[i] = k
	em.atk_t[i] = 0.0
	em.hold_t[i] = 0.0
	em._update_attacks(i, DT, em.player.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)


## ... and fires it (the wind-up over).
func _fire(em: EnemyManager, i: int) -> void:
	em.timer[i] = 0.0
	em._update_attacks(i, DT, em.player.global_position)


func _tick_until_done(em: EnemyManager, hero: Node3D, cap_s := 8.0) -> void:
	var t := 0.0
	while not em._custom_runs.is_empty() and t < cap_s:
		em._tick_custom_attacks(DT, hero.global_position)
		t += DT


# ---------------------------------------------------------------- the content

func test_the_gila_rains_red_cactus_spikes_instead_of_its_rumble() -> void:
	var gila: EnemyDef = Registry.enemy("gila_grande")
	var names: Array = []
	for a in gila.boss.get("attacks", []):
		names.append(str((a as Dictionary).get("name", "")))
	assert_bool(names.has("cactus_rain")).is_true()
	assert_bool(names.has("rumble")).is_false()
	var rain: BossAttackDef = Registry.boss_attack("cactus_rain")
	assert_object(rain).is_not_null()
	assert_str(rain.attack_kind).is_equal("rain")
	assert_str(rain.display_name).is_not_empty()
	# a custom attack has no icon and is never listed as missing one
	assert_bool(Registry.missing_icons.has("cactus_rain")).is_false()
	assert_bool(JsonContent.TYPES.has("boss_attacks")).is_true()
	# red, a cactus spike, a huge area, gaps, a telegraph before each landing (Garry's numbers may move: shapes only)
	var t := rain.tint()
	assert_bool(t.r > t.g * 2.0 and t.r > t.b * 2.0).override_failure_message("the spikes are red").is_true()
	assert_str(rain.text("projectile", "look")).is_equal("spike")
	assert_float(rain.num("pattern", "radius_max")).is_greater_equal(10.0)
	assert_float(rain.num("pattern", "gap")).is_greater(0.0)
	assert_str(rain.text("telegraph", "kind")).is_equal("circles")
	assert_float(rain.num("telegraph", "seconds")).is_greater(0.3)
	# a built-in name is never a custom attack, and the resolved entry keeps the boss entry's own keys
	var em := EnemyManager.new()
	assert_object(em.custom_attack_of("rumble")).is_null()
	assert_object(em.custom_attack_of("cactus_rain")).is_not_null()
	var e := rain.runner_entry({"name": "cactus_rain", "min_range": 3.0})
	assert_str(str(e["name"])).is_equal("cactus_rain")
	assert_str(str(e["custom"])).is_equal("cactus_rain")
	assert_float(float(e["windup"])).is_equal(rain.num("timing", "windup"))
	assert_str(str(e["telegraph"])).is_equal("none")
	assert_float(float(e["min_range"])).is_equal(3.0)
	em.free()


func test_every_shape_keeps_the_gap_between_landing_circles() -> void:
	var rng := RandomNumberGenerator.new()
	for shape: String in BossAttackDef.SHAPES:
		for seed_v in [1, 7, 42]:
			rng.seed = seed_v
			var pat := {"shape": shape, "radius_min": 3.0, "radius_max": 16.0, "spacing": 3.2, "jitter": 0.6, "gap": 1.0, "turn": true, "order": "out"}
			var pts := BossAttackDef.points(pat, 0.9, rng)
			assert_int(pts.size()).override_failure_message("%s seed %d: %d points" % [shape, seed_v, pts.size()]).is_greater(25)
			# the rule: never less than `gap` of free sand between two circles
			assert_float(BossAttackDef.smallest_gap(pts, 0.9)).override_failure_message(shape).is_greater_equal(1.0 - 0.001)
			for p: Vector2 in pts:
				assert_float(p.length()).is_less_equal(16.0 + 1.0)
				assert_float(p.length()).is_greater_equal(3.0 - 1.0)
	# "out": inside first
	rng.seed = 3
	var outp := BossAttackDef.points({"shape": "rings", "radius_min": 2.0, "radius_max": 12.0, "spacing": 3.0, "jitter": 0.0, "gap": 0.8, "order": "out"}, 0.8, rng)
	for k in range(1, outp.size()):
		assert_float(outp[k].length()).is_greater_equal(outp[k - 1].length() - 0.001)
	# `count` keeps the first ones
	rng.seed = 3
	assert_int(BossAttackDef.points({"shape": "grid", "radius_max": 14.0, "count": 9}, 0.9, rng).size()).is_equal(9)
	# without the random (no jitter, no turn) a layout is the same in the game and in the Level Editor's preview
	# (boss_model.js; selftest_BOSS.py pins the same three counts)
	var fixed := {"radius_min": 3.6, "radius_max": 16.0, "spacing": 3.2, "jitter": 0.0, "gap": 1.0, "turn": false, "order": "out"}
	var want := {"rings": 89, "grid": 84, "spiral": 82}
	for shape: String in want.keys():
		var pf := fixed.duplicate()
		pf["shape"] = shape
		assert_int(BossAttackDef.points(pf, 0.9, rng).size()).override_failure_message(shape).is_equal(int(want[shape]))
	# a spacing below the rule is lifted to it
	rng.seed = 5
	var tight := BossAttackDef.points({"shape": "rings", "radius_min": 3.0, "radius_max": 10.0, "spacing": 0.5, "gap": 1.2}, 1.0, rng)
	assert_float(BossAttackDef.smallest_gap(tight, 1.0)).is_greater_equal(1.2 - 0.001)


func test_the_rain_arrives_over_its_stagger() -> void:
	var lt := BossAttackDef.land_times(5, 1.5, 1.1)
	assert_float(lt[0]).is_equal_approx(1.1, 0.0001)
	assert_float(lt[4]).is_equal_approx(2.6, 0.0001)
	for k in range(1, 5):
		assert_float(lt[k]).is_greater(lt[k - 1])
	assert_float(BossAttackDef.land_times(1, 1.5, 1.1)[0]).is_equal_approx(1.1, 0.0001)


func test_a_script_attack_wraps_a_built_in() -> void:
	var a := _attack("t72_rumble2", {"kind": "script", "script": "rumble", "params": {"count": 3, "speed": 9.0, "telegraph": "fan"}})
	var e := a.runner_entry({"name": "t72_rumble2"})
	assert_str(str(e["name"])).is_equal("rumble")
	assert_int(int(e["count"])).is_equal(3)
	assert_bool(e.has("custom")).is_false()


# ---------------------------------------------------------------- the runner

func test_the_cactus_rain_telegraphs_every_spot_and_lands_on_time() -> void:
	var w := _world(Vector3(0, 0, 40))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var rain: BossAttackDef = Registry.boss_attack("cactus_rain")
	var gila: EnemyDef = Registry.enemy("gila_grande")
	var k := -1
	var atks: Array = gila.boss["attacks"]
	for j in range(atks.size()):
		if str((atks[j] as Dictionary).get("name", "")) == "cactus_rain":
			k = j
	assert_int(k).is_greater_equal(0)
	var i := em.spawn("gila_grande", Vector3(0, 0, 0))
	assert_int(i).is_greater_equal(0)
	_begin(em, i, k)
	# the wind-up is the attack's own, 1/pace long (pass 73, lane GROUND, re-pinned on purpose: the rain lights every
	# landing circle at once as the wind-up starts, each up until its spike lands, instead of the area's outline and a
	# circle `telegraph.seconds` before each landing)
	assert_float(em.timer[i]).is_equal_approx(rain.windup_seconds() / em.pace, 0.001)
	var lit: Array = em._custom_lit[i]["spots"]
	assert_int(g.rings.size()).is_equal(lit.size())
	for r: Dictionary in g.rings:
		assert_float(float(r["r"])).is_equal_approx(rain.num("landing", "radius"), 0.001)
		assert_bool(bool(r["filled"])).is_true()
		assert_float(float(r["dur"])).is_greater(rain.num("telegraph", "seconds") / em.pace)
	g.rings.clear()
	_fire(em, i)
	assert_int(em._custom_runs.size()).is_equal(1)
	var spots: Array = em._custom_runs[0]["spots"]
	assert_int(spots.size()).is_greater(30)
	assert_int(spots.size()).is_equal(lit.size())
	assert_int(em.custom_last.get("spots", 0)).is_equal(spots.size())
	# the boss stands while its spikes leave its mouth and its stretch settles (pass 73: the spew's burst + 0.35 s, on the
	# shot clock)
	assert_float(em.hold_t[i]).is_equal_approx((rain.num("spew", "burst") + 0.35) / em.pace, 0.01)
	_tick_until_done(em, hero)
	assert_bool(em._custom_runs.is_empty()).is_true()
	# no circle more after the spew: they were all up already
	assert_int(g.rings.size()).is_equal(0)
	assert_int(em.custom_landed).is_equal(spots.size())
	# the hero 40 m off was never hit
	assert_int(hero.hits).is_equal(0)


func test_between_the_circles_is_safe_and_on_one_is_one_hit() -> void:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var d := _boss_def("t72_rainer", "gila_grande", [{"name": "cactus_rain"}])
	var rain: BossAttackDef = Registry.boss_attack("cactus_rain")
	var i := em.spawn(d.id, Vector3(0, 0, 0))
	_begin(em, i, 0)
	_fire(em, i)
	var spots: Array = em._custom_runs[0]["spots"]
	# the safest spot of the ring between the inner and the outer circles
	var lr := rain.num("landing", "radius")
	var best := Vector3.ZERO
	var best_d := -1.0
	for x in range(-12, 13):
		for z in range(-12, 13):
			var p := Vector3(float(x), 0, float(z))
			if p.length() < 5.0 or p.length() > 12.0:
				continue
			var near := INF
			for s: Dictionary in spots:
				var sv: Vector3 = s["at"]
				near = minf(near, Vector2(p.x - sv.x, p.z - sv.z).length())
			if near > best_d:
				best_d = near
				best = p
	assert_float(best_d).is_greater(lr + 0.3)
	hero.global_position = best
	_tick_until_done(em, hero)
	assert_int(hero.hits).override_failure_message("a hero standing in a gap was hit").is_equal(0)
	# again, the hero on a landing spot: hit once, knocked by the attack's own number
	em.hold_t[i] = 0.0
	_begin(em, i, 0)
	_fire(em, i)
	var spot: Vector3 = (em._custom_runs[0]["spots"] as Array)[3]["at"]
	hero.global_position = Vector3(spot.x, 0, spot.z)
	_tick_until_done(em, hero)
	assert_int(hero.hits).is_equal(1)
	assert_float(float(hero.knocks[0])).is_equal(rain.knockback)
	# its damage: `damage` x the bite x the factors
	assert_float(float(em.custom_last["damage"])).is_equal_approx(rain.damage * d.damage * em.stage_of(i) * em.lvd_of(i) * em.host_of(i), 0.001)


func test_a_volley_a_ring_and_a_slam_made_in_code() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	_attack("t72_volley", {"kind": "volley", "projectile": {"look": "pellet", "speed": 12.0, "range": 18.0, "hit_radius": 0.5},
		"pattern": {"count": 8, "spread_deg": 360, "aim": "hero", "waves": 2, "wave_gap": 0.4}, "timing": {"windup": 0.5}})
	_attack("t72_ring", {"kind": "ring", "projectile": {"speed": 10.0}, "pattern": {"radius_max": 12.0, "width": 1.5, "count": 1},
		"timing": {"windup": 0.5}, "telegraph": {"kind": "ring"}})
	_attack("t72_slam", {"kind": "slam", "pattern": {"radius_max": 5.0, "center": "boss"}, "timing": {"windup": 0.7, "cooldown": 4.5},
		"knockback": 6.0, "lift": 2.0})
	var d := _boss_def("t72_caster", "gila_grande", [{"name": "t72_volley"}, {"name": "t72_ring"}, {"name": "t72_slam"}])
	var i := em.spawn(d.id, Vector3(0, 0, 0))
	# the volley: eight lines, the first down the hero's way; two waves; the hero 6 m off down one is hit once
	_begin(em, i, 0)
	assert_int(g.lines.size()).is_equal(8)
	assert_float(float(g.lines[0]["length"])).is_equal(18.0)
	_fire(em, i)
	assert_int((em._custom_runs[0]["shots"] as Array).size()).is_equal(16)
	_tick_until_done(em, hero)
	assert_int(hero.hits).is_equal(2)
	# the ring: it races out once; the hero 6 m off is hit as it passes
	hero.hits = 0
	em.hold_t[i] = 0.0
	_begin(em, i, 1)
	_fire(em, i)
	_tick_until_done(em, hero)
	assert_int(hero.hits).is_equal(1)
	# the slam: 5 m round the boss; 6 m off is clear, 3 m off is hit and thrown; its own rest after it
	hero.hits = 0
	_begin(em, i, 2)
	_fire(em, i)
	assert_int(hero.hits).is_equal(0)
	assert_float(em.atk_t[i]).is_equal(4.5)
	hero.global_position = Vector3(0, 0, 3)
	_begin(em, i, 2)
	_fire(em, i)
	assert_int(hero.hits).is_equal(1)
	assert_int(hero.blasts).is_equal(1)


# ---------------------------------------------------------------- boss HP pegged to DPS

func test_the_hp_multiplier_follows_the_square_root_of_dps_inside_its_clamp() -> void:
	var cfg := {"enabled": true, "exponent": 0.5, "window": 45, "min": 0.75, "max": 3.0}
	assert_float(WaveTimeline.boss_hp_mult(cfg, 400.0, 400.0)).is_equal_approx(1.0, 0.0001)
	# twice the DPS: 1.41 the HP, the fight 29% shorter (1.41 / 2)
	assert_float(WaveTimeline.boss_hp_mult(cfg, 800.0, 400.0)).is_equal_approx(sqrt(2.0), 0.0001)
	assert_float(WaveTimeline.boss_hp_mult(cfg, 800.0, 400.0) / 2.0).is_equal_approx(0.7071, 0.0001)
	# the floor and the ceiling
	assert_float(WaveTimeline.boss_hp_mult(cfg, 100.0, 400.0)).is_equal_approx(0.75, 0.0001)
	assert_float(WaveTimeline.boss_hp_mult(cfg, 0.0, 400.0)).is_equal_approx(0.75, 0.0001)
	assert_float(WaveTimeline.boss_hp_mult(cfg, 40000.0, 400.0)).is_equal_approx(3.0, 0.0001)
	# off, no reference: 1
	assert_float(WaveTimeline.boss_hp_mult({"enabled": false, "exponent": 0.5}, 900.0, 400.0)).is_equal(1.0)
	assert_float(WaveTimeline.boss_hp_mult(cfg, 900.0, 0.0)).is_equal(1.0)
	# pass 72, lane INTEG: no block plays the game's defaults, on (a map saved without the block still pegs its bosses)
	assert_float(WaveTimeline.boss_hp_mult({}, 900.0, 400.0)).is_equal_approx(1.5, 0.0001)
	assert_bool(bool(WaveTimeline.BOSS_HP_SCALING_DEFAULTS["enabled"])).is_true()
	# the JSON reads as it is; a boss its ref_dps leaves out takes the measured default, 0 = never scaled
	var tl := JsonContent.timeline_from_dict({"boss_hp_scaling": {"enabled": true, "ref_dps": {"gila_grande": 900, "tumbleweed_king": 0}}})
	assert_float(tl.boss_ref_dps("gila_grande")).is_equal(900.0)
	assert_float(tl.boss_ref_dps("brander")).is_equal(20000.0)
	assert_float(tl.boss_ref_dps("tumbleweed_king")).is_equal(0.0)
	assert_float(tl.boss_ref_dps("nobody")).is_equal(0.0)
	assert_float(tl.boss_dps_window()).is_equal(45.0)
	assert_bool(JsonContent.timeline_from_dict({"boss_hp_scaling": 3}).boss_hp_scaling.is_empty()).is_true()


func test_recent_dps_counts_the_last_window_of_the_clock() -> void:
	Run.dps_reset()
	Run.elapsed = 100.0
	Run.add_damage("revolver", 500.0)
	Run.elapsed = 120.5
	Run.add_damage("revolver", 400.0)
	Run.elapsed = 130.0
	# both inside 45 s: 900 over 45
	assert_float(Run.recent_dps(45.0)).is_equal_approx(900.0 / 45.0, 0.001)
	# the first is 30 s back: outside a 15 s window
	assert_float(Run.recent_dps(15.0)).is_equal_approx(400.0 / 15.0, 0.001)
	# the boss fight's held time counts as clock too (buff_clock)
	Run.held_time = 100.0
	assert_float(Run.recent_dps(45.0)).is_equal(0.0)
	# the first seconds of a run are not a weak hero: 300 in 10 s is 30 a second
	Run.dps_reset()
	Run.held_time = 0.0
	Run.elapsed = 9.5
	Run.add_damage("revolver", 300.0)
	Run.elapsed = 10.0
	assert_float(Run.recent_dps(45.0)).is_equal_approx(30.0, 0.001)


func test_a_boss_spawns_with_hp_pegged_to_the_heros_dps() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	# (lane INTEG: the Brander's 0 = never scaled; a boss left out would take its measured default)
	# (pass 83, lane SCALE: the seconds mode is the game's default now; this test pins the pegged mode by name)
	tl.boss_hp_scaling = {"enabled": true, "mode": "dps", "exponent": 0.5, "window": 45, "min": 0.75, "max": 3.0, "ref_dps": {"gila_grande": 500, "brander": 0}}
	var w := _world(Vector3(0, 0, 30))
	var em: EnemyManager = w["em"]
	var dir := WaveDirector.new()
	dir.timeline = tl
	auto_free(dir)
	Run.stage = 1
	Run.elapsed = 850.0
	Run.dps_reset()
	# 2000 a second for the window: four times the reference, twice the HP
	for s in range(45):
		Run.elapsed = 805.0 + float(s)
		Run.add_damage("revolver", 2000.0)
	Run.elapsed = 850.0
	var m := dir.boss_dps_scale("gila_grande")
	assert_float(m).is_equal_approx(2.0, 0.02)
	assert_float(float(dir.last_boss_scale["dps"])).is_equal_approx(2000.0, 50.0)
	assert_float(float(dir.last_boss_scale["ref"])).is_equal(500.0)
	em.boss_hp_scale = m
	var i := em.spawn("gila_grande", Vector3(0, 0, 0))
	em.boss_hp_scale = 1.0
	var gila: EnemyDef = Registry.enemy("gila_grande")
	var plain: float = gila.hp * pow(float(gila.boss.get("hp_mult_per_stage", 1.6)), 1.0) * maxf(em.stage_mult, 1.0)
	assert_float(em.max_hp[i]).is_equal_approx(plain * m, 0.5)
	# a boss without a reference (0, or one neither the map nor the defaults name), the arena, scaling off: never scaled
	assert_float(dir.boss_dps_scale("brander")).is_equal(1.0)
	assert_float(dir.boss_dps_scale("nobody")).is_equal(1.0)
	Run.arena = true
	assert_float(dir.boss_dps_scale("gila_grande")).is_equal(1.0)
	Run.arena = false
	tl.boss_hp_scaling["enabled"] = false
	assert_float(dir.boss_dps_scale("gila_grande")).is_equal(1.0)
	# the next spawn is back at 1
	em.kill_all(false)
	var j := em.spawn("gila_grande", Vector3(5, 0, 0))
	assert_float(em.max_hp[j]).is_equal_approx(plain, 0.5)


func test_endless_grows_the_reference_with_the_boss() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	# (pass 83, lane SCALE: the pegged mode by name)
	tl.boss_hp_scaling = {"enabled": true, "mode": "dps", "exponent": 0.5, "window": 45, "min": 0.75, "max": 3.0, "ref_dps": {"tumbleweed_king": 300}}
	var dir := WaveDirector.new()
	dir.timeline = tl
	auto_free(dir)
	assert_int(dir.boss_stage_of("tumbleweed_king")).is_equal(0)
	assert_int(dir.boss_stage_of("gila_grande")).is_equal(1)
	assert_int(dir.boss_stage_of("nobody")).is_equal(-1)
	Run.dps_reset()
	Run.stage = 3
	Run.elapsed = 1400.0
	for s in range(45):
		Run.elapsed = 1355.0 + float(s)
		Run.add_damage("revolver", 3000.0)
	Run.elapsed = 1400.0
	dir.boss_dps_scale("tumbleweed_king")
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	var hpm := float(king.boss.get("hp_mult_per_stage", 1.6))
	var grow := pow(hpm, 3.0) * maxf(Run.stage_mult(), 1.0) / maxf(tl.stage_mult(0), 1.0)
	assert_float(float(dir.last_boss_scale["ref"])).is_equal_approx(300.0 * grow, 0.5)


func test_red_canyon_pegs_its_bosses_to_the_heros_dps() -> void:
	# read from the map file (Garry tunes it in the Level Editor): on, and a reference for every boss its timeline brings
	var f := FileAccess.open("res://content/maps/red_canyon/red_canyon.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	# (lane INTEG: a key the block leaves out, or the whole block, plays WaveTimeline's defaults: on, the measured refs)
	var bhs: Dictionary = d["timeline_data"].get("boss_hp_scaling", {})
	var dflt: Dictionary = WaveTimeline.BOSS_HP_SCALING_DEFAULTS
	assert_bool(bool(bhs.get("enabled", dflt["enabled"]))).is_true()
	assert_float(float(bhs.get("exponent", dflt["exponent"]))).is_between(0.0, 1.0)
	assert_float(float(bhs.get("min", dflt["min"]))).is_less_equal(1.0)
	assert_float(float(bhs.get("max", dflt["max"]))).is_greater_equal(1.0)
	var tl := JsonContent.timeline_from_dict(d["timeline_data"])
	for ev in d["timeline_data"]["events"]:
		if str(ev.get("type", "")) == "boss":
			assert_float(tl.boss_ref_dps(str(ev["enemy"]))).override_failure_message(str(ev["enemy"])).is_greater(0.0)
	# and the imported map plays the file's block
	assert_str(JSON.stringify(Registry.map("red_canyon").timeline.boss_hp_scaling, "", true)).is_equal(JSON.stringify(bhs, "", true))
