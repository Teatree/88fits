## The menu frame (Wanted): a paper wash at 82 % over a still of the desert (art/ui/wanted/menu_backdrop.jpg; plain
## paper when it is missing), the menu header (a 96 px back square at 36, 44, the name in 72 px slab, the gold plate or
## a count top-right), and one board column from y ~200 that scrolls under a finger only when it has to. The wash fades
## in over 200 ms and the board slides up 40 px. Screens fill `content` in build().
class_name ScreenBase
extends Control

const TITLE := "res://ui/TitleScreen.tscn"
const BACKDROP := "res://art/ui/wanted/menu_backdrop.jpg"

var content: VBoxContainer
var margin: MarginContainer
var header: WMenuHeader
var title_label: WText
var scroll: ScrollContainer
var wash: ColorRect
# finger scrolling done by hand (TouchScroll): the drag is read at the viewport before any control can swallow it, so it
# does not matter what the finger lands on (a label, an icon, a card, the gap between rows); a fling coasts and slows
var _touch: TouchScroll


func _ready() -> void:
	# a hub screen never runs paused: a paused tree freezes the list's fade-in and the rows stay invisible
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_backdrop(self)
	wash = W.dim(W.WASH, false)
	add_child(wash)
	if use_header():
		header = WMenuHeader.make("", header_right())
		header.back.connect(on_back)
		add_child(header)
		title_label = header.title
	# the scroll runs the full width and the margins sit inside it, so a seal hanging off a panel's corner is not cut;
	# it starts no higher than the header's foot, so the back square keeps all of its own touches
	var room := board_room()
	scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 0
	scroll.offset_right = 0
	scroll.offset_top = board_top() - room
	scroll.offset_bottom = -board_bottom()
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
	_enter()


## The still of the desert behind every menu, covering the screen (plain paper until it exists).
static func add_backdrop(to: Control) -> void:
	var bg := ColorRect.new()
	bg.color = W.PAPER
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	to.add_child(bg)
	if ResourceLoader.exists(BACKDROP):
		var t := TextureRect.new()
		t.texture = load(BACKDROP)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		to.add_child(t)


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
	ts.tween_property(scroll, "offset_bottom", -board_bottom(), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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


## Room over the board inside the scroll, for a shadow or a seal over the first panel; it starts no higher than the
## header's foot. A screen with a fixed strip over its board (the Collection's tabs) returns 0.
func board_room() -> float:
	return 50.0 if not use_header() else clampf(board_top() - 160.0, 0.0, 50.0)


## The board's side margins (48 on the menus; the results use 60).
func board_side() -> float:
	return 48.0


## Move the board: its top edge and side margins (the Collection's item page sits higher and narrower than its grid).
func set_board(top: float, side: float) -> void:
	scroll.offset_top = top - float(margin.get_theme_constant("margin_top"))
	margin.add_theme_constant_override("margin_left", int(side))
	margin.add_theme_constant_override("margin_right", int(side))
	scroll.scroll_vertical = 0


func set_title(t: String) -> void:
	if title_label:
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


func _input(event: InputEvent) -> void:
	if _touch:
		_touch.input(event)


func _process(_delta: float) -> void:
	if _touch:
		_touch.process()


## Android's back button or gesture: the screen's own back (the title), as Esc does on a PC.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		on_back()
	elif event.is_action_pressed("ui_cancel"):
		on_back()
