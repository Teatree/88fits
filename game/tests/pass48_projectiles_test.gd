extends GdUnitTestSuite

## Pass 48, lane L2 (the projectile weapons, Garry's sixth list). Priority aim on every shot, the pod and the seekers'
## lock. The Boomstick's Birdshot lane (hits only inside its rectangle, burns with Dragon's Breath, Both Barrels fires it
## twice every third pull) and the Blunderbuss's cone (wider and longer than the top Boomstick, twice every second pull).
## Mini crits carried through every pierce. The Silver Bullet (bigger, pale blue, a harder kick, 15% faster and never
## saying so) and Hip Shot (three volleys every fifth pull, then a twirl). The Pea Cannon's three ricochets with their
## puffs, the Golden Pineapple riding the strongest creature in its crowd. The Bouncing Skull's two hops past its blasts,
## Curare's growing chance, its hold and cooldown, the Grave Hail's double poison. Methanol's blue fire and bottle, the
## Moonshine's burning line and its six death pools. Pollen's flowers and their buff, the Tarantula Hawk's one creature
## and five stings, the Hive Queen's flowers. The silver emblem, an evolution's `final` params, and every evolution
## beating its weapon at the top level with the whole path.

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
var clouds: Array = []
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
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func spawn_cloud(at: Vector3, w, radius: float, element: String = "poison", params: Dictionary = {}) -> void:
	var c := ElementCloud.new()
	c.slow = float(params.get("slow", 0.0))
	c.blue = w != null and w.blue_fire()
	c.params = params
	if element == "fire":
		c.setup(self, w, radius, float(w.params.get("cloud_seconds", 3.0)), w.stat("fire_damage", 4.0), 1, w.stat("fire_duration", 1.8), "fire", w.stat("fire_spread", 0.5))
	else:
		c.setup(self, w, radius, float(w.params.get("cloud_seconds", 4.0)), w.stat("poison_damage", 3.0), maxi(w.stat_int("poison_stacks", 1), 1), w.stat("poison_duration", 10.0))
	c.position = Vector3(at.x, 0.0, at.z)
	add_child(c)
	clouds.append({"at": at, "r": radius, "element": element, "params": params, "node": c})
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

## base weapon -> its evolution (pass 48)
const FAMILIES := {"boomstick": "blunderbuss", "peashooter": "pea_cannon", "tommy_gun": "chicago_typewriter",
	"revolver": "golden_revolver", "skull_rain": "grave_hail", "lob_grenade": "golden_pineapple", "molotov": "moonshine",
	"hornet_nest": "hive_queen"}


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


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


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	var pe := ProjectileEmitter.new()
	(w["g"] as Node).add_child(pe)
	pe.setup(inst, w["g"])
	return pe


## The live shots of weapon `inst`, ghosts left out.
func _live_of(pm: ProjectileManager, inst: WeaponInstance) -> Array:
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst and not (pm.extra[j] as Dictionary).has("ghost"):
			out.append(j)
	return out


func _hp(em: EnemyManager, ids: Array) -> Dictionary:
	var out := {}
	for i: int in ids:
		out[i] = em.hp[i]
	return out


func _flat_angle(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(Vector3(a.x, 0, a.z).angle_to(Vector3(b.x, 0, b.z)))


# ---------------------------------------------------------------- priority aim

func test_priority_weapons_aim_at_the_big_one_from_the_gun_the_pod_and_the_seeker() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var small := _creature(em, Vector3(4, 0, 0), 1.0)
	var big := _creature(em, Vector3(0, 0, 7.2), 10.0)
	for k in range(3):
		_creature(em, Vector3(-40, 0, -10.0 * k), 1.0)
	em._rebuild_grid()
	em.refresh_crowd_stats()
	# the Peashooter's pod fires at the big one, from where it circles
	var pea := _inst("peashooter")
	var pe := _emitter(w, pea)
	assert_bool(pe._fire()).is_true()
	var shots := _live_of(pm, pea)
	assert_int(shots.size()).is_equal(1)
	var j: int = shots[0]
	var to_big: Vector3 = em.pos[big] - pm.pos[j]
	assert_float(_flat_angle(pm.vel[j], to_big)).is_less(3.0)
	# between shots it turns to the big one too
	for n in range(40):
		pe._tick(DT)
	assert_float(absf(angle_difference(pe._aim_yaw, atan2(-0.0, -7.2)))).is_less(0.05)
	# a forward weapon still takes the nearest
	var pb := _emitter(w, _inst("boomstick"))
	assert_bool(pb._fire()).is_true()
	assert_float(_flat_angle(pb._aim_dir, em.pos[small])).is_less(1.0)
	# the Hornet Nest's pod faces the big one, and its seekers lock on it
	var hn := _inst("hornet_nest")
	var mp := MissilePod.new()
	g.add_child(mp)
	mp.setup(hn, g)
	for n in range(60):
		mp._tick(DT)
	assert_float(absf(angle_difference(mp._aim_yaw, atan2(-0.0, -7.2)))).is_less(0.05)
	var mk := pm.launch_missile(mp.projectile_kind, Vector3(0, 1.5, 0), Vector3(0, 1, 0), 15.0, 5.0, 0.0, 11.0, hn,
		{"wander": 0.0, "turn": 9.0, "spiral": 0.0, "life": 3.0, "trail": 2}, 1.0)
	pm._physics_process(DT)
	assert_int(int(pm.extra[mk]["target"])).is_equal(big)


# ---------------------------------------------------------------- the Boomstick

func test_a_birdshot_lane_hits_only_inside_its_rectangle_and_burns() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var inst := _inst("boomstick", ["birdshot_lane", "dragons_breath"], 5)
	# the lane's shape is what this tests: Dragon's Breath lights only 60% since pass 51, so here every hit catches
	inst.params["ignite_chance"] = 1.0
	var bl := inst.blast()
	assert_str(str(bl["shape"])).is_equal("lane")
	assert_float(float(bl["width"])).is_equal_approx(2.6, 0.001)
	assert_float(float(bl["range"])).is_equal_approx(inst.stat("range") * 1.25, 0.001)
	var inside := [_creature(em, Vector3(3, 0, 0)), _creature(em, Vector3(6, 0, 1.0)), _creature(em, Vector3(7.2, 0, -1.1))]
	var outside := [_creature(em, Vector3(3.5, 0, 2.2)), _creature(em, Vector3(8.4, 0, 0)), _creature(em, Vector3(-4, 0, 0))]
	em._rebuild_grid()
	var hp0 := _hp(em, inside + outside)
	var pe := _emitter(w, inst)
	assert_bool(pe._fire()).is_true()
	assert_int(pe.blasts).is_equal(1)
	# 40% of a full point-blank volley to each, at once, and alight
	var per := 0.4 * inst.stat("damage") * float(inst.stat_int("amount"))
	for i: int in inside:
		assert_float(float(hp0[i]) - em.hp[i]).is_equal_approx(per, 0.01)
		assert_bool(em.is_burning(i)).is_true()
	for i: int in outside:
		assert_float(em.hp[i]).is_equal(float(hp0[i]))
		assert_bool(em.is_burning(i)).is_false()
	# the pellets streak down the lane for the eye and hit nothing
	var ghosts := 0
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and (pm.extra[j] as Dictionary).has("ghost"):
			ghosts += 1
	assert_int(ghosts).is_greater_equal(3)
	assert_int(_live_of(pm, inst).size()).is_equal(0)
	var hp1 := _hp(em, inside + outside)
	for n in range(30):
		pm._physics_process(DT)
	for i: int in inside + outside:
		assert_float(em.hp[i]).is_equal(float(hp1[i]))


func test_both_barrels_fires_the_lane_twice_every_third_pull() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var inst := _inst("boomstick", ["birdshot_lane", "both_barrels"], 5)
	var pe := _emitter(w, inst)
	var per := 0.4 * inst.stat("damage") * float(inst.stat_int("amount"))
	var hp0: float = em.hp[i]
	for n in range(3):
		assert_bool(pe._fire()).is_true()
	# the third pull's second barrel goes a beat later (pass 51: two shots, not one bigger one)
	assert_int(pe.blasts).is_equal(3)
	pe._tick(ProjectileEmitter.DOUBLE_GAP + 0.02)
	assert_int(pe.blasts).is_equal(4)
	assert_float(hp0 - em.hp[i]).is_equal_approx(per * 4.0, 0.05)


func test_the_blunderbuss_cone_is_wider_and_longer_and_doubles_every_second_pull() -> void:
	var path := ["dragons_breath", "birdshot_lane", "both_barrels"]
	var top := _inst("boomstick", path, 5)
	var bb := _inst("blunderbuss", path)
	var bl := bb.blast()
	# its own cone over the lane its path brings (`final`), and its own pace over Both Barrels' third
	assert_str(str(bl["shape"])).is_equal("cone")
	assert_float(float(bl["deg"])).is_equal_approx(75.0, 0.001)
	assert_float(float(bl["deg"])).is_greater(top.stat("spread_deg"))
	assert_float(float(bl["range"])).is_equal_approx(10.0, 0.001)
	assert_float(float(bl["range"])).is_greater(float(top.blast()["range"]))
	assert_float(float(bl["range"])).is_greater(top.stat("range"))
	assert_int(int(bb.params["double_every"])).is_equal(2)
	assert_bool(bb.params.has("final")).is_false()
	assert_float(bb.stat("cooldown")).is_less(top.stat("cooldown"))
	assert_float(bb.stat("knockback")).is_greater_equal(12.0)
	# fire of its own, on top of Dragon's Breath's
	assert_float(float(Registry.weapon("blunderbuss").base.get("fire_damage", 0.0))).is_greater(0.0)
	assert_float(bb.stat("fire_damage")).is_greater(top.stat("fire_damage"))
	var w := _world()
	var em: EnemyManager = w["em"]
	var near := _creature(em, Vector3(2, 0, 0))
	var far_in := _creature(em, Vector3(9.5, 0, 2.0))
	var wide_out := _creature(em, Vector3(5, 0, 5.5))
	var long_out := _creature(em, Vector3(10.8, 0, 0))
	em._rebuild_grid()
	var hp0 := _hp(em, [near, far_in, wide_out, long_out])
	var pe := _emitter(w, bb)
	for n in range(4):
		assert_bool(pe._fire()).is_true()
	# pulls closer together than the gap: the second pull's second barrel goes as the fourth pull arms its own (pass 51),
	# and that one a beat later
	assert_int(pe.blasts).is_equal(5)
	pe._tick(ProjectileEmitter.DOUBLE_GAP + 0.02)
	assert_int(pe.blasts).is_equal(6)
	var per := float(bl["frac"]) * bb.stat("damage") * float(bb.stat_int("amount"))
	for i: int in [near, far_in]:
		assert_float(float(hp0[i]) - em.hp[i]).is_equal_approx(per * 6.0, 0.05)
	for i: int in [wide_out, long_out]:
		assert_float(em.hp[i]).is_equal(float(hp0[i]))
	var rows := {}
	for r: Dictionary in bb.stat_rows():
		rows[str(r["stat"])] = r
	assert_str(str(rows["blast"]["value"])).contains("75°")
	assert_str(str(rows["double_every"]["value"])).is_equal("every 2")


# ---------------------------------------------------------------- mini crits

func test_a_mini_crit_round_carries_it_through_every_pierce() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var row := [_creature(em, Vector3(3, 0, 0)), _creature(em, Vector3(5, 0, 0)), _creature(em, Vector3(7, 0, 0))]
	em._rebuild_grid()
	var inst := _inst("tommy_gun", ["mini_crits"], 5)
	assert_float(float(inst.params["mini_crit"])).is_equal_approx(0.25, 0.001)
	# every round rolled for the test
	inst.params["mini_crit"] = 1.0
	var k := pm.register_kind(BoxMesh.new(), null)
	var j := pm.fire(k, Vector3(0, 0.8, 0), Vector3(20, 0, 0), 10.0, 2, 0.2, 1.0, inst, 0.0)
	assert_bool((pm.extra[j] as Dictionary).has("mini")).is_true()
	var hp0 := _hp(em, row)
	for n in range(30):
		pm._physics_process(DT)
	var mult := 1.0 + (Run.player_sheet.get_stat("crit_damage", 2.0) - 1.0) * 0.5
	# pass 62: the pierce drop-off on top (the n-th in the row takes ProjectileManager.falloff_factor of the round)
	var pf := ProjectileManager.weapon_falloff(inst)
	for n0 in range(row.size()):
		var i: int = row[n0]
		assert_float(float(hp0[i]) - em.hp[i]).is_equal_approx(10.0 * mult * ProjectileManager.falloff_factor(pf, n0 + 1), 0.01)
	# a round that did not roll it hits plain
	inst.params["mini_crit"] = 0.0
	var hp1 := _hp(em, row)
	var j2 := pm.fire(k, Vector3(0, 0.8, 0), Vector3(20, 0, 0), 10.0, 2, 0.2, 1.0, inst, 0.0)
	assert_bool((pm.extra[j2] as Dictionary).has("mini")).is_false()
	for n in range(30):
		pm._physics_process(DT)
	for n1 in range(row.size()):
		var i: int = row[n1]
		assert_float(float(hp1[i]) - em.hp[i]).is_equal_approx(10.0 * ProjectileManager.falloff_factor(pf, n1 + 1), 0.01)
	# the estimate counts a quarter of the rounds at half a crit's extra
	var plain := _inst("tommy_gun", [], 5)
	var mc := _inst("tommy_gun", ["mini_crits"], 5)
	assert_float(mc.dps_estimate()).is_equal_approx(plain.dps_estimate() * 1.125, 0.01)


# ---------------------------------------------------------------- the Revolver

func test_the_silver_bullet_is_bigger_bluer_and_quietly_faster() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(6, 0, 0))
	em._rebuild_grid()
	var plain := _inst("revolver")
	var inst := _inst("revolver", ["silver_bullet"])
	assert_float(inst.stat("damage")).is_equal_approx(plain.stat("damage") * 1.5, 0.001)
	assert_int(inst.stat_int("pierce")).is_equal(plain.stat_int("pierce") + 1)
	var pe := _emitter(w, inst)
	assert_bool(pe._fire()).is_true()
	var shots := _live_of(pm, inst)
	assert_int(shots.size()).is_equal(1)
	var j: int = shots[0]
	assert_float(pm.vel[j].length()).is_equal_approx(inst.stat("speed") * 1.15, 0.01)
	assert_float(pm.psize[j]).is_equal_approx(1.5, 0.001)
	assert_float(pm.radius[j]).is_equal_approx(float(plain.params["radius"]) * 1.5, 0.001)
	# pale blue: its own kind, its tracer, a harder kick and a small camera kick
	assert_int(pm.kind[j]).is_not_equal(pe.projectile_kind)
	# (pass 79, lane FX: its line in its own pale silver, the mutation's tracer_color)
	var svc := Color(str(Registry.mutation("silver_bullet").params["tracer_color"]))
	assert_bool(pm._tracer_colour(inst).is_equal_approx(Color(svc.r, svc.g, svc.b, 0.9))).is_true()
	assert_float(pe._recoil).is_equal_approx(ProjectileEmitter.SILVER_RECOIL, 0.001)
	assert_int(int((w["cam"] as Node).get("shakes"))).is_greater(0)
	# the speed is never written anywhere
	var md: MutationDef = Registry.mutation("silver_bullet")
	# pass 62: the pierce drop-off's own sentence ("the first enemy ... takes 15% more") is about damage, not speed
	var desc := inst.description().replace(TextGen.pierce_falloff_words(inst.params, "ProjectileEmitter", inst.stat_int("pierce")), "")
	for s: String in [md.text, md.flavour, md.vfx, desc]:
		for word: String in ["speed", "fast", "1.15", "15%"]:
			assert_bool(s.to_lower().contains(word)).override_failure_message("'%s' says %s" % [s, word]).is_false()
	for r: Dictionary in inst.stat_rows():
		if str(r["stat"]) == "speed":
			assert_str(str(r["value"])).is_equal(TextGen.format_value("speed", inst.stat("speed")))


func test_hip_shot_fires_three_volleys_every_fifth_pull_then_twirls() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(6, 0, 0))
	em._rebuild_grid()
	var inst := _inst("revolver", ["hip_shot"])
	var pe := _emitter(w, inst)
	for n in range(4):
		assert_bool(pe._fire()).is_true()
	assert_int(_live_of(pm, inst).size()).is_equal(4)
	assert_int(pe.hip_volleys).is_equal(0)
	assert_bool(pe._fire()).is_true()
	assert_int(pe.hip_volleys).is_equal(1)
	pe._tick(0.13)
	pe._tick(0.13)
	assert_int(pe.hip_volleys).is_equal(3)
	assert_int(_live_of(pm, inst).size()).is_equal(4 + 3)
	assert_bool(pe.spinning()).is_true()
	pe._tick(0.4)
	assert_bool(pe.spinning()).is_false()
	# the next fifth pull is another
	for n in range(5):
		pe._fire()
	pe._tick(0.13)
	pe._tick(0.13)
	assert_int(pe.hip_volleys).is_equal(6)


func test_the_golden_revolver_is_silver_hips_every_third_and_ricochets_without_a_kill() -> void:
	var gr := _inst("golden_revolver", ["silver_bullet", "hip_shot", "trick_shot"])
	assert_bool(bool(gr.params.get("silver", false))).is_true()
	assert_int(int(gr.params["hip_shot"]["every"])).is_equal(3)
	assert_int(int(gr.params["ricochet_any"]["count"])).is_equal(2)
	assert_float(float(gr.params["ricochet_any"]["frac"])).is_equal_approx(0.8, 0.001)
	# the energy lines stay, and it stands upright
	assert_bool(Registry.weapon("golden_revolver").params.has("trace")).is_true()
	assert_bool(gr.params.has("trace")).is_true()
	assert_float(float((gr.params.get("familiar", {}) as Dictionary).get("roll", 0.0))).is_equal(0.0)
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var a := _creature(em, Vector3(3, 0, 0))
	var b := _creature(em, Vector3(3, 0, 4))
	var c := _creature(em, Vector3(6, 0, 4.5))
	em._rebuild_grid()
	var hp0 := _hp(em, [a, b, c])
	var k := pm.register_kind(BoxMesh.new(), null)
	pm.fire(k, Vector3(0, 0.8, 0), Vector3(30, 0, 0), 20.0, 0, 0.2, 1.0, gr, 0.0)
	for n in range(60):
		pm._physics_process(DT)
	# none of them died, and the round went on twice at 80% of what it struck first with
	assert_float(float(hp0[a]) - em.hp[a]).is_equal_approx(20.0, 0.01)
	assert_float(float(hp0[b]) - em.hp[b]).is_equal_approx(16.0, 0.01)
	assert_float(float(hp0[c]) - em.hp[c]).is_equal_approx(16.0, 0.01)
	assert_int(pm.ricochets_any).is_equal(2)


# ---------------------------------------------------------------- the Peashooter

func test_big_peas_are_bigger_and_the_pea_cannon_bounces_three_times_with_its_puffs() -> void:
	var bp := _inst("peashooter", ["big_peas"])
	assert_float(float(bp.params["size_mult"])).is_equal_approx(1.5, 0.001)
	assert_float(float(bp.params["radius_mult"])).is_equal_approx(1.5, 0.001)
	var path := ["toxic_peas", "big_peas", "bouncing_peas"]
	var pc := _inst("pea_cannon", path)
	assert_float(float(pc.params["size_mult"])).is_equal_approx(2.0, 0.001)
	assert_float(pc.stat("poison_damage")).is_greater(0.0)
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var a := _creature(em, Vector3(3, 0, 0))
	var b := _creature(em, Vector3(3, 0, 4))
	var c := _creature(em, Vector3(6, 0, 4.5))
	var d := _creature(em, Vector3(6, 0, 8.5))
	var e := _creature(em, Vector3(30, 0, 30))
	em._rebuild_grid()
	var hp0 := _hp(em, [a, b, c, d, e])
	var k := pm.register_kind(BoxMesh.new(), null)
	pm.fire(k, Vector3(0, 0.8, 0), Vector3(20, 0, 0), 10.0, 0, 0.3, 2.0, pc, 0.0)
	for n in range(120):
		pm._physics_process(DT)
	for i: int in [a, b, c, d]:
		assert_float(float(hp0[i]) - em.hp[i]).override_failure_message("creature %d" % i).is_equal_approx(10.0, 0.01)
	assert_float(em.hp[e]).is_equal(float(hp0[e]))
	# a small, short puff of poison at every bounce
	var puffs: Array = (g.get("clouds") as Array).filter(func(cl: Dictionary) -> bool: return (cl["params"] as Dictionary).has("pool_seconds"))
	assert_int(puffs.size()).is_equal(3)
	for p: Dictionary in puffs:
		assert_str(str(p["element"])).is_equal("poison")
		assert_float(float(p["r"])).is_less(1.5)
		assert_float((p["node"] as ElementCloud).life).is_equal_approx(1.5, 0.001)


# ---------------------------------------------------------------- the Skull Rain

func test_a_bouncing_skull_hops_twice_past_its_blasts_turning_and_shrinking() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	_creature(em, Vector3(9, 0, 5))
	em._rebuild_grid()
	var inst := _inst("skull_rain", ["bouncing_skull"])
	var a0 := inst.stat("area")
	var k := pm.register_kind(BoxMesh.new(), null)
	var lp: Dictionary = inst.params.duplicate()
	lp["throw_dir"] = Vector3(1, 0, 0)
	pm.lob(k, Vector3(0, 1.2, 0), Vector3(5, 0, 0), 12.0, inst.stat("damage"), a0, inst, 2.0, lp)
	var hops: Array = []
	for n in range(400):
		pm._physics_process(DT)
		for j in range(ProjectileManager.MAX):
			if pm.alive[j] == 1 and pm.arc[j] == 1:
				var ex: Dictionary = pm.extra[j]
				var bk := int(ex.get("bounce_k", 0))
				if bk > hops.size():
					hops.append({"target": ex["target"], "area": pm.area[j], "size": pm.psize[j], "dir": ex["throw_dir"]})
	assert_int(hops.size()).is_equal(2)
	assert_int(pm.lobs_exploded).is_equal(3)
	var blasts: Array = g.get("clouds")
	assert_int(blasts.size()).is_equal(3)
	# each lands past the blast it left, the first further than the second
	var d1 := Vector2((hops[0]["target"] as Vector3).x - (blasts[0]["at"] as Vector3).x, (hops[0]["target"] as Vector3).z - (blasts[0]["at"] as Vector3).z).length()
	var d2 := Vector2((hops[1]["target"] as Vector3).x - (blasts[1]["at"] as Vector3).x, (hops[1]["target"] as Vector3).z - (blasts[1]["at"] as Vector3).z).length()
	assert_float(d1).is_equal_approx(a0 * 1.6 + 1.5, 0.05)
	assert_float(d2).is_equal_approx(a0 * 1.2 + 1.0, 0.05)
	assert_float(d1).is_greater(a0)
	assert_float(d2).is_greater(a0 * 0.7)
	assert_float(d1).is_greater(d2)
	# turned towards the creature ahead, never more than 30 degrees a hop
	var turn1 := _flat_angle(Vector3(1, 0, 0), hops[0]["dir"])
	assert_float(turn1).is_greater(5.0)
	assert_float(turn1).is_less_equal(30.01)
	assert_float(_flat_angle(hops[0]["dir"], hops[1]["dir"])).is_less_equal(30.01)
	# smaller blasts, clouds and skulls
	assert_float(float(hops[0]["area"])).is_equal_approx(a0 * 0.7, 0.001)
	assert_float(float(hops[1]["area"])).is_equal_approx(a0 * 0.5, 0.001)
	assert_float(float(hops[0]["size"])).is_equal_approx(0.8, 0.001)
	assert_float(float(hops[1]["size"])).is_equal_approx(0.6, 0.001)
	assert_float(float(blasts[1]["r"])).is_equal_approx(a0 * 0.7, 0.001)
	assert_float(float(blasts[2]["r"])).is_equal_approx(a0 * 0.5, 0.001)


func test_curare_grows_with_every_poisoning_then_slows_moves_and_attacks_and_cools_down() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var e := _creature(em, Vector3(4, 0, 0))
	var f := _creature(em, Vector3(-4, 0, 0))
	em._rebuild_grid()
	var inst := _inst("skull_rain", ["curare"])
	pm.curare_roll = 0.99
	for want: float in [0.4, 0.6, 0.8, 1.0]:
		pm.weapon_poison(e, inst)
		assert_float(pm.curare_chance(e)).is_equal_approx(want, 0.001)
		assert_float(em.hamper_t[e]).is_equal(0.0)
		pm.clock += 1.1
	# the fifth takes
	pm.weapon_poison(e, inst)
	assert_int(pm.curare_procs).is_equal(1)
	assert_float(pm.curare_chance(e)).is_equal_approx(0.2, 0.001)
	assert_float(em.attack_clock(e)).is_equal_approx(0.5, 0.001)
	assert_float(em.slow_f[e]).is_greater_equal(0.5)
	assert_float(em.hamper_t[e]).is_equal_approx(3.0, 0.01)
	assert_bool(em.status_tint[e].is_equal_approx(ProjectileManager.CURARE_TINT)).is_true()
	assert_float(em.status_t[e]).is_equal_approx(3.0, 0.01)
	assert_bool(pm.curare_holds(e)).is_true()
	assert_bool(em.is_poisoned(e)).is_true()
	# cooling down: a sure roll does not take for 10 s
	pm.curare_roll = 0.0
	pm.clock += 5.0
	pm.weapon_poison(e, inst)
	assert_int(pm.curare_procs).is_equal(1)
	pm.clock += 5.5
	pm.weapon_poison(e, inst)
	assert_int(pm.curare_procs).is_equal(2)
	# a cloud breathing on a creature every 0.3 s is one poisoning a second
	pm.curare_roll = 0.99
	pm.weapon_poison(f, inst)
	pm.clock += 0.3
	pm.weapon_poison(f, inst)
	pm.clock += 0.3
	pm.weapon_poison(f, inst)
	assert_float(pm.curare_chance(f)).is_equal_approx(0.4, 0.001)
	pm.clock += 0.6
	pm.weapon_poison(f, inst)
	assert_float(pm.curare_chance(f)).is_equal_approx(0.6, 0.001)


func test_the_grave_hail_bounces_three_full_size_and_doubles_the_poison_of_what_it_holds() -> void:
	var gh := _inst("grave_hail", ["plague", "curare", "bouncing_skull"])
	var bo: Dictionary = gh.params["bounce"]
	assert_int(int(bo["count"])).is_equal(3)
	for s in bo["scale"]:
		assert_float(float(s)).is_equal(1.0)
	var cu: Dictionary = gh.params["curare"]
	assert_float(float(cu["chance"])).is_equal(1.0)
	assert_float(float(cu["cooldown"])).is_equal(5.0)
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var a := _creature(em, Vector3(4, 0, 0))
	var b := _creature(em, Vector3(-4, 0, 0))
	em._rebuild_grid()
	var d := gh.stat("poison_damage")
	# the first poisoning takes, and what it holds takes the poison twice over
	pm.weapon_poison(a, gh)
	assert_bool(pm.curare_holds(a)).is_true()
	assert_float(float(em.poison_src[a]["grave_hail"]["dmg"])).is_equal_approx(d * 2.0, 0.001)
	pm.curare_roll = 1.5
	pm.weapon_poison(b, gh)
	assert_bool(pm.curare_holds(b)).is_false()
	assert_float(float(em.poison_src[b]["grave_hail"]["dmg"])).is_equal_approx(d, 0.001)
	# when the hold is over the dose falls back
	pm.clock += 3.5
	pm.weapon_poison(a, gh)
	assert_float(float(em.poison_src[a]["grave_hail"]["dmg"])).is_equal_approx(d, 0.001)


# ---------------------------------------------------------------- the Lob Grenade

func test_the_golden_pineapple_rides_the_strongest_and_blows_wider_with_spikes_and_bomblets() -> void:
	var path := ["new_equipment", "frag", "sticky"]
	var gp := _inst("golden_pineapple", path)
	assert_bool(bool(gp.params["sticky"]["priority"])).is_true()
	assert_int(int(gp.params["burst_spawn"]["count"])).is_equal(12)
	assert_int(int(gp.params["bomblets"])).is_equal(4)
	assert_float(float(gp.params["size_mult"])).is_equal_approx(1.35, 0.001)
	var w := _world(Vector3(-20, 0, 0))
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var small := _creature(em, Vector3(5, 0, 0.5), 50.0)
	var big := _creature(em, Vector3(5.8, 0, -0.8), 500.0)
	# a crowd of ordinary ones far off: the big one stands out against the crowd's mean
	for n in range(4):
		_creature(em, Vector3(40.0, 0, 10.0 * n), 50.0)
	em._rebuild_grid()
	em.refresh_crowd_stats()
	var k := pm.register_kind(BoxMesh.new(), null)
	var lp: Dictionary = gp.params.duplicate()
	lp["throw_dir"] = Vector3(1, 0, 0)
	var area := gp.stat("area")
	var j := pm.lob(k, Vector3(0, 1.2, 0), Vector3(5, 0, 0), 9.0, gp.stat("damage"), area, gp, 2.0, lp)
	var rode := -1
	for n in range(120):
		pm._physics_process(DT)
		if pm.alive[j] == 1 and pm.stuck[j] >= 0:
			rode = pm.stuck[j]
			break
	assert_int(rode).is_equal(big)
	assert_int(rode).is_not_equal(small)
	# a witness past the plain blast but inside the 40% wider one
	var at: Vector3 = em.pos[big]
	var witness := _creature(em, at + Vector3(0, 0, area * 1.25), 50.0)
	em._rebuild_grid()
	var hw: float = em.hp[witness]
	for n in range(100):
		pm._physics_process(DT)
		if pm.lobs_exploded > 0:
			break
	assert_int(pm.lobs_exploded).is_equal(1)
	assert_float(em.hp[witness]).is_less(hw)
	var spikes := 0
	var bomblets := 0
	for q in range(ProjectileManager.MAX):
		if pm.alive[q] == 0:
			continue
		var ex: Dictionary = pm.extra[q]
		if ex.has("shrapnel"):
			spikes += 1
		elif ex.has("is_bomblet"):
			bomblets += 1
			assert_float(pm.psize[q]).is_equal_approx(1.35 * 0.5, 0.001)
	assert_int(spikes).is_equal(12)
	assert_int(bomblets).is_equal(4)


# ---------------------------------------------------------------- the Molotov

func test_methanol_burns_blue_and_its_bottle_comes_with_it() -> void:
	var plain := _inst("molotov")
	assert_bool(plain.blue_fire()).is_false()
	var me := _inst("molotov", ["methanol"])
	assert_bool(me.blue_fire()).is_true()
	assert_object(me.visual_scene()).is_same(Registry.mutation("methanol").visual)
	assert_object(me.visual_scene()).is_not_same(plain.visual_scene())
	# the evolution keeps its jug, and its fire is blue whatever it carries
	var ms := _inst("moonshine", ["accelerant", "methanol", "oil_slick"])
	assert_object(ms.visual_scene()).is_same(Registry.weapon("moonshine").visual)
	assert_bool(ms.blue_fire()).is_true()
	assert_bool(_inst("moonshine").blue_fire()).is_true()
	# taken mid-run, the bottle on the weapon changes
	var w := _world()
	var g: Node = w["g"]
	var pm: ProjectileManager = w["pm"]
	var lb := Lobber.new()
	g.add_child(lb)
	var held := _inst("molotov")
	lb.setup(held, g)
	var k0 := lb.projectile_kind
	assert_str(str(lb.visual.name)).is_equal("MolotovVisual")
	held.mutations.append(Registry.mutation("methanol"))
	held.rebuild(Run.player_sheet, [held])
	lb.refresh_marks()
	assert_str(str(lb.visual.name)).is_equal("MethanolVisual")
	assert_int(lb.projectile_kind).is_not_equal(k0)
	# its pool is half again as wide as the blast, and blue
	var lp: Dictionary = me.params.duplicate()
	pm.lob(lb.projectile_kind, Vector3(0, 1.2, 0), Vector3(6, 0, 0), 10.0, 8.0, me.stat("area"), me, 2.0, lp)
	for n in range(120):
		pm._physics_process(DT)
	var pools: Array = g.get("clouds")
	assert_int(pools.size()).is_equal(1)
	assert_float(float(pools[0]["r"])).is_equal_approx(me.stat("area") * 1.5, 0.001)
	assert_bool((pools[0]["node"] as ElementCloud).blue).is_true()


func test_the_moonshine_lays_a_burning_line_and_a_long_growing_pool() -> void:
	var w := _world(Vector3(-20, 0, 0))
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	var ms := _inst("moonshine", ["accelerant", "methanol", "oil_slick"])
	assert_float(float(ms.params["cloud_seconds"])).is_equal(9.0)
	var k := pm.register_kind(BoxMesh.new(), null)
	var lp: Dictionary = ms.params.duplicate()
	lp["throw_dir"] = Vector3(1, 0, 0)
	pm.lob(k, Vector3(0, 1.2, 0), Vector3(10, 0, 0), 11.0, 10.0, ms.stat("area"), ms, 2.0, lp)
	for n in range(200):
		pm._physics_process(DT)
	var clouds: Array = g.get("clouds")
	var pieces: Array = clouds.filter(func(c: Dictionary) -> bool: return (c["params"] as Dictionary).has("line_to"))
	var pools: Array = clouds.filter(func(c: Dictionary) -> bool: return not (c["params"] as Dictionary).has("line_to"))
	assert_int(pieces.size()).is_greater_equal(4)
	assert_int(pools.size()).is_equal(1)
	# end to end along the throw, from a metre and a half out to where the jug broke
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["at"] as Vector3).x < (b["at"] as Vector3).x)
	assert_float((pieces[0]["at"] as Vector3).x).is_between(1.4, 2.4)
	for n in range(1, pieces.size()):
		var prev: Vector3 = (pieces[n - 1]["params"] as Dictionary)["line_to"]
		assert_float(Vector2(prev.x - (pieces[n]["at"] as Vector3).x, prev.z - (pieces[n]["at"] as Vector3).z).length()).is_less(0.01)
	var end: Vector3 = (pieces[pieces.size() - 1]["params"] as Dictionary)["line_to"]
	assert_float(Vector2(end.x - (pools[0]["at"] as Vector3).x, end.z - (pools[0]["at"] as Vector3).z).length()).is_less(0.01)
	var piece: ElementCloud = pieces[0]["node"]
	assert_bool(piece.blue).is_true()
	assert_float(piece.slow).is_greater(0.0)
	# the pool burns three times as long as the Molotov's and grows
	var pool: ElementCloud = pools[0]["node"]
	assert_float(pool.life).is_equal_approx(9.0, 0.001)
	assert_float(pool.grow).is_equal_approx(0.6, 0.001)
	var r0 := pool.radius
	pool._process(4.5)
	assert_float(pool.radius).is_greater(r0)


func test_a_moonshine_burning_death_splashes_a_pool_six_at_most() -> void:
	var w := _world(Vector3(0, 0, -30))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var ms := _inst("moonshine", ["accelerant", "methanol", "oil_slick"])
	var lb := Lobber.new()
	g.add_child(lb)
	lb.setup(ms, g)
	# a death by something else leaves nothing
	var c0 := _creature(em, Vector3(20, 0, 0), 1.0)
	em.damage(c0, 9999.0, "peashooter")
	assert_int(lb.death_pools).is_equal(0)
	for n in range(9):
		var c := _creature(em, Vector3(-10.0 + 2.5 * n, 0, 6), 1.0)
		em.ignite(c, "moonshine", 4.0, 3.0, 0.0)
		em.damage(c, 9999.0, "moonshine")
	assert_int(lb.death_pools).is_equal(6)
	assert_int(lb.death_pool_count()).is_equal(6)
	var pools: Array = (g.get("clouds") as Array).filter(func(c: Dictionary) -> bool: return str((c["params"] as Dictionary).get("death_of", "")) == "moonshine")
	assert_int(pools.size()).is_equal(6)
	for p: Dictionary in pools:
		assert_float(float(p["r"])).is_equal_approx(1.0, 0.001)
		assert_bool((p["node"] as ElementCloud).blue).is_true()
		assert_float((p["node"] as ElementCloud).life).is_equal_approx(3.0, 0.001)


# ---------------------------------------------------------------- the Hornet Nest

func test_flowers_grow_only_while_pollen_is_held_three_at_most_out_on_the_sand() -> void:
	var w := _world()
	var g: Node = w["g"]
	Run.add_weapon(Registry.weapon("hornet_nest"), 1)
	# nothing carries Pollen: a field made anyway goes by itself
	var f0 := FlowerField.ensure(g)
	f0._process(0.6)
	assert_bool(f0.is_queued_for_deletion()).is_true()
	assert_object(FlowerField.of(g)).is_null()
	assert_bool(Run.add_mutation("pollen", true)).is_true()
	var f := FlowerField.ensure(g)
	assert_object(FlowerField.of(g)).is_same(f)
	assert_bool(f.is_in_group("flower_field")).is_true()
	# the first comes a little after, 10-18 m out
	f._process(FlowerField.FIRST + 0.1)
	assert_int(f.live_count()).is_equal(1)
	assert_float((f.positions()[0] as Vector3).length()).is_between(10.0, 18.0)
	# then one every 8-12 s, never more than three at once
	for n in range(60):
		f._process(0.5)
		assert_int(f.live_count()).is_less_equal(3)
	for x: float in [30.0, -30.0, 0.0, 15.0]:
		f.grow_at(Vector3(x, 0, 30.0), false)
	assert_int(f.live_count()).is_equal(3)
	# a flower lives 15 s, blinks 4 s, and goes
	var w2 := _world()
	var f2 := FlowerField.new()
	f2.game = w2["g"]
	(w2["g"] as Node).add_child(f2)
	f2.grow_at(Vector3(12, 0, 0), false)
	var blinked := false
	for n in range(37):
		f2._tick_flowers(0.5)
		var sp: BillboardSprite = f2.flowers[0]["sprite"]
		if not sp.visible:
			blinked = true
		# no blinking in its first fifteen seconds
		if n < 29:
			assert_bool(sp.visible).is_true()
	assert_bool(blinked).is_true()
	assert_int(f2.positions().size()).is_equal(1)
	f2._tick_flowers(0.6)
	assert_int(f2.positions().size()).is_equal(0)
	f2._tick_flowers(0.4)
	assert_int(f2.flowers.size()).is_equal(0)


func test_a_picked_flower_gives_four_times_the_bees_half_again_as_fast_for_five_seconds() -> void:
	var w := _world()
	var g: Node = w["g"]
	Run.add_weapon(Registry.weapon("hornet_nest"), 3)
	Run.add_mutation("pollen", true)
	var inst := Run.weapon_instance("hornet_nest")
	var am0 := inst.stat_int("amount")
	var sp0 := inst.stat("speed")
	var f := FlowerField.ensure(g)
	f.grow_at(Vector3(0.6, 0, 0.6), false)
	f._tick_flowers(0.5)
	assert_int(f.picked).is_equal(1)
	assert_int(f.live_count()).is_equal(0)
	assert_int(inst.stat_int("amount")).is_equal(am0 * 4)
	assert_float(inst.stat("speed")).is_equal_approx(sp0 * 1.5, 0.001)
	assert_float(Run.boost_left(FlowerField.buff_id("hornet_nest"))).is_equal_approx(5.0, 0.01)
	# while it lasts the bees fly red, with red trails
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(5, 0, 0))
	em._rebuild_grid()
	var mp := MissilePod.new()
	g.add_child(mp)
	mp.setup(inst, g)
	assert_bool(mp.pollen_on()).is_true()
	assert_bool(mp._fire()).is_true()
	mp._tick(0.01)
	var red := 0
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst:
			assert_int(int(pm.extra[j]["trail"])).is_equal(4)
			assert_int(pm.kind[j]).is_not_equal(mp.projectile_kind)
			red += 1
	assert_int(red).is_greater(0)
	# five seconds on, it is over
	Run.elapsed += 5.1
	Run.tick_timed()
	assert_int(inst.stat_int("amount")).is_equal(am0)
	assert_float(inst.stat("speed")).is_equal_approx(sp0, 0.001)
	assert_bool(mp.pollen_on()).is_false()


func test_a_hawk_takes_one_creature_stings_five_times_and_goes_with_it() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var inst := _inst("hornet_nest", ["tarantula_hawk"], 5)
	var cfg: Dictionary = inst.params["hawk"]
	var big := _creature(em, Vector3(4, 0, 0), 60.0)
	var small := _creature(em, Vector3(-3, 0, 0), 20.0)
	# their health pinned (pass 49): one skeleton in ten spawns a tinted special at 2.2 times the health, and a special
	# small one had outweighed the big one now and then
	for pair in [[big, 600.0], [small, 200.0]]:
		em.hp[int(pair[0])] = float(pair[1])
		em.max_hp[int(pair[0])] = float(pair[1])
	em._rebuild_grid()
	em.refresh_crowd_stats()
	var first := TarantulaHawk.pick(em, Vector3.ZERO, 12.0, TarantulaHawk.held_serials(g))
	assert_int(first).is_equal(big)
	var h1 := TarantulaHawk.launch(g, inst, Vector3(0, 1.6, 0), first, cfg)
	# one hawk a creature: the next takes the other one, and then there is none
	var second := TarantulaHawk.pick(em, Vector3.ZERO, 12.0, TarantulaHawk.held_serials(g))
	assert_int(second).is_equal(small)
	var h2 := TarantulaHawk.launch(g, inst, Vector3(0, 1.6, 0), second, cfg)
	assert_int(TarantulaHawk.pick(em, Vector3.ZERO, 12.0, TarantulaHawk.held_serials(g))).is_equal(-1)
	# five stings over four seconds, each a bee's damage; its prey slowed and purple while it holds it
	var hp0: float = em.hp[big]
	var held_seen := false
	var t := 0.0
	while t < 7.0 and not h1.is_queued_for_deletion():
		h1.tick(DT)
		t += DT
		if h1.state == TarantulaHawk.HOLD and h1.stings_done >= 2:
			held_seen = true
			assert_float(em.attack_clock(big)).is_equal_approx(0.9, 0.001)
			assert_bool(em.status_tint[big].is_equal_approx(TarantulaHawk.TINT)).is_true()
	assert_bool(held_seen).is_true()
	assert_int(h1.stings_done).is_equal(5)
	assert_float(hp0 - em.hp[big]).is_equal_approx(5.0 * inst.stat("damage"), 0.01)
	assert_float(t).is_between(4.0, 6.0)
	assert_bool(h1.is_queued_for_deletion()).is_true()
	# its prey dies: it drops and fades, and never goes after another
	for n in range(30):
		h2.tick(DT)
	assert_int(h2.state).is_equal(TarantulaHawk.HOLD)
	em.damage(small, 99999.0, "x")
	var s2 := h2.stings_done
	for n in range(60):
		h2.tick(DT)
	assert_int(h2.state).is_equal(TarantulaHawk.FALLING)
	assert_bool(h2.is_queued_for_deletion()).is_true()
	assert_int(h2.stings_done).is_equal(s2)


func test_the_pod_sends_a_hawk_every_fourth_burst_and_every_burst_on_pollen() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	for n in range(6):
		_creature(em, Vector3(3.0 + n, 0, 0))
	em._rebuild_grid()
	Run.add_weapon(Registry.weapon("hornet_nest"), 1)
	Run.add_mutation("tarantula_hawk", true)
	var inst := Run.weapon_instance("hornet_nest")
	var mp := MissilePod.new()
	g.add_child(mp)
	mp.setup(inst, g)
	for n in range(8):
		assert_bool(mp._fire()).is_true()
	assert_int(mp.hawks_sent).is_equal(2)
	Run.add_timed_effects(FlowerField.buff_id("hornet_nest"), "Pollen", [], 5.0, true)
	mp._fire()
	assert_int(mp.hawks_sent).is_equal(3)
	# the Hive Queen: a hawk every burst, Second Sting twice, flowers from kills
	var hq := _inst("hive_queen", ["pollen", "tarantula_hawk", "second_sting"])
	assert_int(int(hq.params["hawk"]["every"])).is_equal(1)
	assert_int(int(hq.params["second_sting"])).is_equal(2)
	assert_float(float(hq.params["flower_on_kill"])).is_equal_approx(0.15, 0.001)


func test_a_hive_queen_kill_sprouts_a_flower_where_it_fell() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	Run.add_weapon(Registry.weapon("hornet_nest"), 1)
	Run.add_mutation("pollen", true)
	var f := FlowerField.ensure(g)
	var hq := _inst("hive_queen", ["pollen", "tarantula_hawk", "second_sting"])
	hq.params["flower_on_kill"] = 1.0
	var c := _creature(em, Vector3(6, 0, 3), 0.05)
	em._rebuild_grid()
	var k := pm.register_kind(BoxMesh.new(), null)
	pm.launch_missile(k, Vector3(0, 1.5, 0), Vector3(1, 0.2, 0.5), 17.0, 50.0, 0.0, 12.0, hq,
		{"wander": 0.0, "turn": 14.0, "spiral": 0.0, "life": 3.0, "trail": 2}, 1.0)
	for n in range(120):
		pm._physics_process(DT)
		if em.state[c] == EnemyManager.STATE_DYING:
			break
	assert_int(em.state[c]).is_equal(EnemyManager.STATE_DYING)
	assert_int(f.live_count()).is_equal(1)
	assert_float(Vector2((f.positions()[0] as Vector3).x - 6.0, (f.positions()[0] as Vector3).z - 3.0).length()).is_less(1.0)


# ---------------------------------------------------------------- the rest

func test_no_mutation_hangs_an_emblem_any_more() -> void:
	# re-pinned in pass 60 (Garry: "remove all the current little halos that appear over weapons after a mutation is
	# applied"): the emblem builder and its colours are gone; refresh_marks builds nothing and frees one left hanging
	var b: WeaponBehavior = auto_free(WeaponBehavior.new())
	assert_bool(b.has_method("_mark_colour")).is_false()
	assert_bool(b.has_method("_mark_for")).is_false()
	assert_bool(b.has_method("_tick_marks")).is_false()
	assert_bool(b.has_method("shows_marks")).is_false()
	var old := Node3D.new()
	old.name = "MutationMarks"
	b.add_child(old)
	b.refresh_marks()
	assert_object(b.get_node_or_null("MutationMarks")).is_null()


func test_the_new_mutations_and_evolutions_say_what_they_do() -> void:
	for id in ["birdshot_lane", "big_peas", "mini_crits", "silver_bullet", "hip_shot", "bouncing_skull", "curare",
			"new_equipment", "methanol", "pollen", "tarantula_hawk"]:
		var m: MutationDef = Registry.mutation(id)
		assert_bool(m.text.length() > 20).override_failure_message(id).is_true()
		assert_bool(m.hidden).is_false()
	assert_str(Registry.mutation("birdshot_lane").text).contains("2.6 m")
	assert_str(Registry.mutation("birdshot_lane").text).contains("40%")
	assert_str(Registry.mutation("hip_shot").text).contains("0.12 s")
	assert_str(Registry.mutation("bouncing_skull").text).contains("30°")
	assert_str(Registry.mutation("tarantula_hawk").text).contains("4 s")
	for base: String in FAMILIES.keys():
		var evo: WeaponDef = Registry.weapon(FAMILIES[base])
		assert_bool(evo.flavour.length() > 20).override_failure_message(evo.id).is_true()
	assert_str(Registry.weapon("blunderbuss").flavour).contains("75°")
	assert_str(Registry.weapon("golden_pineapple").flavour).contains("12")
	# the flowers are pickups the creatures never drop
	for id in FlowerField.KINDS:
		var p: PickupDef = Registry.pickup(id)
		assert_object(p).override_failure_message(id).is_not_null()
		assert_str(p.effect_kind).is_equal("pollen")
		assert_float(p.weight).is_equal(0.0)
		assert_bool(bool(p.params.get("small", false))).is_true()


func test_every_evolution_beats_its_weapon_at_the_top_with_the_whole_path() -> void:
	seed(48)
	for base: String in FAMILIES.keys():
		var def: WeaponDef = Registry.weapon(base)
		assert_str(def.evolves_into).is_equal(FAMILIES[base])
		var path: Array = Registry.mutations_of(base).map(func(m: MutationDef) -> String: return m.id)
		assert_int(path.size()).override_failure_message(base).is_equal(3)
		var top := _inst(base, path, def.max_level)
		var evo := _inst(def.evolves_into, path)
		assert_float(evo.dps_estimate()).override_failure_message("%s %.1f is not past %s %.1f" % [evo.def.id, evo.dps_estimate(), base, top.dps_estimate()]).is_greater(top.dps_estimate())
