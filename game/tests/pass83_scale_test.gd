extends GdUnitTestSuite

## Pass 83, lane SCALE (Garry: "I want it to take at least 25 seconds of Player's FULL DPS on Tumbleweed king to kill it.
## Then 40s for the next and a full minute to the last one" and "add a modifier for the enemy HP scaling with the power
## level of the Player ... Default scaling is 1, meaning no scaling at all"): boss_hp_scaling's seconds mode
## (WaveTimeline.boss_seconds_hp, WaveDirector.boss_seconds_target, EnemyManager.boss_hp_target), the hero's power
## (HeroPower: full DPS, effective HP, power), the creatures' HP by power (WaveTimeline.power_hp_factor,
## WaveDirector.power_hp_mult folded into the fixed numbers' lv_hp), the power on every run record row, and Red Canyon's
## block read from the map file.

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
var facing := 0.0
var velocity := Vector3.ZERO
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

var _keep: Dictionary = {}
var _keep_pw := 1.0
var _keep_pmax := 10.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	_keep = (tl.boss_hp_scaling as Dictionary).duplicate(true)
	_keep_pw = tl.power_hp_scaling
	_keep_pmax = tl.power_hp_max
	HeroPower.forget()


func after_test() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	tl.boss_hp_scaling = _keep
	tl.power_hp_scaling = _keep_pw
	tl.power_hp_max = _keep_pmax
	Run.arena = false
	Run.stage = 0
	Run.elapsed = 0.0
	HeroPower.forget()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = Vector3(0, 0, 30)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "em": em}


## The Drifter with the Revolver at `lv` and nothing else.
func _revolver(lv: int) -> void:
	Run.debug_clear_items()
	Run.debug_set_item("weapon", "revolver", lv)
	Run.rebuild_sheets()
	HeroPower.forget()


# ---------------------------------------------------------------- the seconds mode

func test_the_seconds_rule_is_full_dps_times_seconds_never_under_the_data_hp() -> void:
	assert_float(WaveTimeline.boss_seconds_hp(1440.0, 300.0, 25.0)).is_equal(7500.0)
	# a weak hero meets the data HP
	assert_float(WaveTimeline.boss_seconds_hp(1440.0, 40.0, 25.0)).is_equal(1440.0)
	# 0 seconds or no DPS: the data HP
	assert_float(WaveTimeline.boss_seconds_hp(1440.0, 300.0, 0.0)).is_equal(1440.0)
	assert_float(WaveTimeline.boss_seconds_hp(1440.0, 0.0, 25.0)).is_equal(1440.0)
	# the boss's damage reduction is folded in: the kill still takes the seconds of full DPS
	assert_float(WaveTimeline.boss_seconds_hp(0.0, 300.0, 25.0, 0.2)).is_equal_approx(6000.0, 0.001)
	# the defaults: the mode on, Garry's 25 / 40 / 60
	var bare := WaveTimeline.new()
	assert_str(bare.boss_hp_mode()).is_equal("seconds")
	assert_float(bare.boss_seconds("tumbleweed_king")).is_equal(25.0)
	assert_float(bare.boss_seconds("gila_grande")).is_equal(40.0)
	assert_float(bare.boss_seconds("brander")).is_equal(60.0)
	assert_float(bare.boss_seconds("nobody")).is_equal(0.0)
	var tl := JsonContent.timeline_from_dict({"boss_hp_scaling": {"mode": "dps", "seconds": {"gila_grande": 90}}})
	assert_str(tl.boss_hp_mode()).is_equal("dps")
	assert_float(tl.boss_seconds("gila_grande")).is_equal(90.0)
	assert_float(tl.boss_seconds("brander")).is_equal(60.0)
	assert_str(JsonContent.timeline_from_dict({"boss_hp_scaling": {"mode": "nonsense"}}).boss_hp_mode()).is_equal("seconds")


func test_a_boss_comes_with_its_seconds_of_the_heros_full_dps() -> void:
	_revolver(5)
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	tl.boss_hp_scaling = {"enabled": true, "mode": "seconds", "seconds": {"tumbleweed_king": 25, "gila_grande": 0}}
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := WaveDirector.new()
	dir.timeline = tl
	auto_free(dir)
	Run.stage = 0
	var full := HeroPower.boss_dps_now()
	assert_float(full).is_greater(0.0)
	var target := dir.boss_seconds_target("tumbleweed_king")
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	assert_float(target).is_equal_approx(full * 25.0 * (1.0 - king.damage_reduction), 0.01)
	assert_str(str(dir.last_boss_scale["mode"])).is_equal("seconds")
	assert_float(float(dir.last_boss_scale["seconds"])).is_equal(25.0)
	# the spawn takes max(the data HP, the target); here the Revolver alone is under the King's data HP x 25 s or over it
	em.boss_hp_target = target
	var i := em.spawn("tumbleweed_king", Vector3(0, 0, 0))
	em.boss_hp_target = 0.0
	var base: float = king.hp * maxf(em.stage_mult, 1.0)
	assert_float(em.max_hp[i]).is_equal_approx(maxf(base, target), 0.5)
	# a monster build: the target wins
	em.kill_all(false)
	em.boss_hp_target = base * 10.0
	var j := em.spawn("tumbleweed_king", Vector3(0, 0, 0))
	em.boss_hp_target = 0.0
	assert_float(em.max_hp[j]).is_equal_approx(base * 10.0, 0.5)
	# the seconds mode never pegs (the multiplier stays 1)
	assert_float(dir.boss_dps_scale("tumbleweed_king")).is_equal(1.0)
	# 0 seconds, the pegged mode, scaling off, the arena: no target
	assert_float(dir.boss_seconds_target("gila_grande")).is_equal(0.0)
	tl.boss_hp_scaling["mode"] = "dps"
	assert_float(dir.boss_seconds_target("tumbleweed_king")).is_equal(0.0)
	tl.boss_hp_scaling["mode"] = "seconds"
	tl.boss_hp_scaling["enabled"] = false
	assert_float(dir.boss_seconds_target("tumbleweed_king")).is_equal(0.0)
	tl.boss_hp_scaling["enabled"] = true
	Run.arena = true
	assert_float(dir.boss_seconds_target("tumbleweed_king")).is_equal(0.0)
	Run.arena = false
	# a stronger hero: a bigger target, in step with his full DPS
	_revolver(1)
	var f1 := HeroPower.boss_dps_now()
	var t1 := dir.boss_seconds_target("tumbleweed_king")
	_revolver(5)
	var f5 := HeroPower.boss_dps_now()
	var t5 := dir.boss_seconds_target("tumbleweed_king")
	assert_float(t5).is_greater(t1)
	assert_float(t5 / t1).is_equal_approx(f5 / f1, 0.001)


func test_red_canyon_sets_its_bosses_by_seconds_of_full_dps() -> void:
	# read from the map file (Garry tunes it in the Level Editor): the mode it plays, and seconds for every boss it brings
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var tl := JsonContent.timeline_from_dict(d["timeline_data"])
	assert_str(tl.boss_hp_mode()).is_equal("seconds")
	for ev in d["timeline_data"]["events"]:
		if str(ev.get("type", "")) == "boss":
			assert_float(tl.boss_seconds(str(ev["enemy"]))).override_failure_message(str(ev["enemy"])).is_greater(0.0)


# ---------------------------------------------------------------- the hero's power

func test_the_power_formula_on_a_fixed_build() -> void:
	# a fresh level-1 Drifter with the Revolver is 1 (the constants are his numbers)
	assert_float(HeroPower.power_from(HeroPower.BASE_DPS, HeroPower.BASE_EHP)).is_equal_approx(1.0, 0.0001)
	assert_float(HeroPower.power_from(HeroPower.BASE_DPS * 4.0, HeroPower.BASE_EHP)).is_equal_approx(2.0, 0.0001)
	assert_float(HeroPower.power_from(HeroPower.BASE_DPS * 2.0, HeroPower.BASE_EHP * 2.0)).is_equal_approx(2.0, 0.0001)
	_revolver(1)
	var m: Dictionary = HeroPower.measure(Run.weapons, Run.player_sheet)
	assert_float(float(m["power"])).override_failure_message("a fresh Drifter's power: %s" % str(m)).is_between(0.8, 1.25)
	# the effective HP: (max HP + shield + 30 s of regen and lifesteal) / ((1 - armour) x (1 - evade))
	var sh := StatSheet.new()
	sh.set_bases({"max_hp": 200.0, "shield_max": 20.0, "regen": 1.0, "lifesteal": 0.01, "lifesteal_cap": 0.04, "damage_reduction": 0.2, "evade": 0.5})
	# lifesteal 1% of 300 DPS = 3 a second, under its cap of 8 a second
	assert_float(HeroPower.ehp(sh, 300.0)).is_equal_approx((220.0 + 30.0 * (1.0 + 3.0)) / (0.8 * 0.5), 0.01)
	# the cap holds (4% of 200 = 8 a second at most)
	assert_float(HeroPower.ehp(sh, 100000.0)).is_equal_approx((220.0 + 30.0 * (1.0 + 8.0)) / (0.8 * 0.5), 0.01)
	# the average crit
	sh.set_bases({"crit_chance": 0.25, "crit_damage": 3.0})
	assert_float(HeroPower.crit_factor(sh)).is_equal_approx(1.5, 0.0001)
	# full DPS: the Revolver hits one target a shot: its estimate x the crit
	var rev = Run.weapons[0]
	assert_float(HeroPower.crowd_of(rev)).is_equal(1.0)
	assert_float(HeroPower.full_dps(Run.weapons, Run.player_sheet)).is_equal_approx(rev.dps_estimate() * HeroPower.crit_factor(Run.player_sheet), 0.001)
	# more levels, more power
	_revolver(5)
	assert_float(HeroPower.current()).is_greater(float(m["power"]))


func test_a_crowd_weapon_counts_one_target_in_its_full_dps() -> void:
	Run.debug_clear_items()
	Run.debug_set_item("weapon", "guitarra", 1)
	Run.rebuild_sheets()
	var g = Run.weapons[0]
	# a cone wave's estimate counts three creatures a chord; full DPS counts the one
	assert_float(HeroPower.crowd_of(g)).is_equal(3.0)
	assert_float(HeroPower.weapon_dps(g)).is_equal_approx(g.dps_estimate() / 3.0 + HeroPower.element_dps(g), 0.001)


# ---------------------------------------------------------------- the creatures' HP by power

func test_power_hp_scaling_1_is_no_scaling_and_more_grows_the_hp_with_power() -> void:
	for p: float in [0.5, 1.0, 3.0, 50.0]:
		assert_float(WaveTimeline.power_hp_factor(1.0, 10.0, p)).is_equal(1.0)
	assert_float(WaveTimeline.power_hp_factor(2.0, 10.0, 4.0)).is_equal_approx(4.0, 0.0001)
	assert_float(WaveTimeline.power_hp_factor(1.5, 10.0, 4.0)).is_equal_approx(2.0, 0.0001)
	# the direction: more power, more HP (above 1); held at the ceiling
	assert_float(WaveTimeline.power_hp_factor(1.5, 10.0, 9.0)).is_greater(WaveTimeline.power_hp_factor(1.5, 10.0, 4.0))
	assert_float(WaveTimeline.power_hp_factor(2.0, 10.0, 50.0)).is_equal(10.0)
	# below 1 the creatures soften, held at 1 / the ceiling
	assert_float(WaveTimeline.power_hp_factor(0.5, 10.0, 4.0)).is_equal_approx(0.5, 0.0001)
	assert_float(WaveTimeline.power_hp_factor(0.0, 4.0, 100.0)).is_equal_approx(0.25, 0.0001)
	# power 1 (a fresh Drifter) is x1 at any scaling
	assert_float(WaveTimeline.power_hp_factor(2.5, 10.0, 1.0)).is_equal_approx(1.0, 0.0001)
	# the map's default: 1 (a map without the key, and the class)
	assert_float(JsonContent.timeline_from_dict({}).power_hp_scaling).is_equal(1.0)
	assert_float(JsonContent.timeline_from_dict({"power_hp_scaling": 1.6, "power_hp_max": 4}).power_hp_max).is_equal(4.0)


func test_the_director_folds_the_power_into_a_rows_fixed_hp() -> void:
	_revolver(5)
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var dir := WaveDirector.new()
	dir.timeline = tl
	auto_free(dir)
	tl.power_hp_scaling = 1.0
	var plain: Dictionary = dir.fixed_numbers(100.0)
	assert_float(dir.power_hp_mult()).is_equal(1.0)
	var p := HeroPower.current()
	assert_float(p).is_greater(1.0)
	tl.power_hp_scaling = 2.0
	tl.power_hp_max = 1000.0
	var scaled: Dictionary = dir.fixed_numbers(100.0)
	assert_float(float(scaled["lv_hp"])).is_equal_approx(float(plain["lv_hp"]) * p, 0.001)
	# the damage and the time curve are not touched
	assert_float(float(scaled["lv_dmg"])).is_equal(float(plain["lv_dmg"]))
	assert_float(float(scaled["hp_time"])).is_equal(float(plain["hp_time"]))
	# never in the arena
	Run.arena = true
	assert_float(dir.power_hp_mult()).is_equal(1.0)
	Run.arena = false


# ---------------------------------------------------------------- the record

## pass74_analytics_test's fake game: two goblins up, a director, a hero at 80 of 100.
const REC_GAME := """extends Node
var enemies = null
var director = null
var player = null
"""
const REC_ENEMIES := """extends Node
signal enemy_died(def, pos, elite, weapon_id)
signal boss_died(def, pos)
var alive := PackedByteArray()
var state := PackedInt32Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var dmg := PackedFloat32Array()
var type_idx := PackedInt32Array()
var types: Array = []
var boss_index := -1
var stage_mult := 1.0
var hp_time_mult := 1.0
var damage_time_mult := 1.0
var level_hp_mult := 1.0
var level_dmg_mult := 1.0
var time_scale := 1.0
var count_alive := 0
var specials_alive := 0
var special_chests := 0
var sniper_aims := 0
var sniper_hero_hits := 0
func alive_count() -> int:
	return count_alive
func cap_load() -> float:
	return float(count_alive)
"""
const REC_DIRECTOR := """extends Node
signal boss_started(def)
signal stage_started(stage)
var phase := 0
var timeline = null
var last_boss_scale: Dictionary = {}
func current_cap() -> int:
	return 20
"""
const REC_PLAYER := """extends Node
var hp := 80.0
var max_hp := 100.0
var shield_pts := 0.0
var invuln := 0.0
var damage_log: Array = []
"""


func _fake_recorder_game() -> Node:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(REC_GAME))
	add_child(g)
	var em := Node.new()
	em.set_script(_script(REC_ENEMIES))
	g.add_child(em)
	var alive := PackedByteArray()
	alive.resize(8)
	em.alive = alive
	var state := PackedInt32Array()
	state.resize(8)
	em.state = state
	em.hp = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	em.max_hp = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	em.dmg = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	em.type_idx = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])
	g.enemies = em
	var d := Node.new()
	d.set_script(_script(REC_DIRECTOR))
	g.add_child(d)
	g.director = d
	var p := Node.new()
	p.set_script(_script(REC_PLAYER))
	g.add_child(p)
	g.player = p
	return g


func test_every_row_of_the_record_carries_the_power() -> void:
	_revolver(3)
	var g := _fake_recorder_game()
	var ra := RunAnalytics.new()
	ra.mirror = false
	g.add_child(ra)
	ra.begin(g)
	ra.header["stamp"] = "test-p83-%d" % Time.get_ticks_usec()
	ra.tick(1.0)
	ra.tick(1.0)
	assert_int(ra.samples.size()).is_greater_equal(2)
	var m: Dictionary = HeroPower.measure(Run.weapons, Run.player_sheet)
	for row: Dictionary in ra.samples:
		assert_float(float(row.get("power", 0.0))).is_equal_approx(snappedf(float(m["power"]), 0.01), 0.011)
		assert_float(float(row.get("full_dps", 0.0))).is_greater(0.0)
		assert_float(float(row.get("ehp", 0.0))).is_greater(0.0)
		# scaling 1 on the map: no factor on the row
		assert_bool(row.has("power_hp")).is_false()
	DirAccess.remove_absolute("user://analytics/runs/%s.json" % str(ra.header["stamp"]))
	ra.queue_free()


func test_the_hooks_are_in_the_game() -> void:
	var wd := FileAccess.get_file_as_string("res://core/systems/WaveDirector.gd")
	assert_str(wd).contains("em.set(\"boss_hp_target\", boss_seconds_target(id, variant, en[\"stats\"]))")
	assert_str(wd).contains("* power_hp_mult()")
	var em := FileAccess.get_file_as_string("res://core/systems/EnemyManager.gd")
	assert_str(em).contains("hp[i] = maxf(hp[i], boss_hp_target)")
	var ra := FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd")
	assert_str(ra).contains("_putf(row, \"power\", float(hpw[\"power\"]), 0.01)")
