## A bar: an aged track with an ink border and a hard shadow, and a flat fill. It can carry text inside the fill (the
## results' "Killer Swarm · 6,540") and show a loss hatched in rock and ink at its end (the Stranger's price).
class_name WBar
extends Control

var value := 0.5:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var fill := W.ROCK
var track := W.AGED
var border := 4
var shadow := 4
## The part of the bar that is going away (drawn hatched after the fill).
var loss := 0.0
var text := ""
var text_px := 28
var text_color := W.INK


static func make(v: float, f: Color, h: float, p_border: int = 4, p_shadow: int = 4) -> WBar:
	var b := WBar.new()
	b.value = v
	b.fill = f
	b.border = p_border
	b.shadow = p_shadow
	b.custom_minimum_size = Vector2(0, h)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if shadow > 0:
		draw_rect(Rect2(r.position + Vector2(shadow, shadow), r.size), W.INK)
	draw_rect(r, W.INK)
	var inner := r.grow(-border)
	draw_rect(inner, track)
	var fw := inner.size.x * value
	if fw > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y)), fill)
	if loss > 0.0:
		var lr := Rect2(inner.position + Vector2(fw, 0), Vector2(inner.size.x * loss, inner.size.y))
		draw_rect(lr, W.INK)
		# rock stripes at 45 degrees over the ink (the mock's 8 px rock, 4 px ink)
		var step := 12.0
		var x := lr.position.x - lr.size.y
		while x < lr.end.x:
			var seg := W.clip_segment(Vector2(x, lr.end.y), Vector2(x + lr.size.y, lr.position.y), lr)
			if seg.size() == 2:
				draw_line(seg[0], seg[1], W.ROCK, 6.0)
			x += step
	if text != "":
		var f := W.slab()
		var base := inner.position.y + (inner.size.y - f.get_height(text_px)) * 0.5 + f.get_ascent(text_px)
		draw_string(f, Vector2(inner.position.x + 14.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, text_color)
