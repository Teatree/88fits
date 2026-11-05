## "Royale, refined" (design_handoff_88fits_royale, Claude Design, 2026-11-02; the lead's read in
## docs/ui_review/royale_assessment.md; Garry's build brief of the same day): the game's one design since pass 124, its
## tokens and the helpers every component shares. Navy on every edge, outline and base; slate panels on a hard navy base;
## glossy two-tone buttons whose colour says what they do (gold = happens now, green = buys, blue = opens something,
## slate = everything else, red = danger, locked = grey at 75%); cream display text with a navy edge (Garry: titles in
## cream, gold only for what acts at once, coins, stars and Legendary); Ultra for display and Rubik for body. Pass 122
## (lane UIKIT_A). Sizes are canvas px at 1080 x 1920, as W's. The radial rarity fills, the rainbow rim and the rays are
## shaders (lane UIKIT_B), as are the item frame, the bars, the sliders, the coin and the star line: the numbers they
## need live here.
class_name R
extends RefCounted

# --- colour ----------------------------------------------------------------------------------------------------------
const NAVY := Color("0e1f4a")              ## every edge, outline and base; the text on a gold button
const CREAM := Color("fff6dc")             ## display text: screen titles, names, big numbers
const GOLD_TEXT := Color("ffdc73")         ## gold display text: coins, stars, Legendary, a count's number
const GOLD_BEVEL := Color("b7780a")        ## the bevel under a big gold title (0 .045em), over the navy drop (0 .075em)
const SECONDARY := Color("cfe3ff")         ## labels, sublines, secondary text
const WHITE := Color("ffffff")             ## the type on a black info plate, the toggle's knob
const MUTED := Color("8f98ab")             ## a count at 0, the locked grey's top
## The slate panel: a top-to-bottom gradient (SLATE_TOP at 0 %, SLATE_MID at 60 %, SLATE_BOTTOM at 100 %), a 4 px navy
## border, an 8 px navy base (a hard shadow straight down), a 14 % white lip along the top inside the border.
const SLATE_TOP := Color("3a4661")
const SLATE_MID := Color("27314a")
const SLATE_BOTTOM := Color("1f2840")
const SLATE_MID_AT := 0.6
const PANEL_STOPS := [[0.0, SLATE_TOP], [SLATE_MID_AT, SLATE_MID], [1.0, SLATE_BOTTOM]]
const PANEL_EDGE := 4
const PANEL_BASE := 8
const PANEL_LIP := 0.14
const PANEL_LIP_PX := 3
## A dimmer slate (an unselected tab's, an empty track's: where Wanted used AGED).
const SLATE_DIM := Color("27314a")
## Buttons: a 4 px navy edge, the fill split at 44 % (the role's top colour over its bottom), a 45 % white lip, an 8 px
## base in the role's base colour with a 4 px navy base under it; pressed, down 8 px with no base and an inset shadow;
## locked, grey at 75 %.
const BUTTON_EDGE := 4
const BUTTON_SPLIT := 0.44
const BUTTON_LIP := 0.45
const BUTTON_LIP_PX := 3
const BUTTON_BASE := 8
const BUTTON_NAVY_BASE := 4
const PRESS_DOWN := 8
const PRESS_INSET := Color(14 / 255.0, 31 / 255.0, 74 / 255.0, 0.35)
const PRESS_INSET_PX := 6
const LOCKED_ALPHA := 0.75
## The roles (Garry: button colours mean something): gold = happens now (START, TAKE IT, RESUME, DEAL, CLAIM), green =
## buys, blue = opens something (DETAILS, CHOOSE, UPGRADE), slate = everything else, red = danger (Abandon, Stay down,
## Leave the shop, Walk away), locked = grey at 75 %. Each: the fill's top and bottom, the base, the label's colour.
const ROLES := {
	"gold": {"top": Color("ffdc73"), "bottom": Color("f5b82a"), "base": Color("a86d06"), "text": Color("0e1f4a")},
	"green": {"top": Color("a3ea74"), "bottom": Color("5fc43a"), "base": Color("2a7416"), "text": Color("fff6dc")},
	# pass 123 (Garry: "The white text on the blue button doesn't read well at all, either go for a darker blue or add
	# contour"): a darker blue, and every label on a coloured face wears a navy contour (WButton)
	"blue": {"top": Color("4a8ae0"), "bottom": Color("2360bd"), "base": Color("123375"), "text": Color("ffffff")},
	"slate": {"top": Color("4a5670"), "bottom": Color("2f3a50"), "base": Color("141b2b"), "text": Color("fff6dc")},
	"red": {"top": Color("ff7d6a"), "bottom": Color("e2402f"), "base": Color("8c1f14"), "text": Color("fff6dc")},
	"locked": {"top": Color("8f98ab"), "bottom": Color("6b7488"), "base": Color("363c4a"), "text": Color("fff6dc")},
}
const ROLE_NAMES := ["gold", "green", "blue", "slate", "red", "locked"]
## The black info plate (HUD basics, the wallet, run summaries, stat cells, pills): 56 % black, a 2 px inset of white at
## 8 %, no edge, no base, white type.
const PLATE := Color(8 / 255.0, 10 / 255.0, 18 / 255.0, 0.56)
const PLATE_INSET := Color(1, 1, 1, 0.08)
const PLATE_INSET_PX := 2
## The dims: 80 % black behind a modal and a question; the resume gate's lighter one; Down!'s with a red cast (the
## mock's red dim); the menus' wash over the desert still (the mock paints a sunset there; the lead keeps the painted
## scene: W.dim_color("wash") darkens it so slate reads on it).
const DIM := Color(0, 0, 0, 0.8)
const DIM_GATE := Color(0, 0, 0, 0.4)
const DIM_DOWN := Color(60 / 255.0, 12 / 255.0, 8 / 255.0, 0.82)
const WASH := Color(14 / 255.0, 31 / 255.0, 74 / 255.0, 0.6)
## Corners: 6 px everywhere, 4 on tags and pips, 8 on docked tabs.
const RADIUS := 6
const RADIUS_TAG := 4
const RADIUS_TAB := 8
## The tags (18 px Rubik 700 by Garry's font rule, a 4 px radius, a 3 px navy edge): NEW gold, UPGRADE / BEATEN /
## UNLOCKED / SAFE green, LOCKED and a price short red, a mutation purple.
const TAG_GOLD := Color("f5b82a")
const TAG_GREEN := Color("5fc43a")
const TAG_RED := Color("e2402f")
const TAG_PURPLE := Color("a650e8")
## Pass 123 (Garry: "Mutation Icons looks too much like Epic Rarity Items. Change that to be some other colour"): the
## mutations' own teal, on frames, tags and their kind word; no rarity wears it.
## Pass 123: the half-transparent sheet the menus' boards sit on (ScreenBase.board_sheet).
const SHEET := Color(0.05, 0.075, 0.17, 0.72)
const SHEET_EDGE := Color(0.055, 0.12, 0.29, 0.9)
## Pass 124 (Garry: "Mutation Icons look the same as Perk items ... Choose a look that would make mutations look distinct from
## other items"). Teal was the perks' own colour. What the craft says: tell categories apart by shape first, then by how dark or
## light they are, and only then by hue (a colour-blind player, a small icon on a phone), and don't take a hue the rarity ladder
## uses. So a mutation is the only frame with cut corners (WPlate's shape 2), it has a near-black face like the Evolved frame it
## leads to (three mutations and level 5 evolve a weapon), and a hot rose rim no rarity or perk wears.
const MUTATION_FILL := Color("d81b60")
const TAG_MUTATION := Color("d81b60")
const MUTATION := {"light": Color("5a1a3d"), "base": Color("2c0c22"), "dark": Color("120610"), "rim": Color("ff9dc0"), "rim_b": Color("e8286f"),
	"word": Color("ff9dc0"), "glow": Color(0.95, 0.12, 0.42, 0.55)}
## How far a mutation frame's corners are cut, a share of its side.
const MUTATION_CUT := 0.2
## Pass 123 (Garry: "Make the highlighted numbers in the text be yellowish-white instead of just white"): the bold numbers
## in body text (WText.bold_color through W.serif_text).
const NUMBER_HI := Color("ffe48a")
const TAG_EDGE := 3
const TAG_PX := 18
## The level plaque hanging off an item frame's bottom centre: blue, a navy edge, "LV n" (a plain "n" at 80 px).
## Pass 123 (Garry: "Change the number to be black text on white, cz white on blue doesn't read very well"; "Evo can stay
## on yellow(ish) bg"): a white plaque with black type.
const PLAQUE_TOP := Color("ffffff")
const PLAQUE_BOTTOM := Color("e4e8ef")
## The docked tabs: the active one gold and taller (74 against 62).
const TAB_H := 62
const TAB_H_ACTIVE := 74
const TAB_GAP := 8
## The toggle (84 x 44, gold on, slate off, a white knob), the slider's knob (68 x 58), the modal's width (990).
const TOGGLE_SIZE := Vector2(84, 44)
const TOGGLE_EDGE := 3
const TOGGLE_KNOB := 30
const SLIDER_KNOB := Vector2(68, 58)
const MODAL_W := 990
## The rarity fills (radial: light at the centre top, base, dark at the foot) and rims. The mock's five; uncommon is not
## in it and is derived from today's W.RARITY_PLATE green 8cc97a the same way (its hue at the kit's saturation 0.66,
## epic's; the light / dark / rim by the mock's own ratios: light s x0.58 v x1.12, dark s x1.1 v x0.74, rim s x0.32 at
## full value). Epic and legendary glow; legendary's rim is the thicker gold bevel (RIM_BEVEL: 11 px at 200, 7 at 80)
## with a 3 px inner dark line; Evolved is a black face in a rainbow rim (RAINBOW, a conic sweep) with a soft white glow
## and an EVO plaque on gold. Passive items keep their rarity; weapons and Cards keep pass 48's level_fill rule as their
## fill (level 1 common .. 5 legendary); no new rarity rule (Garry wants the tiers proposed first).
const RARITY := {
	"common": {"light": Color("cdd5de"), "base": Color("95a1b0"), "dark": Color("67727f"), "rim": Color("e4e9ee")},
	"uncommon": {"light": Color("9fe18b"), "base": Color("63c944"), "dark": Color("419529"), "rim": Color("d5ffc9")},
	"rare": {"light": Color("7cc9ff"), "base": Color("2f8de6"), "dark": Color("1c5aa8"), "rim": Color("b4e1ff")},
	"epic": {"light": Color("de9fff"), "base": Color("a650e8"), "dark": Color("6a2bb0"), "rim": Color("f0ccff"),
		"glow": Color(166 / 255.0, 80 / 255.0, 232 / 255.0, 0.85)},
	"legendary": {"light": Color("ffea92"), "base": Color("f6b72a"), "dark": Color("c47d0a"), "rim": Color("fff5c0"),
		"inner": Color("7a4a05"), "glow": Color(246 / 255.0, 183 / 255.0, 42 / 255.0, 0.95)},
	"evolved": {"light": Color("4a4a58"), "base": Color("1a1a22"), "dark": Color("050507"), "rim": Color("ffffff"),
		"glow": Color(1, 1, 1, 0.55)},
}
const RIM_BEVEL := [Color("fff5c0"), Color("f6b72a"), Color("c47d0a"), Color("ffe28a")]
const RAINBOW := [Color("ff4b3e"), Color("ffb13b"), Color("ffe13b"), Color("5fd13c"), Color("2fb8ff"), Color("8a5cff"),
	Color("ff4bd1"), Color("ff4b3e")]
const FRAME_LIP := 0.35
const FRAME_FOOT := 0.22
const FRAME_RIM_BIG := 7       ## the rarity rim at >= 160 px, 5 below; the navy outline 4 at >= 160, 3 below
const FRAME_RIM_SMALL := 5
const FRAME_EDGE_BIG := 4
const FRAME_EDGE_SMALL := 3
const FRAME_ICON := 0.86
## Pass 122 (lane UIKIT_B): the rest of the item frame (core/shaders/ui_radial_fill.gdshader, drawn by WPlate), the level
## plaque and the rays. The lip, the foot and the icon's hard drop are FRAME_LIP_FRAC of the side (10 px at 320, 3 at
## 96; never under 2); the legendary rim is FRAME_LEGEND_RIM times the rarity rim (11 at 200, 7 at 80) with a 3 px dark
## line inside it; the glows reach the mock's blur radii; a locked frame (an item not found yet) wears the locked grey;
## the radial light sits at FRAME_CENTER of the face (the mock's circle at 50 % 42 %), the base colour at FRAME_BASE_AT of
## the reach to the farthest corner; the face's own corners are 2 px inside the rim.
const FRAME_LIP_FRAC := 0.031
const FRAME_LEGEND_RIM := 1.5
const FRAME_LEGEND_INNER := 3
const FRAME_GLOW_EPIC := 30
const FRAME_GLOW_LEGEND := 34
const FRAME_GLOW_EVOLVED := 26
const FRAME_ICON_DROP := Color(0, 0, 0, 0.35)
const FRAME_FACE_RADIUS := 2.0
const FRAME_CENTER := Vector2(0.5, 0.42)
const FRAME_BASE_AT := 0.55
const FRAME_LOCKED := {"light": Color("8f98ab"), "base": Color("6b7488"), "dark": Color("363c4a"), "rim": Color("aab2c2")}
## The level plaque hanging off a frame's bottom centre: PLAQUE_H_FRAC of the side tall (83 at 320, never under
## PLAQUE_H_MIN), PLAQUE_HANG of its height below the frame's foot, its type PLAQUE_FONT_FRAC of the side (48 at 320,
## never under PLAQUE_FONT_MIN; Ultra from R.ULTRA_MIN, Rubik 700 under it by Garry's rule), PLAQUE_PAD_FRAC of the type
## at either side, a navy edge (3 px on a frame under 160), "LV n" (a plain "n" on a frame of PLAQUE_PLAIN_AT px or
## smaller), white type; the EVO plaque the same in gold with navy type.
const PLAQUE_H_FRAC := 0.26
const PLAQUE_HANG := 0.55
const PLAQUE_FONT_FRAC := 0.15
const PLAQUE_H_MIN := 28
const PLAQUE_FONT_MIN := 18
const PLAQUE_PAD_FRAC := 0.54
const PLAQUE_EDGE := 4
const PLAQUE_EDGE_SMALL := 3
const PLAQUE_PLAIN_AT := 80.0
const PLAQUE_TEXT := Color("0b0d14")
const PLAQUE_EVO_TOP := Color("ffdc73")
const PLAQUE_EVO_BOTTOM := Color("f5b82a")
const PLAQUE_EVO_TEXT := NAVY
## The rays behind a pressed card's item and behind the chest's and the mutation offer's frames
## (core/shaders/ui_rays.gdshader): ffe696 at .35, RAYS_ON_DEG lit of every RAYS_PERIOD_DEG (the mock's
## `repeating-conic-gradient(from 0deg, c 0 8deg, transparent 8deg 20deg)`), masked to a disc from RAYS_MASK_IN to
## RAYS_MASK_OUT of its radius, one turn in RAYS_TURN_S seconds; the disc RAYS_SCALE times the frame's side (the mock's 620
## round a 280 frame and 760 round a 320 one).
const RAYS_COLOR := Color(1.0, 0.902, 0.588, 0.35)
const RAYS_ON_DEG := 8.0
const RAYS_PERIOD_DEG := 20.0
const RAYS_MASK_IN := 0.3
const RAYS_MASK_OUT := 0.7
const RAYS_TURN_S := 30.0
const RAYS_SCALE := 2.2
## The bars (Garry: the mock's "look rather dim and unnoticeable. They need to be a little bit more noticeable"): the
## fills brighter and more saturated than the mock's, with a clear light lip, over a black trough (WBar is lane UIKIT_B's).
const BAR_TROUGH := Color(8 / 255.0, 10 / 255.0, 18 / 255.0, 0.72)
const BAR_XP := Color("c06cff")
const BAR_XP_LIP := Color("ecc4ff")
const BAR_HP := Color("4fe06a")
const BAR_HP_LIP := Color("b6ffc1")
const BAR_BOSS := Color("ff4b3e")
const BAR_BOSS_LIP := Color("ffb0a8")
const BAR_GOLD := Color("f5b82a")
const BAR_GOLD_LIP := Color("ffeaa6")

# --- type ------------------------------------------------------------------------------------------------------------
const DISPLAY_PATH := "res://ui/fonts/Ultra-Regular.ttf"
const BODY_PATH := "res://ui/fonts/Rubik.ttf"
const BODY_ITALIC_PATH := "res://ui/fonts/Rubik-Italic.ttf"
## Ultra fills in under this size on a phone (Garry: no Ultra under about 28 px in 1080 space): W.slab_for and W.text
## set anything smaller in Rubik 700 instead.
const ULTRA_MIN := 28
const BODY_WEIGHT := 500
const LABEL_WEIGHT := 700
const BOLD_WEIGHT := 800
const LABEL_TRACK := 0.2
## The edge every Ultra text carries (README section 2): a navy stroke of about 6 % of the size (2.5 px on buttons) and
## a hard drop straight down (7 %); a big gold title adds the bevel (GOLD_BEVEL at 4.5 %, the drop at 7.5 %). These are
## the mock's CSS numbers; `edge` converts the stroke for WText (whose `stroke` draws twice its value outside the glyph,
## where CSS draws half of its stroke outside): WText.stroke = round(css / 3), at least 1.
const STROKE_FRAC := 0.06
const DROP_FRAC := 0.07
const BEVEL_FRAC := 0.045
const GOLD_DROP_FRAC := 0.075
const STROKE_DIV := 3.0
static var _text_map: Array = []
static var _boxes: Dictionary = {}


## Ultra, the display face: titles, names, big numbers, buttons, tabs. `track` is extra px per letter.
static func display(track: int = 0) -> Font:
	return W._base(DISPLAY_PATH) if track == 0 else W._variant(DISPLAY_PATH, 0, track)


## Rubik at a weight (variable 300 .. 900), upright or italic: effect lines, stats, labels, notes.
static func body(weight: int = BODY_WEIGHT, italic: bool = false, track: int = 0) -> Font:
	return W._variant(BODY_ITALIC_PATH if italic else BODY_PATH, weight, track)


## Bitter's weights as Rubik's: 400 (body) -> 500, 600 (labels) -> 700, 800 (bold numbers) -> 800.
static func body_weight(bitter: int) -> int:
	if bitter <= 400:
		return BODY_WEIGHT
	if bitter < 800:
		return LABEL_WEIGHT
	return BOLD_WEIGHT


## The tracked uppercase labels: Rubik 700, letter-spacing .2em, secondary blue (the mock's 18-22 px).
static func label(t: String, size: int = 20, color: Color = SECONDARY, em_frac: float = LABEL_TRACK) -> WText:
	return W.text(t.to_upper(), body(LABEL_WEIGHT, false, W.em(size, em_frac)), size, color, HORIZONTAL_ALIGNMENT_LEFT, 0.0)


## Whether `f` is the display face (Ultra), through any variation.
static func is_display(f: Font) -> bool:
	var base := f
	while base is FontVariation and (base as FontVariation).base_font:
		base = (base as FontVariation).base_font
	return base != null and base.resource_path == DISPLAY_PATH


## The CSS stroke (px) of display text at `size`: 6 % of it (9 at 150, 2 at 34).
static func stroke_px(size: int) -> int:
	return maxi(int(round(STROKE_FRAC * size)), 1)


## The hard drop (px) straight down under display text at `size`: 7 % of it.
static func drop_px(size: int) -> int:
	return maxi(int(round(DROP_FRAC * size)), 1)


## The bevel (px) under a big gold title at `size`: 4.5 % of it, in GOLD_BEVEL, over the drop at 7.5 %.
static func bevel_px(size: int) -> int:
	return maxi(int(round(BEVEL_FRAC * size)), 1)


## The navy edge on a WText of display type: the stroke, the hard drop straight down and, for a gold title, the bevel.
static func edge(t: WText, size: int, gold: bool = false) -> WText:
	t.stroke = maxi(int(round(stroke_px(size) / STROKE_DIV)), 1)
	t.stroke_color = NAVY
	t.shadow = maxi(int(round(GOLD_DROP_FRAC * size)), 1) if gold else drop_px(size)
	t.shadow_color = NAVY
	t.shadow_straight = true
	if gold:
		t.bevel = bevel_px(size)
		t.bevel_color = GOLD_BEVEL
	return t


## No edge on a WText (the navy text of a gold face: a navy stroke on navy only fattens it).
static func no_edge(t: WText) -> WText:
	t.stroke = 0
	t.shadow = 0
	t.bevel = 0
	return t


## The kit's old text colours on paper, as Royale sets them on slate: W.text maps `color` through this; a colour not
## in the table is kept as given (a screen's own colour survives).
static func text_colour(c: Color) -> Color:
	if _text_map.is_empty():
		_text_map = [[W.INK, CREAM], [W.INK_SOFT, SECONDARY], [W.PAPER, CREAM], [W.AGED, SECONDARY],
			[W.BRASS, GOLD_TEXT], [W.BRASS_DARK, GOLD_TEXT], [W.ROCK, ROLES["red"]["top"]], [W.BAD_DARK, ROLES["red"]["top"]],
			[W.SAGE, ROLES["green"]["top"]], [W.WEAPON_INK, SECONDARY], [W.LINE_INK, GOLD_TEXT], [W.PLUM, RARITY["epic"]["light"]],
			[W.TURQUOISE, Color("6fd3cc")]]
	for pair in _text_map:
		if (pair[0] as Color).is_equal_approx(c):
			return pair[1]
	return c


## The button role a Wanted variant plays: primary -> gold (happens now), danger -> red, upgrade -> blue (opens the
## board), secondary -> slate; "locked" is a state, not a variant.
static func role_of(variant: String) -> String:
	match variant:
		"primary":
			return "gold"
		"danger":
			return "red"
		"upgrade":
			return "blue"
	return "slate"


## A role's table ("gold", "green", "blue", "slate", "red", "locked"; anything else reads slate).
static func role(name: String) -> Dictionary:
	return ROLES.get(name, ROLES["slate"])


# --- draw helpers (RenderingServer on a canvas item: HardBox and the pieces that draw by hand share them) ---------------
## A flat rounded box in `col` to draw with .draw(ci, rect); cached by its look. `corners`: which of top-left, top-right,
## bottom-right, bottom-left are rounded.
static func flat(col: Color, radius: int = RADIUS, corners: Array = [true, true, true, true]) -> StyleBoxFlat:
	var key := "%s:%d:%d%d%d%d" % [col.to_html(true), radius, int(corners[0]), int(corners[1]), int(corners[2]), int(corners[3])]
	if _boxes.has(key):
		return _boxes[key]
	var f := StyleBoxFlat.new()
	f.bg_color = col
	f.anti_aliasing = true
	f.corner_radius_top_left = radius if corners[0] else 0
	f.corner_radius_top_right = radius if corners[1] else 0
	f.corner_radius_bottom_right = radius if corners[2] else 0
	f.corner_radius_bottom_left = radius if corners[3] else 0
	_boxes[key] = f
	return f


## A vertical gradient over `rect`: `stops` = [[offset 0..1, Color], ...] in order (the slate panel's three).
static func gradient(ci: RID, rect: Rect2, stops: Array) -> void:
	for k in range(stops.size() - 1):
		var a: Array = stops[k]
		var b: Array = stops[k + 1]
		var y0 := rect.position.y + rect.size.y * float(a[0])
		var y1 := rect.position.y + rect.size.y * float(b[0])
		var pts := PackedVector2Array([Vector2(rect.position.x, y0), Vector2(rect.end.x, y0), Vector2(rect.end.x, y1), Vector2(rect.position.x, y1)])
		var cols := PackedColorArray([a[1], a[1], b[1], b[1]])
		RenderingServer.canvas_item_add_polygon(ci, pts, cols)


## The white lip along the top of `inner` (the panel's 14 %, a button's 45 %).
static func lip(ci: RID, inner: Rect2, alpha: float, px: int) -> void:
	if inner.size.y < px:
		return
	RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position, Vector2(inner.size.x, px)), Color(1, 1, 1, alpha))


## The slate panel's inside (the gradient and the lip) over `inner`, the rect inside the navy edge.
static func panel_fill(ci: RID, inner: Rect2) -> void:
	gradient(ci, inner, PANEL_STOPS)
	lip(ci, inner, PANEL_LIP, PANEL_LIP_PX)


## A button face's inside over `inner`: the role's top colour over its bottom, split at 44 %, a 45 % white lip; `held`
## adds the pressed inset shadow along the top.
static func button_fill(ci: RID, inner: Rect2, role_name: String, held: bool = false) -> void:
	var r := role(role_name)
	var split := inner.size.y * BUTTON_SPLIT
	RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position, Vector2(inner.size.x, split)), r["top"])
	RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position + Vector2(0, split), Vector2(inner.size.x, inner.size.y - split)), r["bottom"])
	if held:
		RenderingServer.canvas_item_add_rect(ci, Rect2(inner.position, Vector2(inner.size.x, minf(PRESS_INSET_PX, inner.size.y))), PRESS_INSET)
	else:
		lip(ci, inner, BUTTON_LIP, BUTTON_LIP_PX)


## The black info plate over `rect`: 56 % black with a 2 px white 8 % inset, no edge, no base.
static func plate(ci: RID, rect: Rect2, radius: int = RADIUS) -> void:
	flat(PLATE, radius).draw(ci, rect)
	var px := float(PLATE_INSET_PX)
	RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position, Vector2(rect.size.x, px)), PLATE_INSET)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(rect.position.x, rect.end.y - px), Vector2(rect.size.x, px)), PLATE_INSET)
	RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position, Vector2(px, rect.size.y)), PLATE_INSET)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(rect.end.x - px, rect.position.y), Vector2(px, rect.size.y)), PLATE_INSET)


# --- pass 123 (lane KIT2): the pieces the remaining Royale screens share ------------------------------------------------
## The docked bottom tab bar (the mock 5_Main_menu; ui/wanted/WTabBar.gd): a band DOCK_BAR_H tall at the foot (above the
## phone's gesture bar, W.safe_bottom) in DOCK_BAR_TOP -> DOCK_BAR_BOTTOM under a 4 px navy top edge and a 10 % white
## lip; five tabs DOCK_SIDE in from either side, DOCK_GAP apart, DOCK_TAB_H tall, the open one DOCK_TAB_H_ACTIVE tall and
## DOCK_ACTIVE_FLEX times as wide; each the game's own icon (DOCK_ICON tall, the open one's DOCK_ICON_ACTIVE) over its
## word (pass 126: every tab's word Ultra, DOCK_WORD_PX cream, the open one's DOCK_WORD_ACTIVE_PX navy; a word too long for its tab
## shrinks to fit); a round DOCK_BADGE badge (the STORE's lock, the Upgrade's "!") hanging DOCK_BADGE_OUT off the tab's top-right
## corner.
const DOCK_BAR_H := 200
const DOCK_BAR_TOP := Color("27314a")
const DOCK_BAR_BOTTOM := Color("1a2238")
const DOCK_BAR_EDGE := 4
const DOCK_BAR_LIP := 0.1
const DOCK_TAB_H := 176
const DOCK_TAB_H_ACTIVE := 224
const DOCK_ACTIVE_FLEX := 1.4
const DOCK_SIDE := 24
const DOCK_GAP := 10
const DOCK_ICON := 84
const DOCK_ICON_ACTIVE := 104
## the HEROES tab's icon: the played hero's round badge DOCK_PORTRAIT px across in a DOCK_PORTRAIT_RING px navy ring
const DOCK_PORTRAIT := 80
const DOCK_PORTRAIT_RING := 4
const DOCK_WORD_PX := 22
const DOCK_WORD_ACTIVE_PX := 28
const DOCK_BADGE := 46
const DOCK_BADGE_RING := 4
const DOCK_BADGE_OUT := Vector2(12, 16)
const DOCK_BADGE_FILL := Color("2f3a50")
## Pass 126 (lane UI): the scroll thumb (ui/wanted/WScrollThumb.gd): its track's width and how dark, the thumb inside it (never
## shorter than SCROLL_THUMB_MIN), its shaded side, the grip notches' spacing, and the room for the arrow under the track.
const SCROLL_THUMB_W := 20.0
const SCROLL_THUMB_INSET := 2.0
const SCROLL_THUMB_MIN := 72.0
const SCROLL_THUMB_LOW := Color("d9b47a")
const SCROLL_GRIP_GAP := 7.0
const SCROLL_TRACK_ALPHA := 0.8
const SCROLL_ARROW_H := 22.0
## A refused tap on a locked tab: it shakes sideways DOCK_SHAKE_PX and settles in DOCK_SHAKE_S (the Stages' closed card's).
const DOCK_SHAKE_PX := 14.0
const DOCK_SHAKE_S := 0.32
## The menu header (the mocks 5_Upgrade, 10_Collection, 10_Settings): the back square HEADER_BACK px at HEADER_POS, a slate
## button on its base; the screen's name HEADER_TITLE_PX Ultra in cream at HEADER_TITLE_X, HEADER_TITLE_Y (shrunk to fit
## the room to the wallet, never under HEADER_TITLE_MIN); whatever sits top-right HEADER_RIGHT_Y down, HEADER_POS.x in.
const HEADER_POS := Vector2(40, 56)
const HEADER_BACK := 96
const HEADER_BACK_PX := 60
const HEADER_TITLE_PX := 64
const HEADER_TITLE_X := 160
const HEADER_TITLE_Y := 70
const HEADER_TITLE_MIN := 36
const HEADER_RIGHT_Y := 68
## The wallet: a black plate WALLET_H tall, WALLET_PAD (left, right) inside, the coin and the number WALLET_GAP apart, the
## number white Ultra at WALLET_SCALE of the Wanted plate's size (44 -> 34) with a soft drop (WALLET_DROP px, 60 % black).
const WALLET_H := 72
const WALLET_PAD := Vector2(14, 20)
const WALLET_GAP := 10
const WALLET_SCALE := 34.0 / 44.0
const WALLET_DROP := 2
const WALLET_DROP_COLOR := Color(0, 0, 0, 0.6)
## The black info pill (run summaries, the trait, "◷ 7:10 to the boss", "01:01 · STAGE 1"): PILL_H tall, PILL_PAD at
## either side, PILL_RADIUS corners, Rubik 500 PILL_PX white (a bold part 700), pieces PILL_GAP apart.
const PILL_H := 48
const PILL_PX := 26
const PILL_PAD := 16
const PILL_RADIUS := 6
const PILL_GAP := 8
## A price button (the mocks 8_Shop_24_gold, 5_Upgrade): PRICE_H tall, PRICE_PX type, the coin PRICE_COIN; short of gold,
## the locked grey with its label in LOCKED_TEXT and "n short" (SHORT_PX Rubik 700 in red) SHORT_GAP before it.
const PRICE_H := 64
const PRICE_PX := 28
const PRICE_COIN := 28.0
const LOCKED_TEXT := Color("d2d7e0")
## Pass 124 (Garry: "the grayed button with red text for coins amount"): the price on a button the purse can't pay.
const SHORT_INK := Color("ff5a4a")
const SHORT_PX := 22
const SHORT_GAP := 16
## The modal shell (WConfirm, the mocks 10_Confirm / 10_Consent / 10_Survey / 5_Hero_details): MODAL_W wide (R.MODAL_W),
## MODAL_PAD inside its edge, the star line MODAL_STAR_PX Ultra tracked MODAL_STAR_EM, the title MODAL_TITLE_PX cream (Garry:
## "White header"), the body MODAL_BODY_PX Rubik 500 white at MODAL_BODY_LH, MODAL_GAP between them, the buttons
## MODAL_BUTTON_H tall (MODAL_BUTTON_PX type) MODAL_BUTTON_GAP apart on the card's foot, the card at least MODAL_MIN_H
## tall; its top MODAL_TOP_AT of the room above and below it (MODAL_TOP_AT_TALL for a card taller than MODAL_TALL).
const MODAL_PAD := Vector2(36, 30)
const MODAL_STAR_PX := 30
const MODAL_STAR_EM := 0.3
const MODAL_TITLE_PX := 72
const MODAL_BODY_PX := 28
const MODAL_BODY_LH := 1.35
const MODAL_GAP := 22
const MODAL_BUTTON_H := 106
const MODAL_BUTTON_PX := 38
const MODAL_BUTTON_GAP := 24
const MODAL_MIN_H := 520
const MODAL_TOP_AT := 0.4
const MODAL_TOP_AT_TALL := 0.5
const MODAL_TALL := 900.0
const MODAL_LINK_PX := 20
## The solid board under a page (Garry, the Collection's item page: "Make it sit on a more solid background, not just
## hover in the air"): the slate panel as one sheet, with CELL cells inside it (a level, a mutation column) in place of
## the mock's see-through black; CELL_EDGE px navy, corners RADIUS, no base.
const CELL := Color("1b2339")
const CELL_EDGE := 3
