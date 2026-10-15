## Level-up and mutation offer, "Wanted" (screens 07 and 08). The run dims to sepia; a star line, a slab title
## and one dry line head the screen; the offers are item cards (kind by plate colour and one word, a passive item's
## rarity by its plate's colour, level by stars, one effect line; the hero's favourite wears a brass heart on its plate
## and FAVOURITE by its tag, pass 62, and a new one shows the level it lands on and that level's numbers);
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
## (the HUD's rail steps aside with the HUD under every modal).
## Pass 58 (Garry's thirteenth list): the rail is full on both screens ("it should be the full EXP bar every time": the
## mutation offer drew the run's XP and read as a level-up stopped part-way); a turning shine (WShine) behind LEVEL N and
## behind the mutation offer's weapon plate once its reel lands ("make it look good and fitting with our UI style");
## the star line over LEVEL N says LEVEL UP; and BANISH says what it does ("(!!!) Level Up Banish? What are we
## banishing?"): tapped, the title turns to a red BANISH, a line under it says in plain words what a banish does, every
## card that may go wears a red stamp, every item the hero has is dimmed with YOU HAVE THIS and a tap on it says why
## (Garry: "Banish option should not allow Banishing items that Player already has, because this way they can lock
## themselves out of progression for those weapons": Run.banish_refusal), CANCEL goes back, and the struck card is
## stamped BANISHED as its replacement drops into its place. The first time, the line says a little more (the "banish"
## hint, Save.hint_seen). The review round: LEVEL UP is 34 px with the kit's ink shadow (it is read over the shine's
## brightest middle), banish mode's star line names its moment instead of LEVEL UP, a refused REROLL or SKIP in banish
## mode says so for a moment and the mode's words come back, a reroll takes the struck card's ghost with the old table,
## and the mutation offer's shine reaches as far as the level-up's.
class_name CardScreen
extends WModal

signal chosen(card: Dictionary)

var _offer: Array = []
var _banish_mode := false
var _picking := false
var path_mode := false
## Pass 79 (lane MUT): the hero's level when the mutation offer is a level-up's (Game._mutlvl_open sets it before
## show_offer, which reads it once and clears it): the head's line reads "Level N! Pick a mutation". 0 = a plain offer.
var path_level := 0
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
## The turning shine (pass 58): over the dim, under the reveal's bursts, the rail, the header and the cards.
var _shine: WShineScript
## The level-up's title as given ("LEVEL 3"), put back when banish mode ends.
var _title_text := "LEVEL 1"
## What banish mode says under its title (pass 58), in the header's stack under its line: the header line itself does
## not wrap, and this says two sentences.
var _banish_wrap: MarginContainer
var _banish_note: WText
## A button row re-sort is waiting for the next frame (_set_button).
var _resort_pending := false
## What banish mode's line said when it opened (the first time's or the usual), put back after a refusal (_say).
var _banish_text := ""
var _note_tw: Tween
## Struck cards' ghosts so far (each ghost's name is its own).
var _struck_n := 0

## The rail's thickness and its fill's inset are the HUD's (pass 56, Garry: "Make the EXP bar twice as thick": one pair of
## constants for both rails, 36 px and 6, so the level-up screen's can never differ from the run's), and the paper glint
## along the fill's top edge grew with them (2 px on the 12 px fill before). Pass 61 (Garry: "Make the EXP bar 1.8 times
## bigger"): 65 px and 11, the glint 7 px on the 43 px fill (4 on 24 before).
const RAIL_H := HUD.RAIL_H
const RAIL_INSET := HUD.RAIL_INSET
const RAIL_GLINT := 7.0
const RAIL_SLICES := 24
## How fast the rail's hues race: whole turns of the rainbow a second.
const RAIL_SPEED := 1.2
## The pre-reel's spin.
const REEL_SECONDS := 1.5
## The cards' drop (pass 54): each from DROP_PX above, DROP_GAP after the one before.
const DROP_PX := 40.0
const DROP_GAP := 0.05
## What the rail gained over the 18 px the screen was laid out under (pass 56, Garry: "Make the EXP bar twice as thick,
## move all the other UI with it accordingly"): everything placed from the top sits this much lower, so the gaps under
## the rail stay as they were (92 px to the header's top, 72 to the mutation offer's head).
const RAIL_GROWTH := HUD.RAIL_H - 18.0
## The header's top (WModal's 110), the mutation offer's head's top (90), the cards' top under each (470 and 720) and
## the highest a long list may lift to under the header (360, the header's foot and 13 px), all at 1080 x 1920 and under
## the camera cutout (W.safe_top()).
const HEADER_TOP := 110.0 + RAIL_GROWTH
const PATH_HEAD_TOP := 90.0 + RAIL_GROWTH
const LIST_TOP := 470.0 + RAIL_GROWTH
const PATH_LIST_TOP := 720.0 + RAIL_GROWTH
const LIST_FLOOR := 360.0 + RAIL_GROWTH
## Under the mutation offer's head a long list stops HEAD_CLEAR short of it (pass 56: four cards under a camera cutout ran
## over the weapon's name), and one that still does not fit between there and the bottom row shrinks, to MIN_SCALE at
## the least, rather than run over the skip.
const HEAD_CLEAR := 16.0
const MIN_SCALE := 0.6
## The star line over LEVEL N (pass 58 review: its paper capitals, 21 px tall at the kit's 30 px, were the faintest words
## on the screen, over the shine's brightest middle): 34 px and the kit's hard ink shadow, 2 px, as under the dry line.
const STAR_LINE_PX := 34
const STAR_LINE_SHADOW := 2
## The middle of the LEVEL N title (the header's top, its star line (STAR_LINE_PX x 1.25 tall), half the 150 px title).
const TITLE_MID_Y := HEADER_TOP + STAR_LINE_PX * 1.25 + 75.0
## The pre-reel by path: a new class_name is known only once the global class cache is made again (the next import).
const WWeaponReelScript := preload("res://ui/wanted/WWeaponReel.gd")
## The turning shine by path too (pass 58, new): its reach behind LEVEL N and behind the mutation offer's 272 px plate
## (the review: at 380 the plate covered the glow and the strongest of the rays, a faint halo round it; at 500 the rays
## clear its corners by some 200 px, as the level-up's fan out round its title).
const WShineScript := preload("res://ui/wanted/WShine.gd")
const SHINE_R := 520.0
const PATH_SHINE_R := 500.0
## The star line over LEVEL N (pass 58, Garry: "we should say "Level Up" somewhere on that screen ... such that it doesn't
## ruin the UI coherence": it said WANTED). Three ways were captured: this, a brass ribbon reading LEVEL UP! over the
## title, and the title itself reading LEVEL UP! over a star line LEVEL N. This one won: every modal's star line names its
## moment (LOOT, A PATH OPENS, PICK A MUTATION) and its title the thing itself, so LEVEL UP over LEVEL 12 reads as one
## poster with the number kept big; the ribbon cut into the title's capitals and is a piece no other screen has, and the
## big LEVEL UP! pushed the number into the small line.
const LEVEL_UP_WORDS := "Level up"
## The level-up's own line.
const PICK_LINE := "Pick one. The desert waits."
const HINT_LINE := "Pick one. The plate's colour says what it is."
## Banish mode's words (pass 58): what a banish does, in plain words, and the first time a little more of it.
const BANISH_TITLE := "BANISH"
const BANISH_LINE := "Tap a new item to strike it from this run. It will not be offered again."
const BANISH_FIRST := "Tap a new item to strike it from this run: it will not be offered again, on level-ups or in chests. What you already have can't be banished, so its upgrades stay yours."
const NOTHING_TO_BANISH := "Nothing here can be banished: you already have all of these."
## Banish mode's star line over its red BANISH (the review: LEVEL UP over BANISH spelled out Garry's "Level Up Banish?").
const BANISH_KICKER := "Strike one off"
## How long a refusal stands in banish mode's line before the mode's words come back (the review: a refused REROLL or
## SKIP had replaced them until the mode was opened again).
const NOTE_HOLD := 2.2
## The struck card: its BANISHED stamp slams in over STRIKE_SLAM seconds, holds STRIKE_HOLD, fades out over
## STRIKE_FADE while its replacement drops into its place.
const STRIKE_SLAM := 0.18
const STRIKE_HOLD := 0.42
const STRIKE_FADE := 0.22


func _ready() -> void:
	build_dim(W.DIM)
	# the shine right over the dim (pass 58): the reveal's bursts go in over it, the rail and everything else after
	_shine = WShineScript.make(Vector2(540.0, TITLE_MID_Y), SHINE_R)
	_shine.name = "Shine"
	_shine.put(self)
	_shine.visible = false
	_build_rail()
	# build_header's header with a larger star line (STAR_LINE_PX: LEVEL UP)
	header = WModalHeader.make(LEVEL_UP_WORDS, "LEVEL 1", PICK_LINE, 150, W.PAPER, STAR_LINE_PX, HEADER_TOP)
	add_child(header)
	# the star line and the dry line are read over the shine's rays (pass 58): the kit's hard ink shadow under both, as
	# under the title
	header.shadow_star(STAR_LINE_SHADOW)
	header.line.shadow = 2
	_build_banish_note()
	_list = VBoxContainer.new()
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_list.offset_left = 48
	_list.offset_right = -48
	_list.offset_top = LIST_TOP + W.safe_top()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	_build_path_head()
	build_buttons(108.0)
	_reroll_btn = _row_button()
	_skip_btn = _row_button()
	_banish_btn = _row_button()
	_banish_btn.name = "Banish"
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
	# banish mode's marks sit on each card's tag, wherever the card's layout puts it
	if _banish_mode:
		for slot in _slots:
			var mark := (slot as Node).get_node_or_null("BanishMark") as CanvasItem
			if mark and mark.visible:
				mark.queue_redraw()


func _row_button() -> WButton:
	var b := WButton.make(["…"], 34, WButton.SECONDARY, 5, 8, 26.0, 0.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(b)
	return b


## Banish mode's line (pass 58): in the header's stack under its own line, 60 px in from each side so it wraps on the
## paper's measure, Bitter 600 in paper with a hard ink shadow (it is read over the shine); hidden outside banish mode.
func _build_banish_note() -> void:
	_banish_wrap = MarginContainer.new()
	_banish_wrap.name = "BanishNote"
	_banish_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banish_wrap.add_theme_constant_override("margin_left", 60)
	_banish_wrap.add_theme_constant_override("margin_right", 60)
	_banish_wrap.add_theme_constant_override("margin_top", 10)
	_banish_note = W.serif_text("", 30, W.PAPER, 600, false, HORIZONTAL_ALIGNMENT_CENTER, 39.0, true)
	_banish_note.shadow = 3
	_banish_wrap.add_child(_banish_note)
	_banish_wrap.visible = false
	header.add_child(_banish_wrap)


## The mutation offer's head: the star line, the weapon's plate (260 px), its name in 96 px slab, and its mutation rivets.
func _build_path_head() -> void:
	_path_head = VBoxContainer.new()
	_path_head.alignment = BoxContainer.ALIGNMENT_BEGIN
	_path_head.add_theme_constant_override("separation", 14)
	_path_head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_path_head.offset_top = PATH_HEAD_TOP + W.safe_top()
	_path_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_head.visible = false
	add_child(_path_head)


## The mutation offer's head line (pass 79, lane MUT): "Level 12! Pick a mutation" on a level-up's, the old words else.
static func mutlvl_line(hero_level: int) -> String:
	return "Level %d! Pick a mutation" % hero_level if hero_level > 0 else "Pick a mutation"


## `level` (pass 48): the weapon's level held, its plate's colour.
func _fill_path_head(def: ContentDef, taken: int, offered: int = 3, level: int = 0) -> void:
	# out at once, not only queued: the reel measures the new star line and holds back the new parts this frame
	for c in _path_head.get_children():
		_path_head.remove_child(c)
		c.queue_free()
	var star := WStarLine.make(mutlvl_line(path_level), 30, W.PAPER)
	# read over the shine once the reel lands (pass 58 review): the kit's ink shadow, as LEVEL UP's
	WModalHeader.shadow_line(star, STAR_LINE_SHADOW, 30)
	_path_head.add_child(star)
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
	# the hero's favourite weapon on its way down its path keeps its heart (pass 62)
	if Run.is_favourite(def):
		WCard.add_heart(p)
	var nm := W.slab_text(def.display_name.to_upper(), 96, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, 96.0)
	nm.shadow = 8
	_path_head.add_child(nm)
	_path_name = nm
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the row's words are read over the shine's rays too (pass 58 review): the dry line's 2 px ink shadow
	var word := W.serif_text("Mutation", 28, W.AGED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	word.shadow = 2
	row.add_child(word)
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
	var rest := W.serif_text(leave_line(offered), 28, W.AGED, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	rest.shadow = 2
	row.add_child(rest)
	_path_head.add_child(row)
	_path_row = row


## What happens to the cards not taken, true for three on the table or four (a hero's mutation makes it four).
static func leave_line(offered: int) -> String:
	if offered <= 1:
		return ""
	return "· the other comes back next stage" if offered == 2 else "· the others come back next stage"


func show_offer(offer: Array, title: String, with_hints: bool, path: bool = false) -> void:
	_stop_reel()
	# the last offer's confetti, still falling when a new offer comes quickly, goes (pass 54; a struck card's ghost goes
	# with the old table in _rebuild)
	for c in get_children():
		if c is WCelebrate:
			c.queue_free()
	_offer = offer
	_banish_mode = false
	_banish_wrap.visible = false
	_stop_note_hold()
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
		_title_text = title.trim_suffix("!").to_upper()
		_say_level_up()
		header.set_line(_pick_line())
	path_level = 0
	buttons.visible = not path
	_path_skip.visible = path
	_path_note.visible = false
	_list.visible = true
	# the rainbow rail (pass 54), full on both (pass 58, Garry: "it should be the full EXP bar every time": a mutation offer
	# drew the run's XP, part of the bar dancing, and read as a level-up stopped half-way)
	_rail_frac = 1.0
	_rail_t = 0.0
	_rail.offset_top = W.safe_top()
	_rail.offset_bottom = W.safe_top() + RAIL_H
	_refresh_buttons()
	_rebuild()
	_picking = false
	modulate.a = 1.0
	enter()
	Audio.play("ui_card_pick")
	# the shine (pass 58): behind LEVEL N at once; on a mutation offer it waits for the reel's landing, behind the plate
	_shine.visible = false
	if not path:
		_shine_at(Vector2(get_viewport_rect().size.x * 0.5, TITLE_MID_Y + W.safe_top()), SHINE_R)
	if path and w:
		# the pre-reel first (pass 54): the head's plate, name and rivets, the cards and the skip wait for its landing
		_start_reel(w)
		return
	_drop_cards()
	if not path:
		# the reveal (pass 44; pass 54 more of it): a brass sun behind the title, a strong burst of rays, stars and paper
		# scraps and a second one after it, the title stamping in, a fanfare; over the shine (pass 58)
		WCelebrate.level_up(self, Vector2(get_viewport_rect().size.x * 0.5, TITLE_MID_Y + W.safe_top()), _shine.get_index() + 1)
		header.stamp.call_deferred()
		Audio.play("ui_fanfare")


## The shine at `at` reaching `r`, popping in (pass 58).
func _shine_at(at: Vector2, r: float) -> void:
	_shine.center = at
	_shine.radius = r
	_shine.color = W.BRASS
	_shine.color2 = W.PAPER
	_shine.strength = 1.0
	_shine.visible = true
	_shine.pop_in()


## The turning shine (tools and tests read it).
func shine() -> Control:
	return _shine


## The level-up's header: LEVEL UP on the star line, the title LEVEL N in paper.
func _say_level_up() -> void:
	header.set_star(LEVEL_UP_WORDS, W.PAPER)
	header.set_title_fit(_title_text, 150, W.PAPER, get_viewport_rect().size.x - 80.0)


## The level-up's dry line: the hint's on the first offers of a save, else the desert's.
func _pick_line() -> String:
	return HINT_LINE if _with_hints else PICK_LINE


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
	return PATH_HEAD_TOP + W.safe_top() + star_h + 14.0 + 272.0 * 0.5


## The head's plate, name and rivets shown or held back (the star line stays).
func _set_path_parts(on: bool) -> void:
	for c in _path_head.get_children():
		if c is WStarLine or not c is CanvasItem:
			continue
		(c as CanvasItem).modulate.a = 1.0 if on else 0.0


## The reel has landed: the weapon's plate takes its place growing from the reel's size, its name stamps in, the rivets
## fade in, then the cards drop in and the skip comes back; the shine pops in behind the plate (pass 58).
func _after_reel() -> void:
	if _reel:
		_reel.queue_free()
		_reel = null
	if not visible or not path_mode:
		return
	_set_path_parts(true)
	_shine_at(Vector2(get_viewport_rect().size.x * 0.5, path_plate_center_y()), PATH_SHINE_R)
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
	# held back while the reel ran, the cards were never laid out (their text unwrapped, so they measured short and a long
	# list ran over the skip): they are fitted now (pass 56)
	_fit()


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
	_set_button(_reroll_btn, ["REROLL ", ["×%d" % Run.rerolls_left, W.BRASS_DARK]])
	_reroll_btn.locked = Run.rerolls_left <= 0
	# a skip pays nothing since pass 47: it is one of the stage's skips, shared with the chests
	for b: WButton in [_skip_btn, _path_skip]:
		_set_button(b, ["SKIP ", ["×%d" % Run.skips_left, W.BRASS_DARK]])
		b.locked = Run.skips_left <= 0
	# pass 58: in banish mode the button takes it back (CANCEL); outside it, it locks with no banish left or nothing on the
	# table that may go (every card an upgrade of something the hero has)
	if _banish_mode:
		_set_button(_banish_btn, ["CANCEL"])
		_banish_btn.locked = false
	else:
		_set_button(_banish_btn, ["BANISH ", ["×%d" % Run.banishes_left, W.BRASS_DARK]])
		_banish_btn.locked = Run.banishes_left <= 0 or CardPool.banishable(_offer).is_empty()
	_banish_btn.show_held(_banish_mode)


## A button's words, set only when they change (pass 58). WButton.set_parts queues the old words' nodes for deletion, so
## for that frame a button measures its words twice and grows in place, and a tap on a locked BANISH had left REROLL over
## SKIP and BANISH off the screen's edge: the row is sorted again on the next frame, once the old words are gone.
func _set_button(b: WButton, parts: Array) -> void:
	var key := var_to_str(parts)
	if str(b.get_meta("parts", "")) == key:
		return
	b.set_meta("parts", key)
	b.set_parts(parts)
	if _resort_pending or not is_inside_tree():
		return
	_resort_pending = true
	get_tree().process_frame.connect(func():
		_resort_pending = false
		if is_instance_valid(buttons):
			buttons.queue_sort(), CONNECT_ONE_SHOT)


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


## A line under the header (under banish mode's title while it is on, for NOTE_HOLD seconds, then the mode's own words
## come back), or under the mutation offer's head (which has no header line).
func _say(t: String) -> void:
	if path_mode:
		_path_note.text = t
		_path_note.visible = t != ""
	elif _banish_mode:
		_banish_note.text = t
		_stop_note_hold()
		# bound to the line: it goes with the screen
		_note_tw = _banish_note.create_tween()
		_note_tw.tween_interval(NOTE_HOLD)
		_note_tw.tween_callback(func():
			if _banish_mode:
				_banish_note.text = _banish_text)
	else:
		header.set_line(t)


## A refusal's wait to put banish mode's words back, dropped (the mode ends, opens again, or another line comes).
func _stop_note_hold() -> void:
	if _note_tw and _note_tw.is_valid():
		_note_tw.kill()
	_note_tw = null


## Banish mode's own words as it opened (tests; a refusal stands NOTE_HOLD seconds, then these come back).
func banish_line() -> String:
	return _banish_text


func _rebuild() -> void:
	# a struck card's ghost still fading goes with the table it stood on (pass 58 review: a quick reroll left it fading
	# over the new first card)
	for c in get_children():
		if str(c.name).begins_with("Struck"):
			c.queue_free()
	for c in _slots:
		(c as Node).queue_free()
	_cards.clear()
	_slots.clear()
	for card in _offer:
		var slot := _make_slot()
		_list.add_child(slot)
		_slots.append(slot)
		_cards.append(_put_card(slot, card))
	_list.add_theme_constant_override("separation", 36 if path_mode else 44)
	_list.offset_top = (PATH_LIST_TOP if path_mode else LIST_TOP) + W.safe_top()
	_fit.call_deferred()


## Each card in a margin holder, so it can slide up inside its place without moving the others; banish mode's mark
## (pass 58) lies over the card in the same holder.
func _make_slot() -> MarginContainer:
	var slot := MarginContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


## `card`'s card into `slot` (its old card and mark out), with its banish mark over it; returns the card.
func _put_card(slot: MarginContainer, card: Dictionary) -> WCard:
	for k in slot.get_children():
		slot.remove_child(k)
		k.queue_free()
	var node := _make_card(card)
	slot.add_child(node)
	var mark := BanishMark.new()
	mark.name = "BanishMark"
	slot.add_child(mark)
	_mark(node, mark, card)
	return node


## The cards drop into place one after another (pass 54; they slid up 60 px before): each from DROP_PX above with a
## little bounce, fading in, DROP_GAP after the one before, a soft card tick as each one starts.
func _drop_cards() -> void:
	for i in _slots.size():
		_drop_slot(_slots[i], DROP_GAP * i)


## One card's drop, `delay` seconds from now (a banish's replacement drops alone, pass 58).
func _drop_slot(slot: MarginContainer, delay: float) -> void:
	slot.add_theme_constant_override("margin_top", -int(DROP_PX))
	slot.add_theme_constant_override("margin_bottom", int(DROP_PX))
	slot.modulate.a = 0.0
	# bound to the slot: a quick pick frees it mid-drop, and the tween goes with it
	var tw := slot.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		W.sfx_first(["ui_card", "ui_tap"])
		# a banish's replacement waited untouchable (pass 58); every card takes a finger from its drop on
		for k in slot.get_children():
			if k is WTap:
				(k as Control).mouse_filter = Control.MOUSE_FILTER_PASS)
	tw.tween_method(func(v: float):
		slot.add_theme_constant_override("margin_top", -int(v))
		slot.add_theme_constant_override("margin_bottom", int(v)), DROP_PX, 0.0, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(slot, "modulate:a", 1.0, 0.18)


func _make_card(card: Dictionary) -> WCard:
	var def: ContentDef = card["def"]
	var extra := {}
	if path_mode:
		extra = {"plate_px": 170.0, "name_size": 56, "rarity": "", "pad": [30, 32, 30, 32], "stars": [], "icon_frac": 0.72}
	# the hero's favourite wears its heart and says FAVOURITE by its tag (pass 62: WItem.options, WCard; it said
	# " · FAVOURITE" after its word before)
	var o := WItem.options(card, extra)
	var c := WCard.make(def, o)
	var box: HardBox = c.box
	# the card's own band (an evolution's ember), put back when banish mode ends
	c.set_meta("band", [box.inner, box.inner_color])
	c.pressed.connect(func(): _pick(card, c))
	return c


## Banish mode's look on one card (pass 58), or the card's own look outside it: a card that may go wears a red-rock band
## and a red BANISH stamp; an item the hero has (Run.banish_refusal) is dimmed (locked: aged paper at 60 %, still
## tappable, so the tap can say why) with YOU HAVE THIS (EVOLVES YOURS on an evolution) over it.
func _mark(c: WCard, mark: BanishMark, card: Dictionary) -> void:
	var why := Run.banish_refusal(card) if _banish_mode else ""
	var band: Array = c.get_meta("band", [0, W.BRASS])
	var box: HardBox = c.box
	if _banish_mode and why == "":
		box.inner = 6
		box.inner_color = W.ROCK
	else:
		box.inner = int(band[0])
		box.inner_color = band[1]
	c.box = box
	c.locked = _banish_mode and why != ""
	mark.card = c
	if not _banish_mode:
		mark.style = ""
	else:
		mark.style = "strike" if why == "" else ("evolution" if why == "evolution" else "held")
	# the card's own tag (NEW, UPGRADE: WCard.tag_node) gives its corner to the mark while banish mode is on
	var tag = c.get("tag_node")
	if tag is CanvasItem and is_instance_valid(tag):
		(tag as CanvasItem).modulate.a = 0.0 if _banish_mode else 1.0


func _mark_cards() -> void:
	for i in mini(_cards.size(), _offer.size()):
		var slot: MarginContainer = _slots[i]
		var mark := slot.get_node_or_null("BanishMark") as BanishMark
		if mark and is_instance_valid(_cards[i]):
			_mark(_cards[i], mark, _offer[i])


## The cards between the header and the buttons: at 1080 x 1920 from LIST_TOP (PATH_LIST_TOP under a mutation offer's
## head), 44 px apart (36 on a path); a taller screen centres them with up to 60 px between; a list too long squeezes the
## gap to 24 and lifts, up to LIST_FLOOR under the header (on a mutation offer HEAD_CLEAR under its head, pass 56), and
## one still too long shrinks to fit. On a mutation offer the cards stop 12 px over the line above its skip (pass 56: a
## long list ran over it). Pass 58: never over the header's foot either (banish mode's line makes it taller).
func _fit() -> void:
	if _cards.is_empty():
		return
	await get_tree().process_frame
	# while the mutation offer's reel runs the cards wait hidden and unsorted: the landing fits them (_after_reel)
	if not _list.visible or _cards.is_empty():
		return
	var vp := get_viewport_rect().size
	var n := _cards.size()
	var gap := 36.0 if path_mode else 44.0
	var top := (PATH_LIST_TOP if path_mode else LIST_TOP) + W.safe_top()
	var total := 0.0
	for c in _cards:
		if is_instance_valid(c):
			total += (c as Control).get_combined_minimum_size().y
	var bottom := vp.y - 90.0 - 108.0 - 40.0
	var floor_y := maxf(LIST_FLOOR + W.safe_top(), header_foot() + 13.0)
	if path_mode:
		bottom = vp.y + _path_note.offset_top - 12.0
		floor_y = PATH_HEAD_TOP + W.safe_top() + _path_head.get_combined_minimum_size().y + HEAD_CLEAR
	# never over the head (a weapon's name on two lines makes it taller)
	top = maxf(top, floor_y)
	var span := total + gap * (n - 1)
	var k := 1.0
	if top + span > bottom:
		gap = maxf((bottom - top - total) / maxf(n - 1, 1), 24.0)
		span = total + gap * (n - 1)
		if top + span > bottom:
			top = maxf(bottom - span, floor_y)
			if top + span > bottom:
				k = clampf((bottom - top) / maxf(span, 1.0), MIN_SCALE, 1.0)
	elif vp.y > 1930.0:
		gap = minf(gap + (bottom - top - span) / maxf(n + 1, 2), 60.0)
		span = total + gap * (n - 1)
		top = top + (bottom - top - span) * 0.5
	_list.add_theme_constant_override("separation", int(gap))
	_list.offset_top = top
	# shrunk about its top's middle, so it stays centred and starts where it did
	_list.pivot_offset = Vector2(_list.size.x * 0.5, 0.0)
	_list.scale = Vector2(k, k)


## The level-up header's foot (screen y) where it settles: its top, then its star line, title, line and banish mode's line.
func header_foot() -> float:
	return HEADER_TOP + W.safe_top() + header.get_combined_minimum_size().y


func _pick(card: Dictionary, button: Control = null) -> void:
	if _picking:
		return
	if _banish_mode:
		_banish_pick(card, button)
		return
	_picking = true
	if button:
		(button as WTap).show_held(true)
		# the level it lands on goes with it: the gate's flying plate is in that level's colour (pass 48)
		last_pick = {"def": card["def"], "rect": button.get_global_rect(), "level": int(card.get("level_to", 0))}
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_callback(func(): _finish(card))


## A card tapped in banish mode (pass 58): one the hero has says why and stays (a shake, nothing spent); a new one is
## struck (Run.banish_card spends the stage's banish), stamped BANISHED, and its replacement drops into its place; the
## line names what went.
func _banish_pick(card: Dictionary, button: Control) -> void:
	var i := _index_of(card, button)
	var why := Run.banish_refusal(card)
	if why != "":
		_say(refusal_line(card, why))
		Audio.play("ui_locked")
		if i >= 0:
			_shake(i)
		return
	if not Run.banish_card(card):
		_set_banish(false)
		_say("No banishes left this stage.")
		Audio.play("ui_locked")
		return
	if RunAnalytics.I: RunAnalytics.I.event("banish", str(card["id"]))
	var gone := (card["def"] as ContentDef).display_name
	var ids: Array = []
	for c in _offer:
		if c["id"] != card["id"]:
			ids.append(c["id"])
	var more := CardPool.level_up_offer(1, ids)
	_set_banish(false)
	header.set_line("%s is banished for this run. Pick one." % gone)
	# a stamp's thud (pass 58: "ui_stamp" when the lead binds one, the chest's knock until then)
	W.sfx_first(["ui_stamp", "ui_chest_knock"])
	if i < 0:
		# a card no longer on the table (a tool's): the offer simply loses it
		_offer = _offer.filter(func(c) -> bool: return c["id"] != card["id"]) + more
		_rebuild()
	else:
		_strike(i)
		if more.is_empty():
			_offer.remove_at(i)
			(_slots[i] as Node).queue_free()
			_slots.remove_at(i)
			_cards.remove_at(i)
		else:
			_offer[i] = more[0]
			_cards[i] = _put_card(_slots[i], more[0])
			# it waits unseen under the struck card's ghost: no finger may take it until it drops in
			(_cards[i] as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_drop_slot(_slots[i], STRIKE_SLAM + STRIKE_HOLD)
		_fit()
	_refresh_buttons()
	if _offer.is_empty():
		_finish({"skipped": true})


## Where `card` sits on the table: the tapped card's place, else the first card with its id; -1 when it is not there.
func _index_of(card: Dictionary, button: Control) -> int:
	if button != null:
		var at := _cards.find(button)
		if at >= 0:
			return at
	for k in _offer.size():
		if str(_offer[k]["id"]) == str(card.get("id", "")):
			return k
	return -1


## The struck card at `i` leaves the list as a ghost where it stood: its BANISHED stamp slams in, a red line strikes it,
## it holds and fades and goes (the replacement drops into its old place meanwhile).
func _strike(i: int) -> void:
	var c: WCard = _cards[i]
	var slot: MarginContainer = _slots[i]
	var at := c.get_global_rect()
	var ghost := Control.new()
	# a name of its own (a second ghost named like one still fading would be renamed past the "Struck" that _rebuild
	# looks for)
	_struck_n += 1
	ghost.name = "Struck%d_%d" % [i, _struck_n]
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	move_child(ghost, _list.get_index() + 1)
	ghost.position = at.position
	ghost.scale = _list.scale
	ghost.size = c.size
	var old_mark := slot.get_node_or_null("BanishMark")
	if old_mark:
		slot.remove_child(old_mark)
		old_mark.queue_free()
	slot.remove_child(c)
	ghost.add_child(c)
	c.position = Vector2.ZERO
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.locked = true
	var mark := BanishMark.new()
	mark.name = "BanishMark"
	mark.size = c.size
	mark.card = c
	ghost.add_child(mark)
	mark.style = "banished"
	var tag = c.get("tag_node")
	if tag is CanvasItem and is_instance_valid(tag):
		(tag as CanvasItem).modulate.a = 0.0
	mark.slam = 0.0
	var tw := ghost.create_tween()
	tw.tween_property(mark, "slam", 1.0, STRIKE_SLAM).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(STRIKE_HOLD)
	tw.tween_property(ghost, "modulate:a", 0.0, STRIKE_FADE)
	tw.tween_callback(ghost.queue_free)


## A refused card shakes in its place (pass 58), its mark with it.
func _shake(i: int) -> void:
	var slot: MarginContainer = _slots[i]
	var parts: Array = []
	for k in slot.get_children():
		if k is Control:
			parts.append(k)
	var tw := slot.create_tween()
	tw.tween_method(func(v: float):
		for p: Control in parts:
			if is_instance_valid(p):
				p.position.x = sin(v * TAU * 3.0) * 18.0 * (1.0 - v), 0.0, 1.0, 0.32)


## What a refused banish says (pass 58), in plain words: why this card cannot go. `why` is Run.banish_refusal's.
static func refusal_line(card: Dictionary, why: String) -> String:
	var def: ContentDef = card.get("def")
	var nm := def.display_name if def else "That"
	match why:
		"held":
			return "You have %s: banishing it would lock its upgrades." % nm
		"evolution":
			return "%s evolves what you have: it can't be banished." % nm
		"mutation":
			return "%s is a mutation: mutations can't be banished." % nm
		"gold":
			return "Gold cannot be banished."
	return ""


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
		_say("No rerolls left. The Choice upgrade gives more.")
		Audio.play("ui_locked")
		return
	Run.rerolls_left -= 1
	if RunAnalytics.I: RunAnalytics.I.event("reroll")
	# a fresh table ends banish mode (pass 58): BANISH again strikes from the new cards
	if _banish_mode:
		_set_banish(false)
	header.set_line("Rerolled. Pick one.")
	_offer = CardPool.level_up_offer(_offer.size())
	_refresh_buttons()
	_rebuild()


## BANISH: banish mode on (pass 58: the title a red BANISH, the line saying what it does, the cards marked), or off again
## (CANCEL); with no banish left, or nothing on the table that may go, it stays off and says why.
func _toggle_banish() -> void:
	if _picking or path_mode:
		return
	if _banish_mode:
		_set_banish(false)
		header.set_line(_pick_line())
		return
	if Run.banishes_left <= 0:
		_say("No banishes left this stage.")
		Audio.play("ui_locked")
		_refresh_buttons()
		return
	if CardPool.banishable(_offer).is_empty():
		_say(NOTHING_TO_BANISH)
		Audio.play("ui_locked")
		_refresh_buttons()
		return
	_set_banish(true)


## Banish mode on or off: the title, the line, the button and every card's mark.
func _set_banish(on: bool) -> void:
	_banish_mode = on
	var vw := get_viewport_rect().size.x
	if on:
		# the first time it says a little more (the "banish" hint, pass 58)
		var first := not Save.hint_seen("banish")
		header.set_star(BANISH_KICKER, W.PAPER)
		header.set_title_fit(BANISH_TITLE, 150, W.ROCK, vw - 80.0)
		header.set_line("")
		_stop_note_hold()
		_banish_text = BANISH_FIRST if first else BANISH_LINE
		_banish_note.text = _banish_text
		_banish_wrap.visible = true
		if first:
			Save.mark_hint("banish")
		header.stamp.call_deferred()
		_shine.strength = 0.55
		W.sfx_first(["ui_card", "ui_tap"])
	else:
		_stop_note_hold()
		_banish_wrap.visible = false
		_say_level_up()
		_shine.strength = 1.0
	_refresh_buttons()
	_mark_cards()
	_fit()


## Whether banish mode is on (tools and tests).
func banish_mode() -> bool:
	return _banish_mode


## The debug hand, opened from the small button: it hands over whatever was picked and leaves the offer standing.
func _open_debug() -> void:
	if RunAnalytics.I: RunAnalytics.I.via = "debug"
	if _debug == null:
		_debug = DebugHand.new()
		add_child(_debug)
		_debug.given.connect(func(): _rebuild())
	_debug.open()


## Banish mode's mark over a card (pass 58), in the card's holder over the card: "strike" a red rubber stamp BANISH at the
## card's top right (it may go), "held" an ink tag YOU HAVE THIS, "evolution" EVOLVES YOURS (it may not), "banished" the
## struck card's big BANISHED stamp slamming in (slam 0..1) with a red line through the card; "" nothing.
class BanishMark extends Control:
	var style := "":
		set(v):
			style = v
			visible = v != ""
			queue_redraw()
	var slam := 1.0:
		set(v):
			slam = v
			queue_redraw()
	## The card it marks: the stamp and the tag sit where the card's own tag (NEW, UPGRADE) is.
	var card: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		var at := _anchor()
		match style:
			"strike":
				_stamp("BANISH", Vector2(at.end.x + 8.0 - 96.0, at.get_center().y), 32, deg_to_rad(-8.0), 1.0, 0.92)
			"held":
				_tag("YOU HAVE THIS", at)
			"evolution":
				_tag("EVOLVES YOURS", at)
			"banished":
				var k := clampf(slam, 0.0, 1.2)
				var mid := size * 0.5
				draw_line(Vector2(24.0, mid.y + 6.0), Vector2(size.x - 24.0, mid.y - 6.0), Color(W.ROCK, 0.85 * minf(k, 1.0)), 8.0, true)
				_stamp("BANISHED", mid, 64, deg_to_rad(-6.0), lerpf(1.8, 1.0, minf(k, 1.0)), minf(k, 1.0))

	## A rubber stamp in red-rock ink: a double frame round tracked slab capitals, turned `angle`, at `at`.
	func _stamp(t: String, at: Vector2, px: int, angle: float, scale_k: float, alpha: float) -> void:
		if alpha <= 0.01:
			return
		var f := W.slab(W.em(px, 0.12))
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var asc := f.get_ascent(px)
		var desc := f.get_descent(px)
		var h := asc + desc
		var pad := Vector2(px * 0.6, px * 0.32)
		var box := Rect2(-w * 0.5 - pad.x, -h * 0.5 - pad.y, w + pad.x * 2.0, h + pad.y * 2.0)
		var ink := Color(W.ROCK, alpha)
		draw_set_transform(at, angle, Vector2(scale_k, scale_k))
		# a pale wash under the ink, so the stamp reads over a card's own words
		draw_rect(box, Color(W.PAPER, 0.78 * alpha))
		draw_rect(box, ink, false, maxf(4.0, px * 0.14))
		draw_rect(box.grow(-px * 0.2), ink, false, maxf(2.0, px * 0.06))
		draw_string(f, Vector2(-w * 0.5, -h * 0.5 + asc), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## The card's own tag in this mark's pixels, or where one would be (the top right of the card's words) without one.
	func _anchor() -> Rect2:
		var tag = card.get("tag_node") if is_instance_valid(card) else null
		if tag is Control and is_instance_valid(tag) and (tag as Control).is_inside_tree() and (tag as Control).size.x > 1.0:
			var tc := tag as Control
			var xf := get_global_transform().affine_inverse() * tc.get_global_transform()
			return Rect2(xf.origin, tc.size * xf.get_scale())
		return Rect2(size.x - 140.0, 30.0, 100.0, 34.0)

	## An ink tag with tracked paper capitals, its right edge on the card's tag's.
	func _tag(t: String, at: Rect2) -> void:
		var px := 22
		var f := W.serif(700, false, W.em(px, 0.14))
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var asc := f.get_ascent(px)
		var desc := f.get_descent(px)
		var h := asc + desc + 16.0
		var r := Rect2(at.end.x - (w + 32.0), at.get_center().y - h * 0.5, w + 32.0, h)
		draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(W.INK, 0.5))
		draw_rect(r, W.INK)
		draw_string(f, Vector2(r.position.x + 16.0, r.position.y + 8.0 + asc), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, W.PAPER)
