## The kit's scroll thumb (pass 126, lane UI; Garry on the Heroes screen: "For the top part there is a clear scroll weight
## thing"): a dark rounded track down the side of a list with a cream rod for a thumb in a navy edge (lit down its left side, three
## grip notches in its middle), as long as the share of the list on view and as far down it as the list is, and a small gold arrow
## at the track's foot while there is more below. It says
## and takes nothing else (no touch: a finger moves the list by TouchScroll wherever it lands). Gone while the list fits. Nothing
## is done a frame: it redraws when the list's scroll bar changes.
## WScrollThumb.make(scroll_container), then add it over the list and give it its rect (R.SCROLL_THUMB_W wide).
class_name WScrollThumb
extends Control

var scroll: ScrollContainer


static func make(sc: ScrollContainer) -> WScrollThumb:
	var t := WScrollThumb.new()
	t.name = "ScrollThumb"
	t.scroll = sc
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := sc.get_v_scroll_bar()
	bar.changed.connect(t.queue_redraw)
	bar.value_changed.connect(func(_v: float) -> void: t.queue_redraw())
	return t


## Whether the list runs past its view.
func runs_over() -> bool:
	if scroll == null or not is_instance_valid(scroll):
		return false
	var bar := scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 1.0


## Whether more of the list lies below its view.
func more_below() -> bool:
	if not runs_over():
		return false
	var bar := scroll.get_v_scroll_bar()
	return bar.value < bar.max_value - bar.page - 1.0


## The track: the control's rect less the arrow's room at its foot.
func track_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x, maxf(size.y - R.SCROLL_ARROW_H, 0.0)))


## The thumb inside the track (R.SCROLL_THUMB_MIN at least), where the list stands.
func thumb_rect() -> Rect2:
	var track := track_rect()
	var bar := scroll.get_v_scroll_bar()
	var whole := maxf(bar.max_value, 1.0)
	var room := track.size.y - 2.0 * R.SCROLL_THUMB_INSET
	var h := clampf(room * bar.page / whole, minf(float(R.SCROLL_THUMB_MIN), room), room)
	var run := maxf(whole - bar.page, 1.0)
	var y := R.SCROLL_THUMB_INSET + (room - h) * clampf(bar.value / run, 0.0, 1.0)
	return Rect2(Vector2(R.SCROLL_THUMB_INSET, y), Vector2(track.size.x - 2.0 * R.SCROLL_THUMB_INSET, h))


func _draw() -> void:
	if not runs_over() or size.y < R.SCROLL_THUMB_MIN:
		return
	var track := track_rect()
	draw_style_box(R.flat(Color(R.NAVY, R.SCROLL_TRACK_ALPHA), int(track.size.x * 0.5)), track)
	var t := thumb_rect()
	var rad := int(t.size.x * 0.5)
	draw_style_box(R.flat(R.NAVY, rad + 2), t.grow(2.0))
	draw_style_box(R.flat(R.SCROLL_THUMB_LOW, rad), t)
	draw_style_box(R.flat(R.CREAM, int(t.size.x * 0.34)), Rect2(t.position, Vector2(t.size.x * 0.68, t.size.y)))
	# the grip: it is a thing a list hangs on, not a rule on the page
	var mid := t.get_center()
	for k in [-1, 0, 1]:
		draw_rect(Rect2(mid + Vector2(-t.size.x * 0.32, float(k) * R.SCROLL_GRIP_GAP - 1.0), Vector2(t.size.x * 0.64, 2.0)), R.NAVY)
	if more_below():
		# the arrow under the track: the list goes on down there
		var c := Vector2(size.x * 0.5, track.end.y + R.SCROLL_ARROW_H * 0.5 + 2.0)
		var w := size.x * 0.5 + 2.0
		var h := R.SCROLL_ARROW_H * 0.34
		var tri := PackedVector2Array([c + Vector2(-w, -h), c + Vector2(w, -h), c + Vector2(0.0, h)])
		draw_colored_polygon(tri, R.GOLD_TEXT)
		var edge := PackedVector2Array([tri[0], tri[1], tri[2], tri[0]])
		draw_polyline(edge, R.NAVY, 2.0, true)
