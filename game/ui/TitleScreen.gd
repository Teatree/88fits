## Title (Wanted 01/02), with play setup merged in: the gold plate, "★ WANTED ★ / OUTLAW / SURVIVORS" (pass 115; it was
## "88fits / DRAG · DODGE · SURVIVE"), the
## hero full-body (art/ui/wanted/hero_<id>.png, since pass 68 the played look's own `title` when it has one; a striped
## slot until painted) between two arrow squares, swipe or tap
## to change, a dot per hero under it, the hero plaque (name, italic line, the trait's numbers and the favourite's plate:
## his weapon, or the line or passive he favours, Ironwood's Brawn since pass 47, each plate in its colour), PLAY, the
## map and its best run in one line (a tap changes the map when there are several). Heroes still to unlock ride the
## same carousel after the open ones: a dark silhouette with a padlock, a half-aged dot, what unlocks them and how far
## along that is, and PLAY reading LOCKED. (The developer menu can add the hidden heroes, locked, to preview the look.) Then Upgrade · Collection ·
## Settings, Upgrade in turquoise (pass 46: brass is kept for buying) with a breathing glow and a mark when a rank is
## affordable (pass 44: the Mirror's name said nothing about what it was for). No version label; the developer menu
## lives in Settings (hold the version label for 2 s), and the player's own debug mode (ten taps on the hints switch)
## puts an ARENA button top right. The top block hangs from the top edge, the plaque and the buttons from the bottom;
## the hero keeps the middle.
## Pass 69 (Garry: heroes to unlock and to buy): the carousel holds every hero not hidden, owned first, then those on
## sale, then the locked ones (Registry.heroes_for_drawer). A hero not owned runs in under a full black mask; his plaque
## reads Unknown, "?" for his stats, his start weapon and favourite as black silhouettes with a "?" (WPlate.mystery), and
## PLAY is LOCKED. Locked (his quest not done): what unlocks him written over the plaque (the Requirement card, with how
## far along it is) and the padlock on his chest. On sale: a BUY button over him with his price; a tap asks (WConfirm),
## spends the gold (Save.buy_hero), lifts the mask (TitleStage.reveal) with a burst (WCelebrate) and he is playable. Left
## of the plaque the Hero Collections button (pass 70: a square as tall as the plaque, eight squares of a 3 x 3 grid)
## opens the hero drawer over the preview (WHeroDrawer: every
## hero as a badge tile, two rows); a tile selects that hero, a tap outside closes it, and while it is open the button
## is a close X.
## Pass 52, two looks (Settings.menu_style, chosen in Settings under the player's debug mode): "painted" as above, or
## "live": the level itself behind the UI instead of the still, and in place of the cut-out the hero as a run draws him,
## smaller, standing on the sand with his start weapon circling him (ui/TitleStage.gd); a locked one is a dark figure
## with the same padlock. Everything else (the plaque, PLAY, the map line, the buttons, the swipe) is the same.
extends Control

## The cut-out box: 520 × 700 inside a 4 px dashed border, 24 px under the label (the mock's box is content-box).
const HERO_SIZE := Vector2(528, 732)
## The hero row's top on a 1920 screen; a taller screen moves it down by half the extra height.
const HERO_TOP := 560.0
## Where the plaque, PLAY and the map line sit, measured up from the bottom edge (1330, 1560, 1720 on a 1920 screen).
const PLAQUE_UP := 590.0
const PLAY_UP := 360.0
## The plaque's foot sits this far above PLAY (the mock's 1497 -> 1560); the plaque grows upwards from there.
const PLAQUE_GAP := 63.0
## Pass 73 (Garry: "The size of the hero plaque in the main menu keeps changing depending on which hero you're looking
## at ... Make it so that it stays static ... The font size should be consistent for all the heroes"): one height for
## every hero in every state (owned, on sale, locked), the Hero Collections button a square of it, the width what the
## screen leaves; inside, the padding (border included) and one set of sizes: the name, the flavour (at most
## LINE_MAX lines), the trait's numbers and every label. The longest hero decides them (pass73_uipc_test fits every
## hero in every state); a hero whose words do not fit is cut at the plaque's edge rather than moving anything.
const PLAQUE_H := 200.0
const PLAQUE_PAD := Vector2(30, 19)
const NAME_PX := 52
const LINE_PX := 24
const LINE_LH := 29.0
const LINE_MAX := 2
const VALUE_PX := 30
const LABEL_PX := 18
const PLATE_PX := 84.0
## The plates' column on the right (two plates: START and FAVOURITE, the wider label's width each), and the gap
## between it and the words.
const ITEMS_W := 216.0
const ITEMS_GAP := 20.0
## The most item plates the plaque shows: the start weapon and the favourite (the hero's sheet lists any other).
const PLATES_MAX := 2
const MAP_UP := 200.0
## A finger that travels this far sideways over the hero changes it.
const SWIPE := 90.0
## The game's big word in the slab (pass 115: OUTLAW, 953 px wide at 190, inside the 1080 px canvas with its 10 px
## shadow; "88fits" was 210).
const LOGO_PX := 190
## The trait's numbers under short names (the rest fall back to TextGen's stat names: ATTACK DAMAGE, AREA OF EFFECT,
## COIN GAIN since pass 45, so the words live in one place).
const SHORT := {"max_hp": "HP", "damage_reduction": "DEFENCE", "move_speed": "SPEED", "magnet": "REACH",
	"cooldown": "COOLDOWN", "luck": "LUCK", "regen": "REGEN", "regen_delay": "REGEN DELAY", "revives": "REVIVES",
	"projectile_speed": "SHOT SPEED", "xp_gain": "XP", "crit_chance": "CRIT", "amount": "PROJECTILES"}
## A unit after a number whose stat has none of its own (regen is health a second: "+1.2/s" over REGEN).
const UNIT := {"regen": "/s"}
## The breathing halo behind Upgrade: the button's own turquoise (pass 46; it was brass with the button).
const GLOW := W.TURQUOISE
## Stats a hero is better off with less of: a negative on these is a buff, and stays sage.
const LOWER_BETTER := ["cooldown", "regen_delay", "shield_delay"]

var _heroes: Array = []
var _index := 0
var _maps: Array = []
var _map_id := ""
var _hero_row: Control
var _art_host: Control
var _art: WPlaceholder
var _dots: Control
var _plaque: PanelContainer
var _name: WText
var _line: WText
## The item plates (START, FAVOURITE) on the plaque's right; the trait's numbers flow under the flavour (pass 73).
var _stats: HBoxContainer
var _trait: HFlowContainer
## pass 111 (lane SKINS): the plaque's "Details ›" (reads "Looks · Details ›" for a hero with looks)
var _details: WText
var _play: WButton
var _map_tap: WTap
var _map_line: WText
var _lower: Array = []
## The hero's sheet (pass 61): the CV a tap on the plaque opens (ui/wanted/WHeroSheet.gd, no class_name).
const WHeroSheetScript := preload("res://ui/wanted/WHeroSheet.gd")
var _sheet: Control
var _swipe_id := -2   # -2 none, -1 the mouse, else a finger index
var _swipe_from := Vector2.ZERO
var _upgrade_btn: WButton
var _glow: Control
var _mark: Control
var _halo := StyleBoxFlat.new()
var _affordable := false
var _glow_t := 0.0
var _arena_btn: WButton
## The live look (pass 52): the 3D stage behind everything, the padlock over a locked hero there, and the wash, whose
## clear middle reaches down to the hero's feet (it is under the hero in this look, over the still in the other). The
## stage's script by its path: a new class_name is unknown to a headless run until the editor rescans the project.
const TitleStageScript := preload("res://ui/TitleStage.gd")
## The play-data card (pass 59) and how long after the title comes in it asks.
const WConsentScript := preload("res://ui/wanted/WConsent.gd")
## The Stages menu (pass 87, lane SUI): PLAY opens it once the map's first stage is beaten.
const StagesScreenScript := preload("res://ui/StagesScreen.gd")
const CONSENT_DELAY := 0.8
var _live := false
var _stage: TitleStageScript
var _lock: Control
var _wash_rect: TextureRect
var _wash_grad: Gradient
## Pass 69: the gold plate (a purchase changes it on the title now), the Hero Collections button left of the plaque and
## its glyph, the drawer it opens, the Requirement card over the plaque of a locked hero, the BUY button over a hero on
## sale (in a column with the shortfall under it when the purse is short).
const WHeroDrawerScript := preload("res://ui/wanted/WHeroDrawer.gd")
const BOX_BTN := 104.0
const BOX_GAP := 14.0
const BOX_LEFT := 36.0
var _gold_plate: PanelContainer
var _drawer_btn: WTap
var _drawer_glyph: Control
var _drawer: Control
var _req: PanelContainer
var _req_text: WText
var _buy_col: VBoxContainer
var _buy: WButton
var _buy_note: WText
var _buy_note_box: PanelContainer
## The title's top block (the name stack): the drawer stays under it.
var _top_stack: Control
## A hero not owned on the painted title: his cut-out's fill, a full black (pass 69).
const MASK := Color(0.03, 0.024, 0.02, 1.0)


## Back on the title leaves the game, as it always did (quit_on_go_back is off so a run can ignore the gesture).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# the hero's sheet up (pass 61): back closes it, the game stays
		if sheet_open():
			# pass 111 (lane SKINS): a look's question on the sheet goes first
			if not WConfirm.dismiss(_sheet):
				_sheet.call("close")
			return
		# pass 69: the buy question, then the hero drawer, before the game goes
		if WConfirm.dismiss(self):
			return
		if drawer_open():
			close_drawer()
			return
		Save.flush()
		get_tree().quit()


func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the look (pass 52): the painted cut-out over the still of the desert, or the level itself with the hero standing in it
	_live = str(Settings.menu_style) == "live"
	if not _live:
		ScreenBase.add_backdrop(self)
		# a live title's world kept for the way back from a menu is not wanted any more
		TitleStageScript.forget()
	_wash_rect = _wash()
	add_child(_wash_rect)
	# quests a save's totals already satisfy (pass 44 added many) complete here, quietly, instead of all at once five
	# seconds into the next run; since pass 76 they are not listed again as "Unlocked this run" (only a run's own checks
	# fill QuestTracker.just_completed)
	QuestTracker.check_all(false)
	# gold cannot change on the title: the Upgrade mark is decided once
	_affordable = _rank_affordable()
	_heroes = _roster()
	var last := Registry.playable_character(str(Save.data.get("last_character", Save.DEFAULT_HERO)))
	# pass 69: a hero to be bought is not the one the title opens on (the first owned one is: the carousel lists them first)
	if last and _is_locked(last):
		last = null
	_index = maxi(_heroes.find(last), 0)
	# pass 101 (lane LOOKS): no run is going, so the last run's pinned strips are let go (LookArt keeps the most recent
	# few); the live title keeps the strip of the hero it opens on (the painted title draws his cut-out, no strip)
	var keep: Array = []
	if _live and not _heroes.is_empty():
		keep.append(Registry.played_look(_heroes[_index]).strip_path())
	LookArt.pin_only(keep)
	_maps =Registry.sorted_maps().filter(func(m: MapDef) -> bool: return Registry.is_unlocked("map", m.id))
	_map_id = str(Save.data.get("last_map", ""))
	if _maps.filter(func(m: MapDef) -> bool: return m.id == _map_id).is_empty():
		_map_id = _maps[0].id if not _maps.is_empty() else "red_canyon"
	if _live:
		# behind everything: the map the line under PLAY names, laid out from the title's own roll
		_stage = TitleStageScript.new()
		_stage.name = "TitleStage"
		_stage.map_id = _map_id
		add_child(_stage)
		move_child(_stage, 0)
	# the gold plate, top-left
	var gold := WMenuHeader.gold_plate(Save.gold(), 44, 40.0, 5, 4)
	gold.position = Vector2(36, 44 + W.safe_top())
	add_child(gold)
	_gold_plate = gold
	# the debug arena (pass 44: the player's debug mode, ten taps on the hints switch), top right
	_arena_btn = WButton.make(["ARENA"], 24, WButton.SECONDARY, 4, 4, 10.0, 18.0)
	_arena_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_arena_btn.offset_left = -36 - 180
	_arena_btn.offset_right = -36
	_arena_btn.offset_top = 44 + W.safe_top()
	_arena_btn.offset_bottom = 44 + W.safe_top() + 60
	_arena_btn.visible = Settings.debug_mode and not Settings.is_prod()
	_arena_btn.name = "ArenaButton"
	_arena_btn.pressed.connect(func():
		Run.arena_next = true
		_leave_for_a_run()
		UiFx.go(get_tree(), "res://game/Game.tscn"))
	add_child(_arena_btn)
	# the name stack
	var stack := VBoxContainer.new()
	_top_stack = stack
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stack.offset_top = 150 + W.safe_top()
	add_child(stack)
	var wanted := WStarLine.make("Wanted", 26, W.INK, 0.4)
	wanted.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(wanted)
	# pass 115 (Garry: "we just write 'Outlaw' with big fat text and the 'Drag Dodge Survive' is replaced with simply
	# 'Survivors'"): OUTLAW in the slab at LOGO_PX (it is wider than "88fits" was, so it fits the 1080 px with room for its
	# shadow) in the same 199.5 px line box, so nothing under it moves; SURVIVORS where the tagline was, in its style
	var logo := W.slab_text(W.GAME_WORD.to_upper(), LOGO_PX, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 199.5)
	logo.name = "Logo"
	logo.shadow = 10
	logo.shadow_color = W.BRASS
	stack.add_child(logo)
	var tag := W.label(W.GAME_LINE, 30, W.INK, 0.3)
	tag.name = "Tagline"
	tag.align = HORIZONTAL_ALIGNMENT_CENTER
	tag.custom_minimum_size.y = 6.0 + 36.0
	tag.valign = VERTICAL_ALIGNMENT_BOTTOM
	stack.add_child(tag)
	_build_hero_row()
	_build_lower()
	_build_unknown()
	_show_hero(0)
	get_viewport().size_changed.connect(_place)
	_place()
	_enter()
	Audio.play_music(["mu_title"], 1)
	# the play-data card (pass 59): once, the first time a build that can send starts, after the title has come in
	if Analytics.consent_needed():
		get_tree().create_timer(CONSENT_DELAY).timeout.connect(func():
			if is_inside_tree() and Analytics.consent_needed() and get_node_or_null("Consent") == null:
				WConsentScript.open(self))


## The title wash: warm at the top, clear through the middle where the hero stands, paper again at the foot. In the live
## look (pass 52) the hero stands in the scene under it, so its clear middle runs on down past his feet and turns to
## paper only between them and the plaque (_live_wash sets the stops from the layout).
func _wash() -> TextureRect:
	var g := Gradient.new()
	if _live:
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.68, 0.72, 1.0])
		g.colors = PackedColorArray([Color8(233, 201, 160, 242), Color8(233, 201, 160, 102), Color8(243, 230, 200, 0),
			Color8(243, 230, 200, 0), Color8(243, 230, 200, 205), Color8(243, 230, 200, 235)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.78, 1.0])
		g.colors = PackedColorArray([Color8(233, 201, 160, 242), Color8(233, 201, 160, 102), Color8(243, 230, 200, 0),
			Color8(243, 230, 200, 178), Color8(243, 230, 200, 235)])
	_wash_grad = g
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 256
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_hero_row() -> void:
	_hero_row = Control.new()
	_hero_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_row)
	_art_host = Control.new()
	_art_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_host.size = HERO_SIZE
	_hero_row.add_child(_art_host)
	for side in [-1, 1]:
		var a := WTap.new()
		var b := W.box(W.PAPER, 4, 5).pad(4, 4, 4, 10)
		a.box = b
		var t := W.slab_text("‹" if side < 0 else "›", 48, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 48.0)
		t.custom_minimum_size = Vector2(72, 72)
		t.valign = VERTICAL_ALIGNMENT_CENTER
		a.add_child(t)
		a.size = Vector2(80, 86)
		a.set_meta("side", side)
		a.pressed.connect(func(): _step(side))
		a.name = "Prev" if side < 0 else "Next"
		_hero_row.add_child(a)
	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	add_child(_dots)


## The plaque, PLAY, the map line and the three menu buttons. The plaque is a tap (pass 61, Garry: "make the character
## name plaque clickable"): it opens the hero's sheet; a sideways swipe across it still changes the hero (_input).
func _build_lower() -> void:
	var tap := WTap.new()
	tap.name = "Plaque"
	tap.box = W.box(W.PAPER, 5, 8).pad(PLAQUE_PAD.x, PLAQUE_PAD.y, PLAQUE_PAD.x, PLAQUE_PAD.y)
	tap.pressed.connect(open_sheet)
	_plaque = tap
	add_child(_plaque)
	# pass 69: the Hero Collections button left of the plaque (a close X while the drawer is open); pass 70: a square as
	# tall as the plaque, with the plaque's shadow, its glyph a grid of squares (_draw_drawer_glyph)
	_drawer_btn = WTap.new()
	_drawer_btn.name = "HeroesButton"
	_drawer_btn.box = W.box(W.PAPER, 5, 8)
	_drawer_btn.custom_minimum_size = Vector2(BOX_BTN, BOX_BTN)
	_drawer_btn.size = Vector2(BOX_BTN, BOX_BTN)
	_drawer_glyph = Control.new()
	_drawer_glyph.name = "Glyph"
	_drawer_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_glyph.draw.connect(_draw_drawer_glyph)
	_drawer_btn.add_child(_drawer_glyph)
	_drawer_btn.pressed.connect(toggle_drawer)
	add_child(_drawer_btn)
	# pass 73: the insides sit in a plain Control, so no hero's words can make the plaque grow; the name at the top left,
	# the flavour under it, the trait's numbers along the foot (a second row when they need it), the item plates top
	# right and "Details ›" (what a tap on the plaque does, pass 61) in the bottom-right corner
	var body := Control.new()
	body.name = "Body"
	body.clip_contents = true
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plaque.add_child(body)
	var h := HBoxContainer.new()
	h.name = "Columns"
	h.add_theme_constant_override("separation", int(ITEMS_GAP))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(h)
	var left := VBoxContainer.new()
	left.name = "Words"
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	_name = W.slab_text("", NAME_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(NAME_PX))
	_name.name = "Name"
	left.add_child(_name)
	_line = W.serif_text("", LINE_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, LINE_LH, true)
	_line.name = "Flavour"
	_line.max_lines = LINE_MAX
	left.add_child(_line)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(gap)
	_trait = HFlowContainer.new()
	_trait.name = "Trait"
	_trait.add_theme_constant_override("h_separation", 22)
	_trait.add_theme_constant_override("v_separation", 6)
	_trait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_trait)
	var right := VBoxContainer.new()
	right.name = "Items"
	right.add_theme_constant_override("separation", 0)
	right.custom_minimum_size = Vector2(ITEMS_W, 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	_stats = HBoxContainer.new()
	_stats.name = "Plates"
	_stats.add_theme_constant_override("separation", 12)
	_stats.alignment = BoxContainer.ALIGNMENT_END
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_stats)
	var gap2 := Control.new()
	gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(gap2)
	var more := W.label("Details ›", LABEL_PX, W.BRASS_DARK, 0.15)
	more.name = "Details"
	more.align = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(more)
	_details = more
	_play = WButton.make(["PLAY"], 84, WButton.PRIMARY, 6, 10, 22.0, 22.0, 84.0)
	_play.pressed.connect(_on_play)
	add_child(_play)
	_map_tap = WTap.new()
	var clear := W.box(Color(0, 0, 0, 0), 0, 0)
	_map_tap.box = clear
	_map_tap.box_down = clear
	_map_line = W.serif_text("", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_map_tap.add_child(_map_line)
	_map_tap.pressed.connect(_next_map)
	add_child(_map_tap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 60
	row.offset_right = -60
	row.offset_bottom = -60
	row.offset_top = -60 - 91
	# Upgrade (the Mirror until pass 44) is the one button in colour (turquoise since pass 46: brass is for buying), with
	# a pulsing glow and a mark when a rank can be bought: it is where the gold goes, and the row should say so. The glow
	# sits under the row and the mark over it (pass 45: both drawn under it, the mark showed as a crescent)
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_halo.draw_center = false
	_halo.set_border_width_all(0)
	_halo.set_corner_radius_all(14)
	_halo.shadow_offset = Vector2.ZERO
	add_child(row)
	_mark = Control.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(_draw_mark)
	add_child(_mark)
	for pair in [["Upgrade", "res://ui/HomesteadScreen.tscn"], ["Collection", "res://ui/CollectionScreen.tscn"], ["Settings", "res://ui/SettingsScreen.tscn"]]:
		var primary: bool = pair[0] == "Upgrade"
		var b := WButton.make([pair[0]], 30, WButton.UPGRADE if primary else WButton.SECONDARY, 5, 6, 20.0, 0.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path: String = pair[1]
		b.pressed.connect(func():
			# the live look keeps its built world for the way back (pass 52)
			if _stage:
				_stage.keep_on_exit = true
			UiFx.go(get_tree(), path))
		row.add_child(b)
		if primary:
			_upgrade_btn = b
	_lower = [_plaque, _drawer_btn, _play, _map_tap, row]
	_refresh_map()


## Everything that depends on the screen's height: the lower block hangs from the bottom edge, the hero row takes the
## middle and shrinks when a short screen has no room for it.
func _place() -> void:
	var vp := get_viewport_rect().size
	# pass 69: the Hero Collections button takes the plaque's left end; the plaque keeps its right edge (PLAY's)
	# pass 70: the button is a square as tall as the plaque; pass 73: both one size whatever the hero (PLAQUE_H)
	var btn_side := drawer_side(vp)
	var plaque_x := BOX_LEFT + btn_side + BOX_GAP
	var plaque_h := btn_side
	_plaque.size = Vector2(vp.x - 60.0 - plaque_x, plaque_h)
	var plaque_top := vp.y - PLAY_UP - PLAQUE_GAP - plaque_h
	_plaque.position = Vector2(plaque_x, plaque_top)
	_drawer_btn.custom_minimum_size = Vector2(btn_side, btn_side)
	_drawer_btn.size = Vector2(btn_side, btn_side)
	_drawer_btn.position = Vector2(BOX_LEFT, plaque_top + (plaque_h - btn_side) * 0.5)
	_drawer_glyph.queue_redraw()
	_play.position = Vector2(60, vp.y - PLAY_UP)
	_play.size = Vector2(vp.x - 120, 0)
	_map_tap.position = Vector2(0, vp.y - MAP_UP)
	_map_tap.size = Vector2(vp.x, 0)
	var top := HERO_TOP + W.safe_top() + (vp.y - 1920.0) * 0.5
	# the room between the title's words (440 on a 1920 screen, moved down by a camera cutout's inset: pass 73, the
	# hero's hat reached the tag line on a short screen with a cutout) and the plaque
	var room := plaque_top - 38.0 - 440.0 - W.safe_top()
	var k := clampf(room / HERO_SIZE.y, 0.5, 1.0)
	if top + HERO_SIZE.y * k > plaque_top - 38.0:
		top = plaque_top - 38.0 - HERO_SIZE.y * k
	_hero_row.position = Vector2(0, top)
	_hero_row.size = Vector2(vp.x, HERO_SIZE.y * k)
	var art_w := HERO_SIZE.x * k
	_art_host.position = Vector2((vp.x - art_w) * 0.5, 0)
	_art_host.scale = Vector2(k, k)
	for a in _hero_row.get_children():
		if a is WTap:
			var side: int = a.get_meta("side")
			var x := (vp.x - art_w) * 0.5 - 40.0 - 80.0 if side < 0 else (vp.x + art_w) * 0.5 + 40.0
			a.position = Vector2(x, (HERO_SIZE.y * k - 86.0) * 0.5)
	_dots.position = Vector2(0, top + HERO_SIZE.y * k - 12.0)
	_dots.size = Vector2(vp.x, 26)
	if _stage:
		# the live hero stands in the same box the cut-out fills (pass 52)
		_stage.frame(Rect2(_hero_row.position + _art_host.position, HERO_SIZE * k))
		_live_wash(vp.y, plaque_top)
		_place_lock()
	_place_unknown(plaque_top)


## The live look's wash stops (pass 52): clear to just under the hero's shadow, paper by a little past the plaque's top.
func _live_wash(h: float, plaque_top: float) -> void:
	if _wash_grad == null or _stage == null or h <= 0.0:
		return
	var clear_to := clampf((_stage.ground_px().y + 40.0) / h, 0.52, 0.95)
	var paper_at := clampf((plaque_top + 40.0) / h, clear_to + 0.01, 0.98)
	_wash_grad.offsets = PackedFloat32Array([0.0, 0.3, 0.5, clear_to, paper_at, 1.0])


## Every hero the carousel shows (pass 69: Registry.heroes_for_drawer, the drawer's list too): the owned ones first,
## then those on sale, then the locked ones. With the developer's preview on, the hidden heroes join the locked ones.
func _roster() -> Array:
	var out: Array = Registry.heroes_for_drawer()
	if bool(Settings.get("preview_locked_heroes")):
		var hidden: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return c.hidden)
		hidden.sort_custom(func(a, b): return a.id < b.id)
		out.append_array(hidden)
	return out


## Where the player stands with `c` (pass 69, Registry.hero_state): owned, buyable or locked; a hidden hero the
## developer previews reads as locked.
func _state(c: CharacterDef) -> String:
	var st := Registry.hero_state(c)
	return "locked" if st == "hidden" else st


## Not owned (pass 69: locked, on sale, or a previewed hidden one): the black mask, Unknown, PLAY locked.
func _is_locked(c: CharacterDef) -> bool:
	return _state(c) != "owned"


## The hero at `_index`: the cut-out (sliding in from the side the finger went), the dots, the plaque and PLAY.
func _show_hero(from_side: int) -> void:
	if _heroes.is_empty():
		return
	var c: CharacterDef = _heroes[_index]
	var locked := _is_locked(c)
	if _live:
		# the hero on the sand (pass 52): he runs in from the side the finger came from, the last one runs off; one not
		# owned under a full black mask (pass 69), the padlock on his chest while his requirement is not met
		_stage.show_hero(c, locked, from_side)
		_show_lock(_state(c) == "locked", from_side)
	else:
		_show_art(c, from_side)
	_show_plaque(c)


## The painted look's cut-out of `c`, sliding in from `from_side`: the look he is played in (pass 68,
## Registry.played_look): the look's own `title` when that file is there, else hero_<id>.png, else the striped slot. A
## hero not owned: the cut-out a black silhouette (pass 69: a full black mask), the padlock while he is locked.
func _show_art(c: CharacterDef, from_side: int) -> void:
	if _art:
		_art.queue_free()
	var who := ("the " + c.display_name) if c.id == "drifter" else c.display_name
	_art = WPlaceholder.make(Registry.played_look(c).title_path(), "%s, full-body cut-out\nfacing camera · 520 × 700" % who, HERO_SIZE)
	if _is_locked(c):
		# painted: a black silhouette; not yet painted: the striped slot, faded
		_art.silhouette = true
		(_art.material as ShaderMaterial).set_shader_parameter("fill", MASK)
		_art.modulate.a = 1.0 if _art.tex else 0.45
		if _state(c) == "locked":
			_art.add_child(_padlock())
	_art_host.add_child(_art)
	if from_side != 0:
		_art.position.x = 90.0 * from_side
		var a := _art.modulate.a
		_art.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_art, "position:x", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_art, "modulate:a", a, 0.16)


## The dots, the plaque, PLAY, the Requirement card and the BUY for `c`. Pass 69 (Garry: "the name is simply 'unknown',
## stats are unknown, weapon is a black silhouette of the one with a question mark and so is the fav item"): a hero not
## owned reads Unknown, a "?" for each of his numbers, his start weapon and favourite as mystery plates.
func _show_plaque(c: CharacterDef) -> void:
	var locked := _is_locked(c)
	_dots.queue_redraw()
	_name.text = ("The " + c.display_name) if c.id == "drifter" else c.display_name
	# out of the rows at once: a queued plate still counts in its row's size
	for row: Control in [_stats, _trait]:
		for s in row.get_children():
			row.remove_child(s)
			s.queue_free()
	_line.visible = not locked
	if locked:
		_name.text = "Unknown"
		_line.text = ""
		for st in _stats_of(c):
			_trait.add_child(_stat("?", "???", true, true))
		var start0 := Registry.start_weapon_for(c)
		if start0:
			_stats.add_child(_item_plate(start0, "Start", 1, true))
		var fav0 := _favourite_of(c)
		if fav0 and fav0 != start0:
			_stats.add_child(_item_plate(fav0, "Favourite", 1, true))
	else:
		_line.font = W.serif(400, true)
		_line.color = W.INK_SOFT
		_line.text = c.flavour
		for st in _stats_of(c):
			_trait.add_child(_stat(st[0], st[1], bool(st[2])))
		# the hero's items as plates: the weapon he lands with (pass 47b, Garry: Ironwood's Spear did not show), the
		# favourite, then any other weapon only this hero can find while there is room (PLATES_MAX, pass 73)
		var start := Registry.start_weapon_for(c)
		if start:
			_stats.add_child(_item_plate(start, "Start", start_level(c, start)))
		var fav := _favourite_of(c)
		if fav and fav != start:
			_stats.add_child(_item_plate(fav, "Favourite", start_level(c, fav)))
		for w: WeaponDef in _own_weapons(c):
			if w != start and _stats.get_child_count() < PLATES_MAX:
				_stats.add_child(_item_plate(w, "Special", 1))
	_play.locked = locked
	_play.set_parts(["LOCKED" if locked else "PLAY"])
	if not locked:
		Save.data["last_character"] = c.id
	# pass 111 (lane SKINS): a hero with looks to wear or earn says so where the sheet is opened
	if _details:
		_details.text = ("Looks · Details ›" if not locked and not Registry.skins_of(c).is_empty() else "Details ›").to_upper()
	_show_unknown(c)


## The hero's favourite: his weapon, or when he has none, the line or passive he favours (pass 46: Ironwood's Cake; pass
## 47: his Brawn, a line on its light yellow plate).
func _favourite_of(c: CharacterDef) -> ContentDef:
	var w: WeaponDef = Registry.weapon(c.favourite_weapon) if c.favourite_weapon != "" else null
	if w:
		return w
	return Registry.passive(c.favourite_passive) if c.favourite_passive != "" else null


## The level a hero has an item at when he finds it or lands with it (pass 48: the plaque's plates take its colour): a
## favourite at its bonus level (the Drifter's Peashooter and Calavera's Skull Rain 2, Ironwood's Brawn 2), else 1.
static func start_level(c: CharacterDef, def: ContentDef) -> int:
	if c == null or def == null:
		return 1
	if def is WeaponDef and def.id == c.favourite_weapon:
		if str(c.favourite_bonus.get("type", "")) == "level":
			return clampi(int(c.favourite_bonus.get("value", 1)), 1, maxi((def as WeaponDef).max_level, 1))
		return 1
	if def is PassiveDef and def.id == c.favourite_passive:
		var mx := maxi((def as PassiveDef).max_level, 1)
		match str(c.favourite_passive_bonus.get("type", "")):
			"max":
				return mx
			"level":
				return clampi(int(c.favourite_passive_bonus.get("value", 1)), 1, mx)
	return 1


## An item on the plaque: its plate (PLATE_PX) in the colour of the level he has it at and a tracked word under it
## (START, FAVOURITE, SPECIAL) at the plaque's one label size (pass 73: 14 px before, too small to read on the phone).
func _item_plate(def: ContentDef, word: String, level: int = 1, mystery: bool = false) -> VBoxContainer:
	var col := _column()
	col.name = word
	col.set_meta("def", def)
	col.set_meta("level", level)
	var p := WPlate.new().for_def(def, PLATE_PX, false, level)
	p.icon_frac = 68.0 / 92.0
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# pass 69: a hero not owned yet shows only the item's black shape and a "?"
	p.mystery = mystery
	col.add_child(p)
	var l := W.label(word, LABEL_PX, W.INK_SOFT, 0.1)
	l.align = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return col


## The weapons only this hero can find (`WeaponDef.hero`: the Drifter's Revolver, Astro's Gravity Gun).
func _own_weapons(c: CharacterDef) -> Array:
	var only: Array = Registry.weapons.values().filter(func(w: WeaponDef) -> bool:
		return w.hero == c.id and not w.is_evolution and not Registry.is_hidden(w))
	only.sort_custom(func(a, b): return a.id < b.id)
	return only


## Up to three of the trait's numbers: its effects on the player, then the heal on every level. Each is [value, label,
## good]: a debuff (a negative, or a positive on a lower-is-better stat) is not good and reads in dark red (pass 45).
## Pass 61: a hero whose trait grows with his level shows what one level gives ("+1%" over "CRIT / LV").
func _stats_of(c: CharacterDef) -> Array:
	var out: Array = []
	if not c.level_trait.is_empty():
		for e in c.level_trait:
			if e is Effect:
				var x: Effect = e
				var up: bool = (x.value >= 0.0) != (x.stat in LOWER_BETTER)
				out.append([TextGen.hero_step(x) + str(UNIT.get(x.stat, "")), str(SHORT.get(x.stat, TextGen.stat_name(x.stat).to_upper())) + " / LV", up])
		if c.level_heal > 0.0:
			out.append(["%d%%" % int(round(c.level_heal * 100.0)), "HEAL / LV", true])
		return out.slice(0, 3)
	for e in c.trait_effects:
		if e is Effect and (e.target == "player" or e.target == ""):
			var good: bool = e.op == "set" or ((e.value >= 0.0) != (e.stat in LOWER_BETTER))
			out.append([TextGen.describe_effect(e, false) + str(UNIT.get(e.stat, "")), SHORT.get(e.stat, TextGen.stat_name(e.stat).to_upper()), good])
	if c.level_heal > 0.0:
		out.append(["%d%%" % int(round(c.level_heal * 100.0)), "HEAL / LV", true])
	return out.slice(0, 3)


func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## One of the trait's numbers on the plaque: sage slab (dark red for a debuff) and its tracked label beside it, on one
## baseline (pass 73: the numbers flow along the plaque's foot; they stood over their labels in a row that pushed the
## plaque wider and taller).
func _stat(value: String, what: String, good: bool = true, unknown: bool = false) -> HBoxContainer:
	var v := HBoxContainer.new()
	v.name = "Stat"
	v.add_theme_constant_override("separation", 7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := W.slab_text(value, VALUE_PX, W.INK_SOFT if unknown else (W.SAGE if good else W.BAD_DARK), HORIZONTAL_ALIGNMENT_LEFT, float(VALUE_PX))
	n.name = "Value"
	v.add_child(n)
	var l := W.label(what, LABEL_PX, W.INK_SOFT, 0.1)
	l.name = "Label"
	# the label's line box at the foot of the number's: their baselines meet (Alfa Slab's at 25.5 of 30, Bitter's at
	# 17 of 22)
	l.custom_minimum_size.y = float(VALUE_PX)
	l.valign = VERTICAL_ALIGNMENT_BOTTOM
	v.add_child(l)
	return v


## The live look's padlock (pass 52): over a locked hero's chest as on the cut-out, showing once he has run in.
func _show_lock(locked: bool, from_side: int) -> void:
	if _lock:
		_lock.queue_free()
		_lock = null
	if not locked:
		return
	_lock = _padlock()
	_lock.name = "Padlock"
	_art_host.add_child(_lock)
	_place_lock()
	if from_side != 0:
		_lock.modulate.a = 0.0
		var tw := _lock.create_tween()
		tw.tween_interval(TitleStageScript.SWAP_TIME * 0.8)
		tw.tween_property(_lock, "modulate:a", 1.0, 0.15)


## The padlock on the live hero's chest, in the box's own (unscaled) units, three quarters of the cut-out's size since the
## live figure is smaller.
func _place_lock() -> void:
	if _lock == null or _stage == null:
		return
	var k: float = _art_host.scale.y if _art_host.scale.y > 0.0 else 1.0
	var origin := _hero_row.position + _art_host.position
	var fig: Rect2 = _stage.figure_rect()
	var s := 0.75
	var chest := (fig.position.y + fig.size.y * 0.32 - origin.y) / k
	_lock.scale = Vector2(s, s)
	_lock.position = Vector2(HERO_SIZE.x * 0.5 - 60.0 * s, chest - 80.0 * s)


## A padlock over a locked hero's chest: an ink shackle over a brass body with a keyhole.
func _padlock() -> Control:
	var l := Control.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(HERO_SIZE.x * 0.5 - 60.0, HERO_SIZE.y * 0.36)
	l.size = Vector2(120, 140)
	l.draw.connect(func():
		var c := Vector2(60, 0)
		l.draw_arc(c + Vector2(0, 58), 34.0, PI, TAU, 32, W.INK, 26.0, true)
		l.draw_arc(c + Vector2(0, 58), 34.0, PI, TAU, 32, W.AGED, 12.0, true)
		var body := Rect2(Vector2(4, 56), Vector2(112, 84))
		var sb := StyleBoxFlat.new()
		sb.bg_color = W.BRASS
		sb.border_color = W.INK
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		l.draw_style_box(sb, body)
		l.draw_circle(c + Vector2(0, 88), 11.0, W.INK, true, -1.0, true)
		l.draw_rect(Rect2(c + Vector2(-5, 92), Vector2(10, 26)), W.INK))
	return l


## A dot per hero: brass for the one shown, paper for the rest, aged at half for a locked one.
func _draw_dots() -> void:
	var n := _heroes.size()
	if n < 2:
		return
	var w := n * 26.0 + (n - 1) * 14.0
	var x := (_dots.size.x - w) * 0.5 + 13.0
	for i in n:
		var c: CharacterDef = _heroes[i]
		var locked := _is_locked(c)
		var fill := W.BRASS if i == _index else (Color(W.AGED, 0.5) if locked else W.PAPER)
		var ink := Color(W.INK, 0.5) if locked and i != _index else W.INK
		_dots.draw_circle(Vector2(x, 13), 13.0, ink, true, -1.0, true)
		_dots.draw_circle(Vector2(x, 13), 10.0, fill, true, -1.0, true)
		x += 40.0


func _step(dir: int) -> void:
	if _heroes.size() < 2:
		return
	_index = posmod(_index + dir, _heroes.size())
	Audio.play("ui_tap")
	_show_hero(dir)
	_place()


## The map's best run under PLAY: nothing until a run has been played (pass 44: the "no runs yet" line read like a
## placeholder), then the true best: time, level, stage and kills.
func _refresh_map() -> void:
	var m := Registry.map(_map_id)
	var bits: Array = [m.display_name if m else _map_id]
	var best := Save.best_run(_map_id)
	var played := not best.is_empty() and float(best.get("time", 0.0)) > 0.0
	_map_tap.visible = played or _maps.size() > 1
	if played:
		bits.append("best " + W.mmss(float(best.get("time", 0.0))))
		bits.append(W.lv(int(best.get("level", 0))))
		bits.append("stage %d" % int(best.get("stage", 1)))
		if int(best.get("kills", 0)) > 0:
			bits.append("%s kills" % W.num(int(best.get("kills", 0))))
	_map_line.text = " · ".join(bits)


## The glow behind Upgrade: one smooth turquoise halo that breathes, the button's own colour (a StyleBoxFlat's feathered
## shadow ring, nothing drawn inside the button; pass 45: six stepped rings had read as a staircase).
func _draw_glow() -> void:
	if _upgrade_btn == null or not _upgrade_btn.is_visible_in_tree():
		return
	var r := _upgrade_btn.get_global_rect()
	r.position -= _glow.global_position
	var pulse := 0.5 + 0.5 * sin(_glow_t * 2.6)
	_halo.shadow_size = int(round(18.0 + 14.0 * pulse))
	_halo.shadow_color = Color(GLOW, 0.42 + 0.22 * pulse)
	_glow.draw_style_box(_halo, r)


## The brass "!" on Upgrade's top-right corner when a rank can be bought, drawn over the row.
func _draw_mark() -> void:
	if _upgrade_btn == null or not _upgrade_btn.is_visible_in_tree() or not _affordable:
		return
	var r := _upgrade_btn.get_global_rect()
	r.position -= _mark.global_position
	var c := Vector2(r.end.x - 6.0, r.position.y + 6.0)
	_mark.draw_circle(c, 22.0, W.INK, true, -1.0, true)
	_mark.draw_circle(c, 17.0, W.BRASS, true, -1.0, true)
	_mark.draw_rect(Rect2(c + Vector2(-3.0, -11.0), Vector2(6.0, 13.0)), W.INK)
	_mark.draw_circle(c + Vector2(0.0, 7.5), 3.2, W.INK, true, -1.0, true)


## Whether the purse buys the next rank of any open talent.
func _rank_affordable() -> bool:
	for def: TalentDef in Registry.talents_list():
		if not Registry.is_unlocked("talent", def.id):
			continue
		var cost := def.cost_of_rank(Save.talent_rank(def.id))
		# pass 111 (lane SKINS): in the talent's own currency
		if cost >= 0 and Currency.can_afford(def.currency_type, cost):
			return true
	return false


func _process(delta: float) -> void:
	if _glow == null:
		return
	_glow_t += delta
	_glow.queue_redraw()
	# the row slides in (_enter): the mark follows the button
	if _mark:
		_mark.queue_redraw()


## With more than one open map, the line under PLAY steps through them.
func _next_map() -> void:
	if _maps.size() < 2:
		return
	var i := 0
	for j in _maps.size():
		if _maps[j].id == _map_id:
			i = j
	_map_id = _maps[(i + 1) % _maps.size()].id
	_refresh_map()
	if _stage:
		_stage.set_map(_map_id)


func _on_play() -> void:
	if _play.locked:
		Audio.play("ui_locked")
		return
	var c: CharacterDef = _heroes[_index] if not _heroes.is_empty() else null
	# pass 69: a hero not owned never starts a run, whatever the button shows
	if c and _is_locked(c):
		Audio.play("ui_locked")
		return
	if c:
		Save.data["last_character"] = c.id
	Save.data["last_map"] = _map_id
	Save.request_save()
	# pass 87 (lane SUI): once the map's first stage is beaten, PLAY opens the Stages menu (every time); the live look
	# keeps its world for the way back, as for the other menus. Before that PLAY starts stage 1 as it always did.
	if StagesScreenScript.opens_for(_map_id):
		if _stage:
			_stage.keep_on_exit = true
		UiFx.go(get_tree(), "res://ui/StagesScreen.tscn")
		return
	Run.choose_stage(0)
	_leave_for_a_run()
	UiFx.go(get_tree(), "res://game/Game.tscn")


## A run starting lets the live look's world go (pass 52): the run builds its own map, and never carries two.
func _leave_for_a_run() -> void:
	if _stage:
		_stage.keep_on_exit = false
	TitleStageScript.forget()


## The hero's sheet over the title (pass 61): open while it is up and not on its way out.
func sheet_open() -> bool:
	return _sheet != null and is_instance_valid(_sheet) and not bool(_sheet.call("is_done"))


# ---------------------------------------------------------------- heroes to buy (pass 69)

## The Requirement card over the plaque (a hero whose requirement is not met: what unlocks him, how far along it is) and
## the BUY column over the hero (one on sale: BUY with his price, and under it what the purse is short of). Built once,
## shown and filled by _show_unknown, placed by _place_unknown. Names for tools: "Requirement", "BuyColumn", "Buy",
## "BuyNote".
func _build_unknown() -> void:
	_req = PanelContainer.new()
	_req.name = "Requirement"
	_req.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_req.add_theme_stylebox_override("panel", W.box(W.AGED, 4, 6).pad(26, 14, 26, 18))
	var v := VBoxContainer.new()
	v.name = "Rows"
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_req.add_child(v)
	v.add_child(W.label("To unlock", 18, W.ROCK, 0.15))
	var line := HBoxContainer.new()
	line.name = "Line"
	line.add_theme_constant_override("separation", 20)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	_req_text = W.serif_text("", 28, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	_req_text.name = "Text"
	_req_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_req_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_req_text)
	_req.visible = false
	add_child(_req)
	_buy_col = VBoxContainer.new()
	_buy_col.name = "BuyColumn"
	_buy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_buy_col.add_theme_constant_override("separation", 12)
	_buy_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy = WButton.make(["BUY"], 52, WButton.PRIMARY, 5, 8, 16.0, 30.0)
	_buy.name = "Buy"
	_buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# short of gold it stays whole over the black figure (aged, no shadow), the shortfall under it
	_buy.locked_alpha = 1.0
	_buy.pressed.connect(ask_buy)
	_buy_col.add_child(_buy)
	_buy_note_box = PanelContainer.new()
	_buy_note_box.name = "BuyNote"
	_buy_note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy_note_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_buy_note_box.add_theme_stylebox_override("panel", W.box(W.PAPER, 3, 4).pad(16, 6, 16, 8))
	_buy_note = W.label("", 18, W.ROCK, 0.12)
	_buy_note_box.add_child(_buy_note)
	_buy_col.add_child(_buy_note_box)
	_buy_col.visible = false
	add_child(_buy_col)


## What the card and the BUY say for `c`, and which of them shows.
func _show_unknown(c: CharacterDef) -> void:
	if _req == null or _buy_col == null:
		return
	var st := _state(c)
	_req.visible = st == "locked"
	_buy_col.visible = st == "buyable"
	if st == "locked":
		var q := Registry.quest_for("character", c.id)
		_req_text.text = Registry.hero_requirement_text(c) if q else "Not in the game yet."
		var line: Control = _req.get_node("Rows/Line")
		var old := line.get_node_or_null("Bar")
		if old:
			line.remove_child(old)
			old.queue_free()
		var p := QuestTracker.progress(q) if q else Vector2i.ZERO
		if p.y > 0:
			var bar := WBar.make(clampf(float(p.x) / float(p.y), 0.0, 1.0), W.BRASS, 34.0, 4, 0)
			bar.name = "Bar"
			bar.custom_minimum_size.x = 280
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.text = "%s / %s" % [W.num(mini(p.x, p.y)), W.num(p.y)]
			bar.text_px = 20
			line.add_child(bar)
	elif st == "buyable":
		# pass 111 (lane SKINS): in his currency (Currency), its own icon on the button
		var cur := Currency.of(c.currency_type)
		var short := maxi(c.price, 0) - Currency.balance(cur)
		_buy.set_parts(["BUY", {"coin": 46, "fill": W.PAPER, "currency": cur}, [W.num(maxi(c.price, 0)), null, 52]])
		_buy.locked = short > 0
		_buy_note_box.visible = short > 0
		_buy_note.text = "%s more %s" % [W.num(short), Currency.word_of(cur)] if short > 0 else ""


## The card over the plaque, its width, its foot just over the dots (it covers the black figure's feet); the BUY over the
## middle of the hero's figure; the drawer in its room over the preview.
func _place_unknown(_plaque_top: float) -> void:
	if _req:
		_req.size = Vector2(_plaque.size.x, 0)
		_req.reset_size()
		_req.size = Vector2(_plaque.size.x, 0)
		var h := _req.get_combined_minimum_size().y
		_req.position = Vector2(_plaque.position.x, _dots.position.y - 6.0 - h)
	if _buy_col:
		var fig := hero_figure_rect()
		_buy_col.reset_size()
		var cs := _buy_col.get_combined_minimum_size()
		_buy_col.size = cs
		_buy_col.position = Vector2(fig.get_center().x - cs.x * 0.5, fig.position.y + fig.size.y * 0.5 - _buy.get_combined_minimum_size().y * 0.5)
	if drawer_open():
		_drawer.call("frame", _drawer_area())


## The rect the shown hero's figure takes on the screen: the live hero's (TitleStage.figure_rect), else the cut-out's box.
func hero_figure_rect() -> Rect2:
	if _stage:
		return _stage.figure_rect()
	return Rect2(_hero_row.position + _art_host.position, HERO_SIZE * _art_host.scale.x)


## The drawer's room: under the title's top block, across the screen, its foot just over the hero's head (on a short
## screen the drawer reaches down over him: WHeroDrawer.frame).
func _drawer_area() -> Rect2:
	var vp := get_viewport_rect().size
	var top := 0.0
	if _top_stack:
		# its size can read 0 (anchored by its top edge only): its content's height counts
		top = _top_stack.position.y + maxf(_top_stack.size.y, _top_stack.get_combined_minimum_size().y) + 14.0
	var fig := hero_figure_rect()
	var foot := fig.position.y - 10.0 if _stage else fig.position.y + fig.size.y * 0.42
	return Rect2(Vector2(BOX_LEFT, top), Vector2(vp.x - BOX_LEFT * 2.0, maxf(foot - top, 0.0)))


func drawer_open() -> bool:
	return _drawer != null and is_instance_valid(_drawer) and not bool(_drawer.call("is_done"))


## The Hero Collections button: opens the drawer, or closes it while it is open (its glyph is the close X then).
func toggle_drawer() -> void:
	if drawer_open():
		close_drawer()
	else:
		open_drawer()


## The drawer over the preview with every hero of the carousel, the shown one marked; the button moves over its catcher
## so it can close it.
func open_drawer() -> void:
	if drawer_open() or _heroes.is_empty() or sheet_open():
		return
	_swipe_id = -2
	var states := {}
	for h: CharacterDef in _heroes:
		states[h.id] = _state(h)
	_drawer = WHeroDrawerScript.open(self, _heroes, _heroes[_index], _drawer_area(), states)
	_drawer.connect("picked", _on_drawer_pick)
	_drawer.connect("closed", func(): _drawer_glyph.queue_redraw())
	move_child(_drawer_btn, -1)
	_drawer_glyph.queue_redraw()


func close_drawer() -> void:
	if drawer_open():
		_drawer.call("close")
	_drawer_glyph.queue_redraw()


## A tile tapped in the drawer: that hero is shown (he runs in from the side his tile lies on), the drawer stays open.
func _on_drawer_pick(h: CharacterDef) -> void:
	var i := _heroes.find(h)
	if i < 0 or i == _index:
		return
	var dir := 1 if i > _index else -1
	_index = i
	_show_hero(dir)
	_place()


## Pass 70 (Garry: "make it the same height as the Hero plaque while maintaining square aspect ratio"): the Hero
## Collections button's side, the plaque's height. Since pass 73 that height is PLAQUE_H for every hero (it followed
## the hero's words before, and the button, the plaque and the hero above them moved with every swipe). `vp` is kept
## for the callers.
func drawer_side(_vp: Vector2) -> float:
	return PLAQUE_H


## The plaque's room inside its border and padding (pass 73): what the name, the flavour, the numbers and the plates
## share, the same for every hero.
func plaque_inner() -> Vector2:
	return _plaque.size - PLAQUE_PAD * 2.0 if _plaque else Vector2.ZERO


## The glyph's grid (pass 70): its squares span GLYPH_SPAN of the button's side, GLYPH_GAP of a square apart.
const GLYPH_SPAN := 0.5
const GLYPH_GAP := 0.28


## The glyph's squares in a box of `box` (pass 70, Garry: "It should just be a matrix of squares. The 3x3 was the last
## one at the bottom, missing."): a 3 x 3 grid, row by row from the top-left, the bottom-right one left out (eight
## rects), whole pixels so every edge is crisp.
static func glyph_cells(box: Vector2) -> Array:
	var span := minf(box.x, box.y) * GLYPH_SPAN
	var sq := floorf(span / (3.0 + 2.0 * GLYPH_GAP))
	var gap := maxf(roundf(sq * GLYPH_GAP), 1.0)
	var full := sq * 3.0 + gap * 2.0
	var o := ((box - Vector2(full, full)) * 0.5).floor()
	var out: Array = []
	for row in 3:
		for col in 3:
			if row == 2 and col == 2:
				continue
			out.append(Rect2(o + Vector2(col, row) * (sq + gap), Vector2(sq, sq)))
	return out


## The button's glyph: eight plain ink squares (glyph_cells); while the drawer is open, pass 69's close X, grown with
## the button so it reads as it did.
func _draw_drawer_glyph() -> void:
	var g := _drawer_glyph
	var c := g.size * 0.5
	if drawer_open():
		var k := minf(g.size.x, g.size.y) / BOX_BTN
		var r := 22.0 * k
		g.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), W.INK, 9.0 * k, true)
		g.draw_line(c + Vector2(r, -r), c + Vector2(-r, r), W.INK, 9.0 * k, true)
		return
	for cell: Rect2 in glyph_cells(g.size):
		g.draw_rect(cell, W.INK)


## The BUY button: a hero on sale and a purse that holds his price asks first (WConfirm); short of it, it only says so.
func ask_buy() -> void:
	if _heroes.is_empty():
		return
	var c: CharacterDef = _heroes[_index]
	if _state(c) != "buyable":
		return
	if not Currency.can_afford(c.currency_type, maxi(c.price, 0)):
		Audio.play("ui_locked")
		return
	WConfirm.open(self, "Buy this hero?", "%s from your purse. Yours to play from then on." % Currency.price_words(c.currency_type, maxi(c.price, 0)),
		"Buy · %s" % W.num(maxi(c.price, 0)), "Not now", func(): _buy_now(c))


## The purchase: the gold spent (Save.buy_hero, the sink "hero"), the mask lifted with a burst, the plaque and PLAY his.
func _buy_now(c: CharacterDef) -> void:
	if not Save.buy_hero(c):
		Audio.play("ui_locked")
		_show_plaque(c)
		_place()
		return
	Audio.play("ui_buy")
	Analytics.track("hero_bought", {"hero": c.id, "price": maxi(c.price, 0), "currency": Currency.of(c.currency_type), "gold_after": Save.gold()})
	_refresh_gold()
	# the carousel's order follows what is owned: he moves up among the owned heroes and stays the one shown
	_heroes = _roster()
	_index = maxi(_heroes.find(c), 0)
	if _live:
		_stage.reveal()
		_show_lock(false, 0)
	else:
		_show_art(c, 0)
	_show_plaque(c)
	_place()
	var fig := hero_figure_rect()
	WCelebrate.burst(self, fig.get_center(), get_child_count(), 1.6)


## The gold plate's number after a purchase, and the Upgrade mark (a rank may no longer be affordable).
func _refresh_gold() -> void:
	if _gold_plate:
		for n in _gold_plate.find_children("Amount", "", true, false):
			(n as WText).text = W.num(Save.gold())
		# fewer digits: the plate shrinks to them
		_gold_plate.reset_size()
	_affordable = _rank_affordable()


## A tap on the plaque (pass 61): the shown hero's sheet, a locked one's with its quest.
func open_sheet() -> void:
	if _heroes.is_empty() or sheet_open():
		return
	var c: CharacterDef = _heroes[_index]
	_swipe_id = -2
	_sheet = WHeroSheetScript.open(self, c, _is_locked(c))
	# pass 111 (lane SKINS): a look worn or bought on the sheet: the purse and the hero behind it at once
	_sheet.connect("look_changed", func(_code: String): _on_sheet_look(c))


## The sheet's look changed (pass 111, lane SKINS): the gold plate, and the hero drawn again in the look he wears now.
func _on_sheet_look(c: CharacterDef) -> void:
	_refresh_gold()
	if _heroes.is_empty() or _heroes[_index] != c:
		return
	_show_hero(0)
	_place()


## A sideways swipe over the hero changes it; the finger is read here so it works wherever it lands in the row, and
## (pass 61) across the plaque, whose tap opens the hero's sheet: a swipe travels past the tap's slop, so it never opens it.
func _input(event: InputEvent) -> void:
	# pass 69: with the drawer open its own list takes the sideways drags, and a tap outside it only closes it
	if sheet_open() or drawer_open():
		return
	var pos := Vector2.ZERO
	var id := -2
	var down := false
	var up := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		pos = t.position
		id = t.index
		down = t.pressed
		up = not t.pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var m := event as InputEventMouseButton
		pos = m.position
		id = -1
		down = m.pressed
		up = not m.pressed
	else:
		return
	pos = get_viewport().get_canvas_transform().affine_inverse() * pos
	if down and _swipe_id == -2:
		var band := Rect2(Vector2(0, _hero_row.position.y), Vector2(get_viewport_rect().size.x, _hero_row.size.y))
		if band.has_point(pos) or _plaque.get_global_rect().has_point(pos):
			_swipe_id = id
			_swipe_from = pos
	elif up and id == _swipe_id:
		_swipe_id = -2
		var d := pos - _swipe_from
		if absf(d.x) > SWIPE and absf(d.x) > absf(d.y) * 1.5:
			_step(-1 if d.x > 0 else 1)


## The lower block slides up 40 px and the rest fades in.
func _enter() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	for n in _lower:
		var c := n as Control
		var y := c.position.y
		c.position.y = y + 40.0
		create_tween().tween_property(c, "position:y", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
