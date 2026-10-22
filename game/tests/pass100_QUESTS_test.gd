## Pass 100, lane QUESTS (Garry: "I'd like to see more requirements that have to do with getting Player to reach a
## specific level with a hero, upgrading items passive/card/weapon to a certain level. Evolving an item, etc."): five
## build quests done in one run, read off the run's build (QuestTracker.run_progress / held_items): hero_level,
## item_level (a passive item by its rung), evolve_item, weapon_paths, items_maxed; each progresses and completes from
## Run's own calls, is worded by TextGen, reports its progress for the run record only while a run is on; seven kill
## quests and May's became build quests (the Sabre, Haste, Overkill, the Land Mine, Thirst, Ricochet, Fadeaway, May);
## a quest done on a save stays done whatever its condition becomes; every condition names things that exist and can be
## had (no chain dead-ends).
extends GdUnitTestSuite

const KILL_TYPES := ["kills_with_weapon", "kills_of_enemy", "kills_in_run_of_enemy", "kills_total"]
const BUILD_TYPES := ["hero_level", "item_level", "evolve_item", "weapon_paths", "items_maxed"]


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false


func after_test() -> void:
	Run.arena = false
	Run.end()


func _start(hero: String = "drifter") -> void:
	Run.start(Registry.character(hero), Registry.map("red_canyon"))


func _quest(cond: Dictionary) -> QuestDef:
	var q := QuestDef.new()
	q.id = "t_build"
	q.condition = cond
	q.unlocks = {"type": "mode", "id": "t_build"}
	return q


func _levels(n: int) -> void:
	var target := Run.level + n
	var guard := 0
	while Run.level < target and guard < 1000:
		Run.add_xp(Run.xp_to_next() - Run.xp + 0.01)
		guard += 1


# ---------------------------------------------------------------- the five types

func test_hero_level_counts_only_with_its_hero() -> void:
	var q := _quest({"type": "hero_level", "hero": "drifter", "level": 4})
	_start("drifter")
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(1, 4))
	_levels(3)
	assert_int(Run.level).is_equal(4)
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	# never outside a run's own check (the title's quiet one)
	assert_bool(QuestTracker._satisfied(q, false)).is_false()
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(4, 4))
	Run.end()
	# outside a run it has no progress (like reach_level): the drawer shows none
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i.ZERO)
	_start("astro")
	_levels(5)
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i.ZERO)
	assert_str(TextGen.quest_text(q)).is_equal("Reach level 4 with Drifter.")
	assert_int(QuestTracker.stage_hint(q)).is_equal(1)


func test_item_level_weapon_by_id_and_by_kind() -> void:
	var q := _quest({"type": "item_level", "kind": "weapon", "id": "orbit_saws", "level": 5})
	var any_w := _quest({"type": "item_level", "kind": "weapon", "level": 3})
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(0, 5))
	Run.add_weapon(Registry.weapon("orbit_saws"), 1)
	for i in range(3):
		Run.level_weapon("orbit_saws")
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(4, 5))
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	assert_bool(QuestTracker._satisfied(any_w, true)).is_true()
	Run.level_weapon("orbit_saws")
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	# its evolution counts the source at its top level: an evolution never undoes a level reached
	Run.evolve(Run.weapon_instance("orbit_saws"))
	assert_bool(Run.has_weapon("orbit_saws")).is_false()
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	assert_str(TextGen.quest_text(q)).is_equal("Get the Orbit Saws to level 5 in one run.")
	assert_str(TextGen.quest_text(any_w)).is_equal("Get a weapon to level 3 in one run.")


func test_item_level_card_and_its_risen_form() -> void:
	var q := _quest({"type": "item_level", "kind": "card", "level": 4})
	_start()
	# a passive item at level 4 is not a card
	for i in range(4):
		Run.add_or_level_passive("beer")
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	for i in range(3):
		Run.add_or_level_passive("mend")
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(3, 4))
	Run.add_or_level_passive("mend")
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	assert_bool(Run.evolve_passive("mend")).is_true()
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	assert_str(TextGen.quest_text(q)).is_equal("Get a card to level 4 in one run.")


func test_item_level_passive_item_by_rung() -> void:
	var q := _quest({"type": "item_level", "kind": "passive", "rung": "legendary"})
	var by_level := _quest({"type": "item_level", "id": "beer", "level": 3})
	_start()
	# a card never counts for a rung, however high
	for i in range(4):
		Run.add_or_level_passive("mend")
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	var gm: PassiveDef = Registry.passive("gas_mask")
	assert_str(gm.rarity).is_equal("epic")
	Run.add_or_level_passive("gas_mask")
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(QuestTracker.rung_rank("epic"), QuestTracker.rung_rank("legendary")))
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	Run.add_or_level_passive("gas_mask")
	assert_str(gm.rung_at(Run.passive_level("gas_mask"))).is_equal("legendary")
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	# `level` on a passive item is its level number
	Run.add_or_level_passive("beer")
	Run.add_or_level_passive("beer")
	assert_bool(QuestTracker._satisfied(by_level, true)).is_false()
	Run.add_or_level_passive("beer")
	assert_bool(QuestTracker._satisfied(by_level, true)).is_true()
	assert_str(TextGen.quest_text(q)).is_equal("Get a passive item to Legendary in one run.")
	assert_str(TextGen.quest_text(by_level)).is_equal("Get Beer to level 3 in one run.")
	assert_int(QuestTracker.stage_hint(q)).is_equal(1)
	q.condition["rung"] = "evolved"
	assert_int(QuestTracker.stage_hint(q)).is_equal(2)


func test_evolve_item_weapon_card_and_passive_item() -> void:
	var w := _quest({"type": "evolve_item", "id": "salt"})
	var c := _quest({"type": "evolve_item", "id": "mend"})
	var p := _quest({"type": "evolve_item", "id": "gas_mask"})
	var any_card := _quest({"type": "evolve_item", "kind": "card"})
	_start()
	var salt := Run.add_weapon(Registry.weapon("salt"), 5)
	assert_bool(QuestTracker._satisfied(w, true)).is_false()
	assert_object(QuestTracker.progress(w)).is_equal(Vector2i(0, 1))
	Run.evolve(salt)
	assert_bool(QuestTracker._satisfied(w, true)).is_true()
	# the evolved form's own id works too
	assert_bool(QuestTracker._satisfied(_quest({"type": "evolve_item", "id": "hiwa_kai"}), true)).is_true()
	for i in range(4):
		Run.add_or_level_passive("mend")
	assert_bool(QuestTracker._satisfied(c, true)).is_false()
	assert_bool(QuestTracker._satisfied(any_card, true)).is_false()
	# the Risen card comes as a level-up of the maxed card
	assert_bool(Run.add_or_level_passive("second_wind")).is_true()
	assert_bool(QuestTracker._satisfied(c, true)).is_true()
	assert_bool(QuestTracker._satisfied(any_card, true)).is_true()
	var gm: PassiveDef = Registry.passive("gas_mask")
	for i in range(gm.ladder_top() - 1):
		Run.add_or_level_passive("gas_mask")
	assert_bool(QuestTracker._satisfied(p, true)).is_false()
	Run.add_or_level_passive("gas_mask")
	assert_bool(gm.is_evolved_rung(Run.passive_level("gas_mask"))).is_true()
	assert_bool(QuestTracker._satisfied(p, true)).is_true()
	assert_str(TextGen.quest_text(w)).is_equal("Evolve the Salt into the %s." % Registry.weapon("hiwa_kai").display_name)
	assert_str(TextGen.quest_text(c)).is_equal("Evolve Temperance into Temperance Risen.")
	assert_str(TextGen.quest_text(p)).is_equal("Get Gas Mask to Evolved in one run.")
	assert_str(TextGen.quest_text(any_card)).is_equal("Evolve any card.")
	assert_int(QuestTracker.stage_hint(w)).is_equal(2)
	assert_int(QuestTracker.stage_hint(c)).is_equal(1)


func test_weapon_paths_named_and_any() -> void:
	var q := _quest({"type": "weapon_paths", "weapon": "revolver"})
	var any_q := _quest({"type": "weapon_paths"})
	_start("drifter")
	var path: Array = Registry.mutations_of("revolver")
	assert_int(path.size()).is_equal(3)
	Run.add_weapon(Registry.weapon("revolver"), 1)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(0, 3))
	for i in range(path.size()):
		assert_bool(QuestTracker._satisfied(q, true)).is_false()
		assert_bool(Run.add_mutation((path[i] as MutationDef).id, true)).is_true()
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(3, 3))
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	assert_bool(QuestTracker._satisfied(any_q, true)).is_true()
	assert_str(TextGen.quest_text(q)).is_equal("Take all 3 mutations of the Revolver in one run.")


func test_items_maxed_counts_what_is_held_at_its_top() -> void:
	var q := _quest({"type": "items_maxed", "kind": "weapon", "count": 2})
	var any_q := _quest({"type": "items_maxed", "kind": "any", "count": 3})
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 5)
	Run.add_weapon(Registry.weapon("salt"), 4)
	assert_object(QuestTracker.progress(q)).is_equal(Vector2i(1, 2))
	assert_bool(QuestTracker._satisfied(q, true)).is_false()
	# an evolved weapon counts as maxed
	Run.evolve(Run.weapon_instance("salt"))
	assert_bool(QuestTracker._satisfied(q, true)).is_true()
	assert_bool(QuestTracker._satisfied(any_q, true)).is_false()
	for i in range(4):
		Run.add_or_level_passive("mend")
	assert_bool(QuestTracker._satisfied(any_q, true)).is_true()
	assert_str(TextGen.quest_text(q)).is_equal("Hold 2 weapons at max level at once.")
	assert_str(TextGen.quest_text(any_q)).is_equal("Hold 3 items at max level at once.")
	assert_int(QuestTracker.stage_hint(q)).is_equal(1)
	assert_int(QuestTracker.stage_hint(any_q)).is_equal(2)


func test_a_build_quest_completes_through_the_runs_check() -> void:
	var q := _quest({"type": "item_level", "kind": "weapon", "id": "boomstick", "level": 2})
	Registry.quests[q.id] = q
	_start()
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	assert_array(QuestTracker.check_all(true)).not_contains([q.id])
	Run.level_weapon("boomstick")
	# the title's quiet check never completes an in-run quest
	assert_array(QuestTracker.check_all(false)).not_contains([q.id])
	assert_bool(Save.quest_done(q.id)).is_false()
	assert_array(QuestTracker.check_all(true)).contains([q.id])
	assert_bool(Save.quest_done(q.id)).is_true()
	# nothing done in the arena counts
	Registry.quests.erase(q.id)
	QuestTracker.just_completed.clear()


func test_the_run_record_carries_the_build_quests_progress() -> void:
	_start("drifter")
	var at_start := RunTimeline.quest_progress()
	# the Drifter's level quest (Fadeaway's) and the item quests are counted from the run's start
	assert_bool(at_start.has("unlock_fadeaway")).is_true()
	assert_bool(at_start.has("unlock_sabre")).is_true()
	assert_bool(at_start.has("unlock_may")).is_false()   # Calavera's level: not this run's hero
	_levels(2)
	assert_int(QuestTracker.progress(Registry.quests["unlock_fadeaway"]).x).is_equal(3)


# ---------------------------------------------------------------- the content

func test_a_completed_quest_stays_done_when_its_condition_changes() -> void:
	# Save keeps completion by quest id (quests_done): a save that finished the Sabre's old 40 Skeleton Knights keeps the
	# Sabre, whatever the condition reads now
	Save.mark_quest("unlock_sabre")
	var q: QuestDef = Registry.quests["unlock_sabre"]
	var was: Dictionary = q.condition.duplicate(true)
	q.condition = {"type": "kills_of_enemy", "enemy": "skeleton_knight", "count": 999999}
	assert_bool(Registry.is_unlocked("weapon", "sabre")).is_true()
	QuestTracker.check_all(false)
	assert_bool(Save.quest_done("unlock_sabre")).is_true()
	q.condition = was
	assert_bool(Registry.is_unlocked("weapon", "sabre")).is_true()
	# an old save's list loads as it is (nothing re-locks)
	var old := Save._default()
	old["quests_done"] = ["unlock_sabre", "unlock_fadeaway", "unlock_may", "unlock_thirst"]
	Save.data = old
	for id in old["quests_done"]:
		assert_bool(Save.quest_done(str(id))).is_true()
	assert_str(Registry.hero_state(Registry.character("fadeaway"))).is_equal("buyable")
	assert_bool(Registry.is_unlocked("passive", "thirst")).is_true()


func test_the_converted_quests_read_their_new_conditions() -> void:
	var want := {
		"unlock_sabre": "item_level", "unlock_haste": "item_level", "unlock_overkill": "item_level",
		"unlock_land_mine": "evolve_item", "unlock_thirst": "evolve_item", "unlock_ricochet": "weapon_paths",
		"unlock_fadeaway": "hero_level", "unlock_may": "hero_level",
	}
	for id: String in want.keys():
		var q: QuestDef = Registry.quests.get(id)
		assert_object(q).is_not_null()
		assert_str(str(q.condition.get("type", ""))).override_failure_message(id).is_equal(want[id])
		assert_str(TextGen.quest_text(q)).override_failure_message(id).is_not_equal("Complete a challenge.")
	# kill quests stay (Garry: "which is fine"), the mix is varied, and every build type is used by at least one unlock
	var kills := 0
	var builds := {}
	for q: QuestDef in Registry.quests.values():
		var t := str(q.condition.get("type", ""))
		if KILL_TYPES.has(t):
			kills += 1
		if BUILD_TYPES.has(t):
			builds[t] = true
	assert_int(kills).is_between(4, 9)
	assert_int(builds.size()).is_greater_equal(4)


func test_every_condition_names_things_that_exist() -> void:
	var map: MapDef = Registry.map("red_canyon")
	for q: QuestDef in Registry.quests.values():
		var c := q.condition
		var t := str(c.get("type", ""))
		var msg := "%s (%s)" % [q.id, t]
		if c.has("hero"):
			var h: CharacterDef = Registry.character(str(c["hero"]))
			assert_object(h).override_failure_message(msg).is_not_null()
			assert_bool(h.hidden).override_failure_message(msg + ": a hidden hero").is_false()
		if c.has("weapon"):
			var w: WeaponDef = Registry.weapon(str(c["weapon"]))
			assert_object(w).override_failure_message(msg).is_not_null()
			assert_bool(Registry.is_hidden(w) and Registry.quest_visible(q)).override_failure_message(msg + ": a hidden weapon").is_false()
		if str(c.get("id", "")) != "":
			var kind := QuestTracker.item_kind_of(str(c["id"]), "")
			assert_str(kind).override_failure_message(msg + ": no such item").is_not_empty()
			var d: ContentDef = Registry.passive(str(c["id"]))
			if kind == "weapon":
				d = Registry.weapon(str(c["id"]))
			assert_bool(Registry.is_hidden(d)).override_failure_message(msg + ": a hidden item").is_false()
			if str(c.get("kind", "any")) != "any":
				assert_str(kind).override_failure_message(msg + ": kind").is_equal(str(c["kind"]))
		if c.has("enemy"):
			assert_float(QuestTracker.first_arrival(map.timeline, str(c["enemy"]))).override_failure_message(msg + ": never comes").is_greater_equal(0.0)
		if c.has("rung"):
			assert_int(QuestTracker.rung_rank(str(c["rung"]))).override_failure_message(msg).is_greater(1)
		if t == "weapon_paths" and str(c.get("weapon", "")) != "":
			assert_int(Registry.mutations_of(str(c["weapon"])).size()).override_failure_message(msg).is_greater(0)


## No chain dead-ends: starting from what a new save has (the free heroes and the ones sold for gold alone, every item no
## quest locks), completing what can be completed must reach every quest in play. A quest whose condition names a hero,
## an item or a weapon waits for it; a weapon that is one hero's own waits for that hero.
func test_no_quest_waits_on_something_it_can_never_have() -> void:
	var have := {}
	for c: CharacterDef in Registry.characters.values():
		if not c.hidden and Registry.quest_for("character", c.id) == null:
			have["hero:" + c.id] = true
	for w: WeaponDef in Registry.weapons.values():
		if Registry.quest_for("weapon", w.id) == null:
			have["item:" + w.id] = true
	for p: PassiveDef in Registry.passives.values():
		if Registry.quest_for("passive", p.id) == null:
			have["item:" + p.id] = true
	var open: Array = Registry.quests.values().filter(func(q: QuestDef) -> bool: return Registry.quest_visible(q))
	var progress := true
	while progress:
		progress = false
		for q: QuestDef in open.duplicate():
			if _needs_met(q, have):
				open.erase(q)
				var u := str(q.unlocks.get("id", ""))
				have[("hero:" if str(q.unlocks.get("type", "")) == "character" else "item:") + u] = true
				# an item's evolutions come with it
				var w: WeaponDef = Registry.weapon(u)
				if w and w.evolves_into != "":
					have["item:" + w.evolves_into] = true
				progress = true
	var left: Array = open.map(func(q: QuestDef) -> String: return q.id)
	# Mira's quest (hidden) and Dad's (hidden) are out of play; nothing else may be left
	assert_array(left).is_empty()


func _needs_met(q: QuestDef, have: Dictionary) -> bool:
	var c := q.condition
	if c.has("hero") and not have.has("hero:" + str(c["hero"])):
		return false
	for key in ["weapon", "id"]:
		var id := str(c.get(key, ""))
		if id == "":
			continue
		if not have.has("item:" + id):
			# an evolved form's id: its source
			var w: WeaponDef = Registry.weapon(id)
			var p: PassiveDef = Registry.passive(id)
			var src := w.evolved_from if w and w.is_evolution else (p.evolves_from if p else "")
			if src == "" or not have.has("item:" + src):
				return false
		var wd: WeaponDef = Registry.weapon(id)
		if wd and wd.hero != "" and not have.has("hero:" + wd.hero):
			return false
	return true


func test_the_quest_locked_band_and_stage_spread_still_hold() -> void:
	# pass44_test's band (re-run here on today's quests): the share locked and the 1 / 2 / 3 stage spread
	var items: Array = []
	for w in Registry.base_weapons():
		if not Registry.is_hidden(w):
			items.append(w)
	for p in Registry.base_passives():
		items.append(p)
	var locked: Array = []
	for d in items:
		var q := Registry.quest_for("weapon" if d is WeaponDef else "passive", d.id)
		if q:
			locked.append(q)
	assert_float(float(locked.size()) / float(items.size())).is_between(0.28, 0.56)
	var by_stage := {1: 0, 2: 0, 3: 0}
	for q in locked:
		by_stage[clampi(QuestTracker.stage_hint(q), 1, 3)] += 1
	assert_float(float(by_stage[1]) / float(locked.size())).is_between(0.48, 0.66)
	assert_float(float(by_stage[2]) / float(locked.size())).is_between(0.30, 0.48)
	assert_int(by_stage[3]).is_between(1, 2)
