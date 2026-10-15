extends GdUnitTestSuite

## Pass 80, lane BOT (Garry: "add a desire to explore the map and interact with totems and barrels ... Sometimes chase
## power-ups, sometimes chase structures. Add option to interact with the Shop and the Stranger"): the reusable bot in
## tools/bot/ (Bot.gd, BotLegs.gd, BotCards.gd, BotGoals.gd). The cards' scores and their order, the skill dial's spread,
## goals suppressed by danger and low health, an option off never makes a goal of its thing, things are goals only once
## seen, the decision entries' shape, the same seed giving the same decisions, the sim77 preset being pass 77's bot, the
## legs' dials, and a short real run driven by the bot.

const BOT := preload("res://tools/bot/Bot.gd")
const CARDS := preload("res://tools/bot/BotCards.gd")
const GOALS := preload("res://tools/bot/BotGoals.gd")
const LEGS := preload("res://tools/bot/BotLegs.gd")
const SIM := preload("res://tools/sim_run.gd")

# (pass 82, lane WATCH, re-pinned on purpose: "special", the hunt of a special)
const ALLOWED_INTENTS := ["kite", "sweep", "explore", "totem", "barrel", "powerup", "chest", "boss", "boss_chest", "portal", "dodge", "down",
	"special"]


func after_test() -> void:
	Run.launch_override = {}
	Run.sim_mode = false
	Run.seed_dice(0)
	Run.forced_map_seed = 0
	get_tree().paused = false
	if Save.sandboxed():
		Save.end_sandbox()
	RunAnalytics.I = null
	Run.end()


# ---------------------------------------------------------------- fakes

class FakeInput:
	extends RefCounted
	var wants_move := false
	var origin := Vector2.ZERO
	var touch_pos := Vector2.ZERO


class FakePlayer:
	extends Node3D
	var input := FakeInput.new()
	var hp := 100.0
	var max_hp := 100.0
	var dead := false


class FakeMap:
	extends RefCounted
	var flats_center := Vector3.ZERO
	var arena_radius := 66.0
	var obstacles: Array = []


class FakeStructDef:
	extends RefCounted
	var id := ""
	var effect_kind := ""
	var display_name := ""
	var radius := 2.2
	var interact_time := 3.0
	var params := {}

	func _init(i: String, e: String, r: float = 2.2) -> void:
		id = i
		effect_kind = e
		display_name = i.capitalize()
		radius = r


class FakeStructure:
	extends Node3D
	var def: FakeStructDef
	var used := false
	var arriving := false
	var leaving := false
	var progress := 0.0


class FakeStructures:
	extends RefCounted
	var items: Array = []


class FakeBarrels:
	extends RefCounted
	var pos := PackedVector3Array()
	var alive := PackedByteArray()
	var light := PackedByteArray()
	var broken := 0


class FakePickupDef:
	extends RefCounted
	var effect_kind := "buff"
	var display_name := "Sprint"


class FakePowerup:
	extends Node3D
	var def := FakePickupDef.new()
	var taken := false
	var life := 20.0


class FakePickups:
	extends RefCounted
	var specials: Array = []
	var chests: Array = []


class FakeSheet:
	extends RefCounted

	func get_stat(_n: String, d: float = 0.0) -> float:
		return d


class FakeRun:
	extends RefCounted
	var player_sheet := FakeSheet.new()
	var stage := 0
	var run_gold := 0


class FakeGame:
	extends Node
	var player: FakePlayer
	var map := FakeMap.new()
	var structures := FakeStructures.new()
	var barrels := FakeBarrels.new()
	var pickups := FakePickups.new()
	var paused := false


func _fake_game() -> FakeGame:
	var g: FakeGame = auto_free(FakeGame.new())
	g.player = FakePlayer.new()
	add_child(g)
	g.add_child(g.player)
	return g


func _structure(g: FakeGame, id: String, effect: String, at: Vector3, r: float = 2.2) -> FakeStructure:
	var s := FakeStructure.new()
	s.def = FakeStructDef.new(id, effect, r)
	g.add_child(s)
	s.global_position = at
	g.structures.items.append(s)
	return s


func _barrel(g: FakeGame, at: Vector3, black: bool) -> void:
	g.barrels.pos.append(at)
	g.barrels.alive.append(1)
	g.barrels.light.append(1 if black else 0)


func _view(opts: Dictionary, hp: float = 1.0, danger: float = 0.0) -> Dictionary:
	return {"me": Vector3.ZERO, "t": 10.0, "hp_frac": hp, "danger": danger, "style": "balanced", "opts": BOT.resolve_opts(opts),
		"boss": Vector3.INF, "leash": true, "lure_s": 0.0, "lure_at": Vector3.INF}


static func _kinds(cands: Array) -> Array:
	var out: Array = []
	for c in cands:
		if not out.has(str(c["kind"])):
			out.append(str(c["kind"]))
	return out


# ---------------------------------------------------------------- the cards

func _start_run() -> WeaponInstance:
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	var inst := Run.add_weapon(Registry.weapon("revolver"), 1)
	Run.rebuild_sheets()
	return inst


## The first passive in play (not a line, not evolved unless asked) whose level-1 effects carry `stat`.
func _passive_with(stat: String) -> PassiveDef:
	var ids: Array = Registry.passives.keys()
	ids.sort()
	for id in ids:
		var p: PassiveDef = Registry.passives[id]
		if p.hidden or p.is_evolved():
			continue
		for e in p.effects_at_level(1):
			if e is Effect and e.stat == stat and float(e.value) > 0.0:
				return p
	return null


func test_the_scores_measure_what_a_card_adds() -> void:
	var held := _start_run()
	var ctx := CARDS.context(Run, 1.0, 0.0, "balanced")
	assert_float(float(ctx["est"])).is_greater(0.0)
	# a new weapon adds DPS and a share of the free slots' plan
	var tommy := {"type": "weapon", "id": "tommy_gun", "def": Registry.weapon("tommy_gun"), "level_from": 0, "level_to": 1, "is_new": true}
	var s_new := CARDS.score_card(tommy, ctx)
	assert_float(float(s_new["parts"]["dps"])).is_greater(0.0)
	assert_float(float(s_new["parts"]["plan"])).is_greater(0.0)
	# a level of the held weapon adds DPS and its level's plan
	var lv := {"type": "weapon", "id": "revolver", "def": held.def, "level_from": held.level, "level_to": held.level + 1, "is_new": false}
	var s_lv := CARDS.score_card(lv, ctx)
	assert_float(float(s_lv["parts"]["dps"])).is_greater(0.0)
	assert_float(float(s_lv["parts"]["plan"])).is_greater_equal(CARDS.PLAN_WEAPON_LEVEL)
	assert_str(str(s_lv["words"])).contains("DPS")
	# a might passive's DPS comes from the weapons rebuilt on a copy of the sheet (the run's own sheet untouched)
	var might := _passive_with("might")
	assert_object(might).is_not_null()
	var before := Run.player_sheet.entries.size()
	var s_m := CARDS.score_card({"type": "passive", "id": might.id, "def": might, "level_from": 0, "level_to": 1, "is_new": true}, ctx)
	assert_float(float(s_m["parts"]["dps"])).is_greater(0.0)
	assert_int(Run.player_sheet.entries.size()).is_equal(before)
	# a max HP passive is survival, and survival weighs more in danger
	var hp := _passive_with("max_hp")
	assert_object(hp).is_not_null()
	var card := {"type": "passive", "id": hp.id, "def": hp, "level_from": 0, "level_to": 1, "is_new": true}
	var calm := CARDS.score_card(card, ctx)
	var hot := CARDS.score_card(card, CARDS.context(Run, 0.3, 1.0, "balanced"))
	assert_float(float(calm["parts"]["survival"])).is_greater(0.0)
	assert_float(float(hot["score"])).is_greater(float(calm["score"]))
	# the style moves the order: damage weighs the DPS card up against the survival card, safety down
	var dmg := CARDS.context(Run, 1.0, 0.0, "damage")
	var safe := CARDS.context(Run, 1.0, 0.0, "safety")
	var gap_d := float(CARDS.score_card(lv, dmg)["score"]) - float(CARDS.score_card(card, dmg)["score"])
	var gap_s := float(CARDS.score_card(lv, safe)["score"]) - float(CARDS.score_card(card, safe)["score"])
	assert_float(gap_d).is_greater(gap_s)
	# a Totem gift is scored as the effect it puts on the hero
	var boon := {"type": "boon", "id": "bear", "name": "Chet-woot", "effects": [Effect.make("might", "mul", 0.06, "player")]}
	assert_float(float(CARDS.score_card(boon, ctx)["parts"]["dps"])).is_greater(0.0)
	# every part is there on every card the game offers now
	for c in CardPool.level_up_offer(3):
		var sc := CARDS.score_card(c, ctx)
		for k in ["dps", "survival", "plan", "greed"]:
			assert_bool((sc["parts"] as Dictionary).has(k)).is_true()


func test_the_skill_dial_spreads_the_picks() -> void:
	var rows := [{"score": 30.0}, {"score": 20.0}, {"score": 10.0}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := {1.0: [0, 0, 0], 0.6: [0, 0, 0], 0.0: [0, 0, 0]}
	for skill in counts:
		for i in range(400):
			var k := CARDS.pick_scored(rows, float(skill), rng)
			(counts[skill] as Array)[k] += 1
	# skill 1: always the best
	assert_int(int(counts[1.0][0])).is_equal(400)
	# lower: the best still most often, the weaker ones more often the lower the skill
	assert_int(int(counts[0.6][0])).is_greater(int(counts[0.6][1]))
	assert_int(int(counts[0.6][1]) + int(counts[0.6][2])).is_greater(0)
	assert_int(int(counts[0.0][1]) + int(counts[0.0][2])).is_greater(int(counts[0.6][1]) + int(counts[0.6][2]))
	assert_int(CARDS.pick_scored([], 1.0, rng)).is_equal(-1)


# ---------------------------------------------------------------- the goals

func test_far_goals_give_way_to_danger_and_low_health() -> void:
	assert_float(GOALS.far_limit(1.0, 0.0)).is_equal_approx(GOALS.FAR_MAX, 0.001)
	assert_float(GOALS.far_limit(GOALS.HP_LOW, 0.0)).is_equal_approx(GOALS.FAR_MIN, 0.001)
	assert_float(GOALS.far_limit(1.0, 1.0)).is_less(GOALS.FAR_MAX)
	assert_float(GOALS.far_limit(0.6, 0.0)).is_less(GOALS.far_limit(0.9, 0.0))
	var g := _fake_game()
	var run := FakeRun.new()
	_structure(g, "totem_pole", "totem", Vector3(40, 0, 0), 1.2)
	var gl = GOALS.new(3)
	gl.setup_map(g.map)
	gl.observe(g, Vector3(35, 0, 0))
	var view := _view({"preset": "explorer", "explore": 0.0})
	assert_array(_kinds(gl.candidates(g, run, view))).contains(["totem"])
	# hurt: a Totem Pole 40 m off is no goal; nor while the last half minute cost him
	assert_array(_kinds(gl.candidates(g, run, _view({"preset": "explorer", "explore": 0.0}, 0.3)))).not_contains(["totem"])
	assert_array(_kinds(gl.candidates(g, run, _view({"preset": "explorer", "explore": 0.0}, 1.0, 1.0)))).not_contains(["totem"])
	# a healing well calls the more the more he is hurt, and not at all while he is well
	_structure(g, "healing_well", "heal", Vector3(10, 0, 0))
	gl.observe(g, Vector3(10, 0, 0))
	var well_at := func(hp: float) -> float:
		for c in gl.candidates(g, run, _view({"preset": "explorer", "explore": 0.0}, hp)):
			if str(c["what"]) == "structure:healing_well":
				return float(c["value"])
		return 0.0
	assert_float(float(well_at.call(1.0))).is_equal(0.0)
	assert_float(float(well_at.call(0.4))).is_greater(float(well_at.call(0.7)))


func test_an_option_off_never_makes_a_goal_of_its_thing() -> void:
	var g := _fake_game()
	var run := FakeRun.new()
	_structure(g, "totem_pole", "totem", Vector3(8, 0, 0), 1.2)
	_structure(g, "beacon", "level_up", Vector3(-8, 0, 0))
	_structure(g, "shop", "shop", Vector3(0, 0, 8))
	_structure(g, "hooded_figure", "stranger", Vector3(0, 0, -8))
	_barrel(g, Vector3(5, 0, 5), true)
	var pu := FakePowerup.new()
	g.add_child(pu)
	pu.global_position = Vector3(-5, 0, 5)
	g.pickups.specials.append(pu)
	run.run_gold = 10000
	var gl = GOALS.new(4)
	gl.setup_map(g.map)
	gl.observe(g, Vector3.ZERO)
	var all := gl.candidates(g, run, _view({"preset": "explorer"}))
	assert_array(_kinds(all)).contains(["totem", "structure", "barrel", "powerup", "explore"])
	var whats: Array = []
	for c in all:
		whats.append(str(c["what"]))
	assert_array(whats).contains(["structure:shop", "structure:hooded_figure", "structure:beacon"])
	# each option off: its thing is never a goal
	for off in ["totems", "barrels", "powerups"]:
		var o := {"preset": "explorer"}
		o[off] = false
		var ks := _kinds(gl.candidates(g, run, _view(o)))
		assert_array(ks).not_contains([{"totems": "totem", "barrels": "barrel", "powerups": "powerup"}[off]])
	var ws: Array = []
	for c in gl.candidates(g, run, _view({"preset": "explorer", "shop": false, "stranger": false})):
		ws.append(str(c["what"]))
	assert_array(ws).not_contains(["structure:shop", "structure:hooded_figure"])
	assert_array(ws).contains(["structure:beacon"])
	assert_array(_kinds(gl.candidates(g, run, _view({"preset": "explorer", "structures": false})))).not_contains(["structure"])
	assert_array(_kinds(gl.candidates(g, run, _view({"preset": "explorer", "explore": 0.0})))).not_contains(["explore"])
	# pass 77's bot: no map goals at all, no planner
	assert_bool(BOT.planner_on(BOT.resolve_opts({"preset": "sim77"}))).is_false()
	assert_bool(BOT.planner_on(BOT.resolve_opts({"preset": "explorer"}))).is_true()


func test_a_thing_is_a_goal_only_once_seen() -> void:
	var g := _fake_game()
	var run := FakeRun.new()
	_structure(g, "totem_pole", "totem", Vector3(30, 0, 0), 1.2)
	_barrel(g, Vector3(-30, 0, 0), false)
	var gl = GOALS.new(5)
	gl.setup_map(g.map)
	gl.observe(g, Vector3.ZERO)
	var ks := _kinds(gl.candidates(g, run, _view({"preset": "explorer"})))
	assert_array(ks).not_contains(["totem", "barrel"])
	assert_array(ks).contains(["explore"])
	gl.observe(g, Vector3(25, 0, 0))
	assert_array(_kinds(gl.candidates(g, run, _view({"preset": "explorer"})))).contains(["totem"])
	assert_float(gl.seen_share()).is_greater(0.0)
	# used, floating down or resting after a give-up: no goal
	(g.structures.items[0] as FakeStructure).used = true
	assert_array(_kinds(gl.candidates(g, run, _view({"preset": "explorer"})))).not_contains(["totem"])


func test_the_runs_taste_and_mood_follow_the_seed() -> void:
	var a = GOALS.new(11)
	var b = GOALS.new(11)
	var c = GOALS.new(12)
	assert_dict(a.taste).is_equal(b.taste)
	assert_bool(a.taste == c.taste).is_false()
	assert_float(a.mood("powerup", 100.0)).is_equal(b.mood("powerup", 100.0))
	assert_float(a.jitter("st:5")).is_equal(b.jitter("st:5"))
	for k in GOALS.KINDS:
		assert_float(float(a.taste[k])).is_between(GOALS.TASTE_LO, GOALS.TASTE_HI)
	# the mood changes from one spell to the next for some kind
	var moved := false
	for k in GOALS.KINDS:
		if a.mood(k, 10.0) != a.mood(k, 10.0 + GOALS.MOOD_EVERY):
			moved = true
	assert_bool(moved).is_true()


# ---------------------------------------------------------------- the decisions

func _offer() -> Array:
	var w := Registry.weapon("revolver")
	var inst := Run.weapon_instance("revolver")
	var out: Array = [{"type": "weapon", "id": "tommy_gun", "def": Registry.weapon("tommy_gun"), "level_from": 0, "level_to": 1, "is_new": true},
		{"type": "weapon", "id": "revolver", "def": w, "level_from": inst.level, "level_to": inst.level + 1, "is_new": false}]
	var hp := _passive_with("max_hp")
	out.append({"type": "passive", "id": hp.id, "def": hp, "level_from": 0, "level_to": 1, "is_new": true})
	return out


func test_decision_entries_have_their_shape() -> void:
	_start_run()
	var g := _fake_game()
	var bot = BOT.new(g, {"seed": 3, "preset": "explorer", "skill": 1.0})
	var seen: Array = []
	bot.decided.connect(func(e: Dictionary) -> void: seen.append(e))
	var pick: Dictionary = bot._choose_scored("card", _offer())
	assert_bool(pick.is_empty()).is_false()
	assert_int(bot.decisions.size()).is_equal(1)
	assert_int(seen.size()).is_equal(1)
	var e: Dictionary = bot.decisions[0]
	for k in ["t", "clock", "kind", "offered", "taken", "reason", "level", "dps_before"]:
		assert_bool(e.has(k)).override_failure_message("no %s" % k).is_true()
	assert_str(str(e["kind"])).is_equal("card")
	assert_str(str(e["taken"])).is_equal(str(pick["id"]))
	assert_int((e["offered"] as Array).size()).is_equal(3)
	for row in e["offered"]:
		for k in ["id", "name", "score", "parts"]:
			assert_bool((row as Dictionary).has(k)).is_true()
		for k in ["dps", "survival", "plan", "greed"]:
			assert_bool((row["parts"] as Dictionary).has(k)).is_true()
	assert_str(str(e["reason"])).is_not_empty()
	# skill 1 takes the best scored
	var best := ""
	var bv := -INF
	for row in e["offered"]:
		if float(row["score"]) > bv:
			bv = float(row["score"])
			best = str(row["id"])
	assert_str(str(e["taken"])).is_equal(best)
	# a goal entry carries what and the runner-up
	bot._commit({"kind": "totem", "what": "totem", "key": "st:1", "at": Vector3(3, 0, 0), "value": 60.0, "u": 30.0, "why": "a gift", "d": 3.0},
		{"kind": "barrel", "what": "barrel", "key": "barrel:0", "at": Vector3.ZERO, "value": 10.0, "u": 5.0, "why": "a barrel", "d": 4.0})
	var ge: Dictionary = bot.decisions[bot.decisions.size() - 1]
	assert_str(str(ge["kind"])).is_equal("goal")
	assert_str(str(ge["what"])).is_equal("totem")
	assert_str(str(ge["runner_up"])).contains("barrel")
	assert_str(str(bot.goal["what"])).is_equal("totem")
	# the summary the run sim writes
	var sm: Dictionary = bot.summary()
	for k in ["opts", "metres", "goals", "gave_up", "decisions", "seen", "shop_bought", "stranger_taken"]:
		assert_bool(sm.has(k)).is_true()


func test_the_same_seed_gives_the_same_decisions() -> void:
	_start_run()
	var g := _fake_game()
	var takes := func(sd: int) -> Array:
		var bot = BOT.new(g, {"seed": sd, "preset": "explorer", "skill": 0.2})
		var out: Array = []
		for i in range(30):
			out.append(str(bot._choose_scored("card", _offer()).get("id", "")))
		return out
	var a: Array = takes.call(7)
	assert_array(takes.call(7)).is_equal(a)
	assert_bool(takes.call(8) == a).is_false()


func test_the_shop_and_the_stranger_follow_their_options() -> void:
	_start_run()
	var g := _fake_game()
	# shop off: he leaves without buying, and says so
	var bot = BOT.new(g, {"seed": 2, "preset": "explorer", "shop": false, "stranger": false})
	var sh := FakeShop.new()
	sh._offer = _offer()
	Run.run_gold = 100000
	bot._shop(sh)
	assert_bool(sh.finished).is_true()
	assert_bool(sh.bought).is_false()
	assert_str(str(bot.decisions[0]["taken"])).is_equal("")
	# shop on, rich: he buys the best ware worth its price
	var bot2 = BOT.new(g, {"seed": 2, "preset": "explorer", "skill": 1.0})
	var sh2 := FakeShop.new()
	sh2._offer = _offer()
	sh2._cards = [null, null, null]
	bot2._shop(sh2)
	assert_bool(sh2.bought).is_true()
	assert_str(str(bot2.decisions[0]["taken"])).is_not_empty()
	# poor: nothing bought
	Run.run_gold = 0
	var sh3 := FakeShop.new()
	sh3._offer = _offer()
	sh3._cards = [null, null, null]
	bot2._shop(sh3)
	assert_bool(sh3.bought).is_false()
	# the Stranger: hurt, he walks away whatever the ware; stranger off, too
	var ss := FakeStranger.new()
	ss.offer = _offer()[0]
	g.player.hp = 30.0
	bot2._stranger(ss)
	assert_bool(ss.took).is_false()
	assert_str(str(bot2.decisions[bot2.decisions.size() - 1]["reason"])).contains("walked away")
	g.player.hp = 100.0
	var ss2 := FakeStranger.new()
	ss2.offer = _offer()[0]
	bot._stranger(ss2)
	assert_bool(ss2.took).is_false()


class FakeShop:
	extends RefCounted
	var _offer: Array = []
	var _cards: Array = []
	var finished := false
	var bought := false

	func price_of(_c: Dictionary) -> int:
		return 300

	func _buy(_c: Dictionary, _price: int, _node) -> void:
		bought = true
		finished = true

	func _finish(b: bool) -> void:
		finished = true
		bought = b


class FakeStranger:
	extends RefCounted
	var offer: Dictionary = {}
	var took := false
	var done := false

	func result() -> Dictionary:
		return offer

	func _finish(t: bool) -> void:
		took = t
		done = true


# ---------------------------------------------------------------- the options

func test_the_presets_and_the_options() -> void:
	# every preset sets every option; the runner's args name every one
	var keys: Array = (BOT.PRESETS["sim77"] as Dictionary).keys()
	for p in BOT.PRESETS:
		assert_array((BOT.PRESETS[p] as Dictionary).keys()).contains_exactly_in_any_order(keys)
	for k in keys:
		assert_bool(SIM.BOT_ARGS.has(k)).override_failure_message("sim_run.gd's BOT_ARGS lacks %s" % k).is_true()
	assert_str(BOT.DEFAULT_PRESET).is_equal("explorer")
	# pass 77's bot: tiers, no goals, the kite's distances exactly
	var o := BOT.resolve_opts({"preset": "sim77"})
	assert_str(str(o["cards"])).is_equal("tier")
	assert_float(BOT.daring_keep(float(o["daring"]))).is_equal(LEGS.KEEP)
	assert_float(BOT.daring_flee(float(o["daring"]))).is_equal(LEGS.FLEE)
	# a key given wins over the preset; out-of-range values are clamped; unknown keys dropped
	var o2 := BOT.resolve_opts({"preset": "sim77", "skill": 3.0, "totems": "1", "style": "nonsense", "bogus": 1})
	assert_float(float(o2["skill"])).is_equal(1.0)
	assert_bool(bool(o2["totems"])).is_true()
	assert_str(str(o2["style"])).is_equal("balanced")
	assert_bool(o2.has("bogus")).is_false()
	assert_str(str(BOT.resolve_opts({"preset": "nope"})["preset"])).is_equal(BOT.DEFAULT_PRESET)
	# daring moves the kite's distances: bolder is closer
	assert_float(BOT.daring_keep(1.0)).is_less(BOT.daring_keep(0.0))
	assert_float(BOT.daring_flee(1.0)).is_less(BOT.daring_flee(0.0))


func test_the_legs_dials() -> void:
	var it := {"pool": "band", "mode": 1, "t": 0.1, "dur": 1.6, "dead": false, "r": 4.6, "at": Vector3.ZERO, "col": Color(0.93, 0.29, 0.36, 0.85)}
	# reaction: a warning younger than it is not seen yet
	assert_bool(LEGS.seen_warning(it, Vector3.ZERO, 0.3, 1.0, 1)).is_false()
	it["t"] = 0.5
	assert_bool(LEGS.seen_warning(it, Vector3.ZERO, 0.3, 1.0, 1)).is_true()
	# dodge 0 sees none, 1 every one; between, a fixed roll per warning
	assert_bool(LEGS.seen_warning(it, Vector3.ZERO, 0.0, 0.0, 1)).is_false()
	assert_bool(LEGS.seen_warning(it, Vector3.ZERO, 0.0, 1.0, 1)).is_true()
	var n := 0
	for i in range(200):
		var at := Vector3(float(i) * 0.37, 0, float(i % 7))
		if LEGS.seen_warning(it, at, 0.0, 0.5, 9):
			n += 1
		assert_bool(LEGS.seen_warning(it, at, 0.0, 0.5, 9)).is_equal(LEGS.seen_warning(it, at, 0.0, 0.5, 9))
	assert_int(n).is_between(60, 140)
	# the danger push seen `reaction` seconds late
	var legs = LEGS.new(1)
	legs.reaction = 0.5
	var push := Vector3(1, 0, 0)
	assert_vector(legs._react(push, 0.1)).is_equal(Vector3.ZERO)
	for i in range(5):
		legs._react(push, 0.1)
	assert_vector(legs._react(Vector3(0, 0, 1), 0.1)).is_equal(push)
	legs.reaction = 0.0
	assert_vector(legs._react(Vector3(0, 0, 1), 0.1)).is_equal(Vector3(0, 0, 1))


# ---------------------------------------------------------------- a real run

func test_the_bot_plays_a_real_run() -> void:
	Save.begin_sandbox()
	Run.seed_dice(9)
	Run.launch_override = {"character": "drifter", "map": "red_canyon", "map_seed": 9, "analytics_memory": true}
	var g: Game = load("res://game/Game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.player.god = true
	# a black barrel just ahead of him, the explorer's and a bot told barrels=0's
	var bf: BarrelField = g.barrels
	assert_object(bf).is_not_null()
	var me := g.player.global_position
	bf.pos[0] = Vector3(me.x + 6.0, bf.pos[0].y, me.z)
	bf.light[0] = 1
	# (pass 82, re-pinned on purpose: the specials are a map goal too, so they are off here)
	var off = BOT.new(g, {"seed": 9, "preset": "explorer", "barrels": false, "totems": false, "structures": false, "explore": 0.0, "powerups": false,
		"specials": false})
	# the barrels=0 bot runs no planner (no map goal is on): it never makes a barrel a goal
	assert_object(off.planner).is_null()
	var bot = BOT.new(g, {"seed": 9, "preset": "explorer", "explore": 0.0})
	var intents := {}
	var start := g.player.global_position
	var frames := 0
	for i in range(1200):
		await get_tree().process_frame
		if g._ended:
			break
		bot.tick(get_process_delta_time())
		intents[bot.intent] = true
		frames += 1
		if bf.alive[0] == 0:
			break
	for k in intents:
		assert_bool(ALLOWED_INTENTS.has(str(k)) or str(k).begins_with("structure:")).override_failure_message("intent %s" % k).is_true()
	assert_bool(intents.has("barrel")).override_failure_message("intents %s" % str(intents.keys())).is_true()
	assert_int(int(bf.alive[0])).override_failure_message("the barrel at %s still stands after %d frames (hero from %s to %s, goal %s)" % [
		str(bf.pos[0]), frames, str(start), str(g.player.global_position), str(bot.goal)]).is_equal(0)
	var goals: Array = bot.decisions.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "goal")
	assert_bool(goals.is_empty()).is_false()
	assert_float(float(bot.metres)).is_greater(1.0)
	g.queue_free()
	await get_tree().process_frame
