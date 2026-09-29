## Stage clear (Wanted screen 15), the game's biggest decision, shown as two roads: Extract (safe, the run ends, this
## run's gold banked at ×1.25, the number struck and the new one big in brass) and Continue (the next stage: the slots it
## opens, how many creatures come at once, and that the gold stays at ×1.0 until you extract or die). Tap a card.
class_name PortalDialog
extends WModal

signal decided(extract: bool)

var _tag: PanelContainer
var _extract: WTap
var _continue: WTap
var _cards: VBoxContainer
var _foot: WText
var _gold_from: WText
var _gold_to: WText
var _cont_title: WText
var _cont_tag: WText
var _cont_lines: VBoxContainer
var _locked_note: WText


func _ready() -> void:
	build_dim(W.DIM)
	build_header("", "STAGE 1 CLEAR", "05:00 · 0 kills · Lv 1. Bank it, or push your luck.", 108)
	header.offset_top = 100
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
	_cards.offset_top = 500
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	_extract = _road("Extract", "Safe · run ends", W.SAGE, "strongbox", "strongbox\nart")
	_extract.pressed.connect(func(): visible = false; decided.emit(true))
	var ev: VBoxContainer = _extract.get_meta("body")
	ev.add_child(W.serif_text("This run's gold, at ×1.25", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 14)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_from = W.slab_text("0", 40, W.INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_gold_from.strike = true
	_gold_from.size_flags_vertical = Control.SIZE_SHRINK_END
	g.add_child(_gold_from)
	var arrow := W.serif_text("→", 40, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_END
	g.add_child(arrow)
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
	_locked_note = W.serif_text("", 28, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true)
	_cards.add_child(_locked_note)
	_foot = W.serif_text("Tap a card. The portal stays open as long as you like.", 28, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_foot.offset_bottom = -80
	_foot.offset_top = -80 - 34
	add_child(_foot)


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
	var banked := int(round(gold * 1.25))
	header.set_title("STAGE %d CLEAR" % stage_cleared)
	header.set_line("%s · %s kills · %s. Bank it, or push your luck." % [W.mmss(Run.elapsed), W.num(Run.kills), W.lv(Run.level)])
	_gold_from.text = W.num(gold)
	_gold_to.text = W.num(banked)
	for c in _cont_lines.get_children():
		c.queue_free()
	_continue.visible = can_continue
	if can_continue:
		var tl = Run.map.timeline if Run.map else null
		var next := stage_cleared   # the stage index the player walks into
		if final_stage:
			_cont_title.text = "Continue"
			_cont_tag.text = "ENDLESS · HARDER EVERY MINUTE"
		else:
			_cont_title.text = "Continue"
			_cont_tag.text = "STAGE %d · HARDER" % (stage_cleared + 1)
		if tl:
			var slots: int = tl.weapon_cap_at(next) - tl.weapon_cap_at(next - 1)
			if slots > 0:
				_cont_lines.add_child(_fact("+%d" % slots, W.SAGE, "weapon slot%s open" % ("" if slots == 1 else "s")))
			var at: int = tl.cap_at(tl.stage_length * next, next)
			var tough := ("%.1f" % float(tl.stage_mult(next))).trim_suffix(".0")
			_cont_lines.add_child(_fact(W.num(at), W.ROCK, ("creatures at once, each ×%s as tough" % tough) if next < tl.stage_mults.size() else "creatures at once"))
		_cont_lines.add_child(_fact("×1.0", W.SAGE, "gold, until you extract or die"))
		_cont_lines.add_child(W.serif_text("Die out there and the %s stays in the sand." % W.num(gold), 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
		_locked_note.visible = false
	else:
		_locked_note.text = "Endless is locked. Kill the stage 3 boss to open it."
		_locked_note.visible = true
	modulate.a = 1.0
	enter()
