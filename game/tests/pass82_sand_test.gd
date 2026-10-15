extends GdUnitTestSuite

## Pass 82, lane SAND (Garry: "Sand Texture is still not very good. I added a reference called sand-texture.webp let's
## try generating something like that, and maybe a couple (4) variants to try out, see which feels most natural. I like
## the little rocks in the texture though, can you keep them in 2 out of the 4 variants. Add the previous sand texture as
## the 5th variant as well. I want to be able to switch between them easily. Maybe in the LevelEditor"):
##  - five sands (RedCanyon.SANDS): pass 81's (art/env/sand.png, unchanged, the default until Garry picks) and four new
##    paintings (tools/gen_sand.py: soft wavy dune shading and a fine grain, two with little pebbles), each tileable and
##    at pass 81's mean colour;
##  - the map file's `sand` (timeline_data; WaveTimeline.sand) picks one as the terrain builds; "" or an unknown id
##    plays the default; the arena switches them on the spot (RedCanyon.set_sand).

const RED_CANYON := preload("res://world/maps/red_canyon/RedCanyon.gd")
const TERRAIN := "res://core/shaders/terrain_painted.gdshader"
const NEW := ["dunes", "dunes_pebbles", "ripples", "ripples_pebbles"]


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	Run.forced_map_seed = 0
	Run.end()
	_restore()


## the map file's own sand while a test has set another (null: nothing to put back)
var _file_sand = null


func _restore() -> void:
	var md: MapDef = Registry.map("red_canyon")
	if _file_sand != null and md and md.timeline:
		md.timeline.sand = str(_file_sand)
	_file_sand = null


## Red Canyon built with the map file's sand set to `id` for this test (the map's own value put back after).
func _canyon(id: String, ms := 5) -> MapBase:
	var md: MapDef = Registry.map("red_canyon")
	if _file_sand == null:
		_file_sand = md.timeline.sand
	md.timeline.sand = id
	Run.forced_map_seed = ms
	Run.end()
	Run.start(Registry.character("drifter"), md)
	var m: MapBase = auto_free((md.scene as PackedScene).instantiate())
	add_child(m)
	return m


func _img(path: String) -> Image:
	var img := Image.new()
	assert_int(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))).is_equal(OK)
	img.convert(Image.FORMAT_RGB8)
	return img


func _mean(img: Image, step := 2) -> Color:
	var sum := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	sum /= float(n)
	return Color(sum.x, sum.y, sum.z)


func _diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _repo_file(rel: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("..").path_join(rel))


# ---------------------------------------------------------------- the five sands

func test_five_sands_and_the_default_is_pass_81s() -> void:
	var sands: Dictionary = RED_CANYON.SANDS
	assert_array(sands.keys()).contains_exactly_in_any_order(["pass81"] + NEW)
	assert_str(RED_CANYON.SAND_DEFAULT).is_equal("pass81")
	assert_str(str(sands["pass81"]["file"])).is_equal("res://art/env/sand.png")
	assert_float(float(sands["pass81"]["scale"])).is_equal(1.0)
	for id: String in sands:
		var s: Dictionary = sands[id]
		assert_bool(ResourceLoader.exists(str(s["file"]))).override_failure_message(id + ": no painting").is_true()
		assert_float(float(s["scale"])).is_between(0.4, 2.0)
		assert_str(str(s.get("name", ""))).is_not_empty()
		assert_str(str(s.get("short", ""))).is_not_empty()
	for id: String in NEW:
		assert_str(str(sands[id]["file"])).is_equal("res://art/env/sand_%s.png" % id)
		# the arena and the editor name them; the new paintings import with mipmaps like pass 81's
		var imp := FileAccess.get_file_as_string("res://art/env/sand_%s.png.import" % id)
		assert_bool(imp.contains("mipmaps/generate=true")).override_failure_message(id + " has no mipmaps").is_true()
	# pass 81's sand is untouched: still the s8102 painting's tool and source
	assert_bool(_repo_file("tools/gen_textures.py").contains("sand_klein_s8102.png")).is_true()


func test_every_new_sand_tiles_and_wears_pass_81s_colour() -> void:
	var today := _mean(_img("res://art/env/sand.png"))
	for id: String in NEW:
		var img := _img("res://art/env/sand_%s.png" % id)
		var w := img.get_width()
		var h := img.get_height()
		assert_int(w).is_equal(1024)
		assert_int(h).is_equal(1024)
		# it tiles: the wrap is no harder a step than neighbouring columns or rows, nor are the lines through the middle
		# (where a painting's old edges were repainted)
		var wrap_x := 0.0
		var wrap_y := 0.0
		var adj := 0.0
		var mid_x := 0.0
		var mid_y := 0.0
		for k in range(0, 1024, 2):
			wrap_x += _diff(img.get_pixel(0, k), img.get_pixel(w - 1, k))
			wrap_y += _diff(img.get_pixel(k, 0), img.get_pixel(k, h - 1))
			adj += _diff(img.get_pixel(300, k), img.get_pixel(301, k)) + _diff(img.get_pixel(k, 300), img.get_pixel(k, 301))
			mid_x += _diff(img.get_pixel(w / 2 - 1, k), img.get_pixel(w / 2, k))
			mid_y += _diff(img.get_pixel(k, h / 2 - 1), img.get_pixel(k, h / 2))
		adj /= 2.0
		for v: float in [wrap_x, wrap_y, mid_x, mid_y]:
			assert_float(v).override_failure_message("%s: a seam (%.1f against %.1f)" % [id, v, adj]).is_less(adj * 1.6)
		# the same mean colour as pass 81's (within a level of 255): the river bed, the oases and the walls still match
		var m := _mean(img)
		assert_float(_diff(m, today)).override_failure_message("%s: mean %s against %s" % [id, m, today]).is_less(3.0 / 255.0)
		# and the pins pass 54 and 61 hold for the sand's colour
		assert_float(m.v).is_greater(0.835)
		assert_float(m.s).is_less(0.36)
		assert_float(m.h * 360.0).is_between(33.0, 40.0)


func test_two_of_the_new_sands_keep_little_rocks() -> void:
	# a sand is the mean colour lighter or darker (its saturation the same everywhere); a pebble keeps some of its own
	# grey: count the pixels well greyer than the sand
	var counts := {}
	for id: String in NEW:
		var img := _img("res://art/env/sand_%s.png" % id)
		var s0 := _mean(img).s
		var n := 0
		for y in range(0, 1024, 2):
			for x in range(0, 1024, 2):
				if img.get_pixel(x, y).s < s0 * 0.8:
					n += 1
		counts[id] = n
	for id: String in ["dunes_pebbles", "ripples_pebbles"]:
		assert_int(int(counts[id])).override_failure_message("pebbles %s" % [counts]).is_greater(150)
		# little rocks, scattered: never a carpet (under 2% of the sand)
		assert_int(int(counts[id])).override_failure_message("pebbles %s" % [counts]).is_less(512 * 512 / 50)
	for id: String in ["dunes", "ripples"]:
		assert_int(int(counts[id])).override_failure_message("pebbles %s" % [counts]).is_less(int(counts[id + "_pebbles"]) / 10)


# ---------------------------------------------------------------- the switch

func test_the_map_files_sand_paints_the_terrain() -> void:
	for id: String in NEW:
		var m := _canyon(id)
		var mat: ShaderMaterial = m.get("_terrain_mat")
		var tex: Texture2D = mat.get_shader_parameter("sand_tex")
		assert_str(tex.resource_path).is_equal("res://art/env/sand_%s.png" % id)
		assert_float(float(mat.get_shader_parameter("sand_scale"))).is_equal(float(RED_CANYON.SANDS[id]["scale"]))
		assert_str(str(m.get("sand_id"))).is_equal(id)
		m.queue_free()
		await get_tree().process_frame


func test_no_sand_or_an_unknown_one_plays_pass_81s() -> void:
	for id: String in ["", "pass81", "nope"]:
		var m := _canyon(id)
		var mat: ShaderMaterial = m.get("_terrain_mat")
		assert_str((mat.get_shader_parameter("sand_tex") as Texture2D).resource_path).is_equal("res://art/env/sand.png")
		assert_float(float(mat.get_shader_parameter("sand_scale"))).is_equal(1.0)
		assert_str(str(m.get("sand_id"))).is_equal("pass81")
		m.queue_free()
		await get_tree().process_frame


func test_the_arena_switches_the_sand_on_the_spot() -> void:
	var m := _canyon("")
	var mat: ShaderMaterial = m.get("_terrain_mat")
	m.call("set_sand", "ripples_pebbles")
	assert_str((mat.get_shader_parameter("sand_tex") as Texture2D).resource_path).is_equal("res://art/env/sand_ripples_pebbles.png")
	assert_str(str(m.get("sand_id"))).is_equal("ripples_pebbles")
	m.call("set_sand", "bogus")
	assert_str((mat.get_shader_parameter("sand_tex") as Texture2D).resource_path).is_equal("res://art/env/sand.png")
	# the arena's WORLD tab lists every sand by its short label
	var gs := GDScript.new()
	gs.source_code = "extends Node
var map = null
"
	gs.reload()
	var fake: Node = auto_free(Node.new())
	fake.set_script(gs)
	fake.set("map", m)
	var panel: ArenaPanel = auto_free(ArenaPanel.new())
	panel.game = fake
	var opts: Array = panel.sand_options()
	assert_int(opts.size()).is_equal(5)
	for o: Array in opts:
		assert_bool(RED_CANYON.SANDS.has(str(o[0]))).is_true()
		assert_str(str(o[1])).is_equal(str(RED_CANYON.SANDS[o[0]]["short"]))


func test_the_sand_key_is_read_from_the_map_file() -> void:
	var w: WaveTimeline = JsonContent.timeline_from_dict({"sand": "dunes"})
	assert_str(w.sand).is_equal("dunes")
	assert_str(JsonContent.timeline_from_dict({}).sand).is_equal("")
	# the map file is Garry's: whatever it names is one of the five (or nothing, the default)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var tl: Dictionary = (data as Dictionary).get("timeline_data", {})
	if tl.has("sand"):
		assert_bool(RED_CANYON.SANDS.has(str(tl["sand"]))).override_failure_message("the map names %s" % tl["sand"]).is_true()
	# the shader samples the sand at its own scale; the river bed and the rock keep theirs
	var code: String = (load(TERRAIN) as Shader).code
	assert_bool(code.contains("uniform float sand_scale = 1.0;")).is_true()
	assert_bool(code.contains("texture(sand_tex, uv * sand_scale)")).is_true()
	assert_bool(code.contains("texture(cracked_tex, uv * 0.8)")).is_true()
	# the Level Editor's World card offers the five, the default pass 81's
	var fields := _repo_file("tools/level_editor/fields.js")
	assert_bool(fields.contains("{ key: 'sand', group: 'World', label: 'Sand', type: 'select', def: 'pass81'")).is_true()
	for id: String in RED_CANYON.SANDS:
		assert_bool(fields.contains("{ v: '%s'," % id)).override_failure_message("fields.js lacks " + id).is_true()
