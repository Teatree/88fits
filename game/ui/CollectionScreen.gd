## Collection (Wanted 04/04b): five tabs (Weapons, Passives, Lines, Perks, Creatures), the open one showing how many of
## its kind are found; a board of tiles (the item's plate with its rarity seal and its name, or, still to find, an aged
## plate with the icon's shadow and what it takes). A tile opens the item's page: the plate, what it does in full, its
## levels, and for a weapon its three paths and its evolution. Evolutions and paths live on their weapon's page, heroes
## on the title. What is out of the game (hidden) is not here: the developer menu opens it (`hidden_only`).
class_name CollectionScreen
extends ScreenBase

const TABS := ["Weapons", "Passives", "Lines", "Perks", "Creatures"]
const GRID_TOP := 265.0
const PAGE_TOP := 190.0

## Set by the developer menu before it opens this screen: one board of everything hidden, no tabs.
static var hidden_only := false

var _tab := 0
var _tabs: WTabs
var _count: WText
var _foot: WText
var _page: ContentDef
var _grid_scroll := 0


func header_right() -> Control:
	_count = W.serif_text("", 30, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_RIGHT, 0.0)
	_count.set_meta("keep", true)
	return _count


func board_top() -> float:
	return PAGE_TOP if hidden_only else GRID_TOP


func board_room() -> float:
	return 0.0


func board_side() -> float:
	return 36.0


func board_bottom() -> float:
	return 50.0 + 31.0 + 20.0


func build() -> void:
	set_title("Hidden" if hidden_only else "Collection")
	content.add_theme_constant_override("separation", 0)
	_tabs = WTabs.make(TABS, 28, Vector2(26, 16))
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tabs.offset_left = 36
	_tabs.offset_right = -36
	_tabs.offset_top = GRID_TOP - 75.0
	_tabs.changed.connect(func(i: int): _tab = i; _show_grid())
	_tabs.visible = not hidden_only
	add_child(_tabs)
	_foot = W.serif_text("%s kills all time" % W.num(Save.total("kills")), 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_foot.offset_bottom = -50
	_foot.offset_top = -50 - 31
	add_child(_foot)
	_show_grid()


# --- what is in each tab ---------------------------------------------------------------------------------------------

func _items(tab: int) -> Array:
	var out: Array = []
	match tab:
		0:
			out = Registry.base_weapons()
		1:
			out = Registry.passives.values().filter(func(p): return not (p is LineDef))
		2:
			out = Registry.lines.values().filter(func(l: LineDef) -> bool: return l.evolves_from == "")
		3:
			out = Registry.perks.values()
		4:
			out = Registry.enemies.values()
	out = out.filter(func(d: ContentDef) -> bool: return not Registry.is_hidden(d) and not (d is EnemyDef and (d as EnemyDef).retired))
	out.sort_custom(func(a: ContentDef, b: ContentDef) -> bool:
		if a is PerkDef and b is PerkDef and (a as PerkDef).hero != (b as PerkDef).hero:
			return (a as PerkDef).hero < (b as PerkDef).hero
		return a.display_name < b.display_name)
	return out


## Everything the game keeps but does not play (the developer menu's list).
static func hidden_items() -> Array:
	var out: Array = []
	for d in Registry.weapons.values() + Registry.passives.values() + Registry.lines.values() + Registry.perks.values() \
			+ Registry.mutations.values() + Registry.characters.values() + Registry.enemies.values():
		if Registry.is_hidden(d) or (d is EnemyDef and (d as EnemyDef).retired):
			if not out.has(d):
				out.append(d)
	out.sort_custom(func(a: ContentDef, b: ContentDef) -> bool: return a.display_name < b.display_name)
	return out


func _found(def: ContentDef) -> bool:
	if hidden_only:
		return true
	if def is EnemyDef:
		return Save.keyed_total("kills_of_enemy", def.id) > 0
	if def is PerkDef:
		return Registry.is_unlocked("character", (def as PerkDef).hero)
	if def is WeaponDef and (def as WeaponDef).is_evolution:
		return Save.keyed_total("kills_with_weapon", def.id) > 0
	return Registry.is_unlocked(W.kind_of(def), def.id)


func _tally(tab: int) -> Vector2i:
	var items := _items(tab)
	return Vector2i(items.filter(func(d): return _found(d)).size(), items.size())


# --- the grid --------------------------------------------------------------------------------------------------------

func _show_grid() -> void:
	_page = null
	set_title("Hidden" if hidden_only else "Collection")
	header.set_right(_count)
	_tabs.visible = not hidden_only
	_foot.visible = not hidden_only
	set_board(PAGE_TOP if hidden_only else GRID_TOP, 36.0)
	clear_content()
	var found := 0
	var all := 0
	for t in TABS.size():
		var n := _tally(t)
		found += n.x
		all += n.y
		_tabs.set_label(t, [[TABS[t] + " ", null], ["%d/%d" % [n.x, n.y], W.BRASS_DARK]] if t == _tab else TABS[t])
	_tabs.select(_tab, false)
	_count.text = "%d hidden" % hidden_items().size() if hidden_only else "%d / %d found" % [found, all]
	var board := PanelContainer.new()
	board.mouse_filter = Control.MOUSE_FILTER_PASS
	var bb: HardBox
	if hidden_only:
		bb = W.box(W.PAPER, 5, 0)
	else:
		bb = WTabs.board()
	board.add_theme_stylebox_override("panel", bb.pad(35, 36 + (5 if hidden_only else 0), 35, 41))
	content.add_child(board)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 26)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	board.add_child(grid)
	for def in (hidden_items() if hidden_only else _items(_tab)):
		grid.add_child(_tile(def))
	scroll.set_deferred("scroll_vertical", _grid_scroll)


## One tile: the plate (its kind's colour, the rarity seal over its corner) and the name; still to find, an aged plate
## with the icon's shadow and what it takes.
func _tile(def: ContentDef) -> WTap:
	var found := _found(def)
	var t := WTap.new()
	var clear := W.box(Color(0, 0, 0, 0), 0, 0)
	t.box = clear
	t.box_down = clear
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	var plate := WPlate.new().for_def(def, 210.0, not found)
	plate.icon_frac = 160.0 / 210.0
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if found and not (def is EnemyDef) and not (def is PerkDef):
		var seal := WSeal.new().for_rarity(W.rarity_of(def), 50.0)
		seal.ring = 0
		seal.position = Vector2(210.0 - 47.0, -3.0)
		plate.add_child(seal)
	v.add_child(plate)
	var label := def.display_name
	if not found:
		label = _still_to_find(def)
	var n := W.slab_text(label, 24, W.INK if found else W.COMMON, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	n.wrap = true
	v.add_child(n)
	t.pressed.connect(func():
		if not found:
			Audio.play("ui_locked")
			return
		_grid_scroll = scroll.scroll_vertical
		_open_page(def))
	return t


## What a still-hidden item takes, short: the unlock's own words without the full stop.
func _still_to_find(def: ContentDef) -> String:
	if def is EnemyDef:
		return "Not met yet"
	if def is PerkDef:
		var hero := Registry.character((def as PerkDef).hero)
		return "Play %s" % (hero.display_name if hero else (def as PerkDef).hero.capitalize())
	var q := Registry.quest_for(W.kind_of(def), def.id)
	return TextGen.quest_text(q).strip_edges().trim_suffix(".") if q else "Not found yet"


# --- the item page ---------------------------------------------------------------------------------------------------

func _open_page(def: ContentDef) -> void:
	_page = def
	set_title(def.display_name)
	_tabs.visible = false
	_foot.visible = false
	if def is EnemyDef or def is PerkDef:
		header.set_right(Control.new())
	else:
		header.set_right(WSeal.new().for_rarity(W.rarity_of(def), 106.0))
	set_board(PAGE_TOP, 48.0)
	clear_content()
	content.add_child(_hero_card(def))
	if def is WeaponDef:
		var w := def as WeaponDef
		_section("Levels", _level_grid(def), 78.0)
		var muts := Registry.mutations_of(w.id)
		if not muts.is_empty():
			_section("Paths · take one a stage", _paths(muts), 157.0)
		var evo := Registry.weapon(w.evolves_into) if w.evolves_into != "" else null
		if evo:
			_section("Evolution · two paths, then a chest", _evolution(evo), 135.0)
	elif def is PassiveDef:
		_section("Ranks" if def is LineDef else "Levels", _level_grid(def), 78.0)
		if def is LineDef and (def as LineDef).evolves_into != "":
			var into: LineDef = Registry.lines.get((def as LineDef).evolves_into)
			if into:
				_section("Evolution · once it is full", _evolution(into), 80.0)
	elif def is EnemyDef:
		_section("Numbers", _creature_grid(def as EnemyDef), 78.0)


## The page's top card: the 272 px plate, the kind and its levels, what it does in full, the flavour, one tally.
func _hero_card(def: ContentDef) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 8).pad(35, 35, 35, 35))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var plate := WPlate.new().for_def(def, 272.0)
	plate.border = 6
	plate.radius = 16
	plate.icon_frac = 220.0 / 272.0
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var k := W.kind_of(def)
	v.add_child(W.label(_kind_line(def), 22, W.KIND_WORD.get(k, W.BRASS_DARK) if k != "enemy" else W.INK_SOFT, 0.15))
	v.add_child(W.serif_text(_full_text(def), 32, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 32.0 * 1.3, true))
	if def.flavour != "" and not (def is EnemyDef and (def as EnemyDef).doc != ""):
		v.add_child(W.serif_text(def.flavour, 26, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var tally := _tally_line(def)
	if tally != "":
		v.add_child(W.serif_text(tally, 24, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	return p


func _kind_line(def: ContentDef) -> String:
	if def is WeaponDef:
		return ("Evolution" if (def as WeaponDef).is_evolution else "Weapon") + " · %d levels" % (def as WeaponDef).max_level
	if def is LineDef:
		return "Line · %d ranks" % W.max_level_of(def)
	if def is PassiveDef:
		return "Passive · %d levels" % W.max_level_of(def)
	if def is PerkDef:
		var hero := Registry.character((def as PerkDef).hero)
		return "%s's perk" % (hero.display_name if hero else (def as PerkDef).hero.capitalize())
	if def is MutationDef:
		var w := Registry.weapon((def as MutationDef).weapon)
		return "Path · %s" % (w.display_name if w else (def as MutationDef).weapon)
	if def is CharacterDef:
		return "Hero"
	if def is EnemyDef:
		var e := def as EnemyDef
		return "Creature · %s" % ("boss" if e.archetype == "boss" else ("elite" if e.archetype == "elite" else e.archetype))
	return W.kind_of(def)


## What the item does, generated from its data (never hand-written per item).
func _full_text(def: ContentDef) -> String:
	if def is WeaponDef:
		var inst := WeaponInstance.new(def, 1)
		inst.rebuild(StatSheet.new(), [])
		return inst.description()
	if def is LineDef:
		var l := def as LineDef
		var s := TextGen.passive_description(def, 1)
		return s + (" The trade: %s." % l.trade.trim_suffix(".") if l.trade != "" else "")
	if def is PassiveDef:
		return TextGen.passive_description(def, 1)
	if def is PerkDef:
		return (def as PerkDef).text
	if def is MutationDef:
		return (def as MutationDef).text
	if def is CharacterDef:
		var c := def as CharacterDef
		return c.trait_text if c.trait_text != "" else TextGen.describe_effects(c.trait_effects)
	if def is EnemyDef:
		return (def as EnemyDef).doc if (def as EnemyDef).doc != "" else def.flavour
	return def.flavour


func _tally_line(def: ContentDef) -> String:
	if def is WeaponDef:
		var n := Save.keyed_total("kills_with_weapon", def.id)
		return ("%s kills with it, all time" % W.num(n)) if n > 0 else "No kills with it yet"
	if def is EnemyDef:
		return "Killed %s times" % W.num(Save.keyed_total("kills_of_enemy", def.id))
	return ""


## A labelled part of the page, `gap` under the one before.
func _section(title: String, body: Control, gap: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = gap
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(g)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(W.label(title, 22, W.INK_SOFT, 0.15))
	v.add_child(body)
	content.add_child(v)


## Level cells, four to a row: the level in brass slab, what it adds.
func _level_grid(def: ContentDef) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	var levels: Array = def.get("levels") if def.get("levels") != null else []
	var mx := W.max_level_of(def)
	var first := 2 if def is WeaponDef else 1
	for lv in range(first, mx + 1):
		var fx: Array = []
		if lv - 1 < levels.size():
			fx = levels[lv - 1]
		elif not levels.is_empty() and def is PassiveDef and (def as PassiveDef).repeat_last_level:
			fx = levels[levels.size() - 1]
		var text := TextGen.describe_effects(fx)
		if text == "":
			continue
		grid.add_child(_cell(str(lv), text))
	return grid


func _cell(n: String, text: String, fill: Color = W.PAPER) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", W.box(fill, 4, 0).pad(20, 16, 20, 16))
	var h := HBoxContainer.new()
	# one space of Bitter 24 between the level and what it adds, as the mock sets them inline
	h.add_theme_constant_override("separation", 5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if n != "":
		var num := W.slab_text(n, 28, W.BRASS, HORIZONTAL_ALIGNMENT_LEFT, 38.0)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(num)
	var t := W.serif_text(text, 24, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	return p


## A weapon's paths: plum plates, the name, the first thing each does.
func _paths(muts: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	for m: MutationDef in muts:
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", W.box(W.PAPER, 4, 0).pad(24, 24, 24, 24))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		var plate := WPlate.new().for_def(m, 150.0)
		plate.radius = 12
		plate.icon_frac = 110.0 / 150.0
		plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(plate)
		var n := W.slab_text(m.display_name, 30, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
		n.wrap = true
		v.add_child(n)
		v.add_child(W.serif_text(_first_sentence(m.text), 24, W.INK, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true))
		grid.add_child(p)
	return grid


func _first_sentence(t: String) -> String:
	var s := t.strip_edges()
	var i := s.find(". ")
	return s.substr(0, i + 1) if i > 0 else s


## The evolution: found, its plate and what it does; not yet, an aged card at 75 % with its shadow.
func _evolution(evo: ContentDef) -> PanelContainer:
	var found := Save.keyed_total("kills_with_weapon", evo.id) > 0 if evo is WeaponDef else false
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", W.box(W.PAPER if found else W.AGED, 4, 0).pad(34, 28, 34, 28))
	p.modulate.a = 1.0 if found else 0.75
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var plate := WPlate.new().for_def(evo, 170.0, not found)
	plate.radius = 12
	plate.icon_frac = 130.0 / 170.0
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(W.label("Evolution", 20, W.EMBER, 0.15))
	v.add_child(W.slab_text(evo.display_name, 44, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 44.0))
	var line := "Not yet found. Open a chest with two paths taken."
	if evo is LineDef:
		line = TextGen.passive_description(evo, 1)
	elif found:
		line = _full_text(evo)
	v.add_child(W.serif_text(line, 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	return p


## A creature's numbers as cells.
func _creature_grid(e: EnemyDef) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(_cell("", "%s HP" % W.num(e.hp)))
	grid.add_child(_cell("", "speed %s" % ("%.1f" % e.speed).trim_suffix(".0")))
	grid.add_child(_cell("", "%s damage" % W.num(e.damage)))
	if e.armor > 0.0:
		grid.add_child(_cell("", "armour %s" % W.num(e.armor)))
	return grid


## Back from a page goes to the grid; from the grid, to the title (or the developer menu, for the hidden list).
func on_back() -> void:
	if _page:
		_show_grid()
		return
	if hidden_only:
		hidden_only = false
		go("res://ui/DevMenu.tscn")
		return
	go(TITLE)
