## Pass 143, lane HORSE (Garry: "Jezyk. He should become the Horseman. This will be a humanoid character with a horse head. He
## should be wearing a poncho, and westerny attire otherwise. Otherwise he does the same thing."): the outlaw `buck` plays one
## new look, BUC-H (a lean man with a chestnut horse head in an indigo serape poncho), fresh until Garry approves it; it loads
## with every frame row of a hero strip, its badge, sheet still and title cut-out exist, and every older look (Jeżyk's) is
## shelved. Gameplay is untouched (the same start weapon).
## Pass 148 (lane HORSE): the Horseman plays BUC-I (his textured 3D model's puppet), BUC-H is kept whole and shelved: these
## tests read the played look from the data and pin BUC-H's art as kept, never as played.
extends GdUnitTestSuite

const CODE := "BUC-H"
## every row a hero strip carries (Player's order), as many frames as the outlaw's own strip
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


func test_the_horseman_look_loads_and_is_played() -> void:
	var c := _buck()
	# pass 148: the played look is the JSON's (BUC-I since pass 148); BUC-H is kept whole, shelved
	assert_bool(c.variants.has(CODE)).override_failure_message("no look BUC-H (kept, never deleted)").is_true()
	assert_bool(c.variant_shelved(CODE)).override_failure_message("BUC-H shelved since pass 148").is_true()
	var worn: CharacterDef = Registry.played_look(c)
	assert_str(worn.look_code()).is_equal(c.variant)
	var e: Dictionary = c.variants[CODE]
	var an: Dictionary = e["anims"]
	var total := 0
	for r: String in ROWS:
		assert_int(int(an.get(r, 0))).override_failure_message("row %s empty" % r).is_greater(0)
		total += int(an.get(r, 0))
	assert_int(total).override_failure_message("frames").is_equal(166)
	assert_int(int(e["strip_cols"])).is_equal(62)
	var strip := c.look_strip_path(CODE)
	assert_str(strip.get_file()).is_equal("buck_sprite_h.png")
	var tex := load(strip) as Texture2D
	assert_object(tex).override_failure_message("the strip loads").is_not_null()
	assert_int(tex.get_width()).is_equal(62 * 256)
	assert_int(tex.get_height()).is_equal(3 * 256)


func test_the_badge_the_sheet_still_and_the_title_exist() -> void:
	var c := _buck()
	var e: Dictionary = c.variants[CODE]
	assert_str(str(e.get("icon", "")).get_file()).is_equal("buck_icon_h.png")
	assert_object(LookArt.icon(e.get("icon"))).override_failure_message("badge loads").is_not_null()
	assert_str(c.look_still_path(CODE)).override_failure_message("sheet still").is_not_empty()
	var worn: CharacterDef = c.variant_def(CODE)
	assert_str(worn.look_title()).is_equal("hero_buck_h.png")
	assert_bool(ResourceLoader.exists(worn.title_path())).override_failure_message("title file").is_true()


func test_every_older_look_is_shelved() -> void:
	var c := _buck()
	for code in c.variants.keys():
		if str(code) == c.variant:
			continue
		assert_bool(c.variant_shelved(str(code))).override_failure_message("%s still offered (older art)" % code).is_true()
	# the arena's chips: the played look alone, so the list is empty (one art)
	assert_array(c.variant_codes()).is_empty()


func test_the_gameplay_is_unchanged() -> void:
	var c := _buck()
	assert_str(c.start_weapon).is_equal("frisbee")
	assert_str(c.id).is_equal("buck")


## Pass 143 follow-up (Garry on BUC-H: "no need for that Naruto run, do a normal run"): the look runs on the plain run drivers
## the other outlaws use (arms swinging at his sides under the poncho), never on the dash with both arms swept back.
func test_the_run_is_a_normal_run() -> void:
	var rec: Dictionary = ((_json()["variants"] as Dictionary)[CODE] as Dictionary).get("recipe", {})
	var drivers: Dictionary = rec.get("pose_drivers", {})
	for view in ["front", "fd", "side", "bd", "back"]:
		assert_bool(drivers.has(view)).override_failure_message("no driver for " + view).is_true()
		assert_bool(str(drivers.get(view, "")).begins_with("run_dash")).override_failure_message(view + " still runs the dash").is_false()
	assert_bool(str(rec.get("pose_motion", "")).contains("swept")).override_failure_message("the motion words still sweep the arms back").is_false()
