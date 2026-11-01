extends GdUnitTestSuite

## Pass 120, the lead (Garry: "I wanted to make the 4th Spider Row a guaranteed specials with a Split modifier, but I
## can't tell if I made it so they are guaranteed to spawn as specials. I set the Spider to isSpecial = TRUE, but it's
## giving me a warning"; and the retunes: "Personal Storm - Make it so it appears every 45s instead of every 30s",
## "Pocket Bible - Make it so every attack doesn't take more than 35% of heroes' Max HP", "Iron Horse - ... every 30s
## at the start ... the foreshadowing ... is double the time, and the train moves at 75% of the current speed").
## A forced special (a row's "special": true) comes as its coloured special also when it wears an elite modifier (both)
## and when its creature has no variance block (the map's special_defaults, else the game's, colour SPECIAL_TINT); a
## random roll never lands on an elite-modded one; an elite-modded special drops the Elite's chest, not the special's on
## top; the three items' numbers.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
var toasts: Array = []
var director = null
var no_random_chests := false
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
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
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

const FAKE_PICKUPS := """extends Node
var chests := 0
var chest_at: Array = []
func spawn_special(_def, _at, _quiet = false) -> void:
	pass
func spawn_chest(at, _boss = false) -> void:
	chests += 1
	chest_at.append(at)
func spawn(_k, _at, _v = 0.0) -> int:
	return -1
"""

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
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


func _world(hero_at := Vector3(0, 0, 80)) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.set("player", hero)
	var mb := MapBase.new()
	g.add_child(mb)
	g.set("map", mb)
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.set("pickups", pk)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	# colour from the first kill, as a director sets it (a crowd without one spawns plain, pass 71)
	em.colour_after_kills = 0
	return {"g": g, "hero": hero, "em": em, "map": mb, "pk": pk}


## A test creature `id` made from `from` with no jitter, its variance block `vr`; gone after the test.
func _test_def(id: String, from: String, vr: Dictionary) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = vr
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	d.drops = {}
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _row(em: EnemyManager, id: String, n: int, z: float = 0.0) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(em.spawn(id, Vector3(float(k) * 2.5 - 10.0, 0, z)))
	return out



func _splitter() -> EliteModDef:
	var m: EliteModDef = Registry.elites.get("splitter")
	assert_object(m).is_not_null()
	return m


func test_a_forced_special_without_a_variance_block_takes_the_maps_numbers_and_the_default_colour() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.special_defaults = {"damage": 3.5}
	var d := _test_def("p120_plain_spider", "desert_spider", {})
	em.force_special = true
	var i := em.spawn(d.id, Vector3(0, 0, 0))
	em.force_special = false
	assert_int(i).is_greater_equal(0)
	assert_int(int(em.vspecial[i])).is_equal(1)
	var j := em.spawn(d.id, Vector3(4, 0, 0))
	assert_int(int(em.vspecial[j])).is_equal(0)
	# x15 HP (the game's), x3.5 damage (the map's), x1.5 size, the glow, in crimson
	assert_float(em.max_hp[i] / em.max_hp[j]).is_equal_approx(15.0, 0.001)
	assert_float(em.dmg[i] / em.dmg[j]).is_equal_approx(3.5, 0.001)
	assert_float(em.size[i] / em.size[j]).is_equal_approx(1.5, 0.001)
	assert_float(em.vglow[i]).is_equal_approx(0.6, 0.001)
	var c := Color(EnemyDef.SPECIAL_TINT)
	assert_float(em.vtint[i].r).is_equal_approx(c.r, 0.01)
	assert_float(em.vtint[i].a).is_equal_approx(0.6, 0.001)
	# the map's own colour wins over the default
	em.special_defaults = {"tint": "#2040A0"}
	em.force_special = true
	var k := em.spawn(d.id, Vector3(8, 0, 0))
	em.force_special = false
	assert_float(em.vtint[k].b).is_equal_approx(Color("#2040A0").b, 0.01)


func test_a_forced_special_with_an_elite_modifier_is_both() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var d := _test_def("p120_split_spider", "desert_spider", {})
	var mod := _splitter()
	var plain := em.spawn(d.id, Vector3(0, 0, 0))
	var elite := em.spawn(d.id, Vector3(4, 0, 0), mod)
	em.force_special = true
	var both := em.spawn(d.id, Vector3(8, 0, 0), mod)
	em.force_special = false
	assert_int(int(em.vspecial[elite])).is_equal(0)
	assert_int(int(em.vspecial[both])).is_equal(1)
	assert_int(em.elite_idx[both]).is_greater_equal(0)
	# the modifier's HP (a "mul" 1.5: x2.5) and the special's x15 on top
	assert_float(em.max_hp[elite] / em.max_hp[plain]).is_equal_approx(2.5, 0.001)
	assert_float(em.max_hp[both] / em.max_hp[elite]).is_equal_approx(15.0, 0.01)
	# the modifier's scale and the special's size factor
	assert_float(em.size[both] / em.size[elite]).is_equal_approx(1.5, 0.001)
	assert_float(em.radius[both] / em.radius[elite]).is_equal_approx(1.5, 0.001)
	assert_int(em.specials_alive).is_equal(1)


func test_a_random_special_roll_never_lands_on_an_elite_modded_one() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.special_defaults = {"max_alive": 0}
	var d := _test_def("p120_always_spider", "desert_spider", {"special_chance": 1.0, "special": {"tint": "#5A1078"}})
	var mod := _splitter()
	var plain := em.spawn(d.id, Vector3(0, 0, 0))
	var elite := em.spawn(d.id, Vector3(4, 0, 0), mod)
	assert_int(int(em.vspecial[plain])).is_equal(1)
	assert_int(int(em.vspecial[elite])).is_equal(0)


func test_an_elite_modded_special_drops_the_elites_chest_not_the_specials_on_top() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.special_defaults = {"chest_chance": 1.0}
	var d := _test_def("p120_chest_spider", "desert_spider", {})
	em.force_special = true
	var solo := em.spawn(d.id, Vector3(0, 0, 0))
	var both := em.spawn(d.id, Vector3(4, 0, 0), _splitter())
	em.force_special = false
	var pk = w["pk"]
	assert_bool(em._special_chest_drop(solo, d, null)).is_true()
	assert_bool(em._special_chest_drop(both, d, _splitter())).is_false()
	assert_int(int(pk.chests)).is_equal(1)


func test_garrys_spider_row_is_forced_special_and_split() -> void:
	# his row as he left it (he may change it in the Level Editor: only checked while it still says so)
	var tl: Dictionary = _json("res://content/maps/red_canyon/red_canyon.json")["timeline_data"]
	for r in tl.get("roster", []):
		if str((r as Dictionary).get("id", "")) == "r68" and bool(r.get("special", false)) and str(r.get("elite", "")) == "splitter":
			assert_str(str(r["enemy"])).is_equal("desert_spider")
			assert_object(Registry.elites.get("splitter")).is_not_null()


# ---------------------------------------------------------------- the three retuned legendaries

func _passive_stat(id: String, level: int, stat: String) -> float:
	var d := _json("res://content/passives/%s/%s.json" % [id, id])
	for e in d["levels"][level]:
		if str(e["stat"]) == stat:
			return float(e["value"])
	return -1.0


func test_the_storm_comes_every_45_s_and_36_evolved() -> void:
	assert_float(_passive_stat("personal_storm", 0, "storm_every")).is_equal(45.0)
	assert_float(_passive_stat("personal_storm", 1, "storm_every")).is_equal(36.0)
	assert_float(float(PersonalStorm.DEFAULTS["every"])).is_equal(45.0)


func test_the_bible_caps_every_hit_at_35_percent_and_30_evolved() -> void:
	assert_float(_passive_stat("pocket_bible", 0, "hit_cap_pct")).is_equal(35.0)
	assert_float(_passive_stat("pocket_bible", 0, "boss_hit_cap_pct")).is_equal(35.0)
	assert_float(_passive_stat("pocket_bible", 1, "hit_cap_pct")).is_equal(30.0)
	assert_float(_passive_stat("pocket_bible", 1, "boss_hit_cap_pct")).is_equal(30.0)


func test_the_horse_comes_every_30_s_with_twice_the_warning_at_three_quarters_the_speed() -> void:
	assert_float(_passive_stat("iron_horse", 0, "train_every")).is_equal(30.0)
	assert_float(_passive_stat("iron_horse", 1, "train_every")).is_equal(22.0)
	var tr: Dictionary = _json("res://content/passives/iron_horse/iron_horse.json")["params"]["train"]
	assert_float(float(tr["rumble"])).is_equal_approx(1.2 * 2.0, 0.001)
	assert_float(float(tr["warn"])).is_equal_approx(1.0 * 2.0, 0.001)
	assert_float(float(tr["speed"])).is_equal_approx(30.0 * 0.75, 0.001)
	assert_float(float(IronHorse.DEFAULTS["speed"])).is_equal(22.5)


# ---------------------------------------------------------------- the row comes before colour is open

func _director(w: Dictionary, row: Dictionary) -> WaveDirector:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline.duplicate(true)
	tl.roster = [row]
	tl.events = []
	tl.waves = []
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = tl
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	w["g"].set("director", d)
	d._apply_mults()
	return d


func _split_row(special: bool) -> Dictionary:
	# Garry's r68 (pass 120), its window at 7:49-7:51
	return {"id": "p120_r68", "t": 469, "until": 471, "enemy": "desert_spider", "weights": [[469, 8.0], [537, 8.0]],
		"pack": 15, "pattern": "scatter", "stats": {"hp_mult": 0.2, "speed": 2.1}, "pace": "once", "count": 3,
		"special": special, "elite": "splitter"}


func test_a_forced_special_elite_row_comes_before_colour_is_open() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var d := _director(w, _split_row(true))
	d.timeline.colour_after_kills = 50
	em.colour_after_kills = 50
	Run.kills = 0
	assert_bool(d.colour_open()).is_false()
	Run.elapsed = 470.0
	for k in range(3):
		d._process_events()
		d._tick_row_waves()
	var specials := 0
	var split := 0
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 1 and em.state[i] != EnemyManager.STATE_DYING:
			specials += int(em.vspecial[i])
			if em.elite_idx[i] >= 0 and (em.elites[em.elite_idx[i]] as EliteModDef).id == "splitter":
				split += 1
	assert_int(specials).is_equal(3)
	assert_int(split).is_equal(3)


func test_a_plain_elite_row_still_waits_for_colour() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var d := _director(w, _split_row(false))
	d.timeline.colour_after_kills = 50
	em.colour_after_kills = 50
	Run.kills = 0
	Run.elapsed = 470.0
	for k in range(3):
		d._process_events()
		d._tick_row_waves()
	assert_int(em.count_alive).is_equal(0)
