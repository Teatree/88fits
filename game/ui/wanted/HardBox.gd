## The kit's one box (the mock's "nine-slice"): a flat fill, an ink border on the chosen sides, and a hard ink shadow
## offset down-right with no blur. `press` draws the box sitting on its shadow (a pressed button), and `inner` draws a
## band just inside the border (the brass outline of a held card, the ember outline of an evolution). Corners are
## square unless `radius` is set (the icon plates), then the box is drawn through a StyleBoxFlat.
class_name HardBox
extends StyleBox

var fill := W.PAPER
var border := 5
var border_color := W.INK
## Which sides carry the border: left, top, right, bottom (a tab has no bottom, an edge pointer no right).
var sides := [true, true, true, true]
var shadow := 0
var shadow_color := W.INK
var radius := 0
var inner := 0
var inner_color := W.BRASS
var press := 0
var _flat: StyleBoxFlat
var _flat_shadow: StyleBoxFlat


func _init() -> void:
	set_content_margin_all(0)


func _draw(ci: RID, rect: Rect2) -> void:
	var r := rect
	if press > 0:
		r.position += Vector2(press, press)
	elif shadow > 0:
		if radius > 0:
			_flat_box(true).draw(ci, Rect2(r.position + Vector2(shadow, shadow), r.size))
		else:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(shadow, shadow), r.size), shadow_color)
	if radius > 0:
		_flat_box(false).draw(ci, r)
		return
	if fill.a > 0.0:
		RenderingServer.canvas_item_add_rect(ci, r, fill)
	if border > 0:
		var b := float(border)
		if sides[0]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(b, r.size.y)), border_color)
		if sides[1]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, b)), border_color)
		if sides[2]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - b, r.position.y), Vector2(b, r.size.y)), border_color)
		if sides[3]:
			RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - b), Vector2(r.size.x, b)), border_color)
	if inner > 0:
		var o := float(border)
		var i := float(inner)
		var ir := r.grow(-o)
		RenderingServer.canvas_item_add_rect(ci, Rect2(ir.position, Vector2(i, ir.size.y)), inner_color)
		RenderingServer.canvas_item_add_rect(ci, Rect2(ir.position, Vector2(ir.size.x, i)), inner_color)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(ir.end.x - i, ir.position.y), Vector2(i, ir.size.y)), inner_color)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(ir.position.x, ir.end.y - i), Vector2(ir.size.x, i)), inner_color)


func _flat_box(for_shadow: bool) -> StyleBoxFlat:
	var f := _flat_shadow if for_shadow else _flat
	if f == null:
		f = StyleBoxFlat.new()
		f.anti_aliasing = true
		if for_shadow:
			_flat_shadow = f
		else:
			_flat = f
	f.set_corner_radius_all(radius)
	if for_shadow:
		f.bg_color = shadow_color
		f.set_border_width_all(0)
	else:
		f.bg_color = fill
		f.border_color = border_color
		f.border_width_left = border if sides[0] else 0
		f.border_width_top = border if sides[1] else 0
		f.border_width_right = border if sides[2] else 0
		f.border_width_bottom = border if sides[3] else 0
	return f


## A copy that sits on its own shadow: pressed.
func pressed(fill_override: Color = Color(0, 0, 0, 0)) -> HardBox:
	var p: HardBox = duplicate()
	p.press = maxi(shadow, 0)
	if fill_override.a > 0.0:
		p.fill = fill_override
	# the content moves with the box
	p.content_margin_left = content_margin_left + p.press
	p.content_margin_top = content_margin_top + p.press
	p.content_margin_right = content_margin_right - p.press
	p.content_margin_bottom = content_margin_bottom - p.press
	return p


func pad(l: float, t: float, r: float, b: float) -> HardBox:
	content_margin_left = l
	content_margin_top = t
	content_margin_right = r
	content_margin_bottom = b
	return self
