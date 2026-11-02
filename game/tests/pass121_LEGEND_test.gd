## Pass 121, lane LEGEND (Garry, 2026-11-02: "Make it so that up until 4:30 in every run of any Stage there is 0 chance of
## getting a Legendary and after 4:30 there is some (small) chance of getting it (so whatever it is now)"; "No guarantee,
## just the hold"): no new legendary item is offered before the stage clock reaches the map's `legendary.from`, in any
## offer (level-up cards, a banish's redraw, the Shop, a chest's roll and its reel's filler, the Stranger); after it the
## draw is the old one; a stage's own block wins over the map's; the guarantee switch (`guarantee_at`, off) changes
## nothing while off and, on, puts one legendary into the next level-up after its time, once. BALANCING.md 63.LEGEND.
extends GdUnitTestSuite

## The legendary items' weights while a test forces them high (restored in after_test).
var _weights: Dictionary = {}
## The map the run plays: a copy of Red Canyon with its own timeline, so a test can set the legendary block freely.
var _map: MapDef = null


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	CardPool.rng = null
	_weights.clear()
	var src: MapDef = Registry.map("red_canyon")
	_map = src.duplicate()
	_map.timeline = src.timeline.duplicate(true)
	# its own lists and blocks (never the Registry's), the map's legendary block as the file has it, no stage's own
	_map.timeline.stage_list = src.timeline.stage_list.duplicate(true)
	_map.timeline.legendary = src.timeline.legendary.duplicate(true)
	for e in _map.timeline.stage_list:
		if e is Dictionary:
			(e as Dictionary).erase("legendary")


func after_test() -> void:
	for id in _weights.keys():
		var p: PassiveDef = Registry.passive(str(id))
		if p:
			p.weight = float(_weights[id])
	_weights.clear()
	CardPool.rng = null
	Run.arena = false
	Run.end()


## Every legendary item in the game (by rarity: the hold reads the rarity, never a list).
func _legends() -> Array:
	return Registry.passives.values().filter(func(p: PassiveDef) -> bool: return p.rarity == "legendary" and not p.hidden and not p.is_evolved())


func _legend_ids() -> Array:
	return _legends().map(func(p: PassiveDef) -> String: return p.id)


## Makes every legendary item far likelier than anything else (the test's "luck"), remembering the old weights.
func _force_legends() -> void:
	for p: PassiveDef in _legends():
		if not _weights.has(p.id):
			_weights[p.id] = p.weight
		p.weight = 100000.0


func _start(stage: int = 0) -> void:
	var c: CharacterDef = Registry.character("drifter")
	Run.start(c, _map)
	Run.add_weapon(Registry.start_weapon_for(c), 1)
	Run.start_stage(stage)


## Puts the stage clock at `secs` (the HUD's clock: 0:00 at the stage's start).
func _at(secs: float) -> void:
	Run.elapsed = _map.timeline.stage_start(Run.stage) + secs
	assert_float(Run.stage_clock()).is_equal_approx(secs, 0.001)


func _seed(s: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = s
	CardPool.rng = r


## The ids of cards (Dictionaries) or of defs (CardPool.offer_passives' PassiveDefs).
func _ids(cards: Array) -> Array:
	return cards.map(func(c) -> String: return (c as ContentDef).id if c is ContentDef else str((c as Dictionary).get("id", "")))


func _has_legend(cards: Array) -> bool:
	for c in cards:
		if c is Dictionary and (c as Dictionary).get("def") is ContentDef and ((c as Dictionary)["def"] as ContentDef).rarity == "legendary":
			return true
	return false


## Every offer source at once, `n` times: the level-up cards (and the Shop's, the same draw), a banish's redraw, a chest's
## roll, the Stranger. Returns how many held a legendary.
func _offers_with_legend(n: int) -> int:
	var hits := 0
	for k in range(n):
		var lv := CardPool.level_up_offer(3, [], true)
		if _has_legend(lv):
			hits += 1
		if _has_legend(CardPool.level_up_offer(3)):
			hits += 1
		if _has_legend(CardPool.level_up_offer(1, _ids(lv))):
			hits += 1
		if _has_legend([Run.chest_roll()]):
			hits += 1
		if _has_legend([Run.stranger_offer()]):
			hits += 1
	return hits


# ---------------------------------------------------------------- the data

func test_the_map_file_carries_the_block_and_the_game_reads_it() -> void:
	var f := FileAccess.open("res://content/maps/red_canyon/red_canyon.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	var block = (d["timeline_data"] as Dictionary).get("legendary")
	assert_bool(block is Dictionary).override_failure_message("timeline_data.legendary is missing").is_true()
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	for key: String in ["from", "guarantee_at"]:
		assert_bool(block[key] is float or block[key] is int).override_failure_message(key).is_true()
		assert_float(tl.legendary_value(key)).is_equal_approx(float(block[key]), 0.001)
		# a stage with no block of its own plays the map's
		for k in range(tl.stage_count()):
			var own = (tl.stage_list[k] as Dictionary).get("legendary", {}) if tl.stage_list.size() > k and tl.stage_list[k] is Dictionary else {}
			if not (own is Dictionary and (own as Dictionary).has(key)):
				assert_float(tl.legendary_value(key, k)).is_equal_approx(float(block[key]), 0.001)
	# the code's defaults: 4:30 and off
	assert_float(float(WaveTimeline.LEGENDARY_DEFAULTS["from"])).is_equal(270.0)
	assert_float(float(WaveTimeline.LEGENDARY_DEFAULTS["guarantee_at"])).is_equal(0.0)
	# a timeline without the block plays them
	var bare := WaveTimeline.new()
	assert_float(bare.legendary_value("from")).is_equal(270.0)
	assert_float(bare.legendary_value("guarantee_at", 1)).is_equal(0.0)
	var parsed := JsonContent.timeline_from_dict({"legendary": {"from": 99, "guarantee_at": 500}})
	assert_float(parsed.legendary_value("from")).is_equal(99.0)
	assert_float(parsed.legendary_value("guarantee_at")).is_equal(500.0)


func test_the_six_legendaries_are_held_by_rarity() -> void:
	var ids := _legend_ids()
	assert_array(ids).contains(["fools_gold", "iron_horse", "lightning_in_a_bottle", "personal_storm", "pocket_bible", "undertakers_shovel"])
	_start()
	_at(0.0)
	for p: PassiveDef in _legends():
		assert_bool(LegendaryHold.held(p)).is_true()
	# a rarer-than-common item that is not legendary is never held
	assert_bool(LegendaryHold.held(Registry.passive("jade_key"))).is_false()
	# a future legendary of any kind is held by its rarity alone
	var fake := PassiveDef.new()
	fake.rarity = "legendary"
	assert_bool(LegendaryHold.held(fake)).is_true()
	fake.rarity = "epic"
	assert_bool(LegendaryHold.held(fake)).is_false()


# ---------------------------------------------------------------- the hold

func test_none_offered_before_the_hold_ends_in_any_stage_whatever_the_luck() -> void:
	_force_legends()
	var from := 0.0
	for stage in range(_map.timeline.stage_count()):
		_start(stage)
		from = LegendaryHold.from_seconds()
		assert_float(from).is_greater(0.0)
		Run.player_sheet.add_effects([Effect.make("luck", "add", 50.0, "player")], "test luck")
		_seed(1000 + stage)
		for t: float in [0.0, 30.0, from * 0.5, from - 1.0, from - 0.01]:
			_at(t)
			assert_bool(LegendaryHold.open()).is_false()
			assert_array(_ids(CardPool.offer_passives())).not_contains(_legend_ids())
			assert_array(_ids(CardPool.candidates())).not_contains(_legend_ids())
			assert_array(_ids(Run.chest_candidates())).not_contains(_legend_ids())
			assert_int(_offers_with_legend(30)).override_failure_message("stage %d at %.1f s" % [stage + 1, t]).is_equal(0)
		assert_bool(Run.legendary_shown).is_false()


func test_offered_once_the_stage_clock_reaches_it() -> void:
	_force_legends()
	for stage in range(_map.timeline.stage_count()):
		_start(stage)
		var from := LegendaryHold.from_seconds()
		_seed(77 + stage)
		_at(from)
		assert_bool(LegendaryHold.open()).is_true()
		assert_array(_ids(CardPool.offer_passives())).contains(_legend_ids())
		assert_array(_ids(Run.chest_candidates())).contains(_legend_ids())
		# forced high, the level-up shows them, and so do a chest and the Stranger
		var lv := 0
		var chest := 0
		var stranger := 0
		for k in range(40):
			if _has_legend(CardPool.level_up_offer(3, [], true)):
				lv += 1
			if _has_legend([Run.chest_roll()]):
				chest += 1
		# the Stranger draws evenly among his candidates (weights do not count there): some of 200
		for k in range(200):
			if _has_legend([Run.stranger_offer()]):
				stranger += 1
		assert_int(lv).is_greater(30)
		assert_int(chest).is_greater(30)
		assert_int(stranger).is_greater(0)
		assert_bool(Run.legendary_shown).is_true()


func test_after_the_hold_the_draw_is_the_old_one() -> void:
	# past the hold the weights are weight_of's, and the candidates are those of a hold that never was (from 0)
	_start()
	var from := LegendaryHold.from_seconds()
	_at(from + 5.0)
	var past: Array = CardPool.candidates()
	_map.timeline.legendary = {"from": 0}
	var never: Array = CardPool.candidates()
	assert_array(_ids(past)).is_equal(_ids(never))
	for k in range(past.size()):
		assert_float(float(past[k]["weight"])).is_equal_approx(float(never[k]["weight"]), 0.0001)
	for c: Dictionary in past:
		var lv: int = int(c["level_from"])
		if bool(c.get("evolve", false)) or str(c["type"]) == "perk" or (c["def"] is WeaponDef and lv == 0):
			continue
		assert_float(float(c["weight"])).is_equal_approx(CardPool.weight_of(c["def"], lv), 0.0001)


func test_the_boss_falling_and_endless_count_as_past() -> void:
	_start()
	_at(10.0)
	assert_bool(LegendaryHold.open()).is_false()
	Run.stage_beaten = true
	assert_bool(LegendaryHold.open()).is_true()
	Run.stage_beaten = false
	Run.endless = true
	assert_bool(LegendaryHold.open()).is_true()
	assert_array(_ids(CardPool.offer_passives())).contains(_legend_ids())
	Run.endless = false
	assert_bool(LegendaryHold.open()).is_false()


func test_a_legendary_already_held_keeps_its_levels() -> void:
	# only the debug arena's ITEMS tab hands one over this early (it is no offer)
	_start()
	_at(5.0)
	Run.debug_set_item("passive", "fools_gold", 1)
	assert_int(Run.passive_level("fools_gold")).is_equal(1)
	var up: Array = CardPool.candidates().filter(func(c: Dictionary) -> bool: return str(c["id"]) == "fools_gold")
	assert_int(up.size()).is_equal(1)
	assert_int(int(up[0]["level_from"])).is_equal(1)
	# and the other legendaries stay held
	var others: Array = _legend_ids().filter(func(id: String) -> bool: return id != "fools_gold")
	assert_array(_ids(CardPool.candidates())).not_contains(others)


func test_the_chest_reel_never_shows_a_held_legendary_as_filler() -> void:
	_start()
	var cs = load("res://ui/ChestScreen.gd").new()
	_at(0.0)
	var pool: Array = cs._pool_for("passive", null)
	assert_array(pool.map(func(d: ContentDef) -> String: return d.id)).not_contains(_legend_ids())
	_at(LegendaryHold.from_seconds())
	pool = cs._pool_for("passive", null)
	assert_array(pool.map(func(d: ContentDef) -> String: return d.id)).contains(["fools_gold"])
	cs.free()


func test_a_stage_block_wins_over_the_map() -> void:
	_map.timeline.legendary = {"from": 200, "guarantee_at": 0}
	var sl: Array = _map.timeline.stage_list
	assert_int(sl.size()).is_greater(1)
	(sl[1] as Dictionary)["legendary"] = {"from": 60}
	_start(0)
	assert_float(LegendaryHold.from_seconds()).is_equal(200.0)
	_at(100.0)
	assert_bool(LegendaryHold.open()).is_false()
	_start(1)
	assert_float(LegendaryHold.from_seconds()).is_equal(60.0)
	# the key it leaves out is the map's
	assert_float(LegendaryHold.guarantee_seconds()).is_equal(0.0)
	_at(59.0)
	assert_bool(LegendaryHold.open()).is_false()
	_at(61.0)
	assert_bool(LegendaryHold.open()).is_true()
	assert_array(_ids(CardPool.offer_passives())).contains(_legend_ids())
	# a stage's 0 opens them from its start
	(sl[1] as Dictionary)["legendary"] = {"from": 0}
	_at(0.0)
	assert_bool(LegendaryHold.open()).is_true()
	# no block anywhere: the default 4:30
	_map.timeline.legendary = {}
	(sl[1] as Dictionary).erase("legendary")
	assert_float(LegendaryHold.from_seconds()).is_equal(270.0)


# ---------------------------------------------------------------- the guarantee switch

func test_the_guarantee_off_changes_nothing() -> void:
	_map.timeline.legendary = {"from": 270, "guarantee_at": 0}
	_start()
	for t: float in [10.0, 300.0, 400.0]:
		_at(t)
		assert_bool(LegendaryHold.guarantee_due()).is_false()
		var a: Array = []
		var b: Array = []
		_seed(4242)
		for k in range(25):
			a.append(_ids(CardPool.level_up_offer(3, [], true)))
		Run.legendary_shown = false
		_seed(4242)
		for k in range(25):
			b.append(_ids(CardPool.level_up_offer(3, [], false)))
		assert_array(a).is_equal(b)


func test_the_guarantee_on_puts_one_in_the_next_level_up_once() -> void:
	_map.timeline.legendary = {"from": 270, "guarantee_at": 300}
	_start()
	_seed(9)
	_at(299.0)
	assert_bool(LegendaryHold.guarantee_due()).is_false()
	_at(300.0)
	assert_bool(Run.legendary_shown).is_false()
	assert_bool(LegendaryHold.guarantee_due()).is_true()
	# the Shop's offer is not a level-up: never forced
	var shop := CardPool.level_up_offer(3)
	if not _has_legend(shop):
		assert_bool(LegendaryHold.guarantee_due()).is_true()
	Run.legendary_shown = false
	var offer := CardPool.level_up_offer(3, [], true)
	assert_int(offer.size()).is_equal(3)
	assert_bool(_has_legend(offer)).is_true()
	assert_bool(Run.legendary_shown).is_true()
	assert_bool(LegendaryHold.guarantee_due()).is_false()
	# once only: an offer without one is left as it was from now on
	var plain: Array = CardPool.candidates().filter(func(c: Dictionary) -> bool: return not _has_legend([c])).slice(0, 3)
	assert_array(_ids(LegendaryHold.guarantee(plain, CardPool.candidates(), 3))).is_equal(_ids(plain))


func test_the_guarantee_waits_for_the_hold_and_only_names_what_the_hero_can_take() -> void:
	_map.timeline.legendary = {"from": 270, "guarantee_at": 100}
	_start()
	_at(200.0)
	assert_bool(LegendaryHold.guarantee_due()).is_false()
	_at(270.0)
	assert_bool(LegendaryHold.guarantee_due()).is_true()
	# the Iron Horse held shuts the Storm out: the forced card is never the Storm; banished ones never come
	Run.debug_set_item("passive", "iron_horse", 1)
	Run.legendary_shown = false
	for id: String in ["fools_gold", "lightning_in_a_bottle", "pocket_bible"]:
		Run.banished.append(id)
	for k in range(30):
		Run.legendary_shown = false
		var offer := CardPool.level_up_offer(3, [], true)
		assert_bool(_has_legend(offer)).is_true()
		for c: Dictionary in offer:
			assert_str(str(c["id"])).is_not_equal("personal_storm")
			assert_bool(["fools_gold", "lightning_in_a_bottle", "pocket_bible"].has(str(c["id"]))).is_false()
	# nothing left to take: the offer is the plain draw
	Run.banished.append("undertakers_shovel")
	Run.debug_set_item("passive", "iron_horse", 2)
	Run.legendary_shown = false
	var none: Array = CardPool.candidates().filter(func(c: Dictionary) -> bool: return _has_legend([c]))
	assert_int(none.size()).is_equal(0)
	var plain := CardPool.level_up_offer(3, [], true)
	assert_bool(_has_legend(plain)).is_false()
	assert_bool(Run.legendary_shown).is_false()


func test_the_guarantee_is_the_same_on_the_same_dice() -> void:
	_map.timeline.legendary = {"from": 270, "guarantee_at": 280}
	var runs: Array = []
	for rep in range(2):
		_start()
		_at(281.0)
		_seed(31337)
		var seq: Array = []
		for k in range(6):
			seq.append(_ids(CardPool.level_up_offer(3, [], true)))
		runs.append(seq)
	assert_array(runs[0]).is_equal(runs[1])
	assert_bool((runs[0] as Array).size() == 6).is_true()


# ---------------------------------------------------------------- "shown", counted from every source

func test_shown_is_counted_from_every_source() -> void:
	_force_legends()
	_start()
	_at(LegendaryHold.from_seconds() + 1.0)
	_seed(5)
	# a chest
	var r := Run.chest_roll()
	assert_bool(_has_legend([r])).is_true()
	assert_bool(Run.legendary_shown).is_true()
	# the Stranger (he draws evenly: until one comes)
	Run.legendary_shown = false
	var seen := false
	for k in range(200):
		if _has_legend([Run.stranger_offer()]):
			seen = true
			break
	assert_bool(seen).is_true()
	assert_bool(Run.legendary_shown).is_true()
	# a banish's redraw
	Run.legendary_shown = false
	var redraw := CardPool.level_up_offer(1, ["revolver"])
	assert_bool(_has_legend(redraw)).is_true()
	assert_bool(Run.legendary_shown).is_true()
	# a run starts with none shown
	_start()
	assert_bool(Run.legendary_shown).is_false()
