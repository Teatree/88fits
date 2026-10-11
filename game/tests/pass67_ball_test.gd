extends GdUnitTestSuite

## Pass 67, lane P (the basketball's code), on a ball weapon made here (lane C's content lands in parallel): `amount`
## counts bounces (one ball, its hops seeded as ricochet_any.count + amount - 1, Multishot one more); a pierce-0 ball with
## return_on_hit turns home when its hops are spent and when nobody is within reach, with return_pierce touches for the
## way home (the creature it turned at struck once more: the rebound), flies on through the rest and is caught, once and
## never at a second pass's relaunch; the catch refunds the cooldown and warms Heat only when the trip scored, up to
## heat_max; Heat multiplies the throw and is its glow; a hit on his health cools it unless heat_keep; Slam Dunk's dunk at
## full Heat; Free Throw on an evade with its gap; ricochet_any.reach; the boomerang's turn as before; the estimate, the
## noun and the words.

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
var caught: Array = []
var behaviors: Dictionary = {}
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
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func ball_caught(w, ex: Dictionary) -> void:
	caught.append(ex.duplicate())
	var b = behaviors.get(w.def.id)
	if b != null and b.has_method("on_caught"):
		b.on_caught(ex)
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
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
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0

## The basketball's params as the design has them (tools/dl/p67/design_spec.json), on a weapon made here.
const BALL := {
	"radius": 0.3, "amount_mode": "bounces", "ricochet_any": {"count": 1, "frac": 0.85, "reach": 7.0},
	"return": true, "return_on_hit": true, "return_pierce": 2, "return_damage_mult": 0.75, "back_speed_mult": 1.25,
	"catch": {"refund": 0.35, "heat_per": 0.05, "heat_max": 10}}


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.heat = 0


func after_test() -> void:
	Run.heat = 0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at`, with the real crowd, shots, effects and ground marks.
func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam}


## A tough creature on its feet where it was put, taking every hit whole.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	return i


## A ball weapon: BALL with `over` merged in (deep), the base stats with `base_over`, five levels of nothing.
func _ball_def(over: Dictionary = {}, base_over: Dictionary = {}) -> WeaponDef:
	var d := WeaponDef.new()
	d.id = "p67_test_ball"
	d.display_name = "Test Ball"
	d.behavior = "ProjectileEmitter"
	d.targeting = "priority"
	d.base = {"damage": 20.0, "cooldown": 1.4, "amount": 1, "pierce": 0, "speed": 16.0, "range": 9.0, "knockback": 0.0}
	for k in base_over.keys():
		d.base[k] = base_over[k]
	d.levels = [[], [], [], [], []]
	d.max_level = 5
	d.params = WeaponInstance.merge_params(BALL, over)
	return d


func _ball(over: Dictionary = {}, base_over: Dictionary = {}, sheet: StatSheet = null) -> WeaponInstance:
	var inst := WeaponInstance.new(_ball_def(over, base_over), 1)
	inst.rebuild(sheet if sheet != null else StatSheet.new(), [inst])
	return inst


## A behaviour for `inst` in the fake game, known to its ball_caught by the weapon's id (as Game._behaviors).
func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	var pe := ProjectileEmitter.new()
	(w["g"] as Node).add_child(pe)
	pe.setup(inst, w["g"])
	((w["g"] as Node).get("behaviors") as Dictionary)[inst.def.id] = pe
	return pe


## The live shots of weapon `inst`, ghosts left out.
func _live_of(pm: ProjectileManager, inst: WeaponInstance) -> Array:
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst and not (pm.extra[j] as Dictionary).has("ghost"):
			out.append(j)
	return out


## The one live shot of `inst` that is not in `seen`.
func _new_shot(pm: ProjectileManager, inst: WeaponInstance, seen: Array) -> int:
	for j: int in _live_of(pm, inst):
		if not seen.has(j):
			return j
	return -1


func _hp(em: EnemyManager, ids: Array) -> Dictionary:
	var out := {}
	for i: int in ids:
		out[i] = em.hp[i]
	return out


## Steps the shots until shot `j` is no longer on its way out (ret 1), at most `most` ticks.
func _until_turned(pm: ProjectileManager, j: int, most := 240) -> void:
	var steps := 0
	while pm.alive[j] == 1 and pm.ret[j] == 1 and steps < most:
		pm._physics_process(DT)
		steps += 1


## Steps the shots until shot `j` is gone (caught or freed), at most `most` ticks.
func _until_gone(pm: ProjectileManager, j: int, most := 900) -> void:
	var steps := 0
	while pm.alive[j] == 1 and steps < most:
		pm._physics_process(DT)
		steps += 1


# ---------------------------------------------------------------- amount = bounces

## One ball a throw whatever the amount: the amount past the first is that many more hops for it (ricochet_any.count 1 +
## amount 3 - 1 = 3), and Multishot's +1 on his sheet is one hop more, never a second ball; the noun says bounces.
func test_amount_counts_bounces_one_ball_a_throw() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	var three := _ball({}, {"amount": 3})
	assert_int(three.stat_int("amount")).is_equal(3)
	var pe := _emitter(w, three)
	assert_bool(pe._fire()).is_true()
	var shots := _live_of(pm, three)
	assert_int(shots.size()).is_equal(1)
	assert_int(int(pm.extra[shots[0]]["rc_left"])).is_equal(3)
	assert_int(pe.throws).is_equal(1)
	var ms := StatSheet.new()
	ms.add_effect(Effect.make("amount", "add", 1.0), "multishot")
	var two := _ball({}, {}, ms)
	assert_int(two.stat_int("amount")).is_equal(2)
	var pe2 := _emitter(w, two)
	assert_bool(pe2._fire()).is_true()
	var shots2 := _live_of(pm, two)
	assert_int(shots2.size()).is_equal(1)
	assert_int(int(pm.extra[shots2[0]]["rc_left"])).is_equal(2)
	assert_str(TextGen.amount_noun(two.def, two.sheet, two.params)).is_equal("bounces")


# ---------------------------------------------------------------- the trip: hops, the turn, the way home, the catch

## The throw strikes the first creature whole and hops to the next within reach at 85%; its hops spent, it turns there
## for home (ret 2, the way home's two touches at 75%) and strikes that creature once more (the rebound); home, it is
## caught once: the trip's three hits, 35% of the cooldown back, one Heat.
func test_a_ball_hops_turns_home_rebounds_and_is_caught() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var a := _creature(em, Vector3(4, 0, 0))
	var b := _creature(em, Vector3(4, 0, 5))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	var hp0 := _hp(em, [a, b])
	var inst := _ball()
	var pe := _emitter(w, inst)
	assert_bool(pe._fire()).is_true()
	var j: int = _live_of(pm, inst)[0]
	assert_int(pm.ret[j]).is_equal(1)
	assert_int(int(pm.extra[j]["rc_left"])).is_equal(1)
	_until_turned(pm, j)
	assert_int(pm.alive[j]).is_equal(1)
	assert_int(pm.ret[j]).is_equal(2)
	assert_int(pm.pierce[j]).is_equal(2)
	assert_float(pm.dmg[j]).is_equal_approx(15.0, 0.001)
	assert_float(float(hp0[a]) - em.hp[a]).is_equal_approx(20.0, 0.01)
	assert_float(float(hp0[b]) - em.hp[b]).is_equal_approx(17.0, 0.01)
	pe.cooldown_left = 1.4
	_until_gone(pm, j)
	assert_int(pm.alive[j]).is_equal(0)
	# the rebound off the one it turned at; the first is off the way home
	assert_float(float(hp0[b]) - em.hp[b]).is_equal_approx(32.0, 0.01)
	assert_float(float(hp0[a]) - em.hp[a]).is_equal_approx(20.0, 0.01)
	var caught: Array = g.get("caught")
	assert_int(caught.size()).is_equal(1)
	assert_int(int((caught[0] as Dictionary).get("hits", 0))).is_equal(3)
	assert_int(pe.catches).is_equal(1)
	assert_float(pe.cooldown_left).is_equal_approx(1.4 - 0.35 * 1.4, 0.001)
	assert_int(Run.heat).is_equal(1)


## With nobody within reach of the creature it struck, the ball turns there at once instead of ending: the lone creature
## takes the throw and the rebound (20 + 15), the one 8 m further on is never touched, and the ball is caught.
func test_a_lone_ball_turns_at_its_creature_and_rebounds() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var a := _creature(em, Vector3(4, 0, 0))
	var far := _creature(em, Vector3(4, 0, 12))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	var hp0 := _hp(em, [a, far])
	var inst := _ball()
	var pe := _emitter(w, inst)
	assert_bool(pe._fire()).is_true()
	var j: int = _live_of(pm, inst)[0]
	_until_turned(pm, j)
	assert_int(pm.ret[j]).is_equal(2)
	assert_int(pm.pierce[j]).is_equal(2)
	# the hop was never spent: nobody stood within reach
	assert_int(int(pm.extra[j]["rc_left"])).is_equal(1)
	_until_gone(pm, j)
	assert_int(pm.alive[j]).is_equal(0)
	assert_float(float(hp0[a]) - em.hp[a]).is_equal_approx(35.0, 0.01)
	assert_float(em.hp[far]).is_equal(float(hp0[far]))
	assert_int((g.get("caught") as Array).size()).is_equal(1)
	assert_int(pe.catches).is_equal(1)
	assert_int(Run.heat).is_equal(1)


## A throw that meets nobody flies its range, turns there (the boomerang's own turn) with the way home's touches, and is
## caught: the refund, but no Heat (the trip did not score).
func test_a_ball_that_hits_nothing_comes_home_without_heat() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var inst := _ball()
	var pe := _emitter(w, inst)
	var j := pm.fire(pe.projectile_kind, Vector3(0, 0.8, 0), Vector3(16, 0, 0), 20.0, 0, 0.3, 9.0 / 16.0, inst, 0.0)
	_until_turned(pm, j)
	assert_int(pm.ret[j]).is_equal(2)
	assert_int(pm.pierce[j]).is_equal(2)
	assert_float(pm.pos[j].x).is_greater(8.5)
	pe.cooldown_left = 1.0
	_until_gone(pm, j)
	assert_int(pm.alive[j]).is_equal(0)
	var caught: Array = g.get("caught")
	assert_int(caught.size()).is_equal(1)
	assert_int(int((caught[0] as Dictionary).get("hits", 0))).is_equal(0)
	assert_int(pe.catches).is_equal(1)
	assert_float(pe.cooldown_left).is_equal_approx(1.0 - 0.35 * 1.4, 0.001)
	assert_int(Run.heat).is_equal(0)


## The way home strikes return_pierce creatures (2) at return_damage_mult, then flies on through the rest to his hand;
## Rebound's 80 at full damage strikes all three on its line.
func test_the_way_home_strikes_return_pierce_creatures_then_flies_through() -> void:
	for rebound: bool in [false, true]:
		var w := _world()
		var em: EnemyManager = w["em"]
		var pm: ProjectileManager = w["pm"]
		var g: Node = w["g"]
		var hero: Node3D = w["hero"]
		var line: Array = [_creature(em, Vector3(5, 0, -1.5)), _creature(em, Vector3(5, 0, -3.0)), _creature(em, Vector3(5, 0, -4.5))]
		em._rebuild_grid()
		var hp0 := _hp(em, line)
		var over: Dictionary = {"return_pierce": 80, "return_damage_mult": 1.0, "back_speed_mult": 1.6} if rebound else {}
		var inst := _ball(over)
		var pe := _emitter(w, inst)
		# out along +x, clear of the line, to its turn 5 m out
		var j := pm.fire(pe.projectile_kind, Vector3(0, 0.8, 0), Vector3(16, 0, 0), 20.0, 0, 0.3, 5.0 / 16.0, inst, 0.0)
		_until_turned(pm, j)
		assert_int(pm.ret[j]).is_equal(2)
		# he has moved on: the way home runs down the line
		hero.global_position = Vector3(5, 0, -6)
		_until_gone(pm, j)
		assert_int(pm.alive[j]).is_equal(0)
		var took: Array = []
		for i: int in line:
			took.append(float(hp0[i]) - em.hp[i])
		if rebound:
			for t: float in took:
				assert_float(t).is_equal_approx(20.0, 0.01)
		else:
			assert_float(float(took[0])).is_equal_approx(15.0, 0.01)
			assert_float(float(took[1])).is_equal_approx(15.0, 0.01)
			assert_float(float(took[2])).is_equal(0.0)
		var caught: Array = g.get("caught")
		assert_int(caught.size()).override_failure_message("rebound %s" % str(rebound)).is_equal(1)
		assert_int(int((caught[0] as Dictionary).get("hits", 0))).is_equal(3 if rebound else 2)


## A ball with a second pass (the Dust Devil's rule) is caught once, at the end of its second trip, never at the relaunch.
func test_the_catch_waits_for_a_second_pass() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var inst := _ball({"second_pass": true})
	var pe := _emitter(w, inst)
	var j := pm.fire(pe.projectile_kind, Vector3(0, 0.8, 0), Vector3(16, 0, 0), 20.0, 0, 0.3, 4.0 / 16.0, inst, 0.0)
	assert_int(int(pm.extra[j].get("passes", 1))).is_equal(0)
	var relaunched := false
	var steps := 0
	while pm.alive[j] == 1 and steps < 1500:
		pm._physics_process(DT)
		steps += 1
		if not relaunched and int(pm.extra[j].get("passes", 0)) == 1:
			relaunched = true
			# out again from his hand, nothing caught yet
			assert_int(pm.ret[j]).is_equal(1)
			assert_int((g.get("caught") as Array).size()).is_equal(0)
	assert_bool(relaunched).is_true()
	assert_int(pm.alive[j]).is_equal(0)
	assert_int((g.get("caught") as Array).size()).is_equal(1)
	assert_int(pe.catches).is_equal(1)


## ricochet_any.reach: a hop looks that far for its next creature (Full Court Press's 10 m); without the key it looks
## ProjectileManager.RICOCHET_REACH (7 m), so a creature 8.5 m on is out of reach and the ball turns at the first.
func test_a_hop_looks_as_far_as_its_reach() -> void:
	assert_float(ProjectileManager.RICOCHET_REACH).is_equal(7.0)
	for reach: float in [0.0, 7.0, 10.0]:
		# each round's catch warms Heat: every round throws cold
		Run.heat = 0
		var w := _world()
		var em: EnemyManager = w["em"]
		var pm: ProjectileManager = w["pm"]
		var a := _creature(em, Vector3(4, 0, 0))
		var b := _creature(em, Vector3(4, 0, 8.5))
		em._rebuild_grid()
		em.refresh_crowd_stats()
		var hp0 := _hp(em, [a, b])
		var d := _ball_def()
		if reach > 0.0:
			(d.params["ricochet_any"] as Dictionary)["reach"] = reach
		else:
			(d.params["ricochet_any"] as Dictionary).erase("reach")
		var inst := WeaponInstance.new(d, 1)
		inst.rebuild(StatSheet.new(), [inst])
		var pe := _emitter(w, inst)
		assert_bool(pe._fire()).is_true()
		var j: int = _live_of(pm, inst)[0]
		_until_gone(pm, j)
		var msg := "reach %.0f: the first took %.2f, the far one %.2f" % [reach, float(hp0[a]) - em.hp[a], float(hp0[b]) - em.hp[b]]
		if reach > 8.5:
			assert_float(float(hp0[a]) - em.hp[a]).override_failure_message(msg).is_equal_approx(20.0, 0.01)
			assert_float(float(hp0[b]) - em.hp[b]).override_failure_message(msg).is_equal_approx(32.0, 0.01)
		else:
			assert_float(float(hp0[a]) - em.hp[a]).override_failure_message(msg).is_equal_approx(35.0, 0.01)
			assert_float(em.hp[b]).override_failure_message(msg).is_equal(float(hp0[b]))


## The boomerang turns as before (the Tumbleweed's Boomerang, the Dust Devil): no return_pierce is 80 touches home at
## back_speed_mult and return_damage_mult, no catch without `catch`, and its turn at the range's end marks no rebound.
func test_the_boomerang_turn_is_unchanged() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var d := _ball_def()
	d.params = {"return": true, "return_damage_mult": 2.0, "back_speed_mult": 1.5}
	var inst := WeaponInstance.new(d, 1)
	inst.rebuild(StatSheet.new(), [inst])
	var k := pm.register_kind(BoxMesh.new(), null)
	var j := pm.fire(k, Vector3(0, 0.8, 0), Vector3(6, 0, 0), 10.0, 40, 0.3, 1.0, inst, 0.0)
	_until_turned(pm, j)
	assert_int(pm.ret[j]).is_equal(2)
	assert_int(pm.pierce[j]).is_equal(80)
	assert_float(pm.dmg[j]).is_equal_approx(20.0, 0.001)
	assert_float(pm.vel[j].length()).is_equal_approx(9.0, 0.01)
	assert_bool((pm.extra[j] as Dictionary).has("rebound")).is_false()
	_until_gone(pm, j)
	assert_int(pm.alive[j]).is_equal(0)
	assert_int((g.get("caught") as Array).size()).is_equal(0)


# ---------------------------------------------------------------- Heat, the dunk, the free throw

## Heat: +1 for a caught ball that scored (never for one that did not), up to heat_max; the refund never takes the
## cooldown below nothing; the throw's damage x (1 + Heat x heat_per) and its glow Heat / heat_max; a hit on his health
## drops it to 0, unless heat_keep; a weapon without `catch` never touches it.
func test_heat_rises_on_a_scoring_catch_cools_on_a_hit_and_warms_the_throw() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	var inst := _ball()
	var pe := _emitter(w, inst)
	pe.on_caught({"hits": 0})
	assert_int(Run.heat).is_equal(0)
	assert_int(pe.catches).is_equal(1)
	pe.on_caught({"hits": 2})
	assert_int(Run.heat).is_equal(1)
	for k in range(15):
		pe.on_caught({"hits": 1})
	assert_int(Run.heat).is_equal(10)
	assert_float(pe.heat_mult()).is_equal_approx(1.5, 0.0001)
	pe.cooldown_left = 1.4
	pe.on_caught({"hits": 1})
	assert_float(pe.cooldown_left).is_equal_approx(0.91, 0.0001)
	pe.cooldown_left = 0.2
	pe.on_caught({"hits": 1})
	assert_float(pe.cooldown_left).is_equal(0.0)
	# the throw at Heat 4: 20 x 1.2, glowing 0.4
	Run.heat = 4
	assert_bool(pe._fire()).is_true()
	var j: int = _live_of(pm, inst)[0]
	assert_float(pm.dmg[j]).is_equal_approx(24.0, 0.001)
	assert_float(pm.glow[j]).is_equal_approx(0.4, 0.001)
	pe.on_hero_hit()
	assert_int(Run.heat).is_equal(0)
	# Slam Dunk's heat_keep keeps it through a hit
	var keep := _ball({"catch": {"heat_keep": true}})
	var pk := _emitter(w, keep)
	Run.heat = 6
	pk.on_hero_hit()
	assert_int(Run.heat).is_equal(6)
	# a gun with no catch: no Heat on its damage, none made or lost
	var pea := WeaponInstance.new(Registry.weapon("peashooter"), 1)
	pea.rebuild(StatSheet.new(), [pea])
	var pp := _emitter(w, pea)
	pp.on_hero_hit()
	pp.on_caught({"hits": 3})
	assert_int(Run.heat).is_equal(6)
	assert_int(pp.catches).is_equal(0)
	assert_float(pp.heat_mult()).is_equal(1.0)


## Slam Dunk's catch at full Heat is a dunk: the damage x 1.5 to everything within 3.5 m of him, a shake; below full
## Heat a catch is only a catch; at full Heat every catch dunks, scored or not; its Heat survives a hit (heat_keep).
func test_slam_dunk_dunks_at_full_heat() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var cam: Node = w["cam"]
	var near := _creature(em, Vector3(1.5, 0, 0))
	var near2 := _creature(em, Vector3(0, 0, -2.5))
	var far := _creature(em, Vector3(6, 0, 0))
	em._rebuild_grid()
	var hp0 := _hp(em, [near, near2, far])
	var slam := {"at_heat": 10, "radius": 3.5, "damage_frac": 1.5, "knockback": 0.0}
	var sd := _ball({"return_pierce": 80, "catch": {"refund": 0.4, "heat_keep": true, "slam": slam}}, {"damage": 36.0})
	var pe := _emitter(w, sd)
	Run.heat = 5
	pe.on_caught({"hits": 1})
	assert_int(Run.heat).is_equal(6)
	assert_int(pe.dunks).is_equal(0)
	assert_float(em.hp[near]).is_equal(float(hp0[near]))
	Run.heat = 9
	pe.on_caught({"hits": 1})
	assert_int(Run.heat).is_equal(10)
	assert_int(pe.dunks).is_equal(1)
	assert_float(float(hp0[near]) - em.hp[near]).is_equal_approx(54.0, 0.01)
	assert_float(float(hp0[near2]) - em.hp[near2]).is_equal_approx(54.0, 0.01)
	assert_float(em.hp[far]).is_equal(float(hp0[far]))
	assert_int(int(cam.get("shakes"))).is_equal(1)
	pe.on_caught({"hits": 0})
	assert_int(pe.dunks).is_equal(2)
	pe.on_hero_hit()
	assert_int(Run.heat).is_equal(10)


## Free Throw: an evade throws a ball at once, drawn white, at damage_mult, leaving the cooldown as it was, then no other
## for `every` seconds; with nobody within range no ball goes and no gap starts; the next ordinary throw is the ball's
## own; a ball without Free Throw never throws on an evade.
func test_free_throw_fires_on_an_evade_and_keeps_its_gap() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var inst := _ball({"free_throw": {"every": 0.8, "damage_mult": 0.5}})
	var pe := _emitter(w, inst)
	pe.cooldown_left = 1.0
	pe.on_hero_evaded()
	assert_int(pe.free_throws).is_equal(0)
	_creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	pe.on_hero_evaded()
	assert_int(pe.free_throws).is_equal(1)
	var shots := _live_of(pm, inst)
	assert_int(shots.size()).is_equal(1)
	var j: int = shots[0]
	assert_float(pm.dmg[j]).is_equal_approx(10.0, 0.001)
	assert_int(pm.kind[j]).is_equal(pe.tint_kind(ProjectileEmitter.FREE_TINT))
	assert_int(pm.kind[j]).is_not_equal(pe._kind())
	assert_float(pe.cooldown_left).is_equal(1.0)
	# its gap: none within 0.8 s
	pe.on_hero_evaded()
	assert_int(pe.free_throws).is_equal(1)
	pe._tick(0.5)
	pe.on_hero_evaded()
	assert_int(pe.free_throws).is_equal(1)
	pe._tick(0.35)
	pe.on_hero_evaded()
	assert_int(pe.free_throws).is_equal(2)
	# the ordinary throw after it: the ball's own look and the whole damage
	var seen := _live_of(pm, inst)
	assert_bool(pe._fire()).is_true()
	var k := _new_shot(pm, inst, seen)
	assert_int(k).is_greater_equal(0)
	assert_float(pm.dmg[k]).is_equal_approx(20.0, 0.001)
	assert_int(pm.kind[k]).is_equal(pe._kind())
	var plain := _ball()
	var pp := _emitter(w, plain)
	pp.on_hero_evaded()
	assert_int(pp.free_throws).is_equal(0)
	assert_int(pp.throws).is_equal(0)


# ---------------------------------------------------------------- the estimate and the words

## The estimate counts a throw as the throw, its hops at 85%, two touches home at 75% (Rebound's at 100%), all times
## Heat; the words say where it goes, how far it bounces, how it comes back and the Heat (and Slam Dunk's dunk), never
## "ricochets"; a level that adds one reads "Bounces 1 → 2".
func test_the_estimate_and_the_words_count_bounces() -> void:
	var b1 := _ball()
	assert_float(b1.dps_estimate()).is_equal_approx(20.0 * (1.0 + 0.85 + 2.0 * 0.75) / 1.4, 0.01)
	var b3 := _ball({}, {"amount": 3})
	assert_float(b3.dps_estimate()).is_equal_approx(20.0 * (1.0 + 3.0 * 0.85 + 2.0 * 0.75) / 1.4, 0.01)
	var rb := _ball({"return_pierce": 80, "return_damage_mult": 1.0})
	assert_float(rb.dps_estimate()).is_equal_approx(20.0 * (1.0 + 0.85 + 2.0) / 1.4, 0.01)
	Run.heat = 10
	assert_int(WeaponInstance.run_heat()).is_equal(10)
	assert_float(b1.dps_estimate()).is_equal_approx(20.0 * 3.35 * 1.5 / 1.4, 0.01)
	Run.heat = 0
	assert_str(TextGen.amount_noun(b1.def, b1.sheet, b1.params)).is_equal("bounces")
	assert_str(b1.description()).is_equal("Throws a ball at the strongest enemy within 9 m: it bounces to 1 more enemy within 7 m, then flies back to his hand, hitting up to 2 on the way. Every caught ball that scored adds Heat: +5% damage, up to +50%. A hit on him cools it.")
	assert_str(b3.description()).contains("it bounces to 3 more enemies within 7 m")
	assert_str(rb.description()).contains("then flies back to his hand, hitting everything on the way.")
	assert_str(b1.description()).not_contains("ricochet")
	var slam := {"at_heat": 10, "radius": 3.5, "damage_frac": 1.5, "knockback": 12.0}
	var sd := _ball({"return_pierce": 80, "ricochet_any": {"count": 3, "reach": 10.0}, "catch": {"heat_keep": true, "slam": slam}}, {"range": 10.0})
	assert_str(sd.description()).is_equal("Throws a ball at the strongest enemy within 10 m: it bounces to 3 more enemies within 10 m, then flies back to his hand, hitting everything on the way. Every caught ball that scored adds Heat: +5% damage, up to +50%. Its Heat never cools. At full Heat every catch is a dunk: 150% of its damage to everything within 3.5 m, thrown back.")
	# the Build tab: the amount row counts the bounces a throw makes (ricochet_any.count + amount - 1), the ricochet row
	# what each one strikes for
	assert_int(b3.ball_bounces()).is_equal(3)
	assert_int(sd.ball_bounces()).is_equal(3)
	var tab := {}
	for r: Dictionary in b3.stat_rows():
		tab[str(r["stat"])] = r
	assert_str(str(tab["amount"]["name"])).is_equal("bounces")
	assert_str(str(tab["amount"]["value"])).is_equal("3")
	assert_str(str(tab["ricochet_any"]["name"])).is_equal("each bounce")
	assert_str(str(tab["ricochet_any"]["value"])).is_equal("85%")
	var d := _ball_def()
	d.levels = [[], [], [Effect.make("amount", "add", 1.0)], [], []]
	var rows := TextGen.weapon_changes(d, 2, 3)
	var amt: Array = rows.filter(func(r: Dictionary) -> bool: return str(r["stat"]) == "amount")
	assert_int(amt.size()).is_equal(1)
	assert_str(str(amt[0]["name"])).is_equal("Bounces")
	assert_str(str(amt[0]["before"])).is_equal("1")
	assert_str(str(amt[0]["after"])).is_equal("2")
