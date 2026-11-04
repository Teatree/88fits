## The wax seal: rarity as a circle in its colour with an ink border, a darker inset ring and the word in tracked
## Bitter 600 paper (COMMON / RARE / EPIC). Also the NEW BEST seal (rock, two lines, turned). No word when `text_size`
## is 0 (the collection's 44 px seals).
## Pass 122 (lane UIKIT_B), under Royale: the same seal with a navy edge, its fill the kit's rarity base
## (royale_fill: the Wanted seal colours map to R.RARITY, rock to the red role) and the word in cream Rubik 700.
class_name WSeal
extends Control

var side := 96.0:
	set(v):
		side = v
		custom_minimum_size = Vector2(v, v)
		size = Vector2(v, v)
		queue_redraw()
var fill := W.COMMON
var border := 4
var ring := 6
var word := "COMMON"
var text_size := 18
var text_color := W.PAPER
var track := 0.12
var italic := false
## A soft rarity glow behind the seal (the chest's hero seal): concentric rings, no blur.
var glow := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)


func for_rarity(rarity: String, px: float) -> WSeal:
	fill = W.RARITY.get(rarity, W.COMMON)
	word = rarity.to_upper()
	side = px
	border = 3 if px < 80 else (4 if px < 120 else 5)
	ring = 5 if px < 90 else 6
	# the word is sized off the inside of the seal: 18 px on a 96 px seal (16 for COMMON, the longer word)
	var inner := px - border * 2.0
	text_size = 0 if px < 60 else int(round(inner * (0.167 if rarity == "common" else 0.1875)))
	queue_redraw()
	return self


## The seal's colour under Royale: the rarity's base (common, rare, epic), the red role for rock, else the colour itself.
static func royale_fill(c: Color) -> Color:
	if c.is_equal_approx(W.COMMON):
		return R.RARITY["common"]["base"]
	if c.is_equal_approx(W.RARE):
		return R.RARITY["rare"]["base"]
	if c.is_equal_approx(W.EPIC):
		return R.RARITY["epic"]["base"]
	if c.is_equal_approx(W.ROCK):
		return R.role("red")["bottom"]
	return c


func _draw() -> void:
	var ink := R.NAVY
	var body := royale_fill(fill)
	var c := Vector2(side, side) * 0.5
	var r := side * 0.5
	if glow > 0.0:
		for i in 8:
			var k := 1.0 - i / 8.0
			draw_circle(c, r + glow * k, Color(body.r, body.g, body.b, 0.06), true, -1.0, true)
	draw_circle(c, r, ink, true, -1.0, true)
	draw_circle(c, r - border, body, true, -1.0, true)
	draw_arc(c, r - border - ring * 0.5, 0.0, TAU, 64, Color(0, 0, 0, 0.15), ring, true)
	if text_size <= 0 or word == "":
		return
	var f := W.serif(600, italic, W.em(text_size, track))
	var lines := word.split("\n")
	var lh := f.get_height(text_size) * 0.9
	var y0 := c.y - lh * lines.size() * 0.5
	for i in lines.size():
		var w := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		# letter spacing adds after the last glyph too: centre on the ink, not the advance
		w -= W.em(text_size, track)
		var base := y0 + i * lh + (lh - f.get_height(text_size)) * 0.5 + f.get_ascent(text_size)
		draw_string(f, Vector2(c.x - w * 0.5, base), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, R.text_colour(text_color))
