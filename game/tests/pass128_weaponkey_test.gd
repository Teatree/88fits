## Pass 128, lane UI, job 4 (Garry: "whenever a player unlocks heroes that have their starting weapons, that starting
## weapon becomes available to players in their runs"; owning him is the only key):
##  - a base weapon an outlaw (not hidden) starts with is offered in a run only once he is owned (Registry.hero_may_use,
##    weapon_comes_with; unlocked_weapons, CardPool.offer_weapons), and is in afterwards;
##  - the run outlaw's own weapon, a held weapon and the run outlaw's favourite are always in;
##  - Mira and Dad (hidden, no start weapon) gate nothing; the Drifter is free, so his Revolver is anyone's;
##  - a Wanted poster never names a gated weapon (WantedBoard.context uses the same rule);
##  - the quests unlock_pike and unlock_big_mouth are retired;
##  - a gated weapon reads "Comes with <name>" and the Outlaws screen opens on him once (HeroesScreen.open_on).
extends GdUnitTestSuite

## weapon id -> the outlaw who starts with it (the Drifter's Revolver apart: he is free)
const KEYS := {"gravity_gun": "astro", "guitarra": "calavera", "pike": "ironwood", "sun_scepter": "solenne",
	"basketball": "fadeaway", "frisbee": "buck", "big_mouth": "may"}


func before_test() -> void:
	# pass 132: Ironwood is free in the game now; this suite's checks of an outlaw sold for gold put him on sale for their time
	Registry.character("ironwood").availability = "purchase"
	# a new save: only the Drifter is owned
	Save.data = Save._default()
	Run.arena = false
	CardPool.rng = null


func after_test() -> void:
	Registry.character("ironwood").availability = "available"
	CardPool.rng = null
	Run.arena = false
	Run.end()
	load("res://ui/HeroesScreen.gd").set("open_on", "")


func _start(hero: String = "drifter") -> void:
	var c: CharacterDef = Registry.character(hero)
	Run.start(c, Registry.map("red_canyon"))
	Run.add_weapon(Registry.start_weapon_for(c), 1)


## The save owns outlaw `id`: bought, and his unlock quest (if he has one) done.
func _own(id: String) -> void:
	if not Save.heroes_owned().has(id):
		Save.heroes_owned().append(id)
	var q := Registry.quest_for("character", id)
	if q and not Save.quest_done(q.id):
		(Save.data["quests_done"] as Array).append(q.id)


func _ids(list: Array) -> Array:
	return list.map(func(w): return str(w.id))


func test_each_outlaws_weapon_is_out_until_he_is_owned_and_in_afterwards() -> void:
	_start("drifter")
	# the Drifter is free: nothing waits for him
	assert_object(Registry.weapon_comes_with(Registry.weapon("revolver"))).is_null()
	for wid: String in KEYS.keys():
		var w: WeaponDef = Registry.weapon(wid)
		var c: CharacterDef = Registry.character(str(KEYS[wid]))
		assert_object(w).override_failure_message(wid).is_not_null()
		assert_str(c.start_weapon).is_equal(wid)
		assert_bool(Registry.hero_owned(c)).override_failure_message(c.id + " owned on a new save").is_false()
		assert_object(Registry.weapon_comes_with(w)).override_failure_message(wid).is_same(c)
		assert_bool(Registry.hero_may_use(w)).override_failure_message(wid).is_false()
		assert_bool(_ids(Registry.unlocked_weapons()).has(wid)).override_failure_message(wid + " in the pool").is_false()
		assert_bool(_ids(CardPool.offer_weapons()).has(wid)).override_failure_message(wid + " offered").is_false()
		_own(c.id)
		assert_bool(Registry.hero_owned(c)).override_failure_message(c.id).is_true()
		assert_object(Registry.weapon_comes_with(w)).override_failure_message(wid).is_null()
		assert_bool(Registry.hero_may_use(w)).override_failure_message(wid).is_true()
		# in, by the rules that were there before (hidden, an unlock quest, the legendary hold)
		var open := not w.hidden and Registry.is_unlocked("weapon", wid)
		assert_bool(_ids(Registry.unlocked_weapons()).has(wid)).override_failure_message(wid + " after").is_equal(open)
		assert_bool(_ids(CardPool.offer_weapons()).has(wid)).override_failure_message(wid + " offered after").is_equal(open and not LegendaryHold.held(w))
		# a weapon marked an outlaw's own (WeaponDef.hero) still weighs its guest_weight in another's run
		if w.hero != "":
			assert_bool(Registry.is_guest_weapon(w)).override_failure_message(wid).is_true()


func test_the_run_outlaws_own_weapon_a_held_weapon_and_his_favourite_are_always_in() -> void:
	# Ironwood's run on a save that does not own him (the arena, a tool): the Spear is his
	_start("ironwood")
	var pike: WeaponDef = Registry.weapon("pike")
	assert_bool(Registry.hero_owned(Registry.character("ironwood"))).is_false()
	assert_bool(Registry.hero_may_use(pike)).is_true()
	assert_bool(Registry.unlocked_weapons().has(pike)).is_true()
	assert_bool(CardPool.offer_weapons().has(pike)).is_true()
	# asked about another outlaw, the answer is his
	assert_bool(Registry.hero_may_use(pike, Registry.character("drifter"))).is_false()
	assert_bool(Registry.hero_may_use(pike, Registry.character("ironwood"))).is_true()
	Run.end()
	# a weapon held stays in the offers whatever its key (the Drifter with the Gravity Gun in hand)
	_start("drifter")
	var gg: WeaponDef = Registry.weapon("gravity_gun")
	assert_bool(CardPool.offer_weapons().has(gg)).is_false()
	Run.add_weapon(gg, 1)
	assert_bool(CardPool.offer_weapons().has(gg)).is_true()
	# and the run outlaw's favourite, whoever starts with it
	var c: CharacterDef = Run.character
	var was := c.favourite_weapon
	var guitar: WeaponDef = Registry.weapon("guitarra")
	assert_bool(CardPool.offer_weapons().has(guitar)).is_false()
	c.favourite_weapon = "guitarra"
	var has := CardPool.offer_weapons().has(guitar)
	c.favourite_weapon = was
	assert_bool(has).is_equal(not guitar.hidden and not LegendaryHold.held(guitar))


func test_mira_and_dad_gate_nothing() -> void:
	for id: String in ["mira", "dad"]:
		var c: CharacterDef = Registry.character(id)
		assert_object(c).override_failure_message(id).is_not_null()
		assert_str(c.start_weapon).override_failure_message(id).is_equal("")
	# every gate there is belongs to an outlaw in play who starts with that weapon
	for w: WeaponDef in Registry.base_weapons():
		var g: CharacterDef = Registry.weapon_comes_with(w)
		if g != null:
			assert_str(g.id).override_failure_message(w.id).is_equal(str(KEYS.get(w.id, "")))
			assert_bool(g.hidden).is_false()
	# a hidden outlaw gates nothing even with a start weapon
	var dad: CharacterDef = Registry.character("dad")
	var boom: WeaponDef = Registry.weapon("boomstick")
	dad.start_weapon = "boomstick"
	var g2: CharacterDef = Registry.weapon_comes_with(boom)
	dad.start_weapon = ""
	assert_object(g2).is_null()
	# an evolution is never gated (it is never a card of its own)
	assert_object(Registry.weapon_comes_with(Registry.weapon(Registry.weapon("pike").evolves_into))).is_null()


func test_a_poster_never_names_a_gated_weapon() -> void:
	var names := func(hero: String) -> Array:
		return (WantedBoard.context("red_canyon", 0, hero)["weapons"] as Array).map(func(x): return str(x["id"]))
	var first: Array = names.call("drifter")
	assert_bool(first.has("revolver")).is_true()
	for wid: String in KEYS.keys():
		assert_bool(first.has(wid)).override_failure_message("a poster may name " + wid).is_false()
	# his own start weapon is on his own posters whatever the save owns
	assert_bool((names.call("ironwood") as Array).has("pike")).is_true()
	# owned: on anyone's posters (pass 35's "another hero's own never" is gone), by the stage rule that was there
	_own("astro")
	var gg: WeaponDef = Registry.weapon("gravity_gun")
	assert_bool((names.call("drifter") as Array).has("gravity_gun")).is_equal(not gg.hidden and gg.from_stage <= 1)


func test_the_two_quests_are_retired() -> void:
	for wid: String in ["pike", "big_mouth"]:
		assert_bool(Registry.quests.has("unlock_" + wid)).override_failure_message(wid).is_false()
		assert_object(Registry.quest_for("weapon", wid)).is_null()
		assert_bool(Registry.is_unlocked("weapon", wid)).is_true()
		assert_bool(DirAccess.dir_exists_absolute("res://content/quests/unlock_" + wid)).is_false()
	assert_array(Registry.problems).is_empty()


func test_a_gated_weapon_reads_comes_with_and_opens_the_outlaws_screen_on_him() -> void:
	var may: CharacterDef = Registry.character("may")
	var mouth: WeaponDef = Registry.weapon("big_mouth")
	assert_object(CollectionScreen.comes_with(mouth)).is_same(may)
	assert_object(CollectionScreen.comes_with(Registry.weapon("revolver"))).is_null()
	assert_object(CollectionScreen.comes_with(Registry.passives.values()[0])).is_null()
	assert_str(CollectionScreen.comes_with_words(may)).is_equal("Comes with " + may.display_name)
	var line: WTap = auto_free(CollectionScreen.comes_with_line(may, 30, null))
	assert_str(str(line.get_meta("outlaw"))).is_equal("may")
	assert_str((line.find_child("Words", true, false) as WText).text).is_equal("Comes with " + may.display_name)
	# the Collection: locked, the tile and the page say it, no quest
	var col: CollectionScreen = auto_free(load("res://ui/CollectionScreen.tscn").instantiate())
	add_child(col)
	await get_tree().process_frame
	assert_bool(col._locked(mouth)).is_true()
	assert_str(col._still_to_find(mouth)).is_equal("Comes with " + may.display_name)
	col._open_locked(mouth)
	await get_tree().process_frame
	var tap: WTap = col.content.find_child("ComesWith", true, false)
	assert_object(tap).is_not_null()
	assert_object(col.content.find_child("Quest", true, false)).is_null()
	_own("may")
	assert_bool(col._locked(mouth)).is_false()
	col.queue_free()
	# the Outlaws screen opens on him once, then on the last one played as ever
	var hs_script = load("res://ui/HeroesScreen.gd")
	hs_script.set("open_on", "calavera")
	var hs: Control = auto_free(load("res://ui/HeroesScreen.tscn").instantiate())
	add_child(hs)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_str(str(hs.get("shown").id)).is_equal("calavera")
	assert_str(str(hs_script.get("open_on"))).is_equal("")
