## A chest was opened: the game pauses and one reel spins for four seconds past the run's items before it lands on
## what the chest holds. Then two choices: take it, or sell it for a fifth of its shop price.
class_name ChestScreen
extends Control

signal closed(take: bool)

const SPIN := 4.0
const CELL := 320
const GAP := 26
const STEP := CELL + GAP
const CELLS := 28

var _box: VBoxContainer
var _title: Label
var _window: Control
var _reel: VBoxContainer
var _frame: Panel
var _name: Label
var _desc: Label
var _tag: Label
var _buttons: HBoxContainer
var _sell_btn: Button
var _take_btn: Button
var _result: Dictionary = {}
var _sell_gold := 0
var _spinning := false
var _reel_y := 0.0
var _last_cell := -1
var _tw: Tween


func _ready() -> void:
	UiKit.fullscreen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.86))
	_box = UiKit.vbox(10)
	_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_box.offset_left = 50
	_box.offset_right = -50
	_box.offset_top = 150
	_box.offset_bottom = 330
	add_child(_box)
	_title = UiKit.outline(UiKit.label("CHEST!", 96, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 8)
	_box.add_child(_title)
	_tag = UiKit.label("what's inside?", 32, UiKit.INK2, HORIZONTAL_ALIGNMENT_CENTER)
	_box.add_child(_tag)
	# the machine: a framed window one cell tall, the reel is a column of icons sliding up behind it
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.BG, 36, UiKit.ACCENT, 6, true, false, false))
	_frame.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_frame.offset_top = 420
	_frame.offset_bottom = 420 + CELL + 70
	_frame.offset_left = -(CELL + 70) / 2
	_frame.offset_right = (CELL + 70) / 2
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_window = Control.new()
	_window.clip_contents = true
	_window.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_window.offset_top = 455
	_window.offset_bottom = 455 + CELL
	_window.offset_left = -CELL / 2
	_window.offset_right = CELL / 2
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	_reel = UiKit.vbox(GAP)
	_reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_reel)
	# two pointers either side of the window
	for side in [-1, 1]:
		var p := UiKit.outline(UiKit.label("▶" if side < 0 else "◀", 44, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 5)
		p.set_anchors_preset(Control.PRESET_CENTER_TOP)
		p.offset_top = 455 + CELL / 2 - 30
		p.offset_bottom = 455 + CELL / 2 + 30
		p.offset_left = side * (CELL / 2 + 60) - 40
		p.offset_right = side * (CELL / 2 + 60) + 40
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(p)
	# the result: name and what it does
	var res := UiKit.vbox(8)
	res.set_anchors_preset(Control.PRESET_TOP_WIDE)
	res.offset_left = 70
	res.offset_right = -70
	res.offset_top = 420 + CELL + 110
	res.offset_bottom = 420 + CELL + 420
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(res)
	_name = UiKit.outline(UiKit.label("", 56, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER), 6)
	res.add_child(_name)
	_desc = UiKit.label("", 30, UiKit.INK2, HORIZONTAL_ALIGNMENT_CENTER)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res.add_child(_desc)
	_buttons = UiKit.hbox(20)
	_buttons.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_buttons.offset_left = 50
	_buttons.offset_right = -50
	_buttons.offset_top = -200
	_buttons.offset_bottom = -80
	add_child(_buttons)
	_sell_btn = UiKit.button("Sell it", 36, false, 120)
	_sell_btn.pressed.connect(func(): _finish(false))
	_take_btn = UiKit.button("Take it", 40, true, 120)
	_take_btn.pressed.connect(func(): _finish(true))
	_buttons.add_child(_sell_btn)
	_buttons.add_child(_take_btn)


## Opens on a roll from Run.chest_roll and spins the reel; the outcome is fixed before the first frame.
func open(result: Dictionary) -> void:
	_result = result
	_spinning = true
	_last_cell = -1
	_name.text = ""
	_desc.text = ""
	_tag.text = "what's inside?"
	_buttons.visible = false
	_name.visible = false
	_desc.visible = false
	for c in _reel.get_children():
		c.queue_free()
	var kind := str(result.get("type", "gold"))
	var def: ContentDef = result.get("def")
	_sell_gold = 0
	if def:
		_sell_gold = maxi(int(round(StructureShop.price_of(result) * 0.2)), 1)
	# filler: the run's own items and whatever else is unlocked, so the reel looks like it could land anywhere
	var pool: Array = []
	for w in Registry.unlocked_weapons():
		pool.append(w)
	for p in Registry.unlocked_passives():
		pool.append(p)
	for wi in Run.weapons:
		pool.append(wi.def)
	pool.shuffle()
	for k in range(CELLS - 1):
		if pool.is_empty():
			_reel.add_child(_cell(null, "gold"))
		else:
			var d: ContentDef = pool[k % pool.size()]
			_reel.add_child(_cell(d, "weapon" if d is WeaponDef else "passive"))
	_reel.add_child(_cell(def, kind))
	_reel.position = Vector2.ZERO
	_reel_y = 0.0
	visible = true
	UiFx.enter(self, _box)
	Audio.play("pk_chest_open")
	# fast at first, crawling at the end, a little bounce back onto the last cell
	_tw = create_tween()
	_tw.tween_method(_set_reel, 0.0, float(CELLS - 1) * STEP + 34.0, SPIN).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_set_reel, float(CELLS - 1) * STEP + 34.0, float(CELLS - 1) * STEP, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(_land)


## A tap anywhere while the reel spins hurries it along (four times the speed, the landing bounce included).
func _input(event: InputEvent) -> void:
	if not visible or not _spinning or _tw == null or not _tw.is_valid():
		return
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if tap:
		_tw.set_speed_scale(4.0)
		_tag.text = "hurrying…"
		Audio.play("ui_tap")


func _set_reel(y: float) -> void:
	_reel_y = y
	_reel.position.y = -y
	var cell := int((y + STEP * 0.5) / STEP)
	if cell != _last_cell:
		_last_cell = cell
		Audio.play("ui_tap")


func _land() -> void:
	_spinning = false
	var kind := str(_result.get("type", "gold"))
	var def: ContentDef = _result.get("def")
	if def:
		if kind == "evolution":
			_tag.text = "EVOLUTION!"
			_name.text = def.display_name
			var tmp := WeaponInstance.new(def, 1)
			tmp.rebuild(Run.player_sheet, Run.weapons)
			_desc.text = tmp.description()
		else:
			_tag.text = UiKit.card_tag(_result)
			_name.text = def.display_name
			_desc.text = UiKit.card_description(_result)
	else:
		_tag.text = "GOLD"
		_name.text = "+%d gold" % int(_result.get("gold", 50))
		_desc.text = "Straight into the purse."
	_name.visible = true
	_desc.visible = true
	UiFx.pop(_name, 0.0, 0.7, 0.35)
	UiFx.pop(_desc, 0.08, 0.9, 0.3)
	UiFx.punch(_frame, 1.06, 0.2)
	Audio.play("w_evo_reveal" if kind == "evolution" else "ui_levelup")
	_sell_btn.visible = def != null
	_sell_btn.text = "Sell it · +%d gold" % _sell_gold
	_buttons.visible = true
	UiFx.stagger(_buttons, 0.08)


func _cell(def: ContentDef, kind: String) -> Control:
	if def:
		return UiKit.icon_view(def, CELL, kind)
	var root := Control.new()
	root.custom_minimum_size = Vector2(CELL, CELL)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := Panel.new()
	plate.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.ACCENT.darkened(0.55), CELL / 5, UiKit.ACCENT, 8, true, false, false))
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	var l := UiKit.outline(UiKit.label("$", int(CELL * 0.55), UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 6)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return root


func sell_gold() -> int:
	return _sell_gold


func result() -> Dictionary:
	return _result


func _finish(take: bool) -> void:
	if _spinning:
		return
	_spinning = true
	UiFx.punch(_take_btn if take else _sell_btn, 1.05, 0.12)
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func():
		visible = false
		closed.emit(take))
