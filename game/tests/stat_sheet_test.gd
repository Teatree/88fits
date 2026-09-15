extends GdUnitTestSuite


func test_add_then_mul() -> void:
	var s := StatSheet.new()
	s.set_base("damage", 10.0)
	s.add_effect(Effect.make("damage", "add", 5.0), "lv")
	s.add_effect(Effect.make("damage", "mul", 0.2), "might")
	assert_float(s.get_stat("damage")).is_equal_approx(18.0, 0.001)


func test_muls_multiply_not_sum() -> void:
	var s := StatSheet.new()
	s.set_base("might", 1.0)
	s.add_effect(Effect.make("might", "mul", 0.5), "a")
	s.add_effect(Effect.make("might", "mul", 0.5), "b")
	assert_float(s.get_stat("might")).is_equal_approx(2.25, 0.001)


func test_set_replaces_base() -> void:
	var s := StatSheet.new()
	s.set_base("cooldown", 1.0)
	s.add_effect(Effect.make("cooldown", "set", 0.5), "evo")
	s.add_effect(Effect.make("cooldown", "mul", -0.1), "haste")
	assert_float(s.get_stat("cooldown")).is_equal_approx(0.45, 0.001)


func test_remove_source() -> void:
	var s := StatSheet.new()
	s.set_base("armor", 0.0)
	s.add_effect(Effect.make("armor", "add", 4.0), "passive:x")
	s.remove_source("passive:x")
	assert_float(s.get_stat("armor")).is_equal_approx(0.0, 0.001)


func test_breakdown_lists_sources() -> void:
	var s := StatSheet.new()
	s.set_base("move_speed", 5.0)
	s.add_effect(Effect.make("move_speed", "mul", 0.1), "Gnome")
	var rows := s.breakdown("move_speed")
	assert_int(rows.size()).is_equal(3)
	assert_str(rows[1]["source"]).is_equal("Gnome")
