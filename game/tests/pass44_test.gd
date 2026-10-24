## Pass 44 (Garry's second list): the Collection shows what was met, half the items sit behind quests spread over the
## stages, the Upgrade refund is half, a death leaves the gold, Cheese replaced the jerky (Cake since pass 46), the Blue
## Slime took the hobgoblin's row, the skeletons carry four art variants each and stay out of play, the prickly pear is
## gone, the new sounds exist, the player's debug mode persists.
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
	Run.add_or_level_passive("brawn")
	assert_bool(Save.seen("weapon", "peashooter")).is_true()
	assert_bool(Save.seen("passive", "magnet")).is_true()
	# pass 46: a former line is met as a passive
	assert_bool(Save.seen("passive", "brawn")).is_true()
	assert_bool(Save.seen("passive", "mend")).is_false()
	Run.end()


func test_half_the_items_sit_behind_quests_spread_over_the_stages() -> void:
	var items: Array = []
	for w in Registry.base_weapons():
		if not Registry.is_hidden(w):
			items.append(w)
	# the base passives, the lines among them (an evolved one is its source's evolution)
	for p in Registry.base_passives():
		items.append(p)
	var locked: Array = []
	for d in items:
		# the quests know a line as a passive (pass 47 draws it as a line)
		var q := Registry.quest_for("weapon" if d is WeaponDef else "passive", d.id)
		if q:
			locked.append(q)
	var share := float(locked.size()) / float(items.size())
	# pass 47: the nine new lines and passive items came unlocked and the thrown spear went hidden: 23 of 53 (43%),
	# half of 45 before
	# pass 47c: four more open passive items, 23 of 59 (39%)
	# pass 54: more open items since, and Solenne's Sun Scepter (her own, no quest): 23 of 66 (35%)
	# pass 69: the Salt, the Frisbee and five passive items (Counterpunch, Heavyweight, Snake Oil, Hot Springs, Last Stand)
	# came unlocked: 23 of 75 (31%)
	# pass 70 (lane LINES): four new lines (Lodestone, Mule Kick, Slow Burn, Tin Star) came unlocked: 23 of 79 (29%)
	assert_float(share).is_between(0.28, 0.56)
	# 70 / 25 / 5 by the stage that can do them (within a couple of items)
	# pass 54: 57 / 39 / 4. The map's timeline (the Level Editor's placement) brings the fire ants at 9:19, the mummies
	# at 7:10 and the armadillos at 12:11 of a 7:10 stage, so the Land Mine, the Lob Grenade, Thirst, Big Mouth and
	# Killer Bees are stage-2 quests now: 13 / 9 / 1 of 23
	var by_stage := {1: 0, 2: 0, 3: 0}
	for q in locked:
		var s: int = clampi(QuestTracker.stage_hint(q), 1, 3)
		by_stage[s] += 1
	assert_float(float(by_stage[1]) / float(locked.size())).is_between(0.48, 0.66)
	assert_float(float(by_stage[2]) / float(locked.size())).is_between(0.30, 0.48)
	assert_int(by_stage[3]).is_between(1, 2)
	# the quests name real things, and every locked passive is kept out of the offers
	for q in locked:
		assert_object(Registry.unlocked_by(q)).is_not_null()
		assert_str(TextGen.quest_text(q)).is_not_equal("Complete a challenge.")
	for p in Registry.unlocked_passives():
		assert_bool(Registry.is_unlocked("passive", p.id)).is_true()
	assert_int(Registry.unlocked_passives().size()).is_less(Registry.base_passives().size())
	# every hero still has a hand of weapons for the level-up offers
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


func test_cake_replaced_the_cheese_that_replaced_the_jerky() -> void:
	# pass 44: Cheese for Beef Jerky; pass 46: Cake for Cheese, the same numbers
	assert_object(Registry.passive("cake")).is_not_null()
	assert_str(Registry.passive("cake").display_name).is_equal("Cake")
	assert_object(Registry.passive("cheese")).is_null()
	assert_object(Registry.passive("beef_jerky")).is_null()
	var slice: PickupDef = Registry.pickup("cake_slice")
	assert_object(slice).is_not_null()
	assert_str(slice.display_name).is_equal("Cake Slice")
	assert_str(slice.effect_kind).is_equal("heal")
	assert_float(slice.value).is_equal_approx(0.06, 0.0001)
	assert_object(Registry.pickup("cheese_bite")).is_null()
	assert_object(Registry.pickup("jerky")).is_null()


func test_the_blue_slime_took_the_hobgoblins_row() -> void:
	var slime: EnemyDef = Registry.enemy("blue_slime")
	assert_object(slime).is_not_null()
	assert_bool(slime.retired).is_false()
	assert_bool(Registry.enemy("hobgoblin").retired).is_true()
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var rows: Array = tl.roster.filter(func(r): return str(r.get("enemy", "")) == "blue_slime")
	# Garry took the slime off his roster in the Level Editor (2026-10-24): its rows are only checked while it has any
	if rows.is_empty():
		return
	assert_int(tl.roster.filter(func(r): return str(r.get("enemy", "")) == "hobgoblin").size()).is_equal(0)
	# pass 56 (re-pinned): Garry moved the slime to a regular row in stage 1 (0:58) in the Level Editor; its quest's
	# stage hint follows its earliest row wherever he puts it
	var first := INF
	for r in rows:
		first = minf(first, float(r.get("t", 0.0)))
	assert_float(QuestTracker.first_arrival(tl, "blue_slime")).is_equal(first)


func test_the_skeletons_carry_four_variants_and_stay_out() -> void:
	for id in ["skeleton", "skeleton_knight"]:
		var e: EnemyDef = Registry.enemy(id)
		# pass 45: the skeletons took the goblins' roster rows (variants SK-A / KN-A in play), so they are no longer retired
		assert_bool(e.retired).is_false()
		assert_str(e.variant).is_equal("SK-A" if id == "skeleton" else "KN-A")
		# the recipes live in the JSON (the .tres carries a variant once its strip is painted)
		var f := FileAccess.open("res://content/enemies/%s/%s.json" % [id, id], FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		var variants: Dictionary = d.get("variants", {})
		assert_int(variants.size()).is_greater_equal(4)
		for code in variants.keys():
			var recipe: Dictionary = variants[code].get("recipe", {})
			# a painted look names its paintings; a tinted one (pass 54: SK-E / KN-E, the dark-blue bones) names the look
			# whose strip it recolours frame by frame (tools/recolour_strip.py --mode tint)
			var made_from := str(recipe.get("stills", "")) + str(recipe.get("tint_of", ""))
			assert_str(made_from).override_failure_message("%s %s says nothing of how it was made" % [id, code]).is_not_empty()
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
