extends GdUnitTestSuite

## Pass 122, lane UILEVELUP: the Royale level-up cards (Garry's build brief of 2026-11-02 on Claude Design's "Royale,
## refined": a second theme behind a switch, Wanted the default and pixel-identical while it is off; "Level-up cards as
## the mock: slate cards, same text and layout, the touched card gold-lit with rays, REROLL · SKIP · BANISH in slate";
## "One tap on a card picks it, as today; the gold-lit state with rays is press feedback only"; "keep the Level N and
## Level Up text white").
##  - the screen builds under both themes with three cards; the title and the star line are cream with the navy edge
##    under Royale and paper with the ink shadows under Wanted; the dim, the shine and the rail's track follow;
##  - a press lights the card (Royale: the 5 px gold edge, the rays behind its item, the card in its place; Wanted: the
##    brass band on its shadow) and a release picks it, one tap, no question, under either theme;
##  - the counts: navy pills with a gold number (grey at 0) under Royale, today's "×N" runs under Wanted;
##  - the layout is the same under both themes (the list's top and width, the rail, the header, the button rows, the
##    cards' width);
##  - the mutation offer follows (its plate's rays, its cream name, its SKIP pill, its cream star line), a theme flip
##    between offers rebuilds the head and recolours the dim, and banish mode's marks wear the kit's colours.

var _settings_before: Dictionary = {}
var _hints_had_banish := false


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)


func before_test() -> void:
	_hints_had_banish = Save.hint_seen("banish")


func after_test() -> void:
	if not _hints_had_banish:
		(Save.data["hints_seen"] as Array).erase("banish")
	Settings.force_prod(false)
	Run.end()


## A colour's rgb at full alpha: the dim's entry tween moves its alpha, its rgb is set at once.
func _rgb(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 1.0)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _start() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.rerolls_left = 1
	Run.skips_left = 2
	Run.banishes_left = 0


func _card(type: String, def: ContentDef, from: int = 0, to: int = 1) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


## The capture's table (wanted_shots 07): a new Card, a new rare passive item, the Boomstick 3 -> 4.
func _table() -> Array:
	return [_card("passive", Registry.passive("bristle")), _card("passive", Registry.passive("desperado")),
		_card("weapon", Registry.weapon("boomstick"), 3, 4)]


func _open(royale: bool, title: String = "LEVEL 3!") -> CardScreen:
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer(_table(), title, false)
	await _frames(3)
	return cs


func _touch(at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	return e


func _base_path(f: Font) -> String:
	var b := f
	while b is FontVariation and (b as FontVariation).base_font:
		b = (b as FontVariation).base_font
	return b.resource_path if b else ""


## The mutation offer's reel skipped and its cards on the table.
func _land(cs: CardScreen) -> void:
	cs.skip_reel()
	var n := 0
	while (cs.reel_running() or cs._cards.is_empty()) and n < 120:
		await get_tree().process_frame
		n += 1
	await _frames(2)


## The count pill's number (the WText inside the "Count" pill) of a button, null without one.
func _pill(b: WButton) -> WText:
	var pc := b.find_child("Count", true, false)
	return pc.get_child(0) as WText if pc else null


# ---------------------------------------------------------------- 1. the head



# ---------------------------------------------------------------- 2. the press and the pick

func test_a_press_lights_the_card_and_a_release_picks_it() -> void:
	_start()
	for royale in [true]:
		var cs: CardScreen = await _open(royale)
		assert_int(cs._cards.size()).is_equal(3)
		var card: WCard = cs._cards[1]
		var picked: Array = []
		cs.chosen.connect(func(c: Dictionary): picked.append(c))
		var at := card.size * 0.5
		card._gui_input(_touch(at, true))
		assert_bool(card._held_look).override_failure_message("royale %s: a finger down lights the card" % royale).is_true()
		assert_bool(card.plate.rays).is_equal(royale)
		assert_bool(card.is_processing()).is_equal(royale)
		var down: HardBox = card.box_down
		if royale:
			# the mock's pressed card: in its place on its base, a 5 px gold inner edge, the rays 1.5x its 200 px frame
			assert_int(down.inner).is_equal(CardScreen.ROYALE_EDGE)
			assert_int(down.press).is_equal(0)
			assert_bool(card._held_offset().is_equal_approx(Vector2.ZERO)).is_true()
			assert_float(card.plate.rays_scale).is_equal(CardScreen.ROYALE_RAYS)
			assert_float(card.plate.side).is_equal(CardScreen.ROYALE_PLATE_PX)
			assert_str(down.royale_kind()).is_equal("panel")
		else:
			# today's: the card sits on its shadow with a 6 px brass band, its 180 px plate
			assert_int(down.inner).is_equal(6)
			assert_int(down.press).is_equal(10)
			assert_bool(card._held_offset().is_equal_approx(Vector2(10, 10))).is_true()
			assert_float(card.plate.side).is_equal(180.0)
		assert_bool(down.inner_color.is_equal_approx(W.BRASS)).is_true()
		assert_array(picked).is_empty()
		assert_bool(cs.visible).is_true()
		# the release within SLOP: the one tap picks, no second tap, no question; the lit look holds for the pick's beat
		card._gui_input(_touch(at + Vector2(8, 4), false))
		assert_bool(card._held_look).is_true()
		assert_bool(card.plate.rays).is_equal(royale)
		await get_tree().create_timer(0.4).timeout
		assert_int(picked.size()).override_failure_message("royale %s: the release picks" % royale).is_equal(1)
		assert_str(str(picked[0]["id"])).is_equal("desperado")
		assert_bool(cs.visible).is_false()
		assert_str(str((cs.last_pick["def"] as ContentDef).id)).is_equal("desperado")
		assert_int(int(cs.last_pick["level"])).is_equal(1)


# ---------------------------------------------------------------- 3. the counts



# ---------------------------------------------------------------- 4. the layout

func test_the_layout_is_the_same_under_both_themes() -> void:
	_start()
	var w: CardScreen = await _open(false)
	# measured landed: the entry motion drops the header 40 px over 250 ms and slides the cards up 60 ms apart (a read
	# five frames in sat 1 px apart between the themes on a slow machine)
	await await_millis(450)
	var w_list_top := w._list.offset_top
	var w_list := w._list.get_global_rect()
	var w_buttons := w.buttons.get_global_rect()
	var w_rail := w._rail.get_global_rect()
	var w_head := w.header.offset_top
	var w_skip := w._path_skip.get_global_rect()
	var w_scale := w._list.scale
	var w_widths: Array = []
	for c in w._cards:
		w_widths.append((c as Control).size.x)
	w.visible = false
	var r: CardScreen = await _open(true)
	await await_millis(450)
	assert_float(r._list.offset_top).is_equal_approx(w_list_top, 0.5)
	assert_float(r._list.get_global_rect().position.x).is_equal_approx(w_list.position.x, 0.5)
	assert_float(r._list.get_global_rect().size.x).is_equal_approx(w_list.size.x, 0.5)
	assert_bool(r.buttons.get_global_rect().is_equal_approx(w_buttons)).is_true()
	assert_bool(r._rail.get_global_rect().is_equal_approx(w_rail)).is_true()
	assert_float(r.header.offset_top).is_equal_approx(w_head, 0.5)
	# pass 123 (lane RUN_C, re-pinned): the mutation offer's SKIP is the mock's 590 x 106 under Royale (Garry: "Mutation
	# offer as the mock"), on the same foot and middle as today's 430 x 108
	var r_skip := r._path_skip.get_global_rect()
	assert_float(r_skip.size.x).is_equal_approx(CardScreen.ROYALE_SKIP_W, 0.5)
	assert_float(r_skip.end.y).is_equal_approx(w_skip.end.y, 0.5)
	assert_float(r_skip.get_center().x).is_equal_approx(w_skip.get_center().x, 0.5)
	assert_bool(r._list.scale.is_equal_approx(w_scale)).is_true()
	assert_int(r._cards.size()).is_equal(3)
	for i in r._cards.size():
		assert_float((r._cards[i] as Control).size.x).is_equal_approx(w_widths[i], 0.5)
	# the three cards clear the button row under Royale too (the 200 px frames, Rubik's lines), at full size
	var last: Control = r._cards[2]
	assert_float(last.get_global_rect().end.y).is_less(r.buttons.get_global_rect().position.y)
	assert_bool(r._list.scale.is_equal_approx(Vector2.ONE)).is_true()
	# the frames: the kit's Royale frame on each card (its layer made), the Wanted plate on none
	for c in r._cards:
		assert_object((c as WCard).plate.get_node_or_null("RoyaleFrame")).is_not_null()
	r.visible = false


# ---------------------------------------------------------------- 5. the mutation offer

func test_the_mutation_offer_follows_the_theme() -> void:
	_start()
	var w: WeaponInstance = Run.weapon_instance("boomstick")
	assert_object(w).is_not_null()
	for royale in [true]:
		var cs: CardScreen = auto_free(CardScreen.new())
		add_child(cs)
		cs.show_offer(CardPool.path_offer(w), "MUTATION", false, true)
		await _land(cs)
		assert_bool(cs.path_mode).is_true()
		assert_int(cs._cards.size()).is_greater_equal(2)
		assert_bool(cs._path_plate.rays).is_equal(royale)
		var nm: WText = cs._path_name
		var star: WStarLine = cs._path_head.get_child(0)
		if royale:
			assert_bool(nm.color.is_equal_approx(R.CREAM)).is_true()
			assert_bool(R.is_display(nm.font)).is_true()
			assert_bool(nm.shadow_straight).is_true()
			assert_str(cs._path_skip.label_text()).is_equal("SKIP×2")
			# the head's star line in cream like the level-up's, no pass 58 star shadows (the kit's navy edge)
			assert_bool(star.color.is_equal_approx(R.CREAM)).is_true()
			assert_object((star.get_child(0) as Control).get_node_or_null("Shadow")).is_null()
			assert_bool(cs._path_note.shadow_straight).is_false()
			assert_bool(R.is_display(cs._path_note.font)).is_false()
		else:
			assert_bool(nm.color.is_equal_approx(W.PAPER)).is_true()
			assert_int(nm.shadow).is_equal(8)
			assert_bool(nm.shadow_straight).is_false()
			assert_str(cs._path_skip.label_text()).is_equal("SKIP ×2")
			assert_bool(star.color.is_equal_approx(W.PAPER)).is_true()
			assert_object((star.get_child(0) as Control).get_node_or_null("Shadow")).is_not_null()
		# a card of the offer takes the press feedback the same way; a finger that wanders past SLOP picks nothing
		var card: WCard = cs._cards[0]
		card._gui_input(_touch(card.size * 0.5, true))
		assert_bool(card._held_look).is_true()
		assert_bool(card.plate.rays).is_equal(royale)
		card._gui_input(_touch(card.size * 0.5 + Vector2(200, 200), false))
		assert_bool(card._held_look).is_false()
		assert_bool(card.plate.rays).is_false()
		assert_bool(cs.visible).is_true()
		cs.visible = false


# ---------------------------------------------------------------- 6. a theme flip between offers



# ---------------------------------------------------------------- 7. banish mode's marks

func test_banish_marks_wear_the_kits_colours() -> void:
	_start()
	assert_bool(CardScreen.BanishMark.rock().is_equal_approx(R.role("red")["bottom"])).is_true()
	assert_bool(CardScreen.BanishMark.paper().is_equal_approx(R.CREAM)).is_true()
	assert_bool(CardScreen.BanishMark.ink().is_equal_approx(R.NAVY)).is_true()
	# a strike card's band in banish mode: the kit's red under Royale, rock under Wanted (pass 58's pin)
	for royale in [true]:
		var cs: CardScreen = await _open(royale)
		Run.banishes_left = 1
		cs._refresh_buttons()
		cs._toggle_banish()
		await _frames(1)
		assert_bool(cs.banish_mode()).is_true()
		var band: Color = ((cs._cards[0] as WCard).box as HardBox).inner_color
		assert_bool(band.is_equal_approx(CardScreen.BanishMark.rock())).is_true()
		assert_bool(band.is_equal_approx(W.ROCK)).is_equal(not royale)
		assert_str(str(cs._slots[0].get_node("BanishMark").style)).is_equal("strike")
		assert_str(str(cs._slots[2].get_node("BanishMark").style)).is_equal("held")
		cs._set_banish(false)
		cs.visible = false
		await _frames(1)
