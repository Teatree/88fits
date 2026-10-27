## The run's kill counter under the HUD's clock (pass 109, Garry: "Right under the timer lets add a simple kill counter
## ... a number with a simple icon to the left of it (the icon is of a skull, the skull should look different from the
## boss skull though, maybe no lower jaw). Whenever Player kills an enemy this number grows with a simple ding animation.
## As the frequency of kills increases the dinging gets more intense. The skull makes a ding as well. No sound").
##
## The count is Run.kills (the Results screen's), the skull a jawless cranium drawn here (bone with an ink outline and a
## hard ink shadow: the dome, two eye sockets, the nasal hole, a short row of upper teeth, no lower jaw; the boss badge is
## a whole red-eyed skull with its jaw). The number is paper slab with an ink stroke and shadow, so it reads on any ground.
##
## The ding, one state driven by tick() (no tween per kill, so hundreds of kills a second cost a few float operations):
##  - the kill rate: an estimate in kills a second, decayed with time constant RATE_TAU (a kill adds 1 / RATE_TAU);
##  - heat = ln(1 + rate) / ln(1 + RATE_HOT), clamped to 0..1 (1 kill/s 0.20, 3/s 0.40, 10/s 0.70, 30/s 1.0);
##  - a ding: the counter's scale punches up by POP_MIN..POP_MAX (by heat) and springs back, amp x e^(-POP_DAMP t) x
##    cos(2 pi POP_FREQ t) over POP_TIME; the skull punches SKULL_EXTRA more and tilts SKULL_TILT_COLD..SKULL_TILT_HOT
##    degrees, its side flipping each ding; kills closer together than DING_GAP_COLD..DING_GAP_HOT seconds share the next
##    ding (at most about 16 dings a second);
##  - the number and the skull flash towards gold (cold) or a hot orange (hot) on each ding; at rest they warm from paper
##    to gold with heat (REST_WARM of the way at most);
##  - past SHAKE_FROM heat the counter trembles, at most SHAKE_PX pixels.
class_name WKillCount
extends Control

const NUM_PX := 36
const SKULL_PX := 38.0
const GAP := 8.0
const RATE_TAU := 0.8
const RATE_HOT := 30.0
const POP_MIN := 0.12
const POP_MAX := 0.30
const POP_TIME := 0.32
const POP_DAMP := 11.0
const POP_FREQ := 2.6
const SKULL_EXTRA := 0.35
const SKULL_TILT_COLD := 6.0
const SKULL_TILT_HOT := 14.0
const DING_GAP_COLD := 0.09
const DING_GAP_HOT := 0.06
const REST_WARM := 0.45
const SHAKE_FROM := 0.7
const SHAKE_PX := 3.0
const GOLD := Color("ffc93c")
const HOT := Color("ff7a2e")
## the skull's outline and hard shadow, in px at SKULL_PX
const OUTLINE := 3.0
const SHADOW := 3.0

## the kills shown, the rate estimate (kills a second) and the heat (0..1)
var count := 0
var rate := 0.0
var heat := 0.0
var _num: WText
var _skull: Control
var _bone := W.PAPER
var _since := 99.0     # seconds since the last ding
var _amp := 0.0        # this ding's punch
var _pending := false  # a kill waits for the next ding
var _side := 1.0
var _t := 0.0
var _row_h := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skull = Control.new()
	_skull.name = "Skull"
	_skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skull.size = Vector2(SKULL_PX, SKULL_PX)
	_skull.pivot_offset = _skull.size * 0.5
	_skull.draw.connect(_draw_skull)
	add_child(_skull)
	_num = W.text("0", W.slab(), NUM_PX, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, NUM_PX * 1.15)
	_num.name = "Kills"
	_num.stroke = 4
	_num.shadow = 3
	_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_num)
	_row_h = maxf(NUM_PX * 1.15, SKULL_PX)
	_lay_out()


## The counter's text now (tests).
func text() -> String:
	return _num.text


## The whole counter's scale now (1 at rest).
func pop_scale() -> float:
	return scale.x


## The kill rate's heat for `r` kills a second (0..1).
static func heat_for(r: float) -> float:
	return clampf(log(1.0 + maxf(r, 0.0)) / log(1.0 + RATE_HOT), 0.0, 1.0)


## A ding's punch at heat `h`.
static func pop_amp_for(h: float) -> float:
	return lerpf(POP_MIN, POP_MAX, clampf(h, 0.0, 1.0))


## The least time between two dings at heat `h`.
static func ding_gap(h: float) -> float:
	return lerpf(DING_GAP_COLD, DING_GAP_HOT, clampf(h, 0.0, 1.0))


## The scale's offset `t` seconds into a ding of punch `amp` (0 before and after it).
static func pop_at(t: float, amp: float) -> float:
	if t < 0.0 or t >= POP_TIME:
		return 0.0
	return amp * exp(-POP_DAMP * t) * cos(TAU * POP_FREQ * t)


## Width of the skull and the number side by side, unscaled.
func row_width() -> float:
	return SKULL_PX + GAP + _num.get_combined_minimum_size().x


## Height of the row, unscaled.
func row_height() -> float:
	return _row_h


## One frame: `kills` is the run's count now (Run.kills). A count lower than shown (a new run) is taken at once.
func tick(delta: float, kills: int) -> void:
	if kills < count:
		count = kills
		rate = 0.0
		_pending = false
		_set_text()
	if delta > 0.0:
		rate *= exp(-delta / RATE_TAU)
		_t += delta
		_since += delta
	var fresh := kills - count
	if fresh > 0:
		count = kills
		rate += float(fresh) / RATE_TAU
		_pending = true
		_set_text()
	heat = heat_for(rate)
	if _pending and _since >= ding_gap(heat):
		_pending = false
		_since = 0.0
		_amp = pop_amp_for(heat)
		_side = -_side
	_apply()


func _set_text() -> void:
	_num.text = W.num(count)
	_lay_out()


## The row centred on x 0 (the HUD places this control at the clock's middle), its top at y 0.
func _lay_out() -> void:
	_num.reset_size()
	var ns := _num.get_combined_minimum_size()
	_num.size = ns
	var w := SKULL_PX + GAP + ns.x
	var left := -w * 0.5
	_skull.position = Vector2(left, (_row_h - SKULL_PX) * 0.5)
	_num.position = Vector2(left + SKULL_PX + GAP, (_row_h - ns.y) * 0.5)
	pivot_offset = Vector2(0.0, _row_h * 0.5)


func _apply() -> void:
	var p := pop_at(_since, _amp)
	var env := pop_at(_since, 1.0)
	scale = Vector2.ONE * (1.0 + p)
	_skull.scale = Vector2.ONE * (1.0 + p * SKULL_EXTRA)
	_skull.rotation = deg_to_rad(lerpf(SKULL_TILT_COLD, SKULL_TILT_HOT, heat)) * _side * env if _amp > 0.0 else 0.0
	var rest := W.PAPER.lerp(GOLD, heat * REST_WARM)
	var flash := GOLD.lerp(HOT, heat)
	var c := rest.lerp(flash, clampf(env, 0.0, 1.0) * 0.9)
	if not c.is_equal_approx(_num.color):
		_num.color = c
	if not c.is_equal_approx(_bone):
		_bone = c
		_skull.queue_redraw()
	var shake := 0.0
	if heat > SHAKE_FROM:
		shake = SHAKE_PX * (heat - SHAKE_FROM) / (1.0 - SHAKE_FROM)
	var off := Vector2(sin(_t * 83.0), cos(_t * 67.0)) * shake
	_skull.position.x = _num.position.x - GAP - SKULL_PX + off.x
	_skull.position.y = (_row_h - SKULL_PX) * 0.5 + off.y
	_num.position.y = (_row_h - _num.size.y) * 0.5 + off.y


# ---------------------------------------------------------------- the jawless skull

func _draw_skull() -> void:
	var k := SKULL_PX / 40.0
	_skull_shape(Vector2(SHADOW, SHADOW), OUTLINE, W.INK, k)
	_skull_shape(Vector2.ZERO, OUTLINE, W.INK, k)
	_skull_shape(Vector2.ZERO, 0.0, _bone, k)
	# the eye sockets, the nasal hole (a point up), the upper teeth's gaps
	_skull.draw_colored_polygon(_ellipse(Vector2(13.6, 18.8) * k, 4.6 * k, 5.0 * k), W.INK)
	_skull.draw_colored_polygon(_ellipse(Vector2(26.4, 18.8) * k, 4.6 * k, 5.0 * k), W.INK)
	_skull.draw_colored_polygon(PackedVector2Array([Vector2(20.0, 23.2) * k, Vector2(22.4, 28.0) * k, Vector2(17.6, 28.0) * k]), W.INK)
	for x in [16.6, 20.0, 23.4]:
		_skull.draw_line(Vector2(x, 30.6) * k, Vector2(x, 34.6) * k, W.INK, 1.8 * k, true)


## The skull's silhouette grown by `grow` px: the dome (a circle) and under it the upper face (a block with rounded lower
## corners), narrower than the dome and ending at the upper teeth.
func _skull_shape(off: Vector2, grow: float, col: Color, k: float) -> void:
	_skull.draw_circle(Vector2(20.0, 16.0) * k + off, 15.0 * k + grow, col, true, -1.0, true)
	_skull.draw_rect(Rect2(Vector2(11.0, 18.0) * k + off - Vector2(grow, grow), Vector2(18.0, 13.5) * k + Vector2(grow, grow) * 2.0), col)
	_skull.draw_rect(Rect2(Vector2(14.0, 28.0) * k + off - Vector2(0.0, grow), Vector2(12.0, 6.5) * k + Vector2(0.0, grow * 2.0)), col)
	_skull.draw_circle(Vector2(14.0, 31.5) * k + off, 3.0 * k + grow, col, true, -1.0, true)
	_skull.draw_circle(Vector2(26.0, 31.5) * k + off, 3.0 * k + grow, col, true, -1.0, true)


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
