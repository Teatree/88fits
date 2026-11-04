## The question before a deed that cannot be undone (pass 45): a small wanted-poster card over an ink dim, "★ HOLD ON ★",
## the question in slab, one plain line on what is lost, an ink rule, and two buttons: the way out in paper on the left,
## the deed in rock on the right. Replaces every "Sure? Tap again" button. Works in the hub (a ScreenBase, the tree
## running) and in a run (a WModal or the arena panel on the `ui` CanvasLayer, the tree paused: PROCESS_MODE_ALWAYS).
## A tap on the dim is the way out; the hosts route the back gesture and Esc to `dismiss`; the host hiding takes the card
## with it. One per host at a time: a new question replaces the old one. Tools find it by class name and its buttons
## by name ("Cancel", "Confirm"); the dim carries the audit's `tap_at` meta, above the card.
## Pass 123 (lane KIT2), under Royale: the mock's modal shell (10_Confirm; Garry: "one shared confirm pop-up (safe answer
## slate, destructive red, buying green)", "White header"): a slate panel R.MODAL_W (990) wide over the 80 % black dim,
## R.MODAL_PAD inside, "★ HOLD ON ★" in gold Ultra 30 tracked .3em, the question in cream Ultra 72, the line in white
## Rubik 500 28, no rule, the two buttons 106 tall (Ultra 38) on the card's foot, the card at least R.MODAL_MIN_H (520)
## tall with its top at R.MODAL_TOP_AT of the room (the mock's 560). Wanted is drawn as before.
## The same shell for every other pop-up (pass 123): WConfirm.shell(host, options) (the play-data card, the survey, the
## Hero details, the Upgrade board's choice): a star line and / or a corner word, a title, a body line, the caller's own
## rows in `body_box`, any number of buttons by role, a link under the card; it answers with the button's id (`answered`,
## `on_answer`), the dim, the back gesture and Esc answer `cancel_id`. Same dim, same entry, same one-per-host rule, found
## by the same tools.
class_name WConfirm
extends Control

signal confirmed
signal cancelled
## Pass 123: the id of the answer (a shell's button, its link, or its cancel_id for the dim / back / Esc); WConfirm.open
## answers "confirm" or "cancel".
signal answered(id: String)

const WIDTH_INSET := 60.0
## Where a finger (and tools/touch_audit.gd) taps the dim to cancel: above the card, canvas px.
const DIM_TAP := Vector2(540, 300)

var card: PanelContainer
var dim: WTap
var confirm_btn: WButton
var cancel_btn: WButton
## Pass 123: the shell's own rows go here (between the body line and the buttons), its button row and its link.
var body_box: VBoxContainer
var buttons_row: HBoxContainer
var link_btn: WTap
var _on_confirm: Callable
var _on_cancel: Callable
var _done := false
var _shell := false
var _o: Dictionary = {}
var _buttons: Dictionary = {}
var _cancel_id := "cancel"
var _confirm_id := "confirm"
var _keep_open := false
var _dim_cancels := true


## `host` is the screen or modal that asks (the card is its last child, over everything it holds). `kind` (pass 122,
## lane UIKIT_A): what the deed is, for the confirm button's colour: "danger" (the default: rock, Royale red), "buy"
## (a purchase: brass, Royale green) or "act" (the one thing that happens now: brass, Royale gold); the way out is
## always paper / slate.
static func open(host: Control, title: String, body: String, confirm_label: String, cancel_label: String,
		on_confirm: Callable, on_cancel: Callable = Callable(), kind: String = "danger") -> WConfirm:
	var old := current(host)
	if old:
		old._finish(false, true)
	var c := WConfirm.new()
	c._on_confirm = on_confirm
	c._on_cancel = on_cancel
	c._build(title, body, confirm_label, cancel_label, kind)
	host.add_child(c)
	c._enter()
	return c


## The modal shell (pass 123, lane KIT2): any pop-up in the confirm's frame, on `host` (one per host, as open's). Options:
##   "star": the star line's words ("A quick word"; "" none)      "corner": a small word top-right ("1 / 2", "DETAILS")
##   "title": the title ("" none)  "title_px": its size (R.MODAL_TITLE_PX 72)  "title_align": "center" | "left"
##   "title_upper": capitals (true)  "body": a plain line under it ("" none)  "body_px": its size (R.MODAL_BODY_PX 28)
##   "buttons": [{"id": String, "text": String or "parts": [WButton parts], "role": "slate" | "gold" | "green" |
##     "blue" | "red" | "locked"}, ...] left to right, equal widths ("cancel" and "confirm" are named "Cancel" and
##     "Confirm", the rest "Btn_<id>")   "button_h": their height (R.MODAL_BUTTON_H 106)   "button_px": their type (38)
##   "cancel_id": what the dim, the back gesture and Esc answer ("cancel")   "confirm_id": what confirm() answers (the
##     last button's id)   "dim_cancels": a tap on the dim answers cancel_id (true; false: the card wants an answer)
##   "keep_open": a button other than cancel_id answers and the card stays (a survey's NEXT); close() ends it; the link
##     always closes it
##   "min_h": the card's least height (0)   "width": its width (R.MODAL_W 990)
##   "link": an underlined line under the card ("Don't ask me again"), answering "link"
##   "body_margin": px either side of the body line under Royale (the mock's 40; 20 for a long text)
##   "on_answer": Callable(id: String), called after `answered`
## Put your own rows in the returned card's `body_box`. Under Wanted the same shell is the paper card.
static func shell(host: Control, o: Dictionary) -> WConfirm:
	var old := current(host)
	if old:
		old._finish(false, true)
	var c := WConfirm.new()
	c._shell = true
	c._o = o
	c._build_shell(o)
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


# --- the shell's pieces (pass 123): the card's box, the star line, the title, the body line, a button ---------------------
## The card's box: under Royale the slate panel (a 4 px navy edge, the 8 px navy base, R.MODAL_PAD inside); under Wanted
## the paper card (6 px ink, a 12 px shadow, 50 / 44 inside).
static func card_box() -> HardBox:
	if W.royale():
		var e := R.PANEL_EDGE
		return W.box(W.PAPER, e, R.PANEL_BASE).pad(R.MODAL_PAD.x + e, R.MODAL_PAD.y + e, R.MODAL_PAD.x + e, R.MODAL_PAD.y + e)
	return W.box(W.PAPER, 6, 12).pad(50, 44, 50, 44)


## The star line ("★ HOLD ON ★"): gold Ultra 30 tracked .3em under Royale, ink-soft Bitter 24 under Wanted.
static func make_star(t: String) -> WStarLine:
	if W.royale():
		return WStarLine.make(t, R.MODAL_STAR_PX, R.GOLD_TEXT, R.MODAL_STAR_EM)
	return WStarLine.make(t, 24, W.INK_SOFT)


## The title: cream Ultra (R.MODAL_TITLE_PX) with the navy edge under Royale (Garry: "White header"; Rubik 700 under 28
## px), wrapped; the ink slab 64 under Wanted. `px` 0 = the theme's size.
static func make_title(t: String, px: int = 0, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> WText:
	if W.royale():
		var tpx := px if px > 0 else R.MODAL_TITLE_PX
		var w := W.text(t, W.slab_for(tpx), tpx, R.CREAM, align, float(tpx), true)
		w.name = "Title"
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return w
	var wt := W.text(t, W.slab(), px if px > 0 else 64, W.INK, align, float(px if px > 0 else 64), true)
	wt.name = "Title"
	wt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return wt


## The body line: white Rubik 500 (R.MODAL_BODY_PX) at R.MODAL_BODY_LH under Royale, ink-soft Bitter 30 under Wanted;
## wrapped, numbers bold.
static func make_body(t: String, px: int = 0, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> WText:
	var b: WText
	if W.royale():
		var bpx := px if px > 0 else R.MODAL_BODY_PX
		b = W.serif_text(t, bpx, R.WHITE, 400, false, align, roundf(bpx * R.MODAL_BODY_LH), true)
	else:
		b = W.serif_text(t, px if px > 0 else 30, W.INK_SOFT, 400, false, align, 39.0, true)
	b.name = "Body"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## A shell button in `role` (Royale; Wanted plays the matching variant): `h` tall with `px` type.
static func make_button(parts: Array, role: String, h: float = 0.0, px: int = 0) -> WButton:
	var variant := WButton.SECONDARY
	match role:
		WButton.GOLD, WButton.GREEN:
			variant = WButton.PRIMARY
		WButton.BLUE:
			variant = WButton.UPGRADE
		WButton.RED:
			variant = WButton.DANGER
	if W.royale():
		var bh := h if h > 0.0 else float(R.MODAL_BUTTON_H)
		var bpx := px if px > 0 else R.MODAL_BUTTON_PX
		var e := R.BUTTON_EDGE
		return WButton.make(parts, bpx, variant, e, R.BUTTON_BASE, maxf((bh - 2.0 * e - bpx) * 0.5, 0.0), 0.0, float(bpx), role)
	return WButton.make(parts, px if px > 0 else 34, variant, 5, 8, 26.0, 0.0, 0.0, role)


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("wanted_modal")


func _make_dim() -> void:
	dim = WTap.new()
	dim.name = "Dim"
	var db := W.box(W.dim_color("ask"), 0, 0)
	dim.box = db
	dim.box_down = db
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.set_meta("tap_at", DIM_TAP)
	dim.pressed.connect(_on_dim)
	add_child(dim)


func _on_dim() -> void:
	if _shell and not _dim_cancels:
		return
	cancel()


func _build(title: String, body: String, confirm_label: String, cancel_label: String, kind: String = "danger") -> void:
	var royale := W.royale()
	if royale:
		# pass 123 (lane KIT2): the mock's shell; the deed's role by kind (buy green, act gold, the rest red)
		var role := WButton.RED
		match kind:
			"buy":
				role = WButton.GREEN
			"act":
				role = WButton.GOLD
		_build_shell({"star": "Hold on", "title": title, "body": body, "min_h": R.MODAL_MIN_H,
			"buttons": [{"id": "cancel", "text": cancel_label, "role": WButton.SLATE},
				{"id": "confirm", "text": confirm_label, "role": role}]})
		return
	_make_dim()
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
	# the star line: ink-soft on paper; gold on the Royale slate (pass 122)
	v.add_child(WStarLine.make("Hold on", 24, R.GOLD_TEXT if royale else W.INK_SOFT))
	var t := W.text(title.to_upper(), W.slab(), 64, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 64.0, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(t)
	var b := W.serif_text(body, 30, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 39.0, true)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(b)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.12) if royale else W.INK
	rule.custom_minimum_size.y = 2 if royale else 4
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
	# the deed's button by kind (pass 122): a buy is brass (Royale green), the one thing that happens now brass (gold),
	# anything that cannot be undone rock (red)
	var variant := WButton.DANGER
	var role := ""
	match kind:
		"buy":
			variant = WButton.PRIMARY
			role = WButton.GREEN
		"act":
			variant = WButton.PRIMARY
	confirm_btn = WButton.make([confirm_label.to_upper()], 34, variant, 5, 8, 26.0, 0.0, 0.0, role)
	confirm_btn.name = "Confirm"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.pressed.connect(confirm)
	row.add_child(confirm_btn)


## The shell's card (pass 123): see shell(). WConfirm.open under Royale lays its card out here too.
func _build_shell(o: Dictionary) -> void:
	var royale := W.royale()
	_cancel_id = str(o.get("cancel_id", "cancel"))
	_dim_cancels = bool(o.get("dim_cancels", true))
	_keep_open = bool(o.get("keep_open", false))
	var specs: Array = o.get("buttons", [])
	_confirm_id = str(o.get("confirm_id", (specs.back() as Dictionary).get("id", "confirm") if not specs.is_empty() else "confirm"))
	_make_dim()
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", card_box())
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var inset := (1080.0 - float(o.get("width", R.MODAL_W))) * 0.5 if royale else WIDTH_INSET
	card.offset_left = inset
	card.offset_right = -inset
	card.offset_top = 700
	card.custom_minimum_size.y = float(o.get("min_h", 0.0))
	add_child(card)
	var v := VBoxContainer.new()
	v.name = "Stack"
	v.add_theme_constant_override("separation", R.MODAL_GAP if royale else 24)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var star := str(o.get("star", ""))
	var corner := str(o.get("corner", ""))
	var title := str(o.get("title", ""))
	var align := HORIZONTAL_ALIGNMENT_LEFT if str(o.get("title_align", "center")) == "left" else HORIZONTAL_ALIGNMENT_CENTER
	var corner_used := false
	if star != "":
		var sl := make_star(star)
		if corner != "":
			# the star line at the left, the corner word at the right (the survey's "1 / 2")
			sl.alignment = BoxContainer.ALIGNMENT_BEGIN
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(_with_corner(sl, corner))
			corner_used = true
		else:
			v.add_child(sl)
	if title != "":
		var tt := make_title(title.to_upper() if bool(o.get("title_upper", true)) else title, int(o.get("title_px", 0)), align)
		if corner != "" and not corner_used:
			v.add_child(_with_corner(tt, corner))
		else:
			v.add_child(tt)
	var body := str(o.get("body", ""))
	if body != "":
		var bb := make_body(body, int(o.get("body_px", 0)), align)
		if royale:
			# the mock's 22 px either side of the line (the confirm's 40, the play data's 20)
			var m := MarginContainer.new()
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var side := int(o.get("body_margin", 20 if body.length() > 160 else 40))
			m.add_theme_constant_override("margin_left", side)
			m.add_theme_constant_override("margin_right", side)
			m.add_child(bb)
			v.add_child(m)
		else:
			v.add_child(bb)
	body_box = VBoxContainer.new()
	body_box.name = "Rows"
	body_box.add_theme_constant_override("separation", 12)
	body_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body_box)
	# the buttons sit on the card's foot when the card is taller than its words (min_h)
	var gap := Control.new()
	gap.name = "Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	if not royale:
		var rule := ColorRect.new()
		rule.color = W.INK
		rule.custom_minimum_size.y = 4
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(rule)
	buttons_row = HBoxContainer.new()
	buttons_row.name = "Buttons"
	buttons_row.add_theme_constant_override("separation", R.MODAL_BUTTON_GAP if royale else 24)
	buttons_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(buttons_row)
	var bh := float(o.get("button_h", 0.0))
	var bpx := int(o.get("button_px", 0))
	for spec in specs:
		var d := spec as Dictionary
		var id := str(d.get("id", ""))
		var parts: Array = d.get("parts", [str(d.get("text", id)).to_upper()])
		var btn := make_button(parts, str(d.get("role", WButton.SLATE)), bh, bpx)
		btn.name = "Cancel" if id == "cancel" else ("Confirm" if id == "confirm" else "Btn_%s" % id)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(answer.bind(id))
		buttons_row.add_child(btn)
		_buttons[id] = btn
	cancel_btn = _buttons.get("cancel") as WButton
	confirm_btn = _buttons.get("confirm") as WButton
	var link := str(o.get("link", ""))
	if link != "":
		link_btn = WTap.new()
		link_btn.name = "Link"
		var lb := W.box(Color(0, 0, 0, 0), 0, 0).pad(20, 12, 20, 12)
		link_btn.box = lb
		link_btn.box_down = lb
		var lt := W.serif_text(link, R.MODAL_LINK_PX if royale else 24, R.SECONDARY if royale else W.INK_SOFT, 400, false,
			HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
		lt.underline = true
		link_btn.add_child(lt)
		link_btn.pressed.connect(answer.bind("link"))
		add_child(link_btn)


## `piece` with a small word at the right of its row (the survey's "1 / 2", the Hero details' "DETAILS").
func _with_corner(piece: Control, word: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Head"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	piece.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(piece)
	var c := W.label(word, 20, W.INK_SOFT)
	c.name = "Corner"
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(c)
	return row


## A shell's button by its id (pass 123).
func button(id: String) -> WButton:
	return _buttons.get(id) as WButton


## The shell answers `id` (pass 123): a button, the link, or cancel_id (the dim, the back gesture, Esc). WConfirm.open's
## card answers "confirm" or "cancel" through confirm() and cancel().
func answer(id: String) -> void:
	if _done:
		return
	if not _shell:
		if id == "confirm":
			confirm()
		else:
			cancel()
		return
	var cb = _o.get("on_answer")
	if _keep_open and id != _cancel_id and id != "link":
		answered.emit(id)
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(id)
		return
	_finish(id != _cancel_id, false)
	answered.emit(id)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(id)


## A keep_open shell's end (pass 123): it leaves as an answer would, without one.
func close() -> void:
	if not _done:
		_finish(true, false)


## The kit's entry: the dim fades in over 200 ms, the card slides up 60 px and fades in over 250 ms (the talent
## sheet's). The card's height is known only after its wrapped lines have laid out, two frames in. Pass 123: under Royale
## the card's top sits R.MODAL_TOP_AT of the room above and below it (the mock's), a tall card's R.MODAL_TOP_AT_TALL.
func _enter() -> void:
	dim.modulate.a = 0.0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	card.modulate.a = 0.0
	if link_btn:
		link_btn.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _done or not is_inside_tree():
		return
	var h := maxf(card.size.y, card.get_combined_minimum_size().y)
	var vh := get_viewport_rect().size.y
	var at := 0.5
	if W.royale():
		at = R.MODAL_TOP_AT_TALL if h > R.MODAL_TALL else R.MODAL_TOP_AT
	var y := (vh - h) * at
	card.offset_top = y + 60.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "offset_top", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	if link_btn:
		var ls := link_btn.get_combined_minimum_size()
		link_btn.size = ls
		link_btn.position = Vector2((get_viewport_rect().size.x - ls.x) * 0.5, y + h + 60.0 + 20.0)
		tw.tween_property(link_btn, "position:y", y + h + 20.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(link_btn, "modulate:a", 1.0, 0.2)


## What the rock button does (tools call it too). Pass 123: a shell answers its confirm_id.
func confirm() -> void:
	if _done:
		return
	if _shell:
		answer(_confirm_id)
		return
	_finish(true, false)
	answered.emit("confirm")
	if _on_confirm.is_valid():
		_on_confirm.call()


## What the paper button, the dim, the back gesture and Esc do. Pass 123: a shell answers its cancel_id.
func cancel() -> void:
	if _done:
		return
	if _shell:
		answer(_cancel_id)
		return
	_finish(false, false)
	answered.emit("cancel")
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
