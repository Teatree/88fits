## Pause (Wanted screens 13, 13b, 13c): "PAUSED" and the clock with the stage, the tab strip, and a board under it.
## Build: one row per held item saying what it does, with its stars, under a word for each group: the weapons, the
## lines, then every passive item (pass 47, Garry: "To see all the items including the Passives Player has to go Pause
## and see the Build Tab": the passive items have no HUD slot), then the perks, each plate in its colour (weapons light
## blue, lines light yellow, passive items their rarity's); a tapped row opens on its numbers (a stat grid), its
## mutation chips and what evolving still needs. Stats: a breakdown card (max HP by default, any stat on a tap) over two
## columns of every stat. Options: sound, music, screen shake, the floating text (pass 54: the four switches and the size
## the Settings screen has) and abandoning the run (a pop-up asks first); the rest lives in Settings. RESUME at the
## bottom. Nothing hand-written per item.
## Pass 54: the board's list clips (it is a ScrollContainer), and the sliders' thumbs hang over their rows (WSlider: 19 px
## above the track's row, 25 below plus a 5 px shadow, 46 px past the right end at the top value), so the Options list has
## room inside it for them: OPT_TOP above the first row and OPT_BOTTOM under the last (taken off the board's padding, so
## the rows stay where the mock has them) and the slider rows end SLIDER_RIGHT before the list's edge. A once-a-run item
## that has done its deed (Phoenix Feather) reads "(used)" after its name in grey on its Build row.
class_name PauseScreen
extends WModal

## The Options list's room for the thumbs (pass 54): above the first row, under the last, and the slider rows' margins.
const OPT_TOP := 28
const OPT_BOTTOM := 36
const SLIDER_LEFT := 8
const SLIDER_RIGHT := 52
## The floating text's switches (pass 54): the words, the setting, the node's name (as the Settings screen has them).
const FLOAT_SWITCHES := [["Damage numbers", "damage_numbers", "DamageNumbers"], ["Heal numbers", "float_heal", "HealNumbers"],
	["XP numbers", "float_xp", "XpNumbers"], ["Coin numbers", "float_coins", "CoinNumbers"]]
## A spent item's word on its Build row (pass 54; SPENT in rock before).
const USED := "(used)"

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


func _ready() -> void:
	build_dim(W.DIM)
	var paused := W.slab_text("PAUSED", 110, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	paused.shadow = 8
	var inset := W.safe_top()
	paused.position = Vector2(48, 60 + inset)
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
	plate.offset_top = 84 + inset
	add_child(plate)
	_tabs = WTabs.make(["Build", "Stats", "Options"], 30)
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tabs.offset_left = 48
	_tabs.offset_right = -48
	_tabs.offset_top = 230 + inset
	_tabs.changed.connect(func(i): _tab = i; _refresh())
	add_child(_tabs)
	# the board: paper, 5 px ink on three sides; the chosen tab opens into it
	_board = PanelContainer.new()
	_board.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_board.offset_left = 48
	_board.offset_right = -48
	_board.offset_top = 308 + inset
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
	_refresh()
	modulate.a = 1.0
	enter()


func close() -> void:
	visible = false
	if _touch:
		_touch.reset()


## A question up (the abandon pop-up) keeps the board still under a finger.
func _input(event: InputEvent) -> void:
	if visible and _touch and not WConfirm.is_open(self):
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
	if _tab == 2:
		# the Options list carries its own room for the thumbs inside the clip (OPT_TOP, OPT_BOTTOM): the board's padding
		# gives it up, so the rows stay put
		b.pad(pads[0] + 5, pads[1] - OPT_TOP, pads[0] + 5, pads[1] + 5 - OPT_BOTTOM)
	else:
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


## The board is as tall as what it holds (the Options list's room for the thumbs too: its spacers are children), up to
## the RESUME button; past that the list scrolls under a finger.
func _fit_board() -> void:
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var room := vp.y - 90.0 - 124.0 - 40.0 - _board.offset_top
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
		_content.add_child(W.serif_text("Nothing yet.", 28, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	if not Run.weapons.is_empty():
		_group("Weapons", "%d / %d" % [Run.weapons.size(), Run.weapon_cap()])
	for w in Run.weapons:
		var inst: WeaponInstance = w
		_content.add_child(_item_row(inst.def, inst.level, inst.def.max_level, inst))
	var lines := Run.held_lines()
	if not lines.is_empty():
		# out of the six slots (the arena's cap is as many as it likes: then the count alone)
		var cap := Run.line_cap()
		_group("Lines", ("%d / %d" % [lines.size(), cap]) if cap <= Run.MAX_LINES else str(lines.size()))
	for pid in lines:
		var ld: PassiveDef = Registry.passive(str(pid))
		if ld:
			_content.add_child(_item_row(ld, int(Run.passives.get(pid, 1)), ld.max_level, null))
	var passives := Run.held_passives()
	if not passives.is_empty():
		_group("Passives", "%d · not on the HUD" % passives.size())
	for pid in passives:
		var def: PassiveDef = Registry.passive(str(pid))
		if def:
			_content.add_child(_item_row(def, int(Run.passives.get(pid, 1)), def.max_level, null))
	if not Run.perks.is_empty():
		_group("Perks", "")
	for pk in Run.perks:
		var pdef: PerkDef = Registry.perk(pk)
		if pdef:
			_content.add_child(_item_row(pdef, 1, 1, null))


## A group's head on the Build tab (pass 47): its word tracked in ink-soft, a count after it.
func _group(title: String, count: String) -> void:
	var h := HBoxContainer.new()
	h.name = "Group" + title
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(W.label(title, 20, W.INK_SOFT))
	if count != "":
		var c := W.serif_text(count, 22, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	_content.add_child(h)


## One line on what an item does: a weapon's first sentence with its mutation names after it, a passive's generated
## line (a maxed one that can evolve says so).
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
	elif Run.item_spent(def):
		s = "Used: it stood you up once this run"
	elif def is PassiveDef:
		# what it gives at the level held, in total ("+56% pickup radius")
		s = TextGen.describe_effects(TextGen._sum_effects((def as PassiveDef).effects_for_level(maxi(level, 1))))
		if level >= (def as PassiveDef).max_level and (def as PassiveDef).evolves_into != "":
			s += " · maxed, can evolve"
	if s == "" or s.begins_with(" · "):
		s = def.flavour.trim_suffix(".") + s
	return s


## The stars' size on a Build row (pass 48, Garry: bigger stars everywhere; 24 before).
const STAR_PX := 34.0


func _item_row(def: ContentDef, level: int, max_level: int, inst: WeaponInstance) -> WRow:
	var open := _expanded == def.id
	var marks: Control = null
	# an item that has done its once-a-run deed (pass 48, Run.item_spent: Phoenix Feather once it stood him up)
	var spent := Run.item_spent(def)
	if spent:
		# "(used)" in grey after its name (pass 54; SPENT in rock before), no stars, the plate in its locked look
		pass
	elif not def is PerkDef and max_level > 1:
		# the stars, open or closed (pass 48: the mutations are dots on the plate, so the open row needs no rivets)
		marks = WMarks.new().setup("stars", max_level, level, -1, STAR_PX)
	# a weapon's plate carries its mutation dots and glows while it waits to evolve (pass 48)
	var dots := Run.path_progress(inst) if inst else Vector2i.ZERO
	var evo_ready := Run.evolution_ready(inst) if inst else false
	var row := WRow.make(def, _one_line(def, level, inst), marks, open, spent, level, dots, evo_ready, USED if spent else "")
	if spent and row.suffix:
		# the name the tests and tools know the mark by
		row.suffix.name = "Spent"
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
				desc = passive_now(def, level)
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


## A held passive's words on its open Build row (pass 51: the arena's ITEMS tab shows the same): what it gives at
## `level`, and its trade once.
static func passive_now(def: PassiveDef, level: int) -> String:
	var desc := TextGen.passive_description(def, level)
	if def.trade != "":
		desc += " Trade: %s." % def.trade.trim_suffix(".")
	return desc


func _evolve_note(inst: WeaponInstance) -> String:
	return evolve_note(inst)


## What evolving still needs, in a few words, after how many of its path's mutations it has (pass 48: "2/3 mutations",
## the evolution needs every one and the top level). Static since pass 51: the arena's ITEMS tab says the same.
static func evolve_note(inst: WeaponInstance) -> String:
	if inst.def.is_evolution:
		return "evolved"
	if inst.def.evolves_into == "":
		return ""
	var pp := Run.path_progress(inst)
	var need := pp.y - pp.x
	var have := "%d/%d mutations" % [pp.x, pp.y]
	if need > 0:
		return have + (" · one more and it can evolve" if need == 1 else " · %d more and it can evolve" % need)
	if inst.level < inst.def.max_level:
		return have + " · Lv %d and it can evolve" % inst.def.max_level
	return have + " · evolves at the next chest"


# ---------------------------------------------------------------- stats

const STATS := ["damage_reduction", "regen", "move_speed", "might", "cooldown", "area", "projectile_speed", "duration", "amount",
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
	# a timed buff by the name it was given (pass 49: Pollen's "buff:pollen:hornet_nest" read "Buff:pollen:hornet nest")
	if src.begins_with("buff:"):
		for tb in Run.timed:
			if str(tb.get("source", "")) == src and str(tb.get("label", "")) != "":
				return str(tb["label"])
		var pk: PickupDef = Registry.pickup(src.trim_prefix("buff:"))
		if pk:
			return pk.display_name
	var parts := src.split(":")
	if parts.size() == 2:
		var def: ContentDef = null
		match parts[0]:
			"passive", "favourite":
				def = Registry.passive(parts[1])
			"perk":
				def = Registry.perk(parts[1])
			"mutation":
				def = Registry.mutation(parts[1])
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
	# the room for the thumbs (pass 54): a spacer over the first row and one under the last, the rows 44 apart between
	_content.add_theme_constant_override("separation", 0)
	var top := _spacer(OPT_TOP)
	top.name = "OptionsTop"
	_content.add_child(top)
	var opts := VBoxContainer.new()
	opts.name = "OptionsRows"
	opts.add_theme_constant_override("separation", 44)
	opts.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(opts)
	var bottom := _spacer(OPT_BOTTOM)
	bottom.name = "OptionsBottom"
	_content.add_child(bottom)
	opts.add_child(_slider_row("Sound", Settings.sfx_volume, 0.0, 1.0, func(v): Settings.set_value("sfx_volume", v), 5))
	opts.add_child(_slider_row("Music", Settings.music_volume, 0.0, 1.0, func(v): Settings.set_value("music_volume", v), 5))
	var shake := HBoxContainer.new()
	shake.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sl := W.serif_text("Screen shake", 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shake.add_child(sl)
	var sw := WSwitch.make(Settings.screen_shake > 0.0)
	sw.name = "ScreenShake"
	sw.toggled.connect(func(on): Settings.set_value("screen_shake", 1.0 if on else 0.0))
	shake.add_child(sw)
	opts.add_child(shake)
	opts.add_child(_floating_text_block())
	# the rule, then abandoning the run: a pop-up asks first (pass 45)
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
	# the purse, with its coin (pass 46): since pass 70 abandoning banks it like any end
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override("separation", 8)
	purse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := WCoin.make(26.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	purse.add_child(coin)
	var amount := W.slab_text(W.num(Run.run_gold), 24, W.BRASS_DARK, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	purse.add_child(amount)
	var lost := W.serif_text("picked up so far is kept · asks first", 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	lost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	purse.add_child(lost)
	tv.add_child(purse)
	row.add_child(tv)
	var btn := WButton.make(["Abandon"], 28, WButton.DANGER, 4, 5, 12.0, 28.0)
	btn.name = "Abandon"
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_ask_abandon)
	row.add_child(btn)
	# its hard shadow sits 5 px past its right edge: the row stops short of the list's clip
	var keep := MarginContainer.new()
	keep.add_theme_constant_override("margin_right", 8)
	keep.mouse_filter = Control.MOUSE_FILTER_PASS
	keep.add_child(row)
	ab.add_child(keep)
	opts.add_child(ab)


## The floating text (pass 54, Garry: the Settings screen's switches, a pause away during a run): damage, heal, XP and
## coin numbers on or off, and their size; each saved at once, as Settings saves them.
func _floating_text_block() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "FloatingText"
	v.add_theme_constant_override("separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(W.label("Floating text", 20, W.INK_SOFT))
	for spec in FLOAT_SWITCHES:
		var r := HBoxContainer.new()
		r.mouse_filter = Control.MOUSE_FILTER_PASS
		var l := W.serif_text(str(spec[0]), 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(l)
		var key: String = spec[1]
		var s := WSwitch.make(bool(Settings.get(key)))
		s.name = str(spec[2])
		s.toggled.connect(func(on: bool): Settings.set_value(key, on))
		r.add_child(s)
		v.add_child(r)
	var size_label := W.label("Floating text size", 20, W.INK_SOFT)
	v.add_child(size_label)
	var size_choice := WChoice.make([["Small"], ["Normal"], ["Large"]], Settings.float_size, 30, 20, 14.0,
		HORIZONTAL_ALIGNMENT_CENTER, 0)
	size_choice.name = "FloatSize"
	size_choice.chosen.connect(func(i: int): Settings.set_value("float_size", i))
	v.add_child(size_choice)
	return v


## The question before the run is thrown away (pass 45): a pop-up over the board, not a button that changes its words.
## Abandoning counts as a death, and since pass 70 a death banks the run's gold like an extraction (Game.end_run).
func _ask_abandon() -> void:
	var gold := Run.run_gold
	var body := "The run ends here" + ((", and the %s gold picked up so far comes home with you." % W.num(gold)) if gold > 0 else ".")
	WConfirm.open(self, "Abandon the run?", body, "Abandon", "Keep playing", func():
		if game:
			close()
			game.abandon_run())


## A setting as a row: its name in Bitter 30 (200 px), then the slider (`levels` stops when it has them: the volumes).
## Pass 54: in a margin, SLIDER_LEFT in and SLIDER_RIGHT short of the list's edge, so the thumb at the top value (46 px
## past the track and its 5 px shadow) stays inside the list's clip.
func _slider_row(name: String, value: float, lo: float, hi: float, on_change: Callable, levels: int = 0) -> Control:
	var m := MarginContainer.new()
	m.name = "SliderRow" + name
	m.add_theme_constant_override("margin_left", SLIDER_LEFT)
	m.add_theme_constant_override("margin_right", SLIDER_RIGHT)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(h)
	var l := W.serif_text(name, 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	l.custom_minimum_size.x = 200
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := WSlider.make_levels(value, levels, lo, hi) if levels > 1 else WSlider.make(value, lo, hi)
	s.value_changed.connect(func(x): on_change.call(x))
	h.add_child(s)
	return m
