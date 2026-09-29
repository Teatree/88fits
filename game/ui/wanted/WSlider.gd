## The slider: a 26 px aged track with a 4 px ink border, a brass fill, and an 80 x 70 paper thumb carrying the value in
## slab with a 5 px hard shadow. A TouchSlider underneath, so a finger moves it on the phone and the page still
## scrolls when the drag is vertical. `shown` maps the value to the number on the thumb (0..100 by default).
class_name WSlider
extends TouchSlider

const TRACK_H := 26.0
const THUMB := Vector2(90, 80)   # 80 x 70 inside a 5 px border
## The row the slider takes in a layout: its label's line (Bitter 30). The thumb hangs over it above and below, as the
## mock's absolutely placed thumb does, and still answers a finger anywhere on it (`_has_point`).
const ROW_H := 36.0

var shown: Callable


func _init() -> void:
	custom_minimum_size = Vector2(200, ROW_H)
	# the Slider draws nothing of its own; the travel matches the thumb (TouchSlider reads the grabber's width)
	var clear := Image.create_empty(int(THUMB.x), 1, false, Image.FORMAT_RGBA8)
	var ct := ImageTexture.create_from_image(clear)
	for k in ["grabber", "grabber_highlight", "grabber_disabled"]:
		add_theme_icon_override(k, ct)
	for k in ["slider", "grabber_area", "grabber_area_highlight"]:
		add_theme_stylebox_override(k, StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	value_changed.connect(func(_v): queue_redraw())


static func make(v: float, lo: float, hi: float, step_v: float = 0.01) -> WSlider:
	var s := WSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step_v
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func frac() -> float:
	return 0.0 if max_value <= min_value else clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)


## The thumb's middle under the finger: it sits at inner-left + fill + 5 (the mock's -40 on a 90 px thumb).
func _follow(local: Vector2) -> void:
	var inner_w := maxf(size.x - 8.0, 1.0)
	var f := clampf((local.x - 9.0) / inner_w, 0.0, 1.0)
	value = min_value + f * (max_value - min_value)


## A finger anywhere on the thumb (which hangs 22 px over the row above and below) or beside the track takes it.
func _has_point(p: Vector2) -> bool:
	var over := (THUMB.y - size.y) * 0.5 + 8.0
	return Rect2(Vector2(-THUMB.x * 0.5, -over), Vector2(size.x + THUMB.x, size.y + over * 2.0)).has_point(p)


func _draw() -> void:
	# the track (26 px inside a 4 px border) centred on the row; the thumb's top 20 px over the track's, its left edge
	# 40 px before the value's spot (tucked 4 px outside the track at 0), as the mock places them
	var track := Rect2(0, (size.y - TRACK_H - 8.0) * 0.5, size.x, TRACK_H + 8.0)
	draw_rect(track, W.INK)
	var inner := track.grow(-4.0)
	draw_rect(inner, W.AGED)
	var fw := inner.size.x * frac()
	if fw > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y)), W.BRASS)
	var tx := maxf(inner.position.x + fw - 40.0, inner.position.x - 4.0)
	var th := Rect2(Vector2(tx, track.position.y - 20.0), THUMB)
	draw_rect(Rect2(th.position + Vector2(5, 5), th.size), W.INK)
	draw_rect(th, W.INK)
	draw_rect(th.grow(-5.0), W.PAPER)
	var txt := str(int(round(shown.call(value)))) if shown.is_valid() else str(int(round(frac() * 100.0)))
	var f := W.slab()
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var base := th.position.y + (th.size.y - f.get_height(28)) * 0.5 + f.get_ascent(28)
	draw_string(f, Vector2(th.get_center().x - tw * 0.5, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, W.INK)
