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
## Pass 122 (lane UIKIT_B), under Royale (W.royale()): the same plate is the handoff's ITEM FRAME (README section 3; the
## Wanted drawing is untouched while the switch is off): a radial rarity fill with a white lip and a dark foot inside a
## rarity rim (7 px from 160 up, 5 below; the legendary's a thicker gold bevel with a dark line inside it and a glow, the
## epic's a glow), a navy outline (4 / 3 px), a navy base 8 px straight down, the icon at 86 % with a hard drop shadow,
## 6 px corners; the rarity is the one the Wanted plate's colour stands for (frame_rarity: a passive item's rarity or
## rung, a weapon's or Card's level colour, pass 48's rule kept; a fill of a screen's own derives its triplet), an evolved
## item a black face in a rainbow rim with a soft white glow and an EVO plaque on gold, a locked one the locked grey with
## the icon a navy silhouette, an empty slot a slate tile with a dashed line. The frame is painted by
## core/shaders/ui_radial_fill.gdshader on a child drawn behind the plate (`RoyaleFrame`), the optional rays
## (`rays`, core/shaders/ui_rays.gdshader) on another behind it (`RoyaleRays`); the icon, the plaque, the dots, the
## glyphs and the badge are drawn by the plate over them. The level plaque (`level_plaque`: "LV n", a plain "n" on a frame
## of 80 px or less; `level_text` shows the same way) hangs off the bottom centre in blue. The public API of the Wanted
## plate (for_def, slot, side, fill, border, radius, shadow, icon_frac, level_text, dots, kind_mark ...) is unchanged.
## Pass 122 review fixes (lane UIKIT_B_FIX): a plate redraws only when something changes (every drawn-from property is a
## setter that queues a redraw; `_process` runs only while the evolution glow breathes), the evolved look is for_def's
## flag alone (an ink fill, every creature's, is a slate frame), a hand-set ring is drawn whatever its colour (brass ->
## gold, rock -> red), and a glow never paints over an earlier sibling's frame (`glow_cuts`; `glow_reach` caps it).
class_name WPlate
extends Control

var side := 96.0:
	set(v):
		side = v
		custom_minimum_size = Vector2(v, v)
		queue_redraw()
## Every property the drawing reads queues a redraw when set (pass 122 review fix: a plate no longer redraws every frame,
## so a screen that writes one after the plate is in the tree, the Totem's `tex`, the HUD's `level_text`, sees it drawn).
var fill := W.BRASS:
	set(v):
		fill = v
		queue_redraw()
var border := 4:
	set(v):
		border = v
		queue_redraw()
var border_color := W.INK:
	set(v):
		border_color = v
		queue_redraw()
var radius := 10:
	set(v):
		radius = v
		queue_redraw()
var round_plate := false:
	set(v):
		round_plate = v
		queue_redraw()
var tex: Texture2D:
	set(v):
		tex = v
		queue_redraw()
var icon_frac := 0.81:
	set(v):
		icon_frac = v
		queue_redraw()
var level_text := "":
	set(v):
		level_text = v
		queue_redraw()
var level_size := 22:
	set(v):
		level_size = v
		queue_redraw()
var level_fill := W.PAPER:
	set(v):
		level_fill = v
		queue_redraw()
var level_border_color := W.INK:
	set(v):
		level_border_color = v
		queue_redraw()
var locked := false:
	set(v):
		locked = v
		queue_redraw()
var shadow := 0:
	set(v):
		shadow = v
		queue_redraw()
## A second, inner outline: the brass ring of an evolved item.
var ring := 0:
	set(v):
		ring = v
		queue_redraw()
var ring_color := W.BRASS:
	set(v):
		ring_color = v
		queue_redraw()
## The ring the plate has of its own (an evolved item's), for whoever borrows the ring and gives it back.
var base_ring := 0
## An open slot with nothing in it: aged, a dashed line inside the border, no icon.
var empty := false:
	set(v):
		empty = v
		queue_redraw()
## A slot still shut: aged, a drawn padlock, on its body the stage that opens the slot (`lock_stage`, 1-based; 0 or
## less draws a keyhole instead).
var padlock := false:
	set(v):
		padlock = v
		queue_redraw()
var lock_stage := 0:
	set(v):
		lock_stage = v
		queue_redraw()
## A slab character drawn in the middle when there is no icon (the "?" of a damage source without its picture).
var glyph := "":
	set(v):
		glyph = v
		queue_redraw()
var glyph_color := W.INK:
	set(v):
		glyph_color = v
		queue_redraw()
## Pass 69 (Garry: an unknown hero's "weapon is a black silhouette of the one with a question mark and so is the fav
## item"): the plate aged, the icon a flat black silhouette (its shape only), a paper "?" in an ink outline over it. On a
## round plate (a hero's badge) the badge's own figure goes black the same way.
var mystery := false:
	set(v):
		mystery = v
		queue_redraw()
## A badge over the top-left corner (pass 47, the Collection's Enemies: skull boss, crown Elite, gear special), as big
## as `badge_px` (0: a third of the plate).
var badge: Texture2D:
	set(v):
		badge = v
		queue_redraw()
var badge_px := 0.0:
	set(v):
		badge_px = v
		queue_redraw()
## The kind's corner glyph (pass 54, Garry: "a small corner glyph" telling a weapon from a line on the cards, since both
## take the same level colours): "weapon" or "line" (W.kind_mark_of), "" none. Drawn over the bottom-left corner,
## KIND_FRAC of the plate across, in a paper disc with an ink ring so it reads on any plate colour; the painted glyph
## (`kind_glyph`, W.kind_glyph) inside it, or the kind's letter in slab until the picture is imported.
var kind_mark := "":
	set(v):
		kind_mark = v
		queue_redraw()
var kind_glyph: Texture2D:
	set(v):
		kind_glyph = v
		queue_redraw()
const KIND_FRAC := 0.26
## Mutation dots (pass 48, Garry: "on weapon icons display mutations as dots over them"): `dots.x` held of the `dots.y`
## on the weapon's path (Run.path_progress: a hero's own mutation is not on it), in a row along the top edge, each
## `dot_px` across (0: 20 px on a 72 px HUD slot, growing with the plate). Pass 49 (Garry: "those should only appear when
## the player selects a mutation for it: all mutations, all 3 dots; none, none"): only the held ones are drawn, a brass
## dot each, the row centred over them (held_center). `dots_ready`: every one is held and the evolution waits at the next
## chest, so the plate glows soft brass, breathing.
var dots := Vector2i.ZERO:
	set(v):
		dots = v
		queue_redraw()
var dot_px := 0.0:
	set(v):
		dot_px = v
		queue_redraw()
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

# --- Royale (pass 122, lane UIKIT_B) -----------------------------------------------------------------------------------
const FILL_SHADER := preload("res://core/shaders/ui_radial_fill.gdshader")
const RAYS_SHADER := preload("res://core/shaders/ui_rays.gdshader")
## The level plaque hanging off the bottom centre under Royale: "LV n" (a plain "n" on a frame of R.PLAQUE_PLAIN_AT px or
## less); 0 = none, when `level_text` shows the same way as a plain plaque (the HUD's levels and the buffs' seconds). An
## evolved item's plaque says EVO on gold whatever these say.
var level_plaque := 0:
	set(v):
		level_plaque = maxi(v, 0)
		queue_redraw()
## The rays behind the frame under Royale (a pressed card's item, the chest's and the mutation offer's frames): a disc
## `rays_scale` times the side, turning, in `rays_color`.
var rays := false:
	set(v):
		rays = v
		queue_redraw()
var rays_scale := R.RAYS_SCALE:
	set(v):
		rays_scale = v
		queue_redraw()
var rays_color := R.RAYS_COLOR:
	set(v):
		rays_color = v
		queue_redraw()
## The icon's share of the frame under Royale: -1 = R.FRAME_ICON (86 %); a screen whose icon was painted for a size sets
## its own (the Wanted `icon_frac` is not read under Royale: its values were tuned to the Wanted plate's inner box).
var icon_frac_royale := -1.0:
	set(v):
		icon_frac_royale = v
		queue_redraw()
## How far the frame's glow (epic, legendary, evolved) may reach in px under Royale: -1 = the rarity's own
## (R.FRAME_GLOW_*); a screen with frames in a tight row may cap it at half its gap. The glow never paints over an
## earlier sibling WPlate's frame anyway (`glow_cuts`), so a row's glows all sit behind their neighbours.
var glow_reach := -1.0:
	set(v):
		glow_reach = v
		queue_redraw()
## The evolved look (for_def: an evolution, a line grown from a line, a passive item's Evolved rung), kept apart from the
## brass `ring` a screen may set by hand (the Totem's carved inset keeps its own ring under Royale).
var _evolved := false
var _fill_node: Control
var _rays_node: Control
var _fill_mat: ShaderMaterial
var _rays_mat: ShaderMaterial
var _fill_key := ""
## The frame's px and glow pad as last synced (frame_metrics / glow_pad), reused by the draw (review fix: built once per
## change, not three times a draw).
var _royale_m: Dictionary = {}
var _royale_pad := 0
var _cuts := PackedVector4Array()
## The rarities whose look is a fixed triplet of R.RARITY; anything else is derived from the fill.
const FRAME_RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
## A Wanted ink fill (W.KIND["enemy"] / ["elite"]: every creature's plate) under Royale: the kit's slate panel colours with
## a muted rim, not a brown derived from the ink (review fix: the evolved look is for_def's flag alone, never the fill).
const FRAME_INK := {"light": R.SLATE_TOP, "base": R.SLATE_MID, "dark": R.SLATE_BOTTOM, "rim": R.MUTED}
## How many earlier siblings' frames a glow is cut round at most (ui_radial_fill.gdshader's `cuts[6]`).
const GLOW_CUTS := 6


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(side, side)
	set_process(false)
	# a moved or scaled plate syncs its glow's cuts against its neighbours (review fix 4)
	set_notify_local_transform(true)


func _ready() -> void:
	# Godot turns _process on at READY because the script overrides it, so _init's set_process(false) never held and
	# every plate redrew every frame (review fix 3): only the breathing evolution glow needs a frame clock
	set_process(dots_ready)
	# pass 122: the Royale layers are made before the first draw (a plate is set up before it enters the tree); under
	# Wanted nothing is added
	if W.royale():
		_ensure_royale()


func _enter_tree() -> void:
	# a neighbour added, moved or taken away changes what a glow is cut round (review fix 4)
	var parent := get_parent()
	if W.royale() and parent and not parent.child_order_changed.is_connected(_neighbours_moved):
		parent.child_order_changed.connect(_neighbours_moved)


func _exit_tree() -> void:
	var parent := get_parent()
	if parent and parent.child_order_changed.is_connected(_neighbours_moved):
		parent.child_order_changed.disconnect(_neighbours_moved)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_neighbours_moved()


## The glow's cuts may be stale: draw again (only a glowing Royale frame without rays has any).
func _neighbours_moved() -> void:
	if _fill_node and _fill_node.visible and _royale_pad > 0 and not rays:
		queue_redraw()


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
	# pass 95 (lane PASSIVES): a passive item on its Evolved rung wears the evolved look and its Evolved icon
	var evolved := W.is_evolved(def) or W.is_evolved_rung(def, level)
	fill = W.plate_fill(def, level)
	round_plate = k == "character"
	tex = W.icon_at(def, level) if def else null
	locked = is_locked
	radius = 10 if px < 140 else (12 if px < 190 else (14 if px < 240 else (18 if px < 400 else 24)))
	border = 4 if px < 140 else 5
	# an evolution: the dark plate in a brass ring (about 4 px on a HUD slot)
	ring = maxi(3, int(round(px * 0.04))) if evolved and not is_locked else 0
	ring_color = W.EVOLVED_RING
	base_ring = ring
	_evolved = evolved
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
	if W.royale():
		_draw_royale()
		return
	_hide_royale()
	_draw_wanted()


## The Wanted plate, as it has been drawn since pass 48 (pass 122 moved it here whole).
func _draw_wanted() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(side, side))
	if dots_ready and not locked:
		_glow(r)
	var f := W.AGED if locked or empty or padlock or mystery else fill
	f.a *= plate_alpha
	var bc := Color(border_color, border_color.a * plate_alpha)
	if shadow > 0:
		_shape(Rect2(r.position + Vector2(shadow, shadow), r.size), Color(W.INK, plate_alpha), 0, W.INK)
	_shape(r, f, border, bc)
	if empty:
		_dashes(r.grow(-(border + side * 0.1)))
	if padlock:
		_padlock()
	if ring > 0 and not mystery:
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
		draw_texture_rect(tex, Rect2(at, sz), false, Color(0, 0, 0, 1) if mystery else (Color(0.14, 0.106, 0.078, 0.3) if locked else Color.WHITE))
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
	if mystery:
		_mystery_mark()
	if kind_mark != "" and not empty and not padlock and not mystery:
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


## The "?" over a mystery plate (pass 69): paper slab in an ink outline, a little over half the plate high.
func _mystery_mark(ink: Color = W.INK, paper: Color = W.PAPER) -> void:
	var gf := W.slab()
	var gpx := maxi(int(round(side * 0.5)), 8)
	var gw := gf.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, gpx).x
	var gbase := side * 0.5 - gf.get_height(gpx) * 0.5 + gf.get_ascent(gpx)
	var at := Vector2((side - gw) * 0.5, gbase)
	draw_string_outline(gf, at, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, maxi(int(round(side * 0.07)), 3), ink)
	draw_string(gf, at, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, paper)


## The mutation dots along the top edge: one per mutation held, brass in an ink ring with a glint, so it reads on every
## plate colour and over the sand (pass 49: the open ones are not drawn at all).
func _dots(ink: Color = W.INK, brass: Color = W.BRASS) -> void:
	var d := dot_size()
	var rad := d * 0.5
	var edge := maxf(roundf(d * 0.12), 2.0)
	for i in dots.x:
		var c := held_center(i)
		# plain circles, not anti-aliased: an anti-aliased circle is a feathered polygon of its own and never batches, and
		# the HUD's twelve plates' dots and its empty slots' dashes were half its draw calls (pass 48, perf_late)
		draw_circle(c, rad, ink, true, -1.0, false)
		draw_circle(c, rad - edge, brass, true, -1.0, false)
		draw_circle(c + Vector2(-rad, -rad) * 0.3, rad * 0.24, Color(1.0, 0.93, 0.72, 0.9), true, -1.0, false)


## The kind's corner glyph: a paper disc in an ink ring with a hard ink shadow, the glyph (or its letter) in ink inside.
## `straight` (Royale) drops the shadow straight down.
func _kind_disc(ink: Color = W.INK, paper: Color = W.PAPER, straight: bool = false) -> void:
	var r := kind_disc()
	var c := r.get_center()
	var rad := r.size.x * 0.5
	var edge := maxf(roundf(rad * 0.16), 2.0)
	draw_circle(c + (Vector2(0.0, edge) if straight else Vector2(edge, edge) * 0.6), rad, Color(ink, 0.85), true, -1.0, true)
	draw_circle(c, rad, ink, true, -1.0, true)
	draw_circle(c, rad - edge, paper, true, -1.0, true)
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
		draw_string(gf, Vector2(c.x - gw * 0.5, gbase), t, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, ink)


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
func _dashes(rr: Rect2, c: Color = Color(W.INK_SOFT, 0.5)) -> void:
	var w := maxf(side * 0.035, 2.0)
	var dash := maxf(side * 0.09, 5.0)
	var pts: Array[Vector2] = [rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]
	# plain dashes (pass 48): anti-aliased ones were a draw call each, nine a side on every empty HUD slot
	for i in 4:
		draw_dashed_line(pts[i], pts[(i + 1) % 4], c, w, dash, true, false)


## The shut slot's padlock (drawn: no font has one): an ink shackle over an ink body that carries the stage that opens
## the slot in paper slab, or a keyhole when no stage does.
func _padlock(ink: Color = W.INK, paper: Color = W.PAPER, aged: Color = W.AGED) -> void:
	var cx := side * 0.5
	var bw := side * 0.46
	var bh := side * 0.34
	var body := Rect2(cx - bw * 0.5, side * 0.44, bw, bh)
	var sw := maxf(side * 0.075, 2.5)
	var sr := bw * 0.3
	var top := body.position.y - side * 0.04
	draw_arc(Vector2(cx, top), sr, PI, TAU, 24, ink, sw, true)
	draw_line(Vector2(cx - sr, top), Vector2(cx - sr, body.position.y + 1.0), ink, sw, true)
	draw_line(Vector2(cx + sr, top), Vector2(cx + sr, body.position.y + 1.0), ink, sw, true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ink
	sb.set_corner_radius_all(maxi(int(round(side * 0.06)), 2))
	sb.anti_aliasing = true
	draw_style_box(sb, body)
	if lock_stage > 0:
		var fnt := W.slab()
		var px := maxi(int(round(bh * 0.72)), 8)
		var txt := str(lock_stage)
		var tw := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var base := body.get_center().y - fnt.get_height(px) * 0.5 + fnt.get_ascent(px)
		draw_string(fnt, Vector2(body.get_center().x - tw * 0.5, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, paper)
	else:
		var kc := body.get_center()
		draw_circle(kc - Vector2(0, bh * 0.1), bh * 0.14, aged, true, -1.0, true)
		draw_rect(Rect2(kc.x - bh * 0.05, kc.y - bh * 0.05, bh * 0.1, bh * 0.28), aged)


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


# --- Royale (pass 122, lane UIKIT_B) -----------------------------------------------------------------------------------
## The rarity the frame shows under Royale: "common" .. "legendary" (a passive item's rarity or rung, a weapon's or
## Card's level colour: whatever the Wanted plate's colour stands for), "evolved", "locked" (a locked or mystery plate),
## "slot" (an empty or padlocked slot) or "custom" (a fill of a screen's own, derived: frame_look).
func frame_rarity() -> String:
	if empty or padlock:
		return "slot"
	if locked or mystery:
		return "locked"
	# for_def's flag alone (review fix 1): W.EVOLVED_FILL is the ink every creature plate wears (W.KIND["enemy"])
	if _evolved:
		return "evolved"
	# pass 123: a mutation's own colour, never a rarity's (W.KIND["mutation"], or a screen's R.MUTATION_FILL)
	if fill.is_equal_approx(W.PLUM) or fill.is_equal_approx(R.MUTATION_FILL):
		return "mutation"
	for k: String in FRAME_RARITIES:
		if fill.is_equal_approx(W.RARITY_PLATE[k]):
			return k
	return "custom"


## Whether the frame wears the evolved look under Royale (the black face, the rainbow rim, the EVO plaque).
func is_evolved_frame() -> bool:
	return frame_rarity() == "evolved"


## The frame's colours under Royale: {rarity, light, base, dark, rim, rim_mode (0 plain, 1 the gold bevel, 2 the
## rainbow), inner (px), glow (Color), glow_px, flat (a slate tile: no rim, no radial)}.
func frame_look() -> Dictionary:
	var r := frame_rarity()
	var out := {"rarity": r, "rim_mode": 0, "inner": 0, "glow": Color(1, 1, 1, 0), "glow_px": 0, "flat": false}
	var t: Dictionary
	match r:
		"slot":
			t = {"light": R.SLATE_DIM, "base": R.SLATE_DIM, "dark": R.SLATE_DIM, "rim": R.SLATE_DIM}
			out["flat"] = true
		"locked":
			t = R.FRAME_LOCKED
		"evolved":
			t = R.RARITY["evolved"]
			out["rim_mode"] = 2
			out["glow"] = t["glow"]
			out["glow_px"] = R.FRAME_GLOW_EVOLVED
		"custom":
			t = derive_frame(fill)
		"mutation":
			t = R.MUTATION
			out["glow"] = t["glow"]
			out["glow_px"] = R.FRAME_GLOW_EPIC
		_:
			t = R.RARITY[r]
			if r == "legendary":
				out["rim_mode"] = 1
				out["inner"] = R.FRAME_LEGEND_INNER
				out["glow"] = t["glow"]
				out["glow_px"] = R.FRAME_GLOW_LEGEND
			elif r == "epic":
				out["glow"] = t["glow"]
				out["glow_px"] = R.FRAME_GLOW_EPIC
	for k in ["light", "base", "dark", "rim"]:
		out[k] = t[k]
	return out


## A frame triplet for a colour of a screen's own (the HUD's buff plates on sage and rock, a talent form on paper), the
## way R derives uncommon: the light at .58 of the saturation and 1.12 of the value, the dark at 1.1 and .74, the rim at
## .32 of the saturation at full value. Paper and aged (and any pale, barely saturated colour) read as the common grey;
## the ink (every creature's plate) the kit's slate (FRAME_INK).
static func derive_frame(c: Color) -> Dictionary:
	if c.is_equal_approx(W.INK):
		return FRAME_INK
	if c.s < 0.3 and c.v > 0.75:
		return R.RARITY["common"]
	return {"light": Color.from_hsv(c.h, c.s * 0.58, minf(c.v * 1.12, 1.0)), "base": c,
		"dark": Color.from_hsv(c.h, minf(c.s * 1.1, 1.0), c.v * 0.74), "rim": Color.from_hsv(c.h, c.s * 0.32, 1.0)}


## The frame's px under Royale: {edge, rim, lip, drop, base}: the outline 4 from 160 up and 3 below, the rim 7 / 5 (the
## legendary's 1.5 times that), the lip, the foot and the icon's drop 3.1 % of the side (never under 2), the base 8.
func frame_metrics() -> Dictionary:
	var big := side >= 160.0
	var r := frame_rarity()
	var rim := R.FRAME_RIM_BIG if big else R.FRAME_RIM_SMALL
	if r == "legendary":
		rim = int(round(rim * R.FRAME_LEGEND_RIM))
	elif r == "slot":
		rim = 0
	var lip := maxi(int(round(side * R.FRAME_LIP_FRAC)), 2)
	return {"edge": R.FRAME_EDGE_BIG if big else R.FRAME_EDGE_SMALL, "rim": rim, "lip": lip, "drop": lip,
		"base": 0 if round_plate else R.PANEL_BASE}


## The face's rect under Royale (inside the outline and the rim).
func face_rect() -> Rect2:
	var m := frame_metrics()
	var inset := float(int(m["edge"]) + int(m["rim"]))
	return Rect2(Vector2.ZERO, Vector2(side, side)).grow(-inset)


func _hide_royale() -> void:
	if _fill_node:
		_fill_node.visible = false
	if _rays_node:
		_rays_node.visible = false


## The two layers drawn behind the plate: the rays, then the frame (both `show_behind_parent`, so the icon and the
## plaque the plate draws itself sit over them and anything a screen adds to the plate over all of it).
func _ensure_royale() -> void:
	if _fill_node != null:
		return
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = RAYS_SHADER
	_rays_node = Control.new()
	_rays_node.name = "RoyaleRays"
	_rays_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays_node.show_behind_parent = true
	_rays_node.material = _rays_mat
	_rays_node.visible = false
	_rays_node.draw.connect(func(): _rays_node.draw_rect(Rect2(Vector2.ZERO, _rays_node.size), Color.WHITE))
	add_child(_rays_node)
	move_child(_rays_node, 0)
	_fill_mat = ShaderMaterial.new()
	_fill_mat.shader = FILL_SHADER
	_fill_mat.set_shader_parameter("rainbow", PackedColorArray(R.RAINBOW))
	_fill_node = Control.new()
	_fill_node.name = "RoyaleFrame"
	_fill_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_node.show_behind_parent = true
	_fill_node.material = _fill_mat
	_fill_node.draw.connect(func(): _fill_node.draw_rect(Rect2(Vector2.ZERO, _fill_node.size), Color.WHITE))
	add_child(_fill_node)
	move_child(_fill_node, 1)


## The glow's reach in px for a look: its rarity's glow, no further than `glow_reach` when a screen set one.
func glow_pad(look: Dictionary) -> int:
	var g := int(look["glow_px"])
	if glow_reach >= 0.0:
		g = mini(g, int(round(glow_reach)))
	return g


## The frame's and the rays' rects and uniforms for what the plate is now (set again only when something changed). The
## key is the fields the look and the px are made of (review fix 3: no look or metrics built just to compare).
func _sync_royale() -> void:
	var edge_col := R.NAVY if border_color.is_equal_approx(W.INK) else border_color
	var key := "%d%d%d%d%d|%.1f|%s|%d|%.2f|%s|%.1f" % [int(empty), int(padlock), int(locked), int(mystery), int(_evolved),
		side, fill.to_html(true), int(round_plate), plate_alpha, edge_col.to_html(true), glow_reach]
	_fill_node.visible = true
	if key != _fill_key:
		_fill_key = key
		var look := frame_look()
		var m := frame_metrics()
		var pad := glow_pad(look)
		_royale_m = m
		_royale_pad = pad
		_fill_node.position = Vector2(-pad, -pad)
		_fill_node.size = Vector2(side + 2 * pad, side + 2 * pad + int(m["base"]))
		var p := _fill_mat
		p.set_shader_parameter("size", _fill_node.size)
		p.set_shader_parameter("pad", float(pad))
		p.set_shader_parameter("base_px", float(m["base"]))
		p.set_shader_parameter("radius", float(R.RADIUS))
		p.set_shader_parameter("shape", 1 if round_plate else 0)
		p.set_shader_parameter("edge_px", float(m["edge"]))
		p.set_shader_parameter("edge_color", edge_col)
		p.set_shader_parameter("rim_px", float(m["rim"]))
		p.set_shader_parameter("rim_mode", int(look["rim_mode"]))
		if int(look["rim_mode"]) == 1:
			p.set_shader_parameter("rim_a", R.RIM_BEVEL[0])
			p.set_shader_parameter("rim_b", R.RIM_BEVEL[1])
			p.set_shader_parameter("rim_c", R.RIM_BEVEL[2])
			p.set_shader_parameter("rim_d", R.RIM_BEVEL[3])
		else:
			p.set_shader_parameter("rim_a", look["rim"])
			p.set_shader_parameter("rim_b", look["base"])
		p.set_shader_parameter("inner_px", float(look["inner"]))
		p.set_shader_parameter("inner_color", R.RARITY["legendary"]["inner"])
		p.set_shader_parameter("face_radius", 0.0 if round_plate else R.FRAME_FACE_RADIUS)
		p.set_shader_parameter("light", look["light"])
		p.set_shader_parameter("base", look["base"])
		p.set_shader_parameter("dark", look["dark"])
		p.set_shader_parameter("center", R.FRAME_CENTER)
		p.set_shader_parameter("base_at", R.FRAME_BASE_AT)
		var flat := bool(look["flat"])
		p.set_shader_parameter("lip_px", 0.0 if flat else float(m["lip"]))
		p.set_shader_parameter("lip_alpha", R.FRAME_LIP)
		p.set_shader_parameter("foot_px", 0.0 if flat else float(m["lip"]))
		p.set_shader_parameter("foot_alpha", R.FRAME_FOOT)
		p.set_shader_parameter("glow_px", float(pad))
		p.set_shader_parameter("glow_color", look["glow"])
		p.set_shader_parameter("alpha", plate_alpha)
		p.set_shader_parameter("cut_radius", float(R.RADIUS))
		p.set_shader_parameter("cut_base", float(R.PANEL_BASE))
		p.set_shader_parameter("cut_count", 0)
		_cuts = PackedVector4Array()
		_fill_node.queue_redraw()
	_sync_cuts()
	_rays_node.visible = rays
	if rays:
		var d := roundf(side * rays_scale)
		_rays_node.position = Vector2((side - d) * 0.5, (side - d) * 0.5)
		_rays_node.size = Vector2(d, d)
		_rays_mat.set_shader_parameter("size", d)
		_rays_mat.set_shader_parameter("color", rays_color)
		_rays_mat.set_shader_parameter("on_deg", R.RAYS_ON_DEG)
		_rays_mat.set_shader_parameter("period_deg", R.RAYS_PERIOD_DEG)
		_rays_mat.set_shader_parameter("mask_in", R.RAYS_MASK_IN)
		_rays_mat.set_shader_parameter("mask_out", R.RAYS_MASK_OUT)
		_rays_mat.set_shader_parameter("turn_s", R.RAYS_TURN_S)
		_rays_node.queue_redraw()


## The glow's cuts for what stands round the plate now, set when they changed (review fix 4: a glow painted by a child
## behind its plate lay over the earlier sibling's frame and under the later one's; cut where the earlier frames stand,
## every glow in a row sits behind its neighbours, as one glow field under the row would paint them).
func _sync_cuts() -> void:
	var cuts := PackedVector4Array()
	if _royale_pad > 0 and not rays and is_inside_tree():
		cuts = glow_cuts(_royale_pad)
	if cuts == _cuts:
		return
	_cuts = cuts
	_fill_mat.set_shader_parameter("cut_count", cuts.size())
	if not cuts.is_empty():
		var full := cuts.duplicate()
		full.resize(GLOW_CUTS)
		_fill_mat.set_shader_parameter("cuts", full)
	_fill_node.queue_redraw()


## The frames of the earlier sibling WPlates a glow of `pad` px would paint over, as the shader's cuts: (centre x, centre
## y) in the frame layer's px, the half side, how solid the neighbour is (its plate_alpha and modulate). A sibling drawn
## later covers the glow by itself; a frame with its rays on (the chest's, the offer's, a held card's) paints over
## everything and has none. At most GLOW_CUTS, the nearest in the tree first.
func glow_cuts(pad: int) -> PackedVector4Array:
	var out := PackedVector4Array()
	var parent := get_parent()
	if parent == null:
		return out
	var inv := get_transform().affine_inverse()
	var base := float(int(_royale_m.get("base", R.PANEL_BASE)))
	var reach := Rect2(Vector2(-pad, -pad), Vector2(side + 2.0 * pad, side + 2.0 * pad + base))
	for i in get_index():
		var sib := parent.get_child(i) as WPlate
		if sib == null or not sib.visible or sib.plate_alpha <= 0.0 or sib.modulate.a <= 0.0:
			continue
		var t := inv * sib.get_transform()
		var sr := t * Rect2(Vector2.ZERO, Vector2(sib.side, sib.side))
		var footed := Rect2(sr.position, sr.size + Vector2(0.0, 0.0 if sib.round_plate else float(R.PANEL_BASE)))
		if not footed.intersects(reach):
			continue
		var a := clampf(sib.plate_alpha * sib.modulate.a * sib.self_modulate.a, 0.0, 1.0)
		var c := sr.get_center() + Vector2(pad, pad)
		out.append(Vector4(c.x, c.y, sr.size.x * 0.5, a))
		if out.size() >= GLOW_CUTS:
			break
	return out


## Whether a ring a screen set by hand is drawn under Royale: not on an evolved frame (its rainbow rim is the ring) nor
## a mystery plate; its colour whatever it is (review fix 2: a brass ring, the Collection's special creatures, was
## skipped for being the evolved ring's colour).
func ring_shown() -> bool:
	return ring > 0 and not is_evolved_frame() and not mystery


## A hand-set ring's colour under Royale: brass -> the kit's gold, rock -> its red, anything else through R.text_colour
## (ember and a screen's own colour, the Totem's carved inset, stay as they are).
static func royale_ring_colour(c: Color) -> Color:
	if c.is_equal_approx(W.BRASS) or c.is_equal_approx(W.BRASS_DARK):
		return R.role("gold")["bottom"]
	if c.is_equal_approx(W.ROCK):
		return R.role("red")["bottom"]
	return R.text_colour(c)


## The Royale frame's top: the icon with its hard drop, a slot's dashes or padlock, the glyph, the badge, the "?" of a
## mystery, the kind disc, the dots, a hand-set ring, and the plaque (EVO on gold for an evolved item, "LV n" or a plain
## "n" for `level_plaque`, else `level_text` as it is).
func _draw_royale() -> void:
	_ensure_royale()
	_sync_royale()
	var m := _royale_m
	var r := Rect2(Vector2.ZERO, Vector2(side, side))
	var gold: Color = R.role("gold")["bottom"]
	if dots_ready and not locked:
		_glow_royale(r, gold)
	if empty:
		_dashes(r.grow(-(int(m["edge"]) + side * 0.1)), Color(1, 1, 1, 0.28))
	if padlock:
		_padlock(R.NAVY, R.CREAM, R.SECONDARY)
	if ring_shown():
		# a ring a screen set by hand (the Totem's carved inset, the Collection's dangerous creatures), just inside the
		# outline, in the kit's colour for it
		var rcol := royale_ring_colour(ring_color)
		var rc := Color(rcol, rcol.a * plate_alpha)
		var rr := r.grow(-float(int(m["edge"])))
		if round_plate:
			draw_arc(rr.get_center(), rr.size.x * 0.5 - ring * 0.5, 0.0, TAU, 64, rc, ring, true)
		else:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_corner_radius_all(maxi(R.RADIUS - int(m["edge"]), 2))
			sb.set_border_width_all(ring)
			sb.border_color = rc
			sb.anti_aliasing = true
			draw_style_box(sb, rr)
	if tex:
		var frac := icon_frac_royale if icon_frac_royale > 0.0 else R.FRAME_ICON
		var inner := side * frac
		var ts := tex.get_size()
		var k := inner / maxf(ts.x, ts.y)
		var sz := ts * k
		# the mock lifts the icon a touch off the centre (translateY(-6px) at 320)
		var at := (Vector2(side, side) - sz) * 0.5 - Vector2(0.0, roundf(side * 0.019))
		if round_plate:
			var e := float(int(m["edge"]))
			at = Vector2(e, e)
			sz = Vector2(side - e * 2.0, side - e * 2.0)
		if mystery:
			draw_texture_rect(tex, Rect2(at, sz), false, Color(0, 0, 0, 1))
		elif locked:
			draw_texture_rect(tex, Rect2(at, sz), false, Color(R.NAVY, 0.6))
		else:
			draw_texture_rect(tex, Rect2(at + Vector2(0.0, float(int(m["drop"]))), sz), false, R.FRAME_ICON_DROP)
			draw_texture_rect(tex, Rect2(at, sz), false, Color.WHITE)
	elif glyph != "" and not empty and not padlock:
		var gpx := maxi(int(round(side * 0.56)), 8)
		var gf := W.slab_for(gpx)
		var gw := gf.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx).x
		var gbase := side * 0.5 - gf.get_height(gpx) * 0.5 + gf.get_ascent(gpx)
		var gat := Vector2((side - gw) * 0.5, gbase)
		var gc := R.text_colour(glyph_color)
		if R.is_display(gf):
			draw_string_outline(gf, gat + Vector2(0, R.drop_px(gpx)), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, R.stroke_px(gpx), R.NAVY)
			draw_string_outline(gf, gat, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, R.stroke_px(gpx), R.NAVY)
		draw_string(gf, gat, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gpx, gc)
	if badge:
		var bp := badge_px if badge_px > 0.0 else side * 0.34
		var bs := badge.get_size()
		var bk := bp / maxf(bs.x, bs.y)
		draw_texture_rect(badge, Rect2(Vector2(-bp * 0.3, -bp * 0.3), bs * bk), false, Color(1, 1, 1, 0.6) if locked else Color.WHITE)
	if mystery:
		_mystery_mark(R.NAVY, R.CREAM)
	if kind_mark != "" and not empty and not padlock and not mystery:
		_kind_disc(R.NAVY, R.CREAM, true)
	if dots.x > 0 and not locked:
		_dots(R.NAVY, gold)
	if _evolved and not locked and not mystery:
		_plaque("EVO", R.PLAQUE_EVO_TOP, R.PLAQUE_EVO_BOTTOM, R.PLAQUE_EVO_TEXT)
	elif level_plaque > 0:
		_plaque(plaque_text(level_plaque), R.PLAQUE_TOP, R.PLAQUE_BOTTOM, R.PLAQUE_TEXT)
	elif level_text != "":
		var top: Color = R.PLAQUE_EVO_TOP if level_fill.is_equal_approx(W.BRASS) else R.PLAQUE_TOP
		var bottom: Color = R.PLAQUE_EVO_BOTTOM if level_fill.is_equal_approx(W.BRASS) else R.PLAQUE_BOTTOM
		_plaque(level_text, top, bottom, R.PLAQUE_EVO_TEXT if level_fill.is_equal_approx(W.BRASS) else R.PLAQUE_TEXT)


## What the level plaque says for level `n` on this frame: "LV n", a plain "n" on a frame of R.PLAQUE_PLAIN_AT or less.
func plaque_text(n: int) -> String:
	return str(n) if side <= R.PLAQUE_PLAIN_AT else "LV %d" % n


## The plaque's box: its height, type size and edge from the side (R.PLAQUE_*), hanging PLAQUE_HANG of its height below
## the frame's foot, centred.
func plaque_rect(text: String) -> Rect2:
	var px := plaque_px()
	return _plaque_box(W.slab_for(px).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x)


## The plaque's box round text `tw` px wide (measured once by whoever draws it).
func _plaque_box(tw: float) -> Rect2:
	var h := maxf(roundf(side * R.PLAQUE_H_FRAC), float(R.PLAQUE_H_MIN))
	var px := plaque_px()
	var edge := float(R.PLAQUE_EDGE if side >= 160.0 else R.PLAQUE_EDGE_SMALL)
	var padx := roundf(px * R.PLAQUE_PAD_FRAC)
	var w := ceilf(tw) + padx * 2.0 + edge * 2.0
	var hang := roundf(h * R.PLAQUE_HANG)
	return Rect2(Vector2(roundf((side - w) * 0.5), side - (h - hang)), Vector2(w, h))


func plaque_px() -> int:
	return maxi(int(round(side * R.PLAQUE_FONT_FRAC)), R.PLAQUE_FONT_MIN)


func _plaque(text: String, top: Color, bottom: Color, text_col: Color) -> void:
	var px := plaque_px()
	var f := W.slab_for(px)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var rect := _plaque_box(tw)
	var edge := float(R.PLAQUE_EDGE if side >= 160.0 else R.PLAQUE_EDGE_SMALL)
	R.flat(R.NAVY, R.RADIUS_TAG).draw(get_canvas_item(), rect)
	var inner := rect.grow(-edge)
	R.gradient(get_canvas_item(), inner, [[0.0, top], [1.0, bottom]])
	var base := inner.position.y + (inner.size.y - f.get_height(px)) * 0.5 + f.get_ascent(px)
	draw_string(f, Vector2(inner.get_center().x - tw * 0.5, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, text_col)


## The evolution-ready glow under Royale: gold rings outside the frame, fading out, breathing (the face stays clear:
## the plate draws over its frame).
func _glow_royale(r: Rect2, gold: Color) -> void:
	var breath := GLOW_LOW + (1.0 - GLOW_LOW) * (0.5 + 0.5 * sin(_glow_t / GLOW_PERIOD * TAU))
	var reach := maxf(side * 0.17, 8.0)
	var layers := 6
	var step := reach / float(layers)
	for i in layers:
		var k := float(i) / float(layers)
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_corner_radius_all(int(R.RADIUS + step * (i + 1)))
		sb.set_border_width_all(int(ceil(step)) + 1)
		sb.border_color = Color(gold.r, gold.g, gold.b, 0.11 * (1.0 - k) * breath)
		sb.anti_aliasing = true
		draw_style_box(sb, r.grow(step * (i + 1)))
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.set_corner_radius_all(R.RADIUS + 3)
	edge.set_border_width_all(maxi(int(round(side * 0.035)), 2))
	edge.border_color = Color(gold, 0.85 * breath)
	edge.anti_aliasing = true
	draw_style_box(edge, r.grow(3.0))
