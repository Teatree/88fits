## The Store (pass 147, lane SHOP; Garry: "Make the Shop Screen. On this screen we will only allow selling of Coin Packs for
## now. Make it similar to any other game which does this. Very much reference should be of the Archero or Survivor.io
## Gems section in the shop, but fixed to occupy the whole Portrait screen ... Don't implement actual purchasing yet").
## The STORE tab of the docked tab bar opens it while the Store is open (StorePacks.is_open: the Settings screen's debug
## panel row "Store"; locked by default and in prod). What is on screen, top to bottom: the menu header (the back square,
## STORE, the purse), the board sheet holding "COIN PACKS" and a grid of the six coin packs of
## res://content/store/store.json (two columns, three rows, sized to fill the board between the header and the tab bar on
## any phone, the camera cutout's inset taken off: W.safe_top), and the tab bar with STORE open.
## A pack is a card (the kit's slate panel): its ribbon hanging over its top edge ("MOST POPULAR", "BEST VALUE": the
## file's `ribbon`), a soft gold glow behind its picture (rays turning behind a ribboned one), its "+N% BONUS" tag
## (StorePacks' rule), the coin and the amount in big gold numbers, and a green price button with the real-money price
## ("$0.99"). A tap on a price plays the button's press, then the kit's modal shell (WConfirm.shell) says "Coming soon:
## Purchases aren't open yet. Nothing was bought and nothing was charged." with one OK (ui.store.not_yet_*): no coins are
## added, nothing is saved or recorded (StorePacks.buy). Coins x25 never changes an amount here.
## Nodes for tools: "Heading", "Grid", the cards "Pack_<id>" (meta "pack": the id) holding "Art", "Glow", "Amount" (its
## number "Coins"), "Ribbon", "Bonus" and the WButton "Price"; the message is a WConfirm (its button "Btn_ok").
class_name StoreScreen
extends ScreenBase

const SELF_SCENE := "res://ui/StoreScreen.tscn"
const COLUMNS := 2
## The grid's gaps (px), the heading's line, a card's smallest and largest height (a tall phone grows the pictures, a
## short window scrolls).
const GAP := 24.0
const HEADING_PX := 36
const HEADING_H := 46.0
const CARD_H_MIN := 360.0
const CARD_H_MAX := 640.0
## Inside a card: the side padding, the price button's height and its gap to the foot, the amount line, the ribbon's
## overhang over the card's top and its own height, the bonus tag's type.
const PAD := 20.0
const PRICE_BTN_H := 80.0
const PRICE_PX := 38
const FOOT := 20.0
const AMOUNT_H := 58.0
const AMOUNT_PX := 46
const COIN_PX := 46.0
const RIBBON_H := 46.0
const RIBBON_UP := 20.0
const RIBBON_PX := 22
const RIBBON_W := 0.78
const BONUS_PX := 20
## The ribbons' colours (a key of StorePacks.RIBBONS -> its face).
const RIBBON_FILL := {"most_popular": R.TAG_PURPLE, "best_value": R.TAG_RED}
## The glow behind a picture: warm gold, strongest at the middle.
const GLOW := Color(1.0, 0.83, 0.42, 0.42)
const RAYS_SHADER := preload("res://core/shaders/ui_rays.gdshader")

var _grid: GridContainer
var _wallet: PanelContainer
var _cards: Dictionary = {}
## What the price taps answered (StorePacks.buy's dictionaries, newest last): read by the tests and the audit.
var answers: Array = []


# ---------------------------------------------------------------- the frame

func tab_bar() -> String:
	return "store"


func header_right() -> Control:
	_wallet = WMenuHeader.gold_plate(Currency.balance(StorePacks.currency()), 44, 40.0, 5, 4)
	return _wallet


func build() -> void:
	set_title(Loc.t("ui.store.title"))
	var heading := W.text(Loc.t("ui.store.section").to_upper(), R.display(), HEADING_PX, R.CREAM, HORIZONTAL_ALIGNMENT_CENTER,
		HEADING_H)
	heading.name = "Heading"
	R.edge(heading, HEADING_PX)
	content.add_child(heading)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_grid)
	var card_h := card_height()
	for pk: Dictionary in StorePacks.packs():
		var c := _card(pk, card_h)
		_cards[str(pk["id"])] = c
		_grid.add_child(c)


## A card's height: the board's visible height less the heading and the gaps, split over the rows (CARD_H_MIN ..
## CARD_H_MAX), so the six packs fill the board between the header and the tab bar.
func card_height() -> float:
	var n := StorePacks.packs().size()
	var rows := maxi(ceili(float(n) / float(COLUMNS)), 1)
	var sep := float(content.get_theme_constant("separation")) if content else 30.0
	var room := visible_board_height() - HEADING_H - sep - GAP * float(rows - 1)
	return clampf(floorf(room / float(rows)), CARD_H_MIN, CARD_H_MAX)


func on_back() -> void:
	go(TITLE)


# ---------------------------------------------------------------- a pack

func card_of(id: String) -> Control:
	return _cards.get(id) as Control


func _card(pk: Dictionary, h: float) -> Control:
	var id := str(pk["id"])
	var c := Control.new()
	c.name = "Pack_%s" % id
	c.set_meta("pack", id)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.custom_minimum_size = Vector2(0.0, h)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var face := Panel.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", W.sheet_box(Vector2.ZERO))
	c.add_child(face)
	var ribbon := str(pk["ribbon"])
	# rays behind a ribboned pack's picture, a soft glow behind every one
	var rays: Control = null
	if ribbon != "":
		rays = Control.new()
		rays.name = "Rays"
		rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = RAYS_SHADER
		m.set_shader_parameter("color", Color(1.0, 0.902, 0.588, 0.22))
		rays.material = m
		rays.draw.connect(func() -> void: rays.draw_rect(Rect2(Vector2.ZERO, rays.size), Color.WHITE))
		c.add_child(rays)
	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture = _glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	c.add_child(glow)
	var art := TextureRect.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = picture_of(pk)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.add_child(art)
	# the coin and the amount
	var amount := HBoxContainer.new()
	amount.name = "Amount"
	amount.alignment = BoxContainer.ALIGNMENT_CENTER
	amount.add_theme_constant_override("separation", 10)
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(COIN_PX, W.BRASS, 3.0, StorePacks.currency())
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(coin)
	var n := W.text(W.num(int(pk["coins"])), R.display(), AMOUNT_PX, R.GOLD_TEXT, HORIZONTAL_ALIGNMENT_LEFT, float(AMOUNT_PX))
	n.name = "Coins"
	R.edge(n, AMOUNT_PX, true)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(n)
	c.add_child(amount)
	# the price: green, the real money's price; it buys nothing yet
	var pad_v := maxf((PRICE_BTN_H - 2.0 * R.BUTTON_EDGE - float(PRICE_PX)) * 0.5, 0.0)
	var b := WButton.make([str(pk["price_text"])], PRICE_PX, WButton.PRIMARY, R.BUTTON_EDGE, R.BUTTON_BASE, pad_v, 22.0,
		float(PRICE_PX), WButton.GREEN)
	b.name = "Price"
	b.set_meta("pack", id)
	b.pressed.connect(press_price.bind(id))
	c.add_child(b)
	if ribbon != "" and RIBBON_FILL.has(ribbon):
		c.add_child(_ribbon(ribbon))
	var bonus := int(pk.get("bonus", 0))
	if bonus > 0:
		c.add_child(_bonus_tag(bonus))
	c.resized.connect(_lay_card.bind(c))
	return c


## Where everything in a card sits (on every resize: the grid gives the card its width).
func _lay_card(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var face := c.get_node("Face") as Control
	face.position = Vector2.ZERO
	face.size = Vector2(w, h)
	var b := c.get_node("Price") as Control
	var bh := maxf(b.get_combined_minimum_size().y, PRICE_BTN_H)
	b.position = Vector2(PAD, h - FOOT - float(R.BUTTON_BASE) - bh)
	b.size = Vector2(w - 2.0 * PAD, bh)
	var amount := c.get_node("Amount") as Control
	amount.position = Vector2(PAD, b.position.y - 10.0 - AMOUNT_H)
	amount.size = Vector2(w - 2.0 * PAD, AMOUNT_H)
	var top := RIBBON_H - RIBBON_UP + 6.0 if c.has_node("Ribbon") else PAD
	var art_rect := Rect2(PAD, top, w - 2.0 * PAD, amount.position.y - 6.0 - top)
	var art := c.get_node("Art") as Control
	art.position = art_rect.position
	art.size = art_rect.size
	var side := minf(art_rect.size.x, art_rect.size.y)
	var glow := c.get_node("Glow") as Control
	var gs := side * 1.25
	glow.position = art_rect.get_center() - Vector2(gs, gs) * 0.5
	glow.size = Vector2(gs, gs)
	if c.has_node("Rays"):
		var rays := c.get_node("Rays") as Control
		var rs := side * 1.6
		rays.position = art_rect.get_center() - Vector2(rs, rs) * 0.5
		rays.size = Vector2(rs, rs)
		(rays.material as ShaderMaterial).set_shader_parameter("size", rs)
		rays.queue_redraw()
	if c.has_node("Ribbon"):
		var r := c.get_node("Ribbon") as Control
		var rw := roundf(w * RIBBON_W)
		r.position = Vector2(roundf((w - rw) * 0.5), -RIBBON_UP)
		r.size = Vector2(rw, RIBBON_H)
	if c.has_node("Bonus"):
		var t := c.get_node("Bonus") as Control
		var ts := t.get_combined_minimum_size()
		t.size = ts
		t.position = Vector2(w - PAD * 0.5 - ts.x, top + 4.0)
	# a picture glow and a card face cut nothing: the art is inside its rect, the ribbon hangs over the top on purpose
	c.queue_redraw()


## The ribbon over a card's top edge: a band in its colour with a navy edge, its words in capitals.
func _ribbon(key: String) -> Control:
	var r := PanelContainer.new()
	r.name = "Ribbon"
	r.set_meta("ribbon", key)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = RIBBON_FILL[key]
	sb.border_color = R.NAVY
	sb.set_border_width_all(R.TAG_EDGE)
	sb.set_corner_radius_all(R.RADIUS)
	sb.anti_aliasing = true
	sb.shadow_color = Color(R.NAVY, 0.9)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(0, 4)
	r.add_theme_stylebox_override("panel", sb)
	var t := W.text(Loc.t(StorePacks.RIBBON_KEY % key).to_upper(), R.body(R.BOLD_WEIGHT), RIBBON_PX, R.CREAM,
		HORIZONTAL_ALIGNMENT_CENTER, float(RIBBON_PX))
	t.name = "Words"
	t.stroke = 2
	t.stroke_color = R.NAVY
	t.shadow = 2
	t.shadow_color = R.NAVY
	t.shadow_straight = true
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(t)
	return r


## The "+N% BONUS" tag: a gold tag with navy words (StorePacks.bonus_for's N).
func _bonus_tag(n: int) -> Control:
	var p := PanelContainer.new()
	p.name = "Bonus"
	p.set_meta("bonus", n)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = R.TAG_GOLD
	sb.border_color = R.NAVY
	sb.set_border_width_all(R.TAG_EDGE)
	sb.set_corner_radius_all(R.RADIUS_TAG)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	var t := W.text(Loc.t("ui.store.bonus", {"percent": str(n)}).to_upper(), R.body(R.BOLD_WEIGHT), BONUS_PX, R.NAVY,
		HORIZONTAL_ALIGNMENT_CENTER, float(BONUS_PX))
	t.name = "Words"
	R.no_edge(t)
	p.add_child(t)
	return p


## A pack's picture: its file, else the purse's coin (a pack whose picture is missing still shows coins).
static func picture_of(pk: Dictionary) -> Texture2D:
	var path := str(pk.get("picture", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return WCoin.art_of(StorePacks.currency())


static var _glow_tex: GradientTexture2D


static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, GLOW)
		g.set_color(1, Color(GLOW, 0.0))
		g.add_point(0.45, Color(GLOW, GLOW.a * 0.45))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	return _glow_tex


# ---------------------------------------------------------------- a price tapped

## A finger on pack `id`'s price (the button's press has played): there is no billing yet (StorePacks.buy), so the purse
## stays as it is and the player is told in the kit's modal (one at a time: a second tap while it shows only replaces it).
func press_price(id: String) -> void:
	var ans := StorePacks.buy(id)
	answers.append(ans)
	if bool(ans.get("ok", false)):
		return
	WConfirm.shell(self, {"title": Loc.t("ui.store.not_yet_title"), "body": Loc.t("ui.store.not_yet_body"),
		"buttons": [{"id": "ok", "text": Loc.t("ui.store.not_yet_ok"), "role": WButton.GOLD}], "cancel_id": "ok"})
