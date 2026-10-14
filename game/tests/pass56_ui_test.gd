## Pass 56, the UI lane (Garry's twelfth list): "Make the EXP bar twice as thick, move all the other UI with it
## accordingly" (a plain fill, just twice as thick: the HUD's rail and the level-up screen's rainbow copy read one pair of
## constants, and the top row, the slots, the strip, the thumb zone and everything under them sit 18 px lower with every
## gap as it was, with or without a camera cutout), and "Change the marker for a weapon ... It should be a single
## revolver and it should look a bit more different from the scroll glyph" (one solid revolver, tools/make_kind_glyphs.py).
## The fix round: the boss's plate under the power-ups (its bar had run across them), the level-up screen's header, the
## mutation offer's head and the cards 18 px lower too (and a long mutation offer kept between its head and its skip),
## the arena's quick column under the camera cutout and the boss's plate, and a tap on the strip that lets the resume
## gate go no longer opens the pause menu.
extends GdUnitTestSuite

## The rail before pass 56, and the top row, the slots and the strip it set.
const OLD_RAIL := 18.0
## Pass 61 (Garry: "Make the EXP bar 1.8 times bigger"): the rail is 1.8 times pass 56's 36 px, rounded (65), its fill
## 11 px in (6 x 1.8); re-pinned here, the gaps under it unchanged.
const P61_GROW := 1.8
const OLD_TOP_Y := 30.0
const OLD_SLOT_Y := 126.0
const OLD_BAND_H := 220.0
const GLYPH := "res://art/ui/wanted/kind_weapon.png"
## The line items' glyph: a rolled scroll until pass 72, a fortune card since pass 73 (lane CARDS); the same file.
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
	# a write the test asked for (a weapon seen) may have gone to the test save while the inset was 130, and the next
	# run would boot with it: the settings as they are now go on the file before the next test
	Save.request_save()
	Save.flush()


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
	assert_float(HUD.RAIL_H).is_equal(roundf(2.0 * OLD_RAIL * P61_GROW))
	# the fill keeps two thirds of it: 6 px in from the top and the bottom (3 of 18 before), 11 since pass 61
	assert_float(HUD.RAIL_INSET).is_equal(roundf(6.0 * P61_GROW))
	assert_float(HUD.RAIL_H - 2.0 * HUD.RAIL_INSET).is_equal(43.0)
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
	# 18 in pass 56, 47 since pass 61
	assert_float(gain).is_equal(47.0)
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
	assert_float(hud._slots_bottom).is_equal(OLD_SLOT_Y + (HUD.RAIL_H - OLD_RAIL) + 72.0 + 6.0)
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


# ---------------------------------------------------------------- 5. the fix round: under the strip

func _touch(at: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = at
	ev.pressed = pressed
	get_tree().root.push_input(ev, true)


## Berserk and Sprint up (their plates under the slots), then the HUD laid out.
func _power_ups(hud: HUD) -> void:
	Run.add_timed_effects("rage", "Berserk", [], 30.0)
	Run.add_timed_effects("sprint", "Sprint", [], 22.0)
	hud._refresh_buffs()
	await get_tree().process_frame


## The power-ups' plates on screen.
func _plates(hud: HUD) -> Array:
	var out: Array = []
	for c in hud._buffs.get_children():
		out.append((c as Control).get_global_rect())
	return out


func test_the_boss_plate_sits_under_the_power_ups_and_the_words_and_toasts_under_both() -> void:
	var king: EnemyDef = Registry.enemy("tumbleweed_king")
	for inset: int in [0, 130]:
		Settings.top_inset = inset
		var hud := await _hud()
		var why := "inset %d" % inset
		# no power-ups: the boss's plate where it always was, 20 px under the slots
		hud.show_boss(king)
		assert_float(hud._boss_box.position.y).override_failure_message(why).is_equal(hud._slots_bottom + HUD.BOSS_GAP)
		await _power_ups(hud)
		var plates := _plates(hud)
		assert_int(plates.size()).override_failure_message(why).is_equal(2)
		var boss := hud._boss_box.get_global_rect()
		for r: Rect2 in plates:
			# under the plates and their seconds' tags (which hang 6 px under them), never across them
			assert_bool(r.intersects(boss)).override_failure_message(why).is_false()
			assert_float(boss.position.y).override_failure_message(why).is_greater_equal(r.end.y + 6.0)
		assert_float(boss.position.y).override_failure_message(why).is_equal(plates[0].end.y + HUD.BOSS_UNDER_BUFFS)
		assert_float(hud.boss_plate_bottom()).override_failure_message(why).is_equal(boss.end.y)
		# the words under the boss's bar, the toasts under the words
		Run.adrenaline = 5
		Run.adrenaline_until = Run.buff_clock() + 30.0
		hud._refresh_buffs()
		assert_bool(hud._adren.visible).override_failure_message(why).is_true()
		var words := hud._adren.get_global_rect()
		assert_float(words.position.y).override_failure_message(why).is_greater_equal(boss.end.y)
		assert_float(hud._toasts.position.y).override_failure_message(why).is_greater_equal(words.end.y)
		assert_float(hud._under_bottom).override_failure_message(why).is_equal(words.end.y)
		# the boss gone: the words under the plates' tags, the toasts under the words
		hud.hide_boss()
		assert_float(hud.boss_plate_bottom()).is_equal(-1.0)
		words = hud._adren.get_global_rect()
		for r: Rect2 in _plates(hud):
			assert_float(words.position.y).override_failure_message(why).is_greater_equal(r.end.y + 6.0)
		assert_float(hud._toasts.position.y).override_failure_message(why).is_greater_equal(words.end.y)
		# the words gone too: the toasts under the plates
		Run.adrenaline = 0
		hud._refresh_buffs()
		assert_bool(hud._adren.visible).is_false()
		assert_float(hud._toasts.position.y).override_failure_message(why).is_equal(plates[0].end.y + HUD.TOAST_GAP)
		Run.timed.clear()
		hud.queue_free()
		await get_tree().process_frame


func test_the_arena_column_keeps_under_the_camera_cutout_and_the_boss_plate() -> void:
	# it sat at a fixed y 380: with a 130 px inset the boss's bar ran beneath ARENA and AGAIN
	Settings.top_inset = 130
	assert_float(ArenaPanel.column_top(-1.0)).is_equal(380.0 + 130.0)
	assert_float(ArenaPanel.column_top(400.0)).is_equal(380.0 + 130.0)
	assert_float(ArenaPanel.column_top(600.0)).is_equal(600.0 + ArenaPanel.COLUMN_GAP)
	var hud := await _hud()
	var panel: ArenaPanel = auto_free(ArenaPanel.new())
	add_child(panel)
	await get_tree().process_frame
	var col: Control = panel.find_child("QuickColumn", false, false)
	assert_object(col).is_not_null()
	assert_float(col.get_global_rect().position.y).is_equal(380.0 + 130.0)
	hud.show_boss(Registry.enemy("tumbleweed_king"))
	await _power_ups(hud)
	panel.place_column(hud)
	await get_tree().process_frame
	# under the boss's bar, which sits under the power-ups
	var boss := hud._boss_box.get_global_rect()
	assert_float(col.get_global_rect().position.y).is_greater_equal(boss.end.y + ArenaPanel.COLUMN_GAP - 0.5)
	assert_bool(col.get_global_rect().intersects(boss)).is_false()
	# and back once the boss is gone
	hud.hide_boss()
	panel.place_column(hud)
	await get_tree().process_frame
	assert_float(col.get_global_rect().position.y).is_equal(380.0 + 130.0)
	Run.timed.clear()


func test_a_tap_on_the_strip_that_lets_the_gate_go_does_not_open_the_pause_menu() -> void:
	var hud := await _hud()
	var gate: ResumeGate = auto_free(ResumeGate.new())
	gate.hud = hud
	add_child(gate)
	await get_tree().process_frame
	var pauses := [0]
	hud.pause_requested.connect(func(): pauses[0] += 1)
	var vp := hud.get_viewport_rect().size
	var k := vp.x / 1080.0
	# on the strip (the pause strip's and the gate's, whatever the canvas width): under the clock, just over the strip's
	# foot, and on the pause disc
	var foot := HUD.band_h * minf(k, 1.0) - 6.0
	var spots: Array = [Vector2(vp.x * 0.5, HUD.TOP_Y + 20.0), Vector2(vp.x * 0.5, foot), hud._pause_btn.get_global_rect().get_center()]
	for at: Vector2 in spots:
		assert_bool(ResumeGate.on_strip(at, vp)).override_failure_message(str(at)).is_true()
		gate.open({})
		gate._t = 1.0
		_touch(at, true)
		await get_tree().process_frame
		_touch(at, false)
		await get_tree().process_frame
		assert_bool(gate.visible).override_failure_message(str(at)).is_false()
		assert_int(pauses[0]).override_failure_message("a tap at %s let the gate go and paused" % str(at)).is_equal(0)
	# lower down the touch goes on (it can start the stick): the gate goes and the strip hears nothing
	var low := Vector2(vp.x * 0.5, HUD.band_h * maxf(k, 1.0) + 300.0)
	assert_bool(ResumeGate.on_strip(low, vp)).is_false()
	gate.open({})
	gate._t = 1.0
	_touch(low, true)
	await get_tree().process_frame
	_touch(low, false)
	await get_tree().process_frame
	assert_bool(gate.visible).is_false()
	assert_int(pauses[0]).is_equal(0)
	# with no gate up a tap on the strip still pauses (the strip hears these touches)
	_touch(spots[1], true)
	await get_tree().process_frame
	_touch(spots[1], false)
	await get_tree().process_frame
	assert_int(pauses[0]).is_equal(1)


# ---------------------------------------------------------------- 6. the fix round: the level-up screen under the rail

func test_the_level_up_screen_moves_down_with_the_rail_and_keeps_its_gaps() -> void:
	assert_float(CardScreen.RAIL_GROWTH).is_equal(HUD.RAIL_H - OLD_RAIL)
	# pass 58 review: the star line over LEVEL N is STAR_LINE_PX (34) where the kit's is 30, 42.5 px tall (was 38)
	assert_float(CardScreen.TITLE_MID_Y).is_equal(110.0 + CardScreen.RAIL_GROWTH + CardScreen.STAR_LINE_PX * 1.25 + 75.0)
	for inset: int in [0, 130]:
		Settings.top_inset = inset
		var cs: CardScreen = auto_free(CardScreen.new())
		add_child(cs)
		await get_tree().process_frame
		var rail_foot := float(inset) + HUD.RAIL_H
		var why := "inset %d" % inset
		# from the rail's foot: 92 px to the header, 72 to the mutation offer's head, 452 and 702 to the cards, as under
		# the 18 px rail
		assert_float(cs.header.offset_top - rail_foot).override_failure_message(why).is_equal(110.0 - OLD_RAIL)
		assert_float(cs._path_head.offset_top - rail_foot).override_failure_message(why).is_equal(90.0 - OLD_RAIL)
		assert_float(cs._list.offset_top - rail_foot).override_failure_message(why).is_equal(470.0 - OLD_RAIL)
		assert_float(CardScreen.PATH_LIST_TOP + inset - rail_foot).override_failure_message(why).is_equal(720.0 - OLD_RAIL)
		cs.queue_free()
		await get_tree().process_frame


func test_a_long_mutation_offer_stays_between_its_head_and_its_skip() -> void:
	# four cards (the grenade's three and the Drifter's Fire in the Hole; pass 76, lane DYN: the Peashooter and his Fan
	# the Hammer it used are hidden), with and without a camera cutout: under one they ran over the weapon's name before
	# the fix round, and three ran into SKIP
	for inset: int in [0, 130]:
		Settings.top_inset = inset
		_start("drifter")
		Run.debug_clear_items()
		Run.add_weapon(Registry.weapon("lob_grenade"), 3)
		var offer: Array = []
		for m: MutationDef in Registry.mutations_of("lob_grenade"):
			if offer.size() < 3:
				offer.append({"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1, "is_new": true})
		for m: MutationDef in Registry.weapon_hero_mutations("lob_grenade"):
			offer.append({"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1, "is_new": true})
			break
		assert_int(offer.size()).is_equal(4)
		var cs: CardScreen = auto_free(CardScreen.new())
		add_child(cs)
		cs.show_offer(offer, "MUTATION", false, true)
		cs.skip_reel()
		# fitted a frame after the landing; the cards still drop into their places, so the places are measured
		for f in 4:
			await get_tree().process_frame
		var why := "inset %d, the canvas %s" % [inset, str(cs.get_viewport_rect().size)]
		var head_foot := cs._path_head.get_global_rect().end.y
		var note_top := cs._path_note.get_global_rect().position.y
		var skip := cs._path_skip.get_global_rect()
		assert_int(cs._slots.size()).is_equal(4)
		for c: Control in cs._slots:
			var r := c.get_global_rect()
			why = "inset %d, the canvas %s, head foot %.1f, card %s" % [inset, str(cs.get_viewport_rect().size), head_foot, str(r)]
			assert_float(r.position.y).override_failure_message(why).is_greater_equal(head_foot + CardScreen.HEAD_CLEAR - 0.5)
			assert_float(r.end.y).override_failure_message(why).is_less_equal(note_top - 12.0 + 0.5)
			assert_bool(r.intersects(skip)).override_failure_message(why).is_false()
		# the skip stays on the screen
		assert_float(skip.end.y).is_less_equal(cs.get_viewport_rect().size.y)
		cs.visible = false
		cs.queue_free()
		await get_tree().process_frame
