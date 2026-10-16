## Pass 46, the passives (Garry: "change all the Line items to be just Passives", "limit the number of Passives to 6",
## "the number of passives in the slot increases with each Stage", "the HUD should display the empty slots from the
## start", Cheese to Cake, a passive that hits harder as health falls, every mutation on the weapon's page): the lines
## are passives under one cap by the stage (4 / 5 / 6, as many as it likes in the arena), an evolution takes its
## source's slot and the source never comes back, the hero's favourite passive arrives full from a card, the shop or
## the Stranger, Desperado grows by the tenth of health missing, the quests unlock passives, the HUD lays out all twelve
## slots with the shut ones padlocked, the Collection has four tabs and marks the heroes' own mutations, a stance sorts
## after the motion; and the map's pace (xp_need_mult) scales the XP a level needs.
## Pass 47 (Garry's fifth list) brought the lines back as a flag on the passives (PassiveDef.line): six line slots all run
## beside six weapon slots, no cap on the passive items, nothing padlocked; this suite follows (pass47_rules_test has the
## rest).
extends GdUnitTestSuite

## What the code may no longer say (EnergyTraces.MAX_LINES, Smasher's quake lines and Game's hell lines are other lines;
## pass 47's Run.line_cap and Registry.sorted_lines are the lines' own again, kept on the passives).
const GONE := ["LineDef", "Registry.line(", "Registry.lines", "Run.lines", "add_or_rank_line", "evolve_line",
	"line_rank", "open_lines"]
const FORMER_LINES := ["aegis", "bloodthirst", "brawn", "bristle", "cactus_hide", "energy_shield", "evade", "ghost_step",
	"ironclad", "juggernaut", "mend", "roadrunner", "second_wind", "stride", "thirst", "vigour"]


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Run.end()


func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(_scripts(dir.path_join(sub)))
	return out


# ---------------------------------------------------------------- the lines are passives

func test_no_lines_left_anywhere() -> void:
	assert_bool(JsonContent.TYPES.has("lines")).is_false()
	assert_bool(DirAccess.dir_exists_absolute("res://content/lines")).is_false()
	for id in FORMER_LINES:
		var p: PassiveDef = Registry.passive(id)
		assert_object(p).override_failure_message(id + " is not a passive").is_not_null()
		assert_str(p.kind()).is_equal("passive")
		assert_str(p.source_dir).is_equal("res://content/passives/%s/" % id)
	assert_bool(Registry.get("lines") == null).is_true()
	assert_bool(ProjectSettings.get_global_class_list().any(func(c: Dictionary) -> bool: return str(c.get("class", "")) == "LineDef")).is_false()
	for dir in ["res://core", "res://ui", "res://game", "res://player", "res://world", "res://tools", "res://addons/content_dock"]:
		for path in _scripts(dir):
			var text := FileAccess.get_file_as_string(path)
			for token in GONE:
				assert_bool(text.contains(token)).override_failure_message("%s still says %s" % [path, token]).is_false()


func test_every_passive_reads_as_a_passive() -> void:
	# one kind of content (a line is a passive with `line`, pass 47), the evolved ones known as evolved
	for p: PassiveDef in Registry.passives.values():
		assert_str(p.kind()).is_equal("passive")
		assert_bool(W.is_evolved(p)).is_equal(p.is_evolved())
	assert_str(WItem.word({"def": Registry.mutation("danza_macabra"), "level_from": 0, "level_to": 1})).is_equal("HERO MUTATION")
	# the former lines (lines again since pass 47) say "level" (pass 46), never "rank"
	for id in FORMER_LINES:
		var p: PassiveDef = Registry.passive(id)
		assert_bool(p.is_line()).override_failure_message(id + " is no line").is_true()
		assert_bool((p.trade + " " + p.text).to_lower().contains("rank")).override_failure_message(id + " still says rank").is_false()


# ---------------------------------------------------------------- the cap: six lines on every stage (pass 47)

func test_the_line_cap_is_five_on_every_stage() -> void:
	_start()
	for s in [0, 1, 2, 7]:
		Run.stage = s
		assert_int(Run.line_cap()).is_equal(5)
	Run.stage = 0
	# five lines (pass 52) and three passive items
	for id in ["magnet", "reach", "venom", "mend", "vigour", "stride", "thirst", "brawn"]:
		assert_bool(Run.add_or_level_passive(id)).override_failure_message(id + " found no slot").is_true()
	assert_bool(Run.add_or_level_passive("multishot")).override_failure_message("a sixth line on stage 1").is_false()
	# the passive items take no slot
	assert_bool(Run.add_or_level_passive("kindling")).is_true()
	# the cards keep it: with six lines a new passive card is a passive item
	for k in range(30):
		for c in CardPool.level_up_offer(4):
			if c["type"] == "passive" and not Run.passives.has(str(c["id"])):
				assert_bool((c["def"] as PassiveDef).is_line()).override_failure_message("a new line at the cap: " + str(c["id"])).is_false()
	# the debug hand: not past five lines, the passive items freely
	assert_int(Run.debug_set_item("passive", "vigour", 2)).is_equal(2)
	assert_int(Run.debug_set_item("passive", "haste", 1)).is_equal(0)
	assert_int(Run.debug_set_item("passive", "cake", 1)).is_equal(1)
	# the arena holds as many as it likes
	Run.arena = true
	assert_int(Run.line_cap()).is_equal(99)
	assert_int(Run.debug_set_item("passive", "haste", 1)).is_equal(1)
	assert_bool(Run.add_or_level_passive("multishot")).is_true()
	assert_int(Run.held_lines().size()).is_equal(7)
	assert_int(Run.passives.size()).is_equal(12)


# ---------------------------------------------------------------- evolutions

func test_an_evolution_takes_its_sources_slot_and_the_source_never_comes_back() -> void:
	_start()
	Run.add_or_level_passive("magnet")
	for k in range(4):
		Run.add_or_level_passive("vigour")
	Run.add_or_level_passive("reach")
	assert_bool(Run.evolve_passive("vigour")).is_true()
	assert_array(Run.passives.keys()).is_equal(["magnet", "ironclad", "reach"])
	assert_int(Run.passive_level("ironclad")).is_equal(1)
	assert_int(Run.passive_level("vigour")).is_equal(0)
	assert_bool(Save.seen("passive", "ironclad")).is_true()
	assert_float(Run.player_sheet.get_stat("damage_reduction", 0.0)).is_greater_equal(0.15)
	for k in range(40):
		for c in CardPool.level_up_offer(4):
			assert_str(str(c["id"])).override_failure_message("Vigour offered after it evolved").is_not_equal("vigour")
			if c["type"] == "passive" and not bool(c.get("evolve", false)):
				assert_bool((c["def"] as PassiveDef).is_evolved()).override_failure_message("an evolved passive on its own: " + str(c["id"])).is_false()
	# an evolved passive asked for while its source is held is that evolution, in the same slot
	Run.add_or_level_passive("bristle")
	assert_bool(Run.add_or_level_passive("cactus_hide")).is_true()
	assert_array(Run.passives.keys()).is_equal(["magnet", "ironclad", "reach", "cactus_hide"])
	# nothing to evolve into, nothing happens
	assert_bool(Run.evolve_passive("magnet")).is_false()
	assert_bool(Run.evolve_passive("vigour")).is_false()


# ---------------------------------------------------------------- the favourite passive

func test_a_favourite_passive_arrives_full_from_a_card_the_shop_and_the_stranger() -> void:
	var cook := CharacterDef.new()
	cook.id = "t46_cook"
	cook.display_name = "Cook"
	cook.favourite_passive = "cake"
	cook.favourite_passive_bonus = {"type": "max"}
	Run.start(cook, Registry.map("red_canyon"))
	var cake: PassiveDef = Registry.passive("cake")
	assert_int(Run.first_passive_level(cake)).is_equal(cake.max_level)
	assert_bool(Run.is_favourite(cake)).is_true()
	assert_int(Run.first_passive_level(Registry.passive("magnet"))).is_equal(1)
	assert_bool(Run.is_favourite(Registry.passive("magnet"))).is_false()
	# the card says FAVOURITE and lands it full (the shop applies the same cards)
	var card: Dictionary = {}
	for k in range(300):
		for o in CardPool.level_up_offer(4):
			if str(o["id"]) == "cake":
				card = o
		if not card.is_empty():
			break
	assert_bool(card.is_empty()).override_failure_message("no Cake card in 300 offers").is_false()
	assert_bool(bool(card.get("favourite", false))).is_true()
	assert_int(int(card["level_to"])).is_equal(cake.max_level)
	assert_str(CardPool.apply(card)).is_equal("Cake Lv %d" % cake.max_level)
	assert_int(Run.passive_level("cake")).is_equal(cake.max_level)
	# the Stranger's deal (to level 2) delivers it full as well
	Run.start(cook, Registry.map("red_canyon"))
	Run.stranger_take({"type": "passive", "id": "cake", "def": cake, "level_from": 0, "level_to": 2, "is_new": true}, 0.1)
	assert_int(Run.passive_level("cake")).is_equal(cake.max_level)
	# a level bonus lands at that level
	cook.favourite_passive_bonus = {"type": "level", "value": 3}
	Run.start(cook, Registry.map("red_canyon"))
	assert_bool(Run.add_or_level_passive("cake")).is_true()
	assert_int(Run.passive_level("cake")).is_equal(3)
	# Ironwood's: Brawn at level 2 (pass 47; Cake, full at once, in pass 46)
	var iron: CharacterDef = Registry.character("ironwood")
	assert_object(iron).is_not_null()
	assert_str(iron.favourite_passive).is_equal("brawn")
	assert_str(str(iron.favourite_passive_bonus.get("type", ""))).is_equal("level")
	assert_int(int(iron.favourite_passive_bonus.get("value", 0))).is_equal(2)


func test_the_stranger_keeps_the_line_slots_and_never_sells_an_evolved_passive() -> void:
	var done: Array = Save.data["quests_done"]
	var added := not done.has("unlock_energy_shield")
	if added:
		done.append("unlock_energy_shield")
	_start()
	for k in range(4):
		Run.add_or_level_passive("energy_shield")
	assert_bool(Run.evolve_passive("energy_shield")).is_true()
	for k in range(200):
		var o := Run.stranger_offer()
		if o.is_empty() or str(o["type"]) != "passive":
			continue
		assert_bool((o["def"] as PassiveDef).is_evolved()).is_false()
		assert_str(str(o["id"])).is_not_equal("energy_shield")
	# with the line slots full (five since pass 52) he sells levels of the lines held, never a new line (pass 47: passive
	# items take no slot)
	for id in ["brawn", "mend", "vigour", "bristle"]:
		Run.add_or_level_passive(id)
	assert_int(Run.held_lines().size()).is_equal(5)
	for k in range(200):
		var o2 := Run.stranger_offer()
		if not o2.is_empty() and str(o2["type"]) == "passive" and (o2["def"] as PassiveDef).is_line():
			assert_bool(Run.passives.has(str(o2["id"]))).override_failure_message("a new line past the slots").is_true()
	if added:
		done.erase("unlock_energy_shield")


# ---------------------------------------------------------------- Desperado

func test_desperado_grows_by_the_tenth_of_health_missing() -> void:
	_start()
	Run.note_hp(100.0, 100.0)
	var base := Run.player_sheet.get_stat("might", 1.0)
	# without it, health is nothing to might
	Run.note_hp(10.0, 100.0)
	assert_bool(Run._desperado_dirty).is_false()
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base, 0.0001)
	Run.note_hp(100.0, 100.0)
	for k in range(5):
		Run.add_or_level_passive("desperado")
	assert_float(Run.player_sheet.get_stat("desperado", 0.0)).is_equal_approx(0.6, 0.0001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base, 0.0001)
	# half the health gone: half of it, by the tenth
	Run.note_hp(45.0, 100.0)
	assert_int(Run.desperado_bucket).is_equal(5)
	assert_bool(Run._desperado_dirty).is_true()
	# the timed tick folds it in (on real time, at most four times a second: the run clock stops in a boss fight)
	Run._desperado_built_ms = -100000
	Run.tick_timed()
	assert_bool(Run._desperado_dirty).is_false()
	assert_float(Run.desperado_might()).is_equal_approx(0.3, 0.0001)
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 1.3, 0.0001)
	# nearly down: nine tenths
	Run.note_hp(5.0, 100.0)
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base * 1.54, 0.0001)
	# the pause screen's breakdown names it
	var named := false
	for r in Run.player_sheet.breakdown("might"):
		if str(r["source"]).begins_with("Desperado"):
			named = true
	assert_bool(named).is_true()
	# healed: gone
	Run.note_hp(100.0, 100.0)
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("might", 1.0)).is_equal_approx(base, 0.0001)
	var d: PassiveDef = Registry.passive("desperado")
	assert_str(d.rarity).is_equal("rare")   # pass 47b: nothing above rare yet
	assert_int(d.max_level).is_equal(5)


# ---------------------------------------------------------------- the pace of levels

func test_the_maps_pace_scales_the_xp_a_level_needs() -> void:
	_start()
	var tl: WaveTimeline = Run.map.timeline
	assert_float(tl.xp_need_mult).is_greater_equal(1.0)
	var curve := func(n: int) -> float: return 15.0 + 6.0 * n + 0.5 * n * n
	# pass 82 re-pin (lane XP): the map's own growth type (XpCurve; none = the curve above), read, never pinned
	var map_curve := func(n: int) -> float: return XpCurve.need(tl.xp_curve, n)
	for n in [1, 5, 20]:
		assert_float(Run.xp_to_next(n)).is_equal_approx(map_curve.call(n) * tl.xp_need_mult, 0.001)
	Run.level = 7
	assert_float(Run.xp_to_next()).is_equal_approx(map_curve.call(7) * tl.xp_need_mult, 0.001)
	# the reader: 1 when the map says nothing
	assert_float(JsonContent.timeline_from_dict({}).xp_need_mult).is_equal(1.0)
	assert_float(JsonContent.timeline_from_dict({"xp_need_mult": 1.433}).xp_need_mult).is_equal_approx(1.433, 0.0001)
	# the arena levels by the button: the plain curve
	Run.arena = true
	assert_float(Run.xp_to_next(5)).is_equal_approx(curve.call(5), 0.001)


# ---------------------------------------------------------------- the quests

func test_the_quests_unlock_passives() -> void:
	for qid in ["unlock_energy_shield", "unlock_evade", "unlock_stride", "unlock_thirst"]:
		var q: QuestDef = Registry.quests.get(qid)
		assert_object(q).is_not_null()
		assert_str(str(q.unlocks.get("type", ""))).is_equal("passive")
		var def := Registry.unlocked_by(q)
		assert_bool(def is PassiveDef).override_failure_message(qid + " unlocks no passive").is_true()
		assert_object(Registry.quest_for("passive", def.id)).is_equal(q)
		assert_bool(Registry.quest_visible(q)).is_true()
	for q: QuestDef in Registry.quests.values():
		assert_str(str(q.unlocks.get("type", ""))).is_not_equal("line")


# ---------------------------------------------------------------- the HUD's twelve slots

func test_the_hud_shows_twelve_slots_from_the_start() -> void:
	_start()
	var tl: WaveTimeline = Run.map.timeline
	var specs := HUD.slot_specs([[Registry.weapon("peashooter"), 2, 0], [Registry.weapon("boomstick"), 1, 1]], Run.weapon_cap(),
		tl.weapon_cap, [[Registry.passive("brawn"), 1]], Run.line_cap(), tl.passive_cap)
	assert_int(specs.size()).is_equal(10)
	# pass 47: six weapon slots and six line slots open from the start, nothing shut on any stage; five and five since pass 52
	assert_array(specs.map(func(s: Array) -> int: return int(s[4]))).is_equal([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_object(specs[5][0]).is_equal(Registry.passive("brawn"))
	assert_object(specs[6][0]).is_null()
	assert_int(int(specs[1][3])).is_equal(1)
	# the real strip, on stage 1: a passive item takes no slot
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("magnet")
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	var plates: Array = hud._slots.get_children()
	assert_int(plates.size()).is_equal(10)
	assert_int(plates.filter(func(p: WPlate) -> bool: return p.padlock).size()).is_equal(0)
	assert_int(plates.filter(func(p: WPlate) -> bool: return p.empty).size()).is_equal(7)
	assert_int(hud._slot_nodes.size()).is_equal(3)
	# one row
	for p: WPlate in plates:
		assert_float(p.position.y).is_less(12.0)
	# a new stage opens nothing more: there was nothing shut
	Run.stage = 1
	hud.refresh_stage()
	plates = hud._slots.get_children().filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())
	assert_int(plates.size()).is_equal(10)
	assert_int(plates.filter(func(p: WPlate) -> bool: return p.padlock).size()).is_equal(0)


# ---------------------------------------------------------------- the Collection

func test_the_collection_has_its_tabs_and_marks_the_heroes_mutations() -> void:
	# pass 47: the lines and the passive items each have a tab again
	assert_bool(CollectionScreen.TABS.has("Weapons")).is_true()
	# pass 73 (lane CARDS): the line items are fortune cards, their tab says Cards
	assert_bool(CollectionScreen.TABS.has("Cards")).is_true()
	assert_bool(CollectionScreen.TABS.has("Passives")).is_true()
	assert_bool(CollectionScreen.TABS.has("Perks")).is_true()
	# pass 83 (lane META, re-pinned): a hero's own shows on the page only while the save owns him
	# (CollectionScreen.hero_item_hidden): every hero on sale owned for these checks, the list put back after
	var owned_keep: Array = Save.heroes_owned().duplicate()
	for hc: CharacterDef in Registry.characters.values():
		if hc.availability == "purchase" and not Save.owns_hero(hc.id):
			Save.heroes_owned().append(hc.id)
	var rain: Array = CollectionScreen.page_mutations(Registry.weapon("skull_rain")).map(func(m: MutationDef) -> String: return m.id)
	assert_int(rain.size()).is_equal(4)
	assert_str(str(rain[3])).is_equal("danza_macabra")
	assert_str(CollectionScreen.hero_only_text(Registry.mutation("danza_macabra"))).is_equal("CALAVERA ONLY")
	assert_str(CollectionScreen.hero_only_text(Registry.mutation(str(rain[0])))).is_equal("")
	# pass 76 (lane DYN): the Drifter's own is Fire in the Hole on the dynamite (the Lob Grenade); the Peashooter and his
	# Fan the Hammer are hidden
	var lob: Array = CollectionScreen.page_mutations(Registry.weapon("lob_grenade")).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(lob.has("fire_in_the_hole")).is_true()
	assert_str(CollectionScreen.hero_only_text(Registry.mutation("fire_in_the_hole"))).is_equal("DRIFTER ONLY")
	var pea: Array = CollectionScreen.page_mutations(Registry.weapon("peashooter")).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(pea.has("fan_the_hammer")).is_false()
	# pass 67: Buck is back in play, so his own is on his weapon's page, marked as his; pass 69: he is Jeżyk, his own is
	# Salt Flats on the Salt's page and the Tommy Gun's Drum Roll is hidden (off the page)
	var tommy: Array = CollectionScreen.page_mutations(Registry.weapon("tommy_gun")).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(tommy.has("drum_roll")).is_false()
	var salt: Array = CollectionScreen.page_mutations(Registry.weapon("salt")).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(salt.has("salt_flats")).is_true()
	assert_str(CollectionScreen.hero_only_text(Registry.mutation("salt_flats"))).is_equal("JEŻYK ONLY")
	# pass 69 (lane UI): Mira is back (a hero to buy), so her Blasting Cap is on the Land Mine's page, marked as hers (a
	# hidden hero's own staying off: pass66_shape_test's rule, Dad has none)
	# (Garry hid her again on 2026-10-13: the page shows her own exactly while she is in play)
	var mine: Array = CollectionScreen.page_mutations(Registry.weapon("land_mine")).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(mine.has("blasting_cap")).is_equal(not Registry.character("mira").hidden)
	assert_str(CollectionScreen.hero_only_text(Registry.mutation("blasting_cap"))).is_equal("MIRA ONLY")
	# the cells: three to a row, a short last row centred under them
	var cs: CollectionScreen = auto_free(load("res://ui/CollectionScreen.tscn").instantiate())
	add_child(cs)
	var col: VBoxContainer = cs._paths(CollectionScreen.page_mutations(Registry.weapon("skull_rain")))
	assert_int(col.get_child_count()).is_equal(2)
	assert_int(col.get_child(0).get_child_count()).is_equal(3)
	assert_int(col.get_child(1).get_child_count()).is_equal(1)
	assert_int((col.get_child(1) as HBoxContainer).alignment).is_equal(BoxContainer.ALIGNMENT_CENTER)
	var w0: float = (col.get_child(0).get_child(0) as Control).custom_minimum_size.x
	assert_float((col.get_child(1).get_child(0) as Control).custom_minimum_size.x).is_equal(w0)
	col.free()
	Save.data["heroes_owned"] = owned_keep


func test_a_stance_sorts_after_the_motion() -> void:
	assert_int(int(Registry.MUTATION_ORDER["stance"])).is_greater(int(Registry.MUTATION_ORDER["motion"]))
	assert_int(int(Registry.MUTATION_ORDER["hero"])).is_greater(int(Registry.MUTATION_ORDER["stance"]))
	# every path in that order (pass 47: the turret's Watchtower is gone and its Bunker is the motion pick, so no path
	# carries a stance today)
	for w: WeaponDef in Registry.base_weapons():
		var order: Array = Registry.mutations_of(w.id).map(func(m: MutationDef) -> int: return int(Registry.MUTATION_ORDER.get(m.mutation_kind, 9)))
		var sorted := order.duplicate()
		sorted.sort()
		assert_array(order).override_failure_message(w.id + " path order").is_equal(sorted)
	var kinds: Array = Registry.mutations_of("turret_buddy").map(func(m: MutationDef) -> String: return m.mutation_kind)
	assert_array(kinds).is_equal(["element", "volume", "motion"])
