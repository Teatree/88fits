## The menu frame: the menu backdrop under a dark overlay (below), the menu header (a 96 px back square at 36, 44, the name in 72 px slab, the gold plate or
## a count top-right), and one board column from y ~200 that scrolls under a finger only when it has to. The wash fades
## in over 200 ms and the board slides up 40 px. Screens fill `content` in build().
## Pass 123 (lane KIT2), under Royale: the menu backdrop (lane BACKDROP's
## res://ui/wanted/RoyaleBackdrop.gd, kind backdrop_kind(); the README's sunset drawn plainly while that file is missing)
## under a dark overlay of backdrop_dim() in place of the paper wash (it fades in the same 200 ms); the header the mocks'
## (WMenuHeader: a slate back square, the name in cream Ultra 64 in capitals, the wallet a black plate); and, for a
## screen whose tab_bar() names its tab, the docked tab bar at the foot (res://ui/wanted/WTabBar.gd), the board's scroll
## ending above it (bottom_total() = board_bottom() + tab_bar_height()). solid_sheet() is the solid slate board a page
## can sit on (Garry: "a more solid background, not just hover in the air").
class_name ScreenBase
extends Control

const TITLE := "res://ui/TitleScreen.tscn"
## Pass 123 (lane KIT2): the Royale backdrop (lane BACKDROP's; no class_name, loaded by path) and the tab bar.
const ROYALE_BACKDROP := "res://ui/wanted/RoyaleBackdrop.gd"
const TAB_BAR := "res://ui/wanted/WTabBar.gd"
## The README's menu sunset (#120C3A -> #FFD27A over the sky, #2A1430 -> #0C0918 on the ground from 57 % down), drawn
## while RoyaleBackdrop.gd is missing: [offset 0..1, colour].
const SUNSET := [[0.0, Color("120c3a")], [0.28, Color("2d1a5a")], [0.48, Color("7a2a5a")], [0.57, Color("d8513f")]]
const SUNSET_GROUND := [[0.57, Color("2a1430")], [1.0, Color("0c0918")]]
## The dark overlay over the Royale backdrop behind a screen of panels (backdrop_dim()'s default).
const ROYALE_DIM := 0.25
## The board sheet's border (px); the scroll never starts above its inner edge (scroll_top, pass 128).
const SHEET_EDGE := 3

var content: VBoxContainer
var margin: MarginContainer
var header: WMenuHeader
var title_label: WText
var scroll: ScrollContainer
var wash: ColorRect
## Pass 123 (lane KIT2): the backdrop add_backdrop made (the Royale one, or the Wanted still / paper), and the tab bar
## (Royale, when tab_bar() names a tab; else null).
var backdrop: Control
var tab_bar_node: Control
var board_sheet_node: Panel
# finger scrolling done by hand (TouchScroll): the drag is read at the viewport before any control can swallow it, so it
# does not matter what the finger lands on (a label, an icon, a card, the gap between rows); a fling coasts and slows
var _touch: TouchScroll


func _ready() -> void:
	# a hub screen never runs paused: a paused tree freezes the list's fade-in and the rows stay invisible
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = add_backdrop(self, backdrop_kind())
	# pass 123 (lane KIT2): under Royale a dark overlay in place of the paper wash (the same fade in)
	wash = W.dim(Color(0, 0, 0, backdrop_dim()), false)
	add_child(wash)
	if board_sheet():
		_add_board_sheet()
	if tab_bar() != "" and ResourceLoader.exists(TAB_BAR):
		var bar_script = load(TAB_BAR)
		tab_bar_node = bar_script.make(tab_bar())
	if use_header():
		header = WMenuHeader.make("", header_right())
		header.back.connect(on_back)
		add_child(header)
		title_label = header.title
	# the scroll runs the full width and the margins sit inside it, so a seal hanging off a panel's corner is not cut;
	# it starts no higher than the header's foot, so the back square keeps all of its own touches
	# pass 128: and no higher than the sheet's inner top edge (scroll_top): the room over the board is what is left
	var room := board_top() - scroll_top()
	scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 0
	scroll.offset_right = 0
	scroll.offset_top = scroll_top() + W.safe_top()
	scroll.offset_bottom = -bottom_total()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(board_side()))
	margin.add_theme_constant_override("margin_right", int(board_side()))
	margin.add_theme_constant_override("margin_top", int(room))
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 30)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(content)
	_touch = TouchScroll.new(scroll)
	build()
	# the header over everything a screen built (pass 48: the Collection's tabs sat over its back square on a phone
	# with a camera cutout): nothing ever covers the back button
	if header:
		move_child(header, get_child_count() - 1)
	# pass 123: the tab bar over the board (it ends above the bar; the open tab rises over the board's foot)
	if tab_bar_node:
		add_child(tab_bar_node)
	_enter()


## The still of the desert behind every menu, covering the screen (plain paper until it exists). Pass 123 (lane KIT2):
## returns what it laid last; under Royale the menu backdrop of `kind` ("menu", or "title" for the main menu: lane
## BACKDROP's RoyaleBackdrop, named "RoyaleBackdrop"; its set_dim darkens it) or, while that file is missing, the
## README's sunset drawn plainly.
static func add_backdrop(to: Control, kind: String = "menu") -> Control:
	var bd: Control = null
	if ResourceLoader.exists(ROYALE_BACKDROP):
		var bd_script = load(ROYALE_BACKDROP)
		bd = bd_script.make(kind)
	if bd == null:
		bd = sunset_backdrop()
	bd.name = "RoyaleBackdrop"
	to.add_child(bd)
	return bd


## The README's menu sunset as plain bands (pass 123): the fallback while lane BACKDROP's painted one is missing.
static func sunset_backdrop() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		for stops: Array in [SUNSET, SUNSET_GROUND]:
			for k in range(stops.size() - 1):
				var a: Array = stops[k]
				var b: Array = stops[k + 1]
				var y0 := c.size.y * float(a[0])
				var y1 := c.size.y * float(b[0])
				c.draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(c.size.x, y0), Vector2(c.size.x, y1), Vector2(0, y1)]),
					PackedColorArray([a[1], a[1], b[1], b[1]])))
	return c


## The menu motion: the wash fades in over 200 ms, the board slides up 40 px.
func _enter() -> void:
	wash.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(wash, "modulate:a", 1.0, 0.2)
	var top := scroll.offset_top
	scroll.offset_top = top + 40.0
	scroll.offset_bottom -= -40.0
	scroll.modulate.a = 0.0
	var ts := create_tween().set_parallel(true)
	ts.tween_property(scroll, "offset_top", top, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ts.tween_property(scroll, "offset_bottom", -bottom_total(), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ts.tween_property(scroll, "modulate:a", 1.0, 0.2)


## Screens override these.
func build() -> void:
	pass


func use_header() -> bool:
	return true


func header_right() -> Control:
	return null


func board_top() -> float:
	return 200.0


func board_bottom() -> float:
	return 40.0


## Pass 123 (lane KIT2), Royale only: the tab this screen opens in the docked tab bar ("heroes", "battle", "upgrade",
## "collections"; "" = no bar, the default). Garry: "Keep the tab bar on all four hub screens".
func tab_bar() -> String:
	return ""


## Pass 123, Royale only: the backdrop's kind ("menu"; the main menu's is "title") and the dark overlay over it (0 .. 1;
## ROYALE_DIM for a screen of panels).
func backdrop_kind() -> String:
	return "menu"


func backdrop_dim() -> float:
	return ROYALE_DIM


## Pass 123 (Garry on Results and the Collection: "needs the half transparent bg otherwise it looks like the whole thing is
## hovering over air"; on Heroes: "Add a half transparent bg over the vista"): under Royale a half-transparent navy sheet
## over the backdrop and under the board, from the board's top to its foot; false for a screen with none.
func board_sheet() -> bool:
	return true


func _add_board_sheet() -> void:
	board_sheet_node = Panel.new()
	board_sheet_node.name = "BoardSheet"
	board_sheet_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = R.SHEET
	sb.border_color = R.SHEET_EDGE
	sb.set_border_width_all(SHEET_EDGE)
	sb.set_corner_radius_all(R.RADIUS_TAB)
	sb.anti_aliasing = true
	board_sheet_node.add_theme_stylebox_override("panel", sb)
	board_sheet_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := sheet_insets()
	board_sheet_node.offset_left = inset.position.x
	board_sheet_node.offset_top = inset.position.y
	board_sheet_node.offset_right = -inset.size.x
	board_sheet_node.offset_bottom = -inset.size.y
	add_child(board_sheet_node)


## The sheet's margins (left, top, right, bottom in px; a Rect2 for the four): the board's rect and a little room.
func sheet_insets() -> Rect2:
	var side := maxf(board_side() - 20.0, 10.0)
	return Rect2(side, board_top() + W.safe_top() - 18.0, side, bottom_total() - 8.0)


## Whether a tab bar sits at the foot (pass 123: Royale, a tab named).
func has_tab_bar() -> bool:
	return tab_bar_node != null or (tab_bar() != "" and ResourceLoader.exists(TAB_BAR))


## The tab bar's band over the screen's foot (its gesture-bar inset with it; 0 without a bar).
func tab_bar_height() -> float:
	if not has_tab_bar():
		return 0.0
	var bar_script = load(TAB_BAR)
	return float(bar_script.height())


## What the board's scroll keeps clear at the foot: board_bottom() and the tab bar's band.
func bottom_total() -> float:
	return board_bottom() + tab_bar_height()


## The board's visible height: from its top (board_top, the cutout's inset with it) to the scroll's foot (pass 123).
func visible_board_height() -> float:
	var vh := get_viewport_rect().size.y if is_inside_tree() else 1920.0
	var mb := float(margin.get_theme_constant("margin_bottom")) if margin else 20.0
	return maxf(vh - board_top() - W.safe_top() - bottom_total() - mb - float(R.PANEL_BASE), 0.0)


## A solid slate sheet a page sits on (pass 123, lane KIT2; Garry on the Collection's item page: "Make it sit on a more
## solid background, not just hover in the air"): W.sheet_box(pad) at least the board's visible height, so a short page
## still fills one sheet. Put the page's rows in it (a VBox of cards; W.cell_box for the cells inside) and add it to
## `content`. Under Wanted the same box is ScreenBase.board's paper.
func solid_sheet(pad: Vector2 = Vector2(24, 24)) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Sheet"
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", W.sheet_box(pad))
	p.custom_minimum_size.y = visible_board_height()
	return p


## Room over the board inside the scroll, for a shadow or a seal over the first panel; it starts no higher than the
## header's foot. A screen with a fixed strip over its board (the Collection's tabs) returns 0.
func board_room() -> float:
	return 50.0 if not use_header() else clampf(board_top() - 160.0, 0.0, 50.0)


## Pass 128: where the scroll's rect starts (design px, before the cutout's inset): board_room() over the board, but on a
## board sheet never above the sheet's inner top edge. Scrolled content used to show in the band between the two, over
## the bare backdrop, and was then cut by a straight line (the Outlaws screen's running figure lost his head outside the
## sheet). The page starts where it did at rest: the margin over the board is board_top() - scroll_top().
func scroll_top() -> float:
	var top := board_top() - board_room()
	if board_sheet():
		top = maxf(top, sheet_insets().position.y - W.safe_top() + float(SHEET_EDGE))
	return minf(top, board_top())


## The board's side margins (48 on the menus; the results use 60).
func board_side() -> float:
	return 48.0


## Move the board: its top edge (in the design's px, the safe-area inset added as _ready adds it: pass 48, it was
## dropped, and on a phone with a camera cutout the Collection's board slid up over its back button) and side margins
## (the Collection's item page sits higher and narrower than its grid).
func set_board(top: float, side: float) -> void:
	scroll.offset_top = top - float(margin.get_theme_constant("margin_top")) + W.safe_top()
	margin.add_theme_constant_override("margin_left", int(side))
	margin.add_theme_constant_override("margin_right", int(side))
	scroll.scroll_vertical = 0


## The screen's name in the header (pass 123: through WMenuHeader.set_title, which under Royale sets it in capitals and
## shrinks it to the room left of the wallet; under Wanted it is the plain text as before).
func set_title(t: String) -> void:
	if header:
		header.set_title(t)
	elif title_label:
		title_label.text = t


func on_back() -> void:
	go(TITLE)


func go(path: String) -> void:
	UiFx.go(get_tree(), path)


func clear_content() -> void:
	for c in content.get_children():
		c.queue_free()


## A board: paper with a 5 px ink border and an 8 px hard shadow (the menu panels).
static func board(pad: Vector2 = Vector2(30, 30), shadow: int = 8, border: int = 5) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, border, shadow).pad(pad.x + border, pad.y + border, pad.x + border, pad.y + border))
	return p


## A question up (WConfirm, pass 45) keeps the board still: a drag that lands on its card does not scroll what is beneath.
func _input(event: InputEvent) -> void:
	if _touch and not WConfirm.is_open(self):
		_touch.input(event)


func _process(_delta: float) -> void:
	if _touch:
		_touch.process()


## Android's back button or gesture: a question up is cancelled, else the screen's own back (the title), as Esc does
## on a PC.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not WConfirm.dismiss(self):
			on_back()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or event.is_action_pressed("ui_cancel"):
		if not WConfirm.dismiss(self):
			on_back()
