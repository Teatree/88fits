## The Totem Pole's gifts: "The Spirit Pole" (pass 82, lane TOTEM; design_handoff_88fits_totem, direction 1b, after
## pass 73's carved planks). The offer builds a pole on the left of the screen: the thunderbird crest on top, the three
## offered spirits as carved segments stacked under it (the kit's item plate in rock with a carved inset, the spirit's
## face on it), a paper tag nailed beside each: the amount big in slab with its stat ("+2%" "move speed"), the spirit
## ("Le-loo, the Wolf"), and the roll gauge (the range's two ends and three notches: which third of that gift's own range
## the roll landed in; the number turns brass dark on a top third). Over the paused world in the modal dim, the HUD
## hidden. "★ TOTEM 4 OF 11 ★" over it all (this gift's count of the map's poles). No title, no buttons, no way out:
## each gift row (its segment and its tag) is one tap target; anywhere else does nothing.
## Motion (the README's): open 460 ms (the in-world ring flashes first, Game/StructureManager), press 60 ms, a drag out
## cancels in 90 ms, close 420 ms: the chosen face flies to the toast slot and shrinks, the rest drops and fades, the run
## goes on at 300 ms (`closed`) with the toast "Le-loo · +2% move speed" carrying the face.
class_name TotemScreen
extends WModal

signal closed(boon: Dictionary)
## The gift is taken and the screen starts to close (the in-world pole greys from here).
signal closing(boon: Dictionary)

## core/systems/TotemBoons.gd, by path (a new script's class name is unknown until the editor imports it)
const BOONS := preload("res://core/systems/TotemBoons.gd")
const CREST_PATH := "res://art/ui/totem/crest.png"

# --- layout: canvas px at 1080 x 1920, top-anchored (a taller phone adds room under the base) -------------------------
## The design keeps the top SAFE_DESIGN px empty; a camera cutout deeper than that moves everything down by the rest.
const SAFE_DESIGN := 130.0
const LABEL_AT := Vector2(60, 300)
const LABEL_PX := 30
## The mock sets "★ TOTEM 4 OF 11 ★" as one string tracked +35 % (10.5 px). Godot tracks in whole px (10) and does not
## track a space, so a space is LABEL_SPACE wider (its tracking and the half px the glyphs lose): every glyph lands within
## 2 px of the mock's over the line. Bitter has no ★: the stars are drawn (WMarks.star, as WStarLine draws them).
const LABEL_TRACK := 10
const LABEL_SPACE := 12
## the right star sits this much further out than a tracked space and the left star's inset (the mock's ★ is a fallback
## glyph that advances wider than its ink; measured on screens/01)
const LABEL_STAR_PAD := 22.0
const LABEL_STAR_R := 12.0
## the left star's middle and the words' box in the label (canvas: the star at 72, 323; the T's ink at 112)
const LABEL_STAR_L := Vector2(12, 23)
const LABEL_TEXT_X := 50.0
## the words' baseline under the label's top: the mock's line box is pushed 3 px down by its ★ (a fallback face with a
## taller ascent), so its baseline sits at 331, not at the 328 Bitter alone would give
const LABEL_BASELINE := 31.0
const CREST_AT := Vector2(0, 372)
const CREST_W := 420.0
## Pass 83 (lane TOTEM): the crest is the pole's top: centred on the column, at most CREST_MAX_H tall (it never reaches
## the label), its foot CREST_SINK px down behind the top segment so the bird sits on the column.
const CREST_MAX_H := 150.0
const CREST_SINK := 12.0
## Pass 83: the cedar post behind the segments, from under the crest to the base, so the gaps between the plates read as
## the same pole (POST_W wide, centred on the column; the plates' rock darkened, ink sides, the carved inset).
const POST_W := 200.0
const POST_FILL := Color(0x7a / 255.0, 0x34 / 255.0, 0x1f / 255.0)
## The pole's bare cedar (the wood every painted segment is laid on, tools/gen_totem_icons.py): the post (shaded by
## POST_SHADE, it stands back) and the base are cut from it; without the file they are POST_FILL and rock.
const CEDAR_PATH := "res://art/ui/totem/cedar.png"
const POST_SHADE := Color(0.72, 0.72, 0.72)
const SEG_X := 60.0
const SEG := 300.0
const SEG_Y: Array = [500.0, 840.0, 1180.0]
const SEG_BORDER := 6
const SEG_RADIUS := 10
## the carved inset: `box-shadow: inset 0 0 0 8px rgba(0,0,0,.18)` (WPlate's inner ring)
const CARVE := 8
const CARVE_COLOR := Color(0, 0, 0, 0.18)
## Pass 83 (lane TOTEM): the carved segment fills its plate inside the ink border (the painted segments are opaque
## squares of the pole), the carved inset and the border drawn again over it (GiftRow.carve)
const FACE := SEG - 2.0 * SEG_BORDER
const WORD_PX := 40
## the room a word keeps from the plate's border on either side before it shrinks
const WORD_CLEAR := 4.0
## the tag: x 390 on the canvas, 30 px under its segment's top (centred on it); TAG_AT is where that is in a gift row
## (whose origin is its segment's top-left)
const TAG_X := 390.0
const TAG_AT := Vector2(TAG_X - SEG_X, 30)
const TAG := Vector2(630, 240)
const TAG_BORDER := 5
const TAG_SHADOW := 8
## padding inside the border: 40 left, 30 right; the three lines centred top to bottom, LINE_GAP apart
const TAG_PAD_L := 40.0
const TAG_PAD_R := 30.0
const LINE_GAP := 10.0
const AMOUNT_PX := 48
const STAT_PX := 30
const AMOUNT_GAP := 14.0
const SPIRIT_PX := 26
## the nail's middle: 2 px right of the tag's left edge (CSS left -19 px on the padding box, 32 px wide)
const NAIL_DX := 2.0
const BASE_AT := Vector2(30, 1510)
const BASE := Vector2(360, 64)
const BASE_RADIUS := 6

# --- states ------------------------------------------------------------------------------------------------------------
const PRESS_SEG_X := 14.0
const PRESS_TAG := Vector2(8, 8)
const PRESS_INNER := 6
const GLOW_PX := 44
## CSS `0 0 44px` is a Gaussian (half strength at the plate's edge, a fifth at 20 px out); StyleBoxFlat's shadow fades
## linearly over its size, so a third of the colour at the edge matches it from 15 px out
const GLOW_COLOR := Color(0x3f / 255.0, 0x8f / 255.0, 0x8a / 255.0, 0.36)
const OTHERS_ALPHA := 0.6
const T_PRESS := 0.06
const T_CANCEL := 0.09

# --- motion (seconds) --------------------------------------------------------------------------------------------------
## open: the ring's flash (the world, StructureManager.flash_ring), then the dim, the crest, the segments and tags, the base
const T_FLASH := 0.12
const T_DIM_IN := 0.16
const T_CREST := 0.22
const CREST_FROM_Y := -80.0
const T_SEG := 0.18
const SEG_STAGGER := 0.06
const SEG_RISE := 60.0
const TAG_AFTER := 0.04
const T_TAG := 0.16
const TAG_SLIDE := 40.0
const T_BASE := 0.12
const T_OPEN := 0.46
## close: the face's flight, the others dropping, the fades, the dim lifting last; the run goes on at T_CONTROL
const T_FLY := 0.30
const FLY_TO := 72.0
const T_DROP := 0.2
const DROP_PX := 140.0
const T_FADE := 0.15
const T_DIM_OUT := 0.15
const T_CONTROL := 0.30
const T_CLOSE := 0.42
## where the face flies when no HUD says where its toast's icon goes (the README's toast slot)
const TOAST_SLOT := Vector2(540, 300)

var _offer: Array = []
var _rows: Array = []
var _done := false
var _label: Control
var _label_text: WText
var _crest: TextureRect
var _base: Control
var _post: Control
var _flyer: TextureRect
var _held_row: GiftRow
var _tweens: Array = []
var _dy := 0.0
var _index := 0
var _total := 0


## One gift: its carved segment and its nailed tag, one tap target (a WTap, so the kit's audits find it). Its pieces sit
## in `body` (a plain Control), free-placed as the mock places them, inside `group` (a CanvasGroup: the row fades as one
## picture, as CSS opacity does; faded piece by piece, the tag's shadow showed through its paper).
class GiftRow:
	extends WTap

	signal hold_changed(on: bool)

	var boon: Dictionary = {}
	## the roll's third (1..3): the gauge's filled notches (the bot's "feathers" since pass 73)
	var feathers := 1
	var group: CanvasGroup
	var body: Control
	var seg: Control
	var glow: Panel
	var glow_holder: Node2D
	var plate: WPlate
	## pass 83: the carved inset and the ink border over the face (the face fills the plate inside its border)
	var carve: Control
	var word: WText
	var tag: Panel
	var tag_box: HardBox
	var tag_box_down: HardBox
	var nail: WNail
	var amount: WText
	var stat: WText
	var spirit: WText
	var gauge: WNotches
	var seg_home := Vector2.ZERO
	var tag_home := Vector2.ZERO
	## taking a finger: set once its open motion has landed (a tap on a piece still moving is not a choice)
	var arrived := false
	## pass 83 (lane TOTEM): when its open motion should have landed (Time.get_ticks_msec), so a slow frame at the open
	## (the motion's chained steps each wait a frame) never leaves a landed-looking gift deaf to a finger; -1 = not set
	var arrive_ms := -1
	var held := false
	var screen: Node
	var _touching := false
	var _finger := -1
	var _tw: Tween

	func _ready() -> void:
		super._ready()
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	## The segment (where it sits held, too) and the tag with its nail and shadow: a finger on either is this gift's; the
	## gap beside the nail, between the segment and the tag, is nobody's.
	func _has_point(p: Vector2) -> bool:
		if Rect2(Vector2.ZERO, Vector2(SEG + PRESS_SEG_X, SEG)).has_point(p):
			return true
		var nail := WNail.SIDE * 0.5 - NAIL_DX
		return Rect2(TAG_AT - Vector2(nail, 0), TAG + Vector2(TAG_SHADOW + nail, TAG_SHADOW)).has_point(p)

	func _gui_input(e: InputEvent) -> void:
		var pos := Vector2.ZERO
		var idx := 0
		var kind := ""
		if e is InputEventScreenTouch:
			var t := e as InputEventScreenTouch
			pos = t.position
			idx = t.index
			kind = "press" if t.pressed else "release"
		elif e is InputEventScreenDrag:
			var d := e as InputEventScreenDrag
			pos = d.position
			idx = d.index
			kind = "move"
		elif e is InputEventMouseButton:
			var m := e as InputEventMouseButton
			if m.button_index != MOUSE_BUTTON_LEFT:
				return
			pos = m.position
			idx = -2
			kind = "press" if m.pressed else "release"
		elif e is InputEventMouseMotion:
			pos = (e as InputEventMouseMotion).position
			idx = -2
			kind = "move"
		else:
			return
		match kind:
			"press":
				if not _touching and _can_press():
					_touching = true
					_finger = idx
					_set_held(true)
					accept_event()
			"move":
				if _touching and idx == _finger and not _has_point(pos):
					# dragged out: no choice; back in 90 ms
					_touching = false
					_finger = -1
					_set_held(false)
			"release":
				if _touching and idx == _finger:
					_touching = false
					_finger = -1
					accept_event()
					if _has_point(pos):
						W.sfx("ui_tap")
						pressed.emit()
						# nobody took it (a muted audit): the row stands up again
						if screen == null or not bool(screen.get("_done")):
							_set_held(false)
					else:
						_set_held(false)

	func _can_press() -> bool:
		if screen == null or bool(screen.get("_done")):
			return false
		if not arrived and (arrive_ms < 0 or Time.get_ticks_msec() < arrive_ms):
			return false
		var other = screen.get("_held_row")
		return other == null or other == self

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _touching:
			_touching = false
			_finger = -1
			_set_held(false)

	## The pressed look without a finger (the capture tools; the kit's show_held).
	func show_held(on: bool) -> void:
		_set_held(on)

	func _set_held(on: bool) -> void:
		if held == on:
			return
		held = on
		hold_changed.emit(on)
		if _tw:
			_tw.kill()
		var secs := T_PRESS if on else T_CANCEL
		tag.add_theme_stylebox_override("panel", tag_box_down if on else tag_box)
		_tw = create_tween().set_parallel(true)
		_tw.tween_property(seg, "position", seg_home + (Vector2(PRESS_SEG_X, 0) if on else Vector2.ZERO), secs)
		_tw.tween_property(glow_holder, "position", seg_home + (Vector2(PRESS_SEG_X, 0) if on else Vector2.ZERO), secs)
		_tw.tween_property(tag, "position", tag_home + (PRESS_TAG if on else Vector2.ZERO), secs)
		_tw.tween_property(glow, "modulate:a", 1.0 if on else 0.0, secs)


func _ready() -> void:
	build_dim(W.DIM)
	_label = Control.new()
	_label.name = "Label"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label_text = W.text("TOTEM", label_font(), LABEL_PX, W.PAPER)
	_label_text.name = "Words"
	_label.add_child(_label_text)
	_label.draw.connect(_draw_label_stars)
	_post = Control.new()
	_post.name = "Post"
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.draw.connect(_draw_post)
	add_child(_post)
	_crest = TextureRect.new()
	_crest.name = "Crest"
	_crest.texture = load(CREST_PATH) if ResourceLoader.exists(CREST_PATH) else null
	_crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crest.stretch_mode = TextureRect.STRETCH_SCALE
	_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crest)
	_base = Control.new()
	_base.name = "Base"
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.draw.connect(_draw_base)
	add_child(_base)


## A rock plate with its ink border and carved inset in `rect` of `ci` (the base; the segments are WPlates).
static func carved(ci: CanvasItem, rect: Rect2, radius: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = W.ROCK
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(SEG_BORDER)
	sb.border_color = W.INK
	sb.anti_aliasing = true
	ci.draw_style_box(sb, rect)
	var inset := StyleBoxFlat.new()
	inset.draw_center = false
	inset.set_corner_radius_all(maxi(radius - SEG_BORDER, 0))
	inset.set_border_width_all(CARVE)
	inset.border_color = CARVE_COLOR
	ci.draw_style_box(inset, rect.grow(-SEG_BORDER))


## Pass 83: the carved inset and the ink border drawn over a segment's face (only while it has one).
static func carved_over(ci: CanvasItem, plate: WPlate) -> void:
	if plate == null or plate.tex == null:
		return
	var rect := Rect2(Vector2.ZERO, Vector2(SEG, SEG))
	var inset := StyleBoxFlat.new()
	inset.draw_center = false
	inset.set_corner_radius_all(maxi(SEG_RADIUS - SEG_BORDER, 0))
	inset.set_border_width_all(CARVE)
	inset.border_color = CARVE_COLOR
	ci.draw_style_box(inset, rect.grow(-SEG_BORDER))
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.set_corner_radius_all(SEG_RADIUS)
	edge.set_border_width_all(SEG_BORDER)
	edge.border_color = W.INK
	edge.anti_aliasing = true
	ci.draw_style_box(edge, rect)


static var _cedar: Texture2D
static var _cedar_tried := false


## The bare cedar texture (null when the file is missing).
static func cedar() -> Texture2D:
	if not _cedar_tried:
		_cedar_tried = true
		_cedar = load(CEDAR_PATH) as Texture2D if ResourceLoader.exists(CEDAR_PATH) else null
	return _cedar


## The base: the pole's foot, a cedar plinth in its ink border with the carved inset (rock without the cedar).
func _draw_base() -> void:
	var r := Rect2(Vector2.ZERO, _base.size)
	carved(_base, r, BASE_RADIUS)
	var tex := cedar()
	if tex == null:
		return
	var inner := r.grow(-SEG_BORDER)
	_base.draw_texture_rect_region(tex, inner, Rect2(Vector2.ZERO, Vector2(tex.get_size().x, tex.get_size().x * inner.size.y / inner.size.x)))
	var inset := StyleBoxFlat.new()
	inset.draw_center = false
	inset.set_border_width_all(CARVE)
	inset.border_color = CARVE_COLOR
	_base.draw_style_box(inset, inner)


## Pass 83: the cedar post behind the segments (the pole between its carved plates): darker than the plates, ink sides,
## the carved inset down both sides.
## Drawn only between the segments (behind a faded gift the post would show through it).
func _draw_post() -> void:
	var spans: Array = []
	var y := 0.0
	for k in range(mini(_rows.size(), SEG_Y.size())):
		var top := float(SEG_Y[k]) + _dy - _post.position.y + SEG_BORDER
		if top > y:
			spans.append(Vector2(y, top))
		y = top + SEG - 2.0 * SEG_BORDER
	if _post.size.y > y:
		spans.append(Vector2(y, _post.size.y))
	var w := _post.size.x
	var tex := cedar()
	for sp: Vector2 in spans:
		var h := sp.y - sp.x
		_post.draw_rect(Rect2(0, sp.x, w, h), W.INK)
		var wood := Rect2(SEG_BORDER, sp.x, w - 2.0 * SEG_BORDER, h)
		if tex:
			# the grain runs on down the pole: the texture's middle columns, its rows by where the span sits
			var ts := tex.get_size()
			var k := ts.x / (SEG - 2.0 * SEG_BORDER)
			var src := Rect2((ts.x - wood.size.x * k) * 0.5, fmod(sp.x * k, maxf(ts.y - h * k, 1.0)), wood.size.x * k, minf(h * k, ts.y))
			_post.draw_texture_rect_region(tex, wood, src, POST_SHADE)
		else:
			_post.draw_rect(wood, POST_FILL)
		_post.draw_rect(Rect2(SEG_BORDER, sp.x, CARVE, h), CARVE_COLOR)
		_post.draw_rect(Rect2(w - SEG_BORDER - CARVE, sp.x, CARVE, h), CARVE_COLOR)


## `offer`: the gifts (TotemBoons.offer); `def` the pole; `index` this gift's count this run (1-based) and `total` the
## map's poles (0: unknown, the label says "4TH TOTEM").
func open(p_offer: Array, _def: StructureDef = null, index: int = 0, total: int = 0) -> void:
	_kill_tweens()
	_offer = p_offer
	_done = false
	_held_row = null
	_index = index if index > 0 else _run_index()
	_total = total
	for r in _rows:
		(r as Node).queue_free()
	_rows.clear()
	if _flyer:
		_flyer.queue_free()
		_flyer = null
	var n := mini(_offer.size(), SEG_Y.size())
	for k in range(n):
		var row := _make_row(_offer[k] as Dictionary, k)
		add_child(row)
		_rows.append(row)
	_label_text.text = BOONS.pole_label(_index, _total)
	if not is_in_group("wanted_modal"):
		add_to_group("wanted_modal")
	modulate.a = 1.0
	visible = true
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	_open_motion()
	Audio.play("ui_pause")


## Gifts taken so far this run + 1 (when the caller gives no count).
func _run_index() -> int:
	var run := W.node("Run")
	return (run.get("totem_boons") as Array).size() + 1 if run and run.get("totem_boons") is Array else 1


## The label's words as shown (tests, tools): "TOTEM 4 OF 11" or "4TH TOTEM", between the drawn stars.
func label_text() -> String:
	return _label_text.text if _label_text else ""


func _layout() -> void:
	_dy = maxf(W.safe_top() - SAFE_DESIGN, 0.0)
	_label.position = LABEL_AT + Vector2(0, _dy)
	var lf := label_font()
	_label_text.position = Vector2(LABEL_TEXT_X, LABEL_BASELINE - _baseline_in(lf, LABEL_PX, W.normal_height(lf, LABEL_PX)))
	_label_text.size = _label_text.get_combined_minimum_size()
	_label.size = Vector2(label_star_r().x + LABEL_STAR_R, 46)
	_label.queue_redraw()
	var col_x := SEG_X + SEG * 0.5
	_crest.size = crest_size()
	# the pole's top: centred on the column, its foot CREST_SINK behind the top segment
	_crest.position = Vector2(col_x - _crest.size.x * 0.5, float(SEG_Y[0]) + CREST_SINK - _crest.size.y + _dy)
	var post_top := _crest.position.y + _crest.size.y * 0.5
	_post.position = Vector2(col_x - POST_W * 0.5, post_top)
	_post.size = Vector2(POST_W, BASE_AT.y + _dy + SEG_BORDER - post_top)
	_post.queue_redraw()
	for k in range(_rows.size()):
		var row: GiftRow = _rows[k]
		row.position = Vector2(SEG_X, float(SEG_Y[k]) + _dy)
		row.size = Vector2(TAG_AT.x + TAG.x + TAG_SHADOW, SEG)
	_base.position = BASE_AT + Vector2(0, _dy)
	_base.size = BASE
	_base.queue_redraw()


## The crest's size on the canvas: CREST_W wide at its painting's aspect, no taller than CREST_MAX_H (then narrower).
func crest_size() -> Vector2:
	if _crest == null or _crest.texture == null:
		return Vector2(CREST_W, 0)
	var ts := _crest.texture.get_size()
	var sz := Vector2(CREST_W, CREST_W * ts.y / maxf(ts.x, 1.0))
	if sz.y > CREST_MAX_H:
		sz *= CREST_MAX_H / sz.y
	return Vector2(roundf(sz.x), roundf(sz.y))


## The label's face: Bitter 600 tracked LABEL_TRACK, its spaces LABEL_SPACE wider (made once).
static var _label_font: FontVariation


static func label_font() -> Font:
	if _label_font == null:
		_label_font = FontVariation.new()
		_label_font.base_font = load(W.SERIF_PATH) if ResourceLoader.exists(W.SERIF_PATH) else ThemeDB.fallback_font
		_label_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
		_label_font.spacing_glyph = LABEL_TRACK
		_label_font.spacing_space = LABEL_SPACE
	return _label_font


## The right star's middle in the label: after the words' advance (its trailing tracking included), a tracked space,
## then the star as far in as the left one sits from the label's edge.
func label_star_r() -> Vector2:
	var f := label_font()
	var words := f.get_string_size(_label_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x
	var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x
	return Vector2(LABEL_TEXT_X + words + space + LABEL_STAR_L.x + LABEL_STAR_PAD, LABEL_STAR_L.y)


func _draw_label_stars() -> void:
	WMarks.star(_label, LABEL_STAR_L, LABEL_STAR_R, W.PAPER)
	WMarks.star(_label, label_star_r(), LABEL_STAR_R, W.PAPER)


func _make_row(b: Dictionary, k: int) -> GiftRow:
	var row := GiftRow.new()
	row.name = "Gift_%s" % str(b.get("id", k))
	row.boon = b
	row.screen = self
	row.feathers = BOONS.roll_third(b)
	# the glow behind the segment while it is held: outside the group (a see-through glow drawn into the group's buffer
	# came out darker), in a Node2D so the row (a container) leaves its size alone; it moves with the segment
	var glow_holder := Node2D.new()
	glow_holder.name = "GlowHolder"
	row.add_child(glow_holder)
	row.glow_holder = glow_holder
	var group := CanvasGroup.new()
	group.name = "Group"
	group.fit_margin = 12.0
	row.add_child(group)
	row.group = group
	var body := Control.new()
	body.name = "Body"
	body.size = Vector2(TAG_AT.x + TAG.x + TAG_SHADOW, SEG)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(body)
	row.body = body
	# the segment: the plate, the word when the spirit has no face yet
	var seg := Control.new()
	seg.name = "Segment"
	seg.size = Vector2(SEG, SEG)
	body.add_child(seg)
	row.seg = seg
	var glow := Panel.new()
	glow.name = "Glow"
	var gs := StyleBoxFlat.new()
	gs.bg_color = W.ROCK
	gs.set_corner_radius_all(SEG_RADIUS)
	gs.shadow_color = GLOW_COLOR
	gs.shadow_size = GLOW_PX
	gs.anti_aliasing = true
	glow.add_theme_stylebox_override("panel", gs)
	glow.size = Vector2(SEG, SEG)
	glow.modulate.a = 0.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_holder.add_child(glow)
	row.glow = glow
	var plate := WPlate.new()
	plate.name = "Plate"
	plate.side = SEG
	plate.size = Vector2(SEG, SEG)
	plate.fill = W.ROCK
	plate.border = SEG_BORDER
	plate.radius = SEG_RADIUS
	plate.ring = CARVE
	plate.ring_color = CARVE_COLOR
	plate.icon_frac = FACE / SEG
	plate.tex = BOONS.icon_of(b)
	seg.add_child(plate)
	row.plate = plate
	var carve := Control.new()
	carve.name = "Carve"
	carve.size = Vector2(SEG, SEG)
	carve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carve.draw.connect(func() -> void: carved_over(carve, plate))
	plate.add_child(carve)
	row.carve = carve
	if plate.tex == null:
		var wd := W.slab_text(BOONS.word(b), WORD_PX, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
		wd.name = "Word"
		wd.valign = VERTICAL_ALIGNMENT_CENTER
		wd.size = Vector2(SEG, SEG)
		# Alfa Slab 40 as the README says (Thunderbird, the longest word, is 273 px: inside the border, a pixel into the
		# carved band); a longer word one day shrinks rather than touch the border
		var room := SEG - 2.0 * (SEG_BORDER + WORD_CLEAR)
		if wd.text_width() > room:
			wd.font_size = int(floor(WORD_PX * room / wd.text_width()))
		seg.add_child(wd)
		row.word = wd
	# the tag: the kit's paper box with its hard shadow; pressed it sits on its shadow with the brass inner outline
	var tag := Panel.new()
	tag.name = "Tag"
	tag.size = TAG
	row.tag_box = W.box(W.PAPER, TAG_BORDER, TAG_SHADOW)
	var down := W.box(W.PAPER, TAG_BORDER, 0)
	down.inner = PRESS_INNER
	down.inner_color = W.BRASS
	row.tag_box_down = down
	tag.add_theme_stylebox_override("panel", row.tag_box)
	body.add_child(tag)
	row.tag = tag
	_fill_tag(row, b)
	row.seg_home = Vector2.ZERO
	row.tag_home = TAG_AT
	seg.position = row.seg_home
	tag.position = row.tag_home
	W.pass_through(row)
	row.pressed.connect(func() -> void: _pick(row))
	row.hold_changed.connect(func(on: bool) -> void: _on_hold(row, on))
	return row


## The tag's three lines, centred top to bottom inside its border: the effect (amount and stat on one baseline), the
## spirit, the gauge; and the nail on its left edge.
func _fill_tag(row: GiftRow, b: Dictionary) -> void:
	var top3 := BOONS.roll_third(b) >= 3
	var amount := W.slab_text(BOONS.amount_text(b), AMOUNT_PX, W.BRASS_DARK if top3 else W.INK)
	amount.name = "Amount"
	var stat := W.serif_text(BOONS.stat_text(b), STAT_PX, W.INK, 600, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
	stat.name = "Stat"
	var spirit := W.serif_text(BOONS.title(b), SPIRIT_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
	spirit.name = "Spirit"
	var ends := BOONS.range_texts(b)
	var gauge := WNotches.make(str(ends[0]), str(ends[1]), BOONS.roll_third(b))
	gauge.name = "Gauge"
	for c in [amount, stat, spirit, gauge]:
		row.tag.add_child(c)
	row.amount = amount
	row.stat = stat
	row.spirit = spirit
	row.gauge = gauge
	# the effect line: two faces on one baseline (CSS align-items: baseline); its box is the taller part above the
	# baseline and the taller part below it
	var a_up := _baseline_in(W.slab(), AMOUNT_PX, AMOUNT_PX)
	var a_dn := float(AMOUNT_PX) - a_up
	var s_lh := W.normal_height(W.serif(600), STAT_PX)
	var s_up := _baseline_in(W.serif(600), STAT_PX, s_lh)
	var s_dn := s_lh - s_up
	var up := maxf(a_up, s_up)
	var effect_h := up + maxf(a_dn, s_dn)
	var spirit_h := W.normal_height(W.serif(400, true), SPIRIT_PX)
	var gauge_h := gauge.line_h()
	var block := effect_h + LINE_GAP + spirit_h + LINE_GAP + gauge_h
	var inner_h := TAG.y - 2.0 * TAG_BORDER
	var y := TAG_BORDER + (inner_h - block) * 0.5
	var x := TAG_BORDER + TAG_PAD_L
	amount.position = Vector2(x, y + up - a_up)
	amount.size = amount.get_combined_minimum_size()
	stat.position = Vector2(x + amount.text_width() + AMOUNT_GAP, y + up - s_up)
	stat.size = stat.get_combined_minimum_size()
	y += effect_h + LINE_GAP
	spirit.position = Vector2(x, y)
	spirit.size = spirit.get_combined_minimum_size()
	y += spirit_h + LINE_GAP
	gauge.position = Vector2(x, y)
	gauge.size = gauge.get_combined_minimum_size()
	var nail := WNail.at_center(Vector2(NAIL_DX, TAG.y * 0.5))
	nail.name = "Nail"
	row.tag.add_child(nail)
	row.nail = nail


## Where the baseline sits from the top of a line box `lh` tall of `f` at `px` (CSS half-leading round the face's own
## ascent and descent).
static func _baseline_in(f: Font, px: int, lh: float) -> float:
	return (lh - (f.get_ascent(px) + f.get_descent(px))) * 0.5 + f.get_ascent(px)


# ---------------------------------------------------------------- motion

func _tw() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t


func _kill_tweens() -> void:
	for t in _tweens:
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
	_tweens.clear()


## Open (460 ms): the ring's flash (the world's, first T_FLASH), the dim in, the crest dropping from above, the segments
## rising one after another, each tag sliding in after its segment, the base last. A run sim shows it all at once.
func _open_motion() -> void:
	var sim := _instant()
	dim.color = Color(dim_color.r, dim_color.g, dim_color.b, dim_color.a if sim else 0.0)
	for k in range(_rows.size()):
		var row: GiftRow = _rows[k]
		row.arrived = sim
	if sim:
		for row: GiftRow in _rows:
			row.arrived = true
		return
	var td := _tw()
	td.tween_interval(T_FLASH)
	td.tween_property(dim, "color:a", dim_color.a, T_DIM_IN)
	_label.modulate.a = 0.0
	var tl := _tw()
	tl.tween_interval(T_FLASH)
	tl.tween_property(_label, "modulate:a", 1.0, T_DIM_IN)
	var crest_y := _crest.position.y
	_crest.position.y = CREST_FROM_Y
	_crest.modulate.a = 0.0
	var tc := _tw()
	tc.tween_interval(T_FLASH)
	tc.tween_property(_crest, "modulate:a", 1.0, 0.0)
	tc.tween_property(_crest, "position:y", crest_y, T_CREST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for k in range(_rows.size()):
		var row: GiftRow = _rows[k]
		var at := T_FLASH + SEG_STAGGER * k
		row.arrive_ms = Time.get_ticks_msec() + int(ceilf((at + TAG_AFTER + T_TAG) * 1000.0))
		row.seg.position = row.seg_home + Vector2(0, SEG_RISE)
		row.seg.modulate.a = 0.0
		var ts := _tw()
		ts.tween_interval(at)
		ts.set_parallel(true)
		ts.chain().tween_property(row.seg, "position", row.seg_home, T_SEG).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ts.tween_property(row.seg, "modulate:a", 1.0, T_SEG * 0.6)
		row.tag.position = row.tag_home + Vector2(TAG_SLIDE, 0)
		row.tag.modulate.a = 0.0
		var tt := _tw()
		tt.tween_interval(at + TAG_AFTER)
		tt.set_parallel(true)
		tt.chain().tween_property(row.tag, "position", row.tag_home, T_TAG).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tt.tween_property(row.tag, "modulate:a", 1.0, T_TAG * 0.6)
		tt.chain().tween_callback(func() -> void: row.arrived = true)
	_post.modulate.a = 0.0
	var tp := _tw()
	tp.tween_interval(T_FLASH)
	tp.tween_property(_post, "modulate:a", 1.0, T_DIM_IN)
	_base.modulate.a = 0.0
	var tb := _tw()
	tb.tween_interval(T_OPEN - T_BASE)
	tb.tween_property(_base, "modulate:a", 1.0, T_BASE)


## No motion in a run sim (Run.sim_mode: a headless run played fast).
func _instant() -> bool:
	var run := W.node("Run")
	return run != null and bool(run.get("sim_mode"))


## A row held: the other two fade to 60 % (60 ms), back when it is let go (90 ms).
func _on_hold(row: GiftRow, on: bool) -> void:
	if on:
		_held_row = row
	elif _held_row == row:
		_held_row = null
	if _done:
		return
	for r: GiftRow in _rows:
		if r == row:
			continue
		var t := _tw()
		t.tween_property(r.group, "self_modulate:a", OTHERS_ALPHA if on else 1.0, T_PRESS if on else T_CANCEL)


func _pick(row: GiftRow) -> void:
	if _done or not visible or row == null:
		return
	RunReplay.note("totem", {"id": str(row.boon.get("id", "")), "i": _rows.find(row), "value": row.boon.get("value", 0.0)})
	_done = true
	W.sfx_first(["ui_totem", "ui_card_pick"])
	var boon: Dictionary = row.boon
	closing.emit(boon)
	if _instant():
		_finish(boon)
		_hide()
		return
	row.show_held(true)
	_close_motion(row)


## Close (420 ms): the chosen face lifts off its plate and flies to its toast's icon (shrinking 240 -> 72), the other two
## gifts drop out, the chosen tag and plate, the crest, the label and the base fade, the dim lifts last. The run goes on at
## T_CONTROL; the screen hides at T_CLOSE.
func _close_motion(row: GiftRow) -> void:
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = row.plate.tex
	if tex:
		var from := _face_rect(row)
		_flyer = TextureRect.new()
		_flyer.name = "Face"
		_flyer.texture = tex
		_flyer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_flyer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flyer.position = from.position
		_flyer.size = from.size
		add_child(_flyer)
		row.plate.tex = null
		row.plate.queue_redraw()
		row.carve.queue_redraw()
		var to_c := face_target(row.boon)
		var to := Rect2(to_c - Vector2(FLY_TO, FLY_TO) * 0.5, Vector2(FLY_TO, FLY_TO))
		var tf := _tw().set_parallel(true)
		tf.tween_property(_flyer, "position", to.position, T_FLY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tf.tween_property(_flyer, "size", to.size, T_FLY).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for r: GiftRow in _rows:
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := _tw().set_parallel(true)
		if r == row:
			t.tween_property(r.group, "self_modulate:a", 0.0, T_FADE)
			t.tween_property(r.glow, "modulate:a", 0.0, T_FADE)
		else:
			t.tween_property(r, "position:y", r.position.y + DROP_PX, T_DROP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(r.group, "self_modulate:a", 0.0, T_DROP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for c: Control in [_crest, _base, _label, _post]:
		var tc := _tw()
		tc.tween_property(c, "modulate:a", 0.0, T_FADE)
	var td := _tw()
	td.tween_interval(T_CLOSE - T_DIM_OUT)
	td.tween_property(dim, "color:a", 0.0, T_DIM_OUT)
	var boon: Dictionary = row.boon
	var tq := _tw()
	tq.tween_interval(T_CONTROL)
	tq.tween_callback(func() -> void:
		# the run goes on: the HUD comes back under the last of the motion
		if is_in_group("wanted_modal"):
			remove_from_group("wanted_modal")
		_finish(boon))
	tq.tween_interval(T_CLOSE - T_CONTROL)
	tq.tween_callback(_hide)


## Where the chosen face's icon lands: its toast's icon on the HUD (HUD.toast_icon_spot), else the README's slot.
func face_target(boon: Dictionary) -> Vector2:
	var g := get_tree().current_scene if is_inside_tree() else null
	var hud = g.get("hud") if g else null
	if hud != null and is_instance_valid(hud) and hud.has_method("toast_icon_spot"):
		return hud.toast_icon_spot(BOONS.toast_text(boon))
	return TOAST_SLOT + Vector2(0, _dy)


## The face as the plate draws it, on the canvas: the texture fitted into FACE px in the plate's middle.
func _face_rect(row: GiftRow) -> Rect2:
	var tex: Texture2D = row.plate.tex
	var inner := SEG * row.plate.icon_frac
	var ts := tex.get_size() if tex else Vector2(inner, inner)
	var k := inner / maxf(maxf(ts.x, ts.y), 1.0)
	var sz := ts * k
	var at := row.plate.get_global_transform() * ((Vector2(SEG, SEG) - sz) * 0.5)
	return Rect2(get_global_transform().affine_inverse() * at, sz)


## The gifts as offered (tests, tools).
func offer() -> Array:
	return _offer


## The gift rows in order (tests, tools; the bot reads each one's `boon` and `feathers`).
func planks() -> Array:
	return _rows


func rows() -> Array:
	return _rows


func _finish(boon: Dictionary) -> void:
	if not visible:
		return
	closed.emit(boon)


func _hide() -> void:
	_kill_tweens()
	visible = false
	if _flyer:
		_flyer.queue_free()
		_flyer = null
	if not is_in_group("wanted_modal"):
		add_to_group("wanted_modal")
	modulate.a = 1.0
	dim.color = dim_color
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
