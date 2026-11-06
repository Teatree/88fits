## The hero's sheet (pass 61, Garry: "make the character name plaque clickable and when I click on it, it opens up a pop-up
## that covers most of the screen ... Their portrait at the top with the name, the slogan everything. Supposed to look like
## a kind of a CV"): a Wanted poster of the hero over a sepia dim, opened by a tap on the title's plaque. From the top: his
## badge as the portrait in a frame (pass 68: the badge of the look he is played in, Registry.played_look), beside it the
## name, the slogan and the trait's name; the SIGNATURE STAT (the rule in
## TextGen.hero_trait's words, its step a level in big numbers, and what it comes to at levels 1, 10, 20 and 40); the
## STATS a run starts with (Run.hero_sheet at level 1, the Upgrade ranks in, TextGen's names, his signature stats in
## sage); the ITEMS (the weapon he lands with, his favourite and what finding it gives, any other weapon only he finds,
## his hero mutation and his perks), each on its plate with its name and the words the level-up card shows for it. A
## hero still locked shows the same under the quest that unlocks him and how far along it is.
## Pass 69 (Garry: an unavailable hero is unknown, "stats are unknown, weapon is a black silhouette of the one with a
## question mark and so is the fav item. All of it."): a hero not owned (`locked`: on sale or locked) reads UNKNOWN under
## his black badge, no slogan or trait, his signature a "?", every stat a "?", each item a mystery plate (WPlate.mystery)
## with its role and a "?" for its name; the box under the header says what unlocks him (and how far along it is) or, on
## sale, his price and where to buy him (the title's BUY).
## The card scrolls by hand (TouchScroll) when it is taller than the screen; CLOSE, a tap on the dim outside the card, the
## back gesture (TitleScreen asks close()) and Esc close it. It keeps clear of a camera cutout (W.safe_top()).
## No class_name (a new one is unknown to a headless run until the editor rescans): open it with
## preload("res://ui/wanted/WHeroSheet.gd").open(host, hero, locked).
## Names for tools: "HeroSheet", "Dim", "Card", "Scroll", "Body", "Close", "Portrait", "Name", "Slogan", "Locked",
## "Signature", "Stats", "Items", "Item_<role>_<id>" (role start, favourite, own, mutation, perk).
## Pass 111 (lane SKINS; Garry: "add the UI support for this. Make it easy to access for each hero. ... first you
## complete a goal, then you get access to buying skins"): LOOKS, right under the header of a hero the player owns (a
## hero not owned sells none): a tile for each look he can wear or work towards (Registry.skins_of: the look every
## player owns first, then those sold as skins), its full-body still (tools/skin_stills.py; the look's badge without
## one), its name and where the player stands with it: WORN (brass), OWNED ("Tap to wear"), BUY (the price in its
## currency's icon; a tap asks, WConfirm, then pays through Currency and wears it) or LOCKED (the goal in the quests'
## words and how far along it is; pass 113: its still a dark silhouette until the goal is reached). Names: "Looks",
## "LookGrid", "Look_<CODE>" (meta "look" and "state": worn, owned, buyable, locked). `look_changed` tells the title to
## draw him in the new look.
## Pass 123 (lane HEROES), under Royale: the Hero details pop-up (the mock
## 5_Hero_details; Garry: "Hero details drops the milestone row; the trait rule in words only" and "I actually like our
## detailed view. Make that, but with the new UI style"): today's content in the mock's shell. A slate card R.MODAL_W wide
## (WConfirm.card_box) over the 80 % dim; at the top his badge round in a navy ring, his name in cream Ultra with DETAILS
## in the corner, his slogan and the trait as black pills ("TRAIT · LONG ROAD", "+1% crit chance per Level"); SIGNATURE
## STAT the rule in words (no level 1 / 10 / 20 / 40 row); STATS · A RUN'S START in two columns, his signature stats green,
## a note under them; HIS ITEMS on their rarity frames with the level-up card's words (the favourite's bonus in Garry's
## words); LOOKS as the Heroes screen's tiles; CLOSE slate on the card's foot. A hero not
## owned keeps today's unknown version in the same style. It scrolls by finger as today. The pieces the Heroes screen
## (ui/HeroesScreen.gd) shares are static here: trait_lines, trait_note, items_of, royale_item_row, royale_portrait,
## royale_look_tile, royale_tag, look_state_of, bonus_line.
extends Control

signal closed
## Pass 111 (lane SKINS): the player wore or bought a look of `hero` (the title draws him in it at once).
signal look_changed(code: String)


## The card's margins on the screen (the hard shadow adds its 12 px on the right and the foot).
const SIDE := 36.0
const TOP := 40.0
const PAD := 40.0
const PORTRAIT := 236.0
const PLATE := 128.0
## The stats a run starts with, in this order (TextGen's names).
const STATS := ["max_hp", "regen", "regen_delay", "damage_reduction", "move_speed", "might", "crit_chance", "crit_damage",
	"area", "cooldown", "projectile_speed", "duration", "debuff_duration", "magnet", "luck", "greed", "xp_gain", "revive_hp"]
## Player stats held as a multiplier of 1, shown as a percent ("100%" attack damage, "87%" cooldown).
const MULTS := ["might", "cooldown", "area", "projectile_speed", "duration", "debuff_duration", "buff_duration", "greed",
	"xp_gain", "heal_mult", "haste"]
## A tap is a press and a release this close together (WTap's slop).
const SLOP := 40.0
## The paper fade over the list's foot while more of it is below (so a row cut by the edge reads as "scroll on").
const FADE_H := 56.0
## Pass 123 (lane HEROES), Royale: the card's margins on the screen (its 8 px navy base under the foot), the portrait,
## the name, the slogan, the trait pills, the section labels and the gap above each, the rule's words, a stat row (the
## mock's 56 px rows, two columns 40 apart, the value in Ultra by Garry's 28 px rule), the note, an item (its frame, name,
## words and label), the looks a row, and the slate the list's foot fades into (the panel's gradient near its foot).
const R_TOP := 40.0
const R_BOTTOM := 44.0
const R_PORTRAIT := 200.0
const R_NAME_PX := 56
const R_SLOGAN_PX := 26
const R_PILL_PX := 22
const R_PILL_H := 40.0
const R_LABEL_PX := 18
const R_SECTION_GAP := 34.0
const R_RULE_PX := 26
const R_STAT_H := 56.0
const R_STAT_NAME_PX := 24
const R_STAT_VALUE_PX := 28
const R_STAT_GAP := 40
const R_NOTE_PX := 20
const R_ITEM_FRAME := 112.0
const R_ITEM_NAME_PX := 38
const R_ITEM_TEXT_PX := 26
const R_ITEM_LABEL_PX := 18
const R_LOOK_COLS := 4
const R_FADE := Color("212a42")
## One look's tile (the Heroes screen's LOOKS strip and this sheet's grid; the mock's 200 x 210, taller for a goal's
## words): its size, the still's height, the badge's side, the name's and the foot's type.
const LOOK_TILE_R := Vector2(200, 236)
const LOOK_STILL_R := 128.0
const LOOK_BADGE_R := 100.0
const LOOK_NAME_PX := 18
const LOOK_FOOT_PX := 18
const LOOK_GOAL_PX := 16
## The round portrait's navy ring, the gold ring outside it on the one that is shown or worn, the dark disc behind a
## hero not owned and his "?" (the mock's #141b2b and #4a5670).
const RING_NAVY := 5.0
const RING_GOLD := 4.0
const UNKNOWN_DISC := Color("141b2b")
const UNKNOWN_MARK := Color("4a5670")

var hero: CharacterDef
## Not owned (pass 69): on sale or locked (TitleScreen._is_locked); the sheet reads Registry.hero_state for which.
var locked := false
var dim: ColorRect
var card: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var close_btn: WButton
var _touch: TouchScroll
var _fade: TextureRect
var _done := false
## pass 111 (lane SKINS): the header's badge and the Looks section (rebuilt when a look is worn or bought)
var _portrait: TextureRect
var _looks_v: VBoxContainer
var _dim_down := false
var _dim_from := Vector2.ZERO
## Pass 123: built the Royale way (the theme when it opened).


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
	_build_royale()
	return


## Paper from clear to whole, laid over the list's foot by _process while there is more below.
func _foot_fade() -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	# pass 123: the slate near the card's foot under Royale
	var fc := R_FADE
	g.colors = PackedColorArray([Color(fc, 0.0), Color(fc, 1.0)])
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

## The name as the title and the plaque write it: "The Drifter".
static func hero_name(c: CharacterDef) -> String:
	return ("The " + c.display_name) if c.id == "drifter" else c.display_name


## The name's size: as big as fits beside the portrait (Alfa Slab runs about 0.78 em a letter).
static func name_px(n: String) -> int:
	return clampi(int(560.0 / maxf(float(n.length()) * 0.78, 1.0)), 52, 84)


## One step in big numbers over its words: "+1%" over "CRIT CHANCE A LEVEL".
func _big(value: String, words: String, good: bool) -> Control:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 4)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(W.slab_text(value, 64, W.SAGE if good else W.BAD_DARK, HORIZONTAL_ALIGNMENT_LEFT, 0.0))
	c.add_child(W.label(words, 18, W.INK_SOFT, 0.12))
	return c


## A stat's value as the sheet shows it: a multiplier as a percent, everything else in TextGen's units.
static func stat_value(st: String, val: float) -> String:
	if st in MULTS:
		# as few decimals as it needs: Solenne's 101.5% debuff duration at level 1
		return TextGen._plain(val * 100.0) + "%"
	return TextGen.format_value(st, val)


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
		var word := "Favourite " + ("weapon" if fav is WeaponDef else ("card" if W.is_line(fav) else "item"))
		v.add_child(_item(fav, "favourite", word, _level_of(fav), _bonus_words(fav), sheet))
	for w: WeaponDef in own_weapons(hero):
		if w != start and w != fav:
			# pass 118 (lane ITEMS): anyone may find a hero's own weapon now
			v.add_child(_item(w, "own", "Signature weapon", 1, "", sheet))
	for m: MutationDef in Registry.hero_mutations(hero.id):
		var on := Registry.weapon(m.weapon)
		v.add_child(_item(m, "mutation", "Outlaw mutation · " + (on.display_name if on else m.weapon), 1, "", sheet))
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


## One item: its plate in the colour of the level he has it at, the role over its name, the card's words, the bonus.
func _item(def: ContentDef, role: String, word: String, level: int, bonus: String, sheet: StatSheet) -> Control:
	var h := HBoxContainer.new()
	h.name = "Item_%s_%s" % [role, def.id]
	h.add_theme_constant_override("separation", 26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := WPlate.new().for_def(def, PLATE, false, level)
	plate.icon_frac = 0.74
	# pass 69: a hero not owned: the item's black shape and a "?", its role only
	plate.mystery = locked
	if locked:
		word = word.get_slice(" · ", 0)
		level = 1
		bonus = ""
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var k := W.kind_of(def)
	col.add_child(W.label(word + ((" · " + W.lv(level)) if level > 1 else ""), 18, W.KIND_WORD.get(k, W.INK_SOFT), 0.12))
	col.add_child(W.text("?" if locked else def.display_name, W.slab(), 38, W.INK, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true))
	var d := W.serif_text("Unknown until this outlaw is yours." if locked else describe(def, level, sheet), 26, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
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
		return TextGen.perk_text(def as PerkDef)
	if def is MutationDef:
		return (def as MutationDef).text
	return def.flavour


# ---------------------------------------------------------------- the looks (pass 111, lane SKINS)

## The tiles again (a look worn or bought): the section's title stays, the rest is made anew.
func _fill_looks() -> void:
	if _looks_v == null:
		return
	_fill_looks_royale()
	return


## The look he wears in the sheet's terms: the worn skin, else the look every player owns.
func worn_code() -> String:
	var w := Registry.worn_skin(hero)
	return w if w != "" else hero.home_look()


## Where the player stands with look `code`: worn, owned, buyable or locked.
func look_state(code: String) -> String:
	return "worn" if code == worn_code() else Registry.skin_state(hero, code)


## A tile tapped: an owned look is worn, a look to buy asks first, a locked one only says so.
func _on_look(code: String) -> void:
	if _done:
		return
	match look_state(code):
		"worn":
			pass
		"owned":
			wear(code)
		"buyable":
			ask_buy_look(code)
		_:
			# pass 129 (lane TRAIL-UI): a skin a Trail node gives: the tap opens the Trail on its node
			if Nav.to_trail("skin", Registry.skin_key(hero.id, code)):
				return
			Audio.play("ui_locked")


## Wears look `code` from now on (the look every player owns = none kept): the badge above, the tiles, the title.
func wear(code: String) -> void:
	if Registry.skin_state(hero, code) != "owned":
		return
	Save.set_skin_worn(hero.id, "" if code == hero.home_look() else code)
	Analytics.track("skin_worn", {"hero": hero.id, "look": code})
	_after_look_change(code)


## A look on sale: with the price in the purse it asks (WConfirm); short of it, it only says so.
func ask_buy_look(code: String) -> void:
	if Registry.skin_state(hero, code) != "buyable":
		return
	var cur := Currency.of(hero.skin_currency(code))
	var price := hero.skin_price(code)
	if not Currency.can_afford(cur, price):
		Audio.play("ui_locked")
		return
	# pass 123: a purchase asks in green under Royale (Garry: "buying green"); Wanted's card as it was
	WConfirm.open(self, "Buy this skin?", "%s from your purse. %s wears it from then on." % [Currency.price_words(cur, price), hero_name(hero)],
		"Buy · %s" % W.num(price), "Not now", func(): buy_look(code), Callable(), "buy", WButton.price_parts(price, "BUY", R.MODAL_BUTTON_PX, cur))


## The purchase: paid through Currency (Save.buy_skin, the sink "skin"), worn at once, a burst over its tile.
func buy_look(code: String) -> bool:
	var cur := Currency.of(hero.skin_currency(code))
	var price := hero.skin_price(code)
	if not Save.buy_skin(hero, code):
		Audio.play("ui_locked")
		_fill_looks()
		return false
	Audio.play("ui_buy")
	Analytics.track("skin_bought", {"hero": hero.id, "look": code, "price": price, "currency": cur, "balance_after": Currency.balance(cur)})
	Save.set_skin_worn(hero.id, code)
	_after_look_change(code)
	var tile: Control = find_child("Look_" + code, true, false)
	if tile:
		WCelebrate.burst(self, tile.get_global_rect().get_center() - global_position, get_child_count(), 1.2)
	return true


func _after_look_change(code: String) -> void:
	if _portrait:
		_portrait.texture = Registry.played_look(hero).icon
	_fill_looks()
	look_changed.emit(code)


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


# ---------------------------------------------------------------- pass 123 (lane HEROES): the Royale pop-up

## The Royale card (see the header): the 80 % dim, the slate card R.MODAL_W wide from the top margin to the foot's, the
## list that scrolls by finger, CLOSE slate on the card's foot. Names as the Wanted sheet's.
func _build_royale() -> void:
	dim = W.dim(W.dim_color("modal"), true)
	dim.name = "Dim"
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", WConfirm.card_box())
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := (1080.0 - float(R.MODAL_W)) * 0.5
	card.offset_left = inset
	card.offset_right = -inset
	card.offset_top = R_TOP + W.safe_top()
	card.offset_bottom = -R_BOTTOM - float(R.PANEL_BASE)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
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
	body.add_child(_header_royale())
	if locked:
		body.add_child(_spacer(26.0))
		body.add_child(_locked_box_royale())
	_signature_royale()
	_stats_royale()
	_items_royale()
	# his looks (pass 111: a hero not owned sells none; a hero with one look has nothing to choose)
	if not locked and not Registry.skins_of(hero).is_empty():
		_looks_v = _section_royale("Skins", "Looks")
		_fill_looks_royale()
	body.add_child(_spacer(12.0))
	close_btn = WConfirm.make_button(["CLOSE"], WButton.SLATE, 96.0, 40)
	close_btn.name = "Close"
	close_btn.pressed.connect(close)
	v.add_child(close_btn)
	_touch = TouchScroll.new(scroll, true)
	_fade = _foot_fade()
	add_child(_fade)


## The top: his badge round in a navy ring, beside it his name in cream Ultra with DETAILS in the corner (the mock's),
## his slogan, and the trait as black pills ("TRAIT · LONG ROAD", "+1% crit chance per Level"); a hero not owned: his
## black badge with a "?", UNKNOWN, a "?" for the slogan and a LOCKED or ON SALE tag.
func _header_royale() -> Control:
	var h := HBoxContainer.new()
	h.name = "Head"
	h.add_theme_constant_override("separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait := royale_portrait(Registry.played_look(hero).icon, R_PORTRAIT, false, locked)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait = portrait.get_node("Badge")
	h.add_child(portrait)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var shown := "Unknown" if locked else hero_name(hero)
	var nm := W.text(shown.to_upper(), W.slab(), R_NAME_PX, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(R_NAME_PX))
	nm.name = "Name"
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var corner := W.label("Details", R_LABEL_PX, W.INK_SOFT)
	corner.name = "Corner"
	corner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(corner)
	# the room the name has: the card's inside less the portrait, the gap, the corner word and its gap
	var room := float(R.MODAL_W) - 2.0 * (R.MODAL_PAD.x + float(R.PANEL_EDGE)) - R_PORTRAIT - 30.0 - corner.get_combined_minimum_size().x - 16.0
	fit_text(nm, room, 36)
	var sl := W.serif_text("?" if locked else hero.flavour, R_SLOGAN_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true, false)
	sl.name = "Slogan"
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(sl)
	var pills := HFlowContainer.new()
	pills.name = "Pills"
	pills.add_theme_constant_override("h_separation", 12)
	pills.add_theme_constant_override("v_separation", 10)
	pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pills)
	if locked:
		var on_sale := Registry.hero_state(hero) == "buyable"
		pills.add_child(royale_tag("On sale" if on_sale else "Locked", "green" if on_sale else "red", 20))
		return h
	if hero.trait_name != "":
		pills.add_child(W.pill(("Trait · " + hero.trait_name).to_upper(), 20, R_PILL_H))
	for line: Array in trait_lines(hero):
		pills.add_child(W.pill([[str(line[0]), R.ROLES["green"]["top"] if bool(line[2]) else R.ROLES["red"]["top"], "bold"], " " + str(line[1])], R_PILL_PX, R_PILL_H))
	return h


## A hero not owned (Royale): what unlocks him and how far along it is, or, on sale, his price.
func _locked_box_royale() -> Control:
	var p := PanelContainer.new()
	p.name = "Locked"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", W.cell_box(Vector2(26, 20)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var q := Registry.quest_for("character", hero.id)
	if Registry.hero_state(hero) == "buyable":
		v.add_child(W.label("On sale", R_LABEL_PX, W.SAGE))
		var row := HBoxContainer.new()
		row.name = "Price"
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(WCoin.make(40.0, W.BRASS, 3.0, Currency.of(hero.currency_type)))
		var pr := W.slab_text(W.num(maxi(hero.price, 0)), 40, W.BRASS, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
		pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pr)
		v.add_child(row)
		var said := ("Requirement met: %s " % TextGen.quest_text(q)) if q else ""
		var t := W.serif_text(said + "Buy on the Outlaws screen.", 26, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
		t.color = R.WHITE
		v.add_child(t)
		return p
	v.add_child(W.label("To unlock", R_LABEL_PX, W.ROCK))
	# pass 129 (lane TRAIL-UI): an outlaw a Trail node gives reads "Reach Trail Level N"; a tap opens the Trail on it
	var trail_line := TrailScreen.requirement_line("outlaw", hero.id, 28)
	if trail_line:
		v.add_child(trail_line)
		return p
	var words := TextGen.quest_text(q) if q else "Not in the game yet."
	var wt := W.serif_text(words, 28, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	wt.color = R.WHITE
	v.add_child(WPoster.with_picture(q, wt, 40.0))
	if q:
		var pr2 := QuestTracker.progress(q)
		if pr2.y > 0:
			var bar := WBar.make(clampf(float(pr2.x) / float(pr2.y), 0.0, 1.0), W.BRASS, 36.0, 4, 0)
			bar.name = "Progress"
			bar.text = "%s / %s" % [W.num(mini(pr2.x, pr2.y)), W.num(pr2.y)]
			bar.text_px = 22
			v.add_child(bar)
	return p


## SIGNATURE STAT (Royale): the rule in words only (Garry: "the trait rule in words only"; no level 1 / 10 / 20 / 40 row).
func _signature_royale() -> void:
	var title := ("Signature stat · " + hero.trait_name) if hero.trait_name != "" and not locked else "Signature stat"
	var v := _section_royale(title, "Signature")
	if locked:
		var u := W.text("?", W.slab(), 64, W.INK_SOFT)
		u.name = "Unknown"
		v.add_child(u)
		return
	var rule := W.serif_text(rule_words(hero), R_RULE_PX, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	rule.color = R.WHITE
	rule.name = "Rule"
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(rule)


## The rule in words as the sheet writes it ("per Level", Garry's wording).
static func rule_words(c: CharacterDef) -> String:
	return TextGen.hero_trait(c).replace(" per level", " per Level")


## STATS · A RUN'S START (Royale): the mock's two columns of 56 px rows, his signature stats green, the note under them.
func _stats_royale() -> void:
	var ups := _has_upgrades()
	var v := _section_royale("Stats · a run's start" + (", your upgrades in" if ups else ""), "Stats")
	var sheet: StatSheet = Run.hero_sheet(hero, 1)
	var mine := signature_stats(hero)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", R_STAT_GAP)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for st: String in STATS:
		grid.add_child(_stat_cell_royale(st, "?" if locked else stat_value(st, sheet.get_stat(st)), st in mine and not locked))
	v.add_child(grid)
	var words := "Every number is unknown until this outlaw is yours." if locked else ("Signature stat in green. " + (
		"Your Upgrade board ranks are counted in." if ups else "Ranks on the Upgrade board add to these."))
	var note := W.serif_text(words, R_NOTE_PX, W.INK_SOFT, 400, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true, false)
	note.name = "Note"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(note)


## The stats his signature raises (and max HP for a heal on every level-up): drawn green.
static func signature_stats(c: CharacterDef) -> Array:
	var mine: Array = []
	for e in c.level_trait:
		if e is Effect:
			mine.append((e as Effect).stat)
	if c.level_heal > 0.0:
		mine.append("max_hp")
	return mine


## One stat row (Royale): its name in Rubik, its value in Ultra, white (green for a signature stat), a faint line under.
func _stat_cell_royale(st: String, value: String, mine: bool) -> Control:
	var p := PanelContainer.new()
	p.name = "Stat_" + st
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size.y = R_STAT_H
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0)
	b.border_width_bottom = 2
	b.border_color = Color(1, 1, 1, 0.1)
	p.add_theme_stylebox_override("panel", b)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var col: Color = R.ROLES["green"]["top"] if mine else R.WHITE
	var words := TextGen.stat_name(st)
	var n := W.serif_text(words.substr(0, 1).to_upper() + words.substr(1), R_STAT_NAME_PX, W.INK, 400, false,
		HORIZONTAL_ALIGNMENT_LEFT, 0.0, true, false)
	n.color = col
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	var val := W.slab_text(value, R_STAT_VALUE_PX, W.INK, HORIZONTAL_ALIGNMENT_RIGHT, float(R_STAT_VALUE_PX))
	R.no_edge(val)
	val.color = col
	val.name = "Value"
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(val)
	return p


## HIS ITEMS (Royale): every item of items_of on its frame with its kind, its name and its words.
func _items_royale() -> void:
	var v := _section_royale((TextGen.possessive(hero) + " items") if not locked else "Items", "Items")
	v.add_theme_constant_override("separation", 26)
	var sheet: StatSheet = Run.hero_sheet(hero, 1)
	for it: Dictionary in items_of(hero):
		v.add_child(royale_item_row(it, sheet, locked, R_ITEM_FRAME, R_ITEM_NAME_PX, R_ITEM_TEXT_PX, R_ITEM_LABEL_PX))


## LOOKS (Royale): "LOOKS · n OF m OWNED", what he wears, and the Heroes screen's tiles, R_LOOK_COLS a row.
func _fill_looks_royale() -> void:
	if _looks_v == null:
		return
	for k in range(_looks_v.get_child_count() - 1, -1, -1):
		var c := _looks_v.get_child(k)
		_looks_v.remove_child(c)
		c.queue_free()
	var codes: Array = Registry.skins_of(hero)
	var worn := worn_code()
	var owned := 0
	var to_earn := false
	for code: String in codes:
		var st := look_state(code)
		if st == "worn" or st == "owned":
			owned += 1
		if Registry.skin_state(hero, code) != "owned":
			to_earn = true
	_looks_v.add_child(W.label("Skins · %d of %d owned" % [owned, codes.size()], R_LABEL_PX, W.INK_SOFT))
	var how := "Reach a skin's goal, then buy it." if to_earn else "Tap a skin to wear it."
	var line := W.serif_text("Wearing %s. %s" % [hero.skin_name(worn), how], 24, W.INK_SOFT, 400, true,
		HORIZONTAL_ALIGNMENT_LEFT, 0.0, true, false)
	line.name = "Wearing"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_looks_v.add_child(line)
	var grid := GridContainer.new()
	grid.name = "LookGrid"
	grid.columns = R_LOOK_COLS
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 26)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for code: String in codes:
		var t := royale_look_tile(hero, code, worn)
		t.pressed.connect(func(): _on_look(code))
		grid.add_child(t)
	_looks_v.add_child(grid)


## A labelled part of the Royale card: the gap, then a box with its label; returns the box its rows go in.
func _section_royale(title: String, node_name: String) -> VBoxContainer:
	body.add_child(_spacer(R_SECTION_GAP))
	var v := VBoxContainer.new()
	v.name = node_name
	v.add_theme_constant_override("separation", 14)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(W.label(title, R_LABEL_PX, W.INK_SOFT))
	body.add_child(v)
	return v


# ---------------------------------------------------------------- pass 123: the pieces the Heroes screen shares

## The trait as lines (the Heroes screen's TRAIT panel, the pop-up's pills): [step, words, good] for each signature stat
## ("+1%", "crit chance per Level") and for a heal on every level-up; [] for a hero without a level trait (trait_note
## then carries his trait's words).
static func trait_lines(c: CharacterDef) -> Array:
	var out: Array = []
	if c == null:
		return out
	for e in c.level_trait:
		if e is Effect:
			var x: Effect = e
			out.append([TextGen.hero_step(x), TextGen.hero_word(x.stat) + " per Level", _good(x.stat, x.value)])
	if c.level_heal > 0.0:
		out.append(["+" + TextGen._plain(c.level_heal * 100.0) + "%", "max HP healed every level-up", true])
	return out


## What the rule adds to its lines (TextGen.hero_trait's brackets and a hero's own mechanism after it), "" when nothing;
## a hero without a level trait: his trait's words whole.
static func trait_note(c: CharacterDef) -> String:
	if c == null:
		return ""
	if c.level_trait.is_empty():
		return TextGen.hero_trait(c)
	var notes: Array = []
	for e in c.level_trait:
		if e is Effect:
			var x: Effect = e
			var word := TextGen.hero_word(x.stat)
			if StatSheet.STAT_FLOORS.has(x.stat):
				notes.append("%s never under %s" % [word, TextGen.hero_amount(x.stat, "add", float(StatSheet.STAT_FLOORS[x.stat]))])
			if TextGen.HERO_NOTES.has(x.stat):
				notes.append(str(TextGen.HERO_NOTES[x.stat]).replace("{his}", TextGen.possessive(c)))
	var s := ""
	if not notes.is_empty():
		var j := "; ".join(notes)
		s = j.substr(0, 1).to_upper() + j.substr(1) + "."
	if c.trait_text != "" and not c.specials.is_empty():
		s = (s + " " + c.trait_text).strip_edges()
	return s


## The hero's favourite: his weapon, else the line or passive he favours.
static func favourite_of(c: CharacterDef) -> ContentDef:
	if c == null:
		return null
	var w: WeaponDef = Registry.weapon(c.favourite_weapon) if c.favourite_weapon != "" else null
	if w:
		return w
	return Registry.passive(c.favourite_passive) if c.favourite_passive != "" else null


## The level he has an item at when he lands with it or finds it (TitleScreen.start_level: a favourite's bonus level).
static func level_of(c: CharacterDef, def: ContentDef) -> int:
	var ts: Script = load("res://ui/TitleScreen.gd")
	return int(ts.call("start_level", c, def))


## What finding the favourite gives, in Garry's words for the Heroes screen ("finding it gives a bonus level"): "Finding
## it in a run gives it a bonus level." (two levels: "2 bonus levels"; full: "every level at once"; effects: "... gives it
## +20% area of effect.").
static func bonus_line(c: CharacterDef, def: ContentDef) -> String:
	var b: Dictionary = c.favourite_bonus if def is WeaponDef else c.favourite_passive_bonus
	match str(b.get("type", "")):
		"level":
			var n := int(b.get("value", 1)) - 1
			if n <= 0:
				return ""
			return "Finding it in a run gives it a bonus level." if n == 1 else "Finding it in a run gives it %d bonus levels." % n
		"max":
			return "Finding it in a run gives it every level at once."
		"effects":
			return "Finding it in a run gives it %s." % TextGen.describe_effects(b.get("effects", []))
	return ""


## His items as the Heroes screen and the pop-up list them: the weapon he lands with, his favourite and what finding it
## gives, any other weapon only he finds, his hero mutations, his perks. Each {def, role (start, favourite, own, mutation,
## perk), word, level, bonus}. Pass 126 (lane UI; Garry: "Why is the Evolution Item shown as part of Heroes unique items?
## Make it so this isn't shown, it's not unique to them everyone gets this now"): the list ended on the evolution of the
## weapon he lands with whenever WeaponDef.hero named him (pass 123), a rule from before pass 118 let anyone find such a
## weapon (`guest_weight`). It is gone from both lists; the Collection's item page still tells how a weapon evolves.
static func items_of(c: CharacterDef) -> Array:
	var out: Array = []
	if c == null:
		return out
	var start := Registry.start_weapon_for(c)
	var fav: ContentDef = favourite_of(c)
	if start:
		out.append({"def": start, "role": "start", "word": "Start weapon" + (" · favourite" if start == fav else ""),
			"level": level_of(c, start), "bonus": bonus_line(c, start) if start == fav else ""})
	if fav and fav != start:
		var word := "Favourite " + ("weapon" if fav is WeaponDef else ("card" if W.is_line(fav) else "item"))
		out.append({"def": fav, "role": "favourite", "word": word, "level": level_of(c, fav), "bonus": bonus_line(c, fav)})
	for w: WeaponDef in own_weapons(c):
		if w != start and w != fav:
			out.append({"def": w, "role": "own", "word": "Signature weapon", "level": 1})
	for m: MutationDef in Registry.hero_mutations(c.id):
		var on := Registry.weapon(m.weapon)
		out.append({"def": m, "role": "mutation", "word": "Outlaw mutation · " + (on.display_name if on else m.weapon), "level": 1})
	for pk: PerkDef in Registry.perks_of(c.id):
		out.append({"def": pk, "role": "perk", "word": "Perk", "level": 1})
	return out


## One item (Royale): its frame (WPlate: the rarity or level colour), the kind over its name on one line, the level-up
## card's words, the favourite's bonus in green; a hero not owned: the item's black shape, its role and a "?".
## Named "Item_<role>_<id>".
static func royale_item_row(it: Dictionary, sheet: StatSheet, unknown: bool, frame_px: float, name_px: int, text_px: int,
		label_px: int) -> Control:
	var def: ContentDef = it["def"]
	var role := str(it.get("role", ""))
	var word := str(it.get("word", ""))
	var level := int(it.get("level", 1))
	var bonus := str(it.get("bonus", ""))
	var words := "Unknown until this outlaw is yours." if unknown else describe(def, level, sheet)
	if unknown:
		word = word.get_slice(" · ", 0)
		level = 1
		bonus = ""
	var h := HBoxContainer.new()
	h.name = "Item_%s_%s" % [role, def.id]
	h.add_theme_constant_override("separation", 16 if frame_px < 100.0 else 26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := WPlate.new().for_def(def, frame_px, false, level)
	plate.name = "Frame"
	plate.mystery = unknown
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	var head := HFlowContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("h_separation", 12)
	head.add_theme_constant_override("v_separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	# the mock's kind words are all the secondary blue (gold is kept for what acts at once, coins, stars and Legendary)
	var kind_col: Color = W.INK_SOFT
	var lab := W.label(word + ((" · " + W.lv(level)) if level > 1 else ""), label_px, kind_col)
	lab.name = "Kind"
	lab.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(lab)
	var nm := W.text("?" if unknown else def.display_name, W.slab(), name_px, W.INK, HORIZONTAL_ALIGNMENT_LEFT, float(name_px))
	nm.name = "ItemName"
	nm.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(nm)
	var d := W.serif_text(words, text_px, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true)
	d.name = "Text"
	d.color = R.WHITE
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(d)
	if bonus != "":
		var bw := W.serif_text(bonus, text_px - 2, W.SAGE, 600, true, HORIZONTAL_ALIGNMENT_LEFT, 0.0, true, false)
		bw.name = "Bonus"
		bw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(bw)
	return h


## A hero's (or a look's) round badge `px` across in a navy ring (the mock's portraits), a gold ring outside it when
## `gold` (the hero shown, the look worn); `unknown`: a black silhouette on the mock's dark disc, with a "?" when `mark`.
## Named "Portrait" ("Badge" the picture, "Ring", "Mark"); the gold ring follows set_meta("gold", on) + queue_redraw on
## "Ring".
static func royale_portrait(tex: Texture2D, px: float, gold: bool = false, unknown: bool = false, mark: bool = true) -> Control:
	var holder := Control.new()
	holder.name = "Portrait"
	holder.custom_minimum_size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta("gold", gold)
	holder.set_meta("unknown", unknown)
	if unknown:
		holder.draw.connect(func() -> void:
			holder.draw_circle(holder.size * 0.5, minf(holder.size.x, holder.size.y) * 0.5 - 1.0, UNKNOWN_DISC, true, -1.0, true))
	var tr := TextureRect.new()
	tr.name = "Badge"
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unknown:
		tr.self_modulate = Color(0, 0, 0, 0.85)
	holder.add_child(tr)
	if unknown and mark:
		var q := W.text("?", W.slab(), maxi(int(px * 0.54), R.ULTRA_MIN), UNKNOWN_MARK, HORIZONTAL_ALIGNMENT_CENTER)
		R.no_edge(q)
		q.name = "Mark"
		q.valign = VERTICAL_ALIGNMENT_CENTER
		q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(q)
	var ring := Control.new()
	ring.name = "Ring"
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func() -> void:
		var c := ring.size * 0.5
		var r := minf(ring.size.x, ring.size.y) * 0.5
		ring.draw_arc(c, r - RING_NAVY * 0.5, 0.0, TAU, 64, R.NAVY, RING_NAVY, true)
		if bool(holder.get_meta("gold", false)):
			ring.draw_arc(c, r + RING_GOLD * 0.5, 0.0, TAU, 64, R.GOLD_TEXT, RING_GOLD, true))
	holder.add_child(ring)
	return holder


## A small tag (Royale; README "Tag": a 4 px radius, a 3 px navy edge, Rubik 700 by Garry's 28 px rule): `kind` gold,
## green, red, slate or locked (the grey of a price the purse cannot meet); a coin `coin` px before the word when > 0.
## Named "Tag" ("Word" the text).
static func royale_tag(t: String, kind: String, px: int = R.TAG_PX, coin: float = 0.0, currency: String = "gold") -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Tag"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill: Color = R.role("slate")["top"]
	var ink: Color = R.CREAM
	match kind:
		"gold":
			fill = R.TAG_GOLD
			ink = R.NAVY
		"green":
			fill = R.TAG_GREEN
			ink = R.NAVY
		"red":
			fill = R.TAG_RED
		"locked":
			fill = R.role("locked")["bottom"]
			# pass 126 (lane UI): pass 124's short price on the tag too: the grey with the amount in red
			ink = R.SHORT_INK
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = R.NAVY
	sb.set_border_width_all(R.TAG_EDGE)
	sb.set_corner_radius_all(R.RADIUS_TAG)
	sb.anti_aliasing = true
	sb.content_margin_left = 10.0 + R.TAG_EDGE
	sb.content_margin_right = 10.0 + R.TAG_EDGE
	sb.content_margin_top = 3.0 + R.TAG_EDGE
	sb.content_margin_bottom = 3.0 + R.TAG_EDGE
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	if coin > 0.0:
		var cn := WCoin.make(coin, W.BRASS if kind != "locked" else W.AGED, 3.0, currency)
		cn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cn)
	var w := W.text(t.to_upper(), R.body(R.LABEL_WEIGHT, false, W.em(px, 0.05)), px, ink, HORIZONTAL_ALIGNMENT_LEFT, roundf(px * 1.15))
	w.color = ink
	w.name = "Word"
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(w)
	return p


## The look hero `c` wears in the sheet's terms (the worn skin, else the look every player owns; "" for one art).
static func worn_of(c: CharacterDef) -> String:
	var w := Registry.worn_skin(c)
	return w if w != "" else c.home_look()


## Where the player stands with look `code` of `c`: worn, owned, buyable or locked (look_state's rule, static).
static func look_state_of(c: CharacterDef, code: String) -> String:
	return "worn" if code == worn_of(c) else Registry.skin_state(c, code)


## One look's tile (Royale; the mock 5_Heroes' LOOKS strip): the slate tile, the look's full-body still
## (tools/skin_stills.py) or its badge round in a navy ring, its name, and where the player stands with it: WORN (the
## gold edge and a gold tag), WEAR (slate), the price (a green tag with the coin; short of it the grey tag and "n short"
## in red) or LOCKED (the still a black silhouette, the goal in the quests' words and how far along it is). Named
## "Look_<CODE>" ("Look_base" for a hero with one art), metas "look" and "state"; "Picture" > "Still" / "Portrait",
## "LookName", "Foot" > "Tag" / "Price" / "Short" / "Goal" / "Progress". The caller wires `pressed`.
static func royale_look_tile(c: CharacterDef, code: String, worn: String, tile: Vector2 = LOOK_TILE_R) -> WTap:
	var st := "worn" if code == worn else Registry.skin_state(c, code)
	var t := WTap.new()
	t.name = "Look_" + (code if code != "" else "base")
	t.set_meta("look", code)
	t.set_meta("state", st)
	t.custom_minimum_size = tile
	t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var e := R.PANEL_EDGE
	var b := W.box(W.PAPER, e, R.PANEL_BASE).pad(10 + e, 12 + e, 10 + e, 10 + e)
	if st == "worn":
		b.inner = 5
		b.inner_color = W.BRASS
	t.box = b
	t.box_down = b.pressed()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(v)
	var pic := CenterContainer.new()
	pic.name = "Picture"
	pic.custom_minimum_size = Vector2(0, LOOK_STILL_R)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var still := c.look_still_path(code)
	if still != "":
		var tr := TextureRect.new()
		tr.name = "Still"
		tr.texture = load(still) as Texture2D
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(tile.x - 28.0, LOOK_STILL_R)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if st == "locked":
			# pass 113 (Garry: "when the Skin is LOCKED it displays the Skin Icon as a Darkened Silhouette")
			tr.self_modulate = Color(0, 0, 0, 0.9)
		pic.add_child(tr)
	else:
		pic.add_child(royale_portrait(c.variant_def(code).icon, LOOK_BADGE_R, st == "worn", st == "locked", false))
	var nm := W.text(c.skin_name(code).to_upper(), R.body(R.LABEL_WEIGHT, false, W.em(LOOK_NAME_PX, 0.08)), LOOK_NAME_PX, W.INK,
		HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	nm.color = R.WHITE
	nm.name = "LookName"
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fit_text(nm, tile.x - 28.0, 14)
	v.add_child(nm)
	var foot := VBoxContainer.new()
	foot.name = "Foot"
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(foot)
	match st:
		"worn":
			foot.add_child(royale_tag("Worn", "gold", LOOK_FOOT_PX))
		"owned":
			foot.add_child(royale_tag("Wear", "slate", LOOK_FOOT_PX))
		"buyable":
			var cur := Currency.of(c.skin_currency(code))
			var price := c.skin_price(code)
			var can := Currency.can_afford(cur, price)
			var tag := royale_tag(W.num(price), "green" if can else "locked", LOOK_FOOT_PX, 20.0, cur)
			tag.name = "Price"
			foot.add_child(tag)
			if not can:
				var sh := W.short_text(price - Currency.balance(cur), 16)
				sh.align = HORIZONTAL_ALIGNMENT_CENTER
				sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				foot.add_child(sh)
		_:
			var words := Registry.skin_requirement_text(c, code)
			# pass 129 (lane TRAIL-UI): a Trail line carries its chevron (the tile's tap opens the Trail)
			if words != "" and Trail.gated("skin", Registry.skin_key(c.id, code)) and R.body().has_char(0x203A):
				words += " ›"
			var g := W.serif_text(words if words != "" else "Not on sale yet.", LOOK_GOAL_PX, W.INK_SOFT, 400, false,
				HORIZONTAL_ALIGNMENT_CENTER, roundf(LOOK_GOAL_PX * 1.25), true)
			g.name = "Goal"
			g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			foot.add_child(g)
			var q := Registry.skin_quest(c, code)
			var pr := QuestTracker.progress(q) if q else Vector2i.ZERO
			if pr.y > 0:
				var bar := WBar.make(clampf(float(pr.x) / float(pr.y), 0.0, 1.0), W.BRASS, 12.0, 2, 0)
				bar.name = "Progress"
				foot.add_child(bar)
	return t


## Shrinks a one-line WText until it fits `max_w`, never under `min_px` (a long name in a fixed room); the navy edge of
## display type follows the size.
static func fit_text(t: WText, max_w: float, min_px: int) -> void:
	if max_w <= 0.0:
		return
	var px := t.font_size
	while px > min_px and t.text_width() + float(t.stroke) * 2.0 > max_w:
		# a line box at line-height 1 (display type) shrinks with the type; any other keeps its height
		if is_equal_approx(t.line_height, float(px)):
			t.line_height = float(px - 2)
		px -= 2
		t.font_size = px
	if t.stroke > 0 and R.is_display(t.font) and px >= R.ULTRA_MIN:
		R.edge(t, px, t.color.is_equal_approx(R.GOLD_TEXT))


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
		# pass 111 (lane SKINS): a look's question goes first
		if not WConfirm.dismiss(self):
			close()
		return
	if _touch and not WConfirm.is_open(self):
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
