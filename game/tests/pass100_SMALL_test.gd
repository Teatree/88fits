## Pass 100, lane SMALL (Garry's request of 2026-10-23):
##  1. Phoenix Feather "should still be a revive item with 50% HP on revive. It can only be used once and doesn't feature
##     any upgrades": a one-shot passive item (PassiveDef.single, `single` in the JSON): one level, off the rarity ladder
##     (no rungs, no Evolved rung, no Evolved icon), never offered again once held, one free revive at the hero's revive
##     health (50%, Second Wind's ranks add to it as to every revive), spent after it and marked so.
##  2. Stage 2's "intro cutscene is not in dark": the run's stage look (StageLook: the filter, hell) is on before the
##     spawn beam's landing, at once, and the director's stage_started after the landing switches nothing.
extends GdUnitTestSuite


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.arena = false
	Run.banished.clear()
	Run.end()


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _ph() -> PassiveDef:
	return Registry.passive("phoenix_feather")


# ---------------------------------------------------------------- 1. the one-shot item

func test_phoenix_is_one_level_off_the_ladder() -> void:
	var ph := _ph()
	assert_object(ph).is_not_null()
	assert_bool(ph.single).is_true()
	assert_bool(ph.is_item()).is_true()
	assert_bool(ph.on_ladder()).is_false()
	assert_int(ph.max_level).is_equal(1)
	assert_int(ph.ladder_top()).is_equal(1)
	assert_int(ph.levels.size()).is_equal(1)
	# no rungs: its rarity at every level, never Evolved, never the Evolved icon or the dark plate
	for lv in [0, 1, 2, 5]:
		assert_str(ph.rung_at(lv)).is_equal(ph.rarity)
		assert_bool(ph.is_evolved_rung(lv)).is_false()
		assert_bool(W.is_evolved_rung(ph, lv)).is_false()
		assert_object(ph.icon_at(lv)).is_same(ph.icon)
		assert_str(W.rung_of(ph, lv)).is_equal(ph.rarity)
	assert_bool(W.plate_fill(ph, 1).is_equal_approx(W.RARITY_PLATE[ph.rarity])).is_true()
	# a level an old run may hold past the one adds nothing (pass 115: its one level is the free revive and the feather's
	# own least revive health, phoenix_hp)
	assert_int(ph.effects_for_level(1).size()).is_equal(2)
	assert_int(ph.effects_for_level(5).size()).is_equal(2)
	assert_array(ph.effects_at_level(2)).is_empty()
	# apply_ladder keeps it at one level whatever the JSON says
	var d := PassiveDef.new()
	d.rarity = "common"
	d.single = true
	d.max_level = 6
	d.apply_ladder()
	assert_int(d.max_level).is_equal(1)
	# a card or an evolved card ignores `single` (it is for passive items)
	var line := PassiveDef.new()
	line.line = true
	line.single = true
	line.max_level = 4
	line.apply_ladder()
	assert_int(line.max_level).is_equal(4)
	assert_int(line.ladder_top()).is_equal(4)
	# every other passive item stays on the ladder
	for p: PassiveDef in Registry.sorted_passives_only():
		if p.id != "phoenix_feather":
			assert_bool(p.on_ladder()).override_failure_message(p.id).is_true()


func test_the_texts_promise_no_rungs() -> void:
	var ph := _ph()
	var lines: Array = [ph.text, TextGen.passive_description(ph, 1), TextGen.next_level_text(ph, 0), TextGen.next_level_text(ph, 1),
		WItem.word({"def": ph, "level_from": 0, "level_to": 1}), WItem.tag({"def": ph, "level_from": 0, "level_to": 1}),
		WItem.rung_word({"def": ph, "level_from": 0, "level_to": 1})]
	for s: String in lines:
		assert_bool(s.contains("Evolved")).override_failure_message("promises Evolved: " + s).is_false()
		assert_bool(s.to_lower().contains("rung")).override_failure_message("promises rungs: " + s).is_false()
		assert_bool(s.contains("_")).override_failure_message("a raw stat: " + s).is_false()
	assert_str(TextGen.passive_description(ph, 1)).is_equal("+1 free revive.")
	assert_str(TextGen.next_level_text(ph, 0)).is_equal("Next level: +1 free revive")
	assert_str(TextGen.next_level_text(ph, 1)).is_equal("Maxed.")
	assert_str(WItem.tag({"def": ph, "level_from": 0, "level_to": 1})).is_equal("NEW")
	assert_str(ph.text).contains("half health")
	assert_str(ph.text).contains("Once a run")
	# the Collection: no ladder line, no rung-washed cells
	var cs: CollectionScreen = auto_free(CollectionScreen.new())
	assert_str(cs._kind_line(ph)).is_equal("Passive · Uncommon · no upgrades")


func test_a_fifty_percent_revive_once() -> void:
	_start()
	var ph := _ph()
	assert_bool(Run.phoenix_ready()).is_false()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	assert_int(Run.passive_level("phoenix_feather")).is_equal(1)
	assert_int(Run.phoenix_count()).is_equal(1)
	assert_bool(Run.phoenix_ready()).is_true()
	# the feather adds no revive health: the hero's own is Nerve's 40% (pass 115) and the feather's revive takes its own
	# half (phoenix_hp, Player.revive_share) when that is more
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(0.4, 0.0001)
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Run.character)
	p.hp = p.max_hp
	p.take_damage(99999.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_bool(p.dead).is_true()
	# what Game._on_player_died does with it: spend it, stand him up
	assert_bool(Run.phoenix_ready()).is_true()
	Run.use_phoenix()
	p.revive(true)
	assert_float(p.hp).is_equal_approx(p.max_hp * 0.5, 0.001)
	# spent: no second one, held and marked spent (the pause screen's "(used)"), never offered again
	assert_bool(Run.phoenix_ready()).is_false()
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.item_spent(ph)).is_true()
	assert_bool(Run.held_passives().has("phoenix_feather")).is_true()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_false()
	Run.rebuild_sheets()
	assert_bool(Run.phoenix_ready()).is_false()
	# Second Wind's revive health reaches the feather's revive too (one rule for every revive): a fresh run, the
	# feather held, revive health on the sheet past the feather's half (pass 115: 40% + 25% = 65%)
	p.queue_free()
	_start()
	Run.add_or_level_passive("phoenix_feather")
	var q: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(q)
	q.setup(Run.character)
	Run.player_sheet.add_effects([Effect.make("revive_hp", "add", 0.25, "player")], "test")
	q.hp = q.max_hp
	q.take_damage(99999.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
	assert_bool(Run.phoenix_ready()).is_true()
	Run.use_phoenix()
	q.revive(true)
	assert_float(q.hp).is_equal_approx(q.max_hp * 0.65, 0.001)
	Run.player_sheet.remove_source("test")


func test_never_offered_again_once_held() -> void:
	_start()
	# not held: a card, a chest may hold it, new, at level 1
	var seen := false
	for k in range(200):
		for c: Dictionary in CardPool.level_up_offer(4):
			if str(c["id"]) == "phoenix_feather":
				seen = true
				assert_int(int(c["level_from"])).is_equal(0)
				assert_int(int(c["level_to"])).is_equal(1)
	assert_bool(seen).is_true()
	Run.add_or_level_passive("phoenix_feather")
	# held (spent or not): no card, no chest, no Stranger
	for spent in [false, true]:
		if spent:
			Run.use_phoenix()
		for k in range(200):
			for c: Dictionary in CardPool.level_up_offer(4):
				assert_str(str(c["id"])).is_not_equal("phoenix_feather")
		for c: Dictionary in Run.chest_candidates():
			assert_str(str(c["id"])).is_not_equal("phoenix_feather")
		for k in range(100):
			var o := Run.stranger_offer()
			if not o.is_empty():
				assert_str(str(o["id"])).is_not_equal("phoenix_feather")


func test_the_bot_still_values_one_revive() -> void:
	# game/tools/bot/BotCards.gd: a free revive is worth its survival points on the new card, the only one there is
	var bc: GDScript = load("res://tools/bot/BotCards.gd")
	assert_float(float(bc.SURVIVAL_PTS.get("phoenix_revive", 0.0))).is_greater(0.0)


# ---------------------------------------------------------------- 2. the stage look before the landing

## A real Game on a launch that plays the spawn beam at stage `s1` (1-based); returns it right after its _ready.
func _game_at(s1: int) -> Game:
	Run.launch_override = {"spawn": true, "stage": s1, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _expect_look(g: Game, s: int) -> void:
	var tl: WaveTimeline = Run.map.timeline
	var e := StageLook.entry_of(tl, s)
	var sl: StageLook = g.get_node_or_null(StageLook.NODE_NAME)
	assert_object(sl).override_failure_message("no StageLook at stage %d" % s).is_not_null()
	assert_int(sl.stage).is_equal(s)
	var m: Array = StageLook.filter_mults(e)
	assert_bool(sl.env_mult.is_equal_approx(m[0])).override_failure_message("stage %d world %s, wants %s" % [s, sl.env_mult, m[0]]).is_true()
	assert_bool(sl.actor_mult.is_equal_approx(m[1])).override_failure_message("stage %d actors %s" % [s, sl.actor_mult]).is_true()


func test_the_stage_look_is_on_before_the_landing() -> void:
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	var n := StageLook.stage_list_of(tl).size()
	assert_int(n).is_greater_equal(3)
	for s1 in range(1, n + 1):
		var s := s1 - 1
		var g := _game_at(s1)
		# the landing is playing, the director has not started the stage yet, and the look is on already
		assert_bool(g.spawning).is_true()
		assert_bool(g._run_started).is_false()
		assert_int(Run.stage).is_equal(s)
		_expect_look(g, s)
		await get_tree().process_frame
		await get_tree().process_frame
		var want_hell := 1.0 if StageLook.hell_of(tl, s) else 0.0
		assert_float(float(g.map.get("_hell"))).override_failure_message("stage %d hell at the landing" % s1).is_equal_approx(want_hell, 0.001)
		# the landing hurried, the run started (stage_started fired): nothing switched
		g.spawn_rate = Game.SPAWN_HURRY
		var frames := 0
		while not g._run_started and frames < 900:
			await get_tree().process_frame
			frames += 1
		assert_bool(g._run_started).override_failure_message("stage %d: the run never started" % s1).is_true()
		_expect_look(g, s)
		await get_tree().process_frame
		_expect_look(g, s)
		assert_float(float(g.map.get("_hell"))).is_equal_approx(want_hell, 0.001)
		g.set_paused(false)
		g.queue_free()
		await get_tree().process_frame
		Run.end()
	# the stages differ: Nightfall and Blood Moon are not daylight
	var m2: Array = StageLook.filter_mults(StageLook.entry_of(tl, 1))
	var m3: Array = StageLook.filter_mults(StageLook.entry_of(tl, 2))
	assert_bool((m2[0] as Color).is_equal_approx(Color.WHITE)).is_false()
	assert_bool((m3[0] as Color).is_equal_approx(Color.WHITE)).is_false()


func test_show_stage_leaves_the_stage_it_shows() -> void:
	var g := _game_at(2)
	var sl: StageLook = g.get_node(StageLook.NODE_NAME)
	_expect_look(g, 1)
	# the director's call (no seconds) on the stage shown: nothing moves, no fade starts
	sl.show_stage(1)
	assert_object(sl._tween).is_null()
	_expect_look(g, 1)
	# an explicit seconds (the arena's choice, a tool) still shows a stage, at once
	sl.show_stage(0, 0.0)
	assert_int(sl.stage).is_equal(0)
	assert_bool(sl.env_mult.is_equal_approx(StageLook.filter_mults(StageLook.entry_of(Run.map.timeline, 0))[0])).is_true()
	# a later stage by the director (the old flow) still fades in
	sl.show_stage(2)
	assert_object(sl._tween).is_not_null()
	# the warm-up under the beam finishes on a timer: let it, so nothing of it outlives the game
	await get_tree().create_timer(0.6).timeout
	g.queue_free()
	await get_tree().process_frame
