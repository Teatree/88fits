## The unlock pop-up (pass 139, lane POP; Garry: "Trials unlocking new items, heroes, etc should be accompanied by a quick
## pop-up that notifies Player of the Unlock and goes away. The whole sequence shouldn't take more than 2 seconds. Showing
## the unlock clearly."). Over its host: the screen dims, a turning shine (WShine) and a burst (WCelebrate) open behind
## the thing's picture, which punches in from POP_FROM of its size with an overshoot; over the picture a gold header
## ("NEW OUTLAW", "NEW WEAPON", ...), under it the thing's name, an optional sub-line (a skin's outlaw) and an optional
## gold pill (the Trail level the buy finished); it holds, then rises a little, shrinks and fades. IN + HOLD + OUT =
## 1.85 s; a tap anywhere while it is coming in or holding hurries it out (OUT_HURRY) and is eaten by the pop-up (it
## never buys the next node by accident); while it goes out taps pass through to the screen. Two plays in quick
## succession queue: the next starts when the one before is gone. Each start plays `ui_unlock`.
## The picture by kind (entry_for): an outlaw and a skin stand as their full-body cut-out (CharacterDef.title_path, the
## look the player plays / the skin's own), a round badge plate when there is none; a weapon, a Card, an item, a
## structure and a power-up sit on their Royale item frame (WPlate.for_def, the kind's corner glyph); a stage or a map is
## its wide picture in a navy frame with a gold rim; anything else (the Bounty Board) its picture on a brass plate.
## Its clock is its own (`step`, called from _process; tests step it by hand, captures freeze it with `seek`), so a
## frame-rate dip never stretches it past TOTAL.
## Use (a new class_name is known only after the next import: by path from other scripts):
##   const WUnlockPopScript := preload("res://ui/wanted/WUnlockPop.gd")
##   var pop = WUnlockPopScript.new(); host.add_child(pop)      # full rect, hidden until it plays
##   pop.play(WUnlockPopScript.entry_for("weapon", "boomstick", "Boomstick"))
## Today the Trail screen plays it (TrailScreen.buy_selected); a quest's unlock at the Results could play the same entry
## (ResultsScreen._build_unlocks' landed unlocks: entry_for(kind, id, name)) — not wired.
class_name WUnlockPop
extends Control

signal done

## The sequence (seconds): the punch in, the hold, the way out; a tap's hurried way out.
const IN := 0.18
const HOLD := 1.37
const OUT := 0.3
const OUT_HURRY := 0.14
const TOTAL := IN + HOLD + OUT
## The picture starts at this share of its size and overshoots (ease-out-back, BACK_K) before it settles; on the way out
## it shrinks by OUT_SHRINK and rises OUT_RISE px.
const POP_FROM := 0.35
const BACK_K := 2.2
const OUT_SHRINK := 0.08
const OUT_RISE := 46.0
## The dim over the host at full, and the picture's middle as a share of the height.
const DIM := Color(0.02, 0.035, 0.09, 0.82)
const CENTRE_Y := 0.44
## Sizes in 1080-wide design pixels: an item's frame, a figure's height, a picture's width, the header, the name (shrunk
## to fit WIDTH, never under NAME_MIN_PX), the sub-line, the gaps, the shine's reach and opacity.
const PLATE_PX := 340.0
const FIGURE_H := 640.0
const PICTURE_W := 880.0
const PICTURE_EDGE := 10.0
const HEAD_PX := 64
const NAME_PX := 84
const NAME_MIN_PX := 44
const SUB_PX := 34
const FOOT_PX := 34
const WIDTH := 960.0
const GAP_HEAD := 26.0
const GAP_NAME := 30.0
const SHINE_R := 560.0
const SHINE_STRENGTH := 0.8
## The kinds' header keys (ui.unlock_pop.head.<kind>); anything else says "UNLOCKED".
const HEADS := ["outlaw", "skin", "weapon", "card", "item", "stage", "map", "structure", "powerup"]

var _queue: Array = []
var _cur: Dictionary = {}
var _t := 0.0
var _hurry_at := -1.0
## Captures hold the clock (seek); the pop-up then never moves on by itself.
var frozen := false
## How many plays have started (tests).
var started := 0
var _card: Control
var _shine: Control
var _burst: Control
var _art_rect := Rect2()
var _dim_a := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_card = Control.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_card)


## The entry for an unlock of `kind` (outlaw, skin "hero:CODE", weapon, passive, stage, map, structure, powerup,
## feature) `id`, named `what`; `art` is the picture for the kinds whose art the caller knows best (a stage's, a
## feature's) and the fallback for the rest.
static func entry_for(kind: String, id: String, what: String, art: Texture2D = null) -> Dictionary:
	var e := {"kind": kind, "name": what, "frame": "plate", "def": null, "tex": art, "sub": "", "foot": ""}
	var head := kind
	match kind:
		"outlaw":
			var c := Registry.character(id)
			var look: CharacterDef = Registry.played_look(c) if c else null
			e["def"] = look
			var tp := look.title_path() if look else ""
			if tp != "" and ResourceLoader.exists(tp):
				e["frame"] = "figure"
				e["tex"] = load(tp)
			if what == "" and c:
				e["name"] = c.display_name
		"skin":
			var hc := Registry.character(id.get_slice(":", 0))
			var vd: CharacterDef = hc.variant_def(id.get_slice(":", 1)) if hc else null
			e["def"] = vd
			# the skin's own cut-out only: the outlaw's base one would show the wrong clothes (else its badge)
			var tp := vd.title_path() if vd and vd.look_title() != "" else ""
			if tp != "" and ResourceLoader.exists(tp):
				e["frame"] = "figure"
				e["tex"] = load(tp)
			if hc:
				e["sub"] = Loc.t("ui.unlock_pop.skin_for", {"outlaw": hc.display_name})
		"weapon":
			e["def"] = Registry.weapon(id)
		"passive":
			var p := Registry.passive(id)
			e["def"] = p
			head = "card" if p and p.is_line() else "item"
		"structure":
			e["def"] = Registry.structure(id)
		"powerup":
			e["def"] = Registry.pickup(id)
		"stage", "map":
			e["frame"] = "picture" if art else "plate"
	if e["def"] == null and e["tex"] == null:
		e["frame"] = "plate"
	e["head"] = Loc.t("ui.unlock_pop.head." + (head if HEADS.has(head) else "any"))
	if str(e["name"]) == "" and e["def"] is ContentDef:
		e["name"] = str((e["def"] as ContentDef).display_name)
	return e


## Shows `entry` (entry_for's), at once when nothing is up, else after what is up and queued before it.
func play(entry: Dictionary) -> void:
	if _cur.is_empty():
		_start(entry)
	else:
		_queue.append(entry)


## Whether one is up (coming in, holding or going out) or waiting.
func is_up() -> bool:
	return not _cur.is_empty()


func queued() -> int:
	return _queue.size()


## "in", "hold", "out" or "" (nothing up).
func phase() -> String:
	if _cur.is_empty():
		return ""
	if _hurry_at >= 0.0 and _t >= _hurry_at:
		return "out"
	if _t < IN:
		return "in"
	return "hold" if _t < IN + HOLD else "out"


## The entry up now ({} when none).
func current() -> Dictionary:
	return _cur


## How long the one up lasts in all, from its start (TOTAL, or less once hurried).
func length() -> float:
	return _hurry_at + OUT_HURRY if _hurry_at >= 0.0 else TOTAL


## Out now (a tap's): from where it stands, OUT_HURRY seconds. Nothing while it is already going.
func hurry() -> void:
	if _cur.is_empty() or phase() == "out":
		return
	_hurry_at = _t
	_apply()


## The clock of the one up set to `t` seconds and held there (captures); `run` lets it go on.
func seek(t: float, run: bool = false) -> void:
	if _cur.is_empty():
		return
	frozen = not run
	_t = maxf(t, 0.0)
	_apply()


func _process(delta: float) -> void:
	if not frozen:
		step(delta)


## Moves the clock on by `dt` seconds: the next phase, the next in the queue, or gone.
func step(dt: float) -> void:
	if _cur.is_empty():
		return
	_t += dt
	if _t >= length():
		_finish()
		return
	_apply()


func _gui_input(e: InputEvent) -> void:
	var press := false
	if e is InputEventScreenTouch:
		press = (e as InputEventScreenTouch).pressed
	elif e is InputEventMouseButton:
		press = (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if press and phase() != "out":
		hurry()
		accept_event()


func _start(entry: Dictionary) -> void:
	_cur = entry
	_t = 0.0
	_hurry_at = -1.0
	started += 1
	visible = true
	# over whatever the host has put up since (a question closing, the tab bar, the tutorial's highlight)
	var host := get_parent()
	if host:
		host.move_child(self, -1)
	_build(entry)
	W.sfx("ui_unlock")
	_apply()


func _finish() -> void:
	_cur = {}
	_t = 0.0
	_hurry_at = -1.0
	_clear()
	if not _queue.is_empty():
		_start(_queue.pop_front())
		return
	visible = false
	frozen = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	done.emit()


func _clear() -> void:
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	# the burst frees itself after WCelebrate.LIFE: a held (seek) pop-up can outlive it
	for n in [_shine, _burst]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_shine = null
	_burst = null


func _view() -> Vector2:
	return size if size.x > 1.0 and size.y > 1.0 else get_viewport_rect().size


## The picture, the header, the name and its lines, laid out round the picture's middle; the shine and the burst
## behind it.
func _build(e: Dictionary) -> void:
	_clear()
	var vp := _view()
	var mid := Vector2(vp.x * 0.5, vp.y * CENTRE_Y)
	var art := _make_art(e)
	_art_rect = Rect2(mid - art.size * 0.5, art.size)
	art.position = _art_rect.position
	_card.add_child(art)
	_card.pivot_offset = mid
	# the header over the picture, gold
	var head := W.text(str(e.get("head", "")).to_upper(), R.display(W.em(HEAD_PX, 0.06)), HEAD_PX, R.GOLD_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hh := head.get_combined_minimum_size().y
	head.size = Vector2(WIDTH, hh)
	head.position = Vector2((vp.x - WIDTH) * 0.5, _art_rect.position.y - GAP_HEAD - hh)
	_card.add_child(head)
	# the name under it, cream, shrunk to the width
	var name_t := W.text(str(e.get("name", "")), R.display(), NAME_PX, R.CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	name_t.name = "Name"
	name_t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	while name_t.text_width() > WIDTH and name_t.font_size > NAME_MIN_PX:
		name_t.font_size -= 4
		R.edge(name_t, name_t.font_size)
	var y := _art_rect.end.y + GAP_NAME
	var nh := name_t.get_combined_minimum_size().y
	name_t.size = Vector2(WIDTH, nh)
	name_t.position = Vector2((vp.x - WIDTH) * 0.5, y)
	_card.add_child(name_t)
	y += nh + 8.0
	if str(e.get("sub", "")) != "":
		var sub := W.text(str(e["sub"]), R.body(R.LABEL_WEIGHT), SUB_PX, R.SECONDARY, HORIZONTAL_ALIGNMENT_CENTER)
		sub.name = "Sub"
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sub_h := sub.get_combined_minimum_size().y
		sub.size = Vector2(WIDTH, sub_h)
		sub.position = Vector2((vp.x - WIDTH) * 0.5, y)
		_card.add_child(sub)
		y += sub_h + 8.0
	if str(e.get("foot", "")) != "":
		var foot := W.pill([[str(e["foot"]).to_upper(), R.GOLD_TEXT, "bold"]], FOOT_PX, 58.0)
		foot.name = "Foot"
		_card.add_child(foot)
		foot.reset_size()
		var fs := foot.get_combined_minimum_size()
		foot.size = fs
		foot.position = Vector2((vp.x - fs.x) * 0.5, y + 12.0)
	# behind it all: the burst's rays, ring and confetti, and the turning shine (each fades with the card)
	_burst = WCelebrate.burst(self, mid, 0, 1.0)
	var sh := WShine.make(mid, SHINE_R) as WShine
	sh.name = "Shine"
	sh.strength = SHINE_STRENGTH
	sh.put(self, 0)
	_shine = sh


## The picture in its frame, sized (its position is set by the caller).
func _make_art(e: Dictionary) -> Control:
	var tex: Texture2D = e.get("tex")
	var def: Variant = e.get("def")
	match str(e.get("frame", "plate")):
		"figure":
			var ts := tex.get_size() if tex else Vector2(660, 888)
			var box := Control.new()
			box.name = "Art"
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.size = Vector2(FIGURE_H * ts.x / maxf(ts.y, 1.0), FIGURE_H)
			# a navy shadow under the feet, then the cut-out
			box.draw.connect(func() -> void:
				var foot := Vector2(box.size.x * 0.5, box.size.y * 0.97)
				box.draw_set_transform(foot, 0.0, Vector2(1.0, 0.22))
				box.draw_circle(Vector2.ZERO, box.size.x * 0.34, Color(R.NAVY, 0.55), true, -1.0, true)
				box.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
			var fig := TextureRect.new()
			fig.name = "Figure"
			fig.texture = tex
			fig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fig.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			box.add_child(fig)
			return box
		"picture":
			var ps := tex.get_size() if tex else Vector2(1248, 480)
			var w := PICTURE_W
			var h := w * ps.y / maxf(ps.x, 1.0)
			var frame := Control.new()
			frame.name = "Art"
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.size = Vector2(w, h) + Vector2(PICTURE_EDGE, PICTURE_EDGE) * 2.0
			frame.draw.connect(func() -> void:
				var outer := Rect2(Vector2.ZERO, frame.size)
				frame.draw_style_box(_box(R.NAVY, 18, 0, Color.TRANSPARENT), Rect2(outer.position + Vector2(0, 8), outer.size))
				frame.draw_style_box(_box(R.NAVY, 18, 0, Color.TRANSPARENT), outer)
				var inner := outer.grow(-PICTURE_EDGE)
				if tex:
					frame.draw_texture_rect(tex, inner, false)
				frame.draw_style_box(_box(Color.TRANSPARENT, 10, 5, R.GOLD_TEXT), inner.grow(2.0))
				frame.draw_rect(Rect2(inner.position + Vector2(6, 6), Vector2(inner.size.x - 12, 3)), Color(1, 1, 1, 0.35)))
			return frame
	var p := WPlate.new()
	p.name = "Art"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if def is ContentDef:
		p.for_def(def as ContentDef, PLATE_PX)
		p.set_kind_mark_for(def as ContentDef)
	else:
		p.side = PLATE_PX
		p.fill = W.BRASS
		p.radius = 18
		p.border = 5
	if tex and not (def is ContentDef):
		p.tex = tex
	p.size = Vector2(PLATE_PX, PLATE_PX)
	return p


static func _box(fill: Color, radius: int, border: int, border_col: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.draw_center = fill.a > 0.0
	b.set_corner_radius_all(radius)
	b.set_border_width_all(border)
	b.border_color = border_col
	b.anti_aliasing = true
	return b


## The look at the clock: the picture's scale, its opacity and how far it has risen, from the start or from a hurry.
func _look_at(t: float) -> Vector3:
	if t < IN:
		var u := clampf(t / IN, 0.0, 1.0)
		var k := 1.0 + BACK_K * pow(u - 1.0, 3.0) + (BACK_K - 1.0) * pow(u - 1.0, 2.0)
		return Vector3(lerpf(POP_FROM, 1.0, k), clampf(u * 2.0, 0.0, 1.0), 0.0)
	if t < IN + HOLD:
		return Vector3(1.0, 1.0, 0.0)
	var v := clampf((t - IN - HOLD) / OUT, 0.0, 1.0)
	return Vector3(1.0 - OUT_SHRINK * v, 1.0 - v, OUT_RISE * v)


func _apply() -> void:
	var l := _look_at(_t)
	if _hurry_at >= 0.0 and _t >= _hurry_at:
		var b := _look_at(_hurry_at)
		var v := clampf((_t - _hurry_at) / OUT_HURRY, 0.0, 1.0)
		l = Vector3(b.x * (1.0 - OUT_SHRINK * v), b.y * (1.0 - v), b.z + OUT_RISE * v)
	_card.scale = Vector2(l.x, l.x)
	_card.position = Vector2(0.0, -l.z)
	_card.modulate.a = l.y
	_dim_a = l.y
	if is_instance_valid(_shine):
		_shine.set("fade", l.y)
		_shine.set("grow", clampf(l.x, 0.0, 1.1))
	if is_instance_valid(_burst):
		_burst.modulate.a = l.y
	# eats taps while it comes in and holds; lets them through on its way out
	mouse_filter = Control.MOUSE_FILTER_IGNORE if phase() == "out" else Control.MOUSE_FILTER_STOP
	queue_redraw()


func _draw() -> void:
	if _dim_a > 0.003:
		draw_rect(Rect2(Vector2.ZERO, _view()), Color(DIM, DIM.a * _dim_a))
