extends GdUnitTestSuite

## Pass 88, lane MIRROR (Garry: "The following should be removed: LifeSteal, Thorns. To be replaced by 1. Difficulty -
## Increases regular enemies movement speed, HP and ATK and increases the coins and exp (we don't write that in the
## description, and it's less than the difficulty increase) 2. BOSS - Increases Boss (and Elites) movement speed, HP and
## ATK and increases the coins and exp ... reassess the pricing of the Upgrades ... the ones who's first upgrade is the
## cheapest go on top and the most expensive on the bottom"). The Stakes are MirrorDanger's two families of stats.
## Pass 129: the Upgrade board is gone; the Trail's optional Stakes nodes (upgrade types `stakes` and `boss_stakes`) feed
## the same stats, so these cases buy those nodes. Their numbers are read from content/trail/trail.json, never pinned
## here (Garry tunes them). The board's own cases (its words, its order, Spite's old refund) left with the board.

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
var director = null
var no_random_chests := true
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

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Trail.load_from()
	Trail.refresh()
	Run.arena = false


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Save.data = Save._default()
	Trail.refresh()
	Run.arena = false
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> EnemyManager:
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
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	# no colour: no special, no tint (a special's x15 HP would hide the factor)
	em.colour_after_kills = 1000000
	return em


## A creature `id` made from `from` with no jitter and no variance; gone after the test.
func _plain_def(id: String, from: String) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = {}
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	d.size_range = Vector2.ZERO
	Registry.enemies[id] = d
	_added.append(id)
	return d


## The upgrade type of a family: 0 = the regular creatures' Stakes, 1 = the bosses' and Elites'.
const TYPES := ["stakes", "boss_stakes"]


## The ids of the Trail's first `n` nodes that give upgrade `type`, in file order.
func _stake_ids(type: String, n: int) -> Array:
	var out: Array = []
	for nd: Dictionary in Trail.nodes():
		var g: Dictionary = nd["gives"]
		if out.size() < n and str(g.get("type", "")) == "upgrade" and str(g.get("upgrade", "")) == type:
			out.append(str(nd["id"]))
	return out


## The run started with the Trail's first `regular` Stakes nodes and first `big` Boss Stakes nodes bought (0, 0 = none).
func _start_with(regular: int, big: int = 0) -> void:
	Run.end()
	var ids: Array = _stake_ids("stakes", regular)
	ids.append_array(_stake_ids("boss_stakes", big))
	assert_int(ids.size()).is_equal(regular + big)
	Save.data["trail"] = {"bought": ids, "spent": 0, "had": []}
	Trail.refresh()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false


## 1 + what the first `n` nodes of family `form` (TYPES) add to `stat`: each node's value x the type's `per` for it.
func _want(form: int, stat: String, n: int) -> float:
	var type: String = TYPES[form]
	var per := 0.0
	for e: Dictionary in Trail.upgrade(type).get("effects", []):
		if str(e.get("stat", "")) == stat:
			per = float(e.get("per", 1.0))
	var v := 0.0
	for id: String in _stake_ids(type, n):
		v += float((Trail.node(id)["gives"] as Dictionary)["value"]) * per
	return 1.0 + v


# ---------------------------------------------------------------- 1. the Trail's Stakes nodes

func test_the_trail_has_optional_stakes_nodes_for_both_families() -> void:
	for type: String in TYPES:
		var ids := _stake_ids(type, 99)
		assert_int(ids.size()).is_greater_equal(2)
		for id: String in ids:
			assert_str(str(Trail.node(id)["kind"])).is_equal("optional")
	assert_float(_want(0, "danger_hp", 1)).is_greater(1.0)
	assert_float(_want(1, "boss_danger_hp", 1)).is_greater(1.0)


## Garry (pass 88): the Stakes pay more coins and XP, and "we don't write that in the description". The board's test of
## it went with the board; the Trail's two upgrade types keep the rule (pass 129): their words, their warning, a
## node's give text and the stats' own text never name the reward.
func test_the_words_say_the_danger_and_never_the_reward() -> void:
	for type: String in TYPES:
		var u: Dictionary = Trail.upgrade(type)
		var id: String = _stake_ids(type, 1)[0]
		var said := "%s | %s | %s | %s" % [str(u.get("name", "")), str(u.get("text", "")), str(u.get("warn", "")),
				Trail.give_text(Trail.node(id))]
		said = said.to_lower()
		for word in ["coin", "gold", "xp", "exp", "bounty", "reward", "paid", "pay"]:
			assert_bool(said.contains(word)).override_failure_message("%s's words say %s: %s" % [type, word, said]).is_false()
		assert_str(said).contains("tougher")
	assert_str(TextGen.describe_effect(Effect.make("danger_bounty", "add", 0.05, "player"))).is_empty()
	assert_str(TextGen.describe_effect(Effect.make("boss_danger_bounty", "add", 0.05, "player"))).is_empty()


func test_difficulty_makes_a_regular_creature_tougher_faster_and_richer() -> void:
	_plain_def("t88_skel", "skeleton")
	_start_with(0)
	var em := _world()
	var a := em.spawn("t88_skel", Vector3(-5, 0, 0))
	var hp0: float = em.max_hp[a]
	var sp0: float = em.speed[a]
	var dm0: float = em.dmg[a]
	var xp0: float = em.xp_scale[a]
	var host0: float = em.host_of(a)
	_start_with(3)
	em.refresh_player_stats()
	var b := em.spawn("t88_skel", Vector3(5, 0, 0))
	assert_float(em.max_hp[b] / hp0).is_equal_approx(_want(0, "danger_hp", 3), 0.001)
	assert_float(em.speed[b] / sp0).is_equal_approx(_want(0, "danger_speed", 3), 0.001)
	assert_float(em.dmg[b] / dm0).is_equal_approx(_want(0, "danger_attack", 3), 0.001)
	assert_float(em.xp_scale[b] / xp0).is_equal_approx(_want(0, "danger_bounty", 3), 0.001)
	# every hit it throws (host_of) carries the attack factor too
	assert_float(em.host_of(b) / host0).is_equal_approx(_want(0, "danger_attack", 3), 0.001)


func test_difficulty_leaves_bosses_and_elites_and_boss_leaves_the_crowd() -> void:
	_plain_def("t88_skel", "skeleton")
	_plain_def("t88_golem", "stone_golem")
	_start_with(0)
	var em := _world()
	var s0 := em.spawn("t88_skel", Vector3(-5, 0, 0))
	var g0 := em.spawn("t88_golem", Vector3(5, 0, 0))
	var shp: float = em.max_hp[s0]
	var ghp: float = em.max_hp[g0]
	var gsp: float = em.speed[g0]
	# Difficulty: the Elite is as it was
	_start_with(2)
	em.refresh_player_stats()
	var g1 := em.spawn("t88_golem", Vector3(5, 0, 6))
	assert_float(em.max_hp[g1]).is_equal_approx(ghp, 0.001)
	assert_float(em.speed[g1]).is_equal_approx(gsp, 0.001)
	# Boss: the Elite is tougher and faster, the crowd as it was
	_start_with(0, 2)
	em.refresh_player_stats()
	var g2 := em.spawn("t88_golem", Vector3(5, 0, 12))
	var s2 := em.spawn("t88_skel", Vector3(-5, 0, 12))
	assert_float(em.max_hp[g2] / ghp).is_equal_approx(_want(1, "boss_danger_hp", 2), 0.001)
	assert_float(em.speed[g2] / gsp).is_equal_approx(_want(1, "boss_danger_speed", 2), 0.001)
	assert_float(em.xp_scale[g2] / em.xp_scale[g0]).is_equal_approx(_want(1, "boss_danger_bounty", 2), 0.001)
	assert_float(em.max_hp[s2]).is_equal_approx(shp, 0.001)


func test_the_boss_form_multiplies_after_the_seconds_floor() -> void:
	_start_with(0, 3)
	var em := _world()
	# the seconds mode's floor far over the data HP: the floor rules, then the Boss form on top
	em.boss_hp_target = 1000000.0
	var b := em.spawn("tumbleweed_king", Vector3(0, 0, 0))
	assert_int(b).is_greater_equal(0)
	assert_float(em.max_hp[b]).is_equal_approx(1000000.0 * _want(1, "boss_danger_hp", 3), 1.0)


func test_nothing_changes_in_the_arena() -> void:
	_plain_def("t88_skel", "skeleton")
	_start_with(4)
	Run.arena = true
	assert_float(MirrorDanger.factor(false, "hp")).is_equal(1.0)
	assert_float(MirrorDanger.factor(true, "bounty")).is_equal(1.0)
	Run.arena = false
	assert_float(MirrorDanger.factor(false, "hp")).is_equal_approx(_want(0, "danger_hp", 4), 0.001)
	assert_float(MirrorDanger.factor(true, "hp")).is_equal(1.0)


# ---------------------------------------------------------------- 3. the coins

func test_a_coin_pays_its_bounty_on_average() -> void:
	# 2 coins x1.1 = 2.2: 2, or 3 when the dice fall under 0.2
	assert_int(MirrorDanger.scaled_count(2.0, 1.1, 0.5)).is_equal(2)
	assert_int(MirrorDanger.scaled_count(2.0, 1.1, 0.1)).is_equal(3)
	assert_int(MirrorDanger.scaled_count(3.0, 1.0, 0.0)).is_equal(3)
	assert_int(MirrorDanger.scaled_count(0.0, 1.5, 0.0)).is_equal(0)
	var sum := 0
	for k in range(4000):
		sum += MirrorDanger.scaled_count(2.0, 1.25)
	assert_float(float(sum) / 4000.0).is_equal_approx(2.5, 0.08)
