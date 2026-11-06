## Pass 129, lane TRAIL-UI (docs/trail_schema.md "Layout", tools/dl/p128/TRAILUI/brief.md): the Trail screen on its own
## fixture (tests/fixtures/trail_screen.json, 40 levels with every node kind; never the game's file): where it opens,
## the schema's places, choosing and buying, a choice closing its siblings on screen, a warned node asking first, the
## pool holding a 500-level track, the tab's word, scene and crumb, the "Reach Trail Level N" lines and the way back
## (core/systems/Nav.gd) with each screen's state.
extends GdUnitTestSuite

const FIX := "res://tests/fixtures/trail_screen.json"
const SCENE := "res://ui/TrailScreen.tscn"
const HEROES := "res://ui/HeroesScreen.tscn"
const COLLECTION := "res://ui/CollectionScreen.tscn"
const TabBarScript := preload("res://ui/wanted/WTabBar.gd")

var _went: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from(FIX)
	Nav.clear()
	_went = []
	Nav.navigate = func(path: String) -> void: _went.append(path)


func after_test() -> void:
	Nav.navigate = Callable()
	Nav.clear()
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()


func _have(bought: Array, gold: int) -> void:
	Save.data["trail"] = {"bought": bought.duplicate(), "spent": 0, "had": []}
	Save.data["gold"] = gold
	Trail.refresh()


func _open(path: String = SCENE) -> Control:
	var s: Control = auto_free(load(path).instantiate())
	add_child(s)
	for k in 5:
		await get_tree().process_frame
	return s


## Level `l`'s nodes as the screen places them: [id, x in hundredths of the width, the tile's side].
func _places(s: TrailScreen, l: int) -> Array:
	var out: Array = []
	for e: Dictionary in s._lay_level(l):
		out.append([str(e["id"]), int(round(float(e["x"]) * 100.0)), int(e["side"])])
	return out


func test_a_new_save_opens_on_level_1_with_its_node_chosen() -> void:
	_have([], 500)
	var s: TrailScreen = await _open()
	assert_str(s.selected).is_equal("n01")
	assert_object(s.tile_of("n01")).is_not_null()
	assert_str(str(s.tile_of("n01").get_meta("state"))).is_equal("open")
	# the foot of the track: level 1's row is in view, the far end is not built
	assert_int(s.centre_level()).is_less(6)
	assert_object(s.tile_of("n40")).is_null()
	assert_bool(s._from_nav).is_false()


func test_it_opens_centred_on_the_node_bought_last_with_the_next_one_chosen() -> void:
	var bought: Array = ["n01", "n02", "n03a", "n04", "n05", "n06a", "n07a", "n07b", "n07c", "n08", "n09a", "n10", "n11", "n12a", "n12b", "n13",
		"n14", "n15", "n16", "n17", "n18", "n19", "n20a"]
	_have(bought, 0)
	var s: TrailScreen = await _open()
	assert_int(Trail.level()).is_equal(20)
	assert_int(s.centre_level()).is_equal(20)
	assert_str(s.selected).is_equal("n21")
	assert_object(s.tile_of("n20a")).is_not_null()
	assert_object(s.tile_of("n01")).is_null()
	assert_str(str(s.tile_of("n20b").get_meta("state"))).is_equal("closed")


func test_open_on_centres_chooses_and_rings_the_things_node() -> void:
	_have(["n01"], 0)
	TrailScreen.open_on("outlaw", "calavera")
	var s: TrailScreen = await _open()
	assert_str(s.ringed).is_equal("n24")
	assert_str(s.selected).is_equal("n24")
	assert_int(s.centre_level()).is_equal(24)
	assert_bool(s.tile_of("n24").get("ring")).is_true()
	# read once: the next opening is the plain one
	var again: TrailScreen = await _open()
	assert_str(again.ringed).is_equal("")


func test_the_places_follow_the_schema() -> void:
	var s: TrailScreen = await _open()
	assert_array(_places(s, 1)).is_equal([["n01", 50, 148]])
	assert_array(_places(s, 3)).is_equal([["n03a", 33, 148], ["n03b", 60, 148]])
	assert_array(_places(s, 7)).is_equal([["n07a", 20, 148], ["n07b", 42, 148], ["n07c", 64, 148]])
	assert_array(_places(s, 9)).is_equal([["n09a", 12, 132], ["n09b", 30, 132], ["n09c", 48, 132], ["n09d", 66, 132]])
	# an optional node 0.20 right of the rightmost required one; a second takes the left
	assert_array(_places(s, 4)).is_equal([["n04", 50, 148], ["n04o", 70, 116]])
	assert_array(_places(s, 10)).is_equal([["n10", 50, 148], ["n10o", 70, 116], ["n10p", 30, 116]])
	# level 1 at the bottom, rows 236 apart
	assert_float(s._row_y(1) - s._row_y(2)).is_equal(236.0)
	# an optional node that names no node hangs on its level's required node; three rails meet in n08
	assert_array(s._links("n04o")).is_equal([["n04", true]])
	assert_int(s._links("n08").size()).is_equal(3)


func test_a_tap_chooses_a_node_and_buy_buys_it() -> void:
	_have([], 1000)
	var s: TrailScreen = await _open()
	var price := Trail.price("n01")
	s.select("n01")
	var buy := s._dock.get_node_or_null("Buy") as WButton
	assert_object(buy).is_not_null()
	assert_int(int(buy.get_meta("price"))).is_equal(price)
	assert_str((s._dock.get_node("DockGives") as WText).text).is_equal(Trail.give_text(Trail.node("n01")))
	buy.pressed.emit()
	assert_str(Trail.state("n01")).is_equal("bought")
	assert_int(Save.gold()).is_equal(1000 - price)
	assert_str(str(s.tile_of("n01").get_meta("state"))).is_equal("bought")
	assert_int(Trail.level()).is_equal(1)
	# on to the next node to buy
	assert_str(s.selected).is_equal("n02")
	assert_bool(s.tile_of("n02").get("chosen")).is_true()
	assert_bool(s.tile_of("n01").get("chosen")).is_false()


func test_a_short_purse_buys_nothing_and_says_how_short() -> void:
	_have([], 10)
	var s: TrailScreen = await _open()
	var buy := s._dock.get_node_or_null("Buy") as WButton
	assert_int(int(buy.get_meta("short"))).is_equal(Trail.price("n01") - 10)
	buy.pressed.emit()
	assert_str(Trail.state("n01")).is_equal("open")
	assert_int(Save.gold()).is_equal(10)
	assert_bool(s.tile_of("n01").get("short")).is_true()


func test_a_choice_asks_first_and_closes_its_siblings_on_screen() -> void:
	_have(["n01", "n02"], 5000)
	var s: TrailScreen = await _open()
	s.select("n03a")
	assert_str((s._dock.get_node("DockState") as WText).text).is_equal("Taking this closes Tempo for good.")
	s.press_buy()
	assert_bool(WConfirm.is_open(s)).is_true()
	assert_str(Trail.state("n03a")).is_equal("open")
	WConfirm.current(s).confirm()
	assert_str(Trail.state("n03a")).is_equal("bought")
	assert_str(Trail.state("n03b")).is_equal("closed")
	assert_str(str(s.tile_of("n03b").get_meta("state"))).is_equal("closed")
	s.select("n03b")
	assert_object(s._dock.get_node_or_null("Buy")).is_null()
	assert_str((s._dock.get_node("DockState") as WText).text).is_equal("Closed by your choice")
	s.select("n03a")
	assert_str((s._dock.get_node("DockState") as WText).text).is_equal("Yours")


func test_a_warned_node_asks_and_not_now_keeps_the_gold() -> void:
	_have(["n01", "n02", "n03a", "n04"], 5000)
	var s: TrailScreen = await _open()
	s.select("n04o")
	assert_str((s._dock.get_node("DockState") as WText).text).contains(str(Trail.upgrade("stakes")["warn"]))
	s.press_buy()
	assert_bool(WConfirm.is_open(s)).is_true()
	WConfirm.current(s).cancel()
	assert_str(Trail.state("n04o")).is_equal("open")
	assert_int(Save.gold()).is_equal(5000)


func test_the_dock_says_what_a_locked_node_waits_for() -> void:
	_have(["n01", "n02", "n03a", "n04", "n05", "n06a", "n07a", "n07b"], 0)
	assert_str(TrailScreen.state_words(Trail.node("n12a"))).is_equal("Finish level 11 first")
	# level 7 is not done while one of its three nodes waits: the node all three meet in says so
	assert_str(Trail.state("n08")).is_equal("locked")
	assert_str(TrailScreen.state_words(Trail.node("n08"))).is_equal("Finish level 7 first")
	assert_str(TrailScreen.join(["A"])).is_equal("A")
	assert_str(TrailScreen.join(["A", "B", "C"])).is_equal("A, B and C")
	assert_str(TrailScreen.gift_words(Trail.node("n05"))).is_equal("Astro rides with you")
	assert_str(TrailScreen.name_of(Trail.node("n05"))).is_equal("A New Face")


func test_a_track_of_500_levels_keeps_only_the_tiles_near_the_view() -> void:
	var ups: Dictionary = Trail.read_file(FIX)["upgrades"]
	var nodes: Array = []
	var bought: Array = []
	for l in range(1, 501):
		nodes.append({"id": "b%d" % l, "level": l, "kind": "node", "gives": {"type": "upgrade", "upgrade": "might", "value": 0.01}})
		if l <= 300:
			bought.append("b%d" % l)
	Trail.load_data({"version": 1, "currency": "gold", "sections": [{"from": 1, "name": "One", "top": "f7b24a", "bottom": "ef7d22", "motif": "cactus"}],
		"upgrades": ups, "nodes": nodes, "end": {"text": "To be continued"}})
	_have(bought, 0)
	var s: TrailScreen = await _open()
	assert_int(s.centre_level()).is_equal(300)
	assert_int(s._track.get_child_count()).is_less(16)
	s.scroll.scroll_vertical = 0
	for k in 3:
		await get_tree().process_frame
	assert_object(s.tile_of("b500")).is_not_null()
	assert_object(s.tile_of("b300")).is_null()
	assert_int(s._track.get_child_count()).is_less(16)


func test_the_tab_is_the_trails() -> void:
	assert_str(TabBarScript.word_of("upgrade")).is_equal("TRAIL")
	assert_str(TabBarScript.scene_of("upgrade")).is_equal(SCENE)
	_have([], 0)
	var bar: Control = auto_free(TabBarScript.make("battle"))
	add_child(bar)
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_false()
	_have([], 1000)
	bar.call("refresh")
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_true()
	# the Trail screen is that tab: no crumb on the open tab, and opening it shows the player what can be bought
	var s: TrailScreen = await _open()
	assert_str(s.tab_bar()).is_equal("upgrade")
	assert_bool((s.tab_bar_node.get_node("UpgradeMark") as Control).visible).is_false()
	bar.call("refresh")
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_false()
	# a node the purse could not pay for before brings the crumb back
	_have(["n01"], 0)
	bar.call("refresh")
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_false()
	Save.data["gold"] = 1000
	Trail.refresh()
	bar.call("refresh")
	assert_bool((bar.get_node("UpgradeMark") as Control).visible).is_true()
	# pass 129 (lane TRAIL-REMOVE): the Upgrade board is gone, so the tab is the Trail's whatever the file holds
	Trail.load_from("res://tests/fixtures/trail_empty.json")
	assert_str(TabBarScript.word_of("upgrade")).is_equal("TRAIL")
	assert_str(TabBarScript.scene_of("upgrade")).is_equal(SCENE)
	assert_bool(ResourceLoader.exists("res://ui/HomesteadScreen.tscn")).is_false()


func test_a_requirement_line_opens_the_trail_and_back_returns_to_the_outlaw() -> void:
	assert_object(TrailScreen.requirement_line("outlaw", "drifter", 22)).is_null()
	load("res://ui/HeroesScreen.gd").set("open_on", "calavera")
	var hs: Control = await _open(HEROES)
	assert_str(str(hs.get("shown").id)).is_equal("calavera")
	var line := hs.get("content").find_child("TrailLine", true, false) as WTap
	assert_object(line).is_not_null()
	assert_str((line.find_child("Requirement", true, false) as WText).text).is_equal("Reach Trail Level 24")
	# a gated outlaw is bought on the Trail: no BUY here
	assert_str(str(hs.call("state_of", hs.get("shown")))).is_equal("locked")
	assert_bool(Nav.to_trail("outlaw", "calavera", hs)).is_true()
	assert_array(_went).is_equal([Nav.TRAIL])
	var s: TrailScreen = await _open()
	assert_bool(s._from_nav).is_true()
	assert_str(s.ringed).is_equal("n24")
	s.on_back()
	assert_array(_went).is_equal([Nav.TRAIL, HEROES])
	assert_int(Nav.depth()).is_equal(0)
	var hs2: Control = await _open(HEROES)
	assert_str(str(hs2.get("shown").id)).is_equal("calavera")
	# the state is handed out once: the next opening is the plain one
	var hs3: Control = await _open(HEROES)
	assert_str(str(hs3.get("shown").id)).is_not_equal("calavera")


func test_the_collection_comes_back_on_its_tab_and_the_items_page() -> void:
	var cs: Control = await _open(COLLECTION)
	var gun := Registry.weapon("boomstick")
	assert_bool(Registry.is_unlocked("weapon", "boomstick")).is_false()
	cs.call("_open_locked", gun)
	await get_tree().process_frame
	var line := cs.get("content").find_child("TrailLine", true, false) as WTap
	assert_object(line).is_not_null()
	assert_str((line.find_child("Words", true, false) as WText).text).is_equal("Reach Trail Level 8")
	assert_str(str(cs.call("_still_to_find", gun))).is_equal("Reach Trail Level 8")
	var state: Dictionary = cs.call("nav_state")
	assert_str(str(state["item"])).is_equal("boomstick")
	assert_bool(Nav.to_trail("weapon", "boomstick", cs)).is_true()
	assert_bool(Nav.back()).is_true()
	assert_array(_went).is_equal([Nav.TRAIL, COLLECTION])
	var cs2: Control = await _open(COLLECTION)
	assert_int(int(cs2.get("_tab"))).is_equal(int(state["tab"]))
	assert_str(str(cs2.get("_page").id)).is_equal("boomstick")


func test_the_trail_opened_by_its_tab_forgets_the_way_back() -> void:
	var hs: Control = await _open(HEROES)
	assert_bool(Nav.to_trail("outlaw", "calavera", hs)).is_true()
	# the player left by the tab bar instead; the next plain opening has no way back
	Nav.arrived()
	var s: TrailScreen = await _open()
	assert_bool(s._from_nav).is_false()
	assert_int(Nav.depth()).is_equal(0)
	# no node gives the Drifter: nothing to open
	assert_bool(Nav.to_trail("outlaw", "drifter", hs)).is_false()
