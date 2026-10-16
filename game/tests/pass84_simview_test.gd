extends GdUnitTestSuite

## Pass 84, lane SIMVIEW (Garry's Timeline overlays the Sim): tools/sim_run.gd's own sampler for the Timeline (alive by
## channel, the regular load against the cap, cap-full shares, starving rows, the crowd's threat and the challenge,
## creature lifetimes). Its pieces are static and checked here on stand-ins; the whole is proved by a sim (tools/dl/p84/
## history_SIMVIEW.md). Definitions: tools/dl/p84/balancing_SIMVIEW.md.

const SIM := preload("res://tools/sim_run.gd")


## A stand-in crowd with the arrays crowd_now reads.
class Crowd:
	const STATE_DYING := 3
	var alive := PackedByteArray()
	var state := PackedInt32Array()
	var type_idx := PackedInt32Array()
	var max_hp := PackedFloat32Array()
	var dmg := PackedFloat32Array()
	var _t_ccd := PackedFloat32Array()
	var types: Array = []
	var boss_index := -1

	func add_type(id: String, share: float, ccd: float) -> int:
		var d := EnemyDef.new()
		d.id = id
		types.append({"def": d, "share": share})
		_t_ccd.append(ccd)
		return types.size() - 1

	func add(ti: int, hp: float, bite: float, st := 0) -> int:
		alive.append(1)
		state.append(st)
		type_idx.append(ti)
		max_hp.append(hp)
		dmg.append(bite)
		return alive.size() - 1


func test_threat_and_challenge() -> void:
	assert_float(SIM.threat_of(100.0, 6.0, 0.6)).is_equal_approx(1000.0, 0.001)
	# a cadence under 0.05 s counts as 0.05; negative numbers as 0
	assert_float(SIM.threat_of(10.0, 1.0, 0.0)).is_equal_approx(200.0, 0.001)
	assert_float(SIM.threat_of(-5.0, 1.0, 0.6)).is_equal(0.0)
	assert_float(SIM.challenge_of(2000.0, 20.0, 100.0)).is_equal_approx(1.0, 0.0001)
	assert_float(SIM.challenge_of(2000.0, 0.0, 100.0)).is_equal(0.0)


func test_the_crowd_by_channel() -> void:
	var em := Crowd.new()
	var gob := em.add_type("goblin", 0.5, 0.6)
	var imp := em.add_type("imp", 1.0, 0.5)
	var king := em.add_type("king", 1.0, 1.0)
	em.add(gob, 30.0, 6.0)
	em.add(gob, 30.0, 6.0)
	em.add(gob, 30.0, 6.0, Crowd.STATE_DYING)
	em.add(imp, 50.0, 10.0)
	em.boss_index = em.add(king, 5000.0, 40.0)
	var c: Dictionary = SIM.crowd_now(em, {"imp": true})
	# the dying goblin is not counted; the boss is alive but not in the threat
	assert_int(int(c["alive"])).is_equal(4)
	assert_int(int(c["alive_hell"])).is_equal(1)
	assert_float(float(c["load"])).is_equal_approx(2.0, 0.001)
	assert_float(float(c["load_hell"])).is_equal_approx(1.0, 0.001)
	assert_float(float(c["threat"])).is_equal_approx(2.0 * 30.0 * 6.0 / 0.6 + 50.0 * 10.0 / 0.5, 0.01)
	assert_dict(c["hell_by"]).is_equal({"imp": 1})


func test_a_row_starves_only_when_it_wants_to_spawn_and_cannot() -> void:
	var cont := {"t": 10.0, "until": 100.0, "enemy": "goblin", "weight": 2.0}
	assert_bool(SIM.starving(cont, 0, 50.0, true, false, null, null, {})).is_true()
	assert_bool(SIM.starving(cont, 0, 50.0, false, true, null, null, {})).is_false()
	# not open yet, or closed
	assert_bool(SIM.starving(cont, 0, 5.0, true, false, null, null, {})).is_false()
	assert_bool(SIM.starving(cont, 0, 100.0, true, false, null, null, {})).is_false()
	# a row at weight 0 wants nothing
	var zero := cont.duplicate()
	zero["weight"] = 0.0
	assert_bool(SIM.starving(zero, 0, 50.0, true, false, null, null, {})).is_false()
	# the hell channel's rows starve on the hell channel's room
	var hell := cont.duplicate()
	hell["channel"] = "hell"
	assert_bool(SIM.starving(hell, 1, 50.0, true, false, null, null, {})).is_false()
	assert_bool(SIM.starving(hell, 1, 50.0, false, true, null, null, {})).is_true()
	# a paced row starves while its last wave owes creatures (whatever the room), never through the continuous rule
	var waves := {"t": 10.0, "enemy": "goblin", "pace": "waves", "every": 30.0, "count": 12, "id": "sw"}
	assert_bool(SIM.starving(waves, 3, 50.0, true, true, null, null, {"row:sw#3": {"owed": 5}})).is_true()
	assert_bool(SIM.starving(waves, 3, 50.0, true, true, null, null, {"row:sw#3": {"owed": 0}})).is_false()
	var once := {"t": 10.0, "enemy": "goblin", "pace": "once", "count": 24}
	assert_bool(SIM.starving(once, 4, 50.0, true, true, null, null, {"row#4": {"owed": 3}})).is_true()
	# a waves row that trickles is in the continuous draw too
	var trickle := waves.duplicate()
	trickle["trickle"] = true
	assert_bool(SIM.starving(trickle, 3, 50.0, true, false, null, null, {})).is_true()


func test_row_keys_are_the_directors() -> void:
	assert_str(SIM.row_key({"enemy": "goblin"}, 7)).is_equal("row#7")
	assert_str(SIM.row_key({"enemy": "goblin", "id": "swarm1"}, 7)).is_equal("row:swarm1#7")
	assert_str(SIM.row_key({"id": "a"}, 2)).is_equal(WaveDirector._row_key_at({"id": "a"}, 2))
	var rows: Array = SIM.roster_rows([{"t": 0, "enemy": "goblin"}, "junk", {"t": 30, "until": 90, "enemy": ["a", "b"], "channel": "hell", "pace": "waves", "id": "x"}])
	assert_int(rows.size()).is_equal(2)
	assert_dict(rows[0]).is_equal({"key": "row#0", "k": 0, "id": "", "enemy": "goblin", "t": 0.0, "until": null, "channel": "", "pace": "continuous"})
	assert_str(str(rows[1]["key"])).is_equal("row:x#2")
	assert_array(rows[1]["enemy"]).is_equal(["a", "b"])


func test_lifetimes_by_stage() -> void:
	var life := {}
	SIM.life_add(life, "goblin", 0, 4.0)
	SIM.life_add(life, "goblin", 0, 6.0)
	SIM.life_add(life, "goblin", 9, 3.0)
	SIM.life_gone(life, "goblin")
	SIM.life_add(life, "", 0, 1.0)
	assert_array(life["goblin"]["n"]).is_equal([2, 0, 0, 1])
	assert_float(float(life["goblin"]["s"][0])).is_equal_approx(10.0, 0.001)
	assert_int(int(life["goblin"]["gone"])).is_equal(1)
	assert_bool(life.has("")).is_false()


func test_breakdowns_and_lengths() -> void:
	var by := {}
	SIM.put_by(by, {"a": 2}, 0, 1.0)
	SIM.put_by(by, {"b": 0.256}, 1, 0.01)
	SIM.put_by(by, {}, 2, 1.0)
	assert_int(by["a"].size()).is_equal(3)
	assert_int(int(by["a"][0])).is_equal(2)
	assert_float(float(by["a"][1]) + float(by["a"][2])).is_equal(0.0)
	assert_int(by["b"].size()).is_equal(3)
	assert_float(float(by["b"][0])).is_equal(0.0)
	assert_float(float(by["b"][1])).is_equal_approx(0.26, 0.000001)
	assert_float(float(by["b"][2])).is_equal(0.0)
	assert_array(SIM.fit_len([1, 2, 3], 2)).is_equal([1, 2])
	assert_array(SIM.fit_len([1, 2], 4)).is_equal([1, 2, 2, 2])
	assert_array(SIM.fit_len([], 2)).is_equal([0, 0])
