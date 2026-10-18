## Upgrade (Wanted 03/03b; "The Mirror" until pass 44, when Garry asked for a name that says what it is for): the meta
## between runs. Eight talents, each with two mutually exclusive forms and six ranks (three until pass 46, Garry: "double
## the number of possible Upgrades for each path"). The board shows each talent's name, its rank notches, the live form
## and what it does, and the next rank's price on a paper tag (brass is the BUY button's alone, pass 46); a tap opens the
## talent's sheet over a sepia dim: the two forms side by side (the live one in ink; switching is free and keeps the
## ranks), what the ranks give now, and the next rank for gold. "Take it all back" asks in a pop-up, then empties the
## board and returns half the coins (Save.REFUND_FRAC). The talents hold for every hero, so the mirror shows none of
## them: something looks back out of the dark glass, two brass eyes (art/ui/wanted/mirror.png replaces the drawn mirror
## when it exists).
## Pass 61 (Garry: "The choices in the Mirror should be shown as little icons. Maybe as a summary also. Each of those
## icons should be distinctly different from their counterpart. So say Grit will have a progress bar filled up with 2
## types of distinct icons representing choices that Player made. Make the UI elements taller to make enough space for
## those icons to make sense as well as the empty bars"): every form has its own painted icon (TalentDef.form_icon); a
## tile's notches became a rank bar of six slots (a bought rank the live form's icon on a raised paper plate, an unbought
## one the HUD's dashed empty slot), a talent with no rank shows both forms' icons small beside its name, the tiles grew
## to hold the bar, the sheet shows the same bar large and the two forms with their icons, and a summary strip over the
## mirror lists every talent with ranks as its live form's icon and "x<rank>".
extends ScreenBase

const MIRROR_ART := "res://art/ui/wanted/mirror.png"
## The rank bar's slots (pass 61; the 28 x 20 notches beside the name before): on a tile six 60 px slots 8 apart (400
## px of the tile's 422), the icon 49 px inside (WPlate.icon_frac), so it reads at the 44 px it was painted for; on the
## sheet six 100 px slots 12 apart. A bought rank's plate is raised (a hard ink shadow) and paper; an unbought one aged
## with the dashed line inside.
const TILE_SLOT := 60.0
const TILE_SLOT_GAP := 8.0
const SHEET_SLOT := 100.0
const SHEET_SLOT_GAP := 12.0
const SLOT_SHADOW := 3
## The two forms' icons beside a talent's name while it has no rank (the choice shows before the first buy), "or" between.
const NAME_ICON := 46.0
## The forms' icons in the sheet's choice, on a paper plate so they read on the chosen (ink) half too.
const CHOICE_ICON := 76.0
## The summary over the mirror: one chip per talent with ranks, its live form's icon on a plate and "x<rank>".
const CHIP_PX := 60.0

var _gold: PanelContainer
var _grid: GridContainer
var _refund: WTap
var _refund_text: WText
var _sheet_root: Control
var _sheet_def: TalentDef
## The summary strip (pass 61) and the flow its chips (or the empty hint) sit in.
var _summary: PanelContainer
var _summary_flow: HFlowContainer


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
	content.add_child(_make_summary())
	var over := Control.new()
	over.custom_minimum_size.y = 24
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(over)
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
	# pass 88 (lane MIRROR): Spite's old ranks paid back, said once
	_show_board_note()


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
	# out of the grid at once (a queued tile still counts and still lays out until the frame ends)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for def: TalentDef in Registry.talents_list():
		_grid.add_child(_card(def))
	_fill_summary()
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


## One talent on the board: its name (both forms' icons beside it while it has no rank), its rank bar, the live form
## and what it does, the next rank's price.
func _card(def: TalentDef) -> WTap:
	var locked := not Registry.is_unlocked("talent", def.id)
	var picks := Save.talent_picks(def.id)
	var rank := picks.size()
	var c := WTap.new()
	c.name = "Talent_" + def.id
	var b := W.box(W.PAPER, 5, 6).pad(29, 27, 29, 27)
	c.box = b
	c.box_down = b.pressed()
	c.locked_alpha = 0.55
	c.locked = locked
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.custom_minimum_size.y = NAME_ICON
	var n := W.slab_text(def.display_name, 44, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 44.0)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(n)
	# both forms beside the name while a rank is left to buy (pass 63: every rank is its own choice)
	if rank < def.max_rank():
		head.add_child(_form_pair(def))
	v.add_child(head)
	v.add_child(rank_bar(def, picks, TILE_SLOT, TILE_SLOT_GAP))
	var line := "Each rank: %s or %s" % [def.form_name(0), def.form_name(1)]
	if rank > 0:
		line = TextGen.describe_effects(held_effects(def))
	v.add_child(W.serif_text(line, 26, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
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


## The rank bar (pass 61): `def.max_rank()` slots `px` square, `gap` apart; the bought ones first, each the icon of the
## form that rank was bought in (pass 63: `picks`, Save.talent_picks, so one bar can hold both icons) on a raised paper
## plate (its initial in slab when the icon is missing), the rest dashed empties. The slots are named Rank1.. and carry
## their state in the meta "bought" (and the plate its "form").
static func rank_bar(def: TalentDef, picks: Array, px: float, gap: float) -> HBoxContainer:
	var rank := picks.size()
	var bar := HBoxContainer.new()
	bar.name = "RankBar"
	bar.add_theme_constant_override("separation", int(gap))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in def.max_rank():
		var slot: WPlate
		if k < rank:
			slot = form_plate(def, int(picks[k]), px)
			slot.shadow = SLOT_SHADOW
		else:
			slot = WPlate.slot(px)
		slot.name = "Rank%d" % (k + 1)
		slot.set_meta("bought", k < rank)
		bar.add_child(slot)
	return bar


## A form's icon on a paper plate `px` square (the bar's bought slot, the choice's, the summary's chip, the pair beside a
## name), or the form's initial when its icon is missing.
static func form_plate(def: TalentDef, form: int, px: float) -> WPlate:
	var p := WPlate.new()
	p.side = px
	p.fill = W.PAPER
	p.radius = 10 if px < 140 else 12
	p.border = 3 if px < 56 else 4
	p.tex = def.form_icon(form)
	if p.tex == null:
		p.glyph = def.form_name(form).left(1)
	p.set_meta("form", form)
	return p


## Both forms' icons small beside a name with no rank yet: "[icon] or [icon]".
func _form_pair(def: TalentDef) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "FormIcons"
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(form_plate(def, 0, NAME_ICON))
	var o := W.serif_text("or", 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	o.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(o)
	h.add_child(form_plate(def, 1, NAME_ICON))
	return h


# --- the summary -------------------------------------------------------------------------------------------------------

## The summary strip over the mirror (pass 61, Garry: "Maybe as a summary also"): a paper strip, the build at a glance.
func _make_summary() -> PanelContainer:
	_summary = PanelContainer.new()
	_summary.name = "Summary"
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 6).pad(29, 20, 29, 22))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(W.slab_text("YOUR UPGRADES", 28, W.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 28.0))
	_summary_flow = HFlowContainer.new()
	_summary_flow.name = "Chips"
	_summary_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_summary_flow.add_theme_constant_override("h_separation", 26)
	_summary_flow.add_theme_constant_override("v_separation", 14)
	_summary_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_summary_flow)
	_summary.add_child(v)
	return _summary


## The chips again: per talent with ranks, in board order, one chip a form it holds: the form's icon and "x<ranks of it>"
## (pass 63: Grit with two Padding ranks and one Plate rank is two chips); nothing bought, a line that says where the
## icons will come from.
func _fill_summary() -> void:
	if _summary_flow == null:
		return
	for c in _summary_flow.get_children():
		_summary_flow.remove_child(c)
		c.queue_free()
	for def: TalentDef in summary_talents():
		for form in range(2):
			var n := Save.talent_count(def.id, form)
			if n <= 0:
				continue
			var chip := HBoxContainer.new()
			chip.name = "Chip_%s_%d" % [def.id, form]
			chip.add_theme_constant_override("separation", 8)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var plate := form_plate(def, form, CHIP_PX)
			plate.shadow = SLOT_SHADOW
			chip.add_child(plate)
			var t := W.slab_text("x%d" % n, 32, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 32.0)
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.add_child(t)
			_summary_flow.add_child(chip)
	if _summary_flow.get_child_count() == 0:
		var hint := W.serif_text("Nothing bought yet: every rank you buy shows here.", 26, W.INK_SOFT, 400, true,
			HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
		hint.name = "Hint"
		_summary_flow.add_child(hint)


## What a talent's ranks give together (pass 63): each form's ranks summed, the first form's effects first.
static func held_effects(def: TalentDef) -> Array:
	var out: Array = []
	for form in range(2):
		var n := Save.talent_count(def.id, form)
		if n > 0:
			out.append_array(def.summed_effects(form, n))
	return out


## The talents the summary lists: those with at least one rank, in board order.
static func summary_talents() -> Array:
	var out: Array = []
	for def: TalentDef in Registry.talents_list():
		if Save.talent_rank(def.id) > 0:
			out.append(def)
	return out


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
	var picks := Save.talent_picks(def.id)
	var rank := picks.size()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 26)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(v)
	var n := W.slab_text(def.display_name, 84, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 84.0)
	v.add_child(n)
	v.add_child(rank_bar(def, picks, SHEET_SLOT, SHEET_SLOT_GAP))
	v.add_child(W.serif_text(def.flavour, 30, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var now := "No ranks yet"
	if rank > 0:
		# the ranks summed by form (pass 45, pass 63), out of how many
		now = "Rank %d of %d owned · %s" % [rank, def.max_rank(), TextGen.describe_effects(held_effects(def))]
	# wrapping: a wrapped line's minimum width is nothing, so a long one breaks instead of widening the sheet
	var status := W.serif_text(now, 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	status.name = "Status"
	v.add_child(status)
	var cost := def.cost_of_rank(rank)
	if rank >= def.max_rank() or cost < 0:
		var full := WButton.make(["FULL"], 48, WButton.PRIMARY, 5, 8, 24.0, 24.0)
		full.name = "Buy"
		full.locked = true
		full.pressed.connect(func(): Audio.play("ui_locked"))
		v.add_child(full)
	else:
		# pass 63 (Garry: "Player makes a choice, Padding or Plate and that is added to the upgrades list with the icon
		# that stands for it"): the next rank is bought in one form or the other, and it keeps that form
		var note := W.serif_text("Rank %d: choose one. It stays; Take it all back is the only way to choose again." % (rank + 1),
			26, W.INK, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
		note.name = "ChoiceNote"
		v.add_child(note)
		for form in range(2):
			v.add_child(_form_offer(def, form, cost, sheet))
	var close := WTap.new()
	var clear := W.box(Color(0, 0, 0, 0), 0, 0).pad(0, 4, 0, 4)
	close.box = clear
	close.box_down = clear
	close.name = "Close"
	close.add_child(W.slab_text("Close", 30, W.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 0.0))
	close.pressed.connect(func(): _close(true))
	v.add_child(close)


## One form's offer on the sheet (pass 63): its icon, name and what a rank gives, and its own buy button for the next
## rank ("Buy0" / "Buy1"); locked when the purse is short.
func _form_offer(def: TalentDef, form: int, cost: int, sheet: PanelContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Offer%d" % form
	box.add_theme_constant_override("separation", 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := form_plate(def, form, CHOICE_ICON)
	plate.shadow = SLOT_SHADOW
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(plate)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 4)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(W.slab_text(def.form_name(form), 40, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 40.0))
	var held := Save.talent_count(def.id, form)
	var t := _short(def.form_text(form)) + (" · %d owned" % held if held > 0 else "")
	words.add_child(W.serif_text(t, 26, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	row.add_child(words)
	box.add_child(row)
	var buy := WButton.make([def.form_name(form).to_upper(), {"coin": 40, "fill": W.PAPER}, [W.num(cost), null, 40]], 44, WButton.PRIMARY, 5, 8, 24.0, 24.0)
	buy.name = "Buy%d" % form
	buy.locked = Save.gold() < cost
	buy.pressed.connect(func():
		if buy.locked:
			Audio.play("ui_locked")
			return
		if Save.buy_talent(def, form):
			Audio.play("ui_buy")
			_refresh()
			_fill_sheet.call_deferred(sheet))
	box.add_child(buy)
	return box


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


# ---------------------------------------------------------------- pass 88 (lane MIRROR): the Stakes' refund, said once

## The toasts over the mirror while the board's note shows (null without one).
var _note_toasts: WToasts
## Where they sit: over the mirror's glass, under the summary strip.
const NOTE_TOP := 450.0


## Save.board_note's "stakes_refund" (Save._migrate_stakes: an older save's Spite ranks, Thorns and Thirst, paid back in
## full) as two toasts the first time the board opens after it, then forgotten.
func _show_board_note() -> void:
	var n := Save.board_note()
	if str(n.get("kind", "")) != "stakes_refund":
		return
	_note_toasts = WToasts.new()
	_note_toasts.name = "NoteToasts"
	_note_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_note_toasts.offset_top = NOTE_TOP
	_note_toasts.offset_bottom = NOTE_TOP + 200.0
	add_child(_note_toasts)
	for t in note_words(n):
		_note_toasts.push(t)
	Save.clear_board_note()


## The note's toasts: ["SPITE IS NOW STAKES", "+2,900 GOLD BACK FOR 3 RANKS"].
static func note_words(n: Dictionary) -> Array:
	var ranks := int(n.get("ranks", 0))
	return ["SPITE IS NOW STAKES", "+%s GOLD BACK FOR %d RANK%s" % [W.num(int(n.get("gold", 0))), ranks, "" if ranks == 1 else "S"]]


func _process(delta: float) -> void:
	super(delta)
	if _note_toasts:
		_note_toasts.tick(delta)
