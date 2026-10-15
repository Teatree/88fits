## The roll gauge (pass 82, lane TOTEM; design_handoff_88fits_totem, direction 1b): where a roll landed inside its own
## range, in thirds, with both ends written so a full gauge on one gift never outranks an empty one on another. One line,
## vertically centred: the low end in Bitter 600 18, `count` notches (56 x 18, a 3 px ink border, 8 px apart; brass when
## filled, aged when not), the high end. No feathers, no stars, no rarity colour: the gifts have no rarity.
class_name WNotches
extends Control

const NOTCH := Vector2(56, 18)
const NOTCH_BORDER := 3.0
const GAP := 8.0
const PX := 18

var low := "":
	set(v):
		low = v
		_changed()
var high := "":
	set(v):
		high = v
		_changed()
## How many notches are filled (the roll's third: 1, 2 or 3 of 3).
var filled := 0:
	set(v):
		filled = v
		queue_redraw()
var count := 3:
	set(v):
		count = maxi(v, 1)
		_changed()
var text_color := W.INK_SOFT
var fill_color := W.BRASS
var empty_color := W.AGED


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func make(p_low: String, p_high: String, p_filled: int, p_count: int = 3) -> WNotches:
	var g := WNotches.new()
	g.count = p_count
	g.low = p_low
	g.high = p_high
	g.filled = p_filled
	g.size = g.get_combined_minimum_size()
	return g


func _font() -> Font:
	return W.serif(600)


## The line's height: the end's text box (CSS normal line height) or a notch, the taller.
func line_h() -> float:
	return maxf(W.normal_height(_font(), PX), NOTCH.y)


func _text_w(t: String) -> float:
	return _font().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, PX).x if t != "" else 0.0


func _get_minimum_size() -> Vector2:
	var w := _text_w(low) + GAP + count * NOTCH.x + (count - 1) * GAP + GAP + _text_w(high)
	return Vector2(ceilf(w), line_h())


func _changed() -> void:
	update_minimum_size()
	queue_redraw()


## Notch `i`'s box (0-based), in the gauge's own coordinates.
func notch_rect(i: int) -> Rect2:
	var x := _text_w(low) + GAP + i * (NOTCH.x + GAP)
	return Rect2(Vector2(x, (line_h() - NOTCH.y) * 0.5), NOTCH)


func _draw() -> void:
	var f := _font()
	var lh := line_h()
	# the text centred in the line as CSS centres an inline box: half-leading round the face's own ascent and descent
	var base := (lh - (f.get_ascent(PX) + f.get_descent(PX))) * 0.5 + f.get_ascent(PX)
	if low != "":
		draw_string(f, Vector2(0, base), low, HORIZONTAL_ALIGNMENT_LEFT, -1, PX, text_color)
	for i in count:
		var r := notch_rect(i)
		draw_rect(r, W.INK)
		draw_rect(r.grow(-NOTCH_BORDER), fill_color if i < filled else empty_color)
	if high != "":
		var hx := notch_rect(count - 1).end.x + GAP
		draw_string(f, Vector2(hx, base), high, HORIZONTAL_ALIGNMENT_LEFT, -1, PX, text_color)
