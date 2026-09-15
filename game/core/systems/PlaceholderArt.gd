## Draws goofy placeholder sprites and icons from each content item's `placeholder` hints,
## both at runtime (when a file is missing) and from tools/gen_placeholders.gd (to write PNGs).
## Every character shares the animation set from design bible section 15.
class_name PlaceholderArt
extends RefCounted

const ENEMY_ORDER := ["idle", "run", "attack", "hit", "die"]
const CHAR_ORDER := ["idle", "run", "turn", "hit", "die", "cheer", "idle_f", "run_f", "idle_s", "run_s", "idle_bd", "run_bd", "idle_fd", "run_fd", "hit_f", "hit_s", "hit_bd", "hit_fd"]
const OUTLINE := Color(0.13, 0.08, 0.1)


static func _col(hint, fallback: Color) -> Color:
	if hint is String and hint != "":
		return Color(hint)
	return fallback


# ---------------------------------------------------------------- image helpers

static func fill_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var x0 := int(max(floor(cx - rx), 0))
	var x1 := int(min(ceil(cx + rx), img.get_width() - 1))
	var y0 := int(max(floor(cy - ry), 0))
	var y1 := int(min(ceil(cy + ry), img.get_height() - 1))
	for y in range(y0, y1 + 1):
		var dy := (y + 0.5 - cy) / ry
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5 - cx) / rx
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


static func fill_rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := Rect2i(int(x), int(y), int(w), int(h)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


static func fill_tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var minx := int(max(floor(min(a.x, b.x, c.x)), 0))
	var maxx := int(min(ceil(max(a.x, b.x, c.x)), img.get_width() - 1))
	var miny := int(max(floor(min(a.y, b.y, c.y)), 0))
	var maxy := int(min(ceil(max(a.y, b.y, c.y)), img.get_height() - 1))
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := _sign(p, a, b)
			var d2 := _sign(p, b, c)
			var d3 := _sign(p, c, a)
			var has_neg := d1 < 0 or d2 < 0 or d3 < 0
			var has_pos := d1 > 0 or d2 > 0 or d3 > 0
			if not (has_neg and has_pos):
				img.set_pixel(x, y, col)


static func _sign(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)


static func line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var n := int((b - a).length() / max(w * 0.5, 1.0)) + 1
	for k in range(n + 1):
		var p := a.lerp(b, float(k) / float(n))
		fill_ellipse(img, p.x, p.y, w * 0.5, w * 0.5, c)


# ---------------------------------------------------------------- sprites

## Draws one frame of a creature into `img` at cell origin (ox, oy) with cell size `s`.
## pose: {"lean": -1..1, "bob": px, "squash": 0..1, "eyes": "open|x|shut", "tint": Color?, "back": bool}
static func draw_creature(img: Image, ox: int, oy: int, s: int, ph: Dictionary, pose: Dictionary) -> void:
	var body := _col(ph.get("color"), Color(0.8, 0.6, 0.35))
	if pose.has("tint"):
		body = body.lerp(pose["tint"], 0.7)
	var shape := str(ph.get("shape", "blob"))
	var ears := str(ph.get("ears", "none"))
	var lean := float(pose.get("lean", 0.0))
	var bob := float(pose.get("bob", 0.0))
	var squash := float(pose.get("squash", 0.0))
	var cx := ox + s * 0.5 + lean * s * 0.06
	var base_y := oy + s * 0.92
	var rx := s * 0.30
	var ry := s * 0.30
	match shape:
		"ant":
			rx = s * 0.26; ry = s * 0.18
		"tall":
			rx = s * 0.20; ry = s * 0.40
		"wide":
			rx = s * 0.38; ry = s * 0.26
		"ball":
			rx = s * 0.36; ry = s * 0.36
		"disc":
			rx = s * 0.38; ry = s * 0.14
	rx *= 1.0 + squash * 0.35
	ry *= 1.0 - squash * 0.35
	var cy := base_y - ry - bob
	# legs / feet
	var feet := body.darkened(0.35)
	if shape == "ant":
		for k in range(3):
			var lx := cx - rx * 0.6 + k * rx * 0.6
			line(img, Vector2(lx, cy + ry * 0.3), Vector2(lx - s * 0.08 + lean * 4.0, base_y), s * 0.04, feet)
	elif shape != "disc" and shape != "ball":
		fill_ellipse(img, cx - rx * 0.45, base_y - s * 0.03, s * 0.12, s * 0.05, feet)
		fill_ellipse(img, cx + rx * 0.45, base_y - s * 0.03, s * 0.12, s * 0.05, feet)
	# ears / horns / hat before body so body overlaps their base
	match ears:
		"pointed":
			fill_tri(img, Vector2(cx - rx * 0.75, cy - ry * 0.5), Vector2(cx - rx * 0.55, cy - ry * 1.55), Vector2(cx - rx * 0.15, cy - ry * 0.7), body.darkened(0.25))
			fill_tri(img, Vector2(cx + rx * 0.75, cy - ry * 0.5), Vector2(cx + rx * 0.55, cy - ry * 1.55), Vector2(cx + rx * 0.15, cy - ry * 0.7), body.darkened(0.25))
		"horn":
			fill_tri(img, Vector2(cx - rx * 0.2, cy - ry * 0.6), Vector2(cx - rx * 0.05, cy - ry * 1.8), Vector2(cx + rx * 0.25, cy - ry * 0.7), Color(0.22, 0.14, 0.1))
		"arms":
			fill_rect(img, cx - rx * 1.5, cy - ry * 0.2, rx * 0.5, ry * 0.7, body)
			fill_rect(img, cx + rx * 1.0, cy - ry * 0.5, rx * 0.5, ry * 0.7, body)
		"crown":
			var gold := Color(1.0, 0.75, 0.2)
			fill_rect(img, cx - rx * 0.5, cy - ry * 1.35, rx * 1.0, ry * 0.35, gold)
			for k in range(3):
				var tx := cx - rx * 0.5 + rx * 0.5 * k
				fill_tri(img, Vector2(tx, cy - ry * 1.35), Vector2(tx + rx * 0.25, cy - ry * 1.75), Vector2(tx + rx * 0.5, cy - ry * 1.35), gold)
	# body with outline
	fill_ellipse(img, cx, cy, rx + s * 0.02, ry + s * 0.02, OUTLINE)
	fill_ellipse(img, cx, cy, rx, ry, body)
	fill_ellipse(img, cx - rx * 0.25, cy - ry * 0.35, rx * 0.35, ry * 0.25, body.lightened(0.18))
	if shape == "ball":
		# tumbleweed twigs
		for k in range(10):
			var a := k * 0.63
			line(img, Vector2(cx, cy), Vector2(cx + cos(a) * rx * 0.95, cy + sin(a) * ry * 0.95), s * 0.02, body.darkened(0.4))
	# hat for characters
	if ph.has("hat") and str(ph.get("hat", "")) != "":
		var hat := _col(ph.get("hat"), Color(0.8, 0.2, 0.2))
		fill_tri(img, Vector2(cx - rx * 0.7, cy - ry * 0.8), Vector2(cx, cy - ry * 2.1), Vector2(cx + rx * 0.7, cy - ry * 0.8), hat)
	# eyes
	var eyes := str(pose.get("eyes", "open"))
	var n_eyes := int(ph.get("eyes", 2))
	var back := bool(pose.get("back", false))
	if not back:
		var ex := [cx - rx * 0.35, cx + rx * 0.35] if n_eyes == 2 else [cx]
		for e in ex:
			var ey := cy - ry * 0.15
			match eyes:
				"x":
					line(img, Vector2(e - s * 0.05, ey - s * 0.05), Vector2(e + s * 0.05, ey + s * 0.05), s * 0.025, OUTLINE)
					line(img, Vector2(e - s * 0.05, ey + s * 0.05), Vector2(e + s * 0.05, ey - s * 0.05), s * 0.025, OUTLINE)
				"shut":
					line(img, Vector2(e - s * 0.05, ey), Vector2(e + s * 0.05, ey), s * 0.025, OUTLINE)
				_:
					fill_ellipse(img, e, ey, s * 0.07, s * 0.075, Color.WHITE)
					fill_ellipse(img, e + lean * 2.0, ey + s * 0.01, s * 0.035, s * 0.04, OUTLINE)
		# mouth
		if eyes == "open":
			line(img, Vector2(cx - rx * 0.2, cy + ry * 0.35), Vector2(cx + rx * 0.2, cy + ry * 0.35), s * 0.02, OUTLINE)
		elif eyes == "x":
			fill_ellipse(img, cx, cy + ry * 0.4, s * 0.06, s * 0.04, OUTLINE)


static func _poses(anim: String, frame: int, is_char: bool) -> Dictionary:
	match anim:
		"idle":
			return {"bob": 0.0 if frame == 0 else 3.0, "squash": 0.0 if frame == 0 else 0.06}
		"run":
			var f := frame % 4
			return {"lean": [-0.5, 0.0, 0.5, 0.0][f], "bob": [2.0, 6.0, 2.0, 0.0][f], "back": is_char}
		"turn":
			return {"lean": 1.0, "bob": 2.0}
		"attack":
			return {"lean": -1.0 if frame == 0 else 1.0, "bob": 0.0 if frame == 0 else 4.0, "eyes": "open"}
		"hit":
			return {"squash": 0.35, "eyes": "shut", "tint": Color(1, 1, 1)}
		"die":
			return {"squash": 0.6 if frame == 0 else 0.85, "eyes": "x", "bob": -2.0}
		"cheer":
			return {"bob": 8.0, "lean": 0.0}
	return {}


static func enemy_image(def: EnemyDef) -> Image:
	var s := def.frame_px
	var total := def.total_frames()
	var img := Image.create_empty(s * total, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := 0
	for anim in ENEMY_ORDER:
		var n := def.frames_of(anim)
		for f in range(n):
			draw_creature(img, k * s, 0, s, def.placeholder, _poses(anim, f, false))
			k += 1
	return img


static func character_image(def: CharacterDef) -> Image:
	var s := def.frame_px if def else 256
	var anims: Dictionary = def.anims if def else {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
	var ph: Dictionary = def.placeholder if def else {"color": "#FFD166", "hat": "#D8433B", "eyes": 2}
	var total := 0
	for a in CHAR_ORDER:
		total += int(anims.get(a, 0))
	var img := Image.create_empty(s * max(total, 1), s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var k := 0
	for anim in CHAR_ORDER:
		var n := int(anims.get(anim, 0))
		for f in range(n):
			# the front and side views of a real strip share the placeholder's poses
			draw_creature(img, k * s, 0, s, ph, _poses(anim.split("_")[0], f, true))
			k += 1
	return img


static func enemy_strip(def: EnemyDef) -> ImageTexture:
	return ImageTexture.create_from_image(enemy_image(def))


static func character_strip(def: CharacterDef) -> ImageTexture:
	return ImageTexture.create_from_image(character_image(def))


static func frames_from_strip(tex: Texture2D, anims: Dictionary, fpx: int, order: Array) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var k := 0
	for anim in order:
		var n := int(anims.get(anim, 0))
		if n <= 0:
			continue
		sf.add_animation(anim)
		sf.set_animation_speed(anim, {"idle": 2.0, "run": 8.0, "attack": 6.0}.get(anim, 6.0))
		sf.set_animation_loop(anim, anim in ["idle", "run", "turn"])
		for f in range(n):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(k * fpx, 0, fpx, fpx)
			sf.add_frame(anim, at)
			k += 1
	if not sf.has_animation("idle"):
		sf.add_animation("idle")
	return sf


# ---------------------------------------------------------------- icons

static func icon_image(def: ContentDef, px: int = 128) -> Image:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ph: Dictionary = def.placeholder if def else {}
	var col := _col(ph.get("color"), Color(0.7, 0.7, 0.75))
	var glyph := str(ph.get("glyph", ""))
	var c := px * 0.5
	var r := px * 0.32
	var gold := bool(ph.get("gold", false))
	match glyph:
		"pea":
			fill_ellipse(img, c, c, r, r, OUTLINE); fill_ellipse(img, c, c, r * 0.9, r * 0.9, col)
			fill_ellipse(img, c - r * 0.3, c - r * 0.3, r * 0.25, r * 0.2, col.lightened(0.4))
		"shotgun":
			fill_rect(img, c - r * 1.1, c - r * 0.25, r * 2.2, r * 0.5, OUTLINE)
			fill_rect(img, c - r * 1.0, c - r * 0.18, r * 2.0, r * 0.36, col)
			fill_rect(img, c - r * 1.1, c + r * 0.1, r * 0.6, r * 0.7, Color(0.45, 0.28, 0.15))
		"saw":
			fill_ellipse(img, c, c, r, r, OUTLINE)
			for k in range(12):
				var a := TAU * k / 12.0
				fill_tri(img, Vector2(c + cos(a) * r * 0.9, c + sin(a) * r * 0.9), Vector2(c + cos(a + 0.25) * r * 1.15, c + sin(a + 0.25) * r * 1.15), Vector2(c + cos(a + 0.5) * r * 0.9, c + sin(a + 0.5) * r * 0.9), OUTLINE)
			fill_ellipse(img, c, c, r * 0.85, r * 0.85, col)
			fill_ellipse(img, c, c, r * 0.2, r * 0.2, OUTLINE)
		"grenade":
			fill_ellipse(img, c, c + r * 0.15, r * 0.8, r * 0.9, OUTLINE); fill_ellipse(img, c, c + r * 0.15, r * 0.7, r * 0.8, col)
			fill_rect(img, c - r * 0.2, c - r * 0.95, r * 0.4, r * 0.35, Color(0.6, 0.6, 0.65))
		"bolt":
			var pts := [Vector2(c + r * 0.2, c - r), Vector2(c - r * 0.5, c + r * 0.1), Vector2(c, c + r * 0.1), Vector2(c - r * 0.2, c + r), Vector2(c + r * 0.5, c - r * 0.1), Vector2(c, c - r * 0.1)]
			fill_tri(img, pts[0], pts[1], pts[5], col); fill_tri(img, pts[1], pts[2], pts[5], col)
			fill_tri(img, pts[2], pts[3], pts[4], col); fill_tri(img, pts[2], pts[4], pts[5], col)
		"turret":
			fill_rect(img, c - r * 0.7, c, r * 1.4, r * 0.8, OUTLINE); fill_rect(img, c - r * 0.6, c + r * 0.08, r * 1.2, r * 0.64, col)
			fill_ellipse(img, c, c, r * 0.5, r * 0.5, col.lightened(0.2)); fill_rect(img, c, c - r * 0.12, r * 1.0, r * 0.24, OUTLINE)
			fill_ellipse(img, c - r * 0.15, c - r * 0.1, r * 0.08, r * 0.08, OUTLINE); fill_ellipse(img, c + r * 0.15, c - r * 0.1, r * 0.08, r * 0.08, OUTLINE)
		"fist":
			fill_ellipse(img, c, c, r * 0.8, r * 0.7, OUTLINE); fill_ellipse(img, c, c, r * 0.7, r * 0.6, col)
			for k in range(4):
				fill_ellipse(img, c - r * 0.5 + k * r * 0.33, c - r * 0.35, r * 0.17, r * 0.2, col.lightened(0.2))
		"clock":
			fill_ellipse(img, c, c, r, r, OUTLINE); fill_ellipse(img, c, c, r * 0.88, r * 0.88, col)
			line(img, Vector2(c, c), Vector2(c, c - r * 0.6), r * 0.1, OUTLINE); line(img, Vector2(c, c), Vector2(c + r * 0.45, c), r * 0.1, OUTLINE)
		"ring":
			fill_ellipse(img, c, c, r, r, col); fill_ellipse(img, c, c, r * 0.6, r * 0.6, Color(0, 0, 0, 0))
		"triple":
			for k in range(3):
				fill_ellipse(img, c - r * 0.6 + k * r * 0.6, c, r * 0.28, r * 0.28, OUTLINE)
				fill_ellipse(img, c - r * 0.6 + k * r * 0.6, c, r * 0.24, r * 0.24, col)
		"magnet":
			fill_ellipse(img, c, c - r * 0.2, r, r, col); fill_ellipse(img, c, c - r * 0.2, r * 0.5, r * 0.5, Color(0, 0, 0, 0))
			fill_rect(img, c - r, c - r * 0.2, r * 2.0, r * 1.2, Color(0, 0, 0, 0))
			fill_rect(img, c - r, c - r * 0.2, r * 0.5, r * 0.8, col); fill_rect(img, c + r * 0.5, c - r * 0.2, r * 0.5, r * 0.8, col)
			fill_rect(img, c - r, c + r * 0.3, r * 0.5, r * 0.3, Color.WHITE); fill_rect(img, c + r * 0.5, c + r * 0.3, r * 0.5, r * 0.3, Color.WHITE)
		"heart":
			fill_ellipse(img, c - r * 0.42, c - r * 0.3, r * 0.5, r * 0.5, col); fill_ellipse(img, c + r * 0.42, c - r * 0.3, r * 0.5, r * 0.5, col)
			fill_tri(img, Vector2(c - r * 0.9, c - r * 0.1), Vector2(c + r * 0.9, c - r * 0.1), Vector2(c, c + r), col)
		"boot":
			fill_rect(img, c - r * 0.5, c - r, r * 0.7, r * 1.4, col); fill_rect(img, c - r * 0.5, c + r * 0.2, r * 1.5, r * 0.6, col)
		"clover":
			for k in range(4):
				var a := TAU * k / 4.0
				fill_ellipse(img, c + cos(a) * r * 0.45, c + sin(a) * r * 0.45, r * 0.42, r * 0.42, col)
		"coin":
			fill_ellipse(img, c, c, r, r, OUTLINE); fill_ellipse(img, c, c, r * 0.88, r * 0.88, col); fill_ellipse(img, c, c, r * 0.5, r * 0.5, col.darkened(0.2))
		"dice":
			fill_rect(img, c - r, c - r, r * 2, r * 2, col)
			for p in [Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(0, 0), Vector2(-0.5, 0.5), Vector2(0.5, -0.5)]:
				fill_ellipse(img, c + p.x * r, c + p.y * r, r * 0.16, r * 0.16, OUTLINE)
		"skip":
			fill_tri(img, Vector2(c - r, c - r * 0.8), Vector2(c - r, c + r * 0.8), Vector2(c + r * 0.1, c), col)
			fill_rect(img, c + r * 0.3, c - r * 0.8, r * 0.3, r * 1.6, col)
		"cross":
			line(img, Vector2(c - r, c - r), Vector2(c + r, c + r), r * 0.35, col); line(img, Vector2(c - r, c + r), Vector2(c + r, c - r), r * 0.35, col)
		"shield":
			fill_tri(img, Vector2(c - r, c - r * 0.8), Vector2(c + r, c - r * 0.8), Vector2(c, c + r), col); fill_rect(img, c - r, c - r, r * 2, r * 0.6, col)
		"wing":
			fill_tri(img, Vector2(c - r, c), Vector2(c + r, c - r * 0.8), Vector2(c + r * 0.6, c + r * 0.5), col)
		"split":
			fill_ellipse(img, c - r * 0.5, c - r * 0.4, r * 0.45, r * 0.45, col); fill_ellipse(img, c + r * 0.5, c - r * 0.4, r * 0.45, r * 0.45, col); fill_ellipse(img, c, c + r * 0.5, r * 0.45, r * 0.45, col)
		"boom":
			for k in range(8):
				var a := TAU * k / 8.0
				fill_tri(img, Vector2(c, c), Vector2(c + cos(a - 0.2) * r * 0.6, c + sin(a - 0.2) * r * 0.6), Vector2(c + cos(a) * r * 1.1, c + sin(a) * r * 1.1), col)
			fill_ellipse(img, c, c, r * 0.5, r * 0.5, col.lightened(0.4))
		"sun":
			fill_ellipse(img, c, c, r * 0.6, r * 0.6, col)
			for k in range(8):
				var a := TAU * k / 8.0
				line(img, Vector2(c + cos(a) * r * 0.75, c + sin(a) * r * 0.75), Vector2(c + cos(a) * r * 1.05, c + sin(a) * r * 1.05), r * 0.14, col)
		_:
			# generic: a rounded blob with the first letter-ish mark
			fill_ellipse(img, c, c, r, r, OUTLINE); fill_ellipse(img, c, c, r * 0.9, r * 0.9, col)
			fill_rect(img, c - r * 0.35, c - r * 0.35, r * 0.7, r * 0.7, col.darkened(0.35))
	if gold:
		# gold rim for evolutions
		var rim := Color(1.0, 0.8, 0.25)
		for k in range(40):
			var a := TAU * k / 40.0
			fill_ellipse(img, c + cos(a) * px * 0.44, c + sin(a) * px * 0.44, px * 0.03, px * 0.03, rim)
	return img


static func icon(def: ContentDef, px: int = 128) -> ImageTexture:
	return ImageTexture.create_from_image(icon_image(def, px))
