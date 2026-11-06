## Pass 129, lane TRAIL-SETUP: the Trail's first set, read from the game's own file (content/trail/trail.json; the
## design lives in tools/trail_setup.py, Garry edits the file in the Level Editor). Shape rules, never his numbers: 100
## nodes, a plain opening, more special nodes each third, no upgrade type twice within five levels, no unlock in a
## choice, the outlaws in title order, both late stages gated, check() clean, a rising price curve, and the two fits'
## bands: the power of node 100 against today's full Upgrade board (HeroPower), and the runs the purse model needs
## (BALANCING.md pass 129; the model's numbers below are tools/trail_setup.py's STAGES and LEARN).
extends GdUnitTestSuite

const UNLOCKS := ["outlaw", "skin", "weapon", "passive", "stage", "map", "structure", "powerup", "feature"]
const OUTLAWS := ["astro", "calavera", "solenne", "fadeaway", "buck", "may"]
const PLAIN_WEAPONS := [["revolver", 5], ["molotov", 4], ["orbit_saws", 4], ["boomstick", 3], ["tommy_gun", 3]]
const PLAIN_PASSIVES := [["brawn", 3], ["vigour", 3], ["mend", 2], ["reach", 2], ["quickdraw", 2]]
## the purse model (tools/trail_setup.py): [clear purse, open level, share at open, ready level, bounty]
const STAGES := [[1200.0, 0, 0.25, 8, 150.0], [4000.0, 8, 0.30, 18, 150.0], [5300.0, 18, 0.35, 27, 200.0], [12000.0, 36, 0.25, 55, 250.0]]
const LEARN := [0.1, 0.4, 0.7, 0.9]

var _nodes: Array = []
var _top := 0


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	Trail.load_from()
	_nodes = Trail.nodes()
	_top = Trail.levels()


func after_test() -> void:
	Run.end()
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()


func _is_up(n: Dictionary) -> bool:
	return str((n["gives"] as Dictionary).get("type", "")) == "upgrade"


func _type(n: Dictionary) -> String:
	return str((n["gives"] as Dictionary).get("upgrade", ""))


func _third(level: int) -> int:
	return 0 if level <= int(round(_top / 3.0)) else (1 if level <= int(round(2.0 * _top / 3.0)) else 2)


## The choice groups in file order, each its member ids.
func _groups() -> Array:
	var out: Array = []
	var seen := {}
	for n: Dictionary in _nodes:
		if str(n["kind"]) == "choice" and not seen.has(str(n["id"])):
			var g: Array = Trail.group(str(n["id"]))
			for id: String in g:
				seen[id] = true
			out.append(g)
	return out


## Every required node of levels 1..level, the choices taken evenly (the k-th group its member (k + pattern) mod size).
func _bought(level: int, pattern: int = 0) -> Array:
	var pick := {}
	var k := 0
	for g: Array in _groups():
		pick[str(g[(k + pattern) % g.size()])] = true
		k += 1
	var out: Array = []
	for n: Dictionary in _nodes:
		if int(n["level"]) <= level and (str(n["kind"]) == "node" or pick.has(str(n["id"]))):
			out.append(str(n["id"]))
	return out


func _level_of(type: String, id: String) -> int:
	return Trail.level_for(type, id)


func test_the_set_is_100_nodes_under_to_be_continued() -> void:
	assert_int(_nodes.size()).is_equal(100)
	assert_bool(_top >= 60 and _top <= 80).override_failure_message("%d levels" % _top).is_true()
	assert_str(Trail.end_text()).is_equal("To be continued")
	for l in range(1, _top + 1):
		var required := Trail.nodes_on(l).filter(func(n: Dictionary) -> bool: return str(n["kind"]) != "optional")
		assert_bool(required.is_empty()).override_failure_message("level %d has no required node" % l).is_false()
		assert_bool(Trail.nodes_on(l).size() <= 4).override_failure_message("level %d holds more than 4" % l).is_true()


func test_the_game_and_the_file_agree_the_trail_is_sound() -> void:
	assert_array(Trail.check(Trail.read_file(Trail.DEFAULT))).is_empty()
	assert_bool(Trail.has_nodes()).is_true()


func test_the_opening_is_eight_plain_upgrades_each_a_different_one() -> void:
	var seen := {}
	for l in range(1, 9):
		var row := Trail.nodes_on(l)
		assert_int(row.size()).override_failure_message("level %d" % l).is_equal(1)
		assert_str(str(row[0]["kind"])).is_equal("node")
		assert_bool(_is_up(row[0])).override_failure_message("level %d is no upgrade" % l).is_true()
		seen[_type(row[0])] = true
	assert_int(seen.size()).is_equal(8)
	for n: Dictionary in _nodes:
		if str(n["kind"]) == "choice":
			assert_bool(int(n["level"]) >= 9).override_failure_message("a choice at level %d" % int(n["level"])).is_true()
		if str(n["kind"]) == "optional":
			assert_bool(int(n["level"]) >= 10).override_failure_message("an optional node at level %d" % int(n["level"])).is_true()


func test_special_nodes_take_a_larger_share_each_third() -> void:
	var all := [0, 0, 0]
	var special := [0, 0, 0]
	var choice_levels := [{}, {}, {}]
	for n: Dictionary in _nodes:
		var t := _third(int(n["level"]))
		all[t] += 1
		if str(n["kind"]) != "node":
			special[t] += 1
		if str(n["kind"]) == "choice":
			(choice_levels[t] as Dictionary)[int(n["level"])] = true
	var share: Array = []
	for t in range(3):
		share.append(float(special[t]) / float(maxi(all[t], 1)))
	assert_bool(share[0] < share[1] and share[1] < share[2]).override_failure_message("special shares by third %s" % [share]).is_true()
	assert_bool((choice_levels[0] as Dictionary).size() <= (choice_levels[1] as Dictionary).size()
		and (choice_levels[1] as Dictionary).size() <= (choice_levels[2] as Dictionary).size()).override_failure_message("choice levels by third").is_true()
	# most nodes are regular, and the late third has a three-way and a four-way choice
	assert_bool(float(special[0] + special[1] + special[2]) / 100.0 < 0.5).is_true()
	var sizes := {}
	for g: Array in _groups():
		assert_bool(g.size() >= 2 and g.size() <= 4).is_true()
		if _third(int(Trail.node(str(g[0]))["level"])) == 2:
			sizes[g.size()] = true
	assert_bool(sizes.has(3) and sizes.has(4)).override_failure_message("late choices of sizes %s" % [sizes.keys()]).is_true()
	# rails meet: three to five nodes hang on two or three others
	var meet := _nodes.filter(func(n: Dictionary) -> bool: return (n["from"] as Array).size() >= 2)
	assert_bool(meet.size() >= 3 and meet.size() <= 5).override_failure_message("%d nodes where rails meet" % meet.size()).is_true()


func test_no_upgrade_type_comes_twice_within_five_levels() -> void:
	var last := {}
	for n: Dictionary in _nodes:
		if not _is_up(n):
			continue
		var t := _type(n)
		if last.has(t):
			var gap := int(n["level"]) - int(last[t])
			assert_bool(gap >= 5).override_failure_message("%s at levels %d and %d" % [t, int(last[t]), int(n["level"])]).is_true()
		last[t] = int(n["level"])
	# every upgrade type the file defines is used
	for t: Variant in Trail.upgrade_types():
		assert_bool(last.has(str(t))).override_failure_message("upgrade type %s is never used" % str(t)).is_true()


func test_a_choice_is_between_upgrades_never_an_unlock() -> void:
	for n: Dictionary in _nodes:
		var type := str((n["gives"] as Dictionary).get("type", ""))
		if UNLOCKS.has(type):
			assert_str(str(n["kind"])).override_failure_message("%s: an unlock that is %s" % [str(n["id"]), str(n["kind"])]).is_equal("node")
	for g: Array in _groups():
		var types := {}
		for id: String in g:
			types[_type(Trail.node(id))] = true
		assert_int(types.size()).override_failure_message("a choice repeats a type").is_equal(g.size())


func test_the_outlaws_come_in_title_order_at_their_own_prices() -> void:
	var levels: Array = []
	for id: String in OUTLAWS:
		assert_bool(Trail.gated("outlaw", id)).override_failure_message(id).is_true()
		levels.append(_level_of("outlaw", id))
		var c: CharacterDef = Registry.character(id)
		assert_int(Trail.price(str(Trail.gate("outlaw", id)["id"]))).override_failure_message(id).is_equal(c.price)
		assert_str(Registry.hero_state(c)).is_equal("locked")
		assert_str(Registry.hero_requirement_text(c)).is_equal("Reach Trail Level %d" % _level_of("outlaw", id))
		assert_object(Registry.quest_for("character", id)).override_failure_message("%s still has an unlock quest" % id).is_null()
	var sorted := levels.duplicate()
	sorted.sort()
	assert_array(levels).is_equal(sorted)
	assert_bool(int(levels[0]) <= 10 and int(levels[levels.size() - 1]) >= 40 and int(levels[levels.size() - 1]) <= 50).override_failure_message("outlaw levels %s" % [levels]).is_true()
	# the Drifter is free and Ironwood is bought on the Outlaws screen: no node names them
	assert_bool(Trail.gated("outlaw", "drifter") or Trail.gated("outlaw", "ironwood")).is_false()
	assert_str(Registry.hero_state(Registry.character("ironwood"))).is_equal("buyable")


func test_the_dust_bowl_and_blood_moon_are_trail_unlocks_and_the_first_two_stages_are_not() -> void:
	assert_bool(Trail.gated("stage", "red_canyon:dust")).is_true()
	assert_bool(Trail.gated("stage", "red_canyon:s3")).is_true()
	assert_bool(Trail.gated("stage", "red_canyon:s1") or Trail.gated("stage", "red_canyon:s2")).is_false()
	assert_bool(_level_of("stage", "red_canyon:dust") < _level_of("stage", "red_canyon:s3")).is_true()
	# the boss before each still has to be beaten, and the node bought
	for i in range(3):
		Save.mark_stage_beaten("red_canyon", i)
	Trail.refresh()
	var beaten_only := Save.stage_unlocked("red_canyon", 2)
	Save.data["trail"] = {"bought": _bought(_level_of("stage", "red_canyon:dust")), "spent": 0, "had": []}
	Trail.refresh()
	assert_bool(beaten_only).is_false()
	assert_bool(Save.stage_unlocked("red_canyon", 2)).is_true()
	assert_bool(Save.stage_unlocked("red_canyon", 3)).is_false()


func test_eight_items_moved_off_their_quests_and_the_dynamite_kept_its_own() -> void:
	var items := _nodes.filter(func(n: Dictionary) -> bool: return ["weapon", "passive"].has(str((n["gives"] as Dictionary).get("type", ""))))
	assert_int(items.size()).is_equal(8)
	for n: Dictionary in items:
		var type := str(n["gives"]["type"])
		var id := str(n["gives"]["id"])
		assert_object(Registry.weapon(id) if type == "weapon" else Registry.passive(id)).override_failure_message(id).is_not_null()
		assert_object(Registry.quest_for(type, id)).override_failure_message("%s still has an unlock quest" % id).is_null()
		assert_bool(Registry.is_unlocked(type, id)).override_failure_message(id).is_false()
		assert_bool(int(n["level"]) >= 6 and int(n["level"]) <= 60).override_failure_message("%s at level %d" % [id, int(n["level"])]).is_true()
	assert_bool(Trail.gated("weapon", "lob_grenade")).is_false()
	assert_object(Registry.quest_for("weapon", "lob_grenade")).is_not_null()
	# no structure, power-up, feature, map or skin node in this set
	for n: Dictionary in _nodes:
		assert_bool(["structure", "powerup", "feature", "map", "skin"].has(str((n["gives"] as Dictionary).get("type", "")))).is_false()


func test_stakes_are_four_and_four_optional_nodes_never_two_on_a_level() -> void:
	for t: String in ["stakes", "boss_stakes"]:
		var st := _nodes.filter(func(n: Dictionary) -> bool: return _is_up(n) and _type(n) == t)
		assert_int(st.size()).override_failure_message(t).is_equal(4)
		for n: Dictionary in st:
			assert_str(str(n["kind"])).is_equal("optional")
			assert_float(float(n["gives"]["value"])).is_equal_approx(0.1, 0.0001)
	for l in range(1, _top + 1):
		var n := Trail.nodes_on(l).filter(func(x: Dictionary) -> bool: return _is_up(x) and ["stakes", "boss_stakes"].has(_type(x))).size()
		assert_bool(n <= 1).override_failure_message("level %d holds %d Stakes nodes" % [l, n]).is_true()


func test_count_milestones_are_rare_named_and_dearer() -> void:
	for t: String in ["amount", "extra_life", "reroll", "skip", "banish"]:
		var ms := _nodes.filter(func(n: Dictionary) -> bool: return _is_up(n) and _type(n) == t)
		assert_bool(ms.size() >= 1 and ms.size() <= 2).override_failure_message("%s: %d nodes" % [t, ms.size()]).is_true()
		for n: Dictionary in ms:
			assert_str(str(n["name"])).override_failure_message("%s has no name" % str(n["id"])).is_not_empty()
			assert_bool(float(n["price_mult"]) > 1.0).override_failure_message("%s has no price multiplier" % str(n["id"])).is_true()


func test_the_price_curve_rises_and_the_first_node_is_nearly_free() -> void:
	var cfg: Dictionary = Trail.read_file(Trail.DEFAULT)["price"]
	var prev := 0
	for l in range(1, _top + 1):
		var p := Trail.price_at(cfg, l)
		assert_bool(p >= prev).override_failure_message("the curve falls at level %d" % l).is_true()
		prev = p
	assert_bool(Trail.price(str(_nodes[0]["id"])) <= 20).is_true()
	for l in range(2, 9):
		assert_bool(Trail.price(str(Trail.nodes_on(l)[0]["id"])) < Registry.character("astro").price).override_failure_message("level %d is not cheap" % l).is_true()


## The Drifter's power (HeroPower) at level 30 with a plain build, under the save as it stands.
func _power() -> float:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.debug_clear_items()
	for w: Array in PLAIN_WEAPONS:
		Run.debug_set_item("weapon", str(w[0]), int(w[1]))
	for p: Array in PLAIN_PASSIVES:
		Run.debug_set_item("passive", str(p[0]), int(p[1]))
	Run.level = 30
	Run.rebuild_sheets()
	HeroPower.forget()
	var out := float(HeroPower.measure(Run.weapons, Run.player_sheet)["power"])
	Run.end()
	return out


func _trail_power(level: int) -> float:
	var sum := 0.0
	for pattern in range(2):
		Save.data["trail"] = {"bought": _bought(level, pattern), "spent": 0, "had": []}
		Trail.refresh()
		sum += _power()
	Save.data["trail"] = {"bought": [], "spent": 0, "had": []}
	Trail.refresh()
	return sum / 2.0


## Fit 1 (BALANCING.md pass 129): node 100 leaves the Drifter 1.25 to 1.4 times as strong as today's full Upgrade
## board in its strongest forms (Muscle, Plate, Poultice at rank 7); a quarter of the board's gain where the Dust Bowl
## opens and half where Blood Moon does, each within a wide margin (the stage nodes sit "within a few levels").
func test_fit_1_the_power_of_the_trail_against_the_full_board() -> void:
	var fresh := _power()
	var seven := [0, 0, 0, 0, 0, 0, 0]
	var ones := [1, 1, 1, 1, 1, 1, 1]
	Save.data["talents"] = {"drive": {"picks": seven, "rank": 7, "form": 0}, "grit": {"picks": ones, "rank": 7, "form": 1}, "study": {"picks": ones, "rank": 7, "form": 1}}
	var board := _power() / fresh
	Save.data["talents"] = {}
	assert_bool(board > 1.8).override_failure_message("the full board measures x%.2f" % board).is_true()
	var top := _trail_power(_top) / fresh
	assert_bool(top / board >= 1.25 and top / board <= 1.4).override_failure_message("node 100 is x%.3f of the full board (1.25 to 1.4)" % (top / board)).is_true()
	var dust := (_trail_power(_level_of("stage", "red_canyon:dust")) / fresh - 1.0) / (board - 1.0)
	var moon := (_trail_power(_level_of("stage", "red_canyon:s3")) / fresh - 1.0) / (board - 1.0)
	assert_bool(dust >= 0.15 and dust <= 0.35).override_failure_message("the Dust Bowl opens at %.0f%% of the board's gain (about a quarter)" % (dust * 100.0)).is_true()
	assert_bool(moon >= 0.38 and moon <= 0.62).override_failure_message("Blood Moon opens at %.0f%% of the board's gain (about half)" % (moon * 100.0)).is_true()


## The purse model (tools/trail_setup.py `purse`): the best-paying stage open at this Trail level.
func _purse(run: int, level: int, greed: float) -> int:
	var best := 0.0
	for s: Array in STAGES:
		if level < int(s[1]):
			continue
		var f := minf(1.0, float(level - int(s[1])) / float(maxi(int(s[3]) - int(s[1]), 1)))
		best = maxf(best, (float(s[0]) * (1.0 + greed) + float(s[4])) * (float(s[2]) + (1.0 - float(s[2])) * f))
	if run <= LEARN.size():
		best *= float(LEARN[run - 1])
	return int(round(best))


## Fit 2 (BALANCING.md pass 129): by the purse model the first node is bought after run 1, about 35 of the 100 nodes
## lie on done levels by run 20, about 65 by run 50, and every required node and outlaw is bought by about run 100
## (optional nodes outside the budget).
func test_fit_2_about_a_hundred_runs_for_the_hundred_nodes() -> void:
	var order: Array = _bought(_top)
	var last_of := {}
	for i in range(order.size()):
		last_of[int(Trail.node(str(order[i]))["level"])] = i
	var gold := 0
	var i := 0
	var level := 0
	var greed := 0.0
	var by := {}
	var done_run := 0
	for run in range(1, 301):
		gold += _purse(run, level, greed)
		while i < order.size() and Trail.price(str(order[i])) <= gold:
			var n := Trail.node(str(order[i]))
			gold -= Trail.price(str(order[i]))
			if _is_up(n) and _type(n) == "greed":
				greed += float(n["gives"]["value"])
			if int(last_of[int(n["level"])]) == i:
				level = int(n["level"])
			i += 1
		by[run] = _nodes.filter(func(n: Dictionary) -> bool: return int(n["level"]) <= level).size()
		if level >= _top:
			done_run = run
			break
	assert_bool(int(by[1]) >= 1).override_failure_message("no node after run 1").is_true()
	assert_bool(int(by[5]) >= 7).override_failure_message("%d nodes after five runs" % int(by[5])).is_true()
	assert_bool(absi(int(by.get(20, 100)) - 35) <= 6).override_failure_message("%d nodes by run 20 (about 35)" % int(by.get(20, 100))).is_true()
	assert_bool(absi(int(by.get(50, 100)) - 65) <= 6).override_failure_message("%d nodes by run 50 (about 65)" % int(by.get(50, 100))).is_true()
	assert_bool(done_run >= 90 and done_run <= 110).override_failure_message("every required node at run %d (about 100)" % done_run).is_true()
