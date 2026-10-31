## Small helpers that give every screen the same look. Survivor.io is the target: navy panels with a lighter rim,
## one gold accent for the thing to press, purple for XP, chunky rounded display type with a dark outline
## wherever text sits over the world. Base design resolution is 1080 x 1920.
class_name UiKit
extends RefCounted

## Type: Lilita One (OFL) for headers, numbers and buttons; Baloo 2 (OFL, variable) at two weights for body text.
const HEAD_FONT_PATH := "res://ui/fonts/LilitaOne.ttf"
const BODY_FONT_PATH := "res://ui/fonts/Baloo2.ttf"
## Sizes are design pixels at 1080 wide. 1.0: the type itself is already large.
const UI_SCALE := 1.0
## Labels at this size and above use the display face.
const HEAD_AT := 40
static var _font_regular: Font
static var _font_bold: Font
static var _font_head: Font


static func font(bold: bool = false) -> Font:
	if _font_regular == null:
		if ResourceLoader.exists(BODY_FONT_PATH):
			var base: Font = load(BODY_FONT_PATH)
			var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
			var r := FontVariation.new()
			r.base_font = base
			r.variation_opentype = {tag: 600.0}
			var b := FontVariation.new()
			b.base_font = base
			b.variation_opentype = {tag: 800.0}
			_font_regular = r
			_font_bold = b
		else:
			_font_regular = ThemeDB.fallback_font
			_font_bold = ThemeDB.fallback_font
	return _font_bold if bold else _font_regular


static func font_head() -> Font:
	if _font_head == null:
		if ResourceLoader.exists(HEAD_FONT_PATH):
			_font_head = load(HEAD_FONT_PATH)
			# pass 69: Lilita One has no Polish letters (Jeżyk's ż): the bold body font draws what it lacks
			if _font_head.fallbacks.is_empty() and font(true) != _font_head:
				_font_head.fallbacks = [font(true)]
		else:
			_font_head = font(true)
	return _font_head


## Palette. Navy ground with lighter rims, gold for the one thing to press, purple for XP and passives,
## green for good news, red for danger. Text is white on navy and outlined over the world.
const BG := Color(0.078, 0.102, 0.169)
const BG2 := Color(0.122, 0.157, 0.255)
const BG3 := Color(0.169, 0.212, 0.353)
const LINE := Color(0.275, 0.349, 0.541)
const INK := Color(1.0, 1.0, 1.0)
const INK2 := Color(0.788, 0.827, 0.941)
const INK3 := Color(0.553, 0.608, 0.769)
const ACCENT := Color(1.0, 0.71, 0.18)
const ACCENT_INK := Color(0.24, 0.145, 0.0)
const XP := Color(0.545, 0.424, 1.0)
const DANGER := Color(1.0, 0.373, 0.42)
const GOOD := Color(0.353, 0.839, 0.416)
const INFO := Color(0.298, 0.788, 1.0)
const OUTLINE := Color(0.06, 0.07, 0.12, 0.95)

const TYPE_COLORS := {"weapon": ACCENT, "passive": XP, "evolution": Color(1.0, 0.827, 0.353), "shop": Color(0.27, 0.815, 0.815), "character": GOOD, "map": Color(0.94, 0.54, 0.29), "enemy": DANGER, "elite": DANGER, "pickup": GOOD,
	"mutation": Color(1.0, 0.42, 0.8), "perk": GOOD}
## The kind a card or row is drawn as, from the def's class.
static func kind_of(def: ContentDef) -> String:
	if def is WeaponDef:
		return "evolution" if def.is_evolution else "weapon"
	if def is MutationDef:
		return "mutation"
	if def is PerkDef:
		return "perk"
	if def is PassiveDef:
		return "passive"
	if def is CharacterDef:
		return "character"
	return def.kind() if def else "weapon"


## The one StyleBoxFlat factory. `shadow` adds a soft drop shadow, `bevel` a thicker darker bottom edge (a flat
## button reads as a physical one), `pad` false gives a bare box for progress bars and plates.
static func stylebox(color: Color, radius: int = 24, border: Color = Color(0, 0, 0, 0), border_w: int = 0, shadow: bool = false, bevel: bool = false, pad: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	if bevel:
		if border_w <= 0:
			sb.border_color = color.darkened(0.42)
		sb.border_width_bottom = maxi(border_w, 0) + 6
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.32)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 5)
	if pad:
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		sb.content_margin_top = 18
		sb.content_margin_bottom = 18
	else:
		sb.set_content_margin_all(0)
	return sb


## Bare bar style for ProgressBar backgrounds and fills (no padding, optional thin rim).
static func bar(color: Color, radius: int = 10, rim: Color = Color(0, 0, 0, 0), rim_w: int = 0) -> StyleBoxFlat:
	return stylebox(color, radius, rim, rim_w, false, false, false)


static func label(text: String, size: int = 36, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_head() if size >= HEAD_AT else font(size >= 30))
	l.add_theme_font_size_override("font_size", int(round(size * UI_SCALE)))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Dark outline for text that sits over the world (HUD, toasts, banners) or on gold.
static func outline(l: Label, px: int = 5, color: Color = OUTLINE) -> Label:
	l.add_theme_constant_override("outline_size", px)
	l.add_theme_color_override("font_outline_color", color)
	return l


static func button(text: String, size: int = 40, primary: bool = false, min_h: int = 110) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_head())
	b.add_theme_font_size_override("font_size", int(round(size * UI_SCALE)))
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := ACCENT if primary else BG3
	var r: int = mini(min_h / 2, 30)
	var rim := Color(0, 0, 0, 0) if primary else LINE
	var rim_w := 0 if primary else 3
	b.add_theme_stylebox_override("normal", stylebox(bg, r, rim, rim_w, true, true))
	b.add_theme_stylebox_override("hover", stylebox(bg.lightened(0.08), r, rim, rim_w, true, true))
	b.add_theme_stylebox_override("pressed", stylebox(bg.darkened(0.12), r, rim, rim_w, false, false))
	b.add_theme_stylebox_override("disabled", stylebox(BG2, r, LINE, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, INK)
	b.add_theme_color_override("font_disabled_color", INK3)
	if primary:
		# white on gold needs the dark rim to read; the game look
		b.add_theme_constant_override("outline_size", maxi(int(size * 0.14), 4))
		b.add_theme_color_override("font_outline_color", ACCENT_INK)
	b.pressed.connect(func(): Audio.play("ui_tap"))
	UiFx.pressable(b)
	return b


static func panel(color: Color = BG2, radius: int = 28, border: Color = LINE, border_w: int = 2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(color, radius, border, border_w, true))
	return p


## A tappable card that sizes itself to its content. Fill it with `card_body` or your own MarginContainer.
static func card(border: Color = LINE, border_w: int = 2, bg: Color = BG2, radius: int = 26) -> TapCard:
	var c := TapCard.new()
	c.add_theme_stylebox_override("panel", stylebox(bg, radius, border, border_w, true, false, false))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Standard card body: icon on the left, a column of texts (each [text, size, colour]) on the right, generous
## padding, everything mouse-transparent so the card itself takes the tap. Returns the text column.
static func card_body(c: Control, def: ContentDef, kind: String, icon_size: int, texts: Array) -> VBoxContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 26)
	m.add_theme_constant_override("margin_right", 26)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 20)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(m)
	var h := hbox(24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	if def:
		h.add_child(icon_view(def, icon_size, kind))
	var v := vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for t in texts:
		var l := label(str(t[0]), int(t[1]), t[2] if t.size() > 2 else INK)
		v.add_child(l)
	h.add_child(v)
	return v


static func vbox(sep: int = 16) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v


static func hbox(sep: int = 16) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


static func spacer(h: int = 20) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func fullscreen(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0


static func dim(alpha: float = 0.82) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.05, 0.06, 0.11, alpha)
	fullscreen(c)
	return c


## Icon on a type-coloured plate (square for weapons, round for passives and characters). Always a square:
## it never stretches with the row it sits in, and it is mouse-transparent so the card behind takes the tap.
## Falls back to a letter tile when the def has no icon.
static func icon_view(def: ContentDef, size: int = 120, kind: String = "") -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(size, size)
	root.size = Vector2(size, size)
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := kind if kind != "" else (def.kind() if def else "weapon")
	if def is WeaponDef and def.is_evolution:
		k = "evolution"
	var col: Color = TYPE_COLORS.get(k, BG3)
	var plate := Panel.new()
	# one short of half for the round plates: a radius of exactly half the size draws a seam down the middle
	var radius := size / 2 - 1 if k == "passive" or k == "character" or k == "perk" else size / 5
	# a mutation wears its own frame: thick, in the mutation colour, so it is never mistaken for a weapon or a passive
	var rim_w := maxi(size / 10, 5) if k == "mutation" else maxi(size / 24, 3)
	plate.add_theme_stylebox_override("panel", stylebox(col.darkened(0.62), radius, col, rim_w, true, false, false))
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	var tex: Texture2D = def.icon if def else null
	if tex == null and def:
		tex = PlaceholderArt.icon(def, 128)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		# item icons sit inside the plate; a character badge is itself a circle and fills the plate to its rim
		var inset := size * (0.02 if k == "character" else 0.1)
		tr.offset_left = inset
		tr.offset_top = inset
		tr.offset_right = -inset
		tr.offset_bottom = -inset
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
	else:
		var l := label(def.display_name.substr(0, 1).to_upper() if def else "?", int(size * 0.5), INK, HORIZONTAL_ALIGNMENT_CENTER)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)
	return root


static func pip_row(level: int, max_level: int, width: int = 120) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(max_level):
		var p := ColorRect.new()
		p.custom_minimum_size = Vector2(maxi(width / max_level - 4, 4), 8)
		p.color = ACCENT if i < level else LINE
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(p)
	return h


## A crisp anti-aliased disc as a texture (radial gradient): round plates and knobs without StyleBoxFlat's seam on
## translucent circles.
static func circle_texture(size: int, fill: Color, rim: Color = Color(0, 0, 0, 0), rim_w: float = 0.08) -> Texture2D:
	var g := Gradient.new()
	var edge := 1.0 - rim_w
	g.offsets = PackedFloat32Array([0.0, edge - 0.04, edge, 0.97, 1.0])
	g.colors = PackedColorArray([fill, fill, rim if rim.a > 0.0 else fill, rim if rim.a > 0.0 else fill, Color(rim if rim.a > 0.0 else fill, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 1.0)
	return t


## Slider in the kit's colours: navy track with a rim, gold filled part, round gold knob. A TouchSlider, so a finger moves
## it on the phone (pass 37: the plain HSlider only listened to the mouse), 84 px tall for a thumb.
static func slider(value: float, lo: float, hi: float, step: float = 0.05) -> HSlider:
	var s := TouchSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 84)
	var track := bar(BG3, 9, LINE, 2)
	track.content_margin_top = 9
	track.content_margin_bottom = 9
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", bar(ACCENT, 9))
	s.add_theme_stylebox_override("grabber_area_highlight", bar(ACCENT.lightened(0.1), 9))
	var knob := circle_texture(44, ACCENT, ACCENT_INK, 0.12)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	s.add_theme_icon_override("grabber_disabled", knob)
	return s


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.add_child(child)
	return s


static func margin(child: Control, m: int = 40) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", m)
	mc.add_theme_constant_override("margin_right", m)
	mc.add_theme_constant_override("margin_top", m)
	mc.add_theme_constant_override("margin_bottom", m)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mc.add_child(child)
	return mc


static func card_description(card: Dictionary) -> String:
	var def: ContentDef = card["def"]
	if def is MutationDef:
		return (def as MutationDef).text
	if def is PerkDef:
		return TextGen.perk_text(def as PerkDef)
	if def is PassiveDef and bool(card.get("evolve", false)):
		# the evolution (pass 33.2): the whole of what the maxed passive becomes, in place of its levels
		var ed := def as PassiveDef
		var src: PassiveDef = Registry.passive(ed.evolves_from)
		var se := "Replaces %s: %s" % [src.display_name if src else ed.evolves_from, TextGen.describe_effects(ed.effects_for_level(1))]
		if ed.trade != "":
			se += " (the trade: %s)" % ed.trade
		return se
	if def is WeaponDef:
		var inst := Run.weapon_instance(def.id)
		if inst:
			return _next_only(TextGen.next_level_text(def, inst.level))
		var tmp := WeaponInstance.new(def, 1)
		tmp.rebuild(Run.player_sheet, Run.weapons)
		return tmp.description()
	elif def is PassiveDef:
		var pd := def as PassiveDef
		var lv := int(card["level_to"])
		var s := TextGen.describe_effects(pd.effects_at_level(lv)) + (" a level" if pd.repeat_last_level else "")
		if pd.trade != "":
			s += " (the trade: %s)" % pd.trade
		if int(card.get("level_from", 0)) == 0 and pd.text != "":
			s = pd.text + " " + s
		return ("Next: " + s) if int(card.get("level_from", 0)) > 0 else s
	return ""


## A level pill: "LV 2 → 3" for an upgrade, "NEW · LV 1" for a fresh item, "MAX" when the step lands on the cap.
static func level_chip(card: Dictionary) -> Control:
	var def: ContentDef = card["def"]
	var lf := int(card.get("level_from", 0))
	var lt := int(card.get("level_to", 1))
	var mx: int = def.max_level if (def is WeaponDef or def is PassiveDef) else 8
	# a new item taken past level 1 in one go (the Stranger's, pass 34) says where it lands
	var text := ("NEW · LV %d" % maxi(lt, 1) if lf == 0 else "LV %d → %d" % [lf, lt]) + (" · MAX" if lt >= mx and lf > 0 else "")
	if def is MutationDef:
		# the path's real count (pass 48: every mutation of it is needed to evolve), the held ones read off the weapon
		var fam_w := Run.family_instance((def as MutationDef).weapon)
		var fam_n: int = maxi(Registry.mutations_of((def as MutationDef).weapon).size(), 1)
		var held_n: int = Run.path_progress(fam_w).x if fam_w else 0
		text = "HERO" if (def as MutationDef).is_hero() else "MUTATION %d / %d" % [mini(held_n + 1, fam_n), fam_n]
	elif bool(card.get("evolve", false)):
		text = "EVOLVE"
	elif def is PerkDef:
		text = "ONCE"
	var l := label(text, 24, ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(ACCENT, 14, Color(0, 0, 0, 0), 0, false, false, false))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(l)
	p.add_child(m)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## Level pips for a card: gold for the levels held, a white pip with a gold rim for the one this pick gives, grey
## for the rest, so "where am I" and "what do I get" are one glance.
static func level_pips(card: Dictionary, width: int = 320) -> Control:
	var def: ContentDef = card["def"]
	var lf := int(card.get("level_from", 0))
	var lt := int(card.get("level_to", 1))
	var mx: int = def.max_level if (def is WeaponDef or def is PassiveDef) else 8
	if def is MutationDef:
		# a weapon's mutations have three pips: the picks held on the weapon, this one, the rest
		var held := Run.mutations_held((def as MutationDef).weapon).size()
		if (def as MutationDef).is_hero():
			return Control.new()
		lf = held
		lt = held + 1
		mx = 3
	elif def is PerkDef:
		return Control.new()
	if bool(card.get("evolve", false)):
		# an evolution has no ranks to count
		return Control.new()
	var h := hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: int = maxi(width / maxi(mx, 1) - 6, 10)
	for i in range(mx):
		var p := Panel.new()
		p.custom_minimum_size = Vector2(w, 20)
		var col: Color = ACCENT if i < lf else (Color(1, 1, 1) if i < lt else BG3)
		var rim: Color = ACCENT if i < lt else LINE
		p.add_theme_stylebox_override("panel", stylebox(col, 6, rim, 2, false, false, false))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(p)
	return h


## The top of an item card: the kind tag, the name with the level chip on the right, the pip row. Returns the column.
static func item_header(v: VBoxContainer, card: Dictionary, kind_col: Color, name_size: int = 46, extra_tag: String = "") -> void:
	var def: ContentDef = card["def"]
	var kind := "WEAPON" if def is WeaponDef else "PASSIVE"
	if def is WeaponDef and def.is_evolution:
		kind = "EVOLUTION"
	var tag_text := kind + (" · UPGRADE" if int(card.get("level_from", 0)) > 0 else " · NEW") + extra_tag
	if def is MutationDef:
		var md := def as MutationDef
		var wname: String = Registry.weapon(md.weapon).display_name.to_upper() if Registry.weapon(md.weapon) else md.weapon.to_upper()
		tag_text = ("HERO MUTATION · " if md.is_hero() else "MUTATION · ") + wname + ("" if md.is_hero() else " · " + md.mutation_kind.to_upper()) + extra_tag
	elif def is PassiveDef and bool(card.get("evolve", false)):
		var src: PassiveDef = Registry.passive((def as PassiveDef).evolves_from)
		tag_text = "PASSIVE · EVOLUTION OF " + (src.display_name.to_upper() if src else "A PASSIVE") + extra_tag
	elif def is PerkDef:
		tag_text = "HERO PERK" + extra_tag
	var tl := label(tag_text, 22, kind_col)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tl)
	var row := hbox(16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := label(def.display_name, name_size, INK)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nl)
	row.add_child(level_chip(card))
	v.add_child(row)
	v.add_child(level_pips(card))


## "Next level: +15% might" -> "Next: +15% might"; "Maxed." stays.
static func _next_only(text: String) -> String:
	if text.begins_with("Next level: "):
		return "Next: " + text.trim_prefix("Next level: ")
	return text


static func card_tag(card: Dictionary) -> String:
	var def: ContentDef = card["def"]
	var t := "WEAPON" if def is WeaponDef else "PASSIVE"
	if def is MutationDef:
		return "MUTATION · " + (Registry.weapon((def as MutationDef).weapon).display_name.to_upper() if Registry.weapon((def as MutationDef).weapon) else "")
	if def is PerkDef:
		return "HERO PERK"
	if bool(card.get("evolve", false)):
		return t + " · EVOLUTION"
	if card.get("is_new", false):
		return t + " · NEW"
	return t + " · LV %d → %d" % [int(card["level_from"]), int(card["level_to"])]
