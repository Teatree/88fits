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
##   ITEMS  every weapon, evolution, passive, line, perk and mutation, each with − / + / max, applied at once and past
##          the caps the cards keep.
##   HERO   levels (+1, +5, +10, to 30), level-up cards on or off, god mode, heal, a hit, going down, gold, rerolls.
##   DROPS  every power-up on the sand by the hero, a chest, a boss chest, a shower of gems or coins.
##   WORLD  game speed, freezing the crowd, killing or removing everything, the camera's zoom, the stats overlay, leaving.
## Nothing done here reaches the save (Game.leave_arena puts the save back as it was when the arena opened).
class_name ArenaPanel
extends Control

const TABS := [["enemy", "ENEMY"], ["waves", "WAVES"], ["items", "ITEMS"], ["hero", "HERO"], ["drops", "DROPS"], ["world", "WORLD"]]
const SHEET_H := 1180

var game: Node
var _tab := "enemy"
var _sheet: PanelContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _tab_buttons: Dictionary = {}
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
# WAVES
var _minute := 0.0
# ITEMS: which sections are open
var _open: Dictionary = {"Weapons": true}
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
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -196
	col.offset_right = -16
	col.offset_top = 380
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
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
	for c in _content.get_children():
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


func _buttons(pairs: Array, h := 72, size := 22) -> void:
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	for p in pairs:
		var b := UiKit.button(str(p[0]), size, false, h)
		var cb: Callable = p[1]
		b.pressed.connect(cb)
		row.add_child(b)
	_content.add_child(row)


## A label and a row of choices, the current one lit; `pick` gets the chosen value and the tab is redrawn.
func _choice(title: String, options: Array, current, pick: Callable) -> void:
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
## name when picking one.
func _variants_section() -> void:
	var defs: Array = Registry.enemies.values().filter(func(d: EnemyDef) -> bool: return not d.variant_codes().is_empty())
	if defs.is_empty():
		return
	defs.sort_custom(func(a, b): return a.id < b.id)
	_section("Art variants")
	_note("Tap a code to spawn How many with that art. ● is the one in the game. Tell Claude the code you like.")
	for d: EnemyDef in defs:
		var row := UiKit.hbox(8)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var l := UiKit.label(d.display_name, 22, UiKit.INK2)
		l.custom_minimum_size = Vector2(150, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		for code in d.variant_codes():
			var c := str(code)
			var b := UiKit.button(c + (" ●" if c == d.variant else ""), 20, c == d.variant, 64)
			b.pressed.connect(func(): spawn_enemy(d.variant_def(c)))
			row.add_child(b)
		_content.add_child(row)
		for code in d.variant_codes():
			var note := str((d.variants[code] as Dictionary).get("note", ""))
			if note != "":
				_note("%s  %s" % [str(code), note])


func _enemy_sub(def: EnemyDef) -> String:
	var bits: Array = ["%s hp" % str(snappedf(def.hp, 0.1))]
	if def.damage_reduction > 0.0:
		bits.append("takes %d%% less" % int(round(def.damage_reduction * 100.0)))
	if def.pack_size > 1:
		bits.append("packs of %d" % def.pack_size)
	return " · ".join(bits)


## Every creature in the game, grouped: the roster in arrival order, the specials, the Elites, the bosses, the retired,
## and any other (the ones only an attack brings, like the centipede's young).
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
	var other: Array = []
	var rest: Array = Registry.enemies.values()
	rest.sort_custom(func(a, b): return a.id < b.id)
	for d: EnemyDef in rest:
		if seen.has(d.id):
			continue
		if d.archetype == "boss":
			bosses.append(d)
		elif d.archetype == "elite":
			elites.append(d)
		elif d.retired:
			retired.append(d)
		else:
			other.append(d)
	return [["The roster", roster], ["Specials", specials], ["Elites", elites], ["Bosses", bosses], ["Retired", retired], ["Other", other]]


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


func _spawn_enemy_now(def: EnemyDef, n: int, place: String, mod_id: String, hold: bool) -> void:
	var em: EnemyManager = game.enemies
	em.register_type(def)
	if def.archetype == "boss":
		# a real boss: its bar, its attacks and, when it dies, its chest and its portal
		game.director._start_boss(def.id, _place_point("near", 0, 1) + _screen_up() * 7.0)
		return
	var elite: EliteModDef = Registry.elites.get(mod_id) if mod_id != "" else null
	for k in range(n):
		var i: int = em.spawn(def.id, _place_point(place, k, n), elite, 1.0, 1.0, def.variant_code)
		if i < 0:
			continue
		if hold:
			em.speed[i] = 0.0
		if def.archetype == "elite":
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
	var left := n
	var guard := 0
	while left > 0 and guard < 400:
		guard += 1
		var pick := randf() * total
		var row: Dictionary = rows[rows.size() - 1]
		for k in range(rows.size()):
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

func _items_tab() -> void:
	_buttons([["Max all held", func(): _max_held(); _refresh()], ["Remove every item", func(): _remove_all(); _refresh()]])
	for sec in item_sections():
		var title: String = sec[0]
		var open_now := bool(_open.get(title, false))
		var head := UiKit.button("%s %s (%d)" % ["-" if open_now else "+", title, (sec[2] as Array).size()], 26, false, 70)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.pressed.connect(func(): _open[title] = not bool(_open.get(title, false)); _refresh())
		_content.add_child(head)
		if not open_now:
			continue
		for def in sec[2]:
			_content.add_child(_item_row(str(sec[1]), def))


## [title, kind, defs] for every kind of item, each list sorted by name (mutations by weapon).
func item_sections() -> Array:
	var weapons: Array = []
	var evos: Array = []
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution:
			evos.append(w)
		else:
			weapons.append(w)
	var by_name := func(a, b): return a.display_name < b.display_name
	weapons.sort_custom(by_name)
	evos.sort_custom(by_name)
	var passives: Array = Registry.passives.values()
	passives.sort_custom(by_name)
	var lines: Array = Registry.lines.values()
	lines.sort_custom(by_name)
	var perks: Array = Registry.perks.values()
	perks.sort_custom(func(a, b): return a.hero + a.display_name < b.hero + b.display_name)
	var muts: Array = Registry.mutations.values()
	muts.sort_custom(func(a, b): return a.weapon + a.display_name < b.weapon + b.display_name)
	return [["Weapons", "weapon", weapons], ["Evolutions", "evolution", evos], ["Passives", "passive", passives], ["Lines", "line", lines],
		["Perks", "perk", perks], ["Mutations", "mutation", muts]]


func item_level(kind: String, def: ContentDef) -> int:
	match kind:
		"weapon", "evolution":
			var w := Run.weapon_instance(def.id)
			return w.level if w else 0
		"passive":
			return int(Run.passives.get(def.id, 0))
		"line":
			return Run.line_rank(def.id)
		"perk":
			return 1 if Run.has_perk(def.id) else 0
		"mutation":
			return 1 if Run.mutations_held((def as MutationDef).weapon).has(def.id) else 0
	return 0


func item_max(kind: String, def: ContentDef) -> int:
	match kind:
		"weapon", "evolution":
			return (def as WeaponDef).max_level
		"passive", "line":
			return (def as PassiveDef).max_level
	return 1


func _item_row(kind: String, def: ContentDef) -> Control:
	var p := UiKit.panel(UiKit.BG2, 16, UiKit.LINE, 2)
	var h := UiKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(h)
	var ic := UiKit.icon_view(def, 64, UiKit.kind_of(def))
	h.add_child(ic)
	var name_s := def.display_name
	if kind == "mutation":
		var wd: WeaponDef = Registry.weapon((def as MutationDef).weapon)
		name_s = "%s · %s" % [wd.display_name if wd else (def as MutationDef).weapon, def.display_name]
	elif kind == "perk":
		name_s = "%s · %s" % [(def as PerkDef).hero, def.display_name]
	var nl := UiKit.label(name_s, 22, UiKit.INK)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nl)
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
			show.call())
		if d_step == -1:
			h.add_child(b)
			h.add_child(lv)
		else:
			h.add_child(b)
	return p


func _max_held() -> void:
	for w in Run.weapons.duplicate():
		Run.debug_set_item("evolution" if w.def.is_evolution else "weapon", w.def.id, w.def.max_level)
	for pid in Run.passives.keys():
		var pd: PassiveDef = Registry.passive(pid)
		if pd:
			Run.debug_set_item("passive", pid, pd.max_level)
	for lid in Run.lines.keys():
		var ld: LineDef = Registry.line(lid)
		if ld:
			Run.debug_set_item("line", lid, ld.max_level)


func _remove_all() -> void:
	Run.debug_clear_items()


# ---------------------------------------------------------------- HERO

func _hero_tab() -> void:
	_section("Level %d · %d / %d XP" % [Run.level, int(Run.xp), int(Run.xp_to_next())])
	_buttons([["+1", func(): _levels(1); _refresh()], ["+5", func(): _levels(5); _refresh()], ["+10", func(): _levels(10); _refresh()], ["To 30", func(): _levels(maxi(30 - Run.level, 0)); _refresh()]])
	_choice("Level-up cards", [[false, "Off"], [true, "On"]], bool(game.arena_cards), func(v): game.arena_cards = bool(v))
	_section("Life")
	_choice("God mode", [[false, "Off"], [true, "On"]], bool(game.player.god), func(v): game.player.god = bool(v))
	_buttons([["Heal full", func(): game.player.heal(game.player.max_hp)], ["Take a hit (10)", func(): close(); _hit(10.0)],
		["Go down", func(): close(); _go_down()]])
	_section("Purse")
	_buttons([["+100 gold", func(): Run.add_gold(100)], ["+1000 gold", func(): Run.add_gold(1000)],
		["+5 rerolls, banishes", func(): Run.rerolls_left += 5; Run.banishes_left += 5]])


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


func _go_down() -> void:
	var p: Player = game.player
	p.god = false
	p.invuln = 0.0
	p.shield_t = 0.0
	p.shield_pts = 0.0
	p.take_damage(p.hp + 99999.0, p.global_position + Vector3(1, 0, 0), {"by": "the arena", "kind": "melee", "fx": ["debug"]})


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
	_section("The field")
	_buttons([["Kill all (with drops)", func(): game.enemies.kill_all(true); close()], ["Remove all", func(): _clear_field(); close()],
		["Clear shots", func(): game.projectiles.clear_all()]])
	_section("Leave")
	_note("Back to the title. Nothing done in the arena is kept.")
	_buttons([["Leave the arena", func(): close(); game.leave_arena()]], 90, 28)


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
	if _sheet.visible and _touch:
		_touch.input(event)
