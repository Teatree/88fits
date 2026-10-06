extends GdUnitTestSuite

## Pass 45, the bosses: a scripted roll runs one clock (the runner's) for its whole `duration` at the attack's `speed`,
## and its red line is as long as the roll (speed x duration + the body) or a brand's `length`; the Tumbleweed King
## has 1.6x the health, a `tumbleweed_volley` on a `spokes` telegraph (twelve rolling hostile shots that throw the
## hero past the shove's cap) and a ring of `tumbleweed_minion`s; the Brander's brand lines know their owner; the
## specials have 50 HP and the harpooner no armour; the giant's drops are rarer; and a creature whose front painting
## turns the other way (the hellhound) says so in its JSON (`front_faces`) and has its mirror inverted in the render.

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var map = null
var camera = null
var director = null
var portal = null
var paused := false
var lines: Array = []
var volleys: Array = []
func telegraph_line(_a, _b, c, _d, _e) -> void:
	lines.append(float(c))
func telegraph_ring(_a, _b, _c, _d) -> void:
	pass
func fx_burst(_a, _b, _c) -> void:
	pass
func fx_hit(_a, _b) -> void:
	pass
func tumbleweed_volley(at, first, count, speed, damage, life, knockback, lift, info) -> void:
	volleys.append({"at": at, "first": first, "count": count, "speed": speed, "damage": damage, "life": life, "knockback": knockback, "lift": lift, "info": info})
"""

const FAKE_HERO := """extends Node3D
var dead := false
var velocity := Vector3.ZERO
var last_outcome := "hit"
var blasts: Array = []
var shoves := 0
var hits := 0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3) -> bool:
	shoves += 1
	return true
func blast(v: Vector3, up: float = 0.0) -> void:
	blasts.append({"v": v, "up": up})
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
func shake(_a: float) -> void:
	pass
"""

const DT := 1.0 / 60.0


func before_test() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


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


func _pm(g: Node) -> ProjectileManager:
	var pm: ProjectileManager = auto_free(ProjectileManager.new())
	pm.game = g
	add_child(pm)
	g.projectiles = pm
	pm.register_kind(BoxMesh.new(), null)
	return pm


func _step(em: EnemyManager, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		em._physics_process(DT)
		t += DT


func _attack_index(boss_id: String, atk_name: String) -> int:
	var attacks: Array = Registry.enemy(boss_id).boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == atk_name:
			return k
	return -1


# ---------------------------------------------------------------- the roll (items 16 and 24)

func test_the_roll_runs_its_whole_duration_at_the_attacks_speed() -> void:
	# the hero far down +X: the first attack (the roll) heads that way
	var g := _fake_game(Vector3(60, 0, 0))
	var em := _manager(g)
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	assert_int(b).is_greater_equal(0)
	assert_int(em.boss_index).is_equal(b)
	em.atk_t[b] = 0.0
	var t := 0.0
	while t < 3.0 and em.state[b] != EnemyManager.STATE_CHARGE:
		em._physics_process(DT)
		t += DT
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_CHARGE)
	var x0: float = em.pos[b].x
	# pass 48: the pace knob (Red Canyon's 0.8) runs the roll at 0.8 of its speed for 1/0.8 as long: the same 14.4 m in
	# 1.5 s; the seconds below are the pace-free ones over the pace
	var pc := Run.move_pace()
	# 1.0 s in it is still rolling (the second clock in _steer used to end it at 0.6 s)
	_step(em, 1.0 / pc)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_CHARGE)
	# and it ends at its `duration`, 1.2 s
	var rolled := 1.0 / pc
	while rolled < 1.4 / pc and em.state[b] == EnemyManager.STATE_CHARGE:
		em._physics_process(DT)
		rolled += DT
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(rolled).is_between(1.15 / pc, 1.3 / pc)
	# 12 m/s x 1.2 s = 14.4 m, at the attack's speed on every tick (it averaged 9 and 12 before), whatever the pace
	assert_float(em.pos[b].x - x0).is_between(12.9, 15.9)
	# the end came through the runner: the cooldown is set and the contact damage is the boss's own again
	assert_float(em.atk_t[b]).is_between(1.9, 2.0)
	assert_float(em.dmg[b]).is_equal_approx(Registry.enemy("tumbleweed_king").damage * em.stage_mult, 0.01)


func test_the_line_telegraph_is_as_long_as_the_attack() -> void:
	var g := _fake_game(Vector3(60, 0, 0))
	var em := _manager(g)
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	em.state[b] = EnemyManager.STATE_MOVE
	em.atk_t[b] = 0.0
	em._update_attacks(b, DT, g.player.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int(g.lines.size()).is_equal(1)
	# the King's roll: speed x duration + his radius (it was 22 m for every line)
	assert_float(float(g.lines[0])).is_equal_approx(12.0 * 1.2 + em.radius[b], 0.01)
	# the Brander's brand is drawn at its `length`
	var g2 := _fake_game(Vector3(60, 0, 0))
	var em2 := _manager(g2)
	var b2 := em2.spawn("brander", Vector3.ZERO)
	em2.state[b2] = EnemyManager.STATE_MOVE
	em2.atk_t[b2] = 0.0
	em2._update_attacks(b2, DT, g2.player.global_position)
	assert_int(em2.state[b2]).is_equal(EnemyManager.STATE_ATTACK)
	assert_int(g2.lines.size()).is_equal(1)
	assert_float(float(g2.lines[0])).is_equal_approx(16.0, 0.01)


func test_a_plain_charger_keeps_its_own_clock() -> void:
	# the beetle's charge is not scripted: _steer still runs its timer and its charge.speed
	var g := _fake_game(Vector3(60, 0, 0))
	var em := _manager(g)
	var i := em.spawn("bull_beetle", Vector3.ZERO)
	var def: EnemyDef = Registry.enemy("bull_beetle")
	assert_bool(def.charge.size() > 0).is_true()
	em.state[i] = EnemyManager.STATE_CHARGE
	em.charge_dir[i] = Vector3(1, 0, 0)
	em.timer[i] = 0.5
	_step(em, 0.3)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_CHARGE)
	_step(em, 0.4)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_MOVE)


func test_a_brand_line_knows_its_owner() -> void:
	var attacks: Array = Registry.enemy("brander").boss.get("attacks", [])
	var brands := 0
	for a in attacks:
		if str((a as Dictionary).get("name", "")) == "brand":
			brands += 1
	assert_int(brands).is_greater_equal(1)
	# Game.hell_line takes the owner as its ninth argument (defaulted, so the old calls stand)
	var game_script: GDScript = load("res://game/Game.gd")
	var found := false
	for m in game_script.get_script_method_list():
		if str(m["name"]) == "hell_line":
			found = true
			assert_int((m["args"] as Array).size()).is_equal(9)
			assert_str(str((m["args"] as Array)[8]["name"])).is_equal("owner_i")
	assert_bool(found).is_true()


# ---------------------------------------------------------------- the King (items 14 and 15)

func test_the_bosses_have_their_new_health() -> void:
	assert_float(Registry.enemy("tumbleweed_king").hp).is_equal_approx(1440.0, 0.001)
	assert_float(Registry.enemy("gila_grande").hp).is_equal_approx(2400.0, 0.001)
	assert_float(Registry.enemy("brander").hp).is_equal_approx(5440.0, 0.001)


func test_the_king_has_a_volley_and_a_ring_of_minions() -> void:
	var attacks: Array = Registry.enemy("tumbleweed_king").boss.get("attacks", [])
	var names: Array = []
	var volley: Dictionary = {}
	var ring: Dictionary = {}
	for a in attacks:
		names.append(str((a as Dictionary).get("name", "")))
		if str((a as Dictionary).get("name", "")) == "tumbleweed_volley":
			volley = a
		elif str((a as Dictionary).get("name", "")) == "spawn_ring":
			ring = a
	assert_array(names).contains(["roll", "tumbleweed_volley", "spawn_ring", "slam"])
	assert_str(str(volley.get("telegraph", ""))).is_equal("spokes")
	assert_int(int(volley.get("count", 0))).is_greater_equal(10)
	assert_float(float(volley.get("lift", 0.0))).is_greater(0.0)
	assert_float(float(volley.get("knockback", 0.0))).is_greater_equal(14.0)
	# the reach: across the screen, whether the hero is near or not
	assert_float(float(volley.get("speed", 0.0)) * float(volley.get("life", 0.0))).is_greater_equal(22.0)
	assert_str(str(ring.get("enemy", ""))).is_equal("tumbleweed_minion")
	assert_str(Registry.enemy("tumbleweed_king").doc).contains("tumbleweed")


func test_the_minion_is_a_goblin_on_twig_legs() -> void:
	var m: EnemyDef = Registry.enemy("tumbleweed_minion")
	assert_object(m).is_not_null()
	var gob: EnemyDef = Registry.enemy("goblin")
	assert_str(m.archetype).is_equal("walker")
	assert_str(m.brain).is_equal("chase")
	assert_float(m.speed).is_equal_approx(2.0, 0.001)
	assert_float(m.hp).is_equal_approx(gob.hp, 0.001)
	assert_float(m.cap_share).is_equal_approx(0.5, 0.001)
	# the ring spawns them like any registered creature
	var g := _fake_game(Vector3(60, 0, 0))
	var em := _manager(g)
	em.spawn_ring("tumbleweed_minion", 12, Vector3.ZERO, 5.0)
	assert_int(em.alive_of("tumbleweed_minion")).is_equal(12)


func test_the_volley_draws_spokes_then_rolls_the_tumbleweeds() -> void:
	var g := _fake_game(Vector3(20, 0, 0))
	var em := _manager(g)
	var b := em.spawn("tumbleweed_king", Vector3.ZERO)
	var vi := _attack_index("tumbleweed_king", "tumbleweed_volley")
	assert_int(vi).is_greater_equal(0)
	var row: Dictionary = (Registry.enemy("tumbleweed_king").boss["attacks"] as Array)[vi]
	em.state[b] = EnemyManager.STATE_MOVE
	em.atk_i[b] = vi
	em.atk_t[b] = 0.0
	em._update_attacks(b, DT, g.player.global_position)
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_ATTACK)
	# one red line per tumbleweed, as long as it rolls (pass 47: they were 5 m against a 25 m roll)
	assert_int(g.lines.size()).is_equal(int(row["count"]))
	for l in g.lines:
		assert_float(float(l)).is_equal_approx(EnemyManager.volley_reach(row), 0.01)
	assert_float(EnemyManager.volley_reach(row)).is_greater_equal(float(row["speed"]) * float(row["life"]))
	# the first spoke's direction is kept for the shots
	var first: Vector3 = em.charge_dir[b]
	assert_float(first.length()).is_equal_approx(1.0, 0.01)
	var t := 0.0
	while t < 2.0 and g.volleys.is_empty():
		em._update_attacks(b, DT, g.player.global_position)
		t += DT
	assert_int(g.volleys.size()).is_equal(1)
	var v: Dictionary = g.volleys[0]
	assert_int(int(v["count"])).is_equal(int(row["count"]))
	assert_float(float(v["speed"])).is_equal_approx(float(row["speed"]), 0.001)
	assert_float(float(v["life"])).is_equal_approx(float(row["life"]), 0.001)
	assert_float(float(v["lift"])).is_equal_approx(float(row["lift"]), 0.001)
	assert_float(float(v["knockback"])).is_equal_approx(float(row["knockback"]), 0.001)
	assert_float(float(v["damage"])).is_equal_approx(float(row["damage"]) * em.stage_mult * em.level_dmg_mult, 0.001)
	assert_float((v["first"] as Vector3).distance_to(first)).is_less(0.001)
	assert_str(str((v["info"] as Dictionary).get("kind", ""))).is_equal("boss")
	assert_int(em.state[b]).is_equal(EnemyManager.STATE_MOVE)
	assert_float(em.atk_t[b]).is_equal_approx(2.0, 0.001)


func test_a_rolling_shot_is_wide_and_turns_like_a_wheel() -> void:
	var g := _fake_game(Vector3(50, 0, 0))
	var pm := _pm(g)
	var i := pm.hostile_shot(0, Vector3(0, 0.55, 0), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false,
		{"shot": "tumbleweed", "roll": 0.55, "hit_radius": 0.6, "knockback": 14.0, "lift": 2.5, "info": {}})
	var j := pm.hostile_shot(0, Vector3(0, 0.55, 4), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false, {"shot": "pellet", "info": {}})
	assert_float(pm.radius[i]).is_equal_approx(0.6, 0.001)
	assert_float(pm.radius[j]).is_equal_approx(0.35, 0.001)
	var s0: float = pm.spin[i]
	var s1: float = pm.spin[j]
	pm._physics_process(0.1)
	# v / r a second on the creatures' clock; a plain hostile shot never spins
	assert_float(pm.spin[i] - s0).is_equal_approx(9.0 / 0.55 * 0.1, 0.05)
	assert_float(pm.spin[j]).is_equal_approx(s1, 0.0001)
	assert_int(pm.alive[i]).is_equal(1)
	# it rolls on the sand for its life, then stops (no blast: splash 0)
	var t := 0.1
	while t < 4.0 and pm.alive[i] == 1:
		pm._physics_process(DT)
		t += DT
	assert_int(pm.alive[i]).is_equal(0)
	assert_float(t).is_between(2.5, 2.8)


func test_a_tumbleweed_throws_the_hero_past_the_shove() -> void:
	var g := _fake_game(Vector3(1.5, 0, 0))
	var hero = g.player
	var pm := _pm(g)
	var i := pm.hostile_shot(0, Vector3(0, 0.55, 0), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false,
		{"shot": "tumbleweed", "roll": 0.55, "hit_radius": 0.6, "knockback": 14.0, "lift": 2.5, "info": {"by": "The Tumbleweed King", "kind": "boss"}})
	var t := 0.0
	while t < 2.0 and pm.alive[i] == 1:
		pm._physics_process(DT)
		t += DT
	assert_int(pm.alive[i]).is_equal(0)
	assert_int(hero.hits).is_equal(1)
	assert_int(hero.blasts.size()).is_equal(1)
	assert_int(hero.shoves).is_equal(0)
	var bl: Dictionary = hero.blasts[0]
	assert_float(float(bl["up"])).is_equal_approx(2.5, 0.001)
	assert_float((bl["v"] as Vector3).length()).is_equal_approx(14.0, 0.01)
	assert_float((bl["v"] as Vector3).x).is_greater(13.0)
	# a shot without `lift` still shoves
	var k := pm.hostile_shot(0, Vector3(0, 0.55, 0), Vector3(9, 0, 0), 5.0, 0.0, 2.6, false, {"shot": "pellet", "knockback": 4.0, "info": {}})
	t = 0.0
	while t < 2.0 and pm.alive[k] == 1:
		pm._physics_process(DT)
		t += DT
	assert_int(hero.shoves).is_equal(1)
	assert_int(hero.blasts.size()).is_equal(1)
	# an evaded tumbleweed leaves him standing
	hero.last_outcome = "evaded"
	var e := pm.hostile_shot(0, Vector3(0, 0.55, 0), Vector3(9, 0, 0), 14.0, 0.0, 2.6, false,
		{"shot": "tumbleweed", "roll": 0.55, "hit_radius": 0.6, "knockback": 14.0, "lift": 2.5, "info": {}})
	t = 0.0
	while t < 2.0 and pm.alive[e] == 1:
		pm._physics_process(DT)
		t += DT
	assert_int(pm.alive[e]).is_equal(0)
	assert_int(hero.blasts.size()).is_equal(1)
	assert_int(hero.shoves).is_equal(1)


func test_the_volley_sound_exists() -> void:
	assert_bool(Registry.soundmap.entry("en_king_volley").is_empty()).is_false()
	assert_bool(Registry.soundmap.entry("w_tumble_hit").is_empty()).is_false()


# ---------------------------------------------------------------- the specials and the giant (items 25 and 23)

func test_the_specials_have_fifty_health_and_no_armour() -> void:
	var r: EnemyDef = Registry.enemy("rocketeer")
	var h: EnemyDef = Registry.enemy("harpoon_troglodyte")
	# pass 48: the rocketeer (the Vulture Raider) has 30% less, 35; the harpooner keeps 50
	assert_float(r.hp).is_equal_approx(35.0, 0.001)
	assert_float(h.hp).is_equal_approx(50.0, 0.001)
	assert_float(h.damage_reduction).is_equal_approx(0.0, 0.001)
	assert_float(r.damage_reduction).is_equal_approx(0.0, 0.001)


func test_the_giants_drops_are_rarer() -> void:
	var gi: EnemyDef = Registry.enemy("hammer_giant")
	assert_float(float(gi.drops.get("chest", 0.0))).is_equal_approx(0.08, 0.0001)
	assert_float(float((gi.drops.get("pickup", {}) as Dictionary).get("chance", 0.0))).is_equal_approx(0.12, 0.0001)


# ---------------------------------------------------------------- the hellhound's facing (item 22)

func test_hellhound_front_painting_faces_left() -> void:
	var h: EnemyDef = Registry.enemy("hellhound")
	assert_str(h.front_faces).is_equal("left")
	assert_str(h.back_faces).is_equal("right")
	assert_str(Registry.enemy("goblin").front_faces).is_equal("right")
	assert_str(Registry.enemy("goblin").back_faces).is_equal("right")


func test_face_fix_codes() -> void:
	assert_int(EnemyManager._face_fix("right")).is_equal(0)
	assert_int(EnemyManager._face_fix("left")).is_equal(1)
	assert_int(EnemyManager._face_fix("straight")).is_equal(2)
	assert_int(EnemyManager._face_fix("")).is_equal(0)


func test_json_reads_front_faces() -> void:
	var d: EnemyDef = JsonContent.build("enemies", {"id": "x", "front_faces": "straight"}, "res://content/enemies/hellhound/")
	assert_str(d.front_faces).is_equal("straight")
	assert_str(d.back_faces).is_equal("right")
	var e: EnemyDef = JsonContent.build("enemies", {"id": "y", "back_faces": "left"}, "res://content/enemies/hellhound/")
	assert_str(e.front_faces).is_equal("right")
	assert_str(e.back_faces).is_equal("left")


func test_the_render_inverts_the_mirror_for_a_left_facing_front() -> void:
	# (the headless Dummy renderer drops MultiMesh instance data, so the bit is read off the function _render calls)
	var g := _fake_game(Vector3(60, 0, 0))
	var em := _manager(g)
	var h := em.spawn("hellhound", Vector3.ZERO)
	var gb := em.spawn("goblin", Vector3(3, 0, 0))
	var th: int = em.type_idx[h]
	var tg: int = em.type_idx[gb]
	# the table: the hound's front set inverted, its back set plain; the goblin plain both ways
	assert_int(em._t_face_fix[th * 2]).is_equal(1)
	assert_int(em._t_face_fix[th * 2 + 1]).is_equal(0)
	assert_int(em._t_face_fix[tg * 2]).is_equal(0)
	assert_int(em._t_face_fix[tg * 2 + 1]).is_equal(0)
	# both freshly spawned: idle, the front set
	var front: int = em._strip_of(h, th)
	assert_int(front).is_equal(EnemyManager.A_IDLE)
	# heading right (flip 0): the hound's front is painted facing left, so it shows mirrored; the goblin as painted
	assert_float(em._face_bit(0, th, front)).is_equal_approx(1.0, 0.001)
	assert_float(em._face_bit(0, tg, front)).is_equal_approx(0.0, 0.001)
	# heading left (flip 1): the hound as painted, the goblin mirrored
	assert_float(em._face_bit(1, th, front)).is_equal_approx(0.0, 0.001)
	assert_float(em._face_bit(1, tg, front)).is_equal_approx(1.0, 0.001)
	# the same for every strip of the front set (run, attack, hit, die are all cut from the front painting)
	for strip in [EnemyManager.A_RUN, EnemyManager.A_ATTACK, EnemyManager.A_HIT, EnemyManager.A_DIE]:
		assert_float(em._face_bit(0, th, strip)).is_equal_approx(1.0, 0.001)
	# walking away shows the back set, which keeps the plain rule (the hound's back cycle is straight on)
	em.away[h] = 1
	var back: int = em._strip_of(h, th)
	assert_int(back).is_equal(6)
	assert_float(em._face_bit(0, th, back)).is_equal_approx(0.0, 0.001)
	assert_float(em._face_bit(1, th, back)).is_equal_approx(1.0, 0.001)
	# a "straight" painting is never mirrored
	em._t_face_fix[tg * 2] = 2
	assert_float(em._face_bit(1, tg, front)).is_equal_approx(0.0, 0.001)
	# and _render runs over them without complaint
	em._render()
