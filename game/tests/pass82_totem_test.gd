extends GdUnitTestSuite

## Pass 82, lane TOTEM (Garry: "I got the response from Claude Design ... implement it as described for the totem UI"):
## the Spirit Pole gift screen (design_handoff_88fits_totem, direction 1b). The layout in the README's numbers at
## 1080 x 1920 (label, crest, segments, tags, nails, base), the roll gauge (thirds of the gift's own range, both ends
## written, the number brass dark only on a top third), the label with and without the map's total, the amounts with
## sign and unit, the spirits' icon slots and the empty-plate fallback, a real finger on a tag (or its segment) taking
## that gift, a drag off it taking nothing, taps outside the rows doing nothing, the toast with the face, and the
## in-world pole keeping its paint under the screen and greying once the gift is taken.

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


func _pole() -> StructureDef:
	return Registry.structure("totem_pole")


## The mock's offer (screens/01): Le-loo +2% (middle third), Chet-woot +6% (top third), Frog +2% (bottom third).
func _mock() -> Array:
	return [
		{"id": "wolf", "name": "Le-loo", "animal": "the Wolf", "stat": "move_speed", "op": "mul", "value": 0.02, "min": 0.01, "max": 0.03, "quality": 2},
		{"id": "bear", "name": "Chet-woot", "animal": "the Bear", "stat": "might", "op": "mul", "value": 0.06, "min": 0.02, "max": 0.06, "quality": 3},
		{"id": "frog", "name": "Frog", "animal": "", "stat": "xp_gain", "op": "mul", "value": 0.02, "min": 0.02, "max": 0.04, "quality": 1}]


func _open(offer: Array, index: int = 4, total: int = 11) -> TotemScreen:
	var scr: TotemScreen = auto_free(SCREEN.new())
	add_child(scr)
	scr.open(offer, _pole(), index, total)
	return scr


func _touch(at: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = at
	e.pressed = pressed
	get_tree().root.push_input(e, true)


func _drag(at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = at
	e.relative = rel
	get_tree().root.push_input(e, true)


func _frames(n: int) -> void:
	for k in range(n):
		await get_tree().process_frame


func _near(r: Rect2, want: Rect2, what: String) -> void:
	assert_vector(r.position).override_failure_message("%s at %s, want %s" % [what, r.position, want.position]).is_equal_approx(want.position, Vector2(0.6, 0.6))
	assert_vector(r.size).override_failure_message("%s %s, want %s" % [what, r.size, want.size]).is_equal_approx(want.size, Vector2(0.6, 0.6))


# ---------------------------------------------------------------- the layout

func test_the_layout_is_the_readmes_at_1080_by_1920() -> void:
	var scr := _open(_mock())
	await get_tree().create_timer(0.7).timeout
	assert_bool(scr.visible).is_true()
	# the dim is the kit's modal dim, rgba(48,30,14,.78)
	assert_bool(scr.dim.color.is_equal_approx(W.DIM)).is_true()
	assert_bool(scr.dim.color.is_equal_approx(Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.78))).is_true()
	# the label at (60, 300), nothing in the top 130 px
	var label: Control = scr.get_node("Label")
	assert_vector(label.get_global_rect().position).is_equal(Vector2(60, 300))
	assert_str(scr.label_text()).is_equal("TOTEM 4 OF 11")
	# the crest (pass 83 re-pin: the repainted thunderbird, the pole's top): 420 wide at its painting's aspect (at most
	# 150 tall), centred on the column (x 210), its foot 12 px behind the top segment
	var crest_r: Rect2 = (scr.get_node("Crest") as Control).get_global_rect()
	assert_float(crest_r.size.x).is_equal_approx(420.0, 0.6)
	assert_float(crest_r.size.y).is_less_equal(150.0)
	assert_float(crest_r.get_center().x).is_equal_approx(210.0, 0.6)
	assert_float(crest_r.end.y).is_equal_approx(512.0, 0.6)
	# three segments 300 px at x 60, y 500 / 840 / 1180; tags 630 x 240 at x 390, 30 px under each segment's top
	var rows: Array = scr.planks()
	assert_int(rows.size()).is_equal(3)
	for k in range(3):
		var row = rows[k]
		var y: float = [500.0, 840.0, 1180.0][k]
		_near((row.plate as Control).get_global_rect(), Rect2(60, y, 300, 300), "segment %d" % k)
		_near((row.tag as Control).get_global_rect(), Rect2(390, y + 30, 630, 240), "tag %d" % k)
		# the plate: rock, a 6 px ink border, radius 10, the carved inset 8 px of black at .18, the face 240 px
		assert_bool(row.plate.fill.is_equal_approx(W.ROCK)).is_true()
		assert_int(row.plate.border).is_equal(6)
		assert_int(row.plate.radius).is_equal(10)
		assert_int(row.plate.ring).is_equal(8)
		assert_bool(row.plate.ring_color.is_equal_approx(Color(0, 0, 0, 0.18))).is_true()
		# pass 83 re-pin: the painted segment fills the plate inside its 6 px border (288), not 240
		assert_float(row.plate.icon_frac * 300.0).is_equal_approx(288.0, 0.01)
		# the tag: the kit's paper box, 5 px ink, an 8 px hard shadow
		var box: HardBox = row.tag_box
		assert_bool(box.fill.is_equal_approx(W.PAPER)).is_true()
		assert_int(box.border).is_equal(5)
		assert_int(box.shadow).is_equal(8)
		# the nail: 32 px, centred 2 px right of the tag's left edge, halfway down it
		var nr: Rect2 = (row.nail as Control).get_global_rect()
		assert_vector(nr.size).is_equal(Vector2(32, 32))
		assert_vector(nr.get_center()).is_equal_approx(Vector2(392, y + 30 + 120), Vector2(0.6, 0.6))
		# the lines: slab 48 then Bitter 600 30 on one baseline 14 px apart, italic 26, the gauge; all inside the tag's
		# padding (40 left, 30 right)
		assert_int(row.amount.font_size).is_equal(48)
		assert_int(row.stat.font_size).is_equal(30)
		assert_int(row.spirit.font_size).is_equal(26)
		var tr: Rect2 = (row.tag as Control).get_global_rect()
		assert_float((row.amount as Control).get_global_rect().position.x).is_equal_approx(tr.position.x + 45.0, 0.6)
		assert_float((row.stat as Control).get_global_rect().position.x - (row.amount as Control).get_global_rect().position.x).is_equal_approx(row.amount.text_width() + 14.0, 0.6)
		for c in [row.stat, row.spirit, row.gauge]:
			assert_float((c as Control).get_global_rect().end.x).is_less_equal(tr.end.x - 35.0)
		# the block of three lines centred top to bottom
		var top: float = (row.amount as Control).get_global_rect().position.y - tr.position.y
		var bottom: float = tr.end.y - (row.gauge as Control).get_global_rect().end.y
		assert_float(absf(top - bottom)).is_less(8.0)
	# the base 360 x 64 at (30, 1510)
	_near((scr.get_node("Base") as Control).get_global_rect(), Rect2(30, 1510, 360, 64), "base")
	# top-anchored: nothing in the top 130 px, nothing under the base (a taller phone adds room down there)
	for c in scr.find_children("*", "Control", true, false):
		var cc := c as Control
		if cc == scr.dim or not cc.is_visible_in_tree():
			continue
		assert_float(cc.get_global_rect().position.y).override_failure_message(str(cc.get_path())).is_greater_equal(130.0)
		assert_float(cc.get_global_rect().end.y).override_failure_message(str(cc.get_path())).is_less_equal(1574.5)


func test_a_deep_camera_cutout_moves_the_screen_down_by_what_passes_130() -> void:
	Settings.top_inset = 200
	var scr := _open(_mock())
	await get_tree().create_timer(0.7).timeout
	assert_vector((scr.get_node("Label") as Control).get_global_rect().position).is_equal(Vector2(60, 370))
	_near((scr.planks()[0].plate as Control).get_global_rect(), Rect2(60, 570, 300, 300), "segment 0")
	Settings.top_inset = 130
	var scr2 := _open(_mock())
	await get_tree().create_timer(0.7).timeout
	assert_vector((scr2.get_node("Label") as Control).get_global_rect().position).is_equal(Vector2(60, 300))


# ---------------------------------------------------------------- the gauge and the numbers

func test_the_gauge_shows_the_rolls_third_of_its_own_range_and_both_ends() -> void:
	# the thirds, as rolled and worked out again without `quality`
	for v in [[0.01, 1], [0.02, 2], [0.03, 3]]:
		var b := {"stat": "move_speed", "op": "mul", "value": v[0], "min": 0.01, "max": 0.03}
		assert_int(BOONS.roll_third(b)).is_equal(int(v[1]))
		b["quality"] = int(v[1])
		assert_int(BOONS.roll_third(b)).is_equal(int(v[1]))
	assert_int(BOONS.roll_third({"stat": "cooldown", "op": "mul", "value": -0.04, "min": -0.04, "max": -0.02})).is_equal(3)
	var offer := []
	for v in [0.01, 0.02, 0.03]:
		offer.append({"id": "wolf", "name": "Le-loo", "animal": "the Wolf", "stat": "move_speed", "op": "mul", "value": v,
			"min": 0.01, "max": 0.03, "quality": BOONS.quality(v, 0.01, 0.03)})
	var scr := _open(offer)
	await get_tree().create_timer(0.6).timeout
	var rows: Array = scr.planks()
	for k in range(3):
		var g: WNotches = rows[k].gauge
		assert_int(g.count).is_equal(3)
		assert_int(g.filled).is_equal(k + 1)
		assert_int(rows[k].feathers).is_equal(k + 1)
		assert_str(g.low).is_equal("+1%")
		assert_str(g.high).is_equal("+3%")
		# 56 x 18 notches, 8 px apart, a 3 px ink border
		assert_vector(g.notch_rect(0).size).is_equal(Vector2(56, 18))
		assert_float(g.notch_rect(1).position.x - g.notch_rect(0).end.x).is_equal(8.0)
		# the number turns brass dark on a top third only
		var want := W.BRASS_DARK if k == 2 else W.INK
		assert_bool(rows[k].amount.color.is_equal_approx(want)).override_failure_message("row %d" % k).is_true()


func test_amounts_and_range_ends_carry_their_sign_and_unit() -> void:
	var cases := [
		[{"stat": "move_speed", "op": "mul", "value": 0.02, "min": 0.01, "max": 0.03}, "+2%", "move speed", ["+1%", "+3%"]],
		[{"stat": "max_hp", "op": "add", "value": 5.0, "min": 2.0, "max": 6.0}, "+5", "max HP", ["+2", "+6"]],
		[{"stat": "regen", "op": "add", "value": 0.1, "min": 0.1, "max": 0.3}, "+0.1", "regen per second", ["+0.1", "+0.3"]],
		# the smaller size first, whatever the sign: the gauge fills from the left as the gift grows
		[{"stat": "cooldown", "op": "mul", "value": -0.03, "min": -0.04, "max": -0.02}, "−3%", "cooldown", ["−2%", "−4%"]],
		[{"stat": "magnet", "op": "mul", "value": 0.2, "min": 0.1, "max": 0.2}, "+20%", "pickup radius", ["+10%", "+20%"]]]
	for c in cases:
		var b: Dictionary = c[0]
		assert_str(BOONS.amount_text(b)).is_equal(str(c[1]))
		assert_str(BOONS.stat_text(b)).is_equal(str(c[2]))
		assert_array(BOONS.range_texts(b)).is_equal(c[3])
	# every gift in the pole's pool reads with a sign
	for e: Dictionary in BOONS.pool_of(_pole()):
		for t in BOONS.range_texts(e):
			assert_bool(str(t).begins_with("+") or str(t).begins_with("−")).override_failure_message(str(t)).is_true()
	# the toast: "{Word} · {amount} {stat}"
	assert_str(BOONS.toast_text(_mock()[0])).is_equal("Le-loo · +2% move speed")
	assert_str(BOONS.toast_text(_mock()[2])).is_equal("Frog · +2% XP gain")


func test_the_spirit_line_and_the_label_with_and_without_a_total() -> void:
	assert_str(BOONS.title(_mock()[0])).is_equal("Le-loo, the Wolf")
	assert_str(BOONS.title(_mock()[2])).is_equal("Frog")
	assert_str(BOONS.animal(_mock()[2])).is_equal("")
	assert_str(BOONS.pole_label(4, 11)).is_equal("TOTEM 4 OF 11")
	assert_str(BOONS.pole_label(4, 0)).is_equal("4TH TOTEM")
	assert_str(BOONS.pole_label(13, 12)).is_equal("TOTEM 13 OF 13")
	for p in [[1, "1ST"], [2, "2ND"], [3, "3RD"], [4, "4TH"], [11, "11TH"], [12, "12TH"], [13, "13TH"], [21, "21ST"], [22, "22ND"]]:
		assert_str(BOONS.ordinal(int(p[0]))).is_equal(str(p[1]))
	var scr := _open(_mock(), 4, 0)
	await get_tree().create_timer(0.3).timeout
	assert_str(scr.label_text()).is_equal("4TH TOTEM")
	var rows: Array = scr.planks()
	assert_str(rows[0].spirit.text).is_equal("Le-loo, the Wolf")
	assert_str(rows[2].spirit.text).is_equal("Frog")


## Pass 83 re-pin: every spirit has its painted segment now; the empty plate with the word is for a spirit added without
## a picture (an id with no file).
func test_the_four_faces_fill_their_slots_and_the_rest_show_their_word() -> void:
	for id in ["wolf", "bear", "frog", "serpent", "whale", "thunderbird", "seal", "salmon", "killer_whale", "bullhead", "raven"]:
		assert_object(BOONS.icon_of({"id": id})).override_failure_message(id).is_not_null()
		var tex: Texture2D = BOONS.icon_of({"id": id})
		assert_bool(BOONS.icon_path({"id": id}).begins_with("res://art/ui/totem/spirit_")).is_true()
		assert_float(tex.get_size().x).is_greater(0.0)
	assert_object(BOONS.icon_of({"id": "p83_no_picture"})).is_null()
	# a pool entry's own icon wins over its slot
	assert_str(BOONS.icon_path({"id": "raven", "icon": "art/ui/totem/spirit_wolf.png"})).is_equal("res://art/ui/totem/spirit_wolf.png")
	var scr := _open([
		{"id": "p83_no_picture", "name": "Thunderbird", "animal": "", "stat": "cooldown", "op": "mul", "value": -0.03, "min": -0.04, "max": -0.02, "quality": 2},
		_mock()[0]])
	await get_tree().create_timer(0.6).timeout
	var rows: Array = scr.planks()
	assert_int(rows.size()).is_equal(2)
	assert_object(rows[0].plate.tex).is_null()
	assert_object(rows[0].word).is_not_null()
	assert_str(rows[0].word.text).is_equal("Thunderbird")
	assert_int(rows[0].word.font_size).is_equal(40)
	assert_bool(rows[0].word.color.is_equal_approx(W.PAPER)).is_true()
	# the longest word fits inside the plate's border at 40 px
	assert_float(rows[0].word.text_width()).is_less_equal(300.0 - 2.0 * (6 + 4))
	assert_object(rows[1].plate.tex).is_not_null()
	assert_object(rows[1].word).is_null()


# ---------------------------------------------------------------- fingers

func test_a_tap_on_a_tag_takes_that_gift() -> void:
	var scr := _open(_mock())
	var took := [{}]
	scr.closed.connect(func(b: Dictionary) -> void: took[0] = b)
	await get_tree().create_timer(0.7).timeout
	var at: Vector2 = (scr.planks()[1].tag as Control).get_global_rect().get_center()
	_touch(at, true)
	await _frames(3)
	# held: the segment 14 px right, the tag on its shadow (8, 8) with the brass inner outline, the others at 60 %
	await get_tree().create_timer(0.12).timeout
	var row = scr.planks()[1]
	assert_bool(row.held).is_true()
	assert_vector((row.seg as Control).position).is_equal_approx(Vector2(14, 0), Vector2(0.5, 0.5))
	assert_vector((row.tag as Control).position - row.tag_home).is_equal_approx(Vector2(8, 8), Vector2(0.5, 0.5))
	assert_int(row.tag_box_down.inner).is_equal(6)
	assert_int(row.tag_box_down.shadow).is_equal(0)
	assert_float(scr.planks()[0].group.self_modulate.a).is_equal_approx(0.6, 0.01)
	assert_float(scr.planks()[2].group.self_modulate.a).is_equal_approx(0.6, 0.01)
	_touch(at, false)
	await get_tree().create_timer(0.55).timeout
	assert_str(str((took[0] as Dictionary).get("id", ""))).is_equal("bear")
	assert_bool(scr.visible).is_false()


func test_a_tap_on_a_segment_takes_its_gift_too() -> void:
	var scr := _open(_mock())
	var took := [{}]
	scr.closed.connect(func(b: Dictionary) -> void: took[0] = b)
	await get_tree().create_timer(0.7).timeout
	var at: Vector2 = (scr.planks()[2].plate as Control).get_global_rect().get_center()
	_touch(at, true)
	await _frames(3)
	_touch(at, false)
	await get_tree().create_timer(0.55).timeout
	assert_str(str((took[0] as Dictionary).get("id", ""))).is_equal("frog")


func test_taps_outside_the_rows_and_a_drag_off_a_gift_take_nothing() -> void:
	var scr := _open(_mock())
	var took := [false]
	scr.closed.connect(func(_b: Dictionary) -> void: took[0] = true)
	await get_tree().create_timer(0.7).timeout
	# the dim, the label, the crest, the base, the gap between two rows, the right of a segment's corner by its tag
	for at in [Vector2(900, 200), Vector2(200, 320), Vector2(210, 430), Vector2(210, 1540), Vector2(700, 820),
			Vector2(540, 1800), Vector2(375, 515)]:
		_touch(at, true)
		await _frames(2)
		_touch(at, false)
		await _frames(2)
	await get_tree().create_timer(0.4).timeout
	assert_bool(took[0]).is_false()
	assert_bool(scr.visible).is_true()
	for r in scr.planks():
		assert_bool(r.held).is_false()
	# a finger laid on a gift and dragged off it: back in 90 ms, nothing taken
	var from: Vector2 = (scr.planks()[0].tag as Control).get_global_rect().get_center()
	_touch(from, true)
	await _frames(2)
	assert_bool(scr.planks()[0].held).is_true()
	var prev := from
	for k in range(1, 7):
		var p := from.lerp(Vector2(540, 1800), float(k) / 6.0)
		_drag(p, p - prev)
		prev = p
		await _frames(1)
	assert_bool(scr.planks()[0].held).is_false()
	_touch(Vector2(540, 1800), false)
	await get_tree().create_timer(0.3).timeout
	assert_bool(took[0]).is_false()
	assert_float(scr.planks()[1].group.self_modulate.a).is_equal_approx(1.0, 0.01)
	# a tap during the open motion (the rows still moving) is not a choice
	var scr2 := _open(_mock())
	var took2 := [false]
	scr2.closed.connect(func(_b: Dictionary) -> void: took2[0] = true)
	await _frames(2)
	var at2: Vector2 = Vector2(700, 650)
	_touch(at2, true)
	await _frames(2)
	_touch(at2, false)
	await get_tree().create_timer(0.6).timeout
	assert_bool(took2[0]).is_false()


# ---------------------------------------------------------------- the close, the toast, the pole

func test_the_close_hands_control_back_at_300_ms_and_hides_at_420() -> void:
	var scr := _open(_mock())
	var took := [{}]
	var closing := [{}]
	scr.closed.connect(func(b: Dictionary) -> void: took[0] = b)
	scr.closing.connect(func(b: Dictionary) -> void: closing[0] = b)
	await get_tree().create_timer(0.6).timeout
	scr._pick(scr.planks()[0])
	# the pick starts the close at once (the world's pole greys from here); the gift goes to the game at 300 ms
	assert_str(str((closing[0] as Dictionary).get("id", ""))).is_equal("wolf")
	assert_bool((took[0] as Dictionary).is_empty()).is_true()
	# the face lifted off its plate and flies
	assert_object(scr.planks()[0].plate.tex).is_null()
	assert_object(scr.get_node_or_null("Face")).is_not_null()
	await get_tree().create_timer(0.36).timeout
	assert_str(str((took[0] as Dictionary).get("id", ""))).is_equal("wolf")
	assert_bool(scr.is_in_group("wanted_modal")).is_false()
	await get_tree().create_timer(0.2).timeout
	assert_bool(scr.visible).is_false()
	assert_bool(scr.is_in_group("wanted_modal")).is_true()
	# a second pick on the closed screen takes nothing more
	took[0] = {}
	scr._pick(scr.planks()[1])
	await get_tree().create_timer(0.4).timeout
	assert_bool((took[0] as Dictionary).is_empty()).is_true()


func test_an_icon_toast_lays_its_face_left_of_its_words() -> void:
	var t: WToasts = auto_free(WToasts.new())
	add_child(t)
	t.size = Vector2(1080, 200)
	var tex: Texture2D = BOONS.icon_of({"id": "wolf"})
	var words := "Le-loo · +2% move speed"
	var spot := t.icon_spot(words)
	t.push(words, W.PAPER, tex)
	t.tick(0.016)
	var w: WText = t.get_child(0)
	var ic := w.get_node("Icon") as TextureRect
	assert_object(ic).is_not_null()
	assert_vector(ic.size).is_equal(Vector2(72, 72))
	# the icon's middle where icon_spot said, the words 14 px after it, the pair centred
	var ic_rect := Rect2(w.position + ic.position, ic.size)
	assert_vector(ic_rect.get_center()).is_equal_approx(spot, Vector2(1.0, 1.0))
	var words_x := w.position.x + (w.size.x - w.text_width()) * 0.5
	assert_float(words_x - ic_rect.end.x).is_equal_approx(14.0, 1.0)
	var left := ic_rect.position.x
	var right := words_x + w.text_width()
	assert_float(absf((left - 0.0) - (1080.0 - right))).is_less(2.0)


func test_in_a_run_the_pole_keeps_its_paint_under_the_screen_and_greys_after_the_pick() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 9, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.3).timeout
	g.director.stop()
	var sm: StructureManager = g.structures
	var here: Vector3 = g.player.global_position + Vector3(6, 0, 0)
	here.y = g.map.height_at(here.x, here.z)
	var s: StructureManager.Structure = sm._spawn(_pole(), here)
	var poles := sm.count_of("totem_pole")
	assert_int(poles).is_between(11, 13)
	sm._use(s)
	await get_tree().create_timer(0.3).timeout
	assert_bool(g.totem_screen.visible).is_true()
	assert_str(g.totem_screen.label_text()).is_equal("TOTEM 1 OF %d" % poles)
	# under the screen: used, its paint and its ring kept
	assert_bool(s.used).is_true()
	assert_bool(s.ring.visible).is_true()
	var mat := (s.visual as BillboardSprite).material_override as ShaderMaterial
	# its tint untouched (never set: the shader's white) and nothing drained from it
	var tint0 = mat.get_shader_parameter("tint")
	assert_bool(tint0 == null or (tint0 is Color and (tint0 as Color).is_equal_approx(Color(1, 1, 1, 1)))).is_true()
	var desat0 = mat.get_shader_parameter("desat")
	assert_bool(desat0 == null or float(desat0) < 0.001).is_true()
	# the pick: the screen closes, the gift stays, the toast carries the face, the pole greys
	var row = g.totem_screen.planks()[0]
	var boon: Dictionary = row.boon
	g.totem_screen._pick(row)
	await get_tree().create_timer(0.9).timeout
	assert_bool(g.totem_screen.visible).is_false()
	assert_bool(g.paused).is_false()
	assert_int(Run.totem_boons.size()).is_equal(1)
	assert_str(str(Run.totem_boons[0]["id"])).is_equal(str(boon["id"]))
	assert_bool(s.ring.visible).is_false()
	var grey := StructureManager.grey_painting(_pole())
	if grey != null:
		assert_object(mat.get_shader_parameter("sprite")).is_same(grey)
	assert_float(float(mat.get_shader_parameter("desat"))).is_equal_approx(0.0, 0.001)
	# the hero's safety after the pick, as before
	assert_float(g.player.invuln).is_greater(0.0)
