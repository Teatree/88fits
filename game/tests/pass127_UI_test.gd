extends GdUnitTestSuite

## Pass 127 (Garry's UI list):
##  - "Hero on the Main Menu still hovers above the drop shadow ... its idle animation is always squeezing him heightwise": his soles
##    end on the shadow's line in every idle frame (core/systems/FigureSoles.gd, art/ui/figure_soles.json);
##  - "at the moment of selecting a different hero, we reset the upper scroll section to be all the way to the top";
##  - "its borders touching the back button too closely. The separation between Heroes select area and this scrollable area isn't
##    very clear": the sheet stands clear of the header, a gap of the vista between it and the picker's own tray;
##  - "The Heroes select area has the same exact tint of buttons as the very bottom buttons": the closed tabs have their own tint;
##  - "Change the 'Looks' text to 'Skins'. Do this anywhere else where the Skins are mentioned."

const SCREEN := "res://ui/HeroesScreen.tscn"
const Heroes := preload("res://ui/HeroesScreen.gd")
const Title := preload("res://ui/TitleScreen.gd")
const Bar := preload("res://ui/wanted/WTabBar.gd")


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func _screen() -> Control:
	var s: Control = auto_free(load(SCREEN).instantiate())
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return s


# ---------------------------------------------------------------- the hero's feet

func test_the_table_has_every_heros_played_look_and_it_is_up_to_date() -> void:
	for c: CharacterDef in Registry.sorted_characters():
		if c.hidden:
			continue
		var look: CharacterDef = Registry.played_look(c)
		if look == null or look.sprite == null:
			continue
		var rows: Dictionary = FigureSoles.of(look.sprite)
		assert_bool(rows.is_empty()).override_failure_message("%s: no soles for %s (python tools/figure_soles.py)" % [c.id, look.sprite.resource_path]).is_false()


func test_every_idle_frame_is_drawn_with_its_soles_on_the_line() -> void:
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	var fig: Control = t.get("_figure")
	assert_object(fig).is_not_null()
	fig.call("play", ["idle_f", "idle_fd", "idle"])
	var soles: Array = fig.get("_soles")
	assert_int(soles.size()).is_greater(1)
	var seen := {}
	for f in soles.size():
		fig.set("frame", f)
		var v := float(fig.call("sole_v"))
		seen[v] = true
		# where this frame's paint ends, once drawn, in the figure's own px
		var ends: float = v * fig.size.y + float(fig.call("sole_shift"))
		assert_float(ends).is_equal_approx(float(fig.call("soles").y), 0.01)
	# the frames really differ: the shift is doing something
	assert_int(seen.size()).is_greater(1)


func test_a_run_has_no_row_and_keeps_the_figures_line() -> void:
	var t: Control = auto_free(load("res://ui/TitleScreen.tscn").instantiate())
	add_child(t)
	await get_tree().process_frame
	await get_tree().process_frame
	var fig: Control = t.get("_figure")
	fig.call("play", ["run_fd", "run_f", "run"])
	assert_float(float(fig.call("sole_shift"))).is_equal(0.0)


# ---------------------------------------------------------------- the Heroes screen

func test_a_different_hero_sets_the_page_to_its_top_at_once() -> void:
	var s := await _screen()
	var page: ScrollContainer = s.get("scroll")
	page.scroll_vertical = 200
	await get_tree().process_frame
	assert_int(page.scroll_vertical).is_greater(0)
	var other: CharacterDef = Registry.character("astro")
	assert_object(other).is_not_null()
	assert_bool(s.get("shown") != other).is_true()
	s.call("show_hero", other)
	# at once: no tween that would read as a scroll
	assert_int(page.scroll_vertical).is_equal(0)
	assert_object(s.get("shown")).is_equal(other)


func test_his_own_tile_changes_nothing() -> void:
	var s := await _screen()
	var page: ScrollContainer = s.get("scroll")
	page.scroll_vertical = 150
	await get_tree().process_frame
	var at := page.scroll_vertical
	var before: Node = s.get("content").get_child(0)
	s.call("show_hero", s.get("shown"))
	assert_int(page.scroll_vertical).is_equal(at)
	assert_object(s.get("content").get_child(0)).is_equal(before)


func test_the_sheet_stands_clear_of_the_back_button_and_of_the_tray() -> void:
	var s := await _screen()
	var sheet: Control = s.get("board_sheet_node")
	var back := s.find_child("Back", true, false) as Control
	if back != null:
		assert_float(sheet.get_global_rect().position.y).is_greater_equal(back.get_global_rect().end.y + 16.0)
	var tray := (s.get("picker") as Control).get_node("Panel") as Control
	var gap: float = tray.get_global_rect().position.y - sheet.get_global_rect().end.y
	assert_float(gap).is_equal_approx(Heroes.PICK_GAP, 1.0)
	# the tray is as wide as the sheet
	assert_float(tray.get_global_rect().size.x).is_equal_approx(sheet.get_global_rect().size.x, 1.0)


func test_a_tile_and_a_closed_tab_do_not_share_a_tint() -> void:
	var dock: Dictionary = R.role(R.DOCK_ROLE)
	var slate: Dictionary = R.role("slate")
	assert_bool((dock["top"] as Color).is_equal_approx(slate["top"])).is_false()
	assert_bool((dock["bottom"] as Color).is_equal_approx(slate["bottom"])).is_false()
	var bar: Control = auto_free(Bar.make("heroes"))
	add_child(bar)
	await get_tree().process_frame
	var tab := bar.find_child("Tab_battle", true, false) as WTap
	assert_str(str((tab.box as HardBox).role)).is_equal(R.DOCK_ROLE)
	var on := bar.find_child("Tab_heroes", true, false) as WTap
	assert_str(str((on.box as HardBox).role)).is_equal(WButton.GOLD)


# ---------------------------------------------------------------- Looks -> Skins

func _all_words(n: Node, out: Array) -> void:
	if n is WText:
		out.append(str((n as WText).text))
	elif n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_all_words(c, out)


func test_the_screens_say_skins_never_looks() -> void:
	var s := await _screen()
	var words: Array = []
	_all_words(s, words)
	assert_bool(" ".join(words).to_upper().contains("LOOKS")).is_false()
	s.call("open_looks")
	await get_tree().process_frame
	words.clear()
	_all_words(s, words)
	assert_bool(" ".join(words).to_upper().contains("LOOKS")).is_false()
	var src := FileAccess.get_file_as_string("res://ui/HeroesScreen.gd")
	# pass 137 (lane W2-HUB): the words are rows of the string table
	assert_bool(src.contains("WButton.make([Loc.t(\"ui.heroes.skins\")]")).is_true()
	assert_str(Loc.t("ui.heroes.skins")).is_equal("SKINS")
	assert_bool(src.contains("make_star(Loc.t(\"ui.heroes.skins_star\"))")).is_true()
	assert_str(Loc.t("ui.heroes.skins_star")).is_equal("Skins")


func test_no_player_facing_string_in_the_skin_flows_says_look() -> void:
	for path: String in ["res://ui/HeroesScreen.gd", "res://ui/wanted/WHeroSheet.gd", "res://ui/DevMenu.gd", "res://game/Game.gd"]:
		for line: String in FileAccess.get_file_as_string(path).split("
"):
			if line.strip_edges().begins_with("#"):
				continue
			for bad: String in ["\"Looks ·", "\"LOOKS", "this look?", "NEW LOOK", "a look's goal", "Tap a look"]:
				assert_bool(line.contains(bad)).override_failure_message("%s still says %s" % [path, bad]).is_false()
