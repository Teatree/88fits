## Pass 56, the UI lane (Garry's twelfth list): "Make the EXP bar twice as thick, move all the other UI with it
## accordingly" (a plain fill, just twice as thick: the HUD's rail and the level-up screen's rainbow copy read one pair of
## constants, and the top row, the slots, the strip, the thumb zone and everything under them sit 18 px lower with every
## gap as it was, with or without a camera cutout), and "Change the marker for a weapon ... It should be a single
## revolver and it should look a bit more different from the scroll glyph" (one solid revolver, tools/make_kind_glyphs.py).
extends GdUnitTestSuite

## The rail before pass 56, and the top row, the slots and the strip it set.
const OLD_RAIL := 18.0
const OLD_TOP_Y := 30.0
const OLD_SLOT_Y := 126.0
const OLD_BAND_H := 220.0
const GLYPH := "res://art/ui/wanted/kind_weapon.png"
const SCROLL := "res://art/ui/wanted/kind_line.png"


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func after_test() -> void:
	Settings.top_inset = -1
	Run.arena = false
	Run.end()
	DamageNumbers.I = null
	# the next suite builds its HUD from scratch: band_h back to the strip's own height
	HUD.band_h = float(HUD.BAND_H)


## A HUD in the tree with a run's weapons on it, laid out (the top row is placed a frame after _ready).
func _hud() -> HUD:
	_start()
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	return hud


func _rail_of(n: Node) -> Control:
	return n.find_child("XpRail", false, false) as Control


# ---------------------------------------------------------------- 1. the rail, twice as thick, one constant

func test_the_rail_is_twice_as_thick_in_the_hud_and_on_the_level_up_screen() -> void:
	assert_float(HUD.RAIL_H).is_equal(2.0 * OLD_RAIL)
	# the fill keeps two thirds of it: 6 px in from the top and the bottom (3 of 18 before)
	assert_float(HUD.RAIL_INSET).is_equal(6.0)
	assert_float(HUD.RAIL_H - 2.0 * HUD.RAIL_INSET).is_equal(24.0)
	# the level-up screen's rainbow rail reads the HUD's constants: the two can never differ
	assert_float(CardScreen.RAIL_H).is_equal(HUD.RAIL_H)
	assert_float(CardScreen.RAIL_INSET).is_equal(HUD.RAIL_INSET)
	var hud := await _hud()
	var rail := _rail_of(hud)
	assert_object(rail).is_not_null()
	assert_float(rail.offset_top).is_equal(0.0)
	assert_float(rail.offset_bottom).is_equal(HUD.RAIL_H)
	assert_float(rail.size.y).is_equal(HUD.RAIL_H)
	# a plain fill (Garry: "nothing inside it"): the rail holds no nodes, it only draws its track and its fill
	assert_int(rail.get_child_count()).is_equal(0)
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	var crail := _rail_of(cs)
	assert_object(crail).is_not_null()
	cs.show_offer(CardPool.level_up_offer(3), "LEVEL 2!", false)
	await get_tree().process_frame
	assert_float(crail.offset_top).is_equal(rail.offset_top)
	assert_float(crail.offset_bottom).is_equal(rail.offset_bottom)
	assert_float(crail.size.y).is_equal(HUD.RAIL_H)
	cs.visible = false


# ---------------------------------------------------------------- 2. everything under it 18 px lower, the gaps kept

func test_the_top_row_the_slots_and_the_strip_move_down_by_what_the_rail_gained() -> void:
	var gain := HUD.RAIL_H - OLD_RAIL
	assert_float(gain).is_equal(18.0)
	assert_float(HUD.TOP_Y).is_equal(OLD_TOP_Y + gain)
	assert_float(HUD.SLOT_Y).is_equal(OLD_SLOT_Y + gain)
	assert_float(float(HUD.BAND_H)).is_equal(OLD_BAND_H + gain)
	# each is laid out from the one above it, so a thicker rail can never sit on them again
	assert_float(HUD.TOP_Y - HUD.RAIL_H).is_equal(OLD_TOP_Y - OLD_RAIL)
	assert_float(HUD.SLOT_Y - HUD.TOP_Y).is_equal(OLD_SLOT_Y - OLD_TOP_Y)
	assert_float(float(HUD.BAND_H) - HUD.SLOT_Y).is_equal(OLD_BAND_H - OLD_SLOT_Y)


func test_nothing_in_the_top_row_starts_above_the_rail_s_bottom() -> void:
	var hud := await _hud()
	var rail_foot := _rail_of(hud).get_global_rect().end.y
	assert_float(rail_foot).is_equal(HUD.RAIL_H)
	# the LV plate, the clock and the gold 12 px under the rail, the pause disc 10 px (as under the 18 px rail)
	for p: Control in [hud._lv_plate, hud._timer_plate, hud._gold_plate]:
		assert_float(p.get_global_rect().position.y).override_failure_message(str(p.get_path())).is_equal(rail_foot + 12.0)
	assert_float(hud._pause_btn.get_global_rect().position.y).is_equal(rail_foot + 10.0)
	# the top row's box from the rail's top down to 10 px over the slots; the slots 108 px under the rail
	assert_float(hud._top.offset_top).is_equal(0.0)
	assert_float(hud._top.offset_bottom).is_equal(HUD.SLOT_Y - 10.0)
	assert_float(hud._slots.position.y).is_equal(rail_foot + 108.0)
	# the slots start under the whole top row (the disc is its tallest piece)
	var row_foot := 0.0
	for p: Control in [hud._lv_plate, hud._timer_plate, hud._gold_plate, hud._pause_btn]:
		row_foot = maxf(row_foot, p.get_global_rect().end.y)
	assert_float(hud._slots.position.y).is_greater(row_foot)
	# one row of 72 px slots: the strip's foot, the boss plate, the power-ups and the toasts under it, all 18 px lower
	assert_float(hud._slots_bottom).is_equal(OLD_SLOT_Y + 18.0 + 72.0 + 6.0)
	assert_float(HUD.band_h).is_equal(float(HUD.BAND_H))
	assert_float(hud._band.offset_bottom).is_equal(HUD.band_h)
	assert_float(hud._buffs.position.y).is_equal(hud._slots_bottom + 14.0)
	assert_float(hud._boss_box.position.y).is_equal(hud._slots_bottom + 20.0)
	assert_float(hud._toasts.position.y).is_greater_equal(hud._slots_bottom)


func test_the_pause_disc_is_in_place_the_moment_the_hud_is_ready() -> void:
	# no frame between: a finger in the frame the run loads finds the disc at the row's right end, not at its corner
	_start()
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	var w := hud.get_viewport_rect().size.x
	assert_float(hud._pause_btn.position.x).is_equal(w - 36.0 - HUD.DISC)
	assert_float(hud._pause_btn.position.y).is_equal(HUD.TOP_Y - 2.0)
	assert_float(hud._gold_plate.position.y).is_equal(HUD.TOP_Y)
	assert_float(hud._gold_plate.get_global_rect().end.x).is_less_equal(hud._pause_btn.position.x - 18.0 + 0.5)


# ---------------------------------------------------------------- 3. with a camera cutout

func test_with_a_camera_cutout_the_rail_and_the_strip_sit_lower_by_the_inset() -> void:
	Settings.top_inset = 130
	var hud := await _hud()
	var rail := _rail_of(hud)
	# the ink strip down to the rail, the rail under it, every piece of the strip 130 px lower
	assert_float(hud._cutout.offset_bottom).is_equal(130.0)
	assert_float(rail.get_global_rect().position.y).is_equal(130.0)
	assert_float(rail.get_global_rect().end.y).is_equal(130.0 + HUD.RAIL_H)
	assert_float(hud._lv_plate.get_global_rect().position.y).is_equal(130.0 + HUD.TOP_Y)
	assert_float(hud._pause_btn.get_global_rect().position.y).is_equal(130.0 + HUD.TOP_Y - 2.0)
	assert_float(hud._slots.position.y).is_equal(130.0 + HUD.SLOT_Y)
	assert_float(HUD.band_h).is_equal(float(HUD.BAND_H) + 130.0)
	assert_float(hud._band.offset_bottom).is_equal(HUD.band_h)
	# the level-up screen's rail sits where the HUD's does
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	await get_tree().process_frame
	assert_float(_rail_of(cs).get_global_rect().position.y).is_equal(130.0)
	assert_float(_rail_of(cs).get_global_rect().end.y).is_equal(130.0 + HUD.RAIL_H)
	cs.visible = false


func test_the_thumb_zone_starts_under_the_strip_that_moved() -> void:
	for inset: int in [0, 130]:
		Settings.top_inset = inset
		var hud := await _hud()
		var input: PlayerInput = auto_free(PlayerInput.new())
		add_child(input)
		var k := input.get_viewport().get_visible_rect().size.x / 1080.0
		# a finger on the strip pauses, one just under it walks
		assert_bool(input._in_thumb_zone(Vector2(500, (HUD.band_h - 2.0) * k))).override_failure_message("inset %d" % inset).is_false()
		assert_bool(input._in_thumb_zone(Vector2(500, (HUD.band_h + 2.0) * k))).override_failure_message("inset %d" % inset).is_true()
		# the slots' row (the strip's lowest part) is still the strip's
		assert_bool(input._in_thumb_zone(Vector2(500, (hud._slots_bottom - 2.0) * k))).is_false()
		hud.queue_free()
		input.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------- 4. the weapon's glyph: one solid revolver

## The glyph's picture (the PNG the tool writes; the import is the lead's).
func _glyph(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert_object(img).is_not_null()
	return img


## The ink pixels (alpha at least half) of a square glyph picture, as a flat array of bools.
static func _ink_of(img: Image) -> Array:
	var n := img.get_width()
	var out: Array = []
	out.resize(n * n)
	for y in n:
		for x in n:
			out[y * n + x] = img.get_pixel(x, y).a >= 0.5
	return out


func _ink(path: String) -> Array:
	var img := _glyph(path)
	assert_int(img.get_width()).is_equal(64)
	assert_int(img.get_height()).is_equal(64)
	return _ink_of(img)


## The sizes of the 8-connected ink shapes of an n x n mask, largest first.
static func _shapes(ink: Array) -> Array:
	var n := int(round(sqrt(float(ink.size()))))
	var seen: Array = []
	seen.resize(ink.size())
	seen.fill(false)
	var sizes: Array = []
	for i in ink.size():
		if not ink[i] or seen[i]:
			continue
		var stack: Array = [i]
		seen[i] = true
		var count := 0
		while not stack.is_empty():
			var c: int = stack.pop_back()
			count += 1
			var cx := c % n
			var cy := c / n
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = cx + dx
					var ny: int = cy + dy
					if nx < 0 or ny < 0 or nx >= n or ny >= n:
						continue
					var j := ny * n + nx
					if ink[j] and not seen[j]:
						seen[j] = true
						stack.append(j)
		sizes.append(count)
	sizes.sort()
	sizes.reverse()
	return sizes


## The ink's bounding box in an n x n mask: Rect2i(x, y, w, h).
static func _box(ink: Array) -> Rect2i:
	var n := int(round(sqrt(float(ink.size()))))
	var x0 := n
	var y0 := n
	var x1 := -1
	var y1 := -1
	for i in ink.size():
		if ink[i]:
			x0 = mini(x0, i % n)
			x1 = maxi(x1, i % n)
			y0 = mini(y0, i / n)
			y1 = maxi(y1, i / n)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func test_the_weapon_glyph_is_one_solid_revolver_unlike_the_scroll() -> void:
	var gun := _ink(GLYPH)
	var shapes := _shapes(gun)
	# one connected shape (the scroll's writing lines are shapes of their own)
	assert_int(shapes.size()).is_equal(1)
	# filled ink: a good part of its box is ink, and it is wider than tall (barrel to the right)
	var box := _box(gun)
	assert_int(box.size.x).is_greater(box.size.y)
	assert_int(box.size.x).is_greater_equal(56)
	assert_float(float(shapes[0]) / float(box.size.x * box.size.y)).is_greater(0.25)
	# plainly different from the scroll: the two share under half their ink
	var scroll := _ink(SCROLL)
	var both := 0
	var either := 0
	for i in gun.size():
		if gun[i] and scroll[i]:
			both += 1
		if gun[i] or scroll[i]:
			either += 1
	assert_float(float(both) / float(either)).is_less(0.5)
	assert_int(_shapes(scroll).size()).is_greater(1)


func test_the_revolver_stays_one_shape_at_the_size_the_cards_draw_it() -> void:
	# a weapon's card plate is 170 px; WPlate's disc is KIND_FRAC of it across and the glyph fills 78 % of the paper
	# inside its ink ring (WPlate._kind_disc): about 28 px, shrunk without mipmaps as the game draws it
	var p: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("boomstick"), 170.0, false, 1))
	p.set_kind_mark("weapon")
	assert_str(W.KIND_GLYPH_PATH % p.kind_mark).is_equal(GLYPH)
	var rad := p.kind_disc().size.x * 0.5
	var inner := (rad - maxf(roundf(rad * 0.16), 2.0)) * 2.0 * 0.78
	assert_float(inner).is_between(26.0, 30.0)
	for side: int in [int(round(inner)), 37, 74]:
		var img := _glyph(GLYPH)
		img.resize(side, side, Image.INTERPOLATE_BILINEAR)
		var ink := _ink_of(img)
		# still one gun, still lying across, at the card's size, the chest reel's and its landed plate's
		assert_int(_shapes(ink).size()).override_failure_message("%d px" % side).is_equal(1)
		var box := _box(ink)
		assert_int(box.size.x).override_failure_message("%d px" % side).is_greater(box.size.y)
