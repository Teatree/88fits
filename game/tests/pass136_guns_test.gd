extends GdUnitTestSuite

## Pass 136, lane GUNS: "Aim where you face" (core/systems/Aim.gd; Garry's answers on docs/weapons_aim, 2026-11-08). The
## score's worked example (R4), nothing behind him, the priority creature inside ±45°, the assist's clamp, the placed
## weapons' circle (R6: in its ring, apart, the same for the same seed), the switch off = the old aim, R1's turn on the spot,
## the aimed Basketball's dry throw that falls and bounces instead of coming home, the Gravity Gun firing at the sand with
## nobody near, the aim wedge (R7) and the run record's switches.

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
var catches := 0
var last_catch := {}
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
func ball_caught(_w, ex) -> void:
	catches += 1
	last_catch = ex
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

const HOLDER := """extends Node3D
var map = null
"""

const FLAT_MAP := """extends Node
func in_water(_p: Vector3) -> bool:
	return false
func height_at(_x: float, _z: float) -> float:
	return 0.0
"""

const DT := 1.0 / 60.0

var _keep_aim := true
var _keep_show := true
var _keep_ff := false


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	_keep_aim = Settings.aim_mode
	_keep_show = Settings.show_aim
	_keep_ff = Settings.fire_forward
	Settings.aim_mode = true
	Settings.show_aim = true
	Settings.fire_forward = false
	Aim.reset()
	Run.heat = 0


func after_test() -> void:
	Settings.aim_mode = _keep_aim
	Settings.show_aim = _keep_show
	Settings.fire_forward = _keep_ff
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "tg": tg}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, inst: WeaponInstance) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## A tough, risen creature at `at` (`r` its body's radius when >= 0).
func _creature(em: EnemyManager, at: Vector3, r := -1.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	if r >= 0.0:
		em.radius[i] = r
	em._rebuild_grid()
	return i


## A flat point `d` metres out at `deg` degrees off -Z (positive to the right, +X).
static func _at(d: float, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return Vector3(sin(a) * d, 0.0, -cos(a) * d)


func _first_alive(pm: ProjectileManager) -> int:
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1:
			return j
	return -1


# ---------------------------------------------------------------- R4: the score

func test_the_score_matches_the_worked_example() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ahead := _creature(em, _at(6.0, 0.0), 0.0)
	var off := _creature(em, _at(3.0, 25.0), 0.0)
	var f := Vector3(0, 0, -1)
	assert_float(Aim.cone_score(em, ahead, Vector3.ZERO, f, 60.0)).is_equal_approx(6.0, 0.01)
	assert_float(Aim.cone_score(em, off, Vector3.ZERO, f, 60.0)).is_equal_approx(7.17, 0.05)
	# the one straight ahead wins although it is twice as far
	assert_int(Aim.pick(em, Vector3.ZERO, f, 14.0, 60.0)).is_equal(ahead)
	var best := _creature(em, _at(3.4, -12.0), 0.0)
	assert_float(Aim.cone_score(em, best, Vector3.ZERO, f, 60.0)).is_equal_approx(4.49, 0.05)
	assert_int(Aim.pick(em, Vector3.ZERO, f, 14.0, 60.0)).is_equal(best)


func test_a_creature_behind_or_outside_the_cone_is_never_picked() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var f := Vector3(0, 0, -1)
	var behind := _creature(em, _at(2.0, 180.0))
	var side := _creature(em, _at(2.0, 70.0))
	assert_float(Aim.cone_score(em, behind, Vector3.ZERO, f, 60.0)).is_equal(INF)
	assert_int(Aim.pick(em, Vector3.ZERO, f, 14.0, 60.0)).is_equal(-1)
	# the shot then goes straight down the facing
	var sh := Aim.shot(_inst("revolver"), em, w["hero"], Vector3.ZERO, 14.0)
	assert_int(int(sh["target"])).is_equal(-1)
	assert_vector(sh["dir"]).is_equal_approx(f, Vector3.ONE * 0.001)
	assert_int(side).is_not_equal(behind)


func test_a_priority_creature_is_taken_first_only_within_45_degrees() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var f := Vector3(0, 0, -1)
	_creature(em, _at(2.0, 0.0), 0.0)
	var elite := _creature(em, _at(6.0, 40.0), 0.0)
	em.elite_idx[elite] = 0
	em._rebuild_grid()
	assert_bool(em.is_priority(elite)).is_true()
	# at 40 degrees (inside 1.5 x the 30 degree half cone) it wins over the plain one straight ahead
	assert_int(Aim.pick(em, Vector3.ZERO, f, 14.0, 60.0)).is_equal(elite)
	# the shot may turn to it by up to its own 45 degrees
	var sh := Aim.shot(_inst("revolver"), em, w["hero"], Vector3.ZERO, 14.0)
	assert_int(int(sh["target"])).is_equal(elite)
	assert_float(rad_to_deg(f.angle_to(sh["dir"]))).is_equal_approx(40.0, 0.5)
	# at 60 degrees it waits until he turns: the plain one ahead is taken
	em.pos[elite] = _at(6.0, 60.0)
	em._rebuild_grid()
	assert_int(Aim.pick(em, Vector3.ZERO, f, 14.0, 60.0)).is_not_equal(elite)


func test_the_assist_never_turns_more_than_its_limit() -> void:
	var f := Vector3(0, 0, -1)
	var d := Aim.assist(Vector3.ZERO, f, _at(5.0, 50.0), 30.0)
	assert_float(rad_to_deg(f.angle_to(d))).is_equal_approx(30.0, 0.01)
	# turned towards the target's side
	assert_float(d.x).is_greater(0.0)
	var d2 := Aim.assist(Vector3.ZERO, f, _at(5.0, -10.0), 30.0)
	assert_float(rad_to_deg(f.angle_to(d2))).is_equal_approx(10.0, 0.01)
	assert_float(d2.x).is_less(0.0)


# ---------------------------------------------------------------- R6: the circle

func test_circle_spots_stay_in_their_ring_keep_apart_and_repeat_for_the_same_seed() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Dice.reseed(4242)
	Aim.reset()
	var a := Aim.circle_spots(em, Vector3(3, 0, 1), 2.0, 10.0, 4, 1.5)
	assert_int(a.size()).is_equal(4)
	for p: Vector3 in a:
		var r := Vector2(p.x - 3.0, p.z - 1.0).length()
		assert_float(r).is_between(2.0 - 0.001, 10.0 + 0.001)
	for i in a.size():
		for j in range(i + 1, a.size()):
			assert_float(Vector2(a[i].x - a[j].x, a[i].z - a[j].z).length()).is_greater_equal(1.5 * Aim.APART - 0.001)
	Dice.reseed(4242)
	Aim.reset()
	var b := Aim.circle_spots(em, Vector3(3, 0, 1), 2.0, 10.0, 4, 1.5)
	assert_array(b).is_equal(a)
	# a crowd pulls the spots to it far more often than chance (a ring 2-5 m: the pack's 3 m round it is a fifth of it)
	for k in range(8):
		_creature(em, Vector3(3.5 + float(k % 3) * 0.3, 0, float(k / 3) * 0.3))
	Dice.reseed(77)
	Aim.reset()
	var near := 0
	for t in range(40):
		var s := Aim.circle_spots(em, Vector3.ZERO, 2.0, 5.0, 1, 1.5)
		if Vector2(s[0].x - 3.8, s[0].z - 0.3).length() < 2.0:
			near += 1
	assert_int(near).is_greater(12)


# ---------------------------------------------------------------- the switch, the guns

func test_the_switch_off_plays_the_old_aim() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var gun := _behaviour(w, ProjectileEmitter.new(), _inst("revolver")) as ProjectileEmitter
	_creature(em, _at(4.0, 180.0))
	Settings.aim_mode = false
	assert_bool(Aim.covers(gun.inst)).is_false()
	assert_bool(gun._fire()).is_true()
	# the old aim turns round to the creature behind him (from the companion's mouth, a little off the hero's line)
	assert_float(gun._aim_dir.z).is_greater(0.8)
	assert_int(gun.dry_pulls).is_equal(0)
	pm.clear_all()
	gun._burst.clear()
	# the switch on: down the facing, a dry pull counted
	Settings.aim_mode = true
	assert_bool(Aim.covers(gun.inst)).is_true()
	assert_bool(gun._fire()).is_true()
	assert_vector(gun._aim_dir).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.01)
	assert_int(gun.dry_pulls).is_equal(1)
	assert_int(int(Aim.dry_counts().get("revolver", 0))).is_equal(1)


func test_the_boomstick_fires_dry_and_turns_only_15_degrees() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var gun := _behaviour(w, ProjectileEmitter.new(), _inst("boomstick")) as ProjectileEmitter
	# nobody in reach: it fires anyway (pass 53's rule gave way to R5), quieter
	assert_bool(gun._fire()).is_true()
	assert_int(gun.dry_pulls).is_equal(1)
	assert_float(float(Aim.cfg(gun.inst)["dry_db"])).is_less(0.0)
	# a creature 25 degrees off within its reach: the blast turns 15 degrees, no more
	_creature(em, _at(3.0, 25.0))
	assert_bool(gun._fire()).is_true()
	assert_float(rad_to_deg(Vector3(0, 0, -1).angle_to(gun._aim_dir))).is_equal_approx(15.0, 0.1)


func test_trigger_happy_sways_on_its_own() -> void:
	var w := _world()
	var gun := _behaviour(w, ProjectileEmitter.new(), _inst("tommy_gun", ["trigger_happy"])) as ProjectileEmitter
	assert_float(float(gun.inst.params.get("stream_sway_deg", 0.0))).is_equal(12.0)
	var lo := 0.0
	var hi := 0.0
	for k in range(90):
		gun._sway_t = float(k) * 0.02
		var s := rad_to_deg(gun._sway())
		lo = minf(lo, s)
		hi = maxf(hi, s)
	assert_float(hi).is_equal_approx(12.0, 0.2)
	assert_float(lo).is_equal_approx(-12.0, 0.2)
	# the plain Tommy Gun does not sway
	var plain := _behaviour(w, ProjectileEmitter.new(), _inst("tommy_gun")) as ProjectileEmitter
	plain._sway_t = 0.35
	assert_float(plain._sway()).is_equal(0.0)


func test_the_basketball_dry_throw_falls_bounces_and_never_comes_home() -> void:
	var w := _world()
	var g: Node = w["g"]
	var pm: ProjectileManager = w["pm"]
	var ball := _behaviour(w, ProjectileEmitter.new(), _inst("basketball")) as ProjectileEmitter
	assert_bool(ball._fire()).is_true()
	var j := _first_alive(pm)
	assert_int(j).is_greater_equal(0)
	assert_bool(pm.extra[j].has("drop_bounce")).is_true()
	assert_vector(pm.vel[j].normalized()).is_equal_approx(Vector3(0, 0, -1), Vector3.ONE * 0.001)
	var returned := false
	var steps := 0
	var bounces_seen := 0
	var last_left := -1
	while pm.alive[j] == 1 and steps < 400:
		pm._physics_process(DT)
		if pm.ret[j] == 2:
			returned = true
		var left := int(pm.extra[j].get("bounces_left", -1))
		if last_left >= 0 and left < last_left:
			bounces_seen += 1
		last_left = left
		steps += 1
	assert_int(pm.alive[j]).is_equal(0)
	assert_bool(returned).is_false()
	assert_int(bounces_seen).is_equal(ProjectileManager.DROP_BOUNCES)
	assert_int(int(g.get("catches"))).is_equal(0)
	assert_int(Run.heat).is_equal(0)


func test_a_basketball_that_hits_still_comes_home() -> void:
	var w := _world()
	var g: Node = w["g"]
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	_creature(em, _at(5.0, 10.0))
	var ball := _behaviour(w, ProjectileEmitter.new(), _inst("basketball")) as ProjectileEmitter
	assert_bool(ball._fire()).is_true()
	var j := _first_alive(pm)
	var steps := 0
	while pm.alive[j] == 1 and steps < 900:
		em._rebuild_grid()
		pm._physics_process(DT)
		steps += 1
	assert_int(int(g.get("catches"))).is_equal(1)
	assert_int(pm.drops).is_equal(0)


func test_the_gravity_gun_fires_at_the_sand_with_nobody_near() -> void:
	var w := _world()
	var g: Node = w["g"]
	var em: EnemyManager = w["em"]
	var gun := _behaviour(w, GravityGun.new(), _inst("gravity_gun")) as GravityGun
	assert_bool(gun._fire()).is_true()
	assert_int(gun.dry_shots).is_equal(1)
	assert_int(int(g.get("sands"))).is_equal(1)
	assert_int(gun._grips.size()).is_equal(0)
	# a creature behind him is never grabbed; one ahead in the cone is
	var back := _creature(em, _at(3.0, 170.0))
	assert_bool(gun._fire()).is_true()
	assert_int(gun._grips.size()).is_equal(0)
	var ahead := _creature(em, _at(4.0, 20.0))
	assert_bool(gun._fire()).is_true()
	assert_int(gun._grips.size()).is_equal(1)
	assert_int(int(gun._grips[0]["i"])).is_equal(ahead)
	assert_int(back).is_not_equal(ahead)


func test_the_frisbee_and_the_guitarra_go_down_the_facing() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	hero.set("facing", PI * 0.5)  # he faces -X
	var fr: Node = _behaviour(w, (load("res://core/behaviors/Frisbee.gd") as GDScript).new(), _inst("frisbee"))
	assert_bool(fr._fire()).is_true()
	var d: Dictionary = (fr.get("discs") as Array)[0]
	var d0: Vector3 = d["dir0"]
	assert_float(Vector2(d0.x, d0.z).normalized().distance_to(Vector2(-1, 0))).is_less(0.6)
	var gt := _behaviour(w, ConeWave.new(), _inst("guitarra")) as ConeWave
	assert_bool(gt._fire()).is_true()
	assert_vector(gt._aim).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)


# ---------------------------------------------------------------- R1: the turn on the spot

func _player() -> Player:
	var holder: Node3D = auto_free(Node3D.new())
	holder.set_script(_script(HOLDER))
	add_child(holder)
	var m: Node = Node.new()
	m.set_script(_script(FLAT_MAP))
	holder.add_child(m)
	holder.set("map", m)
	var pl: Player = (load("res://player/Player.tscn") as PackedScene).instantiate()
	holder.add_child(pl)
	pl.setup(Registry.character("drifter"))
	pl.global_position = Vector3.ZERO
	pl.camera_yaw_fn = func() -> float: return 0.0
	pl.input.set_process(false)
	pl.input.set_process_unhandled_input(false)
	pl.set_physics_process(false)
	return pl


func test_a_small_push_turns_him_without_walking() -> void:
	var pl := _player()
	pl.facing = 0.0
	pl.input.wants_move = true
	pl.input.stick_dir = Vector2(0.1, 0.0)
	for k in range(20):
		pl._physics_process(DT)
	assert_float(Vector2(pl.global_position.x, pl.global_position.z).length()).is_less(0.001)
	# he turned to face +X (a stick right is a yaw of -90 degrees)
	assert_float(pl.forward().x).is_greater(0.95)
	# a fuller push walks
	pl.input.stick_dir = Vector2(0.5, 0.0)
	for k in range(20):
		pl._physics_process(DT)
	assert_float(pl.global_position.x).is_greater(0.3)
	# the switch off: the same small push creeps as before
	Settings.aim_mode = false
	var x0 := pl.global_position.x
	pl.input.stick_dir = Vector2(0.1, 0.0)
	for k in range(20):
		pl._physics_process(DT)
	assert_float(pl.global_position.x - x0).is_greater(0.01)


# ---------------------------------------------------------------- R7: the wedge, the record

func test_the_wedge_takes_the_widest_aimed_cone_and_pulses() -> void:
	var rev := _inst("revolver")
	var tum := _inst("tumbleweed")
	var gui := _inst("guitarra")
	assert_float(AimWedge.widest_cone([rev, tum])).is_equal(60.0)
	assert_float(AimWedge.widest_cone([tum, gui])).is_equal(70.0)
	assert_float(AimWedge.widest_cone([tum])).is_equal(40.0)
	Settings.aim_mode = false
	assert_float(AimWedge.widest_cone([rev])).is_equal(0.0)
	Settings.aim_mode = true
	var mesh := AimWedge.build_mesh(60.0)
	assert_int(mesh.get_surface_count()).is_equal(1)
	# a live wedge on the fake game: shown, pulsed, hidden with the setting off
	var w := _world()
	Run.weapons = [rev]
	var wedge := AimWedge.make(w["g"])
	(w["g"] as Node).add_child(wedge)
	wedge._process(DT)
	assert_float(wedge.cone_deg).is_equal(60.0)
	assert_bool(wedge.visible).is_true()
	AimWedge.pulse()
	assert_int(wedge.pulses).is_equal(1)
	AimWedge.pulse_dir(Vector3(1, 0, -1).normalized())
	assert_int(wedge.pulses).is_equal(2)
	Settings.show_aim = false
	wedge._process(DT)
	assert_bool(wedge.visible).is_false()
	assert_float(AimWedge.local_angle(0.0, Vector3(1, 0, -1).normalized())).is_equal_approx(PI * 0.25, 0.001)
	Run.weapons = []


func test_the_settings_carry_both_switches_and_prod_keeps_the_aim_on() -> void:
	var d := Settings.to_dict()
	assert_bool(d.has("aim_mode")).is_true()
	assert_bool(d.has("show_aim")).is_true()
	assert_bool(bool(Settings.PROD_LOCKED["aim_mode"])).is_true()
	# an old save without the keys plays the defaults
	Settings.aim_mode = false
	Settings.show_aim = false
	var fresh = load("res://core/autoload/Settings.gd").new()
	assert_bool(bool(fresh.aim_mode)).is_true()
	assert_bool(bool(fresh.show_aim)).is_true()
	fresh.free()
