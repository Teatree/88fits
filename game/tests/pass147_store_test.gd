## Pass 147, lane SHOP (Garry: "Make the Shop Screen. On this screen we will only allow selling of Coin Packs for now ...
## Don't implement actual purchasing yet, but put up prices that are common for us. Make the shop button unlockable via the
## Debug version of the Settings. By default locked."): the STORE tab locked by default and opened by the debug panel's
## switch (Settings.store_open, held shut in prod); the Store screen's six packs read from content/store/store.json; a
## price tap adds no coins, writes nothing and says so; Coins x25 leaves the amounts alone; the bonus tag's rule.
extends GdUnitTestSuite

const STORE := "res://ui/StoreScreen.tscn"
const BAR := "res://ui/wanted/WTabBar.gd"

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


func before_test() -> void:
	_settings = Settings.to_dict()
	Settings.store_open = false
	Save.data = Save._default()
	Save.skip_trail_tutorial()
	Save._dirty = false
	StorePacks.load_from()


func after_test() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings)
	StorePacks.load_from()
	Save.dir = _save_dir
	Save.data = _save_data.duplicate(true)
	Save._dirty = false


func _bar(active: String) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var bar: Control = load(BAR).make(active)
	host.add_child(bar)
	return bar


func _store() -> Control:
	var s: Control = auto_free(load(STORE).instantiate())
	add_child(s)
	for k in 3:
		await get_tree().process_frame
	return s


func _file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(StorePacks.DEFAULT))


# ---------------------------------------------------------------- the lock

func test_the_store_tab_is_locked_by_default() -> void:
	assert_bool(Settings.store_open).is_false()
	assert_bool(StorePacks.is_open()).is_false()
	var bar := _bar("battle")
	await get_tree().process_frame
	var script: GDScript = load(BAR)
	assert_bool(script.opens("store")).is_false()
	assert_bool(bar.call("is_locked", "store")).is_true()
	assert_bool((bar.call("tab", "store") as WTap).locked).is_true()
	assert_bool((bar.get_node("LockBadge") as Control).visible).is_true()
	# a finger on it goes nowhere
	var asked: Array = []
	bar.set("navigate", func(p: String) -> void: asked.append(p))
	bar.call("press", "store")
	assert_array(asked).is_empty()


func test_the_debug_switch_opens_the_store_tab() -> void:
	Settings.store_open = true
	assert_bool(StorePacks.is_open()).is_true()
	var bar := _bar("battle")
	await get_tree().process_frame
	assert_bool(bar.call("is_locked", "store")).is_false()
	assert_bool((bar.call("tab", "store") as WTap).locked).is_false()
	assert_bool((bar.get_node("LockBadge") as Control).visible).is_false()
	# the icon in colour: no grey material on it
	var art := (bar.call("tab", "store") as Control).find_child("Art", true, false) as CanvasItem
	if art:
		assert_object(art.material).is_null()
	var asked: Array = []
	bar.set("navigate", func(p: String) -> void: asked.append(p))
	bar.call("press", "store")
	assert_array(asked).contains_exactly([STORE])
	# the Store's own bar: STORE is the open tab
	var own := _bar("store")
	await get_tree().process_frame
	assert_str(str(own.get("active"))).is_equal("store")
	assert_str(((own.call("tab", "store") as WTap).box as HardBox).role).is_equal("gold")


func test_the_settings_debug_panel_has_the_store_switch() -> void:
	Settings.debug_mode = true
	var s: Control = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await get_tree().process_frame
	var sw := s.find_child("StoreOpen", true, false) as WSwitch
	assert_object(sw).is_not_null()
	assert_bool(sw.on).is_false()
	sw.toggled.emit(true)
	assert_bool(Settings.store_open).is_true()
	assert_bool(Settings.to_dict().has("store_open")).is_true()
	sw.toggled.emit(false)
	assert_bool(Settings.store_open).is_false()
	# its words are the string table's row
	assert_str(Loc.t("ui.settings.store")).is_equal("Store")
	s.visible = false


func test_prod_keeps_the_store_shut() -> void:
	assert_bool(Settings.PROD_LOCKED.has("store_open")).is_true()
	assert_bool(bool(Settings.PROD_LOCKED["store_open"])).is_false()
	Settings.store_open = true
	Settings.force_prod(true)
	assert_bool(Settings.store_open).is_false()
	Settings.set_value("store_open", true)
	assert_bool(Settings.store_open).is_false()
	assert_bool(StorePacks.is_open()).is_false()
	assert_bool(load(BAR).opens("store")).is_false()
	# a save that says open is held shut too
	Settings.from_dict({"store_open": true})
	assert_bool(Settings.store_open).is_false()


# ---------------------------------------------------------------- the packs

func test_the_file_holds_six_packs_at_the_common_prices() -> void:
	assert_array(StorePacks.problems()).is_empty()
	var packs: Array = StorePacks.packs()
	assert_int(packs.size()).is_equal(6)
	var cents: Array = []
	for pk: Dictionary in packs:
		cents.append(int(pk["price_cents"]))
		assert_bool(ResourceLoader.exists(str(pk["picture"]))).override_failure_message("%s's picture" % pk["id"]).is_true()
	assert_array(cents).contains_exactly([99, 499, 999, 1999, 4999, 9999])
	assert_str(str(packs[2]["ribbon"])).is_equal("most_popular")
	assert_str(str(packs[5]["ribbon"])).is_equal("best_value")
	# more coins a dollar the bigger the pack (the genre's shape), the last clearly more than the first
	var last := -1.0
	for pk: Dictionary in packs:
		var rate := float(pk["coins"]) / float(StorePacks.dollars(int(pk["price_cents"])))
		assert_float(rate).is_greater(last)
		last = rate
	var first: Dictionary = packs[0]
	assert_float(last / (float(first["coins"]) / float(StorePacks.dollars(int(first["price_cents"]))))).is_greater_equal(1.3)


func test_the_bonus_tag_rule() -> void:
	assert_int(StorePacks.dollars(99)).is_equal(1)
	assert_int(StorePacks.dollars(499)).is_equal(5)
	assert_int(StorePacks.dollars(9999)).is_equal(100)
	assert_int(StorePacks.bonus_for(1000, 99, 1000.0)).is_equal(0)
	assert_int(StorePacks.bonus_for(5500, 499, 1000.0)).is_equal(10)
	assert_int(StorePacks.bonus_for(150000, 9999, 1000.0)).is_equal(50)
	assert_int(StorePacks.bonus_for(900, 99, 1000.0)).is_equal(0)
	StorePacks.load_data({"show_bonus": false, "packs": [{"id": "a", "coins": 10, "price_cents": 99, "price_text": "$0.99"},
		{"id": "b", "coins": 100, "price_cents": 499, "price_text": "$4.99"}]})
	assert_int(int(StorePacks.pack("b")["bonus"])).is_equal(0)
	StorePacks.load_data({"packs": [{"id": "a", "coins": 10, "price_cents": 99, "price_text": "$0.99"},
		{"id": "b", "coins": 100, "price_cents": 499, "price_text": "$4.99"}]})
	assert_int(int(StorePacks.pack("b")["bonus"])).is_equal(100)
	# the checks
	StorePacks.load_data({"packs": [{"id": "a", "coins": 0, "price_cents": 99, "price_text": "$1.99", "ribbon": "hot"},
		{"id": "a", "coins": 5, "price_cents": 0, "price_text": ""}]})
	assert_int(StorePacks.problems().size()).is_equal(6)


func test_the_screen_shows_the_files_packs() -> void:
	var s := await _store()
	var grid := s.find_child("Grid", true, false) as GridContainer
	assert_object(grid).is_not_null()
	assert_int(grid.columns).is_equal(2)
	var d := _file()
	var packs: Array = d["packs"]
	assert_int(grid.get_child_count()).is_equal(packs.size())
	for i in packs.size():
		var pk: Dictionary = packs[i]
		var card := grid.get_child(i) as Control
		assert_str(card.name).is_equal("Pack_%s" % pk["id"])
		var coins := card.find_child("Coins", true, false) as WText
		assert_str(coins.text).is_equal(W.num(int(pk["coins"])))
		var price := card.get_node("Price") as WButton
		assert_str(price.label_text()).is_equal(str(pk["price_text"]))
		assert_str(price.role).is_equal("green")
		assert_bool(card.has_node("Ribbon")).is_equal(str(pk.get("ribbon", "")) != "")
		var bonus: int = StorePacks.bonus_for(int(pk["coins"]), int(pk["price_cents"]), StorePacks.base_rate())
		assert_bool(card.has_node("Bonus")).is_equal(bonus > 0)
		if bonus > 0:
			var words := (card.get_node("Bonus") as Control).find_child("Words", true, false) as WText
			assert_str(words.text).is_equal(Loc.t("ui.store.bonus", {"percent": str(bonus)}).to_upper())
	# the ribbons' words
	var pop := (s.call("card_of", "pack_pouch") as Control).get_node("Ribbon").find_child("Words", true, false) as WText
	assert_str(pop.text).is_equal("MOST POPULAR")
	var best := (s.call("card_of", "pack_cart") as Control).get_node("Ribbon").find_child("Words", true, false) as WText
	assert_str(best.text).is_equal("BEST VALUE")
	assert_array(Loc.warnings()).is_empty()
	s.visible = false


func test_the_grid_fills_the_board_between_the_header_and_the_tab_bar() -> void:
	var s := await _store()
	await get_tree().process_frame
	var grid := s.find_child("Grid", true, false) as Control
	var foot := grid.get_global_rect().end.y
	var bar := s.get("tab_bar_node") as Control
	var bar_top := bar.get_global_rect().end.y - float(R.DOCK_BAR_H)
	var vh := s.get_viewport_rect().size.y
	if vh < 1900.0:
		# a test window shorter than the phone's: the cards' floor holds and the board scrolls instead
		s.visible = false
		return
	# the grid ends above the tab bar's band, and within a card's gap of the board's foot
	assert_float(foot).is_less_equal(bar_top)
	assert_float(bar_top - foot).is_less(float(StoreScreen.GAP) + 80.0)
	s.visible = false


func test_a_price_tap_adds_no_coins_writes_nothing_and_says_so() -> void:
	Save.data["gold"] = 123
	var before := JSON.stringify(Save.data)
	var s := await _store()
	var card := s.call("card_of", "pack_cart") as Control
	var price := card.get_node("Price") as WButton
	price.pressed.emit()
	await get_tree().process_frame
	assert_int(Save.gold()).is_equal(123)
	assert_str(JSON.stringify(Save.data)).is_equal(before)
	assert_bool(Save._dirty).is_false()
	var answers: Array = s.get("answers")
	assert_int(answers.size()).is_equal(1)
	assert_bool(bool(answers[0]["ok"])).is_false()
	assert_str(str(answers[0]["reason"])).is_equal("not_yet")
	# the message: the kit's modal, its words the string table's, one OK
	assert_bool(WConfirm.is_open(s)).is_true()
	var ask := WConfirm.current(s)
	var words: Array = []
	for t: Node in ask.find_children("*", "WText", true, false):
		words.append((t as WText).text)
	assert_array(words).contains([Loc.t("ui.store.not_yet_body")])
	assert_object(ask.button("ok")).is_not_null()
	# a second tap: still one message, still no coins
	price.pressed.emit()
	await get_tree().process_frame
	var open := 0
	for n: Node in s.get_children():
		if n is WConfirm and not bool(n.get("_done")):
			open += 1
	assert_int(open).is_equal(1)
	assert_int(Save.gold()).is_equal(123)
	# OK closes it
	WConfirm.current(s).answer("ok")
	await get_tree().create_timer(0.4).timeout
	assert_bool(WConfirm.is_open(s)).is_false()
	# the wallet shows the purse as it is
	var wallet := s.get("_wallet") as Control
	var amount := wallet.find_child("Amount", true, false) as WText
	assert_str(amount.text).is_equal(W.num(123))
	s.visible = false


func test_coins_x25_does_not_touch_the_amounts() -> void:
	Settings.coins_x25 = true
	var s := await _store()
	for pk: Dictionary in StorePacks.packs():
		var card := s.call("card_of", str(pk["id"])) as Control
		var coins := card.find_child("Coins", true, false) as WText
		assert_str(coins.text).is_equal(W.num(int(_file_pack(str(pk["id"]))["coins"])))
	s.visible = false


func _file_pack(id: String) -> Dictionary:
	for pk: Dictionary in _file()["packs"]:
		if str(pk["id"]) == id:
			return pk
	return {}
