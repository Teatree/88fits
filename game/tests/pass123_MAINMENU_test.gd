## Pass 123, lane MAINMENU: the main menu in the Royale layout (the mock 5_Main_menu; Garry: "Main menu in the new
## layout: wordmark, hero with ‹ ›, name, trait pill, DETAILS (opens Hero details), gold START to Select Stage, docked
## bottom bar, Settings behind ≡, wallet top right."; "Leave the main menu's sides empty"; "Show STORE as a locked tab";
## "Move the run-history line ... to the Stages screen's header"), behind the Royale switch; under Wanted the title is
## today's.
##  - the pieces and their places on the 1080 x 1920 canvas, the backdrop's title kind with its disc, no TitleStage;
##  - Wanted's pieces gone under Royale (plaque, drawer button, dots, menu row, map line), kept under Wanted;
##  - the hero as a run draws him: his played look's idle frame, the figure's size and soles on the disc, its speed;
##  - the trait pill's words from data ("per Level", never "/ LV"), DETAILS opening the sheet, START's flow and LOCKED;
##  - a hero not owned: UNKNOWN, the black figure; on sale the green price · BUY (short: grey and "n short"), the shared
##    confirm's buy, the deed and the mask lifting; locked: the requirement and the padlock;
##  - ‹ › and the HEROES tab following the shown hero; the Upgrade mark's rule lives once; the capture tools' states.
extends GdUnitTestSuite

const Stage := preload("res://ui/TitleStage.gd")
const Title := preload("res://ui/TitleScreen.gd")
const TabBarScript := preload("res://ui/wanted/WTabBar.gd")

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"debug": Settings.debug_mode, "preview": Settings.preview_locked_heroes,
		"inset": Settings.top_inset}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	W.bottom_inset_override = 0.0
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Stage.forget()
	Settings.debug_mode = bool(_keep["debug"])
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	W.bottom_inset_override = -1.0
	Save.data = Save._default()
	Save._dirty = false
	if Save.sandboxed():
		Save.end_sandbox()


func _title(royale: bool, style: String = "painted") -> Control:
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	# the lower block's entrance (up 40 px over 0.25 s) is over before anything is measured
	await get_tree().create_timer(0.32).timeout
	await get_tree().process_frame
	return t


func _hero(id: String) -> CharacterDef:
	var c: CharacterDef = Registry.character(id)
	assert_object(c).override_failure_message(id).is_not_null()
	return c


## The first hero in Garry's order whose state on the save now is `state` (null when none).
func _first_in(state: String) -> CharacterDef:
	for c: CharacterDef in Registry.sorted_characters():
		if Registry.hero_state(c) == state:
			return c
	return null


func _show(t: Control, c: CharacterDef) -> void:
	var i: int = (t._heroes as Array).find(c)
	assert_int(i).override_failure_message("%s is not on the carousel" % c.id).is_greater_equal(0)
	t._index = i
	t._show_hero(0)
	t._place()


func _texts(n: Node) -> String:
	var s := ""
	for c in n.find_children("*", "", true, false):
		if c is WText:
			var w := c as WText
			if w.runs.is_empty():
				s += w.text
			else:
				for r in w.runs:
					s += str(r[0])
	return s


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# ---------------------------------------------------------------- the layout

func test_the_royale_title_is_the_mocks_new_layout() -> void:
	var t := await _title(true)
	# the backdrop's title kind (its disc), no live stage and no paper wash
	var bd: Control = t.find_child("RoyaleBackdrop", false, false)
	assert_object(bd).is_not_null()
	assert_int(bd.get_index()).is_equal(0)
	if bd.has_method("disc_center"):
		assert_str(str(bd.get("kind"))).is_equal("title")
		assert_vector(bd.call("disc_center")).is_equal(Vector2(540, 1160))
	assert_object(t.find_child("TitleStage", false, false)).is_null()
	assert_object(t._wash_rect).is_null()
	# ≡ top left: a slate square opening Settings
	var menu: WButton = t.find_child("MenuButton", false, false)
	assert_object(menu).is_not_null()
	assert_vector(menu.position).is_equal(Title.RY_MENU_POS)
	assert_vector(menu.size).is_equal(Vector2(Title.RY_MENU, Title.RY_MENU))
	assert_str(menu.role).is_equal(WButton.SLATE)
	assert_object(menu.find_child("Glyph_menu", true, false)).is_not_null()
	assert_int(menu.pressed.get_connections().size()).is_greater(0)
	# the wallet top right: 40 in, 64 down, the purse in it
	var wallet: Control = t.find_child("Wallet", false, false)
	assert_object(wallet).is_not_null()
	assert_float(wallet.position.x + wallet.size.x).is_equal_approx(1080.0 - Title.RY_WALLET.x, 0.5)
	assert_float(wallet.position.y).is_equal(Title.RY_WALLET.y)
	assert_str((wallet.find_child("Amount", true, false) as WText).text).is_equal(W.num(Save.gold()))
	# the wordmark: OUTLAW in cream Ultra 170 at 150, SURVIVORS in gold over it at 330
	var logo: WText = t.find_child("Logo", true, false)
	assert_str(logo.text).is_equal(W.GAME_WORD.to_upper())
	assert_int(logo.font_size).is_equal(Title.RY_LOGO_PX)
	assert_bool(R.is_display(logo.font)).is_true()
	assert_bool(logo.color.is_equal_approx(R.CREAM)).is_true()
	assert_float(logo.get_global_rect().position.y).is_equal(Title.RY_LOGO_TOP)
	var tag: WStarLine = t.find_child("Tagline", true, false)
	assert_str(tag.text()).is_equal(W.GAME_LINE.to_upper())
	assert_bool(tag.color.is_equal_approx(R.GOLD_TEXT)).is_true()
	# the hero between ‹ › on the disc; the name; the pill and DETAILS; START; the tab bar
	var prev: WButton = t.find_child("Prev", true, false)
	var nxt: WButton = t.find_child("Next", true, false)
	assert_vector(prev.get_global_rect().position).is_equal(Vector2(540.0 - Title.RY_ARROW_X, 1160.0 - Title.RY_ARROW_UP))
	assert_float(nxt.get_global_rect().end.x).is_equal(540.0 + Title.RY_ARROW_X)
	assert_vector(prev.size).is_equal(Vector2(Title.RY_ARROW, Title.RY_ARROW))
	assert_str(prev.role).is_equal(WButton.SLATE)
	var nm: WText = t.find_child("Name", false, false)
	assert_float(nm.position.y).is_equal(1160.0 + Title.RY_NAME_DOWN)
	assert_int(nm.font_size).is_equal(Title.RY_NAME_PX)
	assert_bool(nm.color.is_equal_approx(R.CREAM)).is_true()
	var row: Control = t.find_child("TraitRow", false, false)
	assert_float(row.get_global_rect().get_center().x).is_equal_approx(540.0, 1.0)
	var det: WButton = t.find_child("Details", false, false)
	assert_str(det.role).is_equal(WButton.BLUE)
	assert_vector(det.size).is_equal(Title.RY_DETAILS)
	var start: WButton = t.find_child("Start", false, false)
	assert_str(start.role).is_equal(WButton.GOLD)
	assert_str(start.label_text()).is_equal("START")
	assert_vector(start.position).is_equal(Vector2(45, 1500))
	assert_vector(start.size).is_equal(Title.RY_START)
	var bar: Control = t.find_child("TabBar", false, false)
	assert_object(bar).is_not_null()
	assert_str(str(bar.get("active"))).is_equal("battle")
	assert_bool(bar.call("is_locked", "store")).is_true()
	# START clears the tab bar's rise
	assert_float(start.position.y + start.size.y + R.BUTTON_BASE + R.BUTTON_NAVY_BASE).is_less(1920.0 - TabBarScript.reach())
	# the debug arena beside ≡, never over the wordmark
	var arena: WButton = t.find_child("ArenaButton", false, false)
	assert_vector(arena.position).is_equal(Title.RY_ARENA_POS)
	assert_float(arena.get_global_rect().end.y).is_less(Title.RY_LOGO_TOP)
	assert_float(arena.get_global_rect().end.x).is_less(wallet.position.x)


func test_start_clears_the_gesture_bar_and_the_top_row_the_camera_cutout() -> void:
	W.bottom_inset_override = 48.0
	Settings.top_inset = 130
	var t := await _title(true)
	var start: WButton = t.find_child("Start", false, false)
	assert_float(start.position.y).is_equal(1920.0 - 48.0 - Title.RY_START_UP)
	assert_float(start.position.y + start.size.y + R.BUTTON_BASE + R.BUTTON_NAVY_BASE).is_less(1920.0 - TabBarScript.reach())
	var menu: Control = t.find_child("MenuButton", false, false)
	assert_float(menu.position.y).is_equal(Title.RY_MENU_POS.y + W.safe_top())
	assert_float((t.find_child("Logo", true, false) as Control).get_global_rect().position.y).is_equal(Title.RY_LOGO_TOP + W.safe_top())
	# the hero group keeps the backdrop's disc (the cutout moves only the top row and the wordmark)
	assert_float(t.hero_figure_rect().end.y).is_equal_approx(1160.0 - Title.RY_FEET_UP, 0.5)
	assert_float((t.find_child("Tagline", true, false) as Control).get_global_rect().end.y).is_less(t.hero_figure_rect().position.y)




# ---------------------------------------------------------------- the hero

func test_the_hero_is_drawn_as_a_run_draws_him_small_on_the_disc() -> void:
	var t := await _title(true)
	var c: CharacterDef = t._heroes[t._index]
	var look := Registry.played_look(c)
	var fig = t.find_child("HeroFigure", true, false)
	assert_object(fig).is_not_null()
	assert_object(fig.tex).is_equal(look.sprite)
	# the front idle: its first frame and count in the strip's order
	var k := 0
	var want := -1
	var count := 0
	var anim := ""
	for a in ["idle_f", "idle_fd", "idle"]:
		if int(look.anims.get(a, 0)) > 0:
			anim = a
			break
	for a in Stage.ORDER:
		if a == anim:
			want = k
			count = int(look.anims[a])
		k += int(look.anims.get(a, 0))
	assert_int(fig.first).is_equal(want)
	assert_int(fig.count).is_equal(count)
	var cols: int = look.strip_cols if look.strip_cols > 0 else k
	assert_int(fig.cols).is_equal(cols)
	assert_float(fig.cell.x).is_equal_approx(float(look.sprite.get_width()) / float(cols), 0.01)
	# his figure RY_FIGURE_H tall, his soles RY_FEET_UP over the disc's centre, his middle on it
	var r: Rect2 = t.hero_figure_rect()
	assert_float(r.size.y).is_equal_approx(Title.RY_FIGURE_H, 0.5)
	assert_float(r.end.y).is_equal_approx(1160.0 - Title.RY_FEET_UP, 0.5)
	assert_float(r.get_center().x).is_equal_approx(540.0, 0.5)
	# his idle steps at the look's speed, and only redraws on a new frame
	if count > 1:
		var f0: int = fig.frame
		fig._process(1.0 / fig.fps + 0.001)
		assert_int(fig.frame).is_equal((f0 + 1) % count)
		assert_float(fig.fps).is_equal(Title.HeroFigure.speed_of(look.fps, anim))
	assert_float(Title.HeroFigure.speed_of({}, "idle_f")).is_equal(Title.RY_IDLE_FPS)
	assert_float(Title.HeroFigure.speed_of({"idle": 7}, "idle_f")).is_equal(7.0)
	assert_bool(fig.tint.is_equal_approx(Color.WHITE)).is_true()


func test_prev_next_and_the_heroes_tab_follow_the_shown_hero() -> void:
	# two owned heroes: the Drifter and a bought one
	var other := _first_in("buyable")
	assert_object(other).is_not_null()
	Save.heroes_owned().append(other.id)
	var t := await _title(true)
	var n: int = (t._heroes as Array).size()
	assert_int(n).is_greater(1)
	var i0: int = t._index
	(t.find_child("Next", true, false) as WButton).pressed.emit()
	assert_int(t._index).is_equal(posmod(i0 + 1, n))
	var shown: CharacterDef = t._heroes[t._index]
	if not t._is_locked(shown):
		assert_str(str(Save.data["last_character"])).is_equal(shown.id)
		var d = TabBarScript.hero_def()
		assert_str(t._tab_hero).is_equal("%s:%s" % [d.id, d.look_code()])
		assert_str(d.id).is_equal(shown.id)
	(t.find_child("Prev", true, false) as WButton).pressed.emit()
	assert_int(t._index).is_equal(i0)
	# one tab bar at a time, the last thing on the screen
	await get_tree().process_frame
	var bars := 0
	for ch in t.get_children():
		if ch.name == "TabBar" and not ch.is_queued_for_deletion():
			bars += 1
	assert_int(bars).is_equal(1)
	# the swipe band covers the hero and the trait row
	var band: Rect2 = Rect2(t._hero_row.position, t._hero_row.size)
	assert_bool(band.encloses(t.hero_figure_rect())).is_true()
	assert_bool(band.encloses((t.find_child("TraitRow", false, false) as Control).get_global_rect())).is_true()


# ---------------------------------------------------------------- the words

func test_the_trait_pill_reads_per_level_from_data() -> void:
	var t := await _title(true)
	var c: CharacterDef = t._heroes[t._index]
	var pill: Control = t._trait_pill
	assert_object(pill).is_not_null()
	assert_str(pill.name).is_equal("Pill")
	var words := _texts(pill)
	assert_str(words).not_contains("/ LV")
	for st in t._stats_of(c):
		assert_str(words).contains(str(st[0]))
		assert_str(words).contains(Title.per_level(str(st[1])))
	if not c.level_trait.is_empty():
		assert_str(words).contains("per Level")
		assert_str(words).contains(TextGen.hero_step(c.level_trait[0]))
	assert_str(Title.per_level("CRIT / LV")).is_equal("CRIT per Level")
	assert_str(Title.per_level("SPEED")).is_equal("SPEED")
	# the name in capitals ("The Drifter" as the title always called him)
	var shown := ("The " + c.display_name) if c.id == "drifter" else c.display_name
	assert_str(t._name.text).is_equal(shown.to_upper())
	# DETAILS opens his sheet
	t._details_btn.pressed.emit()
	await get_tree().process_frame
	assert_bool(t.sheet_open()).is_true()
	assert_object(t._sheet.get("hero")).is_equal(c)
	t._sheet.call("close")


# ---------------------------------------------------------------- heroes not owned

func test_a_hero_on_sale_is_bought_through_the_shared_confirm() -> void:
	var sale := _first_in("buyable")
	assert_object(sale).is_not_null()
	Save.data["gold"] = sale.price + 500
	var t := await _title(true)
	_show(t, sale)
	assert_str(t._name.text).is_equal("UNKNOWN")
	assert_bool(t._play.locked).is_true()
	assert_str(t._play.label_text()).is_equal("LOCKED")
	assert_bool(t._figure.tint.is_equal_approx(Title.MASK)).is_true()
	assert_bool(t._buy_col.visible).is_true()
	assert_bool(t._req.visible).is_false()
	var buy: WButton = t._buy_col.find_child("Buy", false, false)
	assert_object(buy).is_not_null()
	assert_str(buy.role).is_equal(WButton.GREEN)
	assert_int(int(buy.get_meta("price"))).is_equal(maxi(sale.price, 0))
	assert_str(buy.label_text()).contains("BUY")
	assert_bool((t._buy_col.find_child("BuyNote", false, false) as Control).visible).is_false()
	# the BUY sits over his figure's middle
	assert_bool(t.hero_figure_rect().has_point(buy.get_global_rect().get_center())).is_true()
	# the question: the shared confirm's buy (green)
	t.ask_buy()
	var ask := WConfirm.current(t)
	assert_object(ask).is_not_null()
	assert_str((ask.find_child("Confirm", true, false) as WButton).role).is_equal(WButton.GREEN)
	ask.confirm()
	assert_bool(Save.owns_hero(sale.id)).is_true()
	assert_int(Save.gold()).is_equal(500)
	assert_bool(t._play.locked).is_false()
	assert_str(t._play.label_text()).is_equal("START")
	assert_bool(t._buy_col.visible).is_false()
	# the mask lifts (TitleStage's reveal time)
	await get_tree().create_timer(Stage.REVEAL_TIME + 0.15).timeout
	assert_bool(t._figure.tint.is_equal_approx(Color.WHITE)).is_true()


func test_short_of_gold_the_buy_is_grey_and_says_how_short() -> void:
	var sale := _first_in("buyable")
	Save.data["gold"] = maxi(sale.price - 166, 0)
	var t := await _title(true)
	_show(t, sale)
	var buy: WButton = t._buy_col.find_child("Buy", false, false)
	assert_bool(buy.locked).is_true()
	assert_int(int(buy.get_meta("short"))).is_equal(sale.price - Save.gold())
	var note: Control = t._buy_col.find_child("BuyNote", false, false)
	assert_bool(note.visible).is_true()
	assert_str(_texts(note)).is_equal("%s short" % W.num(sale.price - Save.gold()))
	# a finger on it asks nothing
	t.ask_buy()
	assert_object(WConfirm.current(t)).is_null()
	assert_bool(Save.owns_hero(sale.id)).is_false()
	# (the grey label's first parts, queued for freeing, go at the frame's end)
	await get_tree().process_frame


func test_a_locked_hero_shows_his_requirement_and_start_refuses_him() -> void:
	Settings.preview_locked_heroes = true
	var locked := _first_in("locked")
	var t := await _title(true)
	if locked == null:
		# the developer's preview: the hidden heroes ride the carousel, locked
		for h in t._heroes:
			if t._state(h) == "locked":
				locked = h
				break
	assert_object(locked).is_not_null()
	_show(t, locked)
	await get_tree().process_frame
	assert_bool(t._req.visible).is_true()
	assert_bool(t._buy_col.visible).is_false()
	var q := Registry.quest_for("character", locked.id)
	# pass 129 (re-pinned): an outlaw a Trail node gives reads "Reach Trail Level N" without a quest
	assert_str(t._req_text.text).is_equal(Registry.hero_requirement_text(locked) if (q != null or Trail.gated("outlaw", locked.id)) else "Not in the game yet.")
	assert_object(t._figure.get_node_or_null("Padlock")).is_not_null()
	assert_bool(t._play.locked).is_true()
	# the card stands over his feet, clear of the name
	t._place()
	await get_tree().process_frame
	assert_float(t._req.get_global_rect().end.y + R.PANEL_BASE).is_less_equal(t._name.position.y)
	# START refuses him: nothing set, nothing started
	Save.data["last_map"] = "p123_sentinel"
	t._on_play()
	assert_str(str(Save.data["last_map"])).is_equal("p123_sentinel")


# ---------------------------------------------------------------- rules that live once, and the tools

func test_the_upgrade_mark_is_the_tab_bars_rule() -> void:
	var t := await _title(true)
	Save.data["gold"] = 0
	assert_bool(t._rank_affordable()).is_equal(TabBarScript.upgrade_mark())
	Save.data["gold"] = 10000000
	assert_bool(t._rank_affordable()).is_equal(TabBarScript.upgrade_mark())
	assert_bool(t._rank_affordable()).is_true()
	# START and ARENA still go into a run through the curtain only (pass 120's count)
	var src := _src("res://ui/TitleScreen.gd")
	assert_int(src.count("UiFx.go_run(get_tree())")).is_equal(2)


func test_the_capture_tools_carry_the_royale_title() -> void:
	var shots := _src("res://tools/wanted_shots.gd")
	assert_str(shots).contains("func _title_buy()")
	for n in ["01d-title-buyable", "01e-title-buy-short", "01f-title-buy-ask"]:
		assert_str(shots).contains(n)
	var audit := _src("res://tools/touch_audit.gd")
	assert_str(audit).contains("func _title_royale()")
	assert_str(audit).contains("_want(\"title_royale\")")
