## Pause (Wanted screens 13, 13b, 13c): "PAUSED" and the clock with the stage, the tab strip, and a board under it.
## Build: one row per held item saying what it does, with its stars; a tapped row opens on its numbers (a stat grid),
## its path chips and what evolving still needs. Stats: a breakdown card (max HP by default, any stat on a tap) over two
## columns of every stat. Options: sound, music, screen shake and abandoning the run (it asks twice); the rest lives in
## Settings. RESUME at the bottom. Nothing hand-written per item.
class_name PauseScreen
extends WModal

var game: Node
var _tabs: WTabs
var _tab := 0
var _expanded := ""
var _stat := "max_hp"
var _clock: WText
var _board: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _touch: TouchScroll
var _abandon_armed := false


func _ready() -> void:
	build_dim(W.DIM)
	var paused := W.slab_text("PAUSED", 110, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	paused.shadow = 8
	paused.position = Vector2(48, 60)
	paused.size = Vector2(600, 110)
	add_child(paused)
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", W.box(W.PAPER, 4, 5).pad(28, 10, 28, 10))
	_clock = W.slab_text("00:00 · Stage 1", 40, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	plate.add_child(_clock)
	plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.offset_right = -48
	plate.offset_top = 84
	add_child(plate)
	_tabs = WTabs.make(["Build", "Stats", "Options"], 30)
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tabs.offset_left = 48
	_tabs.offset_right = -48
	_tabs.offset_top = 230
	_tabs.changed.connect(func(i): _tab = i; _refresh())
	add_child(_tabs)
	# the board: paper, 5 px ink on three sides; the chosen tab opens into it
	_board = PanelContainer.new()
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_board.offset_left = 48
	_board.offset_right = -48
	_board.offset_top = 308
	add_child(_board)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_content)
	_touch = TouchScroll.new(_scroll)
	var resume := WButton.make(["RESUME"], 60, WButton.PRIMARY, 6, 10, 26.0, 0.0, 60.0)
	resume.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	resume.offset_left = 48
	resume.offset_right = -48
	resume.offset_bottom = -90
	resume.offset_top = -90 - 124
	resume.pressed.connect(func(): if game: game.close_pause())
	add_child(resume)


func open() -> void:
	_abandon_armed = false
	_refresh()
	modulate.a = 1.0
	enter()


func close() -> void:
	visible = false
	if _touch:
		_touch.reset()


func _input(event: InputEvent) -> void:
	if visible and _touch:
		_touch.input(event)


func _process(_delta: float) -> void:
	if visible and _touch:
		_touch.process()


func _refresh() -> void:
	_clock.text = "%s · %s" % [W.mmss(Run.elapsed), ("Endless" if Run.endless else "Stage %d" % (Run.stage + 1))]
	_tabs.select(_tab, false)
	for c in _content.get_children():
		c.queue_free()
	_content.add_theme_constant_override("separation", 14)
	var pads: Array = [[24, 24], [30, 30], [30, 40]][_tab]
	var b := WTabs.board()
	b.pad(pads[0] + 5, pads[1], pads[0] + 5, pads[1] + 5)
	_board.add_theme_stylebox_override("panel", b)
	match _tab:
		0:
			_build_tab()
		1:
			_stats_tab()
		2:
			_options_tab()
	_fit_board.call_deferred()


## The board is as tall as what it holds, up to the RESUME button; past that the list scrolls under a finger.
func _fit_board() -> void:
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var room := vp.y - 90.0 - 124.0 - 40.0 - 308.0
	var want := _content.get_combined_minimum_size().y
	var st: StyleBox = _board.get_theme_stylebox("panel")
	var pads: float = st.content_margin_top + st.content_margin_bottom if st else 0.0
	var h := minf(want, room - pads)
	_scroll.custom_minimum_size.y = h
	# anchored across the screen: its height is set by the bottom offset (reset_size would undo the anchors)
	_board.offset_bottom = _board.offset_top + h + pads


# ---------------------------------------------------------------- build

func _build_tab() -> void:
	if Run.weapons.is_empty() and Run.passives.is_empty():
		_content.add_child(W.serif_text("Nothing yet. Pick a starter.", 28, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	for w in Run.weapons:
		var inst: WeaponInstance = w
		_content.add_child(_item_row(inst.def, inst.level, inst.def.max_level, inst))
	for pid in Run.passives.keys():
		var def: PassiveDef = Registry.passive(pid)
		if def:
			_content.add_child(_item_row(def, int(Run.passives[pid]), def.max_level, null))
	for lid in Run.lines.keys():
		var ldef: LineDef = Registry.line(lid)
		if ldef:
			_content.add_child(_item_row(ldef, int(Run.lines[lid]), ldef.max_level, null))
	for pk in Run.perks:
		var pdef: PerkDef = Registry.perk(pk)
		if pdef:
			_content.add_child(_item_row(pdef, 1, 1, null))


## One line on what an item does: a weapon's first sentence with its path names after it, a passive's generated line,
## a maxed line that can evolve says so.
func _one_line(def: ContentDef, level: int, inst: WeaponInstance) -> String:
	var s := ""
	if inst:
		# the first sentence that says what it does (not the weapon's name, not the tails every weapon shares)
		for sentence in inst.description().split(". "):
			var t := sentence.strip_edges().trim_suffix(".")
			if t == "" or t == def.display_name or t == "Knocks enemies back" or t.begins_with("Evolved:") or t.ends_with(" only"):
				continue
			s = t
			break
		var names: Array = []
		for m in inst.mutations:
			names.append((m as MutationDef).display_name)
		if not names.is_empty():
			s += " · " + " · ".join(names)
	elif def is PerkDef:
		s = (def as PerkDef).text.split(". ")[0].trim_suffix(".")
	elif def is PassiveDef:
		# what it gives at the level held, in total ("+56% pickup radius")
		s = TextGen.describe_effects(TextGen._sum_effects((def as PassiveDef).effects_for_level(maxi(level, 1))))
		if def is LineDef and level >= (def as LineDef).max_level and (def as LineDef).evolves_into != "":
			s += " · maxed, can evolve"
	if s == "" or s.begins_with(" · "):
		s = def.flavour.trim_suffix(".") + s
	return s


func _item_row(def: ContentDef, level: int, max_level: int, inst: WeaponInstance) -> WRow:
	var open := _expanded == def.id
	var marks: Control = null
	if inst and open and def is WeaponDef and not (def as WeaponDef).is_evolution:
		var r := WMarks.new().setup("rivets", Run.EVOLVE_MUTATIONS + 1, inst.mutations.size(), -1, 30.0)
		r.gap = 6.0
		marks = r
	elif not def is PerkDef and max_level > 1:
		marks = WMarks.new().setup("stars", max_level, level, -1, 24.0)
	var row := WRow.make(def, _one_line(def, level, inst), marks, open)
	row.pressed.connect(func():
		_expanded = "" if open else def.id
		_refresh())
	if open:
		if inst:
			var cells: Array = []
			for sr in inst.stat_rows():
				if cells.size() >= 3:
					break
				cells.append([str(sr["name"]), _short_number(str(sr["value"]))])
			cells.append(["this run", W.num(int(Run.damage_by_weapon.get(def.id, 0.0)))])
			row.body.add_child(WRow.stat_grid(cells))
			var names: Array = []
			for m in inst.mutations:
				names.append((m as MutationDef).display_name)
			var note := _evolve_note(inst)
			if not names.is_empty() or note != "":
				row.body.add_child(WRow.path_chips(names, note))
		else:
			var desc := ""
			if def is PerkDef:
				desc = (def as PerkDef).text
			elif def is PassiveDef:
				desc = TextGen.passive_description(def, level)
				if def is LineDef and (def as LineDef).trade != "":
					desc += ". Trade: %s." % (def as LineDef).trade
			var nxt := TextGen.next_level_text(def, level) if not def is PerkDef else ""
			var cells2: Array = [["now", desc]]
			var p := WRow.stat_grid([])
			var v := VBoxContainer.new()
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(W.serif_text(desc, 24, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
			if nxt != "":
				v.add_child(W.serif_text(nxt, 22, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
			p.get_child(0).queue_free()
			p.add_child(v)
			row.body.add_child(p)
			cells2.clear()
	return row


## "5.70 s" -> "5.7 s", "16.00 s" -> "16 s": the grid's numbers carry no trailing zeros.
func _short_number(v: String) -> String:
	var m := RegEx.create_from_string("^(-?\\d+)\\.(\\d*?)0+(\\D.*)?$").search(v)
	if m == null:
		return v
	var frac := m.get_string(2)
	return m.get_string(1) + ("." + frac if frac != "" else "") + m.get_string(3)


## What evolving still needs, in a few words.
func _evolve_note(inst: WeaponInstance) -> String:
	if inst.def.is_evolution:
		return "evolved"
	if inst.def.evolves_into == "":
		return ""
	var need := Run.EVOLVE_MUTATIONS - inst.mutations.size()
	if need > 0:
		return "one more and it can evolve" if need == 1 else "%d more paths and it can evolve" % need
	return "evolves at the next chest"


# ---------------------------------------------------------------- stats

const STATS := ["armor", "regen", "move_speed", "might", "cooldown", "area", "projectile_speed", "duration", "amount",
	"magnet", "luck", "greed", "xp_gain", "lifesteal", "evade", "crit_chance", "thorns", "execute_frac", "revives"]


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


func _stats_tab() -> void:
	var sheet := Run.player_sheet
	# the open stat: its value and where it comes from
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", W.box(W.AGED, 4, 0).pad(24, 20, 24, 20))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := W.serif_text(_cap(TextGen.stat_name(_stat)), 28, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	top.add_child(W.slab_text(TextGen.format_value(_stat, sheet.get_stat(_stat)), 36, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0))
	cv.add_child(top)
	for r in sheet.breakdown(_stat):
		if r["source"] == "total":
			continue
		var t := str(r["text"])
		var bad := t.begins_with("-") or t.begins_with("−")
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var src := W.serif_text(_source_name(str(r["source"])), 24, W.ROCK if bad else W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		src.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(src)
		line.add_child(W.serif_text(t, 24, W.ROCK if bad else W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_RIGHT, 0.0))
		cv.add_child(line)
	_content.add_child(card)
	_content.add_child(_spacer(2))
	# two columns of the rest, each a tap away from its breakdown
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	var keys: Array = STATS.duplicate()
	if _stat != "max_hp":
		keys.push_front("max_hp")
		keys.erase(_stat)
	if sheet.get_stat("shield_max", 0.0) > 0.0 and not keys.has("shield_max") and _stat != "shield_max":
		keys.append("shield_max")
	for s in keys:
		grid.add_child(_stat_cell(_cap(TextGen.stat_name(s)), TextGen.format_value(s, sheet.get_stat(s)), s))
	grid.add_child(_stat_cell("Kills", W.num(Run.kills), ""))
	_content.add_child(grid)


func _source_name(src: String) -> String:
	if src == "base":
		return "Base"
	var parts := src.split(":")
	if parts.size() == 2:
		var def: ContentDef = null
		match parts[0]:
			"passive":
				def = Registry.passive(parts[1])
				if def == null:
					def = Registry.line(parts[1])
			"line":
				def = Registry.line(parts[1])
			"character":
				def = Registry.character(parts[1])
			"weapon":
				def = Registry.weapon(parts[1])
		if def:
			return def.display_name
		return _cap(parts[1].replace("_", " "))
	return _cap(src.replace("_", " "))


func _stat_cell(n: String, v: String, stat: String) -> Control:
	var cell := WTap.new()
	var b := W.box(Color(0, 0, 0, 0), 2, 0).pad(0, 12, 0, 12)
	b.sides = [false, false, false, true]
	b.border_color = W.AGED
	cell.box = b
	cell.box_down = b
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := W.serif_text(n, 28, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(W.slab_text(v, 30, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0))
	cell.add_child(h)
	if stat != "":
		cell.pressed.connect(func():
			_stat = stat
			_refresh())
	return cell


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ---------------------------------------------------------------- options

func _options_tab() -> void:
	_content.add_theme_constant_override("separation", 44)
	_content.add_child(_slider_row("Sound", Settings.sfx_volume, 0.0, 1.0, func(v): Settings.set_value("sfx_volume", v)))
	_content.add_child(_slider_row("Music", Settings.music_volume, 0.0, 1.0, func(v): Settings.set_value("music_volume", v)))
	var shake := HBoxContainer.new()
	shake.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sl := W.serif_text("Screen shake", 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shake.add_child(sl)
	var sw := WSwitch.make(Settings.screen_shake > 0.0)
	sw.toggled.connect(func(on): Settings.set_value("screen_shake", 1.0 if on else 0.0))
	shake.add_child(sw)
	_content.add_child(shake)
	# the rule, then abandoning the run: it asks twice
	var ab := VBoxContainer.new()
	ab.add_theme_constant_override("separation", 36)
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = W.INK
	rule.custom_minimum_size.y = 4
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ab.add_child(rule)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(W.serif_text("Abandon the run", 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	tv.add_child(W.serif_text("gold picked up so far is lost · asks twice", 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	row.add_child(tv)
	var btn := WButton.make(["Sure? Tap again" if _abandon_armed else "Abandon"], 28, WButton.DANGER, 4, 5, 12.0, 28.0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func():
		if not _abandon_armed:
			_abandon_armed = true
			_refresh()
			return
		if game:
			close()
			game.abandon_run())
	row.add_child(btn)
	ab.add_child(row)
	_content.add_child(ab)


## A setting as a row: its name in Bitter 30 (200 px), then the slider.
func _slider_row(name: String, value: float, lo: float, hi: float, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := W.serif_text(name, 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.custom_minimum_size.x = 200
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := WSlider.make(value, lo, hi)
	s.value_changed.connect(func(x): on_change.call(x))
	h.add_child(s)
	return h
