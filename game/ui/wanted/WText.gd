## Text laid out the way the mock's CSS lays it out: one face at one size, an exact line height (the glyphs centred in
## each line box, as CSS half-leading does), wrapping to the width, and the kit's hard ink shadow and stroke. `runs`
## lets one line carry two colours ("REROLL ×1", "Weapons 7/12"): an array of [text, colour] (colour null = `color`).
## Pass 54 (Garry: bold numbers in every item description): with `bold_numbers` and a `bold_font`, every number in the
## text, with its sign and its unit ("+15%", "1.5 s", "×2", "3rd"), is set in the bold face (number_spans), one
## paragraph of several spans that wraps and aligns as one; the runs path is left as it is.
class_name WText
extends Control

var text := "":
	set(v):
		if v != text:
			text = v
			_dirty = true
			update_minimum_size()
			queue_redraw()
var runs: Array = []:
	set(v):
		runs = v
		_dirty = true
		update_minimum_size()
		queue_redraw()
var font: Font:
	set(v):
		font = v
		_dirty = true
		update_minimum_size()
		queue_redraw()
var font_size := 30:
	set(v):
		font_size = v
		_dirty = true
		update_minimum_size()
		queue_redraw()
var color := W.INK:
	set(v):
		color = v
		queue_redraw()
## CSS line height in px; 0 = the font's own height.
var line_height := 0.0
var align := HORIZONTAL_ALIGNMENT_LEFT
var valign := VERTICAL_ALIGNMENT_TOP
var wrap := false
var max_lines := 0
## Hard shadow offset (down-right) and the stroke drawn round every glyph (both in px).
var shadow := 0
var shadow_color := W.INK
var stroke := 0
var stroke_color := W.INK
## A line drawn through the text (the struck "312" on the stage-clear card).
var strike := false
var underline := false
## The numbers in the bold face (pass 54): W.serif_text turns it on for Bitter body text with Bitter 800 as `bold_font`.
var bold_numbers := false:
	set(v):
		if v != bold_numbers:
			bold_numbers = v
			_dirty = true
			update_minimum_size()
			queue_redraw()
var bold_font: Font:
	set(v):
		bold_font = v
		_dirty = true
		update_minimum_size()
		queue_redraw()

## A number with its sign and its unit: "+15%", "−20%", "×2", "1.5 s", "4 m", "90°", "3rd", "1,200"; not a digit
## glued to a word ("SK2", nor the tail of "v0.39"), and a unit only when no letter follows it ("3 seconds" bolds the 3
## alone).
const NUMBER_PATTERN := r"(?<![A-Za-z\d.,])[+\-−×]?\d+(?:[.,]\d+)*(?:\s?(?:%|°|m/s|/s|s|m|x)(?![A-Za-z])|(?:st|nd|rd|th)(?![A-Za-z]))?"
static var _num_re: RegEx

var _para: TextParagraph
var _lines: Array = []   # for runs: [[TextLine, colour], ...]
var _dirty := true
var _shaped_w := -2.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func():
		if wrap and absf(size.x - _shaped_w) > 0.5:
			_dirty = true
			update_minimum_size()
			queue_redraw())


func _lh() -> float:
	return line_height if line_height > 0.0 else W.normal_height(_f(), font_size)


func _f() -> Font:
	return font if font else W.slab()


func _shape() -> void:
	if not _dirty:
		return
	_dirty = false
	_shaped_w = size.x
	_lines.clear()
	if not runs.is_empty():
		for r in runs:
			var tl := TextLine.new()
			tl.add_string(str(r[0]), r[2] if r.size() > 2 and r[2] else _f(), int(r[3]) if r.size() > 3 else font_size)
			_lines.append([tl, r[1] if r.size() > 1 and r[1] != null else null])
		_para = null
		return
	_para = TextParagraph.new()
	if bold_numbers and bold_font and text != "":
		# the numbers in the bold face, the words between them in the text's own (pass 54)
		for sp in number_spans(text):
			_para.add_string(str(sp[0]), bold_font if sp[1] else _f(), font_size)
	else:
		_para.add_string(text, _f(), font_size)
	_para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	_para.width = size.x if wrap and size.x > 1.0 else -1.0
	_para.alignment = align
	if max_lines > 0:
		_para.max_lines_visible = max_lines


## `t` cut into [text, is_number] spans in order (pass 54): the numbers NUMBER_PATTERN finds and the words between them;
## the spans joined give `t` back.
static func number_spans(t: String) -> Array:
	if _num_re == null:
		_num_re = RegEx.create_from_string(NUMBER_PATTERN)
	var out: Array = []
	var at := 0
	for m in _num_re.search_all(t):
		if m.get_start() > at:
			out.append([t.substr(at, m.get_start() - at), false])
		out.append([m.get_string(), true])
		at = m.get_end()
	if at < t.length():
		out.append([t.substr(at), false])
	return out


## The numbers this text sets in bold (none unless bold_numbers with a bold_font).
func bold_spans() -> Array:
	var out: Array = []
	if not bold_numbers or bold_font == null:
		return out
	for sp in number_spans(text):
		if sp[1]:
			out.append(str(sp[0]))
	return out


func _runs_width() -> float:
	var w := 0.0
	for l in _lines:
		w += (l[0] as TextLine).get_line_width()
	return w


func _line_count() -> int:
	if not _lines.is_empty() or _para == null:
		return 1
	var n := _para.get_line_count()
	return mini(n, max_lines) if max_lines > 0 else n


func _get_minimum_size() -> Vector2:
	_shape()
	var w := 0.0
	if not _lines.is_empty():
		w = _runs_width()
	elif _para and not wrap:
		w = _para.get_size().x
	return Vector2(ceilf(w + stroke * 2.0), ceilf(_lh() * _line_count()))


## Width of the widest line as shaped now (for callers that size a plate round the text).
func text_width() -> float:
	_shape()
	if not _lines.is_empty():
		return _runs_width()
	var w := 0.0
	if _para:
		for i in _para.get_line_count():
			w = maxf(w, _para.get_line_width(i))
	return w


func _draw() -> void:
	_shape()
	var lh := _lh()
	var n := _line_count()
	var total := lh * n
	var y0 := 0.0
	if valign == VERTICAL_ALIGNMENT_CENTER:
		y0 = (size.y - total) * 0.5
	elif valign == VERTICAL_ALIGNMENT_BOTTOM:
		y0 = size.y - total
	var ci := get_canvas_item()
	if not _lines.is_empty():
		var w := _runs_width()
		var x := _x_for(w)
		for l in _lines:
			var tl: TextLine = l[0]
			var c: Color = l[1] if l[1] != null else color
			var asc := tl.get_line_ascent()
			var des := tl.get_line_descent()
			var pos := Vector2(x, y0 + (lh - (asc + des)) * 0.5)
			_paint(func(p: Vector2, col: Color, outline: int): _draw_textline(tl, ci, p, col, outline), pos, c)
			x += tl.get_line_width()
		return
	for i in n:
		var asc := _para.get_line_ascent(i)
		var des := _para.get_line_descent(i)
		var lw := _para.get_line_width(i)
		# a wrapped paragraph's lines are aligned here, one by one (TextParagraph draws them from the left)
		var x := _para_line_x(i) if (wrap and size.x > 1.0) else _x_for(lw)
		var pos := Vector2(x, y0 + i * lh + (lh - (asc + des)) * 0.5)
		var li := i
		_paint(func(p: Vector2, col: Color, outline: int): _draw_paraline(li, ci, p, col, outline), pos, color)
		if strike or underline:
			var lx := pos.x
			var ly := pos.y + (asc * 0.62 if strike else asc + 4.0)
			draw_line(Vector2(lx, ly), Vector2(lx + lw, ly), color, maxf(2.0, font_size * 0.07))


func _para_line_x(i: int) -> float:
	# where an aligned line of a wrapped paragraph starts
	var lw := _para.get_line_width(i)
	match align:
		HORIZONTAL_ALIGNMENT_CENTER:
			return (size.x - lw) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			return size.x - lw
	return 0.0


func _x_for(w: float) -> float:
	match align:
		HORIZONTAL_ALIGNMENT_CENTER:
			return (size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			return size.x - w
	return 0.0


## Shadow, then stroke, then the fill: the mock's text-shadow and -webkit-text-stroke in draw order.
func _paint(fn: Callable, pos: Vector2, col: Color) -> void:
	if shadow > 0:
		if stroke > 0:
			fn.call(pos + Vector2(shadow, shadow), shadow_color, stroke * 2)
		fn.call(pos + Vector2(shadow, shadow), shadow_color, 0)
	if stroke > 0:
		fn.call(pos, stroke_color, stroke * 2)
	fn.call(pos, col, 0)


func _draw_textline(tl: TextLine, ci: RID, p: Vector2, col: Color, outline: int) -> void:
	if outline > 0:
		tl.draw_outline(ci, p, outline, col)
	else:
		tl.draw(ci, p, col)


func _draw_paraline(i: int, ci: RID, p: Vector2, col: Color, outline: int) -> void:
	# a wrapped paragraph's lines carry their own alignment offset when the paragraph has a width
	if outline > 0:
		_para.draw_line_outline(ci, p, i, outline, col)
	else:
		_para.draw_line(ci, p, i, col)
