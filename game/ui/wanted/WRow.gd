## A list row: a 96 px plate, the name (slab 36), one effect line (Bitter 24, ink-soft), the level as stars (or path
## rivets when open), and a chevron. Open, it wears a 4 px brass band inside its border and shows what `open_body`
## holds under the head (the pause screen's stat grid and path chips). A 4 px ink border, no shadow.
class_name WRow
extends WTap

var head: HBoxContainer
var body: VBoxContainer
var chevron: WText
var is_open := false


static func make(def: ContentDef, effect: String, marks: Control, p_open: bool = false, locked_look: bool = false) -> WRow:
	var r := WRow.new()
	r.is_open = p_open
	var b := W.box(W.PAPER, 4, 0).pad(18 + 4, 14 + 4, 18 + 4, (18 if p_open else 14) + 4)
	if p_open:
		b.inner = 4
		b.inner_color = W.BRASS
	r.box = b
	r.box_down = b
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	r.head = HBoxContainer.new()
	r.head.add_theme_constant_override("separation", 20)
	r.head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(r.head)
	var plate := WPlate.new().for_def(def, 104.0, locked_look)
	plate.icon_frac = 0.68
	r.head.add_child(plate)
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", 0)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(W.slab_text(def.display_name, 36, W.INK_SOFT if locked_look else W.INK, HORIZONTAL_ALIGNMENT_LEFT, 36.0))
	var e := W.serif_text(effect, 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	e.max_lines = 2
	tc.add_child(e)
	r.head.add_child(tc)
	if marks:
		marks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.head.add_child(marks)
	# the chevron sits in a plain holder: a container resets its children's rotation, and open it points down
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(24, 40)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.chevron = W.slab_text("›", 40, W.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	r.chevron.size = Vector2(24, 40)
	if p_open:
		r.chevron.pivot_offset = Vector2(12, 20)
		r.chevron.rotation = PI * 0.5
	holder.add_child(r.chevron)
	r.head.add_child(holder)
	r.body = VBoxContainer.new()
	r.body.add_theme_constant_override("separation", 14)
	r.body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.body.visible = p_open
	col.add_child(r.body)
	return r


## The stat grid of an open row: an aged panel, four columns of a small label and a slab value.
static func stat_grid(cells: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.AGED, 4, 0).pad(22, 18, 22, 18))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(g)
	for c in cells:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(W.serif_text(str(c[0]), 20, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
		v.add_child(W.slab_text(str(c[1]), 32, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
		g.add_child(v)
	return p


## "Paths [Watchtower] [Bunker] · one more and it can evolve": plum chips with paper slab names.
static func path_chips(names: Array, note: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(W.serif_text("Paths", 22, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	for n in names:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", W.box(W.PLUM, 0, 0).pad(14, 4, 14, 4))
		chip.add_child(W.slab_text(str(n), 20, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(chip)
	if note != "":
		var t := W.serif_text("· " + note, 22, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
	return h
