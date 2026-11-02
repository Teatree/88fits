extends GdUnitTestSuite

## Pass 121, lane GRIND (Garry: "Grindstone - should be a 1 time use item. And there should be an animation sequence
## showing a weapon being upgraded. It's one time use, no upgrades, player gets only one ever."; one a run, the lead):
## - the Grindstone is a one-shot item (`single`, like Phoenix Feather): one level, off the rarity ladder, rare, weight 5;
## - taking it works once (the weakest weapon one level up, or with every weapon maxed a ready one evolved: grind_target)
##   and it is never offered again that run, from any source (cards, chests, the Stranger, the shop), even if it left
##   the build (grind_idle); held, it reads used (item_spent, spent_words);
## - every route raises the weapon exactly once: a level-up card, a chest, the Stranger, the arena's ITEMS tab;
## - the show (ui/GrindMoment.gd, Game.Modal.GRIND): time stops, it plays its beats, a tap hurries it (recorded for
##   replays: "grind_hurry"), it closes into the gate and the run goes on; behind another screen it waits its turn.

const STONE := "grindstone"


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	CardPool.rng = null


func after_test() -> void:
	CardPool.rng = null
	Run.arena = false
	Run.end()


func _start(hero: String = "drifter") -> void:
	var c: CharacterDef = Registry.character(hero)
	Run.start(c, Registry.map("red_canyon"))
	Run.add_weapon(Registry.start_weapon_for(c), 1)


func _g() -> PassiveDef:
	return Registry.passive(STONE)


func _levels() -> Dictionary:
	var out := {}
	for w: WeaponInstance in Run.weapons:
		out[w.def.id] = w.level
	return out


## The run's weapon levels went up by exactly one level in total, on `id`.
func _raised_once(before: Dictionary, id: String) -> void:
	var after := _levels()
	var total := 0
	for k in after.keys():
		total += int(after[k]) - int(before.get(k, 0))
	assert_int(total).override_failure_message("levels gained: %s -> %s" % [str(before), str(after)]).is_equal(1)
	assert_int(int(after.get(id, 0))).is_equal(int(before.get(id, 0)) + 1)


# ---------------------------------------------------------------- the item

func test_it_is_a_one_shot_item_of_one_level() -> void:
	var g := _g()
	assert_object(g).is_not_null()
	assert_bool(g.single).is_true()
	assert_bool(g.is_item()).is_true()
	assert_bool(g.on_ladder()).is_false()
	assert_int(g.max_level).is_equal(1)
	assert_int(g.ladder_top()).is_equal(1)
	assert_int(g.levels.size()).is_equal(1)
	# rarity and weight kept
	assert_str(g.rarity).is_equal("rare")
	assert_int(int(g.weight)).is_equal(5)
	for lv in [0, 1, 2, 4]:
		assert_str(g.rung_at(lv)).is_equal("rare")
		assert_bool(g.is_evolved_rung(lv)).is_false()
	# the card says it works once and never levels up; nothing promises rungs
	var t := TextGen.passive_text(g)
	assert_str(t).starts_with("Once:")
	assert_str(t).contains("weakest weapon")
	assert_str(t).contains("evolves")
	assert_str(t).contains("never levels up")
	assert_int(t.length()).is_less_equal(190)
	for s: String in [t, TextGen.passive_description(g, 1), WItem.effect({"def": g, "level_from": 0, "level_to": 1})]:
		assert_bool(s.contains("Evolved")).override_failure_message(s).is_false()
		assert_bool(s.to_lower().contains("rung")).override_failure_message(s).is_false()
	assert_str(WItem.effect({"def": g, "level_from": 0, "level_to": 1})).is_equal(t)
	# the show's numbers are the item's: a level 2.5-3.5 s, an evolution no longer than 3.6 s
	var m: Dictionary = g.params["grind"]["moment"]
	assert_float(float(m["seconds"])).is_between(2.5, 3.5)
	assert_float(float(m["evolve_seconds"])).is_between(2.5, 3.6)
	assert_float(float(m["reveal_at"])).is_less(float(m["seconds"]))
	# every sound it names is bound (the grind's own, or its fallback)
	for k in ["sound_press", "sound_stamp", "sound_level", "sound_flash", "sound_evolve"]:
		assert_bool(Registry.soundmap.entry(str(m[k])).get("stream") != null).override_failure_message(k).is_true()
	var grind_bound: bool = Registry.soundmap.entry(str(m["sound_grind"])).get("stream") != null \
		or Registry.soundmap.entry(str(m["sound_grind_fallback"])).get("stream") != null
	assert_bool(grind_bound).is_true()


func test_taking_it_works_once_and_it_is_never_offered_again() -> void:
	_start()
	var rev := Run.weapon_instance("revolver")
	var saws := Run.add_weapon(Registry.weapon("orbit_saws"), 1)
	Run.level_weapon("revolver")
	var told: Array = []
	var cb := func(id: String, words: String) -> void: told.append([id, words])
	Run.grindstone_worked.connect(cb)
	assert_bool(Run.grind_used.is_empty()).is_true()
	assert_bool(CardPool.offer_passives().has(_g())).is_true()
	var before := _levels()
	assert_bool(Run.add_or_level_passive(STONE)).is_true()
	# the weakest: the saws (level 1) to level 2
	_raised_once(before, "orbit_saws")
	assert_int(saws.level).is_equal(2)
	assert_int(rev.level).is_equal(2)
	assert_array(told).is_equal([["orbit_saws", "level 2"]])
	assert_dict(Run.grind_used).is_equal({"id": "orbit_saws", "from": "orbit_saws", "level_from": 1, "level_to": 2, "evolved": false})
	# held at its one level, used: never again
	assert_int(Run.passive_level(STONE)).is_equal(1)
	assert_bool(Run.add_or_level_passive(STONE)).is_false()
	assert_int(saws.level).is_equal(2)
	assert_int(told.size()).is_equal(1)
	Run.grindstone_worked.disconnect(cb)
	assert_bool(Run.item_spent(_g())).is_true()
	assert_str(Run.spent_words(_g())).is_equal("Used: it ground the Orbit Saws to level 2")
	assert_bool(Run.grind_idle(_g())).is_true()
	assert_bool(CardPool.offer_passives().has(_g())).is_false()
	var ids := func(list: Array) -> Array: return list.map(func(c: Dictionary) -> String: return str(c.get("id", "")))
	assert_array(ids.call(Run.chest_candidates())).not_contains([STONE])
	# no Stranger and no level-up's cards hold it, however often they are rolled
	for k in 60:
		assert_str(str(Run.stranger_offer().get("id", ""))).is_not_equal(STONE)
		assert_array(ids.call(CardPool.level_up_offer(3))).not_contains([STONE])
	# even out of the build (the arena's −), a used one stays out of every offer this run
	Run.passives.erase(STONE)
	assert_bool(CardPool.offer_passives().has(_g())).is_false()
	assert_array(ids.call(Run.chest_candidates())).not_contains([STONE])
	# a new run: offered again (one a run)
	Run.end()
	_start()
	Run.add_weapon(Registry.weapon("orbit_saws"), 1)
	assert_bool(Run.grind_used.is_empty()).is_true()
	assert_bool(Run.item_spent(_g())).is_false()
	assert_bool(CardPool.offer_passives().has(_g())).is_true()


func test_the_phoenix_keeps_its_own_used_words() -> void:
	_start()
	var ph: PassiveDef = Registry.passive("phoenix_feather")
	Run.add_or_level_passive("phoenix_feather")
	Run.use_phoenix()
	assert_bool(Run.item_spent(ph)).is_true()
	assert_str(Run.spent_words(ph)).is_equal("Used: it stood you up once this run")
	# a Grindstone not used yet is not spent, whatever the feather did
	assert_bool(Run.item_spent(_g())).is_false()


# ---------------------------------------------------------------- every route, once

func test_a_level_up_card_raises_the_weapon_once() -> void:
	_start()
	var before := _levels()
	CardPool.apply({"type": "passive", "id": STONE, "def": _g(), "level_from": 0, "level_to": 1, "is_new": true})
	_raised_once(before, "revolver")
	assert_int(Run.passive_level(STONE)).is_equal(1)


func test_a_chest_raises_the_weapon_once() -> void:
	_start()
	var before := _levels()
	var r := {"type": "passive", "id": STONE, "def": _g(), "level_from": 0, "level_to": 1, "is_new": true}
	assert_str(Run.chest_take(r)).contains("Grindstone")
	_raised_once(before, "revolver")
	# the same roll taken again (it cannot be offered: a test's hand) pays gold, the weapon is not touched again
	var gold := Run.run_gold
	Run.chest_take(r)
	assert_int(Run.weapon_instance("revolver").level).is_equal(2)
	assert_int(Run.run_gold).is_greater(gold)


func test_the_stranger_raises_the_weapon_once() -> void:
	_start()
	var before := _levels()
	# the Stranger's new item at its offered level (min(2, max) = 1 for a one-level item)
	var offer := {"type": "passive", "id": STONE, "def": _g(), "level_from": 0, "level_to": maxi(mini(2, _g().max_level), 1), "is_new": true}
	assert_int(int(offer["level_to"])).is_equal(1)
	Run.stranger_take(offer, 0.15)
	_raised_once(before, "revolver")


func test_the_arena_plus_raises_the_weapon_once() -> void:
	_start()
	Run.arena = true
	var before := _levels()
	# MAX and + both stop at its one level
	Run.debug_set_item("passive", STONE, 99)
	_raised_once(before, "revolver")
	assert_int(Run.passive_level(STONE)).is_equal(1)
	Run.debug_set_item("passive", STONE, 2)
	assert_int(Run.weapon_instance("revolver").level).is_equal(2)


func test_with_every_weapon_maxed_it_evolves_a_ready_one() -> void:
	_start()
	var rev := Run.weapon_instance("revolver")
	while rev.level < rev.def.max_level:
		Run.level_weapon("revolver")
	assert_bool(Run.grind_idle(_g())).is_true()
	for m: MutationDef in Registry.mutations_of("revolver"):
		Run.add_mutation(m.id, true)
	assert_bool(Run.grind_can_work()).is_true()
	var into := rev.def.evolves_into
	var evos := Run.evolutions
	Run.add_or_level_passive(STONE)
	assert_str((Run.weapons[0] as WeaponInstance).def.id).is_equal(into)
	assert_int(Run.evolutions).is_equal(evos + 1)
	assert_bool(Run.grind_working).is_false()
	assert_str(str(Run.grind_used["from"])).is_equal("revolver")
	assert_str(str(Run.grind_used["id"])).is_equal(into)
	assert_bool(bool(Run.grind_used["evolved"])).is_true()
	assert_int(int(Run.grind_used["level_from"])).is_equal(rev.def.max_level)
	assert_str(Run.spent_words(_g())).is_equal("Used: it evolved the Revolver into the %s" % Registry.weapon(into).display_name)


# ---------------------------------------------------------------- the show on its own

func _moment() -> GrindMoment:
	var m: GrindMoment = auto_free(GrindMoment.new())
	add_child(m)
	m.size = Vector2(1080, 1920)
	return m


func test_the_show_plays_its_beats_and_ends() -> void:
	var m := _moment()
	var mo: Dictionary = _g().params["grind"]["moment"]
	m.open({"id": "revolver", "from": "revolver", "level_from": 2, "level_to": 3, "evolved": false}, mo)
	var ends := [0]
	m.finished.connect(func() -> void: ends[0] += 1)
	assert_bool(m.playing).is_true()
	assert_bool(m.visible).is_true()
	assert_str(m.phase()).is_equal("spin")
	var b := m.beats()
	assert_float(float(b["seconds"])).is_equal(float(mo["seconds"]))
	m.seek(float(b["press"]) + 0.3)
	assert_str(m.phase()).is_equal("grind")
	assert_int(m.sparks_thrown).is_greater(10)
	m.seek(float(b["reveal"]) + 0.05)
	assert_str(m.phase()).is_equal("reveal")
	assert_bool(m.stamped).is_false()
	m.seek(float(b["stamp"]) + 0.05)
	assert_str(m.phase()).is_equal("stamped")
	assert_bool(m.stamped).is_true()
	m.seek(float(b["seconds"]) - 0.1)
	assert_str(m.phase()).is_equal("fade")
	assert_int(ends[0]).is_equal(0)
	m.advance(0.2)
	assert_bool(m.playing).is_false()
	assert_bool(m.visible).is_false()
	assert_int(ends[0]).is_equal(1)
	# an evolution plays longer (its burst after the old plate's flashes)
	m.open({"id": "golden_revolver", "from": "revolver", "level_from": 5, "level_to": 1, "evolved": true}, mo)
	assert_float(float(m.beats()["seconds"])).is_equal(float(mo["evolve_seconds"]))
	m.seek(float(m.beats()["stamp"]) + 0.01)
	assert_bool(m.stamped).is_true()
	m.skip()
	assert_int(ends[0]).is_equal(2)


func test_a_tap_hurries_it_to_the_reveal_the_stamp_then_the_fade() -> void:
	var m := _moment()
	m.open({"id": "revolver", "from": "revolver", "level_from": 1, "level_to": 2, "evolved": false}, _g().params["grind"]["moment"])
	var b := m.beats()
	m.advance(0.1)
	assert_bool(m.hurry()).is_true()
	assert_float(m.t).is_equal_approx(float(b["reveal"]), 0.0001)
	assert_bool(m.hurry()).is_true()
	assert_float(m.t).is_equal_approx(float(b["stamp"]), 0.0001)
	assert_bool(m.stamped).is_true()
	# the guard: a tap right on the stamp does nothing (a double tap does not throw the result away)
	assert_bool(m.hurry()).is_false()
	m.advance(0.35)
	assert_bool(m.hurry()).is_true()
	assert_float(m.t).is_equal_approx(float(b["fade"]), 0.0001)
	assert_bool(m.hurry()).is_false()
	assert_int(m.hurries).is_equal(3)
	m.advance(1.0)
	assert_bool(m.playing).is_false()


# ---------------------------------------------------------------- in a run

func _game() -> Game:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 9, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	return g


func _until(cond: Callable, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		if cond.call():
			return true
		await get_tree().create_timer(0.05, true).timeout
		waited += 0.05
	return bool(cond.call())


func test_time_stops_for_the_show_and_the_run_goes_on_through_the_gate() -> void:
	var g := _game()
	await get_tree().create_timer(0.4).timeout
	await _until(func() -> bool: return not g.spawning, 6.0)
	g.player.god = true
	var rev := Run.weapon_instance("revolver")
	assert_int(rev.level).is_equal(1)
	# taken from the running game (as the arena's hand would): the show opens at once
	Run.add_or_level_passive(STONE)
	assert_int(rev.level).is_equal(2)
	assert_int(g.current_modal()).is_equal(Game.Modal.GRIND)
	assert_bool(g.paused).is_true()
	assert_bool(get_tree().paused).is_true()
	var gm = g.grind_moment
	assert_object(gm).is_not_null()
	assert_bool(gm.playing).is_true()
	assert_array(g.visible_modals()).is_equal(["grind"])
	var clock0 := Run.elapsed
	# a finger while it plays: swallowed (nothing opens), and it hurries the show
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = Vector2(1000, 120)
	t.pressed = true
	Input.parse_input_event(t)
	await get_tree().process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = t.position
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame
	assert_int(int(gm.touches_eaten)).is_greater_equal(1)
	assert_bool(g.pause_screen.visible).is_false()
	assert_str(str(gm.phase())).is_not_equal("spin")
	# it ends by itself into the gate (the weapon's plate flying to its slot); the clock never moved meanwhile
	var ended: bool = await _until(func() -> bool: return not bool(gm.playing), 5.0)
	assert_bool(ended).is_true()
	assert_float(Run.elapsed).is_equal_approx(clock0, 0.0001)
	await _until(func() -> bool: return g.resume_gate.visible, 1.0)
	assert_bool(g.resume_gate.visible).is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.NONE)
	g.resume_gate.tap()
	await get_tree().process_frame
	assert_bool(g.paused).is_false()
	assert_bool(get_tree().paused).is_false()
	# the weapon went up exactly once
	assert_int(Run.weapon_instance("revolver").level).is_equal(2)


func test_behind_another_screen_the_show_waits_its_turn() -> void:
	var g := _game()
	await get_tree().create_timer(0.4).timeout
	await _until(func() -> bool: return not g.spawning, 6.0)
	g.player.god = true
	# a screen is up (the shop's turn, held by hand): the Grindstone taken from it waits
	g._open_modal(Game.Modal.SHOP, func() -> bool:
		g.set_paused(true)
		return true)
	assert_int(g.current_modal()).is_equal(Game.Modal.SHOP)
	Run.add_or_level_passive(STONE)
	assert_int(Run.weapon_instance("revolver").level).is_equal(2)
	assert_array(g.modal_queue_kinds()).contains([Game.Modal.GRIND])
	assert_bool(g.grind_moment == null or not g.grind_moment.playing).is_true()
	# the shop closes: after the beat the show opens
	g._modal_done({}, false)
	var opened: bool = await _until(func() -> bool: return g.grind_moment != null and bool(g.grind_moment.playing), 2.0)
	assert_bool(opened).is_true()
	assert_int(g.current_modal()).is_equal(Game.Modal.GRIND)
	assert_bool(g.paused).is_true()
	# the replay's hand on it: the recorded tap hurries it as the player's did
	var rr := RunReplay.new()
	rr.game = g
	var t0: float = g.grind_moment.t
	assert_bool(rr._apply({"k": "grind_hurry", "f": 0, "p": 0})).is_true()
	assert_float(float(g.grind_moment.t)).is_greater(t0)
	rr.free()
	g.grind_moment.skip()
	await _until(func() -> bool: return g.resume_gate.visible, 1.0)
	g.resume_gate.tap()
	await get_tree().process_frame
	assert_bool(g.paused).is_false()
	assert_int(Run.weapon_instance("revolver").level).is_equal(2)
	# with no show up the decision waits (a replay that parted)
	var rr2 := RunReplay.new()
	rr2.game = g
	assert_bool(rr2._apply({"k": "grind_hurry", "f": 0, "p": 0})).is_false()
	rr2.free()


func test_an_evolution_by_it_shows_no_banner_of_its_own() -> void:
	var g := _game()
	await get_tree().create_timer(0.4).timeout
	await _until(func() -> bool: return not g.spawning, 6.0)
	g.player.god = true
	var rev := Run.weapon_instance("revolver")
	while rev.level < rev.def.max_level:
		Run.level_weapon("revolver")
	for m: MutationDef in Registry.mutations_of("revolver"):
		Run.add_mutation(m.id, true)
	var into := rev.def.evolves_into
	Run.add_or_level_passive(STONE)
	assert_str((Run.weapons[0] as WeaponInstance).def.id).is_equal(into)
	assert_int(g.current_modal()).is_equal(Game.Modal.GRIND)
	assert_bool(bool(g.grind_moment.evolved)).is_true()
	assert_object(g.grind_moment.to_def).is_equal(Registry.weapon(into))
	assert_object(g.grind_moment.from_def).is_equal(Registry.weapon("revolver"))
	# no EVOLVED banner of the evolution's own (Game._on_evolved gives way: Run.grind_working)
	assert_bool(g.hud.banner_text().begins_with("EVOLVED")).is_false()
	g.grind_moment.skip()
	await _until(func() -> bool: return g.resume_gate.visible, 1.0)
	g.resume_gate.tap()
	await get_tree().process_frame
	assert_bool(g.paused).is_false()
