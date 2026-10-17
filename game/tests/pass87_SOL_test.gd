extends GdUnitTestSuite

## Pass 87, lane SOL (Garry: "Solenne - Let's try a Look using the Puppet Method, I always felt it was weird that she looks
## at us while walking to the side. Make sure to use the Cat Walk animation instead of a Run one for this. Make 2 new
## versions (trying a more precise and less precise prompts)"): two looks made with the Puppet method (hero_puppet,
## pass 71) on Mixamo's Catwalk Walking retargeted onto her own rigged 3D puppet, SOL-F on precise words and SOL-G on
## loose ones. Each painted its own side, three-quarter front and three-quarter back (her sun face looking where she
## walks); front, back, cheer, death and the front/back hurts stay her own paintings. Both are fresh until Garry picks;
## her played look is whatever the JSON's `variant` says (SOL-B when the pass shipped).

const DIR := "res://content/characters/solenne/"
const JP := DIR + "solenne.json"
const VIEWS := ["front", "fd", "side", "bd", "back"]
const LOOKS := {"SOL-F": "f", "SOL-G": "g"}


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(JP))


func test_both_puppet_looks_walk_the_catwalk_on_her_puppet() -> void:
	var d := _doc()
	var vs: Dictionary = d["variants"]
	for code: String in LOOKS.keys():
		assert_bool(vs.has(code)).override_failure_message(code).is_true()
		var e: Dictionary = vs[code]
		var rec: Dictionary = e["recipe"]
		assert_str(str(rec["method"])).is_equal("hero_puppet")
		var pp: Dictionary = rec["puppet"]
		# the catwalk, not the run (Garry's words)
		assert_str(str(pp["clip"])).is_equal("catwalk_walking.fbx")
		assert_str(str(pp["source"])).is_equal("SOL-B")
		assert_str(str(pp["stills"])).is_equal("repaint")
		assert_str(str(pp["face"])).is_equal("nose")
		for v: String in VIEWS:
			assert_str(str(rec["pose_drivers"][v])).starts_with("solenne_puppet_catwalk_walking")
		# the side on the guide whose far arm is hidden while it swings high (it came out as a hand at her neck)
		assert_str(str(rec["pose_drivers"]["side"])).ends_with("_farhide")
		# depth only where the face never shows: the side and the diagonals walk on the stick figure (its face points
		# carry the face's direction; the depth bd painted a black reflection under her feet)
		var ctl: Dictionary = rec.get("ctl_drivers", {})
		for v in ctl.keys():
			assert_str(str(ctl[v])).ends_with("_depth")
			assert_bool(v in ["back"]).override_failure_message("%s walks %s on depth" % [code, v]).is_true()
		assert_array(pp["depth_views"]).contains_exactly_in_any_order(ctl.keys())
		assert_str(str(rec["run_fit"])).ends_with("silhouette.json")
		assert_bool(bool(rec["fringe_remap"])).is_true()
		# her own paintings for the views where the face turns; her front and back stay hers
		assert_str(str(rec["stills"])).is_equal(LOOKS[code])
		var sk: Dictionary = rec["still_keys"]
		assert_str(str(sk["front"])).is_equal("solenne_front")
		assert_str(str(sk["back"])).is_equal("solenne_back")
		assert_bool(sk.has("side")).is_false()
		assert_bool(sk.has("fd")).is_false()
		# not approved yet, never shelved
		assert_bool(bool(e.get("fresh", false))).is_true()
		assert_bool(bool(e.get("shelved", false))).is_false()
	# her played look stays one of hers (Garry picks)
	assert_str(str(d["variant"])).starts_with("SOL-")


func test_the_precise_words_say_more_than_the_loose_ones() -> void:
	var vs: Dictionary = _doc()["variants"]
	var f: Dictionary = vs["SOL-F"]["recipe"]
	var g: Dictionary = vs["SOL-G"]["recipe"]
	var lf := 0
	var lg := 0
	for k in ["pose_hint", "side_hint", "back_hint", "anim_hint", "pose_motion", "anim_negative"]:
		lf += str(f.get(k, "")).length()
		lg += str(g.get(k, "")).length()
	assert_int(lf).is_greater(lg * 5)
	# both ask for the face to look where she walks; both walk the catwalk
	assert_str(str(f["anim_hint"])).contains("looks the way she walks")
	assert_str(str(g["anim_hint"])).contains("looking where she walks")
	assert_str(str(f["pose_motion"])).contains("catwalk")
	assert_str(str(g["pose_motion"])).contains("catwalk")
	# the two looks roll their own seeds
	assert_int(int(f["seed_offset"])).is_not_equal(int(g["seed_offset"]))


func test_each_puppet_look_has_a_whole_strip_like_her_played_one() -> void:
	var d := _doc()
	var played: Dictionary = d["variants"]["SOL-B"]
	for code: String in LOOKS.keys():
		var e: Dictionary = d["variants"][code]
		var file := "solenne_sprite_%s.png" % LOOKS[code]
		assert_str(str(e["sprite"])).is_equal(file)
		assert_bool(ResourceLoader.exists(DIR + file)).override_failure_message(file).is_true()
		assert_dict(e["anims"]).is_equal(played["anims"])
		assert_int(int(e["strip_cols"])).is_equal(int(played["strip_cols"]))
		var tex: Texture2D = load(DIR + file)
		var cells := 0
		for k in (e["anims"] as Dictionary).values():
			cells += int(k)
		var rows := int(ceil(float(cells) / float(e["strip_cols"])))
		assert_int(tex.get_width()).is_equal(int(e["strip_cols"]) * 256)
		assert_int(tex.get_height()).is_equal(rows * 256)


func test_the_game_wears_each_puppet_look_when_named() -> void:
	var c: CharacterDef = Registry.character("solenne")
	assert_object(c).is_not_null()
	for code: String in LOOKS.keys():
		assert_bool(c.variant_codes().has(code)).override_failure_message(code).is_true()
		var v: CharacterDef = c.variant_def(code)
		assert_str(v.look_code()).is_equal(code)
		assert_object(v.sprite).is_not_null()
		assert_int(v.strip_cols).is_equal(62)
		assert_int(int(v.anims.get("run_s", 0))).is_equal(24)
		assert_int(int(v.anims.get("run_fd", 0))).is_equal(24)
		# her badge stays her own
		assert_object(v.icon).is_not_null()
