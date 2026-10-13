## Stage clear (Wanted screen 15), the game's biggest decision, shown as two roads: Extract (safe, the run ends, this
## run's gold banked, the number big in brass) and Continue (the next stage: how many creatures come at once, how much
## tougher; pass 47: no slot lines, the six weapon and six line slots are open from the start). After the last stage the second road is Stay: hell keeps coming, tougher every wave, and
## the next boss opens another portal. Tap a card. (Pass 43: the ×1.25 extract bonus and the "×1.0 gold" line are gone.)
## Pass 48 (Garry: a way out of the dialog): NOT YET under the two roads, and Esc or the back gesture, close it with no
## decision; the run goes on and the portal waits for the hero to step out and walk back in.
class_name PortalDialog
extends WModal

signal decided(extract: bool)
## The hero is not ready to choose (NOT YET, Esc, the back gesture): the dialog closes with no decision, the run goes
## on (Game unpauses), and the portal arms again once he steps out.
signal declined

## The footer: what NOT YET means.
const FOOT := "Not ready? Step out, and walk back in when you are."

var _tag: PanelContainer
var _extract: WTap
var _continue: WTap
var _cards: VBoxContainer
var _foot: WText
var _gold_to: WText
var _cont_title: WText
var _cont_tag: WText
var _cont_lines: VBoxContainer
var _not_yet: WButton


func _ready() -> void:
	build_dim(W.DIM)
	build_header("", "STAGE 1 CLEAR", "05:00 · 0 kills · Lv 1. Head home, or push on.", 108)
	header.offset_top = 100 + W.safe_top()
	# the BOSS DOWN tag over the title
	_tag = PanelContainer.new()
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tag.add_theme_stylebox_override("panel", W.box(W.INK, 0, 0).pad(30, 8, 30, 8))
	_tag.add_child(W.text("BOSS DOWN", W.slab(W.em(30, 0.08)), 30, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 0.0))
	header.add_child(_tag)
	header.move_child(_tag, 0)
	header.add_theme_constant_override("separation", 8)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 40)
	_cards.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cards.offset_left = 48
	_cards.offset_right = -48
	_cards.offset_top = 500 + W.safe_top()
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	_extract = _road("Extract", "Safe · run ends", W.SAGE, "strongbox", "strongbox\nart")
	_extract.pressed.connect(func(): visible = false; decided.emit(true))
	var ev: VBoxContainer = _extract.get_meta("body")
	ev.add_child(W.serif_text("This run's gold, banked", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 14)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(56.0, W.BRASS, 4.0)
	g.add_child(coin)
	_gold_to = W.slab_text("0", 96, W.BRASS_DARK, HORIZONTAL_ALIGNMENT_LEFT, 96.0)
	g.add_child(_gold_to)
	ev.add_child(g)
	_continue = _road("Continue", "Stage 2 · harder", W.ROCK, "portal", "portal\nart")
	_continue.pressed.connect(func(): visible = false; decided.emit(false))
	_cont_title = _continue.get_meta("title")
	_cont_tag = _continue.get_meta("tag")
	_cont_lines = _continue.get_meta("body")
	# NOT YET (pass 48), centred under the roads
	_not_yet = WButton.make(["NOT YET"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	_not_yet.name = "NotYet"
	_not_yet.custom_minimum_size.x = 420
	_not_yet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_not_yet.pressed.connect(decline)
	_cards.add_child(_not_yet)
	_foot = W.serif_text(FOOT, 28, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_foot.offset_bottom = -80
	_foot.offset_top = -80 - 34
	add_child(_foot)


## Not now: the dialog closes with no decision (`declined`; Game unpauses and the portal re-arms once the hero is out).
func decline() -> void:
	if not visible:
		return
	visible = false
	declined.emit()


## The back gesture does what NOT YET does while the dialog is up (in a run it otherwise does nothing).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		decline()


## Esc on a PC, the same.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE) or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		decline()


## One road: a paper card (6 px ink, a 12 px shadow), its name in 64 px slab with a tracked tag on the right, the art
## (a placeholder until painted) and a column of what it means.
func _road(t: String, tag: String, tag_color: Color, slot: String, art_label: String) -> WTap:
	var c := WTap.new()
	var b := W.box(W.PAPER, 6, 12).pad(46, 42, 46, 42)
	c.box = b
	var down := b.pressed()
	down.inner = 6
	c.box_down = down
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tt := W.slab_text(t, 64, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 64.0)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	var tg := W.label(tag, 20, tag_color)
	tg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tg)
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := WPlaceholder.make(slot, art_label, Vector2(188, 188))
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.set_meta("small", true)
	row.add_child(art)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(body)
	v.add_child(row)
	c.set_meta("title", tt)
	c.set_meta("tag", tg)
	c.set_meta("body", body)
	_cards.add_child(c)
	return c


## A line on the Continue card: a number in slab (sage good, rock hard) and what it means in Bitter.
func _fact(n: String, col: Color, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nt := W.slab_text(n, 34, col, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	nt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nt)
	var tt := W.serif_text(text, 28, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tt)
	return h


func open(stage_cleared: int, can_continue: bool, final_stage: bool) -> void:
	var gold := Run.run_gold
	W.sfx_first(["ui_stage_clear"])   # pass 64: the stage-clear jingle
	header.set_title("STAGE %d CLEAR" % stage_cleared)
	header.set_line("%s · %s kills · %s. Head home, or push on." % [W.mmss(Run.elapsed), W.num(Run.kills), W.lv(Run.level)])
	_gold_to.text = W.num(gold)
	for c in _cont_lines.get_children():
		c.queue_free()
	_continue.visible = can_continue
	if can_continue:
		var tl = Run.map.timeline if Run.map else null
		var next := stage_cleared   # the stage index the player walks into
		if final_stage:
			# after the last boss: stay and fight, tougher every wave, until the next boss opens another portal
			_cont_title.text = "Stay"
			_cont_tag.text = "HELL KEEPS COMING"
			if tl:
				var per := ("%.2f" % float(tl.endless_wave_mult)).trim_suffix("0")
				_cont_lines.add_child(_fact("×%s" % per, W.ROCK, "tougher every wave (a minute), stacking"))
				_cont_lines.add_child(_fact(W.num(tl.cap_at(tl.stage_length * next, next)), W.ROCK, "creatures at once, plus the hell crowd"))
			_cont_lines.add_child(_fact("+1", W.SAGE, "portal with every boss, to extract later"))
		else:
			_cont_title.text = "Continue"
			_cont_tag.text = ("STAGE %d · HELL" if stage_cleared + 1 >= 3 else "STAGE %d · HARDER") % (stage_cleared + 1)
			if tl:
				var at: int = tl.cap_at(tl.stage_length * next, next)
				var tough := ("%.1f" % float(tl.stage_mult(next))).trim_suffix(".0")
				_cont_lines.add_child(_fact(W.num(at), W.ROCK, ("creatures at once, each ×%s as tough" % tough) if next < tl.stage_mults.size() else "creatures at once"))
				if tl.hell_cap_at(next) > 0.0:
					_cont_lines.add_child(_fact("+%d%%" % int(round(tl.hell_cap_at(next) * 100.0)), W.ROCK, "more bodies: the hell crowd"))
		# pass 70: a death banks the purse too, so the gold is not the stake any more
		_cont_lines.add_child(W.serif_text("The %s gold comes home either way." % W.num(gold), 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	modulate.a = 1.0
	enter()
