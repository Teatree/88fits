## The slider: a 26 px aged track with a 4 px ink border, a brass fill, and an 80 x 70 paper thumb carrying the value in
## slab with a 5 px hard shadow. A TouchSlider underneath, so a finger moves it on the phone and the page still
## scrolls when the drag is vertical. `shown` maps the value to the number on the thumb (0..100 by default).
## Pass 122 (lane UIKIT_B), under Royale: the mock's slider: a black trough with the gold fill (WBar.paint),
## the stops as pale notches, and a slate value knob 68 x 58 (R.SLIDER_KNOB: the slate button face in a navy edge on a
## navy base) centred on the value, the number in white Ultra 28 with the navy edge. The row keeps its height and the
## finger its reach.
class_name WSlider
extends TouchSlider

const TRACK_H := 26.0
const THUMB := Vector2(90, 80)   # 80 x 70 inside a 5 px border
const KNOB_EDGE := 3.0
const KNOB_BASE := 4.0
const KNOB_PX := 28
## The row the slider takes in a layout: its label's line (Bitter 30). The thumb hangs over it above and below, as the
## mock's absolutely placed thumb does, and still answers a finger anywhere on it (`_has_point`).
const ROW_H := 36.0

var shown: Callable
## A stepped slider (pass 43: the volumes): this many stops, drawn as notches, the thumb naming the stop (0..n-1).
var levels := 0


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


## A slider with `n` stops from `lo` to `hi` (the volumes: five levels, not a hundred).
static func make_levels(v: float, n: int, lo: float = 0.0, hi: float = 1.0) -> WSlider:
	var s := make(v, lo, hi, (hi - lo) / float(maxi(n - 1, 1)))
	s.levels = n
	s.shown = func(x: float) -> float: return (x - lo) / (hi - lo) * float(n - 1)
	return s


func frac() -> float:
	return 0.0 if max_value <= min_value else clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)


## The thumb's middle under the finger: it sits at inner-left + fill + 5 (the mock's -40 on a 90 px thumb). Under
## Royale the knob is centred on the value's spot, so the finger's x is the spot.
func _follow(local: Vector2) -> void:
	var inner_w := maxf(size.x - 8.0, 1.0)
	var f := clampf((local.x - (4.0)) / inner_w, 0.0, 1.0)
	value = min_value + f * (max_value - min_value)


## A finger anywhere on the thumb (which hangs 22 px over the row above and below) or beside the track takes it.
func _has_point(p: Vector2) -> bool:
	var over := (THUMB.y - size.y) * 0.5 + 8.0
	return Rect2(Vector2(-THUMB.x * 0.5, -over), Vector2(size.x + THUMB.x, size.y + over * 2.0)).has_point(p)


func _draw() -> void:
	_draw_royale()
	return


## The value shown on the knob.
func shown_text() -> String:
	return str(int(round(shown.call(value)))) if shown.is_valid() else str(int(round(frac() * 100.0)))


## The Royale knob's box: R.SLIDER_KNOB centred on the value's spot along the track, kept inside the row's width.
func knob_rect() -> Rect2:
	var inner_x := 4.0
	var inner_w := maxf(size.x - 8.0, 1.0)
	var cx := clampf(inner_x + inner_w * frac(), R.SLIDER_KNOB.x * 0.5 - 4.0, size.x - R.SLIDER_KNOB.x * 0.5 + 4.0)
	return Rect2(Vector2(cx - R.SLIDER_KNOB.x * 0.5, (size.y - R.SLIDER_KNOB.y) * 0.5), R.SLIDER_KNOB)


## The Royale slider (pass 122): the trough and the gold fill (WBar.paint), the stops, the slate knob with its number.
func _draw_royale() -> void:
	var track := Rect2(0, (size.y - TRACK_H - 8.0) * 0.5, size.x, TRACK_H + 8.0)
	var inner := WBar.paint(self, track, frac(), R.BAR_GOLD, R.BAR_GOLD_LIP, 4.0)
	if levels > 1:
		for k in range(levels):
			var nx := inner.position.x + (inner.size.x - 4.0) * float(k) / float(levels - 1)
			draw_rect(Rect2(nx, inner.position.y, 4.0, inner.size.y), Color(1, 1, 1, 0.22))
	var kr := knob_rect()
	var ci := get_canvas_item()
	R.flat(R.NAVY, R.RADIUS).draw(ci, Rect2(kr.position + Vector2(0.0, KNOB_BASE), kr.size))
	R.flat(R.NAVY, R.RADIUS).draw(ci, kr)
	R.button_fill(ci, kr.grow(-KNOB_EDGE), "slate")
	var txt := shown_text()
	var f := W.slab_for(KNOB_PX)
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, KNOB_PX).x
	var base := kr.position.y + (kr.size.y - f.get_height(KNOB_PX)) * 0.5 + f.get_ascent(KNOB_PX)
	var at := Vector2(kr.get_center().x - tw * 0.5, base)
	draw_string_outline(f, at + Vector2(0, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, KNOB_PX, 2, R.NAVY)
	draw_string_outline(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, KNOB_PX, 2, R.NAVY)
	draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, KNOB_PX, R.WHITE)
