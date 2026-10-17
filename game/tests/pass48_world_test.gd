extends GdUnitTestSuite

## Pass 48, lane L5 (the world): the pace knob carried through every move and every warning (a creature walks, steps and
## charges at the pace, its shots, rumbles, boulders and stalactites run on the paced clock, every wind-up and telegraph
## lasts 1/pace, and the hostile rocket pays the pace once); the portal's one wave and the quiet after it; "Not yet" and
## the portal asking again once the hero has stepped out; the arena's training dummies (rows of five, undying or standing
## up again, walking home, never biting); the Vulture Raider's health and launcher; the black rare barrels with brass
## hoops and the King's black tumbleweeds; the speed looks (Barrel Rush a thin gold ribbon only, a Sprint's blue ribbon
## and wind, Skedaddle's red ribbon, each at its own height).

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var fx = null
var pickups = null
var hud = null
var paused := false
var _ended := false
var lines: Array = []
var rings: Array = []
var sectors: Array = []
var missiles: Array = []
var boulders: Array = []
var toasts: Array = []
func toast(t, _c = null) -> void:
	toasts.append(str(t))
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
func fx_lightning(_a) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(_a, _b, c, d, _e) -> void:
	lines.append({"length": float(c), "dur": float(d)})
func telegraph_ring(_a, b, c, _d, _e = true) -> void:
	rings.append({"r": float(b), "dur": float(c)})
func telegraph_sector(_a, _b, c, _d, e, _f) -> void:
	sectors.append({"r": float(c), "dur": float(e)})
func shockwave(_a, _b) -> void:
	pass
func rumble_mark(_a, _b) -> void:
	pass
func stalactite(_a, _b, _c = 1.0, _d = 9.0) -> void:
	pass
func stalactite_hit(_a) -> void:
	pass
func erupt_mound(_a, _b, _c) -> void:
	pass
func light_pillar(_a, _b, _c) -> void:
	pass
func throw_boulder(_t, from, to, atk, _m, _i) -> void:
	boulders.append({"from": from, "to": to, "flight": float(atk.get("flight", 1.6))})
func boulder_land(_a, _b, _c, _d = -1) -> void:
	pass
func enemy_missile(shooter, from, _s, _t, _d, _a, _soh = 0.0, _i = {}, _b = {}) -> void:
	missiles.append({"shooter": shooter, "from": from})
func rocket_out(_i) -> bool:
	return false
func enemy_shot_straight(_a, _b, _c, _d, _e, _f = {}) -> void:
	pass
func enemy_spit(_a, _b, _c, _d, _e, _f = {}) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

## a hero stand-in whose top speed carries the pace knob as Player.max_speed does
const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
var hits := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0 * Run.move_pace()
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

## the director's pickups: the boss chest is all it is asked for
const FAKE_PICKUPS := """extends Node
var chests: Array = []
func spawn_chest(at: Vector3, boss: bool = false) -> void:
	chests.append({"at": at, "boss": boss})
"""

const DT := 1.0 / 60.0

var _added: Array = []
var _pace_keep := 1.0


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	_pace_keep = Run.map.timeline.move_pace


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	var m: MapDef = Registry.map("red_canyon")
	if m and m.timeline:
		m.timeline.move_pace = _pace_keep
	Run.elapsed = 0.0
	Run.stage = 0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at`, with the real crowd and shots.
func _world(hero_at := Vector3(0, 0, 0)) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
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
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm}


func _pace(p: float) -> void:
	Run.map.timeline.move_pace = p


## A test creature (`id`) made from `from` with another brain, no variance, and the given fields; gone after the test.
func _test_def(id: String, from: String, brain: String, fields: Dictionary = {}) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	d.brain = brain
	d.variance = {}
	for k: String in fields.keys():
		d.set(k, fields[k])
	Registry.enemies[id] = d
	_added.append(id)
	return d


func _attack_index(def: EnemyDef, atk_name: String) -> int:
	var attacks: Array = def.boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


## The scripted creature `id` at `at`, its next attack the one called `atk_name`, started now.
func _start_attack(em: EnemyManager, id: String, atk_name: String, at: Vector3) -> int:
	var i := em.spawn(id, at)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.atk_i[i] = _attack_index(Registry.enemy(id), atk_name)
	em.atk_t[i] = 0.0
	em._update_attacks(i, DT, em.player.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)
	return i


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------- the pace knob

func test_red_canyon_runs_at_its_pace() -> void:
	# the one knob (Garry: "slow everyone's movement speed by like 20%, one place to tweak it"); 0.8 in pass 48, and Garry
	# set it to 0.6 by hand before pass 52 and to 0.9 before pass 53 (kept, as his hand edits are)
	assert_float(Registry.map("red_canyon").timeline.move_pace).is_equal_approx(0.9, 0.0001)


func test_creatures_walk_and_step_at_the_pace() -> void:
	var d := _test_def("w48_walker", "skeleton", "chase")
	var w := _world(Vector3(0, 0, 60))
	var em: EnemyManager = w["em"]
	_pace(1.0)
	var a := em.spawn(d.id, Vector3(-20, 0, 0))
	_pace(0.8)
	var b := em.spawn(d.id, Vector3(20, 0, 0))
	assert_float(em.speed[b] / em.speed[a]).is_equal_approx(0.8, 0.02)
	# the walk cycle plays at the pace too, so the feet keep to the ground
	em.state[b] = EnemyManager.STATE_MOVE
	em._physics_process(DT)
	em._physics_process(DT)
	var t0: float = em.anim_t[b]
	for k in range(60):
		em._physics_process(DT)
	var fps: float = em._t_run_fps[em.type_idx[b]]
	if fps <= 0.0:
		fps = 10.0
	assert_float(em.anim_t[b] - t0).is_equal_approx(fps * 0.8, fps * 0.05)


func test_a_charge_covers_its_line_at_any_pace() -> void:
	var d := _test_def("w48_charger", "bull_beetle", "charge", {"charge": {"windup": 0.8, "duration": 0.7, "speed": 9.0, "trigger_range": 6.0, "cooldown": 4.0}})
	for p: float in [1.0, 0.8]:
		_pace(p)
		# inside the arena's wall (66 m): a creature outside it is put back on the wall's edge
		var w := _world(Vector3(0, 0, 40))
		var em: EnemyManager = w["em"]
		var g: Node = w["g"]
		var i := em.spawn(d.id, Vector3(0, 0, 36))
		em.state[i] = EnemyManager.STATE_MOVE
		em.cooldown[i] = 5.0
		em._physics_process(DT)
		em.cooldown[i] = 0.0
		em._steer(i, em.player.global_position, DT)
		assert_int(em.state[i]).is_equal(EnemyManager.STATE_WINDUP)
		# the wind-up and its red line last 1/pace
		assert_float(em.timer[i]).is_equal_approx(0.8 / p, 0.001)
		assert_float(float((g.lines.back() as Dictionary)["dur"])).is_equal_approx(0.8 / p, 0.001)
		# the charge: 1/pace as long at the pace's speed, the same ground (separation is off: it is alone)
		em.charge_dir[i] = Vector3(1, 0, 0)
		em.timer[i] = 0.0
		em._steer(i, em.player.global_position, DT)
		assert_int(em.state[i]).is_equal(EnemyManager.STATE_CHARGE)
		assert_float(em.timer[i]).is_equal_approx(0.7 / p, 0.001)
		var x0: float = em.pos[i].x
		var t := 0.0
		while em.state[i] == EnemyManager.STATE_CHARGE and t < 3.0:
			em._physics_process(DT)
			t += DT
		assert_float(t).is_equal_approx(0.7 / p, 0.06)
		assert_float(em.pos[i].x - x0).override_failure_message("pace %.1f: charged %.2f m" % [p, em.pos[i].x - x0]).is_equal_approx(9.0 * 0.7, 0.45)


func test_a_scripted_roll_covers_its_line_at_the_pace() -> void:
	_pace(0.8)
	var w := _world(Vector3(60, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var b := _start_attack(em, "tumbleweed_king", "roll", Vector3.ZERO)
	assert_float(em.timer[b]).is_equal_approx(1.0 / 0.8, 0.001)
	var line: Dictionary = g.lines.back()
	assert_float(float(line["dur"])).is_equal_approx(1.0 / 0.8, 0.001)
	var want: float = float(line["length"]) - em.radius[b]
	assert_float(want).is_equal_approx(12.0 * 1.2, 0.01)
	var t := 0.0
	while em.state[b] != EnemyManager.STATE_CHARGE and t < 3.0:
		em._physics_process(DT)
		t += DT
	var x0: float = em.pos[b].x
	t = 0.0
	while em.state[b] == EnemyManager.STATE_CHARGE and t < 4.0:
		em._physics_process(DT)
		t += DT
	assert_float(t).is_equal_approx(1.2 / 0.8, 0.06)
	assert_float(em.pos[b].x - x0).is_equal_approx(want, 1.2)


func test_shots_rumbles_stalactites_and_boulders_run_on_the_paced_clock() -> void:
	_pace(0.8)
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var g: Node = w["g"]
	em._physics_process(DT)
	assert_float(em.pace).is_equal_approx(0.8, 0.0001)
	assert_float(em.hostile_clock()).is_equal_approx(0.8, 0.0001)
	# a creature's shot covers 0.8 of its ground a tick: the same line, 1/0.8 as long in the air
	var kind := pm.register_kind(SphereMesh.new(), StandardMaterial3D.new(), 1.0)
	var s := pm.hostile_shot(kind, Vector3(30, 1, 30), Vector3(10, 0, 0), 5.0, 0.5, 4.0)
	var x0: float = pm.pos[s].x
	pm._physics_process(DT)
	assert_float(pm.pos[s].x - x0).is_equal_approx(10.0 * DT * 0.8, 0.0001)
	# the rumble (the Gila's until pass 72, when its red cactus rain took the slot; still a built-in any script may name): its
	# fan lasts 1/pace and the waves run at the pace to the end of the lines
	var rum := {"name": "rumble", "windup": 1.0, "count": 7, "spread_deg": 100, "speed": 13.0, "length": 14.0, "width": 1.2,
		"damage": 16, "knockback": 10, "lift": 3.0, "telegraph": "fan"}
	_test_def("w48_rumbler", "gila_grande", "boss", {"boss": {"attacks": [rum], "cooldown_between": 2.2}})
	var gila := _start_attack(em, "w48_rumbler", "rumble", Vector3(-30, 0, 0))
	assert_float(em.timer[gila]).is_equal_approx(float(rum["windup"]) / 0.8, 0.001)
	assert_float(float((g.lines.back() as Dictionary)["dur"])).is_equal_approx(float(rum["windup"]) / 0.8, 0.001)
	assert_float(float((g.lines.back() as Dictionary)["length"])).is_equal_approx(float(rum["length"]), 0.001)
	em.timer[gila] = 0.0
	em._update_attacks(gila, DT, em.player.global_position)
	assert_bool(em._rumbles.is_empty()).is_false()
	assert_float(float(em._rumbles[0]["speed"])).is_equal_approx(float(rum["speed"]) * 0.8, 0.001)
	# the golem's swoop: a wedge 1/pace long, stalactites falling 1/pace as long
	var golem := _start_attack(em, "stone_golem", "swoop", Vector3(0, 0, 4))
	var gdef: EnemyDef = Registry.enemy("stone_golem")
	var swoop: Dictionary = (gdef.boss["attacks"] as Array)[_attack_index(gdef, "swoop")]
	assert_float(float((g.sectors.back() as Dictionary)["dur"])).is_equal_approx(float(swoop["windup"]) / 0.8, 0.001)
	em.timer[golem] = 0.0
	em._update_attacks(golem, DT, em.player.global_position)
	assert_float(float(em._stalactites.back()["fall"])).is_equal_approx(float(swoop["fall"]) / 0.8, 0.001)
	# its boulder: the ring on the landing spot lasts the paced flight
	em.state[golem] = EnemyManager.STATE_MOVE
	em.atk_i[golem] = _attack_index(gdef, "boulder")
	em.atk_t[golem] = 0.0
	em.hold_t[golem] = 0.0
	em._update_attacks(golem, DT, em.player.global_position)
	var bould: Dictionary = (gdef.boss["attacks"] as Array)[_attack_index(gdef, "boulder")]
	assert_float(float((g.rings.back() as Dictionary)["dur"])).is_equal_approx(float(bould["windup"]) / 0.8, 0.001)
	em.timer[golem] = 0.0
	em._update_attacks(golem, DT, em.player.global_position)
	assert_int(g.boulders.size()).is_equal(1)
	assert_float(float((g.rings.back() as Dictionary)["dur"])).is_equal_approx(float(bould["flight"]) / 0.8, 0.001)
	# and the boulder itself lands when that ring runs out: it flies on the paced clock
	var bl = Game.BOULDER_SCRIPT.new()
	bl.setup(g, Vector3(0, 2, 30), Vector3(0, 0, 0), float(bould["flight"]), {"size": 1.0}, {}, -1)
	add_child(bl)
	var frames := 0
	while not bl._done and frames < 400:
		bl._process(DT)
		frames += 1
	assert_float(float(frames) * DT).is_equal_approx(float(bould["flight"]) / 0.8, 0.05)
	# the Sun Prophet's eruption: every ring warns 1/pace as long
	var prophet := _start_attack(em, "sun_prophet", "erupt", Vector3(0, 0, -10))
	em.timer[prophet] = 0.0
	em._update_attacks(prophet, DT, em.player.global_position)
	var pdef: EnemyDef = Registry.enemy("sun_prophet")
	var erupt: Dictionary = (pdef.boss["attacks"] as Array)[_attack_index(pdef, "erupt")]
	assert_float(float(em._rains.back()["warn"])).is_equal_approx(float(erupt["warn"]) / 0.8, 0.001)


func test_a_ranged_wind_up_lasts_one_over_the_pace() -> void:
	_pace(0.8)
	var d := _test_def("w48_kite", "skeleton", "kite", {"ranged": {"keep_distance": 5.0, "range": 9.0, "cooldown": 2.5, "telegraph": 0.6, "straight": true, "projectile_speed": 12.0}})
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var i := em.spawn(d.id, Vector3(6, 0, 0))
	em.state[i] = EnemyManager.STATE_MOVE
	em.cooldown[i] = 5.0
	em._physics_process(DT)
	em.cooldown[i] = 0.0
	em._steer(i, em.player.global_position, DT)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_WINDUP)
	assert_float(em.timer[i]).is_equal_approx(0.6 / 0.8, 0.001)
	assert_float(float((g.lines.back() as Dictionary)["dur"])).is_equal_approx(0.6 / 0.8, 0.001)


func test_the_hostile_rocket_pays_the_pace_once() -> void:
	# the rocket flies at 0.9 of the hero's top speed; his top speed already has the pace in it and the rocket flies on
	# the paced clock, so ProjectileManager takes the pace out once: 0.9 x 5 x 0.8 m/s, not x 0.64 and not x 1
	_pace(0.8)
	var w := _world(Vector3(0, 0, 80))
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	em._physics_process(DT)
	var kind := pm.register_kind(BoxMesh.new(), null, 1.0, true)
	var r := pm.launch_enemy_rocket(kind, 99, Vector3(0, 0.9, 0), Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6, 0.9)
	pm._physics_process(DT)
	var z0: float = pm.pos[r].z
	for k in range(60):
		pm._physics_process(DT)
	assert_float(pm.pos[r].z - z0).is_equal_approx(0.9 * 5.0 * 0.8, 0.12)


# ---------------------------------------------------------------- the portal

func _director(g: Node) -> WaveDirector:
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = g
	d.timeline = Run.map.timeline
	d.map = Run.map
	d.running = true
	g.add_child(d)
	return d


func test_the_portal_sends_one_wave_then_nothing() -> void:
	assert_int(int(Registry.map("red_canyon").timeline.portal_wave.get("count", 0))).is_equal(12)
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var pk: Node = Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var d := _director(g)
	Run.stage = 0
	Run.elapsed = Run.map.timeline.stage_length + 0.5
	d.phase = WaveDirector.Phase.BOSS
	var before := em.alive_count()
	d._on_boss_died(Registry.enemy("tumbleweed_king"), Vector3(5, 0, 5))
	# the portal's phase, the boss chest, and twelve creatures of the stage's roster from all round the hero
	assert_int(d.phase).is_equal(WaveDirector.Phase.PORTAL)
	assert_int((pk.get("chests") as Array).size()).is_equal(1)
	assert_int(em.alive_count() - before).is_equal(12)
	assert_int(d.portal_wave_spawned).is_equal(12)
	var north := 0
	var south := 0
	for i in range(EnemyManager.MAX):
		if em.alive[i] == 1:
			var dd := _flat(em.pos[i], Vector3.ZERO)
			assert_float(dd).is_between(8.0, 27.0)
			if em.pos[i].z < 0.0:
				north += 1
			else:
				south += 1
	assert_int(north + south).is_equal(12)
	# then nothing, however long the portal waits
	assert_int(d.current_cap()).is_equal(0)
	d._portal_t = 999.0
	assert_int(d.current_cap()).is_equal(0)
	var n := em.alive_count()
	for k in range(5):
		d._spawn_burst()
	assert_int(em.alive_count()).is_equal(n)
	# pass 87 (lane SGAME, re-pinned: no going on through the portal any more): when its countdown runs out, Endless keeps
	# a crowd up again
	d.start_endless()
	assert_int(d.current_cap()).is_greater(0)
	Run.endless = false
	Run.endless_time = 0.0


func test_a_timeline_without_a_wave_keeps_its_portal_cap() -> void:
	var tl: WaveTimeline = (Registry.map("red_canyon").timeline as WaveTimeline).duplicate() as WaveTimeline
	tl.portal_wave = {}
	tl.portal_cap = 10
	tl.portal_spawn_seconds = 30.0
	var w := _world()
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.timeline = tl
	d.running = true
	assert_bool(d.has_portal_wave()).is_false()
	assert_int(d.spawn_portal_wave()).is_equal(0)
	Run.elapsed = 430.0
	d.phase = WaveDirector.Phase.PORTAL
	d._portal_t = 0.0
	assert_int(d.current_cap()).is_equal(10)
	d._portal_t = 31.0
	assert_int(d.current_cap()).is_equal(0)


func test_a_held_director_sends_no_wave() -> void:
	# the arena holds its director: a boss killed there opens the portal and brings nobody
	var w := _world()
	var em: EnemyManager = w["em"]
	var d := _director(w["g"])
	d.running = false
	Run.elapsed = 430.5
	assert_int(d.spawn_portal_wave()).is_equal(0)
	assert_int(em.alive_count()).is_equal(0)


func test_the_portal_asks_again_once_the_hero_stepped_out() -> void:
	var portal: Portal = auto_free(Portal.new())
	add_child(portal)
	portal.global_position = Vector3(10, 0, 10)
	var hero: Node3D = auto_free(Node3D.new())
	add_child(hero)
	var asked := [0]
	portal.entered.connect(func(): asked[0] += 1)
	hero.global_position = Vector3(10.8, 0, 10)
	portal.check_player(hero)
	assert_int(asked[0]).is_equal(1)
	assert_bool(portal.armed).is_false()
	# "Not yet": standing in it, or a step out, asks nothing
	for k in range(30):
		portal.check_player(hero)
	hero.global_position = Vector3(12.2, 0, 10)
	portal.check_player(hero)
	assert_bool(portal.armed).is_false()
	assert_int(asked[0]).is_equal(1)
	# out past 2.5 m it waits again, and walking back in asks again
	hero.global_position = Vector3(12.7, 0, 10)
	portal.check_player(hero)
	assert_bool(portal.armed).is_true()
	hero.global_position = Vector3(10.5, 0, 10.5)
	portal.check_player(hero)
	assert_int(asked[0]).is_equal(2)


# ---------------------------------------------------------------- the arena's dummies

## A bare Game with the real crowd, a real hero and Fx (no scene: only what the dummies and the speed looks use).
func _bare_game() -> Dictionary:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var game: Game = auto_free(Game.new())
	game.enemies = em
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.setup(Run.character)
	add_child(p)
	p.global_position = Vector3(0, 0, 0)
	game.player = p
	em.player = p
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	game.fx = fx
	return {"game": game, "em": em, "hero": p, "fx": fx, "g": w["g"]}


## The field's dummies standing (pass 49: the Elite and the Boss dummy stand apart beside the field, dummies of their own).
func _dummies_alive(em: EnemyManager) -> Array:
	var out: Array = []
	for i in range(EnemyManager.MAX):
		if em.is_alive(i) and em.is_dummy(i) and (em.types[em.type_idx[i]]["def"] as EnemyDef).id == "training_dummy":
			out.append(i)
	return out


func test_the_dummies_stand_in_rows_of_five_north_of_the_hero() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	# never fewer than ten
	game.arena_dummies(4, 0)
	assert_int(_dummies_alive(em).size()).is_equal(10)
	game.arena_dummies(12, 0)
	var ids := _dummies_alive(em)
	assert_int(ids.size()).is_equal(12)
	assert_int(game.dummies_standing()).is_equal(12)
	# rows of five, 1.6 m apart, the nearest 7 m north (-Z); the short row centred
	var rows := {}
	for i: int in ids:
		var key := roundi(em.pos[i].z * 10.0)
		rows[key] = int(rows.get(key, 0)) + 1
	assert_int(rows.size()).is_equal(3)
	assert_int(int(rows.get(-70, 0))).is_equal(5)
	assert_int(int(rows.get(-86, 0))).is_equal(5)
	assert_int(int(rows.get(-102, 0))).is_equal(2)
	var xs: Array = []
	var short: Array = []
	for i: int in ids:
		if roundi(em.pos[i].z * 10.0) == -70:
			xs.append(roundi(em.pos[i].x * 10.0))
		elif roundi(em.pos[i].z * 10.0) == -102:
			short.append(roundi(em.pos[i].x * 10.0))
	xs.sort()
	short.sort()
	assert_array(xs).is_equal([-32, -16, 0, 16, 32])
	assert_array(short).is_equal([-8, 8])


func test_an_undying_dummy_takes_everything_and_stands() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	game.arena_dummies(10, 0)
	var i: int = _dummies_alive(em)[0]
	assert_int(em.undying[i]).is_equal(1)
	var mx: float = em.max_hp[i]
	assert_float(mx).is_equal_approx(Registry.enemy("training_dummy").hp, 0.01)
	# a killing hit, a shove, a burn, a freeze: it shows them all and stands
	assert_bool(em.damage(i, mx * 20.0, "w48_gun", Vector3(1, 0, 0), 8.0)).is_false()
	assert_bool(em.is_alive(i)).is_true()
	assert_float(em.hp[i]).is_equal(mx)
	assert_float(em.kb[i].length()).is_greater(0.5)
	em.ignite(i, "w48_gun", 1.0, 3.0, 0.0)
	assert_bool(em.is_burning(i)).is_true()
	em.freeze(i, 1.0)
	assert_float(em.freeze_t[i]).is_greater(0.0)
	# a kill-all leaves it standing; a clear takes the field away for good
	em.kill_all(true)
	assert_int(_dummies_alive(em).size()).is_equal(10)
	em.kill_all(false)
	assert_int(_dummies_alive(em).size()).is_equal(0)
	game._tick_dummies(6.0)
	assert_int(_dummies_alive(em).size()).is_equal(0)


func test_a_dummy_with_health_falls_and_stands_up_again_on_its_spot() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	game.arena_dummies(10, 100)
	var i: int = _dummies_alive(em)[3]
	assert_int(em.undying[i]).is_equal(0)
	assert_float(em.max_hp[i]).is_equal_approx(100.0, 0.001)
	var spot: Vector3 = em.pos[i]
	var kills0: int = int(Save.total("kills"))
	assert_bool(em.damage(i, 500.0, "w48_gun")).is_true()
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_DYING)
	# it counts for no quest
	assert_int(int(Save.total("kills"))).is_equal(kills0)
	assert_int(game.dummies_standing()).is_equal(9)
	game._tick_dummies(4.9)
	assert_int(game.dummies_standing()).is_equal(9)
	game._tick_dummies(0.2)
	assert_int(game.dummies_standing()).is_equal(10)
	var back := -1
	for j: int in _dummies_alive(em):
		if _flat(em.pos[j], spot) < 0.05:
			back = j
	assert_int(back).is_greater_equal(0)
	assert_float(em.hp[back]).is_equal_approx(100.0, 0.001)


func test_a_dummy_walks_home_and_never_bites() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	var hero: Player = b["hero"]
	# standing, not patrolling (pass 49: the arena's Patrol setting walks them)
	var patrol: bool = Settings.dummy_patrol
	Settings.dummy_patrol = false
	game.arena_dummies(10, 0)
	Settings.dummy_patrol = patrol
	var i: int = _dummies_alive(em)[0]
	var home: Vector3 = em.home[i]
	em.pos[i] = home + Vector3(2.0, 0, 0)
	for k in range(180):
		em._physics_process(DT)
	assert_float(_flat(em.pos[i], home)).is_less(0.5)
	# right on top of the hero, a second of ticks: not a scratch
	var hp0: float = hero.hp
	em.pos[i] = hero.global_position + Vector3(0.3, 0, 0)
	em.home[i] = em.pos[i]
	for k in range(60):
		em.contact_cd[i] = 0.0
		em._physics_process(DT)
	assert_float(hero.hp).is_equal(hp0)


# ---------------------------------------------------------------- the Vulture Raider

func test_the_vulture_raider_has_less_health_and_fires_from_his_launcher() -> void:
	var r: EnemyDef = Registry.enemy("rocketeer")
	assert_float(r.hp).is_equal_approx(35.0, 0.001)
	assert_str(r.display_name).is_equal("Vulture Raider")
	var mz: Dictionary = r.artillery.get("muzzle", {})
	assert_bool(mz.has("up") and mz.has("side") and mz.has("forward")).is_true()
	var w := _world(Vector3(0, 0, 30))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	em._physics_process(DT)
	var i := em.spawn("rocketeer", Vector3(0, 0, 0))
	em.size[i] = r.size
	em.state[i] = EnemyManager.STATE_MOVE
	em.flip[i] = 0
	em.away[i] = 0
	# the front painting: his right hand, screen-left (-X), up the painting (the camera's up: up and a little north)
	var aim := Vector3(0, 0, 1)
	var m := em.muzzle_point(i, aim)
	var cam_up := em._cam_up()
	var want := em.pos[i] + cam_up * float(mz["up"]) + Vector3(-float(mz["side"]), 0, 0) + aim * float(mz["forward"])
	assert_float(m.distance_to(want)).is_less(0.01)
	assert_float(m.y - em.pos[i].y).is_greater(1.2)
	# mirrored, it is on the other side
	em.flip[i] = 1
	assert_float(em.muzzle_point(i, aim).x).is_equal_approx(em.pos[i].x + float(mz["side"]), 0.01)
	# seen from behind (walking away, the back set), his right hand is screen-right
	em.flip[i] = 0
	em.away[i] = 1
	em.vel[i] = Vector3(0, 0, -1)
	# pass 60: a creature that fights at range walks by its brain's intent (a shove is no walk); here the test means the walk
	em.intent[i] = em.vel[i]
	assert_int(em._strip_of(i, em.type_idx[i])).is_equal(5)
	assert_float(em.muzzle_point(i, aim).x).is_equal_approx(em.pos[i].x + float(mz["side"]), 0.01)
	# the wind-up ends and the rocket leaves from there (the front attack painting, not mirrored)
	em.vel[i] = Vector3.ZERO
	em.away[i] = 0
	em.flip[i] = 0
	em.state[i] = EnemyManager.STATE_WINDUP
	em.timer[i] = 0.0
	em._steer(i, em.player.global_position, DT)
	assert_int(g.missiles.size()).is_equal(1)
	var from: Vector3 = g.missiles[0]["from"]
	assert_float(from.x).is_equal_approx(em.pos[i].x - float(mz["side"]), 0.05)
	assert_float(from.y - em.pos[i].y).is_greater(1.2)


func test_the_rocket_is_dark_with_a_hot_tail() -> void:
	var game: Game = auto_free(Game.new())
	var mesh: Mesh = game._rocket_mesh()
	assert_object(mesh).is_not_null()
	# nose down -Z: the hot exhaust is at the back (+Z), the paint near black elsewhere
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	assert_int(c.size()).is_equal(v.size())
	var hot_z := 0.0
	var hot_n := 0
	var dark := 0
	for k in range(v.size()):
		var by_paint: float = clampf((c[k].r - 0.6) * 4.0, 0.0, 1.0) * clampf((c[k].g - 0.25) * 6.0, 0.0, 1.0)
		if maxf(1.0 - c[k].a, by_paint) > 0.5:
			hot_z += v[k].z
			hot_n += 1
		elif c[k].r < 0.35 and c[k].g < 0.35:
			dark += 1
	assert_int(hot_n).is_greater(0)
	assert_float(hot_z / float(hot_n)).is_greater(0.2)
	assert_float(mesh.get_aabb().position.z).is_less(-0.4)
	assert_float(float(dark) / float(v.size())).is_greater(0.6)
	# the drawn stand-in is painted the same way
	var drawn: Mesh = game._rocket_mesh_drawn()
	assert_int((drawn.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).size()).is_greater(0)
	var code: String = (load("res://core/shaders/rocket.gdshader") as Shader).code
	assert_str(code).contains("COLOR.rgb")
	assert_str(code).contains("1.0 - COLOR.a")
	# the kind's MultiMesh carries instance colours as well as its custom data (the heat): one with custom data and no
	# colours hands a spatial shader COLOR = 0, and a capture showed the rocket bright yellow (Game.paint_white)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 4
	mm.visible_instance_count = 0
	Game.paint_white(mm)
	assert_bool(mm.use_colors).is_true()
	assert_bool(mm.use_custom_data).is_true()
	assert_int(mm.instance_count).is_equal(4)
	assert_int(mm.visible_instance_count).is_equal(0)


# ---------------------------------------------------------------- black

## a flat map for the barrels: no rocks, no water, no paintings
const FLAT_MAP := """extends MapBase
var flats_radius := 16.0
"""


func _material_of(bf: BarrelField, mm: MultiMesh) -> Material:
	for c in bf.get_children():
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh == mm:
			return (c as MultiMeshInstance3D).material_override
	return null


func test_the_rare_barrels_are_black_with_brass_hoops() -> void:
	assert_bool(BarrelField.LIGHT.is_equal_approx(Color(0.05, 0.05, 0.06))).is_true()
	var w := _world()
	var mnode := Node3D.new()
	mnode.set_script(_script(FLAT_MAP))
	var map: MapBase = auto_free(mnode)
	add_child(map)
	var bf: BarrelField = auto_free(BarrelField.new())
	add_child(bf)
	bf.setup(w["g"], map)
	assert_int(bf.pos.size()).is_equal(BarrelField.COUNT)
	var light_n := 0
	for k in range(bf.pos.size()):
		light_n += bf.light[k]
	# a hoop MultiMesh for each kind: the common ones' iron (the model's own), the rare ones' brass
	assert_int(bf._hoops.visible_instance_count).is_equal(bf.pos.size() - light_n)
	assert_int(bf._hoops_light.visible_instance_count).is_equal(light_n)
	assert_object(_material_of(bf, bf._hoops)).is_null()
	var brass: StandardMaterial3D = _material_of(bf, bf._hoops_light)
	assert_bool(brass.albedo_color.is_equal_approx(Color(0.85, 0.62, 0.22))).is_true()
	assert_float(brass.metallic).is_equal_approx(0.4, 0.001)
	# matte black bodies; the common wood unchanged
	var black: StandardMaterial3D = _material_of(bf, bf._body_light)
	assert_bool(black.albedo_color.is_equal_approx(Color(0.05, 0.05, 0.06))).is_true()
	assert_float(black.metallic).is_equal(0.0)
	assert_float(black.roughness).is_greater(0.9)
	var wood: StandardMaterial3D = _material_of(bf, bf._body_dark)
	assert_bool(wood.albedo_color.is_equal_approx(BarrelField.DARK)).is_true()
	# breaking one of each kind
	for k in range(bf.pos.size()):
		if bf.alive[k] == 1 and (bf.light[k] == 1 or k == 0):
			bf._break(k)
			assert_int(bf.alive[k]).is_equal(0)


func test_the_kings_tumbleweeds_are_jet_black() -> void:
	var game: Game = auto_free(Game.new())
	var m: StandardMaterial3D = game._tumble_material()
	assert_bool(m.albedo_color.is_equal_approx(Color(0.035, 0.03, 0.03))).is_true()
	assert_float(m.roughness).is_equal_approx(0.85, 0.001)


# ---------------------------------------------------------------- the speed looks

func test_barrel_rush_is_one_thin_gold_ribbon_and_nothing_else() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var fx: Fx = b["fx"]
	var hero: Player = b["hero"]
	Run.add_timed_effects(Run.BARREL_RUSH, "Barrel Rush", [Effect.make("move_speed", "mul", 0.3, "player")], 4.0, true)
	var n0: int = fx._n
	game.barrel_rush_fx(false)
	hero.velocity = Vector3(5, 0, 0)
	for k in range(20):
		hero.global_position += Vector3(5.0 * DT, 0, 0)
		game._tick_speed_fx(DT)
	assert_int(fx.speed_trail_points("gold")).is_greater(5)
	# no puffs, no streaks, no burst: not one particle more than the warm-up note Fx starts with
	assert_int(fx._n).is_less_equal(n0)
	assert_bool(fx.speed_trail_live("blue")).is_false()
	assert_int(fx.wind_count()).is_equal(0)
	assert_float(float(Fx.TRAILS["gold"]["width"])).is_less(0.5)
	assert_float(float(Fx.TRAILS["gold"]["alpha"])).is_less(0.5)


func test_a_sprint_blows_wind_and_a_blue_ribbon_and_all_three_run_together() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var fx: Fx = b["fx"]
	var hero: Player = b["hero"]
	var sprint: PickupDef = Registry.pickup("sprint")
	assert_bool(Game._speeds_up(sprint)).is_true()
	assert_bool(Game._speeds_up(Registry.pickup("rage"))).is_false()
	Run.add_timed_effects(sprint.id, sprint.display_name, sprint.effects, sprint.duration)
	game._speed_buffs.append(sprint.id)
	Run.add_timed_effects(Run.BARREL_RUSH, "Barrel Rush", [Effect.make("move_speed", "mul", 0.3, "player")], 4.0, true)
	game.barrel_rush_fx(false)
	hero.velocity = Vector3(0, 0, -6)
	for k in range(30):
		hero.global_position += Vector3(0, 0, -6.0 * DT)
		game._tick_speed_fx(DT)
		# Skedaddle's ribbon is Fx's own (lane L1 says when it runs)
		fx.speed_trail("red", hero.global_position, DT, true)
	assert_bool(fx.speed_trail_live("blue")).is_true()
	assert_bool(fx.speed_trail_live("gold")).is_true()
	assert_bool(fx.speed_trail_live("red")).is_true()
	assert_int(fx.wind_count()).is_greater(3)
	# each at its own height above his feet
	var ys: Array = []
	for src in ["red", "gold", "blue"]:
		var tr: Fx.SpeedTrail = fx._trails[src]
		ys.append(tr.pts[tr.pts.size() - 1].y - hero.global_position.y)
	assert_float(float(ys[0])).is_less(float(ys[1]) - 0.2)
	assert_float(float(ys[1])).is_less(float(ys[2]) - 0.2)
	# the wind streams back past him: every streak flies against his run
	for k in range(fx._wind_vel.size()):
		assert_float(fx._wind_vel[k].z).is_greater(0.0)
	# when the boosts end, the ribbons shrink away and the wind blows out
	Run.timed.clear()
	game._rush_running = false
	for k in range(60):
		game._tick_speed_fx(DT)
	assert_bool(fx.speed_trail_live("blue")).is_false()
	assert_bool(fx.speed_trail_live("gold")).is_false()
	assert_int(fx.wind_count()).is_equal(0)


func test_skedaddle_shows_red_while_it_lasts() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var fx: Fx = b["fx"]
	var hero: Player = b["hero"]
	# without the item a hit starts nothing
	var n0: int = fx._n
	game._skedaddle()
	assert_int(fx._n).is_equal(n0)
	assert_float(Run.skedaddle_left()).is_equal(0.0)
	# held: a hit (on his health or his shield, both call this) starts it with a small red burst, and the red ribbon
	# follows him while it lasts
	Run.player_sheet.add_effects([Effect.make("hurt_speed", "add", 0.3, "player"), Effect.make("hurt_speed_seconds", "add", 2.0, "player")], "w48")
	game._skedaddle()
	assert_float(Run.skedaddle_left()).is_greater(1.5)
	assert_int(fx._n).is_greater(n0)
	hero.velocity = Vector3(5, 0, 0)
	for k in range(20):
		hero.global_position += Vector3(5.0 * DT, 0, 0)
		game._tick_speed_fx(DT)
	assert_bool(fx.speed_trail_live("red")).is_true()
	assert_bool(fx.speed_trail_live("gold")).is_false()
	Run.player_sheet.remove_source("w48")
