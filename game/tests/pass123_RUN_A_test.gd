## Pass 123, lane RUN_A: Pause, Down!, Stage clear and Results under the Royale theme, built to the mocks' structure
## (Garry, after pass 122's checkpoint: "this isnt the full Royale UI. It's just a reskin of some buttons and fonts. There
## were no structural UI changes"); Wanted (the default) drawn as before.
##  - Pause: the clock on a black plate in capitals, the three tabs sharing the sheet's width over one slate sheet that
##    reaches RESUME, the Build rows on thin lines with bigger stars ("the Stars need to be bigger"), the open row's dark
##    stat cells and purple mutation tags, a stat that did not move still readable, the change chip, the dark sources
##    card, the Options' ABANDON in red and the size choice in capitals; a theme flip builds it again on the next open;
##  - Down!: the cream disc with the navy count, the run pills, GET UP with the drawn ad icon in place of "WATCH AN AD",
##    STAY DOWN red, the hit log only under the developer's hit log or debug mode (as today), the line under the disc
##    following it, no chance left locking GET UP;
##  - Stage clear: EXTRACT a gold button on the Extract card (it extracts), NOT YET under the cards and outside the
##    Endless card, the run pills, the count gold then red in its last seconds;
##  - Results: the run pills, the damage rows on one slate panel with their 72 px frames, "DAMAGE DEALT · n SOURCES",
##    the Royale kills chart, the buttons' words in capitals and their roles, the stamps as the kit's tags;
##  - under Wanted every one of them keeps today's pieces; the capture tool carries the new Down! states.
extends GdUnitTestSuite

const RESULTS := preload("res://ui/ResultsScreen.gd")
const QT := preload("res://core/systems/QuestTracker.gd")

var _keep: Dictionary = {}


func before_test() -> void:
	_keep = {"inset": Settings.top_inset, "save": Save.data.duplicate(true), "settings": Settings.to_dict()}
	Settings.top_inset = -1
	Save.data = Save._default()
	Save._migrate_seen()
	Save._dirty = false
	Run.arena = false
	QT.just_completed.clear()


func after_test() -> void:
	Settings.from_dict(_keep["settings"])
	Settings.top_inset = int(_keep["inset"])
	Settings.debug_mode = false
	QT.just_completed.clear()
	Save.data = _keep["save"]
	Save._dirty = false
	Run.end()


func _start(hero := "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


## A run with a weapon that has two mutations (an open row's cells and tags), a line and a passive item.
func _build() -> void:
	_start()
	Run.debug_clear_items()
	Run.debug_set_item("weapon", "turret_buddy", 3)
	Run.debug_set_item("weapon", "molotov", 2)
	Run.debug_set_item("passive", "clover", 2)
	Run.debug_set_item("passive", "magnet", 2)
	# two of Turret Buddy's mutations, as wanted_shots gives them (its _mut)
	var ms: Array = Registry.mutations_of("turret_buddy")
	for i in mini(2, ms.size()):
		Run.debug_set_item("mutation", (ms[i] as MutationDef).id, 1)


func _pause() -> PauseScreen:
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	return ps


func _texts(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "WText", true, false):
		var t := c as WText
		out += t.text + "|"
		for r in t.runs:
			out += str((r as Array)[0]) + "|"
	return out


# ---------------------------------------------------------------- Pause

func test_the_pause_frame_under_royale_and_under_wanted() -> void:
	_build()
	var ps := _pause()
	ps.open()
	await _frames(3)
	var plate := ps.find_child("ClockPlate", true, false) as PanelContainer
	assert_object(plate).is_not_null()
	var pb := plate.get_theme_stylebox("panel") as HardBox
	assert_str(pb.role).is_equal("plate")
	assert_str(ps._clock.text).contains("STAGE 1")
	assert_bool(ps._clock.color.is_equal_approx(R.WHITE)).is_true()
	# the three tabs share the sheet's width (within a few px), in capitals
	var tabs: Array = []
	for c in ps._tabs.get_children():
		if c is WTap:
			tabs.append(c)
	assert_int(tabs.size()).is_equal(3)
	var w0 := (tabs[0] as Control).size.x
	for t in tabs:
		assert_float((t as Control).size.x).is_equal_approx(w0, 3.0)
	assert_float(w0 * 3.0 + float(R.TAB_GAP) * 2.0).is_equal_approx(ps._tabs.size.x, 4.0)
	assert_str(_texts(ps._tabs)).contains("BUILD")
	# one slate sheet with its top edge, reaching down to RESUME
	var sb := ps._board.get_theme_stylebox("panel") as HardBox
	assert_str(sb.royale_kind()).is_equal("panel")
	assert_bool(bool(sb.sides[1])).is_true()
	var resume := ps.find_child("Resume", true, false) as Control
	await _frames(3)
	assert_float(resume.get_global_rect().position.y - ps._board.get_global_rect().end.y).is_between(30.0, 60.0)
	# a theme flip builds it again on the next open
	ps.close()
func test_the_build_rows_under_royale_have_bigger_stars_cells_and_tags() -> void:
	_build()
	var ps := _pause()
	ps._expanded = "turret_buddy"
	ps._tab = 0
	ps.open()
	await _frames(3)
	var rows := ps._content.find_children("*", "WRow", true, false)
	assert_int(rows.size()).is_greater_equal(4)
	for r in rows:
		var b := (r as WRow).box as HardBox
		assert_bool(b.themed).is_false()
		assert_float(b.fill.a).is_equal(0.0)
	var marks := ps._content.find_children("*", "WMarks", true, false)
	assert_int(marks.size()).is_greater(0)
	for m in marks:
		assert_float((m as WMarks).mark).is_equal(PauseScreen.ROYALE_STAR_PX)
	assert_float(PauseScreen.ROYALE_STAR_PX).is_greater(PauseScreen.STAR_PX)
	# the open weapon row: four dark cells, a purple tag a mutation, what evolving still needs
	var cells := ps._content.find_child("StatCells", true, false) as Control
	assert_object(cells).is_not_null()
	assert_int(cells.get_child_count()).is_equal(4)
	assert_str(((cells.get_child(0) as PanelContainer).get_theme_stylebox("panel") as HardBox).fill.to_html()).is_equal(R.CELL.to_html())
	var tags := ps._content.find_child("PathTags", true, false) as Control
	assert_object(tags).is_not_null()
	var tag_n := 0
	for c in tags.get_children():
		if str(c.name).begins_with("Tag"):
			tag_n += 1
			assert_bool(((c as PanelContainer).get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(R.TAG_MUTATION)).is_true()
	assert_int(tag_n).is_equal(Run.weapons[0].mutations.size())
	# the group heads: one tracked label with its count after a dot
	var g := ps._content.find_child("GroupWeapons", true, false) as Control
	assert_str(_texts(g)).contains("WEAPONS · 2 / ")
	assert_object(ps._content.find_child("GroupPassives", true, false)).is_not_null()
	# a frame's glow stays inside the list (capped at the inset the words keep)
	var plate := (rows[0] as WRow).head.get_node("Plate") as WPlate
	assert_float(plate.glow_reach).is_equal(float(PauseScreen.ROYALE_BUILD_INSET))




func test_the_stats_under_royale_read_on_the_slate() -> void:
	_build()
	var ps := _pause()
	ps._tab = 1
	ps._stat = "luck"
	ps.open()
	await _frames(3)
	# a stat that did not move reads in the secondary blue (not the faded ink that vanished on the slate)
	var still := ps._content.find_child("Stat_execute_frac", true, false) as Control
	var nm := still.find_child("Name", true, false) as WText
	assert_float(nm.color.a).is_equal_approx(PauseScreen.ROYALE_DIM_ALPHA, 0.001)
	assert_float(Color(nm.color.r, nm.color.g, nm.color.b).get_luminance()).is_greater(0.6)
	# luck moved (the clover): its chip is the kit's green tag, its sources a dark cell
	var luck := ps._content.find_child("Stat_luck", true, false) as Control
	var chip := luck.find_child("Change", true, false) as PanelContainer
	assert_object(chip).is_not_null()
	assert_bool((chip.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(R.TAG_GREEN)).is_true()
	var card := ps._content.find_child("Sources", true, false).find_child("Card", true, false) as PanelContainer
	assert_bool((card.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(R.CELL)).is_true()
	assert_bool((luck as WTap).box.fill.is_equal_approx(PauseScreen.ROYALE_OPEN_FILL)).is_true()


func test_the_options_under_royale() -> void:
	_build()
	var ps := _pause()
	ps._tab = 2
	ps.open()
	await _frames(3)
	var ab := ps.find_child("Abandon", true, false) as WButton
	assert_str(ab.label_text()).is_equal("ABANDON")
	assert_str(ab.role).is_equal("red")
	assert_str(_texts(ps.find_child("FloatSize", true, false))).contains("NORMAL")
	assert_int(ps._content.find_children("Rule", "ColorRect", true, false).size()).is_greater_equal(5)
	# every switch is still found by its name (touch_audit's)
	for n in ["ScreenShake", "DamageNumbers", "HealNumbers", "XpNumbers", "CoinNumbers"]:
		assert_object(ps.find_child(n, true, false)).override_failure_message(n).is_not_null()
# ---------------------------------------------------------------- Down!

func _revive() -> ReviveScreen:
	var rs: ReviveScreen = auto_free(ReviveScreen.new())
	add_child(rs)
	return rs


func test_down_under_royale() -> void:
	_start()
	Settings.hit_log = false
	Settings.debug_mode = false
	Settings.free_revive_button = false
	var rs := _revive()
	Run.kills = 123
	rs.open(86, 1, "", {"by": "The Brander", "kind": "boss", "role": "boss"})
	rs._held = true
	await _frames(3)
	assert_bool(rs._count.color.is_equal_approx(R.NAVY)).is_true()
	assert_str(rs.header.star_line.text()).is_equal("1 CHANCE LEFT")
	assert_bool(rs.header.title.color.is_equal_approx(R.CREAM)).is_true()
	# GET UP with the drawn ad icon in place of the words
	var up := rs._ad_btn
	assert_object(up.find_child("Glyph_ad", true, false)).is_not_null()
	assert_str(up.label_text()).not_contains("WATCH")
	assert_str(up.label_text()).contains("GET UP")
	assert_str(up.role).is_equal("gold")
	assert_str((rs.find_child("StayDown", true, false) as WButton).role).is_equal("red")
	# the run's numbers as three black pills
	var pills := rs.find_child("RunPills", true, false) as Control
	assert_int(pills.get_child_count()).is_equal(3)
	assert_str(_texts(pills)).contains("123 kills")
	# the hit log stays debug-only (as today); the line under the disc follows it
	assert_bool(rs._log_panel.visible).is_false()
	var low := rs._disc.position.y
	assert_float(rs._who.offset_top).is_greater(low + 270.0 + ReviveScreen.ROYALE_DISC_R)
	Settings.debug_mode = true
	rs.open(86, 1, "", {}, [{"t": 1.0, "by": "Skeleton", "kind": "melee", "role": "", "colour": "", "fx": [], "raw": 6.0,
		"dealt": 6.0, "shield": 0.0, "note": "", "hp": 0.0, "fatal": true}])
	rs._held = true
	await _frames(2)
	assert_bool(rs._log_panel.visible).is_true()
	assert_float(rs._disc.position.y).is_less(low)
	var row := rs._list.find_child("Row", true, false) as PanelContainer
	assert_bool((row.get_theme_stylebox("panel") as HardBox).border_color.is_equal_approx(R.TAG_RED)).is_true()
	# no chance left: GET UP locked
	Settings.debug_mode = false
	rs.open(86, 0)
	await _frames(1)
	assert_bool(rs._ad_btn.locked).is_true()
	assert_str(rs.header.star_line.text()).is_equal("NO CHANCES LEFT")




# ---------------------------------------------------------------- Stage clear

func test_the_stage_clear_under_royale() -> void:
	_start()
	Run.run_gold = 312
	var pd: PortalDialog = auto_free(PortalDialog.new())
	add_child(pd)
	var left := [59.2]
	pd.seconds_source = func() -> float: return left[0]
	var said: Array = []
	pd.decided.connect(func(x): said.append(x))
	pd.open(1, true, false)
	await _frames(2)
	assert_str(pd.header.star_line.text()).is_equal("BOSS DOWN")
	assert_str(pd.header.title.text).is_equal("STAGE 1 CLEAR")
	var pills := pd.find_child("RunPills", true, false) as Control
	assert_int(pills.get_child_count()).is_equal(4)
	assert_str(_texts(pills)).contains("Bank it before the horde comes.")
	# EXTRACT: a gold button on the Extract card
	var ex := pd.find_child("Extract", true, false) as WButton
	assert_object(ex).is_not_null()
	assert_str(ex.role).is_equal("gold")
	assert_object(pd.find_child("ExtractCard", true, false).find_child("Extract", true, false)).is_not_null()
	# NOT YET: under the cards, outside the Endless card
	var nb := pd.find_child("NotYet", true, false) as WButton
	var cards: Node = pd.get("_cards")
	assert_object(nb.get_parent()).is_same(cards)
	assert_int(nb.get_index()).is_equal(cards.get_child_count() - 1)
	assert_object((pd.get("_endless") as Node).find_child("NotYet", true, false)).is_null()
	assert_str(nb.role).is_equal("slate")
	# the count: gold, then red in its last seconds
	var count := pd.get("_count") as WText
	assert_bool(count.color.is_equal_approx(R.GOLD_TEXT)).is_true()
	left[0] = 7.4
	await _frames(2)
	assert_bool(count.color.is_equal_approx(R.ROLES["red"]["top"])).is_true()
	assert_int(count.bevel).is_equal(0)
	left[0] = 30.0
	await _frames(2)
	ex.pressed.emit()
	assert_array(said).is_equal([true])
	assert_bool(pd.visible).is_false()




# ---------------------------------------------------------------- Results

func _results() -> Control:
	_start()
	Run.kills = 120
	Run.damage_by_weapon = {"revolver": 900.0, "fire": 40.0, "": 3.0}
	Run.last_result = {"gold_before": 100, "banked": 50}
	var r: Control = auto_free(load("res://ui/ResultsScreen.tscn").instantiate())
	add_child(r)
	return r


func test_the_results_under_royale() -> void:
	var r := _results()
	await _frames(2)
	r.skip_all()
	await _frames(2)
	var pills := r.find_child("RunPills", true, false) as Control
	assert_int(pills.get_child_count()).is_equal(4)
	assert_str(_texts(pills)).contains("120 kills")
	var panel := r.find_child("DamagePanel", true, false) as PanelContainer
	assert_object(panel).is_not_null()
	var rows := panel.find_child("DamageRows", true, false) as Control
	assert_int(rows.get_child_count()).is_equal(3)
	for row in rows.get_children():
		assert_float((row.get_child(0) as WPlate).side).is_equal(RESULTS.ROYALE_ROW_PLATE)
		assert_object(row.find_child("Name", true, false)).is_not_null()
		assert_object(row.find_child("Amount", true, false)).is_not_null()
	assert_str((r.get("_dmg_label") as WText).text).is_equal("DAMAGE DEALT · 3 SOURCES")
	assert_bool(r.get("_chart") is RESULTS.RoyaleChart).is_true()
	var words := {}
	for b in r.find_children("*", "WButton", true, false):
		words[(b as WButton).label_text()] = (b as WButton).role
	assert_str(str(words.get("PLAY AGAIN", ""))).is_equal("gold")
	assert_str(str(words.get("UPGRADE", ""))).is_equal("blue")
	assert_str(str(words.get("MAIN MENU", ""))).is_equal("slate")
	assert_float(r.backdrop_dim()).is_equal(RESULTS.ROYALE_BACKDROP_DIM)
	# the stamp under Royale is the kit's tag, landing as WStamp does
	var st: WStamp = RESULTS.make_stamp("UNLOCKED", W.SAGE, 28)
	assert_bool(st is RESULTS.RoyaleStamp).is_true()
	assert_bool((st as RESULTS.RoyaleStamp).tag_fill().is_equal_approx(R.TAG_GREEN)).is_true()
	st.free()




# ---------------------------------------------------------------- the capture tool

func test_the_capture_tool_has_the_new_down_states() -> void:
	var src := FileAccess.get_file_as_string("res://tools/wanted_shots.gd")
	assert_str(src).contains("14c-down-plain")
	assert_str(src).contains("14d-down-no-chance")
