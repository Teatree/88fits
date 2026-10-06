## Level-up and mutation offer, "Wanted" (screens 07 and 08). The run dims to sepia; a star line, a slab title
## and one dry line head the screen; the offers are item cards (kind by plate colour and one word, a passive item's
## rarity by its plate's colour, level by stars, one effect line; the hero's favourite says FAVOURITE after its word);
## REROLL ×N / SKIP ×N / BANISH ×N sit in the bottom row. Pass 47 (Garry: "only two skips per Stage, and those skips
## work for both Level Ups and Chests ... same treatment for Banish, but initially Players only get 1 Banish"): a skip
## pays nothing and takes one of the stage's skips (Run.use_skip), a banish one of its banishes (Run.use_banish); at
## none the button locks and a tap says so in the header. A mutation offer ("Pick a mutation", pass 46: the
## player-facing word for a path) puts the weapon on top with its mutation rivets, the mutation cards under it and a
## single SKIP ×N on the same skips. The card a finger holds sits on its shadow with a brass band; the pick is
## remembered (`last_pick`) so the gate can fly it to its HUD slot.
## Pass 54 (Garry's tenth list): the weapon a mutation offer is for is picked at random among the weapons with an open
## path (Run.next_path_weapon), and a pre-reel (WWeaponReel) runs the hero's weapons past a brass window and stops on it
## before the head and the cards come; a level-up comes with more: a brass sun behind LEVEL N, a stronger burst and a
## second one, the cards dropping in one after another with a tick each. Both draw a rainbow XP rail along the top edge
## (the HUD's rail steps aside with the HUD under every modal): full on a level-up, the run's XP on a mutation offer.
class_name CardScreen
extends WModal

signal chosen(card: Dictionary)

var _offer: Array = []
var _banish_mode := false
var _picking := false
var path_mode := false
## The card taken last: {def, rect} (the gate flies it to the slot it lands in).
var last_pick: Dictionary = {}
var _list: VBoxContainer
var _cards: Array = []
var _slots: Array = []
var _path_head: VBoxContainer
## The mutation offer's own line under its head (it has no header line): "No skips left this stage."
var _path_note: WText
var _reroll_btn: WButton
var _skip_btn: WButton
var _banish_btn: WButton
var _path_skip: WButton
## the debug hand (developer menu: "Debug buttons on modals"): any item, any level, as many as you like
var _debug: DebugHand
var _with_hints := false
## The rainbow XP rail (pass 54): over the dim, under everything else.
var _rail: Control
var _rail_frac := 0.0
var _rail_t := 0.0
## The mutation offer's pre-reel while it runs (pass 54).
var _reel: WWeaponReelScript
## The mutation head's parts the reel holds back until it lands: the plate, the name, the rivets row.
var _path_plate: WPlate
var _path_name: WText
var _path_row: Control

## The rail's thickness and its fill's inset are the HUD's (pass 56, Garry: "Make the EXP bar twice as thick": one pair of
## constants for both rails, 36 px and 6, so the level-up screen's can never differ from the run's), and the paper glint
## along the fill's top edge grew with them (2 px on the 12 px fill before).
const RAIL_H := HUD.RAIL_H
const RAIL_INSET := HUD.RAIL_INSET
const RAIL_GLINT := 4.0
const RAIL_SLICES := 24
## How fast the rail's hues race: whole turns of the rainbow a second.
const RAIL_SPEED := 1.2
## The pre-reel's spin.
const REEL_SECONDS := 1.5
## The cards' drop (pass 54): each from DROP_PX above, DROP_GAP after the one before.
const DROP_PX := 40.0
const DROP_GAP := 0.05
## The middle of the LEVEL N title at 1080 x 1920 (the header's top 110, its star line, half the 150 px title).
const TITLE_MID_Y := 110.0 + 38.0 + 75.0
## The pre-reel by path: a new class_name is known only once the global class cache is made again (the next import).
const WWeaponReelScript := preload("res://ui/wanted/WWeaponReel.gd")


func _ready() -> void:
	build_dim(W.DIM)
	_build_rail()
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
	_skip_btn.pressed.connect(_skip)
	_banish_btn.pressed.connect(_toggle_banish)
	# the mutation offer's single skip, 420 px wide, centred
	_path_skip = WButton.make(["SKIP"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	_path_skip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_path_skip.offset_left = -215
	_path_skip.offset_right = 215
	_path_skip.offset_bottom = -90
	_path_skip.offset_top = -90 - 108
	_path_skip.pressed.connect(_skip)
	add_child(_path_skip)
	_path_note = W.serif_text("", 30, W.AGED, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 39.0)
	_path_note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_path_note.offset_bottom = -90 - 108 - 24
	_path_note.offset_top = -90 - 108 - 24 - 40
	_path_note.visible = false
	add_child(_path_note)
	build_debug_button(_open_debug)


## The rail along the top edge where the HUD's sits (W.safe_top() .. + RAIL_H): the ink track, then the fill as
## RAIL_SLICES slices whose hues turn along it, (x / w + t * RAIL_SPEED) mod 1 at saturation 0.85, and a paper glint.
func _build_rail() -> void:
	_rail = Control.new()
	_rail.name = "XpRail"
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_rail.offset_top = W.safe_top()
	_rail.offset_bottom = W.safe_top() + RAIL_H
	_rail.draw.connect(_draw_rail)
	add_child(_rail)


func _draw_rail() -> void:
	var w := _rail.size.x
	_rail.draw_rect(Rect2(0, 0, w, RAIL_H), W.INK)
	var fw := w * clampf(_rail_frac, 0.0, 1.0)
	if fw <= 0.0 or w <= 0.0:
		return
	var sw := w / float(RAIL_SLICES)
	var x := 0.0
	while x < fw - 0.01:
		var x2 := minf(x + sw, fw)
		_rail.draw_rect(Rect2(x, RAIL_INSET, x2 - x + 0.6, RAIL_H - 2.0 * RAIL_INSET), rail_colour(x / w, _rail_t))
		x = x2
	_rail.draw_rect(Rect2(0, RAIL_INSET, fw, RAIL_GLINT), Color(W.PAPER, 0.7))


## The rail's colour at `u` (0..1 along it) at time `t`.
static func rail_colour(u: float, t: float) -> Color:
	return Color.from_hsv(fposmod(u + t * RAIL_SPEED, 1.0), 0.85, 1.0)


## How full the rail is now (0..1).
func rail_frac() -> float:
	return _rail_frac


func _process(delta: float) -> void:
	if not visible:
		return
	_rail_t += delta
	_rail.queue_redraw()


func _row_button() -> WButton:
	var b := WButton.make(["…"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(b)
	return b


## The mutation offer's head: the star line, the weapon's plate (260 px), its name in 96 px slab, and its mutation rivets.
func _build_path_head() -> void:
	_path_head = VBoxContainer.new()
	_path_head.alignment = BoxContainer.ALIGNMENT_BEGIN
	_path_head.add_theme_constant_override("separation", 14)
	_path_head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_path_head.offset_top = 90 + W.safe_top()
	_path_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_head.visible = false
	add_child(_path_head)


## `level` (pass 48): the weapon's level held, its plate's colour.
func _fill_path_head(def: ContentDef, taken: int, offered: int = 3, level: int = 0) -> void:
	# out at once, not only queued: the reel measures the new star line and holds back the new parts this frame
	for c in _path_head.get_children():
		_path_head.remove_child(c)
		c.queue_free()
	_path_head.add_child(WStarLine.make("Pick a mutation", 30, W.PAPER))
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := WPlate.new().for_def(def, 272.0, false, level)
	p.name = "WeaponPlate"
	p.border = 6
	p.radius = 18
	p.shadow = 10
	p.icon_frac = 0.74
	cc.add_child(p)
	_path_head.add_child(cc)
	_path_plate = p
	var nm := W.slab_text(def.display_name.to_upper(), 96, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 96.0)
	nm.shadow = 8
	_path_head.add_child(nm)
	_path_name = nm
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(W.serif_text("Mutation", 28, W.AGED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	# a rivet per mutation of the weapon's path (pass 48: the real count, Registry.mutations_of; three on every path)
	var fam: String = (def as WeaponDef).evolved_from if def is WeaponDef and (def as WeaponDef).is_evolution and (def as WeaponDef).evolved_from != "" else def.id
	var total := maxi(Registry.mutations_of(fam).size(), 1)
	var r := WMarks.new().setup("rivets", total, mini(taken, total), mini(taken, total) + 1, 36.0)
	r.rivet_fill = W.BRASS
	r.rivet_empty = Color(W.AGED.r, W.AGED.g, W.AGED.b, 0.25)
	r.gap = 8.0
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# the next mutation is aged paper, the ones after it faint
	r.next_fill = W.AGED
	row.add_child(r)
	row.add_child(W.serif_text(leave_line(offered), 28, W.AGED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	_path_head.add_child(row)
	_path_row = row


## What happens to the cards not taken, true for three on the table or four (a hero's mutation makes it four).
static func leave_line(offered: int) -> String:
	if offered <= 1:
		return ""
	return "· the other comes back next stage" if offered == 2 else "· the others come back next stage"


func show_offer(offer: Array, title: String, with_hints: bool, path: bool = false) -> void:
	_stop_reel()
	# the last offer's confetti, still falling when a new offer comes quickly, goes (pass 54)
	for c in get_children():
		if c is WCelebrate:
			c.queue_free()
	_offer = offer
	_banish_mode = false
	path_mode = path
	_with_hints = with_hints
	header.visible = not path
	_path_head.visible = path
	var w: WeaponInstance = null
	if path:
		var md: MutationDef = offer[0]["def"] if not offer.is_empty() and offer[0]["def"] is MutationDef else null
		w = Run.family_instance(md.weapon) if md else null
		if w:
			_fill_path_head(w.def, Run.path_progress(w).x, offer.size(), w.level)
	else:
		header.set_title(title.trim_suffix("!").to_upper())
		header.set_line("Pick one. The plate's colour says what it is." if with_hints else "Pick one. The desert waits.")
	buttons.visible = not path
	_path_skip.visible = path
	_path_note.visible = false
	_list.visible = true
	# the rainbow rail (pass 54): the bar that just filled on a level-up, the run's XP on a mutation offer
	_rail_frac = clampf(Run.xp / maxf(Run.xp_to_next(), 1.0), 0.0, 1.0) if path else 1.0
	_rail_t = 0.0
	_rail.offset_top = W.safe_top()
	_rail.offset_bottom = W.safe_top() + RAIL_H
	_refresh_buttons()
	_rebuild()
	_picking = false
	modulate.a = 1.0
	enter()
	Audio.play("ui_card_pick")
	if path and w:
		# the pre-reel first (pass 54): the head's plate, name and rivets, the cards and the skip wait for its landing
		_start_reel(w)
		return
	_drop_cards()
	if not path:
		# the reveal (pass 44; pass 54 more of it): a brass sun behind the title, a strong burst of rays, stars and paper
		# scraps and a second one after it, the title stamping in, a fanfare
		WCelebrate.level_up(self, Vector2(get_viewport_rect().size.x * 0.5, TITLE_MID_Y + W.safe_top()), 1)
		header.stamp.call_deferred()
		Audio.play("ui_fanfare")


## The weapons the mutation offer's reel runs past (pass 54): those with a path still open (Run.path_offer_weapons, the
## weapons lane's), else the held ones that can still take a mutation this stage.
static func reel_weapons() -> Array:
	if Run.has_method("path_offer_weapons"):
		var got = Run.call("path_offer_weapons")
		if got is Array and not (got as Array).is_empty():
			return got
	var out: Array = []
	for wi in Run.weapons:
		var inst: WeaponInstance = wi
		if Run.can_mutate(inst) and not Run.open_mutations(inst).is_empty():
			out.append(inst.def)
	return out


## The reel in the head's place (over the dim and the rail, under the header): the head shows only its star line, the
## cards and the skip wait; the window sits where the weapon's plate will be, so the landed plate becomes it.
func _start_reel(w: WeaponInstance) -> void:
	_set_path_parts(false)
	_list.visible = false
	_path_skip.visible = false
	_reel = WWeaponReelScript.new()
	_reel.name = "WeaponReel"
	add_child(_reel)
	move_child(_reel, mini(2, get_child_count() - 1))
	_reel.center = Vector2(get_viewport_rect().size.x * 0.5, path_plate_center_y())
	_reel.done.connect(_after_reel, CONNECT_ONE_SHOT)
	_reel.play(reel_weapons(), w.def, REEL_SECONDS)


## The middle of the mutation head's weapon plate (screen y): under the head's top, its star line and 14 px.
func path_plate_center_y() -> float:
	var star_h := 38.0
	if _path_head.get_child_count() > 0 and _path_head.get_child(0) is Control:
		star_h = (_path_head.get_child(0) as Control).get_combined_minimum_size().y
	return 90.0 + W.safe_top() + star_h + 14.0 + 272.0 * 0.5


## The head's plate, name and rivets shown or held back (the star line stays).
func _set_path_parts(on: bool) -> void:
	for c in _path_head.get_children():
		if c is WStarLine or not c is CanvasItem:
			continue
		(c as CanvasItem).modulate.a = 1.0 if on else 0.0


## The reel has landed: the weapon's plate takes its place growing from the reel's size, its name stamps in, the rivets
## fade in, then the cards drop in and the skip comes back.
func _after_reel() -> void:
	if _reel:
		_reel.queue_free()
		_reel = null
	if not visible or not path_mode:
		return
	_set_path_parts(true)
	if is_instance_valid(_path_plate):
		_path_plate.pivot_offset = _path_plate.custom_minimum_size * 0.5
		_path_plate.scale = Vector2.ONE * (WWeaponReelScript.CELL / 272.0)
		var tp := _path_plate.create_tween()
		tp.tween_property(_path_plate, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_path_name):
		WModalHeader.stamp_in(_path_name)
	if is_instance_valid(_path_row):
		_path_row.modulate.a = 0.0
		var tr := _path_row.create_tween()
		tr.tween_property(_path_row, "modulate:a", 1.0, 0.25)
	_list.visible = true
	_path_skip.visible = true
	_drop_cards()


## A reel still running is dropped (a new offer, a skip, a pick).
func _stop_reel() -> void:
	if _reel:
		if _reel.done.is_connected(_after_reel):
			_reel.done.disconnect(_after_reel)
		_reel.queue_free()
		_reel = null


## Whether the mutation offer's reel is still up (the tools wait on it).
func reel_running() -> bool:
	return _reel != null and is_instance_valid(_reel) and not _reel.is_finished()


## Straight to the reel's landing and on to the cards (a tool; a finger taps anywhere).
func skip_reel() -> void:
	if reel_running():
		_reel.skip()
	if reel_running():
		_reel.skip()


func _refresh_buttons() -> void:
	# spent buttons stay tappable but locked-looking, so the tap can say why
	_reroll_btn.set_parts(["REROLL ", ["×%d" % Run.rerolls_left, W.BRASS_DARK]])
	_reroll_btn.locked = Run.rerolls_left <= 0
	# a skip pays nothing since pass 47: it is one of the stage's skips, shared with the chests
	for b: WButton in [_skip_btn, _path_skip]:
		b.set_parts(["SKIP ", ["×%d" % Run.skips_left, W.BRASS_DARK]])
		b.locked = Run.skips_left <= 0
	_banish_btn.set_parts(["BANISHING…"] if _banish_mode else ["BANISH ", ["×%d" % Run.banishes_left, W.BRASS_DARK]])
	_banish_btn.locked = Run.banishes_left <= 0 and not _banish_mode
	_banish_btn.show_held(_banish_mode)


## SKIP (the level-up's and the mutation offer's): takes one of the stage's skips (Run.use_skip) and closes on nothing;
## with none left it stays put and says so (pass 47).
func _skip() -> void:
	if _picking:
		return
	if not Run.use_skip():
		_say("No skips left this stage.")
		Audio.play("ui_locked")
		_refresh_buttons()
		return
	_finish({"skipped": true})


## A line under the header, or under the mutation offer's head (which has no header line).
func _say(t: String) -> void:
	if path_mode:
		_path_note.text = t
		_path_note.visible = t != ""
	else:
		header.set_line(t)


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


## The cards drop into place one after another (pass 54; they slid up 60 px before): each from DROP_PX above with a
## little bounce, fading in, DROP_GAP after the one before, a soft card tick as each one starts.
func _drop_cards() -> void:
	for i in _slots.size():
		var slot: MarginContainer = _slots[i]
		slot.add_theme_constant_override("margin_top", -int(DROP_PX))
		slot.add_theme_constant_override("margin_bottom", int(DROP_PX))
		slot.modulate.a = 0.0
		# bound to the slot: a quick pick frees it mid-drop, and the tween goes with it
		var tw := slot.create_tween()
		tw.tween_interval(DROP_GAP * i)
		tw.tween_callback(func(): W.sfx_first(["ui_card", "ui_tap"]))
		tw.tween_method(func(v: float):
			slot.add_theme_constant_override("margin_top", -int(v))
			slot.add_theme_constant_override("margin_bottom", int(v)), DROP_PX, 0.0, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(slot, "modulate:a", 1.0, 0.18)


func _make_card(card: Dictionary) -> WCard:
	var def: ContentDef = card["def"]
	var extra := {}
	if path_mode:
		extra = {"plate_px": 170.0, "name_size": 56, "rarity": "", "pad": [30, 32, 30, 32], "stars": [], "icon_frac": 0.72}
	var o := WItem.options(card, extra)
	if bool(card.get("favourite", false)):
		o["word"] = str(o["word"]) + " · FAVOURITE"
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
		_banish_mode = false
		if not Run.use_banish():
			_say("No banishes left this stage.")
			Audio.play("ui_locked")
			_refresh_buttons()
			_rebuild()
			return
		Run.banished.append(card["id"])
		if RunAnalytics.I: RunAnalytics.I.event("banish", str(card["id"]))
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
		# the level it lands on goes with it: the gate's flying plate is in that level's colour (pass 48)
		last_pick = {"def": card["def"], "rect": button.get_global_rect(), "level": int(card.get("level_to", 0))}
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_callback(func(): _finish(card))


func _finish(card: Dictionary) -> void:
	if card.get("skipped", false):
		last_pick = {}
	_stop_reel()
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
	if RunAnalytics.I: RunAnalytics.I.event("reroll")
	header.set_line("Rerolled. Pick one.")
	_offer = CardPool.level_up_offer(_offer.size())
	_refresh_buttons()
	_rebuild()


func _toggle_banish() -> void:
	if Run.banishes_left <= 0 and not _banish_mode:
		_say("No banishes left this stage.")
		Audio.play("ui_locked")
		return
	_banish_mode = not _banish_mode
	header.set_line("Tap a card to strike it from this run." if _banish_mode else "Pick one. The desert waits.")
	_refresh_buttons()
	_rebuild()


## The debug hand, opened from the small button: it hands over whatever was picked and leaves the offer standing.
func _open_debug() -> void:
	if RunAnalytics.I: RunAnalytics.I.via = "debug"
	if _debug == null:
		_debug = DebugHand.new()
		add_child(_debug)
		_debug.given.connect(func(): _rebuild())
	_debug.open()
