## Pass 54, the UI lane (Garry's tenth list): the pause Options' room for the slider thumbs and its floating text
## switches, the damage numbers in Bitter 800, the mutation offer's pre-reel (WWeaponReel) before its head and cards,
## the rainbow XP rail and the bigger level-up reveal, the boss's MUTATION CHEST in purple, the kind glyphs on the cards'
## and the chest's plates, bold numbers in body text, Phoenix Feather's flight and banner as it stands him up and its
## "(used)" Build row, and the debug switch for the ranged weapons' on-screen aim.
extends GdUnitTestSuite

## New class_names are known once the lead imports: by path here.
const ReelScript := preload("res://ui/wanted/WWeaponReel.gd")

var _keep := {}


func before_test() -> void:
	_keep = {"damage_numbers": Settings.damage_numbers, "float_heal": Settings.float_heal, "float_xp": Settings.float_xp,
		"float_coins": Settings.float_coins, "float_size": Settings.float_size, "debug_mode": Settings.debug_mode,
		"sfx_volume": Settings.sfx_volume, "music_volume": Settings.music_volume}
	if "ranged_on_screen" in Settings:
		_keep["ranged_on_screen"] = Settings.get("ranged_on_screen")


func after_test() -> void:
	for k in _keep:
		Settings.set(k, _keep[k])
	Settings.top_inset = -1
	Run.arena = false
	Run.end()
	DamageNumbers.I = null


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _card(type: String, def: ContentDef, from: int = 0, to: int = 1) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			s += (n as WText).text + " "
	return s


func _celebrations(host: Node) -> Array:
	return host.get_children().filter(func(n: Node) -> bool: return n is WCelebrate and not n.is_queued_for_deletion())


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


# ---------------------------------------------------------------- 1. the pause Options' room for the thumbs

func test_the_options_list_has_room_for_the_thumbs() -> void:
	_start()
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	ps._tab = 2
	ps._refresh()
	ps.visible = true
	await _frames(4)
	var kids := ps._content.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	assert_str(str(kids[0].name)).is_equal("OptionsTop")
	assert_str(str(kids[kids.size() - 1].name)).is_equal("OptionsBottom")
	assert_float((kids[0] as Control).custom_minimum_size.y).is_equal(float(PauseScreen.OPT_TOP))
	assert_float((kids[kids.size() - 1] as Control).custom_minimum_size.y).is_equal(float(PauseScreen.OPT_BOTTOM))
	assert_int(PauseScreen.OPT_TOP).is_equal(28)
	assert_int(PauseScreen.OPT_BOTTOM).is_equal(36)
	# the board gives its padding up to them, so the rows stay where they were (40 over the list, 45 under)
	var st: StyleBox = ps._board.get_theme_stylebox("panel")
	assert_float(st.content_margin_top + PauseScreen.OPT_TOP).is_equal(40.0)
	assert_float(st.content_margin_bottom + PauseScreen.OPT_BOTTOM).is_equal(45.0)
	# the slider rows end 52 px short of the list's edge and start 8 in
	for row_name in ["SliderRowSound", "SliderRowMusic"]:
		var row: MarginContainer = ps.find_child(row_name, true, false)
		assert_object(row).override_failure_message(row_name).is_not_null()
		assert_int(row.get_theme_constant("margin_right")).is_equal(PauseScreen.SLIDER_RIGHT)
		assert_int(row.get_theme_constant("margin_left")).is_equal(PauseScreen.SLIDER_LEFT)
	# both thumbs whole inside the list's clip, at the top value and at nothing, with their 5 px shadow
	var clip := ps._scroll.get_global_rect()
	for row_name in ["SliderRowSound", "SliderRowMusic"]:
		var sl: WSlider = (ps.find_child(row_name, true, false) as Node).find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is WSlider)[0]
		for frac in [0.0, 1.0]:
			var track := Rect2(0, (sl.size.y - WSlider.TRACK_H - 8.0) * 0.5, sl.size.x, WSlider.TRACK_H + 8.0)
			var inner := track.grow(-4.0)
			var tx := maxf(inner.position.x + inner.size.x * frac - 40.0, inner.position.x - 4.0)
			var th := Rect2(Vector2(tx, track.position.y - 20.0), WSlider.THUMB).grow_individual(0, 0, 5, 5)
			var g := Rect2(sl.get_global_transform() * th.position, th.size)
			assert_bool(clip.encloses(g)).override_failure_message("%s thumb at %d: %s outside %s" % [row_name, int(frac * 100), str(g), str(clip)]).is_true()
	ps.visible = false


# ---------------------------------------------------------------- 2. floating text in the pause Options

func test_the_pause_options_carry_the_floating_text_switches() -> void:
	_start()
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	ps._tab = 2
	ps._refresh()
	await _frames(2)
	for spec in PauseScreen.FLOAT_SWITCHES:
		var sw: WSwitch = ps.find_child(str(spec[2]), true, false)
		assert_object(sw).override_failure_message(str(spec[2])).is_not_null()
		var key: String = spec[1]
		Settings.set(key, true)
		sw.toggled.emit(false)
		assert_bool(bool(Settings.get(key))).override_failure_message(key).is_false()
		sw.toggled.emit(true)
		assert_bool(bool(Settings.get(key))).is_true()
	var size_choice: WChoice = ps.find_child("FloatSize", true, false)
	assert_object(size_choice).is_not_null()
	size_choice.chosen.emit(2)
	assert_int(Settings.float_size).is_equal(2)
	size_choice.chosen.emit(0)
	assert_int(Settings.float_size).is_equal(0)
	assert_str(_texts(ps._content)).contains("FLOATING TEXT")
	ps.visible = false


# ---------------------------------------------------------------- 2b. the damage numbers' face

func test_the_damage_numbers_are_bitter_800_a_tenth_up() -> void:
	var dn := DamageNumbers.new()
	add_child(dn)
	auto_free(dn)
	assert_object(dn._font).is_same(W.serif(800))
	assert_int(DamageNumbers.WEIGHT).is_equal(800)
	assert_array([DamageNumbers.PX, DamageNumbers.PX_CRIT, DamageNumbers.PX_MINI, DamageNumbers.PX_TICK, DamageNumbers.PX_HURT,
		DamageNumbers.PX_HEAL, DamageNumbers.PX_WORD]).is_equal([52, 78, 64, 44, 58, 52, 44])
	assert_float(DamageNumbers.OUTLINE_FRAC).is_equal_approx(0.28, 0.0001)
	assert_bool(DamageNumbers.SHADOW.is_equal_approx(Vector2(2, 3))).is_true()


# ---------------------------------------------------------------- 3. the mutation pre-reel

func test_the_reel_lands_on_the_chosen_weapon() -> void:
	var a: WeaponDef = Registry.weapon("boomstick")
	var b: WeaponDef = Registry.weapon("peashooter")
	var c: WeaponDef = Registry.weapon("molotov")
	var reel = auto_free(ReelScript.new())
	add_child(reel)
	reel.center = Vector2(540, 300)
	var got := [false]
	reel.done.connect(func(): got[0] = true)
	reel.play([a, b, c], b, 0.3)
	assert_bool(reel.is_landed()).is_false()
	var waited := 0.0
	while waited < 3.0 and not got[0]:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	assert_bool(got[0]).is_true()
	assert_bool(reel.is_landed()).is_true()
	var land: int = reel.landing_cell()
	assert_object(reel._defs[land]).is_same(b)
	# the cells either side of the landing are never the chosen one itself
	assert_object(reel._defs[land - 1]).is_not_same(b)
	assert_object(reel._defs[land + 1]).is_not_same(b)
	# it ticked on its way and stopped with the chosen plate in the window
	assert_int(reel.ticks).is_greater(0)
	var p: WPlate = reel._plates[land]
	assert_bool((p.position + Vector2(ReelScript.CELL, ReelScript.CELL) * 0.5).distance_to(reel.center) < 1.0).is_true()
	# a tick for every plate that reaches the window
	var t0: int = reel.ticks
	reel._last_cell = 0
	for k in range(1, 6):
		reel._set_x(k * ReelScript.STEP)
	assert_int(reel.ticks - t0).is_equal(5)
	# the strip runs at least MIN_CELLS plates and TAIL more past the landing
	assert_int(reel._defs.size()).is_greater_equal(ReelScript.MIN_CELLS + ReelScript.TAIL)


func test_a_single_weapon_wobbles_and_lands_and_a_tap_skips() -> void:
	var a: WeaponDef = Registry.weapon("boomstick")
	var reel = auto_free(ReelScript.new())
	add_child(reel)
	reel.play([a], a, 1.5)
	assert_bool(reel._single).is_true()
	var waited := 0.0
	while waited < 2.0 and not reel.is_finished():
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	assert_bool(reel.is_finished()).is_true()
	assert_float(waited).is_less(ReelScript.WOBBLE + ReelScript.HOLD + 0.5)
	# a long spin, skipped by a tap: straight to the landing, then a second tap goes on at once
	var b: WeaponDef = Registry.weapon("peashooter")
	var reel2 = auto_free(ReelScript.new())
	add_child(reel2)
	var fired := [0]
	reel2.done.connect(func(): fired[0] += 1)
	reel2.play([a, b], a, 5.0)
	reel2.skip()
	assert_bool(reel2.is_landed()).is_true()
	assert_object(reel2._defs[reel2.landing_cell()]).is_same(a)
	assert_int(fired[0]).is_equal(0)
	reel2.skip()
	assert_int(fired[0]).is_equal(1)
	reel2.skip()
	assert_int(fired[0]).is_equal(1)


func test_the_mutation_offer_runs_the_reel_before_its_head_and_cards() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	var w: WeaponInstance = Run.weapon_instance("peashooter")
	var offer := CardPool.path_offer(w)
	assert_bool(offer.is_empty()).is_false()
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer(offer, "MUTATION", false, true)
	assert_bool(cs.reel_running()).is_true()
	assert_object(cs._reel.chosen).is_same(w.def)
	# over the dim and the rail, under the header
	assert_int(cs._reel.get_index()).is_equal(2)
	assert_bool(cs._list.visible).is_false()
	assert_bool(cs._path_skip.visible).is_false()
	assert_float(cs._path_name.modulate.a).is_equal(0.0)
	# the reel runs past the weapons with an open path, both held here
	var defs: Array = CardScreen.reel_weapons().map(func(x): return x.def if x is WeaponInstance else x)
	assert_bool(defs.has(w.def)).is_true()
	assert_bool(defs.has(Registry.weapon("boomstick"))).is_true()
	# a tap lands it, a second goes on: the head, the cards and the skip come
	cs.skip_reel()
	assert_bool(cs.reel_running()).is_false()
	assert_bool(cs._list.visible).is_true()
	assert_bool(cs._path_skip.visible).is_true()
	assert_float(cs._path_name.modulate.a).is_equal(1.0)
	assert_int(cs._cards.size()).is_equal(offer.size())
	# the rail shows the run's XP on a mutation offer
	assert_float(cs.rail_frac()).is_equal_approx(clampf(Run.xp / maxf(Run.xp_to_next(), 1.0), 0.0, 1.0), 0.0001)
	# a skip mid-reel closes on nothing and leaves no reel behind
	cs.show_offer(CardPool.path_offer(w), "MUTATION", false, true)
	assert_bool(cs.reel_running()).is_true()
	cs._skip()
	assert_bool(cs.visible).is_false()
	assert_object(cs._reel).is_null()
	await _frames(2)


# ---------------------------------------------------------------- 4. the rainbow rail and the bigger reveal

func test_a_level_up_draws_a_full_rainbow_rail_and_celebrates_more() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	var rail: Control = cs.find_child("XpRail", false, false)
	assert_object(rail).is_not_null()
	# over the dim, under the header and the cards
	assert_int(rail.get_index()).is_less(cs.header.get_index())
	assert_bool(cs.get_child(0) == cs.dim).is_true()
	cs.show_offer(CardPool.level_up_offer(3), "LEVEL 2!", false)
	assert_float(cs.rail_frac()).is_equal(1.0)
	# its hues race along it: red at the start, cyan halfway, and the whole band moves with time
	assert_float(CardScreen.rail_colour(0.0, 0.0).h).is_equal_approx(0.0, 0.01)
	assert_float(CardScreen.rail_colour(0.5, 0.0).h).is_equal_approx(0.5, 0.01)
	assert_float(CardScreen.rail_colour(0.0, 0.25).h).is_equal_approx(0.3, 0.01)
	assert_float(CardScreen.rail_colour(0.3, 0.0).s).is_equal_approx(0.85, 0.01)
	# the sun badge and a strong burst at once, a second burst BURST_GAP later
	var now := _celebrations(cs)
	assert_int(now.size()).is_equal(2)
	var strong: Array = now.filter(func(c) -> bool: return c._sun_r <= 0.0)
	assert_int(strong.size()).is_equal(1)
	assert_int(strong[0].rays()).is_equal(WCelebrate.RAYS_STRONG)
	assert_int(strong[0].bits()).is_equal(WCelebrate.BITS_STRONG)
	assert_int(WCelebrate.RAYS_STRONG).is_equal(18)
	assert_int(WCelebrate.BITS_STRONG).is_equal(64)
	await get_tree().create_timer(WCelebrate.BURST_GAP + 0.1).timeout
	assert_int(_celebrations(cs).size()).is_equal(3)
	# the whole reveal is over inside 2 s
	assert_float(WCelebrate.LIFE + WCelebrate.BURST_GAP).is_less(2.1)
	# the cards drop in from above, one after another
	assert_float(CardScreen.DROP_PX).is_equal(40.0)
	assert_float(CardScreen.DROP_GAP).is_equal(0.05)
	cs.visible = false
	await _frames(2)


# ---------------------------------------------------------------- 5. the mutation chest's header

func test_the_boss_chest_reads_mutation_chest_in_purple_and_resets() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await _frames(1)
	var roll := Run.chest_roll(true)
	assert_str(str(roll.get("type", ""))).is_equal("mutation")
	cs.open(roll)
	assert_str(cs.header.title.text).is_equal("MUTATION CHEST")
	assert_bool(cs.header.title.color.is_equal_approx(W.TOAST_PURPLE)).is_true()
	assert_str(cs.header.star_line.text()).is_equal("A PATH OPENS")
	assert_bool(cs.header.star_line.color.is_equal_approx(W.TOAST_PURPLE)).is_true()
	assert_bool(cs.light_colour().is_equal_approx(ChestScreen.BOSS_LIGHT)).is_true()
	# the long title fits the screen, the line box keeps its height
	var w := W.slab().get_string_size(cs.header.title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cs.header.title.font_size).x
	assert_float(w).is_less_equal(cs.get_viewport_rect().size.x - 96.0 + 1.0)
	assert_float(cs.header.title.line_height).is_equal(150.0)
	# the landed mutation's word stays plum
	cs._tw.kill()
	cs._land()
	assert_bool(cs._word.color.is_equal_approx(W.PLUM)).is_true()
	# an ordinary chest after it: CHEST in brass under LOOT in paper, brass light
	var saws: WeaponDef = Registry.weapon("boomstick")
	cs.open({"type": "weapon", "id": saws.id, "def": saws, "level_from": 3, "level_to": 4, "is_new": false})
	assert_str(cs.header.title.text).is_equal("CHEST")
	assert_bool(cs.header.title.color.is_equal_approx(W.BRASS)).is_true()
	assert_int(cs.header.title.font_size).is_equal(150)
	assert_str(cs.header.star_line.text()).is_equal("LOOT")
	assert_bool(cs.header.star_line.color.is_equal_approx(W.PAPER)).is_true()
	assert_bool(cs.light_colour().is_equal_approx(W.BRASS)).is_true()
	cs._tw.kill()
	cs.visible = false
	await _frames(2)


# ---------------------------------------------------------------- 6. kind glyphs

func test_the_kind_glyph_picks_weapons_and_lines_only() -> void:
	assert_str(W.kind_mark_of(Registry.weapon("boomstick"))).is_equal("weapon")
	assert_str(W.kind_mark_of(Registry.weapon("pea_cannon"))).is_equal("weapon")
	assert_str(W.kind_mark_of(Registry.passive("brawn"))).is_equal("line")
	assert_str(W.kind_mark_of(Registry.passive("juggernaut"))).is_equal("line")
	assert_str(W.kind_mark_of(Registry.passive("magnet"))).is_equal("")
	assert_str(W.kind_mark_of(Registry.perk("thruster_burst"))).is_equal("")
	assert_str(W.kind_mark_of(Registry.mutations_of("boomstick")[0])).is_equal("")
	assert_object(W.kind_glyph("")).is_null()
	# the cards: the plate carries the mark of the card's item
	for pair in [[Registry.weapon("boomstick"), "weapon"], [Registry.passive("brawn"), "line"], [Registry.passive("magnet"), ""]]:
		var def: ContentDef = pair[0]
		var card := _card("weapon" if def is WeaponDef else "passive", def)
		var c: WCard = auto_free(WCard.make(def, WItem.options(card)))
		assert_str(c.plate.kind_mark).override_failure_message(def.id).is_equal(str(pair[1]))
	# drawn over the bottom-left corner, a quarter of the plate across, poking 10 px past the border
	var p: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("boomstick"), 180.0, false, 1))
	p.set_kind_mark("weapon")
	var r := p.kind_disc()
	assert_float(r.size.x).is_equal(roundf(180.0 * WPlate.KIND_FRAC))
	assert_float(r.position.x).is_equal(p.border - 10.0)
	assert_float(r.end.y).is_equal(180.0 - p.border + 10.0)
	# the picture once imported (the lead imports it), the kind's letter until then: either way the plate draws
	assert_str(p.kind_mark).is_equal("weapon")


func test_the_chest_reel_and_landed_plate_carry_their_kind() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await _frames(1)
	var def: WeaponDef = Registry.weapon("boomstick")
	cs.open({"type": "weapon", "id": def.id, "def": def, "level_from": 2, "level_to": 3, "is_new": false})
	var seen := 0
	for pr in cs._plates:
		var d: ContentDef = pr[1]
		if d:
			assert_str((pr[0] as WPlate).kind_mark).is_equal(W.kind_mark_of(d))
			seen += 1
	assert_int(seen).is_greater(0)
	cs._tw.kill()
	cs._land()
	assert_str(cs._hero.kind_mark).is_equal("weapon")
	cs.visible = false
	await _frames(2)


# ---------------------------------------------------------------- 7. bold numbers

func test_numbers_in_body_text_are_set_bold() -> void:
	var t := "+15% attack damage for 1.5 s, −20% max HP, ×2 rounds, every 3rd shot, 3 seconds, SK2 and 1,200 gold"
	var spans := WText.number_spans(t)
	var joined := ""
	var nums: Array = []
	for sp in spans:
		joined += str(sp[0])
		if sp[1]:
			nums.append(str(sp[0]))
	assert_str(joined).is_equal(t)
	assert_array(nums).is_equal(["+15%", "1.5 s", "−20%", "×2", "3rd", "3", "1,200"])
	# Bitter body text bolds its numbers in Bitter 800, the words stay as they were
	var body := W.serif_text("Deals 12 damage every 0.8 s.", 30)
	auto_free(body)
	assert_bool(body.bold_numbers).is_true()
	assert_object(body.bold_font).is_same(W.serif(W.BOLD_WEIGHT))
	assert_array(body.bold_spans()).is_equal(["12", "0.8 s"])
	assert_str(body.text).is_equal("Deals 12 damage every 0.8 s.")
	# an italic line takes the italic bold
	var it := W.serif_text("Lasts 4 s.", 24, W.INK, 400, true)
	auto_free(it)
	assert_object(it.bold_font).is_same(W.serif(W.BOLD_WEIGHT, true))
	# off where asked (a version line), never on slab or labels
	var plain := W.serif_text("88fits v0.39", 24, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, 0.0, false, false)
	auto_free(plain)
	assert_array(plain.bold_spans()).is_empty()
	var slab := W.slab_text("LEVEL 12", 60)
	auto_free(slab)
	assert_bool(slab.bold_numbers).is_false()
	var lab := W.label("Stage 3", 20)
	auto_free(lab)
	assert_bool(lab.bold_numbers).is_false()
	# a wrapped card line shapes with the spans and keeps its words
	var card := W.serif_text("+8 thorns damage a level. Trade: cooldowns 4% longer.", 30, W.INK, 400, false, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	add_child(card)
	auto_free(card)
	card.size = Vector2(400, 0)
	await _frames(2)
	assert_float(card.get_combined_minimum_size().y).is_greater(39.0 * 1.5)
	assert_array(card.bold_spans()).is_equal(["+8", "4%"])


# ---------------------------------------------------------------- 8. Phoenix Feather

func test_the_feather_flies_off_as_he_falls_and_its_row_says_used() -> void:
	var g: Node = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	# nothing real may knock him down while the feather does its work
	g.player.god = true
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	assert_bool(Run.phoenix_ready()).is_true()
	g._on_player_died()
	await _frames(1)
	assert_bool(Run.phoenix_used).is_true()
	var fly: Control = g.hud.find_child("FlyItem", true, false)
	assert_object(fly).is_not_null()
	assert_object(fly.find_child("Embers", true, false)).is_not_null()
	var plate: WPlate = fly.find_child("Plate", true, false)
	assert_object(plate.tex).is_same(Registry.passive("phoenix_feather").icon)
	# the banner with its icon, in the feather's colour
	assert_str(g.hud.banner_text()).is_equal("PHOENIX FEATHER")
	var box: StyleBox = g.hud._banner.get_theme_stylebox("panel")
	assert_bool((box as HardBox).fill.is_equal_approx(g.PHOENIX_COLOUR)).is_true()
	assert_object(g.hud._banner._icon.texture).is_same(Registry.passive("phoenix_feather").icon)
	# it rises, grows and turns
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(fly):
		assert_float(fly.scale.x).is_greater(1.05)
		assert_float(fly.rotation).is_less(0.0)
	# he stands at PHOENIX_DELAY; the banner said again then is the same one, still in its colour
	await get_tree().create_timer(g.PHOENIX_DELAY).timeout
	assert_bool(g.player.hp > 0.0).is_true()
	if g.hud._banner.is_up():
		assert_bool((g.hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(g.PHOENIX_COLOUR)).is_true()
	# its Build row: "(used)" after the grey name, the one line says so, no stars
	var ps: PauseScreen = g.pause_screen
	ps._tab = 0
	ps._refresh()
	await _frames(2)
	var used: WText = ps._content.find_child("Spent", true, false)
	assert_object(used).is_not_null()
	assert_str(used.text).is_equal("(used)")
	assert_bool(used.color.is_equal_approx(W.COMMON)).is_true()
	assert_str(_texts(ps._content)).contains("Used: it stood you up once this run")
	var row: WRow = null
	for r in ps._content.find_children("*", "", true, false):
		if r is WRow and (r as WRow).suffix == used:
			row = r
	assert_object(row).is_not_null()
	assert_bool(row.name_text.color.is_equal_approx(W.COMMON)).is_true()
	assert_bool((row.find_child("Plate", true, false) as WPlate).locked).is_true()
	g.set_paused(false)


# ---------------------------------------------------------------- 9. the debug switch for the on-screen aim

func test_the_debug_panel_carries_the_on_screen_aim_switch() -> void:
	Settings.debug_mode = true
	var s: Node = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s)
	await _frames(2)
	var sw: Node = s.find_child("RangedOnScreen", true, false)
	if "ranged_on_screen" in Settings:
		assert_object(sw).is_not_null()
		Settings.set("ranged_on_screen", true)
		(sw as WSwitch).toggled.emit(false)
		assert_bool(bool(Settings.get("ranged_on_screen"))).is_false()
		(sw as WSwitch).toggled.emit(true)
		assert_bool(bool(Settings.get("ranged_on_screen"))).is_true()
	else:
		# the setting is the combat lane's: without it, no switch
		assert_object(sw).is_null()
	# no debug mode, no panel
	Settings.debug_mode = false
	var s2: Node = auto_free(load("res://ui/SettingsScreen.tscn").instantiate())
	add_child(s2)
	await _frames(2)
	assert_object(s2.find_child("RangedOnScreen", true, false)).is_null()
	# the version line keeps one weight
	assert_array((s2.get("_version") as WText).bold_spans()).is_empty()


# ---------------------------------------------------------------- 8b. the banner's colour and the flight on their own

func test_the_banner_takes_an_item_s_own_colour_and_says_it_once() -> void:
	_start()
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	await _frames(1)
	var feather: PassiveDef = Registry.passive("phoenix_feather")
	var orange := Color(1.0, 0.55, 0.15)
	hud.banner("PHOENIX FEATHER", orange, feather.icon)
	assert_str(hud.banner_text()).is_equal("PHOENIX FEATHER")
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(orange)).is_true()
	# the same words while they are up: the one showing stays, icon and colour
	hud.banner("PHOENIX FEATHER", orange)
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(orange)).is_true()
	assert_object(hud._banner._icon.texture).is_same(feather.icon)
	# an evolution and an unlock keep the ember with their icon; plain news is ink
	var sw: WeaponDef = Registry.weapon("killer_swarm")
	hud.banner("EVOLVED · KILLER SWARM", Color(1.0, 0.83, 0.35), sw.icon if sw else feather.icon)
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.EMBER)).is_true()
	hud.banner("UNLOCKED: Sabre", UiKit.GOOD, feather.icon)
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.EMBER)).is_true()
	hud.banner("STAGE 2", UiKit.ACCENT)
	assert_bool((hud._banner.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.INK)).is_true()
	# the flight: a plain holder (it turns and grows), the item's plate and its embers
	var fly: Control = hud.fly_item(feather, Vector2(540, 900), orange)
	assert_str(str(fly.name)).is_equal("FlyItem")
	assert_bool(fly is Container).is_false()
	assert_object(fly.find_child("Plate", true, false)).is_not_null()
	assert_int(int((fly.find_child("Embers", true, false) as Node).get_meta("count", 0))).is_equal(HUD.FLY_EMBERS)
	assert_bool((fly.position + fly.size * 0.5).is_equal_approx(Vector2(540, 900))).is_true()
	assert_float(HUD.FLY_RISE).is_equal(260.0)
	assert_float(HUD.FLY_TIME).is_equal(1.6)
	assert_float(HUD.FLY_SCALE).is_equal(1.35)
	assert_float(HUD.FLY_TILT).is_equal(-12.0)
