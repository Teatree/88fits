## Settings from the hub: camera mode, joystick size, shake, volumes, hints, debug, wipe save.
extends ScreenBase


func build() -> void:
	set_title("Settings")
	_refresh()


func _refresh() -> void:
	clear_content()
	content.add_child(UiKit.label("Camera", 30, UiKit.INK))
	content.add_child(UiKit.label("Fixed keeps north up, so the stick maps straight to the screen. Follow swings the camera behind the hero as he turns.", 24, UiKit.INK3))
	var row := UiKit.hbox(10)
	for i in range(2):
		var b := UiKit.button(["Fixed · north up", "Follow · behind"][i], 26, Settings.camera_mode == i, 84)
		b.pressed.connect(func(): Settings.set_value("camera_mode", i); _refresh())
		row.add_child(b)
	content.add_child(row)
	content.add_child(UiKit.label("Controls", 30, UiKit.INK))
	content.add_child(UiKit.label("Touch anywhere below the top strip and drag: the joystick appears under your thumb. Lift to stop. On a PC use WASD or the arrow keys. Every weapon fires by itself.", 24, UiKit.INK3))
	content.add_child(_slider("Joystick size", Settings.stick_size, 0.6, 1.4, func(v): Settings.set_value("stick_size", v)))
	content.add_child(_slider("Screen shake", Settings.screen_shake, 0.0, 1.5, func(v): Settings.set_value("screen_shake", v)))
	content.add_child(_slider("Sound", Settings.sfx_volume, 0.0, 1.0, func(v): Settings.set_value("sfx_volume", v)))
	content.add_child(_slider("Music", Settings.music_volume, 0.0, 1.0, func(v): Settings.set_value("music_volume", v)))
	var hints := UiKit.button("First-play hints: " + ("ON" if Settings.show_hints else "OFF"), 28, false, 84)
	hints.pressed.connect(func(): Settings.set_value("show_hints", not Settings.show_hints); _refresh())
	content.add_child(hints)
	var reset := UiKit.button("Show hints again next run", 28, false, 84)
	reset.pressed.connect(func(): Save.reset_hints(); Audio.play("ui_tap"))
	content.add_child(reset)
	var dbg := UiKit.button("Debug panel: " + ("ON" if Settings.debug_panel else "OFF"), 28, false, 84)
	dbg.pressed.connect(func(): Settings.set_value("debug_panel", not Settings.debug_panel); _refresh())
	content.add_child(dbg)
	content.add_child(UiKit.spacer(40))
	var wipe := UiKit.button("Wipe save (gold, unlocks, everything)", 26, false, 84)
	wipe.add_theme_color_override("font_color", UiKit.DANGER)
	wipe.pressed.connect(func(): Save.wipe(); Audio.play("ui_locked"); _refresh())
	content.add_child(wipe)
	content.add_child(UiKit.label("Save file: " + ProjectSettings.globalize_path("user://save.json"), 18, UiKit.INK3))


func _slider(name: String, value: float, lo: float, hi: float, on_change: Callable) -> Control:
	var v := UiKit.vbox(4)
	var h := UiKit.hbox()
	h.add_child(UiKit.label(name, 26, UiKit.INK2))
	var val := UiKit.label("%d%%" % int(value * 100), 24, UiKit.INK3, HORIZONTAL_ALIGNMENT_RIGHT)
	h.add_child(val)
	v.add_child(h)
	var s := UiKit.slider(value, lo, hi)
	s.value_changed.connect(func(x): val.text = "%d%%" % int(x * 100); on_change.call(x))
	v.add_child(s)
	return v
