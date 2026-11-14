## Pass 148, lane HORSE (Garry: "Let's do a similar thing that we did to Pip to Horseman now ... create a convincing looking 3d
## first with proper textures and everything and then turn that into a sprite sheet"): the outlaw `buck` (the Horseman) plays one
## look, BUC-I, walked on his own rigged, textured 3D model's guides (horseman.glb, its poncho hanging like a blanket); it loads
## with every frame row of a hero strip, its badge, sheet still and title cut-out exist, every older look of his is shelved, and
## his gameplay is untouched.
extends GdUnitTestSuite

const CODE := "BUC-I"
## every row a hero strip carries (Player's order)
const ROWS := ["idle", "run", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd",
	"hit_f", "hit_s", "hit_bd", "hit_fd"]


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func _buck() -> CharacterDef:
	var c: CharacterDef = Registry.character("buck")
	assert_object(c).override_failure_message("no outlaw buck").is_not_null()
	return c


func _json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/buck/buck.json")) as Dictionary


func test_the_horseman_plays_buc_i_with_every_frame_row() -> void:
	var c := _buck()
	assert_str(c.variant).override_failure_message("the look he plays").is_equal(CODE)
	assert_bool(c.variants.has(CODE)).override_failure_message("no look " + CODE).is_true()
	assert_bool(c.variant_shelved(CODE)).override_failure_message(CODE + " shelved").is_false()
	# `fresh` is the Level Editor's flag (the JSON's): fresh until Garry approves the look
	assert_bool(bool((_json()["variants"] as Dictionary)[CODE].get("fresh", false))).override_failure_message(CODE + ": fresh").is_true()
	var worn := Registry.played_look(c)
	assert_str(worn.look_code()).override_failure_message("a fresh save plays " + CODE).is_equal(CODE)
	assert_str(worn.strip_path().get_file()).is_equal("buck_sprite_i.png")
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


func test_the_horseman_runs_on_his_own_puppet() -> void:
	# the recipe names the guides made from his rigged 3D model; a normal run (never the dash)
	var rec: Dictionary = ((_json()["variants"] as Dictionary)[CODE] as Dictionary)["recipe"]
	# front, bd and back on its depth guides; the side and fd on its OpenPose guides (on depth Wan painted the poncho gold)
	var ctl: Dictionary = rec["ctl_drivers"]
	for v: String in ["front", "fd", "side", "bd", "back"]:
		assert_str(str(rec["pose_drivers"][v])).is_equal("buck_horse_run")
		if v in ["front", "bd", "back"]:
			assert_str(str(ctl.get(v, ""))).is_equal("buck_horse_run_depth")
		else:
			assert_bool(ctl.has(v)).override_failure_message(v + " walks on its pose guide").is_false()
	assert_str(str(rec["run_fit"])).contains("buck_horse_run")
	assert_str(str(rec["method"])).is_equal("hero_puppet")
	assert_str(str(rec["puppet"]["source"])).is_equal("horseman.glb")


func test_every_older_look_is_shelved() -> void:
	var c := _buck()
	var n := 0
	for code: String in c.variants:
		if code == CODE:
			continue
		n += 1
		assert_bool(c.variant_shelved(code)).override_failure_message(code + " still offered: it shows the old art").is_true()
	assert_int(n).override_failure_message("the older looks are kept (shelved, never deleted)").is_greater(0)
	# a phone that kept BUC-H from the arena plays BUC-I all the same
	Save.data["hero_look"] = {"buck": "BUC-H"}
	assert_str(Registry.played_look(c).look_code()).is_equal(CODE)


func test_the_badge_the_sheet_still_and_the_title_exist() -> void:
	var c := _buck()
	var e: Dictionary = c.variants[CODE]
	assert_str(str(e.get("icon", "")).get_file()).override_failure_message("badge").is_equal("buck_icon_i.png")
	assert_object(LookArt.icon(e.get("icon"))).override_failure_message("badge loads").is_not_null()
	assert_str(c.look_still_path(CODE)).override_failure_message("sheet still").is_not_empty()
	var worn := c.variant_def(CODE)
	assert_str(worn.look_title()).override_failure_message("title").is_equal("hero_buck_i.png")
	assert_bool(ResourceLoader.exists(worn.title_path())).override_failure_message("title file").is_true()


func test_the_gameplay_is_unchanged() -> void:
	var c := _buck()
	assert_str(c.id).is_equal("buck")
	assert_str(c.start_weapon).is_equal("frisbee")
