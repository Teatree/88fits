extends GdUnitTestSuite

## Pass 127 (Garry on Black Sunday: "a bit smaller (25% smaller)"; "Remove Black Sunday's charge attack ... a new attack 'Come
## Here'": a wider rectangle with the charge's reach, quick, dust, everyone in it pulled towards him, harder the further away, never
## quite to him, shown as a jump; "Make him spawn 2 different looks of Straw Man ... The split should be always random. Sometimes
## it's all 1 look and other times it's all the other.").

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var hud = null
var paused := false
var lines: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, c, d, _e, f = 1.2) -> void:
	lines.append({"length": float(c), "dur": float(d), "width": float(f)})
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func rocket_out(_i: int) -> bool:
	return false
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
var max_hp := 100.0
var last_outcome := "hit"
var hits: Array = []
var leaps: Array = []
func take_damage(a: float, f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "from": f, "info": i})
func pull_leap(d: Vector3, dist: float, h: float, s: float) -> bool:
	leaps.append({"dir": d, "dist": dist, "height": h, "secs": s})
	return true
func knock_immune() -> bool:
	return false
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.level = 1


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at: Vector3) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.set("player", hero)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _boss(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("black_sunday", at)
	em.rise_t[i] = 1.0
	em.state[i] = EnemyManager.STATE_MOVE
	em.boss_index = i
	return i


func _row(name: String) -> Dictionary:
	for a in Registry.enemy("black_sunday").boss.get("attacks", []):
		if str((a as Dictionary).get("name", "")) == name:
			return a
	return {}


func _aim_at(em: EnemyManager, b: int, name: String) -> void:
	var list: Array = em.custom_resolved(Registry.enemy("black_sunday"), Registry.enemy("black_sunday").boss.get("attacks", []))
	for k in list.size():
		if str((list[k] as Dictionary).get("name", "")) == name:
			em.atk_i[b] = k
	em.atk_t[b] = 0.0


# ---------------------------------------------------------------- the numbers

func test_he_is_a_quarter_smaller() -> void:
	var d: EnemyDef = Registry.enemy("black_sunday")
	assert_float(d.size).is_equal_approx(5.6 * 0.75, 0.001)
	assert_float(d.radius).is_equal_approx(2.2 * 0.75, 0.001)


func test_the_charge_is_gone_and_come_here_has_its_reach_and_a_wider_mark() -> void:
	assert_bool(_row("roll").is_empty()).is_true()
	var r := _row("come_here")
	assert_str(str(r.get("telegraph", ""))).is_equal("rect")
	# the charge's reach: speed 13.5 x duration 1.1 + its old radius 2.2 m
	assert_float(float(r["length"])).is_equal_approx(13.5 * 1.1 + 2.2, 0.1)
	# a charge's line is 1.2 m wide (Telegraphs.line)
	assert_float(float(r["width"])).is_greater(1.2 * 3.0)
	# quicker than the charge's 1 s wind-up
	assert_float(float(r["windup"])).is_less(1.0)


func test_a_pull_grows_with_distance_and_never_reaches_him() -> void:
	var cfg := BossComeHere.config_of(_row("come_here"))
	var stop := BossComeHere.stop_of(1.65, cfg)
	var last := -1.0
	var d := stop + 0.01
	while d <= float(cfg["length"]):
		var p := BossComeHere.pull_of(d, stop, cfg)
		assert_bool(p >= last - 0.001).override_failure_message("a pull at %.2f m shrank" % d).is_true()
		# never quite to him
		assert_bool(d - p >= stop - 0.001).override_failure_message("a pull at %.2f m came inside %.2f" % [d, stop]).is_true()
		last = p
		d += 0.25
	# inside the stop nothing moves
	assert_float(BossComeHere.pull_of(stop * 0.5, stop, cfg)).is_equal(0.0)
	# the far end is pulled well over twice as hard, as a share of the way too
	var near := BossComeHere.pull_of(float(cfg["length"]) * 0.4, stop, cfg)
	assert_float(last).is_greater(near * 2.0)


func test_inside_is_the_rectangle_drawn() -> void:
	var cfg := BossComeHere.config_of({"length": 10.0, "width": 4.0})
	var axis := Vector3(1, 0, 0)
	assert_bool(BossComeHere.inside(Vector3(5, 0, 1.9), Vector3.ZERO, axis, cfg)).is_true()
	assert_bool(BossComeHere.inside(Vector3(5, 0, 2.1), Vector3.ZERO, axis, cfg)).is_false()
	assert_bool(BossComeHere.inside(Vector3(10.1, 0, 0), Vector3.ZERO, axis, cfg)).is_false()
	assert_bool(BossComeHere.inside(Vector3(-0.1, 0, 0), Vector3.ZERO, axis, cfg)).is_false()


# ---------------------------------------------------------------- the attack in the runner

func test_the_wind_up_draws_the_wide_rectangle_along_his_aim() -> void:
	var w := _world(Vector3(12, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var b := _boss(em, Vector3.ZERO)
	_aim_at(em, b, "come_here")
	(g.lines as Array).clear()
	em._update_attacks(b, DT, em.player.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int((g.lines as Array).size()).is_equal(1)
	var row := _row("come_here")
	assert_float(float(g.lines[0]["width"])).is_equal(float(row["width"]))
	assert_float(float(g.lines[0]["length"])).is_equal(float(row["length"]))
	assert_float(float(g.lines[0]["dur"])).is_equal_approx(float(row["windup"]) / em.pace, 0.001)


func test_the_hero_inside_leaps_towards_him_and_takes_no_harm() -> void:
	var w := _world(Vector3(12, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var b := _boss(em, Vector3.ZERO)
	_aim_at(em, b, "come_here")
	em._update_attacks(b, DT, hero.global_position)
	em.timer[b] = 0.0
	em._update_attacks(b, DT, hero.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_MOVE)
	assert_int((hero.leaps as Array).size()).is_equal(1)
	var leap: Dictionary = hero.leaps[0]
	# along the line to him, short of him
	assert_float((leap["dir"] as Vector3).x).is_less(-0.99)
	assert_float(12.0 - float(leap["dist"])).is_greater_equal(em.radius[b] + 2.0 - 0.001)
	assert_float(float(leap["height"])).is_greater(0.5)
	assert_int((hero.hits as Array).size()).is_equal(0)


func test_the_hero_outside_the_rectangle_is_left_alone() -> void:
	var w := _world(Vector3(12, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var b := _boss(em, Vector3.ZERO)
	em.charge_dir[b] = Vector3(1, 0, 0)
	var off := Vector3(8.0, 0.0, float(_row("come_here")["width"]))
	hero.global_position = off
	BossComeHere.fire(em, b, _row("come_here"), off)
	assert_int((hero.leaps as Array).size()).is_equal(0)


func test_creatures_inside_leap_and_land_nearer_unhurt_those_outside_stay() -> void:
	var w := _world(Vector3(30, 0, 30))
	var em: EnemyManager = w["em"]
	var b := _boss(em, Vector3.ZERO)
	em.charge_dir[b] = Vector3(1, 0, 0)
	var a := em.spawn("straw_man", Vector3(14, 0, 0.5))
	var out := em.spawn("straw_man", Vector3(14, 0, 9.0))
	for i: int in [a, out]:
		em.rise_t[i] = 1.0
		em.state[i] = EnemyManager.STATE_MOVE
	em._rebuild_grid()
	var hp0: float = em.hp[a]
	assert_int(BossComeHere.fire(em, b, _row("come_here"), Vector3(30, 0, 30))).is_equal(1)
	assert_bool(em.is_launched(a)).is_true()
	assert_bool(em.is_launched(out)).is_false()
	var from: Vector3 = em.pos[a]
	var peak := 0.0
	for _k in range(120):
		em._tick_launch(a, DT) if em.is_launched(a) else null
		peak = maxf(peak, em.lift_h[a])
	assert_float(peak).is_greater(0.5)
	var moved := Vector2(from.x - em.pos[a].x, from.z - em.pos[a].z).length()
	var want := BossComeHere.pull_of(Vector2(from.x, from.z).length(), em.radius[b] + 2.0, BossComeHere.config_of(_row("come_here")))
	assert_float(moved).is_equal_approx(want, 0.5)
	assert_float(em.hp[a]).is_equal(hp0)
	assert_bool(em.pos[a].x > em.radius[b]).is_true()


# ---------------------------------------------------------------- the Straw Men's looks

func test_the_ring_names_both_looks_and_they_exist() -> void:
	var looks: Array = _row("spawn_ring").get("looks", [])
	assert_array(looks).contains_exactly(["SM-A", "SM-B"])
	var d: EnemyDef = Registry.enemy("straw_man")
	for code in looks:
		assert_bool(d.variants.has(str(code))).is_true()


func test_the_split_is_random_all_one_all_the_other_and_mixes_in_between() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 127
	var all_a := 0
	var all_b := 0
	var seen := {}
	for _k in range(400):
		var worn := EnemyManager.look_split(14, ["SM-A", "SM-B"], rng)
		assert_int(worn.size()).is_equal(14)
		var a := worn.count("SM-A")
		seen[a] = true
		if a == 14:
			all_a += 1
		elif a == 0:
			all_b += 1
	# about a fifth each way, and many different splits between
	assert_int(all_a).is_between(50, 130)
	assert_int(all_b).is_between(50, 130)
	assert_int(seen.size()).is_greater(10)


func test_a_rings_looks_are_pinned_for_the_stage() -> void:
	var out: Array = []
	RunLooks._brings(Registry, out, {"attacks": [_row("spawn_ring")]}, {})
	assert_bool(out.has(["straw_man", "SM-A"])).is_true()
	assert_bool(out.has(["straw_man", "SM-B"])).is_true()


func test_the_hero_is_pulled_as_a_flight_of_no_landing_of_his_own() -> void:
	var pl: Node = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(pl)
	var landed := [0]
	pl.air_landed.connect(func(_at): landed[0] += 1)
	var flights: int = pl.air_flights
	assert_bool(pl.pull_leap(Vector3(1, 0, 0), 4.0, 1.5, 0.5)).is_true()
	assert_bool(pl.airborne).is_true()
	assert_int(pl.air_flights).is_equal(flights)
	assert_int(pl.pull_leaps).is_equal(1)
	# nothing steers it
	assert_float(pl._air_control).is_equal(0.0)
	# already in the air: no second pull
	assert_bool(pl.pull_leap(Vector3(1, 0, 0), 4.0, 1.5, 0.5)).is_false()
	pl._air_land()
	assert_bool(pl.airborne).is_false()
	assert_int(landed[0]).is_equal(0)
	# a flight of his own still lands as one
	assert_bool(pl.trampoline_launch(Vector3(1, 0, 0), 1.5, 4.0, 0.5, 0.35)).is_true()
	pl._air_land()
	assert_int(landed[0]).is_equal(1)


func test_the_bubble_holds_him() -> void:
	var pl: Node = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(pl)
	pl.shield_t = 1.0
	assert_bool(pl.pull_leap(Vector3(1, 0, 0), 4.0, 1.5, 0.5)).is_false()
	assert_bool(pl.airborne).is_false()


func test_a_flyer_comes_in_the_air_and_a_walker_grows_out_of_the_ground() -> void:
	var w := _world(Vector3(30, 0, 30))
	var em: EnemyManager = w["em"]
	em.spawn_rise_s = 1.0
	assert_bool(Registry.enemy("carrion_crow").flies).is_true()
	var crow := em.spawn("carrion_crow", Vector3(5, 0, 0))
	var man := em.spawn("straw_man", Vector3(-5, 0, 0))
	assert_float(em.rise_t[crow]).is_equal(1.0)
	assert_float(em.rise_t[man]).is_less(1.0)
