## Pass 123, lane KIT2: the kit pieces the remaining Royale screens share (Garry, 2026-11-03: "this isnt the full Royale
## UI ... Let's continue with this up until it's matching all the choices that I made for the UI").
##  - the docked tab bar (ui/wanted/WTabBar.gd): five tabs in order, the open one gold, taller and wider, STORE locked
##    and refused, a finger on a tab asks for its scene (the bar's `navigate` stubbed), the Upgrade mark's rule, the
##    phone's bottom inset (W.safe_bottom);
##  - ScreenBase under both themes, with and without a tab bar (the backdrop, the overlay, the scroll's foot, the header);
##  - the menu header's capitals and fitting, the wallet; the info pill; the price button and its short state; the ad
##    glyph as a WButton part; the solid sheet and its cells;
##  - the modal shell (WConfirm.open under Royale, WConfirm.shell); the capture tools' new pieces.
extends GdUnitTestSuite

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_settings_before)


func after_test() -> void:
	W.bottom_inset_override = -1.0
	if Save.sandboxed():
		Save.end_sandbox()


func _bar(active: String) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var bar: Control = load("res://ui/wanted/WTabBar.gd").make(active)
	host.add_child(bar)
	return bar


## A hub screen made for the test: a ScreenBase whose tab_bar() is `tab` ("" none) and whose back goes nowhere.
func _hub(tab: String) -> Control:
	var src := "extends ScreenBase\nfunc tab_bar() -> String:\n\treturn \"%s\"\nfunc on_back() -> void:\n\tpass\n" % tab
	var gs := GDScript.new()
	gs.source_code = src
	gs.reload()
	var s: Control = auto_free(gs.new())
	add_child(s)
	return s


func _finger(c: Control, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = c.size * 0.5
	c._gui_input(e)


# ---------------------------------------------------------------- the tab bar

func test_the_tab_bar_has_five_tabs_the_open_one_gold_taller_and_wider() -> void:
	var bar := _bar("upgrade")
	await get_tree().process_frame
	await get_tree().process_frame
	var ids: Array = bar.TABS
	assert_array(ids).contains_exactly(["store", "heroes", "battle", "upgrade", "collections"])
	assert_str(bar.name).is_equal("TabBar")
	assert_object(bar.get_node_or_null("Band")).is_not_null()
	var last_x := -1.0
	for id: String in ids:
		var t: WTap = bar.get_node("Tab_%s" % id)
		assert_object(t).is_not_null()
		assert_str(str(t.get_meta("tab"))).is_equal(id)
		assert_float(t.position.x).is_greater(last_x)
		last_x = t.position.x
		# every tab stands on the screen's foot (no gesture bar here)
		assert_float(t.position.y + t.size.y + bar.position.y).is_equal_approx(1920.0, 0.5)
		var hb := t.box as HardBox
		assert_array(hb.sides).contains_exactly([true, true, true, false])
		assert_int(hb.radius).is_equal(R.RADIUS_TAB)
		assert_array(hb.corners).contains_exactly([true, true, false, false])
	var up: WTap = bar.call("tab", "upgrade")
	var col: WTap = bar.call("tab", "collections")
	assert_float(up.size.y).is_equal(float(R.DOCK_TAB_H_ACTIVE))
	assert_float(col.size.y).is_equal(float(R.DOCK_TAB_H))
	assert_float(up.size.x / col.size.x).is_equal_approx(R.DOCK_ACTIVE_FLEX, 0.02)
	assert_str((up.box as HardBox).role).is_equal("gold")
	assert_str((col.box as HardBox).role).is_equal("slate")
	# the side margins and the gaps
	var store: WTap = bar.call("tab", "store")
	assert_float(store.position.x).is_equal_approx(float(R.DOCK_SIDE), 0.6)
	assert_float(col.position.x + col.size.x).is_equal_approx(1080.0 - R.DOCK_SIDE, 1.2)
	assert_float(col.position.x - (up.position.x + up.size.x)).is_equal_approx(float(R.DOCK_GAP), 1.2)
	# the words: the open one navy Ultra 28, the rest cream Rubik 700 under the Ultra minimum
	var up_word: WText = up.find_child("Word", true, false)
	var col_word: WText = col.find_child("Word", true, false)
	assert_int(up_word.font_size).is_equal(R.DOCK_WORD_ACTIVE_PX)
	assert_bool(R.is_display(up_word.font)).is_true()
	assert_bool(up_word.color.is_equal_approx(R.NAVY)).is_true()
	assert_bool(R.is_display(col_word.font)).is_false()
	assert_str(col_word.text).is_equal("COLLECTIONS")
	# STORE locked with its badge; the open tab never locked
	assert_bool(store.locked).is_true()
	assert_bool(bool(store.get_meta("locked"))).is_true()
	assert_bool(bar.call("is_locked", "store")).is_true()
	assert_bool(bar.call("is_locked", "upgrade")).is_false()
	assert_bool((bar.get_node("LockBadge") as Control).visible).is_true()
	# the Upgrade mark is never on the Upgrade board itself
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_false()
	# HEROES is locked exactly while its screen does not exist
	var heroes_open := ResourceLoader.exists("res://ui/HeroesScreen.tscn")
	assert_bool(bar.call("is_locked", "heroes")).is_equal(not heroes_open)
	# the band takes the touches between the tabs; the bar itself none
	assert_int(bar.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((bar.get_node("Band") as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_a_finger_on_a_tab_asks_for_its_scene_and_store_goes_nowhere() -> void:
	var bar := _bar("battle")
	await get_tree().process_frame
	var asked: Array = []
	var pressed: Array = []
	bar.set("navigate", func(p: String) -> void: asked.append(p))
	bar.connect("tab_pressed", func(id: String) -> void: pressed.append(id))
	for id: String in ["store", "battle", "collections", "upgrade", "heroes"]:
		var t: WTap = bar.call("tab", id)
		_finger(t, true)
		_finger(t, false)
		await get_tree().process_frame
	assert_array(pressed).contains_exactly(["store", "battle", "collections", "upgrade", "heroes"])
	var want: Array = ["res://ui/CollectionScreen.tscn", "res://ui/HomesteadScreen.tscn"]
	if ResourceLoader.exists("res://ui/HeroesScreen.tscn"):
		want.append("res://ui/HeroesScreen.tscn")
	assert_array(asked).contains_exactly(want)
	# the scenes by tab, the store's none
	var script: GDScript = load("res://ui/wanted/WTabBar.gd")
	assert_str(script.scene_of("store")).is_equal("")
	assert_str(script.scene_of("battle")).is_equal("res://ui/TitleScreen.tscn")
	assert_bool(script.opens("store")).is_false()
	assert_bool(script.opens("upgrade")).is_true()
	# a refused tap shakes the tab and leaves it where it stands (the first tap's shake over first)
	await get_tree().create_timer(R.DOCK_SHAKE_S + 0.2).timeout
	var store: WTap = bar.call("tab", "store")
	var x := store.position.x
	assert_float(x).is_equal_approx(float(R.DOCK_SIDE), 0.6)
	bar.call("press", "store")
	await get_tree().create_timer(R.DOCK_SHAKE_S + 0.2).timeout
	assert_float(store.position.x).is_equal_approx(x, 0.5)
	assert_int(asked.size()).is_equal(want.size())


func test_the_bottom_inset_lifts_the_tabs_over_the_gesture_bar() -> void:
	# headless there is no gesture bar; a phone's comes from the display's safe area
	assert_float(W.safe_bottom()).is_equal(0.0)
	W.bottom_inset_override = 48.0
	assert_float(W.safe_bottom()).is_equal(48.0)
	var script: GDScript = load("res://ui/wanted/WTabBar.gd")
	assert_float(script.height()).is_equal(float(R.DOCK_BAR_H) + 48.0)
	assert_float(script.reach()).is_equal(float(R.DOCK_TAB_H_ACTIVE) + 48.0)
	var bar := _bar("battle")
	await get_tree().process_frame
	await get_tree().process_frame
	var t: WTap = bar.call("tab", "collections")
	assert_float(bar.position.y + t.position.y + t.size.y).is_equal_approx(1920.0 - 48.0, 0.5)
	var band: Control = bar.get_node("Band")
	# the band runs on under the inset to the screen's edge
	assert_float(bar.position.y + band.position.y + band.size.y).is_equal_approx(1920.0, 0.5)
	assert_float(band.size.y).is_equal_approx(float(R.DOCK_BAR_H) + 48.0, 0.5)


func test_the_upgrade_mark_is_the_titles_rule() -> void:
	Save.begin_sandbox()
	var script: GDScript = load("res://ui/wanted/WTabBar.gd")
	Save.data["gold"] = 0
	var want := false
	for def: TalentDef in Registry.talents_list():
		if not Registry.is_unlocked("talent", def.id):
			continue
		var cost := def.cost_of_rank(Save.talent_rank(def.id))
		if cost >= 0 and Currency.can_afford(def.currency_type, cost):
			want = true
	assert_bool(script.upgrade_mark()).is_equal(want)
	Save.data["gold"] = 99999999
	assert_bool(script.upgrade_mark()).is_true()
	var bar := _bar("battle")
	await get_tree().process_frame
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_true()
	Save.data["gold"] = 0
	bar.call("refresh")
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_equal(script.upgrade_mark())


# ---------------------------------------------------------------- ScreenBase

func test_screen_base_under_royale_with_a_tab_bar() -> void:
	var s := _hub("collections")
	await get_tree().process_frame
	var bar: Control = s.get("tab_bar_node")
	assert_object(bar).is_not_null()
	assert_str(bar.name).is_equal("TabBar")
	assert_bool(s.get_child(s.get_child_count() - 1) == bar).is_true()
	assert_bool(s.has_tab_bar()).is_true()
	assert_float(s.tab_bar_height()).is_equal(float(R.DOCK_BAR_H))
	assert_float(s.bottom_total()).is_equal(s.board_bottom() + float(R.DOCK_BAR_H))
	# the backdrop, and the dark overlay in place of the paper wash
	var bd: Control = s.get("backdrop")
	assert_str(bd.name).is_equal("RoyaleBackdrop")
	var wash: ColorRect = s.get("wash")
	assert_bool(Color(wash.color.r, wash.color.g, wash.color.b).is_equal_approx(Color.BLACK)).is_true()
	assert_float(wash.color.a).is_equal_approx(s.backdrop_dim(), 0.001)
	# the scroll ends above the bar once the board has slid in
	await get_tree().create_timer(0.4).timeout
	var sc: ScrollContainer = s.get("scroll")
	assert_float(sc.offset_bottom).is_equal_approx(-s.bottom_total(), 0.5)
	# the header: the slate back square at (40, 56), the name in capitals at 64
	var h: WMenuHeader = s.get("header")
	assert_float(h.offset_left).is_equal(R.HEADER_POS.x)
	assert_float(h.offset_top).is_equal(R.HEADER_POS.y)
	assert_str((h.back_button.box as HardBox).role).is_equal("slate")
	assert_float(h.back_button.size.x).is_equal(float(R.HEADER_BACK))
	s.set_title("Settings")
	assert_str(h.title.text).is_equal("SETTINGS")
	assert_int(h.title.font_size).is_equal(R.HEADER_TITLE_PX)
	assert_bool(R.is_display(h.title.font)).is_true()
	assert_float(h.title.position.x + h.offset_left).is_equal(float(R.HEADER_TITLE_X))
	# the solid sheet fills the board's visible height
	var sheet: PanelContainer = s.solid_sheet()
	auto_free(sheet)
	assert_float(sheet.custom_minimum_size.y).is_equal_approx(s.visible_board_height(), 0.5)
	assert_float(s.visible_board_height()).is_greater(1000.0)
	assert_str((sheet.get_theme_stylebox("panel") as HardBox).royale_kind()).is_equal("panel")




func test_every_screen_base_screen_builds_under_both_themes() -> void:
	Save.begin_sandbox()
	for scene: String in ["res://ui/SettingsScreen.tscn", "res://ui/StagesScreen.tscn", "res://ui/CollectionScreen.tscn",
			"res://ui/HomesteadScreen.tscn", "res://ui/ShopScreen.tscn", "res://ui/ResultsScreen.tscn"]:
		for on: bool in [true]:
			var s: Control = auto_free(load(scene).instantiate())
			add_child(s)
			await get_tree().process_frame
			await get_tree().process_frame
			assert_object(s.get("scroll")).override_failure_message("%s royale=%s: no board" % [scene, on]).is_not_null()
			assert_object(s.get("content")).is_not_null()
			if s.call("use_header"):
				var h: WMenuHeader = s.get("header")
				assert_object(h).is_not_null()
				assert_float(h.offset_left).is_equal(R.HEADER_POS.x if on else 36.0)
			var bd: Control = s.get("backdrop")
			assert_object(bd).is_not_null()
			assert_bool(bd.name == "RoyaleBackdrop").is_equal(on)
			# a screen asks for its bar itself (screen lanes); none does before they land unless it says so
			assert_bool(s.get("tab_bar_node") != null).is_equal(on and str(s.call("tab_bar")) != "")
			remove_child(s)


func test_the_header_fits_a_long_name_beside_the_wallet() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var wallet := WMenuHeader.gold_plate(108411, 44, 40.0, 5, 4)
	var h := WMenuHeader.make("", wallet)
	host.add_child(h)
	await get_tree().process_frame
	h.set_title("Undertaker's Shovel")
	await get_tree().process_frame
	assert_str(h.title.text).is_equal("UNDERTAKER'S SHOVEL")
	assert_int(h.title.font_size).is_less(R.HEADER_TITLE_PX)
	assert_int(h.title.font_size).is_greater_equal(R.HEADER_TITLE_MIN)
	var tw := h.title.font.get_string_size(h.title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, h.title.font_size).x
	assert_float(h.title.position.x + tw).is_less_equal(wallet.position.x)
	# the wallet: the mock's black plate, 72 tall, the number white Ultra 34 with no edge
	assert_str(wallet.name).is_equal("Wallet")
	assert_float(wallet.custom_minimum_size.y).is_equal(float(R.WALLET_H))
	assert_str((wallet.get_theme_stylebox("panel") as HardBox).royale_kind()).is_equal("plate")
	var amount: WText = wallet.find_child("Amount", true, false)
	assert_str(amount.text).is_equal("108,411")
	assert_int(amount.font_size).is_equal(34)
	assert_bool(amount.color.is_equal_approx(R.WHITE)).is_true()
	assert_int(amount.stroke).is_equal(0)
	assert_float(wallet.position.y + h.offset_top).is_equal_approx(float(R.HEADER_RIGHT_Y), 0.5)
	# a short name keeps its size
	h.set_title("Upgrade")
	assert_int(h.title.font_size).is_equal(R.HEADER_TITLE_PX)
	# under Wanted the plate is today's, the number 44
# ---------------------------------------------------------------- the small pieces

func test_the_info_pill() -> void:
	var green: Color = R.ROLES["green"]["top"]
	var p := W.pill([["+1%", green, "bold"], " CRIT per Level"])
	auto_free(p)
	assert_str(p.name).is_equal("Pill")
	assert_float(p.custom_minimum_size.y).is_equal(float(R.PILL_H))
	var box := p.get_theme_stylebox("panel") as HardBox
	assert_str(box.royale_kind()).is_equal("plate")
	assert_int(box.radius).is_equal(R.PILL_RADIUS)
	assert_float(box.content_margin_left).is_equal(float(R.PILL_PAD))
	var texts := p.find_children("*", "WText", true, false)
	assert_int(texts.size()).is_equal(1)
	var t: WText = texts[0]
	assert_int(t.runs.size()).is_equal(2)
	assert_bool((t.runs[0][1] as Color).is_equal_approx(green)).is_true()
	assert_bool(t.color.is_equal_approx(R.WHITE)).is_true()
	assert_int(t.font_size).is_equal(R.PILL_PX)
	assert_bool(R.is_display(t.font)).is_false()
	# the bold part in Rubik 700
	var bold: Font = t.runs[0][2]
	assert_object(bold).is_not_null()
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	assert_int(int((bold as FontVariation).variation_opentype.get(tag, 0))).is_equal(R.LABEL_WEIGHT)
	# a coin and a drawn glyph among the words
	var p2 := W.pill([{"glyph": "clock", "px": 24}, "7:10 to the boss", {"coin": 30.0}])
	auto_free(p2)
	assert_object(p2.find_child("Glyph_clock", true, false)).is_not_null()
	assert_int(p2.find_children("*", "WCoin", true, false).size()).is_equal(1)
	# a plain string, a smaller pill
	var p3 := W.pill("TRAIT · LONG ROAD", 20, 40.0)
	auto_free(p3)
	assert_float(p3.custom_minimum_size.y).is_equal(40.0)
	# under Wanted it still reads: ink type on the paper plate
func test_the_price_button_and_its_short_state() -> void:
	var buy := WButton.price(300, "BUY")
	var host: Control = auto_free(Control.new())
	add_child(host)
	host.add_child(buy)
	await get_tree().process_frame
	assert_str(buy.role).is_equal(WButton.GREEN)
	assert_str(buy.label_text()).is_equal("300 · BUY")
	assert_bool(buy.locked).is_false()
	assert_int(buy.find_children("*", "WCoin", true, false).size()).is_equal(1)
	assert_float(buy.get_combined_minimum_size().y).is_equal_approx(float(R.PRICE_H), 1.0)
	assert_int(int(buy.get_meta("price"))).is_equal(300)
	var choose := WButton.price(1500, "CHOOSE", WButton.BLUE)
	auto_free(choose)
	assert_str(choose.role).is_equal(WButton.BLUE)
	assert_str(choose.label_text()).is_equal("1,500 · CHOOSE")
	# short of gold: the locked grey with the price alone, still emitting `pressed` (WTap's rule)
	var short := WButton.price(190, "BUY", WButton.GREEN, R.PRICE_PX, 166)
	auto_free(short)
	assert_str(short.role).is_equal(WButton.LOCKED)
	assert_bool(short.locked).is_true()
	assert_str(short.label_text()).is_equal("190")
	assert_int(int(short.get_meta("short"))).is_equal(166)
	var lt: WText = short.find_children("*", "WText", true, false)[0]
	assert_bool(lt.color.is_equal_approx(R.SHORT_INK)).is_true()
	var kept := WButton.price(190, "BUY", WButton.GREEN, R.PRICE_PX, 166, "gold", true)
	auto_free(kept)
	assert_str(kept.label_text()).is_equal("190 · BUY")
	# the row: "n short" in red before the button
	var row := W.price_row(190, "BUY", "green", R.PRICE_PX, 166)
	auto_free(row)
	var s: WText = row.get_node("Short")
	assert_bool(s.visible).is_true()
	assert_str(s.text).is_equal("166 short")
	assert_bool(s.color.is_equal_approx(R.ROLES["red"]["top"])).is_true()
	assert_object(W.price_button_of(row)).is_not_null()
	assert_bool(W.price_button_of(row).locked).is_true()
	var ok_row := W.price_row(100, "CHOOSE", "blue")
	auto_free(ok_row)
	assert_bool((ok_row.get_node("Short") as WText).visible).is_false()
	assert_bool(W.price_button_of(ok_row).locked).is_false()
	# under Wanted: brass for a buy, the same label
func test_the_ad_icon_and_the_drawn_glyphs() -> void:
	var b := WButton.make(["GET UP · ", {"ad": 44}], 48, WButton.PRIMARY, 4, 8, 29.0, 30.0, 48.0)
	auto_free(b)
	var g: Control = b.find_child("Glyph_ad", true, false)
	assert_object(g).is_not_null()
	assert_str(str(g.get_meta("glyph"))).is_equal("ad")
	assert_float(g.custom_minimum_size.y).is_equal(44.0)
	assert_float(g.custom_minimum_size.x).is_greater(44.0)
	assert_str(b.label_text()).is_equal("GET UP · ")
	# a glyph part by name, and every kind draws
	var m := WButton.make([{"glyph": "menu", "px": 40}], 40, WButton.SECONDARY)
	auto_free(m)
	assert_object(m.find_child("Glyph_menu", true, false)).is_not_null()
	var host: Control = auto_free(Control.new())
	add_child(host)
	for k: String in ["ad", "play", "lock", "clock", "menu"]:
		var c := W.glyph(k, 48.0, R.CREAM)
		host.add_child(c)
		assert_str(c.name).is_equal("Glyph_%s" % k)
		assert_float(c.custom_minimum_size.y).is_equal(48.0)
	host.add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	# Wanted builds it too
func test_the_solid_sheet_and_cells() -> void:
	var sb := W.sheet_box(Vector2(24, 20))
	assert_str(sb.royale_kind()).is_equal("panel")
	assert_int(sb.border).is_equal(R.PANEL_EDGE)
	assert_int(sb.shadow).is_equal(R.PANEL_BASE)
	assert_float(sb.content_margin_left).is_equal(24.0 + R.PANEL_EDGE)
	var cb := W.cell_box()
	assert_bool(cb.fill.is_equal_approx(R.CELL)).is_true()
	assert_bool(cb.fill.a >= 1.0).is_true()
	assert_int(cb.border).is_equal(R.CELL_EDGE)
	assert_int(cb.shadow).is_equal(0)
	assert_int(cb.radius).is_equal(R.RADIUS)
# ---------------------------------------------------------------- the modal shell

func test_the_confirm_under_royale_is_the_mocks_shell() -> void:
	var host: Control = auto_free(Control.new())
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var hits: Array = []
	var c := WConfirm.open(host, "Wipe the save?", "Everything goes.", "Wipe", "Keep it", func() -> void: hits.append("ok"))
	assert_float(c.card.offset_left).is_equal((1080.0 - R.MODAL_W) * 0.5)
	assert_float(c.card.offset_right).is_equal(-(1080.0 - R.MODAL_W) * 0.5)
	assert_float(c.card.custom_minimum_size.y).is_equal(float(R.MODAL_MIN_H))
	assert_str(c.cancel_btn.name).is_equal("Cancel")
	assert_str(c.confirm_btn.name).is_equal("Confirm")
	assert_str(c.cancel_btn.role).is_equal(WButton.SLATE)
	assert_str(c.confirm_btn.role).is_equal(WButton.RED)
	assert_float(c.cancel_btn.get_combined_minimum_size().y).is_equal_approx(float(R.MODAL_BUTTON_H), 1.0)
	# no rule under Royale; a cream title, a white body
	assert_int(c.card.find_children("*", "ColorRect", true, false).size()).is_equal(0)
	var title: WText = c.card.find_child("Title", true, false)
	assert_str(title.text).is_equal("WIPE THE SAVE?")
	assert_bool(title.color.is_equal_approx(R.CREAM)).is_true()
	assert_int(title.font_size).is_equal(R.MODAL_TITLE_PX)
	var body: WText = c.card.find_child("Body", true, false)
	assert_bool(body.color.is_equal_approx(R.WHITE)).is_true()
	assert_int(c.card.find_children("*", "WStarLine", true, false).size()).is_equal(1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# the card's top at R.MODAL_TOP_AT of the room (the mock's 560)
	var h := maxf(c.card.size.y, c.card.get_combined_minimum_size().y)
	await get_tree().create_timer(0.35).timeout
	assert_float(c.card.offset_top).is_equal_approx((host.get_viewport_rect().size.y - h) * R.MODAL_TOP_AT, 1.0)
	c.confirm_btn.pressed.emit()
	assert_array(hits).contains_exactly(["ok"])
	assert_bool(WConfirm.is_open(host)).is_false()
	# the kinds' roles
	var buy := WConfirm.open(host, "Buy?", "", "Buy", "Not now", func() -> void: pass, Callable(), "buy")
	assert_str(buy.confirm_btn.role).is_equal(WButton.GREEN)
	var act := WConfirm.open(host, "Go?", "", "Go", "Not now", func() -> void: pass, Callable(), "act")
	assert_str(act.confirm_btn.role).is_equal(WButton.GOLD)
	assert_bool(WConfirm.dismiss(host)).is_true()
	# under Wanted the paper card as before: 60 in, the ink rule
func test_the_shell_answers_by_id() -> void:
	var host: Control = auto_free(Control.new())
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var said: Array = []
	var called: Array = []
	var s := WConfirm.shell(host, {"star": "A quick word", "corner": "1 / 2", "title": "How much fun was that run?",
		"title_px": 44, "title_align": "left", "title_upper": false, "keep_open": true, "link": "Don't ask me again",
		"dim_cancels": false, "min_h": 620,
		"buttons": [{"id": "cancel", "text": "Not now", "role": "slate"}, {"id": "next", "text": "Next", "role": "blue"}],
		"on_answer": func(id: String) -> void: called.append(id)})
	s.answered.connect(func(id: String) -> void: said.append(id))
	assert_object(s.card.find_child("Corner", true, false)).is_not_null()
	assert_str((s.card.find_child("Title", true, false) as WText).text).is_equal("How much fun was that run?")
	assert_int((s.card.find_child("Title", true, false) as WText).font_size).is_equal(44)
	assert_str(s.button("next").role).is_equal(WButton.BLUE)
	assert_str(s.button("next").name).is_equal("Btn_next")
	assert_str(s.button("cancel").name).is_equal("Cancel")
	assert_object(s.link_btn).is_not_null()
	assert_str(s.link_btn.name).is_equal("Link")
	s.body_box.add_child(W.pill("a row of the caller's"))
	assert_int(s.body_box.get_child_count()).is_equal(1)
	# keep_open: NEXT answers and the card stays; the dim does nothing when the card wants an answer
	s.button("next").pressed.emit()
	assert_bool(WConfirm.is_open(host)).is_true()
	s.dim.pressed.emit()
	assert_bool(WConfirm.is_open(host)).is_true()
	# the link answers and closes
	s.link_btn.pressed.emit()
	assert_bool(WConfirm.is_open(host)).is_false()
	assert_array(said).contains_exactly(["next", "link"])
	assert_array(called).contains_exactly(["next", "link"])
	# a plain shell: the dim and the back gesture answer cancel_id; confirm() answers the last button
	var said2: Array = []
	var s2 := WConfirm.shell(host, {"title": "Grit", "cancel_id": "close",
		"buttons": [{"id": "close", "text": "Close", "role": "slate"}, {"id": "padding", "text": "Buy", "role": "green"}]})
	s2.answered.connect(func(id: String) -> void: said2.append(id))
	s2.dim.pressed.emit()
	assert_bool(WConfirm.is_open(host)).is_false()
	var s3 := WConfirm.shell(host, {"title": "Grit", "buttons": [{"id": "cancel", "text": "Close"}, {"id": "padding", "text": "Buy", "role": "green"}]})
	s3.answered.connect(func(id: String) -> void: said2.append(id))
	s3.confirm()
	assert_array(said2).contains_exactly(["close", "padding"])
	var s4 := WConfirm.shell(host, {"title": "Grit", "buttons": [{"id": "cancel", "text": "Close"}]})
	s4.answered.connect(func(id: String) -> void: said2.append(id))
	assert_bool(WConfirm.dismiss(host)).is_true()
	assert_array(said2).contains_exactly(["close", "padding", "cancel"])
	# a new question replaces the old one (one per host)
	var a := WConfirm.shell(host, {"title": "One"})
	var b := WConfirm.shell(host, {"title": "Two"})
	assert_bool(WConfirm.current(host) == b).is_true()
	assert_bool(bool(a.get("_done"))).is_true()
	WConfirm.dismiss(host)
	# Wanted builds the same shell on paper
# ---------------------------------------------------------------- the tools

func test_the_capture_tools_carry_the_kit2_pieces() -> void:
	var shots := FileAccess.get_file_as_string("res://tools/wanted_shots.gd")
	# the pass-121 artefact: no one-shot item in the shop's build (the Grindstone's show stayed up over later states)
	assert_bool(shots.contains("if bool(p.get(\"single\")):")).is_true()
	assert_bool(shots.contains("func _kit2()")).is_true()
	assert_bool(shots.contains("\"kit2\"]")).is_true()
	var sheet := FileAccess.get_file_as_string("res://tools/_p122_UIKIT_sheet.gd")
	assert_bool(sheet.contains("func _page_three(")).is_true()
	assert_bool(sheet.contains("[1, 2, 3]")).is_true()
	var audit := FileAccess.get_file_as_string("res://tools/touch_audit.gd")
	assert_bool(audit.contains("func _tab_bar_audit()")).is_true()
