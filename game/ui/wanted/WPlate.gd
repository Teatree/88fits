## The one plate every item lives on: a rounded square in its colour with an ink border (W.plate_fill; pass 48, Garry:
## plates that change colour as they level: a weapon or a line in the colour of its level, Lv 1 common .. Lv 5 legendary;
## a passive item its rarity's World of Warcraft colour; an evolved one dark in a brass ring), the painted icon centred
## on it, an optional level tag (paper chip, 3 px ink, slab number) overlapping the bottom-right corner by 10 px, a
## weapon's mutation dots along its top edge (pass 48; pass 49: a brass dot for each mutation held, nothing for the open
## ones; the plate glows soft brass while its evolution waits at the next chest), and a locked look (aged plate, the icon a
## 30 % ink silhouette). Portraits are round (`round_plate`). The HUD's slots that hold nothing (pass 46) are plates too:
## an open one aged with a dashed line inside (`empty`), one the stage has not opened aged with a drawn padlock and the
## stage that opens it (`padlock`, `lock_stage`; no slot is shut since pass 47, the caps are static: five and five
## since pass 52).
## `plate_alpha` (pass 48: the HUD's see-through slots) fades the fill and the frame and keeps the icon, the level tag,
## the dots and a padlock solid. Without an icon a plate can carry a slab `glyph` (the results' "?" for a damage source
## with no picture yet), and a `badge` (a creature's skull, crown or gear) hangs over its top-left corner. Pass 54: a
## card's plate (the level-up's, the chest's) carries its kind's corner glyph over the bottom-left corner (`kind_mark`:
## a revolver on a weapon (pass 56), a rolled scroll on a line, in a paper disc with an ink ring). Drawn in one pass, so a
## HUD row of ten (five weapons and five lines since pass 52) stays cheap.
class_name WPlate
extends Control

var side := 96.0:
	set(v):
		side = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
var fill := W.BRASS
var border := 4
var border_color := W.INK
var radius := 10
var round_plate := false
var tex: Texture2D
var icon_frac := 0.81
var level_text := ""
var level_size := 22
var level_fill := W.PAPER
var level_border_color := W.INK
var locked := false
var shadow := 0
## A second, inner outline: the brass ring of an evolved item.
var ring := 0
var ring_color := W.BRASS
## The ring the plate has of its own (an evolved item's), for whoever borrows the ring and gives it back.
var base_ring := 0
## An open slot with nothing in it: aged, a dashed line inside the border, no icon.
var empty := false
## A slot still shut: aged, a drawn padlock, on its body the stage that opens the slot (`lock_stage`, 1-based; 0 or
## less draws a keyhole instead).
var padlock := false
var lock_stage := 0
## A slab character drawn in the middle when there is no icon (the "?" of a damage source without its picture).
var glyph := ""
var glyph_color := W.INK
## A badge over the top-left corner (pass 47, the Collection's Enemies: skull boss, crown Elite, gear special), as big
## as `badge_px` (0: a third of the plate).
var badge: Texture2D
var badge_px := 0.0
## The kind's corner glyph (pass 54, Garry: "a small corner glyph" telling a weapon from a line on the cards, since both
## take the same level colours): "weapon" or "line" (W.kind_mark_of), "" none. Drawn over the bottom-left corner,
## KIND_FRAC of the plate across, in a paper disc with an ink ring so it reads on any plate colour; the painted glyph
## (`kind_glyph`, W.kind_glyph) inside it, or the kind's letter in slab until the picture is imported.
var kind_mark := ""
var kind_glyph: Texture2D
const KIND_FRAC := 0.26
## Mutation dots (pass 48, Garry: "on weapon icons display mutations as dots over them"): `dots.x` held of the `dots.y`
## on the weapon's path (Run.path_progress: a hero's own mutation is not on it), in a row along the top edge, each
## `dot_px` across (0: 20 px on a 72 px HUD slot, growing with the plate). Pass 49 (Garry: "those should only appear when
## the player selects a mutation for it: all mutations, all 3 dots; none, none"): only the held ones are drawn, a brass
## dot each, the row centred over them (held_center). `dots_ready`: every one is held and the evolution waits at the next
## chest, so the plate glows soft brass, breathing.
var dots := Vector2i.ZERO
var dot_px := 0.0
var dots_ready := false:
	set(v):
		dots_ready = v
		set_process(v)
		queue_redraw()
## How much of the fill and the frame shows (the HUD's slots: 0.5, the world shows through them); the icon, the level
## tag, the dots, a padlock and a glyph stay solid.
var plate_alpha := 1.0:
	set(v):
		plate_alpha = clampf(v, 0.0, 1.0)
		queue_redraw()
var _glow_t := 0.0

## The glow's breath: one in and out every GLOW_PERIOD seconds, between GLOW_LOW and 1 of its strength.
const GLOW_PERIOD := 1.6
const GLOW_LOW := 0.65


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)
	set_process(false)


## A slot with nothing in it, `px` square: open (dashed), or padlocked until stage `stage`.
static func slot(px: float, p_padlock: bool = false, stage: int = 0) -> WPlate:
	var p := WPlate.new()
	p.side = px
	p.empty = not p_padlock
	p.padlock = p_padlock
	p.lock_stage = stage
	p.radius = 10 if px < 140 else 12
	p.border = 4 if px < 140 else 5
	return p


## Set the plate up for a content item: its colour, its icon, locked if it is not found yet. `level` (pass 48) is the
## level the plate shows a weapon or a line at, its colour on the rarity ladder (W.plate_fill); 0 = the item in general,
## common.
func for_def(def: ContentDef, px: float, is_locked: bool = false, level: int = 0) -> WPlate:
	side = px
	var k := W.kind_of(def)
	var evolved := W.is_evolved(def)
	fill = W.plate_fill(def, level)
	round_plate = k == "character"
	tex = def.icon if def else null
	locked = is_locked
	radius = 10 if px < 140 else (12 if px < 190 else (14 if px < 240 else (18 if px < 400 else 24)))
	border = 4 if px < 140 else 5
	# an evolution: the dark plate in a brass ring (about 4 px on a HUD slot)
	ring = maxi(3, int(round(px * 0.04))) if evolved and not is_locked else 0
	ring_color = W.EVOLVED_RING
	base_ring = ring
	queue_redraw()
	return self


## The kind's corner glyph for `def` (W.kind_mark_of: a weapon or its evolution, a line or its evolution; nothing for
## the rest), or for the kind `kind` when it is given.
func set_kind_mark_for(def: ContentDef) -> WPlate:
	return set_kind_mark(W.kind_mark_of(def))


func set_kind_mark(kind: String) -> WPlate:
	kind_mark = kind
	kind_glyph = W.kind_glyph(kind)
	queue_redraw()
	return self


## The kind disc's middle and its diameter: over the bottom-left corner, 10 px past the border's inner edge, as the
## level tag overlaps the bottom-right one.
func kind_disc() -> Rect2:
	var d := roundf(side * KIND_FRAC)
	return Rect2(Vector2(border - 10.0, side - border + 10.0 - d), Vector2(d, d))


## The mutation dots: `p` = (held, total) along the weapon's path; `p_ready` glows the plate (its evolution waits at the
## next chest). (0, 0) takes them off.
func set_dots(p: Vector2i, p_ready: bool = false) -> WPlate:
	dots = Vector2i(clampi(p.x, 0, maxi(p.y, 0)), maxi(p.y, 0))
	dots_ready = p_ready and dots.y > 0
	queue_redraw()
	return self


## A weapon's dots (pass 48): (held, total) along its path, read off the run's copy of it (Run.path_progress), else none
## held of its path's total (Registry.mutations_of); ZERO for anything that is not a weapon or has no path. An evolution
## reads its family's path (the mutations stay on the evolved form).
static func path_of(def: ContentDef) -> Vector2i:
	if not def is WeaponDef:
		return Vector2i.ZERO
	var wd := def as WeaponDef
	var fam := wd.evolved_from if wd.is_evolution and wd.evolved_from != "" else wd.id
	var run := W.node("Run")
	if run and run.has_method("family_instance") and run.has_method("path_progress"):
		var inst = run.family_instance(fam)
		if inst != null:
			return run.path_progress(inst)
	var reg := W.node("Registry")
	if reg and reg.has_method("mutations_of"):
		return Vector2i(0, (reg.mutations_of(fam) as Array).size())
	return Vector2i.ZERO


## Whether the run's copy of a weapon waits to evolve at the next chest (Run.evolution_ready: every mutation of its path
## held and its top level).
static func ready_of(def: ContentDef) -> bool:
	if not def is WeaponDef or (def as WeaponDef).is_evolution:
		return false
	var run := W.node("Run")
	if run == null or not run.has_method("weapon_instance") or not run.has_method("evolution_ready"):
		return false
	var inst = run.weapon_instance(def.id)
	return inst != null and bool(run.evolution_ready(inst))


## The dots' size in px: `dot_px`, or 20 on a 72 px plate, growing with the square root of the plate's side (24 on a
## pause row's 104, 32 on a card's 180, 49 on the chest's landed 436).
func dot_size() -> float:
	return dot_px if dot_px > 0.0 else roundf(20.0 * sqrt(side / 72.0))


## The middle of dot `i` (0-based) in a row of the path's whole `dots.y`, centred along the top edge, straddling the
## border.
func dot_center(i: int) -> Vector2:
	return _row_center(i, dots.y)


## The middle of held dot `i` (pass 49): the row of the `dots.x` held ones, centred along the top edge (what is drawn).
func held_center(i: int) -> Vector2:
	return _row_center(i, dots.x)


func _row_center(i: int, n: int) -> Vector2:
	var d := dot_size()
	var gap := maxf(roundf(d * 0.2), 2.0)
	var w := n * d + maxi(n - 1, 0) * gap
	return Vector2((side - w) * 0.5 + d * 0.5 + i * (d + gap), border * 0.5)


func _process(delta: float) -> void:
	_glow_t = fmod(_glow_t + delta, GLOW_PERIOD)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(side, side))
	if dots_ready and not locked:
		_glow(r)
	var f := W.AGED if locked or empty or padlock else fill
	f.a *= plate_alpha
	var bc := Color(border_color, border_color.a * plate_alpha)
	if shadow > 0:
		_shape(Rect2(r.position + Vector2(shadow, shadow), r.size), Color(W.INK, plate_alpha), 0, W.INK)
	_shape(r, f, border, bc)
	if empty:
		_dashes(r.grow(-(border + side * 0.1)))
	if padlock:
		_padlock()
	if ring > 0:
		var rc := Color(ring_color, ring_color.a * plate_alpha)
		var rr := r.grow(-border)
		if round_plate:
			draw_arc(rr.get_center(), rr.size.x * 0.5 - ring * 0.5, 0.0, TAU, 64, rc, ring, true)
		else:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_corner_radius_all(maxi(radius - border, 2))
			sb.set_border_width_all(ring)
			sb.border_color = rc
			sb.anti_aliasing = true
			draw_style_box(sb, rr)
	if tex:
		var inner := side * icon_frac
		var ts := tex.get_size()
		var k := inner / maxf(ts.x, ts.y)
		var sz := ts * k
		var at := (Vector2(side, side) - sz) * 0.5
		if round_plate:
			# a portrait fills its disc
			at = Vector2(border, border)
			sz = Vector2(side - border * 2, side - border * 2)
		draw_texture_rect(tex, Rect2(at, sz), false, Color(0.14, 0.106, 0.078, 0.3) if locked else Color.WHITE)
	elif glyph != "" and not empty and not padlock:
		var gf := W.slab()
		var gpx := maxi(int(round(side * 0.56)), 8)
		var gw := gf.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx).x
		var gbase := side * 0.5 - gf.get_height(gpx) * 0.5 + gf.get_ascent(gpx)
		draw_string(gf, Vector2((side - gw) * 0.5, gbase), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, glyph_color)
	if badge:
		# over the corner: a third of it outside the plate, up and to the left
		var bp := badge_px if badge_px > 0.0 else side * 0.34
		var bs := badge.get_size()
		var bk := bp / maxf(bs.x, bs.y)
		draw_texture_rect(badge, Rect2(Vector2(-bp * 0.3, -bp * 0.3), bs * bk), false, Color(1, 1, 1, 0.6) if locked else Color.WHITE)
	if kind_mark != "" and not empty and not padlock:
		_kind_disc()
	if dots.x > 0 and not locked:
		_dots()
	if level_text != "":
		var fnt := W.slab()
		var tw := fnt.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, level_size).x
		var padx := 8.0 if level_size >= 22 else 7.0
		var h := W.normal_height(fnt, level_size) + 6.0
		var w := tw + padx * 2.0 + 6.0
		# right:-10 / bottom:-10 on the padding box: 10 px past the inner edge of the border
		var tag := Rect2(Vector2(side - border + 10.0 - w, side - border + 10.0 - h), Vector2(w, h))
		draw_rect(tag, level_border_color)
		draw_rect(tag.grow(-3.0), level_fill)
		var base := tag.position.y + 3.0 + (h - 6.0 - fnt.get_height(level_size)) * 0.5 + fnt.get_ascent(level_size)
		draw_string(fnt, Vector2(tag.position.x + 3.0 + padx, base), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, level_size, W.INK)


## The mutation dots along the top edge: one per mutation held, brass in an ink ring with a glint, so it reads on every
## plate colour and over the sand (pass 49: the open ones are not drawn at all).
func _dots() -> void:
	var d := dot_size()
	var rad := d * 0.5
	var edge := maxf(roundf(d * 0.12), 2.0)
	for i in dots.x:
		var c := held_center(i)
		# plain circles, not anti-aliased: an anti-aliased circle is a feathered polygon of its own and never batches, and
		# the HUD's twelve plates' dots and its empty slots' dashes were half its draw calls (pass 48, perf_late)
		draw_circle(c, rad, W.INK, true, -1.0, false)
		draw_circle(c, rad - edge, W.BRASS, true, -1.0, false)
		draw_circle(c + Vector2(-rad, -rad) * 0.3, rad * 0.24, Color(1.0, 0.93, 0.72, 0.9), true, -1.0, false)


## The kind's corner glyph: a paper disc in an ink ring with a hard ink shadow, the glyph (or its letter) in ink inside.
func _kind_disc() -> void:
	var r := kind_disc()
	var c := r.get_center()
	var rad := r.size.x * 0.5
	var edge := maxf(roundf(rad * 0.16), 2.0)
	draw_circle(c + Vector2(edge, edge) * 0.6, rad, Color(W.INK, 0.85), true, -1.0, true)
	draw_circle(c, rad, W.INK, true, -1.0, true)
	draw_circle(c, rad - edge, W.PAPER, true, -1.0, true)
	var inner := (rad - edge) * 2.0 * 0.78
	if kind_glyph:
		var ts := kind_glyph.get_size()
		var k := inner / maxf(ts.x, ts.y)
		var sz := ts * k
		draw_texture_rect(kind_glyph, Rect2(c - sz * 0.5, sz), false, Color(1, 1, 1, 0.45) if locked else Color.WHITE)
	else:
		var gf := W.slab()
		var t := "W" if kind_mark == "weapon" else "L"
		var gpx := maxi(int(round(inner * 0.72)), 8)
		var gw := gf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx).x
		var gbase := c.y - gf.get_height(gpx) * 0.5 + gf.get_ascent(gpx)
		draw_string(gf, Vector2(c.x - gw * 0.5, gbase), t, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, W.INK)


## The evolution-ready glow: soft brass in layers round the plate and a bright brass edge just outside its border,
## breathing.
func _glow(r: Rect2) -> void:
	var breath := GLOW_LOW + (1.0 - GLOW_LOW) * (0.5 + 0.5 * sin(_glow_t / GLOW_PERIOD * TAU))
	var reach := maxf(side * 0.17, 8.0)
	var layers := 8
	for i in layers:
		var k := float(i) / float(layers)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(W.BRASS.r, W.BRASS.g, W.BRASS.b, 0.08 * breath)
		sb.set_corner_radius_all(int(radius + reach * (1.0 - k)))
		sb.anti_aliasing = true
		draw_style_box(sb, r.grow(reach * (1.0 - k)))
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.set_corner_radius_all(radius + 3)
	edge.set_border_width_all(maxi(int(round(side * 0.035)), 2))
	edge.border_color = Color(W.BRASS, 0.85 * breath)
	edge.anti_aliasing = true
	draw_style_box(edge, r.grow(3.0))


## The open slot's line: short ink dashes, half seen, round an inset square.
func _dashes(rr: Rect2) -> void:
	var c := Color(W.INK_SOFT, 0.5)
	var w := maxf(side * 0.035, 2.0)
	var dash := maxf(side * 0.09, 5.0)
	var pts: Array[Vector2] = [rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]
	# plain dashes (pass 48): anti-aliased ones were a draw call each, nine a side on every empty HUD slot
	for i in 4:
		draw_dashed_line(pts[i], pts[(i + 1) % 4], c, w, dash, true, false)


## The shut slot's padlock (drawn: no font has one): an ink shackle over an ink body that carries the stage that opens
## the slot in paper slab, or a keyhole when no stage does.
func _padlock() -> void:
	var cx := side * 0.5
	var bw := side * 0.46
	var bh := side * 0.34
	var body := Rect2(cx - bw * 0.5, side * 0.44, bw, bh)
	var sw := maxf(side * 0.075, 2.5)
	var sr := bw * 0.3
	var top := body.position.y - side * 0.04
	draw_arc(Vector2(cx, top), sr, PI, TAU, 24, W.INK, sw, true)
	draw_line(Vector2(cx - sr, top), Vector2(cx - sr, body.position.y + 1.0), W.INK, sw, true)
	draw_line(Vector2(cx + sr, top), Vector2(cx + sr, body.position.y + 1.0), W.INK, sw, true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = W.INK
	sb.set_corner_radius_all(maxi(int(round(side * 0.06)), 2))
	sb.anti_aliasing = true
	draw_style_box(sb, body)
	if lock_stage > 0:
		var fnt := W.slab()
		var px := maxi(int(round(bh * 0.72)), 8)
		var txt := str(lock_stage)
		var tw := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var base := body.get_center().y - fnt.get_height(px) * 0.5 + fnt.get_ascent(px)
		draw_string(fnt, Vector2(body.get_center().x - tw * 0.5, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, W.PAPER)
	else:
		var kc := body.get_center()
		draw_circle(kc - Vector2(0, bh * 0.1), bh * 0.14, W.AGED, true, -1.0, true)
		draw_rect(Rect2(kc.x - bh * 0.05, kc.y - bh * 0.05, bh * 0.1, bh * 0.28), W.AGED)


func _shape(r: Rect2, f: Color, b: int, bc: Color) -> void:
	if round_plate:
		var c := r.get_center()
		var rad := r.size.x * 0.5
		if b > 0:
			draw_circle(c, rad, bc, true, -1.0, true)
			draw_circle(c, rad - b, f, true, -1.0, true)
		else:
			draw_circle(c, rad, f, true, -1.0, true)
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = f
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(b)
	sb.border_color = bc
	sb.anti_aliasing = true
	draw_style_box(sb, r)
