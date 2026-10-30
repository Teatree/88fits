extends GdUnitTestSuite

## Pass 73, lane GROUND (Garry: the Gila's cactus rain "each spot where the projectile will fall is highlighted. At once
## they wait for a little bit and then the boss does his animation of all those projectiles flying out of his mouth but
## they all land around the same time"; "It would be nice if I can actually see him burrowing into the ground ... This is
## also true for the Scorpion Elite"; the Gila waits 3 s unseen and "tries to guess where the player is going to be";
## "throw other enemies out of the way and the Player too"; "Spawning enemies with a skill should never allow for any
## special enemies. Also spawn 4 more"; "Enemies Spawning ... grow out of the ground"). The ground-clip (EnemyManager.
## ground_clip, the billboard shader's cut), rise_v and _tick_rise (sinking hides, rising comes up at its own rate), the
## spawn rise (WaveTimeline.spawn_rise -> set_spawn_rise: out of the grid below `targetable`, harmless until up), the
## burrows (the visible sink, the Gila's three hidden seconds and predicted spot, the throws of the hero and the crowd),
## the summons (force_plain, the bosses' counts), the volley rain (BossAttackDef.volley_times, every circle lit at the
## wind-up's start, the crouch and the spew from the mouth, the spikes landing together, the held marks released).

const DT := 1.0 / 60.0

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
var lines: Array = []
var rings: Array = []
var bursts: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(a, _b, c) -> void:
	bursts.append({"at": a, "size": float(c)})
func fx_hit(_a, _b) -> void:
	pass
func fx_sand(_a, _b = 1.0) -> void:
	pass
func hint_once(_a, _b) -> void:
	pass
func telegraph_line(a, b, c, d, _e) -> void:
	lines.append({"from": a, "dir": b, "length": float(c), "dur": float(d)})
func telegraph_ring(a, b, c, _d, e = true) -> void:
	rings.append({"at": a, "r": float(b), "dur": float(c), "filled": bool(e)})
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "none"
var outcome := "hit"
var max_hp := 100.0
var hits := 0
var throws: Array = []
var shoves := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
	last_outcome = outcome
func shove(_v: Vector3, _c := true) -> bool:
	shoves += 1
	return true
func apply_knockback(_v: Vector3, _h := true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h := true) -> void:
	pass
func knock_immune() -> bool:
	return false
func trampoline_launch(dir: Vector3, height: float, distance: float, air_time: float, control: float) -> bool:
	throws.append({"dir": dir, "height": height, "distance": distance, "air": air_time, "control": control})
	return true
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_FX := """extends Node
var calls: Dictionary = {}
func _note(n: String, a) -> void:
	if not calls.has(n):
		calls[n] = []
	(calls[n] as Array).append(a)
func pop_dust(at, size) -> void:
	_note("pop_dust", {"at": at, "size": float(size)})
func dig_ring(at, size) -> void:
	_note("dig_ring", {"at": at, "size": float(size)})
func dig_spray(at, size, k = 0.0) -> void:
	_note("dig_spray", {"at": at, "size": float(size), "k": float(k)})
func emerge_dust(at, size, big = false) -> void:
	_note("emerge_dust", {"at": at, "size": float(size), "big": bool(big)})
func sand(_a, _b = 1.0) -> void:
	pass
func burst(_a, _b, _c = 1.0, _d = 1.0) -> void:
	pass
func hit(_a, _b) -> void:
	pass
func n(name: String) -> int:
	return (calls.get(name, []) as Array).size()
"""

const FAKE_TG := """extends Node
var held: Dictionary = {}
var released: Array = []
var next := 1
var flashes := 0
func hold_disc(at, r, c) -> int:
	next += 1
	held[next] = {"at": at, "r": float(r), "kind": "disc", "a": float(c.a)}
	return next
func hold_ring(at, r, c) -> int:
	next += 1
	held[next] = {"at": at, "r": float(r), "kind": "ring", "a": float(c.a)}
	return next
func set_alpha(id, a) -> void:
	if held.has(id):
		held[id]["a"] = float(a)
func release(id) -> void:
	if held.has(id):
		held.erase(id)
		released.append(id)
func flash_ring(_a, _b, _c, _d = 0.35, _e = 0.0) -> void:
	flashes += 1
"""

const FAKE_CAMERA := """extends Node
func shake(_a: float) -> void:
	pass
func current_yaw() -> float:
	return 0.0
func zoom() -> float:
	return 1.0
"""

var _added: Array = []


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	for id: String in _added:
		Registry.enemies.erase(id)
	_added.clear()
	Run.arena = false
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at` with the real crowd, a recording fx, a camera; `tg` adds a recording
## Telegraphs (held marks).
func _world(hero_at := Vector3.ZERO, tg := false) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	var f := Node.new()
	f.set_script(_script(FAKE_FX))
	g.add_child(f)
	g.fx = f
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	if tg:
		var t := Node.new()
		t.set_script(_script(FAKE_TG))
		g.add_child(t)
		g.telegraphs = t
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": f, "tg": g.telegraphs}


func _attack_index(id: String, atk_name: String) -> int:
	var attacks: Array = Registry.enemy(id).boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


func _attack(id: String, atk_name: String) -> Dictionary:
	var k := _attack_index(id, atk_name)
	return (Registry.enemy(id).boss["attacks"] as Array)[k] if k >= 0 else {}


## Creature `i` put straight into attack `k` of its list through the runner.
func _force_attack(em: EnemyManager, i: int, k: int) -> void:
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	em.hold_t[i] = 0.0
	em.atk_i[i] = k
	em.atk_t[i] = 0.0
	em._update_attacks(i, DT, em.player.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)


func _step(em: EnemyManager, seconds: float) -> float:
	var t := 0.0
	while t < seconds - 0.0001:
		em._physics_process(DT)
		t += DT
	return t


## A test creature copied from `from` (gone after the test).
func _def(id: String, from: String) -> EnemyDef:
	var d: EnemyDef = Registry.enemy(from).duplicate()
	d.id = id
	Registry.enemies[id] = d
	_added.append(id)
	return d


## A plain creature standing still at `at`, up and on its feet.
func _standing(em: EnemyManager, id: String, at: Vector3) -> int:
	var j := em.spawn(id, at)
	em.state[j] = EnemyManager.STATE_MOVE
	em.rise_t[j] = 1.0
	em.rise_v[j] = 0.0
	em.speed[j] = 0.0
	em.cooldown[j] = 99.0
	return j


# ---------------------------------------------------------------- the ground-clip

func test_the_ground_clip_cuts_what_is_under_the_sand() -> void:
	var w := _world(Vector3(0, 0, 20))
	var em: EnemyManager = w["em"]
	var i := em.spawn("skeleton", Vector3.ZERO)
	# no director: it appears at once, nothing cut
	assert_float(em.rise_t[i]).is_equal(1.0)
	assert_float(em.ground_clip(i)).is_equal(0.0)
	var t := em.type_idx[i]
	var head: float = float(em.types[t]["head"])
	var drop: float = em._t_sh[t * 4 + 3]
	em.rise_t[i] = 0.0
	assert_float(em.ground_clip(i)).is_equal_approx(clampf(drop + head, 0.0, 1.0), 0.0001)
	# half way up in time: three quarters of the figure out (the ease), a quarter cut
	em.rise_t[i] = 0.5
	assert_float(em.ground_clip(i)).is_equal_approx(drop + 0.25 * head, 0.0001)
	# the cut follows the slide: the share of the quad under the sand line is the painting's drop plus the part of the
	# figure rise_sink pushes down, over the quad's height (size x squash)
	var cam_up := Vector3(0, 0.695, -0.719)
	var slid := em.rise_sink(i, 1.0, cam_up).length() + em.sprite_sink(i, 1.0, cam_up).length()
	assert_float(slid / em.size[i]).is_equal_approx(em.ground_clip(i), 0.001)
	# the render takes a rising creature (the clip rides in the basis' z column)
	em.state[i] = EnemyManager.STATE_MOVE
	em._cf_tick = Vector3(0, 0, -1)
	em._render()
	assert_int((em.types[t]["mm"] as MultiMesh).visible_instance_count).is_equal(1)
	# the shader reads it from there and cuts under it, its silhouette pass drawing nothing while it rises
	var src: String = (load("res://core/shaders/enemy_billboard.gdshader") as Shader).code
	assert_bool(src.contains("v_clip = MODEL_MATRIX[2].y;")).is_true()
	assert_bool(src.contains("if (v_qh < cut) {")).is_true()
	assert_float(EnemyManager.frame_code(4, 0.5)).is_equal(4.5)


func test_a_sink_goes_under_and_hides_and_a_rise_comes_up_at_its_own_rate() -> void:
	var w := _world(Vector3(0, 0, 20))
	var em: EnemyManager = w["em"]
	var i := _standing(em, "skeleton", Vector3.ZERO)
	em.rise_v[i] = -1.0 / 0.6
	var t := 0.0
	while em.hidden[i] == 0 and t < 3.0:
		em._tick_rise(i, DT)
		t += DT
	assert_int(em.hidden[i]).is_equal(1)
	assert_float(em.rise_t[i]).is_equal(0.0)
	assert_float(em.rise_v[i]).is_equal(0.0)
	assert_float(t).is_between(0.6 / em.pace - DT, 0.6 / em.pace + 2.0 * DT)
	# hidden, nothing moves
	em._tick_rise(i, 0.5)
	assert_float(em.rise_t[i]).is_equal(0.0)
	# up again at its own rate
	em.hidden[i] = 0
	em.rise_v[i] = 1.0 / 0.6
	em._tick_rise(i, 0.3 / em.pace)
	assert_float(em.rise_t[i]).is_equal_approx(0.5, 0.01)
	em._tick_rise(i, 0.31 / em.pace)
	assert_float(em.rise_t[i]).is_equal(1.0)
	assert_float(em.rise_v[i]).is_equal(0.0)
	# with no rate of its own it comes up at RISE_TIME's (pass 60)
	em.rise_t[i] = 0.0
	em._tick_rise(i, EnemyManager.RISE_TIME / em.pace * 0.5)
	assert_float(em.rise_t[i]).is_equal_approx(0.5, 0.01)


# ---------------------------------------------------------------- growing out of the ground

func test_the_map_names_the_spawn_rise_and_the_defaults_fill_it() -> void:
	var dflt: Dictionary = WaveTimeline.SPAWN_RISE_DEFAULTS
	assert_float(float(dflt["seconds"])).is_between(0.3, 0.7)
	assert_float(float(dflt["targetable"])).is_between(0.5, 0.9)
	var tl := JsonContent.timeline_from_dict({"spawn_rise": {"seconds": 0.6, "dust": 0.0}})
	assert_float(tl.spawn_rise_value("seconds")).is_equal(0.6)
	assert_float(tl.spawn_rise_value("dust")).is_equal(0.0)
	assert_float(tl.spawn_rise_value("big_seconds")).is_equal(float(dflt["big_seconds"]))
	assert_float(JsonContent.timeline_from_dict({}).spawn_rise_value("seconds")).is_equal(float(dflt["seconds"]))
	assert_bool(JsonContent.timeline_from_dict({"spawn_rise": 3}).spawn_rise.is_empty()).is_true()
	# Red Canyon's (read from the file: Garry tunes it in the Level Editor; a key it leaves out plays the default) grows
	# every spawn out of the ground
	var f := FileAccess.open("res://content/maps/red_canyon/red_canyon.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var rc := JsonContent.timeline_from_dict(d["timeline_data"])
	assert_float(rc.spawn_rise_value("seconds")).is_greater(0.0)
	assert_float(Registry.map("red_canyon").timeline.spawn_rise_value("seconds")).is_equal(rc.spawn_rise_value("seconds"))


func test_the_director_hands_the_spawn_rise_over() -> void:
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	# a manager without a director (tests, tools) leaves every spawn up at once
	assert_float(em.spawn_rise_s).is_equal(0.0)
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = Registry.map("red_canyon").timeline
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	d._apply_mults()
	assert_float(em.spawn_rise_s).is_equal(d.timeline.spawn_rise_value("seconds"))
	assert_float(em.spawn_rise_big_s).is_equal(d.timeline.spawn_rise_value("big_seconds"))
	assert_float(em.rise_targetable).is_equal(d.timeline.spawn_rise_value("targetable"))


func test_a_spawn_grows_out_of_the_ground_never_chosen_and_harmless_until_up() -> void:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var fx: Node = w["fx"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	# right on top of the hero, the bite well within reach
	var i := em.spawn("skeleton", Vector3(0.3, 0, 0))
	em.vspecial[i] = 0
	assert_float(em.rise_t[i]).is_equal(0.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_SPAWN)
	assert_int(em.emerged).is_equal(1)
	assert_int(fx.n("emerge_dust")).is_equal(1)
	assert_float(em.squash[i]).is_greater(1.0)
	var t := 0.0
	var seen_at := -1.0
	var hp0: float = em.hp[i]
	while em.state[i] == EnemyManager.STATE_SPAWN and t < 3.0:
		em._physics_process(DT)
		t += DT
		# in the crowd's grid all along: area damage finds it (the lead's rule: blasts, the revive, patches, rings...)
		assert_bool(em.indices_in_radius(Vector3.ZERO, 3.0).has(i)).is_true()
		# but no weapon chooses it until it is `targetable` of the way up
		var r: float = em.rise_t[i]
		assert_bool(em.targetable(i)).override_failure_message("targetable at rise %.2f" % r).is_equal(r >= 0.7)
		var chosen: bool = em.nearest_index(Vector3.ZERO, 3.0, "", true) == i
		assert_bool(chosen).override_failure_message("chosen at rise %.2f" % r).is_equal(r >= 0.7)
		assert_bool(em.priority_index(Vector3.ZERO, 3.0, "", true) == i).is_equal(r >= 0.7)
		assert_bool(em.random_in_range(Vector3.ZERO, 3.0, [], "", true) == i).is_equal(r >= 0.7)
		assert_bool(em.screen_ok(i, true)).is_equal(r >= 0.7)
		if chosen and seen_at < 0.0:
			seen_at = t
		if t < 2.5 * DT:
			# a blast while it is still mostly under the sand hits it
			em.damage_radius(Vector3.ZERO, 3.0, 0.5, "", 0.0)
			assert_float(em.hp[i]).is_less(hp0)
		# harmless all the way up
		assert_int(hero.hits).is_equal(0)
	assert_float(em.rise_t[i]).is_equal(1.0)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(t).is_between(0.45 / em.pace - DT, 0.45 / em.pace + 3.0 * DT)
	assert_float(seen_at).is_between(0.0, t)
	assert_int(em.nearest_index(Vector3.ZERO, 3.0, "", true)).is_equal(i)
	# up: the bite lands
	_step(em, 0.7)
	assert_int(hero.hits).is_greater_equal(1)
	# an Elite (or a boss) by its kind takes the longer rise, and its dust says it is big
	var e := em.spawn("dune_scorpion", Vector3(10, 0, 0))
	assert_float(em.rise_v[e]).is_equal_approx(1.0 / 0.9, 0.0001)
	assert_bool(bool((fx.calls["emerge_dust"] as Array)[1]["big"])).is_true()


func test_without_the_rise_a_spawn_stands_at_once_and_an_ambusher_stays_buried() -> void:
	var w := _world(Vector3(0, 0, 20))
	var em: EnemyManager = w["em"]
	var i := em.spawn("skeleton", Vector3.ZERO)
	assert_float(em.rise_t[i]).is_equal(1.0)
	assert_int(em.emerged).is_equal(0)
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	var d := _def("t73_ambusher", "skeleton")
	d.brain = "ambush"
	var a := em.spawn(d.id, Vector3(5, 0, 0))
	assert_int(em.hidden[a]).is_equal(1)
	assert_float(em.rise_t[a]).is_equal(1.0)
	# seconds 0 = off
	em.set_spawn_rise(0.0, 0.0, 0.7, 1.0)
	var k := em.spawn("skeleton", Vector3(-5, 0, 0))
	assert_float(em.rise_t[k]).is_equal(1.0)


# ---------------------------------------------------------------- summons

func test_a_summon_is_never_a_special() -> void:
	var w := _world(Vector3(0, 0, 30))
	var em: EnemyManager = w["em"]
	em.colour_after_kills = 0
	var s := _def("t73_always_special", "skeleton")
	s.variance = {"tints": ["#ffffff"], "special_chance": 1.0, "special": {"tint": "#aa2222"}}
	# on its own it comes as its special
	var plain := em.spawn(s.id, Vector3(8, 0, 0))
	assert_int(em.vspecial[plain]).is_equal(1)
	em.kill_all(false)
	# a boss's ring of it never does
	var b := _def("t73_summoner", "gila_grande")
	b.boss = {"attacks": [{"name": "spawn_ring", "enemy": s.id, "count": 5, "windup": 0.5, "telegraph": "none"}], "cooldown_between": 2.0}
	var i := em.spawn(b.id, Vector3.ZERO)
	_force_attack(em, i, 0)
	em.timer[i] = 0.0
	em._update_attacks(i, DT, em.player.global_position)
	var n := 0
	for j in range(EnemyManager.MAX):
		if em.alive[j] == 1 and j != i:
			n += 1
			assert_int(em.vspecial[j]).override_failure_message("a summoned special").is_equal(0)
	assert_int(n).is_equal(5)
	assert_bool(em.force_plain).is_false()


func test_the_three_bosses_summon_four_more_than_before() -> void:
	# pass 72's counts were the King 12 minions, the Gila 8 lizards, the Brander 10 imps (read from the files)
	var want := {"tumbleweed_king": 16, "gila_grande": 12, "brander": 14}
	for id: String in want.keys():
		var f := FileAccess.open("res://content/bosses/%s/%s.json" % [id, id], FileAccess.READ)
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		var got := -1
		for a in d["boss"]["attacks"]:
			if str(a.get("name", "")) == "spawn_ring":
				got = int(a.get("count", 0))
		assert_int(got).override_failure_message(id).is_equal(int(want[id]))
		assert_int(int(_attack(id, "spawn_ring").get("count", 0))).override_failure_message(id + " (.tres)").is_equal(int(want[id]))


# ---------------------------------------------------------------- the burrows

func test_the_scorpion_sinks_in_sight_and_its_eruption_throws_the_hero_and_the_crowd() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var g: Node = w["g"]
	var fx: Node = w["fx"]
	var atk := _attack("dune_scorpion", "burrow")
	assert_float(float(atk.get("sink", 0.0))).is_greater(0.0)
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	em.cooldown[i] = 99.0
	_force_attack(em, i, _attack_index("dune_scorpion", "burrow"))
	# it sinks where it stands, in sight: not hidden yet, going down, a ring of dust; the ring on the hero and the mound
	assert_int(em.hidden[i]).is_equal(0)
	assert_float(em.rise_v[i]).is_less(0.0)
	assert_int(fx.n("dig_ring")).is_equal(1)
	assert_int(g.rings.size()).is_equal(1)
	assert_bool(em._mounds.has(i)).is_true()
	var sink := float(atk["sink"]) / em.pace
	var s1 := _step(em, sink * 0.5)
	assert_int(em.hidden[i]).is_equal(0)
	assert_float(em.rise_t[i]).is_between(0.35, 0.65)
	assert_int(fx.n("dig_spray")).is_greater(2)
	assert_bool(em._mounds.has(i)).is_true()
	var s2 := _step(em, sink * 0.5 + 2.0 * DT)
	assert_int(em.hidden[i]).is_equal(1)
	# the sand closes over it in a small poof; the mound still swells at the ring
	assert_int(fx.n("pop_dust")).is_equal(1)
	assert_bool(em._mounds.has(i)).is_true()
	# a crowd round the hero's spot, out of the eruption's middle
	var c1 := _standing(em, "skeleton_knight", hero.global_position + Vector3(3.0, 0, 0))
	var c2 := _standing(em, "skeleton_knight", hero.global_position + Vector3(-2.0, 0, 1.5))
	var far := _standing(em, "skeleton_knight", hero.global_position + Vector3(12.0, 0, 0))
	var hp1: float = em.hp[c1]
	var t := 0.0
	while em.state[i] == EnemyManager.STATE_ATTACK and t < 5.0:
		em._physics_process(DT)
		t += DT
	assert_float(s1 + s2 + t).is_between(2.3 / em.pace - 0.1, 2.3 / em.pace + 0.1)
	# up at the ring's spot, the hit, the hero thrown on a real arc away from where it went under
	assert_float(Vector2(em.pos[i].x - 0.0, em.pos[i].z - 6.0).length()).is_less(0.01)
	assert_int(hero.hits).is_equal(1)
	assert_int(hero.throws.size()).is_equal(1)
	var th: Dictionary = hero.throws[0]
	assert_float(float(th["height"])).is_equal_approx(float(atk["throw_up"]), 0.0001)
	assert_float(float(th["distance"])).is_equal_approx(float(atk["throw_out"]), 0.0001)
	assert_float(float(th["air"])).is_equal_approx(sqrt(8.0 * float(atk["throw_up"]) / EnemyManager.THROW_G), 0.0001)
	assert_float((th["dir"] as Vector3).dot(Vector3(0, 0, 1))).is_greater(0.99)
	assert_int(hero.shoves).is_equal(0)
	assert_int(em.erupt_hero_throws).is_equal(1)
	# the crowd inside goes up and away; the one outside stays
	assert_bool(em.is_launched(c1)).is_true()
	assert_bool(em.is_launched(c2)).is_true()
	assert_bool(em.is_launched(far)).is_false()
	var drift: Vector3 = em._launched[c1]["drift"]
	assert_float(drift.normalized().dot(Vector3(1, 0, 0))).is_greater(0.99)
	var air: float = em.lift_d[c1]
	assert_float(drift.length() * air).is_equal_approx(float(atk["creature_out"]) * em._t_kbt[em.type_idx[c1]], 0.01)
	assert_float(em.lift_peak[c1]).is_equal_approx(float(atk["creature_up"]), 0.0001)
	# it rises over its own `rise`
	assert_float(em.rise_v[i]).is_equal_approx(1.0 / float(atk["rise"]), 0.0001)
	# the crowd lands a little hurt: `creature_damage` of its max HP
	_step(em, air + 0.1)
	assert_bool(em.is_launched(c1)).is_false()
	assert_float(hp1 - em.hp[c1]).is_equal_approx(em.max_hp[c1] * float(atk["creature_damage"]) * (1.0 - em.dr[c1]), 0.01)
	assert_float(em.rise_t[i]).is_equal(1.0)


func test_the_gila_hides_three_seconds_then_erupts_where_the_hero_is_heading() -> void:
	var w := _world(Vector3(0, 0, 8))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var g: Node = w["g"]
	var atk := _attack("gila_grande", "burrow")
	assert_float(float(atk.get("predict", 0.0))).is_greater(0.0)
	assert_str(str(atk.get("telegraph", "none"))).is_equal("none")
	var i := em.spawn("gila_grande", Vector3.ZERO)
	_force_attack(em, i, _attack_index("gila_grande", "burrow"))
	# nothing shown: no ring, no mound
	assert_int(g.rings.size()).is_equal(0)
	assert_bool(em._mounds.has(i)).is_false()
	var sink := float(atk["sink"]) / em.pace
	var warn := float(atk["warn"]) / em.pace
	var wind := float(atk["windup"]) / em.pace
	var t := _step(em, sink + 2.0 * DT)
	assert_int(em.hidden[i]).is_equal(1)
	# under for the wait with nothing shown (the hero walking east)
	hero.velocity = Vector3(5.0, 0, 0)
	var hidden_t := 0.0
	while em.state[i] == EnemyManager.STATE_ATTACK and g.rings.is_empty() and t < 8.0:
		hero.global_position += hero.velocity * DT
		em._physics_process(DT)
		t += DT
		hidden_t += DT
	assert_int(g.rings.size()).is_equal(1)
	assert_float(t).is_between(wind - warn - 0.05, wind - warn + 0.05)
	# (pass 115, lane BOSS: the wait under the sand is the file's wind-up less the sink and the warning: 3.0 s, x1.25 since
	# pass 115 = 3.75 s, Garry's "increase the time it takes for the Gila to pop out of the ground by 25%")
	assert_float(hidden_t + 2.0 * DT).is_between(wind - sink - warn - 0.1, wind - sink - warn + 0.1)
	assert_float(float(atk["windup"]) - float(atk["sink"]) - float(atk["warn"])).is_equal_approx(3.75, 0.0001)
	# the warning: where he will be `predict` seconds on, for what is left of the wind-up
	var ring: Dictionary = g.rings[0]
	var want: Vector3 = hero.global_position + hero.velocity * float(atk["predict"])
	assert_float(Vector2((ring["at"] as Vector3).x - want.x, (ring["at"] as Vector3).z - want.z).length()).is_less(0.15)
	assert_float(float(ring["r"])).is_equal(float(atk["radius"]))
	assert_float(float(ring["dur"])).is_between(warn - 0.05, warn + 0.02)
	# a crowd round that spot; he keeps going
	var spot: Vector3 = ring["at"]
	var c1 := _standing(em, "skeleton_knight", spot + Vector3(0, 0, 3.5))
	while em.state[i] == EnemyManager.STATE_ATTACK and t < 9.0:
		hero.global_position += hero.velocity * DT
		em._physics_process(DT)
		t += DT
	assert_float(t).is_between(wind - 0.05, wind + 0.05)
	# up at the predicted spot; the hero (inside the radius) hit and thrown 2.5 m up and 4 m out, the crowd thrown
	assert_float(Vector2(em.pos[i].x - spot.x, em.pos[i].z - spot.z).length()).is_less(0.01)
	assert_int(hero.hits).is_equal(1)
	assert_int(hero.throws.size()).is_equal(1)
	assert_float(float(hero.throws[0]["height"])).is_equal(float(atk["throw_up"]))
	assert_float(float(hero.throws[0]["distance"])).is_equal(float(atk["throw_out"]))
	assert_bool(em.is_launched(c1)).is_true()
	assert_float(em.lift_peak[c1]).is_equal(float(atk["creature_up"]))
	assert_int(int(em.last_erupt["crowd"])).is_equal(1)


func test_the_predicted_spot_keeps_to_the_walkable_map() -> void:
	var w := _world(Vector3(60, 0, 0))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	hero.velocity = Vector3(50, 0, 0)
	var p := em.predict_spot(hero.global_position, 0.6)
	assert_float(Vector2(p.x, p.z).length()).is_less_equal(em.arena_radius - 2.0 + 0.001)
	hero.velocity = Vector3.ZERO
	assert_float(em.predict_spot(Vector3(3, 0, 4), 0.6).distance_to(Vector3(3, 0, 4))).is_less(0.01)


func test_a_throw_needs_a_hit_that_landed() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	hero.outcome = "evaded"
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	_force_attack(em, i, _attack_index("dune_scorpion", "burrow"))
	_step(em, 2.3 / em.pace + 0.1)
	assert_int(hero.hits).is_equal(1)
	assert_int(hero.throws.size()).is_equal(0)


func test_a_burrow_dropped_while_it_sinks_comes_back_up() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	_force_attack(em, i, _attack_index("dune_scorpion", "burrow"))
	_step(em, 0.2)
	assert_float(em.rise_v[i]).is_less(0.0)
	# something ends its attack before it is under
	em.state[i] = EnemyManager.STATE_MOVE
	em.atk_t[i] = 99.0
	em._update_boss(DT, em.player.global_position)
	assert_float(em.rise_v[i]).is_greater(0.0)
	assert_int(em.hidden[i]).is_equal(0)
	_step(em, EnemyManager.RISE_TIME / em.pace + 0.1)
	assert_float(em.rise_t[i]).is_equal(1.0)
	assert_bool(em._burrows.has(i)).is_false()


func test_a_burrow_without_a_sink_is_gone_at_once_as_before() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var fx: Node = w["fx"]
	var d := _def("t73_old_burrow", "dune_scorpion")
	d.boss = {"attacks": [{"name": "burrow", "windup": 1.0, "radius": 4.0, "damage": 10, "knockback": 6, "telegraph": "ring_at_hero"}], "cooldown_between": 4.0}
	var i := em.spawn(d.id, Vector3.ZERO)
	_force_attack(em, i, 0)
	assert_int(em.hidden[i]).is_equal(1)
	assert_int(fx.n("pop_dust")).is_equal(1)
	assert_int(fx.n("dig_ring")).is_equal(0)
	_step(em, 1.0 / em.pace + 0.1)
	# the old shove, no throw
	var hero: Node3D = w["hero"]
	assert_int(hero.hits).is_equal(1)
	assert_int(hero.shoves).is_equal(1)
	assert_int(hero.throws.size()).is_equal(0)
	assert_float(em.rise_v[i]).is_equal(0.0)


# ---------------------------------------------------------------- the volley rain

func test_volley_times_land_together_nearest_first() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts := PackedVector2Array([Vector2(4, 0), Vector2(0, 8), Vector2(-12, 0), Vector2(0, -16), Vector2(6, 6)])
	var vt: Array = BossAttackDef.volley_times(pts, 1.1, 0.25, 0.12, rng)
	var dep: PackedFloat32Array = vt[0]
	var land: PackedFloat32Array = vt[1]
	var lo := INF
	var hi := -INF
	for k in range(pts.size()):
		assert_float(dep[k]).is_between(0.0, 0.12)
		assert_float(land[k] - dep[k]).is_between(1.1, 1.1 + 0.25 - 0.12 + 0.0001)
		lo = minf(lo, land[k])
		hi = maxf(hi, land[k])
	assert_float(hi - lo).is_less_equal(0.25 + 0.0001)
	# the farthest spot's spike flies the longest; the nearest's the shortest
	assert_float(land[3] - dep[3]).is_equal_approx(1.1 + 0.13, 0.0001)
	assert_float(land[0] - dep[0]).is_equal_approx(1.1, 0.0001)
	# one spot, no spread: it flies the flight
	var one: Array = BossAttackDef.volley_times(PackedVector2Array([Vector2(3, 3)]), 0.8, 0.25, 0.0, rng)
	assert_float((one[1] as PackedFloat32Array)[0]).is_equal_approx(0.8, 0.0001)


func test_the_cactus_rain_lights_every_circle_and_spews_bigger_spikes_onto_wider_circles() -> void:
	var rain: BossAttackDef = Registry.boss_attack("cactus_rain")
	assert_bool(rain.is_volley()).is_true()
	assert_bool(rain.lit_at_once()).is_true()
	assert_float(rain.windup_seconds()).is_greater_equal(rain.num("telegraph", "seconds"))
	assert_float(float(rain.runner_entry({"name": "cactus_rain"})["windup"])).is_equal(rain.windup_seconds())
	# the stagger is a moment: they land together
	assert_float(rain.num("timing", "stagger")).is_less_equal(0.4)
	# bigger spikes (x1.6 of pass 72's 1.7) and circles (pass 72's 0.9 m) with less room between them
	assert_float(rain.num("projectile", "size")).is_greater_equal(1.7 * 1.6 - 0.01)
	assert_float(rain.num("landing", "radius")).is_greater_equal(1.3)
	var rng := RandomNumberGenerator.new()
	var gaps: Array = []
	for seed_v in [1, 2, 3]:
		rng.seed = seed_v
		var pts := rain.rain_points(rng)
		var lr := rain.num("landing", "radius")
		assert_float(BossAttackDef.smallest_gap(pts, lr)).is_greater_equal(rain.num("pattern", "gap") - 0.001)
		# every spot's nearest neighbour leaves a narrow gap: about a metre or a little more
		for a in range(pts.size()):
			var best := INF
			for b in range(pts.size()):
				if a != b:
					best = minf(best, pts[a].distance_to(pts[b]) - 2.0 * lr)
			gaps.append(best)
	gaps.sort()
	var median: float = gaps[gaps.size() / 2]
	assert_float(median).is_between(0.95, 1.5)


func test_every_circle_lights_at_the_wind_up_and_the_spikes_leave_the_mouth_together() -> void:
	var w := _world(Vector3(0, 0, 40))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var rain: BossAttackDef = Registry.boss_attack("cactus_rain")
	var i := em.spawn("gila_grande", Vector3.ZERO)
	_force_attack(em, i, _attack_index("gila_grande", "cactus_rain"))
	var wind: float = em.timer[i]
	assert_float(wind).is_equal_approx(rain.windup_seconds() / em.pace, 0.001)
	# every circle at once, at the landing radius, each up until its spike lands
	assert_bool(em._custom_lit.has(i)).is_true()
	var spots: Array = em._custom_lit[i]["spots"]
	assert_int(spots.size()).is_greater(30)
	assert_int(g.rings.size()).is_equal(spots.size())
	var k_real: float = em.pace * em.time_scale
	for k in range(spots.size()):
		var r: Dictionary = g.rings[k]
		assert_float(float(r["r"])).is_equal(rain.num("landing", "radius"))
		assert_float(float(r["dur"])).is_equal_approx(wind + float(spots[k]["land"]) / k_real, 0.01)
	# the crouch late in the wind-up
	var t := 0.0
	var crouched := false
	while em.state[i] == EnemyManager.STATE_ATTACK and t < 5.0:
		em._physics_process(DT)
		t += DT
		if em.state[i] == EnemyManager.STATE_ATTACK and em.timer[i] < rain.num("spew", "crouch") / em.pace * 0.5:
			crouched = crouched or em.squash[i] < 0.95
	assert_bool(crouched).is_true()
	# the spew: from the mouth, the boss stretched up, the shots all in the air together
	assert_int(em._custom_runs.size()).is_equal(1)
	var run: Dictionary = em._custom_runs[0]
	assert_float((run["from"] as Vector3).distance_to(em.custom_mouth(i, rain))).is_less(0.3)
	assert_float((run["from"] as Vector3).y - em.pos[i].y).is_greater(em.size[i] * 0.35)
	assert_float(em.squash[i]).is_greater(1.1)
	assert_bool(em._custom_lit.has(i)).is_false()
	var lands: Array = []
	var c0 := em.custom_landed
	var tt := 0.0
	while not em._custom_runs.is_empty() and tt < 5.0:
		var before := em.custom_landed
		em._physics_process(DT)
		tt += DT
		for n in range(em.custom_landed - before):
			lands.append(tt)
	assert_int(em.custom_landed - c0).is_equal(spots.size())
	lands.sort()
	assert_float(float(lands[lands.size() - 1]) - float(lands[0])).is_less_equal(rain.num("timing", "stagger") / em.pace + 2.0 * DT)
	# the hero 40 m off was never hit
	assert_int(w["hero"].hits).is_equal(0)


func test_the_lit_circles_are_held_marks_gone_as_each_lands_or_with_the_boss() -> void:
	var w := _world(Vector3(0, 0, 40), true)
	var em: EnemyManager = w["em"]
	var tg: Node = w["tg"]
	var i := em.spawn("gila_grande", Vector3.ZERO)
	_force_attack(em, i, _attack_index("gila_grande", "cactus_rain"))
	var n: int = (em._custom_lit[i]["spots"] as Array).size()
	# a disc and a ring per spot, at full size from the start
	assert_int(tg.held.size()).is_equal(2 * n)
	_step(em, 5.0)
	assert_bool(em._custom_runs.is_empty()).is_true()
	assert_int(tg.held.size()).is_equal(0)
	assert_int(tg.released.size()).is_equal(2 * n)
	# a boss that dies in its wind-up takes its circles with it
	tg.released.clear()
	_force_attack(em, i, _attack_index("gila_grande", "cactus_rain"))
	assert_int(tg.held.size()).is_greater(0)
	em.kill_all(false)
	em._physics_process(DT)
	assert_int(tg.held.size()).is_equal(0)
	assert_bool(em._custom_lit.is_empty()).is_true()


func test_zz_probe_giant_slams_after_rising() -> void:
	var w := _world(Vector3(0, 0, 0))
	var em: EnemyManager = w["em"]
	em.set_spawn_rise(0.45, 0.9, 0.7, 1.0)
	var i := em.spawn("hammer_giant", Vector3(2.5, 0, 0))
	var seen := false
	var t := 0.0
	var log: Array = []
	while t < 6.0 and not seen:
		em._physics_process(DT)
		t += DT
		if int(t * 60.0) % 30 == 0:
			log.append("t=%.2f st=%d rise=%.2f atk_t=%.2f hidden=%d pos=%s" % [t, em.state[i], em.rise_t[i], em.atk_t[i], em.hidden[i], str(em.pos[i])])
		seen = seen or em.state[i] == EnemyManager.STATE_ATTACK
	print("\n".join(log))
	assert_bool(seen).override_failure_message("\n".join(log)).is_true()
