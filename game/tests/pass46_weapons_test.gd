extends GdUnitTestSuite

## Pass 46, the weapons. The Guitarra's cone of melody (ConeWave): it hits only inside its angle, lifts what it hits and
## sets it down on the spot it stood with nothing more than the chord's damage, Far Reach's half circle further at half
## damage, Music Slap's sideways shove, echoes for Multishot, Bosses and Elites only hit, its path. The Spear (Ironwood's
## alone): it flies without tumbling, stands in the sand where it comes down, pins the first creature it strikes; the
## Spear Volley is three for every one, the War Lance leaves slowing dust. The Turret Buddy's model on each stance, Buddy
## Squad doubling the drop and the cap at -40%, its rounds keeping the muzzle's height. The Big Mouth's wind-up and its
## boiling sand over a hill. The Hammer's beats and size. And the words for all of it.

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
var zones := 0
var sands := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	sands += 1
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _c = Color.WHITE):
	zones += 1
	return null
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

## a dune three metres high at x = 6 on the line east of the hero
const HILL := """extends RefCounted
func height_at(x: float, z: float) -> float:
	return 3.0 * exp(-((x - 6.0) * (x - 6.0) + z * z) / 2.0)
"""

const FLAT := """extends RefCounted
func height_at(_x: float, _z: float) -> float:
	return 0.0
"""

const DT := 1.0 / 60.0
const EAST := Vector3(1, 0, 0)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks. Astro's run: no
## crits to roll (Calavera's Last Dance would double a hit now and then).
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


## A tough creature on its feet where it was put.
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	return i


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


## The guitar held over the hero's head, so the cone starts at his feet.
func _hold_still(cw: ConeWave) -> void:
	cw.inst.params["familiar"] = {"radius": 0.0, "height": 1.5, "bob": 0.0}
	cw._familiar.global_position = Vector3(0, 1.5, 0)


func _cone(w: Dictionary, id: String, muts: Array = []) -> ConeWave:
	var cw := ConeWave.new()
	(w["g"] as Node).add_child(cw)
	cw.setup(_inst(id, muts), w["g"])
	_hold_still(cw)
	return cw


# ---------------------------------------------------------------- the Guitarra

func test_the_guitarra_is_a_cone_now() -> void:
	var g: WeaponDef = Registry.weapon("guitarra")
	assert_str(g.behavior).is_equal("ConeWave")
	assert_str(g.hero).is_equal("calavera")
	# no shotgun keys left, and no level adds waves (Multishot's job)
	for k in ["pierce", "speed", "spread_deg"]:
		assert_bool(g.base.has(k)).override_failure_message("guitarra still has " + k).is_false()
	for k in ["burst", "strum", "no_shells"]:
		assert_bool(g.params.has(k)).override_failure_message("guitarra still has params." + k).is_false()
	for lv in g.levels:
		for e: Effect in lv:
			assert_str(e.stat).is_not_equal("amount")
	var r: WeaponDef = Registry.weapon("requiem")
	assert_str(r.behavior).is_equal("ConeWave")
	assert_float(TextGen.cone_width(r.params)).is_equal(360.0)
	assert_float(float(r.base["cooldown"])).is_less(float(g.base["cooldown"]))
	assert_float(float(r.params["cone"]["lift"])).is_greater(float(g.params["cone"]["lift"]))
	assert_float(float(r.base["damage"])).is_greater(float(g.base["damage"]))
	# the visuals hold the guitar upright under the Familiar, nothing to shoot
	for id in ["guitarra", "requiem"]:
		var vis: Node = (Registry.weapon(id).visual as PackedScene).instantiate()
		var fam: Node = vis.get_node_or_null("Familiar")
		assert_object(fam).is_not_null()
		assert_object(fam.find_child("Body", true, false)).is_not_null()
		assert_object(fam.find_child("Strings", true, false)).is_not_null()
		assert_object(fam.find_child("Soundhole", true, false)).is_not_null()
		assert_object(vis.get_node_or_null("Projectile")).is_null()
		vis.free()


func test_the_cone_hits_only_inside_its_angle() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# 70 degrees, 6 m: straight ahead and 17 degrees off are in; 52 degrees off, behind and 7.5 m out are not
	var inside := [_creature(em, Vector3(3, 0, 0)), _creature(em, Vector3(4, 0, 1.2))]
	var outside := [_creature(em, Vector3(2, 0, 2.6)), _creature(em, Vector3(-3, 0, 0)), _creature(em, Vector3(7.5, 0, 0))]
	em._rebuild_grid()
	var hp := {}
	for i: int in inside + outside:
		hp[i] = em.hp[i]
	var cw := _cone(w, "guitarra")
	assert_float(TextGen.cone_width(cw.inst.params)).is_equal_approx(70.0, 0.01)
	var notes0: int = (w["fx"] as Fx).note_count()
	cw._wave(EAST, 1.0, false)
	for i: int in inside:
		assert_float(em.hp[i]).is_less(hp[i])
		assert_bool(cw.last_hits.has(i)).is_true()
	for i: int in outside:
		assert_float(em.hp[i]).is_equal(hp[i])
		assert_bool(cw.last_hits.has(i)).is_false()
	assert_int(cw.waves).is_equal(1)
	# seen and heard: a wash and a ring on the sand, notes flying, the guitar rocked and its strings ringing
	assert_int((w["tg"] as Telegraphs).live_count()).is_greater_equal(2)
	assert_int((w["fx"] as Fx).note_count() - notes0).is_greater_equal(6)
	assert_float(cw._rock_v).is_greater(0.0)
	assert_float(cw._shimmer).is_equal(1.0)


func test_a_chord_lifts_them_and_sets_them_down_on_their_spot() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var cw := _cone(w, "guitarra")
	var hp0: float = em.hp[i]
	cw._wave(EAST, 1.0, false)
	# the chord's damage, and up it goes
	var hp1: float = em.hp[i]
	assert_float(hp1).is_less(hp0)
	assert_int(em.lift_mode[i]).is_equal(1)
	var at: Vector3 = em.pos[i]
	var lift := float(cw.inst.params["cone"]["lift"])
	var top := 0.0
	var t := 0.0
	while em.lift_t[i] > 0.0 and t < 2.0:
		em._physics_process(DT)
		t += DT
		top = maxf(top, em.lift_h[i])
	assert_float(t).is_between(float(cw.inst.params["cone"]["lift_time"]) - DT, float(cw.inst.params["cone"]["lift_time"]) + DT * 2.0)
	assert_float(top).is_between(lift * 0.9, lift + 0.001)
	# down on the very spot, hurt by nothing but the chord
	assert_float(Vector2(em.pos[i].x - at.x, em.pos[i].z - at.z).length()).is_less(0.001)
	assert_float(em.hp[i]).is_equal(hp1)
	# with the chord's small shove, straight away from the guitar
	assert_float(em.kb[i].x).is_greater(0.0)
	assert_float(absf(em.kb[i].z)).is_less(0.001)


func test_bosses_and_elites_only_take_the_hit() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var e := _creature(em, Vector3(3, 0, 0), 5.0, "dune_scorpion")
	em._rebuild_grid()
	var hp0: float = em.hp[e]
	var cw := _cone(w, "guitarra")
	cw._wave(EAST, 1.0, false)
	assert_float(em.hp[e]).is_less(hp0)
	assert_float(em.lift_t[e]).is_equal(0.0)


func test_far_reach_is_half_a_circle_half_again_as_far_at_half_damage() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var base := _inst("guitarra")
	var cw := _cone(w, "guitarra", ["far_reach"])
	assert_float(TextGen.cone_width(cw.inst.params)).is_equal_approx(180.0, 0.01)
	assert_float(cw.stat("range")).is_equal_approx(base.stat("range") * 1.5, 0.001)
	assert_float(cw.stat("damage")).is_equal_approx(base.stat("damage") * 0.5, 0.001)
	# 85 degrees off the aim and 8 m out is caught, 95 degrees is not
	var a := _creature(em, Vector3(cos(deg_to_rad(85.0)), 0, sin(deg_to_rad(85.0))) * 8.0)
	var b := _creature(em, Vector3(cos(deg_to_rad(95.0)), 0, sin(deg_to_rad(95.0))) * 8.0)
	em._rebuild_grid()
	cw._wave(EAST, 1.0, false)
	assert_bool(cw.last_hits.has(a)).is_true()
	assert_bool(cw.last_hits.has(b)).is_false()
	# it never narrows the Requiem's full ring
	var rq := WeaponInstance.new(Registry.weapon("requiem"), 1)
	rq.mutations = [Registry.mutation("far_reach")]
	rq.rebuild(Run.player_sheet, [rq])
	assert_float(TextGen.cone_width(rq.params)).is_equal(360.0)


func test_music_slap_hits_harder_and_slaps_them_aside() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var base := _inst("guitarra")
	var cw := _cone(w, "guitarra", ["music_slap"])
	assert_float(cw.stat("damage")).is_equal_approx(base.stat("damage") * 1.6, 0.001)
	assert_float(cw.stat("cooldown")).is_equal_approx(base.stat("cooldown") * 1.4, 0.001)
	var i := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	cw._wave(EAST, 1.0, false)
	# the landing shove runs across the chord, not along it, and harder than the plain chord's
	var k: Vector3 = em.lift_knock[i]
	assert_float(absf(k.x)).is_less(0.001)
	assert_float(absf(k.z)).is_greater(float(base.params["cone"]["knock"]) / maxf(em.size[i], 0.8))


func test_the_guitarra_path_and_ember_chord_burns() -> void:
	var ids: Array = Registry.mutations_of("guitarra").map(func(m: MutationDef) -> String: return m.id)
	# pass 48: Tinnitus took Ember Chord's element slot; Ember Chord is hidden, kept, and still burns when carried
	assert_array(ids).is_equal(["tinnitus", "far_reach", "music_slap"])
	assert_bool(Registry.mutation("ember_chord").hidden).is_true()
	assert_object(Registry.mutation("power_chord")).is_null()
	assert_object(Registry.mutation("tremolo")).is_null()
	# Calavera's own stays on the Skull Rain
	assert_str(Registry.mutation("danza_macabra").weapon).is_equal("skull_rain")
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var cw := _cone(w, "guitarra", ["ember_chord"])
	cw._wave(EAST, 1.0, false)
	assert_bool(em.has_element(i, "fire")).is_true()


func test_multishot_sends_echo_waves_at_sixty_percent() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var cw := _cone(w, "guitarra")
	cw.inst.bonus_effects = [Effect.make("amount", "add", 2.0)]
	cw.inst.rebuild(Run.player_sheet, [cw.inst])
	_hold_still(cw)
	assert_int(cw.stat_int("amount")).is_equal(3)
	var hp0: float = em.hp[i]
	assert_bool(cw._fire()).is_true()
	assert_int(cw.waves).is_equal(1)
	var d1: float = hp0 - em.hp[i]
	cw._tick(0.21)
	assert_int(cw.waves).is_equal(2)
	var d2: float = hp0 - d1 - em.hp[i]
	assert_float(d2 / d1).is_equal_approx(WeaponInstance.ECHO_FRAC, 0.001)
	cw._tick(0.2)
	assert_int(cw.waves).is_equal(3)
	cw._tick(0.5)
	assert_int(cw.waves).is_equal(3)
	# a cooldown shorter than the echoes packs them closer instead of losing one
	cw.inst.bonus_effects = [Effect.make("amount", "add", 5.0), Effect.make("cooldown", "set", 0.6)]
	cw.inst.rebuild(Run.player_sheet, [cw.inst])
	_hold_still(cw)
	assert_bool(cw._fire()).is_true()
	var last: float = 0.0
	for e: Dictionary in cw._echoes:
		last = maxf(last, float(e["t"]))
	assert_int(cw._echoes.size()).is_equal(5)
	assert_float(last).is_less(cw.stat("cooldown"))


# ---------------------------------------------------------------- the Spear

func test_the_spear_is_ironwoods_alone() -> void:
	var s: WeaponDef = Registry.weapon("spear")
	assert_object(s).is_not_null()
	assert_str(s.hero).is_equal("ironwood")
	assert_str(s.behavior).is_equal("ProjectileEmitter")
	assert_int(int(s.base["pierce"])).is_greater_equal(99)
	assert_bool(s.params.get("plant") is Dictionary).is_true()
	assert_bool(bool(s.params.get("no_spin", false))).is_true()
	for lv in s.levels:
		for e: Effect in lv:
			assert_str(e.stat).is_not_equal("amount")
	assert_str(s.evolves_into).is_equal("war_lance")
	assert_object(WeaponBehavior.projectile_source(auto_free((s.visual as PackedScene).instantiate()))).is_not_null()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	assert_bool(Registry.unlocked_weapons().map(func(x): return x.id).has("spear")).is_false()
	# pass 47: the old spear is shelved (hidden, "Throwing Spear"): Ironwood no longer finds it either, and lands with the
	# Pike
	Run.start(Registry.character("ironwood"), Registry.map("red_canyon"))
	assert_bool(s.hidden).is_true()
	assert_bool(Registry.unlocked_weapons().map(func(x): return x.id).has("spear")).is_false()
	assert_str(Registry.character("ironwood").start_weapon).is_equal("pike")
	# the War Lance: his too, two spears a throw at twice the damage, a trail of dust
	var l: WeaponDef = Registry.weapon("war_lance")
	assert_str(l.evolved_from).is_equal("spear")
	assert_str(l.hero).is_equal("ironwood")
	assert_bool(l.is_evolution).is_true()
	assert_int(int(l.base["amount"])).is_equal(2)
	assert_float(float(l.base["damage"])).is_equal_approx(float(s.base["damage"]) * 2.0, 0.001)
	assert_bool(l.params.get("trail_zone") is Dictionary).is_true()
	assert_object(WeaponBehavior.projectile_source(auto_free((l.visual as PackedScene).instantiate()))).is_not_null()
	# its path: an element, a volume and a motion
	var ids: Array = Registry.mutations_of("spear").map(func(m: MutationDef) -> String: return m.id)
	assert_array(ids).is_equal(["fire_hardened", "spear_volley", "pinning_throw"])
	Run.end()


func _spear_kind(pm: ProjectileManager, id: String) -> int:
	var vis: Node = auto_free((Registry.weapon(id).visual as PackedScene).instantiate())
	var src := WeaponBehavior.projectile_source(vis)
	return pm.register_kind(src.mesh, null, 0.8)


func test_a_spear_flies_straight_and_stands_in_the_sand_where_it_comes_down() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var inst := _inst("spear")
	var k := _spear_kind(pm, "spear")
	var i := pm.fire(k, Vector3(0, 0.8, 0), EAST * 20.0, 22.0, 99, 0.35, 0.3, inst, 4.0)
	assert_float(pm.spin[i]).is_equal(0.0)
	for n in range(4):
		pm._physics_process(0.05)
	# no tumbling on the way
	assert_float(pm.spin[i]).is_equal(0.0)
	assert_bool(pm.extra[i].has("planted")).is_false()
	for n in range(4):
		pm._physics_process(0.05)
	# its flight is over: it stands still, tipped down along its heading, the point in the sand and the shaft out of it
	assert_int(pm.alive[i]).is_equal(1)
	assert_bool(pm.extra[i].has("planted")).is_true()
	assert_float(pm.vel[i].length()).is_equal(0.0)
	var b: Basis = pm.extra[i]["planted"]
	var fwd := -b.z
	var tilt := deg_to_rad(float(inst.params["plant"].get("tilt_deg", 70.0)))
	assert_float(fwd.x).is_equal_approx(cos(tilt), 0.01)
	assert_float(fwd.y).is_equal_approx(-sin(tilt), 0.01)
	assert_float(absf(fwd.z)).is_less(0.01)
	var reach: float = float(pm.kinds[k]["tip"]) * float(pm.kinds[k]["scale"])
	assert_float((pm.pos[i] + fwd * reach).y).is_less(0.0)
	assert_float(pm.pos[i].y).is_greater(0.0)
	assert_int(g.sands).is_greater_equal(1)
	# it hurts nothing while it stands there
	var c := _creature(em, Vector3(pm.pos[i].x, 0, pm.pos[i].z))
	em._rebuild_grid()
	var hp0: float = em.hp[c]
	pm._physics_process(0.05)
	assert_float(em.hp[c]).is_equal(hp0)
	# and it goes once its time is up
	for n in range(14):
		pm._physics_process(0.05)
	assert_int(pm.alive[i]).is_equal(0)


func test_a_pinning_throw_holds_the_first_one_it_strikes() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(2, 0, 0))
	var b := _creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	var k := _spear_kind(pm, "spear")
	pm.fire(k, Vector3(0, 0.8, 0), EAST * 20.0, 5.0, 99, 0.35, 0.5, _inst("spear", ["pinning_throw"]), 0.0)
	for n in range(6):
		pm._physics_process(0.05)
	assert_float(em.slow_f[a]).is_equal(1.0)
	assert_float(em.slow_t[a]).is_equal_approx(1.2, 0.001)
	assert_float(em.slow_t[b]).is_equal(0.0)
	# a plain spear pins nobody
	var c := _creature(em, Vector3(2, 0, 3))
	em._rebuild_grid()
	pm.fire(k, Vector3(0, 0.8, 3), EAST * 20.0, 5.0, 99, 0.35, 0.5, _inst("spear"), 0.0)
	for n in range(6):
		pm._physics_process(0.05)
	assert_float(em.slow_t[c]).is_equal(0.0)


func test_a_spear_volley_is_three_for_every_one_fanned() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var base := _inst("spear")
	var v := _inst("spear", ["spear_volley"])
	assert_int(v.stat_int("amount")).is_equal(3)
	assert_float(v.stat("damage")).is_equal_approx(base.stat("damage") * 0.6, 0.001)
	# Multishot still counts: three for every spear
	v.bonus_effects = [Effect.make("amount", "add", 1.0)]
	v.rebuild(Run.player_sheet, [v])
	assert_int(v.stat_int("amount")).is_equal(6)
	# thrown, the three fan out
	_creature(em, Vector3(6, 0, 0))
	em._rebuild_grid()
	var pe := ProjectileEmitter.new()
	(w["g"] as Node).add_child(pe)
	pe.setup(_inst("spear", ["spear_volley"]), w["g"])
	assert_bool(pe._fire()).is_true()
	var angles: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.kind[j] == pe.projectile_kind:
			angles.append(rad_to_deg(atan2(pm.vel[j].z, pm.vel[j].x)))
	assert_int(angles.size()).is_equal(3)
	angles.sort()
	assert_float(float(angles[2]) - float(angles[0])).is_greater(20.0)


func test_the_war_lance_leaves_a_trail_of_slowing_dust() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	# a plain spear leaves none
	pm.fire(_spear_kind(pm, "spear"), Vector3(0, 0.8, 2), EAST * 20.0, 22.0, 99, 0.35, 0.5, _inst("spear"), 4.0)
	for n in range(30):
		pm._physics_process(DT)
	assert_int(g.zones).is_equal(0)
	var k := _spear_kind(pm, "war_lance")
	pm.fire(k, Vector3(0, 0.8, 0), EAST * 20.0, 44.0, 99, 0.4, 0.5, _inst("war_lance"), 5.0)
	for n in range(30):
		pm._physics_process(DT)
	# ten metres at a patch every 1.6 m or so
	assert_int(g.zones).is_between(4, 7)


# ---------------------------------------------------------------- the Turret Buddy

func _spawner(w: Dictionary, id: String, muts: Array = [], level := 1) -> Spawner:
	var sp := Spawner.new()
	(w["g"] as Node).add_child(sp)
	sp.setup(_inst(id, muts, level), w["g"])
	return sp


func _turret(w: Dictionary, sp: Spawner) -> Turret:
	var t := Turret.new()
	t.setup(sp, sp._proto, sp._turret_mesh, sp._turret_mat)
	(w["g"] as Node).add_child(t)
	t.global_position = Vector3.ZERO
	t.scale = Vector3.ONE
	return t


func test_buddy_squad_doubles_the_drop_and_the_cap_at_less_damage() -> void:
	var base := _inst("turret_buddy", [], 6)
	var sq := _inst("turret_buddy", ["buddy_squad"], 6)
	assert_int(base.stat_int("amount")).is_equal(2)
	assert_int(sq.stat_int("amount")).is_equal(base.stat_int("amount") * 2)
	assert_float(sq.stat("damage")).is_equal_approx(base.stat("damage") * 0.6, 0.001)
	# double whatever it is, Multishot included
	sq.bonus_effects = [Effect.make("amount", "add", 1.0)]
	sq.rebuild(Run.player_sheet, [sq])
	assert_int(sq.stat_int("amount")).is_equal(6)
	var w := _world()
	var plain := _spawner(w, "turret_buddy")
	assert_int(plain.max_turrets()).is_equal(6)
	var squad := _spawner(w, "turret_buddy", ["buddy_squad"], 6)
	assert_int(squad.max_turrets()).is_equal(12)
	# a drop is four now, and no more than twelve stand
	assert_bool(squad._fire()).is_true()
	assert_int(squad.standing().size()).is_equal(4)
	for n in range(3):
		squad._fire()
	assert_int(squad.standing().size()).is_equal(12)
	assert_str(squad.inst.description()).contains("4 turrets")


func test_the_turret_model_stands_on_its_stance() -> void:
	var w := _world()
	# pass 47: the Watchtower (the Tripod stance) is shelved
	var cases := [["", "Base", "BaseTop", 1], ["bunker", "Sandbags", "SandbagsTop", 2]]
	for c: Array in cases:
		var sp := _spawner(w, "turret_buddy", [c[0]] if c[0] != "" else [])
		var t := _turret(w, sp)
		var model: Node3D = t._model
		assert_object(model).override_failure_message("no model for " + str(c[0])).is_not_null()
		for s in ["Base", "Tripod", "Sandbags"]:
			assert_bool((model.get_node(s) as Node3D).visible).override_failure_message("%s: %s" % [c[0], s]).is_equal(s == c[1])
		var top: Node3D = model.get_node(str(c[2]))
		assert_float(t._yaw.position.distance_to(top.position)).is_less(0.001)
		assert_int(t._barrel_nodes.size()).is_equal(int(c[3]))
		# every muzzle at its barrel's tip, out along the gun's -Z
		var gun: Node3D = t._gun
		for b: Dictionary in t._barrel_nodes:
			var m: Node3D = b["muzzle"]
			var p: Vector3 = gun.global_transform.affine_inverse() * m.global_position
			assert_float(p.z).is_less(-0.5)
			assert_bool((b["node"] as Node3D).visible).is_true()


func test_a_shot_kicks_the_barrel_and_its_round_keeps_the_muzzles_height() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(5, 0, 0))
	em._rebuild_grid()
	var sp := _spawner(w, "turret_buddy")
	var t := _turret(w, sp)
	# pass 47: the head turns to the creature first (a quarter turn at its traverse), then it fires
	var frames := 0
	while t.shots == 0 and frames < 120:
		t._process(DT)
		frames += 1
	assert_int(t.shots).is_equal(1)
	var shot := -1
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == sp.inst:
			shot = j
	assert_int(shot).is_greater_equal(0)
	# the round leaves at the muzzle's height on the stand, not the old 0.35 m floor, and keeps it
	var muzzle_y: float = (t._barrel_nodes[0]["muzzle"] as Node3D).global_position.y
	assert_float(pm.hover[shot]).is_greater(0.5)
	assert_float(pm.hover[shot]).is_equal_approx(muzzle_y, 0.1)
	pm._physics_process(DT)
	assert_float(pm.pos[shot].y).is_greater(0.5)
	# the barrel kicked back along the gun and eases home
	var bar: Dictionary = t._barrel_nodes[0]
	t._tick_model(0.02)
	assert_float((bar["node"] as Node3D).position.z).is_greater((bar["rest"] as Vector3).z + 0.05)
	for n in range(20):
		t._tick_model(DT)
	assert_float((bar["node"] as Node3D).position.distance_to(bar["rest"])).is_less(0.001)
	# a plain shot keeps to the old ceiling
	var j2 := pm.fire(sp.projectile_kind, Vector3(0, 3.0, 0), EAST * 10.0, 1.0, 0, 0.2, 1.0, null)
	assert_float(pm.hover[j2]).is_equal_approx(1.3, 0.001)


# ---------------------------------------------------------------- the Big Mouth

func _mouth(w: Dictionary) -> LaserBeam:
	var lb := LaserBeam.new()
	(w["g"] as Node).add_child(lb)
	lb.setup(_inst("big_mouth"), w["g"])
	return lb


func test_the_mouth_winds_up_then_snaps_wide_open() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	var lb := _mouth(w)
	assert_object(lb._jaw).is_not_null()
	assert_bool(lb._fire()).is_true()
	# nothing pours yet: the wind-up first
	assert_float(lb._beam_t).is_equal(0.0)
	assert_float(lb._windup_t).is_equal_approx(lb.windup_seconds(), 0.0001)
	assert_int(lb.beams).is_equal(0)
	lb._tick(lb.windup_seconds() * 0.6)
	# pass 87 (re-pinned on purpose, lane BIGMOUTH): the wind-up is a breath now, not a clamp: the jaw gapes a little, the
	# lips rear up and the mouth swells (it was clamped shut and squashed)
	assert_float(lb._jaw.rotation.x).is_less(-deg_to_rad(8.0))
	assert_float(lb._jaw.rotation.x).is_greater(-deg_to_rad(LaserBeam.JAW_OPEN_DEG))
	assert_float(lb._model.rotation.x).is_greater(deg_to_rad(32.0) + 0.15)
	assert_float(lb._model.scale.x).is_greater(lb._model_scale * 1.03)
	lb._tick(lb.windup_seconds() * 0.5)
	# it pours, with a kick of the camera
	assert_float(lb._beam_t).is_greater(0.0)
	assert_int(lb.beams).is_equal(1)
	assert_int((w["cam"] as Node).shakes).is_greater_equal(1)
	# the jaw snaps open past its mark and settles on it
	var widest := 0.0
	for n in range(40):
		lb._tick(DT)
		widest = maxf(widest, -lb._jaw.rotation.x)
	assert_float(widest).is_greater(deg_to_rad(LaserBeam.JAW_OPEN_DEG))
	assert_float(-lb._jaw.rotation.x).is_between(deg_to_rad(LaserBeam.JAW_OPEN_DEG - 8.0), deg_to_rad(LaserBeam.JAW_OPEN_DEG + 8.0))
	assert_float(lb._cavity_mat.emission_energy_multiplier).is_greater(0.5)


func test_the_sand_boils_where_the_beam_runs_under_a_hill() -> void:
	var w := _world()
	var g: Node = w["g"]
	var lb := _mouth(w)
	var from := Vector3(0, 1.3, 0)
	var to := Vector3(13, 0.6, 0)
	# no map, or flat ground: nothing boils
	assert_array(lb.boil_points(from, to)).is_empty()
	var flat: RefCounted = _script(FLAT).new()
	g.map = flat
	assert_array(lb.boil_points(from, to)).is_empty()
	# a dune on the line: the sand over the buried stretch, on the surface
	var hill: RefCounted = _script(HILL).new()
	g.map = hill
	var pts := lb.boil_points(from, to)
	assert_int(pts.size()).is_between(4, 8)
	for p: Vector3 in pts:
		assert_float(p.x).is_between(4.0, 8.0)
		assert_float(p.y).is_equal_approx(hill.height_at(p.x, p.z), 0.0001)
		assert_float(p.y).is_greater(lerpf(from.y, to.y, p.x / to.x))
	# while the beam pours east over it, cracks glow up there
	lb._aim_yaw = atan2(-1.0, 0.0)
	lb._familiar.global_position = from
	lb._beam_t = 1.0
	var tg: Telegraphs = w["tg"]
	var n0 := tg.live_count()
	lb._boil(0.2)
	assert_int(tg.live_count()).is_greater(n0)
	g.map = null


# ---------------------------------------------------------------- the Hammer

func test_the_hammer_winds_up_and_lands_on_its_beat() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var c := _creature(em, Vector3(3, 0, 0))
	em._rebuild_grid()
	var s := Smasher.new()
	(w["g"] as Node).add_child(s)
	s.setup(_inst("hammer"), w["g"])
	assert_float(s._smash("size", 1.0)).is_equal_approx(1.4, 0.001)
	assert_float(Registry.weapon("earthshaker").params["smash"]["size"]).is_equal_approx(1.5, 0.001)
	var beats := s.phase_times()
	assert_float(float(beats[2])).is_equal_approx(0.12 + 0.34 + 0.18, 0.001)
	var hp0: float = em.hp[c]
	assert_bool(s._fire()).is_true()
	var sw: Dictionary = s._swings[0]
	var n: Node3D = sw["it"]["node"]
	var t := 0.0
	var top_pitch := 0.0
	var size_seen := 0.0
	while not sw["hit"] and t < 2.0:
		s._tick(DT)
		t += DT
		if t > float(beats[0]) and t < float(beats[1]):
			top_pitch = maxf(top_pitch, n.rotation.x)
			size_seen = maxf(size_seen, n.scale.x)
	# the blow lands on its beat
	assert_float(t).is_between(float(beats[2]) - DT * 0.5, float(beats[2]) + DT * 1.5)
	assert_float(em.hp[c]).is_less(hp0)
	# it reared back well past upright, at its full size
	assert_float(top_pitch).is_greater(PI * 0.5 + 0.3)
	assert_float(size_seen).is_equal_approx(1.4, 0.01)
	# the head came down on the creature with its face, squashed flat for that moment
	var head: Node3D = sw["it"]["head"]
	assert_float(head.scale.y).is_less(head.scale.x * 0.8)
	var at: Vector3 = sw["at"]
	var hp := head.global_position
	assert_float(Vector2(hp.x - at.x, hp.z - at.z).length()).is_less(0.3)
	var head_s := clampf(s._blast_r() / 1.6, 0.75, 1.9)
	assert_float(hp.y - at.y).is_equal_approx(Smasher.HEAD_HALF * head_s * 1.4, 0.15)
	# then it bounces, lifts away and is gone
	while not s._swings.is_empty() and t < 3.0:
		s._tick(DT)
		t += DT
	assert_float(t).is_between(float(beats[4]) - DT, float(beats[4]) + DT * 2.0)


# ---------------------------------------------------------------- the words

func test_the_text_says_what_they_do() -> void:
	Run.start(Registry.character("calavera"), Registry.map("red_canyon"))
	var g := _inst("guitarra")
	assert_str(g.description()).contains("70° cone of melody")
	assert_str(g.description()).contains("lifted")
	g.bonus_effects = [Effect.make("amount", "add", 2.0)]
	g.rebuild(Run.player_sheet, [g])
	assert_str(g.description()).contains("2 echoes")
	assert_str(_inst("requiem").description()).contains("ring of melody")
	assert_str(_inst("guitarra", ["far_reach"]).description()).contains("180°")
	assert_str(_inst("guitarra", ["music_slap"]).description()).contains("aside")
	var rows := {}
	for r: Dictionary in _inst("guitarra").stat_rows():
		rows[str(r["stat"])] = r
	assert_str(str(rows["cone_deg"]["value"])).is_equal("70°")
	assert_str(str(rows["amount"]["name"])).is_equal("waves")
	assert_str(str(rows["range"]["name"])).is_equal("reach")
	assert_bool(rows.has("lift")).is_true()
	var cd: float = maxf(_inst("guitarra").stat("cooldown"), 0.05)
	assert_float(_inst("guitarra").dps_estimate()).is_equal_approx(_inst("guitarra").stat("damage") * 3.0 / cd, 0.01)
	var sp := _inst("spear", ["pinning_throw"])
	assert_str(sp.description()).contains("spear")
	assert_str(sp.description()).contains("pinned")
	assert_str(sp.description()).not_contains("Pierces")
	var srows: Array = sp.stat_rows().map(func(r): return str(r["stat"]))
	assert_bool(srows.has("pin")).is_true()
	assert_bool(srows.has("plant")).is_true()
	assert_str(_inst("war_lance").description()).contains("dust")
	Run.end()
