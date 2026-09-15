## In-run HUD laid out like Survivor.io: a thin strip over the world (level + XP bar + stage, kills + big timer +
## gold, twelve item slots) that takes the top 13% of the screen, a round pause button, the boss countdown just
## under the strip, the HP bar under the player, the boss bar, the floating joystick, toasts and banners.
## Tapping the strip also pauses.
class_name HUD
extends Control

signal pause_requested

## Height of the strip in design px (1080 x 1920). PlayerInput's thumb zone starts just below it.
const BAND_H := 250
const SLOT := 72

var game: Node
var _xp_bar: ProgressBar
var _lv: Label
var _timer: Label
var _stage: Label
var _kills: Label
var _gold: Label
var _weapon_row: HBoxContainer
var _passive_row: HBoxContainer
var _hp_bg: ColorRect
var _hp_fg: ColorRect
var _boss_box: Control
var _boss_name: Label
var _boss_bar: ProgressBar
var _toasts: VBoxContainer
var _banner: Label
var _pause_btn: Button
var _boss_in: Label
var _boss_warned := false
var _ring_pos := Vector2.ZERO
var _ring_alpha := 0.0
var _stick := Vector2.ZERO
var _stick_r := 150.0
var _hp := 1.0
var _band: Control
var _buffs: HBoxContainer
var _buffs_key := ""
var _xp_batch := 0.0      # XP collected since the last popup
var _xp_batch_t := 0.0    # seconds until the batch is shown


func _ready() -> void:
	UiKit.fullscreen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_band()
	_build_player_hp()
	_build_boss()
	_build_toasts()
	Run.xp_changed.connect(func(xp, need): _xp_bar.max_value = need; _xp_bar.value = xp; _lv.text = "LV %d" % Run.level)
	Run.xp_gained.connect(_on_xp_gained)
	Run.gold_changed.connect(func(g): _gold.text = str(g))
	Run.kills_changed.connect(func(_k): _refresh_counts())
	Run.build_changed.connect(_refresh_rows)
	Run.stage_changed.connect(func(_s): refresh_stage())
	if game and game.player:
		game.player.input.touch_started.connect(func(p): _ring_pos = p; _ring_alpha = 1.0)
		game.player.input.touch_ended.connect(func(): _ring_alpha = 0.0)
	_refresh_rows()
	_refresh_counts()
	_xp_bar.max_value = Run.xp_to_next()
	_xp_bar.value = Run.xp


func _build_band() -> void:
	_band = Control.new()
	_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_band.offset_bottom = BAND_H
	_band.mouse_filter = Control.MOUSE_FILTER_STOP
	_band.gui_input.connect(func(ev):
		if ev is InputEventScreenTouch and ev.pressed:
			pause_requested.emit()
		elif ev is InputEventMouseButton and ev.pressed:
			pause_requested.emit())
	add_child(_band)
	# a soft gradient instead of a solid panel: the world shows through and the strip reads as thin
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.04, 0.09, 0.8))
	grad.set_color(1, Color(0.03, 0.04, 0.09, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 8
	gt.height = 64
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.offset_bottom = 60
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(shade)
	var v := UiKit.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 36
	v.offset_right = -36
	v.offset_top = 40
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(v)
	# row 1: level · XP bar · stage
	var top := UiKit.hbox(14)
	_lv = UiKit.outline(UiKit.label("LV 1", 36, UiKit.INK), 5)
	_lv.autowrap_mode = TextServer.AUTOWRAP_OFF
	_lv.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_lv.custom_minimum_size = Vector2(104, 0)
	top.add_child(_lv)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 20)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_theme_stylebox_override("background", UiKit.bar(Color(0, 0, 0, 0.5), 10, Color(1, 1, 1, 0.2), 2))
	_xp_bar.add_theme_stylebox_override("fill", UiKit.bar(UiKit.XP, 10, Color(1, 1, 1, 0.22), 2))
	top.add_child(_xp_bar)
	_stage = UiKit.outline(UiKit.label("STAGE 1", 22, UiKit.INK2, HORIZONTAL_ALIGNMENT_RIGHT), 4)
	_stage.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stage.size_flags_horizontal = Control.SIZE_SHRINK_END
	_stage.custom_minimum_size = Vector2(300, 0)
	top.add_child(_stage)
	v.add_child(top)
	# row 2: kills · timer · gold (the pause button floats at the right end)
	var mid := UiKit.hbox(10)
	_kills = UiKit.outline(UiKit.label("0 kills · 0 alive", 24, UiKit.INK2), 4)
	_kills.autowrap_mode = TextServer.AUTOWRAP_OFF
	_kills.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_kills.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kills.custom_minimum_size = Vector2(300, 0)
	mid.add_child(_kills)
	_timer = UiKit.outline(UiKit.label("00:00", 54, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER), 7)
	_timer.autowrap_mode = TextServer.AUTOWRAP_OFF
	mid.add_child(_timer)
	var right := UiKit.hbox(8)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.custom_minimum_size = Vector2(300, 0)
	_gold = UiKit.outline(UiKit.label("0", 30, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT), 5)
	_gold.autowrap_mode = TextServer.AUTOWRAP_OFF
	_gold.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(_gold)
	var coin := Panel.new()
	coin.custom_minimum_size = Vector2(28, 28)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.add_theme_stylebox_override("panel", UiKit.bar(UiKit.ACCENT, 14, UiKit.ACCENT_INK, 3))
	right.add_child(coin)
	var room := UiKit.spacer(0)
	room.custom_minimum_size = Vector2(90, 0)   # the pause button sits here
	right.add_child(room)
	mid.add_child(right)
	v.add_child(mid)
	# row 3: six weapon slots on the left, six passive slots on the right (square vs round plates tell them apart)
	var rows := UiKit.hbox(0)
	_weapon_row = UiKit.hbox(8)
	_weapon_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_passive_row = UiKit.hbox(8)
	_passive_row.alignment = BoxContainer.ALIGNMENT_END
	rows.add_child(_weapon_row)
	rows.add_child(_passive_row)
	v.add_child(rows)
	# the round pause button, where Survivor.io has it
	_pause_btn = UiKit.button("", 26, true, 76)
	_pause_btn.custom_minimum_size = Vector2(76, 76)
	_pause_btn.add_theme_stylebox_override("normal", UiKit.stylebox(UiKit.ACCENT, 38, Color(0, 0, 0, 0), 0, true, true, false))
	_pause_btn.add_theme_stylebox_override("hover", UiKit.stylebox(UiKit.ACCENT.lightened(0.06), 38, Color(0, 0, 0, 0), 0, true, true, false))
	_pause_btn.add_theme_stylebox_override("pressed", UiKit.stylebox(UiKit.ACCENT.darkened(0.12), 38, Color(0, 0, 0, 0), 0, false, false, false))
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left = -112
	_pause_btn.offset_right = -36
	_pause_btn.offset_top = 92
	_pause_btn.offset_bottom = 168
	_pause_btn.pressed.connect(func(): pause_requested.emit())
	_band.add_child(_pause_btn)
	# two bars as panels, so the glyph never depends on a font
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 10)
	bars.set_anchors_preset(Control.PRESET_CENTER)
	bars.offset_left = -15
	bars.offset_right = 15
	bars.offset_top = -17
	bars.offset_bottom = 13
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(2):
		var bar := Panel.new()
		bar.custom_minimum_size = Vector2(10, 30)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("panel", UiKit.bar(UiKit.ACCENT_INK, 4))
		bars.add_child(bar)
	_pause_btn.add_child(bars)
	# boss countdown floats just under the strip
	_boss_in = UiKit.outline(UiKit.label("", 30, UiKit.DANGER, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_boss_in.autowrap_mode = TextServer.AUTOWRAP_OFF
	_boss_in.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_in.offset_top = BAND_H + 2
	_boss_in.offset_bottom = BAND_H + 46
	_boss_in.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_in.visible = false
	add_child(_boss_in)
	# timed buffs from pickups, each an icon with its seconds left, under the strip on the left
	_buffs = UiKit.hbox(10)
	_buffs.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_buffs.offset_left = 36
	_buffs.offset_top = BAND_H + 4
	_buffs.offset_right = 500
	_buffs.offset_bottom = BAND_H + 64
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_buffs)


func _slot(def: ContentDef, level: int, max_level: int, kind: String) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(SLOT, SLOT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if def:
		root.add_child(UiKit.icon_view(def, SLOT, kind))
		# level badge over the corner, gold once maxed
		var maxed := level >= max_level
		var badge := Panel.new()
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -30
		badge.offset_right = 6
		badge.offset_top = -30
		badge.offset_bottom = 6
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", UiKit.bar(UiKit.BG, 17, UiKit.ACCENT if maxed else UiKit.LINE, 2))
		var num := UiKit.outline(UiKit.label(str(level), 20, UiKit.ACCENT if maxed else UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER), 3)
		num.autowrap_mode = TextServer.AUTOWRAP_OFF
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.set_anchors_preset(Control.PRESET_FULL_RECT)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(num)
		root.add_child(badge)
	elif kind == "weapon":
		var empty := Panel.new()
		empty.set_anchors_preset(Control.PRESET_FULL_RECT)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.add_theme_stylebox_override("panel", UiKit.bar(Color(0, 0, 0, 0.35), 14, Color(1, 1, 1, 0.22), 2))
		root.add_child(empty)
	else:
		# a translucent circle as a texture: a StyleBoxFlat circle double-blends down its middle
		var disc := TextureRect.new()
		disc.texture = UiKit.circle_texture(SLOT, Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.22), 0.07)
		disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		disc.set_anchors_preset(Control.PRESET_FULL_RECT)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(disc)
	return root


func _refresh_rows() -> void:
	for c in _weapon_row.get_children():
		c.queue_free()
	for c in _passive_row.get_children():
		c.queue_free()
	for i in range(Run.MAX_WEAPONS):
		if i < Run.weapons.size():
			var w: WeaponInstance = Run.weapons[i]
			_weapon_row.add_child(_slot(w.def, w.level, w.def.max_level, "weapon"))
		else:
			_weapon_row.add_child(_slot(null, 0, 8, "weapon"))
	var pids := Run.passives.keys()
	for i in range(Run.MAX_PASSIVES):
		if i < pids.size():
			var def: PassiveDef = Registry.passive(pids[i])
			_passive_row.add_child(_slot(def, int(Run.passives[pids[i]]), def.max_level if def else 8, "passive"))
		else:
			_passive_row.add_child(_slot(null, 0, 8, "passive"))


func _refresh_counts() -> void:
	_kills.text = "%d kills · %d alive" % [Run.kills, Run.alive]


func refresh_stage() -> void:
	var name := Run.map.display_name.to_upper() if Run.map else ""
	_stage.text = ("ENDLESS · " if Run.endless else "STAGE %d · " % (Run.stage + 1)) + name


func _build_player_hp() -> void:
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.5)
	_hp_bg.size = Vector2(150, 14)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bg)
	_hp_fg = ColorRect.new()
	_hp_fg.color = UiKit.GOOD
	_hp_fg.size = Vector2(150, 14)
	_hp_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_fg)


## The run ends the frame the hero falls, so tick() stops: hide the bar and the stick ring explicitly.
func hide_player_bar() -> void:
	_hp_bg.visible = false
	_hp_fg.visible = false
	_ring_alpha = 0.0
	queue_redraw()


func set_hp(hp: float, max_hp: float) -> void:
	_hp = clamp(hp / max(max_hp, 1.0), 0.0, 1.0)
	_hp_fg.color = UiKit.GOOD if _hp > 0.35 else UiKit.DANGER


func _build_boss() -> void:
	_boss_box = UiKit.vbox(6)
	_boss_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_box.offset_top = BAND_H + 50
	_boss_box.offset_left = 60
	_boss_box.offset_right = -60
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_name = UiKit.outline(UiKit.label("", 30, UiKit.DANGER, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(0, 26)
	_boss_bar.show_percentage = false
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_theme_stylebox_override("background", UiKit.bar(Color(0, 0, 0, 0.5), 13, Color(1, 1, 1, 0.2), 2))
	_boss_bar.add_theme_stylebox_override("fill", UiKit.bar(UiKit.DANGER, 13, Color(1, 1, 1, 0.22), 2))
	_boss_box.add_child(_boss_name)
	_boss_box.add_child(_boss_bar)
	_boss_box.visible = false
	add_child(_boss_box)


func show_boss(def: EnemyDef) -> void:
	_boss_name.text = def.display_name.to_upper()
	_boss_box.visible = true
	UiFx.pop(_boss_box, 0.0, 0.9, 0.3)


func set_boss_hp(hp: float, max_hp: float) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = hp


func hide_boss() -> void:
	_boss_box.visible = false


func _build_toasts() -> void:
	_toasts = UiKit.vbox(8)
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 560
	_toasts.offset_left = -400
	_toasts.offset_right = 400
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toasts)
	_banner = UiKit.outline(UiKit.label("", 84, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 8)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -520
	_banner.offset_right = 520
	_banner.offset_top = -420
	_banner.offset_bottom = -300
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)


func toast(text: String, color: Color = UiKit.INK) -> void:
	var l := UiKit.outline(UiKit.label(text, 34, color, HORIZONTAL_ALIGNMENT_CENTER), 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(l)
	UiFx.pop(l, 0.0, 0.9, 0.22)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
	while _toasts.get_child_count() > 4:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()


func banner(text: String, color: Color = UiKit.ACCENT) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(0.7, 0.7)
	_banner.pivot_offset = _banner.size * 0.5
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)


## Gems collected within a quarter second are shown as one "+N XP" rising from the hero, and the bar pops.
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
	var vp := get_viewport().get_visible_rect().size
	var s := vp.x / 1080.0
	var l := UiKit.outline(UiKit.label("+%d XP" % n, 34 if n < 50 else 42, UiKit.XP.lightened(0.25), HORIZONTAL_ALIGNMENT_CENTER), 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size = Vector2(300 * s, 60 * s)
	l.position = sp - Vector2(150 * s, 30 * s)
	l.scale = Vector2(s, s) * 0.6
	l.pivot_offset = l.size * 0.5
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2(s, s), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 110 * s, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)
	# the bar itself pops
	_xp_bar.pivot_offset = Vector2(0, _xp_bar.size.y * 0.5)
	var tb := create_tween()
	tb.tween_property(_xp_bar, "scale", Vector2(1.0, 1.45), 0.08)
	tb.tween_property(_xp_bar, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func flash_level(level: int) -> void:
	_lv.text = "LV %d" % level
	UiFx.punch(_lv, 1.3, 0.3)


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
			var cell := UiKit.hbox(4)
			cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if def:
				cell.add_child(UiKit.icon_view(def, 48, "pickup"))
			var l := UiKit.outline(UiKit.label("", 24, UiKit.INK), 4)
			l.name = "secs"
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.custom_minimum_size = Vector2(44, 0)
			l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(l)
			_buffs.add_child(cell)
	var k := 0
	for tb in Run.timed:
		if k < _buffs.get_child_count():
			var l: Label = _buffs.get_child(k).get_node_or_null("secs")
			if l:
				l.text = "%ds" % int(ceil(float(tb["until"]) - Run.elapsed))
		k += 1


func tick(_delta: float) -> void:
	_timer.text = TextGen.time_mmss(Run.elapsed)
	_refresh_buffs()
	# boss countdown: visible in the last 45 s, a banner at 30 s, pulsing red in the last 10
	var boss_t: float = game.director.next_boss_in() if game and game.get("director") and game.director and game.director.has_method("next_boss_in") else -1.0
	if boss_t > 0.0 and boss_t <= 45.0:
		_boss_in.visible = true
		_boss_in.text = "BOSS IN %s" % TextGen.time_mmss(boss_t)
		if boss_t <= 10.0:
			_boss_in.pivot_offset = _boss_in.size * 0.5
			_boss_in.scale = Vector2.ONE * (1.0 + 0.12 * absf(sin(Run.elapsed * 8.0)))
		else:
			_boss_in.scale = Vector2.ONE
		if boss_t <= 30.0 and not _boss_warned:
			_boss_warned = true
			banner("BOSS INCOMING", UiKit.DANGER)
			Audio.play("en_boss_roar")
	else:
		_boss_in.visible = false
		if boss_t > 45.0 or boss_t < 0.0:
			_boss_warned = false
	# hp bar under the player (gone once he is down)
	if game and game.player and game.camera and not game.player.dead:
		var cam: Camera3D = game.camera.camera
		var wp: Vector3 = game.player.global_position + Vector3(0, -0.1, 0)
		if not cam.is_position_behind(wp):
			var sp := cam.unproject_position(wp)
			var vp := get_viewport().get_visible_rect().size
			var scale := vp.x / 1080.0
			var w := 150.0 * scale
			_hp_bg.size = Vector2(w, 14 * scale)
			_hp_bg.position = sp - Vector2(w * 0.5, -10 * scale)
			_hp_fg.size = Vector2(w * _hp, 14 * scale)
			_hp_fg.position = _hp_bg.position
			_hp_bg.visible = true
			_hp_fg.visible = true
		else:
			_hp_bg.visible = false
			_hp_fg.visible = false
	else:
		_hp_bg.visible = false
		_hp_fg.visible = false
	_tick_xp_popup(_delta)
	# the joystick ring follows the thumb; keyboard play (PC) draws none
	if game and game.player and game.player.input and game.player.input.wants_move and not game.player.input.keyboard:
		_ring_pos = game.player.input.origin
		_stick = game.player.input.stick_dir
		_stick_r = game.player.input.radius_px()
		_ring_alpha = 1.0
	elif _ring_alpha > 0.0:
		_ring_alpha = maxf(_ring_alpha - _delta * 3.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if _ring_alpha <= 0.0:
		return
	var vp := get_viewport().get_visible_rect().size
	var s := vp.x / 1080.0
	var base := Color(1, 1, 1, 0.22 * _ring_alpha)
	draw_circle(_ring_pos, _stick_r, Color(0, 0, 0, 0.10 * _ring_alpha))
	draw_arc(_ring_pos, _stick_r, 0.0, TAU, 48, base, 3.0 * s)
	var knob := _ring_pos + _stick * _stick_r
	draw_circle(knob, 46 * s, Color(1, 1, 1, 0.42 * _ring_alpha))
	draw_circle(knob, 46 * s, Color(0.16, 0.10, 0.0, 0.5 * _ring_alpha), false, 3.0 * s)
