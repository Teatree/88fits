extends GdUnitTestSuite

## Pass 136, lane HOMING (Garry's answers on the weapons-aim proposal): under the aim (Settings.aim_mode, Aim.covers) the
## Rocket Pod's rockets lock only inside the +-45 degree fan ahead and go about 8 m down the facing with nothing there,
## each showing where it goes with a mark on the sand that goes when it blows; the Killer Bees fly to their own spots in a
## circle round him (deterministic: the aim dice) and dive on what is near, or fade there; the Big Mouth has no assist,
## pours down the facing and ramps its small ticks per creature; the Zap Beam and the Sun Scepter strike the sand with
## nobody round and every strike leaves a mark, capped; the switch off plays as before.

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
var bolts: Array = []
func toast(_t, _c = null) -> void:
	pass
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
func fx_lightning(pts) -> void:
	bolts.append(pts)
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	return null
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
var still := false
var fwd := Vector3.FORWARD
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return still
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
	return fwd
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func kick(_a = 0.0, _b = 0.0) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0
const PROBE_OUT := "res://../tools/dl/p136/HOMING/probe.json"

var _aim_was := true


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_aim_was = Settings.aim_mode
	Settings.aim_mode = true
	# pass 137 (lane AIM): these pin pass 136's rule (every aimed weapon hard); pass137_aim_test pins the soft one
	Aim.soft_rule = false
	Aim.reset()


func after_test() -> void:
	Settings.aim_mode = _aim_was
	Aim.soft_rule = true
	Run.debug_clear_items()
	Run.end()


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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "tg": tg}


## A tough creature standing where it was put (risen, on the screen), taking every hit whole.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	em.rise_t[i] = 1.0
	em.pos[i] = at
	if em.onscreen.size() > i:
		em.onscreen[i] = 1
	return i


func _inst(id: String, level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, inst: WeaponInstance) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


func _flat_angle(from: Vector3, dir: Vector3, to: Vector3) -> float:
	return rad_to_deg(Aim.angle_off(from, dir, to))


## Fires the pod once and ticks until its whole volley has left.
func _volley(pod: MissilePod) -> void:
	assert_bool(pod._fire()).is_true()
	for k in range(120):
		pod._tick(DT)
		if pod._queue.is_empty():
			break


# ---------------------------------------------------------------- Rocket Pod

func test_rockets_lock_only_inside_the_fan_ahead() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# one close at the side (60 degrees off the facing, outside +-45), one further ahead inside the fan
	var side := _creature(em, Vector3(4.3, 0, -2.5))
	var ahead := _creature(em, Vector3(1.5, 0, -8.0))
	em._rebuild_grid()
	var pod: MissilePod = _behaviour(w, MissilePod.new(), _inst("rocket_pod"))
	assert_str(pod.aim_mode()).is_equal("rockets")
	_volley(pod)
	assert_int(pod.flying().size()).is_greater(0)
	for r: Dictionary in pod.flying():
		var ex: Dictionary = r["ex"]
		assert_int(int(ex.get("target", -1))).is_equal(ahead)
		assert_int(int(ex.get("target", -1))).is_not_equal(side)
	assert_int(pod.locked_launched).is_equal(pod.flying().size())
	# the locked creature dies: the rocket picks again only inside the fan (the side one never), so it goes dry
	em.alive[ahead] = 0
	var pm: ProjectileManager = w["pm"]
	var r0: Dictionary = pod.flying()[0]
	var ex0: Dictionary = r0["ex"]
	ex0["age"] = 99.0
	pm._fly_missile(int(r0["i"]), DT, em, null)
	assert_int(int(ex0.get("target", -1))).is_equal(-1)
	assert_bool(bool(ex0.get("aim_dry", false))).is_true()


func test_rockets_with_nothing_ahead_fly_to_a_spot_about_8m_down_the_facing() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(-6, 0, 1))   # behind and to the side: not in the fan
	em._rebuild_grid()
	var pod: MissilePod = _behaviour(w, MissilePod.new(), _inst("rocket_pod"))
	_volley(pod)
	assert_int(pod.dry_launched).is_greater(0)
	for r: Dictionary in pod.flying():
		var ex: Dictionary = r["ex"]
		assert_bool(bool(ex.get("aim_dry", false))).is_true()
		var spot: Vector3 = ex["aim_spot"]
		var d := Vector2(spot.x, spot.z).length()
		assert_float(d).is_between(6.4, 9.6)
		assert_float(_flat_angle(Vector3.ZERO, Vector3.FORWARD, spot)).is_less_equal(12.5)
	# with no creature at all it still fires (R5)
	var w2 := _world()
	var pod2: MissilePod = _behaviour(w2, MissilePod.new(), _inst("rocket_pod"))
	assert_bool(pod2._fire()).is_true()


func test_each_rocket_shows_a_mark_that_follows_its_creature_and_goes_when_it_blows() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var tg: Telegraphs = w["tg"]
	var c := _creature(em, Vector3(0, 0, -7), 200.0)
	em._rebuild_grid()
	var pod: MissilePod = _behaviour(w, MissilePod.new(), _inst("rocket_pod"))
	_volley(pod)
	var n := pod.flying().size()
	assert_int(n).is_greater(0)
	var ids: Array = []
	for r: Dictionary in pod.flying():
		assert_int(int(r["ring"])).is_greater_equal(0)
		assert_int(int(r["dot"])).is_greater_equal(0)
		ids.append(int(r["ring"]))
		ids.append(int(r["dot"]))
	tg._advance(DT)
	assert_int(tg.live_count()).is_greater_equal(2 * n)
	# the creature steps aside: the marks follow it
	em.pos[c] = Vector3(1.0, 0, -7.5)
	em._rebuild_grid()
	for k in range(3):
		pm._physics_process(DT)
		pod._tick(DT)
	var r1: Dictionary = pod.flying()[0]
	var held: Dictionary = tg._held.get(int(r1["ring"]), {})
	assert_bool(held.is_empty()).is_false()
	assert_float((held["at"] as Vector3).x).is_equal_approx(1.0, 0.05)
	# fly them home: every mark goes as its rocket blows
	for k in range(600):
		pm._physics_process(DT)
		pod._tick(DT)
		if pod.flying().is_empty():
			break
	assert_int(pod.flying().size()).is_equal(0)
	for id: int in ids:
		assert_bool(tg._held.has(id)).is_false()


# ---------------------------------------------------------------- Killer Bees

func test_bee_spots_lie_in_their_circle_and_play_the_same_from_the_same_seed() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(5, 0, 3))
	em._rebuild_grid()
	var inst := _inst("hornet_nest")
	var pod: MissilePod = _behaviour(w, MissilePod.new(), inst)
	assert_str(pod.aim_mode()).is_equal("bees")
	var rng := inst.stat("range", 11.0)
	# a run's seed (with none every stream is random)
	Dice.reseed(136)
	Aim.reset()
	pod._add_spots(6)
	var first := pod.pending_spots()
	assert_int(first.size()).is_equal(6)
	for p: Vector3 in first:
		var d := Vector2(p.x, p.z).length()
		assert_float(d).is_between(2.5 - 0.01, rng + 0.01)
	# the same seed, the same spots (the aim dice)
	pod._spots.clear()
	Aim.reset()
	pod._add_spots(6)
	var again := pod.pending_spots()
	for k in range(6):
		assert_float((again[k] as Vector3).distance_to(first[k])).is_less(0.0001)
	# no mark, no aim shown: a bee volley lays nothing on the sand
	pod._spots.clear()
	_volley(pod)
	(w["tg"] as Telegraphs)._advance(DT)
	assert_int(pod.flying().size()).is_equal(0)
	Dice.reseed(0)


func test_a_bee_dives_on_what_is_near_its_spot_or_fades_there() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var c := _creature(em, Vector3(6, 0, 0), 100.0)
	em._rebuild_grid()
	var inst := _inst("hornet_nest")
	var pod: MissilePod = _behaviour(w, MissilePod.new(), inst)
	# a bee to a spot next to the creature: it takes the creature
	pod._spots = [Vector3(5.5, 0, 0.5)]
	pod._queue = [0]
	pod._launch_one()
	var bi := -1
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1 and pm.extra[i] is Dictionary and (pm.extra[i] as Dictionary).has("bee_spot"):
			bi = i
	assert_int(bi).is_greater_equal(0)
	(pm.extra[bi] as Dictionary)["age"] = 99.0
	pm._fly_missile(bi, DT, em, null)
	assert_int(int((pm.extra[bi] as Dictionary).get("target", -1))).is_equal(c)
	# a bee to an empty spot: it gets there and fades
	pod._spots = [Vector3(-4, 0, -4)]
	pod._queue = [0]
	var faded0 := pm.bees_faded
	pod._launch_one()
	for k in range(600):
		pm._physics_process(DT)
		if pm.bees_faded > faded0:
			break
	assert_int(pm.bees_faded).is_greater(faded0)


# ---------------------------------------------------------------- Big Mouth

func _pour(lb: LaserBeam, secs: float) -> void:
	var n := int(secs / DT)
	for k in range(n):
		lb.cooldown_left -= DT
		lb._tick(DT)
		if lb.cooldown_left <= 0.0:
			if lb._fire():
				lb.cooldown_left = 99.0
			else:
				lb.cooldown_left = 0.15


func test_the_big_mouth_has_no_assist_and_pours_down_the_facing() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# a creature 20 degrees off the facing, inside the 50 degree cone: it pours, and down the facing, not at it
	var c := _creature(em, Vector3(sin(deg_to_rad(20.0)) * 7.0, 0, -cos(deg_to_rad(20.0)) * 7.0), 100.0)
	em._rebuild_grid()
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst("big_mouth"))
	lb._yaw0 = 0.0
	lb.cooldown_left = 0.0
	_pour(lb, 0.6)
	assert_int(lb.beams).is_equal(1)
	# its line runs through the spot `converge` m down the facing (the mouth floats beside him), never at the creature
	var goal := Vector3.FORWARD * float(Aim.cfg(lb.inst).get("converge", 6.0))
	var m := lb.muzzle()
	var to := Vector3(goal.x - m.x, 0, goal.z - m.z).normalized()
	assert_float(rad_to_deg(to.angle_to(lb._dir()))).is_less(1.5)
	var at_c := Vector3(em.pos[c].x - m.x, 0, em.pos[c].z - m.z).normalized()
	assert_float(rad_to_deg(at_c.angle_to(lb._dir()))).is_greater(5.0)


func test_the_big_mouth_waits_half_a_second_for_its_cone_then_pours_anyway() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(7, 0, 0), 100.0)   # 90 degrees off: outside the cone
	em._rebuild_grid()
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst("big_mouth"))
	lb.cooldown_left = 0.0
	_pour(lb, 0.3)
	assert_int(lb.beams).is_equal(0)
	assert_float(lb._windup_t).is_equal(0.0)
	_pour(lb, 0.6)
	assert_bool(lb.beams == 1 or lb._windup_t > 0.0).is_true()


func test_the_big_mouth_turns_after_the_facing_at_most_180_degrees_a_second() -> void:
	var w := _world()
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst("big_mouth"))
	lb._yaw0 = 0.0
	(w["hero"] as Node3D).set("fwd", Vector3.BACK)
	lb._tick_aim(0.25)
	assert_float(rad_to_deg(absf(lb._yaw0))).is_equal_approx(45.0, 0.5)


func test_the_big_mouth_ramps_its_ticks_per_creature() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var c := _creature(em, Vector3(0, 0, -6), 100.0)
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst("big_mouth"))
	var cfg := Aim.cfg(lb.inst)
	var tick := float(cfg["tick"])
	var first := lb.ramp_of(c, tick)
	assert_float(first).is_equal_approx(float(cfg["ramp_start"]), 0.001)
	var share := first
	var steps := int(ceil(float(cfg["ramp_seconds"]) / tick)) + 1
	for k in range(steps):
		lb._pour_clock += tick
		share = lb.ramp_of(c, tick)
	assert_float(share).is_equal_approx(float(cfg["ramp_full"]), 0.001)
	# out of the beam a while: the ramp falls back
	lb._pour_clock += 2.0
	assert_float(lb.ramp_of(c, tick)).is_less(float(cfg["ramp_full"]) * 0.6)


## The probe the brief asks for (BALANCING 77.AIM.BEAM): the damage a pour at level 1 deals (a) to a tough creature held
## in the beam, (b) to a row of fodder the beam is swept across, (c) to a file of fodder down the line, old rule against
## new; written to tools/dl/p136/HOMING/probe.json. (a) must stay within 15% of the old.
func test_probe_big_mouth_old_against_new() -> void:
	var out := {}
	for mode: String in ["old", "new"]:
		Settings.aim_mode = mode == "new"
		Aim.reset()
		out[mode] = {"held": _probe_held(), "swept": _probe_swept(), "file": _probe_file()}
	Settings.aim_mode = true
	var f := FileAccess.open(ProjectSettings.globalize_path(PROBE_OUT), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	var a_old := float(out["old"]["held"])
	var a_new := float(out["new"]["held"])
	assert_float(a_old).is_greater(0.0)
	assert_float(a_new / a_old).is_between(0.85, 1.15)


func _probe_beam(w: Dictionary) -> LaserBeam:
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst("big_mouth"))
	lb._yaw0 = 0.0
	lb._aim_yaw = 0.0
	lb.cooldown_left = 0.0
	return lb


func _probe_held() -> float:
	var w := _world()
	var em: EnemyManager = w["em"]
	var c := _creature(em, Vector3(0, 0, -6), 2000.0)
	em._rebuild_grid()
	var hp0: float = em.hp[c]
	var lb := _probe_beam(w)
	_pour(lb, 2.5)
	return hp0 - em.hp[c]


func _probe_swept() -> Array:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ids: Array = []
	for k in range(7):
		var a := deg_to_rad(-60.0 + 20.0 * float(k))
		ids.append(_creature(em, Vector3(sin(a) * 8.0, 0, -cos(a) * 8.0), 2000.0))
	em._rebuild_grid()
	var hp0: Array = []
	for i: int in ids:
		hp0.append(em.hp[i])
	var lb := _probe_beam(w)
	var hero: Node3D = w["hero"]
	# the facing swings from -60 to +60 degrees over the pour (60 degrees a second), the old beam locks as it always did
	var n := int(2.5 / DT)
	for k in range(n):
		var a := deg_to_rad(-60.0 + 120.0 * clampf(float(k) * DT / 2.0, 0.0, 1.0))
		hero.set("fwd", Vector3(sin(a), 0, -cos(a)))
		lb.cooldown_left -= DT
		lb._tick(DT)
		if lb.cooldown_left <= 0.0:
			lb.cooldown_left = 99.0 if lb._fire() else 0.15
	var dealt: Array = []
	for j in range(ids.size()):
		dealt.append(snappedf(float(hp0[j]) - em.hp[int(ids[j])], 0.1))
	return dealt


func _probe_file() -> Array:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ids: Array = []
	for k in range(5):
		ids.append(_creature(em, Vector3(0.0, 0, -3.0 - 2.0 * float(k)), 2000.0))
	em._rebuild_grid()
	var hp0: Array = []
	for i: int in ids:
		hp0.append(em.hp[i])
	var lb := _probe_beam(w)
	_pour(lb, 2.5)
	var dealt: Array = []
	for j in range(ids.size()):
		dealt.append(snappedf(float(hp0[j]) - em.hp[int(ids[j])], 0.1))
	return dealt


# ---------------------------------------------------------------- Zap Beam, Sun Scepter

func test_the_zap_strikes_the_sand_with_nobody_round_and_every_strike_leaves_a_mark() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var zap: Beam = _behaviour(w, Beam.new(), _inst("zap_beam"))
	assert_bool(zap._fire()).is_true()
	assert_int(zap.dry_bolts).is_equal(1)
	var sm := StrikeMarks.of(w["g"])
	assert_object(sm).is_not_null()
	assert_int(sm.count("zap")).is_equal(1)
	var bolt: Array = (w["g"] as Node).get("bolts")[0]
	var at: Vector3 = bolt[bolt.size() - 1]
	assert_float(Vector2(at.x, at.z).length()).is_between(2.0 - 0.01, zap.stat("range", 9.0) + 0.01)
	# a creature in range: it is struck, and its spot burnt
	var c := _creature(em, Vector3(3, 0, 2), 100.0)
	em._rebuild_grid()
	var hp0: float = em.hp[c]
	assert_bool(zap._fire()).is_true()
	assert_float(em.hp[c]).is_less(hp0)
	assert_int(sm.count("zap")).is_equal(2)
	# the marks cool and go
	for k in range(int((StrikeMarks.ZAP_HOLD + StrikeMarks.ZAP_FADE) / 0.1) + 2):
		sm._process(0.1)
	assert_int(sm.count()).is_equal(0)


func test_the_sun_strikes_the_sand_with_nobody_round_and_burns_a_ring() -> void:
	var w := _world()
	var sun: SunScepter = _behaviour(w, SunScepter.new(), _inst("sun_scepter"))
	assert_bool(sun._fire()).is_true()
	assert_int(sun.dry_strikes).is_equal(1)
	for k in range(60):
		sun._tick(DT)
	var sm := StrikeMarks.of(w["g"])
	assert_object(sm).is_not_null()
	assert_int(sm.count("sun")).is_equal(maxi(sun.stat_int("amount", 1), 1))


func test_the_marks_are_capped() -> void:
	var w := _world()
	for k in range(StrikeMarks.CAP + 15):
		StrikeMarks.zap(w["g"], Vector3(float(k) * 0.3, 0, 0))
		StrikeMarks.sun(w["g"], Vector3(float(k) * 0.3, 0, 3), 1.3)
	var sm := StrikeMarks.of(w["g"])
	assert_int(sm.count("zap")).is_equal(StrikeMarks.CAP)
	assert_int(sm.count("sun")).is_equal(StrikeMarks.CAP)
	var tg: Telegraphs = w["tg"]
	tg._advance(DT)
	# two held marks a burn at most (the glow and the burn)
	assert_int(tg.live_count()).is_less_equal(4 * StrikeMarks.CAP)


# ---------------------------------------------------------------- the switch off

func test_with_the_switch_off_they_aim_as_before() -> void:
	Settings.aim_mode = false
	var w := _world()
	var pod: MissilePod = _behaviour(w, MissilePod.new(), _inst("rocket_pod"))
	assert_str(pod.aim_mode()).is_equal("")
	assert_bool(pod._fire()).is_false()
	var bees: MissilePod = _behaviour(w, MissilePod.new(), _inst("hornet_nest"))
	assert_bool(bees._fire()).is_false()
	var zap: Beam = _behaviour(w, Beam.new(), _inst("zap_beam"))
	assert_bool(zap._fire()).is_false()
	var lb: LaserBeam = _behaviour(w, LaserBeam.new(), _inst("big_mouth"))
	assert_bool(lb._fire()).is_false()
	var sun: SunScepter = _behaviour(w, SunScepter.new(), _inst("sun_scepter"))
	assert_bool(sun._fire()).is_false()
	assert_object(StrikeMarks.of(w["g"])).is_null()
	# a creature ahead: the pod's rockets carry no aim (the old flight) and lay no marks
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(6, 0, 0), 100.0)
	em._rebuild_grid()
	_volley(pod)
	assert_int(pod.flying().size()).is_equal(0)
	var pm: ProjectileManager = w["pm"]
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1 and pm.extra[i] is Dictionary:
			assert_bool((pm.extra[i] as Dictionary).has("aim_spot")).is_false()
