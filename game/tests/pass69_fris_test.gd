extends GdUnitTestSuite

## Pass 69, lane FRIS: the Frisbee (core/behaviors/Frisbee.gd) in a fake game with the real crowd. The bend grows with the
## amount; a disc flies its whole range through every creature on its way, then glides down and goes; the drop-off and
## its floor; Carry takes only the first creature it hits, never an Elite or a boss, one a disc, and sets it down where the
## disc came down; Poison Razors poisons; Trick Shot's proc_mult reaches life steal, crit, Cold Snap and Vulture for the
## frisbee only; the Flying Saucer loops exactly once; the content's shape and words.

const FRIS := preload("res://core/behaviors/Frisbee.gd")

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
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	sands += 1
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var max_hp := 100.0
var heals := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	heals += 1
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.debug_clear_items()


func after_test() -> void:
	Run.debug_clear_items()


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
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	em.screen_filter_on = false
	g.enemies = em
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.dr[i] = 0.0
	return i


## The frisbee held in the run at `level` with `muts`, its crit chance nought so the damage sums are exact.
func _held(level := 1, muts: Array = [], wid := "frisbee") -> WeaponInstance:
	Run.debug_set_item("evolution" if Registry.weapon(wid).is_evolution else "weapon", wid, level)
	for m: String in muts:
		Run.debug_set_item("mutation", m, 1)
	_no_crits()
	return Run.weapon_instance(wid)


func _no_crits() -> void:
	Run.player_sheet.add_effect(Effect.make("crit_chance", "set", 0.0), "p69 test")


func _behavior(w: Dictionary, inst: WeaponInstance) -> Node:
	var b: Node = FRIS.new()
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


## Steps the discs until none is left, at most `most` ticks; the crowd's grid rebuilt every tick as the game does.
func _fly_out(w: Dictionary, b: Node, most := 900) -> int:
	var em: EnemyManager = w["em"]
	var steps := 0
	while not (b.get("discs") as Array).is_empty() and steps < most:
		em._rebuild_grid()
		b._tick(DT)
		steps += 1
	return steps


# ---------------------------------------------------------------- the arc

func test_the_bend_grows_with_the_amount() -> void:
	var pr: Dictionary = Registry.weapon("frisbee").params
	assert_float(FRIS.bend_deg(1, pr)).is_equal_approx(25.0, 0.001)
	assert_float(FRIS.bend_deg(2, pr)).is_equal_approx(37.0, 0.001)
	assert_float(FRIS.bend_deg(3, pr)).is_equal_approx(49.0, 0.001)
	# a disc leaves its line at that bend, to one side or the other
	var w := _world()
	var b := _behavior(w, _held())
	var aim := Vector3(1, 0, 0)
	for n in [1, 3]:
		for side in [-1.0, 1.0]:
			var d: Dictionary = b._launch(aim, 8.0, n, side)
			var h: Vector3 = b.heading(d)
			var ang := rad_to_deg(aim.signed_angle_to(h, Vector3.UP))
			assert_float(absf(ang)).is_equal_approx(FRIS.bend_deg(n, pr), 0.01)
			assert_float(signf(ang)).is_equal(side)
	# the turn brings it back over its line about where the creature stood (the circle through both)
	var d2: Dictionary = b._launch(Vector3(0, 0, -1), 8.0, 1, 1.0)
	var start: Vector3 = d2["pos"]
	var crossed := Vector3.INF
	var prev_x: float = start.x
	for k in range(200):
		b._fly(d2, DT)
		var p: Vector3 = d2["pos"]
		if signf(p.x) != signf(prev_x) and absf(p.x - prev_x) < 1.0 and float(d2["s"]) > 1.0:
			crossed = p
			break
		prev_x = p.x
	assert_bool(crossed != Vector3.INF).is_true()
	assert_float(-crossed.z).is_between(7.0, 9.0)


func test_a_volley_fans_out_and_turns_both_ways_at_random() -> void:
	var w := _world()
	var inst := _held(5)
	assert_int(inst.stat_int("amount")).is_equal(3)
	var b := _behavior(w, inst)
	var sides := {}
	for k in range(20):
		assert_bool(b._fire()).is_true()
		for d: Dictionary in b.discs:
			sides[float(d["side"])] = true
		var dirs: Array = (b.discs as Array).map(func(d: Dictionary) -> Vector3: return d["dir0"])
		assert_int(dirs.size()).is_equal(3)
		# three lines 16 degrees apart round the aim
		assert_float(rad_to_deg((dirs[0] as Vector3).angle_to(dirs[2]))).is_equal_approx(32.0, 0.01)
		_fly_out(w, b)
	assert_int(sides.size()).is_equal(2)
	assert_int(b.throws).is_equal(20)


# ---------------------------------------------------------------- the flight

func test_it_flies_its_whole_range_through_every_hit_then_glides_down_and_goes() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held()
	var b := _behavior(w, inst)
	var range_m := inst.stat("range")
	assert_float(range_m).is_equal_approx(12.0, 0.001)
	# a straight disc (no bend) along -Z through a line of tough creatures
	inst.params["bend_deg"] = 0.0
	inst.params["bend_per_extra"] = 0.0
	var ids: Array = []
	for k in range(6):
		ids.append(_creature(em, Vector3(0, 0, -1.5 - 1.6 * k), 200.0))
	em._rebuild_grid()
	var d: Dictionary = b._launch(Vector3(0, 0, -1), 12.0, 1, 1.0)
	var steps := 0
	while int(d["phase"]) == 0 and steps < 600:
		em._rebuild_grid()
		b._tick(DT)
		steps += 1
	# it never stopped: the whole range flown, every creature in its way cut once
	assert_float(float(d["s"])).is_equal_approx(range_m, 0.001)
	assert_int(int(d["n"])).is_equal(6)
	for i: int in ids:
		assert_float(em.hp[i]).is_less(em.max_hp[i])
	# about range / speed seconds in the air
	var sp := inst.stat("speed")
	assert_float(float(steps) * DT).is_between(range_m / sp - 0.05, range_m / sp + 0.1)
	# gliding, it hits nothing: a creature under it now is left alone
	var late := _creature(em, d["pos"] as Vector3, 200.0)
	em._rebuild_grid()
	_fly_out(w, b)
	assert_float(em.hp[late]).is_equal(em.max_hp[late])
	assert_bool((b.discs as Array).is_empty()).is_true()


func test_damage_drops_off_by_creature_down_to_its_floor() -> void:
	var pr: Dictionary = Registry.weapon("frisbee").params
	assert_float(FRIS.falloff_mult(0, pr)).is_equal_approx(1.0, 0.0001)
	assert_float(FRIS.falloff_mult(1, pr)).is_equal_approx(0.85, 0.0001)
	assert_float(FRIS.falloff_mult(2, pr)).is_equal_approx(0.7225, 0.0001)
	# it never stops, so a floor: the tenth creature on takes a quarter (0.85^9 = 0.23 is under it)
	assert_float(FRIS.falloff_mult(8, pr)).is_equal_approx(pow(0.85, 8), 0.0001)
	assert_float(FRIS.falloff_mult(9, pr)).is_equal_approx(0.25, 0.0001)
	assert_float(FRIS.falloff_mult(30, pr)).is_equal_approx(0.25, 0.0001)
	# in flight: each creature down the line takes 15% less than the one before
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held()
	var b := _behavior(w, inst)
	inst.params["bend_deg"] = 0.0
	var ids: Array = []
	for k in range(4):
		ids.append(_creature(em, Vector3(0, 0, -2.0 - 2.0 * k), 200.0))
	em._rebuild_grid()
	b._launch(Vector3(0, 0, -1), 12.0, 1, 1.0)
	_fly_out(w, b)
	var dmg := inst.stat("damage")
	for k in range(4):
		var lost: float = em.max_hp[ids[k]] - em.hp[ids[k]]
		assert_float(lost).is_equal_approx(dmg * pow(0.85, k), 0.01)


# ---------------------------------------------------------------- Carry

func test_carry_takes_only_the_first_creature_it_hits_and_sets_it_down_where_the_disc_lands() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var inst := _held(1, ["carry"])
	assert_float(float(inst.params["carry"]["chance"])).is_equal_approx(0.1, 0.0001)
	assert_float(float(inst.params["disc"]["size_mult"])).is_equal_approx(1.5, 0.0001)
	var b := _behavior(w, inst)
	inst.params["carry"]["chance"] = 1.0
	inst.params["bend_deg"] = 0.0
	var a := _creature(em, Vector3(0, 0, -3), 200.0)
	var c := _creature(em, Vector3(0, 0, -6), 200.0)
	var e := _creature(em, Vector3(0, 0, -9), 200.0)
	em._rebuild_grid()
	var d: Dictionary = b._launch(Vector3(0, 0, -1), 12.0, 1, 1.0)
	var rode := false
	var steps := 0
	while not (b.discs as Array).is_empty() and steps < 900:
		em._rebuild_grid()
		b._tick(DT)
		steps += 1
		if em.held[a] == 1:
			rode = true
			# it rides the disc, on top of it
			var p: Vector3 = d["pos"]
			assert_float(Vector2(em.pos[a].x - p.x, em.pos[a].z - p.z).length()).is_less(0.01)
		# never the second or the third
		assert_int(em.held[c]).is_equal(0)
		assert_int(em.held[e]).is_equal(0)
	assert_bool(rode).is_true()
	assert_int(b.carries).is_equal(1)
	# set down at the end of the flight, out where the disc came down; the others still cut on the way
	assert_int(em.held[a]).is_equal(0)
	assert_float(-em.pos[a].z).is_greater(11.5)
	assert_float(em.hp[c]).is_less(em.max_hp[c])
	assert_float(em.hp[e]).is_less(em.max_hp[e])
	# the ride took no hit from its own disc after the first (the plain Carry has no drop hit)
	assert_float(em.max_hp[a] - em.hp[a]).is_equal_approx(inst.stat("damage"), 0.01)
	assert_int(int(g.get("sands"))).is_greater(0)


func test_carry_never_takes_an_elite_or_a_boss_and_only_the_first_has_the_chance() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held(1, ["carry"])
	var b := _behavior(w, inst)
	inst.params["carry"]["chance"] = 1.0
	inst.params["bend_deg"] = 0.0
	var big := _creature(em, Vector3(0, 0, -3), 200.0)
	em.elite_idx[big] = 0
	var next := _creature(em, Vector3(0, 0, -6), 200.0)
	em._rebuild_grid()
	assert_bool(em.grabbable(big)).is_false()
	b._launch(Vector3(0, 0, -1), 12.0, 1, 1.0)
	var steps := 0
	while not (b.discs as Array).is_empty() and steps < 900:
		em._rebuild_grid()
		b._tick(DT)
		steps += 1
		assert_int(em.held[big]).is_equal(0)
		assert_int(em.held[next]).is_equal(0)
	assert_int(b.carries).is_equal(0)
	em.elite_idx[big] = -1
	# a boss
	var boss := _creature(em, Vector3(0, 0, -3.2), 200.0)
	em.boss_index = boss
	em._rebuild_grid()
	assert_bool(em.grabbable(boss)).is_false()
	em.boss_index = -1


func test_two_discs_each_carry_their_own_and_one_at_a_time() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held(1, ["carry"])
	var b := _behavior(w, inst)
	inst.params["carry"]["chance"] = 1.0
	inst.params["bend_deg"] = 0.0
	var left := _creature(em, Vector3(-4, 0, -3), 200.0)
	var right := _creature(em, Vector3(4, 0, -3), 200.0)
	em._rebuild_grid()
	var d1: Dictionary = b._launch(Vector3(-4, 0, -3).normalized(), 5.0, 1, 1.0)
	var d2: Dictionary = b._launch(Vector3(4, 0, -3).normalized(), 5.0, 1, 1.0)
	for k in range(30):
		em._rebuild_grid()
		b._tick(DT)
	assert_int(int(d1["carry"])).is_equal(left)
	assert_int(int(d2["carry"])).is_equal(right)
	_fly_out(w, b)
	assert_int(b.carries).is_equal(2)
	assert_int(em.held[left]).is_equal(0)
	assert_int(em.held[right]).is_equal(0)


func test_a_disc_still_carrying_when_the_weapon_goes_lets_its_creature_go() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held(1, ["carry"])
	var b := _behavior(w, inst)
	inst.params["carry"]["chance"] = 1.0
	inst.params["bend_deg"] = 0.0
	var a := _creature(em, Vector3(0, 0, -2), 200.0)
	em._rebuild_grid()
	b._launch(Vector3(0, 0, -1), 12.0, 1, 1.0)
	for k in range(20):
		em._rebuild_grid()
		b._tick(DT)
	assert_int(em.held[a]).is_equal(1)
	b.free()
	assert_int(em.held[a]).is_equal(0)


# ---------------------------------------------------------------- Poison Razors

func test_poison_razors_poisons_what_it_cuts_and_looks_the_part() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held(1, ["poison_razors"])
	assert_float(inst.stat("poison_damage")).is_greater(0.0)
	assert_str(inst.element()).is_equal("poison")
	assert_str(str(inst.params["disc"]["look"])).is_equal("razors")
	var b := _behavior(w, inst)
	inst.params["bend_deg"] = 0.0
	var a := _creature(em, Vector3(0, 0, -3), 200.0)
	em._rebuild_grid()
	b._launch(Vector3(0, 0, -1), 12.0, 1, 1.0)
	_fly_out(w, b)
	assert_bool(em.is_poisoned(a)).is_true()
	# the razor disc has its blades: a second surface
	assert_int((b.get("_mesh") as ArrayMesh).get_surface_count()).is_equal(2)
	# the plain frisbee poisons nothing
	Run.debug_clear_items()
	var plain := _held()
	var b2 := _behavior(w, plain)
	plain.params["bend_deg"] = 0.0
	var c := _creature(em, Vector3(2, 0, -3), 200.0)
	em._rebuild_grid()
	b2._launch(Vector3(2, 0, -3).normalized(), 5.0, 1, 1.0)
	_fly_out(w, b2)
	assert_float(em.hp[c]).is_less(em.max_hp[c])
	assert_bool(em.is_poisoned(c)).is_false()
	assert_int((b2.get("_mesh") as ArrayMesh).get_surface_count()).is_equal(1)


# ---------------------------------------------------------------- Trick Shot

func test_trick_shot_raises_the_frisbees_procs_only() -> void:
	_held(1, ["frisbee_trick_shot"])
	Run.debug_set_item("weapon", "revolver", 1)
	assert_float(Run.trick_proc_mult("frisbee")).is_equal_approx(1.25, 0.0001)
	assert_float(Run.trick_proc_mult("revolver")).is_equal_approx(1.0, 0.0001)
	assert_float(Run.trick_proc_mult("")).is_equal_approx(1.0, 0.0001)
	assert_float(Run.trick_proc_mult("not_held")).is_equal_approx(1.0, 0.0001)
	# life steal: a quarter more from the frisbee's damage, the same from the revolver's
	Run.player_sheet.add_effect(Effect.make("lifesteal", "set", 0.01), "p69 test")
	Run.player_sheet.add_effect(Effect.make("lifesteal_cap", "set", 10.0), "p69 test")
	Run.lifesteal_pool = 0.0
	Run.add_damage("revolver", 40.0)
	assert_float(Run.lifesteal_pool).is_equal_approx(0.4, 0.0001)
	Run.lifesteal_pool = 0.0
	Run.add_damage("frisbee", 40.0)
	assert_float(Run.lifesteal_pool).is_equal_approx(0.5, 0.0001)
	Run.lifesteal_pool = 0.0


func test_trick_shot_crit_cold_snap_and_vulture_chances() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	_held(1, ["frisbee_trick_shot"])
	Run.debug_set_item("weapon", "revolver", 1)
	# 0.8 x 1.25 = 1: every frisbee hit crits, freezes and heals; the revolver's, at 0.8, not every one
	Run.player_sheet.add_effect(Effect.make("crit_chance", "set", 0.8), "p69 test b")
	Run.player_sheet.add_effect(Effect.make("freeze_chance", "set", 0.8), "p69 test b")
	Run.player_sheet.add_effect(Effect.make("crit_heal_chance", "set", 0.8), "p69 test b")
	em.refresh_player_stats()
	var i := _creature(em, Vector3(0, 0, -3), 5000.0)
	var crits := 0
	var frozen := 0
	for k in range(60):
		em.freeze_t[i] = 0.0
		em.damage(i, 1.0, "frisbee")
		crits += 1 if em.last_crit else 0
		frozen += 1 if em.freeze_t[i] > 0.0 else 0
	assert_int(crits).is_equal(60)
	assert_int(frozen).is_equal(60)
	assert_int(int(hero.get("heals"))).is_equal(60)
	var rc := 0
	var rf := 0
	for k in range(60):
		em.freeze_t[i] = 0.0
		em.damage(i, 1.0, "revolver")
		rc += 1 if em.last_crit else 0
		rf += 1 if em.freeze_t[i] > 0.0 else 0
	assert_int(rc).is_less(60)
	assert_int(rf).is_less(60)


func test_trick_shot_raises_a_frisbee_stun() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held(1, ["frisbee_trick_shot"])
	var b := _behavior(w, inst)
	inst.params["stun"] = {"chance": 0.8, "seconds": 1.0}
	var i := _creature(em, Vector3(0, 0, -3), 5000.0)
	for k in range(40):
		em.stun_t[i] = 0.0
		b._stun_roll(em, i)
		assert_float(em.stun_t[i]).is_greater(0.0)


# ---------------------------------------------------------------- the Flying Saucer

func test_the_flying_saucer_carries_its_path_amplified() -> void:
	var inst := _held(1, ["carry", "poison_razors", "frisbee_trick_shot"], "flying_saucer")
	assert_str(inst.def.evolved_from).is_equal("frisbee")
	assert_str(str(inst.params["disc"]["look"])).is_equal("saucer")
	assert_bool(bool(inst.params["disc"]["haze"])).is_true()
	assert_float(float(inst.params["disc"]["size_mult"])).is_equal_approx(1.5, 0.0001)
	assert_float(float(inst.params["carry"]["chance"])).is_equal_approx(0.2, 0.0001)
	assert_float(float(inst.params["carry"]["drop_hit"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(inst.params["proc_mult"])).is_equal_approx(1.5, 0.0001)
	# poison x1.5: the saucer's own 2 on the razors' 4, damage and seconds
	var razors: MutationDef = Registry.mutation("poison_razors")
	var pd := 0.0
	var pt := 0.0
	for e: Effect in razors.effects:
		if e.stat == "poison_damage":
			pd = e.value
		elif e.stat == "poison_duration":
			pt = e.value
	assert_float(inst.stat("poison_damage")).is_equal_approx(pd * 1.5, 0.0001)
	assert_float(inst.stat("poison_duration")).is_equal_approx(pt * 1.5, 0.0001)
	assert_float(Run.trick_proc_mult("flying_saucer")).is_equal_approx(1.5, 0.0001)


func test_the_saucer_loops_exactly_once_a_flight_and_comes_back_to_its_arc() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held(1, ["carry", "poison_razors", "frisbee_trick_shot"], "flying_saucer")
	var b := _behavior(w, inst)
	for k in range(5):
		var d: Dictionary = b._launch(Vector3(0, 0, -1), 10.0, 1)
		var la: float = d["loop_at"]
		assert_float(la).is_between(0.3 * float(d["range"]), 0.7 * float(d["range"]))
		var entered := Vector3.INF
		var steps := 0
		var far := 0.0
		while not (b.discs as Array).is_empty() and steps < 900:
			em._rebuild_grid()
			b._tick(DT)
			steps += 1
			if float(d["loop_t"]) >= 0.0 and entered == Vector3.INF:
				entered = d["loop_p0"]
			if float(d["loop_t"]) >= 0.0:
				far = maxf(far, ((d["pos"] as Vector3) - entered).length())
		assert_int(int(d["looped"])).is_equal(1)
		# a circle of 1.3 m: at most its diameter from where it began
		assert_float(far).is_between(2.4, 2.65)
	assert_int(b.loops).is_equal(5)
	# the plain frisbee never loops
	Run.debug_clear_items()
	var plain := _held()
	var b2 := _behavior(w, plain)
	var d2: Dictionary = b2._launch(Vector3(0, 0, -1), 10.0, 1)
	assert_float(float(d2["loop_at"])).is_less(0.0)
	_fly_out(w, b2)
	assert_int(int(d2["looped"])).is_equal(0)


func test_the_saucer_drops_what_it_carried_with_a_hit() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := _held(1, ["carry", "poison_razors", "frisbee_trick_shot"], "flying_saucer")
	var b := _behavior(w, inst)
	inst.params["carry"]["chance"] = 1.0
	inst.params["bend_deg"] = 0.0
	inst.params.erase("loop")
	var a := _creature(em, Vector3(0, 0, -3), 5000.0)
	em._rebuild_grid()
	b._launch(Vector3(0, 0, -1), 12.0, 1, 1.0)
	_fly_out(w, b)
	assert_int(b.carries).is_equal(1)
	# the cut and the drop: twice the saucer's damage (no crits)
	assert_float(em.max_hp[a] - em.hp[a]).is_equal_approx(inst.stat("damage") * 2.0, 0.01)


# ---------------------------------------------------------------- content and words

func test_the_frisbee_is_whole_and_in_play() -> void:
	var f: WeaponDef = Registry.weapon("frisbee")
	assert_object(f).is_not_null()
	assert_str(f.behavior).is_equal("Frisbee")
	assert_str(f.rarity).is_equal("common")
	assert_str(f.hero).is_equal("")
	assert_bool(f.hidden).is_false()
	assert_int(f.max_level).is_equal(5)
	assert_array(f.tags).contains(["disc"])
	var path: Array = Registry.mutations_of("frisbee").map(func(m: MutationDef) -> String: return m.id)
	assert_array(path).is_equal(["poison_razors", "carry", "frisbee_trick_shot"])
	assert_str(f.evolves_into).is_equal("flying_saucer")
	var ev: WeaponDef = Registry.weapon("flying_saucer")
	assert_bool(ev.is_evolution).is_true()
	assert_str(ev.behavior).is_equal("Frisbee")
	assert_float(float(f.base["damage"])).is_equal_approx(14.0, 0.001)
	assert_float(float(f.base["cooldown"])).is_equal_approx(1.2, 0.001)
	assert_float(float(f.base["speed"])).is_equal_approx(13.0, 0.001)
	assert_float(float(f.base["range"])).is_equal_approx(12.0, 0.001)
	# the Revolver's own Trick Shot is still the Revolver's
	assert_str(Registry.mutation("trick_shot").weapon).is_equal("revolver")


func test_the_words() -> void:
	assert_str(Registry.mutation("carry").text).is_equal("It has a 10% chance to carry the enemy away.")
	var f: WeaponDef = Registry.weapon("frisbee")
	var inst := WeaponInstance.new(f, 1)
	inst.rebuild(StatSheet.new(), [inst])
	var text := TextGen.weapon_description(f, inst.sheet, inst.params)
	assert_str(text).contains("Throws a frisbee at the nearest enemy within 12 m")
	assert_str(text).contains("15% less (never under 25%)")
	assert_str(text).not_contains("Pierces")
	assert_str(TextGen.amount_noun(f, inst.sheet, inst.params)).is_equal("frisbees")
	var rows: Array = inst.stat_rows().map(func(r: Dictionary) -> String: return str(r["stat"]))
	assert_array(rows).not_contains(["pierce"])
	assert_array(rows).contains(["damage", "range", "dps"])
	assert_float(inst.dps_estimate()).is_greater(inst.stat("damage") / inst.stat("cooldown"))
	var sv: WeaponDef = Registry.weapon("flying_saucer")
	var si := WeaponInstance.new(sv, 1)
	si.mutations = [Registry.mutation("carry"), Registry.mutation("poison_razors"), Registry.mutation("frisbee_trick_shot")]
	si.rebuild(StatSheet.new(), [si])
	var st := TextGen.weapon_description(sv, si.sheet, si.params)
	assert_str(st).contains("Throws 3 frisbees")
	assert_str(st).contains("20% chance to carry the first enemy it hits away and drop it with a hit")
	assert_str(st).contains("50% better")
	assert_str(st).contains("loops once")
	assert_str(st).contains("Poisons")


func test_the_disc_meshes_build_for_every_look() -> void:
	for look: String in ["plain", "razors", "saucer"]:
		var m: ArrayMesh = FRIS.disc_mesh(look, Color("#B8FF2A"))
		var mats: Array = FRIS.disc_materials(look, Color("#7CFF00"), 0.8)
		assert_int(m.get_surface_count()).is_equal(mats.size())
		assert_float(m.get_aabb().size.x).is_between(1.9, 2.6)
