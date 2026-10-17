extends GdUnitTestSuite

## Pass 87, lane SGAME (Garry, 2026-10-17: "Now Player Unlocks Stages and is only able to enter them after having
## completed the previous one. They differ in how long it takes to complete them as well ... Player kills the boss and
## the Portal that appears shows a 1 minute timer before the Endless Mode will activate. There is only an Extract button
## now in the Portal"; his answers: a stage picked from the menu is a fresh run, lengths 7:10 / 10:00 / 13:00, a death in
## Endless banks everything). The map keeps one timeline; each stage is a window of it (WaveTimeline.stage_list); a run
## plays one stage from its window's start (Run.start_stage) to its boss; the boss's death opens the portal and its
## countdown; Endless when it runs out (waves every `every` s, compounding); Save.stages_beaten unlocks the next stage.

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


func _tl() -> WaveTimeline:
	return Registry.map("red_canyon").timeline


func _json() -> Dictionary:
	var f := FileAccess.open("res://content/maps/red_canyon/red_canyon.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## A timeline built by hand without a stage_list (the pre-87 maps): 3 stages of 300 s, bosses at their ends.
func _old_tl() -> WaveTimeline:
	var tl := WaveTimeline.new()
	tl.stage_length = 300.0
	tl.stages = 3
	tl.stage_mults = [1.0, 2.0, 3.0]
	tl.events = [{"t": 150, "type": "elite_boss", "enemy": "dune_scorpion"}, {"t": 300, "type": "boss", "enemy": "tumbleweed_king"},
		{"t": 600, "type": "boss", "enemy": "gila_grande"}, {"t": 900, "type": "boss", "enemy": "brander"}]
	return tl


# ---------------------------------------------------------------- the windows

func test_red_canyon_has_its_stages_as_windows_of_one_timeline() -> void:
	var tl := _tl()
	var raw: Array = _json()["timeline_data"]["stage_list"]
	assert_int(tl.stage_count()).is_equal(raw.size())
	assert_int(tl.stage_count()).is_greater_equal(3)
	# each window starts where the one before ends, as long as its `length` (read from the file: Garry edits them)
	var t := 0.0
	for k in range(tl.stage_count()):
		assert_float(tl.stage_start(k)).is_equal_approx(t, 0.001)
		assert_float(tl.stage_len(k)).is_equal_approx(float(raw[k]["length"]), 0.001)
		assert_float(tl.stage_end(k)).is_equal_approx(t + float(raw[k]["length"]), 0.001)
		assert_vector(tl.stage_window(k)).is_equal(Vector2(tl.stage_start(k), tl.stage_end(k)))
		t += float(raw[k]["length"])
		# a boundary second belongs to the stage it starts, the last second before it to the stage it ends
		assert_int(tl.stage_at(tl.stage_start(k))).is_equal(k)
		assert_int(tl.stage_at(tl.stage_end(k) - 0.5)).is_equal(k)
		# a boss closes every stage, and a boss event sits on its window's end
		var boss := tl.stage_boss(k)
		assert_object(Registry.enemy(boss)).override_failure_message("stage %d boss %s" % [k + 1, boss]).is_not_null()
		var on_end := false
		for ev in tl.events:
			if str(ev.get("type", "")) == "boss" and absf(float(ev.get("t", 0.0)) - tl.stage_end(k)) < 0.5:
				on_end = true
		assert_bool(on_end).override_failure_message("no boss event at stage %d's end" % (k + 1)).is_true()
	assert_float(tl.total_length()).is_equal_approx(t, 0.001)
	assert_int(tl.stage_at(t + 500.0)).is_equal(tl.stage_count() - 1)
	# Garry's lengths (2026-10-17): 7:10, 10:00, 13:00, the Tumbleweed King, the Gila Grande and the Brander
	assert_float(tl.stage_len(0)).is_equal(430.0)
	assert_str(tl.stage_boss(0)).is_equal("tumbleweed_king")
	assert_str(tl.stage_boss(1)).is_equal("gila_grande")
	assert_str(tl.stage_boss(2)).is_equal("brander")
	# stage 3 is hell; every stage has a name, a line and words for the Stages menu
	assert_bool(tl.stage_hell(2)).is_true()
	assert_bool(tl.stage_hell(0)).is_false()
	for k in range(tl.stage_count()):
		var e := tl.stage_entry(k)
		for key: String in ["index", "id", "name", "length", "boss", "description", "difficulty", "filter", "hell", "shot", "start", "end"]:
			assert_bool(e.has(key)).override_failure_message("stage %d entry has no %s" % [k + 1, key]).is_true()
		assert_str(str(e["name"])).is_not_empty()
		assert_str(str(e["difficulty"])).is_not_empty()
		assert_str(str(e["description"])).is_not_empty()


func test_a_map_without_a_stage_list_keeps_its_old_windows() -> void:
	var tl := _old_tl()
	assert_int(tl.stage_count()).is_equal(3)
	assert_vector(tl.stage_window(0)).is_equal(Vector2(0, 300))
	assert_vector(tl.stage_window(1)).is_equal(Vector2(300, 600))
	assert_vector(tl.stage_window(2)).is_equal(Vector2(600, 900))
	# indices outside clamp into the stages
	assert_vector(tl.stage_window(7)).is_equal(Vector2(600, 900))
	assert_vector(tl.stage_window(-2)).is_equal(Vector2(0, 300))
	assert_int(tl.stage_at(299.9)).is_equal(0)
	assert_int(tl.stage_at(300.0)).is_equal(1)
	assert_int(tl.stage_at(5000.0)).is_equal(2)
	assert_str(tl.stage_name(1)).is_equal("Stage 2")
	assert_str(tl.stage_id(2)).is_equal("s3")
	# the boss is the boss event on the window's end (never the Elite in the middle)
	assert_str(tl.stage_boss(0)).is_equal("tumbleweed_king")
	assert_str(tl.stage_boss(2)).is_equal("brander")
	# hell from stage 3 on, no filter
	assert_bool(tl.stage_hell(1)).is_false()
	assert_bool(tl.stage_hell(2)).is_true()
	assert_float(float(tl.stage_filter(1)["strength"])).is_equal(0.0)
	# the portal's countdown and Endless play the defaults
	assert_float(tl.portal_seconds(0)).is_equal(60.0)
	assert_float(tl.endless_value("every")).is_equal(10.0)


func test_a_stage_entry_names_its_own_boss_filter_and_endless() -> void:
	var tl := _old_tl()
	tl.stage_list = [{"id": "a", "name": "First", "length": 100},
		{"id": "b", "name": "Second", "length": 200, "boss": "gila_grande", "filter": {"color": "#3050a0", "strength": 0.4},
			"endless": {"hp_growth": 0.5, "portal_seconds": 20}}]
	tl.endless = {"hp_growth": 0.2}
	assert_int(tl.stage_count()).is_equal(2)
	assert_vector(tl.stage_window(1)).is_equal(Vector2(100, 300))
	# stage 1 names no boss: the boss event at its end, else the last inside its window, else none
	assert_str(tl.stage_boss(0)).is_equal("")
	assert_str(tl.stage_boss(1)).is_equal("gila_grande")
	var f := tl.stage_filter(1)
	assert_bool((f["color"] as Color).is_equal_approx(Color.html("#3050a0"))).is_true()
	assert_float(float(f["strength"])).is_equal_approx(0.4, 0.0001)
	assert_str(str(tl.stage_entry(1)["filter"]["color"])).is_equal("#3050a0")
	# the stage's own Endless key, then the map's, then the default
	assert_float(tl.endless_value("hp_growth", 1)).is_equal(0.5)
	assert_float(tl.endless_value("hp_growth", 0)).is_equal(0.2)
	assert_float(tl.endless_value("atk_growth", 1)).is_equal(float(WaveTimeline.ENDLESS_DEFAULTS["atk_growth"]))
	assert_float(tl.portal_seconds(1)).is_equal(20.0)
	assert_float(tl.portal_seconds(0)).is_equal(60.0)


func test_endless_waves_grow_compounding_and_a_little_faster() -> void:
	var tl := _old_tl()
	tl.endless = {"hp": 1.5, "atk": 1.2, "speed": 1.1, "hp_growth": 0.2, "atk_growth": 0.1, "speed_growth": 0.05,
		"speed_max": 1.3, "every": 10, "first_wave": 150, "wave_size": 30, "wave_growth": 3}
	var m1 := tl.endless_mults(1)
	var m2 := tl.endless_mults(2)
	var m5 := tl.endless_mults(5)
	assert_float(float(m1["hp"])).is_equal_approx(1.5, 0.0001)
	assert_float(float(m2["hp"])).is_equal_approx(1.5 * 1.2, 0.0001)
	assert_float(float(m5["hp"])).is_equal_approx(1.5 * pow(1.2, 4), 0.0001)
	assert_float(float(m5["atk"])).is_equal_approx(1.2 * pow(1.1, 4), 0.0001)
	# speed: linear, never past speed_max
	assert_float(float(m2["speed"])).is_equal_approx(1.1 * 1.05, 0.0001)
	assert_float(float(tl.endless_mults(40)["speed"])).is_equal_approx(1.3, 0.0001)
	# the huge first wave, then wave_size + wave_growth x (k - 2)
	assert_int(tl.endless_wave_size(1)).is_equal(150)
	assert_int(tl.endless_wave_size(2)).is_equal(30)
	assert_int(tl.endless_wave_size(4)).is_equal(36)
	# a wave every 10 s of Endless
	assert_int(tl.endless_wave_at(0.0)).is_equal(1)
	assert_int(tl.endless_wave_at(9.9)).is_equal(1)
	assert_int(tl.endless_wave_at(10.0)).is_equal(2)
	assert_int(tl.endless_wave_at(35.0)).is_equal(4)


# ---------------------------------------------------------------- a stage run

func test_a_stage_run_is_a_fresh_run_at_its_window() -> void:
	var tl := _tl()
	Run.start_stage(1)
	assert_int(Run.stage).is_equal(1)
	assert_int(Run.stage_index).is_equal(1)
	assert_float(Run.elapsed).is_equal_approx(tl.stage_start(1), 0.001)
	assert_float(Run.stage_clock()).is_equal(0.0)
	assert_float(Run.run_time()).is_equal(0.0)
	assert_float(Run.stage_length_now()).is_equal_approx(tl.stage_len(1), 0.001)
	assert_int(Run.level).is_equal(1)
	assert_int(Run.path_slot).is_equal(0)
	assert_bool(Run.endless).is_false()
	Run.elapsed += 65.0
	Run.held_time += 20.0
	assert_float(Run.stage_clock()).is_equal_approx(65.0, 0.001)
	assert_float(Run.run_time()).is_equal_approx(85.0, 0.001)
	# a stage past the map's last plays the last; Endless's numbers and the run's end are read off it
	Run.start_stage(9)
	assert_int(Run.stage).is_equal(tl.stage_count() - 1)
	assert_str(Run.outcome()).is_equal("died")
	Run.stage_beaten = true
	assert_str(Run.outcome()).is_equal("died_after_boss")
	Run.endless = true
	assert_str(Run.outcome()).is_equal("died_endless")
	Run.extracted = true
	assert_str(Run.outcome()).is_equal("extracted")
	Run.extracted = false
	# the Stages menu's choice waits for the next run (Game reads it and puts it back to 0)
	Run.choose_stage(2)
	assert_int(Run.stage_next).is_equal(2)
	Run.choose_stage(-3)
	assert_int(Run.stage_next).is_equal(0)


# ---------------------------------------------------------------- unlocks

func test_a_stage_unlocks_once_the_one_before_is_beaten() -> void:
	assert_bool(Save.stage_unlocked("red_canyon", 0)).is_true()
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_false()
	assert_bool(Save.stages_menu_open("red_canyon")).is_false()
	Save.mark_stage_beaten("red_canyon", 0)
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_true()
	assert_bool(Save.stage_unlocked("red_canyon", 2)).is_false()
	assert_bool(Save.stages_menu_open("red_canyon")).is_true()
	Save.mark_stage_beaten("red_canyon", 1)
	assert_bool(Save.stage_unlocked("red_canyon", 2)).is_true()
	assert_array(Save.stages_beaten("red_canyon")).is_equal([true, true])
	# another map knows nothing of it
	assert_bool(Save.stage_unlocked("other_map", 1)).is_false()
	Save.forget_stages("red_canyon")
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_false()


func test_an_old_save_keeps_the_stages_its_bosses_prove() -> void:
	# the King's stage flag (marked as a stage's boss died since pass 30) and a Gila kill in the totals: stages 1 and 2
	Save.data = Save._default()
	Save.data["once"] = ["boss_red_canyon_1"]
	Save.data["totals"]["kills_of_enemy"] = {"gila_grande": 2, "skeleton": 900}
	Save._migrate_stages()
	assert_bool(Save.stage_beaten("red_canyon", 0)).is_true()
	assert_bool(Save.stage_beaten("red_canyon", 1)).is_true()
	assert_bool(Save.stage_beaten("red_canyon", 2)).is_false()
	assert_bool(Save.stage_unlocked("red_canyon", 2)).is_true()
	assert_bool(Save.once("stages_migrated")).is_true()
	# once only: what is forgotten afterwards stays forgotten
	Save.forget_stages()
	Save._migrate_stages()
	assert_bool(Save.stage_beaten("red_canyon", 0)).is_false()
	# a new save beats nothing
	Save.data = Save._default()
	Save._migrate_stages()
	assert_array(Save.stages_beaten("red_canyon")).is_empty()


# ---------------------------------------------------------------- the director: window, boss, portal, Endless

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


func test_a_stage_run_skips_what_came_before_its_window() -> void:
	var w := _world()
	var tl := _tl()
	Run.start_stage(1)
	var d := _director(w["g"])
	d.start(Run.map)
	var w0 := tl.stage_start(1)
	for e: Dictionary in d._run_events:
		var t := float(e.get("t", 0.0))
		if t < w0 or (t == w0 and str(e.get("type", "")) == "boss"):
			assert_bool(bool(e.get("_skip", false))).override_failure_message("event at %.0f still due" % t).is_true()
	# the stage before's boss (on the window's start) never comes: the next boss is this stage's, at its end
	assert_float(d.next_boss_in()).is_equal_approx(tl.stage_end(1) - Run.elapsed, 0.01)
	d._process_events()
	assert_int(d.phase).is_equal(WaveDirector.Phase.NORMAL)
	assert_int(w["em"].boss_index).is_equal(-1)
	d.stop()


func test_the_clock_stops_at_the_window_end_with_the_stage_boss() -> void:
	var w := _world()
	var tl := _tl()
	Run.start_stage(0)
	var d := _director(w["g"])
	d.start(Run.map)
	d.skip_events_before(tl.stage_end(0) - 1.0)
	Run.elapsed = tl.stage_end(0) - 0.05
	d._process(0.5)
	assert_float(Run.elapsed).is_equal_approx(tl.stage_end(0), 0.0001)
	assert_int(d.phase).is_equal(WaveDirector.Phase.BOSS)
	assert_float(d.next_boss_in()).is_equal(-1.0)
	d.stop()


func test_a_window_without_a_boss_event_brings_the_stage_boss() -> void:
	var w := _world()
	var keep: WaveTimeline = Run.map.timeline
	var tl: WaveTimeline = keep.duplicate(true) as WaveTimeline
	tl.events = (tl.events as Array).filter(func(e) -> bool: return str(e.get("type", "")) != "boss")
	Run.map.timeline = tl
	Run.start_stage(0)
	var d := _director(w["g"])
	d.start(Run.map)
	d.skip_events_before(tl.stage_end(0) - 1.0)
	Run.elapsed = tl.stage_end(0) - 0.05
	d._process(0.5)
	assert_int(d.phase).is_equal(WaveDirector.Phase.BOSS)
	var em: EnemyManager = w["em"]
	assert_int(em.boss_index).is_greater_equal(0)
	assert_str((em.types[em.type_idx[em.boss_index]]["def"] as EnemyDef).id).is_equal(tl.stage_boss(0))
	d.stop()
	# (Run.map is the Registry's map itself: its own timeline goes back)
	Run.map.timeline = keep


func test_the_boss_down_opens_a_countdown_then_endless_waves_grow() -> void:
	var w := _world()
	var tl := _tl()
	var em: EnemyManager = w["em"]
	Run.start_stage(1)
	var d := _director(w["g"])
	d.start(Run.map)
	Run.elapsed = tl.stage_end(1)
	d.phase = WaveDirector.Phase.BOSS
	d._on_boss_died(null, Vector3(3, 0, 0))
	# the stage is beaten (stage 3 unlocks) and the countdown runs
	assert_int(d.phase).is_equal(WaveDirector.Phase.PORTAL)
	assert_bool(Run.stage_beaten).is_true()
	assert_bool(Save.stage_beaten("red_canyon", 1)).is_true()
	assert_bool(Save.stage_unlocked("red_canyon", 2)).is_true()
	assert_float(d.portal_seconds_left()).is_equal_approx(tl.portal_seconds(1), 0.001)
	assert_float(d.next_boss_in()).is_equal(-1.0)
	assert_float(d.xp_share()).is_equal(1.0)
	d.tick_portal_countdown(tl.portal_seconds(1) - 0.5)
	assert_int(d.phase).is_equal(WaveDirector.Phase.PORTAL)
	assert_float(d.portal_seconds_left()).is_equal_approx(0.5, 0.001)
	em.kill_all(false)
	var started := [0]
	d.endless_started.connect(func(): started[0] += 1)
	d.tick_portal_countdown(1.0)
	# Endless: the countdown is gone, the first wave came at once (a huge one, the hard cap holding), XP and coins cut
	assert_int(started[0]).is_equal(1)
	assert_int(d.phase).is_equal(WaveDirector.Phase.ENDLESS)
	assert_bool(Run.endless).is_true()
	assert_float(d.portal_seconds_left()).is_equal(-1.0)
	assert_int(Run.endless_wave()).is_equal(1)
	assert_int(em.alive_count()).is_equal(mini(tl.endless_wave_size(1, 1), tl.hard_cap))
	assert_float(d.xp_share()).is_equal_approx(tl.endless_value("xp_share", 1), 0.0001)
	assert_float(float(w["pk"].endless_coin_chance)).is_equal_approx(tl.endless_value("coin_chance", 1), 0.0001)
	# the pool is the stage's late roster (its last roster_window seconds), not a later stage's creature
	assert_bool(d._endless_pool.is_empty()).is_false()
	for p: Dictionary in d._endless_pool:
		var r: Dictionary = p["row"]
		assert_float(float(r.get("t", 0.0))).is_less(tl.stage_end(1))
	# the wave's numbers: the row's own times the Endless multiplier (hp, atk)
	var k1 := ""
	for k: String in d._src.keys():
		if k.ends_with("@w1"):
			k1 = k
	assert_str(k1).is_not_empty()
	var base := d.fixed_numbers(0.0, {})
	var s1: Dictionary = d._src[k1]
	assert_float(float(s1["endless_wave"])).is_equal(1.0)
	# every `every` seconds the next wave, tougher (compounding) and a little faster
	var waves := [0]
	d.endless_wave_started.connect(func(_w): waves[0] += 1)
	em.kill_all(false)
	d._tick_endless(tl.endless_value("every", 1))
	assert_int(Run.endless_wave()).is_equal(2)
	assert_int(waves[0]).is_equal(1)
	assert_int(em.alive_count()).is_greater(0)
	var w2 := 0
	for k: String in d._src.keys():
		if k.ends_with("@w2"):
			w2 += 1
	assert_int(w2).override_failure_message("no wave-2 numbers").is_greater(0)
	# a source's numbers in wave 2: its own fixed numbers x wave 2's multipliers (hp_growth, atk_growth compounding)
	var own := d.fixed_numbers(100.0, {})
	var s2 := d.source_for("probe", 100.0, {})
	var m2 := tl.endless_mults(2, 1)
	assert_float(float(s2["hp_time"])).is_equal_approx(float(own["hp_time"]) * float(m2["hp"]), 0.001)
	assert_float(float(s2["dmg_time"])).is_equal_approx(float(own["dmg_time"]) * float(m2["atk"]), 0.001)
	assert_float(float(m2["hp"])).is_equal_approx(float(tl.endless_mults(1, 1)["hp"]) * (1.0 + tl.endless_value("hp_growth", 1)), 0.0001)
	assert_float(float(s1["hp_time"])).is_greater(0.0)
	assert_float(float(em.stage_speed_mult)).is_equal_approx(tl.speed_mult(1) * float(tl.endless_mults(2, 1)["speed"]), 0.0001)
	assert_float(float(base["hp_time"])).is_greater(0.0)
	# Endless keeps its crowd up to its cap between the waves, and the run's clock stands at the window's end
	em.kill_all(false)
	d._endless_fill()
	assert_int(em.alive_count()).is_greater(0)
	assert_float(Run.elapsed).is_equal_approx(tl.stage_end(1), 0.001)
	assert_int(d.current_cap()).is_equal(int(float(tl.cap_at(Run.elapsed, 1)) * tl.endless_value("cap", 1)))
	d.stop()
