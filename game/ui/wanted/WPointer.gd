## An edge pointer: a paper tag riding the screen's left or right edge (no border on that side), a 22 px triangle in the
## target's colour pointing out (rock = boss, sage = portal, ember = Elite) and the name with the distance in slab.
## Pass 122 (lane UIKIT_B), under Royale (W.royale()): the mock's HUD pointer: a black info plate hugging the edge (56 %
## black, no edge, 6 px corners on its inner side), the arrow gold for the boss and an Elite and green for the portal
## (royale_arrow), the words white in the display face (Rubik 700 at this size, Garry's rule) with a navy edge.
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
	var f := W.slab_for(PX)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PX).x
	# padding 6/14/6/16, the triangle, an 8 px gap, the 4 px border on three sides
	size = Vector2(tw + TRI.x + 8.0 + 14.0 + 16.0 + 4.0, W.normal_height(f, PX) + 12.0 + 8.0)
	custom_minimum_size = size
	queue_redraw()


## The arrow's colour under Royale: green for the portal (the Wanted sage), gold for everything else.
static func royale_arrow(c: Color) -> Color:
	if c.is_equal_approx(W.SAGE):
		return R.role("green")["bottom"]
	return R.role("gold")["bottom"]


func _draw() -> void:
	if W.royale():
		_draw_royale()
		return
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


## The Royale pointer (pass 122): the black plate rounded on its inner side, the arrow, the white words.
func _draw_royale() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var corners := [side > 0, side < 0, side < 0, side > 0]
	var ci := get_canvas_item()
	R.flat(R.PLATE, R.RADIUS, corners).draw(ci, r)
	var px := float(R.PLATE_INSET_PX)
	draw_rect(Rect2(r.position, Vector2(r.size.x, px)), R.PLATE_INSET)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - px), Vector2(r.size.x, px)), R.PLATE_INSET)
	var inner := Rect2(r.position + Vector2(0.0 if side < 0 else 4.0, 4.0), r.size - Vector2(4.0, 8.0))
	var f := W.slab_for(PX)
	var cy := r.size.y * 0.5
	var x := inner.position.x + (16.0 if side < 0 else 14.0)
	var tri := PackedVector2Array()
	if side < 0:
		tri = [Vector2(x, cy), Vector2(x + TRI.x, cy - TRI.y * 0.5), Vector2(x + TRI.x, cy + TRI.y * 0.5)]
	else:
		tri = [Vector2(x, cy - TRI.y * 0.5), Vector2(x + TRI.x, cy), Vector2(x, cy + TRI.y * 0.5)]
	draw_colored_polygon(tri, royale_arrow(color))
	var base := cy - f.get_height(PX) * 0.5 + f.get_ascent(PX)
	var at := Vector2(x + TRI.x + 8.0, base)
	draw_string_outline(f, at + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PX, 2, R.NAVY)
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PX, 2, R.NAVY)
	draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PX, R.WHITE)
