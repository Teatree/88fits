extends GdUnitTestSuite

## Pass 107, lane RECOLOUR (Garry: "Let's make Recolour variants of the following enemies ... Bull Beetle - white shell,
## everything else as is. Fire Ant - brighter somehow, maybe yellow or white-pink variant. Scorpion - also white or
## yellow. Each gets 2 looks"): six looks made by tools/recolour_strip.py --mode lift (artkit.lift_range) from each
## creature's played look, no painting: the same frames, layout and lines. All fresh; the played looks are unchanged
## (the lead sets the Stage 2 rows' looks in the map).

const E := "res://content/enemies/"
## new code -> [creature, source code, letter]
const NEW := {
	"BB-E": ["bull_beetle", "BB-C", "e"],
	"BB-F": ["bull_beetle", "BB-C", "f"],
	"ANT-G": ["fire_ant", "ANT-E", "g"],
	"ANT-H": ["fire_ant", "ANT-E", "h"],
	"LS-D": ["lesser_scorpion", "LS-B", "d"],
	"LS-E": ["lesser_scorpion", "LS-B", "e"],
}
const PLAYED := {"bull_beetle": "BB-C", "fire_ant": "ANT-E", "lesser_scorpion": "LS-B"}


func _doc(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(E + id + "/" + id + ".json"))


func _img(id: String, file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(E + id + "/" + file))


func test_the_played_looks_are_unchanged() -> void:
	for id: String in PLAYED:
		assert_str(str(_doc(id)["variant"])).override_failure_message(id).is_equal(str(PLAYED[id]))
		assert_str(Registry.enemy(id).variant).override_failure_message(id).is_equal(str(PLAYED[id]))


func test_six_fresh_recolour_looks_with_strip_and_icon() -> void:
	for code: String in NEW:
		var id: String = NEW[code][0]
		var vs: Dictionary = _doc(id)["variants"]
		assert_bool(vs.has(code)).override_failure_message(code).is_true()
		var e: Dictionary = vs[code]
		var letter: String = NEW[code][2]
		assert_bool(bool(e.get("fresh", false))).override_failure_message(code).is_true()
		assert_bool(bool(e.get("shelved", false))).is_false()
		assert_str(str(e.get("sprite", ""))).is_equal("%s_sprite_%s.png" % [id, letter])
		assert_str(str(e.get("icon", ""))).is_equal("%s_icon_%s.png" % [id, letter])
		assert_bool(ResourceLoader.exists(E + id + "/" + str(e["sprite"]))).override_failure_message(code).is_true()
		assert_bool(ResourceLoader.exists(E + id + "/" + str(e["icon"]))).override_failure_message(code).is_true()
		var r: Dictionary = e["recipe"]
		assert_str(str(r["recolour_of"])).is_equal(str(NEW[code][1]))
		assert_str(str((r["recolour_passes"] as Array)[0])).contains("--mode lift")
		assert_str(str(e.get("note", ""))).contains("Pass 107 recolour")


func test_the_same_frame_layout_as_the_source() -> void:
	for code: String in NEW:
		var id: String = NEW[code][0]
		var vs: Dictionary = _doc(id)["variants"]
		var e: Dictionary = vs[code]
		var s: Dictionary = vs[str(NEW[code][1])]
		for k: String in ["anims", "strip_cols", "head", "fps", "shadow"]:
			assert_str(JSON.stringify(e.get(k))).override_failure_message("%s %s" % [code, k]).is_equal(JSON.stringify(s.get(k)))
		var a := _img(id, str(e["sprite"]))
		var b := _img(id, str(s["sprite"]))
		assert_vector(Vector2(a.get_size())).override_failure_message(code).is_equal(Vector2(b.get_size()))
		assert_vector(Vector2(_img(id, str(e["icon"])).get_size())).is_equal(Vector2(_img(id, str(s["icon"])).get_size()))


func test_only_the_colour_moved_and_it_moved_lighter() -> void:
	# the alpha of every pixel is the source's (the same silhouettes and outline), and the figure is brighter on average
	for code: String in NEW:
		var id: String = NEW[code][0]
		var vs: Dictionary = _doc(id)["variants"]
		var a := _img(id, str(vs[code]["sprite"]))
		var b := _img(id, str(vs[str(NEW[code][1])]["sprite"]))
		var diff_alpha := 0
		var la := 0.0
		var lb := 0.0
		var n := 0
		var step := 7
		for y in range(0, a.get_height(), step):
			for x in range(0, a.get_width(), step):
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.a - cb.a) > 0.01:
					diff_alpha += 1
				if cb.a > 0.5:
					la += ca.get_luminance()
					lb += cb.get_luminance()
					n += 1
		assert_int(diff_alpha).override_failure_message(code).is_equal(0)
		assert_float(la / n).override_failure_message(code).is_greater(lb / n + 0.05)


func test_the_game_loads_every_new_look() -> void:
	for code: String in NEW:
		var def: EnemyDef = Registry.enemy(str(NEW[code][0]))
		var v: EnemyDef = def.variant_def(code)
		assert_object(v).override_failure_message(code).is_not_null()
		assert_object(v.sprite).override_failure_message(code).is_not_null()
		assert_bool(v != def).override_failure_message(code).is_true()
		assert_str(v.variant_code).is_equal(code)
