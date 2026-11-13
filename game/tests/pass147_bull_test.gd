## Pass 147, lane ROBOT (Garry: "Let's update The Robot character because right now it's trying to be too many things at once,
## a robot, a basketball player a bull ... Use the latest 3d model ... Use the 3d puppet method ... he is wider and that's by
## design"): the outlaw `fadeaway` plays one look, FAD-I (a huge black bull standing like a man in a red basketball kit with the
## number 22, nothing metal), walked on his own rigged 3D model's guides; it loads with every frame row of a hero strip, its
## badge, sheet still and title cut-out exist, and every older look of his is shelved (they show the robot and the man before).
extends GdUnitTestSuite

const CODE := "FAD-I"
## every row a hero strip carries (Player's order)
const ROWS := ["idle", "run", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd",
	"hit_f", "hit_s", "hit_bd", "hit_fd"]


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func _bull() -> CharacterDef:
	var c: CharacterDef = Registry.character("fadeaway")
	assert_object(c).override_failure_message("no outlaw fadeaway").is_not_null()
	return c


func _json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/fadeaway/fadeaway.json")) as Dictionary


func test_the_bull_plays_fad_i_with_every_frame_row() -> void:
	var c := _bull()
	assert_str(c.variant).override_failure_message("the look he plays").is_equal(CODE)
	assert_bool(c.variants.has(CODE)).override_failure_message("no look " + CODE).is_true()
	assert_bool(c.variant_shelved(CODE)).override_failure_message(CODE + " shelved").is_false()
	# `fresh` is the Level Editor's flag (the JSON's; the game's def does not carry it): fresh until Garry approves the look
	assert_bool(bool((_json()["variants"] as Dictionary)[CODE].get("fresh", false))).override_failure_message(CODE + ": fresh").is_true()
	var worn := Registry.played_look(c)
	assert_str(worn.look_code()).override_failure_message("a fresh save plays " + CODE).is_equal(CODE)
	assert_str(worn.strip_path().get_file()).is_equal("fadeaway_sprite_i.png")
	var e: Dictionary = c.variants[CODE]
	var an: Dictionary = e["anims"]
	var total := 0
	for r: String in ROWS:
		assert_int(int(an.get(r, 0))).override_failure_message("row %s empty" % r).is_greater(0)
		total += int(an.get(r, 0))
	var cols := int(e["strip_cols"])
	var tex := load(worn.strip_path()) as Texture2D
	assert_object(tex).override_failure_message("the strip loads").is_not_null()
	assert_int(tex.get_width()).is_equal(cols * 256)
	assert_int(tex.get_height()).is_equal(int(ceil(float(total) / float(cols))) * 256)
	assert_int(worn.strip_cols).is_equal(cols)
	assert_float(float(worn.fps.get("run", 0))).override_failure_message("run rate").is_greater(0.0)


func test_the_bull_walks_on_his_own_puppet() -> void:
	# the recipe names the guides made from his rigged 3D model (the Level Editor and a later run read them)
	var rec: Dictionary = ((_json()["variants"] as Dictionary)[CODE] as Dictionary)["recipe"]
	for v: String in ["front", "fd", "side", "bd", "back"]:
		assert_str(str(rec["ctl_drivers"][v])).is_equal("fadeaway_bull_creature_walk_depth")
		assert_str(str(rec["pose_drivers"][v])).is_equal("fadeaway_bull_creature_walk")
	assert_str(str(rec["run_fit"])).contains("fadeaway_bull_creature_walk")
	assert_str(str(rec["method"])).is_equal("hero_puppet")


func test_every_older_look_is_shelved() -> void:
	var c := _bull()
	var n := 0
	for code: String in c.variants:
		if code == CODE:
			continue
		n += 1
		assert_bool(c.variant_shelved(code)).override_failure_message(code + " still offered: it shows the old character").is_true()
	assert_int(n).override_failure_message("the older looks are kept (shelved, never deleted)").is_greater(0)
	# a phone that kept the robot from the arena plays the bull all the same
	Save.data["hero_look"] = {"fadeaway": "FAD-H"}
	assert_str(Registry.played_look(c).look_code()).is_equal(CODE)


func test_the_badge_the_sheet_still_and_the_title_exist() -> void:
	var c := _bull()
	var e: Dictionary = c.variants[CODE]
	var icon := str(e.get("icon", ""))
	assert_str(icon.get_file()).override_failure_message("badge").is_equal("fadeaway_icon_i.png")
	assert_object(LookArt.icon(e.get("icon"))).override_failure_message("badge loads").is_not_null()
	assert_str(c.look_still_path(CODE)).override_failure_message("sheet still").is_not_empty()
	var worn := c.variant_def(CODE)
	assert_str(worn.look_title()).override_failure_message("title").is_equal("hero_fadeaway_i.png")
	assert_bool(ResourceLoader.exists(worn.title_path())).override_failure_message("title file").is_true()
	assert_str(worn.title_path()).is_not_equal(CharacterDef.TITLE_DIR + "hero_fadeaway.png")
