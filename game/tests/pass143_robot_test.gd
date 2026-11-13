## Pass 143, lane ROBOT (Garry: "Fadeaway. Should become The Robot. This robot will have a head of a robot bull and will be
## wearing Chicago bulls red basketball uniform. Without any of the Chicago bulls symbols."; "Don't create any looks for them
## yet"): the outlaw `fadeaway` played one look, FAD-H (a lean robot of dark metal with a robot bull's head in a red jersey and
## shorts, the 88 on the chest and the back), painted for that pass; it loads with every frame row of a hero strip, its badge,
## sheet still and title cut-out exist, and every look but the one he plays is shelved.
## Pass 147 (re-pinned by the data): he is the bull basketball player now (FAD-I, pass147_bull_test.gd); FAD-H is kept, whole
## and shelved, like every older look.
extends GdUnitTestSuite

const CODE := "FAD-H"
## every row a hero strip carries (Player's order), as many frames as FAD-E's (the look it replaced, same walk)
const ROWS := ["idle", "run", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd",
	"hit_f", "hit_s", "hit_bd", "hit_fd"]


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func _robot() -> CharacterDef:
	var c: CharacterDef = Registry.character("fadeaway")
	assert_object(c).override_failure_message("no outlaw fadeaway").is_not_null()
	return c


func _json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/fadeaway/fadeaway.json")) as Dictionary


func test_the_robot_look_fad_h_keeps_every_frame_row() -> void:
	var c := _robot()
	assert_bool(c.variants.has(CODE)).override_failure_message("no look " + CODE).is_true()
	# the look he plays is the JSON's (pass 147: the bull, FAD-I); FAD-H is shelved since, never deleted
	assert_str(c.variant).is_equal(str(_json()["variant"]))
	assert_bool(c.variant_shelved(CODE)).override_failure_message(CODE + " shelved since pass 147").is_equal(c.variant != CODE)
	var worn := c.variant_def(CODE)
	assert_str(worn.strip_path().get_file()).is_equal("fadeaway_sprite_h.png")
	var e: Dictionary = c.variants[CODE]
	var an: Dictionary = e["anims"]
	var was: Dictionary = (c.variants["FAD-E"] as Dictionary)["anims"]
	var total := 0
	for r: String in ROWS:
		assert_int(int(an.get(r, 0))).override_failure_message("row %s" % r).is_equal(int(was.get(r, 0)))
		assert_int(int(an.get(r, 0))).override_failure_message("row %s empty" % r).is_greater(0)
		total += int(an.get(r, 0))
	assert_int(total).override_failure_message("frames").is_equal(166)
	assert_int(int(e["strip_cols"])).is_equal(62)
	var tex := load(worn.strip_path()) as Texture2D
	assert_object(tex).override_failure_message("the strip loads").is_not_null()
	assert_int(tex.get_width()).is_equal(62 * 256)
	assert_int(tex.get_height()).is_equal(3 * 256)


func test_every_look_but_the_played_one_is_shelved() -> void:
	var c := _robot()
	var n := 0
	for code: String in c.variants:
		if code == c.variant:
			continue
		n += 1
		assert_bool(c.variant_shelved(code)).override_failure_message(code + " still offered: it shows an older character").is_true()
	assert_int(n).override_failure_message("the older looks are kept (shelved, never deleted)").is_greater(0)
	# a phone that kept an old look from the arena plays the one he plays all the same
	Save.data["hero_look"] = {"fadeaway": "FAD-E"}
	assert_str(Registry.played_look(c).look_code()).is_equal(c.variant)


func test_the_robot_badge_sheet_still_and_title_are_kept() -> void:
	var c := _robot()
	var e: Dictionary = c.variants[CODE]
	var icon := str(e.get("icon", ""))
	assert_str(icon.get_file()).override_failure_message("badge").is_equal("fadeaway_icon_h.png")
	assert_object(LookArt.icon(e.get("icon"))).override_failure_message("badge loads").is_not_null()
	var worn := c.variant_def(CODE)
	assert_str(worn.look_title()).override_failure_message("title").is_equal("hero_fadeaway_h.png")
	assert_bool(ResourceLoader.exists(worn.title_path())).override_failure_message("title file").is_true()
