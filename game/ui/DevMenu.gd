## The developer menu (Wanted 17): everything that used to leak into the player's screens, in one place, reached by
## holding the version line in Settings for 2 s. Ink, JetBrains Mono. The arena, the in-run debug panel, the debug
## buttons on the pick screens, the free revive and the hit log on Down! (and Results), the last run's last second, the recent system
## pauses, the hidden items (the Collection in its hidden mode) and where the save file lives. Switches save at once.
## Pass 48: the arena's training dummies, their health (UNDYING or 100 .. 10000 HP, Settings.dummy_hp) and how many
## stand in the field (10 .. 30, Settings.dummy_count), each a row that steps on a tap. Pass 49: whether the field patrols
## (Settings.dummy_patrol), the attacking dummies' health (Settings.attacker_dummy_hp), and the Elite dummy's and the Boss
## dummy's health and behaviour (stand, patrol, melee, ranged), stepped the same way.
extends Control

const SETTINGS := "res://ui/SettingsScreen.tscn"

var _list: VBoxContainer
var _scroll: ScrollContainer
var _touch: TouchScroll
var _open := ""


func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = W.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var header := WMenuHeader.make("")
	header.back.connect(_back)
	# on ink the back square keeps its paper face and loses its shadow
	var bb := W.box(W.PAPER, 5, 0)
	header.back_button.box = bb
	header.back_button.box_down = bb
	header.title.font = W.mono(500)
	header.title.font_size = 44
	header.title.line_height = 0.0
	header.title.color = W.PAPER
	header.title.valign = VERTICAL_ALIGNMENT_CENTER
	header.title.position.y = 0
	header.title.size = Vector2(860, 114)
	header.title.text = "developer · v%s" % str(ProjectSettings.get_setting("application/config/version", "0.28"))
	add_child(header)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 200 + W.safe_top()
	_scroll.offset_bottom = -40
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 48)
	m.add_theme_constant_override("margin_right", 48)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(m)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 18)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(_list)
	_touch = TouchScroll.new(_scroll)
	_refresh()


func _refresh() -> void:
	# out of the list at once (pass 48): a row only queued keeps its name, and the new one took a made-up one
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(_row("Arena", "›", func():
		Run.arena_next = true
		UiFx.go(get_tree(), "res://game/Game.tscn")))
	_list.add_child(_switch("Debug mode (the player's: 10 taps on the hints switch)", "debug_mode"))
	_list.add_child(_switch("Debug panel in run", "debug_panel"))
	_list.add_child(_switch("Debug buttons on modals", "debug_modal_buttons"))
	_list.add_child(_switch("Free revive button", "free_revive_button"))
	_list.add_child(_switch("Hit log on Down! · copy", "hit_log"))
	_list.add_child(_switch("Hidden heroes as locked on the title", "preview_locked_heroes"))
	# the arena's training dummies (pass 48): a tap steps each one on, the arena lays them out from these
	var hp_row := _row("Arena dummies · health", Settings.dummy_hp_label(Settings.dummy_hp), func():
		Settings.set_value("dummy_hp", Settings.next_step(Settings.DUMMY_HP_STEPS, Settings.dummy_hp))
		_refresh())
	hp_row.name = "DummyHealth"
	_list.add_child(hp_row)
	var n_row := _row("Arena dummies · count", str(Settings.dummy_count), func():
		Settings.set_value("dummy_count", Settings.next_step(Settings.DUMMY_COUNT_STEPS, Settings.dummy_count))
		_refresh())
	n_row.name = "DummyCount"
	_list.add_child(n_row)
	# pass 49: the field's patrol, the attackers' health, the Elite's and the Boss's health and behaviour
	var p_row := _row("Arena dummies · patrol", "ON" if Settings.dummy_patrol else "OFF", func():
		Settings.set_value("dummy_patrol", not Settings.dummy_patrol)
		_refresh())
	p_row.name = "DummyPatrol"
	_list.add_child(p_row)
	var a_row := _row("Arena attackers · health", Settings.dummy_hp_label(Settings.attacker_dummy_hp), func():
		Settings.set_value("attacker_dummy_hp", Settings.next_step(Settings.ATTACKER_HP_STEPS, Settings.attacker_dummy_hp))
		_refresh())
	a_row.name = "AttackerHealth"
	_list.add_child(a_row)
	for spec in [["elite", "Elite", Settings.ELITE_DUMMY_HP_STEPS], ["boss", "Boss", Settings.BOSS_DUMMY_HP_STEPS]]:
		var role: String = spec[0]
		var word: String = spec[1]
		var steps: Array = spec[2]
		var h_row := _row("Arena %s dummy · health" % word, Settings.dummy_hp_label(int(Settings.get(role + "_dummy_hp"))), func():
			Settings.set_value(role + "_dummy_hp", Settings.next_step(steps, int(Settings.get(role + "_dummy_hp"))))
			_refresh())
		h_row.name = word + "DummyHealth"
		_list.add_child(h_row)
		var m_row := _row("Arena %s dummy · behaviour" % word, str(Settings.get(role + "_dummy_mode")).to_upper(), func():
			Settings.set_value(role + "_dummy_mode", Settings.next_mode(str(Settings.get(role + "_dummy_mode"))))
			_refresh())
		m_row.name = word + "DummyMode"
		_list.add_child(m_row)
	# the top inset for a camera cutout: what the phone reports, or a fixed value to see the screens with one
	var ins := int(Settings.top_inset)
	_list.add_child(_row("Top inset · camera cutout", "AUTO (%d px)" % int(round(W.safe_top())) if ins < 0 else "%d px" % ins, func():
		var steps := [-1, 0, 80, 130, 180]
		var k := steps.find(int(Settings.top_inset))
		Settings.set_value("top_inset", steps[(k + 1) % steps.size()])
		_refresh()))
	_list.add_child(_file_row("Last run's last second", "user://breadcrumb.txt", "no run has left a breadcrumb yet"))
	_list.add_child(_file_row("Recent system pauses", "user://pauses.txt", "the phone has not paused a run"))
	var hidden := CollectionScreen.hidden_items().size()
	_list.add_child(_row("Hidden items · %d" % hidden, "›", func():
		CollectionScreen.hidden_only = true
		UiFx.go(get_tree(), "res://ui/CollectionScreen.tscn")))
	var save := _box()
	var sv: VBoxContainer = save.get_child(0)
	sv.add_child(W.text("Save file", W.mono(500), 30, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	var path := W.text(ProjectSettings.globalize_path(Save.path()), W.mono(500), 22, Color(W.AGED, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	sv.add_child(path)
	# what the boot read, the last write and its error, whether a backup sits beside the file (pass 45)
	var when: String = Time.get_datetime_string_from_unix_time(Save.last_saved_unix, true) + " UTC" if Save.last_saved_unix > 0 else "never"
	for line: String in ["loaded from: %s" % Save.loaded_from,
			"last write: %s%s" % [when, "" if Save.last_error == "" else " · " + Save.last_error],
			"backup: %s" % ("yes" if FileAccess.file_exists(Save.bak_path()) else "none")]:
		sv.add_child(W.text(line, W.mono(500), 22, Color(W.AGED, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	_list.add_child(save)


## A row's frame: a 3 px aged outline round 26 x 30 px of room, a column inside.
func _box() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var b := W.box(Color(0, 0, 0, 0), 3, 0).pad(33, 29, 33, 29)
	b.border_color = W.AGED
	p.add_theme_stylebox_override("panel", b)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return p


## A tappable row: the words on the left, the value or the arrow in brass on the right.
func _row(t: String, value: String, on_tap: Callable, extra: Control = null) -> WTap:
	var r := WTap.new()
	var b := W.box(Color(0, 0, 0, 0), 3, 0).pad(33, 29, 33, 29)
	b.border_color = W.AGED
	var down := b.duplicate() as HardBox
	down.fill = Color(W.PAPER, 0.08)
	r.box = b
	r.box_down = down
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := W.text(t, W.mono(500), 30, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var val := W.text(value, W.mono(500), 30, W.BRASS, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	val.name = "Value"
	h.add_child(val)
	v.add_child(h)
	if extra:
		v.add_child(extra)
	r.pressed.connect(on_tap)
	return r


## A setting that is on or off (Settings.<key>).
func _switch(t: String, key: String) -> WTap:
	var on := bool(Settings.get(key))
	return _row(t, "ON" if on else "OFF", func():
		Settings.set_value(key, not bool(Settings.get(key)))
		_refresh())


## A log file shown in the row when it is opened.
func _file_row(t: String, path: String, empty: String) -> WTap:
	var open := _open == path
	var body: Control = null
	if open:
		var txt := ""
		if FileAccess.file_exists(path):
			txt = FileAccess.get_file_as_string(path).strip_edges()
		body = W.text(txt if txt != "" else empty, W.mono(500), 22, Color(W.AGED, 0.85), HORIZONTAL_ALIGNMENT_LEFT, 30.0, true)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _row(t, "hide" if open else "›", func():
		_open = "" if open else path
		_refresh(), body)


func _back() -> void:
	UiFx.go(get_tree(), SETTINGS)


func _input(event: InputEvent) -> void:
	if _touch:
		_touch.input(event)


func _process(_delta: float) -> void:
	if _touch:
		_touch.process()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_back()
