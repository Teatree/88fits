## Pass 123, lane BACKDROP: the Royale theme's menu backdrop (ui/wanted/RoyaleBackdrop.gd; Garry: "Paint a sunset version
## of today's title scene (same desert, props and hero) and use it behind the menus" ... "maybe a tumbleweed passes
## every minute or so, maybe a wind moves some cactuses gently, maybe the sun shine").
##  - make() builds both kinds by path (no class cache needed): a full-rect Control that never takes a touch;
##  - the layers: the painted plate, the sun's shine, the title preset's paintings (every one of its props, the game's
##    own pictures, over their shadows, far first), the tumbleweed, the motes; the disc only on the title;
##  - set_dim, the disc (its default spot, set_disc, the plate following it to cover);
##  - the tumbleweed's timer stays inside its range and a forced pass rolls across and ends;
##  - the animation is off while hidden or out of the tree, and headless unless forced;
##  - the manifest's props are the title scene's first preset, at the capture's spots.
extends GdUnitTestSuite

const BD := "res://ui/wanted/RoyaleBackdrop.gd"
const MANIFEST := "res://art/ui/royale/backdrop.json"


func after_test() -> void:
	load(BD).set("force_live", false)


func _make(kind: String, view := Vector2(1080, 1920)) -> Control:
	var host := Control.new()
	host.size = view
	add_child(host)
	var bd: Control = load(BD).call("make", kind)
	host.add_child(bd)
	bd.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bd.size = view
	auto_free(host)
	return bd


func _manifest() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return d if d is Dictionary else {}


func test_make_builds_both_kinds_without_a_class_name() -> void:
	var script: GDScript = load(BD)
	assert_str(script.get_global_name()).is_empty()
	for kind in ["menu", "title"]:
		var bd := _make(kind)
		assert_object(bd).is_not_null()
		assert_str(str(bd.get("kind"))).is_equal(kind)
		assert_int(bd.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# an unknown kind is the menu's
	assert_str(str(_make("nonsense").get("kind"))).is_equal("menu")


func test_make_is_full_rect() -> void:
	var bd: Control = auto_free(load(BD).call("make", "title"))
	assert_float(bd.anchor_left).is_equal(0.0)
	assert_float(bd.anchor_top).is_equal(0.0)
	assert_float(bd.anchor_right).is_equal(1.0)
	assert_float(bd.anchor_bottom).is_equal(1.0)


func test_the_layers_exist() -> void:
	var m := _manifest()
	assert_bool(m.is_empty()).is_false()
	for kind in ["menu", "title"]:
		var bd := _make(kind)
		assert_bool(bd.call("has_plate")).is_true()
		var stage: Control = bd.get("stage")
		assert_object(stage).is_not_null()
		assert_object(stage.get_node_or_null("Plate")).is_not_null()
		assert_object(stage.get_node_or_null("Sun")).is_not_null()
		assert_object(stage.get_node_or_null("Motes")).is_not_null()
		assert_object(stage.get_node_or_null("Tumbleweed")).is_not_null()
		var props: Array = bd.get("props")
		assert_int(props.size()).is_equal((m["props"] as Array).size())
		assert_int((bd.get("shadows") as Array).size()).is_greater(0)
		# far first: every painting's base no nearer than the one drawn after it
		var last := -1
		var last_y := -INF
		for p: Sprite2D in props:
			assert_int(p.get_index()).is_greater(last)
			assert_float(p.position.y).is_greater_equal(last_y)
			last = p.get_index()
			last_y = p.position.y
			assert_object(p.material).is_not_null()
		# the dim is drawn over the scene
		assert_int(bd.get_node("Dim").get_index()).is_greater(stage.get_index())
		if kind == "title":
			assert_object(bd.get("disc")).is_not_null()
		else:
			assert_object(bd.get("disc")).is_null()


func test_the_paintings_are_the_title_scenes_first_preset() -> void:
	var m := _manifest()
	var sc = JSON.parse_string(FileAccess.get_file_as_string("res://art/ui/title_scene.json"))
	var preset: Array = sc["red_canyon"]["presets"][0]["props"]
	var ids: Array = []
	for p in preset:
		ids.append(str(p["id"]))
	var got: Array = []
	for p in m["props"]:
		got.append(str(p["look"]))
		assert_bool(ResourceLoader.exists(str(p["texture"]))).is_true()
		assert_float(float(p["height_px"])).is_greater(10.0)
	# pass 123 (Garry: "Make the environment art a bit Sparser"): fewer than the preset, and every one of them from it
	assert_int(got.size()).is_greater(0)
	assert_int(got.size()).is_less(ids.size())
	for g: String in got:
		assert_bool(ids.has(g)).override_failure_message(g).is_true()
	assert_bool(ResourceLoader.exists(str(m["plate"]))).is_true()
	assert_bool(ResourceLoader.exists(str(m["tumbleweed"]))).is_true()


func test_set_dim_clamps_and_shows() -> void:
	var bd := _make("menu")
	assert_float(bd.call("get_dim")).is_equal(0.0)
	bd.call("set_dim", 0.4)
	assert_float(bd.call("get_dim")).is_equal_approx(0.4, 0.0001)
	assert_float((bd.get_node("Dim") as ColorRect).color.a).is_equal_approx(0.4, 0.0001)
	bd.call("set_dim", 3.0)
	assert_float(bd.call("get_dim")).is_equal(1.0)
	bd.call("set_dim", -1.0)
	assert_float(bd.call("get_dim")).is_equal(0.0)


func test_the_disc_defaults_and_moves() -> void:
	var bd := _make("title")
	var c: Vector2 = bd.call("disc_center")
	assert_vector(c).is_equal(Vector2(540, 1160))
	assert_float(bd.call("disc_radius")).is_equal(270.0)
	# the plate's own spot lands on it
	var stage: Control = bd.get("stage")
	var spot := Vector2(540, 1400)
	assert_vector(stage.position + spot * stage.scale.x).is_equal_approx(c, Vector2(0.5, 0.5))
	var disc: Control = bd.get("disc")
	assert_vector(stage.position + (disc.position + disc.size * 0.5) * stage.scale.x).is_equal_approx(c, Vector2(0.5, 0.5))
	bd.call("set_disc", Vector2(540, 1100), 240.0)
	assert_vector(bd.call("disc_center")).is_equal(Vector2(540, 1100))
	assert_float(bd.call("disc_radius")).is_equal(240.0)
	assert_vector(stage.position + (disc.position + disc.size * 0.5) * stage.scale.x).is_equal_approx(Vector2(540, 1100), Vector2(0.5, 0.5))
	# the plate still covers the screen
	assert_float(stage.position.y).is_less_equal(0.0)
	assert_float(stage.position.y + 2400.0 * stage.scale.y).is_greater_equal(1920.0)


func test_a_taller_and_a_wider_screen_are_covered_with_the_spot_kept() -> void:
	for view in [Vector2(1080, 2400), Vector2(1080, 2520), Vector2(1440, 1920)]:
		var bd := _make("title", view)
		var stage: Control = bd.get("stage")
		var s := stage.scale.x
		assert_float(s).is_greater_equal(1.0)
		assert_float(stage.position.x).is_less_equal(0.001)
		assert_float(stage.position.y).is_less_equal(0.001)
		assert_float(stage.position.x + 1080.0 * s).is_greater_equal(view.x - 0.001)
		assert_float(stage.position.y + 2400.0 * s).is_greater_equal(view.y - 0.001)
		var c: Vector2 = bd.call("disc_center")
		assert_float(c.x).is_equal_approx(view.x * 0.5, 0.01)
		assert_float(bd.call("plate_scale")).is_equal_approx(s, 0.0001)


func test_the_tumbleweed_timer_stays_in_range() -> void:
	var script: GDScript = load(BD)
	assert_float(script.TUMBLE_MIN).is_greater_equal(30.0)
	assert_float(script.TUMBLE_MAX).is_less_equal(120.0)
	assert_float(script.TUMBLE_MIN).is_less(script.TUMBLE_MAX)
	for i in 20:
		script.set("_next_pass_ms", -1)
		var bd: Control = auto_free(script.new())
		var w: float = bd.call("tumble_wait")
		assert_float(w).is_between(script.TUMBLE_FIRST_MIN - 0.5, script.TUMBLE_FIRST_MAX)
	# one clock for the session: the next screen's backdrop waits for the same pass, it does not roll a new first one
	var at: int = script.get("_next_pass_ms")
	var again: Control = auto_free(script.new())
	assert_int(script.get("_next_pass_ms")).is_equal(at)
	assert_float(again.call("tumble_wait")).is_less_equal(script.TUMBLE_FIRST_MAX)


func test_a_forced_pass_rolls_across_and_waits_again() -> void:
	var script: GDScript = load(BD)
	var bd := _make("menu")
	bd.call("force_tumbleweed")
	assert_bool(bd.call("tumble_rolling")).is_true()
	var tumble: Node2D = bd.get("tumble")
	assert_bool(tumble.visible).is_true()
	var x0 := tumble.position.x
	# step it by hand (headless: the backdrop's own process is off)
	var steps := 0
	while bool(bd.call("tumble_rolling")) and steps < 2000:
		bd.call("_process", 0.05)
		steps += 1
	assert_int(steps).is_less(2000)
	assert_float(absf(tumble.position.x - x0)).is_greater(1000.0)
	assert_bool(tumble.visible).is_false()
	assert_float(bd.call("tumble_wait")).is_between(script.TUMBLE_MIN, script.TUMBLE_MAX)


func test_the_animation_is_off_while_hidden_and_headless() -> void:
	var script: GDScript = load(BD)
	var bd := _make("title")
	# headless and not forced: nothing runs
	assert_bool(bd.call("is_animating")).is_false()
	script.set("force_live", true)
	bd.visible = false
	bd.visible = true
	assert_bool(bd.call("is_animating")).is_true()
	bd.visible = false
	assert_bool(bd.call("is_animating")).is_false()
	bd.visible = true
	assert_bool(bd.call("is_animating")).is_true()
	# a hidden parent stops it too
	var host: Control = bd.get_parent()
	host.visible = false
	assert_bool(bd.call("is_animating")).is_false()
	host.visible = true
	assert_bool(bd.call("is_animating")).is_true()
	# out of the tree
	host.remove_child(bd)
	assert_bool(bd.call("is_animating")).is_false()
	bd.free()


func _walk(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control:
			out.append(c)
		_walk(c, out)


func test_no_layer_takes_a_touch() -> void:
	for kind in ["menu", "title"]:
		var bd := _make(kind)
		var all: Array = []
		_walk(bd, all)
		assert_int(all.size()).is_greater(4)
		for c: Control in all:
			assert_int(c.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_the_foot_shade_starts_under_the_disc() -> void:
	var script: GDScript = load(BD)
	var bd := _make("title")
	var foot: Control = bd.get("foot")
	assert_object(foot).is_not_null()
	var c: Vector2 = bd.call("disc_center")
	assert_float(foot.position.y).is_equal_approx(c.y + script.FOOT_FROM, 0.5)
	assert_float(foot.position.y + foot.size.y).is_equal_approx(1920.0, 0.5)
	assert_int(foot.get_index()).is_less(bd.get_node("Dim").get_index())
