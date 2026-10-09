## Pass 61, lane MR (Garry: "The choices in the Mirror should be shown as little icons. Maybe as a summary also. Each of
## those icons should be distinctly different from their counterpart. So say Grit will have a progress bar filled up with
## 2 types of distinct icons representing choices that Player made. Make the UI elements taller to make enough space for
## those icons to make sense as well as the empty bars." and "Make the EXP bar 1.8 times bigger. Make sure the rainbow
## animation isn't broken."): every talent form has its own painted icon, each board tile a rank bar (bought ranks the
## live form's icon, the rest dashed empties) and, with no rank, both forms' icons beside the name; a summary strip lists
## the talents with ranks; the sheet shows the bar and the forms with their icons. The XP rail is 65 px (36 x 1.8), its
## fill 11 px in, everything under it laid out from its foot, and the level-up screen's rainbow copy reads the same pair.
extends GdUnitTestSuite

const HOME := "res://ui/HomesteadScreen.tscn"


func _fresh_save() -> void:
	Save.data = Save._default()
	Save._migrate_seen()


func after_test() -> void:
	Settings.top_inset = -1
	Run.arena = false
	Run.end()
	HUD.band_h = float(HUD.BAND_H)
	Save.data["talents"] = {}
	Save.data["talent_spent"] = 0


func _home() -> Control:
	var h: Control = auto_free(load(HOME).instantiate())
	add_child(h)
	await get_tree().process_frame
	await get_tree().process_frame
	return h


func _tile(h: Control, id: String) -> Control:
	return h._grid.find_child("Talent_" + id, false, false) as Control


func _slots(bar: Node) -> Array:
	var out: Array = []
	for c in bar.get_children():
		if c is WPlate and not (c as Node).is_queued_for_deletion():
			out.append(c)
	return out


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			s += (n as WText).text + " "
	return s


# ---------------------------------------------------------------- 1. the rail, 1.8 times

func test_the_rail_is_one_point_eight_times_its_pass_56_height() -> void:
	assert_float(HUD.RAIL_H).is_equal(roundf(36.0 * 1.8))
	assert_float(HUD.RAIL_H).is_equal(65.0)
	assert_float(HUD.RAIL_INSET).is_equal(roundf(6.0 * 1.8))
	# the fill keeps its two thirds of the rail (24 of 36 before, 43 of 65 now)
	assert_float(HUD.RAIL_H - 2.0 * HUD.RAIL_INSET).is_equal(43.0)
	# everything under it laid out from its foot, the gaps as before
	assert_float(HUD.TOP_Y).is_equal(HUD.RAIL_H + 12.0)
	assert_float(HUD.SLOT_Y).is_equal(HUD.TOP_Y + 96.0)
	assert_float(float(HUD.BAND_H)).is_equal(HUD.SLOT_Y + 94.0)
	# the level-up screen's rainbow rail is the same rail, and its header and cards moved down by what it gained
	assert_float(CardScreen.RAIL_H).is_equal(HUD.RAIL_H)
	assert_float(CardScreen.RAIL_INSET).is_equal(HUD.RAIL_INSET)
	assert_float(CardScreen.RAIL_GROWTH).is_equal(HUD.RAIL_H - 18.0)
	assert_float(CardScreen.HEADER_TOP).is_equal(110.0 + 47.0)
	assert_float(CardScreen.LIST_TOP).is_equal(470.0 + 47.0)
	# the glint grew with the fill
	assert_float(CardScreen.RAIL_GLINT).is_equal(7.0)


func test_the_hud_lays_out_under_the_thicker_rail_with_and_without_a_cutout() -> void:
	for inset: int in [0, 130]:
		Settings.top_inset = inset
		Run.start(Registry.character("astro"), Registry.map("red_canyon"))
		Run.debug_clear_items()
		Run.add_weapon(Registry.weapon("boomstick"), 2)
		var hud: HUD = auto_free(HUD.new())
		add_child(hud)
		await get_tree().process_frame
		await get_tree().process_frame
		var why := "inset %d" % inset
		var rail := hud.find_child("XpRail", false, false) as Control
		assert_float(rail.get_global_rect().position.y).override_failure_message(why).is_equal(float(inset))
		assert_float(rail.size.y).override_failure_message(why).is_equal(65.0)
		var foot := float(inset) + 65.0
		assert_float(hud._lv_plate.get_global_rect().position.y).override_failure_message(why).is_equal(foot + 12.0)
		assert_float(hud._pause_btn.get_global_rect().position.y).override_failure_message(why).is_equal(foot + 10.0)
		assert_float(hud._slots.position.y).override_failure_message(why).is_equal(foot + 108.0)
		assert_float(HUD.band_h).override_failure_message(why).is_equal(float(HUD.BAND_H) + inset)
		# nothing in the top row starts above the rail's foot
		for p: Control in [hud._lv_plate, hud._timer_plate, hud._gold_plate, hud._pause_btn]:
			assert_float(p.get_global_rect().position.y).override_failure_message(why + " " + str(p.name)).is_greater_equal(foot)
		hud.queue_free()
		Run.end()
		await get_tree().process_frame


func test_the_rainbow_rail_fills_the_new_height_and_keeps_moving() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer(CardPool.level_up_offer(3), "LEVEL 2!", false)
	await get_tree().process_frame
	var rail := cs.find_child("XpRail", false, false) as Control
	assert_float(rail.size.y).is_equal(65.0)
	assert_float(rail.size.x).is_equal(cs.get_viewport_rect().size.x)
	assert_float(cs.rail_frac()).is_equal(1.0)
	# the hues race: the colour at one spot changes as the screen's clock runs
	var t0: float = cs._rail_t
	for i in 10:
		await get_tree().process_frame
	var t1: float = cs._rail_t
	assert_float(t1).is_greater(t0)
	assert_bool(CardScreen.rail_colour(0.2, t0).is_equal_approx(CardScreen.rail_colour(0.2, t1))).is_false()
	# the header and the cards still sit under the rail's foot
	assert_float(cs.header.get_global_rect().position.y).is_greater(rail.get_global_rect().end.y)
	assert_float(cs._list.get_global_rect().position.y).is_greater(rail.get_global_rect().end.y)
	cs.visible = false


# ---------------------------------------------------------------- 2. the icons

func test_every_talent_form_has_its_own_icon_and_the_two_differ() -> void:
	assert_int(Registry.talents_list().size()).is_equal(8)
	for def: TalentDef in Registry.talents_list():
		assert_int(def.forms.size()).is_equal(2)
		var means: Array = []
		for f in 2:
			var tex := def.form_icon(f)
			assert_object(tex).override_failure_message("%s form %d has no icon" % [def.id, f]).is_not_null()
			assert_str(tex.resource_path).is_equal("res://content/talents/%s/%s_%d_icon.png" % [def.id, def.id, f])
			assert_float(tex.get_size().x).is_greater_equal(128.0)
			means.append(_mean_colour(tex))
		# each pair different in colour as well as in shape (Garry: "distinctly different from their counterpart")
		var a: Color = means[0]
		var b: Color = means[1]
		var dist := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
		assert_float(dist).override_failure_message("%s: its two icons' colours are %.3f apart" % [def.id, dist]).is_greater(0.12)


## The mean colour of the icon's opaque pixels.
func _mean_colour(tex: Texture2D) -> Color:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var acc := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				acc += Vector3(c.r, c.g, c.b)
				n += 1
	if n == 0:
		return Color.BLACK
	acc /= float(n)
	return Color(acc.x, acc.y, acc.z)


# ---------------------------------------------------------------- 3. the board's rank bars

func test_a_tile_shows_its_bought_ranks_as_the_live_form_s_icons_and_the_rest_empty() -> void:
	_fresh_save()
	Save.data["talents"] = {"grit": {"form": 1, "rank": 3}}
	var h := await _home()
	var grit: TalentDef = Registry.talent("grit")
	var tile := _tile(h, "grit")
	assert_object(tile).is_not_null()
	var bar := tile.find_child("RankBar", true, false)
	var slots := _slots(bar)
	assert_int(slots.size()).is_equal(grit.max_rank())
	for k in slots.size():
		var p: WPlate = slots[k]
		if k < 3:
			assert_bool(p.get_meta("bought")).is_true()
			assert_bool(p.empty).is_false()
			assert_object(p.tex).is_same(grit.form_icon(1))
		else:
			assert_bool(p.get_meta("bought")).is_false()
			assert_bool(p.empty).is_true()
			assert_object(p.tex).is_null()
	# pass 63: while a rank is left the pair beside the name stays (every rank is its own choice)
	assert_object(tile.find_child("FormIcons", true, false)).is_not_null()
	# a bar holds both icons, rank by rank in the order they were bought (pass 63: a rank keeps its form)
	Save.data["talents"] = {"grit": {"picks": [0, 0, 0]}}
	h._refresh()
	tile = _tile(h, "grit")
	slots = _slots(tile.find_child("RankBar", true, false))
	var bought := 0
	for p: WPlate in slots:
		if p.get_meta("bought"):
			bought += 1
			assert_object(p.tex).is_same(grit.form_icon(0))
	assert_int(bought).is_equal(3)
	assert_int(Save.talent_rank("grit")).is_equal(3)
	h.visible = false
	# the tiles _refresh took out are freed at the frame's end
	await get_tree().process_frame


func test_a_talent_with_no_rank_shows_six_empties_and_both_form_icons_beside_its_name() -> void:
	_fresh_save()
	var h := await _home()
	for def: TalentDef in Registry.talents_list():
		var tile := _tile(h, def.id)
		var slots := _slots(tile.find_child("RankBar", true, false))
		assert_int(slots.size()).is_equal(6)
		for p: WPlate in slots:
			assert_bool(p.empty).is_true()
		var pair := tile.find_child("FormIcons", true, false)
		assert_object(pair).override_failure_message(def.id).is_not_null()
		var icons: Array = []
		for c in pair.get_children():
			if c is WPlate:
				icons.append((c as WPlate).tex)
		assert_int(icons.size()).is_equal(2)
		assert_object(icons[0]).is_same(def.form_icon(0))
		assert_object(icons[1]).is_same(def.form_icon(1))
	h.visible = false


func test_the_tiles_grew_to_hold_the_bar_and_still_fit_their_column() -> void:
	_fresh_save()
	Save.data["talents"] = {"nerve": {"form": 1, "rank": 6}}
	var h := await _home()
	var grid: GridContainer = h._grid
	for tile: Control in grid.get_children():
		assert_float(tile.size.x).is_less_equal((h.content.size.x - 24.0) * 0.5 + 0.5)
		var bar := tile.find_child("RankBar", true, false) as Control
		var r := tile.get_global_rect()
		var br := bar.get_global_rect()
		# the whole bar inside the tile, under the name, over the price
		assert_bool(r.grow(0.5).encloses(br)).override_failure_message(str(tile.name)).is_true()
		var price := tile.find_child("Price", true, false) as Control
		if price:
			assert_float(price.get_global_rect().position.y).is_greater_equal(br.end.y)
		# taller than a tile of name, notches, line and tag (about 220 px before)
		assert_float(tile.size.y).is_greater(260.0)
	h.visible = false


# ---------------------------------------------------------------- 4. the summary

func test_the_summary_lists_only_talents_with_ranks_in_board_order() -> void:
	_fresh_save()
	var h := await _home()
	var flow: Node = h._summary_flow
	# nothing bought: no chips, one line instead
	assert_int(flow.find_children("Chip_*", "", false, false).size()).is_equal(0)
	assert_object(flow.find_child("Hint", false, false)).is_not_null()
	Save.data["talents"] = {"stride": {"form": 1, "rank": 1}, "grit": {"form": 0, "rank": 3}, "spite": {"form": 0, "rank": 0}}
	h._refresh()
	# (pass 63: a chip a form held, named Chip_<talent>_<form>)
	var chips: Array = []
	for c in flow.get_children():
		if str(c.name).begins_with("Chip_"):
			chips.append(c)
	assert_int(chips.size()).is_equal(2)
	assert_str(str(chips[0].name)).is_equal("Chip_grit_0")
	assert_str(str(chips[1].name)).is_equal("Chip_stride_1")
	assert_object(flow.find_child("Hint", false, false)).is_null()
	assert_str(_texts(chips[0])).contains("x3")
	assert_str(_texts(chips[1])).contains("x1")
	var plate: WPlate = chips[1].get_child(0)
	assert_object(plate.tex).is_same(Registry.talent("stride").form_icon(1))
	var listed: Array = []
	for def: TalentDef in h.summary_talents():
		listed.append(def.id)
	assert_array(listed).is_equal(["grit", "stride"])
	h.visible = false
	await get_tree().process_frame


# ---------------------------------------------------------------- 5. the sheet

func test_the_sheet_shows_the_bar_and_both_forms_with_their_icons() -> void:
	_fresh_save()
	Save.data["talents"] = {"grit": {"form": 1, "rank": 2}}
	var h := await _home()
	var grit: TalentDef = Registry.talent("grit")
	h._open(grit)
	await get_tree().process_frame
	await get_tree().process_frame
	var sheet: Control = h._sheet_root.find_child("Sheet", true, false)
	var bar := sheet.find_child("RankBar", true, false)
	var slots := _slots(bar)
	assert_int(slots.size()).is_equal(6)
	var bought := 0
	for p: WPlate in slots:
		if p.get_meta("bought"):
			bought += 1
			assert_object(p.tex).is_same(grit.form_icon(1))
	assert_int(bought).is_equal(2)
	# pass 63: one offer a form, each with its icon and its own buy button; no form switch any more
	assert_object(sheet.find_child("Forms", true, false)).is_null()
	for f in range(2):
		var offer: Node = sheet.find_child("Offer%d" % f, true, false)
		assert_object(offer).is_not_null()
		var pic: WPlate = null
		for n in offer.find_children("*", "", true, false):
			if n is WPlate:
				pic = n
				break
		assert_object(pic.tex).is_same(grit.form_icon(f))
		assert_object(offer.find_child("Buy%d" % f, true, false)).is_not_null()
	# the sheet still fits its width
	assert_float(sheet.get_combined_minimum_size().x).is_less_equal(sheet.size.x + 0.5)
	# buying the next rank as Padding adds a Padding rank after the two Plate ones; nothing moves
	Save.add_gold(100000)
	assert_bool(Save.buy_talent(grit, 0)).is_true()
	assert_array(Save.talent_picks("grit")).is_equal([1, 1, 0])
	h._fill_sheet(sheet)
	await get_tree().process_frame
	await get_tree().process_frame
	var bar2 := sheet.find_child("RankBar", true, false)
	var icons: Array = []
	for p: WPlate in _slots(bar2):
		if p.get_meta("bought"):
			icons.append(p.tex)
	assert_int(icons.size()).is_equal(3)
	assert_object(icons[0]).is_same(grit.form_icon(1))
	assert_object(icons[1]).is_same(grit.form_icon(1))
	assert_object(icons[2]).is_same(grit.form_icon(0))
	h._close(false)
	h.visible = false
