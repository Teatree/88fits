extends GdUnitTestSuite

## Pass 110, lane ECON (Garry, 2026-10-28: "Reduce the number of chests to make them feel more special. Basically make
## it so the chance of Chest falling out of a normal enemy is next to nothing while the Special versions of those enemies
## still guarantee a chest. Since that's the case let's reduce the number of Specials in the end. Increase ATK of
## Specials quite a bit." and "Reduce the coins gain from Boss, Elite and Specials. By 50%. Mirror costs should be more
## exponential (Polynomial) while the increases stay the same. Starting point prices should stay the same though.
## Normalize the Hero costs as well. And increase them."). Pinned here: every regular creature's chest at REGULAR_CHEST
## (Elites keep theirs); a special whose chest chance is 1 always drops one, one special at a time, a third of pass 69's
## chance again, ATK x3.5; the Elite and boss purses, the bosses' coins and the big coin halved, a special's own coin half
## as often; the Upgrade board's rank k at k x k times rank 1 (rank 1 as pass 88 priced it, the per-rank effects
## untouched), an old save's ranks kept and its refund half of what it paid; every hero on sale at 500 x his title place.

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
func spawn_special(_def, _at, _quiet = false) -> void:
	pass
func spawn_chest(_at, _boss = false) -> void:
	chests += 1
func spawn(_k, _at, _v = 0.0) -> int:
	return -1
"""

## Every regular creature's drops.chest (about one chest in 5,000 kills).
const REGULAR_CHEST := 0.0002
## Each talent's first rank as pass 88 priced it ("Starting point prices should stay the same").
const FIRST_RANK := {"choice": 325, "drive": 375, "fortune": 300, "grit": 450, "nerve": 500, "spite": 100, "stride": 425,
	"study": 400}
## A hero on sale costs this much gold for each place in the title order (Ironwood, 2nd, 1,000; May, 8th, 4,000).
const HERO_STEP := 500

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
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
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


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
	hero.global_position = Vector3(0, 0, 80)
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
	em.colour_after_kills = 0
	return {"g": g, "em": em, "pk": pk}


## A test creature `id` made from `from`, its variance block `vr`, no drops; gone after the test.
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


## Every creature's own JSON (content/enemies/<id>/<id>.json), by id.
func _creature_files() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://content/enemies")
	for id: String in dir.get_directories():
		var p := "res://content/enemies/%s/%s.json" % [id, id]
		if FileAccess.file_exists(p):
			out[id] = _json(p)
	return out


# ---------------------------------------------------------------- 1. chests

func test_a_regular_creature_drops_a_chest_next_to_never_and_an_elite_always() -> void:
	var regular := 0
	var elites := 0
	for id: String in _creature_files().keys():
		var d: Dictionary = _creature_files()[id]
		if str(d.get("brain", "")) == "dummy" or not (d.get("drops", {}) as Dictionary).has("chest"):
			continue
		var chest := float(d["drops"]["chest"])
		if str(d.get("archetype", "")) == "elite":
			assert_float(chest).override_failure_message(id + " (an Elite)").is_equal(1.0)
			elites += 1
		else:
			assert_float(chest).override_failure_message(id).is_equal_approx(REGULAR_CHEST, 0.000001)
			# and the .tres the game plays says the same
			assert_float(float(Registry.enemy(id).drops.get("chest", -1.0))).override_failure_message(id + " .tres").is_equal_approx(REGULAR_CHEST, 0.000001)
			regular += 1
	assert_int(regular).is_greater_equal(25)
	assert_int(elites).is_greater_equal(3)


func test_a_special_with_a_sure_chest_always_drops_one() -> void:
	var sp := _test_def("p110_c1", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {}})
	var w := _world()
	var em: EnemyManager = w["em"]
	var pk: Node = w["pk"]
	em.special_defaults = {"chest_chance": 1.0, "max_alive": 0}
	for k in range(40):
		var i := em.spawn(sp.id, Vector3(float(k % 10) * 2.0 - 10.0, 0, float(k / 10) * 2.0))
		assert_int(em.vspecial[i]).is_equal(1)
		em.damage(i, 1e9)
		em._free(i)
	assert_int(int(pk.chests)).is_equal(40)
	assert_int(em.special_chests).is_equal(40)


func test_red_canyon_plays_its_own_special_numbers() -> void:
	# Garry tunes these in the Level Editor (Settings -> Coloured specials): what applies is the map file's
	var raw: Dictionary = _json("res://content/maps/red_canyon/red_canyon.json")["timeline_data"]
	var spd: Dictionary = raw.get("special_defaults", {})
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for key: String in ["chest_chance", "damage"]:
		if spd.has(key):
			assert_float(EnemyDef.special_value({}, tl.special_defaults, key)).override_failure_message(key).is_equal_approx(float(spd[key]), 0.0001)
	if spd.has("max_alive"):
		assert_int(EnemyDef.special_max_alive(tl.special_defaults)).is_equal(int(spd["max_alive"]) if int(spd["max_alive"]) > 0 else -1)


func test_one_special_at_a_time_on_a_cap_of_one() -> void:
	var sp := _test_def("p110_cap", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {}})
	var w := _world()
	var em: EnemyManager = w["em"]
	em.special_defaults = {"max_alive": 1}
	var made: Array = []
	for k in range(4):
		made.append(em.spawn(sp.id, Vector3(float(k) * 2.5 - 5.0, 0, 0)))
	var specials := 0
	for i: int in made:
		specials += em.vspecial[i]
	assert_int(specials).is_equal(1)
	assert_int(em.specials_alive).is_equal(1)
	# it dies: the next roll may make the next one
	em.damage(made[0], 1e9)
	assert_int(em.specials_alive).is_equal(0)
	assert_int(em.vspecial[em.spawn(sp.id, Vector3(0, 0, 6))]).is_equal(1)


func test_every_coloured_special_is_rarer_again_and_hits_three_and_a_half_times_as_hard() -> void:
	var seen := 0
	var files := _creature_files()
	for id: String in files.keys():
		var vr = (files[id] as Dictionary).get("variance", {})
		if not (vr is Dictionary) or not (vr as Dictionary).has("special"):
			continue
		var chance := float((vr as Dictionary).get("special_chance", 0.0))
		# a ninth of pass 69's 0.12 at most (pass 69 took a third, pass 110 a third again)
		assert_float(chance).override_failure_message(id + " chance").is_less_equal(0.0134)
		var sp: Dictionary = vr["special"]
		var dmg := EnemyDef.special_value(sp, Registry.map("red_canyon").timeline.special_defaults, "damage")
		assert_float(dmg).override_failure_message(id + " ATK x").is_equal(3.5)
		seen += 1
	assert_int(seen).is_greater_equal(22)


func test_a_special_red_goblin_bites_for_three_and_a_half_times_a_plain_one() -> void:
	var gob: EnemyDef = Registry.enemy("red_goblin")
	var vr: Dictionary = gob.variance.duplicate(true)
	vr["size"] = 0.0
	vr["special_chance"] = 1.0
	var sp := _test_def("p110_rg", "red_goblin", vr)
	var plain_vr: Dictionary = vr.duplicate(true)
	plain_vr["special_chance"] = 0.0
	var pl := _test_def("p110_rgp", "red_goblin", plain_vr)
	var w := _world()
	var em: EnemyManager = w["em"]
	em.special_defaults = Registry.map("red_canyon").timeline.special_defaults.duplicate()
	em.special_defaults["max_alive"] = 0
	var i := em.spawn(sp.id, Vector3(0, 0, 0))
	var j := em.spawn(pl.id, Vector3(3, 0, 0))
	assert_int(em.vspecial[i]).is_equal(1)
	assert_int(em.vspecial[j]).is_equal(0)
	# its bite, its shots and its throws all read dmg[] (contact still capped at the map's contact_cap of his health)
	assert_float(em.dmg[i] / em.dmg[j]).is_equal_approx(3.5, 0.0001)
	assert_float(em.max_hp[i] / em.max_hp[j]).is_equal_approx(15.0, 0.0001)


# ---------------------------------------------------------------- 2. coins

func test_the_elite_and_boss_gold_is_half_of_pass_70s() -> void:
	for s in 4:
		assert_int(Game.elite_purse(s)).is_equal((450 + 300 * s) / 2)
		assert_int(Game.boss_purse(s)).is_equal((1300 + 700 * s) / 2)
	assert_int(Game.BOSS_COINS).is_equal(30)
	assert_float(PickupManager.BIG_COIN_MULT).is_equal(2.5)
	assert_float(PickupManager.SPECIAL_COIN_MULT).is_equal(0.5)
	# the bosses' coins on the sand, half of pass 70's 60 / 150 / 200
	var half := {"tumbleweed_king": 30, "gila_grande": 75, "brander": 100}
	for id: String in half.keys():
		assert_int(int(Registry.enemy(id).drops.get("coins", 0))).override_failure_message(id).is_equal(int(half[id]))


func test_a_coin_factor_scales_the_chance_of_the_coin() -> void:
	var def := EnemyDef.new()
	def.id = "p110_coin"
	def.drops = {"gold": 1.0}
	var luck: float = Run.player_sheet.get_stat("luck", 0.0)
	var n := 1500
	var got: Array = []
	for mult: float in [1.0, PickupManager.SPECIAL_COIN_MULT, 0.0]:
		var pm: PickupManager = auto_free(PickupManager.new())
		add_child(pm)
		seed(1100)
		for k in range(n):
			pm.drop_from(def, Vector3(float(k % 40), 0, float(k / 40)), 1.0, false, mult)
		var coins := 0
		for i in range(pm.alive.size()):
			if pm.alive[i] == 1 and pm.kind[i] == PickupManager.KIND_COIN:
				coins += 1
		got.append(float(coins) / float(n))
	assert_float(float(got[0])).is_equal_approx(minf(1.0 + luck, 1.0), 0.02)
	assert_float(float(got[1])).is_equal_approx(minf((1.0 + luck) * 0.5, 1.0), 0.05)
	assert_float(float(got[2])).is_equal(0.0)


func test_a_dying_special_says_so_while_its_death_is_paid() -> void:
	var sp := _test_def("p110_ds", "skeleton", {"size": 0.0, "special_chance": 1.0, "special": {}})
	var pl := _test_def("p110_dp", "skeleton", {"size": 0.0, "special_chance": 0.0})
	var w := _world()
	var em: EnemyManager = w["em"]
	em.special_defaults = {"max_alive": 0, "chest_chance": 0.0}
	var seen: Array = []
	em.enemy_died.connect(func(_d, _p, _e, _w): seen.append(em.died_special))
	em.damage(em.spawn(sp.id, Vector3(0, 0, 0)), 1e9)
	em.damage(em.spawn(pl.id, Vector3(3, 0, 0)), 1e9)
	assert_array(seen).is_equal([true, false])
	assert_bool(em.died_special).is_false()
	# and Game hands that factor to the drop
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(src).contains("PickupManager.SPECIAL_COIN_MULT if enemies and enemies.died_special else 1.0")


# ---------------------------------------------------------------- 3. the Upgrade board

func test_every_talents_rank_k_costs_k_squared_times_its_first() -> void:
	assert_int(Registry.talents_list().size()).is_equal(8)
	for td: TalentDef in Registry.talents_list():
		assert_int(int(td.cost[0])).override_failure_message(td.id + " first rank").is_equal(int(FIRST_RANK[td.id]))
		for k in range(td.ranks):
			assert_int(td.cost_of_rank(k)).override_failure_message("%s rank %d" % [td.id, k + 1]).is_equal(int(td.cost[0]) * (k + 1) * (k + 1))
	# the increases stay: Grit's Padding is still +10% max HP a rank, Drive's Muscle +6% damage
	var grit: TalentDef = Registry.talent("grit")
	var e: Effect = (grit.forms[0] as Dictionary)["effects"][0]
	assert_str(e.stat).is_equal("max_hp")
	assert_float(e.value).is_equal_approx(0.1, 0.0001)
	assert_int(grit.effects_for(0, 3).size()).is_equal(3)
	var mu: Effect = (Registry.talent("drive").forms[0] as Dictionary)["effects"][0]
	assert_float(mu.value).is_equal_approx(0.06, 0.0001)


func test_ranks_bought_at_the_old_prices_stay_and_refund_half_of_what_was_paid() -> void:
	var grit: TalentDef = Registry.talent("grit")
	# an older save: two ranks of Grit bought at pass 88's 450 + 810
	Save.data["talents"] = {"grit": {"picks": [0, 1], "rank": 2, "form": 1}}
	Save.data["talent_spent"] = 450 + 810
	Save.data["gold"] = 5000
	assert_int(Save.talent_rank("grit")).is_equal(2)
	# the next rank is the third at the new price
	assert_int(grit.cost_of_rank(Save.talent_rank("grit"))).is_equal(450 * 9)
	assert_bool(Save.buy_talent(grit, 0)).is_true()
	assert_int(Save.gold()).is_equal(5000 - 4050)
	assert_array(Save.talent_picks("grit")).is_equal([0, 1, 0])
	assert_int(Save.talent_spent()).is_equal(1260 + 4050)
	# Take it all back: half of what was really paid, never of today's prices
	assert_int(Save.talent_refund()).is_equal(int(floor((1260 + 4050) * Save.REFUND_FRAC)))


# ---------------------------------------------------------------- 4. heroes

func test_every_hero_on_sale_costs_500_a_place_in_the_title_order() -> void:
	var on_sale := 0
	for c: CharacterDef in Registry.sorted_characters():
		if c.hidden or c.availability != "purchase":
			continue
		assert_int(c.price).override_failure_message("%s (place %d)" % [c.id, c.order]).is_equal(HERO_STEP * c.order)
		assert_str(c.currency_type).is_equal("gold")
		on_sale += 1
	assert_int(on_sale).is_equal(7)
	# the Drifter free, Mira and Dad out of sale as before
	assert_int(Registry.character("drifter").price).is_equal(0)
	assert_str(Registry.character("drifter").availability).is_equal("available")
	assert_bool(Registry.character("mira").hidden).is_true()
	assert_bool(Registry.character("dad").hidden).is_true()
	# every one dearer than before pass 110 (300, 300, 300, 1500, 1750, 2000, 2500)
	var old := {"ironwood": 300, "astro": 300, "calavera": 300, "solenne": 1500, "fadeaway": 1750, "buck": 2000, "may": 2500}
	for id: String in old.keys():
		assert_int(Registry.character(id).price).override_failure_message(id).is_greater(int(old[id]))


func test_a_hero_is_still_bought_at_his_new_price() -> void:
	var iw: CharacterDef = Registry.character("ironwood")
	assert_str(Registry.hero_state(iw)).is_equal("buyable")
	Save.data["gold"] = iw.price - 1
	assert_bool(Save.buy_hero(iw)).is_false()
	assert_bool(Save.owns_hero("ironwood")).is_false()
	Save.data["gold"] = iw.price + 7
	assert_bool(Save.buy_hero(iw)).is_true()
	assert_int(Save.gold()).is_equal(7)
	assert_str(Registry.hero_state(iw)).is_equal("owned")
