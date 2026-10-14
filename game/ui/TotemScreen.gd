## The Totem Pole's gifts (pass 73, Garry: "When activated a menu pops up offering Players a choice between 3 small stats
## improvements for that run ... Use thematical language and visuals for this menu, but also write the stats as simple
## numbers"). A dark cedar dim, "★ CARVED SPIRITS ★ / THE TOTEM", the pole's own painting with a glow behind it, and
## three carved planks, one gift each: the gift's amount big on a paper disc ("+6%"), the spirit's word in slab
## ("LE-LOO"), its animal in italic ("the Wolf") and the gift as a plain line ("+6% move speed", TextGen). One to three
## feathers hang from a plank's corner: how big its amount rolled within its range (TotemBoons.quality). A tap on a
## plank takes it (raw touch, WTap); the screen closes at once and the run goes on. Nothing to buy, nothing to refuse.
class_name TotemScreen
extends WModal

signal closed(boon: Dictionary)

## the dim: a dark cedar brown, a shade deeper than the other modals' sepia, so the planks stand out
const DIM_TOTEM := Color(34 / 255.0, 20 / 255.0, 12 / 255.0, 0.86)
## the planks' wood, its carved grooves and grain, the held plank's darker wood
const WOOD := Color("9a5733")
const WOOD_DARK := Color("6a361c")
const WOOD_HELD := Color("7e4426")
const GRAIN := Color(0.35, 0.17, 0.08, 0.32)
## the feathers: paper vanes, a rock-red band, an ink tip, a turquoise wrap at the quill
const FEATHER := Color("f3e6c8")
const FEATHER_BAND := Color("b4472b")
const FEATHER_WRAP := Color("3f8f8a")
## sizes (canvas px at 1080 x 1920)
const SIDE := 48.0
const PLANK_GAP := 30.0
const PLANK_PAD := Vector4(30, 26, 132, 26)   # left, top, right (room for the feathers), bottom
const DISC_R := 86.0
## the pole's painting between the header and the planks: as tall as the room there allows, between ART_MIN and ART_MAX
const ART_MIN := 140.0
const ART_MAX := 380.0
const ART_GAP := 14.0
const WORD_PX := 62
const ANIMAL_PX := 30
const LINE_PX := 34
const AMOUNT_PX := 54
## the gap under the header; the planks sit low, in the thumb's reach (a one-thumb game), the last one's foot FOOT over
## the screen's bottom edge
const BODY_GAP := 18.0
const FOOT := 150.0
const FOOT_MIN := 60.0

## core/systems/TotemBoons.gd, by path (a new script's class name is unknown until the editor imports it)
const BOONS := preload("res://core/systems/TotemBoons.gd")

var _art: Control
var _art_tex: Texture2D
var _list: Control
var _planks: Array = []
var _offer: Array = []
var _done := false
var _t := 0.0


## One carved plank: a WTap whose box is the cedar, drawn over with its grooves, grain and feathers.
class Plank:
	extends WTap
	var boon: Dictionary = {}
	var feathers := 1
	var sway := 0.0
	var disc: Control
	var amount: WText
	var word: WText
	var animal: WText
	var line: WText

	func held_offset() -> Vector2:
		return Vector2(box.shadow, box.shadow) if _held_look and box else Vector2.ZERO

	func _draw() -> void:
		var o := held_offset()
		var r := Rect2(o, size)
		# the grain: a few long wavy lines across the wood, inside the border
		var inner := r.grow(-12.0)
		for k in range(5):
			var y := inner.position.y + inner.size.y * (0.14 + 0.18 * k)
			var pts := PackedVector2Array()
			var steps := 24
			for s in range(steps + 1):
				var x := inner.position.x + inner.size.x * float(s) / float(steps)
				pts.append(Vector2(x, y + sin(float(s) * 0.7 + k * 1.9) * 3.0))
			draw_polyline(pts, GRAIN, 2.0)
		# the carved groove: a frame cut a little inside the ink border
		draw_rect(r.grow(-15.0), WOOD_DARK, false, 4.0)
		# formline corners: small turquoise ovoids in the groove's corners
		for c in [r.position + Vector2(15, 15), Vector2(r.end.x - 15, r.position.y + 15), Vector2(r.position.x + 15, r.end.y - 15), r.end - Vector2(15, 15)]:
			draw_circle(c, 7.0, W.INK)
			draw_circle(c, 4.5, FEATHER_WRAP)
		# the feathers, hung from pegs along the plank's top right, swaying a little
		for k in range(feathers):
			var peg := Vector2(r.end.x - 44.0 - 34.0 * k, r.position.y + 24.0)
			var ang := deg_to_rad(8.0 + 7.0 * k) + sway * (1.0 + 0.3 * k)
			TotemScreen.draw_feather(self, peg, ang, minf(size.y - 46.0, 170.0), 30.0)


func _ready() -> void:
	build_dim(DIM_TOTEM)
	build_header("Carved spirits", "THE TOTEM", "Choose one gift. It stays with you all run.", 120, W.PAPER)
	_art = Control.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	add_child(_art)
	_list = Control.new()
	_list.name = "Planks"
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)


## `offer`: the gifts (TotemBoons.offer), `def` the pole (its painting is drawn at the top).
func open(offer: Array, def: StructureDef = null) -> void:
	_offer = offer
	_done = false
	var path := "res://art/sprites/props/st_%s.png" % (def.id if def else "totem_pole")
	_art_tex = load(path) if ResourceLoader.exists(path) else null
	for p in _planks:
		(p as Node).queue_free()
	_planks.clear()
	for b in _offer:
		var pl := _make_plank(b as Dictionary)
		_list.add_child(pl)
		_planks.append(pl)
	modulate.a = 1.0
	_layout()
	var stagger: Array = [_art]
	stagger.append_array(_planks)
	enter(stagger)
	Audio.play("ui_pause")


## The planks low on the screen, in the thumb's reach: the last one's foot FOOT over the bottom edge, one over another at
## their own heights (nothing on a plank wraps, so its size is known at once, before the slide-in reads the positions);
## the pole's painting in the room between the header's real foot (it carries W.safe_top() already) and the first
## plank, as tall as fits between ART_MIN and ART_MAX, in the middle of it. A short screen pushes the planks down to
## FOOT_MIN over the edge, then squeezes their gaps.
func _layout() -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1080, 1920)
	var top := header.offset_top + header.get_combined_minimum_size().y + BODY_GAP
	var w := vp.x - SIDE * 2.0
	var heights: Array = []
	var total := 0.0
	for p: Plank in _planks:
		p.size.x = w
		var h := maxf(p.get_combined_minimum_size().y, DISC_R * 2.0 + PLANK_PAD.y + PLANK_PAD.w)
		heights.append(h)
		total += h
	var n := _planks.size()
	var gap := PLANK_GAP
	var block := total + gap * maxf(n - 1, 0)
	var foot := vp.y - FOOT
	var first := foot - block
	# too little room for the painting: the planks go down first, then their gaps close up
	if first - ART_GAP - top < ART_MIN:
		foot = minf(vp.y - FOOT_MIN, top + ART_MIN + ART_GAP + block)
		first = foot - block
		if first - ART_GAP - top < ART_MIN and n > 1:
			gap = maxf(gap - (top + ART_MIN + ART_GAP - first) / float(n - 1), 12.0)
			block = total + gap * (n - 1)
			first = foot - block
	var room := maxf(first - ART_GAP - top, 0.0)
	var art_h := clampf(room, minf(ART_MIN, room), ART_MAX)
	_art.position = Vector2(0, top + (room - art_h) * 0.5)
	_art.size = Vector2(vp.x, art_h)
	_art.queue_redraw()
	var y := first
	for k in range(n):
		var p: Plank = _planks[k]
		p.position = Vector2(SIDE, y)
		p.size = Vector2(w, heights[k])
		y += float(heights[k]) + gap


func _make_plank(b: Dictionary) -> Plank:
	var p := Plank.new()
	p.name = "Plank_%s" % str(b.get("id", ""))
	p.boon = b
	p.feathers = clampi(int(b.get("quality", 1)), 1, 3)
	var hb := W.box(WOOD, 5, 10).pad(PLANK_PAD.x, PLANK_PAD.y, PLANK_PAD.z, PLANK_PAD.w)
	p.box = hb
	var down := hb.pressed(WOOD_HELD)
	down.inner = 5
	down.inner_color = W.BRASS
	p.box_down = down
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	# the disc: the amount big on paper
	var disc := Control.new()
	disc.custom_minimum_size = Vector2(DISC_R * 2.0 + 10.0, DISC_R * 2.0 + 10.0)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.draw.connect(func() -> void:
		var c := Vector2(DISC_R, DISC_R) + Vector2(2, 2)
		disc.draw_circle(c + Vector2(8, 8), DISC_R, W.INK)
		disc.draw_circle(c, DISC_R, W.INK)
		disc.draw_circle(c, DISC_R - 5.0, W.PAPER)
		disc.draw_arc(c, DISC_R - 16.0, 0.0, TAU, 48, Color(W.INK, 0.25), 3.0))
	row.add_child(disc)
	p.disc = disc
	var amount := W.slab_text(BOONS.amount_text(b), AMOUNT_PX, W.INK, HORIZONTAL_ALIGNMENT_CENTER)
	amount.name = "Amount"
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount.valign = VERTICAL_ALIGNMENT_CENTER
	amount.position = Vector2(2, 2)
	amount.size = Vector2(DISC_R * 2.0, DISC_R * 2.0)
	amount.custom_minimum_size = Vector2(DISC_R * 2.0, DISC_R * 2.0)
	disc.add_child(amount)
	p.amount = amount
	# the words
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var word := W.slab_text(str(b.get("name", "")).to_upper(), WORD_PX, W.PAPER)
	word.name = "Word"
	word.shadow = 5
	col.add_child(word)
	p.word = word
	var animal := W.serif_text(str(b.get("animal", "")), ANIMAL_PX, W.AGED, 400, true)
	animal.name = "Animal"
	animal.visible = str(b.get("animal", "")) != ""
	col.add_child(animal)
	p.animal = animal
	var line := W.serif_text(BOONS.text(b), LINE_PX, W.PAPER, 600, false, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	line.name = "Line"
	line.shadow = 3
	col.add_child(line)
	p.line = line
	W.pass_through(p)
	p.pressed.connect(func() -> void: _pick(p))
	return p


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for k in range(_planks.size()):
		var p: Plank = _planks[k]
		if is_instance_valid(p):
			p.sway = 0.05 * sin(_t * 1.7 + k * 1.3)
			p.queue_redraw()


## The pole's own painting at the top, a soft turquoise glow behind it and a feather either side.
func _draw_art() -> void:
	var r := Rect2(Vector2.ZERO, _art.size)
	var c := Vector2(r.size.x * 0.5, r.size.y * 0.52)
	WMarks.glow(_art, c, r.size.y * 0.62, Color(FEATHER_WRAP, 0.42))
	if _art_tex:
		var ts := _art_tex.get_size()
		var k := r.size.y / maxf(ts.y, 1.0)
		var sz := ts * k
		_art.draw_texture_rect(_art_tex, Rect2(Vector2((r.size.x - sz.x) * 0.5, 0.0), sz), false)
	var h := r.size.y * 0.62
	draw_feather(_art, Vector2(c.x - r.size.y * 0.62, c.y - h * 0.1), deg_to_rad(28.0), h, 34.0)
	draw_feather(_art, Vector2(c.x + r.size.y * 0.62, c.y - h * 0.1), deg_to_rad(-28.0), h, 34.0)


## A feather hung from `peg`, `ang` radians off straight down (positive leans it left), `length` and `width` px: the
## quill and its turquoise wrap, a paper vane with two notches, a rock-red band and an ink tip, all in an ink line.
static func draw_feather(ci: CanvasItem, peg: Vector2, ang: float, length: float, width: float) -> void:
	var dir := Vector2(-sin(ang), cos(ang))
	var n := Vector2(-dir.y, dir.x)
	var cord_end := peg + dir * 10.0
	ci.draw_line(peg, cord_end, W.INK, 3.0)
	var base := cord_end
	# the vane: a long leaf from 0.12 to 1.0 of the length
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 14
	for s in range(steps + 1):
		var t := 0.12 + 0.88 * float(s) / float(steps)
		var half := width * 0.5 * pow(sin(PI * minf(t * 1.08, 1.0)), 0.7)
		if t > 0.96:
			half *= 0.4
		var p := base + dir * (length * t)
		left.append(p + n * half)
		right.append(p - n * half)
	var vane := PackedVector2Array()
	vane.append_array(left)
	var rev := right.duplicate()
	rev.reverse()
	vane.append_array(rev)
	ci.draw_colored_polygon(vane, FEATHER)
	# the band and the tip: the vane's last part in red, then ink
	var band := _vane_part(left, right, 0.62, 0.78)
	if band.size() >= 3:
		ci.draw_colored_polygon(band, FEATHER_BAND)
	var tip := _vane_part(left, right, 0.86, 1.0)
	if tip.size() >= 3:
		ci.draw_colored_polygon(tip, W.INK)
	var closed := vane.duplicate()
	closed.append(vane[0])
	ci.draw_polyline(closed, W.INK, 3.0, true)
	# the quill down the middle and its wrap at the root
	ci.draw_line(base, base + dir * length * 0.98, Color(W.INK, 0.8), 2.5)
	ci.draw_line(base + dir * length * 0.04, base + dir * length * 0.16, FEATHER_WRAP, 7.0)
	# two notches cut into the vane's edge
	for t in [0.42, 0.55]:
		var i := int(round(float(steps) * (t - 0.12) / 0.88))
		i = clampi(i, 1, steps - 1)
		ci.draw_line(left[i], left[i].lerp(base + dir * (length * t), 0.55) + dir * 6.0, W.INK, 2.5)


## The stretch of the vane between `a` and `b` (fractions of its points) as one polygon.
static func _vane_part(left: PackedVector2Array, right: PackedVector2Array, a: float, b: float) -> PackedVector2Array:
	var n := left.size()
	var i0 := clampi(int(round(a * float(n - 1))), 0, n - 1)
	var i1 := clampi(int(round(b * float(n - 1))), 0, n - 1)
	var out := PackedVector2Array()
	for i in range(i0, i1 + 1):
		out.append(left[i])
	for i in range(i1, i0 - 1, -1):
		out.append(right[i])
	return out


func _pick(p: Plank) -> void:
	if _done or not visible:
		return
	_done = true
	W.sfx_first(["ui_totem", "ui_card_pick"])
	p.show_held(true)
	var tw := create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(func() -> void: _finish(p.boon))


## The gifts on the planks as offered (tests, tools).
func offer() -> Array:
	return _offer


## The planks in order (tests, tools).
func planks() -> Array:
	return _planks


func _finish(boon: Dictionary) -> void:
	if not visible:
		return
	visible = false
	closed.emit(boon)
