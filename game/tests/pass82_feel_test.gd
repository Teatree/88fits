extends GdUnitTestSuite

## Pass 82, lane FEEL (Garry: "Don't shake the screen when hero is damaged. Shake the hp bar instead. But do that a little
## bit." and "The explosion thing that affects the enemy's corpses with knockback should come from all weapons. I think
## currently it's just the dynamite."): a hit on the hero's health leaves the camera still and jiggles his HP bar
## (HUD.shake_hp_bar, Game._feel_hurt_bar_shake), which comes back to its place; every kill by a hit throws the body
## along the killing hit with a floor push and a floor toss that grow with the hit's weight (EnemyManager._corpse_follow);
## the boss keeps his death, big game slides as before, the living are not moved. Numbers are read off the constants.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_poison(_a) -> void:
	pass
func fx_fire(_a, _b = 1.0, _blue = false) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _blue = false) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	return null
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
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
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Save.begin_sandbox()
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Engine.time_scale = 1.0
	Run.debug_clear_items()
	Run.end()
	Save.end_sandbox()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at the origin, with the real crowd and effects.
func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
	g.player = hero
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": fx}


## A creature on its feet where it was put, every hit whole.
func _creature(em: EnemyManager, at: Vector3, id := "goblin", hp_mult := 1.0, elite: EliteModDef = null) -> int:
	var i := em.spawn(id, at, elite, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.dr[i] = 0.0
	em.speed[i] = 0.0
	em._rebuild_grid()
	return i


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Steps the crowd until body `i` is gone or `seconds` ran out; the highest it flew.
func _fly(em: EnemyManager, i: int, seconds: float) -> float:
	var top := 0.0
	for k in range(int(seconds / DT)):
		em._physics_process(DT)
		top = maxf(top, em.lift_h[i])
		assert_float(em.lift_h[i]).is_greater_equal(0.0)
	return top


# ---------------------------------------------------------------- the hurt shakes the HP bar, not the camera

func _launch(d: Dictionary) -> void:
	var f := FileAccess.open("user://debug_launch.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func test_a_hurt_leaves_the_camera_still_and_jiggles_the_hp_bar_back_into_place() -> void:
	_launch({"weapon": "revolver", "level": 1, "character": "drifter", "map": "red_canyon", "map_seed": 11, "analytics": false})
	var g: Game = auto_free(load("res://game/Game.tscn").instantiate())
	add_child(g)
	await get_tree().create_timer(0.3).timeout
	g.set_process(false)
	var p: Player = g.player
	var hud: HUD = g.hud
	var cam: CameraRig = g.camera
	assert_float(hud.hp_shake_x).is_equal(0.0)
	# a plain hit on his health (an evade's roll can miss it: try again until one lands)
	var landed := false
	for k in range(20):
		cam._shake = 0.0
		p.invuln = 0.0
		p.shield_pts = 0.0
		p.take_damage(12.0, p.global_position + Vector3(1, 0, 0), {"by": "test"})
		Engine.time_scale = 1.0
		if p.last_outcome == "hit":
			landed = true
			break
	assert_bool(landed).is_true()
	# the camera is left alone
	assert_float(cam._shake).is_equal(0.0)
	# the bar's jiggle starts at the hit's size: the hit's share of his max HP
	var dealt: float = float((p.damage_log[p.damage_log.size() - 1] as Dictionary)["dealt"])
	var amp := HUD.hp_shake_amp_for(dealt / p.max_hp)
	assert_float(hud._hp_shake_t).is_equal(0.0)
	assert_float(hud._hp_shake_amp).is_equal_approx(amp, 0.0001)
	assert_float(amp).is_less_equal(HUD.HP_SHAKE_MAX_PX)
	# it swings both ways, never past its size, and is back at exactly 0 once its time is out
	var lo := 0.0
	var hi := 0.0
	for k in range(int(HUD.HP_SHAKE_TIME / DT) + 3):
		hud._tick_hp_shake(DT)
		lo = minf(lo, hud.hp_shake_x)
		hi = maxf(hi, hud.hp_shake_x)
		assert_float(absf(hud.hp_shake_x)).is_less_equal(amp + 0.0001)
	assert_float(hi).is_greater(amp * 0.5)
	assert_float(lo).is_less(-amp * 0.3)
	assert_float(hud.hp_shake_x).is_equal(0.0)
	assert_float(hud._hp_shake_t).is_equal(-1.0)


func test_the_hp_bar_shake_is_small_grows_with_the_hit_and_is_capped() -> void:
	assert_float(HUD.hp_shake_amp_for(0.0)).is_equal(HUD.HP_SHAKE_PX)
	assert_float(HUD.hp_shake_amp_for(0.05)).is_equal_approx(HUD.HP_SHAKE_PX + HUD.HP_SHAKE_PX_PER_HP * 0.05, 0.0001)
	assert_float(HUD.hp_shake_amp_for(0.1)).is_greater(HUD.hp_shake_amp_for(0.05))
	assert_float(HUD.hp_shake_amp_for(5.0)).is_equal(HUD.HP_SHAKE_MAX_PX)
	assert_float(HUD.HP_SHAKE_MAX_PX).is_less_equal(12.0)
	assert_float(HUD.HP_SHAKE_TIME).is_between(0.2, 0.3)
	# at rest before and after, inside its size in between
	assert_float(HUD.hp_shake_at(-0.1, 8.0)).is_equal(0.0)
	assert_float(HUD.hp_shake_at(0.0, 8.0)).is_equal(0.0)
	assert_float(HUD.hp_shake_at(HUD.HP_SHAKE_TIME, 8.0)).is_equal(0.0)
	for k in range(30):
		assert_float(absf(HUD.hp_shake_at(HUD.HP_SHAKE_TIME * float(k) / 30.0, 8.0))).is_less_equal(8.0)
	# a smaller hit while a big jiggle runs keeps what is left of the big one
	var hud: HUD = auto_free(HUD.new())
	hud.shake_hp_bar(1.0)
	hud._tick_hp_shake(0.02)
	hud.shake_hp_bar(0.0)
	var u := 0.02 / HUD.HP_SHAKE_TIME
	assert_float(hud._hp_shake_amp).is_equal_approx(HUD.HP_SHAKE_MAX_PX * (1.0 - u) * (1.0 - u), 0.0001)
	assert_float(hud._hp_shake_t).is_equal(0.0)


# ---------------------------------------------------------------- every kill throws its body

func test_a_no_knockback_kill_throws_its_body_at_least_the_floor() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(0, 0, -6))
	var p0: Vector3 = em.pos[i]
	# a chip of a kill (no push, no direction): the floor, away from the hero
	em.hp[i] = 0.01
	assert_bool(em.damage(i, 0.01, "", Vector3.ZERO, 0.0)).is_true()
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_int(em.corpse_tosses).is_equal(1)
	assert_bool(em._corpse_air.has(i)).is_true()
	assert_int(em._corpse_kill_i).is_equal(-1)
	var fp := EnemyManager.corpse_floor_push(0.0, em.size[i])
	assert_float(fp).is_greater_equal(EnemyManager.CORPSE_FLOOR_PUSH * EnemyManager.CORPSE_HEFT_MIN)
	assert_float(-em.kb[i].z).is_equal_approx(fp, 0.01)
	var top := _fly(em, i, 1.2)
	assert_float(top).is_greater_equal(EnemyManager.CORPSE_FLOOR_TOSS - 0.05)
	assert_float(top).is_less(EnemyManager.CORPSE_FLOOR_TOSS + 0.15)
	assert_int(em.corpse_landings).is_equal(1)
	# back from the hero, a metre or more, on the ground at the end
	var went := _flat(em.pos[i]).distance_to(_flat(p0))
	assert_float(went).is_greater(1.0)
	assert_float(went).is_less(2.5)
	assert_float(em.pos[i].z).is_less(p0.z)
	assert_float(absf(em.pos[i].x - p0.x)).is_less(0.05)
	assert_float(em.lift_h[i]).is_equal(0.0)


func test_a_weapon_kill_goes_the_way_the_hit_went() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(0, 0, -6))
	var p0: Vector3 = em.pos[i]
	# a revolver round flying east, no knockback: the body goes east, not away from the hero (north)
	assert_bool(em.damage(i, 99999.0, "revolver", Vector3(1, 0, 0), 0.0)).is_true()
	assert_int(em.corpse_tosses).is_equal(1)
	_fly(em, i, 1.4)
	assert_float(em.pos[i].x - p0.x).is_greater(1.0)
	assert_float(absf(em.pos[i].z - p0.z)).is_less(0.1)


func test_a_burn_kill_is_thrown_away_from_the_hero() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _creature(em, Vector3(4, 0, 0))
	var p0: Vector3 = em.pos[i]
	em.hp[i] = 0.5
	assert_bool(em.damage(i, 1.0, "molotov", Vector3.ZERO, 0.0, false, true)).is_true()
	assert_int(em.corpse_tosses).is_equal(1)
	_fly(em, i, 1.2)
	assert_float(em.pos[i].x - p0.x).is_greater(1.0)


func test_heavier_hits_throw_further_and_higher_within_a_cap() -> void:
	# the weight: the hit over CORPSE_HEAVY_RATIO max HPs, a crit's share on top, never past 1
	assert_float(EnemyManager.corpse_kill_weight(0.0, false)).is_equal(0.0)
	assert_float(EnemyManager.corpse_kill_weight(EnemyManager.CORPSE_HEAVY_RATIO * 0.5, false)).is_equal_approx(0.5, 0.0001)
	assert_float(EnemyManager.corpse_kill_weight(0.0, true)).is_equal_approx(EnemyManager.CORPSE_CRIT_WEIGHT, 0.0001)
	assert_float(EnemyManager.corpse_kill_weight(0.0, false, true)).is_equal_approx(EnemyManager.CORPSE_CRIT_WEIGHT * 0.5, 0.0001)
	assert_float(EnemyManager.corpse_kill_weight(1000.0, true)).is_equal(1.0)
	# the push and the toss between the floor and the heavy end; the hit's own push adds height up to the cap
	assert_float(EnemyManager.corpse_floor_push(0.0, 1.0)).is_equal_approx(EnemyManager.CORPSE_FLOOR_PUSH, 0.0001)
	assert_float(EnemyManager.corpse_floor_push(1.0, 1.0)).is_equal_approx(EnemyManager.CORPSE_HEAVY_PUSH, 0.0001)
	assert_float(EnemyManager.corpse_floor_push(0.0, 3.4)).is_equal_approx(EnemyManager.CORPSE_FLOOR_PUSH * maxf(EnemyManager.CORPSE_HEFT_SIZE / 3.4, EnemyManager.CORPSE_HEFT_MIN), 0.0001)
	assert_float(EnemyManager.corpse_kill_toss(0.0, 0.0)).is_equal_approx(EnemyManager.CORPSE_FLOOR_TOSS, 0.0001)
	assert_float(EnemyManager.corpse_kill_toss(1.0, 0.0)).is_equal_approx(EnemyManager.CORPSE_HEAVY_TOSS, 0.0001)
	assert_float(EnemyManager.corpse_kill_toss(1.0, 1000.0)).is_equal(EnemyManager.CORPSE_HIT_TOSS_MAX)
	assert_float(EnemyManager.CORPSE_HIT_TOSS_MAX).is_less_equal(EnemyManager.CORPSE_TOSS_MAX)
	# in the crowd: a one-shot many times over flies higher and further than a chip
	var w := _world()
	var em: EnemyManager = w["em"]
	var a := _creature(em, Vector3(-3, 0, -6))
	var b := _creature(em, Vector3(3, 0, -6))
	var pa: Vector3 = em.pos[a]
	var pb: Vector3 = em.pos[b]
	em.hp[a] = 0.01
	em.damage(a, 0.01, "", Vector3(0, 0, -1), 0.0)
	em.damage(b, em.max_hp[b] * 100.0, "", Vector3(0, 0, -1), 0.0)
	var top_a := 0.0
	var top_b := 0.0
	for k in range(int(1.3 / DT)):
		em._physics_process(DT)
		top_a = maxf(top_a, em.lift_h[a])
		top_b = maxf(top_b, em.lift_h[b])
	assert_float(top_b).is_greater(top_a + 0.3)
	assert_float(top_b).is_less_equal(EnemyManager.CORPSE_HIT_TOSS_MAX + 0.05)
	assert_float(pb.z - em.pos[b].z).is_greater((pa.z - em.pos[a].z) * 1.4)


func test_a_blast_kill_flies_at_least_as_high_as_before() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var centre := Vector3(0, 0, -6)
	var i := _creature(em, centre + Vector3(1.0, 0, 0))
	var force := 40.0
	var push := force / maxf(em.size[i], 0.8) * em._t_kbt[em.type_idx[i]] * em.hero_knock_mult()
	em.damage_radius(centre, 2.5, 99999.0, "lob_grenade", force)
	assert_int(em.corpse_tosses).is_equal(1)
	var top := _fly(em, i, 1.6)
	assert_float(top).is_greater_equal(EnemyManager.corpse_toss_height(push) - 0.15)
	assert_float(em.pos[i].x).is_greater(centre.x + 1.0)


func test_a_boss_does_not_fly() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := em.spawn_boss("tumbleweed_king", Vector3(0, 0, -8))
	assert_int(i).is_greater_equal(0)
	em.boss_index = i
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em._rebuild_grid()
	var p0: Vector3 = em.pos[i]
	em.damage(i, 99999999.0, "revolver", Vector3(0, 0, -1), 0.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_float(em.kb[i].length()).is_equal(0.0)
	assert_int(em.corpse_tosses).is_equal(0)
	for k in range(30):
		em._physics_process(DT)
	assert_float(_flat(em.pos[i]).distance_to(_flat(p0))).is_less(0.001)
	assert_float(em.lift_h[i]).is_equal(0.0)


func test_big_game_slides_on_its_own_push_as_before() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var mods: Array = Registry.elites.values()
	assert_int(mods.size()).is_greater(0)
	var i := _creature(em, Vector3(0, 0, -6), "goblin", 1.0, mods[0])
	assert_bool(em.is_big_game(i)).is_true()
	var force := 10.0
	var push := force / maxf(em.size[i], 0.8) * em._t_kbt[em.type_idx[i]] * em.hero_knock_mult()
	em.damage(i, 99999999.0, "revolver", Vector3(0, 0, -1), force)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	assert_float(em.kb[i].length()).is_equal_approx(push, 0.001)
	assert_int(em.corpse_tosses).is_equal(0)
	em._physics_process(DT)
	assert_float(em.lift_h[i]).is_equal(0.0)


func test_the_living_and_a_body_still_rising_are_not_thrown() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	# a survivor of a no-knockback hit stands where it was
	var a := _creature(em, Vector3(-2, 0, -6), "goblin", 500.0)
	em.damage(a, 1.0, "revolver", Vector3(0, 0, -1), 0.0)
	assert_int(em.state[a]).is_not_equal(EnemyManager.STATE_DYING)
	assert_float(em.kb[a].length()).is_equal(0.0)
	assert_float(em.lift_h[a]).is_equal(0.0)
	# one still coming up out of the sand (not a target yet: a blast's area hit) sinks where it is
	var b := _creature(em, Vector3(2, 0, -6))
	em.rise_t[b] = em.rise_targetable * 0.5
	em.damage(b, 99999.0, "revolver", Vector3(0, 0, -1), 0.0)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_DYING)
	assert_float(em.kb[b].length()).is_equal(0.0)
	assert_int(em.corpse_tosses).is_equal(0)
	# one nearly up (a target already) is shown whole and thrown
	var c := _creature(em, Vector3(5, 0, -6))
	em.rise_t[c] = (em.rise_targetable + 1.0) * 0.5
	em.damage(c, 99999.0, "revolver", Vector3(0, 0, -1), 0.0)
	assert_int(em.corpse_tosses).is_equal(1)
	assert_float(em.rise_t[c]).is_equal(1.0)
	assert_float(-em.kb[c].z).is_greater(0.0)


func test_a_thrown_body_stays_inside_the_arena() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var r := em.arena_radius
	var i := _creature(em, Vector3(r - 2.2, 0, 0))
	em.damage(i, 99999.0, "revolver", Vector3(1, 0, 0), 0.0, false, false, EnemyManager.HIT_CRIT)
	assert_int(em.corpse_tosses).is_equal(1)
	for k in range(90):
		em._physics_process(DT)
		assert_float(_flat(em.pos[i]).length()).is_less_equal(r - 2.0 + 0.001)
		assert_float(em.lift_h[i]).is_greater_equal(0.0)
