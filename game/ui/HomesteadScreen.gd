## Upgrade (Wanted 03/03b; "The Mirror" until pass 44, when Garry asked for a name that says what it is for): the meta
## between runs. Eight talents, each with two mutually exclusive forms and six ranks (three until pass 46, Garry: "double
## the number of possible Upgrades for each path"). The board shows each talent's name, its rank notches, the live form
## and what it does, and the next rank's price on a paper tag (brass is the BUY button's alone, pass 46); a tap opens the
## talent's sheet over a sepia dim: the two forms side by side (the live one in ink; switching is free and keeps the
## ranks), what the ranks give now, and the next rank for gold. "Take it all back" asks in a pop-up, then empties the
## board and returns half the coins (Save.REFUND_FRAC). The talents hold for every hero, so the mirror shows none of
## them: something looks back out of the dark glass, two brass eyes (art/ui/wanted/mirror.png replaces the drawn mirror
## when it exists).
extends ScreenBase

const MIRROR_ART := "res://art/ui/wanted/mirror.png"
## A rank notch on a board tile and on the sheet, sized so six sit beside the name (42 and 68 px fitted three).
const TILE_NOTCH := Vector2(28, 20)
const TILE_NOTCH_GAP := 5.0
const SHEET_NOTCH := Vector2(52, 30)
const SHEET_NOTCH_GAP := 7.0

var _gold: PanelContainer
var _grid: GridContainer
var _refund: WTap
var _refund_text: WText
var _sheet_root: Control
var _sheet_def: TalentDef


func header_right() -> Control:
	_gold = WMenuHeader.gold_plate(Save.gold(), 44, 40.0, 5, 4)
	return _gold


func board_top() -> float:
	return 190.0


func board_bottom() -> float:
	# the refund link (31 px, 60 off the bottom) and a gap
	return 60.0 + 32.0 + 20.0


func build() -> void:
	set_title("Upgrade")
	content.add_theme_constant_override("separation", 0)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mirror := _mirror()
	mirror.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(mirror)
	var line := W.serif_text("Something looks back. It wants gold.", 26, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	stack.add_child(line)
	content.add_child(stack)
	var gap := Control.new()
	gap.custom_minimum_size.y = 1
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(gap)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 24)
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_grid)
	# the footer link, under the board
	_refund = WTap.new()
	var clear := W.box(Color(0, 0, 0, 0), 0, 0).pad(20, 4, 20, 4)
	_refund.box = clear
	_refund.box_down = clear
	_refund_text = W.text("", W.serif(600), 26, W.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_refund_text.underline = true
	_refund.add_child(_refund_text)
	_refund.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_refund.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_refund.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_refund.offset_bottom = -60 + 4
	_refund.pressed.connect(_take_back)
	add_child(_refund)
	_refresh()


## The mirror: a brass frame in an ink ring round dark glass, and whatever lives in it looking back.
func _mirror() -> Control:
	var m := Control.new()
	m.custom_minimum_size = Vector2(328, 328)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MIRROR_ART):
		var art := TextureRect.new()
		art.texture = load(MIRROR_ART)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(art)
		return m
	m.draw.connect(func():
		var c := Vector2(164, 164)
		m.draw_circle(c, 170.0, W.INK, true, -1.0, true)
		m.draw_circle(c, 164.0, W.BRASS, true, -1.0, true))
	var glass := Control.new()
	glass.position = Vector2(14, 14)
	glass.size = Vector2(300, 300)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.draw.connect(func(): _draw_glass(glass))
	m.add_child(glass)
	var ring := Control.new()
	ring.position = Vector2(14, 14)
	ring.size = Vector2(300, 300)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func(): ring.draw_arc(Vector2(150, 150), 147.0, 0.0, TAU, 96, W.INK, 6.0, true))
	m.add_child(ring)
	return m


## Dark glass: ink soft at 40 % down, ink from 70 % of the way to the far corner (the mock's radial gradient), as a fan.
func _draw_glass(ci: Control) -> void:
	var c := Vector2(150, 150)
	var focus := Vector2(150, 120)
	var reach := Vector2(0, 300).distance_to(focus) * 0.7
	var pts := PackedVector2Array([focus])
	var cols := PackedColorArray([W.INK_SOFT])
	for k in 97:
		var p := c + Vector2.from_angle(TAU * k / 96.0) * 150.0
		pts.append(p)
		cols.append(W.INK_SOFT.lerp(W.INK, clampf(p.distance_to(focus) / reach, 0.0, 1.0)))
	var idx := PackedInt32Array()
	for k in 96:
		idx.append_array([0, k + 1, k + 2])
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)
	# the glass catches the light along its upper left
	ci.draw_arc(c, 124.0, deg_to_rad(198.0), deg_to_rad(252.0), 24, Color(W.PAPER, 0.16), 9.0, true)
	ci.draw_arc(c, 108.0, deg_to_rad(212.0), deg_to_rad(232.0), 12, Color(W.PAPER, 0.10), 5.0, true)
	# something looks back: two brass eyes low in the dark, each in a faint glow, with a thin slit of a pupil
	for side in [-1.0, 1.0]:
		var e := Vector2(150.0 + side * 36.0, 158.0)
		for k in 7:
			ci.draw_circle(e, 30.0 - k * 3.5, Color(W.BRASS, 0.045), true, -1.0, true)
		var lid := PackedVector2Array()
		for a in 28:
			var t := TAU * a / 28.0
			# an almond, its outer end tipped up
			lid.append(e + Vector2(cos(t) * 15.0, sin(t) * 6.0 - cos(t) * side * 2.5))
		ci.draw_colored_polygon(lid, W.BRASS)
		ci.draw_colored_polygon(PackedVector2Array([e + Vector2(0, -5), e + Vector2(2.2, 0), e + Vector2(0, 5), e + Vector2(-2.2, 0)]), W.INK)


func _refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for def: TalentDef in Registry.talents_list():
		_grid.add_child(_card(def))
	var amount := _amount_of(_gold)
	if amount:
		amount.text = W.num(Save.gold())
	var spent := Save.talent_spent()
	# half comes back (pass 44): the refund is a loss, not a free respec
	_refund_text.text = ("Take it all back · %s of the %s spent comes back" % [W.num(Save.talent_refund()), W.num(spent)]) if spent > 0 else "Nothing to take back"
	_refund.modulate.a = 1.0 if spent > 0 else 0.45


func _amount_of(p: Control) -> WText:
	for n in p.find_children("Amount", "", true, false):
		return n as WText
	return null


## One talent on the board: its name and notches, the live form and what it does, the next rank's price.
func _card(def: TalentDef) -> WTap:
	var locked := not Registry.is_unlocked("talent", def.id)
	var form := Save.talent_form(def.id)
	var rank := Save.talent_rank(def.id)
	var c := WTap.new()
	var b := W.box(W.PAPER, 5, 6).pad(29, 27, 29, 27)
	c.box = b
	c.box_down = b.pressed()
	c.locked_alpha = 0.55
	c.locked = locked
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := W.slab_text(def.display_name, 44, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 44.0)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(n)
	var marks := WMarks.new()
	marks.notch = TILE_NOTCH
	marks.gap = TILE_NOTCH_GAP
	marks.setup("notches", def.max_rank(), rank)
	marks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(marks)
	v.add_child(head)
	v.add_child(W.serif_text("%s · %s" % [def.form_name(form), _short(def.form_text(form))], 26, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var tag: Control
	if locked:
		var q := Registry.quest_for("talent", def.id)
		tag = _tag(TextGen.quest_text(q) if q else "Locked", W.PAPER, 0)
	else:
		var cost := def.cost_of_rank(rank)
		if rank >= def.max_rank() or cost < 0:
			tag = _tag("Full", W.AGED, 0)
		else:
			tag = _price(cost, Save.gold() >= cost)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(tag)
	c.pressed.connect(func():
		if locked:
			Audio.play("ui_locked")
			return
		_open(def))
	return c


## "+10% max HP a rank." -> "+10% max HP a rank" (the board's line has no full stop).
func _short(t: String) -> String:
	return t.strip_edges().trim_suffix(".")


## The next rank's price: the coin and the number in ink on a paper tag; aged, coin and all, when the purse is short
## (pass 46: the tag was brass, and brass is kept for BUY).
func _price(cost: int, can: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Price"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER if can else W.AGED, 4, 4 if can else 0).pad(22, 12, 22, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(32.0, W.BRASS if can else W.AGED, 3.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(coin)
	var t := W.slab_text(W.num(cost), 30, W.INK if can else W.INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	h.add_child(t)
	p.add_child(h)
	return p


## A flat tag in slab ("Full", the unlock quest).
func _tag(t: String, fill: Color, shadow: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(fill, 4, shadow).pad(22, 12, 22, 12))
	p.add_child(W.slab_text(t, 26, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	return p


# --- the sheet ---------------------------------------------------------------------------------------------------------

## A talent opened over a sepia dim: its two forms, what the ranks give, the next rank for gold, Close.
func _open(def: TalentDef) -> void:
	_close(false)
	_sheet_def = def
	_sheet_root = Control.new()
	_sheet_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sheet_root)
	var dim := WTap.new()
	var dim_box := W.box(Color8(48, 30, 14, 140), 0, 0)
	dim.box = dim_box
	dim.box_down = dim_box
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.pressed.connect(func(): _close(true))
	# above the sheet: where a finger closes it (and where tools/touch_audit.gd taps it)
	dim.set_meta("tap_at", Vector2(540, 250))
	_sheet_root.add_child(dim)
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(50, 46, 50, 46))
	sheet.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sheet.offset_left = 60
	sheet.offset_right = -60
	sheet.offset_top = 420
	_sheet_root.add_child(sheet)
	_fill_sheet(sheet)
	dim.modulate.a = 0.0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	sheet.offset_top = 480
	sheet.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sheet, "offset_top", 420.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sheet, "modulate:a", 1.0, 0.2)


func _fill_sheet(sheet: PanelContainer) -> void:
	for c in sheet.get_children():
		c.queue_free()
	var def := _sheet_def
	var form := Save.talent_form(def.id)
	var rank := Save.talent_rank(def.id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 26)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := W.slab_text(def.display_name, 84, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 84.0)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(n)
	var marks := WMarks.new()
	marks.notch = SHEET_NOTCH
	marks.gap = SHEET_NOTCH_GAP
	marks.notch_border = 4
	marks.setup("notches", def.max_rank(), rank)
	marks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(marks)
	v.add_child(head)
	v.add_child(W.serif_text(def.flavour, 30, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var choice := WChoice.make([[def.form_name(0), _short(def.form_text(0))], [def.form_name(1), _short(def.form_text(1))]],
		form, 40, 26, 22.0, HORIZONTAL_ALIGNMENT_LEFT, 6)
	choice.chosen.connect(func(i: int):
		if i != Save.talent_form(def.id):
			Save.set_talent_form(def.id, i)
			_refresh()
			_fill_sheet.call_deferred(sheet))
	v.add_child(choice)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var now := "No ranks yet"
	if rank > 0:
		# the ranks summed (pass 45): effects_for repeats the form's effect a rank, and three "+10% max HP" pushed the
		# sheet off the right edge at FULL; out of how many (pass 46: six now)
		now = "Rank %d of %d owned · %s" % [rank, def.max_rank(), TextGen.describe_effects(def.summed_effects(form, rank))]
	# wrapping: a wrapped line's minimum width is nothing, so a long one breaks instead of widening the sheet
	var left := W.serif_text(now, 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(left)
	var free := W.serif_text("Switching form is free", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	free.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	status.add_child(free)
	v.add_child(status)
	var cost := def.cost_of_rank(rank)
	var buy: WButton
	if rank >= def.max_rank() or cost < 0:
		buy = WButton.make(["FULL"], 48, WButton.PRIMARY, 5, 8, 24.0, 24.0)
		buy.locked = true
	else:
		buy = WButton.make(["RANK %d" % (rank + 1), {"coin": 40, "fill": W.PAPER}, [W.num(cost), null, 40]], 48, WButton.PRIMARY, 5, 8, 24.0, 24.0)
		buy.locked = Save.gold() < cost
	buy.name = "Buy"
	buy.pressed.connect(func():
		if buy.locked:
			Audio.play("ui_locked")
			return
		if Save.buy_talent(def):
			Audio.play("ui_buy")
			_refresh()
			_fill_sheet.call_deferred(sheet))
	v.add_child(buy)
	var close := WTap.new()
	var clear := W.box(Color(0, 0, 0, 0), 0, 0).pad(0, 4, 0, 4)
	close.box = clear
	close.box_down = clear
	close.name = "Close"
	close.add_child(W.slab_text("Close", 30, W.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 0.0))
	close.pressed.connect(func(): _close(true))
	v.add_child(close)


func _close(animate: bool) -> void:
	if _sheet_root == null:
		return
	var root := _sheet_root
	_sheet_root = null
	_sheet_def = null
	if not animate:
		root.queue_free()
		return
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.15)
	tw.tween_callback(root.queue_free)


## The question before every rank goes (pass 45): what comes back and what does not, then the refund.
func _take_back() -> void:
	var spent := Save.talent_spent()
	if spent <= 0:
		Audio.play("ui_locked")
		return
	WConfirm.open(self, "Take it all back?",
		"Every rank on the board goes. %s of the %s gold spent comes back; the rest is gone." % [W.num(Save.talent_refund()), W.num(spent)],
		"Take it back", "Keep them", func():
			Save.talent_refund_all()
			Audio.play("ui_buy")
			_refresh())


## The back gesture (or Esc) closes an open talent first.
func on_back() -> void:
	if _sheet_root:
		_close(true)
		return
	go(TITLE)


## The board does not scroll under an open sheet.
func _input(event: InputEvent) -> void:
	if _sheet_root == null:
		super._input(event)
