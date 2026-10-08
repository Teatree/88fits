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
const TRAY_SMALL_FROM := 13
const TRAY_GAP := 10
## The column's gap under the header, between the tray and the cards, and between the cards and LEAVE.
const BODY_GAP := 24.0
const CARDS_GAP := 24.0
## The cards' gap as designed and the least it squeezes to; the least the list shrinks to (CardScreen's numbers).
const CARD_GAP := 40.0
const CARD_GAP_MIN := 24.0
const MIN_SCALE := 0.6

var _gold_plate: PanelContainer
var _body: Control
var _tray: VBoxContainer
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
	build_header("One visit only", "THE SHOP", "", 120)
	header.line.visible = false
	var gc := CenterContainer.new()
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gc.custom_minimum_size.y = 16 + 88
	_gold_plate = WMenuHeader.gold_plate(0, 56, 50.0, 6, 5)
	gc.add_child(_gold_plate)
	header.add_child(gc)
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
	# YOU HOLD: the label on its own row, left, then the plates in a flow that wraps
	_tray = VBoxContainer.new()
	_tray.name = "Tray"
	_tray.add_theme_constant_override("separation", TRAY_GAP)
	_tray.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_tray)
	_hold_label = W.label("You hold", 20, W.AGED)
	_hold_label.name = "HoldLabel"
	_tray.add_child(_hold_label)
	_hold_flow = HFlowContainer.new()
	_hold_flow.name = "HoldFlow"
	_hold_flow.add_theme_constant_override("h_separation", TRAY_GAP)
	_hold_flow.add_theme_constant_override("v_separation", TRAY_GAP)
	_hold_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray.add_child(_hold_flow)
	_list = VBoxContainer.new()
	_list.name = "Cards"
	_list.add_theme_constant_override("separation", int(CARD_GAP))
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_list)
	var leave_btn := WButton.make(["LEAVE"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	leave_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	leave_btn.offset_left = -215
	leave_btn.offset_right = 215
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


## The tray's plate size for `count` items: the handoff's 76 px, 60 px for a long build.
static func tray_px(count: int) -> float:
	return TRAY_PX_SMALL if count >= TRAY_SMALL_FROM else TRAY_PX


## How many rows `count` plates of `px` take in a flow `width` wide with TRAY_GAP between them.
static func tray_rows_for(count: int, px: float, width: float) -> int:
	if count <= 0:
		return 0
	var per_row := maxi(int(floor((width + TRAY_GAP) / (px + TRAY_GAP))), 1)
	return int(ceil(float(count) / float(per_row)))


## The tray's height for `count` plates of `px`: the label, its gap and the rows (0 with nothing held).
func tray_height_for(count: int, px: float) -> float:
	if count <= 0:
		return 0.0
	# before the first layout the flow has no width yet: the body's, 48 px in from either edge of the screen
	var w := _hold_flow.size.x
	if w <= 0.0:
		w = get_viewport_rect().size.x - 96.0
	var rows := tray_rows_for(count, px, w)
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
	_list.add_theme_constant_override("separation", int(CARD_GAP))
	_list.offset_top = tray_height_for(held.size(), _plate_px) + (CARDS_GAP if not held.is_empty() else 0.0)
	modulate.a = 1.0
	enter()
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
	var gap := CARD_GAP
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
			gap = clampf((bottom - top - total) / maxf(n - 1, 1), CARD_GAP_MIN, CARD_GAP)
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
	var o := WItem.options(card, {"plate_px": 160.0, "name_size": 54, "effect_size": 28, "pad": [30, 32, 30, 32],
		"seal_px": 92.0, "icon_frac": 0.72, "stars": [], "price": price, "short": short, "locked": short > 0})
	var c := WCard.make(def, o)
	c.pressed.connect(func(): _buy(card, price, c))
	return c


func _buy(card: Dictionary, price: int, node: WCard) -> void:
	if _done:
		return
	if Run.run_gold < price:
		Audio.play("ui_locked")
		return
	_done = true
	Run.spend_gold(price)
	var line := CardPool.apply(card)
	Audio.play("ui_buy")
	node.show_held(true)
	var tw := create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(func(): _finish(true, line))


func _finish(bought: bool, line: String = "") -> void:
	visible = false
	if bought and line != "":
		Run.build_changed.emit()
	closed.emit(bought)
