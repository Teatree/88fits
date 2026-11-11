## Pass 141, lane TRAIL (Garry, Polish #4): "The 2 lanes seem redundant, I can't progress unless I buy both ... I'd rather
## have fewer variety and higher value increase to the power nodes. Also it's ok to just increase the total number of
## levels"; "Highlight the Unlock item nodes"; "All Skins should be locked behind either a task or in the Trail ... They are
## the 2nd skin, so they should be at least x3 times harder to get than the first one". The Trail read from the game's own
## file (content/trail/trail.json, written by tools/trail_setup.py); BALANCING.md 82.TRAIL.
extends GdUnitTestSuite

const SWAPS := preload("res://tests/fixtures/skin_swaps.gd")
const TRAIL140 := "res://tests/fixtures/trail_pass140.json"
const SCENE := "res://ui/TrailScreen.tscn"
const PLAIN_WEAPONS := [["revolver", 5], ["molotov", 4], ["orbit_saws", 4], ["boomstick", 3], ["tommy_gun", 3]]
const PLAIN_PASSIVES := [["brawn", 3], ["vigour", 3], ["mend", 2], ["reach", 2], ["quickdraw", 2]]
## Garry's very good run (pass 126, game/tests/pass126_SKINS_test.gd): five of them is what a skin's goal across runs asks
## at least; a feat of one run takes about one run with the outlaw (one and a half at most)
const RUN_DAMAGE := {"revolver": 61929.0, "gravity_gun": 44530.0}
const RUN_DAMAGE_ANY := 60000.0
const RUN_KILLS_ONE_WEAPON := 600.0
const RUN_HEAL_DEATH := 1824.4 * 0.75
const RUN_FIRE := 80449.0
const FEAT_RUNS := 1.5
const FEAT_TYPES := ["item_level", "hero_level", "evolve_item", "weapon_paths", "items_maxed"]
## The journey model (python tools/trail_setup.py --tables, the measured purses): the Trail Level bought by run 15, three
## times the five runs a feat of Astro's takes at most (he is open from the start)
const TRAIL_LEVEL_AT_RUN_15 := 38

var _nodes: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	Trail.load_from()
	_nodes = Trail.nodes()


func after_test() -> void:
	Run.end()
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()


func _type(n: Dictionary) -> String:
	return str((n["gives"] as Dictionary).get("type", ""))


# ---------------------------------------------------------------- one lane

func test_every_level_holds_one_thing_to_buy() -> void:
	# a plain node or one choice group; the optional nodes beside it
	assert_int(Trail.levels()).is_greater(70)
	for l in range(1, Trail.levels() + 1):
		var plain := 0
		var groups := {}
		for n: Dictionary in Trail.nodes_on(l):
			match str(n["kind"]):
				"node":
					plain += 1
				"choice":
					groups[str(n.get("group", ""))] = true
		var one := (plain == 1 and groups.is_empty()) or (plain == 0 and groups.size() == 1)
		assert_bool(one).override_failure_message("level %d: %d plain nodes and %d choice groups" % [l, plain, groups.size()]).is_true()


func test_the_mix_of_choice_optional_and_meeting_nodes_stays() -> void:
	var groups := {}
	var choice := 0
	var optional := 0
	var meet: Array = []
	for n: Dictionary in _nodes:
		match str(n["kind"]):
			"choice":
				choice += 1
				groups["%d:%s" % [int(n["level"]), str(n.get("group", ""))]] = true
			"optional":
				optional += 1
		if (n.get("from", []) as Array).size() >= 2:
			meet.append(n)
	assert_int(groups.size()).is_equal(12)
	assert_int(choice).is_equal(28)
	assert_int(optional).is_equal(10)
	assert_int(meet.size()).is_equal(3)
	# the rails meet from every member of the choice group right below, whichever was taken (need any)
	for n: Dictionary in meet:
		assert_str(str(n["need"])).override_failure_message(str(n["id"])).is_equal("any")
		var below := Trail.nodes_on(int(n["level"]) - 1).filter(func(m: Dictionary) -> bool: return str(m["kind"]) == "choice")
		assert_int(below.size()).override_failure_message(str(n["id"])).is_equal((n["from"] as Array).size())
		for m: Dictionary in below:
			assert_bool((n["from"] as Array).has(str(m["id"]))).override_failure_message(str(n["id"])).is_true()
	# a meeting node opens once one member below is taken
	var g: Array = Trail.group(str((meet[0]["from"] as Array)[0]))
	var upto: Array = []
	for m: Dictionary in _nodes:
		if int(m["level"]) < int(meet[0]["level"]) - 1 and str(m["kind"]) != "optional":
			if str(m["kind"]) == "node" or str(m["id"]) == str(Trail.group(str(m["id"]))[0]):
				upto.append(str(m["id"]))
	upto.append(str(g[g.size() - 1]))
	Save.data["trail"] = {"bought": upto, "spent": 0, "had": []}
	Trail.refresh()
	assert_str(Trail.state(str(meet[0]["id"]))).is_equal("open")
	assert_array(Trail.check(Trail.read_file(Trail.DEFAULT))).is_empty()


func test_fewer_power_nodes_with_bigger_amounts_and_every_unlock_on_its_own_level() -> void:
	var t140 := Trail.read_file(TRAIL140)
	var count140 := 0
	for n: Dictionary in t140["nodes"]:
		if str(n["kind"]) == "node" and str((n["gives"] as Dictionary).get("type", "")) == "upgrade":
			count140 += 1
	var count := 0
	var unlocks := 0
	for n: Dictionary in _nodes:
		if str(n["kind"]) != "node":
			continue
		if _type(n) == "upgrade":
			count += 1
		else:
			unlocks += 1
			assert_int(Trail.nodes_on(int(n["level"])).filter(func(m: Dictionary) -> bool: return str(m["kind"]) != "optional").size()).is_equal(1)
	assert_int(count).is_less(count140)
	assert_int(unlocks).is_equal(36)
	# the unlocks come in pass 140's order
	var order140: Array = []
	for n: Dictionary in t140["nodes"]:
		var g: Dictionary = n["gives"]
		if str(g.get("type", "")) != "upgrade":
			order140.append(str(g.get("id", g.get("stage", ""))).get_slice(":", 0))
	var order: Array = []
	for n: Dictionary in _nodes:
		var g: Dictionary = n["gives"]
		if str(g.get("type", "")) != "upgrade":
			order.append(str(g.get("id", g.get("stage", ""))).get_slice(":", 0))
	assert_array(order).is_equal(order140)
	# four thin types left the Trail (their blocks stay for the Level Editor)
	for t: String in ["shot_speed", "care_package", "grip", "loose_coins"]:
		assert_bool(Trail.upgrade_types().has(t)).is_true()
		assert_int(_nodes.filter(func(n: Dictionary) -> bool: return _type(n) == "upgrade" and str(n["gives"]["upgrade"]) == t).size()).override_failure_message(t).is_equal(0)


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


## Every required node of the Trail loaded now, the k-th choice group taking its member (k + pattern) mod its size.
func _all_bought(pattern: int) -> Array:
	var pick := {}
	var k := 0
	var seen := {}
	for n: Dictionary in Trail.nodes():
		if str(n["kind"]) == "choice" and not seen.has(str(n["id"])):
			var g: Array = Trail.group(str(n["id"]))
			for id: String in g:
				seen[id] = true
			pick[str(g[(k + pattern) % g.size()])] = true
			k += 1
	var out: Array = []
	for n: Dictionary in Trail.nodes():
		if str(n["kind"]) == "node" or pick.has(str(n["id"])):
			out.append(str(n["id"]))
	return out


func _end_power() -> float:
	var sum := 0.0
	for pattern in range(2):
		Save.data["trail"] = {"bought": _all_bought(pattern), "spent": 0, "had": []}
		Trail.refresh()
		sum += _power()
	Save.data["trail"] = {"bought": [], "spent": 0, "had": []}
	Trail.refresh()
	return sum / 2.0


func test_the_last_level_is_at_least_as_strong_as_pass_140s() -> void:
	var fresh := _power()
	var now := _end_power() / fresh
	Trail.load_from(TRAIL140)
	var before := _end_power() / fresh
	Trail.load_from()
	assert_bool(now >= before * 0.999).override_failure_message("the last level is x%.3f of a fresh save, pass 140's x%.3f" % [now, before]).is_true()
	# (this build measures pass 140's last level at about x3.19; the probe's own build x3.28)
	assert_bool(now >= 3.0).override_failure_message("x%.3f" % now).is_true()


# ---------------------------------------------------------------- the unlock nodes stand out

func test_an_unlock_tile_stands_out_and_an_owned_one_reads_owned() -> void:
	# the first unlock and the power node right before it (both in view once it is bought)
	var first_unlock := ""
	var first_power := ""
	for n: Dictionary in _nodes:
		if first_unlock != "":
			break
		if TrailScreen.is_unlock(n):
			first_unlock = str(n["id"])
		else:
			first_power = str(n["id"])
	var lvl := int(Trail.node(first_unlock)["level"])
	var bought: Array = []
	for n: Dictionary in _nodes:
		if int(n["level"]) <= lvl and str(n["kind"]) == "node":
			bought.append(str(n["id"]))
	Save.data["trail"] = {"bought": bought, "spent": 0, "had": []}
	Save.data["gold"] = 0
	Trail.refresh()
	var s: Control = auto_free(load(SCENE).instantiate())
	add_child(s)
	for k in 6:
		await get_tree().process_frame
	var ts := s as TrailScreen
	var u: Variant = ts.tile_of(first_unlock)
	var p: Variant = ts.tile_of(first_power)
	assert_object(u).is_not_null()
	assert_object(p).is_not_null()
	assert_bool(bool(u.get("unlock"))).is_true()
	assert_bool(bool(p.get("unlock"))).is_false()
	assert_str(str(u.get("state"))).is_equal("bought")
	# its face in the thing's rarity colours, the tab's words by state
	assert_str(str(u.get("rarity"))).is_equal(TrailScreen.unlock_rarity(Trail.node(first_unlock)))
	assert_str(Loc.t("ui.trail.tag.unlock")).is_equal("UNLOCK")
	assert_str(Loc.t("ui.trail.tag.unlocked")).is_equal("UNLOCKED")
	# Garry: "For owned item write 'owned' not 'yours'"
	assert_str(TrailScreen.state_words(Trail.node(first_unlock)).to_lower()).is_equal("owned")
	assert_str(Loc.t("ui.trail.tag.yours").to_lower()).is_equal("owned")
	# an outlaw, a skin and a stage are gold, an item its own rarity
	for n: Dictionary in _nodes:
		if ["outlaw", "skin", "stage"].has(_type(n)):
			assert_str(TrailScreen.unlock_rarity(n)).is_equal("legendary")
		elif _type(n) == "passive":
			assert_str(TrailScreen.unlock_rarity(n)).is_equal(W.rarity_of(Registry.passive(str(n["gives"]["id"]))))
	assert_array(Loc.warnings()).is_empty()


# ---------------------------------------------------------------- every skin locked, the second x3 the first

## Every skin an outlaw sells: [CharacterDef, code], the look every player owns left out.
func _skins() -> Array:
	var out: Array = []
	for c: CharacterDef in Registry.characters.values():
		if c.hidden:
			continue
		for code in c.variants.keys():
			if str(code) != c.home_look() and c.sells_skin(str(code)) and not c.variant_shelved(str(code)):
				out.append([c, str(code)])
	return out


func test_every_skin_is_behind_a_task_or_the_trail() -> void:
	var n := 0
	for pair: Array in _skins():
		var c: CharacterDef = pair[0]
		var code := str(pair[1])
		var key := Registry.skin_key(c.id, code)
		var q := Registry.skin_quest(c, code)
		assert_bool(q != null or Trail.gated("skin", key)).override_failure_message(key + ": on sale from the start").is_true()
		# a fresh save owns none and can buy none, whoever is owned
		Save.data["heroes_owned"] = [c.id]
		Trail.refresh()
		assert_str(Registry.skin_state(c, code)).override_failure_message(key).is_equal("locked")
		n += 1
	assert_int(n).is_greater_equal(10)


func test_an_outlaws_skins_show_cheaper_first() -> void:
	for c: CharacterDef in Registry.characters.values():
		var codes: Array = Registry.skins_of(c)
		for i in range(2, codes.size()):
			assert_bool(c.skin_price(str(codes[i])) >= c.skin_price(str(codes[i - 1]))).override_failure_message("%s %s" % [c.id, codes]).is_true()


## How many runs a skin's goal takes, by pass 126's measure: a feat of one run about one and a half at most; a total
## across runs its count over the very good run's.
func _runs(q: QuestDef) -> float:
	var cond := q.condition
	var t := str(cond.get("type", ""))
	if FEAT_TYPES.has(t):
		return FEAT_RUNS
	var n := float(cond.get("count", 0))
	match t:
		"damage_with_weapon":
			return n / float(RUN_DAMAGE.get(str(cond.get("weapon", "")), RUN_DAMAGE_ANY))
		"kills_with_weapon":
			return n / RUN_KILLS_ONE_WEAPON
		"heal_with_item":
			return n / RUN_HEAL_DEATH
		"element_damage":
			return n / RUN_FIRE
	return 0.0


func test_each_outlaws_second_skin_is_at_least_three_times_the_first() -> void:
	var pairs := 0
	for c: CharacterDef in Registry.characters.values():
		var codes: Array = Registry.skins_of(c)
		if codes.size() < 3:
			continue
		pairs += 1
		var first := str(codes[1])
		var second := str(codes[2])
		var m := "%s: %s then %s" % [c.id, first, second]
		assert_bool(c.skin_price(second) >= c.skin_price(first)).override_failure_message(m + ": price").is_true()
		var q1 := Registry.skin_quest(c, first)
		assert_object(q1).override_failure_message(m + ": the first has no task").is_not_null()
		if Trail.gated("skin", Registry.skin_key(c.id, second)):
			# the Trail's skin: a level the journey model buys at three times the runs of the first's feat or later
			assert_bool(FEAT_TYPES.has(str(q1.condition.get("type", "")))).override_failure_message(m + ": the first is a feat").is_true()
			assert_int(Trail.level_for("skin", Registry.skin_key(c.id, second))).override_failure_message(m).is_greater_equal(TRAIL_LEVEL_AT_RUN_15)
			continue
		var q2 := Registry.skin_quest(c, second)
		assert_object(q2).override_failure_message(m + ": the second has no task").is_not_null()
		# the second waits for the first and takes at least three times the runs
		assert_array(q2.requires).override_failure_message(m + ": waits for the first").contains([q1.id])
		var r1 := _runs(q1)
		var r2 := _runs(q2)
		assert_bool(r1 > 0.0 and r2 >= 3.0 * r1).override_failure_message("%s: %.1f runs then %.1f" % [m, r1, r2]).is_true()
	# the Drifter, Ironwood, Astro and Calavera (pass 143: Fadeaway's two went with him: he is The Robot, with no skins)
	assert_int(pairs).is_equal(4)


func test_solenne_wears_the_dearest_skin() -> void:
	var sol: Dictionary = {}
	for e: Dictionary in SWAPS.table():
		if str(e["hero"]) == "solenne":
			sol = e
	assert_int(int(sol["price"])).is_equal(4500)
	for pair: Array in _skins():
		var c: CharacterDef = pair[0]
		if c.id != "solenne":
			assert_bool(c.skin_price(str(pair[1])) < int(sol["price"])).override_failure_message("%s %s" % [c.id, pair[1]]).is_true()
	# once lane ART's look is in, it is the one sold, at that price, behind the renamed task
	if SWAPS.done(sol):
		var c := Registry.character("solenne")
		assert_int(c.skin_price(str(sol["new"]))).is_equal(int(sol["price"]))
		assert_bool(c.sells_skin(str(sol["old"]))).is_false()
		assert_str(Registry.skin_quest(c, str(sol["new"])).id).is_equal(str(sol["quest_new"]))


func test_the_swap_table_agrees_with_the_script_and_the_files() -> void:
	var on_disk := SWAPS.script_table()
	if not on_disk.is_empty():
		assert_int(on_disk.size()).is_equal(SWAPS.TABLE.size())
		for i in on_disk.size():
			var a: Dictionary = on_disk[i]
			var b: Dictionary = SWAPS.TABLE[i]
			assert_array(a.keys()).contains_exactly_in_any_order(b.keys())
			for k: Variant in b.keys():
				# JSON reads numbers as floats
				var av: Variant = a[k]
				var want := str(b[k])
				assert_str(str(int(av)) if av is float else str(av)).override_failure_message("%s %s" % [b["hero"], k]).is_equal(want)
	for e: Dictionary in SWAPS.table():
		var c := Registry.character(str(e["hero"]))
		var code := SWAPS.now(c.id, str(e["old"]))
		# the code standing now is a sold skin; the other one is not
		assert_bool(c.sells_skin(code)).override_failure_message(code).is_true()
		if code == str(e["new"]):
			assert_bool(c.sells_skin(str(e["old"]))).is_false()
			assert_bool(c.variant_shelved(str(e["old"]))).is_true()
		if str(e["via"]) == "trail":
			assert_bool(Trail.gated("skin", Registry.skin_key(c.id, code))).override_failure_message(code).is_true()
		else:
			var q := Registry.skin_quest(c, code)
			assert_object(q).is_not_null()
			assert_str(q.id).is_equal(str(e["quest_old"]) if code == str(e["old"]) else str(e["quest_new"]))
