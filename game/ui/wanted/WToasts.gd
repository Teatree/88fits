## The toast queue under the timer: Alfa Slab 40 in paper (or toast green / purple) with a 2 px ink stroke and a 3 px
## hard shadow. One at a time, 1.2 s each, then a 200 ms fade; a newer toast pushes the one showing down to 60 % while
## it fades, so no more than two are ever on screen. A hint (first-play) sits in the same slot until it is cleared.
class_name WToasts
extends Control

const HOLD := 1.2
const FADE := 0.2
const PX := 40

var _queue: Array = []      # [text, colour]
var _shown: Array = []      # [WText, age]
var _hint: WText
var _gap := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Toasts only come in the kit's three colours: green for health, purple for XP, paper for everything else.
static func tone(c: Color) -> Color:
	if c.g > c.r * 1.25 and c.g > c.b:
		return W.TOAST_GREEN
	if c.b > c.g * 1.2 and c.r > c.g:
		return W.TOAST_PURPLE
	return W.PAPER


func push(t: String, c: Color = W.PAPER) -> void:
	_queue.append([t, tone(c)])
	# a burst of news: keep only the newest few waiting
	while _queue.size() > 4:
		_queue.pop_front()


func hint(t: String) -> void:
	if _hint == null:
		_hint = _make(t, W.PAPER)
		add_child(_hint)
	_hint.text = t
	_hint.visible = t != ""
	_layout()


func clear_hint() -> void:
	if _hint:
		_hint.visible = false
		_layout()


func _make(t: String, c: Color) -> WText:
	var w := W.text(t, W.slab(), PX, c, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	w.stroke = 2
	w.shadow = 3
	w.size = Vector2(size.x, W.normal_height(W.slab(), PX))
	return w


func tick(delta: float) -> void:
	_gap -= delta
	# the newest one on top: a new toast waits until the current one has been read for a moment
	if not _queue.is_empty() and (_shown.is_empty() or _gap <= 0.0):
		var q: Array = _queue.pop_front()
		var w := _make(str(q[0]), q[1])
		add_child(w)
		_shown.push_front([w, 0.0])
		_gap = 0.45
		while _shown.size() > 2:
			var old: Array = _shown.pop_back()
			(old[0] as Node).queue_free()
	for i in range(_shown.size() - 1, -1, -1):
		var s: Array = _shown[i]
		s[1] = float(s[1]) + delta
		var w: WText = s[0]
		var a := 1.0
		var age: float = s[1]
		if age > HOLD:
			a = 1.0 - (age - HOLD) / FADE
		if i > 0:
			a = minf(a, 0.6)
		w.modulate.a = clampf(a, 0.0, 1.0)
		if age > HOLD + FADE:
			w.queue_free()
			_shown.remove_at(i)
	_layout()


func _layout() -> void:
	var lh := W.normal_height(W.slab(), PX)
	var y := 0.0
	if _hint and _hint.visible:
		_hint.position = Vector2(0, y)
		_hint.size = Vector2(size.x, lh)
		y += lh + 6.0
	for s in _shown:
		var w: WText = s[0]
		w.position = Vector2(0, y)
		w.size = Vector2(size.x, lh)
		y += lh + 6.0
