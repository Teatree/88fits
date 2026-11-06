## Pass 129, lane TRAILCORE (Garry's brief and answers of 2026-11-06, docs/trail_schema.md): the Trail's rules and
## hooks, on fixtures under tests/fixtures/ (never the game's own nodes): every rule (a choice closes its sibling and
## what hangs under it, `any` and `all` links, optional nodes, the level gate), prices, buying and the purse, each kind
## of gate and the hook that asks it, a gift the save already has, the effects summed per type and seen in
## Run.hero_sheet, the three new stats (start_gold, totem_boost, boss_purse) doing their one thing, check's warnings,
## the migration on a test save, and that a Trail without nodes changes nothing.
extends GdUnitTestSuite

const RULES := "res://tests/fixtures/trail_rules.json"
const GATES := "res://tests/fixtures/trail_gates.json"
const EMPTY := "res://tests/fixtures/trail_empty.json"
const BAD := "res://tests/fixtures/trail_bad.json"
const StagesScreenScript := preload("res://ui/StagesScreen.gd")
const TotemBoonsScript := preload("res://core/systems/TotemBoons.gd")

var _keep_quests: Dictionary = {}


func before_test() -> void:
	Save.data = Save._default()
	Save._dirty = false
	Run.arena = false
	_keep_quests = Registry.quests.duplicate()
	Trail.load_from(RULES)


func after_test() -> void:
	Run.end()
	Run.arena = false
	Registry.quests = _keep_quests
	Save.data = Save._default()
	Save._dirty = false
	Trail.load_from()


func _rich(n: int = 100000) -> void:
	Save.data["gold"] = n


## Buys the nodes in order, each one asserted.
func _buy(ids: Array) -> void:
	for id: String in ids:
		assert_bool(Trail.buy(id)).override_failure_message("could not buy %s (%s)" % [id, Trail.state(id)]).is_true()


func _states(ids: Array) -> Array:
	var out: Array = []
	for id: String in ids:
		out.append(Trail.state(id))
	return out


func _effect(type: String, stat: String) -> Effect:
	for te: Dictionary in Trail.effects():
		if str(te["type"]) == type:
			for e: Effect in te["effects"]:
				if e.stat == stat:
					return e
	return null


# ---------------------------------------------------------------- an empty Trail

func test_a_trail_without_nodes_changes_nothing() -> void:
	Trail.load_from(EMPTY)
	Save.data["gold"] = 5000
	assert_bool(Trail.has_nodes()).is_false()
	assert_int(Trail.levels()).is_equal(0)
	assert_int(Trail.level()).is_equal(0)
	assert_array(Trail.effects()).is_empty()
	assert_bool(Trail.any_affordable()).is_false()
	assert_bool(Trail.buy("n1")).is_false()
	assert_str(Trail.state("n1")).is_equal("locked")
	# no gate: everything answers as its own rule does
	for type: String in Trail.GIFTS:
		assert_bool(Trail.gated(type, "anything")).is_false()
		assert_bool(Trail.has(type, "anything")).is_true()
		assert_int(Trail.level_for(type, "anything")).is_equal(0)
		assert_str(Trail.requirement_text(type, "anything")).is_empty()
	for w: WeaponDef in Registry.base_weapons():
		var q := Registry.quest_for("weapon", w.id)
		assert_bool(Registry.is_unlocked("weapon", w.id)).is_equal(q == null or Save.quest_done(q.id))
	for p: PassiveDef in Registry.passives.values():
		var q := Registry.quest_for("passive", p.id)
		assert_bool(Registry.is_unlocked("passive", p.id)).is_equal(q == null or Save.quest_done(q.id))
	# lane TRAIL-SETUP (re-pinned): Calavera's quest retired with his node; without a Trail he is on sale by the old rule
	var cal: CharacterDef = Registry.character("calavera")
	assert_str(Registry.hero_state(cal)).is_equal("buyable")
	assert_str(Registry.hero_state(Registry.character("drifter"))).is_equal("owned")
	assert_bool(Save.stage_unlocked("red_canyon", 0)).is_true()
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_false()
	Save.mark_stage_beaten("red_canyon", 0)
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_true()
	var pole: StructureDef = Registry.structure("totem_pole")
	assert_array(StructureManager.in_play([pole])).contains_exactly([pole])
	var roster: Array = [{"id": "heart", "weight": 6}, {"id": "rage", "weight": 3}]
	assert_bool(is_same(Trail.rows_open("powerup", roster), roster)).is_true()
	assert_bool(WantedBoard.unlocked()).is_false()
	Save.add_total("runs", 2)
	assert_bool(WantedBoard.unlocked()).is_true()
	# the sheet has no source of the Trail's, the purse starts empty
	var sheet := Run.hero_sheet(Registry.character("drifter"), 1)
	for en in sheet.entries:
		assert_bool(str(en["sid"]).begins_with("trail:")).is_false()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	assert_int(Run.run_gold).is_equal(0)
	# and the migration waits: nothing refunded, nothing flagged, the old board's keys still in the save
	Save.data["talent_spent"] = 900
	assert_int(Save._migrate_trail()).is_equal(0)
	assert_bool(Save.once(Trail.ONCE)).is_false()
	assert_int(int(Save.data["talent_spent"])).is_equal(900)


# ---------------------------------------------------------------- the file and the prices

func test_the_file_reads_into_nodes_levels_groups_and_sections() -> void:
	assert_bool(Trail.has_nodes()).is_true()
	assert_int(Trail.nodes().size()).is_equal(13)
	assert_int(Trail.levels()).is_equal(6)
	assert_str(str(Trail.node("n2a")["kind"])).is_equal("choice")
	assert_dict(Trail.node("nope")).is_empty()
	assert_array(Trail.group("n2a")).contains_exactly(["n2a", "n2b"])
	assert_array(Trail.group("n1")).is_empty()
	assert_int(Trail.nodes_on(3).size()).is_equal(3)
	assert_str(Trail.currency()).is_equal("gold")
	assert_str(Trail.end_text()).is_equal("To be continued")
	assert_int(Trail.sections().size()).is_equal(2)
	assert_str(str(Trail.section_at(3)["name"])).is_equal("First")
	assert_str(str(Trail.section_at(4)["name"])).is_equal("Second")
	assert_str(str(Trail.upgrade("might")["name"])).is_equal("Might")
	assert_dict(Trail.upgrade("nope")).is_empty()
	assert_str(Trail.icon_path("might")).is_equal("res://art/ui/trail/might.png")
	# a node without `from` hangs on the required nodes of the level below
	assert_array(Trail.from_of("n2a")).contains_exactly(["n1"])
	assert_array(Trail.from_of("n3a")).contains_exactly(["n2a"])
	assert_array(Trail.from_of("n6")).contains_exactly(["n5", "n5x"])


func test_prices_follow_the_curve_an_own_price_and_a_multiplier() -> void:
	# round_to(40 + 1.5 * level ^ 2, 10): 41.5, 46, 53.5, 64, 77.5, 94
	assert_int(Trail.price("n1")).is_equal(40)
	assert_int(Trail.price("n2a")).is_equal(50)
	assert_int(Trail.price("n3a")).is_equal(50)
	assert_int(Trail.price("n4")).is_equal(60)
	assert_int(Trail.price("n6")).is_equal(90)
	# a multiplier on the curve, an own price over it
	assert_int(Trail.price("n5")).is_equal(160)
	assert_int(Trail.price("n3o")).is_equal(500)
	assert_int(Trail.price("nope")).is_equal(0)
	assert_int(Trail.price_at({"base": 0, "k": 1, "power": 3, "round": 0}, 4)).is_equal(64)
	assert_int(Trail.price_at({}, 100)).is_equal(15040)
	assert_int(Trail.price_at({"base": 40, "k": 1.5, "power": 2.0, "round": 10}, 5, 1.25)).is_equal(100)


# ---------------------------------------------------------------- the rules

func test_a_new_save_opens_level_one_only() -> void:
	assert_int(Trail.level()).is_equal(0)
	assert_str(Trail.state("n1")).is_equal("open")
	assert_array(_states(["n2a", "n2b", "n2o", "n3a", "n3b", "n3o", "n4", "n5", "n6"])).contains_exactly(
		["locked", "locked", "locked", "locked", "locked", "locked", "locked", "locked", "locked"])
	assert_bool(Trail.level_done(1)).is_false()
	assert_bool(Trail.level_done(7)).is_false()
	# open is not affordable: an empty purse buys nothing
	assert_bool(Trail.can_buy("n1")).is_false()
	assert_bool(Trail.any_affordable()).is_false()
	assert_bool(Trail.buy("n1")).is_false()
	assert_array(Save.trail_bought()).is_empty()


func test_buying_pays_records_and_raises_the_level() -> void:
	_rich(1000)
	assert_bool(Trail.can_buy("n1")).is_true()
	assert_bool(Trail.any_affordable()).is_true()
	assert_bool(Trail.buy("n1")).is_true()
	assert_int(Save.gold()).is_equal(960)
	assert_array(Save.trail_bought()).contains_exactly(["n1"])
	assert_int(Save.trail_spent()).is_equal(40)
	assert_str(Trail.state("n1")).is_equal("bought")
	assert_bool(Trail.level_done(1)).is_true()
	assert_int(Trail.level()).is_equal(1)
	# bought once only; a locked node and an unknown one are refused, nothing paid
	assert_bool(Trail.buy("n1")).is_false()
	assert_bool(Trail.buy("n3a")).is_false()
	assert_bool(Trail.buy("nope")).is_false()
	assert_int(Save.gold()).is_equal(960)
	# the whole of one side: 40 + 50 + 50 + 60 + 160 + 90
	_buy(["n2a", "n3a", "n4", "n5", "n6"])
	assert_int(Save.gold()).is_equal(1000 - 450)
	assert_int(Save.trail_spent()).is_equal(450)
	assert_int(Trail.level()).is_equal(6)
	assert_int(Trail.level()).is_equal(Trail.levels())


func test_a_short_purse_buys_nothing() -> void:
	_rich(39)
	assert_str(Trail.state("n1")).is_equal("open")
	assert_bool(Trail.can_buy("n1")).is_false()
	assert_bool(Trail.buy("n1")).is_false()
	assert_int(Save.gold()).is_equal(39)
	assert_array(Save.trail_bought()).is_empty()
	_rich(40)
	assert_bool(Trail.any_affordable()).is_true()
	assert_bool(Trail.buy("n1")).is_true()
	assert_int(Save.gold()).is_equal(0)
	assert_bool(Trail.any_affordable()).is_false()


func test_a_choice_closes_its_sibling_and_what_hangs_under_it() -> void:
	_rich()
	_buy(["n1"])
	assert_array(_states(["n2a", "n2b", "n2o"])).contains_exactly(["open", "open", "locked"])
	_buy(["n2a"])
	# the sibling, for good; what hangs under it (n3b, then n4x and n5x that need it); the any-link whose every side is closed
	assert_array(_states(["n2b", "n3b", "n4x", "n5x", "n4y"])).contains_exactly(["closed", "closed", "closed", "closed", "closed"])
	assert_bool(Trail.buy("n2b")).is_false()
	assert_bool(Trail.can_buy("n2b")).is_false()
	# the chosen side goes on: its own node open, the level done with the closed ones left out
	assert_array(_states(["n2o", "n3a", "n3o"])).contains_exactly(["open", "open", "open"])
	assert_bool(Trail.level_done(2)).is_true()
	assert_int(Trail.level()).is_equal(2)
	_buy(["n3a"])
	assert_int(Trail.level()).is_equal(3)
	# a level whose other node is closed is done by the one that is left
	_buy(["n4"])
	assert_bool(Trail.level_done(4)).is_true()
	# a rail is drawn from the chosen one only
	assert_array(Trail.from_of("n5")).contains_exactly(["n4"])


func test_the_other_side_of_the_choice_mirrors_it() -> void:
	_rich()
	_buy(["n1", "n2b"])
	assert_array(_states(["n2a", "n2o", "n3a", "n5x"])).contains_exactly(["closed", "closed", "closed", "closed"])
	assert_array(_states(["n3b", "n4", "n4x", "n4y"])).contains_exactly(["open", "locked", "locked", "locked"])
	_buy(["n3b"])
	# `any`: one of the two it names is enough (the other is closed); `all` of one: that one
	assert_array(_states(["n4", "n4x", "n4y"])).contains_exactly(["open", "open", "open"])
	# level 4 now needs both of its required nodes
	_buy(["n4"])
	assert_bool(Trail.level_done(4)).is_false()
	assert_str(Trail.state("n5")).is_equal("locked")
	_buy(["n4x"])
	assert_bool(Trail.level_done(4)).is_true()
	assert_str(Trail.state("n5")).is_equal("open")


func test_the_level_gate_holds_a_node_whose_links_are_met() -> void:
	_rich()
	_buy(["n1", "n2a"])
	# n5 names no `from` and n3o is optional: both wait for the level under them, nothing else
	assert_str(Trail.state("n5")).is_equal("locked")
	assert_str(Trail.state("n4")).is_equal("locked")
	_buy(["n3a"])
	assert_str(Trail.state("n4")).is_equal("open")
	assert_str(Trail.state("n5")).is_equal("locked")
	_buy(["n4"])
	assert_str(Trail.state("n5")).is_equal("open")
	assert_str(Trail.state("n6")).is_equal("locked")


func test_optional_nodes_never_hold_a_level_and_stay_open_on_done_levels() -> void:
	_rich()
	_buy(["n1", "n2a", "n3a", "n4", "n5", "n6"])
	assert_int(Trail.level()).is_equal(6)
	# skipped all the way up, still open
	assert_array(_states(["n2o", "n3o"])).contains_exactly(["open", "open"])
	_buy(["n3o", "n2o"])
	assert_array(_states(["n2o", "n3o"])).contains_exactly(["bought", "bought"])
	assert_int(Save.trail_spent()).is_equal(450 + 500 + 50)
	# an optional node hangs beside the node it names: locked until that one is bought
	Save.data = Save._default()
	_rich()
	_buy(["n1"])
	assert_str(Trail.state("n2o")).is_equal("locked")


func test_the_states_follow_the_save_without_a_buy() -> void:
	_rich()
	_buy(["n1"])
	assert_int(Trail.level()).is_equal(1)
	# a list that grew is seen at once; one edited in place needs refresh()
	(Save.trail_bought() as Array).append("n2b")
	assert_str(Trail.state("n2a")).is_equal("closed")
	(Save.trail_bought() as Array)[1] = "n2a"
	Trail.refresh()
	assert_str(Trail.state("n2b")).is_equal("closed")
	assert_str(Trail.state("n2a")).is_equal("bought")
	# a wipe (the save's data replaced) is seen too
	Save.data = Save._default()
	assert_int(Trail.level()).is_equal(0)
	assert_str(Trail.state("n1")).is_equal("open")


# ---------------------------------------------------------------- the gates and their hooks

func test_every_kind_of_gate_locks_until_its_node_is_bought() -> void:
	Trail.load_from(GATES)
	_rich()
	var gates := [["outlaw", "calavera", "g_outlaw", 1], ["skin", "drifter:DRI-B", "g_skin", 1], ["weapon", "hammer", "g_weapon", 1],
		["weapon", "molotov", "g_free", 1], ["passive", "deadeye", "g_passive", 2], ["stage", "red_canyon:s2", "g_stage", 2],
		["map", "red_canyon", "g_map", 2], ["structure", "totem_pole", "g_structure", 3], ["powerup", "rage", "g_powerup", 3],
		["feature", "wanted", "g_feature", 3]]
	for g: Array in gates:
		var type := str(g[0])
		var id := str(g[1])
		assert_bool(Trail.gated(type, id)).override_failure_message(type).is_true()
		assert_bool(Trail.has(type, id)).override_failure_message(type).is_false()
		assert_str(str(Trail.gate(type, id)["id"])).is_equal(str(g[2]))
		assert_int(Trail.level_for(type, id)).is_equal(int(g[3]))
		assert_str(Trail.requirement_text(type, id)).is_equal("Reach Trail Level %d" % int(g[3]))
	# a thing no node names keeps its own rule
	assert_bool(Trail.gated("weapon", "sabre")).is_false()
	assert_bool(Trail.has("weapon", "sabre")).is_true()
	assert_dict(Trail.gate("weapon", "sabre")).is_empty()
	for g: Array in gates:
		assert_bool(Trail.buy(str(g[2]))).override_failure_message(str(g[2])).is_true()
		assert_bool(Trail.has(str(g[0]), str(g[1]))).override_failure_message(str(g[0])).is_true()
	assert_int(Trail.level()).is_equal(3)


func test_an_outlaw_a_node_gives_is_locked_then_owned_without_a_second_payment() -> void:
	Trail.load_from(GATES)
	var cal: CharacterDef = Registry.character("calavera")
	# his quest done would make him buyable by the old rule: the Trail's answer comes first
	Save.mark_quest("unlock_calavera")
	assert_str(Registry.hero_state(cal)).is_equal("locked")
	assert_bool(Registry.hero_owned(cal)).is_false()
	assert_str(Registry.hero_requirement_text(cal)).is_equal("Reach Trail Level 1")
	assert_bool(Save.buy_hero(cal)).is_false()
	_rich(1000)
	_buy(["g_outlaw"])
	assert_str(Registry.hero_state(cal)).is_equal("owned")
	assert_bool(Registry.hero_owned(cal)).is_true()
	assert_int(Save.gold()).is_equal(1000 - Trail.price("g_outlaw"))
	# an outlaw no node names keeps his rule
	assert_str(Registry.hero_state(Registry.character("drifter"))).is_equal("owned")
	assert_str(Registry.hero_state(Registry.character("astro"))).is_equal("buyable")


func test_items_maps_and_skins_ask_the_trail_first() -> void:
	Trail.load_from(GATES)
	# a weapon with a quest: the quest done is not enough; one that was free: locked too
	Save.mark_quest("unlock_hammer")
	assert_bool(Registry.is_unlocked("weapon", "hammer")).is_false()
	assert_bool(Registry.is_unlocked("weapon", "molotov")).is_false()
	assert_bool(Registry.unlocked_weapons().any(func(w: WeaponDef) -> bool: return w.id == "hammer" or w.id == "molotov")).is_false()
	assert_bool(Registry.is_unlocked("passive", "deadeye")).is_false()
	assert_bool(Registry.unlocked_passives().any(func(p: PassiveDef) -> bool: return p.id == "deadeye")).is_false()
	assert_bool(Registry.is_unlocked("map", "red_canyon")).is_false()
	# things no node names: as before
	assert_bool(Registry.is_unlocked("weapon", "revolver")).is_true()
	assert_bool(Registry.is_unlocked("weapon", "sabre")).is_false()
	# a quest whose thing a node gives is neither shown nor tracked
	assert_bool(Registry.quest_visible(Registry.quests["unlock_hammer"])).is_false()
	assert_bool(Registry.quest_visible(Registry.quests["unlock_deadeye"])).is_false()   # lane TRAIL-SETUP: unlock_calavera retired with his node
	assert_bool(Registry.quest_visible(Registry.quests["unlock_sabre"])).is_true()
	var dri: CharacterDef = Registry.character("drifter")
	assert_str(Registry.skin_state(dri, "DRI-B")).is_equal("locked")
	assert_str(Registry.skin_requirement_text(dri, "DRI-B")).is_equal("Reach Trail Level 1")
	assert_str(Registry.skin_state(dri, "DRI-C")).is_equal("locked")
	assert_bool(Registry.skin_requirement_text(dri, "DRI-C").begins_with("Reach Trail")).is_false()
	_rich()
	_buy(["g_outlaw", "g_skin", "g_weapon", "g_free", "g_passive", "g_stage", "g_map"])
	assert_bool(Registry.is_unlocked("weapon", "hammer")).is_true()
	assert_bool(Registry.is_unlocked("weapon", "molotov")).is_true()
	assert_bool(Registry.is_unlocked("passive", "deadeye")).is_true()
	assert_bool(Registry.is_unlocked("map", "red_canyon")).is_true()
	assert_str(Registry.skin_state(dri, "DRI-B")).is_equal("owned")
	assert_bool(Registry.unlocked_weapons().any(func(w: WeaponDef) -> bool: return w.id == "molotov")).is_true()


func test_a_stage_needs_the_boss_before_it_and_its_node() -> void:
	Trail.load_from(GATES)
	var m := Registry.map("red_canyon")
	var list: Array = StagesScreenScript.entries(m)
	assert_str(Trail.stage_key("red_canyon", 1)).is_equal("red_canyon:s2")
	assert_int(Trail.stage_index("red_canyon", "s2")).is_equal(1)
	# the first stage and an unnamed one keep their rule
	assert_bool(Save.stage_unlocked("red_canyon", 0)).is_true()
	assert_bool(Trail.stage_open("red_canyon", 2)).is_true()
	# neither met: the old line; the boss beaten, the node missing: the Trail's line
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_false()
	assert_bool(StagesScreenScript.requirement(m, list, 1).begins_with("Beat ")).is_true()
	Save.mark_stage_beaten("red_canyon", 0)
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_false()
	assert_str(StagesScreenScript.requirement(m, list, 1)).is_equal("Reach Trail Level 2")
	assert_str(StagesScreenScript.requirement(m, list, 0)).is_empty()
	assert_bool(StagesScreenScript.requirement(m, list, 2).begins_with("Beat ")).is_true()
	# the node bought, the boss not beaten: still locked, by the old rule
	Save.forget_stages()
	_rich()
	_buy(["g_outlaw", "g_skin", "g_weapon", "g_free", "g_stage"])
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_false()
	assert_bool(StagesScreenScript.requirement(m, list, 1).begins_with("Beat ")).is_true()
	Save.mark_stage_beaten("red_canyon", 0)
	assert_bool(Save.stage_unlocked("red_canyon", 1)).is_true()


func test_structures_power_ups_and_the_bounty_board_wait_for_their_nodes() -> void:
	Trail.load_from(GATES)
	var pole: StructureDef = Registry.structure("totem_pole")
	var shop: StructureDef = Registry.structure("shop")
	assert_array(StructureManager.in_play([pole, shop])).contains_exactly([shop])
	var roster: Array = [{"id": "heart", "weight": 6}, {"id": "rage", "weight": 3}, {"id": "sprint", "weight": 3}]
	var rows: Array = Trail.rows_open("powerup", roster)
	assert_array(rows.map(func(r: Dictionary) -> String: return str(r["id"]))).contains_exactly(["heart", "sprint"])
	assert_int(roster.size()).is_equal(3)
	# the barrels' weight lists are rows too
	assert_array(Trail.rows_open("powerup", BarrelSpawns.weight_list({"rage": 2.0}))).is_empty()
	Save.add_total("runs", 5)
	assert_bool(WantedBoard.unlocked()).is_false()
	_rich()
	_buy(["g_outlaw", "g_skin", "g_weapon", "g_free", "g_passive", "g_stage", "g_map", "g_structure", "g_powerup", "g_feature"])
	assert_array(StructureManager.in_play([pole, shop])).contains_exactly([pole, shop])
	assert_bool(is_same(Trail.rows_open("powerup", roster), roster)).is_false()
	assert_int(Trail.rows_open("powerup", roster).size()).is_equal(3)
	assert_bool(WantedBoard.unlocked()).is_true()
	# the board's own switch still turns it off
	assert_bool(WantedBoard.unlocked({"enabled": false})).is_false()


func test_a_gift_the_save_already_has_counts_as_bought_at_no_cost() -> void:
	Trail.load_from(GATES)
	_rich(1000)
	# an outlaw owned, a skin owned, and what the save kept from before the Trail
	Save.heroes_owned().append("calavera")
	Save.skins_owned().append("drifter:DRI-B")
	Save.trail_had().append("weapon:hammer")
	Save.trail_had().append("stage:red_canyon:s2")
	assert_array(_states(["g_outlaw", "g_skin", "g_weapon", "g_stage"])).contains_exactly(["bought", "bought", "bought", "bought"])
	assert_bool(Trail.has("outlaw", "calavera")).is_true()
	assert_bool(Trail.has("weapon", "hammer")).is_true()
	assert_bool(Registry.is_unlocked("weapon", "hammer")).is_true()
	assert_str(Registry.hero_state(Registry.character("calavera"))).is_equal("owned")
	assert_bool(Trail.buy("g_outlaw")).is_false()
	assert_int(Save.gold()).is_equal(1000)
	assert_array(Save.trail_bought()).is_empty()
	# they count for the level: one more node and level 1 is done
	assert_int(Trail.level()).is_equal(0)
	_buy(["g_free"])
	assert_int(Trail.level()).is_equal(1)
	assert_int(Save.trail_spent()).is_equal(40)


# ---------------------------------------------------------------- the effects and the three new stats

func test_bought_upgrades_add_up_per_type_and_reach_the_hero_sheet() -> void:
	var dri: CharacterDef = Registry.character("drifter")
	var before := Run.hero_sheet(dri, 1)
	assert_array(Trail.effects()).is_empty()
	_rich()
	_buy(["n1", "n2a", "n2o", "n3a", "n3o"])
	# one entry per type, in the file's order; two might nodes are one effect
	var types: Array = Trail.effects().map(func(te: Dictionary) -> String: return str(te["type"]))
	assert_array(types).contains_exactly(["might", "regen", "grubstake", "stakes"])
	var might: Dictionary = Trail.effects()[0]
	assert_str(str(might["name"])).is_equal("The Trail: Might")
	assert_str(str(might["source"])).is_equal("trail:might")
	assert_int((might["effects"] as Array).size()).is_equal(1)
	var e := _effect("might", "might")
	assert_str(e.op).is_equal("mul")
	assert_str(e.target).is_equal("player")
	assert_float(e.value).is_equal_approx(0.08, 0.00001)
	assert_float(Trail.total("might")).is_equal_approx(0.08, 0.00001)
	# `per` scales each stat of a type: Stakes 10% is HP and attack +10%, speed +4%, bounty +5%
	assert_float(_effect("stakes", "danger_hp").value).is_equal_approx(0.1, 0.00001)
	assert_float(_effect("stakes", "danger_speed").value).is_equal_approx(0.04, 0.00001)
	assert_float(_effect("stakes", "danger_bounty").value).is_equal_approx(0.05, 0.00001)
	var sheet := Run.hero_sheet(dri, 1)
	assert_float(sheet.get_stat("might", 1.0) / before.get_stat("might", 1.0)).is_equal_approx(1.08, 0.00001)
	assert_float(sheet.get_stat("regen", 0.0) - before.get_stat("regen", 0.0)).is_equal_approx(0.5, 0.00001)
	assert_float(sheet.get_stat("start_gold", 0.0)).is_equal_approx(25.0, 0.00001)
	assert_float(sheet.get_stat("danger_hp", 0.0)).is_equal_approx(0.1, 0.00001)
	# its own source on the sheet, named for the pause screen
	var sids: Array = sheet.entries.map(func(en: Dictionary) -> String: return str(en["sid"]))
	assert_bool(sids.has("trail:might") and sids.has("trail:stakes")).is_true()
	var row := StatSources.describe_source("trail:might", "x")
	assert_str(str(row["name"])).is_equal("The Trail: Might")
	assert_str(str(row["kind"])).is_equal("trail")
	assert_bool(StatSources.START_KINDS.has("trail")).is_true()
	# a negative `per`: Tempo cuts the cooldown
	Save.data = Save._default()
	_rich()
	_buy(["n1", "n2b"])
	assert_float(_effect("tempo", "cooldown").value).is_equal_approx(-0.04, 0.00001)
	assert_float(Run.hero_sheet(dri, 1).get_stat("cooldown", 1.0) / before.get_stat("cooldown", 1.0)).is_equal_approx(0.96, 0.00001)


func test_start_gold_is_in_the_purse_as_a_run_starts() -> void:
	var dri: CharacterDef = Registry.character("drifter")
	var earned := Save.total("gold_earned")
	Run.start(dri, Registry.map("red_canyon"))
	assert_int(Run.run_gold).is_equal(0)
	Run.end()
	_rich()
	_buy(["n1", "n2a", "n3a"])
	Run.start(dri, Registry.map("red_canyon"))
	assert_int(Run.run_gold).is_equal(25)
	# a stage's fresh run keeps it; it is not gold earned
	Run.start_stage(1)
	assert_int(Run.run_gold).is_equal(25)
	assert_int(Save.total("gold_earned")).is_equal(earned)
	assert_bool(RunAnalytics.GOLD_SOURCES.has("start_gold")).is_true()
	assert_bool(StatSheet.PLAYER_DEFAULTS.has("start_gold")).is_true()
	assert_bool(TextGen.STATS.has("start_gold")).is_true()


func test_totem_boost_grows_every_gift() -> void:
	var offer: Array = [{"id": "wolf", "stat": "move_speed", "op": "mul", "value": 0.05, "min": 0.02, "max": 0.06, "quality": 3},
		{"id": "bear", "stat": "max_hp", "op": "add", "value": 10.0, "min": 6.0, "max": 12.0, "quality": 2}]
	# nothing bought: the same list
	assert_bool(is_same(TotemBoonsScript.boosted(offer, 0.0), offer)).is_true()
	var up: Array = TotemBoonsScript.boosted(offer, 0.2)
	assert_float(float(up[0]["value"])).is_equal_approx(0.06, 0.00001)
	assert_float(float(up[0]["min"])).is_equal_approx(0.024, 0.00001)
	assert_float(float(up[0]["max"])).is_equal_approx(0.072, 0.00001)
	assert_float(float(up[1]["value"])).is_equal_approx(12.0, 0.00001)
	assert_int(TotemBoonsScript.roll_third(up[0])).is_equal(3)
	assert_float(float(offer[0]["value"])).is_equal_approx(0.05, 0.00001)
	assert_float(TotemBoonsScript.effect_of(up[1]).value).is_equal_approx(12.0, 0.00001)
	# the stat comes from the Trail and the game reads it where the offer is rolled
	_rich()
	_buy(["n1", "n2a", "n3a", "n4"])
	assert_float(Run.hero_sheet(Registry.character("drifter"), 1).get_stat("totem_boost", 0.0)).is_equal_approx(0.2, 0.00001)
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(game_src).contains("TOTEM_SCREEN.BOONS.boosted(offer, Run.player_sheet.get_stat(\"totem_boost\", 0.0))")
	assert_bool(TextGen.STATS.has("totem_boost")).is_true()


func test_boss_purse_grows_the_chest_and_the_counters_pay_the_same() -> void:
	var pack := BossChest.make_pack("tumbleweed_king", 200.0, 1000.0, 30.0, 0.0)
	var plain := BossChest.net(pack, 1.2, 1.1)
	assert_int(int(plain["gold_net"])).is_equal(240)
	assert_float(float(plain["xp_net"])).is_equal_approx(1100.0, 0.001)
	assert_bool(plain.has("purse")).is_false()
	var more := BossChest.net(pack, 1.2, 1.1, 0.5)
	assert_int(int(more["gold_net"])).is_equal(360)
	assert_float(float(more["xp_net"])).is_equal_approx(1650.0, 0.001)
	# CLAIM pays the net amounts, so the counters and the payout stay equal; the game reads the stat at the opening
	var game_src := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_str(game_src).contains("BossChest.net(pack, greed, gain, Run.player_sheet.get_stat(\"boss_purse\", 0.0))")
	assert_str(game_src).contains("var gold := int(p.get(\"gold_net\", 0))")
	_rich()
	_buy(["n1", "n2a", "n3a", "n4", "n5"])
	assert_float(Run.hero_sheet(Registry.character("drifter"), 1).get_stat("boss_purse", 0.0)).is_equal_approx(0.5, 0.00001)
	assert_bool(TextGen.STATS.has("boss_purse")).is_true()


# ---------------------------------------------------------------- the words

func test_what_a_node_gives_in_words() -> void:
	assert_str(Trail.give_text(Trail.node("n1"))).is_equal("Attack damage +3%")
	assert_str(Trail.give_text(Trail.node("n2o"))).is_equal("Health a second +0.5")
	assert_str(Trail.give_text(Trail.node("n3b"))).is_equal("Reroll a run +1")
	assert_str(Trail.give_text(Trail.node("n3a"))).is_equal("Coins at the start of a run +25")
	assert_str(Trail.amount_text("percent", 0.025)).is_equal("+2.5%")
	assert_str(Trail.amount_text("percent", -0.1)).is_equal("−10%")
	assert_str(Trail.amount_text("seconds", 2.0)).is_equal("+2 s")
	assert_str(Trail.amount_text("word", 1.0)).is_empty()
	Trail.load_from(GATES)
	assert_str(Trail.give_text(Trail.node("g_outlaw"))).is_equal("Outlaw: " + Registry.character("calavera").display_name)
	assert_str(Trail.give_text(Trail.node("g_weapon"))).is_equal("Weapon: " + Registry.weapon("hammer").display_name)
	var dead: PassiveDef = Registry.passive("deadeye")
	assert_str(Trail.give_text(Trail.node("g_passive"))).is_equal(("Card: " if dead.is_line() else "Item: ") + dead.display_name)
	assert_str(Trail.give_text(Trail.node("g_stage"))).is_equal("Stage: " + Registry.map("red_canyon").timeline.stage_name(1))
	assert_str(Trail.give_text(Trail.node("g_map"))).is_equal("Map: " + Registry.map("red_canyon").display_name)
	assert_str(Trail.give_text(Trail.node("g_structure"))).is_equal("Structure: " + Registry.structure("totem_pole").display_name)
	assert_str(Trail.give_text(Trail.node("g_powerup"))).is_equal("Power-up: " + Registry.pickup("rage").display_name)
	assert_str(Trail.give_text(Trail.node("g_feature"))).is_equal("The Bounty Board")
	assert_str(Trail.give_text(Trail.node("g_skin"))).is_equal("Skin: %s, %s" % [Registry.character("drifter").display_name,
		Registry.character("drifter").skin_name("DRI-B")])
	# never the word the players do not read
	for n: Dictionary in Trail.nodes():
		assert_bool(Trail.give_text(n).to_lower().contains("hero")).is_false()


func test_the_run_record_carries_the_trail() -> void:
	_rich()
	_buy(["n1", "n2a"])
	Save.trail_had().append("nothing:here")
	var r := Trail.record()
	assert_int(int(r["level"])).is_equal(2)
	assert_array(r["bought"]).contains_exactly(["n1", "n2a"])
	assert_int(int(r["paid"])).is_equal(2)
	assert_int(int(r["spent"])).is_equal(90)
	assert_float(float((r["upgrades"] as Dictionary)["might"])).is_equal_approx(0.08, 0.00001)
	var src := FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd")
	# pass 129 (lane TRAIL-REMOVE, schema 6): the header's block is Trail.record() plus the Trail's size and the bought
	# types' words (RunAnalytics.trail_block)
	assert_str(src).contains("header[\"trail\"] = RunAnalytics.trail_block()")
	var blk := RunAnalytics.trail_block()
	assert_array(blk["bought"]).contains_exactly(["n1", "n2a"])
	assert_int(int(blk["levels"])).is_equal(Trail.levels())
	assert_int(int(blk["nodes"])).is_equal(Trail.nodes().size())
	assert_str(str(blk["types"]["might"]["name"])).is_equal(str(Trail.upgrade("might")["name"]))
	assert_bool(RunAnalytics.INDEX_SKIP.has("trail")).is_true()
	assert_bool(RunAnalytics.META_REASONS.has("trail")).is_true()


# ---------------------------------------------------------------- check

func test_check_passes_the_sound_fixtures() -> void:
	for path: String in [RULES, GATES, EMPTY]:
		# an icon still being painted is the art lane's
		var w: Array = Trail.check(Trail.read_file(path)).filter(func(s: String) -> bool: return not s.contains("its icon"))
		assert_array(w).override_failure_message("%s: %s" % [path, "\n".join(PackedStringArray(w))]).is_empty()


func test_check_names_every_fault() -> void:
	var w: Array[String] = Trail.check(Trail.read_file(BAD))
	var all := "\n".join(PackedStringArray(w))
	for want: String in [
			"price: 'k' is not a number", "price: 'round' is not a number", "currency: 'doubloons'",
			"section 'Late': the first section must start at level 1", "section 'Late': 'bottom' is not a colour",
			"section 'Back': starts at level 2", "unknown motif 'anvil'",
			"upgrade 'ghost': no name", "upgrade 'ghost': unknown kind 'bananas'", "art/ui/trail/no_such_icon_p129.png is missing",
			"'no_such_stat' is not a stat", "no_such_stat's op must be add or mul", "no_such_stat's per is 0",
			"upgrade 'hollow': no icon", "upgrade 'hollow': no effects",
			"node a: its id is used twice", "nodes: a node has no id",
			"node b: its level must be 1 or more", "node b: unknown kind 'weird'", "node b: only a choice has a group",
			"node b: need must be all or any", "node b: names itself in from", "node b: from names 'nobody'",
			"node b: from names h, which stands above it", "node b: its price must be", "node b: its price_mult must be",
			"node b: x 0.90 is in the right quarter", "node b: gives an unknown upgrade type 'mite'", "node b: its upgrade has no value",
			"choice group 'solo' on level 2: 1 member", "node c: an unlock (outlaw:nobody_p129) in a choice group",
			"node c: 'nobody_p129' is no outlaw", "node d: a choice without a group", "node d: the weapon 'peashooter' is hidden",
			"node e: from names f of its own level", "node f: gives weapon:hammer, which e gives too",
			"node g: 's1' is the map's first stage", "node h: 'casino' is not a feature", "node i: gives an unknown type 'teleporter'",
			"node j: drifter has no look 'NOPE'", "node k: gives nothing", "node l: map red_canyon has no stage 's9'",
			"node m: its powerup names nothing", "level 2: 5 nodes", "level 4: 6 nodes", "level 3: no nodes"]:
		assert_bool(all.contains(want)).override_failure_message("missing: %s\n---\n%s" % [want, all]).is_true()
	# and the game still plays the file as well as it can: the doubles and the nameless left out, nothing crashes
	Trail.load_from(BAD)
	assert_int(Trail.nodes().size()).is_equal(13)
	for n: Dictionary in Trail.nodes():
		assert_bool(["bought", "open", "locked", "closed"].has(Trail.state(str(n["id"])))).is_true()
		Trail.give_text(n)
		Trail.price(str(n["id"]))
	# a `from` that names no node (or itself) is left out, so the node is not closed for good
	assert_array((Trail.node("b")["from"] as Array)).contains_exactly(["h"])


func test_the_games_own_upgrade_types_name_live_stats() -> void:
	var data := Trail.read_file(Trail.DEFAULT)
	assert_dict(data).is_not_empty()
	var ups: Dictionary = data["upgrades"]
	assert_int(ups.size()).is_greater_equal(35)
	for t: String in ups.keys():
		var u: Dictionary = ups[t]
		assert_bool(Trail.UPGRADE_KINDS.has(str(u["kind"]))).override_failure_message(t).is_true()
		assert_str(str(u["name"])).is_not_empty()
		assert_str(str(u["text"])).is_not_empty()
		for e: Dictionary in u["effects"]:
			var stat := str(e["stat"])
			assert_bool(StatSheet.PLAYER_DEFAULTS.has(stat)).override_failure_message("%s: %s" % [t, stat]).is_true()
			assert_bool(TextGen.STATS.has(stat)).override_failure_message("%s: %s has no TextGen row" % [t, stat]).is_true()
			assert_bool(["add", "mul"].has(str(e["op"]))).is_true()
			# a count is added whole; a multiplier stat (its default 1) never gets a flat or a count
			if str(u["kind"]) == "count":
				assert_str(str(e["op"])).is_equal("add")
				assert_str(TextGen.stat_kind(stat)).is_equal("count")
	# the file without its nodes has nothing to warn of but icons not painted yet
	var bare := data.duplicate(true)
	bare["nodes"] = []
	var w: Array = Trail.check(bare).filter(func(s: String) -> bool: return not s.contains("its icon"))
	assert_array(w).override_failure_message("\n".join(PackedStringArray(w))).is_empty()


# ---------------------------------------------------------------- the migration and the reset

## A save from before the Trail: the board bought into, runs played, things owned and unlocked.
func _old_save() -> void:
	Save.data["gold"] = 100
	Save.data["talents"] = {"drive": {"picks": [0, 1], "rank": 2, "form": 1}, "grit": {"picks": [0], "rank": 1, "form": 0}}
	Save.data["talent_spent"] = 1234
	Save.data["runs_started"] = 7
	Save.add_total("runs", 6)
	Save.heroes_owned().append("calavera")
	Save.skins_owned().append("drifter:DRI-B")
	Save.mark_quest("unlock_hammer")
	Save.mark_stage_beaten("red_canyon", 0)


func test_the_migration_refunds_the_board_and_keeps_what_the_save_has() -> void:
	Trail.load_from(GATES)
	_old_save()
	# two quests retired since (their files gone): one this save had done, one it had not
	Registry.quests.erase("unlock_hammer")
	Registry.quests.erase("unlock_sabre")
	assert_int(Save._migrate_trail()).is_equal(1234)
	# every coin back in full, the old board's keys gone from the save (pass 129: nothing else reads them), the note
	# for the toast
	assert_int(Save.gold()).is_equal(1334)
	for k: String in ["talents", "talent_spent", "talent_spent_in"]:
		assert_bool(Save.data.has(k)).override_failure_message("the save still has " + k).is_false()
	var note := Save.board_note()
	assert_str(str(note["kind"])).is_equal("trail_refund")
	assert_int(int(note["gold"])).is_equal(1234)
	assert_int(int(note["ranks"])).is_equal(3)
	assert_str(Trail.note_text(note)).is_equal("The Upgrade board is now the Trail. Your 1,234 coins are back.")
	assert_str(Trail.note_text({"kind": "trail_refund", "gold": 0})).is_equal("The Upgrade board is now the Trail.")
	assert_str(Trail.note_text({"kind": "stakes_refund", "gold": 5})).is_empty()
	# what the save already had
	var had: Array = Save.trail_had()
	for key: String in ["outlaw:calavera", "outlaw:drifter", "skin:drifter:DRI-B", "weapon:hammer", "weapon:molotov", "weapon:revolver",
			"stage:red_canyon:s1", "stage:red_canyon:s2", "structure:totem_pole", "powerup:rage", "powerup:heart", "feature:wanted",
			"map:red_canyon"]:
		assert_bool(had.has(key)).override_failure_message("not kept: " + key).is_true()
	# and what it had not: an outlaw not bought, a quest not done (retired or still there), a stage not open, a hidden structure
	for key: String in ["outlaw:astro", "weapon:sabre", "weapon:zap_beam", "passive:deadeye", "stage:red_canyon:dust", "structure:gold_bank",
			"skin:drifter:DRI-C"]:
		assert_bool(had.has(key)).override_failure_message("kept: " + key).is_false()
	# so the nodes that give them count as bought at no cost, the others lock
	assert_array(_states(["g_outlaw", "g_skin", "g_weapon", "g_free", "g_structure", "g_powerup", "g_feature", "g_stage", "g_map"])).contains_exactly(
		["bought", "bought", "bought", "bought", "bought", "bought", "bought", "bought", "bought"])
	assert_str(Trail.state("g_passive")).is_equal("open")
	assert_int(Trail.level()).is_equal(1)
	assert_array(Save.trail_bought()).is_empty()
	assert_bool(Registry.is_unlocked("weapon", "hammer")).is_true()
	assert_bool(Registry.is_unlocked("passive", "deadeye")).is_false()
	assert_str(Registry.hero_state(Registry.character("calavera"))).is_equal("owned")
	# once only
	assert_bool(Save.once(Trail.ONCE)).is_true()
	Save.data["talent_spent"] = 500
	assert_int(Save._migrate_trail()).is_equal(0)
	assert_int(int(Save.data["talent_spent"])).is_equal(500)
	assert_int(Save.gold()).is_equal(1334)


func test_a_new_save_keeps_nothing_and_meets_every_gate() -> void:
	Trail.load_from(GATES)
	assert_int(Save._migrate_trail()).is_equal(0)
	assert_bool(Save.once(Trail.ONCE)).is_true()
	assert_array(Save.trail_had()).is_empty()
	assert_dict(Save.board_note()).is_empty()
	assert_array(_states(["g_outlaw", "g_skin", "g_weapon", "g_free"])).contains_exactly(["open", "open", "open", "open"])
	assert_bool(Registry.is_unlocked("weapon", "molotov")).is_false()
	assert_bool(StructureManager.in_play([Registry.structure("totem_pole")]).is_empty()).is_true()


func test_a_wiped_save_is_a_new_one_to_the_trail() -> void:
	Trail.load_from(GATES)
	_old_save()
	Save.wipe()
	# flagged at once: its first runs are never taken for a save older than the Trail
	assert_bool(Save.once(Trail.ONCE)).is_true()
	Save.data["runs_started"] = 3
	Save.data["talent_spent"] = 700
	assert_int(Save._migrate_trail()).is_equal(0)
	assert_array(Save.trail_had()).is_empty()
	assert_int(int(Save.data["talent_spent"])).is_equal(700)
	assert_bool(Trail.has("weapon", "molotov")).is_false()
	# with no nodes a wipe flags nothing: the migration still waits for them
	Trail.load_from(EMPTY)
	Save.wipe()
	assert_bool(Save.once(Trail.ONCE)).is_false()


func test_the_gates_are_off_only_while_the_migration_looks() -> void:
	Trail.load_from(GATES)
	_old_save()
	var had := Trail.had_before()
	assert_bool(had.has("weapon:molotov")).is_true()
	# the look is over: the gates answer again
	assert_bool(Trail.gated("weapon", "molotov")).is_true()
	assert_bool(Trail.has("weapon", "molotov")).is_false()
	assert_array(Save.trail_had()).is_empty()


func test_the_debug_reset_gives_the_coins_back() -> void:
	_rich(1000)
	_buy(["n1", "n2a"])
	Save.trail_had().append("weapon:hammer")
	assert_int(Save.gold()).is_equal(910)
	assert_int(Save.trail_reset()).is_equal(90)
	assert_int(Save.gold()).is_equal(1000)
	assert_array(Save.trail_bought()).is_empty()
	assert_int(Save.trail_spent()).is_equal(0)
	assert_int(Trail.level()).is_equal(0)
	assert_str(Trail.state("n2b")).is_equal("locked")
	# what the save had before the Trail stays, unless asked
	assert_array(Save.trail_had()).contains_exactly(["weapon:hammer"])
	assert_int(Save.trail_reset(true)).is_equal(0)
	assert_array(Save.trail_had()).is_empty()
	# outside prod only: the developer menu holds the row
	var dev_src := FileAccess.get_file_as_string("res://ui/DevMenu.gd")
	assert_str(dev_src).contains("Save.trail_reset()")
	assert_str(dev_src).contains("if Settings.is_prod():")


func test_the_save_keeps_the_trail_through_the_sandbox_and_a_wipe() -> void:
	_rich(1000)
	_buy(["n1"])
	Save.begin_sandbox()
	_buy(["n2a"])
	assert_int(Trail.level()).is_equal(2)
	Save.end_sandbox()
	# the arena's purchases are gone with it
	assert_array(Save.trail_bought()).contains_exactly(["n1"])
	assert_int(Trail.level()).is_equal(1)
	assert_int(Save.gold()).is_equal(960)
	# a file from before the Trail has no block: it reads as empty
	Save.data.erase("trail")
	Trail.refresh()
	assert_array(Save.trail_bought()).is_empty()
	assert_int(Trail.level()).is_equal(0)
	assert_dict(Save._default()["trail"]).is_equal({"bought": [], "spent": 0, "had": []})
