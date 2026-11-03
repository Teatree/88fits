## Pass 122, lane UIKIT_A: the Royale kit's foundation (Garry's build brief of 2026-11-02 on Claude Design's "Royale,
## refined": a SECOND THEME behind a switch, Wanted the default and pixel-identical while the switch is off).
##  - Settings.ui_theme ("wanted" | "royale") round-trips with the other settings and is held at wanted in prod;
##  - W.royale() follows it (through Settings.changed, or theme_changed() after a direct assignment);
##  - the fonts load (Ultra and Rubik are real faces, not the fallback), the Ultra minimum rule (nothing under 28 px),
##    W's faces follow the theme, normal_height knows the two faces;
##  - WButton roles and their colours (R.ROLES), a count pill, set_role; HardBox's kinds; the dims;
##  - every component the lane touched builds and draws under both themes; no W colour constant moves.
extends GdUnitTestSuite

const SETTINGS_SCENE := "res://ui/SettingsScreen.tscn"
const DEV_SCENE := "res://ui/DevMenu.tscn"

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)
	W.theme_changed()


func after_test() -> void:
	Settings.force_prod(false)
	Settings.ui_theme = "wanted"
	Settings.debug_mode = bool(_settings_before.get("debug_mode", false))
	W.theme_changed()


func _royale(on: bool) -> void:
	Settings.ui_theme = "royale" if on else "wanted"
	W.theme_changed()


func _base_path(f: Font) -> String:
	var b := f
	while b is FontVariation and (b as FontVariation).base_font:
		b = (b as FontVariation).base_font
	return b.resource_path if b else ""


func _weight(f: Font) -> int:
	if f is FontVariation:
		var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
		return int((f as FontVariation).variation_opentype.get(tag, 0))
	return 0


# ---------------------------------------------------------------- the switch

func test_the_setting_round_trips_and_defaults_to_wanted() -> void:
	var script: GDScript = load("res://core/autoload/Settings.gd")
	var s: Node = auto_free(script.new())
	assert_str(s.ui_theme).is_equal("wanted")
	assert_str(script.UI_THEME_DEFAULT).is_equal("wanted")
	assert_array(script.UI_THEMES).contains_exactly(["wanted", "royale"])
	assert_str(str(script.PROD_LOCKED["ui_theme"])).is_equal("wanted")
	assert_bool(s.to_dict().has("ui_theme")).is_true()
	assert_str(str(s.to_dict()["ui_theme"])).is_equal("wanted")
	s.from_dict({})
	assert_str(s.ui_theme).is_equal("wanted")
	s.from_dict({"ui_theme": "royale"})
	assert_str(s.ui_theme).is_equal("royale")
	assert_str(str(s.to_dict()["ui_theme"])).is_equal("royale")
	var back: Node = auto_free(script.new())
	back.from_dict(s.to_dict())
	assert_str(back.ui_theme).is_equal("royale")
	s.from_dict({"ui_theme": "fancy"})
	assert_str(s.ui_theme).is_equal("wanted")
	s.ui_theme = "royale"
	s.from_dict({"music_volume": 0.3})
	assert_str(s.ui_theme).is_equal("royale")


func test_the_setting_reaches_the_save_file() -> void:
	# an earlier suite's arena may have left the save sandboxed (save_now writes nothing then)
	if Save.sandboxed():
		Save.end_sandbox()
	Settings.set_value("ui_theme", "royale")
	assert_bool(Save.save_now()).is_true()
	var data = JSON.parse_string(FileAccess.get_file_as_string(Save.path()))
	assert_str(str(data["settings"]["ui_theme"])).is_equal("royale")
	Settings.set_value("ui_theme", "wanted")
	assert_bool(Save.save_now()).is_true()
	data = JSON.parse_string(FileAccess.get_file_as_string(Save.path()))
	assert_str(str(data["settings"]["ui_theme"])).is_equal("wanted")


func test_prod_holds_the_theme_at_wanted() -> void:
	Settings.ui_theme = "royale"
	Settings.force_prod(true)
	assert_str(Settings.ui_theme).is_equal("wanted")
	Settings.set_value("ui_theme", "royale")
	assert_str(Settings.ui_theme).is_equal("wanted")
	Settings.from_dict({"ui_theme": "royale"})
	assert_str(Settings.ui_theme).is_equal("wanted")
	W.theme_changed()
	assert_bool(W.royale()).is_false()
	Settings.force_prod(false)
	Settings.set_value("ui_theme", "royale")
	assert_str(Settings.ui_theme).is_equal("royale")


func test_w_royale_follows_the_switch() -> void:
	_royale(false)
	assert_bool(W.royale()).is_false()
	assert_str(W.theme_name()).is_equal("wanted")
	_royale(true)
	assert_bool(W.royale()).is_true()
	assert_str(W.theme_name()).is_equal("royale")
	# set_value emits Settings.changed, which the cache follows in the same frame
	Settings.set_value("ui_theme", "wanted")
	assert_bool(W.royale()).is_false()
	Settings.set_value("ui_theme", "royale")
	assert_bool(W.royale()).is_true()
	# a direct assignment is read fresh the next frame
	Settings.ui_theme = "wanted"
	await get_tree().process_frame
	assert_bool(W.royale()).is_false()


func test_the_settings_screen_offers_the_choice_in_debug_mode_only() -> void:
	Settings.debug_mode = true
	_royale(false)
	var dev: Control = auto_free(load(SETTINGS_SCENE).instantiate())
	add_child(dev)
	await get_tree().process_frame
	var choice = dev.find_child("UiTheme", true, false)
	assert_object(choice).is_not_null()
	assert_int(choice.index).is_equal(0)
	# beside the Painted / Live choice, in the same panel
	assert_object(dev.find_child("MenuStyle", true, false)).is_not_null()
	dev.visible = false
	_royale(true)
	var roy: Control = auto_free(load(SETTINGS_SCENE).instantiate())
	add_child(roy)
	await get_tree().process_frame
	assert_int(roy.find_child("UiTheme", true, false).index).is_equal(1)
	roy.visible = false
	# the production build: no choice, and the theme is wanted whatever a save said
	Settings.force_prod(true)
	Settings.debug_mode = true
	Settings.ui_theme = "royale"
	W.theme_changed()
	var prod: Control = auto_free(load(SETTINGS_SCENE).instantiate())
	add_child(prod)
	await get_tree().process_frame
	assert_object(prod.find_child("UiTheme", true, false)).is_null()
	assert_bool(W.royale()).is_false()
	prod.visible = false


func test_the_developer_menu_has_the_row() -> void:
	_royale(false)
	var menu: Node = auto_free(load(DEV_SCENE).instantiate())
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Node = menu.find_child("UiThemeRow", true, false)
	assert_object(row).is_not_null()
	var val: Node = row.find_child("Value", true, false)
	assert_str(str(val.get("text"))).is_equal("WANTED")


func test_the_capture_tools_take_a_theme_argument() -> void:
	for p in ["res://tools/wanted_shots.gd", "res://tools/touch_audit.gd", "res://tools/uidoc_shots.gd", "res://tools/store_shots.gd"]:
		var src := FileAccess.get_file_as_string(p)
		assert_bool(src.contains("theme=")).override_failure_message(p).is_true()
		assert_bool(src.contains("ui_theme")).override_failure_message(p).is_true()


# ---------------------------------------------------------------- the type

func test_the_fonts_load() -> void:
	var d := R.display()
	assert_object(d).is_not_null()
	assert_bool(d == ThemeDB.fallback_font).is_false()
	assert_str(d.resource_path).is_equal(R.DISPLAY_PATH)
	var b := R.body(500)
	assert_bool(b is FontVariation).is_true()
	assert_str(_base_path(b)).is_equal(R.BODY_PATH)
	assert_bool((b as FontVariation).base_font == ThemeDB.fallback_font).is_false()
	assert_int(_weight(b)).is_equal(500)
	assert_int(_weight(R.body(700))).is_equal(700)
	assert_str(_base_path(R.body(500, true))).is_equal(R.BODY_ITALIC_PATH)
	# the faces are real: a glyph the fallback would draw differently has a width of its own
	assert_float(d.get_string_size("START", HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x).is_greater(100.0)
	assert_bool(R.is_display(d)).is_true()
	assert_bool(R.is_display(R.display(3))).is_true()
	assert_bool(R.is_display(b)).is_false()
	assert_bool(R.is_display(W.slab())).is_false()


func test_normal_height_knows_the_two_faces() -> void:
	assert_bool(W.METRICS.has("Ultra")).is_true()
	assert_bool(W.METRICS.has("Rubik")).is_true()
	# Ultra: 2066 / 561 over 2048; Rubik: 935 / 250 over 1000 (fontTools), each side rounded to the pixel at 100 px
	assert_float(W.normal_height(R.display(), 100)).is_equal(128.0)
	assert_float(W.normal_height(R.body(500), 100)).is_equal(119.0)
	assert_float(W.normal_height(R.body(500, true), 100)).is_equal(119.0)
	# the old faces as before
	_royale(false)
	assert_float(W.normal_height(W.slab(), 100)).is_equal(137.0)
	assert_float(W.normal_height(W.serif(), 100)).is_equal(121.0)


func test_w_faces_follow_the_theme() -> void:
	_royale(false)
	assert_str(_base_path(W.slab())).is_equal(W.SLAB_PATH)
	assert_str(_base_path(W.slab(2))).is_equal(W.SLAB_PATH)
	assert_str(_base_path(W.serif())).is_equal(W.SERIF_PATH)
	assert_str(_base_path(W.serif(400, true))).is_equal(W.SERIF_ITALIC_PATH)
	assert_int(_weight(W.serif(600))).is_equal(600)
	assert_str(_base_path(W.slab_for(20))).is_equal(W.SLAB_PATH)
	var lw: WText = auto_free(W.label("Camera", 22))
	assert_str(_base_path(lw.font)).is_equal(W.SERIF_PATH)
	assert_bool(lw.color.is_equal_approx(W.INK_SOFT)).is_true()
	_royale(true)
	assert_str(_base_path(W.slab())).is_equal(R.DISPLAY_PATH)
	assert_str(_base_path(W.slab(2))).is_equal(R.DISPLAY_PATH)
	assert_int((W.slab(2) as FontVariation).spacing_glyph).is_equal(2)
	assert_str(_base_path(W.serif())).is_equal(R.BODY_PATH)
	assert_int(_weight(W.serif(400))).is_equal(500)
	assert_int(_weight(W.serif(600))).is_equal(700)
	assert_int(_weight(W.serif(W.BOLD_WEIGHT))).is_equal(800)
	assert_str(_base_path(W.serif(400, true))).is_equal(R.BODY_ITALIC_PATH)
	var lr: WText = auto_free(W.label("Camera", 22))
	assert_str(_base_path(lr.font)).is_equal(R.BODY_PATH)
	assert_int(_weight(lr.font)).is_equal(700)
	assert_bool(lr.color.is_equal_approx(R.SECONDARY)).is_true()
	assert_str(lr.text).is_equal("CAMERA")
	assert_int((lr.font as FontVariation).spacing_glyph).is_equal(W.em(22, R.LABEL_TRACK))


func test_the_ultra_minimum_rule() -> void:
	_royale(true)
	assert_bool(R.is_display(W.slab_for(R.ULTRA_MIN - 1))).is_false()
	assert_str(_base_path(W.slab_for(R.ULTRA_MIN - 1))).is_equal(R.BODY_PATH)
	assert_int(_weight(W.slab_for(R.ULTRA_MIN - 1))).is_equal(700)
	assert_bool(R.is_display(W.slab_for(R.ULTRA_MIN))).is_true()
	assert_int((W.slab_for(20, 3) as FontVariation).spacing_glyph).is_equal(3)
	# the text helpers apply it, and the edge goes only with Ultra
	var small: WText = auto_free(W.slab_text("Lv 3", 24))
	assert_bool(R.is_display(small.font)).is_false()
	assert_int(small.stroke).is_equal(0)
	assert_int(small.shadow).is_equal(0)
	var big: WText = auto_free(W.slab_text("PAUSED", 100))
	assert_bool(R.is_display(big.font)).is_true()
	assert_int(big.stroke).is_greater(0)
	assert_int(big.shadow).is_equal(R.drop_px(100))
	assert_bool(big.shadow_straight).is_true()
	assert_bool(big.stroke_color.is_equal_approx(R.NAVY)).is_true()
	assert_bool(big.color.is_equal_approx(R.CREAM)).is_true()
	assert_int(big.bevel).is_equal(0)
	# a gold title carries the bevel
	var gold: WText = auto_free(W.slab_text("1,200", 120, R.GOLD_TEXT))
	assert_int(gold.bevel).is_equal(R.bevel_px(120))
	assert_bool(gold.bevel_color.is_equal_approx(R.GOLD_BEVEL)).is_true()
	# a caller that hands W.text the slab face directly is caught too
	var direct: WText = auto_free(W.text("x", W.slab(), 20))
	assert_bool(R.is_display(direct.font)).is_false()
	var direct_big: WText = auto_free(W.text("x", W.slab(), 40))
	assert_bool(R.is_display(direct_big.font)).is_true()
	# and under Wanted nothing of it
	_royale(false)
	var w: WText = auto_free(W.slab_text("Lv 3", 24))
	assert_str(_base_path(w.font)).is_equal(W.SLAB_PATH)
	assert_int(w.stroke).is_equal(0)
	assert_int(w.shadow).is_equal(0)
	assert_bool(w.color.is_equal_approx(W.INK)).is_true()


func test_the_text_colours_map_on_slate() -> void:
	_royale(true)
	assert_bool(R.text_colour(W.INK).is_equal_approx(R.CREAM)).is_true()
	assert_bool(R.text_colour(W.INK_SOFT).is_equal_approx(R.SECONDARY)).is_true()
	assert_bool(R.text_colour(W.PAPER).is_equal_approx(R.CREAM)).is_true()
	assert_bool(R.text_colour(W.BRASS_DARK).is_equal_approx(R.GOLD_TEXT)).is_true()
	var own := Color("123456")
	assert_bool(R.text_colour(own).is_equal_approx(own)).is_true()
	var body: WText = auto_free(W.serif_text("body", 30))
	assert_bool(body.color.is_equal_approx(R.CREAM)).is_true()
	var note: WText = auto_free(W.serif_text("note", 24, W.INK_SOFT))
	assert_bool(note.color.is_equal_approx(R.SECONDARY)).is_true()
	# a run's colour too
	var t: WText = auto_free(W.text("", W.slab(), 34))
	t.runs = [["REROLL ", null], ["×1", W.INK_SOFT]]
	assert_bool((t.runs[1][1] as Color).is_equal_approx(R.SECONDARY)).is_true()
	assert_bool(t.runs[0][1] == null).is_true()
	_royale(false)
	assert_bool(R.text_colour(W.INK).is_equal_approx(R.CREAM)).is_true()   # the table itself does not care
	var wbody: WText = auto_free(W.serif_text("body", 30))
	assert_bool(wbody.color.is_equal_approx(W.INK)).is_true()
	var u: WText = auto_free(W.text("", W.slab(), 34))
	u.runs = [["×1", W.INK_SOFT]]
	assert_bool((u.runs[0][1] as Color).is_equal_approx(W.INK_SOFT)).is_true()


# ---------------------------------------------------------------- buttons, boxes, dims

func test_button_roles_and_their_colours() -> void:
	assert_str(R.role_of(WButton.PRIMARY)).is_equal("gold")
	assert_str(R.role_of(WButton.DANGER)).is_equal("red")
	assert_str(R.role_of(WButton.UPGRADE)).is_equal("blue")
	assert_str(R.role_of(WButton.SECONDARY)).is_equal("slate")
	assert_array(R.ROLE_NAMES).contains_exactly(["gold", "green", "blue", "slate", "red", "locked"])
	for n in R.ROLE_NAMES:
		var r: Dictionary = R.ROLES[n]
		for k in ["top", "bottom", "base", "text"]:
			assert_bool(r[k] is Color).override_failure_message("%s.%s" % [n, k]).is_true()
	assert_bool(R.ROLES["gold"]["top"].is_equal_approx(Color("ffdc73"))).is_true()
	assert_bool(R.ROLES["gold"]["bottom"].is_equal_approx(Color("f5b82a"))).is_true()
	assert_bool(R.ROLES["gold"]["base"].is_equal_approx(Color("a86d06"))).is_true()
	assert_bool(R.ROLES["gold"]["text"].is_equal_approx(R.NAVY)).is_true()
	assert_bool(R.ROLES["green"]["bottom"].is_equal_approx(Color("5fc43a"))).is_true()
	assert_bool(R.ROLES["blue"]["bottom"].is_equal_approx(Color("3b7fe0"))).is_true()
	assert_bool(R.ROLES["slate"]["base"].is_equal_approx(Color("141b2b"))).is_true()
	assert_bool(R.ROLES["red"]["base"].is_equal_approx(Color("8c1f14"))).is_true()
	assert_bool(R.ROLES["locked"]["top"].is_equal_approx(Color("8f98ab"))).is_true()
	assert_bool(R.ROLES["red"]["text"].is_equal_approx(R.CREAM)).is_true()
	assert_bool(R.role("nonsense") == R.ROLES["slate"]).is_true()
	_royale(true)
	var start := WButton.make(["START"], 34, WButton.PRIMARY)
	auto_free(start)
	assert_str(start.role).is_equal("gold")
	assert_str(start.box.role).is_equal("gold")
	assert_str(start.box.royale_kind()).is_equal("button")
	assert_str(start.label_text()).is_equal("START")
	var st: WText = start._row.get_child(0)
	assert_bool(st.color.is_equal_approx(R.NAVY)).is_true()
	assert_int(st.stroke).is_equal(0)
	var skip := WButton.make(["SKIP", {"count": 2}], 34, WButton.SECONDARY)
	auto_free(skip)
	assert_str(skip.role).is_equal("slate")
	assert_str(skip.label_text()).is_equal("SKIP×2")
	var sk: WText = skip._row.get_child(0)
	assert_bool(sk.color.is_equal_approx(R.CREAM)).is_true()
	assert_int(sk.stroke).is_greater(0)
	assert_object(skip.find_child("Count", true, false)).is_not_null()
	var none := WButton.make(["BANISH", {"count": 0}], 34, WButton.SECONDARY)
	auto_free(none)
	assert_str(none.label_text()).is_equal("BANISH×0")
	var danger: WButton = auto_free(WButton.make(["X"], 34, WButton.DANGER))
	assert_str(danger.role).is_equal("red")
	var upgrade: WButton = auto_free(WButton.make(["X"], 34, WButton.UPGRADE))
	assert_str(upgrade.role).is_equal("blue")
	var buy := WButton.make(["BUY"], 34, WButton.PRIMARY, 5, 8, 26.0, 22.0, 0.0, "green")
	auto_free(buy)
	assert_str(buy.role).is_equal("green")
	assert_str(buy.box.role).is_equal("green")
	buy.set_role("blue")
	assert_str(buy.role).is_equal("blue")
	assert_str(buy.box.role).is_equal("blue")
	assert_str(buy.label_text()).is_equal("BUY")
	# Wanted: the role is carried but the box is the brass paper button as before
	_royale(false)
	var w := WButton.make(["SKIP", {"count": 2}], 34, WButton.PRIMARY)
	auto_free(w)
	assert_str(w.role).is_equal("gold")
	assert_bool(w.box.fill.is_equal_approx(W.BRASS)).is_true()
	assert_str(w.label_text()).is_equal("SKIP×2")
	assert_object(w.find_child("Count", true, false)).is_null()
	assert_bool((w._row.get_child(0) as WText).color.is_equal_approx(W.INK)).is_true()
	assert_int((w._row.get_child(0) as WText).stroke).is_equal(0)


func test_the_hardbox_kinds_and_the_pressed_copy() -> void:
	assert_str(W.box(W.PAPER, 5, 8).royale_kind()).is_equal("panel")
	assert_str(W.box(W.AGED, 5, 0).royale_kind()).is_equal("panel_dim")
	assert_str(W.box(W.ROCK, 5, 8).royale_kind()).is_equal("plain")
	assert_str(W.box(Color(0, 0, 0, 0), 3, 0).royale_kind()).is_equal("plain")
	assert_str(W.plate_box().royale_kind()).is_equal("plate")
	assert_str(W.plate_box().role).is_equal("plate")
	var g := W.box(W.PAPER, 5, 8)
	g.role = "gold"
	assert_str(g.royale_kind()).is_equal("button")
	_royale(false)
	var hb := W.box(W.PAPER, 5, 8).pad(10, 10, 10, 10)
	var p := hb.pressed()
	assert_int(p.press).is_equal(8)
	assert_float(p.content_margin_left).is_equal(18.0)
	assert_float(p.content_margin_top).is_equal(18.0)
	assert_bool(p.held).is_false()
	_royale(true)
	var hr := W.box(W.PAPER, 5, 12).pad(10, 10, 10, 10)
	var pr := hr.pressed()
	assert_int(pr.press).is_equal(R.PRESS_DOWN)
	assert_bool(pr.held).is_true()
	assert_float(pr.content_margin_left).is_equal(10.0)
	assert_float(pr.content_margin_top).is_equal(10.0 + R.PRESS_DOWN)
	assert_float(pr.content_margin_bottom).is_equal(10.0 - R.PRESS_DOWN)


## The review of lane UIKIT_A: Resource.duplicate() copies no HardBox field (game/tools/_p122_UIKIT_dupprobe.gd), so the
## Royale locked face and pressed copy are made with HardBox.copy(), which carries every field; Wanted keeps duplicate().
func test_a_copy_carries_every_field_and_the_locked_tap_stands_on_its_base() -> void:
	var src := W.box(W.ROCK, 3, 12, 9).pad(10, 11, 12, 13)
	src.border_color = W.AGED
	src.sides = [true, true, true, false]
	src.shadow_color = W.BRASS
	src.inner = 4
	src.inner_color = W.EMBER
	src.role = "green"
	src.corners = [true, true, false, false]
	src.held = true
	# what duplicate() loses (the probe's finding, pinned so the rule stays visible)
	var d := src.duplicate() as HardBox
	assert_bool(d.fill.is_equal_approx(W.PAPER)).is_true()
	assert_int(d.border).is_equal(5)
	assert_int(d.shadow).is_equal(0)
	assert_str(d.role).is_equal("")
	assert_float(d.content_margin_left).is_equal(10.0)
	# copy() keeps all of it, the arrays as its own
	var c := src.copy()
	assert_bool(c != src).is_true()
	assert_bool(c.fill.is_equal_approx(W.ROCK)).is_true()
	assert_int(c.border).is_equal(3)
	assert_bool(c.border_color.is_equal_approx(W.AGED)).is_true()
	assert_array(c.sides).contains_exactly([true, true, true, false])
	assert_int(c.shadow).is_equal(12)
	assert_bool(c.shadow_color.is_equal_approx(W.BRASS)).is_true()
	assert_int(c.radius).is_equal(9)
	assert_int(c.inner).is_equal(4)
	assert_bool(c.inner_color.is_equal_approx(W.EMBER)).is_true()
	assert_str(c.role).is_equal("green")
	assert_array(c.corners).contains_exactly([true, true, false, false])
	assert_bool(c.held).is_true()
	assert_float(c.content_margin_left).is_equal(10.0)
	assert_float(c.content_margin_bottom).is_equal(13.0)
	c.sides[3] = true
	c.corners[2] = true
	assert_bool(src.sides[3]).is_false()
	assert_bool(src.corners[2]).is_false()
	# the Royale pressed copy keeps the box's shape: a docked tab (no bottom side, top corners, a 3 px edge) stays one
	_royale(true)
	var tab := W.box(W.PAPER, 3, 6, R.RADIUS_TAB)
	tab.sides = [true, true, true, false]
	tab.corners = [true, true, false, false]
	tab.role = "slate"
	var pr := tab.pressed()
	assert_int(pr.border).is_equal(3)
	assert_int(pr.radius).is_equal(R.RADIUS_TAB)
	assert_array(pr.sides).contains_exactly([true, true, true, false])
	assert_array(pr.corners).contains_exactly([true, true, false, false])
	assert_str(pr.role).is_equal("slate")
	assert_int(pr.press).is_equal(6)
	assert_bool(pr.held).is_true()
	assert_bool(W.box(W.BRASS, 5, 8).pressed(W.BRASS_DARK).fill.is_equal_approx(W.BRASS_DARK)).is_true()
	# the locked tap: the grey role on the box's OWN base, its border and corners kept, the piece at 75 %
	var tap: WTap = auto_free(WTap.new())
	tap.box = W.box(W.PAPER, 4, 10, R.RADIUS_TAB)
	tap.locked = true
	var lb: HardBox = tap.get_theme_stylebox("panel")
	assert_bool(lb != tap.box).is_true()
	assert_str(lb.role).is_equal("locked")
	assert_str(lb.royale_kind()).is_equal("button")
	assert_int(lb.shadow).is_equal(10)
	assert_int(lb.border).is_equal(4)
	assert_int(lb.radius).is_equal(R.RADIUS_TAB)
	assert_int(lb.inner).is_equal(0)
	assert_float(tap.modulate.a).is_equal_approx(R.LOCKED_ALPHA, 0.001)
	assert_str(tap.box.role).is_equal("")
	# a locked button stands on the same 8 px base as the buttons beside it
	var btn: WButton = auto_free(WButton.make(["LOCKED"], 34, WButton.SECONDARY))
	btn.locked = true
	var bb: HardBox = btn.get_theme_stylebox("panel")
	assert_str(bb.role).is_equal("locked")
	assert_int(bb.shadow).is_equal(8)
	assert_int(bb.border).is_equal(5)
	assert_float(btn.modulate.a).is_equal_approx(R.LOCKED_ALPHA, 0.001)
	btn.locked = false
	assert_str((btn.get_theme_stylebox("panel") as HardBox).role).is_equal("slate")
	assert_float(btn.modulate.a).is_equal_approx(1.0, 0.001)
	# Wanted: as it has always been (aged, no shadow, 45 %; the pressed copy still a duplicate(): pixel-identical)
	_royale(false)
	tap.locked = false
	tap.locked = true
	var wb: HardBox = tap.get_theme_stylebox("panel")
	assert_bool(wb.fill.is_equal_approx(W.AGED)).is_true()
	assert_int(wb.shadow).is_equal(0)
	assert_str(wb.role).is_equal("")
	assert_float(tap.modulate.a).is_equal_approx(0.45, 0.001)
	var wp := W.box(W.ROCK, 3, 8).pressed()
	assert_bool(wp.fill.is_equal_approx(W.PAPER)).is_true()
	assert_int(wp.border).is_equal(5)
	assert_int(wp.press).is_equal(8)
	assert_bool(wp.held).is_false()


func test_the_dims_follow_the_theme_and_no_w_constant_moves() -> void:
	# the kit's colours as the Wanted handoff set them: the theme never moves a constant
	var pins := [[W.INK, Color("241b14")], [W.PAPER, Color("f3e6c8")], [W.AGED, Color("e2cfa4")], [W.BRASS, Color("c9932f")],
		[W.ROCK, Color("b4472b")], [W.SAGE, Color("6e8b5e")], [W.INK_SOFT, Color("5a4a3a")],
		[W.DIM, Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.78)], [W.DIM_ASK, Color(36 / 255.0, 27 / 255.0, 20 / 255.0, 0.55)],
		[W.WASH, Color(243 / 255.0, 230 / 255.0, 200 / 255.0, 0.82)]]
	_royale(false)
	assert_bool(W.dim_color("modal").is_equal_approx(W.DIM)).is_true()
	assert_bool(W.dim_color("chest").is_equal_approx(W.DIM_CHEST)).is_true()
	assert_bool(W.dim_color("down").is_equal_approx(W.DIM_DOWN)).is_true()
	assert_bool(W.dim_color("stranger").is_equal_approx(W.DIM_STRANGER)).is_true()
	assert_bool(W.dim_color("gate").is_equal_approx(W.DIM_GATE)).is_true()
	assert_bool(W.dim_color("ask").is_equal_approx(W.DIM_ASK)).is_true()
	assert_bool(W.dim_color("wash").is_equal_approx(W.WASH)).is_true()
	assert_bool(W.themed_dim(W.DIM_DOWN).is_equal_approx(W.DIM_DOWN)).is_true()
	_royale(true)
	assert_bool(W.dim_color("modal").is_equal_approx(R.DIM)).is_true()
	assert_bool(W.dim_color("chest").is_equal_approx(R.DIM)).is_true()
	assert_bool(W.dim_color("ask").is_equal_approx(R.DIM)).is_true()
	assert_bool(W.dim_color("gate").is_equal_approx(R.DIM_GATE)).is_true()
	assert_bool(W.dim_color("down").is_equal_approx(R.DIM_DOWN)).is_true()
	assert_bool(W.dim_color("wash").is_equal_approx(R.WASH)).is_true()
	assert_float(R.DIM.a).is_equal_approx(0.8, 0.001)
	assert_bool(W.themed_dim(W.DIM).is_equal_approx(R.DIM)).is_true()
	assert_bool(W.themed_dim(W.DIM_DOWN).is_equal_approx(R.DIM_DOWN)).is_true()
	var own := Color(W.DIM.r, W.DIM.g, W.DIM.b, 0.3)
	assert_bool(W.themed_dim(own).is_equal_approx(own)).is_true()
	for pair in pins:
		assert_bool((pair[0] as Color).is_equal_approx(pair[1])).override_failure_message(str(pair[1])).is_true()
	assert_bool(W.RARITY_PLATE["uncommon"].is_equal_approx(Color("8cc97a"))).is_true()
	assert_bool(R.NAVY.is_equal_approx(Color("0e1f4a"))).is_true()
	assert_bool(R.CREAM.is_equal_approx(Color("fff6dc"))).is_true()
	assert_bool(R.SECONDARY.is_equal_approx(Color("cfe3ff"))).is_true()
	assert_bool(R.PLATE.is_equal_approx(Color(8 / 255.0, 10 / 255.0, 18 / 255.0, 0.56))).is_true()
	for n in ["common", "uncommon", "rare", "epic", "legendary", "evolved"]:
		for k in ["light", "base", "dark", "rim"]:
			assert_bool(R.RARITY[n][k] is Color).override_failure_message("%s.%s" % [n, k]).is_true()
	assert_bool(R.RARITY["legendary"]["inner"].is_equal_approx(Color("7a4a05"))).is_true()
	assert_int(R.RAINBOW.size()).is_equal(8)
	assert_int(R.RIM_BEVEL.size()).is_equal(4)


# ---------------------------------------------------------------- every component, both themes

## Builds one of everything the lane touched into `host`.
func _kit(host: Control) -> Dictionary:
	var out := {}
	var col := VBoxContainer.new()
	col.position = Vector2(40, 40)
	host.add_child(col)
	for b in [W.box(W.PAPER, 5, 8), W.box(W.AGED, 5, 0), W.plate_box(), W.box(Color(0, 0, 0, 0), 3, 0), W.box(W.ROCK, 5, 8, 6)]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", b.pad(20, 20, 20, 20))
		pc.add_child(W.slab_text("Box", 34))
		col.add_child(pc)
	var inner := W.box(W.PAPER, 5, 8)
	inner.inner = 5
	var ipc := PanelContainer.new()
	ipc.add_theme_stylebox_override("panel", inner.pad(20, 20, 20, 20))
	ipc.add_child(W.serif_text("A held card's +15% line, 1.5 s", 30))
	col.add_child(ipc)
	col.add_child(W.slab_text("TITLE", 100))
	col.add_child(W.slab_text("Lv 3", 24))
	col.add_child(W.label("Camera", 22))
	col.add_child(W.serif_text("Notes, 400", 26, W.INK_SOFT, 400, true))
	var t := W.text("", W.slab(), 34)
	t.runs = [["REROLL ", null], ["×1", W.INK_SOFT]]
	col.add_child(t)
	var row := HBoxContainer.new()
	col.add_child(row)
	for v in [WButton.PRIMARY, WButton.SECONDARY, WButton.DANGER, WButton.UPGRADE]:
		row.add_child(WButton.make([v.to_upper(), {"coin": 30.0}, "9", {"count": 1}], 34, v))
	var locked := WButton.make(["LOCKED"], 34, WButton.SECONDARY)
	locked.locked = true
	row.add_child(locked)
	var held := WButton.make(["HELD"], 34, WButton.PRIMARY)
	held.show_held(true)
	row.add_child(held)
	var green := WButton.make([{"coin": 30.0}, "300"], 34, WButton.PRIMARY, 5, 8, 26.0, 22.0, 0.0, "green")
	row.add_child(green)
	out["buttons"] = row
	var tabs := WTabs.make(["Build", "Stats", [["Options ", null], ["3", W.BRASS_DARK]]], 30)
	col.add_child(tabs)
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", WTabs.board().pad(30, 30, 30, 30))
	board.add_child(W.serif_text("The board under the tabs", 30))
	col.add_child(board)
	tabs.select(1)
	out["tabs"] = tabs
	var choice := WChoice.make([["Fixed", "north stays up"], ["Follow", "swings behind the hero"]], 0, 36, 24, 20.0, HORIZONTAL_ALIGNMENT_CENTER, 0)
	choice.choose(1)
	col.add_child(choice)
	out["choice"] = choice
	var sw_row := HBoxContainer.new()
	sw_row.add_child(WSwitch.make(true))
	sw_row.add_child(WSwitch.make(false))
	col.add_child(sw_row)
	out["switches"] = sw_row
	var tap := WTap.new()
	tap.box = W.box(W.PAPER, 5, 6)
	tap.add_child(W.slab_text("A row", 30))
	col.add_child(tap)
	var tap_locked := WTap.new()
	tap_locked.box = W.box(W.PAPER, 5, 6)
	tap_locked.add_child(W.slab_text("A locked row", 30))
	tap_locked.locked = true
	col.add_child(tap_locked)
	out["tap"] = tap
	var mh := WMenuHeader.make("SETTINGS", WMenuHeader.gold_plate(1200))
	host.add_child(mh)
	out["menu_header"] = mh
	var modal := WModal.new()
	modal.build_dim(W.DIM)
	modal.build_header("Level up", "LEVEL 7", "Pick one. The desert waits.", 150)
	var btns := modal.build_buttons()
	btns.add_child(WButton.make(["RESUME"], 34, WButton.PRIMARY))
	host.add_child(modal)
	modal.enter([btns])
	out["modal"] = modal
	var hdr := WModalHeader.make("Boss down", "STAGE 1 CLEAR", "", 108, W.PAPER, 30, 600.0)
	hdr.set_title_fit("MUTATION CHEST", 150, W.PAPER, 1000.0)
	hdr.set_star("A path opens", W.PLUM)
	hdr.set_line("the others come back next stage")
	hdr.shadow_star(2)
	host.add_child(hdr)
	out["header"] = hdr
	return out


func test_every_component_builds_and_draws_under_both_themes() -> void:
	for royale in [false, true]:
		_royale(royale)
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(host)
		var made := _kit(host)
		var ask := WConfirm.open(host, "Abandon the run?", "The purse is kept.", "Abandon", "Keep going", func(): pass)
		var buy := WConfirm.open(host, "Buy it?", "300 gold.", "Buy", "Not now", func(): pass, Callable(), "buy")
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		assert_bool(is_instance_valid(buy)).override_failure_message("royale=%s" % royale).is_true()
		assert_object(WConfirm.current(host)).is_same(buy)
		# the first question was replaced by the second at once (freed, or done and fading)
		assert_bool(not is_instance_valid(ask) or ask._done).is_true()
		assert_str(buy.confirm_btn.role).is_equal("green")
		assert_str(buy.cancel_btn.role).is_equal("slate")
		assert_str(buy.confirm_btn.variant).is_equal(WButton.PRIMARY)
		var sw: WSwitch = made["switches"].get_child(0)
		assert_bool(sw.custom_minimum_size.is_equal_approx(Vector2(140, 80))).is_true()
		var tabs: WTabs = made["tabs"]
		assert_int(tabs.selected).is_equal(1)
		var lab: WText = (tabs._tabs[1] as WTap).get_child(0)
		var off: WText = (tabs._tabs[0] as WTap).get_child(0)
		if royale:
			assert_bool(lab.color.is_equal_approx(R.NAVY)).is_true()
			assert_bool(off.color.is_equal_approx(R.CREAM)).is_true()
			assert_str((tabs._tabs[1] as WTap).box.role).is_equal("gold")
			assert_str((tabs._tabs[0] as WTap).box.role).is_equal("slate")
			assert_bool((tabs._tabs[1] as WTap).box.content_margin_top > (tabs._tabs[0] as WTap).box.content_margin_top).is_true()
			# the dim's own colour (dim.color is mid-fade: enter() brings its alpha up over 0.2 s)
			assert_bool(made["modal"].dim_color.is_equal_approx(R.DIM)).is_true()
			assert_bool(made["header"].title.color.is_equal_approx(R.CREAM)).is_true()
			assert_bool(made["header"].title.shadow_straight).is_true()
			var mh: WMenuHeader = made["menu_header"]
			assert_bool(mh.title.color.is_equal_approx(R.CREAM)).is_true()
			assert_str((mh.right as PanelContainer).get_theme_stylebox("panel").role).is_equal("plate")
			var ch: WChoice = made["choice"]
			assert_str((ch._halves[1] as WTap).box.role).is_equal("gold")
			assert_str((ch._halves[0] as WTap).box.role).is_equal("slate")
			assert_bool((ch._texts[1][0] as WText).color.is_equal_approx(R.NAVY)).is_true()
			assert_bool((ch._texts[0][0] as WText).color.is_equal_approx(R.CREAM)).is_true()
			var confirm_modal: WText = buy.find_child("Confirm", true, false)._row.get_child(0)
			assert_bool(confirm_modal.color.is_equal_approx(R.CREAM)).is_true()
		else:
			assert_bool(lab.color.is_equal_approx(W.INK)).is_true()
			assert_bool(off.color.is_equal_approx(W.INK_SOFT)).is_true()
			assert_bool((tabs._tabs[1] as WTap).box.fill.is_equal_approx(W.PAPER)).is_true()
			assert_bool((tabs._tabs[0] as WTap).box.fill.is_equal_approx(W.AGED)).is_true()
			assert_bool(made["modal"].dim_color.is_equal_approx(W.DIM)).is_true()
			assert_bool(made["header"].title.color.is_equal_approx(W.PAPER)).is_true()
			assert_int(made["header"].title.shadow).is_equal(8)
			assert_bool(made["header"].title.shadow_straight).is_false()
			var ch: WChoice = made["choice"]
			assert_bool((ch._halves[1] as WTap).box.fill.is_equal_approx(W.INK)).is_true()
			assert_bool((ch._texts[1][0] as WText).color.is_equal_approx(W.PAPER)).is_true()
			assert_bool(buy.confirm_btn.box.fill.is_equal_approx(W.BRASS)).is_true()
		# a finger on the switch and the tab answers under either theme
		var before := sw.on
		var tap_at := sw.global_position + Vector2(20, 20)
		sw._gui_input(_touch(tap_at, true))
		sw._gui_input(_touch(tap_at, false))
		assert_bool(sw.on).is_equal(not before)
		var tapped := [false]
		(tabs._tabs[2] as WTap).pressed.connect(func(): tapped[0] = true)
		(tabs._tabs[2] as WTap)._gui_input(_touch(Vector2(10, 10), true))
		(tabs._tabs[2] as WTap)._gui_input(_touch(Vector2(12, 12), false))
		assert_bool(tapped[0]).is_true()
		assert_int(tabs.selected).is_equal(2)
		buy.cancel()
		await get_tree().process_frame
		host.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame


func _touch(at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	return e
