extends GdUnitTestSuite

## Pass 72, lane ITEMS. (1) The basketball "seems to be white, should be orange": a free throw's ball was drawn in white
## (ProjectileEmitter.FREE_TINT, gone: it is the ball now), and On Fire's glowing body bleached to yellow-white at full
## Heat (heat_look.body_green_max caps the green its glow adds, ProjectileManager._cap_body_green). (2) "Half all the
## knockback effect": one map number, WaveTimeline.hero_knockback_mult (Red Canyon 0.5), on every push the hero's side
## gives a creature (EnemyManager.hero_knock_mult): a hit's kb_force from a hero source, hero_throw_radius (the Nuke,
## Thruster Burst, Grand Finale), Buck's Ram, the tornado's toss, the Guitarra's bounce and Bucking Bronco's throw
## distance; never a hostile push (HOSTILE_PUSH_IDS: a dead rocketeer's loose rocket, a hostile blast), throw_radius
## itself (the hostile throws), the pull, knockback_resist or a stun.

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
var zones := 0
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
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _c = Color.WHITE):
	zones += 1
	return null
func on_creature_died_index(_i) -> void:
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
var max_hp := 100.0
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
const EAST := Vector3(1, 0, 0)
const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.heat = 0


func after_test() -> void:
	Run.heat = 0
	Run.end()


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


## A creature on its feet where it was put, at its JSON size, standing still, taking every hit whole.
func _put(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.dr[i] = 0.0
	em.size[i] = Registry.enemy(id).size
	em.radius[i] = Registry.enemy(id).radius
	em.vel[i] = Vector3.ZERO
	em.kb[i] = Vector3.ZERO
	return i


func _real_ball(muts: Array, id := "basketball") -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), 5 if id == "basketball" else 1)
	for m in muts:
		inst.mutations.append(Registry.mutation(str(m)))
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
		if pm.alive[j] == 1 and pm.weapon[j] == inst:
			out.append(j)
	return out


# ---------------------------------------------------------------- the basketball

func test_a_free_throw_is_the_ball_in_its_own_colours() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var ball := _real_ball(["free_throw"])
	assert_bool(ball.params.get("free_throw") is Dictionary).is_true()
	var pe := _emitter(w, ball)
	_put(em, Vector3(4, 0, 0))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	pe.cooldown_left = 5.0
	pe.on_hero_evaded()
	assert_int(pe.free_throws).is_equal(1)
	var shots := _live_of(pm, ball)
	assert_int(shots.size()).is_equal(1)
	var k: int = pm.kind[shots[0]]
	# the ordinary throw's kind: the GLB's own vertex colours (burnt orange, black seams), no white paint, no white glow
	assert_int(k).is_equal(pe._ball_kind(pe._kind()))
	var mesh: Mesh = (pm.kinds[k]["mm"] as MultiMesh).mesh
	var body: StandardMaterial3D = mesh.surface_get_material(0)
	assert_bool(body.vertex_color_use_as_albedo).is_true()
	assert_float(body.emission_energy_multiplier).is_equal(0.0)


func test_the_real_basketball_caps_its_bodys_glow() -> void:
	var hl = Registry.weapon("basketball").params.get("heat_look")
	assert_bool(hl is Dictionary).is_true()
	assert_bool((hl as Dictionary).has("body_green_max")).is_true()
	var cap := float(hl["body_green_max"])
	assert_float(cap).is_between(0.0, 1.0)
	# the plain ball's own top glow (no glow of its own, `color` at glow_max beating by `pulse`) stays under it
	var col := Color(str(hl["color"]))
	assert_float(col.g * float(hl["glow_max"]) * (1.0 + float(hl["pulse"]))).is_less(cap)


func test_on_fires_body_stays_orange_at_every_heat() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var ball := _real_ball(["on_fire"])
	var pe := _emitter(w, ball)
	var kh := pe._ball_kind(pe._kind())
	var mesh: Mesh = (pm.kinds[kh]["mm"] as MultiMesh).mesh
	var body: StandardMaterial3D = mesh.surface_get_material(0)
	var hl: Dictionary = ball.params["heat_look"]
	var cap := float(hl["body_green_max"])
	# cold: On Fire's own glow, untouched
	pe._tick(DT)
	var e0 := body.emission
	var en0 := body.emission_energy_multiplier
	assert_float(en0).is_greater(1.0)
	var cold_g := e0.g * en0
	for heat in [3, 6, 10]:
		Run.heat = heat
		for k in range(12):
			pm.clock += 1.0 / 36.0
			pe._tick(DT)
			var g := body.emission.g * body.emission_energy_multiplier
			var r := body.emission.r * body.emission_energy_multiplier
			assert_float(g).override_failure_message("heat %d: green %.3f" % [heat, g]).is_less_equal(maxf(cold_g, cap) + 0.001)
			# orange: the red it adds is well over twice its green
			assert_float(r).is_greater(g * 2.0)
	# the seams still glow hot at the top
	var seam: StandardMaterial3D = mesh.surface_get_material(1)
	assert_float(seam.emission_energy_multiplier).is_greater(1.0)


func test_the_plain_balls_glow_is_as_it_was() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var ball := _real_ball([])
	var pe := _emitter(w, ball)
	var kh := pe._ball_kind(pe._kind())
	var body: StandardMaterial3D = ((pm.kinds[kh]["mm"] as MultiMesh).mesh).surface_get_material(0)
	var hl: Dictionary = ball.params["heat_look"]
	Run.heat = 10
	var hi := 0.0
	for k in range(30):
		pm.clock += 1.0 / 90.0
		pe._tick(DT)
		hi = maxf(hi, body.emission_energy_multiplier)
	# glow_max beating by `pulse`, never cut by the cap
	assert_float(hi).is_greater(float(hl["glow_max"]) * (1.0 + float(hl["pulse"]) * 0.8))
	assert_float(hi).is_less_equal(float(hl["glow_max"]) * (1.0 + float(hl["pulse"])) + 0.001)


func test_cap_body_green_keeps_a_cold_glow_and_cuts_only_the_excess() -> void:
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission = Color("#FF5A10")
	m.emission_energy_multiplier = 2.16
	ProjectileManager._cap_body_green(m, Color("#FF3A00"), 1.6, 0.3)
	# max(its cold green 0.227 x 1.6 = 0.364, 0.3) over the new colour's green
	var want := (Color("#FF3A00").g * 1.6) / Color("#FF5A10").g
	assert_float(m.emission_energy_multiplier).is_equal_approx(want, 0.001)
	# under the cap: untouched
	m.emission_energy_multiplier = 0.5
	ProjectileManager._cap_body_green(m, Color.BLACK, 0.0, 0.3)
	assert_float(m.emission_energy_multiplier).is_equal(0.5)


# ---------------------------------------------------------------- the map number

func test_the_map_key_defaults_to_half_and_red_canyon_reads_its_json() -> void:
	# pass 72, lane INTEG (re-pinned): a map that names no number halves too (WaveTimeline.HERO_KNOCKBACK_DEFAULT 0.5), so a
	# map JSON saved without the key (an editor page opened before it existed) keeps Garry's halving
	assert_float(JsonContent.timeline_from_dict({}).hero_knockback_mult).is_equal(0.5)
	assert_float(WaveTimeline.new().hero_knockback_mult).is_equal(0.5)
	assert_float(JsonContent.timeline_from_dict({"hero_knockback_mult": 1.0}).hero_knockback_mult).is_equal(1.0)
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON))
	var tl: Dictionary = j["timeline_data"]
	# Red Canyon's number from the Registry (the .tres import_json wrote) is the JSON's (Garry may tune it), else the default
	var want: float = float(tl.get("hero_knockback_mult", WaveTimeline.HERO_KNOCKBACK_DEFAULT))
	assert_float(Registry.map("red_canyon").timeline.hero_knockback_mult).is_equal_approx(want, 0.0001)


func test_the_manager_reads_the_runs_map_and_a_test_override() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	assert_float(em.hero_knock_mult()).is_equal_approx(Registry.map("red_canyon").timeline.hero_knockback_mult, 0.0001)
	em.hero_knockback_override = 0.25
	assert_float(em.hero_knock_mult()).is_equal(0.25)
	em.hero_knockback_override = -1.0
	Run.end()
	Run.map = null
	assert_float(em.hero_knock_mult()).is_equal(1.0)


# ---------------------------------------------------------------- the pushes

## The push `src` gives a fresh creature with the map's share at `mult`.
func _hit_push(em: EnemyManager, at: Vector3, src: String, mult: float) -> float:
	em.hero_knockback_override = mult
	var i := _put(em, at)
	em.damage(i, 1.0, src, Vector3(1, 0, 0), 6.0)
	return em.kb[i].length()


func test_a_hit_from_the_heros_side_pushes_at_the_maps_share() -> void:
	var w := _world(Vector3(50, 0, 50))
	var em: EnemyManager = w["em"]
	var mass := maxf(Registry.enemy("skeleton").size, 0.8)
	var full := _hit_push(em, Vector3(0, 0, 0), "revolver", 1.0)
	assert_float(full).is_equal_approx(6.0 / mass, 0.001)
	assert_float(_hit_push(em, Vector3(0, 0, 4), "revolver", 0.5)).is_equal_approx(full * 0.5, 0.001)
	# thorns and the revive are his too
	assert_float(_hit_push(em, Vector3(0, 0, 8), "", 0.5)).is_equal_approx(full * 0.5, 0.001)
	assert_float(_hit_push(em, Vector3(0, 0, 12), "basketball", 0.5)).is_equal_approx(full * 0.5, 0.001)


func test_a_hostile_push_stays_whole() -> void:
	var w := _world(Vector3(50, 0, 50))
	var em: EnemyManager = w["em"]
	var full := _hit_push(em, Vector3(0, 0, 0), "blast", 1.0)
	assert_float(full).is_greater(0.5)
	for src: String in EnemyManager.HOSTILE_PUSH_IDS:
		assert_float(_hit_push(em, Vector3(0, 0, 4 + 4 * EnemyManager.HOSTILE_PUSH_IDS.find(src)), src, 0.5)).override_failure_message(src).is_equal_approx(full, 0.001)


func test_hero_blasts_throw_at_the_share_and_hostile_throws_whole() -> void:
	var w := _world(Vector3(50, 0, 50))
	var em: EnemyManager = w["em"]
	em.hero_knockback_override = 0.5
	var a := _put(em, Vector3(1.0, 0, 0))
	var b := _put(em, Vector3(31.0, 0, 0))
	em._rebuild_grid()
	assert_int(em.hero_throw_radius(Vector3.ZERO, 4.5, 26.0)).is_equal(1)
	assert_int(em.throw_radius(Vector3(30, 0, 0), 4.5, 26.0)).is_equal(1)
	assert_float(em.kb[a].length()).is_equal_approx(em.kb[b].length() * 0.5, 0.001)
	assert_float(em.kb[a].x).is_greater(0.0)


func test_the_nuke_thruster_burst_and_grand_finale_use_the_heros_throw() -> void:
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(src).contains('enemies.hero_throw_radius(here, Run.perk_param("thruster_burst"')
	assert_str(src).contains('enemies.hero_throw_radius(at, fr, Run.perk_param("grand_finale"')
	# pass 103 (lane PLAY): the nuke's throw names its source for Endless's knock resistance (explosive, never resisted)
	assert_str(src).contains('enemies.hero_throw_radius(at, radius, knock, -1, "nuke")')
	# the hostile throws (the rocket, the loose rocket, the golem's boulder) keep the plain throw
	assert_str(src).contains('enemies.throw_radius(ground, tr, float(blast.get("throw", 20.0)))')
	assert_str(src).contains('enemies.throw_radius(ground, reach, float(blast.get("throw", 20.0)))')
	assert_str(src).contains('enemies.throw_radius(ground, tr, float(cfg.get("throw", 22.0)), thrower)')


func test_bucking_broncos_throw_goes_half_as_far() -> void:
	var w := _world(Vector3(50, 0, 50))
	var em: EnemyManager = w["em"]
	var dist: Array = []
	for m in [1.0, 0.5]:
		em.hero_knockback_override = m
		var i := _put(em, Vector3(dist.size() * 10.0, 0, 0))
		em.set("_bronco", 1.0)
		assert_bool(em._bronco_kick(i, Vector3(1, 0, 0), 8.0, "revolver", 0.0)).is_true()
		dist.append(((em._launched[i] as Dictionary)["drift"] as Vector3).length() * EnemyManager.BRONCO_AIR)
	assert_float(float(dist[0])).is_between(EnemyManager.BRONCO_AWAY_MIN, EnemyManager.BRONCO_AWAY_MAX)
	assert_float(float(dist[1])).is_equal_approx(float(dist[0]) * 0.5, 0.001)


func test_the_tornados_toss_goes_at_the_share() -> void:
	var w := _world(Vector3(50, 0, 50))
	var em: EnemyManager = w["em"]
	em.hero_knockback_override = 0.5
	var i := _put(em, Vector3(3.0, 0, 3.0))
	em._rebuild_grid()
	assert_int(em.lift_radius(em.pos[i], 0.5, 1.0)).is_equal(1)
	var t := 0.0
	while em.lift_t[i] > 0.0 and t < 3.0:
		em._physics_process(DT)
		t += DT
	assert_float(em.kb[i].length()).is_equal_approx(12.0 * 0.5, 0.001)


func test_the_ram_shoves_at_the_share() -> void:
	Run.end()
	Run.start(Registry.character("buck"), Registry.map("red_canyon"))
	assert_bool(Run.add_perk("ram")).is_true()
	Run.momentum = 1.0
	var shove := Run.perk_param("ram", "shove", 0.0)
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	em.hero_knockback_override = 0.5
	var r: float = Registry.enemy("skeleton").radius
	var i := _put(em, Vector3(r + 0.3, 0, 0))
	em.hp[i] = 1000.0
	em.max_hp[i] = 1000.0
	em.contact_cd[i] = 0.0
	em._physics_process(DT)
	assert_float(em.kb[i].x).is_equal_approx(shove * 0.5, 0.001)


func test_the_guitarras_bounce_lands_with_half_the_shove() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var knocks: Array = []
	for m in [1.0, 0.5]:
		em.hero_knockback_override = m
		var cw := ConeWave.new()
		(w["g"] as Node).add_child(cw)
		var inst := WeaponInstance.new(Registry.weapon("guitarra"), 1)
		inst.rebuild(Run.player_sheet, [inst])
		cw.setup(inst, w["g"])
		cw.inst.params["familiar"] = {"radius": 0.0, "height": 1.5, "bob": 0.0}
		cw._familiar.global_position = Vector3(0, 1.5, 0)
		var i := _put(em, Vector3(3, 0, 0))
		em._rebuild_grid()
		cw._wave(EAST, 1.0, false)
		knocks.append(em.lift_knock[i].length())
		em.kill_all(false)
		cw.queue_free()
	assert_float(float(knocks[0])).is_greater(0.1)
	assert_float(float(knocks[1])).is_equal_approx(float(knocks[0]) * 0.5, 0.001)


func test_the_pull_and_the_resist_are_untouched() -> void:
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	em.hero_knockback_override = 0.5
	assert_object(Run.add_weapon(Registry.weapon("branding_iron"), 1)).is_not_null()
	assert_bool(Run.add_mutation("lasso", true)).is_true()
	var pl: float = Run.weapon_instance("branding_iron").stat("pull", 0.0)
	assert_float(pl).is_greater(0.0)
	var i := _put(em, Vector3(3, 0, 0))
	em.damage(i, 1.0, "branding_iron")
	# the Lasso tows it the whole pull (the Branding Iron has no knockback of its own)
	assert_float(em.kb[i].x).is_equal_approx(-pl, 0.001)
