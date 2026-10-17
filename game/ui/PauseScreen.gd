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
var _stat := AUTO
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
	# pass 76: another tab opens at its top (the Build list scrolled to its end left the Stats grid scrolled too)
	_tabs.changed.connect(func(i): _tab = i; _scroll.scroll_vertical = 0; _refresh())
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
	# pass 87 (lane SGAME): the stage's own clock
	_clock.text = "%s · %s" % [W.mmss(Run.stage_clock()), ("Endless" if Run.endless else "Stage %d" % (Run.stage + 1))]
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
	# pass 76: a card a tap opened scrolls into view once the list is laid out
	if _reveal and _tab == 1:
		await get_tree().process_frame
		_reveal_card()


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
		# pass 73 (lane CARDS): the line items are fortune cards to the player
		_group("Cards", ("%d / %d" % [lines.size(), cap]) if cap <= Run.MAX_LINES else str(lines.size()))
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

## core/systems/StatSources.gd by path (pass 76: a new script's class name is unknown until the editor imports it)
const SOURCES := preload("res://core/systems/StatSources.gd")

const STATS := ["damage_reduction", "regen", "move_speed", "might", "cooldown", "area", "projectile_speed", "duration", "amount",
	"magnet", "luck", "greed", "xp_gain", "lifesteal", "evade", "crit_chance", "thorns", "execute_frac", "revives"]

## Pass 76 (lane UI; Garry: "Stats in pause menu. Mark the stats that were changed since the start of the game. Provide
## some minimal info on which items are doing the stat changes underneath somewhere. Think like a good game UI designer
## here and be inspired by Vampire Survivors or Megabonk"): the grid in two columns, every stat that moved since the run
## began (StatSources, against Run.start_stats) in ink with a change pill (a drawn arrow the way the number went and how
## far, in the value's own unit; sage when it is better, rock when worse: a cooldown cut is sage), every one that did
## not dimmed; a stat that moved outside the list gets a cell of its own. A tapped cell opens its sources right under its
## row (the Build tab's rows open the same way), an aged card pointing at the cell: "At the start" (the base, the hero,
## the Upgrade board) and "This run" (cards, items, perks, mutations, the hero's levels, Totem gifts, the Stranger, timed
## buffs with their seconds left), a row a source with its icon and its summed amount. The first stat that moved opens
## by itself (max HP when none did); tapped again it closes.
## The open stat before the player picks one: the first that moved (see above).
const AUTO := "?"
## The Kills cell's key (a count, not a stat: never marked, never opened).
const KILLS := "kills"
## The two columns' gap and a cell's side padding.
const COL_GAP := 40
const CELL_PAD := 10
## The change pill's colours: better, worse (on the paper board and on the aged card).
const BETTER := W.SAGE
const WORSE := W.ROCK
## A source row's amount on the aged card: better, worse (darker than the pill's, so a small number reads on aged paper).
const BETTER_TEXT := Color("4a6b3c")
const WORSE_TEXT := Color("a03a22")
## The card's pointer: its height over the card's top edge and its half width.
const POINTER_H := 16.0
const POINTER_HW := 18.0
## An unchanged cell's ink: ink-soft, faded, so the stats that moved stand out.
const DIM_ALPHA := 0.62
## A source row's icon plate.
const SOURCE_PX := 40.0

var _open_card: Control
## Set by a tap: once laid out, the list scrolls so the card that opened is in view (_reveal_card).
var _reveal := false


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


static func _dim_ink() -> Color:
	return Color(W.INK_SOFT.r, W.INK_SOFT.g, W.INK_SOFT.b, DIM_ALPHA)


func _stats_tab() -> void:
	var sheet := Run.player_sheet
	var keys: Array = SOURCES.grid_stats(sheet, STATS)
	var moved: Array = keys.filter(func(s) -> bool: return SOURCES.changed(sheet, str(s)))
	if _stat == AUTO:
		_stat = str(moved[0]) if not moved.is_empty() else "max_hp"
	_content.add_child(_stats_head(moved.size()))
	var grid := VBoxContainer.new()
	grid.name = "StatGrid"
	grid.add_theme_constant_override("separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(grid)
	var cells: Array = keys.duplicate()
	cells.append(KILLS)
	_open_card = null
	for k in range(0, cells.size(), 2):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", COL_GAP)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var col := -1
		for j in range(2):
			if k + j < cells.size():
				var s := str(cells[k + j])
				row.add_child(_stat_cell(sheet, s))
				if s != KILLS and s == _stat:
					col = j
			else:
				var filler := Control.new()
				filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(filler)
		grid.add_child(row)
		if col >= 0:
			_open_card = _sources_card(sheet, _stat, col)
			grid.add_child(_open_card)


## The tab's head (as the Build tab's group heads): how many stats moved since the run began, and what a tap does.
func _stats_head(moved: int) -> Control:
	var h := HBoxContainer.new()
	h.name = "StatsHead"
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(W.label("Changed this run", 20, W.INK_SOFT))
	var n := W.serif_text(str(moved) if moved > 0 else "none yet", 22, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	n.name = "Moved"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	var tip := W.serif_text("tap a stat for its sources", 22, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, false, false)
	tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tip)
	return h


## One stat in the grid: its name, its change pill when it moved since the run began, its value; dimmed when it did not
## move; aged while its sources are open under it. A tap opens its sources, a tap on the open one closes them.
func _stat_cell(sheet: StatSheet, stat: String) -> Control:
	var kills := stat == KILLS
	var ch: Dictionary = {} if kills else SOURCES.change(sheet, stat)
	var moved := bool(ch.get("moved", false))
	var is_open := not kills and stat == _stat
	var cell := WTap.new()
	cell.name = "Stat_" + stat
	cell.set_meta("stat", stat)
	cell.set_meta("moved", moved)
	var b := W.box(W.AGED if is_open else Color(0, 0, 0, 0), 2, 0).pad(CELL_PAD, 12, CELL_PAD, 12)
	b.sides = [false, false, false, not is_open]
	b.border_color = W.AGED
	cell.box = b
	cell.box_down = b
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := W.INK if (moved or kills or is_open) else _dim_ink()
	var l := W.serif_text("Kills" if kills else _cap(TextGen.stat_name(stat)), 28, ink, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	l.name = "Name"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	if moved:
		var pill := _change_pill(ch, 22)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pill)
	var v := W.slab_text(W.num(Run.kills) if kills else TextGen.player_value(stat, SOURCES.now(sheet, stat)), 30, ink,
		HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	v.name = "Value"
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	cell.add_child(h)
	if not kills:
		cell.pressed.connect(func():
			_stat = "" if _stat == stat else stat
			_reveal = _stat != ""
			_refresh())
	return cell


## A change since the run began as a pill: a drawn arrow the way the number went and how far, paper on sage (better) or
## rock (worse). Named "Change", its meta "worse" and "up" for the tests.
func _change_pill(ch: Dictionary, px: int) -> PanelContainer:
	var worse := bool(ch.get("worse", false))
	var up := bool(ch.get("up", true))
	var p := PanelContainer.new()
	p.name = "Change"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("worse", worse)
	p.set_meta("up", up)
	p.add_theme_stylebox_override("panel", W.box(WORSE if worse else BETTER, 0, 0, 6).pad(7, 2, 9, 2))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(_arrow(up, W.PAPER, float(px) * 0.55))
	var t := W.slab_text(str(ch.get("text", "")), px, W.PAPER, HORIZONTAL_ALIGNMENT_LEFT, float(px) + 2.0)
	t.name = "Amount"
	h.add_child(t)
	return p


## A small filled triangle, pointing up or down (drawn: the kit's faces carry no arrow glyphs).
static func _arrow(up: bool, col: Color, px: float) -> Control:
	var a := Control.new()
	a.name = "Up" if up else "Down"
	a.custom_minimum_size = Vector2(px * 1.1, px)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	a.draw.connect(func():
		var w := a.size.x
		var hh := a.size.y
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w * 0.5, hh)])
		if up:
			pts = PackedVector2Array([Vector2(0, hh), Vector2(w * 0.5, 0), Vector2(w, hh)])
		a.draw_colored_polygon(pts, col))
	return a


## The open stat's sources under its row: an aged card pointing at the cell in column `col`, "At the start" with the
## value the run began with, then "This run" with the change (StatSources.rows: one row a source, its amount summed).
func _sources_card(sheet: StatSheet, stat: String, col: int) -> Control:
	var holder := MarginContainer.new()
	holder.name = "Sources"
	holder.add_theme_constant_override("margin_top", int(POINTER_H) + 4)
	holder.add_theme_constant_override("margin_bottom", 22)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", W.box(W.AGED, 4, 0).pad(26, 20, 26, 22))
	card.draw.connect(func(): _draw_pointer(card, col))
	holder.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var rs: Dictionary = SOURCES.rows(sheet, stat)
	var ch: Dictionary = SOURCES.change(sheet, stat)
	var start_v := W.slab_text(TextGen.player_value(stat, SOURCES.at_start(stat)), 26, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	v.add_child(_group_head("At the start", start_v, "GroupStart"))
	for r: Dictionary in rs[SOURCES.START]:
		v.add_child(_source_row(r, false))
	v.add_child(_spacer(6))
	var right: Control
	if bool(ch.get("moved", false)):
		right = _change_pill(ch, 22)
	else:
		right = W.serif_text("unchanged", 22, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_RIGHT, 0.0, false, false)
	v.add_child(_group_head("This run", right, "GroupRun"))
	for r: Dictionary in rs[SOURCES.RUN]:
		v.add_child(_source_row(r, true))
	return holder


## The card's pointer: an aged triangle over its top edge, under the middle of the open cell's column, its two sides
## inked as the card's border is.
func _draw_pointer(card: Control, col: int) -> void:
	var w := card.size.x
	var cw := (w - float(COL_GAP)) * 0.5
	var x := cw * 0.5 if col == 0 else w - cw * 0.5
	card.draw_colored_polygon(PackedVector2Array([Vector2(x - POINTER_HW, 4.0), Vector2(x, -POINTER_H),
		Vector2(x + POINTER_HW, 4.0)]), W.AGED)
	card.draw_polyline(PackedVector2Array([Vector2(x - POINTER_HW - 4.0, 2.0), Vector2(x, -POINTER_H),
		Vector2(x + POINTER_HW + 4.0, 2.0)]), W.INK, 4.0)


## A group's head on the card: its word tracked in ink-soft, what stands at its right (a value, the change pill).
func _group_head(title: String, right: Control, node_name: String) -> Control:
	var h := HBoxContainer.new()
	h.name = node_name
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := W.label(title, 20, W.INK_SOFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(right)
	return h


## One source on the card: its icon plate, its name (a timed buff's seconds left after it), its amount; "This run"'s
## amounts in the change's colours, the start's in ink-soft (rock when it pulls the stat the wrong way).
func _source_row(r: Dictionary, this_run: bool) -> Control:
	var h := HBoxContainer.new()
	h.name = "Source"
	h.set_meta("sid", str(r.get("sid", "")))
	h.set_meta("key", str(r.get("key", "")))
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_source_icon(r))
	var n := W.serif_text(str(r.get("name", "")), 24, W.INK if str(r.get("kind", "")) != "base" else W.INK_SOFT, 400, false,
		HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	n.name = "Name"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	var clock := float(r.get("clock", -1.0))
	if clock >= 0.0:
		var c := W.serif_text("%d s left" % int(ceilf(clock)), 22, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
		c.name = "Clock"
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	var worse := bool(r.get("worse", false))
	var col := W.INK_SOFT
	if worse:
		col = WORSE_TEXT
	elif this_run and str(r.get("op", "")) != "set":
		col = BETTER_TEXT
	var a := W.slab_text(str(r.get("text", "")), 24, col, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	a.name = "Amount"
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(a)
	return h


## A source's plate (SOURCE_PX): an item on its own plate (its colour, its level's for a card or a passive item), a hero
## on his round badge, anything else that has a picture (a talent's form, the Totem Pole, the Stranger) on paper; the base
## has none (an empty square keeps the names in line).
func _source_icon(r: Dictionary) -> Control:
	var def = r.get("def")
	var tex = r.get("icon")
	if def is ContentDef and (def is PassiveDef or def is PerkDef or def is MutationDef or def is WeaponDef or def is CharacterDef):
		var lv := int(Run.passives.get((def as ContentDef).id, 0)) if def is PassiveDef else 0
		var pl := WPlate.new().for_def(def, SOURCE_PX, false, lv)
		pl.name = "Icon"
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return pl
	if tex is Texture2D:
		var p := WPlate.new()
		p.name = "Icon"
		p.side = SOURCE_PX
		p.fill = W.PAPER
		p.border = 3
		p.radius = 8
		p.tex = tex
		p.icon_frac = 0.86
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return p
	var e := Control.new()
	e.custom_minimum_size = Vector2(SOURCE_PX, SOURCE_PX)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return e


## Once a tap opened a card and the list is laid out: scrolled so the whole card shows, never so far that the row it
## opened from leaves the top.
func _reveal_card() -> void:
	_reveal = false
	if not is_instance_valid(_open_card) or not _open_card.is_inside_tree():
		return
	var top := _open_card.get_global_position().y - _content.get_global_position().y
	var bottom := top + _open_card.size.y
	var view := _scroll.size.y
	var at := float(_scroll.scroll_vertical)
	if bottom <= at + view:
		return
	# the row above the card stays in sight (its height is the card's holder's previous sibling's)
	var row_top := top
	var i := _open_card.get_index()
	if i > 0:
		row_top = top - (_open_card.get_parent().get_child(i - 1) as Control).size.y
	_scroll.scroll_vertical = int(maxf(at, minf(bottom - view, row_top)))


## The name a sheet's source goes by in words (pass 49; the Stats tab names its rows by their source ids since pass 76:
## StatSources.describe_source): a timed buff by its label, an item by its name. Pass 76: a source in words of its own
## ("Totem: Le-loo", "Grit: Padding 3") is said whole; the ':' was cut and its first part lost.
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
	if parts.size() == 2 and parts[0] in ["passive", "favourite", "perk", "mutation", "character", "weapon"]:
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
	if src.contains(": "):
		return src
	return _cap(src.replace("_", " "))

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
