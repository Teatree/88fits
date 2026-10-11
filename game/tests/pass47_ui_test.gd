## Pass 47, the UI lane (Garry's fifth list): weapons on light blue plates, lines on light yellow, passive items on their
## rarity's World of Warcraft colour (no seal, no rarity word), evolved ones dark in a brass ring; the kind's one word
## (WEAPON, LINE, PASSIVE); the HUD's six weapon and six line slots with no passive items and no padlocks, the boss's name
## over the world without its ink box, the gold rising from the hero; the Collection's five tabs and the dangerous
## enemies' badges; two skips and one banish a stage on the level-up, the mutation offer and the chest (SKIP ×N, BANISH
## ×N, TAKE IT; a banish spins the reel again); the chest opening on the lower third; every damage source on the
## Results with its plate, name and number; no slot lines on the stage clear; the pause screen's Build tab listing the
## lines and every passive item.
extends GdUnitTestSuite


func _start(hero: String = "astro") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Run.end()


func _texts(root: Node) -> String:
	var s := ""
	for n in root.find_children("*", "", true, false):
		if n is WText:
			var t := n as WText
			s += t.text + " "
			for r in t.runs:
				s += str(r[0]) + " "
	return s


func _coins(root: Node) -> Array:
	return root.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is WCoin)


func _plate(def: ContentDef) -> WPlate:
	return auto_free(WPlate.new().for_def(def, 96.0))


## The chest's intro skipped and its reel hurried until it lands.
func _land(cs) -> void:
	cs.skip_intro()
	cs._tw.set_speed_scale(40.0)
	for k in 60:
		await get_tree().process_frame
		if not cs._spinning:
			break


## A button's words once the labels it replaced have gone (set_parts frees the old ones at the frame's end).
func _label(b: WButton) -> String:
	await get_tree().process_frame
	return b.label_text()


# ---------------------------------------------------------------- plates and words

func test_the_plate_colours_by_kind_and_rarity() -> void:
	# WoW's hues, softened (pass 47b, Garry: too saturated); common a light grey since pass 53 (Garry: "Change the White of
	# Common item bg to a light gray")
	assert_str(W.RARITY_PLATE["common"].to_html(false)).is_equal("d2cfc7")
	assert_str(W.RARITY_PLATE["uncommon"].to_html(false)).is_equal("8cc97a")
	assert_str(W.RARITY_PLATE["rare"].to_html(false)).is_equal("6b9fd8")
	# a light blue and a light yellow: light, and neither the paper nor the brass
	for c: Color in [W.WEAPON_BLUE, W.LINE_YELLOW]:
		assert_float(c.get_luminance()).is_greater(0.6)
		assert_bool(c.is_equal_approx(W.PAPER) or c.is_equal_approx(W.BRASS)).is_false()
	# the line yellow (pass 47c, Garry: weapons like the lines)
	assert_bool(W.WEAPON_BLUE.is_equal_approx(W.LINE_YELLOW)).is_true()
	assert_float(W.LINE_YELLOW.r).is_greater(W.LINE_YELLOW.b + 0.3)
	# every base weapon common as an item in general (pass 48: a weapon's plate takes its level's colour, W.plate_fill;
	# level 0 reads common), every evolution dark in its brass ring
	for w: WeaponDef in Registry.weapons.values():
		var p := _plate(w)
		if w.is_evolution:
			assert_bool(p.fill.is_equal_approx(W.EVOLVED_FILL)).override_failure_message(w.id).is_true()
			assert_int(p.ring).is_greater(0)
		else:
			assert_bool(p.fill.is_equal_approx(W.RARITY_PLATE["common"])).override_failure_message(w.id).is_true()
	# lines common in general too (pass 48; their evolutions dark), passive items their rarity's colour, no ring
	var rarities := {}
	for pd: PassiveDef in Registry.passives.values():
		var p := _plate(pd)
		if pd.is_evolved():
			assert_bool(p.fill.is_equal_approx(W.EVOLVED_FILL)).override_failure_message(pd.id).is_true()
			assert_bool(p.ring_color.is_equal_approx(W.EVOLVED_RING)).is_true()
		elif pd.is_line():
			assert_bool(p.fill.is_equal_approx(W.RARITY_PLATE["common"])).override_failure_message(pd.id).is_true()
		else:
			assert_bool(p.fill.is_equal_approx(W.RARITY_PLATE[W.rarity_of(pd)])).override_failure_message(pd.id).is_true()
			assert_int(p.ring).is_equal(0)
			rarities[W.rarity_of(pd)] = true
	# the passive items span the tiers there are (pass 47b: common, uncommon, rare; pass 48: Sinner's Greed is epic); pass
	# 66: at most the four, never legendary (an item made in the Level Editor takes one of them)
	assert_int(rarities.size()).is_between(1, 4)
	assert_bool(rarities.has("legendary")).is_false()
	# the rest keep their kind's colour
	assert_bool(_plate(Registry.mutation("dragons_breath")).fill.is_equal_approx(W.PLUM)).is_true()
	assert_bool(_plate(Registry.perk("supply_drop")).fill.is_equal_approx(W.TURQUOISE)).is_true()
	# an unknown rarity reads as common
	var odd := PassiveDef.new()
	odd.rarity = "mythic"
	assert_str(W.rarity_of(odd)).is_equal("common")


func test_kinds_and_their_words() -> void:
	var brawn: PassiveDef = Registry.passive("brawn")
	var magnet: PassiveDef = Registry.passive("magnet")
	assert_str(W.kind_of(brawn)).is_equal("line")
	assert_str(W.kind_of(Registry.passive("juggernaut"))).is_equal("line")
	assert_str(W.kind_of(magnet)).is_equal("passive")
	assert_bool(W.is_line(brawn)).is_true()
	assert_bool(W.is_line(magnet)).is_false()
	assert_bool(W.is_line(Registry.weapon("boomstick"))).is_false()
	# the Registry, the save and the quests know both as passives
	assert_str(W.content_kind(brawn)).is_equal("passive")
	assert_str(W.content_kind(magnet)).is_equal("passive")
	assert_str(W.content_kind(Registry.weapon("boomstick"))).is_equal("weapon")
	assert_bool(W.KIND.has("line") and W.KIND_WORD.has("line")).is_true()
	# the cards' one word, and beside it the tag (pass 58: NEW and UPGRADE moved out of the word into the tag, and the
	# "LV 2 → 3" went for the stars and the change rows; Garry: "There should be some kind of an indicator on items when
	# they are upgraded rather than a new item")
	assert_str(WItem.word({"def": brawn, "level_from": 0, "level_to": 1})).is_equal("LINE")
	assert_str(WItem.tag({"def": brawn, "level_from": 0, "level_to": 1})).is_equal("NEW")
	assert_str(WItem.word({"def": brawn, "level_from": 2, "level_to": 3})).is_equal("LINE")
	assert_str(WItem.tag({"def": brawn, "level_from": 2, "level_to": 3})).is_equal("UPGRADE")
	assert_str(WItem.word({"def": Registry.passive("juggernaut"), "level_from": 4, "level_to": 5, "evolve": true})).is_equal("EVOLVES BRAWN")
	assert_str(WItem.tag({"def": Registry.passive("juggernaut"), "level_from": 4, "level_to": 5, "evolve": true})).is_equal("EVOLUTION")
	assert_str(WItem.word({"def": magnet, "level_from": 0, "level_to": 1})).is_equal("PASSIVE")
	assert_str(WItem.tag({"def": magnet, "level_from": 0, "level_to": 1})).is_equal("NEW")
	assert_str(WItem.word({"def": magnet, "level_from": 1, "level_to": 2})).is_equal("PASSIVE")
	assert_str(WItem.tag({"def": magnet, "level_from": 1, "level_to": 2})).is_equal("UPGRADE")
	assert_str(WItem.word({"def": Registry.weapon("boomstick"), "level_from": 0, "level_to": 1})).is_equal("WEAPON")
	assert_str(WItem.tag({"def": Registry.weapon("boomstick"), "level_from": 0, "level_to": 1})).is_equal("NEW")
	assert_str(WItem.word({"def": Registry.weapon("boomstick"), "level_from": 5, "level_to": 6})).is_equal("WEAPON")
	assert_str(WItem.tag({"def": Registry.weapon("boomstick"), "level_from": 5, "level_to": 6})).is_equal("UPGRADE")
	assert_bool(WItem.word_color({"def": brawn}).is_equal_approx(W.LINE_INK)).is_true()
	assert_bool(WItem.word_color({"def": Registry.weapon("boomstick")}).is_equal_approx(W.WEAPON_INK)).is_true()
	# no seal and no rarity word on a passive item's card: its plate says it
	var card := {"def": Registry.passive("brimstone_brand"), "level_from": 0, "level_to": 1}
	var c: WCard = auto_free(WCard.make(card["def"], WItem.options(card)))
	assert_object(c.seal).is_null()
	assert_str(_texts(c).to_lower()).not_contains("rare")
	assert_bool(c.plate.fill.is_equal_approx(W.RARITY_PLATE["rare"])).is_true()


func test_a_plate_without_an_icon_can_say_what_it_is() -> void:
	var p: WPlate = auto_free(WPlate.new())
	p.side = 96.0
	p.glyph = "?"
	add_child(p)
	await get_tree().process_frame
	assert_str(p.glyph).is_equal("?")
	# the badge over the corner
	p.badge = load("res://art/ui/badges/skull.png")
	p.queue_redraw()
	await get_tree().process_frame


# ---------------------------------------------------------------- the HUD

func test_the_hud_shows_six_weapons_and_six_lines_and_no_passive_item() -> void:
	_start()
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("magnet")
	Run.add_or_level_passive("desperado")
	assert_array(Run.held_lines()).contains(["brawn"])
	assert_array(Run.held_passives()).contains(["magnet", "desperado"])
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	var plates: Array = hud._slots.get_children()
	assert_int(plates.size()).is_equal(10)
	# no padlocks: both caps are static (five since pass 52)
	assert_int(plates.filter(func(p: WPlate) -> bool: return p.padlock).size()).is_equal(0)
	assert_int(plates.filter(func(p: WPlate) -> bool: return p.empty).size()).is_equal(7)
	assert_bool(hud._slot_nodes.has("peashooter") and hud._slot_nodes.has("boomstick") and hud._slot_nodes.has("brawn")).is_true()
	assert_bool(hud._slot_nodes.has("magnet") or hud._slot_nodes.has("desperado")).is_false()
	# five weapon slots, then five line slots (pass 52)
	var specs := HUD.slot_specs([[Registry.weapon("peashooter"), 2, 0]], Run.weapon_cap(), [], HUD.held_line_specs(), Run.line_cap(), [])
	assert_int(specs.size()).is_equal(10)
	assert_int(specs.slice(0, 5).filter(func(s: Array) -> bool: return bool(s[2])).size()).is_equal(5)
	assert_int(specs.slice(5, 10).filter(func(s: Array) -> bool: return not bool(s[2])).size()).is_equal(5)
	assert_bool(specs.all(func(s: Array) -> bool: return int(s[4]) == 0)).is_true()
	# a passive item's card flies into the pause disc (the Build tab lists it); a line's into its slot
	assert_bool(hud.slot_rect("magnet").is_equal_approx(hud._pause_btn.get_global_rect())).is_true()
	assert_bool(hud.slot_rect("brawn").is_equal_approx((hud._slot_nodes["brawn"] as WPlate).get_global_rect())).is_true()
	assert_float(hud.slot_rect("not_held").size.x).is_equal(0.0)
	# they fit one row
	for p: WPlate in plates:
		assert_float(p.position.y).is_less(12.0)
	# a new stage changes nothing on the strip
	Run.stage = 1
	hud.refresh_stage()
	plates = hud._slots.get_children().filter(func(p: Node) -> bool: return not p.is_queued_for_deletion())
	assert_int(plates.size()).is_equal(10)
	assert_int(plates.filter(func(p: WPlate) -> bool: return p.padlock).size()).is_equal(0)


func test_the_boss_name_has_no_ink_box() -> void:
	_start()
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	hud.show_boss(Registry.enemy("tumbleweed_king"))
	await get_tree().process_frame
	assert_bool(hud._boss_box.visible).is_true()
	assert_int(hud._boss_box.find_children("*", "PanelContainer", true, false).size()).is_equal(0)
	assert_str(hud._boss_name.text).is_equal("THE TUMBLEWEED KING")
	assert_bool(hud._boss_name.color.is_equal_approx(W.PAPER)).is_true()
	assert_int(hud._boss_name.stroke).is_greater(0)
	assert_int(hud._boss_name.shadow).is_greater(0)
	assert_object(hud._boss_icon.texture).is_not_null()
	hud.hide_boss()


func test_gold_rises_from_the_hero_and_steady_shows_beside_adrenaline() -> void:
	_start()
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	# Run.gold_gained reaches the HUD and is batched over a quarter second
	Run.gold_gained.emit(10)
	Run.gold_gained.emit(14)
	assert_int(hud._gold_batch).is_equal(24)
	assert_float(hud._gold_batch_t).is_equal_approx(0.25, 0.001)
	# the popup: the coin and "+24" in gold
	var row := hud.gold_popup(24, Vector2(540, 900))
	assert_int(_coins(row).size()).is_equal(1)
	assert_str(_texts(row)).contains("+24")
	# Steady Hand's buff label
	Run.steady_bucket = 7
	hud._refresh_buffs()
	assert_bool(hud._adren.visible).is_true()
	assert_str(hud._adren.text).contains("STEADY +35%")
	Run.steady_bucket = 0
	hud._refresh_buffs()
	assert_bool(hud._adren.visible).is_false()
	await get_tree().process_frame


# ---------------------------------------------------------------- the Collection

func test_the_collection_has_five_tabs_and_marks_the_dangerous_enemies() -> void:
	assert_array(CollectionScreen.TABS).is_equal(["Weapons", "Lines", "Passives", "Perks", "Enemies"])
	assert_str(CollectionScreen.danger_role(Registry.enemy("brander"))).is_equal("boss")
	assert_str(CollectionScreen.danger_role(Registry.enemy("dune_scorpion"))).is_equal("elite")
	assert_str(CollectionScreen.danger_role(Registry.enemy("rocketeer"))).is_equal("special")
	assert_str(CollectionScreen.danger_role(Registry.enemy("harpoon_troglodyte"))).is_equal("special")
	assert_str(CollectionScreen.danger_role(Registry.enemy("skeleton"))).is_equal("")
	var p: WPlate = auto_free(WPlate.new().for_def(Registry.enemy("brander"), 210.0))
	var spec := CollectionScreen.mark_danger(p, Registry.enemy("brander"), 84.0)
	assert_str(str(spec[0])).is_equal("skull")
	assert_object(p.badge).is_not_null()
	assert_int(p.ring).is_greater(0)
	assert_bool(p.ring_color.is_equal_approx(W.ROCK)).is_true()
	var q: WPlate = auto_free(WPlate.new().for_def(Registry.enemy("stone_golem"), 210.0))
	CollectionScreen.mark_danger(q, Registry.enemy("stone_golem"), 84.0)
	assert_bool(q.ring_color.is_equal_approx(W.EMBER)).is_true()
	var r: WPlate = auto_free(WPlate.new().for_def(Registry.enemy("skeleton"), 210.0))
	assert_array(CollectionScreen.mark_danger(r, Registry.enemy("skeleton"), 84.0)).is_empty()
	assert_object(r.badge).is_null()
	# the tabs hold what they say, and five fit the strip
	var c: Control = auto_free(load("res://ui/CollectionScreen.tscn").instantiate())
	add_child(c)
	await get_tree().process_frame
	await get_tree().process_frame
	var lines: Array = c._items(1)
	var passives: Array = c._items(2)
	assert_int(lines.size()).is_greater(0)
	assert_bool(lines.all(func(d: PassiveDef) -> bool: return d.is_line() and not d.is_evolved())).is_true()
	assert_bool(passives.all(func(d: PassiveDef) -> bool: return not d.is_line())).is_true()
	assert_bool(c._items(4).all(func(d) -> bool: return d is EnemyDef)).is_true()
	for t in CollectionScreen.TABS.size():
		c._tab = t
		c._show_grid()
		await get_tree().process_frame
		assert_float(c._tabs.get_combined_minimum_size().x).override_failure_message("tab %d" % t).is_less_equal(c.get_viewport_rect().size.x - 72.0)
	# the enemies' tiles carry the badges
	c._tab = 4
	c._show_grid()
	await get_tree().process_frame
	var badged: Array = c.content.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n is WPlate and (n as WPlate).badge != null)
	assert_int(badged.size()).is_greater_equal(5)
	c.visible = false


# ---------------------------------------------------------------- skips and banishes

func test_the_level_up_skip_and_banish_take_the_stage_s() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	assert_int(Run.skips_left).is_equal(2)
	assert_int(Run.banishes_left).is_equal(1)
	var cs: CardScreen = auto_free(CardScreen.new())
	add_child(cs)
	var offer := CardPool.level_up_offer(3)
	cs.show_offer(offer, "LEVEL 2!", false)
	# SKIP ×2, no coin, no gold
	assert_str(await _label(cs._skip_btn)).is_equal("SKIP ×2")
	assert_int(_coins(cs._skip_btn).size()).is_equal(0)
	assert_str(await _label(cs._banish_btn)).is_equal("BANISH ×1")
	var got: Array = []
	cs.chosen.connect(func(card): got.append(card))
	cs._skip()
	assert_int(Run.skips_left).is_equal(1)
	assert_int(got.size()).is_equal(1)
	assert_bool(bool(got[0].get("skipped", false))).is_true()
	# none left: the button locks, a tap says so and nothing closes
	Run.skips_left = 0
	cs.show_offer(offer, "LEVEL 3!", false)
	assert_bool(cs._skip_btn.locked).is_true()
	cs._skip()
	assert_int(got.size()).is_equal(1)
	assert_str(cs.header.line.text).is_equal("No skips left this stage.")
	# a banish takes the stage's one; pass 58: only a card that may go (never the held Boomstick's upgrade)
	cs._toggle_banish()
	var struck: Dictionary = CardPool.banishable(cs._offer)[0]
	cs._pick(struck)
	assert_int(Run.banishes_left).is_equal(0)
	assert_bool(Run.banished.has(struck["id"])).is_true()
	assert_bool(cs._banish_btn.locked).is_true()
	cs._toggle_banish()
	assert_str(cs.header.line.text).is_equal("No banishes left this stage.")
	# the mutation offer's SKIP uses the same skips
	Run.skips_left = 1
	cs.show_offer(CardPool.path_offer(Run.weapons[0]), "MUTATION", false, true)
	assert_str(await _label(cs._path_skip)).is_equal("SKIP ×1")
	cs._skip()
	assert_int(Run.skips_left).is_equal(0)
	assert_int(got.size()).is_equal(2)
	cs.show_offer(CardPool.path_offer(Run.weapons[0]), "MUTATION", false, true)
	cs._skip()
	assert_int(got.size()).is_equal(2)
	assert_bool(cs._path_note.visible).is_true()
	assert_str(cs._path_note.text).is_equal("No skips left this stage.")
	cs.visible = false
	await get_tree().process_frame


func test_the_chest_skips_banishes_and_spins_again() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	Run.add_weapon(Registry.weapon("peashooter"), 2)
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	var r := {"type": "weapon", "id": "boomstick", "def": Registry.weapon("boomstick"), "level_from": 2, "level_to": 3, "is_new": false}
	cs.open(r)
	# the chest opens on the lower third, its light under the reel
	assert_float(cs._chest.center.y).is_greater(cs.get_viewport_rect().size.y * 0.6)
	assert_float(cs._mouth.y).is_greater(ChestScreen.REEL_Y + ChestScreen.BIG)
	await _land(cs)
	assert_bool(cs._spinning).is_false()
	assert_bool(cs.buttons.visible).is_true()
	assert_str(await _label(cs._skip_btn)).is_equal("SKIP ×2")
	assert_str(await _label(cs._banish_btn)).is_equal("BANISH ×1")
	assert_str(await _label(cs._take_btn)).is_equal("TAKE IT")
	assert_bool(cs._skip_btn.visible and cs._banish_btn.visible).is_true()
	assert_str(_texts(cs).to_upper()).not_contains("SELL")
	# no skip left: the chest stays, the header says so
	var closed: Array = []
	cs.closed.connect(func(take): closed.append(take))
	Run.skips_left = 0
	cs._refresh_buttons()
	assert_bool(cs._skip_btn.locked).is_true()
	cs._skip()
	assert_int(closed.size()).is_equal(0)
	assert_str(cs.header.line.text).is_equal("No skips left this stage.")
	# pass 58 (Garry: "Banish option should not allow Banishing items that Player already has"): the Boomstick is held,
	# so BANISH is locked on its next level and a tap says why, spending nothing
	assert_bool(cs._banish_btn.locked).is_true()
	cs._banish()
	assert_str(cs.header.line.text).is_equal(ChestScreen.banish_refusal(r))
	assert_int(Run.banishes_left).is_equal(1)
	assert_bool(Run.banished.has("boomstick")).is_false()
	assert_int(cs.respins).is_equal(0)
	# a banish of a new passive item: the stage's one taken, the item struck, the reel spun again and landed, the chest
	# still open
	var fresh := {"type": "passive", "id": "magnet", "def": Registry.passive("magnet"), "level_from": 0, "level_to": 1, "is_new": true}
	cs.open(fresh)
	await _land(cs)
	assert_bool(cs._banish_btn.locked).is_false()
	cs._banish()
	assert_int(Run.banishes_left).is_equal(0)
	assert_bool(Run.banished.has("magnet")).is_true()
	assert_int(cs.respins).is_equal(1)
	assert_bool(cs._spinning).is_true()
	assert_float(cs._spin_total).is_equal_approx(ChestScreen.RESPIN + 0.22, 0.001)
	assert_bool(cs.visible).is_true()
	await _land(cs)
	assert_bool(cs._spinning).is_false()
	assert_bool(cs.buttons.visible).is_true()
	assert_str(str(cs.result().get("id", ""))).is_not_equal("magnet")
	assert_bool(cs._banish_btn.locked).is_true()
	# with a skip again it closes on nothing
	Run.skips_left = 1
	cs._refresh_buttons()
	cs._skip()
	await get_tree().create_timer(0.3).timeout
	assert_array(closed).is_equal([false])
	# gold: SKIP and BANISH lock (it goes straight into the purse), a tap says why and nothing closes or spins
	Run.skips_left = 2
	Run.banishes_left = 1
	closed.clear()
	cs.open({"type": "gold", "id": "", "def": null, "gold": 50, "level_from": 0, "level_to": 0, "is_new": false})
	await _land(cs)
	assert_bool(cs._skip_btn.locked and cs._banish_btn.locked).is_true()
	assert_bool(cs._take_btn.visible and not cs._take_btn.locked).is_true()
	cs._skip()
	assert_str(cs.header.line.text).is_equal("Gold goes straight into the purse.")
	cs._banish()
	assert_str(cs.header.line.text).is_equal("Gold cannot be banished.")
	assert_int(cs.respins).is_equal(0)
	assert_int(Run.skips_left).is_equal(2)
	assert_int(Run.banishes_left).is_equal(1)
	# an evolution: BANISH locks (banished, the weapon would stay unevolved), SKIP still skips
	var evo: WeaponDef = Registry.weapon(Registry.weapon("boomstick").evolves_into)
	cs.open({"type": "evolution", "id": evo.id, "def": evo, "src_id": "boomstick", "level_from": 0, "level_to": 1, "is_new": true})
	await _land(cs)
	assert_bool(cs._banish_btn.locked).is_true()
	assert_bool(cs._skip_btn.locked).is_false()
	cs._banish()
	assert_str(cs.header.line.text).is_equal("An evolution cannot be banished.")
	assert_int(cs.respins).is_equal(0)
	assert_int(Run.banishes_left).is_equal(1)
	# pass 58 (Run.banish_refusal, the game's one rule): a held weapon's next level and a path mutation of a held weapon
	# cannot go either; a new passive item can
	assert_bool(ChestScreen.can_banish({"type": "weapon", "id": "boomstick", "def": Registry.weapon("boomstick")})).is_false()
	assert_bool(ChestScreen.can_banish({"type": "mutation", "id": "dragons_breath", "def": Registry.mutation("dragons_breath")})).is_false()
	assert_bool(ChestScreen.can_banish({"type": "passive", "id": "cake", "def": Registry.passive("cake"), "level_from": 0, "level_to": 1, "is_new": true})).is_true()
	assert_bool(ChestScreen.can_banish({"type": "evolution", "id": "x", "def": evo})).is_false()
	assert_bool(ChestScreen.can_banish({"type": "gold", "def": null})).is_false()
	cs.visible = false


## Pass 58 (Garry: "Banish option should not allow Banishing items that Player already has, because this way they can
## lock themselves out of progression for those weapons"): the boss chest's mutation is for a weapon the hero carries,
## and a banished path mutation would keep that weapon from its evolution all run, so BANISH is locked and says why (it
## spun to another mutation until pass 58).
func test_a_boss_chest_never_banishes_its_mutation() -> void:
	_start()
	Run.add_weapon(Registry.weapon("hornet_nest"), 3)
	var cs: ChestScreen = auto_free(ChestScreen.new())
	add_child(cs)
	await get_tree().process_frame
	var r := Run.chest_roll(true)
	assert_str(str(r.get("type", ""))).is_equal("mutation")
	cs.open(r)
	assert_bool(cs._chest.boss).is_true()
	await _land(cs)
	assert_bool(cs._banish_btn.locked).is_true()
	var left := Run.banishes_left
	cs._banish()
	assert_int(cs.respins).is_equal(0)
	assert_bool(Run.banished.has(str(r["id"]))).is_false()
	assert_int(Run.banishes_left).is_equal(left)
	# pass 60: no mutation can be banished; the line says so plainly
	assert_str(cs.header.line.text).contains("mutation")
	cs.visible = false


# ---------------------------------------------------------------- the Results

func test_every_damage_source_has_a_plate_a_name_and_a_number() -> void:
	var rs = load("res://ui/ResultsScreen.gd")
	# every weapon, the perks and the power-up that deal damage are their items
	for w: WeaponDef in Registry.weapons.values():
		var s: Dictionary = rs.damage_source(w.id)
		assert_object(s["def"]).override_failure_message(w.id).is_same(w)
		assert_str(str(s["name"])).is_equal(w.display_name)
	for id in ["supply_drop", "grand_finale"]:
		var s2: Dictionary = rs.damage_source(id)
		assert_bool(s2["def"] is PerkDef).override_failure_message(id).is_true()
	assert_bool(rs.damage_source("nuke")["def"] is PickupDef).is_true()
	# the rest by what they are
	var names := {"revive": "Revive blast", "fire": "Fire", "burn": "Fire", "poison": "Poison", "blast": "Explosions",
		"loose_rocket": "Explosions", "thorns": "Thorns", "": "Unknown"}
	for id in names:
		var s3: Dictionary = rs.damage_source(id)
		assert_str(str(s3["name"])).override_failure_message(id).is_equal(names[id])
		assert_object(s3["def"]).is_null()
	assert_object(rs.damage_source("poison")["icon"]).is_same(Registry.passive("venom").icon)
	assert_str(str(rs.damage_source("mystery_beam")["name"])).is_equal("Mystery Beam")
	# the rows: one a source (the explosions summed), each its plate (an icon or the "?"), name, number and share
	var rows: VBoxContainer = auto_free(rs.damage_rows({"boomstick": 600.0, "blast": 120.0, "loose_rocket": 30.0, "revive": 200.0,
		"burn": 40.0, "": 9.0, "mystery_beam": 1.0}))
	assert_int(rows.get_child_count()).is_equal(6)
	var first: HBoxContainer = rows.get_child(0)
	assert_str(str(first.get_meta("source")["name"])).is_equal("Boomstick")
	for row in rows.get_children():
		var plate: WPlate = row.get_child(0)
		assert_bool(plate.tex != null or plate.glyph == "?").is_true()
		assert_object(row.find_child("Name", true, false)).is_not_null()
		var amount: WText = row.find_child("Amount", true, false)
		assert_str(amount.text).is_not_empty()
	var said := _texts(rows)
	assert_str(said).contains("Explosions")
	assert_str(said).contains("150")
	assert_str(said).contains("<1%")


# ---------------------------------------------------------------- the stage clear and the pause screen

func test_the_stage_clear_lists_no_slots() -> void:
	_start()
	var pd: PortalDialog = auto_free(PortalDialog.new())
	add_child(pd)
	pd.open(1, true, false)
	await get_tree().process_frame
	assert_str(_texts(pd).to_lower()).not_contains("slot")
	pd.visible = false


func test_the_build_tab_lists_the_lines_and_every_passive_item() -> void:
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 2)
	Run.add_or_level_passive("brawn")
	Run.add_or_level_passive("magnet")
	Run.add_or_level_passive("desperado")
	var ps: PauseScreen = auto_free(PauseScreen.new())
	add_child(ps)
	ps._tab = 0
	ps._refresh()
	await get_tree().process_frame
	for g in ["GroupWeapons", "GroupLines", "GroupPassives"]:
		assert_object(ps._content.find_child(g, false, false)).override_failure_message(g).is_not_null()
	var rows: Array = ps._content.get_children().filter(func(n: Node) -> bool: return n is WRow)
	assert_int(rows.size()).is_equal(4)
	var said := _texts(ps._content)
	assert_str(said).contains("Magnet")
	assert_str(said).contains("Desperado")
	assert_str(said).contains("Brawn")
	ps.visible = false
