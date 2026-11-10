## Pass 140, lane QUESTS (plan v2's tasks, Garry: "Proceed with implementation"): the 34 tasks of section 3; a task
## behind another (`requires`: hidden and uncounted until the other is done), the gates `holding` and `hero`, the boss
## count `bosses_total`, the generic ladder (Dust Yourself Off -> Killing Spree -> Old Hand -> Pay Day -> Body Count), the
## Results' 3 task rows; every unlock exists and none is also a Trail node (tools/dl/p140/split.json and trail.json).
extends GdUnitTestSuite

const RESULTS := preload("res://ui/ResultsScreen.gd")
const LADDER := ["unlock_tommy_gun", "unlock_adrenaline", "unlock_phoenix_feather", "unlock_sinners_greed", "unlock_hot_streak"]
const RETIRED := ["unlock_lob_grenade", "unlock_quickdraw", "unlock_stride", "unlock_haste", "unlock_field_notes",
	"unlock_zap_beam", "unlock_rocket_pod", "skin_drifter_dri_c", "skin_ironwood_irn_c", "skin_astro_ast_c", "skin_astro_ast_b"]


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	TaskTally.bank_in_tools = true
	QuestTracker.just_completed.clear()


func after_test() -> void:
	TaskTally.bank_in_tools = false
	Run.arena = false
	Run.end()
	QuestTracker.just_completed.clear()


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _q(id: String) -> QuestDef:
	return Registry.quests.get(id)


func _tasks() -> Array:
	return Registry.quests.values().filter(func(q: QuestDef) -> bool: return not (q.id in ["unlock_dad", "unlock_mira"]))


# ---------------------------------------------------------------- the set

func test_thirty_four_tasks_plus_dad_and_mira() -> void:
	assert_int(_tasks().size()).is_equal(34)
	assert_object(_q("unlock_dad")).is_not_null()
	assert_object(_q("unlock_mira")).is_not_null()
	for id in RETIRED:
		assert_object(_q(id)).override_failure_message("retired %s" % id).is_null()
	# ten skin tasks, five of them behind another task
	var skins: Array = _tasks().filter(func(q: QuestDef) -> bool: return str(q.unlocks.get("type", "")) == "skin")
	assert_int(skins.size()).is_equal(10)
	assert_int(skins.filter(func(q: QuestDef) -> bool: return not q.requires.is_empty()).size()).is_equal(5)
	# twelve tasks behind another (the plan's count)
	assert_int(_tasks().filter(func(q: QuestDef) -> bool: return not q.requires.is_empty()).size()).is_equal(12)
	# every prerequisite is a quest, none waits on itself or in a ring
	for q: QuestDef in Registry.quests.values():
		var seen := {q.id: true}
		var cur: QuestDef = q
		var guard := 0
		while not cur.requires.is_empty() and guard < 10:
			var nxt: QuestDef = _q(str(cur.requires[0]))
			assert_object(nxt).override_failure_message("%s requires %s" % [cur.id, cur.requires[0]]).is_not_null()
			assert_bool(seen.has(nxt.id)).override_failure_message("ring at %s" % nxt.id).is_false()
			seen[nxt.id] = true
			cur = nxt
			guard += 1


func test_the_ladder_is_one_chain_of_five_generic_counters() -> void:
	var ladder: Array = Registry.quests.values().filter(func(q: QuestDef) -> bool: return q.ladder)
	assert_int(ladder.size()).is_equal(5)
	for i in LADDER.size():
		var q: QuestDef = _q(LADDER[i])
		assert_bool(q.ladder).is_true()
		if i == 0:
			assert_array(q.requires).is_empty()
		else:
			assert_array(q.requires).is_equal([LADDER[i - 1]])
	# one generic counter at a time: on a fresh save only Dust Yourself Off is open
	var open_ladder: Array = ladder.filter(func(q: QuestDef) -> bool: return Registry.quest_open(q))
	assert_array(open_ladder.map(func(q: QuestDef) -> String: return q.id)).is_equal(["unlock_tommy_gun"])


# ---------------------------------------------------------------- Dust Yourself Off

func test_dust_yourself_off_is_done_by_any_finished_run_and_unlocks_the_tommy_gun() -> void:
	assert_bool(Registry.is_unlocked("weapon", "tommy_gun")).is_false()
	# a 20-second death: the run is counted (Game.end_run -> Save.record_run), then the run's own check
	_start()
	Save.record_run("red_canyon", 20.0, 1, 1, 3)
	var done: Array = QuestTracker.check_all(true)
	assert_array(done).contains(["unlock_tommy_gun"])
	assert_array(QuestTracker.just_completed).contains(["unlock_tommy_gun"])
	assert_bool(Registry.is_unlocked("weapon", "tommy_gun")).is_true()
	# the only first-run task: nothing else is done by it
	assert_array(done).is_equal(["unlock_tommy_gun"])
	# the next step of the ladder opens
	assert_bool(Registry.quest_open(_q("unlock_adrenaline"))).is_true()


# ---------------------------------------------------------------- requires

func test_a_task_behind_another_is_hidden_and_uncounted_until_the_other_is_done() -> void:
	var spree := _q("unlock_adrenaline")
	Save.data["totals"]["kills"] = 1500
	assert_bool(Registry.quest_visible(spree)).is_true()
	assert_bool(Registry.quest_open(spree)).is_false()
	assert_object(QuestTracker.progress(spree)).is_equal(Vector2i.ZERO)
	assert_object(QuestTracker.waiting_on(spree)).is_equal(_q("unlock_tommy_gun"))
	assert_str(QuestTracker.requirement_text(spree)).is_equal("After Dust Yourself Off.")
	# nor in the run's snapshot of what can move
	assert_bool(RunTimeline.quest_progress().has(spree.id)).is_false()
	# enough kills, but it waits: never done by a check
	Save.data["totals"]["kills"] = 5000
	QuestTracker.check_all(false)
	assert_bool(Save.quest_done(spree.id)).is_false()
	# its prerequisite done: it opens with its all-time count and completes in the same check
	Save.data["totals"]["runs"] = 1
	var done: Array = QuestTracker.check_all(false)
	assert_array(done).contains(["unlock_tommy_gun", "unlock_adrenaline"])
	# the step after waits for it in turn: open now, and counting
	var hand := _q("unlock_phoenix_feather")
	assert_bool(Registry.quest_open(hand)).is_true()
	assert_object(QuestTracker.progress(hand)).is_equal(Vector2i(1, 10))


func test_a_skin_task_behind_another_says_what_it_waits_for() -> void:
	var marigold := _q("skin_calavera_cal_b")
	var cal: CharacterDef = Registry.character("calavera")
	assert_object(Registry.skin_quest(cal, "CAL-B")).is_equal(marigold)
	assert_str(Registry.skin_requirement_text(cal, "CAL-B")).is_equal("After %s." % _q("skin_calavera_cal_c").display_name)
	Save.mark_quest("skin_calavera_cal_c")
	assert_str(Registry.skin_requirement_text(cal, "CAL-B")).is_equal(TextGen.quest_text(marigold))


# ---------------------------------------------------------------- holding

func test_holding_counts_only_while_the_run_holds_the_item() -> void:
	var game := _q("unlock_guillotine")
	assert_str(str(game.condition.get("holding", ""))).is_equal("big_game_hunter")
	Save.mark_quest("unlock_big_game_hunter")
	_start()
	# a boss without Big Game Hunter counts nothing
	TaskTally.note_boss()
	assert_object(QuestTracker.progress(game)).is_equal(Vector2i(0, 5))
	Run.add_or_level_passive("big_game_hunter")
	assert_bool(QuestTracker.run_gates(game.condition)).is_true()
	TaskTally.note_boss()
	assert_object(QuestTracker.progress(game)).is_equal(Vector2i(1, 5))
	# banked at the run's end, counted across runs
	assert_bool(TaskTally.bank()).is_true()
	Run.end()
	assert_object(QuestTracker.progress(game)).is_equal(Vector2i(1, 5))
	assert_str(TextGen.quest_text(game)).is_equal("Beat 5 bosses holding Big Game Hunter.")
	# Last Stand: Nightfall beaten holding The Guardian
	var stand := _q("unlock_last_stand")
	Save.mark_quest("unlock_energy_shield")
	_start()
	Run.stage = 1
	Run.stage_beaten = true
	assert_bool(QuestTracker._satisfied(stand, true)).is_false()
	Run.add_or_level_passive("energy_shield")
	assert_bool(QuestTracker._satisfied(stand, true)).is_true()
	assert_str(TextGen.quest_text(stand)).is_equal("Beat Nightfall holding The Guardian.")


func test_a_boss_counts_nothing_for_a_bosses_task_still_waiting() -> void:
	_start()
	Run.add_or_level_passive("big_game_hunter")
	TaskTally.note_boss()
	assert_bool(Run.bosses_by_gate.is_empty()).is_true()


# ---------------------------------------------------------------- hero

func test_hero_counts_only_as_that_outlaw() -> void:
	var quick := _q("unlock_desperado")
	_start("astro")
	Run.add_weapon(Registry.weapon("revolver"), 5)
	assert_bool(QuestTracker._satisfied(quick, true)).is_false()
	assert_object(QuestTracker.progress(quick)).is_equal(Vector2i.ZERO)
	Run.end()
	_start("drifter")
	Run.add_weapon(Registry.weapon("revolver"), 5)
	assert_object(QuestTracker.progress(quick)).is_equal(Vector2i(5, 5))
	assert_bool(QuestTracker._satisfied(quick, true)).is_true()
	assert_str(TextGen.quest_text(quick)).is_equal("Get the Revolver to level 5 in one run with Drifter.")
	Run.end()
	# Czerwony: 30 barrels in one run as Jezyk
	var red := _q("skin_buck_buc_g")
	_start("drifter")
	Run.barrels_broken = 40
	assert_bool(QuestTracker._satisfied(red, true)).is_false()
	Run.end()
	_start("buck")
	Run.barrels_broken = 30
	assert_bool(QuestTracker._satisfied(red, true)).is_true()


# ---------------------------------------------------------------- the Results' rows

func test_the_results_show_at_most_three_rows_the_ladder_first() -> void:
	Save.mark_quest("unlock_tommy_gun")
	Save.data["totals"]["kills"] = 600
	Save.add_keyed_total(TaskTally.SAVE_ELEMENT, "fire", 50000)
	Save.add_keyed_total(TaskTally.SAVE_ELEMENT, "poison", 40000)
	Save.add_keyed_total(TaskTally.SAVE_HEAL_ITEM, "cake", 1000)
	Save.add_keyed_total(TaskTally.SAVE_HEAL_ITEM, "mend", 1900)
	Save.add_keyed_total(TaskTally.SAVE_DAMAGE, "revolver", 20000)
	var before := {"unlock_adrenaline": 500, "unlock_brimstone_brand": 10000, "unlock_gas_mask": 1000,
		"unlock_snake_oil": 900, "unlock_thirst": 1000, "skin_drifter_dri_b": 10000,
		# waits for Fire Bug: never a row
		"skin_solenne_sol_h": 0}
	var list: Array = RESULTS.progress_list(before)
	var ids: Array = list.map(func(c): return (c["q"] as QuestDef).id)
	assert_int(list.size()).is_equal(3)
	# the ladder's step first though it moved least, then the two the run moved most: Snakebite (+78% of its need),
	# Second Wind (+45%)
	assert_array(ids).is_equal(["unlock_adrenaline", "unlock_gas_mask", "unlock_thirst"])


# ---------------------------------------------------------------- unlocks and the Trail

func _trail_gives() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://content/trail/trail.json", FileAccess.READ)
	assert_object(f).is_not_null()
	var d = JSON.parse_string(f.get_as_text())
	for n in (d["nodes"] as Array):
		var g: Dictionary = n.get("gives", {})
		if str(g.get("type", "")) != "" and g.has("id"):
			out["%s:%s" % [str(g["type"]), str(g["id"])]] = str(n.get("id", ""))
	return out


func _trail_type(utype: String) -> String:
	return "outlaw" if utype == "character" else utype


func test_every_unlock_exists_and_none_is_also_a_trail_node() -> void:
	var gives := _trail_gives()
	for q: QuestDef in Registry.quests.values():
		var t := str(q.unlocks.get("type", ""))
		var id := str(q.unlocks.get("id", ""))
		match t:
			"weapon", "passive", "character":
				assert_object(Registry.unlocked_by(q)).override_failure_message("%s unlocks %s %s" % [q.id, t, id]).is_not_null()
			"skin":
				var c: CharacterDef = Registry.character(id.get_slice(":", 0))
				assert_object(c).is_not_null()
				assert_bool(c.variants.has(id.get_slice(":", 1))).override_failure_message(q.id).is_true()
				# (a look Garry took off sale in the editor, May's Midnight Mime since pass 115, keeps its task: hidden
				# until he sells it again, Registry.quest_visible)
				assert_bool(Registry.quest_visible(q)).is_equal(c.sells_skin(id.get_slice(":", 1)))
			_:
				fail("%s unlocks a %s" % [q.id, t])
		assert_bool(gives.has("%s:%s" % [_trail_type(t), id])).override_failure_message("%s's %s is a Trail node" % [q.id, id]).is_false()
		assert_bool(Trail.gated(_trail_type(t), id)).override_failure_message("%s's %s is gated by the Trail" % [q.id, id]).is_false()
	# the agreed split (lane TRAIL's file, when the tree has it): every task entry names its quest, which unlocks it
	var path := ProjectSettings.globalize_path("res://").path_join("../tools/dl/p140/split.json")
	if not FileAccess.file_exists(path):
		return
	var split = JSON.parse_string(FileAccess.get_file_as_string(path))
	var tasks := 0
	for e in (split["locked"] as Array):
		if str(e.get("by", "")) != "task":
			continue
		tasks += 1
		var q: QuestDef = _q(str(e.get("quest", "")))
		assert_object(q).override_failure_message("split task %s" % e.get("id")).is_not_null()
		assert_str(_trail_type(str(q.unlocks.get("type", "")))).is_equal(str(e["kind"]))
		assert_str(str(q.unlocks.get("id", ""))).is_equal(str(e["id"]))
		assert_bool(gives.has("%s:%s" % [str(e["kind"]), str(e["id"])])).is_false()
	assert_int(tasks).is_equal(34)


func test_the_skins_for_sale_need_no_task_and_may_comes_from_hers() -> void:
	for pair in [["drifter", "DRI-C"], ["ironwood", "IRN-C"], ["astro", "AST-C"]]:
		var c: CharacterDef = Registry.character(str(pair[0]))
		assert_object(Registry.skin_quest(c, str(pair[1]))).is_null()
		if Registry.hero_state(c) == "owned":
			assert_str(Registry.skin_state(c, str(pair[1]))).is_equal("buyable")
	var may: CharacterDef = Registry.character("may")
	assert_object(Registry.quest_for("character", "may")).is_equal(_q("unlock_may"))
	assert_str(Registry.hero_state(may)).is_equal("locked")
	Save.mark_quest("unlock_may")
	assert_str(Registry.hero_state(may)).is_equal("owned")
