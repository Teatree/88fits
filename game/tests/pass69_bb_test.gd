extends GdUnitTestSuite

## Pass 69, lane BB (Garry: the basketball's Heat "should only be present on the 3d object of the ball itself ... No UI
## Indicators"; "Full Court Press - Hide this mutation"; a new mutation where "an enemy will be thrown up after being hit
## by the ball"; "Evolution 3d Object should turn the Basketball Black"): Alley-Oop's launch (EnemyManager.try_launch,
## launch, _tick_launch: the chance, the height, the air time, the fall's damage from the hit, big game taking it at once,
## no bite or attack up there, no second launch, a body killed up there falling), the path (On Fire, Alley-Oop, Rebound;
## Full Court Press hidden), Slam Dunk's amplified combo and black ball, the ball's Heat on the ball (heat_look: the
## glow, the trail, the halo, the beat at the top, the cooling), the seams (tint.body / tint.seams), the words, and no
## hero gauge in the HUD.

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
var bursts := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	bursts += 1
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
var hits := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
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
var shakes := 0
func shake(_a: float) -> void:
	shakes += 1
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0

## The basketball's params as pass 67 made them, with pass 69's heat look, on a weapon made here.
const BALL := {
	"radius": 0.3, "amount_mode": "bounces", "ricochet_any": {"count": 1, "frac": 0.85, "reach": 7.0},
	"return": true, "return_on_hit": true, "return_pierce": 2, "return_damage_mult": 0.75, "back_speed_mult": 1.25,
	"catch": {"refund": 0.35, "heat_per": 0.05, "heat_max": 10},
	"heat_look": {"color": "#FF6A1A", "hot": "#FFD27A", "glow_min": 0.0, "glow_max": 2.2, "pulse_hz": 3.0, "pulse": 0.35,
		"surfaces": "all", "trail_from": 0.1, "flame_from": 0.4, "halo": 2.2, "halo_alpha": 0.3}}


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
	em.rise_t[i] = 1.0
	em.dr[i] = 0.0
	return i


func _ball_def(over: Dictionary = {}) -> WeaponDef:
	var d := WeaponDef.new()
	d.id = "p69_test_ball"
	d.display_name = "Test Ball"
	d.behavior = "ProjectileEmitter"
	d.targeting = "priority"
	d.base = {"damage": 20.0, "cooldown": 1.4, "amount": 1, "pierce": 0, "speed": 16.0, "range": 9.0, "knockback": 0.0}
	d.levels = [[], [], [], [], []]
	d.max_level = 5
	d.params = WeaponInstance.merge_params(BALL, over)
	return d


func _ball(over: Dictionary = {}) -> WeaponInstance:
	var inst := WeaponInstance.new(_ball_def(over), 1)
	inst.rebuild(StatSheet.new(), [inst])
	return inst


func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	var pe := ProjectileEmitter.new()
	(w["g"] as Node).add_child(pe)
	pe.setup(inst, w["g"])
	((w["g"] as Node).get("behaviors") as Dictionary)[inst.def.id] = pe
	return pe


func _live_of(pm: ProjectileManager, inst: WeaponInstance) -> Array:
	var out: Array = []
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1 and pm.weapon[j] == inst and not (pm.extra[j] as Dictionary).has("ghost"):
			out.append(j)
	return out


## The real basketball (its GLB, its params) carrying `muts` (ids), folded.
func _real_ball(muts: Array, id := "basketball") -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), 5 if id == "basketball" else 1)
	for m in muts:
		inst.mutations.append(Registry.mutation(str(m)))
	inst.rebuild(StatSheet.new(), [inst])
	return inst


# ---------------------------------------------------------------- the content

func test_alley_oop_is_the_basketballs_volume_mutation_and_full_court_press_is_hidden() -> void:
	var ao: MutationDef = Registry.mutation("alley_oop")
	assert_object(ao).is_not_null()
	assert_str(ao.display_name).is_equal("Alley-Oop")
	assert_str(ao.weapon).is_equal("basketball")
	assert_str(ao.mutation_kind).is_equal("volume")
	assert_str(ao.rarity).is_equal("rare")
	assert_bool(ao.hidden).is_false()
	assert_object(ao.icon).is_not_null()
	var lc: Dictionary = ao.params["launch"]
	assert_float(float(lc["chance"])).is_equal(0.15)
	assert_float(float(lc["height"])).is_equal(3.5)
	assert_float(float(lc["air_time"])).is_equal(0.9)
	assert_float(float(lc["fall_damage_frac"])).is_equal(1.0)
	assert_str(ao.text).is_equal("Each hit has a 15% chance to throw the creature into the air. It can't attack up there and takes the hit again when it lands.")
	# the dark blue ball: its body flat in #0A4FA8 (out of the sky's warm ambient, the lead's pass-69 fix), a blue glow, the seams kept
	assert_str(str(ao.params["tint"]["body"])).is_equal("#0A4FA8")
	assert_str(str(ao.params["tint"]["emission"])).is_equal("#1A5CFF")
	assert_bool(ao.params["tint"].get("seams") is Dictionary).is_true()
	# its Heat glows in the seams only, so the body stays dark blue
	assert_str(str(ao.params["heat_look"]["surfaces"])).is_equal("seams")
	# Full Court Press: kept, out of play
	var fcp: MutationDef = Registry.mutation("full_court_press")
	assert_object(fcp).is_not_null()
	assert_bool(fcp.hidden).is_true()
	assert_bool(Registry.is_hidden(fcp)).is_true()


func test_the_basketballs_path_is_on_fire_alley_oop_rebound_and_slam_dunk_evolves_from_it() -> void:
	var path: Array = Registry.mutations_of("basketball")
	var by_kind := {}
	for m: MutationDef in path:
		by_kind[m.mutation_kind] = m.id
	assert_int(path.size()).is_equal(3)
	assert_str(str(by_kind.get("element", ""))).is_equal("on_fire")
	assert_str(str(by_kind.get("volume", ""))).is_equal("alley_oop")
	assert_str(str(by_kind.get("motion", ""))).is_equal("rebound")
	assert_str(Registry.weapon("basketball").evolves_into).is_equal("slam_dunk")
	# the evolution comes once the three are held at level 5
	var inst := _real_ball(["on_fire", "alley_oop", "rebound"])
	Run.weapons = [inst]
	Run.mutations["basketball"] = ["on_fire", "alley_oop"]
	assert_bool(Run.evolution_ready(inst)).is_false()
	Run.mutations["basketball"] = ["on_fire", "alley_oop", "rebound"]
	assert_bool(Run.evolution_ready(inst)).is_true()
	# Full Court Press no longer counts for the path
	Run.mutations["basketball"] = ["on_fire", "full_court_press", "rebound"]
	assert_bool(Run.evolution_ready(inst)).is_false()
	Run.mutations.erase("basketball")
	Run.weapons = []


# ---------------------------------------------------------------- the launch

func test_the_launch_rolls_its_chance() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(5, 0, 0))
	var cfg := {"chance": 0.15, "height": 3.5, "air_time": 0.9, "fall_damage_frac": 1.0}
	assert_int(em.try_launch(i, 20.0, "p69", cfg, 0.16)).is_equal(0)
	assert_bool(em.is_launched(i)).is_false()
	assert_int(em.try_launch(i, 20.0, "p69", cfg, 0.14)).is_equal(1)
	assert_bool(em.is_launched(i)).is_true()
	assert_int(em.launches).is_equal(1)
	# a chance of 0 never throws, of 1 always
	var j := _creature(em, Vector3(-5, 0, 0))
	assert_int(em.try_launch(j, 20.0, "p69", {"chance": 0.0}, 0.0)).is_equal(0)
	assert_int(em.try_launch(j, 20.0, "p69", {"chance": 1.0}, 0.999)).is_equal(1)


func test_a_launched_creature_goes_straight_up_hangs_drops_and_takes_the_hit_again_on_landing() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(6, 0, 0))
	var at := em.pos[i]
	var hp0 := em.hp[i]
	assert_int(em.try_launch(i, 20.0, "p69", {"chance": 1.0, "height": 3.5, "air_time": 0.9, "fall_damage_frac": 1.0}, 0.0)).is_equal(1)
	var top := 0.0
	var t := 0.0
	var at_hang := -1.0
	while em.is_launched(i) and t < 2.0:
		em._physics_process(DT)
		t += DT
		top = maxf(top, em.lift_h[i])
		if at_hang < 0.0 and t >= 0.9 * 0.4:
			at_hang = em.lift_h[i]
		# straight up: no drift, no turn
		assert_float(Vector2(em.pos[i].x - at.x, em.pos[i].z - at.z).length()).is_less(0.001)
	# it landed after its air time, having reached its height (and hung near it)
	assert_float(t).is_between(0.88, 0.95)
	assert_float(top).is_between(3.4, 3.5 * (1.0 + EnemyManager.LAUNCH_FLOAT) + 0.01)
	assert_float(at_hang).is_greater(3.4)
	assert_float(em.lift_h[i]).is_equal(0.0)
	assert_int(em.landings).is_equal(1)
	# the fall is the hit's damage again, through damage()
	assert_float(hp0 - em.hp[i]).is_equal_approx(20.0, 0.01)


func test_the_curve_is_up_fast_a_hang_then_the_drop() -> void:
	assert_float(EnemyManager.launch_curve(0.0)).is_equal(0.0)
	# up fast: past three quarters of the height by half the rise
	assert_float(EnemyManager.launch_curve(EnemyManager.LAUNCH_RISE * 0.5)).is_greater(0.7)
	assert_float(EnemyManager.launch_curve(EnemyManager.LAUNCH_RISE)).is_equal_approx(1.0, 0.0001)
	assert_float(EnemyManager.launch_curve((EnemyManager.LAUNCH_RISE + EnemyManager.LAUNCH_HANG) * 0.5)).is_greater_equal(1.0)
	# the drop gathers speed: the first half of it loses less than the second
	var mid := (EnemyManager.LAUNCH_HANG + 1.0) * 0.5
	var first := 1.0 - EnemyManager.launch_curve(mid)
	var second := EnemyManager.launch_curve(mid)
	assert_float(first).is_less(second)
	assert_float(EnemyManager.launch_curve(1.0)).is_equal(0.0)


func test_the_fall_scales_with_the_hits_damage_and_its_frac() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(6, 0, 0))
	var b := _creature(em, Vector3(-6, 0, 0))
	var c := _creature(em, Vector3(0, 0, 6))
	var ha := em.hp[a]
	var hb := em.hp[b]
	var hc := em.hp[c]
	em.try_launch(a, 20.0, "p69", {"chance": 1.0, "air_time": 0.5}, 0.0)
	em.try_launch(b, 40.0, "p69", {"chance": 1.0, "air_time": 0.5}, 0.0)
	em.try_launch(c, 40.0, "p69", {"chance": 1.0, "air_time": 0.5, "fall_damage_frac": 1.5}, 0.0)
	for k in range(45):
		em._physics_process(DT)
	assert_float(ha - em.hp[a]).is_equal_approx(20.0, 0.01)
	assert_float(hb - em.hp[b]).is_equal_approx(40.0, 0.01)
	assert_float(hc - em.hp[c]).is_equal_approx(60.0, 0.01)


func test_elites_and_bosses_take_the_fall_at_once_and_stay_down() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var e := _creature(em, Vector3(6, 0, 0), 5.0, "stone_golem")
	assert_bool(em.is_big_game(e)).is_true()
	var h0 := em.hp[e]
	assert_int(em.try_launch(e, 30.0, "p69", {"chance": 1.0, "fall_damage_frac": 1.0}, 0.0)).is_equal(2)
	assert_float(h0 - em.hp[e]).is_equal_approx(30.0, 0.01)
	assert_float(em.lift_t[e]).is_equal(0.0)
	assert_bool(em.is_launched(e)).is_false()
	assert_int(em.launch_instant).is_equal(1)
	# a boss the same way
	var bi := _creature(em, Vector3(-6, 0, 0), 5.0)
	em.boss_index = bi
	var hb := em.hp[bi]
	assert_int(em.try_launch(bi, 30.0, "p69", {"chance": 1.0, "fall_damage_frac": 1.5}, 0.0)).is_equal(2)
	assert_float(hb - em.hp[bi]).is_equal_approx(45.0, 0.01)
	assert_bool(em.can_launch(bi)).is_false()
	em.boss_index = -1
	# and a miss of the roll costs them nothing
	assert_int(em.try_launch(e, 30.0, "p69", {"chance": 0.1}, 0.5)).is_equal(0)


func test_up_there_it_cannot_bite_or_attack_and_cannot_be_thrown_again() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero = w["hero"]
	# right against the hero: on its feet it bites at once
	var i := _creature(em, Vector3(0.3, 0, 0))
	em.contact_cd[i] = 0.0
	assert_int(em.try_launch(i, 5.0, "p69", {"chance": 1.0, "air_time": 0.9}, 0.0)).is_equal(1)
	# a wind-up it was in is dropped the way a stun drops it; while up it does not steer
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	for k in range(40):
		em._physics_process(DT)
		assert_float(em.vel[i].length()).is_equal(0.0)
	assert_int(int(hero.get("hits"))).is_equal(0)
	assert_bool(em.is_launched(i)).is_true()
	# a second launch while it is up does nothing
	assert_int(em.try_launch(i, 5.0, "p69", {"chance": 1.0}, 0.0)).is_equal(0)
	assert_int(em.launches).is_equal(1)
	# down again, it bites
	for k in range(30):
		em._physics_process(DT)
	assert_bool(em.is_launched(i)).is_false()
	assert_int(int(hero.get("hits"))).is_greater_equal(1)


func test_a_creature_that_cannot_go_up_is_left_alone() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(6, 0, 0))
	var h0 := em.hp[i]
	em.rise_t[i] = 0.5
	assert_int(em.try_launch(i, 20.0, "p69", {"chance": 1.0}, 0.0)).is_equal(0)
	em.rise_t[i] = 1.0
	em.state[i] = EnemyManager.STATE_SPAWN
	assert_int(em.try_launch(i, 20.0, "p69", {"chance": 1.0}, 0.0)).is_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	# a bounce already holds it
	assert_bool(em.bounce(i, 1.0, 0.5)).is_true()
	assert_int(em.try_launch(i, 20.0, "p69", {"chance": 1.0}, 0.0)).is_equal(0)
	assert_float(em.hp[i]).is_equal(h0)


func test_a_body_killed_up_there_falls_to_the_sand() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(6, 0, 0), 1.0)
	em.try_launch(i, 1.0, "p69", {"chance": 1.0, "height": 3.5, "air_time": 0.9}, 0.0)
	for k in range(20):
		em._physics_process(DT)
	assert_float(em.lift_h[i]).is_greater(2.5)
	assert_bool(em.damage(i, 99999.0, "p69")).is_true()
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	for k in range(60):
		em._physics_process(DT)
	assert_float(em.lift_h[i]).is_equal(0.0)


func test_a_ball_hit_rolls_the_launch() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var inst := _ball({"launch": {"chance": 1.0, "height": 3.5, "air_time": 0.9, "fall_damage_frac": 1.0}})
	var pe := _emitter(w, inst)
	var i := _creature(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	assert_bool(pe._fire()).is_true()
	var up := false
	for k in range(60):
		pm._physics_process(DT)
		em._rebuild_grid()
		if em.is_launched(i):
			up = true
			break
	assert_bool(up).is_true()
	# its fall is the throw's damage (20), and the ball itself hit for 20
	assert_float(float(em._launched[i]["dmg"])).is_equal_approx(20.0, 0.01)
	# a ball without the mutation never throws
	var plain := _ball()
	var pp := _emitter(w, plain)
	var j := _creature(em, Vector3(-4, 0, 0))
	em._rebuild_grid()
	var n0 := em.launches
	pp._fire()
	for k in range(60):
		pm._physics_process(DT)
		em._rebuild_grid()
	assert_int(em.launches).is_equal(n0)
	assert_bool(em.is_launched(j)).is_false()


# ---------------------------------------------------------------- Slam Dunk

func test_slam_dunk_amplifies_the_three_and_is_black() -> void:
	var evo: WeaponDef = Registry.weapon("slam_dunk")
	var sd := _real_ball(["on_fire", "alley_oop", "rebound"], "slam_dunk")
	var base := _real_ball(["on_fire", "alley_oop", "rebound"])
	# Alley-Oop's launch: 0.25 and x1.5 (its height and air time kept)
	var lc: Dictionary = sd.params["launch"]
	assert_float(float(lc["chance"])).is_equal(0.25)
	assert_float(float(lc["fall_damage_frac"])).is_equal(1.5)
	assert_float(float(lc["height"])).is_equal(float(Registry.mutation("alley_oop").params["launch"]["height"]))
	assert_float(float(lc["air_time"])).is_equal(float(Registry.mutation("alley_oop").params["launch"]["air_time"]))
	# Rebound's way home: everything on it, x1.2
	assert_int(int(sd.params["return_pierce"])).is_equal(80)
	assert_float(float(sd.params["return_damage_mult"])).is_equal_approx(1.2 * float(Registry.mutation("rebound").params["return_damage_mult"]), 0.0001)
	# On Fire's burn x1.5
	assert_float(sd.stat("fire_damage", 0.0)).is_equal_approx(1.5 * base.stat("fire_damage", 0.0), 0.0001)
	assert_float(sd.stat("fire_damage", 0.0)).is_greater(0.0)
	# its own dunk and Heat kept
	assert_bool(sd.params["catch"].get("slam") is Dictionary).is_true()
	assert_bool(bool(sd.params["catch"].get("heat_keep", false))).is_true()
	# the black ball with ember seams, over On Fire's red and Alley-Oop's blue; its Heat shows in the seams
	assert_str(str(sd.params["tint"]["body"])).is_equal("#141414")
	assert_bool(sd.params["tint"]["seams"].has("emission")).is_true()
	assert_str(str(sd.params["heat_look"]["surfaces"])).is_equal("seams")
	assert_bool(evo.params.has("heat_look")).is_true()


# ---------------------------------------------------------------- the ball's looks

func test_alley_oops_ball_is_dark_blue_with_its_seams_and_slam_dunks_black_with_glowing_seams() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var ao := _real_ball(["alley_oop"])
	var pe := _emitter(w, ao)
	var k := pe._kind()
	assert_int(k).is_not_equal(pe.projectile_kind)
	var mesh: Mesh = (pm.kinds[k]["mm"] as MultiMesh).mesh
	assert_int(mesh.get_surface_count()).is_equal(2)
	var body: StandardMaterial3D = mesh.surface_get_material(0)
	var seam: StandardMaterial3D = mesh.surface_get_material(1)
	assert_bool(body.vertex_color_use_as_albedo).is_false()
	assert_bool(body.albedo_color.is_equal_approx(Color("#0A4FA8"))).is_true()
	# out of the sky's warm ambient light (the lead's pass-69 fix: with it the navy rendered violet)
	assert_bool(body.disable_ambient_light).is_true()
	assert_bool(seam.albedo_color.is_equal_approx(Color("#05081A"))).is_true()
	# the seams are a fair share of the ball, not all of it
	var nb: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var ns: int = (mesh.surface_get_arrays(1)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	assert_int(ns).is_greater(0)
	assert_float(float(ns) / float(nb + ns)).is_between(0.05, 0.5)
	# the plain ball keeps its own look
	var plain := _real_ball([])
	var pp := _emitter(w, plain)
	assert_int(pp._kind()).is_equal(pp.projectile_kind)
	# Slam Dunk: black, its seams glowing ember
	var sd := _real_ball(["on_fire", "alley_oop", "rebound"], "slam_dunk")
	var ps := _emitter(w, sd)
	var ks := ps._kind()
	var ms: Mesh = (pm.kinds[ks]["mm"] as MultiMesh).mesh
	assert_int(ms.get_surface_count()).is_equal(2)
	assert_bool((ms.surface_get_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(Color("#141414"))).is_true()
	var sm: StandardMaterial3D = ms.surface_get_material(1)
	assert_bool(sm.emission_enabled).is_true()
	assert_float(sm.emission_energy_multiplier).is_greater(0.5)


func test_heat_look_params_drive_the_glow_and_a_hit_cools_it_at_once() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var inst := _ball()
	var pe := _emitter(w, inst)
	assert_dict(pe.heat_look()).is_not_empty()
	_creature(em, Vector3(6, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	assert_bool(pe._fire()).is_true()
	var shots := _live_of(pm, inst)
	assert_int(shots.size()).is_equal(1)
	var kh: int = pm.kind[shots[0]]
	# the ball is drawn in its heat copy
	assert_float(pm.heat_energy(kh)).is_greater_equal(0.0)
	# cold: its own look (the stand-in shot's own glow, 0.8)
	pe._tick(DT)
	var e0 := pm.heat_energy(kh)
	assert_float(e0).is_equal_approx(0.8, 0.001)
	assert_float(pe.heat_level_shown).is_equal(0.0)
	# half: half the way to glow_max
	Run.heat = 5
	pe._tick(DT)
	assert_float(pe.heat_level_shown).is_equal_approx(0.5, 0.0001)
	assert_float(pm.heat_energy(kh)).is_equal_approx(lerpf(e0, 2.2, 0.5), 0.01)
	# full: glow_max, beating at pulse_hz by `pulse` either way
	Run.heat = 10
	var lo := 99.0
	var hi := 0.0
	for k in range(30):
		pm.clock += 1.0 / 30.0 / 3.0
		pe._tick(DT)
		lo = minf(lo, pm.heat_energy(kh))
		hi = maxf(hi, pm.heat_energy(kh))
	assert_float(hi).is_greater(2.2 * 1.25)
	assert_float(lo).is_less(2.2 * 0.75)
	assert_float(hi).is_less_equal(2.2 * 1.35 + 0.01)
	# a hit on him: Heat 0, the ball in flight cold at once, a puff of steam off it
	pe.on_hero_hit()
	assert_int(Run.heat).is_equal(0)
	var b0: int = int((w["g"] as Node).get("bursts"))
	pe._tick(DT)
	assert_float(pm.heat_energy(kh)).is_equal_approx(e0, 0.0001)
	assert_int(pe.fizzles).is_equal(1)
	assert_int(int((w["g"] as Node).get("bursts"))).is_equal(b0 + 1)


func test_a_hot_ball_trails_and_wears_a_halo_and_a_cold_one_neither() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var em: EnemyManager = w["em"]
	var inst := _ball()
	var pe := _emitter(w, inst)
	_creature(em, Vector3(8, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	assert_bool(pe._fire()).is_true()
	var j: int = _live_of(pm, inst)[0]
	assert_bool((pm.extra[j] as Dictionary).has("heat_t")).is_true()
	# cold: no beads, no halo
	var n0 := pm.trail_next
	for k in range(5):
		pm._physics_process(DT)
	assert_int(pm.trail_next).is_equal(n0)
	pm._render()
	pm._tick_trail(DT)
	assert_int(pm.heat_halos).is_equal(0)
	# hot: beads behind it, and a halo
	Run.heat = 10
	for k in range(5):
		pm._physics_process(DT)
	assert_int(pm.trail_next).is_not_equal(n0)
	pm._render()
	pm._tick_trail(DT)
	assert_int(pm.heat_halos).is_equal(1)
	# below flame_from: a trail but no halo
	Run.heat = 2
	pm._render()
	pm._tick_trail(DT)
	assert_int(pm.heat_halos).is_equal(0)


func test_the_real_balls_read_their_heat_look() -> void:
	for id in ["basketball", "slam_dunk"]:
		var hl = Registry.weapon(id).params.get("heat_look")
		assert_bool(hl is Dictionary).override_failure_message(id).is_true()
		for key in ["color", "hot", "glow_max", "seam_glow_max", "pulse_hz", "pulse", "surfaces", "trail_from", "flame_from", "halo", "halo_from", "halo_alpha"]:
			assert_bool((hl as Dictionary).has(key)).override_failure_message("%s %s" % [id, key]).is_true()
		assert_float(float(hl["pulse_hz"])).is_equal(3.0)


func test_the_real_balls_heat_glows_in_its_seams_hotter_than_its_body() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var ball := _real_ball([])
	var pe := _emitter(w, ball)
	var kh := pe._ball_kind(pe._kind())
	assert_bool(pm.has_seams(kh)).is_true()
	var mesh: Mesh = (pm.kinds[kh]["mm"] as MultiMesh).mesh
	assert_int(mesh.get_surface_count()).is_equal(2)
	# the plain ball's seams keep their own dark colour (its vertex colours)
	assert_bool((mesh.surface_get_material(1) as StandardMaterial3D).vertex_color_use_as_albedo).is_true()
	Run.heat = 9
	pe._tick(DT)
	var body: StandardMaterial3D = mesh.surface_get_material(0)
	var seam: StandardMaterial3D = mesh.surface_get_material(1)
	assert_float(seam.emission_energy_multiplier).is_greater(body.emission_energy_multiplier)
	assert_float(body.emission_energy_multiplier).is_less_equal(float(ball.params["heat_look"]["glow_max"]) + 0.001)
	# Slam Dunk's body never glows (surfaces "seams")
	var sd := _real_ball(["on_fire", "alley_oop", "rebound"], "slam_dunk")
	var ps := _emitter(w, sd)
	var ks := ps._ball_kind(ps._kind())
	var ms: Mesh = (pm.kinds[ks]["mm"] as MultiMesh).mesh
	var e_body := (ms.surface_get_material(0) as StandardMaterial3D).emission_energy_multiplier
	Run.heat = 10
	ps._tick(DT)
	assert_float((ms.surface_get_material(0) as StandardMaterial3D).emission_energy_multiplier).is_equal_approx(e_body, 0.0001)
	assert_float((ms.surface_get_material(1) as StandardMaterial3D).emission_energy_multiplier).is_greater(1.3)


# ---------------------------------------------------------------- the words and the HUD

func test_the_words_say_the_launch() -> void:
	assert_str(TextGen.launch_words({})).is_empty()
	assert_str(TextGen.launch_words({"launch": {"chance": 0.15, "fall_damage_frac": 1.0}})).contains("15% chance to throw the enemy into the air")
	assert_str(TextGen.launch_words({"launch": {"chance": 0.15, "fall_damage_frac": 1.0}})).contains("takes the hit again when it lands")
	var ao := _real_ball(["alley_oop"])
	assert_str(ao.description()).contains("15% chance to throw the enemy into the air")
	var sd := _real_ball(["on_fire", "alley_oop", "rebound"], "slam_dunk")
	var d := sd.description()
	assert_str(d).contains("25% chance")
	assert_str(d).contains("takes 150% of the hit when it lands")
	# the plain ball says nothing of it
	assert_str(_real_ball([]).description()).not_contains("into the air")


func test_the_estimate_counts_the_falls() -> void:
	var plain := _ball()
	var oop := _ball({"launch": {"chance": 0.15, "fall_damage_frac": 1.0}})
	var dunk := _ball({"launch": {"chance": 0.25, "fall_damage_frac": 1.5}})
	assert_float(oop.dps_estimate()).is_equal_approx(plain.dps_estimate() * 1.15, 0.01)
	assert_float(dunk.dps_estimate()).is_equal_approx(plain.dps_estimate() * 1.375, 0.01)


func test_no_hero_gauge_in_the_hud_even_with_heat() -> void:
	var inst := _ball()
	Run.weapons = [inst]
	Run.heat = 7
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	hud.tick(0.0)
	assert_object(hud.find_child("HeroGauge", true, false)).is_null()
	assert_bool(hud.has_method("gauge_state")).is_false()
	for s in HUD.buff_parts():
		assert_bool(str(s).begins_with("HEAT")).is_false()
	Run.weapons = []
