## The debug arena (pass 33.4): the map and the hero with nothing coming unless asked, and this over it.
##
## A column of quick buttons at the right edge: ARENA opens the panel, AGAIN does the last spawn again, CLEAR takes every
## creature and shot away, WAVES runs or holds the real director, LV +1 levels the hero. Under them a line of status.
##
## The panel is a bottom sheet with six tabs (the game waits while it is open):
##   ENEMY  every creature in the game, by group (the roster in arrival order, the specials, the Elites, the bosses, the
##          retired and anything else), spawned with the options on top: how many, where (near, ring, far), an elite
##          modifier and whether they hold still. A boss comes as a real boss: its bar, its attacks, its portal.
##   WAVES  the arena clock (every spawn scales as at that minute), a crowd drawn from the roster at that minute, a swarm
##          of the last creature picked, the real director run from the clock (events, Elites, bosses, specials) or held,
##          and an Elite or a special on demand.
##   ITEMS  every weapon, evolution, line, passive, perk and mutation, each with − / + / max, applied at once and past
##          the caps the cards keep. Pass 49: each weapon's mutations and evolution are stacked under it, opened from
##          the weapon's row (weapon_stack); the weapons out of play have a section of their own. Pass 51: every row's INFO
##          opens what a player reads about it, at the level held and with the hero's stats now (item_texts), and a
##          weapon's EVO toggle counts the three path mutations its evolution needs (heroes' own are optional extras).
##   HERO   levels (+1, +5, +10, to 30), level-up cards on or off, god mode, heal, a hit, going down, gold, rerolls.
##          Pass 55: on top, every hero in play (and the ones out of play with the player's debug mode on), a tap swapping
##          him in where he stands (Game.arena_swap_hero), and the hero's looks (art variants) as chips: a tap draws him
##          in it for this visit, USE FROM NOW ON keeps it for every run (Save.set_hero_look, through the sandbox).
##   DROPS  every power-up on the sand by the hero, a chest, a boss chest, a shower of gems or coins.
##   WORLD  game speed, freezing the crowd, killing or removing everything, the camera's zoom, the stats overlay, leaving;
##          the training dummies (pass 48; pass 49: the patrol, the attacking dummies, the Elite and the Boss dummy).
## Nothing done here reaches the save (Game.leave_arena puts the save back as it was when the arena opened). A death here
## respawns the hero at once (pass 49, Game.arena_respawn); HERO's "Go down" is the real fall.
class_name ArenaPanel
extends Control

const TABS := [["enemy", "ENEMY"], ["waves", "WAVES"], ["items", "ITEMS"], ["hero", "HERO"], ["drops", "DROPS"], ["world", "WORLD"]]
const SHEET_H := 1180
## The quick column's top (pass 56): COLUMN_TOP under the camera cutout, and COLUMN_GAP under the boss's plate and bar
## while one is up and reaches lower (it sat at a fixed y 380, so with a 130 px inset, or under the power-ups, the boss's
## bar ran beneath ARENA and AGAIN).
const COLUMN_TOP := 380.0
const COLUMN_GAP := 20.0

var game: Node
var _tab := "enemy"
var _sheet: PanelContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _tab_buttons: Dictionary = {}
var _col: VBoxContainer
var _waves_btn: Button
var _again_btn: Button
var _status: Label
var _status_t := 0.0
var _paused_by_me := false
var _again: Callable = Callable()
var _again_name := ""
# ENEMY options
var _count := 1
var _place := "near"
var _elite_id := ""
var _hold := false
var _last_enemy := "goblin"
## The looks (pass 66, Garry: the arena must cope with ~50 looks of one creature): the chips wrap (HFlowContainer); with
## more than LOOKS_NOTED looks the per-code notes show only for the lit chip; with more than LOOKS_FOLD creatures carrying
## looks the Art variants section folds to one header a creature and a tap opens one (`_looks_open`); a shelved look
## (`variants[CODE].shelved`) is skipped unless the Shelved looks choice shows them, dimmed.
const LOOKS_NOTED := 8
const LOOKS_FOLD := 6
const SHELVED_ALPHA := 0.55
var _show_shelved := false
var _looks_open: Dictionary = {}
# WAVES
var _minute := 0.0
# ITEMS: which sections are open, and which weapons' stacks (STACK_KEY + the weapon's id, pass 49)
var _open: Dictionary = {"Weapons": true}
const STACK_KEY := "stack:"
## and which rows' INFO is open (INFO_KEY + kind + ":" + id, pass 51), with the fill of each open one, run again whenever a
## level is set here (one item's level reaches the others: Brawn changes every weapon's numbers)
const INFO_KEY := "info:"
var _info_fills: Array = []
# WORLD
var _speed := 1.0
var _frozen := false
var _zoom := 0.0
# scrolling by hand (a drag that starts on a button never reaches a ScrollContainer on a phone): TouchScroll
var _touch: TouchScroll


func _ready() -> void:
	UiKit.fullscreen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_toolbar()
	_build_sheet()
	_sheet.visible = false


# ---------------------------------------------------------------- the quick column

func _build_toolbar() -> void:
	var col := UiKit.vbox(10)
	col.name = "QuickColumn"
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -196
	col.offset_right = -16
	col.offset_top = column_top(-1.0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_col = col
	col.add_child(_tool("ARENA", open, true))
	_again_btn = _tool("AGAIN", _do_again)
	col.add_child(_again_btn)
	col.add_child(_tool("CLEAR", _clear_field))
	_waves_btn = _tool("WAVES", _toggle_waves)
	col.add_child(_waves_btn)
	col.add_child(_tool("LV +1", func(): _levels(1)))
	_status = UiKit.outline(UiKit.label("", 20, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT), 4)
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status)


## Where the quick column starts: COLUMN_TOP under the camera cutout (W.safe_top()), and COLUMN_GAP under the boss's
## plate when its foot (`boss_bottom`, -1 for none) reaches lower.
static func column_top(boss_bottom: float) -> float:
	var y := COLUMN_TOP + W.safe_top()
	if boss_bottom >= 0.0:
		y = maxf(y, boss_bottom + COLUMN_GAP)
	return y


## The quick column at its top for `hud` (the run's HUD: its boss plate) now.
func place_column(hud: Node) -> void:
	if _col == null:
		return
	var b := -1.0
	if hud != null and hud.has_method("boss_plate_bottom"):
		b = float(hud.call("boss_plate_bottom"))
	var y := column_top(b)
	if absf(_col.offset_top - y) > 0.5:
		_col.offset_top = y


func _tool(text: String, cb: Callable, primary := false) -> Button:
	var b := UiKit.button(text, 22, primary, 64)
	b.custom_minimum_size = Vector2(180, 64)
	b.modulate.a = 0.9
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------- the sheet

func _build_sheet() -> void:
	_sheet = UiKit.panel(Color(0.06, 0.05, 0.08, 0.97), 26, UiKit.INFO, 3)
	_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.offset_left = 10
	_sheet.offset_right = -10
	_sheet.offset_top = -SHEET_H
	_sheet.offset_bottom = -10
	add_child(_sheet)
	var v := UiKit.vbox(10)
	_sheet.add_child(v)
	var tabs := UiKit.hbox(6)
	v.add_child(tabs)
	for t in TABS:
		var id: String = t[0]
		var b := UiKit.button(t[1], 21, false, 70)
		b.pressed.connect(func(): _tab = id; _refresh())
		tabs.add_child(b)
		_tab_buttons[id] = b
	var x := UiKit.button("CLOSE", 21, true, 70)
	x.custom_minimum_size = Vector2(120, 70)
	x.size_flags_horizontal = Control.SIZE_SHRINK_END
	x.pressed.connect(close)
	tabs.add_child(x)
	_content = UiKit.vbox(12)
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll = UiKit.scroll(_content)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(_scroll)
	_touch = TouchScroll.new(_scroll, true, 0.92)


func open() -> void:
	if game == null or game.get("_ended"):
		return
	_sheet.visible = true
	if not game.paused:
		game.set_paused(true)
		_paused_by_me = true
	_refresh()


func close() -> void:
	_sheet.visible = false
	if _touch:
		_touch.reset()
	if _paused_by_me:
		_paused_by_me = false
		game.set_paused(false)


func is_open() -> bool:
	return _sheet.visible


func _refresh() -> void:
	var keep := _scroll.scroll_vertical
	_info_fills.clear()
	for c in _content.get_children():
		# out of the list at once (pass 49): a row only queued keeps its name, and the new one would take a made-up one
		_content.remove_child(c)
		c.queue_free()
	for id in _tab_buttons.keys():
		(_tab_buttons[id] as Button).modulate = Color(1.0, 0.85, 0.4) if id == _tab else Color(1, 1, 1)
	match _tab:
		"enemy":
			_enemy_tab()
		"waves":
			_waves_tab()
		"items":
			_items_tab()
		"hero":
			_hero_tab()
		"drops":
			_drops_tab()
		"world":
			_world_tab()
	_scroll.scroll_vertical = keep


# ---------------------------------------------------------------- building blocks

func _section(title: String) -> void:
	_content.add_child(UiKit.spacer(6))
	_content.add_child(UiKit.label(title, 30, UiKit.ACCENT))


func _note(text: String) -> void:
	var l := UiKit.label(text, 22, UiKit.INK3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)


func _buttons(pairs: Array, h := 72, size := 22) -> HBoxContainer:
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	for p in pairs:
		var b := UiKit.button(str(p[0]), size, false, h)
		var cb: Callable = p[1]
		b.pressed.connect(cb)
		row.add_child(b)
	_content.add_child(row)
	return row


## A label and a row of choices, the current one lit; `pick` gets the chosen value and the tab is redrawn. The row comes
## back so it can be named (pass 49: the touch audit finds the dummies' rows by name).
func _choice(title: String, options: Array, current, pick: Callable) -> HBoxContainer:
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := UiKit.label(title, 22, UiKit.INK2)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	for o in options:
		var val = o[0]
		var b := UiKit.button(str(o[1]), 20, val == current, 64)
		b.pressed.connect(func(): pick.call(val); _refresh())
		row.add_child(b)
	_content.add_child(row)
	return row


func _grid(defs: Array, cols: int, make: Callable) -> void:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.mouse_filter = Control.MOUSE_FILTER_PASS
	for d in defs:
		g.add_child(make.call(d))
	_content.add_child(g)


## A tile with an icon and a name; tapping it runs `cb`.
func _tile(def: ContentDef, kind: String, sub: String, cb: Callable) -> Control:
	var c := UiKit.card(UiKit.LINE, 2, UiKit.BG2, 18)
	c.custom_minimum_size = Vector2(336, 0)
	var v := UiKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiKit.margin(v, 10)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(m)
	var h := UiKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var ic := UiKit.icon_view(def, 84, kind)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var t := UiKit.vbox(0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := UiKit.label(def.display_name, 22, UiKit.INK)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size = Vector2(210, 0)
	t.add_child(n)
	if sub != "":
		t.add_child(UiKit.label(sub, 18, UiKit.INK3))
	h.add_child(t)
	c.pressed.connect(cb)
	return c


# ---------------------------------------------------------------- ENEMY

func _enemy_tab() -> void:
	_choice("How many", [[1, "1"], [5, "5"], [20, "20"], [50, "50"]], _count, func(v): _count = int(v))
	_choice("Where", [["near", "Near"], ["ring", "Ring"], ["far", "Far"]], _place, func(v): _place = str(v))
	var mods: Array = [["", "None"]]
	for e: EliteModDef in Registry.elites_list():
		mods.append([e.id, e.display_name])
	_choice("Elite mod", mods, _elite_id, func(v): _elite_id = str(v))
	_choice("Hold still", [[false, "No"], [true, "Yes"]], _hold, func(v): _hold = bool(v))
	_variants_section()
	for group in enemy_groups():
		if (group[1] as Array).is_empty():
			continue
		_section(group[0])
		_grid(group[1], 3, func(def: EnemyDef) -> Control:
			return _tile(def, "enemy", _enemy_sub(def), func(): spawn_enemy(def)))


## The art variants (pass 34): every creature that has more than one strip, a chip per code. A chip spawns How many of
## it with that art, so two or more can be walked side by side; the one the game plays is marked. The code is what to
## name when picking one. Pass 66: the chips wrap (`Variants_<id>`, chips `Variant_<id>_<code>`), the section folds to a
## header a creature (`LooksHead_<id>`) when more than LOOKS_FOLD creatures carry looks, shelved looks hide unless shown.
func _variants_section() -> void:
	var shelved_any := _any_shelved()
	var defs: Array = Registry.enemies.values().filter(func(d: EnemyDef) -> bool: return not d.variant_codes(_show_shelved).is_empty())
	if defs.is_empty() and not shelved_any:
		return
	defs.sort_custom(func(a, b): return a.id < b.id)
	_section("Art variants")
	_note("Tap a code to spawn How many with that art. ● is the one in the game. Tell Claude the code you like.")
	if shelved_any:
		_shelved_choice("ShelvedLooks")
	var fold := defs.size() > LOOKS_FOLD
	if fold:
		_note("Tap a creature to open its looks.")
	for d: EnemyDef in defs:
		var codes: Array = d.variant_codes(_show_shelved)
		if fold:
			var opened: bool = bool(_looks_open.get(d.id, false))
			var head := UiKit.button("%s  %s · %d looks" % ["▾" if opened else "▸", d.display_name, codes.size()], 22, opened, 64)
			head.name = "LooksHead_" + d.id
			head.alignment = HORIZONTAL_ALIGNMENT_LEFT
			head.pressed.connect(func(): _looks_open[d.id] = not opened; _refresh())
			_content.add_child(head)
			if not opened:
				continue
		var row := _chip_flow("Variants_" + d.id)
		if not fold:
			var l := UiKit.label(d.display_name, 22, UiKit.INK2)
			l.custom_minimum_size = Vector2(150, 0)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(l)
		for code in codes:
			var c := str(code)
			var b := UiKit.button(c + (" ●" if c == d.variant else ""), 20, c == d.variant, 64)
			b.name = "Variant_%s_%s" % [d.id, c]
			if d.variant_shelved(c):
				b.modulate = Color(1, 1, 1, SHELVED_ALPHA)
			b.pressed.connect(func(): spawn_enemy(d.variant_def(c)))
			row.add_child(b)
		_content.add_child(row)
		_look_notes(codes, func(c: String) -> String: return str((d.variants[c] as Dictionary).get("note", "")), d.variant)


## A row of chips that wraps (pass 66: fifty looks of one creature fit the sheet; an HFlowContainer as the Upgrade
## board's summary chips and the shop's tray).
func _chip_flow(row_name: String) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.name = row_name
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	f.mouse_filter = Control.MOUSE_FILTER_PASS
	return f


## The per-code notes under a chip row: every code's with up to LOOKS_NOTED looks, only the lit chip's with more (pass
## 66: fifty notes would bury the sheet). `note_of` gives a code's note, "" for none.
func _look_notes(codes: Array, note_of: Callable, lit: String) -> void:
	for code in codes:
		var c := str(code)
		if codes.size() > LOOKS_NOTED and c != lit:
			continue
		var note: String = str(note_of.call(c))
		if note != "":
			_note("%s  %s" % [c, note])


## The Shelved looks choice (pass 66): Hide (the default) or Show, dimmed; one switch for the ENEMY and HERO tabs.
func _shelved_choice(row_name: String) -> void:
	var row := _choice("Shelved looks", [[false, "Hide"], [true, "Show"]], _show_shelved, func(v): _show_shelved = bool(v))
	row.name = row_name


## Whether any creature carries a shelved look (pass 66): then the section offers to show them.
func _any_shelved() -> bool:
	for d: EnemyDef in Registry.enemies.values():
		for code in d.variants.keys():
			if d.variant_shelved(str(code)):
				return true
	return false


## Whether a hero carries a shelved look (pass 66).
static func hero_has_shelved(c: CharacterDef) -> bool:
	if c == null:
		return false
	for code in c.variants.keys():
		if c.variant_shelved(str(code)):
			return true
	return false


func _enemy_sub(def: EnemyDef) -> String:
	var bits: Array = ["%s hp" % str(snappedf(def.hp, 0.1))]
	if def.damage_reduction > 0.0:
		bits.append("takes %d%% less" % int(round(def.damage_reduction * 100.0)))
	if def.pack_size > 1:
		bits.append("packs of %d" % def.pack_size)
	return " · ".join(bits)


## Every creature in the game, grouped: the roster in arrival order, the specials, the Elites, the bosses, the retired,
## the training dummies (pass 49: the Elite and Boss dummies are Elites by their kind, but they are dummies first) and
## any other (the ones only an attack brings, like the centipede's young).
func enemy_groups() -> Array:
	var seen: Dictionary = {}
	var roster: Array = []
	var specials: Array = []
	var tl: WaveTimeline = Run.map.timeline if Run.map else null
	if tl:
		for r in tl.roster:
			var d: EnemyDef = Registry.enemy(str(r.get("enemy", "")))
			if d and not seen.has(d.id):
				seen[d.id] = true
				roster.append(d)
		for row in tl.specials.get("pool", []):
			var sd: EnemyDef = Registry.enemy(str(row.get("enemy", "")) if row is Dictionary else str(row))
			if sd and not seen.has(sd.id):
				seen[sd.id] = true
				specials.append(sd)
	var elites: Array = []
	var bosses: Array = []
	var retired: Array = []
	var dummies: Array = []
	var other: Array = []
	var rest: Array = Registry.enemies.values()
	rest.sort_custom(func(a, b): return a.id < b.id)
	for d: EnemyDef in rest:
		if seen.has(d.id):
			continue
		if d.brain == "dummy":
			dummies.append(d)
		elif d.archetype == "boss":
			bosses.append(d)
		elif d.archetype == "elite":
			elites.append(d)
		elif d.retired:
			retired.append(d)
		else:
			other.append(d)
	return [["The roster", roster], ["Specials", specials], ["Elites", elites], ["Bosses", bosses], ["Retired", retired],
		["Training dummies", dummies], ["Other", other]]


func spawn_enemy(def: EnemyDef) -> void:
	_last_enemy = def.id
	var n := _count
	var place := _place
	var mod_id := _elite_id
	var hold := _hold
	var act := func() -> void:
		_spawn_enemy_now(def, n, place, mod_id, hold)
	var label := def.display_name if def.archetype == "boss" else "%d %s" % [n, def.display_name]
	if def.variant_code != "":
		label += " " + def.variant_code
	_set_again(label, act)
	act.call()
	close()


## `n` of `def` near the hero at once, no elite modifier, not held (pass 66: the launch file's `spawn_enemy`, the Level
## Editor's "Test in game"; Game._launch_in_arena).
func spawn_enemy_n(def: EnemyDef, n: int) -> void:
	_spawn_enemy_now(def, maxi(n, 1), "near", "", false)


func _spawn_enemy_now(def: EnemyDef, n: int, place: String, mod_id: String, hold: bool) -> void:
	var em: EnemyManager = game.enemies
	em.register_type(def)
	if def.archetype == "boss":
		# a real boss: its bar, its attacks and, when it dies, its chest and its portal
		game.director._start_boss(def.id, _place_point("near", 0, 1) + _screen_up() * 7.0)
		return
	# an attacking dummy (pass 49) comes as the WORLD tab adds one: on a spot of its own, biting or spitting, up again
	# after it falls
	for kind in Game.ATTACKER_IDS.keys():
		if str(Game.ATTACKER_IDS[kind]) == def.id and game.has_method("add_attacker"):
			for k in range(n):
				game.add_attacker(str(kind))
			return
	var elite: EliteModDef = Registry.elites.get(mod_id) if mod_id != "" else null
	for k in range(n):
		var i: int = em.spawn(def.id, _place_point(place, k, n), elite, 1.0, 1.0, def.variant_code)
		if i < 0:
			continue
		if hold:
			em.speed[i] = 0.0
		# the director's Elite is a real one (pass 49: never the Elite or the Boss dummy)
		if def.archetype == "elite" and def.brain != "dummy":
			game.director.elite_index = i


func _screen_up() -> Vector3:
	var yaw: float = game.camera.current_yaw()
	return Vector3(-sin(yaw), 0, -cos(yaw))


## Where the k-th of n goes: a few metres up the screen from the hero, a ring round him, or out past the screen.
func _place_point(place: String, k: int, n: int) -> Vector3:
	var p: Vector3 = game.player.global_position
	var up := _screen_up()
	var side := Vector3(-up.z, 0, up.x)
	var at := p
	match place:
		"near":
			at = p + up * randf_range(4.0, 6.5) + side * randf_range(-3.0, 3.0)
		"ring":
			var a := TAU * float(k) / float(maxi(n, 1))
			at = p + Vector3(cos(a), 0, sin(a)) * 9.0
		_:
			var a2 := randf() * TAU
			at = p + Vector3(cos(a2), 0, sin(a2)) * randf_range(20.0, 26.0)
	if game.map and game.map.has_method("clamp_to_arena"):
		at = game.map.clamp_to_arena(at)
	return at


# ---------------------------------------------------------------- WAVES

func _waves_tab() -> void:
	var tl: WaveTimeline = Run.map.timeline
	_section("Arena clock")
	_note("Everything spawned scales as at this minute (stage, HP growth); the director runs from it.")
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	for step in [[-5.0, "-5 min"], [-1.0, "-1 min"]]:
		var s: float = step[0]
		var b := UiKit.button(str(step[1]), 20, false, 70)
		b.pressed.connect(func(): set_clock(_minute + s); _refresh())
		row.add_child(b)
	var cl := UiKit.label("%s · stage %d" % [_mmss(_minute * 60.0), _stage_at(_minute * 60.0) + 1], 26, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cl)
	for step2 in [[1.0, "+1 min"], [5.0, "+5 min"]]:
		var s2: float = step2[0]
		var b2 := UiKit.button(str(step2[1]), 20, false, 70)
		b2.pressed.connect(func(): set_clock(_minute + s2); _refresh())
		row.add_child(b2)
	_content.add_child(row)
	_section("A crowd from the roster")
	_note("Creatures the roster brings at the clock's minute, by its weights, in packs out past the screen.")
	_buttons([["30", func(): crowd(30)], ["100", func(): crowd(100)], ["200", func(): crowd(200)], ["Hard cap (%d)" % tl.hard_cap, func(): crowd(tl.hard_cap)]])
	var last: EnemyDef = Registry.enemy(_last_enemy)
	_section("A swarm of one kind")
	_note("The last creature picked on ENEMY: %s, in a ring closing on the hero." % (last.display_name if last else "?"))
	_buttons([["20", func(): swarm(20)], ["50", func(): swarm(50)], ["100", func(): swarm(100)], ["200", func(): swarm(200)]])
	_section("The director")
	var d: WaveDirector = game.director
	_note("%s. The real timeline from the clock: its spawns, its events (swarms, Elites, bosses), the specials' clock. Held, nothing comes." % ("Running" if d.running else "Held"))
	_buttons([["Run from the clock", func(): run_director(); close()], ["Hold", func(): hold_director(); _refresh()]])
	_section("Now")
	_buttons([["An Elite (random mod)", func(): _act("Elite", func(): game.director._spawn_elite("", "")); close()],
		["A special", func(): _act("special", _special_now); close()]])


func _mmss(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _stage_at(t: float) -> int:
	var tl: WaveTimeline = Run.map.timeline
	return clampi(int(t / maxf(tl.stage_length, 1.0)), 0, maxi(tl.stages - 1, 0))


## The arena clock: every spawn after this scales as at `minute`, and the HUD shows its stage.
func set_clock(minute: float) -> void:
	var tl: WaveTimeline = Run.map.timeline
	_minute = clampf(minute, 0.0, float(tl.stages) * tl.stage_length / 60.0)
	Run.elapsed = _minute * 60.0
	Run.stage = _stage_at(Run.elapsed)
	game.director._apply_mults()
	if game.hud:
		game.hud.refresh_stage()


func crowd(n: int) -> void:
	var t := _minute * 60.0
	_act("crowd of %d at %s" % [n, _mmss(t)], func() -> void: _crowd_now(n, t))
	close()


func _crowd_now(n: int, t: float) -> void:
	var tl: WaveTimeline = Run.map.timeline
	var rows: Array = tl.roster_at(t)
	if rows.is_empty():
		return
	var weights: Array = []
	var total := 0.0
	for r in rows:
		var w: float = game.director._roster_weight(r, t)
		weights.append(w)
		total += w
	# pass 54: presence keyframes can set a row to 0; when every open row is at 0 the crowd brings nothing, as in play
	if total <= 0.0:
		return
	var left := n
	var guard := 0
	while left > 0 and guard < 400:
		guard += 1
		var pick := randf() * total
		var row: Dictionary = rows[rows.size() - 1]
		for k in range(rows.size()):
			if float(weights[k]) <= 0.0:
				continue
			pick -= float(weights[k])
			if pick <= 0.0:
				row = rows[k]
				break
		var def: EnemyDef = Registry.enemy(str(row.get("enemy", "")))
		if def == null:
			continue
		var pack := mini(maxi(def.pack_size, 1), left)
		var at := _place_point("far", 0, 1)
		game.enemies.spawn_pack(def.id, at, pack)
		left -= pack


func swarm(n: int) -> void:
	var def: EnemyDef = Registry.enemy(_last_enemy)
	if def == null:
		return
	_act("swarm of %d %s" % [n, def.display_name], func() -> void:
		for k in range(n):
			var a := TAU * float(k) / float(n) + randf_range(-0.05, 0.05)
			var at: Vector3 = game.player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(14.0, 18.0)
			game.enemies.spawn(def.id, game.map.clamp_to_arena(at) if game.map.has_method("clamp_to_arena") else at))
	close()


## The real director from the arena clock: the next events after it, the specials' clock, its spawns.
func run_director() -> void:
	var d: WaveDirector = game.director
	set_clock(_minute)
	d.phase = WaveDirector.Phase.NORMAL
	d._event_i = 0
	while d._event_i < d.timeline.events.size() and float(d.timeline.events[d._event_i].get("t", 0.0)) < Run.elapsed:
		d._event_i += 1
	d.special_t = -1.0
	# a row's numbers are fixed at its first spawn (pass 58): a re-run from another minute or hero level starts them afresh
	d.forget_sources()
	d.running = true


func hold_director() -> void:
	game.director.running = false
	_minute = Run.elapsed / 60.0


func _toggle_waves() -> void:
	if game.director.running:
		hold_director()
	else:
		_minute = Run.elapsed / 60.0
		run_director()


func _special_now() -> void:
	var pool: Array = game.director.specials_pool()
	if pool.is_empty():
		pool = ["rocketeer"]
	var id: String = pool[randi() % pool.size()]
	game.enemies.register_type(Registry.enemy(id))
	game.enemies.spawn(id, _place_point("far", 0, 1))


# ---------------------------------------------------------------- ITEMS

## The ITEMS tab. Pass 49 (Garry: "the Mutations and evolutions are stacked option for Weapon Items, so it's easier to find
## them"): every base weapon is a row whose toggle (▶ 4 + evo) opens its stack under it, indented: its path mutations
## (element, volume, motion), its heroes' own ones, its evolution, then whatever of it is kept hidden (old mutations and
## evolutions), each row with the same − / level / + / MAX. The weapons out of play have their own section, shut until
## opened; the lines, the passives and the perks follow as before.
func _items_tab() -> void:
	_buttons([["Max all held", func(): _max_held(); _refresh()], ["Remove every item", func(): _remove_all(); _refresh()]])
	for sec in item_sections():
		var title: String = sec[0]
		var kind: String = sec[1]
		var open_now := bool(_open.get(title, false))
		var head := UiKit.button("%s %s (%d)" % ["-" if open_now else "+", title, (sec[2] as Array).size()], 26, false, 70)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.pressed.connect(func(): _open[title] = not bool(_open.get(title, false)); _refresh())
		_content.add_child(head)
		if not open_now:
			continue
		for def in sec[2]:
			if kind != "weapon":
				_content.add_child(_item_row(kind, def))
				continue
			var stack := weapon_stack(def)
			_content.add_child(_item_row(kind, def, "", false, stack))
			if bool(_open.get(STACK_KEY + def.id, false)):
				for entry in stack:
					_content.add_child(_item_row(str(entry[0]), entry[1], str(entry[2]), true))


## [title, kind, defs] for each section of the ITEMS tab, each list by name (pass 49): Weapons (the base weapons in play;
## each carries its stack, weapon_stack), Hidden weapons (the base weapons out of play, with theirs), Lines, Passives and
## Perks, and Other mutations / Other evolutions for any whose weapon is not in the game (none today), so nothing is lost.
## Every weapon, evolution, mutation, passive and perk is in exactly one section or one stack.
func item_sections() -> Array:
	var by_name := func(a, b): return a.display_name < b.display_name
	var weapons: Array = []
	var out_of_play: Array = []
	var stray_evos: Array = []
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution:
			if _evo_owner(w) == "":
				stray_evos.append(w)
		elif Registry.is_hidden(w):
			out_of_play.append(w)
		else:
			weapons.append(w)
	weapons.sort_custom(by_name)
	out_of_play.sort_custom(by_name)
	stray_evos.sort_custom(by_name)
	# the lines and the passive items apart (pass 47), both handed over as the passives they are
	var lines: Array = Registry.passives.values().filter(func(p: PassiveDef) -> bool: return W.is_line(p))
	lines.sort_custom(by_name)
	var passives: Array = Registry.passives.values().filter(func(p: PassiveDef) -> bool: return not W.is_line(p))
	passives.sort_custom(by_name)
	var perks: Array = Registry.perks.values()
	perks.sort_custom(func(a, b): return a.hero + a.display_name < b.hero + b.display_name)
	var stray_muts: Array = Registry.mutations.values().filter(func(m: MutationDef) -> bool: return _mutation_owner(m) == "")
	stray_muts.sort_custom(func(a, b): return a.weapon + a.display_name < b.weapon + b.display_name)
	var out: Array = [["Weapons", "weapon", weapons], ["Hidden weapons", "weapon", out_of_play], ["Lines", "passive", lines],
		["Passives", "passive", passives], ["Perks", "perk", perks]]
	if not stray_muts.is_empty():
		out.append(["Other mutations", "mutation", stray_muts])
	if not stray_evos.is_empty():
		out.append(["Other evolutions", "evolution", stray_evos])
	return out


## A base weapon's stack in the ITEMS tab (pass 49): [kind, def, tag] rows, `kind` as Run.debug_set_item takes it and
## `tag` the word before the name. Its path mutations by kind (element, volume, motion, then any other; MutationDef's
## `mutation_kind`) and name, its heroes' own mutations (the hero's name), its evolution (`evolves_into` first, then any
## other evolution of it), then everything of it kept hidden ("hidden mutation", "hidden evolution": golden_revolver_v47).
func weapon_stack(w: WeaponDef) -> Array:
	var path: Array = []
	var heroes: Array = []
	var evos: Array = []
	var gone: Array = []
	for m: MutationDef in Registry.mutations.values():
		if _mutation_owner(m) != w.id:
			continue
		if m.hidden or (m.is_hero() and _hero_hidden(m.hero)):
			# kept out of play, a hero out of play's own one too (pass 51: Mira's Blasting Cap, Buck's Drum Roll)
			gone.append(m)
		elif m.is_hero():
			heroes.append(m)
		else:
			path.append(m)
	for e: WeaponDef in Registry.weapons.values():
		if e.is_evolution and _evo_owner(e) == w.id:
			if e.hidden:
				gone.append(e)
			else:
				evos.append(e)
	path.sort_custom(func(a: MutationDef, b: MutationDef) -> bool:
		var ka := int(Registry.MUTATION_ORDER.get(a.mutation_kind, 9))
		var kb := int(Registry.MUTATION_ORDER.get(b.mutation_kind, 9))
		return ka < kb if ka != kb else a.display_name < b.display_name)
	heroes.sort_custom(func(a: MutationDef, b: MutationDef) -> bool: return _hero_word(a.hero) + a.display_name < _hero_word(b.hero) + b.display_name)
	evos.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool:
		if (a.id == w.evolves_into) != (b.id == w.evolves_into):
			return a.id == w.evolves_into
		return a.display_name < b.display_name)
	gone.sort_custom(func(a: ContentDef, b: ContentDef) -> bool:
		if (a is MutationDef) != (b is MutationDef):
			return a is MutationDef
		return a.display_name < b.display_name)
	var out: Array = []
	for m: MutationDef in path:
		out.append(["mutation", m, str(m.mutation_kind).capitalize()])
	for m: MutationDef in heroes:
		# a hero's own mutation is an extra, never one of the three the evolution needs (pass 51)
		out.append(["mutation", m, _hero_word(m.hero) + " · optional"])
	for e: WeaponDef in evos:
		out.append(["evolution", e, "Evolution"])
	for d: ContentDef in gone:
		if d is MutationDef and (d as MutationDef).is_hero() and not (d as MutationDef).hidden:
			var hc: CharacterDef = Registry.characters.get((d as MutationDef).hero)
			out.append(["mutation", d, "hidden · " + (hc.display_name if hc else (d as MutationDef).hero.capitalize())])
		else:
			out.append(["mutation", d, "hidden mutation"] if d is MutationDef else ["evolution", d, "hidden evolution"])
	return out


## Whether hero `hero_id` is out of play (hidden, or not in the game at all).
static func _hero_hidden(hero_id: String) -> bool:
	var c: CharacterDef = Registry.characters.get(hero_id)
	return c == null or c.hidden


## The base weapon a mutation belongs to (its `weapon`, or that evolution's own weapon), "" when it is none in the game.
static func _mutation_owner(m: MutationDef) -> String:
	var w: WeaponDef = Registry.weapon(m.weapon)
	if w == null:
		return ""
	return w.id if not w.is_evolution else _evo_owner(w)


## The base weapon an evolution stacks under: its `evolved_from`, else the base weapon that `evolves_into` it; "" for none.
static func _evo_owner(e: WeaponDef) -> String:
	var src: WeaponDef = Registry.weapon(e.evolved_from) if e.evolved_from != "" else null
	if src != null and not src.is_evolution:
		return src.id
	for w: WeaponDef in Registry.weapons.values():
		if not w.is_evolution and w.evolves_into == e.id:
			return w.id
	return ""


## A hero mutation's tag: its hero's name, "(hidden)" after a hero out of play.
static func _hero_word(hero_id: String) -> String:
	var c: CharacterDef = Registry.characters.get(hero_id)
	if c == null:
		return hero_id.capitalize()
	return c.display_name + (" (hidden)" if c.hidden else "")


## The EVO toggle's words for a stack: the path mutations its evolution needs, and whether there is an evolution (pass 51,
## Garry: "Land Mine has 4 mutations, this is wrong": the count took in a hero's own one, which is optional; hidden ones
## are inside and never counted).
static func stack_summary(stack: Array) -> String:
	var muts := 0
	var evo := false
	for entry in stack:
		if str(entry[2]).begins_with("hidden"):
			continue
		if entry[1] is MutationDef:
			if not (entry[1] as MutationDef).is_hero():
				muts += 1
		else:
			evo = true
	return "%d%s" % [muts, " + EVO" if evo else ""]


func item_level(kind: String, def: ContentDef) -> int:
	match kind:
		"weapon", "evolution":
			var w := Run.weapon_instance(def.id)
			return w.level if w else 0
		"passive":
			return int(Run.passives.get(def.id, 0))
		"perk":
			return 1 if Run.has_perk(def.id) else 0
		"mutation":
			return 1 if Run.mutations_held((def as MutationDef).weapon).has(def.id) else 0
	return 0


func item_max(kind: String, def: ContentDef) -> int:
	match kind:
		"weapon", "evolution":
			return (def as WeaponDef).max_level
		"passive":
			return (def as PassiveDef).max_level
	return 1


## One item's row: its icon, its name, INFO, a weapon's EVO, − / level / + / MAX (Run.debug_set_item). Pass 49: `tag`
## goes before the name in a weapon's stack ("Element · Toxic Peas"), `indent` sets the row in under its weapon, and a
## weapon row given its `stack` carries the toggle that opens it (▶ shut, ▼ open: Baloo has the arrows, the heading font
## does not). Pass 51 (Garry: "Each Item should have an extend view which I can press to see the description of the item
## (at that level using the most current stats). In case of Weapons there are 2 extends (1 for Evo and 1 for
## Description)"): INFO opens what a player reads about it under the row (item_texts: the very calls the level-up cards,
## the Build tab and the chest make, from the run as it stands), filled again whenever a level is set here. Named
## Item_<kind>_<id>, its toggles Info and Stack, the open text Info_<kind>_<id>, for the tests.
func _item_row(kind: String, def: ContentDef, tag: String = "", indent: bool = false, stack: Array = []) -> Control:
	var p := UiKit.panel(UiKit.BG if indent else UiKit.BG2, 16, UiKit.BG3 if indent else UiKit.LINE, 2)
	p.name = "Item_%s_%s" % [kind, def.id]
	var col := UiKit.vbox(8)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(col)
	var h := UiKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(h)
	var ic := UiKit.icon_view(def, 56 if indent else 64, UiKit.kind_of(def))
	h.add_child(ic)
	var name_s := def.display_name
	if tag != "":
		name_s = "%s · %s" % [tag, def.display_name]
	elif kind == "mutation":
		var wd: WeaponDef = Registry.weapon((def as MutationDef).weapon)
		name_s = "%s · %s" % [wd.display_name if wd else (def as MutationDef).weapon, def.display_name]
	elif kind == "perk":
		name_s = "%s · %s" % [(def as PerkDef).hero, def.display_name]
	var nl := UiKit.label(name_s, 22, UiKit.INK3 if tag.begins_with("hidden") else UiKit.INK)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
	# INFO: what the player reads about it
	var ikey := INFO_KEY + kind + ":" + def.id
	var info_open := bool(_open.get(ikey, false))
	var ib := UiKit.button(("▼ " if info_open else "▶ ") + "INFO", 20, info_open, 60)
	ib.name = "Info"
	ib.add_theme_font_override("font", UiKit.font(true))
	ib.custom_minimum_size = Vector2(118, 60)
	ib.size_flags_horizontal = Control.SIZE_SHRINK_END
	ib.pressed.connect(func(): _open[ikey] = not bool(_open.get(ikey, false)); _refresh())
	h.add_child(ib)
	if not stack.is_empty():
		# EVO: its mutations and evolution, stacked under it
		var key := STACK_KEY + def.id
		var open_now := bool(_open.get(key, false))
		var tg := UiKit.button(("▼ " if open_now else "▶ ") + stack_summary(stack), 20, open_now, 60)
		tg.name = "Stack"
		tg.add_theme_font_override("font", UiKit.font(true))
		tg.custom_minimum_size = Vector2(150, 60)
		tg.size_flags_horizontal = Control.SIZE_SHRINK_END
		tg.pressed.connect(func(): _open[key] = not bool(_open.get(key, false)); _refresh())
		h.add_child(tg)
	var mx := item_max(kind, def)
	var lv := UiKit.label("", 24, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	lv.custom_minimum_size = Vector2(96, 0)
	var show := func(): lv.text = "%d/%d" % [item_level(kind, def), mx]
	show.call()
	for step in [["-", -1], ["+", 1], ["MAX", 99]]:
		var d_step: int = step[1]
		var b := UiKit.button(str(step[0]), 22, d_step == 99, 60)
		b.custom_minimum_size = Vector2(84 if d_step != 99 else 96, 60)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.pressed.connect(func():
			var want: int = mx if d_step == 99 else item_level(kind, def) + d_step
			Run.debug_set_item(kind, def.id, want)
			show.call()
			_refill_info())
		if d_step == -1:
			h.add_child(b)
			h.add_child(lv)
		else:
			h.add_child(b)
	if info_open:
		var box := UiKit.vbox(4)
		box.name = "Info_%s_%s" % [kind, def.id]
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(box)
		var fill := func(): _fill_info(box, kind, def)
		fill.call()
		_info_fills.append(fill)
	if not indent:
		return p
	var m := MarginContainer.new()
	m.name = "Under_%s_%s" % [kind, def.id]
	m.add_theme_constant_override("margin_left", 56)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(p)
	return m


## Every open INFO filled again (pass 51): a level set here reaches more than its own row.
func _refill_info() -> void:
	for f in _info_fills:
		(f as Callable).call()


## The open INFO under an item's row (pass 51): each heading and text of item_texts, read again now.
func _fill_info(box: VBoxContainer, kind: String, def: ContentDef) -> void:
	if not is_instance_valid(box):
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var k := 0
	for pair in item_texts(kind, def):
		var hd := UiKit.label(str(pair[0]), 18, UiKit.ACCENT)
		hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(hd)
		var tx := UiKit.label(str(pair[1]), 21, UiKit.INK)
		tx.name = "InfoText%d" % k
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tx)
		k += 1


## What a player reads about an item (pass 51, Garry: "the exact same description that Players will see in the game, and
## it's always up to date"): [heading, text] pairs from the very calls the screens make, read from the run as it stands
## (the level held, the hero's stats now). A weapon held: its description as it fires now (WeaponInstance.description,
## the words its card and the chest use), the Build tab's stat rows and evolve note, and the next level's card; not held,
## the card that offers it (the chest's words for an evolution). A passive or a line held: the Build tab's words at its
## level and the next level's card (a maxed line, its evolution's card); not held, its card. A mutation, a perk: its card.
static func item_texts(kind: String, def: ContentDef) -> Array:
	var out: Array = []
	if def is WeaponDef:
		var w := def as WeaponDef
		var inst := Run.weapon_instance(w.id)
		if inst == null:
			out.append(["Not held · %s" % ("the chest's words" if w.is_evolution else "the card that offers it"), WItem.effect({"def": w, "level_from": 0, "level_to": 1})])
			return out
		out.append(["Lv %d of %d · as it fires now" % [inst.level, w.max_level], inst.description()])
		var cells: Array = []
		for sr in inst.stat_rows():
			cells.append("%s %s" % [str(sr["name"]), str(sr["value"])])
		if not cells.is_empty():
			out.append(["The Build tab", " · ".join(cells)])
		var note := PauseScreen.evolve_note(inst)
		if note != "":
			out.append(["Evolution", note])
		if inst.level < w.max_level:
			out.append(["Next level · the level-up card", WItem.card_text({"def": w, "level_from": inst.level, "level_to": inst.level + 1})])
		return out
	if def is PassiveDef:
		var pd := def as PassiveDef
		var lv := int(Run.passives.get(pd.id, 0))
		if lv <= 0:
			out.append(["Not held · the card that offers it", WItem.effect({"def": pd, "level_from": 0, "level_to": 1, "evolve": pd.is_evolved()})])
			return out
		out.append(["Lv %d of %d · the Build tab" % [lv, pd.max_level], PauseScreen.passive_now(pd, lv)])
		if lv < pd.max_level:
			out.append(["Next level · the level-up card", WItem.card_text({"def": pd, "level_from": lv, "level_to": lv + 1})])
		elif pd.evolves_into != "":
			var evo: PassiveDef = Registry.passive(pd.evolves_into)
			if evo:
				out.append(["Evolves into %s · its card" % evo.display_name, WItem.effect({"def": evo, "level_from": 0, "level_to": 1, "evolve": true})])
		return out
	out.append(["The card", WItem.effect({"def": def, "level_from": 0, "level_to": 1})])
	return out


func _max_held() -> void:
	for w in Run.weapons.duplicate():
		Run.debug_set_item("evolution" if w.def.is_evolution else "weapon", w.def.id, w.def.max_level)
	for pid in Run.passives.keys():
		var pd: PassiveDef = Registry.passive(pid)
		if pd:
			Run.debug_set_item("passive", pid, pd.max_level)


func _remove_all() -> void:
	Run.debug_clear_items()


# ---------------------------------------------------------------- HERO

func _hero_tab() -> void:
	_hero_switch()
	_hero_looks()
	_section("Level %d · %d / %d XP" % [Run.level, int(Run.xp), int(Run.xp_to_next())])
	_buttons([["+1", func(): _levels(1); _refresh()], ["+5", func(): _levels(5); _refresh()], ["+10", func(): _levels(10); _refresh()], ["To 30", func(): _levels(maxi(30 - Run.level, 0)); _refresh()]])
	# the hero's rule and what it comes to at this level (pass 61: the signature stat grows with every level)
	if Run.character:
		var now := TextGen.hero_trait_now(Run.character, Run.level)
		_note("%s: %s%s" % [Run.character.trait_name, TextGen.hero_trait(Run.character), (" Now " + now + ".") if now != "" else ""])
	_choice("Level-up cards", [[false, "Off"], [true, "On"]], bool(game.arena_cards), func(v): game.arena_cards = bool(v))
	_section("Life")
	_choice("God mode", [[false, "Off"], [true, "On"]], bool(game.player.god), func(v): game.player.god = bool(v))
	_buttons([["Heal full", func(): game.player.heal(game.player.max_hp)], ["Take a hit (10)", func(): close(); _hit(10.0)],
		["Go down", func(): close(); _go_down()]])
	var respawns = game.get("arena_respawns")
	_note("A death in the arena stands you up again at once on the start spot, whole, with nothing spent (%d so far). Go down is the real fall: Down! and Phoenix Feather." % int(respawns if respawns != null else 0))
	_section("Purse")
	_buttons([["+100 gold", func(): Run.add_gold(100, "debug")], ["+1000 gold", func(): Run.add_gold(1000, "debug")],
		["+5 rerolls, skips, banishes", func(): Run.rerolls_left += 5; Run.skips_left += 5; Run.banishes_left += 5]])


## The hero (pass 55, Garry: "an option in the hero tab of the Arena Debug menu which allows switching between heroes on
## the fly"): a tile for every hero in play, and with the player's debug mode on the ones out of play in a dimmer grid
## under them. A tap swaps that hero in where the one playing stands (Game.arena_swap_hero) and closes the sheet so he
## shows; the one playing is lit.
func _hero_switch() -> void:
	var now: CharacterDef = Run.character
	_section("Hero · %s" % (now.display_name if now else "-"))
	_note("Tap a hero to play as them here and now: their trait takes over, the items stay, the old hero's perks go (ITEMS hands perks out).")
	_grid(Registry.sorted_characters(), 3, func(c: CharacterDef) -> Control: return _hero_tile(c, false))
	if Settings.debug_mode:
		var out: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return c.hidden)
		if not out.is_empty():
			out.sort_custom(func(a, b): return a.id < b.id)
			_note("Out of play (debug mode)")
			_grid(out, 3, func(c: CharacterDef) -> Control: return _hero_tile(c, true))


## One hero's tile: his badge and name, "● playing" and a gold rim on the one playing, out-of-play ones dimmer. The badge
## is the one of his look (pass 68): the look he wears now for the one playing, else the one he is played in
## (Registry.played_look).
func _hero_tile(c: CharacterDef, dim: bool) -> Control:
	var playing := Run.character != null and Run.character.id == c.id
	var sub := "● playing" if playing else ("out of play" if c.hidden else ("locked" if not Registry.is_unlocked("character", c.id) else ""))
	var art: CharacterDef = c.variant_def(shown_look()) if playing else Registry.played_look(c)
	var t := _tile(art, "character", sub, func(): swap_hero(c.id))
	t.name = "Hero_" + c.id
	if playing:
		t.add_theme_stylebox_override("panel", UiKit.stylebox(UiKit.BG3, 18, UiKit.ACCENT, 4, true, false, false))
	if dim:
		t.modulate = Color(1, 1, 1, 0.62)
	return t


## A hero tile's tap (pass 55): that hero in place of the one playing, and the sheet closed so he shows.
func swap_hero(id: String) -> void:
	if game and game.has_method("arena_swap_hero"):
		game.arena_swap_hero(id)
	close()


## The hero's looks (pass 55, Garry: "the option to choose between different Art variants, like we do for the enemies"
## and "to choose which art should be used from that point onwards"): a chip per art variant, as the ENEMY tab has them.
## A tap draws him in that look at once for this visit (Player.show_look) and closes the sheet so it shows; ● marks the
## look he wears now, a green rim and RUNS the one runs start with. USE FROM NOW ON keeps the look he wears now
## (Save.set_hero_look: outlives the arena), and the line under it names the kept one.
func _hero_looks() -> void:
	var c: CharacterDef = Run.character
	if c == null:
		return
	var shelved_any := hero_has_shelved(c)
	var codes: Array = c.variant_codes(_show_shelved)
	if codes.is_empty():
		_note("%s has one look%s." % [c.display_name, (" (%s)" % c.variant) if c.variant != "" else ""])
		if shelved_any:
			_shelved_choice("ShelvedLooksHero")
		return
	_section("Looks · %s" % c.display_name)
	_note("Tap a look to see it on the hero now (this visit only). ● on the hero now, RUNS what every run starts with.")
	if shelved_any:
		_shelved_choice("ShelvedLooksHero")
	var shown := shown_look()
	var kept := kept_look(c)
	# pass 66: the chips wrap, so fifty looks fit the sheet
	var row := _chip_flow("HeroLooks")
	for code in codes:
		var k := str(code)
		var b := UiKit.button(look_chip_text(k, shown, kept), 20, k == shown, 64)
		b.name = "Look_" + k
		if k == kept:
			# the kept one wears a green rim whether or not it is lit
			var bg := UiKit.ACCENT if k == shown else UiKit.BG3
			b.add_theme_stylebox_override("normal", UiKit.stylebox(bg, 30, UiKit.GOOD, 4, true, true))
			b.add_theme_stylebox_override("hover", UiKit.stylebox(bg.lightened(0.08), 30, UiKit.GOOD, 4, true, true))
		if c.variant_shelved(k):
			b.modulate = Color(1, 1, 1, SHELVED_ALPHA)
		b.pressed.connect(func(): show_look(k))
		row.add_child(b)
	_content.add_child(row)
	_look_notes(codes, func(k: String) -> String: return c.variant_note(k), shown)
	var keep_row := UiKit.hbox(8)
	keep_row.name = "HeroLookKeep"
	keep_row.mouse_filter = Control.MOUSE_FILTER_PASS
	var keep := UiKit.button("USE %s FROM NOW ON" % shown, 22, false, 72)
	keep.name = "KeepLook"
	# nothing to keep while he wears the kept look
	keep.disabled = shown == kept
	keep.pressed.connect(keep_look)
	keep_row.add_child(keep)
	_content.add_child(keep_row)
	_note("Runs use %s." % kept)


## A look chip's words: the code, ● when he wears it now, RUNS when runs start with it.
static func look_chip_text(code: String, shown: String, kept: String) -> String:
	return code + (" ●" if code == shown else "") + (" · RUNS" if code == kept else "")


## The look the hero wears now in the arena (the Player's), else the one runs start with.
func shown_look() -> String:
	var p = game.player if game else null
	if p and p.has_method("look_code") and p.look_code() != "":
		return str(p.look_code())
	return kept_look(Run.character) if Run.character else ""


## The look every run starts the hero in: the one kept for him (Save.hero_look) when he still has it, else his JSON's.
static func kept_look(c: CharacterDef) -> String:
	return Registry.played_look(c).look_code() if c else ""


## A look chip's tap (pass 55): the hero drawn in that look at once, for this visit (Player.show_look), and the sheet
## closed so he shows.
func show_look(code: String) -> void:
	var p = game.player if game else null
	if p and p.has_method("show_look"):
		p.show_look(code)
	close()


## USE FROM NOW ON (pass 55): the look the hero wears now becomes the one every run, the title and the arena draw him
## in (Save.set_hero_look, which writes it past the arena's sandbox).
func keep_look() -> void:
	var c: CharacterDef = Run.character
	if c == null:
		return
	Save.set_hero_look(c.id, shown_look())
	_refresh()


func _levels(n: int) -> void:
	for k in range(n):
		Run.add_xp(Run.xp_to_next() - Run.xp + 0.01)


func _hit(amount: float) -> void:
	var p: Player = game.player
	var was := p.god
	p.god = false
	p.invuln = 0.0
	p.take_damage(amount, p.global_position + Vector3(1, 0, 0), {"by": "the arena", "kind": "melee", "fx": ["debug"]})
	p.god = was


## The real fall (pass 49: an arena death otherwise respawns him at once, Game.arena_respawn): Down! and Phoenix Feather.
func _go_down() -> void:
	var p: Player = game.player
	p.god = false
	p.invuln = 0.0
	p.shield_t = 0.0
	p.shield_pts = 0.0
	game.set("arena_real_down", true)
	p.take_damage(p.hp + 99999.0, p.global_position + Vector3(1, 0, 0), {"by": "the arena", "kind": "melee", "fx": ["debug"]})
	if not p.dead:
		# an Evade took it: the next death in the arena is the arena's again
		game.set("arena_real_down", false)


# ---------------------------------------------------------------- DROPS

func _drops_tab() -> void:
	_section("Power-ups on the sand by the hero")
	var defs: Array = Registry.pickups.values()
	defs.sort_custom(func(a, b): return a.display_name < b.display_name)
	_grid(defs, 3, func(def: PickupDef) -> Control:
		return _tile(def, "pickup", "", func(): _act(def.display_name, func() -> void: _drop_pickup(def)); close()))
	_section("Chests")
	_buttons([["A chest", func(): _act("chest", func() -> void: game.pickups.spawn_chest(_drop_point(3.0))); close()],
		["A boss chest", func(): _act("boss chest", func() -> void: game.pickups.spawn_chest(_drop_point(3.0), true)); close()]])
	_section("Showers")
	_buttons([["40 gems", func(): _act("gems", func() -> void: _shower(PickupManager.KIND_GEM_M, 40, 5.0)); close()],
		["40 coins", func(): _act("coins", func() -> void: _shower(PickupManager.KIND_COIN, 40, 1.0)); close()],
		["Pull it all in", func(): game.pickups.vacuum_all(true, true); close()]])


func _drop_point(dist: float) -> Vector3:
	var up := _screen_up()
	var side := Vector3(-up.z, 0, up.x)
	var at: Vector3 = game.player.global_position + up * dist + side * randf_range(-1.5, 1.5)
	return Vector3(at.x, game.map.height_at(at.x, at.z) if game.map else at.y, at.z)


func _drop_pickup(def: PickupDef) -> void:
	game.pickups.spawn_special(def, _drop_point(3.0))


func _shower(kind: int, n: int, value: float) -> void:
	for k in range(n):
		var a := randf() * TAU
		var at: Vector3 = game.player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 7.0)
		game.pickups.spawn(kind, at, value)


# ---------------------------------------------------------------- WORLD

func _world_tab() -> void:
	_choice("Game speed", [[0.25, "0.25x"], [0.5, "0.5x"], [1.0, "1x"], [2.0, "2x"]], _speed, func(v):
		_speed = float(v)
		Engine.time_scale = _speed)
	_choice("Freeze crowd", [[false, "No"], [true, "Yes"]], _frozen, func(v):
		_frozen = bool(v)
		game.enemies.process_mode = Node.PROCESS_MODE_DISABLED if _frozen else Node.PROCESS_MODE_INHERIT)
	_choice("Camera zoom", [[0.0, "Auto"], [1.0, "1x"], [1.5, "1.5x"], [2.0, "2x"], [2.6, "2.6x"]], _zoom, func(v):
		_zoom = float(v)
		game.camera.zoom_override = _zoom)
	_choice("Stats overlay", [[false, "Off"], [true, "On"]], bool(game.debug_panel.visible), func(v): game.debug_panel.visible = bool(v))
	# the training dummies (pass 48): the developer menu's two settings, and laying the field out again with them; pass 49
	# (Garry's arena list): the field's patrol, the attacking dummies, the Elite dummy and the Boss dummy. Each row is named
	# for the touch audit.
	_section("Training dummies")
	_choice("Health", _hp_options(Settings.DUMMY_HP_STEPS), Settings.dummy_hp, func(v): Settings.set_value("dummy_hp", int(v))).name = "DummyHealth"
	var n_opts: Array = []
	for n in Settings.DUMMY_COUNT_STEPS:
		n_opts.append([int(n), str(n)])
	_choice("Count", n_opts, Settings.dummy_count, func(v): Settings.set_value("dummy_count", int(v))).name = "DummyCount"
	_choice("Patrol", [[false, "Off"], [true, "On"]], Settings.dummy_patrol, func(v):
		Settings.set_value("dummy_patrol", bool(v))
		_apply_dummies()).name = "DummyPatrol"
	_buttons([["RESET DUMMIES", reset_dummies]], 80, 24)
	_note("RESET DUMMIES lays the field out again with this health and count, north of the spawn, with the Elite dummy behind it on the left and the Boss dummy behind it on the right. Patrol walks every field dummy left and right round its spot; it and everything below reach the dummies at once.")
	_section("Attacking dummies")
	_choice("Health", _hp_options(Settings.ATTACKER_HP_STEPS), Settings.attacker_dummy_hp, func(v):
		Settings.set_value("attacker_dummy_hp", int(v))
		_apply_dummies()).name = "AttackerHealth"
	_buttons([["+ MELEE DUMMY", func(): add_attacker("melee")], ["+ RANGED DUMMY", func(): add_attacker("ranged")]], 80, 24).name = "AttackerAdd"
	_buttons([["REMOVE ATTACKERS", remove_attackers]], 72, 22).name = "AttackerRemove"
	_note(_attackers_note())
	for spec in [["elite", "Elite dummy (crown)", Settings.ELITE_DUMMY_HP_STEPS, "Elite"], ["boss", "Boss dummy (skull)", Settings.BOSS_DUMMY_HP_STEPS, "Boss"]]:
		var role: String = spec[0]
		_section(str(spec[1]))
		_choice("Health", _hp_options(spec[2]), int(Settings.get(role + "_dummy_hp")), func(v):
			Settings.set_value(role + "_dummy_hp", int(v))
			_apply_dummies()).name = str(spec[3]) + "DummyHealth"
		_choice("Behaviour", _mode_options(), str(Settings.get(role + "_dummy_mode")), func(v):
			Settings.set_value(role + "_dummy_mode", str(v))
			_apply_dummies()).name = str(spec[3]) + "DummyMode"
	_note("Both stand apart from the field. Patrol walks left and right; Melee chases you within %d m of its spot and bites (the Elite for %d, the Boss for %d); Ranged spits like the Spit Cactus (for %d and %d). Both stand up again 5 s after they fall and pay nothing." % [
		int(EnemyManager.DUMMY_CHASE), _dummy_hit("training_dummy_elite", false), _dummy_hit("training_dummy_boss", false),
		_dummy_hit("training_dummy_elite", true), _dummy_hit("training_dummy_boss", true)])
	_section("The field")
	_buttons([["Kill all (with drops)", func(): game.enemies.kill_all(true); close()], ["Remove all", func(): _clear_field(); close()],
		["Clear shots", func(): game.projectiles.clear_all()]])
	_section("Leave")
	_note("Back to the title. Nothing done in the arena is kept.")
	_buttons([["Leave the arena", _ask_leave]], 90, 28)


## The training dummies laid out again (pass 48): Settings.dummy_count of them at Settings.dummy_hp (Game.arena_dummies),
## with the Elite and the Boss dummy beside them (pass 49). The attackers stay.
func reset_dummies() -> void:
	if game and game.has_method("arena_dummies"):
		game.arena_dummies(Settings.dummy_count, Settings.dummy_hp)
		_status_t = 0.0


## One more attacking dummy by the hero (pass 49, Game.add_attacker: "melee" or "ranged"); the tab is drawn again with
## the count.
func add_attacker(kind: String) -> void:
	if game and game.has_method("add_attacker"):
		game.add_attacker(kind)
		_status_t = 0.0
	_refresh()


## Every attacking dummy off the field (pass 49, Game.remove_attackers); the field, the Elite and the Boss stay.
func remove_attackers() -> void:
	if game and game.has_method("remove_attackers"):
		game.remove_attackers()
		_status_t = 0.0
	_refresh()


## A dummy setting changed (pass 49): it reaches the dummies standing at once (Game.apply_dummy_settings).
func _apply_dummies() -> void:
	if game and game.has_method("apply_dummy_settings"):
		game.apply_dummy_settings()


## Health choices for a dummy setting's steps: Undying for 0, the rest with their thousands marked.
static func _hp_options(steps: Array) -> Array:
	var out: Array = []
	for hp in steps:
		out.append([int(hp), "Undying" if int(hp) <= 0 else Settings.thousands(int(hp))])
	return out


## The Elite's and the Boss's behaviours (pass 49, Settings.DUMMY_MODES).
static func _mode_options() -> Array:
	var out: Array = []
	for m in Settings.DUMMY_MODES:
		out.append([str(m), str(m).capitalize()])
	return out


func _attackers_note() -> String:
	var melee := 0
	var ranged := 0
	if game and game.has_method("attackers_standing"):
		melee = int(game.attackers_standing("melee"))
		ranged = int(game.attackers_standing("ranged"))
	return ("On the field: %d melee, %d ranged. Each comes on a spot of its own by you; melee chases you within %d m of its spot and bites for %d, ranged spits like the Spit Cactus for %d. The first one turns god mode off (HERO turns it on again); a death here respawns you at once." % [
		melee, ranged, int(EnemyManager.DUMMY_CHASE), _dummy_hit("training_dummy_melee", false), _dummy_hit("training_dummy_ranged", true)])


## What a dummy's touch (or, `spit`, its spit) takes, as its JSON says (Game._dress_dummy hands the same numbers over).
static func _dummy_hit(id: String, spit: bool) -> int:
	var d: EnemyDef = Registry.enemy(id)
	if d == null:
		return 0
	return int(round(float(d.ranged.get("damage", d.damage)) if spit else d.damage))


## The question before the title (pass 45): nothing done in the arena is kept either way.
func _ask_leave() -> void:
	WConfirm.open(self, "Leave the arena?", "Back to the title. Nothing done here is kept.", "Leave", "Stay", func():
		close()
		game.leave_arena())


# ---------------------------------------------------------------- the quick column's actions

func _clear_field() -> void:
	game.enemies.kill_all(false)
	game.projectiles.clear_all()


func _act(name: String, act: Callable) -> void:
	_set_again(name, act)
	act.call()


func _set_again(name: String, act: Callable) -> void:
	_again = act
	_again_name = name


func _do_again() -> void:
	if _again.is_valid():
		_again.call()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if game == null:
		return
	place_column(game.get("hud"))
	_status_t -= delta
	if _status_t <= 0.0:
		_status_t = 0.25
		var d: WaveDirector = game.director
		_status.text = "%s · stage %d\n%d alive · waves %s\nagain: %s" % [_mmss(Run.elapsed), Run.stage + 1, game.enemies.count_alive,
			"on" if d.running else "held", _again_name if _again_name != "" else "-"]
		_waves_btn.text = "HOLD" if d.running else "WAVES"
	if _sheet.visible and _touch:
		_touch.process()


func _input(event: InputEvent) -> void:
	if _sheet.visible and _touch and not WConfirm.is_open(self):
		_touch.input(event)
