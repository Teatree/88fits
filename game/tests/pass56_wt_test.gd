extends GdUnitTestSuite

## Pass 56, lane WT (Garry: "Hero for some reason walks on water, they are not submerged at all for some reason. Should be
## submerged like all the enemies"): the oasis is a see-through disc drawn at priority -10 that tints the lower half of
## every painting that wades, and the hero's second pass (pass 49, drawn after it so his speed trails go under him)
## painted his whole figure over it again. That pass now leaves out what the water's disc covers on his first pass
## (core/shaders/sprite_billboard_over, BillboardSprite.set_water), handed over every frame by Game._sink_hero from the
## map's water_disc; his first pass and every creature's painting are drawn as before.
## The fix round: his outline where something hides him (core/shaders/sprite_silhouette) leaves out the same pixels, and
## the blob shadows (his and the creatures') go wherever the drawn disc covers any of them, not only past in_water's edge
## (BillboardSprite.water_covers_blob, Game._sink_hero, EnemyManager.shadow_wet): they lay on the water as dark plates in
## the band at the shore.

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

## a creature crowd's game and hero (pass54_combat_test's): EnemyManager reads the game's `map` for the lake
const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const DT := 1.0 / 60.0
const DISC := Vector4(10.0, 0.04, 0.0, 4.24)
## the fake lake's in_water edge and the drawn disc's
const WET_EDGE := 4.08
const DISC_R := 4.24
## the hero's blob as Player._process draws it on the ground (Player.tscn's 1.4 m quad at 0.9, 0.7 of that deep): it
## reaches 0.63 m across the screen (east and west of him, facing north) and 0.441 m up and down it
const HERO_SHADOW := Vector3(0.9, 1.0, 0.63)
const HERO_REACH := 0.63
const HERO_DEPTH := 0.441
## a bank still under the water's top face (the lake bed rises to the sand well past the disc's edge)
const BANK_Y := -0.37


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
	p.shadow.scale = HERO_SHADOW
	game.player = p
	game._ripple_t = 0.2
	return {"game": game, "hero": p, "map": m}


## A creature crowd on the fake lake's map, its ground a bank `ground` under the water's top face everywhere.
func _crowd(ground: float) -> EnemyManager:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var m: MapBase = MapBase.new()
	m.set_script(_script(FAKE_LAKE_MAP))
	g.add_child(m)
	g.map = m
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = hero
	add_child(em)
	em.height_fn = func(_x: float, _z: float) -> float: return ground
	em.colour_after_kills = 999999
	g.enemies = em
	return em


## A skeleton standing at (x, z) on the crowd's ground, past its spawn pop.
func _skeleton(em: EnemyManager, x: float, z: float) -> int:
	var i := em.spawn("skeleton", Vector3(x, 0.0, z))
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	# at its JSON's size: the variance's size jitter (always on) had made the 0.45 m bank check flaky in the full suite
	em.size[i] = Registry.enemy("skeleton").size
	return i


## How many blob shadows the crowd draws now.
func _shadows(em: EnemyManager) -> int:
	em._render()
	return em._shadow_mm.visible_instance_count


func _over_water(p: Player) -> Vector4:
	var v: Variant = p.sprite._over.get_shader_parameter("water")
	return v if v is Vector4 else Vector4.ZERO


func _sil_water(s: BillboardSprite) -> Vector4:
	var v: Variant = s._sil.get_shader_parameter("water")
	return v if v is Vector4 else Vector4.ZERO


## Where the run's fixed camera stands for a hero at `at` (CameraRig._update: 46 degrees down, 22.5 m x zoom back, the
## focus 3.3 m north of him).
static func _camera_for(at: Vector3, zoom: float) -> Vector3:
	var pitch := deg_to_rad(46.0)
	var d := 22.5 * zoom
	return Vector3(at.x, at.y, at.z - 3.3) + Vector3(0.0, sin(pitch) * d, cos(pitch) * d)


## A round blob's half-axes (`r` metres every way), and an oval's (`a` across the screen, `b` up and down it).
static func _round(r: float) -> Array:
	return [Vector3(r, 0, 0), Vector3(0, 0, r)]


## The hero's blob's half-axes as drawn now (Player.tscn's quad, his shadow node's basis).
static func _hero_axes(hero: Player) -> Array:
	var b: Basis = hero.shadow.global_transform.basis
	var half: Vector2 = (hero.shadow.mesh as QuadMesh).size * 0.5
	return [b.x * half.x, b.z * half.y]


static func _covers(at: Vector3, axes: Array, cam: Vector3, disc: Vector4) -> bool:
	return BillboardSprite.water_covers_blob(at, axes[0], axes[1], cam, disc, 0.08)


## A camera a kilometre straight above the fake lake, so the hero's and the crowd's tests see it as from straight above
## (whatever camera an earlier suite left in the tree).
func _top_camera() -> Camera3D:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.global_position = Vector3(10, 1000, 0)
	cam.make_current()
	return cam


## A camera drawing the scene from the run's place for a hero at `at` (the one the hero's and the crowd's viewport use).
func _run_camera(at: Vector3) -> Camera3D:
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.global_position = _camera_for(at, 1.0)
	cam.look_at(Vector3(at.x, at.y, at.z - 3.3))
	cam.make_current()
	return cam


# ---------------------------------------------------------------- the shaders

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


func test_the_outline_leaves_out_what_the_water_covers_with_the_same_test() -> void:
	# his outline where a creature or a prop hides him is drawn after the water as well: the over pass's very test
	var sil: String = (load("res://core/shaders/sprite_silhouette.gdshader") as Shader).code
	var over: String = (load("res://core/shaders/sprite_billboard_over.gdshader") as Shader).code
	for line in ["uniform vec4 water = vec4(0.0, -1000.0, 0.0, 0.0);", "uniform float water_thick = 0.08;",
			"varying vec3 v_world;", "v_world = world;", "if (water.w > 0.0 && v_world.y < water.y)",
			"vec2 at_top = cam.xz + run * ((cam.y - water.y) / drop);",
			"vec2 at_rim = cam.xz + run * ((cam.y - max(v_world.y, water.y - water_thick)) / drop);",
			"if (distance(at_top, water.xz) < water.w || distance(at_rim, water.xz) < water.w) {"]:
		assert_bool(sil.contains(line)).override_failure_message("the outline lacks: " + line).is_true()
		assert_bool(over.contains(line)).override_failure_message("the over pass lacks: " + line).is_true()
	# the outline's world point is the painting's own (no pull), and the test runs before the rim is worked out
	assert_int(sil.find("v_world = world;")).is_less(sil.find("VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;"))
	assert_int(sil.find("discard;")).is_less(sil.find("float rim ="))
	# still the outline: drawn where something stands in front of him
	assert_str(sil).contains("depth_test_inverted")


func test_the_first_pass_knows_no_water_and_only_the_later_passes_get_it() -> void:
	# his first pass is drawn as before and the water covers it as it covers a creature's painting
	var first: String = (load("res://core/shaders/sprite_billboard.gdshader") as Shader).code
	assert_bool(first.contains("uniform vec4 water")).override_failure_message("the first pass reads the water").is_false()
	# a sprite with the water: the outline and the second pass have it, the first pass does not
	var s := _sprite()
	s.set_water(Vector2(10, 0), 0.04, 4.24, 0.08)
	var first_mat := s.material_override as ShaderMaterial
	assert_object(first_mat).is_same(s._mat)
	assert_object(first_mat.get_shader_parameter("water")).is_null()
	assert_bool(_sil_water(s).is_equal_approx(DISC)).is_true()
	assert_float(float(s._sil.get_shader_parameter("water_thick"))).is_equal_approx(0.08, 0.0001)
	assert_int(first_mat.render_priority).is_equal(0)
	assert_int(s._sil.render_priority).is_equal(0)
	assert_int(s._over.render_priority).is_equal(BillboardSprite.OVER_PRIORITY)
	# the chain is pass 49's
	assert_object(first_mat.next_pass).is_same(s._sil)
	assert_object(s._sil.next_pass).is_same(s._over)


# ---------------------------------------------------------------- BillboardSprite

func test_set_water_hands_the_disc_to_the_later_passes_and_clear_takes_it_back() -> void:
	var s := _sprite()
	assert_bool(s.has_water()).is_false()
	s.set_water(Vector2(10, 0), 0.04, 4.24, 0.08)
	assert_bool(s.has_water()).is_true()
	assert_bool(s.water().is_equal_approx(DISC)).is_true()
	assert_bool((s._over.get_shader_parameter("water") as Vector4).is_equal_approx(DISC)).is_true()
	assert_float(float(s._over.get_shader_parameter("water_thick"))).is_equal_approx(0.08, 0.0001)
	assert_bool(_sil_water(s).is_equal_approx(DISC)).is_true()
	s.clear_water()
	assert_bool(s.has_water()).is_false()
	assert_float((s._over.get_shader_parameter("water") as Vector4).w).is_equal(0.0)
	assert_float(_sil_water(s).w).is_equal(0.0)
	# the shaders' own default is no water as well (passes that were never handed one)
	var fresh := _sprite()
	assert_object(fresh._over.get_shader_parameter("water")).is_null()
	assert_object(fresh._sil.get_shader_parameter("water")).is_null()


func test_the_water_reaches_passes_made_later_and_outlives_a_new_look() -> void:
	var s: BillboardSprite = auto_free(BillboardSprite.new())
	add_child(s)
	s.set_water(Vector2(10, 0), 0.04, 4.24, 0.08)
	# no outline and no second pass yet: kept, and given to each when it is made
	assert_object(s._sil).is_null()
	assert_object(s._over).is_null()
	s.enable_outline()
	assert_bool(_sil_water(s).is_equal_approx(DISC)).is_true()
	s.enable_over_trails()
	assert_bool((s._over.get_shader_parameter("water") as Vector4).is_equal_approx(DISC)).is_true()
	# a new painting (the arena's look chips, another hero) keeps it
	s.setup(PlaceholderArt.character_strip(null), {"idle": 2, "run": 4}, ["idle", "run"], 1.9)
	assert_bool((s._over.get_shader_parameter("water") as Vector4).is_equal_approx(DISC)).is_true()
	assert_bool(_sil_water(s).is_equal_approx(DISC)).is_true()


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


func test_a_blob_goes_wherever_the_disc_covers_any_of_it() -> void:
	var no_cam := Vector3.INF
	var bank := BANK_Y + 0.03
	var r5 := _round(0.5)
	# seen from straight above: the disc's radius plus the blob's own, while the blob lies under the disc's top
	assert_bool(_covers(Vector3(10 + DISC_R - 0.1, bank, 0), r5, no_cam, DISC)).is_true()
	assert_bool(_covers(Vector3(10 + DISC_R + 0.45, bank, 0), r5, no_cam, DISC)).is_true()
	assert_bool(_covers(Vector3(10 + DISC_R + 0.55, bank, 0), r5, no_cam, DISC)).is_false()
	# a blob on a bank above the water's top is drawn over whatever lies under it, the water's edge too
	assert_bool(_covers(Vector3(10 + DISC_R + 0.2, 0.1, 0), r5, no_cam, DISC)).is_false()
	# no disc, no water
	assert_bool(_covers(Vector3(10, bank, 0), r5, no_cam, Vector4.ZERO)).is_false()
	# an oval (wide across the screen, shallow up and down it, as every blob is drawn) reaches the water with its long
	# side on the east shore and its short side on the north one
	var oval := [Vector3(0.5, 0, 0), Vector3(0, 0, 0.3)]
	assert_bool(_covers(Vector3(10 + DISC_R + 0.45, bank, 0), oval, no_cam, DISC)).is_true()
	assert_bool(_covers(Vector3(10, bank, -(DISC_R + 0.25)), oval, no_cam, DISC)).is_true()
	assert_bool(_covers(Vector3(10, bank, -(DISC_R + 0.35)), oval, no_cam, DISC)).is_false()
	# turned a quarter (the hero's turns with him), the other way round
	var turned := [Vector3(0, 0, 0.5), Vector3(-0.3, 0, 0)]
	assert_bool(_covers(Vector3(10 + DISC_R + 0.35, bank, 0), turned, no_cam, DISC)).is_false()
	assert_bool(_covers(Vector3(10, bank, -(DISC_R + 0.45)), turned, no_cam, DISC)).is_true()
	# from the run's camera (the hero in the middle of the lake): on the far shore the bank shows through the water, so
	# a blob further out than the disc and its own reach is still under it ...
	var cam := _camera_for(Vector3(10, -0.41, 0), 1.0)
	var r48 := _round(0.48)
	var north := Vector3(10, bank, -(DISC_R + 0.48 + 0.25))
	assert_bool(_covers(north, r48, cam, DISC)).is_true()
	assert_bool(_covers(north, r48, no_cam, DISC)).is_false()
	# ... and on the near shore the line of sight passes under the disc's rim to a blob reaching a little under it
	var south := Vector3(10, bank, DISC_R + 0.48 - 0.1)
	assert_bool(_covers(south, r48, cam, DISC)).is_false()
	assert_bool(_covers(south, r48, no_cam, DISC)).is_true()
	# well under it on either shore, always
	assert_bool(_covers(Vector3(10, bank, DISC_R - 0.3), r48, cam, DISC)).is_true()
	assert_bool(_covers(Vector3(10, bank, -(DISC_R - 0.3)), r48, cam, DISC)).is_true()


# ---------------------------------------------------------------- Game._sink_hero

func test_in_the_water_he_gets_the_disc_and_out_of_it_his_pass_is_whole_at_once() -> void:
	var w := _game(FAKE_LAKE_MAP)
	var game: Game = w["game"]
	var hero: Player = w["hero"]
	assert_bool(hero.sprite.has_water()).is_false()
	# wading in the middle: the map's disc, on the second pass and the outline, never the first pass
	game._tick_water(DT)
	assert_bool(hero.sprite.has_water()).is_true()
	assert_bool(_over_water(hero).is_equal_approx(DISC)).is_true()
	assert_bool(_sil_water(hero.sprite).is_equal_approx(DISC)).is_true()
	assert_float(float(hero.sprite._over.get_shader_parameter("water_thick"))).is_equal_approx(0.08, 0.0001)
	assert_object(hero.sprite._mat.get_shader_parameter("water")).is_null()
	# one frame and he is far up the bank: his whole painting again, that very frame (the ripples' clock has not run out)
	hero.global_position = Vector3(10 + 4.24 + Game.WADE_REACH + 0.1, 0.0, 0)
	game._tick_water(DT)
	assert_float(game._ripple_t).is_greater(0.0)
	assert_bool(hero.sprite.has_water()).is_false()
	assert_float(_over_water(hero).w).is_equal(0.0)
	assert_float(_sil_water(hero.sprite).w).is_equal(0.0)
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
	# a map that says "in the water" but draws no disc: nothing to leave out, and no shadow while he wades (pass 54)
	var dry := _game(FAKE_DRY_MAP)
	(dry["game"] as Game)._tick_water(DT)
	assert_bool((dry["hero"] as Player).sprite.has_water()).is_false()
	assert_bool((dry["hero"] as Player).shadow.visible).is_false()
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
	assert_bool(hero.shadow.visible).is_true()


func test_his_shadow_goes_wherever_the_drawn_water_covers_it_and_comes_back_at_once() -> void:
	var w := _game(FAKE_LAKE_MAP)
	_top_camera()
	var game: Game = w["game"]
	var hero: Player = w["hero"]
	var m: MapBase = w["map"]
	# wading: none (pass 54)
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_false()
	# in the band between in_water's edge and the drawn disc's: in_water says dry, the disc lies over his blob
	var band := Vector3(10 + (WET_EDGE + DISC_R) * 0.5, BANK_Y, 0)
	assert_bool(bool(m.call("in_water", band))).is_false()
	hero.global_position = band
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_false()
	# past the disc's edge with his blob still reaching under it (no camera here: seen from straight above)
	hero.global_position = Vector3(10 + DISC_R + HERO_REACH - 0.1, BANK_Y, 0)
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_false()
	# a step further, clear of it: back that very frame (the ripples' clock has not run out)
	hero.global_position = Vector3(10 + DISC_R + HERO_REACH + 0.1, BANK_Y, 0)
	game._tick_water(DT)
	assert_float(game._ripple_t).is_greater(0.0)
	assert_bool(hero.shadow.visible).is_true()
	# and gone again the frame he steps back
	hero.global_position = band
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_false()
	# a bank above the water's top: his blob lies over the water's edge, as on any slope
	hero.global_position = Vector3(10 + DISC_R + 0.2, 0.1, 0)
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_true()
	# thrown up over the lake: none, as before (it rides with him over the water)
	hero.global_position = Vector3(10, 1.2, 0)
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_false()
	# the spawn beam keeps its own say
	hero.global_position = Vector3(10 + DISC_R + HERO_REACH + 0.1, BANK_Y, 0)
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_true()
	hero.cinematic = true
	hero.global_position = band
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_true()


func test_from_the_run_camera_his_shadow_goes_on_the_far_bank_the_water_covers() -> void:
	var w := _game(FAKE_LAKE_MAP)
	var game: Game = w["game"]
	var hero: Player = w["hero"]
	# on the north bank, past the disc and his blob's reach (its shallow side faces the water there): from straight
	# above nothing of it is under the disc, but the camera looks down across the water at it, and the water's top lies
	# between them
	var north := Vector3(10, BANK_Y, -(DISC_R + HERO_DEPTH + 0.15))
	hero.global_position = north
	_run_camera(north)
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_false()
	assert_bool(_covers(hero.shadow.global_position, _hero_axes(hero), Vector3.INF, DISC)).is_false()
	# on the south bank with his blob reaching a little under the disc's edge: the line of sight passes under the rim,
	# nothing covers it, so it stays
	var south := Vector3(10, BANK_Y, DISC_R + HERO_DEPTH - 0.1)
	hero.global_position = south
	_run_camera(south)
	game._tick_water(DT)
	assert_bool(hero.shadow.visible).is_true()
	assert_bool(_covers(hero.shadow.global_position, _hero_axes(hero), Vector3.INF, DISC)).is_true()


# ---------------------------------------------------------------- the creatures' shadows, the same rule

func test_a_creature_s_shadow_goes_where_the_drawn_water_covers_it() -> void:
	var em := _crowd(BANK_Y)
	_top_camera()
	var wet := _skeleton(em, 10.0, 0.0)
	var band := _skeleton(em, 10 + (WET_EDGE + DISC_R) * 0.5, 0.0)
	var reach := _skeleton(em, 10 + DISC_R + 0.3, 0.0)
	var dry := _skeleton(em, 10 + DISC_R + 1.5, 0.0)
	# the map's drawn water is read with its lake
	assert_bool(em._lake_refresh()).is_true()
	assert_bool(em._disc.is_equal_approx(DISC)).is_true()
	assert_float(em._disc_thick).is_equal_approx(0.08, 0.0001)
	# wading (pass 54), in the band, past the disc with the blob still under it (a skeleton's reaches 0.48 m): none
	assert_bool(em.in_lake(em.pos[band])).is_false()
	assert_int(_shadows(em)).is_equal(1)
	var xf := em.shadow_xform(dry, em._cf_tick, Vector3(-em._cf_tick.z, 0, em._cf_tick.x))
	assert_bool(em.shadow_wet(dry, xf, Vector3.INF)).is_false()
	for i in [wet, band, reach]:
		var xi := em.shadow_xform(i, em._cf_tick, Vector3(-em._cf_tick.z, 0, em._cf_tick.x))
		assert_bool(em.shadow_wet(i, xi, Vector3.INF)).is_true()
	# without the drawn water (set by hand, as pass 54's lakes) only the wader loses it
	em.set_lake(Vector2(10, 0), 4.0)
	assert_int(_shadows(em)).is_equal(3)
	# and handed the disc by hand, the same three as the map's
	em.set_lake(Vector2(10, 0), 4.0, DISC, 0.08)
	assert_int(_shadows(em)).is_equal(1)


func test_the_hero_and_a_creature_lose_their_shadows_at_the_same_spot() -> void:
	var w := _game(FAKE_LAKE_MAP)
	_top_camera()
	var game: Game = w["game"]
	var hero: Player = w["hero"]
	var em := _crowd(BANK_Y)
	assert_bool(em._lake_refresh()).is_true()
	var scf: Vector3 = em._cf_tick
	var scr := Vector3(-scf.z, 0, scf.x)
	# along the east shore, from wading to dry sand, from straight above: each one answers as the shared test does for
	# its own blob, so where both blobs reach as far they go together
	for out in [-0.5, -0.12, 0.1, 0.3, 0.45, 0.7, 1.0]:
		var x := 10.0 + DISC_R + float(out)
		hero.global_position = Vector3(x, BANK_Y, 0)
		game._tick_water(DT)
		var i := _skeleton(em, x, 0.0)
		var xf := em.shadow_xform(i, scf, scr)
		var creature_wet := em.shadow_wet(i, xf, Vector3.INF)
		var hero_wet := not hero.shadow.visible
		assert_bool(creature_wet).is_equal(_covers(xf.origin, [xf.basis.x * 0.5, xf.basis.z * 0.5], Vector3.INF, DISC) or em.in_lake(em.pos[i]))
		assert_bool(hero_wet).is_equal(_covers(hero.shadow.global_position, _hero_axes(hero), Vector3.INF, DISC) or float(out) < WET_EDGE - DISC_R)
		# across the screen both blobs reach past 0.45 m (the skeleton's 0.48, his 0.63) and neither 0.7
		if float(out) <= 0.45 or float(out) >= 0.7:
			assert_bool(creature_wet).override_failure_message("%.2f m out" % out).is_equal(hero_wet)
		em._free(i)


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
		# a little way up) or of his blob, from the run's camera close in, at its base and at its widest: well inside
		# the reach
		var d4 := Vector4(c.x, float(disc["top"]), c.y, r)
		var far := 0.0
		var far_blob := 0.0
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
					# his blob in the air (Player: 1.1 of the 0.7 m half quad)
					if BillboardSprite.water_covers_blob(feet + Vector3(0, 0.03, 0), Vector3(0.77, 0, 0), Vector3(0, 0, 0.77), cam, d4, float(disc["thick"])):
						far_blob = maxf(far_blob, out)
		assert_float(far).override_failure_message("seed %d: covered %.1f m out" % [seed, far]).is_less(Game.WADE_REACH - 1.0)
		# the shadow's test runs inside the same reach
		assert_float(far_blob).override_failure_message("seed %d: blob covered %.1f m out" % [seed, far_blob]).is_less(Game.WADE_REACH)
	Run.forced_map_seed = keep
