## Pass 48, the UI lane (Garry's sixth list): plates in the colour of their level (weapons and lines Lv 1 common .. Lv 5
## legendary, lines topping out at epic; evolutions dark in the brass ring; passive items their rarity), bigger stars,
## a weapon's mutation dots along its plate's top edge (brass held, a hollow ring open, a glow when it waits to
## evolve), the HUD's twelve equal see-through 72 px slots with a brass line between the groups, the Collection's tabs
## and board under the back button at any camera-cutout inset, the stage clear's NOT YET, WoW-style crit numbers (and
## mini crits, and purple poison), the developer menu's dummy rows, the Powder Keg's source on the Results, the title
## plaque's start levels and Phoenix Feather's SPENT ("(used)" since pass 54).
extends GdUnitTestSuite


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func after_test() -> void:
	Settings.top_inset = -1
	Run.arena = false
	Run.end()
	DamageNumbers.I = null


func _rarity(level: int) -> Color:
	return W.RARITY_PLATE[W.RARITIES[clampi(level - 1, 0, 4)]]


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			var t := n as WText
			s += t.text + " "
			for r in t.runs:
				s += str(r[0]) + " "
	return s


func _marks(root: Node) -> Array:
	return root.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is WMarks)


# ---------------------------------------------------------------- plates by level

func test_a_weapon_s_and_a_line_s_plate_takes_its_level_s_colour() -> void:
	var pea: WeaponDef = Registry.weapon("peashooter")
	for lv in range(1, 6):
		assert_bool(W.plate_fill(pea, lv).is_equal_approx(_rarity(lv))).override_failure_message("weapon level %d" % lv).is_true()
	# level 0 is the item in general (common); past the top it stays legendary
	assert_bool(W.plate_fill(pea, 0).is_equal_approx(W.RARITY_PLATE["common"])).is_true()
	assert_bool(W.plate_fill(pea, 9).is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
	# a line the same, its fourth and last level epic
	var brawn: PassiveDef = Registry.passive("brawn")
	assert_int(brawn.max_level).is_equal(4)
	for lv in range(1, 5):
		assert_bool(W.plate_fill(brawn, lv).is_equal_approx(_rarity(lv))).override_failure_message("line level %d" % lv).is_true()
	# evolutions dark at any level, a passive item its rarity at any level
	for lv in [0, 1, 5]:
		assert_bool(W.plate_fill(Registry.weapon("pea_cannon"), lv).is_equal_approx(W.EVOLVED_FILL)).is_true()
		assert_bool(W.plate_fill(Registry.passive("juggernaut"), lv).is_equal_approx(W.EVOLVED_FILL)).is_true()
		var magnet: PassiveDef = Registry.passive("magnet")
		assert_bool(W.plate_fill(magnet, lv).is_equal_approx(W.RARITY_PLATE[W.rarity_of(magnet)])).is_true()
	# the plate takes the level; an evolution keeps its brass ring
	var p: WPlate = auto_free(WPlate.new().for_def(pea, 72.0, false, 4))
	assert_bool(p.fill.is_equal_approx(W.RARITY_PLATE["epic"])).is_true()
	var e: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("pea_cannon"), 72.0, false, 1))
	assert_int(e.ring).is_greater(0)
	assert_bool(e.ring_color.is_equal_approx(W.EVOLVED_RING)).is_true()


func test_cards_show_the_level_the_pick_lands_on() -> void:
	_start()
	var card := {"def": Registry.weapon("boomstick"), "level_from": 2, "level_to": 3}
	var o := WItem.options(card)
	assert_int(int(o["level"])).is_equal(3)
	var c: WCard = auto_free(WCard.make(card["def"], o))
	assert_bool(c.plate.fill.is_equal_approx(W.RARITY_PLATE["rare"])).is_true()
	# a new weapon is common, a line's evolution is the dark plate in the brass ring (no ember plate any more)
	var fresh: WCard = auto_free(WCard.make(Registry.weapon("boomstick"), WItem.options({"def": Registry.weapon("boomstick"), "level_from": 0, "level_to": 1})))
	assert_bool(fresh.plate.fill.is_equal_approx(W.RARITY_PLATE["common"])).is_true()
	var evo := {"def": Registry.passive("juggernaut"), "level_from": 4, "level_to": 5, "evolve": true}
	var ec: WCard = auto_free(WCard.make(evo["def"], WItem.options(evo)))
	assert_bool(ec.plate.fill.is_equal_approx(W.EVOLVED_FILL)).is_true()
	assert_int(ec.plate.ring).is_greater(0)
	# the plaque: a favourite at its bonus level, the gun he lands with at 1
	var ts = load("res://ui/TitleScreen.gd")
	var drifter: CharacterDef = Registry.character("drifter")
	# pass 76 (lane DYN): his favourite is the dynamite (the Lob Grenade) now
	assert_int(ts.start_level(drifter, Registry.weapon("lob_grenade"))).is_equal(2)
	assert_int(ts.start_level(drifter, Registry.weapon("revolver"))).is_equal(1)
	assert_int(ts.start_level(Registry.character("calavera"), Registry.weapon("skull_rain"))).is_equal(2)
	assert_int(ts.start_level(Registry.character("ironwood"), Registry.passive("brawn"))).is_equal(2)


# ---------------------------------------------------------------- stars

func test_the_stars_are_bigger_and_five_fit_every_layout() -> void:
	_start()
	assert_float(WCard.STAR_PX).is_equal(40.0)
	assert_float(ChestScreen.STAR_PX).is_equal(48.0)
	assert_float(PauseScreen.STAR_PX).is_equal(34.0)
	# a weapon card: five stars (its max level), 40 px
	var card := {"def": Registry.weapon("boomstick"), "level_from": 2, "level_to": 3}
	var c: WCard = auto_free(WCard.make(card["def"], WItem.options(card)))
	var m: Array = _marks(c)
	assert_int(m.size()).is_equal(1)
	assert_int((m[0] as WMarks).total).is_equal(5)
	assert_float((m[0] as WMarks).mark).is_equal(40.0)
	# five fit each layout at 1080 (the canvas keeps 1080 wide on a 540 px phone too): the card's text column, the
	# chest's result panel, a pause row beside its plate, name and chevron
	var five_40 := WMarks.new().setup("stars", 5, 3, -1, 40.0)
	var five_48 := WMarks.new().setup("stars", 5, 3, -1, 48.0)
	var five_34 := WMarks.new().setup("stars", 5, 3, -1, 34.0)
	assert_float(five_40.get_combined_minimum_size().x).is_less(1080.0 - 96.0 - 74.0 - 180.0 - 28.0)
	assert_float(five_48.get_combined_minimum_size().x).is_less(1080.0 - 120.0 - 92.0)
	assert_float(five_34.get_combined_minimum_size().x + 104.0 + 24.0 + 60.0 + 300.0).is_less(1080.0 - 96.0 - 58.0 - 44.0)
	for x in [five_40, five_48, five_34]:
		x.free()
	# the pause screen's rows: stars at 34, open or closed (the mutations are dots on the plate)
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	for open in ["", "boomstick"]:
		ps._expanded = open
		ps._tab = 0
		ps._refresh()
		await get_tree().process_frame
		var rows: Array = ps._content.get_children().filter(func(n: Node) -> bool: return n is WRow and not n.is_queued_for_deletion())
		var stars: Array = _marks(rows[0])
		assert_int(stars.size()).override_failure_message("open '%s'" % open).is_equal(1)
		assert_str((stars[0] as WMarks).mode).is_equal("stars")
		assert_float((stars[0] as WMarks).mark).is_equal(34.0)
		assert_int((stars[0] as WMarks).total).is_equal(5)
	ps.visible = false


# ---------------------------------------------------------------- mutation dots

func test_a_plate_draws_its_mutation_dots_and_glows_when_ready() -> void:
	var p: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("peashooter"), 72.0, false, 2))
	p.set_dots(Vector2i(2, 3))
	assert_object(p.dots).is_equal(Vector2i(2, 3))
	assert_bool(p.dots_ready).is_false()
	assert_float(p.dot_size()).is_equal(20.0)
	# along the top edge, in the middle, inside the plate's width
	for i in 3:
		var c := p.dot_center(i)
		assert_float(c.y).is_equal_approx(p.border * 0.5, 0.01)
		assert_float(c.x - p.dot_size() * 0.5).is_greater_equal(0.0)
		assert_float(c.x + p.dot_size() * 0.5).is_less_equal(72.0)
	assert_float(p.dot_center(0).x + p.dot_center(2).x).is_equal_approx(72.0, 0.01)
	# all held and ready: the glow breathes (the plate processes only then)
	p.set_dots(Vector2i(3, 3), true)
	assert_bool(p.dots_ready).is_true()
	assert_bool(p.is_processing()).is_true()
	p.set_dots(Vector2i(3, 3), false)
	assert_bool(p.is_processing()).is_false()
	# more held than the path has is clamped; none off
	p.set_dots(Vector2i(5, 3))
	assert_object(p.dots).is_equal(Vector2i(3, 3))
	p.set_dots(Vector2i.ZERO)
	assert_int(p.dots.y).is_equal(0)
	# bigger plates, bigger dots
	var big: WPlate = auto_free(WPlate.new().for_def(Registry.weapon("peashooter"), 180.0))
	assert_float(big.dot_size()).is_greater(p.dot_size())
	await get_tree().process_frame


func test_the_hud_s_weapons_carry_their_path_dots_hero_mutations_aside() -> void:
	_start("drifter")
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	var w: WeaponInstance = Run.weapon_instance("peashooter")
	assert_object(Run.path_progress(w)).is_equal(Vector2i(0, 3))
	assert_bool(Run.add_mutation("toxic_peas", true)).is_true()
	# a hero's own mutation is no dot (pass 48: the path is the three that evolve it)
	assert_bool(Run.add_mutation("fan_the_hammer", true)).is_true()
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	var p: WPlate = hud._slot_nodes["peashooter"]
	assert_object(p.dots).is_equal(Vector2i(1, 3))
	assert_bool(p.dots_ready).is_false()
	# the plate is in the colour of its level
	assert_bool(p.fill.is_equal_approx(W.RARITY_PLATE["uncommon"])).is_true()
	# every mutation held and the top level: the evolution waits at the next chest, the plate glows
	Run.add_mutation("big_peas", true)
	Run.add_mutation("bouncing_peas", true)
	hud._refresh_rows()
	p = hud._slot_nodes["peashooter"]
	assert_object(p.dots).is_equal(Vector2i(3, 3))
	assert_bool(p.dots_ready).is_false()
	w.level = w.def.max_level
	hud._refresh_rows()
	p = hud._slot_nodes["peashooter"]
	assert_bool(Run.evolution_ready(w)).is_true()
	assert_bool(p.dots_ready).is_true()
	assert_bool(p.fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
	# a line carries no dots
	Run.add_or_level_passive("brawn")
	hud._refresh_rows()
	assert_int((hud._slot_nodes["brawn"] as WPlate).dots.y).is_equal(0)
	# the same dots on its card, its pause row and the chest's reel
	var o := WItem.options({"def": w.def, "level_from": 4, "level_to": 5})
	assert_object(o["dots"]).is_equal(Vector2i(3, 3))
	var c: WCard = auto_free(WCard.make(w.def, o))
	assert_object(c.plate.dots).is_equal(Vector2i(3, 3))
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	ps._tab = 0
	ps._refresh()
	await get_tree().process_frame
	var row: WRow = ps._content.get_children().filter(func(n: Node) -> bool: return n is WRow)[0]
	var rp: WPlate = row.head.find_child("Plate", false, false)
	assert_object(rp.dots).is_equal(Vector2i(3, 3))
	assert_bool(rp.dots_ready).is_true()
	# the open row says how far down the path it is
	assert_str(ps._evolve_note(w)).starts_with("3/3 mutations")
	ps.visible = false
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	cs.open({"type": "weapon", "id": "peashooter", "def": w.def, "level_from": 4, "level_to": 5, "is_new": false})
	var landing: WPlate = cs._plates[ChestScreen.CELLS - 1][0]
	assert_object(landing.dots).is_equal(Vector2i(3, 3))
	assert_bool(landing.fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 60:
		await get_tree().process_frame
		if not cs._spinning:
			break
	assert_object(cs._hero.dots).is_equal(Vector2i(3, 3))
	# taken, the level it lands on goes to the gate with it
	cs._finish(true)
	assert_int(int(cs.take_pick().get("level", -1))).is_equal(5)
	cs.visible = false


# ---------------------------------------------------------------- the HUD's slots

func test_the_hud_has_twelve_equal_see_through_slots_on_one_row() -> void:
	_start()
	Run.debug_clear_items()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	Run.add_weapon(Registry.weapon("peashooter"), 5)
	Run.add_or_level_passive("brawn")
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	await get_tree().process_frame
	assert_float(HUD.WEAPON_PX).is_equal(72.0)
	assert_float(HUD.OTHER_PX).is_equal(72.0)
	var plates: Array = hud._slots.get_children()
	assert_int(plates.size()).is_equal(10)
	# pass 49: the three held items' plates are solid, the empty or padlocked slots see-through (ten slots since pass 52)
	var solid := 0
	for p: WPlate in plates:
		assert_float(p.side).is_equal(72.0)
		assert_float(p.position.y).is_equal(0.0)
		if p.plate_alpha >= 1.0:
			solid += 1
		else:
			assert_float(p.plate_alpha).is_equal(HUD.SLOT_ALPHA)
	assert_int(solid).is_equal(3)
	for id in ["boomstick", "peashooter", "brawn"]:
		assert_float((hud._slot_nodes[id] as WPlate).plate_alpha).is_equal(1.0)
	assert_float(HUD.SLOT_ALPHA).is_equal(0.5)
	# 8 px between slots; between the last weapon slot and the first line slot whatever the row has left (pass 53, Garry:
	# the groups against their sides; the 48 px gap with the brass line in it marked the middle of a centred row)
	var vw := hud.get_viewport_rect().size.x
	var avail := vw - 72.0
	for i in range(1, 10):
		var gap: float = (plates[i] as WPlate).position.x - ((plates[i - 1] as WPlate).position.x + 72.0)
		assert_float(gap).override_failure_message("gap %d" % i).is_equal_approx(avail - 784.0 if i == 5 else 8.0, 0.01)
	assert_object(hud.get("_divider")).is_null()
	assert_object(hud.find_child("SlotDivider", true, false)).is_null()
	# a row needs 832 px (five and five since pass 52; six and six were 992 of the 1008 between the margins); the weapons
	# start at the left margin and the lines end at the right one (pass 53)
	var items := HUD.slot_specs([], 5, [], [], 5, [])
	assert_float(HUD._row_width(items)).is_equal(832.0)
	assert_float(HUD._row_width(items)).is_less_equal(1080.0 - 72.0)
	var left := hud._slots.position.x + (plates[0] as WPlate).position.x
	var right := vw - (hud._slots.position.x + (plates[9] as WPlate).position.x + 72.0)
	assert_float(left).is_equal_approx(36.0, 0.5)
	assert_float(right).is_equal_approx(36.0, 0.5)
	# the strip ends under the slots (the thumb zone starts below it)
	assert_float(HUD.band_h).is_equal(float(HUD.BAND_H) + W.safe_top())
	assert_float(hud._slots_bottom).is_less(HUD.band_h)
	# each held plate in its level's colour, the empty ones aged and see-through
	assert_bool((hud._slot_nodes["boomstick"] as WPlate).fill.is_equal_approx(W.RARITY_PLATE["uncommon"])).is_true()
	assert_bool((hud._slot_nodes["peashooter"] as WPlate).fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
	assert_bool((hud._slot_nodes["brawn"] as WPlate).fill.is_equal_approx(W.RARITY_PLATE["common"])).is_true()
	assert_int(plates.filter(func(p: WPlate) -> bool: return p.empty and p.plate_alpha == 0.5).size()).is_equal(7)


func test_the_buff_words_under_the_slots() -> void:
	_start()
	assert_array(HUD.buff_parts()).is_empty()
	# Hot Streak (pass 49): the attack damage its kills have built, while it is held
	Run.add_or_level_passive("hot_streak")
	assert_float(Run.player_sheet.get_stat("kill_might", 0.0)).is_greater(0.0)
	Run.streak = 1370
	assert_array(HUD.buff_parts()).contains(["HOT STREAK +6%"])
	Run.streak = 0
	assert_bool(HUD.buff_parts().any(func(s: String) -> bool: return s.begins_with("HOT STREAK"))).is_false()
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	Run.adrenaline = 3
	hud._refresh_buffs()
	assert_str(hud._adren.text).contains("ADRENALINE ×3")
	Run.adrenaline = 0
	hud._refresh_buffs()
	assert_bool(hud._adren.visible).is_false()


func test_a_buff_plate_counts_its_own_seconds_on_the_buffs_clock() -> void:
	_start()
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	# a quiet timer with no plate ahead of a power-up's: the plate still reads the power-up's seconds (it was matched by
	# place in Run.timed and read the other's)
	Run.add_timed_effects("skedaddle", "SKEDADDLE", [], 2.0, true)
	Run.add_timed_effects("rage", "BERSERK", [], 10.0)
	assert_object(Registry.pickup("rage")).is_not_null()
	hud._refresh_buffs()
	var plates: Array = hud._buffs.get_children()
	assert_int(plates.size()).is_equal(1)
	assert_str(str((plates[0] as WPlate).get_meta("buff"))).is_equal("rage")
	assert_str((plates[0] as WPlate).level_text).is_equal("10")
	# on the buffs' clock, which runs on through a boss fight while the stage clock holds
	Run.held_time += 4.0
	hud._refresh_buffs()
	assert_str((plates[0] as WPlate).level_text).is_equal("6")
	Run.held_time -= 4.0
	Run.timed.clear()


# ---------------------------------------------------------------- the Collection's back button

func test_the_collection_s_tabs_and_board_sit_under_the_back_button_at_any_inset() -> void:
	for inset: int in [0, 80, 130, 180]:
		Settings.top_inset = inset
		var c: CollectionScreen = load("res://ui/CollectionScreen.tscn").instantiate()
		add_child(c)
		await get_tree().create_timer(0.4).timeout
		var head_foot := 44.0 + inset + 114.0
		assert_float(c.header.offset_top).is_equal(44.0 + inset)
		# the tabs 14 px under the header, the board under the tabs, both lower by the inset
		assert_float(c._tabs.offset_top).override_failure_message("tabs at inset %d" % inset).is_equal(CollectionScreen.TAB_TOP + inset)
		assert_float(c._tabs.offset_top).is_greater_equal(head_foot)
		assert_float(c.scroll.offset_top).override_failure_message("grid at inset %d" % inset).is_equal_approx(CollectionScreen.GRID_TOP + inset, 0.5)
		assert_float(c._tabs.get_global_rect().end.y).is_less_equal(c.scroll.get_global_rect().position.y + 2.0)
		# nothing over the back square: the header is the last thing drawn (and the first to take a touch)
		assert_int(c.header.get_index()).is_equal(c.get_child_count() - 1)
		var back := c.header.back_button.get_global_rect()
		assert_bool(back.intersects(c._tabs.get_global_rect())).override_failure_message("tabs over the back at %d" % inset).is_false()
		assert_bool(back.intersects(c.scroll.get_global_rect())).override_failure_message("board over the back at %d" % inset).is_false()
		# an item's page keeps clear of it too
		c._open_page(Registry.weapon("boomstick"))
		await get_tree().process_frame
		assert_float(c.scroll.offset_top).is_equal_approx(CollectionScreen.PAGE_TOP + inset, 0.5)
		assert_bool(back.intersects(c.scroll.get_global_rect())).is_false()
		c._show_grid()
		c.visible = false
		c.queue_free()
		await get_tree().process_frame
	Settings.top_inset = -1


# ---------------------------------------------------------------- the stage clear's way out

func test_not_yet_closes_the_stage_clear_without_a_decision() -> void:
	_start()
	var pd: PortalDialog = auto_free(PortalDialog.new())
	add_child(pd)
	var said: Array = []
	var no: Array = []
	pd.decided.connect(func(x): said.append(x))
	pd.declined.connect(func(): no.append(true))
	pd.open(1, true, false)
	await get_tree().process_frame
	var nb: WButton = pd.find_child("NotYet", true, false)
	assert_object(nb).is_not_null()
	assert_str(nb.label_text()).is_equal("NOT YET")
	# under the two roads
	assert_int(nb.get_index()).is_equal(pd._cards.get_child_count() - 1)
	assert_str(pd._foot.text).is_equal("Not ready? Step out, and walk back in when you are.")
	nb.pressed.emit()
	assert_bool(pd.visible).is_false()
	assert_int(no.size()).is_equal(1)
	assert_int(said.size()).is_equal(0)
	# Esc does the same, and the back gesture
	pd.open(1, true, false)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	pd._unhandled_input(esc)
	assert_bool(pd.visible).is_false()
	assert_int(no.size()).is_equal(2)
	pd.open(1, true, false)
	pd._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_bool(pd.visible).is_false()
	assert_int(no.size()).is_equal(3)
	# closed, nothing more happens; the roads still decide
	pd._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_int(no.size()).is_equal(3)
	pd.open(1, true, false)
	pd._extract.pressed.emit()
	assert_array(said).is_equal([true])
	assert_int(no.size()).is_equal(3)


# ---------------------------------------------------------------- the numbers

func test_crits_read_like_wow_mini_crits_paler_and_poison_purple() -> void:
	Settings.damage_numbers = true
	var dn: DamageNumbers = auto_free(DamageNumbers.new())
	add_child(dn)
	dn.add(1, Vector3.ZERO, 120.0, true)
	dn.add(2, Vector3.ZERO, 60.0, false, false, false, true)
	dn.add(3, Vector3.ZERO, 5.0, false, true, false)
	dn.add(4, Vector3.ZERO, 5.0, false, false, true)
	dn.add(5, Vector3.ZERO, 30.0)
	var n: Array = dn.live()
	var crit: DamageNumbers.Num = n[0]
	var mini: DamageNumbers.Num = n[1]
	assert_bool(crit.crit and not crit.mini).is_true()
	assert_bool(mini.mini and not mini.crit).is_true()
	assert_str(DamageNumbers.colour_of(crit).to_html(false)).is_equal("ffe23a")
	assert_str(DamageNumbers.colour_of(mini).to_html(false)).is_equal("fff0a0")
	assert_str(DamageNumbers.colour_of(n[2]).to_html(false)).is_equal("c07bff")
	assert_bool(DamageNumbers.colour_of(n[3]) == DamageNumbers.HOT).is_true()
	assert_bool(DamageNumbers.colour_of(n[4]) == DamageNumbers.WHITE).is_true()
	# pass 54: a tenth up for Bitter 800 (72 / 58 / 48 in Alfa Slab)
	assert_int(DamageNumbers.size_of(crit)).is_equal(78)
	assert_int(DamageNumbers.size_of(mini)).is_equal(64)
	assert_int(DamageNumbers.size_of(n[4])).is_equal(52)
	# the pop: a crit from 2.6, a mini crit from 2.0, overshooting under 1 before settling at POP_CRIT
	assert_float(DamageNumbers.pop_scale(0.0, true)).is_equal_approx(2.6, 0.001)
	assert_float(DamageNumbers.pop_scale(0.0, false, true)).is_equal_approx(2.0, 0.001)
	assert_float(DamageNumbers.pop_scale(DamageNumbers.POP_CRIT * 0.8, true)).is_less(1.0)
	assert_float(DamageNumbers.pop_scale(DamageNumbers.POP_CRIT, true)).is_equal_approx(1.0, 0.0001)
	assert_float(DamageNumbers.pop_scale(DamageNumbers.POP, false)).is_equal_approx(1.0, 0.0001)
	# the hop: up about 60 px and back 20 in the first quarter second (a mini crit half), none on a plain hit
	assert_float(DamageNumbers.hop_of(crit)).is_equal(60.0)
	assert_float(DamageNumbers.hop_of(mini)).is_equal(30.0)
	assert_float(DamageNumbers.hop_of(n[4])).is_equal(0.0)
	assert_float(DamageNumbers.hop_at(DamageNumbers.HOP_T * 0.45, 60.0)).is_equal_approx(60.0, 0.01)
	assert_float(DamageNumbers.hop_at(DamageNumbers.HOP_T, 60.0)).is_equal_approx(40.0, 0.01)
	assert_float(DamageNumbers.hop_at(0.6, 60.0)).is_equal_approx(40.0, 0.01)
	assert_float(DamageNumbers.hop_at(DamageNumbers.HOP_T, 30.0)).is_equal_approx(20.0, 0.01)
	assert_float(DamageNumbers.hop_at(0.0, 60.0)).is_equal(0.0)
	# merging: a mini crit makes a plain number a mini crit, a full crit then makes it a crit
	dn.add(5, Vector3.ZERO, 10.0, false, false, false, true)
	assert_bool((n[4] as DamageNumbers.Num).mini).is_true()
	dn.add(5, Vector3.ZERO, 10.0, true)
	assert_bool((n[4] as DamageNumbers.Num).crit and not (n[4] as DamageNumbers.Num).mini).is_true()
	assert_float((n[4] as DamageNumbers.Num).amount).is_equal_approx(50.0, 0.001)
	await get_tree().process_frame


# ---------------------------------------------------------------- the developer menu's dummies

func test_the_developer_menu_steps_the_arena_dummies() -> void:
	var keep_hp: int = Settings.dummy_hp
	var keep_n: int = Settings.dummy_count
	assert_array(Settings.DUMMY_HP_STEPS).is_equal([0, 100, 500, 2000, 10000])
	assert_array(Settings.DUMMY_COUNT_STEPS).is_equal([10, 15, 20, 30])
	assert_int(Settings.next_step(Settings.DUMMY_HP_STEPS, 0)).is_equal(100)
	assert_int(Settings.next_step(Settings.DUMMY_HP_STEPS, 10000)).is_equal(0)
	assert_int(Settings.next_step(Settings.DUMMY_COUNT_STEPS, 30)).is_equal(10)
	assert_int(Settings.next_step(Settings.DUMMY_COUNT_STEPS, 12)).is_equal(15)
	assert_str(Settings.dummy_hp_label(0)).is_equal("UNDYING")
	assert_str(Settings.dummy_hp_label(500)).is_equal("500 HP")
	Settings.dummy_hp = 0
	Settings.dummy_count = 10
	var dm: Control = auto_free(load("res://ui/DevMenu.tscn").instantiate())
	add_child(dm)
	await get_tree().process_frame
	var hp_row: WTap = dm.find_child("DummyHealth", true, false)
	var n_row: WTap = dm.find_child("DummyCount", true, false)
	assert_object(hp_row).is_not_null()
	assert_object(n_row).is_not_null()
	assert_str(_texts(hp_row)).contains("UNDYING")
	hp_row.pressed.emit()
	assert_int(Settings.dummy_hp).is_equal(100)
	await get_tree().process_frame
	hp_row = dm.find_child("DummyHealth", true, false)
	assert_str(_texts(hp_row)).contains("100 HP")
	for k in 4:
		(dm.find_child("DummyHealth", true, false) as WTap).pressed.emit()
		await get_tree().process_frame
	assert_int(Settings.dummy_hp).is_equal(0)
	(dm.find_child("DummyCount", true, false) as WTap).pressed.emit()
	assert_int(Settings.dummy_count).is_equal(15)
	await get_tree().process_frame
	assert_str(_texts(dm.find_child("DummyCount", true, false))).contains("15")
	Settings.dummy_hp = keep_hp
	Settings.dummy_count = keep_n


# ---------------------------------------------------------------- the Results, the pause screen

func test_the_powder_keg_has_its_picture_and_plates_end_at_their_level() -> void:
	_start()
	var rs = load("res://ui/ResultsScreen.gd")
	var s: Dictionary = rs.damage_source("powder_keg")
	assert_str(str(s["name"])).is_equal("Powder Keg")
	assert_object(s["icon"]).is_not_null()
	var keg: PassiveDef = Registry.passive("powder_keg")
	if keg and keg.icon:
		assert_object(s["icon"]).is_same(keg.icon)
	# the new evolutions are their own items
	for id in ["blunderbuss", "moonshine", "pea_cannon", "grave_hail", "hive_queen", "jackrabbit_mines", "golden_pineapple"]:
		var e: Dictionary = rs.damage_source(id)
		assert_object(e["def"]).override_failure_message(id).is_same(Registry.weapon(id))
	# a weapon's plate in the colour of the level it ended at; one that evolved, its top
	Run.add_weapon(Registry.weapon("boomstick"), 4)
	assert_int(rs.final_level(Registry.weapon("boomstick"))).is_equal(4)
	var plate: WPlate = auto_free(rs.source_plate(rs.damage_source("boomstick"), 96.0))
	assert_bool(plate.fill.is_equal_approx(W.RARITY_PLATE["epic"])).is_true()
	assert_int(rs.final_level(Registry.weapon("tommy_gun"))).is_equal(1)


func test_phoenix_feather_says_spent_once_it_has_stood_him_up() -> void:
	_start()
	var feather: PassiveDef = Registry.passive("phoenix_feather")
	assert_object(feather).is_not_null()
	Run.add_or_level_passive("phoenix_feather")
	Run.phoenix_used = false
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	ps._tab = 0
	ps._refresh()
	await get_tree().process_frame
	assert_object(ps._content.find_child("Spent", true, false)).is_null()
	# once it has stood him up, its Build row says "(used)" after its name in grey (pass 54; SPENT in rock before; the
	# mark keeps the node name "Spent") (Run.item_spent), no stars, in the locked look
	Run.phoenix_used = true
	assert_bool(Run.item_spent(feather)).is_true()
	ps._refresh()
	await get_tree().process_frame
	assert_object(ps._content.find_child("Spent", true, false)).is_not_null()
	assert_str((ps._content.find_child("Spent", true, false) as WText).text).is_equal("(used)")
	assert_str(_texts(ps._content)).contains("Used: it stood you up once this run")
	assert_bool(Run.item_spent(Registry.passive("magnet"))).is_false()
	ps.visible = false
	Run.phoenix_used = false
