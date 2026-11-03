extends GdUnitTestSuite

## Pass 122, lane S3LOOKS_A (Garry: "Creating coloured variants for enemies that don't have a white / or yellow (or any
## other coloured) version. You'd need to specifically [pick] ones that actually look visible on red."): three warm-set
## looks for the Blood Moon's rose-red ground, made by tools/recolour_strip.py --mode lift (artkit.lift_range) from the
## look each creature plays there, no painting: the same frames, layout, alpha and lines. The imp IMP-A (mint green) from
## its own strip (IMP-0, the imp's first looks block), the Red Goblin RG-C (bright gold) from RG-B, the Red Goblin Runt
## RR-C (pale peach-white) from RR-A. All fresh; the looks the creatures play are unchanged (lane S3APPLY sets the stage-3
## rows). The hellhound, horned toad, dust shaman, werewolf and the fire ant (ANT-G already reads) got no new look.

const E := "res://content/enemies/"
## new code -> [creature, source code, letter]
const NEW := {
	"IMP-A": ["imp", "IMP-0", "a"],
	"RG-C": ["red_goblin", "RG-B", "c"],
	"RR-C": ["red_goblin_runt", "RR-A", "c"],
}
## what each creature plays where no row names a look (its base strip)
const PLAYED := {"imp": "IMP-0", "red_goblin": "RG-A", "red_goblin_runt": "RR-A"}
## the creatures of the lane that keep their one look (judged by eye on the pass-122 ground: they read by value or by
## their own pale parts)
const LEFT_ALONE := ["hellhound", "horned_toad", "dust_shaman"]


func _doc(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(E + id + "/" + id + ".json"))


func _img(id: String, file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(E + id + "/" + file))


## The art keys the source look draws with: its own entry's, or the top level's for a base code without them.
func _source_art(id: String, code: String) -> Dictionary:
	var d := _doc(id)
	var vs: Dictionary = d.get("variants", {})
	var e: Dictionary = vs.get(code, {})
	var out := {}
	for k: String in ["anims", "strip_cols", "head", "fps"]:
		out[k] = e.get(k, d.get(k))
	out["sprite"] = str(e.get("sprite", d.get("sprite", id + "_sprite.png")))
	out["icon"] = str(e.get("icon", d.get("icon", id + "_icon.png")))
	return out


func test_the_played_looks_are_unchanged() -> void:
	for id: String in PLAYED:
		var d := _doc(id)
		assert_str(str(d["variant"])).override_failure_message(id).is_equal(str(PLAYED[id]))
		assert_str(str(d["variant_base"])).override_failure_message(id).is_equal(str(PLAYED[id]))
		var def: EnemyDef = Registry.enemy(id)
		assert_str(def.variant).override_failure_message(id).is_equal(str(PLAYED[id]))
		# the base code draws the top-level strip, as before the looks block
		assert_str(def.strip_path()).override_failure_message(id).is_equal(E + id + "/" + id + "_sprite.png")
		assert_str(def.look_strip_path(str(PLAYED[id]))).is_equal(def.strip_path())
		assert_bool(def.variant_def(str(PLAYED[id])) == def).is_true()


func test_the_imp_got_its_first_looks_block_in_the_editors_shape() -> void:
	# a creature without looks gets `<PREFIX>-0` for its top-level strip and the editor's base note (server._ensure_variants)
	var d := _doc("imp")
	var vs: Dictionary = d["variants"]
	assert_array(vs.keys()).contains_exactly_in_any_order(["IMP-0", "IMP-A"])
	assert_bool((vs["IMP-0"] as Dictionary).has("sprite")).is_false()
	assert_str(str((vs["IMP-0"] as Dictionary).get("note", ""))).contains("top-level strip")
	var def: EnemyDef = Registry.enemy("imp")
	assert_array(def.variant_codes()).contains_exactly(["IMP-0", "IMP-A"])
	# nothing else about the imp moved: its blood, its numbers and its strip layout are the file's (the .tres against the
	# JSON, never a literal: the blood is Garry's to set in the Creatures tab)
	assert_str(def.blood.to_html(false).to_upper()).is_equal(str(d["blood"]).trim_prefix("#").to_upper())
	assert_int(def.strip_cols).is_equal(int(d["strip_cols"]))
	assert_str(JSON.stringify(def.anims)).is_equal(JSON.stringify(d["anims"]))


func test_three_fresh_recolour_looks_with_strip_and_icon() -> void:
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
		assert_str(str(e.get("note", ""))).contains("Pass 122 recolour")
		for k: String in ["anims", "strip_cols", "fps", "head"]:
			assert_bool(e.has(k)).override_failure_message("%s carries %s" % [code, k]).is_true()


func test_the_same_frame_layout_as_the_source_and_the_strip_fits_its_columns() -> void:
	for code: String in NEW:
		var id: String = NEW[code][0]
		var d := _doc(id)
		var e: Dictionary = (d["variants"] as Dictionary)[code]
		var s := _source_art(id, str(NEW[code][1]))
		for k: String in ["anims", "strip_cols", "head", "fps"]:
			assert_str(JSON.stringify(e.get(k))).override_failure_message("%s %s" % [code, k]).is_equal(JSON.stringify(s[k]))
		var a := _img(id, str(e["sprite"]))
		var b := _img(id, str(s["sprite"]))
		assert_vector(Vector2(a.get_size())).override_failure_message(code).is_equal(Vector2(b.get_size()))
		assert_vector(Vector2(_img(id, str(e["icon"])).get_size())).is_equal(Vector2(_img(id, str(s["icon"])).get_size()))
		# the strip's width is its columns of frame_px cells, its height the rows those frames need
		var fp := int(d.get("frame_px", 128))
		var cols := int(e["strip_cols"])
		var frames := 0
		for n in (e["anims"] as Dictionary).values():
			frames += int(n)
		assert_int(a.get_width()).override_failure_message(code).is_equal(cols * fp)
		assert_int(a.get_height()).override_failure_message(code).is_equal(ceili(float(frames) / float(cols)) * fp)


func test_only_the_colour_moved_and_it_moved_lighter() -> void:
	# the alpha of every pixel is the source's (the same silhouettes and outline), and the figure is brighter on average
	for code: String in NEW:
		var id: String = NEW[code][0]
		var e: Dictionary = (_doc(id)["variants"] as Dictionary)[code]
		var a := _img(id, str(e["sprite"]))
		var b := _img(id, _source_art(id, str(NEW[code][1]))["sprite"])
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


func test_each_look_is_its_warm_set_colour() -> void:
	# the mean of the strip's opaque, coloured pixels: the imp green (mint), the goblin yellow (gold), the runt a pale
	# warm (peach-white); none of them red on the Blood Moon's rose-red ground
	var want := {"IMP-A": "mint", "RG-C": "gold", "RR-C": "peach"}
	for code: String in NEW:
		var id: String = NEW[code][0]
		var e: Dictionary = (_doc(id)["variants"] as Dictionary)[code]
		var a := _img(id, str(e["sprite"]))
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for y in range(0, a.get_height(), 5):
			for x in range(0, a.get_width(), 5):
				var c := a.get_pixel(x, y)
				if c.a > 0.9 and c.s > 0.2 and c.v > 0.3:
					sum += c
					n += 1
		var m := sum / float(n)
		var hue := m.h * 360.0
		match str(want[code]):
			"mint":
				assert_float(hue).override_failure_message(code).is_between(120.0, 185.0)
				assert_float(m.g).is_greater(m.r + 0.1)
			"gold":
				assert_float(hue).override_failure_message(code).is_between(35.0, 65.0)
				assert_float(m.v).is_greater(0.6)
			"peach":
				assert_float(hue).override_failure_message(code).is_between(5.0, 40.0)
				assert_float(m.s).override_failure_message(code).is_less(0.5)
				assert_float(m.v).override_failure_message(code).is_greater(0.7)


func test_the_game_loads_every_new_look() -> void:
	for code: String in NEW:
		var def: EnemyDef = Registry.enemy(str(NEW[code][0]))
		var v: EnemyDef = def.variant_def(code)
		assert_object(v).override_failure_message(code).is_not_null()
		assert_object(v.sprite).override_failure_message(code).is_not_null()
		assert_bool(v != def).override_failure_message(code).is_true()
		assert_str(v.variant_code).is_equal(code)
		assert_str(v.type_key()).is_equal(str(NEW[code][0]) + "@" + code)
		# the wave schema's way in (a row's `variant`) wears it too
		var w: EnemyDef = Registry.enemy_with(str(NEW[code][0]), code)
		assert_str(w.variant_code).is_equal(code)
		assert_str(w.strip_path()).is_equal(E + str(NEW[code][0]) + "/" + str((_doc(str(NEW[code][0]))["variants"] as Dictionary)[code]["sprite"]))


func test_the_creatures_left_alone_still_have_one_look() -> void:
	for id: String in LEFT_ALONE:
		assert_bool(_doc(id).has("variants")).override_failure_message(id).is_false()
		assert_array(Registry.enemy(id).variant_codes()).override_failure_message(id).is_empty()
	# the werewolf and the fire ant keep their looks as they were (WW-D and ANT-E in play)
	assert_str(Registry.enemy("werewolf").variant).is_equal("WW-D")
	assert_str(Registry.enemy("fire_ant").variant).is_equal("ANT-E")
	assert_bool(Registry.enemy("fire_ant").variants.has("ANT-G")).is_true()
