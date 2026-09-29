## The item card: paper, a 5 px ink border and a hard shadow, a brass rivet on the top edge, the plate on the left,
## the wax seal top-right, and a column of: the kind in one word (tracked, in the kind's colour), the name, the level
## stars and one effect line. Variants: an evolution wears an ember band inside the border; a card the player cannot
## afford is aged at 60 % with its price button in paper ("· 8 short"). Held, it sits on its shadow with a brass band.
class_name WCard
extends WTap

var def: ContentDef
var plate: WPlate
var seal: WSeal
var rivet := true
var rivet_px := 32.0
var price_button: WButton
var effect_text: WText
## The seal's corner offset from the card's top-right (20, 20 on a card; 0, -10 in the Stranger's panel).
var seal_at := Vector2(20, 20)
var _col: VBoxContainer
var _shadow := 10


## o: word, word_color, name, name_size (60), stars [total, held, upto] or [], effect, rarity ("" = no seal),
## plate_px (170), evolution (bool), price (-1 = none), short (gold missing), shadow (10), pad [t, r, b, l], gap (28),
## col_gap (8), effect_size (30), text_right (room for the seal, 110), seal_px (96), locked (bool).
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
	c.plate = WPlate.new().for_def(p_def, float(o.get("plate_px", 170.0)))
	c.plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if o.has("plate_fill"):
		c.plate.fill = o["plate_fill"]
	c.plate.icon_frac = float(o.get("icon_frac", 0.76))
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
	if word != "":
		c._col.add_child(W.label(word, int(o.get("word_size", 20)), o.get("word_color", W.INK_SOFT)))
	var name_px := int(o.get("name_size", 60))
	c._col.add_child(W.slab_text(str(o.get("name", p_def.display_name if p_def else "")), name_px, W.INK))
	var st: Array = o.get("stars", [])
	if st.size() >= 2:
		c._col.add_child(WMarks.new().setup("stars", int(st[0]), int(st[1]), int(st[2]) if st.size() > 2 else -1, float(o.get("star_px", 28.0))))
	var eff := str(o.get("effect", ""))
	if eff != "":
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
