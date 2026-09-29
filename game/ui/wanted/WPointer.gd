## An edge pointer: a paper tag riding the screen's left or right edge (no border on that side), a 22 px triangle in the
## target's colour pointing out (rock = boss, sage = portal, ember = Elite) and the name with the distance in slab.
class_name WPointer
extends Control

var color := W.ROCK
var text := "BOSS 43 m":
	set(v):
		if v != text:
			text = v
			_fit()
## -1 left edge, 1 right edge
var side := 1:
	set(v):
		side = v
		queue_redraw()

const PX := 26
const TRI := Vector2(22, 28)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()


func _fit() -> void:
	var f := W.slab()
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PX).x
	# padding 6/14/6/16, the triangle, an 8 px gap, the 4 px border on three sides
	size = Vector2(tw + TRI.x + 8.0 + 14.0 + 16.0 + 4.0, W.normal_height(f, PX) + 12.0 + 8.0)
	custom_minimum_size = size
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size), W.INK)
	draw_rect(r, W.INK)
	# no border on the edge side
	var inner := Rect2(r.position + Vector2(0.0 if side < 0 else 4.0, 4.0), r.size - Vector2(4.0, 8.0))
	draw_rect(inner, W.PAPER)
	var f := W.slab()
	var cy := r.size.y * 0.5
	var x := inner.position.x + (16.0 if side < 0 else 14.0)
	var tri := PackedVector2Array()
	if side < 0:
		tri = [Vector2(x, cy), Vector2(x + TRI.x, cy - TRI.y * 0.5), Vector2(x + TRI.x, cy + TRI.y * 0.5)]
	else:
		tri = [Vector2(x, cy - TRI.y * 0.5), Vector2(x + TRI.x, cy), Vector2(x, cy + TRI.y * 0.5)]
	draw_colored_polygon(tri, color)
	var base := cy - f.get_height(PX) * 0.5 + f.get_ascent(PX)
	draw_string(f, Vector2(x + TRI.x + 8.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PX, W.INK)
