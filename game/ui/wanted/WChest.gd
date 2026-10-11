## The chest that opens before the reel runs (pass 46, Garry: "an actual 2d Chest Opening animation that somehow fits
## smoothly with the rest of the UI", after the beats of his Animated Chests reference): it drops in on the lower third
## of the screen (pass 47: "The Chest opening animation should be on the lower part of the Screen"), knocks three times
## (a jiggle and a thud each), its lid cracks open on a dark inside, then swings up and flops back while the light pours
## out and climbs up the screen into the reel's row (the rays grow over RAYS_GROW), and it sinks and fades as the reel
## rises out of that light, about LIFE seconds in all. The pose is a pure function of the time (at), so the chest screen
## drives it from the same tween as the reel: a speed-up or a skip moves both. The paintings are art/ui/wanted/chest_closed.png, chest_cracked.png and chest_open.png (the
## boss's violet chest: boss_chest_*.png); until all three of a set exist the chest is drawn in the kit's look, walnut
## (violet for the boss) in an ink outline with brass bands, a lock plate and a lid that lifts. Never takes a touch.
class_name WChest
extends Control

## The beats, in seconds from the start: landed, the three knocks, the lid cracking, the lid open; the chest screen
## starts the reel at SPIN_AT, and by LIFE the chest has sunk away.
const DROP := 0.2
## How far above its spot the chest starts its drop, in px.
const DROP_HEIGHT := 200.0
const KNOCKS := [0.26, 0.4, 0.54]
const KNOCK_LEN := 0.13
const CRACK := 0.64
const OPEN := 0.74
## The reel starts once the light has climbed most of the way to it (pass 47: the chest sits low, the reel high).
const SPIN_AT := 0.92
const LIFE := 1.25
## How long the rays take to reach their full length, from OPEN.
const RAYS_GROW := 0.3
const ART := "res://art/ui/wanted/%schest_%s.png"
const FRAMES := ["closed", "cracked", "open"]
const CLOSED := 0
const CRACKED := 1
const OPENED := 2
## The knock: its own sound when the sound map has it, else a knock on rock.
const KNOCK_SOUND := "ui_chest_knock"
const KNOCK_FALLBACK := "en_golem_hit"
const WALNUT := Color("6e4529")
const WALNUT_DARK := Color("472b19")
const VIOLET := Color("6f4796")
const VIOLET_DARK := Color("472c63")

## The chest's width; its middle sits on `center` while it is closed.
var side := 420.0
var center := Vector2(540, 678)
var boss := false
## Where the intro is (seconds), and what that makes of the chest.
var t := 0.0
var frame := CLOSED
var light := 0.0
var _frames: Array = []   # the three paintings, or empty: drawn
var _y := 0.0
var _rot := 0.0
var _squash := Vector2.ONE
var _beat := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A fresh chest for a new opening: walnut or the boss's violet, standing at `p_center`, `p_side` wide.
func setup(p_boss: bool, p_center: Vector2, p_side: float = 420.0) -> WChest:
	boss = p_boss
	center = p_center
	side = p_side
	_frames = paintings(boss)
	_beat = -1
	visible = true
	at(0.0)
	return self


## The three paintings of a chest (closed, cracked, open), or [] while any of them is missing.
static func paintings(for_boss: bool) -> Array:
	var out: Array = []
	for f: String in FRAMES:
		var path := ART % ["boss_" if for_boss else "", f]
		if not ResourceLoader.exists(path):
			return []
		var tex := load(path) as Texture2D
		if tex == null:
			return []
		out.append(tex)
	return out


## Whether the chest is painted (else drawn).
func painted() -> bool:
	return _frames.size() == FRAMES.size()


## The chest `p_t` seconds into its intro: where it is, how it leans and squashes, which frame shows, how much light
## pours out and how faded it is. A knock passed since the last call plays its sound, only the latest one (a skip that
## jumps over the knocks sounds one knock).
func at(p_t: float) -> void:
	t = p_t
	var y := 0.0
	var rot := 0.0
	var sq := Vector2.ONE
	var alpha := 1.0
	# the drop: falling in from a little above (clear of the title), squashing as it lands
	if t < DROP:
		var k := t / DROP
		y = -DROP_HEIGHT * (1.0 - k * k)
		alpha = clampf(t / 0.08, 0.0, 1.0)
	else:
		sq *= _bump(t - DROP, 0.1, Vector2(1.12, 0.86))
	# three knocks from inside: a lean right, left, right, each with a hop
	for n: int in range(KNOCKS.size()):
		var u := (t - float(KNOCKS[n])) / KNOCK_LEN
		if u > 0.0 and u < 1.0:
			var s := sin(u * PI)
			rot += (0.085 if n % 2 == 0 else -0.085) * s
			y -= 16.0 * s
			sq *= Vector2(1.0 + 0.06 * s, 1.0 - 0.06 * s)
	# the lid cracks, then swings open and flops back
	frame = CLOSED if t < CRACK else (CRACKED if t < OPEN else OPENED)
	if t >= OPEN:
		sq *= _bump(t - OPEN, 0.14, Vector2(0.92, 1.1))
	elif t >= CRACK:
		sq *= _bump(t - CRACK, 0.08, Vector2(0.96, 1.06))
	light = clampf((t - OPEN) / 0.08, 0.0, 1.0) if t >= OPEN else 0.0
	# the sink: down and away while the reel spins up out of it
	if t > SPIN_AT:
		var k2 := clampf((t - SPIN_AT) / (LIFE - SPIN_AT), 0.0, 1.0)
		y += 110.0 * k2 * k2
		alpha = 1.0 - k2
	_y = y
	_rot = rot
	_squash = sq
	modulate.a = alpha
	visible = t < LIFE
	_sound()
	queue_redraw()


## Whether the intro is still before the reel's start.
func before_spin() -> bool:
	return t < SPIN_AT


## A squash that springs back: `to` at once, nothing by `length`, with a small overshoot on the way.
static func _bump(dt: float, length: float, to: Vector2) -> Vector2:
	if dt < 0.0 or dt >= length:
		return Vector2.ONE
	var k := dt / length
	var w := (1.0 - k) * cos(k * PI * 1.5)
	return Vector2.ONE + (to - Vector2.ONE) * w


## The knocks sound; the lid's crack is silent since pass 67 (the chest's burst, pk_chest_open, played in the world when
## it was touched: Game.open_chest, and played again here before).
func _sound() -> void:
	var last := -1
	for k: int in range(KNOCKS.size()):
		if t >= float(KNOCKS[k]):
			last = k
	if last <= _beat:
		return
	_beat = last
	W.sfx(knock_sound())


static var _knock_id := ""


## The knock's sound id: ui_chest_knock once the sound map has it, else a knock on rock.
static func knock_sound() -> String:
	if _knock_id == "":
		_knock_id = KNOCK_FALLBACK
		var reg := W.node("Registry")
		if reg and reg.get("soundmap") and reg.soundmap.has_method("entry") and not (reg.soundmap.entry(KNOCK_SOUND) as Dictionary).is_empty():
			_knock_id = KNOCK_SOUND
	return _knock_id


func _draw() -> void:
	# the chest stands on its foot, so it leans and squashes from the ground
	var foot := center + Vector2(0.0, side * 0.3 + _y)
	draw_set_transform(foot, _rot, _squash)
	if painted():
		if light > 0.0:
			_draw_light(Vector2(0.0, -side * 0.42))
		var tex: Texture2D = _frames[frame]
		var h := side * float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
		draw_texture_rect(tex, Rect2(-side * 0.5, -h, side, h), false)
	else:
		_draw_drawn()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The light out of the open chest: a fan of brass rays fading upwards, turning a little, and a paper glow at the mouth.
## The rays grow from the mouth to their full reach over RAYS_GROW (pass 47: the light rises into the reel above).
func _draw_light(mouth: Vector2) -> void:
	var turn := t * 0.6
	var grow := clampf((t - OPEN) / RAYS_GROW, 0.0, 1.0)
	grow = 0.12 + 0.88 * (1.0 - pow(1.0 - grow, 3.0))
	for k in 9:
		var ang := -PI * 0.5 + (float(k) - 4.0) * 0.19 + sin(turn + k * 1.3) * 0.03
		var half := 0.05 + 0.02 * sin(k * 1.7)
		var reach := (760.0 + 160.0 * sin(k * 2.3)) * grow
		draw_polygon(PackedVector2Array([mouth, mouth + Vector2.from_angle(ang - half) * reach, mouth + Vector2.from_angle(ang + half) * reach]),
			PackedColorArray([Color(W.BRASS, 0.55 * light), Color(W.BRASS, 0.0), Color(W.BRASS, 0.0)]))
	for k in 6:
		draw_circle(mouth, 130.0 - k * 20.0, Color(W.PAPER, 0.07 * light), true, -1.0, true)


## The chest in the kit's look, for as long as it is not painted: walnut (the boss's violet) in an ink outline, brass
## bands and a lock plate, the lid an arch that lifts on a dark inside and then stands open behind it.
func _draw_drawn() -> void:
	var wd := side * 0.86
	var hb := side * 0.38
	var hl := side * 0.22
	var wood := VIOLET if boss else WALNUT
	var dark := VIOLET_DARK if boss else WALNUT_DARK
	match frame:
		OPENED:
			# the lid swung back: its underside stands up behind the mouth, brass rim at the top
			var lb := -hb - 6.0
			var lt := lb - hl * 1.3
			_poly(PackedVector2Array([Vector2(-wd * 0.5 + 6.0, lb), Vector2(wd * 0.5 - 6.0, lb), Vector2(wd * 0.46, lt), Vector2(-wd * 0.46, lt)]), dark)
			_box(Rect2(-wd * 0.46, lt - 2.0, wd * 0.92, 18.0), W.BRASS, 4.0)
			if light > 0.0:
				_draw_light(Vector2(0.0, -hb - 18.0))
			# the dark inside, and what is in it shining
			_poly(PackedVector2Array([Vector2(-wd * 0.5 + 8.0, -hb + 4.0), Vector2(wd * 0.5 - 8.0, -hb + 4.0), Vector2(wd * 0.5 - 30.0, -hb - 34.0), Vector2(-wd * 0.5 + 30.0, -hb - 34.0)]), W.INK)
			_ellipse(Vector2(0.0, -hb - 14.0), wd * 0.3, 14.0, Color(W.BRASS, 0.85 * light))
			_ellipse(Vector2(0.0, -hb - 14.0), wd * 0.16, 7.0, Color(W.PAPER, 0.9 * light))
			_body(wd, hb, wood, dark, true)
		CRACKED:
			# the lid lifts on the dark inside, a line of light across it
			var lift := 34.0
			draw_rect(Rect2(-wd * 0.5 + 14.0, -hb - lift - 6.0, wd - 28.0, lift + 10.0), W.INK)
			draw_rect(Rect2(-wd * 0.5 + 34.0, -hb - lift * 0.5 - 3.0, wd - 68.0, 6.0), Color(W.BRASS, 0.95))
			_body(wd, hb, wood, dark, true)
			_lid(wd, hl * 0.9, -hb - lift, wood, dark)
		_:
			_body(wd, hb, wood, dark, false)
			_lid(wd, hl, -hb, wood, dark)
			_lock(-hb - 14.0)


## The body: a box in an ink outline, two planks, two brass bands; the lock plate on its top edge once the lid is up.
func _body(wd: float, hb: float, wood: Color, dark: Color, lid_up: bool) -> void:
	_box(Rect2(-wd * 0.5, -hb, wd, hb), wood, 6.0)
	for k: int in [1, 2]:
		var y := -hb + hb * float(k) / 3.0
		draw_line(Vector2(-wd * 0.5 + 6.0, y), Vector2(wd * 0.5 - 6.0, y), dark, 4.0)
	for sx: float in [-1.0, 1.0]:
		_box(Rect2(sx * wd * 0.3 - 13.0, -hb, 26.0, hb), W.BRASS, 4.0)
	if lid_up:
		_lock(-hb)


## The lid: an arch from `bottom` up `h`, its bands following the curve and a dark rim along its foot.
func _lid(wd: float, h: float, bottom: float, wood: Color, dark: Color) -> void:
	var arch := PackedVector2Array()
	for k in 25:
		var a := PI + PI * float(k) / 24.0
		arch.append(Vector2(cos(a) * wd * 0.5, bottom + sin(a) * h))
	_poly(arch, wood)
	for sx: float in [-1.0, 1.0]:
		var x0 := sx * wd * 0.3
		var xo := absf(x0) + 13.0
		var top := bottom - h * sqrt(maxf(1.0 - pow(xo / (wd * 0.5), 2.0), 0.0))
		_box(Rect2(x0 - 13.0, top, 26.0, bottom - top), W.BRASS, 4.0)
	_box(Rect2(-wd * 0.5, bottom - 16.0, wd, 16.0), dark, 4.0)


## The lock plate hanging from `top`, with its keyhole.
func _lock(top: float) -> void:
	_box(Rect2(-26.0, top, 52.0, 60.0), W.BRASS, 4.0)
	draw_circle(Vector2(0.0, top + 24.0), 7.0, W.INK, true, -1.0, true)
	draw_rect(Rect2(-3.5, top + 26.0, 7.0, 18.0), W.INK)


func _box(r: Rect2, fill: Color, ink: float) -> void:
	if ink > 0.0:
		draw_rect(r, W.INK)
		draw_rect(r.grow(-ink), fill)
	else:
		draw_rect(r, fill)


func _poly(pts: PackedVector2Array, fill: Color) -> void:
	draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, W.INK, 6.0, true)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	if col.a <= 0.0:
		return
	var pts := PackedVector2Array()
	for k in 32:
		var a := TAU * float(k) / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
