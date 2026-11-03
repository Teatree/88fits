## A bar: an aged track with an ink border and a hard shadow, and a flat fill. It can carry text inside the fill (the
## results' "Killer Swarm · 6,540") and show a loss hatched in rock and ink at its end (the Stranger's price).
## Pass 122 (lane UIKIT_B), under Royale (W.royale()): a black trough (R.BAR_TROUGH, 6 px corners, no shadow) with the
## fill inset by `border` (at most 3 px) as a bright two-tone band (the top 44 % lifted towards its lip colour, a lip of
## it along the top), brighter and more saturated than the mock's (Garry: the mock's bars "look rather dim and
## unnoticeable"); the Wanted fills map to the kit's (royale_fill: rock -> the boss red, sage -> the HP green, brass ->
## gold, epic -> the XP purple, rare -> the shield blue; a colour of a screen's own keeps itself with a lighter lip), the
## loss hatched red over navy, the gain in the HP green, the text white in the display face with a navy edge. `paint`
## draws the same bar for a screen that draws by hand (the HUD's XP rail and hero bars), `kind_fill` names the fills.
class_name WBar
extends Control

## The Royale shield bar (the hero's shield under his health; R has the other four).
const SHIELD := Color("4fa8ff")
const SHIELD_LIP := Color("b9dcff")
## How far the band's top is lifted towards the lip colour, and the lip's height over the band's (1 to 3 px).
const LIFT := 0.45
const LIP_FRAC := 0.14

var value := 0.5:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var fill := W.ROCK
var track := W.AGED
var border := 4
var shadow := 4
## The part of the bar that is going away (drawn hatched after the fill).
var loss := 0.0
## The last part of the fill that was just gained (pass 72, the Results' unlock progress: this run's share), drawn in
## `gain_fill` at the fill's end.
var gain := 0.0:
	set(v):
		gain = maxf(v, 0.0)
		queue_redraw()
var gain_fill := W.SAGE
var text := ""
var text_px := 28
var text_color := W.INK
## Pass 122 (lane UIHUD): false keeps the Wanted drawing under Royale too (the HUD's boss bar: Garry keeps the boss's
## name and bar exactly as they are, in both themes).
var themed := true


static func make(v: float, f: Color, h: float, p_border: int = 4, p_shadow: int = 4) -> WBar:
	var b := WBar.new()
	b.value = v
	b.fill = f
	b.border = p_border
	b.shadow = p_shadow
	b.custom_minimum_size = Vector2(0, h)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## The Royale fill and lip for a Wanted fill colour: [fill, lip].
static func royale_fill(c: Color) -> Array:
	if c.is_equal_approx(W.ROCK):
		return [R.BAR_BOSS, R.BAR_BOSS_LIP]
	if c.is_equal_approx(W.SAGE):
		return [R.BAR_HP, R.BAR_HP_LIP]
	if c.is_equal_approx(W.BRASS) or c.is_equal_approx(W.BRASS_DARK):
		return [R.BAR_GOLD, R.BAR_GOLD_LIP]
	if c.is_equal_approx(W.EPIC):
		return [R.BAR_XP, R.BAR_XP_LIP]
	if c.is_equal_approx(W.RARE):
		return [SHIELD, SHIELD_LIP]
	return [c, c.lerp(Color.WHITE, 0.55)]


## The Royale fill and lip by name: "xp" (purple), "hp" (green), "shield" (blue), "boss" (red), "gold"; [fill, lip].
static func kind_fill(kind: String) -> Array:
	match kind:
		"xp":
			return [R.BAR_XP, R.BAR_XP_LIP]
		"hp":
			return [R.BAR_HP, R.BAR_HP_LIP]
		"shield":
			return [SHIELD, SHIELD_LIP]
		"boss":
			return [R.BAR_BOSS, R.BAR_BOSS_LIP]
	return [R.BAR_GOLD, R.BAR_GOLD_LIP]


## The Royale bar drawn into `r` of `ci`: the black trough with `radius` corners (-1: 6 px, 3 under 14 px tall), the
## fill `value` of the way across inset by `inset`, its lifted top and its lip; returns the inner rect (the trough
## inside its inset), for whoever adds a loss or a gain.
static func paint(ci: CanvasItem, r: Rect2, value: float, p_fill: Color, lip: Color, inset: float = 2.0, radius: int = -1) -> Rect2:
	var rad := radius if radius >= 0 else (R.RADIUS if r.size.y >= 14.0 else 3)
	ci.draw_style_box(R.flat(R.BAR_TROUGH, rad), r)
	var inner := r.grow(-inset)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return inner
	var fw := inner.size.x * clampf(value, 0.0, 1.0)
	if fw > 0.5:
		fill_band(ci, Rect2(inner.position, Vector2(fw, inner.size.y)), p_fill, lip, maxi(rad - int(inset), 2))
	return inner


## A two-tone band `fr` in `p_fill` with its lip: the body, the top 44 % lifted towards `lip`, a lip along the top.
static func fill_band(ci: CanvasItem, fr: Rect2, p_fill: Color, lip: Color, rad: int) -> void:
	if fr.size.x <= 0.0 or fr.size.y <= 0.0:
		return
	ci.draw_style_box(R.flat(p_fill, rad), fr)
	var split := roundf(fr.size.y * R.BUTTON_SPLIT)
	if split >= 1.0:
		ci.draw_style_box(R.flat(p_fill.lerp(lip, LIFT), rad, [true, true, false, false]), Rect2(fr.position, Vector2(fr.size.x, split)))
	var lip_px := clampf(roundf(fr.size.y * LIP_FRAC), 1.0, 3.0)
	var side := minf(rad * 0.5, fr.size.x * 0.5)
	ci.draw_rect(Rect2(fr.position + Vector2(side, 0.0), Vector2(maxf(fr.size.x - side * 2.0, 0.0), lip_px)), lip)


func _draw() -> void:
	if themed and W.royale():
		_draw_royale()
		return
	var r := Rect2(Vector2.ZERO, size)
	if shadow > 0:
		draw_rect(Rect2(r.position + Vector2(shadow, shadow), r.size), W.INK)
	draw_rect(r, W.INK)
	var inner := r.grow(-border)
	draw_rect(inner, track)
	var fw := inner.size.x * value
	if fw > 0.0:
		draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y)), fill)
		if gain > 0.0:
			var gw := minf(inner.size.x * gain, fw)
			draw_rect(Rect2(inner.position + Vector2(fw - gw, 0), Vector2(gw, inner.size.y)), gain_fill)
	if loss > 0.0:
		var lr := Rect2(inner.position + Vector2(fw, 0), Vector2(inner.size.x * loss, inner.size.y))
		draw_rect(lr, W.INK)
		# rock stripes at 45 degrees over the ink (the mock's 8 px rock, 4 px ink)
		var step := 12.0
		var x := lr.position.x - lr.size.y
		while x < lr.end.x:
			var seg := W.clip_segment(Vector2(x, lr.end.y), Vector2(x + lr.size.y, lr.position.y), lr)
			if seg.size() == 2:
				draw_line(seg[0], seg[1], W.ROCK, 6.0)
			x += step
	if text != "":
		var f := W.slab()
		var base := inner.position.y + (inner.size.y - f.get_height(text_px)) * 0.5 + f.get_ascent(text_px)
		draw_string(f, Vector2(inner.position.x + 14.0, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, text_color)


## The Royale bar (pass 122): the trough, the band, the gain, the loss and the text.
func _draw_royale() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var fl := royale_fill(fill)
	var inset := float(mini(border, 3))
	var inner := paint(self, r, value, fl[0], fl[1], inset)
	var fw := inner.size.x * value
	var rad := maxi((R.RADIUS if r.size.y >= 14.0 else 3) - int(inset), 2)
	if fw > 0.5 and gain > 0.0:
		var gw := minf(inner.size.x * gain, fw)
		var gl := royale_fill(gain_fill)
		fill_band(self, Rect2(inner.position + Vector2(fw - gw, 0), Vector2(gw, inner.size.y)), gl[0], gl[1], rad)
	if loss > 0.0:
		var lr := Rect2(inner.position + Vector2(fw, 0), Vector2(inner.size.x * loss, inner.size.y))
		draw_rect(lr, R.NAVY)
		var red: Color = R.role("red")["bottom"]
		var step := 12.0
		var x := lr.position.x - lr.size.y
		while x < lr.end.x:
			var seg := W.clip_segment(Vector2(x, lr.end.y), Vector2(x + lr.size.y, lr.position.y), lr)
			if seg.size() == 2:
				draw_line(seg[0], seg[1], red, 6.0)
			x += step
	if text != "":
		var f := W.slab_for(text_px)
		var base := inner.position.y + (inner.size.y - f.get_height(text_px)) * 0.5 + f.get_ascent(text_px)
		var at := Vector2(inner.position.x + 14.0, base)
		var col := R.WHITE if text_color.is_equal_approx(W.INK) else R.text_colour(text_color)
		draw_string_outline(f, at + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, 2, R.NAVY)
		draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, 2, R.NAVY)
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_px, col)
