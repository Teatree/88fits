## Pass 69, lane UI (Garry: "There are now unavailable heroes, ones that can be unlocked ... After the requirements are
## met the heroes will become available to unlock by buying them with coins"; a Hero Collections drawer on the title):
## a hero is owned when free (availability "available") or bought (Save.heroes_owned); a "purchase" hero is locked until
## his quest unlock_<id> is done, then on sale (Registry.hero_state); buying spends his price once (Save.buy_hero, the sink
## "hero"); the title shows a hero not owned as Unknown under a black mask with mystery plates, his requirement over the
## plaque or a BUY over him, and PLAY refuses him; the drawer lists every hero not hidden.
extends GdUnitTestSuite

const Stage := preload("res://ui/TitleStage.gd")
const Drawer := preload("res://ui/wanted/WHeroDrawer.gd")

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"style": Settings.menu_style, "debug": Settings.debug_mode, "preview": Settings.preview_locked_heroes,
		"inset": Settings.top_inset}
	Settings.preview_locked_heroes = false
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Stage.forget()
	Settings.menu_style = str(_keep["style"])
	Settings.debug_mode = bool(_keep["debug"])
	Settings.preview_locked_heroes = bool(_keep["preview"])
	Settings.top_inset = int(_keep["inset"])
	Registry.quests.erase("p69_test_quest")
	Registry.characters.erase("p69_free_quest")
	Save.data = Save._default()
	Save._dirty = false


func _hero(id: String) -> CharacterDef:
	var c: CharacterDef = Registry.character(id)
	assert_object(c).override_failure_message(id).is_not_null()
	return c


func _title(style: String = "live") -> Control:
	Settings.menu_style = style
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


## Every WPlate under `n` (find_children's type filter does not see a script's class_name).
func _plates(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "", true, false):
		if c is WPlate:
			out.append(c)
	return out


func _show(t: Control, id: String) -> void:
	var i: int = (t._heroes as Array).find(_hero(id))
	assert_int(i).override_failure_message("%s is not on the carousel" % id).is_greater_equal(0)
	t._index = i
	t._show_hero(0)
	t._place()


# ---------------------------------------------------------------- the content

func test_availability_purchase_shows_the_hero_and_hidden_hides_him() -> void:
	var base: Dictionary = JsonContent.load_json("res://content/characters/astro/astro.json")
	var buy := base.duplicate(true)
	buy["availability"] = "purchase"
	buy["hidden"] = true   # the Level Editor's server wrote hidden = (availability != available) before pass 69
	var c := JsonContent.build("characters", buy, "res://content/characters/astro/") as CharacterDef
	assert_bool(c.hidden).is_false()
	var hid := base.duplicate(true)
	hid["availability"] = "hidden"
	assert_bool((JsonContent.build("characters", hid, "res://content/characters/astro/") as CharacterDef).hidden).is_true()
	var both := base.duplicate(true)
	both["availability"] = "available"
	both["hidden"] = true
	assert_bool((JsonContent.build("characters", both, "res://content/characters/astro/") as CharacterDef).hidden).is_true()


func test_every_purchase_hero_has_a_price_and_a_requirement_the_quests_can_check() -> void:
	var on_sale := 0
	for c: CharacterDef in Registry.characters.values():
		if c.availability != "purchase":
			continue
		on_sale += 1
		assert_bool(c.hidden).override_failure_message(c.id).is_false()
		assert_int(c.price).override_failure_message(c.id).is_greater(0)
		assert_str(c.currency_type).override_failure_message(c.id).is_equal("gold")
		var q := Registry.quest_for("character", c.id)
		if q:
			assert_str(q.id).is_equal("unlock_" + c.id)
			assert_str(TextGen.quest_text(q)).override_failure_message(c.id).is_not_equal("Complete a challenge.")
			assert_bool(Registry.quest_visible(q)).override_failure_message(c.id).is_true()
	assert_int(on_sale).is_greater(0)
	# Garry's asks: the Drifter and Astro free, Fadeaway on sale with no requirement (his test), Mira back with one she
	# will never meet, Dad still hidden
	assert_str(_hero("drifter").availability).is_equal("available")
	assert_str(_hero("astro").availability).is_equal("available")
	assert_str(_hero("fadeaway").availability).is_equal("purchase")
	assert_object(Registry.quest_for("character", "fadeaway")).is_null()
	assert_str(_hero("mira").availability).is_equal("purchase")
	assert_bool(_hero("mira").hidden).is_false()
	var mq := Registry.quest_for("character", "mira")
	assert_object(mq).is_not_null()
	assert_int(int(mq.condition.get("count", 0))).is_greater_equal(10000000)
	assert_bool(_hero("dad").hidden).is_true()
	assert_str(TextGen.grouped(99999999)).is_equal("99,999,999")
	assert_str(TextGen.grouped(2500)).is_equal("2,500")
	assert_str(TextGen.grouped(400)).is_equal("400")


# ---------------------------------------------------------------- the states

func test_hero_state_for_each_case() -> void:
	# free: owned from the start
	assert_str(Registry.hero_state(_hero("drifter"))).is_equal("owned")
	assert_str(Registry.hero_state(_hero("astro"))).is_equal("owned")
	# on sale with no requirement
	assert_str(Registry.hero_state(_hero("fadeaway"))).is_equal("buyable")
	# a requirement not met: locked; met: on sale; bought: owned
	var cal := _hero("calavera")
	assert_str(Registry.hero_state(cal)).is_equal("locked")
	Save.mark_quest("unlock_calavera")
	assert_str(Registry.hero_state(cal)).is_equal("buyable")
	Save.heroes_owned().append("calavera")
	assert_str(Registry.hero_state(cal)).is_equal("owned")
	assert_bool(Registry.hero_owned(cal)).is_true()
	# hidden
	assert_str(Registry.hero_state(_hero("dad"))).is_equal("hidden")
	assert_str(Registry.hero_state(null)).is_equal("hidden")
	# Mira's requirement is out of reach
	assert_str(Registry.hero_state(_hero("mira"))).is_equal("locked")
	assert_str(Registry.hero_requirement_text(_hero("mira"))).is_equal("Kill 99,999,999 creatures, all time.")
	# a free hero gated by a quest: locked, then owned with nothing to pay
	var free := CharacterDef.new()
	free.id = "p69_free_quest"
	free.availability = "available"
	Registry.characters[free.id] = free
	var q := QuestDef.new()
	q.id = "p69_test_quest"
	q.condition = {"type": "runs_total", "count": 999999}
	q.unlocks = {"type": "character", "id": free.id}
	Registry.quests[q.id] = q
	assert_str(Registry.hero_state(free)).is_equal("locked")
	Save.mark_quest(q.id)
	assert_str(Registry.hero_state(free)).is_equal("owned")


func test_the_drawer_order_is_owned_then_on_sale_then_locked() -> void:
	var list: Array = Registry.heroes_for_drawer()
	assert_int(list.size()).is_equal(Registry.sorted_characters().size())
	var rank := {"owned": 0, "buyable": 1, "locked": 2}
	var last := -1
	for c: CharacterDef in list:
		var r: int = rank[Registry.hero_state(c)]
		assert_int(r).override_failure_message(c.id).is_greater_equal(last)
		last = r
	assert_str((list[0] as CharacterDef).id).is_equal("drifter")


# ---------------------------------------------------------------- buying

func test_buying_spends_the_gold_once_and_owns_him() -> void:
	var fad := _hero("fadeaway")
	Save.data["gold"] = fad.price + 30
	var moved: Array = []
	var probe := func(d: int, why: String, _bal: int, extra: Dictionary): moved.append([d, why, str(extra.get("hero", ""))])
	Save.gold_moved.connect(probe)
	assert_bool(Save.buy_hero(fad)).is_true()
	assert_int(Save.gold()).is_equal(30)
	assert_bool(Save.owns_hero("fadeaway")).is_true()
	assert_str(Registry.hero_state(fad)).is_equal("owned")
	# a second buy: nothing, the gold stays
	assert_bool(Save.buy_hero(fad)).is_false()
	assert_int(Save.gold()).is_equal(30)
	assert_int((Save.data["heroes_owned"] as Array).count("fadeaway")).is_equal(1)
	Save.gold_moved.disconnect(probe)
	assert_array(moved).is_equal([[-fad.price, "hero", "fadeaway"]])


func test_no_buy_without_the_requirement_or_the_gold() -> void:
	var cal := _hero("calavera")
	Save.data["gold"] = 100000
	assert_bool(Save.buy_hero(cal)).is_false()
	assert_int(Save.gold()).is_equal(100000)
	assert_bool(Save.owns_hero("calavera")).is_false()
	var fad := _hero("fadeaway")
	Save.data["gold"] = fad.price - 1
	assert_bool(Save.buy_hero(fad)).is_false()
	assert_int(Save.gold()).is_equal(fad.price - 1)
	assert_bool(Save.owns_hero("fadeaway")).is_false()
	# free and hidden heroes are never bought
	Save.data["gold"] = 100000
	assert_bool(Save.buy_hero(_hero("drifter"))).is_false()
	assert_bool(Save.buy_hero(_hero("dad"))).is_false()
	assert_int(Save.gold()).is_equal(100000)


func test_a_save_from_before_owns_only_the_free_heroes_and_the_developer_owns_them_all() -> void:
	Save.data = Save._default()
	Save._merge_file({"gold": 12, "last_character": "fadeaway"})
	assert_array(Save.heroes_owned()).is_empty()
	assert_str(Registry.hero_state(_hero("fadeaway"))).is_not_equal("owned")
	var n := Save.own_every_hero()
	assert_int(n).is_greater(0)
	for c: CharacterDef in Registry.sorted_characters():
		if c.availability == "purchase":
			assert_str(Registry.hero_state(c)).override_failure_message(c.id).is_equal("owned")
	Save.forget_bought_heroes()
	assert_array(Save.heroes_owned()).is_empty()


func test_a_save_whose_last_hero_is_not_owned_opens_on_the_drifter() -> void:
	var f := FileAccess.open(Save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": Save.VERSION, "gold": 5, "last_character": "fadeaway"}))
	f.close()
	Save.load_save()
	assert_str(str(Save.data["last_character"])).is_equal("drifter")
	f = FileAccess.open(Save.path(), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": Save.VERSION, "gold": 5, "last_character": "fadeaway", "heroes_owned": ["fadeaway"]}))
	f.close()
	Save.load_save()
	assert_str(str(Save.data["last_character"])).is_equal("fadeaway")
	DirAccess.remove_absolute(Save.path())


# ---------------------------------------------------------------- the title

func test_the_title_shows_a_hero_not_owned_as_unknown_and_play_refuses_him() -> void:
	var t := await _title("live")
	# it opens on an owned hero
	assert_bool(t._is_locked(t._heroes[t._index])).is_false()
	# on sale: Unknown, the BUY over him, no requirement card, PLAY locked, the black mask, mystery plates
	_show(t, "fadeaway")
	assert_str(t._name.text).is_equal("Unknown")
	assert_bool(t._buy_col.visible).is_true()
	assert_bool(t._req.visible).is_false()
	assert_bool(t._play.locked).is_true()
	var tint: Color = (t._stage.hero_sprite().material_override as ShaderMaterial).get_shader_parameter("tint")
	assert_float(tint.get_luminance()).is_less(0.05)
	var plates := 0
	for p in _plates(t._stats):
		assert_bool(p.mystery).is_true()
		plates += 1
	assert_int(plates).is_greater(0)
	# PLAY refuses him: nothing set, nothing started
	Save.data["last_map"] = "p69_sentinel"
	t._on_play()
	assert_str(str(Save.data["last_map"])).is_equal("p69_sentinel")
	assert_str(str(Save.data["last_character"])).is_not_equal("fadeaway")
	# locked: the requirement over the plaque, no BUY, the padlock
	_show(t, "mira")
	assert_bool(t._req.visible).is_true()
	assert_bool(t._buy_col.visible).is_false()
	assert_str(t._req_text.text).is_equal("Kill 99,999,999 creatures, all time.")
	assert_object(t._lock).is_not_null()
	assert_bool(t._play.locked).is_true()
	# owned: his name, neither, PLAY open
	_show(t, "astro")
	assert_str(t._name.text).is_equal("Astro")
	assert_bool(t._req.visible).is_false()
	assert_bool(t._buy_col.visible).is_false()
	assert_bool(t._play.locked).is_false()
	await get_tree().process_frame


func test_buying_on_the_title_reveals_him_and_opens_play() -> void:
	Save.data["gold"] = 500
	var t := await _title("live")
	_show(t, "fadeaway")
	var price: int = _hero("fadeaway").price
	t._buy_now(_hero("fadeaway"))
	assert_bool(Save.owns_hero("fadeaway")).is_true()
	assert_int(Save.gold()).is_equal(500 - price)
	assert_object(t._heroes[t._index]).is_same(_hero("fadeaway"))
	assert_bool(t._play.locked).is_false()
	assert_str(t._name.text).is_equal("Fadeaway")
	assert_bool(t._buy_col.visible).is_false()
	# the gold plate says what is left
	var amount: WText = t._gold_plate.find_children("Amount", "", true, false)[0]
	assert_str(amount.text).is_equal(W.num(500 - price))
	# the mask lifts
	await get_tree().create_timer(Stage.REVEAL_TIME + 0.2).timeout
	var tint: Color = (t._stage.hero_sprite().material_override as ShaderMaterial).get_shader_parameter("tint")
	assert_bool(tint.is_equal_approx(Color.WHITE)).is_true()
	# short of gold: the BUY is locked and says by how much; a tap only refuses
	Save.data["gold"] = 10
	_show(t, "fadeaway")
	Save.heroes_owned().clear()
	_show(t, "fadeaway")
	assert_bool(t._buy.locked).is_true()
	assert_bool(t._buy_note_box.visible).is_true()
	t.ask_buy()
	assert_bool(WConfirm.is_open(t)).is_false()
	assert_int(Save.gold()).is_equal(10)


func test_the_drawer_lists_every_hero_not_hidden_and_a_tile_selects_him() -> void:
	var t := await _title("live")
	t.open_drawer()
	await get_tree().process_frame
	assert_bool(t.drawer_open()).is_true()
	var d: Control = t._drawer
	for c: CharacterDef in Registry.characters.values():
		if c.hidden:
			assert_object(d.call("tile_of", c.id)).override_failure_message(c.id).is_null()
		else:
			assert_object(d.call("tile_of", c.id)).override_failure_message(c.id).is_not_null()
	# two rows
	assert_int((d.get("grid") as GridContainer).columns).is_equal(int(ceil(Registry.sorted_characters().size() / 2.0)))
	# a hero not owned: his badge a mystery; an owned one's in colour
	var fad_tile: Control = d.call("tile_of", "fadeaway")
	assert_bool((fad_tile.find_child("Badge", true, false) as WPlate).mystery).is_true()
	var dr_tile: Control = d.call("tile_of", "drifter")
	assert_bool((dr_tile.find_child("Badge", true, false) as WPlate).mystery).is_false()
	# a tile selects that hero and the drawer stays open
	d.call("_pick", _hero("mira"))
	assert_object(t._heroes[t._index]).is_same(_hero("mira"))
	assert_bool(t.drawer_open()).is_true()
	# the button closes it
	t.toggle_drawer()
	assert_bool(t.drawer_open()).is_false()
	await get_tree().process_frame


func test_the_drawer_scrolls_sideways_when_the_tiles_do_not_fit() -> void:
	var t := await _title("live")
	t.open_drawer()
	await get_tree().process_frame
	var d: Control = t._drawer
	# a narrow room: the grid is wider than the panel
	d.call("frame", Rect2(Vector2(36, 500), Vector2(400, 400)))
	assert_bool(bool(d.call("scrolls"))).is_true()
	var ts: TouchScroll = d.get("_touch")
	assert_bool(ts.horizontal).is_true()
	var sc: ScrollContainer = d.get("scroll")
	await get_tree().process_frame
	await get_tree().process_frame
	var r := sc.get_global_rect()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = r.get_center()
	down.pressed = true
	ts.input(down)
	for k in 6:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = r.get_center() - Vector2(20.0 * (k + 1), 0)
		drag.relative = Vector2(-20, 0)
		ts.input(drag)
	assert_int(sc.scroll_horizontal).is_greater(0)
	assert_int(sc.scroll_vertical).is_equal(0)
	ts.reset()
	t.close_drawer()
	await get_tree().process_frame


func test_the_hero_sheet_of_a_hero_not_owned_is_unknown() -> void:
	var t := await _title("live")
	_show(t, "fadeaway")
	t.open_sheet()
	await get_tree().process_frame
	var s: Control = t._sheet
	var nm: WText = s.find_child("Name", true, false)
	assert_str(nm.text).is_equal("UNKNOWN")
	var n := 0
	for p in _plates(s):
		assert_bool(p.mystery).is_true()
		n += 1
	assert_int(n).is_greater(0)
	assert_object(s.find_child("Price", true, false)).is_not_null()
	s.call("close")
	await get_tree().process_frame
