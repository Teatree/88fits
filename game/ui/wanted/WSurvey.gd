## The end-of-run survey card (pass 59, Garry: "ask people a couple of questions at the end of the run for their opinion
## about the game ... Only the Result Screens"). The questions come from PostHog Surveys (a survey of type API, written
## and edited in PostHog, fetched by core/autoload/Analytics.gd); the Results screen asks `Analytics.survey_after_run`
## and opens this card over an ink dim. One question a page: a rating (a row of numbers with the scale's two labels), a
## single choice, a multiple choice or a short text (optional ones can be left empty), "1 / 3" in the corner, NOT NOW
## (PostHog's "survey dismissed") and NEXT / SEND ("survey sent" with every answer); under the card "Don't ask me again"
## turns Settings' "Questions after a run" off and tells PostHog (survey_opt_out). A tap on the dim does nothing.
## No class_name: open it with preload("res://ui/wanted/WSurvey.gd").open(host, survey).
## Names for tools: "NotNow", "Next", "NeverAsk", "Choice<i>", "Rate<n>", "Answer" (the text box).
## Pass 60 (Garry: "Survey Type here doesn't seem to work. I tap and the ability to type doesn't appear (the keyboard)"):
## the game keeps emulate_mouse_from_touch off, and Godot's TextEdit takes focus only from a mouse click, so a finger on
## the box did nothing on the phone. The box now takes focus from a finger (its gui_input), which raises the phone's
## keyboard (TextEdit shows it on focus; a belt-and-braces DisplayServer.virtual_keyboard_show follows a frame later when
## none has come up), wears a brass ring while focused, the card rises so its foot (the SEND row) stays over the keyboard
## (keyboard_canvas_height / lift_for, polled in _process), and a finger anywhere outside the box lets the focus go, which
## hides the keyboard.
## Pass 123 (lane RUN_C), under Royale (W.royale(); Garry: "Consent and survey pop-ups in the shared pop-up shell, as the
## mock", "White header"): the card is the kit's modal shell (WConfirm's pieces, the mock 10_Survey): the slate panel
## R.MODAL_W wide over the 80 % black dim, "★ A QUICK WORD ★" in gold Ultra at the left with "1 / 2" at the right, the
## question in cream Ultra QUESTION_PX at the left, the 1-5 cells slate with the pick gold (WButton roles; the choices
## the same), the scale's ends in italic Rubik, the text box a solid navy cell with a gold edge while focused, no rule,
## NOT NOW slate · NEXT blue on the card's foot (BUTTON_H), the card at least SURVEY_MIN_H tall with its top
## R.MODAL_TOP_AT of the room (never higher than CARD_TOP under the cutout, so the keyboard's lift works as before), and
## "Don't ask me again" an underlined link 20 px under it. Every answer, name and rule is today's; Wanted as before.
extends Control

## "sent", "dismissed" or "opted_out"
signal finished(how: String)

const WIDTH_INSET := 50.0
## The card's top under the camera cutout, high enough that a phone's keyboard leaves the text box in view.
const CARD_TOP := 330.0
const THANKS_HOLD := 1.2
## The card's foot stays this far over the phone's keyboard (pass 60), and its top never rises past this under the cutout.
const KEYBOARD_GAP := 24.0
const LIFT_TOP_MIN := 20.0
const LIFT_SECONDS := 0.2
## Under Royale (pass 123, the mock 10_Survey): the card's least height, the question's size, the rating cells' height
## and type, the buttons' height and type, the link's gap under the card.
const SURVEY_MIN_H := 620.0
const QUESTION_PX := 44
const CELL_H := 100.0
const CELL_PX := 40
const CHOICE_PX := 30
const BUTTON_H := 96.0
const BUTTON_PX := 34
const LINK_GAP := 20.0

var survey: Dictionary = {}
var answers: Dictionary = {}
var page := 0
var card: PanelContainer
var dim: ColorRect
var next_btn: WButton
var not_now_btn: WButton
var never_btn: WTap
var _q_box: VBoxContainer
var _progress: WText
var _value: Variant = null
var _choices: Array = []
var _text: TextEdit
var _done := false
## The card's top is composed (pass 60): its resting top (CARD_TOP under the cutout), less the lift drawn for the
## keyboard (tweened toward the lift asked, _kb_lift), plus the entrance's slide (60 px at first, tweened to 0); two
## tweens on the one offset had fought (the entrance's last write undid a lift asked while it ran).
var _base_top := 0.0
var _kb_lift := 0.0
var _lift_shown := 0.0
var _drop := 0.0
var _lift_tw: Tween


static func open(host: Control, sv: Dictionary) -> Control:
	var c: Control = load("res://ui/wanted/WSurvey.gd").new()
	c.name = "Survey"
	c.set("survey", sv)
	c.call("_build")
	host.add_child(c)
	c.call("_enter")
	Analytics.survey_shown(sv)
	return c


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("wanted_modal")


func questions() -> Array:
	return survey.get("questions", [])


func _build() -> void:
	if W.royale():
		_build_royale()
		return
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = W.DIM_ASK
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(44, 40, 44, 40))
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	card.offset_left = WIDTH_INSET
	card.offset_right = -WIDTH_INSET
	_base_top = CARD_TOP + W.safe_top()
	card.offset_top = _base_top
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 26)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star := WStarLine.make("A quick word", 24, W.INK_SOFT)
	star.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(star)
	_progress = W.serif_text("", 24, W.INK_SOFT, 600, false, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, false, false)
	_progress.name = "Progress"
	head.add_child(_progress)
	v.add_child(head)
	_q_box = VBoxContainer.new()
	_q_box.name = "Question"
	_q_box.add_theme_constant_override("separation", 22)
	_q_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_q_box)
	var rule := ColorRect.new()
	rule.color = W.INK
	rule.custom_minimum_size.y = 4
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	not_now_btn = WButton.make(["NOT NOW"], 32, WButton.SECONDARY, 5, 8, 24.0, 0.0)
	not_now_btn.name = "NotNow"
	not_now_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	not_now_btn.pressed.connect(dismiss)
	row.add_child(not_now_btn)
	next_btn = WButton.make(["NEXT"], 32, WButton.PRIMARY, 5, 8, 24.0, 0.0)
	next_btn.name = "Next"
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.pressed.connect(next)
	row.add_child(next_btn)
	# under the card: a plain line to stop the questions for good
	never_btn = WTap.new()
	never_btn.name = "NeverAsk"
	var nb := W.box(Color(0, 0, 0, 0), 0, 0).pad(20, 16, 20, 16)
	never_btn.box = nb
	never_btn.box_down = nb
	never_btn.add_child(W.serif_text("Don't ask me again", 26, W.PAPER, 600, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false))
	never_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	never_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	never_btn.pressed.connect(never_ask)
	add_child(never_btn)
	show_page(0)


## The Royale card (pass 123): the kit's modal shell from WConfirm's pieces, keeping the survey's own names, pages,
## keyboard lift and answers.
func _build_royale() -> void:
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.color = W.dim_color("ask")
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", WConfirm.card_box())
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var inset := (1080.0 - float(R.MODAL_W)) * 0.5
	card.offset_left = inset
	card.offset_right = -inset
	card.custom_minimum_size.y = SURVEY_MIN_H
	_base_top = CARD_TOP + W.safe_top()
	card.offset_top = _base_top
	add_child(card)
	var v := VBoxContainer.new()
	v.name = "Stack"
	v.add_theme_constant_override("separation", R.MODAL_GAP)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	# the star line at the left, "1 / 2" at the right (the shell's corner word)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star := WConfirm.make_star("A quick word")
	star.alignment = BoxContainer.ALIGNMENT_BEGIN
	star.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(star)
	_progress = W.label("", 20, W.INK_SOFT)
	_progress.name = "Progress"
	_progress.align = HORIZONTAL_ALIGNMENT_RIGHT
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_progress)
	v.add_child(head)
	_q_box = VBoxContainer.new()
	_q_box.name = "Question"
	_q_box.add_theme_constant_override("separation", 16)
	_q_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_q_box)
	# no rule: the buttons sit on the card's foot
	var gap := Control.new()
	gap.name = "Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", R.MODAL_BUTTON_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	not_now_btn = WConfirm.make_button(["NOT NOW"], WButton.SLATE, BUTTON_H, BUTTON_PX)
	not_now_btn.name = "NotNow"
	not_now_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	not_now_btn.pressed.connect(dismiss)
	row.add_child(not_now_btn)
	next_btn = WConfirm.make_button(["NEXT"], WButton.BLUE, BUTTON_H, BUTTON_PX)
	next_btn.name = "Next"
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.pressed.connect(next)
	row.add_child(next_btn)
	# under the card: the shell's link (underlined, the secondary blue), a finger's height to tap
	never_btn = WTap.new()
	never_btn.name = "NeverAsk"
	var nb := W.box(Color(0, 0, 0, 0), 0, 0).pad(20, 22, 20, 22)
	never_btn.box = nb
	never_btn.box_down = nb
	var lt := W.serif_text("Don't ask me again", R.MODAL_LINK_PX, R.SECONDARY, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	lt.underline = true
	never_btn.add_child(lt)
	never_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	never_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	never_btn.pressed.connect(never_ask)
	add_child(never_btn)
	show_page(0)


func _enter() -> void:
	dim.modulate.a = 0.0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	card.modulate.a = 0.0
	never_btn.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if _done or not is_inside_tree():
		return
	if W.royale():
		# pass 123: the shell's place (R.MODAL_TOP_AT of the room), never higher than today's CARD_TOP under the cutout
		var h := maxf(card.size.y, card.get_combined_minimum_size().y)
		_base_top = maxf(CARD_TOP + W.safe_top(), (get_viewport_rect().size.y - h) * R.MODAL_TOP_AT)
		_place_card()
	_place_never()
	_set_drop(60.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_set_drop, 60.0, 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	tw.tween_property(never_btn, "modulate:a", 1.0, 0.3)


## "Don't ask me again" sits 30 px under the card's foot (pass 123: the link's tap box under Royale, its words LINK_GAP
## under the foot).
func _place_never() -> void:
	var h := maxf(card.size.y, card.get_combined_minimum_size().y)
	never_btn.offset_top = card.offset_top + h + (LINK_GAP - 22.0 + 8.0 if W.royale() else 30.0)
	never_btn.offset_bottom = never_btn.offset_top + 70.0
	never_btn.offset_left = -260
	never_btn.offset_right = 260


## Page `i`: the question, its line under it, and the way to answer.
func show_page(i: int) -> void:
	page = i
	_value = null
	_choices = []
	_text = null
	# freed at once: the page's own nodes never wait as orphans (no handler of theirs is running: NEXT is not on the page)
	for c in _q_box.get_children():
		_q_box.remove_child(c)
		c.free()
	var qs := questions()
	var q: Dictionary = qs[i]
	_progress.text = "%d / %d" % [i + 1, qs.size()]
	var qt: WText
	if W.royale():
		# pass 123: the shell's title at the left, cream Ultra (Garry: "White header"), as it is written
		qt = WConfirm.make_title(str(q.get("question", "")), QUESTION_PX, HORIZONTAL_ALIGNMENT_LEFT)
	else:
		qt = W.serif_text(str(q.get("question", "")), 38, W.INK, 700, false, HORIZONTAL_ALIGNMENT_LEFT, 48.0, true, false)
	qt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_q_box.add_child(qt)
	var desc := str(q.get("description", ""))
	if desc != "":
		var dt := W.serif_text(desc, 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 34.0, true, false)
		dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_q_box.add_child(dt)
	match str(q.get("type", "")):
		"rating":
			_rating(q)
		"single_choice", "multiple_choice":
			_choice_list(q, str(q.get("type")) == "multiple_choice")
		"open":
			_open_text(q)
	next_btn.set_parts(["SEND" if i == qs.size() - 1 else "NEXT"])
	_refresh_next()
	if is_inside_tree():
		_place_never.call_deferred()


func _rating(q: Dictionary) -> void:
	var n := int(q.get("scale", 5))
	var per_row := 5 if n > 5 else n
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = null
	for k in range(1, n + 1):
		if row == null or row.get_child_count() >= per_row:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(row)
		var b := _cell([str(k)], CELL_PX, CELL_H) if W.royale() else WButton.make([str(k)], 40, WButton.SECONDARY, 5, 6, 18.0, 0.0)
		b.name = "Rate%d" % k
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := k
		b.pressed.connect(func(): _pick_single(b, val))
		row.add_child(b)
		_choices.append(b)
	_q_box.add_child(rows)
	var lo := str(q.get("lower", ""))
	var hi := str(q.get("upper", ""))
	if lo != "" or hi != "":
		var ends := HBoxContainer.new()
		ends.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := W.serif_text(lo, 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ends.add_child(l)
		ends.add_child(W.serif_text(hi, 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, false, false))
		_q_box.add_child(ends)


## A Royale answer cell (pass 123, the mock's 1-5 cells): a slate button `h` tall (0: its words' height with 18 px above
## and below) with `px` type; the pick turns it gold (_mark).
func _cell(parts: Array, px: int, h: float) -> WButton:
	var e := R.BUTTON_EDGE
	var pad_v := maxf((h - 2.0 * e - float(px)) * 0.5, 0.0) if h > 0.0 else 18.0
	return WButton.make(parts, px, WButton.SECONDARY, e, R.BUTTON_BASE, pad_v, 0.0 if h > 0.0 else 20.0, float(px), WButton.SLATE)


func _choice_list(q: Dictionary, many: bool) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var choices: Array = q.get("choices", [])
	for k in choices.size():
		var c := str(choices[k])
		var b := _cell([c], CHOICE_PX, 0.0) if W.royale() else WButton.make([c], 30, WButton.SECONDARY, 5, 6, 18.0, 20.0)
		b.name = "Choice%d" % k
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if many:
			b.pressed.connect(func(): _toggle(b, c))
		else:
			b.pressed.connect(func(): _pick_single(b, c))
		col.add_child(b)
		_choices.append(b)
	if many:
		_value = []
		var hint := W.serif_text("Pick any that fit.", 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
		_q_box.add_child(hint)
	_q_box.add_child(col)


func _open_text(q: Dictionary) -> void:
	_text = TextEdit.new()
	_text.name = "Answer"
	_text.custom_minimum_size = Vector2(0, 190)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = "Type here" + (" (or leave it empty)" if bool(q.get("optional", false)) else "")
	_text.add_theme_font_override("font", W.serif(400, false))
	_text.add_theme_font_size_override("font_size", 30)
	_text.add_theme_color_override("font_color", W.INK)
	_text.add_theme_color_override("font_placeholder_color", W.INK_SOFT)
	_text.add_theme_color_override("caret_color", W.INK)
	var box := W.box(W.AGED, 4, 0).pad(18, 14, 18, 14)
	# focused: paper in a brass ring, the kit's mark of the piece in hand (pass 60)
	var focus := W.box(W.PAPER, 4, 0).pad(18, 14, 18, 14)
	focus.border_color = W.BRASS
	if W.royale():
		# pass 123: a solid navy cell (W.cell_box), cream words, the placeholder in the secondary blue; focused, its edge
		# in the kit's gold
		box = W.cell_box(Vector2(18, 14))
		focus = W.cell_box(Vector2(18, 14))
		focus.border_color = R.GOLD_TEXT
		_text.add_theme_color_override("font_color", R.CREAM)
		_text.add_theme_color_override("font_placeholder_color", Color(R.SECONDARY, 0.6))
		_text.add_theme_color_override("caret_color", R.CREAM)
	_text.add_theme_stylebox_override("normal", box)
	_text.add_theme_stylebox_override("focus", focus)
	_text.text_changed.connect(_refresh_next)
	# a finger on the box focuses it (pass 60): the engine's TextEdit listens to the mouse alone, and the phone sends none
	_text.gui_input.connect(_on_answer_input)
	_q_box.add_child(_text)


## A finger (or a click) on the answer box: the box takes focus, which raises the phone's keyboard; if none has come up a
## frame later (a TextEdit that was not asked to), it is asked for outright.
func _on_answer_input(event: InputEvent) -> void:
	if _text == null or _done:
		return
	var pressed := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not pressed or _text.has_focus():
		return
	_text.grab_focus()
	_ensure_keyboard.call_deferred()


## The keyboard, asked for by hand when focus alone did not raise it (only where there is one to raise: the phone).
func _ensure_keyboard() -> void:
	if _text == null or not is_instance_valid(_text) or not _text.has_focus():
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	if DisplayServer.virtual_keyboard_get_height() <= 0:
		DisplayServer.virtual_keyboard_show(_text.text, _text.get_global_rect(), DisplayServer.KEYBOARD_TYPE_MULTILINE)


## Whether the answer box is the focused piece (tests, tools).
func answer_focused() -> bool:
	return _text != null and is_instance_valid(_text) and _text.has_focus()


## A finger anywhere outside the answer box lets its focus go (the keyboard goes with it); the finger still reaches
## whatever it landed on (SEND, a choice), since nothing here is marked handled.
func _input(event: InputEvent) -> void:
	if _done or not answer_focused():
		return
	var pressed := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not pressed:
		return
	var at: Vector2 = (event as InputEvent).get("position")
	if not _text.get_global_rect().has_point(at):
		_text.release_focus()


## The phone's keyboard, as the canvas measures it (its height comes in the window's pixels, like W.safe_top's inset);
## 0 where there is none.
func keyboard_canvas_height() -> float:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return 0.0
	var h := float(DisplayServer.virtual_keyboard_get_height())
	if h <= 0.0:
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return h
	return h * get_viewport_rect().size.x / float(win.x)


## How far the card must rise so its foot (the rule and the SEND row under the box) stays KEYBOARD_GAP over a keyboard
## `kb_px` tall (canvas px): 0 while the card already clears it, never so far that its top passes LIFT_TOP_MIN under
## the cutout.
func lift_for(kb_px: float) -> float:
	if kb_px <= 0.0 or card == null:
		return 0.0
	var h := maxf(card.size.y, card.get_combined_minimum_size().y)
	var foot := _base_top + h + KEYBOARD_GAP
	var kb_top := get_viewport_rect().size.y - kb_px
	var lift := maxf(foot - kb_top, 0.0)
	return minf(lift, maxf(_base_top - (W.safe_top() + LIFT_TOP_MIN), 0.0))


## The card's top from its parts: the resting top, the lift drawn and the entrance's slide.
func _place_card() -> void:
	card.offset_top = _base_top - _lift_shown + _drop


func _set_drop(d: float) -> void:
	_drop = d
	_place_card()


func _set_lift_shown(l: float) -> void:
	_lift_shown = l
	_place_card()


## The card slides to its lifted place (and back when the keyboard goes); "Don't ask me again" follows its foot.
func _set_lift(lift: float) -> void:
	_kb_lift = lift
	if _lift_tw and _lift_tw.is_valid():
		_lift_tw.kill()
	_lift_tw = create_tween()
	_lift_tw.tween_method(_set_lift_shown, _lift_shown, lift, LIFT_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lift_tw.tween_callback(_place_never)


## The lift the keyboard asks for right now (tests, tools): applied when it changes.
func keyboard_lift() -> float:
	return _kb_lift


func _process(_delta: float) -> void:
	if _done or card == null:
		return
	var want := lift_for(keyboard_canvas_height())
	if not is_equal_approx(want, _kb_lift):
		_set_lift(want)


## A choice picked: brass, the others paper again.
func _pick_single(b: WButton, val) -> void:
	_value = val
	for c in _choices:
		_mark(c, c == b)
	_refresh_next()


func _toggle(b: WButton, val: String) -> void:
	var list: Array = _value if _value is Array else []
	if list.has(val):
		list.erase(val)
		_mark(b, false)
	else:
		list.append(val)
		_mark(b, true)
	_value = list
	_refresh_next()


func _mark(b: WButton, on: bool) -> void:
	if W.royale():
		# pass 123: the pick gold, the rest slate (the kit's button roles; a HardBox copy by duplicate() keeps none of its
		# fields under Royale)
		if b.role != (WButton.GOLD if on else WButton.SLATE):
			b.set_role(WButton.GOLD if on else WButton.SLATE)
		b.set_meta("on", on)
		return
	if not b.has_meta("paper"):
		b.set_meta("paper", b.box)
		b.set_meta("paper_down", b.box_down)
	if on:
		var hb: HardBox = (b.get_meta("paper") as HardBox).duplicate()
		hb.fill = W.BRASS
		b.box_down = hb.pressed(W.BRASS_DARK)
		b.box = hb
	else:
		b.box_down = b.get_meta("paper_down")
		b.box = b.get_meta("paper")
	b.set_meta("on", on)


func is_marked(b: WButton) -> bool:
	return bool(b.get_meta("on", false))


## This page's answer, or null when it has none (an empty text, nothing picked).
func current_answer() -> Variant:
	if _text != null:
		var t := _text.text.strip_edges()
		return t if t != "" else null
	if _value is Array:
		return null if (_value as Array).is_empty() else (_value as Array).duplicate()
	return _value


func can_go_on() -> bool:
	var q: Dictionary = questions()[page]
	return current_answer() != null or bool(q.get("optional", false))


func _refresh_next() -> void:
	next_btn.locked = not can_go_on()


## NEXT keeps the answer and turns the page; on the last page SEND sends them all.
func next() -> void:
	if _done or not can_go_on():
		return
	var q: Dictionary = questions()[page]
	var a = current_answer()
	if a != null:
		answers[str(q.get("id", ""))] = a
	if page + 1 < questions().size():
		show_page(page + 1)
		return
	_done = true
	Analytics.survey_sent(survey, answers)
	finished.emit("sent")
	_thanks()


## NOT NOW: PostHog hears it was dismissed; the answers so far are not sent.
func dismiss() -> void:
	if _done:
		return
	_done = true
	Analytics.survey_dismissed(survey)
	finished.emit("dismissed")
	_close()


## Don't ask me again: dismissed, and the questions stop (Settings can turn them back on).
func never_ask() -> void:
	if _done:
		return
	_done = true
	Analytics.survey_dismissed(survey)
	Analytics.set_surveys(false, "card")
	finished.emit("opted_out")
	_close()


func _thanks() -> void:
	# freed at once: the page's own nodes never wait as orphans (no handler of theirs is running: NEXT is not on the page)
	for c in _q_box.get_children():
		_q_box.remove_child(c)
		c.free()
	var t := W.text("THANK YOU, PARTNER", W.slab(), 52, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 56.0, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_q_box.add_child(t)
	next_btn.visible = false
	not_now_btn.visible = false
	never_btn.visible = false
	_progress.text = ""
	Audio.play("ui_tap")
	var tw := create_tween()
	tw.tween_interval(THANKS_HOLD)
	tw.tween_callback(_close)


func _close() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)


func is_done() -> bool:
	return _done
