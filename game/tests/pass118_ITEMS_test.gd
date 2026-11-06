## Pass 118, lane ITEMS (Garry: "Credit Card (Green) ... Our version will be Epic ... +1% Luck from each Chest Open, and
## when Player Upgrades it it doesn't affect previous Luck increases, only the subsequent ones", the Red one "something
## similar", "Keys instead", the Blacksmith's Anvil "not an Anvil but something else", Beer "not an Alcoholic thing",
## "the Hero Weapons ... add them all to the pull ... +5-10% likelihood not more"): the Jade Key and the Ruby Key bank
## luck and attack damage at every chest opened (Run.chest_opened, chest_bank), at the key's level when the chest opens;
## the Grindstone grinds bonuses into a weapon at its level-ups (pass 119, lane LEGEND_B: Garry "let's not add extra stats
## to weapons. Just Upgrade or Evolve the weakest one": the grind is gone, the Grindstone is rare and pinned in
## pass119_LEGEND_B_test.gd); every hero's own weapon is in every hero's pool at its guest_weight,
## and the weapon-card share of a level-up rises within Garry's 5-10%; Beer is the Ghost Pepper.
extends GdUnitTestSuite


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	CardPool.rng = null


func after_test() -> void:
	CardPool.rng = null
	Run.arena = false
	Run.end()


## A run of `hero` holding his own weapon at level 1 (Game hands it over; Run.start alone does not).
func _start(hero: String = "drifter") -> void:
	var c: CharacterDef = Registry.character(hero)
	Run.start(c, Registry.map("red_canyon"))
	Run.add_weapon(Registry.start_weapon_for(c), 1)


func _luck() -> float:
	return Run.player_sheet.get_stat("luck", 0.0)


func _might() -> float:
	return Run.player_sheet.get_stat("might", 1.0)


# ---------------------------------------------------------------- the keys

func test_the_items_are_there_available_and_on_the_ladder() -> void:
	for id in ["jade_key", "ruby_key", "grindstone"]:
		var p: PassiveDef = Registry.passive(id)
		assert_object(p).override_failure_message(id).is_not_null()
		assert_bool(p.is_item()).is_true()
		assert_bool(p.hidden).is_false()
		# no unlock quest: offered from the start
		assert_bool(Registry.is_unlocked("passive", id)).override_failure_message(id + " is locked").is_true()
		assert_bool(Registry.unlocked_passives().has(p)).is_true()
		assert_str(p.flavour).is_not_empty()
		assert_object(p.icon).is_not_null()
		assert_object(p.evolved_icon).is_not_null()
	assert_str(Registry.passive("jade_key").rarity).is_equal("epic")
	assert_str(Registry.passive("ruby_key").rarity).is_equal("epic")
	# pass 119 (lane LEGEND_B): the Grindstone raises the weakest weapon now, a rare item (pass 121, lane GRIND: of one
	# level, a one-shot item off the ladder: pass121_GRIND_test)
	assert_str(Registry.passive("grindstone").rarity).is_equal("rare")
	assert_int(Registry.passive("jade_key").max_level).is_equal(3)
	assert_int(Registry.passive("grindstone").max_level).is_equal(1)


func test_a_chest_banks_luck_at_the_keys_level_then_and_a_level_up_never_changes_the_bank() -> void:
	_start()
	var l0 := _luck()
	# no key: a chest banks nothing
	Run.chest_opened()
	assert_bool(Run.chest_bank.is_empty()).is_true()
	assert_float(_luck()).is_equal_approx(l0, 0.00001)
	assert_bool(Run.add_or_level_passive("jade_key")).is_true()
	# holding it gives nothing before a chest
	assert_float(_luck()).is_equal_approx(l0, 0.00001)
	Run.chest_opened()
	Run.chest_opened()
	assert_float(_luck()).is_equal_approx(l0 + 0.02, 0.00001)
	# a level taken later: the banked 2% stays as it is
	assert_bool(Run.add_or_level_passive("jade_key")).is_true()
	assert_float(_luck()).is_equal_approx(l0 + 0.02, 0.00001)
	# only the chests after it bank the new value (+1.5%)
	Run.chest_opened()
	assert_float(_luck()).is_equal_approx(l0 + 0.035, 0.00001)
	# Evolved: +2% a chest
	assert_bool(Run.add_or_level_passive("jade_key")).is_true()
	assert_bool(Registry.passive("jade_key").is_evolved_rung(Run.passive_level("jade_key"))).is_true()
	Run.chest_opened()
	assert_float(_luck()).is_equal_approx(l0 + 0.055, 0.00001)
	var b: Dictionary = Run.chest_bank["jade_key"]
	assert_int(int(b["chests"])).is_equal(4)
	assert_float(float((b["stats"] as Dictionary)["luck"])).is_equal_approx(0.055, 0.00001)
	# a full rebuild keeps it (the bank is the run's, not the sheet's)
	Run.rebuild_sheets()
	assert_float(_luck()).is_equal_approx(l0 + 0.055, 0.00001)


func test_the_ruby_key_banks_attack_damage_that_reaches_the_weapons() -> void:
	_start()
	var m0 := _might()
	var w := Run.weapons[0] as WeaponInstance
	var d0 := w.stat("damage")
	Run.add_or_level_passive("ruby_key")
	for _k in range(3):
		Run.chest_opened()
	# +2% a chest, summed (never compounded): +6%
	assert_float(_might()).is_equal_approx(m0 * 1.06, 0.0001)
	assert_float(w.stat("damage")).is_equal_approx(d0 * 1.06, 0.01)
	Run.add_or_level_passive("ruby_key")
	assert_float(_might()).is_equal_approx(m0 * 1.06, 0.0001)
	Run.chest_opened()
	assert_float(_might()).is_equal_approx(m0 * 1.09, 0.0001)


func test_both_keys_bank_their_own_and_the_bank_resets_with_a_new_run() -> void:
	_start()
	Run.add_or_level_passive("jade_key")
	Run.add_or_level_passive("ruby_key")
	Run.chest_opened()
	assert_int(Run.chest_bank.size()).is_equal(2)
	# each key its own source on the pause Stats tab, named with its chests
	var rows: Array = StatSources.rows(Run.player_sheet, "luck")[StatSources.RUN]
	var mine := rows.filter(func(r: Dictionary) -> bool: return str(r["sid"]) == "chest:jade_key")
	assert_int(mine.size()).is_equal(1)
	assert_str(str(mine[0]["name"])).is_equal("Jade Key · 1 chest")
	assert_object(mine[0]["icon"]).is_same(Registry.passive("jade_key").icon)
	_start()
	assert_bool(Run.chest_bank.is_empty()).is_true()
	assert_float(_luck()).is_equal_approx(Run.hero_sheet(Run.character, 1).get_stat("luck", 0.0), 0.00001)


func test_the_keys_say_what_they_do() -> void:
	var jt := TextGen.passive_text(Registry.passive("jade_key"))
	assert_str(jt).contains("+1% luck")
	assert_str(jt).contains("only the chests after it")
	assert_str(TextGen.passive_text(Registry.passive("ruby_key"))).contains("+2% attack damage")
	# the upgrade card names the step per chest, never a raw stat id
	var nx := WItem.effect({"def": Registry.passive("jade_key"), "level_from": 1, "level_to": 2})
	assert_str(nx).contains("luck per chest opened")
	assert_bool(nx.contains("_")).is_false()


# ---------------------------------------------------------------- the Grindstone
# pass 119 (lane LEGEND_B): pass 118's grind of random bonuses (Run._grind, WeaponInstance.ground, its seeded dice) is
# gone; a Grindstone level raises the weakest weapon or evolves a ready one (pass119_LEGEND_B_test.gd pins it)


# ---------------------------------------------------------------- the heroes' own weapons in every pool

const HERO_WEAPONS := {"revolver": "drifter", "gravity_gun": "astro", "guitarra": "calavera", "sun_scepter": "solenne",
	"basketball": "fadeaway"}


## Pass 128: an outlaw's start weapon is offered only once he is owned (Registry.hero_may_use): the save of these tests
## owns every outlaw in HERO_WEAPONS (bought, his unlock quest done), so their weapons are guests as pass 118 pinned them.
func _own_weapon_outlaws() -> void:
	for wid: String in HERO_WEAPONS.keys():
		var oid := str(HERO_WEAPONS[wid])
		if not Save.heroes_owned().has(oid):
			Save.heroes_owned().append(oid)
		var oq := Registry.quest_for("character", oid)
		if oq and not Save.quest_done(oq.id):
			(Save.data["quests_done"] as Array).append(oq.id)


func test_any_hero_is_offered_another_heros_weapon_at_its_guest_weight() -> void:
	_own_weapon_outlaws()
	for hid in ["drifter", "astro", "ironwood", "may"]:
		_start(hid)
		var cands := CardPool.candidates()
		for wid: String in HERO_WEAPONS.keys():
			var w: WeaponDef = Registry.weapon(wid)
			if Run.weapon_instance(wid) != null:
				continue
			var c := cands.filter(func(x: Dictionary) -> bool: return str(x["id"]) == wid)
			assert_int(c.size()).override_failure_message("%s is not offered to %s" % [wid, hid]).is_equal(1)
			var plain := float(w.weight) * float(CardPool.RARITY_W[w.rarity]) * CardPool.luck_boost(w.rarity)
			var want := plain * (w.guest_weight if HERO_WEAPONS[wid] != hid else 1.0)
			assert_float(float(c[0]["weight"])).override_failure_message("%s for %s" % [wid, hid]).is_equal_approx(want, 0.0001)
		# the Stranger counts a guest at its share too
		var g := {"type": "weapon", "is_new": true, "def": Registry.weapon("revolver" if hid != "drifter" else "basketball")}
		assert_float(Run._stranger_share(g)).is_equal_approx(0.45, 0.0001)
	# the knob is data: each hero weapon's JSON
	for wid: String in HERO_WEAPONS.keys():
		assert_float(Registry.weapon(wid).guest_weight).is_equal_approx(0.45, 0.0001)
	# a hero still lands with his own
	assert_str(Registry.start_weapon_for(Registry.character("drifter")).id).is_equal("revolver")
	assert_str(Registry.start_weapon_for(Registry.character("astro")).id).is_equal("gravity_gun")


func test_the_card_says_whose_own_it_is_never_only() -> void:
	_start("astro")
	var t := CardPool.preview_weapon(Registry.weapon("revolver"), 1).description()
	assert_str(t).contains("Drifter's own.")
	assert_bool(t.contains(" only.")).is_false()


## The share of level-up offers that hold a weapon card (new or an upgrade), drawn `n` times on seeded dice, with the
## candidates as they are now (`guests`) or without another hero's own weapons (the rule before pass 118).
func _weapon_share(guests: bool, n: int, seed_: int) -> float:
	var cands := CardPool.candidates()
	if not guests:
		cands = cands.filter(func(c: Dictionary) -> bool:
			return not (str(c["type"]) == "weapon" and Registry.is_guest_weapon(c["def"])))
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	CardPool.rng = r
	var hit := 0
	for _k in range(n):
		var offer := CardPool._pick(cands, 3, {"weapon_new": 1, "perk": 1})
		if offer.any(func(c: Dictionary) -> bool: return str(c["type"]) == "weapon"):
			hit += 1
	CardPool.rng = null
	return float(hit) / float(n)


func test_the_weapon_card_share_rises_within_garrys_five_to_ten_percent() -> void:
	# a fresh save (the most a guest can add: fewer weapons unlocked), the run's first offers and a mid-run build
	# pass 128: with those outlaws owned (on a save that owns only the Drifter the Revolver is the one guest: +2.3%)
	_own_weapon_outlaws()
	var before := 0.0
	var after := 0.0
	for hid in ["drifter", "astro", "calavera", "fadeaway"]:
		_start(hid)
		before += _weapon_share(false, 6000, 11)
		after += _weapon_share(true, 6000, 11)
		Run.level_weapon(Run.weapons[0].def.id)
		Run.add_weapon(Registry.weapon("boomstick" if hid != "drifter" else "orbit_saws"), 2)
		Run.add_or_level_passive("brawn")
		Run.add_or_level_passive("cake")
		Run.perk_gap = 0
		before += _weapon_share(false, 6000, 12)
		after += _weapon_share(true, 6000, 12)
	var rel := after / before - 1.0
	print("pass118 weapon-card share: before %.1f%%, after %.1f%%, %+.1f%% relative" % [before * 12.5, after * 12.5, rel * 100.0])
	assert_float(rel).override_failure_message("the weapon-card share rose %.1f%%" % (rel * 100.0)).is_between(0.04, 0.105)


# ---------------------------------------------------------------- the Ghost Pepper

func test_beer_is_the_ghost_pepper() -> void:
	var p: PassiveDef = Registry.passive("beer")
	assert_str(p.display_name).is_equal("Ghost Pepper")
	assert_bool(p.flavour.to_lower().contains("beer")).is_false()
	assert_bool(p.flavour.to_lower().contains("liquid")).is_false()
	assert_str(TextGen.quest_item_name("beer")).is_equal("Ghost Pepper")
	# its numbers are Beer's: more attack damage, less health
	var e: Array = p.effects_at_level(1)
	assert_str((e[0] as Effect).stat).is_equal("might")
	assert_float((e[0] as Effect).value).is_equal_approx(0.15, 0.0001)
	assert_str((e[1] as Effect).stat).is_equal("max_hp")
	assert_object(p.evolved_icon).is_not_null()
	# "The Devil Risen" keeps its own id ghost_pepper and its own name
	assert_str(Registry.passive("ghost_pepper").display_name).is_not_equal("Ghost Pepper")
