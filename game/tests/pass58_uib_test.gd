extends GdUnitTestSuite

## Pass 58, lane UIB (Garry, 2026-10-07: "There should be some kind of an indicator on items when they are upgraded
## rather than a new item. I mean in the level-up and chest screens during gameplay. Maybe the new star is pulsating in
## an animated way. Maybe there's a word "upgrade." ... Maybe we show which stats are actually changing as well with the
## upgrade, rather than just giving the line with a little arrow that shows a number turning into a different one", and
## "Banish option should not allow Banishing items that Player already has"): a card says UPGRADE, NEW or EVOLUTION in a
## tag beside its word; an upgrade lists the stats it changes before and after (TextGen.weapon_changes on the hero's own
## copy of the weapon, TextGen.passive_changes on a line or a passive item), at most four rows, in place of its "Next:"
## line; its new stars pulse; the chest's landed item does the same; the chest never banishes the next level of something
## the hero holds, nor a mutation on the path of one of his weapons (Run.banish_refusal, the game's one rule), and says
## why; the chest opens over a turning shine.

const WChestScript := preload("res://ui/wanted/WChest.gd")


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Run.end()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


## The chest's intro skipped and its reel hurried until it lands.
func _land(cs: ChestScreen) -> void:
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 60:
		await get_tree().process_frame
		if not cs._spinning:
			break


func _rows(box: Node) -> Array:
	return box.get_children().filter(func(n: Node) -> bool: return n is WCard.ChangeRow)


func _tag_word(tag: Node) -> String:
	var w := tag.find_child("Word", true, false) as WText
	return w.text if w else ""


## The damage a weapon's sheet holds at `level`, worked out from its data alone: base x every damage multiplier of its
## levels so far x the hero's attack damage (the card's numbers must be the ones the hero will fight with).
func _damage_at(def: WeaponDef, level: int) -> float:
	var v := float(def.base.get("damage", 5.0))
	var adds := 0.0
	var mul := 1.0
	for e: Effect in def.effects_for_level(level):
		if e.stat == "damage":
			if e.op == "mul":
				mul *= 1.0 + e.value
			elif e.op == "add":
				adds += e.value
	return (v + adds) * mul * Run.player_sheet.get_stat("might", 1.0)


# ---------------------------------------------------------------- 1. upgrade versus new

func test_a_held_weapon_s_card_says_upgrade_and_lists_what_changes() -> void:
	_start()
	var pea: WeaponDef = Registry.weapon("peashooter")
	Run.add_weapon(pea, 2)
	# the level a damage multiplier comes in at, past the one held
	var to := -1
	for lv in range(3, pea.max_level + 1):
		for e: Effect in pea.effects_at_level(lv):
			if e.stat == "damage" and to < 0:
				to = lv
	assert_int(to).override_failure_message("the Peashooter's damage never grows past level 2").is_greater(0)
	var card := {"def": pea, "level_from": to - 1, "level_to": to}
	Run.weapon_instance("peashooter").level = to - 1
	Run.weapon_instance("peashooter").rebuild(Run.player_sheet, Run.weapons)
	assert_str(WItem.tag(card)).is_equal("UPGRADE")
	assert_str(WItem.word(card)).is_equal("WEAPON")
	var rows := WItem.changes(card)
	assert_int(rows.size()).is_between(1, TextGen.CHANGE_ROWS)
	var dmg: Array = rows.filter(func(r: Dictionary) -> bool: return r["stat"] == "damage")
	assert_int(dmg.size()).is_equal(1)
	var want := TextGen._tidy_pair(TextGen.format_value("damage", _damage_at(pea, to - 1)), TextGen.format_value("damage", _damage_at(pea, to)))
	assert_str(str(dmg[0]["before"])).is_equal(str(want[0]))
	assert_str(str(dmg[0]["after"])).is_equal(str(want[1]))
	assert_str(str(dmg[0]["name"])).is_equal("Damage")
	assert_bool(bool(dmg[0]["worse"])).is_false()
	# only what changes: every row's two numbers differ, and the estimate is never a row
	for r: Dictionary in rows:
		assert_str(str(r["before"])).is_not_equal(str(r["after"]))
		assert_str(str(r["stat"])).is_not_equal("dps")
	# every stat the level moves is there
	for e: Effect in pea.effects_at_level(to):
		assert_bool(rows.any(func(r: Dictionary) -> bool: return r["stat"] == e.stat)).override_failure_message(e.stat).is_true()
	# the card: the tag at the word line's end, the rows in place of the "Next:" line, the new star pulsing
	var c: WCard = auto_free(WCard.make(pea, WItem.options(card)))
	assert_object(c.tag_node).is_not_null()
	assert_str(_tag_word(c.tag_node)).is_equal("UPGRADE")
	assert_bool((c.tag_node.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.BRASS)).is_true()
	assert_object(c.changes_box).is_not_null()
	assert_object(c.effect_text).is_null()
	var cr: Array = _rows(c.changes_box)
	assert_int(cr.size()).is_equal(rows.size())
	var first: WCard.ChangeRow = cr[0]
	assert_str(first.name_text.text).is_equal(str(rows[0]["name"]))
	assert_str(str(first.values.runs[0][0])).is_equal(str(rows[0]["before"]))
	assert_str(str(first.values.runs[2][0])).is_equal(str(rows[0]["after"]))
	# the new number in Bitter 800, the old one plain
	assert_object(first.values.runs[2][2]).is_same(W.serif(W.BOLD_WEIGHT))
	assert_object(first.values.runs[0][2]).is_same(W.serif(400))
	assert_object(c.marks).is_not_null()
	assert_bool(c.marks.pulse).is_true()
	# the "Next:" line the rows replace is still what the arena's INFO and the Collection read
	assert_str(WItem.effect(card)).starts_with("Next: ")


func test_rows_follow_the_hero_s_sheet_and_cap_at_four() -> void:
	_start()
	var hammer: WeaponDef = Registry.weapon("hammer")
	Run.add_weapon(hammer, hammer.max_level - 1)
	var card := {"def": hammer, "level_from": hammer.max_level - 1, "level_to": hammer.max_level}
	var rows := WItem.changes(card)
	assert_int(rows.size()).is_between(1, TextGen.CHANGE_ROWS)
	# a weapon's numbers at both levels as the pause screen would show them for the hero (his might folded in)
	var a := WeaponInstance.new(hammer, hammer.max_level - 1)
	a.rebuild(Run.player_sheet, Run.weapons)
	var b := WeaponInstance.new(hammer, hammer.max_level)
	b.rebuild(Run.player_sheet, Run.weapons)
	for r: Dictionary in rows:
		var st := str(r["stat"])
		if st == "area":
			# the Hammer's area is its blast's radius, read in metres (fix round: TextGen.area_radius)
			var rr := TextGen._tidy_pair("%.1f m" % float(TextGen.area_radius(hammer, a.sheet, a.params)[1]),
				"%.1f m" % float(TextGen.area_radius(hammer, b.sheet, b.params)[1]))
			assert_str(str(r["name"])).is_equal("Blast radius")
			assert_str(str(r["before"])).is_equal(str(rr[0]))
			assert_str(str(r["after"])).is_equal(str(rr[1]))
		elif a.sheet.has_stat(st):
			var pair := TextGen._tidy_pair(TextGen.format_value(st, a.stat(st)), TextGen.format_value(st, b.stat(st)))
			assert_str(str(r["before"])).override_failure_message(st).is_equal(str(pair[0]))
			assert_str(str(r["after"])).override_failure_message(st).is_equal(str(pair[1]))
	# more attack damage on the hero shows in the card's damage numbers
	Run.player_sheet.add_effect(Effect.make("might", "mul", 1.0), "test")
	var pea: WeaponDef = Registry.weapon("peashooter")
	var lv := -1
	for k in range(2, pea.max_level + 1):
		if lv < 0 and pea.effects_at_level(k).any(func(e: Effect) -> bool: return e.stat == "damage"):
			lv = k
	var might := Run.player_sheet.get_stat("might", 1.0)
	assert_float(might).is_greater_equal(2.0)
	var doubled: Array = TextGen.weapon_changes(pea, lv - 1, lv, null, Run.player_sheet, Run.weapons).filter(func(r: Dictionary) -> bool: return r["stat"] == "damage")
	var plain: Array = TextGen.weapon_changes(pea, lv - 1, lv, null, null, []).filter(func(r: Dictionary) -> bool: return r["stat"] == "damage")
	assert_float(float(str(doubled[0]["after"]))).is_equal_approx(might * float(str(plain[0]["after"])), 0.06 * might)
	# never more than four rows, never a row that does not change, nothing for a new weapon or an evolution
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution:
			assert_array(TextGen.weapon_changes(w, 1, 2)).is_empty()
			continue
		for k in range(1, w.max_level):
			var rr := TextGen.weapon_changes(w, k, k + 1)
			assert_int(rr.size()).override_failure_message("%s %d" % [w.id, k]).is_less_equal(TextGen.CHANGE_ROWS)
			for r: Dictionary in rr:
				assert_str(str(r["before"])).override_failure_message("%s %d %s" % [w.id, k, r["stat"]]).is_not_equal(str(r["after"]))
		assert_array(TextGen.weapon_changes(w, 0, 1)).is_empty()


func test_a_new_item_says_new_and_keeps_its_line() -> void:
	_start()
	var magnet: PassiveDef = Registry.passive("magnet")
	var card := {"def": magnet, "level_from": 0, "level_to": 1}
	assert_str(WItem.tag(card)).is_equal("NEW")
	assert_str(WItem.word(card)).is_equal("PASSIVE")
	assert_array(WItem.changes(card)).is_empty()
	var c: WCard = auto_free(WCard.make(magnet, WItem.options(card)))
	assert_str(_tag_word(c.tag_node)).is_equal("NEW")
	assert_bool((c.tag_node.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.SAGE)).is_true()
	assert_object(c.changes_box).is_null()
	assert_object(c.effect_text).is_not_null()
	assert_str(c.effect_text.text).is_equal(WItem.effect(card))
	# a new item's stars stand still: nothing of it is "this pick" on top of a level held
	assert_bool(c.marks.pulse).is_false()
	# a new weapon and a new line the same
	var pea := {"def": Registry.weapon("peashooter"), "level_from": 0, "level_to": 1}
	assert_str(WItem.tag(pea)).is_equal("NEW")
	assert_str(WItem.word(pea)).is_equal("WEAPON")
	assert_array(WItem.changes(pea)).is_empty()
	var brawn := {"def": Registry.passive("brawn"), "level_from": 0, "level_to": 1}
	assert_str(WItem.tag(brawn)).is_equal("NEW")
	assert_str(WItem.word(brawn)).is_equal("LINE")


func test_a_line_s_next_rank_lists_its_change() -> void:
	_start()
	var brawn: PassiveDef = Registry.passive("brawn")
	var card := {"def": brawn, "level_from": 2, "level_to": 3}
	assert_str(WItem.tag(card)).is_equal("UPGRADE")
	var rows := WItem.changes(card)
	assert_int(rows.size()).is_greater(0)
	# the summed effect at each rank, as the pause screen sums it
	for e: Effect in TextGen._sum_effects(brawn.effects_for_level(3)):
		var before := 0.0
		for e0: Effect in TextGen._sum_effects(brawn.effects_for_level(2)):
			if e0.stat == e.stat and e0.op == e.op:
				before = e0.value
		var row: Array = rows.filter(func(r: Dictionary) -> bool: return r["stat"] == e.stat)
		if TextGen.change_value(e.stat, e.op, before) == TextGen.change_value(e.stat, e.op, e.value):
			continue
		assert_int(row.size()).override_failure_message(e.stat).is_equal(1)
		assert_str(str(row[0]["before"])).is_equal(TextGen.change_value(e.stat, e.op, before))
		assert_str(str(row[0]["after"])).is_equal(TextGen.change_value(e.stat, e.op, e.value))
		assert_str(str(row[0]["name"])).starts_with(TextGen._sentence(TextGen.stat_name(e.stat)))
	# the card shows them
	var c: WCard = auto_free(WCard.make(brawn, WItem.options(card)))
	assert_int(_rows(c.changes_box).size()).is_equal(rows.size())
	# a trade's growing price is a row of its own, its new number in dark red (Thirst: life steal for max HP)
	var thirst: PassiveDef = Registry.passive("thirst")
	var tr := TextGen.passive_changes(thirst, 1, 2)
	var hp: Array = tr.filter(func(r: Dictionary) -> bool: return r["stat"] == "max_hp")
	if thirst.trade != "" and not hp.is_empty():
		assert_bool(bool(hp[0]["worse"])).is_true()
		var tc: WCard = auto_free(WCard.make(thirst, WItem.options({"def": thirst, "level_from": 1, "level_to": 2})))
		var hr: Array = _rows(tc.changes_box).filter(func(n: WCard.ChangeRow) -> bool: return n.stat == "max_hp")
		assert_bool((hr[0] as WCard.ChangeRow).values.runs[2][1].is_equal_approx(W.BAD_DARK)).is_true()
	# a shorter cooldown is a gain, a longer one a loss
	assert_bool(TextGen._worse("cooldown", 1.0, 0.9)).is_false()
	assert_bool(TextGen._worse("cooldown", 1.0, 1.1)).is_true()
	assert_bool(TextGen._worse("damage", 10.0, 12.0)).is_false()
	assert_bool(TextGen._worse("max_hp", -0.05, -0.1)).is_true()
	# the numbers worded like the cards word them
	assert_str(TextGen.change_value("area", "mul", 0.16)).is_equal("+16%")
	assert_str(TextGen.change_value("max_hp", "mul", -0.05)).is_equal("−5%")
	assert_str(TextGen.change_value("amount", "add", 2.0)).is_equal("+2")
	assert_str(TextGen.change_value("barrel_seconds", "add", 3.75)).is_equal("+3.75 s")
	assert_str(TextGen.change_value("damage_reduction", "add", 0.0)).is_equal("0%")
	assert_array(TextGen._tidy_pair("12.00 s", "16.00 s")).is_equal(["12 s", "16 s"])
	assert_array(TextGen._tidy_pair("1.10 s", "0.95 s")).is_equal(["1.10 s", "0.95 s"])
	assert_array(TextGen._tidy_pair("11.5", "15.0")).is_equal(["11.5", "15.0"])
	# every line and passive item: at most four rows, each a real change
	for p: PassiveDef in Registry.passives.values():
		for k in range(1, p.max_level):
			var pr := TextGen.passive_changes(p, k, k + 1)
			assert_int(pr.size()).override_failure_message("%s %d" % [p.id, k]).is_less_equal(TextGen.CHANGE_ROWS)
			for r: Dictionary in pr:
				assert_str(str(r["before"])).is_not_equal(str(r["after"]))


func test_evolutions_say_evolution_and_mutations_and_perks_are_unchanged() -> void:
	_start()
	var juggernaut := {"def": Registry.passive("juggernaut"), "level_from": 4, "level_to": 5, "evolve": true}
	assert_str(WItem.tag(juggernaut)).is_equal("EVOLUTION")
	assert_str(WItem.word(juggernaut)).is_equal("EVOLVES BRAWN")
	assert_array(WItem.changes(juggernaut)).is_empty()
	var jc: WCard = auto_free(WCard.make(juggernaut["def"], WItem.options(juggernaut)))
	assert_str(_tag_word(jc.tag_node)).is_equal("EVOLUTION")
	assert_bool((jc.tag_node.get_theme_stylebox("panel") as HardBox).fill.is_equal_approx(W.EMBER)).is_true()
	# its ember band stays
	assert_int((jc.box as HardBox).inner).is_greater(0)
	var boom: WeaponDef = Registry.weapon("boomstick")
	var evo: WeaponDef = Registry.weapon(boom.evolves_into)
	var ec := {"type": "evolution", "id": evo.id, "def": evo, "src_id": boom.id, "level_from": 0, "level_to": 1}
	assert_str(WItem.tag(ec)).is_equal("EVOLUTION")
	assert_str(WItem.word(ec)).is_equal("EVOLVES " + boom.display_name.to_upper())
	# a mutation and a perk: no tag, their words and lines as before
	var mut := {"def": Registry.mutations_of("boomstick")[0], "level_from": 0, "level_to": 1}
	assert_str(WItem.tag(mut)).is_equal("")
	assert_str(WItem.word(mut)).is_equal("MUTATION")
	var mc: WCard = auto_free(WCard.make(mut["def"], WItem.options(mut)))
	assert_object(mc.tag_node).is_null()
	assert_object(mc.changes_box).is_null()
	var perk := {"def": Registry.perk("thruster_burst"), "level_from": 0, "level_to": 1}
	assert_str(WItem.tag(perk)).is_equal("")
	assert_str(WItem.word(perk)).ends_with("'S PERK · ONCE")


# ---------------------------------------------------------------- 2. the pulsing star

func test_the_new_star_pulses() -> void:
	var m: WMarks = auto_free(WMarks.new().setup("stars", 5, 2, 3, 40.0))
	m.pulse = m.has_next()
	add_child(m)
	assert_bool(m.pulse).is_true()
	assert_bool(m.is_processing()).is_true()
	assert_float(m.pulse_scale()).is_equal_approx(1.0, 0.001)
	m._process(WMarks.PULSE_PERIOD * 0.25)
	var quarter := m.pulse_scale()
	m._process(WMarks.PULSE_PERIOD * 0.25)
	var half := m.pulse_scale()
	assert_float(quarter).is_greater(1.0)
	assert_float(half).is_equal_approx(1.0 + WMarks.PULSE_SCALE, 0.001)
	# and back: the loop closes on a whole period
	m._process(WMarks.PULSE_PERIOD * 0.5)
	assert_float(m.pulse_scale()).is_equal_approx(1.0, 0.001)
	# it ticks on its own while it is in the tree, even with the run paused under the level-up
	m._process(WMarks.PULSE_PERIOD * 0.1)
	var before := m.pulse_scale()
	await _frames(6)
	assert_float(m.pulse_scale()).is_not_equal(before)
	# the pause screen's stars and a new item's stand still
	var still: WMarks = auto_free(WMarks.new().setup("stars", 5, 3, -1, 34.0))
	add_child(still)
	assert_bool(still.pulse).is_false()
	assert_bool(still.has_next()).is_false()
	still._process(0.4)
	assert_float(still.pulse_scale()).is_equal(1.0)
	assert_bool(still.is_processing()).is_false()
	remove_child(m)
	remove_child(still)


# ---------------------------------------------------------------- 3. the chest

func test_the_chest_never_banishes_a_held_item() -> void:
	_start()
	var boom: WeaponDef = Registry.weapon("boomstick")
	Run.add_weapon(boom, 2)
	Run.add_or_level_passive("brawn")
	var magnet: PassiveDef = Registry.passive("magnet")
	assert_int(Run.passive_level("magnet")).is_equal(0)
	var held_w := {"type": "weapon", "id": boom.id, "def": boom, "level_from": 2, "level_to": 3, "is_new": false}
	var held_p := {"type": "passive", "id": "brawn", "def": Registry.passive("brawn"), "level_from": 1, "level_to": 2, "is_new": false}
	var fresh := {"type": "passive", "id": "magnet", "def": magnet, "level_from": 0, "level_to": 1, "is_new": true}
	var evo: WeaponDef = Registry.weapon(boom.evolves_into)
	var mut: MutationDef = Registry.mutations_of("boomstick")[0]
	assert_bool(ChestScreen.can_banish(held_w)).is_false()
	assert_bool(ChestScreen.can_banish(held_p)).is_false()
	assert_bool(ChestScreen.can_banish(fresh)).is_true()
	assert_bool(ChestScreen.can_banish({"type": "evolution", "id": evo.id, "def": evo, "src_id": boom.id})).is_false()
	assert_bool(ChestScreen.can_banish({"type": "mutation", "id": mut.id, "def": mut, "boss": true})).is_false()
	# a hero's own mutation too (pass 60, Garry: "mutations shouldn't be banishable anywhere")
	var hm: MutationDef = Registry.mutation("danza_macabra")
	assert_bool(hm.is_hero()).is_true()
	assert_bool(ChestScreen.can_banish({"type": "mutation", "id": hm.id, "def": hm, "boss": true})).is_false()
	assert_bool(ChestScreen.can_banish({"type": "gold", "def": null})).is_false()
	# a roll with no level on it still counts what the hero holds
	assert_bool(ChestScreen.can_banish({"type": "weapon", "id": boom.id, "def": boom})).is_false()
	# the words say why, plainly
	assert_str(ChestScreen.banish_refusal(held_w)).is_equal("You have %s. Only new items can be banished." % boom.display_name)
	assert_str(ChestScreen.banish_refusal(held_p)).contains("You have Brawn")
	assert_str(ChestScreen.banish_refusal({"type": "mutation", "id": mut.id, "def": mut})).is_equal("A mutation cannot be banished.")
	assert_str(ChestScreen.banish_refusal({"type": "mutation", "id": hm.id, "def": hm, "boss": true})).is_equal("A mutation cannot be banished.")
	assert_str(ChestScreen.banish_refusal({"type": "evolution", "id": evo.id, "def": evo})).is_equal("An evolution cannot be banished.")
	assert_str(ChestScreen.banish_refusal({"type": "gold", "def": null})).is_equal("Gold cannot be banished.")
	assert_str(ChestScreen.banish_refusal(fresh)).is_equal("")
	# on the screen: BANISH locked on the held weapon, a tap says why and spends nothing
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	var left := Run.banishes_left
	assert_int(left).is_greater(0)
	cs.open(held_w)
	await _land(cs)
	assert_bool(cs._banish_btn.locked).is_true()
	cs._banish()
	assert_str(cs.header.line.text).is_equal(ChestScreen.banish_refusal(held_w))
	assert_int(cs.respins).is_equal(0)
	assert_int(Run.banishes_left).is_equal(left)
	assert_bool(Run.banished.has(boom.id)).is_false()
	# a new passive item can go: the banish is spent and the reel spins again
	cs.open(fresh)
	await _land(cs)
	assert_bool(cs._banish_btn.locked).is_false()
	cs._banish()
	assert_int(cs.respins).is_equal(1)
	assert_int(Run.banishes_left).is_equal(left - 1)
	assert_bool(Run.banished.has("magnet")).is_true()
	await _land(cs)
	cs.visible = false


func test_the_chest_s_landed_item_says_upgrade_or_new() -> void:
	_start()
	var boom: WeaponDef = Registry.weapon("boomstick")
	Run.add_weapon(boom, 2)
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	var up := {"type": "weapon", "id": boom.id, "def": boom, "level_from": 2, "level_to": 3, "is_new": false}
	cs.open(up)
	await _land(cs)
	assert_object(cs._tag).is_not_null()
	assert_str(_tag_word(cs._tag)).is_equal("UPGRADE")
	assert_str(cs._word.text).is_equal("WEAPON")
	assert_object(cs._marks).is_not_null()
	assert_bool(cs._marks.pulse).is_true()
	var rows := WItem.changes(up)
	assert_int(rows.size()).is_greater(0)
	assert_object(cs._changes).is_not_null()
	assert_int(_rows(cs._changes).size()).is_equal(rows.size())
	assert_bool(cs._changes_host.visible).is_true()
	assert_bool(cs._effect.visible).is_false()
	# a new passive item: NEW, its line, no rows, the old tag gone
	var magnet: PassiveDef = Registry.passive("magnet")
	cs.open({"type": "passive", "id": "magnet", "def": magnet, "level_from": 0, "level_to": 1, "is_new": true})
	await _land(cs)
	assert_str(_tag_word(cs._tag)).is_equal("NEW")
	assert_int(cs._word_row.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Tag")).size()).is_equal(1)
	assert_object(cs._changes).is_null()
	assert_bool(cs._changes_host.visible).is_false()
	assert_bool(cs._effect.visible).is_true()
	assert_str(cs._effect.text).is_equal(WItem.effect({"type": "passive", "id": "magnet", "def": magnet, "level_from": 0, "level_to": 1, "is_new": true}))
	assert_bool(cs._marks.pulse).is_false()
	# gold: no tag, no stars, its own line
	cs.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	await _land(cs)
	assert_object(cs._tag).is_null()
	assert_object(cs._marks).is_null()
	assert_str(cs._word.text).is_equal("GOLD")
	cs.visible = false


func test_the_chest_opens_over_a_turning_shine() -> void:
	_start()
	var boom: WeaponDef = Registry.weapon("boomstick")
	Run.add_weapon(boom, 2)
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	var shine := cs.find_child("Shine", false, false) as Control
	assert_object(shine).is_not_null()
	assert_str((shine.get_script() as Script).resource_path).is_equal("res://ui/wanted/WShine.gd")
	# over the dim, under the chest's light, the reel, the chest and the result
	assert_int(shine.get_index()).is_greater(cs.dim.get_index())
	for n: Node in [cs._beam, cs._reel, cs._chest, cs._panel, cs.buttons]:
		assert_int(shine.get_index()).is_less(n.get_index())
	assert_bool(shine.visible).is_false()
	cs.open({"type": "weapon", "id": boom.id, "def": boom, "level_from": 2, "level_to": 3, "is_new": false})
	assert_bool(shine.visible).is_true()
	# behind the chest while it opens, in brass: nothing yet as it drops, then grown in by the time the lid is open
	cs._intro_at(0.0)
	assert_float(float(shine.get("grow"))).is_equal_approx(0.0, 0.001)
	cs._intro_at(WChestScript.OPEN + 0.14)
	assert_float(float(shine.get("grow"))).is_greater(0.95)
	assert_float(float(shine.get("fade"))).is_equal_approx(1.0, 0.001)
	assert_bool((shine.get("center") as Vector2).is_equal_approx(cs._mouth)).is_true()
	assert_bool((shine.get("color") as Color).is_equal_approx(W.BRASS)).is_true()
	# it turns while the run is paused under the chest
	var a0: float = shine.call("angle")
	await _frames(6)
	assert_float(float(shine.call("angle"))).is_not_equal(a0)
	# carried up with the light to the landing cell, dimmed while the reel runs, full again once it lands, and it stays
	cs._intro_at(WChestScript.LIFE)
	assert_bool((shine.get("center") as Vector2).is_equal_approx(cs.landing_center())).is_true()
	assert_float(float(shine.get("strength"))).is_equal_approx(ChestScreen.SHINE_SPIN, 0.001)
	await _land(cs)
	await get_tree().create_timer(0.6).timeout
	assert_bool(shine.visible).is_true()
	assert_float(float(shine.get("strength"))).is_equal_approx(1.0, 0.01)
	assert_bool((shine.get("center") as Vector2).is_equal_approx(cs.landing_center())).is_true()
	# never over the landed plate: the plate is in the reel, drawn after the shine
	assert_bool(cs._hero.is_inside_tree() and cs._hero.get_parent() == cs._reel).is_true()
	# the boss's chest: the shine in its violet
	var cs2: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs2)
	await get_tree().process_frame
	var roll := Run.chest_roll(true)
	assert_str(str(roll.get("type", ""))).is_equal("mutation")
	cs2.open(roll)
	var s2 := cs2.find_child("Shine", false, false)
	assert_bool((s2.get("color") as Color).is_equal_approx(ChestScreen.BOSS_LIGHT)).is_true()
	# an ordinary chest after it is brass again
	cs2.open({"type": "weapon", "id": boom.id, "def": boom, "level_from": 2, "level_to": 3, "is_new": false})
	assert_bool((s2.get("color") as Color).is_equal_approx(W.BRASS)).is_true()
	cs.visible = false
	cs2.visible = false


# ---------------------------------------------------------------- 4. the review's findings (pass 58, the fix round)

## What each weapon's amount counts, in its description's word (the review: "Projectiles 2 → 3" on the Hammer, the
## Gravity Gun and the Orbit Saws, which fire none).
const NOUNS := {"hammer": "hammers", "orbit_saws": "blades", "gravity_gun": "enemies thrown", "land_mine": "mines",
	"turret_buddy": "turrets", "rocket_pod": "rockets", "hornet_nest": "bees", "lob_grenade": "grenades",
	"skull_rain": "bombs", "molotov": "bottles", "sabre": "swings", "pike": "blades", "boomstick": "pellets",
	"peashooter": "shots", "revolver": "shots", "tommy_gun": "shots", "tumbleweed": "shots", "spear": "spears",
	"flare_gun": "flares", "poison_dart": "darts", "guitarra": "waves", "sun_scepter": "pillars"}
## The weapons whose area is a radius on the sand, and the radius's name on their rows.
const RADII := {"land_mine": "Blast radius", "lob_grenade": "Blast radius", "molotov": "Pool radius",
	"skull_rain": "Cloud radius", "rocket_pod": "Blast radius", "hammer": "Blast radius", "gravity_gun": "Blast radius"}


func _plain_at(w: WeaponDef, level: int) -> WeaponInstance:
	var inst := WeaponInstance.new(w, level)
	inst.rebuild(StatSheet.new(), [])
	return inst


func test_the_amount_row_names_what_the_weapon_counts() -> void:
	_start()
	for id: String in NOUNS:
		var w: WeaponDef = Registry.weapon(id)
		assert_object(w).override_failure_message(id).is_not_null()
		var one := _plain_at(w, 1)
		assert_str(TextGen.amount_noun(w, one.sheet, one.params)).override_failure_message(id).is_equal(str(NOUNS[id]))
	# every amount row of every weapon's step says what it counts, never "Projectiles"
	var seen := {}
	for w: WeaponDef in Registry.weapons.values():
		if w.is_evolution:
			continue
		for k in range(1, w.max_level):
			for r: Dictionary in TextGen.weapon_changes(w, k, k + 1):
				if str(r["stat"]) != "amount":
					continue
				var b := _plain_at(w, k + 1)
				assert_str(str(r["name"])).override_failure_message("%s %d" % [w.id, k]).is_equal(TextGen._sentence(TextGen.amount_noun(w, b.sheet, b.params)))
				assert_str(str(r["name"])).override_failure_message("%s %d" % [w.id, k]).is_not_equal("Projectiles")
				seen[w.id] = str(r["name"])
	assert_str(str(seen.get("hammer", ""))).is_equal("Hammers")
	assert_str(str(seen.get("orbit_saws", ""))).is_equal("Blades")
	assert_str(str(seen.get("gravity_gun", ""))).is_equal("Enemies thrown")
	# on the hero's own copy and on the card the same
	var hammer: WeaponDef = Registry.weapon("hammer")
	var step := -1
	for k in range(1, hammer.max_level):
		if step < 0 and hammer.effects_at_level(k + 1).any(func(e: Effect) -> bool: return e.stat == "amount"):
			step = k
	assert_int(step).is_greater(0)
	Run.debug_set_item("weapon", "hammer", step)
	Run.weapon_instance("hammer").rebuild(Run.player_sheet, Run.weapons)
	var c: WCard = auto_free(WCard.make(hammer, WItem.options({"def": hammer, "level_from": step, "level_to": step + 1})))
	var names: Array = _rows(c.changes_box).map(func(n: WCard.ChangeRow) -> String: return n.name_text.text)
	assert_bool(names.has("Hammers")).is_true()
	assert_bool(names.has("Projectiles")).is_false()


func test_an_area_that_is_a_radius_reads_in_metres() -> void:
	_start()
	for id: String in RADII:
		var w: WeaponDef = Registry.weapon(id)
		var one := _plain_at(w, 1)
		var ar := TextGen.area_radius(w, one.sheet, one.params)
		assert_int(ar.size()).override_failure_message(id).is_equal(2)
		assert_str(TextGen._sentence(str(ar[0]))).override_failure_message(id).is_equal(str(RADII[id]))
		# the number the weapon's own description gives ("a 2.4 m blast", "a 2.0 m pool of flames")
		assert_str(one.description()).override_failure_message(id).contains("%.1f m" % float(ar[1]))
		for k in range(1, w.max_level):
			for r: Dictionary in TextGen.weapon_changes(w, k, k + 1):
				if str(r["stat"]) != "area":
					continue
				var a := _plain_at(w, k)
				var b := _plain_at(w, k + 1)
				var want := TextGen._tidy_pair("%.1f m" % float(TextGen.area_radius(w, a.sheet, a.params)[1]),
					"%.1f m" % float(TextGen.area_radius(w, b.sheet, b.params)[1]))
				assert_str(str(r["name"])).override_failure_message("%s %d" % [id, k]).is_equal(str(RADII[id]))
				assert_str(str(r["before"])).override_failure_message("%s %d" % [id, k]).is_equal(str(want[0]))
				assert_str(str(r["after"])).override_failure_message("%s %d" % [id, k]).is_equal(str(want[1]))
				assert_str(str(r["after"])).override_failure_message("%s %d" % [id, k]).ends_with(" m")
	# the Land Mine's step the review read as "Area of effect 240% → 288%": its blast in metres, from 2.4 m
	var lm: WeaponDef = Registry.weapon("land_mine")
	var mine_rows: Array = []
	for k in range(1, lm.max_level):
		mine_rows.append_array(TextGen.weapon_changes(lm, k, k + 1).filter(func(r: Dictionary) -> bool: return r["stat"] == "area"))
	assert_int(mine_rows.size()).is_greater(0)
	assert_float(float(TextGen.area_radius(lm, _plain_at(lm, 1).sheet)[1])).is_equal_approx(float(lm.base.get("area", 2.4)), 0.001)
	# a weapon whose area is a share of its own size keeps the share (the Orbit Saws' blades)
	var saws: WeaponDef = Registry.weapon("orbit_saws")
	assert_array(TextGen.area_radius(saws, _plain_at(saws, 1).sheet)).is_empty()
	for k in range(1, saws.max_level):
		for r: Dictionary in TextGen.weapon_changes(saws, k, k + 1):
			if str(r["stat"]) == "area":
				assert_str(str(r["name"])).is_equal("Area of effect")
				assert_str(str(r["after"])).ends_with("%")
	# Repulsor's 40% wider blast: the Gravity Gun's description and its rows read the real radius (GravityGun._blast_r)
	var gg: WeaponDef = Registry.weapon("gravity_gun")
	Run.debug_set_item("weapon", "gravity_gun", 1)
	assert_bool(Run.add_mutation("repulsor", true)).is_true()
	var inst := Run.weapon_instance("gravity_gun")
	var grav: Dictionary = gg.params.get("gravity", {})
	var throw_mult := float((Registry.mutation("repulsor").params["gravity"] as Dictionary).get("throw_mult", 1.0))
	var want_r := float(grav.get("blast", 1.9)) * inst.sheet.get_stat("area", 1.0) * throw_mult
	assert_float(throw_mult).is_greater(1.0)
	assert_float(float(TextGen.area_radius(gg, inst.sheet, inst.params)[1])).is_equal_approx(want_r, 0.001)
	assert_str(inst.description()).contains("a %.1f m blast" % want_r)


func test_a_ceiling_keeps_its_up_to() -> void:
	_start()
	# "up to" kept on one line: its words joined by a no-break space (Desperado's had wrapped "falls, up / to")
	var up_to := ", up\u00a0to"
	for id in ["gas_mask", "desperado"]:
		var rows := TextGen.passive_changes(Registry.passive(id), 1, 2)
		assert_int(rows.size()).override_failure_message(id).is_greater(0)
		assert_str(str(rows[0]["name"])).override_failure_message(id).ends_with(up_to)
	assert_str(str(TextGen.passive_changes(Registry.passive("gas_mask"), 1, 2)[0]["name"])).is_equal("Damage reduction from poisoned enemies" + up_to)
	assert_str(str(TextGen.passive_changes(Registry.passive("desperado"), 1, 2)[0]["name"])).is_equal("Attack damage as health falls" + up_to)
	# a plain bonus says none
	for r: Dictionary in TextGen.passive_changes(Registry.passive("brawn"), 1, 2):
		assert_str(str(r["name"])).not_contains(", up")


func test_a_starless_upgrade_card_says_its_step() -> void:
	_start()
	var hammer: WeaponDef = Registry.weapon("hammer")
	Run.debug_set_item("weapon", "hammer", 2)
	var up := {"def": hammer, "level_from": 2, "level_to": 3}
	# the shop's options (StructureShop._make_card): no stars, so the word carries the step as every card did before
	var shop := {"plate_px": 160.0, "name_size": 54, "effect_size": 28, "pad": [30, 32, 30, 32], "seal_px": 92.0,
		"icon_frac": 0.72, "stars": [], "price": 40, "short": 0, "locked": false}
	assert_str(str(WItem.options(up, shop)["word"])).is_equal("WEAPON · LV 2 → 3")
	var c: WCard = auto_free(WCard.make(hammer, WItem.options(up, shop)))
	assert_object(c.marks).is_null()
	assert_str(_tag_word(c.tag_node)).is_equal("UPGRADE")
	assert_object(c.changes_box).is_not_null()
	# with its stars the word stays one word; a new item, a mutation and a line's evolution never take a step
	assert_str(str(WItem.options(up)["word"])).is_equal("WEAPON")
	assert_str(str(WItem.options({"def": hammer, "level_from": 0, "level_to": 1}, shop)["word"])).is_equal("WEAPON")
	var mut: MutationDef = Registry.mutations_of("hammer")[0]
	assert_str(str(WItem.options({"def": mut, "level_from": 0, "level_to": 1}, {"stars": []})["word"])).is_equal("MUTATION")
	var jug := {"def": Registry.passive("juggernaut"), "level_from": 4, "level_to": 5, "evolve": true}
	assert_str(str(WItem.options(jug, {"stars": []})["word"])).is_equal("EVOLVES BRAWN")
	assert_str(str(WItem.options({"def": Registry.passive("magnet"), "level_from": 1, "level_to": 2}, {"stars": []})["word"])).is_equal("PASSIVE · LV 1 → 2")
	# what a card shows under its name as one line (the arena's INFO can quote it): an upgrade's rows, else its line
	var parts: Array = []
	for r: Dictionary in WItem.changes(up):
		parts.append("%s %s → %s" % [str(r["name"]), str(r["before"]), str(r["after"])])
	assert_int(parts.size()).is_greater(0)
	assert_str(WItem.card_text(up)).is_equal(" · ".join(parts))
	var fresh := {"def": hammer, "level_from": 0, "level_to": 1}
	assert_str(WItem.card_text(fresh)).is_equal(WItem.effect(fresh))


func test_the_boss_chest_locks_banish_on_a_hero_mutation() -> void:
	# re-pinned in pass 60 (Garry: "mutations shouldn't be banishable anywhere"): Calavera's own Danza Macabra was the
	# one boss-chest roll BANISH allowed (pass 58's review fixed its re-spin); now the button is locked with the reason,
	# a press spends nothing and spins nothing, and the mutation stays on the boss chest's list
	_start("calavera")
	Run.debug_set_item("weapon", "skull_rain", 3)
	var hm: MutationDef = Registry.mutation("danza_macabra")
	assert_bool(hm.is_hero()).is_true()
	assert_str(hm.weapon).is_equal("skull_rain")
	var roll := {"type": "mutation", "id": hm.id, "def": hm, "level_from": 0, "level_to": 1, "is_new": true, "boss": true}
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	Run.banishes_left = maxi(Run.banishes_left, 1)
	var left := Run.banishes_left
	cs.open(roll)
	await _land(cs)
	assert_bool(cs._banish_btn.locked).is_true()
	assert_bool(ChestScreen.can_banish(roll)).is_false()
	assert_str(ChestScreen.banish_refusal(roll)).is_equal("A mutation cannot be banished.")
	cs._banish()
	assert_int(cs.respins).is_equal(0)
	assert_int(Run.banishes_left).is_equal(left)
	assert_bool(Run.banished.has(hm.id)).is_false()
	assert_str(str(cs.result().get("id", ""))).is_equal(hm.id)
	# and a later boss chest still holds it
	assert_bool(Run.boss_chest_mutations().has(hm)).is_true()
	cs.visible = false
