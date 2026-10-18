extends GdUnitTestSuite

## Pass 88, lane MIRROR (Garry: "The following should be removed: LifeSteal, Thorns. To be replaced by 1. Difficulty -
## Increases regular enemies movement speed, HP and ATK and increases the coins and exp (we don't write that in the
## description, and it's less than the difficulty increase) 2. BOSS - Increases Boss (and Elites) movement speed, HP and
## ATK and increases the coins and exp ... reassess the pricing of the Upgrades ... the ones who's first upgrade is the
## cheapest go on top and the most expensive on the bottom"). Spite is Stakes: Difficulty and Boss (MirrorDanger); its
## numbers are read from the talent's JSON, never pinned here (Garry tunes them).

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

const HS := preload("res://ui/HomesteadScreen.gd")

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Save.data = Save._default()
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


## The run started with `picks` ranks of Stakes ([0, 0] = two Difficulty ranks; [] = none).
func _start_with(picks: Array) -> void:
	Run.end()
	Save.data["talents"] = {} if picks.is_empty() else {"spite": {"picks": picks}}
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false


## 1 + ranks x the form's per-rank value of `stat`, as the talent's JSON says.
func _want(form: int, stat: String, ranks: int) -> float:
	var td: TalentDef = Registry.talent("spite")
	var v := 0.0
	for e in td.effects_for(form, ranks):
		if (e as Effect).stat == stat:
			v += (e as Effect).value
	return 1.0 + v


func _per_rank(form: int, stat: String) -> float:
	return _want(form, stat, 1) - 1.0


# ---------------------------------------------------------------- 1. the talent

func test_spite_is_stakes_with_difficulty_and_boss_and_no_thorns_or_thirst() -> void:
	var td: TalentDef = Registry.talent("spite")
	assert_object(td).is_not_null()
	assert_str(td.display_name).is_equal("Stakes")
	assert_str(td.form_name(0)).is_equal("Difficulty")
	assert_str(td.form_name(1)).is_equal("Boss")
	for form in range(2):
		for e in td.effects_for(form, 1):
			assert_bool((e as Effect).stat in ["thorns", "lifesteal"]).is_false()
	# the danger on each form, the bounty on each, and the bounty below every danger it pays for
	for form in range(2):
		var pre := "danger_" if form == 0 else "boss_danger_"
		var bounty := _per_rank(form, pre + "bounty")
		assert_float(bounty).override_failure_message("form %d pays nothing" % form).is_greater(0.0)
		for what in ["hp", "attack", "speed"]:
			assert_float(_per_rank(form, pre + what)).override_failure_message("form %d %s" % [form, what]).is_greater(0.0)
		for what in ["hp", "attack"]:
			assert_float(bounty).override_failure_message("form %d: the bounty is not below its %s" % [form, what]).is_less(_per_rank(form, pre + what))


func test_the_words_say_the_danger_and_never_the_reward() -> void:
	var td: TalentDef = Registry.talent("spite")
	for form in range(2):
		var t := td.form_text(form).to_lower()
		var said := TextGen.describe_effects(td.summed_effects(form, 3)).to_lower()
		for word in ["coin", "gold", "xp", "exp", "bounty", "reward"]:
			assert_bool(t.contains(word)).override_failure_message("form %d's text says %s" % [form, word]).is_false()
			assert_bool(said.contains(word)).override_failure_message("form %d's sum says %s" % [form, word]).is_false()
		assert_str(said).contains("hp")
	assert_str(TextGen.describe_effect(Effect.make("danger_bounty", "add", 0.05, "player"))).is_empty()
	assert_str(TextGen.describe_effect(Effect.make("boss_danger_bounty", "add", 0.05, "player"))).is_empty()
	assert_bool(StatSources.listable("danger_bounty")).is_false()
	assert_str(TextGen.describe_effect(Effect.make("danger_hp", "add", 0.1, "player"))).is_equal("+10% enemy HP")


# ---------------------------------------------------------------- 2. the creatures

func test_difficulty_makes_a_regular_creature_tougher_faster_and_richer() -> void:
	_plain_def("t88_skel", "skeleton")
	_start_with([])
	var em := _world()
	var a := em.spawn("t88_skel", Vector3(-5, 0, 0))
	var hp0: float = em.max_hp[a]
	var sp0: float = em.speed[a]
	var dm0: float = em.dmg[a]
	var xp0: float = em.xp_scale[a]
	var host0: float = em.host_of(a)
	_start_with([0, 0, 0])
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
	_start_with([])
	var em := _world()
	var s0 := em.spawn("t88_skel", Vector3(-5, 0, 0))
	var g0 := em.spawn("t88_golem", Vector3(5, 0, 0))
	var shp: float = em.max_hp[s0]
	var ghp: float = em.max_hp[g0]
	var gsp: float = em.speed[g0]
	# Difficulty: the Elite is as it was
	_start_with([0, 0])
	em.refresh_player_stats()
	var g1 := em.spawn("t88_golem", Vector3(5, 0, 6))
	assert_float(em.max_hp[g1]).is_equal_approx(ghp, 0.001)
	assert_float(em.speed[g1]).is_equal_approx(gsp, 0.001)
	# Boss: the Elite is tougher and faster, the crowd as it was
	_start_with([1, 1])
	em.refresh_player_stats()
	var g2 := em.spawn("t88_golem", Vector3(5, 0, 12))
	var s2 := em.spawn("t88_skel", Vector3(-5, 0, 12))
	assert_float(em.max_hp[g2] / ghp).is_equal_approx(_want(1, "boss_danger_hp", 2), 0.001)
	assert_float(em.speed[g2] / gsp).is_equal_approx(_want(1, "boss_danger_speed", 2), 0.001)
	assert_float(em.xp_scale[g2] / em.xp_scale[g0]).is_equal_approx(_want(1, "boss_danger_bounty", 2), 0.001)
	assert_float(em.max_hp[s2]).is_equal_approx(shp, 0.001)


func test_the_boss_form_multiplies_after_the_seconds_floor() -> void:
	_start_with([1, 1, 1])
	var em := _world()
	# the seconds mode's floor far over the data HP: the floor rules, then the Boss form on top
	em.boss_hp_target = 1000000.0
	var b := em.spawn("tumbleweed_king", Vector3(0, 0, 0))
	assert_int(b).is_greater_equal(0)
	assert_float(em.max_hp[b]).is_equal_approx(1000000.0 * _want(1, "boss_danger_hp", 3), 1.0)


func test_nothing_changes_in_the_arena() -> void:
	_plain_def("t88_skel", "skeleton")
	_start_with([0, 0, 0, 0])
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


# ---------------------------------------------------------------- 4. an old save's Spite

func test_an_old_saves_thorns_and_thirst_come_back_in_full_once() -> void:
	Save.data["gold"] = 100
	Save.data["talents"] = {"spite": {"picks": [0, 1, 0]}, "grit": {"picks": [0]}}
	Save.data["talent_spent"] = 2900 + 350
	var back: int = Save._migrate_stakes()
	assert_int(back).is_equal(500 + 900 + 1500)
	assert_int(Save.gold()).is_equal(100 + 2900)
	assert_bool((Save.data["talents"] as Dictionary).has("spite")).is_false()
	assert_int(Save.talent_rank("grit")).is_equal(1)
	assert_int(Save.talent_spent()).is_equal(350)
	assert_str(str(Save.board_note().get("kind", ""))).is_equal("stakes_refund")
	assert_array(HS.note_words(Save.board_note())).contains(["+2,900 GOLD BACK FOR 3 RANKS"])
	# once: a second load pays nothing
	assert_int(Save._migrate_stakes()).is_equal(0)
	assert_int(Save.gold()).is_equal(3000)
	Save.clear_board_note()
	assert_bool(Save.board_note().is_empty()).is_true()


func test_a_new_save_and_a_stakes_rank_are_never_paid_back() -> void:
	assert_int(Save._migrate_stakes()).is_equal(0)
	assert_bool(Save.once(Save.STAKES_ONCE)).is_true()
	# a save wiped since its load: buying a Stakes rank marks it, so the next load keeps the rank
	Save.data = Save._default()
	Save.add_gold(100000)
	assert_bool(Save.buy_talent(Registry.talent("spite"), 0)).is_true()
	assert_bool(Save.once(Save.STAKES_ONCE)).is_true()
	assert_int(Save._migrate_stakes()).is_equal(0)
	assert_int(Save.talent_rank("spite")).is_equal(1)


# ---------------------------------------------------------------- 5. the order

func test_the_board_lists_the_cheapest_first_rank_first() -> void:
	var list := Registry.talents_list()
	assert_int(list.size()).is_equal(8)
	for k in range(1, list.size()):
		var a: TalentDef = list[k - 1]
		var b: TalentDef = list[k]
		assert_int(a.first_price()).override_failure_message("%s before %s" % [a.id, b.id]).is_less_equal(b.first_price())
	# the JSON's `order` agrees with the prices (it breaks ties)
	for k in range(list.size()):
		assert_int((list[k] as TalentDef).order).override_failure_message((list[k] as TalentDef).id).is_equal(k + 1)
	# the Stakes are a choice for gold and challenge: the cheapest
	assert_str((list[0] as TalentDef).id).is_equal("spite")
