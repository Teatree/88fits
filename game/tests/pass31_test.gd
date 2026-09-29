extends GdUnitTestSuite

## Pass 31: spikes that hold their line, the Rocketeer lit and dancing, the healing economy cut back, flat water.


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func test_the_rocketeer_is_lit_and_dances() -> void:
	var f := FileAccess.open("res://content/enemies/rocketeer/rocketeer.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_float(float(d.get("outline_frac", 0.0))).is_greater(0.0)
	assert_str(str(d.get("outline_color", ""))).is_not_equal("")
	assert_bool(str(d.get("motion", "")).to_lower().contains("danc")).override_failure_message(str(d.get("motion", ""))).is_true()


func test_healing_is_a_trickle() -> void:
	_start()
	# the lines pay less than they did, and Mend says what it costs
	var mend: LineDef = Registry.line("mend")
	assert_float(float(mend.levels[0][0].value)).is_less_equal(0.5)
	assert_str(mend.trade).is_not_equal("")
	var thirst: LineDef = Registry.line("thirst")
	assert_float(float(thirst.levels[0][0].value)).is_less_equal(0.015)
	assert_float(Registry.pickup("heart").value).is_less_equal(0.2)
	assert_float(Registry.character("astro").level_heal).is_less_equal(0.05)


func test_lifesteal_cannot_outrun_a_crowd() -> void:
	_start()
	Run.add_or_rank_line("thirst")
	Run.add_or_rank_line("thirst")
	Run.rebuild_sheets()
	var healed := 0.0
	var tally := func(n: float): healed += n
	Run.lifesteal_healed.connect(tally)
	# a beam through a pack: ten thousand points of damage in one second heals a sliver, not a bar
	for k in range(100):
		Run.add_damage("big_mouth", 100.0)
	Run.lifesteal_healed.disconnect(tally)
	var cap: float = Run.player_sheet.get_stat("max_hp", 100.0) * Run.LIFESTEAL_CAP
	assert_float(healed).override_failure_message("healed %.1f, cap %.1f" % [healed, cap]).is_less_equal(cap + 1.0)


func test_regen_waits_after_a_hit() -> void:
	var p := load("res://player/Player.gd")
	assert_bool(p != null).is_true()
	# the constant is the contract: three seconds of no regen after every hit
	assert_float(float(p.REGEN_HOLD_AFTER_HIT)).is_greater_equal(2.0)


func test_the_water_is_a_plain_material() -> void:
	Run.forced_map_seed = 5
	_start()
	var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
	add_child(m)
	var lake: MeshInstance3D = m.find_child("Oasis", true, false)
	assert_object(lake).is_not_null()
	var mat := lake.material_override
	assert_bool(mat is StandardMaterial3D).override_failure_message("the water is still a shader").is_true()
	var sm := mat as StandardMaterial3D
	assert_int(int(sm.shading_mode)).is_equal(int(BaseMaterial3D.SHADING_MODE_UNSHADED))
	assert_float(sm.albedo_color.a).is_between(0.3, 0.9)   # pass 32: deepened so the sand under it stops showing
	assert_object(sm.albedo_texture).is_null()
	Run.forced_map_seed = 0
