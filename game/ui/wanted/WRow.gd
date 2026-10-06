## A list row: a 104 px plate (pass 48: in the colour of the level held, a weapon's mutation dots along its top edge and
## its glow when it is ready to evolve), the name (slab 36), one effect line (Bitter 24, ink-soft), the level as stars,
## and a chevron. Open, it wears a 4 px brass band inside its border and shows what `open_body` holds under the head
## (the pause screen's stat grid and mutation chips). A 4 px ink border, no shadow. Pass 54: `name_suffix` follows the
## name in grey ("(used)": Phoenix Feather once it has stood the hero up), the name grey with it.
class_name WRow
extends WTap

var head: HBoxContainer
var body: VBoxContainer
var chevron: WText
var is_open := false
## The name and the words after it (null without a suffix).
var name_text: WText
var suffix: WText


static func make(def: ContentDef, effect: String, marks: Control, p_open: bool = false, locked_look: bool = false,
		level: int = 0, dots: Vector2i = Vector2i.ZERO, dots_ready: bool = false, name_suffix: String = "") -> WRow:
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
	var plate := WPlate.new().for_def(def, 104.0, locked_look, level)
	plate.icon_frac = 0.68
	if dots.y > 0:
		plate.set_dots(dots, dots_ready)
	plate.name = "Plate"
	r.head.add_child(plate)
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", 0)
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_col := W.INK_SOFT if locked_look else W.INK
	if name_suffix != "":
		name_col = W.COMMON
	r.name_text = W.slab_text(def.display_name, 36, name_col, HORIZONTAL_ALIGNMENT_LEFT, 36.0)
	if name_suffix == "":
		tc.add_child(r.name_text)
	else:
		# the name, then the suffix in grey italic on the same line
		var nl := HBoxContainer.new()
		nl.add_theme_constant_override("separation", 12)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.add_child(r.name_text)
		r.suffix = W.serif_text(name_suffix, 28, W.COMMON, 600, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
		r.suffix.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nl.add_child(r.suffix)
		tc.add_child(nl)
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


## "Mutations [Watchtower] [Bunker] · one more and it can evolve": plum chips with paper slab names.
static func path_chips(names: Array, note: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(W.serif_text("Mutations", 22, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
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
