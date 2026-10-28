## The coin, wherever gold shows (the HUD, the title and menu purses, the Upgrade prices and BUY, Results, the chest's
## SELL and gold, Down!, the shop, the stage clear, a skip): the painted coin, art/ui/wanted/coin.png (pass 46, Garry: "the
## Coin has an actual Icon instead of that lazy looking circle"), drawn to the coin's square; until it is painted, a
## brass disc with an ink ring (paper on a brass button, so it still reads). A coin that is not the player's (gold left
## in the sand, a price the purse cannot reach) passes `fill` AGED: the drawn disc turns aged, the painting fades.
class_name WCoin
extends Control

const ART := "res://art/ui/wanted/coin.png"
## How much of the painting shows on an aged coin.
const AGED_ALPHA := 0.5

static var _art: Texture2D = null
static var _art_looked := false

var side := 34.0:
	set(v):
		side = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var fill := W.BRASS
var border := 3.0
## Pass 111 (lane SKINS): the currency the coin stands for (content/currencies): its own icon from the registry
## (Currency.icon), gold's being the coin. Every price plate and BUY names the currency of what it sells.
var currency := "gold":
	set(v):
		currency = v if v != "" else "gold"
		queue_redraw()
## icons of the other currencies, by id (gold keeps _art, which set_art can stand in for)
static var _arts: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func make(px: float, f: Color = W.BRASS, b: float = 3.0, cur: String = "gold") -> WCoin:
	var c := WCoin.new()
	c.side = px
	c.fill = f
	c.border = b
	c.currency = cur
	return c


## The painted coin, looked up once (null until art/ui/wanted/coin.png exists: the drawn disc stands in). Pass 111: the
## gold currency's own icon (content/currencies/gold) when the registry has one, else ART.
static func art() -> Texture2D:
	if not _art_looked:
		_art_looked = true
		_art = Currency.icon("gold")
		if _art == null:
			_art = (load(ART) as Texture2D) if ResourceLoader.exists(ART) else null
	return _art


## The icon of currency `cur` (pass 111): gold's is art(); another's its registry icon (null: the drawn disc).
static func art_of(cur: String) -> Texture2D:
	if cur == "" or Currency.of(cur) == "gold":
		return art()
	if not _arts.has(cur):
		_arts[cur] = Currency.icon(cur)
	return _arts[cur]


## Tests and tools: draw `tex` as the coin (null = the drawn disc); `look_again` forgets it and looks for the file again.
static func set_art(tex: Texture2D, look_again: bool = false) -> void:
	_art = tex
	_art_looked = not look_again


func _draw() -> void:
	var tex := art_of(currency)
	if tex:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(side, side)), false, Color(1, 1, 1, AGED_ALPHA) if fill == W.AGED else Color.WHITE)
		return
	var c := Vector2(side, side) * 0.5
	draw_circle(c, side * 0.5, W.INK, true, -1.0, true)
	draw_circle(c, side * 0.5 - border, fill, true, -1.0, true)
