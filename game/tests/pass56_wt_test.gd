extends GdUnitTestSuite

## Pass 56, lane WT (Garry: "Hero for some reason walks on water, they are not submerged at all for some reason. Should be
## submerged like all the enemies"): the oasis is a see-through disc drawn at priority -10 that tints the lower half of
## every painting that wades, and the hero's second pass (pass 49, drawn after it so his speed trails go under him)
## painted his whole figure over it again. That pass now leaves out what the water's disc covers on his first pass
## (core/shaders/sprite_billboard_over, BillboardSprite.set_water), handed over every frame by Game._sink_hero from the
## map's water_disc; his first pass, his outline and every creature are drawn as before.

## a map with a lake as RedCanyon names it: a 4 m lake at (10, 0), its disc 6% wider, its top face 4 cm over the level
const FAKE_LAKE_MAP := """extends MapBase
func lake_center() -> Vector2:
	return Vector2(10, 0)
func lake_radius() -> float:
	return 4.0
func in_water(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(Vector2(10, 0)) < 4.0 * 1.02
func water_level() -> float:
	return 0.0
func water_disc() -> Dictionary:
	return {"center": Vector2(10, 0), "top": 0.04, "radius": 4.24, "thick": 0.08}
"""

## a map that knows where the hero stands in the water but draws no disc (an old map): nothing to leave out
const FAKE_DRY_MAP := """extends MapBase
func in_water(_p: Vector3) -> bool:
	return true
"""

const DT := 1.0 / 60.0
const DISC := Vector4(10.0, 0.04, 0.0, 4.24)


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()


## The hero's painting as Player sets it up: the first pass, the outline where props hide him, the pass over his trails.
func _sprite() -> BillboardSprite:
	var s: BillboardSprite = auto_free(BillboardSprite.new())
	s.enable_outline()
	s.enable_over_trails()
	add_child(s)
	return s


## A bare Game (no scene) with the real hero from his scene and a map, the ripples' clock part way through its 0.28 s.
func _game(map_src: String) -> Dictionary:
	var game: Game = auto_free(Game.new())
	var m: MapBase = auto_free(MapBase.new())
	m.set_script(_script(map_src))
	add_child(m)
	game.map = m
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("drifter"))
	p.global_position = Vector3(10, -0.41, 0)
	game.player = p
	game._ripple_t = 0.2
	return {"game": game, "hero": p, "map": m}


func _over_water(p: Player) -> Vector4:
	var v: Variant = p.sprite._over.get_shader_parameter("water")
	return v if v is Vector4 else Vector4.ZERO


## Where the run's fixed camera stands for a hero at `at` (CameraRig._update: 46 degrees down, 22.5 m x zoom back, the
## focus 3.3 m north of him).
static func _camera_for(at: Vector3, zoom: float) -> Vector3:
	var pitch := deg_to_rad(46.0)
	var d := 22.5 * zoom
	return Vector3(at.x, at.y, at.z - 3.3) + Vector3(0.0, sin(pitch) * d, cos(pitch) * d)


# ---------------------------------------------------------------- the shader

func test_the_over_pass_leaves_out_what_the_water_covers() -> void:
	var code: String = (load("res://core/shaders/sprite_billboard_over.gdshader") as Shader).code
	# the disc: x and z its centre, y its top face, w its radius, off by default (a radius of 0)
	assert_str(code).contains("uniform vec4 water = vec4(0.0, -1000.0, 0.0, 0.0);")
	assert_str(code).contains("uniform float water_thick")
	# the point on his painting before the pull towards the camera: the very point his first pass draws at the pixel
	assert_str(code).contains("varying vec3 v_world;")
	var at_world := code.find("v_world = world;")
	assert_int(at_world).is_greater(0)
	assert_int(at_world).is_less(code.find("VERTEX.xy *= z1 / z0;"))
	# the fragment: under the top face, where the line from the camera crosses the top face or the rim inside the disc
	assert_str(code).contains("if (water.w > 0.0 && v_world.y < water.y)")
	assert_str(code).contains("CAMERA_POSITION_WORLD")
	assert_str(code).contains("distance(at_top, water.xz) < water.w || distance(at_rim, water.xz) < water.w")
	assert_str(code).contains("max(v_world.y, water.y - water_thick)")
	# and still the pass of pass 49: in the see-through queue, pulled towards the camera, his whole painting elsewhere
	assert_str(code).contains("depth_draw_never, blend_mix")
	assert_str(code).contains("uniform float pull = 0.08;")


func test_the_first_pass_the_outline_and_the_creatures_know_no_water() -> void:
	# his first pass is drawn as before and the water covers it as it covers a creature; the outline and the creatures'
	# paintings are untouched
	for path in ["res://core/shaders/sprite_billboard.gdshader", "res://core/shaders/sprite_silhouette.gdshader", "res://core/shaders/enemy_billboard.gdshader"]:
		var code: String = (load(path) as Shader).code
		assert_bool(code.contains("water")).override_failure_message(path + " reads the water").is_false()
		assert_bool(code.contains("v_world")).override_failure_message(path).is_false()
	var first: String = (load("res://core/shaders/sprite_billboard.gdshader") as Shader).code
	assert_str(first).contains("render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_opaque;")
	assert_str(first).contains("stencil_mode write, compare_always, 1;")
	# a sprite with the water: only the second pass has it
	var s := _sprite()
	s.set_water(Vector2(10, 0), 0.04, 4.24, 0.08)
	var first_mat := s.material_override as ShaderMaterial
	assert_object(first_mat).is_same(s._mat)
	assert_object(first_mat.get_shader_parameter("water")).is_null()
	assert_object(s._sil.get_shader_parameter("water")).is_null()
	assert_int(first_mat.render_priority).is_equal(0)
	assert_int(s._sil.render_priority).is_equal(0)
	assert_int(s._over.render_priority).is_equal(BillboardSprite.OVER_PRIORITY)
	# the chain is pass 49's
	assert_object(first_mat.next_pass).is_same(s._sil)
	assert_object(s._sil.next_pass).is_same(s._over)


# ---------------------------------------------------------------- BillboardSprite

func test_set_water_hands_the_disc_to_the_second_pass_and_clear_takes_it_back() -> void:
	var s := _sprite()
	assert_bool(s.has_water()).is_false()
	s.set_water(Vector2(10, 0), 0.04, 4.24, 0.08)
	assert_bool(s.has_water()).is_true()
	assert_bool(s.water().is_equal_approx(DISC)).is_true()
	assert_bool((s._over.get_shader_parameter("water") as Vector4).is_equal_approx(DISC)).is_true()
	assert_float(float(s._over.get_shader_parameter("water_thick"))).is_equal_approx(0.08, 0.0001)
	s.clear_water()
	assert_bool(s.has_water()).is_false()
	assert_float((s._over.get_shader_parameter("water") as Vector4).w).is_equal(0.0)
	# the shader's own default is no water as well (a pass that was never handed one)
	var fresh := _sprite()
	assert_object(fresh._over.get_shader_parameter("water")).is_null()


func test_the_water_reaches_a_pass_made_later_and_outlives_a_new_look() -> void:
	var s: BillboardSprite = auto_free(BillboardSprite.new())
	add_child(s)
	s.set_water(Vector2(10, 0), 0.04, 4.24, 0.08)
	# no second pass yet: kept, and given to it when it is made
	assert_object(s._over).is_null()
	s.enable_outline()
	s.enable_over_trails()
	assert_bool((s._over.get_shader_parameter("water") as Vector4).is_equal_approx(DISC)).is_true()
	# a new painting (the arena's look chips, another hero) keeps it
	s.setup(PlaceholderArt.character_strip(null), {"idle": 2, "run": 4}, ["idle", "run"], 1.9)
	assert_bool((s._over.get_shader_parameter("water") as Vector4).is_equal_approx(DISC)).is_true()


func test_the_water_test_covers_what_the_disc_covers() -> void:
	# the run's camera for a hero on the lake bed of a disc at the origin (radius 6, top face at 0, a rim 8 cm deep)
	var disc := Vector4(0.0, 0.0, 0.0, 6.0)
	var cam := _camera_for(Vector3(0, -0.45, 0), 1.0)
	# in the middle, under the surface: covered; above it: never
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.3, 0), cam, disc, 0.08)).is_true()
	assert_bool(BillboardSprite.water_covers(Vector3(0, 0.05, 0), cam, disc, 0.08)).is_false()
	# no disc: nothing
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.3, 0), cam, Vector4(0, 0, 0, 0), 0.08)).is_false()
	# just past the north edge (away from the camera) on a bank still under the surface: the disc lies between the
	# camera and his feet and covers them, as it covers a creature's there
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.37, -6.2), cam, disc, 0.08)).is_true()
	# further out the line from the camera comes down past the disc
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.37, -7.0), cam, disc, 0.08)).is_false()
	# just inside the south edge (towards the camera): the rim covers what its 8 cm reach, and the line to a deeper
	# point passes under the disc's edge, where no water is drawn over a creature either
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.07, 5.98), cam, disc, 0.08)).is_true()
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.2, 5.95), cam, disc, 0.08)).is_true()
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.4, 5.9), cam, disc, 0.08)).is_false()
	# on the sand south of the lake: nothing
	assert_bool(BillboardSprite.water_covers(Vector3(0, -0.2, 7.0), cam, disc, 0.08)).is_false()


# ---------------------------------------------------------------- Game._sink_hero

func test_in_the_water_he_gets_the_disc_and_out_of_it_his_pass_is_whole_at_once() -> void:
	var w := _game(FAKE_LAKE_MAP)
	var game: Game = w["game"]
	var hero: Player = w["hero"]
	assert_bool(hero.sprite.has_water()).is_false()
	# wading in the middle: the map's disc, on the second pass only
	game._tick_water(DT)
	assert_bool(hero.sprite.has_water()).is_true()
	assert_bool(_over_water(hero).is_equal_approx(DISC)).is_true()
	assert_float(float(hero.sprite._over.get_shader_parameter("water_thick"))).is_equal_approx(0.08, 0.0001)
	assert_object(hero.sprite._mat.get_shader_parameter("water")).is_null()
	# one frame and he is far up the bank: his whole painting again, that very frame (the ripples' clock has not run out)
	hero.global_position = Vector3(10 + 4.24 + Game.WADE_REACH + 0.1, 0.0, 0)
	game._tick_water(DT)
	assert_float(game._ripple_t).is_greater(0.0)
	assert_bool(hero.sprite.has_water()).is_false()
	assert_float(_over_water(hero).w).is_equal(0.0)
	# and back in: under the water that very frame
	hero.global_position = Vector3(11, -0.41, 1)
	game._tick_water(DT)
	assert_float(game._ripple_t).is_greater(0.0)
	assert_bool(hero.sprite.has_water()).is_true()


func test_the_disc_reaches_past_the_wet_edge_so_he_keeps_it_there() -> void:
	var w := _game(FAKE_LAKE_MAP)
	var game: Game = w["game"]
	var hero: Player = w["hero"]
	var m: MapBase = w["map"]
	# just past the north rim of the disc, on a bank still under the surface: in_water says dry, the disc still covers
	# his feet from the camera, so his second pass keeps the water and leaves them out
	var at := Vector3(10, -0.37, -(4.24 + 0.2))
	hero.global_position = at
	assert_bool(bool(m.call("in_water", at))).is_false()
	game._tick_water(DT)
	assert_bool(hero.sprite.has_water()).is_true()
	assert_bool(BillboardSprite.water_covers(at, _camera_for(at, 1.0), hero.sprite.water(), 0.08)).is_true()
	# on the sand south of it, nearer than the reach: the disc is there, and nothing of him is under it
	var south := Vector3(10, -0.1, 4.24 + 0.8)
	hero.global_position = south
	game._tick_water(DT)
	assert_bool(hero.sprite.has_water()).is_true()
	assert_bool(BillboardSprite.water_covers(south, _camera_for(south, 1.0), hero.sprite.water(), 0.08)).is_false()


func test_no_disc_no_water_and_a_fallen_hero_stays_under() -> void:
	# a map without a lake: _tick_water does nothing and his pass stays whole
	var plain := _game("extends MapBase\n")
	(plain["game"] as Game)._tick_water(DT)
	assert_bool((plain["hero"] as Player).sprite.has_water()).is_false()
	# a map that says "in the water" but draws no disc: nothing to leave out
	var dry := _game(FAKE_DRY_MAP)
	(dry["game"] as Game)._tick_water(DT)
	assert_bool((dry["hero"] as Player).sprite.has_water()).is_false()
	# fallen in the water: his body lies under it until he gets up
	var w := _game(FAKE_LAKE_MAP)
	var game: Game = w["game"]
	var hero: Player = w["hero"]
	game._tick_water(DT)
	assert_bool(hero.sprite.has_water()).is_true()
	hero.dead = true
	game._tick_water(DT)
	assert_bool(hero.sprite.has_water()).is_true()
	# up again somewhere else (the arena puts him back at the start): whole at once
	hero.dead = false
	hero.global_position = Vector3(40, 0, 40)
	game._tick_water(DT)
	assert_bool(hero.sprite.has_water()).is_false()


# ---------------------------------------------------------------- Red Canyon's disc

func test_red_canyon_tells_the_disc_it_draws_and_the_reach_covers_every_bank() -> void:
	var keep: int = Run.forced_map_seed
	for seed in [5, 88]:
		Run.forced_map_seed = seed
		Run.end()
		Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
		var m: MapBase = auto_free((Registry.map("red_canyon").scene as PackedScene).instantiate())
		add_child(m)
		var disc: Dictionary = m.call("water_disc")
		var lake: MeshInstance3D = m.find_child("Oasis", true, false)
		var cm := lake.mesh as CylinderMesh
		var c: Vector2 = disc["center"]
		assert_bool(c.is_equal_approx(m.call("lake_center"))).is_true()
		assert_float(float(disc["radius"])).is_equal_approx(cm.top_radius, 0.0001)
		assert_float(float(disc["thick"])).is_equal_approx(cm.height, 0.0001)
		assert_float(float(disc["top"])).is_equal_approx(lake.position.y + cm.height * 0.5, 0.0001)
		assert_float(float(disc["top"])).is_equal_approx(float(m.call("water_level")) + 0.04, 0.0001)
		# the disc reaches past the wet edge (in_water's 1.02 of the radius): a switch at that edge would stand him on
		# the water's rim
		var r: float = disc["radius"]
		assert_float(r).is_greater(float(m.call("lake_radius")) * 1.02)
		# every bank round the real lake where the disc can cover any of him (his feet line, a coat's width either side,
		# a little way up), from the run's camera close in, at its base and at its widest: well inside the reach
		var d4 := Vector4(c.x, float(disc["top"]), c.y, r)
		var far := 0.0
		for step in range(0, 31):
			var out := float(step) * 0.1
			for k in range(48):
				var a := TAU * float(k) / 48.0
				var fx := c.x + cos(a) * (r + out)
				var fz := c.y + sin(a) * (r + out)
				var feet := Vector3(fx, m.height_at(fx, fz), fz)
				for zoom in [0.5, 1.0, 2.12]:
					var cam := _camera_for(feet, zoom)
					var cam_up := Vector3(0.0, cos(deg_to_rad(46.0)), -sin(deg_to_rad(46.0)))
					for side in [-0.6, 0.0, 0.6]:
						for up in [0.0, 0.2, 0.4]:
							var p: Vector3 = feet + Vector3(side, 0, 0) + cam_up * up
							if BillboardSprite.water_covers(p, cam, d4, float(disc["thick"])):
								far = maxf(far, out)
		assert_float(far).override_failure_message("seed %d: covered %.1f m out" % [seed, far]).is_less(Game.WADE_REACH - 1.0)
	Run.forced_map_seed = keep
