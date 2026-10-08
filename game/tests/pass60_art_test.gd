extends GdUnitTestSuite

## Pass 60, lane ART (Garry: "Werewolf - make another version similar to the chosen ... his up walk seems to not match the
## stance that it has for down walk, down walk one is the correct one"; "Solenne - make another version similar to the
## chosen ... critically evaluate the latest prompt and try making it better"; "Critical Thinking - also regenerate that
## icon, it's nonsensical"): the werewolf's WW-D is WW-A's front (the same painting, so its first front cell is WW-A's
## pixel for pixel) with a back painted to that stance and a back walk driven on the Orc Walk like the front (WW-A's and
## WW-B's back walks were free clips: every driven try put the clawed feet on the clip's bottom edge, so WW-D's back view
## runs on `orc_walk_wolf_b88`, the stick figure shrunk 12%, as a `pose`/`pose_front` pair); Solenne's SOL-E is the
## catwalk again on the fitted drivers with a prompt that says what each part of the body does and its own seeds; the
## Critical Thinking icon is a new 256 px painting and the old one is kept in tools/dl/backup/icons60.

const WW := "res://content/enemies/werewolf/"
const SOL := "res://content/characters/solenne/"
const ICON := "res://content/mutations/critical_thinking/critical_thinking_icon.png"


func _cell(path: String, cell: int, col: int) -> PackedByteArray:
	var img := Image.load_from_file(path)
	assert_object(img).override_failure_message(path).is_not_null()
	return img.get_region(Rect2i(col * cell, 0, cell, cell)).get_data()


func test_werewolf_ww_d_resolves_with_its_own_strip() -> void:
	var w: EnemyDef = Registry.enemy("werewolf")
	assert_object(w).is_not_null()
	assert_array(w.variant_codes()).contains(["WW-A", "WW-B", "WW-C", "WW-D"])
	var d: EnemyDef = w.variant_def("WW-D")
	# the played look is the def itself (variant_def returns self for the code in `variant`); any other code is a copy
	if w.variant == "WW-D":
		assert_object(d).is_same(w)
	else:
		assert_object(d).is_not_same(w)
		assert_str(d.variant_code).is_equal("WW-D")
	assert_str(d.sprite_file).is_equal("werewolf_sprite_d.png")
	assert_object(d.sprite).is_not_null()
	assert_int(d.strip_cols).is_greater(0)
	assert_float(d.head).is_between(0.8, 1.0)
	assert_int(int(d.fps.get("run", 0))).is_equal(15)
	assert_int(int(d.fps.get("die", 0))).is_equal(12)
	# the back walk is driven (12 frames) like the front's, not the free clip's cut
	assert_int(d.frames_of("run")).is_equal(12)
	assert_int(d.frames_of("run_b")).is_equal(12)
	assert_str(d.type_key()).is_equal("werewolf" if w.variant == "WW-D" else "werewolf@WW-D")


func test_ww_d_front_is_ww_a_pixel_for_pixel() -> void:
	# the first cell is the front idle, the standing painting itself ("stand": "still"): copied, not repainted
	var a := _cell(WW + "werewolf_sprite_a.png", 176, 0)
	var d := _cell(WW + "werewolf_sprite_d.png", 176, 0)
	assert_int(a.size()).is_equal(176 * 176 * 4)
	assert_bool(a == d).override_failure_message("WW-D's front idle cell differs from WW-A's").is_true()
	# the back idle cell (after idle 4, run 12, attack 2, hit 1, die 8, run_b 12 = column 39) is a new painting
	var ab := _cell(WW + "werewolf_sprite_a.png", 176, 39)
	var db := _cell(WW + "werewolf_sprite_d.png", 176, 39)
	assert_bool(ab == db).override_failure_message("WW-D's back idle cell is still WW-A's").is_false()


func test_ww_d_recipe_pins_the_front_and_a_driven_back() -> void:
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WW + "werewolf.json"))
	var v: Dictionary = j["variants"]
	var r: Dictionary = v["WW-D"]["recipe"]
	assert_str(str(r.get("stills", ""))).is_equal("wwd")
	assert_str(str(r.get("art_prompt", ""))).is_equal(str(v["WW-A"]["recipe"]["art_prompt"]))
	assert_str(str(r.get("pose_front", ""))).is_equal("orc_walk_wolf")
	assert_str(str(r.get("pose", ""))).is_equal("orc_walk_wolf_b88")
	assert_str(str(r.get("back_hint", ""))).contains("hunched")
	assert_str(str(v["WW-D"].get("note", ""))).is_not_empty()
	# the scaled driver is on disk, back view only (the front keeps the shared driver)
	var drv := ProjectSettings.globalize_path("res://").path_join("../tools/dl/drivers/orc_walk_wolf_b88")
	assert_bool(DirAccess.dir_exists_absolute(drv.path_join("back"))).is_true()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(drv.path_join("back/poses.json")))
	assert_float(float((meta.get("scaled", {}) as Dictionary).get("factor", 0.0))).is_equal_approx(0.88, 0.001)


func test_solenne_sol_e_resolves_as_a_fifth_look() -> void:
	var c: CharacterDef = Registry.character("solenne")
	assert_object(c).is_not_null()
	assert_array(c.variant_codes()).is_equal(["SOL-A", "SOL-B", "SOL-C", "SOL-D", "SOL-E"])
	assert_str(c.variant).is_equal("SOL-B")   # Garry picks in the arena; B stays in play
	var e: CharacterDef = c.variant_def("SOL-E")
	assert_object(e).is_not_same(c)
	assert_str(e.look_code()).is_equal("SOL-E")
	assert_str(e.sprite_file).is_equal("solenne_sprite_e.png")
	assert_object(e.sprite).is_not_null()
	assert_int(e.strip_cols).is_equal(62)
	assert_int(int(e.fps.get("run", 0))).is_equal(36)
	assert_int(int(e.anims.get("run_s", 0))).is_equal(24)
	assert_str(c.variant_note("SOL-E")).contains("catwalk")
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOL + "solenne.json"))
	var r: Dictionary = j["variants"]["SOL-E"]["recipe"]
	assert_int(int(r.get("anim_seed", 0))).is_equal(4)
	assert_str(str(r["pose_drivers"]["side"])).is_equal("catwalk_fit")
	assert_str(str(r["pose_drivers"]["back"])).is_equal("catwalk_fit_spread")
	# the three-quarter back view walks on a wider spread (0.10): on the 0.06 one Wan planted both hands on her hips
	assert_str(str(r["pose_drivers"]["bd"])).is_equal("catwalk_fit_wide_spread")
	var drv := ProjectSettings.globalize_path("res://").path_join("../tools/dl/drivers/catwalk_fit_wide_spread")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(drv.path_join("meta.json")))
	assert_float(float((meta.get("spread", {}) as Dictionary).get("gap", 0.0))).is_equal_approx(0.10, 0.001)
	assert_bool(DirAccess.dir_exists_absolute(drv.path_join("bd"))).is_true()
	assert_str(str(r.get("pose_motion", ""))).contains("hips swaying")
	assert_str(str(r.get("pose_motion", ""))).contains("one foot placed straight in front of the other")


func test_critical_thinking_icon_is_new_and_the_old_one_is_kept() -> void:
	var img := Image.load_from_file(ICON)
	assert_object(img).is_not_null()
	assert_int(img.get_width()).is_equal(256)
	assert_int(img.get_height()).is_equal(256)
	var bk := ProjectSettings.globalize_path("res://").path_join("../tools/dl/backup/icons60/critical_thinking_icon.png")
	assert_bool(FileAccess.file_exists(bk)).override_failure_message(bk).is_true()
	var old := Image.load_from_file(bk)
	assert_object(old).is_not_null()
	assert_bool(old.get_data() == img.get_data()).override_failure_message("the icon was not repainted").is_false()
	# it is lossy in the import, like every content PNG (pass 34's rule)
	var imp := FileAccess.get_file_as_string(ICON + ".import")
	assert_str(imp).contains("compress/mode=1")
