## "★ WANTED ★": tracked Bitter 600 between two drawn stars (no face here has the glyph). Over a modal it is paper;
## on the title it is ink. Pass 54: one line can change its words and its colour afterwards (`set_text`, `recolour`:
## the boss's chest says "★ A PATH OPENS ★" in purple), so a screen that is reused keeps its line.
## Pass 122 (lane UIKIT_B), under Royale: the mock's "★ LEVEL UP ★": the words in the display face (Ultra
## from 28 px, Rubik 700 under it, W.slab_for) with the navy edge, gold wherever the Wanted line was paper, ink, soft ink,
## aged or brass (royale_colour; a colour of a screen's own maps through R.text_colour), the stars gold in a navy stroke,
## as big as today's.
class_name WStarLine
extends HBoxContainer

var _stars: Array = []
var _text: WText
## The words' and the stars' colour (the stars read it when they draw).
var color := W.PAPER


static func make(t: String, px: int = 30, col: Color = W.PAPER, em_frac: float = 0.35) -> WStarLine:
	var s := WStarLine.new()
	var c := royale_colour(col)
	s.color = c
	s.alignment = BoxContainer.ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# a space plus the tracking sits either side of the word in the mock
	s.add_theme_constant_override("separation", int(px * (0.3 + em_frac)))
	s._stars.append(_star(s, px))
	s.add_child(s._stars[0])
	var w: WText
	w = W.text(t.to_upper(), W.slab_for(px, W.em(px, em_frac)), px, c, HORIZONTAL_ALIGNMENT_CENTER, px * 1.25)
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s._text = w
	s.add_child(w)
	s._stars.append(_star(s, px))
	s.add_child(s._stars[1])
	return s


## The line's colour under Royale: gold for every Wanted ink and paper, a screen's own colour through the kit's map.
static func royale_colour(col: Color) -> Color:
	for c in [W.PAPER, W.INK, W.INK_SOFT, W.AGED, W.BRASS, W.BRASS_DARK]:
		if (c as Color).is_equal_approx(col):
			return R.GOLD_TEXT
	return R.text_colour(col)


static func _star(s: WStarLine, px: int) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(px * 0.84, px * 1.25)
	c.draw.connect(func():
		WMarks.star(c, c.size * Vector2(0.5, 0.5), px * 0.4, s.color, maxf(roundf(px * 0.07), 2.0), R.NAVY))
	return c


## The line's words (upper case, as made).
func text() -> String:
	return _text.text if _text else ""


func set_text(t: String) -> void:
	if _text:
		_text.text = t.to_upper()


## The words and both stars in `col` (under Royale the kit's reading of it, royale_colour).
func recolour(col: Color) -> void:
	color = royale_colour(col)
	if _text:
		_text.color = color
	for st in _stars:
		(st as Control).queue_redraw()
