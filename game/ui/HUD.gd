## In-run HUD, "Wanted" (design_handoff_88fits_wanted, screens 06 and 06b): an ink XP rail across the top edge (pass 56:
## twice as thick, RAIL_H, with everything under it 18 px lower), a row of paper plates (LV, the clock, gold) with the
## brass pause disc, the slots (pass 47: six weapons and six lines from the
## start, five and five since pass 52, the held items as plates with their level tags, the open ones dashed; the passive items are not on the HUD,
## Garry: "Only the Weapons and Line Items", the pause screen's Build tab lists them; pass 48: equal 72 px slots on one
## row, the plates see-through at 50 % with their icons, level tags and a weapon's mutation dots solid, each plate in the
## colour of its level; pass 53: the weapons group sits against the row's left edge and the lines group against its right
## edge, nothing between them), the toast queue
## under the clock, the boss's name and bar only while a boss lives (pass 47: the name in paper with an ink outline over
## the world, no ink box behind it), pointers riding the screen edge, the hero's bars under him, the "+N XP" and "+N"
## gold (pass 47, with the coin) rising from him, and the floating joystick. A banner pops in at 38 % of the screen's
## height for 2 s (pass 45: on the top row it went unseen). A tap anywhere on the top strip pauses. Nothing interactive
## lives between y 700 and 1600.
## Pass 122 (lane UIHUD), under the Royale theme (Garry's build brief of 2026-11-02: "HUD as the mock on
## today's footprint ... Keep the height of the EXP bar as fat as ours is, keep the overall sizes the same for just about
## every element in that HUD as we have them now, only change the Style of indicators and buttons and such"): the same
## layout to the pixel (every box measured against the Wanted capture), the rail a black trough with the kit's bright
## purple band, LV / clock / gold on black 56 % info plates in white Ultra, the pause button a slate Royale button, the
## slots the kit's item frames with a level plaque under each (plain common frames unless the debug switch
## Settings.hud_slot_rarity puts the level's colour on them; an evolved item black in its rainbow rim either way), the
## power-ups on black plates, the pointers the kit's black plates; the kill counter, the boss's name and bar, the hero's
## bars, the floating numbers and the joystick exactly as under Wanted (Garry). The Wanted drawing is untouched while the
## switch is off (_apply_theme restyles the HUD's own pieces in place, so the in-run debug panel's switch takes at once).
class_name HUD
extends Control

signal pause_requested

## The XP rail across the top edge (pass 56, Garry: "Make the EXP bar twice as thick, move all the other UI with it
## accordingly"; "a plain fill, just twice as thick"): RAIL_H of ink (18 px before), the purple fill RAIL_INSET in from its
## top and bottom (3 before), so the fill keeps two thirds of it. The level-up screen's rainbow rail (CardScreen) reads
## both, so the two rails can never differ again. The top row, the slots and the strip are laid out from the rail's
## bottom, each from the one above it, so a thicker rail moves them all down by what it gained and every gap stays.
## Pass 61 (Garry: "Make the EXP bar 1.8 times bigger. Make sure the rainbow animation isn't broken"): 65 px (36 x 1.8,
## rounded), the fill 11 px in (6 x 1.8, rounded), so the fill keeps its two thirds; everything under it 29 px lower.
const RAIL_H := 65.0
const RAIL_INSET := 11.0
## The compact top (pass 41: the mock's row, 44 px plates from y 44 and 104 px weapon slots from y 170, took a fifth
## of the phone's height): the row's line and type 12 px under the rail (the pause disc 2 px higher), the pause disc, and
## the slots' line 96 px under the row's (pass 56: 48 and 144, each 18 px lower than the 30 and 126 of passes 41-55).
const TOP_Y := RAIL_H + 12.0
const PLATE_PX := 36
const TIMER_PX := 56
const DISC := 78.0
const SLOT_Y := TOP_Y + 96.0
## Height of the strip in design px with one slot row: the top row and the slots (pass 48: 72 px slots, was 236 with the
## 88 px weapons; pass 56: 238, the 220 of passes 48-55 and the 18 px the rail gained). A build that needs two rows
## makes it taller (`band_h`); PlayerInput's thumb zone starts just below `band_h`, and a tap anywhere on the strip
## pauses. Everything on the strip sits `W.safe_top()` lower on a phone with a camera cutout (pass 43).
const BAND_H := SLOT_Y + 94.0
## The slots (pass 48, Garry: equal and see-through): weapons and lines the same 72 px, SLOT_GAP apart; GROUP_GAP is the
## least room between the last weapon and the first line, the width a row must have (five and five: 5 x 72 + 4 x 8 twice
## and 48 = 832 px, _row_width) before it squeezes or splits. Pass 53 (Garry: "Don't center the 2 Slot groups, make the
## stick to their sides, Lines on the right weapons on the left"): on a 1080 px screen (1008 between the 36 px margins)
## the weapons start at the left margin, the lines end at the right one, and the room between them is what is left (224
## px); the brass divider that marked the middle of the centred row is gone. The plates' fill and frame show at SLOT_ALPHA.
const WEAPON_PX := 72.0
const OTHER_PX := 72.0
const SLOT_GAP := 8.0
const GROUP_GAP := 48.0
const ROW_GAP := 18.0
const SLOT_ALPHA := 0.5
## Where the banner sits, as a share of the screen's height: the upper part of the middle, under the strip, the boss
## plate and the toasts in every build, above the hero (pass 45: the top row was too high to notice).
const BANNER_FRAC := 0.38
static var band_h := float(BAND_H)
const PORTAL_GREEN := W.SAGE
const ELITE_ORANGE := W.EMBER
const BOSS_RED := W.ROCK
## The strip's slots (pass 47, Garry: the caps are a static six and six; pass 52: five and five, Run.MAX_WEAPONS and
## Run.MAX_LINES): weapons, then lines.
const WEAPON_SLOTS := 5
const LINE_SLOTS := 5
## The gold popup's number (the damage numbers' crit gold, with the coin beside it).
const COIN_GOLD := Color("ffc93c")
## The boss's name over the world (pass 47): paper slab with an ink outline and shadow instead of the ink box.
const BOSS_NAME_PX := 30
## Under the slots (pass 56): the power-ups' plates (BUFF_PX) BUFF_GAP under them; the boss's plate and bar BOSS_GAP under
## the slots, or BOSS_UNDER_BUFFS under the power-ups while any are up (both had started at the slots' foot, so the
## boss's bar ran across Berserk's and Sprint's plates); the words for what is building up (Adrenaline, Hot Streak...)
## WORDS_UNDER_BUFFS under the power-ups (clear of their seconds' tags, which hang 6 px under the plates; 2 px since pass
## 47 had the words touching them) or WORDS_UNDER_BOSS under the boss's bar; the toasts TOAST_GAP under the slots or the
## power-ups, TOAST_UNDER_BOSS under the bar, TOAST_UNDER_WORDS under the words.
const BUFF_PX := 72.0
const BUFF_GAP := 14.0
const BOSS_GAP := 20.0
const BOSS_UNDER_BUFFS := 16.0
const WORDS_UNDER_BUFFS := 12.0
const WORDS_UNDER_BOSS := 12.0
const TOAST_GAP := 18.0
## seconds a toast on screen takes to slide to its new place when the layout under the strip changes (pass 56)
const TOAST_SLIDE := 0.18
const TOAST_UNDER_BOSS := 20.0
const TOAST_UNDER_WORDS := 10.0
## A pointer on the screen's edge keeps its middle this far under all of them (pass 56: half a pointer and a gap).
const POINTER_CLEAR := 40.0
## Pass 122 (lane UIHUD), the HUD under Royale: the strip above the rail and the rail's trough in the kit's plate black
## (R.PLATE's colour), opaque, since the rail is the top of the screen (pass 47d); the LV number in the kit's epic light
## (R.RARITY epic light) while a mutation offer is due, the plate staying black (the rail's MUTATION NEXT is the mark);
## the clock's digits in the kit's soft red (R.ROLES red top) while the portal counts down, white otherwise; the pause
## button's base the kit's button base (R.BUTTON_BASE) under a 78 px slate square with 6 px corners.
const ROYALE_RAIL_BLACK := Color(8 / 255.0, 10 / 255.0, 18 / 255.0)
const ROYALE_MUT_TEXT := Color("de9fff")
const ROYALE_WARN_TEXT := Color("ff7d6a")

var game: Node
var _band: Control
var _rail: Control
var _cutout: ColorRect
var _top: Control
var _lv_plate: PanelContainer
var _lv: WText
var _timer_plate: PanelContainer
var _timer: WText
## pass 109: the run's kill counter under the clock (WKillCount)
var _kills: WKillCount
var _gold_plate: PanelContainer
var _gold: WText
## pass 122 (the review of lane UIHUD): the gold plate's coin, drawn again when the theme flips (_apply_theme)
var _coin: WCoin
var _pause_btn: WTap
var _slots: Control
var _slot_nodes: Dictionary = {}   # item id -> WPlate
var _buffs: HBoxContainer
var _buffs_key := ""
var _adren: WText
var _toasts: WToasts
var _banner: WBanner
var _boss_box: VBoxContainer
var _boss_name: WText
var _boss_icon: TextureRect
var _boss_bar: WBar
var _boss_warned := false
var _boss_ten := false
var _xp_frac := 0.0
var _slots_bottom: float = BAND_H
## pass 110: the height of the slots' first row as laid out (_refresh_rows), the kill counter's middle (_place_kills)
var _slot_row_h: float = WEAPON_PX
var _ring_pos := Vector2.ZERO
var _ring_alpha := 0.0
var _stick := Vector2.ZERO
var _stick_r := 150.0
var _hp := 1.0
var _xp_batch := 0.0      # XP collected since the last popup
var _xp_batch_t := 0.0    # seconds until the batch is shown
var _gold_batch := 0      # gold picked up since the last popup (Run.gold_gained, pass 47)
var _gold_batch_t := 0.0
var _arrows: Array = []   # {pos, dir, color, text, side}
var _pointers: Array = [] # one WPointer per arrow on screen, made as needed
## Pointers a capture tool pins on screen ({pos, color, side, text}), shown as if their targets were off screen.
var test_arrows: Array = []
var _flash_rect: ColorRect
## pass 79 (lane MUT): the mark that the next level-up is a mutation offer (Run.mutlvl_pending): the LV plate in the
## kit's mutation plum and a word at the XP rail's end
var _mut_word: WText
var _mut_on := false
var _lv_box_paper: StyleBox
var _lv_box_plum: StyleBox
## pass 122 (lane UIHUD): the theme and the slot-rarity switch the HUD's own pieces were last styled for (_apply_theme),
## and the top plates' text holders (the Wanted face's box whatever the theme, _fit_holders)
var _slot_rarity_applied := false
var _lv_hold: Control
var _timer_hold: Control
var _gold_hold: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_band()
	_build_boss()
	_toasts = WToasts.new()
	add_child(_toasts)
	_banner = WBanner.new()
	add_child(_banner)
	Run.xp_changed.connect(func(xp, need): _set_xp(xp, need); _lv.text = Loc.t("ui.hud.level", {"level": "%d" % Run.level}); _fit_top())
	Run.xp_gained.connect(_on_xp_gained)
	Run.gold_changed.connect(func(g): _gold.text = W.num(g); _fit_top())
	# the gold the hero picks up rises from him like the XP (pass 47); Run says how much each pickup really paid
	Run.gold_gained.connect(_on_gold_gained)
	Run.build_changed.connect(_refresh_rows)
	# pass 79 (lane MUT): the mutation mark follows the offers due and the picks open
	_build_mut_mark()
	Run.mutation_due_changed.connect(_refresh_mut_mark)
	Run.build_changed.connect(_refresh_mut_mark)
	Run.stage_changed.connect(func(_s): _refresh_mut_mark())
	# pass 122 (lane UIHUD): the HUD's own pieces in the theme, and again whenever the UI theme or the slot-rarity
	# switch flips in a run (the in-run debug panel; Settings.changed)
	_apply_theme(true)
	Settings.changed.connect(func(): _apply_theme())
	if game and game.player:
		game.player.input.touch_started.connect(func(p): _ring_pos = p; _ring_alpha = 1.0)
		game.player.input.touch_ended.connect(func(): _ring_alpha = 0.0)
	_refresh_rows()
	_set_xp(Run.xp, Run.xp_to_next())
	_gold.text = W.num(Run.run_gold)
	_lv.text = Loc.t("ui.hud.level", {"level": "%d" % Run.level})
	# the top row in place at once (pass 56: a tool that tapped the pause disc in the frame the run loaded found it still
	# at the row's corner, under the LV plate), and again once the plates have their sizes
	_fit_top()
	_fit_top.call_deferred()
	_layout_toasts()


## Pass 110 (lane ARENA): hidden for the debug arena's clean screenshot (the bars, the joystick, the toasts, all of it).
var clean_hidden := false


## While a modal that pauses the run is up (level-up, chest, shop, pause...), the HUD steps aside; the gate brings it
## back so the card can land in its slot.
func _process(_delta: float) -> void:
	# pass 77 (lane SIMRUN): the run sim's fast mode shows no HUD
	if Run.sim_mode:
		return
	# pass 110 (lane ARENA): the debug arena's clean capture hides the HUD for a screenshot (ArenaPanel.set_clean)
	var covered := clean_hidden
	for m in get_tree().get_nodes_in_group("wanted_modal"):
		if (m as CanvasItem).visible:
			covered = true
			break
	if visible == covered:
		visible = not covered


## A top-row plate: paper with an ink border and a hard shadow; pass 122, under Royale the kit's black info plate (56 %
## black, no edge, no base: W.plate_box, the same HardBox with the role "plate", which Wanted ignores), the border's
## room kept in the padding so the words sit where they did.
func _plate(border: int = 4, shadow: int = 5, pad := Vector2(18, 4)) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.plate_box(border, shadow).pad(pad.x + border, pad.y + border, pad.x + border, pad.y + border))
	return p


func _build_band() -> void:
	# the strip: a tap anywhere on it pauses (the plates let the touch through)
	_band = Control.new()
	_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_band.offset_bottom = BAND_H
	_band.mouse_filter = Control.MOUSE_FILTER_STOP
	_band.gui_input.connect(func(ev):
		if (ev is InputEventScreenTouch and ev.pressed) or (ev is InputEventMouseButton and ev.pressed):
			pause_requested.emit())
	add_child(_band)
	# the camera cutout's strip (pass 47d, Garry: the empty sand above the XP rail looked like the UI was cut off): solid
	# ink from the screen's top edge down to the rail, so the rail reads as the top of the screen; 0 px tall on a phone
	# without a cutout
	_cutout = ColorRect.new()
	_cutout.name = "CutoutBand"
	_cutout.color = W.INK
	_cutout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutout.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cutout.offset_top = 0.0
	_cutout.offset_bottom = W.safe_top()
	add_child(_cutout)
	# the XP rail: RAIL_H of ink along the top edge (36 px since pass 56), a plain purple fill RAIL_INSET in from its top
	# and bottom (24 px of it)
	_rail = Control.new()
	_rail.name = "XpRail"
	_rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_rail.offset_top = W.safe_top()
	_rail.offset_bottom = W.safe_top() + RAIL_H
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.draw.connect(_draw_rail)
	add_child(_rail)
	_top = Control.new()
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_top = W.safe_top()
	_top.offset_bottom = W.safe_top() + SLOT_Y - 10.0
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	# (pass 122: each plate's words sit in a holder that keeps the Wanted face's box whatever the theme, _hold)
	_lv_plate = _plate()
	_lv = W.text(Loc.t("ui.hud.level", {"level": "1"}), W.slab(), PLATE_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_lv_hold = _hold(_lv)
	_lv_plate.add_child(_lv_hold)
	_lv_plate.position = Vector2(36, TOP_Y)
	_top.add_child(_lv_plate)
	_timer_plate = _plate(4, 5, Vector2(32, 0))
	_timer = W.text("00:00", W.slab(), TIMER_PX, W.INK, HORIZONTAL_ALIGNMENT_CENTER, TIMER_PX * 1.15)
	_timer_hold = _hold(_timer)
	_timer_plate.add_child(_timer_hold)
	_timer_plate.position = Vector2(400, TOP_Y)
	_top.add_child(_timer_plate)
	# pass 109: the kill counter, centred under the clock (under its tag while one hangs there; _place_kills)
	_kills = WKillCount.new()
	_kills.name = "KillCounter"
	_top.add_child(_kills)
	_gold_plate = _plate()
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 10)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin = WCoin.make(32.0)
	gr.add_child(_coin)
	_gold = W.text("0", W.slab(), PLATE_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_gold_hold = _hold(_gold)
	_gold_hold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gr.add_child(_gold_hold)
	_gold_plate.add_child(gr)
	_top.add_child(_gold_plate)
	# the brass pause disc: a 4 px border, two ink bars (pass 122: a slate Royale square under Royale, _style_pause)
	_pause_btn = WTap.new()
	_style_pause()
	_pause_btn.custom_minimum_size = Vector2(DISC, DISC)
	_pause_btn.size = Vector2(DISC, DISC)
	var bars := HBoxContainer.new()
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 10)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var b := ColorRect.new()
		b.name = "Bar%d" % i
		b.color = W.INK
		b.custom_minimum_size = Vector2(10, 30)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars.add_child(b)
	bars.name = "PauseBars"
	_pause_btn.add_child(bars)
	_pause_btn.pressed.connect(func(): pause_requested.emit())
	_top.add_child(_pause_btn)
	# the held items, under the top row
	_slots = Control.new()
	_slots.position = Vector2(36, SLOT_Y + W.safe_top())
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots)
	# timed power-ups (plates with their seconds) and the Adrenaline count, under the slots on the left
	_buffs = HBoxContainer.new()
	_buffs.add_theme_constant_override("separation", 14)
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buffs)
	_adren = W.text("", W.slab(), 28, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_adren.stroke = 2
	_adren.shadow = 3
	_adren.visible = false
	add_child(_adren)


## Place the top row on TOP_Y: LV at left 36, the clock centred, gold just left of the disc, the disc at right 36.
func _fit_top() -> void:
	var w := get_viewport_rect().size.x
	_fit_holders()
	for p in [_lv_plate, _timer_plate, _gold_plate]:
		(p as Control).reset_size()
	_lv_plate.position = Vector2(36, TOP_Y)
	_timer_plate.position = Vector2((w - _timer_plate.size.x) * 0.5, TOP_Y)
	_gold_plate.position = Vector2(w - 36 - DISC - 18 - _gold_plate.size.x, TOP_Y)
	_pause_btn.position = Vector2(w - 36 - DISC, TOP_Y - 2)
	_pause_btn.size = Vector2(DISC, DISC)
	_place_stage_tag()
	_place_kills()
	_fit_mut_word()


# ---------------------------------------------------------------- pass 79 (lane MUT): the next level-up is a mutation

## The mark (M4): while an offer is due and a weapon has a pick open (Run.mutlvl_pending), the LV plate turns the kit's
## mutation plum with paper letters and the XP rail's end says MUTATION NEXT, so the level-up that shows a mutation offer
## in place of the three cards never comes as a surprise.
const MUT_WORD_KEY := "ui.hud.mutation_next"
const MUT_WORD_PX := 30
const MUT_WORD_RIGHT := 24.0


func _build_mut_mark() -> void:
	_lv_box_paper = _lv_plate.get_theme_stylebox("panel")
	var pad := Vector2(18 + 4, 4 + 4)
	_lv_box_plum = W.box(W.PLUM, 4, 5).pad(pad.x, pad.y, pad.x, pad.y)
	_mut_word = W.text(Loc.t(MUT_WORD_KEY), W.slab(), MUT_WORD_PX, W.PAPER, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	_mut_word.name = "MutationNext"
	_mut_word.stroke = 4
	_mut_word.shadow = 0
	_mut_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mut_word.visible = false
	_rail.add_child(_mut_word)
	_refresh_mut_mark()


## Whether the mark shows (tests, captures).
func mutation_mark_on() -> bool:
	return _mut_on


## `force` (pass 122): the mark styled again for the theme even when nothing about it changed (_apply_theme). Under
## Royale the LV plate stays the black plate and its number turns the epic light while the mark is on.
func _refresh_mut_mark(force: bool = false) -> void:
	if _mut_word == null:
		return
	var on := Run.mutlvl_pending()
	if not force and on == _mut_on and _mut_word.visible == on:
		return
	_mut_on = on
	_mut_word.visible = on
	_lv_plate.add_theme_stylebox_override("panel", _lv_box_paper)
	_lv.color = ROYALE_MUT_TEXT if on else R.WHITE
	_lv.queue_redraw()
	_fit_top()


func _fit_mut_word() -> void:
	if _mut_word == null:
		return
	_mut_word.reset_size()
	var sz := _mut_word.get_combined_minimum_size()
	_mut_word.size = sz
	_mut_word.position = Vector2(get_viewport_rect().size.x - MUT_WORD_RIGHT - sz.x, (RAIL_H - sz.y) * 0.5)


func _set_xp(xp: float, need: float) -> void:
	_xp_frac = clampf(xp / maxf(need, 1.0), 0.0, 1.0)
	_rail.queue_redraw()


## The boss's name and bar (pass 47, Garry: "remove the Black rectangle behind the name of the Boss"): the badge and the
## name ride over the world on their own, the name in paper slab with an ink outline and a hard ink shadow so it reads
## on sand, rock and water alike; the bar under them.
func _build_boss() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_boss_box.add_theme_constant_override("separation", 8)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	var row := HBoxContainer.new()
	row.name = "BossName"
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_icon = TextureRect.new()
	_boss_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_boss_icon.custom_minimum_size = Vector2(48, 48)
	_boss_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_boss_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_boss_icon)
	_boss_name = W.text("", W.slab(W.em(BOSS_NAME_PX, 0.06)), BOSS_NAME_PX, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	# pass 122 (lane UIHUD; Garry: "keep ... the boss name as well because the mock doesn't look good"): the name and
	# its bar are today's piece under both themes: the Wanted face and ink edge, the bar's Wanted drawing (WBar.themed)
	keep_wanted(_boss_name, W.em(BOSS_NAME_PX, 0.06))
	_boss_name.color = W.PAPER
	_boss_name.stroke = 5
	_boss_name.shadow = 4
	_boss_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_boss_name)
	_boss_box.add_child(row)
	_boss_bar = WBar.make(1.0, W.ROCK, 30.0, 4, 4)
	_boss_bar.themed = false
	_boss_box.add_child(_boss_bar)
	add_child(_boss_box)


func show_boss(def: EnemyDef) -> void:
	_boss_name.text = def.display_name.to_upper()
	var badge := "res://art/ui/badges/%s.png" % def.badge_for()
	_boss_icon.texture = load(badge) if ResourceLoader.exists(badge) else def.icon
	_boss_box.visible = true
	_layout_toasts()


func set_boss_hp(hp: float, max_hp: float) -> void:
	_boss_bar.value = hp / maxf(max_hp, 1.0)


## Pass 113 (lane BOSS; Garry's spec: "The guard must read"): the boss's bar through his bullet-heaven pattern (BossPatterns):
## 0 as ever (rock red), 1 guarded (grey, GUARDED in it: he shrugs most of every hit off), 2 spent (brass, DAZED in it: he
## takes extra). The mode now is `boss_guard`.
const BOSS_GUARD_FILL := Color("8e959c")
const BOSS_DAZED_FILL := Color("e0a63a")
var boss_guard := 0


func set_boss_guard(mode: int) -> void:
	boss_guard = mode
	if _boss_bar == null:
		return
	match mode:
		1:
			_boss_bar.fill = BOSS_GUARD_FILL
			_boss_bar.text = Loc.t("ui.hud.boss_guarded")
		2:
			_boss_bar.fill = BOSS_DAZED_FILL
			_boss_bar.text = Loc.t("ui.hud.boss_dazed")
		_:
			_boss_bar.fill = W.ROCK
			_boss_bar.text = ""
	_boss_bar.text_color = W.INK
	# (inside the 30 px bar's 22 px fill)
	_boss_bar.text_px = 18
	_boss_bar.queue_redraw()


func hide_boss() -> void:
	_boss_box.visible = false
	set_boss_guard(0)
	_layout_toasts()


## Under the slots, one under the other (pass 56, the lead: "when buff plates are up, put the boss box under them (and
## the adrenaline/streak labels and toasts under the lower of the two)"; the boss's bar had run across the power-up
## plates, both laid out from the slots' foot): the power-ups on the left, the boss's plate and bar while a boss lives
## (under the power-ups while any are up), the words for what is building up under the lower of the two, and the toasts
## under all of it. With no power-ups up everything sits where it did. `_under_bottom` is the foot of the lowest of them
## (the toasts aside), which the pointers on the screen's edges keep under.
var _under_bottom := 0.0
var _toast_tw: Tween


func _layout_toasts() -> void:
	var w := get_viewport_rect().size.x
	var has_buffs := _buffs.get_child_count() > 0
	# the column hangs from the slots' foot (pass 69: the hero's gauge that sat between them is gone, Garry: "No UI
	# indicators"; Heat shows on the ball itself, momentum on the hero)
	var top := _slots_bottom
	_buffs.position = Vector2(36, top + BUFF_GAP)
	var low := _buffs.position.y + BUFF_PX if has_buffs else top
	_boss_box.position = Vector2(60, low + BOSS_UNDER_BUFFS if has_buffs else top + BOSS_GAP)
	_boss_box.size = Vector2(w - 120, 0)
	if _boss_box.visible:
		low = _boss_box.position.y + _boss_box.get_combined_minimum_size().y
	var words_y := top + BUFF_GAP
	if _boss_box.visible:
		words_y = low + WORDS_UNDER_BOSS
	elif has_buffs:
		words_y = low + WORDS_UNDER_BUFFS
	_adren.position = Vector2(36, words_y)
	var y := top + TOAST_GAP
	if _adren.visible:
		low = words_y + _adren.get_combined_minimum_size().y
		y = low + TOAST_UNDER_WORDS
	elif _boss_box.visible:
		y = low + TOAST_UNDER_BOSS
	elif has_buffs:
		y = low + TOAST_GAP
	_under_bottom = low
	# a toast on screen slides to its new place rather than jumping (pass 56, the lead: the words under the plates come
	# and go all the time, Steady Hand's whenever he stops, and a toast that snapped 44 px each time read as a glitch)
	var to := Vector2(0, y)
	if _toast_tw:
		_toast_tw.kill()
		_toast_tw = null
	if _toasts.get_child_count() > 0 and is_inside_tree() and absf(_toasts.position.y - y) > 0.5:
		_toast_tw = create_tween()
		_toast_tw.tween_property(_toasts, "position", to, TOAST_SLIDE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_toasts.position = to
	_toasts.size = Vector2(w, 200)


## The foot of the boss's plate and bar on screen, or -1 while no boss is up (pass 56: the arena's quick column keeps
## under it; with a camera cutout, or under the power-ups, the bar had run beneath ARENA and AGAIN).
func boss_plate_bottom() -> float:
	if _boss_box == null or not _boss_box.visible:
		return -1.0
	return _boss_box.position.y + _boss_box.get_combined_minimum_size().y


## The strip's slots in order (pass 46; pass 47: weapons and lines, the passive items stay off the HUD), as [def (null
## for a slot with nothing in it), level, is_weapon, dots held, lock_stage, dots total, ready]: every weapon held, the
## open slots up to `weapon_cap`, then shut ones up to the strip's six; the same for the lines. `held_weapons` is [def,
## level, dots held] or [def, level, dots held, dots total, ready] each (pass 48: the mutation dots, Run.path_progress,
## and whether the weapon waits to evolve, Run.evolution_ready), `held_lines` [def, level] each; `weapon_caps` and
## `line_caps` are caps per stage, so a shut slot knows the stage (1-based) that opens it (-1: none does). lock_stage is
## 0 on a held or open slot. Since pass 47 both caps are a static six (Run.weapon_cap, Run.line_cap): every slot not
## held is open, and no padlock shows.
static func slot_specs(held_weapons: Array, weapon_cap: int, weapon_caps: Array, held_lines: Array, line_cap: int,
		line_caps: Array) -> Array:
	var out: Array = []
	for it in held_weapons:
		var total: int = int(it[3]) if it.size() > 3 else 0
		var evo_ready: bool = bool(it[4]) if it.size() > 4 else false
		out.append([it[0], int(it[1]), true, int(it[2]), 0, total, evo_ready])
	_fill_slots(out, held_weapons.size(), weapon_cap, weapon_caps, WEAPON_SLOTS, true)
	for it in held_lines:
		out.append([it[0], int(it[1]), false, 0, 0, 0, false])
	_fill_slots(out, held_lines.size(), line_cap, line_caps, LINE_SLOTS, false)
	return out


## The lines held, in the order they were picked, as [def, level] (pass 47: Run.held_lines; the passive items are left
## out, the pause screen's Build tab lists them).
static func held_line_specs() -> Array:
	var out: Array = []
	for pid in Run.held_lines():
		var pd: PassiveDef = Registry.passive(str(pid))
		if pd:
			out.append([pd, int(Run.passives.get(pid, 1))])
	return out


## The slots after the held ones, up to the strip's `strip`: open while under `cap`, shut past it.
static func _fill_slots(out: Array, held: int, cap: int, caps: Array, strip: int, is_weapon: bool) -> void:
	for i in range(held, strip):
		if i < cap:
			out.append([null, 0, is_weapon, 0, 0, 0, false])
		else:
			out.append([null, 0, is_weapon, 0, _opens_at(i + 1, caps), 0, false])


## The first stage (1-based) whose cap reaches `n` slots, -1 when none does.
static func _opens_at(n: int, caps: Array) -> int:
	for s in caps.size():
		if int(caps[s]) >= n:
			return s + 1
	return -1


## All the slots from the start (pass 46; pass 47: six weapons and six lines, both caps static; pass 52: five and five): what is held and what
## is open. Pass 48 (Garry: equal, see-through slots): weapons and lines both 72 px, SLOT_GAP apart; each plate in its level's
## colour (W.plate_fill), its fill and frame at SLOT_ALPHA with the icon, the level tag and a weapon's mutation dots solid
## (the glow when it waits to evolve); pass 49: a filled slot is solid, only the empty and padlocked ones see-through.
## Pass 53 (Garry: "Don't center the 2 Slot groups, make the stick to their sides, Lines on the right weapons on the
## left"): the weapons group starts at the row's left edge (x 0 of `_slots`, under the LV plate's left edge) and the lines
## group ends at its right edge (`avail`, the width less the two 36 px margins); the room between them is whatever is
## left, 224 px for five and five on a 1080 px screen, and no divider marks it. A row that needs more than fits at 85 %
## (the arena's long hands) splits: the weapons keep a left-aligned row of their own and the lines a right-aligned one
## under it, each row shrinking (`k`) only as far as it must, so a narrow screen squeezes the groups towards each other
## and never the plates into each other's level tags. Only held items are keys of `_slot_nodes`.
func _refresh_rows() -> void:
	var t0 := Time.get_ticks_usec()
	for c in _slots.get_children():
		c.queue_free()
	_slot_nodes.clear()
	var hw: Array = []
	for w in Run.weapons:
		var inst: WeaponInstance = w
		# the mutation dots: the path's mutations held of its total (never a hero's own), and the glow while it waits to
		# evolve at the next chest
		var pp := Run.path_progress(inst)
		hw.append([inst.def, inst.level, pp.x, pp.y, Run.evolution_ready(inst)])
	var items := slot_specs(hw, Run.weapon_cap(), [], held_line_specs(), Run.line_cap(), [])
	var avail := get_viewport_rect().size.x - 72.0
	var weapons := items.filter(func(it): return bool(it[2]))
	var others := items.filter(func(it): return not bool(it[2]))
	# a row is a list of groups: both on one row while they fit, else each on its own
	var rows: Array = [[weapons, others]]
	if _row_width(items) * 0.85 > avail:
		rows = [[weapons], [others]]
	var y := 0.0
	for row in rows:
		var groups: Array = (row as Array).filter(func(g): return not (g as Array).is_empty())
		if groups.is_empty():
			continue
		# the row's least width: each group's, GROUP_GAP between two; past `avail` everything on it shrinks by `k`
		var need := -GROUP_GAP
		for g in groups:
			need += _row_width(g) + GROUP_GAP
		var k := minf(avail / maxf(need, 1.0), 1.0)
		var row_h := 0.0
		for g in groups:
			var is_weapon_group: bool = bool((g as Array)[0][2])
			# weapons against the left edge, lines against the right one
			var x := 0.0 if is_weapon_group else maxf(avail - _row_width(g) * k, 0.0)
			for it in g:
				var is_w: bool = it[2]
				var side := (WEAPON_PX if is_w else OTHER_PX) * k
				var p: WPlate
				if it[0] == null:
					p = WPlate.slot(side, int(it[4]) != 0, int(it[4]))
				else:
					p = WPlate.new().for_def(it[0], side, false, int(it[1]))
					p.icon_frac = 0.66
					p.level_text = str(it[1])
					p.level_size = int(round(19 * maxf(k, 0.8)))
					# pass 122 (lane UIHUD): under Royale the kit draws the level as the plaque under the frame, and the
					# frame is the plain common one for every slot unless the debug switch Settings.hud_slot_rarity puts
					# the level's colour (or a passive's rarity) on it, as the mock (Garry compares the two on the
					# phone); an evolved item keeps its black face and rainbow rim either way (for_def's own flag). The
					# row is laid out again when the switch or the theme flips (_apply_theme).
					if not Settings.hud_slot_rarity:
						p.fill = W.RARITY_PLATE["common"]
					if is_w and it.size() > 5 and int(it[5]) > 0:
						p.dot_px = roundf(20.0 * k)
						p.set_dots(Vector2i(int(it[3]), int(it[5])), it.size() > 6 and bool(it[6]))
				p.border = 4
				p.radius = 10
				# pass 49 (Garry: "when the item slots are filled they should stop being transparent"): only an empty or
				# padlocked slot shows see-through
				p.plate_alpha = SLOT_ALPHA if it[0] == null else 1.0
				p.position = Vector2(x, y)
				_slots.add_child(p)
				if it[0] != null:
					_slot_nodes[(it[0] as ContentDef).id] = p
				x += side + SLOT_GAP * k
				row_h = maxf(row_h, side)
		if y == 0.0:
			_slot_row_h = row_h
		y += row_h + ROW_GAP
	var inset := W.safe_top()
	_rail.offset_top = inset
	_cutout.offset_bottom = inset
	_rail.offset_bottom = inset + RAIL_H
	_top.offset_top = inset
	_top.offset_bottom = inset + SLOT_Y - 10.0
	_slots.position = Vector2(36, SLOT_Y + inset)
	_slots_bottom = SLOT_Y + inset + maxf(y - ROW_GAP, 0.0) + 6.0
	# the strip that pauses on a tap reaches under the slots (and the thumb zone starts below it)
	band_h = maxf(float(BAND_H) + inset, _slots_bottom + 14.0)
	_band.offset_bottom = band_h
	_layout_toasts()
	_place_kills()
	Perf.add("hud.rows", t0)


## One row's least width at full size: weapons WEAPON_PX, the lines OTHER_PX, SLOT_GAP apart, GROUP_GAP in place of the
## slot gap where the weapons end (five and five are 832 px; pass 53 spreads the two groups to the row's edges, so on a
## screen wider than this the room between them grows).
static func _row_width(row: Array) -> float:
	var nw := 0
	var np := 0
	for it in row:
		if bool(it[2]):
			nw += 1
		else:
			np += 1
	return nw * WEAPON_PX + np * OTHER_PX + maxf(nw + np - 1, 0) * SLOT_GAP + ((GROUP_GAP - SLOT_GAP) if nw > 0 and np > 0 else 0.0)


## Where an item's slot is on screen (the gate's flying card lands there); an empty rect when it has none. A passive
## item has no slot (pass 47): its card flies into the pause disc, where the Build tab lists it.
func slot_rect(id: String) -> Rect2:
	var p: WPlate = _slot_nodes.get(id)
	if p:
		return p.get_global_rect()
	if _pause_btn and Run.held_passives().has(id):
		return _pause_btn.get_global_rect()
	return Rect2()


## The gate's mark on the slot that just took the pick: a brass border and a brass level tag, for as long as it waits.
func mark_slot(id: String, on: bool) -> void:
	var p: WPlate = _slot_nodes.get(id)
	if p == null:
		return
	p.border_color = W.BRASS if on else W.INK
	p.level_fill = W.BRASS if on else W.PAPER
	p.ring = p.base_ring
	p.queue_redraw()


## The run ends the frame the hero falls, so tick() stops: hide the bars and the stick ring explicitly.
func hide_player_bar() -> void:
	_hero_bars = false
	_ring_alpha = 0.0
	queue_redraw()


## Back after a revive.
func show_player_bar() -> void:
	_hero_bars = true
	_ring_alpha = 0.0
	queue_redraw()


func set_hp(hp: float, max_hp: float) -> void:
	_hp = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	queue_redraw()


# the hero's bars: health (sage, rock when low) with the shield (rare blue) under it, both on an ink track with 2 px of
# padding, drawn at a fixed spot under the hero on screen (CameraRig.hero_anchor) and 1.5 m wide at the camera's zoom
var _hero_bars := true
var _bar_c := Vector2.ZERO
var _bar_w := 0.0
var _bar_h := 0.0
var _shield_frac := -1.0
## Snake Oil's overheal (pass 69) as a share of max HP: the HP bar runs on past full by that much, drawn OVERHEAL_PINK
var _over_frac := 0.0
const OVERHEAL_PINK := Color("e86aa8")


# ---------------------------------------------------------------- pass 82 (lane FEEL): the hurt shakes the HP bar
## Garry: "Don't shake the screen when hero is damaged. Shake the hp bar instead. But do that a little bit." A hit on his
## health (Game._feel_hurt_bar_shake) jiggles the hero's bars sideways instead of kicking the camera: HP_SHAKE_PX +
## HP_SHAKE_PX_PER_HP pixels for every whole max HP the hit took, at most HP_SHAKE_MAX_PX, HP_SHAKE_SWINGS swings over
## HP_SHAKE_TIME seconds dying away as (1 - u)^2, so the bars end exactly where they were; a hit while one runs starts it
## again at the larger of the new size and what is left of the old. Canvas pixels (the 1080-wide canvas).
const HP_SHAKE_PX := 4.0
const HP_SHAKE_PX_PER_HP := 40.0
const HP_SHAKE_MAX_PX := 10.0
const HP_SHAKE_TIME := 0.25
const HP_SHAKE_SWINGS := 3.0
## seconds since the hurt (-1 at rest), its size in px, and the bars' sideways offset now (px; 0 at rest)
var _hp_shake_t := -1.0
var _hp_shake_amp := 0.0
var hp_shake_x := 0.0


## A hit that took `frac` of the hero's max HP: the bars jiggle (no allocation; the offset is drawn by _draw_hero_bars).
func shake_hp_bar(frac: float) -> void:
	var left := 0.0
	if _hp_shake_t >= 0.0:
		var u := clampf(_hp_shake_t / HP_SHAKE_TIME, 0.0, 1.0)
		left = _hp_shake_amp * (1.0 - u) * (1.0 - u)
	_hp_shake_amp = maxf(hp_shake_amp_for(frac), left)
	_hp_shake_t = 0.0


## The jiggle's size (px) for a hit of `frac` of max HP.
static func hp_shake_amp_for(frac: float) -> float:
	return minf(HP_SHAKE_PX + HP_SHAKE_PX_PER_HP * maxf(frac, 0.0), HP_SHAKE_MAX_PX)


## The bars' offset (px) `t` seconds into a jiggle of `amp` px: 0 before it and from HP_SHAKE_TIME on.
static func hp_shake_at(t: float, amp: float) -> float:
	if t < 0.0 or t >= HP_SHAKE_TIME:
		return 0.0
	var u := t / HP_SHAKE_TIME
	return amp * (1.0 - u) * (1.0 - u) * sin(u * HP_SHAKE_SWINGS * TAU)


func _tick_hp_shake(delta: float) -> void:
	if _hp_shake_t < 0.0:
		return
	_hp_shake_t += delta
	if _hp_shake_t >= HP_SHAKE_TIME:
		_hp_shake_t = -1.0
		hp_shake_x = 0.0
		return
	hp_shake_x = hp_shake_at(_hp_shake_t, _hp_shake_amp)


func _tick_hero_bars() -> void:
	if game == null or game.player == null or game.camera == null or not game.camera.has_method("hero_anchor"):
		return
	var a: Dictionary = game.camera.hero_anchor()
	var ppm: float = a["ppm"]
	_bar_w = 1.5 * ppm
	_bar_h = maxf(0.15 * ppm, 8.0)
	_bar_c = (a["pos"] as Vector2) + Vector2(0, 0.42 * ppm)
	var p = game.player
	var smax: float = p.sheet.get_stat("shield_max", 0.0) if p.sheet else 0.0
	_shield_frac = clampf(float(p.shield_pts) / smax, 0.0, 1.0) if smax > 0.0 else -1.0
	# Snake Oil (pass 69): the overheal as a share of max HP, the bar's pink extension
	var ov = p.get("overheal")
	_over_frac = clampf(float(ov) / maxf(float(p.max_hp), 1.0), 0.0, 1.0) if ov != null else 0.0


func _draw_hero_bars() -> void:
	if not _hero_bars or _bar_w <= 0.0 or (game and game.player and game.player.dead):
		return
	var hh := _bar_h + 4.0
	# pass 82 (lane FEEL): the hurt's jiggle moves the bars sideways (0 at rest)
	var r := Rect2(_bar_c + Vector2(hp_shake_x, 0.0) - Vector2(_bar_w * 0.5, hh * 0.5), Vector2(_bar_w, hh))
	# Snake Oil's overheal (pass 69): the ink track runs on past full by its share of the bar, the extra drawn pink
	var ext := _bar_w * _over_frac
	draw_rect(Rect2(r.position, Vector2(_bar_w + ext, hh)) if ext >= 1.0 else r, W.INK)
	if _hp > 0.0:
		var fr := r.grow(-2.0)
		draw_rect(Rect2(fr.position, Vector2(fr.size.x * _hp, fr.size.y)), W.SAGE if _hp > 0.35 else W.ROCK)
		if ext >= 1.0:
			draw_rect(Rect2(Vector2(fr.end.x + 1.0, fr.position.y), Vector2(maxf(ext - 1.0, 1.0), fr.size.y)), OVERHEAL_PINK)
	if _shield_frac >= 0.0:
		var sh := maxf(_bar_h * 0.71, 6.0) + 4.0
		var sr := Rect2(Vector2(r.position.x, r.end.y + 4.0), Vector2(_bar_w, sh))
		draw_rect(sr, W.INK)
		if _shield_frac > 0.0:
			var sf := sr.grow(-2.0)
			draw_rect(Rect2(sf.position, Vector2(sf.size.x * _shield_frac, sf.size.y)), W.RARE)


## A full-screen flash that fades (the nuke, a harpoon hit).
func flash(col: Color, seconds: float) -> void:
	if _flash_rect == null:
		_flash_rect = ColorRect.new()
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_flash_rect)
	_flash_rect.color = col
	_flash_rect.visible = true
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _flash_rect.visible = false)


func toast(text: String, color: Color = W.PAPER, icon: Texture2D = null) -> void:
	_toasts.push(text, color, icon)


## Pass 82 (lane TOTEM): where an icon toast saying `text` would show its icon if pushed now, on the canvas (the Totem
## screen flies the chosen spirit's face there).
func toast_icon_spot(text: String) -> Vector2:
	return _toasts.get_global_transform() * _toasts.icon_spot(text)


## A first-play hint: it sits in the toast slot until cleared.
func hint(text: String) -> void:
	_toasts.hint(text)


func clear_hint() -> void:
	_toasts.clear_hint()


## News that pops in at BANNER_FRAC of the height for 2 s (never under the toast slot, so a two-row build with a boss
## plate keeps clear of it). An evolution and an unlock are ember with the item's icon; an item's own news with its icon
## (pass 54: PHOENIX FEATHER) is in `color`; the rest are ink. The same words while they are still up are not shown
## again (Phoenix Feather's banner opens as he falls and is called again as he stands). The top row stays as it is.
func banner(text: String, color: Color = W.INK, icon: Texture2D = null) -> void:
	var t := text.replace(": ", " · ")
	if _banner.is_up() and t.to_upper() == _banner_text:
		return
	_banner_text = t.to_upper()
	var ember := t.begins_with("EVOLVED") or (icon != null)
	var vp := get_viewport_rect().size
	var y := maxf(vp.y * BANNER_FRAC, _toasts.position.y + 200.0 + 24.0)
	_banner.play(t, ember, icon, y)
	if icon != null and not t.begins_with("EVOLVED") and not t.begins_with("UNLOCKED"):
		var hb := W.box(color, 4, 5).pad(52, 14, 52, 14)
		hb.themed = false   # pass 122: the banner stays as it is under both themes (Garry)
		_banner.add_theme_stylebox_override("panel", hb)


## The banner's words now (upper case) and whether it is up.
var _banner_text := ""


func banner_text() -> String:
	return _banner_text if _banner and _banner.is_up() else ""


## An item leaving the hero (pass 54, Garry: Phoenix Feather flying off him as it stands him up): its plate, FLY_PX
## across, from `at` (screen px, its middle) rises FLY_RISE px, grows to FLY_SCALE and turns FLY_TILT degrees, fading
## over the second half of FLY_TIME s, with FLY_EMBERS ember dots in `color` drifting up off it faster than it rises.
## Returns its holder (a plain Control named "FlyItem", so the turn and the growth stick).
const FLY_PX := 160.0
const FLY_RISE := 260.0
const FLY_TIME := 1.6
const FLY_SCALE := 1.35
const FLY_TILT := -12.0
const FLY_EMBERS := 6


func fly_item(def: ContentDef, at: Vector2, color: Color = Color(1.0, 0.55, 0.15)) -> Control:
	var holder := Control.new()
	holder.name = "FlyItem"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(FLY_PX, FLY_PX)
	holder.position = at - holder.size * 0.5
	holder.pivot_offset = holder.size * 0.5
	if def:
		var plate := WPlate.new().for_def(def, FLY_PX, false, 1)
		plate.name = "Plate"
		plate.shadow = 8
		plate.icon_frac = 0.74
		holder.add_child(plate)
	# the embers: dots round the plate that drift up faster than it, shrinking as they fade
	var seeds: Array = []
	for k in FLY_EMBERS:
		seeds.append([randf_range(0.1, 0.9) * FLY_PX, randf_range(0.35, 0.95) * FLY_PX, randf_range(60.0, 140.0),
			randf_range(6.0, 11.0), randf_range(-30.0, 30.0)])
	var embers := Control.new()
	embers.name = "Embers"
	embers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	embers.size = holder.size
	embers.set_meta("t", 0.0)
	embers.set_meta("count", seeds.size())
	embers.draw.connect(func():
		var t: float = embers.get_meta("t", 0.0)
		var a := clampf(1.0 - t, 0.0, 1.0)
		for e in seeds:
			var p := Vector2(float(e[0]) + float(e[4]) * t, float(e[1]) - float(e[2]) * t * 1.6)
			var r: float = float(e[3]) * (1.0 - t * 0.7)
			embers.draw_circle(p, r + 2.0, Color(W.INK, 0.5 * a))
			embers.draw_circle(p, r, Color(color, a))
			embers.draw_circle(p - Vector2(r, r) * 0.25, r * 0.4, Color(1.0, 0.95, 0.7, a)))
	holder.add_child(embers)
	add_child(holder)
	var tw := holder.create_tween().set_parallel(true)
	tw.tween_property(holder, "position:y", holder.position.y - FLY_RISE, FLY_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2.ONE * FLY_SCALE, FLY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "rotation", deg_to_rad(FLY_TILT), FLY_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 0.0, FLY_TIME * 0.45).set_delay(FLY_TIME * 0.55)
	tw.tween_method(func(v: float):
		embers.set_meta("t", v)
		embers.queue_redraw(), 0.0, 1.0, FLY_TIME)
	tw.chain().tween_callback(holder.queue_free)
	return holder


## Gems collected within a quarter second are shown as one "+N XP" rising from the hero.
func _on_xp_gained(amount: float) -> void:
	if not Settings.float_xp:
		return
	_xp_batch += amount
	if _xp_batch_t <= 0.0:
		_xp_batch_t = 0.25


## Gold picked up within a quarter second is shown as one "+N" with the coin, rising from just above the XP's start (so
## it never covers the hero's head) (pass 47, Garry: "Just as EXP + text floats up from the Player, we should do the
## same for the coins").
func _on_gold_gained(amount: int) -> void:
	if amount <= 0 or not Settings.float_coins:
		return
	_gold_batch += amount
	if _gold_batch_t <= 0.0:
		_gold_batch_t = 0.25


func _tick_gold_popup(delta: float) -> void:
	if _gold_batch_t <= 0.0:
		return
	_gold_batch_t -= delta
	if _gold_batch_t > 0.0:
		return
	var n := _gold_batch
	_gold_batch = 0
	if n <= 0 or game == null or game.player == null or game.camera == null:
		return
	var cam: Camera3D = game.camera.camera
	var wp: Vector3 = game.player.global_position + Vector3(0, 2.1, 0)
	if cam.is_position_behind(wp):
		return
	gold_popup(n, cam.unproject_position(wp) + Vector2(0, -52))


## The gold popup at `at` (its middle): the coin and "+N" in gold with an ink outline, popping in, rising 110 px and
## fading, as the XP's does.
func gold_popup(n: int, at: Vector2) -> Control:
	var px := int(round((32 if n < 50 else 40) * Settings.float_scale()))
	var row := HBoxContainer.new()
	row.name = "GoldPopup"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(px * 1.05, W.BRASS, 3.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)
	var l := W.text("+%s" % W.num(n), W.slab(), px, COIN_GOLD, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.stroke = 2
	l.shadow = 2
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	row.size = Vector2(300, 60)
	row.position = at - Vector2(150, 30)
	row.scale = Vector2(0.6, 0.6)
	row.pivot_offset = row.size * 0.5
	add_child(row)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(row, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "position:y", row.position.y - 110, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(row.queue_free)
	return row


func _tick_xp_popup(delta: float) -> void:
	if _xp_batch_t <= 0.0:
		return
	_xp_batch_t -= delta
	if _xp_batch_t > 0.0:
		return
	var n := int(round(_xp_batch))
	_xp_batch = 0.0
	if n <= 0 or game == null or game.player == null or game.camera == null:
		return
	var cam: Camera3D = game.camera.camera
	var wp: Vector3 = game.player.global_position + Vector3(0, 2.1, 0)
	if cam.is_position_behind(wp):
		return
	var sp := cam.unproject_position(wp)
	var px := int(round((32 if n < 50 else 40) * Settings.float_scale()))
	var l := W.text(Loc.t("ui.hud.xp_gain", {"amount": "%d" % n}), W.slab(), px, W.TOAST_PURPLE, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	l.stroke = 2
	l.shadow = 2
	l.size = Vector2(300, 60)
	l.position = sp - Vector2(150, 30)
	l.scale = Vector2(0.6, 0.6)
	l.pivot_offset = l.size * 0.5
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 110, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


func flash_level(level: int) -> void:
	_lv.text = Loc.t("ui.hud.level", {"level": "%d" % level})
	_fit_top()
	_lv_plate.pivot_offset = _lv_plate.size * 0.5
	var tw := create_tween()
	tw.tween_property(_lv_plate, "scale", Vector2(1.18, 1.18), 0.12)
	tw.tween_property(_lv_plate, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A new stage (Game, the arena's clock): the strip is laid out again (since pass 47 the caps are static, so nothing
## opens; the call stays for the arena and old saves). No stage name on the HUD any more (the pause screen says it).
func refresh_stage() -> void:
	_refresh_rows()


## The timed power-ups as sage plates with their seconds left: a pickup's buff, and Pollen's (pass 49, Garry: "since
## it's a kind of a power-up it should show up in the HUD as well"; Skedaddle, Barrel Rush and the other quiet timers
## have no plate). Pass 48: each plate is matched to its entry in Run.timed by id (they were matched by place, so a
## Skedaddle ahead of a Berserk put its seconds on Berserk's plate) and counts down on Run.buff_clock() (the buffs' own
## clock, which runs on through a boss fight while Run.elapsed holds). Pass 49: a plate goes the moment its seconds run
## out, whether or not Run.tick_timed has taken the buff off yet, and every weapon's Pollen buff shares one plate
## (plate_key) showing the longest of their seconds.
func _refresh_buffs() -> void:
	var now := Run.buff_clock()
	# the plates in Run.timed's order, each once, with the latest end among the buffs it stands for
	var keys: Array = []
	var ends := {}
	for tb in Run.timed:
		var k := plate_key(str(tb["id"]))
		if k == "" or float(tb["until"]) <= now:
			continue
		if not ends.has(k):
			keys.append(k)
			ends[k] = float(tb["until"])
		else:
			ends[k] = maxf(float(ends[k]), float(tb["until"]))
	# pass 119 (lane LEGEND_B): the Pocket Bible's plate while it is held: lit while its block is ready, dim with its
	# seconds while it fills again (bible_plate)
	var bible := bible_plate_key()
	if bible != "":
		keys.append(bible)
	var key := ",".join(keys)
	if key != _buffs_key:
		_buffs_key = key
		for c in _buffs.get_children():
			_buffs.remove_child(c)
			c.queue_free()
		for k: String in keys:
			var def := plate_def(k)
			if def == null:
				continue
			var p := _buff_plate(def, k)
			p.name = "buff"
			p.set_meta("buff", k)
			_buffs.add_child(p)
		_layout_toasts()
	if _adren:
		var parts := buff_parts()
		if not parts.is_empty():
			_adren.text = " · ".join(parts)
		# the toasts sit under the words while they show (pass 56), so their coming and going lays the column out again
		if _adren.visible == parts.is_empty():
			_adren.visible = not parts.is_empty()
			_layout_toasts()
	for c in _buffs.get_children():
		# (pass 122: a WPlate under Wanted, a RoyaleBuffPlate under Royale; both carry `level_text`)
		var p := c as Control
		if p == null or p.get("level_text") == null:
			continue
		var k := str(p.get_meta("buff", ""))
		if ends.has(k):
			var s := "%d" % maxi(int(ceil(float(ends[k]) - now)), 0)
			if str(p.get("level_text")) != s:
				p.set("level_text", s)
				p.queue_redraw()
		elif k.begins_with("passive:"):
			_bible_plate(p)


## A power-up's plate for `def` under its key `k` (pass 122, lane UIHUD): the WPlate of pass 47 under Wanted (pass 106:
## a structure's boost, the War Drum, on the drum's red; pass 119: an item's own plate, the Pocket Bible, on paper; the
## power-ups on sage), the black RoyaleBuffPlate under Royale (Garry: "buffs and pointers on black plates").
func _buff_plate(def: ContentDef, k: String) -> Control:
	var f := W.SAGE
	if k.begins_with("structure:"):
		f = W.ROCK
	if k.begins_with("passive:"):
		f = W.PAPER
	var rp := RoyaleBuffPlate.new(BUFF_PX)
	rp.tex = W.icon_at(def, 0)
	rp.fill = f
	return rp


## Pass 119 (lane LEGEND_B): the Pocket Bible's plate key ("passive:<id>" of the held item whose params carry `bible`
## with `plate`), "" while none is held.
static func bible_plate_key() -> String:
	if Run.bible_left() < 0.0:
		return ""
	var src: Array = Run.item_params("bible")
	if src.is_empty() or not bool((src[1] as Dictionary).get("plate", true)):
		return ""
	return "passive:" + str(src[0])


## The Bible's plate now: whole while the block is ready, at BIBLE_DIM with the seconds to go while it fills again.
const BIBLE_DIM := 0.4


func _bible_plate(p: Control) -> void:
	var left := Run.bible_left()
	var s := "" if left <= 0.0 else "%d" % maxi(int(ceil(left)), 1)
	var a := 1.0 if left <= 0.0 else BIBLE_DIM
	var shown := str(p.get("level_text"))
	if shown != s or absf(p.modulate.a - a) > 0.01:
		# the moment it is spent the plate jumps, as the hit bounces off
		if left > 0.0 and shown == "":
			p.pivot_offset = p.size * 0.5
			var tw := p.create_tween()
			tw.tween_property(p, "scale", Vector2(1.25, 1.25), 0.08)
			tw.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		p.set("level_text", s)
		p.modulate.a = a
		p.queue_redraw()


## The plate a timed buff shows on (pass 49): a pickup's under its own id, every weapon's Pollen buff under
## FlowerField.MUTATION, "" for a buff with no plate.
static func plate_key(id: String) -> String:
	if Registry.pickup(id) != null:
		return id
	if FlowerField.is_buff(id):
		return FlowerField.MUTATION
	# pass 106 (lane DRUM): a structure's buff whose params ask for a plate (the War Drum's boost, "structure:war_drum")
	if id.begins_with("structure:"):
		var sd: StructureDef = Registry.structure(id.trim_prefix("structure:"))
		if sd != null and bool(sd.params.get("plate", false)):
			return id
	return ""


## What a plate shows (its icon): the pickup, or the Pollen mutation (a flower's pickup if that is missing).
static func plate_def(k: String) -> ContentDef:
	if k == FlowerField.MUTATION:
		var m: ContentDef = Registry.mutation(k)
		return m if m != null else Registry.pickup(str(FlowerField.KINDS[0]))
	if k.begins_with("structure:"):
		return Registry.structure(k.trim_prefix("structure:"))
	# pass 119 (lane LEGEND_B): an item's own plate (the Pocket Bible)
	if k.begins_with("passive:"):
		return Registry.passive(k.trim_prefix("passive:"))
	return Registry.pickup(k)


## The words under the slots for what is building up or running (joined with " · "): Adrenaline's stacks, Crescendo,
## Steady Hand (pass 47); pass 48: Gas Mask's damage reduction from the poisoned crowd, and SKEDADDLE while its burst of
## speed runs; pass 49: the attack damage Hot Streak's kills have built. Pass 69 (Garry: "No UI indicators of any
## kind"): the hero's own words of pass 67 are gone with his gauge (MOMENTUM, RAM, OVERDRIVE, HEAT); his momentum shows
## on him, the ball's Heat on the ball.
static func buff_parts() -> Array:
	var parts: Array = []
	if Run.adrenaline > 0:
		parts.append(Loc.t("ui.hud.buff.adrenaline", {"amount": "%d" % Run.adrenaline}))
	if Run.crescendo > 0:
		parts.append(Loc.t("ui.hud.buff.crescendo", {"amount": "%d" % int(round(Run.crescendo_might() * 100.0))}))
	# Steady Hand (pass 47): attack damage that grows while the hero stands still
	var steady := Run.steady_might()
	if steady > 0.0:
		parts.append(Loc.t("ui.hud.buff.steady", {"amount": "%d" % int(round(steady * 100.0))}))
	# Hot Streak (pass 49): the attack damage its kills have built so far, kept for the rest of the run
	var hs := Run.hot_streak_bonus()
	if hs > 0.0:
		parts.append(Loc.t("ui.hud.buff.hot_streak", {"amount": "%d" % int(round(hs * 100.0))}))
	# Gas Mask: the damage reduction the poisoned crowd gives him now
	var gm := Run.gas_mask_dr()
	if gm > 0.0:
		parts.append(Loc.t("ui.hud.buff.gas_mask", {"amount": "%d" % int(round(gm * 100.0))}))
	# Skedaddle: while the burst of speed after a hit runs
	if Run.skedaddle_left() > 0.0:
		parts.append(Loc.t("ui.hud.buff.skedaddle"))
	# pass 126 (lane ITEMS): the Canteen, while its heal after leaving water runs (a quiet timer: words, no plate)
	if Run.canteen_left > 0.0:
		parts.append(Loc.t("ui.hud.buff.canteen"))
	return parts


func tick(delta: float) -> void:
	# pass 87 (lane SUI): the stage's clock, the portal's count or Endless's time (_tick_stage_clock)
	_tick_stage_clock()
	_kills.tick(delta, Run.kills)
	_fit_holders()
	if _timer_plate.size.x > 0.0 and absf(_timer_plate.get_combined_minimum_size().x - _timer_plate.size.x) > 1.0:
		_fit_top()
	_refresh_buffs()
	_toasts.tick(delta)
	# the boss: a banner at 30 s and a toast at 10 s (no countdown label on the HUD any more)
	var boss_t: float = game.director.next_boss_in() if game and game.get("director") and game.director and game.director.has_method("next_boss_in") else -1.0
	if boss_t > 0.0 and boss_t <= 30.0:
		if not _boss_warned:
			_boss_warned = true
			banner(Loc.t("banner.boss_incoming"))
			Audio.play("en_boss_roar")
		if boss_t <= 10.0 and not _boss_ten:
			_boss_ten = true
			toast(Loc.t("toast.boss_in_10"))
	elif boss_t > 45.0 or boss_t < 0.0:
		_boss_warned = false
		_boss_ten = false
	_tick_hero_bars()
	_tick_hp_shake(delta)
	_tick_xp_popup(delta)
	_tick_gold_popup(delta)
	_tick_arrow()
	# the joystick ring follows the thumb; keyboard play (PC) draws none
	if game and game.player and game.player.input and game.player.input.wants_move and not game.player.input.keyboard:
		_ring_pos = game.player.input.origin
		_stick = game.player.input.stick_dir
		_stick_r = game.player.input.radius_px()
		_ring_alpha = 1.0
	elif _ring_alpha > 0.0:
		_ring_alpha = maxf(_ring_alpha - delta * 3.0, 0.0)
	queue_redraw()


## Where the big things are: the boss while it lives (rock), the portal it leaves (sage), the Elite (ember). A tag on
## the screen's edge for each one off screen, none for one on it.
func _tick_arrow() -> void:
	_arrows.clear()
	for t in test_arrows:
		_arrows.append({"pos": t["pos"], "dir": Vector2(float(t["side"]), 0), "color": t["color"], "side": int(t["side"]), "text": t["text"]})
	if game == null or game.player == null or game.camera == null or game.enemies == null:
		_sync_pointers()
		return
	var em: EnemyManager = game.enemies
	if em.boss_index >= 0 and em.is_alive(em.boss_index):
		_edge_arrow(em.pos[em.boss_index], BOSS_RED, Loc.t("ui.hud.arrow.boss"))
	var portal = game.get("portal")
	if portal != null and is_instance_valid(portal):
		_edge_arrow((portal as Node3D).global_position, PORTAL_GREEN, Loc.t("ui.hud.arrow.portal"))
	if game.director and game.director.has_method("elite_position"):
		var ep: Vector3 = game.director.elite_position()
		if ep != Vector3.INF:
			_edge_arrow(ep, ELITE_ORANGE, Loc.t("ui.hud.arrow.elite"))
	# (pass 49, Garry: "don't show the HUD guide to where the Flowers are": Pollen's flowers have no pointers; its buff
	# has a plate among the power-ups, _refresh_buffs)
	_sync_pointers()


## A tag on the left or right edge towards `target`, unless it is on screen: at the height where the line from the
## hero towards it leaves the play area, saying `name` and how far.
func _edge_arrow(target: Vector3, color: Color, name: String) -> void:
	var cam: Camera3D = game.camera.camera
	var vp := get_viewport().get_visible_rect().size
	# from 140 px under the slots (and POINTER_CLEAR under whatever hangs lowest under them, pass 56: the boss's bar sits
	# lower under the power-ups) to 200 px over the screen's foot
	var top := maxf(_slots_bottom + 140.0, _under_bottom + POINTER_CLEAR)
	var rect := Rect2(Vector2(0, top), Vector2(vp.x, maxf(vp.y - 200.0 - top, 0.0)))
	if not cam.is_position_behind(target + Vector3(0, 1, 0)):
		var sp := cam.unproject_position(target + Vector3(0, 1, 0))
		if Rect2(Vector2.ZERO, vp).has_point(sp) and sp.y > _slots_bottom:
			return
	var d: Vector3 = target - game.player.global_position
	d.y = 0.0
	var yaw: float = game.camera.current_yaw()
	var cf := Vector3(-sin(yaw), 0, -cos(yaw))
	var cr := Vector3(-cf.z, 0, cf.x)
	var dir := Vector2(d.dot(cr), -d.dot(cf))
	if dir.length_squared() < 0.001:
		return
	dir = dir.normalized()
	var origin := Vector2(vp.x * 0.5, vp.y * 0.55)
	if not cam.is_position_behind(game.player.global_position):
		origin = cam.unproject_position(game.player.global_position)
	var side := 1 if dir.x >= 0.0 else -1
	var t := 1e9
	if absf(dir.x) > 0.0001:
		t = ((vp.x if side > 0 else 0.0) - origin.x) / dir.x
	var at := origin + dir * maxf(t, 0.0)
	at.y = clampf(at.y, rect.position.y, rect.end.y)
	# no name: the chevron alone
	var said := Loc.t("ui.hud.arrow.distance", {"name": name, "distance": "%d" % int(round(d.length()))}) if name != "" else ""
	_arrows.append({"pos": at, "dir": dir, "color": color, "side": side, "text": said})


func _sync_pointers() -> void:
	var vp := get_viewport().get_visible_rect().size
	while _pointers.size() < _arrows.size():
		var p := WPointer.new()
		add_child(p)
		_pointers.append(p)
	for k in range(_pointers.size()):
		var p: WPointer = _pointers[k]
		if k >= _arrows.size():
			p.visible = false
			continue
		var a: Dictionary = _arrows[k]
		p.color = a["color"]
		p.text = str(a["text"])
		p.side = int(a["side"])
		var pos: Vector2 = a["pos"]
		p.position = Vector2(0.0 if p.side < 0 else vp.x - p.size.x, pos.y - p.size.y * 0.5)
		p.visible = true
		p.queue_redraw()


func _draw() -> void:
	_draw_hero_bars()
	if _ring_alpha <= 0.0:
		return
	# the joystick: a 300 px ring in 55 % ink over a faint paper disc, a 110 px paper knob
	var a := _ring_alpha
	draw_circle(_ring_pos, _stick_r + 3.0, Color(W.PAPER.r, W.PAPER.g, W.PAPER.b, 0.15 * a), true, -1.0, true)
	draw_arc(_ring_pos, _stick_r, 0.0, TAU, 64, Color(W.INK.r, W.INK.g, W.INK.b, 0.55 * a), 6.0, true)
	var kr := _stick_r * 0.367
	var knob := _ring_pos + _stick * _stick_r
	draw_circle(knob, kr, Color(W.PAPER.r, W.PAPER.g, W.PAPER.b, 0.7 * a), true, -1.0, true)
	draw_arc(knob, kr, 0.0, TAU, 48, Color(W.INK.r, W.INK.g, W.INK.b, 0.6 * a), 5.0, true)


# ---------------------------------------------------------------- the stage clock, the portal's count, Endless (pass 87, lane SUI)

## Garry (pass 87): after the boss "the Portal that appears shows a 1 minute timer before the Endless Mode will activate";
## Endless is "a huge wave of enemies ... and every 10 seconds the power of the next wave ... becomes stronger". The clock
## plate says which clock it is showing: the stage's own time (from 00:00 at the stage's start, lane SGAME's
## stage clock) on paper; while the portal waits, the seconds left before Endless on rock with ENDLESS IN hanging under
## it (the tag, pulsing in its last STAGE_TAG_WARN seconds); in Endless the time survived in it on ink with WAVE n under
## it (a pulse on each new wave), and an ENDLESS banner in rock as it starts.
const STAGE_TAG_PX := 20
const STAGE_TAG_WARN := 10.0
var _stage_tag: PanelContainer
var _stage_tag_text: WText
var _clock_mode := ""
var _clock_box_paper: StyleBox
var _was_endless := false
var _endless_wave_seen := 0
var _tag_pulse_at := -1
## A capture tool's or a test's clock (pass 87): {portal_left, endless, endless_wave, endless_seconds, stage_seconds},
## each read in place of the game's when present (as test_arrows pins pointers).
var test_stage_clock: Dictionary = {}


## The clock plate's words and look, and the tag under it, each frame of the run (tick).
func _tick_stage_clock() -> void:
	if _stage_tag == null:
		_build_stage_tag()
	var mode := ""
	var left := portal_left()
	var in_endless: bool = bool(test_stage_clock.get("endless", Run.endless))
	if in_endless:
		mode = "endless"
	elif left > 0.0:
		mode = "portal"
	if mode != _clock_mode:
		_set_clock_mode(mode)
	match mode:
		"portal":
			var whole := int(ceil(left))
			_timer.text = W.mmss(float(whole))
			if left <= STAGE_TAG_WARN and whole != _tag_pulse_at:
				_tag_pulse_at = whole
				_pulse_stage_tag()
		"endless":
			_timer.text = W.mmss(endless_seconds())
			var wave := endless_wave()
			_stage_tag_text.text = Loc.t("ui.hud.wave", {"wave": "%d" % maxi(wave, 1)})
			if wave != _endless_wave_seen:
				if _endless_wave_seen > 0:
					_pulse_stage_tag()
				_endless_wave_seen = wave
			_place_stage_tag()
		_:
			_timer.text = W.mmss(float(test_stage_clock.get("stage_seconds", stage_seconds())))
	# Endless began: its banner (whoever started it; the same words while up are not shown twice)
	if in_endless and not _was_endless:
		endless_banner()
	_was_endless = in_endless


## The ENDLESS banner, in rock (pass 87).
func endless_banner() -> void:
	banner(Loc.t("banner.endless"))
	var hb := W.box(W.ROCK, 4, 5).pad(52, 14, 52, 14)
	hb.themed = false   # pass 122: the banner stays as it is under both themes (Garry)
	_banner.add_theme_stylebox_override("panel", hb)


func _build_stage_tag() -> void:
	_clock_box_paper = _timer_plate.get_theme_stylebox("panel")
	_stage_tag = PanelContainer.new()
	_stage_tag.name = "StageTag"
	_stage_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_tag_text = W.text("", W.slab(W.em(STAGE_TAG_PX, 0.08)), STAGE_TAG_PX, W.PAPER, HORIZONTAL_ALIGNMENT_CENTER, STAGE_TAG_PX * 1.2)
	_stage_tag.add_child(_stage_tag_text)
	_stage_tag.visible = false
	_top.add_child(_stage_tag)


## Paper for the stage's clock, rock for the portal's count, ink for Endless; the tag under it says which. Pass 122,
## under Royale: the clock stays on its black plate, its digits the kit's soft red while the portal counts down and white
## otherwise; ENDLESS IN a black pill in that red, WAVE n a red tag (the kit's tag: a 3 px navy edge, 4 px corners) in
## cream. `_apply_theme` calls it again with the mode it is in when the theme flips.
func _set_clock_mode(mode: String) -> void:
	_clock_mode = mode
	_tag_pulse_at = -1
	match mode:
		"portal":
			_timer_plate.add_theme_stylebox_override("panel", _clock_box_paper)
			_timer.color = ROYALE_WARN_TEXT
			_stage_tag_text.text = Loc.t("ui.hud.endless_in")
			_stage_tag_text.color = ROYALE_WARN_TEXT
			_stage_tag.add_theme_stylebox_override("panel", W.plate_box(3, 3).pad(14, 3, 14, 4))
			_stage_tag.visible = true
		"endless":
			_timer_plate.add_theme_stylebox_override("panel", _clock_box_paper)
			_timer.color = R.WHITE
			_stage_tag_text.text = Loc.t("ui.hud.wave", {"wave": "%d" % maxi(endless_wave(), 1)})
			_stage_tag_text.color = R.CREAM
			_stage_tag.add_theme_stylebox_override("panel", W.box(R.TAG_RED, R.TAG_EDGE, 0, R.RADIUS_TAG).pad(14, 3, 14, 4))
			_stage_tag.visible = true
			_endless_wave_seen = endless_wave()
		_:
			if _clock_box_paper:
				_timer_plate.add_theme_stylebox_override("panel", _clock_box_paper)
			_timer.color = R.WHITE
			_stage_tag.visible = false
	_fit_top()
	_place_stage_tag()
	_place_kills()


## The tag hangs from the clock plate's foot, centred under it (over the gap between the weapons and the lines).
func _place_stage_tag() -> void:
	if _stage_tag == null or not _stage_tag.visible:
		return
	_stage_tag.reset_size()
	var s := _stage_tag.get_combined_minimum_size()
	_stage_tag.size = s
	_stage_tag.pivot_offset = s * 0.5
	_stage_tag.position = Vector2(_timer_plate.position.x + (_timer_plate.size.x - s.x) * 0.5, _timer_plate.position.y + _timer_plate.size.y - 6.0)


func _pulse_stage_tag() -> void:
	if _stage_tag == null:
		return
	_stage_tag.pivot_offset = _stage_tag.size * 0.5
	_stage_tag.scale = Vector2.ONE * 1.22
	var tw := _stage_tag.create_tween()
	tw.tween_property(_stage_tag, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


const KILLS_TAG_GAP := 6.0


func _place_kills() -> void:
	if _kills == null:
		return
	var y := SLOT_Y + _slot_row_h * 0.5 - _kills.row_height() * 0.5
	y = maxf(y, _timer_plate.position.y + _timer_plate.size.y + KILLS_TAG_GAP)
	if _stage_tag != null and _stage_tag.visible:
		y = maxf(y, _stage_tag.position.y + _stage_tag.size.y + KILLS_TAG_GAP)
	_kills.position = Vector2(_timer_plate.position.x + _timer_plate.size.x * 0.5, y)


## The middle of the item slots' (first) row in the top bar's space (pass 110: the kill counter's middle sits on it).
func slots_middle_y() -> float:
	return SLOT_Y + _slot_row_h * 0.5


## The kill counter (tests, captures).
func kill_counter() -> WKillCount:
	return _kills


## Which clock the plate shows now: "" (the stage's), "portal" or "endless" (tests and tools).
func clock_mode() -> String:
	return _clock_mode


## The tag's words under the clock ("" when it is not shown).
func stage_tag_text() -> String:
	return _stage_tag_text.text if _stage_tag and _stage_tag.visible else ""


## The seconds the portal has left before Endless (lane SGAME's Game.portal_seconds_left()); -1 when none counts.
func portal_left() -> float:
	if test_stage_clock.has("portal_left"):
		return float(test_stage_clock["portal_left"])
	if game and game.has_method("portal_seconds_left"):
		return float(game.call("portal_seconds_left"))
	return -1.0


## The stage's own clock (00:00 at the stage's start; lane SGAME's Run.stage_clock()).
static func stage_seconds() -> float:
	return Run.stage_clock()


## Seconds survived in Endless (Run.endless_time) and its wave (Run.endless_wave(), 1 the first; lane SGAME).
func endless_seconds() -> float:
	if test_stage_clock.has("endless_seconds"):
		return float(test_stage_clock["endless_seconds"])
	return Run.endless_time


func endless_wave() -> int:
	if test_stage_clock.has("endless_wave"):
		return int(test_stage_clock["endless_wave"])
	return Run.endless_wave()


## Game's announcements (lane SGAME: WaveDirector.endless_started / endless_wave_started): the ENDLESS banner, and the
## WAVE tag's pulse with its new number on each wave after the first.
func on_endless_started() -> void:
	endless_banner()


func on_endless_wave(w: int) -> void:
	if _stage_tag == null or _clock_mode != "endless":
		return
	_stage_tag_text.text = Loc.t("ui.hud.wave", {"wave": "%d" % maxi(w, 1)})
	_place_stage_tag()
	if w > _endless_wave_seen and _endless_wave_seen > 0:
		_pulse_stage_tag()
	_endless_wave_seen = maxi(w, _endless_wave_seen)


# ---------------------------------------------------------------- pass 122 (lane UIHUD): the HUD under the Royale theme

## The HUD's own pieces styled for the theme, at build (`initial`: _ready lays the rows out itself) and
## again when the UI theme or the slot-rarity switch flips in a run (Settings.changed; the in-run debug panel's two
## buttons): the strip above the rail and the rail's trough, the top row's words (white Ultra with the navy edge on
## the black plates, or ink slab on paper), the pause button, MUTATION NEXT, the words under the slots, the clock's
## mode, and the slots and the power-ups laid out again (their frames read the theme and the switch as they are
## built). The kit's own pieces (the plates' boxes, the item frames, the pointers, the coin) read the theme as they draw,
## so the three plates and the coin are queued to draw again here (the review of lane UIHUD: a plate's words keep their
## Wanted box, so _fit_top gives it no new size and no redraw, and the coin redraws only on its own setters; a flip in a
## run left the gold plate paper with its ink border and the coin brass until the purse changed its digit count or a
## modal hid and showed the HUD). The pointers queue their own redraw every tick (_sync_pointers).
func _apply_theme(initial: bool = false) -> void:
	var rarity := bool(Settings.hud_slot_rarity)
	if not initial and rarity == _slot_rarity_applied:
		return
	_slot_rarity_applied = rarity
	_cutout.color = ROYALE_RAIL_BLACK
	_style_text(_lv, PLATE_PX, R.WHITE, -1, -1, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_style_text(_timer, TIMER_PX, R.WHITE, -1, -1, HORIZONTAL_ALIGNMENT_CENTER, TIMER_PX * 1.15)
	_style_text(_gold, PLATE_PX, R.WHITE, -1, -1, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_style_text(_mut_word, MUT_WORD_PX, R.WHITE, 4, 0, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	_style_text(_adren, 28, R.WHITE, 2, 3, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_style_pause()
	for p in [_lv_plate, _timer_plate, _gold_plate]:
		(p as Control).queue_redraw()
	if _coin != null:
		_coin.queue_redraw()
	_refresh_mut_mark(true)
	if _stage_tag != null:
		_set_clock_mode(_clock_mode)
	_rail.queue_redraw()
	if not initial:
		_buffs_key = ""
		_refresh_rows()
		_refresh_buffs()


## A WText of the HUD's own in the theme: under Royale the display face (Ultra from 28 px, Rubik 700 under it, as
## W.slab_for), `royale_col`, a navy stroke and a straight navy drop (`stroke` / `shadow` px as the HUD sets them, or
## the kit's edge when both are -1), the Wanted face's line box so a plate keeps its height (the words centred in it,
## as CSS half-leading does); under Wanted the Alfa Slab face, `wanted_col`, ink, the drop down-right, `line_h` as
## built: exactly what W.text built, so a theme put back leaves no trace.
func _style_text(t: WText, px: int, royale_col: Color, stroke: int, shadow: int,
		align: int, line_h: float, track: int = 0) -> void:
	if t == null:
		return
	t.align = align
	t.font = W.slab_for(px, track)
	t.color = royale_col
	t.line_height = line_h if line_h > 0.0 else W.normal_height(wanted_slab(track), px)
	if stroke < 0:
		R.edge(t, px)
	else:
		t.stroke = stroke
		t.shadow = shadow
		t.stroke_color = R.NAVY
		t.shadow_color = R.NAVY
		t.shadow_straight = true
		t.bevel = 0
	t.queue_redraw()


## The pause button's boxes for the theme: the brass disc on its ink shadow (pass 41) under Wanted; under Royale a
## slate Royale button, the same 78 px square with the kit's 6 px corners on the kit's base (pressed it moves 8 px down
## with no base, as every Royale button), the two bars in the slate role's cream.
func _style_pause() -> void:
	var pb: HardBox
	pb = W.box(W.PAPER, R.BUTTON_EDGE, R.BUTTON_BASE, R.RADIUS)
	pb.role = "slate"
	_pause_btn.box_down = pb.pressed()
	_pause_btn.box = pb
	var bars := _pause_btn.get_node_or_null("PauseBars")
	if bars:
		for b in bars.get_children():
			(b as ColorRect).color = R.role("slate")["text"]


## The XP rail (pass 56 / 61: RAIL_H of ink, the purple fill RAIL_INSET in from its top and bottom). Pass 122, under
## Royale: the trough in the kit's plate black (opaque: the rail is the top of the screen, pass 47d), the fill the
## kit's bright purple two-tone band with its lip (WBar.kind_fill "xp": brighter than the mock's, Garry), the same
## height and inset, its right end rounded by the kit's 6 px (the band starts off screen so its left end stays square).
func _draw_rail() -> void:
	var w := _rail.size.x
	_rail.draw_rect(Rect2(0, 0, w, RAIL_H), ROYALE_RAIL_BLACK)
	if _xp_frac > 0.0:
		var fl: Array = WBar.kind_fill("xp")
		var rad := R.RADIUS
		WBar.fill_band(_rail, Rect2(-rad, RAIL_INSET, w * _xp_frac + rad, RAIL_H - 2.0 * RAIL_INSET), fl[0], fl[1], rad)


## A top plate's words in a holder: a plain Control whose minimum size is the Wanted face's box for the words
## (_fit_holders), so the plate's rect is the same under both themes (Garry: the same sizes), the words centred in it
## (the Royale face is 5-10 % wider at the same size and reaches a few px into the plate's padding).
func _hold(t: WText) -> Control:
	var h := Control.new()
	h.name = "Hold"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	h.resized.connect(func(): _center_held(t, h))
	return h


## The three holders sized to the Wanted face's box for their words now, the words centred (every frame from tick,
## and from _fit_top: the words change with the level, the clock and the purse).
func _fit_holders() -> void:
	for trio in [[_lv, _lv_hold, PLATE_PX], [_timer, _timer_hold, TIMER_PX], [_gold, _gold_hold, PLATE_PX]]:
		var t: WText = trio[0]
		var h: Control = trio[1]
		if t == null or h == null:
			continue
		var box := _wanted_box(t, int(trio[2]))
		if not h.custom_minimum_size.is_equal_approx(box):
			h.custom_minimum_size = box
		_center_held(t, h)


## The Wanted face's box for `t`'s words at `px`: the WText's own minimum size under Wanted; under Royale the same
## measure taken with the Wanted face (a TextParagraph's width, as WText shapes it, and the line box WText uses),
## remembered per words and size (the clock's words change every second; the table is emptied past WANTED_BOXES_MAX).
var _wanted_boxes: Dictionary = {}
const WANTED_BOXES_MAX := 128


func _wanted_box(t: WText, px: int) -> Vector2:
	var key := "%s|%d|%.2f" % [t.text, px, t.line_height]
	if _wanted_boxes.has(key):
		return _wanted_boxes[key]
	var p := TextParagraph.new()
	p.add_string(t.text, wanted_slab(), px)
	var lh := t.line_height if t.line_height > 0.0 else W.normal_height(wanted_slab(), px)
	var box := Vector2(ceilf(p.get_size().x), ceilf(lh))
	if _wanted_boxes.size() >= WANTED_BOXES_MAX:
		_wanted_boxes.clear()
	_wanted_boxes[key] = box
	return box


## `t` at its own size, centred in its holder `h` (at 0, 0 under Wanted, where the two boxes are one).
func _center_held(t: WText, h: Control) -> void:
	var s := t.get_combined_minimum_size()
	t.size = s
	t.position = Vector2(roundf((h.size.x - s.x) * 0.5), roundf((h.size.y - s.y) * 0.5))


## The Wanted slab face (Alfa Slab One, tracked `track` px) whatever the theme: for the pieces Garry keeps exactly as
## they are (the kill counter's number, the boss's name) and for the Wanted box the top plates keep.
static func wanted_slab(track: int = 0) -> Font:
	return W.wanted_slab(track)


## A slab WText held to the Wanted face and its ink edge whatever the theme (Garry: "keep the kill counter exactly as
## it is now, and the boss name as well"): W.text had set the theme's face and edge at construction; this puts the
## Wanted ones back (the face, ink for the stroke and the shadow, the shadow down-right, no bevel). The caller's own
## stroke and shadow sizes and its colour are left to it.
static func keep_wanted(t: WText, track: int = 0) -> WText:
	t.font = wanted_slab(track)
	t.stroke_color = W.INK
	t.shadow_color = W.INK
	t.shadow_straight = false
	t.bevel = 0
	return t


## A power-up's plate under Royale (Garry: "buffs ... on black plates"): the Wanted plate's 72 px footprint, the kit's
## black info plate (R.plate: 56 % black, the white inset, 6 px corners, no edge, no base), the icon at ICON_FRAC with
## a hard drop, and the seconds (or the Bible's wait) as white Rubik 700 (TAG_PX, under the kit's Ultra minimum) in a
## navy pill over the bottom-right corner, where the Wanted tag sits (TAG_OVER past the corner, as the tag's 10 px).
## `tex`, `level_text`, `fill` and `modulate` are what _refresh_buffs and _bible_plate set on a WPlate, so both plates
## are driven alike (the row is built again when the theme flips: _apply_theme).
class RoyaleBuffPlate extends Control:
	const ICON_FRAC := 0.66
	const TAG_PX := 20
	const TAG_PAD := 8.0
	const TAG_OVER := 10.0
	var tex: Texture2D
	var level_text := "":
		set(v):
			level_text = v
			queue_redraw()
	var fill := W.SAGE
	var side := 72.0


	func _init(px: float = 72.0) -> void:
		side = px
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(px, px)


	## The seconds pill's box (its bottom-right corner TAG_OVER past the plate's); an empty rect without a text.
	func tag_rect() -> Rect2:
		if level_text == "":
			return Rect2()
		var f := W.slab_for(TAG_PX)
		var tw := f.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX).x
		var h := ceilf(f.get_height(TAG_PX)) + 4.0
		var w := ceilf(tw) + TAG_PAD * 2.0
		return Rect2(Vector2(side - w + TAG_OVER, side - h + TAG_OVER), Vector2(w, h))


	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(side, side))
		R.plate(get_canvas_item(), r, R.RADIUS)
		if tex:
			var inner := side * ICON_FRAC
			var ts := tex.get_size()
			var k := inner / maxf(ts.x, ts.y)
			var sz := ts * k
			var at := (Vector2(side, side) - sz) * 0.5
			draw_texture_rect(tex, Rect2(at + Vector2(0.0, 2.0), sz), false, R.FRAME_ICON_DROP)
			draw_texture_rect(tex, Rect2(at, sz), false, Color.WHITE)
		if level_text != "":
			var f := W.slab_for(TAG_PX)
			var rect := tag_rect()
			R.flat(R.NAVY, R.RADIUS_TAG).draw(get_canvas_item(), rect)
			var base := rect.position.y + (rect.size.y - f.get_height(TAG_PX)) * 0.5 + f.get_ascent(TAG_PX)
			draw_string(f, Vector2(rect.position.x + TAG_PAD, base), level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_PX, R.WHITE)
