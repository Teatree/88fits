extends GdUnitTestSuite

## Pass 79, lane MUT (Garry: "Mutations are supposed to be level ups, not just random occurrences"; his pick: the offers
## stay, one per weapon per stage, but come as the level-up screen itself in place of the three cards; "decrease the
## level requirements to achieve the same power level considering the changes"):
## M1 an offer falls due on the stage's path_times (spent with nothing when no pick is open), M2 it waits for the hero's
## next level-up, which shows it in place of the three cards (due offers queue, one a level-up), M3 a level-up whose offer
## finds no weapon open is an ordinary one, M4 the HUD's mark, M5 the card levels for what grows with the level
## (mutation_levels_scale); the XP curve's pace (xp_need_mult).

const DIR := "user://test_saves/p79_mut"


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	get_tree().paused = false
	Run.forced_map_seed = 0
	Run.arena = false
	Run.end()


func _due_now() -> bool:
	var times: Array = Run.map.timeline.path_times_at(Run.stage)
	return Run.mutlvl_tick(float(times[Run.path_slot]) + 0.1)


func _level_up() -> void:
	Run.add_xp(Run.xp_to_next() - Run.xp + 0.01)


# ---------------------------------------------------------------- Run: M1-M3, M5

func test_a_due_offer_waits_for_the_next_level_up() -> void:
	Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	var times: Array = Run.map.timeline.path_times_at(0)
	assert_bool(Run.mutlvl_tick(float(times[0]) - 1.0)).is_false()
	assert_int(Run.mutlvl_due).is_equal(0)
	assert_bool(Run.mutlvl_tick(float(times[0]) + 0.1)).is_true()
	assert_bool(Run.mutlvl_tick(float(times[0]) + 0.2)).override_failure_message("a slot fell due twice").is_false()
	# due, not shown: the mark says the next level-up is a mutation
	assert_int(Run.mutlvl_due).is_equal(1)
	assert_bool(Run.mutlvl_pending()).is_true()
	assert_int(Run.mutation_levels).is_equal(0)
	_level_up()
	assert_int(Run.level).is_equal(2)
	assert_int(Run.mutlvl_due).is_equal(0)
	assert_int(Run.mutlvl_ready).is_equal(1)
	assert_int(Run.mutation_levels).is_equal(1)
	assert_bool(Run.mutlvl_pending()).is_false()
	# the screen draws the weapon among those open then
	var w := Run.mutlvl_take()
	assert_object(w).is_not_null()
	assert_str(w.def.id).is_equal("orbit_saws")
	assert_int(Run.mutlvl_ready).is_equal(0)
	assert_bool(CardPool.path_offer(w).is_empty()).is_false()
	# the next level-up is an ordinary one
	_level_up()
	assert_int(Run.mutlvl_ready).is_equal(0)
	assert_object(Run.mutlvl_take()).is_null()
	assert_int(Run.mutation_levels).is_equal(1)


func test_due_offers_queue_one_a_level_up() -> void:
	Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	Run.add_weapon(Registry.weapon("hornet_nest"), 1)
	assert_bool(_due_now()).is_true()
	assert_bool(_due_now()).is_true()
	assert_int(Run.mutlvl_due).is_equal(2)
	# one credit of three levels: two mutation level-ups and one ordinary
	Run.add_xp(Run.xp_to_next(1) + Run.xp_to_next(2) + Run.xp_to_next(3) + 0.01)
	assert_int(Run.level).is_equal(4)
	assert_int(Run.mutlvl_due).is_equal(0)
	assert_int(Run.mutlvl_ready).is_equal(2)
	assert_int(Run.mutation_levels).is_equal(2)
	assert_int(Run.card_level()).is_equal(2)
	var a := Run.mutlvl_take()
	assert_bool(Run.add_mutation(str(CardPool.path_offer(a)[0]["id"]))).is_true()
	var b := Run.mutlvl_take()
	assert_object(b).is_not_null()
	assert_str(b.family_id()).is_not_equal(a.family_id())
	assert_object(Run.mutlvl_take()).is_null()


func test_an_offer_with_no_pick_open_is_spent_or_dropped() -> void:
	var w := Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	# the stage's pick already taken: the slot is spent with nothing (M1), as before
	Run.mutation_stage[w.family_id()] = Run.stage
	assert_bool(_due_now()).is_false()
	assert_int(Run.mutlvl_due).is_equal(0)
	assert_bool(Run.mutlvl_pending()).is_false()
	# due while open, the pick spent before the level-up (a chest's mutation): an ordinary level-up (M3)
	Run.mutation_stage.erase(w.family_id())
	assert_bool(_due_now()).is_true()
	Run.mutation_stage[w.family_id()] = Run.stage
	assert_bool(Run.mutlvl_pending()).override_failure_message("no weapon open: no mark").is_false()
	_level_up()
	assert_int(Run.mutlvl_due).is_equal(0)
	assert_int(Run.mutlvl_ready).is_equal(0)
	assert_int(Run.mutation_levels).is_equal(0)
	assert_int(Run.card_level()).is_equal(Run.level)


func test_a_claimed_level_whose_pick_went_meanwhile_opens_as_cards() -> void:
	var w := Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	assert_bool(_due_now()).is_true()
	_level_up()
	assert_int(Run.mutation_levels).is_equal(1)
	# banked behind a chest that took the weapon's pick
	Run.mutation_stage[w.family_id()] = Run.stage
	assert_object(Run.mutlvl_take()).is_null()
	assert_int(Run.mutation_levels).is_equal(0)
	assert_int(Run.mutlvl_ready).is_equal(0)


func test_due_offers_stay_due_across_a_stage() -> void:
	Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	assert_bool(_due_now()).is_true()
	Run.stage = 1
	Run.path_slot = 0
	assert_int(Run.mutlvl_due).is_equal(1)
	assert_bool(Run.mutlvl_pending()).is_true()
	_level_up()
	assert_int(Run.mutlvl_ready).is_equal(1)


func test_the_arena_never_has_an_offer_due() -> void:
	Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	Run.arena = true
	assert_bool(_due_now()).is_false()
	assert_int(Run.mutlvl_due).is_equal(0)


func test_what_grows_with_the_level_reads_the_card_levels() -> void:
	Run.add_weapon(Registry.weapon("orbit_saws"), 2)
	assert_bool(_due_now()).is_true()
	_level_up()
	_level_up()
	assert_int(Run.level).is_equal(3)
	assert_int(Run.mutation_levels).is_equal(1)
	assert_int(Run.card_level()).is_equal(2)
	# the creatures' level factor (WaveDirector.fixed_numbers) and the hero's trait (Astro: max HP a level) at 2, not 3
	var wd: WaveDirector = auto_free(WaveDirector.new())
	wd.timeline = Run.map.timeline
	var fx := wd.fixed_numbers(0.0)
	assert_float(float(fx["lv_hp"])).is_equal_approx(1.0 + Run.map.timeline.level_hp_per_level * 1.0, 0.0001)
	assert_float(float(fx["lv_dmg"])).is_equal_approx(1.0 + Run.map.timeline.level_damage_per_level * 1.0, 0.0001)
	var want := Run.hero_sheet(Run.character, 2).get_stat("max_hp", 0.0)
	assert_float(Run.player_sheet.get_stat("max_hp", 0.0)).is_equal_approx(want, 0.0001)
	# the map's switch counts them
	Run.map.timeline.mutation_levels_scale = true
	assert_int(Run.card_level()).is_equal(3)
	Run.map.timeline.mutation_levels_scale = false


# ---------------------------------------------------------------- the XP curve

func test_the_xp_curve_reads_the_map_and_the_switch_defaults_off() -> void:
	assert_bool(JsonContent.timeline_from_dict({}).mutation_levels_scale).is_false()
	assert_bool(JsonContent.timeline_from_dict({"mutation_levels_scale": true}).mutation_levels_scale).is_true()
	# Run.xp_to_next follows the map's pace (read from the map, never pinned: Garry tunes it in the Level Editor)
	var mt: WaveTimeline = Run.map.timeline
	for L: int in [1, 5, 20, 60]:
		var want := (15.0 + 6.0 * L + 0.5 * L * L) * mt.xp_need_mult
		assert_float(Run.xp_to_next(L)).is_equal_approx(want, 0.001)
	# the arena keeps the plain curve
	Run.arena = true
	assert_float(Run.xp_to_next(5)).is_equal_approx(15.0 + 30.0 + 12.5, 0.001)


# ---------------------------------------------------------------- Game: the screen, the director, the mark

func _game() -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "boomstick", "level": 2, "character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	g.player.god = true
	return g


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_a_mutation_level_up_shows_the_offer_in_place_of_the_cards() -> void:
	var g := await _game()
	assert_bool(Run.path_offer_instances().is_empty()).is_false()
	Run.mutlvl_due = 1
	Run.mutation_due_changed.emit()
	assert_bool(g.hud.mutation_mark_on()).is_true()
	_level_up()
	await _frames(2)
	assert_bool(g.cards.visible).is_true()
	assert_bool(g.cards.path_mode).override_failure_message("the level-up showed cards, not the mutation offer").is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.PATH)
	for c in g.cards._offer:
		assert_str(str(c["type"])).is_equal("mutation")
	assert_int(Run.mutation_levels).is_equal(1)
	assert_bool(g.hud.mutation_mark_on()).is_false()
	# the head says it is the level's
	assert_str(CardScreen.mutlvl_line(Run.level)).is_equal("Level %d! Pick a mutation" % Run.level)
	if g.cards.reel_running():
		g.cards.skip_reel()
	var pick: Dictionary = g.cards._offer[0]
	g.cards._pick(pick)
	await get_tree().create_timer(0.8).timeout
	var w := Run.family_instance((pick["def"] as MutationDef).weapon)
	assert_bool(w.has_mutation(str(pick["id"]))).is_true()
	g.modal_reset()
	g.set_paused(false)


func test_a_level_up_with_no_pick_open_shows_the_three_cards() -> void:
	var g := await _game()
	for w: WeaponInstance in Run.weapons:
		Run.mutation_stage[w.family_id()] = Run.stage
	Run.mutlvl_due = 1
	Run.mutation_due_changed.emit()
	assert_bool(g.hud.mutation_mark_on()).is_false()
	_level_up()
	await _frames(2)
	assert_bool(g.cards.visible).is_true()
	assert_bool(g.cards.path_mode).is_false()
	assert_int(Run.mutation_levels).is_equal(0)
	g.modal_reset()
	g.set_paused(false)


func test_the_director_never_opens_an_offer_on_the_clock() -> void:
	var g := await _game()
	var times: Array = Run.map.timeline.path_times_at(0)
	Run.path_slot = 0
	Run.elapsed = float(times[0]) - 0.02
	await _frames(6)
	assert_int(Run.path_slot).is_equal(1)
	assert_int(Run.mutlvl_due).is_equal(1)
	assert_bool(g.cards.visible).override_failure_message("the slot opened a screen on its own").is_false()
	assert_bool(g.paused).is_false()
	assert_bool(g.hud.mutation_mark_on()).is_true()
