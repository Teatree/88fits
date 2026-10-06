extends GdUnitTestSuite


func test_describe_mul_percent() -> void:
	# pass 45: might, area and greed read as attack damage, area of effect and coin gain (the ids are unchanged)
	assert_str(TextGen.describe_effect(Effect.make("might", "mul", 0.10))).is_equal("+10% attack damage")
	assert_str(TextGen.describe_effect(Effect.make("area", "mul", 0.20))).is_equal("+20% area of effect")
	assert_str(TextGen.describe_effect(Effect.make("greed", "mul", 0.12))).is_equal("+12% coin gain")


func test_describe_negative_mul() -> void:
	assert_str(TextGen.describe_effect(Effect.make("cooldown", "mul", -0.08))).is_equal("−8% cooldown")


func test_describe_add_count_singular() -> void:
	assert_str(TextGen.describe_effect(Effect.make("amount", "add", 1))).is_equal("+1 projectile")


func test_describe_add_count_plural() -> void:
	assert_str(TextGen.describe_effect(Effect.make("amount", "add", 2))).is_equal("+2 projectiles")


func test_weapon_description_forward_cone() -> void:
	var w := WeaponDef.new()
	w.id = "boomstick"
	w.display_name = "Boomstick"
	w.behavior = "ProjectileEmitter"
	w.targeting = "forward"
	w.base = {"damage": 6, "cooldown": 1.4, "amount": 5, "spread_deg": 35, "range": 6, "knockback": 2}
	var inst := WeaponInstance.new(w, 1)
	inst.rebuild(StatSheet.new(), [])
	assert_str(inst.description()).contains("5 pellets in a 35° cone")
	assert_str(inst.description()).contains("Knocks enemies back")


func test_next_level_text_maxed() -> void:
	var p := PassiveDef.new()
	p.max_level = 2
	p.levels = [[Effect.make("might", "mul", 0.1, "player")]]
	assert_str(TextGen.next_level_text(p, 2)).is_equal("Maxed.")


func test_time_format() -> void:
	assert_str(TextGen.time_mmss(272.4)).is_equal("04:32")
