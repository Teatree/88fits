## Pass 138, lane TEXTUI (Garry: "Item descriptions are hard to read, make the text bigger and more clear"; "Hide the clever
## quips, at least from the Gameplay screens (Level Up) and what not. You can keep em in the Collections Screen."): one
## description face in the kit (W.desc_text: R.DESC_PX, R.DESC_WEIGHT, R.DESC_INK) on every screen that shows what an item
## does, and the flavour quip only in the Collection.
extends GdUnitTestSuite


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Run.end()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _wtexts(root: Node) -> Array:
	return root.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is WText and (n as WText).visible)


## Whether any shown WText under `root` says `t` (a flavour line).
func _shows(root: Node, t: String) -> bool:
	for n in _wtexts(root):
		if (n as WText).text.strip_edges() == t.strip_edges():
			return true
	return false


func test_the_kit_has_one_description_face_bigger_than_before() -> void:
	assert_int(R.DESC_PX).is_greater_equal(36)
	assert_int(R.DESC_WEIGHT).is_greater(R.BODY_WEIGHT)
	var d: WText = auto_free(W.desc_text("Lobs 1 stick. Explodes in a 3.6 m radius."))
	assert_int(d.font_size).is_equal(R.DESC_PX)
	assert_object(d.color).is_equal(R.DESC_INK)
	assert_bool(d.wrap).is_true()
	assert_bool(d.bold_numbers).is_true()
	assert_object(d.bold_color).is_equal(R.NUMBER_HI)
	assert_float(d.line_height).is_equal_approx(roundf(R.DESC_PX * R.DESC_LH), 0.01)


func test_level_up_cards_say_what_they_do_in_the_description_face_without_quips() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	var offer := CardPool.level_up_offer(3)
	cs.show_offer(offer, "LEVEL 2!", false)
	await _frames(2)
	var seen := 0
	for c: WCard in cs._cards:
		if c.effect_text:
			assert_int(c.effect_text.font_size).is_equal(R.DESC_PX)
			assert_object(c.effect_text.color).is_equal(R.DESC_INK)
			seen += 1
		if c.changes_box:
			for row in c.changes_box.get_children():
				assert_int((row as WCard.ChangeRow).name_text.font_size).is_equal(WCard.CHANGE_PX)
		if c.def.flavour != "":
			assert_bool(_shows(cs, c.def.flavour)).override_failure_message("quip on %s" % c.def.id).is_false()
	assert_int(seen + cs._cards.filter(func(c) -> bool: return (c as WCard).changes_box != null).size()).is_equal(cs._cards.size())
	# the desert's quip is gone from the level-up's line; the first offers' hint stays
	assert_str(cs.header.line.text).is_not_equal(Loc.t(CardScreen.PICK_KEY))
	assert_bool(cs.header.line.visible).is_false()
	cs.show_offer(offer, "LEVEL 3!", true)
	assert_str(cs.header.line.text).is_equal(Loc.t(CardScreen.HINT_KEY))


func test_the_mutation_offer_cards_are_bigger() -> void:
	assert_int(CardScreen.ROYALE_PATH_TEXT_PX).is_greater(24)


func test_the_chest_says_what_it_holds_in_the_description_face_without_its_quip() -> void:
	_start()
	var pd: PassiveDef = null
	for p: PassiveDef in Registry.passives.values():
		if p.flavour != "" and not p.hidden and not p.is_evolved() and not p.is_line() and p.icon != null:
			pd = p
			break
	assert_object(pd).is_not_null()
	var cs := ChestScreen.new()
	add_child(cs)
	await _frames(1)
	cs.open({"type": "passive", "id": pd.id, "def": pd, "level_from": 0, "level_to": 1, "is_new": true})
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 80:
		await get_tree().process_frame
		if not cs._spinning:
			break
	await _frames(2)
	assert_int(cs._effect.font_size).is_equal(ChestScreen.EFFECT_PX)
	assert_int(ChestScreen.EFFECT_PX).is_greater(34)
	assert_object(cs._effect.color).is_equal(R.DESC_INK)
	assert_str(cs._effect.text).is_not_empty()
	assert_bool(_shows(cs, pd.flavour)).is_false()
	cs.queue_free()


func test_the_stranger_hides_his_quote_and_shows_the_deal_bigger() -> void:
	_start()
	var s := StrangerScreen.new()
	add_child(s)
	await _frames(1)
	var g: PassiveDef = Registry.passive("guillotine")
	s.open({"type": "passive", "id": "guillotine", "def": g, "level_from": 0, "level_to": 2, "is_new": true}, 0.15)
	await _frames(4)
	assert_bool(s._quote.visible).is_false()
	var cards := s.find_children("*", "WCard", true, false)
	assert_int(cards.size()).is_equal(1)
	assert_int((cards[0] as WCard).effect_text.font_size).is_equal(StrangerScreen.ROYALE_EFFECT_PX)
	assert_int(StrangerScreen.ROYALE_EFFECT_PX).is_greater(30)
	if g.flavour != "":
		assert_bool(_shows(s, g.flavour)).is_false()
	# the deal panel stands where the quote stood, clear of the portrait
	assert_float(s._panel.offset_top).is_less_equal(StrangerScreen.PANEL_TOP + W.safe_top() + 0.5)
	s.queue_free()


func test_the_pause_row_and_the_outlaw_sheet_say_no_quip() -> void:
	# the Build row's line in the description face, up to three lines
	var r: WRow = auto_free(WRow.make(Registry.weapon("boomstick"), "Fires 5 pellets in a 35° cone.", null))
	var d := r.find_child("Desc", true, false) as WText
	assert_object(d).is_not_null()
	assert_int(d.font_size).is_equal(WRow.EFFECT_PX)
	assert_int(WRow.EFFECT_PX).is_greater(24)
	assert_int(d.max_lines).is_equal(3)
	# no flavour stands in for a missing line on the pause screen, and the Outlaw sheet has no flavour fallback
	var pause := FileAccess.get_file_as_string("res://ui/PauseScreen.gd")
	assert_str(pause).not_contains("def.flavour")
	var sheet: GDScript = load("res://ui/wanted/WHeroSheet.gd")
	assert_str(str(sheet.call("describe", ContentDef.new(), 1, null))).is_empty()
	assert_int(int(sheet.get_script_constant_map()["R_ITEM_TEXT_PX"])).is_greater(26)
	var heroes: GDScript = load("res://ui/HeroesScreen.gd")
	assert_int(int(heroes.get_script_constant_map()["ITEM_TEXT_PX"])).is_greater(24)
	assert_int(StructureShop.ROYALE_EFFECT_PX).is_greater(28)


func test_the_collection_keeps_the_quip_beside_the_bigger_words() -> void:
	var c: CollectionScreen = load("res://ui/CollectionScreen.tscn").instantiate()
	add_child(c)
	auto_free(c)
	await get_tree().create_timer(0.35).timeout
	var w := Registry.weapon("boomstick")
	assert_str(w.flavour).is_not_empty()
	var card: PanelContainer = auto_free(c._hero_card_royale(w))
	var fl := card.find_child("Flavour", true, false) as WText
	assert_object(fl).is_not_null()
	assert_str(fl.text).is_equal(w.flavour)
	var fx := card.find_child("Effect", true, false) as WText
	assert_int(fx.font_size).is_equal(CollectionScreen.RY_EFFECT_PX)
	assert_int(CollectionScreen.RY_EFFECT_PX).is_greater(28)
	assert_object(fx.color).is_equal(R.DESC_INK)
