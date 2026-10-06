## The debug hand: a list of every weapon, evolution, line, passive, perk and mutation in the game, with a level box
## beside each one (a line is handed over as the passive it is, pass 47), opened from a small button on the level-up screen. Tap a few, set how many levels of each, and
## "Give" hands them over and closes. For trying a build out without playing to it.
class_name DebugHand
extends Control

signal given

var _list: VBoxContainer
var _scroll: ScrollContainer
var _picked: Dictionary = {}   # id -> {"kind", "def", "n"}
var _touch: TouchScroll


func _ready() -> void:
	UiKit.fullscreen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.92))
	var v := UiKit.vbox(12)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 30
	v.offset_right = -30
	v.offset_top = 60 + W.safe_top()
	v.offset_bottom = -40
	add_child(v)
	var head := UiKit.hbox(14)
	head.add_child(UiKit.label("DEBUG · give me", 40, UiKit.INK))
	var close := UiKit.button("Close", 26, false, 66)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	v.add_child(head)
	_list = UiKit.vbox(8)
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll = UiKit.scroll(_list)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_scroll)
	_touch = TouchScroll.new(_scroll)
	var give := UiKit.button("Give", 34, true, 84)
	give.pressed.connect(_give)
	v.add_child(give)


func open() -> void:
	_picked.clear()
	_rebuild()
	visible = true


func _rows() -> Array:
	var out: Array = []
	for w: WeaponDef in Registry.weapons.values():
		out.append(["evolution" if w.is_evolution else "weapon", w])
	for p: PassiveDef in Registry.passives.values():
		out.append(["line" if W.is_line(p) else "passive", p])
	for pk: PerkDef in Registry.perks.values():
		out.append(["perk", pk])
	for m: MutationDef in Registry.mutations.values():
		out.append(["mutation", m])
	out.sort_custom(func(a, b): return str(a[0]) + str((a[1] as ContentDef).display_name) < str(b[0]) + str((b[1] as ContentDef).display_name))
	return out


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for row in _rows():
		var kind: String = row[0]
		var def: ContentDef = row[1]
		var p := UiKit.panel(UiKit.BG2, 16, UiKit.LINE, 2)
		var h := UiKit.hbox(10)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		p.add_child(h)
		var pick := UiKit.button("+", 26, false, 56)
		pick.custom_minimum_size = Vector2(70, 56)
		var name_l := UiKit.label("%s · %s" % [kind.substr(0, 3).to_upper(), def.display_name], 26, UiKit.INK)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var count_l := UiKit.label("0", 26, UiKit.ACCENT)
		count_l.custom_minimum_size = Vector2(46, 0)
		var minus := UiKit.button("−", 26, false, 56)
		minus.custom_minimum_size = Vector2(70, 56)
		pick.pressed.connect(func():
			var e: Dictionary = _picked.get(def.id, {"kind": kind, "def": def, "n": 0})
			e["n"] = int(e["n"]) + 1
			_picked[def.id] = e
			count_l.text = str(e["n"])
			Audio.play("ui_tap"))
		minus.pressed.connect(func():
			var e: Dictionary = _picked.get(def.id, {"kind": kind, "def": def, "n": 0})
			e["n"] = maxi(int(e["n"]) - 1, 0)
			_picked[def.id] = e
			count_l.text = str(e["n"]))
		h.add_child(minus)
		h.add_child(count_l)
		h.add_child(name_l)
		h.add_child(pick)
		_list.add_child(p)


func _give() -> void:
	for id in _picked.keys():
		var e: Dictionary = _picked[id]
		var n: int = int(e["n"])
		if n <= 0:
			continue
		match str(e["kind"]):
			"weapon", "evolution":
				var w: WeaponDef = e["def"]
				if Run.weapon_instance(w.id) == null:
					Run.add_weapon(w, 1)
				for k in range(n - 1):
					Run.level_weapon(w.id)
			"passive", "line":
				for k in range(n):
					Run.add_or_level_passive(str(id))
			"perk":
				Run.add_perk(str(id))
			"mutation":
				Run.add_mutation(str(id), true)
	Run.rebuild_sheets()
	visible = false
	given.emit()


func _input(event: InputEvent) -> void:
	if visible and _touch:
		_touch.input(event)


func _process(_delta: float) -> void:
	if visible and _touch:
		_touch.process()
