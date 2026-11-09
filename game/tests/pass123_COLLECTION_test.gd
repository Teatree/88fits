## Pass 123, lane COLLECTION: the Collection under the Royale theme as the mocks 10_Collection and 10_Item_detail (Garry:
## "Collection as the mock: docked tabs with counts, framed tiles, unfound items as silhouettes with their quest and a
## progress bar; the item page as slate cards (levels, mutations, evolution)" ... "Make it sit on a more solid background,
## not just hover in the air"), and the Wanted Collection left exactly as it was.
##  - Wanted: no sheet, no tab bar, the count and the kills line as WTexts, the tabs and the board where they always were;
##  - Royale: the fixed slate sheet framing the scroll, the docked tabs on its top edge (the open one gold, 74 tall, its
##    count from the data, the five across the sheet), the found total on its black plate, the 4-wide slate tiles with
##    120 px frames, unfound ones as silhouettes with their quest, a gold bar and its count, the kills pill above the
##    COLLECTIONS tab bar;
##  - the item page on one solid sheet under the header (the bar aside): the header card with its 200 px frame, LEVELS
##    as solid cells, MUTATIONS as framed purple columns with their full text, the EVOLUTION card's evolved frame; the
##    locked page, the creature page and a passive item's rung cells in the same shell; back returns to the grid.
extends GdUnitTestSuite

const SCENE := "res://ui/CollectionScreen.tscn"

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_settings_before)


func after_test() -> void:
	Settings.top_inset = int(_settings_before.get("top_inset", -1))
	CollectionScreen.hidden_only = false
	if Save.sandboxed():
		Save.end_sandbox()


## The screen in the tree, its board slid in (ScreenBase's 0.25 s entrance).
func _screen() -> CollectionScreen:
	var c: CollectionScreen = load(SCENE).instantiate()
	add_child(c)
	auto_free(c)
	await get_tree().create_timer(0.35).timeout
	return c


## The grid's tiles in order (the tree renames siblings that share a name: take them by kind, not by name).
func _tiles(c: CollectionScreen) -> Array:
	var grids := c.content.get_children().filter(func(n: Node) -> bool: return n is GridContainer and not n.is_queued_for_deletion())
	if grids.is_empty():
		return []
	return (grids[0] as Node).get_children().filter(func(n: Node) -> bool: return n is WTap and not n.is_queued_for_deletion())


func _sections(c: CollectionScreen) -> Array:
	return c.content.get_children().filter(func(n: Node) -> bool: return str(n.name).contains("Section") and not n.is_queued_for_deletion())


## A base weapon behind an unlock quest that counts (the sandbox's quests all undone).
func _locked_counting(c: CollectionScreen) -> WeaponDef:
	for def: ContentDef in c._items(0):
		if not c._locked(def):
			continue
		var q := Registry.quest_for(W.content_kind(def), def.id)
		if q and QuestTracker.progress(q).y > 0:
			return def as WeaponDef
	return null


# ---------------------------------------------------------------- Wanted is left as it was



# ---------------------------------------------------------------- the Royale grid

func test_royale_grid_frame_tabs_plate_and_pill() -> void:
	var c := await _screen()
	# the sheet frames the scroll: its edge just outside it, under it in the tree
	var sheet: PanelContainer = c._sheet
	assert_object(sheet).is_not_null()
	assert_str(sheet.name).is_equal("Sheet")
	assert_int(sheet.get_index()).is_less(c.scroll.get_index())
	assert_str((sheet.get_theme_stylebox("panel") as HardBox).royale_kind()).is_equal("panel")
	var e := float(R.PANEL_EDGE)
	assert_float(sheet.offset_top).is_equal_approx(c.scroll.offset_top - e, 0.5)
	assert_float(sheet.offset_bottom).is_equal_approx(c.scroll.offset_bottom + e, 0.5)
	assert_float(sheet.offset_left).is_equal(CollectionScreen.RY_SIDE)
	assert_float(sheet.offset_top).is_equal_approx(CollectionScreen.RY_SHEET_TOP + W.safe_top(), 0.5)
	# the docked tabs on its top edge, across it
	var tabs := c._tabs
	assert_float(tabs.offset_top).is_equal(CollectionScreen.RY_TAB_TOP + W.safe_top())
	assert_float(tabs.get_global_rect().end.y).is_equal_approx(sheet.get_global_rect().position.y, 1.0)
	assert_float(tabs.get_global_rect().size.x).is_equal_approx(sheet.get_global_rect().size.x, 1.0)
	var room := c.get_viewport_rect().size.x - 2.0 * CollectionScreen.RY_SIDE
	assert_float(tabs.get_combined_minimum_size().x).is_less_equal(room)
	var n0 := c._tally(0)
	for k in CollectionScreen.TABS.size():
		var tab: WTap = tabs._tabs[k]
		var lab: WText = tab.get_child(0)
		var on := k == 0
		assert_str((tab.box as HardBox).role).is_equal("gold" if on else "slate")
		assert_float(tab.size.y).override_failure_message("tab %d" % k).is_equal_approx(float(R.TAB_H_ACTIVE if on else R.TAB_H), 1.0)
		assert_bool(lab.color.is_equal_approx(R.NAVY if on else R.CREAM)).is_true()
		if on:
			assert_str(lab.text).is_equal("WEAPONS %d/%d" % [n0.x, n0.y])
			assert_bool(R.is_display(lab.font) or lab.font_size < R.ULTRA_MIN).is_true()
		else:
			assert_str(lab.text).is_equal(Loc.t(str(CollectionScreen.TABS[k])).to_upper())
			assert_bool(R.is_display(lab.font)).is_false()
			assert_int(lab.font_size).is_equal(CollectionScreen.RY_TAB_PX)
	# the found total on its black plate, from the data
	var found := 0
	var all := 0
	for t in CollectionScreen.TABS.size():
		var n := c._tally(t)
		found += n.x
		all += n.y
	assert_bool(c.header.right == c._count_box).is_true()
	assert_str(c._count_box.name).is_equal("Found")
	var runs: Array = c._count.runs
	assert_str(str(runs[0][0])).is_equal("%d / %d FOUND" % [found, all])
	assert_bool(R.is_display(runs[0][2])).is_true()
	# the kills pill above the open tab of the COLLECTIONS bar
	var bar: Control = c.tab_bar_node
	assert_object(bar).is_not_null()
	assert_str(str(bar.get("active"))).is_equal("collections")
	assert_bool(bar.visible).is_true()
	assert_str(c._foot_box.name).is_equal("Kills")
	assert_bool(c._foot_box.visible).is_true()
	assert_str(str(c._foot.runs[0][0])).is_equal(W.num(Save.total("kills")))
	assert_str(str(c._foot.runs[1][0])).is_equal(" kills all time")
	var vh := c.get_viewport_rect().size.y
	var bar_top := vh - c.tab_bar_height() - CollectionScreen.RY_OPEN_RISE
	assert_float(c._foot_box.get_global_rect().end.y).is_less_equal(bar_top - CollectionScreen.RY_PILL_GAP + 0.5)
	assert_float(c._foot_box.get_global_rect().position.y).is_greater(sheet.get_global_rect().end.y + float(R.PANEL_BASE))
	# the scroll ends inside the sheet's edge
	assert_float(c.scroll.offset_bottom).is_equal_approx(-c.bottom_total(), 0.5)


func test_royale_tiles_found_and_unfound() -> void:
	Save.begin_sandbox()
	Save.data["quests_done"] = []
	var c := await _screen()
	var grid: GridContainer = c.content.get_children().filter(func(n: Node) -> bool: return n is GridContainer)[0]
	assert_str(str(grid.name)).starts_with("Grid")
	assert_int(grid.columns).is_equal(4)
	var tiles := _tiles(c)
	assert_int(tiles.size()).is_equal(c._items(0).size())
	# four tiles across the sheet's inner width, about the mock's 232
	var w := (tiles[0] as Control).size.x
	assert_float(w).is_between(215.0, 240.0)
	var seen_found := false
	var seen_unfound := false
	for i in tiles.size():
		var t: WTap = tiles[i]
		var def: ContentDef = c._items(0)[i]
		assert_str((t.box as HardBox).royale_kind()).is_equal("panel")
		var plate: WPlate = t.find_child("Frame", true, false)
		assert_float(plate.side).is_equal(CollectionScreen.RY_FRAME)
		var name_t: WText = t.find_child("Name", true, false)
		var found: bool = c._found(def) and not c._locked(def)
		if found:
			seen_found = true
			assert_str(name_t.text).is_equal(def.display_name)
			assert_bool(name_t.color.is_equal_approx(R.WHITE)).is_true()
			assert_object(plate.find_child("Silhouette", false, false)).is_null()
			assert_object(plate.tex).is_not_null()
		else:
			seen_unfound = true
			assert_bool(plate.locked).is_true()
			var sil: Control = plate.find_child("Silhouette", false, false)
			assert_object(sil).is_not_null()
			assert_bool(sil.show_behind_parent).is_true()
			assert_object(plate.tex).is_null()
			assert_object(sil.get_meta("tex")).is_not_null()
			assert_bool(name_t.color.is_equal_approx(R.SECONDARY)).is_true()
	assert_bool(seen_unfound).is_true()
	# a locked weapon whose quest counts: its line, a gold bar and the count under it
	var lw := _locked_counting(c)
	if lw:
		var at := c._items(0).find(lw)
		var t: WTap = tiles[at]
		var q := Registry.quest_for("weapon", lw.id)
		var p := QuestTracker.progress(q)
		assert_str((t.find_child("Name", true, false) as WText).text).is_equal(c._still_to_find(lw))
		var bar: WBar = t.find_child("Bar", true, false)
		assert_object(bar).is_not_null()
		assert_float(bar.custom_minimum_size.y).is_equal(CollectionScreen.RY_BAR_H)
		assert_float(bar.value).is_equal_approx(clampf(float(p.x) / float(p.y), 0.0, 1.0), 0.001)
		assert_str((t.find_child("Count", true, false) as WText).text).is_equal("%s / %s" % [W.num(mini(p.x, p.y)), W.num(p.y)])
		# the bar sits at the tile's foot
		assert_float(bar.get_global_rect().end.y).is_greater(t.get_global_rect().get_center().y)
	# a tap on a found tile opens its page (the Wanted rule)
	if seen_found:
		for i in tiles.size():
			var def2: ContentDef = c._items(0)[i]
			if c._found(def2) and not c._locked(def2):
				(tiles[i] as WTap).pressed.emit()
				await get_tree().process_frame
				assert_object(c._page).is_equal(def2)
				break


func test_royale_tab_switch_and_back() -> void:
	var c := await _screen()
	(c._tabs._tabs[2] as WTap).pressed.emit()
	await get_tree().process_frame
	assert_int(c._tab).is_equal(2)
	var n := c._tally(2)
	assert_str(((c._tabs._tabs[2] as WTap).get_child(0) as WText).text).is_equal("PASSIVES %d/%d" % [n.x, n.y])
	assert_str(((c._tabs._tabs[0] as WTap).get_child(0) as WText).text).is_equal("WEAPONS")
	assert_str(((c._tabs._tabs[2] as WTap).box as HardBox).role).is_equal("gold")
	await get_tree().process_frame
	assert_int(_tiles(c).size()).is_equal(c._items(2).size())
	# every tab's open words fit with the rest across the sheet
	for k in CollectionScreen.TABS.size():
		c._tab = k
		c._show_grid()
		await get_tree().process_frame
		assert_float(c._tabs.get_combined_minimum_size().x).override_failure_message("tab %d" % k).is_less_equal(
			c.get_viewport_rect().size.x - 2.0 * CollectionScreen.RY_SIDE)


# ---------------------------------------------------------------- the Royale item page

func test_royale_weapon_page_on_one_solid_sheet() -> void:
	var c := await _screen()
	var w := Registry.weapon("boomstick")
	c._open_page(w)
	await get_tree().process_frame
	await get_tree().process_frame
	# the sheet under the header filling the screen, the bar, the tabs and the pill aside
	var e := float(R.PANEL_EDGE)
	assert_float(c.scroll.offset_top).is_equal_approx(CollectionScreen.RY_PAGE_TOP + e + W.safe_top(), 0.5)
	assert_float(c._sheet.offset_top).is_equal_approx(CollectionScreen.RY_PAGE_TOP + W.safe_top(), 0.5)
	# pass 123 (Garry's brief: "Keep the tab bar on all four hub screens"): the bar stays on the page, the sheet ends over it
	assert_float(c._sheet.offset_bottom).is_equal_approx(-(c.tab_bar_height() + CollectionScreen.RY_GRID_FOOT), 0.5)
	assert_bool(c.tab_bar_node.visible).is_true()
	assert_bool(c._tabs.visible).is_false()
	assert_bool(c._foot_box.visible).is_false()
	assert_float(c._sheet.get_global_rect().position.y).is_greater_equal(c.header.back_button.get_global_rect().end.y)
	assert_str(c.header.title.text).is_equal("BOOMSTICK")
	# the header card: a slate card, the 200 px frame, the kind, the effect in white, the tally's number white
	var card: PanelContainer = c.content.get_child(0)
	assert_str(card.name).is_equal("Card")
	assert_str((card.get_theme_stylebox("panel") as HardBox).royale_kind()).is_equal("panel")
	var frame: WPlate = card.find_child("Frame", true, false)
	assert_float(frame.side).is_equal(CollectionScreen.RY_PAGE_FRAME)
	var fx: WText = card.find_child("Effect", true, false)
	assert_str(fx.text).is_equal(c._full_text(w))
	assert_bool(fx.color.is_equal_approx(R.WHITE)).is_true()
	assert_int(fx.font_size).is_equal(CollectionScreen.RY_EFFECT_PX)
	var tally: WText = card.find_child("Tally", true, false)
	assert_object(tally).is_not_null()
	var kills := Save.keyed_total("kills_with_weapon", w.id)
	if kills > 0:
		var white := tally.runs.filter(func(r: Array) -> bool: return r.size() > 1 and r[1] is Color and (r[1] as Color).is_equal_approx(R.WHITE))
		assert_str(str(white[0][0])).is_equal(W.num(kills))
	# LEVELS, MUTATIONS, EVOLUTION
	var secs := _sections(c)
	assert_int(secs.size()).is_equal(3)
	var levels: Control = secs[0]
	var cells := levels.find_children("*Cell*", "", true, false)
	assert_int(cells.size()).is_equal(w.max_level - 1)
	var cb: HardBox = (cells[0] as Control).get_theme_stylebox("panel")
	assert_bool(cb.fill.is_equal_approx(R.CELL)).is_true()
	assert_int(cb.border).is_equal(R.CELL_EDGE)
	var muts := CollectionScreen.page_mutations(w)
	var cols := (secs[1] as Control).find_children("*Mutation*", "", true, false)
	assert_int(cols.size()).is_equal(muts.size())
	for i in cols.size():
		var m: MutationDef = muts[i]
		var texts := (cols[i] as Control).find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is WText)
		# the full text, not only its first sentence
		var has_full := texts.any(func(t: WText) -> bool: return t.text == m.text.strip_edges())
		assert_bool(has_full).override_failure_message(m.id).is_true()
		var mp: WPlate = (cols[i] as Control).find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is WPlate)[0]
		assert_str(mp.frame_rarity()).is_equal("mutation")
	var evo: PanelContainer = (secs[2] as Control).find_child("Evolution", true, false)
	assert_object(evo).is_not_null()
	var ef: WPlate = evo.find_child("Frame", true, false)
	assert_float(ef.side).is_equal(CollectionScreen.RY_EVO_FRAME)
	var evo_def := Registry.weapon(w.evolves_into)
	var evo_found := Save.keyed_total("kills_with_weapon", evo_def.id) > 0 or Save.seen("weapon", evo_def.id)
	assert_bool(ef.is_evolved_frame()).is_equal(evo_found)
	assert_float(evo.modulate.a).is_equal(1.0 if evo_found else 0.75)
	# back: the grid, the bar and the pill again
	c.on_back()
	await get_tree().process_frame
	assert_object(c._page).is_null()
	assert_bool(c.tab_bar_node.visible).is_true()
	assert_bool(c._foot_box.visible).is_true()
	assert_bool(c._tabs.visible).is_true()
	assert_float(c._sheet.offset_top).is_equal_approx(CollectionScreen.RY_SHEET_TOP + W.safe_top(), 0.5)
	assert_bool(c.header.right == c._count_box).is_true()


func test_royale_locked_creature_and_passive_pages() -> void:
	Save.begin_sandbox()
	Save.data["quests_done"] = []
	var c := await _screen()
	# a locked weapon: the silhouette frame, the quest, its bar and count, WHAT IT DOES in a cell
	var lw := _locked_counting(c)
	assert_object(lw).is_not_null()
	c._open_locked(lw)
	await get_tree().process_frame
	var card: PanelContainer = c.content.get_child(0)
	assert_str(card.name).is_equal("Card")
	var frame: WPlate = card.find_child("Frame", true, false)
	assert_bool(frame.locked).is_true()
	assert_object(frame.find_child("Silhouette", false, false)).is_not_null()
	var q := Registry.quest_for("weapon", lw.id)
	assert_str((card.find_child("Quest", true, false) as WText).text).is_equal(TextGen.quest_text(q))
	var p := QuestTracker.progress(q)
	assert_str((card.find_child("Count", true, false) as WText).text).is_equal("%s / %s" % [W.num(mini(p.x, p.y)), W.num(p.y)])
	assert_object(card.find_child("Bar", true, false)).is_not_null()
	var secs := _sections(c)
	assert_int(secs.size()).is_equal(1)
	assert_int((secs[0] as Control).find_children("*Cell*", "", true, false).size()).is_equal(1)
	assert_bool(c.tab_bar_node.visible).is_true()
	# a boss: its badge and ring on the 200 px frame, its numbers in cells, the tally's number white
	var boss := Registry.enemy("brander")
	c._open_page(boss)
	await get_tree().process_frame
	card = c.content.get_child(0)
	frame = card.find_child("Frame", true, false)
	assert_object(frame.badge).is_not_null()
	assert_int(frame.ring).is_greater(0)
	assert_int(c.content.get_child_count()).is_greater_equal(3)
	var cells := (_sections(c)[0] as Control).find_children("*Cell*", "", true, false)
	assert_int(cells.size()).is_greater_equal(3)
	var tally: WText = card.find_child("Tally", true, false)
	var num := W.num(Save.keyed_total("kills_of_enemy", boss.id))
	assert_bool(tally.runs.any(func(r: Array) -> bool: return str(r[0]) == num and r[1] is Color and (r[1] as Color).is_equal_approx(R.WHITE))).is_true()
	# a passive item on the ladder: its rung cells washed with their rarity, each rung its own
	var item: PassiveDef = null
	for pd: PassiveDef in Registry.sorted_passives_only():
		if pd.on_ladder():
			item = pd
			break
	assert_object(item).is_not_null()
	c._open_page(item)
	await get_tree().process_frame
	var rung_cells := (_sections(c)[0] as Control).find_children("*Cell*", "", true, false)
	assert_int(rung_cells.size()).is_greater(1)
	var fills: Array = []
	for rc in rung_cells:
		var f: Color = ((rc as Control).get_theme_stylebox("panel") as HardBox).fill
		assert_bool(f.is_equal_approx(R.CELL)).is_false()
		if not fills.any(func(x: Color) -> bool: return x.is_equal_approx(f)):
			fills.append(f)
	assert_int(fills.size()).is_equal(rung_cells.size())
	assert_bool(CollectionScreen.rung_tint(item, 1).is_equal_approx(R.CELL.lerp(R.RARITY[W.rung_of(item, 1)]["base"], 0.3))).is_true()


func test_royale_hidden_list_and_inset() -> void:
	CollectionScreen.hidden_only = true
	var c := await _screen()
	assert_object(c.tab_bar_node).is_null()
	assert_bool(c._tabs.visible).is_false()
	assert_bool(c._foot_box.visible).is_false()
	assert_str(str(c._count.runs[0][0])).is_equal("%d HIDDEN" % CollectionScreen.hidden_items().size())
	assert_float(c._sheet.offset_top).is_equal_approx(CollectionScreen.RY_PAGE_TOP + W.safe_top(), 0.5)
	CollectionScreen.hidden_only = false
	# a camera cutout: the tabs and the sheet move down with it, the back square stays clear
	Settings.top_inset = 130
	var d := await _screen()
	assert_float(d._tabs.offset_top).is_equal(CollectionScreen.RY_TAB_TOP + 130.0)
	assert_float(d._sheet.offset_top).is_equal_approx(CollectionScreen.RY_SHEET_TOP + 130.0, 0.5)
	var back := d.header.back_button.get_global_rect()
	assert_bool(back.intersects(d._tabs.get_global_rect())).is_false()
	assert_bool(back.intersects(d.scroll.get_global_rect())).is_false()
	assert_int(d.header.get_index()).is_greater(d._tabs.get_index())


func test_silhouette_moves_the_icon_into_a_shape() -> void:
	var p: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("revolver"), 120.0, true, 1))
	var tex := p.tex
	CollectionScreen.silhouette(p)
	assert_object(p.tex).is_null()
	var s: Control = p.find_child("Silhouette", false, false)
	assert_object(s).is_not_null()
	assert_object(s.get_meta("tex")).is_equal(tex)
	assert_float(s.size.x).is_equal(120.0)
	assert_bool(CollectionScreen.RY_SILHOUETTE.v < 0.1).is_true()
	# a plate with no icon is left alone
	var q: WPlate = auto_free(WPlate.new())
	CollectionScreen.silhouette(q)
	assert_object(q.find_child("Silhouette", false, false)).is_null()


func test_the_capture_and_audit_tools_carry_the_new_states() -> void:
	var shots := FileAccess.get_file_as_string("res://tools/wanted_shots.gd")
	assert_str(shots).contains("\"collection_more\"")
	assert_str(shots).contains("func _collection_more()")
	for s in ["04l-collection-passive-page", "04m-collection-card-page", "04n-collection-perk-page",
			"04o-collection-weapon-page-foot", "04p-collection-grid-foot", "04q-collection-hidden"]:
		assert_str(shots).contains(s)
	var audit := FileAccess.get_file_as_string("res://tools/touch_audit.gd")
	assert_str(audit).contains("func _collection_royale_audit()")
