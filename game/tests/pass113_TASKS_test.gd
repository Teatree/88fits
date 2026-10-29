## Pass 113, lane TASKS (Garry: "Add the following task types everywhere in the game where we have tasks: Deal N Damage
## with Weapon, Restore N HP with Item, Restore N HP with (Heal Power-up, Structure), Upgrade Item to N Level, Destroy N
## Barrels, Claim N Totems, Deal N Poison/Fire damage"): core/systems/TaskTally.gd, the six new quest conditions, the
## seven new Wanted types (BALANCING.md 56.TASKS).
##  1. every new quest type completes, shows its progress and says its words; "in one run" counts only that run;
##  2. damage with a weapon counts its family (the weapon and its evolution), never another weapon's;
##  3. fire and poison: a burn's and a poison's ticks count, a plain hit and a hostile one never;
##  4. a heal is split among the items by their share of the healing stat; an evolved card counts for its source;
##  5. the real game credits the Heart, the Healing Well, a Cake Slice, life steal, regen, barrels and Totem gifts;
##  6. the run's tallies reach the save once, at the run's end, and never from the arena, the run sim or a tool;
##  7. the Wanted posters of the new types: targets only from what the run can get, N within an item's own levels and a
##     map's Totem Poles, their progress, their pictures; a quest's picture resolves like a poster's.
extends GdUnitTestSuite

const MAP := "red_canyon"
const NEW_QUESTS := ["damage_with_weapon", "heal_with_item", "heal_with_source", "element_damage", "barrels_total", "totems_total"]
const NEW_WANTED := ["damage_weapon", "heal_item", "heal_source", "item_level", "barrels", "totems", "element_damage"]

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
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_fire(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_poison(_a) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func heal(_a: float, _s: String = "", _c: String = "") -> void:
	pass
"""

const FAKE_PICKUPS := """extends Node
func spawn(_kind: int, _at: Vector3, _v: float) -> int:
	return 0
func spawn_chest(_at: Vector3, _boss: bool = false) -> void:
	pass
func add_attractor(_p: Vector3, _r: float) -> void:
	pass
"""


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	Run.sim_mode = false
	TaskTally.bank_in_tools = true
	WantedBoard.set_config({})


func after_test() -> void:
	TaskTally.bank_in_tools = false
	WantedBoard.set_config({})
	WantedRun.current = null
	get_tree().paused = false
	Run.arena = false
	Run.sim_mode = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map(MAP))
	Run.start_stage(0)


func _quest(cond: Dictionary) -> QuestDef:
	var q := QuestDef.new()
	q.id = "t_task"
	q.condition = cond
	q.unlocks = {"type": "mode", "id": "t_task"}
	return q


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A crowd world on a stand-in game (a real EnemyManager and Fx): its manager.
func _world() -> EnemyManager:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = Vector3(60, 0, 60)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	em._rebuild_grid()
	return em


func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _game() -> Game:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": MAP, "map_seed": 11, "analytics": false})
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _meet_everything() -> void:
	for id in Registry.enemies.keys():
		Save.mark_seen("enemy", str(id))
	for id in Registry.weapons.keys():
		Save.mark_seen("weapon", str(id))
	for id in Registry.passives.keys():
		Save.mark_seen("passive", str(id))


# ---------------------------------------------------------------- 1 and 2: the quests, their words, the family rule

func test_damage_with_a_weapon_counts_its_family_across_runs() -> void:
	var q := _quest({"type": "damage_with_weapon", "weapon": "revolver", "count": 1000})
	var evo := Registry.weapon("revolver").evolves_into
	assert_str(evo).is_not_empty()
	_start()
	Run.add_damage("revolver", 600.0)
	Run.add_damage("boomstick", 5000.0)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(600, 1000))
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	# the evolution is the same family; another weapon never counts
	Run.add_damage(evo, 500.0)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(1100, 1000))
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	# an evolution named in the condition counts the same family
	var qe := _quest({"type": "damage_with_weapon", "weapon": evo, "count": 1000})
	assert_object(QuestTracker.progress(qe)).is_equal(Vector2i(1100, 1000))
	assert_str(TextGen.quest_text(q)).is_equal("Deal 1,000 damage with the Revolver.")
	assert_int(QuestTracker.stage_hint(q)).is_equal(1)
	# banked once at the run's end; the run's part is not counted twice
	assert_bool(TaskTally.bank()).is_true()
	assert_bool(TaskTally.bank()).is_false()
	assert_int(Save.keyed_total(TaskTally.SAVE_DAMAGE, "revolver")).is_equal(1100)
	assert_int(Save.keyed_total(TaskTally.SAVE_DAMAGE, "boomstick")).is_equal(5000)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(1100, 1000))
	Run.end()
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(1100, 1000))
	# a later run adds to it while it goes on
	_start()
	Run.add_damage("revolver", 50.0)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(1150, 1000))


func test_in_one_run_counts_only_that_run() -> void:
	Save.add_keyed_total(TaskTally.SAVE_DAMAGE, "revolver", 900)
	var q := _quest({"type": "damage_with_weapon", "weapon": "revolver", "count": 1000, "in_one_run": true})
	assert_str(TextGen.quest_text(q)).is_equal("Deal 1,000 damage with the Revolver in one run.")
	# outside a run: no progress, never done (the title's quiet check)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i.ZERO)
	_start()
	Run.add_damage("revolver", 400.0)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(400, 1000))
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	Run.add_damage("revolver", 700.0)
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	assert_bool(QuestTracker._satisfied(q, false)).is_false()
	# every new type takes in_one_run and says so
	for t: String in NEW_QUESTS:
		var c := {"type": t, "count": 5, "in_one_run": true, "weapon": "revolver", "item": "mend", "source": "pickup:heart", "element": "fire"}
		assert_str(TextGen.quest_text(_quest(c))).override_failure_message(t).ends_with(" in one run.")


func test_every_new_quest_type_completes_and_says_its_words() -> void:
	var words := {
		"heal_with_item": [{"item": "thirst", "count": 2000}, "Restore 2,000 HP with Death."],
		"heal_with_source": [{"source": "pickup:heart", "count": 500}, "Restore 500 HP with Hearts."],
		"element_damage": [{"element": "fire", "count": 20000}, "Deal 20,000 fire damage."],
		"barrels_total": [{"count": 40}, "Break 40 barrels."],
		"totems_total": [{"count": 10}, "Take 10 Totem gifts."],
	}
	for t: String in words.keys():
		var c: Dictionary = (words[t][0] as Dictionary).duplicate()
		c["type"] = t
		assert_str(TextGen.quest_text(_quest(c))).override_failure_message(t).is_equal(str(words[t][1]))
	assert_str(TextGen.quest_text(_quest({"type": "heal_with_source", "source": "structure:healing_well", "count": 300}))) \
		.is_equal("Restore 300 HP with Healing Wells.")
	assert_str(TextGen.quest_text(_quest({"type": "element_damage", "element": "poison", "count": 5000}))).is_equal("Deal 5,000 poison damage.")
	assert_str(TextGen.quest_text(_quest({"type": "totems_total", "count": 1}))).is_equal("Take a Totem gift.")
	_start()
	var qs := {
		"heal_with_item": _quest({"type": "heal_with_item", "item": "mend", "count": 30}),
		"heal_with_source": _quest({"type": "heal_with_source", "source": "pickup:heart", "count": 30}),
		"element_damage": _quest({"type": "element_damage", "element": "poison", "count": 30}),
		"barrels_total": _quest({"type": "barrels_total", "count": 3}),
		"totems_total": _quest({"type": "totems_total", "count": 2}),
	}
	for t: String in qs.keys():
		assert_bool(QuestTracker._satisfied(qs[t], true)).override_failure_message(t + " done before anything").is_false()
		assert_int((QuestTracker.progress(qs[t]) as Vector2i).x).override_failure_message(t).is_equal(0)
	Run.healed_by_item["mend"] = 31.0
	Run.healed_by_source["pickup:heart"] = 30.5
	Run.add_damage("venom", 30.0, "poison")
	Run.barrels_broken = 3
	Run.take_totem_boon({"id": "wolf", "stat": "move_speed", "op": "mul", "value": 0.02})
	Run.take_totem_boon({"id": "bear", "stat": "might", "op": "mul", "value": 0.02})
	# a pole used with nothing taken counts for nothing
	Run.take_totem_boon({})
	assert_int(Run.totems_taken).is_equal(2)
	for t: String in qs.keys():
		assert_bool(QuestTracker._satisfied(qs[t], true)).override_failure_message(t + " not done").is_true()
		var p: Vector2i = QuestTracker.progress(qs[t])
		assert_bool(p.y > 0 and p.x >= p.y).override_failure_message("%s progress %s" % [t, p]).is_true()
	# an any-heart-or-well source and both elements
	assert_float(TaskTally.amount({"type": "heal_with_source", "source": "pickup:"})).is_equal_approx(30.5, 0.001)
	assert_float(TaskTally.amount({"type": "heal_with_source", "source": "structure:"})).is_equal(0.0)
	assert_str(TextGen.quest_text(_quest({"type": "heal_with_source", "source": "pickup:", "count": 50}))).is_equal("Restore 50 HP with power-ups.")
	Run.add_damage("molotov", 10.0, "fire")
	assert_float(TaskTally.amount({"type": "element_damage", "element": ""})).is_equal_approx(40.0, 0.001)
	# the check marks them done like any quest (completion by quest id)
	for t: String in NEW_QUESTS:
		assert_bool(TextGen.quest_text(_quest({"type": t, "count": 1})) != "Complete a challenge.").override_failure_message(t).is_true()


# ---------------------------------------------------------------- 3. fire and poison

func test_burns_and_poison_ticks_count_plain_and_hostile_hits_never() -> void:
	_start("astro")
	var em := _world()
	var i := em.spawn("skeleton", Vector3(0, 0, 0), null, 1.0, 5000.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	# a burn's tick (hot), a poison's (green), a plain hit, the boss's ring of fire burning the crowd (no weapon), a
	# hostile blast's friendly fire
	em.damage(i, 12.0, "molotov", Vector3.ZERO, 0.0, false, true)
	em.damage(i, 7.0, "venom", Vector3.ZERO, 0.0, true)
	em.damage(i, 100.0, "revolver")
	em.damage(i, 50.0, "", Vector3.ZERO, 0.0, false, true)
	em.damage(i, 30.0, "blast", Vector3.ZERO, 0.0, false, true)
	assert_float(float(Run.element_damage.get("fire", 0.0))).is_equal_approx(12.0, 0.001)
	assert_float(float(Run.element_damage.get("poison", 0.0))).is_equal_approx(7.0, 0.001)
	# the real clocks: a burn and a poison tick on their own
	var f0 := float(Run.element_damage.get("fire", 0.0))
	var p0 := float(Run.element_damage.get("poison", 0.0))
	em.ignite(i, "molotov", 5.0, 3.0, 0.0)
	em.poison(i, "venom", 2.0, 1, 4.0)
	# (a poison ticks every POISON_TICK = 2 s, a burn every 0.6 s)
	for k in range(150):
		em._tick_fire(i, 1.0 / 60.0)
		em._tick_poison(i, 1.0 / 60.0)
	assert_float(float(Run.element_damage.get("fire", 0.0))).is_greater(f0)
	assert_float(float(Run.element_damage.get("poison", 0.0))).is_greater(p0)
	# the fire and poison damage is part of the weapon's own (the family rule sees it too)
	assert_float(float(Run.damage_by_weapon.get("molotov", 0.0))).is_greater_equal(float(Run.element_damage.get("fire", 0.0)) - 0.001)


# ---------------------------------------------------------------- 4. the heal split

func test_a_heal_is_split_by_each_items_share_of_the_stat() -> void:
	_start("ironwood")
	Run.debug_set_item("passive", "mend", 1)
	Run.debug_set_item("passive", "hot_springs", 1)
	var sh := TaskTally.shares_of("regen")
	# Ironwood's own regen (his trait) is in the stat but no item's: the two items share the rest
	var mend: float = float(sh.get("mend", 0.0))
	var hs: float = float(sh.get("hot_springs", 0.0))
	assert_float(mend).is_greater(0.0)
	assert_float(hs).is_greater(0.0)
	assert_float(mend + hs).is_less(1.0)
	var regen := Run.player_sheet.get_stat("regen", 0.0)
	assert_float(mend).is_equal_approx(0.45 / regen, 0.02)
	TaskTally.note_regen(10.0, 1.0, 0.0)
	assert_float(float(Run.healed_by_item.get("mend", 0.0))).is_equal_approx(10.0 * mend, 0.001)
	assert_float(float(Run.healed_by_item.get("hot_springs", 0.0))).is_equal_approx(10.0 * hs, 0.001)
	# regen and Siesta together: each part to its own items
	Run.debug_set_item("passive", "siesta", 1)
	Run.healed_by_item.clear()
	TaskTally.note_regen(9.0, 2.0, 1.0)
	assert_float(float(Run.healed_by_item.get("siesta", 0.0))).is_equal_approx(3.0, 0.001)
	# an evolved card counts for its source (Death Risen heals for Death)
	_start("drifter")
	Run.debug_set_item("passive", "thirst", 1)
	assert_bool(Run.evolve_passive("thirst")).is_true()
	assert_bool(Run.passives.has("bloodthirst")).is_true()
	TaskTally.note_heal("stat:lifesteal", 4.0)
	assert_float(float(Run.healed_by_item.get("thirst", 0.0))).is_equal_approx(4.0, 0.001)
	assert_bool(Run.healed_by_item.has("bloodthirst")).is_false()
	# a heal with nothing behind it counts for no item; a source counts for itself
	Run.healed_by_item.clear()
	TaskTally.note_heal("stat:crit_heal_chance", 5.0)
	assert_bool(Run.healed_by_item.is_empty()).is_true()
	TaskTally.note_heal("structure:healing_well", 6.0)
	assert_float(float(Run.healed_by_source.get("structure:healing_well", 0.0))).is_equal_approx(6.0, 0.001)


func test_the_healing_items_are_read_off_the_content() -> void:
	var ids: Array = TaskTally.heal_items().map(func(p: PassiveDef) -> String: return p.id)
	for want in ["thirst", "mend", "hot_springs", "siesta", "vulture", "cake"]:
		assert_bool(ids.has(want)).override_failure_message("missing " + want).is_true()
	# Snake Oil fills an overheal but heals nothing itself; an evolved form is its source's
	for not_one in ["snake_oil", "bloodthirst", "second_wind"]:
		assert_bool(ids.has(not_one)).override_failure_message("listed " + not_one).is_false()
	assert_bool(TaskTally.pickup_heals(Registry.pickup("heart"))).is_true()
	assert_bool(TaskTally.pickup_heals(Registry.pickup("cake_slice"))).is_false()
	assert_bool(TaskTally.pickup_heals(Registry.pickup("nuke"))).is_false()
	assert_bool(TaskTally.structure_heals(Registry.structure("healing_well"))).is_true()
	assert_bool(TaskTally.structure_heals(Registry.structure("totem_pole"))).is_false()


# ---------------------------------------------------------------- 5. the real game credits each source

func test_the_game_credits_hearts_wells_cake_life_steal_regen_barrels_and_totems() -> void:
	var g := _game()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(Run.active).is_true()
	var pl: Player = g.player
	pl.hp = 10.0
	g.apply_pickup(Registry.pickup("heart"), pl.global_position)
	assert_float(float(Run.healed_by_source.get("pickup:heart", 0.0))).is_greater(1.0)
	pl.hp = 10.0
	g.use_structure(Registry.structure("healing_well"), pl.global_position)
	assert_float(float(Run.healed_by_source.get("structure:healing_well", 0.0))).is_greater(1.0)
	# a Cake Slice counts for the Cake (its `credit_stat`), never as a power-up
	Run.debug_set_item("passive", "cake", 1)
	pl.refresh_stats()
	pl.hp = 10.0
	g.apply_pickup(Registry.pickup("cake_slice"), pl.global_position)
	assert_float(float(Run.healed_by_item.get("cake", 0.0))).is_greater(1.0)
	assert_bool(Run.healed_by_source.has("pickup:cake_slice")).is_false()
	# life steal for Death
	Run.debug_set_item("passive", "thirst", 1)
	pl.refresh_stats()
	pl.hp = 10.0
	Run.lifesteal_healed.emit(3.0)
	assert_float(float(Run.healed_by_item.get("thirst", 0.0))).is_equal_approx(3.0, 0.01)
	# regen's ticks for Temperance
	Run.debug_set_item("passive", "mend", 1)
	pl.refresh_stats()
	pl.hp = 10.0
	pl.regen_hold = 0.0
	pl._tick_regen(1.0)
	assert_float(float(Run.healed_by_item.get("mend", 0.0))).is_greater(0.0)
	# a barrel broken, a Totem gift taken
	var bf: BarrelField = g.barrels
	var k := bf.alive.find(1)
	assert_int(k).is_greater_equal(0)
	bf._break(k)
	assert_int(Run.barrels_broken).is_equal(1)
	Run.take_totem_boon({"id": "wolf", "stat": "move_speed", "op": "mul", "value": 0.02})
	assert_int(Run.totems_taken).is_equal(1)
	# the run's end banks it all (the arena never: test 6): end_run calls the bank once, after the purse (its scene change
	# is left to the real game; the source says where it sits)
	var src := FileAccess.get_file_as_string("res://game/Game.gd")
	var body := src.substr(src.find("func end_run() -> void:"), 1400)
	assert_int(body.count("TaskTally.bank()")).is_equal(1)
	assert_int(body.find("TaskTally.bank()")).is_greater(body.find("bank_run_end("))
	assert_int(body.find("TaskTally.bank()")).is_less(body.find("QuestTracker.check_all(true)"))
	assert_bool(TaskTally.bank()).is_true()
	assert_int(Save.total(TaskTally.SAVE_BARRELS)).is_equal(1)
	assert_int(Save.total(TaskTally.SAVE_TOTEMS)).is_equal(1)
	assert_int(Save.keyed_total(TaskTally.SAVE_HEAL_SOURCE, "pickup:heart")).is_greater(0)
	assert_int(Save.keyed_total(TaskTally.SAVE_HEAL_ITEM, "thirst")).is_equal(3)


# ---------------------------------------------------------------- 6. never from the arena, the sim or a tool

func test_nothing_counts_in_the_arena_the_sim_or_a_tool() -> void:
	var q := _quest({"type": "barrels_total", "count": 1})
	_start()
	Run.barrels_broken = 5
	assert_bool(TaskTally.counts()).is_true()
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	# the debug arena
	Run.arena = true
	assert_bool(TaskTally.counts()).is_false()
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	assert_bool(TaskTally.bank()).is_false()
	assert_array(QuestTracker.check_all(true)).is_empty()
	Run.arena = false
	# the run sim
	Run.sim_mode = true
	assert_bool(TaskTally.counts()).is_false()
	assert_bool(TaskTally.bank()).is_false()
	Run.sim_mode = false
	# a tool's process (this very test runner: headless) without the tests' switch
	TaskTally.bank_in_tools = false
	assert_bool(RunAnalytics.is_tool_process()).is_true()
	assert_bool(TaskTally.counts()).is_false()
	assert_bool(TaskTally.bank()).is_false()
	assert_int(Save.total(TaskTally.SAVE_BARRELS)).is_equal(0)
	TaskTally.bank_in_tools = true
	# an old save without the new totals reads them as nothing
	var old := Save._default()
	for key in ["damage_with_weapon", "heal_with_item", "heal_with_source", "element_damage", "barrels", "totems"]:
		assert_bool((old["totals"] as Dictionary).has(key)).override_failure_message(key).is_true()
		(old["totals"] as Dictionary).erase(key)
	Save.data = old
	assert_int(Save.total(TaskTally.SAVE_TOTEMS)).is_equal(0)
	assert_int(Save.keyed_total(TaskTally.SAVE_DAMAGE, "revolver")).is_equal(0)
	assert_float(TaskTally.saved_amount({"type": "heal_with_source", "source": "pickup:"})).is_equal(0.0)


# ---------------------------------------------------------------- 7. the Wanted posters

func test_the_wanted_types_target_only_what_the_run_can_get() -> void:
	Save.add_total("runs", 1)
	var cfg := WantedBoard.config(true)
	for t: String in NEW_WANTED:
		assert_bool(WantedBoard.TYPE_ORDER.has(t)).override_failure_message(t).is_true()
		assert_bool(WantedBoard.task_cfg(cfg, t).is_empty()).override_failure_message("no row " + t).is_false()
	# a fresh save: no healing item seen yet; the hero's own gun only
	var ctx := WantedBoard.context(MAP, 0, "drifter")
	assert_array(WantedBoard.targets_of(cfg, "heal_item", ctx)).is_empty()
	var dw := WantedBoard.targets_of(cfg, "damage_weapon", ctx)
	assert_int(dw.size()).is_equal(1)
	assert_str(str(dw[0]["id"])).is_equal("revolver")
	# the map's heal sources: the Heart (kills and barrels drop it), the Healing Well (placed); never a Cake Slice
	var srcs: Array = WantedBoard.targets_of(cfg, "heal_source", ctx).map(func(x: Dictionary) -> String: return "%s:%s" % [x["kind"], x["id"]])
	assert_bool(srcs.has("pickup:heart")).is_true()
	assert_bool(srcs.has("structure:healing_well")).is_true()
	assert_bool(srcs.has("pickup:cake_slice")).is_false()
	assert_int(int(ctx["totem_poles"])).is_equal(10)
	assert_int(WantedBoard.targets_of(cfg, "element_damage", ctx).size()).is_equal(2)
	_meet_everything()
	ctx = WantedBoard.context(MAP, 0, "drifter")
	var heals: Array = WantedBoard.targets_of(cfg, "heal_item", ctx).map(func(x: Dictionary) -> String: return str(x["id"]))
	assert_bool(heals.has("mend")).is_true()
	# Death is quest-locked on a fresh save (Temperance Risen opens it)
	assert_bool(heals.has("thirst")).is_false()
	for x: Dictionary in WantedBoard.targets_of(cfg, "heal_item", ctx):
		var p: PassiveDef = Registry.passive(str(x["id"]))
		assert_bool(p.hidden or not Registry.is_unlocked("passive", p.id)).override_failure_message(p.id).is_false()
	# many rolls: N within the item's own levels, totems within the poles, the right words and pictures
	for k in 300:
		for type: String in NEW_WANTED:
			var c := WantedBoard.make_contract(cfg, type, ctx, _rng(k * 31 + type.hash()))
			if c.is_empty():
				continue
			assert_str(str(c["text"])).override_failure_message(type).not_contains("{")
			assert_str(str(c["name"])).override_failure_message(type).not_contains("{")
			assert_int(int(c["skulls"])).is_between(1, 5)
			assert_int(int(c["reward"]) % 5).is_equal(0)
			match type:
				"item_level":
					var top := 0
					match str(c["target_kind"]):
						"weapon":
							top = Registry.weapon(str(c["target"])).max_level
						_:
							top = Registry.passive(str(c["target"])).ladder_top()
					assert_int(int(c["n"])).override_failure_message("%s %s" % [c["target"], c["n"]]).is_between(2, top)
				"totems":
					assert_int(int(c["n"])).is_between(1, int(ctx["totem_poles"]))
				"barrels":
					assert_int(int(c["n"])).is_less_equal(40)
				"heal_item":
					assert_bool(heals.has(str(c["target"]))).is_true()


func test_a_target_s_own_factor_scales_its_numbers() -> void:
	var cfg := WantedBoard.normalized({"choices": 1, "tasks": [
		{"type": "heal_item", "weight": 1, "difficulty": [1, 3], "n": [[100, 200]], "step": 1, "target_mult": {"cake": 0.25}, "text": "x {n}"}]})
	var ctx := {"map": MAP, "stage": 0, "stage_name": "Sundown", "P": 0, "hero": {"id": "drifter", "name": "Drifter", "start": "revolver"},
		"heal_items": [{"id": "cake", "name": "Cake", "kind": "passive", "seen": true}]}
	for k in 50:
		var c := WantedBoard.make_contract(cfg, "heal_item", ctx, _rng(k))
		assert_int(int(c["n"])).is_between(25, 50)
		assert_str(str(c["still"]["kind"])).is_equal("passive")
	ctx["heal_items"] = [{"id": "mend", "name": "Temperance", "kind": "card", "seen": true}]
	for k in 50:
		var c := WantedBoard.make_contract(cfg, "heal_item", ctx, _rng(k))
		assert_int(int(c["n"])).is_between(100, 200)


func test_the_wanted_run_follows_the_new_types() -> void:
	_start()
	var evo := Registry.weapon("revolver").evolves_into
	var cases := [
		[{"type": "damage_weapon", "target": "revolver", "target_kind": "weapon", "n": 1000}, func(): Run.add_damage("revolver", 600.0); Run.add_damage(evo, 450.0)],
		[{"type": "heal_item", "target": "mend", "target_kind": "card", "n": 40}, func(): Run.healed_by_item["mend"] = 40.2],
		[{"type": "heal_source", "target": "heart", "target_kind": "pickup", "n": 30}, func(): Run.healed_by_source["pickup:heart"] = 30.0],
		[{"type": "element_damage", "target": "fire", "target_kind": "element", "n": 3000}, func(): Run.add_damage("molotov", 3000.0, "fire")],
		[{"type": "barrels", "target": "", "n": 4}, func(): Run.barrels_broken = 4],
		[{"type": "totems", "target": "totem_pole", "target_kind": "structure", "n": 1}, func(): Run.take_totem_boon({"id": "wolf", "stat": "move_speed", "op": "mul", "value": 0.02})],
		[{"type": "item_level", "target": "orbit_saws", "target_kind": "weapon", "n": 3}, func(): Run.debug_set_item("weapon", "orbit_saws", 3)],
	]
	for cs: Array in cases:
		var c: Dictionary = cs[0]
		var fake: Node = auto_free(Node.new())
		add_child(fake)
		var w := WantedRun.new()
		w.game = fake
		w.contract = c
		fake.add_child(w)
		w.check()
		assert_bool(w.done).override_failure_message(str(c["type"]) + " done before anything").is_false()
		assert_int(w.progress().y).is_equal(int(c["n"]))
		(cs[1] as Callable).call()
		w.check()
		assert_bool(w.done).override_failure_message(str(c["type"]) + " not done: " + str(w.progress())).is_true()
		assert_str(w.progress_text()).is_equal("DONE")
		WantedRun.current = null


func test_the_pictures_resolve_for_posters_and_quests() -> void:
	Save.add_total("runs", 1)
	_meet_everything()
	var cfg := WantedBoard.config(true)
	var ctx := WantedBoard.context(MAP, 0, "drifter")
	for type: String in NEW_WANTED:
		var c := WantedBoard.make_contract(cfg, type, ctx, _rng(5))
		assert_bool(c.is_empty()).override_failure_message("no poster for " + type).is_false()
		assert_object(WPoster.still_texture(c["still"])).override_failure_message("no picture for " + type).is_not_null()
		assert_object(WPoster.thumb_texture(c["still"])).override_failure_message("no thumb for " + type).is_not_null()
	# the barrel, the flask, the fire and the Totem Pole's own icon
	for id in ["barrel", "poison", "fire"]:
		assert_object(WPoster.still_texture({"kind": "art", "id": id})).override_failure_message(id).is_not_null()
	assert_object(WPoster.still_texture({"kind": "structure", "id": "totem_pole"})).is_not_null()
	# a quest's picture is a poster's still
	var conds := [{"type": "damage_with_weapon", "weapon": "revolver"}, {"type": "heal_with_item", "item": "mend"},
		{"type": "heal_with_source", "source": "pickup:heart"}, {"type": "heal_with_source", "source": "structure:healing_well"},
		{"type": "element_damage", "element": "poison"}, {"type": "element_damage", "element": "fire"}, {"type": "barrels_total"},
		{"type": "totems_total"}, {"type": "item_level", "id": "orbit_saws", "kind": "weapon"}, {"type": "kills_of_enemy", "enemy": "skeleton"}]
	for c: Dictionary in conds:
		var still := QuestTracker.picture(_quest(c))
		assert_bool(still.is_empty()).override_failure_message(str(c)).is_false()
		assert_object(WPoster.still_texture(still)).override_failure_message(str(c)).is_not_null()
	# nothing to draw for "any item of a kind"
	assert_bool(QuestTracker.picture(_quest({"type": "item_level", "kind": "weapon", "level": 3})).is_empty()).is_true()
