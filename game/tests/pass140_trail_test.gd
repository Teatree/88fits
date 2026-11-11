## Pass 140, lane TRAIL: the Trail of the progression plan v2 with Garry's changes (docs/progression/progression_plan.html;
## Garry 2026-11-10: "Remove Power-ups from the Trails, but keep Stage", "keep 3 Unlocked: Drifter, Ironwood and Astro",
## "make sure not to damage our mix of choice/optional and regular nodes"), read from the game's own file
## (content/trail/trail.json, written by tools/trail_setup.py). BALANCING.md 81.TRAIL. Pass 141 (lane TRAIL, one lane:
## pass141_trail_test.gd) re-pinned the levels and the price to the file.
extends GdUnitTestSuite

const SWAPS := preload("res://tests/fixtures/skin_swaps.gd")
const UNLOCK_MULT := 0.5
const OUTLAW_MULT := 2.0

var _nodes: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()
	_nodes = Trail.nodes()


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()


func _type(n: Dictionary) -> String:
	return str((n["gives"] as Dictionary).get("type", ""))


func _gift_id(n: Dictionary) -> String:
	var g: Dictionary = n["gives"]
	if str(g.get("type", "")) == "stage":
		return "%s:%s" % [str(g.get("map", "")), str(g.get("stage", ""))]
	return str(g.get("id", ""))


func test_no_power_up_structure_feature_or_map_on_the_trail_and_every_power_up_open() -> void:
	for n: Dictionary in _nodes:
		assert_bool(["powerup", "structure", "feature", "map"].has(_type(n))).override_failure_message("%s gives a %s" % [str(n["id"]), _type(n)]).is_false()
	for id: String in ["rage", "nuke"]:
		assert_bool(Trail.gated("powerup", id)).override_failure_message(id).is_false()
		assert_bool(Trail.has("powerup", id)).override_failure_message(id).is_true()
	assert_bool(Trail.gated("feature", "wanted")).is_false()


func test_the_dust_bowl_and_blood_moon_each_on_its_own_level() -> void:
	# pass 140: 18 and 34; pass 141 (one lane): 26 and 46, about the same run
	var dust := Trail.level_for("stage", "red_canyon:dust")
	var moon := Trail.level_for("stage", "red_canyon:s3")
	assert_bool(dust > 0 and dust < moon).override_failure_message("%d, %d" % [dust, moon]).is_true()
	for l: int in [dust, moon]:
		assert_int(Trail.nodes_on(l).filter(func(n: Dictionary) -> bool: return str(n["kind"]) != "optional").size()).is_equal(1)
	var stages := _nodes.filter(func(n: Dictionary) -> bool: return _type(n) == "stage")
	assert_int(stages.size()).is_equal(2)
	for n: Dictionary in stages:
		# a stage is a gate, not an item: its level's price
		assert_float(float(n.get("price_mult", 1.0))).is_equal_approx(1.0, 0.0001)
		assert_bool(n.has("price")).is_false()


func test_drifter_ironwood_and_astro_start_open_may_is_no_node() -> void:
	for id: String in ["drifter", "ironwood", "astro", "may"]:
		assert_bool(Trail.gated("outlaw", id)).override_failure_message(id).is_false()
	for id: String in ["drifter", "ironwood", "astro"]:
		var c: CharacterDef = Registry.character(id)
		assert_str(Registry.hero_state(c)).override_failure_message(id).is_equal("owned")
		assert_bool(Registry.hero_owned(c)).override_failure_message(id).is_true()
	assert_str(Registry.character("astro").availability).is_equal("available")
	# Astro's own weapon is in the draw on a fresh save (an outlaw's starting weapon needs him owned, pass 128)
	assert_object(Registry.weapon_comes_with(Registry.start_weapon_for(Registry.character("astro")))).is_null()


func test_four_outlaws_on_the_trail_at_twice_their_levels_price() -> void:
	var cfg: Dictionary = Trail.read_file(Trail.DEFAULT)["price"]
	var got: Array = []
	for n: Dictionary in _nodes:
		if _type(n) != "outlaw":
			continue
		got.append(_gift_id(n))
		assert_bool(n.has("price")).override_failure_message(_gift_id(n)).is_false()
		assert_float(float(n.get("price_mult", 1.0))).override_failure_message(_gift_id(n)).is_equal_approx(OUTLAW_MULT, 0.0001)
		assert_int(Trail.price(str(n["id"]))).is_equal(Trail.price_at(cfg, int(n["level"]), OUTLAW_MULT))
		assert_str(Registry.hero_state(Registry.character(_gift_id(n)))).override_failure_message(_gift_id(n)).is_equal("locked")
	assert_array(got).is_equal(["calavera", "solenne", "fadeaway", "buck"])


func test_item_card_and_skin_nodes_cost_half_their_levels_price() -> void:
	var cfg: Dictionary = Trail.read_file(Trail.DEFAULT)["price"]
	var count := 0
	for n: Dictionary in _nodes:
		if not ["weapon", "passive", "skin"].has(_type(n)):
			continue
		count += 1
		assert_bool(n.has("price")).override_failure_message(_gift_id(n)).is_false()
		assert_float(float(n.get("price_mult", 1.0))).override_failure_message(_gift_id(n)).is_equal_approx(UNLOCK_MULT, 0.0001)
		assert_int(Trail.price(str(n["id"]))).is_equal(Trail.price_at(cfg, int(n["level"]), UNLOCK_MULT))
	# 29 items, Cards and weapons and Astro's second skin (Event Horizon; pass 141: Splashdown once lane ART installs it)
	assert_int(count).is_equal(30)
	var skin := Registry.skin_key("astro", SWAPS.now("astro", "AST-B"))
	assert_bool(Trail.gated("skin", skin)).override_failure_message(skin).is_true()
	assert_int(Trail.nodes_on(Trail.level_for("skin", skin)).filter(func(n: Dictionary) -> bool: return str(n["kind"]) != "optional").size()).is_equal(1)


func test_the_price_block_is_the_plans_fit() -> void:
	# pass 140: the progression plan's fit (Garry may edit it in the Level Editor's Trail tab: re-pin to his numbers then);
	# pass 141: the one-lane Trail's fit on lane ECON's measured purses (k 6.21 -> 1.16, power 1.9 -> 2.25)
	var cfg: Dictionary = Trail.read_file(Trail.DEFAULT)["price"]
	assert_float(float(cfg["base"])).is_equal_approx(20.0, 0.0001)
	assert_float(float(cfg["k"])).is_equal_approx(1.16, 0.0001)
	assert_float(float(cfg["power"])).is_equal_approx(2.25, 0.0001)
	assert_float(float(cfg["round"])).is_equal_approx(10.0, 0.0001)
	# the first node keeps its own price (Garry's Might +5% for 10)
	assert_int(Trail.price(str(_nodes[0]["id"]))).is_equal(10)


func test_the_mix_of_choice_optional_and_rails_meeting_nodes_is_pass_129s() -> void:
	var groups := {}
	var choice := 0
	var optional := 0
	var meet := 0
	for n: Dictionary in _nodes:
		match str(n["kind"]):
			"choice":
				choice += 1
				groups["%d:%s" % [int(n["level"]), str(n.get("group", ""))]] = true
			"optional":
				optional += 1
		if (n.get("from", []) as Array).size() >= 2:
			meet += 1
	assert_int(groups.size()).is_equal(12)
	assert_int(choice).is_equal(28)
	assert_int(optional).is_equal(10)
	assert_int(meet).is_equal(3)
	# the rails meet from the level right below: Extra Barrel (52), Pass the Bottle (59), Boot Hill Pass (64); pass 141 (one
	# lane): from every member of the choice group right below them (62, 69, 72)
	for n: Dictionary in _nodes:
		var from: Array = n.get("from", [])
		if from.size() >= 2:
			for id: Variant in from:
				assert_int(int(Trail.node(str(id))["level"])).override_failure_message(str(n["id"])).is_equal(int(n["level"]) - 1)
	assert_array(Trail.check(Trail.read_file(Trail.DEFAULT))).is_empty()


func test_no_trail_gift_is_also_a_tasks_unlock() -> void:
	for n: Dictionary in _nodes:
		var t := _type(n)
		if t == "upgrade" or t == "stage":
			continue
		var qt := "character" if t == "outlaw" else t
		assert_object(Registry.quest_for(qt, _gift_id(n))).override_failure_message("%s %s has a quest too" % [t, _gift_id(n)]).is_null()
		assert_bool(Registry.is_unlocked(t, _gift_id(n)) if t != "outlaw" else Registry.hero_owned(Registry.character(_gift_id(n)))).override_failure_message(_gift_id(n)).is_false()


## The split of every locked thing between the Trail and the tasks (lanes TRAIL and QUESTS, pass 140): tools/dl/ is
## git-ignored, so the test reads it only where it exists.
func test_split_json_agrees_with_the_trail() -> void:
	var path := ProjectSettings.globalize_path("res://").path_join("../tools/dl/p140/split.json").simplify_path()
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(data is Dictionary).is_true()
	var tasks := {}
	var trail := 0
	for e: Dictionary in (data as Dictionary).get("locked", []):
		var kind := str(e.get("kind", ""))
		var id := str(e.get("id", ""))
		var key := kind + ":" + id
		if str(e.get("by", "")) == "trail":
			trail += 1
			var want_id := ("red_canyon:" + id) if kind == "stage" else id
			if kind == "skin":
				# pass 141: Astro's Trail skin is Splashdown once lane ART's look is in (tests/fixtures/skin_swaps.gd)
				want_id = Registry.skin_key(id.get_slice(":", 0), SWAPS.now(id.get_slice(":", 0), id.get_slice(":", 1)))
			assert_bool(Trail.gated(kind, want_id)).override_failure_message("%s is no Trail node" % key).is_true()
			# (pass 141: the levels moved with the one-lane Trail; the split itself holds)
		else:
			tasks[key] = true
	var gifts := 0
	for n: Dictionary in _nodes:
		var t := _type(n)
		if t == "upgrade":
			continue
		gifts += 1
		var id := _gift_id(n).trim_prefix("red_canyon:") if t == "stage" else _gift_id(n)
		assert_bool(tasks.has(t + ":" + id)).override_failure_message("%s:%s is a task's unlock too" % [t, id]).is_false()
	assert_int(trail).is_equal(gifts)
