## A Wanted poster (pass 111, lane WANTED: the Bounty Board's contracts, core/systems/WantedBoard.gd): sun-aged paper
## with torn edges and a soft stain, a brass nail at its top, "WANTED" in the slab face over a double rule, the target's
## picture large in an ink frame (a creature's front still from the strip of the look it is played in, a weapon's or a
## card's icon, the hero's title cut-out, the stage's picture, the chest, the coin; a badge in its corner where the task
## says skull, crown, gear or heart), the target's name, the task, REWARD with the coin and the gold, and the
## difficulty as five skulls. Existing art only (Garry: "Try using existing enemy, hero and item art whenever possible").
## A WTap: a tap emits `pressed` (the board selects it); `selected` rings it in brass. The polygon of its torn edge is
## simple (its corners kept out of the ragged sides), so the paper fills whole.
class_name WPoster
extends WTap

const W_PX := 316.0
const H_PX := 760.0
## The picture's box inside the poster (its share of the width, its height) and the badge in its corner.
const PIC_W := 0.84
const PIC_H := 350.0
const BADGE_PX := 58.0
const SKULL_PX := 34.0
const TEAR := 7.0
## Pass 113 (lane TASKS): the barrel and the poison flask (painted for the task types), the fire (the damage sources' own).
const ART := {"chest": "res://art/ui/wanted/chest_closed.png", "coin": "res://art/ui/wanted/coin.png",
	"barrel": "res://art/ui/wanted/barrel.png", "poison": "res://art/ui/wanted/poison.png", "fire": "res://art/ui/sources/fire.png"}
const BADGE_PATH := "res://art/ui/badges/%s.png"
## The Stages menu's helpers: a stage's picture.
const StagesScreenScript := preload("res://ui/StagesScreen.gd")

var contract: Dictionary = {}
var selected := false:
	set(v):
		selected = v
		queue_redraw()
## The torn edge's points, made once from the contract (the same poster tears the same way).
var _edge := PackedVector2Array()
var _seed := 0
var _px := W_PX / W_PX


static func make(c: Dictionary, width: float = W_PX) -> WPoster:
	var p := WPoster.new()
	p.contract = c
	p._px = width / W_PX
	p._seed = str(c.get("type", "")).hash() ^ str(c.get("target", "")).hash() ^ int(c.get("n", 0))
	p.custom_minimum_size = Vector2(W_PX, H_PX) * p._px
	p.size = p.custom_minimum_size
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	p._build()
	return p


func _restyle() -> void:
	queue_redraw()


func _build() -> void:
	var k := _px
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", int(24 * k))
	pad.add_theme_constant_override("margin_right", int(24 * k))
	pad.add_theme_constant_override("margin_top", int(26 * k))
	pad.add_theme_constant_override("margin_bottom", int(20 * k))
	add_child(pad)
	var v := VBoxContainer.new()
	v.name = "Body"
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", int(6 * k))
	pad.add_child(v)
	var head := W.text("WANTED", W.slab(W.em(int(48 * k), 0.03)), int(48 * k), W.INK, HORIZONTAL_ALIGNMENT_CENTER, 54.0 * k)
	head.name = "Wanted"
	v.add_child(head)
	v.add_child(_rule(k))
	v.add_child(_picture(k))
	var nm := _fit_text(str(contract.get("name", "")).to_upper(), W.slab(), int(36 * k), int(22 * k), (W_PX - 48.0) * k)
	nm.name = "Name"
	v.add_child(nm)
	var task := W.serif_text(str(contract.get("text", "")), int(27 * k), W.INK_SOFT, 600, false, HORIZONTAL_ALIGNMENT_CENTER, 32.0 * k, true)
	task.name = "Task"
	v.add_child(task)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)
	var rl := W.label("Reward", int(16 * k), W.INK_SOFT, 0.3)
	rl.align = HORIZONTAL_ALIGNMENT_CENTER
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rl)
	var rr := HBoxContainer.new()
	rr.name = "Reward"
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	rr.add_theme_constant_override("separation", int(10 * k))
	rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the gold coin; another currency (the config's reward.currency) shows its own icon
	var cur := WantedBoard.currency()
	if cur == Currency.DEFAULT or Currency.icon(cur) == null:
		var coin := WCoin.make(44.0 * k, W.BRASS, 3.0)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rr.add_child(coin)
	else:
		var ci := TextureRect.new()
		ci.texture = Currency.icon(cur)
		ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ci.custom_minimum_size = Vector2(44, 44) * k
		ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rr.add_child(ci)
	var amt := W.slab_text(W.num(int(contract.get("reward", 0))), int(52 * k), W.BRASS_DARK, HORIZONTAL_ALIGNMENT_LEFT, 54.0 * k)
	amt.name = "Amount"
	amt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(amt)
	v.add_child(rr)
	v.add_child(_skulls(k))
	# the nail on a plain layer over the paper (the poster is a container: it lays out its own children, never the layer's)
	var over := Control.new()
	over.name = "Over"
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(over)
	var nail := WNail.new()
	nail.name = "Nail"
	nail.size = Vector2(30, 30) * k
	nail.custom_minimum_size = nail.size
	nail.position = Vector2(W_PX * 0.5 - 15.0, 6.0) * k
	over.add_child(nail)


## The double rule under WANTED.
func _rule(k: float) -> Control:
	var r := Control.new()
	r.custom_minimum_size = Vector2(0, 12 * k)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.draw.connect(func():
		r.draw_line(Vector2(0, 3 * k), Vector2(r.size.x, 3 * k), W.INK, 3.0 * k)
		r.draw_line(Vector2(0, 9 * k), Vector2(r.size.x, 9 * k), W.INK, 1.5 * k))
	return r


## The picture: an aged box framed in ink, the target's still covering it as it fits, a badge in its top-left corner.
func _picture(k: float) -> Control:
	var box := Control.new()
	box.name = "Picture"
	box.custom_minimum_size = Vector2(0, PIC_H * k)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	var still: Dictionary = contract.get("still", {}) if contract.get("still") is Dictionary else {}
	var kind := str(still.get("kind", ""))
	box.draw.connect(func():
		box.draw_rect(Rect2(Vector2.ZERO, box.size), W.AGED.lerp(W.PAPER, 0.35))
		# a few sun rays behind a figure (not behind a stage picture, which covers the box)
		if kind != "stage":
			var c := Vector2(box.size.x * 0.5, box.size.y * 0.62)
			for i in 12:
				var a := TAU * float(i) / 12.0
				var p1 := c + Vector2(cos(a - 0.09), sin(a - 0.09)) * box.size.x
				var p2 := c + Vector2(cos(a + 0.09), sin(a + 0.09)) * box.size.x
				box.draw_colored_polygon(PackedVector2Array([c, p1, p2]), Color(W.BRASS, 0.13))
	)
	var tex := still_texture(still)
	var tr := TextureRect.new()
	tr.name = "Still"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if kind == "stage" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := 0.0 if kind == "stage" else 10.0 * k
	tr.offset_left = inset
	tr.offset_right = -inset
	tr.offset_top = inset
	tr.offset_bottom = -inset * 0.4
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var bpath := BADGE_PATH % str(still.get("badge", "")) if str(still.get("badge", "")) != "" else ""
	if kind == "badge":
		bpath = ""
	if bpath != "" and ResourceLoader.exists(bpath):
		var b := TextureRect.new()
		b.name = "Badge"
		b.texture = load(bpath)
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b.position = Vector2(4, 4) * k
		b.size = Vector2(BADGE_PX, BADGE_PX) * k
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(b)
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.draw.connect(func(): frame.draw_rect(Rect2(Vector2.ZERO, frame.size), W.INK, false, 4.0 * k))
	box.add_child(frame)
	return box


## Five skulls: as many in full ink as the poster's difficulty, the rest faint.
func _skulls(k: float) -> Control:
	var h := HBoxContainer.new()
	h.name = "Skulls"
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", int(4 * k))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := clampi(int(contract.get("skulls", WantedBoard.skulls_of(float(contract.get("d", 1.0))))), 1, 5)
	var tex: Texture2D = load(BADGE_PATH % "skull") if ResourceLoader.exists(BADGE_PATH % "skull") else null
	for i in 5:
		var s := TextureRect.new()
		s.name = "Skull%d" % (i + 1)
		s.texture = tex
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		s.custom_minimum_size = Vector2(SKULL_PX, SKULL_PX) * k
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.modulate = Color.WHITE if i < n else Color(0.35, 0.3, 0.25, 0.28)
		s.set_meta("lit", i < n)
		h.add_child(s)
	return h


## A one-line slab label at `px`, smaller down to `min_px` until it fits `width`; it wraps past that.
static func _fit_text(t: String, f: Font, px: int, min_px: int, width: float) -> WText:
	var fit := px
	while fit > min_px and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fit).x > width:
		fit -= 1
	return W.text(t, f, fit, W.INK, HORIZONTAL_ALIGNMENT_CENTER, fit * 1.05, true)


# ---------------------------------------------------------------- the paper

func _ready() -> void:
	super._ready()
	_make_edge()


## The torn outline: the top almost straight, the sides a little ragged, the bottom torn; one shape per poster.
func _make_edge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var w := W_PX * _px
	var h := H_PX * _px
	var t := TEAR * _px
	var pts := PackedVector2Array()
	var steps_x := 14
	var steps_y := 22
	# the top left to right, the right side down (its corners left to the top and the foot), the torn foot right to left,
	# the left side up: every point further round than the one before, so the outline never crosses itself
	for i in steps_x + 1:
		pts.append(Vector2(w * float(i) / float(steps_x), rng.randf_range(0.0, t * 0.35)))
	for i in range(1, steps_y):
		pts.append(Vector2(w - rng.randf_range(0.0, t * 0.6), h * float(i) / float(steps_y)))
	for i in range(steps_x * 2, -1, -1):
		var x := w * float(i) / float(steps_x * 2)
		pts.append(Vector2(x, h - rng.randf_range(0.0, t * 1.6) - (t * 0.8 if i % 2 == 0 else 0.0)))
	for i in range(steps_y - 1, 0, -1):
		pts.append(Vector2(rng.randf_range(0.0, t * 0.6), h * float(i) / float(steps_y)))
	_edge = pts
	queue_redraw()


func _draw() -> void:
	if _edge.is_empty():
		return
	var k := _px
	var held := _held_look
	var off := Vector2(4, 4) * k if held else Vector2.ZERO
	# the hard shadow, then the paper
	var shadow := PackedVector2Array()
	for p in _edge:
		shadow.append(p + Vector2(8, 10) * k)
	draw_colored_polygon(shadow, Color(W.INK, 0.38 if not held else 0.2))
	var paper := PackedVector2Array()
	for p in _edge:
		paper.append(p + off)
	if selected:
		# the brass ring round the chosen one
		var ring := PackedVector2Array(paper)
		ring.append(paper[0])
		draw_polyline(ring, W.BRASS, 16.0 * k, true)
	draw_colored_polygon(paper, W.PAPER.lerp(W.AGED, 0.5))
	# the stains: soft aged blots by the corners and the edges
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 7
	for i in 7:
		var c := Vector2(rng.randf_range(0.0, size.x), rng.randf_range(0.0, size.y)) + off
		if i < 4:
			c = Vector2(size.x * float(i % 2), size.y * floorf(i / 2.0)) + off
		var r := rng.randf_range(60.0, 120.0) * k
		for j in 4:
			draw_circle(c, r * (1.0 - 0.22 * float(j)), Color(W.AGED.darkened(0.2), 0.09), true, -1.0, true)
	var outline := PackedVector2Array(paper)
	outline.append(paper[0])
	draw_polyline(outline, Color(W.INK, 0.75), 2.0 * k, true)
	# the printer's inner frame
	var inner := Rect2(Vector2(12, 12) * k + off, size - Vector2(24, 28) * k)
	draw_rect(inner, Color(W.INK, 0.55), false, 2.0 * k)


# ---------------------------------------------------------------- the pictures (existing art only)

## The picture of a poster's `still` ({kind, id, ...}): a creature's front still (frame 0 of the strip of the look it is
## played in: Registry.enemy carries the played look), else its icon; a weapon's or a card's icon in the look it plays; the
## hero's title cut-out in his played look (his head and shoulders), else his badge; the stage's picture; the chest; the
## coin; a badge. Null when there is nothing to draw.
static func still_texture(still: Dictionary) -> Texture2D:
	var id := str(still.get("id", ""))
	match str(still.get("kind", "")):
		"enemy", "boss":
			var def: EnemyDef = Registry.enemy(id)
			if def == null:
				return null
			var f := front_still(def)
			return f if f else def.icon
		"weapon":
			var w: WeaponDef = Registry.weapon(id)
			return w.icon if w else null
		"card", "passive":
			var p: PassiveDef = Registry.passive(id)
			return p.icon if p else null
		# pass 113 (lane TASKS): a power-up's icon (the Heart), a structure's (the Healing Well, the Totem Pole)
		"pickup":
			var pk: PickupDef = Registry.pickup(id)
			return pk.icon if pk else null
		"structure":
			# its painting on the map (art/sprites/props/st_<id>.png, the Healing Well's well), else its icon
			var sp := "res://art/sprites/props/st_%s.png" % id
			if ResourceLoader.exists(sp):
				return load(sp)
			var sd: StructureDef = Registry.structure(id)
			return sd.icon if sd else null
		"hero":
			var c: CharacterDef = Registry.character(id)
			if c == null:
				return null
			var look := Registry.played_look(c)
			var tp := look.title_path() if look else ""
			if tp != "" and ResourceLoader.exists(tp):
				var t: Texture2D = load(tp)
				var a := AtlasTexture.new()
				a.atlas = t
				# head to waist: the top of the cut-out as wide as it is, a little taller
				a.region = Rect2(0, 0, t.get_width(), minf(t.get_height(), t.get_width() * 0.95))
				return a
			return look.icon if look else c.icon
		"stage":
			var m: MapDef = Registry.map(id)
			if m == null or m.timeline == null:
				return null
			var k := int(still.get("stage", 0))
			var path: String = StagesScreenScript.shot_path(id, k, m.timeline.stage_entry(k))
			return load(path) if path != "" and ResourceLoader.exists(path) else null
		"art":
			var ap := str(ART.get(id, ""))
			return load(ap) if ap != "" and ResourceLoader.exists(ap) else null
		"badge":
			var bp := BADGE_PATH % id
			return load(bp) if ResourceLoader.exists(bp) else null
	return null


## Pass 113 (lane TASKS): a quest's words with its picture on their left (QuestTracker.picture: the poster's own still,
## its small picture at `px`), for the Collection's locked box and the hero sheet's; the words alone when the quest names
## nothing to draw. `words` keeps its own size and wraps in what is left of the row.
static func with_picture(q: QuestDef, words: Control, px: float = 40.0) -> Control:
	var still := QuestTracker.picture(q) if q else {}
	var tex: Texture2D = thumb_texture(still) if not still.is_empty() else null
	if tex == null:
		return words
	var h := HBoxContainer.new()
	h.name = "QuestWords"
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.name = "QuestPicture"
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if str(still.get("kind", "")) == "stage" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.clip_contents = true
	pic.custom_minimum_size = Vector2(px, px)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pic)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(words)
	return h


## The small picture of a poster's target (the HUD's plate, the pause screen, the Results' row): a creature's, a weapon's
## or a card's icon, the hero's badge, else the poster's own still.
static func thumb_texture(still: Dictionary) -> Texture2D:
	var id := str(still.get("id", ""))
	match str(still.get("kind", "")):
		"enemy", "boss":
			var def: EnemyDef = Registry.enemy(id)
			return def.icon if def and def.icon else still_texture(still)
		"hero":
			var c: CharacterDef = Registry.character(id)
			var look := Registry.played_look(c) if c else null
			return look.icon if look and look.icon else still_texture(still)
	return still_texture(still)


## A creature's front still: the first cell (the standing idle frame) of its strip, cut out of the grid the strip is
## (strip_cols per row, else every frame in one row). Null without a strip.
static func front_still(def: EnemyDef) -> Texture2D:
	var tex: Texture2D = def.sprite
	if tex == null:
		return null
	var total := def.total_frames()
	var cols: int = def.strip_cols if def.strip_cols > 0 else total
	var rows := int(ceil(float(total) / float(maxi(cols, 1))))
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2(0, 0, float(tex.get_width()) / float(maxi(cols, 1)), float(tex.get_height()) / float(maxi(rows, 1)))
	return a
