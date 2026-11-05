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
		for code: String in LOOKS[hid]:
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
	assert_int(total).is_equal(12)


func test_every_goal_is_an_item_feat_or_at_least_five_of_his_very_good_runs() -> void:
	for hid: String in LOOKS:
		var c := _hero(hid)
		for code: String in LOOKS[hid]:
			var m := "%s %s" % [hid, code]
			var q: QuestDef = Registry.skin_quest(c, code)
			assert_object(q).override_failure_message(m + ": no goal").is_not_null()
			assert_str(str(q.unlocks.get("id", ""))).is_equal(Registry.skin_key(hid, code))
			assert_bool(Registry.quest_visible(q)).override_failure_message(m).is_true()
			assert_str(TextGen.quest_text(q)).override_failure_message(m).is_not_equal("Complete a challenge.")
			assert_dict(QuestTracker.picture(q)).override_failure_message(m + ": no picture").is_not_empty()
			var cond: Dictionary = q.condition
			var n := float(cond.get("count", 0))
			match str(cond.get("type", "")):
				"item_level":
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
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(RUN_BARRELS * FIVE)
				"totems_total":
					assert_float(n).override_failure_message(m + ": under 5 runs").is_greater_equal(RUN_TOTEMS * FIVE)
				_:
					assert_str(str(cond.get("type", ""))).override_failure_message(m + ": a goal outside the brief").is_empty()
			# a career goal is across runs, never "in one run"
			assert_bool(bool(cond.get("in_one_run", false))).override_failure_message(m).is_false()


func test_the_goals_use_varied_tasks() -> void:
	var types := {}
	for hid: String in LOOKS:
		for code: String in LOOKS[hid]:
			types[str(Registry.skin_quest(_hero(hid), code).condition.get("type", ""))] = true
	assert_int(types.size()).is_greater_equal(6)


func test_a_career_goal_earned_opens_the_shop_and_buying_wears_it() -> void:
	var c := _hero("buck")
	var q: QuestDef = Registry.skin_quest(c, "BUC-G")
	Save.heroes_owned().append("buck")
	Save.data["gold"] = c.skin_price("BUC-G")
	assert_str(Registry.skin_state(c, "BUC-G")).is_equal("locked")
	assert_bool(Save.buy_skin(c, "BUC-G")).is_false()
	Save.data["totals"]["barrels"] = int(q.condition.get("count", 0))
	assert_array(QuestTracker.check_all(false)).contains([q.id])
	assert_str(Registry.skin_state(c, "BUC-G")).is_equal("buyable")
	assert_bool(Save.buy_skin(c, "BUC-G")).is_true()
	assert_int(Save.gold()).is_equal(0)
	# (the sheet and the Heroes screen wear what they sell: Save.set_skin_worn after the purchase)
	Save.set_skin_worn(c.id, "BUC-G")
	assert_str(Registry.played_look(c).look_code()).is_equal("BUC-G")


func test_a_goal_done_for_a_hero_not_owned_stays_done_and_says_nothing() -> void:
	var c := _hero("buck")
	var q: QuestDef = Registry.skin_quest(c, "BUC-G")
	Save.data["heroes_owned"] = []
	assert_str(Registry.hero_state(c)).is_not_equal("owned")
	Save.data["totals"]["barrels"] = int(q.condition.get("count", 0))
	QuestTracker.just_completed.clear()
	# no banner: it is not in what the check returns, nor on the Results' list
	assert_array(QuestTracker.check_all(true)).not_contains([q.id])
	assert_array(QuestTracker.just_completed).not_contains([q.id])
	assert_bool(Save.quest_done(q.id)).is_true()
	# bought later, the skin is on sale at once
	Save.heroes_owned().append("buck")
	assert_str(Registry.hero_state(c)).is_equal("owned")
	assert_str(Registry.skin_state(c, "BUC-G")).is_equal("buyable")
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
		assert_array(Registry.skins_of(c)).contains([str(pair[1])] + (LOOKS[c.id] as Array))
	# and every skin's goal is not done on a fresh save, so a fresh hero wears the look he always wore
	for hid: String in LOOKS:
		var c := _hero(hid)
		assert_str(Registry.worn_skin(c)).is_equal("")
		assert_str(Registry.played_look(c).look_code()).is_equal(c.home_look())
		for code: String in LOOKS[hid]:
			assert_str(Registry.skin_state(c, code)).is_equal("locked")


func test_the_production_build_keeps_every_skin() -> void:
	var reach = load("res://tools/prod_reach.gd")
	var plan: Dictionary = reach.plan(Registry)
	for hid: String in LOOKS:
		var look: Dictionary = (plan["looks"] as Dictionary).get("characters/" + hid, {})
		for code: String in LOOKS[hid]:
			assert_array(look.get("keep", [])).override_failure_message("%s %s" % [hid, code]).contains([code])
			assert_array(look.get("drop", [])).not_contains([code])
