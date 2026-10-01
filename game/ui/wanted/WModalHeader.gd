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


func set_line(t: String) -> void:
	line.text = t
	line.visible = t != ""


## The title stamps in (pass 44, the level-up reveal): from half again its size and a tilt down to its place, with a
## bounce. Called deferred, once the stack has laid out, so the pivot sits in the middle of the title.
func stamp() -> void:
	if title == null:
		return
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(1.6, 1.6)
	title.rotation = deg_to_rad(-4.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "rotation", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The entry motion: the stack drops 40 px with a 250 ms ease-out.
func drop_in() -> void:
	var y := offset_top
	offset_top = y - 40.0
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "offset_top", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
