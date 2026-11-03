## The tab strip: the chosen tab paper, the others aged with ink-soft text, 5 px ink borders with no bottom, and one
## 5 px base line running on to the right; the board under it has no top border, so the chosen tab opens into it.
## Pass 122 (lane UIKIT_A), under Royale: docked tabs 8 px apart, each a slate face with its top corners rounded (8 px)
## and no bottom edge, the chosen one gold and 12 px taller (the mock's 74 against 62) with navy text, the rest cream
## with the navy edge; no base line (the board, a slate panel with no top edge, docks them). Wanted draws as before.
class_name WTabs
extends HBoxContainer

signal changed(index: int)

var selected := 0
var _tabs: Array = []
var font_px := 30
var pad := Vector2(36, 16)


static func make(names: Array, px: int = 30, p_pad: Vector2 = Vector2(36, 16)) -> WTabs:
	var t := WTabs.new()
	t.font_px = px
	t.pad = p_pad
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var royale := W.royale()
	t.add_theme_constant_override("separation", R.TAB_GAP if royale else 0)
	for i in names.size():
		var tab := WTap.new()
		var lab := W.slab_text("", px, W.INK, HORIZONTAL_ALIGNMENT_CENTER, px * 1.369)
		var parts = names[i]
		if parts is Array:
			lab.runs = parts
		else:
			lab.text = str(parts)
		tab.add_child(lab)
		if royale:
			# the shorter tabs sit on the board's edge, the taller chosen one rises above them
			tab.size_flags_vertical = Control.SIZE_SHRINK_END
		var idx := i
		tab.pressed.connect(func(): t.select(idx, true))
		t._tabs.append(tab)
		t.add_child(tab)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rest.draw.connect(func():
		if W.royale():
			return
		rest.draw_rect(Rect2(0, rest.size.y - 5, rest.size.x, 5), W.INK))
	t.add_child(rest)
	t.select(0, false)
	return t


func select(i: int, emit: bool = false) -> void:
	selected = i
	var royale := W.royale()
	for k in _tabs.size():
		var on := k == i
		var b: HardBox
		if royale:
			var rise := float(R.TAB_H_ACTIVE - R.TAB_H) if on else 0.0
			b = W.box(W.PAPER, 5, 0).pad(pad.x + 5, pad.y + 5 + rise, pad.x + 5, pad.y)
			b.role = "gold" if on else "slate"
			b.sides = [true, true, true, false]
			b.radius = R.RADIUS_TAB
			b.corners = [true, true, false, false]
		else:
			b = W.box(W.PAPER if on else W.AGED, 5, 0).pad(pad.x + (5 if k == 0 else 0), pad.y + 5, pad.x + 5, pad.y)
			b.sides = [k == 0, true, true, false]
		var tab: WTap = _tabs[k]
		tab.box = b
		tab.box_down = b
		var lab: WText = tab.get_child(0)
		if royale:
			lab.color = R.NAVY if on else R.CREAM
			if on or not R.is_display(lab.font):
				R.no_edge(lab)
			else:
				R.edge(lab, font_px)
		else:
			lab.color = W.INK if on else W.INK_SOFT
	if emit:
		changed.emit(i)


## A tab's label again: a String, or runs ([[text, colour], ...]; the Collection's "Weapons 7/12").
func set_label(i: int, parts) -> void:
	var lab: WText = (_tabs[i] as WTap).get_child(0)
	if parts is Array:
		lab.text = ""
		lab.runs = parts
	else:
		lab.runs = []
		lab.text = str(parts)


## The board a tab strip sits on: paper, 5 px ink on three sides.
static func board() -> HardBox:
	var b := W.box(W.PAPER, 5, 0)
	b.sides = [true, false, true, true]
	return b
