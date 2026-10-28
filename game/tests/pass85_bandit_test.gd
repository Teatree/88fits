extends GdUnitTestSuite

## Pass 85, lane BANDIT: the Spit Cactus's Dynamite Bandit (look SC-A from Garry's Dynamite_Bandit.png) and his dynamite
## (ranged.shot "dynamite", ranged.dynamite {speed, fuse, out_before, lead, lead_max, model, hand, blast {radius,
## knockback, lift, push, push_radius}}, ranged.release_hold): thrown in place from the hand at the end of the wind-up, a
## little ahead of the hero (a share of his velocity over the flight, capped), flying faster than the spit, harmless in the
## air, lying 1 s with its spark lit (out half a second before), a red ring on its spot from the throw to the blast, then a
## blast like the hero's stick: the hero hurt and thrown inside it, the crowd pushed and unhurt; always red and pulsing.
## The look's attack strip is a throw (EnemyDef.attack_throw: wind-up | release in each view's half, _throw_frame).

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
var rings: Array = []
var bursts: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(at, col, size) -> void:
	bursts.append({"at": at, "col": col, "size": size})
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_poison(_a) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func telegraph_ring(at: Vector3, r: float, dur: float, _col: Color, _filled := true) -> void:
	rings.append({"at": at, "r": r, "dur": dur})
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
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
var hits: Array = []
var blasts: Array = []
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return true
func take_damage(a: float, _f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "info": i})
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(v: Vector3, up: float = 0.0, _h: bool = true) -> void:
	blasts.append({"v": v, "up": up})
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


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "cam": cam}


func _creature(em: EnemyManager, at: Vector3, id := "spit_cactus", hp_mult := 50.0) -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


func _dy() -> Dictionary:
	# pass 111 (lane ENEMY): the block the cactus throws by (a "bomb" shot throws by ranged.bomb, EnemyManager.throw_block)
	return EnemyManager.throw_block(Registry.enemy("spit_cactus"))


## A stick thrown by the cactus at `i` from `from` to `target`, as _throw_dynamite throws it.
func _throw(w: Dictionary, i: int, from: Vector3, target: Vector3) -> int:
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var dy := _dy()
	return pm.hostile_dynamite(from, target, float(dy["speed"]), 8.0, float(dy["blast"]["radius"]), dy, em.hit_info(i, "ranged", ["dynamite"]))


# ---------------------------------------------------------------- the data

func test_the_cactus_throws_red_pulsing_dynamite_faster_than_the_spit() -> void:
	var r: Dictionary = Registry.enemy("spit_cactus").ranged
	# pass 111 (lane ENEMY; Garry: "a nice black bomb ... instead of a dynamite stick"): the throw is the bomb now, by its
	# own block; the dynamite's block stays for a "dynamite" shot
	assert_str(str(r.get("shot", ""))).is_equal("bomb")
	assert_bool(EnemyManager.throws_dynamite(Registry.enemy("spit_cactus"))).is_true()
	var dy: Dictionary = _dy()
	assert_float(float(dy["fuse"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(dy["out_before"])).is_equal_approx(0.5, 0.0001)
	# faster than the spit's 5.4
	assert_float(float(dy["speed"])).is_greater(float(r["projectile_speed"]))
	# a little lead, not the harpooner's whole one
	assert_float(float(dy["lead"])).is_greater(0.0)
	assert_float(float(dy["lead"])).is_less(0.6)
	assert_bool(ResourceLoader.exists(str(dy["model"]))).is_true()
	assert_str(str(dy["model"])).contains("bomb")
	assert_str(str(r["dynamite"]["model"])).contains("red")
	# the pulse is kept, red
	var c := Color(str(r["pulse"]["color"]))
	assert_float(c.r).is_greater(0.8)
	assert_float(c.g).is_less(0.3)
	assert_float(float(r["release_hold"])).is_greater(0.0)
	# Garry's spit numbers kept
	assert_float(float(r["cooldown"])).is_equal_approx(2.6, 0.0001)
	assert_float(float(r["telegraph"])).is_equal_approx(0.7, 0.0001)
	assert_float(float(r["range"])).is_equal_approx(8.0, 0.0001)
	assert_float(float(r["keep_distance"])).is_equal_approx(5.5, 0.0001)


# ---------------------------------------------------------------- the aim

func test_he_aims_at_a_standing_heros_feet_and_a_little_ahead_of_a_running_one() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var def: EnemyDef = Registry.enemy("spit_cactus")
	var i := _creature(em, Vector3(0, 0, 0))
	var dy := _dy()
	var ppos := Vector3(7, 0, 0)
	var still := em.dynamite_aim(i, def, ppos, Vector3.ZERO)
	assert_float(Vector2(still.x - 7.0, still.z).length()).is_less(0.001)
	# running across his line at 5 m/s: the share of his run over the flight
	var v := Vector3(0, 0, 5)
	var at := em.dynamite_aim(i, def, ppos, v)
	var t: float = clampf(7.0 / float(dy["speed"]), 0.4, 2.0) / em.hostile_clock()
	var want := 5.0 * t * float(dy["lead"])
	assert_float(at.z).is_equal_approx(minf(want, float(dy["lead_max"])), 0.001)
	assert_float(at.x).is_equal_approx(7.0, 0.001)
	# much less than the whole lead (where he would be when it lands)
	assert_float(at.z).is_less(5.0 * t * 0.6)
	# a dash is capped at lead_max
	var fast := em.dynamite_aim(i, def, ppos, Vector3(0, 0, 60))
	assert_float(fast.z).is_equal_approx(float(dy["lead_max"]), 0.001)


# ---------------------------------------------------------------- the stick

func test_the_stick_never_hurts_in_the_air_lies_a_second_then_blows_inside_its_ring() -> void:
	for case in [[0.5, 1], [2.2, 1], [2.7, 0]]:
		var w := _world()
		var em: EnemyManager = w["em"]
		var pm: ProjectileManager = w["pm"]
		var hero: Node3D = w["hero"]
		var g: Node = w["g"]
		var i := _creature(em, Vector3(-7, 0, 0))
		var target := Vector3(0, 0, 0)
		# the hero under its climb first: nothing in the air hurts him
		hero.global_position = Vector3(-6.4, 0, 0)
		var j := _throw(w, i, Vector3(-7, 1.3, 0), target)
		assert_int(j).is_greater_equal(0)
		assert_bool(pm.extra[j].has("land_only")).is_true()
		var dy := _dy()
		var r := float(dy["blast"]["radius"])
		# one red ring on the spot, the blast's radius, from the throw to the blast
		var rings: Array = g.get("rings")
		assert_int(rings.size()).is_equal(1)
		assert_float(Vector2(rings[0]["at"].x, rings[0]["at"].z).length()).is_less(0.35)
		assert_float(float(rings[0]["r"])).is_equal_approx(r, 0.0001)
		var s := 0.0
		var landed_at := -1.0
		var lit_at_half := false
		var out_before_end := false
		while pm.alive[j] == 1 and s < 6.0:
			if s > 0.3:
				hero.global_position = target + Vector3(float(case[0]), 0, 0)
			pm._physics_process(DT)
			s += DT
			if pm.alive[j] == 0:
				break
			if landed_at < 0.0 and pm.extra[j].has("lie_t"):
				landed_at = s
				assert_int((hero.get("hits") as Array).size()).is_equal(0)
			if landed_at >= 0.0:
				var left := float(pm.extra[j]["lie_t"])
				if left > 0.7:
					lit_at_half = lit_at_half or pm.fuse_lit(j)
				if left < 0.4 and not pm.fuse_lit(j):
					out_before_end = true
		assert_float(landed_at).is_greater(0.0)
		# it lay its fuse out on the creatures' clock, and the ring lasted the flight and the fuse
		var lay := s - landed_at
		assert_float(lay * em.hostile_clock()).is_equal_approx(float(dy["fuse"]), 0.05)
		assert_float(s).is_equal_approx(float(rings[0]["dur"]), 0.08)
		assert_bool(lit_at_half).is_true()
		assert_bool(out_before_end).is_true()
		assert_int(pm.dynamite_blasts).is_equal(1)
		var hits: Array = hero.get("hits")
		assert_int(hits.size()).override_failure_message("hero %.2f m off" % float(case[0])).is_equal(int(case[1]))
		if int(case[1]) == 1:
			assert_bool(((hits[0]["info"] as Dictionary).get("fx", []) as Array).has("dynamite blast")).is_true()
			# thrown back, away from the blast
			var bl: Array = hero.get("blasts")
			assert_int(bl.size()).is_equal(1)
			assert_float((bl[0]["v"] as Vector3).x).is_greater(0.0)
		# the hero's stick's blast (pass 110, re-pinned on purpose, lane VFX: Fx's blast pool, at the blast's radius)
		var fxn: Fx = g.get("fx")
		assert_int(fxn.blasts).is_greater_equal(1)
		assert_float(float(fxn.last_blast["r"])).is_equal_approx(r, 0.001)


func test_the_lying_stick_keeps_pulsing_and_its_spark_burns_at_the_fuse() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3(40, 0, 40)
	var i := _creature(em, Vector3(-5, 0, 0))
	var j := _throw(w, i, Vector3(-5, 1.3, 0), Vector3(0, 0, 0))
	assert_bool(pm.extra[j].has("pulse")).is_true()
	var s := 0.0
	while pm.alive[j] == 1 and not pm.extra[j].has("lie_t") and s < 3.0:
		pm._physics_process(DT)
		s += DT
	assert_bool(pm.extra[j].has("lie_t")).is_true()
	var lo := 9.0
	var hi := 0.0
	for n in range(24):
		pm._physics_process(DT)
		lo = minf(lo, pm.psize[j])
		hi = maxf(hi, pm.psize[j])
	assert_float(hi - lo).is_greater(0.1)
	# lying still, on its side, its spark listed for drawing
	assert_float(pm.vel[j].length()).is_equal(0.0)
	pm._render()
	assert_int(pm.sparks_drawn).is_equal(1)
	# drawn with the block's model (pass 111: the black bomb, its glossy look), not the spit's ball
	var look = _dy().get("material", {})
	assert_int(pm.kind[j]).is_equal(pm.dynamite_kind(str(_dy()["model"]), float(_dy().get("scale", 1.0)), look if look is Dictionary else {}))
	assert_int(pm.kind[j]).is_not_equal(int(w["g"].get("_spit_kind")) if w["g"].get("_spit_kind") != null else -2)


func test_the_blast_pushes_the_crowd_without_hurting_it() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	hero.global_position = Vector3(40, 0, 40)
	var thrower := _creature(em, Vector3(-7, 0, 0))
	var near := _creature(em, Vector3(1.0, 0, 0), "skeleton")
	var hp0: float = em.hp[near]
	var j := _throw(w, thrower, Vector3(-7, 1.3, 0), Vector3(0, 0, 0))
	var s := 0.0
	while pm.alive[j] == 1 and s < 6.0:
		pm._physics_process(DT)
		s += DT
	assert_int(pm.dynamite_blasts).is_equal(1)
	assert_float(em.kb[near].x).is_greater(0.5)
	assert_float(em.hp[near]).is_equal(hp0)


# ---------------------------------------------------------------- the throw in place

func test_he_stands_to_wind_up_throws_from_his_hand_and_holds_the_release() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var hero: Node3D = w["hero"]
	var def: EnemyDef = Registry.enemy("spit_cactus")
	hero.global_position = Vector3(7, 0, 0)
	var i := _creature(em, Vector3(0, 0, 0))
	em.cooldown[i] = 0.0
	var start: Vector3 = em.pos[i]
	var wound := false
	var thrown_at := -1
	var held := 0
	for k in range(240):
		em._physics_process(DT)
		pm._physics_process(DT)
		if em.state[i] == EnemyManager.STATE_WINDUP:
			wound = true
			assert_int(em.dynamite_throws).is_equal(0)
		if em.dynamite_throws == 1 and thrown_at < 0:
			thrown_at = k
		if thrown_at >= 0 and em.state[i] == EnemyManager.STATE_ATTACK:
			held += 1
		if thrown_at >= 0 and em.state[i] == EnemyManager.STATE_MOVE:
			break
	assert_bool(wound).is_true()
	assert_int(thrown_at).is_greater_equal(0)
	# in place: he stood through the wind-up and the release
	assert_float(Vector2(em.pos[i].x - start.x, em.pos[i].z - start.z).length()).is_less(0.3)
	# the release pose held about release_hold
	var hold_s := float(held) * DT
	assert_float(hold_s).is_equal_approx(float(def.ranged["release_hold"]) / em.pace, 0.1)
	# a stick in the air, aimed at the hero (he stands still)
	assert_int(pm.dynamite_thrown).is_equal(1)
	assert_float(Vector2(em.last_dynamite_aim.x - 7.0, em.last_dynamite_aim.z).length()).is_less(0.01)


func test_a_throw_strip_shows_its_wind_up_then_its_release_in_the_views_half() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(0, 0, 0))
	var t: int = em.type_idx[i]
	em._t_throw[t] = 1
	em._t_atkv[t] = 1
	var off: int = em._t_off[t * EnemyManager.N_ANIMS + EnemyManager.A_ATTACK]
	var n: int = em._t_cnt[t * EnemyManager.N_ANIMS + EnemyManager.A_ATTACK]
	if n < 4:
		# the old cactus strip: nothing to split, every frame stays inside the attack strip
		return
	var half := n >> 1
	var q := half >> 1
	for k in range(6):
		em.anim_t[i] = float(k)
		em.away[i] = 0
		em.state[i] = EnemyManager.STATE_WINDUP
		var f := em._throw_frame(i, t)
		assert_int(f).is_greater_equal(off)
		assert_int(f).is_less(off + q)
		em.state[i] = EnemyManager.STATE_ATTACK
		f = em._throw_frame(i, t)
		assert_int(f).is_greater_equal(off + q)
		assert_int(f).is_less(off + half)
		em.away[i] = 1
		f = em._throw_frame(i, t)
		assert_int(f).is_greater_equal(off + half + q)
		assert_int(f).is_less(off + n)
		em.state[i] = EnemyManager.STATE_WINDUP
		f = em._throw_frame(i, t)
		assert_int(f).is_greater_equal(off + half)
		assert_int(f).is_less(off + half + q)


# ---------------------------------------------------------------- the look

func test_the_dynamite_bandit_is_the_cactus_played_look_with_a_throw_strip() -> void:
	var def: EnemyDef = Registry.enemy("spit_cactus")
	assert_str(def.variant).is_equal("SC-A")
	assert_bool(def.variants.has("SC-A")).is_true()
	assert_bool(def.variants.has("SC-0")).is_true()
	assert_str(def.sprite_file).is_equal("spit_cactus_sprite_a.png")
	assert_object(def.sprite).is_not_null()
	# the throw: a wind-up | release half from the front and from behind
	assert_str(def.attack_views).is_equal("front_back")
	assert_bool(def.attack_throw).is_true()
	assert_int(def.frames_of("attack")).is_equal(8)
	for a in ["idle", "run", "die", "run_b", "idle_b"]:
		assert_int(def.frames_of(a)).override_failure_message(a).is_greater(0)
	# the cactus's own look keeps its two attack frames and no throw layout
	var cactus := def.variant_def("SC-0")
	assert_str(cactus.attack_views).is_equal("")
	assert_bool(cactus.attack_throw).is_false()
	assert_int(cactus.frames_of("attack")).is_equal(2)
