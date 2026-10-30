## Pass 111, lane SKINS (Garry: "Skins ... first you complete a goal, then you get access to buying skins ... choice of
## currency ... get everything ready for the currency selection functionality in every place where it matters"): a hero's
## look marked `skin.purchasable` is locked until its goal (a quest whose unlocks is {type skin, id hero:CODE}) is done,
## then bought for its price in its currency (Save.buy_skin through Currency), then worn (Save.set_skin_worn), which is
## the look he is played in (Registry.played_look) unless the arena keeps another; the look the game plays is every
## player's; old saves read as having bought none; every meta price (heroes, talents, skins) is paid through Currency and
## shows its currency's icon; the new goal beat_stage {map, stage, hero}; the hero sheet's Looks tiles.
extends GdUnitTestSuite

const Sheet := preload("res://ui/wanted/WHeroSheet.gd")

## the fixture: a hero with a look sold for `PRICE` behind a test quest
const HERO := "may"
const PRICE := 700
const QID := "p111_test_skin"

var _keep_variants: Dictionary = {}
var _keep_currencies: Dictionary = {}


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	var c := _hero()
	_keep_variants = c.variants.duplicate(true)
	_keep_currencies = Registry.currencies.duplicate()


func after_test() -> void:
	var c := _hero()
	c.variants = _keep_variants
	Registry.currencies = _keep_currencies
	Registry.quests.erase(QID)
	Run.arena = false
	Run.end()
	Run.stage_beaten = false
	Save.data = Save._default()
	Save._dirty = false


func _hero() -> CharacterDef:
	var c: CharacterDef = Registry.character(HERO)
	assert_object(c).is_not_null()
	return c


## A look of the hero other than the one he plays, sold for PRICE in `cur` behind the test quest (when `gated`).
func _sell(cur: String = "gold", gated: bool = true, price: int = PRICE) -> String:
	var c := _hero()
	# a look the content does not sell (so no goal of the content's names it)
	var code := ""
	for k in c.variant_codes():
		if str(k) != c.home_look() and not c.sells_skin(str(k)) and Registry.skin_quest(c, str(k)) == null:
			code = str(k)
			break
	assert_str(code).is_not_empty()
	var e: Dictionary = (c.variants[code] as Dictionary).duplicate(true)
	e["shelved"] = false
	e["skin"] = {"purchasable": true, "name": "Test Look", "price": price, "currency_type": cur, "unlock_quest": QID if gated else ""}
	c.variants[code] = e
	if gated:
		var q := QuestDef.new()
		q.id = QID
		q.condition = {"type": "runs_total", "count": 3}
		q.unlocks = {"type": "skin", "id": Registry.skin_key(c.id, code)}
		Registry.quests[QID] = q
	return code


func _own_hero() -> void:
	if not Save.owns_hero(HERO):
		Save.heroes_owned().append(HERO)


func _gems() -> CurrencyDef:
	var g := CurrencyDef.new()
	g.id = "gems"
	g.display_name = "Gems"
	g.word = "gems"
	g.order = 5
	g.icon = PlaceholderTexture2D.new()
	Registry.currencies["gems"] = g
	return g


# ---------------------------------------------------------------- the content

func test_the_currency_registry_holds_gold_only() -> void:
	assert_bool(Registry.currencies.has("gold")).is_true()
	assert_array(Currency.ids()).contains_exactly(["gold"])
	assert_str(Currency.name_of("gold")).is_equal("Gold")
	assert_object(Currency.icon("gold")).is_not_null()
	# an id the content lacks reads as gold
	assert_str(Currency.of("doubloons")).is_equal("gold")
	assert_str(Currency.of("")).is_equal("gold")


func test_every_sold_look_is_painted_named_and_gated_by_a_real_goal() -> void:
	var sold := 0
	for c: CharacterDef in Registry.characters.values():
		for code in c.variants.keys():
			if not c.sells_skin(str(code)):
				continue
			sold += 1
			var msg := "%s %s" % [c.id, code]
			assert_bool(c.hidden).override_failure_message(msg + ": a hidden hero").is_false()
			assert_str(c.look_strip_path(str(code))).override_failure_message(msg + ": no strip").is_not_empty()
			assert_str(str(c.skin_of(str(code)).get("name", ""))).override_failure_message(msg + ": no name").is_not_empty()
			assert_bool(Currency.known(c.skin_currency(str(code)))).override_failure_message(msg + ": currency").is_true()
			var q := Registry.skin_quest(c, str(code))
			assert_object(q).override_failure_message(msg + ": no goal").is_not_null()
			assert_bool(Registry.quest_visible(q)).override_failure_message(msg).is_true()
			assert_str(TextGen.quest_text(q)).override_failure_message(msg).is_not_equal("Complete a challenge.")
	# (pass 111 pinned at least two on sale; pass 115: Garry takes looks off sale in the editor (Solenne's Canyon Red,
	# May's Midnight Mime), so how many are on sale is his: every one that is must be whole, above)
	assert_int(sold).is_greater_equal(0)


# ---------------------------------------------------------------- owning, buying, wearing

func test_the_look_he_plays_is_always_owned() -> void:
	var c := _hero()
	assert_str(c.home_look()).is_equal(c.variant)
	assert_str(Registry.skin_state(c, c.home_look())).is_equal("owned")
	assert_str(Registry.worn_skin(c)).is_equal("")
	assert_str(Registry.played_look(c).look_code()).is_equal(c.variant)
	# a look that is not sold and not bought is not shown
	for code in c.variants.keys():
		if str(code) != c.home_look() and not c.sells_skin(str(code)):
			assert_str(Registry.skin_state(c, str(code))).is_equal("hidden")


func test_a_skin_is_locked_until_its_goal_is_done_then_bought_once() -> void:
	var c := _hero()
	var code := _sell()
	_own_hero()
	Save.data["gold"] = PRICE * 3
	assert_str(Registry.skin_state(c, code)).is_equal("locked")
	assert_bool(Save.buy_skin(c, code)).is_false()
	assert_int(Save.gold()).is_equal(PRICE * 3)
	Save.mark_quest(QID)
	assert_str(Registry.skin_state(c, code)).is_equal("buyable")
	assert_bool(Save.buy_skin(c, code)).is_true()
	assert_int(Save.gold()).is_equal(PRICE * 2)
	assert_bool(Save.owns_skin(Registry.skin_key(c.id, code))).is_true()
	assert_str(Registry.skin_state(c, code)).is_equal("owned")
	# never twice
	assert_bool(Save.buy_skin(c, code)).is_false()
	assert_int(Save.gold()).is_equal(PRICE * 2)


func test_a_short_purse_or_a_hero_not_owned_buys_nothing() -> void:
	var c := _hero()
	var code := _sell("gold", false)
	Save.data["gold"] = PRICE * 5
	# a hero not owned sells no look
	Save.data["heroes_owned"] = []
	assert_bool(Save.buy_skin(c, code)).is_false()
	_own_hero()
	Save.data["gold"] = PRICE - 1
	assert_bool(Save.buy_skin(c, code)).is_false()
	assert_int(Save.gold()).is_equal(PRICE - 1)
	assert_bool(Save.owns_skin(Registry.skin_key(c.id, code))).is_false()


func test_a_free_skin_is_owned_once_its_goal_is_done() -> void:
	var c := _hero()
	var code := _sell("gold", true, 0)
	assert_str(Registry.skin_state(c, code)).is_equal("locked")
	Save.mark_quest(QID)
	assert_str(Registry.skin_state(c, code)).is_equal("owned")


func test_buying_spends_the_skins_own_currency() -> void:
	_gems()
	var c := _hero()
	var code := _sell("gems", false)
	_own_hero()
	Save.data["gold"] = PRICE * 10
	assert_bool(Save.buy_skin(c, code)).is_false()   # no gems yet
	var moved: Array = []
	var log := func(cur: String, delta: int, reason: String, _bal: int, _extra: Dictionary): moved.append([cur, delta, reason])
	Save.currency_moved.connect(log)
	Currency.add("gems", PRICE + 5, "test")
	assert_int(Currency.balance("gems")).is_equal(PRICE + 5)
	assert_bool(Save.buy_skin(c, code)).is_true()
	Save.currency_moved.disconnect(log)
	assert_int(Currency.balance("gems")).is_equal(5)
	assert_int(Save.gold()).is_equal(PRICE * 10)
	assert_array(moved).contains_exactly([["gems", PRICE + 5, "test"], ["gems", -PRICE, "skin"]])


func test_the_worn_skin_is_the_look_he_is_played_in() -> void:
	var c := _hero()
	var code := _sell("gold", false)
	_own_hero()
	Save.data["gold"] = PRICE
	# not owned: wearing it changes nothing
	Save.set_skin_worn(c.id, code)
	assert_str(Registry.played_look(c).look_code()).is_equal(c.home_look())
	assert_bool(Save.buy_skin(c, code)).is_true()
	assert_str(Registry.played_look(c).look_code()).is_equal(code)
	assert_str(Analytics.hero_look_of(c)).is_equal(code)
	# the arena's kept look (a debug choice) wins; the sheet's choice lets it go
	Save.set_hero_look(c.id, c.home_look())
	assert_str(Registry.played_look(c).look_code()).is_equal(c.home_look())
	Save.set_skin_worn(c.id, code)
	assert_str(Save.hero_look(c.id)).is_equal("")
	assert_str(Registry.played_look(c).look_code()).is_equal(code)
	# a look shelved since is not worn
	(c.variants[code] as Dictionary)["shelved"] = true
	assert_str(Registry.played_look(c).look_code()).is_equal(c.home_look())


func test_an_old_save_reads_as_no_skins_and_bad_values_fall_back() -> void:
	var old := {"version": 5, "gold": 1234, "talents": {}, "quests_done": [], "last_character": "drifter"}
	Save.data = Save._default()
	Save._merge_file(old)
	assert_array(Save.skins_owned()).is_empty()
	assert_str(Save.skin_worn(HERO)).is_equal("")
	assert_int(Save.currency_balance("gold")).is_equal(1234)
	assert_int(Save.currency_balance("gems")).is_equal(0)
	assert_str(Registry.played_look(_hero()).look_code()).is_equal(_hero().variant)
	# a file whose new keys are the wrong kind keeps the defaults
	Save.data = Save._default()
	Save._merge_file({"skins_owned": "may:MAY-B", "skin_worn": 3, "wallets": [1, 2]})
	assert_array(Save.skins_owned()).is_empty()
	assert_str(Save.skin_worn(HERO)).is_equal("")
	assert_int(Save.currency_balance("gems")).is_equal(0)
	# a wipe takes the skins (they are progress)
	Save.data["skins_owned"] = ["may:MAY-B"]
	Save.data["skin_worn"] = {"may": "MAY-B"}
	Save.data = Save._default()
	assert_array(Save.skins_owned()).is_empty()


# ---------------------------------------------------------------- every meta price through Currency

func test_heroes_and_talents_are_paid_through_their_currency() -> void:
	_gems()
	# a talent priced in gems spends gems and comes back half in gems
	var t: TalentDef = Registry.talents_list()[0]
	var was := t.currency_type
	t.currency_type = "gems"
	var cost := t.cost_of_rank(0)
	Save.data["gold"] = cost * 4
	Currency.add("gems", cost, "test")
	assert_bool(Save.buy_talent(t, 0)).is_true()
	assert_int(Currency.balance("gems")).is_equal(0)
	assert_int(Save.gold()).is_equal(cost * 4)
	assert_int(Save.talent_spent_in("gems")).is_equal(cost)
	Save.talent_refund_all()
	assert_int(Currency.balance("gems")).is_equal(int(floor(cost * Save.REFUND_FRAC)))
	t.currency_type = was
	# by default every talent is in gold
	for td: TalentDef in Registry.talents_list():
		assert_str(Currency.of(td.currency_type)).is_equal("gold")
	# a hero on sale is paid in his currency_type (gold), through Currency
	var h: CharacterDef = null
	for c: CharacterDef in Registry.sorted_characters():
		if c.availability == "purchase" and Registry.quest_for("character", c.id) == null:
			h = c
			break
	assert_object(h).is_not_null()
	Save.data["gold"] = h.price + 1
	assert_bool(Save.buy_hero(h)).is_true()
	assert_int(Currency.balance("gold")).is_equal(1)


func test_a_price_shows_its_currencys_icon() -> void:
	var g := _gems()
	var coin: WCoin = auto_free(WCoin.make(30.0, W.BRASS, 3.0, "gems"))
	assert_object(WCoin.art_of(coin.currency)).is_same(g.icon)
	var gold: WCoin = auto_free(WCoin.make(30.0))
	assert_str(gold.currency).is_equal("gold")
	var b: WButton = auto_free(WButton.make(["BUY", {"coin": 40, "currency": "gems"}, ["9", null, 40]], 44))
	var coins: Array = b.find_children("*", "", true, false).filter(func(n): return n is WCoin)
	assert_int(coins.size()).is_equal(1)
	assert_str((coins[0] as WCoin).currency).is_equal("gems")


# ---------------------------------------------------------------- the goal beat_stage

func test_beat_stage_needs_that_stage_beaten_with_that_hero() -> void:
	var map: MapDef = Registry.map("red_canyon")
	var cond := {"type": "beat_stage", "map": "red_canyon", "stage": 2, "hero": HERO}
	var q := QuestDef.new()
	q.condition = cond
	assert_str(TextGen.quest_text(q)).is_equal("Beat %s with %s." % [map.timeline.stage_name(1), _hero().display_name])
	var any := cond.duplicate()
	any["hero"] = ""
	q.condition = any
	assert_str(TextGen.quest_text(q)).is_equal("Beat %s." % map.timeline.stage_name(1))
	Run.start(_hero(), map)
	Run.stage = 1
	Run.stage_beaten = false
	assert_bool(QuestTracker.beat_stage_now(cond)).is_false()
	Run.stage_beaten = true
	assert_bool(QuestTracker.beat_stage_now(cond)).is_true()
	assert_bool(QuestTracker.beat_stage_now(any)).is_true()
	Run.stage = 0
	assert_bool(QuestTracker.beat_stage_now(cond)).is_false()
	Run.stage = 1
	Run.character = Registry.character("drifter")
	assert_bool(QuestTracker.beat_stage_now(cond)).is_false()
	assert_bool(QuestTracker.beat_stage_now(any)).is_true()
	assert_int(QuestTracker.stage_hint(q)).is_equal(2)


# ---------------------------------------------------------------- the hero sheet

func _sheet(locked: bool = false) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var s: Control = Sheet.open(host, _hero(), locked)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func test_the_sheet_sells_looks_only_for_a_hero_owned() -> void:
	_sell("gold", false)
	var locked := await _sheet(true)
	assert_object(locked.find_child("Looks", true, false)).is_null()
	assert_object(locked.find_child("LookGrid", true, false)).is_null()


func test_the_sheet_shows_worn_owned_buy_and_locked_and_wears_and_buys() -> void:
	var c := _hero()
	var code := _sell()
	_own_hero()
	Save.data["gold"] = PRICE
	var s := await _sheet()
	assert_object(s.find_child("Looks", true, false)).is_not_null()
	var home: Control = s.find_child("Look_" + c.home_look(), true, false)
	var tile: Control = s.find_child("Look_" + code, true, false)
	assert_object(home).is_not_null()
	assert_object(tile).is_not_null()
	assert_str(str(home.get_meta("state"))).is_equal("worn")
	assert_str(str(tile.get_meta("state"))).is_equal("locked")
	# the goal's words on the locked tile
	var goal: WText = tile.find_child("Goal", true, false)
	assert_str(goal.text).is_equal(TextGen.quest_text(Registry.quests[QID]))
	# a tap on it buys nothing and opens no question
	s.call("_on_look", code)
	assert_bool(WConfirm.is_open(s)).is_false()
	Save.mark_quest(QID)
	s.call("_fill_looks")
	tile = s.find_child("Look_" + code, true, false)
	assert_str(str(tile.get_meta("state"))).is_equal("buyable")
	# the price with its currency's coin
	var coins: Array = tile.find_children("*", "", true, false).filter(func(n): return n is WCoin)
	assert_int(coins.size()).is_equal(1)
	# a tap asks first
	s.call("_on_look", code)
	assert_bool(WConfirm.is_open(s)).is_true()
	WConfirm.dismiss(s)
	var changed: Array = []
	s.connect("look_changed", func(k: String): changed.append(k))
	assert_bool(s.call("buy_look", code)).is_true()
	assert_int(Save.gold()).is_equal(0)
	assert_str(Registry.played_look(c).look_code()).is_equal(code)
	assert_array(changed).contains_exactly([code])
	await get_tree().process_frame
	assert_str(str((s.find_child("Look_" + code, true, false) as Control).get_meta("state"))).is_equal("worn")
	assert_str(str((s.find_child("Look_" + c.home_look(), true, false) as Control).get_meta("state"))).is_equal("owned")
	# back to the look every player owns
	s.call("_on_look", c.home_look())
	assert_str(Registry.played_look(c).look_code()).is_equal(c.home_look())
	assert_str(Save.skin_worn(c.id)).is_equal("")
	await get_tree().process_frame
	assert_str(str((s.find_child("Look_" + c.home_look(), true, false) as Control).get_meta("state"))).is_equal("worn")
