extends GdUnitTestSuite

## Pass 58, lane UIA (Garry's thirteenth list, 2026-10-07): the level-up and mutation screens. "Sometimes when I level
## up, the EXP bar at the top is only partially filled ... it should be the full EXP bar every time": the rainbow rail is
## full on both screens. "an animated shine effect behind the Level N header part ... Do the same for the Version of
## Level up that is for a Specific Weapon Mutation": WShine turns behind LEVEL N and behind the mutation offer's weapon
## plate once its reel lands, and goes with its host. "we should say "Level Up" somewhere on that screen": the star line
## over LEVEL N says LEVEL UP. "(!!!) Level Up Banish? What are we banishing?" and "Banish option should not allow
## Banishing items that Player already has": Run.banish_refusal refuses an upgrade of something held, an evolution of
## it and a path mutation of a weapon held; banish mode says what it does, refuses a held card (nothing spent, the card
## stays), strikes a new one (its replacement drops into its place), locks when nothing on the table may go, CANCEL
## takes it back, the first time says more; CardPool never offers a banished id. The review round: a banished hero's
## mutation never comes back in a boss chest or a path offer; a base weapon whose evolution is held is never offered
## again (a level-up, the Stranger) and reads as held; LEVEL UP is 34 px with an ink shadow (the mutation head's star
## line and row take the shadow too, every other modal's star line stays plain); banish mode's star line names its
## moment; a refusal in banish mode stands NOTE_HOLD and the mode's words come back; a reroll takes the struck card's
## ghost; the mutation offer's shine reaches as far as the level-up's; WShine.warm draws one unseen for Warmup.

## New class_names are known once the lead imports: by path here.
const WShineScript := preload("res://ui/wanted/WShine.gd")

var _hints_had_banish := false


func before_test() -> void:
	_hints_had_banish = Save.hint_seen("banish")


func after_test() -> void:
	if not _hints_had_banish:
		(Save.data["hints_seen"] as Array).erase("banish")
	Settings.top_inset = -1
	Run.end()


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _card(type: String, def: ContentDef, from: int = 0, to: int = 1) -> Dictionary:
	return {"type": type, "id": def.id, "def": def, "level_from": from, "level_to": to, "is_new": from == 0, "weight": 1.0}


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


## A button's words once the old ones are gone (WButton.set_parts queues them for deletion).
func _label(b: WButton) -> String:
	await get_tree().process_frame
	return b.label_text()


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			s += (n as WText).text + " "
		elif n is WStarLine:
			s += (n as WStarLine).text() + " "
	return s


## Two new passive items the run may find, never the hero's favourite (a favourite card says so) and never held.
func _new_passives(n: int) -> Array:
	var out: Array = []
	for p: PassiveDef in Registry.unlocked_passives():
		if p.is_line() or Run.passives.has(p.id) or Run.is_favourite(p) or not CardPool.stage_open(p):
			continue
		out.append(p)
		if out.size() >= n:
			break
	return out


## A line that evolves, at its top level, and the evolution card a level-up offers for it.
func _line_evolution_card() -> Dictionary:
	for p: PassiveDef in Registry.sorted_lines():
		if p.evolves_into == "" or p.is_evolved():
			continue
		var evo: PassiveDef = Registry.passive(p.evolves_into)
		if evo == null:
			continue
		Run.passives[p.id] = p.max_level
		var c := _card("passive", evo, p.max_level, p.max_level + 1)
		c["evolve"] = true
		c["src_id"] = p.id
		return c
	return {}


# ---------------------------------------------------------------- 1. the rail is full on both screens

func test_the_rail_is_full_on_a_level_up_and_on_a_mutation_offer() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	# the run's bar part-filled: a third of the way to the next level
	Run.xp = Run.xp_to_next() * 0.33
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer(CardPool.level_up_offer(3), "LEVEL 2!", false)
	assert_float(cs.rail_frac()).is_equal(1.0)
	var w: WeaponInstance = Run.weapon_instance("peashooter")
	cs.show_offer(CardPool.path_offer(w), "MUTATION", false, true)
	assert_float(cs.rail_frac()).is_equal(1.0)
	cs.skip_reel()
	assert_float(cs.rail_frac()).is_equal(1.0)
	cs.visible = false
	await _frames(2)


# ---------------------------------------------------------------- 2. the shine

func test_the_shine_turns_and_goes_with_its_host() -> void:
	var host: Control = auto_free(Control.new())
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var s = WShineScript.make(Vector2(300, 200), 260.0)
	s.put(host)
	assert_object(s.get_parent()).is_same(host)
	# behind things and never in a finger's way; it turns while the run is paused
	assert_int(s.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(s.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_object(s.material).is_not_null()
	var a0: float = s.angle()
	await _frames(6)
	assert_float(s.age()).is_greater(0.0)
	assert_float(absf(angle_difference(a0, s.angle()))).is_greater(0.0001)
	# it pops in from nothing and settles at its reach (the breath swells it a few percent)
	s.pop_in(0.2)
	assert_float(s.grow).is_equal(0.0)
	await get_tree().create_timer(0.35).timeout
	assert_float(s.grow).is_equal_approx(1.0, 0.001)
	assert_float(s.drawn_radius()).is_between(260.0 * (1.0 - WShineScript.BREATH_SIZE) - 0.5, 260.0 * (1.0 + WShineScript.BREATH_SIZE) + 0.5)
	# hidden, it stops turning; shown again it goes on
	s.visible = false
	var a1: float = s.angle()
	await _frames(4)
	assert_float(s.angle()).is_equal(a1)
	s.visible = true
	# tinted: both layers take the colour (the boss chest's purple)
	s.tint(W.TOAST_PURPLE)
	assert_bool(s.color.is_equal_approx(W.TOAST_PURPLE)).is_true()
	assert_bool(s.color2.is_equal_approx(W.TOAST_PURPLE.lerp(W.PAPER, 0.62))).is_true()
	# freed with its host
	var ref: WeakRef = weakref(s)
	host.queue_free()
	await _frames(2)
	assert_object(ref.get_ref()).is_null()


func test_the_shine_stands_behind_level_n_and_behind_the_landed_weapon() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	var sh = cs.shine()
	assert_object(sh).is_not_null()
	# over the dim, under the rail, the header and the cards
	assert_int(sh.get_index()).is_equal(cs.dim.get_index() + 1)
	assert_int(sh.get_index()).is_less(cs.find_child("XpRail", false, false).get_index())
	assert_int(sh.get_index()).is_less(cs.header.get_index())
	assert_int(sh.get_index()).is_less(cs._list.get_index())
	cs.show_offer(CardPool.level_up_offer(3), "LEVEL 4!", false)
	assert_bool(sh.visible).is_true()
	assert_float(sh.center.y).is_equal_approx(CardScreen.TITLE_MID_Y + W.safe_top(), 0.5)
	assert_float(sh.center.x).is_equal_approx(cs.get_viewport_rect().size.x * 0.5, 0.5)
	assert_float(sh.radius).is_equal(CardScreen.SHINE_R)
	# the reveal's sun and bursts play over it
	for c in cs.get_children():
		if c is WCelebrate:
			assert_int(c.get_index()).is_greater(sh.get_index())
	# a mutation offer: no shine while the reel spins, then behind the weapon's plate
	var w: WeaponInstance = Run.weapon_instance("peashooter")
	cs.show_offer(CardPool.path_offer(w), "MUTATION", false, true)
	assert_bool(cs.reel_running()).is_true()
	assert_bool(sh.visible).is_false()
	cs.skip_reel()
	assert_bool(sh.visible).is_true()
	assert_float(sh.center.y).is_equal_approx(cs.path_plate_center_y(), 0.5)
	assert_float(sh.radius).is_equal(CardScreen.PATH_SHINE_R)
	# as far as the level-up's, so its rays clear the 272 px plate (the review: at 380 it was a faint halo round it)
	assert_float(CardScreen.PATH_SHINE_R).is_greater_equal(CardScreen.SHINE_R * 0.9)
	assert_float(CardScreen.PATH_SHINE_R - 272.0 * 0.5 * sqrt(2.0)).is_greater(250.0)
	cs.visible = false
	await _frames(2)


func test_the_shine_can_be_warmed_unseen() -> void:
	var host: Control = auto_free(Control.new())
	add_child(host)
	var s = WShineScript.warm(host)
	assert_object(s.get_parent()).is_same(host)
	# drawn (its shader compiles: _draw skips a shine fainter than 0.002), never seen, no glints
	assert_float(s.strength * s.fade * (1.0 - WShineScript.BREATH_ALPHA)).is_greater(0.002)
	assert_float(s.strength).is_less_equal(0.02)
	assert_int(s.glints).is_equal(0)
	assert_bool(s.is_visible_in_tree()).is_true()
	# given seconds it goes by itself; without, with its host
	var s2 = WShineScript.warm(host, 0.1)
	var ref2: WeakRef = weakref(s2)
	await get_tree().create_timer(0.3).timeout
	assert_object(ref2.get_ref()).is_null()
	assert_bool(is_instance_valid(s)).is_true()
	var ref: WeakRef = weakref(s)
	host.queue_free()
	await _frames(2)
	assert_object(ref.get_ref()).is_null()


# ---------------------------------------------------------------- 3. LEVEL UP

func test_the_level_up_says_level_up_over_level_n() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer(CardPool.level_up_offer(3), "LEVEL 3!", false)
	assert_str(cs.header.star_line.text()).is_equal("LEVEL UP")
	assert_str(cs.header.title.text).is_equal("LEVEL 3")
	assert_str(_texts(cs)).contains("LEVEL UP")
	# read over the shine (the review: the faintest words on the screen): STAR_LINE_PX and the kit's ink shadow under
	# its words and both stars, drawn behind each star
	_assert_shadowed(cs.header.star_line, CardScreen.STAR_LINE_SHADOW, CardScreen.STAR_LINE_PX)
	assert_int(CardScreen.STAR_LINE_PX).is_greater(30)
	# the title's middle follows the taller star line (the shine and the reveal's sun sit on it), once the header has
	# dropped in and the title stamped
	await get_tree().create_timer(0.5).timeout
	var mid := cs.header.title.get_global_rect().get_center().y
	assert_float(mid).is_equal_approx(CardScreen.TITLE_MID_Y + W.safe_top(), 2.0)
	# every other modal's star line stays as it was: 30 px, plain
	var plain := WModalHeader.make("LOOT", "CHEST")
	_assert_shadowed(plain.star_line, 0, 30)
	plain.free()
	# a mutation offer keeps its own head; its star line and row are read over the shine too
	cs.show_offer(CardPool.path_offer(Run.weapons[0]), "MUTATION", false, true)
	assert_bool(cs.header.visible).is_false()
	cs.skip_reel()
	var head_star: WStarLine = cs._path_head.get_child(0)
	_assert_shadowed(head_star, CardScreen.STAR_LINE_SHADOW, 30)
	for t in cs._path_row.get_children():
		if t is WText:
			assert_int((t as WText).shadow).is_equal(2)
	cs.visible = false
	await _frames(2)


## A star line's words at `px` with an ink shadow of `shadow` (0: none), and its stars with a shadow drawn behind them
## (or none).
func _assert_shadowed(s: WStarLine, shadow: int, px: int) -> void:
	assert_object(s).is_not_null()
	var stars := 0
	for k in s.get_children():
		if k is WText:
			assert_int((k as WText).shadow).is_equal(shadow)
			assert_int((k as WText).font_size).is_equal(px)
		elif k is Control:
			stars += 1
			var sh := (k as Control).get_node_or_null("Shadow") as CanvasItem
			if shadow > 0:
				assert_object(sh).is_not_null()
				assert_bool(sh.show_behind_parent).is_true()
			else:
				assert_object(sh).is_null()
	assert_int(stars).is_equal(2)


# ---------------------------------------------------------------- 4. the banish rule (code)

func test_run_never_banishes_what_the_hero_has() -> void:
	_start("drifter")
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.add_or_level_passive("brawn")
	var news := _new_passives(1)
	assert_int(news.size()).is_equal(1)
	var held_w := _card("weapon", Registry.weapon("boomstick"), 3, 4)
	var held_p := _card("passive", Registry.passive("brawn"), 1, 2)
	var new_p := _card("passive", news[0])
	var new_w: Dictionary = {}
	assert_str(Run.banish_refusal(held_w)).is_equal("held")
	assert_str(Run.banish_refusal(held_p)).is_equal("held")
	assert_str(Run.banish_refusal(new_p)).is_equal("")
	# a card for something held reads as held whatever its numbers say
	assert_str(Run.banish_refusal(_card("weapon", Registry.weapon("boomstick")))).is_equal("held")
	# an evolution of something held: a line's evolution card, a chest's weapon evolution
	var evo_line := _line_evolution_card()
	assert_bool(evo_line.is_empty()).is_false()
	assert_str(Run.banish_refusal(evo_line)).is_equal("evolution")
	var evo_w: WeaponDef = Registry.weapon(Registry.weapon("boomstick").evolves_into)
	assert_str(Run.banish_refusal({"type": "evolution", "id": evo_w.id, "def": evo_w, "src_id": "boomstick", "level_from": 0, "level_to": 1})).is_equal("evolution")
	assert_str(Run.banish_refusal({"type": "gold", "id": "", "def": null, "gold": 50})).is_equal("gold")
	# a path mutation of a weapon held: its evolution needs every one (a boss chest's pick)
	var path_m: MutationDef = Registry.mutations_of("boomstick")[0]
	assert_str(Run.banish_refusal(_card("mutation", path_m))).is_equal("path")
	# a hero's own mutation is optional: it may go
	for hm: MutationDef in Registry.hero_mutations("drifter"):
		if Run.family_instance(hm.weapon) == null:
			Run.add_weapon(Registry.weapon(hm.weapon), 1)
		assert_str(Run.banish_refusal(_card("mutation", hm))).is_equal("")
		break
	# a weapon the hero does not have (picked after the hero's mutation brought its weapon in)
	for w: WeaponDef in Registry.unlocked_weapons():
		if not Run.has_weapon(w.id):
			new_w = _card("weapon", w)
			break
	assert_bool(new_w.is_empty()).is_false()
	assert_str(Run.banish_refusal(new_w)).is_equal("")
	# refused: nothing spent, nothing struck
	Run.banishes_left = 1
	assert_bool(Run.banish_card(held_w)).is_false()
	assert_bool(Run.banish_card(evo_line)).is_false()
	assert_int(Run.banishes_left).is_equal(1)
	assert_bool(Run.banished.has("boomstick")).is_false()
	assert_bool(Run.banished.has(str(evo_line["id"]))).is_false()
	# a chest refuses the same, and spends nothing
	assert_bool(Run.chest_banish(held_w).is_empty()).is_true()
	assert_bool(Run.chest_banish(_card("mutation", path_m)).is_empty()).is_true()
	assert_int(Run.banishes_left).is_equal(1)
	# a new item goes: the stage's banish spent, the id out of the run
	assert_bool(Run.banish_card(new_p)).is_true()
	assert_int(Run.banishes_left).is_equal(0)
	assert_bool(Run.banished.has(news[0].id)).is_true()
	# none left: refused
	var other := _new_passives(1)
	assert_bool(Run.banish_card(_card("passive", other[0]))).is_false()
	# CardPool keeps only the cards that may go
	var table := [held_w, new_w, held_p]
	assert_array(CardPool.banishable(table)).is_equal([new_w])


func test_card_pool_never_offers_a_banished_id() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	# half of what may be found is banished
	var gone: Array = []
	var k := 0
	for p: PassiveDef in Registry.unlocked_passives():
		if k % 2 == 0:
			gone.append(p.id)
		k += 1
	for w: WeaponDef in Registry.unlocked_weapons():
		if w.id != "boomstick" and k % 2 == 0:
			gone.append(w.id)
		k += 1
	Run.banished = gone.duplicate()
	for i in range(60):
		for c in CardPool.level_up_offer(3):
			assert_bool(gone.has(str(c["id"]))).override_failure_message("offered a banished %s" % str(c["id"])).is_false()
		for c in CardPool.level_up_offer(1, ["boomstick"]):
			assert_bool(gone.has(str(c["id"]))).is_false()
	for i in range(30):
		var r := Run.chest_roll()
		assert_bool(gone.has(str(r.get("id", "")))).is_false()


## A hero's own mutation banished from a boss chest (the one mutation a boss chest lets go) is out of the run (the
## review: it stayed on the reel's list, came back on the respin and in 88 of 400 later boss chests): never on the list,
## the respin, a later boss chest, or the weapon's path offer.
func test_a_banished_hero_mutation_never_comes_back() -> void:
	_start("drifter")
	var hm: MutationDef = null
	for m: MutationDef in Registry.hero_mutations("drifter"):
		if Registry.weapon(m.weapon) != null:
			hm = m
			break
	assert_object(hm).is_not_null()
	var wi := Run.add_weapon(Registry.weapon(hm.weapon), 3)
	assert_bool(Run.boss_chest_mutations().has(hm)).is_true()
	assert_bool(Run.open_mutations(wi).has(hm)).is_true()
	# a boss chest lands on it: it may go
	Run.banishes_left = 1
	var roll := {"type": "mutation", "id": hm.id, "def": hm, "level_from": 0, "level_to": 1, "is_new": true, "boss": true}
	assert_str(Run.banish_refusal(roll)).is_equal("")
	var again := Run.chest_banish(roll)
	assert_bool(Run.banished.has(hm.id)).is_true()
	assert_int(Run.banishes_left).is_equal(0)
	assert_bool(again.is_empty()).is_false()
	assert_str(str(again.get("id", ""))).is_not_equal(hm.id)
	# gone from the reel's list, every later boss chest and the path offer
	assert_bool(Run.boss_chest_mutations().has(hm)).is_false()
	for i in 200:
		assert_str(str(Run.chest_roll(true).get("id", ""))).override_failure_message("a boss chest rolled the banished %s" % hm.id).is_not_equal(hm.id)
	assert_bool(Run.open_mutations(wi).has(hm)).is_false()
	for c in CardPool.path_offer(wi):
		assert_str(str(c["id"])).is_not_equal(hm.id)


## A base weapon whose evolution the hero carries is his (the review: a level-up offered the Boomstick again as NEW
## next to the Blunderbuss, banishable, and taken it was a second copy already carrying the whole path, a second
## evolution one chest later): no level-up or Stranger offer holds it, and a card for it reads as held.
func test_an_evolved_weapon_s_base_is_never_offered_again() -> void:
	_start("drifter")
	var base: WeaponDef = Registry.weapon("revolver")
	var w := Run.add_weapon(base, base.max_level)
	for m: MutationDef in Registry.mutations_of(base.id):
		Run.add_mutation(m.id, true)
	assert_bool(Run.evolution_ready(w)).is_true()
	assert_object(Run.evolve(w)).is_not_null()
	assert_bool(Run.has_weapon(base.id)).is_false()
	assert_object(Run.family_instance(base.id)).is_not_null()
	# it would be on the table without the rule: the run may find it, a weapon slot is free, the Stranger sells its rarity
	assert_bool(CardPool.offer_weapons().has(base)).is_true()
	assert_bool(Run.weapons.size() < Run.weapon_cap()).is_true()
	assert_bool(Run.STRANGER_SKIPS.has(base.rarity)).is_false()
	for i in 300:
		for c in CardPool.level_up_offer(3):
			assert_str(str(c["id"])).override_failure_message("a level-up offered %s again" % base.id).is_not_equal(base.id)
		assert_str(str(Run.stranger_offer().get("id", ""))).override_failure_message("the Stranger offered %s again" % base.id).is_not_equal(base.id)
	assert_str(Run.banish_refusal(_card("weapon", base))).is_equal("held")


# ---------------------------------------------------------------- 5. banish mode on the level-up

func test_banish_mode_refuses_a_held_card_and_strikes_a_new_one() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.banishes_left = 1
	var news := _new_passives(2)
	var held := _card("weapon", Registry.weapon("boomstick"), 3, 4)
	var a := _card("passive", news[0])
	var b := _card("passive", news[1])
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer([a, held, b], "LEVEL 4!", false)
	await _frames(2)
	assert_bool(cs._banish_btn.locked).is_false()
	cs._toggle_banish()
	assert_bool(cs.banish_mode()).is_true()
	# it says what it does: a red BANISH, the line in plain words, CANCEL on the button
	assert_str(cs.header.title.text).is_equal("BANISH")
	assert_bool(cs.header.title.color.is_equal_approx(W.ROCK)).is_true()
	# its star line names its moment, never "LEVEL UP" over BANISH (the review: Garry's "Level Up Banish?" spelled out)
	assert_str(cs.header.star_line.text()).is_equal(CardScreen.BANISH_KICKER.to_upper())
	assert_str(_texts(cs.header)).not_contains("LEVEL UP")
	assert_bool(cs._banish_wrap.visible).is_true()
	assert_str(cs._banish_note.text).contains("strike it from this run")
	assert_str(await _label(cs._banish_btn)).is_equal("CANCEL")
	# the held card is dimmed and says why; the new ones wear the stamp and the red band
	var held_card: WCard = cs._cards[1]
	assert_bool(held_card.locked).is_true()
	assert_str(str(cs._slots[1].get_node("BanishMark").style)).is_equal("held")
	for i in [0, 2]:
		assert_bool((cs._cards[i] as WCard).locked).is_false()
		assert_str(str(cs._slots[i].get_node("BanishMark").style)).is_equal("strike")
		assert_bool(((cs._cards[i] as WCard).box as HardBox).inner_color.is_equal_approx(W.ROCK)).is_true()
	# a tap on the held card: nothing spent, nothing struck, the card stays, the line says why
	var banished_before := Run.banished.duplicate()
	cs._pick(held, held_card)
	assert_array(Run.banished).is_equal(banished_before)
	assert_int(Run.banishes_left).is_equal(1)
	assert_bool(cs.banish_mode()).is_true()
	assert_str(str(cs._offer[1]["id"])).is_equal("boomstick")
	assert_object(cs._cards[1]).is_same(held_card)
	assert_str(cs._banish_note.text).is_equal(CardScreen.refusal_line(held, "held"))
	assert_str(cs._banish_note.text).contains("You have")
	# a tap on a new card: struck, the banish spent, banish mode over, the line names it, a new card in its place
	cs._pick(a, cs._cards[0])
	assert_bool(Run.banished.has(str(a["id"]))).is_true()
	assert_int(Run.banishes_left).is_equal(0)
	assert_bool(cs.banish_mode()).is_false()
	assert_str(cs.header.line.text).contains("%s is banished" % (a["def"] as ContentDef).display_name)
	assert_str(cs.header.title.text).is_equal("LEVEL 4")
	assert_str(cs.header.star_line.text()).is_equal("LEVEL UP")
	assert_int(cs._offer.size()).is_equal(3)
	assert_str(str(cs._offer[0]["id"])).is_not_equal(str(a["id"]))
	assert_str(str(cs._offer[1]["id"])).is_equal("boomstick")
	assert_str(str(cs._offer[2]["id"])).is_equal(str(b["id"]))
	assert_int(cs._cards.size()).is_equal(3)
	# the struck card stays a moment as a ghost stamped BANISHED, then goes
	var ghost: Node = null
	for c in cs.get_children():
		if str(c.name).begins_with("Struck"):
			ghost = c
	assert_object(ghost).is_not_null()
	assert_str(str(ghost.get_node("BanishMark").style)).is_equal("banished")
	# the replacement takes no finger until it has dropped in
	assert_int((cs._cards[0] as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	await get_tree().create_timer(CardScreen.STRIKE_SLAM + CardScreen.STRIKE_HOLD + CardScreen.STRIKE_FADE + 0.4).timeout
	assert_bool(is_instance_valid(ghost)).is_false()
	assert_int((cs._cards[0] as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	# every card back to its own look, the button locked (no banish left)
	for i in 3:
		assert_bool((cs._cards[i] as WCard).locked).is_false()
		assert_str(str(cs._slots[i].get_node("BanishMark").style)).is_equal("")
	assert_bool(cs._banish_btn.locked).is_true()
	cs.visible = false
	await _frames(2)


func test_banish_locks_when_every_card_is_held_and_cancel_goes_back() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	Run.add_or_level_passive("brawn")
	Run.banishes_left = 1
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	var all_held := [_card("weapon", Registry.weapon("boomstick"), 3, 4), _card("weapon", Registry.weapon("peashooter"), 2, 3),
		_card("passive", Registry.passive("brawn"), 1, 2)]
	cs.show_offer(all_held, "LEVEL 5!", false)
	assert_bool(cs._banish_btn.locked).is_true()
	cs._toggle_banish()
	assert_bool(cs.banish_mode()).is_false()
	assert_str(cs.header.line.text).is_equal(CardScreen.NOTHING_TO_BANISH)
	assert_int(Run.banishes_left).is_equal(1)
	# the row keeps its three even buttons (a tap on a locked BANISH had pushed it off the screen's edge)
	await _frames(3)
	var w0: float = cs._reroll_btn.size.x
	for b: WButton in [cs._skip_btn, cs._banish_btn]:
		assert_float(b.size.x).is_equal_approx(w0, 1.0)
	assert_float(cs._banish_btn.get_global_rect().end.x).is_less_equal(cs.get_viewport_rect().size.x)
	# words set only when they change: a second refresh queues nothing
	cs._refresh_buttons()
	for b: WButton in [cs._reroll_btn, cs._skip_btn, cs._banish_btn]:
		assert_int(b._row.get_child_count()).is_equal(1)
	# a table with one new item: on, then CANCEL takes it back to the level-up as it was
	var news := _new_passives(1)
	cs.show_offer([all_held[0], _card("passive", news[0]), all_held[2]], "LEVEL 5!", true)
	assert_bool(cs._banish_btn.locked).is_false()
	cs._toggle_banish()
	assert_bool(cs.banish_mode()).is_true()
	cs._toggle_banish()
	assert_bool(cs.banish_mode()).is_false()
	assert_str(cs.header.title.text).is_equal("LEVEL 5")
	assert_str(cs.header.star_line.text()).is_equal("LEVEL UP")
	assert_bool(cs.header.title.color.is_equal_approx(W.PAPER)).is_true()
	assert_str(cs.header.line.text).is_equal(CardScreen.HINT_LINE)
	assert_bool(cs._banish_wrap.visible).is_false()
	assert_str(await _label(cs._banish_btn)).is_equal("BANISH ×1")
	for i in 3:
		assert_bool((cs._cards[i] as WCard).locked).is_false()
		assert_str(str(cs._slots[i].get_node("BanishMark").style)).is_equal("")
		var tag = (cs._cards[i] as WCard).get("tag_node")
		if tag is CanvasItem:
			assert_float((tag as CanvasItem).modulate.a).is_equal(1.0)
	assert_int(Run.banishes_left).is_equal(1)
	assert_bool(Run.banished.is_empty()).is_true()
	cs.visible = false
	await _frames(2)


func test_the_first_banish_mode_says_more() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.banishes_left = 1
	(Save.data["hints_seen"] as Array).erase("banish")
	var news := _new_passives(2)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer([_card("passive", news[0]), _card("weapon", Registry.weapon("boomstick"), 3, 4), _card("passive", news[1])], "LEVEL 4!", false)
	cs._toggle_banish()
	assert_str(cs._banish_note.text).is_equal(CardScreen.BANISH_FIRST)
	assert_str(cs._banish_note.text).contains("can't be banished")
	assert_bool(Save.hint_seen("banish")).is_true()
	cs._toggle_banish()
	cs._toggle_banish()
	assert_str(cs._banish_note.text).is_equal(CardScreen.BANISH_LINE)
	# the cards never run over banish mode's taller header
	await _frames(3)
	var foot := cs.header_foot()
	assert_float((cs._slots[0] as Control).get_global_rect().position.y).is_greater_equal(foot)
	cs.visible = false
	await _frames(2)



# ---------------------------------------------------------------- 6. the review round's banish mode

## A refused REROLL or SKIP in banish mode says so, then the mode's own words come back (the review: they had replaced
## them until the mode was opened again); a held card's refusal the same; banish mode stays on throughout.
func test_a_refusal_in_banish_mode_stands_a_moment_then_its_words_come_back() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.banishes_left = 1
	Run.rerolls_left = 0
	Run.skips_left = 0
	var news := _new_passives(2)
	var held := _card("weapon", Registry.weapon("boomstick"), 3, 4)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer([_card("passive", news[0]), held, _card("passive", news[1])], "LEVEL 4!", false)
	cs._toggle_banish()
	assert_bool(cs.banish_mode()).is_true()
	var words := cs.banish_line()
	assert_str(words).is_not_empty()
	assert_str(cs._banish_note.text).is_equal(words)
	for tap: Callable in [cs._reroll, cs._skip, func(): cs._pick(held, cs._cards[1])]:
		tap.call()
		assert_bool(cs.visible).is_true()
		assert_bool(cs.banish_mode()).is_true()
		assert_str(cs._banish_note.text).is_not_equal(words)
		await get_tree().create_timer(CardScreen.NOTE_HOLD * 0.5).timeout
		assert_str(cs._banish_note.text).is_not_equal(words)
		await get_tree().create_timer(CardScreen.NOTE_HOLD * 0.5 + 0.25).timeout
		assert_str(cs._banish_note.text).is_equal(words)
	# nothing was spent by any of them
	assert_int(Run.banishes_left).is_equal(1)
	assert_bool(Run.banished.is_empty()).is_true()
	# a refusal that lands as the mode ends leaves the level-up's header alone
	cs._reroll()
	cs._toggle_banish()
	await get_tree().create_timer(CardScreen.NOTE_HOLD + 0.25).timeout
	assert_bool(cs.banish_mode()).is_false()
	assert_bool(cs._banish_wrap.visible).is_false()
	assert_str(cs.header.title.text).is_equal("LEVEL 4")
	cs.visible = false
	await _frames(2)


## A reroll while the struck card's ghost still fades takes the ghost with the old table (the review: it faded over the
## new first card).
func test_a_reroll_takes_the_struck_card_s_ghost() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 3)
	Run.banishes_left = 1
	Run.rerolls_left = 1
	var news := _new_passives(2)
	var a := _card("passive", news[0])
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	cs.show_offer([a, _card("weapon", Registry.weapon("boomstick"), 3, 4), _card("passive", news[1])], "LEVEL 4!", false)
	cs._toggle_banish()
	cs._pick(a, cs._cards[0])
	assert_bool(Run.banished.has(str(a["id"]))).is_true()
	var ghosts := cs.get_children().filter(func(n: Node) -> bool: return str(n.name).begins_with("Struck"))
	assert_int(ghosts.size()).is_equal(1)
	cs._reroll()
	await _frames(1)
	var left := cs.get_children().filter(func(n: Node) -> bool: return str(n.name).begins_with("Struck"))
	assert_int(left.size()).is_equal(0)
	assert_int(cs._cards.size()).is_equal(3)
	cs.visible = false
	await _frames(2)
