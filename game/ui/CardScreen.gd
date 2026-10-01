## Level-up, path offer and starter pick, "Wanted" (screens 07 and 08). The run dims to sepia; a star line, a slab title
## and one dry line head the screen; the offers are item cards (kind by plate colour and one word, rarity by seal, level
## by stars, one effect line); REROLL / SKIP / BANISH sit in the bottom row. A path offer puts the weapon on top with its
## path rivets, three mutation cards under it and a single SKIP. The card a finger holds sits on its shadow with a brass
## band; the pick is remembered (`last_pick`) so the gate can fly it to its HUD slot.
class_name CardScreen
extends WModal

signal chosen(card: Dictionary)

var _offer: Array = []
var _starter := false
var _banish_mode := false
var _picking := false
var path_mode := false
## The card taken last: {def, rect} (the gate flies it to the slot it lands in).
var last_pick: Dictionary = {}
var _list: VBoxContainer
var _cards: Array = []
var _slots: Array = []
var _path_head: VBoxContainer
var _reroll_btn: WButton
var _skip_btn: WButton
var _banish_btn: WButton
var _path_skip: WButton
## the debug hand (developer menu: "Debug buttons on modals"): any item, any level, as many as you like
var _debug: DebugHand
var _with_hints := false


func _ready() -> void:
	build_dim(W.DIM)
	build_header("Wanted", "LEVEL 1", "Pick one. The desert waits.")
	_list = VBoxContainer.new()
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_list.offset_left = 48
	_list.offset_right = -48
	_list.offset_top = 470 + W.safe_top()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	_build_path_head()
	build_buttons(108.0)
	_reroll_btn = _row_button()
	_skip_btn = _row_button()
	_banish_btn = _row_button()
	_reroll_btn.pressed.connect(_reroll)
	_skip_btn.pressed.connect(func(): _finish({"skipped": true}))
	_banish_btn.pressed.connect(_toggle_banish)
	# the path offer's single skip, 420 px wide, centred
	_path_skip = WButton.make(["SKIP"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	_path_skip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_path_skip.offset_left = -215
	_path_skip.offset_right = 215
	_path_skip.offset_bottom = -90
	_path_skip.offset_top = -90 - 108
	_path_skip.pressed.connect(func(): _finish({"skipped": true}))
	add_child(_path_skip)
	build_debug_button(_open_debug)


func _row_button() -> WButton:
	var b := WButton.make(["…"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(b)
	return b


## The path offer's head: the star line, the weapon's plate (260 px), its name in 96 px slab, and its path rivets.
func _build_path_head() -> void:
	_path_head = VBoxContainer.new()
	_path_head.alignment = BoxContainer.ALIGNMENT_BEGIN
	_path_head.add_theme_constant_override("separation", 14)
	_path_head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_path_head.offset_top = 90 + W.safe_top()
	_path_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_head.visible = false
	add_child(_path_head)


func _fill_path_head(def: ContentDef, taken: int) -> void:
	for c in _path_head.get_children():
		c.queue_free()
	_path_head.add_child(WStarLine.make("The road forks", 30, W.PAPER))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := WPlate.new().for_def(def, 272.0)
	p.border = 6
	p.radius = 18
	p.shadow = 10
	p.icon_frac = 0.74
	cc.add_child(p)
	_path_head.add_child(cc)
	var nm := W.slab_text(def.display_name.to_upper(), 96, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 96.0)
	nm.shadow = 8
	_path_head.add_child(nm)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(W.serif_text("Path", 28, W.AGED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var r := WMarks.new().setup("rivets", 3, taken, taken + 1, 36.0)
	r.rivet_fill = W.BRASS
	r.rivet_empty = Color(W.AGED.r, W.AGED.g, W.AGED.b, 0.25)
	r.gap = 8.0
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# the next path is aged paper, the ones after it faint
	r.next_fill = W.AGED
	row.add_child(r)
	row.add_child(W.serif_text("· the two you leave come back next stage", 28, W.AGED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	_path_head.add_child(row)


func show_offer(offer: Array, title: String, starter: bool, with_hints: bool, path: bool = false) -> void:
	_offer = offer
	_starter = starter
	_banish_mode = false
	path_mode = path
	_with_hints = with_hints
	header.visible = not path
	_path_head.visible = path
	if path:
		var md: MutationDef = offer[0]["def"] if not offer.is_empty() and offer[0]["def"] is MutationDef else null
		var w: WeaponInstance = Run.family_instance(md.weapon) if md else null
		if w:
			_fill_path_head(w.def, Run.mutations_held(w.family_id()).size())
	elif starter:
		header.star_line.visible = true
		header.set_title("PICK A GUN")
		header.set_line("Your first weapon. The rest you earn.")
	else:
		header.set_title(title.trim_suffix("!").to_upper())
		header.set_line("Pick one. The seal says how rare it is." if with_hints else "Pick one. The desert waits.")
	buttons.visible = not starter and not path
	_path_skip.visible = path
	_path_skip.set_parts(["SKIP ", ["+%d" % Run.skip_gold(), W.BRASS_DARK]])
	_refresh_buttons()
	_rebuild()
	_picking = false
	modulate.a = 1.0
	enter()
	_slide_cards()
	Audio.play("ui_card_pick")
	if not starter and not path:
		# the reveal (pass 44): a sunburst behind the title, stars and paper scraps falling, the title stamping in, a fanfare
		WCelebrate.burst(self, Vector2(get_viewport_rect().size.x * 0.5, 250.0 + W.safe_top()), 1)
		header.stamp.call_deferred()
		Audio.play("ui_fanfare")


func _refresh_buttons() -> void:
	# spent buttons stay tappable but locked-looking, so the tap can say where more charges come from
	_reroll_btn.set_parts(["REROLL ", ["×%d" % Run.rerolls_left, W.BRASS_DARK]])
	_reroll_btn.locked = Run.rerolls_left <= 0
	_skip_btn.set_parts(["SKIP ", ["+%d" % Run.skip_gold(), W.BRASS_DARK]])
	_skip_btn.locked = Run.skips_left <= 0
	_banish_btn.set_parts(["BANISHING…"] if _banish_mode else ["BANISH ", ["×%d" % Run.banishes_left, W.BRASS_DARK]])
	_banish_btn.locked = Run.banishes_left <= 0 and not _banish_mode
	_banish_btn.show_held(_banish_mode)


func _rebuild() -> void:
	for c in _slots:
		(c as Node).queue_free()
	_cards.clear()
	_slots.clear()
	for card in _offer:
		var node := _make_card(card)
		# each card in a margin holder, so it can slide up inside its place without moving the others
		var slot := MarginContainer.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(node)
		_list.add_child(slot)
		_cards.append(node)
		_slots.append(slot)
	_list.add_theme_constant_override("separation", 36 if path_mode else 44)
	_list.offset_top = (720.0 if path_mode else 470.0) + W.safe_top()
	_fit.call_deferred()


## The cards slide up 60 px, 60 ms apart, fading in.
func _slide_cards() -> void:
	for i in _slots.size():
		var slot: MarginContainer = _slots[i]
		slot.add_theme_constant_override("margin_top", 60)
		slot.add_theme_constant_override("margin_bottom", -60)
		slot.modulate.a = 0.0
		# bound to the slot: a quick pick frees it mid-slide, and the tween goes with it
		var tw := slot.create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_method(func(v: float):
			slot.add_theme_constant_override("margin_top", int(v))
			slot.add_theme_constant_override("margin_bottom", -int(v)), 60.0, 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(slot, "modulate:a", 1.0, 0.2)


func _make_card(card: Dictionary) -> WCard:
	var def: ContentDef = card["def"]
	var extra := {}
	if path_mode:
		extra = {"plate_px": 170.0, "name_size": 56, "rarity": "", "pad": [30, 32, 30, 32], "stars": [], "icon_frac": 0.72}
	var o := WItem.options(card, extra)
	if bool(card.get("favourite", false)):
		o["word"] = str(o["word"]) + " · FAVOURITE"
	if _starter and _with_hints and def is WeaponDef:
		match (def as WeaponDef).targeting:
			"forward":
				o["effect"] = str(o["effect"]) + " Fires where you face."
			"orbit":
				o["effect"] = str(o["effect"]) + " Guards you while you move."
			_:
				o["effect"] = str(o["effect"]) + " Aims itself."
	var c := WCard.make(def, o)
	if _banish_mode:
		# banishing: every card wears a rock band until one is struck out
		(c.box as HardBox).inner = 6
		(c.box as HardBox).inner_color = W.ROCK
		c.box = c.box
	c.pressed.connect(func(): _pick(card, c))
	return c


## The cards between the header and the buttons: at 1080 x 1920 from y 470 (720 under a path head), 44 px apart (36 on
## a path); a taller screen centres them with up to 60 px between; a fourth card squeezes the gap to 24 and lifts the list.
func _fit() -> void:
	if _cards.is_empty():
		return
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var n := _cards.size()
	var gap := 36.0 if path_mode else 44.0
	var top := (720.0 if path_mode else 470.0) + W.safe_top()
	var total := 0.0
	for c in _cards:
		total += (c as Control).get_combined_minimum_size().y
	var bottom := vp.y - 90.0 - 108.0 - 40.0
	var span := total + gap * (n - 1)
	if top + span > bottom:
		gap = maxf((bottom - top - total) / maxf(n - 1, 1), 24.0)
		span = total + gap * (n - 1)
		if top + span > bottom:
			top = maxf(bottom - span, 360.0 + W.safe_top())
	elif vp.y > 1930.0:
		gap = minf(gap + (bottom - top - span) / maxf(n + 1, 2), 60.0)
		span = total + gap * (n - 1)
		top = top + (bottom - top - span) * 0.5
	_list.add_theme_constant_override("separation", int(gap))
	_list.offset_top = top


func _pick(card: Dictionary, button: Control = null) -> void:
	if _picking:
		return
	if _banish_mode:
		# the banished card leaves the run's pool and only its slot is redrawn; the other cards stay
		Run.banished.append(card["id"])
		Run.banishes_left -= 1
		_banish_mode = false
		var keep: Array = []
		var ids: Array = []
		for c in _offer:
			if c["id"] != card["id"]:
				keep.append(c)
				ids.append(c["id"])
		_offer = keep + CardPool.level_up_offer(1, ids)
		header.set_line("%s banished for this run. Pick one." % (card["def"] as ContentDef).display_name)
		_refresh_buttons()
		_rebuild()
		if _offer.is_empty():
			_finish({"skipped": true})
		return
	_picking = true
	if button:
		(button as WTap).show_held(true)
		last_pick = {"def": card["def"], "rect": button.get_global_rect()}
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_callback(func(): _finish(card))


func _finish(card: Dictionary) -> void:
	if card.get("skipped", false):
		last_pick = {}
	visible = false
	Audio.play("ui_card_pick")
	chosen.emit(card)


## The gate takes the pick once (a skip or a chest leaves nothing to fly).
func take_pick() -> Dictionary:
	var p := last_pick
	last_pick = {}
	return p


func _reroll() -> void:
	if Run.rerolls_left <= 0:
		header.set_line("No rerolls left. The Choice upgrade gives more.")
		Audio.play("ui_locked")
		return
	Run.rerolls_left -= 1
	header.set_line("Rerolled. Pick one.")
	_offer = CardPool.level_up_offer(_offer.size())
	_refresh_buttons()
	_rebuild()


func _toggle_banish() -> void:
	if Run.banishes_left <= 0 and not _banish_mode:
		header.set_line("No banishes left. The Choice upgrade gives more.")
		Audio.play("ui_locked")
		return
	_banish_mode = not _banish_mode
	header.set_line("Tap a card to strike it from this run." if _banish_mode else "Pick one. The desert waits.")
	_refresh_buttons()
	_rebuild()


## The debug hand, opened from the small button: it hands over whatever was picked and leaves the offer standing.
func _open_debug() -> void:
	if _debug == null:
		_debug = DebugHand.new()
		add_child(_debug)
		_debug.given.connect(func(): _rebuild())
	_debug.open()
