## The title's hero drawer (pass 69, Garry: "a Hero Collections button to the left of the selected hero plaque ... Clicking
## it opens up a kind of a Drawer UI element with the list of all heroes 2 rows tall, it opens up over the hero preview
## animation thing"): a paper panel over the hero's preview with every hero that is not hidden as a badge tile, in two
## rows that scroll sideways when they do not fit (TouchScroll, horizontal). A tap on a tile selects that hero: the
## title shows him and he runs in behind the drawer, which stays open. A tap anywhere outside the panel closes it (the
## catcher under it takes that tap, so nothing behind it fires); the title's button over the catcher, a close X while the
## drawer is open, closes it too; back and Esc close it.
## A tile: the hero's badge in the look he is played in (Registry.played_look) on a round plate and his name under it.
## A hero not owned yet: the badge a black silhouette with a "?" (WPlate.mystery) on an aged tile, and under it his
## price with a coin when he is on sale (his requirement met), LOCKED when it is not. The selected hero's tile is brass.
## No class_name (a new one is unknown to a headless run until the editor rescans): open it with
## preload("res://ui/wanted/WHeroDrawer.gd").open(host, heroes, selected, area).
## Names for tools: "HeroDrawer", "Catcher", "Panel", "Scroll", "Grid", "Tile_<id>" (meta "hero": the CharacterDef).
extends Control

signal picked(hero: CharacterDef)
signal closed

## A tile: the badge's side, the tile's box width, the gap between tiles, the panel's padding.
const BADGE := 112.0
const TILE_W := 140.0
const GAP := 12
const PAD := 22.0
## A tap is a press and a release this close together (WTap's slop).
const SLOP := 40.0
## The drawer's way in: it drops this far while it fades in.
const DROP := 36.0

## The heroes it lists, in order (the title's carousel: Registry.heroes_for_drawer), the one the title shows, and what
## the player stands with each (hero id -> Registry.hero_state, the title's own reading: a previewed hidden hero is
## "locked").
var heroes: Array = []
var selected: CharacterDef
var states: Dictionary = {}
var catcher: Control
var panel: PanelContainer
var scroll: ScrollContainer
var grid: GridContainer
var _touch: TouchScroll
var _tiles: Dictionary = {}
var _done := false
var _down := false
var _from := Vector2.ZERO
var _area := Rect2()


static func open(host: Control, list: Array, sel: CharacterDef, area: Rect2, hero_states: Dictionary = {}) -> Control:
	var d: Control = load("res://ui/wanted/WHeroDrawer.gd").new()
	d.name = "HeroDrawer"
	d.set("heroes", list)
	d.set("selected", sel)
	d.set("states", hero_states)
	d.call("_build")
	host.add_child(d)
	d.call("frame", area)
	d.call("_enter")
	return d


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the drawer itself lets everything through; its catcher and its panel take what lands on them
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("wanted_modal")


func _build() -> void:
	catcher = Control.new()
	catcher.name = "Catcher"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_catcher_input)
	add_child(catcher)
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 8).pad(PAD, PAD - 6.0, PAD, PAD))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var head := WStarLine.make("Heroes", 20, W.INK_SOFT, 0.35)
	head.name = "Head"
	v.add_child(head)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(grid)
	_fill()
	_touch = TouchScroll.new(scroll, true)
	_touch.horizontal = true


## The tiles, two rows: as many columns as half the heroes, rounded up (a row-major grid: the first half on top).
func _fill() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_tiles.clear()
	grid.columns = maxi(int(ceil(heroes.size() / 2.0)), 1)
	for h: CharacterDef in heroes:
		var t := _tile(h)
		grid.add_child(t)
		_tiles[h.id] = t


func _state(h: CharacterDef) -> String:
	return str(states.get(h.id, Registry.hero_state(h)))


func _tile(h: CharacterDef) -> WTap:
	var st := _state(h)
	var owned := st == "owned"
	var t := WTap.new()
	t.name = "Tile_" + h.id
	t.set_meta("hero", h)
	t.custom_minimum_size = Vector2(TILE_W, 0)
	t.box = _tile_box(h, owned)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	var p := WPlate.new().for_def(Registry.played_look(h), BADGE, false, 0)
	p.name = "Badge"
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mystery = not owned
	v.add_child(p)
	var foot: Control
	match st:
		"owned":
			var n := W.slab_text(h.display_name, _name_px(h.display_name), W.INK, HORIZONTAL_ALIGNMENT_CENTER, 28.0)
			n.custom_minimum_size = Vector2(TILE_W - 16.0, 28.0)
			foot = n
		"buyable":
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 6)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.custom_minimum_size.y = 28.0
			row.add_child(WCoin.make(22.0, W.BRASS, 3.0, Currency.of(h.currency_type)))
			var pr := W.slab_text(W.num(h.price), 22, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 28.0)
			pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pr)
			foot = row
		_:
			var l := W.label("Locked", 16, W.ROCK, 0.15)
			l.align = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size = Vector2(TILE_W - 16.0, 28.0)
			l.valign = VERTICAL_ALIGNMENT_CENTER
			foot = l
	foot.name = "Foot"
	v.add_child(foot)
	t.pressed.connect(func(): _pick(h))
	return t


## A tile's box: paper for an owned hero, aged for one still to get, brass for the one the title shows.
func _tile_box(h: CharacterDef, owned: bool) -> HardBox:
	var fill := W.BRASS if selected and h.id == selected.id else (W.PAPER if owned else W.AGED)
	return W.box(fill, 4, 5).pad(8, 10, 8, 8)


## The name as big as fits the tile (Alfa Slab runs about 0.62 em a letter at this size).
static func _name_px(n: String) -> int:
	return clampi(int((TILE_W - 18.0) / maxf(float(n.length()) * 0.62, 1.0)), 15, 22)


func _pick(h: CharacterDef) -> void:
	if _done:
		return
	set_selected(h)
	picked.emit(h)


## Marks `h` as the hero the title shows (his tile brass, the last one's back to its own).
func set_selected(h: CharacterDef) -> void:
	selected = h
	for hh: CharacterDef in heroes:
		var t: WTap = _tiles.get(hh.id)
		if t:
			t.box = _tile_box(hh, _state(hh) == "owned")


## The tile of hero `id` (tools, tests): null when he is not listed.
func tile_of(id: String) -> WTap:
	return _tiles.get(id)


## Lays the panel out in `area` (the title's room over the hero's preview, canvas px): centred across it, its foot on the
## area's foot, never above its top (on a short screen it reaches down over the hero instead); the tiles scroll sideways
## when the grid is wider than the area.
func frame(area: Rect2) -> void:
	_area = area
	var gs := grid.get_combined_minimum_size()
	var inner_w := minf(gs.x, area.size.x - PAD * 2.0)
	scroll.custom_minimum_size = Vector2(inner_w, gs.y)
	panel.reset_size()
	var ps := panel.get_combined_minimum_size()
	var x := area.position.x + (area.size.x - ps.x) * 0.5
	var y := maxf(area.end.y - ps.y, area.position.y)
	panel.position = Vector2(x, y)
	panel.size = ps


## Whether the tiles are wider than the panel (they scroll sideways).
func scrolls() -> bool:
	return grid.get_combined_minimum_size().x > scroll.custom_minimum_size.x + 1.0


# ---------------------------------------------------------------- in and out

func _enter() -> void:
	panel.modulate.a = 0.0
	await get_tree().process_frame
	if _done or not is_inside_tree():
		return
	var y := panel.position.y
	panel.position.y = y - DROP
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "position:y", y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.16)


func close() -> void:
	if _done:
		return
	_done = true
	if _touch:
		_touch.reset()
	catcher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)


func is_done() -> bool:
	return _done


## A tap outside the panel closes the drawer (a drag that ends there does not).
func _on_catcher_input(e: InputEvent) -> void:
	var is_press := false
	var is_release := false
	var pos := Vector2.ZERO
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		is_press = t.pressed
		is_release = not t.pressed
		pos = t.position
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var m := e as InputEventMouseButton
		is_press = m.pressed
		is_release = not m.pressed
		pos = m.position
	else:
		return
	if is_press:
		_down = true
		_from = pos
	elif is_release and _down:
		_down = false
		if pos.distance_to(_from) <= SLOP:
			W.sfx("ui_tap")
			close()


func _input(event: InputEvent) -> void:
	if _done:
		return
	var esc := event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE
	if esc or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if _touch:
		_touch.input(event)


func _process(_delta: float) -> void:
	if _touch and not _done:
		_touch.process()
