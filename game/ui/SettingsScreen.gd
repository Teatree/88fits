## Settings (Wanted 05): one screen, no debug. The camera as a two-way choice (Fixed / Follow), the joystick size, screen
## shake, sound and music as sliders, the damage numbers (a switch, pass 46), the first-play hints (a switch, and a reset
## for next run), and wiping the save, which a pop-up asks about first. The version line at the foot opens the developer
## menu when held for 2 s. Pass 52: while the player's debug mode is on, a Debug panel above the wipe holds the title's
## look (Painted or Live, Settings.menu_style); pass 54 adds a switch for the ranged weapons' aim (on screen only, or
## anywhere in reach: Settings.ranged_on_screen). Pass 57: "Anonymous play data" (Settings.analytics, the PostHog client
## in core/autoload/Analytics.gd), a switch with one line under it saying what goes, or that this build's key file is
## empty and nothing does.
## Pass 123 (lane STAGES_SETTINGS), under Royale (W.royale(); Wanted is built and drawn exactly as before): the mock
## 10_Settings (Garry: "Settings in slate panels as the mock; one shared confirm pop-up (safe answer slate, destructive
## red, buying green)"): today's groups, in today's order and words, as slate panels 990 wide 30 apart: the camera's
## two-way choice under its CAMERA label (gold the chosen, the sublines kept), the four sliders in 96 px rows, the
## floating-text switches in 74 px rows with a faint line under each and the FLOATING TEXT SIZE choice, the hints with
## RESET, the play data with its line under the switch's name and the questions after a run, the Debug panel in the
## player's debug mode (the UI theme row kept), the wipe with its red WIPE; every row's name white Rubik 500 26, the
## choices' words in capitals (Ultra 28, Garry's floor). The foot is one line, "saved 9 h ago · Outlaw Survivors v1.00 ·
## Lanky Tinker 24" in the secondary blue, the version part still held 2 s for the developer menu. The wipe asks through
## WConfirm (kind "danger": KEEP IT slate, WIPE red).
extends ScreenBase

## Pass 123 (lane STAGES_SETTINGS), the Royale layout (the mock 10_Settings in canvas px): the first panel's top, the
## panels' side margin (990 wide), the panel's padding (the camera's 20 over and under, the rest 10; 28 at the sides),
## the row heights, the type sizes, the choices' cells, the small buttons, the foot line's top.
const R_TOP := 180.0
const R_SIDE := 45.0
const R_PAD_X := 28
const R_PAD_Y := 10
const R_PAD_CAMERA := 20
const R_ROW_H := 74.0
const R_SLIDER_H := 96.0
const R_SLIDER_LABEL_W := 240.0
const R_LABEL_PX := 18
const R_ROW_PX := 26
const R_SUB_PX := 20
const R_CHOICE_PX := 28
const R_CHOICE_SUB_PX := 18
const R_CAMERA_PAD := 18.5
const R_SIZE_PAD := 16.5
const R_BUTTON := Vector2(168, 52)
const R_BUTTON_PX := 28
const R_DIVIDER := Color(1, 1, 1, 0.1)
const R_FOOT_PX := 20
## The foot line's top above the screen's foot (the mock's 1810 of 1920), and the board's end 20 px over it.
const R_FOOT_UP := 110.0

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
## Pass 123 (Royale): the foot's one line (the saved part, a " · ", the version part) and the dot between.
var _foot: HBoxContainer
var _foot_dot: WText


func board_top() -> float:
	return R_TOP if W.royale() else 200.0


func board_bottom() -> float:
	if W.royale():
		# the board ends 20 px over the foot line
		return R_FOOT_UP + 20.0
	return 50.0 + 29.0 + 28.0 + 20.0


func board_side() -> float:
	return R_SIDE if W.royale() else super.board_side()


func build() -> void:
	set_title("Settings")
	if W.royale():
		_build_foot_royale()
		Save.saved.connect(_on_saved)
		_refresh()
		return
	_version = W.serif_text(version_line(), 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	_version.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_version.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.offset_bottom = -50
	_version.offset_left = -460
	_version.offset_right = 460
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
		_saved_line.color = _bad_ink() if Save.last_error != "" else _soft_ink()


## The foot's colours in the theme (pass 123): the soft line (ink soft; Royale's secondary blue), the refused save
## (rock; Royale's red) and the held line's warning (brass dark; Royale's gold).
static func _soft_ink() -> Color:
	return R.SECONDARY if W.royale() else W.INK_SOFT


static func _bad_ink() -> Color:
	return R.ROLES["red"]["top"] if W.royale() else W.ROCK


static func _held_ink() -> Color:
	return R.GOLD_TEXT if W.royale() else W.BRASS_DARK


func _refresh() -> void:
	clear_content()
	if W.royale():
		_refresh_royale()
		return
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
	# the end-of-run questions (pass 59): off sends survey_opt_out, so Garry sees it in PostHog
	var srow := _row("Questions after a run")
	var ssw := WSwitch.make(Settings.surveys)
	ssw.name = "SurveySwitch"
	ssw.toggled.connect(func(on: bool): Analytics.set_surveys(on, "settings"))
	srow.add_child(ssw)
	ap.get_child(0).add_child(srow)
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
	# pass 123 (Royale): the mock's label, sub-heads and choices (capitals in Ultra 28, sublines Rubik 18)
	var royale := W.royale()
	col.add_child(W.label("Debug", R_LABEL_PX if royale else 22, W.INK_SOFT, -1.0 if royale else 0.15))
	# the title's look: Painted (the default since pass 119) or Live; never in the production build (pass 119, lane
	# LOADUI: it is always painted there; the panel itself only shows in debug mode, which prod locks off)
	if not Settings.is_prod():
		col.add_child(_sub_head("Main menu"))
		var style := WChoice.make(_choice_words([["Painted", "the hero's portrait"], ["Live", "the level, the hero in it"]]),
			1 if Settings.menu_style == "live" else 0, R_CHOICE_PX if royale else 30, R_CHOICE_SUB_PX if royale else 20,
			R_CAMERA_PAD if royale else 14.0, HORIZONTAL_ALIGNMENT_CENTER, 4 if royale else 0)
		style.name = "MenuStyle"
		style.chosen.connect(func(i: int): Settings.set_value("menu_style", "live" if i == 1 else "painted"))
		col.add_child(style)
	# the UI theme (pass 122, lane UIKIT_A; Garry's build brief: Claude Design's "Royale, refined" as a second theme
	# behind a switch, Wanted the default): Wanted or Royale; the next screen built wears it, and this one is rebuilt
	# at once; never in the production build (PROD_LOCKED holds it at wanted)
	if not Settings.is_prod() and "ui_theme" in Settings:
		col.add_child(_sub_head("UI theme"))
		var theme := WChoice.make(_choice_words([["Wanted", "paper, ink and brass"], ["Royale", "slate, navy and gold"]]),
			1 if str(Settings.ui_theme) == "royale" else 0, R_CHOICE_PX if royale else 30, R_CHOICE_SUB_PX if royale else 20,
			R_CAMERA_PAD if royale else 14.0, HORIZONTAL_ALIGNMENT_CENTER, 4 if royale else 0)
		theme.name = "UiTheme"
		theme.chosen.connect(func(i: int):
			Settings.set_value("ui_theme", "royale" if i == 1 else "wanted")
			W.theme_changed()
			_rebuild_for_theme.call_deferred())
		col.add_child(theme)
	# the ranged weapons' aim (pass 54, Garry: they shoot only at what is on the screen; a switch to compare, debug only)
	if "ranged_on_screen" in Settings:
		var r := _row("Ranged weapons aim only on screen")
		var sw := WSwitch.make(bool(Settings.get("ranged_on_screen")))
		sw.name = "RangedOnScreen"
		sw.toggled.connect(func(on: bool): Settings.set_value("ranged_on_screen", on))
		r.add_child(sw)
		col.add_child(r)
	# the pierce drop-off (pass 62, Garry: "I am not super sure about this change so add an option to toggle this on and
	# off in the Debug version of the Settings"): off, piercing shots and the Spear's thrust hit as they did before
	if "pierce_falloff" in Settings:
		var r2 := _row("Pierce damage drop-off")
		var sw2 := WSwitch.make(bool(Settings.get("pierce_falloff")))
		sw2.name = "PierceFalloff"
		sw2.toggled.connect(func(on: bool): Settings.set_value("pierce_falloff", on))
		r2.add_child(sw2)
		col.add_child(r2)
	# the hero's knockback from hits (pass 88, Garry: "Remove the Knockback from being hit for Player entirely. Add this
	# option in the Debug version of the Settings menu"): off by default; on, every hit pushes him as before (pass 89: off,
	# only the special attacks push him, at the map's share)
	if "hero_knockback" in Settings:
		var r3 := _row("Full hero knockback")
		var sw3 := WSwitch.make(bool(Settings.get("hero_knockback")))
		sw3.name = "HeroKnockback"
		sw3.toggled.connect(func(on: bool): Settings.set_value("hero_knockback", on))
		r3.add_child(sw3)
		col.add_child(r3)
	# "Fire forward" (pass 95, lane ITEMS; Garry: "add this as a togglable option in the debug version of settings, by
	# default it's off"): on, the Sabre, Spear, Hammer, Frisbee, Tumbleweed and Basketball fire along the hero's facing
	# while no creature stands within 75% of their range (core/systems/FireForward.gd)
	if "fire_forward" in Settings:
		var r4 := _row("Fire forward")
		var sw4 := WSwitch.make(bool(Settings.get("fire_forward")))
		sw4.name = "FireForward"
		sw4.toggled.connect(func(on: bool): Settings.set_value("fire_forward", on))
		r4.add_child(sw4)
		col.add_child(r4)
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


## A menu panel (paper, 5 px ink, an 8 px shadow, 30 px in) holding a column `gap` apart. Pass 123: under Royale the
## mock's slate panel (_panel_royale; the Debug panel's rows sit 0 apart, each with its line under it).
func _panel(gap: int) -> PanelContainer:
	if W.royale():
		return _panel_royale(R_PAD_Y + 10, 12)
	var p := ScreenBase.board(Vector2(30, 30), 8, 5)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(v)
	return p


## A line of the panel: its words in Bitter 30 on the left, the control on the right. Pass 123: under Royale the mock's
## 74 px row (_row_royale).
func _row(t: String) -> HBoxContainer:
	if W.royale():
		return _row_royale(t)
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
	# pass 81 (lane PROD): the production build has no debug mode to flip
	if Settings.is_prod():
		return
	_hint_taps += 1
	if _hint_taps < DEBUG_TAPS or _debug_flipped:
		return
	_debug_flipped = true
	Settings.set_value("debug_mode", not Settings.debug_mode)
	Audio.play("ui_unlock" if Settings.debug_mode else "ui_locked")
	_sync_debug_panel()
	# the version line says so for a moment
	_version.text = "debug options %s" % ("ON · arena on the title, any item on level-up, hold, respawn and the last hits on Down!" if Settings.debug_mode else "OFF")
	_version.color = _held_ink()
	# pass 123 (Royale): the one foot line gives the message its whole width for the moment
	_foot_message(true)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func():
		if is_instance_valid(_version):
			_version.text = version_line()
			_version.color = _soft_ink()
			_foot_message(false))


# ---------------------------------------------------------------- Royale (pass 123, lane STAGES_SETTINGS)

## The Royale board (the mock 10_Settings): today's panels in today's order, the mock's slate and rows.
func _refresh_royale() -> void:
	# the camera: its label, then the two-way choice (90 px cells, the chosen gold, the sublines kept)
	var cam := _panel_royale(R_PAD_CAMERA, 14)
	cam.name = "CameraPanel"
	var cc: VBoxContainer = cam.get_child(0)
	cc.add_child(W.label("Camera", R_LABEL_PX))
	var choice := WChoice.make(_choice_words([["Fixed", "north stays up"], ["Follow", "swings behind the hero"]]),
		Settings.camera_mode, R_CHOICE_PX, R_CHOICE_SUB_PX, R_CAMERA_PAD, HORIZONTAL_ALIGNMENT_CENTER, 4)
	choice.name = "CameraChoice"
	choice.chosen.connect(func(i: int): Settings.set_value("camera_mode", i))
	cc.add_child(choice)
	content.add_child(cam)
	# the sliders, 96 px rows
	var sl := _panel_royale(R_PAD_Y, 0)
	sl.name = "SliderPanel"
	var box: VBoxContainer = sl.get_child(0)
	box.add_child(_slider_row_royale("Joystick size", Settings.stick_size, 0.6, 1.4, func(v): Settings.set_value("stick_size", v), 100.0))
	box.add_child(_slider_row_royale("Screen shake", Settings.screen_shake, 0.0, 1.5, func(v): Settings.set_value("screen_shake", v), 100.0))
	box.add_child(_slider_row_royale("Sound", Settings.sfx_volume, 0.0, 1.0, func(v): Settings.set_value("sfx_volume", v), 0.0, 5))
	box.add_child(_slider_row_royale("Music", Settings.music_volume, 0.0, 1.0, func(v): Settings.set_value("music_volume", v), 0.0, 5))
	content.add_child(sl)
	# the floating text: a switch per kind, then the size
	var ft := _panel_royale(R_PAD_Y, 0)
	ft.name = "FloatPanel"
	var fc: VBoxContainer = ft.get_child(0)
	for spec in [["Damage numbers", "damage_numbers", "DamageNumbers"], ["Heal numbers", "float_heal", "HealNumbers"],
			["XP numbers", "float_xp", "XpNumbers"], ["Coin numbers", "float_coins", "CoinNumbers"]]:
		var r := _row_royale(str(spec[0]))
		var key: String = spec[1]
		var s := _switch_royale(bool(Settings.get(key)))
		s.name = str(spec[2])
		s.toggled.connect(func(on: bool): Settings.set_value(key, on))
		r.add_child(s)
		fc.add_child(r)
	var lab := W.label("Floating text size", R_LABEL_PX)
	var lm := MarginContainer.new()
	lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lm.add_theme_constant_override("margin_top", 18)
	lm.add_theme_constant_override("margin_bottom", 10)
	lm.add_child(lab)
	fc.add_child(lm)
	var size_choice := WChoice.make(_choice_words([["Small"], ["Normal"], ["Large"]]), Settings.float_size, R_CHOICE_PX, R_CHOICE_SUB_PX,
		R_SIZE_PAD, HORIZONTAL_ALIGNMENT_CENTER, 0)
	size_choice.name = "FloatSize"
	size_choice.chosen.connect(func(i: int): Settings.set_value("float_size", i))
	fc.add_child(size_choice)
	fc.add_child(_spacer(R_PAD_Y + 8))
	content.add_child(ft)
	# the hints: the switch (ten taps flip the player's debug mode, as today) and RESET for next run
	var hp := _panel_royale(R_PAD_Y, 0)
	hp.name = "HintsPanel"
	var hints := _row_royale("First-play hints")
	var sw := _switch_royale(Settings.show_hints)
	sw.name = "HintsSwitch"
	sw.toggled.connect(func(on: bool):
		Settings.set_value("show_hints", on)
		_count_hint_tap())
	hints.add_child(sw)
	hp.get_child(0).add_child(hints)
	var again := _row_royale("Show the hints again next run")
	var reset := _small_button("Reset", WButton.SECONDARY, WButton.SLATE)
	reset.name = "ResetHints"
	reset.pressed.connect(func():
		Save.reset_hints()
		reset.set_parts(["DONE"])
		var tw := reset.create_tween()
		tw.tween_interval(1.2)
		tw.tween_callback(func(): reset.set_parts(["RESET"])))
	again.add_child(reset)
	hp.get_child(0).add_child(again)
	content.add_child(hp)
	# anonymous play data (pass 57): the switch with its line under the name; the end-of-run questions (pass 59)
	var ap := _panel_royale(R_PAD_Y, 0)
	ap.name = "AnalyticsPanel"
	var arow := _row_royale("Anonymous play data", Analytics.settings_line())
	var aline: WText = arow.find_child("Sub", true, false)
	if aline:
		aline.name = "AnalyticsLine"
	var asw := _switch_royale(Settings.analytics)
	asw.name = "AnalyticsSwitch"
	asw.toggled.connect(func(on: bool): Settings.set_value("analytics", on))
	arow.add_child(asw)
	ap.get_child(0).add_child(arow)
	var srow := _row_royale("Questions after a run")
	var ssw := _switch_royale(Settings.surveys)
	ssw.name = "SurveySwitch"
	ssw.toggled.connect(func(on: bool): Analytics.set_surveys(on, "settings"))
	srow.add_child(ssw)
	ap.get_child(0).add_child(srow)
	content.add_child(ap)
	# the player's debug options (pass 52): only while the debug mode is on
	if Settings.debug_mode:
		content.add_child(_debug_panel())
	# wiping the save (pass 45): its row straight in the panel (the debug panel finds it there), a red WIPE that asks
	var wp := _panel_royale(R_PAD_Y, 0, false)
	wp.name = "WipePanel"
	var wr := _row_royale("Wipe the save", "gold, unlocks, everything · asks twice", false)
	wp.add_child(wr)
	_wipe = _small_button("Wipe", WButton.DANGER, WButton.RED)
	_wipe.name = "Wipe"
	_wipe.pressed.connect(_ask_wipe)
	wr.add_child(_wipe)
	content.add_child(wp)


## The foot (Royale): one line centred `R_FOOT_UP` over the screen's foot, "saved 9 h ago · Outlaw Survivors v1.00 ·
## Lanky Tinker 24" in Rubik 500 20, secondary blue (the saved part red when the disk refused); the version part takes
## the 2 s hold.
func _build_foot_royale() -> void:
	_foot = HBoxContainer.new()
	_foot.name = "FootLine"
	_foot.alignment = BoxContainer.ALIGNMENT_CENTER
	_foot.add_theme_constant_override("separation", 0)
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_foot.offset_left = R_SIDE
	_foot.offset_right = -R_SIDE
	_foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_foot.offset_top = -R_FOOT_UP
	_foot.offset_bottom = -R_FOOT_UP + roundf(R_FOOT_PX * 1.3)
	_saved_line = W.serif_text(_saved_text(), R_FOOT_PX, R.SECONDARY, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	_saved_line.name = "Saved"
	_saved_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saved_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if Save.last_error != "":
		_saved_line.color = _bad_ink()
	_foot.add_child(_saved_line)
	_foot_dot = W.serif_text(" · ", R_FOOT_PX, R.SECONDARY, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	_foot_dot.name = "Dot"
	_foot_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foot_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foot.add_child(_foot_dot)
	_version = W.serif_text(version_line(), R_FOOT_PX, R.SECONDARY, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, false, false)
	_version.name = "Version"
	_version.mouse_filter = Control.MOUSE_FILTER_STOP
	_version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_version.gui_input.connect(_on_version_input)
	_foot.add_child(_version)
	add_child(_foot)


## Royale: while the debug mode's message shows, the foot gives it the whole width (the saved part and the dot step
## aside, the message wraps to two lines at most); then the line comes back. Nothing under Wanted.
func _foot_message(on: bool) -> void:
	if _foot == null or not is_instance_valid(_foot):
		return
	_saved_line.visible = not on
	_foot_dot.visible = not on
	_version.wrap = on
	_version.custom_minimum_size.x = (1080.0 - 2.0 * R_SIDE) if on else 0.0
	_foot.offset_top = -R_FOOT_UP - (roundf(R_FOOT_PX * 1.3) if on else 0.0)


## The UI theme flipped in the Debug panel (pass 123): the whole screen again in the new theme (its header, backdrop and
## foot are the theme's too), or, when this screen is not the scene (a test), its board as before.
func _rebuild_for_theme() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().change_scene_to_file(scene_file_path if scene_file_path != "" else "res://ui/SettingsScreen.tscn")
		return
	_refresh()


## The mock's slate panel: the slate role (4 px navy edge, 8 px navy base, the lip), `pad_v` over and under, 28 px at the
## sides, holding a column `gap` apart (`column` false: the panel holds a single row itself, the wipe's).
func _panel_royale(pad_v: int, gap: int, column: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var e := R.PANEL_EDGE
	var b := W.box(W.PAPER, e, R.PANEL_BASE).pad(R_PAD_X + e, pad_v + e, R_PAD_X + e, pad_v + e)
	b.role = "panel"
	p.add_theme_stylebox_override("panel", b)
	if column:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", gap)
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		p.add_child(v)
	return p


## The mock's row: at least 74 px, its name white Rubik 500 26 (a line under it in Rubik 500 20, secondary, wrapped:
## "Sub"), the control at the right, a faint 2 px line under the row (`line` false: none).
func _row_royale(t: String, sub: String = "", line: bool = true) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	h.custom_minimum_size.y = R_ROW_H
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := W.serif_text(t, R_ROW_PX, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
	l.name = "Name"
	col.add_child(l)
	if sub != "":
		var s := W.serif_text(sub, R_SUB_PX, R.SECONDARY, 400, false, HORIZONTAL_ALIGNMENT_LEFT, R_SUB_PX * 1.3, true, false)
		s.name = "Sub"
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(s)
		# a two-line row keeps 14 px over and under its words
		var mc := MarginContainer.new()
		mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_theme_constant_override("margin_top", 14)
		mc.add_theme_constant_override("margin_bottom", 14)
		mc.add_child(col)
		h.add_child(mc)
	else:
		h.add_child(col)
	if line:
		h.draw.connect(func(): h.draw_rect(Rect2(0.0, h.size.y - 2.0, h.size.x, 2.0), R_DIVIDER))
	return h


## The mock's switch row piece: WSwitch's 84 x 44 toggle at the right of a 140 x 74 target (the row's height).
func _switch_royale(on: bool) -> WSwitch:
	var s := WSwitch.make(on)
	s.custom_minimum_size = Vector2(140, R_ROW_H)
	return s


## A slider row (Royale): the name (240 px, white Rubik 500 26), then the slider (WSlider as today), 96 px tall.
func _slider_row_royale(t: String, value: float, lo: float, hi: float, on_change: Callable, mult: float = 0.0, levels: int = 0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "SliderRow" + t.replace(" ", "")
	h.add_theme_constant_override("separation", 30)
	h.custom_minimum_size.y = R_SLIDER_H
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := W.serif_text(t, R_ROW_PX, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
	l.name = "Name"
	l.custom_minimum_size.x = R_SLIDER_LABEL_W
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := WSlider.make_levels(value, levels, lo, hi) if levels > 1 else WSlider.make(value, lo, hi)
	if mult > 0.0:
		s.shown = func(v: float) -> float: return v * mult
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x): on_change.call(x))
	h.add_child(s)
	return h


## The rows' small button (RESET, WIPE): the mock's 150 x 52, its word in capitals in Ultra 28 (Garry's floor).
func _small_button(t: String, variant: String, role: String) -> WButton:
	var b := WButton.make([t.to_upper()], R_BUTTON_PX, variant, R.BUTTON_EDGE, R.BUTTON_BASE, 0.0, 14.0, float(R_BUTTON_PX), role)
	b.custom_minimum_size = R_BUTTON
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A sub-head in the Debug panel: Bitter 30 ink (Wanted, as before); Royale the row's white Rubik 500 26.
func _sub_head(t: String) -> WText:
	if W.royale():
		var w := W.serif_text(t, R_ROW_PX, R.WHITE, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
		w.name = "SubHead"
		# room over it (a choice's base hangs over the gap above), the words at its foot
		w.custom_minimum_size.y = roundf(R_ROW_PX * 1.3) + 16.0
		w.valign = VERTICAL_ALIGNMENT_BOTTOM
		return w
	return W.serif_text(t, 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)


## A choice's words: as given (Wanted); the titles in capitals under Royale (the mock's FIXED / FOLLOW, SMALL / NORMAL /
## LARGE), the sublines as they are.
static func _choice_words(options: Array) -> Array:
	if not W.royale():
		return options
	var out: Array = []
	for o: Array in options:
		var c := o.duplicate()
		c[0] = str(c[0]).to_upper()
		out.append(c)
	return out


## Empty room in a column (the floating-text panel's foot under its choice).
static func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


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


## The foot line (pass 59): the build and the player's name in PostHog, "Outlaw Survivors v0.98 · Dusty Coyote 41" (the
## game's name since pass 115, W.GAME_NAME; "88fits" before), so a tester can read it out.
static func version_line() -> String:
	return "%s v%s · %s" % [W.GAME_NAME, str(ProjectSettings.get_setting("application/config/version", "")), Save.player_name()]


## Holding the version line for 2 s opens the developer menu; lifting or sliding the finger away cancels it.
func _on_version_input(e: InputEvent) -> void:
	# pass 81 (lane PROD): no developer menu in the production build
	if Settings.is_prod():
		return
	if e is InputEventScreenTouch or (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		var down: bool = e.pressed
		_holding = down
		_hold_t = 0.0
		_hold_from = e.position
		_version.color = _soft_ink()
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _holding:
		if e.position.distance_to(_hold_from) > 40.0:
			_holding = false
			_version.color = _soft_ink()


func _process(delta: float) -> void:
	super._process(delta)
	if not _holding:
		return
	_hold_t += delta
	# halfway there the line turns brass, so a held finger knows something is coming
	_version.color = _held_ink() if _hold_t > HOLD * 0.5 else _soft_ink()
	if _hold_t >= HOLD:
		_holding = false
		Audio.play("ui_tap")
		go("res://ui/DevMenu.tscn")
