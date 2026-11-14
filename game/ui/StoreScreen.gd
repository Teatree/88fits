## The Store (pass 147, lane SHOP; pass 149, lane STORE). Garry (2026-11-13): "Make the Shop Screen ... Very much reference
## should be of the Archero or Survivor.io Gems section in the shop, but fixed to occupy the whole Portrait screen"; (2026-11-14)
## "In the Shop there will now be 2 sections: Gems section at the top, Coins section underneath: Gems are bought with $ ...
## Coins are bought with Gems. As the Player progresses the amount of Coins they get from each offers changes".
## The STORE tab of the docked tab bar opens it while the Store is open (StorePacks.is_open: the Settings screen's debug
## panel row "Store"; locked by default and in prod). What is on screen, top to bottom: the menu header (the back square,
## STORE, the purse and the gem wallet: WMenuHeader.wallets), the board sheet holding
## - **GEMS** (the gem and the word) over the six gem packs of res://content/store/store.json, three a row, each priced in
##   real money ("$0.99"); a tap on a price plays the button's press, then the kit's modal shell says "Coming soon:
##   Purchases aren't open yet. Nothing was bought and nothing was charged." with one OK: nothing is added, saved or
##   recorded (StorePacks.buy_gems);
## - **COINS** (the coin and the word, a line saying the offers grow with the stages and the Trail) over the three coin
##   offers in one row, each showing what it gives this player now (StorePacks.coins_now: the latest stage unlocked and the
##   Trail Level) and priced in gems (the gem on its green button). A tap asks "Buy 5,500 coins for 500 gems?"
##   (WConfirm.open, the buy button the gem and its price); yes = StorePacks.buy_coins: the gems leave the wallet, the
##   coins go into the purse, both plates count again, a toast; short of gems, a message says how many more are needed
##   (its GET GEMS scrolls up to the gem packs) and nothing moves;
## and the tab bar with STORE open. The cards are sized so both sections fill the board between the header and the tab bar
## on a phone (the camera cutout's inset taken off: W.safe_top); a short window scrolls. Coins x25 never changes an amount.
## A card (the kit's slate panel): its ribbon hanging over its top edge ("MOST POPULAR", "BEST VALUE": the file's
## `ribbon`), a soft glow in its currency's colour behind its picture (rays turning behind a ribboned one), its "+N% BONUS"
## tag (StorePacks' rules), the icon and the amount in big numbers, and a green price button.
## Nodes for tools: "GemsSection" ("Heading", "Grid" with the cards "Pack_<id>", meta "pack"), "CoinsSection"
## ("CoinsHeading", "CoinsLine", "Offers" with the cards "Offer_<id>", meta "offer"); a card holds "Art", "Glow",
## "Amount" (its number "Gems" or "Coins"), "Ribbon", "Bonus" and the WButton "Price"; the messages are WConfirms (their
## buttons "Btn_ok", "Btn_gems", "Cancel" / "Confirm").
class_name StoreScreen
extends ScreenBase

const SELF_SCENE := "res://ui/StoreScreen.tscn"
## The gem packs' columns (the coin offers lie in one row of their own).
const COLUMNS := 3
## The grids' gaps (px), a section's heading line, the gap under it, the coin line's height, a card's smallest and largest
## height (a tall phone grows the pictures, a short window scrolls).
const GAP := 20.0
const HEADING_PX := 36
const HEADING_H := 46.0
const HEADING_ICON := 40.0
const SECTION_GAP := 20
## Under the coin line a little more room: a ribbon hangs RIBBON_UP over its card's top.
const COINS_GAP := 30
const LINE_PX := 22
const LINE_H := 28.0
const CARD_H_MIN := 320.0
const CARD_H_MAX := 560.0
## Inside a card: the side padding, the price button's height and its gap to the foot, the amount line, the ribbon's
## overhang over the card's top and its own height, the bonus tag's type.
const PAD := 14.0
const PRICE_BTN_H := 72.0
const PRICE_PX := 32
const PRICE_ICON := 34.0
const FOOT := 16.0
const AMOUNT_H := 50.0
const AMOUNT_PX := 38
const AMOUNT_MIN_PX := 24
const COIN_PX := 38.0
const RIBBON_H := 40.0
const RIBBON_UP := 18.0
const RIBBON_PX := 19
const RIBBON_W := 0.88
const BONUS_PX := 17
## The ribbons' colours (a key of StorePacks.RIBBONS -> its face).
const RIBBON_FILL := {"most_popular": R.TAG_PURPLE, "best_value": R.TAG_RED}
## The glow behind a picture: its currency's colour (the coins' warm gold), strongest at the middle.
const GLOW := Color(1.0, 0.83, 0.42, 0.42)
const GLOW_ALPHA := 0.42
const RAYS_ALPHA := 0.22
const RAYS_SHADER := preload("res://core/shaders/ui_rays.gdshader")

var _grid: GridContainer
var _offers_row: GridContainer
var _wallet: Control
var _cards: Dictionary = {}
var _toasts: WToasts
## What the taps answered (StorePacks.buy_gems' and buy_coins' dictionaries, newest last): read by the tests and the audit.
var answers: Array = []


# ---------------------------------------------------------------- the frame

func tab_bar() -> String:
	return "store"


func header_right() -> Control:
	_wallet = WMenuHeader.wallets(Currency.balance(StorePacks.coin_currency()), 44, 40.0)
	return _wallet


func build() -> void:
	set_title(Loc.t("ui.store.title"))
	var card_h := card_height()
	# GEMS: the six packs for real money, three a row
	var gems := VBoxContainer.new()
	gems.name = "GemsSection"
	gems.add_theme_constant_override("separation", SECTION_GAP)
	gems.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(gems)
	gems.add_child(_heading("Heading", Loc.t("ui.store.gems_section"), StorePacks.gem_currency()))
	_grid = _make_grid("Grid", COLUMNS)
	gems.add_child(_grid)
	for pk: Dictionary in StorePacks.gem_packs():
		var c := _card(pk, card_h, true)
		_cards[str(pk["id"])] = c
		_grid.add_child(c)
	# COINS: the three offers for gems in one row, their amounts this player's
	var coins := VBoxContainer.new()
	coins.name = "CoinsSection"
	coins.add_theme_constant_override("separation", COINS_GAP)
	coins.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(coins)
	var head := VBoxContainer.new()
	head.name = "CoinsHead"
	head.add_theme_constant_override("separation", 2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coins.add_child(head)
	head.add_child(_heading("CoinsHeading", Loc.t("ui.store.coins_section"), StorePacks.coin_currency()))
	var line := W.text(Loc.t("ui.store.coins_line"), R.body(R.BODY_WEIGHT), LINE_PX, R.SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, LINE_H)
	line.name = "CoinsLine"
	R.no_edge(line)
	head.add_child(line)
	_offers_row = _make_grid("Offers", maxi(StorePacks.offers().size(), 1))
	coins.add_child(_offers_row)
	var bonus := StorePacks.offer_bonuses_now()
	for o: Dictionary in StorePacks.offers():
		var oc := o.duplicate()
		oc["amount"] = StorePacks.coins_now(o)
		oc["bonus"] = int(bonus.get(str(o["id"]), 0))
		var c := _card(oc, card_h, false)
		_cards[str(o["id"])] = c
		_offers_row.add_child(c)
	_toasts = WToasts.new()
	_toasts.name = "Toasts"
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toasts.offset_top = board_top() + W.safe_top() + 40.0
	_toasts.offset_bottom = _toasts.offset_top + 200.0
	add_child(_toasts)


## A section's heading: its currency's icon and the word in capitals, centred.
func _heading(n: String, words: String, cur: String) -> Control:
	var row := HBoxContainer.new()
	row.name = n
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = HEADING_H
	var icon := WCoin.make(HEADING_ICON, W.BRASS, 3.0, cur)
	icon.name = "Icon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var t := W.text(words.to_upper(), R.display(), HEADING_PX, R.CREAM, HORIZONTAL_ALIGNMENT_CENTER, HEADING_H)
	t.name = "Words"
	R.edge(t, HEADING_PX)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(t)
	return row


func _make_grid(n: String, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.name = n
	g.columns = cols
	g.add_theme_constant_override("h_separation", int(GAP))
	g.add_theme_constant_override("v_separation", int(GAP))
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	return g


## A card's height: the board's visible height less the headings, the coin line and the gaps, split over the gem packs'
## rows and the offers' one row (CARD_H_MIN .. CARD_H_MAX), so both sections fill the board between the header and the
## tab bar.
func card_height() -> float:
	var rows := gem_rows() + (1 if not StorePacks.offers().is_empty() else 0)
	var sep := float(content.get_theme_constant("separation")) if content else 30.0
	var fixed := HEADING_H + float(SECTION_GAP) + GAP * float(maxi(gem_rows() - 1, 0)) + sep \
		+ HEADING_H + 2.0 + LINE_H + float(COINS_GAP)
	var room := visible_board_height() - fixed
	return clampf(floorf(room / float(maxi(rows, 1))), CARD_H_MIN, CARD_H_MAX)


## The gem packs' rows (three a row).
static func gem_rows() -> int:
	return maxi(ceili(float(StorePacks.gem_packs().size()) / float(COLUMNS)), 1)


func on_back() -> void:
	go(TITLE)


# ---------------------------------------------------------------- a card

func card_of(id: String) -> Control:
	return _cards.get(id) as Control


## A card: a gem pack (`gem` true: its amount of gems, its real-money price) or a coin offer (its amount the coins it gives
## now, its price in gems).
func _card(pk: Dictionary, h: float, gem: bool) -> Control:
	var id := str(pk["id"])
	var cur := StorePacks.gem_currency() if gem else StorePacks.coin_currency()
	var c := Control.new()
	c.name = ("Pack_%s" if gem else "Offer_%s") % id
	c.set_meta("pack" if gem else "offer", id)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.custom_minimum_size = Vector2(0.0, h)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var face := Panel.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", W.sheet_box(Vector2.ZERO))
	c.add_child(face)
	var ribbon := str(pk["ribbon"])
	var tint := glow_colour(cur)
	# rays behind a ribboned card's picture, a soft glow behind every one
	if ribbon != "":
		var rays := Control.new()
		rays.name = "Rays"
		rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = RAYS_SHADER
		m.set_shader_parameter("color", Color(tint.lightened(0.45), RAYS_ALPHA))
		rays.material = m
		rays.draw.connect(func() -> void: rays.draw_rect(Rect2(Vector2.ZERO, rays.size), Color.WHITE))
		c.add_child(rays)
	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture = _glow_texture(tint)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	c.add_child(glow)
	var art := TextureRect.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.texture = picture_of(pk, cur)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	c.add_child(art)
	# the icon and the amount
	var amount := HBoxContainer.new()
	amount.name = "Amount"
	amount.alignment = BoxContainer.ALIGNMENT_CENTER
	amount.add_theme_constant_override("separation", 8)
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(COIN_PX, W.BRASS, 3.0, cur)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(coin)
	var n := W.text(W.num(int(pk["amount"])), R.display(), AMOUNT_PX, amount_colour(cur), HORIZONTAL_ALIGNMENT_LEFT,
		float(AMOUNT_PX))
	n.name = "Gems" if gem else "Coins"
	R.edge(n, AMOUNT_PX, true)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(n)
	c.add_child(amount)
	# the price: green; a gem pack's real money (it buys nothing yet), a coin offer's gems
	var pad_v := maxf((PRICE_BTN_H - 2.0 * R.BUTTON_EDGE - float(PRICE_PX)) * 0.5, 0.0)
	var parts: Array = [str(pk["price_text"])] if gem else [{"coin": PRICE_ICON, "fill": W.BRASS,
		"currency": StorePacks.pay_currency()}, W.num(int(pk["gems"]))]
	var b := WButton.make(parts, PRICE_PX, WButton.PRIMARY, R.BUTTON_EDGE, R.BUTTON_BASE, pad_v, 18.0, float(PRICE_PX),
		WButton.GREEN)
	b.name = "Price"
	b.set_meta("pack" if gem else "offer", id)
	if gem:
		b.pressed.connect(press_price.bind(id))
	else:
		b.set_meta("price", int(pk["gems"]))
		b.pressed.connect(press_offer.bind(id))
	c.add_child(b)
	if ribbon != "" and RIBBON_FILL.has(ribbon):
		c.add_child(_ribbon(ribbon))
	var bonus := int(pk.get("bonus", 0))
	if bonus > 0:
		c.add_child(_bonus_tag(bonus))
	c.resized.connect(_lay_card.bind(c))
	return c


## The glow's colour behind a picture of currency `cur`: the coins' warm gold, another currency's own colour.
static func glow_colour(cur: String) -> Color:
	if Currency.of(cur) == Currency.DEFAULT:
		return Color(GLOW, 1.0)
	return Currency.colour(cur)


## The amount's colour: gold's numbers in gold, another currency's in its colour lifted towards white.
static func amount_colour(cur: String) -> Color:
	if Currency.of(cur) == Currency.DEFAULT:
		return R.GOLD_TEXT
	return Currency.colour(cur).lerp(Color.WHITE, 0.35)


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
	amount.position = Vector2(PAD, b.position.y - 8.0 - AMOUNT_H)
	amount.size = Vector2(w - 2.0 * PAD, AMOUNT_H)
	_fit_amount(amount, w - 2.0 * PAD)
	var top := RIBBON_H - RIBBON_UP + 6.0 if c.has_node("Ribbon") else PAD
	var art_rect := Rect2(PAD, top, w - 2.0 * PAD, amount.position.y - 4.0 - top)
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
		var rs := side * 1.5
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
		t.position = Vector2(w - PAD * 0.5 - ts.x, top + 2.0)
	c.queue_redraw()


## The amount's number shrinks (to AMOUNT_MIN_PX at least) until the icon and it fit the card's width (a coin offer late in
## the game: "270,000").
static func _fit_amount(amount: Control, room: float) -> void:
	var n: WText = null
	var icon_w := 0.0
	for ch in amount.get_children():
		if ch is WText:
			n = ch
		elif ch is Control:
			icon_w += (ch as Control).custom_minimum_size.x
	if n == null:
		return
	var free := room - icon_w - float(amount.get_theme_constant("separation"))
	var px := AMOUNT_PX
	n.font_size = px
	while px > AMOUNT_MIN_PX and n.text_width() > free:
		px -= 1
		n.font_size = px


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


## The "+N% BONUS" tag: a gold tag with navy words (StorePacks' N).
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
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	var t := W.text(Loc.t("ui.store.bonus", {"percent": str(n)}).to_upper(), R.body(R.BOLD_WEIGHT), BONUS_PX, R.NAVY,
		HORIZONTAL_ALIGNMENT_CENTER, float(BONUS_PX))
	t.name = "Words"
	R.no_edge(t)
	p.add_child(t)
	return p


## A card's picture: its file, else its currency's icon (a gem pack whose picture is not painted yet shows the gem).
static func picture_of(pk: Dictionary, cur: String = "gold") -> Texture2D:
	var path := str(pk.get("picture", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	return WCoin.art_of(cur)


static var _glow_texs: Dictionary = {}


static func _glow_texture(tint: Color) -> GradientTexture2D:
	var key := tint.to_html(false)
	if not _glow_texs.has(key):
		var col := Color(tint, GLOW_ALPHA)
		var g := Gradient.new()
		g.set_color(0, col)
		g.set_color(1, Color(col, 0.0))
		g.add_point(0.45, Color(col, col.a * 0.45))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		_glow_texs[key] = tex
	return _glow_texs[key]


# ---------------------------------------------------------------- a gem pack's price tapped

## A finger on gem pack `id`'s price (the button's press has played): there is no billing yet (StorePacks.buy_gems), so the
## wallet stays as it is and the player is told in the kit's modal (one at a time: a second tap only replaces it).
func press_price(id: String) -> void:
	var ans := StorePacks.buy_gems(id)
	answers.append(ans)
	if bool(ans.get("ok", false)):
		return
	WConfirm.shell(self, {"title": Loc.t("ui.store.not_yet_title"), "body": Loc.t("ui.store.not_yet_body"),
		"buttons": [{"id": "ok", "text": Loc.t("ui.store.not_yet_ok"), "role": WButton.GOLD}], "cancel_id": "ok"})


# ---------------------------------------------------------------- a coin offer tapped

## A finger on coin offer `id`'s price: short of gems, the message (how many more, GET GEMS scrolls up to the packs);
## else the question "Buy 5,500 coins for 500 gems?", whose buy button carries the gem and the price.
func press_offer(id: String) -> void:
	var o := StorePacks.offer(id)
	if o.is_empty():
		return
	var cost := int(o["gems"])
	var coins := StorePacks.coins_now(o)
	var pay := StorePacks.pay_currency()
	var short := cost - Currency.balance(pay)
	if short > 0:
		var ans := {"ok": false, "reason": "short", "id": id, "gems": cost, "coins": coins, "short": short}
		answers.append(ans)
		W.sfx("ui_locked")
		show_short(short)
		return
	WConfirm.open(self, Loc.t("ui.store.offer_title"),
		Loc.t("ui.store.offer_body", {"coins": W.num(coins), "gems": W.num(cost)}),
		Loc.t("ui.store.offer_buy"), Loc.t("ui.store.offer_not_now"), func() -> void: buy_offer(id), Callable(), "buy",
		WButton.price_parts(cost, Loc.t("ui.store.offer_buy"), R.MODAL_BUTTON_PX, pay))


## Buys coin offer `id` (StorePacks.buy_coins): the gems leave, the coins come, both wallets count again, a toast. True when
## it was bought; short (the wallet changed meanwhile) shows the message instead.
func buy_offer(id: String) -> bool:
	var ans := StorePacks.buy_coins(id)
	answers.append(ans)
	if not bool(ans.get("ok", false)):
		if str(ans.get("reason", "")) == "short":
			W.sfx("ui_locked")
			show_short(int(ans.get("short", 1)))
		return false
	W.sfx("ui_buy")
	refresh_wallets()
	if _toasts:
		_toasts.push(Loc.t("toast.store.coins_bought", {"coins": W.num(int(ans["coins"]))}), W.PAPER,
			WCoin.art_of(StorePacks.coin_currency()))
	var card := card_of(id)
	if card:
		WCelebrate.burst(self, card.get_global_rect().get_center(), get_child_count(), 1.0)
	return true


## The message when the wallet is short of `short` gems: how many more are needed; GET GEMS scrolls up to the gem packs.
func show_short(short: int) -> void:
	var pay := StorePacks.pay_currency()
	WConfirm.shell(self, {"title": Loc.t("ui.store.short_title", {"word": Currency.word_of(pay)}),
		"body": Loc.t("ui.store.short_body", {"amount": W.num(short), "word": Currency.word_of(pay)}),
		"buttons": [{"id": "cancel", "text": Loc.t("ui.store.offer_not_now"), "role": WButton.SLATE},
			{"id": "gems", "text": Loc.t("ui.store.get_gems", {"word": Currency.word_of(pay)}), "role": WButton.GOLD}],
		"cancel_id": "cancel",
		"on_answer": func(a: String) -> void:
			if a == "gems":
				scroll_to_gems()})


## The board back at its top, where the gem packs are.
func scroll_to_gems() -> void:
	if scroll == null:
		return
	var tw := create_tween()
	tw.tween_property(scroll, "scroll_vertical", 0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The purse and the gem wallet count again (after a purchase or a debug grant).
func refresh_wallets() -> void:
	if _wallet == null or not is_instance_valid(_wallet):
		return
	for a in _wallet.find_children("Amount", "", true, false):
		(a as WText).text = W.num(Currency.balance(StorePacks.coin_currency()))
	WMenuHeader.refresh_wallets(_wallet)
