extends GdUnitTestSuite

## Pass 137, lane AIM: Aiming-Hard and Aiming-Soft (core/systems/Aim.gd; Garry 2026-11-09: the Laser and the Dragon's
## Breath "very much shoot where Player is facing"; every other aimed weapon "will actually shoot behind the Player in
## cases when the enemy is obviously much closer ... much 'weaker' than the not aiming version", and with nothing else
## "at certain close enough distance the weapon does still shoot the only enemy"; the melee weapons soft too). The feels in
## the JSON, a near threat behind taken over a far one in the cone (not one merely a little closer), the lone creature
## within reach (not one far off), melee striking right behind, the Gravity Gun and the rockets, no dice drawn, and the
## switches: Aim.soft_rule off = pass 136's rule, Settings.aim_mode off = the old auto-aim.

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
var sands := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_at, _col, _size) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	sands += 1
func fx_poison(_a) -> void:
	pass
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func ball_caught(_w, _ex) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var cinematic := false
var facing := 0.0
var velocity := Vector3.ZERO
var hip: Node3D = null
var max_hp := 100.0
signal hit
func is_still() -> bool:
	return false
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	var dd := Vector3(d.x, 0, d.z)
	if dd.length_squared() < 0.0001:
		dd = forward()
	return global_position + Vector3(0, 0.8, 0) + dd.normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0
const HARD := ["big_mouth", "loudmouth", "dragons_breath", "fire_eater"]
## creatures stand with this body radius, so a distance below is the body's distance plus BODY_R
const BODY_R := 0.4

var _keep_aim := true
var _keep_ff := false
var _keep_soft := true


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_keep_aim = Settings.aim_mode
	_keep_ff = Settings.fire_forward
	_keep_soft = Aim.soft_rule
	Settings.aim_mode = true
	Settings.fire_forward = false
	Aim.soft_rule = true
	Aim.reset()


func after_test() -> void:
	Settings.aim_mode = _keep_aim
	Settings.fire_forward = _keep_ff
	Aim.soft_rule = _keep_soft
	Aim.reset()
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin facing -Z, with the real crowd, shots and effects.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	var hip := Node3D.new()
	hero.add_child(hip)
	hip.position = Vector3(0.55, 0.7, 0)
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
	em.screen_filter_on = false
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
	var def: WeaponDef = Registry.weapon(id)
	assert_object(def).override_failure_message("no weapon " + id).is_not_null()
	var inst := WeaponInstance.new(def, level)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, inst: WeaponInstance) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## A tough, risen, still creature at `at` with a body of radius BODY_R.
func _creature(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em.radius[i] = BODY_R
	em._rebuild_grid()
	return i


## A flat point `d` metres out at `deg` degrees off -Z (positive to the right, +X).
static func _at(d: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(sin(a) * d, 0.0, -cos(a) * d)


## The angle (degrees) between flat directions.
static func _deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))))


# ---------------------------------------------------------------- the feels in the data

func test_every_aimed_and_melee_weapon_has_its_feel() -> void:
	var seen := 0
	for def: WeaponDef in Registry.weapons.values():
		var a = def.params.get("aim")
		if not (a is Dictionary):
			continue
		var fam := str((a as Dictionary).get("family", "aimed"))
		var inst := WeaponInstance.new(def, 1)
		var c := Aim.cfg(inst)
		if fam == "aimed" or fam == "melee":
			seen += 1
			var want := "hard" if HARD.has(def.id) else "soft"
			assert_str(str((a as Dictionary).get("feel", ""))).override_failure_message(def.id + "'s JSON feel").is_equal(want)
			assert_str(str(c["feel"])).is_equal(want)
			assert_float(float(c["threat_reach"])).is_greater(0.0)
			assert_float(float(c["lone_reach"])).is_greater(float(c["threat_reach"]))
		else:
			assert_bool(c.has("feel")).override_failure_message(def.id + " (placed / around) has no feel").is_false()
	assert_int(seen).is_greater_equal(20)
	# a soft block without the numbers takes Aim's defaults
	var d := WeaponDef.new()
	d.id = "probe"
	d.params = {"aim": {"cone": 60}}
	var c2 := Aim.cfg(WeaponInstance.new(d, 1))
	assert_str(str(c2["feel"])).is_equal("soft")
	assert_float(float(c2["threat_reach"])).is_equal(Aim.THREAT_REACH)
	assert_float(float(c2["threat_ratio"])).is_equal(Aim.THREAT_RATIO)
	assert_float(float(c2["lone_reach"])).is_equal(Aim.LONE_REACH)


# ---------------------------------------------------------------- hard: where he faces

func test_a_hard_weapon_never_turns_to_a_creature_behind() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var behind := _creature(em, _at(1.5, 180.0))
	for id: String in HARD:
		var inst := _inst(id)
		assert_bool(Aim.covers(inst)).is_true()
		assert_bool(Aim.soft(inst)).override_failure_message(id + " is hard").is_false()
		var sh := Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)
		assert_int(int(sh["target"])).is_equal(-1)
		assert_vector(sh["dir"]).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)
	# the Big Mouth: its mouth keeps looking down the facing with the creature behind, waits, then pours ahead
	var mouth := _behaviour(w, LaserBeam.new(), _inst("big_mouth")) as LaserBeam
	for k in range(90):
		mouth._tick_aim(DT)
	assert_float(rad_to_deg(absf(wrapf(mouth._yaw0 - 0.0, -PI, PI)))).is_less(0.5)
	assert_int(behind).is_greater_equal(0)


# ---------------------------------------------------------------- soft: a near threat behind

func test_a_soft_weapon_takes_a_near_threat_behind_over_a_far_one_in_the_cone() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ahead := _creature(em, _at(10.0, 0.0))
	var behind := _creature(em, _at(2.0, 180.0))
	var inst := _inst("revolver")
	assert_bool(Aim.soft(inst)).is_true()
	var sh := Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)
	assert_int(int(sh["target"])).is_equal(behind)
	assert_str(str(sh["soft"])).is_equal("threat")
	# turned all the way round (no assist limit)
	assert_float(_deg(sh["dir"], Vector3(0, 0, 1))).is_less(0.01)
	assert_int(ahead).is_not_equal(behind)


func test_but_not_one_merely_a_little_closer() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ahead := _creature(em, _at(7.0, 0.0))
	_creature(em, _at(6.0, 180.0))
	var inst := _inst("revolver")
	var sh := Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)
	assert_int(int(sh["target"])).is_equal(ahead)
	assert_str(str(sh["soft"])).is_equal("")
	# within threat_reach but not much closer than the cone's pick (2.5 m behind against 4 m ahead: 2.1 > 0.45 x 3.6)
	var w2 := _world()
	var em2: EnemyManager = w2["em"]
	var ahead2 := _creature(em2, _at(4.0, 0.0))
	_creature(em2, _at(2.5, 180.0))
	assert_int(int(Aim.shot(inst, em2, w2["hero"], Vector3.ZERO, 14.0)["target"])).is_equal(ahead2)
	# a threat to the side counts like one behind
	var w3 := _world()
	var em3: EnemyManager = w3["em"]
	_creature(em3, _at(9.0, 5.0))
	var side := _creature(em3, _at(1.5, 80.0))
	assert_int(int(Aim.shot(inst, em3, w3["hero"], Vector3.ZERO, 14.0)["target"])).is_equal(side)


# ---------------------------------------------------------------- soft: the lone creature

func test_the_lone_creature_within_reach_is_shot_one_far_off_is_not() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var lone := _creature(em, _at(5.0, 180.0))
	var inst := _inst("revolver")
	var sh := Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)
	assert_int(int(sh["target"])).is_equal(lone)
	assert_str(str(sh["soft"])).is_equal("lone")
	assert_float(_deg(sh["dir"], Vector3(0, 0, 1))).is_less(0.01)
	var w2 := _world()
	var em2: EnemyManager = w2["em"]
	_creature(em2, _at(12.0, 180.0))
	var sh2 := Aim.shot(inst, em2, w2["hero"], Vector3.ZERO, 14.0)
	assert_int(int(sh2["target"])).is_equal(-1)
	assert_vector(sh2["dir"]).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)
	# a creature in the cone, however far, stops the lone rule: 5 m behind against 11 m ahead is not taken
	var w3 := _world()
	var em3: EnemyManager = w3["em"]
	var far_ahead := _creature(em3, _at(11.0, 0.0))
	_creature(em3, _at(5.0, 180.0))
	assert_int(int(Aim.shot(inst, em3, w3["hero"], Vector3.ZERO, 14.0)["target"])).is_equal(far_ahead)


func test_the_numbers_come_from_the_weapon() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var lone := _creature(em, _at(5.0, 180.0))
	var inst := _inst("revolver")
	var a: Dictionary = (inst.params["aim"] as Dictionary).duplicate()
	a["lone_reach"] = 3.0
	inst.params["aim"] = a
	assert_int(int(Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)["target"])).is_equal(-1)
	a["lone_reach"] = 6.0
	a["feel"] = "hard"
	assert_int(int(Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)["target"])).is_equal(-1)
	a["feel"] = "soft"
	assert_int(int(Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)["target"])).is_equal(lone)


func test_the_gun_fires_behind_and_counts_it() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var back := _creature(em, _at(2.0, 180.0))
	var gun := _behaviour(w, ProjectileEmitter.new(), _inst("revolver")) as ProjectileEmitter
	assert_bool(gun._fire()).is_true()
	assert_int(gun._aim_target).is_equal(back)
	# the round leaves the floating gun towards him: behind the Outlaw (the gun hangs at his side, so not exactly +Z)
	assert_float(gun._aim_dir.z).is_greater(0.75)
	assert_int(gun.dry_pulls).is_equal(0)
	# within threat_reach with the cone empty it counts as a threat; a lone one stands between threat_reach and lone_reach
	var counts := Aim.soft_counts()
	assert_int(int((counts.get("revolver", {}) as Dictionary).get("threat", 0))).is_equal(1)
	var w2 := _world()
	_creature(w2["em"], _at(5.0, 180.0))
	var gun2 := _behaviour(w2, ProjectileEmitter.new(), _inst("revolver")) as ProjectileEmitter
	assert_bool(gun2._fire()).is_true()
	assert_int(int((Aim.soft_counts().get("revolver", {}) as Dictionary).get("lone", 0))).is_equal(1)


# ---------------------------------------------------------------- melee, the Gravity Gun, the rockets

func test_melee_strikes_a_creature_right_behind() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var back := _creature(em, _at(1.2, 180.0))
	var hb := em.hp[back]
	var b := _behaviour(w, Thruster.new(), _inst("sabre")) as Thruster
	assert_bool(b._fire()).is_true()
	assert_int(b.target).is_equal(back)
	assert_float(_deg(b._dir, Vector3(0, 0, 1))).is_less(0.5)
	for k in range(30):
		b._tick(DT)
	assert_float(em.hp[back]).is_less(hb)
	# the Spear too
	var p := _behaviour(w, Thruster.new(), _inst("pike")) as Thruster
	p._fire()
	assert_int(p.target).is_equal(back)


func test_the_gravity_gun_grabs_a_near_threat_behind() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var back := _creature(em, _at(2.0, 170.0))
	var gun := _behaviour(w, GravityGun.new(), _inst("gravity_gun")) as GravityGun
	assert_bool(gun._fire()).is_true()
	assert_int(gun._grips.size()).is_equal(1)
	assert_int(int(gun._grips[0]["i"])).is_equal(back)
	assert_int(gun.dry_shots).is_equal(0)


func test_a_rocket_takes_a_near_threat_behind() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ahead := _creature(em, _at(10.0, 0.0))
	var back := _creature(em, _at(2.0, 180.0))
	var pod := _behaviour(w, MissilePod.new(), _inst("rocket_pod")) as MissilePod
	assert_bool(pod._fire()).is_true()
	for k in range(120):
		pod._tick(DT)
		if pod._queue.is_empty():
			break
	var targets: Array = []
	for r: Dictionary in pod.flying():
		targets.append(int((r["ex"] as Dictionary).get("target", -1)))
	assert_int(targets.size()).is_greater(0)
	# the first rocket takes the threat; the volley's next ones the fan's pick (the threat is another rocket's)
	assert_int(int(targets[0])).is_equal(back)
	for k in range(1, targets.size()):
		assert_int(int(targets[k])).is_equal(ahead)


# ---------------------------------------------------------------- no dice, and the switches

func test_the_soft_rule_draws_no_dice() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, _at(2.0, 180.0))
	_creature(em, _at(8.0, 10.0))
	var inst := _inst("revolver")
	var g := Aim.dice()
	var st := g.state
	for k in range(20):
		Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)
	assert_int(Aim.dice().state).is_equal(st)


func test_soft_rule_off_plays_pass_136_and_the_switch_off_the_old_aim() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var behind := _creature(em, _at(2.0, 180.0))
	var inst := _inst("revolver")
	Aim.soft_rule = false
	assert_bool(Aim.soft(inst)).is_false()
	var sh := Aim.shot(inst, em, w["hero"], Vector3.ZERO, 14.0)
	assert_int(int(sh["target"])).is_equal(-1)
	Aim.soft_rule = true
	# the switch off: no aim rule at all, the gun takes the nearest as before pass 136
	Settings.aim_mode = false
	assert_bool(Aim.covers(inst)).is_false()
	assert_bool(Aim.soft(inst)).is_false()
	var gun := _behaviour(w, ProjectileEmitter.new(), inst) as ProjectileEmitter
	assert_bool(gun._fire()).is_true()
	# it turns round to him (from the floating gun at his side, so a little off +Z)
	assert_float(gun._aim_dir.z).is_greater(0.8)
	assert_bool(Aim.soft_counts().is_empty()).is_true()
	assert_int(behind).is_greater_equal(0)
