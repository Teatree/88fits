## Pause: Build (every held item, expandable, with live numbers), Stats (every stat with its breakdown),
## Options (camera, joystick size, shake, volumes, hints, abandon). Nothing hand-written per item.
class_name PauseScreen
extends Control

var game: Node
var _tabs: HBoxContainer
var _content: VBoxContainer
var _tab := 0
var _expanded := ""
var _timer: Label
var _box: VBoxContainer


func _ready() -> void:
	UiKit.fullscreen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(UiKit.dim(0.9))
	_box = UiKit.vbox(16)
	var v := _box
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 40
	v.offset_right = -40
	v.offset_top = 70
	v.offset_bottom = -60
	add_child(v)
	var head := UiKit.hbox()
	head.add_child(UiKit.label("PAUSED", 64, UiKit.INK))
	_timer = UiKit.label("", 28, UiKit.INK3, HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_timer)
	v.add_child(head)
	_tabs = UiKit.hbox(10)
	for i in range(3):
		var b := UiKit.button(["Build", "Stats", "Options"][i], 32, false, 80)
		b.pressed.connect(func(): _tab = i; _refresh())
		_tabs.add_child(b)
	v.add_child(_tabs)
	_content = UiKit.vbox(14)
	v.add_child(UiKit.scroll(_content))
	var resume := UiKit.button("Resume", 44, true, 120)
	resume.pressed.connect(func(): if game: game.close_pause())
	v.add_child(resume)


func open() -> void:
	visible = true
	_refresh()
	UiFx.enter(self, _box)


func close() -> void:
	visible = false


func _refresh() -> void:
	_timer.text = "%s · %s" % [TextGen.time_mmss(Run.elapsed), ("endless" if Run.endless else "stage %d" % (Run.stage + 1))]
	for i in range(_tabs.get_child_count()):
		var b: Button = _tabs.get_child(i)
		b.add_theme_color_override("font_color", UiKit.ACCENT if i == _tab else UiKit.INK2)
	for c in _content.get_children():
		c.queue_free()
	match _tab:
		0:
			_build_tab()
		1:
			_stats_tab()
		2:
			_options_tab()


# ---------------------------------------------------------------- build

func _build_tab() -> void:
	if Run.weapons.is_empty() and Run.passives.is_empty():
		_content.add_child(UiKit.label("Nothing yet. Pick a starter.", 30, UiKit.INK3))
	for w in Run.weapons:
		_content.add_child(_item_row("weapon", w.def, w.level, w.def.max_level, w))
	for pid in Run.passives.keys():
		var def: PassiveDef = Registry.passive(pid)
		if def:
			_content.add_child(_item_row("passive", def, int(Run.passives[pid]), def.max_level, null))


func _item_row(kind: String, def: ContentDef, level: int, max_level: int, inst: WeaponInstance) -> Control:
	var expanded := _expanded == def.id
	var p := UiKit.panel(UiKit.BG2, 24, UiKit.ACCENT if expanded else UiKit.LINE, 3 if expanded else 2)
	var v := UiKit.vbox(10)
	p.add_child(v)
	var head := TapCard.new()
	head.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	head.pressed.connect(func(): _expanded = "" if expanded else def.id; Audio.play("ui_tap"); _refresh())
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_top", 6)
	hm.add_theme_constant_override("margin_bottom", 6)
	hm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hm)
	var h := UiKit.hbox(20)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hm.add_child(h)
	h.add_child(UiKit.icon_view(def, 90, kind))
	var nv := UiKit.vbox(2)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := UiKit.label(def.display_name, 40, UiKit.INK)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.add_child(nl)
	var tag := "%s · LV %d / %d" % [kind.to_upper(), level, max_level]
	if def is WeaponDef and def.is_evolution:
		tag = "EVOLVED WEAPON"
	var tl := UiKit.label(tag, 22, UiKit.TYPE_COLORS.get("evolution" if (def is WeaponDef and def.is_evolution) else kind, UiKit.ACCENT))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.add_child(tl)
	h.add_child(nv)
	var chev := UiKit.label("▾" if expanded else "›", 40, UiKit.INK3, HORIZONTAL_ALIGNMENT_RIGHT)
	chev.size_flags_horizontal = Control.SIZE_SHRINK_END
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(chev)
	v.add_child(head)
	if not expanded:
		return p
	# description
	var desc := ""
	if inst:
		desc = inst.description()
	elif def is PassiveDef:
		desc = TextGen.passive_description(def, level)
	v.add_child(UiKit.label(desc, 28, UiKit.INK2))
	if def.flavour != "":
		v.add_child(UiKit.label(def.flavour, 22, UiKit.INK3))
	# numbers
	if inst:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 20)
		grid.add_theme_constant_override("v_separation", 6)
		for row in inst.stat_rows():
			grid.add_child(UiKit.label(row["name"], 24, UiKit.INK3))
			grid.add_child(UiKit.label(row["value"], 24, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(UiKit.label("damage this run", 24, UiKit.INK3))
		grid.add_child(UiKit.label(str(int(Run.damage_by_weapon.get(def.id, 0.0))), 24, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(UiKit.label("kills this run", 24, UiKit.INK3))
		grid.add_child(UiKit.label(str(int(Run.kills_by_weapon.get(def.id, 0))), 24, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(grid)
	# next level
	var nxt := TextGen.next_level_text(def, level)
	var np := UiKit.panel(Color(UiKit.ACCENT.r, UiKit.ACCENT.g, UiKit.ACCENT.b, 0.14), 14, Color(0, 0, 0, 0), 0)
	np.add_child(UiKit.label(nxt, 26, UiKit.ACCENT))
	v.add_child(np)
	# evolution
	if inst:
		v.add_child(UiKit.label(Run.evolution_status(inst), 24, Color(0.72, 0.64, 1.0)))
	elif def is PassiveDef and def.pairs_with != "":
		var w := Registry.weapon(def.pairs_with)
		v.add_child(UiKit.label("Pairs with %s for an evolution." % (w.display_name if w else def.pairs_with), 24, Color(0.72, 0.64, 1.0)))
	return p


# ---------------------------------------------------------------- stats

func _stats_tab() -> void:
	var sheet := Run.player_sheet
	_content.add_child(UiKit.label("Every stat, with where it comes from.", 26, UiKit.INK3))
	var keys: Array = StatSheet.PLAYER_DEFAULTS.keys()
	for s in sheet.stats():
		if not keys.has(s):
			keys.append(s)
	for stat in keys:
		var p := UiKit.panel(UiKit.BG2, 18, UiKit.LINE, 1)
		var v := UiKit.vbox(4)
		p.add_child(v)
		var head := UiKit.hbox()
		head.add_child(UiKit.label(TextGen.stat_name(stat), 30, UiKit.INK))
		head.add_child(UiKit.label(TextGen.format_value(stat, sheet.get_stat(stat)), 30, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(head)
		var rows := sheet.breakdown(stat)
		if rows.size() > 2:
			for r in rows:
				if r["source"] == "total":
					continue
				var line := UiKit.hbox()
				line.add_child(UiKit.label(str(r["source"]).replace("passive:", "").capitalize(), 22, UiKit.INK3))
				line.add_child(UiKit.label(str(r["text"]), 22, UiKit.INK2, HORIZONTAL_ALIGNMENT_RIGHT))
				v.add_child(line)
		_content.add_child(p)
	_content.add_child(UiKit.label("Character: %s · %s" % [Run.character.display_name if Run.character else "", Run.character.flavour if Run.character else ""], 24, UiKit.INK3))


# ---------------------------------------------------------------- options

func _options_tab() -> void:
	_content.add_child(UiKit.label("Camera", 30, UiKit.INK))
	var row := UiKit.hbox(10)
	for i in range(2):
		var b := UiKit.button(["Fixed · north up", "Follow · behind"][i], 26, Settings.camera_mode == i, 84)
		b.pressed.connect(func(): Settings.set_value("camera_mode", i); _refresh())
		row.add_child(b)
	_content.add_child(row)
	_content.add_child(_slider("Joystick size", Settings.stick_size, 0.6, 1.4, func(v): Settings.set_value("stick_size", v)))
	_content.add_child(_slider("Screen shake", Settings.screen_shake, 0.0, 1.5, func(v): Settings.set_value("screen_shake", v)))
	_content.add_child(_slider("Sound", Settings.sfx_volume, 0.0, 1.0, func(v): Settings.set_value("sfx_volume", v)))
	_content.add_child(_slider("Music", Settings.music_volume, 0.0, 1.0, func(v): Settings.set_value("music_volume", v)))
	var hints := UiKit.button("Reset first-play hints", 28, false, 84)
	hints.pressed.connect(func(): Save.reset_hints(); _refresh())
	_content.add_child(hints)
	var dbg := UiKit.button("Debug panel: " + ("ON" if Settings.debug_panel else "OFF"), 28, false, 84)
	dbg.pressed.connect(func(): Settings.set_value("debug_panel", not Settings.debug_panel); _refresh())
	_content.add_child(dbg)
	_content.add_child(UiKit.spacer(30))
	var abandon := UiKit.button("Abandon run", 30, false, 90)
	abandon.add_theme_color_override("font_color", UiKit.DANGER)
	abandon.pressed.connect(func(): if game: close(); game.abandon_run())
	_content.add_child(abandon)


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
