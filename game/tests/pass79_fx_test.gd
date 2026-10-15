extends GdUnitTestSuite

## Pass 79, lane FX (Garry: "enemies that die have their corpses follow through with their knockback. So when an explosion
## kills an enemy fly off like the live ones" and "Change the projectile trail. The balls aren't good. Make a simple line
## trail, similar to that of the rocket. Should be thin. 1. Regular shot dark red transparent 2. Silver - thicker, correct
## colour. 3. Then the line disappears like smoke."): a body keeps its push and slides on (EnemyManager._corpse_*), a
## blast's kill is thrown up and lands, the boss keeps his death, big game is never thrown, a body stays in the arena and
## on the ground; every tracer weapon lays a line of segments (ProjectileManager._tracer_*) with its own colour, width and
## life, cut round the hero by tracer_clear, in a ring that laps and rewinds, warmed under the beam. Numbers are read off
## the content and the constants, so tuning never breaks these.

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
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	return null
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h: bool = true) -> void:
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
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.begin_sandbox()
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()
	Save.end_sandbox()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks.
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


## A creature on its feet where it was put, every hit whole.
func _creature(em: EnemyManager, at: Vector3, id := "skeleton", hp_mult := 1.0, elite: EliteModDef = null) -> int:
	var i := em.spawn(id, at, elite, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.dr[i] = 0.0
	em.speed[i] = 0.0
	em._rebuild_grid()
	return i


## The push damage() gives creature `i` for a hit of `force` from the hero's side.
func _push_of(em: EnemyManager, i: int, force: float) -> float:
	return force / maxf(em.size[i], 0.8) * em._t_kbt[em.type_idx[i]] * em.hero_knock_mult()


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## A plain shot kind on `pm` (a quad), so a drawn frame has something to draw.
func _kind(pm: ProjectileManager) -> int:
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	return pm.register_kind(q, StandardMaterial3D.new(), 1.0)


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


# ---------------------------------------------------------------- corpses

func test_a_body_keeps_the_killing_push_and_slides_on_like_a_live_one() -> void:
	# pass 82 (lane FEEL, re-pinned on purpose): every kill now follows through like a blast's (EnemyManager._corpse_follow,
	# pass82_feel_test): the push along the hit is raised to the floor for the hit's weight and the body is thrown up
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(0, 0, -6))
	var push := _push_of(em, i, 10.0)
	assert_float(push).is_greater(0.5)
	var p0: Vector3 = em.pos[i]
	assert_bool(em.damage(i, 99999.0, "revolver", Vector3(0, 0, -1), 10.0)).is_true()
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	# the push is kept, flat, along the hit, at least a heavy kill's floor
	var fp := EnemyManager.corpse_floor_push(1.0, em.size[i])
	assert_float(em.kb[i].length()).is_equal_approx(maxf(push, fp), 0.001)
	assert_float(em.kb[i].z).is_less(0.0)
	assert_float(em.kb[i].y).is_equal(0.0)
	# thrown up as a blast's kill is (pass 82)
	assert_int(em.corpse_tosses).is_equal(1)
	assert_bool(em._corpse_air.has(i)).is_true()
	for k in range(80):
		em._physics_process(DT)
	var went := _flat(em.pos[i]).distance_to(_flat(p0))
	# further than the push alone slides a body over the sand
	assert_float(went).is_greater(maxf(push, fp) / EnemyManager.CORPSE_GROUND_DECAY)
	assert_float(em.pos[i].z).is_less(p0.z)
	# on the ground at the end
	assert_float(em.lift_h[i]).is_equal(0.0)
	assert_float(em.pos[i].y).is_equal_approx(em._height(em.pos[i].x, em.pos[i].z), 0.0001)


func test_a_blast_kill_throws_the_body_up_and_away_and_it_lands() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var centre := Vector3(0, 0, -6)
	var i := _creature(em, centre + Vector3(1.0, 0, 0))
	var force := 14.0
	var push := _push_of(em, i, force)
	# pass 82 (re-pinned): the kill's own follow-through when it is higher (a heavy kill, the push all along the blast)
	var h := maxf(EnemyManager.corpse_toss_height(push), EnemyManager.corpse_kill_toss(1.0, push))
	assert_float(h).is_greater(0.0)
	var p0: Vector3 = em.pos[i]
	em.damage_radius(centre, 2.5, 99999.0, "lob_grenade", force)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_int(em.corpse_tosses).is_equal(1)
	assert_bool(em._corpse_air.has(i)).is_true()
	# the blast's marker is cleared once it is done
	assert_int(em._corpse_blast_i).is_equal(-1)
	# the death lasts the flight and a rest after it
	var vy := sqrt(2.0 * EnemyManager.CORPSE_G * h)
	var t_air := EnemyManager.corpse_air_time(vy, 0.0)
	assert_float(em.timer[i]).is_greater_equal(t_air + EnemyManager.CORPSE_REST - 0.001)
	var top := 0.0
	var landed_at := -1
	for k in range(int((t_air + 0.4) / DT)):
		em._physics_process(DT)
		top = maxf(top, em.lift_h[i])
		if landed_at < 0 and em.corpse_landings > 0:
			landed_at = k
	assert_float(top).is_equal_approx(h, 0.15)
	assert_int(landed_at).is_greater(0)
	assert_float(float(landed_at) * DT).is_equal_approx(t_air, 0.1)
	assert_float(em.lift_h[i]).is_equal(0.0)
	assert_bool(em._corpse_air.has(i)).is_false()
	# out from the blast, further than the push alone slides a body over the sand
	var went := _flat(em.pos[i]).distance_to(_flat(p0))
	assert_float(em.pos[i].x).is_greater(p0.x)
	assert_float(went).is_greater(push / EnemyManager.CORPSE_GROUND_DECAY * 1.5)
	# and it still lies there for a moment before it sinks and goes
	assert_int(em.alive[i]).is_equal(1)
	for k in range(int((EnemyManager.CORPSE_REST + 0.2) / DT)):
		em._physics_process(DT)
	assert_int(em.alive[i]).is_equal(0)


func test_a_blast_without_a_push_throws_by_the_floor_and_a_survivor_is_not_thrown() -> void:
	# pass 82 (lane FEEL, re-pinned on purpose): a kill with no push follows through too, by the floor, out of the blast
	var w := _world()
	var em: EnemyManager = w["em"]
	var centre := Vector3(0, 0, -6)
	var a := _creature(em, centre + Vector3(0.8, 0, 0))
	em.damage_radius(centre, 2.5, 99999.0, "zone", 0.0)
	assert_int(em.state[a]).is_equal(EnemyManager.STATE_DYING)
	assert_int(em.corpse_tosses).is_equal(1)
	assert_bool(em._corpse_air.has(a)).is_true()
	assert_float(em.kb[a].x).is_greater(0.0)
	# a tough one lives through the blast: shoved as before, its feet on the ground (nothing changes for the living)
	var b := _creature(em, centre + Vector3(-0.8, 0, 0), "skeleton", 500.0)
	var push := _push_of(em, b, 14.0)
	em.damage_radius(centre, 2.5, 1.0, "lob_grenade", 14.0)
	assert_int(em.state[b]).is_not_equal(EnemyManager.STATE_DYING)
	assert_float(em.kb[b].length()).is_equal_approx(push, 0.001)
	assert_float(em.lift_h[b]).is_equal(0.0)
	assert_int(em.corpse_tosses).is_equal(1)


func test_a_small_push_is_no_throw_and_a_big_one_is_capped() -> void:
	assert_float(EnemyManager.corpse_toss_height(0.0)).is_equal(0.0)
	assert_float(EnemyManager.corpse_toss_height((EnemyManager.CORPSE_TOSS_MIN * 0.9) / EnemyManager.CORPSE_TOSS_PER)).is_equal(0.0)
	assert_float(EnemyManager.corpse_toss_height(4.0)).is_equal_approx(minf(4.0 * EnemyManager.CORPSE_TOSS_PER, EnemyManager.CORPSE_TOSS_MAX), 0.0001)
	assert_float(EnemyManager.corpse_toss_height(500.0)).is_equal_approx(EnemyManager.CORPSE_TOSS_MAX, 0.0001)
	# the flight: up and back down under CORPSE_G
	assert_float(EnemyManager.corpse_air_time(11.0, 0.0)).is_equal_approx(2.0 * 11.0 / EnemyManager.CORPSE_G, 0.0001)
	assert_float(EnemyManager.corpse_air_time(0.0, 2.0)).is_equal_approx(sqrt(2.0 * 2.0 / EnemyManager.CORPSE_G), 0.0001)


func test_the_boss_keeps_his_death() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := em.spawn_boss("tumbleweed_king", Vector3(0, 0, -8))
	assert_int(i).is_greater_equal(0)
	em.boss_index = i
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	var p0: Vector3 = em.pos[i]
	em.damage_radius(Vector3(0, 0, -6), 4.0, 9999999.0, "lob_grenade", 60.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_float(em.kb[i].length()).is_equal(0.0)
	assert_int(em.corpse_tosses).is_equal(0)
	for k in range(30):
		em._physics_process(DT)
	assert_float(_flat(em.pos[i]).distance_to(_flat(p0))).is_less(0.001)
	assert_float(em.lift_h[i]).is_equal(0.0)


func test_big_game_slides_but_is_never_thrown() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var mods: Array = Registry.elites.values()
	assert_int(mods.size()).is_greater(0)
	var i := _creature(em, Vector3(1.0, 0, -6), "skeleton", 1.0, mods[0])
	assert_bool(em.is_big_game(i)).is_true()
	em.damage_radius(Vector3(0, 0, -6), 2.5, 9999999.0, "lob_grenade", 14.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_float(em.kb[i].length()).is_greater(0.0)
	assert_int(em.corpse_tosses).is_equal(0)
	em._physics_process(DT)
	assert_float(em.lift_h[i]).is_equal(0.0)


func test_a_body_stays_inside_the_arena() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var r := em.arena_radius
	var i := _creature(em, Vector3(r - 2.5, 0, 0))
	em.damage_radius(Vector3(r - 4.0, 0, 0), 3.0, 9999999.0, "lob_grenade", 400.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	for k in range(90):
		em._physics_process(DT)
		assert_float(_flat(em.pos[i]).length()).is_less_equal(r - 2.0 + 0.001)
		assert_float(em.lift_h[i]).is_greater_equal(0.0)


func test_a_body_left_up_in_the_air_falls() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(0, 0, -6))
	# up in a tornado's toss (no launch entry), killed by a burn: it comes down instead of hanging there
	em.lift_t[i] = 1.0
	em.lift_d[i] = 1.0
	em.lift_h[i] = 2.0
	em.lift_mode[i] = 0
	em.damage(i, 99999.0, "")
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_bool(em._corpse_air.has(i)).is_true()
	# pass 82 (re-pinned): the kill throws it a little higher first (at most CORPSE_HIT_TOSS_MAX)
	var fall := EnemyManager.corpse_air_time(sqrt(2.0 * EnemyManager.CORPSE_G * EnemyManager.CORPSE_HIT_TOSS_MAX), 2.0)
	for k in range(int((fall + 0.1) / DT)):
		em._physics_process(DT)
	assert_float(em.lift_h[i]).is_equal(0.0)
	assert_int(em.corpse_landings).is_equal(1)


func test_a_launched_body_keeps_bucking_broncos_drift() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(0, 0, -6))
	assert_bool(em.launch(i, 2.8, 0.8, 0.0, "revolver")).is_true()
	(em._launched[i] as Dictionary)["drift"] = Vector3(4.0, 0, 0)
	em._physics_process(DT)
	em.damage(i, 99999.0, "revolver")
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	# its fall stays the launch's own; the drift is its push
	assert_bool(em._corpse_air.has(i)).is_false()
	assert_float(em.kb[i].x).is_greater_equal(4.0 - 0.001)
	var x0: float = em.pos[i].x
	for k in range(30):
		em._physics_process(DT)
	assert_float(em.pos[i].x).is_greater(x0 + 0.5)
	assert_float(em.lift_h[i]).is_equal(0.0)


# ---------------------------------------------------------------- the tracers' lines

func test_a_revolver_round_lays_its_red_tracer_and_no_beads() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("revolver")
	var beads := pm.trail_next
	var j := pm.fire(_kind(pm), Vector3(0, 0.8, -2), Vector3(0, 0, -33), 3.0, 0, 0.14, 0.6, inst, 0.0)
	assert_int(j).is_greater_equal(0)
	for k in range(12):
		pm._physics_process(DT)
	assert_int(pm.trail_next).is_equal(beads)
	var n := pm.tracer_segments
	assert_int(n).is_greater_equal(8)
	# one line: every piece starts where the last ended, born when the shot was there
	for k in range(n - 1):
		assert_float(pm.tracer_to[k].distance_to(pm.tracer_from[k + 1])).is_less(0.0001)
		assert_float(pm.tracer_birth[k]).is_less(pm.tracer_birth[k + 1])
		assert_float(pm.tracer_from[k].distance_to(pm.tracer_to[k])).is_greater_equal(ProjectileManager.TRACER_SEG_MIN - 0.0001)
	# its own colour, width and life from the content: red, a little see-through (pass 80, lane TRAIL: the wisp in a
	# readable red, 20 cm at the head, its style's life; pass80_trail_test has the rest)
	var c: Color = pm.tracer_col[n - 1]
	assert_bool(c.is_equal_approx(pm._tracer_colour(inst))).is_true()
	assert_float(c.r).is_greater(c.g * 3.0)
	assert_float(c.get_luminance()).is_less(0.3)
	assert_float(c.a).is_less(1.0)
	assert_float(pm.tracer_width[n - 1]).is_equal_approx(float(inst.params["tracer_width"]), 0.0001)
	assert_float(pm.tracer_life[n - 1]).is_equal_approx(ProjectileManager.tracer_life_of(inst), 0.0001)
	pm._tracer_draw()
	assert_int(pm._ln_mm.visible_instance_count).is_equal(n)


func test_silver_bullet_draws_a_thicker_silver_line() -> void:
	var pm: ProjectileManager = auto_free(ProjectileManager.new())
	var plain := _inst("revolver")
	var silver := _inst("revolver", ["silver_bullet"])
	assert_float(ProjectileManager.tracer_width_of(silver)).is_greater(ProjectileManager.tracer_width_of(plain) * 1.3)
	var c := pm._tracer_colour(silver)
	# pale, a touch of blue: silver, not the plain round's red
	assert_float(c.b).is_greater(c.r)
	assert_float(c.get_luminance()).is_greater(0.7)
	assert_bool(c.is_equal_approx(pm._tracer_colour(plain))).is_false()
	# the Golden Revolver's silver form the same
	var gold := _inst("golden_revolver")
	assert_float(ProjectileManager.tracer_width_of(gold)).is_equal_approx(ProjectileManager.tracer_width_of(silver), 0.0001)
	assert_bool(pm._tracer_colour(gold).is_equal_approx(c)).is_true()


func test_every_tracer_weapon_lays_a_line_in_its_own_colour_and_life() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var kd := _kind(pm)
	for id: String in ["tommy_gun", "chicago_typewriter", "boomstick", "blunderbuss", "turret_buddy", "golden_revolver"]:
		var inst := _inst(id)
		assert_bool(bool(inst.params.get("tracer", false))).override_failure_message(id).is_true()
		var n0 := pm.tracer_segments
		var j := pm.fire(kd, Vector3(3, 0.8, 0), Vector3(25, 0, 0), 1.0, 0, 0.1, 0.5, inst, 0.0)
		for k in range(4):
			pm._physics_process(DT)
		pm._free(j)
		assert_int(pm.tracer_segments).override_failure_message(id).is_greater(n0)
		var last := pm.tracer_segments - 1
		assert_bool(pm.tracer_col[last].is_equal_approx(pm._tracer_colour(inst))).override_failure_message(id).is_true()
		assert_float(pm.tracer_life[last]).override_failure_message(id).is_equal_approx(ProjectileManager.tracer_life_of(inst), 0.0001)
		assert_float(pm.tracer_width[last]).override_failure_message(id).is_equal_approx(ProjectileManager.tracer_width_of(inst), 0.0001)
	# the mutations that turn a tracer on or colour it: Toxic Peas' green, On Fire's orange, Drum Mag's bolder line
	var peas := _inst("peashooter", ["toxic_peas"])
	assert_bool(bool(peas.params.get("tracer", false))).is_true()
	var drum := _inst("tommy_gun", ["drum_mag"])
	assert_float(ProjectileManager.tracer_width_of(drum)).is_greater(ProjectileManager.tracer_width_of(_inst("tommy_gun")))


func test_tracer_clear_cuts_the_line_round_the_hero() -> void:
	var w := _world(Vector3(4, 0, 4))
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	var r := 1.1
	var c := Color(0.5, 0, 0, 0.9)
	# out from the hero: the piece inside the circle is gone
	var n0 := pm.tracer_segments
	pm.tracer_segment(Vector3(4, 1, 4), Vector3(4, 1, 0), c, 0.05, 0.5, r, hero)
	assert_int(pm.tracer_segments).is_equal(n0 + 1)
	var k := pm.tracer_segments - 1
	assert_float(_flat(pm.tracer_from[k]).distance_to(Vector2(4, 4))).is_equal_approx(r, 0.001)
	assert_float(pm.tracer_to[k].z).is_equal_approx(0.0, 0.0001)
	# wholly inside: nothing
	pm.tracer_segment(Vector3(4.2, 1, 4), Vector3(4.5, 1, 4), c, 0.05, 0.5, r, hero)
	assert_int(pm.tracer_segments).is_equal(n0 + 1)
	# straight past him: two pieces, each outside
	pm.tracer_segment(Vector3(0, 1, 4), Vector3(8, 1, 4), c, 0.05, 0.5, r, hero)
	assert_int(pm.tracer_segments).is_equal(n0 + 3)
	for q in [pm.tracer_segments - 2, pm.tracer_segments - 1]:
		assert_float(_flat(pm.tracer_from[q]).distance_to(Vector2(4, 4))).is_greater_equal(r - 0.001)
		assert_float(_flat(pm.tracer_to[q]).distance_to(Vector2(4, 4))).is_greater_equal(r - 0.001)
	# no clear: the whole of it
	pm.tracer_segment(Vector3(4, 1, 4), Vector3(4, 1, 0), c, 0.05, 0.5, 0.0, hero)
	assert_float(pm.tracer_from[pm.tracer_segments - 1].distance_to(Vector3(4, 1, 4))).is_less(0.0001)


func test_lines_run_out_and_the_ring_rewinds_and_laps() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	pm.tracer_segment(Vector3(0, 1, 0), Vector3(0, 1, -1), Color.WHITE, 0.05, 0.3)
	pm._tracer_draw()
	assert_int(pm._ln_mm.visible_instance_count).is_equal(1)
	assert_int(pm.tracer_live()).is_equal(1)
	pm.clock += 0.31
	assert_int(pm.tracer_live()).is_equal(0)
	pm._tracer_draw()
	assert_int(pm._ln_mm.visible_instance_count).is_equal(0)
	assert_int(pm._ln_next).is_equal(0)
	# a busy screen laps the ring: the newest overwrite the oldest, the ring never grows
	for k in range(ProjectileManager.TRACER_LINE_MAX + 10):
		pm.tracer_segment(Vector3(0, 1, 0), Vector3(0, 1, -1), Color.WHITE, 0.05, 5.0)
	assert_int(pm._ln_used).is_equal(ProjectileManager.TRACER_LINE_MAX)
	assert_int(pm._ln_next).is_equal(10)


func test_a_busy_screen_lays_longer_pieces() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("tommy_gun")
	pm.count = ProjectileManager.TRACER_BUSY + 1
	var j := pm.fire(_kind(pm), Vector3(0, 0.8, -2), Vector3(0, 0, -25), 1.0, 0, 0.1, 0.6, inst, 0.0)
	for k in range(12):
		pm._physics_process(DT)
	var n := pm.tracer_segments
	assert_int(n).is_greater(1)
	for k in range(n):
		assert_float(pm.tracer_from[k].distance_to(pm.tracer_to[k])).is_greater_equal(ProjectileManager.TRACER_SEG_MIN * 2.0 - 0.0001)
	pm._free(j)


func test_the_line_shader_and_its_warm_up() -> void:
	var code: String = ProjectileManager.TRACER_SHADER.code
	for want: String in ["now", "widen", "rise", "fade_pow", "min_px"]:
		assert_bool(code.contains("uniform float " + want)).override_failure_message("no uniform " + want).is_true()
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	pm.warm_draw(Vector3(0, -8, 0))
	assert_int(pm._ln_mm.visible_instance_count).is_greater_equal(1)
	pm.warm_draw(Vector3.INF)
