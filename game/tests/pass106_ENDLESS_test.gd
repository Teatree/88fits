extends GdUnitTestSuite

## Pass 106, lane ENDLESS (Garry, 2026-10-25: "Increase the movement speed of enemies more dramatically and also apply
## the speed increase to all the enemies that are already spawned"; "Desert Spider dead animations seems to be below the
## shadow"). Endless's speed grows faster (the map's `endless` speed_growth / speed_max, read off the JSON: Garry tunes
## them) and every new wave's factor reaches the creatures already alive (EnemyManager.set_endless_speed: speed x new /
## old, never twice; a boss, an Elite and an elite-modified creature keep theirs). The spider's death lifts onto its
## shadow (shadow.die_drop < 0) and a negative die_drop holds through the end-of-death sink (EnemyManager.die_sink).

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
var paused := false
var _ended := false
var toasts: Array = []
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var max_hp := 100.0
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
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const FAKE_PICKUPS := """extends Node
var chests: Array = []
var endless_coin_chance := 1.0
func spawn_chest(at: Vector3, boss: bool = false) -> void:
	chests.append({"at": at, "boss": boss})
"""

const FLAT_MAP := """extends MapBase
"""

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const SPIDER_JSON := "res://content/enemies/desert_spider/desert_spider.json"

var _save_keep: Dictionary = {}


func before_test() -> void:
	_save_keep = Save.data.duplicate(true)
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	Run.elapsed = 0.0
	Run.stage = 0
	Run.endless = false
	Run.endless_time = 0.0
	Run.stage_beaten = false
	Run.stage_next = 0
	Save.data = _save_keep


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _endless_json() -> Dictionary:
	return (_json(MAP_JSON).get("timeline_data", {}) as Dictionary).get("endless", {})


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
	var mp := Node3D.new()
	mp.set_script(_script(FLAT_MAP))
	g.add_child(mp)
	g.map = mp
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pk": pk}


func _director(g: Node) -> WaveDirector:
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = g
	g.add_child(d)
	return d


## Stage `s`'s boss down and its countdown run out: Endless with its first wave.
func _to_endless(d: WaveDirector, s: int) -> void:
	var tl: WaveTimeline = Run.map.timeline
	Run.elapsed = tl.stage_end(s)
	d.phase = WaveDirector.Phase.BOSS
	d._on_boss_died(null, Vector3(30, 0, 0))
	d.tick_portal_countdown(tl.portal_seconds(s) + 1.0)


# ---------------------------------------------------------------- the numbers

func test_the_map_plays_a_steeper_speed_ramp_than_pass_103() -> void:
	var en := _endless_json()
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for k: String in ["speed", "speed_growth", "speed_max"]:
		assert_float(tl.endless_value(k)).override_failure_message("endless." + k + ": the .tres is stale against the JSON").is_equal_approx(float(en[k]), 0.0001)
	# more dramatic than pass 103's +1.5% a wave to x1.6 (Garry: "more dramatically")
	assert_float(float(en["speed_growth"])).is_greater(0.015)
	assert_float(float(en["speed_max"])).is_greater(1.6)


func test_the_speed_is_linear_and_never_past_its_cap() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var sp0 := tl.endless_value("speed")
	var g := tl.endless_value("speed_growth")
	var top := tl.endless_value("speed_max")
	var last := 0.0
	var capped := false
	for w in range(1, 120):
		var m := float(tl.endless_mults(w)["speed"])
		assert_float(m).is_less_equal(top + 0.0001)
		assert_float(m).is_greater_equal(last)
		if m < top - 0.0001:
			assert_float(m).is_equal_approx(sp0 * (1.0 + g * float(w - 1)), 0.0001)
		else:
			capped = true
		last = m
	assert_bool(capped).override_failure_message("the ramp never reaches speed_max").is_true()


# ---------------------------------------------------------------- the live speed

func test_live_creatures_speed_up_at_each_wave_and_never_twice() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var tl: WaveTimeline = Run.map.timeline
	Run.start_stage(0)
	var d := _director(w["g"])
	d.start(Run.map)
	assert_float(em.endless_speed_live).is_equal(1.0)
	# alive from before Endless: a regular creature (no speed jitter: the dummy has no variance) and an Elite by its kind
	var a := em.spawn("training_dummy", Vector3(4, 0, 0))
	var e := em.spawn("dune_scorpion", Vector3(-4, 0, 0))
	assert_int(a).is_greater_equal(0)
	assert_int(e).is_greater_equal(0)
	var sa := em.speed[a]
	var se := em.speed[e]
	assert_float(sa).is_greater(0.0)
	_to_endless(d, 0)
	assert_int(d.phase).is_equal(WaveDirector.Phase.ENDLESS)
	var m1 := float(tl.endless_mults(1, 0)["speed"])
	assert_float(em.endless_speed_live).is_equal_approx(m1, 0.0001)
	# the creature from before Endless walks at wave 1's speed now; the Elite keeps its own
	assert_float(em.speed[a]).is_equal_approx(sa * m1, 0.0001)
	assert_float(em.speed[e]).is_equal_approx(se, 0.0001)
	# the next wave: the same creature at wave 2's speed (its base x the new factor, not x both)
	d._tick_endless(tl.endless_value("every", 0))
	assert_int(Run.endless_wave()).is_equal(2)
	var m2 := float(tl.endless_mults(2, 0)["speed"])
	assert_float(m2).is_greater(m1)
	assert_float(em.speed[a]).is_equal_approx(sa * m2, 0.0001)
	assert_float(em.e_speed[a]).is_equal_approx(m2, 0.0001)
	# never twice: the same factor again changes nothing
	assert_int(em.set_endless_speed(m2)).is_equal(0)
	assert_float(em.speed[a]).is_equal_approx(sa * m2, 0.0001)
	# a new spawn in wave 2 walks exactly as fast as the old one (the factor rides in stage_speed_mult)
	var b := em.spawn("training_dummy", Vector3(0, 0, 4))
	assert_float(em.speed[b]).is_equal_approx(em.speed[a], 0.0001)
	assert_float(em.e_speed[b]).is_equal_approx(m2, 0.0001)
	assert_float(em.speed[e]).is_equal_approx(se, 0.0001)
	d.stop()


func test_the_live_speed_holds_at_the_cap_far_into_endless() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var tl: WaveTimeline = Run.map.timeline
	Run.start_stage(0)
	var d := _director(w["g"])
	d.start(Run.map)
	var a := em.spawn("training_dummy", Vector3(4, 0, 0))
	var sa := em.speed[a]
	_to_endless(d, 0)
	# ten minutes of Endless in one tick: wave 61, far past the cap
	d._tick_endless(600.0)
	assert_int(Run.endless_wave()).is_equal(tl.endless_wave_at(600.0, 0))
	var top := maxf(tl.endless_value("speed_max", 0), tl.endless_value("speed", 0))
	assert_float(em.endless_speed_live).is_equal_approx(top, 0.0001)
	if em.is_alive(a):
		assert_float(em.speed[a]).is_equal_approx(sa * top, 0.0001)
	d.stop()


func test_a_fresh_run_carries_no_endless_speed() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.endless_speed_live = 2.0
	Run.start_stage(0)
	var d := _director(w["g"])
	d.start(Run.map)
	assert_float(em.endless_speed_live).is_equal(1.0)
	var a := em.spawn("training_dummy", Vector3(4, 0, 0))
	assert_float(em.e_speed[a]).is_equal(1.0)
	d.stop()


# ---------------------------------------------------------------- the spider's death on its shadow

func test_the_spider_lifts_its_death_onto_its_shadow() -> void:
	var sh: Dictionary = _json(SPIDER_JSON).get("shadow", {})
	# its shadow sits up the screen (up > 0); the death painting is lifted (die_drop < 0), within the clamp
	assert_float(float(sh.get("up", 0.0))).is_greater(0.0)
	assert_float(float(sh.get("die_drop", 0.0))).is_less(0.0)
	assert_float(float(sh.get("die_drop", 0.0))).is_greater_equal(-0.5)
	assert_float(EnemyManager.die_drop_of(Registry.enemy("desert_spider"))).is_equal_approx(float(sh["die_drop"]), 0.0001)


func test_a_negative_die_drop_holds_through_the_sink_a_positive_one_does_not() -> void:
	var em: EnemyManager = auto_free(EnemyManager.new())
	add_child(em)
	var up := Vector3.UP
	var ts := em.register_type(Registry.enemy("desert_spider"))
	var tg := em.register_type(Registry.enemy("red_goblin"))
	em.type_idx[0] = ts
	em.size[0] = 1.0
	em.type_idx[1] = tg
	em.size[1] = 1.0
	var dd := EnemyManager.die_drop_of(Registry.enemy("desert_spider"))
	# lifted (down the billboard by a negative share = up), eased in, and the same whatever the squash
	assert_vector(em.die_sink(0, 0.0, 1.0, up)).is_equal(Vector3.ZERO)
	assert_float(em.die_sink(0, 1.0, 1.0, up).y).is_equal_approx(dd, 0.0001)
	assert_float(em.die_sink(0, 1.0, 0.02, up).y).is_equal_approx(dd, 0.0001)
	assert_float(em.die_sink(0, 0.5, 0.3, up).y).is_equal_approx(dd * 0.5, 0.0001)
	# the Red Goblin's positive sink still shrinks with the squash (pass 88)
	var gd := EnemyManager.die_drop_of(Registry.enemy("red_goblin"))
	assert_float(gd).is_greater(0.0)
	assert_float(em.die_sink(1, 1.0, 1.0, up).y).is_equal_approx(gd, 0.0001)
	assert_float(em.die_sink(1, 1.0, 0.5, up).y).is_equal_approx(gd * 0.5, 0.0001)
