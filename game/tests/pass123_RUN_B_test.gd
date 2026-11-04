## Pass 123, lane RUN_B: the Shop, the Stranger, the Totem gifts and the Boss chest under Royale (Garry's build brief,
## tools/dl/p123/BRIEF.md: "Shop as the mock: green price · BUY, an unaffordable offer keeps its card with a grey button
## and the shortfall in red, YOU HOLD as framed icons" + "Leave ... red", "gold amount at the top right"; "Stranger as
## the mock" + "'Walk Away' should be red and make the sizes bigger"; "Totem gifts as the mock: the pole kept" + "Make the
## Totem 1 of 10 more like a Header and make it white"; "Boss chest as the mock" + "Header text white"). Wanted (the
## default) is laid out as before; every screen is built under both themes here.
##  - the shop: the wallet at the top right outside the header, YOU HOLD beside 56 px frames, each card's price row
##    (green BUY; short: the grey locked button with "n short" in red, the card itself not locked), the tag after the
##    word, LEAVE red and wider; under Wanted the plate in the header, the stacked tray, the aged short card, LEAVE slate;
##  - a finger on a short card under Royale: no held look, the tap still answers and buys nothing; a finger on an
##    affordable one: the held look, the purchase, the stall shut;
##  - the Stranger: the title fitted to the screen, WALK AWAY red and DEAL gold at equal halves and the bigger height,
##    the price's numbers (white, red), the kind's words with the rarity before the deal's; Wanted as before;
##  - the Totem: the header ("TOTEM 1 OF 10" in cream between gold stars, centred over the crest), the pole's segments
##    drawn as the carved plate (the kit's frame hidden), the cards where the mock puts them with the gain in gold, the
##    touch area and the held step; Wanted as before;
##  - the boss chest: the cream title and the gold star line, the panels' rects (the speed bonus across the screen,
##    GOLD and EXP as wide between them), the count exact, CLAIM gold, drawn without error; Wanted as before;
##  - the capture tool carries the new states.
extends GdUnitTestSuite

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)
	W.theme_changed()


func after_test() -> void:
	Run.arena = false
	Run.end()
	Settings.force_prod(false)
	Settings.ui_theme = "wanted"
	W.theme_changed()
	if Save.sandboxed():
		Save.end_sandbox()


func _royale(on: bool) -> void:
	Settings.ui_theme = "royale" if on else "wanted"
	W.theme_changed()


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _card(def: ContentDef, from: int = 0, to: int = 1) -> Dictionary:
	var t := "weapon" if def is WeaponDef else "passive"
	return {"type": t, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _offer() -> Array:
	return [_card(Registry.passive("adrenaline")), _card(Registry.passive("clover")), _card(Registry.passive("desperado"))]


func _touch(at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = down
	get_tree().root.push_input(e, true)


## A shop opened on the three passive items with the purse at the cheapest one's price (so at least one is short).
func _open_shop() -> StructureShop:
	var s := StructureShop.new()
	add_child(s)
	await _frames(1)
	# a build in the tray: two weapons and four passive items (none of the offer's)
	Run.debug_clear_items()
	for it in [["weapon", "revolver", 2], ["weapon", "boomstick", 3], ["passive", "magnet", 2], ["passive", "evade", 1],
			["passive", "energy_shield", 2], ["passive", "kindling", 1]]:
		Run.debug_set_item(it[0], it[1], it[2])
	var offer := _offer()
	var low := 1 << 30
	for c: Dictionary in offer:
		low = mini(low, StructureShop.price_of(c))
	Run.run_gold = low
	s.open(offer)
	# the wallet's drop-in (0.25 s) and the fit a frame after the open
	await get_tree().create_timer(0.45, true, false, true).timeout
	await _frames(2)
	return s


func test_the_shop_under_royale_is_the_mock() -> void:
	_royale(true)
	_start()
	var s := await _open_shop()
	var vp := s.get_viewport_rect().size
	# the wallet: the kit's black plate at the top right, outside the header, the purse in white
	var wal: Control = s.get_node_or_null("Wallet")
	assert_object(wal).is_not_null()
	assert_object(s._gold_plate).is_same(wal)
	assert_float(wal.get_global_rect().end.x).is_equal_approx(vp.x - float(R.HEADER_POS.x), 1.0)
	assert_float(wal.get_global_rect().position.y).is_equal_approx(float(R.HEADER_RIGHT_Y) + W.safe_top(), 1.0)
	var amt := wal.find_child("Amount", true, false) as WText
	assert_str(amt.text).is_equal(W.num(Run.run_gold))
	assert_bool(amt.color.is_equal_approx(R.WHITE)).is_true()
	assert_int(s.header.find_children("*", "CenterContainer", true, false).size()).is_equal(0)
	# the body starts under the title (no plate in the header)
	assert_float(s._body.offset_top).is_less(float(400) + W.safe_top())
	# YOU HOLD beside the frames, 56 px
	assert_bool(s._tray is HBoxContainer).is_true()
	assert_bool(s._tray.visible).is_true()
	assert_int(s._hold_flow.get_child_count()).is_equal(StructureShop.held_items().size())
	assert_object(s._hold_label.get_parent()).is_same(s._tray)
	assert_float(s.plate_px()).is_equal(StructureShop.ROYALE_TRAY_PX)
	for p in s._hold_flow.get_children():
		assert_float((p as WPlate).side).is_equal(StructureShop.ROYALE_TRAY_PX)
	assert_float(s._hold_label.get_global_rect().end.x).is_less_equal(s._hold_flow.get_global_rect().position.x - StructureShop.ROYALE_TRAY_LABEL_GAP + 1.0)
	assert_float(s._hold_flow.get_global_rect().position.y).is_equal_approx(s._hold_label.get_global_rect().position.y, 1.0)
	# LEAVE red, the mock's width
	var leave := s.find_child("Leave", true, false) as WButton
	assert_str(leave.role).is_equal(WButton.RED)
	assert_float(leave.size.x).is_equal_approx(StructureShop.ROYALE_LEAVE_W, 1.0)
	# the cards: the price row on each; the short one's grey button with the shortfall in red; no card locked
	var shorts := 0
	for i in s._cards.size():
		var c: WCard = s._cards[i]
		var price := StructureShop.price_of(s._offer[i])
		var short := maxi(price - Run.run_gold, 0)
		var row: Control = c.find_child("Price", true, false)
		assert_object(row).is_not_null()
		var pb := W.price_button_of(row)
		assert_object(c.price_button).is_same(pb)
		assert_bool(c.locked).is_false()
		assert_float(c.modulate.a).is_equal(1.0)
		var sh := row.get_node("Short") as WText
		if short > 0:
			shorts += 1
			assert_bool(pb.locked).is_true()
			assert_int(int(pb.get_meta("short"))).is_equal(short)
			assert_bool(sh.visible).is_true()
			assert_str(sh.text).contains("%d short" % short)
			assert_float(pb.custom_minimum_size.x).is_equal(StructureShop.ROYALE_PRICE_W_SHORT)
		else:
			assert_bool(pb.locked).is_false()
			assert_str(pb.role).is_equal(WButton.GREEN)
			assert_str(pb.label_text()).contains("BUY")
			assert_str(pb.label_text()).contains(W.num(price))
			assert_bool(sh.visible).is_false()
			assert_float(pb.custom_minimum_size.x).is_equal(StructureShop.ROYALE_PRICE_W)
		# the tag straight after the kind's words
		var wl: Control = c.find_child("WordLine", true, false)
		assert_int((wl.get_child(0) as Control).size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
		assert_object(c.find_child("Tag", true, false)).is_not_null()
	assert_int(shorts).is_greater(0)
	assert_int(shorts).is_less(3)
	s.queue_free()


func test_a_short_card_takes_a_finger_without_the_held_look() -> void:
	_royale(true)
	_start()
	var s := await _open_shop()
	var short_c: WCard = null
	var buy_c: WCard = null
	var buy_i := -1
	for i in s._cards.size():
		var c: WCard = s._cards[i]
		if bool(c.price_button.locked):
			short_c = c
		elif buy_c == null:
			buy_c = c
			buy_i = i
	assert_object(short_c).is_not_null()
	assert_object(buy_c).is_not_null()
	var taps := [0]
	short_c.pressed.connect(func() -> void: taps[0] += 1)
	var gold0 := Run.run_gold
	# a finger on the short card's text (not on its button): no held look, no rays; lifted: it answers, buys nothing
	var at := short_c.effect_text.get_global_rect().get_center() if short_c.effect_text else short_c.get_global_rect().get_center()
	_touch(at, true)
	await _frames(2)
	assert_bool(short_c._held_look).is_false()
	assert_bool(short_c.plate.rays).is_false()
	_touch(at, false)
	await _frames(2)
	assert_int(taps[0]).is_equal(1)
	assert_int(Run.run_gold).is_equal(gold0)
	assert_bool(s.visible).is_true()
	assert_bool(s._done).is_false()
	# the affordable one: held under the finger (the kit's glow and rays), bought on the lift, the stall shut
	var closed := [false, false]
	s.closed.connect(func(b: bool) -> void:
		closed[0] = true
		closed[1] = b)
	var at2 := buy_c.get_global_rect().get_center()
	_touch(at2, true)
	await _frames(2)
	assert_bool(buy_c._held_look).is_true()
	assert_bool(buy_c.plate.rays).is_true()
	_touch(at2, false)
	for k in 30:
		await get_tree().process_frame
		if closed[0]:
			break
	assert_bool(closed[0]).is_true()
	assert_bool(closed[1]).is_true()
	assert_int(Run.run_gold).is_equal(gold0 - StructureShop.price_of(s._offer[buy_i]))
	s.queue_free()


func test_the_shop_under_wanted_is_as_before() -> void:
	_royale(false)
	_start()
	var s := await _open_shop()
	assert_object(s.get_node_or_null("Wallet")).is_null()
	assert_bool(s._gold_plate.get_parent() is CenterContainer).is_true()
	assert_object(s._gold_plate.get_parent().get_parent()).is_same(s.header)
	assert_bool(s._tray is VBoxContainer).is_true()
	assert_float(s.plate_px()).is_equal(StructureShop.tray_px(StructureShop.held_items().size()))
	var leave := s.find_child("Leave", true, false) as WButton
	assert_str(leave.variant).is_equal(WButton.SECONDARY)
	assert_float(leave.size.x).is_equal_approx(430.0, 1.0)
	for i in s._cards.size():
		var c: WCard = s._cards[i]
		var short := maxi(StructureShop.price_of(s._offer[i]) - Run.run_gold, 0)
		assert_object(c.find_child("Price", true, false)).is_null()
		assert_object(c.price_button).is_not_null()
		assert_bool(c.locked).is_equal(short > 0)
	s.queue_free()


func _stranger() -> StrangerScreen:
	var s := StrangerScreen.new()
	add_child(s)
	await _frames(1)
	s.open({"type": "passive", "id": "guillotine", "def": Registry.passive("guillotine"), "level_from": 0, "level_to": 2, "is_new": true}, 0.15)
	await _frames(4)
	return s


func test_the_stranger_under_royale_is_the_mock_bigger() -> void:
	_royale(true)
	_start()
	var s := await _stranger()
	var vp := s.get_viewport_rect().size
	# the title fitted to the screen in cream
	var t := s.header.title
	assert_int(t.font_size).is_less(120)
	assert_float(t.text_width()).is_less_equal(vp.x - 2.0 * StrangerScreen.ROYALE_TITLE_SIDE + 1.0)
	assert_bool(t.color.is_equal_approx(R.CREAM)).is_true()
	# WALK AWAY red, DEAL gold, equal halves, the bigger height
	var walk := s.find_child("WalkAway", true, false) as WButton
	var deal := s.find_child("Deal", true, false) as WButton
	assert_str(walk.role).is_equal(WButton.RED)
	assert_str(deal.role).is_equal(WButton.GOLD)
	assert_float(absf(walk.size.x - deal.size.x)).is_less_equal(2.0)
	assert_float(s.buttons.size.y).is_equal_approx(StrangerScreen.ROYALE_BUTTON_H, 1.0)
	assert_int(walk.font_size).is_equal(StrangerScreen.ROYALE_BUTTON_PX)
	# the price: what it is in cream, what it will be in red
	var mx := Run.player_sheet.get_stat("max_hp", 100.0)
	var runs: Array = s._price_nums.runs
	assert_int(runs.size()).is_equal(3)
	assert_str(str(runs[0][0])).is_equal(W.num(int(round(mx))))
	assert_str(str(runs[2][0])).is_equal(W.num(int(round(mx * 0.85))))
	assert_bool((runs[2][1] as Color).is_equal_approx(R.role("red")["top"])).is_true()
	assert_float(s._bar.size.y).is_equal_approx(StrangerScreen.ROYALE_BAR_H, 1.0)
	assert_float(s._bar.loss).is_equal_approx(0.15, 0.001)
	# the deal card's words: the kind, its rarity, then the deal; the tag right after them
	var card := s._card_host.get_child(0) as WCard
	var wl: Control = card.find_child("WordLine", true, false)
	var word := wl.get_child(0) as WText
	assert_int((word as Control).size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	var wr: Array = word.runs
	assert_str(str(wr[0][0])).is_equal("PASSIVE")
	var rar := card.plate.frame_rarity()
	assert_str(str(wr[1][0])).is_equal(" " + rar.to_upper())
	assert_str(str(wr[wr.size() - 1][0])).is_equal(" · STRAIGHT TO LV 2")
	# the deal panel stays clear of the buttons
	assert_float(s._panel.get_global_rect().end.y).is_less_equal(s.buttons.get_global_rect().position.y)
	s.queue_free()


func test_the_stranger_under_wanted_is_as_before() -> void:
	_royale(false)
	_start()
	var s := await _stranger()
	assert_int(s.header.title.font_size).is_equal(120)
	var walk := s.find_child("WalkAway", true, false) as WButton
	var deal := s.find_child("Deal", true, false) as WButton
	assert_str(walk.variant).is_equal(WButton.SECONDARY)
	assert_str(deal.variant).is_equal(WButton.PRIMARY)
	assert_float(deal.size_flags_stretch_ratio).is_equal_approx(1.4, 0.001)
	assert_float(s.buttons.size.y).is_greater_equal(114.0)
	assert_bool(s._price_nums.runs.is_empty()).is_true()
	assert_str(s._price_nums.text).contains(" → ")
	assert_float(s._bar.size.y).is_equal_approx(48.0, 1.0)
	s.queue_free()


func _totem_offer() -> Array:
	var boons = TotemScreen.BOONS
	var pool: Array = boons.pool_of(Registry.structure("totem_pole"))
	var out: Array = []
	for id in ["wolf", "bullhead", "bear"]:
		for e: Dictionary in pool:
			if str(e.get("id", "")) == id:
				var b := {"id": id, "name": str(e.get("name", "")), "animal": str(e.get("animal", "")), "stat": str(e.get("stat", "")),
					"op": str(e.get("op", "add")), "value": float(e.get("min", 0.0)), "min": float(e.get("min", 0.0)), "max": float(e.get("max", 0.0))}
				b["quality"] = boons.quality(float(b["value"]), float(b["min"]), float(b["max"]))
				out.append(b)
	return out


func _totem(index: int = 1, total: int = 10) -> TotemScreen:
	var ts := TotemScreen.new()
	add_child(ts)
	await _frames(1)
	ts.open(_totem_offer(), Registry.structure("totem_pole"), index, total)
	# the open motion (T_OPEN, 0.46 s) landed
	await get_tree().create_timer(0.7, true, false, true).timeout
	await _frames(2)
	return ts


func test_the_totem_under_royale_keeps_the_pole_and_heads_the_screen() -> void:
	_royale(true)
	_start()
	var ts := await _totem()
	var vp := ts.get_viewport_rect().size
	assert_str(ts.header_text()).is_equal("TOTEM 1 OF 10")
	assert_str(ts.label_text()).is_equal("TOTEM 1 OF 10")
	assert_bool(ts._label_text.visible).is_false()
	var h := ts._header_royale
	assert_float(h.get_global_rect().get_center().x).is_equal_approx(vp.x * 0.5, 2.0)
	assert_float(h.get_global_rect().end.y).is_less(ts._crest.get_global_rect().position.y)
	assert_bool(h.color.is_equal_approx(R.GOLD_TEXT)).is_true()
	var words: WText = h.get("_text")
	assert_bool(words.color.is_equal_approx(R.CREAM)).is_true()
	assert_bool(R.is_display(words.font)).is_true()
	assert_int(words.font_size).is_equal(TotemScreen.ROYALE_HEADER_PX)
	var rows: Array = ts.planks()
	assert_int(rows.size()).is_equal(3)
	for r in rows:
		var row := r as TotemScreen.GiftRow
		assert_vector(row.tag_at).is_equal(Vector2(TotemScreen.ROYALE_TAG_X - TotemScreen.SEG_X, (TotemScreen.SEG - TotemScreen.ROYALE_TAG.y) * 0.5))
		assert_vector(row.tag.size).is_equal(TotemScreen.ROYALE_TAG)
		# the pole kept: the kit's frame hidden, the carved face drawn
		assert_bool(row.plate.visible).is_false()
		assert_object(row.face).is_not_null()
		assert_bool(row.face.is_visible_in_tree()).is_true()
		# the gain in gold Ultra
		# pass 123 (Garry: "The stronger the effect the more prominent the visuals", "use stars instead"): by the roll's third
		var third: int = clampi(row.feathers, 1, 3) - 1
		assert_int(row.amount.font_size).is_equal(int(TotemScreen.ROYALE_AMOUNT_BY_THIRD[third]))
		assert_bool(row.amount.color.is_equal_approx(R.GOLD_TEXT)).is_true()
		assert_object(row.gauge).is_null()
		assert_object(row.stars).is_not_null()
		assert_int(row.stars.total).is_equal(3)
		assert_int(row.stars.held).is_equal(third + 1)
		assert_int(row.tag_box.inner).is_equal(int(TotemScreen.ROYALE_INNER_BY_THIRD[third]))
		assert_bool(row.has_meta("tag_glow")).is_equal(int(TotemScreen.ROYALE_GLOW_BY_THIRD[third]) > 0)
		# a finger on the card is the gift's; the gap between the segment and the card is nobody's
		assert_bool(row._has_point(row.tag_at + row.tag_size * 0.5)).is_true()
		assert_bool(row._has_point(Vector2(TotemScreen.SEG + TotemScreen.PRESS_SEG_X + 20.0, TotemScreen.SEG * 0.5))).is_false()
	# the card's right edge stays on the screen
	var last := rows[0] as TotemScreen.GiftRow
	assert_float(last.tag.get_global_rect().end.x).is_less_equal(vp.x)
	# held: the card steps straight down by its base
	var mid := rows[1] as TotemScreen.GiftRow
	mid.arrived = true
	mid.show_held(true)
	for k in 20:
		await get_tree().process_frame
	assert_vector(mid.tag.position).is_equal_approx(mid.tag_home + TotemScreen.ROYALE_PRESS_TAG, Vector2(0.5, 0.5))
	mid.show_held(false)
	ts.queue_free()
	# a pole the map's count does not know
	var ts2 := await _totem(4, 0)
	assert_str(ts2.header_text()).is_equal("4TH TOTEM")
	ts2.queue_free()


func test_the_totem_under_wanted_is_as_before() -> void:
	_royale(false)
	_start()
	var ts := await _totem()
	assert_str(ts.header_text()).is_equal("")
	assert_object(ts._header_royale).is_null()
	assert_bool(ts._label_text.visible).is_true()
	for r in ts.planks():
		var row := r as TotemScreen.GiftRow
		assert_vector(row.tag_at).is_equal(TotemScreen.TAG_AT)
		assert_vector(row.tag.size).is_equal(TotemScreen.TAG)
		assert_bool(row.plate.visible).is_true()
		assert_object(row.face).is_null()
		assert_int(row.amount.font_size).is_equal(TotemScreen.AMOUNT_PX)
	ts.queue_free()


func _boss_chest() -> BossChestScreen:
	var bs := BossChestScreen.new()
	add_child(bs)
	await _frames(1)
	var pack := BossChest.net(BossChest.sample_pack("tumbleweed_king", 0, 45.0), 1.0, 1.0)
	bs.open("tumbleweed_king", pack)
	bs.set_process(false)
	return bs


func test_the_boss_chest_under_royale_is_the_mock() -> void:
	_royale(true)
	_start()
	var bs := await _boss_chest()
	var vp := bs.get_viewport_rect().size
	bs.seek(BossChestScreen.SPEW_AT + 1.0)
	await _frames(2)
	# the header: the chest's name in cream, the star line gold
	assert_bool(bs.header.title.color.is_equal_approx(R.CREAM)).is_true()
	assert_int(bs.header.title.bevel).is_equal(0)
	assert_bool(bs.header.star_line.color.is_equal_approx(R.GOLD_TEXT)).is_true()
	# the panels where the mock puts them
	var side := BossChestScreen.ROYALE_SIDE
	assert_float(bs._meter_rect.position.x).is_equal(side)
	assert_float(bs._meter_rect.size.x).is_equal(vp.x - 2.0 * side)
	assert_float(bs._meter_rect.position.y).is_equal(W.safe_top() + BossChestScreen.ROYALE_METER_Y)
	assert_float(bs._meter_rect.position.y).is_greater(bs.header.title.get_global_rect().position.y)
	assert_float(bs._gold_rect.position.x).is_equal(side)
	assert_float(bs._xp_rect.end.x).is_equal(vp.x - side)
	assert_float(bs._xp_rect.position.x - bs._gold_rect.end.x).is_equal_approx(BossChestScreen.ROYALE_GAP, 0.01)
	assert_float(bs._gold_rect.size.x).is_equal_approx(bs._xp_rect.size.x, 0.01)
	assert_float(bs._meter.modulate.a).is_equal(1.0)
	# the count ends exact, CLAIM gold
	bs.finish_now()
	await _frames(2)
	assert_array(bs.counters()).is_equal([int(bs.gold_total), int(round(float(bs.xp_total)))])
	assert_bool(bs.ready_to_claim()).is_true()
	assert_str((bs.find_child("Claim", true, false) as WButton).role).is_equal(WButton.GOLD)
	assert_str(BossChestScreen.times()).is_not_empty()
	bs.queue_free()


func test_the_boss_chest_under_wanted_is_as_before() -> void:
	_royale(false)
	_start()
	var bs := await _boss_chest()
	var vp := bs.get_viewport_rect().size
	bs.seek(BossChestScreen.SPEW_AT + 1.0)
	await _frames(2)
	assert_bool(bs.header.title.color.is_equal_approx(W.BRASS)).is_true()
	assert_float(bs._meter_rect.size.x).is_equal(800.0)
	assert_float(bs._meter_rect.position.x).is_equal(vp.x * 0.5 - 400.0)
	assert_float(bs._gold_rect.size.x).is_equal(minf((vp.x - 48.0 * 2.0 - 28.0) * 0.5, 470.0))
	assert_float(bs._meter.modulate.a).is_equal(1.0)
	assert_float(bs._counters.modulate.a).is_equal(1.0)
	bs.queue_free()


func test_the_capture_tool_carries_the_new_states() -> void:
	var src := FileAccess.get_file_as_string("res://tools/wanted_shots.gd")
	assert_str(src).contains("in_run.append_array([\"shop_held\", \"totem\", \"bosschest\"])")
	for f in ["func _shop_held()", "func _totem()", "func _bosschest()", "\"11c-shop-held\"", "\"30-totem\"", "\"31-bosschest-spew\""]:
		assert_str(src).contains(f)
