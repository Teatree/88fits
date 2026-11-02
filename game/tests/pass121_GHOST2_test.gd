extends GdUnitTestSuite

## Pass 121, lane GHOST2 (Garry: "Ghost is awful looking. Make it more ghost looking. No clothing. Like a regular ghost
## with minimal facial features."): the Undertaker's Shovel's ghost painted again as a plain sheet ghost (tools/gen_ghost.py):
## - the front shows a face (two dark eyes) inside its outline, the back none;
## - its tail fades out: params.grave `ghost_fade` (the bottom share of its picture) down to `ghost_fade_min` of its alpha,
##   handed to its painting's see-through pass (sprite_billboard_over's ghost_fade), off (0) for every other painting.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var fx = null
var paused := false
"""


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	Run.sim_mode = false


func after_test() -> void:
	Run.sim_mode = false
	Run.end()


func _grave() -> Dictionary:
	var p: PassiveDef = Registry.passive("undertakers_shovel")
	return p.params.get("grave", {})


func _image(key: String) -> Image:
	var path := ProjectSettings.globalize_path("res://content/passives/undertakers_shovel/" + str(_grave().get(key, "")))
	var img := Image.load_from_file(path)
	assert_object(img).override_failure_message(path).is_not_null()
	return img


## Dark pixels well inside the figure in the top `share` of its rows (its eyes and mouth): a dark pixel counts when the
## picture is opaque `inset` pixels away from it in all four directions, so the outline round the edge never does.
func _face_pixels(img: Image, share: float, inset: int) -> int:
	var top := -1
	var bottom := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	var n := 0
	var last := mini(top + int(float(bottom - top) * share), img.get_height() - inset - 1)
	for y in range(maxi(top, inset), last):
		for x in range(inset, img.get_width() - inset):
			var c := img.get_pixel(x, y)
			if c.a <= 0.5 or c.get_luminance() >= 0.25:
				continue
			if img.get_pixel(x - inset, y).a > 0.5 and img.get_pixel(x + inset, y).a > 0.5 					and img.get_pixel(x, y - inset).a > 0.5 and img.get_pixel(x, y + inset).a > 0.5:
				n += 1
	return n


func test_the_front_has_a_face_and_the_back_none() -> void:
	var front := _image("ghost_front")
	var back := _image("ghost_back")
	assert_int(front.get_width()).is_equal(256)
	assert_int(back.get_width()).is_equal(256)
	# two hollow eyes: a few hundred dark pixels inside the head
	assert_int(_face_pixels(front, 0.4, 10)).is_greater(80)
	# seen from behind: nothing dark inside the outline
	assert_int(_face_pixels(back, 0.4, 10)).is_less(10)


func test_its_tail_fades_out_by_the_items_data() -> void:
	var g := _grave()
	var span := float(g.get("ghost_fade", 0.0))
	var floor_a := float(g.get("ghost_fade_min", 0.0))
	assert_float(span).is_greater(0.0)
	assert_float(span).is_less(1.0)
	assert_float(floor_a).is_greater_equal(0.0)
	assert_float(floor_a).is_less(1.0)
	assert_float(float(g.get("ghost_alpha", 0.0))).is_between(0.5, 1.0)
	# the ghost Graveyard makes carries them on its see-through pass
	var c: CharacterDef = Registry.character("drifter")
	Run.start(c, Registry.map("red_canyon"))
	Run.add_or_level_passive("undertakers_shovel")
	var s := GDScript.new()
	s.source_code = FAKE_GAME
	s.reload()
	var game: Node = auto_free(Node.new())
	game.set_script(s)
	add_child(game)
	var gy := Graveyard.new()
	game.add_child(gy)
	gy.setup(game)
	var ghost: BillboardSprite = gy._make_ghost()
	assert_object(ghost).is_not_null()
	assert_float(float(ghost._over.get_shader_parameter("ghost_fade"))).is_equal_approx(span, 0.0001)
	assert_float(float(ghost._over.get_shader_parameter("ghost_fade_min"))).is_equal_approx(floor_a, 0.0001)


func test_no_other_painting_fades() -> void:
	# the uniform is off by default, and a painting that never asks keeps it unset
	var src := (load("res://core/shaders/sprite_billboard_over.gdshader") as Shader).code
	assert_str(src).contains("uniform float ghost_fade = 0.0;")
	var b: BillboardSprite = auto_free(BillboardSprite.new())
	add_child(b)
	b.enable_over_trails()
	assert_object(b._over.get_shader_parameter("ghost_fade")).is_null()
