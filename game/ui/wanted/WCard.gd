## The item card: paper, a 5 px ink border and a hard shadow, a brass rivet on the top edge, the plate on the left,
## the wax seal top-right (no item card has worn one since pass 43; a passive item's rarity is its plate's colour since
## pass 47), and a column of: the kind in one word (tracked, in the kind's colour), the name, the level
## stars and one effect line. Variants: an evolution wears an ember band inside the border; a card the player cannot
## afford is aged at 60 % with its price button in paper ("· 8 short"). Held, it sits on its shadow with a brass band.
## Pass 58 (Garry: "some kind of an indicator on items when they are upgraded rather than a new item"): the word's line
## carries a tag at its right end (UPGRADE in brass, NEW in sage, EVOLUTION in ember: WItem.tag), an upgrade's new stars
## pulse (WMarks.pulse), and an upgrade lists what it changes, a row a stat ("Damage . . . 12 → 15", the new number
## bold), in place of its "Next:" line.
class_name WCard
extends WTap

var def: ContentDef
var plate: WPlate
var seal: WSeal
var rivet := true
var rivet_px := 32.0
var price_button: WButton
var effect_text: WText
## The tag beside the word (pass 58), null when the card has none (a mutation, a perk).
var tag_node: PanelContainer
## The stars (null when the card shows none).
var marks: WMarks
## An upgrade's change rows (pass 58), null when the card shows its effect line instead.
var changes_box: VBoxContainer
## The seal's corner offset from the card's top-right (20, 20 on a card; 0, -10 in the Stranger's panel).
var seal_at := Vector2(20, 20)
var _col: VBoxContainer
var _shadow := 10
## The stars' size on a card (pass 48, Garry: bigger stars everywhere; 28 before).
const STAR_PX := 40.0
## The tag's type size and a change row's (pass 58).
const TAG_PX := 26
const CHANGE_PX := 30


## o: word, word_color, name, name_size (60), stars [total, held, upto] or [], star_px (40; 28 before pass 48), effect,
## rarity ("" = no seal), plate_px (170), level (the plate's colour for a weapon or a line, pass 48; 0 = common), dots
## (Vector2i held/total mutation dots on a weapon's plate, pass 48) and dots_ready (the glow), evolution (bool), price
## (-1 = none), short (gold missing), shadow (10), pad [t, r, b, l], gap (28), col_gap (8), effect_size (30), text_right
## (room for the seal, 110), seal_px (96), locked (bool), kind_mark (pass 54: the plate's corner glyph, "weapon" or "line";
## by default the def's own, W.kind_mark_of; "" for none); pass 58: tag ("UPGRADE", "NEW", "EVOLUTION" or ""), tag_size
## (26), changes (WItem.changes rows: shown in place of the effect line when there are any), change_size (30), pulse
## (true: the "this pick" stars pulse).
static func make(p_def: ContentDef, o: Dictionary) -> WCard:
	var c := WCard.new()
	c.def = p_def
	c._shadow = int(o.get("shadow", 10))
	var pad: Array = o.get("pad", [36, 32, 30, 32])
	var hb := W.box(W.PAPER, 5, c._shadow).pad(float(pad[3]) + 5.0, float(pad[0]) + 5.0, float(pad[1]) + 5.0, float(pad[2]) + 5.0)
	if bool(o.get("bare", false)):
		# the item's content without a frame of its own (the Stranger's deal panel carries it)
		c._shadow = 0
		hb = W.box(Color(0, 0, 0, 0), 0, 0).pad(0, 0, 0, 0)
	if bool(o.get("evolution", false)):
		hb.inner = 6
		hb.inner_color = W.EMBER
	var down := hb.pressed()
	down.inner = 6
	down.inner_color = W.BRASS
	c.box_down = down
	c.box = hb
	c.locked_alpha = 0.6
	c.rivet = bool(o.get("rivet", true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(o.get("gap", 28)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(row)
	c.plate = WPlate.new().for_def(p_def, float(o.get("plate_px", 170.0)), false, int(o.get("level", 0)))
	c.plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if o.has("plate_fill"):
		c.plate.fill = o["plate_fill"]
	var dots: Vector2i = o.get("dots", Vector2i.ZERO)
	if dots.y > 0:
		c.plate.set_dots(dots, bool(o.get("dots_ready", false)))
	c.plate.icon_frac = float(o.get("icon_frac", 0.76))
	# the kind's corner glyph (pass 54): a revolver on a weapon and its evolution (pass 56), a scroll on a line and its
	# evolution, none on a passive item, a perk or a mutation
	c.plate.set_kind_mark(str(o.get("kind_mark", W.kind_mark_of(p_def))))
	row.add_child(c.plate)
	c._col = VBoxContainer.new()
	c._col.add_theme_constant_override("separation", int(o.get("col_gap", 8)))
	c._col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c._col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c._col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rarity := str(o.get("rarity", ""))
	var right := MarginContainer.new()
	right.add_theme_constant_override("margin_right", int(o.get("text_right", 110 if rarity != "" else 0)))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(c._col)
	row.add_child(right)
	var word := str(o.get("word", ""))
	var tag := str(o.get("tag", ""))
	if word != "" or tag != "":
		# the word on the left, the tag at the line's right end (pass 58), so three cards' tags read down one column
		var wl := HBoxContainer.new()
		wl.name = "WordLine"
		wl.add_theme_constant_override("separation", 14)
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wlab := W.label(word, int(o.get("word_size", 20)), o.get("word_color", W.INK_SOFT))
		wlab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wlab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wl.add_child(wlab)
		if tag != "":
			c.tag_node = tag_pill(tag, int(o.get("tag_size", TAG_PX)))
			wl.add_child(c.tag_node)
		c._col.add_child(wl)
	var name_px := int(o.get("name_size", 60))
	c._col.add_child(W.slab_text(str(o.get("name", p_def.display_name if p_def else "")), name_px, W.INK))
	var st: Array = o.get("stars", [])
	if st.size() >= 2:
		c.marks = WMarks.new().setup("stars", int(st[0]), int(st[1]), int(st[2]) if st.size() > 2 else -1, float(o.get("star_px", STAR_PX)))
		c.marks.pulse = bool(o.get("pulse", true)) and c.marks.has_next()
		c._col.add_child(c.marks)
	var ch: Array = o.get("changes", [])
	var eff := str(o.get("effect", ""))
	if not ch.is_empty():
		c.changes_box = change_rows(ch, int(o.get("change_size", CHANGE_PX)))
		c._col.add_child(c.changes_box)
	elif eff != "":
		c.effect_text = W.serif_text(eff, int(o.get("effect_size", 30)), W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
		c.effect_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c._col.add_child(c.effect_text)
	var price := int(o.get("price", -1))
	if price >= 0:
		var short := int(o.get("short", 0))
		var pb: WButton
		if short > 0:
			pb = WButton.make([{"coin": 40, "fill": W.BRASS}, [W.num(price), W.INK]], 36, WButton.SECONDARY, 4, 0, 8.0, 26.0)
			var sh := W.serif_text("· %d short" % short, 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 30.0)
			sh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pb._row.add_child(sh)
		else:
			pb = WButton.make([{"coin": 40, "fill": W.PAPER}, [W.num(price), W.INK]], 36, WButton.PRIMARY, 4, 5, 8.0, 26.0)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb.size_flags_horizontal = Control.SIZE_SHRINK_END
		c.price_button = pb
		c._col.add_child(pb)
	if rarity != "":
		c.seal = WSeal.new().for_rarity(rarity, float(o.get("seal_px", 96.0)))
		c.seal_at = o.get("seal_at", Vector2(20, 20))
		c.add_child(c.seal)
	c.locked = bool(o.get("locked", false))
	return c


func _held_offset() -> Vector2:
	return Vector2(_shadow, _shadow) if (_held_look and not locked) else Vector2.ZERO


func _draw() -> void:
	if rivet:
		var rc := Vector2(size.x * 0.5, -18.0 + rivet_px * 0.5) + _held_offset()
		draw_circle(rc, rivet_px * 0.5, W.INK, true, -1.0, true)
		draw_circle(rc, rivet_px * 0.5 - 4.0, W.BRASS, true, -1.0, true)


func _notification(what: int) -> void:
	super._notification(what)
	# the PanelContainer fits every child to the content; the seal keeps its own size in the top-right corner
	if what == NOTIFICATION_SORT_CHILDREN and seal:
		seal.size = Vector2(seal.side, seal.side)
		seal.position = Vector2(size.x - seal_at.x - seal.side, seal_at.y) + _held_offset()


func _restyle() -> void:
	super._restyle()
	queue_sort()
	queue_redraw()


## The tag beside a card's word (pass 58): UPGRADE on brass with a little ink chevron pointing up, NEW on sage,
## EVOLUTION on ember (WItem.tag_color), in ink Alfa Slab inside a 3 px ink border; the chest's landed item wears it too.
static func tag_pill(t: String, px: int = TAG_PX) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Tag"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(WItem.tag_color(t), 3, 0).pad(12, 4, 13, 4))
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	if t == "UPGRADE":
		var chev := Control.new()
		chev.name = "Chevron"
		chev.custom_minimum_size = Vector2(roundf(px * 0.7), roundf(px * 1.1))
		chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chev.draw.connect(func():
			var s := chev.size
			var w := s.x
			var h := s.x * 0.62
			var y0 := (s.y - h) * 0.5
			chev.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, y0), Vector2(w, y0 + h), Vector2(0, y0 + h)]), W.INK))
		row.add_child(chev)
	var l := W.text(t, W.slab(W.em(px, 0.06)), px, W.INK, HORIZONTAL_ALIGNMENT_LEFT, roundf(px * 1.1))
	l.name = "Word"
	row.add_child(l)
	return p


## An upgrade's change rows (pass 58), one ChangeRow per {name, before, after, worse} of WItem.changes, `px` type.
static func change_rows(rows: Array, px: int = CHANGE_PX) -> VBoxContainer:
	var rb := VBoxContainer.new()
	rb.name = "Changes"
	rb.add_theme_constant_override("separation", 2)
	rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in rows:
		if r is Dictionary:
			rb.add_child(ChangeRow.new().setup(r, px))
	return rb


## One row of what an upgrade changes (pass 58): the stat's name in soft ink on the left, a dotted leader, and
## "before → after" on the right, the old number plain, the arrow brass, the new number in Bitter 800 (dark red when it
## is a loss: a trade's growing price); a name too long for the row wraps, the numbers keeping to its last line.
class ChangeRow extends Container:
	var stat := ""
	var name_text: WText
	var values: WText
	var leader_color := Color(W.INK_SOFT, 0.5)
	var _px := 30
	var _lead_from := 0.0
	var _lead_to := 0.0
	var _lead_y := 0.0
	## Space between the name, the leader and the numbers; the shortest leader and the narrowest a name may be.
	const GAP := 12.0
	const MIN_LEAD := 22.0
	const NAME_MIN := 150.0
	const DOT_STEP := 11.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(row: Dictionary, px: int) -> ChangeRow:
		stat = str(row.get("stat", ""))
		name = "Change_" + stat
		_px = px
		var lh := roundf(px * 1.24)
		name_text = W.serif_text(str(row.get("name", "")), px, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, lh, true, false)
		name_text.name = "Name"
		add_child(name_text)
		values = W.text("", W.serif(400), px, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, lh)
		values.name = "Values"
		var after_col: Color = W.BAD_DARK if bool(row.get("worse", false)) else W.INK
		values.runs = [[str(row.get("before", "")), W.INK_SOFT, W.serif(400), px], [" → ", W.BRASS_DARK, W.serif(700), px],
			[str(row.get("after", "")), after_col, W.serif(W.BOLD_WEIGHT), px]]
		add_child(values)
		return self

	## The name's width on one line.
	func _name_width() -> float:
		return W.serif(400).get_string_size(name_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _px).x

	## How far the name's last line reaches: all of `nw` on one line; wrapped, its last line's width, shaped the way the
	## name wraps it (words broken where they fit in `nw`).
	func _last_line_width(nw: float, wrapped: bool) -> float:
		if not wrapped:
			return nw
		var para := TextParagraph.new()
		para.add_string(name_text.text, W.serif(400), _px)
		para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		para.width = nw
		var n := para.get_line_count()
		return para.get_line_width(n - 1) if n > 0 else nw

	func _get_minimum_size() -> Vector2:
		if values == null:
			return Vector2.ZERO
		var vs := values.get_combined_minimum_size()
		var nh := name_text.get_combined_minimum_size().y
		return Vector2(NAME_MIN + GAP * 2.0 + MIN_LEAD + vs.x, maxf(nh, vs.y))

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN or values == null:
			return
		var vs := values.get_combined_minimum_size()
		var room := maxf(size.x - vs.x - GAP * 2.0 - MIN_LEAD, NAME_MIN)
		var nw := minf(ceilf(_name_width()) + 1.0, room)
		var nh := name_text.get_combined_minimum_size().y
		fit_child_in_rect(name_text, Rect2(0.0, 0.0, nw, nh))
		var vy := maxf(nh - vs.y, 0.0)
		fit_child_in_rect(values, Rect2(size.x - vs.x, vy, vs.x, vs.y))
		# the leader runs from the end of the name's last line to the numbers, on the numbers' baseline
		_lead_from = minf(_last_line_width(nw, nh > vs.y + 1.0), nw) + GAP
		_lead_to = size.x - vs.x - GAP
		_lead_y = vy + vs.y * 0.66
		queue_redraw()

	func _draw() -> void:
		if _lead_to - _lead_from < DOT_STEP:
			return
		var x := _lead_from + fmod(_lead_to - _lead_from, DOT_STEP) * 0.5
		while x <= _lead_to:
			draw_circle(Vector2(x, _lead_y), 2.0, leader_color, true, -1.0, true)
			x += DOT_STEP
