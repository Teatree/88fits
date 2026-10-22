extends GdUnitTestSuite

## Pass 93, lane LEGS (Garry: "give me an instruction on how to improve on the Desert Spider SP-B version. I basically want
## 2 more versions which fix the leg movement (currently most legs aren't moving, and the ones that are moving are moving
## in the wrong direction). And I want the colour of the spider to be a light purple or light blue (1 each variant)"):
## the made walk's legs turned round their hips like clock hands (blender_gait step=swing), so the front and back legs
## swept their feet sideways and the middle legs' fore-aft step was foreshortened away in the front and back views; the
## fixed walk spider_walk_v2 (step=track: every foot along the body) carries SP-E (light purple) and SP-F (light blue),
## SP-B's recipe with only the colour words changed. The spider still plays SP-B.

const DIR := "res://content/enemies/desert_spider/"
const JP := DIR + "desert_spider.json"
const NEW := {"SP-E": "lavender", "SP-F": "sky-blue"}


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(JP))


func test_two_new_colours_of_sp_b_on_the_fixed_walk() -> void:
	var d := _doc()
	var vs: Dictionary = d["variants"]
	var b: Dictionary = vs["SP-B"]["recipe"]
	for code: String in NEW:
		assert_bool(vs.has(code)).override_failure_message(code).is_true()
		var r: Dictionary = vs[code]["recipe"]
		assert_str(str(r["drivers"])).is_equal("spider_walk_v2")
		assert_str(str(r["death_drivers"])).is_equal("spider_death")
		assert_str(str(r["prompt"])).contains(str(NEW[code]))
		assert_str(str(r["prompt"])).contains("grumpy frown")
		assert_str(str(r["prompt"])).not_contains("rust-orange")
		# SP-B's design: the same anatomy and view words, eight legs counted per side
		assert_str(str(r["anatomy"])).is_equal(str(b["anatomy"]))
		assert_str(JSON.stringify(r["words"])).is_equal(JSON.stringify(b["words"]))
		assert_int(int(r["directions"])).is_equal(8)
		assert_int((r["death_keep"] as Array).size()).is_equal(8)
		# fresh until Garry approves; the spider keeps playing SP-B
		assert_bool(bool(vs[code].get("fresh", false))).override_failure_message(code).is_true()
		assert_bool(bool(vs[code].get("shelved", false))).is_false()
	# Garry picks the played look in the editor (SP-B in pass 93/94, SP-G since 2026-10-22): any of its own looks
	assert_bool((d["variants"] as Dictionary).has(str(d["variant"]))).is_true()


func test_the_new_looks_have_strip_icon_and_eight_directions() -> void:
	var d := _doc()
	for code: String in NEW:
		var e: Dictionary = d["variants"][code]
		var letter := code.substr(3).to_lower()
		assert_str(str(e.get("sprite", ""))).is_equal("desert_spider_sprite_%s.png" % letter)
		assert_str(str(e.get("icon", ""))).is_equal("desert_spider_icon_%s.png" % letter)
		assert_bool(ResourceLoader.exists(DIR + str(e["sprite"]))).override_failure_message(code).is_true()
		assert_bool(ResourceLoader.exists(DIR + str(e["icon"]))).override_failure_message(code).is_true()
		var an: Dictionary = e["anims"]
		for k: String in ["run", "run_b", "run_s", "run_bd", "run_fd"]:
			assert_int(int(an.get(k, 0))).override_failure_message("%s %s" % [code, k]).is_equal(12)
		assert_int(int(an.get("die", 0))).override_failure_message(code).is_equal(8)


func test_the_game_plays_the_new_looks_and_their_walks_move() -> void:
	var def: EnemyDef = Registry.enemy("desert_spider")
	var order := ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
	for code: String in NEW:
		var v: EnemyDef = def.variant_def(code)
		assert_object(v.sprite).override_failure_message(code).is_not_null()
		var e: Dictionary = _doc()["variants"][code]
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + str(e["sprite"])))
		var cols := int(e["strip_cols"])
		var cell := img.get_width() / cols
		# every run frame holds a figure, and the side walk's frames differ (the legs step: not a still)
		var k := 0
		for a: String in order:
			var n := int((e["anims"] as Dictionary).get(a, 0))
			if a == "run_s":
				var first := img.get_region(Rect2i((k % cols) * cell, (k / cols) * cell, cell, cell))
				var changed := 0
				for i in range(1, n):
					var j := k + i
					var f := img.get_region(Rect2i((j % cols) * cell, (j / cols) * cell, cell, cell))
					assert_int(f.get_used_rect().size.x).override_failure_message("%s run_s %d is empty" % [code, i]).is_greater(cell / 4)
					if f.get_data() != first.get_data():
						changed += 1
				assert_int(changed).override_failure_message(code).is_equal(n - 1)
			k += n
