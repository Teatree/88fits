## Pass 106 (lane DRUM; Garry: "When Player picks it up time stops (everything stops, including music). There is an
## animation of 'beating of drums': big drum in the center of the screen fades in, circle waves on the top of it to imitate
## slaps, together they make a small melody of drums, each slap is very noticeably accompanied by the drum compressing and
## stuff. Make it look good. The animation sequence lasts like 2 seconds and then the drum fades away"): the War Drum's
## moment, a screen of the one-screen rule (Game.Modal.DRUM) while the run stands paused behind it.
## Everything is the structure's `params.moment` (content/structures/war_drum/war_drum.json): `seconds` long, the drum
## (`picture`, the structure's own painting cut out by tools/make_drum_moment.py) fading in over `fade_in` and away over
## the last `fade_out`, the head's circle `head` [centre x, centre y, radius] as shares of the picture, and the `hits`
## [{t, s, rim?, big?}]: at each `t` a slap of strength `s` (`rim` at the edge of the head, `big` the last, biggest one).
## A slap: the drum squashes on its stand and springs back past its shape (SQUASH_*, a damped spring), the head flashes,
## waves race out from where it was struck, ink slap lines burst round that spot and the drum alone shakes; the big one
## throws three waves, flashes the screen and brings in the boost in words. The melody (`sound`, synthesised from the same
## hits by tools/synth_sfx.py) plays from the first frame, on its own player, so the hits and the slaps land together.
## Every touch is swallowed while it plays (touches_eaten); it counts its own real seconds (a hit-stop's slowed clock
## does not stretch it). `finished` when it is over; skip() ends it at once (tests, tools).
class_name DrumMoment
extends Control

signal finished

const DRUM_W := 0.66
const DRUM_MID_Y := 0.47
const SQUASH_Y := 0.2
const SQUASH_X := 0.12
const BIG_SQUASH := 1.45
const SPRING_HZ := 7.0
const SPRING_TAU := 0.085
const RING_LIFE := 0.55
const SHAKE_PX := 18.0
const SHAKE_TAU := 0.07
const FLASH_TAU := 0.09
const LINES := 12
const TITLE_PX := 112
const WORDS_PX := 50
const RED := Color(0.86, 0.16, 0.1)

var playing := false
## seconds into the moment
var t := 0.0
## touches swallowed while it played, slaps played (tests, touch_audit)
var touches_eaten := 0
var hits_played := 0
var title := ""
var words := ""
var _seconds := 2.2
var _fade_in := 0.3
var _fade_out := 0.4
var _hits: Array = []
var _next := 0
var _tex: Texture2D = null
var _head := Vector3(0.524, 0.399, 0.266)
var _rings: Array = []          # {t0, at: Vector2 (shares of the head's radius from its centre), s}
var _slap_t := 99.0             # seconds since the last slap
var _slap_s := 0.0
var _slap_at := Vector2.ZERO
var _slap_big := false
var _screen_flash := 0.0
var _words_t := -1.0
var _shake := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _glow: GradientTexture2D
var _player: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	add_child(_player)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 256
	_glow.height = 256


## Plays the moment of `def` (its params.moment); `p_words` is the last line (the boost as it will run).
func open(def: StructureDef, p_words: String = "") -> void:
	var m: Dictionary = def.params.get("moment", {}) if def.params.get("moment", {}) is Dictionary else {}
	_seconds = maxf(float(m.get("seconds", 2.2)), 0.2)
	_fade_in = clampf(float(m.get("fade_in", 0.3)), 0.01, _seconds * 0.5)
	_fade_out = clampf(float(m.get("fade_out", 0.4)), 0.01, _seconds * 0.5)
	var h = m.get("head", [])
	if h is Array and (h as Array).size() >= 3:
		_head = Vector3(float(h[0]), float(h[1]), float(h[2]))
	_hits = []
	for x in m.get("hits", []):
		if x is Dictionary:
			_hits.append(x)
	_hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	var pic := str(m.get("picture", ""))
	_tex = load(pic) as Texture2D if pic != "" and ResourceLoader.exists(pic) else def.icon
	title = def.display_name.to_upper()
	words = p_words.to_upper()
	t = 0.0
	_next = 0
	hits_played = 0
	_rings.clear()
	_slap_t = 99.0
	_slap_s = 0.0
	_screen_flash = 0.0
	_words_t = -1.0
	_shake = Vector2.ZERO
	_rng.randomize()
	playing = true
	visible = true
	_play_sound(str(m.get("sound", "")))
	queue_redraw()


func _play_sound(id: String) -> void:
	if id == "" or Run.sim_mode:
		return
	var row := Registry.soundmap.entry(id)
	var stream: AudioStream = row.get("stream") if not row.is_empty() else null
	if stream == null:
		return
	_player.stream = stream
	_player.volume_db = float(row.get("volume_db", 0.0))
	_player.play()


## Ends it now (a test's or a tool's hand): the boost follows as after a whole one.
func skip() -> void:
	if playing:
		_finish()


func _finish() -> void:
	playing = false
	visible = false
	if _player.playing:
		_player.stop()
	finished.emit()


func _process(delta: float) -> void:
	if not playing:
		return
	# real seconds: a hit-stop that slowed the clock as the drum was used does not stretch the show
	var dt := delta / maxf(Engine.time_scale, 0.01)
	t += dt
	_slap_t += dt
	while _next < _hits.size() and t >= float((_hits[_next] as Dictionary).get("t", 0.0)):
		_slap(_hits[_next])
		_next += 1
	_screen_flash = maxf(_screen_flash - dt * 3.0, 0.0)
	var amp := _slap_s * exp(-_slap_t / SHAKE_TAU) * (1.6 if _slap_big else 1.0)
	_shake = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * SHAKE_PX * amp
	var keep: Array = []
	for r: Dictionary in _rings:
		if t - float(r["t0"]) < RING_LIFE * (1.4 if bool(r.get("big", false)) else 1.0):
			keep.append(r)
	_rings = keep
	if t >= _seconds:
		_finish()
		return
	queue_redraw()


func _slap(h: Dictionary) -> void:
	hits_played += 1
	var s := clampf(float(h.get("s", 1.0)), 0.05, 1.5)
	var big := bool(h.get("big", false))
	_slap_t = 0.0
	_slap_s = s
	_slap_big = big
	if bool(h.get("rim", false)):
		# the edge of the head, left or right in turn
		var side := -1.0 if hits_played % 2 == 0 else 1.0
		var a := PI * (0.5 - side * 0.32) + _rng.randf_range(-0.15, 0.15)
		_slap_at = Vector2(cos(a), -sin(a)).rotated(PI) * 0.86
	elif big:
		_slap_at = Vector2.ZERO
	else:
		_slap_at = Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.25, 0.25))
	_rings.append({"t0": t, "at": _slap_at, "s": s, "big": big})
	if big or s >= 0.7:
		_rings.append({"t0": t + 0.06, "at": _slap_at, "s": s * 0.7, "big": big})
	if big:
		_rings.append({"t0": t + 0.13, "at": _slap_at, "s": s * 0.5, "big": true})
		_screen_flash = 1.0
		_words_t = t


func _input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion:
		if (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
			touches_eaten += 1
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if playing:
		accept_event()


## 0..1: in over fade_in, out over the last fade_out.
func alpha_at(time: float) -> float:
	var a_in := clampf(time / _fade_in, 0.0, 1.0)
	var a_out := clampf((_seconds - time) / _fade_out, 0.0, 1.0)
	return minf(1.0 - pow(1.0 - a_in, 2.0), a_out * a_out * (3.0 - 2.0 * a_out))


## The drum's size against its rest: up from 0.72 with a little overshoot as it comes, out to 1.14 as it goes.
func appear_at(time: float) -> float:
	if time < _fade_in:
		var f := time / _fade_in
		var c := 1.7
		var e := 1.0 + (c + 1.0) * pow(f - 1.0, 3.0) + c * pow(f - 1.0, 2.0)
		return lerpf(0.72, 1.0, e)
	var out := clampf((time - (_seconds - _fade_out)) / _fade_out, 0.0, 1.0)
	return 1.0 + 0.14 * out * out


## The squash now: positive squashed (the slap), negative stretched (the spring back past its shape).
func squash() -> float:
	if _slap_t > 1.0:
		return 0.0
	return _slap_s * (BIG_SQUASH if _slap_big else 1.0) * exp(-_slap_t / SPRING_TAU) * cos(TAU * SPRING_HZ * _slap_t)


## Where the drum is drawn now (the picture's rect on the screen, squashed on its stand's feet).
func drum_rect() -> Rect2:
	if _tex == null:
		return Rect2()
	var vp := size
	var k := squash()
	var sc := appear_at(t)
	var dw := vp.x * DRUM_W * sc
	var dh := dw * float(_tex.get_height()) / maxf(float(_tex.get_width()), 1.0)
	var w := dw * (1.0 + SQUASH_X * k)
	var h := dh * (1.0 - SQUASH_Y * k)
	var feet := Vector2(vp.x * 0.5, vp.y * DRUM_MID_Y + dh * 0.5) + _shake
	return Rect2(feet - Vector2(w * 0.5, h), Vector2(w, h))


func _draw() -> void:
	if not playing:
		return
	var vp := size
	var a := alpha_at(t)
	# the world stands still behind a deep red dusk
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.14, 0.04, 0.03, 0.74 * a))
	var r := drum_rect()
	var hc := r.position + Vector2(_head.x * r.size.x, _head.y * r.size.y)
	var hr := _head.z * r.size.x
	var hry := _head.z * r.size.x * (r.size.y / maxf(r.size.x, 1.0)) * (float(_tex.get_width()) / maxf(float(_tex.get_height()), 1.0)) if _tex else hr
	# a glow behind the drum that swells on each slap
	var pulse := clampf(_slap_s * exp(-_slap_t / 0.12), 0.0, 1.0)
	var gr := vp.x * (0.62 + 0.12 * pulse)
	draw_texture_rect(_glow, Rect2(hc - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1.0, 0.32, 0.16, a * (0.45 + 0.4 * pulse)))
	# the big slap lights the whole sky behind the drum (under it, so the drum stands out against it)
	if _screen_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.5, 0.26, 0.38 * _screen_flash * a))
	if _tex != null:
		draw_texture_rect(_tex, r, false, Color(1, 1, 1, a))
	# the head flashes as it is struck
	var fl := clampf(_slap_s * exp(-_slap_t / FLASH_TAU), 0.0, 1.0)
	if fl > 0.01:
		draw_set_transform(hc, 0.0, Vector2(1.0, hry / maxf(hr, 1.0)))
		draw_circle(Vector2.ZERO, hr, Color(1.0, 0.98, 0.88, 0.55 * fl * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the waves out from where it was struck
	for rg: Dictionary in _rings:
		var age := t - float(rg["t0"])
		if age < 0.0:
			continue
		var life := RING_LIFE * (1.4 if bool(rg.get("big", false)) else 1.0)
		var f := clampf(age / life, 0.0, 1.0)
		var s := float(rg["s"])
		var out := 1.0 - pow(1.0 - f, 3.0)
		var at: Vector2 = hc + (rg["at"] as Vector2) * hr
		var rr := hr * (0.12 + (0.9 + 1.1 * s) * out) * (1.35 if bool(rg.get("big", false)) else 1.0)
		var wdt := maxf((6.0 + 14.0 * s) * (1.0 - f), 1.5)
		var c := W.PAPER.lerp(RED, clampf(f * 1.4, 0.0, 1.0))
		var fade := a * pow(1.0 - f, 1.4)
		c.a = fade * 0.95
		# an ink edge under each wave, so it reads on the pale skin and on the red sky alike
		draw_arc(at, rr, 0.0, TAU, 72, Color(W.INK, fade * 0.5), wdt + 6.0, true)
		draw_arc(at, rr, 0.0, TAU, 72, c, wdt, true)
	# ink slap lines burst out of the drum's rim: all round it for a strong slap, on its side for a rim slap
	if _slap_t < 0.18 and (_slap_s >= 0.55 or _slap_big or _slap_at.length() > 0.6):
		var k := 1.0 - _slap_t / 0.18
		var n := LINES + (8 if _slap_big else 0)
		var rim := _slap_at.length() > 0.6 and not _slap_big
		var aim := _slap_at.angle()
		for i in range(n):
			var ang := TAU * float(i) / float(n) + 0.13
			if rim:
				ang = aim + (float(i) / float(maxi(n - 1, 1)) - 0.5) * 1.6
				if i >= 6:
					break
			var dir := Vector2(cos(ang), sin(ang) * hry / maxf(hr, 1.0))
			var jag := 0.85 + 0.3 * float((i * 7) % 5) / 4.0
			var r0 := hr * (1.12 + 0.18 * (1.0 - k))
			var r1 := r0 + hr * (0.22 + 0.3 * _slap_s) * jag * (1.5 if _slap_big else 1.0) * k
			draw_line(hc + dir * r0, hc + dir * r1, Color(W.INK, a * k), 13.0 * k + 3.0, true)
			draw_line(hc + dir * r0, hc + dir * r1, Color(W.PAPER, a * k), 6.0 * k + 1.5, true)
	# the name over the drum, thumping with the slaps
	var font := W.slab()
	var tsc := 1.0 + 0.12 * pulse
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_PX).x
	var ty := r.position.y - vp.y * 0.035
	draw_set_transform(Vector2(vp.x * 0.5, ty), 0.0, Vector2(tsc, tsc))
	draw_string_outline(font, Vector2(-tw * 0.5, 0.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_PX, 18, Color(W.INK, a))
	draw_string(font, Vector2(-tw * 0.5 + 6.0, 8.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_PX, Color(W.INK, a))
	draw_string(font, Vector2(-tw * 0.5, 0.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_PX, Color(W.PAPER, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the boost in words, from the big slap on: two lines (" · " halves)
	if _words_t >= 0.0 and words != "":
		var wa := a * clampf((t - _words_t) / 0.12, 0.0, 1.0)
		var wsc := 1.0 + 0.15 * exp(-(t - _words_t) / 0.08)
		var parts := words.split(" · ")
		var half := int(floor(parts.size() / 2.0))
		var lines: Array = [" · ".join(parts.slice(0, half)), " · ".join(parts.slice(half))]
		var wy := r.end.y + vp.y * 0.05
		for ln: String in lines:
			if ln == "":
				continue
			var px := WORDS_PX
			var ww := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			while ww * wsc > vp.x - 64.0 and px > 20:
				px -= 2
				ww = font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			draw_set_transform(Vector2(vp.x * 0.5, wy), 0.0, Vector2(wsc, wsc))
			draw_string_outline(font, Vector2(-ww * 0.5, 0.0), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 14, Color(W.INK, wa))
			draw_string(font, Vector2(-ww * 0.5, 0.0), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1.0, 0.86, 0.5, wa))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			wy += px * 1.35
