## Pass 83, lane META (Garry: "Go through our requirements and prices ... Most of the locked [heroes] have requirements
## - 2 are only unlocked for money"; "Items that are hero specific should be hidden in the Collections Menu if that hero
## is not unlocked"; "The Thorn Mirror Upgrade is way too OP, nerf it"): exactly two heroes are sold for gold alone,
## every other locked hero has an unlock quest and then a price, the prices climb with the title order; a save that had
## freed Ironwood by his old quest keeps him; a hero's own items (weapon, its evolution, hero mutations, perks) are left
## out of the Collection until he is owned; the Upgrade board's Thorns is +2 a rank (was +5) and thorns answer at most
## one hit every 0.5 s, their damage recorded as "thorns".
extends GdUnitTestSuite

## The two heroes on sale with no requirement (pass 83's pick: the first two after the Drifter in the title order).
const MONEY_ONLY := ["astro", "ironwood"]


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false


func after_test() -> void:
	CollectionScreen.hidden_only = false
	get_tree().paused = false
	Run.arena = false
	Run.end()
	Save.data = Save._default()
	Save._dirty = false


func _hero(id: String) -> CharacterDef:
	var c: CharacterDef = Registry.character(id)
	assert_object(c).override_failure_message(id).is_not_null()
	return c


## The heroes a new player meets locked (on the title, not free).
func _locked_heroes() -> Array:
	return Registry.sorted_characters().filter(func(c: CharacterDef) -> bool: return not c.hidden and c.availability == "purchase")


# ---------------------------------------------------------------- 1. heroes: requirements and prices

func test_exactly_two_locked_heroes_are_sold_for_gold_alone() -> void:
	var money_only: Array = []
	for c: CharacterDef in _locked_heroes():
		if Registry.quest_for("character", c.id) == null:
			money_only.append(c.id)
	money_only.sort()
	assert_array(money_only).is_equal(MONEY_ONLY)
	# on a clean save those two are on sale at once, every other locked hero waits for his quest
	for c: CharacterDef in _locked_heroes():
		assert_str(Registry.hero_state(c)).override_failure_message(c.id).is_equal("buyable" if MONEY_ONLY.has(c.id) else "locked")


func test_every_other_hero_is_free_or_needs_a_requirement_then_a_price() -> void:
	# the Drifter is the only free hero on the title; nobody is free behind a quest any more (Ironwood was, until pass 83)
	for c: CharacterDef in Registry.sorted_characters():
		if c.hidden:
			continue
		if c.availability == "available":
			assert_str(c.id).is_equal("drifter")
			assert_object(Registry.quest_for("character", c.id)).is_null()
		else:
			assert_str(c.availability).override_failure_message(c.id).is_equal("purchase")
			assert_int(c.price).override_failure_message(c.id).is_greater(0)
	assert_object(Registry.quests.get("unlock_ironwood")).is_null()
	# the requirements vary in kind (a boss, an extraction, a creature, minutes, a level) and read as TextGen says them
	var kinds := {}
	for c: CharacterDef in _locked_heroes():
		var q := Registry.quest_for("character", c.id)
		if q:
			kinds[str(q.condition.get("type", ""))] = true
			assert_str(TextGen.quest_text(q)).override_failure_message(c.id).is_not_equal("Complete a challenge.")
			assert_bool(Registry.quest_visible(q)).override_failure_message(c.id).is_true()
	assert_int(kinds.size()).is_greater_equal(4)
	var fq := Registry.quest_for("character", "fadeaway")
	assert_object(fq).is_not_null()
	# re-pinned in pass 100 (lane QUESTS, Garry: more requirements about levels): Fadeaway's requirement is a level
	# reached with the Drifter (it was 3 Saiga Snipers), read off his quest's own condition; an early hero still (stage 1
	# or 2 by the Collection's hint)
	assert_str(str(fq.condition.get("type", ""))).is_equal("hero_level")
	assert_str(TextGen.quest_text(fq)).is_equal("Reach level %d with Drifter." % int(fq.condition.get("level", 0)))
	assert_int(QuestTracker.stage_hint(fq)).is_between(1, 2)


func test_the_prices_climb_with_the_title_order() -> void:
	var last := 0
	for c: CharacterDef in _locked_heroes():
		if c.id == "mira":
			continue
		assert_int(c.price).override_failure_message("%s %d after %d" % [c.id, c.price, last]).is_greater_equal(last)
		last = c.price
	# the two sold for gold alone are the cheapest
	for id: String in MONEY_ONLY:
		for c: CharacterDef in _locked_heroes():
			assert_int(_hero(id).price).override_failure_message(c.id).is_less_equal(c.price)


func test_a_save_that_freed_ironwood_by_his_old_quest_keeps_him() -> void:
	var iw := _hero("ironwood")
	assert_str(Registry.hero_state(iw)).is_equal("buyable")
	Save.data["quests_done"] = ["unlock_ironwood"]
	Save._keep_freed_heroes()
	assert_bool(Save.owns_hero("ironwood")).is_true()
	assert_str(Registry.hero_state(iw)).is_equal("owned")
	# once, whatever how often it runs
	Save._keep_freed_heroes()
	assert_int((Save.data["heroes_owned"] as Array).count("ironwood")).is_equal(1)
	# a save that never did it buys him like anyone
	Save.data = Save._default()
	Save._keep_freed_heroes()
	assert_bool(Save.owns_hero("ironwood")).is_false()


# ---------------------------------------------------------------- 2. the Collection: hero items while he is not owned

func test_items_know_their_hero() -> void:
	assert_str(CollectionScreen.item_hero(Registry.weapon("revolver"))).is_equal("drifter")
	assert_str(CollectionScreen.item_hero(Registry.weapon("basketball"))).is_equal("fadeaway")
	var bb_evo: WeaponDef = Registry.weapon(Registry.weapon("basketball").evolves_into)
	if bb_evo:
		assert_str(CollectionScreen.item_hero(bb_evo)).is_equal("fadeaway")
	assert_str(CollectionScreen.item_hero(Registry.mutation("danza_macabra"))).is_equal("calavera")
	assert_str(CollectionScreen.item_hero(Registry.perks.get("supply_drop"))).is_equal("astro")
	# a favourite or a start weapon anyone may take is nobody's own
	assert_str(CollectionScreen.item_hero(Registry.weapon("frisbee"))).is_equal("")
	assert_str(CollectionScreen.item_hero(Registry.passive("evade"))).is_equal("")


func test_a_heros_items_are_hidden_until_he_is_owned() -> void:
	var cs: CollectionScreen = auto_free(load("res://ui/CollectionScreen.tscn").instantiate())
	var ball := Registry.weapon("basketball")
	# a clean save owns only the Drifter: his Revolver shows, Fadeaway's ball, Calavera's own mutation and Astro's perks
	# do not (not even as a silhouette)
	assert_bool(CollectionScreen.hero_item_hidden(Registry.weapon("revolver"))).is_false()
	assert_bool(CollectionScreen.hero_item_hidden(ball)).is_true()
	assert_bool(cs._items(0).has(ball)).is_false()
	assert_bool(cs._items(0).has(Registry.weapon("revolver"))).is_true()
	assert_bool(cs._items(3).any(func(d: ContentDef) -> bool: return (d as PerkDef).hero == "astro")).is_false()
	assert_bool(cs._items(3).any(func(d: ContentDef) -> bool: return (d as PerkDef).hero == "drifter")).is_true()
	var rain: Array = CollectionScreen.page_mutations(Registry.weapon("skull_rain")).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(rain.has("danza_macabra")).is_false()
	# the tab's count leaves them out too
	var tally := cs._tally(0)
	# bought: they come back
	Save.heroes_owned().append("fadeaway")
	Save.heroes_owned().append("calavera")
	Save.heroes_owned().append("astro")
	assert_bool(CollectionScreen.hero_item_hidden(ball)).is_false()
	assert_bool(cs._items(0).has(ball)).is_true()
	assert_int(cs._tally(0).y).is_greater(tally.y)
	assert_bool(cs._items(3).any(func(d: ContentDef) -> bool: return (d as PerkDef).hero == "astro")).is_true()
	rain = CollectionScreen.page_mutations(Registry.weapon("skull_rain")).map(func(m: MutationDef) -> String: return m.id)
	assert_bool(rain.has("danza_macabra")).is_true()
	# a quest done but not bought is still not his: on sale is not owned
	Save.data["heroes_owned"] = []
	Save.mark_quest("unlock_calavera")
	assert_str(Registry.hero_state(_hero("calavera"))).is_equal("buyable")
	assert_bool(CollectionScreen.hero_item_hidden(Registry.mutation("danza_macabra"))).is_true()
	# the developer's Hidden list is never filtered
	CollectionScreen.hidden_only = true
	assert_bool(CollectionScreen.hero_item_hidden(ball)).is_false()
	CollectionScreen.hidden_only = false


# ---------------------------------------------------------------- 3. Thorns

## Pass 88 (lane MIRROR, re-pinned on purpose): the Upgrade board's Thorns form is gone (Spite is Stakes: Difficulty and
## Boss, game/tests/pass88_mirror_test.gd); thorns stay on the passive items (Bristle), at most one burst a cooldown.
func test_the_upgrade_board_has_no_thorns_form_any_more() -> void:
	var td: TalentDef = Registry.talent("spite")
	assert_object(td).is_not_null()
	for form in range(2):
		assert_str(td.form_name(form)).is_not_equal("Thorns")
		for x: Effect in td.effects_for(form, td.max_rank()):
			assert_str(x.stat).is_not_equal("thorns")
	assert_float(Game.THORNS_COOLDOWN).is_equal_approx(0.5, 0.001)


func test_thorns_strike_once_a_cooldown_and_are_recorded() -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false}))
	f.close()
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.5).timeout
	g.director.stop()
	g.enemies.kill_all(false)
	assert_bool(Run.add_or_level_passive("bristle")).is_true()
	Run.rebuild_sheets()
	assert_float(Run.player_sheet.get_stat("thorns", 0.0)).is_greater(0.0)
	# no hit of their own reaches him while they rise and the grid takes them in (god: no hit, so no burst of theirs)
	g.player.god = true
	var at: Vector3 = g.player.global_position
	for k in 3:
		g.enemies.spawn("skeleton", at + Vector3(0.6 * float(k) - 0.6, 0, 0.5))
	await get_tree().create_timer(1.2).timeout
	g._thorns_last = -1000.0
	var before := float(Run.damage_by_weapon.get("thorns", 0.0))
	g._thorns_burst()
	var once := float(Run.damage_by_weapon.get("thorns", 0.0))
	assert_float(once).is_greater(before)
	# a second hit inside the cooldown brings no burst
	g._thorns_burst()
	assert_float(float(Run.damage_by_weapon.get("thorns", 0.0))).is_equal(once)
	# and the Results know the id
	assert_bool((load("res://ui/ResultsScreen.gd") as GDScript).get_script_constant_map()["SOURCES"].has("thorns")).is_true()
