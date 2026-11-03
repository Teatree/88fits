extends GdUnitTestSuite

## Pass 122, lane S3LOOKS_B (Garry, 2026-11-03: "Creating coloured variants for enemies that don't have a white / or
## yellow (or any other coloured) version. You'd need to specifically [pick] ones that actually look visible on red."):
## four looks for the Blood Moon's lighter red ground, each a frame-by-frame lift of the look its creature plays in
## stage 3 (tools/recolour_strip.py --mode lift, artkit.lift_range): the same frames, layout and lines, one material
## moved to a cool colour. All fresh; the looks the creatures play (`variant`) are unchanged (lane S3APPLY names the
## stage-3 rows' looks in the map). The giant's, the mummy's and the dwarf's hit frames (a white-washed flash of the
## material whose saturation falls under the strip pass's --min-sat) take a second pass of their own on that frame alone
## (`--cells 18`, the tool's pass 122 option); the knight's hit frame keeps its saturation, so the one pass lifts it with
## the rest. Every pass is a plain tools/recolour_strip.py argument string, applied in turn to the strip and the icon.

const E := "res://content/enemies/"
## new code -> [creature, source code, letter]
const NEW := {
	"HG-E": ["hammer_giant", "HG-C", "e"],
	"KN-F": ["skeleton_knight", "KN-E", "f"],
	"DM-J": ["dust_mummy", "DM-G", "j"],
	"BD-B": ["buckshot_dwarf", "BD-A", "b"],
}
## the look each creature plays (its `variant`), as before this pass
const PLAYED := {"hammer_giant": "HG-A", "skeleton_knight": "KN-A", "dust_mummy": "DM-G", "buckshot_dwarf": "BD-A"}
## the looks whose hit frame took its own pass (`--cells <hit frame>`)
const HIT_LIFTED := ["HG-E", "DM-J", "BD-B"]
## the creatures' strips are packed in this fixed order (EnemyDef.frame_offset)
const ORDER := ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd", "idle_l", "run_l", "attack_l", "hit_l", "run_bl", "idle_bl"]


func _doc(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(E + id + "/" + id + ".json"))


func _img(id: String, file: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(E + id + "/" + file))


func _frames(anims: Dictionary) -> int:
	var n := 0
	for k: String in ORDER:
		n += int(anims.get(k, 0))
	return n


func _offset(anims: Dictionary, anim: String) -> int:
	var n := 0
	for k: String in ORDER:
		if k == anim:
			return n
		n += int(anims.get(k, 0))
	return n


func test_the_played_looks_are_unchanged() -> void:
	for id: String in PLAYED:
		assert_str(str(_doc(id)["variant"])).override_failure_message(id).is_equal(str(PLAYED[id]))
		assert_str(Registry.enemy(id).variant).override_failure_message(id).is_equal(str(PLAYED[id]))


func test_four_fresh_recolour_looks_with_strip_and_icon() -> void:
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
		var passes: Array = r["recolour_passes"]
		for p: String in passes:
			# every pass is a plain tools/recolour_strip.py argument string: nothing a tracked tool cannot run
			assert_str(p).override_failure_message(code).starts_with("--")
			assert_str(p).override_failure_message(code).contains("--mode lift")
		assert_bool(str(passes[0]).contains("--cells")).override_failure_message(code + ": the strip pass runs on every frame").is_false()
		if code in HIT_LIFTED:
			assert_int(passes.size()).override_failure_message(code).is_equal(2)
			var hit := _offset(e.get("anims", _doc(id)["anims"]), "hit")
			assert_str(str(passes[1])).override_failure_message(code + ": the second pass on the hit frame alone").ends_with(" --cells %d" % hit)
		else:
			assert_int(passes.size()).override_failure_message(code).is_equal(1)
		assert_str(str(e.get("note", ""))).contains("Pass 122 recolour")


func test_the_same_frame_layout_as_the_source() -> void:
	for code: String in NEW:
		var id: String = NEW[code][0]
		var vs: Dictionary = _doc(id)["variants"]
		var e: Dictionary = vs[code]
		var s: Dictionary = vs[str(NEW[code][1])]
		for k: String in ["anims", "strip_cols", "head", "fps", "shadow", "attack_views", "attack_throw", "front_faces", "back_faces"]:
			assert_str(JSON.stringify(e.get(k))).override_failure_message("%s %s" % [code, k]).is_equal(JSON.stringify(s.get(k)))
		var a := _img(id, str(e["sprite"]))
		var b := _img(id, str(s["sprite"]))
		assert_vector(Vector2(a.get_size())).override_failure_message(code).is_equal(Vector2(b.get_size()))
		assert_vector(Vector2(_img(id, str(e["icon"])).get_size())).is_equal(Vector2(_img(id, str(s["icon"])).get_size()))


func test_the_strip_is_strip_cols_wide_and_holds_every_frame() -> void:
	for code: String in NEW:
		var id: String = NEW[code][0]
		var d := _doc(id)
		var e: Dictionary = d["variants"][code]
		var px := int(d.get("frame_px", 128))
		var cols := int(e.get("strip_cols", d.get("strip_cols", 0)))
		var frames := _frames(e.get("anims", d["anims"]))
		assert_int(cols).override_failure_message(code).is_greater(0)
		var a := _img(id, str(e["sprite"]))
		assert_int(a.get_width()).override_failure_message(code + " width").is_equal(cols * px)
		assert_int(a.get_height()).override_failure_message(code + " height").is_equal(ceili(float(frames) / float(cols)) * px)
		assert_int(frames).override_failure_message(code).is_less_equal(cols * (a.get_height() / px))


func test_only_the_colour_moved_and_it_moved_lighter() -> void:
	# the alpha of every pixel is the source's (the same silhouettes and outline), and the figure is brighter on average
	for code: String in NEW:
		var id: String = NEW[code][0]
		var vs: Dictionary = _doc(id)["variants"]
		for kind: String in ["sprite", "icon"]:
			var a := _img(id, str(vs[code][kind]))
			var b := _img(id, str(vs[str(NEW[code][1])][kind]))
			var diff_alpha := 0
			var la := 0.0
			var lb := 0.0
			var n := 0
			var step := 7 if kind == "sprite" else 2
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
			assert_int(diff_alpha).override_failure_message("%s %s" % [code, kind]).is_equal(0)
			assert_float(la / n).override_failure_message("%s %s" % [code, kind]).is_greater(lb / n + 0.02)


func test_the_hit_frame_is_lifted_too() -> void:
	# the giant's red flash, the mummy's khaki flash and the dwarf's pink poncho flash moved to the look's cool colour:
	# a fair share of the hit cell's figure changed (the dwarf's poncho is an eighth of him), and what changed went blue
	# over red (a flash that still wore the source colour would flicker back to it on every hit)
	for code: String in HIT_LIFTED:
		var id: String = NEW[code][0]
		var d := _doc(id)
		var e: Dictionary = d["variants"][code]
		var s: Dictionary = d["variants"][str(NEW[code][1])]
		var px := int(d.get("frame_px", 128))
		var cols := int(e.get("strip_cols", d.get("strip_cols", 0)))
		var k := _offset(e["anims"], "hit")
		var a := _img(id, str(e["sprite"]))
		var b := _img(id, str(s["sprite"]))
		var x0 := (k % cols) * px
		var y0 := (k / cols) * px
		var da := 0.0
		var db := 0.0
		var n := 0
		var changed := 0
		for y in range(y0, y0 + px, 2):
			for x in range(x0, x0 + px, 2):
				var cb := b.get_pixel(x, y)
				if cb.a > 0.5:
					n += 1
					var ca := a.get_pixel(x, y)
					if not ca.is_equal_approx(cb):
						changed += 1
						da += ca.b - ca.r
						db += cb.b - cb.r
		assert_int(n).override_failure_message(code).is_greater(0)
		assert_float(float(changed) / float(n)).override_failure_message(code + " hit frame: the share of the figure lifted").is_greater(0.05)
		assert_float(da / changed).override_failure_message(code + " hit frame: the lifted pixels' blue over red").is_greater(db / changed + 0.1)


func test_the_game_loads_every_new_look() -> void:
	for code: String in NEW:
		var def: EnemyDef = Registry.enemy(str(NEW[code][0]))
		var v: EnemyDef = def.variant_def(code)
		assert_object(v).override_failure_message(code).is_not_null()
		assert_object(v.sprite).override_failure_message(code).is_not_null()
		assert_bool(v != def).override_failure_message(code).is_true()
		assert_str(v.variant_code).is_equal(code)
		assert_bool(v.has_left_sets()).override_failure_message(code).is_false()
		assert_bool(code in def.variant_codes()).override_failure_message(code + " in the arena's chips").is_true()
		assert_bool(def.variant_shelved(code)).is_false()
