extends GdUnitTestSuite

## Pass 69, the lead's review fixes: a dark ball out of the sky's ambient light, the locked hero drawn without fog, a
## kept look that has since been shelved giving way to the hero's own, Last Stand's thinner rim.


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Save.data = Save._default()
	Save._dirty = false


func test_a_ball_tint_can_leave_the_ambient_light_out() -> void:
	var m := ProjectileManager.tint_material(StandardMaterial3D.new(), {"albedo": "#0A4FA8", "ambient": false})
	assert_bool(m.disable_ambient_light).is_true()
	var lit := ProjectileManager.tint_material(StandardMaterial3D.new(), {"albedo": "#0A4FA8"})
	assert_bool(lit.disable_ambient_light).is_false()
	# Alley-Oop's and Slam Dunk's balls say so
	var ao: MutationDef = Registry.mutations.get("alley_oop")
	assert_bool(bool(ao.params["tint"].get("ambient", true))).is_false()


func test_the_locked_hero_can_be_drawn_without_fog() -> void:
	var s := BillboardSprite.new()
	s.set_fogless(true)
	var code: String = (s.material_override as ShaderMaterial).shader.code
	assert_bool(code.contains("fog_disabled")).is_true()
	s.set_fogless(false)
	assert_bool((s.material_override as ShaderMaterial).shader.code.contains("fog_disabled")).is_false()
	s.free()


func test_a_kept_look_that_was_shelved_gives_way_to_the_heros_own() -> void:
	var buck: CharacterDef = Registry.character("buck")
	assert_bool(buck.variant_shelved("BUC-B")).is_true()
	Save.data["hero_look"] = {"buck": "BUC-B"}
	assert_str(Registry.played_look(buck).look_code()).is_equal(buck.variant)
	Save.data["hero_look"] = {"buck": "BUC-D"}
	assert_str(Registry.played_look(buck).look_code()).is_equal("BUC-D")


func test_last_stands_rim_leaves_the_edges_readable() -> void:
	var code := FileAccess.get_file_as_string("res://core/shaders/last_stand.gdshader")
	assert_bool(code.contains("uniform float rim_width = 0.085;")).is_true()
	assert_bool(code.contains("clamp(red, 0.0, 0.62)")).is_true()
