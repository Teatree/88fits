extends GdUnitTestSuite

## Pass 77, lane SIMRUN (Garry: "simulate like 10 players (editable) and the output is the average ... charts per
## second"): one simulated player's run of the real game (tools/sim_run.gd) and what it needs in the game. The bot's
## card priorities (card_tier, choose_card), the output's series from the recorder's rows (series, events_out), the
## launch set in memory (Run.launch_override: user://debug_launch.json is never touched), the recorder's in-memory mode
## (no analytics file) and its XP total, the dice seed (Run.seed_dice: CardPool's draws and the director's), and the
## difficulty probe's kiting autopilot moved into tools/sim_pilot.gd unchanged (against a frozen copy of pass 62's code).

const SIM := preload("res://tools/sim_run.gd")
const PILOT := preload("res://tools/sim_pilot.gd")
const LAUNCH := "user://debug_launch.json"
const SENTINEL := "{\"character\": \"astro\", \"note\": \"pass77 sentinel\"}"
const REPO_RUNS := "res://../analytics/runs"

var _launch_before = null


func before_test() -> void:
	_launch_before = null
	if FileAccess.file_exists(LAUNCH):
		_launch_before = FileAccess.get_file_as_string(LAUNCH)
	Run.launch_override = {}
	RunAnalytics.I = null


func after_test() -> void:
	Run.launch_override = {}
	Run.sim_mode = false
	Run.seed_dice(0)
	Run.forced_map_seed = 0
	get_tree().paused = false
	if Save.sandboxed():
		Save.end_sandbox()
	# the launch file as it was before the test (the sentinel never outlives it)
	if _launch_before == null:
		if FileAccess.file_exists(LAUNCH):
			DirAccess.remove_absolute(LAUNCH)
	else:
		var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
		f.store_string(str(_launch_before))
		f.close()
	RunAnalytics.I = null
	Run.end()


# ---------------------------------------------------------------- the bot's cards

func _first_passive(line: bool, evolved: bool = false) -> PassiveDef:
	var ids: Array = Registry.passives.keys()
	ids.sort()
	for id in ids:
		var p: PassiveDef = Registry.passives[id]
		if p.is_line() == line and p.is_evolved() == evolved and not p.hidden:
			return p
	return null


func test_card_tiers_follow_the_contract() -> void:
	var w: WeaponDef = Registry.weapon("peashooter")
	var line := _first_passive(true)
	var item := _first_passive(false)
	assert_object(line).is_not_null()
	assert_object(item).is_not_null()
	var perk: PerkDef = null
	for k in Registry.perks.keys():
		perk = Registry.perks[k]
		break
	assert_object(perk).is_not_null()
	# an evolution > the favourite > a new weapon > a held weapon's level > a perk > a new line > a line's level > a passive
	assert_int(SIM.card_tier({"type": "passive", "def": line, "evolve": true, "is_new": false})).is_equal(0)
	assert_int(SIM.card_tier({"type": "weapon", "def": w, "favourite": true, "is_new": true})).is_equal(1)
	assert_int(SIM.card_tier({"type": "weapon", "def": w, "is_new": true})).is_equal(2)
	assert_int(SIM.card_tier({"type": "weapon", "def": w, "is_new": false})).is_equal(3)
	assert_int(SIM.card_tier({"type": "perk", "def": perk, "is_new": true})).is_equal(4)
	assert_int(SIM.card_tier({"type": "passive", "def": line, "is_new": true})).is_equal(5)
	assert_int(SIM.card_tier({"type": "passive", "def": line, "is_new": false})).is_equal(6)
	assert_int(SIM.card_tier({"type": "passive", "def": item, "is_new": true})).is_equal(7)
	assert_int(SIM.card_tier({"type": "passive", "def": item, "is_new": false})).is_equal(7)
	# a favourite passive arriving is the favourite's tier too
	assert_int(SIM.card_tier({"type": "passive", "def": item, "favourite": true, "is_new": true})).is_equal(1)
	assert_int(SIM.card_tier({"type": "mystery"})).is_equal(8)
	# a pick event says what the card hands over (lane SIMUI's item_kind)
	assert_str(SIM.item_kind({"type": "passive", "def": line, "evolve": true})).is_equal("evolution")
	assert_str(SIM.item_kind({"type": "passive", "def": line})).is_equal("line")
	assert_str(SIM.item_kind({"type": "passive", "def": item})).is_equal("passive")
	assert_str(SIM.item_kind({"type": "weapon", "def": w})).is_equal("weapon")
	assert_str(SIM.item_kind({"type": "perk", "def": perk})).is_equal("perk")


func test_the_bot_takes_the_best_tier_and_breaks_ties_at_random() -> void:
	var w: WeaponDef = Registry.weapon("peashooter")
	var w2: WeaponDef = Registry.weapon("molotov")
	var item := _first_passive(false)
	var line := _first_passive(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var offer := [{"type": "passive", "id": item.id, "def": item, "is_new": true},
		{"type": "weapon", "id": w.id, "def": w, "is_new": false},
		{"type": "passive", "id": line.id, "def": line, "is_new": true}]
	assert_str(str(SIM.choose_card(offer, rng).get("id", ""))).is_equal(w.id)
	# two new weapons tie: over many draws both are taken, never the line beside them
	var seen := {}
	var tie := [{"type": "weapon", "id": w.id, "def": w, "is_new": true}, {"type": "weapon", "id": w2.id, "def": w2, "is_new": true},
		{"type": "passive", "id": line.id, "def": line, "is_new": true}]
	for k in range(40):
		seen[str(SIM.choose_card(tie, rng).get("id", ""))] = true
	assert_bool(seen.has(w.id) and seen.has(w2.id)).is_true()
	assert_bool(seen.has(line.id)).is_false()
	assert_dict(SIM.choose_card([], rng)).is_empty()


# ---------------------------------------------------------------- the output

func _row(t: float, extra: Dictionary) -> Dictionary:
	var r := {"t": t, "clock": t, "stage": 1, "level": 1, "hp": 100.0, "hp_max": 100.0}
	r.merge(extra, true)
	return r


func test_the_series_follow_the_rows() -> void:
	var rows := [
		_row(1.0, {"dmg": {"revolver": 10.0}, "killed": {"goblin": 2}, "gold_in": {"coins": 3}, "alive": 5, "alive_by": {"goblin": 5}, "kills": 2, "xp_total": 4.0, "est_total": 20.0, "took": {"goblin": 3.0}, "healed": 1.0, "regen": 0.5,
			"hits": 2, "spawned": {"goblin": 4, "skeleton": 1}, "healed_by": {"heart": 1.0}, "mults": {"stage": 1.0, "hp_t": 1.5, "lvl_hp": 1.2, "dmg_t": 1.1, "lvl_dmg": 1.0},
			"weapons": [{"id": "revolver"}, {"id": "golden_revolver"}], "lines": {"brawn": 1}, "passives": {"beer": 1, "cake": 2}, "perks": ["high_noon"]}),
		_row(2.0, {"dmg": {"revolver": 5.0, "powder_keg": 7.5}, "killed": {"goblin": 1, "skeleton": 1}, "alive": 6, "alive_by": {"goblin": 4, "skeleton": 2}, "kills": 4, "xp_total": 9.0}),
		_row(3.0, {"gold_in": {"elite_purse": 450}, "kills": 4, "level": 2, "xp_total": 9.0, "phase": 1, "boss_hp": 0.5, "boss_now": 800.0, "cap": 40, "press_hp": 1234.5, "press_dmg": 67.8, "near3": 2, "near6": 7}),
		# a run that ended between two seconds: its part-second closes as the next whole second
		_row(3.4, {"dmg": {"revolver": 1.0}, "kills": 4, "level": 2}),
	]
	var rec := [{"t": 0.0, "clock": 0.0, "kind": "stage", "level": 1}, {"t": 1.5, "clock": 1.5, "kind": "level", "level": 2},
		{"t": 2.5, "clock": 2.5, "kind": "death", "id": "goblin", "hit": "melee"}, {"t": 2.6, "clock": 2.6, "kind": "revive", "id": "gold"},
		{"t": 2.7, "clock": 2.7, "kind": "boss_start", "id": "tumbleweed_king", "hp": 5000.0, "mult": 0.9, "window": 45.0},
		{"t": 2.8, "clock": 2.8, "kind": "offer", "id": "molotov"}]
	var mine := [{"t": 2.6, "clock": 2.6, "kind": "assist", "what": "portal"}]
	var out: Dictionary = SIM.series(rows, rec, mine, {"t": 3.4, "clock": 3.4, "kind": "end", "reason": "death"}, {"golden_revolver": true})
	assert_array(out["t"]).is_equal([1, 2, 3, 4])
	for k in ["clock", "stage", "phase", "hp", "hp_max", "dps", "est", "alive", "cap", "press_hp", "press_dmg", "boss_hp", "boss_hp_abs",
			"near3", "near6", "hits", "spawned", "mult_hp", "mult_dmg", "gold_total", "gold", "dmg_total", "kills", "level", "xp_total", "took",
			"healed", "deaths"]:
		assert_int((out[k] as Array).size()).override_failure_message(k).is_equal(4)
	assert_array(out["dps"]).is_equal([10.0, 12.5, 0.0, 1.0])
	assert_array(out["dmg_total"]).is_equal([10.0, 22.5, 22.5, 23.5])
	assert_array(out["gold_total"]).is_equal([3, 3, 453, 453])
	assert_array(out["kills"]).is_equal([2, 4, 4, 4])
	assert_array(out["xp_total"]).is_equal([4.0, 9.0, 9.0, 0.0])
	assert_array(out["deaths"]).is_equal([0, 0, 1, 1])
	assert_array(out["took"]).is_equal([3.0, 0.0, 0.0, 0.0])
	assert_array(out["healed"]).is_equal([1.5, 0.0, 0.0, 0.0])
	assert_array(out["phase"]).is_equal([0, 0, 1, 0])
	# the boss's share of its health (the row's boss_hp) and the health itself (boss_now); the crowd close by
	assert_array(out["boss_hp"]).is_equal([0.0, 0.0, 0.5, 0.0])
	assert_array(out["boss_hp_abs"]).is_equal([0.0, 0.0, 800.0, 0.0])
	assert_array(out["near3"]).is_equal([0, 0, 2, 0])
	assert_array(out["near6"]).is_equal([0, 0, 7, 0])
	# lane SIMUI's round 2: hits, spawns, the spawn multipliers carried, what hurt and what healed (cumulative), the build
	assert_array(out["hits"]).is_equal([2, 0, 0, 0])
	assert_array(out["spawned"]).is_equal([5, 0, 0, 0])
	assert_array(out["mult_hp"]).is_equal([1.8, 1.8, 1.8, 1.8])
	assert_array(out["mult_dmg"]).is_equal([1.1, 1.1, 1.1, 1.1])
	assert_array(out["took_by"]["goblin"]).is_equal([3.0, 3.0, 3.0, 3.0])
	assert_array(out["healed_by"]["heart"]).is_equal([1.0, 1.0, 1.0, 1.0])
	assert_array(out["healed_by"]["regen"]).is_equal([0.5, 0.5, 0.5, 0.5])
	assert_array(out["held_by"]["weapons"]).is_equal([1, 1, 1, 1])
	assert_array(out["held_by"]["evolutions"]).is_equal([1, 1, 1, 1])
	assert_array(out["held_by"]["lines"]).is_equal([1, 1, 1, 1])
	assert_array(out["held_by"]["passives"]).is_equal([2, 2, 2, 2])
	assert_array(out["held_by"]["perks"]).is_equal([1, 1, 1, 1])
	# the breakdowns: cumulative, aligned, zero before an id first appears
	assert_array(out["dmg_by"]["revolver"]).is_equal([10.0, 15.0, 15.0, 16.0])
	assert_array(out["dmg_by"]["powder_keg"]).is_equal([0, 7.5, 7.5, 7.5])
	assert_array(out["kills_by"]["skeleton"]).is_equal([0, 1, 1, 1])
	assert_array(out["kills_by"]["goblin"]).is_equal([2, 3, 3, 3])
	assert_array(out["gold_by"]["elite_purse"]).is_equal([0, 0, 450, 450])
	# alive by creature is a count of the second, not a sum
	assert_array(out["alive_by"]["goblin"]).is_equal([5, 4, 0, 0])
	assert_array(out["alive_by"]["skeleton"]).is_equal([0, 2, 0, 0])
	assert_dict(out["sums"]).is_equal({"rows": 4, "deaths": 1, "gold_total": 453})
	# the events say what their number is, the tool's join them in time order, the end closes them; an offer is not one
	var kinds: Array = (out["events"] as Array).map(func(e): return str(e["kind"]))
	assert_array(kinds).is_equal(["stage", "level", "death", "revive", "assist", "boss_start", "end"])
	var ev: Array = out["events"]
	assert_int(int(ev[0]["stage"])).is_equal(1)
	assert_int(int(ev[1]["level"])).is_equal(2)
	assert_str(str(ev[2]["killer"])).is_equal("goblin")
	assert_str(str(ev[3]["via"])).is_equal("gold")
	assert_float(float(ev[5]["hp"])).is_equal(5000.0)
	assert_str(str(ev[6]["reason"])).is_equal("death")
	# JSON-ready: a round trip keeps every series
	var back = JSON.parse_string(JSON.stringify(out))
	assert_bool(back is Dictionary and (back["t"] as Array).size() == 4).is_true()


# ---------------------------------------------------------------- the game's side: launch, recorder, dice

func _analytics_files() -> int:
	var n := 0
	for dir in ["user://analytics/runs", ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("analytics/runs/tools")]:
		if DirAccess.dir_exists_absolute(dir):
			n += DirAccess.get_files_at(dir).size()
	return n


func test_a_launch_in_memory_leaves_the_file_and_writes_no_record() -> void:
	Save.begin_sandbox()
	# someone's launch file lies there: the run sim's launch must neither read nor remove it
	var f := FileAccess.open(LAUNCH, FileAccess.WRITE)
	f.store_string(SENTINEL)
	f.close()
	var files_before := _analytics_files()
	Run.seed_dice(5)
	Run.launch_override = {"character": "drifter", "map": "red_canyon", "map_seed": 5, "analytics_memory": true}
	var g: Game = load("res://game/Game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	assert_dict(Run.launch_override).is_empty()
	assert_str(Run.character.id).is_equal("drifter")
	assert_int(Run.map_seed).is_equal(5)
	assert_bool(FileAccess.file_exists(LAUNCH)).is_true()
	assert_str(FileAccess.get_file_as_string(LAUNCH)).is_equal(SENTINEL)
	# the director's dice follow the seed
	assert_int(int(g.director._rng.seed)).is_equal(hash([5, "director"]))
	var ra: RunAnalytics = RunAnalytics.I
	assert_object(ra).is_not_null()
	assert_bool(ra.memory_only).is_true()
	g.player.god = true
	# every XP point gained is summed (after Field Notes; this hero has none)
	Run.add_xp(4.0)
	Run.add_xp(6.0)
	assert_float(ra.xp_total).is_equal_approx(10.0 * Run.player_sheet.get_stat("xp_gain", 1.0), 0.001)
	await get_tree().create_timer(2.6).timeout
	assert_int(ra.samples.size()).is_greater_equal(2)
	assert_float(float((ra.samples[ra.samples.size() - 1] as Dictionary).get("xp_total", 0.0))).is_equal_approx(ra.xp_total, 0.05)
	# the series from the run's own rows: aligned, whole seconds rising (a test's frames are real time: a row may close a
	# frame past its second)
	var out: Dictionary = SIM.series(ra.samples, ra.events, [], {})
	var t: Array = out["t"]
	assert_int(t.size()).is_equal(ra.samples.size())
	for i in range(t.size()):
		assert_bool(t[i] is int).is_true()
		assert_float(absf(float(t[i]) - float((ra.samples[i] as Dictionary)["t"]))).is_less(1.0)
		if i > 0:
			assert_int(int(t[i])).is_greater(int(t[i - 1]))
	assert_int((out["hp"] as Array).size()).is_equal(t.size())
	assert_float(float(out["hp_max"][0])).is_greater(0.0)
	# the end that would write the record writes nothing; nor does the game going away
	ra.finish()
	g.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_analytics_files()).is_equal(files_before)
	assert_str(FileAccess.get_file_as_string(LAUNCH)).is_equal(SENTINEL)


func test_without_the_memory_mode_the_recorder_writes_as_before() -> void:
	var ra := RunAnalytics.new()
	assert_bool(ra.memory_only).is_false()
	ra.free()
	var src := FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd")
	assert_bool(src.contains("ra.memory_only = bool(launch.get(\"analytics_memory\", false))")).is_true()
	assert_bool(src.contains("if memory_only:\n\t\treturn \"\"")).is_true()
	# the launch file is still read (and removed) when nothing is set in memory
	var game := FileAccess.get_file_as_string("res://game/Game.gd")
	assert_bool(game.contains("if not Run.launch_override.is_empty():")).is_true()
	assert_bool(game.contains("DirAccess.remove_absolute(\"user://debug_launch.json\")")).is_true()


func test_the_bot_keeps_near_a_living_boss() -> void:
	var me := Vector3.ZERO
	assert_bool(SIM.boss_goal(me, Vector3.INF, false).is_empty()).is_true()
	assert_bool(SIM.boss_goal(me, Vector3(SIM.BOSS_LEASH - 1.0, 0, 0), false).is_empty()).is_true()
	var g: Dictionary = SIM.boss_goal(me, Vector3(SIM.BOSS_LEASH + 1.0, 0, 0), false)
	assert_str(str(g.get("what", ""))).is_equal("boss")
	assert_bool(bool(g.get("must", true))).is_false()
	# once walking back he goes on until BOSS_BACK
	var mid := Vector3((SIM.BOSS_LEASH + SIM.BOSS_BACK) * 0.5, 0, 0)
	assert_bool(SIM.boss_goal(me, mid, true).is_empty()).is_false()
	assert_bool(SIM.boss_goal(me, mid, false).is_empty()).is_true()
	assert_bool(SIM.boss_goal(me, Vector3(SIM.BOSS_BACK - 0.5, 0, 0), true).is_empty()).is_true()
	# gems and chests count only within the leash while a boss lives
	assert_bool(SIM.within_leash(Vector3(SIM.BOSS_LEASH + 2.0, 0, 0), Vector3.ZERO)).is_false()
	assert_bool(SIM.within_leash(Vector3(SIM.BOSS_LEASH - 2.0, 0, 0), Vector3.ZERO)).is_true()
	assert_bool(SIM.within_leash(Vector3(500, 0, 0), Vector3.INF)).is_true()


func test_seed_dice_repeats_the_draws() -> void:
	Run.seed_dice(9)
	assert_int(Run.rng_seed).is_equal(9)
	assert_object(CardPool.rng).is_not_null()
	var a := [CardPool.rng.randf(), CardPool.rng.randf(), randf()]
	Run.seed_dice(9)
	var b := [CardPool.rng.randf(), CardPool.rng.randf(), randf()]
	assert_array(b).is_equal(a)
	# the offers' own draw: the same seed draws the same cards from the same pool
	var pool: Array = []
	for k in range(12):
		pool.append({"type": "passive", "id": "c%d" % k, "weight": 1.0 + float(k % 3)})
	Run.seed_dice(3)
	var p1: Array = CardPool._pick(pool, 3).map(func(c): return c["id"])
	Run.seed_dice(3)
	var p2: Array = CardPool._pick(pool, 3).map(func(c): return c["id"])
	assert_array(p2).is_equal(p1)
	# the Totem Poles' gifts and the structures' places follow the seed too
	Run.seed_dice(5)
	var g1 := Run.totem_rng.randi()
	Run.seed_dice(5)
	assert_int(Run.totem_rng.randi()).is_equal(g1)
	for pair in [["res://core/systems/StructureManager.gd", "_rng.seed = hash([Run.rng_seed, \"structures\"])"],
			["res://game/Game.gd", "TOTEM_SCREEN.BOONS.offer(def, Run.totem_rng)"]]:
		assert_bool(FileAccess.get_file_as_string(str(pair[0])).contains(str(pair[1]))).override_failure_message(str(pair[0])).is_true()
	Run.seed_dice(0)
	assert_int(Run.rng_seed).is_equal(0)
	assert_object(CardPool.rng).is_null()
	assert_object(Run.totem_rng).is_null()


# ---------------------------------------------------------------- the probe's autopilot, moved

class FakeInput:
	extends RefCounted
	var wants_move := false
	var origin := Vector2.ZERO
	var touch_pos := Vector2.ZERO


class FakeDef:
	extends RefCounted
	var id := ""
	var archetype := ""

	func _init(i: String, a: String) -> void:
		id = i
		archetype = a


class FakeEnemies:
	extends RefCounted
	var MAX := 12
	var alive := PackedByteArray()
	var pos := PackedVector3Array()
	var types: Array = []
	var type_idx := PackedInt32Array()


class FakeProjectiles:
	extends RefCounted
	var rocket_of := {}
	var alive := PackedByteArray()
	var pos := PackedVector3Array()


class FakeMap:
	extends RefCounted
	var flats_center := Vector3(3, 0, -2)
	var arena_radius := 30.0
	var obstacles: Array = []


class FakePlayer:
	extends Node3D
	var input := FakeInput.new()
	var hp := 0.0
	var max_hp := 0.0


class FakeGame:
	extends Node
	var player: FakePlayer
	var enemies := FakeEnemies.new()
	var projectiles := FakeProjectiles.new()
	var map := FakeMap.new()
	var paused := false
	var telegraphs: RefCounted = null


## Pass 62's autopilot as difficulty_probe.gd had it before pass 77 (frozen here: the moved one must match it frame by
## frame). `s` holds its state: rng, strafe, strafe_t.
func _ref_steer(game, s: Dictionary, dt: float, t: float) -> void:
	var p: Node3D = game.player
	var inp = p.input
	if inp == null or game.paused:
		return
	var em = game.enemies
	var me: Vector3 = p.global_position
	var away := Vector3.ZERO
	var nearest := INF
	var toward := Vector3.ZERO
	for i in range(em.MAX):
		if em.alive[i] != 1:
			continue
		var d: Vector3 = me - em.pos[i]
		d.y = 0.0
		var l2 := d.length_squared()
		if l2 < nearest:
			nearest = l2
			toward = -d
		if l2 > 100.0 or l2 < 0.0001:
			continue
		away += d / l2
	nearest = sqrt(nearest) if nearest < INF else INF
	var danger := Vector3.ZERO
	for i in range(em.MAX):
		if em.alive[i] != 1:
			continue
		var def = em.types[em.type_idx[i]]["def"]
		if not (def.id in ["hammer_giant", "bull_beetle"] or def.archetype == "elite" or def.archetype == "boss"):
			continue
		var dd: Vector3 = me - em.pos[i]
		dd.y = 0.0
		var l2 := dd.length_squared()
		if l2 < 49.0 and l2 > 0.0001:
			danger += dd / l2 * 6.0
	var pm = game.projectiles
	if pm:
		for pi in pm.rocket_of.keys():
			var k := int(pi)
			if pm.alive[k] != 1:
				continue
			var dr: Vector3 = me - pm.pos[k]
			dr.y = 0.0
			if dr.length_squared() < 100.0 and dr.length_squared() > 0.0001:
				danger += dr.normalized() * 3.0
	away += danger
	s["strafe_t"] = float(s["strafe_t"]) - dt
	if float(s["strafe_t"]) <= 0.0:
		s["strafe_t"] = (s["rng"] as RandomNumberGenerator).randf_range(3.0, 7.0)
		s["strafe"] = -float(s["strafe"])
	var dir := Vector3.ZERO
	if away.length() > 0.0001:
		var a := away.normalized()
		var side := Vector3(-a.z, 0, a.x) * float(s["strafe"])
		if danger.length() > 0.4:
			dir = a + side * 0.25
		elif nearest < 2.6:
			dir = a + side * 0.5
		elif nearest < 4.5:
			dir = side + a * 0.35
		else:
			dir = side - a * 0.4
	elif toward.length() > 0.001:
		dir = toward.normalized()
	else:
		dir = Vector3(sin(t * 0.4), 0, cos(t * 0.4))
	var mb = game.map
	if mb:
		var c: Vector3 = mb.flats_center if mb.get("flats_center") != null else Vector3.ZERO
		var to_c: Vector3 = c - me
		to_c.y = 0.0
		var r: float = mb.arena_radius if mb.get("arena_radius") != null else 60.0
		var k := clampf((to_c.length() - r * 0.45) / (r * 0.4), 0.0, 1.5)
		if to_c.length() > 0.01:
			dir += to_c.normalized() * k * 1.4
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	inp.wants_move = true
	inp.origin = Vector2(216, 500)
	inp.touch_pos = inp.origin + Vector2(dir.x, dir.z) * 120.0


func _fake_game() -> FakeGame:
	var g: FakeGame = auto_free(FakeGame.new())
	g.player = FakePlayer.new()
	add_child(g)
	g.add_child(g.player)
	var em := g.enemies
	em.alive.resize(em.MAX)
	em.pos.resize(em.MAX)
	em.type_idx.resize(em.MAX)
	em.types = [{"def": FakeDef.new("goblin", "melee")}, {"def": FakeDef.new("hammer_giant", "melee")}, {"def": FakeDef.new("dune_scorpion", "elite")}]
	var pm := g.projectiles
	pm.alive.resize(4)
	pm.pos.resize(4)
	return g


func test_the_probe_steers_exactly_as_before() -> void:
	var g := _fake_game()
	var pilot = PILOT.new(11)
	var ref := {"rng": RandomNumberGenerator.new(), "strafe": 1.0, "strafe_t": 0.0}
	(ref["rng"] as RandomNumberGenerator).seed = 11
	var dice := RandomNumberGenerator.new()
	dice.seed = 77
	var em := g.enemies
	var t := 0.0
	var mine := FakeInput.new()
	for frame in range(400):
		var dt := 1.0 / 60.0
		t += dt
		# a fresh scene every few frames: creatures (some big, an Elite) near and far, a rocket now and then, the hero
		# wandering towards the wall
		if frame % 7 == 0:
			for i in range(em.MAX):
				em.alive[i] = 1 if dice.randf() < 0.6 else 0
				em.pos[i] = Vector3(dice.randf_range(-14, 14), 0, dice.randf_range(-14, 14))
				em.type_idx[i] = dice.randi() % em.types.size()
			g.projectiles.rocket_of = {}
			for k in range(4):
				g.projectiles.alive[k] = 1 if dice.randf() < 0.3 else 0
				g.projectiles.pos[k] = Vector3(dice.randf_range(-12, 12), 0, dice.randf_range(-12, 12))
				if g.projectiles.alive[k] == 1:
					g.projectiles.rocket_of[k] = 0
			g.player.position = Vector3(dice.randf_range(-25, 25), 0, dice.randf_range(-25, 25))
		if frame == 200:
			for i in range(em.MAX):
				em.alive[i] = 0
		g.player.input = mine
		pilot.steer(g, dt, t)
		var got := mine.touch_pos
		var ref_in := FakeInput.new()
		g.player.input = ref_in
		_ref_steer(g, ref, dt, t)
		assert_vector(got).override_failure_message("frame %d" % frame).is_equal(ref_in.touch_pos)
		assert_float(float(pilot.strafe)).is_equal(float(ref["strafe"]))
	# the probe steers through it
	var probe := FileAccess.get_file_as_string("res://tools/difficulty_probe.gd")
	assert_bool(probe.contains("_pilot = PILOT.new(_seed)")).is_true()
	assert_bool(probe.contains("_pilot.steer(_game, dt, _t)")).is_true()


func test_the_walk_to_a_goal_heads_for_it() -> void:
	var g := _fake_game()
	var pilot = PILOT.new(3)
	g.player.position = Vector3(0, 0, 0)
	var goal := Vector3(10, 0, 0)
	var d: float = pilot.steer_to(g, 1.0 / 60.0, goal)
	assert_float(d).is_equal_approx(10.0, 0.001)
	var inp: FakeInput = g.player.input
	assert_bool(inp.wants_move).is_true()
	var v := (inp.touch_pos - inp.origin).normalized()
	assert_float(v.x).is_greater(0.99)
	# a creature in the way, far from the goal, turns him aside; at the goal's edge he walks straight in
	g.enemies.alive[0] = 1
	g.enemies.pos[0] = Vector3(1.5, 0, 0.4)
	g.enemies.type_idx[0] = 0
	pilot.steer_to(g, 1.0 / 60.0, goal)
	var v2 := (inp.touch_pos - inp.origin).normalized()
	assert_float(v2.x).is_less(0.99)
	g.player.position = Vector3(9.0, 0, 0)
	g.enemies.pos[0] = Vector3(9.5, 0, 0.6)
	pilot.steer_to(g, 1.0 / 60.0, goal)
	var v3 := (inp.touch_pos - inp.origin).normalized()
	assert_float(v3.x).is_greater(0.99)


func test_the_sweep_leans_to_the_lure_only_when_safe() -> void:
	var g := _fake_game()
	var inp: FakeInput = g.player.input
	g.player.position = Vector3.ZERO
	g.player.hp = 100.0
	g.player.max_hp = 100.0
	var lure := Vector3(6, 0, 0)
	# no creature, whole health: the lean pulls him east
	PILOT.new(5).steer_sweep(g, 1.0 / 60.0, 1.0, lure)
	assert_float((inp.touch_pos - inp.origin).normalized().x).is_greater(0.5)
	# a hammer giant close by (the probe's danger): no lean at all, the kite's way exactly
	g.enemies.alive[0] = 1
	g.enemies.pos[0] = Vector3(-2.0, 0, 1.0)
	g.enemies.type_idx[0] = 1
	PILOT.new(5).steer_sweep(g, 1.0 / 60.0, 1.0, lure)
	var swept := inp.touch_pos
	PILOT.new(5).steer(g, 1.0 / 60.0, 1.0)
	assert_vector(inp.touch_pos).is_equal(swept)
	# a goblin there instead, but the hero at a third of his health: no lean either
	g.enemies.type_idx[0] = 0
	g.player.hp = 30.0
	PILOT.new(5).steer_sweep(g, 1.0 / 60.0, 1.0, lure)
	swept = inp.touch_pos
	PILOT.new(5).steer(g, 1.0 / 60.0, 1.0)
	assert_vector(inp.touch_pos).is_equal(swept)
	# a creature in the lane: only a share of the lean
	g.player.hp = 100.0
	assert_bool(PILOT.lane_clear(g, Vector3.ZERO, lure)).is_true()
	g.enemies.pos[0] = Vector3(2.0, 0, 0.5)
	assert_bool(PILOT.lane_clear(g, Vector3.ZERO, lure)).is_false()


class FakeTelegraphs:
	extends RefCounted
	var _items: Array = []


func test_a_red_warning_under_him_pushes_him_out() -> void:
	var g := _fake_game()
	var tg := FakeTelegraphs.new()
	g.telegraphs = tg
	var me := Vector3(1.0, 0, 0)
	# a boulder's landing ring round (0, 0, 0), 4.6 m, winding up: out, away from its middle
	tg._items = [{"pool": "band", "mode": 1, "t": 0.2, "dur": 1.6, "dead": false, "r": 4.6, "at": Vector3.ZERO, "col": Color(0.93, 0.29, 0.36, 0.85)}]
	var push: Vector3 = PILOT.ring_push(g, me)
	assert_float(push.x).is_greater(1.0)
	assert_float(absf(push.z)).is_less(0.001)
	# outside it, a gold flash ring, a spent one, a green one: nothing
	assert_vector(PILOT.ring_push(g, Vector3(7.0, 0, 0))).is_equal(Vector3.ZERO)
	tg._items = [{"pool": "band", "mode": 1, "t": 0.1, "dur": 0.4, "dead": false, "r": 3.0, "at": Vector3.ZERO, "col": Color(1.0, 0.82, 0.35, 0.85)},
		{"pool": "band", "mode": 1, "t": 2.0, "dur": 1.6, "dead": false, "r": 4.6, "at": Vector3.ZERO, "col": Color(0.93, 0.29, 0.36, 0.85)},
		{"pool": "band", "mode": 1, "t": 0.1, "dur": 1.0, "dead": false, "r": 4.0, "at": Vector3.ZERO, "col": Color(0.45, 0.9, 0.55, 0.85)}]
	assert_vector(PILOT.ring_push(g, me)).is_equal(Vector3.ZERO)
	# a red line (the King's roll along +x, 16.6 m, 1.2 m wide): off its axis, sideways; past its ends or clear of it, nothing
	tg._items = [{"pool": "strip", "mode": 0, "t": 0.2, "dur": 1.0, "dead": false, "r": 16.6, "at": Vector3.ZERO,
		"col": Color(0.93, 0.29, 0.36, 0.6), "k": Color(1.0, 0.0, 16.6, 1.2)}]
	var side: Vector3 = PILOT.ring_push(g, Vector3(5.0, 0, 0.3))
	assert_float(side.z).is_greater(1.0)
	assert_float(absf(side.x)).is_less(0.001)
	assert_float(PILOT.ring_push(g, Vector3(5.0, 0, -0.3)).z).is_less(-1.0)
	for spot in [Vector3(5.0, 0, 2.0), Vector3(20.0, 0, 0.0), Vector3(-2.0, 0, 0.0)]:
		assert_vector(PILOT.ring_push(g, spot)).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------- the lead's additions (Garry looked at the Sim tab)

func test_talents_are_read_rank_by_rank() -> void:
	var known: Array = Registry.talents.keys()
	# lane SIMUI's format: one form a rank, exactly Save.data.talents[id].picks (0/1, or A/B)
	var t: Dictionary = SIM.parse_talents("grit:000,drive:1,nerve:11,stride:AAB", known)
	assert_array(t["grit"]).is_equal([0, 0, 0])
	assert_array(t["drive"]).is_equal([1])
	assert_array(t["nerve"]).is_equal([1, 1])
	assert_array(t["stride"]).is_equal([0, 0, 1])
	assert_bool(t.has("fortune")).is_false()
	# every rank in one form, and the empty board
	assert_array(SIM.parse_talents("spite:2:1", known)["spite"]).is_equal([1, 1])
	assert_array(SIM.parse_talents("study:9:A", known)["study"]).is_equal([0, 0, 0, 0, 0, 0])
	assert_dict(SIM.parse_talents("none", known)).is_empty()
	assert_bool(SIM.parse_talents("nope:00", known).has("error")).is_true()
	assert_bool(SIM.parse_talents("grit:2:C", known).has("error")).is_true()
	assert_bool(SIM.parse_talents("grit:0000000", known).has("error")).is_true()
	assert_bool(SIM.parse_talents("grit:012", known).has("error")).is_true()
	# what the game reads back: Save.talent_picks over the board as the runner writes it
	Save.begin_sandbox()
	Save.data["talents"] = {"drive": {"picks": [1, 1], "rank": 2, "form": 1}, "stride": {"picks": [0, 0, 1], "rank": 3, "form": 1}}
	assert_array(Save.talent_picks("drive")).is_equal([1, 1])
	assert_int(Save.talent_rank("stride")).is_equal(3)
	assert_int(Save.talent_count("stride", 1)).is_equal(1)


class FakeButton:
	extends Control
	var locked := false


class FakeRevive:
	extends Control
	var _ad_btn: Control = null


func test_the_ad_revive_is_taken_only_while_offered() -> void:
	var rs: FakeRevive = auto_free(FakeRevive.new())
	add_child(rs)
	assert_bool(SIM.ad_offered(rs)).is_false()
	var b := FakeButton.new()
	rs._ad_btn = b
	rs.add_child(b)
	assert_bool(SIM.ad_offered(rs)).is_true()
	b.locked = true
	assert_bool(SIM.ad_offered(rs)).is_false()
	b.locked = false
	b.visible = false
	assert_bool(SIM.ad_offered(rs)).is_false()
	assert_bool(SIM.ad_offered(null)).is_false()


func test_the_fast_mode_skips_the_drawing_and_keeps_the_numbers() -> void:
	Run.sim_mode = true
	# Fx makes nothing at all
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	fx.set_process(false)
	var n0: int = fx._n
	fx._emit(Vector3.ZERO, Vector3.UP, 1.0, 0.2, 0.1, 1.0, 0.0, Color.WHITE, 0.0, false, true)
	fx.burst(Vector3.ZERO, Color.WHITE)
	assert_int(fx._n).is_equal(n0)
	# the ground marks still age (the bot reads the warnings), only their drawing is skipped
	var tg: Telegraphs = auto_free(Telegraphs.new())
	add_child(tg)
	tg.set_process(false)
	tg.ring(Vector3.ZERO, 3.0, 1.0, Color(0.93, 0.29, 0.36))
	tg._process(0.25)
	var items: Array = tg._items
	assert_bool(items.is_empty()).is_false()
	assert_float(float((items[0] as Dictionary)["t"])).is_equal_approx(0.25, 0.0001)
	# the sheet's rebuild throttle reads the buffs' clock
	Run.elapsed = 12.5
	Run.held_time = 0.0
	assert_int(Run._rebuild_clock_ms()).is_equal(12500)
	Run.sim_mode = false
	# pass 102 (lane STEADY): in play the game's own clock (Run.play_clock, the frames' deltas), no longer the wall clock,
	# re-pinned on purpose (pass102_steady_test)
	assert_int(Run._rebuild_clock_ms()).is_equal(int(Run.play_clock * 1000.0))
	assert_float(Run.rule_seconds()).is_equal(Run.play_clock)
	# every run sim (either mode) counts the run's clock where a rule counts real time (an orbiter's repeat hits too)
	Run.sim_clock = true
	assert_int(Run._rebuild_clock_ms()).is_equal(12500)
	assert_float(Run.rule_seconds()).is_equal_approx(12.5, 0.0001)
	Run.sim_clock = false
	Run.elapsed = 0.0
	# every guard sits where the drawing or the sound starts
	for pair in [["res://core/systems/EnemyManager.gd", "if player == null or _drawn == _ticks or Run.sim_mode:"],
			["res://core/systems/ProjectileManager.gd", "if game == null or _drawn == _ticks or Run.sim_mode:"],
			["res://core/systems/PickupManager.gd", "if game == null or _drawn == _ticks or Run.sim_mode:"],
			["res://core/autoload/Audio.gd", "if Run.sim_mode:
		return
	var row := Registry.soundmap.entry(id)"],
			["res://ui/HUD.gd", "if Run.sim_mode:"], ["res://ui/DamageNumbers.gd", "if Run.sim_mode:"],
			["res://game/Game.gd", "Run.sim_mode = bool(debug_launch.get(\"sim_fast\", false))"],
			["res://game/Game.gd", "Run.sim_clock = bool(debug_launch.get(\"sim_clock\", false))"],
			["res://core/behaviors/Orbiter.gd", "var now := Run.rule_seconds()"],
			# the companions' bob places what fires (the Big Mouth's beam starts at its mouth): the run's clock in a sim
			["res://core/behaviors/LaserBeam.gd", "var t := Run.rule_seconds()"],
			["res://core/behaviors/WeaponBehavior.gd", "var t := Run.rule_seconds()"],
			["res://tools/sim_run.gd", "\"sim_clock\": true"]]:
		assert_bool(FileAccess.get_file_as_string(str(pair[0])).contains(str(pair[1]))).override_failure_message(str(pair[0])).is_true()


func test_a_run_without_the_launch_key_is_never_fast() -> void:
	Save.begin_sandbox()
	Run.sim_mode = true
	Run.launch_override = {"character": "drifter", "map": "red_canyon", "map_seed": 3, "analytics_memory": true}
	var g: Game = load("res://game/Game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	assert_bool(Run.sim_mode).is_false()
	assert_bool(Run.sim_clock).is_false()
	g.queue_free()
	await get_tree().process_frame
	Run.launch_override = {"character": "drifter", "map": "red_canyon", "map_seed": 3, "analytics_memory": true, "sim_fast": true,
			"sim_clock": true}
	g = load("res://game/Game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	assert_bool(Run.sim_mode).is_true()
	assert_bool(Run.sim_clock).is_true()
	# the recorder's new keys: the crowd close by and the second's loss and healing (zero values are left out)
	g.player.god = true
	await get_tree().create_timer(1.3).timeout
	var ra: RunAnalytics = RunAnalytics.I
	assert_int(ra.samples.size()).is_greater_equal(1)
	var src := FileAccess.get_file_as_string("res://core/systems/RunAnalytics.gd")
	for key in ["\"near3\"", "\"near6\"", "\"hp_lost\"", "\"hp_healed\"", "\"boss_now\""]:
		assert_bool(src.contains(key)).override_failure_message(key).is_true()
	g.queue_free()
	await get_tree().process_frame
	Run.sim_mode = false
	Run.sim_clock = false
