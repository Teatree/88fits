## Pass 149 (lead): the gems, the hard currency (Garry: "This currency is not earned ... I want this currency to be
## available there as a reward, just not used ... Same goes for using it as a price: for nodes in Trail, Revives, for
## Buying Outlaws, Outlaw Looks, etc."; "Gem wallet is only visible to Players when the Store option is turned on").
extends GdUnitTestSuite

var _store_was := false


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	_store_was = Settings.store_open
	Trail.load_from()
	Trail.refresh()


func after_test() -> void:
	Settings.store_open = _store_was
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()
	Trail.refresh()
	WantedBoard.config(true)


func test_the_gems_are_content_and_show_only_with_the_store_open() -> void:
	var g: CurrencyDef = Registry.currencies.get("gems")
	assert_object(g).is_not_null()
	assert_str(g.shown).is_equal("store")
	assert_str(Currency.word_of("gems")).is_equal("gems")
	assert_object(Currency.icon("gems")).is_not_null()
	Settings.store_open = false
	assert_bool(Currency.visible("gems")).is_false()
	assert_bool(Currency.visible("gold")).is_true()
	assert_array(Currency.wallets()).contains_exactly(["gold"])
	Settings.store_open = true
	assert_bool(Currency.visible("gems")).is_true()
	assert_array(Currency.wallets()).contains_exactly(["gold", "gems"])


func test_nothing_in_the_game_pays_or_charges_gems_today() -> void:
	# not earned: no poster pays gems, no Trail node, no outlaw and no skin costs gems (the hooks are there, unused)
	assert_str(WantedBoard.currency()).is_equal("gold")
	for t: Dictionary in (WantedBoard.config().get("tasks", []) as Array):
		assert_str(str(t.get("reward_currency", ""))).is_not_equal("gems")
	for n: Dictionary in Trail.nodes():
		assert_str(Trail.currency_of(str(n["id"]))).is_equal("gold")
	for c: CharacterDef in Registry.characters.values():
		assert_str(Currency.of(c.currency_type)).is_equal("gold")


func test_a_trail_node_can_be_priced_in_gems() -> void:
	var doc: Dictionary = Trail.read_file("res://tests/fixtures/trail_rules.json")
	var first := str((doc["nodes"] as Array)[0]["id"])
	(doc["nodes"] as Array)[0]["currency"] = "gems"
	Trail.load_data(doc)
	Save.data["trail"] = {"bought": [], "spent": 0, "had": []}
	Trail.refresh()
	assert_str(Trail.currency()).is_equal("gold")
	assert_str(Trail.currency_of(first)).is_equal("gems")
	var cost := Trail.price(first)
	assert_int(cost).is_greater(0)
	Save.data["gold"] = cost * 10
	assert_bool(Trail.can_buy(first)).is_false()
	Currency.add("gems", cost, "test")
	assert_bool(Trail.can_buy(first)).is_true()
	assert_bool(Trail.buy(first)).is_true()
	assert_int(Currency.balance("gems")).is_equal(0)
	assert_int(Save.gold()).is_equal(cost * 10)
	# the coins spent on the Trail stay coins; the gems are kept apart and paid back by the testing reset
	assert_int(Save.trail_spent()).is_equal(0)
	assert_int(int(Save.data["trail"]["spent_by"]["gems"])).is_equal(cost)
	Save.trail_reset()
	assert_int(Currency.balance("gems")).is_equal(cost)


func test_a_poster_task_can_pay_a_fixed_amount_of_gems() -> void:
	var cfg := WantedBoard.config().duplicate(true)
	for t: Dictionary in cfg["tasks"]:
		t["reward_currency"] = "gems"
		t["reward_fixed"] = 25
	var ctx := {"map": "red_canyon", "stage": 0, "stage_name": "Sundown", "P": 0, "beaten": false,
		"hero": {"id": "drifter", "name": "The Drifter", "start": "revolver"}, "boss": {}, "creatures": [], "gear": [],
		"elite_boss": [], "elite_estimate": 0, "weapons": [], "cards": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = 149
	var any := false
	for type: String in ["kill_total", "beat_stage", "hero_level", "open_chests", "collect_coins", "barrels", "boss_fast"]:
		var c := WantedBoard.make_contract(cfg, type, ctx, rng)
		if c.is_empty():
			continue
		any = true
		assert_str(WantedBoard.currency_of(c)).is_equal("gems")
		assert_int(int(c["reward"])).is_equal(25)
		# Coins x25 multiplies coins only
		assert_int(WantedBoard.reward_of(c)).is_equal(25)
	assert_bool(any).is_true()
	# a plain poster pays the board's currency
	assert_str(WantedBoard.currency_of({"reward": 100})).is_equal("gold")
