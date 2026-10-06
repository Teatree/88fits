## The header stack of every modal that pauses the run: a star line at y 110, the slab title (paper, 8 px ink hard
## shadow) and one dry italic line under it. It drops 40 px into place when the modal opens.
class_name WModalHeader
extends VBoxContainer

var star_line: WStarLine
var title: WText
var line: WText


## title_px: 150 for most modals (DOWN! 170, STAGE 1 CLEAR 108, a weapon name 96).
static func make(star: String, t: String, italic: String = "", title_px: int = 150, title_color: Color = W.PAPER,
		star_px: int = 30, top: float = 110.0, star_color: Color = W.PAPER) -> WModalHeader:
	var h := WModalHeader.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	h.add_theme_constant_override("separation", 0)
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	h.offset_top = top + W.safe_top()
	h.offset_left = 0
	h.offset_right = 0
	if star != "":
		h.star_line = WStarLine.make(star, star_px, star_color)
		h.add_child(h.star_line)
	h.title = W.slab_text(t, title_px, title_color, HORIZONTAL_ALIGNMENT_CENTER, title_px * 1.0)
	h.title.shadow = 8
	h.add_child(h.title)
	h.line = W.serif_text(italic, 30, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 39.0)
	h.line.visible = italic != ""
	h.add_child(h.line)
	h.line.custom_minimum_size.y = 49.0   # margin-top 10
	h.line.valign = VERTICAL_ALIGNMENT_BOTTOM
	return h


func set_title(t: String) -> void:
	title.text = t


## The title in `col` at `px`, or smaller until it fits `max_w` (pass 54: MUTATION CHEST is wider than the screen at 150);
## the line box keeps its height, so nothing under it moves. `max_w` 0 = no limit.
func set_title_fit(t: String, px: int, col: Color, max_w: float = 0.0) -> void:
	title.text = t
	title.color = col
	var f: Font = title.font if title.font else W.slab()
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var fit := px
	if max_w > 0.0 and w > max_w:
		fit = maxi(int(floor(px * max_w / w)), 24)
	title.font_size = fit


## The star line's words and colour (pass 54: the boss's chest's "★ A PATH OPENS ★" in purple, the loot's "★ LOOT ★"
## in paper); a header made without one gets none.
func set_star(t: String, col: Color) -> void:
	if star_line == null:
		return
	star_line.set_text(t)
	star_line.recolour(col)


func set_line(t: String) -> void:
	line.text = t
	line.visible = t != ""


## The title stamps in (pass 44, the level-up reveal): from half again its size and a tilt down to its place, with a
## bounce. Called deferred, once the stack has laid out, so the pivot sits in the middle of the title.
func stamp() -> void:
	if title == null:
		return
	stamp_in(title)


## Any piece stamps in the same way (pass 54: the mutation offer's weapon name after its reel). It must not sit in a
## Container that sorts again during the stamp (a VBox resets scale and rotation only when it sorts).
static func stamp_in(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.6, 1.6)
	c.rotation = deg_to_rad(-4.0)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The entry motion: the stack drops 40 px with a 250 ms ease-out.
func drop_in() -> void:
	var y := offset_top
	offset_top = y - 40.0
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "offset_top", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
