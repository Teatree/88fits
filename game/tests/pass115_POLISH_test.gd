extends GdUnitTestSuite

## Pass 115, lane POLISH: four things Garry asked for.
## 1. Far creatures catch up harder the further they trail (timeline_data.far_speed: `curve` and `max_speed` since pass
##    115; EnemyManager.far_speed_mult / far_speed_k): the ramp is monotonic, 1 inside its distance, capped at max_mult
##    past distance + ramp, at least pass 111's everywhere and more past 20 m; the boost never takes a walk past
##    max_speed, never slows one; Jeżyk's measured top speed (level 20, full Momentum, The Chariot at level 4) stays above
##    what the fastest regular creature on the map walks at its fastest far away, a typical Jeżyk (level 10, Momentum)
##    gains less on a far skeleton than under pass 111.
## 2. The tornado (timeline_data.dust_devils): bigger (radius x1.25, the funnel x1.25), three times as long, about 0.75 as
##    solid, the hero thrown and creatures lifted about 1.4 times as high; the dust devil wears those numbers.
## 3. Barrels throw out a power-up half as often (timeline_data.barrels.*.powerup_chance).
## 4. The Beehive's Pollen flowers: 1.6 times as big, swaying and breathing, a soft ring under each (FlowerField).

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"

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
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var launches: Array = []
func launch(v: Vector3) -> void:
	launches.append(v)
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

## Pass 111's rule, to compare against: x1 to 14 m, a smoothstep to x2 at 20 m.
const OLD := {"distance": 14.0, "ramp": 6.0, "max_mult": 2.0}


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


func _raw_tl() -> Dictionary:
	return (JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON)) as Dictionary).get("timeline_data", {})


func _game() -> Dictionary:
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
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


## The hero's walking speed (m/s) as a run plays it: Jeżyk at `level`, his Momentum at `momentum`, The Chariot at `chariot`.
func _jezyk(level: int, momentum: float, chariot: int) -> float:
	Run.start(Registry.character("buck"), Registry.map("red_canyon"))
	Run.level = level
	Run.mutation_levels = 0
	Run.momentum = momentum
	if chariot > 0:
		Run.passives["stride"] = chariot
	Run.rebuild_sheets()
	return Run.player_sheet.get_stat("move_speed", 5.0) * Run.move_pace()


## The map's own far-speed block, every key filled.
func _cfg() -> Dictionary:
	return Registry.map("red_canyon").timeline.far_speed_cfg()


func _mult(c: Dictionary, d: float) -> float:
	return EnemyManager.far_speed_mult(d, float(c["distance"]), float(c["ramp"]), float(c["max_mult"]), EnemyManager.FAR_CURVES.find(str(c["curve"])))


# ---------------------------------------------------------------- 1. far creatures

func test_the_ramp_is_monotonic_capped_and_never_below_pass_111s() -> void:
	var c := _cfg()
	var raw: Dictionary = _raw_tl().get("far_speed", {})
	# the map names the new keys
	assert_bool(raw.has("curve") and raw.has("max_speed")).is_true()
	assert_float(float(c["max_mult"])).is_greater(OLD["max_mult"])
	var last := 0.0
	for k in range(0, 601):
		var d := 0.1 * float(k)
		var m := _mult(c, d)
		assert_float(m).is_greater_equal(last - 1e-6)
		last = m
		if d <= float(c["distance"]):
			assert_float(m).is_equal(1.0)
		if d >= float(c["distance"]) + float(c["ramp"]):
			assert_float(m).is_equal_approx(float(c["max_mult"]), 1e-4)
		assert_float(m).is_less_equal(float(c["max_mult"]) + 1e-6)
		# at least pass 111's at every distance, more past its 20 m
		var old := EnemyManager.far_speed_mult(d, OLD["distance"], OLD["ramp"], OLD["max_mult"])
		assert_float(m).is_greater_equal(old - 1e-6)
		if d >= 22.0:
			assert_float(m).is_greater(old + 0.2)
	# every curve is monotonic from 1 to max_mult
	for curve in range(EnemyManager.FAR_CURVES.size()):
		var prev := 1.0
		for k in range(0, 41):
			var m := EnemyManager.far_speed_mult(10.0 + float(k), 12.0, 24.0, 3.0, curve)
			assert_float(m).is_greater_equal(prev - 1e-6)
			prev = m
		assert_float(prev).is_equal_approx(3.0, 1e-4)
	# the despawn line stays at 40 m: the full speed is reached inside it
	assert_float(float(c["distance"]) + float(c["ramp"])).is_less_equal(40.0)


func test_the_cap_bounds_the_boost_and_never_slows_a_walk() -> void:
	var w := _game()
	var em: EnemyManager = w["em"]
	em.set_far_speed({"enabled": true, "distance": 12.0, "max_mult": 3.0, "ramp": 24.0, "bosses": true, "curve": "ease_out", "max_speed": 6.0})
	var i := em.spawn("skeleton", Vector3(40, 0, 0), null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.elite_idx[i] = -1
	em.vspecial[i] = 0
	# a slow walk takes the whole x3
	assert_float(em.far_speed_k(i, 40.0, 1.3)).is_equal_approx(3.0, 1e-4)
	# a quicker one stops at 6 m/s
	assert_float(1.0 * 2.72 * em.far_speed_k(i, 40.0, 2.72)).is_equal_approx(6.0, 1e-4)
	# one already faster keeps its own speed
	assert_float(em.far_speed_k(i, 40.0, 7.0)).is_equal(1.0)
	# inside the distance nothing
	assert_float(em.far_speed_k(i, 10.0, 1.3)).is_equal(1.0)
	# no cap: the whole multiplier
	em.set_far_speed({"enabled": true, "distance": 12.0, "max_mult": 3.0, "ramp": 24.0, "bosses": true, "curve": "ease_out", "max_speed": 0.0})
	assert_float(em.far_speed_k(i, 40.0, 2.72)).is_equal_approx(3.0, 1e-4)


func test_a_fast_jezyk_still_outruns_the_fastest_far_creature_and_gains_less_than_before() -> void:
	var c := _cfg()
	var cap := float(c["max_speed"])
	assert_float(cap).is_greater(0.0)
	var fast := _jezyk(20, 1.0, 4)
	var typical := _jezyk(10, 1.0, 0)
	var start := _jezyk(1, 0.0, 0)
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var drifter := Run.player_sheet.get_stat("move_speed", 5.0) * Run.move_pace()
	# the fastest regular creature on the map at its own walk at the last stage's speed (no row's own boost)
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var pace := Run.move_pace() * tl.creature_speed_mult * tl.speed_mult(2)
	var text := FileAccess.get_file_as_string(MAP_JSON)
	var best := 0.0
	var best_id := ""
	for e: EnemyDef in Registry.enemies.values():
		if EnemyManager.far_kind_of(e) != EnemyManager.FAR_REGULAR or not text.contains("\"%s\"" % e.id):
			continue
		if e.speed * pace > best:
			best = e.speed * pace
			best_id = e.id
	var far := best * _mult(c, 40.0)
	if cap > 0.0 and far > cap:
		far = maxf(best, cap)
	print("pass115 POLISH: Jezyk start %.2f, typical %.2f, fast %.2f m/s; Drifter %.2f; fastest regular %s %.2f m/s, far %.2f m/s (pass 111: %.2f)" % [
		start, typical, fast, drifter, best_id, best, far, best * 2.0])
	assert_float(fast).is_greater(far)
	assert_float(fast).is_greater(cap)
	# a far skeleton: he gains less on it than under pass 111 (x2 at 40 m)
	var sk: EnemyDef = Registry.enemy("skeleton")
	var walk := sk.speed * Run.move_pace() * tl.creature_speed_mult
	var now := minf(walk * _mult(c, 40.0), maxf(walk, cap))
	assert_float(typical - now).is_less(typical - walk * 2.0)
	assert_float(typical).is_greater(now)


# ---------------------------------------------------------------- 2. the tornado

func test_the_tornado_is_bigger_three_times_as_long_thinner_and_throws_higher() -> void:
	var raw: Dictionary = _raw_tl().get("dust_devils", {})
	var c := DustDevils.config_of(raw)
	assert_object(c["life"]).is_equal(Vector2(60.0, 90.0))
	assert_float(float(c["radius"])).is_equal_approx(2.4 * 1.25, 1e-4)
	assert_float(float(c["size"])).is_equal(1.25)
	assert_float(float(c["opacity"])).is_equal_approx(0.94 * 0.75, 0.02)
	# the hero's throw: up v^2 / (2 g) under his 24 m/s2, against pass 113's 8 m/s
	var up := float(c["toss"]["up"])
	assert_float((up * up) / (8.0 * 8.0)).is_between(1.3, 1.5)
	assert_float(float(c["lift_height"]) / EnemyManager.TORNADO_LIFT_H).is_between(1.3, 1.5)
	# the defaults are the same numbers (an empty block plays them)
	var d := DustDevils.config_of(null)
	for k in ["life", "radius", "size", "opacity", "lift_height"]:
		assert_that(d[k]).is_equal(c[k])
	assert_float(float(d["toss"]["up"])).is_equal(up)


func test_a_dust_devil_wears_its_size_and_opacity_and_lifts_creatures_higher() -> void:
	var w := _game()
	var em: EnemyManager = w["em"]
	var dd := DustDevil.new()
	dd.game = w["g"]
	var c := DustDevils.config_of(null)
	dd.setup(c, Vector3(2, 0, 0), Vector3(0, 0, 1), 70.0, 7)
	(w["g"] as Node).add_child(dd)
	assert_float(dd.fx.height).is_equal_approx(DustDevil.HEIGHT * 1.25, 1e-4)
	assert_float(dd.fx.radius_top).is_equal_approx(DustDevil.R_TOP * 1.25, 1e-4)
	assert_float(dd.fx.opacity).is_equal_approx(0.7, 1e-4)
	assert_float(dd.fx.skirt_opacity).is_equal_approx(0.7 * DustDevil.SKIRT_SHARE, 1e-4)
	assert_float(dd.reach()).is_equal_approx(3.5, 1e-4)
	dd.speed = 0.0
	var i := em.spawn("skeleton", Vector3(2.0, 0, 1.0), null, 1.0, 500.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	dd.step(float(c["form_seconds"]) + 0.1)
	assert_float(em.lift_t[i]).is_greater(0.0)
	assert_float(em.lift_peak[i]).is_equal_approx(4.5, 1e-4)
	# the hero thrown 9.5 up
	var hero = w["hero"]
	assert_int(hero.launches.size()).is_equal(1)
	assert_float((hero.launches[0] as Vector3).y).is_equal(9.5)
	# the ride's top: 4.5 m x its size (pass 113: 3.2)
	var top := 0.0
	var t := 0.0
	while em.lift_t[i] > 0.0 and t < 3.0:
		em._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0
		top = maxf(top, em.lift_h[i])
	assert_float(top).is_equal_approx(4.5 * maxf(em.size[i], 0.6), 0.15)
	# the bees' old twister keeps pass 44's height
	var j := em.spawn("skeleton", Vector3(-6, 0, 0), null, 1.0, 500.0)
	em.rise_t[j] = 1.0
	em.twist(j, 1.0, Vector3(-7, 0, 0))
	assert_float(em.lift_peak[j]).is_equal_approx(EnemyManager.TORNADO_LIFT_H, 1e-4)


# ---------------------------------------------------------------- 3. barrels

func test_barrels_throw_out_a_power_up_half_as_often() -> void:
	var raw: Dictionary = _raw_tl().get("barrels", {})
	var brown := BarrelSpawns.contents_of(raw, false)
	var black := BarrelSpawns.contents_of(raw, true)
	# the shipped build's (pass 114) 8% and 30%, halved: the brown one by Garry's own hand in the Level Editor (0.04), the
	# black one here; read from the map so a later tune of his is kept (each at most half of pass 114's)
	var shipped := {"brown": 0.08, "black": 0.3}
	assert_float(float(brown["powerup_chance"])).is_less_equal(shipped["brown"] * 0.5 + 1e-6)
	assert_float(float(black["powerup_chance"])).is_less_equal(shipped["black"] * 0.5 + 1e-6)
	assert_float(float(black["powerup_chance"])).is_greater(0.0)


# ---------------------------------------------------------------- 4. the Pollen flowers

func test_pollen_flowers_are_bigger_sway_breathe_and_have_a_ring() -> void:
	Run.debug_set_item("weapon", "hornet_nest", 5)
	Run.debug_set_item("mutation", "pollen", 1)
	var cfg := FlowerField.held_config()
	assert_float(float(cfg.get("flower_size", 0.0))).is_equal(1.6)
	assert_float(FlowerField.flower_size(cfg)).is_equal(1.6)
	assert_float(FlowerField.flower_size({})).is_equal(FlowerField.FLOWER_SIZE)
	var w := _game()
	var ff: FlowerField = FlowerField.ensure(w["g"])
	assert_object(ff).is_not_null()
	await get_tree().process_frame
	ff._cfg = cfg
	ff.grow_at(Vector3(4, 0, 0), true)
	ff.grow_at(Vector3(-4, 0, 0), true)
	assert_int(ff.flowers.size()).is_equal(2)
	var f: Dictionary = ff.flowers[0]
	# 0.8..1.25 of pass 48's size, times 1.6
	assert_float(float(f["size"])).is_between(FlowerField.SIZE_MIN * 1.6 - 1e-4, FlowerField.SIZE_MAX * 1.6 + 1e-4)
	assert_object(f["halo"]).is_not_null()
	# grown, then it sways and breathes: the roll and the squash change over a second
	var rolls: Array = []
	var squashes: Array = []
	for k in range(60):
		ff._tick_flowers(1.0 / 30.0)
		var sp: BillboardSprite = f["sprite"]
		rolls.append(float(sp._mat.get_shader_parameter("roll")))
		squashes.append(float(sp._mat.get_shader_parameter("stretch")))
	var rmin: float = rolls.min()
	var rmax: float = rolls.max()
	var smin: float = squashes.slice(20).min()
	var smax: float = squashes.slice(20).max()
	assert_float(rmax - rmin).is_greater(deg_to_rad(6.0))
	assert_float(rmax).is_less_equal(deg_to_rad(9.0) + 1e-4)
	assert_float(smax - smin).is_greater(0.05)
	assert_float(smax).is_less_equal(1.0 + 0.07 + 1e-4)
	var halo: MeshInstance3D = f["halo"]
	assert_bool(halo.visible).is_true()
	assert_float(halo.scale.x).is_greater(0.8)
	# halo 0: no ring
	var none := cfg.duplicate(true)
	none["halo"] = 0.0
	ff._cfg = none
	ff.grow_at(Vector3(0, 0, 6), true)
	assert_object(ff.flowers[ff.flowers.size() - 1]["halo"]).is_null()
	# picking is as before: within PICK_R of its foot
	assert_float(FlowerField.PICK_R).is_equal(1.2)
