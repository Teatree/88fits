extends GdUnitTestSuite

## Pass 126 (lane BESTIARY; Garry: "Come up with 3 fodder enemies that would fit this level and implement them already"): the
## Dust Bowl's Straw Man, Carrion Crow and Dust Bunny are whole creatures the compiled crowd walks: each loads, is a plain
## walker (chase or flock, no charge), carries a doc line, a blood, a knockback and sound ids that exist, and the strip it
## plays holds exactly the frames its counts say.

const IDS := ["straw_man", "carrion_crow", "dust_bunny"]


func _json(id: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/%s/%s.json" % [id, id]))
	return d if d is Dictionary else {}


func test_each_one_loads_and_is_a_plain_walker_the_library_can_walk() -> void:
	for id: String in IDS:
		var d: EnemyDef = Registry.enemy(id)
		assert_object(d).override_failure_message(id + " did not load").is_not_null()
		if d == null:
			continue
		assert_str(d.id).is_equal(id)
		assert_bool(["chase", "flock"].has(d.brain)).override_failure_message("%s: brain %s" % [id, d.brain]).is_true()
		# EnemyManager's `plain` test: no charge numbers (a charger shoves as it walks, the script's), no attack script
		assert_bool(d.charge.is_empty()).override_failure_message(id + " charges").is_true()
		assert_bool(d.boss.is_empty()).override_failure_message(id + " has a boss block").is_true()
		assert_bool(d.ranged.is_empty()).override_failure_message(id + " shoots").is_true()
		assert_bool(d.hidden).override_failure_message(id).is_false()
		assert_bool(d.retired).override_failure_message(id).is_false()


func test_each_one_has_its_doc_blood_knockback_and_sounds() -> void:
	for id: String in IDS:
		var j := _json(id)
		var d: EnemyDef = Registry.enemy(id)
		if d == null:
			continue
		assert_str(str(j.get("doc", ""))).override_failure_message(id).is_not_empty()
		assert_str(d.doc).override_failure_message(id).is_not_empty()
		assert_float(d.knockback).override_failure_message(id).is_greater(0.0)
		var hex := str(j.get("blood", ""))
		assert_bool(hex.length() == 7 and Color.html_is_valid(hex)).override_failure_message("%s blood %s" % [id, hex]).is_true()
		assert_bool(d.blood.is_equal_approx(Color.html(hex))).override_failure_message(id).is_true()
		var sfx: Dictionary = j.get("sfx", {})
		for k: String in ["hit", "die"]:
			assert_bool(sfx.has(k)).override_failure_message("%s sfx %s" % [id, k]).is_true()
			assert_bool(Registry.soundmap.has_sound(str(sfx.get(k, "")))).override_failure_message("%s sfx %s: %s" % [id, k, str(sfx.get(k, ""))]).is_true()


func test_every_look_strip_holds_the_frames_its_counts_say() -> void:
	for id: String in IDS:
		var d: EnemyDef = Registry.enemy(id)
		if d == null:
			continue
		var looks: Array = [d]
		for code in d.variants.keys():
			looks.append(d.variant_def(str(code)))
		for v: EnemyDef in looks:
			var path := v.strip_path()
			assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
			var tex: Texture2D = load(path)
			if tex == null:
				continue
			assert_int(v.strip_cols).override_failure_message(path).is_greater(0)
			var cols := v.strip_cols
			var total := v.total_frames()
			var rows := int(ceil(float(total) / float(cols)))
			assert_int(tex.get_height() / rows).override_failure_message("%s: %d high for %d rows" % [path, tex.get_height(), rows]).is_equal(v.frame_px)
			assert_int(tex.get_width() / cols).override_failure_message("%s: %d wide for %d columns" % [path, tex.get_width(), cols]).is_equal(v.frame_px)
			assert_bool(v.frames_of("run") >= 2).override_failure_message(path).is_true()
			assert_bool(v.frames_of("die") >= 2).override_failure_message(path).is_true()
			assert_bool(v.frames_of("run_b") >= 2).override_failure_message(path + " has no back walk").is_true()
