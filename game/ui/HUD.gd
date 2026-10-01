## In-run HUD, "Wanted" (design_handoff_88fits_wanted, screens 06 and 06b): an ink XP rail across the top edge, a row of
## paper plates (LV, the clock, gold) with the brass pause disc, the held items as plates with their level tags and
## path rivets, the toast queue under the clock, the boss's name plate and bar only while a boss lives, pointers riding
## the screen edge, the hero's bars under him and the floating joystick. A banner takes the top row for 2 s. A tap
## anywhere on the top strip pauses. Nothing interactive lives between y 700 and 1600.
class_name HUD
extends Control

signal pause_requested

## Height of the strip in design px with one slot row: the top row and the slots. A build that needs two rows makes
## it taller (`band_h`); PlayerInput's thumb zone starts just below `band_h`, and a tap anywhere on the strip pauses.
## Everything on the strip sits `W.safe_top()` lower on a phone with a camera cutout (pass 43).
const BAND_H := 236
## The compact top (pass 41: the mock's row, 44 px plates from y 44 and 104 px weapon slots from y 170, took a fifth
## of the phone's height): the row's line and type, the pause disc, the slots' line and sizes.
const TOP_Y := 30.0
const PLATE_PX := 36
const TIMER_PX := 56
const DISC := 78.0
const RAIL_H := 18.0
const SLOT_Y := 126.0
const WEAPON_PX := 88.0
const OTHER_PX := 74.0
const SLOT_GAP := 12.0
const GROUP_GAP := 28.0
const ROW_GAP := 18.0
static var band_h := float(BAND_H)
const PORTAL_GREEN := W.SAGE
const ELITE_ORANGE := W.EMBER
const BOSS_RED := W.ROCK

var game: Node
var _band: Control
var _rail: Control
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
var _slots_bottom := 220.0
var _ring_pos := Vector2.ZERO
var _ring_alpha := 0.0
var _stick := Vector2.ZERO
var _stick_r := 150.0
var _hp := 1.0
var _xp_batch := 0.0      # XP collected since the last popup
var _xp_batch_t := 0.0    # seconds until the batch is shown
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
	_banner.shown.connect(_on_banner)
	add_child(_banner)
	Run.xp_changed.connect(func(xp, need): _set_xp(xp, need); _lv.text = "LV %d" % Run.level; _fit_top())
	Run.xp_gained.connect(_on_xp_gained)
	Run.gold_changed.connect(func(g): _gold.text = W.num(g); _fit_top())
	Run.build_changed.connect(_refresh_rows)
	if game and game.player:
		game.player.input.touch_started.connect(func(p): _ring_pos = p; _ring_alpha = 1.0)
		game.player.input.touch_ended.connect(func(): _ring_alpha = 0.0)
	_refresh_rows()
	_set_xp(Run.xp, Run.xp_to_next())
	_gold.text = W.num(Run.run_gold)
	_lv.text = "LV %d" % Run.level
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
	# the XP rail: 18 px of ink along the top edge, the fill 12 px inset 3 from its top
	_rail = Control.new()
	_rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_rail.offset_top = W.safe_top()
	_rail.offset_bottom = W.safe_top() + RAIL_H
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.draw.connect(func():
		_rail.draw_rect(Rect2(0, 0, _rail.size.x, RAIL_H), W.INK)
		if _xp_frac > 0.0:
			_rail.draw_rect(Rect2(0, 3, _rail.size.x * _xp_frac, RAIL_H - 6.0), W.EPIC))
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


func _build_boss() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_boss_box.add_theme_constant_override("separation", 10)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ink := W.box(W.INK, 0, 0).pad(28, 6, 28, 6)
	plate.add_theme_stylebox_override("panel", ink)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_icon = TextureRect.new()
	_boss_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_boss_icon.custom_minimum_size = Vector2(40, 40)
	_boss_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_boss_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_boss_icon)
	_boss_name = W.text("", W.slab(W.em(26, 0.06)), 26, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	_boss_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_boss_name)
	plate.add_child(row)
	_boss_box.add_child(plate)
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


func _refresh_rows() -> void:
	var t0 := Time.get_ticks_usec()
	for c in _slots.get_children():
		c.queue_free()
	_slot_nodes.clear()
	var items: Array = []   # [def, level, is_weapon, rivets]
	for w in Run.weapons:
		var inst: WeaponInstance = w
		items.append([inst.def, inst.level, true, inst.mutations.size()])
	for pid in Run.passives.keys():
		var pd: PassiveDef = Registry.passive(pid)
		if pd:
			items.append([pd, int(Run.passives[pid]), false, 0])
	for lid in Run.lines.keys():
		var ld = Registry.line(lid)
		if ld:
			items.append([ld, int(Run.lines[lid]), false, 0])
	# weapons WEAPON_PX, passives and lines OTHER_PX, SLOT_GAP apart, GROUP_GAP more between the two groups: all on one
	# row while it fits at 85 % or more; past that the weapons keep a row of their own and the passives and lines take a
	# second one under it, each row shrinking only as far as it must (plates never squeeze into each other's level tags)
	var avail := get_viewport_rect().size.x - 72.0
	var weapons := items.filter(func(it): return bool(it[2]))
	var others := items.filter(func(it): return not bool(it[2]))
	var rows: Array = [items]
	if _row_width(items) * 0.85 > avail:
		rows = [weapons, others]
	var y := 0.0
	for row in rows:
		if (row as Array).is_empty():
			continue
		var k := minf(avail / maxf(_row_width(row), 1.0), 1.0)
		var x := 0.0
		var was_weapon := true
		var row_h := 0.0
		for it in row:
			var is_w: bool = it[2]
			var side := (WEAPON_PX if is_w else OTHER_PX) * k
			if not is_w and was_weapon and x > 0.0:
				x += GROUP_GAP * k
			was_weapon = is_w
			var p := WPlate.new().for_def(it[0], side)
			p.border = 4
			p.radius = 10
			p.icon_frac = 0.66 if is_w else 0.62
			p.level_text = str(it[1])
			p.level_size = int(round((19 if is_w else 17) * maxf(k, 0.8)))
			p.rivets = int(it[3])
			p.rivet_size = 15.0 * k
			# a passive beside the weapons sits a little low (the mock's row); on its own row it starts at the top
			p.position = Vector2(x, y + (6.0 * k if not is_w and rows.size() == 1 else 0.0))
			_slots.add_child(p)
			_slot_nodes[(it[0] as ContentDef).id] = p
			x += side + SLOT_GAP * k
			row_h = maxf(row_h, side + (6.0 * k if not is_w and rows.size() == 1 else 0.0))
		y += row_h + ROW_GAP
	var inset := W.safe_top()
	_rail.offset_top = inset
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


## One row's width at full size: weapons WEAPON_PX, the rest OTHER_PX, SLOT_GAP apart, GROUP_GAP more where the
## weapons end.
func _row_width(row: Array) -> float:
	var nw := 0
	var np := 0
	for it in row:
		if bool(it[2]):
			nw += 1
		else:
			np += 1
	return nw * WEAPON_PX + np * OTHER_PX + maxf(nw + np - 1, 0) * SLOT_GAP + (GROUP_GAP if nw > 0 and np > 0 else 0.0)


## Where an item's slot is on screen (the gate's flying card lands there); an empty rect when it has none.
func slot_rect(id: String) -> Rect2:
	var p: WPlate = _slot_nodes.get(id)
	return p.get_global_rect() if p else Rect2()


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


## News that takes the top row for 2 s. An evolution is ember with the weapon's icon; the rest are ink.
func banner(text: String, color: Color = W.INK, icon: Texture2D = null) -> void:
	var t := text.replace(": ", " · ")
	var ember := t.begins_with("EVOLVED") or (icon != null)
	_banner.play(t, ember, icon, TOP_Y + W.safe_top())


func _on_banner(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_top, "modulate:a", 0.0 if on else 1.0, 0.15)


## Gems collected within a quarter second are shown as one "+N XP" rising from the hero.
func _on_xp_gained(amount: float) -> void:
	_xp_batch += amount
	if _xp_batch_t <= 0.0:
		_xp_batch_t = 0.25


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
	var px := 32 if n < 50 else 40
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


## No stage name on the HUD any more (the pause screen says it); kept for the callers.
func refresh_stage() -> void:
	pass


func _refresh_buffs() -> void:
	var key := ""
	for tb in Run.timed:
		key += str(tb["id"]) + ","
	if key != _buffs_key:
		_buffs_key = key
		for c in _buffs.get_children():
			c.queue_free()
		for tb in Run.timed:
			var def: PickupDef = Registry.pickup(str(tb["id"]))
			if def == null:
				continue
			var p := WPlate.new().for_def(def, 72.0)
			p.fill = W.SAGE
			p.icon_frac = 0.66
			p.level_size = 20
			p.name = "buff"
			_buffs.add_child(p)
		_layout_toasts()
	if _adren:
		var parts: Array = []
		if Run.adrenaline > 0:
			parts.append("ADRENALINE ×%d" % Run.adrenaline)
		if Run.crescendo > 0:
			parts.append("CRESCENDO +%d%%" % int(round(Run.crescendo_might() * 100.0)))
		_adren.visible = not parts.is_empty()
		if not parts.is_empty():
			_adren.text = " · ".join(parts)
	var k := 0
	for tb in Run.timed:
		if k < _buffs.get_child_count():
			var p := _buffs.get_child(k) as WPlate
			if p:
				var s := "%d" % int(ceil(float(tb["until"]) - Run.elapsed))
				if p.level_text != s:
					p.level_text = s
					p.queue_redraw()
		k += 1


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
	_arrows.append({"pos": at, "dir": dir, "color": color, "side": side, "text": "%s %d m" % [name, int(round(d.length()))]})


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
