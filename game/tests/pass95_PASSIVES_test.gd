## Pass 95, lane PASSIVES (Garry: "the number of Upgrades is reduced to the number of upgrades they have left to reach
## Legendary + Evolved Rarity ... Evolved is a 'Rarity' for Passive Items"): a passive item climbs the rarity ladder one
## rung an upgrade (PassiveDef.ladder_levels: common 6 levels, uncommon 5, rare 4, epic 3, legendary 2; the top is
## Evolved), its plate takes the rung's colour and the evolved look at the top (W.plate_fill, WPlate), its cards name the
## rung (WItem.word, the EVOLVED tag), its texts name the rung (TextGen.rung_name), the Evolved icon
## (<id>_icon_evolved.png, tools/evolved_icons.py) shows on the Evolved rung, every item's JSON holds every rung
## (tools/passive_ladder.py), a run buys every rung and no further, old levels past the top load without error, the lines
## (cards) are untouched, and Phoenix Feather climbs to a second life.
extends GdUnitTestSuite

const ITEMS := 34
const LADDER := {"common": 6, "uncommon": 5, "rare": 4, "epic": 3, "legendary": 2}


func before_test() -> void:
	Save.data = Save._default()


func after_test() -> void:
	Run.arena = false
	Run.banished.clear()
	Run.end()


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _items() -> Array:
	return Registry.sorted_passives_only()


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			var t := n as WText
			s += t.text + " "
			for r in t.runs:
				s += str(r[0]) + " "
	return s


# ---------------------------------------------------------------- the rule

func test_the_ladder_rule_per_rarity() -> void:
	for r: String in LADDER.keys():
		assert_int(PassiveDef.ladder_levels(r)).override_failure_message(r).is_equal(int(LADDER[r]))
	# an unknown rarity reads as common, as W.rarity_of reads it
	assert_int(PassiveDef.ladder_levels("mythic")).is_equal(6)
	assert_int(PassiveDef.ladder_levels("")).is_equal(6)
	var d := PassiveDef.new()
	d.rarity = "rare"
	assert_bool(d.is_item()).is_true()
	assert_int(d.ladder_top()).is_equal(4)
	assert_str(d.rung_at(0)).is_equal("rare")
	assert_str(d.rung_at(1)).is_equal("rare")
	assert_str(d.rung_at(2)).is_equal("epic")
	assert_str(d.rung_at(3)).is_equal("legendary")
	assert_str(d.rung_at(4)).is_equal(PassiveDef.EVOLVED_RUNG)
	assert_str(d.rung_at(9)).is_equal(PassiveDef.EVOLVED_RUNG)
	assert_bool(d.is_evolved_rung(3)).is_false()
	assert_bool(d.is_evolved_rung(4)).is_true()
	assert_bool(d.is_evolved_rung(7)).is_true()
	d.apply_ladder()
	assert_int(d.max_level).is_equal(4)
	# a common item has the whole ladder, a legendary one Evolved alone
	var c := PassiveDef.new()
	c.rarity = "common"
	assert_array([c.rung_at(1), c.rung_at(2), c.rung_at(3), c.rung_at(4), c.rung_at(5), c.rung_at(6)]).is_equal(
		["common", "uncommon", "rare", "epic", "legendary", "evolved"])
	var l := PassiveDef.new()
	l.rarity = "legendary"
	assert_int(l.ladder_top()).is_equal(2)
	assert_str(l.rung_at(2)).is_equal("evolved")
	# a line (a card) and an evolved form are not on the ladder: their levels are their own
	var line := PassiveDef.new()
	line.rarity = "common"
	line.line = true
	line.max_level = 4
	assert_bool(line.is_item()).is_false()
	assert_int(line.ladder_top()).is_equal(4)
	assert_str(line.rung_at(3)).is_equal("common")
	assert_bool(line.is_evolved_rung(4)).is_false()
	line.apply_ladder()
	assert_int(line.max_level).is_equal(4)
	var evo := PassiveDef.new()
	evo.evolves_from = "line"
	evo.max_level = 1
	assert_bool(evo.is_item()).is_false()
	assert_bool(evo.is_evolved_rung(1)).is_false()
	evo.apply_ladder()
	assert_int(evo.max_level).is_equal(1)
	# the rung names
	assert_str(TextGen.rung_name(d, 1)).is_equal("Rare")
	assert_str(TextGen.rung_name(d, 3)).is_equal("Legendary")
	assert_str(TextGen.rung_name(d, 4)).is_equal("Evolved")
	assert_str(TextGen.rung_name(line, 2)).is_equal("Common")


func test_every_item_climbs_its_ladder_and_the_lines_keep_theirs() -> void:
	assert_array(Registry.problems).is_empty()
	var items := _items()
	assert_int(items.size()).is_equal(ITEMS)
	for p: PassiveDef in items:
		var want := int(LADDER[p.rarity])
		assert_bool(p.is_item()).override_failure_message(p.id).is_true()
		assert_int(p.max_level).override_failure_message(p.id + " max_level").is_equal(want)
		assert_int(p.ladder_top()).is_equal(want)
		# every rung explicit in the JSON (the tool wrote them), none empty, and the JSON's max_level says the same
		assert_int(p.levels.size()).override_failure_message(p.id + " levels").is_equal(want)
		for k in range(want):
			assert_bool((p.levels[k] as Array).is_empty()).override_failure_message("%s rung %d is empty" % [p.id, k + 1]).is_false()
		var d := JsonContent.load_json("res://content/passives/%s/%s.json" % [p.id, p.id])
		assert_int(int(d.get("max_level", 0))).override_failure_message(p.id + " JSON max_level").is_equal(want)
		assert_int((d.get("levels", []) as Array).size()).override_failure_message(p.id + " JSON levels").is_equal(want)
		# the Evolved icon, on disk and on the def, its own picture
		assert_bool(FileAccess.file_exists("res://content/passives/%s/%s_icon_evolved.png" % [p.id, p.id])).override_failure_message(p.id + " has no Evolved icon").is_true()
		assert_object(p.evolved_icon).override_failure_message(p.id + " evolved_icon").is_not_null()
		assert_bool(p.evolved_icon == p.icon).is_false()
		assert_object(p.icon_at(want)).is_same(p.evolved_icon)
		assert_object(p.icon_at(want - 1)).is_same(p.icon)
		assert_object(p.icon_at(0)).is_same(p.icon)
	# the lines: four levels and one for their Risen cards, never an Evolved icon
	for p: PassiveDef in Registry.passives.values():
		if p.is_line():
			assert_bool(p.is_item()).is_false()
			assert_int(p.max_level).override_failure_message(p.id).is_equal(1 if p.is_evolved() else 4)
			assert_object(p.evolved_icon).is_null()
	# the rarities among the items are still the four (pass 47 pins it): legendary stays unused
	var seen := {}
	for p: PassiveDef in items:
		seen[p.rarity] = true
	assert_array(seen.keys()).contains_exactly_in_any_order(["common", "uncommon", "rare", "epic"])
	# the first level is higher than the old one (Garry: "stats on the 1st level will be higher"): spot checks against
	# the committed numbers
	assert_float(float((Registry.passive("skedaddle").effects_at_level(1)[0] as Effect).value)).is_equal_approx(0.25, 0.0001)
	assert_float(float((Registry.passive("desperado").effects_at_level(1)[0] as Effect).value)).is_equal_approx(0.16, 0.0001)
	assert_float(float((Registry.passive("gas_mask").effects_at_level(1)[0] as Effect).value)).is_equal_approx(0.12, 0.0001)
	assert_float(float((Registry.passive("magnet").effects_at_level(1)[0] as Effect).value)).is_equal_approx(6.0, 0.0001)
	assert_float(float((Registry.passive("cake").effects_at_level(1)[0] as Effect).value)).is_equal_approx(0.004, 0.00001)


# ---------------------------------------------------------------- the plates

func test_the_plates_climb_the_ladder_and_go_dark_at_the_top() -> void:
	for p: PassiveDef in _items():
		var top := p.max_level
		var i0 := W.RARITIES.find(p.rarity)
		assert_bool(W.plate_fill(p, 0).is_equal_approx(W.RARITY_PLATE[p.rarity])).override_failure_message(p.id + " level 0").is_true()
		for k in range(1, top):
			var want: Color = W.RARITY_PLATE[W.RARITIES[i0 + k - 1]]
			assert_bool(W.plate_fill(p, k).is_equal_approx(want)).override_failure_message("%s level %d" % [p.id, k]).is_true()
			assert_bool(W.is_evolved_rung(p, k)).is_false()
		assert_bool(W.plate_fill(p, top).is_equal_approx(W.EVOLVED_FILL)).override_failure_message(p.id + " top").is_true()
		assert_bool(W.plate_fill(p, top + 3).is_equal_approx(W.EVOLVED_FILL)).is_true()
		assert_bool(W.is_evolved_rung(p, top)).is_true()
		assert_str(W.rung_of(p, 0)).is_equal(p.rarity)
		assert_str(W.rung_of(p, top)).is_equal("evolved")
	# the plate: the rung's colour, no ring and the base icon below the top; the dark plate, the brass ring and the
	# Evolved icon on the top
	var cake: PassiveDef = Registry.passive("cake")
	var p5: WPlate = auto_free(WPlate.new().for_def(cake, 72.0, false, 5))
	assert_bool(p5.fill.is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
	assert_int(p5.ring).is_equal(0)
	assert_object(p5.tex).is_same(cake.icon)
	var p6: WPlate = auto_free(WPlate.new().for_def(cake, 72.0, false, 6))
	assert_bool(p6.fill.is_equal_approx(W.EVOLVED_FILL)).is_true()
	assert_int(p6.ring).is_greater(0)
	assert_bool(p6.ring_color.is_equal_approx(W.EVOLVED_RING)).is_true()
	assert_object(p6.tex).is_same(cake.evolved_icon)
	var p0: WPlate = auto_free(WPlate.new().for_def(cake, 72.0))
	assert_bool(p0.fill.is_equal_approx(W.RARITY_PLATE["common"])).is_true()
	assert_object(p0.tex).is_same(cake.icon)
	# an epic item: epic, legendary, Evolved
	var mg: PassiveDef = Registry.passive("magnet")
	assert_bool(W.plate_fill(mg, 1).is_equal_approx(W.RARITY_PLATE["epic"])).is_true()
	assert_bool(W.plate_fill(mg, 2).is_equal_approx(W.RARITY_PLATE["legendary"])).is_true()
	assert_bool(W.plate_fill(mg, 3).is_equal_approx(W.EVOLVED_FILL)).is_true()
	# a line keeps its level colours (common .. epic) and is never dark; its Risen card is dark as before
	var brawn: PassiveDef = Registry.passive("brawn")
	for lv in range(1, 5):
		assert_bool(W.plate_fill(brawn, lv).is_equal_approx(W.RARITY_PLATE[W.RARITIES[lv - 1]])).is_true()
	assert_bool(W.is_evolved_rung(brawn, 4)).is_false()
	assert_bool(W.plate_fill(Registry.passive("juggernaut"), 1).is_equal_approx(W.EVOLVED_FILL)).is_true()
	# a weapon is untouched
	assert_bool(W.plate_fill(Registry.weapon("peashooter"), 3).is_equal_approx(W.RARITY_PLATE["rare"])).is_true()
	assert_bool(W.is_evolved_rung(Registry.weapon("peashooter"), 5)).is_false()
	# the Collection's level cells: a wash of the rung's colour, the Evolved one of the ember
	assert_bool(CollectionScreen.rung_wash(cake, 1).is_equal_approx(W.RARITY_PLATE["common"].lerp(W.PAPER, 0.55))).is_true()
	assert_bool(CollectionScreen.rung_wash(cake, 6).is_equal_approx(W.EMBER.lerp(W.PAPER, 0.55))).is_true()


# ---------------------------------------------------------------- the cards and the words

func test_the_cards_name_the_rung_and_the_top_says_evolved() -> void:
	var cake: PassiveDef = Registry.passive("cake")
	# a new item's card: the kind alone, its plate says its rarity (pass 47)
	assert_str(WItem.word({"def": cake, "level_from": 0, "level_to": 1})).is_equal("PASSIVE")
	assert_str(WItem.tag({"def": cake, "level_from": 0, "level_to": 1})).is_equal("NEW")
	# an upgrade names the rung it lands on
	assert_str(WItem.word({"def": cake, "level_from": 1, "level_to": 2})).is_equal("PASSIVE · UNCOMMON")
	assert_str(WItem.tag({"def": cake, "level_from": 1, "level_to": 2})).is_equal("UPGRADE")
	assert_str(WItem.word({"def": cake, "level_from": 2, "level_to": 3})).is_equal("PASSIVE · RARE")
	assert_str(WItem.word({"def": cake, "level_from": 3, "level_to": 4})).is_equal("PASSIVE · EPIC")
	assert_str(WItem.word({"def": cake, "level_from": 4, "level_to": 5})).is_equal("PASSIVE · LEGENDARY")
	# the top: the EVOLVED tag in the evolution's ember, the evolution's band, the kind alone
	var top := {"def": cake, "level_from": 5, "level_to": 6}
	assert_str(WItem.word(top)).is_equal("PASSIVE")
	assert_str(WItem.tag(top)).is_equal("EVOLVED")
	assert_bool(WItem.tag_color("EVOLVED").is_equal_approx(W.EMBER)).is_true()
	var o := WItem.options(top)
	assert_bool(bool(o["evolution"])).is_true()
	assert_int(int(o["level"])).is_equal(6)
	assert_array(WItem.stars(top)).is_equal([6, 5, 6])
	assert_bool(bool(WItem.options({"def": cake, "level_from": 4, "level_to": 5})["evolution"])).is_false()
	# the Stranger's two levels at once land on the rung of the level reached
	assert_str(WItem.word({"def": cake, "level_from": 1, "level_to": 3})).is_equal("PASSIVE · RARE")
	# the card itself: the dark plate in the brass ring with the Evolved icon, EVOLVED among its words
	var c: WCard = auto_free(WCard.make(cake, o))
	assert_bool(c.plate.fill.is_equal_approx(W.EVOLVED_FILL)).is_true()
	assert_int(c.plate.ring).is_greater(0)
	assert_object(c.plate.tex).is_same(cake.evolved_icon)
	assert_bool(_texts(c).contains("EVOLVED")).is_true()
	var c3: WCard = auto_free(WCard.make(cake, WItem.options({"def": cake, "level_from": 2, "level_to": 3})))
	assert_bool(c3.plate.fill.is_equal_approx(W.RARITY_PLATE["rare"])).is_true()
	assert_int(c3.plate.ring).is_equal(0)
	assert_bool(_texts(c3).contains("RARE")).is_true()
	# a line's card keeps its words (CARD, no rung), and its Risen card its EVOLUTION tag
	var brawn: PassiveDef = Registry.passive("brawn")
	assert_str(WItem.word({"def": brawn, "level_from": 2, "level_to": 3})).is_equal("CARD")
	assert_str(WItem.tag({"def": brawn, "level_from": 3, "level_to": 4})).is_equal("UPGRADE")
	assert_str(WItem.tag({"def": Registry.passive("juggernaut"), "level_from": 4, "level_to": 5, "evolve": true})).is_equal("EVOLUTION")
	# a weapon's card is untouched
	assert_str(WItem.word({"def": Registry.weapon("boomstick"), "level_from": 4, "level_to": 5})).is_equal("WEAPON")
	# the texts: the next level names its rung, the pause line names the level's rung, the first level reads plainly
	assert_str(TextGen.next_level_text(cake, 1)).starts_with("Next level (Uncommon): ")
	assert_str(TextGen.next_level_text(cake, 5)).starts_with("Next level (Evolved): ")
	assert_str(TextGen.next_level_text(cake, 6)).is_equal("Maxed.")
	assert_str(TextGen.next_level_text(brawn, 1)).starts_with("Next level: ")
	assert_str(TextGen.passive_description(cake, 1)).is_equal("+0.4% cake drop chance.")
	assert_str(TextGen.passive_description(cake, 3)).is_equal("Level 3 (Rare): +0.9% cake drop chance total.")
	assert_str(TextGen.passive_description(cake, 6)).is_equal("Level 6 (Evolved): +1.75% cake drop chance total.")
	assert_str(TextGen.passive_description(Registry.passive("magnet"), 3)).is_equal("Level 3 (Evolved): +8.5 m EXP pull radius total.")
	assert_str(WItem.effect({"def": cake, "level_from": 5, "level_to": 6})).is_equal("Next: +0.35% cake drop chance.")
	# the Collection's kind line climbs to Evolved
	var cs: CollectionScreen = auto_free(CollectionScreen.new())
	assert_str(cs._kind_line(cake)).is_equal("Passive · Common → Evolved · 6 levels")
	assert_str(cs._kind_line(Registry.passive("magnet"))).is_equal("Passive · Epic → Evolved · 3 levels")
	assert_str(cs._kind_line(brawn)).is_equal("Card · 4 levels")


func test_every_text_reads_well_at_every_rung() -> void:
	for p: PassiveDef in _items():
		var lines: Array = [p.text]
		for lv in range(1, p.max_level + 1):
			lines.append(TextGen.passive_description(p, lv))
			lines.append(TextGen.next_level_text(p, lv))
			lines.append(WItem.effect({"def": p, "level_from": lv - 1, "level_to": lv}))
			lines.append(WItem.word({"def": p, "level_from": lv - 1, "level_to": lv}))
		for s: String in lines:
			assert_bool(s.contains("_")).override_failure_message(p.id + " shows a raw stat: " + s).is_false()
			assert_bool(s.to_lower().contains("rank")).override_failure_message(p.id + " says rank: " + s).is_false()
			if s != "":
				var c0 := s.substr(0, 1)
				assert_bool(c0 == c0.to_upper()).override_failure_message(p.id + " starts small: " + s).is_true()
		# a card line stays short (pass 69's rule, loosened a little for the rungs' words)
		assert_int(p.text.length()).override_failure_message(p.id + " card line is long: " + p.text).is_less_equal(175)
		# the top says Evolved somewhere a player reads it
		assert_bool(TextGen.passive_description(p, p.max_level).contains("Evolved")).override_failure_message(p.id).is_true()
		assert_bool(TextGen.next_level_text(p, p.max_level - 1).contains("Evolved")).override_failure_message(p.id).is_true()
		# every rung changes something (no empty upgrade)
		for lv in range(2, p.max_level + 1):
			assert_bool(TextGen.describe_effects(p.effects_at_level(lv)) != "").override_failure_message("%s rung %d says nothing" % [p.id, lv]).is_true()
	# a hand-written line that named the old numbers names the new (the tool rewrote it)
	assert_str(Registry.passive("skedaddle").text).is_equal("After a hit, run 25% faster for 2 s (+3% and +0.3 s a rung, Evolved +5% and +0.5 s).")
	assert_str(Registry.passive("magnet").text).contains("within 6 m")
	assert_str(Registry.passive("desperado").text).contains("up to +51% once Evolved")


# ---------------------------------------------------------------- the run

func test_a_run_buys_every_rung_and_no_further() -> void:
	for p: PassiveDef in _items():
		_start()
		for k in range(p.max_level):
			assert_bool(Run.add_or_level_passive(p.id)).override_failure_message("%s rung %d" % [p.id, k + 1]).is_true()
			assert_int(Run.passive_level(p.id)).is_equal(k + 1)
		assert_bool(Run.add_or_level_passive(p.id)).override_failure_message(p.id + " past Evolved").is_false()
		assert_int(Run.passive_level(p.id)).is_equal(p.max_level)
		# no chest offers it past the top; the Build tab lists it
		for c: Dictionary in Run.chest_candidates():
			assert_str(str(c["id"])).override_failure_message(p.id + " offered past its top").is_not_equal(p.id)
		assert_bool(Run.held_passives().has(p.id)).is_true()
		# the sheet holds the top's sum (the first stat of the first rung, summed over the rungs that carry it)
		var e0: Effect = p.effects_at_level(1)[0]
		var want := 0.0
		var total: Array = TextGen._sum_effects(p.effects_for_level(p.max_level))
		for e: Effect in total:
			if e.stat == e0.stat and e.op == e0.op and e.target == e0.target:
				want = e.value
		if e0.op == "add" and e0.target == "player":
			var base := float(StatSheet.PLAYER_DEFAULTS.get(e0.stat, 0.0))
			if e0.stat == "regen" or e0.stat == "max_hp":
				base = Run.hero_sheet(Run.character, Run.level).get_stat(e0.stat, 0.0)
			assert_float(Run.player_sheet.get_stat(e0.stat, 0.0) - base).override_failure_message("%s %s at the top" % [p.id, e0.stat]).is_equal_approx(want, 0.001)
		Run.end()
	# a held item is offered one rung at a time (a chest's upgrade lands on the next level)
	_start()
	Run.add_or_level_passive("cake")
	var found := false
	for c: Dictionary in Run.chest_candidates():
		if str(c["id"]) == "cake":
			found = true
			assert_int(int(c["level_from"])).is_equal(1)
			assert_int(int(c["level_to"])).is_equal(2)
	assert_bool(found).is_true()
	# the arena's hand clamps to the top
	assert_int(Run.debug_set_item("passive", "cake", 99)).is_equal(6)
	assert_int(Run.debug_set_item("passive", "magnet", 99)).is_equal(3)


func test_a_level_past_the_top_loads_without_error() -> void:
	# an old run (a save file, a tool) may hold a passive at a level the ladder no longer has: it reads as the top,
	# the plate dark, the words "Maxed.", nothing to buy
	_start()
	var cake: PassiveDef = Registry.passive("cake")
	Run.passives["cake"] = 9
	Run._apply_passives_to_sheet()
	assert_int(cake.effects_for_level(9).size()).is_equal(9)
	assert_bool(W.plate_fill(cake, 9).is_equal_approx(W.EVOLVED_FILL)).is_true()
	assert_object(cake.icon_at(9)).is_same(cake.evolved_icon)
	assert_str(TextGen.rung_name(cake, 9)).is_equal("Evolved")
	assert_str(TextGen.next_level_text(cake, 9)).is_equal("Maxed.")
	assert_bool(TextGen.passive_description(cake, 9).begins_with("Level 9 (Evolved): ")).is_true()
	assert_bool(Run.add_or_level_passive("cake")).is_false()
	var o := WItem.options({"def": cake, "level_from": 9, "level_to": 10})
	assert_str(str(o["tag"])).is_equal("EVOLVED")
	var p: WPlate = auto_free(WPlate.new().for_def(cake, 72.0, false, 9))
	assert_int(p.ring).is_greater(0)
	for c: Dictionary in Run.chest_candidates():
		assert_str(str(c["id"])).is_not_equal("cake")


func test_phoenix_feather_climbs_to_a_second_life() -> void:
	_start()
	var ph: PassiveDef = Registry.passive("phoenix_feather")
	assert_int(ph.max_level).is_equal(5)
	assert_bool(Run.phoenix_ready()).is_false()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	assert_int(Run.phoenix_count()).is_equal(1)
	assert_bool(Run.phoenix_ready()).is_true()
	# one life spent: used up at level 1, as before
	Run.use_phoenix()
	assert_int(Run.phoenix_spent).is_equal(1)
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.phoenix_ready()).is_false()
	assert_bool(Run.item_spent(ph)).is_true()
	# it is offered again while held: the rungs raise the health he rises with
	var share := Run.player_sheet.get_stat("revive_hp", 0.5)
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(share + 0.15, 0.0001)
	assert_bool(Run.phoenix_ready()).is_false()
	Run.add_or_level_passive("phoenix_feather")
	Run.add_or_level_passive("phoenix_feather")
	assert_float(Run.player_sheet.get_stat("revive_hp", 0.5)).is_equal_approx(share + 0.5, 0.0001)
	assert_int(Run.phoenix_count()).is_equal(1)
	# Evolved: a second life, ready again though the first was spent
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_true()
	assert_int(Run.passive_level("phoenix_feather")).is_equal(5)
	assert_int(Run.phoenix_count()).is_equal(2)
	assert_bool(Run.phoenix_used).is_false()
	assert_bool(Run.phoenix_ready()).is_true()
	assert_bool(Run.item_spent(ph)).is_false()
	Run.use_phoenix()
	assert_int(Run.phoenix_spent).is_equal(2)
	assert_bool(Run.phoenix_used).is_true()
	assert_bool(Run.phoenix_ready()).is_false()
	assert_bool(Run.item_spent(ph)).is_true()
	assert_bool(Run.add_or_level_passive("phoenix_feather")).is_false()
	# a rebuild keeps it spent; a new run has it fresh
	Run.rebuild_sheets()
	assert_bool(Run.phoenix_ready()).is_false()
	_start()
	assert_int(Run.phoenix_spent).is_equal(0)
	assert_bool(Run.phoenix_used).is_false()
	# taken Evolved at once (a favourite's "max"): two lives from the start
	Run.debug_set_item("passive", "phoenix_feather", 5)
	assert_int(Run.phoenix_count()).is_equal(2)
	assert_bool(Run.phoenix_ready()).is_true()
	Run.use_phoenix()
	assert_bool(Run.phoenix_ready()).is_true()
	Run.use_phoenix()
	assert_bool(Run.phoenix_ready()).is_false()


func test_the_tool_s_table_matches_the_content() -> void:
	# tools/passive_ladder.py --check reads the JSON back against its table: the committed numbers are the tool's
	var out: Array = []
	var code := OS.execute("python", [ProjectSettings.globalize_path("res://").path_join("..").path_join("tools/passive_ladder.py"), "--check"], out, true)
	assert_int(code).override_failure_message("\n".join(out)).is_equal(0)
