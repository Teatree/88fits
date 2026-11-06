## The Heroes screen (pass 123, lane HEROES; Garry's build brief: "Build the Heroes screen as the mock (hero, trait, items
## with full text, SELECT, LOOKS strip, hero grid) with the real looks, skins and icons from data. It replaces the hero
## drawer and the Wanted-poster sheet; DETAILS opens the new Hero details pop-up." and "Keep the favourite item row with
## 'finding it gives a bonus level'."). Under Royale the HEROES tab of the docked tab bar opens it (ui/wanted/WTabBar.gd);
## under Wanted nothing reaches it (it still builds, so a stray open never crashes).
## The mock 5_Heroes, top to bottom: the header (back, HEROES, the wallet). Top-left the shown hero in the look he is
## played in, standing on a sand disc and stepping through his idle frames at the look's own rate (a hero not owned: a
## black silhouette, the padlock on his chest while he is locked); the TRAIT panel (its name, "+1% crit chance per Level"
## for each signature stat, his heal on every level-up, what the rule adds: WHeroSheet.trait_lines / trait_note), or for
## a hero not owned TO UNLOCK (the quest and how far along it is) or ON SALE; DETAILS · ALL STATS (blue: the Hero details
## pop-up, WHeroSheet.open). Top-right his name, his slogan and HIS ITEMS (WHeroSheet.items_of: the weapon he lands with,
## his favourite with what finding it gives, a weapon only he finds, his hero mutation, his perks;
## each its frame, its kind, its name and the level-up card's words). SELECT (gold: he is the hero runs start with,
## Save.last_character, as the title's carousel picks him; SELECTED in slate once he is), BUY (green, his price: the
## shared confirm, then Save.buy_hero, as the title's BUY) or LOCKED (the locked grey; a tap says no). LOOKS · n OF m
## OWNED (a strip that scrolls sideways under a finger: every look he can wear or earn, WHeroSheet.royale_look_tile:
## WORN, WEAR, the price, or the goal; "SWIPE" when it runs past the screen); HEROES · n OF m OWNED (every hero the drawer
## lists, Registry.heroes_for_drawer, four a row: owned with his badge and name, on sale with his price, LOCKED; the
## shown one gold-edged with a glow; a tap shows him above). The docked tab bar at the foot with HEROES open; the page
## scrolls above it.
## Pass 123, Garry on that first build ("This screen also looks super busy, the Items are all bunched up together, there is
## plenty of empty useless space"; "Looks into a separate pop-up that appears only when Players tabs a new button"; "The
## hero ... doesn't make much sense since we are now showing those elements over the vista. Add a half transparent bg over
## the vista and make the live hero visual run in place, down and right"): the page sits on ScreenBase's half-transparent
## sheet; the top is the hero running in place (his down-right run cycle) beside his name, slogan, TRAIT, and DETAILS and
## LOOKS side by side; SELECT; HIS ITEMS in full-width rows with room between them; the hero grid. LOOKS opens the looks in
## the shared pop-up shell; a red crumb sits on it (and on the hero's tile and the HEROES tab) while a look is newly
## unlocked (core/systems/Crumbs.gd), gone once it has been opened.
## Pass 126 (lane UI; Garry: "Lock the Heroes select at the bottom as a separate scrollable area, the top part should be it's own
## scrollable area now. The Heroes view is always fully in view, 2 rows are displayed fully. The top part can now be cut off. For
## the top part there is a clear scroll weight thing"): two lists with a finger each (TouchScroll only_inside). The page (ScreenBase's
## `scroll`: the hero, SELECT, his items) ends over the picker and wears WScrollThumb with a fade on its foot while more lies below;
## the picker ("Heroes": its own panel on the sheet's foot, over the tab bar) shows PICK_ROWS rows whole in "HeroScroll" and moves
## only when the roster runs past them. A tile tapped shows that hero and brings the page back up to him; the picker stays put.
## No class_name (load by path). Names for tools: "Top", "Stage" ("Sprite", "Padlock"), "Trait", "Details", "LooksBtn",
## Pass 127 (Garry: "the upper part of the canvas for the scrollable area has its borders touching the back button too closely. The
## separation between Heroes select area and this scrollable area isn't very clear either"; "at the moment of selecting a different
## hero, we reset the upper scroll section to be all the way to the top"): the page's sheet starts clear of the header and ends
## PICK_GAP over the picker, whose own solid tray with its lighter edge stands apart on the vista; a tile tapped sets the page to its
## top at once, with no tween that could read as a scroll, and the shown hero's own tile does nothing.
## "HeroName", "Slogan", "Items", "Item_<role>_<id>", "SelectRow" > "Select" (meta "action": select, selected, buy,
## locked), "LooksPop" > "LookGrid" > "Look_<CODE>", "Heroes" ("Label", "HeroScroll" > "HeroGrid", "Hero_<id>": metas "hero",
## "state"), "ScrollThumb", "PageFade", "Crumb".
extends ScreenBase

const SHEET_SCRIPT := preload("res://ui/wanted/WHeroSheet.gd")
## The board: its top (the name's line in the mock) and side; the columns (the mock's 380 and 600, 20 apart).
const TOP := 200.0
const SIDE := 40.0
const COL_L := 340.0
const COL_GAP := 20
## The hero's stage beside his words: its size, where his soles stand in it, how tall his figure is, his soft shadow.
const STAGE_H := 372.0
const FEET_Y := 346.0
const FIGURE_PX := 320.0
const SHADOW := Vector2(190.0, 34.0)
const SHADOW_COLOR := Color(0.02, 0.03, 0.08, 0.5)
## Pass 126: how far over the soles' line the shadow's middle sits (a run's feet lift off the line; the shadow meets them).
const SHADOW_UP := 6.0
## The trait panel's type, the DETAILS button's, the name's, the slogan's, the items' (a 72 px frame, the mock's 26 px
## Ultra name set at 28 by Garry's rule, the words at 21: the mock's 19 a little larger), SELECT's (990 x 100, Ultra 48).
const LABEL_PX := 18
const TRAIT_PX := 26
const TRAIT_MIN_PX := 20
const NOTE_PX := 20
const DETAILS_H := 64.0
const DETAILS_PX := 24
const NAME_PX := 56
const SLOGAN_PX := 26
const ITEM_FRAME := 88.0
const ITEM_NAME_PX := 30
const ITEM_TEXT_PX := 24
const ITEM_LABEL_PX := 18
## The room between two item rows, and the rule drawn in the middle of it.
const ITEM_GAP := 18
const ITEM_RULE := Color(1, 1, 1, 0.08)
const SELECT_H := 100.0
const SELECT_PX := 48
const SELECT_INSET := 5
## The LOOKS strip and the HEROES grid (the mock: tiles 232 x 196, four a row 20 apart; the portraits 104 across).
const LOOK_GAP := 20
const GRID_COLS := 4
const GRID_TILE := Vector2(232, 176)
const GRID_GAP := 20
const GRID_INSET := 6
const PORTRAIT := 92.0
const GRID_NAME_PX := 28
## The glow round the shown hero's tile (the mock's 0 0 40px rgba(255,220,115,.7)): this many rings out to GLOW_PX.
const GLOW := Color(1.0, 0.863, 0.451)
const GLOW_PX := 30.0
const GLOW_RINGS := 10
const GLOW_ALPHA := 0.34
## Pass 126: the picker: the rows always on view, its panel's height parts top to bottom (the pad, the label's line, the gap, the
## room over the first row for the shown tile's glow, the room under the last row's base) and how far its foot stands over the tab
## bar's band (the open tab rises R.DOCK_TAB_H_ACTIVE - R.DOCK_BAR_H over it); the page's fade over the picker.
const PICK_ROWS := 2
const PICK_PAD := 12.0
const PICK_LABEL_H := 22.0
const PICK_LABEL_GAP := 2.0
const PICK_GRID_TOP := 14.0
const PICK_GRID_FOOT := 6.0
const PICK_FOOT := 34.0
const PICK_FILL := Color(0.03, 0.05, 0.12, 0.94)
## Pass 127: the vista's gap between the page's sheet and the picker's tray, the tray's edge.
const PICK_GAP := 18.0
const PICK_EDGE := Color("46558c")
const PICK_EDGE_PX := 3
const PAGE_FADE_H := 70.0
## Pass 126: what the page gives up on its right for the thumb's gutter (the picker's tiles and SELECT end on the same line).
const PAGE_GUTTER := 6
## A refused tap: the button shakes sideways this far, this long (the tab bar's, the Stages' closed card's).
const SHAKE_PX := 14.0
const SHAKE_S := 0.32
## The overlay over the backdrop, under the board's half-transparent sheet.
const DIM := 0.25
## The crumb on the LOOKS button and on a hero's tile.
const CRUMB_PX := 40.0
const CRUMB_TILE_PX := 34.0
const LOOKS_PER_ROW := 4

## Pass 128: the outlaw this screen opens on next time it is built (his id; "" = the last one played, as ever). Set by
## whoever sends the player here to look at one outlaw (the Collection's "Comes with <name>" line: CollectionScreen.
## open_outlaw), read and cleared in build(), like CollectionScreen.hidden_only. Back goes where it always goes.
static var open_on := ""

## The hero the top half shows, the heroes the grid lists (in the drawer's order), the details pop-up while it is up.
var shown: CharacterDef
var heroes: Array = []
var _sheet: Control
var _wallet: Control
## The looks' pop-up while it is up (the shared shell), and its grid.
var looks_pop: WConfirm
var looks_grid: GridContainer
var select_btn: WButton
var grid: GridContainer
## Pass 126: the picker, its list and that list's finger; the page's thumb and fade.
var picker: Control
var grid_scroll: ScrollContainer
var _grid_touch: TouchScroll
var page_thumb: WScrollThumb
var _page_fade: TextureRect
var _sprite: Control
## The sprite's strip and where its idle cycle lies in it (BillboardSprite's layout: frames in TitleStage.ORDER, rows of
## strip_cols), its rate, and the clock that steps it (no allocation per frame).
var _tex: Texture2D
var _frame_px := 256
var _cols := 0
var _anim_from := 0
var _anim_n := 1
var _fps := 4.0
var _clock := 0.0
var _frame := 0
var _silhouette := false

func tab_bar() -> String:
	return "heroes"


func backdrop_dim() -> float:
	return DIM


func board_top() -> float:
	return TOP


func board_side() -> float:
	return SIDE


## Pass 126: the page ends over the picker (ScreenBase keeps the tab bar's band clear on top of this). Pass 127: its sheet ends with
## it, PICK_GAP over the tray (ScreenBase's sheet runs 8 px past the board's foot).
func board_bottom() -> float:
	return PICK_FOOT + picker_height() + PICK_GAP + 8.0


## The picker's whole height: its label's line and its list.
static func picker_height() -> float:
	return PICK_PAD + PICK_LABEL_H + PICK_LABEL_GAP + picker_view_height()


## The picker's list on the screen: PICK_ROWS whole rows of tiles with their bases, and the room round them.
static func picker_view_height() -> float:
	return PICK_GRID_TOP + GRID_TILE.y * PICK_ROWS + float(GRID_GAP + R.PANEL_BASE) * (PICK_ROWS - 1) + R.PANEL_BASE + PICK_GRID_FOOT


func header_right() -> Control:
	_wallet = WMenuHeader.gold_plate(Save.gold(), 44, 40.0, 5, 4)
	return _wallet


func build() -> void:
	set_title("Outlaws")
	content.add_theme_constant_override("separation", 0)
	heroes = _roster()
	var last := Registry.playable_character(str(Save.data.get("last_character", Save.DEFAULT_HERO)))
	shown = last if last and heroes.has(last) else (heroes[0] if not heroes.is_empty() else null)
	# pass 128: opened on one outlaw by name (the Collection's "Comes with <name>"), once
	var want: CharacterDef = Registry.character(open_on) if open_on != "" else null
	open_on = ""
	if want and heroes.has(want):
		shown = want
	# pass 126: each list moves only under a finger that came down on it; the thumb's gutter on the page's right
	_touch.only_inside = true
	margin.add_theme_constant_override("margin_right", int(SIDE) + PAGE_GUTTER)
	_build_picker()
	_build_page_marks()
	_fill()
	if want and shown == want:
		_reveal_tile.call_deferred(want.id)


## Pass 128: the picker's list moved so outlaw `id`'s tile shows (the screen opened on him: open_on).
func _reveal_tile(id: String) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or grid == null or grid_scroll == null:
		return
	var t := grid.get_node_or_null("Hero_" + id) as Control
	if t:
		grid_scroll.ensure_control_visible(t)


## Every hero the drawer lists (Registry.heroes_for_drawer: owned, on sale, locked), the hidden ones after them while the
## developer previews them (the title's rule).
func _roster() -> Array:
	var out: Array = Registry.heroes_for_drawer()
	if bool(Settings.get("preview_locked_heroes")):
		var hidden: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return c.hidden)
		hidden.sort_custom(func(a, b): return a.id < b.id)
		out.append_array(hidden)
	return out


## Where the player stands with `c`: owned, buyable or locked (a previewed hidden hero reads locked, as on the title).
func state_of(c: CharacterDef) -> String:
	var st := Registry.hero_state(c)
	return "locked" if st == "hidden" else st


func owned(c: CharacterDef) -> bool:
	return c != null and state_of(c) == "owned"


# ---------------------------------------------------------------- the page

## The page again for the hero shown (a tap on the grid, a purchase, a look worn): everything under the header, and the
## picker's tiles.
func _fill() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	_fill_picker()
	if shown == null:
		return
	content.add_child(_top())
	content.add_child(_gap(18.0))
	content.add_child(_select_row())
	content.add_child(_gap(34.0))
	content.add_child(_items_panel())
	# pass 126: room for the fade over the last line
	content.add_child(_gap(PAGE_FADE_H * 0.5))


func _gap(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = h
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## The top: the hero running in place at the left; his name, slogan, TRAIT, and DETAILS and LOOKS at the right.
func _top() -> Control:
	var row := HBoxContainer.new()
	row.name = "Top"
	row.add_theme_constant_override("separation", COL_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_stage())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	var is_owned := owned(shown)
	var nm := W.text(("Unknown" if not is_owned else SHEET_SCRIPT.hero_name(shown)).to_upper(), W.slab(), NAME_PX, W.INK,
		HORIZONTAL_ALIGNMENT_LEFT, float(NAME_PX))
	nm.name = "HeroName"
	SHEET_SCRIPT.fit_text(nm, 1080.0 - SIDE * 2.0 - PAGE_GUTTER - COL_L - COL_GAP, 36)
	right.add_child(nm)
	right.add_child(_gap(12.0))
	var sl := W.serif_text("?" if not is_owned else shown.flavour, SLOGAN_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0,
		true, false)
	sl.name = "Slogan"
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(sl)
	right.add_child(_gap(22.0))
	right.add_child(_trait_panel())
	right.add_child(_gap(22.0))
	var buttons := HBoxContainer.new()
	buttons.name = "TopButtons"
	buttons.add_theme_constant_override("separation", 16)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(buttons)
	var details := WButton.make(["DETAILS"], DETAILS_PX, WButton.UPGRADE, R.BUTTON_EDGE, R.BUTTON_BASE,
		maxf((DETAILS_H - 2.0 * R.BUTTON_EDGE - DETAILS_PX) * 0.5, 0.0), 12.0, float(DETAILS_PX), WButton.BLUE)
	details.name = "Details"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.pressed.connect(open_details)
	buttons.add_child(details)
	if is_owned:
		buttons.add_child(_looks_button())
	return row


## LOOKS (blue: it opens something), a red crumb on its corner while a look of his is newly unlocked.
func _looks_button() -> Control:
	var holder := Control.new()
	holder.name = "LooksHolder"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(0.0, DETAILS_H)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var b := WButton.make(["SKINS"], DETAILS_PX, WButton.UPGRADE, R.BUTTON_EDGE, R.BUTTON_BASE,
		maxf((DETAILS_H - 2.0 * R.BUTTON_EDGE - DETAILS_PX) * 0.5, 0.0), 12.0, float(DETAILS_PX), WButton.BLUE)
	b.name = "LooksBtn"
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.pressed.connect(open_looks)
	holder.add_child(b)
	if Crumbs.look_due(shown):
		var c: Control = load(TAB_BAR).make_crumb("Crumb", CRUMB_PX)
		c.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		c.position = Vector2(-CRUMB_PX * 0.6, -CRUMB_PX * 0.4)
		c.offset_left = -CRUMB_PX * 0.6
		c.offset_right = CRUMB_PX * 0.4
		c.offset_top = -CRUMB_PX * 0.4
		c.offset_bottom = CRUMB_PX * 0.6
		holder.add_child(c)
	return holder


## The hero, running in place on the sheet over his soft shadow (his down-right run cycle, stepped by _process).
func _stage() -> Control:
	var st := Control.new()
	st.name = "Stage"
	st.custom_minimum_size = Vector2(COL_L, STAGE_H)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite = Control.new()
	_sprite.name = "Sprite"
	_sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.draw.connect(_draw_sprite)
	st.add_child(_sprite)
	_load_sprite()
	if state_of(shown) == "locked":
		var lock := W.glyph("lock", 64.0, R.GOLD_TEXT)
		lock.name = "Padlock"
		var q := FIGURE_PX / (TitleStage.FIGURE_FEET - TitleStage.FIGURE_TOP)
		var gs := W.glyph_size("lock", 64.0)
		lock.position = Vector2(COL_L * 0.5 - gs.x * 0.5, FEET_Y - TitleStage.FIGURE_FEET * q + q * 0.42 - gs.y * 0.5)
		lock.size = gs
		st.add_child(lock)
	return st


## His played look's strip and his run cycle heading down and to the right (run_fd when the strip has it, else the plainest
## run; TitleStage.ORDER's layout; Garry: "make the live hero visual run in place, down and right").
func _load_sprite() -> void:
	var art: CharacterDef = Registry.played_look(shown)
	_tex = art.sprite if art else null
	var anims: Dictionary = art.anims if art else {}
	if _tex == null:
		_tex = PlaceholderArt.character_strip(shown)
		anims = {"idle": 2, "run": 4, "turn": 1, "hit": 1, "die": 1, "cheer": 1}
		_cols = 0
		_frame_px = 256
	else:
		_cols = art.strip_cols
		_frame_px = art.frame_px
	var want := "run"
	for a2: String in ["run_fd", "run_s", "run_f", "run"]:
		if int(anims.get(a2, 0)) > 0:
			want = a2
			break
	var at := 0
	_anim_from = 0
	_anim_n = 1
	for a: String in TitleStage.ORDER:
		var n := int(anims.get(a, 0))
		if a == want:
			_anim_from = at
			_anim_n = maxi(n, 1)
			break
		at += n
	_fps = 0.0
	if art:
		for k in art.fps.keys():
			if want.begins_with(str(k)):
				_fps = float(art.fps[k])
	if _fps <= 0.0:
		_fps = float(BillboardSprite.SPEEDS.get("run", 10.0))
	_clock = 0.0
	_frame = 0
	_silhouette = not owned(shown)
	if _sprite:
		_sprite.queue_redraw()


## The frame of the run cycle at `_frame`: his soles on FEET_Y, FIGURE_PX tall (the figure fills FIGURE_TOP..FIGURE_FEET
## of a frame), a hero not owned drawn flat black; his soft shadow under him.
func _draw_sprite() -> void:
	if _tex == null:
		return
	# the shadow: three flattened discs, dark in the middle
	# pass 126 (Garry: "so it's actually touching their feet"): on the line his soles truly reach, not the figure's box
	var soles_y := FEET_Y - (TitleStage.FIGURE_FEET - TitleStage.FIGURE_SOLE) * FIGURE_PX / (TitleStage.FIGURE_FEET - TitleStage.FIGURE_TOP)
	_sprite.draw_set_transform(Vector2(COL_L * 0.5 + 16.0, soles_y - SHADOW_UP), 0.0, Vector2(1.0, SHADOW.y / SHADOW.x))
	for k in 3:
		_sprite.draw_circle(Vector2.ZERO, SHADOW.x * 0.5 * (1.0 - 0.28 * k), Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.4), true, -1.0, true)
	_sprite.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var f := _anim_from + _frame
	var col := f % _cols if _cols > 0 else f
	var rw := f / _cols if _cols > 0 else 0
	var src := Rect2(col * _frame_px, rw * _frame_px, _frame_px, _frame_px)
	var q := FIGURE_PX / (TitleStage.FIGURE_FEET - TitleStage.FIGURE_TOP)
	var dst := Rect2(COL_L * 0.5 - q * 0.5, FEET_Y - TitleStage.FIGURE_FEET * q, q, q)
	_sprite.draw_texture_rect_region(_tex, dst, src, TitleStage.LOCKED_TINT if _silhouette else Color.WHITE)


## TRAIT (owned): its name, a line for each signature stat, the rule's notes; TO UNLOCK (locked: the quest and its
## progress) or ON SALE (his requirement met).
func _trait_panel() -> Control:
	var p := PanelContainer.new()
	p.name = "Trait"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var inner := 1080.0 - SIDE * 2.0 - PAGE_GUTTER - COL_L - COL_GAP
	match state_of(shown):
		"owned":
			v.add_child(W.label(("Trait · " + shown.trait_name) if shown.trait_name != "" else "Trait", LABEL_PX, W.INK_SOFT))
			for line: Array in SHEET_SCRIPT.trait_lines(shown):
				var good := bool(line[2])
				var t := W.text("", R.body(R.BODY_WEIGHT), TRAIT_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, roundf(TRAIT_PX * 1.25))
				t.name = "Line"
				t.runs = [[str(line[0]), R.ROLES["green"]["top"] if good else R.ROLES["red"]["top"], R.body(R.LABEL_WEIGHT)],
					[" " + str(line[1]), R.WHITE]]
				SHEET_SCRIPT.fit_text(t, inner, TRAIT_MIN_PX)
				v.add_child(t)
			var note := SHEET_SCRIPT.trait_note(shown)
			if note != "":
				var n := W.serif_text(note, NOTE_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, roundf(NOTE_PX * 1.25), true, false)
				n.name = "Note"
				n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				v.add_child(n)
		"buyable":
			v.add_child(W.label("On sale", LABEL_PX, W.SAGE))
			var q := Registry.quest_for("character", shown.id)
			var cur := Currency.of(shown.currency_type)
			var words := ("Requirement met: " + TextGen.quest_text(q)) if q else ("Yours for %s." % Currency.price_words(cur, maxi(shown.price, 0)))
			var t2 := W.serif_text(words, 22, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
			t2.name = "Requirement"
			t2.color = R.WHITE
			t2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(t2)
			# short of his price: what the purse lacks, in red on the panel (the mock's "n short" beside a grey price)
			var short := maxi(shown.price, 0) - Currency.balance(cur)
			if short > 0:
				var sh := W.short_text(short, 22)
				sh.align = HORIZONTAL_ALIGNMENT_LEFT
				v.add_child(sh)
		_:
			v.add_child(W.label("To unlock", LABEL_PX, W.ROCK))
			var q2 := Registry.quest_for("character", shown.id)
			var t3 := W.serif_text(Registry.hero_requirement_text(shown) if q2 else "Not in the game yet.", 22, W.INK, 400, false,
				HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
			t3.name = "Requirement"
			t3.color = R.WHITE
			t3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(WPoster.with_picture(q2, t3, 36.0))
			var pr := QuestTracker.progress(q2) if q2 else Vector2i.ZERO
			if pr.y > 0:
				var bar := WBar.make(clampf(float(pr.x) / float(pr.y), 0.0, 1.0), W.BRASS, 30.0, 3, 0)
				bar.name = "Progress"
				bar.text = "%s / %s" % [W.num(mini(pr.x, pr.y)), W.num(pr.y)]
				bar.text_px = 18
				v.add_child(bar)
	return p


## HIS ITEMS: every item of WHeroSheet.items_of on a 72 px frame (a hero not owned: their black shapes and roles).
func _items_panel() -> Control:
	var p := PanelContainer.new()
	p.name = "Items"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", ITEM_GAP)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var is_owned := owned(shown)
	v.add_child(W.label((TextGen.possessive(shown) + " items") if is_owned else "Items", LABEL_PX, W.INK_SOFT))
	var sheet: StatSheet = Run.hero_sheet(shown, 1)
	var first := true
	for it: Dictionary in SHEET_SCRIPT.items_of(shown):
		if not first:
			var rule := ColorRect.new()
			rule.color = ITEM_RULE
			rule.custom_minimum_size.y = 2.0
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(rule)
		first = false
		v.add_child(SHEET_SCRIPT.royale_item_row(it, sheet, not is_owned, ITEM_FRAME, ITEM_NAME_PX, ITEM_TEXT_PX, ITEM_LABEL_PX))
	return p


## SELECT (gold) / SELECTED (slate) for an owned hero, BUY with his price (green; short of it the grey and what it is
## short) for one on sale, LOCKED (the locked grey) for one whose requirement is not met.
func _select_row() -> Control:
	var m := MarginContainer.new()
	m.name = "SelectRow"
	m.add_theme_constant_override("margin_left", SELECT_INSET)
	m.add_theme_constant_override("margin_right", SELECT_INSET)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := maxf((SELECT_H - 2.0 * R.BUTTON_EDGE - SELECT_PX) * 0.5, 0.0)
	var st := state_of(shown)
	match st:
		"owned":
			var picked := is_selected(shown)
			select_btn = WButton.make(["SELECTED" if picked else "SELECT"], SELECT_PX, WButton.SECONDARY if picked else WButton.PRIMARY,
				R.BUTTON_EDGE, R.BUTTON_BASE, pad, 0.0, float(SELECT_PX), WButton.SLATE if picked else WButton.GOLD)
			select_btn.set_meta("action", "selected" if picked else "select")
			select_btn.pressed.connect(select_shown)
			m.add_child(select_btn)
		"buyable":
			var cur := Currency.of(shown.currency_type)
			var price := maxi(shown.price, 0)
			var short := maxi(price - Currency.balance(cur), 0)
			# short of it: the locked grey with the price and the word kept; the shortfall is said on the ON SALE panel
			select_btn = WButton.price(price, "BUY", WButton.GREEN, SELECT_PX, short, cur, true, SELECT_H)
			select_btn.set_meta("action", "buy")
			select_btn.pressed.connect(ask_buy)
			m.add_child(select_btn)
		_:
			select_btn = WButton.make([{"glyph": "lock", "px": 40}, "LOCKED"], SELECT_PX, WButton.SECONDARY, R.BUTTON_EDGE,
				R.BUTTON_BASE, pad, 0.0, float(SELECT_PX), WButton.LOCKED)
			select_btn.locked = true
			select_btn.set_meta("action", "locked")
			select_btn.pressed.connect(func(): _refuse(select_btn))
			m.add_child(select_btn)
	select_btn.name = "Select"
	return m


## Whether `c` is the hero runs start with (Save.last_character).
func is_selected(c: CharacterDef) -> bool:
	return c != null and str(Save.data.get("last_character", "")) == c.id


## LOOKS: the shared pop-up shell over the page: his name, how many he owns, every look he can wear or earn (a hero with one
## art his one look). Opening it takes the crumb off (Crumbs.looks_mark_seen).
func open_looks() -> void:
	if shown == null or not owned(shown):
		return
	Crumbs.looks_mark_seen(shown)
	looks_pop = WConfirm.shell(self, {"buttons": [{"id": "cancel", "text": "Close", "role": WButton.SLATE}],
		"button_h": 96.0, "button_px": 38, "on_answer": _on_looks_answer})
	looks_pop.name = "LooksPop"
	_fill_looks_pop()
	_fill()
	_rebuild_tab_bar()


func _on_looks_answer(_id: String) -> void:
	looks_pop = null
	looks_grid = null


func looks_open() -> bool:
	return looks_pop != null and is_instance_valid(looks_pop)


## The pop-up's rows: the star line, the name, n OF m OWNED, the tiles (LOOKS_PER_ROW a row).
func _fill_looks_pop() -> void:
	if not looks_open():
		return
	var box := looks_pop.body_box
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var codes: Array = Registry.skins_of(shown)
	if codes.is_empty():
		codes = [shown.home_look()]
	var worn := SHEET_SCRIPT.worn_of(shown)
	var n_owned := 0
	for code: String in codes:
		var st := SHEET_SCRIPT.look_state_of(shown, code)
		if st == "worn" or st == "owned":
			n_owned += 1
	var v := VBoxContainer.new()
	v.name = "LooksBody"
	v.add_theme_constant_override("separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	v.add_child(WConfirm.make_star("Skins"))
	v.add_child(WConfirm.make_title(SHEET_SCRIPT.hero_name(shown).to_upper(), 56))
	var lab := W.label("%d of %d owned" % [n_owned, codes.size()], LABEL_PX, W.INK_SOFT)
	lab.name = "Label"
	lab.align = HORIZONTAL_ALIGNMENT_CENTER
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(lab)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(cc)
	looks_grid = GridContainer.new()
	looks_grid.name = "LookGrid"
	looks_grid.columns = LOOKS_PER_ROW
	looks_grid.add_theme_constant_override("h_separation", LOOK_GAP)
	looks_grid.add_theme_constant_override("v_separation", LOOK_GAP + R.PANEL_BASE)
	looks_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	cc.add_child(looks_grid)
	for code: String in codes:
		var t: WTap = SHEET_SCRIPT.royale_look_tile(shown, code, worn)
		t.pressed.connect(func(): _on_look(code))
		looks_grid.add_child(t)


## The picker (pass 126): built once, over the sheet's foot and under the tab bar: its panel, HEROES · n OF m OWNED and the
## grid in its own list.
func _build_picker() -> void:
	picker = Control.new()
	picker.name = "Heroes"
	picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var foot := PICK_FOOT + tab_bar_height()
	picker.offset_top = -(foot + picker_height())
	picker.offset_bottom = -foot
	add_child(picker)
	var side := sheet_insets().position.x
	var panel := Panel.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = PICK_FILL
	sb.border_color = PICK_EDGE
	sb.set_border_width_all(PICK_EDGE_PX)
	sb.set_corner_radius_all(R.RADIUS_TAB)
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# pass 127: its own tray, as wide as the page's sheet, down to where that sheet's foot was
	panel.offset_left = side
	panel.offset_right = -side
	panel.offset_bottom = 8.0
	picker.add_child(panel)
	grid_scroll = ScrollContainer.new()
	grid_scroll.name = "HeroScroll"
	grid_scroll.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	grid_scroll.offset_top = -picker_view_height()
	grid_scroll.offset_bottom = 0.0
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	grid_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	picker.add_child(grid_scroll)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(SIDE) + GRID_INSET)
	m.add_theme_constant_override("margin_right", int(SIDE) + GRID_INSET)
	m.add_theme_constant_override("margin_top", int(PICK_GRID_TOP))
	m.add_theme_constant_override("margin_bottom", int(PICK_GRID_FOOT) + R.PANEL_BASE)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	grid_scroll.add_child(m)
	grid = GridContainer.new()
	grid.name = "HeroGrid"
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP + R.PANEL_BASE)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.draw.connect(_draw_glow)
	# the glow follows the tiles (they are laid out after they are made)
	grid.sort_children.connect(grid.queue_redraw)
	m.add_child(grid)
	_grid_touch = TouchScroll.new(grid_scroll, true)
	# the roster past PICK_ROWS: the same thumb, in the same gutter
	var thumb := WScrollThumb.make(grid_scroll)
	thumb.name = "HeroThumb"
	_lay_thumb(thumb, -picker_view_height() + PICK_GRID_TOP, -2.0, Control.PRESET_BOTTOM_RIGHT)
	picker.add_child(thumb)


## The page's marks (pass 126): the thumb in the gutter between the page and the sheet's edge, and the fade over the picker's top
## edge while more of the page lies below.
func _build_page_marks() -> void:
	var foot := bottom_total()
	page_thumb = WScrollThumb.make(scroll)
	_lay_thumb(page_thumb, TOP + W.safe_top() + 6.0, -foot - 6.0, Control.PRESET_RIGHT_WIDE)
	var g := Gradient.new()
	g.set_color(0, Color(PICK_FILL, 0.0))
	g.set_color(1, Color(PICK_FILL, 0.8))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 4
	tex.height = 64
	_page_fade = TextureRect.new()
	_page_fade.name = "PageFade"
	_page_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_fade.texture = tex
	_page_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_fade.stretch_mode = TextureRect.STRETCH_SCALE
	_page_fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var side := sheet_insets().position.x + 3.0
	_page_fade.offset_left = side
	_page_fade.offset_right = -side
	# pass 127: down to the sheet's own foot, inside its edge and clear of its round corners
	_page_fade.offset_top = -foot - PAGE_FADE_H
	_page_fade.offset_bottom = -foot + 5.0
	add_child(_page_fade)
	add_child(page_thumb)
	var bar := scroll.get_v_scroll_bar()
	bar.changed.connect(_read_page_fade)
	bar.value_changed.connect(func(_v: float) -> void: _read_page_fade())


## A thumb in the right gutter, R.SCROLL_THUMB_W wide, from `top` to `bottom` on its anchors.
func _lay_thumb(t: WScrollThumb, top: float, bottom: float, preset: int) -> void:
	t.set_anchors_preset(preset)
	t.anchor_left = 1.0
	t.anchor_right = 1.0
	var x := sheet_insets().position.x + 3.0
	t.offset_right = -x
	t.offset_left = t.offset_right - R.SCROLL_THUMB_W
	t.offset_top = top
	t.offset_bottom = bottom


func _read_page_fade() -> void:
	if _page_fade and page_thumb:
		_page_fade.visible = page_thumb.more_below()


## HEROES · n OF m OWNED and the tiles again; where the list stands stays (the same rows, the same height).
func _fill_picker() -> void:
	var old := picker.get_node_or_null("Label")
	if old:
		picker.remove_child(old)
		old.queue_free()
	var n_owned := 0
	for h: CharacterDef in heroes:
		if owned(h):
			n_owned += 1
	var lab := W.label("Outlaws · %d of %d owned" % [n_owned, heroes.size()], LABEL_PX, W.INK_SOFT)
	lab.name = "Label"
	lab.position = Vector2(SIDE, PICK_PAD)
	lab.size = Vector2(1080.0 - SIDE * 2.0, PICK_LABEL_H)
	picker.add_child(lab)
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for h: CharacterDef in heroes:
		grid.add_child(_hero_tile(h))
	grid.queue_redraw()


## A hero's tile: his badge round in its ring (not owned: the black silhouette and a "?"), then his name, his price
## (green) or LOCKED (red); the shown one gold-edged.
func _hero_tile(h: CharacterDef) -> WTap:
	var st := state_of(h)
	var is_shown := h == shown
	var t := WTap.new()
	t.name = "Hero_" + h.id
	t.set_meta("hero", h)
	t.set_meta("state", st)
	t.custom_minimum_size = GRID_TILE
	var e := R.PANEL_EDGE
	var b := W.box(W.PAPER, e, R.PANEL_BASE).pad(8 + e, 14 + e, 8 + e, 10 + e)
	if is_shown:
		b.inner = 5
		b.inner_color = W.BRASS
	t.box = b
	t.box_down = b.pressed()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	var pic := SHEET_SCRIPT.royale_portrait(Registry.played_look(h).icon, PORTRAIT, is_shown, st != "owned")
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	# pass 123: the crumb's trail to LOOKS runs through his tile
	if st == "owned" and Crumbs.look_due(h):
		var crumb: Control = load(TAB_BAR).make_crumb("Crumb", CRUMB_TILE_PX)
		crumb.position = Vector2(PORTRAIT - CRUMB_TILE_PX * 0.6, -CRUMB_TILE_PX * 0.2)
		pic.add_child(crumb)
	match st:
		"owned":
			var n := W.text(h.display_name.to_upper(), W.slab(), GRID_NAME_PX, W.INK, HORIZONTAL_ALIGNMENT_CENTER, float(GRID_NAME_PX))
			n.name = "Foot"
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			SHEET_SCRIPT.fit_text(n, GRID_TILE.x - 24.0, 22)
			v.add_child(n)
		"buyable":
			var cur := Currency.of(h.currency_type)
			var price := maxi(h.price, 0)
			var tag: PanelContainer = SHEET_SCRIPT.royale_tag(W.num(price), "green" if Currency.can_afford(cur, price) else "locked",
				R.TAG_PX, 20.0, cur)
			tag.name = "Foot"
			v.add_child(tag)
		_:
			var lk: PanelContainer = SHEET_SCRIPT.royale_tag("Locked", "red", R.TAG_PX)
			lk.name = "Foot"
			v.add_child(lk)
	t.pressed.connect(func(): show_hero(h))
	return t


## The glow round the shown hero's tile, drawn by the grid under its tiles: rings growing out and fading.
func _draw_glow() -> void:
	if grid == null or shown == null:
		return
	var t := grid.get_node_or_null("Hero_" + shown.id) as Control
	if t == null:
		return
	var r := Rect2(t.position, t.size)
	for k in GLOW_RINGS:
		var f := float(k + 1) / float(GLOW_RINGS)
		var grow := GLOW_PX * f
		var a := GLOW_ALPHA * (1.0 - f) * (1.0 - f) + 0.02
		grid.draw_style_box(R.flat(Color(GLOW, a), int(R.RADIUS + grow)), r.grow(grow))


# ---------------------------------------------------------------- what a finger does

## Shows `c` in the top half (a tile tapped; tools): the page again, scrolled back up to him; the picker stays where it is.
func show_hero(c: CharacterDef) -> void:
	if c == null or c == shown:
		return
	shown = c
	_fill()
	# pass 126: a page still coasting from a flick stops. Pass 127: and it stands at its top at once
	if _touch:
		_touch.reset()
	if scroll:
		scroll.scroll_vertical = 0


## The page and the wallet again (a purchase, a look worn, the purse changed under it).
func refresh() -> void:
	heroes = _roster()
	if shown and not heroes.has(shown):
		shown = heroes[0] if not heroes.is_empty() else null
	_refresh_wallet()
	_fill()
	_fill_looks_pop()


func _refresh_wallet() -> void:
	if _wallet == null:
		return
	for n in _wallet.find_children("Amount", "", true, false):
		(n as WText).text = W.num(Save.gold())
	_wallet.reset_size()


## SELECT: the shown hero is the one runs start with (Save.last_character, as the title's carousel picks him); the
## button reads SELECTED and the HEROES tab wears his badge.
func select_shown() -> void:
	if shown == null or not owned(shown) or is_selected(shown):
		return
	Save.data["last_character"] = shown.id
	Save.request_save(true)
	_fill()
	_rebuild_tab_bar()


## The tab bar again (its HEROES tab shows the badge of the hero runs start with).
func _rebuild_tab_bar() -> void:
	if tab_bar_node == null:
		return
	var at := tab_bar_node.get_index()
	remove_child(tab_bar_node)
	tab_bar_node.queue_free()
	tab_bar_node = load(TAB_BAR).make(tab_bar())
	add_child(tab_bar_node)
	move_child(tab_bar_node, at)


## BUY: a purse that holds his price asks first (WConfirm, kind "buy": green); short of it, it only says so.
func ask_buy() -> void:
	if shown == null or state_of(shown) != "buyable":
		return
	var c := shown
	var cur := Currency.of(c.currency_type)
	var price := maxi(c.price, 0)
	if not Currency.can_afford(cur, price):
		_refuse(select_btn)
		return
	WConfirm.open(self, "Buy this outlaw?", "%s from your purse. Yours to play from then on." % Currency.price_words(cur, price),
		"Buy · %s" % W.num(price), "Not now", func(): buy_now(c), Callable(), "buy", WButton.price_parts(price, "BUY", R.MODAL_BUTTON_PX, cur))


## The purchase (the title's): the gold spent (Save.buy_hero, the sink "hero"), the page his, a burst over him.
func buy_now(c: CharacterDef) -> bool:
	if not Save.buy_hero(c):
		Audio.play("ui_locked")
		refresh()
		return false
	Audio.play("ui_buy")
	Analytics.track("hero_bought", {"hero": c.id, "price": maxi(c.price, 0), "currency": Currency.of(c.currency_type), "gold_after": Save.gold()})
	shown = c
	refresh()
	var at := Vector2(SIDE + COL_L * 0.5, TOP + FEET_Y - FIGURE_PX * 0.5 + W.safe_top() - float(scroll.scroll_vertical))
	WCelebrate.burst(self, at, get_child_count(), 1.6)
	return true


## A look's tile tapped: an owned look is worn, a look to buy asks first, a locked one only says so (the sheet's rules).
func _on_look(code: String) -> void:
	match SHEET_SCRIPT.look_state_of(shown, code):
		"worn":
			pass
		"owned":
			wear_look(code)
		"buyable":
			ask_buy_look(code)
		_:
			var t: Control = looks_grid.get_node_or_null("Look_" + (code if code != "" else "base")) if looks_grid else null
			_refuse(t)


func wear_look(code: String) -> void:
	if Registry.skin_state(shown, code) != "owned":
		return
	Save.set_skin_worn(shown.id, "" if code == shown.home_look() else code)
	Analytics.track("skin_worn", {"hero": shown.id, "look": code})
	refresh()


## A look to buy: the shared question takes the pop-up's place (one at a time on a screen); its answer brings the looks back.
func ask_buy_look(code: String) -> void:
	if Registry.skin_state(shown, code) != "buyable":
		return
	var c := shown
	var cur := Currency.of(c.skin_currency(code))
	var price := c.skin_price(code)
	if not Currency.can_afford(cur, price):
		Audio.play("ui_locked")
		var t: Control = looks_grid.get_node_or_null("Look_" + code) if looks_grid else null
		_refuse(t)
		return
	_on_looks_answer("replaced")
	WConfirm.open(self, "Buy this skin?", "%s from your purse. %s wears it from then on." % [Currency.price_words(cur, price),
		SHEET_SCRIPT.hero_name(c)], "Buy · %s" % W.num(price), "Not now", func(): buy_look(c, code), open_looks, "buy",
		WButton.price_parts(price, "BUY", R.MODAL_BUTTON_PX, cur))


## The look bought (the sheet's purchase: Save.buy_skin, the sink "skin"), worn at once, the looks back with a burst.
func buy_look(c: CharacterDef, code: String) -> bool:
	var cur := Currency.of(c.skin_currency(code))
	var price := c.skin_price(code)
	if not Save.buy_skin(c, code):
		Audio.play("ui_locked")
		refresh()
		return false
	Audio.play("ui_buy")
	Analytics.track("skin_bought", {"hero": c.id, "look": code, "price": price, "currency": cur, "balance_after": Currency.balance(cur)})
	Save.set_skin_worn(c.id, code)
	refresh()
	open_looks()
	WCelebrate.burst(self, Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y * 0.5), get_child_count(), 1.2)
	return true


## No: the locked sound and a shake (the tab bar's refused tap).
func _refuse(c: Control) -> void:
	Audio.play("ui_locked")
	if c == null or not is_instance_valid(c):
		return
	var x := c.position.x
	var tw := create_tween()
	for k in 4:
		var s := SHAKE_PX * (1.0 - float(k) / 4.0) * (1.0 if k % 2 == 0 else -1.0)
		tw.tween_property(c, "position:x", x + s, SHAKE_S / 5.0)
	tw.tween_property(c, "position:x", x, SHAKE_S / 5.0)


## DETAILS · ALL STATS: the Hero details pop-up (WHeroSheet) of the shown hero; a look worn or bought on it shows here too.
func open_details() -> void:
	if shown == null or sheet_open():
		return
	_sheet = SHEET_SCRIPT.open(self, shown, not owned(shown))
	_sheet.connect("look_changed", func(_code: String): refresh())


func sheet_open() -> bool:
	return _sheet != null and is_instance_valid(_sheet) and not bool(_sheet.call("is_done"))


## Back (the header's square, the back gesture): the pop-up's question first, then the pop-up, then the title.
func on_back() -> void:
	if sheet_open():
		if not WConfirm.dismiss(_sheet):
			_sheet.call("close")
		return
	if WConfirm.dismiss(self):
		_on_looks_answer("back")
		return
	super.on_back()


# ---------------------------------------------------------------- the finger and the clock

## The two lists' fingers (TouchScroll, each only for a finger that came down on it); nothing moves under the pop-up or a question.
func _input(event: InputEvent) -> void:
	if sheet_open() or WConfirm.is_open(self):
		return
	if _touch:
		_touch.input(event)
	if _grid_touch:
		_grid_touch.input(event)


## The picker fades in with the page (ScreenBase's entrance moves the page).
func _enter() -> void:
	super._enter()
	if picker:
		picker.modulate.a = 0.0
		create_tween().tween_property(picker, "modulate:a", 1.0, 0.2)


## The lists' coast and the hero's run frames (a redraw only when the frame changes).
func _process(delta: float) -> void:
	super._process(delta)
	if _grid_touch:
		_grid_touch.process()
	if _tex == null or _anim_n <= 1 or _sprite == null:
		return
	_clock += delta
	var f := int(_clock * _fps) % _anim_n
	if f != _frame:
		_frame = f
		_sprite.queue_redraw()
