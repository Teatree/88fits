extends GdUnitTestSuite

## Pass 87, lane MUMMY: four new Dust Mummy looks from Garry's mummy.png (DM-F serious shuffle, DM-G serious lurch, DM-H
## goofy bounce, DM-I goofy limp), front and back on arm-up pose drivers (tools/dl/drivers/mummy_*_f for the front view,
## mummy_*_b for the back), all fresh; DM-0 stays the look the game plays.

const NEW := ["DM-F", "DM-G", "DM-H", "DM-I"]
const ORDER := ["idle", "run", "attack", "hit", "die", "run_b", "idle_b"]


func _json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/dust_mummy/dust_mummy.json"))


## Re-pinned in pass 88 (Garry: "Let's go with DM-G"): DM-G plays, approved (no longer fresh); the other three stay fresh.
func test_the_four_looks_are_fresh_and_dm0_still_plays() -> void:
	var j := _json()
	assert_str(str(j.get("variant", ""))).is_equal("DM-G")
	var e: EnemyDef = Registry.enemy("dust_mummy")
	assert_str(e.variant).is_equal("DM-G")
	var codes: Array = e.variant_codes()
	for code in NEW:
		assert_bool(codes.has(code)).override_failure_message(code + " is not a look").is_true()
		var v: Dictionary = j["variants"][code]
		assert_bool(bool(v.get("fresh", false))).override_failure_message(code + " freshness").is_equal(code != "DM-G")
		assert_bool(v.get("shelved", false)).is_false()


func test_every_new_look_has_its_strip_icon_and_counts() -> void:
	var j := _json()
	var cell := int(j.get("frame_px", 176))
	for code in NEW:
		var v: Dictionary = j["variants"][code]
		var letter: String = code.split("-")[1].to_lower()
		assert_str(str(v.get("sprite", ""))).is_equal("dust_mummy_sprite_%s.png" % letter)
		assert_bool(ResourceLoader.exists("res://content/enemies/dust_mummy/" + str(v["sprite"]))).override_failure_message(code + " strip").is_true()
		assert_bool(ResourceLoader.exists("res://content/enemies/dust_mummy/" + str(v["icon"]))).override_failure_message(code + " icon").is_true()
		var anims: Dictionary = v["anims"]
		# two directions: a 12-frame walk from the front and from behind, a death
		assert_int(int(anims.get("run", 0))).is_equal(12)
		assert_int(int(anims.get("run_b", 0))).is_equal(12)
		assert_int(int(anims.get("die", 0))).is_greater(3)
		assert_bool(anims.has("run_s")).is_false()
		var n := 0
		for a in ORDER:
			n += int(anims.get(a, 0))
		var cols := int(v["strip_cols"])
		var tex: Texture2D = load("res://content/enemies/dust_mummy/" + str(v["sprite"]))
		assert_int(tex.get_width()).is_equal(cols * cell)
		assert_int(tex.get_height()).is_equal(int(ceil(float(n) / cols)) * cell)
		assert_float(float(v["fps"]["run"])).is_equal(float(v["recipe"]["run_fps"]))


func test_every_new_look_walks_on_its_arm_up_drivers() -> void:
	var j := _json()
	var walks := {}
	for code in NEW:
		var r: Dictionary = j["variants"][code]["recipe"]
		var pose := str(r.get("pose", ""))
		var front := str(r.get("pose_front", ""))
		assert_bool(pose.begins_with("mummy_") and pose.ends_with("_b")).override_failure_message(code + " " + pose).is_true()
		assert_str(front).is_equal(pose.trim_suffix("_b") + "_f")
		assert_str(str(r.get("stand", ""))).is_equal("still")
		assert_str(str(r.get("stills", ""))).is_equal("dm" + code.split("-")[1].to_lower())
		walks[pose] = true
	# four walks, one each
	assert_int(walks.size()).is_equal(4)


func test_a_look_wears_its_art_through_variant_def() -> void:
	var e: EnemyDef = Registry.enemy("dust_mummy")
	for code in NEW:
		var v: EnemyDef = e.variant_def(code)
		assert_int(v.frames_of("run")).is_equal(12)
		# re-pinned in pass 88: the played look (DM-G since pass 88) is the plain type, keyed by the id alone
		if code == e.variant:
			assert_str(v.type_key()).is_equal("dust_mummy")
			continue
		assert_str(v.variant_code).is_equal(code)
		assert_str(v.type_key()).is_equal("dust_mummy@" + code)
