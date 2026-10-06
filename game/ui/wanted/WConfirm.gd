## The question before a deed that cannot be undone (pass 45): a small wanted-poster card over an ink dim, "★ HOLD ON ★",
## the question in slab, one plain line on what is lost, an ink rule, and two buttons: the way out in paper on the left,
## the deed in rock on the right. Replaces every "Sure? Tap again" button. Works in the hub (a ScreenBase, the tree
## running) and in a run (a WModal or the arena panel on the `ui` CanvasLayer, the tree paused: PROCESS_MODE_ALWAYS).
## A tap on the dim is the way out; the hosts route the back gesture and Esc to `dismiss`; the host hiding takes the card
## with it. One per host at a time: a new question replaces the old one. Tools find it by class name and its buttons
## by name ("Cancel", "Confirm"); the dim carries the audit's `tap_at` meta, above the card.
class_name WConfirm
extends Control

signal confirmed
signal cancelled

const WIDTH_INSET := 60.0
## Where a finger (and tools/touch_audit.gd) taps the dim to cancel: above the card, canvas px.
const DIM_TAP := Vector2(540, 300)

var card: PanelContainer
var dim: WTap
var confirm_btn: WButton
var cancel_btn: WButton
var _on_confirm: Callable
var _on_cancel: Callable
var _done := false


## `host` is the screen or modal that asks (the card is its last child, over everything it holds).
static func open(host: Control, title: String, body: String, confirm_label: String, cancel_label: String,
		on_confirm: Callable, on_cancel: Callable = Callable()) -> WConfirm:
	var old := current(host)
	if old:
		old._finish(false, true)
	var c := WConfirm.new()
	c._on_confirm = on_confirm
	c._on_cancel = on_cancel
	c._build(title, body, confirm_label, cancel_label)
	host.add_child(c)
	c._enter()
	return c


static func current(host: Node) -> WConfirm:
	if host == null:
		return null
	for n in host.get_children():
		if n is WConfirm and not (n as WConfirm)._done:
			return n
	return null


static func is_open(host: Node) -> bool:
	return current(host) != null


## Cancels the question on `host`; true when there was one (the hosts call it first on the back gesture and Esc).
static func dismiss(host: Node) -> bool:
	var c := current(host)
	if c == null:
		return false
	c.cancel()
	return true


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("wanted_modal")


func _build(title: String, body: String, confirm_label: String, cancel_label: String) -> void:
	dim = WTap.new()
	dim.name = "Dim"
	var db := W.box(W.DIM_ASK, 0, 0)
	dim.box = db
	dim.box_down = db
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.set_meta("tap_at", DIM_TAP)
	dim.pressed.connect(cancel)
	add_child(dim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(50, 44, 50, 44))
	# anchored across the screen like the talent sheet (never in a Container, which would reset the tweened offset):
	# the height is its content's, the top is set once it has laid out
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	card.offset_left = WIDTH_INSET
	card.offset_right = -WIDTH_INSET
	card.offset_top = 700
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	v.add_child(WStarLine.make("Hold on", 24, W.INK_SOFT))
	var t := W.text(title.to_upper(), W.slab(), 64, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 64.0, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(t)
	var b := W.serif_text(body, 30, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 39.0, true)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(b)
	var rule := ColorRect.new()
	rule.color = W.INK
	rule.custom_minimum_size.y = 4
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	cancel_btn = WButton.make([cancel_label.to_upper()], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	cancel_btn.name = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(cancel)
	row.add_child(cancel_btn)
	confirm_btn = WButton.make([confirm_label.to_upper()], 34, WButton.DANGER, 5, 8, 26.0, 0.0)
	confirm_btn.name = "Confirm"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(confirm)
	row.add_child(confirm_btn)


## The kit's entry: the dim fades in over 200 ms, the card slides up 60 px and fades in over 250 ms (the talent
## sheet's). The card's height is known only after its wrapped lines have laid out, two frames in.
func _enter() -> void:
	dim.modulate.a = 0.0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	card.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _done or not is_inside_tree():
		return
	var h := maxf(card.size.y, card.get_combined_minimum_size().y)
	var y := (get_viewport_rect().size.y - h) * 0.5
	card.offset_top = y + 60.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "offset_top", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)


## What the rock button does (tools call it too).
func confirm() -> void:
	if _done:
		return
	_finish(true, false)
	if _on_confirm.is_valid():
		_on_confirm.call()


## What the paper button, the dim, the back gesture and Esc do.
func cancel() -> void:
	if _done:
		return
	_finish(false, false)
	if _on_cancel.is_valid():
		_on_cancel.call()


## Over: `ok` says which way; `at_once` frees the card without its fade (the host went away, or a new question replaced it).
func _finish(ok: bool, at_once: bool) -> void:
	_done = true
	remove_from_group("wanted_modal")
	# nothing under the fading card takes a touch meant for the screen beneath
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	W.pass_through(self)
	if ok:
		confirmed.emit()
	else:
		cancelled.emit()
	if at_once or not is_inside_tree():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)


## The host hid (the pause closed, the hero got up, the count ran out): the question goes with it, unanswered.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree() and not _done:
		_finish(false, true)
