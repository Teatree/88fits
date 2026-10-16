extends GdUnitTestSuite

## Pass 83, lane TOTEM (Garry: "generate (with local AI ...) icons for each of the types of Upgrades that the Totem can
## give a Player. The icons should make sense as a part of the column. The top bit (above the buttons) which is the top
## of the Totem should have it's transparency fixed and look better. The idea is that the buttons represent parts of the
## column"): every gift of the pole's pool has its painted segment (256 px square, opaque: a piece of the pole), the
## crest's alpha is clean (no see-through background left round the bird), and the screen stacks crest, post, segments
## and base as one column.

const BOONS := preload("res://core/systems/TotemBoons.gd")
const SCREEN := preload("res://ui/TotemScreen.gd")

var _keep_inset := -1


func before_test() -> void:
	_keep_inset = Settings.top_inset
	Settings.top_inset = 0
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	Settings.top_inset = _keep_inset
	get_tree().paused = false
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _pool() -> Array:
	return BOONS.pool_of(Registry.structure("totem_pole"))


## The raw picture (not the imported, maybe compressed texture), so its alpha is the file's.
func _raw(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func test_every_gift_has_its_painted_segment() -> void:
	var pool := _pool()
	assert_int(pool.size()).is_greater_equal(11)
	for e: Dictionary in pool:
		var id := str(e.get("id", ""))
		var path := BOONS.icon_path({"id": id})
		assert_bool(ResourceLoader.exists(path)).override_failure_message("no segment for " + id).is_true()
		assert_object(BOONS.icon_of({"id": id})).override_failure_message(id).is_not_null()
		var img := _raw(path)
		assert_vector(Vector2(img.get_size())).override_failure_message(id).is_equal(Vector2(256, 256))
		# opaque: a piece of the pole, wood to every edge (no key, no fringe)
		img.convert(Image.FORMAT_RGBA8)
		var see_through := 0
		for y in range(0, 256, 4):
			for x in range(0, 256, 4):
				if img.get_pixel(x, y).a < 0.99:
					see_through += 1
		assert_int(see_through).override_failure_message(id + " has see-through pixels").is_equal(0)


func test_the_crest_has_clean_alpha() -> void:
	var img := _raw("res://art/ui/totem/crest.png")
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	assert_int(w).is_greater_equal(420)
	var solid := 0
	var stray := 0
	var soft := 0
	for y in range(h):
		for x in range(w):
			var a := img.get_pixel(x, y).a
			if a >= 0.98:
				solid += 1
			elif a > 0.0:
				soft += 1
				# a soft pixel is only the bird's own rim: a solid pixel within 2 px of it
				var near := false
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var xx := x + dx
						var yy := y + dy
						if xx >= 0 and yy >= 0 and xx < w and yy < h and img.get_pixel(xx, yy).a >= 0.98:
							near = true
				if not near:
					stray += 1
	assert_int(stray).override_failure_message("semi-opaque pixels away from the bird").is_equal(0)
	# a rim, not a halo: few soft pixels for the bird's size
	assert_float(float(soft) / float(maxi(solid, 1))).is_less(0.08)
	# the corners are empty (no background left)
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0)]:
		assert_float(img.get_pixelv(c).a).is_equal(0.0)


func test_the_column_reads_as_one_pole() -> void:
	var scr: TotemScreen = auto_free(SCREEN.new())
	add_child(scr)
	scr.open(_pool().slice(0, 3).map(func(e: Dictionary) -> Dictionary: return BOONS.roll(e, RandomNumberGenerator.new())),
		Registry.structure("totem_pole"), 4, 11)
	await get_tree().create_timer(0.7).timeout
	var rows: Array = scr.planks()
	var seg0: Rect2 = (rows[0].plate as Control).get_global_rect()
	var crest: Rect2 = (scr.get_node("Crest") as Control).get_global_rect()
	var post: Rect2 = (scr.get_node("Post") as Control).get_global_rect()
	var base: Rect2 = (scr.get_node("Base") as Control).get_global_rect()
	var label: Rect2 = (scr.get_node("Label") as Control).get_global_rect()
	# the crest sits on the column: centred on it, its foot behind the top segment, never into the label
	assert_float(crest.get_center().x).is_equal_approx(seg0.get_center().x, 1.0)
	assert_float(crest.end.y).is_equal_approx(seg0.position.y + SCREEN.CREST_SINK, 1.0)
	assert_float(crest.position.y).is_greater_equal(label.end.y)
	# the post runs from under the crest to the base, centred, narrower than the segments (it shows in the gaps)
	assert_float(post.get_center().x).is_equal_approx(seg0.get_center().x, 1.0)
	assert_float(post.position.y).is_less(seg0.position.y)
	assert_float(post.end.y).is_greater(base.position.y)
	assert_float(post.size.x).is_less(seg0.size.x)
	# the post is drawn under the crest, the segments and the base
	assert_int(post.size.x as int).is_equal(int(SCREEN.POST_W))
	assert_int(scr.get_node("Post").get_index()).is_less(scr.get_node("Crest").get_index())
	assert_int(scr.get_node("Post").get_index()).is_less(scr.get_node("Base").get_index())
	assert_int(scr.get_node("Post").get_index()).is_less((rows[0] as Node).get_index())
	# every segment's face fills its plate inside the ink border, the carved inset drawn over it
	for row in rows:
		assert_object(row.plate.tex).is_not_null()
		assert_float(row.plate.icon_frac * 300.0).is_equal_approx(288.0, 0.01)
		assert_object(row.carve).is_not_null()
		assert_bool((row.carve as Control).get_parent() == row.plate).is_true()
