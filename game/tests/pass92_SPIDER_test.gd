extends GdUnitTestSuite

## Pass 92, lane SPIDER (Garry: "Create me another enemy using the same method as we used for the scorpion. This enemy
## will be a spider ... 4 Look Variants of the Spider, they will differ in cartooniness ... The resulting death state of
## the spider should be that of a spider lying on his back with his legs curled up"): the Desert Spider, walked on his
## 3D spider made eight-legged (tools/blender_limb_clone.py) with a made walk and a made death on its back
## (tools/blender_gait.py through blender_depth_drivers.py mode=gait / flip_curl), four looks SP-A..SP-D from near-real
## to very cartoony, painted and walked by gen_ctl. No map brings it yet: Garry places it.

const DIR := "res://content/enemies/desert_spider/"
const JP := DIR + "desert_spider.json"
const LOOKS := ["SP-A", "SP-B", "SP-C", "SP-D"]
const ORDER := ["idle", "run", "attack", "hit", "die", "run_b", "idle_b", "run_s", "idle_s", "run_bd", "idle_bd", "run_fd", "idle_fd"]


func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(JP))


func test_the_spider_loads_and_no_map_brings_it_yet() -> void:
	var d: EnemyDef = Registry.enemy("desert_spider")
	assert_object(d).is_not_null()
	assert_str(d.doc).is_not_empty()
	assert_float(d.knockback).is_greater(0.0)
	assert_float(d.hp).is_greater(0.0)
	assert_bool(d.blood.a > 0.0).is_true()
	# Garry places it: no roster row, wave or event of any map names it
	for id in DirAccess.get_directories_at("res://content/maps"):
		var path := "res://content/maps/%s/%s.json" % [id, id]
		if FileAccess.file_exists(path):
			assert_bool(FileAccess.get_file_as_string(path).contains("desert_spider")).override_failure_message(id).is_false()


func test_four_looks_on_the_same_drivers_from_least_to_most_cartoony() -> void:
	var d := _doc()
	var vs: Dictionary = d["variants"]
	assert_array(vs.keys()).contains_exactly_in_any_order(LOOKS)
	var words := []
	for code: String in LOOKS:
		var r: Dictionary = vs[code]["recipe"]
		# the same 3D spider; the cartoon looks walk and die on its clay given their proportions (spider_walk_c, _d)
		assert_str(str(r["drivers"])).starts_with("spider_walk")
		assert_str(str(r["death_drivers"])).starts_with("spider_death")
		assert_str(str(r["drivers"]).trim_prefix("spider_walk")).is_equal(str(r["death_drivers"]).trim_prefix("spider_death"))
		assert_str(str(r["anatomy"])).contains("exactly eight legs, four on each side")
		assert_int(int(r["directions"])).is_equal(8)
		var keep: Array = r["death_keep"]
		assert_int(keep.size()).is_equal(8)
		# the last kept frame is the held end of the death clip: the spider on its back, legs curled
		assert_int(int(keep[-1])).is_equal(24)
		words.append(str(r["prompt"]))
	assert_str(words[0]).contains("wolf spider")
	assert_str(words[3]).contains("very exaggerated")
	# the played look is one of them (a creature with looks plays one), all four still fresh for Garry to approve
	assert_bool(vs.has(str(d["variant"]))).is_true()
	for code: String in LOOKS:
		assert_bool(bool(vs[code].get("fresh", false))).override_failure_message(code).is_true()
		assert_bool(bool(vs[code].get("shelved", false))).is_false()


func test_every_look_has_its_strip_icon_and_eight_directions() -> void:
	var d := _doc()
	for code: String in LOOKS:
		var e: Dictionary = d["variants"][code]
		var letter := code.substr(3).to_lower()
		assert_str(str(e.get("sprite", ""))).is_equal("desert_spider_sprite_%s.png" % letter)
		assert_bool(ResourceLoader.exists(DIR + str(e["sprite"]))).override_failure_message(code).is_true()
		assert_bool(ResourceLoader.exists(DIR + str(e["icon"]))).override_failure_message(code).is_true()
		var an: Dictionary = e["anims"]
		for k: String in ["run", "run_b", "run_s", "run_bd", "run_fd"]:
			assert_int(int(an.get(k, 0))).override_failure_message("%s %s" % [code, k]).is_equal(12)
		assert_int(int(an.get("die", 0))).override_failure_message(code).is_equal(8)


func test_the_game_plays_each_look_and_its_death_frames_are_drawn() -> void:
	var def: EnemyDef = Registry.enemy("desert_spider")
	for code: String in LOOKS:
		var v: EnemyDef = def.variant_def(code)
		assert_object(v.sprite).override_failure_message(code).is_not_null()
		var e: Dictionary = _doc()["variants"][code]
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + str(e["sprite"])))
		assert_object(img).is_not_null()
		var cols := int(e["strip_cols"])
		var cell := img.get_width() / cols
		# every die frame holds a figure, the last one (the dead pose) too
		var k := 0
		for a: String in ORDER:
			var n := int((e["anims"] as Dictionary).get(a, 0))
			if a == "die":
				for i in range(n):
					var j := k + i
					var f := img.get_region(Rect2i((j % cols) * cell, (j / cols) * cell, cell, cell))
					assert_int(f.get_used_rect().size.x).override_failure_message("%s die %d is empty" % [code, i]).is_greater(cell / 6)
				break
			k += n
