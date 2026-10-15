extends GdUnitTestSuite

## Pass 73, lane SNIPER (Garry, 2026-10-14, "Special Enemies"): the weapons take a special, an Elite or the boss first
## once the hero is close enough (EnemyManager.priority_target, the map's target_priority); the Saiga Sniper
## (content/enemies/saiga_sniper, the brain "sniper": stand-off spawn, flee, a frozen aim with the gathering red lines
## that follow and then lock, a 1 s hold, a beam across the map, sparks, the hero's damage from the Vulture Raider's
## rocket); flee on hit for any creature (EnemyDef.flee_on_hit); the Vulture Raider's rocket shaken and slowed by every
## hit on him (ProjectileManager.shooter_hit); the sniper's row in Red Canyon's specials pool.

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
var hints: Array = []
var bursts := 0
func toast(t, _c = null) -> void:
	toasts.append(str(t))
func fx_burst(_a, _b, _c) -> void:
	bursts += 1
func fx_hit(_a, _b) -> void:
	pass
func hint_once(a, _b) -> void:
	hints.append(str(a))
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func telegraph_ring(_a, _b, _c, _d, _e = true) -> void:
	pass
func rocket_out(_i: int) -> bool:
	return false
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
var max_hp := 100.0
var hits: Array = []
func take_damage(a: float, f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "from": f, "info": i})
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

const DT := 1.0 / 60.0

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.arena = false
	Run.elapsed = 0.0
	Run.stage = 0
	Run.kills = 0
	Run.level = 1


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
	g.set("player", hero)
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.set("enemies", em)
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _projectiles(g: Node) -> ProjectileManager:
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.set("projectiles", pm)
	pm.register_kind(BoxMesh.new(), null, 1.0, true)
	return pm


## A test creature `id` made from `from` (its variance off, no looks), with `extra` set on it; gone after the test.
func _test_def(id: String, from: String, extra: Dictionary = {}) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.variance = {}
	d.variants = {}
	d.variant = ""
	d.variant_code = ""
	d.drops = {}
	for k: String in extra.keys():
		d.set(k, extra[k])
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _run(em: EnemyManager, seconds: float, pm: ProjectileManager = null) -> void:
	var n := int(ceilf(seconds / DT))
	for k in range(n):
		em._physics_process(DT)
		if pm:
			pm._physics_process(DT)


## Ticks until `cond` holds (at most `limit` seconds); the seconds it took, or -1.
func _run_until(em: EnemyManager, cond: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		em._physics_process(DT)
		t += DT
		if cond.call():
			return t
	return -1.0


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- 1. the creature's data

func test_the_saiga_sniper_is_a_special_from_garrys_picture() -> void:
	var d := _json("res://content/enemies/saiga_sniper/saiga_sniper.json")
	var def: EnemyDef = Registry.enemy("saiga_sniper")
	var rk: EnemyDef = Registry.enemy("rocketeer")
	assert_object(def).is_not_null()
	assert_str(def.brain).is_equal("sniper")
	assert_str(def.badge_for()).is_equal("gear")
	assert_bool(def.can_be_elite).is_false()
	assert_int(def.max_alive).is_equal(1)
	# HP and XP like the Vulture Raider's
	assert_float(def.hp).is_equal(rk.hp)
	assert_float(def.xp_mult).is_equal(rk.xp_mult)
	# the shape rules every creature keeps: a doc, a blood, a knockback of its own
	assert_str(str(d.get("doc", ""))).is_not_empty()
	assert_str(str(d.get("blood", ""))).is_not_empty()
	assert_float(def.knockback).is_greater(0.0)
	# the art words for lane ART: the reference's saiga, poncho and rifle; the aim as the attack strip, front and back
	for key in ["art_prompt", "appearance", "back_hint", "dead_hint", "aim_hint", "aim_back_hint", "motion"]:
		assert_str(str(d.get(key, ""))).override_failure_message(key).is_not_empty()
	assert_str(str(d["art_prompt"])).contains("saiga")
	assert_str(str(d["art_prompt"])).contains("poncho")
	assert_str(str(d["art_prompt"])).contains("rifle")
	assert_str(def.attack_views).is_equal("front_back")
	# its numbers as the contract says (Garry may tune them in the Level Editor: read from the data, not pinned here)
	var sn: Dictionary = def.sniper
	assert_float(float(sn["stand_off"])).is_greater(float(sn["flee_range"]))
	assert_float(float(sn["aim"])).is_greater(0.0)
	assert_float(float(sn["lock"])).is_greater(0.0)
	var bm: Dictionary = sn["beam"]
	assert_str(str(bm["damage_from"])).is_equal("rocketeer")
	assert_float(float(bm["length"])).is_greater_equal(40.0)
	# flee on hit, the reusable ability: pass 81 (lane POLISH, re-pinned; Garry: "Remove that feature entirely") the Saiga
	# runs no more (the ability stays in code, tested on test creatures below); a hit still spoils his aim (spoil_on_hit)
	assert_bool(def.flee_on_hit.is_empty()).is_true()
	assert_bool(bool(sn.get("spoil_on_hit", true))).is_true()
	# the sounds it names are in the sound map
	for hook in ["aim", "lock", "shot"]:
		var sid := str(def.sfx.get(hook, ""))
		assert_str(sid).override_failure_message(hook).is_not_empty()
		assert_bool(FileAccess.file_exists("res://content/sounds/real/%s.wav" % sid)).override_failure_message(sid).is_true()


func test_red_canyon_brings_the_sniper_as_often_as_the_vulture_raider() -> void:
	# Garry: "same chance to spawn in stage 1 as Rocketeer". The Raider is not a roster creature but a row of the specials
	# pool (one special at a time, drawn evenly from the rows whose stage has come): the sniper's row matches his
	var pool: Array = _json("res://content/maps/red_canyon/red_canyon.json")["timeline_data"]["specials"]["pool"]
	var rk_stage := -1
	var sn_stage := -1
	for row in pool:
		var id := str(row.get("enemy", "")) if row is Dictionary else str(row)
		var st := int(row.get("stage", 1)) if row is Dictionary else 1
		if id == "rocketeer":
			rk_stage = st
		elif id == "saiga_sniper":
			sn_stage = st
	assert_int(rk_stage).is_greater(0)
	assert_int(sn_stage).is_equal(rk_stage)
	# and the game's timeline reads it
	var names: Array = []
	for row in Registry.map("red_canyon").timeline.specials.get("pool", []):
		names.append(str(row.get("enemy", "")) if row is Dictionary else str(row))
	assert_array(names).contains(["rocketeer", "saiga_sniper"])


# ---------------------------------------------------------------- 2. target priority

func test_priority_target_takes_a_special_elite_or_boss_within_ten_metres() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var plain := em.spawn("skeleton", Vector3(3, 0, 0))
	var gear := em.spawn("rocketeer", Vector3(8, 0, 0))
	# (the Raider is placed at his stand-off when he spawns: put him back)
	em.pos[gear] = Vector3(8, 0, 0)
	em._rebuild_grid()
	assert_bool(em.is_priority(gear)).is_true()
	assert_bool(em.is_priority(plain)).is_false()
	assert_int(em.priority_target(Vector3.ZERO, 12.0)).is_equal(gear)
	# within the weapon's own range only (min(range, 10))
	assert_int(em.priority_target(Vector3.ZERO, 6.0)).is_equal(-1)
	# and never past the map's reach, whatever the weapon's range
	em.pos[gear] = Vector3(11, 0, 0)
	em._rebuild_grid()
	assert_int(em.priority_target(Vector3.ZERO, 30.0)).is_equal(-1)
	# a coloured variance special and an elite-modified creature count; the nearest of several wins
	em.pos[gear] = Vector3(9, 0, 0)
	var sp := em.spawn("skeleton", Vector3(0, 0, 5))
	em.vspecial[sp] = 1
	em._rebuild_grid()
	assert_int(em.priority_target(Vector3.ZERO, 12.0)).is_equal(sp)
	# (set by hand here: the game sets these at a spawn; the list of priority creatures is gathered again with the grid)
	em.vspecial[sp] = 0
	em.elite_idx[plain] = 0
	em._rebuild_grid()
	assert_int(em.priority_target(Vector3.ZERO, 12.0)).is_equal(plain)
	em.elite_idx[plain] = -1
	em._rebuild_grid()
	# the map's switch
	em.set_target_priority({"enabled": false})
	assert_int(em.priority_target(Vector3.ZERO, 12.0)).is_equal(-1)
	em.set_target_priority({})
	assert_bool(em.target_priority_on).is_true()
	assert_float(em.target_priority_reach).is_equal(10.0)
	em.set_target_priority({"reach": 4.0})
	assert_int(em.priority_target(Vector3.ZERO, 12.0)).is_equal(-1)


func test_the_map_carries_the_target_priority_setting() -> void:
	assert_bool(bool(WaveTimeline.TARGET_PRIORITY_DEFAULTS["enabled"])).is_true()
	assert_float(float(WaveTimeline.TARGET_PRIORITY_DEFAULTS["reach"])).is_equal(10.0)
	var tp: Dictionary = Registry.map("red_canyon").timeline.target_priority
	var file_tp = _json("res://content/maps/red_canyon/red_canyon.json")["timeline_data"].get("target_priority", {})
	assert_bool(tp == file_tp).is_true()


func test_a_nearest_weapon_and_the_crowd_spots_go_for_the_priority_one_first() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var near := em.spawn("skeleton", Vector3(2, 0, 0))
	var gear := em.spawn("rocketeer", Vector3(0, 0, 7))
	em.pos[gear] = Vector3(0, 0, 7)
	for k in range(5):
		em.spawn("skeleton", Vector3(-4 + 0.3 * k, 0, -2))
	em._rebuild_grid()
	var b: WeaponBehavior = auto_free(WeaponBehavior.new())
	b.game = w["g"]
	b.player = w["hero"]
	b.inst = WeaponInstance.new(Registry.weapon("frisbee"), 1)
	assert_int(b.aim_index(Vector3.ZERO, 12.0)).is_equal(gear)
	# out of the weapon's reach: the nearest, as before
	assert_int(b.aim_index(Vector3.ZERO, 5.0)).is_equal(near)
	# a priority weapon (the strong and the close) still prefers it
	b.inst = WeaponInstance.new(Registry.weapon("revolver"), 1)
	assert_int(b.aim_index(Vector3.ZERO, 12.0)).is_equal(gear)
	# a spreading volley: the first blow on it, the rest on the crowds as before
	var spots := b.crowd_spots(2, 9.0, 1.6)
	assert_int(spots.size()).is_equal(2)
	assert_float(_flat(spots[0], em.pos[gear])).is_less(0.01)
	assert_float(_flat(spots[1], em.pos[gear])).is_greater(2.0)
	# with the rule off, the crowd's spot comes first again
	em.set_target_priority({"enabled": false})
	assert_int(b.aim_index(Vector3.ZERO, 12.0)).is_not_equal(gear)
	assert_float(_flat(b.crowd_spots(1, 9.0, 1.6)[0], em.pos[gear])).is_greater(2.0)


func test_the_tarantula_hawk_and_the_sceptre_take_it_first_and_spread_the_rest() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var gear := em.spawn("rocketeer", Vector3(0, 0, 6))
	em.pos[gear] = Vector3(0, 0, 6)
	var others: Array = []
	for k in range(4):
		others.append(em.spawn("skeleton", Vector3(2.0 + k, 0, 1)))
	em._rebuild_grid()
	em.refresh_crowd_stats()
	assert_int(TarantulaHawk.pick(em, Vector3.ZERO, 12.0, {})).is_equal(gear)
	# one hawk a creature: the next goes elsewhere
	var taken := {em.serial[gear]: true}
	assert_int(TarantulaHawk.pick(em, Vector3.ZERO, 12.0, taken)).is_not_equal(gear)
	var sc: SunScepter = auto_free(SunScepter.new())
	sc.game = w["g"]
	sc.player = w["hero"]
	sc.inst = WeaponInstance.new(Registry.weapon("sun_scepter"), 1)
	var picks: Array = sc.pick_targets(3)
	assert_int(picks.size()).is_equal(3)
	assert_int(int(picks[0])).is_equal(gear)
	# none twice
	assert_int(picks.count(gear)).is_equal(1)


# ---------------------------------------------------------------- 3. flee on hit

func test_a_hit_sends_a_creature_with_flee_on_hit_running_for_a_second() -> void:
	var def := _test_def("p73_runner", "skeleton", {"flee_on_hit": {"seconds": 1.0, "speed_mult": 2.0, "interrupts": true}})
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := em.spawn(def.id, Vector3(5, 0, 0))
	_run(em, 0.5)
	var at0: Vector3 = em.pos[i]
	var d0 := _flat(at0, Vector3.ZERO)
	# a poison or fire tick is no hit
	em.damage(i, 0.5, "", Vector3.ZERO, 0.0, true)
	assert_bool(em.is_fleeing(i)).is_false()
	em.damage(i, 0.5, "revolver")
	assert_bool(em.is_fleeing(i)).is_true()
	assert_int(em.flee_starts).is_equal(1)
	_run(em, 0.5)
	# straight away from the hero at twice its walk
	var d1 := _flat(em.pos[i], Vector3.ZERO)
	assert_float(d1 - d0).is_greater(em.speed[i] * 2.0 * 0.5 * 0.7)
	_run(em, 0.6)
	assert_bool(em.is_fleeing(i)).is_false()
	# then it walks back at him
	var d2 := _flat(em.pos[i], Vector3.ZERO)
	_run(em, 0.5)
	assert_float(_flat(em.pos[i], Vector3.ZERO)).is_less(d2)


func test_flee_on_hit_drops_a_wind_up_and_never_moves_a_boss() -> void:
	var def := _test_def("p73_winder", "skeleton", {"flee_on_hit": {"seconds": 1.0, "speed_mult": 1.8, "interrupts": true}})
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := em.spawn(def.id, Vector3(4, 0, 0))
	_run(em, 0.5)
	em.state[i] = EnemyManager.STATE_WINDUP
	em.timer[i] = 1.0
	em.damage(i, 0.5, "revolver")
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.cooldown[i]).is_greater_equal(1.0)
	# without `interrupts` the wind-up goes on
	var keep := _test_def("p73_keeper", "skeleton", {"flee_on_hit": {"seconds": 1.0, "speed_mult": 1.8, "interrupts": false}})
	var j := em.spawn(keep.id, Vector3(-4, 0, 0))
	_run(em, 0.5)
	em.state[j] = EnemyManager.STATE_WINDUP
	em.timer[j] = 1.0
	em.damage(j, 0.5, "revolver")
	assert_int(em.state[j]).is_equal(EnemyManager.STATE_WINDUP)
	# a boss never runs
	var boss := _test_def("p73_boss", "tumbleweed_king", {"flee_on_hit": {"seconds": 1.0, "speed_mult": 1.8}})
	var k := em.spawn(boss.id, Vector3(0, 0, 8))
	assert_bool(em.flee_start(k)).is_false()


func test_a_stunned_vulture_raider_winds_up_again() -> void:
	# pass 73: a wind-up something dropped (a stun, a launch, a hit's flee) leaves him ready again (he used to wait for
	# a rocket that never left)
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := em.spawn("rocketeer", Vector3(30, 0, 0))
	var wound := _run_until(em, func() -> bool: return em.state[i] == EnemyManager.STATE_WINDUP, 6.0)
	assert_float(wound).is_greater(0.0)
	em.stun(i, 0.4)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	var again := _run_until(em, func() -> bool: return em.state[i] == EnemyManager.STATE_WINDUP, 6.0)
	assert_float(again).is_greater(0.0)


# ---------------------------------------------------------------- 4. the Saiga Sniper

func test_the_sniper_stands_off_and_holds_when_the_hero_walks_up() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(12, 0, 0))
	var def: EnemyDef = Registry.enemy("saiga_sniper")
	# placed at its stand-off from the hero, as the Vulture Raider is
	assert_float(_flat(em.pos[i], Vector3.ZERO)).is_equal_approx(float(def.sniper["stand_off"]), 0.05)
	# the hero walks up (pass 73's flee_range 14 sent him running): pass 81 (re-pinned) he holds where he is
	hero.global_position = em.pos[i] + Vector3(-11.0, 0, 0)
	_run(em, 0.6)
	var d0 := _flat(em.pos[i], hero.global_position)
	_run(em, 1.0)
	assert_float(_flat(em.pos[i], hero.global_position)).is_less_equal(d0 + 0.2)
	assert_bool(em.is_fleeing(i)).is_false()


func test_the_sniper_aims_locks_holds_and_fires_across_the_map() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(20, 0, 0))
	var def: EnemyDef = Registry.enemy("saiga_sniper")
	var sn: Dictionary = def.sniper
	# a skeleton far behind the hero, on the line the shot will take (pass 81: he walks in from his stand-off to his
	# range first, `follow`, at the cactus's way: up to ~8 s more)
	var t_aim := _run_until(em, func() -> bool: return em.state[i] == EnemyManager.STATE_WINDUP, 16.0)
	assert_float(t_aim).is_greater(0.0)
	assert_int(em.sniper_aims).is_equal(1)
	assert_array(w["g"].hints).contains(["sniper"])
	var s: Dictionary = em._snipers[i]
	assert_int((s["lines"] as Array).size()).is_equal(int(sn["lines"]))
	# frozen while it aims: it does not walk
	var at0: Vector3 = em.pos[i]
	# the lines follow the hero while it aims
	hero.global_position = Vector3(0, 0, 2.0)
	var aim_s := float(sn["aim"]) / em.pace
	_run(em, aim_s * 0.5)
	assert_int(int(em._snipers[i]["phase"])).is_equal(EnemyManager.SNIPER_AIM)
	assert_float(_flat(em._snipers[i]["aim"], hero.global_position)).is_less(0.5)
	assert_bool(em._sniper_fx.busy()).is_true()
	# then they lock: the hero walks on, the line stays where it was
	var t_lock := _run_until(em, func() -> bool: return int(em._snipers[i]["phase"]) == EnemyManager.SNIPER_LOCK, aim_s)
	assert_float(t_lock).is_greater(0.0)
	var from: Vector3 = em._snipers[i]["from"]
	var ldir: Vector3 = em._snipers[i]["ldir"]
	assert_float(EnemyManager.beam_distance(hero.global_position, from, ldir, 60.0)).is_less(0.3)
	var behind := em.spawn("skeleton", from + ldir * 40.0)
	em.pos[behind] = Vector3(from.x, 0.0, from.z) + ldir * 40.0
	var hp0: float = em.hp[behind]
	var lock_s := float(sn["lock"]) / em.pace
	_run(em, lock_s * 0.5)
	assert_bool((em._snipers[i]["ldir"] as Vector3).is_equal_approx(ldir)).is_true()
	assert_int(em.sniper_shots).is_equal(0)
	# the hold ends with the shot: the hero still on the line takes 0.7 x the Raider's rocket
	var t_shot := _run_until(em, func() -> bool: return em.sniper_shots > 0, lock_s)
	assert_float(t_shot).is_greater(0.0)
	var hits: Array = hero.hits
	assert_int(hits.size()).is_equal(1)
	var rk: EnemyDef = Registry.enemy("rocketeer")
	var want := float(rk.artillery["missile"]["damage"]) * float(sn["beam"]["damage_mult"]) * em.stage_of(i) * em.lvd_of(i) * em.host_of(i)
	assert_float(float(hits[0]["amount"])).is_equal_approx(want, 0.001)
	assert_float(float(hits[0]["info"]["knock"])).is_equal(float(sn["beam"]["knockback"]))
	# the creature on the line: a little damage and a push off it
	assert_float(hp0 - em.hp[behind]).is_equal_approx(minf(em.max_hp[behind] * float(sn["beam"]["creature_frac"]), float(sn["beam"]["creature_max"])), 0.01)
	var side := Vector3(-ldir.z, 0, ldir.x)
	assert_float(absf(em.kb[behind].dot(side))).is_greater(1.0)
	# it never moved a muscle through the aim
	assert_float(_flat(em.pos[i], at0)).is_less(0.3)
	# the rest: the next shot interval +- jitter after this one
	var iv := float(sn["interval"])
	var jit := float(sn["interval_jitter"])
	var rest := em.cooldown[i] + (float(sn["aim"]) + float(sn["lock"])) / em.pace
	assert_float(rest).is_between(iv - jit - 0.05, iv + jit + 0.05)
	# he holds the aiming pose a breath after the shot (the beam's flash), then he is free to move again
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_WINDUP)
	assert_int(int(em._snipers[i]["phase"])).is_equal(EnemyManager.SNIPER_AFTER)
	_run(em, EnemyManager.SNIPER_AFTER_HOLD + 0.05)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_int(int(em._snipers[i]["phase"])).is_equal(EnemyManager.SNIPER_IDLE)
	assert_int(em.sniper_cancels).is_equal(0)


func test_stepping_off_the_locked_line_dodges_the_shot() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(20, 0, 0))
	_run_until(em, func() -> bool: return em._snipers.has(i) and int(em._snipers[i]["phase"]) == EnemyManager.SNIPER_LOCK, 20.0)
	var ldir: Vector3 = em._snipers[i]["ldir"]
	hero.global_position += Vector3(-ldir.z, 0, ldir.x) * 2.0
	_run_until(em, func() -> bool: return em.sniper_shots > 0, 3.0)
	assert_int(em.sniper_shots).is_equal(1)
	assert_int((hero.hits as Array).size()).is_equal(0)
	assert_bool(bool(em.sniper_last["hero_hit"])).is_false()


func test_a_hit_spoils_the_aim() -> void:
	# pass 81 (lane POLISH, re-pinned; was "... and sends him running"): the hit spoils the aim (sniper.spoil_on_hit) and
	# he runs no more: he holds where he is
	var w := _world()
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("saiga_sniper", Vector3(20, 0, 0))
	_run_until(em, func() -> bool: return em.state[i] == EnemyManager.STATE_WINDUP, 16.0)
	_run(em, 0.5)
	em.damage(i, 1.0, "revolver")
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_int(em.sniper_cancels).is_equal(1)
	assert_bool(em.is_fleeing(i)).is_false()
	var d0 := _flat(em.pos[i], hero.global_position)
	_run(em, 0.8)
	assert_float(_flat(em.pos[i], hero.global_position)).is_less_equal(d0 + 0.2)
	# no shot came of it, and the next aim waits its recovery
	_run(em, 1.0)
	assert_int(em.sniper_shots).is_equal(0)
	assert_int((hero.hits as Array).size()).is_equal(0)


func test_the_aim_strip_shows_its_front_or_its_back_half() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := em.spawn("saiga_sniper", Vector3(20, 0, 0))
	var t: int = em.type_idx[i]
	var off: int = em.strip_frames(t, EnemyManager.A_ATTACK).x
	var n: int = em.strip_frames(t, EnemyManager.A_ATTACK).y
	assert_int(n % 2).is_equal(0)
	em.away[i] = 0
	em.anim_t[i] = 0.0
	assert_int(em._attack_view_frame(i, t)).is_equal(off)
	em.away[i] = 1
	assert_int(em._attack_view_frame(i, t)).is_equal(off + (n >> 1))
	# a creature without the key keeps every attack frame front-on (the render never asks)
	var sk := em.spawn("skeleton", Vector3(3, 0, 0))
	assert_int(em._t_atkv[em.type_idx[sk]]).is_equal(0)
	assert_int(em._t_atkv[t]).is_equal(1)


func test_the_gathering_lines_come_closer_together_and_faster() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var plan := SniperFx.line_plan(14, 2.0, 44.0, rng)
	assert_int(plan.size()).is_equal(14)
	var gaps: Array = []
	for k in range(plan.size()):
		var l: Dictionary = plan[k]
		# every line lands by the lock, from one side of the cone or the other, alternately
		assert_float(float(l["t0"]) + float(l["dur"])).is_less_equal(2.0 + 0.0001)
		assert_float(absf(float(l["a0"]))).is_less_equal(deg_to_rad(22.0) + 0.0001)
		if k > 0:
			assert_float(float(l["a0"]) * float(plan[k - 1]["a0"])).is_less(0.0)
			assert_float(float(l["dur"])).is_less_equal(float(plan[k - 1]["dur"]) + 0.0001)
			gaps.append(float(l["t0"]) - float(plan[k - 1]["t0"]))
	for k in range(1, gaps.size()):
		assert_float(float(gaps[k])).is_less_equal(float(gaps[k - 1]) + 0.0001)
	# the angle closes on the hero
	var l0: Dictionary = plan[0]
	assert_float(absf(SniperFx.line_angle(l0, 0.0))).is_equal_approx(absf(float(l0["a0"])), 0.0001)
	assert_float(SniperFx.line_angle(l0, 1.0)).is_equal_approx(0.0, 0.0001)


func test_the_fx_draws_the_lines_the_beam_and_the_fading_sparks() -> void:
	var fx: SniperFx = auto_free(SniperFx.new())
	add_child(fx)
	var rng := RandomNumberGenerator.new()
	var plan := SniperFx.line_plan(10, 2.0, 44.0, rng)
	fx.begin()
	fx.aim(Vector3(20, 2, 0), Vector3.ZERO, 1.0, 2.0, plan)
	fx.redraw()
	assert_int(fx.drawn_lines).is_greater(1)
	fx.begin()
	fx.lock(Vector3(20, 2, 0), Vector3(-1, 0, 0), 20.0, 0.5, 1.0, 60.0, 0.5)
	fx.redraw()
	assert_int(fx.drawn_lines).is_equal(1)
	fx.begin()
	fx.beam(Vector3(20, 2, 0), Vector3(-1, 0, 0), 60.0, 0.5, 20.0, 0.15, 1.5)
	fx._process(0.05)
	assert_int(fx.drawn_beams).is_equal(1)
	assert_int(fx.drawn_sparks).is_greater(20)
	for k in range(30):
		fx._process(0.1)
	assert_bool(fx.busy()).is_false()


# ---------------------------------------------------------------- 5. the Vulture Raider's rocket

func test_every_hit_on_the_raider_shakes_his_rocket_and_halves_its_speed_for_three_seconds() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm := _projectiles(w["g"])
	var i := em.spawn("rocketeer", Vector3(30, 0, 0))
	var ms: Dictionary = (Registry.enemy("rocketeer").artillery["missile"] as Dictionary)
	assert_bool(ms.get("hit_slow") is Dictionary).is_true()
	var hs: Dictionary = ms["hit_slow"]
	# far off, so it never reaches the hero inside the test (its blast is Game's)
	var k := pm.launch_enemy_rocket(0, i, Vector3(100, 1, 0), Vector3(-1, 0, 0), 4.0, 1.3, 20.0, 1.6, 0.9, {}, ms)
	assert_int(k).is_greater_equal(0)
	pm._physics_process(DT)
	var v0: float = pm.vel[k].length()
	assert_float(pm.rocket_speed_share(k)).is_equal(1.0)
	# a poison tick is no hit
	em.damage(i, 0.1, "", Vector3.ZERO, 0.0, true)
	assert_int(pm.rocket_slows).is_equal(0)
	em.damage(i, 0.1, "revolver")
	assert_int(pm.rocket_slows).is_equal(1)
	pm._physics_process(DT)
	assert_float(pm.vel[k].length()).is_equal_approx(v0 * float(hs["mult"]), v0 * 0.02)
	assert_float(float(pm.extra[k]["shake_t"])).is_greater(0.0)
	# it shakes: its turn wobbles while the shake lasts (and not once it is over)
	var still := Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP)
	pm._physics_process(DT)
	assert_bool(pm.rocket_shake_basis(k, still).is_equal_approx(still)).is_false()
	# the recovery runs on the creatures' shot clock (EnemyManager.hostile_clock: the pace knob, High Noon), like every
	# hostile shot's flight: linear from `mult` to full over `recover` seconds of it
	var ck := em.hostile_clock()
	var steps := int(float(hs["recover"]) * 0.5 / (DT * ck))
	for n in range(steps):
		pm._physics_process(DT)
	var flown := float(steps + 2) * DT * ck
	assert_float(pm.rocket_speed_share(k)).is_equal_approx(lerpf(float(hs["mult"]), 1.0, flown / float(hs["recover"])), 0.01)
	assert_float(pm.rocket_speed_share(k)).is_equal_approx(0.75, 0.03)
	# a hit while it recovers starts it again from half, never lower
	em.damage(i, 0.1, "revolver")
	pm._physics_process(DT)
	assert_float(pm.rocket_speed_share(k)).is_between(float(hs["mult"]) - 0.001, float(hs["mult"]) + 0.02)
	for n in range(int(float(hs["recover"]) / (DT * ck)) + 5):
		pm._physics_process(DT)
	assert_float(pm.rocket_speed_share(k)).is_equal(1.0)
	assert_float(float(pm.extra[k].get("shake_t", 0.0))).is_equal(0.0)
	assert_bool(pm.rocket_shake_basis(k, still).is_equal_approx(still)).is_true()
