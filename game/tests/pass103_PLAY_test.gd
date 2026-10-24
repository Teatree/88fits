extends GdUnitTestSuite

## Pass 103, lane PLAY (Garry, 2026-10-24: "Ramp up the difficulty scaling, and make it so the enemies get more and more
## knockback resistance with each minute (by minute 1.5 enemies don't have any knockback from not explosive weapons at
## all) ... Reduce the knockback from fire breath a bit. Reduce damage from powder keg by to 1/3"): Endless's steeper
## growth (the map's `endless` block), its knock resistance (WaveTimeline.endless_knock_resist,
## EnemyManager.endless_knock_share: a revolver hit resisted, a blast whole), Backdraft's and the Fire Eater's lighter
## shove, Powder Keg's third of the damage. Map numbers are read off the map's JSON (Garry tunes them).

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
var hits := 0
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	hits += 1
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_fire(_a, _b = 1.0, _c = false) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var still_unhit := 0.0
func forward() -> Vector3:
	return Vector3(-sin(facing), 0, -cos(facing))
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0)
func face_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 1.45, 0) + d.normalized() * 0.3
func still_unhit_seconds() -> float:
	return still_unhit
"""

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const KB := 10.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _endless_json() -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON))
	return (d["timeline_data"] as Dictionary)["endless"]


func _world() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.player_sheet.set_base("crit_chance", 0.0)
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
	em.screen_filter_on = false
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em.hero_knockback_override = 1.0
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func after_test() -> void:
	_dummy = -1
	Run.endless = false
	Run.endless_time = 0.0


func _creature(em: EnemyManager, at: Vector3, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	if em.rise_t.size() > i:
		em.rise_t[i] = 1.0
	em._rebuild_grid()
	return i


## The push a hit from `src` (with `flags`) gives the world's one test creature (spawned once: sizes vary) `t` seconds
## into Endless (t < 0: outside Endless).
var _dummy := -1


func _push(em: EnemyManager, src: String, t: float, flags := 0) -> float:
	Run.endless = t >= 0.0
	Run.endless_time = maxf(t, 0.0)
	if _dummy < 0 or em.alive[_dummy] == 0:
		_dummy = _creature(em, Vector3(0, 0, -3))
	var i := _dummy
	em.pos[i] = Vector3(0, 0, -3)
	em.kb[i] = Vector3.ZERO
	em.damage(i, 0.01, src, Vector3(0, 0, -1), KB, false, false, flags)
	var n := em.kb[i].length()
	em.kb[i] = Vector3.ZERO
	return n


# ---------------------------------------------------------------- the map's numbers

func test_the_map_plays_its_json_endless_block_steeper_than_pass_102() -> void:
	var en := _endless_json()
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for k: String in ["hp", "atk", "hp_growth", "atk_growth", "speed", "speed_growth", "speed_max", "knock_resist_seconds", "knock_resist_max"]:
		assert_float(tl.endless_value(k)).override_failure_message("endless." + k + ": the .tres is stale against the JSON").is_equal_approx(float(en[k]), 0.0001)
	# pass 103 ramps harder than pass 102's x1.11 / x1.07 a wave (Garry: "Ramp up the difficulty scaling")
	assert_float(float(en["hp_growth"])).is_greater(0.11)
	assert_float(float(en["atk_growth"])).is_greater(0.07)
	assert_str(tl.endless_knock_exempt_tag()).is_equal(str(en.get("knock_resist_exempt_tag", "explosive")))
	for s: String in ["nuke", "revive", "powder_keg"]:
		assert_bool(tl.endless_knock_exempt_sources().has(s)).is_true()
	# a wave a minute in compounds its growth: wave 7 = hp x (1 + growth)^6
	var m7: Dictionary = tl.endless_mults(7)
	assert_float(float(m7["hp"])).is_equal_approx(float(en["hp"]) * pow(1.0 + float(en["hp_growth"]), 6.0), 0.0001)
	assert_float(float(m7["atk"])).is_equal_approx(float(en["atk"]) * pow(1.0 + float(en["atk_growth"]), 6.0), 0.0001)


func test_the_ramp_is_linear_to_its_most_and_holds_and_is_off_by_default() -> void:
	var tl := WaveTimeline.new()
	# a map that names neither key: no resistance, as before pass 103
	assert_float(tl.endless_knock_resist(0.0)).is_equal(0.0)
	assert_float(tl.endless_knock_resist(600.0)).is_equal(0.0)
	# Garry's ask: nothing at the start, all of it at 1:30, held after
	tl.endless = {"knock_resist_seconds": 90, "knock_resist_max": 1.0}
	assert_float(tl.endless_knock_resist(0.0)).is_equal_approx(0.0, 0.0001)
	assert_float(tl.endless_knock_resist(45.0)).is_equal_approx(0.5, 0.0001)
	assert_float(tl.endless_knock_resist(90.0)).is_equal_approx(1.0, 0.0001)
	assert_float(tl.endless_knock_resist(120.0)).is_equal_approx(1.0, 0.0001)
	# a lower most and a comma-separated sources string (the Level Editor's text field)
	tl.endless = {"knock_resist_seconds": 60, "knock_resist_max": 0.8, "knock_resist_exempt_sources": "nuke, revive"}
	assert_float(tl.endless_knock_resist(30.0)).is_equal_approx(0.4, 0.0001)
	assert_float(tl.endless_knock_resist(90.0)).is_equal_approx(0.8, 0.0001)
	assert_array(Array(tl.endless_knock_exempt_sources())).is_equal(["nuke", "revive"])
	# a stage's own block wins key by key
	tl.stage_list = [{"id": "a", "length": 100}, {"id": "b", "length": 100, "endless": {"knock_resist_max": 0.5}}]
	assert_float(tl.endless_knock_resist(600.0, 1)).is_equal_approx(0.5, 0.0001)
	assert_float(tl.endless_knock_resist(600.0, 0)).is_equal_approx(0.8, 0.0001)


# ---------------------------------------------------------------- the pushes in Endless

func test_a_revolver_hit_is_resisted_more_each_second_and_a_blast_never() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var en := _endless_json()
	var secs := float(en["knock_resist_seconds"])
	var mx := clampf(float(en["knock_resist_max"]), 0.0, 1.0)
	var base_rev := _push(em, "revolver", -1.0)
	var base_dyn := _push(em, "lob_grenade", -1.0)
	assert_float(base_rev).is_greater(0.1)
	assert_float(base_dyn).is_equal_approx(base_rev, 0.001)
	for t: float in [0.0, 45.0, 90.0, 120.0]:
		var want := 1.0 - mx * clampf(t / secs, 0.0, 1.0)
		assert_float(_push(em, "revolver", t)).override_failure_message("revolver at %s s" % t).is_equal_approx(base_rev * want, 0.001)
		# explosive: the tagged dynamite, the nuke, Powder Keg, a HIT_BLAST hit without a source
		assert_float(_push(em, "lob_grenade", t)).is_equal_approx(base_dyn, 0.001)
		assert_float(_push(em, "nuke", t)).is_equal_approx(base_rev, 0.001)
		assert_float(_push(em, "powder_keg", t)).is_equal_approx(base_rev, 0.001)
		assert_float(_push(em, "", t, EnemyManager.HIT_BLAST)).is_equal_approx(base_rev, 0.001)
		# not explosive: the Molotov's bottle, a sourceless push (thorns)
		assert_float(_push(em, "molotov", t)).is_equal_approx(base_rev * want, 0.001)
		assert_float(_push(em, "", t)).is_equal_approx(base_rev * want, 0.001)
	# Garry's line on Red Canyon: at 1:30 a non-explosive weapon does not push at all
	if mx >= 1.0 and secs <= 90.0:
		assert_float(_push(em, "revolver", 90.0)).is_equal(0.0)
	# outside Endless the clock does not count
	Run.endless = false
	Run.endless_time = 500.0
	assert_float(em.endless_knock_resist()).is_equal(0.0)


func test_the_explosive_tag_is_on_the_blasting_families() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for id: String in ["lob_grenade", "cluster_bomb", "golden_pineapple", "rocket_pod", "hellfire_battery", "missile_massacre", "land_mine", "minefield", "jackrabbit_mines"]:
		assert_object(Registry.weapon(id)).override_failure_message("no weapon " + id).is_not_null()
		assert_bool(Registry.weapon(id).tags.has("explosive")).override_failure_message(id + " is not tagged explosive").is_true()
		assert_bool(em.knock_is_explosive(id)).is_true()
	for id: String in ["revolver", "tommy_gun", "boomstick", "molotov", "skull_rain", "dragons_breath", "hammer", "guitarra", "basketball", "frisbee", "gravity_gun", "hornet_nest"]:
		assert_bool(em.knock_is_explosive(id)).override_failure_message(id + " counted as explosive").is_false()


func test_a_hero_throw_names_its_source() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	Run.endless = true
	Run.endless_time = 1000.0
	em.endless_knock_override = 1.0
	var a := _creature(em, Vector3(0, 0, -2))
	assert_int(em.hero_throw_radius(Vector3.ZERO, 4.0, 16.0)).is_equal(0)
	assert_float(em.kb[a].length()).is_equal(0.0)
	assert_int(em.hero_throw_radius(Vector3.ZERO, 4.0, 16.0, -1, "nuke")).is_greater(0)
	assert_float(em.kb[a].length()).is_greater(0.1)
	em.endless_knock_override = -1.0


# ---------------------------------------------------------------- fire breath and Powder Keg

func test_backdraft_shoves_about_a_third_less() -> void:
	var bd: MutationDef = Registry.mutation("backdraft")
	var knock := float(((bd.params as Dictionary)["breath"] as Dictionary)["knock"])
	assert_float(knock).is_equal_approx(3.3, 0.001)
	var fe: WeaponDef = Registry.weapon("fire_eater")
	var fk := float((((fe.params as Dictionary)["final"] as Dictionary)["breath"] as Dictionary)["knock"])
	assert_float(fk).is_equal_approx(4.7, 0.001)
	# the shove a breath tick gives is that knock (damage()'s kb_force): 0.66 of pass 95's 5.0
	var w := _world()
	var em: EnemyManager = w["em"]
	var inst := WeaponInstance.new(Registry.weapon("dragons_breath"), 1)
	inst.mutations.append(bd)
	inst.rebuild(Run.player_sheet, [inst])
	var b := FireBreath.new()
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	var a := _creature(em, Vector3(0, 0, -3))
	assert_bool(b._fire()).is_true()
	var got: float = em.kb[a].length()
	_dummy = a
	var ref := _push(em, "", -1.0) * 5.0 / KB
	assert_float(got / ref).is_equal_approx(3.3 / 5.0, 0.01)


func test_powder_keg_deals_a_third_of_its_old_damage_at_every_rank() -> void:
	var consts: Dictionary = (load("res://game/Game.gd") as GDScript).get_script_constant_map()
	var frac := float(consts["KEG_FRAC"])
	assert_float(frac).is_equal_approx(0.25 / 3.0, 0.0001)
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game_src.contains("dead_max_hp * KEG_FRAC")).is_true()
	var w := _world()
	var em: EnemyManager = w["em"]
	for rank in range(1, 6):
		Run.add_or_level_passive("powder_keg")
		# the chance grows a rung, the blast does not: a 120 HP body's blast takes 10 HP off its neighbour
		var i := _creature(em, Vector3(1, 0, -3))
		var before: float = em.hp[i]
		em.damage_radius(Vector3(1, 0, -3), float(consts["KEG_RADIUS"]), 120.0 * frac, str(consts["POWDER_KEG"]), float(consts["KEG_KNOCK"]))
		assert_float(before - em.hp[i]).override_failure_message("rank %d" % rank).is_equal_approx(10.0, 0.01)
	assert_float(Run.player_sheet.get_stat("powder_keg_chance", 0.0)).is_equal_approx(0.155, 0.0001)
	assert_str(Registry.passive("powder_keg").text).contains("a twelfth of its max health")
