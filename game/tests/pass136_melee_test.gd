extends GdUnitTestSuite

## Pass 136, lane MELEE: the Sabre and the Spear as effects under the new aim (Aim.covers): no blade shown, a crescent
## arc a swing and a stab streak a thrust centred on the Outlaw's facing within their assist (the Sabre 20, the Spear
## 15 degrees), strokes on every beat with nothing to hit, the hit tests unchanged, the switch off = the blade back and
## the old aim, the pools capped.

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
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
"""

const DT := 1.0 / 60.0

var _aim_was := true
var _ff_was := false


func before_test() -> void:
	_aim_was = Settings.aim_mode
	_ff_was = Settings.fire_forward
	Settings.aim_mode = true
	# pass 137 (lane AIM): these pin pass 136's rule (every aimed weapon hard); pass137_aim_test pins the soft one
	Aim.soft_rule = false


func after_test() -> void:
	Settings.aim_mode = _aim_was
	Aim.soft_rule = true
	Settings.fire_forward = _ff_was


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
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
	return {"g": g, "hero": hero, "em": em}


func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	return i


func _thruster(w: Dictionary, id: String, muts: Array = [], level := 1) -> Thruster:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	var b := Thruster.new()
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## Ticks the stroke through (`secs` seconds).
func _run_for(b: Thruster, secs: float) -> void:
	var n := int(secs / DT)
	for k in range(n):
		b._tick(DT)


func _any_blade_shown(b: Thruster) -> bool:
	for bl: Node3D in b._blades:
		if bl.visible:
			return true
	return false


## The angle (degrees) between flat directions.
func _deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))))


# ---------------------------------------------------------------- the four carry their aim blocks

func test_the_sabre_the_spear_and_their_evolutions_are_melee_aimed() -> void:
	for id: String in ["sabre", "whirlwind", "pike", "thunder_lance"]:
		var inst := WeaponInstance.new(Registry.weapon(id), 1)
		inst.rebuild(Run.player_sheet, [inst])
		var c := Aim.cfg(inst)
		assert_str(str(c.get("family", ""))).override_failure_message(id).is_equal("melee")
		assert_bool(Aim.covers(inst)).override_failure_message(id).is_true()
	var sab := WeaponInstance.new(Registry.weapon("sabre"), 1)
	sab.rebuild(Run.player_sheet, [sab])
	assert_float(float(Aim.cfg(sab)["assist"])).is_equal(20.0)
	assert_str(str(Aim.cfg(sab)["look"])).is_equal("slash")
	var pk := WeaponInstance.new(Registry.weapon("pike"), 1)
	pk.rebuild(Run.player_sheet, [pk])
	assert_float(float(Aim.cfg(pk)["assist"])).is_equal(15.0)
	assert_str(str(Aim.cfg(pk)["look"])).is_equal("stab")


# ---------------------------------------------------------------- no blade, an effect a stroke

func test_a_swing_shows_an_arc_and_no_blade() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -2.0))
	(w["em"] as EnemyManager)._rebuild_grid()
	var b := _thruster(w, "sabre")
	assert_bool(b._fire()).is_true()
	assert_bool(b.fx_on()).is_true()
	_run_for(b, 0.1)
	assert_bool(_any_blade_shown(b)).is_false()
	assert_object(b.effects()).is_not_null()
	assert_int(b.effects().arcs_made).is_equal(1)
	assert_int(b.effects().arcs_live()).is_equal(1)
	# the old crescent is not laid
	for pts: Array in b._trails:
		assert_int(pts.size()).is_equal(0)
	# the arc is gone after its sweep and fade
	_run_for(b, 0.6)
	assert_int(b.effects().arcs_live()).is_equal(0)


func test_a_thrust_shows_a_streak_and_no_spear() -> void:
	var w := _world()
	_creature(w["em"], Vector3(0, 0, -3.0))
	(w["em"] as EnemyManager)._rebuild_grid()
	var b := _thruster(w, "pike")
	assert_bool(b._fire()).is_true()
	_run_for(b, 0.25)
	assert_bool(_any_blade_shown(b)).is_false()
	assert_int(b.effects().thrusts_made).is_equal(1)
	assert_int(b.effects().flashes_made).is_equal(1)
	assert_float(float(b.effects().last_thrust["length"])).is_equal_approx(b.stat("range", 4.6), 0.001)
	assert_float(float(b.effects().last_thrust["lane_half"])).is_equal_approx(0.55 * 0.5 * b.stat("area", 1.0), 0.001)
	assert_int(b._streak_p.size()).is_equal(0)
	# level 5's second streak, fanned 40 degrees
	var b5 := _thruster(w, "pike", [], 5)
	b5._fire()
	assert_int(b5.effects().thrusts_made).is_equal(2)


func test_strokes_come_on_every_beat_with_nothing_to_hit() -> void:
	var w := _world()
	var b := _thruster(w, "sabre")
	assert_bool(b._fire()).is_true()
	assert_int(b.target).is_equal(-1)
	assert_float(_deg(b._dir, Vector3.FORWARD)).is_less(0.01)
	var p := _thruster(w, "pike")
	assert_bool(p._fire()).is_true()
	assert_int(p.effects().thrusts_made).is_equal(1)
	# the old aim waits for a creature
	Settings.aim_mode = false
	Settings.fire_forward = false
	var old := _thruster(w, "sabre")
	assert_bool(old._fire()).is_false()


# ---------------------------------------------------------------- centred on the facing, within the assist

func test_the_arc_turns_at_most_20_degrees_to_its_target() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	hero.facing = 0.4
	var f: Vector3 = hero.forward()
	# a creature 27 degrees off the facing, inside the 60-degree cone
	var t := _creature(em, f.rotated(Vector3.UP, deg_to_rad(27.0)) * 2.0)
	em._rebuild_grid()
	var b := _thruster(w, "sabre")
	b._fire()
	assert_int(b.target).is_equal(t)
	assert_float(_deg(b._dir, f)).is_equal_approx(20.0, 0.05)
	_run_for(b, 0.08)
	var yaw := float(b.effects().last_arc["yaw"])
	var arc_dir := Vector3(-sin(yaw), 0, -cos(yaw))
	assert_float(_deg(arc_dir, f)).is_less_equal(20.05)
	# turned towards it, not away
	assert_float(_deg(arc_dir, em.pos[t])).is_less(_deg(f, em.pos[t]))
	# a creature 10 degrees off: the arc goes straight at it
	em.kill_all(false)
	var t2 := _creature(em, f.rotated(Vector3.UP, deg_to_rad(-10.0)) * 2.0)
	em._rebuild_grid()
	var b2 := _thruster(w, "sabre")
	b2._fire()
	assert_int(b2.target).is_equal(t2)
	assert_float(_deg(b2._dir, f)).is_equal_approx(10.0, 0.3)


func test_the_streak_turns_at_most_15_degrees() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	hero.facing = -0.7
	var f: Vector3 = hero.forward()
	_creature(em, f.rotated(Vector3.UP, deg_to_rad(19.0)) * 3.5)
	em._rebuild_grid()
	var b := _thruster(w, "pike")
	b._fire()
	assert_float(_deg(b._dir, f)).is_equal_approx(15.0, 0.05)
	var d: Vector3 = b.effects().last_thrust["dir"]
	assert_float(_deg(d, b._dir)).is_less(0.01)
	# pass 137 (lane AIM, re-pinned to the soft rule, Aim.soft_target): a creature 3 m behind him, inside the Spear's reach
	# (4.6 + 0.6 m) and within threat_reach, is thrust at (S1, the cone empty)
	Aim.soft_rule = true
	em.kill_all(false)
	var back := _creature(em, -f * 3.0)
	em._rebuild_grid()
	var b2 := _thruster(w, "pike")
	b2._fire()
	assert_int(b2.target).is_equal(back)
	assert_float(_deg(b2._dir, -f)).is_less(0.5)
	# one behind beyond the reach is not: the stroke goes down the facing
	em.kill_all(false)
	_creature(em, -f * 7.0)
	em._rebuild_grid()
	var b3 := _thruster(w, "pike")
	b3._fire()
	assert_int(b3.target).is_equal(-1)
	assert_float(_deg(b3._dir, f)).is_less(0.01)
	# pass 136's rule (every aimed weapon hard; this file's default): not even the one 3 m behind
	Aim.soft_rule = false
	em.kill_all(false)
	_creature(em, -f * 3.0)
	em._rebuild_grid()
	var b4 := _thruster(w, "pike")
	b4._fire()
	assert_int(b4.target).is_equal(-1)
	assert_float(_deg(b4._dir, f)).is_less(0.01)


# ---------------------------------------------------------------- the hit area is the old one

func test_the_hit_tests_are_unchanged() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# the spear's lane: a creature on the line and one just outside the lane's side
	var on := _creature(em, Vector3(0, 0, -2.0), 50.0)
	var r := float(em.radius[on])
	var b := _thruster(w, "pike")
	var lane := 0.55 * b.stat("area", 1.0) * 0.5
	# (pass 136 lead: margins 0.6 / 0.2 m, so a creature's first step cannot carry it across the lane's side)
	var off := _creature(em, Vector3(lane + r + 0.6, 0, -3.0), 50.0)
	var edge := _creature(em, Vector3(-(lane + r - 0.2), 0, -3.5), 50.0)
	em._rebuild_grid()
	var hp_on := em.hp[on]
	var hp_off := em.hp[off]
	var hp_edge := em.hp[edge]
	b._fire()
	# the one on the line is the best target: the thrust goes straight down the facing
	assert_int(b.target).is_equal(on)
	assert_float(_deg(b._dir, Vector3.FORWARD)).is_less(0.01)
	_run_for(b, 0.6)
	# the one on the line and the one at the lane's edge are struck, the one just outside is not
	assert_float(em.hp[on]).is_less(hp_on)
	assert_float(em.hp[edge]).is_less(hp_edge)
	assert_float(em.hp[off]).is_equal(hp_off)
	# the same stroke with the switch off, aimed down the same line, strikes as hard
	var dmg_on := hp_on - em.hp[on]
	em.kill_all(false)
	var on2 := _creature(em, Vector3(0, 0, -2.0), 50.0)
	em._rebuild_grid()
	Settings.aim_mode = false
	Settings.fire_forward = false
	var ob := _thruster(w, "pike")
	var hp2 := em.hp[on2]
	ob._fire()
	assert_float(_deg(ob._dir, Vector3.FORWARD)).is_less(0.01)
	_run_for(ob, 0.6)
	assert_float(hp2 - em.hp[on2]).is_equal_approx(dmg_on, 0.01)


func test_the_sabre_cuts_the_old_slice_round_its_facing() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# 60 degrees off the facing: outside the aim cone, inside the 150-degree slice
	var side := _creature(em, Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(60.0)) * 2.0)
	# behind: never cut
	var back := _creature(em, Vector3(0, 0, 2.0))
	em._rebuild_grid()
	var hs := em.hp[side]
	var hb := em.hp[back]
	var b := _thruster(w, "sabre")
	b._fire()
	assert_float(_deg(b._dir, Vector3.FORWARD)).is_less(0.01)
	_run_for(b, 0.5)
	assert_float(em.hp[side]).is_less(hs)
	assert_float(em.hp[back]).is_equal(hb)


# ---------------------------------------------------------------- the switch off: the blade back

func test_the_switch_off_brings_the_blade_back() -> void:
	var w := _world()
	_creature(w["em"], Vector3(1.5, 0, 0))
	(w["em"] as EnemyManager)._rebuild_grid()
	Settings.aim_mode = false
	Settings.fire_forward = false
	var b := _thruster(w, "sabre")
	assert_bool(b._fire()).is_true()
	assert_bool(b.fx_on()).is_false()
	_run_for(b, 0.1)
	assert_bool(_any_blade_shown(b)).is_true()
	assert_object(b.effects()).is_null()
	# the old aim: straight at the creature, 90 degrees off his facing
	assert_float(_deg(b._dir, Vector3(1, 0, 0))).is_less(0.01)
	var p := _thruster(w, "pike")
	p._fire()
	_run_for(p, 0.15)
	assert_bool(_any_blade_shown(p)).is_true()
	assert_int(p._streak_p.size()).is_greater(0)


# ---------------------------------------------------------------- the looks by build

func test_whirlwind_draws_a_full_ring_and_riposte_a_flick() -> void:
	var w := _world()
	var ww := _thruster(w, "whirlwind")
	ww._fire()
	_run_for(ww, 0.08)
	assert_float(float(ww.effects().last_arc["half_w"])).is_equal_approx(PI, 0.001)
	_run_for(ww, 1.0)
	assert_int(ww.effects().arcs_made).is_equal(ww.stat_int("amount", 4))
	var rp := _thruster(w, "sabre", ["riposte"])
	rp._fire()
	_run_for(rp, 0.5)
	# its swing and the flick
	assert_int(rp.effects().arcs_made).is_equal(2)
	var look := rp._fx_arc_look()
	assert_bool((look["edge"] as Color).is_equal_approx(Thruster.FX_BRASS_EDGE)).is_true()
	var ct := _thruster(w, "sabre", ["critical_thinking"])
	# a hairline: thinner than the plain steel edge
	var plain := _thruster(w, "sabre")
	assert_float(float(ct._fx_arc_look()["edge_w"])).is_less(float(plain._fx_arc_look()["edge_w"]) * 0.5)


func test_heartseeker_warms_up_and_the_fourth_is_red_and_thicker() -> void:
	var w := _world()
	var b := _thruster(w, "pike", ["heartseeker"])
	var widths: Array = []
	var reds: Array = []
	for k in range(4):
		b._fire()
		var look := b._fx_thrust_look()
		widths.append(float(look["width"]))
		reds.append((look["glow"] as Color).r - (look["glow"] as Color).b)
		_run_for(b, 1.0)
	assert_float(float(widths[3])).is_greater(float(widths[0]))
	# warmer stroke by stroke
	assert_float(float(reds[1])).is_greater(float(reds[0]))
	assert_float(float(reds[2])).is_greater(float(reds[1]))
	assert_int(b.crit_strokes).is_equal(1)
	# the red lance mesh of the blade look is not laid: the streak is the lance
	assert_int(b.lances).is_equal(0)


func test_stunning_thrust_rings_and_the_thunder_lance_bolts() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(0, 0, -2.5))
	em._rebuild_grid()
	var b := _thruster(w, "pike", ["stunning_thrust"])
	var th: Dictionary = (b.inst.params.get("thrust", {}) as Dictionary).duplicate(true)
	th["stun"] = {"chance": 1.0, "seconds": 1.0}
	b.inst.params["thrust"] = th
	b._fire()
	_run_for(b, 0.5)
	assert_int(b.stuns).is_greater(0)
	assert_int(b.stun_rings).is_equal(b.stuns)
	var tl := _thruster(w, "thunder_lance")
	tl._fire()
	_run_for(tl, 1.5)
	assert_int(tl.tip_bolts).is_equal(1)
	# the sweep's two arcs (blades mode) and the thrust's two streaks
	assert_int(tl.effects().arcs_made).is_equal(2)
	assert_int(tl.effects().thrusts_made).is_equal(2)


# ---------------------------------------------------------------- the pools are capped

func test_the_pools_are_capped() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var fx := MeleeFx.new()
	(w["g"] as Node).add_child(fx)
	for k in range(30):
		fx.arc(hero, 0.0, 1.0, 2.6, 0.16, 0.12, 1.0)
		fx.thrust(hero, Vector3.FORWARD, 4.6, 0.3, 0.0, 0.1, 0.1, 0.26)
		fx.tick(DT)
	var sizes := fx.pool_sizes()
	assert_int(sizes.x).is_equal(MeleeFx.ARC_MAX)
	assert_int(sizes.y).is_equal(MeleeFx.THRUST_MAX)
	assert_int(sizes.z).is_less_equal(MeleeFx.FLASH_MAX)
	assert_int(fx.arcs_live()).is_less_equal(MeleeFx.ARC_MAX)
	# a Whirlwind under Flurry swinging fast keeps to the cap too
	var ww := _thruster(w, "whirlwind", ["flurry"])
	for k in range(6):
		ww._fire()
		_run_for(ww, 0.3)
	assert_int(ww.effects().pool_sizes().x).is_less_equal(MeleeFx.ARC_MAX)
	fx.queue_free()
