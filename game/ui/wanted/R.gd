## "Royale, refined" (design_handoff_88fits_royale, Claude Design, 2026-11-02; the lead's read in
## docs/ui_review/royale_assessment.md; Garry's build brief of the same day): the second theme's tokens and the helpers
## the Wanted components share when W.royale() is true (Settings.ui_theme "royale"; Wanted is the default and stays
## pixel-identical while the switch is off). Navy on every edge, outline and base; slate panels on a hard navy base;
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
	"blue": {"top": Color("79b3ff"), "bottom": Color("3b7fe0"), "base": Color("173f8a"), "text": Color("fff6dc")},
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
## The coin: a radial FFEAA6 -> F3BD3A -> B07612 in a 3 px navy ring (WCoin draws it; the stops live here).
const COIN_LIGHT := Color("ffeaa6")
const COIN_MID := Color("f3bd3a")
const COIN_DARK := Color("b07612")
const COIN_RING := 3
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
const TAG_EDGE := 3
const TAG_PX := 18
## The level plaque hanging off an item frame's bottom centre: blue, a navy edge, "LV n" (a plain "n" at 80 px).
const PLAQUE_TOP := Color("5a9cf5")
const PLAQUE_BOTTOM := Color("2a62c4")
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
const PLAQUE_TEXT := Color("ffffff")
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


## The Wanted kit's text colours on paper, as Royale sets them on slate: W.text maps `color` through this while
## W.royale(); a colour not in the table is kept as given (a screen's own colour survives).
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
