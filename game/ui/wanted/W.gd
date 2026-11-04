## "Wanted" (design_handoff_88fits_wanted): sun-bleached paper, ink outlines, brass, red rock. The tokens, the three
## faces and the small helpers every Wanted piece shares. Sizes are canvas px at 1080 x 1920.
class_name W
extends RefCounted

# --- the game's name -------------------------------------------------------------------------------------------------
## What the player reads as the game's name (pass 115, Garry: "Rename the game to Outlaw Survivors, but only in the game
## itself. Don't change anything in the code and such"): the title's big word, the line under it, and the two together
## wherever a line names the game (the Settings version line, Down!'s copied log). The project, the packages, the
## launcher label, the save folder, PostHog and every identifier keep "88fits".
const GAME_NAME := "Outlaw Survivors"
const GAME_WORD := "Outlaw"
const GAME_LINE := "Survivors"

# --- colour ----------------------------------------------------------------------------------------------------------
const PAPER := Color("f3e6c8")          ## panels, cards, buttons, HUD plates
const AGED := Color("e2cfa4")           ## unselected tabs, locked cards, empty tracks, empty stars
const INK := Color("241b14")            ## every border, every hard shadow, body text
const INK_SOFT := Color("5a4a3a")       ## secondary text, italic lines, labels
const BRASS := Color("c9932f")          ## primary button, filled stars, rivets, the coin (the weapon plate until pass 47)
const BRASS_DARK := Color("a8792a")     ## pressed primary, gold numbers, "LINE" text
const ROCK := Color("b4472b")           ## danger button, boss HP, "the price", a passive's trade
const BAD_DARK := Color("7d1f16")       ## a debuff's number (−15% max HP on the hero plaque): dark red, darker than rock, reads on paper
const SAGE := Color("6e8b5e")           ## health, positive numbers, pickups (the passive plate until pass 47)
const TURQUOISE := Color("3f8f8a")      ## perk plate
const EMBER := Color("d9662a")          ## evolution plate, EVOLVED banner, Elite pointer
const PLUM := Color("4a3358")           ## mutation plate, path chips
const RARE := Color("3e6e9e")           ## wax seal, shield bar
const EPIC := Color("8a4fb0")           ## wax seal, XP bar
const COMMON := Color("8a8f7a")         ## wax seal
const TOAST_GREEN := Color("7fe07f")
const TOAST_PURPLE := Color("b57bff")
## Pass 47 (Garry: "Weapons should all have a light blue background, while Line Item will have a light yellow
## background"): the two plates the HUD shows, each light enough for the painted icon over it to keep its ink outline,
## and far enough from the paper (cream) and the brass (buttons) to read as their own colour on a card.
const WEAPON_BLUE := Color("f6d75e")    ## weapon plate: the line yellow since pass 47c (Garry: weapons like lines); light blue, then grey before, the name kept
const WEAPON_INK := Color("4a4d55")     ## "WEAPON" on a card: a dark grey that reads on paper
const LINE_YELLOW := Color("f6d75e")    ## line plate
const LINE_INK := Color("8a6a10")       ## "LINE" on a card: the line yellow, dark enough to read on paper
## A passive item's plate is its rarity in World of Warcraft's colours (pass 47, Garry: "mark the background of the
## items with the World of Warcraft colours"); no wax seal and no rarity word go with it.
## WoW's hues, softened (pass 47b, Garry: too saturated): the same five, toned towards the paper. Common is a light grey
## since pass 53 (Garry: "Change the White of Common item bg to a light gray. (For Weapons and Line Items as well)"): it
## was an off-white (f4efe4) that read as the paper itself; d2cfc7 reads grey on the paper and still carries a dark icon,
## and level_fill hands it to every level-1 weapon and line.
const RARITY_PLATE := {"common": Color("d2cfc7"), "uncommon": Color("8cc97a"), "rare": Color("6b9fd8"),
	"epic": Color("a585c8"), "legendary": Color("e0a060")}
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const DIM := Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.78)        ## behind the in-run modals
const DIM_CHEST := Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.85)
const DIM_DOWN := Color(90 / 255.0, 30 / 255.0, 20 / 255.0, 0.82)
const DIM_STRANGER := Color(30 / 255.0, 18 / 255.0, 26 / 255.0, 0.86)
const DIM_GATE := Color(48 / 255.0, 30 / 255.0, 14 / 255.0, 0.40)
const DIM_ASK := Color(36 / 255.0, 27 / 255.0, 20 / 255.0, 0.55)     ## behind a WConfirm, over whatever asked (the pause board, a menu, Down!)
const WASH := Color(243 / 255.0, 230 / 255.0, 200 / 255.0, 0.82)    ## over the desert behind the menus

## A plate's colour by kind, and the colour of the kind's one word. A passive item's plate is its rarity's
## (RARITY_PLATE, plate_fill); "passive" here is the common one's.
const KIND := {"weapon": WEAPON_BLUE, "evolution": EMBER, "mutation": PLUM, "line": LINE_YELLOW, "passive": Color("ffffff"),
	"perk": TURQUOISE, "character": AGED, "enemy": INK, "elite": INK, "pickup": SAGE, "map": BRASS}
const KIND_WORD := {"weapon": WEAPON_INK, "evolution": EMBER, "mutation": PLUM, "line": LINE_INK, "passive": INK_SOFT,
	"perk": TURQUOISE, "character": INK_SOFT, "enemy": INK, "elite": INK}
## The wax seal's colours (the seals left the item cards in pass 43; the NEW BEST seal and the tools keep the piece).
const RARITY := {"common": COMMON, "rare": RARE, "epic": EPIC}
## An evolved weapon or line: a dark plate inside a brass ring, the same for both, so an evolution reads at a glance
## next to the light blue weapons and the light yellow lines.
const EVOLVED_FILL := INK
const EVOLVED_RING := BRASS

# --- type ------------------------------------------------------------------------------------------------------------
const SLAB_PATH := "res://ui/fonts/AlfaSlabOne-Regular.ttf"
const SERIF_PATH := "res://ui/fonts/Bitter.ttf"
const SERIF_ITALIC_PATH := "res://ui/fonts/Bitter-Italic.ttf"
const MONO_PATH := "res://ui/fonts/JetBrainsMono.ttf"
static var _fonts: Dictionary = {}


## Each face's ascent and descent over its em (hhea = typo in all five): CSS "normal" line height is these, each rounded
## to the pixel (Chrome), where Font.get_height() rounds both up and so runs a pixel taller. Pass 122 (lane UIKIT_A):
## Ultra (2066 / 561 over 2048) and Rubik (935 / 250 over 1000, upright and italic alike), measured with fontTools.
const METRICS := {"Bitter": [0.935, 0.265], "AlfaSlab": [1.036, 0.333], "JetBrains": [1.02, 0.3],
	"Ultra": [1.0088, 0.2739], "Rubik": [0.935, 0.25]}


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
## Pass 122 (lane UIKIT_A): Ultra; a size is not known here, so a caller that
## sets small slab text goes through slab_for (text and slab_text do), which keeps Ultra off anything under R.ULTRA_MIN.
static func slab(track: int = 0) -> Font:
	return R.display(track)


## The Wanted slab face (Alfa Slab One, tracked `track` px) whatever the theme (pass 122, the review of lane UIHUD): for
## the pieces Garry keeps as they are under Royale ("Toasts, banners, hints and TAP TO GO stay as they are"; the kill
## counter's number and the boss's name): WToasts, WBanner, WKillCount, ResumeGate and the HUD read it.
static func wanted_slab(track: int = 0) -> Font:
	return _base(SLAB_PATH) if track == 0 else _variant(SLAB_PATH, 0, track)


## Slab text held to the Wanted face whatever the theme (pass 122): the face above, `color` as given (no mapping to the
## kit's cream), the ink stroke and shadow colours with the shadow down-right and no edge: exactly what text() builds
## while the theme is off. The caller sets its own stroke and shadow sizes, as it did.
static func wanted_text(t: String, size: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		line_h: float = 0.0, track: int = 0) -> WText:
	var w := WText.new()
	w.font = wanted_slab(track)
	w.font_size = size
	w.color = color
	w.align = align
	w.line_height = line_h
	w.text = t
	return w


## Bitter whatever the theme (pass 122): the gate's "Still paused" line, kept as it is with TAP TO GO.
static func wanted_serif(weight: int = 400, italic: bool = false, track: int = 0) -> Font:
	return _variant(SERIF_ITALIC_PATH if italic else SERIF_PATH, weight, track)


## Body text held to the Wanted face and `color` whatever the theme, bold numbers as serif_text sets them (pass 123: the
## paper posters; Garry: "Change all of the font colours on those elements to be what they were before").
static func wanted_serif_text(t: String, size: int, color: Color = INK, weight: int = 400, italic: bool = false,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, line_h: float = -1.0, wrap: bool = false) -> WText:
	var w := WText.new()
	w.font = wanted_serif(weight, italic)
	w.font_size = size
	w.color = color
	w.align = align
	w.line_height = size * 1.3 if line_h < 0.0 else line_h
	w.wrap = wrap
	w.text = t
	w.bold_font = wanted_serif(BOLD_WEIGHT, italic)
	w.bold_numbers = true
	return w


## A tracked uppercase label held to the Wanted face whatever the theme (pass 123, the paper posters).
static func wanted_label(t: String, size: int = 20, color: Color = INK_SOFT, em_frac: float = 0.15) -> WText:
	var w := WText.new()
	w.font = wanted_serif(600, false, em(size, em_frac))
	w.font_size = size
	w.color = color
	w.text = t.to_upper()
	return w


## The display face for text at `size` (pass 122): the slab, or under Royale Rubik 700 where Ultra would fill in (a size
## under R.ULTRA_MIN, 28 px: Garry, "NO Ultra under about 28 px in 1080 space").
static func slab_for(size: int, track: int = 0) -> Font:
	if size < R.ULTRA_MIN:
		return R.body(R.LABEL_WEIGHT, false, track)
	return slab(track)


## Bitter at 400 or 600, upright or italic: effect text, notes, labels and flavour lines. Pass 122: Rubik under Royale,
## 400 -> 500 (body), 600 -> 700 (labels), 800 -> 800 (bold numbers): R.body_weight.
static func serif(weight: int = 400, italic: bool = false, track: int = 0) -> Font:
	return R.body(R.body_weight(weight), italic, track)


## JetBrains Mono: the developer menu and the placeholders' labels.
static func mono(weight: int = 500, track: int = 0) -> Font:
	return _variant(MONO_PATH, weight, track)


## Letter spacing in px for a tracking given in em (the mock's letter-spacing: .15em at 20 px is 3 px).
static func em(size: int, em_frac: float) -> int:
	return int(round(size * em_frac))


# --- text ------------------------------------------------------------------------------------------------------------
## Pass 122 (lane UIKIT_A), under Royale: the Wanted ink colours are mapped to the kit's cream, secondary and gold at
## construction (R.text_colour: INK -> cream, INK_SOFT -> secondary, PAPER -> cream, BRASS -> gold ...; a colour set on
## the WText afterwards is kept as given); display text (Ultra) carries its navy edge (R.edge: the stroke, the hard drop
## straight down, the bevel when gold) and a display size under R.ULTRA_MIN is set in Rubik 700 instead.
static func text(t: String, font: Font, size: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT,
		line_h: float = 0.0, wrap: bool = false) -> WText:
	var w := WText.new()
	var f := font
	var col := color
	var edge := false
	col = R.text_colour(color)
	if R.is_display(font):
		if size < R.ULTRA_MIN:
			f = R.body(R.LABEL_WEIGHT, false, (font as FontVariation).spacing_glyph if font is FontVariation else 0)
		else:
			edge = true
	w.font = f
	w.font_size = size
	w.color = col
	w.align = align
	w.line_height = line_h
	w.wrap = wrap
	w.text = t
	if edge:
		R.edge(w, size, col.is_equal_approx(R.GOLD_TEXT))
	return w


## Slab text (Alfa Slab One). CSS line-height 1 is the default for slab headings in the mock; pass 0 for the face's
## own (CSS normal: 1.369 for Alfa Slab, 1.2 for Bitter, 1.32 for JetBrains Mono). Sizes elsewhere are outside sizes
## (the mock's CSS widths are content-box: add the borders).
static func slab_text(t: String, size: int, color: Color = INK, align: int = HORIZONTAL_ALIGNMENT_LEFT, line_h: float = -1.0) -> WText:
	return text(t, slab_for(size), size, color, align, size * 1.0 if line_h < 0.0 else line_h)


## Body text (Bitter). Effect text wraps at line-height 1.3 in the mock. Pass 54 (Garry: bold numbers in every item
## description): the numbers in it, with their unit ("1.5 s", "+15%", "×2"), are set in Bitter 800 (WText.bold_numbers);
## `bold` false keeps the whole line at one weight (a version line, a clock).
static func serif_text(t: String, size: int, color: Color = INK, weight: int = 400, italic: bool = false,
		align: int = HORIZONTAL_ALIGNMENT_LEFT, line_h: float = -1.0, wrap: bool = false, bold: bool = true) -> WText:
	var w := text(t, serif(weight, italic), size, color, align, size * 1.3 if line_h < 0.0 else line_h, wrap)
	if bold:
		w.bold_font = serif(BOLD_WEIGHT, italic)
		w.bold_numbers = true
		w.bold_color = R.NUMBER_HI
	return w


## The weight a number is set in inside body text (Bitter is variable to 900).
const BOLD_WEIGHT := 800


## The tracked uppercase labels (Bitter 600, letter-spacing +15 %). Pass 122: Rubik 700 at .2em in the secondary blue
## under Royale (R.label; a tracking passed in is kept, the default follows the theme).
static func label(t: String, size: int = 20, color: Color = INK_SOFT, em_frac: float = -1.0) -> WText:
	return R.label(t, size, R.text_colour(color), R.LABEL_TRACK if em_frac < 0.0 else em_frac)


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
## The kind an item is drawn and named as: weapon, evolution, mutation, perk, line (pass 47), passive, character,
## enemy... A line and a passive item are both PassiveDefs in content/passives; `content_kind` is the name the
## Registry, the save and the unlock quests know them by.
static func kind_of(def: ContentDef) -> String:
	if def == null:
		return "weapon"
	if def is WeaponDef:
		return "evolution" if (def as WeaponDef).is_evolution else "weapon"
	if def is MutationDef:
		return "mutation"
	if def is PerkDef:
		return "perk"
	if def is PassiveDef:
		return "line" if is_line(def) else "passive"
	if def is CharacterDef:
		return "character"
	if def is EnemyDef:
		return "enemy"
	return def.kind()


## A line (pass 47): a levelled stat item that evolves once maxed and sits in one of the HUD's six line slots beside
## the weapons; its evolution is a line too. Everything else in content/passives is a passive item: no cap, not on the
## HUD (the pause screen's Build tab and the Collection list it). PassiveDef.is_line() decides (`line` in its JSON).
static func is_line(def: ContentDef) -> bool:
	return def is PassiveDef and (def as PassiveDef).is_line()


## The kind the Registry, the save's met-it lists (Save.seen) and the unlock quests know an item by: a line is a
## passive there, everything else is its kind_of.
static func content_kind(def: ContentDef) -> String:
	var k := kind_of(def)
	return "passive" if k == "line" else k


## The small corner glyph a card's plate carries (pass 54, Garry: "a small corner glyph" telling weapons from lines, since
## both sit on plates of the same colours): "weapon" for a weapon and its evolution, "line" for a line and its evolution,
## "" for everything else (passive items, perks, mutations).
static func kind_mark_of(def: ContentDef) -> String:
	if def is WeaponDef:
		return "weapon"
	if def is PassiveDef:
		return "line" if is_line(def) else ""
	return ""


## The painted glyph of a kind mark (art/ui/wanted/kind_<kind>.png: a revolver (pass 56), a rolled scroll; made by
## tools/make_kind_glyphs.py), cached; null until the picture is imported, when WPlate draws the kind's letter instead.
const KIND_GLYPH_PATH := "res://art/ui/wanted/kind_%s.png"
static var _kind_glyphs: Dictionary = {}


static func kind_glyph(kind: String) -> Texture2D:
	if kind == "":
		return null
	if not _kind_glyphs.has(kind):
		var path := KIND_GLYPH_PATH % kind
		_kind_glyphs[kind] = load(path) if ResourceLoader.exists(path) else null
	return _kind_glyphs[kind]


## A plate's fill for an item (pass 47): an evolved weapon or line dark (WPlate rings it in brass), a passive item its
## rarity's World of Warcraft colour, anything else its kind's colour. Pass 48 (Garry: plates that change colour as they
## level): a weapon or a line takes the colour of its `level` on the rarity ladder, level 1 common .. level 5 legendary
## (level_fill); level 0 means the item in general (the Collection, a tool) and reads common.
static func plate_fill(def: ContentDef, level: int = 0) -> Color:
	if def == null:
		return KIND["weapon"]
	if is_evolved(def) or is_evolved_rung(def, level):
		return EVOLVED_FILL
	var k := kind_of(def)
	if k == "passive":
		# pass 95 (lane PASSIVES): a passive item climbs the ladder from its rarity, one rung a level (rung_of); level 0
		# is the item in general, its rarity's colour
		return RARITY_PLATE.get(rung_of(def, level), RARITY_PLATE["common"])
	if k == "weapon" or k == "line":
		return level_fill(level)
	return KIND.get(k, BRASS)


## The rung a passive item stands on at `level` (pass 95, lane PASSIVES; PassiveDef.rung_at): its rarity at level 1 and
## at 0 (the item in general), a rarity up each level, "evolved" at its top; the rarity itself for anything else.
static func rung_of(def: ContentDef, level: int = 0) -> String:
	if def is PassiveDef and (def as PassiveDef).on_ladder() and level > 0:
		return (def as PassiveDef).rung_at(level)
	return rarity_of(def)


## Whether `level` is a passive item's Evolved rung (pass 95): the dark plate in the brass ring, the Evolved icon.
static func is_evolved_rung(def: ContentDef, level: int) -> bool:
	return def is PassiveDef and (def as PassiveDef).is_evolved_rung(level)


## The icon an item is drawn with at `level` (pass 95): a passive item's Evolved icon on its Evolved rung, else its own.
static func icon_at(def: ContentDef, level: int = 0) -> Texture2D:
	if def is PassiveDef:
		return (def as PassiveDef).icon_at(level)
	return def.icon if def else null


## The plate colour of a weapon or a line at `level` (pass 48): RARITY_PLATE by RARITIES[level - 1], level 1 common up to
## level 5 legendary (and past it), 0 or less common.
static func level_fill(level: int) -> Color:
	return RARITY_PLATE[RARITIES[clampi(level - 1, 0, RARITIES.size() - 1)]]


## An evolved item: an evolution weapon, or a line that grew out of another line.
static func is_evolved(def: ContentDef) -> bool:
	if def is WeaponDef:
		return (def as WeaponDef).is_evolution
	if def is PassiveDef:
		return (def as PassiveDef).is_evolved()
	return false


## The item's rarity, one of RARITIES (anything else reads as common).
static func rarity_of(def: ContentDef) -> String:
	var r := def.rarity if def else "common"
	return r if RARITY_PLATE.has(r) else "common"


## The largest a level mark goes: stars for weapons (/5 since pass 48, /8 before) and passives (their max), notches for
## ranks (/3).
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


## The dim behind a screen by kind, in the theme (pass 122, lane UIKIT_A): "modal" (DIM), "chest", "down", "stranger",
## "gate", "ask" (a WConfirm) and "wash" (the menus' paper wash over the desert still). Under Royale a modal, a chest,
## the Stranger and a question sit on 80 % black (R.DIM), the gate on R.DIM_GATE, Down! on R.DIM_DOWN (a red cast), the
## menus on R.WASH (a navy wash that keeps the painted scene). The kit's pieces take theirs here; a screen's own ColorRect
## follows in its lane.
static func dim_color(kind: String) -> Color:
	match kind:
		"gate":
			return R.DIM_GATE
		"down":
			return R.DIM_DOWN
		"wash":
			return R.WASH
	return R.DIM


static func _wanted_dim(kind: String) -> Color:
	match kind:
		"chest":
			return DIM_CHEST
		"down":
			return DIM_DOWN
		"stranger":
			return DIM_STRANGER
		"gate":
			return DIM_GATE
		"ask":
			return DIM_ASK
		"wash":
			return WASH
	return DIM


const DIM_KINDS := ["modal", "chest", "down", "stranger", "gate", "ask", "wash"]


## A Wanted dim constant as the theme shows it (pass 122): the kit's pieces map what a screen passed them (WModal's
## build_dim); a colour that is none of the kit's dims is kept, so a screen's own alpha (the Bounty posters') survives.
static func themed_dim(c: Color) -> Color:
	for k: String in DIM_KINDS:
		if _wanted_dim(k).is_equal_approx(c):
			return dim_color(k)
	return c


# --- the theme ---------------------------------------------------------------------------------------------------------


## A black info plate's box (pass 122): under Royale the 56 % black plate with no edge and no base (HardBox.role
## "plate"); under Wanted the paper plate with its ink border and hard shadow, as the HUD draws today.
static func plate_box(border: int = 5, shadow: int = 6, radius: int = 0) -> HardBox:
	var b := box(PAPER, border, shadow, radius)
	b.role = "plate"
	return b


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


# --- the phone's bottom edge (pass 123, lane KIT2) ----------------------------------------------------------------------
static var _safe_b_cache := 0.0
static var _safe_b_frame := -1
## A fixed bottom inset (design px) for tools and tests; -1 = the display's own (a phone's gesture bar).
static var bottom_inset_override := -1.0


## The bottom inset (design px) a docked bar keeps clear of the phone's gesture bar or navigation buttons: the window's
## foot less the display's safe area's, converted to canvas pixels as safe_top does (a Settings `bottom_inset` >= 0, when
## the setting exists, or bottom_inset_override wins). 0 on the PC (no gesture bar; a window taller than its screen would
## read as one) and headless.
static func safe_bottom() -> float:
	if bottom_inset_override >= 0.0:
		return bottom_inset_override
	var s := node("Settings")
	if s:
		var fixed = s.get("bottom_inset")
		if fixed != null and int(fixed) >= 0:
			return float(fixed)
	var f := Engine.get_process_frames()
	if f == _safe_b_frame:
		return _safe_b_cache
	_safe_b_frame = f
	_safe_b_cache = 0.0
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null or ml.root == null or DisplayServer.get_name() == "headless":
		return 0.0
	# only a phone has a gesture bar: a desktop window taller than its screen (a 1080 x 1920 capture) would read the part
	# below the taskbar as one
	if not OS.has_feature("mobile"):
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var foot := float(DisplayServer.window_get_position().y + win.y)
	var inset_px := foot - float(safe.position.y + safe.size.y)
	# a desktop window sits a few pixels off its screen's safe area (or past it); only a real bar counts
	if inset_px < 12.0:
		return 0.0
	_safe_b_cache = inset_px * ml.root.get_visible_rect().size.x / float(win.x)
	return _safe_b_cache


# --- pass 123 (lane KIT2): the small pieces the Royale screens share -----------------------------------------------------
## A glyph drawn in code, for what Ultra and Rubik do not carry (no ● ◷ ▶ ≡ or padlock in either face): "ad" (a video
## ad's icon, a rounded screen with a play triangle in it: Garry, "instead of text let's use an icon. An icon that's
## usually used for ads buttons"), "play" (▶), "lock" (a padlock), "clock" (◷) and "menu" (≡). `px` is its height;
## `col` its colour; `accent` the colour cut into it (the ad's triangle, the lock's keyhole), clear = navy on a light
## glyph and cream on a dark one. Drawn only when it redraws (no work a frame). Named Glyph_<kind>, meta "glyph".
static func glyph(kind: String, px: float, col: Color, accent: Color = Color(0, 0, 0, 0)) -> Control:
	var c := Control.new()
	c.name = "Glyph_%s" % kind
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = glyph_size(kind, px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.set_meta("glyph", kind)
	c.draw.connect(func() -> void: draw_glyph(c, kind, Rect2(Vector2.ZERO, c.size), col, accent))
	return c


## A glyph's box at `px` tall (the ad's screen is wider than tall, the padlock narrower).
static func glyph_size(kind: String, px: float) -> Vector2:
	match kind:
		"ad":
			return Vector2(roundf(px * 1.36), px)
		"lock":
			return Vector2(roundf(px * 0.82), px)
		"menu":
			return Vector2(roundf(px * 1.1), px)
	return Vector2(px, px)


## Draws glyph `kind` into `r` on `ci` (any CanvasItem, in its _draw or draw signal).
static func draw_glyph(ci: CanvasItem, kind: String, r: Rect2, col: Color, accent: Color = Color(0, 0, 0, 0)) -> void:
	var cut := accent if accent.a > 0.0 else (R.NAVY if col.get_luminance() > 0.5 else R.CREAM)
	var h := r.size.y
	var w := r.size.x
	match kind:
		"ad":
			var scr := Rect2(r.position + Vector2(0.0, h * 0.08), Vector2(w, h * 0.84))
			ci.draw_style_box(R.flat(col, maxi(int(round(h * 0.2)), 2)), scr)
			var c := scr.get_center() + Vector2(h * 0.04, 0.0)
			var t := h * 0.25
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-t * 0.8, -t), c + Vector2(-t * 0.8, t), c + Vector2(t, 0.0)]), cut)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([r.position + Vector2(w * 0.14, 0.0), r.position + Vector2(w * 0.14, h),
				r.position + Vector2(w * 0.96, h * 0.5)]), col)
		"lock":
			var sw := maxf(h * 0.13, 2.0)
			var sc := Vector2(r.position.x + w * 0.5, r.position.y + h * 0.38)
			var sr := w * 0.3
			ci.draw_arc(sc, sr, PI, TAU, 18, col, sw, true)
			ci.draw_line(sc + Vector2(-sr, 0.0), sc + Vector2(-sr, h * 0.1), col, sw)
			ci.draw_line(sc + Vector2(sr, 0.0), sc + Vector2(sr, h * 0.1), col, sw)
			var body := Rect2(r.position + Vector2(0.0, h * 0.44), Vector2(w, h * 0.56))
			ci.draw_style_box(R.flat(col, maxi(int(round(h * 0.1)), 1)), body)
			var kc := body.get_center() + Vector2(0.0, -h * 0.05)
			ci.draw_circle(kc, h * 0.075, cut, true, -1.0, true)
			ci.draw_rect(Rect2(kc + Vector2(-h * 0.035, 0.0), Vector2(h * 0.07, h * 0.15)), cut)
		"clock":
			var cw := maxf(h * 0.12, 2.0)
			var cc := r.get_center()
			var rad := minf(w, h) * 0.5 - cw * 0.5
			ci.draw_arc(cc, rad, 0.0, TAU, 32, col, cw, true)
			ci.draw_line(cc, cc + Vector2(0.0, -rad * 0.62), col, cw, true)
			ci.draw_line(cc, cc + Vector2(rad * 0.5, 0.0), col, cw, true)
		"menu":
			var bh := maxf(roundf(h * 0.17), 2.0)
			for k in 3:
				var y := r.position.y + h * 0.14 + (h * 0.72 - bh) * float(k) * 0.5
				ci.draw_style_box(R.flat(col, maxi(int(bh * 0.5), 1)), Rect2(Vector2(r.position.x, y), Vector2(w, bh)))


## The black info pill (pass 123; README "Info plate / pill", the mocks' run pills, the trait "+1% CRIT per Level",
## "◷ 7:10 to the boss", "01:01 · STAGE 1"): R.PLATE (56 % black) with the 2 px white inset, no edge, no base, PILL_RADIUS
## corners, PILL_PAD at either side, `h` tall, the pieces centred PILL_GAP apart. `parts` is a String or an Array of
## String / [text, colour] / [text, colour, "bold" or a Font] / {"coin": px} / {"glyph": kind, "px": n}; the text is
## Rubik 500 at `px` in `color` (white; a part's own colour wins), a "bold" part Rubik 700; consecutive text parts are one
## line (their own spaces between). Under Wanted the paper plate with ink Bitter, so a pill built there still reads.
static func pill(parts, px: int = R.PILL_PX, h: float = R.PILL_H, color: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var ink := color if color.a > 0.0 else (R.WHITE)
	var body: Font = R.body(R.BODY_WEIGHT)
	var bold: Font = R.body(R.LABEL_WEIGHT)
	var p := PanelContainer.new()
	p.name = "Pill"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", plate_box(3, 0, R.PILL_RADIUS).pad(R.PILL_PAD, 0, R.PILL_PAD, 0))
	p.custom_minimum_size.y = h
	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", R.PILL_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var list: Array = parts if parts is Array else [str(parts)]
	var runs: Array = []
	var flush := func() -> void:
		if runs.is_empty():
			return
		var t := text("", body, px, ink, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		t.runs = runs.duplicate()
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
		runs.clear()
	for part in list:
		if part is Dictionary:
			flush.call()
			var d := part as Dictionary
			if d.has("coin"):
				row.add_child(WCoin.make(float(d["coin"]), d.get("fill", BRASS), float(d.get("border", 3.0)), str(d.get("currency", "gold"))))
			elif d.has("glyph"):
				row.add_child(glyph(str(d["glyph"]), float(d.get("px", px)), d.get("color", ink)))
		elif part is Array:
			var a := part as Array
			var col = a[1] if a.size() > 1 else null
			var f = null
			if a.size() > 2 and a[2] is Font:
				f = a[2]
			elif a.size() > 2 and str(a[2]) == "bold":
				f = bold
			runs.append([str(a[0]), col, f])
		else:
			runs.append([str(part), null, null])
	flush.call()
	return p


## "n short" (pass 123; the mock 8_Shop_24_gold): what a price is short of the purse, Rubik 700 in red (ROCK under Wanted).
static func short_text(n: int, px: int = R.SHORT_PX) -> WText:
	var t := text("%s short" % num(n), R.body(R.LABEL_WEIGHT), px,
		R.ROLES["red"]["top"], HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	t.name = "Short"
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## A price button with its shortfall (pass 123; the mocks 8_Shop_24_gold, 5_Upgrade): an HBox named "Price", right
## aligned: "n short" (named "Short", shown only when `short` > 0) R.SHORT_GAP before the button (named "Button",
## WButton.price: "● 300 · BUY" in `role`, or the locked grey with the price alone when short). Wire the button's
## `pressed` (price_button_of(row)); a short button still emits it (WTap's locked rule), so the screen can say why.
static func price_row(amount: int, word: String = "", p_role: String = "green", px: int = R.PRICE_PX, short: int = 0,
		currency: String = "gold") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Price"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", R.SHORT_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := short_text(maxi(short, 0))
	s.visible = short > 0
	row.add_child(s)
	var b := WButton.price(amount, word, p_role, px, short, currency)
	b.name = "Button"
	row.add_child(b)
	return row


## The button inside a price_row.
static func price_button_of(row: Control) -> WButton:
	if row == null:
		return null
	return row.get_node_or_null("Button") as WButton


## A solid slate board (pass 123; Garry on the Collection's item page: "Make it sit on a more solid background, not just
## hover in the air"): the slate panel (HardBox role "panel": the gradient, a 4 px navy edge, the 8 px navy base, the
## lip) as one sheet behind a whole page, `pad` inside its edge. Under Wanted ScreenBase.board's paper box.
static func sheet_box(pad: Vector2 = Vector2(24, 24)) -> HardBox:
	var e := R.PANEL_EDGE
	var b := box(PAPER, e, R.PANEL_BASE, 0).pad(pad.x + e, pad.y + e, pad.x + e, pad.y + e)
	b.role = "panel"
	return b


## A solid cell inside a sheet (pass 123): R.CELL, opaque, a 3 px navy edge, 6 px corners, no base (a level's cell, a
## mutation's column: the mock's see-through black made solid). Under Wanted an aged box with a 3 px ink edge.
static func cell_box(pad: Vector2 = Vector2(16, 14)) -> HardBox:
	var e := R.CELL_EDGE
	var b := box(R.CELL, e, 0, R.RADIUS)
	return b.pad(pad.x + e, pad.y + e, pad.x + e, pad.y + e)


# --- autoloads, looked up at run time (tool scripts compile before the autoloads exist) ---------------------------------
static func node(name: String) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(name) if ml else null


static func sfx(id: String) -> void:
	var a := node("Audio")
	if a:
		a.play(id)


## The first of `ids` the sound map binds (pass 54: a new sound, the reel's tick or the card's, falls back to an old one
## until the lead binds it).
static func sfx_first(ids: Array) -> void:
	var a := node("Audio")
	if a == null:
		return
	var reg := node("Registry")
	var sm = reg.get("soundmap") if reg else null
	for id in ids:
		if sm == null or not (sm.entry(str(id)) as Dictionary).is_empty():
			a.play(str(id))
			return


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
