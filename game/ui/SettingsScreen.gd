## Settings (Wanted 05): one screen, no debug. The camera as a two-way choice (Fixed / Follow), the joystick size, screen
## shake, sound and music as sliders, the first-play hints (a switch, and a reset for next run), and wiping the save,
## which asks twice. The version line at the foot opens the developer menu when held for 2 s.
extends ScreenBase

const HOLD := 2.0

var _version: WText
var _holding := false
var _hold_t := 0.0
var _hold_from := Vector2.ZERO
var _wipe_armed := false
var _wipe: WButton


func board_top() -> float:
	return 200.0


func board_bottom() -> float:
	return 50.0 + 29.0 + 20.0


func build() -> void:
	set_title("Settings")
	var version := str(ProjectSettings.get_setting("application/config/version", "0.28"))
	_version = W.serif_text("88fits v" + version, 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
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
	_refresh()


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
	box.add_child(_slider_row("Sound", Settings.sfx_volume, 0.0, 1.0, func(v): Settings.set_value("sfx_volume", v)))
	box.add_child(_slider_row("Music", Settings.music_volume, 0.0, 1.0, func(v): Settings.set_value("music_volume", v)))
	content.add_child(sl)
	# the hints
	var hp := _panel(24)
	var hints := _row("First-play hints")
	var sw := WSwitch.make(Settings.show_hints)
	sw.toggled.connect(func(on: bool): Settings.set_value("show_hints", on))
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
	# wiping the save: it asks twice
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
	_wipe = WButton.make(["Sure? Tap again" if _wipe_armed else "Wipe"], 26, WButton.DANGER, 4, 5, 10.0, 24.0)
	_wipe.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wipe.pressed.connect(_on_wipe)
	wr.add_child(_wipe)
	content.add_child(wp)


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
func _slider_row(t: String, value: float, lo: float, hi: float, on_change: Callable, mult: float = 0.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := W.serif_text(t, 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.custom_minimum_size.x = 260
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := WSlider.make(value, lo, hi)
	if mult > 0.0:
		s.shown = func(v: float) -> float: return v * mult
	s.value_changed.connect(func(x): on_change.call(x))
	h.add_child(s)
	return h


func _on_wipe() -> void:
	if not _wipe_armed:
		_wipe_armed = true
		_wipe.set_parts(["Sure? Tap again"])
		return
	_wipe_armed = false
	Save.wipe()
	Audio.play("ui_locked")
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
