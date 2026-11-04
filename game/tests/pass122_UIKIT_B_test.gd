## Pass 122, lane UIKIT_B: the Royale kit, part 2 (the item frame, the meters, the small pieces; Garry's build brief of
## 2026-11-02 on Claude Design's "Royale, refined": a second theme behind a switch, Wanted the default and untouched).
##  - the three shaders load and carry their uniforms (ui_radial_fill, ui_rainbow_rim, ui_rays);
##  - WPlate under both themes for a common passive, a legendary passive, a level-5 weapon, an evolved weapon and a
##    level-plaque frame: the Wanted fill and ring as before, the frame's rarity and evolved flag as computed, the Royale
##    layers made under Royale only, the plaque's words, the frame's px by size;
##  - WBar, WSlider, WCoin, WPointer, WCard, WStarLine (and the small pieces) build and draw under both themes, and say
##    what they are under Royale (the bar's fills, the coin's disc, the arrow's colour, the card's word line and tag);
##  - no W colour constant moves;
##  - the review fixes (lane UIKIT_B_FIX): a creature plate is a slate frame, never evolved; a hand-set brass ring is
##    drawn (gold) and rock is red; a plate at rest draws once and not every frame (a property write draws it again,
##    the evolution glow breathes); a glow is cut round an earlier sibling's frame and `glow_reach` caps its reach.
extends GdUnitTestSuite

const SHADERS := ["res://core/shaders/ui_radial_fill.gdshader", "res://core/shaders/ui_rainbow_rim.gdshader",
	"res://core/shaders/ui_rays.gdshader"]

var _settings_before: Dictionary = {}


func before() -> void:
	_settings_before = Settings.to_dict()


func after() -> void:
	Settings.force_prod(false)
	Settings.from_dict(_settings_before)


func after_test() -> void:
	Settings.force_prod(false)


## A passive item of `rarity` that is not a line and has an icon.
func _passive_of(rarity: String) -> PassiveDef:
	for p: PassiveDef in Registry.passives.values():
		if p.rarity == rarity and not p.hidden and not p.is_evolved() and not p.is_line() and p.icon != null:
			return p
	return null


func _evolution() -> WeaponDef:
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution and w.icon != null:
			return w
	return null


func _uniforms(s: Shader) -> Array:
	var out: Array = []
	for u in s.get_shader_uniform_list():
		out.append(str(u["name"]))
	return out


## A creature with an icon (its plate's fill is the ink, W.KIND["enemy"]).
func _creature() -> EnemyDef:
	for e: EnemyDef in Registry.enemies.values():
		if e.icon != null and not e.hidden and e.archetype != "boss":
			return e
	return null


## Counts a CanvasItem's draws over `frames` frames (after letting it settle).
func _draws_over(node: CanvasItem, frames: int) -> int:
	var count: Array = [0]
	var cb := func() -> void: count[0] += 1
	node.draw.connect(cb)
	for i in frames:
		await get_tree().process_frame
	node.draw.disconnect(cb)
	return int(count[0])


# ---------------------------------------------------------------- the shaders

func test_the_shaders_load() -> void:
	for p in SHADERS:
		assert_bool(ResourceLoader.exists(p)).override_failure_message(p).is_true()
		var s: Shader = load(p)
		assert_object(s).override_failure_message(p).is_not_null()
		assert_bool(s.code.contains("shader_type canvas_item")).override_failure_message(p).is_true()
	var fill: Shader = load(SHADERS[0])
	var fu := _uniforms(fill)
	for name in ["size", "pad", "base_px", "radius", "shape", "edge_px", "edge_color", "rim_px", "rim_mode", "rim_a", "rim_b",
			"rim_c", "rim_d", "rainbow", "inner_px", "inner_color", "light", "base", "dark", "center", "base_at", "lip_px",
			"lip_alpha", "foot_px", "foot_alpha", "glow_px", "glow_color", "alpha", "cut_count", "cuts", "cut_radius", "cut_base"]:
		assert_bool(fu.has(name)).override_failure_message("ui_radial_fill lacks " + name).is_true()
	var rim: Shader = load(SHADERS[1])
	var ru := _uniforms(rim)
	for name in ["size", "pad", "inset", "rim_px", "radius", "shape", "rainbow", "glow_px", "glow_color", "turn", "alpha"]:
		assert_bool(ru.has(name)).override_failure_message("ui_rainbow_rim lacks " + name).is_true()
	var rays: Shader = load(SHADERS[2])
	var yu := _uniforms(rays)
	for name in ["size", "color", "on_deg", "period_deg", "mask_in", "mask_out", "turn_s", "phase", "alpha"]:
		assert_bool(yu.has(name)).override_failure_message("ui_rays lacks " + name).is_true()
	# the frame's and the rays' numbers live in R
	assert_float(R.FRAME_LIP_FRAC).is_equal_approx(0.031, 0.0001)
	assert_float(R.FRAME_LEGEND_RIM).is_equal_approx(1.5, 0.0001)
	assert_int(R.FRAME_LEGEND_INNER).is_equal(3)
	assert_float(R.RAYS_ON_DEG).is_equal_approx(8.0, 0.0001)
	assert_float(R.RAYS_PERIOD_DEG).is_equal_approx(20.0, 0.0001)
	assert_float(R.RAYS_TURN_S).is_equal_approx(30.0, 0.0001)
	# pass 123 (Garry: "Change the number to be black text on white, cz white on blue doesn't read very well")
	assert_bool(R.PLAQUE_TOP.is_equal_approx(Color("ffffff"))).is_true()
	assert_bool(R.PLAQUE_BOTTOM.is_equal_approx(Color("e4e8ef"))).is_true()
	assert_bool(R.PLAQUE_TEXT.is_equal_approx(Color("0b0d14"))).is_true()


# ---------------------------------------------------------------- the item frame

func test_the_frame_under_both_themes() -> void:
	var common := _passive_of("common")
	var legend := _passive_of("legendary")
	var evo := _evolution()
	var weapon: WeaponDef = Registry.weapon("boomstick")
	var creature := _creature()
	assert_object(common).is_not_null()
	assert_object(legend).is_not_null()
	assert_object(evo).is_not_null()
	assert_object(weapon).is_not_null()
	assert_object(creature).is_not_null()
	for royale in [true]:
		var host := Control.new()
		add_child(host)
		var pc: WPlate = WPlate.new().for_def(common, 200.0, false, 1)
		var pl: WPlate = WPlate.new().for_def(legend, 200.0, false, 1)
		var w5: WPlate = WPlate.new().for_def(weapon, 200.0, false, 5)
		var pe: WPlate = WPlate.new().for_def(evo, 200.0, false, 1)
		var pq: WPlate = WPlate.new().for_def(weapon, 80.0, false, 2)
		pq.level_plaque = 4
		var lk: WPlate = WPlate.new().for_def(common, 80.0, true, 1)
		var slot: WPlate = WPlate.slot(72.0)
		# a creature plate (the Collection's Enemies grid): the ink fill, a special's brass ring and gear badge by hand
		var cr: WPlate = WPlate.new().for_def(creature, 210.0, false, 1)
		cr.ring = 8
		cr.ring_color = W.BRASS
		cr.base_ring = cr.ring
		for p in [pc, pl, w5, pe, pq, lk, slot, cr]:
			host.add_child(p)
		await get_tree().process_frame
		await get_tree().process_frame
		# the Wanted fill and ring are what they were (pass 48 / 95 pin them too)
		assert_bool(pc.fill.is_equal_approx(W.RARITY_PLATE["common"])).is_true()
		assert_bool(pl.fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
		assert_bool(w5.fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
		assert_bool(pe.fill.is_equal_approx(W.EVOLVED_FILL)).is_true()
		assert_int(pe.ring).is_greater(0)
		assert_int(pc.ring).is_equal(0)
		assert_bool(cr.fill.is_equal_approx(W.INK)).is_true()
		# the frame's rarity as computed (the theme does not change it)
		assert_str(pc.frame_rarity()).is_equal("common")
		assert_str(pl.frame_rarity()).is_equal("legendary")
		assert_str(w5.frame_rarity()).is_equal("legendary")
		assert_str(pe.frame_rarity()).is_equal("evolved")
		assert_bool(pe.is_evolved_frame()).is_true()
		assert_bool(w5.is_evolved_frame()).is_false()
		assert_str(lk.frame_rarity()).is_equal("locked")
		assert_str(slot.frame_rarity()).is_equal("slot")
		# review fix 1: a creature's ink is never the evolved look; it is the kit's slate frame with a plain rim
		assert_str(cr.frame_rarity()).is_equal("custom")
		assert_bool(cr.is_evolved_frame()).is_false()
		assert_int(cr.frame_look()["rim_mode"]).is_equal(0)
		assert_int(cr.frame_look()["glow_px"]).is_equal(0)
		assert_bool(cr.frame_look()["base"].is_equal_approx(R.SLATE_MID)).is_true()
		assert_bool(cr.frame_look()["rim"].is_equal_approx(R.MUTED)).is_true()
		# review fix 2: its brass ring is shown (gold under Royale), the evolved frame's own ring is not a hand-set one
		assert_bool(cr.ring_shown()).is_true()
		assert_bool(pe.ring_shown()).is_false()
		assert_bool(WPlate.royale_ring_colour(W.BRASS).is_equal_approx(R.role("gold")["bottom"])).is_true()
		assert_bool(WPlate.royale_ring_colour(W.ROCK).is_equal_approx(R.role("red")["bottom"])).is_true()
		assert_bool(WPlate.royale_ring_colour(W.EMBER).is_equal_approx(W.EMBER)).is_true()
		assert_int(pl.frame_look()["rim_mode"]).is_equal(1)
		assert_int(pl.frame_look()["inner"]).is_equal(R.FRAME_LEGEND_INNER)
		assert_int(pe.frame_look()["rim_mode"]).is_equal(2)
		assert_int(pc.frame_look()["rim_mode"]).is_equal(0)
		assert_bool(pc.frame_look()["light"].is_equal_approx(R.RARITY["common"]["light"])).is_true()
		assert_bool(pe.frame_look()["base"].is_equal_approx(R.RARITY["evolved"]["base"])).is_true()
		assert_int(int(pc.frame_metrics()["edge"])).is_equal(R.FRAME_EDGE_BIG)
		assert_int(int(pc.frame_metrics()["rim"])).is_equal(R.FRAME_RIM_BIG)
		assert_int(int(pl.frame_metrics()["rim"])).is_equal(int(round(R.FRAME_RIM_BIG * R.FRAME_LEGEND_RIM)))
		assert_int(int(pq.frame_metrics()["edge"])).is_equal(R.FRAME_EDGE_SMALL)
		assert_int(int(pq.frame_metrics()["rim"])).is_equal(R.FRAME_RIM_SMALL)
		assert_int(int(slot.frame_metrics()["rim"])).is_equal(0)
		assert_str(pq.plaque_text(4)).is_equal("4")
		assert_str(pc.plaque_text(4)).is_equal("LV 4")
		assert_int(pq.level_plaque).is_equal(4)
		# the Royale layers exist under Royale only, behind the plate
		var frame_c := pc.find_child("RoyaleFrame", false, false)
		var rays_c := pc.find_child("RoyaleRays", false, false)
		if royale:
			assert_object(frame_c).is_not_null()
			assert_object(rays_c).is_not_null()
			assert_bool((frame_c as CanvasItem).show_behind_parent).is_true()
			assert_bool((frame_c as CanvasItem).visible).is_true()
			assert_bool((rays_c as CanvasItem).visible).is_false()
			assert_int(frame_c.get_index()).is_less(2)
			var mat := (frame_c as Control).material as ShaderMaterial
			assert_object(mat).is_not_null()
			assert_int(int(mat.get_shader_parameter("rim_mode"))).is_equal(0)
			assert_float(float(mat.get_shader_parameter("rim_px"))).is_equal(float(R.FRAME_RIM_BIG))
			var lmat := (pl.find_child("RoyaleFrame", false, false) as Control).material as ShaderMaterial
			assert_int(int(lmat.get_shader_parameter("rim_mode"))).is_equal(1)
			assert_float(float(lmat.get_shader_parameter("glow_px"))).is_equal(float(R.FRAME_GLOW_LEGEND))
			var emat := (pe.find_child("RoyaleFrame", false, false) as Control).material as ShaderMaterial
			assert_int(int(emat.get_shader_parameter("rim_mode"))).is_equal(2)
			var cmat := (cr.find_child("RoyaleFrame", false, false) as Control).material as ShaderMaterial
			assert_int(int(cmat.get_shader_parameter("rim_mode"))).is_equal(0)
			assert_float(float(cmat.get_shader_parameter("glow_px"))).is_equal(0.0)
			# a frame asked for rays shows them, a disc 2.2 times its side
			pl.rays = true
			await get_tree().process_frame
			var lr := pl.find_child("RoyaleRays", false, false) as Control
			assert_bool(lr.visible).is_true()
			assert_float(lr.size.x).is_equal_approx(roundf(200.0 * R.RAYS_SCALE), 0.5)
			# the plaque's box hangs off the foot, centred
			var box := pq.plaque_rect("4")
			assert_float(box.end.y).is_greater(80.0)
			assert_float(box.position.y).is_less(80.0)
			assert_float(box.get_center().x).is_equal_approx(40.0, 1.0)
			assert_float(box.size.y).is_equal(float(R.PLAQUE_H_MIN))
			var big := pc.plaque_rect("LV 4")
			assert_float(big.size.y).is_equal(roundf(200.0 * R.PLAQUE_H_FRAC))
		else:
			assert_object(frame_c).is_null()
			assert_object(rays_c).is_null()
			assert_int(pc.get_child_count()).is_equal(0)
		host.queue_free()
		await get_tree().process_frame
	# a derived triplet for a fill of a screen's own, and the common grey for paper
	var d := WPlate.derive_frame(W.SAGE)
	assert_bool(d["base"].is_equal_approx(W.SAGE)).is_true()
	assert_bool(d["light"].v > W.SAGE.v).is_true()
	assert_bool(d["dark"].v < W.SAGE.v).is_true()
	assert_bool(WPlate.derive_frame(W.PAPER)["base"].is_equal_approx(R.RARITY["common"]["base"])).is_true()
	assert_bool(WPlate.derive_frame(W.INK)["light"].is_equal_approx(R.SLATE_TOP)).is_true()
	assert_bool(WPlate.derive_frame(W.INK)["dark"].is_equal_approx(R.SLATE_BOTTOM)).is_true()
	# a plate built under Royale and shown under Wanted hides its layers (the Wanted drawing is the old one)
	var flip: WPlate = auto_free(WPlate.new().for_def(common, 96.0))
	add_child(flip)
	await get_tree().process_frame
	assert_object(flip.find_child("RoyaleFrame", false, false)).is_not_null()
## Review fix 3: a plate at rest does not redraw every frame under either theme (Godot turns _process on at READY for a
## script that overrides it; _ready turns it off again); a property write draws it once more; the evolution glow
## (dots_ready) breathes on a frame clock.
func test_a_plate_at_rest_does_not_redraw() -> void:
	var epic := _passive_of("epic")
	var weapon: WeaponDef = Registry.weapon("boomstick")
	assert_object(epic).is_not_null()
	for royale in [true]:
		var host := Control.new()
		add_child(host)
		var p: WPlate = WPlate.new().for_def(epic, 120.0, false, 1)
		host.add_child(p)
		var q: WPlate = WPlate.new().for_def(weapon, 72.0, false, 3)
		q.level_text = "3"
		host.add_child(q)
		# settle: the first draw and the size the tree gives a fresh Control
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		assert_bool(p.is_processing()).override_failure_message("royale=%s" % royale).is_false()
		var rest: int = await _draws_over(p, 12)
		assert_int(rest).override_failure_message("royale=%s: %d draws at rest" % [royale, rest]).is_equal(0)
		assert_int(await _draws_over(q, 6)).is_equal(0)
		# a write to a drawn-from property (the Totem's `tex`, the HUD's `level_text`) is drawn
		q.level_text = "4"
		assert_int(await _draws_over(q, 3)).is_equal(1)
		p.fill = W.SAGE
		assert_int(await _draws_over(p, 3)).is_equal(1)
		p.tex = null
		p.glyph = "?"
		assert_int(await _draws_over(p, 3)).is_equal(1)
		# the evolution glow breathes: a frame clock while it waits, off again when it is gone
		q.set_dots(Vector2i(3, 3), true)
		await get_tree().process_frame
		assert_bool(q.is_processing()).is_true()
		assert_int(await _draws_over(q, 6)).is_greater_equal(5)
		q.set_dots(Vector2i(3, 3), false)
		await get_tree().process_frame
		assert_bool(q.is_processing()).is_false()
		assert_int(await _draws_over(q, 6)).is_equal(0)
		# under Royale the frame layer is not redrawn by its plate's rest either
		if royale:
			var frame := p.find_child("RoyaleFrame", false, false) as Control
			assert_int(await _draws_over(frame, 6)).is_equal(0)
		host.queue_free()
		await get_tree().process_frame


## Review fix 4: a glow (epic, legendary, evolved) is cut where an earlier sibling WPlate's frame stands, so a row's
## glows all sit behind their neighbours; a frame with its rays on paints over everything (no cuts); `glow_reach` caps
## the reach (a screen's half gap) and so the cuts; a moved neighbour row is read again.
func test_a_glow_sits_behind_its_neighbours() -> void:
	var epic := _passive_of("epic")
	var legend := _passive_of("legendary")
	assert_object(epic).is_not_null()
	assert_object(legend).is_not_null()
	var host := Control.new()
	add_child(host)
	var a: WPlate = WPlate.new().for_def(epic, 200.0, false, 1)
	a.position = Vector2(0, 0)
	var b: WPlate = WPlate.new().for_def(legend, 200.0, false, 1)
	b.position = Vector2(208, 0)
	var c: WPlate = WPlate.new().for_def(epic, 200.0, false, 1)
	c.position = Vector2(600, 0)   # far: no neighbour in its glow
	for p in [a, b, c]:
		host.add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	var pad_b := int(R.FRAME_GLOW_LEGEND)
	assert_int(b.glow_pad(b.frame_look())).is_equal(pad_b)
	# the first frame has nothing before it; the second is cut round the first (its centre in the layer's px: the
	# first's middle at (-108, 100) in b's space, plus the pad; half 100; solid); the third sees no neighbour
	assert_int(a.glow_cuts(int(R.FRAME_GLOW_EPIC)).size()).is_equal(0)
	var cuts := b.glow_cuts(pad_b)
	assert_int(cuts.size()).is_equal(1)
	assert_float(cuts[0].x).is_equal_approx(-108.0 + pad_b, 0.01)
	assert_float(cuts[0].y).is_equal_approx(100.0 + pad_b, 0.01)
	assert_float(cuts[0].z).is_equal_approx(100.0, 0.01)
	assert_float(cuts[0].w).is_equal_approx(1.0, 0.001)
	assert_int(c.glow_cuts(int(R.FRAME_GLOW_EPIC)).size()).is_equal(0)
	var bmat := (b.find_child("RoyaleFrame", false, false) as Control).material as ShaderMaterial
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(1)
	var set_cuts: PackedVector4Array = bmat.get_shader_parameter("cuts")
	assert_int(set_cuts.size()).is_equal(WPlate.GLOW_CUTS)
	assert_float(set_cuts[0].z).is_equal_approx(100.0, 0.01)
	var amat := (a.find_child("RoyaleFrame", false, false) as Control).material as ShaderMaterial
	assert_int(int(amat.get_shader_parameter("cut_count"))).is_equal(0)
	# a see-through neighbour (the HUD's empty slot at 50 %) cuts half
	a.plate_alpha = 0.5
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(b.glow_cuts(pad_b)[0].w).is_equal_approx(0.5, 0.001)
	a.plate_alpha = 1.0
	# rays on: the frame paints over everything, no cuts
	b.rays = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(0)
	b.rays = false
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(1)
	# the reach capped at half the gap: the frame layer and its glow shrink to it and the neighbour is out of reach
	b.glow_reach = 4.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(b.glow_pad(b.frame_look())).is_equal(4)
	var layer := b.find_child("RoyaleFrame", false, false) as Control
	assert_float(layer.position.x).is_equal(-4.0)
	assert_float(float(bmat.get_shader_parameter("glow_px"))).is_equal(4.0)
	assert_float(float(bmat.get_shader_parameter("pad"))).is_equal(4.0)
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(0)
	b.glow_reach = -1.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(layer.position.x).is_equal(float(-pad_b))
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(1)
	# the plate moved (its own transform): the cuts are read again, the neighbour out of reach, back when it returns
	b.position = Vector2(1200, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(0)
	b.position = Vector2(208, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(1)
	# the neighbour taken away (the parent's child order changes): the cut goes
	host.remove_child(a)
	a.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(int(bmat.get_shader_parameter("cut_count"))).is_equal(0)
	# a common frame has no glow and no cuts, whoever stands beside it
	var d: WPlate = WPlate.new().for_def(_passive_of("common"), 200.0, false, 1)
	d.position = Vector2(808, 0)
	host.add_child(d)
	await get_tree().process_frame
	assert_int(d.glow_pad(d.frame_look())).is_equal(0)
	assert_int(d.glow_cuts(0).size()).is_equal(0)
	host.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- the meters, the coin, the pointer, the card, the line

func test_the_pieces_build_and_draw_under_both_themes() -> void:
	var epic := _passive_of("epic")
	var weapon: WeaponDef = Registry.weapon("boomstick")
	for royale in [true]:
		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(host)
		var col := VBoxContainer.new()
		col.position = Vector2(40, 40)
		col.size = Vector2(900, 1200)
		host.add_child(col)
		var xp := WBar.make(0.62, W.EPIC, 22.0, 2, 0)
		var boss := WBar.make(0.45, W.ROCK, 30.0, 4, 4)
		boss.text = "GUARDED"
		boss.text_px = 18
		var gold := WBar.make(0.8, W.BRASS, 26.0, 4, 0)
		gold.gain = 0.25
		var loss := WBar.make(0.6, W.SAGE, 48.0, 4, 0)
		loss.loss = 0.15
		for b in [xp, boss, gold, loss]:
			col.add_child(b)
		var sl := WSlider.make(0.65, 0.0, 1.0)
		col.add_child(sl)
		var sl2 := WSlider.make_levels(0.5, 5)
		col.add_child(sl2)
		var coin := WCoin.make(60.0)
		col.add_child(coin)
		var aged := WCoin.make(34.0, W.AGED)
		col.add_child(aged)
		var pointer := WPointer.new()
		pointer.color = W.SAGE
		pointer.text = "PORTAL 24 m"
		col.add_child(pointer)
		var line := WStarLine.make("Level up", 30, W.PAPER)
		col.add_child(line)
		var ink_line := WStarLine.make("Wanted", 26, W.INK, 0.4)
		col.add_child(ink_line)
		var marks := WMarks.new().setup("stars", 5, 3, 4, 40.0)
		marks.pulse = true
		col.add_child(marks)
		var seal := WSeal.new().for_rarity("epic", 96.0)
		col.add_child(seal)
		var stamp := WStamp.make("UNLOCKED", W.SAGE, 30)
		col.add_child(stamp)
		var nail := WNail.new()
		col.add_child(nail)
		var notches := WNotches.make("+6", "+12", 2)
		col.add_child(notches)
		var ph := WPlaceholder.make("", "a picture", Vector2(200, 120))
		col.add_child(ph)
		var card := WCard.make(epic, {"word": "PASSIVE", "word_color": W.INK_SOFT, "name": epic.display_name, "stars": [4, 1, -1],
			"effect": "The more you are hurt, the harder you hit.", "rarity": "", "plate_px": 160.0, "level": 1, "tag": "NEW"})
		col.add_child(card)
		var up := WCard.make(weapon, {"word": "WEAPON", "word_color": W.WEAPON_INK, "name": weapon.display_name, "stars": [5, 3, 4],
			"rarity": "", "plate_px": 160.0, "level": 4, "tag": "UPGRADE", "price": 40, "short": 8,
			"changes": [{"stat": "knockback", "name": "Knockback", "before": "8", "after": "10", "worse": false}]})
		col.add_child(up)
		var buy := WCard.make(weapon, {"word": "WEAPON", "name": weapon.display_name, "stars": [5, 0, 1], "rarity": "", "plate_px": 160.0,
			"level": 1, "tag": "NEW", "price": 40, "short": 0, "favourite": true})
		col.add_child(buy)
		up.show_held(true)
		var shine = load("res://ui/wanted/WShine.gd").make(Vector2(300, 300), 200.0)
		shine.put(host)
		var cel := WCelebrate.burst(host, Vector2(400, 400), 0, 2.0)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		assert_bool(is_instance_valid(cel)).override_failure_message("royale=%s" % royale).is_true()
		if royale:
			assert_bool(WBar.royale_fill(W.ROCK)[0].is_equal_approx(R.BAR_BOSS)).is_true()
			assert_bool(WBar.royale_fill(W.SAGE)[0].is_equal_approx(R.BAR_HP)).is_true()
			assert_bool(WBar.royale_fill(W.EPIC)[0].is_equal_approx(R.BAR_XP)).is_true()
			assert_bool(WBar.royale_fill(W.RARE)[0].is_equal_approx(WBar.SHIELD)).is_true()
			assert_bool(WBar.royale_fill(W.BRASS)[1].is_equal_approx(R.BAR_GOLD_LIP)).is_true()
			assert_bool(WBar.kind_fill("xp")[0].is_equal_approx(R.BAR_XP)).is_true()
			assert_bool(WBar.kind_fill("boss")[1].is_equal_approx(R.BAR_BOSS_LIP)).is_true()
			assert_bool(WPointer.royale_arrow(W.SAGE).is_equal_approx(R.role("green")["bottom"])).is_true()
			assert_bool(WPointer.royale_arrow(W.ROCK).is_equal_approx(R.role("gold")["bottom"])).is_true()
			assert_bool(line.color.is_equal_approx(R.GOLD_TEXT)).is_true()
			assert_bool(ink_line.color.is_equal_approx(R.GOLD_TEXT)).is_true()
			assert_bool(R.is_display(line._text.font)).is_true()
			assert_bool(R.is_display(ink_line._text.font)).is_false()
			# the card: the word line names the passive item's rarity in its colour, the tag is a Royale pill
			var wl: WText = card.find_child("WordLine", true, false).get_child(0)
			assert_int(wl.runs.size()).is_equal(2)
			assert_str(str(wl.runs[1][0])).is_equal(" EPIC")
			assert_bool((wl.runs[1][1] as Color).is_equal_approx(R.RARITY["epic"]["light"])).is_true()
			assert_bool((wl.runs[0][1] as Color).is_equal_approx(R.SECONDARY)).is_true()
			var wwl: WText = up.find_child("WordLine", true, false).get_child(0)
			assert_int(wwl.runs.size()).is_equal(1)
			var tag: PanelContainer = card.find_child("Tag", true, false)
			var tsb := tag.get_theme_stylebox("panel") as StyleBoxFlat
			assert_object(tsb).is_not_null()
			assert_bool(tsb.bg_color.is_equal_approx(WItem.tag_fill("NEW"))).is_true()
			assert_bool(WItem.tag_fill("NEW").is_equal_approx(R.TAG_GOLD)).is_true()
			assert_bool(WItem.tag_fill("UPGRADE").is_equal_approx(R.TAG_GREEN)).is_true()
			assert_bool(WItem.tag_fill("EVOLUTION").is_equal_approx(R.TAG_PURPLE)).is_true()
			assert_bool(WItem.tag_text("NEW").is_equal_approx(R.NAVY)).is_true()
			assert_bool(WItem.tag_text("EVOLUTION").is_equal_approx(R.CREAM)).is_true()
			assert_object(tag.find_child("Chevron", true, false)).is_null()
			assert_bool(card.plate.rays).is_false()
			assert_bool(up.plate.rays).is_true()
			assert_bool(up.is_processing()).is_true()
			assert_str(up.price_button.role).is_equal(WButton.LOCKED)
			assert_str(buy.price_button.role).is_equal(WButton.GREEN)
			assert_bool(card.rivet).is_true()
			assert_str(card.box.royale_kind()).is_equal("panel")
			assert_bool(sl.knob_rect().size.is_equal_approx(R.SLIDER_KNOB)).is_true()
			assert_str(sl.shown_text()).is_equal("65")
		else:
			assert_object(coin.material).is_null()
			assert_bool(line.color.is_equal_approx(W.PAPER)).is_true()
			assert_bool(ink_line.color.is_equal_approx(W.INK)).is_true()
			var wl: WText = card.find_child("WordLine", true, false).get_child(0)
			assert_int(wl.runs.size()).is_equal(0)
			assert_str(wl.text).is_equal("PASSIVE")
			var tag: PanelContainer = card.find_child("Tag", true, false)
			assert_bool(tag.get_theme_stylebox("panel") is HardBox).is_true()
			assert_object(up.find_child("Chevron", true, false)).is_not_null()
			assert_bool(up.plate.rays).is_false()
			assert_bool(up.is_processing()).is_false()
			assert_bool(up.price_button.box.fill.is_equal_approx(W.PAPER)).is_true()
			assert_bool(buy.price_button.box.fill.is_equal_approx(W.BRASS)).is_true()
		# a finger drags the slider under either theme
		var before := sl.value
		sl._follow(Vector2(sl.size.x * 0.25, 10.0))
		assert_float(sl.value).is_not_equal(before)
		host.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame


func test_no_w_colour_constant_moves() -> void:
	var pins := [[W.INK, Color("241b14")], [W.PAPER, Color("f3e6c8")], [W.AGED, Color("e2cfa4")], [W.BRASS, Color("c9932f")],
		[W.BRASS_DARK, Color("a8792a")], [W.ROCK, Color("b4472b")], [W.SAGE, Color("6e8b5e")], [W.INK_SOFT, Color("5a4a3a")],
		[W.EPIC, Color("8a4fb0")], [W.RARE, Color("3e6e9e")], [W.COMMON, Color("8a8f7a")], [W.EMBER, Color("d9662a")],
		[W.EVOLVED_FILL, Color("241b14")], [W.EVOLVED_RING, Color("c9932f")]]
	for pair in pins:
		assert_bool((pair[0] as Color).is_equal_approx(pair[1])).override_failure_message(str(pair[1])).is_true()
	for k in ["common", "uncommon", "rare", "epic", "legendary"]:
		assert_bool(W.RARITY_PLATE.has(k)).is_true()
	assert_bool(W.RARITY_PLATE["common"].is_equal_approx(Color("d2cfc7"))).is_true()
	assert_bool(W.RARITY_PLATE["legendary"].is_equal_approx(Color("e0a060"))).is_true()
	# the Wanted marks' and star line's colours are the kit's (the Royale ones are their own constants)
	assert_bool(WMarks.ROYALE_HELD.is_equal_approx(R.GOLD_TEXT)).is_true()
	assert_bool(WMarks.ROYALE_NEXT.is_equal_approx(R.CREAM)).is_true()
	assert_bool(WStarLine.royale_colour(W.PAPER).is_equal_approx(R.GOLD_TEXT)).is_true()
	assert_bool(WCelebrate.royale_colour(W.BRASS).is_equal_approx(R.role("gold")["bottom"])).is_true()
	assert_bool(WSeal.royale_fill(W.EPIC).is_equal_approx(R.RARITY["epic"]["base"])).is_true()
