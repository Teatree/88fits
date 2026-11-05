## The slab button: Alfa Slab One on a square box with an ink border and a hard shadow. Variants: primary (brass,
## darkens to brass dark while held; since pass 46 brass means buying or the one big go, PLAY), secondary (paper),
## danger (rock with paper text), upgrade (turquoise with paper text, darker while held: the way to the Upgrade board,
## which wants to be seen without looking like a purchase), locked (aged at 45 %, still emits `pressed` so the screen can
## say why). The label is parts: text runs in their own colours and coins ("REROLL ×1", "SELL ○ +4", "RANK 2 ○ 252").
## Pass 122 (lane UIKIT_A), under Royale: the same button wears a `role` (Garry: button colours mean
## something): gold = happens now (START, TAKE IT, RESUME, DEAL, CLAIM), green = buys, blue = opens something (DETAILS,
## CHOOSE, UPGRADE), slate = everything else, red = danger, locked = grey at 75 %. A screen that says nothing gets the
## variant's role (R.role_of: primary -> gold, danger -> red, upgrade -> blue, secondary -> slate); `make`'s `p_role` or
## set_role says otherwise. The face is HardBox's two-tone fill on its coloured and navy base (pressed: down 8 px, no
## base), the label Ultra (Rubik 700 under 28 px) in navy on gold and cream with the navy edge on the rest, a
## {"count": n} part a navy pill with a gold number (grey at 0). Wanted draws exactly as before.
class_name WButton
extends WTap

const PRIMARY := "primary"
const SECONDARY := "secondary"
const DANGER := "danger"
const UPGRADE := "upgrade"
## The upgrade button while held: its turquoise a shade darker, as a primary goes to brass dark.
const UPGRADE_DOWN := Color("2f6d69")
## The Royale roles (pass 122), by name.
const GOLD := "gold"
const GREEN := "green"
const BLUE := "blue"
const SLATE := "slate"
const RED := "red"
const LOCKED := "locked"

var variant := SECONDARY
## The Royale role (pass 122): one of R.ROLE_NAMES; "" at make takes the variant's. Wanted ignores it.
var role := ""
var font_size := 34
var line_h := 0.0   # 0 = the font's own height; the mock's `line-height:1` buttons pass px
var _row: HBoxContainer
var _parts: Array = []
var _border := 5
var _shadow := 8
var _pad_v := 26.0
var _pad_h := 22.0
## Pass 123 (lane KIT2): the label's colour in place of the role's (alpha 0 = the role's): a short price's grey.
var ink_override := Color(0, 0, 0, 0)


## parts: Array of items, each a String (ink), [text, colour], [text, colour, px], {"coin": px, "fill": colour} or
## (pass 122) {"count": n}, (pass 123) {"ad": px} (the drawn ad icon, W.glyph "ad") or {"glyph": kind, "px": n} (any
## W.glyph). `p_role` (pass 122): the Royale role; "" = the variant's. WButton.price (pass 123) makes a price button.
static func make(parts: Array, px: int = 34, p_variant: String = SECONDARY, border: int = 5, shadow: int = 8,
		pad_v: float = 26.0, pad_h: float = 22.0, p_line_h: float = 0.0, p_role: String = "") -> WButton:
	var b := WButton.new()
	b.variant = p_variant
	b.role = p_role if p_role != "" else R.role_of(p_variant)
	b.font_size = px
	b.line_h = p_line_h
	b._border = border
	b._shadow = shadow
	b._pad_v = pad_v
	b._pad_h = pad_h
	b._build_boxes()
	b._row = HBoxContainer.new()
	b._row.alignment = BoxContainer.ALIGNMENT_CENTER
	b._row.add_theme_constant_override("separation", int(px * 0.3))
	b._row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(b._row)
	b.set_parts(parts)
	return b


## The box and its held copy from the variant (Wanted) and the role (Royale, through HardBox.role).
func _build_boxes() -> void:
	var fill := W.PAPER
	match variant:
		PRIMARY:
			fill = W.BRASS
		DANGER:
			fill = W.ROCK
		UPGRADE:
			fill = W.TURQUOISE
	var hb := W.box(fill, _border, _shadow).pad(_pad_h + _border, _pad_v + _border, _pad_h + _border, _pad_v + _border)
	hb.role = role
	box = hb
	var held_fill := fill
	match variant:
		PRIMARY:
			held_fill = W.BRASS_DARK
		UPGRADE:
			held_fill = UPGRADE_DOWN
	box_down = hb.pressed(held_fill)


## The Royale role again (pass 122): the face and the label follow; nothing changes under Wanted.
func set_role(r: String) -> void:
	role = r
	_build_boxes()
	set_parts(_parts)


func set_parts(parts: Array) -> void:
	_parts = parts
	# out of the row at once (pass 122): label_text reads the new parts in the same frame (a tool, set_role)
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	var ink := W.PAPER if variant == DANGER or variant == UPGRADE else W.INK
	ink = R.role(role)["text"]
	if ink_override.a > 0.0:
		ink = ink_override
	var runs: Array = []
	var flush := func():
		if runs.is_empty():
			return
		var t := W.text("", W.slab_for(font_size), font_size, ink, HORIZONTAL_ALIGNMENT_CENTER, line_h)
		t.runs = runs.duplicate()
		if role == GOLD:
			# navy on gold: a navy edge would only fatten it
			R.no_edge(t)
		else:
			# pass 123 (Garry: "add contour, or drop shadow to texts inside the buttons"): every label on a coloured face
			# wears the navy contour and a drop straight down, Rubik labels under Ultra's minimum too
			t.stroke = maxi(t.stroke, 2)
			t.stroke_color = R.NAVY
			t.shadow = maxi(t.shadow, 3)
			t.shadow_color = R.NAVY
			t.shadow_straight = true
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(t)
		runs.clear()
	for p in parts:
		if p is Dictionary and p.has("coin"):
			flush.call()
			# pass 111 (lane SKINS): {"coin": px, "currency": id} draws that currency's icon (gold's coin by default)
			_row.add_child(WCoin.make(float(p["coin"]), p.get("fill", W.BRASS), float(p.get("border", 3.0)), str(p.get("currency", "gold"))))
		elif p is Dictionary and p.has("count"):
			flush.call()
			_row.add_child(_count_pill(int(p["count"]), ink))
		elif p is Dictionary and p.has("ad"):
			# pass 123 (lane KIT2): the ad icon (Garry, Down!'s GET UP: "instead of text let's use an icon. An icon that's
			# usually used for ads buttons"), in the label's colour with the face's colour cut into it
			flush.call()
			_row.add_child(W.glyph("ad", float(p["ad"]), ink, _cut_colour(ink)))
		elif p is Dictionary and p.has("glyph"):
			# pass 123: any of W.glyph's drawn glyphs ({"glyph": "menu", "px": 40}), in the label's colour
			flush.call()
			_row.add_child(W.glyph(str(p["glyph"]), float(p.get("px", font_size)), p.get("color", ink), _cut_colour(ink)))
		elif p is Array:
			# [text, colour] or [text, colour, px] (a smaller number beside the word: "RANK 2 ○ 252")
			if p.size() > 2:
				runs.append([str(p[0]), p[1], null, int(p[2])])
			else:
				runs.append([str(p[0]), p[1] if p.size() > 1 else null])
		else:
			runs.append([str(p), null])
	flush.call()


## A count inside the button (pass 122): {"count": n} is "×n" as a navy pill with a gold number (grey at 0) under
## Royale; under Wanted the same "×n" in the label's ink (the screens' own "REROLL ×1" runs stay as they are).
func _count_pill(n: int, ink: Color) -> Control:
	var px := maxi(int(round(font_size * 0.7)), R.TAG_PX)
	var pc := PanelContainer.new()
	pc.name = "Count"
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = R.NAVY
	sb.anti_aliasing = true
	sb.set_corner_radius_all(R.RADIUS)
	sb.content_margin_left = px * 0.5
	sb.content_margin_right = px * 0.5
	sb.content_margin_top = px * 0.2
	sb.content_margin_bottom = px * 0.2
	pc.add_theme_stylebox_override("panel", sb)
	var t := W.text("×%d" % n, W.slab_for(px), px, R.GOLD_TEXT if n > 0 else R.MUTED, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	R.no_edge(t)
	pc.add_child(t)
	return pc


## The label as plain text (tests and tools read it): every run and count in order, coins left out.
func label_text() -> String:
	return _label_of(_row)


func _label_of(n: Node) -> String:
	var s := ""
	for c in n.get_children():
		if c is WText:
			var t := c as WText
			if t.runs.is_empty():
				s += t.text
			else:
				for r in t.runs:
					s += str(r[0])
		elif c is PanelContainer:
			s += _label_of(c)
	return s


## The colour cut into a drawn glyph on this face (pass 123): under Royale the face's own colour (the gold top under
## navy ink, the role's bottom under cream), under Wanted the box's fill.
func _cut_colour(ink: Color) -> Color:
	var r := R.role(role)
	return r["top"] if ink.is_equal_approx(R.NAVY) else r["bottom"]


## A price button (pass 123, lane KIT2; the mocks 8_Shop_24_gold "● 230 · BUY", 5_Upgrade "● 100 · CHOOSE"): the coin
## (or `currency`'s icon), the amount, and `word` after a " · ", in `p_role` (green buys, blue opens a choice, gold acts at
## once), `height` tall (R.PRICE_H 64) with `px` type (R.PRICE_PX 28). `short` > 0 (the purse is that much short): the
## locked grey with the price alone (`keep_word` keeps the word) in R.LOCKED_TEXT, `locked` (it still emits `pressed`, so
## the screen can say why: WTap's rule) and the meta "short"; W.price_row puts "n short" beside it. The meta "price" holds
## the amount. Under Wanted the brass (gold, green), turquoise (blue) or paper button with the same label.
static func price(amount: int, word: String = "", p_role: String = GREEN, px: int = R.PRICE_PX, short: int = 0,
		currency: String = "gold", keep_word: bool = false, height: float = R.PRICE_H) -> WButton:
	var is_short := short > 0
	var variant := SECONDARY
	match p_role:
		GOLD, GREEN:
			variant = PRIMARY
		BLUE:
			variant = UPGRADE
		RED:
			variant = DANGER
	var border := R.BUTTON_EDGE
	var pad_v := maxf((height - 2.0 * border - float(px)) * 0.5, 0.0)
	var b := make(price_parts(amount, word if not is_short or keep_word else "", px, currency), px, variant, border, R.BUTTON_BASE,
		pad_v, 22.0, float(px), LOCKED if is_short else p_role)
	b.name = "PriceButton"
	if is_short:
		b.ink_override = R.SHORT_INK
		b.set_parts(b._parts)
		b.locked = true
		b.set_meta("short", short)
	b.set_meta("price", amount)
	return b


## A price's label as a button's parts (pass 126, lane UI; Garry: "Buy Look button doesn't have coins icon on it"): the coin (or
## `currency`'s icon) sized to `px`, the amount, and `word` after a " · ". WButton.price wears it, and so does a question's
## deed that buys (WConfirm.open's `confirm_parts`).
static func price_parts(amount: int, word: String = "", px: int = R.PRICE_PX, currency: String = "gold") -> Array:
	var label := W.num(amount)
	if word != "":
		label += " · " + word
	return [{"coin": maxf(R.PRICE_COIN * float(px) / float(R.PRICE_PX), 16.0), "fill": W.BRASS, "currency": currency}, label]
