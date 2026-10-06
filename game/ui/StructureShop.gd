## The travelling shop (Wanted screen 11): three items priced by how strong they are, bought with the run's gold. The
## price is the button; what the player already holds sits above the wares; a card they cannot afford is aged at 60 %
## with its price in paper ("· 8 short"). One purchase and the stall is spent; LEAVE spends it too.
class_name StructureShop
extends WModal

signal closed(bought: bool)

var _gold_plate: PanelContainer
var _hold_row: HBoxContainer
var _list: VBoxContainer
var _offer: Array = []
var _cards: Array = []
var _done := false


func _ready() -> void:
	build_dim(W.DIM)
	build_header("One visit only", "THE SHOP", "", 120)
	header.line.visible = false
	var gc := CenterContainer.new()
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gc.custom_minimum_size.y = 16 + 88
	_gold_plate = WMenuHeader.gold_plate(0, 56, 50.0, 6, 5)
	gc.add_child(_gold_plate)
	header.add_child(gc)
	# YOU HOLD: 76 px plates in a row at y 470
	_hold_row = HBoxContainer.new()
	_hold_row.add_theme_constant_override("separation", 14)
	_hold_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hold_row.offset_left = 48
	_hold_row.offset_right = -48
	_hold_row.offset_top = 470
	_hold_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hold_row)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 40)
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_list.offset_left = 48
	_list.offset_right = -48
	_list.offset_top = 590
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	var leave := WButton.make(["LEAVE"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	leave.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	leave.offset_left = -215
	leave.offset_right = 215
	leave.offset_bottom = -90
	leave.offset_top = -90 - 108
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
	(_gold_plate.find_child("Amount", true, false) as WText).text = W.num(Run.run_gold)
	for c in _hold_row.get_children():
		c.queue_free()
	_hold_row.add_child(W.label("You hold", 20, W.AGED))
	# each in the colour of the level held (pass 48)
	var held: Array = []
	for w in Run.weapons:
		held.append([(w as WeaponInstance).def, (w as WeaponInstance).level])
	for pid in Run.passives.keys():
		if Registry.passive(pid):
			held.append([Registry.passive(pid), int(Run.passives[pid])])
	for h in held:
		var p := WPlate.new().for_def(h[0], 84.0, false, int(h[1]))
		p.icon_frac = 0.72
		_hold_row.add_child(p)
	for c in _cards:
		(c as Node).queue_free()
	_cards.clear()
	for card in _offer:
		var node := _make_card(card)
		_list.add_child(node)
		_cards.append(node)
	modulate.a = 1.0
	enter()
	Audio.play("ui_card_pick")


func _make_card(card: Dictionary) -> WCard:
	var def: ContentDef = card["def"]
	var price := price_of(card)
	var short := maxi(price - Run.run_gold, 0)
	var o := WItem.options(card, {"plate_px": 160.0, "name_size": 54, "effect_size": 28, "pad": [30, 32, 30, 32],
		"seal_px": 92.0, "icon_frac": 0.72, "stars": [], "price": price, "short": short, "locked": short > 0})
	var c := WCard.make(def, o)
	c.pressed.connect(func(): _buy(card, price, c))
	return c


func _buy(card: Dictionary, price: int, node: WCard) -> void:
	if _done:
		return
	if Run.run_gold < price:
		Audio.play("ui_locked")
		return
	_done = true
	Run.spend_gold(price)
	var line := CardPool.apply(card)
	Audio.play("ui_buy")
	node.show_held(true)
	var tw := create_tween()
	tw.tween_interval(0.16)
	tw.tween_callback(func(): _finish(true, line))


func _finish(bought: bool, line: String = "") -> void:
	visible = false
	if bought and line != "":
		Run.build_changed.emit()
	closed.emit(bought)
