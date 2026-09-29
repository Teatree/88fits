## The two-way choice: one bordered strip split by a 5 px ink line; the chosen half brass, the other paper with
## ink-soft text. Each half is a slab word with an optional Bitter line under it. Never a purchase.
class_name WChoice
extends HBoxContainer

signal chosen(index: int)

var index := 0
var _halves: Array = []
var _texts: Array = []


## options: [[title, sub], [title, sub]]
static func make(options: Array, p_index: int = 0, title_px: int = 36, sub_px: int = 24, pad: float = 20.0,
		align: int = HORIZONTAL_ALIGNMENT_CENTER, gap: int = 2) -> WChoice:
	var c := WChoice.new()
	c.add_theme_constant_override("separation", 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in options.size():
		var half := WTap.new()
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", gap)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var o: Array = options[i]
		var t := W.slab_text(str(o[0]), title_px, W.INK, align, title_px * 1.0)
		v.add_child(t)
		var s: WText = null
		if o.size() > 1 and str(o[1]) != "":
			s = W.serif_text(str(o[1]), sub_px, W.INK, 400, false, align, 0.0, true)
			v.add_child(s)
		half.add_child(v)
		half.set_meta("pad", pad)
		var idx := i
		half.pressed.connect(func(): c.choose(idx, true))
		c._halves.append(half)
		c._texts.append([t, s])
		c.add_child(half)
	c.choose(p_index, false)
	return c


func choose(i: int, emit: bool = false) -> void:
	index = i
	var n := _halves.size()
	for k in n:
		var on := k == i
		var pad: float = _halves[k].get_meta("pad")
		var b := W.box(W.BRASS if on else W.PAPER, 5, 0).pad(pad + (5.0 if k == 0 else 5.0), pad + 5.0, pad + (5.0 if k == n - 1 else 0.0), pad + 5.0)
		# one strip: the halves share the middle line, and the strip carries the shadow
		b.sides = [true, true, k == n - 1, true]
		(_halves[k] as WTap).box = b
		(_halves[k] as WTap).box_down = b
		for t in _texts[k]:
			if t:
				(t as WText).color = W.INK if on else W.INK_SOFT
	if emit:
		chosen.emit(i)


func _draw() -> void:
	# the strip's hard shadow, behind both halves
	draw_rect(Rect2(Vector2(6, 6), size), W.INK)
