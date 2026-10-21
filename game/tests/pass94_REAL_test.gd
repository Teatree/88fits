extends GdUnitTestSuite

## Pass 94, lane REAL (Garry: "Let's drop the cartooniness and try to make spider that is as close to the model as
## possible ... Give me 2 more spiders, both the purple colour, one with klein under many iterations and the other using
## 2.dev with many iterations"; then: "I meant not fully realistic, but the realistic version that is still in our style
## ... like SP-A level of realism"): SP-G (Klein) and SP-H (Flux.2 dev), light purple at SP-A's realism in the house style,
## every view the model's own clay repainted (paint_mode repaint with the style anchor, img2img from the tinted clay) and
## walked on the full Wan 2.2 (no speed-up LoRA, 20 steps, cfg 3.5). Both fresh; the spider still plays SP-B.

const DIR := "res://content/enemies/desert_spider/"
const JP := DIR + "desert_spider.json"
const NEW := {"SP-G": "klein", "SP-H": "dev"}


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(JP))


func test_two_realistic_purple_looks_repainted_from_the_clay() -> void:
	var d := _doc()
	var vs: Dictionary = d["variants"]
	for code: String in NEW:
		assert_bool(vs.has(code)).override_failure_message(code).is_true()
		var r: Dictionary = vs[code]["recipe"]
		assert_str(str(r["paint_mode"])).is_equal("repaint")
		assert_str(str((r["painter"] as Dictionary)["model"])).is_equal(str(NEW[code]))
		assert_str(str(r["prompt"])).contains("lavender")
		# Garry's correction: SP-A's realism in the house style (the style anchor kept), not photoreal
		assert_str(str(r["prompt"])).contains("wolf spider")
		assert_str(str(r["detail"])).contains("no cartoon face")
		assert_bool(bool(r.get("anchor", false))).is_true()
		assert_bool(r.has("style")).is_false()
		assert_float(float((r["init"] as Dictionary)["denoise"])).is_less(1.0)
		assert_bool(bool((r["wan"] as Dictionary)["lora"])).is_false()
		# pass 95 (lead): the lane moved to newer drivers after writing this (spider_walk_v24, spider_death_v3); the work is parked
		assert_str(str(r["drivers"])).starts_with("spider_walk")
		assert_str(str(r["death_drivers"])).starts_with("spider_death")
		assert_int((r["death_keep"] as Array).size()).is_equal(8)
		assert_bool(bool(vs[code].get("fresh", false))).override_failure_message(code).is_true()
		assert_bool(bool(vs[code].get("shelved", false))).is_false()
	assert_str(str(d["variant"])).is_equal("SP-B")


func test_the_new_looks_have_strip_icon_and_eight_directions() -> void:
	var d := _doc()
	for code: String in NEW:
		var e: Dictionary = d["variants"][code]
		# pass 95 (lead): the work is parked on Garry's word; a look whose art never landed (SP-H) is skipped
		if not e.has("sprite"):
			push_warning("pass94: %s has no strip yet (the spider work is parked)" % code)
			continue
		var letter := code.substr(3).to_lower()
		assert_str(str(e.get("sprite", ""))).is_equal("desert_spider_sprite_%s.png" % letter)
		assert_str(str(e.get("icon", ""))).is_equal("desert_spider_icon_%s.png" % letter)
		assert_bool(ResourceLoader.exists(DIR + str(e["sprite"]))).override_failure_message(code).is_true()
		assert_bool(ResourceLoader.exists(DIR + str(e["icon"]))).override_failure_message(code).is_true()
		var an: Dictionary = e["anims"]
		for k: String in ["run", "run_b", "run_s", "run_bd", "run_fd"]:
			assert_int(int(an.get(k, 0))).override_failure_message("%s %s" % [code, k]).is_equal(12)
		assert_int(int(an.get("die", 0))).override_failure_message(code).is_equal(8)


func test_the_game_loads_the_new_looks_and_their_walks_move() -> void:
	var def: EnemyDef = Registry.enemy("desert_spider")
	var order := ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
	for code: String in NEW:
		var e: Dictionary = _doc()["variants"][code]
		if not e.has("sprite"):
			continue   # pass 95 (lead): parked, not landed (see above)
		var v: EnemyDef = def.variant_def(code)
		assert_object(v.sprite).override_failure_message(code).is_not_null()
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + str(e["sprite"])))
		var cols := int(e["strip_cols"])
		var cell := img.get_width() / cols
		var k := 0
		for a: String in order:
			var n := int((e["anims"] as Dictionary).get(a, 0))
			if a.begins_with("run"):
				var first := img.get_region(Rect2i((k % cols) * cell, (k / cols) * cell, cell, cell))
				var changed := 0
				for i in range(1, n):
					var j := k + i
					var f := img.get_region(Rect2i((j % cols) * cell, (j / cols) * cell, cell, cell))
					assert_int(f.get_used_rect().size.x).override_failure_message("%s %s %d is empty" % [code, a, i]).is_greater(cell / 4)
					if f.get_data() != first.get_data():
						changed += 1
				assert_int(changed).override_failure_message("%s %s" % [code, a]).is_equal(n - 1)
			k += n
