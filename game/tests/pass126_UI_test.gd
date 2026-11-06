## Pass 126, lane UI (Garry's "Other Changes", items 1 to 4):
##  - Heroes screen: "Why is the Evolution Item shown as part of Heroes unique items? ... everyone gets this now": no list of a
##    hero's items holds an evolution;
##  - "Lock the Heroes select at the bottom as a separate scrollable area ... 2 rows are displayed fully. The top part can now be
##    cut off. For the top part there is a clear scroll weight thing": the picker lies outside the page's list, two rows whole
##    inside the screen and above the tab bar, a finger moves only the list it came down on, the thumb follows the page;
##  - "make the MM Hero bigger than the Heroes Screen one. Around x1.15", the run-off's quicker fade, the shadow from the soles;
##  - "It's weird that the font changes when I tap that button": one face on every tab, open or not, and every word fits;
##  - "Buy Look button doesn't have coins icon on it": the question's deed wears the coin.
extends GdUnitTestSuite

const SCREEN := "res://ui/HeroesScreen.tscn"
const Heroes := preload("res://ui/HeroesScreen.gd")
const Sheet := preload("res://ui/wanted/WHeroSheet.gd")
const Title := preload("res://ui/TitleScreen.gd")
const Bar := preload("res://ui/wanted/WTabBar.gd")

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_settings_before)


func before_test() -> void:
	# pass 132: Ironwood is free in the game now; this suite's checks of an outlaw sold for gold put him on sale for their time
	Registry.character("ironwood").availability = "purchase"
	Save.data = Save._default()
	Save._dirty = false
	Settings.preview_locked_heroes = false


func after_test() -> void:
	Registry.character("ironwood").availability = "available"
	Settings.preview_locked_heroes = false
	Save.data = Save._default()
	Save._dirty = false


func _screen() -> Control:
	var s: Control = auto_free(load(SCREEN).instantiate())
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _title() -> Control:
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


func _touch(s: Control, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = down
	s.call("_input", e)


func _drag(s: Control, at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = at
	e.relative = rel
	s.call("_input", e)


## A finger down on `from`, up the screen by `by` px in steps, and lifted.
func _swipe(s: Control, from: Vector2, by: float) -> void:
	_touch(s, from, true)
	var p := from
	for k in 8:
		p += Vector2(0.0, -by / 8.0)
		_drag(s, p, Vector2(0.0, -by / 8.0))
	_touch(s, p, false)
	await get_tree().process_frame


# ---------------------------------------------------------------- 1a: no evolution among his items

func test_no_hero_lists_an_evolution_among_his_items() -> void:
	for c: CharacterDef in Registry.sorted_characters():
		for it: Dictionary in Sheet.items_of(c):
			assert_str(str(it["role"])).override_failure_message(c.id).is_not_equal("evolution")
			var d: ContentDef = it["def"]
			if d is WeaponDef:
				assert_bool((d as WeaponDef).is_evolution).override_failure_message("%s lists %s" % [c.id, d.id]).is_false()
	# the Drifter's Revolver was the case Garry saw: its Golden Revolver is on neither the screen nor the pop-up
	Save.data["last_character"] = "drifter"
	var s := await _screen()
	var rev := Registry.weapon("revolver")
	assert_str(rev.evolves_into).is_not_empty()
	assert_object(s.find_child("Item_evolution_" + rev.evolves_into, true, false)).is_null()
	assert_object(s.find_child("Item_start_revolver", true, false)).is_not_null()
	s.call("open_details")
	await get_tree().process_frame
	var sheet: Control = s.get("_sheet")
	assert_object(sheet.find_child("Item_evolution_" + rev.evolves_into, true, false)).is_null()
	assert_object(sheet.find_child("Item_start_revolver", true, false)).is_not_null()


# ---------------------------------------------------------------- 1b: two lists

func test_the_picker_lies_outside_the_page_and_shows_two_rows_whole() -> void:
	var s := await _screen()
	var page: ScrollContainer = s.get("scroll")
	var grid: GridContainer = s.find_child("HeroGrid", true, false)
	var list: ScrollContainer = s.get("grid_scroll")
	assert_object(list).is_not_null()
	assert_bool(page.is_ancestor_of(grid)).is_false()
	assert_bool(list.is_ancestor_of(grid)).is_true()
	assert_bool(page.is_ancestor_of(s.find_child("Items", true, false))).is_true()
	assert_bool(page.is_ancestor_of(s.find_child("Select", true, false))).is_true()
	# every tile of the first two rows, its base too, inside the list; the list on the screen, over the open tab
	var view := list.get_global_rect()
	assert_int(grid.columns * Heroes.PICK_ROWS).is_less_equal(grid.get_child_count())
	for k in grid.columns * Heroes.PICK_ROWS:
		var r := (grid.get_child(k) as Control).get_global_rect()
		assert_bool(view.encloses(Rect2(r.position, r.size + Vector2(0.0, R.PANEL_BASE)))) \
			.override_failure_message("tile %d %s outside %s" % [k, str(r), str(view)]).is_true()
	var vh := s.get_viewport_rect().size.y
	assert_float(view.end.y).is_less_equal(vh - Bar.reach())
	# the page stops where the picker starts (past its entrance, which rises from 40 px lower)
	await get_tree().create_timer(0.35).timeout
	assert_float(page.get_global_rect().end.y).is_less_equal((s.get("picker") as Control).get_global_rect().position.y + 0.5)
	# eight heroes fit: the list has nothing to move, and its thumb says nothing
	assert_bool((s.find_child("HeroThumb", true, false) as WScrollThumb).runs_over()).is_false()


func test_with_more_heroes_the_picker_scrolls_and_still_shows_two_rows() -> void:
	Settings.preview_locked_heroes = true
	var s := await _screen()
	var grid: GridContainer = s.find_child("HeroGrid", true, false)
	var list: ScrollContainer = s.get("grid_scroll")
	assert_int(grid.get_child_count()).is_greater(grid.columns * Heroes.PICK_ROWS)
	assert_float(list.size.y).is_equal_approx(Heroes.picker_view_height(), 0.5)
	assert_bool((s.find_child("HeroThumb", true, false) as WScrollThumb).runs_over()).is_true()


func test_a_finger_moves_only_the_list_it_came_down_on() -> void:
	Settings.preview_locked_heroes = true
	var s := await _screen()
	var page: ScrollContainer = s.get("scroll")
	var list: ScrollContainer = s.get("grid_scroll")
	await _swipe(s, page.get_global_rect().get_center(), 300.0)
	assert_int(page.scroll_vertical).is_greater(100)
	assert_int(list.scroll_vertical).is_equal(0)
	var at := page.scroll_vertical
	await _swipe(s, list.get_global_rect().get_center(), 300.0)
	assert_int(list.scroll_vertical).is_greater(50)
	# the first swipe ran the page to its foot (212 px with this hero's page), where a layout pass may settle it by a pixel
	assert_int(absi(page.scroll_vertical - at)).is_less_equal(1)


func test_a_tile_tapped_with_the_page_scrolled_shows_the_hero_and_the_picker_stays() -> void:
	Settings.preview_locked_heroes = true
	Save.heroes_owned().append("astro")
	var s := await _screen()
	var page: ScrollContainer = s.get("scroll")
	var list: ScrollContainer = s.get("grid_scroll")
	page.scroll_vertical = 300
	list.scroll_vertical = 60
	await get_tree().process_frame
	var tile: WTap = s.find_child("Hero_astro", true, false)
	tile.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str((s.get("shown") as CharacterDef).id).is_equal("astro")
	assert_int(list.scroll_vertical).is_equal(60)
	await get_tree().create_timer(0.35).timeout
	assert_int(page.scroll_vertical).is_equal(0)
	# the gold edge moved to his tile in the same grid
	assert_int((s.find_child("Hero_astro", true, false) as WTap).box.inner).is_equal(5)


func test_the_thumb_follows_the_page_and_says_when_there_is_more() -> void:
	var s := await _screen()
	var page: ScrollContainer = s.get("scroll")
	var thumb: WScrollThumb = s.get("page_thumb")
	assert_int(thumb.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_float(thumb.size.x).is_equal_approx(R.SCROLL_THUMB_W, 0.5)
	assert_bool(thumb.runs_over()).is_true()
	assert_bool(thumb.more_below()).is_true()
	var fade: Control = s.find_child("PageFade", true, false)
	assert_bool(fade.visible).is_true()
	var top_y := thumb.thumb_rect().position.y
	assert_float(top_y).is_equal_approx(R.SCROLL_THUMB_INSET, 0.5)
	# at the foot: the thumb on the track's foot, no arrow, no fade
	var bar := page.get_v_scroll_bar()
	page.scroll_vertical = int(bar.max_value)
	await get_tree().process_frame
	assert_bool(thumb.more_below()).is_false()
	assert_bool(fade.visible).is_false()
	var bit := thumb.thumb_rect()
	assert_float(bit.end.y).is_equal_approx(thumb.track_rect().end.y - R.SCROLL_THUMB_INSET, 1.0)
	assert_float(bit.size.y).is_greater_equal(minf(R.SCROLL_THUMB_MIN, thumb.track_rect().size.y))
	# in the gutter: clear of the page's words, inside the sheet
	var words: Control = s.find_child("Items", true, false)
	assert_float(thumb.get_global_rect().position.x).is_greater_equal(words.get_global_rect().end.x)
	var sheet: Control = s.get("board_sheet_node")
	assert_float(thumb.get_global_rect().end.x).is_less_equal(sheet.get_global_rect().end.x)


func test_a_camera_cutout_moves_the_page_not_the_picker() -> void:
	Settings.top_inset = 130
	var s := await _screen()
	var page: ScrollContainer = s.get("scroll")
	assert_float(page.get_global_rect().position.y).is_greater_equal(130.0)
	var view: Rect2 = (s.get("grid_scroll") as Control).get_global_rect()
	assert_float(view.end.y).is_less_equal(s.get_viewport_rect().size.y - Bar.reach())
	Settings.top_inset = int(_settings_before.get("top_inset", -1))


# ---------------------------------------------------------------- 2: the main menu's hero

func test_the_main_menus_hero_is_about_a_seventh_bigger_than_the_heroes_screens() -> void:
	var k: float = Title.RY_FIGURE_H / Heroes.FIGURE_PX
	assert_float(k).is_between(1.13, 1.17)
	var t := await _title()
	assert_float((t.hero_figure_rect() as Rect2).size.y).is_equal_approx(Title.RY_FIGURE_H, 0.5)
	# nothing he stands among is under him: the wordmark above, the arrows beside him
	var fig: Rect2 = t.hero_figure_rect()
	assert_float((t.find_child("Tagline", true, false) as Control).get_global_rect().end.y).is_less(fig.position.y)
	assert_float((t.find_child("Prev", true, false) as Control).get_global_rect().end.x).is_less(fig.position.x)
	assert_float((t.find_child("Next", true, false) as Control).get_global_rect().position.x).is_greater(fig.end.x)
	assert_float((t.find_child("Name", true, false) as Control).get_global_rect().position.y).is_greater(fig.end.y)


func test_he_fades_out_quickly_and_comes_in_whole() -> void:
	Save.heroes_owned().append("astro")
	var t := await _title()
	var leaving: Control = t.get("_figure")
	t.call("_step", 1)
	var coming: Control = t.get("_figure")
	assert_object(coming).is_not_equal(leaving)
	assert_float(coming.modulate.a).is_equal_approx(1.0, 0.001)
	await get_tree().create_timer(Title.RY_RUN_OUT * Title.RY_RUN_FADE + 0.05).timeout
	if is_instance_valid(leaving):
		assert_float(leaving.modulate.a).is_equal_approx(0.0, 0.001)
	assert_float(coming.modulate.a).is_equal_approx(1.0, 0.001)
	assert_float(Title.RY_RUN_OUT).is_less(0.44)
	assert_float(Title.RY_RUN_IN).is_equal_approx(0.62, 0.001)


func test_his_shadow_starts_at_his_soles() -> void:
	assert_float(TitleStage.FIGURE_SOLE).is_less(TitleStage.FIGURE_FEET)
	var t := await _title()
	var f: Control = t.get("_figure")
	assert_float(f.call("soles").y).is_equal_approx(f.size.y * TitleStage.FIGURE_SOLE, 0.01)
	var contact: Control = f.get_node_or_null("Contact")
	if contact:
		assert_float(contact.position.y + contact.size.y * 0.5).is_equal_approx(f.size.y * TitleStage.FIGURE_SOLE, 0.5)


# ---------------------------------------------------------------- 3: the tab bar's one face

func test_every_tab_wears_the_same_face_open_or_not_and_every_word_fits() -> void:
	for active: String in Bar.TABS:
		var b: Control = auto_free(Bar.make(active))
		b.size = Vector2(1080.0, Bar.reach())
		add_child(b)
		await get_tree().process_frame
		for id: String in Bar.TABS:
			var t: WTap = b.call("tab", id)
			var w: WText = t.find_child("Word", true, false)
			assert_bool(R.is_display(w.font)).override_failure_message("%s under %s" % [id, active]).is_true()
			assert_float(w.text_width()).override_failure_message("%s under %s" % [id, active]).is_less_equal(t.size.x - 8.0)
			if id == active:
				assert_int(w.font_size).is_less_equal(R.DOCK_WORD_ACTIVE_PX)
			else:
				assert_int(w.font_size).is_less_equal(R.DOCK_WORD_PX)


# ---------------------------------------------------------------- 4: the coin on the question's deed

func _has_coin(b: Control) -> bool:
	return not b.find_children("*", "WCoin", true, false).is_empty()


func _fadeaway_on_sale() -> CharacterDef:
	var fad := Registry.character("fadeaway")
	Save.heroes_owned().append("fadeaway")
	for q: String in ["unlock_fadeaway", "skin_fadeaway_fad_b"]:
		(Save.data["quests_done"] as Array).append(q)
	return fad


func test_the_buy_look_question_wears_the_coin_on_the_heroes_screen() -> void:
	var fad := _fadeaway_on_sale()
	Save.data["gold"] = fad.skin_price("FAD-B") + 100
	var s := await _screen()
	s.call("show_hero", fad)
	await get_tree().process_frame
	assert_str(Registry.skin_state(fad, "FAD-B")).is_equal("buyable")
	s.call("ask_buy_look", "FAD-B")
	await get_tree().process_frame
	var b: WButton = WConfirm.current(s).button("confirm")
	assert_str(b.role).is_equal(WButton.GREEN)
	assert_bool(_has_coin(b)).is_true()
	assert_str(b.label_text()).is_equal("%s · BUY" % W.num(fad.skin_price("FAD-B")))


func test_the_buy_look_question_wears_the_coin_on_the_details_pop_up() -> void:
	var fad := _fadeaway_on_sale()
	Save.data["gold"] = fad.skin_price("FAD-B") + 100
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var sh: Control = Sheet.open(host, fad, false)
	await get_tree().process_frame
	sh.call("ask_buy_look", "FAD-B")
	await get_tree().process_frame
	var ask := WConfirm.current(sh)
	assert_object(ask).is_not_null()
	assert_bool(_has_coin(ask.button("confirm"))).is_true()


func test_the_buy_hero_questions_wear_the_coin_too() -> void:
	var iron := Registry.character("ironwood")
	Save.data["gold"] = iron.price + 100
	var s := await _screen()
	s.call("show_hero", iron)
	await get_tree().process_frame
	s.call("ask_buy")
	await get_tree().process_frame
	assert_bool(_has_coin(WConfirm.current(s).button("confirm"))).is_true()
	WConfirm.dismiss(s)
	var t := await _title()
	t.set("_index", (t.get("_heroes") as Array).find(iron))
	t.call("ask_buy")
	await get_tree().process_frame
	assert_bool(_has_coin(WConfirm.current(t).button("confirm"))).is_true()


func test_short_of_a_look_the_price_stays_grey_with_the_amount_in_red() -> void:
	var fad := _fadeaway_on_sale()
	var price := fad.skin_price("FAD-B")
	Save.data["gold"] = price - 10
	var s := await _screen()
	s.call("show_hero", fad)
	await get_tree().process_frame
	s.call("open_looks")
	await get_tree().process_frame
	var tile: WTap = (s.get("looks_grid") as Control).get_node("Look_FAD-B")
	var tag: Control = tile.find_child("Price", true, false)
	assert_object(tag).is_not_null()
	assert_bool(_has_coin(tag)).is_true()
	assert_bool((tag.find_child("Word", true, false) as WText).color.is_equal_approx(R.SHORT_INK)).is_true()
	assert_str((tile.find_child("Short", true, false) as WText).text).is_equal("10 short")
	# a tap only says no: no question
	s.call("ask_buy_look", "FAD-B")
	await get_tree().process_frame
	assert_bool(bool(s.call("looks_open"))).is_true()


func test_a_price_buttons_parts_are_the_ones_the_question_wears() -> void:
	var parts := WButton.price_parts(1500, "BUY", R.MODAL_BUTTON_PX, "gold")
	assert_bool((parts[0] as Dictionary).has("coin")).is_true()
	assert_str(str(parts[1])).is_equal("1,500 · BUY")
	var b := WButton.price(1500, "BUY")
	assert_str(b.label_text()).is_equal("1,500 · BUY")
	assert_bool(_has_coin(b)).is_true()
	b.free()
	# short, the grey keeps the amount in red and drops the word (WButton.price's rule)
	var g := WButton.price(1500, "BUY", WButton.GREEN, R.PRICE_PX, 10)
	assert_str(g.label_text()).is_equal("1,500")
	assert_bool(g.ink_override.is_equal_approx(R.SHORT_INK)).is_true()
	assert_bool(_has_coin(g)).is_true()
	g.free()
