## Pass 54, the lead's own pieces: the dark-blue skeleton looks (SK-E / KN-E, frame-by-frame tints of SK-A / KN-A) and
## Solenne's static pictures cut from Garry's turnaround (the title cut-out and the round badge).
extends GdUnitTestSuite


func test_the_skeleton_and_the_knight_carry_a_dark_blue_look() -> void:
	for pair in [["skeleton", "SK-E", "SK-A"], ["skeleton_knight", "KN-E", "KN-A"]]:
		var def: EnemyDef = Registry.enemy(pair[0])
		assert_object(def).is_not_null()
		assert_bool(def.variants.has(pair[1])).override_failure_message("%s has no %s look" % [pair[0], pair[1]]).is_true()
		var e: Dictionary = def.variants[pair[1]]
		var base: Dictionary = def.variants[pair[2]]
		# the loader resolves the look's pictures into textures (JsonContent); an unimported picture would have dropped the look
		var strip = e.get("sprite")
		var icon = e.get("icon")
		assert_bool(strip is Texture2D).override_failure_message("%s's strip is %s" % [pair[1], str(strip)]).is_true()
		assert_bool(icon is Texture2D).is_true()
		assert_str((strip as Texture2D).resource_path).ends_with("%s_sprite_e.png" % pair[0])
		assert_str((icon as Texture2D).resource_path).ends_with("%s_icon_e.png" % pair[0])
		# the same frames as the look it was tinted from: the walk, the fall and the cadence are the same pixels
		assert_that(e.get("anims", {})).is_equal(base.get("anims", {}))
		assert_that(e.get("strip_cols", 0)).is_equal(base.get("strip_cols", 0))
		assert_bool(ResourceLoader.exists("res://content/enemies/%s/%s_sprite_e.png" % [pair[0], pair[0]])).is_true()
		assert_bool(ResourceLoader.exists("res://content/enemies/%s/%s_icon_e.png" % [pair[0], pair[0]])).is_true()
		# the look is a choice, not the one in play: SK-A / KN-A stay the skeletons Garry picked
		assert_str(def.variant).is_equal(pair[2])


func test_a_dark_blue_look_builds_a_playable_variant_def() -> void:
	var def: EnemyDef = Registry.enemy("skeleton")
	var v: EnemyDef = def.variant_def("SK-E")
	assert_object(v).is_not_null()
	assert_str(str(v.sprite_file)).ends_with("skeleton_sprite_e.png")
	assert_str(v.type_key()).is_equal("skeleton@SK-E")
	# the tint keeps the numbers: a blue skeleton bites and walks like the ivory one
	assert_float(v.hp).is_equal_approx(def.hp, 0.001)
	assert_float(v.speed).is_equal_approx(def.speed, 0.001)


func test_the_dark_blue_strip_is_really_blue() -> void:
	# the first standing frame of SK-E: the visible pixels lean blue, the SK-A frame leans warm
	var e := Image.load_from_file("res://content/enemies/skeleton/skeleton_sprite_e.png")
	var a := Image.load_from_file("res://content/enemies/skeleton/skeleton_sprite_a.png")
	assert_object(e).is_not_null()
	assert_object(a).is_not_null()
	assert_int(e.get_width()).is_equal(a.get_width())
	assert_int(e.get_height()).is_equal(a.get_height())
	var cell: int = e.get_height()
	var blue_e := 0.0
	var blue_a := 0.0
	var n := 0
	for y in range(0, cell, 2):
		for x in range(0, cell, 2):
			var pe := e.get_pixel(x, y)
			if pe.a < 0.5:
				continue
			var pa := a.get_pixel(x, y)
			blue_e += pe.b - pe.r
			blue_a += pa.b - pa.r
			n += 1
	assert_int(n).is_greater(200)
	assert_float(blue_e / float(n)).override_failure_message("SK-E is not blue: mean b-r %.3f" % (blue_e / float(n))).is_greater(0.05)
	assert_float(blue_a / float(n)).is_less(0.0)


func test_solennes_static_pictures_exist() -> void:
	# the title's painted-menu cut-out and the round badge come straight from the turnaround (tools/make_solenne_static.py)
	assert_bool(ResourceLoader.exists("res://art/ui/wanted/hero_solenne.png")).is_true()
	assert_bool(ResourceLoader.exists("res://content/characters/solenne/solenne_icon.png")).is_true()
	var t := Image.load_from_file("res://art/ui/wanted/hero_solenne.png")
	assert_int(t.get_width()).is_equal(660)
	assert_int(t.get_height()).is_equal(888)
	var b := Image.load_from_file("res://content/characters/solenne/solenne_icon.png")
	assert_int(b.get_width()).is_equal(256)
	# the badge is her sun head: yellow in the middle
	var c := b.get_pixel(128, 118)
	assert_float(c.r).is_greater(0.6)
	assert_float(c.g).is_greater(0.5)
	assert_float(c.b).is_less(0.5)
