## Level-up and starter pick. Full-width stacked cards, generated text, reroll / skip / banish.
class_name CardScreen
extends Control

signal chosen(card: Dictionary)

var _title: Label
var _list: VBoxContainer
var _buttons: HBoxContainer
var _offer: Array = []
var _starter := false
var _banish_mode := false
var _hint: Label
var _reroll_btn: Button
var _skip_btn: Button
var _banish_btn: Button
var _box: VBoxContainer
var _picking := false


func _ready() -> void:
	UiKit.fullscreen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.86))
	# header, list and buttons are anchored bands: the list scrolls inside its space and the buttons stay on screen
	_box = UiKit.vbox(12)
	_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_box.offset_left = 50
	_box.offset_right = -50
	_box.offset_top = 140
	_box.offset_bottom = 330
	add_child(_box)
	_title = UiKit.outline(UiKit.label("LEVEL UP!", 96, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 8)
	_box.add_child(_title)
	_hint = UiKit.label("pick one", 32, UiKit.INK2, HORIZONTAL_ALIGNMENT_CENTER)
	_box.add_child(_hint)
	_list = UiKit.vbox(26)
	var sc := UiKit.scroll(_list)
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 50
	sc.offset_right = -50
	sc.offset_top = 340
	sc.offset_bottom = -210
	add_child(sc)
	_buttons = UiKit.hbox(20)
	_buttons.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_buttons.offset_left = 50
	_buttons.offset_right = -50
	_buttons.offset_top = -180
	_buttons.offset_bottom = -80
	_reroll_btn = UiKit.button("Reroll", 32, false, 96)
	_skip_btn = UiKit.button("Skip +10", 32, false, 96)
	_banish_btn = UiKit.button("Banish", 32, false, 96)
	_reroll_btn.pressed.connect(_reroll)
	_skip_btn.pressed.connect(func(): _finish({"skipped": true}))
	_banish_btn.pressed.connect(_toggle_banish)
	_buttons.add_child(_reroll_btn)
	_buttons.add_child(_skip_btn)
	_buttons.add_child(_banish_btn)
	add_child(_buttons)


func show_offer(offer: Array, title: String, starter: bool, with_hints: bool) -> void:
	_offer = offer
	_starter = starter
	_banish_mode = false
	_title.text = title
	_hint.text = "pick your first weapon" if starter else "pick one · game is paused"
	_buttons.visible = not starter
	_refresh_buttons()
	_rebuild(with_hints)
	_picking = false
	visible = true
	UiFx.enter(self, _box)
	Audio.play("ui_card_pick")


func _refresh_buttons() -> void:
	_reroll_btn.text = "Reroll ×%d" % Run.rerolls_left
	_reroll_btn.disabled = Run.rerolls_left <= 0
	_skip_btn.disabled = Run.skips_left <= 0
	_banish_btn.text = ("Banishing…" if _banish_mode else "Banish ×%d" % Run.banishes_left)
	_banish_btn.disabled = Run.banishes_left <= 0


func _rebuild(with_hints: bool) -> void:
	for c in _list.get_children():
		c.queue_free()
	for card in _offer:
		_list.add_child(_make_card(card, with_hints))
	UiFx.stagger(_list, 0.06)


func _make_card(card: Dictionary, with_hints: bool) -> Control:
	var def: ContentDef = card["def"]
	var is_fav := bool(card.get("favourite", false))
	var kind := "weapon" if def is WeaponDef else "passive"
	var col: Color = UiKit.TYPE_COLORS.get(kind, UiKit.ACCENT)
	var border := col if is_fav or _banish_mode else UiKit.LINE
	var b := UiKit.card(border, 5 if is_fav or _banish_mode else 2, UiKit.BG2, 30)
	b.pressed.connect(func(): _pick(card, b))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 26)
	m.add_theme_constant_override("margin_right", 26)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 20)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var h := UiKit.hbox(24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var icon := UiKit.icon_view(def, 150, kind)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := UiKit.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tag := UiKit.card_tag(card)
	if is_fav:
		tag += " · FAVOURITE"
	var tl := UiKit.label(tag, 22, col)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tl)
	var nl := UiKit.label(def.display_name, 46, UiKit.INK)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var desc := UiKit.card_description(card)
	if is_fav and Run.character:
		var fb: Dictionary = Run.character.favourite_bonus
		if str(fb.get("type", "")) == "level":
			desc += " Starts at level %d." % int(fb.get("value", 2))
		elif fb.has("effects"):
			desc += " Bonus: " + TextGen.describe_effects(fb["effects"]) + "."
	if with_hints and _starter and def is WeaponDef:
		match def.targeting:
			"forward":
				desc += "  Fires where you face, so steering aims it."
			"orbit":
				desc += "  Protects you while you move."
			_:
				desc += "  Aims itself at the nearest enemy."
	elif with_hints and not _starter:
		desc += "  (%s)" % ("Weapons go in the top-left row." if kind == "weapon" else "Passives go in the top-right row and boost everything.")
	var dl := UiKit.label(desc, 28, UiKit.INK2)
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dl)
	if def.flavour != "" and not with_hints:
		var fl := UiKit.label(def.flavour, 22, UiKit.INK3)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(fl)
	h.add_child(v)
	return b


func _pick(card: Dictionary, button: Control = null) -> void:
	if _picking:
		return
	if _banish_mode:
		Run.banished.append(card["id"])
		Run.banishes_left -= 1
		_banish_mode = false
		_offer = CardPool.level_up_offer(_offer.size())
		_refresh_buttons()
		_rebuild(false)
		if _offer.is_empty():
			_finish({"skipped": true})
		return
	_picking = true
	if button:
		UiFx.punch(button, 1.04, 0.14)
	var tw := create_tween()
	tw.tween_interval(0.14)
	tw.tween_callback(func(): _finish(card))


func _finish(card: Dictionary) -> void:
	visible = false
	Audio.play("ui_card_pick")
	chosen.emit(card)


func _reroll() -> void:
	if Run.rerolls_left <= 0:
		return
	Run.rerolls_left -= 1
	_offer = CardPool.level_up_offer(_offer.size())
	_refresh_buttons()
	_rebuild(false)


func _toggle_banish() -> void:
	if Run.banishes_left <= 0:
		return
	_banish_mode = not _banish_mode
	_hint.text = "tap a card to banish it from this run" if _banish_mode else "pick one · game is paused"
	_refresh_buttons()
	_rebuild(false)
