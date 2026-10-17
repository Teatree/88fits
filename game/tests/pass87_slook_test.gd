extends GdUnitTestSuite

## Pass 87, lane SLOOK (Garry: "Stages now look different a bit (there is a blueish dim filter on the map for Stage 2 to
## indicate evening, and a redish filter on Stage 3 to indicate hell / bloodmoon). This should look good and not mess up
## how elements 'read' during the game. The screenshots in the Stages menu should reflect the look."):
##  - StageLook (core/systems/StageLook.gd): a stage's `filter` {color, strength, actors} multiplies the drawn world by
##    white.lerp(color, strength) and the creatures by white.lerp(color, strength x actors), two quads
##    (core/shaders/stage_filter.gdshader) split by the paintings' stencil and drawn before the ground marks, the
##    shadows, the pickups and the effects; `hell` from the entry (without a stage list: the third stage on);
##  - the gusts and the dust devil drawn before the filter (they take its tint);
##  - the Stages menu's pictures (tools/stage_shots.gd): art/ui/stages/<map>_s<k>.jpg for every stage, 1248 x 480.
## The map's colours are read from its file (Garry tunes them in the Level Editor): only the rules are pinned.

const LOOK := preload("res://core/systems/StageLook.gd")
const PICTURE_SIZE := Vector2i(1248, 480)


func _tl() -> WaveTimeline:
	var md: MapDef = Registry.map("red_canyon")
	return md.timeline if md else null


func test_filter_maths() -> void:
	# no filter, strength 0, a bad colour: nothing
	assert_that(LOOK.filter_mults({})[0]).is_equal(Color.WHITE)
	assert_that(LOOK.filter_mults({"filter": {"color": "#000000", "strength": 0.0}})[0]).is_equal(Color.WHITE)
	assert_that(LOOK.filter_mults({"filter": {"color": "nope", "strength": 0.8}})[0]).is_equal(Color.WHITE)
	# black at half strength halves the world; the creatures take ACTORS_DEFAULT of it
	var m: Array = LOOK.filter_mults({"filter": {"color": "#000000", "strength": 0.5}})
	assert_float((m[0] as Color).r).is_equal_approx(0.5, 0.001)
	assert_float((m[1] as Color).g).is_equal_approx(1.0 - 0.5 * LOOK.ACTORS_DEFAULT, 0.001)
	# a filter's own `actors` share; strength clamped to 1
	var a: Array = LOOK.filter_mults({"filter": {"color": "#ff0000", "strength": 3.0, "actors": 0.0}})
	assert_that(a[0]).is_equal(Color(1, 0, 0))
	assert_that(a[1]).is_equal(Color.WHITE)
	# the shader takes the colour in linear light (the screen shows it as authored)
	assert_vector(LOOK.screen_mult(Color(0.5, 0.5, 0.5))).is_equal_approx(Vector3.ONE * Color(0.5, 0.5, 0.5).srgb_to_linear().r, Vector3.ONE * 0.0001)


func test_hell_and_entries_without_a_stage_list() -> void:
	var tl := WaveTimeline.new()
	assert_bool(LOOK.hell_of(tl, 0)).is_false()
	assert_bool(LOOK.hell_of(tl, 1)).is_false()
	assert_bool(LOOK.hell_of(tl, 2)).is_true()
	assert_dict(LOOK.entry_of(tl, 1)).is_empty()
	assert_that(LOOK.filter_mults(LOOK.entry_of(tl, 2))[0]).is_equal(Color.WHITE)
	# with one: the entry's own `hell`, past the last stage the last's entry (an endless keeps its look)
	tl.set("stage_list", [{"id": "a", "hell": false}, {"id": "b", "hell": true, "filter": {"color": "#102040", "strength": 0.4}}])
	assert_bool(LOOK.hell_of(tl, 0)).is_false()
	assert_bool(LOOK.hell_of(tl, 1)).is_true()
	assert_str(str(LOOK.entry_of(tl, 7).get("id"))).is_equal("b")


func test_red_canyon_stage_looks() -> void:
	var tl := _tl()
	assert_object(tl).is_not_null()
	var list: Array = LOOK.stage_list_of(tl)
	assert_int(list.size()).is_greater_equal(3)
	# stage 1 plays as before: no filter, no hell
	assert_that(LOOK.filter_mults(list[0])[0]).is_equal(Color.WHITE)
	assert_bool(LOOK.hell_of(tl, 0)).is_false()
	# stage 2: a blueish dim (the world darker, blue kept most)
	var m2: Color = LOOK.filter_mults(list[1])[0]
	assert_float(m2.b).is_greater_equal(m2.r)
	assert_float(m2.get_luminance()).is_less(0.95)
	# stage 3: a reddish blood moon over the hell ground (red kept most)
	var m3: Color = LOOK.filter_mults(list[2])[0]
	assert_float(m3.r).is_greater_equal(m3.b)
	assert_float(m3.r).is_greater_equal(m3.g)
	assert_float(m3.get_luminance()).is_less(0.95)
	assert_bool(LOOK.hell_of(tl, 2)).is_true()
	# the creatures are tinted less than the world, so they stay brighter than the ground
	for e: Dictionary in list:
		var mm: Array = LOOK.filter_mults(e)
		assert_float((mm[1] as Color).get_luminance()).is_greater_equal((mm[0] as Color).get_luminance())


func test_the_quads() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var host := Node.new()
	add_child(host)
	var sl: StageLook = LOOK.of(host)
	assert_object(sl).is_not_null()
	assert_object(LOOK.of(host)).is_same(sl)
	sl.camera = cam
	# white: nothing built
	sl.set_mults(Color.WHITE, Color.WHITE, 0.0)
	assert_object(sl.quads()[0]).is_null()
	sl.set_mults(Color(0.5, 0.6, 0.9), Color(0.8, 0.85, 0.95), 0.0)
	var q: Array = sl.quads()
	assert_object(q[0]).is_not_null()
	assert_object(q[1]).is_not_null()
	for k in range(2):
		var mi := q[k] as MeshInstance3D
		assert_bool(mi.visible).is_true()
		assert_object(mi.get_parent()).is_same(cam)
		var mat := mi.material_override as ShaderMaterial
		assert_int(mat.render_priority).is_equal(LOOK.PRIORITY)
		assert_str(mat.shader.code).contains("blend_mul")
	assert_str((q[0].material_override as ShaderMaterial).shader.code).contains("stencil_mode read, compare_not_equal, 1;")
	assert_str((q[1].material_override as ShaderMaterial).shader.code).contains("stencil_mode read, compare_equal, 1;")
	var got: Vector3 = (q[0].material_override as ShaderMaterial).get_shader_parameter("mult")
	assert_vector(got).is_equal_approx(LOOK.screen_mult(Color(0.5, 0.6, 0.9)), Vector3.ONE * 0.0001)
	# back to white: hidden (stage 1 draws nothing)
	sl.set_mults(Color.WHITE, Color.WHITE, 0.0)
	assert_bool((q[0] as MeshInstance3D).visible).is_false()
	assert_bool((q[1] as MeshInstance3D).visible).is_false()
	host.queue_free()
	cam.queue_free()


## The filter sits after the water and before every ground mark, shadow, pickup and effect.
func test_draw_order() -> void:
	assert_int(LOOK.PRIORITY).is_greater(-10)
	assert_int(LOOK.PRIORITY).is_less(Telegraphs.PRIO_SCORCH)
	assert_int(LOOK.PRIORITY).is_less(EnemyManager.SHADOW_PRIORITY)
	assert_int(LOOK.PRIORITY).is_less(PickupManager.PICKUP_PRIORITY)
	assert_int(LOOK.PRIORITY).is_less(-6)   # the Salt's patches (SaltPatches)
	# the gusts and the dust devil come before it (they take the stage's tint)
	var gust := DustGust.new()
	add_child(gust)
	var gm: Material = (gust.get_child(0) as MultiMeshInstance3D).material_override
	assert_int(gm.render_priority).is_less(LOOK.PRIORITY)
	gust.queue_free()
	var dd := DustDevil.new()
	add_child(dd)
	var found := false
	for c in dd.get_children():
		if c is MeshInstance3D:
			assert_int((c as MeshInstance3D).material_override.render_priority).is_less(LOOK.PRIORITY)
			found = true
	assert_bool(found).is_true()
	dd.queue_free()


## show_stage hands the map its hell (the entry's) and keeps the first stage's look at once.
func test_show_stage_on_a_game() -> void:
	var game := _FakeGame.new()
	var cam := Camera3D.new()
	game.add_child(cam)
	game.camera = cam
	game.map = _FakeMap.new()
	game.add_child(game.map)
	add_child(game)
	var sl: StageLook = LOOK.of(game)
	var md: MapDef = Registry.map("red_canyon")
	Run.map = md
	var list: Array = LOOK.stage_list_of(md.timeline)
	for s in range(list.size()):
		sl.stage = -1
		sl.show_stage(s)
		assert_float(game.map.hell).is_equal(1.0 if bool((list[s] as Dictionary).get("hell", false)) else 0.0)
		assert_that(sl.env_mult).is_equal(LOOK.filter_mults(list[s])[0])
	game.queue_free()
	Run.map = null


func test_stage_pictures() -> void:
	var tl := _tl()
	var list: Array = LOOK.stage_list_of(tl)
	for k in range(list.size()):
		var path := "res://art/ui/stages/red_canyon_s%d.jpg" % (k + 1)
		assert_bool(FileAccess.file_exists(path)).override_failure_message("no picture " + path).is_true()
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		assert_object(img).is_not_null()
		assert_that(img.get_size()).is_equal(PICTURE_SIZE)
		var shot := str((list[k] as Dictionary).get("shot", ""))
		if shot != "":
			assert_bool(FileAccess.file_exists(shot)).override_failure_message("the entry's shot is missing: " + shot).is_true()


class _FakeGame:
	extends Node
	var camera: Camera3D
	var map: Node


class _FakeMap:
	extends Node
	var hell := -1.0
	func set_hell(f: float, _seconds: float = 3.0) -> void:
		hell = f
