## Pass 123, lane UPGRADE: the Upgrade board (ui/HomesteadScreen.gd, "the Mirror" in code) under Royale as the mock
## 5_Upgrade (Garry: "Upgrade board as the mock: no mirror, YOU HOLD and TAKE IT ALL BACK with the refund line in the
## header, 2x4 tiles with both options and their effect lines from data, a blue price · CHOOSE opening a pop-up with two
## green BUY buttons"; "the 'Your Upgrades' part ... needs to have enough space for all of them. Also, change the text
## 'Take it all back' to just be 'Reset Upgrades'"; "Filled rank pips show the chosen option's icon"; the tab bar on the
## hub screens, the board above it):
##  - the board's structure (no mirror, YOU HOLD, RESET UPGRADES and its refund line, eight tiles in Registry.talents_list's
##    order, each with both options from data, the pips, the blue CHOOSE), the tab bar with UPGRADE open;
##  - the effect lines (TextGen of one rank, "per rank", shared numbers said once);
##  - YOU HOLD's room for all sixteen options, the board above the tab bar on a 1080 x 1920 canvas;
##  - CHOOSE's pop-up (the shared shell, a green BUY per option), BUY in each option as the Wanted sheet buys, the short
##    state, MAXED, RESET UPGRADES asking in red and refunding half;
##  - Wanted built exactly as before; the capture and audit tools' new states.
extends GdUnitTestSuite

const HS := preload("res://ui/HomesteadScreen.gd")

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.from_dict(_settings_before)
	W.theme_changed()


func after_test() -> void:
	Settings.ui_theme = "wanted"
	W.theme_changed()
	if Save.sandboxed():
		Save.end_sandbox()


func _royale(on: bool) -> void:
	Settings.ui_theme = "royale" if on else "wanted"
	W.theme_changed()


## What `talents` ({id: {"picks": [...]}}) cost at today's prices.
func _spent_of(talents: Dictionary) -> int:
	var n := 0
	for id in talents.keys():
		var def := Registry.talent(str(id))
		var picks: Array = (talents[id] as Dictionary).get("picks", [])
		for k in picks.size():
			n += maxi(def.cost_of_rank(k), 0)
	return n


## The board in a sandboxed save holding `talents` and `gold`, under Royale or Wanted, laid out.
func _board(royale: bool, talents: Dictionary = {}, gold: int = 108411) -> Control:
	Save.begin_sandbox()
	Save.data["talents"] = talents.duplicate(true)
	Save.data["gold"] = gold
	Save.data["talent_spent"] = _spent_of(talents)
	Save.data["talent_spent_in"] = {}
	_royale(royale)
	var h: Control = auto_free(load("res://ui/HomesteadScreen.tscn").instantiate())
	add_child(h)
	for k in 3:
		await get_tree().process_frame
	return h


## Every word under `n`: WText texts and runs, button labels, star lines.
func _texts(n: Node) -> String:
	var out: Array = []
	for c in n.find_children("*", "", true, false):
		if c is WText:
			var w := c as WText
			if w.text != "":
				out.append(w.text)
			else:
				var s := ""
				for r in w.runs:
					s += str(r[0])
				if s != "":
					out.append(s)
		elif c is WButton:
			out.append((c as WButton).label_text())
	return " | ".join(out)


func _tile(h: Control, id: String) -> Control:
	return (h.get("_grid") as Node).get_node_or_null("Talent_" + id) as Control


func _choose(h: Control, id: String) -> WButton:
	return _tile(h, id).find_child("Choose", true, false) as WButton


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


# ---------------------------------------------------------------- the board

func test_the_royale_board_is_the_mock_s_layout() -> void:
	var h: Control = await _board(true, {"grit": {"picks": [0]}, "drive": {"picks": [1]}})
	assert_bool(h.get("_royale_built")).is_true()
	# no mirror, no Wanted summary strip, no footer link
	assert_object(h.find_child("Summary", true, false)).is_null()
	for t in h.find_children("*", "TextureRect", true, false):
		var tex: Texture2D = (t as TextureRect).texture
		assert_bool(tex != null and tex.resource_path == HS.MIRROR_ART).is_false()
	assert_str(_texts(h)).not_contains("Something looks back")
	assert_object(h.get("_refund")).is_null()
	# the header: UPGRADE in capitals, the wallet
	assert_str((h.get("title_label") as WText).text).is_equal("UPGRADE")
	assert_str((h.find_child("Amount", true, false) as WText).text).is_equal(W.num(108411))
	# YOU HOLD, then RESET UPGRADES (slate) with the refund line under it
	var row: Control = h.find_child("HoldRow", true, false)
	assert_object(row).is_not_null()
	assert_str((row.find_child("HoldLabel", true, false) as WText).text).is_equal("YOU HOLD")
	var chips: Array = []
	for c in (h.get("_summary_flow") as Node).get_children():
		chips.append(str(c.name))
	# board order: Drive comes before Grit (Registry.talents_list)
	assert_array(chips).is_equal(["Chip_drive_1", "Chip_grit_0"])
	var chip: WPlate = (h.get("_summary_flow") as Node).get_node("Chip_drive_1")
	assert_object(chip.tex).is_equal(Registry.talent("drive").form_icon(1))
	assert_int(chip.level_plaque).is_equal(1)
	var reset: WButton = row.find_child("Reset", true, false)
	assert_str(reset.label_text()).is_equal("RESET UPGRADES")
	assert_str(reset.role).is_equal(WButton.SLATE)
	assert_bool(reset.locked).is_false()
	var said := _texts(row.find_child("Refund", true, false))
	assert_str(said).contains("%s of the %s spent comes back" % [W.num(Save.talent_refund()), W.num(Save.talent_spent())])
	assert_str(said).contains("every rank is forgotten")
	# the board: two columns, the eight talents in the board's order
	var grid: GridContainer = h.get("_grid")
	assert_int(grid.columns).is_equal(2)
	var names: Array = []
	for c in grid.get_children():
		names.append(str(c.name))
	var want: Array = []
	for def: TalentDef in Registry.talents_list():
		want.append("Talent_" + def.id)
	assert_array(names).is_equal(want)
	# the tab bar with UPGRADE open
	var bar: Control = h.get("tab_bar_node")
	assert_object(bar).is_not_null()
	assert_str(str(bar.get("active"))).is_equal("upgrade")


func test_each_tile_carries_both_options_from_data() -> void:
	var h: Control = await _board(true, {"grit": {"picks": [1, 0]}})
	for def: TalentDef in Registry.talents_list():
		var tile := _tile(h, def.id)
		var picks := Save.talent_picks(def.id)
		var rank := picks.size()
		assert_str((tile.find_child("Name", true, false) as WText).text).is_equal(def.display_name)
		assert_str((tile.find_child("Rank", true, false) as WText).text).is_equal("RANK %d / %d" % [rank, def.max_rank()])
		for f in range(2):
			var form: Control = tile.find_child("Form%d" % f, true, false)
			# pass 123 (Garry: "Looks way too busy"): the icon bare on the tile, no frame
			var frame: TextureRect = form.find_child("Frame", true, false)
			assert_float(frame.custom_minimum_size.x).is_equal(HS.R_FORM)
			assert_object(frame.texture).is_equal(def.form_icon(f))
			assert_str((form.find_child("FormName", true, false) as WText).text).is_equal(def.form_name(f))
			var line := (form.find_child("Effect", true, false) as WText).text
			assert_str(line).is_equal(HS.form_line(def, f).trim_suffix(" per rank"))
			assert_str(line).not_contains("/ LV")
		assert_object(tile.find_child("Or", true, false)).is_null()
		var track: Control = tile.find_child("RankBar", true, false)
		assert_array(track.get_meta("picks")).is_equal(picks)
		var b := _choose(h, def.id)
		assert_str(b.role).is_equal(WButton.BLUE)
		assert_int(int(b.get_meta("price"))).is_equal(def.cost_of_rank(rank))
		assert_str(b.label_text()).contains("%s · CHOOSE" % W.num(def.cost_of_rank(rank)))


func test_the_effect_lines_are_textgen_per_rank_with_shared_numbers_said_once() -> void:
	for def: TalentDef in Registry.talents_list():
		for f in range(2):
			var line := HS.form_line(def, f)
			assert_str(line).is_equal(HS.grouped_text(def.summed_effects(f, 1)) + " per rank")
			assert_str(line).not_contains("/ LV")
	# one effect: TextGen's own words
	var one := Effect.make("max_hp", "mul", 0.1, "player")
	assert_str(HS.grouped_text([one])).is_equal(TextGen.describe_effect(one))
	# the same number on stats that share their first words: said once
	var hp := Effect.make("danger_hp", "add", 0.1, "player")
	var atk := Effect.make("danger_attack", "add", 0.1, "player")
	var spd := Effect.make("danger_speed", "add", 0.04, "player")
	var bounty := Effect.make("danger_bounty", "add", 0.05, "player")
	var want := "%s %s, %s" % [TextGen.describe_effect(hp, false), HS.joined_names([TextGen.stat_name("danger_hp"),
		TextGen.stat_name("danger_attack")]), TextGen.describe_effect(spd)]
	assert_str(HS.grouped_text([hp, atk, spd, bounty])).is_equal(want)
	# different numbers are not joined, a hidden stat says nothing
	var atk2 := Effect.make("danger_attack", "add", 0.2, "player")
	assert_str(HS.grouped_text([hp, atk2])).is_equal(TextGen.describe_effect(hp) + ", " + TextGen.describe_effect(atk2))
	assert_str(HS.grouped_text([bounty])).is_equal("")
	assert_str(HS.joined_names(["enemy HP", "enemy attack"])).is_equal("enemy HP and attack")
	assert_str(HS.joined_names(["boss and Elite HP", "boss and Elite attack"])).is_equal("boss and Elite HP and attack")
	assert_str(HS.joined_names(["max HP", "regen"])).is_equal("max HP and regen")
	assert_str(HS.joined_names(["a x", "a y", "a z"])).is_equal("a x, y and z")


func test_you_hold_keeps_room_for_every_option_and_never_widens_the_board() -> void:
	var h: Control = await _board(true)
	var flow: Control = h.get("_summary_flow")
	var empty_size := flow.size
	var hint: WText = flow.get_node_or_null("Hint")
	assert_object(hint).is_not_null()
	assert_str(hint.text).is_equal("Nothing bought yet: every rank you buy shows here.")
	assert_bool((h.get("_reset") as WButton).locked).is_true()
	assert_str(_texts(h.find_child("Refund", true, false))).is_equal("Nothing to take back")
	remove_child(h)
	await get_tree().process_frame
	Save.end_sandbox()
	# every talent holding both options at full price: sixteen frames in the same room, the row no wider than the board
	var all := {}
	for def: TalentDef in Registry.talents_list():
		var picks: Array = []
		for k in def.max_rank():
			picks.append(k % 2)
		all[def.id] = {"picks": picks}
	var h2: Control = await _board(true, all, 0)
	var flow2: Control = h2.get("_summary_flow")
	assert_int(flow2.get_child_count()).is_equal(16)
	assert_vector(flow2.size).is_equal(empty_size)
	var room := flow2.get_global_rect()
	for c in flow2.get_children():
		var p := c as WPlate
		var r := p.get_global_rect()
		assert_bool(room.grow(0.5).encloses(Rect2(r.position, r.size + Vector2(0, HS.R_CHIP_HANG)))) \
			.override_failure_message("%s at %s outside %s" % [p.name, r, room]).is_true()
		assert_int(p.level_plaque).is_equal(Save.talent_count(str(p.name).split("_")[1], int(str(p.name).split("_")[2])))
	var content: Control = h2.get("content")
	var row: Control = h2.find_child("HoldRow", true, false)
	assert_float(row.size.x).is_less_equal(content.size.x + 0.5)
	for t in h2.find_child("Refund", true, false).get_children():
		assert_int((t as WText).font_size).is_greater_equal(HS.R_REFUND_MIN_PX)
		assert_float((t as WText).size.x).is_less_equal(row.size.x)
	var grid: Control = h2.get("_grid")
	assert_float(grid.size.x).is_less_equal(content.size.x + 0.5)


func test_the_whole_board_fits_above_the_tab_bar_on_the_canvas() -> void:
	# the tallest board: every talent with ranks of both options (Stakes' two-line options too), short of gold everywhere
	var all := {}
	for def: TalentDef in Registry.talents_list():
		all[def.id] = {"picks": [0, 1]}
	var h: Control = await _board(true, all, 10)
	await _wait(0.4)
	var vh := h.get_viewport_rect().size.y
	assert_float(vh).is_equal(1920.0)
	var bar_top := vh - float(load("res://ui/wanted/WTabBar.gd").reach())
	var grid: Control = h.get("_grid")
	for tile in grid.get_children():
		var r := (tile as Control).get_global_rect()
		assert_float(r.end.y + R.PANEL_BASE).override_failure_message("%s ends at %.0f, the open tab at %.0f" % [tile.name,
			r.end.y + R.PANEL_BASE, bar_top]).is_less_equal(bar_top)
	# nothing to scroll
	var sc: ScrollContainer = h.get("scroll")
	var inner: Control = sc.get_child(0)
	assert_float(inner.get_combined_minimum_size().y).is_less_equal(sc.size.y + 0.5)
	# the YOU HOLD row starts under the header
	var row: Control = h.find_child("HoldRow", true, false)
	assert_float(row.get_global_rect().position.y).is_greater_equal(HS.R_TOP - 0.5)


# ---------------------------------------------------------------- CHOOSE and BUY

func test_choose_opens_the_shared_shell_with_a_green_buy_for_each_option() -> void:
	var h: Control = await _board(true, {"grit": {"picks": [0]}})
	var def := Registry.talent("grit")
	_choose(h, "grit").pressed.emit()
	await _wait(0.4)
	var shell := WConfirm.current(h)
	assert_object(shell).is_not_null()
	assert_object(h.get("_sheet_root")).is_same(shell)
	var sheet: Control = shell.find_child("Sheet", true, false)
	assert_object(sheet).is_not_null()
	assert_str((sheet.find_child("Star", true, false) as WStarLine).text()).is_equal("RANK 2 OF %d" % def.max_rank())
	var said := _texts(sheet)
	assert_str(said).contains("GRIT")
	assert_str(said).contains("Rank 1 of %d owned" % def.max_rank())
	assert_str(said).contains(HS.form_line(def, 0))
	assert_str(said).contains(HS.form_line(def, 1))
	assert_str(said).contains("Reset Upgrades is the only way to choose again")
	for f in range(2):
		var b: WButton = sheet.find_child("Buy%d" % f, true, false)
		assert_str(b.role).is_equal(WButton.GREEN)
		assert_int(int(b.get_meta("price"))).is_equal(def.cost_of_rank(1))
		assert_str(b.label_text()).contains("· BUY")
		assert_object((sheet.find_child("Offer%d" % f, true, false) as Control).find_child("Frame", true, false)).is_not_null()
	# the purse in the card's corner (the header's wallet is under the dim)
	var purse: Control = shell.card.get_node_or_null("Purse")
	assert_object(purse).is_not_null()
	assert_str(_texts(purse)).contains(W.num(Save.gold()))
	var close: WButton = shell.find_child("Cancel", true, false)
	assert_str(close.label_text()).is_equal("CLOSE")
	assert_str(close.role).is_equal(WButton.SLATE)
	# the back gesture's path (WConfirm.dismiss) closes it and the board forgets it
	assert_bool(WConfirm.dismiss(h)).is_true()
	assert_object(h.get("_sheet_root")).is_null()
	assert_object(h.get("_choice")).is_null()


func test_buy_in_each_option_buys_as_the_wanted_sheet_does() -> void:
	var def := Registry.talent("grit")
	var c0 := def.cost_of_rank(0)
	var c1 := def.cost_of_rank(1)
	var start := c0 + c1 + 500
	# Royale: Buy0 then Buy1 in the pop-up
	var h: Control = await _board(true, {}, start)
	h.call("_open", def)
	await _wait(0.4)
	var shell := WConfirm.current(h)
	(shell.find_child("Buy0", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(Save.talent_picks("grit")).is_equal([0])
	assert_int(Save.gold()).is_equal(start - c0)
	assert_str((h.find_child("Amount", true, false) as WText).text).is_equal(W.num(start - c0))
	# the purse in the pop-up's corner follows too
	assert_str(_texts(shell.card.get_node("Purse"))).contains(W.num(start - c0))
	# the pop-up stays, with the rank after
	assert_object(WConfirm.current(h)).is_same(shell)
	assert_str((shell.find_child("Star", true, false) as WStarLine).text()).is_equal("RANK 2 OF %d" % def.max_rank())
	assert_str((_tile(h, "grit").find_child("Rank", true, false) as WText).text).is_equal("RANK 1 / %d" % def.max_rank())
	assert_object((h.get("_summary_flow") as Node).get_node_or_null("Chip_grit_0")).is_not_null()
	(shell.find_child("Buy1", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var royale_picks := Save.talent_picks("grit")
	var royale_gold := Save.gold()
	var royale_spent := Save.talent_spent()
	assert_array(royale_picks).is_equal([0, 1])
	assert_int(royale_gold).is_equal(start - c0 - c1)
	assert_array(_tile(h, "grit").find_child("RankBar", true, false).get_meta("picks")).is_equal([0, 1])
	assert_object((h.get("_summary_flow") as Node).get_node_or_null("Chip_grit_1")).is_not_null()
	shell.cancel()
	remove_child(h)
	await get_tree().process_frame
	Save.end_sandbox()
	# Wanted: the same two buys on the sepia sheet end in the same save
	var w: Control = await _board(false, {}, start)
	w.call("_open", def)
	await get_tree().process_frame
	(w.get("_sheet_root").find_child("Buy0", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	(w.get("_sheet_root").find_child("Buy1", true, false) as WButton).pressed.emit()
	await get_tree().process_frame
	assert_array(Save.talent_picks("grit")).is_equal(royale_picks)
	assert_int(Save.gold()).is_equal(royale_gold)
	assert_int(Save.talent_spent()).is_equal(royale_spent)
	w.call("_close", false)


func test_short_of_gold_every_price_wears_the_kit_s_short_state_and_buys_nothing() -> void:
	var h: Control = await _board(true, {}, 50)
	for def: TalentDef in Registry.talents_list():
		var b := _choose(h, def.id)
		var short := def.cost_of_rank(0) - 50
		assert_bool(b.locked).is_true()
		assert_int(int(b.get_meta("short"))).is_equal(short)
		assert_str(_texts(_tile(h, def.id).find_child("ChooseRow", true, false))).contains("%s short" % W.num(short))
	# a short CHOOSE still opens the choice (what the options are), whose BUYs are short and buy nothing
	var grit := Registry.talent("grit")
	_choose(h, "grit").pressed.emit()
	await _wait(0.4)
	var shell := WConfirm.current(h)
	assert_object(shell).is_not_null()
	var buy: WButton = shell.find_child("Buy0", true, false)
	assert_bool(buy.locked).is_true()
	assert_int(int(buy.get_meta("short"))).is_equal(grit.cost_of_rank(0) - 50)
	buy.pressed.emit()
	await get_tree().process_frame
	assert_array(Save.talent_picks("grit")).is_empty()
	assert_int(Save.gold()).is_equal(50)
	shell.cancel()


func test_a_maxed_talent_says_maxed_and_its_pop_up_sells_nothing() -> void:
	var def := Registry.talent("stride")
	var picks: Array = []
	for k in def.max_rank():
		picks.append(k % 2)
	var h: Control = await _board(true, {"stride": {"picks": picks}})
	var b := _choose(h, "stride")
	assert_str(b.label_text()).is_equal("MAXED")
	assert_bool(b.locked).is_true()
	b.pressed.emit()
	await _wait(0.4)
	var shell := WConfirm.current(h)
	assert_object(shell).is_not_null()
	assert_str((shell.find_child("Star", true, false) as WStarLine).text()).is_equal("MAXED")
	assert_object(shell.find_child("Buy0", true, false)).is_null()
	assert_object(shell.find_child("Buy1", true, false)).is_null()
	assert_str(_texts(shell)).contains("%d owned" % Save.talent_count("stride", 0))
	assert_array(shell.find_child("RankBar", true, false).get_meta("picks")).is_equal(picks)
	shell.cancel()


func test_reset_upgrades_asks_in_red_then_refunds_half_as_today() -> void:
	var h: Control = await _board(true, {"grit": {"picks": [0, 1]}}, 1000)
	var spent := Save.talent_spent()
	var back := Save.talent_refund()
	var reset: WButton = h.get("_reset")
	reset.pressed.emit()
	await _wait(0.4)
	var ask := WConfirm.current(h)
	assert_object(ask).is_not_null()
	assert_str(_texts(ask)).contains("RESET UPGRADES?")
	var yes: WButton = ask.find_child("Confirm", true, false)
	assert_str(yes.role).is_equal(WButton.RED)
	# keep them: nothing changes
	ask.cancel()
	await _wait(0.3)
	assert_array(Save.talent_picks("grit")).is_equal([0, 1])
	reset.pressed.emit()
	await _wait(0.4)
	WConfirm.current(h).confirm()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(Save.talent_picks("grit")).is_empty()
	assert_int(Save.talent_spent()).is_equal(0)
	assert_int(Save.gold()).is_equal(1000 + back)
	assert_int(back).is_equal(int(floor(spent * Save.REFUND_FRAC)))
	assert_bool((h.get("_reset") as WButton).locked).is_true()
	assert_str(_texts(h.find_child("Refund", true, false))).is_equal("Nothing to take back")
	assert_object((h.get("_summary_flow") as Node).get_node_or_null("Hint")).is_not_null()
	# with nothing spent the button asks nothing
	(h.get("_reset") as WButton).pressed.emit()
	await _wait(0.3)
	assert_object(WConfirm.current(h)).is_null()


func test_the_pips_show_the_option_each_rank_was_bought_in() -> void:
	var h: Control = await _board(true, {"grit": {"picks": [1, 0, 1]}})
	var def := Registry.talent("grit")
	var track: Control = _tile(h, "grit").find_child("RankBar", true, false)
	assert_array(track.get_meta("picks")).is_equal([1, 0, 1])
	assert_int(int(track.get("ranks"))).is_equal(def.max_rank())
	assert_object((track.get("icons") as Array)[0]).is_equal(def.form_icon(0))
	assert_object((track.get("icons") as Array)[1]).is_equal(def.form_icon(1))
	var n := def.max_rank()
	assert_vector(track.custom_minimum_size).is_equal(Vector2(n * HS.R_PIP.x + (n - 1) * HS.R_PIP_GAP, HS.R_PIP.y))


# ---------------------------------------------------------------- Wanted, and the tools

func test_wanted_builds_the_board_as_before() -> void:
	var h: Control = await _board(false, {"grit": {"picks": [0]}})
	assert_bool(h.get("_royale_built")).is_false()
	assert_object(h.find_child("Summary", true, false)).is_not_null()
	assert_object(h.get("_refund")).is_not_null()
	assert_object(h.find_child("HoldRow", true, false)).is_null()
	assert_object(h.get("tab_bar_node")).is_null()
	assert_float(h.call("board_top")).is_equal(190.0)
	assert_float(h.call("board_bottom")).is_equal(112.0)
	assert_float(h.call("board_side")).is_equal(48.0)
	assert_str((h.get("title_label") as WText).text).is_equal("Upgrade")
	var tile := _tile(h, "grit")
	assert_bool(tile is WTap).is_true()
	h.call("_open", Registry.talent("grit"))
	await get_tree().process_frame
	assert_bool(h.get("_sheet_root") is WConfirm).is_false()
	assert_object((h.get("_sheet_root") as Node).find_child("Buy0", true, false)).is_not_null()
	h.call("_close", false)


func test_the_capture_and_audit_tools_carry_the_upgrade_states() -> void:
	var shots := FileAccess.get_file_as_string("res://tools/wanted_shots.gd")
	for s in ["func _mirror_more()", "\"mirror_more\"", "03d-mirror-many-held", "03e-mirror-choose-short",
			"03f-mirror-choose-maxed", "03g-mirror-reset-confirm", "03h-mirror-empty"]:
		assert_str(shots).contains(s)
	var audit := FileAccess.get_file_as_string("res://tools/touch_audit.gd")
	for s in ["func _upgrade_buy()", "_want(\"upgrade_buy\")"]:
		assert_str(audit).contains(s)
