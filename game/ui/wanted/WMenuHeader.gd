## The menu header: a 96 x 96 back square at (36, 44) (106 x 114 with its border and the 8 px under the glyph), the
## screen's name in 72 px slab beside it, and whatever sits top-right (the gold plate wherever gold can be spent, a
## count, a seal).
## Pass 123 (lane KIT2), under Royale (the mocks 5_Upgrade, 10_Collection, 10_Settings): the back square R.HEADER_BACK
## (96) at R.HEADER_POS (40, 56) as a slate button on its 8 px base (the "‹" cream Ultra 60 with the navy edge), the name
## in cream Ultra R.HEADER_TITLE_PX (64) in capitals at (160, 70), shrunk to the room left of the top-right piece (never
## under R.HEADER_TITLE_MIN), the top-right piece R.HEADER_RIGHT_Y (68) down, 40 in; the wallet (gold_plate) the mock's
## black plate (72 tall, the coin 40, the number white Ultra 34). Wanted is laid out as before.
class_name WMenuHeader
extends Control

signal back

var back_button: WTap
var title: WText
var right: Control
## Pass 123: the name's size before fitting (Royale; 0 = never fitted: a header whose title a screen sets by hand, the
## developer menu's).
var _title_px := 0


static func make(t: String, right_node: Control = null) -> WMenuHeader:
	return _make_royale(t, right_node)


## The Royale header (pass 123, lane KIT2): see the class comment.
static func _make_royale(t: String, right_node: Control) -> WMenuHeader:
	var h := WMenuHeader.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var pos := R.HEADER_POS
	var side := float(R.HEADER_BACK)
	h.offset_left = pos.x
	h.offset_right = -pos.x
	h.offset_top = pos.y + W.safe_top()
	h.offset_bottom = pos.y + W.safe_top() + side + R.BUTTON_BASE + R.BUTTON_NAVY_BASE
	h.back_button = WTap.new()
	h.back_button.name = "Back"
	var bb := W.box(W.PAPER, R.BUTTON_EDGE, R.BUTTON_BASE)
	bb.role = WButton.SLATE
	h.back_button.box = bb
	h.back_button.box_down = bb.pressed()
	h.back_button.position = Vector2.ZERO
	h.back_button.size = Vector2(side, side)
	h.back_button.custom_minimum_size = Vector2(side, side)
	var arrow := W.slab_text("‹", R.HEADER_BACK_PX, W.INK, HORIZONTAL_ALIGNMENT_CENTER, float(R.HEADER_BACK_PX))
	arrow.valign = VERTICAL_ALIGNMENT_CENTER
	# the glyph sits 8 px high (the mock's padding-bottom 8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_bottom", 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(arrow)
	h.back_button.add_child(m)
	h.back_button.pressed.connect(func(): h.back.emit())
	h.add_child(h.back_button)
	var px := R.HEADER_TITLE_PX
	h.title = W.slab_text(t.to_upper(), px, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(px))
	h.title.name = "Title"
	h.title.position = Vector2(R.HEADER_TITLE_X - pos.x, R.HEADER_TITLE_Y - pos.y)
	h.title.size = Vector2(1080.0 - R.HEADER_TITLE_X - pos.x, float(px))
	h.add_child(h.title)
	if t != "":
		h._title_px = px
	if right_node:
		h.set_right(right_node)
	h.resized.connect(h._fit_title)
	return h


## The screen's name (pass 123): under Royale in capitals, fitted to the room left of the top-right piece; under Wanted
## the text as given, as ScreenBase.set_title always set it.
func set_title(t: String) -> void:
	title.text = t.to_upper()
	if _title_px <= 0:
		_title_px = R.HEADER_TITLE_PX
	_fit_title()


## Royale (pass 123): the name back at its size, or smaller until it fits between the back square and the top-right
## piece (R.HEADER_TITLE_MIN at least); a header whose name no one set through make or set_title is left alone.
func _fit_title() -> void:
	if _title_px <= 0 or title == null:
		return
	var w := size.x if size.x > 1.0 else 1080.0 - 2.0 * R.HEADER_POS.x
	var room := w - title.position.x
	if right and is_instance_valid(right) and right.visible:
		room -= right.get_combined_minimum_size().x + 24.0
	var f: Font = title.font if title.font else W.slab()
	var tw := f.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _title_px).x + title.stroke * 2.0
	var fit := _title_px
	if room > 0.0 and tw > room:
		fit = maxi(int(floor(_title_px * room / tw)), R.HEADER_TITLE_MIN)
	if title.font_size != fit:
		title.font_size = fit
		# a smaller name keeps its middle where the full-size one had it
		title.position.y = (R.HEADER_TITLE_Y - R.HEADER_POS.y) + (_title_px - fit) * 0.5
	title.size = Vector2(maxf(room, 1.0), float(fit))
	title.line_height = float(fit)


## Put `n` top-right; the one it replaces leaves (and is freed, unless it carries the meta "keep": a screen that swaps
## its count for a seal and back).
func set_right(n: Control) -> void:
	if right == n:
		return
	if right:
		remove_child(right)
		if not right.has_meta("keep"):
			right.queue_free()
	right = n
	add_child(n)
	# pass 123: the mock's top-right piece, R.HEADER_RIGHT_Y down the screen (the header's top is R.HEADER_POS.y)
	var ms := n.get_combined_minimum_size()
	n.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	n.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	n.offset_right = 0
	n.offset_left = -ms.x
	n.offset_top = R.HEADER_RIGHT_Y - R.HEADER_POS.y
	n.offset_bottom = n.offset_top + ms.y
	_fit_title()
	return


## The gold plate: a coin and the number in slab on paper with a 5 px border and a hard shadow. Pass 122 (lane
## UIKIT_A), under Royale: the wallet is a black info plate (HardBox.role "plate": 56 % black, no edge, no base) with
## the number in white Ultra.
static func gold_plate(gold: int, px: int = 44, coin_px: float = 40.0, shadow: int = 6, border: int = 5) -> PanelContainer:
	return _wallet_royale(gold, px, coin_px)


## The Royale wallet (pass 123, lane KIT2; the mocks 5_Main_menu, 5_Upgrade): a black info plate R.WALLET_H (72) tall,
## R.WALLET_PAD inside (14 left, 20 right), the coin `coin_px` and the number R.WALLET_GAP apart, the number white Ultra at
## R.WALLET_SCALE of the Wanted size (44 -> 34; the Shop's 56 -> 43) with the mock's soft drop. The number is "Amount", as
## under Wanted, so the screens that update it find it the same way.
static func _wallet_royale(gold: int, px: int, coin_px: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Wallet"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var npx := maxi(int(round(px * R.WALLET_SCALE)), R.ULTRA_MIN)
	var h := maxf(float(R.WALLET_H), coin_px + 16.0)
	var hb := W.plate_box(0, 0, R.RADIUS).pad(R.WALLET_PAD.x, 0.0, R.WALLET_PAD.y, 0.0)
	p.add_theme_stylebox_override("panel", hb)
	p.custom_minimum_size.y = h
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", R.WALLET_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(coin_px)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	var n := W.slab_text(W.num(gold), npx, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(npx))
	R.no_edge(n)
	n.color = R.WHITE
	n.shadow = R.WALLET_DROP
	n.shadow_color = R.WALLET_DROP_COLOR
	n.shadow_straight = true
	n.name = "Amount"
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(n)
	p.add_child(row)
	return p
