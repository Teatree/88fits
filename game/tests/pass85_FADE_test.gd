extends GdUnitTestSuite

## Pass 85, lane FADE (Garry: "Redo Fadeaway art asset with the new puppet method"): a new look FAD-D made with the Puppet
## method (hero_puppet, pass 71) on FAD-C's stills: his arms-out paintings turned into a rigged 3D puppet whose stick
## figures and depth videos (tools/dl/drivers/fadeaway_puppet_run, _depth) guided the walks. It is fresh until Garry
## picks it; his played look is whatever the JSON's `variant` says (FAD-C when the pass shipped).

const JP := "res://content/characters/fadeaway/fadeaway.json"
const VIEWS := ["front", "fd", "side", "bd", "back"]


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(JP))


func test_the_puppet_look_is_in_his_json_with_its_recipe() -> void:
	var d := _doc()
	var vs: Dictionary = d["variants"]
	assert_bool(vs.has("FAD-D")).is_true()
	var e: Dictionary = vs["FAD-D"]
	var rec: Dictionary = e["recipe"]
	assert_str(str(rec["method"])).is_equal("hero_puppet")
	# the walks on the puppet's guides: every view's stick figure, the depth video where the recipe names one (fd and
	# back: on depth his jersey came out grey-purple from the side and the back diagonal, so those walk on the stick
	# figure), never the front (a depth video has no face)
	for v: String in VIEWS:
		assert_str(str(rec["pose_drivers"][v])).starts_with("fadeaway_puppet_run")
	var ctl: Dictionary = rec["ctl_drivers"]
	assert_bool(ctl.is_empty()).is_false()
	for v in ctl.keys():
		assert_str(str(ctl[v])).ends_with("_depth")
	assert_bool(ctl.has("front")).is_false()
	assert_array(rec["puppet"]["depth_views"]).contains_exactly_in_any_order(ctl.keys())
	assert_str(str(rec["run_fit"])).ends_with("silhouette.json")
	assert_bool(bool(rec["fringe_remap"])).is_true()
	assert_str(str(rec["puppet"]["source"])).is_equal("FAD-C")
	assert_str(str(rec["puppet"]["face"])).is_equal("nose")
	# FAD-C's stills, nothing painted again
	assert_str(str(rec["stills"])).is_equal("c")
	# not approved yet, never shelved
	assert_bool(bool(e.get("fresh", false))).is_true()
	assert_bool(bool(e.get("shelved", false))).is_false()
	# the played look stays one of his own (Garry picks)
	assert_str(str(d["variant"])).starts_with("FAD-")


func test_the_puppet_look_has_a_whole_strip_like_his_played_one() -> void:
	var d := _doc()
	var e: Dictionary = d["variants"]["FAD-D"]
	var played: Dictionary = d["variants"]["FAD-C"]
	assert_str(str(e["sprite"])).is_equal("fadeaway_sprite_d.png")
	assert_bool(ResourceLoader.exists("res://content/characters/fadeaway/fadeaway_sprite_d.png")).is_true()
	assert_dict(e["anims"]).is_equal(played["anims"])
	assert_int(int(e["strip_cols"])).is_equal(int(played["strip_cols"]))
	var tex: Texture2D = load("res://content/characters/fadeaway/fadeaway_sprite_d.png")
	var cells := 0
	for k in (e["anims"] as Dictionary).values():
		cells += int(k)
	var rows := int(ceil(float(cells) / float(e["strip_cols"])))
	assert_int(tex.get_width()).is_equal(int(e["strip_cols"]) * 256)
	assert_int(tex.get_height()).is_equal(rows * 256)
	# his badge and his cut-out stay FAD-C's (the walks paint neither)
	assert_bool(ResourceLoader.exists("res://content/characters/fadeaway/" + str(e["icon"]))).is_true()


func test_the_game_wears_the_puppet_look_when_named() -> void:
	var c: CharacterDef = Registry.character("fadeaway")
	assert_object(c).is_not_null()
	assert_bool(c.variant_codes().has("FAD-D")).is_true()
	var v: CharacterDef = c.variant_def("FAD-D")
	assert_str(v.look_code()).is_equal("FAD-D")
	assert_object(v.sprite).is_not_null()
	assert_int(v.strip_cols).is_equal(62)
	assert_int(int(v.anims.get("run_s", 0))).is_equal(24)
