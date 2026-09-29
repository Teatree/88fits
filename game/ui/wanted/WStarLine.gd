## "★ WANTED ★": tracked Bitter 600 between two drawn stars (no face here has the glyph). Over a modal it is paper;
## on the title it is ink.
class_name WStarLine
extends HBoxContainer

var _stars: Array = []


static func make(t: String, px: int = 30, col: Color = W.PAPER, em_frac: float = 0.35) -> WStarLine:
	var s := WStarLine.new()
	s.alignment = BoxContainer.ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# a space plus the tracking sits either side of the word in the mock
	s.add_theme_constant_override("separation", int(px * (0.3 + em_frac)))
	s._stars.append(_star(px, col))
	s.add_child(s._stars[0])
	var w := W.text(t.to_upper(), W.serif(600, false, W.em(px, em_frac)), px, col, HORIZONTAL_ALIGNMENT_CENTER, px * 1.25)
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_child(w)
	s._stars.append(_star(px, col))
	s.add_child(s._stars[1])
	return s


static func _star(px: int, col: Color) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(px * 0.84, px * 1.25)
	c.draw.connect(func(): WMarks.star(c, c.size * Vector2(0.5, 0.5), px * 0.4, col))
	return c
