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


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func make(px: float, f: Color = W.BRASS, b: float = 3.0) -> WCoin:
	var c := WCoin.new()
	c.side = px
	c.fill = f
	c.border = b
	return c


## The painted coin, looked up once (null until art/ui/wanted/coin.png exists: the drawn disc stands in).
static func art() -> Texture2D:
	if not _art_looked:
		_art_looked = true
		_art = (load(ART) as Texture2D) if ResourceLoader.exists(ART) else null
	return _art


## Tests and tools: draw `tex` as the coin (null = the drawn disc); `look_again` forgets it and looks for the file again.
static func set_art(tex: Texture2D, look_again: bool = false) -> void:
	_art = tex
	_art_looked = not look_again


func _draw() -> void:
	var tex := art()
	if tex:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(side, side)), false, Color(1, 1, 1, AGED_ALPHA) if fill == W.AGED else Color.WHITE)
		return
	var c := Vector2(side, side) * 0.5
	draw_circle(c, side * 0.5, W.INK, true, -1.0, true)
	draw_circle(c, side * 0.5 - border, fill, true, -1.0, true)
