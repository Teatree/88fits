## The travelling shop (Wanted screen 11): three items priced by how strong they are, bought with the run's gold. The
## price is the button; what the player already holds sits above the wares; a card they cannot afford is aged at 60 %
## with its price in paper ("· 8 short"). One purchase and the stall is spent; LEAVE spends it too.
## Pass 60 (Garry: "The shop in the gameplay thing is borked. The 'you hold' tray is messed up. The prices need to be
## rebalanced as well, should be that Player can afford like 2 items per Stage"): the body is one column under the header
## (the header already sits W.safe_top() lower, so a camera cutout moves everything down together), the YOU HOLD line on a
## row of its own over a flow of plates that wraps (76 px, 60 px once TRAY_SMALL_FROM items are held: two rows take a late
## build of 22), and the three cards under the tray's real height; the prices are half a stage's gold, by kind and rarity
## (price_of). One card a visit and one shop a run, as before. A stack that would run over LEAVE (the cards are taller
## than the mock's since pass 58's change rows, and a cutout pushes everything down) fits itself the way the level-up
## screen's does (_fit): the cards' gap squeezes, the plates step down to TRAY_PX_MIN, and the list shrinks last.
## Pass 123 (lane RUN_B), under Royale: the mocks 8_Shop_24_gold and
## 8_Shop_300_gold with Garry's notes ("Shop as the mock: green price · BUY, an unaffordable offer keeps its card with a
## grey button and the shortfall in red, YOU HOLD as framed icons"; "Header Text white, Leave button is an action that
## will make the shop not accessible anymore so let's make it red. Put gold amount at the top right where it always is"):
## the star line gold over THE SHOP in cream; the purse on the kit's black wallet at the top right (the menus' place,
## R.HEADER_RIGHT_Y down, R.HEADER_POS.x in; the header keeps no plate under it, so the body starts under the title);
## YOU HOLD as a label beside the kit's item frames (ROYALE_TRAY_PX, wrapping under the first frame); three slate offers
## (a ROYALE_PLATE frame, the kind with a passive item's rarity and the tag right after it, the name, the full text, the
## kit's price row on the card's foot: green "● price · BUY", short of gold the grey "● price" with "n short" in red
## before it, the card itself as it stands, no held glow while a finger is on it); LEAVE red and wider.
class_name StructureShop
extends WModal

signal closed(bought: bool)

## Half of what a stage pays (Elite purses, the boss, the coins, a loot cache): about 630 / 1,000 / 1,450 gold on Red
## Canyon in the v0.38-0.41 runs, so a player who keeps a stage's gold affords about two items and, before the first boss
## (about 250 gold), usually none. Stage 1 to 3; endless stays on the third.
const PRICE_BASE_BY_STAGE := [300, 500, 700]
## By kind: a weapon is the whole price, a line (a levelled stat) a little less, a passive item (one effect, no slot) less
## again; a perk counts as a passive item (one pick, no levels).
const KIND_MULT := {"weapon": 1.0, "evolution": 1.0, "line": 0.85, "passive": 0.7, "perk": 0.7}
const RARITY_MULT := {"common": 0.8, "uncommon": 0.9, "rare": 1.0, "epic": 1.2, "legendary": 1.4}
## An upgrade costs more for every level already held.
const LEVEL_STEP := 0.12
## An evolution, should the shop ever hold one.
const EVOLUTION_MULT := 1.4
const PRICE_ROUND := 5
const PRICE_MIN := 40
## The tray's plates: the handoff's 76 px, 60 px once the build is long (TRAY_SMALL_FROM items or more), and 48 px only
## when the stack would not fit over LEAVE otherwise (_fit).
const TRAY_PX := 76.0
const TRAY_PX_SMALL := 60.0
const TRAY_PX_MIN := 48.0
const TRAY_GAP := 10
## The column's gap under the header, between the tray and the cards, and between the cards and LEAVE.
const BODY_GAP := 24.0
const CARDS_GAP := 24.0
## The cards' gap as designed and the least it squeezes to; the least the list shrinks to (CardScreen's numbers).
const CARD_GAP := 40.0
const CARD_GAP_MIN := 24.0
const MIN_SCALE := 0.6
## Pass 123 (lane RUN_B), the Royale layout (the mocks 8_Shop_24_gold / 8_Shop_300_gold, canvas px): the tray's frames
## (Garry's pick: 56 px, stepping to TRAY_PX_MIN only when the stack would not fit), the label beside them
## ROYALE_TRAY_LABEL_GAP before the first, the frames' navy base under the last row; the cards ROYALE_CARD_GAP apart; an
## offer's frame, name, text and padding [t, r, b, l]; the price button's width (BUY / short), its gap above it; the
## wallet's number size (the Wanted plate's px, R.WALLET_SCALE of it) and coin; LEAVE's width and type.
const ROYALE_TRAY_PX := 56.0
const ROYALE_TRAY_LABEL_GAP := 16.0
const ROYALE_TRAY_BASE := 8.0
const ROYALE_CARD_GAP := 28.0
const ROYALE_PLATE := 160.0
const ROYALE_NAME_PX := 48
const ROYALE_EFFECT_PX := 28
const ROYALE_PAD := [40, 32, 36, 30]
const ROYALE_PRICE_W := 260.0
const ROYALE_PRICE_W_SHORT := 200.0
const ROYALE_PRICE_GAP := 10.0
const ROYALE_WALLET_PX := 52
const ROYALE_WALLET_COIN := 44.0
const ROYALE_LEAVE_W := 584.0
const ROYALE_LEAVE_PX := 38

var _gold_plate: PanelContainer
var _body: Control
var _tray: BoxContainer
var _hold_label: WText
var _hold_flow: HFlowContainer
var _list: VBoxContainer
var _offer: Array = []
var _cards: Array = []
var _done := false
## the plates' size as laid out (tests, tools)
var _plate_px := TRAY_PX


func _ready() -> void:
	build_dim(W.DIM)
	build_header(Loc.t("ui.shop.star"), Loc.t("ui.shop.title"), "", 120)
	header.line.visible = false
	# pass 123: the wallet at the top right, where the purse always is (the menus' wallet, the HUD's corner)
	_gold_plate = WMenuHeader.gold_plate(0, ROYALE_WALLET_PX, ROYALE_WALLET_COIN)
	_gold_plate.anchor_left = 1.0
	_gold_plate.anchor_right = 1.0
	_gold_plate.offset_right = -float(R.HEADER_POS.x)
	_gold_plate.offset_left = -float(R.HEADER_POS.x)
	_gold_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_gold_plate.offset_top = float(R.HEADER_RIGHT_Y) + W.safe_top()
	add_child(_gold_plate)
	# the body (pass 60): one column under the header, its top set on open from the header's real foot; a plain Control,
	# not a box, so the cards' list may shrink (a container resets a child's scale on every sort)
	_body = Control.new()
	_body.name = "Body"
	_body.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_body.offset_left = 48
	_body.offset_right = -48
	_body.offset_top = 470
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	# YOU HOLD: the label on its own row, left, then the plates in a flow that wraps (pass 123, Royale: the label beside
	# the frames, the mock's, the flow wrapping under the first frame)
	_tray = HBoxContainer.new()
	_tray.add_theme_constant_override("separation", int(ROYALE_TRAY_LABEL_GAP))
	_tray.name = "Tray"
	_tray.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_tray)
	_hold_label = W.label(Loc.t("ui.shop.you_hold"), 20, W.AGED)
	_hold_label.name = "HoldLabel"
	# centred on the first row of frames
	_hold_label.valign = VERTICAL_ALIGNMENT_CENTER
	_hold_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tray.add_child(_hold_label)
	_hold_flow = HFlowContainer.new()
	_hold_flow.name = "HoldFlow"
	_hold_flow.add_theme_constant_override("h_separation", TRAY_GAP)
	_hold_flow.add_theme_constant_override("v_separation", TRAY_GAP + (int(ROYALE_TRAY_BASE)))
	_hold_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray.add_child(_hold_flow)
	_list = VBoxContainer.new()
	_list.name = "Cards"
	_list.add_theme_constant_override("separation", int(_card_gap()))
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_list)
	var leave_btn: WButton
	var half := 215.0
	# pass 123 (Garry): leaving spends the stall for good, so LEAVE is the kit's red (danger), the mock's width
	leave_btn = WButton.make([Loc.t("ui.shop.leave")], ROYALE_LEAVE_PX, WButton.DANGER, R.BUTTON_EDGE, R.BUTTON_BASE, 26.0, 0.0, 0.0, WButton.RED)
	half = ROYALE_LEAVE_W * 0.5
	leave_btn.name = "Leave"
	leave_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	leave_btn.offset_left = -half
	leave_btn.offset_right = half
	leave_btn.offset_bottom = -90
	leave_btn.offset_top = -90 - 108
	leave_btn.pressed.connect(func(): _finish(false))
	add_child(leave_btn)


## The stage the prices are for: 1 to 3 (Run.stage counts from 0; endless and anything past the third stay on 3), or
## `stage_number` when a caller names one.
static func price_stage(stage_number: int = 0) -> int:
	var s := stage_number if stage_number > 0 else Run.stage + 1
	return clampi(s, 1, PRICE_BASE_BY_STAGE.size())


## The price of a card (pass 60): half a stage's gold (PRICE_BASE_BY_STAGE) x the kind (KIND_MULT) x the rarity
## (RARITY_MULT, every tier) x (1 + LEVEL_STEP x the level already held) for an upgrade, x EVOLUTION_MULT for an
## evolution, rounded to PRICE_ROUND, never under PRICE_MIN. `stage_number` 0 reads the run's stage.
static func price_of(card: Dictionary, stage_number: int = 0) -> int:
	var def: ContentDef = card["def"]
	var base: float = float(PRICE_BASE_BY_STAGE[price_stage(stage_number) - 1])
	var kind := W.kind_of(def)
	var p: float = base * float(KIND_MULT.get(kind, 1.0))
	p *= float(RARITY_MULT.get(W.rarity_of(def), 1.0))
	p *= 1.0 + LEVEL_STEP * float(maxi(int(card.get("level_from", 0)), 0))
	if str(card.get("type", "")) == "evolution" or W.is_evolved(def):
		p *= EVOLUTION_MULT
	return maxi(int(round(p / float(PRICE_ROUND))) * PRICE_ROUND, PRICE_MIN)


## What the hero holds for the tray: [def, level] for every weapon and every passive (lines and items), weapons first.
static func held_items() -> Array:
	var held: Array = []
	for w in Run.weapons:
		held.append([(w as WeaponInstance).def, (w as WeaponInstance).level])
	for pid in Run.passives.keys():
		if Registry.passive(pid):
			held.append([Registry.passive(pid), int(Run.passives[pid])])
	return held


## The tray's plate size for `count` items: the handoff's 76 px, 60 px for a long build (pass 123, Royale: the mock's
## 56 px frames whatever the count).
static func tray_px(count: int) -> float:
	return ROYALE_TRAY_PX


## The cards' gap as designed (pass 123: ROYALE_CARD_GAP under Royale, the mock's).
static func _card_gap() -> float:
	return ROYALE_CARD_GAP


## How many rows `count` plates of `px` take in a flow `width` wide with TRAY_GAP between them.
static func tray_rows_for(count: int, px: float, width: float) -> int:
	if count <= 0:
		return 0
	var per_row := maxi(int(floor((width + TRAY_GAP) / (px + TRAY_GAP))), 1)
	return int(ceil(float(count) / float(per_row)))


## The tray's height for `count` plates of `px`: the label, its gap and the rows (0 with nothing held). Pass 123, under
## Royale: the label sits beside the frames, so the rows alone, ROYALE_TRAY_BASE apart more (each frame's navy base) and
## the last one's base under them.
func tray_height_for(count: int, px: float) -> float:
	if count <= 0:
		return 0.0
	var beside := _tray is HBoxContainer
	# before the first layout the flow has no width yet: the body's, 48 px in from either edge of the screen
	var w := _hold_flow.size.x
	if w <= 0.0:
		w = get_viewport_rect().size.x - 96.0
		if beside:
			w -= _hold_label.get_combined_minimum_size().x + ROYALE_TRAY_LABEL_GAP
	var rows := tray_rows_for(count, px, w)
	if beside:
		return rows * px + (rows - 1) * (TRAY_GAP + ROYALE_TRAY_BASE) + ROYALE_TRAY_BASE
	return _hold_label.get_combined_minimum_size().y + TRAY_GAP + rows * px + (rows - 1) * TRAY_GAP


func open(offer: Array) -> void:
	_offer = offer
	_done = false
	(_gold_plate.find_child("Amount", true, false) as WText).text = W.num(Run.run_gold)
	# under the header's real foot (the header carries W.safe_top() already)
	_body.offset_top = header.offset_top + header.get_combined_minimum_size().y + BODY_GAP
	var held := held_items()
	_fill_tray(held, tray_px(held.size()))
	for c in _cards:
		(c as Node).queue_free()
	_cards.clear()
	for card in _offer:
		var node := _make_card(card)
		_list.add_child(node)
		_cards.append(node)
	# the cards start where the tray should end; the fit a frame later reads the laid-out heights
	_list.scale = Vector2.ONE
	_list.add_theme_constant_override("separation", int(_card_gap()))
	_list.offset_top = tray_height_for(held.size(), _plate_px) + (CARDS_GAP if not held.is_empty() else 0.0)
	modulate.a = 1.0
	enter()
	if _tray is HBoxContainer:
		# pass 123: the wallet (outside the header under Royale) comes in with the header's drop
		var y := float(R.HEADER_RIGHT_Y) + W.safe_top()
		_gold_plate.offset_top = y - 40.0
		_gold_plate.modulate.a = 0.0
		var tw := _gold_plate.create_tween().set_parallel(true)
		tw.tween_property(_gold_plate, "offset_top", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_gold_plate, "modulate:a", 1.0, 0.2)
	Audio.play("ui_card_pick")
	_fit()


## The plates, each in the colour of the level held (pass 48), `px` square.
func _fill_tray(held: Array, px: float) -> void:
	_plate_px = px
	for c in _hold_flow.get_children():
		_hold_flow.remove_child(c)
		c.queue_free()
	for h in held:
		var p := WPlate.new().for_def(h[0], px, false, int(h[1]))
		p.icon_frac = 0.72
		_hold_flow.add_child(p)
	_hold_label.visible = not held.is_empty()
	_tray.visible = not held.is_empty()
	if _tray is HBoxContainer:
		# pass 123: the label beside the frames, centred on their first row
		_hold_label.custom_minimum_size.y = px


## The stack between the header and LEAVE, fitted (pass 60) the way CardScreen fits its cards: the cards sit CARDS_GAP
## under the tray's real height; a stack that would pass CARDS_GAP over LEAVE squeezes the cards' gap to CARD_GAP_MIN,
## then steps the plates down (60, 48 px: fewer rows), and shrinks the list last, to MIN_SCALE at the least, about its
## top's middle. Read a frame after the open, when the flow and the cards' wrapped words have their sizes.
func _fit() -> void:
	await get_tree().process_frame
	if not visible or _cards.is_empty() or not is_inside_tree():
		return
	var held := held_items().size()
	var vp := get_viewport_rect().size
	var bottom := vp.y - 90.0 - 108.0 - CARDS_GAP
	var total := 0.0
	for c in _cards:
		if is_instance_valid(c):
			total += (c as Control).get_combined_minimum_size().y
	var n := _cards.size()
	var gap := _card_gap()
	var tray_h := tray_height_for(held, _plate_px)
	var top := _body.offset_top + tray_h + (CARDS_GAP if held > 0 else 0.0)
	var span := total + gap * (n - 1)
	if top + span > bottom:
		gap = maxf((bottom - top - total) / maxf(n - 1, 1), CARD_GAP_MIN)
		span = total + gap * (n - 1)
	# the plates one size down at a time while the stack still passes LEAVE and a smaller plate takes fewer rows
	var px := _plate_px
	while top + span > bottom and held > 0 and px > TRAY_PX_MIN:
		var smaller := _next_plate_px(px)
		var h2 := tray_height_for(held, smaller)
		if h2 < tray_h:
			tray_h = h2
			top = _body.offset_top + tray_h + CARDS_GAP
			gap = clampf((bottom - top - total) / maxf(n - 1, 1), CARD_GAP_MIN, _card_gap())
			span = total + gap * (n - 1)
		px = smaller
	if px != _plate_px:
		_fill_tray(held_items(), px)
	var k := 1.0
	if top + span > bottom:
		k = clampf((bottom - top) / maxf(span, 1.0), MIN_SCALE, 1.0)
	_list.add_theme_constant_override("separation", int(gap))
	_list.offset_top = top - _body.offset_top
	_list.pivot_offset = Vector2(_list.size.x * 0.5, 0.0)
	_list.scale = Vector2(k, k)


## The plate size under `px`: 76 -> 60 -> 48.
static func _next_plate_px(px: float) -> float:
	if px > TRAY_PX_SMALL:
		return TRAY_PX_SMALL
	return TRAY_PX_MIN


## How many rows the tray's plates take as laid out (tests, tools): distinct tops among them.
func tray_rows() -> int:
	var tops: Array = []
	for c in _hold_flow.get_children():
		var y := int(round((c as Control).position.y))
		if not tops.has(y):
			tops.append(y)
	return tops.size()


## The tray's foot, the cards' top and the cards' drawn foot in the modal's coordinates, as laid out.
func tray_bottom() -> float:
	if not _tray.visible:
		return _body.position.y
	return _body.position.y + _tray.position.y + _tray.size.y


func cards_top() -> float:
	return _body.position.y + _list.position.y


func cards_bottom() -> float:
	return cards_top() + _list.size.y * _list.scale.y


## The plates' size as laid out and the list's scale (1 unless the stack had to shrink).
func plate_px() -> float:
	return _plate_px


func cards_scale() -> float:
	return _list.scale.y


## The right edge of the widest piece of the tray in the modal's coordinates (nothing may pass the screen).
func tray_right() -> float:
	var right := 0.0
	for c in _hold_flow.get_children():
		var ctl := c as Control
		right = maxf(right, _body.position.x + _hold_flow.position.x + ctl.position.x + ctl.size.x)
	return right


func _make_card(card: Dictionary) -> WCard:
	var def: ContentDef = card["def"]
	var price := price_of(card)
	var short := maxi(price - Run.run_gold, 0)
	return _make_card_royale(card, def, price, short)


## Pass 123 (lane RUN_B): the mock's offer under Royale. The slate card at the mock's sizes, the tag straight after the
## kind's words, and on its foot the kit's price row (W.price_row: "● 230 · BUY" green; short of gold "n short" in red
## before the grey "● 325"); the card itself keeps its face whatever the purse (Garry: "an unaffordable offer keeps its
## card"), and a short one shows no held glow under a finger (hold_off). The whole card is the tap target, as under
## Wanted (the price button passes its touches on to it); a short tap says why (ui_locked in _buy).
func _make_card_royale(card: Dictionary, def: ContentDef, price: int, short: int) -> WCard:
	var o := WItem.options(card, {"plate_px": ROYALE_PLATE, "name_size": ROYALE_NAME_PX, "effect_size": ROYALE_EFFECT_PX,
		"pad": ROYALE_PAD, "icon_frac": 0.72, "stars": [], "price": -1, "short": 0, "locked": false})
	var c := WCard.make(def, o)
	tag_after_word(c)
	var gap := Control.new()
	gap.name = "PriceGap"
	gap.custom_minimum_size.y = ROYALE_PRICE_GAP
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := W.price_row(price, Loc.t("ui.shop.buy"), WButton.GREEN, R.PRICE_PX, short)
	var pb := W.price_button_of(row)
	pb.custom_minimum_size.x = ROYALE_PRICE_W_SHORT if short > 0 else ROYALE_PRICE_W
	# (WCard's column: the price row goes under the text, right-aligned, as the card's own price button did)
	var col: VBoxContainer = c.get("_col")
	if col:
		col.add_child(gap)
		col.add_child(row)
	c.price_button = pb
	c.set_meta("short", short)
	c.pressed.connect(func(): _buy(card, price, c))
	if short > 0:
		hold_off(c)
	return c


## Pass 123: the tag beside the kind's words (the mock's "PASSIVE COMMON [NEW]"), not at the line's far end: the words take
## only their own width. The Stranger's deal card reads the same.
static func tag_after_word(c: WCard) -> void:
	var wl := c.find_child("WordLine", true, false)
	if wl and wl.get_child_count() > 0:
		(wl.get_child(0) as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## Pass 123: a card the purse cannot buy under Royale takes a finger without the held look (the gold edge, the glow and
## the rays say "this one"): its own touches are taken here, before WTap's, and a tap (a press and a release within
## WTap.SLOP, as WTap's) still emits `pressed`, so the screen says why.
static func hold_off(c: WTap) -> void:
	c.gui_input.connect(func(e: InputEvent) -> void:
		var pos := Vector2.ZERO
		var down := false
		if e is InputEventScreenTouch:
			pos = (e as InputEventScreenTouch).position
			down = (e as InputEventScreenTouch).pressed
		elif e is InputEventMouseButton:
			if (e as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
				return
			pos = (e as InputEventMouseButton).position
			down = (e as InputEventMouseButton).pressed
		else:
			return
		c.accept_event()
		if down:
			c.set_meta("tap_from", pos)
		elif c.has_meta("tap_from"):
			var from: Vector2 = c.get_meta("tap_from")
			c.remove_meta("tap_from")
			if pos.distance_to(from) <= WTap.SLOP:
				W.sfx("ui_tap")
				c.pressed.emit())


func _buy(card: Dictionary, price: int, node: WCard) -> void:
	if _done:
		return
	RunReplay.note("shop_buy", {"i": _offer.find(card), "id": str(card.get("id", "")), "price": price})
	if Run.run_gold < price:
		Audio.play("ui_locked")
		return
	_done = true
	Run.spend_gold(price, "shop")
	var line := CardPool.apply(card)
	Audio.play("ui_buy")
	node.show_held(true)
	var tw := create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(func(): _finish(true, line))


func _finish(bought: bool, line: String = "") -> void:
	if not bought and visible:
		RunReplay.note("shop_leave")
	visible = false
	if bought and line != "":
		Run.build_changed.emit()
	closed.emit(bought)
