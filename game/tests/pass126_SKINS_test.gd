## Pass 126, lane SKINS (Garry: "Make a skin for every hero that we have, based on the ones that are selected right now. For
## Drifter, Ironwood, Astra and Cavalero do 2 skins. Come up with Unlock requirements that are based on either Reaching a
## certain level with an item or doing some run activity that should take at least 5 very good runs ... Come up with prices
## as well."): twelve skins, each with its art, its goal and its price; every goal an item feat in one run or a career
## total of at least five times his very good run (BALANCING 68.SKINS); the look every player owns plays as before.
extends GdUnitTestSuite

## hero -> how many skins of this pass he sells
const COUNTS := {"drifter": 2, "astro": 2, "calavera": 2, "ironwood": 2, "solenne": 1, "fadeaway": 1, "buck": 1, "may": 1}
## this pass's looks by hero
const LOOKS := {"drifter": ["DRI-B", "DRI-C"], "astro": ["AST-B", "AST-C"], "calavera": ["CAL-B", "CAL-C"], "ironwood": ["IRN-B", "IRN-C"],
	"solenne": ["SOL-H"], "fadeaway": ["FAD-G"], "buck": ["BUC-G"], "may": ["MAY-S"]}
## The figures of Garry's very good run (Drifter, Stage 1, level 30, 13:06 into Endless; the Death card's after this pass's
## 25% cut; a weapon he did not play counts as one of the guns he did), each times five is the least a career goal asks.
const RUN_DAMAGE := {"revolver": 61929.0, "gravity_gun": 44530.0}
const RUN_DAMAGE_ANY := 60000.0
const RUN_KILLS_ONE_WEAPON := 600.0
const RUN_FIRE := 80449.0
const RUN_HEAL_DEATH := 1824.4 * 0.75
const RUN_BARRELS := 30.0
const RUN_TOTEMS := 8.0
const FIVE := 5.0
## Pass 140 (lane QUESTS; plan v2): the skins with no goal: on sale from the start (Dust Walker, Thunderbird, Mission
## Control) or given by a Trail node (Event Horizon). Pass 141 (lane TRAIL; Garry: "All Skins should be locked behind
## either a task or in the Trail"): only the Trail's (Event Horizon, Splashdown once lane ART's AST-D is in)
const NO_GOAL := ["astro:AST-B"]
## Pass 141: the two skins lane ART replaces (AST-B -> AST-D, SOL-H -> SOL-I); a code here stands for its new one once
## the switch is made (tools/dl/p141/TRAIL/retarget_skins.py)
const SWAPS := preload("res://tests/fixtures/skin_swaps.gd")


## This pass's looks of hero `hid` as they stand now (pass 141's switch followed).
## Pass 143 (Garry: "Don't create any looks for them yet"): Jeżyk became the Horseman and Fadeaway The Robot; their skins
## of the old characters are shelved, no longer sold.
const RETIRED := ["buck:BUC-G", "fadeaway:FAD-G"]


func _looks(hid: String) -> Array:
	return (LOOKS[hid] as Array).map(func(code: String) -> String: return SWAPS.now(hid, code)).filter(func(code: String) -> bool: return not RETIRED.has("%s:%s" % [hid, code]))


func _no_goal(hid: String, code: String) -> bool:
	return NO_GOAL.map(func(k: String) -> String: return Registry.skin_key(k.get_slice(":", 0), SWAPS.now(k.get_slice(":", 0), k.get_slice(":", 1)))).has(Registry.skin_key(hid, code))


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func _hero(id: String) -> CharacterDef:
	var c: CharacterDef = Registry.character(id)
	assert_object(c).override_failure_message("no hero " + id).is_not_null()
	return c


func test_twelve_skins_each_with_its_art_goal_and_price() -> void:
	var total := 0
	for hid: String in LOOKS:
		var c := _hero(hid)
		assert_int((LOOKS[hid] as Array).size()).is_equal(int(COUNTS[hid]))
		for code: String in _looks(hid):
			total += 1
			var m := "%s %s" % [hid, code]
			assert_bool(c.variants.has(code)).override_failure_message(m + ": not painted").is_true()
			assert_bool(c.sells_skin(code)).override_failure_message(m + ": not sold").is_true()
			assert_bool(c.variant_shelved(code)).override_failure_message(m + ": shelved").is_false()
			assert_str(str(c.skin_of(code).get("name", ""))).override_failure_message(m + ": no name").is_not_empty()
			assert_int(c.skin_price(code)).override_failure_message(m + ": price").is_greater_equal(1000)
			assert_str(c.skin_currency(code)).is_equal("gold")
			# the art: a strip of its own, whole; a badge and a sheet still of its own; a title cut-out of its own
			var strip := c.look_strip_path(code)
			assert_str(strip).override_failure_message(m + ": strip").is_not_equal(c.strip_path())
			assert_bool(ResourceLoader.exists(strip)).override_failure_message(m + ": strip file").is_true()
			var e: Dictionary = c.variants[code]
			var frames := 0
			for k in (e["anims"] as Dictionary).keys():
				frames += int(e["anims"][k])
			assert_int(frames).override_failure_message(m + ": frames").is_equal(166)
			assert_int(int(e["strip_cols"])).override_failure_message(m + ": cols").is_equal(62)
			assert_str(str(e["icon"])).override_failure_message(m + ": icon").is_not_equal(str(c.variants[c.home_look()]["icon"]))
			assert_bool(ResourceLoader.exists(str(e["icon"]))).override_failure_message(m + ": icon file").is_true()
			assert_str(c.look_still_path(code)).override_failure_message(m + ": still").is_not_empty()
			var worn := c.variant_def(code)
			assert_str(worn.look_title()).override_failure_message(m + ": title").is_not_empty()
			assert_bool(ResourceLoader.exists(worn.title_path())).override_failure_message(m + ": title file").is_true()
	# pass 143: twelve less the two retired with their outlaws (RETIRED)
	assert_int(total).is_equal(10)


func test_every_goal_is_an_item_feat_or_at_least_five_of_his_very_good_runs() -> void:
	for hid: String in LOOKS:
		var c := _hero(hid)
		for code: String in _looks(hid):
			var m := "%s %s" % [hid, code]
			var q: QuestDef = Registry.skin_quest(c, code)
			# pass 140 (lane QUESTS, re-pinned): four skins have no goal now (pass 141: one, the Trail's)
			if _no_goal(hid, code):
				assert_object(q).override_failure_message(m + ": a goal").is_null()
				continue
			assert_object(q).override_failure_message(m + ": no goal").is_not_null()
			assert_str(str(q.unlocks.get("id", ""))).is_equal(Registry.skin_key(hid, code))
			assert_bool(Registry.quest_visible(q)).override_failure_message(m).is_true()
			assert_str(TextGen.quest_text(q)).override_failure_message(m).is_not_equal("Complete a challenge.")
			assert_dict(QuestTracker.picture(q)).override_failure_message(m + ": no picture").is_not_empty()
			var cond: Dictionary = q.condition
			var n := float(cond.get("count", 0))
			match str(cond.get("type", "")):
				"item_level":
					# pass 140 (lane QUESTS): Winter Pelt is a passive item's rung (Cold Snap to Epic as Ironwood)
					if str(cond.get("rung", "")) != "":
						assert_object(Registry.passive(str(cond.get("id", "")))).override_failure_message(m).is_not_null()
						assert_int(QuestTracker.rung_rank(str(cond.get("rung", "")))).override_failure_message(m).is_greater(0)
						continue
					var w: WeaponDef = Registry.weapon(str(cond.get("id", "")))
					assert_object(w).override_failure_message(m).is_not_null()
					assert_int(int(cond.get("level", 0))).override_failure_message(m + ": a level above his run's 4").is_greater(4)
					assert_int(int(cond.get("level", 0))).override_failure_message(m + ": past the top").is_less_equal(w.max_level)
				"evolve_item":
					var w2: WeaponDef = Registry.weapon(str(cond.get("id", "")))
					assert_object(w2).override_failure_message(m).is_not_null()
					assert_bool(Registry.weapons.values().any(func(x: WeaponDef): return x.evolved_from == w2.id)).override_failure_message(m + ": no evolution").is_true()
				"damage_with_weapon":
					assert_object(Registry.weapon(str(cond.get("weapon", "")))).override_failure_message(m).is_not_null()
					var r: float = float(RUN_DAMAGE.get(str(cond.get("weapon", "")), RUN_DAMAGE_ANY))
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(r * FIVE)
				"kills_with_weapon":
					assert_object(Registry.weapon(str(cond.get("weapon", "")))).override_failure_message(m).is_not_null()
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(RUN_KILLS_ONE_WEAPON * FIVE)
				"element_damage":
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(RUN_FIRE * FIVE)
				"heal_with_item":
					assert_object(Registry.passive(str(cond.get("item", "")))).override_failure_message(m).is_not_null()
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(RUN_HEAL_DEATH * FIVE)
				"barrels_total":
					# pass 140 (lane QUESTS): Czerwony is 30 barrels in one run as Jezyk (plan v2)
					if bool(cond.get("in_one_run", false)):
						assert_float(n).override_failure_message(m).is_greater_equal(RUN_BARRELS)
						assert_str(str(cond.get("hero", ""))).is_equal(hid)
						continue
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(RUN_BARRELS * FIVE)
				"totems_total":
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(RUN_TOTEMS * FIVE)
				_:
					assert_str(str(cond.get("type", ""))).override_failure_message(m + ": a goal outside the brief").is_empty()
			# a career goal is across runs, never "in one run" (pass 140: but one played as its own outlaw)
			if str(cond.get("hero", "")) != hid:
				assert_bool(bool(cond.get("in_one_run", false))).override_failure_message(m).is_false()


func test_the_goals_use_varied_tasks() -> void:
	var types := {}
	for hid: String in LOOKS:
		for code: String in _looks(hid):
			var q: QuestDef = Registry.skin_quest(_hero(hid), code)
			if q:
				types[str(q.condition.get("type", ""))] = true
	# pass 143: five (Czerwony's barrels and Purple Reign's level went with their outlaws' old skins)
	assert_int(types.size()).is_greater_equal(5)


func test_a_career_goal_earned_opens_the_shop_and_buying_wears_it() -> void:
	# pass 140 (lane QUESTS, re-pinned): Czerwony is done in one run now; the Drifter's Black Hat is the career goal
	var c := _hero("drifter")
	var q: QuestDef = Registry.skin_quest(c, "DRI-B")
	Save.data["gold"] = c.skin_price("DRI-B")
	assert_str(Registry.skin_state(c, "DRI-B")).is_equal("locked")
	assert_bool(Save.buy_skin(c, "DRI-B")).is_false()
	# pass 141 (lane TRAIL): Black Hat waits for Dust Walker's feat (the Revolver to level 5 in a run)
	for r: Variant in q.requires:
		Save.mark_quest(str(r))
	Save.add_keyed_total(TaskTally.SAVE_DAMAGE, "revolver", int(q.condition.get("count", 0)))
	assert_array(QuestTracker.check_all(false)).contains([q.id])
	assert_str(Registry.skin_state(c, "DRI-B")).is_equal("buyable")
	assert_bool(Save.buy_skin(c, "DRI-B")).is_true()
	assert_int(Save.gold()).is_equal(0)
	# (the sheet and the Heroes screen wear what they sell: Save.set_skin_worn after the purchase)
	Save.set_skin_worn(c.id, "DRI-B")
	assert_str(Registry.played_look(c).look_code()).is_equal("DRI-B")


func test_a_goal_done_for_a_hero_not_owned_stays_done_and_says_nothing() -> void:
	var c := _hero("buck")
	# pass 143: Czerwony (BUC-G) is gone with Jeżyk; its goal stands in as a fixture task (30 barrels in one run as him)
	var q := QuestDef.new()
	q.id = "fixture_skin_buck_barrels"
	q.condition = {"type": "barrels_total", "count": 30, "in_one_run": true, "hero": "buck"}
	q.unlocks = {"type": "skin", "id": "buck:BUC-G"}
	Registry.quests[q.id] = q
	# ... and the look on sale again for the test's time (a skin's goal is tracked while its look is sold)
	var was: Dictionary = (c.variants["BUC-G"] as Dictionary).duplicate(true)
	c.variants["BUC-G"]["skin"] = {"purchasable": true, "name": "Czerwony", "price": 2500, "currency_type": "gold", "unlock_quest": q.id}
	c.variants["BUC-G"].erase("shelved")
	Save.data["heroes_owned"] = []
	assert_str(Registry.hero_state(c)).is_not_equal("owned")
	# pass 140 (lane QUESTS, re-pinned): 30 barrels in one run as Jezyk (a run of an outlaw not owned: a tool's)
	TaskTally.bank_in_tools = true
	Run.arena = false
	Run.start(c, Registry.map("red_canyon"))
	Run.barrels_broken = int(q.condition.get("count", 0))
	QuestTracker.just_completed.clear()
	# no banner: it is not in what the check returns, nor on the Results' list
	assert_array(QuestTracker.check_all(true)).not_contains([q.id])
	assert_array(QuestTracker.just_completed).not_contains([q.id])
	assert_bool(Save.quest_done(q.id)).is_true()
	Run.end()
	TaskTally.bank_in_tools = false
	# bought later, the skin is on sale at once
	Save.heroes_owned().append("buck")
	assert_str(Registry.hero_state(c)).is_equal("owned")
	assert_str(Registry.skin_state(c, "BUC-G")).is_equal("buyable")
	Registry.quests.erase(q.id)
	c.variants["BUC-G"] = was
	QuestTracker.just_completed.clear()


func test_the_look_every_player_owns_still_plays() -> void:
	# the four heroes who had one art wear it under its new code, from the same files
	for pair: Array in [["drifter", "DRI-A"], ["astro", "AST-A"], ["calavera", "CAL-A"], ["ironwood", "IRN-A"]]:
		var c := _hero(str(pair[0]))
		assert_str(c.variant).is_equal(str(pair[1]))
		assert_str(c.home_look()).is_equal(str(pair[1]))
		assert_str(c.strip_path()).is_equal("res://content/characters/%s/%s_sprite.png" % [c.id, c.id])
		assert_str(c.title_path()).is_equal("res://art/ui/wanted/hero_%s.png" % c.id)
		assert_str(Registry.played_look(c).look_code()).is_equal(str(pair[1]))
		assert_str(Registry.skin_state(c, str(pair[1]))).is_equal("owned")
		assert_array(Registry.skins_of(c)).contains([str(pair[1])] + _looks(c.id))
	# and every skin's goal is not done on a fresh save, so a fresh hero wears the look he always wore
	for hid: String in LOOKS:
		var c := _hero(hid)
		assert_str(Registry.worn_skin(c)).is_equal("")
		assert_str(Registry.played_look(c).look_code()).is_equal(c.home_look())
		for code: String in _looks(hid):
			# pass 140 (lane QUESTS, re-pinned): a skin with no goal and no Trail node is on sale to his owner at once
			# (pass 141: none; the one with no goal is the Trail's)
			var key := Registry.skin_key(hid, code)
			var on_sale := _no_goal(hid, code) and not Trail.gated("skin", key) and Registry.hero_state(c) == "owned"
			assert_str(Registry.skin_state(c, code)).override_failure_message(key).is_equal("buyable" if on_sale else "locked")


func test_the_production_build_keeps_every_skin() -> void:
	var reach = load("res://tools/prod_reach.gd")
	var plan: Dictionary = reach.plan(Registry)
	for hid: String in LOOKS:
		var look: Dictionary = (plan["looks"] as Dictionary).get("characters/" + hid, {})
		for code: String in _looks(hid):
			assert_array(look.get("keep", [])).override_failure_message("%s %s" % [hid, code]).contains([code])
			assert_array(look.get("drop", [])).not_contains([code])
