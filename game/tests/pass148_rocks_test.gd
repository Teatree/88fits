extends GdUnitTestSuite
## Pass 148 (lane ROCKS; Garry: the painted rocks "feel a little detached from the ground"): a painting's foot (props.json
## `foot`, prop_billboard.gdshader's foot_* uniforms, PropField.foot_of / _set_foot_uniforms; BALANCING 91): off for every
## painting without one, on for the four rocks, a variant reading its kind's, the hell colour in a hell stage.

const MANIFEST := "res://art/sprites/props/props.json"
const ROCKS := ["rock_small", "rock_big", "boulder", "boulder_b"]


func _field(stage: String = "s1", hell: bool = false) -> PropField:
	var pf: PropField = auto_free(PropField.new())
	add_child(pf)
	pf.setup(MANIFEST, stage, hell)
	return pf


func _mat(pf: PropField, id: String) -> ShaderMaterial:
	var mmi := pf.get_node_or_null("Prop_" + id) as MultiMeshInstance3D
	return mmi.material_override as ShaderMaterial if mmi else null


func test_the_rocks_have_a_foot_and_nothing_else_does() -> void:
	var pf := _field()
	for id: String in pf.manifest.keys():
		var f := pf.foot_of(id)
		if ROCKS.has(id):
			assert_bool(f.is_empty()).override_failure_message(id + " has no foot").is_false()
			assert_float(float(f.get("band", 0.0))).is_greater(0.0)
			assert_float(float(f.get("sink", 0.0))).is_between(0.0, 0.2)
		elif not ROCKS.has(pf.kind_of(id)):
			assert_bool(f.is_empty()).override_failure_message(id + " has a foot").is_true()


func test_a_painting_without_a_foot_keeps_the_shader_as_before() -> void:
	var pf := _field()
	var m := _mat(pf, "saguaro_big")
	assert_object(m).is_not_null()
	for k in ["foot_sink", "foot_band", "foot_fade", "foot_dark", "foot_noise"]:
		var v = m.get_shader_parameter(k)
		assert_float(0.0 if v == null else float(v)).override_failure_message(k).is_equal(0.0)


func test_the_rocks_materials_carry_their_foot() -> void:
	var pf := _field()
	for id: String in ROCKS:
		var m := _mat(pf, id)
		assert_object(m).is_not_null()
		var f := pf.foot_of(id)
		assert_float(float(m.get_shader_parameter("foot_band"))).is_equal_approx(float(f["band"]), 0.0001)
		assert_float(float(m.get_shader_parameter("foot_sink"))).is_equal_approx(float(f.get("sink", 0.0)), 0.0001)
		var c: Color = m.get_shader_parameter("foot_color")
		assert_float(c.a).is_equal_approx(float(f.get("tone", 0.0)), 0.0001)


func test_a_variant_without_its_own_foot_reads_its_kinds() -> void:
	var pf := _field()
	pf.manifest["boulder_b"].erase("foot")
	assert_dict(pf.foot_of("boulder_b")).is_equal(pf.foot_of("boulder"))


func test_the_hell_colour_in_a_hell_stage() -> void:
	var cool := _field("s1", false)
	var hot := _field("s3", true)
	var f := cool.foot_of("rock_big")
	if not f.get("color_hell") is Array:
		return
	var a: Color = _mat(cool, "rock_big").get_shader_parameter("foot_color")
	var b: Color = _mat(hot, "rock_big").get_shader_parameter("foot_color")
	assert_float(a.r).is_equal_approx(float(f["color"][0]), 0.001)
	assert_float(b.g).is_equal_approx(float(f["color_hell"][1]), 0.001)
