extends GdUnitTestSuite

## Pass 73, lane CARDS (Garry: "The Line Items are weird in that they look like just another set of Passive Items ... For
## our purposes I thought Fortune Teller Cards would work best ... Update the texts of 'Line' items to be 'Cards' instead
## ... Change the names / description of the items ... Update the symbol to be a Card ... 4 candidates with different
## approaches ... Each a new 'Look' so I can come back to the old one"): the 21 lines and their 21 evolutions are fortune
## cards (a tarot name each, the evolution "<card> Risen"; ids kept), every player-facing Line says Card, the kind glyph
## is a card, and every card has looks: A the icon it had, B-E the four painted card framings, the JSON's `variant` the
## one the game plays (B), a phone's kept card look (the arena) over it.

## Each line's card (Garry's prompt file names most; Slow Burn is The Ember).
const CARDS := {"brawn": "The Sun", "bristle": "The Thorn", "clover": "The Star", "deadeye": "The Eye",
	"ducktape": "The Hourglass", "energy_shield": "The Guardian", "evade": "The Ghost", "field_notes": "The Sage",
	"gold_tooth": "The King", "haste": "The Tower", "hot_sauce": "The Devil", "lodestone": "The Magnet",
	"mend": "Temperance", "mule_kick": "The Storm", "multishot": "The Hydra", "prospector": "The Miner",
	"slow_burn": "The Ember", "stride": "The Chariot", "thirst": "Death", "tin_star": "The Emperor", "vigour": "The Giant"}
const LOOKS := ["A", "B", "C", "D", "E"]
## The look the cards play until Garry picks (A, the old objects, no longer fits the tarot names).
const PLAYED := "B"


func after_test() -> void:
	Save.set_card_look("")
	Run.end()


func _lines() -> Array:
	var out: Array = []
	for p: PassiveDef in Registry.passives.values():
		if p.is_line() and not p.is_evolved():
			out.append(p)
	return out


# ---------------------------------------------------------------- the names and the words

func test_every_line_is_a_named_card_and_its_evolution_that_card_risen() -> void:
	var lines := _lines()
	assert_int(lines.size()).is_equal(CARDS.size())
	for p: PassiveDef in lines:
		assert_str(p.display_name).override_failure_message(p.id).is_equal(str(CARDS.get(p.id, "?")))
		var evo := Registry.passive(p.evolves_into)
		assert_object(evo).override_failure_message(p.id + " has no evolution").is_not_null()
		assert_str(evo.display_name).is_equal(p.display_name + " Risen")
		assert_bool(evo.is_line()).is_true()
		# the flavour reads as the card (its name in it) and carries no number
		assert_str(p.flavour).override_failure_message(p.id).contains(p.display_name)
		assert_bool(p.flavour.contains("%") or RegEx.create_from_string("[0-9]").search(p.flavour) != null).override_failure_message(p.id).is_false()
	# the ids never moved (saves, quests, analytics)
	for id in CARDS:
		assert_object(Registry.passive(str(id))).is_not_null()


func test_a_card_text_keeps_its_numbers_plain() -> void:
	# the lines with a card text of their own lead with the card and keep the rule's numbers as they were
	assert_str(Registry.passive("clover").text).contains("+10% luck a level")
	assert_str(Registry.passive("evade").text).contains("3% at level 1, 20% at level 4")
	assert_str(Registry.passive("prospector").text).contains("6% a level")
	assert_str(Registry.passive("slow_burn").text).contains("20% longer a level")
	assert_str(Registry.passive("ducktape").text).contains("15% longer a level")
	assert_str(Registry.passive("energy_shield").text).contains("3 s untouched")
	assert_str(Registry.passive("hot_sauce").text).contains("+25% difficulty a level")


func test_every_card_name_fits_its_offer_card_on_a_phone() -> void:
	# the longest names ("The Hourglass Risen") on the level-up card's plate and text column, as CardScreen makes it: the
	# card is never wider than the screen's list (1080 less its 48 px margins)
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	for p: PassiveDef in Registry.passives.values():
		if not p.is_line():
			continue
		var card := {"def": p, "level_from": 0, "level_to": 1}
		if p.is_evolved():
			card = {"def": p, "level_from": 4, "level_to": 5, "evolve": true}
		var c: WCard = auto_free(WCard.make(p, WItem.options(card)))
		add_child(c)
		assert_float(c.get_combined_minimum_size().x).override_failure_message("%s: %.0f px" % [p.display_name, c.get_combined_minimum_size().x]).is_less_equal(1080.0 - 96.0)
		c.queue_free()


func test_every_player_facing_line_says_card() -> void:
	var sun := Registry.passive("brawn")
	assert_str(WItem.word({"def": sun, "level_from": 0, "level_to": 1})).is_equal("CARD")
	assert_str(WItem.word({"def": Registry.passive("juggernaut"), "level_from": 4, "level_to": 5, "evolve": true})).is_equal("EVOLVES THE SUN")
	assert_bool(CollectionScreen.TABS.has("Cards")).is_true()
	assert_bool(CollectionScreen.TABS.has("Lines")).is_false()
	var p: ArenaPanel = auto_free(ArenaPanel.new())
	var titles: Array = p.item_sections().map(func(s) -> String: return str(s[0]))
	assert_bool(titles.has("Cards") and not titles.has("Lines")).is_true()
	# the texts that named a card by hand read its name now
	assert_str(PassiveDef.display_name_of("marshals_star")).is_equal("The Emperor Risen")
	assert_str(PassiveDef.display_name_of("gold_rush")).is_equal("The King Risen")
	assert_str(PassiveDef.display_name_of("no_such_card", "Fallback")).is_equal("Fallback")
	# the pause screen's group of them
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.add_or_level_passive("brawn")
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	ps._tab = 0
	ps._refresh()
	await get_tree().process_frame
	assert_object(ps._content.find_child("GroupCards", false, false)).is_not_null()
	assert_object(ps._content.find_child("GroupLines", false, false)).is_null()
	ps.visible = false


func test_the_kind_glyph_is_a_card_not_the_scroll() -> void:
	var img := (load("res://art/ui/wanted/kind_line.png") as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	# a tilted card: its ink taller than wide, its middle (the star) apart from its outline, its corners clear
	var n := img.get_width()
	var x0 := n
	var x1 := 0
	var y0 := n
	var y1 := 0
	for y in n:
		for x in n:
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	assert_int(y1 - y0).is_greater(x1 - x0)
	assert_float(img.get_pixel(n / 2, n / 2).a).is_greater(0.5)   # the star's heart
	# two shapes: the card's outline and the star inside it, apart (pass 56's own shape count)
	var ink: Array = []
	for y in n:
		for x in n:
			ink.append(img.get_pixel(x, y).a > 0.5)
	var shapes: Array = load("res://tests/pass56_ui_test.gd")._shapes(ink)
	assert_int(shapes.size()).is_equal(2)
	assert_int(int(shapes[1])).is_greater(60)


# ---------------------------------------------------------------- the looks

func test_every_card_has_its_old_icon_as_a_and_the_four_card_framings() -> void:
	for p: PassiveDef in Registry.passives.values():
		if not p.is_line():
			continue
		assert_str(p.variant_base).override_failure_message(p.id).is_equal("A")
		assert_array(p.variant_codes()).override_failure_message(p.id).is_equal(LOOKS)
		for code in LOOKS:
			var t := p.look_icon(code)
			assert_object(t).override_failure_message("%s %s" % [p.id, code]).is_not_null()
			assert_int(t.get_width()).is_equal(256)
		# A is the icon it had before the cards (<id>_icon.png), B-E their own files
		assert_str((p.variants["A"] as Dictionary)["icon_file"]).is_equal(p.id + "_icon.png")
		for code in ["B", "C", "D", "E"]:
			assert_str((p.variants[code] as Dictionary)["icon_file"]).is_equal("%s_icon_%s.png" % [p.id, code.to_lower()])
		# the look it plays is the JSON's, and its icon is the def's own (every screen draws def.icon)
		assert_str(p.variant).override_failure_message(p.id).is_equal(PLAYED)
		assert_object(p.icon).is_same(p.look_icon(PLAYED))
	# a passive item keeps one icon
	assert_bool(Registry.passive("magnet").variants.is_empty()).is_true()


func test_wear_look_swaps_the_icon_and_falls_back_to_the_json_look() -> void:
	var p := Registry.passive("lodestone")
	assert_str(p.wear_look("D")).is_equal("D")
	assert_object(p.icon).is_same(p.look_icon("D"))
	assert_str(p.look_code()).is_equal("D")
	# an unknown look and "" wear the JSON's own
	assert_str(p.wear_look("Z")).is_equal(p.variant)
	assert_object(p.icon).is_same(p.look_icon(p.variant))
	p.wear_look("A")
	assert_object(p.icon).is_same(p.look_icon("A"))
	p.wear_look("")
	assert_object(p.icon).is_same(p.look_icon(p.variant))
	# a shelved look is not worn
	(p.variants["C"] as Dictionary)["shelved"] = true
	assert_str(p.wear_look("C")).is_equal(p.variant)
	assert_bool(p.variant_codes().has("C")).is_false()
	(p.variants["C"] as Dictionary)["shelved"] = false


func test_a_phones_card_look_draws_every_card_in_it_and_survives_the_arena() -> void:
	assert_array(Registry.card_look_codes()).is_equal(LOOKS)
	Save.set_card_look("E")
	for p: PassiveDef in Registry.passives.values():
		if p.is_line():
			assert_object(p.icon).override_failure_message(p.id).is_same(p.look_icon("E"))
	assert_str(Save.card_look()).is_equal("E")
	# kept from inside the arena's sandbox too (a choice about the game, like a hero's look)
	Save.begin_sandbox()
	Save.set_card_look("C")
	Save.end_sandbox()
	assert_str(Save.card_look()).is_equal("C")
	assert_object(Registry.passive("brawn").icon).is_same(Registry.passive("brawn").look_icon("C"))
	# "" = each card's JSON look again
	Save.set_card_look("")
	assert_str(Save.card_look()).is_equal("")
	assert_object(Registry.passive("brawn").icon).is_same(Registry.passive("brawn").look_icon(PLAYED))


func test_the_arena_offers_the_card_looks() -> void:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var p: ArenaPanel = auto_free(ArenaPanel.new())
	add_child(p)
	p._tab = "items"
	p._refresh()
	await get_tree().process_frame
	var row: Node = p._content.find_child("CardLooks", true, false)
	assert_object(row).is_not_null()
	var labels: Array = []
	for b in row.get_children():
		if b is Button:
			labels.append((b as Button).text)
	assert_array(labels).is_equal(["JSON", "A", "B", "C", "D", "E"])
