extends GdUnitTestSuite

## Pass 126, lane BOSS (Garry: "A new Boss is needed of course. Try looking at our other Bosses critically and coming up with
## something that is very similar, but has a unique twist to it and implement them already"): Black Sunday's content, the
## built-in attack `whirl` (core/systems/BossWhirl.gd: he becomes the storm, hunts the hero, his crowd rides and falls hurt, the
## hero is thrown and hit once per cooldown, then he stands dazed at x1.5), his bullet heaven and his chest.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var hud = null
var paused := false
var rings: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e, _f = 1.2) -> void:
	pass
func telegraph_ring(a, b, c, _d, e = true) -> void:
	rings.append({"at": a, "r": float(b), "dur": float(c), "filled": bool(e)})
func shockwave(_a, _b) -> void:
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
var last_outcome := "hit"
var immune := false
var dodge := false
var hits: Array = []
var launches: Array = []
func take_damage(a: float, f: Vector3, i: Dictionary = {}) -> void:
	hits.append({"amount": a, "from": f, "info": i})
	last_outcome = "evaded" if dodge else "hit"
func launch(v: Vector3) -> void:
	launches.append(v)
func knock_immune() -> bool:
	return immune
func special_push(_v: Vector3) -> void:
	pass
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


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false
	Run.kills = 0
	Run.level = 1


func after_test() -> void:
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


func _boss() -> EnemyDef:
	return Registry.enemy("black_sunday")


func _row(atk_name: String) -> Dictionary:
	for a in _boss().boss.get("attacks", []):
		if str((a as Dictionary).get("name", "")) == atk_name:
			return a
	return {}


func _attack_index(atk_name: String) -> int:
	var attacks: Array = _boss().boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


## The boss at `at`, up and ready (no rise), its whirl about to be chosen.
func _spawn_boss(em: EnemyManager, at: Vector3) -> int:
	var b := em.spawn("black_sunday", at)
	em.rise_t[b] = 1.0
	em.rise_v[b] = 0.0
	em.state[b] = EnemyManager.STATE_MOVE
	em.atk_i[b] = _attack_index("whirl")
	em.atk_t[b] = 0.0
	em.hold_t[b] = 0.0
	return b


## Starts the whirl's wind-up (as the runner does) and ends it: he is the storm now.
func _whirl_now(em: EnemyManager, b: int) -> void:
	em._update_attacks(b, DT, em.player.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int(em.whirls.phase_of(b)).is_equal(BossWhirl.TELL)
	em.timer[b] = 0.0
	em._update_attacks(b, DT, em.player.global_position)
	assert_int(em.whirls.phase_of(b)).is_equal(BossWhirl.SPIN)


# ---------------------------------------------------------------- 1. the content

func test_the_design_numbers_are_in_the_json() -> void:
	var d := _boss()
	assert_object(d).is_not_null()
	assert_str(d.display_name).is_equal("Black Sunday")
	assert_str(d.archetype).is_equal("boss")
	assert_float(d.hp).is_equal(7500.0)
	assert_float(d.speed).is_equal(1.5)
	assert_float(d.damage).is_equal(27.0)
	assert_float(float(d.xp_mult)).is_equal(75.0)
	assert_int(int(d.drops.get("coins", 0))).is_equal(44)
	assert_int(int(d.drops.get("chests", 0))).is_equal(2)
	var chest: Dictionary = d.boss.get("chest", {})
	assert_str(str(chest.get("name", ""))).is_equal("Collection Box")
	assert_str(str(chest.get("shine", ""))).is_equal("#d9a35a")
	var names: Array = []
	for a in d.boss.get("attacks", []):
		names.append(str((a as Dictionary).get("name", "")))
	assert_array(names).contains(["come_here", "spawn_ring", "tumbleweed_volley", "whirl", "black_blizzard"])
	assert_array(names).not_contains(["roll"])
	assert_str(str(_row("spawn_ring")["enemy"])).is_equal("straw_man")
	assert_int(int(_row("tumbleweed_volley")["count"])).is_equal(14)
	assert_float(float(_row("tumbleweed_volley")["speed"])).is_equal(10.0)


func test_the_map_names_his_hp_scaling_seconds() -> void:
	# read from the map file: Garry tunes it
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/maps/red_canyon/red_canyon.json"))
	var scaling: Dictionary = (m["timeline_data"] as Dictionary).get("boss_hp_scaling", {})
	var secs: Dictionary = scaling.get("seconds", {}) if scaling.get("seconds") is Dictionary else {}
	assert_bool(secs.has("black_sunday")).is_true()


func test_the_blizzard_is_a_rare_pattern_of_its_own() -> void:
	var c: BossAttackDef = Registry.boss_attack("black_blizzard")
	assert_object(c).is_not_null()
	assert_bool(c.is_pattern()).is_true()
	assert_str(c.text("projectile", "look")).is_equal("grit_clod")
	assert_bool(BossAttackFx.is_billboard("grit_clod")).is_true()
	assert_str(c.text("barrier", "look")).is_equal("cross_fence")
	assert_bool(c.barrier_on()).is_true()
	assert_dict(BarrierMeshes.parts("cross_fence")).contains_keys(["cross", "straw", "wire"])
	# never inside the cycle: a pattern is left out of the runner's list, as every boss's
	var em: EnemyManager = _world()["em"]
	for a in em.custom_resolved(_boss(), _boss().boss["attacks"]):
		assert_str(str((a as Dictionary).get("name", ""))).is_not_equal("black_blizzard")
	# the shape: bullets enough to be a bullet heaven, no more than the Brander's mandala keeps in the air twice over
	var sim: Dictionary = c.simulate()
	var mandala: Dictionary = (Registry.boss_attack("hellbrand_mandala") as BossAttackDef).simulate()
	assert_int(int(sim["peak"])).is_greater(40)
	assert_int(int(sim["peak"])).is_less(int(mandala["peak"]) * 2)


func test_config_merges_groups_key_by_key() -> void:
	var c := BossWhirl.config_of({"radius": 3.0, "toss": {"up": 1.0}, "dazed": {"seconds": 9.0}, "name": "whirl"})
	assert_float(float(c["radius"])).is_equal(3.0)
	assert_float(float(c["seconds"])).is_equal(float(BossWhirl.DEFAULTS["seconds"]))
	assert_float(float(c["toss"]["up"])).is_equal(1.0)
	assert_float(float(c["toss"]["out"])).is_equal(float(BossWhirl.DEFAULTS["toss"]["out"]))
	assert_float(float(c["dazed"]["seconds"])).is_equal(9.0)
	assert_float(float(c["dazed"]["damage_taken"])).is_equal(1.5)
	assert_bool(c.has("name")).is_false()
	assert_float(BossWhirl.reach_of(c)).is_equal(3.0 + DustDevils.HERO_REACH)


# ---------------------------------------------------------------- 2. the whirl

func test_the_wind_up_draws_a_ring_and_nothing_moves_him() -> void:
	var w := _world(Vector3(15, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var b := _spawn_boss(em, Vector3.ZERO)
	(g.rings as Array).clear()
	em._update_attacks(b, DT, em.player.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int(em.whirls.phase_of(b)).is_equal(BossWhirl.TELL)
	assert_int((g.rings as Array).size()).is_equal(1)
	assert_float(float(g.rings[0]["r"])).is_equal_approx(float(_row("whirl")["radius"]), 0.001)
	assert_float(float(g.rings[0]["dur"])).is_equal_approx(float(_row("whirl")["windup"]) / em.pace, 0.001)


func test_he_hunts_the_hero_at_72_percent_of_a_fresh_hero_and_stays_a_target() -> void:
	var w := _world(Vector3(15, 0, 0))
	var em: EnemyManager = w["em"]
	var b := _spawn_boss(em, Vector3.ZERO)
	_whirl_now(em, b)
	var at0: Vector3 = em.pos[b]
	var hit_hp: float = em.hp[b]
	for _k in range(60):
		em._physics_process(DT)
	var moved: float = Vector2(em.pos[b].x - at0.x, em.pos[b].z - at0.z).length()
	# 1 s at speed x pace: move_pace 0.9 x creature_speed_mult 0.9 with the JSON's 3.2 = 2.6 m/s (the map file may change)
	assert_float(moved).is_equal_approx(float(_row("whirl")["speed"]) * em.pace, 0.25)
	assert_float(em.pos[b].x).is_greater(at0.x)
	# he is no ghost: a hit lands, whole
	assert_int(em.hidden[b]).is_equal(0)
	assert_bool(em.targetable(b)).is_true()
	em.damage(b, 100.0, "", Vector3.ZERO, 0.0)
	assert_float(em.hp[b]).is_equal_approx(hit_hp - 100.0, 0.01)
	assert_bool(em.lift_h[b] > 0.0).is_true()


func test_creatures_in_reach_ride_and_fall_hurt_and_the_boss_never_rides() -> void:
	var w := _world(Vector3(15, 0, 0))
	var em: EnemyManager = w["em"]
	var b := _spawn_boss(em, Vector3.ZERO)
	var near := em.spawn("goblin", Vector3(2.0, 0, 0))
	var far := em.spawn("goblin", Vector3(-20.0, 0, 0))
	em.rise_t[near] = 1.0
	em.rise_t[far] = 1.0
	em.state[near] = EnemyManager.STATE_MOVE
	em.state[far] = EnemyManager.STATE_MOVE
	em.max_hp[near] = 1000.0
	em.hp[near] = 1000.0
	_whirl_now(em, b)
	em._rebuild_grid()
	em.whirls.tick(DT, em.player.global_position)
	assert_float(em.lift_t[near]).is_greater(0.0)
	assert_float(em.lift_t[far]).is_equal(0.0)
	assert_float(em.lift_t[b]).is_equal(0.0)
	assert_int(em.whirls.lifted).is_greater_equal(1)
	# it comes down hurt by the row's share of its max HP, and is not taken again for a while
	var t := 0.0
	while t < 4.0 and em.lift_t[near] > 0.0:
		em._physics_process(DT)
		t += DT
	assert_float(em.hp[near]).is_equal_approx(1000.0 * (1.0 - float(_row("whirl")["landing_damage"])), 1.0)
	assert_float(em.lift_cd[near]).is_greater(3.0)
	assert_float(em.lift_land[near]).is_equal(0.0)


func test_a_big_one_falls_softer_and_a_plain_dust_devil_as_ever() -> void:
	var w := _world(Vector3(15, 0, 0))
	var em: EnemyManager = w["em"]
	var i := em.spawn("goblin", Vector3(1.0, 0, 0))
	em.rise_t[i] = 1.0
	em.state[i] = EnemyManager.STATE_MOVE
	em.max_hp[i] = 1000.0
	em.hp[i] = 1000.0
	em._rebuild_grid()
	# a plain ride: 8%
	assert_int(em.lift_radius(em.pos[i], 2.0, 0.1)).is_equal(1)
	assert_float(em.lift_land[i]).is_equal(0.0)
	for _k in range(10):
		em._physics_process(DT)
	assert_float(em.hp[i]).is_equal_approx(920.0, 1.0)
	# a coloured special on a named ride: the big share
	em.lift_cd[i] = 0.0
	em.vspecial[i] = 1
	assert_int(em.lift_radius(em.pos[i], 2.0, 0.1, EnemyManager.TORNADO_LIFT_H, {"land": 0.75, "land_big": 0.12})).is_equal(1)
	assert_float(em.lift_land[i]).is_equal_approx(0.12, 0.0001)


func test_the_hero_is_thrown_and_hit_once_per_cooldown_and_no_bite() -> void:
	var w := _world(Vector3(1.0, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node = w["hero"]
	var b := _spawn_boss(em, Vector3.ZERO)
	_whirl_now(em, b)
	var row := _row("whirl")
	var cd: float = float((row["toss"] as Dictionary)["cooldown"])
	# standing inside for the whole storm
	var secs := float(row["seconds"])
	var t := 0.0
	while t < secs - DT * 2.0:
		em._physics_process(DT)
		t += DT
	var n: int = (hero.launches as Array).size()
	assert_int(n).is_equal(int(ceil(secs / cd)))
	assert_int((hero.hits as Array).size()).is_equal(n)
	var v: Vector3 = hero.launches[0]
	assert_float(v.y).is_equal_approx(float((row["toss"] as Dictionary)["up"]), 0.001)
	assert_float(Vector2(v.x, v.z).length()).is_equal_approx(float((row["toss"] as Dictionary)["out"]), 0.01)
	assert_float(float(hero.hits[0]["amount"])).is_greater(0.0)
	assert_str(str((hero.hits[0]["info"] as Dictionary)["kind"])).is_equal("boss")
	assert_float(float((hero.hits[0]["info"] as Dictionary)["knock"])).is_equal(0.0)


func test_an_evade_or_the_bubble_leaves_him_standing() -> void:
	var w := _world(Vector3(1.0, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node = w["hero"]
	hero.dodge = true
	var b := _spawn_boss(em, Vector3.ZERO)
	_whirl_now(em, b)
	em.whirls.tick(DT, hero.global_position)
	assert_int((hero.launches as Array).size()).is_equal(0)
	assert_int(em.whirls.saved).is_equal(1)
	# the cooldown still ran: no second try the next tick
	em.whirls.tick(DT, hero.global_position)
	assert_int((hero.hits as Array).size()).is_equal(1)
	hero.dodge = false
	hero.immune = true
	for _k in range(int(1.7 / DT)):
		em.whirls.tick(DT, hero.global_position)
	assert_int((hero.launches as Array).size()).is_equal(0)


func test_then_dazed_at_one_and_a_half_then_the_cycle_resumes() -> void:
	var w := _world(Vector3(15, 0, 0))
	var em: EnemyManager = w["em"]
	var b := _spawn_boss(em, Vector3.ZERO)
	_whirl_now(em, b)
	var row := _row("whirl")
	var t := 0.0
	while t < float(row["seconds"]) + 0.5 and em.whirls.phase_of(b) == BossWhirl.SPIN:
		em._physics_process(DT)
		t += DT
	assert_float(t).is_equal_approx(float(row["seconds"]), 0.1)
	assert_int(em.whirls.phase_of(b)).is_equal(BossWhirl.DAZED)
	assert_float(em.lift_h[b]).is_equal(0.0)
	# he stands
	var at: Vector3 = em.pos[b]
	for _k in range(30):
		em._physics_process(DT)
	assert_float(Vector2(em.pos[b].x - at.x, em.pos[b].z - at.z).length()).is_less(0.15)
	var hp0: float = em.hp[b]
	em.damage(b, 100.0, "", Vector3.ZERO, 0.0)
	assert_float(hp0 - em.hp[b]).is_equal_approx(100.0 * float((row["dazed"] as Dictionary)["damage_taken"]), 0.01)
	# over: as he was, walking, his next attack after the rest
	t = 0.0
	while t < 4.0 and em.whirls.running(b):
		em._physics_process(DT)
		t += DT
	assert_bool(em.whirls.running(b)).is_false()
	assert_int(em.whirls.ended).is_equal(1)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_MOVE)
	assert_bool(em.patterns == null or not em.patterns.mult.has(b)).is_true()
	assert_float(em.atk_t[b]).is_greater(0.0)
	hp0 = em.hp[b]
	em.damage(b, 100.0, "", Vector3.ZERO, 0.0)
	assert_float(hp0 - em.hp[b]).is_equal_approx(100.0, 0.01)


func test_killing_him_mid_whirl_lets_everything_go() -> void:
	var w := _world(Vector3(15, 0, 0))
	var em: EnemyManager = w["em"]
	var b := _spawn_boss(em, Vector3.ZERO)
	_whirl_now(em, b)
	em.damage(b, em.hp[b] + 10.0, "", Vector3.ZERO, 0.0)
	for _k in range(3):
		em._physics_process(DT)
	assert_bool(em.whirls.running(b)).is_false()
	assert_int(em.whirls.cut).is_equal(1)


func test_a_whirler_that_is_no_boss_never_takes_itself() -> void:
	# (lift_radius leaves out only the boss by name; the whirl guards the rest)
	var w := _world(Vector3(15, 0, 0))
	var em: EnemyManager = w["em"]
	var i := em.spawn("goblin", Vector3.ZERO)
	em.rise_t[i] = 1.0
	em.state[i] = EnemyManager.STATE_ATTACK
	em.timer[i] = 1.0
	em._whirls_of().begin(i, {"name": "whirl"}, em.player.global_position)
	em._rebuild_grid()
	em.whirls.tick(DT, em.player.global_position)
	assert_float(em.lift_t[i]).is_equal(0.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)


func test_the_same_steps_play_the_same_whirl() -> void:
	# no dice in the rules: two runs of the same ticks end at the same place
	var ends: Array = []
	for _r in range(2):
		var w := _world(Vector3(6, 0, 3))
		var em: EnemyManager = w["em"]
		var b := _spawn_boss(em, Vector3.ZERO)
		_whirl_now(em, b)
		for _k in range(180):
			em._physics_process(DT)
		ends.append(em.pos[b])
		# (gone before the next world's boss: EnemyManager.boss_index is per manager, the pools are its own)
		em.whirls.clear_all()
	assert_vector(ends[0]).is_equal(ends[1])


func test_his_chest_has_its_model_and_its_three_paintings() -> void:
	var chest: Dictionary = _boss().boss.get("chest", {})
	assert_bool(ResourceLoader.exists(str(chest.get("model", "")))).is_true()
	for f: String in ["closed", "cracked", "open"]:
		assert_bool(ResourceLoader.exists(str(chest.get("art", "")).replace("%s", f))).is_true()
	assert_str(str(BossChest.look("black_sunday")["name"])).is_equal("Collection Box")
