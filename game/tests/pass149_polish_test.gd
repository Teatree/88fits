## Pass 149 (lead): Garry's polish list: red numbers on worse stats, the shield's recharge wait doubled, the Ghost Pepper's
## max HP price paid once, Hot Streak's Evolved icon from its new icon.
extends GdUnitTestSuite


func test_a_number_that_makes_a_stat_worse_is_marked_red() -> void:
	var beer: PassiveDef = Registry.passive("beer")
	var t := TextGen.passive_description(beer, 1)
	assert_str(t).contains("−5%")
	var bad := TextGen.bad_numbers_in(t)
	assert_array(Array(bad)).contains(["−5%"])
	assert_bool(bad.has("+15%")).is_false()
	# a cooldown cut is good, a longer wait is bad
	var cut := TextGen.describe_effect(Effect.make("cooldown", "mul", -0.1, "all_weapons"))
	assert_array(Array(TextGen.bad_numbers_in(cut))).is_empty()
	var longer := TextGen.describe_effect(Effect.make("shield_delay", "add", 1.0, "player"))
	assert_int(TextGen.bad_numbers_in(longer).size()).is_equal(1)
	# the words never change, only the colour: a description box marks them
	var w: WText = auto_free(W.desc_text(t))
	assert_bool(w.mark_bad).is_true()
	assert_str(w.text).is_equal(t)
	assert_object(w.bad_color).is_equal(R.NUMBER_BAD)


func test_the_ghost_peppers_max_hp_price_is_paid_once() -> void:
	var beer: PassiveDef = Registry.passive("beer")
	for lv in range(1, beer.max_level + 1):
		var hp := 0.0
		for e: Effect in TextGen._sum_effects(beer.effects_for_level(lv)):
			if e.stat == "max_hp":
				hp = e.value
		assert_float(hp).override_failure_message("level %d" % lv).is_equal_approx(-0.05, 0.0001)


func test_the_shield_waits_twice_as_long_to_recharge() -> void:
	assert_float(float(StatSheet.PLAYER_DEFAULTS["shield_delay"])).is_equal(6.0)
	var aegis: PassiveDef = Registry.passive("aegis")
	for e: Effect in aegis.effects_for_level(1):
		if e.stat == "shield_delay":
			assert_float(e.value).is_equal(3.0)


func test_hot_streaks_evolved_icon_follows_its_icon() -> void:
	var hs: PassiveDef = Registry.passive("hot_streak")
	assert_object(hs.evolved_icon).is_not_null()
	var base := Image.load_from_file(ProjectSettings.globalize_path("res://content/passives/hot_streak/hot_streak_icon_46e9_c1.png"))
	var evo := Image.load_from_file(ProjectSettings.globalize_path("res://content/passives/hot_streak/hot_streak_icon_evolved.png"))
	# the Evolved icon is the base with a white outline: the base's opaque middle pixel shows through unchanged
	var c := Vector2i(base.get_width() / 2, base.get_height() / 2)
	if base.get_pixelv(c).a > 0.9:
		assert_bool(base.get_pixelv(c).is_equal_approx(evo.get_pixelv(c))).is_true()
