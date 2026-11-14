## Pass 149, lane STORE (Garry, 2026-11-14: "we create a Hard Currency ... light blue gems ... In the Shop there will now be 2
## sections: Gems section at the top, Coins section underneath ... Coins are bought with Gems. As the Player progresses the
## amount of Coins they get from each offers changes ... in rounded steps ... Latest Stage currently unlocked ... Their Trail
## Power Level"; "Gem wallet is only visible to Players when the Store option is turned on"): store.json version 2 and its
## rules (StorePacks), the fixture the Level Editor's mirror is checked against, the Store's two sections, a coin offer bought
## with gems (and refused when short), gem packs that buy nothing, the gem wallet only while the Store is open, the paid
## revive (off by default; offered only with a price and no free chance left), the debug gem grant.
extends GdUnitTestSuite

const STORE := "res://ui/StoreScreen.tscn"
const FIXTURE := "res://tests/fixtures/pass149_store_coins.json"
const TRAIL_ARG := "res://tools/trail_arg.gd"

var _settings: Dictionary = {}
var _save_dir := ""
var _save_data: Dictionary = {}


func before() -> void:
	Save.flush()
	_save_dir = Save.dir
	_save_data = Save.data.duplicate(true)


func after() -> void:
	Save.dir = _save_dir
	Save.data = _save_data
	Save._dirty = false
	Trail.refresh()


func before_test() -> void:
	_settings = Settings.to_dict()
	Settings.store_open = false
	Save.data = Save._default()
	Save.skip_trail_tutorial()
	Save._dirty = false
	Trail.refresh()
	StorePacks.load_from()


func after_test() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings)
	StorePacks.load_from()
	Save.dir = _save_dir
	Save.data = _save_data.duplicate(true)
	Save._dirty = false
	Trail.refresh()


func _file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(StorePacks.DEFAULT))


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _store() -> Control:
	var s: Control = auto_free(load(STORE).instantiate())
	add_child(s)
	for k in 3:
		await get_tree().process_frame
	return s


func _gems(n: int) -> void:
	Save._wallets()["gems"] = n
	Save._dirty = false


## A save at the furthest stage and Trail Level `level`: every stage before the last beaten, the Trail's nodes to `level`
## and the nodes that open stages (the Blood Moon's is past level 40).
func _late_save(level: int) -> void:
	for i in 3:
		Save.mark_stage_beaten("red_canyon", i)
	var ta = load(TRAIL_ARG)
	var ids: Array = ta.ids_upto(level)
	for n: Dictionary in Trail.nodes():
		if str((n["gives"] as Dictionary).get("type", "")) == "stage" and not ids.has(str(n["id"])):
			ids.append(str(n["id"]))
	ta.apply(Save, "", false, ids)
	Save._dirty = false


func _texts(n: Node) -> String:
	var out: Array = []
	for t: Node in n.find_children("*", "WText", true, false):
		out.append((t as WText).text)
	return " | ".join(out)


# ---------------------------------------------------------------- the file

func test_the_file_is_version_2_with_no_problems() -> void:
	assert_int(StorePacks.version()).is_equal(2)
	assert_array(StorePacks.problems()).is_empty()
	var d := _file()
	assert_int(int(d["version"])).is_equal(2)
	# the gem packs: Survivor.io's tiers as the lead remembers them (Garry edits them), $0.99 to $99.99
	var amounts: Array = []
	var cents: Array = []
	for pk: Dictionary in StorePacks.gem_packs():
		amounts.append(int(pk["amount"]))
		cents.append(int(pk["price_cents"]))
	assert_array(amounts).contains_exactly([80, 500, 1200, 2500, 6500, 14000])
	assert_array(cents).contains_exactly([99, 499, 999, 1999, 4999, 9999])
	assert_str(StorePacks.gem_currency()).is_equal("gems")
	# the coin offers: gems for coins
	var ids: Array = StorePacks.offers().map(func(o: Dictionary) -> String: return str(o["id"]))
	assert_array(ids).contains_exactly(["coins_small", "coins_medium", "coins_large"])
	assert_str(StorePacks.coin_currency()).is_equal("gold")
	assert_str(StorePacks.pay_currency()).is_equal("gems")
	assert_array(StorePacks.scaling()["stage_mult"]).contains_exactly([1.0, 3.0, 7.0, 14.0])
	# the paid revive is off by default
	assert_int(int(StorePacks.revive_offer()["price"])).is_equal(0)
	# the gem currency is content, shown only with the Store
	assert_object(Currency.def("gems")).is_not_null()
	assert_str(Currency.def("gems").shown).is_equal("store")


func test_a_version_1_file_reads_empty_and_says_so() -> void:
	StorePacks.load_data({"version": 1, "currency": "gold", "packs": [{"id": "a", "coins": 10, "price_cents": 99,
		"price_text": "$0.99"}]})
	assert_array(StorePacks.gem_packs()).is_empty()
	assert_array(StorePacks.offers()).is_empty()
	assert_int(StorePacks.problems().size()).is_equal(1)
	assert_str(str(StorePacks.problems()[0])).contains("version 1")


func test_the_checks() -> void:
	StorePacks.load_data({"version": 2,
		"gems": {"packs": [{"id": "g", "amount": 10, "price_cents": 99, "price_text": "$0.99"}]},
		"coins": {"offers": [{"id": "g", "gems": 0, "coins": 0, "ribbon": "hot"}],
			"scaling": {"stage_mult": [3.0, 1.0], "trail_per_step": -0.1}},
		"revive": {"price": 5, "currency": ""}})
	var p: Array = StorePacks.problems()
	assert_str(" / ".join(PackedStringArray(p))).contains("g: the id is used twice")
	for want in ["g: no gems", "g: no coins", "g: unknown ribbon hot", "stage 2 gives less than stage 1",
			"trail_per_step: below 0", "revive: a price with no currency"]:
		assert_str(" / ".join(PackedStringArray(p))).override_failure_message("missing: " + want).contains(want)


# ---------------------------------------------------------------- the bonus tags

func test_the_bonus_tags() -> void:
	# gem packs: gems a whole dollar against the $0.99 pack's 80
	var tags: Array = StorePacks.gem_packs().map(func(pk: Dictionary) -> int: return int(pk["bonus"]))
	assert_array(tags).contains_exactly([0, 25, 50, 56, 63, 75])
	# coin offers: coins a gem against the smallest offer's, at the amounts shown
	var b := StorePacks.offer_bonuses(0, 0)
	assert_int(int(b["coins_small"])).is_equal(0)
	assert_int(int(b["coins_medium"])).is_equal(10)
	assert_int(int(b["coins_large"])).is_equal(17)
	# late, the rounding moves them a little (the shown amounts' own rates)
	var late := StorePacks.offer_bonuses(3, 83)
	assert_int(int(late["coins_large"])).is_equal(13)
	# no tags at all with show_bonus false
	var d := _file()
	d["coins"]["show_bonus"] = false
	d["gems"]["show_bonus"] = false
	StorePacks.load_data(d)
	assert_int(int(StorePacks.offer_bonuses(0, 0)["coins_large"])).is_equal(0)
	assert_int(int(StorePacks.gem_pack("gems_vault")["bonus"])).is_equal(0)


# ---------------------------------------------------------------- the coin offer rule

func test_the_fixture_matches_the_rule() -> void:
	var fx := _fixture()
	var by_id := {}
	for o: Dictionary in fx["offers"]:
		by_id[str(o["id"])] = o
	var sc: Dictionary = fx["scaling"]
	# the fixture is the game file's offers and scaling (the Level Editor's mirror is checked against it)
	var d := _file()
	assert_str(JSON.stringify(sc)).is_equal(JSON.stringify(d["coins"]["scaling"]))
	assert_int((fx["cases"] as Array).size()).is_equal(3 * 4 * 5)
	for c: Dictionary in fx["cases"]:
		var got := StorePacks.coins_for(by_id[str(c["offer"])], int(c["stage"]), int(c["trail"]), sc)
		assert_int(got).override_failure_message("%s at stage %d, Trail %d" % [c["offer"], c["stage"], c["trail"]]).is_equal(int(c["coins"]))
	for c: Dictionary in fx["edge"]:
		var got := StorePacks.coins_for(by_id[str(c["offer"])], int(c["stage"]), int(c["trail"]), fx["scaling_edge"])
		assert_int(got).override_failure_message("edge %s at stage %d, Trail %d" % [c["offer"], c["stage"], c["trail"]]).is_equal(int(c["coins"]))
	for n: Array in fx["nice"]:
		assert_int(StorePacks.nice(float(n[0]), int(n[1]))).override_failure_message("nice(%s, %s)" % [n[0], n[1]]).is_equal(int(n[2]))
	StorePacks.load_data({"version": 2, "coins": {"offers": fx["offers"], "scaling": sc}})
	for row: Dictionary in fx["bonus"]:
		var got := StorePacks.offer_bonuses(int(row["stage"]), int(row["trail"]))
		for id: String in (row["bonus"] as Dictionary).keys():
			assert_int(int(got[id])).override_failure_message("bonus %s at stage %d, Trail %d" % [id, row["stage"], row["trail"]]).is_equal(int(row["bonus"][id]))


func test_coins_step_by_stage_and_every_ten_trail_levels_in_two_figures() -> void:
	var o := StorePacks.offer("coins_medium")
	# the file's own amount on a new save
	assert_int(StorePacks.coins_for(o, 0, 0)).is_equal(5500)
	# Trail levels 0..9 give the same; 10 is the first step (5,500 x 1.05 = 5,775 -> 5,800)
	for t in range(10):
		assert_int(StorePacks.coins_for(o, 0, t)).is_equal(5500)
	assert_int(StorePacks.coins_for(o, 0, 10)).is_equal(5800)
	assert_int(StorePacks.coins_for(o, 0, 19)).is_equal(5800)
	# a stage is the big step (x3, x7, x14); the lead's example: 5,500 x 3 x 1.05 = 17,325 -> 17,000
	assert_int(StorePacks.coins_for(o, 1, 0)).is_equal(17000)
	assert_int(StorePacks.coins_for(o, 1, 10)).is_equal(17000)
	assert_int(StorePacks.coins_for(o, 2, 0)).is_equal(39000)
	assert_int(StorePacks.coins_for(o, 3, 0)).is_equal(77000)
	# past the list's end the last multiplier holds
	assert_int(StorePacks.coins_for(o, 9, 0)).is_equal(77000)
	# never fewer coins for more progress, and always two significant figures
	for s in 4:
		var last := 0
		for t in range(0, 84):
			for oo: Dictionary in StorePacks.offers():
				var v := StorePacks.coins_for(oo, s, t)
				var digits := str(v).length()
				assert_int(v % int(pow(10.0, float(maxi(digits - 2, 0))))).is_equal(0)
			var m := StorePacks.coins_for(o, s, t)
			assert_int(m).is_greater_equal(last)
			last = m
	# Coins x25 never multiplies a Store amount
	Settings.coins_x25 = true
	assert_int(StorePacks.coins_now(o)).is_equal(5500)


func test_the_latest_stage_and_the_trail_level_come_from_the_save() -> void:
	assert_int(StorePacks.latest_stage()).is_equal(0)
	assert_int(StorePacks.trail_level()).is_equal(0)
	assert_int(StorePacks.coins_now(StorePacks.offer("coins_large"))).is_equal(14000)
	# Sundown beaten: Nightfall is open
	Save.mark_stage_beaten("red_canyon", 0)
	assert_int(StorePacks.latest_stage()).is_equal(1)
	assert_int(StorePacks.coins_now(StorePacks.offer("coins_large"))).is_equal(42000)
	# the furthest stage at Trail Level 40 (its stages' nodes bought on the way)
	_late_save(40)
	assert_bool(Save.stage_unlocked("red_canyon", 3)).is_true()
	assert_int(StorePacks.latest_stage()).is_equal(3)
	assert_int(StorePacks.trail_level()).is_equal(Trail.level())
	assert_int(Trail.level()).is_equal(40)
	assert_int(StorePacks.coins_now(StorePacks.offer("coins_large"))).is_equal(
		StorePacks.coins_for(StorePacks.offer("coins_large"), 3, Trail.level()))


# ---------------------------------------------------------------- buying

func test_a_coin_offer_buys_with_gems_and_is_refused_when_short() -> void:
	Save.data["gold"] = 100
	_gems(600)
	var ans := StorePacks.buy_coins("coins_medium")
	assert_bool(bool(ans["ok"])).is_true()
	assert_int(int(ans["coins"])).is_equal(5500)
	assert_int(Currency.balance("gems")).is_equal(100)
	assert_int(Save.gold()).is_equal(5600)
	assert_bool(Save._dirty).is_true()
	Save._dirty = false
	# short: nothing moves, the answer says how many more
	var before := JSON.stringify(Save.data)
	var no := StorePacks.buy_coins("coins_medium")
	assert_bool(bool(no["ok"])).is_false()
	assert_str(str(no["reason"])).is_equal("short")
	assert_int(int(no["short"])).is_equal(400)
	assert_str(JSON.stringify(Save.data)).is_equal(before)
	assert_bool(Save._dirty).is_false()
	# an id the file does not have
	assert_str(str(StorePacks.buy_coins("nope")["reason"])).is_equal("unknown")
	# the amount follows the player's progress
	Save.mark_stage_beaten("red_canyon", 0)
	_gems(100)
	var later := StorePacks.buy_coins("coins_small")
	assert_int(int(later["coins"])).is_equal(3000)
	assert_int(Save.gold()).is_equal(8600)
	# Coins x25 does not touch it
	Settings.coins_x25 = true
	_gems(100)
	assert_int(int(StorePacks.buy_coins("coins_small")["coins"])).is_equal(3000)


func test_gem_packs_buy_nothing() -> void:
	_gems(5)
	var before := JSON.stringify(Save.data)
	for pk: Dictionary in StorePacks.gem_packs():
		var ans := StorePacks.buy_gems(str(pk["id"]))
		assert_bool(bool(ans["ok"])).is_false()
		assert_str(str(ans["reason"])).is_equal("not_yet")
	assert_str(JSON.stringify(Save.data)).is_equal(before)
	assert_bool(Save._dirty).is_false()


# ---------------------------------------------------------------- the screen

func test_the_screen_has_gems_on_top_and_coins_underneath() -> void:
	Settings.store_open = true
	var s := await _store()
	await get_tree().process_frame
	var gems := s.find_child("GemsSection", true, false) as Control
	var coins := s.find_child("CoinsSection", true, false) as Control
	assert_object(gems).is_not_null()
	assert_object(coins).is_not_null()
	assert_float(gems.get_global_rect().end.y).is_less_equal(coins.get_global_rect().position.y)
	assert_str(_texts(gems.get_node("Heading"))).is_equal("GEMS")
	assert_str(_texts(coins.find_child("CoinsHeading", true, false))).is_equal("COINS")
	assert_str((coins.find_child("CoinsLine", true, false) as WText).text).is_equal(Loc.t("ui.store.coins_line"))
	assert_int((gems.get_node("Grid") as GridContainer).columns).is_equal(3)
	# the offers in one row, each its coins now and its price in gems with the gem on the green button
	var row := coins.find_child("Offers", true, false) as GridContainer
	assert_int(row.columns).is_equal(3)
	assert_int(row.get_child_count()).is_equal(3)
	for o: Dictionary in StorePacks.offers():
		var card := s.call("card_of", str(o["id"])) as Control
		assert_str(card.name).is_equal("Offer_%s" % o["id"])
		assert_str((card.find_child("Coins", true, false) as WText).text).is_equal(W.num(StorePacks.coins_now(o)))
		var price := card.get_node("Price") as WButton
		assert_str(price.role).is_equal("green")
		assert_str(price.label_text()).contains(W.num(int(o["gems"])))
		var icon := price.find_children("*", "WCoin", true, false)
		assert_int(icon.size()).is_equal(1)
		assert_str((icon[0] as WCoin).currency).is_equal("gems")
		# the offer's coin icon on its amount
		var amt_icon := card.get_node("Amount").find_children("*", "WCoin", true, false)
		assert_str((amt_icon[0] as WCoin).currency).is_equal("gold")
	# the gem packs' amounts wear the gem
	var pack := s.call("card_of", "gems_pouch") as Control
	assert_str(((pack.get_node("Amount").find_children("*", "WCoin", true, false)[0]) as WCoin).currency).is_equal("gems")
	# both wallets in the header (the Store is open)
	var wallet := s.get("_wallet") as Control
	assert_object(wallet.find_child("Wallet_gems", true, false)).is_not_null()
	assert_array(Loc.warnings()).is_empty()
	s.visible = false


func test_the_offers_grow_on_the_screen_late_in_the_game() -> void:
	Settings.store_open = true
	_late_save(40)
	var s := await _store()
	var small := s.call("card_of", "coins_small") as Control
	var want := StorePacks.coins_for(StorePacks.offer("coins_small"), 3, Trail.level())
	assert_int(want).is_greater(1000 * 14 - 1)
	assert_str((small.find_child("Coins", true, false) as WText).text).is_equal(W.num(want))
	# a long amount still fits its card
	var large := s.call("card_of", "coins_large") as Control
	await get_tree().process_frame
	var amount := large.get_node("Amount") as Control
	var n := large.find_child("Coins", true, false) as WText
	assert_float(n.text_width()).is_less_equal(amount.size.x)
	s.visible = false


func test_an_offer_tap_asks_then_buys() -> void:
	Settings.store_open = true
	Save.data["gold"] = 250
	_gems(1000)
	var s := await _store()
	var card := s.call("card_of", "coins_medium") as Control
	(card.get_node("Price") as WButton).pressed.emit()
	await get_tree().process_frame
	assert_bool(WConfirm.is_open(s)).is_true()
	var ask := WConfirm.current(s)
	assert_str(_texts(ask)).contains(Loc.t("ui.store.offer_body", {"coins": "5,500", "gems": "500"}))
	# nothing moved yet
	assert_int(Save.gold()).is_equal(250)
	assert_int(Currency.balance("gems")).is_equal(1000)
	ask.confirm()
	await get_tree().process_frame
	assert_int(Save.gold()).is_equal(5750)
	assert_int(Currency.balance("gems")).is_equal(500)
	var answers: Array = s.get("answers")
	assert_bool(bool(answers.back()["ok"])).is_true()
	# the purse and the gem wallet count again
	var wallet := s.get("_wallet") as Control
	assert_str((wallet.find_child("Amount", true, false) as WText).text).is_equal("5,750")
	assert_str((wallet.find_child("Amount_gems", true, false) as WText).text).is_equal("500")
	s.visible = false


func test_an_offer_tap_short_of_gems_says_how_many_more() -> void:
	Settings.store_open = true
	Save.data["gold"] = 250
	_gems(30)
	var before := JSON.stringify(Save.data)
	var s := await _store()
	var card := s.call("card_of", "coins_small") as Control
	(card.get_node("Price") as WButton).pressed.emit()
	await get_tree().process_frame
	assert_bool(WConfirm.is_open(s)).is_true()
	var msg := WConfirm.current(s)
	assert_str(_texts(msg)).contains(Loc.t("ui.store.short_body", {"amount": "70", "word": "gems"}))
	assert_str(JSON.stringify(Save.data)).is_equal(before)
	var answers: Array = s.get("answers")
	assert_str(str(answers.back()["reason"])).is_equal("short")
	# GET GEMS closes it and takes the board back up to the gem packs
	assert_object(msg.button("gems")).is_not_null()
	msg.answer("gems")
	await get_tree().create_timer(0.4).timeout
	assert_bool(WConfirm.is_open(s)).is_false()
	assert_int((s.get("scroll") as ScrollContainer).scroll_vertical).is_equal(0)
	s.visible = false


# ---------------------------------------------------------------- the gem wallet

func test_the_gem_wallet_shows_only_while_the_store_is_open() -> void:
	_gems(1234)
	# shut (the default): the purse alone, exactly gold_plate's plate; nothing about gems
	assert_bool(Currency.visible("gems")).is_false()
	assert_array(Currency.wallets()).contains_exactly(["gold"])
	var shut: Control = auto_free(WMenuHeader.wallets(500))
	assert_str(shut.name).is_equal("Wallet")
	assert_bool(shut is PanelContainer).is_true()
	assert_object(shut.find_child("Wallet_gems", true, false)).is_null()
	# open: the gem plate beside the purse, gold first, the balance in it
	Settings.store_open = true
	assert_bool(Currency.visible("gems")).is_true()
	assert_array(Currency.wallets()).contains_exactly(["gold", "gems"])
	var open: Control = auto_free(WMenuHeader.wallets(500))
	assert_str(open.name).is_equal("Wallets")
	assert_str(open.get_child(0).name).is_equal("Wallet")
	assert_str(open.get_child(1).name).is_equal("Wallet_gems")
	assert_str((open.find_child("Amount", true, false) as WText).text).is_equal("500")
	assert_str((open.find_child("Amount_gems", true, false) as WText).text).is_equal("1,234")
	# refresh_wallets counts again
	_gems(7)
	WMenuHeader.refresh_wallets(open)
	assert_str((open.find_child("Amount_gems", true, false) as WText).text).is_equal("7")
	# the production build: never
	Settings.force_prod(true)
	assert_bool(Currency.visible("gems")).is_false()
	var prod: Control = auto_free(WMenuHeader.wallets(500))
	assert_object(prod.find_child("Wallet_gems", true, false)).is_null()


func test_the_hub_headers_follow_the_store_switch() -> void:
	_gems(42)
	for open in [false, true]:
		Settings.store_open = open
		var s: Control = auto_free(load("res://ui/HeroesScreen.tscn").instantiate())
		add_child(s)
		await get_tree().process_frame
		var gem := s.find_child("Wallet_gems", true, false)
		assert_bool(gem != null).override_failure_message("Outlaws, store %s" % open).is_equal(open)
		if gem:
			assert_str((gem.find_child("Amount_gems", true, false) as WText).text).is_equal("42")
		s.visible = false
		s.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------- the paid revive

func _revive() -> ReviveScreen:
	var rs: ReviveScreen = auto_free(ReviveScreen.new())
	add_child(rs)
	return rs


func test_the_paid_revive_is_off_by_default() -> void:
	assert_dict(StorePacks.revive_for(0, 0)).is_empty()
	assert_dict(StorePacks.revive_for(1, 0)).is_empty()
	Settings.debug_mode = false
	Settings.free_revive_button = false
	Settings.hit_log = false
	var rs := _revive()
	rs.open(0, 0, "", {}, [], StorePacks.revive_for(0, 0))
	await get_tree().process_frame
	# as before: no chances, the ad's GET UP locked, no paid one
	assert_str(rs.header.star_line.text()).is_equal(Loc.t("ui.revive.no_chances"))
	assert_bool(rs._ad_btn.visible).is_true()
	assert_bool(rs._ad_btn.locked).is_true()
	assert_bool((rs.find_child("GetUpPaid", true, false) as Control).visible).is_false()
	rs.visible = false


func test_the_paid_revive_comes_only_with_a_price_and_no_free_chance() -> void:
	var d := _file()
	d["revive"] = {"price": 50, "currency": "gems", "per_run": 1}
	StorePacks.load_data(d)
	assert_dict(StorePacks.revive_for(1, 0)).is_empty()
	assert_dict(StorePacks.revive_for(0, 1)).is_empty()
	var paid := StorePacks.revive_for(0, 0)
	assert_int(int(paid["price"])).is_equal(50)
	assert_str(str(paid["currency"])).is_equal("gems")
	Settings.debug_mode = false
	Settings.free_revive_button = false
	Settings.hit_log = false
	# a free chance left: the screen as before
	var rs := _revive()
	rs.open(0, 1, "", {}, [], StorePacks.revive_for(1, 0))
	await get_tree().process_frame
	assert_bool(rs._ad_btn.visible).is_true()
	assert_bool(rs._ad_btn.locked).is_false()
	assert_bool((rs.find_child("GetUpPaid", true, false) as Control).visible).is_false()
	# none left, short of gems: the paid GET UP, locked, the price in its currency, "50 short"; a tap does nothing
	_gems(0)
	var said: Array = []
	rs.decided.connect(func(k: String) -> void: said.append(k))
	rs.open(0, 0, "", {}, [], paid)
	await get_tree().process_frame
	var up := rs.find_child("GetUpPaid", true, false) as WButton
	assert_bool(up.visible).is_true()
	assert_bool(rs._ad_btn.visible).is_false()
	assert_bool(up.locked).is_true()
	assert_str(up.label_text()).contains("50")
	assert_str((up.find_children("*", "WCoin", true, false)[0] as WCoin).currency).is_equal("gems")
	assert_str(rs.header.star_line.text()).is_equal(Loc.t("ui.revive.no_free_chances"))
	var short := rs.find_child("PaidShort", true, false) as WText
	assert_bool(short.visible).is_true()
	assert_str(short.text).is_equal(Loc.t("ui.kit.short", {"short": "50"}))
	up.pressed.emit()
	assert_array(said).is_empty()
	assert_int(Currency.balance("gems")).is_equal(0)
	# with the gems: a tap pays and gets up ("paid")
	_gems(120)
	rs.open(0, 0, "", {}, [], paid)
	await get_tree().process_frame
	assert_bool(up.locked).is_false()
	assert_str(up.role).is_equal("gold")
	up.pressed.emit()
	assert_array(said).contains_exactly(["paid"])
	assert_int(Currency.balance("gems")).is_equal(70)
	rs.visible = false


func test_the_down_screen_shows_the_gem_wallet_only_with_the_store_open() -> void:
	_gems(321)
	Settings.debug_mode = false
	Settings.free_revive_button = false
	Settings.hit_log = false
	var rs := _revive()
	rs.open(0, 1)
	await get_tree().process_frame
	assert_object(rs.find_child("Wallet_gems", true, false)).is_null()
	Settings.store_open = true
	rs.open(0, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var gem := rs.find_child("Wallet_gems", true, false) as Control
	assert_object(gem).is_not_null()
	assert_str((gem.find_child("Amount_gems", true, false) as WText).text).is_equal("321")
	assert_bool(gem.is_visible_in_tree()).is_true()
	rs.visible = false


func test_a_run_starts_with_no_paid_revive_used() -> void:
	Run.paid_revives = 2
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_int(Run.paid_revives).is_equal(0)
	Run.end()


# ---------------------------------------------------------------- the debug grant

func test_the_debug_grant_adds_gems_and_never_in_prod() -> void:
	assert_int(StorePacks.debug_grant()).is_equal(1000)
	assert_int(Currency.balance("gems")).is_equal(1000)
	Settings.force_prod(true)
	assert_int(StorePacks.debug_grant()).is_equal(1000)
	assert_int(Currency.balance("gems")).is_equal(1000)


func test_the_settings_debug_panel_has_the_gem_grant() -> void:
	Settings.debug_mode = true
	var s: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	var row := s.find_child("AddGemsRow", true, false) as Control
	assert_object(row).is_not_null()
	var b := s.find_child("AddGems", true, false) as WButton
	assert_object(b).is_not_null()
	b.pressed.emit()
	assert_int(Currency.balance("gems")).is_equal(1000)
	assert_str((row.find_child("Name", true, false) as WText).text).is_equal(
		Loc.t("ui.settings.add_gems", {"amount": "1,000", "balance": "1,000"}))
	s.visible = false
