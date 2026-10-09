extends GdUnitTestSuite

## Pass 61, lane WP2 (Garry: "Mutation Visual, implement every Cheap version" and "Make the attack of the scepter visuals
## a bit stronger. For both the 'projectile' and the scepter itself"). Rust oxidises the Orbit Saws and sheds flakes;
## Bad Breath turns the Big Mouth's beam green-yellow and wobbling and puffs gusts where it hits; Critical Thinking puts
## a bright razor edge on the Sabre and draws a white hairline across what it crits; Riposte hangs a brass guard bar on
## it and ends every slice in a quick reverse flick with a clang. Each look comes with its mutation and goes with it.
## The Sun Scepter's pillar lands harder (a fat white core, a pop, motes, a shock ring, a glow on the sand, a longer
## fade) and the sceptre shakes harder, flares bigger and pulses its sun disc, all pooled.

const SCEPTER := preload("res://core/behaviors/SunScepter.gd")
const BEAMS := preload("res://core/systems/SunBeams.gd")

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
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_lightning(_points) -> void:
	pass
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
func shove(_v: Vector3) -> bool:
	return true
func blast(_v: Vector3, _u: float = 0.0) -> void:
	pass
func apply_knockback(_v: Vector3) -> void:
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
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.base_crit = false
	Run.debug_clear_items()
	Run.end()


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
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg}


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


## The same build change Game._sync_weapons makes: the instance re-folded with a new set of mutations, then the marks.
func _rebuild_with(b: WeaponBehavior, muts: Array) -> void:
	b.inst.mutations.clear()
	for m: String in muts:
		b.inst.mutations.append(Registry.mutation(m))
	b.inst.rebuild(Run.player_sheet, [b.inst])
	b.refresh_marks()


func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	em.refresh_crowd_stats()
	return i


func _ticks(b: WeaponBehavior, seconds: float) -> void:
	for k in range(int(round(seconds / DT))):
		b._tick(DT)


func _near(a: Color, c: Color, eps := 0.01) -> bool:
	return absf(a.r - c.r) < eps and absf(a.g - c.g) < eps and absf(a.b - c.b) < eps


# ---------------------------------------------------------------- Rust

func test_rust_oxidises_the_saws_and_goes_with_the_mutation() -> void:
	var w := _world()
	var b := _behaviour(w, Orbiter.new(), "orbit_saws", [], 3) as Orbiter
	b._tick(DT)
	var mmi := b.get_node("Blades") as MultiMeshInstance3D
	# plain: the visual's own silver material, no shader
	assert_bool(b.rusted()).is_false()
	assert_bool(mmi.material_override is ShaderMaterial).is_false()
	# Rust picked mid-run: the blades take the rusted shader over their own colour
	_rebuild_with(b, ["rust"])
	assert_bool(b.rusted()).is_true()
	assert_bool(mmi.material_override is ShaderMaterial).is_true()
	var m := mmi.material_override as ShaderMaterial
	assert_str(m.shader.resource_path).is_equal("res://core/shaders/rust_blade.gdshader")
	assert_float(float(m.get_shader_parameter("amount"))).is_equal_approx(0.75, 0.001)
	assert_bool(_near(m.get_shader_parameter("base_color"), Color(0.86, 0.88, 0.92))).is_true()
	assert_object(m.get_shader_parameter("noise_tex")).is_not_null()
	# gone again without it
	_rebuild_with(b, [])
	assert_bool(b.rusted()).is_false()
	assert_bool(mmi.material_override is ShaderMaterial).is_false()


func test_rusted_saws_shed_flakes_while_they_spin_and_plain_ones_none() -> void:
	var w := _world()
	var fx: Fx = w["fx"]
	var plain := _behaviour(w, Orbiter.new(), "orbit_saws", [], 3) as Orbiter
	_ticks(plain, 1.0)
	assert_int(plain.flakes).is_equal(0)
	plain.queue_free()
	var b := _behaviour(w, Orbiter.new(), "orbit_saws", ["rust"], 3) as Orbiter
	var before := fx._n
	_ticks(b, 1.0)
	# about `flakes` (12) a second, nothing with nothing to hit
	assert_int(b.flakes).is_between(9, 14)
	assert_int(fx._n).is_greater(before)
	# capped a frame: a long frame sheds no more than FLAKES_PER_FRAME
	var n0 := b.flakes
	b._tick(2.0)
	assert_int(b.flakes - n0).is_less_equal(Orbiter.FLAKES_PER_FRAME)


func test_the_saw_halo_keeps_its_gold_under_a_patina_of_rust() -> void:
	var w := _world()
	var halo := _behaviour(w, Orbiter.new(), "saw_halo", ["rust", "saw_swarm", "wide_orbit"]) as Orbiter
	halo._tick(DT)
	assert_bool(halo.rusted()).is_true()
	var m := (halo.get_node("Blades") as MultiMeshInstance3D).material_override as ShaderMaterial
	# its own patina over Rust's: less rust, a thinner rim, over its gold
	assert_float(float(m.get_shader_parameter("amount"))).is_equal_approx(0.4, 0.001)
	assert_float(float(m.get_shader_parameter("rim"))).is_equal_approx(0.12, 0.001)
	# its gold as it shows (the albedo and its glow), never the silver
	var gold: Color = m.get_shader_parameter("base_color")
	assert_float(gold.r).is_greater(0.95)
	assert_float(gold.b).is_less(0.7)
	assert_float(float(m.get_shader_parameter("pits"))).is_equal_approx(0.35, 0.001)
	# the solid ring wears it too
	assert_object(halo._ring).is_not_null()
	assert_object(halo._ring.material_override).is_same(m)
	# a halo handed over without Rust (the arena) stays gold
	var bare := _behaviour(w, Orbiter.new(), "saw_halo") as Orbiter
	bare._tick(DT)
	assert_bool(bare.rusted()).is_false()


# ---------------------------------------------------------------- Bad Breath

func test_bad_breath_turns_the_beam_green_yellow_and_sets_it_wobbling() -> void:
	var w := _world()
	var plain := _behaviour(w, LaserBeam.new(), "big_mouth") as LaserBeam
	assert_bool(plain.breath().is_empty()).is_true()
	assert_bool(_near(plain._beam_colour(), Color(1.0, 0.25, 0.7))).is_true()
	assert_float(plain.wobble()).is_equal(0.0)
	assert_float(plain._beam_haze().a).is_equal(0.0)
	var b := _behaviour(w, LaserBeam.new(), "big_mouth", ["mouth_knock"]) as LaserBeam
	assert_bool(_near(b._beam_colour(), Color(0.66, 1.0, 0.16))).is_true()
	assert_float(b.wobble()).is_equal_approx(1.0, 0.001)
	assert_float(b._beam_haze().a).is_equal_approx(0.6, 0.001)
	# its old numbers are untouched: half again as wide, the first touch throws
	assert_float(b._beam_param("width_mult", 1.0)).is_equal_approx(1.5, 0.001)
	assert_bool(b._beam_flag("first_knock")).is_true()
	# with Slow Roast the line stays orange and the breath is its haze (the Loudmouth carries both)
	var both := _behaviour(w, LaserBeam.new(), "big_mouth", ["mouth_knock", "mouth_burn"]) as LaserBeam
	assert_bool(_near(both._beam_colour(), Color(1.0, 0.45, 0.15))).is_true()
	assert_bool(_near(both._beam_haze(), Color(0.92, 1.0, 0.3))).is_true()
	var loud := _behaviour(w, LaserBeam.new(), "loudmouth", ["mouth_knock", "mouth_burn", "mouth_arch"]) as LaserBeam
	assert_float(loud.wobble()).is_equal_approx(1.0, 0.001)
	# the shader is told while it pours
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(0, 0, -5))
	assert_bool(b._fire()).is_true()
	_ticks(b, LaserBeam.WINDUP + 0.05)
	assert_float(float(b._beam_mat.get_shader_parameter("wobble"))).is_equal_approx(1.0, 0.001)
	assert_bool(_near(b._beam_mat.get_shader_parameter("color"), Color(0.66, 1.0, 0.16))).is_true()


func test_bad_breath_puffs_gusts_where_it_hits_and_the_plain_beam_none() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(3):
		_creature(em, Vector3(0.0, 0, -3.0 - 2.0 * k))
	var plain := _behaviour(w, LaserBeam.new(), "big_mouth") as LaserBeam
	assert_bool(plain._fire()).is_true()
	_ticks(plain, LaserBeam.WINDUP + 0.6)
	assert_int(plain.gust_hits).is_equal(0)
	plain.queue_free()
	var b := _behaviour(w, LaserBeam.new(), "big_mouth", ["mouth_knock"]) as LaserBeam
	var fx: Fx = w["fx"]
	var before := fx._n
	assert_bool(b._fire()).is_true()
	_ticks(b, LaserBeam.WINDUP + 0.05)
	# the first touch: a big gust off what stands in the line
	assert_int(b.gust_hits).is_greater_equal(1)
	assert_int(fx._n).is_greater(before)
	# and on: no more than BIG_GUSTS big ones and `gusts` small ones a tick
	var g0 := b.gust_hits
	b._burn()
	assert_int(b.gust_hits - g0).is_less_equal(2)


# ---------------------------------------------------------------- Critical Thinking

func test_critical_thinking_puts_a_razor_edge_on_the_blade() -> void:
	var w := _world()
	var plain := _behaviour(w, Thruster.new(), "sabre", [], 3) as Thruster
	assert_bool(plain.shows_look("LookRazor")).is_false()
	assert_bool(plain.shows_look("LookGuard")).is_false()
	var b := _behaviour(w, Thruster.new(), "sabre", ["critical_thinking"], 3) as Thruster
	assert_bool(b.shows_look("LookRazor")).is_true()
	assert_bool(b.shows_look("LookGuard")).is_false()
	# a copy made for a stroke carries it, and dropping the mutation takes it off every copy
	b._ensure_blades(3)
	for blade: Node3D in b._blades:
		assert_bool((blade.get_node("LookRazor") as Node3D).visible).is_true()
	_rebuild_with(b, [])
	assert_bool(b.shows_look("LookRazor")).is_false()
	for blade: Node3D in b._blades:
		assert_bool((blade.get_node("LookRazor") as Node3D).visible).is_false()
	# the Whirlwind has its own edge on its curved blade
	var whirl := _behaviour(w, Thruster.new(), "whirlwind", ["critical_thinking", "flurry", "riposte"]) as Thruster
	assert_bool(whirl.shows_look("LookRazor")).is_true()
	assert_bool(whirl.shows_look("LookGuard")).is_true()


func test_last_crit_tells_whether_the_last_hit_crit() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(2, 0, 0))
	Run.player_sheet.set_base("crit_chance", 1.0)
	em.damage(i, 1.0, "sabre")
	assert_bool(em.last_crit).is_true()
	# a tick (poison) never crits; a missed hit is no crit
	em.damage(i, 1.0, "sabre", Vector3.ZERO, 0.0, true)
	assert_bool(em.last_crit).is_false()
	em.damage(i, 1.0, "sabre")
	em.damage(-1, 1.0, "sabre")
	assert_bool(em.last_crit).is_false()
	Run.player_sheet.set_base("crit_chance", 0.0)
	em.damage(i, 1.0, "sabre")
	assert_bool(em.last_crit).is_false()


func test_the_crit_streak_fires_only_on_a_crit_and_only_with_critical_thinking() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(3):
		_creature(em, Vector3(-1.0 + float(k), 0, -1.8))
	# Critical Thinking, no crits: no streak
	Run.player_sheet.set_base("crit_chance", 0.0)
	var b := _behaviour(w, Thruster.new(), "sabre", ["critical_thinking"], 3) as Thruster
	assert_bool(b._fire()).is_true()
	_ticks(b, 0.6)
	assert_int(b.slashes).is_equal(0)
	# every hit a crit: a streak on every creature it cut, drawing itself across and fading
	Run.player_sheet.set_base("crit_chance", 1.0)
	b.cooldown_left = 0.0
	assert_bool(b._fire()).is_true()
	var seen := 0
	for k in range(int(0.6 / DT)):
		b._tick(DT)
		seen = maxi(seen, b.slashes_live())
	assert_int(b.slashes).is_greater_equal(3)
	assert_int(seen).is_greater_equal(1)
	assert_int(seen).is_less_equal(Thruster.SLASH_MAX)
	# and gone after its life, the mesh hidden
	_ticks(b, Thruster.SLASH_LIFE + 0.1)
	assert_int(b.slashes_live()).is_equal(0)
	# crits without Critical Thinking: no streak
	var plain := _behaviour(w, Thruster.new(), "sabre", [], 3) as Thruster
	assert_bool(plain._fire()).is_true()
	_ticks(plain, 0.6)
	assert_int(plain.slashes).is_equal(0)


# ---------------------------------------------------------------- Riposte

func test_riposte_hangs_a_brass_guard_bar() -> void:
	var w := _world()
	var b := _behaviour(w, Thruster.new(), "sabre", ["riposte"], 3) as Thruster
	assert_bool(b.shows_look("LookGuard")).is_true()
	assert_bool(b.shows_look("LookRazor")).is_false()
	# a heavy bar wider than the plain guard (0.85 across the blade's model; its parts may be merged into one mesh)
	var widest := 0.0
	for mi: MeshInstance3D in b._proto.get_node("LookGuard").find_children("*", "MeshInstance3D", true, false):
		widest = maxf(widest, (mi.transform * mi.mesh.get_aabb()).size.x)
	assert_float(widest).is_greater(1.0)


func test_riposte_flicks_back_with_one_clang_a_stroke_and_the_stroke_is_no_longer() -> void:
	# the flick's shape: out to full by its peak, settled by its end
	assert_float(Thruster.flick_at(0.0)).is_equal(0.0)
	assert_float(Thruster.flick_at(Thruster.FLICK_PEAK)).is_equal_approx(1.0, 0.0001)
	assert_float(Thruster.flick_at(1.0)).is_equal(0.0)
	assert_float(Thruster.flick_at(0.9)).is_less(0.1)
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(0, 0, -1.8))
	var plain := _behaviour(w, Thruster.new(), "sabre", [], 3) as Thruster
	assert_float(plain.flick_time(0.12)).is_equal(0.0)
	assert_bool(plain._fire()).is_true()
	var t_plain := 0.0
	while plain.stroke_running() and t_plain < 3.0:
		plain._tick(DT)
		t_plain += DT
	assert_int(plain.clangs).is_equal(0)
	plain.queue_free()
	var b := _behaviour(w, Thruster.new(), "sabre", ["riposte"], 3) as Thruster
	var back := b._thrust("back", 0.12)
	assert_float(b.flick_time(back)).is_greater(0.05)
	assert_float(b.flick_time(back)).is_less_equal(back * Thruster.FLICK_SHARE + 0.0001)
	var fx: Fx = w["fx"]
	assert_bool(b._fire()).is_true()
	var end_yaw := 0.0
	var max_back := 0.0
	var t := 0.0
	var out := b._thrust("out", 0.06)
	var swings_end := out + b._thrust("slice", 0.16) * float(b._swings())
	var n_before := fx._n
	while b.stroke_running() and t < 3.0:
		b._tick(DT)
		t += DT
		if b._blades.is_empty():
			continue
		var yaw: float = (b._blades[0] as Node3D).rotation.y
		if t <= swings_end:
			end_yaw = yaw
		elif t < swings_end + b.flick_time(back):
			max_back = maxf(max_back, absf(angle_difference(end_yaw, yaw)))
	# it snapped back a good part of its flick_deg against the last swing, clanged once, and took no longer
	assert_float(rad_to_deg(max_back)).is_greater(15.0)
	assert_int(b.clangs).is_equal(1)
	assert_int(fx._n).is_greater(n_before)
	assert_float(absf(t - t_plain)).is_less(DT * 1.5)


# ---------------------------------------------------------------- the Sun Scepter

func test_the_pillar_lands_harder_and_fades_slower() -> void:
	# a longer fade and a bigger pop than pass 54's 0.2 s and 0.6
	assert_float(BEAMS.FADE).is_greater(0.3)
	assert_float(BEAMS.LAND_POP).is_greater(0.6)
	assert_float(BEAMS.impact_at(0.2, 0.45)).is_equal(0.0)
	assert_float(BEAMS.impact_at(0.45, 0.45)).is_equal_approx(1.0, 0.0001)
	assert_float(BEAMS.impact_at(0.45 + BEAMS.FADE * 0.5, 0.45)).is_between(0.1, 0.5)
	assert_float(BEAMS.impact_at(0.45 + BEAMS.FADE, 0.45)).is_equal(0.0)
	# the quad wider by LAND_WIDEN the instant it lands, back to its own width by the end of the fade
	assert_float(BEAMS.width_at(2.0, 0.2, 0.45)).is_equal(2.0)
	assert_float(BEAMS.width_at(2.0, 0.45, 0.45)).is_equal_approx(2.0 * (1.0 + BEAMS.LAND_WIDEN), 0.0001)
	assert_float(BEAMS.width_at(2.0, 0.45 + BEAMS.FADE * 0.5, 0.45)).is_between(2.02, 2.0 * (1.0 + BEAMS.LAND_WIDEN))
	assert_float(BEAMS.LAND_WIDEN).is_greater(0.1)
	# the slot goes back to the pool when the fade is over
	var sb: Node3D = auto_free(BEAMS.new())
	add_child(sb)
	sb.begin(Vector3.ZERO, 1.3, 0.45, Color(1, 0.8, 0.3), 0.55)
	sb.tick(0.45)
	assert_int(sb.live()).is_equal(1)
	sb.tick(BEAMS.FADE + 0.01)
	assert_int(sb.live()).is_equal(0)


func test_a_landing_pops_rings_and_glows_the_sand_with_no_new_nodes() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var fx: Fx = w["fx"]
	var tg: Telegraphs = w["tg"]
	_creature(em, Vector3(4, 0, 0))
	var b = SCEPTER.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst("sun_scepter"), w["g"])
	_ticks(b, 0.2)
	var nodes: int = b.get_child_count()
	var fx_nodes := fx.get_child_count()
	var marks0 := tg.live_count()
	assert_bool(b._fire()).is_true()
	var p0 := fx._n
	_ticks(b, 0.5)
	assert_int(b.impacts).is_equal(1)
	# a pop and motes in the pools, the shock ring and the glow among the ground marks
	assert_int(tg.live_count()).is_greater_equal(marks0 + 2)
	# five strikes more: nothing built per strike
	for k in range(5):
		b.cooldown_left = 0.0
		b._fire()
		_ticks(b, 0.6)
	assert_int(b.impacts).is_equal(6)
	assert_int(b.get_child_count()).is_equal(nodes)
	assert_int(fx.get_child_count()).is_equal(fx_nodes)
	assert_int(fx._n).is_less_equal(Fx.MAX_P)
	assert_int(p0).is_greater_equal(0)


func test_the_sceptre_shakes_harder_flares_bigger_and_pulses_its_sun() -> void:
	# pass 55 shook it 5 degrees with a 0.05 m kick
	assert_float(SCEPTER.SHAKE_DEG).is_greater_equal(8.0)
	assert_float(SCEPTER.SHAKE_KICK).is_greater(0.05)
	# the shine: bigger on both, Zenith still over the plain one, its sweep over its strike
	var plain: Dictionary = Registry.weapon("sun_scepter").params["shine"]
	var zen: Dictionary = Registry.weapon("zenith").params["shine"]
	assert_float(float(plain["flare"])).is_greater(1.1)
	assert_float(float(plain["pop"])).is_greater(0.0)
	assert_float(float(zen["flare"])).is_greater(float(plain["flare"]))
	assert_float(float(zen["sweep"])).is_greater(float(zen["flare"]))
	assert_float(float(zen["pop"])).is_greater(float(plain["pop"]))
	# the disc's pulse: up at the call, half again at the landing, back to rest
	assert_float(SCEPTER.pulse_at(-0.1)).is_equal(0.0)
	assert_float(SCEPTER.pulse_at(SCEPTER.PULSE_UP)).is_equal_approx(1.0, 0.0001)
	assert_float(SCEPTER.pulse_at(SCEPTER.PULSE_UP + SCEPTER.PULSE_DOWN)).is_equal(0.0)
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(4, 0, 0))
	var b = SCEPTER.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst("sun_scepter"), w["g"])
	_ticks(b, 0.3)
	assert_bool(b._disc.is_empty()).override_failure_message("the sun disc has no emissive surface").is_false()
	var rest: float = b.disc_energy()
	var rest_scale: float = b._sun.scale.x
	assert_bool(b._fire()).is_true()
	_ticks(b, SCEPTER.PULSE_UP)
	assert_float(b.pulse_now()).is_greater(0.9)
	assert_float(b.disc_energy()).is_greater(rest + SCEPTER.PULSE_EMIT * 0.8)
	assert_float(b._sun.scale.x).is_greater(rest_scale * 1.15)
	# the landing pulses it again, softer
	var pulses: int = b.pulses
	var guard := 0
	while b.pulses == pulses and guard < 60:
		b._tick(DT)
		guard += 1
	assert_int(b.pulses).is_equal(pulses + 1)
	_ticks(b, SCEPTER.PULSE_UP)
	assert_float(b.pulse_now()).is_between(SCEPTER.PULSE_LAND * 0.8, SCEPTER.PULSE_LAND + 0.01)
	_ticks(b, SCEPTER.PULSE_DOWN + 0.05)
	assert_float(b.disc_energy()).is_equal_approx(rest, 0.0001)
	assert_float(b._sun.scale.x).is_equal_approx(rest_scale, 0.0001)
