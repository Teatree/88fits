## The slab button: Alfa Slab One on a square box with an ink border and a hard shadow. Variants: primary (brass,
## darkens to brass dark while held), secondary (paper), danger (rock with paper text), locked (aged at 45 %, still
## emits `pressed` so the screen can say why). The label is parts: text runs in their own colours and coins
## ("REROLL ×1", "SELL ○ +4", "RANK 2 ○ 252").
class_name WButton
extends WTap

const PRIMARY := "primary"
const SECONDARY := "secondary"
const DANGER := "danger"

var variant := SECONDARY
var font_size := 34
var line_h := 0.0   # 0 = the font's own height; the mock's `line-height:1` buttons pass px
var _row: HBoxContainer


## parts: Array of items, each a String (ink), [text, colour], [text, colour, px] or {"coin": px, "fill": colour}.
static func make(parts: Array, px: int = 34, p_variant: String = SECONDARY, border: int = 5, shadow: int = 8,
		pad_v: float = 26.0, pad_h: float = 22.0, p_line_h: float = 0.0) -> WButton:
	var b := WButton.new()
	b.variant = p_variant
	b.font_size = px
	b.line_h = p_line_h
	var fill := W.PAPER
	match p_variant:
		PRIMARY:
			fill = W.BRASS
		DANGER:
			fill = W.ROCK
	var hb := W.box(fill, border, shadow).pad(pad_h + border, pad_v + border, pad_h + border, pad_v + border)
	b.box = hb
	b.box_down = hb.pressed(W.BRASS_DARK if p_variant == PRIMARY else fill)
	b._row = HBoxContainer.new()
	b._row.alignment = BoxContainer.ALIGNMENT_CENTER
	b._row.add_theme_constant_override("separation", int(px * 0.3))
	b._row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(b._row)
	b.set_parts(parts)
	return b


func set_parts(parts: Array) -> void:
	for c in _row.get_children():
		c.queue_free()
	var ink := W.PAPER if variant == DANGER else W.INK
	var runs: Array = []
	var flush := func():
		if runs.is_empty():
			return
		var t := W.text("", W.slab(), font_size, ink, HORIZONTAL_ALIGNMENT_CENTER, line_h)
		t.runs = runs.duplicate()
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(t)
		runs.clear()
	for p in parts:
		if p is Dictionary and p.has("coin"):
			flush.call()
			_row.add_child(WCoin.make(float(p["coin"]), p.get("fill", W.BRASS), float(p.get("border", 3.0))))
		elif p is Array:
			# [text, colour] or [text, colour, px] (a smaller number beside the word: "RANK 2 ○ 252")
			if p.size() > 2:
				runs.append([str(p[0]), p[1], null, int(p[2])])
			else:
				runs.append([str(p[0]), p[1] if p.size() > 1 else null])
		else:
			runs.append([str(p), null])
	flush.call()


## The label as plain text (tests and tools read it).
func label_text() -> String:
	var s := ""
	for c in _row.get_children():
		if c is WText:
			var t := c as WText
			if t.runs.is_empty():
				s += t.text
			else:
				for r in t.runs:
					s += str(r[0])
	return s
