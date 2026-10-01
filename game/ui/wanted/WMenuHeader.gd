## The menu header: a 96 x 96 back square at (36, 44) (106 x 114 with its border and the 8 px under the glyph), the
## screen's name in 72 px slab beside it, and whatever sits top-right (the gold plate wherever gold can be spent, a
## count, a seal).
class_name WMenuHeader
extends Control

signal back

var back_button: WTap
var title: WText
var right: Control


static func make(t: String, right_node: Control = null) -> WMenuHeader:
	var h := WMenuHeader.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	h.offset_left = 36
	h.offset_right = -36
	h.offset_top = 44 + W.safe_top()
	h.offset_bottom = 44 + W.safe_top() + 114
	h.back_button = WTap.new()
	var bb := W.box(W.PAPER, 5, 6)
	h.back_button.box = bb
	h.back_button.box_down = bb.pressed()
	h.back_button.position = Vector2.ZERO
	h.back_button.size = Vector2(106, 114)
	h.back_button.custom_minimum_size = Vector2(106, 114)
	var arrow := W.slab_text("‹", 60, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	arrow.valign = VERTICAL_ALIGNMENT_CENTER
	# the glyph sits 8 px high in the mock (padding-bottom 8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_bottom", 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(arrow)
	h.back_button.add_child(m)
	h.back_button.pressed.connect(func(): h.back.emit())
	h.add_child(h.back_button)
	h.title = W.slab_text(t, 72, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 72.0)
	h.title.position = Vector2(106 + 24, (114 - 72) * 0.5)
	h.title.size = Vector2(700, 72)
	h.add_child(h.title)
	if right_node:
		h.set_right(right_node)
	return h


## Put `n` top-right; the one it replaces leaves (and is freed, unless it carries the meta "keep": a screen that swaps
## its count for a seal and back).
func set_right(n: Control) -> void:
	if right == n:
		return
	if right:
		remove_child(right)
		if not right.has_meta("keep"):
			right.queue_free()
	right = n
	add_child(n)
	n.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	n.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	n.grow_vertical = Control.GROW_DIRECTION_BOTH
	n.offset_right = 0
	n.offset_left = -n.get_combined_minimum_size().x
	n.offset_top = -n.get_combined_minimum_size().y * 0.5
	n.offset_bottom = n.get_combined_minimum_size().y * 0.5


## The gold plate: a coin and the number in slab on paper with a 5 px border and a hard shadow.
static func gold_plate(gold: int, px: int = 44, coin_px: float = 40.0, shadow: int = 6, border: int = 5) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, border, shadow).pad(22.0 + border, 6.0 + border, 22.0 + border, 6.0 + border))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(WCoin.make(coin_px))
	var n := W.slab_text(W.num(gold), px, W.INK, HORIZONTAL_ALIGNMENT_LEFT, px * 1.369)
	n.name = "Amount"
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(n)
	p.add_child(row)
	return p
