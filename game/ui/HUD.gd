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
class_name HUD
extends Control

signal pause_requested

## The XP rail across the top edge (pass 56, Garry: "Make the EXP bar twice as thick, move all the other UI with it
## accordingly"; "a plain fill, just twice as thick"): RAIL_H of ink (18 px before), the purple fill RAIL_INSET in from its
## top and bottom (3 before), so the fill keeps two thirds of it. The level-up screen's rainbow rail (CardScreen) reads
## both, so the two rails can never differ again. The top row, the slots and the strip are laid out from the rail's
## bottom, each from the one above it, so a thicker rail moves them all down by what it gained and every gap stays.
const RAIL_H := 36.0
const RAIL_INSET := 6.0
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

var game: Node
var _band: Control
var _rail: Control
var _cutout: ColorRect
var _top: Control
var _lv_plate: PanelContainer
var _lv: WText
var _timer_plate: PanelContainer
var _timer: WText
var _gold_plate: PanelContainer
var _gold: WText
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_band()
	_build_boss()
	_toasts = WToasts.new()
	add_child(_toasts)
	_banner = WBanner.new()
	add_child(_banner)
	Run.xp_changed.connect(func(xp, need): _set_xp(xp, need); _lv.text = "LV %d" % Run.level; _fit_top())
	Run.xp_gained.connect(_on_xp_gained)
	Run.gold_changed.connect(func(g): _gold.text = W.num(g); _fit_top())
	# the gold the hero picks up rises from him like the XP (pass 47); Run says how much each pickup really paid
	Run.gold_gained.connect(_on_gold_gained)
	Run.build_changed.connect(_refresh_rows)
	if game and game.player:
		game.player.input.touch_started.connect(func(p): _ring_pos = p; _ring_alpha = 1.0)
		game.player.input.touch_ended.connect(func(): _ring_alpha = 0.0)
	_refresh_rows()
	_set_xp(Run.xp, Run.xp_to_next())
	_gold.text = W.num(Run.run_gold)
	_lv.text = "LV %d" % Run.level
	# the top row in place at once (pass 56: a tool that tapped the pause disc in the frame the run loaded found it still
	# at the row's corner, under the LV plate), and again once the plates have their sizes
	_fit_top()
	_fit_top.call_deferred()
	_layout_toasts()


## While a modal that pauses the run is up (level-up, chest, shop, pause...), the HUD steps aside; the gate brings it
## back so the card can land in its slot.
func _process(_delta: float) -> void:
	var covered := false
	for m in get_tree().get_nodes_in_group("wanted_modal"):
		if (m as CanvasItem).visible:
			covered = true
			break
	if visible == covered:
		visible = not covered


func _plate(border: int = 4, shadow: int = 5, pad := Vector2(18, 4)) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, border, shadow).pad(pad.x + border, pad.y + border, pad.x + border, pad.y + border))
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
	_rail.draw.connect(func():
		_rail.draw_rect(Rect2(0, 0, _rail.size.x, RAIL_H), W.INK)
		if _xp_frac > 0.0:
			_rail.draw_rect(Rect2(0, RAIL_INSET, _rail.size.x * _xp_frac, RAIL_H - 2.0 * RAIL_INSET), W.EPIC))
	add_child(_rail)
	_top = Control.new()
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_top = W.safe_top()
	_top.offset_bottom = W.safe_top() + SLOT_Y - 10.0
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	_lv_plate = _plate()
	_lv = W.text("LV 1", W.slab(), PLATE_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_lv_plate.add_child(_lv)
	_lv_plate.position = Vector2(36, TOP_Y)
	_top.add_child(_lv_plate)
	_timer_plate = _plate(4, 5, Vector2(32, 0))
	_timer = W.text("00:00", W.slab(), TIMER_PX, W.INK, HORIZONTAL_ALIGNMENT_CENTER, TIMER_PX * 1.15)
	_timer_plate.add_child(_timer)
	_timer_plate.position = Vector2(400, TOP_Y)
	_top.add_child(_timer_plate)
	_gold_plate = _plate()
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 10)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gr.add_child(WCoin.make(32.0))
	_gold = W.text("0", W.slab(), PLATE_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gr.add_child(_gold)
	_gold_plate.add_child(gr)
	_top.add_child(_gold_plate)
	# the brass pause disc: a 4 px border, two ink bars
	_pause_btn = WTap.new()
	var pb := W.box(W.BRASS, 4, 5, int(DISC * 0.5))
	_pause_btn.box = pb
	_pause_btn.box_down = pb.pressed(W.BRASS_DARK)
	_pause_btn.custom_minimum_size = Vector2(DISC, DISC)
	_pause_btn.size = Vector2(DISC, DISC)
	var bars := HBoxContainer.new()
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 10)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var b := ColorRect.new()
		b.color = W.INK
		b.custom_minimum_size = Vector2(10, 30)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars.add_child(b)
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
	for p in [_lv_plate, _timer_plate, _gold_plate]:
		(p as Control).reset_size()
	_lv_plate.position = Vector2(36, TOP_Y)
	_timer_plate.position = Vector2((w - _timer_plate.size.x) * 0.5, TOP_Y)
	_gold_plate.position = Vector2(w - 36 - DISC - 18 - _gold_plate.size.x, TOP_Y)
	_pause_btn.position = Vector2(w - 36 - DISC, TOP_Y - 2)
	_pause_btn.size = Vector2(DISC, DISC)


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
	_boss_name.stroke = 5
	_boss_name.shadow = 4
	_boss_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_boss_name)
	_boss_box.add_child(row)
	_boss_bar = WBar.make(1.0, W.ROCK, 30.0, 4, 4)
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


func hide_boss() -> void:
	_boss_box.visible = false
	_layout_toasts()


## Under the slots: the boss's plate and bar while a boss lives, the power-ups on the left, and the toasts below
## whichever is lowest.
func _layout_toasts() -> void:
	var w := get_viewport_rect().size.x
	_boss_box.position = Vector2(60, _slots_bottom + 20.0)
	_boss_box.size = Vector2(w - 120, 0)
	_buffs.position = Vector2(36, _slots_bottom + 14.0)
	_adren.position = Vector2(36, _slots_bottom + 14.0 + (74.0 if _buffs.get_child_count() > 0 else 0.0))
	var y := _slots_bottom + 18.0
	if _boss_box.visible:
		y = _boss_box.position.y + _boss_box.get_combined_minimum_size().y + 20.0
	_toasts.position = Vector2(0, y)
	_toasts.size = Vector2(w, 200)


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


func _draw_hero_bars() -> void:
	if not _hero_bars or _bar_w <= 0.0 or (game and game.player and game.player.dead):
		return
	var hh := _bar_h + 4.0
	var r := Rect2(_bar_c - Vector2(_bar_w * 0.5, hh * 0.5), Vector2(_bar_w, hh))
	draw_rect(r, W.INK)
	if _hp > 0.0:
		var fr := r.grow(-2.0)
		draw_rect(Rect2(fr.position, Vector2(fr.size.x * _hp, fr.size.y)), W.SAGE if _hp > 0.35 else W.ROCK)
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


func toast(text: String, color: Color = W.PAPER) -> void:
	_toasts.push(text, color)


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
		_banner.add_theme_stylebox_override("panel", W.box(color, 4, 5).pad(52, 14, 52, 14))


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
	var l := W.text("+%d XP" % n, W.slab(), px, W.TOAST_PURPLE, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
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
	_lv.text = "LV %d" % level
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
			var p := WPlate.new().for_def(def, 72.0)
			p.fill = W.SAGE
			p.icon_frac = 0.66
			p.level_size = 20
			p.name = "buff"
			p.set_meta("buff", k)
			_buffs.add_child(p)
		_layout_toasts()
	if _adren:
		var parts := buff_parts()
		_adren.visible = not parts.is_empty()
		if not parts.is_empty():
			_adren.text = " · ".join(parts)
	for c in _buffs.get_children():
		var p := c as WPlate
		if p == null:
			continue
		var k := str(p.get_meta("buff", ""))
		if ends.has(k):
			var s := "%d" % maxi(int(ceil(float(ends[k]) - now)), 0)
			if p.level_text != s:
				p.level_text = s
				p.queue_redraw()


## The plate a timed buff shows on (pass 49): a pickup's under its own id, every weapon's Pollen buff under
## FlowerField.MUTATION, "" for a buff with no plate.
static func plate_key(id: String) -> String:
	if Registry.pickup(id) != null:
		return id
	if FlowerField.is_buff(id):
		return FlowerField.MUTATION
	return ""


## What a plate shows (its icon): the pickup, or the Pollen mutation (a flower's pickup if that is missing).
static func plate_def(k: String) -> ContentDef:
	if k == FlowerField.MUTATION:
		var m: ContentDef = Registry.mutation(k)
		return m if m != null else Registry.pickup(str(FlowerField.KINDS[0]))
	return Registry.pickup(k)


## The words under the slots for what is building up or running (joined with " · "): Adrenaline's stacks, Crescendo,
## Steady Hand (pass 47); pass 48: Gas Mask's damage reduction from the poisoned crowd, and SKEDADDLE while its burst of
## speed runs; pass 49: the attack damage Hot Streak's kills have built.
static func buff_parts() -> Array:
	var parts: Array = []
	if Run.adrenaline > 0:
		parts.append("ADRENALINE ×%d" % Run.adrenaline)
	if Run.crescendo > 0:
		parts.append("CRESCENDO +%d%%" % int(round(Run.crescendo_might() * 100.0)))
	# Steady Hand (pass 47): attack damage that grows while the hero stands still
	var steady := Run.steady_might()
	if steady > 0.0:
		parts.append("STEADY +%d%%" % int(round(steady * 100.0)))
	# Hot Streak (pass 49): the attack damage its kills have built so far, kept for the rest of the run
	var hs := Run.hot_streak_bonus()
	if hs > 0.0:
		parts.append("HOT STREAK +%d%%" % int(round(hs * 100.0)))
	# Gas Mask: the damage reduction the poisoned crowd gives him now
	var gm := Run.gas_mask_dr()
	if gm > 0.0:
		parts.append("GAS MASK %d%%" % int(round(gm * 100.0)))
	# Skedaddle: while the burst of speed after a hit runs
	if Run.skedaddle_left() > 0.0:
		parts.append("SKEDADDLE")
	return parts


func tick(delta: float) -> void:
	_timer.text = W.mmss(Run.elapsed)
	if _timer_plate.size.x > 0.0 and absf(_timer_plate.get_combined_minimum_size().x - _timer_plate.size.x) > 1.0:
		_fit_top()
	_refresh_buffs()
	_toasts.tick(delta)
	# the boss: a banner at 30 s and a toast at 10 s (no countdown label on the HUD any more)
	var boss_t: float = game.director.next_boss_in() if game and game.get("director") and game.director and game.director.has_method("next_boss_in") else -1.0
	if boss_t > 0.0 and boss_t <= 30.0:
		if not _boss_warned:
			_boss_warned = true
			banner("BOSS INCOMING")
			Audio.play("en_boss_roar")
		if boss_t <= 10.0 and not _boss_ten:
			_boss_ten = true
			toast("BOSS IN 10 s")
	elif boss_t > 45.0 or boss_t < 0.0:
		_boss_warned = false
		_boss_ten = false
	_tick_hero_bars()
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
		_edge_arrow(em.pos[em.boss_index], BOSS_RED, "BOSS")
	var portal = game.get("portal")
	if portal != null and is_instance_valid(portal):
		_edge_arrow((portal as Node3D).global_position, PORTAL_GREEN, "PORTAL")
	if game.director and game.director.has_method("elite_position"):
		var ep: Vector3 = game.director.elite_position()
		if ep != Vector3.INF:
			_edge_arrow(ep, ELITE_ORANGE, "ELITE")
	# (pass 49, Garry: "don't show the HUD guide to where the Flowers are": Pollen's flowers have no pointers; its buff
	# has a plate among the power-ups, _refresh_buffs)
	_sync_pointers()


## A tag on the left or right edge towards `target`, unless it is on screen: at the height where the line from the
## hero towards it leaves the play area, saying `name` and how far.
func _edge_arrow(target: Vector3, color: Color, name: String) -> void:
	var cam: Camera3D = game.camera.camera
	var vp := get_viewport().get_visible_rect().size
	var rect := Rect2(Vector2(0, _slots_bottom + 140.0), Vector2(vp.x, vp.y - _slots_bottom - 340.0))
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
	var said := "%s %d m" % [name, int(round(d.length()))] if name != "" else ""
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
