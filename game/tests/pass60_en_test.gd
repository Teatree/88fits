extends GdUnitTestSuite

## Pass 60, lane EN (Garry: "Reduce the movement speed of all enemies by 10%" as "a multiplier for all"; "The Elite
## Scorpion Attack - the one where it pops out of the ground should be fixed: a visible sequence of the Scorpion actually
## popping from the ground, the dust effect from the Bull Beetle as a poof when it pops out, 1 s more before the pop";
## "Sun Lizard Elite still does the animations glitch thing, he sometimes flickers between frames"). The timeline's
## `creature_speed_mult` (0.9 on Red Canyon) reaches EnemyManager through the director (the arena too) and folds into its
## `pace`: a spawned creature's speed, `hostile_clock()`, every wind-up and scripted speed follow it, the hero's
## `Run.move_pace()` does not. The scorpion's burrow winds up 2.3 s (the Gila's 1.4 stays): it digs in with a small poof, a
## mound swells under the ring through the wind-up (EnemyManager._mound_start, ticked from the wind-up's timer), the pop
## brings the creature up with `rise_t` 0 -> 1 over RISE_TIME at the creatures' pace, in a poof of soft dust and clods
## (Fx.pop_dust, never thinned) as the mound goes, the damage landing at the pop as before; it bites
## nobody and starts nothing until it is up, the safety un-hide rises too, and the painting is drawn sunk by the part still
## under (rise_sink). The Prophet: the caster brain stands for its hold, a ranged creature faces and walks by its brain's
## intent (a knock no longer turns it), a view holds VIEW_MIN after a change, and an eight-direction creature's front-only
## hit and attack frames show only in the front view.

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
func telegraph_line(_a, _b, c, d, _e) -> void:
	lines.append({"length": float(c), "dur": float(d)})
func telegraph_ring(a, b, c, _d, _e = true) -> void:
	rings.append({"at": a, "r": float(b), "dur": float(c)})
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func shockwave(_a, _b) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
"""

const FAKE_FX := """extends Node
var poofs: Array = []
func pop_dust(at, size) -> void:
	poofs.append({"at": at, "size": float(size)})
func burst(_a, _b, _c) -> void:
	pass
func hit(_a, _b) -> void:
	pass
"""

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
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const DT := 1.0 / 60.0
## The run strips of the five views (VIEW_ANIM[A_RUN]) and the idle ones
const RUN_STRIPS := [0, 5, 7, 9, 11]


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.arena = false
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero at `hero_at` with the real crowd; `fx` "fake" records pop_dust calls, "real" is Fx.
func _world(hero_at := Vector3.ZERO, fx := "") -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	g.player = hero
	if fx == "fake":
		var f := Node.new()
		f.set_script(_script(FAKE_FX))
		g.add_child(f)
		g.fx = f
	elif fx == "real":
		var f := Fx.new()
		g.add_child(f)
		g.fx = f
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "fx": g.fx}


func _attack_index(id: String, atk_name: String) -> int:
	var attacks: Array = Registry.enemy(id).boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


func _attack(id: String, atk_name: String) -> Dictionary:
	var k := _attack_index(id, atk_name)
	return (Registry.enemy(id).boss["attacks"] as Array)[k] if k >= 0 else {}


## Creature `i` of `id` put straight into its attack `atk_name` through the runner.
func _force_attack(em: EnemyManager, i: int, id: String, atk_name: String, ppos: Vector3) -> void:
	em.state[i] = EnemyManager.STATE_MOVE
	em.hold_t[i] = 0.0
	em.atk_i[i] = _attack_index(id, atk_name)
	em.atk_t[i] = 0.0
	em._update_attacks(i, DT, ppos)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)


## Steps the crowd through whole ticks until `seconds` is covered; gives back the time really stepped (whole ticks).
func _step(em: EnemyManager, seconds: float) -> float:
	var t := 0.0
	while t < seconds - 0.0001:
		em._physics_process(DT)
		t += DT
	return t


# ---------------------------------------------------------------- creature_speed_mult

func test_the_timeline_reads_creature_speed_mult_and_defaults_to_one() -> void:
	var tl := JsonContent.timeline_from_dict({"creature_speed_mult": 0.9})
	assert_float(tl.creature_speed_mult).is_equal_approx(0.9, 0.0001)
	assert_float(JsonContent.timeline_from_dict({}).creature_speed_mult).is_equal(1.0)
	assert_float(WaveTimeline.new().creature_speed_mult).is_equal(1.0)
	var em: EnemyManager = auto_free(EnemyManager.new())
	assert_float(em.creature_speed_mult).is_equal(1.0)


func test_red_canyon_carries_0_9_and_the_import_matches() -> void:
	var f := FileAccess.open("res://content/maps/red_canyon/red_canyon.json", FileAccess.READ)
	assert_object(f).is_not_null()
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	assert_float(float((d["timeline_data"] as Dictionary).get("creature_speed_mult", 1.0))).is_equal_approx(0.9, 0.0001)
	# the .tres the game plays says the same (import_json ran)
	assert_float(Registry.map("red_canyon").timeline.creature_speed_mult).is_equal_approx(0.9, 0.0001)
	# and the hero's knob is still the map's move_pace, nothing else
	assert_float(Run.move_pace()).is_equal_approx(Registry.map("red_canyon").timeline.move_pace, 0.0001)


func test_a_creature_spawns_at_the_multiple_and_the_shot_clock_follows() -> void:
	var w := _world(Vector3(0, 0, 20))
	var em: EnemyManager = w["em"]
	# the scorpion has no variance: its speed is its own x the pace
	var a := em.spawn("dune_scorpion", Vector3.ZERO)
	var s1: float = em.speed[a]
	assert_float(s1).is_equal_approx(Registry.enemy("dune_scorpion").speed * Run.move_pace(), 0.001)
	em.creature_speed_mult = 0.9
	var b := em.spawn("dune_scorpion", Vector3(6, 0, 0))
	assert_float(em.speed[b]).is_equal_approx(s1 * 0.9, 0.001)
	assert_float(em.pace).is_equal_approx(Run.move_pace() * 0.9, 0.0001)
	assert_float(em.hostile_clock()).is_equal_approx(em.time_scale * Run.move_pace() * 0.9, 0.0001)
	# the tick reads it again (a change between spawns reaches the clocks)
	em.creature_speed_mult = 0.5
	em._physics_process(DT)
	assert_float(em.pace).is_equal_approx(Run.move_pace() * 0.5, 0.0001)
	# the hero's pace is untouched
	assert_float(Run.move_pace()).is_equal_approx(Registry.map("red_canyon").timeline.move_pace, 0.0001)


func test_the_director_hands_the_multiple_over_in_a_run_and_in_the_arena() -> void:
	var w := _world(Vector3.ZERO)
	var em: EnemyManager = w["em"]
	var d: WaveDirector = auto_free(WaveDirector.new())
	d.game = w["g"]
	d.map = Registry.map("red_canyon")
	d.timeline = Registry.map("red_canyon").timeline
	d.running = true
	d.phase = WaveDirector.Phase.NORMAL
	d._apply_mults()
	assert_float(em.creature_speed_mult).is_equal_approx(0.9, 0.0001)
	# the arena plays creatures at their data's damage but at the map's speed: the walks are looked at there
	em.creature_speed_mult = 1.0
	Run.arena = true
	d._apply_mults()
	Run.arena = false
	assert_float(em.creature_speed_mult).is_equal_approx(0.9, 0.0001)
	assert_float(em.creature_damage_mult).is_equal(1.0)


func test_wind_ups_and_scripted_speeds_follow_the_multiple() -> void:
	var w := _world(Vector3(0, 0, 10))
	var em: EnemyManager = w["em"]
	em.creature_speed_mult = 0.9
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	_force_attack(em, i, "dune_scorpion", "burrow", w["hero"].global_position)
	# the wind-up lasts 1 / (move_pace x creature_speed_mult): the creature winds up 11% longer
	assert_float(em.timer[i]).is_equal_approx(2.3 / (Run.move_pace() * 0.9), 0.001)
	# a boss's scripted roll runs at its speed x the pace
	var k := em.spawn("tumbleweed_king", Vector3(0, 0, -30))
	em.atk_i[k] = _attack_index("tumbleweed_king", "roll") + 1
	assert_float(em._scripted_speed(k, Registry.enemy("tumbleweed_king"))).is_equal_approx(float(_attack("tumbleweed_king", "roll")["speed"]) * Run.move_pace() * 0.9, 0.001)


# ---------------------------------------------------------------- the scorpion's pop-out

func test_the_scorpions_burrow_winds_up_a_second_longer_and_the_gilas_as_before() -> void:
	assert_float(float(_attack("dune_scorpion", "burrow")["windup"])).is_equal_approx(2.3, 0.001)
	# (pass 73, lane GROUND, re-pinned on purpose: the Gila's wind-up is its sink, three seconds under unseen and its
	# warning: 0.6 + 3.0 + 0.4)
	var gb := _attack("gila_grande", "burrow")
	# (pass 115, lane BOSS: Garry's "+25% time before the Gila pops out": 3.75 s under, pass115_BOSS_test)
	assert_float(float(gb["windup"])).is_equal_approx(float(gb.get("sink", 0.0)) + 3.75 + float(gb.get("warn", 0.4)), 0.001)
	assert_float(EnemyManager.RISE_TIME).is_equal_approx(0.4, 0.0001)


func test_the_burrow_raises_a_mound_under_the_ring_through_the_wind_up() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var g: Node = w["g"]
	var ppos: Vector3 = w["hero"].global_position
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	_force_attack(em, i, "dune_scorpion", "burrow", ppos)
	# (pass 73, lane GROUND, re-pinned on purpose: it sinks out of sight in the open first, then it is under)
	assert_int(em.hidden[i]).is_equal(0)
	assert_float(em.rise_v[i]).is_less(0.0)
	# the ring on the hero, as long as the wind-up
	assert_int((g.rings as Array).size()).is_equal(1)
	var ring: Dictionary = g.rings[0]
	assert_float(ring["r"]).is_equal_approx(4.6, 0.001)
	assert_float(ring["dur"]).is_equal_approx(em.timer[i], 0.001)
	# and the mound at the ring's centre: a dome of 0.3 of the creature's size (0.9 m for the scorpion), a bump from the
	# first tick that swells through the wind-up
	assert_bool(em._mounds.has(i)).is_true()
	var dome: MeshInstance3D = em._mounds[i]["dome"]
	assert_float(Vector2(dome.position.x - ppos.x, dome.position.z - ppos.z).length()).is_less(0.001)
	assert_float(float((dome.mesh as SphereMesh).radius)).is_equal_approx(EnemyManager.MOUND_FRAC * em.size[i], 0.001)
	assert_float(float((dome.mesh as SphereMesh).radius)).is_equal_approx(0.9, 0.001)
	var full: float = 0.9 * EnemyManager.MOUND_DOME
	var top0: float = em.mound_top(i)
	assert_float(top0).is_between(0.03, 0.08)
	var wind: float = em.timer[i]
	_step(em, wind * 0.5)
	assert_int(em.hidden[i]).is_equal(1)
	var top_half: float = em.mound_top(i)
	assert_float(top_half).is_greater(top0 + 0.1)
	assert_float(top_half).is_between(full * 0.6, full * 0.85)
	_step(em, wind * 0.4)
	assert_int(em.hidden[i]).is_equal(1)
	assert_float(em.mound_top(i)).is_greater(top_half)
	assert_float(em.mound_top(i)).is_less(full + 0.001)
	# the pop: the creature up, the mound gone
	_step(em, wind * 0.15)
	assert_int(em.hidden[i]).is_equal(0)
	assert_bool(em._mounds.has(i)).is_false()
	assert_float(em.mound_top(i)).is_equal(-1.0)
	# one freed under the sand leaves no mound behind
	var k := em.spawn("dune_scorpion", Vector3(8, 0, 0))
	_force_attack(em, k, "dune_scorpion", "burrow", ppos)
	assert_bool(em._mounds.has(k)).is_true()
	em.kill_all(false)
	assert_bool(em._mounds.has(k)).is_false()


func test_the_pop_brings_it_up_rising_in_a_poof_with_the_damage_at_once_and_no_bite_until_up() -> void:
	var w := _world(Vector3(0, 0, 6), "fake")
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var fx: Node = w["fx"]
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	em.cooldown[i] = 99.0
	_force_attack(em, i, "dune_scorpion", "burrow", hero.global_position)
	# (pass 73, lane GROUND, re-pinned on purpose: it sinks in sight first, `sink` seconds, then it is under)
	var t := 0.0
	while t < 3.0 and em.hidden[i] == 0 and em.state[i] == EnemyManager.STATE_ATTACK:
		em._physics_process(DT)
		t += DT
	assert_int(em.hidden[i]).is_equal(1)
	# under the sand for the rest of the wind-up: nothing drawn, nothing hit (damage() says true only for a kill: the
	# proof is the HP untouched)
	var hp0: float = em.hp[i]
	while t < 6.0 and em.hidden[i] == 1:
		em.damage(i, 1.0, "")
		assert_float(em.hp[i]).is_equal(hp0)
		em._physics_process(DT)
		t += DT
	assert_int(em.hidden[i]).is_equal(0)
	assert_float(t).is_between(2.3 / em.pace - 0.05, 2.3 / em.pace + 0.1)
	# the pop: up it comes where the ring was, the damage lands now, the poof goes off at its feet at its size
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.rise_t[i]).is_less(0.1)
	assert_float(Vector2(em.pos[i].x - hero.global_position.x, em.pos[i].z - hero.global_position.z).length()).is_less(0.001)
	assert_int(hero.hits).is_equal(1)
	# two poofs: a small one where it dug in, the full one where it comes up
	assert_int((fx.poofs as Array).size()).is_equal(2)
	assert_float(float(fx.poofs[0]["size"])).is_equal_approx(em.size[i] * 0.6, 0.001)
	assert_float(float(fx.poofs[1]["size"])).is_equal_approx(em.size[i], 0.001)
	assert_float((fx.poofs[1]["at"] as Vector3).distance_to(em.pos[i])).is_less(0.001)
	# a rising creature can be hit: it is there to see
	em.damage(i, 1.0, "")
	assert_float(em.hp[i]).is_less(hp0)
	assert_float(em.flash[i]).is_equal(1.0)
	# it rises over its `rise` (pass 73; RISE_TIME without one) at the creatures' pace: about half way at half the time,
	# and it bites nobody meanwhile (the hero stands on top of it, well within reach); the time is counted in the whole
	# ticks really stepped
	var rise_s := float(_attack("dune_scorpion", "burrow").get("rise", EnemyManager.RISE_TIME))
	var rose: float = _step(em, rise_s / em.pace * 0.5)
	assert_float(em.rise_t[i]).is_between(0.4, 0.6)
	assert_int(hero.hits).is_equal(1)
	while rose < 1.0 and em.rise_t[i] < 1.0:
		assert_int(hero.hits).is_equal(1)
		em._physics_process(DT)
		rose += DT
	assert_float(em.rise_t[i]).is_equal(1.0)
	assert_float(rose).is_between(rise_s / em.pace - 0.001, rise_s / em.pace + 2.5 * DT)
	# up: the bite lands
	_step(em, 0.5)
	assert_int(hero.hits).is_greater_equal(2)


func test_nothing_new_starts_until_it_is_up() -> void:
	var w := _world(Vector3(0, 0, 6))
	var em: EnemyManager = w["em"]
	var ppos: Vector3 = w["hero"].global_position
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	em.state[i] = EnemyManager.STATE_MOVE
	em.cooldown[i] = 0.0
	em.rise_t[i] = 0.0
	em.atk_t[i] = 0.0
	# the runner waits, the brain stands (the hero is in its charge's trigger range)
	em._update_attacks(i, DT, ppos)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.atk_t[i]).is_equal(0.0)
	em._steer(i, ppos, DT)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.vel[i].length()).is_equal(0.0)
	assert_float(em.intent[i].length()).is_equal(0.0)
	# up: the script goes on
	em.rise_t[i] = 1.0
	em._update_attacks(i, DT, ppos)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)


func test_the_safety_un_hide_rises_too() -> void:
	var w := _world(Vector3(0, 0, 12))
	var em: EnemyManager = w["em"]
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	em.hidden[i] = 1
	em.state[i] = EnemyManager.STATE_WINDUP
	em._update_boss(DT, w["hero"].global_position)
	assert_int(em.hidden[i]).is_equal(0)
	assert_float(em.rise_t[i]).is_equal(0.0)


func test_a_rising_figure_is_drawn_sunk_by_the_part_still_under_and_the_render_runs() -> void:
	var w := _world(Vector3(0, 0, 20))
	var em: EnemyManager = w["em"]
	var i := em.spawn("dune_scorpion", Vector3.ZERO)
	em.state[i] = EnemyManager.STATE_MOVE
	em.squash[i] = 1.0
	var cam_up := Vector3(0, 0.695, -0.719)
	var head: float = Registry.enemy("dune_scorpion").head
	# up: no sink of its own
	assert_float(em.rise_sink(i, 1.0, cam_up).length()).is_equal(0.0)
	# just broken through: the whole figure, its top at the ground, down the billboard's up
	em.rise_t[i] = 0.0
	var sink := em.rise_sink(i, 1.0, cam_up)
	assert_float(sink.length()).is_equal_approx(em.size[i] * head, 0.001)
	assert_float(sink.normalized().dot(cam_up.normalized())).is_greater(0.999)
	# half way up in time is three quarters up in the picture (the ease-out), and the sink shrinks with it
	em.rise_t[i] = 0.5
	assert_float(EnemyManager.rise_ease(0.5)).is_equal_approx(0.75, 0.0001)
	assert_float(em.rise_sink(i, 1.0, cam_up).length()).is_equal_approx(em.size[i] * head * 0.25, 0.001)
	assert_float(EnemyManager.rise_ease(0.0)).is_equal(0.0)
	assert_float(EnemyManager.rise_ease(1.0)).is_equal(1.0)
	# the render draws it (it is not hidden) and its shadow
	em._cf_tick = Vector3(0, 0, -1)
	em._render()
	assert_int(em._shadow_mm.visible_instance_count).is_equal(1)
	# and its see-through pass is told to draw nothing while it rises: the frame index the instance data carries takes
	# RISE_FLAG in its fraction (the part still under the sand, hidden from the main pass by the terrain, had shown through
	# the silhouette pass as a ghost of the whole figure), a whole number again once it is up, and both shaders floor it
	# for the frame (the headless renderer keeps no instance buffer to read back, so the rule is checked on its own)
	assert_float(EnemyManager.RISE_FLAG).is_equal(0.5)
	assert_float(EnemyManager.frame_code(37, 0.5)).is_equal(37.5)
	assert_float(EnemyManager.frame_code(37, 0.0)).is_equal(37.5)
	assert_float(EnemyManager.frame_code(37, 1.0)).is_equal(37.0)
	assert_float(floorf(EnemyManager.frame_code(37, 0.5))).is_equal(37.0)
	em.rise_t[i] = 1.0
	em._render()
	assert_int(em._shadow_mm.visible_instance_count).is_equal(1)


func test_pop_dust_is_a_burst_of_soft_puffs_and_grains_never_thinned() -> void:
	var w := _world(Vector3(0, 0, 20), "real")
	var fx: Fx = w["fx"]
	var n0: int = fx._n
	fx.pop_dust(Vector3.ZERO, 3.0)
	# a 3 m creature: 12 + 3 puffs round the spot and a column of 3, 10 grains and 6 clods (box shards both; a clod starts
	# 0.1 of the body's width, a grain 0.11 m)
	var puffs := 0
	var grains := 0
	var clods := 0
	for k in range(n0, fx._n):
		if fx._shard[k] == 4:
			puffs += 1
		elif fx._s0[k] >= 0.09 * 2.1:
			clods += 1
		else:
			grains += 1
	assert_int(puffs).is_equal(18)
	assert_int(grains).is_equal(10)
	assert_int(clods).is_equal(6)
	# the puffs are sized to the body (about 0.7 of the size wide) and flung out and up from the spot
	var up := 0
	for k in range(n0, fx._n):
		if fx._shard[k] == 4:
			assert_float(fx._s1[k]).is_between(0.8 * 2.1 - 0.001, 1.5 * 2.1 + 0.001)
			if fx._vel[k].y > 0.5:
				up += 1
	assert_int(up).is_equal(18)
	# a smaller creature makes a smaller poof with fewer puffs
	n0 = fx._n
	fx.pop_dust(Vector3(10, 0, 0), 1.0)
	var small := 0
	for k in range(n0, fx._n):
		if fx._shard[k] == 4:
			small += 1
	assert_int(small).is_equal(16)


# ---------------------------------------------------------------- the Sun Prophet

func test_the_prophet_stands_to_cast_and_faces_the_circling_hero_without_flickering() -> void:
	# the hero 8 m down the screen (+Z in the fixed camera): the Prophet's keep_distance spot is right where he stands
	var w := _world(Vector3(0, 0, 8))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("sun_prophet", Vector3.ZERO)
	em.state[i] = EnemyManager.STATE_MOVE
	em.hold_t[i] = 10.0
	em.atk_t[i] = 99.0
	em._physics_process(DT)
	assert_int(int(em.view[i])).is_equal(0)
	# the hero circles him at 3 m/s for 3 s: the view changes at most once or twice (the hero really does move round
	# him), the Prophet shows no walk and stays put
	var v0 := int(em.view[i])
	var changes := 0
	var runs := 0
	var t := 0.0
	while t < 3.0:
		var ang := 3.0 * t / 8.0
		hero.global_position = Vector3(sin(ang) * 8.0, 0, cos(ang) * 8.0)
		em._physics_process(DT)
		if int(em.view[i]) != v0:
			changes += 1
			v0 = int(em.view[i])
		if RUN_STRIPS.has(em._strip_of(i, em.type_idx[i])):
			runs += 1
		t += DT
	assert_int(changes).is_less(3)
	assert_int(runs).is_equal(0)
	assert_float(Vector2(em.pos[i].x, em.pos[i].z).length()).is_less(0.3)
	assert_float(em.hold_t[i]).is_between(6.5, 7.5)


func test_a_knock_or_a_shove_turns_a_standing_prophet_no_more() -> void:
	var w := _world(Vector3(0, 0, 8))
	var em: EnemyManager = w["em"]
	var i := em.spawn("sun_prophet", Vector3.ZERO)
	em.state[i] = EnemyManager.STATE_MOVE
	em.hold_t[i] = 10.0
	em.atk_t[i] = 99.0
	em._physics_process(DT)
	assert_int(int(em.view[i])).is_equal(0)
	var flip0 := int(em.flip[i])
	var a0: float = em.anim_t[i]
	# a hard knock sideways: it carries him, but he keeps facing the hero and keeps his standing frames
	em.kb[i] = Vector3(6.0, 0, 0)
	var changes := 0
	for n in range(20):
		em._physics_process(DT)
		if int(em.view[i]) != 0 or int(em.flip[i]) != flip0:
			changes += 1
	assert_int(changes).is_equal(0)
	assert_float(em.pos[i].x).is_greater(0.3)
	# twenty ticks at the standing pace, ATTACK_FPS (a walk would have run at 15 a second)
	assert_float(em.anim_t[i] - a0).is_equal_approx(EnemyManager.ATTACK_FPS * 20.0 * DT, 0.05)


func test_a_view_holds_a_quarter_second_after_a_change() -> void:
	assert_float(EnemyManager.VIEW_MIN).is_equal_approx(0.25, 0.0001)
	var w := _world(Vector3(0, 0, 8))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var i := em.spawn("sun_prophet", Vector3.ZERO)
	em.state[i] = EnemyManager.STATE_MOVE
	em.hold_t[i] = 10.0
	em.atk_t[i] = 99.0
	em._physics_process(DT)
	assert_int(int(em.view[i])).is_equal(0)
	# the hero jumps straight up the screen: the back view, and the timer runs
	hero.global_position = Vector3(0, 0, -8)
	em._physics_process(DT)
	assert_int(int(em.view[i])).is_equal(1)
	assert_float(em.view_t[i]).is_greater(0.2)
	# and straight back down: the view holds until the quarter second is out
	hero.global_position = Vector3(0, 0, 8)
	em._physics_process(DT)
	assert_int(int(em.view[i])).is_equal(1)
	_step(em, 0.3)
	assert_int(int(em.view[i])).is_equal(0)


func test_eight_direction_creatures_show_the_front_only_hit_and_attack_frames_in_the_front_view_only() -> void:
	var w := _world(Vector3(0, 0, 20))
	var em: EnemyManager = w["em"]
	var i := em.spawn("sun_prophet", Vector3.ZERO)
	var t := em.type_idx[i]
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.intent[i] = Vector3.ZERO
	# hit, seen from the side: the side stand with the flash, not the front hit frame
	em.flash[i] = 1.0
	em.view[i] = 2
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.VIEW_ANIM[EnemyManager.A_IDLE][2])
	em.view[i] = 0
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.A_HIT)
	# attacking with his back to the camera: the back stand; facing it: the attack frames
	em.flash[i] = 0.0
	em.state[i] = EnemyManager.STATE_ATTACK
	em.view[i] = 1
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.VIEW_ANIM[EnemyManager.A_IDLE][1])
	em.view[i] = 0
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.A_ATTACK)
	# hit while walking sideways: the side walk
	em.state[i] = EnemyManager.STATE_MOVE
	em.intent[i] = Vector3(1, 0, 0)
	em.vel[i] = Vector3(1, 0, 0)
	em.flash[i] = 1.0
	em.view[i] = 2
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.VIEW_ANIM[EnemyManager.A_RUN][2])
	# a ranged creature shoved by the crowd while its brain stands still shows its stand, not a walk
	em.intent[i] = Vector3.ZERO
	em.flash[i] = 0.0
	assert_int(em._strip_of(i, t)).is_equal(EnemyManager.VIEW_ANIM[EnemyManager.A_IDLE][2])
	# a two-direction creature keeps its hit frame whichever way it faces (the skeleton)
	var k := em.spawn("skeleton", Vector3(5, 0, 0))
	em.state[k] = EnemyManager.STATE_MOVE
	em.flash[k] = 1.0
	em.away[k] = 1
	assert_int(em._strip_of(k, em.type_idx[k])).is_equal(EnemyManager.A_HIT)


func test_the_caster_brain_stands_for_its_hold() -> void:
	var w := _world(Vector3(0, 0, 8))
	var em: EnemyManager = w["em"]
	var ppos: Vector3 = w["hero"].global_position
	# his spot is the origin; he stands 6 m beyond it
	var i := em.spawn("sun_prophet", Vector3(0, 0, -6))
	em.state[i] = EnemyManager.STATE_MOVE
	em.hold_t[i] = 5.0
	em._steer(i, ppos, DT)
	assert_float(em.intent[i].length()).is_equal(0.0)
	assert_float(em.vel[i].length()).is_less(0.001)
	# the hold over, he walks to the spot (down the screen, +Z)
	em.hold_t[i] = 0.0
	em._steer(i, ppos, DT)
	assert_float(em.intent[i].length()).is_greater(0.2)
	assert_float(em.intent[i].z).is_greater(0.0)
	assert_float(em.vel[i].distance_to(em.intent[i])).is_less(0.001)
