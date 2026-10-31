extends GdUnitTestSuite

## Pass 116, lane RESULTS. Endless with a Wanted poster open (Garry: "If Player is playing the Endless Mode and they have
## a Wanted Task to finish this stat increase on enemies is only 33% as effective as it normally is. The moment Player
## manages to complete the task the stat increase picks up from there at a normal regular pace."): the map's
## endless.open_task_growth; WaveDirector.endless_growth_share, Run.endless_growth_steps / endless_growth_seconds. Also
## the Results' bounty sequence (its parts, the reward shown once), the Stranger's icon and the breath's ready sign.

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
	if WantedRun.current and is_instance_valid(WantedRun.current):
		WantedRun.current.queue_free()
	WantedRun.current = null
	Run.last_result = {}


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




func _poster(g: Node) -> WantedRun:
	return WantedRun.begin(g, {"type": "kill_total", "n": 999999, "reward": 120, "name": "Test", "text": "Kill a lot"})


# ---------------------------------------------------------------- Endless with a poster open

func test_the_key_reads_a_third_by_default() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var en := _endless_json()
	var want := float(en.get("open_task_growth", WaveTimeline.ENDLESS_DEFAULTS["open_task_growth"]))
	assert_float(tl.endless_value("open_task_growth")).is_equal_approx(want, 0.0001)
	assert_float(float(WaveTimeline.ENDLESS_DEFAULTS["open_task_growth"])).is_equal_approx(0.33, 0.0001)


func test_whole_steps_match_the_waves() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for w in [1, 2, 5, 12]:
		var a: Dictionary = tl.endless_mults(w, 0)
		var b: Dictionary = tl.endless_mults_steps(float(w - 1), 0)
		for k in ["hp", "atk", "speed"]:
			assert_float(float(b[k])).is_equal_approx(float(a[k]), 0.000001)


func test_growth_with_an_open_poster_is_a_third_then_whole_again() -> void:
	var w := _world()
	var tl: WaveTimeline = Run.map.timeline
	Run.start_stage(0)
	var d := _director(w["g"])
	d.start(Run.map)
	_to_endless(d, 0)
	var every := tl.endless_value("every", 0)
	var share := tl.endless_value("open_task_growth", 0)
	var wr := _poster(w["g"])
	assert_float(d.endless_growth_share()).is_equal_approx(share, 0.0001)
	# six waves with the poster open: a third of six steps
	for i in 6:
		d._tick_endless(every)
	assert_int(Run.endless_wave()).is_equal(7)
	assert_float(Run.endless_growth_steps()).is_equal_approx(6.0 * share, 0.0001)
	var m_open: Dictionary = tl.endless_mults_steps(6.0 * share, 0)
	assert_float(d._endless_speed).is_equal_approx(float(m_open["speed"]), 0.0001)
	# the knock resistance's clock at the same share
	assert_float(Run.endless_growth_seconds()).is_equal_approx(Run.endless_time * share + (Run.endless_time - 6.0 * every) * (1.0 - share), 0.01)
	# done: the next wave adds a whole step, from where it stood (no jump)
	wr.done = true
	assert_float(d.endless_growth_share()).is_equal(1.0)
	var before := Run.endless_growth_steps()
	d._tick_endless(every)
	assert_float(Run.endless_growth_steps()).is_equal_approx(before + 1.0, 0.0001)
	assert_float(Run.endless_growth_steps()).is_less(float(Run.endless_wave() - 1))
	# a failed poster counts as closed too
	wr.done = false
	wr.failed = true
	assert_float(d.endless_growth_share()).is_equal(1.0)
	d.stop()


func test_without_a_poster_the_growth_is_the_waves() -> void:
	var w := _world()
	var tl: WaveTimeline = Run.map.timeline
	Run.start_stage(0)
	var d := _director(w["g"])
	d.start(Run.map)
	_to_endless(d, 0)
	for i in 4:
		d._tick_endless(tl.endless_value("every", 0))
	assert_float(Run.endless_growth_steps()).is_equal_approx(float(Run.endless_wave() - 1), 0.0001)
	assert_float(Run.endless_growth_seconds()).is_equal_approx(Run.endless_time, 0.0001)
	d.stop()


# ---------------------------------------------------------------- the Stranger's icon

func test_the_stranger_and_the_structures_have_painted_icons() -> void:
	var d := StatSources.describe_source("stranger", "The Stranger's cut")
	assert_object(d["icon"]).is_not_null()
	for id in ["hooded_figure", "beacon", "gold_bank", "healing_well", "loot_cache", "shop", "teleport", "uber_magnet"]:
		var sd: StructureDef = Registry.structure(id)
		assert_object(sd).is_not_null()
		var img := sd.icon.get_image()
		# a painting, not the flat placeholder disc (four colours)
		var cols := {}
		for y in range(0, img.get_height(), 8):
			for x in range(0, img.get_width(), 8):
				cols[img.get_pixel(x, y).to_html()] = true
		assert_int(cols.size()).override_failure_message(id + " still has the placeholder icon").is_greater(20)


# ---------------------------------------------------------------- the breath's ready sign

func test_the_ready_sign_plays_and_hides() -> void:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)
	var b := BreathReady.make(holder)
	assert_bool(b.visible).is_false()
	b.play(func(): return Vector3(1, 2, 3))
	assert_bool(b.playing()).is_true()
	assert_bool(b.visible).is_true()
	assert_vector(b.global_position).is_equal_approx(Vector3(1, 2, 3), Vector3.ONE * 0.001)
	b._process(BreathReady.TIME + 0.01)
	assert_bool(b.playing()).is_false()
	assert_bool(b.visible).is_false()


# ---------------------------------------------------------------- the Results' bounty

func _results(rec: Dictionary) -> Control:
	Run.last_result = {"gold_before": 100, "banked": 50, "bounty": rec}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


func test_a_paid_bounty_plays_its_parts_and_counts_into_banked() -> void:
	var r := _results({"name": "T", "text": "t", "have": 60, "need": 60, "done": true, "paid": 240, "reward": 240})
	var names: Array = []
	for p: Dictionary in r._parts:
		names.append(str(p["name"]))
	assert_array(names.slice(0, 4)).is_equal(["gold", "bounty", "bounty_pay", "pop"])
	r.skip_all()
	var v: Dictionary = r.bounty_view()
	assert_str((v["count"] as WText).text).is_equal("60 / 60")
	assert_bool((v["stamp"] as Control).visible).is_true()
	assert_str((v["stamp"] as WStamp).word).is_equal("PAID")
	assert_str((v["coin_num"] as WText).text).is_equal("+240")
	# the Banked count ends at the purse plus the reward, the purse line after it
	assert_str(r._count.text).is_equal("+290")
	assert_str(r._after_line.text).contains("390")


func test_an_unfinished_bounty_shows_its_progress_and_no_pay() -> void:
	var r := _results({"name": "T", "text": "t", "have": 34, "need": 60, "done": false, "paid": 0, "reward": 240})
	var names: Array = []
	for p: Dictionary in r._parts:
		names.append(str(p["name"]))
	assert_bool(names.has("bounty")).is_true()
	assert_bool(names.has("bounty_pay")).is_false()
	r.skip_all()
	var v: Dictionary = r.bounty_view()
	assert_str((v["count"] as WText).text).is_equal("34 / 60")
	assert_str((v["stamp"] as WStamp).word).is_equal("NOT DONE")
	assert_str(r._count.text).is_equal("+50")
