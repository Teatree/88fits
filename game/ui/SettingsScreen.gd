## Settings (Wanted 05): one screen, no debug. The camera as a two-way choice (Fixed / Follow), the joystick size, screen
## shake, sound and music as sliders, the damage numbers (a switch, pass 46), the first-play hints (a switch, and a reset
## for next run), and wiping the save, which a pop-up asks about first. The version line at the foot opens the developer
## menu when held for 2 s. Pass 52: while the player's debug mode is on, a Debug panel above the wipe holds the title's
## look (Painted or Live, Settings.menu_style); pass 54 adds a switch for the ranged weapons' aim (on screen only, or
## anywhere in reach: Settings.ranged_on_screen). Pass 57: "Anonymous play data" (Settings.analytics, the PostHog client
## in core/autoload/Analytics.gd), a switch with one line under it saying what goes, or that this build's key file is
## empty and nothing does.
extends ScreenBase

const HOLD := 2.0

var _version: WText
var _saved_line: WText   # "saved 3 min ago" over the version line (pass 45)
var _holding := false
var _hold_t := 0.0
var _hold_from := Vector2.ZERO
var _wipe: WButton
## Ten taps on the hints switch in one visit flip the player's debug mode (pass 44); it flips back only on a later
## visit, with ten more (a fresh screen each time, so the count and the flip start over).
const DEBUG_TAPS := 10
var _hint_taps := 0
var _debug_flipped := false


func board_top() -> float:
	return 200.0


func board_bottom() -> float:
	return 50.0 + 29.0 + 28.0 + 20.0


func build() -> void:
	set_title("Settings")
	var version := str(ProjectSettings.get_setting("application/config/version", "0.28"))
	_version = W.serif_text("88fits v" + version, 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	_version.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_version.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.offset_bottom = -50
	_version.offset_left = -200
	_version.offset_right = 200
	_version.offset_top = -50 - 29
	_version.mouse_filter = Control.MOUSE_FILTER_STOP
	_version.gui_input.connect(_on_version_input)
	add_child(_version)
	# the save's last write, so the player can see progress is kept (red when the disk refused)
	_saved_line = W.serif_text(_saved_text(), 22, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	_saved_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_saved_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_saved_line.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_saved_line.offset_bottom = -50 - 29 - 2
	_saved_line.offset_top = _saved_line.offset_bottom - 26
	_saved_line.offset_left = -300
	_saved_line.offset_right = 300
	_saved_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Save.last_error != "":
		_saved_line.color = W.ROCK
	add_child(_saved_line)
	Save.saved.connect(_on_saved)
	_refresh()


## "saved just now", "saved 3 min ago", "saved 2 h ago", "saved 2026-10-01 14:02:11", "saved ... · from the backup",
## or the error in red.
func _saved_text() -> String:
	if Save.last_error != "":
		return "save failed · " + Save.last_error
	if Save.last_saved_unix <= 0:
		return "nothing saved yet"
	var ago: int = int(Time.get_unix_time_from_system()) - int(Save.last_saved_unix)
	var when := "just now"
	if ago >= 86400:
		var local: int = int(Save.last_saved_unix) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		when = Time.get_datetime_string_from_unix_time(local, true)
	elif ago >= 3600:
		when = "%d h ago" % int(ago / 3600.0)
	elif ago >= 60:
		when = "%d min ago" % int(ago / 60.0)
	return "saved %s%s" % [when, " · from the backup" if Save.loaded_from == "backup" else ""]


func _on_saved(_ok: bool) -> void:
	if is_instance_valid(_saved_line):
		_saved_line.text = _saved_text()
		_saved_line.color = W.ROCK if Save.last_error != "" else W.INK_SOFT


func _refresh() -> void:
	clear_content()
	# the camera
	var cam := _panel(18)
	cam.get_child(0).add_child(W.label("Camera", 22, W.INK_SOFT, 0.15))
	var choice := WChoice.make([["Fixed", "north stays up"], ["Follow", "swings behind the hero"]], Settings.camera_mode, 36, 24, 20.0,
		HORIZONTAL_ALIGNMENT_CENTER, 0)
	choice.chosen.connect(func(i: int): Settings.set_value("camera_mode", i))
	cam.get_child(0).add_child(choice)
	content.add_child(cam)
	# the sliders
	var sl := _panel(40)
	var box: VBoxContainer = sl.get_child(0)
	box.add_child(_slider_row("Joystick size", Settings.stick_size, 0.6, 1.4, func(v): Settings.set_value("stick_size", v), 100.0))
	box.add_child(_slider_row("Screen shake", Settings.screen_shake, 0.0, 1.5, func(v): Settings.set_value("screen_shake", v), 100.0))
	box.add_child(_slider_row("Sound", Settings.sfx_volume, 0.0, 1.0, func(v): Settings.set_value("sfx_volume", v), 0.0, 5))
	box.add_child(_slider_row("Music", Settings.music_volume, 0.0, 1.0, func(v): Settings.set_value("music_volume", v), 0.0, 5))
	content.add_child(sl)
	# the floating text (pass 46 damage, pass 47b a switch per kind and three sizes)
	var ft := _panel(24)
	for spec in [["Damage numbers", "damage_numbers", "DamageNumbers"], ["Heal numbers", "float_heal", "HealNumbers"],
			["XP numbers", "float_xp", "XpNumbers"], ["Coin numbers", "float_coins", "CoinNumbers"]]:
		var r := _row(str(spec[0]))
		var key: String = spec[1]
		var s := WSwitch.make(bool(Settings.get(key)))
		s.name = str(spec[2])
		s.toggled.connect(func(on: bool): Settings.set_value(key, on))
		r.add_child(s)
		ft.get_child(0).add_child(r)
	var size_choice := WChoice.make([["Small"], ["Normal"], ["Large"]], Settings.float_size, 30, 20, 14.0,
		HORIZONTAL_ALIGNMENT_CENTER, 0)
	size_choice.name = "FloatSize"
	size_choice.chosen.connect(func(i: int): Settings.set_value("float_size", i))
	ft.get_child(0).add_child(W.label("Floating text size", 20, W.INK_SOFT))
	ft.get_child(0).add_child(size_choice)
	content.add_child(ft)
	# the hints
	var hp := _panel(24)
	var hints := _row("First-play hints")
	var sw := WSwitch.make(Settings.show_hints)
	sw.toggled.connect(func(on: bool):
		Settings.set_value("show_hints", on)
		_count_hint_tap())
	hints.add_child(sw)
	hp.get_child(0).add_child(hints)
	var again := _row("Show the hints again next run")
	var reset := WButton.make(["Reset"], 26, WButton.SECONDARY, 4, 5, 10.0, 24.0)
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func():
		Save.reset_hints()
		reset.set_parts(["Done"])
		var tw := reset.create_tween()
		tw.tween_interval(1.2)
		tw.tween_callback(func(): reset.set_parts(["Reset"])))
	again.add_child(reset)
	hp.get_child(0).add_child(again)
	content.add_child(hp)
	# anonymous play data (pass 57): the switch, and one line under it (what goes, or that the key file is empty); off
	# deletes what waits to be sent
	var ap := _panel(10)
	ap.name = "AnalyticsPanel"
	var arow := _row("Anonymous play data")
	var asw := WSwitch.make(Settings.analytics)
	asw.name = "AnalyticsSwitch"
	asw.toggled.connect(func(on: bool): Settings.set_value("analytics", on))
	arow.add_child(asw)
	ap.get_child(0).add_child(arow)
	var aline := W.serif_text(Analytics.settings_line(), 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	aline.name = "AnalyticsLine"
	aline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap.get_child(0).add_child(aline)
	content.add_child(ap)
	# the player's debug options (pass 52): only while the debug mode is on
	if Settings.debug_mode:
		content.add_child(_debug_panel())
	# wiping the save: a pop-up asks first (pass 45)
	var wp := ScreenBase.board(Vector2(30, 30), 8, 5)
	var wr := HBoxContainer.new()
	wr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wp.add_child(wr)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(W.serif_text("Wipe the save", 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	tv.add_child(W.serif_text("gold, unlocks, everything · asks twice", 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	wr.add_child(tv)
	_wipe = WButton.make(["Wipe"], 26, WButton.DANGER, 4, 5, 10.0, 24.0)
	_wipe.name = "Wipe"
	_wipe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wipe.pressed.connect(_ask_wipe)
	wr.add_child(_wipe)
	content.add_child(wp)


## The debug options panel (pass 52, Garry: "a button in the Settings that's only available if the Debug mode is on ...
## switching between those 2 Main Menu versions"): the title's look, Painted (the hero's portrait over the desert's
## still) or Live (the level itself, the hero standing in it with his weapon circling him), next time the title shows.
func _debug_panel() -> PanelContainer:
	var p := _panel(18)
	p.name = "DebugPanel"
	p.set_meta("debug_panel", true)
	var col: VBoxContainer = p.get_child(0)
	col.add_child(W.label("Debug", 22, W.INK_SOFT, 0.15))
	col.add_child(W.serif_text("Main menu", 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var style := WChoice.make([["Painted", "the hero's portrait"], ["Live", "the level, the hero in it"]],
		1 if Settings.menu_style == "live" else 0, 30, 20, 14.0, HORIZONTAL_ALIGNMENT_CENTER, 0)
	style.name = "MenuStyle"
	style.chosen.connect(func(i: int): Settings.set_value("menu_style", "live" if i == 1 else "painted"))
	col.add_child(style)
	# the ranged weapons' aim (pass 54, Garry: they shoot only at what is on the screen; a switch to compare, debug only)
	if "ranged_on_screen" in Settings:
		var r := _row("Ranged weapons aim only on screen")
		var sw := WSwitch.make(bool(Settings.get("ranged_on_screen")))
		sw.name = "RangedOnScreen"
		sw.toggled.connect(func(on: bool): Settings.set_value("ranged_on_screen", on))
		r.add_child(sw)
		col.add_child(r)
	return p


## The debug panel follows the debug mode at once when ten taps flip it (just above the wipe, where _refresh puts it).
## Found by its mark, not its name: after a wipe _refresh rebuilds the board while the old panels wait to be freed, and
## the new one is renamed.
func _sync_debug_panel() -> void:
	var old: Node = null
	for c in content.get_children():
		if c.has_meta("debug_panel") and not c.is_queued_for_deletion():
			old = c
	if Settings.debug_mode and old == null:
		var p := _debug_panel()
		content.add_child(p)
		var wipe_panel := _wipe.get_parent().get_parent() if _wipe else null
		if wipe_panel and wipe_panel.get_parent() == content:
			content.move_child(p, wipe_panel.get_index())
	elif not Settings.debug_mode and old:
		content.remove_child(old)
		old.queue_free()


## A menu panel (paper, 5 px ink, an 8 px shadow, 30 px in) holding a column `gap` apart.
func _panel(gap: int) -> PanelContainer:
	var p := ScreenBase.board(Vector2(30, 30), 8, 5)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(v)
	return p


## A line of the panel: its words in Bitter 30 on the left, the control on the right.
func _row(t: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := W.serif_text(t, 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


## A setting as a slider row: the name (260 px), then the slider with its number on the thumb (`mult` x the value, or
## the fill as 0-100).
func _slider_row(t: String, value: float, lo: float, hi: float, on_change: Callable, mult: float = 0.0, levels: int = 0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := W.serif_text(t, 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.custom_minimum_size.x = 260
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := WSlider.make_levels(value, levels, lo, hi) if levels > 1 else WSlider.make(value, lo, hi)
	if mult > 0.0:
		s.shown = func(v: float) -> float: return v * mult
	s.value_changed.connect(func(x): on_change.call(x))
	h.add_child(s)
	return h


func _count_hint_tap() -> void:
	_hint_taps += 1
	if _hint_taps < DEBUG_TAPS or _debug_flipped:
		return
	_debug_flipped = true
	Settings.set_value("debug_mode", not Settings.debug_mode)
	Audio.play("ui_unlock" if Settings.debug_mode else "ui_locked")
	_sync_debug_panel()
	# the version line says so for a moment
	var version := str(ProjectSettings.get_setting("application/config/version", "0.28"))
	_version.text = "debug options %s" % ("ON · arena on the title, any item on level-up, hold, respawn and the last hits on Down!" if Settings.debug_mode else "OFF")
	_version.color = W.BRASS_DARK
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func():
		if is_instance_valid(_version):
			_version.text = "88fits v" + version
			_version.color = W.INK_SOFT)


## The question before the save goes (pass 45): a pop-up over the screen; the wipe itself runs only from its rock button.
func _ask_wipe() -> void:
	WConfirm.open(self, "Wipe the save?", "Gold, unlocks, talents, quests and records: everything goes, and nothing brings it back.",
		"Wipe", "Keep it", _wipe_now)


func _wipe_now() -> void:
	Save.wipe()
	Audio.play("ui_locked")
	if is_instance_valid(_saved_line):
		_saved_line.text = _saved_text()
	_refresh()


## Holding the version line for 2 s opens the developer menu; lifting or sliding the finger away cancels it.
func _on_version_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		var down: bool = e.pressed
		_holding = down
		_hold_t = 0.0
		_hold_from = e.position
		_version.color = W.INK_SOFT
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _holding:
		if e.position.distance_to(_hold_from) > 40.0:
			_holding = false
			_version.color = W.INK_SOFT


func _process(delta: float) -> void:
	super._process(delta)
	if not _holding:
		return
	_hold_t += delta
	# halfway there the line turns brass, so a held finger knows something is coming
	_version.color = W.BRASS_DARK if _hold_t > HOLD * 0.5 else W.INK_SOFT
	if _hold_t >= HOLD:
		_holding = false
		Audio.play("ui_tap")
		go("res://ui/DevMenu.tscn")
