extends GdUnitTestSuite

## Pass 90, lane BOT (Garry: the bot "has a nasty habit of getting overwhelmed with enemies if they spawn in a `ring`
## around him... detects that he is surrounded and then just tries to push through in a specific direction" / "I meant
## the Special enemy types like `Rocketeer`, `Sniper` and the `Harpooner`... Let's not hunt coloured fodder enemies"):
## the ring breakout (tools/bot/BotBreakout.gd, its option and the "survivor" preset in tools/bot/Bot.gd), the hunt of
## the special creature types only (BotGoals.is_special_type), and Bot.on_revived (the Watch's revive).

const BOT := preload("res://tools/bot/Bot.gd")
const GOALS := preload("res://tools/bot/BotGoals.gd")
const BREAK := preload("res://tools/bot/BotBreakout.gd")
const SIM := preload("res://tools/sim_run.gd")


func after_test() -> void:
	get_tree().paused = false


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


class FakeDef:
	extends RefCounted
	var id := "goblin"
	var display_name := "Goblin"
	var archetype := "swarm"
	var badge := ""

	func badge_for() -> String:
		return badge


class FakeEnemies:
	extends RefCounted
	const MAX := 64
	const STATE_DYING := 3
	var alive := PackedByteArray()
	var vspecial := PackedByteArray()
	var hidden := PackedByteArray()
	var state := PackedInt32Array()
	var serial := PackedInt32Array()
	var pos := PackedVector3Array()
	var radius := PackedFloat32Array()
	var dmg := PackedFloat32Array()
	var type_idx := PackedInt32Array()
	var onscreen := PackedByteArray()
	var types: Array = []
	var special_defaults := {"chest_chance": 0.35}
	var special_chests := 0
	var boss_index := -1

	func _init() -> void:
		alive.resize(MAX)
		vspecial.resize(MAX)
		hidden.resize(MAX)
		state.resize(MAX)
		serial.resize(MAX)
		pos.resize(MAX)
		radius.resize(MAX)
		dmg.resize(MAX)
		type_idx.resize(MAX)
		onscreen.resize(MAX)
		onscreen.fill(1)
		var plain := FakeDef.new()
		var raider := FakeDef.new()
		raider.id = "rocketeer"
		raider.display_name = "Vulture Raider"
		raider.archetype = "spitter"
		raider.badge = "gear"
		# the game's own type entries carry the badge (EnemyManager: "badge": def.badge_for())
		types = [{"def": plain, "badge": ""}, {"def": raider, "badge": "gear"}]

	func put(i: int, at: Vector3, type_i: int = 0, coloured: bool = false, sr: int = 1) -> void:
		alive[i] = 1
		vspecial[i] = 1 if coloured else 0
		state[i] = 0
		serial[i] = sr
		pos[i] = at
		radius[i] = 0.5
		dmg[i] = 10.0
		type_idx[i] = type_i


class FakePickups:
	extends RefCounted
	const GRID_N := 1
	const GRID_CELL := 10.0
	const GRID_HALF := 5.0
	const KIND_COIN := 1
	const KIND_VACUUM := 2
	var specials: Array = []
	var chests: Array = []
	var _g_head := PackedInt32Array([-1])
	var _g_next := PackedInt32Array()
	var pos := PackedVector3Array()
	var kind := PackedInt32Array()
	var value := PackedFloat32Array()
	var alive := PackedByteArray()
	var flying := PackedByteArray()


class FakeGame:
	extends Node
	var player: FakePlayer
	var map := FakeMap.new()
	var enemies := FakeEnemies.new()
	var pickups := FakePickups.new()
	var projectiles = null
	var paused := false
	var portal = null


func _fake_game() -> FakeGame:
	var g: FakeGame = auto_free(FakeGame.new())
	g.player = FakePlayer.new()
	add_child(g)
	g.add_child(g.player)
	return g


## A ring of `n` bodies (Vector4: x, z, radius, weight) `radius` m round the hero, leaving out the directions within
## `skip` degrees of `skip_at`.
static func _ring(n: int, radius: float, skip_at: float = -1.0, skip: float = 0.0, r: float = 0.5) -> Array:
	var out: Array = []
	for k in range(n):
		var deg := 360.0 * float(k) / float(n)
		if skip_at >= 0.0 and absf(rad_to_deg(angle_difference(deg_to_rad(deg), deg_to_rad(skip_at)))) <= skip:
			continue
		var w := BREAK.way_of(deg)
		out.append(Vector4(w.x * radius, w.z * radius, r, 1.0))
	return out


static func _deg_off(a: float, b: float) -> float:
	return absf(rad_to_deg(angle_difference(deg_to_rad(a), deg_to_rad(b))))


# ---------------------------------------------------------------- surrounded or not

func test_a_closed_ring_is_surrounded_and_a_half_ring_is_not() -> void:
	var ring := _ring(24, 8.0)
	var cov := BREAK.coverage(ring)
	assert_int(int(cov["n"])).is_equal(24)
	# the slits between two bites are no way out: the whole round is shut
	assert_float(float(cov["cover"])).is_greater_equal(BREAK.COVER_MIN)
	assert_float(float(cov["gap_deg"])).is_less_equal(BREAK.GAP_MAX_DEG)
	assert_bool(BREAK.surrounded(cov)).is_true()
	# half a ring (the north half): a wide way out to the south
	var half: Array = _ring(24, 8.0).filter(func(b: Vector4) -> bool: return b.y <= 0.01)
	var hc := BREAK.coverage(half)
	assert_bool(BREAK.surrounded(hc)).is_false()
	assert_float(float(hc["gap_deg"])).is_greater(150.0)
	assert_float(_deg_off(float(hc["gap_at"]), 180.0)).is_less(20.0)
	# a ring with a walkable gap (60 degrees open to the east) is the kite's, not a breakout
	var gap := BREAK.coverage(_ring(24, 8.0, 90.0, 30.0))
	assert_bool(BREAK.surrounded(gap)).is_false()
	assert_float(_deg_off(float(gap["gap_at"]), 90.0)).is_less(10.0)
	# a few scattered round him: not a ring (most ways open)
	assert_bool(BREAK.surrounded(BREAK.coverage(_ring(BREAK.N_MIN, 8.0)))).is_false()
	# too few, however close
	assert_bool(BREAK.surrounded(BREAK.coverage(_ring(BREAK.N_MIN - 1, 2.0, -1.0, 0.0, 1.5)))).is_false()
	# a ring still far off (past RING_R) is not counted yet
	assert_int(int(BREAK.coverage(_ring(30, BREAK.RING_R + 4.0))["n"])).is_equal(0)


# ---------------------------------------------------------------- the way out

func test_the_way_out_goes_through_the_thinnest_wall() -> void:
	# two rings (8 and 10 m), the outer one missing round the east: the wall is one creature thick there, two elsewhere
	var bodies := _ring(24, 8.0)
	bodies.append_array(_ring(24, 10.0, 90.0, 25.0))
	var c := BREAK.choose_way(bodies, Vector3.ZERO, 66.0, [], Vector3.ZERO)
	assert_float(_deg_off(float(c["deg"]), 90.0)).is_less_equal(20.0)
	assert_int(int(c["thick"])).is_equal(1)
	assert_str(BREAK.compass(float(c["deg"]))).is_equal("east")
	# the rows the decision lists: the three cheapest, the chosen first
	assert_int((c["rows"] as Array).size()).is_equal(3)
	assert_str(str(c["rows"][0]["id"])).is_equal("way:%d" % roundi(float(c["deg"])))
	# a heavy biter in the east (an Elite's weight) with the west thinned the same way: he goes west
	var west := _ring(24, 10.0, 270.0, 25.0)
	var both := _ring(24, 8.0)
	both.append_array(west.filter(func(b: Vector4) -> bool: return not (b.x > 9.0 and absf(b.y) < 2.6)))
	both.append(Vector4(10.0, 0.0, 1.0, 8.0))
	var c2 := BREAK.choose_way(both, Vector3.ZERO, 66.0, [], Vector3.ZERO)
	assert_float(_deg_off(float(c2["deg"]), 270.0)).is_less_equal(20.0)
	# what lies past the wall counts: the same ring, a crowd waiting past its east side, the west is open beyond
	var past := _ring(24, 8.0)
	for k in range(10):
		past.append(Vector4(BREAK.WALL_LEN + 2.0 + float(k), 0.0, 0.5, 1.0))
	var c3 := BREAK.choose_way(past, Vector3.ZERO, 66.0, [], Vector3.ZERO)
	assert_float(float(c3["beyond"])).is_equal(0.0)
	assert_float(_deg_off(float(c3["deg"]), 90.0)).is_greater(1.0)
	# near the arena's edge (the east) an even ring is left towards the middle, not out at the wall
	var c4 := BREAK.choose_way(_ring(24, 8.0), Vector3(55.0, 0.0, 0.0), 66.0, [], Vector3.ZERO)
	assert_float(_deg_off(float(c4["deg"]), 270.0)).is_less_equal(60.0)
	# an even ring in the open: his goal's way wins the tie
	var c5 := BREAK.choose_way(_ring(24, 8.0), Vector3.ZERO, 66.0, [], BREAK.way_of(135.0))
	assert_float(_deg_off(float(c5["deg"]), 135.0)).is_less_equal(15.0)
	# a rock straight in the thin side's way: he takes another
	var rock := [Vector3(5.0, 0.0, 2.0)]
	var c6 := BREAK.choose_way(bodies, Vector3.ZERO, 66.0, rock, Vector3.ZERO)
	assert_float(_deg_off(float(c6["deg"]), 90.0)).is_greater(5.0)


# ---------------------------------------------------------------- the commitment

func test_the_push_holds_its_way_until_he_is_out_then_cools_down() -> void:
	var bodies := _ring(24, 8.0)
	bodies.append_array(_ring(24, 10.0, 90.0, 25.0))
	var bo = BREAK.new()
	var ctx := {"arena_r": 66.0, "obstacles": [], "lean": Vector3.ZERO}
	var me := Vector3.ZERO
	var d: Vector3 = bo.update(1.0 / 60.0, me, bodies, ctx)
	assert_str(str(bo.last_event)).is_equal("started")
	assert_bool(bool(bo.active)).is_true()
	assert_float(d.length()).is_equal_approx(1.0, 0.001)
	var way := d
	# the margin: the wall's far side + CLEAR_MARGIN
	assert_float(float(bo.need)).is_equal_approx(clampf(float(bo.choice["far"]) + BREAK.CLEAR_MARGIN, BREAK.NEED_MIN, BREAK.WALL_LEN + BREAK.CLEAR_MARGIN), 0.01)
	# half way the crowd shifts (the west now the thinnest, nothing round him at all): he holds his way, no turning back
	var shifted := _ring(24, 8.0)
	shifted.append_array(_ring(24, 10.0, 270.0, 60.0))
	var frames := 0
	while bo.active and frames < 600:
		me += way * 5.0 / 60.0
		var dd: Vector3 = bo.update(1.0 / 60.0, me, shifted if frames % 2 == 0 else [], ctx)
		frames += 1
		if bo.active:
			assert_vector(dd).is_equal(way)
	assert_str(str(bo.last_event)).is_equal("ended")
	assert_str(str(bo.ended["why"])).is_equal("out")
	assert_float(Vector2(me.x, me.z).length()).is_greater_equal(float(bo.need) - 0.1)
	# the cooldown: surrounded again at once, no new push for COOLDOWN_S
	var again := false
	for i in range(roundi(BREAK.COOLDOWN_S / 0.1) - 1):
		var dd2: Vector3 = bo.update(0.1, me, bodies, ctx)
		again = again or dd2 != Vector3.ZERO
	assert_bool(again).is_false()
	bo.update(0.2, me, bodies, ctx)
	assert_bool(bool(bo.active)).is_true()
	# held fast (he does not get anywhere): the clock ends it at MAX_S
	var bo2 = BREAK.new()
	bo2.update(0.0, Vector3.ZERO, bodies, ctx)
	var tt := 0.0
	while bo2.active and tt < 10.0:
		bo2.update(0.1, Vector3.ZERO, bodies, ctx)
		tt += 0.1
	assert_float(tt).is_equal_approx(BREAK.MAX_S, 0.11)
	assert_str(str(bo2.ended["why"])).is_equal("timeout")
	assert_dict(bo2.tallies()).is_equal({"started": 1, "rings": 0, "out": 0, "timeout": 1})
	# reset (a revive): nothing under way, no cooldown
	bo2.reset()
	assert_bool(bool(bo2.active)).is_false()
	assert_float(float(bo2.cooldown)).is_equal(0.0)


func test_bodies_are_read_off_the_crowd() -> void:
	var em := FakeEnemies.new()
	em.put(0, Vector3(3, 0, 0))
	em.put(1, Vector3(0, 0, -4))
	em.dmg[1] = 30.0
	em.put(2, Vector3(40, 0, 0))
	em.put(3, Vector3(-3, 0, 0))
	em.state[3] = FakeEnemies.STATE_DYING
	em.put(4, Vector3(0, 0, 5))
	em.hidden[4] = 1
	var bs := BREAK.bodies_of(em, Vector3(1, 0, 0))
	assert_int(bs.size()).is_equal(2)
	var a: Vector4 = bs[0]
	assert_vector(Vector2(a.x, a.y)).is_equal(Vector2(2, 0))
	# the bite against the crowd's mean (10 and 30: 0.5 and 1.5)
	assert_float(a.w).is_equal_approx(0.5, 0.001)
	assert_float((bs[1] as Vector4).w).is_equal_approx(1.5, 0.001)
	assert_int(BREAK.bodies_of(null, Vector3.ZERO).size()).is_equal(0)


# ---------------------------------------------------------------- the option and the preset

func test_the_breakout_option_the_safety_style_and_the_survivor_preset() -> void:
	assert_bool(BOT.BOOL_KEYS.has("breakout")).is_true()
	assert_bool(SIM.BOT_ARGS.has("breakout")).is_true()
	assert_bool(BOT.PRESETS.has("survivor")).is_true()
	var keys: Array = (BOT.PRESETS["explorer"] as Dictionary).keys()
	for p in BOT.PRESETS:
		assert_array((BOT.PRESETS[p] as Dictionary).keys()).override_failure_message(p).contains_exactly_in_any_order(keys)
	var sv := BOT.resolve_opts({"preset": "survivor"})
	assert_bool(bool(sv["breakout"])).is_true()
	assert_str(str(sv["style"])).is_equal("safety")
	# the survivor is the Explorer otherwise
	for k in keys:
		if not str(k) in ["style", "breakout"]:
			assert_str(str(sv[k])).override_failure_message(str(k)).is_equal(str(BOT.PRESETS["explorer"][k]))
	for p in ["explorer", "sim77", "careless", "expert"]:
		assert_bool(bool(BOT.resolve_opts({"preset": p})["breakout"])).override_failure_message(p).is_false()
	# the safety style brings it, unless it is said; any other style leaves the preset's
	assert_bool(bool(BOT.resolve_opts({"preset": "explorer", "style": "safety"})["breakout"])).is_true()
	assert_bool(bool(BOT.resolve_opts({"preset": "explorer", "style": "safety", "breakout": "0"})["breakout"])).is_false()
	assert_bool(bool(BOT.resolve_opts({"preset": "explorer", "style": "greedy"})["breakout"])).is_false()
	assert_bool(bool(BOT.resolve_opts({"preset": "explorer", "breakout": "1"})["breakout"])).is_true()
	assert_bool(bool(BOT.resolve_opts({"preset": "survivor", "breakout": "off"})["breakout"])).is_false()
	# a bot without it has no breakout at all
	var g := _fake_game()
	assert_object(BOT.new(g, {"preset": "explorer"}).breakout).is_null()
	assert_object(BOT.new(g, {"preset": "survivor"}).breakout).is_not_null()


# ---------------------------------------------------------------- the bot breaks out

func test_the_bot_breaks_out_logs_it_and_a_revive_clears_it() -> void:
	var g := _fake_game()
	var em: FakeEnemies = g.enemies
	# a ring of 24 at 8 m and an outer one at 10 m, open past the east
	var k := 0
	for b: Vector4 in _ring(24, 8.0) + _ring(24, 10.0, 90.0, 25.0):
		em.put(k, Vector3(b.x, 0.0, b.y))
		k += 1
	var bot = BOT.new(g, {"seed": 3, "preset": "survivor"})
	bot._drive(1.0 / 60.0)
	assert_str(str(bot.intent)).is_equal("breakout")
	var e: Dictionary = bot.decisions[bot.decisions.size() - 1]
	assert_str(str(e["kind"])).is_equal("breakout")
	assert_str(str(e["phase"])).is_equal("start")
	assert_float(_deg_off(float(e["dir_deg"]), 90.0)).is_less_equal(20.0)
	assert_int(int(e["thick"])).is_equal(1)
	assert_str(str(e["taken"])).is_equal("way:%d" % int(e["dir_deg"]))
	# (the inner ring: the outer one stands past RING_R)
	assert_str(str(e["reason"])).contains("surrounded: 24 creatures")
	assert_str(str(e["reason"])).contains("east (1 creature in the way)")
	# the stick goes that way at full tilt
	var inp: FakeInput = g.player.input
	assert_bool(inp.wants_move).is_true()
	var stick := (inp.touch_pos - inp.origin).normalized()
	assert_float(_deg_off(BREAK.deg_of(Vector3(stick.x, 0, stick.y)), float(e["dir_deg"]))).is_less(5.0)
	# he walks out: the push ends with an entry of its own
	var way := BREAK.way_of(float(e["dir_deg"]))
	for f in range(400):
		g.player.position += way * 5.0 / 60.0
		bot._drive(1.0 / 60.0)
		if not bot.breakout.active:
			break
	assert_bool(bool(bot.breakout.active)).is_false()
	# (the planner may take a new goal the same frame: the push's own entry is the last "breakout")
	var bos: Array = bot.decisions.filter(func(x: Dictionary) -> bool: return str(x["kind"]) == "breakout")
	assert_int(bos.size()).is_equal(2)
	var end: Dictionary = bos[1]
	assert_str(str(end["kind"])).is_equal("breakout")
	assert_str(str(end["phase"])).is_equal("end")
	assert_str(str(end["why"])).is_equal("out")
	assert_str(str(end["reason"])).starts_with("out of the ring after ")
	assert_dict(bot.summary()["breakout"] as Dictionary).is_equal({"started": 1, "rings": 0, "out": 1, "timeout": 0})
	# a new push under way, then the Watch's revive: all of it cleared
	g.player.position = Vector3.ZERO
	bot.breakout.cooldown = 0.0
	bot._bo_bodies = []
	bot._drive(1.0 / 60.0)
	assert_bool(bool(bot.breakout.active)).is_true()
	bot._cur = {"kind": "explore", "key": "cell:1"}
	bot.goal = {"what": "explore"}
	bot._hold = true
	bot.on_revived()
	assert_bool(bool(bot.breakout.active)).is_false()
	assert_dict(bot._cur).is_empty()
	assert_dict(bot.goal).is_empty()
	assert_bool(bool(bot._hold)).is_false()
	assert_str(str(bot.intent)).is_equal("kite")
	# a bot without the breakout takes a revive too
	BOT.new(g, {"preset": "explorer"}).on_revived()


# ---------------------------------------------------------------- the hunt: the special creature types only

func test_the_hunt_takes_the_special_types_never_the_coloured_ones() -> void:
	var g := _fake_game()
	var em: FakeEnemies = g.enemies
	# a coloured (variance) special goblin at 12 m, a Vulture Raider (gear badge) at 14 m
	em.put(0, Vector3(12, 0, 0), 0, true, 7)
	em.put(1, Vector3(0, 0, 14), 1, false, 9)
	assert_bool(GOALS.is_special_type(em, 0)).is_false()
	assert_bool(GOALS.is_special_type(em, 1)).is_true()
	assert_bool(GOALS.is_special_type(em, 63)).is_false()
	assert_bool(GOALS.is_special_type(null, 0)).is_false()
	# a type entry without the badge asks its def
	em.types[1] = {"def": em.types[1]["def"]}
	assert_bool(GOALS.is_special_type(em, 1)).is_true()
	var gl = GOALS.new(3)
	gl.setup_map(g.map)
	var view := {"me": Vector3.ZERO, "t": 10.0, "hp_frac": 1.0, "danger": 0.0, "style": "balanced",
		"opts": BOT.resolve_opts({"preset": "explorer", "explore": 0.0}), "boss": Vector3.INF, "leash": true, "lure_s": 0.0,
		"lure_at": Vector3.INF, "held_key": ""}
	gl.candidates(g, null, view)
	view["t"] = 20.0
	var sp: Array = gl.candidates(g, null, view).filter(func(c: Dictionary) -> bool: return str(c["kind"]) == "special")
	assert_int(sp.size()).is_equal(1)
	assert_str(str(sp[0]["key"])).is_equal(GOALS.special_key(1, 9))
	assert_str(str(sp[0]["sid"])).is_equal("rocketeer")
	assert_str(str(sp[0]["why"])).is_equal("a special: Vulture Raider, out of reach 10 s")
	# the bot's tallies: the special types it saw (came, killed), the coloured ones apart
	var bot = BOT.new(g, {"seed": 2, "preset": "explorer"})
	for f in range(BOT.GEAR_EVERY):
		bot._watch_gear()
	em.state[1] = FakeEnemies.STATE_DYING
	for f in range(BOT.GEAR_EVERY):
		bot._watch_gear()
	var st: Dictionary = bot.special_tallies()
	assert_int(int(st["came"])).is_equal(1)
	assert_int(int(st["killed"])).is_equal(1)
	assert_bool(st.has("coloured")).is_true()
	for k in ["came", "killed", "life_s", "hunted", "found", "hunted_down", "gave_up"]:
		assert_bool(st.has(k)).override_failure_message(k).is_true()


func test_the_real_special_creatures_wear_the_gear_badge() -> void:
	# by data: the map's special pool and the gear-badge creatures are the same set (the Rocketeer, the Sniper, the Harpooner)
	var gear: Array = []
	for id in Registry.enemies:
		var d: EnemyDef = Registry.enemies[id]
		if d.badge_for() == "gear":
			gear.append(str(id))
	for id in ["rocketeer", "saiga_sniper", "harpoon_troglodyte"]:
		assert_bool(gear.has(id)).override_failure_message(id).is_true()
	var m: MapDef = Registry.map("red_canyon")
	if m != null and m.timeline != null:
		for p in m.timeline.specials.get("pool", []):
			var pid := str(p.get("enemy", "")) if p is Dictionary else str(p)
			assert_bool(gear.has(pid)).override_failure_message(pid).is_true()


# ---------------------------------------------------------------- a fresh ring: out before it closes

## Bodies and keys for creatures at absolute spots `at` (Vector3 list) seen from `me`, keys "k:<n>" from `base`.
static func _read(at: Array, me: Vector3, base: int = 0) -> Array:
	var bodies: Array = []
	var keys: Array = []
	for j in range(at.size()):
		var p: Vector3 = at[j]
		bodies.append(Vector4(p.x - me.x, p.z - me.z, 0.5, 1.0))
		keys.append("k:%d" % (base + j))
	return [bodies, keys]


## Two reads in one: `a` keyed from 0, `b` from `base_b` (keys stay with their creature from read to read).
static func _read_two(a: Array, b: Array, me: Vector3, base_b: int) -> Array:
	var ra := _read(a, me, 0)
	var rb := _read(b, me, base_b)
	return [(ra[0] as Array) + (rb[0] as Array), (ra[1] as Array) + (rb[1] as Array)]


static func _ring_at(n: int, radius: float, center: Vector3 = Vector3.ZERO) -> Array:
	var out: Array = []
	for k in range(n):
		out.append(center + BREAK.way_of(360.0 * float(k) / float(n)) * radius)
	return out


func test_a_fresh_ring_is_seen_and_crossed_before_it_closes() -> void:
	var bo = BREAK.new()
	var ctx := {"arena_r": 66.0, "obstacles": [], "lean": Vector3.ZERO}
	var dt := 1.0 / 30.0
	# the crowd already there (a few to the west): nobody is new on the first read
	var old: Array = [Vector3(-5, 0, 0), Vector3(-6, 0, 2), Vector3(-6, 0, -2), Vector3(-4, 0, 3), Vector3(-4, 0, -3)]
	var r: Array = _read(old, Vector3.ZERO)
	assert_vector(bo.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)).is_equal(Vector3.ZERO)
	assert_bool(bool(bo.fresh_ring(r[0], r[1])["ring"])).is_false()
	# a burst from one side (the north-east) is no ring
	var burst: Array = []
	for k in range(10):
		burst.append(BREAK.way_of(20.0 + 6.0 * float(k)) * 18.0)
	r = _read(old + burst, Vector3.ZERO)
	assert_vector(bo.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)).is_equal(Vector3.ZERO)
	var fb: Dictionary = bo.fresh_ring(r[0], r[1])
	assert_int(int(fb["n"])).is_equal(10)
	assert_bool(bool(fb["ring"])).is_false()
	# a ring of 24 comes up 16 m round him: out at once, the wall counted past its radius, the west (the old crowd) avoided
	var ring := _ring_at(24, 16.0)
	r = _read_two(old, ring, Vector3.ZERO, 100)
	var d: Vector3 = bo.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)
	assert_str(str(bo.last_event)).is_equal("started")
	assert_str(str(bo.kind)).is_equal("ring")
	assert_int(int(bo.seen["n"])).is_equal(24)
	assert_float(float(bo.seen["r"])).is_equal_approx(16.0, 0.01)
	assert_float(_deg_off(BREAK.deg_of(d), 270.0)).is_greater(60.0)
	# he runs; the ring closes at 2.4 m/s; the push ends once the ring is behind him by the margin, not before
	var me := Vector3.ZERO
	var pts: Array = ring.duplicate()
	var frames := 0
	var ended_at := -1.0
	while frames < 300:
		me += d * 5.0 * dt
		for j in range(pts.size()):
			var p: Vector3 = pts[j]
			var to: Vector3 = (me - p)
			to.y = 0.0
			if to.length() > 0.1:
				pts[j] = p + to.normalized() * 2.4 * dt
		r = _read_two(old, pts, me, 100)
		var dd: Vector3 = bo.update(dt, me, r[0], ctx, r[1], true)
		frames += 1
		if bo.last_event == "ended":
			ended_at = float(frames) * dt
			break
		assert_vector(dd).is_equal(d)
	assert_float(ended_at).is_greater(0.0)
	assert_str(str(bo.ended["why"])).is_equal("out")
	assert_bool(bo.ring_ahead(r[0], r[1], {})).is_false()
	# none of the ring stands ahead of him on his line now
	for j in range(old.size(), r[0].size()):
		var b: Vector4 = r[0][j]
		if absf(b.x * d.z - b.y * d.x) < BREAK.AHEAD_HALF + b.z:
			assert_float(b.x * d.x + b.y * d.z).is_less_equal(0.0)
	assert_dict(bo.tallies()).is_equal({"started": 1, "rings": 1, "out": 1, "timeout": 0})
	# a read after a long pause (past FRESH_GAP_S) makes nobody new
	var bo2 = BREAK.new()
	r = _read(old, Vector3.ZERO)
	bo2.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)
	bo2.update(BREAK.FRESH_GAP_S + 0.2, Vector3.ZERO, [], ctx, [], false)
	r = _read_two(old, ring, Vector3.ZERO, 200)
	assert_vector(bo2.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)).is_equal(Vector3.ZERO)
	# and one seen longer than FRESH_S is no longer new
	var bo3 = BREAK.new()
	r = _read(old, Vector3.ZERO)
	bo3.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)
	r = _read_two(old, ring, Vector3.ZERO, 300)
	bo3.cooldown = 10.0
	bo3.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)
	var tt := 0.0
	while tt < BREAK.FRESH_S + 0.1:
		bo3.update(dt, Vector3.ZERO, r[0], ctx, r[1], true)
		tt += dt
	assert_bool(bool(bo3.fresh_ring(r[0], r[1])["ring"])).is_false()


func test_the_arena_wall_closes_a_rings_gap() -> void:
	# near the east wall a ring's spots there are pressed onto the wall (nearer than the ring's radius): they leave a gap
	# in the ring at its distance, and the wall closes it
	var me := Vector3(55.0, 0.0, 0.0)
	var pts: Array = []
	for at: Vector3 in _ring_at(24, 16.0, me):
		var flat := Vector2(at.x, at.z)
		if flat.length() > 64.0:
			flat = flat.normalized() * 64.0
		pts.append(Vector3(flat.x, 0.0, flat.y))
	var bo = BREAK.new()
	var r := _read([], me)
	bo.update(1.0 / 30.0, me, r[0], {}, ["x"], true)
	r = _read(pts, me, 10)
	bo.observe(r[0], r[1])
	var open: Dictionary = bo.fresh_ring(r[0], r[1])
	assert_float(float(open["gap_deg"])).is_greater(BREAK.RING_GAP_MAX_DEG)
	assert_bool(bool(open["ring"])).is_false()
	var walled: Dictionary = bo.fresh_ring(r[0], r[1], me, 66.0)
	assert_bool(bool(walled["ring"])).is_true()
	assert_float(float(walled["gap_deg"])).is_less_equal(BREAK.RING_GAP_MIN_DEG)
