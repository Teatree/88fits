## Title (Wanted 01/02), with play setup merged in: the gold plate, "★ WANTED ★ / 88fits / DRAG · DODGE · SURVIVE", the
## hero full-body (art/ui/wanted/hero_<id>.png, a striped slot until painted) between two arrow squares, swipe or tap
## to change, a dot per hero under it, the hero plaque (name, italic line, the trait's numbers and the favourite's plate:
## his weapon, or the line or passive he favours, Ironwood's Brawn since pass 47, each plate in its colour), PLAY, the
## map and its best run in one line (a tap changes the map when there are several). Heroes still to unlock ride the
## same carousel after the open ones: a dark silhouette with a padlock, a half-aged dot, what unlocks them and how far
## along that is, and PLAY reading LOCKED. (The developer menu can add the hidden heroes, locked, to preview the look.) Then Upgrade · Collection ·
## Settings, Upgrade in turquoise (pass 46: brass is kept for buying) with a breathing glow and a mark when a rank is
## affordable (pass 44: the Mirror's name said nothing about what it was for). No version label; the developer menu
## lives in Settings (hold the version label for 2 s), and the player's own debug mode (ten taps on the hints switch)
## puts an ARENA button top right. The top block hangs from the top edge, the plaque and the buttons from the bottom;
## the hero keeps the middle.
## Pass 52, two looks (Settings.menu_style, chosen in Settings under the player's debug mode): "painted" as above, or
## "live": the level itself behind the UI instead of the still, and in place of the cut-out the hero as a run draws him,
## smaller, standing on the sand with his start weapon circling him (ui/TitleStage.gd); a locked one is a dark figure
## with the same padlock. Everything else (the plaque, PLAY, the map line, the buttons, the swipe) is the same.
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
## The trait's numbers under short names (the rest fall back to TextGen's stat names: ATTACK DAMAGE, AREA OF EFFECT,
## COIN GAIN since pass 45, so the words live in one place).
const SHORT := {"max_hp": "HP", "damage_reduction": "DEFENCE", "move_speed": "SPEED", "magnet": "REACH",
	"cooldown": "COOLDOWN", "luck": "LUCK", "regen": "REGEN", "regen_delay": "REGEN DELAY", "revives": "REVIVES",
	"projectile_speed": "SHOT SPEED", "xp_gain": "XP", "crit_chance": "CRIT", "amount": "PROJECTILES"}
## A unit after a number whose stat has none of its own (regen is health a second: "+1.2/s" over REGEN).
const UNIT := {"regen": "/s"}
## The breathing halo behind Upgrade: the button's own turquoise (pass 46; it was brass with the button).
const GLOW := W.TURQUOISE
## Stats a hero is better off with less of: a negative on these is a buff, and stays sage.
const LOWER_BETTER := ["cooldown", "regen_delay", "shield_delay"]

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
## The hero's sheet (pass 61): the CV a tap on the plaque opens (ui/wanted/WHeroSheet.gd, no class_name).
const WHeroSheetScript := preload("res://ui/wanted/WHeroSheet.gd")
var _sheet: Control
var _swipe_id := -2   # -2 none, -1 the mouse, else a finger index
var _swipe_from := Vector2.ZERO
var _upgrade_btn: WButton
var _glow: Control
var _mark: Control
var _halo := StyleBoxFlat.new()
var _affordable := false
var _glow_t := 0.0
var _arena_btn: WButton
## The live look (pass 52): the 3D stage behind everything, the padlock over a locked hero there, and the wash, whose
## clear middle reaches down to the hero's feet (it is under the hero in this look, over the still in the other). The
## stage's script by its path: a new class_name is unknown to a headless run until the editor rescans the project.
const TitleStageScript := preload("res://ui/TitleStage.gd")
## The play-data card (pass 59) and how long after the title comes in it asks.
const WConsentScript := preload("res://ui/wanted/WConsent.gd")
const CONSENT_DELAY := 0.8
var _live := false
var _stage: TitleStageScript
var _lock: Control
var _wash_rect: TextureRect
var _wash_grad: Gradient


## Back on the title leaves the game, as it always did (quit_on_go_back is off so a run can ignore the gesture).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# the hero's sheet up (pass 61): back closes it, the game stays
		if sheet_open():
			_sheet.call("close")
			return
		Save.flush()
		get_tree().quit()


func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the look (pass 52): the painted cut-out over the still of the desert, or the level itself with the hero standing in it
	_live = str(Settings.menu_style) == "live"
	if not _live:
		ScreenBase.add_backdrop(self)
		# a live title's world kept for the way back from a menu is not wanted any more
		TitleStageScript.forget()
	_wash_rect = _wash()
	add_child(_wash_rect)
	# quests a save's totals already satisfy (pass 44 added many) complete here, quietly, instead of all at once five
	# seconds into the next run; the results screen still lists them
	QuestTracker.check_all(false)
	# gold cannot change on the title: the Upgrade mark is decided once
	_affordable = _rank_affordable()
	_heroes = _roster()
	var last := Registry.playable_character(str(Save.data.get("last_character", Save.DEFAULT_HERO)))
	_index = maxi(_heroes.find(last), 0)
	_maps = Registry.sorted_maps().filter(func(m: MapDef) -> bool: return Registry.is_unlocked("map", m.id))
	_map_id = str(Save.data.get("last_map", ""))
	if _maps.filter(func(m: MapDef) -> bool: return m.id == _map_id).is_empty():
		_map_id = _maps[0].id if not _maps.is_empty() else "red_canyon"
	if _live:
		# behind everything: the map the line under PLAY names, laid out from the title's own roll
		_stage = TitleStageScript.new()
		_stage.name = "TitleStage"
		_stage.map_id = _map_id
		add_child(_stage)
		move_child(_stage, 0)
	# the gold plate, top-left
	var gold := WMenuHeader.gold_plate(Save.gold(), 44, 40.0, 5, 4)
	gold.position = Vector2(36, 44 + W.safe_top())
	add_child(gold)
	# the debug arena (pass 44: the player's debug mode, ten taps on the hints switch), top right
	_arena_btn = WButton.make(["ARENA"], 24, WButton.SECONDARY, 4, 4, 10.0, 18.0)
	_arena_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_arena_btn.offset_left = -36 - 180
	_arena_btn.offset_right = -36
	_arena_btn.offset_top = 44 + W.safe_top()
	_arena_btn.offset_bottom = 44 + W.safe_top() + 60
	_arena_btn.visible = Settings.debug_mode
	_arena_btn.pressed.connect(func():
		Run.arena_next = true
		_leave_for_a_run()
		UiFx.go(get_tree(), "res://game/Game.tscn"))
	add_child(_arena_btn)
	# the name stack
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stack.offset_top = 150 + W.safe_top()
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
	# the play-data card (pass 59): once, the first time a build that can send starts, after the title has come in
	if Analytics.consent_needed():
		get_tree().create_timer(CONSENT_DELAY).timeout.connect(func():
			if is_inside_tree() and Analytics.consent_needed() and get_node_or_null("Consent") == null:
				WConsentScript.open(self))


## The title wash: warm at the top, clear through the middle where the hero stands, paper again at the foot. In the live
## look (pass 52) the hero stands in the scene under it, so its clear middle runs on down past his feet and turns to
## paper only between them and the plaque (_live_wash sets the stops from the layout).
func _wash() -> TextureRect:
	var g := Gradient.new()
	if _live:
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.68, 0.72, 1.0])
		g.colors = PackedColorArray([Color8(233, 201, 160, 242), Color8(233, 201, 160, 102), Color8(243, 230, 200, 0),
			Color8(243, 230, 200, 0), Color8(243, 230, 200, 205), Color8(243, 230, 200, 235)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.78, 1.0])
		g.colors = PackedColorArray([Color8(233, 201, 160, 242), Color8(233, 201, 160, 102), Color8(243, 230, 200, 0),
			Color8(243, 230, 200, 178), Color8(243, 230, 200, 235)])
	_wash_grad = g
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


## The plaque, PLAY, the map line and the three menu buttons. The plaque is a tap (pass 61, Garry: "make the character
## name plaque clickable"): it opens the hero's sheet; a sideways swipe across it still changes the hero (_input).
func _build_lower() -> void:
	var tap := WTap.new()
	tap.name = "Plaque"
	tap.box = W.box(W.PAPER, 5, 8).pad(35, 27, 35, 27)
	tap.pressed.connect(open_sheet)
	_plaque = tap
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
	# what a tap on the plaque does (pass 61)
	var more := W.label("Details ›", 16, W.BRASS_DARK, 0.15)
	more.name = "Details"
	left.add_child(more)
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
	# Upgrade (the Mirror until pass 44) is the one button in colour (turquoise since pass 46: brass is for buying), with
	# a pulsing glow and a mark when a rank can be bought: it is where the gold goes, and the row should say so. The glow
	# sits under the row and the mark over it (pass 45: both drawn under it, the mark showed as a crescent)
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_halo.draw_center = false
	_halo.set_border_width_all(0)
	_halo.set_corner_radius_all(14)
	_halo.shadow_offset = Vector2.ZERO
	add_child(row)
	_mark = Control.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(_draw_mark)
	add_child(_mark)
	for pair in [["Upgrade", "res://ui/HomesteadScreen.tscn"], ["Collection", "res://ui/CollectionScreen.tscn"], ["Settings", "res://ui/SettingsScreen.tscn"]]:
		var primary: bool = pair[0] == "Upgrade"
		var b := WButton.make([pair[0]], 30, WButton.UPGRADE if primary else WButton.SECONDARY, 5, 6, 20.0, 0.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path: String = pair[1]
		b.pressed.connect(func():
			# the live look keeps its built world for the way back (pass 52)
			if _stage:
				_stage.keep_on_exit = true
			UiFx.go(get_tree(), path))
		row.add_child(b)
		if primary:
			_upgrade_btn = b
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
	var top := HERO_TOP + W.safe_top() + (vp.y - 1920.0) * 0.5
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
	if _stage:
		# the live hero stands in the same box the cut-out fills (pass 52)
		_stage.frame(Rect2(_hero_row.position + _art_host.position, HERO_SIZE * k))
		_live_wash(vp.y, plaque_top)
		_place_lock()


## The live look's wash stops (pass 52): clear to just under the hero's shadow, paper by a little past the plaque's top.
func _live_wash(h: float, plaque_top: float) -> void:
	if _wash_grad == null or _stage == null or h <= 0.0:
		return
	var clear_to := clampf((_stage.ground_px().y + 40.0) / h, 0.52, 0.95)
	var paper_at := clampf((plaque_top + 40.0) / h, clear_to + 0.01, 0.98)
	_wash_grad.offsets = PackedFloat32Array([0.0, 0.3, 0.5, clear_to, paper_at, 1.0])


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
	if _live:
		# the hero on the sand (pass 52): he runs in from the side the finger came from, the last one runs off
		_stage.show_hero(c, locked, from_side)
		_show_lock(locked, from_side)
	else:
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
			_stats.add_child(_stat(st[0], st[1], bool(st[2])))
		# the hero's items as plates: the weapon he lands with (pass 47b, Garry: Ironwood's Spear did not show), the
		# favourite, then any other weapon only this hero can find
		var start := Registry.start_weapon_for(c)
		if start:
			_stats.add_child(_item_plate(start, "Start", start_level(c, start)))
		var fav := _favourite_of(c)
		if fav and fav != start:
			_stats.add_child(_item_plate(fav, "Favourite", start_level(c, fav)))
		for w: WeaponDef in _own_weapons(c):
			if w != start:
				_stats.add_child(_item_plate(w, "Special", 1))
	_play.locked = locked
	_play.set_parts(["LOCKED" if locked else "PLAY"])
	if not locked:
		Save.data["last_character"] = c.id


## The hero's favourite: his weapon, or when he has none, the line or passive he favours (pass 46: Ironwood's Cake; pass
## 47: his Brawn, a line on its light yellow plate).
func _favourite_of(c: CharacterDef) -> ContentDef:
	var w: WeaponDef = Registry.weapon(c.favourite_weapon) if c.favourite_weapon != "" else null
	if w:
		return w
	return Registry.passive(c.favourite_passive) if c.favourite_passive != "" else null


## The level a hero has an item at when he finds it or lands with it (pass 48: the plaque's plates take its colour): a
## favourite at its bonus level (the Drifter's Peashooter and Calavera's Skull Rain 2, Ironwood's Brawn 2), else 1.
static func start_level(c: CharacterDef, def: ContentDef) -> int:
	if c == null or def == null:
		return 1
	if def is WeaponDef and def.id == c.favourite_weapon:
		if str(c.favourite_bonus.get("type", "")) == "level":
			return clampi(int(c.favourite_bonus.get("value", 1)), 1, maxi((def as WeaponDef).max_level, 1))
		return 1
	if def is PassiveDef and def.id == c.favourite_passive:
		var mx := maxi((def as PassiveDef).max_level, 1)
		match str(c.favourite_passive_bonus.get("type", "")):
			"max":
				return mx
			"level":
				return clampi(int(c.favourite_passive_bonus.get("value", 1)), 1, mx)
	return 1


## An item on the plaque: its 92 px plate in the colour of the level he has it at and a tracked word under it (START,
## FAVOURITE, SPECIAL).
func _item_plate(def: ContentDef, word: String, level: int = 1) -> VBoxContainer:
	var col := _column()
	col.name = word
	col.set_meta("def", def)
	col.set_meta("level", level)
	var p := WPlate.new().for_def(def, 92.0, false, level)
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


## Up to three of the trait's numbers: its effects on the player, then the heal on every level. Each is [value, label,
## good]: a debuff (a negative, or a positive on a lower-is-better stat) is not good and reads in dark red (pass 45).
## Pass 61: a hero whose trait grows with his level shows what one level gives ("+1%" over "CRIT / LV").
func _stats_of(c: CharacterDef) -> Array:
	var out: Array = []
	if not c.level_trait.is_empty():
		for e in c.level_trait:
			if e is Effect:
				var x: Effect = e
				var up: bool = (x.value >= 0.0) != (x.stat in LOWER_BETTER)
				out.append([TextGen.hero_step(x) + str(UNIT.get(x.stat, "")), str(SHORT.get(x.stat, TextGen.stat_name(x.stat).to_upper())) + " / LV", up])
		if c.level_heal > 0.0:
			out.append(["%d%%" % int(round(c.level_heal * 100.0)), "HEAL / LV", true])
		return out.slice(0, 3)
	for e in c.trait_effects:
		if e is Effect and (e.target == "player" or e.target == ""):
			var good: bool = e.op == "set" or ((e.value >= 0.0) != (e.stat in LOWER_BETTER))
			out.append([TextGen.describe_effect(e, false) + str(UNIT.get(e.stat, "")), SHORT.get(e.stat, TextGen.stat_name(e.stat).to_upper()), good])
	if c.level_heal > 0.0:
		out.append(["%d%%" % int(round(c.level_heal * 100.0)), "HEAL / LV", true])
	return out.slice(0, 3)


func _column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## One number on the plaque: sage slab (dark red for a debuff) over a tracked label.
func _stat(value: String, what: String, good: bool = true) -> VBoxContainer:
	var v := _column()
	var n := W.slab_text(value, 34, W.SAGE if good else W.BAD_DARK, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	v.add_child(n)
	var l := W.label(what, 14, W.INK_SOFT, 0.1)
	l.align = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


## The live look's padlock (pass 52): over a locked hero's chest as on the cut-out, showing once he has run in.
func _show_lock(locked: bool, from_side: int) -> void:
	if _lock:
		_lock.queue_free()
		_lock = null
	if not locked:
		return
	_lock = _padlock()
	_lock.name = "Padlock"
	_art_host.add_child(_lock)
	_place_lock()
	if from_side != 0:
		_lock.modulate.a = 0.0
		var tw := _lock.create_tween()
		tw.tween_interval(TitleStageScript.SWAP_TIME * 0.8)
		tw.tween_property(_lock, "modulate:a", 1.0, 0.15)


## The padlock on the live hero's chest, in the box's own (unscaled) units, three quarters of the cut-out's size since the
## live figure is smaller.
func _place_lock() -> void:
	if _lock == null or _stage == null:
		return
	var k: float = _art_host.scale.y if _art_host.scale.y > 0.0 else 1.0
	var origin := _hero_row.position + _art_host.position
	var fig: Rect2 = _stage.figure_rect()
	var s := 0.75
	var chest := (fig.position.y + fig.size.y * 0.32 - origin.y) / k
	_lock.scale = Vector2(s, s)
	_lock.position = Vector2(HERO_SIZE.x * 0.5 - 60.0 * s, chest - 80.0 * s)


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


## The map's best run under PLAY: nothing until a run has been played (pass 44: the "no runs yet" line read like a
## placeholder), then the true best: time, level, stage and kills.
func _refresh_map() -> void:
	var m := Registry.map(_map_id)
	var bits: Array = [m.display_name if m else _map_id]
	var best := Save.best_run(_map_id)
	var played := not best.is_empty() and float(best.get("time", 0.0)) > 0.0
	_map_tap.visible = played or _maps.size() > 1
	if played:
		bits.append("best " + W.mmss(float(best.get("time", 0.0))))
		bits.append(W.lv(int(best.get("level", 0))))
		bits.append("stage %d" % int(best.get("stage", 1)))
		if int(best.get("kills", 0)) > 0:
			bits.append("%s kills" % W.num(int(best.get("kills", 0))))
	_map_line.text = " · ".join(bits)


## The glow behind Upgrade: one smooth turquoise halo that breathes, the button's own colour (a StyleBoxFlat's feathered
## shadow ring, nothing drawn inside the button; pass 45: six stepped rings had read as a staircase).
func _draw_glow() -> void:
	if _upgrade_btn == null or not _upgrade_btn.is_visible_in_tree():
		return
	var r := _upgrade_btn.get_global_rect()
	r.position -= _glow.global_position
	var pulse := 0.5 + 0.5 * sin(_glow_t * 2.6)
	_halo.shadow_size = int(round(18.0 + 14.0 * pulse))
	_halo.shadow_color = Color(GLOW, 0.42 + 0.22 * pulse)
	_glow.draw_style_box(_halo, r)


## The brass "!" on Upgrade's top-right corner when a rank can be bought, drawn over the row.
func _draw_mark() -> void:
	if _upgrade_btn == null or not _upgrade_btn.is_visible_in_tree() or not _affordable:
		return
	var r := _upgrade_btn.get_global_rect()
	r.position -= _mark.global_position
	var c := Vector2(r.end.x - 6.0, r.position.y + 6.0)
	_mark.draw_circle(c, 22.0, W.INK, true, -1.0, true)
	_mark.draw_circle(c, 17.0, W.BRASS, true, -1.0, true)
	_mark.draw_rect(Rect2(c + Vector2(-3.0, -11.0), Vector2(6.0, 13.0)), W.INK)
	_mark.draw_circle(c + Vector2(0.0, 7.5), 3.2, W.INK, true, -1.0, true)


## Whether the purse buys the next rank of any open talent.
func _rank_affordable() -> bool:
	var gold := Save.gold()
	for def: TalentDef in Registry.talents_list():
		if not Registry.is_unlocked("talent", def.id):
			continue
		var cost := def.cost_of_rank(Save.talent_rank(def.id))
		if cost >= 0 and cost <= gold:
			return true
	return false


func _process(delta: float) -> void:
	if _glow == null:
		return
	_glow_t += delta
	_glow.queue_redraw()
	# the row slides in (_enter): the mark follows the button
	if _mark:
		_mark.queue_redraw()


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
	if _stage:
		_stage.set_map(_map_id)


func _on_play() -> void:
	if _play.locked:
		Audio.play("ui_locked")
		return
	var c: CharacterDef = _heroes[_index] if not _heroes.is_empty() else null
	if c:
		Save.data["last_character"] = c.id
	Save.data["last_map"] = _map_id
	Save.request_save()
	_leave_for_a_run()
	UiFx.go(get_tree(), "res://game/Game.tscn")


## A run starting lets the live look's world go (pass 52): the run builds its own map, and never carries two.
func _leave_for_a_run() -> void:
	if _stage:
		_stage.keep_on_exit = false
	TitleStageScript.forget()


## The hero's sheet over the title (pass 61): open while it is up and not on its way out.
func sheet_open() -> bool:
	return _sheet != null and is_instance_valid(_sheet) and not bool(_sheet.call("is_done"))


## A tap on the plaque (pass 61): the shown hero's sheet, a locked one's with its quest.
func open_sheet() -> void:
	if _heroes.is_empty() or sheet_open():
		return
	var c: CharacterDef = _heroes[_index]
	_swipe_id = -2
	_sheet = WHeroSheetScript.open(self, c, _is_locked(c))


## A sideways swipe over the hero changes it; the finger is read here so it works wherever it lands in the row, and
## (pass 61) across the plaque, whose tap opens the hero's sheet: a swipe travels past the tap's slop, so it never opens it.
func _input(event: InputEvent) -> void:
	if sheet_open():
		return
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
		if band.has_point(pos) or _plaque.get_global_rect().has_point(pos):
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
