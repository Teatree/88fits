## "★ WANTED ★": tracked Bitter 600 between two drawn stars (no face here has the glyph). Over a modal it is paper;
## on the title it is ink. Pass 54: one line can change its words and its colour afterwards (`set_text`, `recolour`:
## the boss's chest says "★ A PATH OPENS ★" in purple), so a screen that is reused keeps its line.
class_name WStarLine
extends HBoxContainer

var _stars: Array = []
var _text: WText
## The words' and the stars' colour (the stars read it when they draw).
var color := W.PAPER


static func make(t: String, px: int = 30, col: Color = W.PAPER, em_frac: float = 0.35) -> WStarLine:
	var s := WStarLine.new()
	s.color = col
	s.alignment = BoxContainer.ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# a space plus the tracking sits either side of the word in the mock
	s.add_theme_constant_override("separation", int(px * (0.3 + em_frac)))
	s._stars.append(_star(s, px))
	s.add_child(s._stars[0])
	var w := W.text(t.to_upper(), W.serif(600, false, W.em(px, em_frac)), px, col, HORIZONTAL_ALIGNMENT_CENTER, px * 1.25)
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s._text = w
	s.add_child(w)
	s._stars.append(_star(s, px))
	s.add_child(s._stars[1])
	return s


static func _star(s: WStarLine, px: int) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(px * 0.84, px * 1.25)
	c.draw.connect(func(): WMarks.star(c, c.size * Vector2(0.5, 0.5), px * 0.4, s.color))
	return c


## The line's words (upper case, as made).
func text() -> String:
	return _text.text if _text else ""


func set_text(t: String) -> void:
	if _text:
		_text.text = t.to_upper()


## The words and both stars in `col`.
func recolour(col: Color) -> void:
	color = col
	if _text:
		_text.color = col
	for st in _stars:
		(st as Control).queue_redraw()
