extends GdUnitTestSuite

## Pass 126, lane STAGE (Garry: The Dust Bowl "after Nightfall ... the same duration as what Hell does now, while increasing Hell
## duration accordingly"; "Tornadoes a bit more often than usual ... visually a bit bigger and x2 as strong in terms of how far
## they throw enemies and heroes"; a brown fog, the wind stronger, the trees bobbing, on this map only). Pinned here: the order
## and the windows; the Blood Moon's rows all in its new window and its strength what it was; saves keep every stage they had;
## the weather comes and goes with a stage and costs nothing elsewhere; the throw is x2 on The Dust Bowl and x1 elsewhere.
## Numbers are read from the map file, as map tests do (Garry tunes it).

const OLD_HELL_MULT := 3.34
const OLD_HELL := [1030.0, 1810.0]

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
var director = null
var paused := false
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
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var launches: Array = []
func launch(v: Vector3) -> void:
	launches.append(v)
"""


func _tl() -> WaveTimeline:
	return Registry.map("red_canyon").timeline


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## The old Blood Moon's second on the new clock.
func _new_t(t: float) -> float:
	return 1810.0 + (t - OLD_HELL[0]) * 960.0 / 780.0


# ---------------------------------------------------------------- the order and the windows

func test_the_order_and_the_windows() -> void:
	var tl := _tl()
	assert_int(tl.stage_count()).is_equal(4)
	assert_array([tl.stage_id(0), tl.stage_id(1), tl.stage_id(2), tl.stage_id(3)]).is_equal(["s1", "s2", "dust", "s3"])
	assert_str(tl.stage_name(2)).is_equal("The Dust Bowl")
	assert_str(tl.stage_boss(2)).is_equal("black_sunday")
	assert_str(tl.stage_boss(3)).is_equal("brander")
	assert_float(tl.stage_len(2)).is_equal(780.0)
	assert_float(tl.stage_len(3)).is_equal(960.0)
	assert_vector(tl.stage_window(2)).is_equal(Vector2(1030, 1810))
	assert_vector(tl.stage_window(3)).is_equal(Vector2(1810, 2770))
	assert_float(tl.total_length()).is_equal(2770.0)
	assert_bool(tl.stage_hell(2)).is_false()
	assert_bool(tl.stage_hell(3)).is_true()
	var words: Array = []
	for k in range(4):
		words.append(str(tl.stage_entry(k)["difficulty"]))
	assert_array(words).is_equal(["Easy", "Medium", "Hard", "Brutal"])


func test_every_list_by_stage_has_four_entries_and_the_hell_channel_stays_hells() -> void:
	var tl := _tl()
	assert_int(tl.path_times.size()).is_equal(4)
	assert_int(tl.stage_mults.size()).is_equal(4)
	assert_float(tl.hell_cap_at(2)).is_equal(0.0)
	assert_float(tl.hell_cap_at(3)).is_greater(0.0)
	# a mutation offer falls inside its stage
	for k in range(4):
		for t in tl.path_times_at(k):
			assert_float(float(t)).is_less(tl.stage_len(k))
	# no row of the hell channel on The Dust Bowl
	var w := tl.stage_window(2)
	for r in tl.roster:
		if str(r.get("channel", "")) == "hell":
			assert_bool(float(r.get("t", 0.0)) >= w.y).is_true()


func test_the_dust_bowls_rows_stay_in_its_window_and_name_creatures_that_exist() -> void:
	var tl := _tl()
	var w := tl.stage_window(2)
	var seen := {}
	for r in tl.roster:
		if not str(r.get("id", "")).begins_with("d"):
			continue
		var id := str(r["enemy"])
		seen[id] = true
		assert_object(Registry.enemy(id)).override_failure_message("row %s names %s" % [r["id"], id]).is_not_null()
		assert_bool(float(r["t"]) >= w.x and float(r["until"]) <= w.y).override_failure_message(str(r)).is_true()
	for id in ["straw_man", "carrion_crow", "dust_bunny"]:
		assert_bool(seen.has(id)).is_true()
	for row in tl.boss_fight_rows(2):
		assert_object(Registry.enemy(str(row["enemy"]))).is_not_null()
	# a first Elite about 3:00 in, the boss at its end
	var firsts: Array = tl.events.filter(func(e) -> bool: return str(e.get("type")) == "elite_boss" and float(e["t"]) >= w.x and float(e["t"]) < w.y)
	assert_bool(firsts.size() >= 1).is_true()
	assert_float(float(firsts[0]["t"]) - w.x).is_between(150.0, 210.0)


# ---------------------------------------------------------------- the Blood Moon moved and stretched

func test_every_row_and_event_of_the_blood_moon_lies_in_its_new_window() -> void:
	var tl := _tl()
	var w := tl.stage_window(3)
	var n := 0
	for r in tl.roster:
		if not str(r.get("id", "")).begins_with("s3"):
			continue
		n += 1
		assert_float(float(r["t"])).override_failure_message(str(r)).is_greater_equal(w.x)
		if r.get("until") != null:
			assert_float(float(r["until"])).is_greater(float(r["t"]))
			assert_float(float(r["until"])).is_less_equal(w.y)
		for p in r.get("weights", []):
			assert_float(float(p[0])).override_failure_message(str(r)).is_greater_equal(w.x)
	assert_int(n).is_greater_equal(34)
	var hell_events := tl.events.filter(func(e) -> bool: return float(e["t"]) > w.x)
	assert_int(hell_events.size()).is_equal(2)
	assert_float(float(hell_events[1]["t"])).is_equal(w.y)
	assert_str(str(hell_events[1]["enemy"])).is_equal("brander")


func test_its_set_pieces_come_as_often_as_they_did() -> void:
	var tl := _tl()
	var w := tl.stage_window(3)
	var once := tl.roster.filter(func(r) -> bool: return str(r.get("id", "")).begins_with("s3") and str(r.get("pace", "")) == "once")
	# 8 in 780 s before: one every 97.5 s; no gap past twice that
	assert_float(w.y - w.x).is_equal(960.0)
	assert_float(960.0 / float(once.size())).is_less_equal(97.5)
	var ts: Array = once.map(func(r) -> float: return float(r["t"]))
	ts.sort()
	for k in range(1, ts.size()):
		assert_float(float(ts[k]) - float(ts[k - 1])).is_less(195.0)


func test_its_creatures_are_as_strong_as_they_were() -> void:
	# the strength a row fixes from its start: the curves on the absolute clock x the stage multiplier
	var tl := _tl()
	var m := tl.stage_mult(3)
	for t: float in [1031.0, 1300.0, 1605.0]:
		var old_hp := pow(1.0 + 0.0977 * t / 60.0, 1.35) * OLD_HELL_MULT
		var new_hp := tl.hp_mult_at(_new_t(t)) * m
		assert_float(new_hp / old_hp).override_failure_message("HP at %.0f: %.2f vs %.2f" % [t, new_hp, old_hp]).is_between(0.92, 1.12)
	# the old damage curve, its points: 0.28 at 1030, 0.72 at 1700, 0.56 at 1810
	var old_dmg := {1031.0: 0.28, 1700.0: 0.72, 1810.0: 0.56}
	for t: float in old_dmg:
		var new_d := tl.damage_mult_at(_new_t(t) + (0.01 if t == 1031.0 else 0.0)) * m
		assert_float(new_d / (float(old_dmg[t]) * OLD_HELL_MULT)).override_failure_message("ATK at %.0f: %.3f" % [t, new_d]).is_between(0.97, 1.05)


func test_the_elite_and_the_brander_keep_their_data_hp_at_the_new_index() -> void:
	var tl := _tl()
	var brander := Registry.enemy("brander")
	var per := float(brander.boss.get("hp_mult_per_stage", 1.6))
	var evs := tl.events.filter(func(e) -> bool: return str(e.get("enemy")) == "brander")
	assert_int(evs.size()).is_equal(1)
	var now := float(evs[0]["stats"]["hp_mult"]) * pow(per, 3.0) * tl.stage_mult(3)
	var was := 0.15 * pow(per, 2.0) * OLD_HELL_MULT
	assert_float(now / was).is_between(0.99, 1.01)
	var elite := tl.events.filter(func(e) -> bool: return str(e.get("type")) == "elite_boss" and float(e["t"]) > 1810.0)
	assert_int(elite.size()).is_equal(1)
	var e_per := 1.8
	var e_now := float(elite[0]["stats"]["hp_mult"]) * pow(e_per, 3.0) * tl.stage_mult(3)
	assert_float(e_now / (0.45 * pow(e_per, 2.0) * OLD_HELL_MULT)).is_between(0.99, 1.01)


func test_its_coins_items_and_speed_are_what_they_were() -> void:
	var tl := _tl()
	assert_float(tl.stage_reward_mult(3)).is_equal(OLD_HELL_MULT)
	assert_int(int(round(tl.stage_reward_mult(3)))).is_equal(3)
	# pass 134: speeds x1.15 at the start, the top kept (Blood Moon 1.2 -> 1.2^0.91953)
	assert_float(tl.speed_mult(3)).is_equal_approx(1.1825, 0.0001)
	# Sundown's and Nightfall's stay what they read: no key of their own
	assert_float(tl.stage_reward_mult(0)).is_equal(tl.stage_mult(0))
	assert_float(tl.stage_reward_mult(1)).is_equal(tl.stage_mult(1))
	assert_float(tl.speed_mult(0)).is_equal_approx(1.0, 0.0001)
	# pass 134: speeds x1.15 at the start, the top kept
	assert_float(tl.speed_mult(1)).is_equal_approx(1.0916, 0.0001)


func test_what_meant_the_blood_moon_keeps_meaning_it() -> void:
	var hell := -1
	for k in range(_tl().stage_count()):
		if _tl().stage_hell(k):
			hell = k
	for id in ["brimstone_brand", "sinners_greed"]:
		assert_int(Registry.passive(id).from_stage).is_equal(hell + 1)
	# pass 129 (lane TRAIL-SETUP, re-pinned): The Ghost's quest (reach the last stage) is retired; a Trail node gives the card
	assert_object(Registry.quest_for("passive", "evade")).is_null()
	assert_bool(Trail.gated("passive", "evade")).is_true()


# ---------------------------------------------------------------- saves

func _save_with(beaten: Array, flags: Array = []) -> void:
	Save.begin_sandbox()
	Save.data["stages_beaten"] = {"red_canyon": beaten}
	Save.data["once"] = flags.duplicate()


func test_a_save_that_had_beaten_the_blood_moon_has_all_four() -> void:
	_save_with([true, true, true], ["boss_red_canyon_3", "extract_red_canyon_3"])
	Save._migrate_dust_bowl()
	assert_array(Save.stages_beaten("red_canyon")).is_equal([true, true, true, true])
	# pass 129 (lane TRAIL-SETUP, re-pinned): the Dust Bowl and Blood Moon also ask the Trail; the save's own migration
	# (it has played) keeps every stage it had open
	Save.data["runs_started"] = 1
	Save._migrate_trail()
	for k in range(4):
		assert_bool(Save.stage_unlocked("red_canyon", k)).is_true()
	assert_bool(Save.once("boss_red_canyon_4")).is_true()
	assert_bool(Save.once("extract_red_canyon_4")).is_true()
	assert_bool(Save.once("boss_red_canyon_3")).is_true()
	Save.end_sandbox()


func test_a_save_at_nightfall_opens_the_dust_bowl_with_the_blood_moon_locked() -> void:
	_save_with([true, true])
	Save._migrate_dust_bowl()
	assert_array(Save.stages_beaten("red_canyon")).is_equal([true, true])
	# pass 129 (lane TRAIL-SETUP, re-pinned): the save's own migration keeps the Dust Bowl it had open (as above)
	Save.data["runs_started"] = 1
	Save._migrate_trail()
	assert_bool(Save.stage_unlocked("red_canyon", 2)).is_true()
	assert_bool(Save.stage_unlocked("red_canyon", 3)).is_false()
	Save.end_sandbox()


func test_the_migration_runs_once_and_never_takes_a_stage_away() -> void:
	_save_with([])
	Save._migrate_dust_bowl()
	assert_array(Save.stages_beaten("red_canyon")).is_empty()
	# a stage beaten after it: index 2 is The Dust Bowl now, and beating it opens only the Blood Moon
	Save.mark_stage_beaten("red_canyon", 0)
	Save.mark_stage_beaten("red_canyon", 1)
	Save.mark_stage_beaten("red_canyon", 2)
	Save._migrate_dust_bowl()
	assert_array(Save.stages_beaten("red_canyon")).is_equal([true, true, true])
	assert_bool(Save.stage_beaten("red_canyon", 3)).is_false()
	# pass 129 (lane TRAIL-SETUP, re-pinned): beaten; Blood Moon opens once its Trail node is bought too
	assert_bool(Save.stage_unlocked("red_canyon", 3)).is_equal(Trail.has("stage", "red_canyon:s3"))
	Save.end_sandbox()
	# the Brander in an old save's totals put on the new index by _migrate_stages: the stages under it come too
	_save_with([true, true, false, true])
	Save._migrate_dust_bowl()
	assert_array(Save.stages_beaten("red_canyon")).is_equal([true, true, true, true])
	# pass 129 (lane TRAIL-SETUP, re-pinned): the Dust Bowl and Blood Moon also ask the Trail; the save's own migration
	# (it has played) keeps every stage it had open
	Save.data["runs_started"] = 1
	Save._migrate_trail()
	Save.end_sandbox()


# ---------------------------------------------------------------- the weather

func test_a_stage_without_a_weather_block_has_none() -> void:
	var tl := _tl()
	for k in [0, 1, 3]:
		assert_bool(tl.stage_weather(k).is_empty()).is_true()
		assert_object(tl.dust_devils_at(k)).is_same(tl.dust_devils)
	assert_bool(tl.stage_weather(2).is_empty()).is_false()


func test_the_weather_comes_and_goes_to_the_number() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var m = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	var env: Environment = m._env
	var fog0 := env.fog_light_color
	var d0 := env.fog_density
	var gust: DustGust = m.get_node("DustGust")
	var haze: DustHaze = m.haze
	assert_bool(haze.showing()).is_false()
	assert_object(haze.quad).is_null()
	assert_int(gust._mm.instance_count).is_equal(DustGust.STREAKS)
	var block := _tl().stage_weather(2)
	m.set_weather(block, 0.0)
	assert_float(env.fog_density).is_equal_approx(float(block["fog"]["density"]), 0.00001)
	assert_bool(env.fog_light_color.is_equal_approx(fog0)).is_false()
	assert_bool(haze.showing()).is_true()
	assert_bool(haze.is_processing()).is_true()
	assert_bool(gust.storm.is_empty()).is_false()
	assert_int(gust._mm.instance_count).is_equal(int(block["gust"]["streaks"]))
	assert_vector(m.props.wind_now).is_equal(Vector3(float(block["wind"]["mult"]), float(block["wind"]["speed"]), float(block["wind"]["gust"])))
	# gone again: not just transparent
	m.set_weather({}, 0.0)
	assert_float(env.fog_density).is_equal(d0)
	assert_bool(env.fog_light_color.is_equal_approx(fog0)).is_true()
	assert_bool(haze.showing()).is_false()
	assert_bool(haze.is_processing()).is_false()
	assert_bool(gust.storm.is_empty()).is_true()
	assert_int(gust._mm.instance_count).is_equal(DustGust.STREAKS)
	assert_vector(m.props.wind_now).is_equal(Vector3(1.0, PropField.WIND_SPEED, 0.0))
	Run.end()


func test_hell_still_tints_the_fog_with_no_weather() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var m = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	m._apply_hell(1.0)
	assert_bool(m._env.fog_light_color.is_equal_approx(m.HELL_FOG)).is_true()
	Run.end()


func test_the_shaders_defaults_are_the_sway_it_always_was_and_a_rock_never_moves() -> void:
	var src: String = load("res://core/shaders/prop_billboard.gdshader").code
	assert_bool(src.contains("uniform float wind_mult = 1.0;")).is_true()
	assert_bool(src.contains("uniform float wind_speed = 1.3;")).is_true()
	assert_bool(src.contains("uniform float wind_gust = 0.0;")).is_true()
	# the lean is proportional to the sway and the square of the height up the painting: 0 at the foot, 0 for a rock
	assert_bool(src.contains("sway * ly * ly * wind_mult")).is_true()


func test_the_haze_is_one_quad_with_two_samples_and_no_scene_fog() -> void:
	var src: String = load("res://core/shaders/dust_haze.gdshader").code
	assert_bool(src.contains("fog_disabled")).is_true()
	assert_int(src.count("texture(noise_tex")).is_equal(2)
	assert_bool(src.contains("for (")).is_false()
	assert_bool(src.contains("stencil_mode read, compare_not_equal, 1;")).is_true()


func test_a_storm_streak_feathers_out_on_every_side_and_is_not_cut_by_the_sand() -> void:
	var src: String = load("res://core/shaders/gust_streak.gdshader").code
	assert_bool(src.contains("depth_test_disabled")).is_true()
	assert_bool(src.contains("fog_disabled")).is_true()
	assert_bool(src.contains("float along = pow(sin(UV.y * PI)")).is_true()
	assert_bool(src.contains("float across = pow(sin(UV.x * PI)")).is_true()
	assert_bool(src.contains("stencil_mode read, compare_not_equal, 1;")).is_true()
	# the shader's two factors are 0 at the quad's four edges and 1 in its middle
	for e: float in [0.0, 1.0]:
		assert_float(pow(sin(e * PI), 1.4)).is_less(0.0001)
		assert_float(pow(sin(e * PI), 2.0)).is_less(0.0001)
	assert_float(pow(sin(0.5 * PI), 1.4)).is_equal_approx(1.0, 0.0001)
	# a storm wears it, the map's gusts keep their material
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var m = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	var gust: DustGust = m.get_node("DustGust")
	var plain: Material = gust._mmi.material_override
	assert_bool(plain is StandardMaterial3D).is_true()
	m.set_weather(_tl().stage_weather(2), 0.0)
	assert_bool(gust._mmi.material_override is ShaderMaterial).is_true()
	assert_int((gust._mmi.material_override as Material).render_priority).is_less(StageLook.PRIORITY)
	m.set_weather({}, 0.0)
	assert_object(gust._mmi.material_override).is_same(plain)
	Run.end()


# ---------------------------------------------------------------- the throw

## Where a real toss {up, out} carries the hero with no stick: Player._physics_process's own steps at 60 Hz (his gravity 24, his
## shove fading at 6/s): {far: metres along the ground at landing, high: metres at the top}.
func _toss(up: float, out: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var y := 0.0
	var vy := up
	var kb := out
	var x := 0.0
	var high := 0.0
	for k in range(600):
		vy -= 24.0 * dt
		y += vy * dt
		x += kb * dt
		kb = lerpf(kb, 0.0, dt * 6.0)
		high = maxf(high, y)
		if y <= 0.0:
			break
	return {"far": x, "high": high}


func test_the_heros_throw_is_x2_on_the_dust_bowl_and_x1_elsewhere() -> void:
	var tl := _tl()
	var base := DustDevils.config_of(tl.dust_devils)
	var dust := DustDevils.config_of(tl.dust_devils_at(2))
	var a := _toss(float(base["toss"]["up"]), float(base["toss"]["out"]))
	var b := _toss(float(dust["toss"]["up"]), float(dust["toss"]["out"]))
	assert_float(float(b["far"]) / float(a["far"])).override_failure_message("far %s vs %s" % [b, a]).is_between(1.85, 2.15)
	assert_float(float(b["high"]) / float(a["high"])).override_failure_message("high %s vs %s" % [b, a]).is_between(1.85, 2.15)
	# he is down before the next throw can come
	assert_float(float(dust["toss"]["cooldown"])).is_greater(2.0 * float(dust["toss"]["up"]) / 24.0)
	for k in [0, 1, 3]:
		var other := DustDevils.config_of(tl.dust_devils_at(k))
		assert_float(float(other["toss"]["up"])).is_equal(float(base["toss"]["up"]))
		assert_float(float(other["toss"]["out"])).is_equal(float(base["toss"]["out"]))
		assert_float(float(other["fling"])).is_equal(1.0)


func test_a_bit_more_often_and_a_bit_bigger_on_the_dust_bowl_only() -> void:
	var tl := _tl()
	var base := DustDevils.config_of(tl.dust_devils)
	var dust := DustDevils.config_of(tl.dust_devils_at(2))
	assert_float(float(dust["first"])).is_less(float(base["first"]))
	assert_float((dust["every"] as Vector2).x).is_less((base["every"] as Vector2).x)
	assert_float((dust["every"] as Vector2).y).is_less((base["every"] as Vector2).y)
	assert_float(float(dust["size"])).is_between(float(base["size"]) * 1.15, float(base["size"]) * 1.45)
	assert_float(float(dust["radius"])).is_between(float(base["radius"]) * 1.1, float(base["radius"]) * 1.35)
	assert_float(float(dust["fling"])).is_equal(2.0)
	# what the map's block leaves alone it keeps
	assert_float(float(dust["lift"])).is_equal(float(base["lift"]))
	assert_float(float(dust["speed"])).is_equal(float(base["speed"]))


## Where a real dust devil with these numbers leaves one creature that started `from` m from its middle: the real ride and the
## real swirl, then the landing's shove run out (it fades at 6/s): metres from the middle.
func _rest_from_middle(fling: float, radius: float, from: float) -> float:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = Vector3(50.0, 0, 50.0)
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
	em._rebuild_grid()
	var dds := DustDevils.new()
	dds.game = g
	g.add_child(dds)
	dds.setup({"first": 9999, "fling": fling, "radius": radius, "life": [60, 60], "form_seconds": 0.1}, 126)
	var dd := dds.call_one(Vector3.ZERO, Vector3(1, 0, 0))
	dd.speed = 0.0
	var i := em.spawn("skeleton", Vector3(from, 0, 0), null, 1.0, 500.0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	var dt := 1.0 / 60.0
	var was_up := false
	for k in range(600):
		dd.step(dt)
		em._physics_process(dt)
		if em.lift_t[i] > 0.0:
			was_up = true
		elif was_up:
			break
	assert_bool(was_up).is_true()
	var p := em.pos[i] + em.kb[i] / 6.0
	p.y = 0.0
	Run.end()
	return p.length()


func test_a_creature_comes_to_rest_x2_as_far_with_fling_2() -> void:
	var r := 3.6
	var one := 0.0
	var two := 0.0
	for from: float in [r * 0.4, r * 0.7, r * 0.95]:
		one += _rest_from_middle(1.0, r, from) / 3.0
		two += _rest_from_middle(2.0, r, from) / 3.0
	print("creature rest from the middle: fling 1 %.2f m, fling 2 %.2f m" % [one, two])
	assert_float(two / one).override_failure_message("%.2f vs %.2f" % [two, one]).is_between(1.75, 2.25)
