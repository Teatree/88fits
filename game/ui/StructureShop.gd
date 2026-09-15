## The travelling shop found on the map: three random items with prices set by how strong they are. Buy one with
## run gold and the shop is spent; leave and it is spent too (it was a one-time stall).
class_name StructureShop
extends Control

signal closed(bought: bool)

var _title: Label
var _gold: Label
var _list: VBoxContainer
var _box: VBoxContainer
var _offer: Array = []
var _done := false


func _ready() -> void:
	UiKit.fullscreen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.86))
	# three bands anchored to the screen: header, the scrolling list, the way out. Anchors, not a stack, so the
	# list can never push the buttons off the bottom no matter how tall its cards report themselves.
	_box = UiKit.vbox(10)
	_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_box.offset_left = 50
	_box.offset_right = -50
	_box.offset_top = 120
	_box.offset_bottom = 330
	add_child(_box)
	var head := UiKit.hbox(10)
	_title = UiKit.outline(UiKit.label("TRAVELLING SHOP", 84, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 8)
	head.add_child(_title)
	var x := UiKit.button("✕", 40, false, 90)
	x.custom_minimum_size = Vector2(90, 90)
	x.size_flags_horizontal = Control.SIZE_SHRINK_END
	x.pressed.connect(func(): _finish(false))
	head.add_child(x)
	_box.add_child(head)
	_gold = UiKit.label("", 34, UiKit.INK2, HORIZONTAL_ALIGNMENT_CENTER)
	_box.add_child(_gold)
	_list = UiKit.vbox(26)
	var sc := UiKit.scroll(_list)
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 50
	sc.offset_right = -50
	sc.offset_top = 340
	sc.offset_bottom = -220
	add_child(sc)
	var leave := UiKit.button("Leave without buying", 40, false, 110)
	leave.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	leave.offset_left = 50
	leave.offset_right = -50
	leave.offset_top = -190
	leave.offset_bottom = -80
	leave.pressed.connect(func(): _finish(false))
	add_child(leave)


## Price by power: rarity sets the base, each level already held adds a third, passives are a touch cheaper.
static func price_of(card: Dictionary) -> int:
	var def: ContentDef = card["def"]
	# gold is scarce (a coin every twenty kills or so, a few dozen per run): a new common item costs about a dozen
	var base: int = int({"common": 12, "rare": 20, "epic": 32}.get(def.rarity, 15))
	var p := float(base) * (1.0 + 0.25 * float(card.get("level_from", 0)))
	if def is PassiveDef:
		p *= 0.8
	return maxi(int(round(p)), 6)


func open(offer: Array) -> void:
	_offer = offer
	_done = false
	for c in _list.get_children():
		c.queue_free()
	_gold.text = "You have %d gold" % Run.run_gold
	for card in _offer:
		_list.add_child(_make_card(card))
	visible = true
	UiFx.enter(self, _box)
	UiFx.stagger(_list, 0.06)
	Audio.play("ui_card_pick")


func _make_card(card: Dictionary) -> Control:
	var def: ContentDef = card["def"]
	var kind := "weapon" if def is WeaponDef else "passive"
	var col: Color = UiKit.TYPE_COLORS.get(kind, UiKit.ACCENT)
	var price := price_of(card)
	var can: bool = Run.run_gold >= price
	var b := UiKit.card(col if can else UiKit.LINE, 3 if can else 2, UiKit.BG2 if can else UiKit.BG, 30)
	var v := UiKit.card_body(b, def, kind, 130, [[UiKit.card_tag(card), 22, col], [def.display_name, 44, UiKit.INK if can else UiKit.INK3], [UiKit.card_description(card), 26, UiKit.INK2 if can else UiKit.INK3]])
	var pl := UiKit.label(("%d gold" % price) if can else ("%d gold · not enough" % price), 30, UiKit.ACCENT if can else UiKit.DANGER)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pl)
	b.pressed.connect(func(): _buy(card, price, b))
	return b


func _buy(card: Dictionary, price: int, node: Control) -> void:
	if _done:
		return
	if Run.run_gold < price:
		Audio.play("ui_locked")
		UiFx.punch(node, 0.97, 0.12)
		return
	_done = true
	Run.spend_gold(price)
	var line := CardPool.apply(card)
	Audio.play("ui_buy")
	UiFx.punch(node, 1.04, 0.14)
	var tw := create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(func(): _finish(true, line))


func _finish(bought: bool, line: String = "") -> void:
	visible = false
	if bought and line != "":
		Run.build_changed.emit()
	closed.emit(bought)
