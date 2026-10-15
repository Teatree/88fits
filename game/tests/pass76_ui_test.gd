## Pass 76, lane UI (Garry: "Stats in pause menu. Mark the stats that were changed since the start of the game. Provide
## some minimal info on which items are doing the stat changes underneath somewhere"; "Result Screen unlocks are showing
## heroes that I already unlocked"; "Make the revolver basic projectile trail thing be a dim red instead of yellow ...
## Make the trail a bit thicker too"): the stats as the run began (Run.start_stats) and the marks against them, the
## better/worse colour (a cooldown cut is better), the open stat's sources grouped "At the start" / "This run" and merged
## by their source ids, the five old bugs (talent and totem names, cooldown and duration in seconds, a cut coloured bad,
## weapon-aimed rows, changed stats never listed); an owned hero never announced, never FOR SALE, never in progress, and
## no stale "Unlocked this run"; the Revolver's dim red, thicker tracer with Silver Bullet's and Venom Rounds' kept.
extends GdUnitTestSuite

const SOURCES := preload("res://core/systems/StatSources.gd")
const RESULTS := preload("res://ui/ResultsScreen.gd")
const QT := preload("res://core/systems/QuestTracker.gd")

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"inset": Settings.top_inset, "save": Save.data.duplicate(true)}
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._migrate_seen()
	Save._dirty = false
	Run.arena = false
	QT.just_completed.clear()


func after_test() -> void:
	Settings.top_inset = int(_keep["inset"])
	QT.just_completed.clear()
	Save.data = _keep["save"]
	Save._dirty = false
	Run.end()


func _start(hero := "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _pause_on_stats(stat: String = "?") -> PauseScreen:
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	ps._tab = 1
	ps._stat = stat
	ps._refresh()
	return ps


func _cell(ps: PauseScreen, stat: String) -> Control:
	return ps._content.find_child("Stat_" + stat, true, false) as Control


func _rows(stat: String) -> Dictionary:
	return SOURCES.rows(Run.player_sheet, stat)


func _row(list: Array, key: String) -> Dictionary:
	for r: Dictionary in list:
		if str(r["key"]) == key:
			return r
	return {}


# ---------------------------------------------------------------- the start and the marks

func test_the_start_is_kept_and_a_stat_that_moved_is_marked_against_it() -> void:
	_start()
	assert_str(Run.start_stats_hero).is_equal("drifter")
	assert_float(float(Run.start_stats.get("max_hp", 0.0))).is_equal_approx(100.0, 0.0001)
	assert_float(Run.start_stat("might", 1.0)).is_equal_approx(1.0, 0.0001)
	# nothing moved yet
	for s in ["max_hp", "might", "cooldown", "luck", "move_speed"]:
		assert_bool(SOURCES.changed(Run.player_sheet, s)).override_failure_message(s).is_false()
	# The Sun (attack damage) and The Tower (cooldown): both moved, the rest did not
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("haste")
	assert_bool(SOURCES.changed(Run.player_sheet, "might")).is_true()
	assert_bool(SOURCES.changed(Run.player_sheet, "cooldown")).is_true()
	assert_bool(SOURCES.changed(Run.player_sheet, "luck")).is_false()
	var up: Dictionary = SOURCES.change(Run.player_sheet, "might")
	assert_bool(bool(up["up"])).is_true()
	assert_bool(bool(up["worse"])).is_false()
	# the start stays what it was
	assert_float(Run.start_stat("might", 1.0)).is_equal_approx(1.0, 0.0001)
	# the tab: a pill on what moved, nothing on what did not, which is dimmed
	var ps := _pause_on_stats()
	await get_tree().process_frame
	var might := _cell(ps, "might")
	assert_object(might).is_not_null()
	assert_bool(bool(might.get_meta("moved"))).is_true()
	assert_object(might.find_child("Change", true, false)).is_not_null()
	var luck := _cell(ps, "luck")
	assert_bool(bool(luck.get_meta("moved"))).is_false()
	assert_object(luck.find_child("Change", true, false)).is_null()
	var name_l := luck.find_child("Name", true, false) as WText
	assert_float(name_l.color.a).is_equal_approx(PauseScreen.DIM_ALPHA, 0.001)
	# the head counts them; the first that moved opened by itself
	assert_str((ps._content.find_child("Moved", true, false) as WText).text).is_equal("2")
	assert_str(ps._stat).is_equal("might")
	assert_object(ps._content.find_child("Sources", true, false)).is_not_null()
	ps.visible = false


func test_a_cooldown_cut_is_better_and_reads_as_a_share() -> void:
	_start()
	Run.add_or_level_passive("haste")
	var ch: Dictionary = SOURCES.change(Run.player_sheet, "cooldown")
	assert_bool(bool(ch["up"])).is_false()
	assert_bool(bool(ch["worse"])).is_false()
	# The Tower's −8%: said as a share of the start, as its row says it
	assert_bool(bool(ch["share"])).is_true()
	assert_str(str(ch["text"])).is_equal("8%")
	# bug 2: the hero's cooldown and duration are shares, never seconds
	assert_str(TextGen.player_value("cooldown", 0.92)).is_equal("92%")
	assert_str(TextGen.player_value("duration", 1.0)).is_equal("100%")
	assert_str(TextGen.player_value("max_hp", 100.0)).is_equal("100")
	# bug 3: the pill and the row in the better colours
	var ps := _pause_on_stats("cooldown")
	await get_tree().process_frame
	var pill := _cell(ps, "cooldown").find_child("Change", true, false) as PanelContainer
	assert_bool(bool(pill.get_meta("worse"))).is_false()
	assert_bool(bool(pill.get_meta("up"))).is_false()
	assert_object(pill.find_child("Down", true, false)).is_not_null()
	var box := pill.get_theme_stylebox("panel") as HardBox
	assert_bool(box.fill.is_equal_approx(PauseScreen.BETTER)).is_true()
	var card := ps._content.find_child("Sources", true, false)
	var row: Control = null
	for n in card.find_children("*", "HBoxContainer", true, false):
		if n.has_meta("sid") and str(n.get_meta("sid")) == "passive:haste":
			row = n
	assert_object(row).is_not_null()
	assert_bool((row.find_child("Amount", true, false) as WText).color.is_equal_approx(PauseScreen.BETTER_TEXT)).is_true()
	assert_str((row.find_child("Amount", true, false) as WText).text).is_equal("−8%")
	ps.visible = false
	# a loss: Death's max HP (its trade) is worse, its pill in rock
	Run.add_or_level_passive("thirst")
	var hp: Dictionary = SOURCES.change(Run.player_sheet, "max_hp")
	assert_bool(bool(hp["worse"])).is_true()
	assert_bool(bool(hp["up"])).is_false()


# ---------------------------------------------------------------- the sources

func test_the_sources_are_grouped_by_start_and_run_and_merged_by_their_ids() -> void:
	# the Upgrade board: three ranks of Padding (one effect a rank)
	Save.data["talents"] = {"grit": {"picks": [0, 0, 0], "rank": 3, "form": 0}}
	_start()
	Run.add_or_level_passive("vigour")
	Run.add_or_level_passive("vigour")
	Run.take_totem_boon({"id": "whale", "name": "El-kolie", "animal": "the Whale", "stat": "max_hp", "op": "add", "value": 10.0})
	Run.take_totem_boon({"id": "whale", "name": "El-kolie", "animal": "the Whale", "stat": "max_hp", "op": "add", "value": 12.0})
	var rs := _rows("max_hp")
	var start: Array = rs[SOURCES.START]
	var run: Array = rs[SOURCES.RUN]
	# At the start: the base, then the three ranks as one row (bug 1: the talent's name whole)
	assert_str(str(start[0]["key"])).is_equal("base")
	var pad := _row(start, "talent:grit:0|mul")
	assert_int(int(pad["count"])).is_equal(3)
	assert_str(str(pad["name"])).contains("Grit")
	assert_str(str(pad["name"])).contains("Padding rank 3")
	assert_str(str(pad["text"])).is_equal("+33%")
	# This run: The Giant's two levels as one row, the two gifts of one spirit as one, their amounts summed
	var giant := _row(run, "passive:vigour|mul")
	assert_int(int(giant["count"])).is_equal(2)
	assert_str(str(giant["name"])).ends_with("Lv 2")
	var whale := _row(run, "totem:whale|add")
	assert_int(int(whale["count"])).is_equal(2)
	assert_str(str(whale["name"])).is_equal("El-kolie, the Whale ×2")
	assert_str(str(whale["text"])).is_equal("+22")
	assert_object(whale["icon"]).is_not_null()
	# nothing of the start is among this run's rows, and the other way round
	for r: Dictionary in run:
		assert_str(str(r["sid"])).not_contains("talent:")
	for r: Dictionary in start:
		assert_str(str(r["sid"])).not_contains("totem:")
	# the old breakdown keeps its words (the tests of passes 49-73 read them)
	var words: Array = []
	for b: Dictionary in Run.player_sheet.breakdown("max_hp"):
		words.append(str(b["source"]))
	assert_bool(words.has("Grit: Padding 3")).is_true()
	assert_bool(words.has("Totem: El-kolie")).is_true()
	# bug 1 in the old namer: a source in words of its own is said whole
	var ps: PauseScreen = auto_free(PauseScreen.new())
	assert_str(ps._source_name("Totem: El-kolie")).is_equal("Totem: El-kolie")
	assert_str(ps._source_name("Grit: Padding 3")).is_equal("Grit: Padding 3")
	assert_str(ps._source_name("passive:brawn")).is_equal(Registry.passive("brawn").display_name)


func test_the_signature_stat_splits_its_first_level_from_its_growth_and_a_buff_shows_its_clock() -> void:
	_start("solenne")
	Run.level = 12
	Run.rebuild_sheets()
	var rs := _rows("debuff_duration")
	var first := _row(rs[SOURCES.START], "trait:solenne|mul")
	assert_dict(first).is_not_empty()
	var step := float(Registry.character("solenne").level_effects(1)[0].value)
	assert_float(float(first["value"])).is_equal_approx(step, 0.00001)
	var growth := _row(rs[SOURCES.RUN], "trait:solenne|mul|growth")
	assert_float(float(growth["value"])).is_equal_approx(step * 11.0, 0.00001)
	assert_str(str(growth["name"])).ends_with("Lv 12")
	# the level moved it: a stat outside the list gets a cell of its own (bug 5)
	assert_bool(SOURCES.grid_stats(Run.player_sheet, PauseScreen.STATS).has("debuff_duration")).is_true()
	# Berserk: a timed buff with its seconds left, after the items; weapon speed listed while it runs
	Run.add_or_level_passive("brawn")
	var rage: PickupDef = Registry.pickup("rage")
	Run.add_timed_effects(rage.id, rage.display_name, rage.effects, 14.0)
	var might: Array = _rows("might")[SOURCES.RUN]
	var last: Dictionary = might[might.size() - 1]
	assert_str(str(last["kind"])).is_equal("buff")
	assert_str(str(last["name"])).is_equal(rage.display_name)
	assert_float(float(last["clock"])).is_greater(0.0)
	assert_bool(SOURCES.grid_stats(Run.player_sheet, PauseScreen.STATS).has("haste")).is_true()
	# a stat said in words (the Magnet's pulls) never gets a cell
	Run.add_or_level_passive("magnet")
	assert_bool(SOURCES.grid_stats(Run.player_sheet, PauseScreen.STATS).has("xp_pull_rate")).is_false()


func test_an_effect_aimed_at_weapons_is_not_among_the_heros_rows() -> void:
	_start()
	var m0 := Run.player_sheet.get_stat("might", 1.0)
	Run.player_sheet.add_effect(Effect.make("might", "mul", 0.5, "all_weapons"), "passive:test_aimed")
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(m0, 0.0001)
	# bug 4: neither the old breakdown nor the new rows list it, so the rows add up to the number
	for b: Dictionary in Run.player_sheet.breakdown("might"):
		assert_str(str(b["source"])).is_not_equal("passive:test_aimed")
	for r: Dictionary in _rows("might")[SOURCES.RUN]:
		assert_str(str(r["sid"])).is_not_equal("passive:test_aimed")
	assert_bool(SOURCES.changed(Run.player_sheet, "might")).is_false()
	Run.player_sheet.remove_source("passive:test_aimed")


func test_a_running_bonus_goes_by_the_item_that_gives_it() -> void:
	_start()
	Run.add_or_level_passive("hot_streak")
	Run.streak = 4000
	Run.rebuild_sheets()
	var rows: Array = _rows("might")[SOURCES.RUN]
	var hs := _row(rows, "passive:hot_streak|mul")
	assert_dict(hs).is_not_empty()
	assert_str(str(hs["name"])).contains(Registry.passive("hot_streak").display_name)
	assert_object(hs["icon"]).is_not_null()
	# its words on the sheet are kept for the older tests
	var named := false
	for b: Dictionary in Run.player_sheet.breakdown("might"):
		if str(b["source"]).begins_with("Hot Streak"):
			named = true
	assert_bool(named).is_true()


# ---------------------------------------------------------------- the Results unlocks

func test_an_owned_hero_is_never_announced_nor_for_sale_nor_in_progress() -> void:
	var q: QuestDef = Registry.quest_for("character", "calavera")
	assert_object(q).is_not_null()
	# bought (or given by the developer menu) before his quest was done
	Save.heroes_owned().append("calavera")
	assert_bool(QT.owned_reward(q)).is_true()
	Save.mark_once("boss_red_canyon_1")
	var done: Array = QT.check_all(true)
	assert_bool(Save.quest_done(q.id)).is_true()
	assert_bool(done.has(q.id)).is_false()
	assert_bool(QT.just_completed.has(q.id)).is_false()
	# never in the progress either
	assert_array(RESULTS.progress_list({q.id: 0})).is_empty()
	# put there anyway (a tool, an older run): the Results screen leaves him out
	QT.just_completed = [q.id]
	_start("astro")
	QT.just_completed = [q.id]
	Run.died = true
	(Save.data["hints_seen"] as Array).append("results")
	Run.last_result = {"gold_before": 100, "banked": 30, "lost": 0, "strongbox": 0, "prev_best": {}}
	Run.damage_by_weapon = {"gravity_gun": 50.0}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	await get_tree().process_frame
	assert_object(r.find_child("Unlocks", true, false)).is_null()
	r.visible = false
	# a free hero is owned exactly when his quest is done: his quest still unlocks him
	var iq: QuestDef = Registry.quest_for("character", "ironwood")
	if iq:
		assert_bool(QT.owned_reward(iq)).is_false()


func test_a_hero_on_sale_reads_for_sale_and_one_owned_does_not() -> void:
	var q: QuestDef = Registry.quest_for("character", "calavera")
	Save.mark_quest(q.id)
	var rs: Control = auto_free(RESULTS.new())
	var p1: Control = auto_free(rs._unlocked(q))
	assert_bool(bool(p1.get_meta("on_sale"))).is_true()
	Save.heroes_owned().append("calavera")
	var p2: Control = auto_free(rs._unlocked(q))
	assert_bool(bool(p2.get_meta("on_sale"))).is_false()


func test_unlocked_this_run_is_never_stale() -> void:
	var q: QuestDef = Registry.quest_for("character", "ironwood")
	assert_object(q).is_not_null()
	# a run's start empties it
	QT.just_completed = ["unlock_something_old"]
	_start()
	assert_array(QT.just_completed).is_empty()
	# the title's quiet check completes a quest the save's totals meet, but it is no run's unlock
	Run.end()
	(Save.data["totals"] as Dictionary)["kills"] = 999999
	var quiet: Array = QT.check_all(false)
	assert_bool(Save.quest_done(q.id)).is_true()
	assert_bool(quiet.has(q.id)).is_true()
	assert_bool(QT.just_completed.has(q.id)).is_false()
	# the same in a run is
	(Save.data["quests_done"] as Array).erase(q.id)
	assert_bool(Save.quest_done(q.id)).is_false()
	var loud: Array = QT.check_all(true)
	assert_bool(loud.has(q.id)).is_true()
	assert_bool(QT.just_completed.has(q.id)).is_true()


# ---------------------------------------------------------------- the Revolver's tracer

func test_the_revolver_tracer_is_dim_red_and_thicker_and_its_mutations_keep_theirs() -> void:
	_start()
	var pm: ProjectileManager = auto_free(ProjectileManager.new())
	var plain := WeaponInstance.new(Registry.weapon("revolver"), 1)
	plain.rebuild(Run.player_sheet, [plain])
	# (pass 79, lane FX: Garry's "dark red transparent" line, its colour and alpha read off the content)
	var red := Color(str(plain.params["tracer_color"]))
	assert_float(red.r).is_greater(red.g * 3.0)
	assert_bool(pm._tracer_colour(plain).is_equal_approx(Color(red.r, red.g, red.b, float(plain.params["tracer_alpha"])))).is_true()
	assert_float(float(plain.params.get("tracer_size", 0.9))).is_equal_approx(1.35, 0.0001)
	# no bead within tracer_clear of the hero (the dim red over him read as blood); a weapon without it drops them anywhere
	var hero: Node3D = auto_free(Node3D.new())
	add_child(hero)
	hero.global_position = Vector3(4, 0, 4)
	var clear := float(plain.params.get("tracer_clear", 0.0))
	assert_float(clear).is_greater(0.0)
	assert_bool(ProjectileManager._tracer_clear_of(plain, Vector3(4.3, 1.2, 4.2), hero)).is_false()
	assert_bool(ProjectileManager._tracer_clear_of(plain, Vector3(4.0 + clear + 0.1, 1.2, 4.0), hero)).is_true()
	var tommy := WeaponInstance.new(Registry.weapon("tommy_gun"), 1)
	assert_bool(ProjectileManager._tracer_clear_of(tommy, Vector3(4.3, 1.2, 4.2), hero)).is_true()
	# Silver Bullet keeps its silver (pass 79: its own tracer_color, the pale silver-blue its line is drawn in), Venom
	# Rounds its green
	var sv := Color(str(Registry.mutation("silver_bullet").params["tracer_color"]))
	for pair in [["silver_bullet", Color(sv.r, sv.g, sv.b, float(Registry.mutation("silver_bullet").params.get("tracer_alpha", 0.9)))],
			["venom_rounds", Color(0.5, 1.0, 0.35, 0.9)]]:
		var w := WeaponInstance.new(Registry.weapon("revolver"), 1)
		w.mutations.append(Registry.mutation(str(pair[0])))
		w.rebuild(Run.player_sheet, [w])
		assert_bool(pm._tracer_colour(w).is_equal_approx(pair[1])).override_failure_message(str(pair[0])).is_true()
	# the Golden Revolver: silver as before (pass 79: its final form's silver line, the Silver Bullet's colour)
	var gold := WeaponInstance.new(Registry.weapon("golden_revolver"), 1)
	gold.rebuild(Run.player_sheet, [gold])
	assert_bool(gold.def.params.has("tracer_color")).is_false()
	assert_bool(pm._tracer_colour(gold).is_equal_approx(Color(sv.r, sv.g, sv.b, 0.9))).is_true()
	# a mutation's own tracer colour still comes first (Toxic Peas' green on the Peashooter)
	var pea := WeaponInstance.new(Registry.weapon("peashooter"), 1)
	pea.mutations.append(Registry.mutation("toxic_peas"))
	pea.rebuild(Run.player_sheet, [pea])
	var tp := Color("#6ED834")
	assert_bool(pm._tracer_colour(pea).is_equal_approx(Color(tp.r, tp.g, tp.b, 0.9))).is_true()
