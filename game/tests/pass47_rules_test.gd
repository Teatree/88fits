## Pass 47, the rules lane (Garry's fifth list): lines and passive items told apart (fifteen lines, each with its
## evolution: Multishot, Field Notes, Haste and Deadeye made lines, Ducktape, Clover and Hot Sauce new; six new passive
## items), six weapon slots and six line slots all run and no cap on passive items, five rarity tiers, one weight
## formula for the cards and the chest (luck by tier, each level already held a little less likely), skips and banishes
## a stage's and the chest's too, the Mirror's Skip and Banish, Ironwood with the pike called the Spear and Brawn his
## favourite, the thrown spear hidden with its path, the damage numbers on again in a version 4 save, the new stats on
## the sheet with their names, Steady Hand's buckets and Barrel Rush's boost.
extends GdUnitTestSuite

## pass 70 (lane LINES): Lodestone, Mule Kick, Slow Burn and Tin Star new, Prospector and Gold Tooth made lines: 21
const LINES := ["brawn", "bristle", "clover", "deadeye", "ducktape", "energy_shield", "evade", "field_notes", "gold_tooth",
	"haste", "hot_sauce", "lodestone", "mend", "mule_kick", "multishot", "prospector", "slow_burn", "stride", "thirst",
	"tin_star", "vigour"]
const EVOLVED := {"brawn": "juggernaut", "bristle": "cactus_hide", "energy_shield": "aegis", "evade": "ghost_step",
	"mend": "second_wind", "stride": "roadrunner", "thirst": "bloodthirst", "vigour": "ironclad", "multishot": "barrage",
	"field_notes": "almanac", "haste": "quicksilver", "deadeye": "eagle_eye", "ducktape": "shackles",
	"clover": "golden_horseshoe", "hot_sauce": "ghost_pepper", "lodestone": "mother_lode", "mule_kick": "bucking_bronco",
	"slow_burn": "prairie_fire", "tin_star": "marshals_star", "prospector": "eureka", "gold_tooth": "gold_rush"}
## Garry's tiers as the lead revised them (pass 47: the WoW-green uncommon plate swallowed the green Reach and Venom icons)
const TIERS := {
	# pass 47b: nothing above rare yet (Garry); pass 48: Sinner's Greed epic, Reach, Venom and Big Game Hunter uncommon, and
	# the six new items (Phoenix Feather, Powder Keg and Loose Change uncommon, Skedaddle and Hot Streak rare, Gas Mask epic);
	# pass 62: the Pocket Watch uncommon; pass 69 (lane PAS): the Magnet epic, Counterpunch uncommon, Heavyweight rare, Snake
	# Oil, Hot Springs and Last Stand epic
	# pass 70: Prospector and Gold Tooth are lines now
	"common": ["cake", "beer", "barrel_rush", "pickpocket", "quickdraw", "cold_snap"],
	"uncommon": ["kindling", "siesta", "ricochet", "overkill", "adrenaline", "hush_money", "vulture", "reach", "venom", "big_game_hunter",
		"phoenix_feather", "powder_keg", "loose_change", "pocket_watch", "counterpunch"],
	"rare": ["steady_hand", "guillotine", "desperado", "brimstone_brand", "skedaddle", "hot_streak", "heavyweight"],
	"epic": ["sinners_greed", "gas_mask", "magnet", "snake_oil", "hot_springs", "last_stand"],
}
const NEW_ITEMS := ["barrel_rush", "beer", "siesta", "steady_hand", "prospector", "big_game_hunter"]
const SAVE_DIR := "user://test_saves/pass47_rules"


func before_test() -> void:
	# nothing unlocked, no Mirror ranks: the base numbers
	Save.data = Save._default()


func after_test() -> void:
	Run.arena = false
	Run.banished.clear()
	Run.player_sheet.remove_source("test")
	Run.end()


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _ids(list: Array) -> Array:
	return list.map(func(d: ContentDef) -> String: return d.id)


# ---------------------------------------------------------------- lines and passive items

func test_fifteen_lines_each_with_an_evolved_line() -> void:
	assert_array(_ids(Registry.sorted_lines())).is_equal(LINES)
	var lines := 0
	for p: PassiveDef in Registry.passives.values():
		if p.is_line():
			lines += 1
	# pass 70: 21 lines and their 21 evolutions
	assert_int(lines).is_equal(42)
	for id: String in LINES:
		var p: PassiveDef = Registry.passive(id)
		assert_bool(p.is_line()).override_failure_message(id + " is no line").is_true()
		assert_int(p.max_level).override_failure_message(id + " levels").is_equal(4)
		assert_str(p.evolves_into).is_equal(str(EVOLVED[id]))
		var evo: PassiveDef = Registry.passive(p.evolves_into)
		assert_object(evo).override_failure_message(id + " evolves into nothing").is_not_null()
		assert_bool(evo.is_line()).override_failure_message(evo.id + " is no line").is_true()
		assert_str(evo.evolves_from).is_equal(id)
		assert_bool(evo.is_evolved()).is_true()
		assert_int(evo.max_level).is_equal(1)
		assert_float(evo.weight).is_equal(0.0)
	# the passive items: no line among them, none evolves, each in Garry's tier
	var items := _ids(Registry.sorted_passives_only())
	var listed: Array = []
	for tier: String in TIERS.keys():
		for id: String in TIERS[tier]:
			listed.append(id)
			assert_str(Registry.passive(id).rarity).override_failure_message(id + " tier").is_equal(tier)
	listed.sort()
	assert_array(items).is_equal(listed)
	for id: String in items:
		var p: PassiveDef = Registry.passive(id)
		assert_bool(p.is_line()).is_false()
		assert_str(p.evolves_into).override_failure_message(id + " evolves").is_empty()
	for id: String in NEW_ITEMS:
		var p: PassiveDef = Registry.passive(id)
		# pass 70: Prospector became a line (four levels)
		assert_int(p.max_level).is_equal(4 if p.is_line() else 5)
		assert_float(p.weight).is_between(8.0, 10.0)
		assert_str(str(p.placeholder.get("color", ""))).is_not_empty()
	for p: PassiveDef in Registry.passives.values():
		assert_bool(ContentDef.RARITIES.has(p.rarity)).override_failure_message(p.id + " rarity " + p.rarity).is_true()
	assert_array(Registry.problems).is_empty()
	# the old listing keeps both
	assert_int(Registry.base_passives().size()).is_equal(LINES.size() + items.size())


func test_every_evolution_beats_its_maxed_source() -> void:
	# stat -> higher is better (cooldown: lower)
	var watch := {"multishot": {"amount": true}, "field_notes": {"xp_gain": true}, "haste": {"cooldown": false},
		"deadeye": {"crit_chance": true, "crit_damage": true}, "ducktape": {"debuff_duration": true},
		"clover": {"luck": true}, "hot_sauce": {"difficulty": true}, "brawn": {"might": true}}
	for id: String in watch.keys():
		_start()
		for k in range(4):
			assert_bool(Run.add_or_level_passive(id)).is_true()
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " past level 4").is_false()
		var maxed := {}
		for stat: String in watch[id].keys():
			maxed[stat] = Run.player_sheet.get_stat(stat, 0.0)
		assert_bool(Run.evolve_passive(id)).is_true()
		var stronger := false
		for stat: String in watch[id].keys():
			var now := Run.player_sheet.get_stat(stat, 0.0)
			var up: bool = watch[id][stat]
			# never worse on any stat it touches, better on at least one
			if up:
				assert_float(now).override_failure_message("%s's evolution lowers %s" % [id, stat]).is_greater_equal(float(maxed[stat]))
				stronger = stronger or now > float(maxed[stat]) + 0.001
			else:
				assert_float(now).override_failure_message("%s's evolution raises %s" % [id, stat]).is_less_equal(float(maxed[stat]))
				stronger = stronger or now < float(maxed[stat]) - 0.001
		assert_bool(stronger).override_failure_message(id + "'s evolution is no stronger").is_true()
		Run.end()
	# the numbers Garry was told: Multishot +4 then Barrage +6, Quicksilver 40% off the cooldowns
	_start()
	for k in range(4):
		Run.add_or_level_passive("multishot")
	assert_float(Run.player_sheet.get_stat("amount", 0.0)).is_equal_approx(4.0, 0.001)
	Run.evolve_passive("multishot")
	assert_float(Run.player_sheet.get_stat("amount", 0.0)).is_equal_approx(6.0, 0.001)
	_start()
	for k in range(4):
		Run.add_or_level_passive("haste")
	Run.evolve_passive("haste")
	assert_float(Run.player_sheet.get_stat("cooldown", 1.0)).is_equal_approx(0.6, 0.001)


func test_brawn_and_juggernaut_carry_no_debuff() -> void:
	for id in ["brawn", "juggernaut"]:
		var p: PassiveDef = Registry.passive(id)
		assert_str(p.trade).is_empty()
		for lv in p.levels:
			for e: Effect in lv:
				assert_str(e.stat).override_failure_message(id + " still slows").is_not_equal("move_speed")
	_start()
	var speed := Run.player_sheet.get_stat("move_speed", 0.0)
	for k in range(4):
		Run.add_or_level_passive("brawn")
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed, 0.0001)
	Run.evolve_passive("brawn")
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed, 0.0001)


# ---------------------------------------------------------------- six and six, static; passive items uncapped

func test_six_weapons_and_six_lines_all_run_and_passive_items_without_a_cap() -> void:
	_start()
	var tl: WaveTimeline = Run.map.timeline
	# JSON numbers come through as floats
	# five and five since pass 52 (Garry: "Reduce the number of Slots for Weapons and Line Items down to 5")
	assert_array(tl.weapon_cap.map(func(v) -> int: return int(v))).is_equal([5, 5, 5])
	assert_array(tl.passive_cap.map(func(v) -> int: return int(v))).is_equal([5, 5, 5])
	for s in [0, 1, 2, 5]:
		Run.stage = s
		assert_int(Run.weapon_cap()).is_equal(5)
		assert_int(Run.line_cap()).is_equal(5)
	Run.stage = 0
	assert_int(Run.MAX_LINES).is_equal(5)
	for id in ["peashooter", "boomstick", "tommy_gun", "hornet_nest", "orbit_saws"]:
		assert_object(Run.add_weapon(Registry.weapon(id), 1)).override_failure_message(id + " found no slot on stage 1").is_not_null()
	assert_object(Run.add_weapon(Registry.weapon("sabre"), 1)).is_null()
	# lines and passive items, mixed in the order taken
	var order := ["magnet", "brawn", "bristle", "reach", "mend", "stride", "kindling", "thirst"]
	for id in order:
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id).is_true()
	assert_array(Run.held_lines()).is_equal(["brawn", "bristle", "mend", "stride", "thirst"])
	assert_array(Run.held_passives()).is_equal(["magnet", "reach", "kindling"])
	# a sixth line finds no slot; passive items keep coming
	assert_bool(Run.add_or_level_passive("evade")).is_false()
	# pass 70: Prospector is a line now; Hush Money in its place
	for id in ["venom", "cake", "pickpocket", "beer", "siesta", "hush_money", "big_game_hunter", "barrel_rush", "overkill", "ricochet"]:
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " was capped").is_true()
	assert_int(Run.held_passives().size()).is_equal(13)
	# the cards keep it: no new line, new passive items still come
	var new_item := false
	for k in range(60):
		for c in CardPool.level_up_offer(4):
			if c["type"] == "passive" and bool(c["is_new"]):
				assert_bool((c["def"] as PassiveDef).is_line()).override_failure_message("a new line past five: " + str(c["id"])).is_false()
				new_item = true
	assert_bool(new_item).is_true()
	# an evolution keeps the slot
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("brawn")
	assert_bool(Run.evolve_passive("brawn")).is_true()
	assert_array(Run.held_lines()).is_equal(["juggernaut", "bristle", "mend", "stride", "thirst"])
	# the debug hand: not past five lines, passive items freely; the arena as many as it likes
	assert_int(Run.debug_set_item("passive", "evade", 1)).is_equal(0)
	assert_int(Run.debug_set_item("passive", "adrenaline", 2)).is_equal(2)
	Run.arena = true
	assert_int(Run.line_cap()).is_equal(99)
	assert_int(Run.weapon_cap()).is_equal(5)
	assert_int(Run.debug_set_item("passive", "evade", 1)).is_equal(1)
	assert_bool(Run.add_or_level_passive("ducktape")).is_true()
	assert_int(Run.held_lines().size()).is_equal(7)


func test_the_stranger_sells_rare_and_up_and_keeps_the_line_slots() -> void:
	_start()
	for id in ["brawn", "bristle", "mend", "stride", "thirst", "vigour"]:
		Run.add_or_level_passive(id)
	var item := false
	for k in range(300):
		var o := Run.stranger_offer()
		if o.is_empty():
			continue
		var def: ContentDef = o["def"]
		if o["type"] == "mutation":
			continue
		assert_bool(["rare", "epic", "legendary"].has(def.rarity)).override_failure_message("the Stranger sold %s (%s)" % [def.id, def.rarity]).is_true()
		assert_bool(CardPool.stage_open(def)).is_true()
		if o["type"] == "passive":
			var p := def as PassiveDef
			if bool(o["is_new"]):
				assert_bool(p.is_line()).override_failure_message("a new line past five from the Stranger").is_false()
				item = true
	assert_bool(item).is_true()


# ---------------------------------------------------------------- the weights

func test_rarity_tiers_and_luck() -> void:
	_start()
	assert_dict(CardPool.RARITY_W).is_equal({"common": 1.0, "uncommon": 0.75, "rare": 0.55, "epic": 0.3, "legendary": 0.15})
	assert_dict(CardPool.LUCK_TIER).is_equal({"common": 0.0, "uncommon": 0.5, "rare": 1.0, "epic": 1.5, "legendary": 2.0})
	assert_float(CardPool.LEVEL_DECAY).is_equal_approx(0.88, 0.0001)
	for tier: String in TIERS.keys():
		var def: PassiveDef = Registry.passive(TIERS[tier][0])
		assert_float(CardPool.weight_of(def, 0)).is_equal_approx(def.weight * float(CardPool.RARITY_W[tier]), 0.0001)
	# luck lifts the higher tiers by their share: Clover maxed (0.4) is x1.2 on uncommon, x1.8 on legendary
	Run.player_sheet.add_effects([Effect.make("luck", "add", 0.4, "player")], "test")
	var siesta: PassiveDef = Registry.passive("siesta")
	var greed: PassiveDef = Registry.passive("sinners_greed")
	var cake: PassiveDef = Registry.passive("cake")
	assert_float(CardPool.weight_of(siesta, 0)).is_equal_approx(siesta.weight * 0.75 * 1.2, 0.0001)
	# pass 48: Sinner's Greed is epic (x0.3, and luck lifts epic by 1.5 x 0.4)
	assert_float(CardPool.weight_of(greed, 0)).is_equal_approx(greed.weight * 0.3 * 1.6, 0.0001)
	assert_float(CardPool.weight_of(cake, 0)).is_equal_approx(cake.weight * 1.0, 0.0001)
	assert_float(CardPool.luck_boost("epic")).is_equal_approx(1.6, 0.0001)
	Run.player_sheet.remove_source("test")
	# Clover's own numbers reach the sheet
	for k in range(4):
		Run.add_or_level_passive("clover")
	assert_float(Run.player_sheet.get_stat("luck", 0.0)).is_equal_approx(0.4, 0.0001)
	Run.evolve_passive("clover")
	assert_float(Run.player_sheet.get_stat("luck", 0.0)).is_equal_approx(0.6, 0.0001)
	assert_str(TextGen.rarity_name("uncommon")).is_equal("Uncommon")
	assert_str(TextGen.rarity_name("legendary")).is_equal("Legendary")


func test_each_level_held_is_a_little_less_likely() -> void:
	_start()
	var pea: WeaponDef = Registry.weapon("peashooter")
	var base := CardPool.weight_of(pea, 0)
	assert_float(CardPool.weight_of(pea, 1)).is_equal_approx(base * 1.5, 0.0001)
	assert_float(CardPool.weight_of(pea, 2)).is_equal_approx(base * 1.5 * 0.88, 0.0001)
	assert_float(CardPool.weight_of(pea, 5)).is_equal_approx(base * 1.5 * pow(0.88, 4), 0.0001)
	assert_float(CardPool.weight_of(pea, 3, true)).is_equal_approx(base * 1.5 * 0.88 * 0.88 * 3.0, 0.0001)
	# the cards carry it: a level-3 weapon, a level-2 line and a maxed line's evolution
	Run.add_weapon(pea, 3)
	Run.add_or_level_passive("mend")
	Run.add_or_level_passive("mend")
	for k in range(4):
		Run.add_or_level_passive("stride")
	var seen := {}
	for k in range(200):
		for c in CardPool.level_up_offer(4):
			seen[str(c["id"])] = c
	assert_float(float(seen["peashooter"]["weight"])).is_equal_approx(CardPool.weight_of(pea, 3), 0.0001)
	assert_float(float(seen["mend"]["weight"])).is_equal_approx(CardPool.weight_of(Registry.passive("mend"), 2), 0.0001)
	var evo: Dictionary = seen["roadrunner"]
	assert_bool(bool(evo["evolve"])).is_true()
	assert_float(float(evo["weight"])).is_equal_approx(CardPool.weight_of(Registry.passive("stride"), 4, true), 0.0001)


func test_the_chest_draws_by_the_same_weights() -> void:
	_start()
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	for k in range(3):
		Run.add_or_level_passive("brawn")
	# a small pool: the two held items and three passive items of three tiers, everything else banished
	var keep := ["cake", "siesta", "steady_hand"]
	for p: PassiveDef in Registry.unlocked_passives():
		if not p.is_line() and not keep.has(p.id):
			Run.banished.append(p.id)
	var cands := Run.chest_candidates()
	var want := {}
	var total := 0.0
	for c: Dictionary in cands:
		want[str(c["id"])] = float(c["weight"])
		total += float(c["weight"])
	assert_array(want.keys()).contains_exactly_in_any_order(["peashooter", "brawn", "cake", "siesta", "steady_hand"])
	assert_float(float(want["peashooter"])).is_equal_approx(CardPool.weight_of(Registry.weapon("peashooter"), 2), 0.0001)
	assert_float(float(want["brawn"])).is_equal_approx(CardPool.weight_of(Registry.passive("brawn"), 3), 0.0001)
	# a new item weighs CHEST_NEW_MULT of its card weight in a chest (integration: about two fifths of an early chest)
	assert_float(float(want["steady_hand"])).is_equal_approx(CardPool.weight_of(Registry.passive("steady_hand"), 0) * Run.CHEST_NEW_MULT, 0.0001)
	for c: Dictionary in cands:
		if str(c["id"]) in keep:
			assert_bool(bool(c["is_new"])).is_true()
			assert_int(int(c["level_to"])).is_equal(1)
	# drawn in proportion (seeded)
	seed(4747)
	var n := 6000
	var got := {}
	for k in range(n):
		var r := Run.chest_roll()
		got[str(r["id"])] = int(got.get(str(r["id"]), 0)) + 1
	for id: String in want.keys():
		var p: float = float(want[id]) / total
		var sd := sqrt(n * p * (1.0 - p))
		assert_float(float(got.get(id, 0))).override_failure_message("%s drawn %d times, %.0f expected" % [id, int(got.get(id, 0)), n * p]).is_between(n * p - 4.0 * sd, n * p + 4.0 * sd)
	# luck moves the share to the rarer ones
	Run.player_sheet.add_effects([Effect.make("luck", "add", 1.0, "player")], "test")
	var lucky := 0.0
	var lucky_total := 0.0
	for c: Dictionary in Run.chest_candidates():
		lucky_total += float(c["weight"])
		if str(c["id"]) == "steady_hand":
			lucky = float(c["weight"])
	assert_float(lucky / lucky_total).is_greater(float(want["steady_hand"]) / total)
	Run.player_sheet.remove_source("test")
	# a passive item taken from the chest arrives at level 1, its next chest is a level of it
	var r2 := {"type": "passive", "id": "siesta", "def": Registry.passive("siesta"), "level_from": 0, "level_to": 1, "is_new": true}
	assert_str(Run.chest_take(r2)).is_equal("Siesta Lv 1")
	assert_int(Run.passive_level("siesta")).is_equal(1)
	for c: Dictionary in Run.chest_candidates():
		if str(c["id"]) == "siesta":
			assert_bool(bool(c["is_new"])).is_false()
	# never a new line in a chest
	Run.banished.clear()
	for c: Dictionary in Run.chest_candidates():
		if bool(c["is_new"]):
			assert_bool((c["def"] as PassiveDef).is_line()).is_false()
	# nothing left: gold
	Run.weapons.clear()
	Run.passives.clear()
	for p: PassiveDef in Registry.passives.values():
		Run.banished.append(p.id)
	assert_str(str(Run.chest_roll()["type"])).is_equal("gold")


func test_an_evolution_still_comes_first_and_a_boss_chest_holds_a_path() -> void:
	_start()
	var w := Run.add_weapon(Registry.weapon("boomstick"), 5)
	# pass 48: the whole path (Dragon's Breath, the lane Birdshot, Both Barrels), one a stage
	Run.add_mutation("dragons_breath")
	Run.stage = 1
	Run.add_mutation("birdshot_lane")
	assert_bool(Run.evolution_ready(w)).is_false()
	Run.stage = 2
	Run.add_mutation("both_barrels")
	assert_bool(Run.evolution_ready(w)).is_true()
	assert_str(str(Run.chest_roll()["type"])).is_equal("evolution")
	Run.add_weapon(Registry.weapon("hornet_nest"), 2)
	assert_str(str(Run.chest_roll(true)["type"])).is_equal("mutation")


# ---------------------------------------------------------------- skips and banishes, a stage's

func test_skips_and_banishes_refill_every_stage_and_rerolls_do_not() -> void:
	assert_float(float(StatSheet.PLAYER_DEFAULTS["skips"])).is_equal(2.0)
	assert_float(float(StatSheet.PLAYER_DEFAULTS["banishes"])).is_equal(1.0)
	_start()
	assert_int(Run.skips_left).is_equal(2)
	assert_int(Run.banishes_left).is_equal(1)
	assert_int(Run.rerolls_left).is_equal(1)
	assert_bool(Run.use_skip()).is_true()
	assert_bool(Run.use_skip()).is_true()
	assert_bool(Run.use_skip()).is_false()
	assert_int(Run.skips_left).is_equal(0)
	assert_bool(Run.use_banish()).is_true()
	assert_bool(Run.use_banish()).is_false()
	Run.rerolls_left = 0
	# the same stage again refills nothing; a new one refills both, never the rerolls
	Run.stage = 0
	assert_int(Run.skips_left).is_equal(0)
	Run.stage = 1
	assert_int(Run.skips_left).is_equal(2)
	assert_int(Run.banishes_left).is_equal(1)
	assert_int(Run.rerolls_left).is_equal(0)
	# a skip pays nothing now (the gold for skipping is gone)
	assert_bool(Run.has_method("skip_gold")).is_false()
	# the Mirror: Skip and Banish ranks
	Save.data["talents"] = {"nerve": {"form": 0, "rank": 2}, "choice": {"form": 1, "rank": 1}}
	_start()
	assert_int(Run.skips_left).is_equal(4)
	assert_int(Run.banishes_left).is_equal(2)
	Run.use_skip()
	Run.stage = 1
	assert_int(Run.skips_left).is_equal(4)
	Save.data["talents"] = {}


func test_a_chest_takes_a_skip_or_a_banish() -> void:
	_start()
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	Run.add_or_level_passive("brawn")
	var gold := Run.run_gold
	var chests := Run.chests_opened
	var r := Run.chest_roll()
	assert_str(Run.chest_skip(r)).is_equal("Chest skipped")
	assert_int(Run.skips_left).is_equal(1)
	assert_int(Run.run_gold).is_equal(gold)
	assert_int(Run.chests_opened).is_equal(chests + 1)
	assert_int(Run.weapon_instance("peashooter").level).is_equal(2)
	assert_int(Run.passive_level("brawn")).is_equal(1)
	Run.chest_skip(Run.chest_roll())
	# none left: nothing spent, nothing counted
	assert_str(Run.chest_skip(Run.chest_roll())).is_empty()
	assert_int(Run.chests_opened).is_equal(chests + 2)
	# pass 58 (Garry: "Banish option should not allow Banishing items that Player already has"): a level of the held
	# Peashooter is refused, nothing spent
	var held_roll := {"type": "weapon", "id": "peashooter", "def": Registry.weapon("peashooter"), "level_from": 2, "level_to": 3, "is_new": false}
	assert_bool(Run.chest_banish(held_roll).is_empty()).is_true()
	assert_int(Run.banishes_left).is_equal(1)
	assert_bool(Run.banished.has("peashooter")).is_false()
	# a banish of a new item: the id is out of the run and a new roll comes back
	var r2 := {}
	for k in range(200):
		var r3 := Run.chest_roll()
		if Run.can_banish_card(r3):
			r2 = r3
			break
	assert_bool(r2.is_empty()).is_false()
	var again := Run.chest_banish(r2)
	assert_bool(Run.banished.has(str(r2["id"]))).is_true()
	assert_int(Run.banishes_left).is_equal(0)
	assert_bool(again.is_empty()).is_false()
	assert_str(str(again["id"])).is_not_equal(str(r2["id"]))
	for k in range(100):
		assert_str(str(Run.chest_roll()["id"])).is_not_equal(str(r2["id"]))
	# none left, or a purse of gold: nothing happens
	assert_bool(Run.chest_banish(Run.chest_roll()).is_empty()).is_true()
	Run.banishes_left = 1
	assert_bool(Run.chest_banish({"type": "gold", "id": "", "gold": 50}).is_empty()).is_true()
	assert_int(Run.banishes_left).is_equal(1)
	# pass 58: an evolution is never banished (it grows out of a weapon the hero has): refused, nothing spent, the weapon
	# still ready to evolve (pass 47 banished it and kept the weapon as it was for the run)
	Run.stage = 0
	var w := Run.add_weapon(Registry.weapon("boomstick"), 5)
	# pass 48: every mutation of the path
	Run.add_mutation("dragons_breath")
	Run.stage = 1
	Run.add_mutation("birdshot_lane")
	Run.stage = 2
	Run.add_mutation("both_barrels")
	var evo := Run.chest_roll()
	assert_str(str(evo["type"])).is_equal("evolution")
	var left := Run.banishes_left
	assert_bool(Run.chest_banish(evo).is_empty()).is_true()
	assert_int(Run.banishes_left).is_equal(left)
	assert_bool(Run.banished.has(str(evo["id"]))).is_false()
	assert_bool(Run.evolution_ready(w)).is_true()


func test_the_mirror_says_skip_and_banish_a_stage() -> void:
	var nerve: TalentDef = Registry.talent("nerve")
	var choice: TalentDef = Registry.talent("choice")
	assert_str(nerve.form_name(0)).is_equal("Skip")
	assert_str(nerve.form_text(0)).is_equal("+1 skip a stage, a rank.")
	assert_str(choice.form_name(1)).is_equal("Banish")
	assert_str(choice.form_text(1)).is_equal("+1 banish a stage, a rank.")
	assert_str(choice.form_text(0)).is_equal("+1 reroll a run, a rank.")
	assert_str((nerve.effects_for(0, 1)[0] as Effect).stat).is_equal("skips")
	assert_str((choice.effects_for(1, 1)[0] as Effect).stat).is_equal("banishes")
	assert_str(TextGen.describe_effect(Effect.make("skips", "add", 1.0, "player"))).is_equal("+1 skip")
	assert_str(TextGen.describe_effect(Effect.make("banishes", "add", 3.0, "player"))).is_equal("+3 banishes")


# ---------------------------------------------------------------- Ironwood, the Spear and the Throwing Spear

func test_ironwood_lands_with_the_pike_called_the_spear() -> void:
	var iw: CharacterDef = Registry.character("ironwood")
	var pike: WeaponDef = Registry.weapon("pike")
	assert_str(iw.start_weapon).is_equal("pike")
	assert_object(Registry.start_weapon_for(iw)).is_same(pike)
	assert_str(pike.display_name).is_equal("Spear")
	assert_str(pike.hero).is_empty()
	assert_str(pike.behavior).is_equal("Thruster")
	# his favourite: Brawn, the attack-damage line, at level 2 the moment he finds it (a "max" bonus would hand him a
	# maxed line and its evolution card at the first pick)
	assert_str(iw.favourite_passive).is_equal("brawn")
	assert_str(str(iw.favourite_passive_bonus.get("type", ""))).is_equal("level")
	assert_int(int(iw.favourite_passive_bonus.get("value", 0))).is_equal(2)
	assert_bool(Registry.passive(iw.favourite_passive).is_line()).is_true()
	# re-pinned in pass 61: the trait's words are his regen rule alone; Brawn is named on the title plaque and in the
	# hero's sheet (the favourite's plate), never in the trait
	assert_str(iw.trait_text).not_contains("Cake")
	assert_str(iw.trait_text).contains("regen")
	assert_array(Registry.problems).is_empty()
	_start("ironwood")
	var brawn: PassiveDef = Registry.passive("brawn")
	assert_bool(Run.is_favourite(brawn)).is_true()
	assert_int(Run.first_passive_level(brawn)).is_equal(2)
	assert_bool(Run.add_or_level_passive("brawn")).is_true()
	assert_int(Run.passive_level("brawn")).is_equal(2)
	# the pike behind its quest: he still holds it, and the level-ups still level it
	assert_bool(Registry.is_unlocked("weapon", "pike")).is_false()
	var inst := Run.add_weapon(Registry.start_weapon_for(Run.character), 1)
	assert_str(inst.def.id).is_equal("pike")
	assert_bool(Registry.unlocked_weapons().has(pike)).is_false()
	assert_bool(CardPool.offer_weapons().has(pike)).is_true()
	var levelled := false
	for k in range(300):
		for c in CardPool.level_up_offer(4):
			if str(c["id"]) == "pike":
				levelled = true
				assert_int(int(c["level_from"])).is_equal(1)
	assert_bool(levelled).override_failure_message("the locked pike in his hands never levelled").is_true()
	# anyone else finds Brawn at level 1
	_start("astro")
	assert_int(Run.first_passive_level(brawn)).is_equal(1)


func test_the_spear_name_reaches_every_word_the_player_reads() -> void:
	var said: Array = [Registry.weapon("pike").display_name, Registry.weapon("pike").flavour,
		Registry.weapon("thunder_lance").display_name, Registry.weapon("thunder_lance").flavour, Registry.quests["unlock_pike"].display_name,   # pass 53 (lane W2): the Halberd is hidden, the Thunder Lance evolves the Spear
		TextGen.quest_text(Registry.quests["unlock_pike"])]
	for m: MutationDef in Registry.mutations_of("pike"):
		said.append_array([m.display_name, m.flavour, m.text, m.vfx])
	for s: String in said:
		assert_bool(s.to_lower().contains("pike")).override_failure_message("still says pike: " + s).is_false()
	assert_str(Registry.mutation("phalanx").text).is_equal("Three spears fanned, −35% damage.")
	assert_str(Registry.quests["unlock_pike"].display_name).is_equal("Spear")


func test_the_throwing_spear_is_out_of_the_game_with_its_path() -> void:
	var spear: WeaponDef = Registry.weapon("spear")
	assert_str(spear.display_name).is_equal("Throwing Spear")
	assert_bool(spear.hidden).is_true()
	assert_bool(Registry.is_hidden(spear)).is_true()
	assert_bool(Registry.is_hidden(Registry.weapon("war_lance"))).is_true()
	for id in ["fire_hardened", "spear_volley", "pinning_throw"]:
		assert_bool(Registry.is_hidden(Registry.mutation(id))).override_failure_message(id + " shows").is_true()
	assert_bool(Registry.is_hidden(Registry.weapon("pike"))).is_false()
	assert_bool(Registry.is_hidden(Registry.weapon("thunder_lance"))).is_false()   # pass 53 (lane W2)
	# never offered, never his start, never his special, never a hero option, never a quest
	for hero in ["ironwood", "astro", "drifter", "calavera"]:
		_start(hero)
		assert_bool(_ids(Registry.unlocked_weapons()).has("spear")).is_false()
		assert_object(Registry.start_weapon_for(Run.character)).is_not_same(spear)
		for k in range(40):
			for c in CardPool.level_up_offer(4):
				assert_bool(["spear", "war_lance", "fire_hardened", "spear_volley", "pinning_throw"].has(str(c["id"]))).is_false()
		for m: MutationDef in Registry.hero_mutations(hero):
			assert_str(m.weapon).is_not_equal("spear")
		Run.end()
	assert_array(Registry.weapon_hero_mutations("spear")).is_empty()
	for q: QuestDef in Registry.quests.values():
		if Registry.quest_visible(q):
			assert_bool(["spear", "war_lance"].has(str(q.unlocks.get("id", "")))).is_false()
	var own: Array = Registry.weapons.values().filter(func(w: WeaponDef) -> bool:
		return w.hero == "ironwood" and not w.is_evolution and not Registry.is_hidden(w))
	assert_array(own).is_empty()


# ---------------------------------------------------------------- the save

func _clear_dir() -> void:
	if DirAccess.dir_exists_absolute(SAVE_DIR):
		for f in DirAccess.get_files_at(SAVE_DIR):
			DirAccess.remove_absolute(SAVE_DIR.path_join(f))


func _write(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(Save.path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_a_version_3_save_turns_the_damage_numbers_on_once() -> void:
	var dir_before := Save.dir
	var settings_before := Settings.to_dict()
	Save.flush()
	Save.dir = SAVE_DIR
	_clear_dir()
	assert_int(Save.VERSION).is_equal(5)   # 5 since pass 53 (the live menu by default)
	_write(JSON.stringify({"version": 3, "gold": 5, "once": ["seen_migrated"],
		"settings": {"damage_numbers": false, "sfx_volume": 0.4}, "seen": {"passive": ["brawn"]}}))
	Save.load_save()
	assert_int(int(Save.data["version"])).is_equal(Save.VERSION)
	assert_bool(Settings.damage_numbers).is_true()
	assert_bool(bool(Save.data["settings"]["damage_numbers"])).is_true()
	assert_float(Settings.sfx_volume).is_equal_approx(0.4, 0.0001)
	assert_int(Save.gold()).is_equal(5)
	assert_bool(Save._dirty).is_true()
	# a line is met as a passive, whichever name a reader asks by
	assert_bool(Save.seen("passive", "brawn")).is_true()
	assert_bool(Save.seen("line", "brawn")).is_true()
	Save.mark_seen("line", "clover")
	assert_bool(Save.seen("passive", "clover")).is_true()
	assert_bool((Save.data["seen"] as Dictionary).has("line")).is_false()
	# once: the player's own switch sticks after it
	Settings.damage_numbers = false
	Save.save_now()
	Save.load_save()
	assert_bool(Settings.damage_numbers).is_false()
	# a version 2 save steps through 3 to 4; one without settings gets them
	_write(JSON.stringify({"version": 2, "seen": {"line": ["mend"]}}))
	Save.load_save()
	assert_int(int(Save.data["version"])).is_equal(Save.VERSION)
	assert_bool(Save.seen("passive", "mend")).is_true()
	assert_bool(Settings.damage_numbers).is_true()
	_clear_dir()
	Save.dir = dir_before
	Save.data = Save._default()
	Save._dirty = false
	Settings.from_dict(settings_before)


# ---------------------------------------------------------------- the new stats

func test_the_new_stats_have_defaults_and_names() -> void:
	var want := {"debuff_duration": 1.0, "difficulty": 0.0, "still_regen": 0.0, "still_might": 0.0, "barrel_speed": 0.0,
		"barrel_seconds": 0.0, "xp_drop_chance": 0.0, "elite_damage": 0.0, "luck": 0.0}
	for stat: String in want.keys():
		assert_float(float(StatSheet.PLAYER_DEFAULTS[stat])).override_failure_message(stat).is_equal(float(want[stat]))
		assert_bool(TextGen.STATS.has(stat)).override_failure_message(stat + " has no name").is_true()
	var said := {
		Effect.make("debuff_duration", "mul", 0.15, "player"): "+15% debuff duration",
		Effect.make("difficulty", "add", 0.25, "player"): "+25% difficulty",
		Effect.make("still_regen", "add", 1.0, "player"): "+1 regen per second standing still",
		Effect.make("still_might", "add", 0.1, "player"): "+10% attack damage per second standing still",
		Effect.make("barrel_speed", "add", 0.25, "player"): "+25% move speed after a barrel",
		Effect.make("barrel_seconds", "add", 0.75, "player"): "+0.75 s barrel boost",
		Effect.make("xp_drop_chance", "add", 0.06, "player"): "+6% extra XP gem chance",
		Effect.make("elite_damage", "add", 0.15, "player"): "+15% damage to Elites and bosses",
		Effect.make("luck", "add", 0.1, "player"): "+10% luck",
		Effect.make("regen", "add", 0.45, "player"): "+0.45 regen per second",
	}
	for e: Effect in said.keys():
		assert_str(TextGen.describe_effect(e)).is_equal(str(said[e]))
	# each new item's numbers reach the sheet
	_start()
	var at := {"ducktape": ["debuff_duration", 1.15], "hot_sauce": ["difficulty", 0.25], "siesta": ["still_regen", 1.0],
		"steady_hand": ["still_might", 0.1], "barrel_rush": ["barrel_speed", 0.25], "prospector": ["xp_drop_chance", 0.06],
		"big_game_hunter": ["elite_damage", 0.15]}
	for id: String in at.keys():
		Run.add_or_level_passive(id)
		assert_float(Run.player_sheet.get_stat(str(at[id][0]), 0.0)).override_failure_message(id).is_equal_approx(float(at[id][1]), 0.0001)
	assert_float(Run.player_sheet.get_stat("barrel_seconds", 0.0)).is_equal_approx(3.0, 0.0001)
	for k in range(4):
		Run.add_or_level_passive("barrel_rush")
		Run.add_or_level_passive("steady_hand")
	assert_float(Run.player_sheet.get_stat("barrel_speed", 0.0)).is_equal_approx(0.65, 0.0001)
	assert_float(Run.player_sheet.get_stat("barrel_seconds", 0.0)).is_equal_approx(6.0, 0.0001)
	assert_float(Run.player_sheet.get_stat("still_might", 0.0)).is_equal_approx(0.3, 0.0001)
	# Beer: more attack damage, less health
	var hp := Run.player_sheet.get_stat("max_hp", 100.0)
	var might := Run.player_sheet.get_stat("might", 1.0)
	Run.add_or_level_passive("beer")
	assert_float(Run.player_sheet.get_stat("max_hp", 100.0)).is_equal_approx(hp * 0.95, 0.001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(might * 1.12, 0.001)
	# gold_gained says what came in, after greed, and only when something did
	var got: Array = []
	var cb := func(a: int) -> void: got.append(a)
	Run.gold_gained.connect(cb)
	Run.add_gold(10)
	Run.add_gold(0)
	Run.gold_gained.disconnect(cb)
	assert_array(got).is_equal([int(round(10 * Run.player_sheet.get_stat("greed", 1.0)))])


func test_the_new_items_read_well() -> void:
	# printed for the eye (the test log), checked for the words they must and must not say
	var ids: Array = NEW_ITEMS.duplicate()
	for id in ["ducktape", "clover", "hot_sauce", "multishot", "field_notes", "haste", "deadeye", "brawn"]:
		ids.append(id)
		ids.append(str(EVOLVED[id]))
	for id: String in ids:
		var p: PassiveDef = Registry.passive(id)
		var lines: Array = [p.text, TextGen.passive_description(p, 1), TextGen.passive_description(p, p.max_level),
			TextGen.next_level_text(p, 1), TextGen.next_level_text(p, p.max_level)]
		print("pass47 text  %-16s | %s" % [p.display_name, " | ".join(lines)])
		for s: String in lines:
			assert_bool(s.to_lower().contains("rank")).override_failure_message(id + " says rank: " + s).is_false()
			assert_bool(s.contains("_")).override_failure_message(id + " shows a raw stat: " + s).is_false()
			assert_bool(s.contains("0.8 s")).override_failure_message(id + " rounds 0.75 s: " + s).is_false()
		assert_str(p.flavour).is_not_empty()
	assert_str(TextGen.passive_description(Registry.passive("barrel_rush"), 1)).is_equal(
		"+25% move speed after a barrel, +3 s barrel boost at level 1, then +10% move speed after a barrel, +0.75 s barrel boost a level.")
	assert_str(TextGen.passive_description(Registry.passive("barrel_rush"), 3)).ends_with("Level 3: +45% move speed after a barrel, +4.5 s barrel boost total.")
	assert_str(TextGen.passive_description(Registry.passive("barrage"), 1)).is_equal("+6 projectiles.")
	assert_str(TextGen.passive_description(Registry.passive("ducktape"), 2)).is_equal("+15% debuff duration per level. Level 2: +32% debuff duration total.")
	# the new lines explain what their stat does on the card
	for id in ["ducktape", "clover", "hot_sauce"]:
		assert_str(Registry.passive(id).text).is_not_empty()
	# each new icon is painted later: the art prompt is in the JSON for the painter
	for id: String in NEW_ITEMS + ["ducktape", "clover", "hot_sauce", "barrage", "almanac", "quicksilver", "eagle_eye",
			"shackles", "golden_horseshoe", "ghost_pepper"]:
		var d := JsonContent.load_json("res://content/passives/%s/%s.json" % [id, id])
		assert_str(str(d.get("art_prompt", ""))).override_failure_message(id + " has no art prompt").is_not_empty()


# ---------------------------------------------------------------- Steady Hand and Barrel Rush

func test_steady_hand_folds_in_five_percent_buckets_up_to_double() -> void:
	_start()
	var base := Run.player_sheet.get_stat("might", 1.0)
	# without it standing still is nothing
	Run.note_still(10.0)
	assert_int(Run.steady_bucket).is_equal(0)
	assert_bool(Run._steady_dirty).is_false()
	assert_float(Run.still_seconds).is_equal(10.0)
	Run.note_still(0.0)
	Run.add_or_level_passive("steady_hand")
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base, 0.0001)
	# 2.3 s at 10% a second: 23%, folded as 20%
	Run.note_still(2.3)
	assert_int(Run.steady_bucket).is_equal(4)
	assert_float(Run.steady_might()).is_equal_approx(0.2, 0.0001)
	assert_bool(Run._steady_dirty).is_true()
	Run._desperado_built_ms = -100000
	Run.tick_timed()
	assert_bool(Run._steady_dirty).is_false()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 1.2, 0.0001)
	var named := false
	for r in Run.player_sheet.breakdown("might"):
		if str(r["source"]) == "Steady Hand +20%":
			named = true
	assert_bool(named).is_true()
	# a little longer in the same bucket: nothing to rebuild
	Run.note_still(2.45)
	assert_bool(Run._steady_dirty).is_false()
	# up to +100% at most, however long he stands
	Run.note_still(60.0)
	assert_int(Run.steady_bucket).is_equal(20)
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 2.0, 0.0001)
	# a rebuild for any other reason keeps it
	Run.add_or_level_passive("magnet")
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 2.0, 0.0001)
	# moving drops it
	Run.note_still(0.0)
	assert_bool(Run._steady_dirty).is_true()
	Run._desperado_built_ms = -100000
	Run.tick_timed()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base, 0.0001)
	assert_float(Run.steady_might()).is_equal(0.0)
	# level 5: 30% a second, the cap in 3.4 s
	for k in range(4):
		Run.add_or_level_passive("steady_hand")
	Run.note_still(3.4)
	assert_int(Run.steady_bucket).is_equal(20)
	Run.note_still(1.0)
	assert_int(Run.steady_bucket).is_equal(6)


func test_barrel_rush_runs_faster_for_a_while_after_a_barrel() -> void:
	_start()
	var speed := Run.player_sheet.get_stat("move_speed", 0.0)
	assert_bool(Run.barrel_rush()).is_false()
	assert_float(Run.boost_left(Run.BARREL_RUSH)).is_equal(0.0)
	Run.add_or_level_passive("barrel_rush")
	assert_bool(Run.barrel_rush()).is_true()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.25, 0.0001)
	assert_float(Run.boost_left("barrel_rush")).is_equal_approx(3.0, 0.0001)
	Run.elapsed += 1.0
	assert_float(Run.boost_left("barrel_rush")).is_equal_approx(2.0, 0.0001)
	# another barrel starts the clock again, the speed not stacked
	assert_bool(Run.barrel_rush()).is_true()
	assert_float(Run.boost_left("barrel_rush")).is_equal_approx(3.0, 0.0001)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.25, 0.0001)
	# two levels later: faster and longer
	Run.add_or_level_passive("barrel_rush")
	Run.add_or_level_passive("barrel_rush")
	assert_bool(Run.barrel_rush()).is_true()
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed * 1.45, 0.0001)
	assert_float(Run.boost_left("barrel_rush")).is_equal_approx(4.5, 0.0001)
	assert_int(Run.timed.filter(func(t: Dictionary) -> bool: return t["id"] == "barrel_rush").size()).is_equal(1)
	# it runs out quietly (no "wore off" toast) and the speed is back
	Run.elapsed += 5.0
	assert_array(Run.tick_timed()).is_empty()
	assert_float(Run.boost_left("barrel_rush")).is_equal(0.0)
	assert_float(Run.player_sheet.get_stat("move_speed", 0.0)).is_equal_approx(speed, 0.0001)
	# a loud buff still says it wore off
	Run.add_timed_effects("t47", "Test Buff", [Effect.make("might", "mul", 0.1, "player")], 1.0)
	Run.elapsed += 2.0
	assert_array(Run.tick_timed()).is_equal(["Test Buff"])
