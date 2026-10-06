extends GdUnitTestSuite

## Pass 48, lane L3: the Hammer's paths (Thor's Wrath zaps only outside the blast and none when nobody stands out there,
## Giant Slayer only on big game), the Earthshaker redone (lightning down the cracks and onto what stands by them, the
## roll along the cracks, Giant Slayer on every blow, the rebuilt model still swinging with its own proportions), the
## Land Mine's (Wide Reach crouches, leaps on an arc onto a creature and blows where it lands, Bouncing Betty pops at the
## landing, Extra Supply doubles about a quarter of the drops, the Jackrabbit springs from 6 m, always double, and hops on
## for a 60% blast), the Gravity Gun's Repulsor (harder, wider, purple), the Guitarra's Tinnitus (every third hit on a
## creature, counted by its serial), priority aim in the Thruster and the Turret, and every evolution against the weapon
## at its top level with all three of its mutations.

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
var bursts := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	bursts += 1
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
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
"""

const DT := 1.0 / 60.0
const EAST := Vector3(1, 0, 0)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks. Astro's run: no
## crits to roll.
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam}


## A tough creature standing where it was put.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton", elite: EliteModDef = null) -> int:
	var i := em.spawn(id, at, elite, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	return i


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, id: String, muts: Array = [], level := 1) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(_inst(id, muts, level), w["g"])
	return b


## Sets params[key][sub] on this weapon alone: a mutation's block in WeaponInstance.params is the MutationDef's own
## dictionary (merge_params hands it over as it is), so it is copied first, never written into.
func _set_param(inst: WeaponInstance, key: String, sub: String, value: Variant) -> void:
	var d: Dictionary = (inst.params.get(key, {}) as Dictionary).duplicate(true)
	d[sub] = value
	inst.params[key] = d


## What a hit of `amount` takes off creature `i` (its damage reduction in).
func _taken(em: EnemyManager, i: int, amount: float) -> float:
	return amount * (1.0 - em.dr[i])


# ---------------------------------------------------------------- priority aim

func test_the_spear_sabre_and_turrets_go_for_the_strongest_close_one() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var small := _creature(em, Vector3(1.6, 0, 0), 1.0)
	var big := _creature(em, Vector3(0, 0, 2.4), 10.0)
	# a thin crowd far off, so the mean max HP is the small ones'
	for k in range(3):
		_creature(em, Vector3(-40, 0, -10.0 * k), 1.0)
	em._rebuild_grid()
	em.refresh_crowd_stats()
	assert_int(em.nearest_index(Vector3.ZERO, 5.0)).is_equal(small)
	# the Sabre (priority): the big one, half again as far
	var sabre: Thruster = _behaviour(w, Thruster.new(), "sabre")
	assert_str(sabre.inst.def.targeting).is_equal("priority")
	assert_bool(sabre._fire()).is_true()
	assert_int(sabre.target).is_equal(big)
	assert_float(sabre._dir.dot(Vector3(0, 0, 1))).is_greater(0.99)
	# the Spear (the Pike) the same
	var pike: Thruster = _behaviour(w, Thruster.new(), "pike")
	assert_bool(pike._fire()).is_true()
	assert_int(pike.target).is_equal(big)
	# a blade that aims at the nearest takes the small one
	var near_def: WeaponDef = Registry.weapon("sabre").duplicate()
	near_def.targeting = "nearest"
	var plain := Thruster.new()
	(w["g"] as Node).add_child(plain)
	var pi := WeaponInstance.new(near_def, 1)
	pi.rebuild(Run.player_sheet, [pi])
	plain.setup(pi, w["g"])
	assert_bool(plain._fire()).is_true()
	assert_int(plain.target).is_equal(small)
	# a turret's new target is the strong one too (it then keeps it while it lives and stays in range)
	em.pos[small] = Vector3(3, 0, 0)
	em.pos[big] = Vector3(0, 0, 5)
	em._rebuild_grid()
	var sp: Spawner = _behaviour(w, Spawner.new(), "turret_buddy")
	var t := Turret.new()
	t.setup(sp, sp._proto, sp._turret_mesh, sp._turret_mat)
	(w["g"] as Node).add_child(t)
	t.global_position = Vector3.ZERO
	t._process(DT)
	assert_int(t.target()).is_equal(big)


# ---------------------------------------------------------------- the Hammer: Thor's Wrath

func _smasher(w: Dictionary, id: String, muts: Array = []) -> Smasher:
	return _behaviour(w, Smasher.new(), id, muts)


func test_thors_wrath_zaps_nobody_when_nobody_stands_outside_the_blast() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var at := Vector3(3, 0, 0)
	var inside := _creature(em, at + Vector3(0.5, 0, 0))
	var far := _creature(em, at + Vector3(7.6, 0, 0))
	em._rebuild_grid()
	var s := _smasher(w, "hammer", ["thors_wrath"])
	_set_param(s.inst, "thor", "chance", 1.0)
	var r := s._blast_r()
	var hp_far: float = em.hp[far]
	s._impact(at, r)
	# the one in the blast took the blow; the one past the reach nothing; no bolt went anywhere
	assert_float(em.hp[inside]).is_less(em.max_hp[inside])
	assert_float(em.hp[far]).is_equal(hp_far)
	assert_int(s.zaps).is_equal(0)
	assert_array(s.zap_targets(at, r, 7.0, 3)).is_empty()


func test_thors_wrath_zaps_the_three_nearest_outside_the_blast_only() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var at := Vector3(0, 0, -3)
	var s := _smasher(w, "hammer", ["thors_wrath"])
	var r := s._blast_r()
	assert_float(r).is_less(2.0)
	var inside := [_creature(em, at + Vector3(0.4, 0, 0)), _creature(em, at + Vector3(-0.9, 0, 0.3))]
	var zapped := [_creature(em, at + Vector3(2.6, 0, 0)), _creature(em, at + Vector3(0, 0, -3.6)), _creature(em, at + Vector3(-4.4, 0, 0))]
	var spared := [_creature(em, at + Vector3(0, 0, 6.2)), _creature(em, at + Vector3(7.5, 0, 0))]
	em._rebuild_grid()
	assert_array(s.zap_targets(at, r, 7.0, 3)).is_equal(zapped)
	var hp := {}
	for i: int in inside + zapped + spared:
		hp[i] = em.hp[i]
	var dmg: float = s.stat("damage")
	_set_param(s.inst, "thor", "chance", 1.0)
	var bolts0: int = (w["fx"] as Fx)._bolts.size()
	s._impact(at, r)
	assert_int(s.zaps).is_equal(3)
	assert_int((w["fx"] as Fx)._bolts.size() - bolts0).is_equal(3)
	for i: int in zapped:
		assert_float(float(hp[i]) - em.hp[i]).is_equal_approx(_taken(em, i, dmg * 0.35), 0.01)
	for i: int in inside:
		assert_float(float(hp[i]) - em.hp[i]).is_equal_approx(_taken(em, i, dmg), 0.01)
	for i: int in spared:
		assert_float(em.hp[i]).is_equal(float(hp[i]))
	# a blow that does not roll it throws no lightning
	_set_param(s.inst, "thor", "chance", 0.0)
	s._impact(at, r)
	assert_int(s.zaps).is_equal(3)


# ---------------------------------------------------------------- the Hammer: Giant Slayer

func test_giant_slayer_crushes_only_big_game() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var at := Vector3(3, 0, 0)
	var plain := _creature(em, at + Vector3(0.3, 0, 0))
	var elite := _creature(em, at + Vector3(-0.3, 0, 0), 20.0, "dune_scorpion")
	var mods: Array = Registry.elites_list()
	var modded := _creature(em, at + Vector3(0, 0, 0.4), 50.0, "skeleton", mods[0] if not mods.is_empty() else null)
	em._rebuild_grid()
	assert_bool(em.is_big_game(elite)).is_true()
	assert_bool(em.is_big_game(plain)).is_false()
	var s := _smasher(w, "hammer", ["giant_slayer"])
	var dmg: float = s.stat("damage")
	var r := s._blast_r()
	var hp := {plain: em.hp[plain], elite: em.hp[elite], modded: em.hp[modded]}
	var shakes0: int = (w["cam"] as Node).shakes
	_set_param(s.inst, "giant_slayer", "chance", 1.0)
	s._impact(at, r)
	assert_float(float(hp[plain]) - em.hp[plain]).is_equal_approx(_taken(em, plain, dmg), 0.01)
	assert_float(float(hp[elite]) - em.hp[elite]).is_equal_approx(_taken(em, elite, dmg * 2.5), 0.01)
	if not mods.is_empty():
		assert_float(float(hp[modded]) - em.hp[modded]).is_equal_approx(_taken(em, modded, dmg * 2.5), 0.01)
	assert_int(s.crushes).is_equal(2 if not mods.is_empty() else 1)
	# a crush kicks the camera on top of the blow's own shake
	assert_int((w["cam"] as Node).shakes - shakes0).is_greater_equal(2)
	# a blow that does not roll it is a plain blow for everyone
	_set_param(s.inst, "giant_slayer", "chance", 0.0)
	var e1: float = em.hp[elite]
	s._impact(at, r)
	assert_float(e1 - em.hp[elite]).is_equal_approx(_taken(em, elite, dmg), 0.01)
	# the plain hammer never crushes
	var h := _smasher(w, "hammer")
	assert_bool(h.slayer_rolls()).is_false()


# ---------------------------------------------------------------- the Earthshaker

func test_the_earthshaker_runs_lightning_down_its_cracks() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var s := _smasher(w, "earthshaker")
	var qk: Dictionary = s._smash_dict("quake")
	assert_bool(qk.get("zap") is Dictionary).is_true()
	assert_bool(qk.get("roll") is Dictionary).is_true()
	var at := Vector3(0, 0, 0)
	var length: float = float(qk["length"]) * s.stat("area")
	var by := _creature(em, Vector3(3.0, 0, 1.2))
	var on := _creature(em, Vector3(2.0, 0, 0.1))
	var off := _creature(em, Vector3(3.0, 0, 2.2))
	var past_end := _creature(em, Vector3(length + 1.2, 0, 0))
	em._rebuild_grid()
	var dmg: float = s.stat("damage")
	var hp := {by: em.hp[by], on: em.hp[on], off: em.hp[off], past_end: em.hp[past_end]}
	var bolts0: int = (w["fx"] as Fx)._bolts.size()
	s._crack_lightning(at, [EAST], length, qk["zap"], dmg)
	# within 1.5 m of the crack (on it, beside it, past its end): half the hit, once; further off nothing
	for i: int in [by, on, past_end]:
		assert_float(float(hp[i]) - em.hp[i]).is_equal_approx(_taken(em, i, dmg * 0.5), 0.01)
	assert_float(em.hp[off]).is_equal(float(hp[off]))
	assert_int(s.crack_zaps).is_equal(3)
	# a bolt down the crack and a jump to each of the three
	assert_int((w["fx"] as Fx)._bolts.size() - bolts0).is_equal(4)


func test_the_earthshakers_roll_runs_along_the_cracks_a_beat_later() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var s := _smasher(w, "earthshaker")
	var qk: Dictionary = s._smash_dict("quake")
	var roll: Dictionary = qk["roll"]
	var length: float = float(qk["length"]) * s.stat("area")
	var near := _creature(em, Vector3(1.0, 0, 0.1))
	var far := _creature(em, Vector3(length - 0.5, 0, -0.1))
	var beside := _creature(em, Vector3(3.0, 0, 2.0))
	em._rebuild_grid()
	var dmg: float = s.stat("damage")
	var hp := {near: em.hp[near], far: em.hp[far], beside: em.hp[beside]}
	s._roll_crack(Vector3.ZERO, EAST, length, float(qk["width"]), roll)
	# nothing yet: it comes a beat after the impact
	s._tick_later(float(roll["delay"]) - 0.05)
	assert_float(em.hp[near]).is_equal(float(hp[near]))
	# the near end first, the far end a few beats later
	s._tick_later(0.06)
	assert_float(float(hp[near]) - em.hp[near]).is_equal_approx(_taken(em, near, dmg * 0.4), 0.01)
	assert_float(em.hp[far]).is_equal(float(hp[far]))
	for k in range(int(roll["steps"]) + 1):
		s._tick_later(float(roll["step"]))
	assert_float(float(hp[far]) - em.hp[far]).is_equal_approx(_taken(em, far, dmg * 0.4), 0.01)
	# once each, and nothing off the crack
	assert_float(float(hp[near]) - em.hp[near]).is_equal_approx(_taken(em, near, dmg * 0.4), 0.01)
	assert_float(em.hp[beside]).is_equal(float(hp[beside]))
	assert_int(s.rolls).is_equal(2)
	assert_bool(s._later.is_empty()).is_true()


func test_the_earthshaker_always_crushes_big_game() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var at := Vector3(3, 0, 0)
	var elite := _creature(em, at, 50.0, "dune_scorpion")
	em._rebuild_grid()
	var s := _smasher(w, "earthshaker")
	for k in range(6):
		assert_bool(s.slayer_rolls()).is_true()
	# with the Giant Slayer path carried on it too (its 35% merged over), still every blow
	var s2 := _smasher(w, "earthshaker", ["thors_wrath", "giant_slayer", "aftershock"])
	for k in range(6):
		assert_bool(s2.slayer_rolls()).is_true()
	var hp0: float = em.hp[elite]
	s._impact(at, s._blast_r())
	# the blow at 2.5 times, then whatever the cracks add
	assert_float(hp0 - em.hp[elite]).is_greater_equal(_taken(em, elite, s.stat("damage") * 2.5) - 0.01)
	assert_int(s.crushes).is_equal(1)


func test_the_rebuilt_earthshaker_swings_with_its_own_proportions() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var c := _creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	var s := _smasher(w, "earthshaker")
	assert_object(s._proto).is_not_null()
	assert_bool(s._fire()).is_true()
	var sw: Dictionary = s._swings[0]
	var it: Dictionary = sw["it"]
	var handle: Node3D = it["handle"]
	var head: Node3D = it["head"]
	assert_object(handle).is_not_null()
	assert_object(head).is_not_null()
	var rest: Vector3 = it["head_rest"]
	var axis: int = it["axis"]
	var hp0: float = em.hp[c]
	var t := 0.0
	while not sw["hit"] and t < 2.0:
		s._tick(DT)
		t += DT
	assert_float(em.hp[c]).is_less(hp0)
	s._tick(DT * 4.0)
	# the handle reached out to the strike along its own length (no fatter than the model), and the head kept its shape
	var hs: Vector3 = handle.scale
	var hr: Vector3 = it["handle_rest"]
	assert_float(hs[axis] / hr[axis]).is_greater(1.5)
	for k in range(3):
		if k != axis:
			assert_float(hs[k]).is_equal_approx(hr[k], 0.001)
	assert_float((head.scale.x / head.scale.y) / (rest.x / rest.y)).is_equal_approx(1.0, 0.01)
	# the handle's far end meets the head, out over the strike
	var box: AABB = (handle as MeshInstance3D).get_aabb()
	var end := Vector3.ZERO
	end[axis] = box.position[axis]
	var tip: Vector3 = handle.global_transform * end
	assert_float(tip.distance_to(head.global_position)).is_less(0.05)
	assert_float(head.global_position.distance_to((it["node"] as Node3D).global_position)).is_greater(2.0)


# ---------------------------------------------------------------- the Land Mine

func _layer(w: Dictionary, id: String, muts: Array = []) -> MineLayer:
	return _behaviour(w, MineLayer.new(), id, muts)


func _drop_one(ml: MineLayer, at: Vector3) -> Mine:
	(ml.player as Node3D).global_position = at
	assert_bool(ml._fire()).is_true()
	var all := ml.mines()
	# the newest one laid where the hero stands (pass 50: a doubled drop lays its second mine up to 1.5 m off at random,
	# and returning that one made the Jackrabbit test hang on the shared random sequence)
	for k in range(all.size() - 1, -1, -1):
		var m: Mine = all[k]
		if Vector2(m.global_position.x - at.x, m.global_position.z - at.z).length() < 0.01:
			return m
	return all[all.size() - 1]


func test_wide_reach_leaps_onto_a_creature_and_blows_where_it_lands() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ml := _layer(w, "land_mine", ["wide_reach"])
	var mine := _drop_one(ml, Vector3.ZERO)
	# 2.8 m since pass 51 (Garry: "a bit too wide")
	assert_float(float(mine.spring()["sense"])).is_equal_approx(2.8, 0.001)
	# a creature 2.6 m off, walking across at 2 m/s
	var c := _creature(em, Vector3(2.6, 0, 0))
	em.vel[c] = Vector3(0, 0, 2.0)
	em._rebuild_grid()
	var hp0: float = em.hp[c]
	mine.step(DT)
	assert_int(mine.state).is_equal(Mine.ST_CROUCH)
	assert_int(mine.target).is_equal(c)
	# it crouches: squashed down, wider
	var t := DT
	while mine.state == Mine.ST_CROUCH and t < 1.0:
		mine.step(DT)
		t += DT
	assert_float(t).is_between(0.25 - DT, 0.25 + DT * 3.0)
	assert_int(mine.state).is_equal(Mine.ST_SPRING)
	# up on its arc, to where the creature will be when it comes down
	var aim: Vector3 = mine._to
	assert_float(aim.distance_to(Vector3(2.6, 0, 0.8))).is_less(0.05)
	var top := 0.0
	var t2 := 0.0
	while mine.state == Mine.ST_SPRING and t2 < 1.0:
		mine.step(DT)
		t2 += DT
		top = maxf(top, mine.global_position.y)
	assert_float(t2).is_between(0.4 - DT, 0.4 + DT * 3.0)
	assert_float(top).is_between(1.2, 1.41)
	# and it blew where it landed
	assert_int(mine.blasts).is_equal(1)
	assert_float(Vector2(mine.global_position.x - aim.x, mine.global_position.z - aim.z).length()).is_less(0.01)
	assert_float(em.hp[c]).is_less(hp0)
	assert_bool(mine.is_queued_for_deletion()).is_true()


func test_a_plain_mine_waits_to_be_stepped_on() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ml := _layer(w, "land_mine")
	var mine := _drop_one(ml, Vector3.ZERO)
	assert_bool(mine.spring().is_empty()).is_true()
	var c := _creature(em, Vector3(2.0, 0, 0))
	em._rebuild_grid()
	for k in range(30):
		mine.step(DT)
	assert_int(mine.state).is_equal(Mine.ST_ARMED)
	em.pos[c] = Vector3(0.3, 0, 0)
	em._rebuild_grid()
	mine.step(DT)
	assert_int(mine.blasts).is_equal(1)


func test_wide_reach_with_bouncing_betty_pops_at_the_landing() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ml := _layer(w, "land_mine", ["wide_reach", "bouncing_betty"])
	var mine := _drop_one(ml, Vector3.ZERO)
	# inside the 2.8 m ring (pass 51: it was 3.5, and the creature stood 3 m off)
	var c := _creature(em, Vector3(0, 0, -2.4))
	em._rebuild_grid()
	var base_area: float = mine.area
	var t := 0.0
	while mine.state != Mine.ST_POP and t < 2.0:
		mine.step(DT)
		t += DT
	assert_int(mine.state).is_equal(Mine.ST_POP)
	assert_int(mine.blasts).is_equal(0)
	# landed by the creature, then up to chest height, wider and harder
	assert_float(Vector2(mine.global_position.x, mine.global_position.z + 2.4).length()).is_less(0.05)
	assert_float(mine.area).is_equal_approx(base_area * 1.5, 0.001)
	var top := 0.0
	while mine.blasts == 0 and t < 3.0:
		mine.step(DT)
		t += DT
		top = maxf(top, mine.global_position.y)
	assert_int(mine.blasts).is_equal(1)
	assert_float(top).is_equal_approx(1.2, 0.05)
	assert_float(em.hp[c]).is_less(em.max_hp[c])


func test_springing_mines_share_out_the_crowd() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ml := _layer(w, "land_mine", ["wide_reach"])
	var a := _drop_one(ml, Vector3(0, 0, 0))
	var b := _drop_one(ml, Vector3(0.5, 0, 0))
	var c1 := _creature(em, Vector3(2.5, 0, 0))
	var c2 := _creature(em, Vector3(3.2, 0, 0))
	em._rebuild_grid()
	a.step(DT)
	b.step(DT)
	assert_int(a.target).is_not_equal(b.target)
	assert_array([a.target, b.target]).contains_exactly_in_any_order([c1, c2])


func test_extra_supply_doubles_about_a_quarter_of_the_drops() -> void:
	var w := _world()
	var ml := _layer(w, "land_mine", ["extra_supply"])
	seed(4848)
	for k in range(400):
		ml._fire()
	assert_int(ml.drops).is_equal(400)
	assert_int(ml.doubled).is_between(70, 130)
	# the cap counts every mine laid
	assert_int(ml.mines().size()).is_less_equal(int(ml.inst.params["max_mines"]))
	# a doubled drop lays twice the amount
	var before := ml.mines().size()
	ml.inst.params["extra_supply"] = 1.0
	ml.inst.params["max_mines"] = 100
	ml._fire()
	assert_int(ml.mines().size() - before).is_equal(2 * ml.stat_int("amount"))
	# without the path, never
	var plain := _layer(w, "land_mine")
	for k in range(50):
		plain._fire()
	assert_int(plain.doubled).is_equal(0)


func test_jackrabbit_mines_spring_from_six_metres_double_and_hop_on() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ml := _layer(w, "jackrabbit_mines", ["wide_reach", "extra_supply", "bouncing_betty"])
	# always double, the evolution's spring over the carried Wide Reach's
	for k in range(5):
		ml._fire()
	assert_int(ml.doubled).is_equal(ml.drops)
	for m: Mine in ml.mines():
		m.queue_free()
	var mine := _drop_one(ml, Vector3.ZERO)
	assert_float(float(mine.spring()["sense"])).is_equal(6.0)
	# the one it springs at, 5.5 m off, and another 4.8 m past it (outside the burst, inside the hop)
	var first := _creature(em, Vector3(5.5, 0, 0))
	var second := _creature(em, Vector3(10.3, 0, 0))
	em._rebuild_grid()
	var hp2: float = em.hp[second]
	var t := 0.0
	while mine.blasts == 0 and t < 3.0:
		mine.step(DT)
		t += DT
	# burst at chest height, over the first one
	assert_int(mine.blasts).is_equal(1)
	assert_float(mine.global_position.y).is_greater(1.0)
	assert_float(em.hp[first]).is_less(em.max_hp[first])
	assert_float(em.hp[second]).is_equal(hp2)
	# the casing hops on to the next one on a small arc and blows again at 60%
	assert_int(mine.state).is_equal(Mine.ST_HOP)
	assert_int(mine.target).is_equal(second)
	while mine.blasts == 1 and t < 5.0:
		mine.step(DT)
		t += DT
	assert_int(mine.blasts).is_equal(2)
	assert_float(Vector2(mine.global_position.x - 10.3, mine.global_position.z).length()).is_less(0.05)
	assert_float(hp2 - em.hp[second]).is_equal_approx(_taken(em, second, ml.stat("damage") * 0.6), 0.01)
	assert_bool(mine.is_queued_for_deletion()).is_true()


func test_a_jackrabbit_with_nobody_to_hop_to_is_done() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var ml := _layer(w, "jackrabbit_mines")
	var mine := _drop_one(ml, Vector3.ZERO)
	var only := _creature(em, Vector3(0, 0, 0.3))
	em._rebuild_grid()
	var t := 0.0
	while not mine.is_queued_for_deletion() and t < 3.0:
		mine.step(DT)
		t += DT
	assert_int(mine.blasts).is_equal(1)
	assert_float(em.hp[only]).is_less(em.max_hp[only])


# ---------------------------------------------------------------- the Gravity Gun: Repulsor

func test_repulsor_throws_harder_wider_and_purple() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var plain: GravityGun = _behaviour(w, GravityGun.new(), "gravity_gun")
	var rep: GravityGun = _behaviour(w, GravityGun.new(), "gravity_gun", ["repulsor"])
	assert_float(rep._blast_r()).is_equal_approx(plain._blast_r() * 1.4, 0.001)
	assert_float(rep.stat("damage")).is_equal_approx(plain.stat("damage") * 1.15, 0.001)
	assert_bool(rep.blast_colour().is_equal_approx(Color(0.62, 0.3, 0.95))).is_true()
	assert_bool(plain.blast_colour().is_equal_approx(Color(0.62, 0.3, 0.95))).is_false()
	var at := Vector3(0, 0, -4)
	var a := _creature(em, at + Vector3(1.0, 0, 0))
	em._rebuild_grid()
	plain._blast(at, plain._blast_r(), 1.0)
	var k1: float = em.kb[a].length()
	em.kb[a] = Vector3.ZERO
	rep._blast(at, rep._blast_r(), 1.0)
	var k2: float = em.kb[a].length()
	assert_float(k2 / k1).is_equal_approx(2.5, 0.01)
	# one past the plain blast's rim and inside the Repulsor's is caught too
	var rim := _creature(em, at + Vector3(0, 0, plain._blast_r() * 1.2))
	em._rebuild_grid()
	var hp0: float = em.hp[rim]
	plain._blast(at, plain._blast_r(), 5.0)
	assert_float(em.hp[rim]).is_equal(hp0)
	rep._blast(at, rep._blast_r(), 5.0)
	assert_float(em.hp[rim]).is_less(hp0)
	# on the Singularity the black hole's pop takes it
	var v := Vortex.new()
	v.setup(w["g"], rep.inst, 3.2, {"knock_mult": 2.5, "throw_mult": 1.4}, 10.0)
	assert_float(v.knock_mult).is_equal(2.5)
	assert_float(v.throw_mult).is_equal(1.4)
	v.free()


# ---------------------------------------------------------------- the Guitarra: Tinnitus

func _cone(w: Dictionary, id: String, muts: Array = []) -> ConeWave:
	var cw: ConeWave = _behaviour(w, ConeWave.new(), id, muts)
	cw.inst.params["familiar"] = {"radius": 0.0, "height": 1.5, "bob": 0.0}
	cw._familiar.global_position = Vector3(0, 1.5, 0)
	return cw


## Lets a bounced creature down at once, so the next chord can lift it again.
func _land(em: EnemyManager, i: int) -> void:
	em.lift_t[i] = 0.0
	em.lift_mode[i] = 0
	em.lift_h[i] = 0.0


func test_tinnitus_rings_every_third_hit_on_the_same_creature() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var cw := _cone(w, "guitarra", ["tinnitus"])
	var dmg: float = cw.stat("damage")
	var drops: Array = []
	var knocks: Array = []
	for k in range(6):
		var hp0: float = em.hp[i]
		cw._wave(EAST, 1.0, false)
		drops.append(hp0 - em.hp[i])
		knocks.append((em.lift_knock[i] as Vector3).length())
		_land(em, i)
	for k in range(6):
		var rang := k == 2 or k == 5
		assert_float(float(drops[k])).override_failure_message("hit %d" % (k + 1)).is_equal_approx(_taken(em, i, dmg * (2.0 if rang else 1.0)), 0.01)
	assert_float(float(knocks[2]) / float(knocks[0])).is_equal_approx(1.5, 0.01)
	assert_int(cw.rings).is_equal(2)
	# a new creature in the slot starts from nothing: two hits on the old one, then it is another
	cw._wave(EAST, 1.0, false)
	_land(em, i)
	cw._wave(EAST, 1.0, false)
	_land(em, i)
	em.serial[i] += 1000
	var hp1: float = em.hp[i]
	cw._wave(EAST, 1.0, false)
	assert_float(hp1 - em.hp[i]).is_equal_approx(_taken(em, i, dmg), 0.01)
	assert_int(cw.rings).is_equal(2)


func test_tinnitus_counts_each_creature_apart() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(3, 0, 0))
	var cw := _cone(w, "guitarra", ["tinnitus"])
	em._rebuild_grid()
	cw._wave(EAST, 1.0, false)
	_land(em, a)
	cw._wave(EAST, 1.0, false)
	_land(em, a)
	# a second creature walks in for the third chord: it is a first hit on it, the third on the other
	var b := _creature(em, Vector3(4, 0, 0.3))
	em._rebuild_grid()
	var hb: float = em.hp[b]
	cw._wave(EAST, 1.0, false)
	assert_int(cw.rings).is_equal(1)
	assert_float(hb - em.hp[b]).is_equal_approx(_taken(em, b, cw.stat("damage")), 0.01)
	# the plain Guitarra never rings
	var plain := _cone(w, "guitarra")
	for k in range(4):
		plain._wave(EAST, 1.0, false)
		_land(em, a)
		_land(em, b)
	assert_int(plain.rings).is_equal(0)


# ---------------------------------------------------------------- the texts and the evolutions

## Every evolution here against its weapon at the top level with all three of its mutations, on the run's estimate.
func test_every_evolution_here_beats_its_top_weapon() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	for wid in ["hammer", "land_mine", "guitarra"]:
		var wd: WeaponDef = Registry.weapon(wid)
		var muts: Array = Registry.mutations_of(wid).map(func(m: MutationDef) -> String: return m.id)
		var top := _inst(wid, muts, wd.max_level)
		var evo := _inst(wd.evolves_into, muts)
		assert_float(evo.dps_estimate()).override_failure_message("%s %.1f against %s %.1f" % [evo.def.id, evo.dps_estimate(), wid, top.dps_estimate()]).is_greater(top.dps_estimate())
	Run.end()


func test_the_new_paths_say_what_they_do() -> void:
	var t: MutationDef = Registry.mutation("thors_wrath")
	assert_str(t.text).contains("7 m")
	assert_str(t.text).contains("35%")
	# pass 49 (Garry): both at 50%
	assert_float(float(t.params["thor"]["chance"])).is_equal(0.5)
	assert_str(t.text).starts_with("Half of all impacts")
	assert_float(float(Registry.mutation("giant_slayer").params["giant_slayer"]["chance"])).is_equal(0.5)
	assert_str(Registry.mutation("giant_slayer").text).starts_with("Half of all impacts")
	assert_str(Registry.mutation("giant_slayer").text).contains("2.5")
	assert_str(Registry.mutation("wide_reach").text).contains("2.8 m")
	assert_float(float(Registry.mutation("extra_supply").params["extra_supply"])).is_equal(0.25)
	assert_str(Registry.mutation("repulsor").text).contains("2.5")
	assert_str(Registry.mutation("repulsor").text).contains("40%")
	assert_str(Registry.mutation("repulsor").text).contains("15%")
	assert_str(Registry.mutation("tinnitus").text).contains("third")
	for id in ["thors_wrath", "giant_slayer", "wide_reach", "extra_supply", "repulsor", "tinnitus"]:
		assert_bool(Registry.mutation(id).hidden).override_failure_message(id).is_false()
	# the paths of the four weapons: element, volume, motion
	for wid in ["hammer", "land_mine", "gravity_gun", "guitarra"]:
		var kinds: Array = Registry.mutations_of(wid).map(func(m: MutationDef) -> String: return m.mutation_kind)
		assert_array(kinds).override_failure_message(wid + " " + str(kinds)).is_equal(["element", "volume", "motion"])
