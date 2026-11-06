## Pass 123, lane HEROES (Garry's build brief: "Build the Heroes screen as the mock (hero, trait, items with full text,
## SELECT, LOOKS strip, hero grid) with the real looks, skins and icons from data ... DETAILS opens the new Hero details
## pop-up", "Keep the favourite item row with 'finding it gives a bonus level'", "Hero details drops the milestone row;
## the trait rule in words only", "I actually like our detailed view. Make that, but with the new UI style"):
##  - the Heroes screen (ui/HeroesScreen.tscn, no class_name) under Royale: its parts in the mock's order, the HEROES tab
##    open in the docked tab bar, the shown hero (Save.last_character), the trait in "per Level" lines, his items from
##    data (the favourite's bonus in Garry's words, the evolution's rule), SELECT / SELECTED / BUY / LOCKED by his state,
##    the grid of every hero the drawer lists with his state, the looks strip and its rules, the finger's axis on the
##    strip, the sprite's idle frames;
##  - buying a hero and a look from it (the shared confirm in green; the purse short buys nothing);
##  - the Hero details pop-up (WHeroSheet) under Royale: the mock's shell, no milestone row, every stat, the items, the
##    looks, the unknown version; under Wanted exactly as before (the Levels row, the paper card).
extends GdUnitTestSuite

const SCREEN := "res://ui/HeroesScreen.tscn"
const Sheet := preload("res://ui/wanted/WHeroSheet.gd")
const SOLD_QID := "p123_heroes_test_skin"

var _settings_before: Dictionary = {}
var _keep_may: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_settings_before)


func before_test() -> void:
	# pass 132: Ironwood is free in the game now; this suite's checks of an outlaw sold for gold put him on sale for their time
	Registry.character("ironwood").availability = "purchase"
	Save.data = Save._default()
	Save._dirty = false
	_keep_may = (Registry.character("may").variants as Dictionary).duplicate(true)


func after_test() -> void:
	Registry.character("ironwood").availability = "available"
	Registry.character("may").variants = _keep_may
	Registry.quests.erase(SOLD_QID)
	Save.data = Save._default()
	Save._dirty = false


func _screen() -> Control:
	var s: Control = auto_free(load(SCREEN).instantiate())
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _texts(n: Node) -> String:
	var out := ""
	if n is WText:
		out += (n as WText).text + " "
	for c in n.get_children():
		out += _texts(c)
	return out


func _hero(id: String) -> CharacterDef:
	return Registry.character(id)


## Every hero's look but the one he plays sold for gold, none gated: a strip that runs past the screen (May has six).
func _sell_every_look(id: String) -> void:
	var c := _hero(id)
	for code in c.variants.keys():
		if str(code) == c.home_look():
			continue
		var e: Dictionary = (c.variants[code] as Dictionary).duplicate(true)
		e["shelved"] = false
		e["skin"] = {"purchasable": true, "name": "Look " + str(code), "price": 300, "currency_type": "gold"}
		c.variants[code] = e


func _labels(n: Node) -> Array:
	var out: Array = []
	for w in n.find_children("*", "Control", true, false):
		if w is WText:
			var t := w as WText
			var s := t.text
			if s == "":
				for r in t.runs:
					s += str(r[0])
			out.append(s)
	return out


# ---------------------------------------------------------------- the screen

func test_the_screen_builds_in_the_mocks_order_with_the_heroes_tab_open() -> void:
	Save.data["gold"] = 104711
	var s := await _screen()
	assert_object(s.get("tab_bar_node")).is_not_null()
	assert_str(str(s.tab_bar())).is_equal("heroes")
	var bar: Control = s.get("tab_bar_node")
	assert_bool(bar.call("is_locked", "heroes")).is_false()
	assert_bool(load("res://ui/wanted/WTabBar.gd").opens("heroes")).is_true()
	assert_str(load("res://ui/wanted/WTabBar.gd").scene_of("heroes")).is_equal(SCREEN)
	assert_str(str(s.get("header").title.text)).is_equal("OUTLAWS")
	var amount: WText = s.find_child("Amount", true, false)
	assert_str(amount.text).is_equal("104,711")
	# the page top to bottom: the top half, SELECT, LOOKS, HEROES
	var names: Array = []
	for c in s.get("content").get_children():
		if not (c as Control).name.begins_with("@"):
			names.append(str(c.name))
	# pass 123, Garry's note: the top, SELECT, his items in full-width rows; the looks live in a pop-up
	# pass 126: the grid left the page for its own list at the foot (pass126_UI_test)
	var order := ["Top", "SelectRow", "Items"]
	var at := -1
	for n: String in order:
		var k := -1
		for i in names.size():
			if str(names[i]) == n:
				k = i
		assert_int(k).override_failure_message("%s missing in %s" % [n, str(names)]).is_greater(at)
		at = k
	for n: String in ["Stage", "Sprite", "Trait", "Details", "LooksBtn", "HeroName", "Slogan", "Items", "Select", "HeroGrid"]:
		assert_object(s.find_child(n, true, false)).override_failure_message(n).is_not_null()
	for n: String in ["Disc", "LooksScroll", "LookStrip"]:
		assert_object(s.find_child(n, true, false)).override_failure_message(n).is_null()
	# the hero's stage on the left; his words on the right, starting past it; the items the page's whole width
	var stage: Control = s.find_child("Top", true, false).find_child("Stage", true, false)
	var hero_name: Control = s.find_child("HeroName", true, false)
	var items: Control = s.find_child("Items", true, false)
	assert_float(stage.global_position.x).is_equal_approx(40.0, 1.0)
	assert_float(hero_name.global_position.x).is_greater_equal(stage.global_position.x + stage.size.x)
	assert_float(items.size.x).is_greater(900.0)
	# DETAILS and LOOKS side by side, the same height
	var det: Control = s.find_child("Details", true, false)
	var lk: Control = s.find_child("LooksBtn", true, false)
	assert_float(det.global_position.y).is_equal_approx(lk.global_position.y, 1.0)
	assert_float(det.size.y).is_equal_approx(lk.size.y, 1.0)
	assert_bool(lk.global_position.x > det.global_position.x).is_true()


func test_the_shown_hero_is_the_one_runs_start_with_and_his_trait_reads_per_level() -> void:
	Save.data["last_character"] = "drifter"
	var s := await _screen()
	assert_str((s.get("shown") as CharacterDef).id).is_equal("drifter")
	assert_str((s.find_child("HeroName", true, false) as WText).text).is_equal("THE DRIFTER")
	var dr := _hero("drifter")
	var line: WText = s.find_child("Trait", true, false).find_child("Line", true, false)
	var words := ""
	for r in line.runs:
		words += str(r[0])
	var e: Effect = dr.level_trait[0]
	assert_str(words).is_equal("%s %s per Level" % [TextGen.hero_step(e), TextGen.hero_word(e.stat)])
	assert_bool((line.runs[0][1] as Color).is_equal_approx(R.ROLES["green"]["top"])).is_true()
	assert_bool(" / LV" in words or "/LV" in words).is_false()
	# SELECT says SELECTED for the hero runs already start with
	var sel: WButton = s.find_child("Select", true, false)
	assert_str(str(sel.get_meta("action"))).is_equal("selected")
	assert_str(sel.role).is_equal(WButton.SLATE)


func test_his_items_come_from_data_with_the_favourites_bonus_and_the_evolutions_rule() -> void:
	for c: CharacterDef in Registry.sorted_characters():
		var list: Array = Sheet.items_of(c)
		assert_str(str((list[0] as Dictionary)["role"])).override_failure_message(c.id).is_equal("start")
		assert_object((list[0] as Dictionary)["def"]).is_equal(Registry.start_weapon_for(c))
		var fav := Sheet.favourite_of(c)
		if fav and fav != Registry.start_weapon_for(c):
			var f: Dictionary = list[1]
			assert_str(str(f["role"])).is_equal("favourite")
			var bonus := str(f.get("bonus", ""))
			var b: Dictionary = c.favourite_bonus if fav is WeaponDef else c.favourite_passive_bonus
			if str(b.get("type", "")) == "level" and int(b.get("value", 1)) == 2:
				assert_str(bonus).is_equal("Finding it in a run gives it a bonus level.")
			if bonus != "":
				assert_str(bonus).override_failure_message(c.id).starts_with("Finding it in a run gives it")
		var perks := 0
		for it: Dictionary in list:
			if str(it["role"]) == "perk":
				perks += 1
		assert_int(perks).is_equal(Registry.perks_of(c.id).size())
	# the Drifter (pass 126: his Revolver's evolution is no longer listed, pass126_UI_test)
	Save.data["last_character"] = "drifter"
	var s := await _screen()
	var fav_row: Control = s.find_child("Item_favourite_" + _hero("drifter").favourite_weapon, true, false)
	assert_object(fav_row.find_child("Bonus", true, false)).is_not_null()
	assert_object(s.find_child("Item_start_revolver", true, false)).is_not_null()


func test_the_grid_lists_every_hero_the_drawer_does_with_his_state() -> void:
	Save.data["gold"] = 1200
	var s := await _screen()
	var grid: GridContainer = s.find_child("HeroGrid", true, false)
	assert_int(grid.columns).is_equal(4)
	var list: Array = Registry.heroes_for_drawer()
	assert_int(grid.get_child_count()).is_equal(list.size())
	var owned := 0
	for i in list.size():
		var h: CharacterDef = list[i]
		var t: Control = grid.get_child(i)
		assert_str(str(t.name)).is_equal("Hero_" + h.id)
		var st := Registry.hero_state(h)
		assert_str(str(t.get_meta("state"))).is_equal(st)
		assert_vector(t.size).is_equal(Vector2(232, 176))
		var portrait: Control = t.find_child("Portrait", true, false)
		assert_bool(bool(portrait.get_meta("unknown"))).is_equal(st != "owned")
		var foot: Control = t.find_child("Foot", true, false)
		match st:
			"owned":
				owned += 1
				assert_bool(foot is WText).is_true()
				assert_str((foot as WText).text).is_equal(h.display_name.to_upper())
			"buyable":
				var w: WText = foot.find_child("Word", true, false)
				assert_str(w.text).is_equal(W.num(h.price))
			_:
				assert_str((foot.find_child("Word", true, false) as WText).text).is_equal("LOCKED")
	var lab: WText = s.find_child("Heroes", true, false).get_node("Label")
	assert_str(lab.text).is_equal("OUTLAWS · %d OF %d OWNED" % [owned, list.size()])
	# the shown hero's tile is gold-edged; a tap shows another
	var shown: CharacterDef = s.get("shown")
	assert_int((grid.get_node("Hero_" + shown.id) as WTap).box.inner).is_equal(5)
	var other: CharacterDef = list[1]
	(grid.get_node("Hero_" + other.id) as WTap).pressed.emit()
	await get_tree().process_frame
	assert_object(s.get("shown")).is_equal(other)
	grid = s.find_child("HeroGrid", true, false)
	assert_int((grid.get_node("Hero_" + other.id) as WTap).box.inner).is_equal(5)
	assert_int((grid.get_node("Hero_" + shown.id) as WTap).box.inner).is_equal(0)


func test_a_hero_on_sale_shows_buy_and_one_locked_shows_his_quest() -> void:
	Save.data["gold"] = 5000
	var s := await _screen()
	var iron := _hero("ironwood")
	assert_str(Registry.hero_state(iron)).is_equal("buyable")
	s.call("show_hero", iron)
	await get_tree().process_frame
	var b: WButton = s.find_child("Select", true, false)
	assert_str(str(b.get_meta("action"))).is_equal("buy")
	assert_int(int(b.get_meta("price"))).is_equal(iron.price)
	assert_str(b.role).is_equal(WButton.GREEN)
	assert_str((s.find_child("HeroName", true, false) as WText).text).is_equal("UNKNOWN")
	assert_object(s.find_child("LooksBtn", true, false)).is_null()
	assert_object(s.find_child("Padlock", true, false)).is_null()
	# short of his price: the grey, the word kept, what is short on the panel
	Save.data["gold"] = 100
	s.call("refresh")
	await get_tree().process_frame
	b = s.find_child("Select", true, false)
	assert_bool(b.locked).is_true()
	assert_int(int(b.get_meta("short"))).is_equal(iron.price - 100)
	assert_str(b.label_text()).contains("BUY")
	var short: WText = s.find_child("Trait", true, false).find_child("Short", true, false)
	assert_str(short.text).is_equal("%s short" % W.num(iron.price - 100))
	# a hero whose quest is not done: LOCKED, his quest's words and the padlock on him
	var fad := _hero("fadeaway")
	assert_str(Registry.hero_state(fad)).is_equal("locked")
	s.call("show_hero", fad)
	await get_tree().process_frame
	b = s.find_child("Select", true, false)
	assert_str(str(b.get_meta("action"))).is_equal("locked")
	assert_bool(b.locked).is_true()
	assert_object(s.find_child("Padlock", true, false)).is_not_null()
	var req: WText = s.find_child("Requirement", true, false)
	assert_str(req.text).is_equal(Registry.hero_requirement_text(fad))
	# his items are their black shapes
	var start_row: Control = s.find_child("Item_start_" + Registry.start_weapon_for(fad).id, true, false)
	assert_bool((start_row.find_child("Frame", true, false) as WPlate).mystery).is_true()


func test_select_makes_him_the_hero_runs_start_with() -> void:
	Save.data["last_character"] = "drifter"
	Save.heroes_owned().append("astro")
	var s := await _screen()
	s.call("show_hero", _hero("astro"))
	await get_tree().process_frame
	var b: WButton = s.find_child("Select", true, false)
	assert_str(str(b.get_meta("action"))).is_equal("select")
	assert_str(b.role).is_equal(WButton.GOLD)
	b.pressed.emit()
	await get_tree().process_frame
	assert_str(str(Save.data["last_character"])).is_equal("astro")
	b = s.find_child("Select", true, false)
	assert_str(str(b.get_meta("action"))).is_equal("selected")
	# the HEROES tab wears his badge now
	var bar: Control = s.get("tab_bar_node")
	assert_object(load("res://ui/wanted/WTabBar.gd").hero_def()).is_not_null()
	assert_str((load("res://ui/wanted/WTabBar.gd").hero_def() as CharacterDef).id).is_equal("astro")
	assert_bool(is_instance_valid(bar)).is_true()


func test_buy_asks_in_green_and_buys_him_once() -> void:
	var iron := _hero("ironwood")
	Save.data["gold"] = iron.price + 50
	var s := await _screen()
	s.call("show_hero", iron)
	await get_tree().process_frame
	(s.find_child("Select", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	var ask := WConfirm.current(s)
	assert_object(ask).is_not_null()
	assert_str((ask.button("confirm") as WButton).role).is_equal(WButton.GREEN)
	ask.confirm()
	await get_tree().process_frame
	assert_str(Registry.hero_state(iron)).is_equal("owned")
	assert_int(Save.gold()).is_equal(50)
	assert_object(s.get("shown")).is_equal(iron)
	assert_str(str((s.find_child("Select", true, false) as WButton).get_meta("action"))).is_equal("select")
	var amount: WText = s.find_child("Amount", true, false)
	assert_str(amount.text).is_equal("50")
	# short of a price nothing asks
	var astro := _hero("astro")
	s.call("show_hero", astro)
	await get_tree().process_frame
	(s.find_child("Select", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	assert_bool(WConfirm.is_open(s)).is_false()
	# pass 129 (re-pinned): Astro is a Trail node now: locked, and a locked outlaw asks nothing either
	assert_str(Registry.hero_state(astro)).is_equal("locked")


func test_the_looks_pop_up_follows_the_sheets_rules() -> void:
	# pass 126 (lane SKINS): the Drifter's own look, worn, his skins beside it, on a fresh save only that one owned
	Save.data["last_character"] = "drifter"
	var dri_looks: Array = Registry.skins_of(_hero("drifter"))
	var s := await _screen()
	assert_bool(bool(s.call("looks_open"))).is_false()
	(s.find_child("LooksBtn", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	assert_bool(bool(s.call("looks_open"))).is_true()
	var strip: Control = s.get("looks_grid")
	assert_int(strip.get_child_count()).is_equal(dri_looks.size())
	assert_str(str(strip.get_child(0).get_meta("state"))).is_equal("worn")
	var pop: WConfirm = s.get("looks_pop")
	assert_str(_texts(pop)).contains("1 OF %d OWNED" % dri_looks.size())
	pop.button("cancel").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(bool(s.call("looks_open"))).is_false()
	# May with every look sold: worn, then the rest on sale; a tap on one asks, the deed buys and wears it, the looks return
	_sell_every_look("may")
	Save.heroes_owned().append("may")
	Save.data["gold"] = 1000
	var may := _hero("may")
	s.call("show_hero", may)
	await get_tree().process_frame
	s.call("open_looks")
	await get_tree().process_frame
	strip = s.get("looks_grid")
	var codes: Array = Registry.skins_of(may)
	assert_int(strip.get_child_count()).is_equal(codes.size())
	assert_str(str(strip.get_child(0).get_meta("state"))).is_equal("worn")
	# the first look on sale (a look a content quest still gates stays locked)
	var code := ""
	for k in codes:
		if Registry.skin_state(may, str(k)) == "buyable" and code == "":
			code = str(k)
	assert_str(code).is_not_empty()
	var tile: WTap = strip.get_node("Look_" + code)
	assert_str(str(tile.get_meta("state"))).is_equal("buyable")
	assert_object(tile.find_child("Price", true, false)).is_not_null()
	tile.pressed.emit()
	await get_tree().process_frame
	var ask := WConfirm.current(s)
	assert_object(ask).is_not_null()
	assert_bool(bool(s.call("looks_open"))).is_false()
	ask.confirm()
	await get_tree().process_frame
	assert_bool(Save.owns_skin(Registry.skin_key("may", code))).is_true()
	assert_str(Registry.played_look(may).look_code()).is_equal(code)
	assert_bool(bool(s.call("looks_open"))).is_true()
	strip = s.get("looks_grid")
	assert_str(str(strip.get_node("Look_" + code).get_meta("state"))).is_equal("worn")
	# the look every player owns: WEAR, and a tap wears it again
	var home: WTap = strip.get_node("Look_" + may.home_look())
	assert_str(str(home.get_meta("state"))).is_equal("owned")
	home.pressed.emit()
	await get_tree().process_frame
	assert_str(Registry.played_look(may).look_code()).is_equal(may.home_look())


func test_a_hero_not_owned_has_no_looks_button_and_open_looks_does_nothing() -> void:
	var s := await _screen()
	s.call("show_hero", _hero("fadeaway"))
	await get_tree().process_frame
	assert_object(s.find_child("LooksBtn", true, false)).is_null()
	s.call("open_looks")
	await get_tree().process_frame
	assert_bool(bool(s.call("looks_open"))).is_false()


func test_the_sprite_runs_in_place_down_and_right() -> void:
	# pass 123 (Garry: "make the live hero visual run in place, down and right")
	Save.data["last_character"] = "drifter"
	var s := await _screen()
	var art := Registry.played_look(_hero("drifter"))
	var want := "run"
	for a2: String in ["run_fd", "run_s", "run_f", "run"]:
		if int(art.anims.get(a2, 0)) > 0:
			want = a2
			break
	assert_int(int(s.get("_anim_n"))).is_equal(int(art.anims.get(want, 1)))
	assert_int(int(s.get("_anim_n"))).is_greater(1)
	var off := 0
	for a: String in TitleStage.ORDER:
		if a == want:
			break
		off += int(art.anims.get(a, 0))
	assert_int(int(s.get("_anim_from"))).is_equal(off)
	assert_float(float(s.get("_fps"))).is_greater(0.0)
	var f0 := int(s.get("_frame"))
	s.call("_process", 1.0 / float(s.get("_fps")) + 0.01)
	assert_int(int(s.get("_frame"))).is_not_equal(f0)
	# a hero not owned is drawn flat black
	s.call("show_hero", _hero("fadeaway"))
	await get_tree().process_frame
	assert_bool(bool(s.get("_silhouette"))).is_true()


func test_details_opens_the_pop_up_and_back_closes_it_first() -> void:
	var s := await _screen()
	(s.find_child("Details", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	assert_bool(bool(s.call("sheet_open"))).is_true()
	var sheet: Control = s.find_child("HeroSheet", false, false)
	assert_object(sheet.get("hero")).is_equal(s.get("shown"))
	s.call("on_back")
	await get_tree().process_frame
	assert_bool(bool(s.call("sheet_open"))).is_false()




# ---------------------------------------------------------------- the Hero details pop-up

func _sheet_on(c: CharacterDef, locked: bool) -> Control:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1080, 1920)
	add_child(host)
	var sh: Control = Sheet.open(host, c, locked)
	await get_tree().process_frame
	await get_tree().process_frame
	return sh


func test_the_pop_up_is_the_mocks_shell_without_the_milestone_row() -> void:
	var dr := _hero("drifter")
	var sh := await _sheet_on(dr, false)
	var card: Control = sh.get("card")
	assert_float(card.size.x).is_equal_approx(float(R.MODAL_W), 1.0)
	assert_bool((sh.get("dim") as ColorRect).color.is_equal_approx(R.DIM)).is_true()
	assert_object(sh.find_child("Levels", true, false)).is_null()
	assert_str((sh.find_child("Name", true, false) as WText).text).is_equal("THE DRIFTER")
	assert_object(sh.find_child("Corner", true, false)).is_not_null()
	var pills: Control = sh.find_child("Pills", true, false)
	var said := _labels(pills)
	assert_bool(said.has(("Trait · " + dr.trait_name).to_upper())).is_true()
	var rule: WText = sh.find_child("Rule", true, false)
	assert_str(rule.text).contains("per Level")
	var stats: Control = sh.find_child("Stats", true, false)
	for st: String in Sheet.STATS:
		assert_object(stats.find_child("Stat_" + st, true, false)).override_failure_message(st).is_not_null()
	var crit: Control = stats.find_child("Stat_crit_chance", true, false)
	assert_bool((crit.find_child("Value", true, false) as WText).color.is_equal_approx(R.ROLES["green"]["top"])).is_true()
	var hp: Control = stats.find_child("Stat_max_hp", true, false)
	assert_bool((hp.find_child("Value", true, false) as WText).color.is_equal_approx(R.WHITE)).is_true()
	assert_object(stats.find_child("Note", true, false)).is_not_null()
	for it: Dictionary in Sheet.items_of(dr):
		var row: Control = sh.find_child("Item_%s_%s" % [it["role"], (it["def"] as ContentDef).id], true, false)
		assert_object(row).override_failure_message(str(it["role"])).is_not_null()
	var close: WButton = sh.find_child("Close", true, false)
	assert_str(close.role).is_equal(WButton.SLATE)
	# pass 126 (lane SKINS): the Drifter has looks to choose from now; a hero with one look has no Looks section
	assert_object(sh.find_child("Looks", true, false)).is_not_null()
	close.pressed.emit()
	await get_tree().process_frame
	assert_bool(bool(sh.call("is_done"))).is_true()


func test_the_pop_up_shows_his_looks_and_a_hero_not_owned_is_unknown() -> void:
	_sell_every_look("may")
	Save.heroes_owned().append("may")
	var may := _hero("may")
	var sh := await _sheet_on(may, false)
	var grid: Control = sh.find_child("LookGrid", true, false)
	assert_object(grid).is_not_null()
	assert_int(grid.get_child_count()).is_equal(Registry.skins_of(may).size())
	assert_str(str(grid.get_child(0).get_meta("state"))).is_equal("worn")
	sh.call("close")
	await get_tree().process_frame
	var fad := _hero("fadeaway")
	var un := await _sheet_on(fad, true)
	assert_str((un.find_child("Name", true, false) as WText).text).is_equal("UNKNOWN")
	assert_object(un.find_child("Locked", true, false)).is_not_null()
	assert_object(un.find_child("Looks", true, false)).is_null()
	var v: WText = un.find_child("Stat_max_hp", true, false).find_child("Value", true, false)
	assert_str(v.text).is_equal("?")




func test_the_capture_and_audit_tools_carry_the_heroes_states() -> void:
	var shots := FileAccess.get_file_as_string("res://tools/wanted_shots.gd")
	assert_bool(shots.contains("func _heroes_shots()")).is_true()
	assert_bool(shots.contains("if _want(\"heroes\"):")).is_true()
	assert_bool(shots.contains("\"heroes\"")).is_true()
	var audit := FileAccess.get_file_as_string("res://tools/touch_audit.gd")
	assert_bool(audit.contains("func _heroes_audit()")).is_true()
	assert_bool(audit.contains("_want(\"heroes_screen\") or _want(\"hero_details\")")).is_true()
