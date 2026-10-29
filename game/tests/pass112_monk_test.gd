extends GdUnitTestSuite

## Pass 112, lane MONK: the Monk (content/enemies/monk) and the squad brain (core/systems/Squads.gd, EnergyOrbs.gd).
## Creatures spawned together are one squad: one centre walking like a kiting Spit Cactus (its band measured from the
## formation's near edge), every member on its own slot of a hex blob `spacing` apart, facing the squad's heading; one
## volley clock (`cooldown` 5.2 s start to start, half the cactus's 2.6): every member stops for `hold` plain s, its
## hands rise then hold, and at `release` s every one looses a blue sphere at the hero in the same tick; the sphere flies
## straight through creatures, hurts only the hero, and is gone at 17.5 m (1.25 x the Revolver's 14). The director brings
## whole squads of 10, 20 or 30 (WaveDirector.squad_take), whatever the row's pattern; one that does not fit waits.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
var toasts: Array = []
var bursts := 0
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	bursts += 1
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var hits: Array = []
var last_outcome := "hit"
func take_damage(a: float, _f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "info": i})
func shove(_v: Vector3, _c: bool = true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h: bool = true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h: bool = true) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_PICKUPS := """extends Node
func spawn_special(_def, _at, _quiet = false) -> void:
	pass
func spawn_chest(_at, _boss = false) -> void:
	pass
func spawn(_k, _at, _v = 1.0) -> void:
	pass
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0


func after_test() -> void:
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _director(w: Dictionary) -> WaveDirector:
	var base := {"stage_length": 430, "stages": 3, "cap_start": 300, "cap_per_minute": 0, "cap_max": 300, "hard_cap": 300,
		"spawn_interval": 0.5, "roster": [], "events": [], "waves": [], "colour_after_kills": 0, "hell_cap": [0.5, 0.5, 0.5]}
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = JsonContent.timeline_from_dict(base)
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	return d


func _monk() -> EnemyDef:
	return Registry.enemy("monk")


## `n` ticks of the crowd (and of the spheres when they exist).
func _run(em: EnemyManager, n: int) -> void:
	for k in range(n):
		em._physics_process(DT)
		if em.squads != null and em.squads.orbs != null:
			em.squads.orbs._physics_process(DT)


## The squad's members as they stand (alive and not dying).
func _members(em: EnemyManager) -> Array:
	var out: Array = []
	for i in range(em.pool_max):
		if em.alive[i] == 1 and em.state[i] != EnemyManager.STATE_DYING and em._t_squad[em.type_idx[i]] == 1:
			out.append(i)
	return out


## The smallest and the largest distance from a member to its nearest neighbour.
func _nn(em: EnemyManager, members: Array) -> Vector2:
	var lo := INF
	var hi := 0.0
	for a: int in members:
		var best := INF
		for b: int in members:
			if a == b:
				continue
			best = minf(best, Vector2(em.pos[a].x - em.pos[b].x, em.pos[a].z - em.pos[b].z).length())
		lo = minf(lo, best)
		hi = maxf(hi, best)
	return Vector2(lo, hi)


## How far north of the hero a squad of `n` stands with its near edge in the middle of its band (pass 112: 7 m in the
## 5..8 m band; pass 113 re-pin: the band is Garry's to tune, so the middle of keep_distance - 0.5 .. range).
func _band_z(n: int) -> float:
	var r := 0.0
	for p: Vector3 in Squads.formation(n, float(_monk().squad_cfg()["spacing"])):
		r = maxf(r, Vector2(p.x, p.z).length())
	var cfg := _monk().squad_cfg()
	return -(r + (float(cfg["keep_distance"]) - 0.5 + float(cfg["range"])) * 0.5)


func _the_squad(em: EnemyManager) -> Dictionary:
	assert_int(em.squads.list.size()).is_equal(1)
	return em.squads.list.values()[0]


# ---------------------------------------------------------------- the data

func test_the_monk_is_a_squad_of_10_20_or_30_with_the_cactus_band_and_half_its_rate() -> void:
	var m := _monk()
	var c: EnemyDef = Registry.enemy("spit_cactus")
	assert_str(m.brain).is_equal("squad")
	assert_bool(m.is_squad()).is_true()
	assert_array(Array(m.squad_sizes())).is_equal([10, 20, 30])
	var cfg := m.squad_cfg()
	# the same attack distance as the Spit Cactus, half as often (pass 112). Pass 113 re-pin: Garry tuned the Monk himself
	# in the Level Editor (keep 4 m, range 6 m, a volley every 6.2 s, spacing 1.2), so what stays pinned is the shape: a
	# band (backs off nearer than keep, walks in past range), never closer than the cactus keeps, a stop shorter than the
	# time between volleys
	assert_float(float(cfg["keep_distance"])).is_greater(0.0)
	assert_float(float(cfg["range"])).is_greater(float(cfg["keep_distance"]))
	assert_float(float(cfg["cooldown"])).is_greater_equal(float(c.ranged["cooldown"]))
	assert_float(float(cfg["cooldown"])).is_greater(float(cfg["hold"]))
	assert_float(float(cfg["hold"])).is_equal_approx(3.0, 0.0001)
	assert_float(float(cfg["release"])).is_less(float(cfg["hold"]))
	assert_float(float(cfg["rise"])).is_less_equal(float(cfg["release"]))
	# the sphere: 25% past the Revolver's 14 m, slow, blue; pass 113 (Garry: "extend the range of the projectiles by 50%",
	# "a bit faster"): half as far again, 5 m/s
	var wj = JSON.parse_string(FileAccess.get_file_as_string("res://content/weapons/revolver/revolver.json"))
	var rev_range := float(wj["base"]["range"])
	assert_float(rev_range).is_equal_approx(14.0, 0.0001)
	assert_float(float(cfg["orb"]["range"])).is_equal_approx(rev_range * 1.25 * 1.5, 0.0001)
	assert_float(float(cfg["orb"]["speed"])).is_less_equal(5.0)
	var col := Color(str(cfg["orb"]["color"]))
	assert_float(col.b).is_greater(col.r + 0.4)
	# never an Elite, never a special, a regular creature's chest roll, its own bite and blood and doc
	assert_bool(m.can_be_elite).is_false()
	assert_float(float(m.variance.get("special_chance", 0.0))).is_equal(0.0)
	assert_float(float(m.drops.get("chest", 0.0))).is_equal_approx(0.0002, 0.000001)
	assert_float(m.knockback).is_greater(0.0)
	assert_str(m.doc).is_not_empty()
	assert_bool(m.ranged.is_empty()).is_true()
	# the size draw only ever brings a listed size, each of them
	var seen := {}
	for k in range(60):
		seen[m.squad_roll(float(k) / 60.0)] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([10, 20, 30])


# ---------------------------------------------------------------- forming

func test_a_pack_comes_as_one_squad_on_its_formation() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var came := em.spawn_pack("monk", Vector3(0, 0, -20), 20)
	assert_int(came).is_equal(20)
	var sq := _the_squad(em)
	assert_int((sq["members"] as PackedInt32Array).size()).is_equal(20)
	var spacing := float(_monk().squad_cfg()["spacing"])
	var nn := _nn(em, _members(em))
	# a tight hex blob: every neighbour about `spacing` away
	assert_float(nn.x).is_greater(spacing * 0.95)
	assert_float(nn.y).is_less(spacing * 1.05)
	# its centre is the pack's point
	var a: Vector3 = sq["anchor"]
	assert_float(Vector2(a.x, a.z + 20.0).length()).is_less(0.01)


func test_lone_spawns_of_one_tick_gather_into_squads_by_place() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	for k in range(6):
		em.spawn("monk", Vector3(float(k) * 1.0, 0, -20))
	for k in range(4):
		em.spawn("monk", Vector3(40.0 + float(k), 0, -20))
	assert_int(em.squads.list.size()).is_equal(2)
	var sizes: Array = []
	for sq: Dictionary in em.squads.list.values():
		sizes.append((sq["members"] as PackedInt32Array).size())
	assert_array(sizes).contains_exactly_in_any_order([6, 4])


# ---------------------------------------------------------------- walking

func test_the_squad_walks_in_with_one_heading_and_keeps_its_spacing() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.spawn_pack("monk", Vector3(0, 0, -30), 20)
	# up out of the sand
	_run(em, 30)
	var sq := _the_squad(em)
	var a0: Vector3 = sq["anchor"]
	var members := _members(em)
	var p0 := {}
	for i: int in members:
		p0[i] = em.pos[i]
	_run(em, 60)
	var a1: Vector3 = sq["anchor"]
	# the centre walks straight at the hero
	var step := Vector3(a1.x - a0.x, 0, a1.z - a0.z)
	assert_float(step.length()).is_greater(0.5)
	assert_float(step.normalized().dot(Vector3(0, 0, 1))).is_greater(0.99)
	var heading: Vector3 = sq["heading"]
	for i: int in members:
		# one heading: every member means the squad's heading
		var it := Vector3(em.intent[i].x, 0, em.intent[i].z)
		assert_float(it.length()).is_greater(0.2)
		assert_float(it.normalized().dot(heading)).is_greater(0.999)
		# and every one moved with the centre, within a hand's breadth
		var d: Vector3 = em.pos[i] - p0[i]
		d.y = 0.0
		assert_float((d - step).length()).is_less(0.25)
	var spacing := float(_monk().squad_cfg()["spacing"])
	var nn := _nn(em, members)
	assert_float(nn.x).is_greater(spacing * 0.85)
	assert_float(nn.y).is_less(spacing * 1.2)


func test_the_squad_backs_off_together_when_the_hero_comes_close() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# pass 113 re-pin: right up against the hero (Garry's keep distance is 4 m now: at 5 m the squad was nearly in its band)
	em.spawn_pack("monk", Vector3(0, 0, -3), 10)
	_run(em, 30)
	var sq := _the_squad(em)
	var a0: Vector3 = sq["anchor"]
	_run(em, 30)
	var a1: Vector3 = sq["anchor"]
	# away from the hero (he stands at the origin, the squad north of him)
	assert_float(a1.z).is_less(a0.z - 0.3)
	var heading: Vector3 = sq["heading"]
	assert_float(heading.dot(Vector3(0, 0, -1))).is_greater(0.99)
	for i: int in _members(em):
		var it := Vector3(em.intent[i].x, 0, em.intent[i].z)
		assert_float(it.normalized().dot(heading)).is_greater(0.999)


func test_a_member_that_dies_reshapes_the_formation() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.spawn_pack("monk", Vector3(0, 0, -30), 20)
	_run(em, 30)
	var sq := _the_squad(em)
	var r20 := float(sq["radius"])
	var members := _members(em)
	for k in range(10):
		em.damage(members[k], 1.0e6)
	_run(em, 2)
	sq = _the_squad(em)
	assert_int((sq["members"] as PackedInt32Array).size()).is_equal(10)
	assert_int((sq["slots"] as PackedVector3Array).size()).is_equal(10)
	assert_float(float(sq["radius"])).is_less(r20)
	# the ten close up into the smaller blob
	_run(em, 240)
	var nn := _nn(em, _members(em))
	var spacing := float(_monk().squad_cfg()["spacing"])
	assert_float(nn.y).is_less(spacing * 1.25)


# ---------------------------------------------------------------- the volley

func test_every_member_stops_and_fires_in_the_same_tick_and_holds_its_pose_3s() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var cfg := _monk().squad_cfg()
	# in its band: the near edge in its middle
	var z := _band_z(20)
	em.spawn_pack("monk", Vector3(0, 0, z), 20)
	_run(em, 30)
	var sq := _the_squad(em)
	var r := float(sq["radius"])
	assert_float(-z - r).is_between(float(cfg["keep_distance"]) - 0.5, float(cfg["range"]))
	sq["cd"] = 0.0
	var members := _members(em)
	var started_tick := -1
	var fired_tick := -1
	var ended_tick := -1
	var held_at := {}
	var max_drift := 0.0
	for t in range(400):
		_run(em, 1)
		var n_atk := 0
		for i: int in members:
			if em.state[i] == EnemyManager.STATE_ATTACK:
				n_atk += 1
		if started_tick < 0 and n_atk > 0:
			# every member at once
			assert_int(n_atk).is_equal(20)
			started_tick = t
			for i: int in members:
				held_at[i] = em.pos[i]
		elif started_tick >= 0 and ended_tick < 0:
			if n_atk == 0:
				ended_tick = t
			else:
				assert_int(n_atk).is_equal(20)
				for i: int in members:
					max_drift = maxf(max_drift, Vector2(em.pos[i].x - held_at[i].x, em.pos[i].z - held_at[i].z).length())
		if fired_tick < 0 and em.squads.volleys_fired > 0:
			fired_tick = t
			# all twenty spheres left in this one tick
			assert_int(em.squads.last_fired.size()).is_equal(20)
			assert_int(em.squads.orbs.fired).is_equal(20)
			assert_int(em.squads.orbs.count).is_equal(20)
		if ended_tick >= 0 and fired_tick >= 0:
			break
	assert_int(started_tick).is_greater_equal(0)
	assert_int(fired_tick).is_greater(started_tick)
	assert_int(ended_tick).is_greater(fired_tick)
	# the stop lasts `hold` plain seconds on every map (Red Canyon's creatures run at pace 0.81: not stretched), the
	# release at `release`
	assert_float(em.pace).is_less(0.95)
	assert_float(float(ended_tick - started_tick) * DT).is_equal_approx(float(cfg["hold"]), 2.0 * DT)
	assert_float(float(fired_tick - started_tick) * DT).is_equal_approx(float(cfg["release"]), 2.0 * DT)
	# a full stop: nobody walks while the hands are up
	assert_float(max_drift).is_less(0.05)
	# and the next volley starts `cooldown` s after this one started
	var next_start := -1
	for t in range(600):
		_run(em, 1)
		if em.squads.volleys_started >= 2:
			next_start = t + ended_tick + 1
			break
	assert_int(next_start).is_greater(0)
	assert_float(float(next_start - started_tick) * DT).is_greater_equal(float(cfg["cooldown"]) - 2.0 * DT)
	# its spheres were aimed at the hero
	assert_int((hero.get("hits") as Array).size()).is_greater(0)


func test_a_stunned_member_sits_out_the_volley() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	em.spawn_pack("monk", Vector3(0, 0, _band_z(10)), 10)
	_run(em, 30)
	var sq := _the_squad(em)
	sq["cd"] = 0.0
	_run(em, 2)
	assert_float(float(sq["atk"])).is_greater_equal(0.0)
	var members := _members(em)
	em.stun(members[0], 5.0, false)
	assert_int(em.state[members[0]]).is_equal(EnemyManager.STATE_MOVE)
	_run(em, int(ceil(float(_monk().squad_cfg()["release"]) / DT)) + 2)
	assert_int(em.squads.last_fired.size()).is_equal(9)
	assert_bool(Array(em.squads.last_fired).has(members[0])).is_false()


func test_the_attack_strip_rises_then_holds_front_and_back() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var d: EnemyDef = _monk().duplicate()
	d.id = "monk_strip_test"
	d.variant_code = "STRIPTEST"
	d.anims = {"idle": 4, "run": 12, "attack": 8, "hit": 1, "die": 8, "run_b": 12, "idle_b": 4}
	d.attack_views = "front_back"
	var t := em.register_type(d)
	assert_int(em._t_squad[t]).is_equal(1)
	var i := em.spawn_pack("monk", Vector3(0, 0, -11.5), 1)
	assert_int(i).is_equal(1)
	var idx: int = _members(em)[0]
	em.type_idx[idx] = t
	var sq := _the_squad(em)
	var cfg := _monk().squad_cfg()
	var rise := float(cfg["rise"])
	var off: int = em._t_off[t * EnemyManager.N_ANIMS + EnemyManager.A_ATTACK]
	em.away[idx] = 0
	sq["atk"] = 0.0
	assert_int(em.squads.attack_frame(idx, t, EnemyManager.A_ATTACK)).is_equal(off + 0)
	sq["atk"] = rise * 0.75
	assert_int(em.squads.attack_frame(idx, t, EnemyManager.A_ATTACK)).is_equal(off + 1)
	sq["atk"] = rise + 0.01
	assert_int(em.squads.attack_frame(idx, t, EnemyManager.A_ATTACK)).is_equal(off + 2)
	sq["atk"] = rise + 0.01 + 1.0 / float(cfg["breath_fps"])
	assert_int(em.squads.attack_frame(idx, t, EnemyManager.A_ATTACK)).is_equal(off + 3)
	# facing away: the back half
	em.away[idx] = 1
	sq["atk"] = rise + 0.01
	assert_int(em.squads.attack_frame(idx, t, EnemyManager.A_ATTACK)).is_equal(off + 6)
	# two frames a half: the first rising, the second held
	d.anims = {"idle": 4, "run": 12, "attack": 4, "hit": 1, "die": 8}
	var d2: EnemyDef = d.duplicate()
	d2.variant_code = "STRIPTEST2"
	var t2 := em.register_type(d2)
	var off2: int = em._t_off[t2 * EnemyManager.N_ANIMS + EnemyManager.A_ATTACK]
	em.away[idx] = 0
	sq["atk"] = 0.1
	assert_int(em.squads.attack_frame(idx, t2, EnemyManager.A_ATTACK)).is_equal(off2)
	sq["atk"] = 2.5
	assert_int(em.squads.attack_frame(idx, t2, EnemyManager.A_ATTACK)).is_equal(off2 + 1)
	# in its stop it shows the attack strip, hit or not, whatever its view
	em.state[idx] = EnemyManager.STATE_ATTACK
	em.flash[idx] = 1.0
	assert_int(em._strip_of(idx, t)).is_equal(EnemyManager.A_ATTACK)


# ---------------------------------------------------------------- the sphere

func test_the_sphere_flies_through_creatures_and_is_gone_at_its_range() -> void:
	var w := _world(Vector3(40, 0, 40))
	var em: EnemyManager = w["em"]
	# a wall of skeletons across its line
	var wall: Array = []
	for k in range(5):
		var j := em.spawn("skeleton", Vector3(-1.0 + float(k) * 0.5, 0, -6))
		em.state[j] = EnemyManager.STATE_MOVE
		wall.append(j)
	var hp0 := {}
	for j: int in wall:
		hp0[j] = em.hp[j]
	var orbs := em._sq().orbs_node()
	var ob: Dictionary = _monk().squad_cfg()["orb"]
	var o := orbs.fire(Vector3(0, 1.8, 0), Vector3(0, 0, -1), float(ob["speed"]), float(ob["range"]), 10.0, ob, {"by": "Monk"})
	assert_int(o).is_greater_equal(0)
	var passed_wall := false
	var ticks := 0
	while orbs.alive[o] == 1 and ticks < 1200:
		orbs._physics_process(DT)
		ticks += 1
		if orbs.alive[o] == 1 and orbs.pos[o].z < -7.0:
			passed_wall = true
	assert_bool(passed_wall).is_true()
	for j: int in wall:
		assert_float(em.hp[j]).is_equal(hp0[j])
		assert_int(em.alive[j]).is_equal(1)
	assert_int(orbs.spent).is_equal(1)
	# pass 113: its range is the JSON's (26.25 m since Garry's +50%)
	var reach := float(ob["range"])
	assert_float(orbs.last_spent_flown).is_between(reach, reach + float(ob["speed"]) * DT + 0.01)
	# slow: about range / speed seconds on the creatures' clock
	assert_float(float(ticks) * DT).is_equal_approx(reach / (float(ob["speed"]) * em.hostile_clock()), 0.1)


func test_the_sphere_hurts_the_hero_once_as_a_plain_shot() -> void:
	var w := _world(Vector3(0, 0, -8))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var orbs := em._sq().orbs_node()
	var ob: Dictionary = _monk().squad_cfg()["orb"]
	var o := orbs.fire(Vector3(0, 1.8, 0), Vector3(0, 0, -1), float(ob["speed"]), float(ob["range"]), 8.0, ob, {"by": "Monk", "id": "monk", "kind": "ranged"})
	for k in range(600):
		orbs._physics_process(DT)
		if orbs.alive[o] == 0:
			break
	var hits: Array = hero.get("hits")
	assert_int(hits.size()).is_equal(1)
	assert_float(float(hits[0]["amount"])).is_equal_approx(8.0, 0.0001)
	assert_bool(bool(hits[0]["info"].get("special_knock", true))).is_false()
	assert_int(orbs.hits).is_equal(1)
	# it came down from the hands to its flying height
	assert_float(orbs.hover[o]).is_equal_approx(float(ob["hover"]), 0.0001)


# ---------------------------------------------------------------- the director

func test_the_director_brings_whole_squads_of_10_20_or_30_that_wait_for_room() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var dir := _director(w)
	var m := _monk()
	# a drawn size, or the largest that fits, or nothing
	for k in range(30):
		assert_array([10, 20, 30]).contains([dir.squad_take(m, {}, 0, 300)])
	for k in range(30):
		assert_array([10, 20]).contains([dir.squad_take(m, {}, 0, 25)])
	assert_int(dir.squad_take(m, {}, 0, 9)).is_equal(0)
	# a row's own pack is the squad, and it never shrinks
	assert_int(dir.squad_take(m, {"pack": 12}, 0, 300)).is_equal(12)
	assert_int(dir.squad_take(m, {"pack": 20}, 0, 15)).is_equal(0)
	# a wave owing 40 comes one squad at a time, at most the largest size
	assert_int(dir.squad_take(m, {}, 40, 300)).is_equal(30)
	assert_int(dir.squad_take(Registry.enemy("skeleton"), {}, 0, 300)).is_equal(-1)
	# the continuous draw: one whole squad a burst, never cut by the burst, whatever the pattern (a few draws: a squad of 10
	# in a burst of 12 must not bring a second)
	for k in range(8):
		var w2 := _world()
		var em2: EnemyManager = w2["em"]
		var dir2 := _director(w2)
		dir2._burst_from([{"t": 0, "enemy": "monk", "weight": 1, "pattern": "scatter"}], 100.0, 300)
		assert_int(em2.squads.list.size()).is_equal(1)
		var n2 := (em2.squads.list.values()[0]["members"] as PackedInt32Array).size()
		assert_array([10, 20, 30]).contains([n2])
		assert_int(em2.alive_count()).is_equal(n2)
	# no room for even the smallest: it waits
	dir._burst_from([{"t": 0, "enemy": "monk", "weight": 1}], 6.0, 300)
	assert_int(em.alive_count()).is_equal(0)
