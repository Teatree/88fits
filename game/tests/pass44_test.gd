## Pass 44 (Garry's second list): the Collection shows what was met, half the items sit behind quests spread over the
## stages, the Upgrade refund is half, a death leaves the gold, Cheese replaced the jerky, the Blue Slime took the
## hobgoblin's row, the skeletons carry four art variants each and stay out of play, the prickly pear is gone, the
## new sounds exist, the player's debug mode persists.
extends GdUnitTestSuite


func before_test() -> void:
	Save.data = Save._default()
	Save._migrate_seen()


func test_seen_is_recorded_once_per_kind() -> void:
	assert_bool(Save.seen("weapon", "peashooter")).is_false()
	Save.mark_seen("weapon", "peashooter")
	Save.mark_seen("weapon", "peashooter")
	assert_bool(Save.seen("weapon", "peashooter")).is_true()
	assert_int((Save.data["seen"]["weapon"] as Array).size()).is_equal(1)
	assert_bool(Save.seen("enemy", "peashooter")).is_false()


func test_an_old_save_keeps_what_its_totals_prove() -> void:
	Save.data = Save._default()
	Save.data.erase("seen")
	Save.data["once"] = []
	Save.add_keyed_total("kills_of_enemy", "goblin", 3)
	Save.add_keyed_total("kills_with_weapon", "boomstick", 1)
	Save.data["seen"] = {}
	Save._migrate_seen()
	assert_bool(Save.seen("enemy", "goblin")).is_true()
	assert_bool(Save.seen("weapon", "boomstick")).is_true()
	assert_bool(Save.seen("weapon", "peashooter")).is_false()


func test_a_run_marks_what_it_holds_and_meets() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	Run.add_or_level_passive("magnet")
	Run.add_or_rank_line("brawn")
	assert_bool(Save.seen("weapon", "peashooter")).is_true()
	assert_bool(Save.seen("passive", "magnet")).is_true()
	assert_bool(Save.seen("line", "brawn")).is_true()
	assert_bool(Save.seen("line", "mend")).is_false()
	Run.end()


func test_half_the_items_sit_behind_quests_spread_over_the_stages() -> void:
	var items: Array = []
	for w in Registry.base_weapons():
		if not Registry.is_hidden(w):
			items.append(w)
	for p in Registry.passives.values():
		if not (p is LineDef) and not Registry.is_hidden(p):
			items.append(p)
	for l in Registry.lines.values():
		if l.evolves_from == "" and not Registry.is_hidden(l):
			items.append(l)
	var locked: Array = []
	for d in items:
		var q := Registry.quest_for(W.kind_of(d), d.id)
		if q:
			locked.append(q)
	var share := float(locked.size()) / float(items.size())
	assert_float(share).is_between(0.45, 0.56)
	# 70 / 25 / 5 by the stage that can do them (within a couple of items)
	var by_stage := {1: 0, 2: 0, 3: 0}
	for q in locked:
		var s: int = clampi(QuestTracker.stage_hint(q), 1, 3)
		by_stage[s] += 1
	assert_float(float(by_stage[1]) / float(locked.size())).is_between(0.62, 0.78)
	assert_float(float(by_stage[2]) / float(locked.size())).is_between(0.18, 0.32)
	assert_int(by_stage[3]).is_between(1, 2)
	# the quests name real things, and every locked line is kept out of the offers
	for q in locked:
		assert_object(Registry.unlocked_by(q)).is_not_null()
		assert_str(TextGen.quest_text(q)).is_not_equal("Complete a challenge.")
	for l in CardPool.open_lines():
		assert_bool(Registry.is_unlocked("line", l.id)).is_true()
	assert_int(CardPool.open_lines().size()).is_less(Registry.sorted_lines().size())
	# the starter pick still has a hand of weapons for every hero
	for c in Registry.sorted_characters():
		Run.start(c, Registry.map("red_canyon"))
		assert_int(Registry.unlocked_weapons().size()).is_greater_equal(5)
		Run.end()


func test_the_new_quest_types_count_and_progress() -> void:
	var q := QuestDef.new()
	q.id = "t_kills"
	q.condition = {"type": "kills_total", "count": 3}
	assert_bool(QuestTracker._satisfied(q, false)).is_false()
	Save.add_total("kills", 3)
	assert_bool(QuestTracker._satisfied(q, false)).is_true()
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(3, 3))
	q.condition = {"type": "gold_total", "count": 10}
	Save.add_total("gold_earned", 4)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(4, 10))
	assert_str(TextGen.quest_text(q)).is_equal("Earn 10 gold, all time.")
	q.condition = {"type": "pickups_total", "count": 2}
	assert_str(TextGen.quest_text(q)).is_equal("Pick up 2 power-ups.")
	q.condition = {"type": "reach_stage", "stage": 3}
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.stage = 1
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	Run.stage = 2
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	assert_int(QuestTracker.stage_hint(q)).is_equal(3)
	Run.end()
	# the creature names read as names
	q.condition = {"type": "kills_of_enemy", "enemy": "dune_scorpion", "count": 1}
	assert_str(TextGen.quest_text(q)).is_equal("Kill the Dune Scorpion.")
	q.condition = {"type": "kills_of_enemy", "enemy": "spit_cactus", "count": 30}
	assert_str(TextGen.quest_text(q)).is_equal("Kill 30 Spit Cactuses.")
	assert_int(QuestTracker.stage_hint(q)).is_equal(1)


func test_gold_earned_is_counted_outside_the_arena() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_gold(40)
	assert_int(Save.total("gold_earned")).is_equal(40)
	Run.arena = true
	Run.add_gold(40)
	assert_int(Save.total("gold_earned")).is_equal(40)
	Run.arena = false
	Run.end()


func test_the_refund_is_half() -> void:
	Save.add_gold(1000)
	var grit: TalentDef = Registry.talents_list()[0]
	assert_bool(Save.buy_talent(grit)).is_true()
	var spent := Save.talent_spent()
	assert_int(spent).is_greater(0)
	assert_int(Save.talent_refund()).is_equal(int(floor(spent * 0.5)))
	var purse := Save.gold()
	var back := Save.talent_refund_all()
	assert_int(back).is_equal(int(floor(spent * 0.5)))
	assert_int(Save.gold()).is_equal(purse + back)


func test_cheese_replaced_the_jerky() -> void:
	assert_object(Registry.passive("cheese")).is_not_null()
	assert_object(Registry.passive("beef_jerky")).is_null()
	var bite: PickupDef = Registry.pickup("cheese_bite")
	assert_object(bite).is_not_null()
	assert_str(bite.effect_kind).is_equal("heal")
	assert_object(Registry.pickup("jerky")).is_null()


func test_the_blue_slime_took_the_hobgoblins_row() -> void:
	var slime: EnemyDef = Registry.enemy("blue_slime")
	assert_object(slime).is_not_null()
	assert_bool(slime.retired).is_false()
	assert_bool(Registry.enemy("hobgoblin").retired).is_true()
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var rows: Array = tl.roster.filter(func(r): return str(r.get("enemy", "")) == "blue_slime")
	assert_int(rows.size()).is_equal(1)
	assert_str(str(rows[0].get("channel", ""))).is_equal("hell")
	assert_int(tl.roster.filter(func(r): return str(r.get("enemy", "")) == "hobgoblin").size()).is_equal(0)
	assert_float(QuestTracker.first_arrival(tl, "blue_slime")).is_equal(300.0)


func test_the_skeletons_carry_four_variants_and_stay_out() -> void:
	for id in ["skeleton", "skeleton_knight"]:
		var e: EnemyDef = Registry.enemy(id)
		assert_bool(e.retired).is_true()
		# the recipes live in the JSON (the .tres carries a variant once its strip is painted)
		var f := FileAccess.open("res://content/enemies/%s/%s.json" % [id, id], FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		var variants: Dictionary = d.get("variants", {})
		assert_int(variants.size()).is_greater_equal(4)
		for code in variants.keys():
			var recipe: Dictionary = variants[code].get("recipe", {})
			assert_str(str(recipe.get("stills", ""))).is_not_empty()
			assert_bool(str(recipe.get("art_prompt", "")).find("stretched straight out") >= 0).is_false()


func test_the_prickly_pear_is_gone() -> void:
	var f := FileAccess.open("res://art/sprites/props/props.json", FileAccess.READ)
	var manifest = JSON.parse_string(f.get_as_text())
	f.close()
	assert_bool(manifest.has("prickly_pear")).is_false()
	assert_bool(ResourceLoader.exists("res://art/sprites/props/prickly_pear.png")).is_false()


func test_the_new_sounds_and_the_debug_switch() -> void:
	var table = Registry.soundmap.entries
	assert_bool(table is Dictionary).is_true()
	for id in ["en_slime_hit", "en_slime_die", "st_barrel_break", "ui_fanfare", "ui_jackpot", "wd_gust"]:
		assert_bool((table as Dictionary).has(id)).override_failure_message("missing sound " + id).is_true()
	Settings.from_dict({"debug_mode": true})
	assert_bool(Settings.debug_mode).is_true()
	assert_bool(bool(Settings.to_dict().get("debug_mode", false))).is_true()
	Settings.from_dict({"debug_mode": false})
	assert_bool(Settings.debug_mode).is_false()


func test_the_barrel_and_the_gun_models_exist() -> void:
	assert_bool(ResourceLoader.exists("res://art/props/barrel.glb")).is_true()
	assert_bool(ResourceLoader.exists("res://art/props/tommy_gun.glb")).is_true()
	var scene: Node = load("res://art/props/barrel.glb").instantiate()
	var names: Array = []
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		names.append(n.name)
	scene.free()
	assert_bool(names.any(func(n): return str(n).begins_with("Body"))).is_true()
	assert_bool(names.any(func(n): return str(n).begins_with("Hoops"))).is_true()
	var gun: Node = load("res://art/props/tommy_gun.glb").instantiate()
	assert_object(gun.find_child("Drum", true, false)).is_not_null()
	gun.free()
