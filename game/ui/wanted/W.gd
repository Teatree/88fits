## "Wanted" (design_handoff_88fits_wanted): sun-bleached paper, ink outlines, brass, red rock. The tokens, the three
## faces and the small helpers every Wanted piece shares. Sizes are canvas px at 1080 x 1920.
class_name W
extends RefCounted

# --- colour ----------------------------------------------------------------------------------------------------------
const PAPER := Color("f3e6c8")          ## panels, cards, buttons, HUD plates
const AGED := Color("e2cfa4")           ## unselected tabs, locked cards, empty tracks, empty stars
const INK := Color("241b14")            ## every border, every hard shadow, body text
const INK_SOFT := Color("5a4a3a")       ## secondary text, italic lines, labels
const BRASS := Color("c9932f")          ## primary button, weapon plate, filled stars, rivets, the coin
const BRASS_DARK := Color("a8792a")     ## pressed primary, "WEAPON" text, gold numbers
const ROCK := Color("b4472b")           ## line plate, danger button, boss HP, "the price"
const SAGE := Color("6e8b5e")           ## passive plate, health, positive numbers
const TURQUOISE := Color("3f8f8a")      ## perk plate
const EMBER := Color("d9662a")          ## evolution plate, EVOLVED banner, Elite pointer
const PLUM := Color("4a3358")           ## mutation plate, path chips
const RARE := Color("3e6e9e")           ## wax seal, shield bar
const EPIC := Color("8a4fb0")           ## wax seal, XP bar
const COMMON := Color("8a8f7a")         ## wax seal
const TOAST_GREEN := Color("7fe07f")
const TOAST_PURPLE := Color("b57bff")
const DIM := Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.78)        ## behind the in-run modals
const DIM_CHEST := Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.85)
const DIM_DOWN := Color(90 / 255.0, 30 / 255.0, 20 / 255.0, 0.82)
const DIM_STRANGER := Color(30 / 255.0, 18 / 255.0, 26 / 255.0, 0.86)
const DIM_GATE := Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.40)
const WASH := Color(243 / 255.0, 230 / 255.0, 200 / 255.0, 0.82)    ## over the desert behind the menus

## A plate's colour by kind, and the colour of the kind's one word.
const KIND := {"weapon": BRASS, "evolution": EMBER, "mutation": PLUM, "passive": SAGE, "line": ROCK, "perk": TURQUOISE,
	"character": AGED, "enemy": INK, "elite": INK, "pickup": SAGE, "map": BRASS}
const KIND_WORD := {"weapon": BRASS_DARK, "evolution": EMBER, "mutation": PLUM, "passive": SAGE, "line": ROCK,
	"perk": TURQUOISE, "character": INK_SOFT, "enemy": INK, "elite": INK}
const RARITY := {"common": COMMON, "rare": RARE, "epic": EPIC}
## An evolved weapon or line: a dark plate inside a brass ring, the same for both, so an evolution reads at a glance
## next to the brass weapons and the rock lines (ember alone sat too close to brass on a phone).
const EVOLVED_FILL := INK
const EVOLVED_RING := BRASS

# --- type ------------------------------------------------------------------------------------------------------------
const SLAB_PATH := "res://ui/fonts/AlfaSlabOne-Regular.ttf"
const SERIF_PATH := "res://ui/fonts/Bitter.ttf"
const SERIF_ITALIC_PATH := "res://ui/fonts/Bitter-Italic.ttf"
const MONO_PATH := "res://ui/fonts/JetBrainsMono.ttf"
static var _fonts: Dictionary = {}


## Each face's ascent and descent over its em (hhea = typo in all three): CSS "normal" line height is these, each rounded
## to the pixel (Chrome), where Font.get_height() rounds both up and so runs a pixel taller.
const METRICS := {"Bitter": [0.935, 0.265], "AlfaSlab": [1.036, 0.333], "JetBrains": [1.02, 0.3]}


## The CSS "normal" line height of `f` at `px`, as the mocks were measured.
static func normal_height(f: Font, px: int) -> float:
	var base := f
	while base is FontVariation and (base as FontVariation).base_font:
		base = (base as FontVariation).base_font
	var path := base.resource_path if base else ""
	for k in METRICS:
		if path.contains(k):
			var m: Array = METRICS[k]
			return roundf(float(m[0]) * px) + roundf(float(m[1]) * px)
	return f.get_height(px)


static func _base(path: String) -> Font:
	if not _fonts.has(path):
		_fonts[path] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _fonts[path]


static func _variant(path: String, weight: int, track: int) -> Font:
	var key := "%s:%d:%d" % [path, weight, track]
	if not _fonts.has(key):
		var v := FontVariation.new()
		v.base_font = _base(path)
		if weight > 0:
			var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
			v.variation_opentype = {tag: float(weight)}
		v.spacing_glyph = track
		_fonts[key] = v
	return _fonts[key]


## Alfa Slab One: every heading, number, button, card name, tab and stat value. `track` is extra px per letter.
static func slab(track: int = 0) -> Font:
	return _base(SLAB_PATH) if track == 0 else _variant(SLAB_PATH, 0, track)


## Bitter at 400 or 600, upright or italic: effect text, notes, labels and flavour lines.
static func serif(weight: int = 400, italic: bool = false, track: int = 0) -> Font:
	return _variant(SERIF_ITALIC_PATH if italic else SERIF_PATH, weight, track)


## JetBrains Mono: the developer menu and the placeholders' labels.
static func mono(weight: int = 500, track: int = 0) -> Font:
	return _variant(MONO_PATH, weight, track)


## Letter spacing in px for a tracking given in em (the mock's letter-spacing: .15em at 20 px is 3 px).
static func em(size: int, em_frac: float) -> int:
	return int(round(size * em_frac))


# --- text ------------------------------------------------------------------------------------------------------------
static func text(t: String, font: Font, size: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		line_h: float = 0.0, wrap: bool = false) -> WText:
	var w := WText.new()
	w.font = font
	w.font_size = size
	w.color = color
	w.align = align
	w.line_height = line_h
	w.wrap = wrap
	w.text = t
	return w


## Slab text (Alfa Slab One). CSS line-height 1 is the default for slab headings in the mock; pass 0 for the face's
## own (CSS normal: 1.369 for Alfa Slab, 1.2 for Bitter, 1.32 for JetBrains Mono). Sizes elsewhere are outside sizes
## (the mock's CSS widths are content-box: add the borders).
static func slab_text(t: String, size: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT, line_h: float = -1.0) -> WText:
	return text(t, slab(), size, color, align, size * 1.0 if line_h < 0.0 else line_h)


## Body text (Bitter). Effect text wraps at line-height 1.3 in the mock.
static func serif_text(t: String, size: int, color: Color = INK, weight: int = 400, italic: bool = false,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, line_h: float = -1.0, wrap: bool = false) -> WText:
	return text(t, serif(weight, italic), size, color, align, size * 1.3 if line_h < 0.0 else line_h, wrap)


## The tracked uppercase labels (Bitter 600, letter-spacing +15 %).
static func label(t: String, size: int = 20, color: Color = INK_SOFT, em_frac: float = 0.15) -> WText:
	return text(t.to_upper(), serif(600, false, em(size, em_frac)), size, color, HORIZONTAL_ALIGNMENT_LEFT, 0.0)


# --- numbers ---------------------------------------------------------------------------------------------------------
## Thousands always separated: 104711 -> "104,711".
static func num(n) -> String:
	var v := int(round(float(n)))
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


## Run clocks as mm:ss, no tenths.
static func mmss(seconds: float) -> String:
	var t := int(maxf(seconds, 0.0))
	return "%02d:%02d" % [t / 60, t % 60]


## "Lv 14", never "L14".
static func lv(level: int) -> String:
	return "Lv %d" % level


# --- kinds -----------------------------------------------------------------------------------------------------------
static func kind_of(def: ContentDef) -> String:
	if def == null:
		return "weapon"
	if def is WeaponDef:
		return "evolution" if (def as WeaponDef).is_evolution else "weapon"
	if def is MutationDef:
		return "mutation"
	if def is LineDef:
		return "line"
	if def is PerkDef:
		return "perk"
	if def is PassiveDef:
		return "passive"
	if def is CharacterDef:
		return "character"
	if def is EnemyDef:
		return "enemy"
	return def.kind()


## An evolved item: an evolution weapon, or a line that grew out of another line.
static func is_evolved(def: ContentDef) -> bool:
	if def is WeaponDef:
		return (def as WeaponDef).is_evolution
	if def is LineDef:
		return (def as LineDef).evolves_from != ""
	return false


static func rarity_of(def: ContentDef) -> String:
	var r := def.rarity if def else "common"
	return r if RARITY.has(r) else "common"


## The largest a level mark goes: stars for weapons (/8), passives and lines (their max), notches for ranks (/3).
static func max_level_of(def: ContentDef) -> int:
	if def is WeaponDef or def is PassiveDef:
		return maxi(int(def.get("max_level")), 1)
	return 1


# --- small shapes ----------------------------------------------------------------------------------------------------
## A HardBox with the kit's usual parts.
static func box(fill: Color = PAPER, border: int = 5, shadow: int = 0, radius: int = 0) -> HardBox:
	var b := HardBox.new()
	b.fill = fill
	b.border = border
	b.shadow = shadow
	b.radius = radius
	return b


## A full-rect ColorRect (the dims and the paper wash), mouse-transparent unless `blocks`.
static func dim(color: Color, blocks: bool = true) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP if blocks else Control.MOUSE_FILTER_IGNORE
	return c


## Place a control at an absolute canvas position and size (the mock is laid out absolutely).
static func at(c: Control, x: float, y: float, w: float = -1.0, h: float = -1.0) -> Control:
	c.position = Vector2(x, y)
	if w >= 0.0 or h >= 0.0:
		c.size = Vector2(w if w >= 0.0 else c.size.x, h if h >= 0.0 else c.size.y)
	return c


## Everything under `root` stops eating touches, so the parent card or button takes the tap.
static func pass_through(root: Node) -> void:
	for n in root.get_children():
		if n is Control:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		pass_through(n)


# --- the phone's top edge -------------------------------------------------------------------------------------------
static var _safe_cache := 0.0
static var _safe_frame := -1


## The top inset (design px) every screen keeps clear of the phone's camera cutout or status bar (pass 43): the display's
## safe area converted to canvas pixels, or the developer menu's fixed value (Settings.top_inset >= 0). 0 on the PC.
static func safe_top() -> float:
	var s := node("Settings")
	if s and int(s.get("top_inset")) >= 0:
		return float(s.get("top_inset"))
	var f := Engine.get_process_frames()
	if f == _safe_frame:
		return _safe_cache
	_safe_frame = f
	_safe_cache = 0.0
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null or ml.root == null or DisplayServer.get_name() == "headless":
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var inset_px := float(safe.position.y - DisplayServer.window_get_position().y)
	# a desktop window sits a few pixels off its screen's safe area; only a real bar or cutout counts
	if inset_px < 12.0:
		return 0.0
	_safe_cache = inset_px * ml.root.get_visible_rect().size.x / float(win.x)
	return _safe_cache


# --- autoloads, looked up at run time (tool scripts compile before the autoloads exist) ---------------------------------
static func node(name: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(name) if ml else null


static func sfx(id: String) -> void:
	var a := node("Audio")
	if a:
		a.play(id)


## A segment clipped to a box (Liang-Barsky): [] when it misses, else its two ends inside.
static func clip_segment(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for k in 4:
		var p: float = [-d.x, d.x, -d.y, d.y][k]
		var q: float = [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y][k]
		if absf(p) < 0.0001:
			if q < 0.0:
				return []
			continue
		var t: float = q / p
		if p < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]
