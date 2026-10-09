## Collection (Wanted 04/04b): five tabs (pass 47: Weapons, Lines, Passives, Perks, Enemies; the lines have their own
## tab again, and Garry: "Change Creatures tab name to 'Enemies'"), the open one showing how many of its kind are found;
## a board of tiles (the item's plate in its colour, weapons light blue, lines light yellow, passive items their
## rarity's, and its name once it has been met in a run, pass 44; an aged plate with the icon's shadow and "Not found
## yet" until then; behind an unlock quest, the quest's words and its progress, and a tap opens the requirement page).
## The dangerous enemies wear their badge over the plate's top-left corner and a frame in their colour (a boss's skull
## in rock red, an Elite's crown in ember, a special's gear in brass), on the tile and on the page. A tile opens the
## item's page: the plate, what it does in full, its levels, for a weapon its mutations (the heroes' own among them,
## marked) and its evolution, for a line its evolution. Evolutions and mutations live on their item's page, heroes on
## the title. What is out of the game (hidden) is not here: the developer menu opens it (`hidden_only`).
class_name CollectionScreen
extends ScreenBase

const TABS := ["Weapons", "Lines", "Passives", "Perks", "Enemies"]
## The tab strip's type and padding: five tabs, the open one with its count, fit across a 1080 px screen.
const TAB_PX := 26
const TAB_PAD := Vector2(18, 16)
## The danger marks (pass 47): a role's badge (art/ui/badges/<badge>.png) and its frame colour.
const DANGER := {"boss": ["skull", W.ROCK], "elite": ["crown", W.EMBER], "special": ["gear", W.BRASS]}
const BADGE_ART := "res://art/ui/badges/%s.png"
## The tab strip's top, the grid's and the item page's (design px, each `W.safe_top()` lower on a phone with a camera
## cutout; pass 48: the tabs had no inset and covered the back square). The header's foot is at 158: the tabs start
## 14 px under it, the grid 75 px under the tabs' top (the strip is 73 tall), the page 32 px under the header.
const TAB_TOP := 172.0
const GRID_TOP := TAB_TOP + 75.0
const PAGE_TOP := 190.0
## The item page's side margins, and the gap between its mutation cells (three to a row).
const PAGE_SIDE := 48.0
const CELL_GAP := 20.0

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
	_tabs = WTabs.make(TABS, TAB_PX, TAB_PAD)
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tabs.offset_left = 36
	_tabs.offset_right = -36
	_tabs.offset_top = TAB_TOP + W.safe_top()
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
			# the lines (pass 47); an evolved line shows on its source's page
			out = Registry.sorted_lines()
		2:
			out = Registry.sorted_passives_only()
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
	for d in Registry.weapons.values() + Registry.passives.values() + Registry.perks.values() \
			+ Registry.mutations.values() + Registry.characters.values() + Registry.enemies.values():
		if Registry.is_hidden(d) or (d is EnemyDef and (d as EnemyDef).retired):
			if not out.has(d):
				out.append(d)
	out.sort_custom(func(a: ContentDef, b: ContentDef) -> bool: return a.display_name < b.display_name)
	return out


## Met in a run (pass 44): an item held once, a creature on the sand once (Save.seen). The developer's hidden list
## shows everything.
func _found(def: ContentDef) -> bool:
	if hidden_only:
		return true
	if def is EnemyDef:
		return Save.seen("enemy", def.id) or Save.keyed_total("kills_of_enemy", def.id) > 0
	if def is PerkDef:
		return Save.seen("perk", def.id)
	if def is WeaponDef and (def as WeaponDef).is_evolution:
		return Save.seen("weapon", def.id) or Save.keyed_total("kills_with_weapon", def.id) > 0
	return Save.seen(W.content_kind(def), def.id)


## Behind an unlock quest that is not done (pass 44: half the items are): the tile says what it takes and opens a page
## with the quest, its progress and the stage that can do it.
func _locked(def: ContentDef) -> bool:
	if hidden_only or def is EnemyDef or def is PerkDef or def is MutationDef or def is CharacterDef:
		return false
	return not Registry.is_unlocked(W.content_kind(def), def.id)


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


## One tile: the plate (its kind's colour) and the name; still to find, an aged plate
## with the icon's shadow and what it takes.
func _tile(def: ContentDef) -> WTap:
	var locked := _locked(def)
	var found := _found(def) and not locked
	var t := WTap.new()
	var clear := W.box(Color(0, 0, 0, 0), 0, 0)
	t.box = clear
	t.box_down = clear
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	var plate := WPlate.new().for_def(def, 210.0, not found, 1)
	plate.icon_frac = 160.0 / 210.0
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if def is EnemyDef:
		mark_danger(plate, def as EnemyDef, 84.0)
	v.add_child(plate)
	var label := def.display_name
	if locked:
		label = _still_to_find(def)
	elif not found:
		label = "Not met yet" if def is EnemyDef else "Not found yet"
	var n := W.slab_text(label, 24, W.INK if found else W.COMMON, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	n.wrap = true
	v.add_child(n)
	if locked:
		# how far the quest has come, when it counts
		var q := Registry.quest_for(W.content_kind(def), def.id)
		var p := QuestTracker.progress(q) if q else Vector2i.ZERO
		if p.y > 0:
			var bar := WBar.make(clampf(float(p.x) / float(p.y), 0.0, 1.0), W.BRASS, 24.0, 3, 0)
			bar.text = "%s / %s" % [W.num(mini(p.x, p.y)), W.num(p.y)]
			bar.text_px = 16
			v.add_child(bar)
	t.pressed.connect(func():
		if locked:
			_grid_scroll = scroll.scroll_vertical
			_open_locked(def)
			return
		if not found:
			Audio.play("ui_locked")
			return
		_grid_scroll = scroll.scroll_vertical
		_open_page(def))
	return t


## A locked item's page (pass 44): the plate in its aged look, what the quest asks, how far along it is, the stage that
## can do it, and what the item will do once it is open.
func _open_locked(def: ContentDef) -> void:
	_page = def
	set_title(def.display_name)
	_tabs.visible = false
	_foot.visible = false
	header.set_right(Control.new())
	set_board(PAGE_TOP, PAGE_SIDE)
	clear_content()
	var q := Registry.quest_for(W.content_kind(def), def.id)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 8).pad(35, 35, 35, 35))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var plate := WPlate.new().for_def(def, 272.0, true, 1)
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
	v.add_child(W.label("Locked · " + _kind_line(def), 22, W.ROCK, 0.15))
	v.add_child(W.serif_text(TextGen.quest_text(q) if q else "Not found yet.", 32, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 32.0 * 1.3, true))
	if q:
		var pr := QuestTracker.progress(q)
		if pr.y > 0:
			var bar := WBar.make(clampf(float(pr.x) / float(pr.y), 0.0, 1.0), W.BRASS, 40.0, 4, 0)
			bar.text = "%s / %s" % [W.num(mini(pr.x, pr.y)), W.num(pr.y)]
			bar.text_px = 24
			v.add_child(bar)
		var st := QuestTracker.stage_hint(q)
		var where := "Any stage will do"
		if st == 1:
			where = "Stage 1 can do it"
		elif st > 1:
			where = "Takes stage %d: keep going at the portal%s" % [st, "s" if st > 2 else ""]
		v.add_child(W.serif_text(where + ". Once done, it joins every run's offers.", 26, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	content.add_child(p)
	_section("What it does", _cell("", _full_text(def)), 60.0)


## What a still-hidden item takes, short: the unlock's own words without the full stop.
func _still_to_find(def: ContentDef) -> String:
	if def is EnemyDef:
		return "Not met yet"
	if def is PerkDef:
		var hero := Registry.character((def as PerkDef).hero)
		return "Play %s" % (hero.display_name if hero else (def as PerkDef).hero.capitalize())
	var q := Registry.quest_for(W.content_kind(def), def.id)
	if q == null and def.from_stage > 0:
		return "Stage %d only" % def.from_stage
	return TextGen.quest_text(q).strip_edges().trim_suffix(".") if q else "Not found yet"


# --- the item page ---------------------------------------------------------------------------------------------------

func _open_page(def: ContentDef) -> void:
	_page = def
	set_title(def.display_name)
	_tabs.visible = false
	_foot.visible = false
	header.set_right(Control.new())
	set_board(PAGE_TOP, PAGE_SIDE)
	clear_content()
	content.add_child(_hero_card(def))
	if def is WeaponDef:
		var w := def as WeaponDef
		_section("Levels", _level_grid(def), 78.0)
		var muts := page_mutations(w)
		if not muts.is_empty():
			_section("Mutations · take one a stage", _paths(muts), 157.0)
		var evo := Registry.weapon(w.evolves_into) if w.evolves_into != "" else null
		if evo:
			_section("Evolution · %s, then a chest" % evolve_needs(w), _evolution(evo), 135.0)
	elif def is PassiveDef:
		_section("Levels", _level_grid(def), 78.0)
		var into: PassiveDef = Registry.passive((def as PassiveDef).evolves_into) if (def as PassiveDef).evolves_into != "" else null
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
	var plate := WPlate.new().for_def(def, 272.0, false, 1)
	plate.border = 6
	plate.radius = 16
	plate.icon_frac = 220.0 / 272.0
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var danger: Array = []
	if def is EnemyDef:
		danger = mark_danger(plate, def as EnemyDef, 104.0)
	h.add_child(plate)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var k := W.kind_of(def)
	var word_c: Color = W.KIND_WORD.get(k, W.BRASS_DARK) if k != "enemy" else W.INK_SOFT
	if not danger.is_empty():
		word_c = W.BRASS_DARK if danger[0] == "gear" else danger[1]
	v.add_child(W.label(_kind_line(def), 22, word_c, 0.15))
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
	if def is PassiveDef:
		return "%s · %d levels" % ["Line" if W.is_line(def) else "Passive", W.max_level_of(def)]
	if def is PerkDef:
		var hero := Registry.character((def as PerkDef).hero)
		return "%s's perk" % (hero.display_name if hero else (def as PerkDef).hero.capitalize())
	if def is MutationDef:
		var w := Registry.weapon((def as MutationDef).weapon)
		return "Mutation · %s" % (w.display_name if w else (def as MutationDef).weapon)
	if def is CharacterDef:
		return "Hero"
	if def is EnemyDef:
		var e := def as EnemyDef
		var role := danger_role(e)
		return "Enemy · %s" % ({"boss": "boss", "elite": "Elite", "special": "special"}.get(role, e.archetype))
	return W.kind_of(def)


## How dangerous a creature is (pass 47): "boss", "elite" (the Elites: the crown), "special" (the one-at-a-time
## specials: the gear) or "" for the rest.
static func danger_role(e: EnemyDef) -> String:
	if e == null:
		return ""
	if e.archetype == "boss":
		return "boss"
	if e.archetype == "elite":
		return "elite"
	if e.badge_for() == "gear":
		return "special"
	return ""


## Marks a dangerous creature's plate (pass 47, Garry: "mark the enemies that are more dangerous accordingly, bosses and
## special enemies should also have their emoji icons in the top left of the icon"): its badge over the top-left
## corner, `badge_px` big, and a frame of its colour inside the ink border. Returns [badge, colour], [] for a plain one.
static func mark_danger(plate: WPlate, e: EnemyDef, badge_px: float) -> Array:
	var role := danger_role(e)
	if role == "":
		return []
	var spec: Array = DANGER[role]
	var path := BADGE_ART % str(spec[0])
	plate.badge = load(path) as Texture2D if ResourceLoader.exists(path) else null
	plate.badge_px = badge_px
	plate.ring = maxi(6, int(round(plate.side * 0.04)))
	plate.ring_color = spec[1]
	plate.base_ring = plate.ring
	plate.queue_redraw()
	return spec


## What the item does, generated from its data (never hand-written per item).
func _full_text(def: ContentDef) -> String:
	if def is WeaponDef:
		var inst := WeaponInstance.new(def, 1)
		inst.rebuild(StatSheet.new(), [])
		return inst.description()
	if def is PassiveDef:
		var pd := def as PassiveDef
		# an evolved passive has one level: all it is, its trade said once (the card's words)
		if pd.is_evolved():
			return WItem.effect({"def": pd, "level_from": 0, "level_to": 1, "evolve": true})
		var s := pd.text + " " if pd.text != "" else ""
		s += TextGen.passive_description(pd, 1)
		return s + (" The trade: %s." % pd.trade.trim_suffix(".") if pd.trade != "" else "")
	if def is PerkDef:
		return (def as PerkDef).text
	if def is MutationDef:
		return (def as MutationDef).text
	if def is CharacterDef:
		# the hero's rule (pass 61: one or two stats a level, TextGen's words wherever the trait shows)
		return TextGen.hero_trait(def as CharacterDef)
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


## What a weapon needs before a chest evolves it (pass 48: every mutation of its path and its top level): "all 3
## mutations at Lv 5".
static func evolve_needs(w: WeaponDef) -> String:
	var n := Registry.mutations_of(w.id).size()
	var m := "all %d mutations" % n if n > 1 else ("its mutation" if n == 1 else "")
	return ("%s at Lv %d" % [m, w.max_level]) if m != "" else "Lv %d" % w.max_level


## What a weapon's page lists under Mutations (pass 46): its path, then every hero's own mutation for it, the heroes in
## play only (Danza Macabra on the Skull Rain, Fan the Hammer on the Peashooter, Gyro Saws on the Orbit Saws).
static func page_mutations(w: WeaponDef) -> Array:
	return Registry.mutations_of(w.id) + Registry.weapon_hero_mutations(w.id)


## The words over a hero's own mutation on the weapon's page ("CALAVERA ONLY"); empty for a path mutation.
static func hero_only_text(m: MutationDef) -> String:
	if m == null or not m.is_hero():
		return ""
	var c: CharacterDef = Registry.character(m.hero)
	return "%s ONLY" % (c.display_name if c else m.hero).to_upper()


## A weapon's mutations: plum plates, the name, the first thing each does, three cells of one width to a row, a short
## last row centred under the others (pass 46: a lone fourth sits in the middle, a fifth and sixth around it). A hero's
## own one says whose it is.
func _paths(muts: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(CELL_GAP))
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var cell_w := floorf((get_viewport_rect().size.x - 2.0 * PAGE_SIDE - 2.0 * CELL_GAP) / 3.0)
	var row: HBoxContainer = null
	for i in muts.size():
		if i % 3 == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", int(CELL_GAP))
			row.mouse_filter = Control.MOUSE_FILTER_PASS
			col.add_child(row)
		row.add_child(_path_cell(muts[i], cell_w))
	return col


func _path_cell(m: MutationDef, cell_w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.custom_minimum_size.x = cell_w
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
	var only := hero_only_text(m)
	if only != "":
		var tag := W.label(only, 20, W.TURQUOISE, 0.15)
		tag.align = HORIZONTAL_ALIGNMENT_CENTER
		tag.wrap = true
		v.add_child(tag)
	var n := W.slab_text(m.display_name, 30, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	n.wrap = true
	v.add_child(n)
	v.add_child(W.serif_text(_first_sentence(m.text), 24, W.INK, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0, true))
	return p


func _first_sentence(t: String) -> String:
	var s := t.strip_edges()
	var i := s.find(". ")
	return s.substr(0, i + 1) if i > 0 else s


## The evolution: found, its plate and what it does; not yet, an aged card at 75 % with its shadow (a passive's says
## what it does either way).
func _evolution(evo: ContentDef) -> PanelContainer:
	var found := false
	if evo is WeaponDef:
		found = Save.keyed_total("kills_with_weapon", evo.id) > 0 or Save.seen("weapon", evo.id)
	elif evo is PassiveDef:
		found = Save.seen("passive", evo.id)
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
	var line := "Not yet found. Open a chest with every mutation taken and the weapon at its top level."
	if found or evo is PassiveDef:
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
	if e.damage_reduction > 0.0:
		grid.add_child(_cell("", "takes %d%% less" % int(round(e.damage_reduction * 100.0))))
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
