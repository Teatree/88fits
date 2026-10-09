## The hero's sheet (pass 61, Garry: "make the character name plaque clickable and when I click on it, it opens up a pop-up
## that covers most of the screen ... Their portrait at the top with the name, the slogan everything. Supposed to look like
## a kind of a CV"): a Wanted poster of the hero over a sepia dim, opened by a tap on the title's plaque. From the top: his
## badge as the portrait in a frame, beside it the name, the slogan and the trait's name; the SIGNATURE STAT (the rule in
## TextGen.hero_trait's words, its step a level in big numbers, and what it comes to at levels 1, 10, 20 and 40); the
## STATS a run starts with (Run.hero_sheet at level 1, the Upgrade ranks in, TextGen's names, his signature stats in
## sage); the ITEMS (the weapon he lands with, his favourite and what finding it gives, any other weapon only he finds,
## his hero mutation and his perks), each on its plate with its name and the words the level-up card shows for it. A
## hero still locked shows the same under the quest that unlocks him and how far along it is.
## The card scrolls by hand (TouchScroll) when it is taller than the screen; CLOSE, a tap on the dim outside the card, the
## back gesture (TitleScreen asks close()) and Esc close it. It keeps clear of a camera cutout (W.safe_top()).
## No class_name (a new one is unknown to a headless run until the editor rescans): open it with
## preload("res://ui/wanted/WHeroSheet.gd").open(host, hero, locked).
## Names for tools: "HeroSheet", "Dim", "Card", "Scroll", "Body", "Close", "Portrait", "Name", "Slogan", "Locked",
## "Signature", "Stats", "Items", "Item_<role>_<id>" (role start, favourite, own, mutation, perk).
extends Control

signal closed

## The card's margins on the screen (the hard shadow adds its 12 px on the right and the foot).
const SIDE := 36.0
const TOP := 40.0
const BOTTOM := 44.0
const PAD := 40.0
const PORTRAIT := 236.0
const PLATE := 128.0
## The levels the signature block shows the rule at.
const LEVELS := [1, 10, 20, 40]
## The stats a run starts with, in this order (TextGen's names).
const STATS := ["max_hp", "regen", "regen_delay", "damage_reduction", "move_speed", "might", "crit_chance", "crit_damage",
	"area", "cooldown", "projectile_speed", "duration", "debuff_duration", "magnet", "luck", "greed", "xp_gain", "revives"]
## Player stats held as a multiplier of 1, shown as a percent ("100%" attack damage, "87%" cooldown).
const MULTS := ["might", "cooldown", "area", "projectile_speed", "duration", "debuff_duration", "buff_duration", "greed",
	"xp_gain", "heal_mult", "haste"]
## A tap is a press and a release this close together (WTap's slop).
const SLOP := 40.0
## The paper fade over the list's foot while more of it is below (so a row cut by the edge reads as "scroll on").
const FADE_H := 56.0

var hero: CharacterDef
var locked := false
var dim: ColorRect
var card: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var close_btn: WButton
var _touch: TouchScroll
var _fade: TextureRect
var _done := false
var _dim_down := false
var _dim_from := Vector2.ZERO


static func open(host: Control, c: CharacterDef, is_locked: bool = false) -> Control:
	var s: Control = load("res://ui/wanted/WHeroSheet.gd").new()
	s.name = "HeroSheet"
	s.set("hero", c)
	s.set("locked", is_locked)
	s.call("_build")
	host.add_child(s)
	s.call("_enter")
	return s


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("wanted_modal")


func _build() -> void:
	dim = W.dim(W.DIM, true)
	dim.name = "Dim"
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", W.box(W.PAPER, 6, 12).pad(PAD, PAD - 8.0, PAD, PAD - 4.0))
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_left = SIDE
	card.offset_right = -SIDE - 12.0
	card.offset_top = TOP + W.safe_top()
	card.offset_bottom = -BOTTOM - 12.0
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 28)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(scroll)
	body = VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(body)
	body.add_child(_header())
	if locked:
		body.add_child(_spacer(28.0))
		body.add_child(_locked_box())
	_signature()
	_stats()
	_items()
	body.add_child(_spacer(12.0))
	close_btn = WButton.make(["CLOSE"], 34, WButton.SECONDARY, 5, 8, 22.0, 0.0)
	close_btn.name = "Close"
	close_btn.pressed.connect(close)
	v.add_child(close_btn)
	_touch = TouchScroll.new(scroll, true)
	_fade = _foot_fade()
	add_child(_fade)


## Paper from clear to whole, laid over the list's foot by _process while there is more below.
func _foot_fade() -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(W.PAPER, 0.0), Color(W.PAPER, 1.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 64
	var r := TextureRect.new()
	r.name = "Fade"
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	return r


# ---------------------------------------------------------------- the blocks

## The top: the badge in an aged frame (a mugshot), beside it WANTED, the name, the slogan and the trait's name.
func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 34)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.name = "Portrait"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", W.box(W.AGED, 5, 8).pad(10, 10, 10, 10))
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tr := TextureRect.new()
	tr.texture = hero.icon
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if locked:
		var m := ShaderMaterial.new()
		m.shader = WPlaceholder.SILHOUETTE
		tr.material = m
	frame.add_child(tr)
	h.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var star := WStarLine.make("Locked" if locked else "Wanted", 22, W.ROCK if locked else W.INK_SOFT, 0.35)
	star.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_child(star)
	var nm := W.text(hero_name(hero).to_upper(), W.slab(), name_px(hero_name(hero)), W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	nm.name = "Name"
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(nm)
	var sl := W.serif_text(hero.flavour, 28, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true, false)
	sl.name = "Slogan"
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(sl)
	if hero.trait_name != "":
		col.add_child(_spacer(2.0))
		col.add_child(W.label("Trait · " + hero.trait_name, 20, W.BRASS_DARK, 0.15))
	return h


## The name as the title and the plaque write it: "The Drifter".
static func hero_name(c: CharacterDef) -> String:
	return ("The " + c.display_name) if c.id == "drifter" else c.display_name


## The name's size: as big as fits beside the portrait (Alfa Slab runs about 0.78 em a letter).
static func name_px(n: String) -> int:
	return clampi(int(560.0 / maxf(float(n.length()) * 0.78, 1.0)), 52, 84)


## A locked hero (pass 61): the quest that unlocks him and how far along it is.
func _locked_box() -> Control:
	var p := PanelContainer.new()
	p.name = "Locked"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.box(W.AGED, 4, 0).pad(28, 22, 28, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(W.label("To unlock", 20, W.ROCK, 0.15))
	var q := Registry.quest_for("character", hero.id)
	var words := TextGen.quest_text(q) if q else "Not in the game yet."
	v.add_child(W.serif_text(words, 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	if q:
		var pr := QuestTracker.progress(q)
		if pr.y > 0:
			var bar := WBar.make(clampf(float(pr.x) / float(pr.y), 0.0, 1.0), W.BRASS, 36.0, 4, 0)
			bar.text = "%s / %s" % [W.num(mini(pr.x, pr.y)), W.num(pr.y)]
			bar.text_px = 22
			v.add_child(bar)
	return p


## SIGNATURE STAT: the step a level in big numbers (and Astro's heal), the rule in words, then what it comes to at
## levels 1, 10, 20 and 40. A hero with no level trait (the hidden ones, previewed) reads his own trait's words.
func _signature() -> void:
	var title := ("Signature stat · " + hero.trait_name) if hero.trait_name != "" else "Signature stat"
	var v := _section(title, "Signature")
	if hero.level_trait.is_empty():
		v.add_child(W.serif_text(TextGen.hero_trait(hero), 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 44)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for e in hero.level_trait:
		if e is Effect:
			var x: Effect = e
			row.add_child(_big(TextGen.hero_step(x), TextGen.hero_word(x.stat) + " a level", _good(x.stat, x.value)))
	if hero.level_heal > 0.0:
		row.add_child(_big(TextGen._plain(hero.level_heal * 100.0) + "%", "healed every level-up", true))
	v.add_child(row)
	var rule := W.serif_text(TextGen.hero_trait(hero), 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	rule.name = "Rule"
	v.add_child(rule)
	var grid := GridContainer.new()
	grid.name = "Levels"
	grid.columns = LEVELS.size()
	grid.add_theme_constant_override("h_separation", 14)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lv: int in LEVELS:
		grid.add_child(_level_cell(lv))
	v.add_child(grid)


## One step in big numbers over its words: "+1%" over "CRIT CHANCE A LEVEL".
func _big(value: String, words: String, good: bool) -> Control:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 4)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(W.slab_text(value, 64, W.SAGE if good else W.BAD_DARK, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	c.add_child(W.label(words, 18, W.INK_SOFT, 0.12))
	return c


## A level's cell: "LV 20" over what each signature stat comes to there.
func _level_cell(lv: int) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", W.box(W.AGED if lv > 1 else W.PAPER, 3, 0).pad(14, 10, 14, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var l := W.label(W.lv(lv), 18, W.INK_SOFT, 0.12)
	l.align = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	for e in hero.level_effects(lv):
		var x: Effect = e
		var t := W.slab_text(TextGen.hero_step(x), 32, W.SAGE if _good(x.stat, x.value) else W.BAD_DARK, HORIZONTAL_ALIGNMENT_CENTER, 0.0)
		v.add_child(t)
	return p


## STATS: what a run starts with (level 1, the Upgrade ranks in), two columns; his signature stats in sage.
func _stats() -> void:
	var ups := _has_upgrades()
	var v := _section("Stats · a run's start" + (", your upgrades in" if ups else ""), "Stats")
	var sheet: StatSheet = Run.hero_sheet(hero, 1)
	var mine: Array = []
	for e in hero.level_trait:
		if e is Effect:
			mine.append((e as Effect).stat)
	if hero.level_heal > 0.0:
		mine.append("max_hp")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for st: String in STATS:
		grid.add_child(_stat_cell(st, stat_value(st, sheet.get_stat(st)), st in mine))
	v.add_child(grid)


## A stat's value as the sheet shows it: a multiplier as a percent, everything else in TextGen's units.
static func stat_value(st: String, val: float) -> String:
	if st in MULTS:
		# as few decimals as it needs: Solenne's 101.5% debuff duration at level 1
		return TextGen._plain(val * 100.0) + "%"
	return TextGen.format_value(st, val)


func _stat_cell(st: String, value: String, mine: bool) -> Control:
	var p := PanelContainer.new()
	p.name = "Stat_" + st
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := W.box(Color(0, 0, 0, 0), 2, 0).pad(0, 10, 0, 10)
	b.sides = [false, false, false, true]
	b.border_color = Color(W.INK, 0.35)
	p.add_theme_stylebox_override("panel", b)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var words := TextGen.stat_name(st)
	var n := W.serif_text(words.substr(0, 1).to_upper() + words.substr(1), 24, W.SAGE if mine else W.INK_SOFT,
		600 if mine else 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true, false)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(W.slab_text(value, 28, W.SAGE if mine else W.INK, HORIZONTAL_ALIGNMENT_RIGHT, 0.0))
	return p


## Whether the Upgrade board (the Mirror) holds any rank: the stats then say they include them.
func _has_upgrades() -> bool:
	for tdef: TalentDef in Registry.talents.values():
		if Save.talent_rank(tdef.id) > 0:
			return true
	return false


## ITEMS: the weapon he lands with, his favourite (and what finding it gives), any other weapon only he finds, his hero
## mutation and his perks; each its plate, its name and the level-up card's words for it.
func _items() -> void:
	var v := _section("Items", "Items")
	var sheet: StatSheet = Run.hero_sheet(hero, 1)
	var start := Registry.start_weapon_for(hero)
	var fav: ContentDef = _favourite()
	if start:
		var bonus := _bonus_words(start) if start == fav else ""
		v.add_child(_item(start, "start", "Start weapon" + (" · favourite" if start == fav else ""), _level_of(start), bonus, sheet))
	if fav and fav != start:
		var word := "Favourite " + ("weapon" if fav is WeaponDef else ("line" if W.is_line(fav) else "item"))
		v.add_child(_item(fav, "favourite", word, _level_of(fav), _bonus_words(fav), sheet))
	for w: WeaponDef in own_weapons(hero):
		if w != start and w != fav:
			v.add_child(_item(w, "own", "Only %s finds it" % _pronoun(), 1, "", sheet))
	for m: MutationDef in Registry.hero_mutations(hero.id):
		var on := Registry.weapon(m.weapon)
		v.add_child(_item(m, "mutation", "Hero mutation · " + (on.display_name if on else m.weapon), 1, "", sheet))
	for pk: PerkDef in Registry.perks_of(hero.id):
		v.add_child(_item(pk, "perk", "Perk", 1, "", sheet))


## The weapons only this hero can find (WeaponDef.hero), the title plaque's SPECIAL plates.
static func own_weapons(c: CharacterDef) -> Array:
	var only: Array = Registry.weapons.values().filter(func(w: WeaponDef) -> bool:
		return w.hero == c.id and not w.is_evolution and not Registry.is_hidden(w))
	only.sort_custom(func(a, b): return a.id < b.id)
	return only


func _favourite() -> ContentDef:
	var w: WeaponDef = Registry.weapon(hero.favourite_weapon) if hero.favourite_weapon != "" else null
	if w:
		return w
	return Registry.passive(hero.favourite_passive) if hero.favourite_passive != "" else null


## The level he has an item at when he lands with it or finds it (TitleScreen.start_level: a favourite's bonus level).
func _level_of(def: ContentDef) -> int:
	var ts: Script = load("res://ui/TitleScreen.gd")
	return int(ts.call("start_level", hero, def))


## What finding the favourite gives, without a pronoun: "Found at level 2.", "Found full.", "Found with +20% area of
## effect."
func _bonus_words(def: ContentDef) -> String:
	var b: Dictionary = hero.favourite_bonus if def is WeaponDef else hero.favourite_passive_bonus
	match str(b.get("type", "")):
		"level":
			return "Found at level %d." % int(b.get("value", 1))
		"max":
			return "Found full."
		"effects":
			return "Found with %s." % TextGen.describe_effects(b.get("effects", []))
	return ""


func _pronoun() -> String:
	match hero.pronoun:
		"he":
			return "he"
		"she":
			return "she"
	return "they"


## One item: its plate in the colour of the level he has it at, the role over its name, the card's words, the bonus.
func _item(def: ContentDef, role: String, word: String, level: int, bonus: String, sheet: StatSheet) -> Control:
	var h := HBoxContainer.new()
	h.name = "Item_%s_%s" % [role, def.id]
	h.add_theme_constant_override("separation", 26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := WPlate.new().for_def(def, PLATE, false, level)
	plate.icon_frac = 0.74
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var k := W.kind_of(def)
	col.add_child(W.label(word + ((" · " + W.lv(level)) if level > 1 else ""), 18, W.KIND_WORD.get(k, W.INK_SOFT), 0.12))
	col.add_child(W.text(def.display_name, W.slab(), 38, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var d := W.serif_text(describe(def, level, sheet), 26, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	d.name = "Text"
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(d)
	if bonus != "":
		col.add_child(W.serif_text(bonus, 24, W.SAGE, 600, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var wrap := VBoxContainer.new()
	wrap.name = h.name
	h.name = "Row"
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override("separation", 0)
	wrap.add_child(_spacer(26.0))
	wrap.add_child(h)
	return wrap


## The words a level-up card shows for an item he does not hold yet, at the level he has it at: a weapon's description
## built on the hero's own level-1 sheet, a line's or a passive item's card line, a perk's or a mutation's text.
static func describe(def: ContentDef, level: int, sheet: StatSheet) -> String:
	if def is WeaponDef:
		var inst := WeaponInstance.new(def as WeaponDef, maxi(level, 1))
		inst.rebuild(sheet if sheet else StatSheet.new(), [])
		return inst.description()
	if def is PassiveDef:
		return WItem.effect({"def": def, "level_from": 0, "level_to": maxi(level, 1), "evolve": (def as PassiveDef).is_evolved()})
	if def is PerkDef:
		return (def as PerkDef).text
	if def is MutationDef:
		return (def as MutationDef).text
	return def.flavour


# ---------------------------------------------------------------- pieces

## A labelled part of the sheet under an ink rule: returns the box its rows go in.
func _section(title: String, node_name: String) -> VBoxContainer:
	body.add_child(_spacer(34.0))
	var rule := ColorRect.new()
	rule.color = W.INK
	rule.custom_minimum_size.y = 4
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(rule)
	body.add_child(_spacer(22.0))
	var v := VBoxContainer.new()
	v.name = node_name
	v.add_theme_constant_override("separation", 16)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(W.label(title, 22, W.INK_SOFT, 0.15))
	body.add_child(v)
	return v


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = h
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## A signature step is good when it raises a stat a hero wants more of (or lowers his regen delay).
static func _good(st: String, value: float) -> bool:
	return (value >= 0.0) != (st in TextGen.HERO_LOWER)


# ---------------------------------------------------------------- in and out

## The dim fades in, the card slides up 60 px and fades in.
func _enter() -> void:
	dim.modulate.a = 0.0
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)
	card.modulate.a = 0.0
	await get_tree().process_frame
	if _done or not is_inside_tree():
		return
	var y := card.position.y
	card.position.y = y + 60.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "position:y", y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)


func close() -> void:
	if _done:
		return
	_done = true
	if _touch:
		_touch.reset()
	closed.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)


func is_done() -> bool:
	return _done


## A tap on the dim outside the card closes it (a drag that ends there does not).
func _on_dim_input(e: InputEvent) -> void:
	var is_press := false
	var is_release := false
	var pos := Vector2.ZERO
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		is_press = t.pressed
		is_release = not t.pressed
		pos = t.position
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var m := e as InputEventMouseButton
		is_press = m.pressed
		is_release = not m.pressed
		pos = m.position
	else:
		return
	if is_press:
		_dim_down = true
		_dim_from = pos
	elif is_release and _dim_down:
		_dim_down = false
		if pos.distance_to(_dim_from) <= SLOP:
			W.sfx("ui_tap")
			close()


func _input(event: InputEvent) -> void:
	if _done:
		return
	var esc := event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE
	if esc or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if _touch:
		_touch.input(event)


func _process(_delta: float) -> void:
	if _touch and not _done:
		_touch.process()
	if _fade and scroll:
		var below := scroll.get_v_scroll_bar().max_value - scroll.size.y - float(scroll.scroll_vertical)
		_fade.visible = below > 2.0
		_fade.position = scroll.global_position - global_position + Vector2(0.0, scroll.size.y - FADE_H)
		_fade.size = Vector2(scroll.size.x, FADE_H)
		_fade.modulate.a = card.modulate.a
