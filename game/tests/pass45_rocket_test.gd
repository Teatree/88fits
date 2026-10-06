extends GdUnitTestSuite

## Pass 45: the rocketeer's rocket once its rocketeer is dead. It hangs and blinks red and white (a red ring blinking on
## the sand under the crowd it will take), climbs wild and fast, then dives on the thickest crowd and goes off there,
## never on the hero; a loose rocket that runs its life out goes off the same way (it used to throw the hero).

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var map = null
var camera = null
var director = null
var portal = null
var paused := false
var blasts: Array = []
var loose_blasts: Array = []
var toasts: Array = []
var marks: Dictionary = {}
var marks_ended: Array = []
var _mark_id := 0
func rocket_out(_i: int) -> bool:
	return false
func rocket_blast(at: Vector3, r: float, damage: float, info: Dictionary, blast: Dictionary) -> void:
	blasts.append({"at": at, "r": r, "damage": damage, "info": info, "blast": blast})
func loose_rocket_blast(at: Vector3, r: float, blast: Dictionary) -> void:
	loose_blasts.append({"at": at, "r": r, "blast": blast})
func loose_mark(at: Vector3, _r: float) -> int:
	_mark_id += 1
	marks[_mark_id] = {"at": at, "alphas": []}
	return _mark_id
func loose_mark_move(id: int, at: Vector3, alpha: float) -> void:
	marks[id]["at"] = at
	(marks[id]["alphas"] as Array).append(alpha)
func loose_mark_end(id: int) -> void:
	marks_ended.append(id)
func toast(t: String, _c: Color = Color.WHITE) -> void:
	toasts.append(t)
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_CAMERA := """extends Node
var z := 1.0
var camera: Camera3D
func zoom() -> float:
	return z
func current_yaw() -> float:
	return 0.0
"""

const DT := 1.0 / 60.0
const BLAST := {"knockback": 26.0, "lift": 6.5, "throw": 26.0, "throw_radius": 4.5}

var _clock := 0.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _fake_game(hero_at: Vector3) -> Node:
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
	return g


func _manager(g: Node) -> EnemyManager:
	var em: EnemyManager = auto_free(EnemyManager.new())
	em.game = g
	em.player = g.player
	add_child(em)
	g.enemies = em
	return em


func _projectiles(g: Node) -> ProjectileManager:
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	pm.register_kind(BoxMesh.new(), null, 1.0, true)
	return pm


## One physics tick of the crowd (when there is one) and the shots, on the suite's clock.
func _tick(em: EnemyManager, pm: ProjectileManager) -> void:
	if em:
		em._physics_process(DT)
	pm._physics_process(DT)
	_clock += DT


func _run_to(em: EnemyManager, pm: ProjectileManager, t: float) -> void:
	while _clock < t:
		_tick(em, pm)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _nearest_of(em: EnemyManager, idx: Array, at: Vector3) -> float:
	var best := 1e9
	for e: int in idx:
		best = minf(best, _flat(em.pos[e], at))
	return best


func test_a_loose_rocket_blinks_climbs_and_dives_on_the_crowd() -> void:
	# pass 48: the loose rocket flies on the creatures' shot clock, paced (Red Canyon's 0.8): every phase lasts 1/pace of
	# real time, so the marks below are the pace-free seconds over the pace
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var pc := Run.move_pace()
	var g := _fake_game(Vector3(0, 0, 60))
	var em := _manager(g)
	var pm := _projectiles(g)
	# six goblins in a knot at (10, 0, 0), one alone at (-3, 0, 0); a hundred times their HP so the scratch kills none
	var crowd: Array = []
	for off: Vector3 in [Vector3.ZERO, Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0.8, 0, 0.8)]:
		var e := em.spawn("goblin", Vector3(10, 0, 0) + off, null, 1.0, 100.0)
		assert_int(e).is_greater_equal(0)
		crowd.append(e)
	var lone := em.spawn("goblin", Vector3(-3, 0, 0), null, 1.0, 100.0)
	var i := pm.launch_enemy_rocket(0, 7, Vector3(0, 1, 0), Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6, 0.0, {"by": "Rocketeer"}, BLAST)
	_clock = 0.0
	_tick(em, pm)
	# his death: the rocket goes loose, says so, and is nobody's any more
	pm.kill_rockets_of(7)
	_clock = 0.0
	assert_bool(bool(pm.extra[i].get("loose", false))).is_true()
	assert_bool(pm.has_rocket_of(7)).is_false()
	assert_array(g.toasts).contains(["ROCKET LOOSE!"])
	# the blink: it hangs, grows, and flashes all the way white and all the way back to red
	var lo := 1.0
	var hi := 0.0
	while _clock < 0.3 / pc:
		_tick(em, pm)
		lo = minf(lo, pm.glow[i])
		hi = maxf(hi, pm.glow[i])
	assert_int(int(pm.extra[i]["loose_phase"])).is_equal(0)
	assert_float(pm.vel[i].length()).is_less(3.2)
	assert_float(pm.psize[i]).is_greater(1.0)
	while _clock < 0.65 / pc:
		_tick(em, pm)
		lo = minf(lo, pm.glow[i])
		hi = maxf(hi, pm.glow[i])
	assert_float(hi).is_greater(0.9)
	assert_float(lo).is_less(0.1)
	# the red ring went down under the knot from the first tick and blinked with it
	assert_int(g.marks.size()).is_equal(1)
	var ring_at: Vector3 = g.marks[1]["at"]
	assert_float(_nearest_of(em, crowd, ring_at)).is_less(2.5)
	var alphas: Array = g.marks[1]["alphas"]
	assert_float(float(alphas.min())).is_less(0.4)
	assert_float(float(alphas.max())).is_greater(0.8)
	# the climb: up and fast
	_run_to(em, pm, 1.2 / pc)
	assert_int(int(pm.extra[i]["loose_phase"])).is_equal(1)
	assert_float(pm.pos[i].y).is_greater(1.5)
	assert_float(pm.vel[i].length()).is_greater(8.0)
	# the dive: on the knot, not on the lone goblin
	_run_to(em, pm, 1.8 / pc)
	assert_int(int(pm.extra[i]["loose_phase"])).is_equal(2)
	var dive_at: Vector3 = pm.extra[i]["dive_at"]
	assert_float(_nearest_of(em, crowd, dive_at)).is_less(2.5)
	assert_float(_flat(em.pos[lone], dive_at)).is_greater(6.0)
	# it comes down on them, never through the hero's blast, and its ring goes with it
	while _clock < 4.0 / pc and pm.alive[i] == 1:
		_tick(em, pm)
	assert_int(pm.alive[i]).is_equal(0)
	assert_array(g.blasts).is_empty()
	assert_int(g.loose_blasts.size()).is_equal(1)
	assert_float(_nearest_of(em, crowd, g.loose_blasts[0]["at"])).is_less(3.0)
	Run.end()
	assert_float(float((g.loose_blasts[0]["blast"] as Dictionary).get("throw", 0.0))).is_equal_approx(26.0, 0.01)
	assert_array(g.marks_ended).contains([1])


func test_a_loose_rocket_with_nobody_in_reach_never_blasts_the_hero() -> void:
	# no creatures at all (and no crowd manager, as in a bare fake game): it still blinks, climbs and comes down
	var g := _fake_game(Vector3(0, 0, 1.5))
	var pm := _projectiles(g)
	var i := pm.launch_enemy_rocket(0, 7, Vector3(0, 1, 0), Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6, 0.0, {}, BLAST)
	pm.kill_rockets_of(7)
	_clock = 0.0
	while _clock < 5.0 and pm.alive[i] == 1:
		_tick(null, pm)
	assert_int(pm.alive[i]).is_equal(0)
	assert_array(g.blasts).is_empty()
	assert_int(g.loose_blasts.size()).is_equal(1)
	# one that runs its life out goes off through the loose blast too (it used to go through the hero's)
	var j := pm.launch_enemy_rocket(0, 8, Vector3(0, 1, 0), Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6, 0.0, {}, BLAST)
	pm.kill_rockets_of(8)
	pm.life[j] = 0.001
	_tick(null, pm)
	assert_int(pm.alive[j]).is_equal(0)
	assert_array(g.blasts).is_empty()
	assert_int(g.loose_blasts.size()).is_equal(2)
	# a rocket whose rocketeer lives still goes off big
	var k := pm.launch_enemy_rocket(0, 9, Vector3(0, 1, -30), Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6, 0.0, {}, BLAST)
	pm.life[k] = 0.001
	_tick(null, pm)
	assert_int(g.blasts.size()).is_equal(1)
	assert_float(pm.glow[k]).is_equal(0.0)


func test_the_rocket_kind_its_shader_and_its_sounds_exist() -> void:
	var g := _fake_game(Vector3.ZERO)
	var pm := _projectiles(g)
	pm.register_kind(BoxMesh.new(), null)
	assert_bool((pm.kinds[0]["mm"] as MultiMesh).use_custom_data).is_true()
	assert_bool((pm.kinds[1]["mm"] as MultiMesh).use_custom_data).is_false()
	# one of each drawn (the custom data goes only to the kind that has room for it)
	pm.launch_enemy_rocket(0, 7, Vector3(0, 1, 0), Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6)
	pm.hostile_shot(1, Vector3(0, 1, 0), Vector3(0, 0, 4), 5.0, 0.0)
	pm._render()
	assert_int((pm.kinds[0]["mm"] as MultiMesh).visible_instance_count).is_equal(1)
	assert_int((pm.kinds[1]["mm"] as MultiMesh).visible_instance_count).is_equal(1)
	var sh = load("res://core/shaders/rocket.gdshader")
	assert_bool(sh is Shader).is_true()
	assert_str((sh as Shader).code).contains("INSTANCE_CUSTOM")
	for id in ["en_rocket_loose", "en_rocket_wild", "en_rocket_dive"]:
		assert_bool(Registry.soundmap.has_sound(id)).override_failure_message("no sound map row for " + id).is_true()
		assert_bool(FileAccess.file_exists("res://content/sounds/placeholder/%s.wav" % id)).override_failure_message("no wav for " + id).is_true()
	# pass 48: the Vulture Raider's own line (the art lane's), the loose rocket still in it
	assert_str(Registry.enemy("rocketeer").doc).contains("loose")
