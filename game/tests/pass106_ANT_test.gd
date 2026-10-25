extends GdUnitTestSuite

## Pass 106, lane ANT (Garry: "New Enemy Look for Fire Ant - Let's test out the new method with use of Gemini and 3d
## model. I added the a-heavily-armored-beetle-3d-model-free as a 3d reference for the look of a fire ant. This should be
## 8 sided and since it's missing a walk animation the animation will have to be created ... Make 2 versions"): the model
## had no rig, so tools/blender_autorig_legs.py rigged it (six legs found by shape, two elbowed antennae added), a made
## walk (armant_walk_v3, step=track) and a dead-on-its-back death (armant_death_v2); two looks: ANT-E on Klein (bright
## red-orange) and ANT-F on Flux.2 dev (a darker crimson soldier), both fresh. The ant keeps playing ANT-A.

const DIR := "res://content/enemies/fire_ant/"
const JP := DIR + "fire_ant.json"
const NEW := {"ANT-E": "klein", "ANT-F": "dev"}


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(JP))


func test_the_ant_keeps_playing_its_look() -> void:
	var d := _doc()
	assert_str(str(d["variant"])).is_equal("ANT-A")
	assert_str(Registry.enemy("fire_ant").variant).is_equal("ANT-A")


func test_two_armoured_looks_from_the_beetle_model() -> void:
	var vs: Dictionary = _doc()["variants"]
	for code: String in NEW:
		assert_bool(vs.has(code)).override_failure_message(code).is_true()
		var e: Dictionary = vs[code]
		var r: Dictionary = e["recipe"]
		assert_str(str(r["method"])).is_equal("creature_ctl")
		assert_str(str(r["drivers"])).starts_with("armant_walk")
		assert_str(str(r["death_drivers"])).starts_with("armant_death")
		assert_str(str((r["painter"] as Dictionary)["model"])).is_equal(str(NEW[code]))
		assert_str(str(r["prompt"])).contains("fire ant")
		assert_str(str(r["anatomy"])).contains("exactly six legs")
		assert_int(int(r["directions"])).is_equal(8)
		assert_bool(bool(e.get("fresh", false))).override_failure_message(code).is_true()
		assert_bool(bool(e.get("shelved", false))).is_false()


func test_the_new_looks_have_strip_icon_and_eight_directions() -> void:
	var d := _doc()
	for code: String in NEW:
		var e: Dictionary = d["variants"][code]
		assert_bool(e.has("sprite")).override_failure_message("%s has no strip" % code).is_true()
		var letter := code.substr(4).to_lower()
		assert_str(str(e.get("sprite", ""))).is_equal("fire_ant_sprite_%s.png" % letter)
		assert_str(str(e.get("icon", ""))).is_equal("fire_ant_icon_%s.png" % letter)
		assert_bool(ResourceLoader.exists(DIR + str(e["sprite"]))).override_failure_message(code).is_true()
		assert_bool(ResourceLoader.exists(DIR + str(e["icon"]))).override_failure_message(code).is_true()
		var an: Dictionary = e["anims"]
		for k: String in ["run", "run_b", "run_s", "run_bd", "run_fd"]:
			assert_int(int(an.get(k, 0))).override_failure_message("%s %s" % [code, k]).is_equal(12)
		assert_int(int(an.get("die", 0))).override_failure_message(code).is_equal(8)


func test_the_game_loads_the_new_looks_and_their_walks_move() -> void:
	var def: EnemyDef = Registry.enemy("fire_ant")
	var order := ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]
	for code: String in NEW:
		var e: Dictionary = _doc()["variants"][code]
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
	# the played look is untouched by the new ones
	assert_str(str(_doc()["variant"])).is_equal("ANT-A")
