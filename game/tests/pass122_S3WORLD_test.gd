## Pass 122, lane S3WORLD (Garry, 2026-11-03: the Blood Moon's sand "not as dark", the barrels "more visible on all that
## red", "maybe make fire tornadoes for the tornadoes?"). Pinned here as shapes and rules, never the tuned numbers:
## the dust devils' `hell` look (DustDevils.HELL_DEFAULTS, hell_look reads the block, config_of carries it as it is, the
## map file and JsonContent carry it), a fire-coloured TornadoFx that instantiates, reaches its shaders, glows only where
## lights are wanted, and frees; a dust devil that burns on a hell stage and not elsewhere (DustDevils.hell_now); the
## barrels' rim light off by default and on with the hell (BarrelField.set_hell, StageLook hands it over), the props'
## shader unchanged at rim 0; the stage-3 filter keeping its purpose (the creatures brighter than the ground); the
## ground's hell tint a lift (hell_add above 0); every shader the lane touched loads.
extends GdUnitTestSuite

const MAP_JSON := "res://content/maps/red_canyon/red_canyon.json"
const SHADERS := ["res://core/shaders/terrain_painted.gdshader", "res://core/shaders/water_lake.gdshader",
	"res://core/shaders/prop_billboard.gdshader", "res://core/shaders/tornado_funnel.gdshader",
	"res://core/shaders/tornado_skirt.gdshader", "res://core/shaders/tornado_debris.gdshader",
	"res://core/shaders/dust_devil_ring.gdshader", "res://core/shaders/stage_filter.gdshader"]

const FAKE_GAME := """extends Node
var map = null
var player = null
var enemies = null
var telegraphs = null
var barrels = null
var camera = null
var hud = null
var director = null
var paused := false
"""

const FAKE_MAP := """extends Node3D
var _hell := 0.0
var arena_radius := 60.0
var obstacles: Array = []
var flats_center := Vector3.ZERO
var hell_set: Array = []
func height_at(_x: float, _z: float) -> float:
	return 0.0
func set_hell(f: float, _seconds: float = 0.0) -> void:
	_hell = f
	hell_set.append(f)
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _game(hell: float) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var map := Node3D.new()
	map.set_script(_script(FAKE_MAP))
	map._hell = hell
	g.add_child(map)
	g.map = map
	return {"g": g, "map": map}


func _devil(g: Node, map: Node, block = null) -> DustDevil:
	var dd := DustDevil.new()
	dd.game = g
	dd.map = map
	dd.setup(DustDevils.config_of(block), Vector3(2, 0, 2), Vector3(1, 0, 0), 12.0, 7)
	g.add_child(dd)
	return dd


func _map_block() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON))
	var b = (d["timeline_data"] as Dictionary).get("dust_devils", {})
	return b if b is Dictionary else {}


# ---------------------------------------------------------------- the hell key

func test_the_hell_look_has_defaults_reads_the_block_and_rides_the_map() -> void:
	# the defaults: three colours and a glow, filled in for a map without the key
	for key: String in ["color", "wisps", "ring", "glow"]:
		assert_bool(DustDevils.HELL_DEFAULTS.has(key)).override_failure_message(key).is_true()
	var d := DustDevils.hell_look(null)
	for key: String in ["color", "wisps", "ring"]:
		assert_bool(d[key] is Color).override_failure_message(key).is_true()
		assert_bool((d[key] as Color).is_equal_approx(Color.html(str(DustDevils.HELL_DEFAULTS[key])))).is_true()
	assert_float(float(d["glow"])).is_equal(float(DustDevils.HELL_DEFAULTS["glow"]))
	# the fire is warm: red leads, blue trails, the wisps lighter than the fire
	assert_float((d["color"] as Color).r).is_greater((d["color"] as Color).b)
	assert_float((d["wisps"] as Color).get_luminance()).is_greater((d["color"] as Color).get_luminance())
	# a block's own keys, the rest the defaults; a bad colour or glow reads as its default; the glow is clamped
	var o := DustDevils.hell_look({"hell": {"color": "#112233", "glow": 2}})
	assert_bool((o["color"] as Color).is_equal_approx(Color.html("#112233"))).is_true()
	assert_float(float(o["glow"])).is_equal(2.0)
	assert_bool((o["wisps"] as Color).is_equal_approx(d["wisps"])).is_true()
	assert_bool((o["ring"] as Color).is_equal_approx(d["ring"])).is_true()
	var bad := DustDevils.hell_look({"hell": {"color": "nope", "wisps": 7, "glow": "x"}})
	assert_bool((bad["color"] as Color).is_equal_approx(d["color"])).is_true()
	assert_bool((bad["wisps"] as Color).is_equal_approx(d["wisps"])).is_true()
	assert_float(float(bad["glow"])).is_equal(float(DustDevils.HELL_DEFAULTS["glow"]))
	assert_float(float(DustDevils.hell_look({"hell": {"glow": 99}})["glow"])).is_equal(DustDevils.HELL_GLOW_MAX)
	assert_float(float(DustDevils.hell_look({"hell": {"glow": -3}})["glow"])).is_equal(0.0)
	# a config_of result reads the same way (the sub-block is carried as it is; a Color stays a Color)
	var c := DustDevils.config_of({"hell": {"ring": "#ABCDEF", "glow": 0}})
	assert_that(c["hell"]).is_equal({"ring": "#ABCDEF", "glow": 0})
	assert_bool((DustDevils.hell_look(c)["ring"] as Color).is_equal_approx(Color.html("#ABCDEF"))).is_true()
	assert_float(float(DustDevils.hell_look(c)["glow"])).is_equal(0.0)
	assert_bool((DustDevils.hell_look({"hell": {"color": Color.BLUE}})["color"] as Color).is_equal_approx(Color.BLUE)).is_true()
	# the Level Editor's card mirrors DEFAULTS key by key: the look stays out of it
	assert_bool(DustDevils.DEFAULTS.has("hell")).is_false()
	# the map file writes the look out with its four keys, JsonContent carries it, the Registry's timeline has it
	var mb := _map_block()
	assert_bool(mb.get("hell") is Dictionary).override_failure_message("timeline_data.dust_devils.hell is missing").is_true()
	for key: String in ["color", "wisps", "ring", "glow"]:
		assert_bool((mb["hell"] as Dictionary).has(key)).override_failure_message(key).is_true()
	var parsed := JsonContent.timeline_from_dict({"dust_devils": {"hell": {"color": "#ff0000"}}})
	assert_str(str((parsed.dust_devils["hell"] as Dictionary)["color"])).is_equal("#ff0000")
	var tl: WaveTimeline = Registry.map("red_canyon").timeline
	assert_that(tl.dust_devils.get("hell")).is_equal(mb["hell"])


# ---------------------------------------------------------------- the fire look

func test_a_fire_tornado_instantiates_reaches_its_shaders_glows_where_wanted_and_frees() -> void:
	var look := DustDevils.hell_look(null)
	var fx: TornadoFx = auto_free(TornadoFx.new())
	fx.fire = 1.0
	fx.color = look["color"]
	fx.wisp_color = look["wisps"]
	fx.glow = float(look["glow"])
	add_child(fx)
	fx.set_strength(1.0)
	fx._process(0.016)
	assert_int(fx.parts().size()).is_equal(4)
	for gi: GeometryInstance3D in fx.parts():
		var m := gi.material_override as ShaderMaterial
		assert_float(float(m.get_shader_parameter("fire"))).override_failure_message(gi.name).is_equal(1.0)
		assert_bool((m.get_shader_parameter("wisp_color") as Color).is_equal_approx(look["wisps"])).is_true()
		assert_bool((m.get_shader_parameter("color") as Color).is_equal_approx(look["color"])).is_true()
		# burning, it is drawn AFTER the stage's filter (the red glass never dims the flames), before the marks and pickups
		assert_int(m.render_priority).override_failure_message(gi.name).is_equal(TornadoFx.PRIORITY_FIRE)
	assert_int(TornadoFx.PRIORITY_FIRE).is_greater(StageLook.PRIORITY)
	assert_int(TornadoFx.PRIORITY_FIRE).is_less(EnemyManager.SHADOW_PRIORITY)
	# its embers are opaque: they write the shots' stencil instead, which the filter never darkens
	var dsh: Shader = (fx.get_node("Debris") as MultiMeshInstance3D).material_override.shader
	assert_object(dsh).is_same(TornadoFx.debris_fire_shader())
	assert_str(dsh.code).contains("stencil_mode write, compare_always, %d;" % StageStencil.CLEAR)
	# going out again: the dust order, the plain debris shader
	fx.fire = 0.0
	fx._process(0.016)
	for gi: GeometryInstance3D in fx.parts():
		assert_int((gi.material_override as Material).render_priority).is_equal(TornadoFx.PRIORITY)
	assert_object((fx.get_node("Debris") as MultiMeshInstance3D).material_override.shader).is_same(TornadoFx.DEBRIS_SHADER)
	fx.fire = 1.0
	fx._process(0.016)
	# the glow: a point light in the fire's colour only where lights are wanted, following the strength
	var light := fx.glow_light()
	if Fx.want_lights():
		assert_object(light).is_not_null()
		assert_bool(light.light_color.is_equal_approx(look["color"])).is_true()
		assert_float(light.light_energy).is_greater(0.0)
		assert_bool(light.shadow_enabled).is_false()
		fx.set_strength(0.0)
		fx._process(0.016)
		assert_float(light.light_energy).is_equal(0.0)
		assert_bool(light.visible).is_false()
	else:
		assert_object(light).is_null()
	# fire is clamped to 0..1
	fx.fire = 7.0
	assert_float(fx.fire).is_equal(1.0)
	fx.fire = -1.0
	assert_float(fx.fire).is_equal(0.0)
	# a plain one is pass 113's: no fire, no light
	var dust: TornadoFx = auto_free(TornadoFx.new())
	add_child(dust)
	dust._process(0.016)
	assert_float(dust.fire).is_equal(0.0)
	assert_object(dust.glow_light()).is_null()
	for gi: GeometryInstance3D in dust.parts():
		assert_float(float((gi.material_override as ShaderMaterial).get_shader_parameter("fire"))).is_equal(0.0)
	# the warm instance (Warmup) is the dust one
	var warm: TornadoFx = auto_free(TornadoFx.warm_instance())
	assert_float(warm.fire).is_equal(0.0)
	assert_float(warm.glow).is_equal(0.0)


func test_a_dust_devil_burns_on_a_hell_stage_and_not_elsewhere() -> void:
	var look := DustDevils.hell_look(null)
	# the map's own red says hell (the arena, a map without a stage list)
	var h := _game(1.0)
	assert_bool(DustDevils.hell_now(h["g"])).is_true()
	var dd := _devil(h["g"], h["map"])
	assert_bool(dd.burning).is_true()
	assert_float(dd.fx.fire).is_equal(1.0)
	assert_bool(dd.fx.color.is_equal_approx(look["color"])).is_true()
	assert_bool(dd.fx.wisp_color.is_equal_approx(look["wisps"])).is_true()
	assert_float(dd.fx.glow).is_equal(float(look["glow"]))
	var rm := dd.ring.material_override as ShaderMaterial
	assert_float(float(rm.get_shader_parameter("fire"))).is_equal(1.0)
	assert_bool((rm.get_shader_parameter("color") as Color).is_equal_approx(look["ring"])).is_true()
	# the ring and the funnel after the filter, the ring under the funnel
	assert_int(rm.render_priority).is_greater(StageLook.PRIORITY)
	assert_int(rm.render_priority).is_less(dd.fx.draw_priority())
	# the block's own colours reach it
	var own := _devil(h["g"], h["map"], {"hell": {"color": "#102030", "ring": "#405060", "glow": 0}})
	assert_bool(own.fx.color.is_equal_approx(Color.html("#102030"))).is_true()
	assert_float(own.fx.glow).is_equal(0.0)
	assert_object(own.fx.glow_light()).is_null()
	assert_bool(((own.ring.material_override as ShaderMaterial).get_shader_parameter("color") as Color).is_equal_approx(Color.html("#405060"))).is_true()
	# its behaviour is the dust one's: it forms, grabs and fades on the same clock
	assert_bool(dd.catching()).is_false()
	dd.step(dd.form_seconds + 0.01)
	assert_bool(dd.catching()).is_true()
	assert_float(dd.strength()).is_equal(1.0)
	# no red: the dust look, pass 113's colours, no fire anywhere
	var s := _game(0.0)
	assert_bool(DustDevils.hell_now(s["g"])).is_false()
	var plain := _devil(s["g"], s["map"])
	assert_bool(plain.burning).is_false()
	assert_float(plain.fx.fire).is_equal(0.0)
	assert_bool(plain.fx.color.is_equal_approx(DustDevil.COLOR)).is_true()
	assert_float(plain.fx.glow).is_equal(0.0)
	var pm := plain.ring.material_override as ShaderMaterial
	assert_float(float(pm.get_shader_parameter("fire"))).is_equal(0.0)
	assert_bool((pm.get_shader_parameter("color") as Color).is_equal_approx(DustDevil.COLOR)).is_true()
	# pass 113's order for the dust one: everything before the filter
	assert_int(pm.render_priority).is_less(StageLook.PRIORITY)
	for gi: GeometryInstance3D in plain.fx.parts():
		assert_int((gi.material_override as Material).render_priority).is_less(StageLook.PRIORITY)
	# a stage shown (the game's StageLook) decides before the map's red: stage 3 burns, stage 1 does not
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var sl := StageLook.new()
	sl.name = StageLook.NODE_NAME
	sl.game = s["g"]
	(s["g"] as Node).add_child(sl)
	sl.stage = 2
	assert_bool(DustDevils.hell_now(s["g"])).is_true()
	sl.stage = 0
	(h["g"] as Node).add_child(StageLook.new())
	assert_bool(DustDevils.hell_now(s["g"])).is_false()
	# nothing to read: no
	assert_bool(DustDevils.hell_now(null)).is_false()
	Run.end()


# ---------------------------------------------------------------- the barrels' rim

func _field(seed_v: int) -> Dictionary:
	Run.map_seed = seed_v
	var ms := GDScript.new()
	ms.source_code = "extends MapBase\nvar flats_radius := 16.0\nvar _hell := 0.0\nfunc set_hell(f: float, _s: float = 0.0) -> void:\n\t_hell = f\n"
	ms.reload()
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(ms)
	add_child(map)
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	g.map = map
	var field: BarrelField = auto_free(BarrelField.new())
	g.add_child(field)
	field.setup(g, map)
	g.barrels = field
	return {"g": g, "map": map, "field": field}


func test_the_barrels_rim_light_is_off_by_default_and_comes_with_the_hell() -> void:
	var f := _field(122)
	var field: BarrelField = f["field"]
	var mats := field.materials()
	assert_int(mats.size()).is_equal(BarrelField.SPRITES.size())
	for m: ShaderMaterial in mats:
		assert_float(float(m.get_shader_parameter("rim"))).is_equal(0.0)
		assert_bool((m.get_shader_parameter("rim_color") as Color).is_equal_approx(BarrelField.RIM_COLOR)).is_true()
		assert_float(float(m.get_shader_parameter("rim_width"))).is_equal(BarrelField.RIM_WIDTH)
		# still the structures' stencil (pass 105): the filter dims them at its `structures` share
		assert_str(m.shader.code).contains("stencil_mode write, compare_always, %d;" % SceneryStencil.STRUCTURE)
		assert_str(m.shader.code).contains("uniform float rim")
	assert_float(field.rim).is_equal(0.0)
	# at once (no tween): on with the hell, off again without it
	field.set_hell(1.0)
	assert_float(field.rim).is_equal(BarrelField.RIM_HELL)
	for m: ShaderMaterial in mats:
		assert_float(float(m.get_shader_parameter("rim"))).is_equal(BarrelField.RIM_HELL)
	field.set_hell(0.5)
	assert_float(field.rim).is_equal_approx(BarrelField.RIM_HELL * 0.5, 0.0001)
	field.set_hell(0.0)
	assert_float(field.rim).is_equal(0.0)
	field.set_hell(3.0)
	assert_float(field.rim).is_equal(BarrelField.RIM_HELL)
	# a tween reaches it
	field.set_hell(0.0, 0.05)
	await await_millis(200)
	assert_float(field.rim).is_equal(0.0)
	# the rim is pale (a moonlit edge), and the hell rim is on
	assert_float(BarrelField.RIM_COLOR.get_luminance()).is_greater(0.8)
	assert_float(BarrelField.RIM_HELL).is_greater(0.0)
	assert_float(BarrelField.RIM_WIDTH).is_between(0.005, 0.1)


func test_the_stage_look_hands_the_hell_to_the_map_and_the_barrels() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var tl: WaveTimeline = Run.map.timeline
	var f := _field(7)
	var g: Node = f["g"]
	var sl := StageLook.of(g)
	sl.camera = Camera3D.new()
	add_child(sl.camera)
	var third := StageLook.hell_of(tl, 2)
	# stage 3 of the map file is hell (pass 43's red ground): the map's set_hell and the barrels' rim follow it
	assert_bool(third).is_true()
	sl.show_stage(2, 0.0)
	await await_millis(150)
	assert_float(float((f["map"] as Node).get("_hell"))).is_equal(1.0)
	assert_float((f["field"] as BarrelField).rim).is_equal_approx(BarrelField.RIM_HELL, 0.0001)
	# stage 1 is not: both go back
	sl.show_stage(0, 0.0)
	await await_millis(150)
	assert_float(float((f["map"] as Node).get("_hell"))).is_equal(0.0)
	assert_float((f["field"] as BarrelField).rim).is_equal(0.0)
	sl.camera.queue_free()
	Run.end()


func test_the_props_shader_is_unchanged_at_rim_0() -> void:
	var sh: Shader = load("res://core/shaders/prop_billboard.gdshader")
	assert_str(sh.code).contains("uniform float rim : hint_range(0.0, 1.0) = 0.0;")
	# the scenery keeps its stencil and never sets the rim: a prop material reads the shader's own default
	assert_str(sh.code).contains("stencil_mode write, compare_always, %d;" % SceneryStencil.VALUE)
	var m := ShaderMaterial.new()
	m.shader = sh
	var v = m.get_shader_parameter("rim")
	assert_bool(v == null or float(v) == 0.0).is_true()
	assert_bool(FileAccess.get_file_as_string("res://core/systems/PropField.gd").contains("\"rim\"")).is_false()


# ---------------------------------------------------------------- the ground

func test_the_stage_3_filter_keeps_its_purpose_and_the_ground_tint_is_a_lift() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(MAP_JSON))
	var sl: Array = (d["timeline_data"] as Dictionary).get("stage_list", [])
	assert_int(sl.size()).is_greater_equal(3)
	var e: Dictionary = sl[2]
	assert_bool(bool(e.get("hell", false))).is_true()
	var f: Dictionary = e.get("filter", {})
	assert_bool(Color.html_is_valid(str(f.get("color", "")))).is_true()
	var k := float(f.get("strength", 0.0))
	assert_float(k).is_between(0.05, 0.95)
	# the creatures stay brighter than the ground: the actors' share under 1, the structures' too
	assert_float(StageLook.share_of(f, "actors", StageLook.ACTORS_DEFAULT)).is_less(1.0)
	assert_float(StageLook.share_of(f, "structures", StageLook.STRUCTURES_DEFAULT)).is_less(1.0)
	var m: Array = StageLook.filter_mults(e)
	for ch in range(3):
		assert_float((m[1] as Color)[ch]).override_failure_message("actors channel %d" % ch).is_greater_equal((m[0] as Color)[ch])
		assert_float((m[2] as Color)[ch]).override_failure_message("structures channel %d" % ch).is_greater_equal((m[0] as Color)[ch])
	# it is still a red glass: red leads
	var c := Color.html(str(f["color"]))
	assert_float(c.r).is_greater(c.g)
	assert_float(c.r).is_greater(c.b)
	# the terrain's hell tint is a lift now (pass 43's added nothing to green or blue): every hell_add channel above 0, the
	# mix line reads the uniforms, and the water keeps a hell line of its own
	var code: String = (load("res://core/shaders/terrain_painted.gdshader") as Shader).code
	assert_str(code).contains("col = mix(col, col * hell_mul + hell_add, hell);")
	var re := RegEx.create_from_string("uniform vec3 hell_add = vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\);")
	var r := re.search(code)
	assert_object(r).is_not_null()
	for i in range(1, 4):
		assert_float(float(r.get_string(i))).is_greater(0.0)
	var re2 := RegEx.create_from_string("uniform vec3 hell_mul = vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\);")
	var r2 := re2.search(code)
	assert_object(r2).is_not_null()
	for i in range(1, 4):
		assert_float(float(r2.get_string(i))).is_between(0.5, 1.5)
	var water: String = (load("res://core/shaders/water_lake.gdshader") as Shader).code
	assert_str(water).contains("uniform float hell")
	assert_str(water).contains("hell * 0.7")
	# the map's hell constants: a wall tint, an ambient and a haze colour, all colours
	var rc: GDScript = load("res://world/maps/red_canyon/RedCanyon.gd")
	var consts: Dictionary = rc.get_script_constant_map()
	for key: String in ["HELL_WALL", "HELL_AMBIENT", "HELL_FOG"]:
		assert_bool(consts.get(key) is Color).override_failure_message(key).is_true()


func test_every_shader_the_lane_touched_loads_with_its_uniforms() -> void:
	for path: String in SHADERS:
		var sh = load(path)
		assert_bool(sh is Shader).override_failure_message(path).is_true()
		assert_bool((sh as Shader).code.contains("shader_type spatial")).is_true()
	for path: String in ["res://core/shaders/tornado_funnel.gdshader", "res://core/shaders/tornado_skirt.gdshader",
			"res://core/shaders/tornado_debris.gdshader", "res://core/shaders/dust_devil_ring.gdshader"]:
		var code: String = (load(path) as Shader).code
		assert_str(code).override_failure_message(path).contains("uniform float fire : hint_range(0.0, 1.0) = 0.0;")
		assert_str(code).override_failure_message(path).contains("uniform vec4 wisp_color : source_color")
	# the funnel still writes the scenery's stencil and the ring none (pass 113)
	assert_str((load("res://core/shaders/tornado_funnel.gdshader") as Shader).code).contains("stencil_mode write, compare_always, %d;" % SceneryStencil.VALUE)
	assert_str((load("res://core/shaders/dust_devil_ring.gdshader") as Shader).code).not_contains("stencil_mode")
	# the store_shots tool took its tuning arguments (additive)
	var tool: String = FileAccess.get_file_as_string("res://tools/store_shots.gd")
	for word: String in ["hell_mul", "hell_add", "filter=", "barrels=", "tornado=1"]:
		assert_str(tool).contains(word)
