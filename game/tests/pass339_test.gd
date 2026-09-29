extends GdUnitTestSuite

## Pass 33.9: the goblin and the runt painted again. Their first front paintings had four ears, and the goblin's walk on a
## man's skeleton came out lanky; now each walks on a Mixamo stride refitted to its big head and short legs (twelve
## frames from the front, twelve from behind; the orc walk for the goblin, the plain walk for the runt) and dies in an
## animated fall between its standing and dead paintings, eight frames at 12 a second that end on the painted body.

const IDS := ["goblin", "goblin_runt"]


func test_goblins_walk_on_the_fitted_stride() -> void:
	for id in IDS:
		var d: EnemyDef = Registry.enemy(id)
		assert_object(d.sprite).override_failure_message(id + " has no painted strip").is_not_null()
		assert_int(d.frames_of("run")).is_equal(12)
		assert_int(d.frames_of("run_b")).is_equal(12)
		# the variant in play keeps its own clip rate (pass 35: RUN-D runs at 20)
		var vf = (d.variants.get(d.variant, {}) as Dictionary).get("fps", {})
		var want: float = float(vf.get("run", 15)) if vf is Dictionary else 15.0
		assert_float(float(d.fps.get("run", 0))).is_equal_approx(want, 0.01)
		assert_float(want).is_between(12.0, 24.0)


func test_goblins_fall_in_eight_frames() -> void:
	for id in IDS:
		var d: EnemyDef = Registry.enemy(id)
		assert_int(d.frames_of("die")).override_failure_message(id + " die frames").is_equal(8)
		assert_float(float(d.fps.get("die", 0))).is_equal_approx(12.0, 0.01)
		# the fall plays through before the body starts to sink (1.4 s from the blow to gone)
		assert_float(8.0 / float(d.fps.get("die", 1))).is_less(1.0)


func test_goblin_sheets_are_whole() -> void:
	for id in IDS:
		_check_sheet(id)


func _check_sheet(id: String) -> void:
	var d: EnemyDef = Registry.enemy(id)
	var total := 0
	for k in d.anims:
		total += int(d.anims[k])
	assert_int(total).is_equal(43)
	var img: Image = d.sprite.get_image()
	if img.is_compressed():
		img.decompress()
	var cell := d.frame_px
	var cols := d.strip_cols if d.strip_cols > 0 else img.get_width() / cell
	assert_int(cols * cell).is_equal(img.get_width())
	# the last die cell is the painted body, not an empty frame
	var off := 0
	for a in ["idle", "run", "attack", "hit"]:
		off += d.frames_of(a)
	var last := off + d.frames_of("die") - 1
	var x0 := (last % cols) * cell
	var y0 := (last / cols) * cell
	var solid := 0
	for y in range(y0, y0 + cell, 4):
		for x in range(x0, x0 + cell, 4):
			if img.get_pixel(x, y).a > 0.5:
				solid += 1
	assert_int(solid).is_greater(60)
