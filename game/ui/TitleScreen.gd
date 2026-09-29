## Title (Wanted 01/02), with play setup merged in: the gold plate, "★ WANTED ★ / 88fits / DRAG · DODGE · SURVIVE", the
## hero full-body (art/ui/wanted/hero_<id>.png, a striped slot until painted) between two arrow squares, swipe or tap
## to change, a dot per hero under it, the hero plaque (name, italic line, the trait's numbers and the favourite weapon's
## plate), PLAY, the map and its best run in one line (a tap changes the map when there are several). Heroes still to
## unlock ride the same carousel after the open ones: a dark silhouette with a padlock, a half-aged dot, what unlocks
## them and how far along that is, and PLAY reading LOCKED. (The developer menu can add the hidden heroes, locked, to
## preview the look.) The map line (a tap changes the map when there are
## several), and The Mirror · Collection · Settings. No version label and no debug entry: both live in the developer
## menu (Settings, hold the version label for 2 s). The top block hangs from the top edge, the plaque and the buttons
## from the bottom; the hero keeps the middle.
extends Control

## The cut-out box: 520 × 700 inside a 4 px dashed border, 24 px under the label (the mock's box is content-box).
const HERO_SIZE := Vector2(528, 732)
## The hero row's top on a 1920 screen; a taller screen moves it down by half the extra height.
const HERO_TOP := 560.0
## Where the plaque, PLAY and the map line sit, measured up from the bottom edge (1330, 1560, 1720 on a 1920 screen).
const PLAQUE_UP := 590.0
const PLAY_UP := 360.0
## The plaque's foot sits this far above PLAY (the mock's 1497 -> 1560); the plaque grows upwards from there.
const PLAQUE_GAP := 63.0
const MAP_UP := 200.0
## A finger that travels this far sideways over the hero changes it.
const SWIPE := 90.0
## The trait's numbers under short names (the rest fall back to TextGen's stat names).
const SHORT := {"max_hp": "HP", "armor": "ARMOUR", "move_speed": "SPEED", "magnet": "REACH", "might": "MIGHT",
	"area": "AREA", "cooldown": "COOLDOWN", "luck": "LUCK", "greed": "GREED", "regen": "REGEN", "revives": "REVIVES",
	"projectile_speed": "SHOT SPEED", "xp_gain": "XP", "crit_chance": "CRIT", "amount": "PROJECTILES"}

var _heroes: Array = []
var _index := 0
var _maps: Array = []
var _map_id := ""
var _hero_row: Control
var _art_host: Control
var _art: WPlaceholder
var _dots: Control
var _plaque: PanelContainer
var _name: WText
var _line: WText
var _stats: HBoxContainer
var _play: WButton
var _map_tap: WTap
var _map_line: WText
var _lower: Array = []
var _swipe_id := -2   # -2 none, -1 the mouse, else a finger index
var _swipe_from := Vector2.ZERO


## Back on the title leaves the game, as it always did (quit_on_go_back is off so a run can ignore the gesture).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ScreenBase.add_backdrop(self)
	add_child(_wash())
	_heroes = _roster()
	var last := Registry.playable_character(str(Save.data.get("last_character", "astro")))
	_index = maxi(_heroes.find(last), 0)
	_maps = Registry.sorted_maps().filter(func(m: MapDef) -> bool: return Registry.is_unlocked("map", m.id))
	_map_id = str(Save.data.get("last_map", ""))
	if _maps.filter(func(m: MapDef) -> bool: return m.id == _map_id).is_empty():
		_map_id = _maps[0].id if not _maps.is_empty() else "red_canyon"
	# the gold plate, top-left
	var gold := WMenuHeader.gold_plate(Save.gold(), 44, 40.0, 5, 4)
	gold.position = Vector2(36, 44)
	add_child(gold)
	# the name stack
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stack.offset_top = 150
	add_child(stack)
	var wanted := WStarLine.make("Wanted", 26, W.INK, 0.4)
	wanted.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(wanted)
	var logo := W.slab_text("88fits", 210, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 199.5)
	logo.shadow = 10
	logo.shadow_color = W.BRASS
	stack.add_child(logo)
	var tag := W.label("Drag · Dodge · Survive", 30, W.INK, 0.3)
	tag.align = HORIZONTAL_ALIGNMENT_CENTER
	tag.custom_minimum_size.y = 6.0 + 36.0
	tag.valign = VERTICAL_ALIGNMENT_BOTTOM
	stack.add_child(tag)
	_build_hero_row()
	_build_lower()
	_show_hero(0)
	get_viewport().size_changed.connect(_place)
	_place()
	_enter()
	Audio.play_music(["mu_title"], 1)


## The title wash: warm at the top, clear through the middle where the hero stands, paper again at the foot.
func _wash() -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.78, 1.0])
	g.colors = PackedColorArray([Color8(233, 201, 160, 242), Color8(233, 201, 160, 102), Color8(243, 230, 200, 0),
		Color8(243, 230, 200, 178), Color8(243, 230, 200, 235)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 256
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_hero_row() -> void:
	_hero_row = Control.new()
	_hero_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_row)
	_art_host = Control.new()
	_art_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_host.size = HERO_SIZE
	_hero_row.add_child(_art_host)
	for side in [-1, 1]:
		var a := WTap.new()
		var b := W.box(W.PAPER, 4, 5).pad(4, 4, 4, 10)
		a.box = b
		var t := W.slab_text("‹" if side < 0 else "›", 48, W.INK, HORIZONTAL_ALIGNMENT_CENTER, 48.0)
		t.custom_minimum_size = Vector2(72, 72)
		t.valign = VERTICAL_ALIGNMENT_CENTER
		a.add_child(t)
		a.size = Vector2(80, 86)
		a.set_meta("side", side)
		a.pressed.connect(func(): _step(side))
		a.name = "Prev" if side < 0 else "Next"
		_hero_row.add_child(a)
	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	add_child(_dots)


## The plaque, PLAY, the map line and the three menu buttons.
func _build_lower() -> void:
	_plaque = PanelContainer.new()
	_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plaque.add_theme_stylebox_override("panel", W.box(W.PAPER, 5, 8).pad(35, 27, 35, 27))
	add_child(_plaque)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 14)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plaque.add_child(pv)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	_name = W.slab_text("", 56, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 56.0)
	left.add_child(_name)
	_line = W.serif_text("", 24, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	left.add_child(_line)
	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", 14)
	_stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_stats)
	_play = WButton.make(["PLAY"], 84, WButton.PRIMARY, 6, 10, 22.0, 22.0, 84.0)
	_play.pressed.connect(_on_play)
	add_child(_play)
	_map_tap = WTap.new()
	var clear := W.box(Color(0, 0, 0, 0), 0, 0)
	_map_tap.box = clear
	_map_tap.box_down = clear
	_map_line = W.serif_text("", 26, W.INK_SOFT, 400, false, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_map_tap.add_child(_map_line)
	_map_tap.pressed.connect(_next_map)
	add_child(_map_tap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 60
	row.offset_right = -60
	row.offset_bottom = -60
	row.offset_top = -60 - 91
	add_child(row)
	for pair in [["The Mirror", "res://ui/HomesteadScreen.tscn"], ["Collection", "res://ui/CollectionScreen.tscn"], ["Settings", "res://ui/SettingsScreen.tscn"]]:
		var b := WButton.make([pair[0]], 30, WButton.SECONDARY, 5, 6, 20.0, 0.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path: String = pair[1]
		b.pressed.connect(func(): UiFx.go(get_tree(), path))
		row.add_child(b)
	_lower = [_plaque, _play, _map_tap, row]
	_refresh_map()


## Everything that depends on the screen's height: the lower block hangs from the bottom edge, the hero row takes the
## middle and shrinks when a short screen has no room for it.
func _place() -> void:
	var vp := get_viewport_rect().size
	_plaque.size = Vector2(vp.x - 120, 0)
	var plaque_top := vp.y - PLAY_UP - PLAQUE_GAP - _plaque.get_combined_minimum_size().y
	_plaque.position = Vector2(60, plaque_top)
	_play.position = Vector2(60, vp.y - PLAY_UP)
	_play.size = Vector2(vp.x - 120, 0)
	_map_tap.position = Vector2(0, vp.y - MAP_UP)
	_map_tap.size = Vector2(vp.x, 0)
	var top := HERO_TOP + (vp.y - 1920.0) * 0.5
	var room := plaque_top - 38.0 - 440.0
	var k := clampf(room / HERO_SIZE.y, 0.5, 1.0)
	if top + HERO_SIZE.y * k > plaque_top - 38.0:
		top = plaque_top - 38.0 - HERO_SIZE.y * k
	_hero_row.position = Vector2(0, top)
	_hero_row.size = Vector2(vp.x, HERO_SIZE.y * k)
	var art_w := HERO_SIZE.x * k
	_art_host.position = Vector2((vp.x - art_w) * 0.5, 0)
	_art_host.scale = Vector2(k, k)
	for a in _hero_row.get_children():
		if a is WTap:
			var side: int = a.get_meta("side")
			var x := (vp.x - art_w) * 0.5 - 40.0 - 80.0 if side < 0 else (vp.x + art_w) * 0.5 + 40.0
			a.position = Vector2(x, (HERO_SIZE.y * k - 86.0) * 0.5)
	_dots.position = Vector2(0, top + HERO_SIZE.y * k - 12.0)
	_dots.size = Vector2(vp.x, 26)


## Every hero the carousel shows: the open ones first, then those still to unlock. With the developer's preview on,
## the hidden heroes join the locked ones.
func _roster() -> Array:
	var open: Array = []
	var shut: Array = []
	for c: CharacterDef in Registry.sorted_characters():
		if Registry.is_unlocked("character", c.id):
			open.append(c)
		else:
			shut.append(c)
	if bool(Settings.get("preview_locked_heroes")):
		var hidden: Array = Registry.characters.values().filter(func(c: CharacterDef) -> bool: return c.hidden)
		hidden.sort_custom(func(a, b): return a.id < b.id)
		shut.append_array(hidden)
	return open + shut


func _is_locked(c: CharacterDef) -> bool:
	return c.hidden or not Registry.is_unlocked("character", c.id)


## The hero at `_index`: the cut-out (sliding in from the side the finger went), the dots, the plaque and PLAY.
func _show_hero(from_side: int) -> void:
	if _heroes.is_empty():
		return
	var c: CharacterDef = _heroes[_index]
	var locked := _is_locked(c)
	if _art:
		_art.queue_free()
	var who := ("the " + c.display_name) if c.id == "drifter" else c.display_name
	_art = WPlaceholder.make("hero_" + c.id, "%s, full-body cut-out\nfacing camera · 520 × 700" % who, HERO_SIZE)
	if locked:
		# painted: a dark silhouette; not yet painted: the striped slot, faded
		_art.silhouette = true
		_art.modulate.a = 1.0 if _art.tex else 0.45
		_art.add_child(_padlock())
	_art_host.add_child(_art)
	if from_side != 0:
		_art.position.x = 90.0 * from_side
		var a := _art.modulate.a
		_art.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_art, "position:x", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_art, "modulate:a", a, 0.16)
	_dots.queue_redraw()
	_name.text = ("The " + c.display_name) if c.id == "drifter" else c.display_name
	# out of the row at once: a queued plate still counts, and the plaque sized in that moment stayed too wide
	for s in _stats.get_children():
		_stats.remove_child(s)
		s.queue_free()
	if locked:
		# what unlocks this hero, and how far along that is
		var q := Registry.quest_for("character", c.id)
		_line.text = TextGen.quest_text(q) if q else "Not in the game yet."
		_line.font = W.serif(400, false)
		_line.color = W.INK
		if q:
			var p := QuestTracker.progress(q)
			if p.y > 0:
				var col := _column()
				var bar := WBar.make(clampf(float(p.x) / float(p.y), 0.0, 1.0), W.BRASS, 34.0, 4, 0)
				bar.custom_minimum_size.x = 250
				bar.text = "%s / %s" % [W.num(mini(p.x, p.y)), W.num(p.y)]
				bar.text_px = 22
				col.add_child(bar)
				col.add_child(W.label("To unlock", 14, W.INK_SOFT, 0.1))
				_stats.add_child(col)
	else:
		_line.font = W.serif(400, true)
		_line.color = W.INK_SOFT
		_line.text = c.flavour
		for st in _stats_of(c):
			_stats.add_child(_stat(st[0], st[1]))
		# the hero's weapons as plates: the favourite, then any weapon only this hero can find
		var fav := Registry.weapon(c.favourite_weapon)
		if fav:
			_stats.add_child(_weapon_plate(fav, "Favourite"))
		for w: WeaponDef in _own_weapons(c):
			_stats.add_child(_weapon_plate(w, "Special"))
	_play.locked = locked
	_play.set_parts(["LOCKED" if locked else "PLAY"])
	if not locked:
		Save.data["last_character"] = c.id


## A weapon on the plaque: its 92 px plate and a tracked word under it (FAVOURITE, SPECIAL).
func _weapon_plate(w: WeaponDef, word: String) -> VBoxContainer:
	var col := _column()
	var p := WPlate.new().for_def(w, 92.0)
	p.icon_frac = 68.0 / 92.0
	col.add_child(p)
	col.add_child(W.label(word, 14, W.INK_SOFT, 0.1))
	return col


## The weapons only this hero can find (`WeaponDef.hero`: the Drifter's Revolver, Astro's Gravity Gun).
func _own_weapons(c: CharacterDef) -> Array:
	var only: Array = Registry.weapons.values().filter(func(w: WeaponDef) -> bool:
		return w.hero == c.id and not w.is_evolution and not Registry.is_hidden(w))
	only.sort_custom(func(a, b): return a.id < b.id)
	return only


## Up to three of the trait's numbers: its effects on the player, then the heal on every level.
func _stats_of(c: CharacterDef) -> Array:
	var out: Array = []
	for e in c.trait_effects:
		if e is Effect and (e.target == "player" or e.target == ""):
			out.append([TextGen.describe_effect(e, false), SHORT.get(e.stat, TextGen.stat_name(e.stat).to_upper())])
	if c.level_heal > 0.0:
		out.append(["%d%%" % int(round(c.level_heal * 100.0)), "HEAL / LV"])
	return out.slice(0, 3)


func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## One number on the plaque: sage slab over a tracked label.
func _stat(value: String, what: String) -> VBoxContainer:
	var v := _column()
	var n := W.slab_text(value, 34, W.SAGE, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	v.add_child(n)
	var l := W.label(what, 14, W.INK_SOFT, 0.1)
	l.align = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


## A padlock over a locked hero's chest: an ink shackle over a brass body with a keyhole.
func _padlock() -> Control:
	var l := Control.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(HERO_SIZE.x * 0.5 - 60.0, HERO_SIZE.y * 0.36)
	l.size = Vector2(120, 140)
	l.draw.connect(func():
		var c := Vector2(60, 0)
		l.draw_arc(c + Vector2(0, 58), 34.0, PI, TAU, 32, W.INK, 26.0, true)
		l.draw_arc(c + Vector2(0, 58), 34.0, PI, TAU, 32, W.AGED, 12.0, true)
		var body := Rect2(Vector2(4, 56), Vector2(112, 84))
		var sb := StyleBoxFlat.new()
		sb.bg_color = W.BRASS
		sb.border_color = W.INK
		sb.set_border_width_all(6)
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		l.draw_style_box(sb, body)
		l.draw_circle(c + Vector2(0, 88), 11.0, W.INK, true, -1.0, true)
		l.draw_rect(Rect2(c + Vector2(-5, 92), Vector2(10, 26)), W.INK))
	return l


## A dot per hero: brass for the one shown, paper for the rest, aged at half for a locked one.
func _draw_dots() -> void:
	var n := _heroes.size()
	if n < 2:
		return
	var w := n * 26.0 + (n - 1) * 14.0
	var x := (_dots.size.x - w) * 0.5 + 13.0
	for i in n:
		var c: CharacterDef = _heroes[i]
		var locked := _is_locked(c)
		var fill := W.BRASS if i == _index else (Color(W.AGED, 0.5) if locked else W.PAPER)
		var ink := Color(W.INK, 0.5) if locked and i != _index else W.INK
		_dots.draw_circle(Vector2(x, 13), 13.0, ink, true, -1.0, true)
		_dots.draw_circle(Vector2(x, 13), 10.0, fill, true, -1.0, true)
		x += 40.0


func _step(dir: int) -> void:
	if _heroes.size() < 2:
		return
	_index = posmod(_index + dir, _heroes.size())
	Audio.play("ui_tap")
	_show_hero(dir)
	_place()


func _refresh_map() -> void:
	var m := Registry.map(_map_id)
	var bits: Array = [m.display_name if m else _map_id]
	var best := Save.best_run(_map_id)
	if best.is_empty():
		bits.append("no runs yet")
	else:
		bits.append("best " + W.mmss(float(best.get("time", 0.0))))
		bits.append(W.lv(int(best.get("level", 0))))
		bits.append("stage %d" % int(best.get("stage", 1)))
	_map_line.text = " · ".join(bits)


## With more than one open map, the line under PLAY steps through them.
func _next_map() -> void:
	if _maps.size() < 2:
		return
	var i := 0
	for j in _maps.size():
		if _maps[j].id == _map_id:
			i = j
	_map_id = _maps[(i + 1) % _maps.size()].id
	_refresh_map()


func _on_play() -> void:
	if _play.locked:
		Audio.play("ui_locked")
		return
	var c: CharacterDef = _heroes[_index] if not _heroes.is_empty() else null
	if c:
		Save.data["last_character"] = c.id
	Save.data["last_map"] = _map_id
	Save.request_save()
	UiFx.go(get_tree(), "res://game/Game.tscn")


## A sideways swipe over the hero changes it; the finger is read here so it works wherever it lands in the row.
func _input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var id := -2
	var down := false
	var up := false
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		pos = t.position
		id = t.index
		down = t.pressed
		up = not t.pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var m := event as InputEventMouseButton
		pos = m.position
		id = -1
		down = m.pressed
		up = not m.pressed
	else:
		return
	pos = get_viewport().get_canvas_transform().affine_inverse() * pos
	if down and _swipe_id == -2:
		var band := Rect2(Vector2(0, _hero_row.position.y), Vector2(get_viewport_rect().size.x, _hero_row.size.y))
		if band.has_point(pos):
			_swipe_id = id
			_swipe_from = pos
	elif up and id == _swipe_id:
		_swipe_id = -2
		var d := pos - _swipe_from
		if absf(d.x) > SWIPE and absf(d.x) > absf(d.y) * 1.5:
			_step(-1 if d.x > 0 else 1)


## The lower block slides up 40 px and the rest fades in.
func _enter() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	for n in _lower:
		var c := n as Control
		var y := c.position.y
		c.position.y = y + 40.0
		create_tween().tween_property(c, "position:y", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
