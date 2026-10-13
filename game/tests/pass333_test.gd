extends GdUnitTestSuite

## Pass 33.3: badges over the special creatures (a crown on an Elite, a skull on a boss, a gear on the harpooner and the
## rocketeer), the rocketeer reloads whenever his rocket is gone and its blast throws the hero and the crowd, the portal
## keeps a green marker, and skeletons with curved swords took the goblins' place (until pass 33.5 brought the goblins back).

const FAKE_GAME := """extends Node
var player: Node3D
var projectiles = null
var enemies = null
var map = null
var camera = null
var director = null
var portal = null
var paused := false
var rocket_alive := false
var missiles: Array = []
var blasts: Array = []
func rocket_out(_i: int) -> bool:
	return rocket_alive
func enemy_missile(shooter: int, _from: Vector3, _speed: float, _turn: float, _damage: float, _area: float, _soh: float = 0.0, _info: Dictionary = {}, blast: Dictionary = {}) -> void:
	missiles.append({"shooter": shooter, "blast": blast})
	rocket_alive = true
func rocket_blast(at: Vector3, r: float, damage: float, info: Dictionary, blast: Dictionary) -> void:
	blasts.append({"at": at, "r": r, "damage": damage, "info": info, "blast": blast})
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


func _hero() -> Player:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.hp = p.max_hp
	return p


func _step(em: EnemyManager, seconds: float, dt: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		em._physics_process(dt)
		t += dt


# ---------------------------------------------------------------- badges

func test_badges_follow_the_role_and_the_data() -> void:
	assert_str(Registry.enemy("rocketeer").badge_for()).is_equal("gear")
	assert_str(Registry.enemy("harpoon_troglodyte").badge_for()).is_equal("gear")
	assert_str(Registry.enemy("dune_scorpion").badge_for()).is_equal("crown")
	assert_str(Registry.enemy("sun_prophet").badge_for()).is_equal("crown")
	assert_str(Registry.enemy("tumbleweed_king").badge_for()).is_equal("skull")
	assert_str(Registry.enemy("gila_grande").badge_for()).is_equal("skull")
	# only the Elites ever wear a crown (pass 33.6; the Stone Golem joined them in pass 45): no ordinary creature, whatever its data asks for
	var crowned: Array = []
	for d: EnemyDef in Registry.enemies.values():
		if d.badge_for() == "crown":
			crowned.append(d.id)
		# pass 66: the rule, not the list (a creature made in the Level Editor with the elite archetype wears one too): a
		# crown is an Elite's alone, and an Elite wears one unless its JSON names another badge (the Boss dummy's skull)
		assert_bool(d.badge_for() == "crown").override_failure_message(d.id).is_equal(d.archetype == "elite" and (d.badge == "" or d.badge == "crown"))
	# pass 49: and the debug arena's Elite dummy, an Elite by its archetype so the items that care see one
	assert_array(crowned).contains(["dune_scorpion", "sun_prophet", "stone_golem", "training_dummy_elite"])
	var sk: EnemyDef = Registry.enemy("goblin").duplicate()
	assert_str(sk.badge_for()).is_equal("")
	sk.badge = "crown"
	assert_str(sk.badge_for()).is_equal("")
	for kind in ["crown", "skull", "gear"]:
		assert_bool(ResourceLoader.exists("res://art/ui/badges/%s.png" % kind)).override_failure_message("no painting for the " + kind).is_true()


func test_badges_float_over_the_heads_of_the_ones_that_wear_them() -> void:
	var g := _fake_game(Vector3.ZERO)
	var em := _manager(g)
	var elite: EliteModDef = Registry.elites.get("shielded")
	var crowned := em.spawn("dune_scorpion", Vector3(2, 0, 0))
	var modded := em.spawn("goblin", Vector3(4, 0, 0), elite)
	var plain := em.spawn("goblin", Vector3(6, 0, 0))
	em.spawn("rocketeer", Vector3(0, 0, -10))
	em._render()
	assert_int((em._badges["crown"] as MultiMesh).visible_instance_count).is_equal(1)
	assert_int((em._badges["gear"] as MultiMesh).visible_instance_count).is_equal(1)
	# which badge each one wears (the Elite a crown; a goblin with an elite modifier nothing, like a plain one), hung
	# past the top of the figure (a headless run keeps no per-instance data to read back, so the height is checked on
	# the data it comes from)
	assert_str(em.badge_of(crowned)).is_equal("crown")
	assert_str(em.badge_of(modded)).is_equal("")
	assert_str(em.badge_of(plain)).is_equal("")
	assert_float(Registry.enemy("dune_scorpion").head).is_greater(0.8)
	# a dying creature drops its badge
	em.damage(crowned, 100000.0)
	em._render()
	assert_int((em._badges["crown"] as MultiMesh).visible_instance_count).is_equal(0)


# ---------------------------------------------------------------- the rocketeer

func test_the_rocketeer_fires_again_once_his_rocket_is_gone() -> void:
	var g := _fake_game(Vector3.ZERO)
	var em := _manager(g)
	var i := em.spawn("rocketeer", Vector3(0, 0, -30))
	assert_int(i).is_greater_equal(0)
	# its first rocket: the spawn, a random first wait and the wind-up at the map's pace (Garry set 0.6 by hand, pass 52)
	var t0 := 0.0
	while g.missiles.is_empty() and t0 < 10.0:
		_step(em, 0.1)
		t0 += 0.1
	assert_int(g.missiles.size()).is_equal(1)
	assert_float(float((g.missiles[0]["blast"] as Dictionary).get("knockback", 0.0))).is_greater(20.0)
	# while his rocket flies he only watches
	_step(em, 6.0)
	assert_int(g.missiles.size()).is_equal(1)
	# the rocket is gone: a reload, a wind-up and the next one
	g.rocket_alive = false
	var reload := float(Registry.enemy("rocketeer").artillery.get("reload", 2.5))
	var windup := float(Registry.enemy("rocketeer").artillery.get("windup", 1.4))
	# the wind-up lasts 1 / pace as long (pass 48)
	_step(em, reload + windup / Run.move_pace() + 0.5)
	assert_int(g.missiles.size()).is_equal(2)


func test_his_rocket_goes_off_through_the_big_blast() -> void:
	var g := _fake_game(Vector3.ZERO)
	var pm := ProjectileManager.new()
	pm.game = g
	g.add_child(pm)
	g.projectiles = pm
	pm.register_kind(BoxMesh.new(), null)
	var blast := {"knockback": 26.0, "lift": 6.5, "throw": 26.0, "throw_radius": 4.5}
	var i := pm.launch_enemy_rocket(0, 7, Vector3(0, 1.0, -4.0), Vector3(0, 0, 1), 4.0, 1.3, 22.0, 1.6, 0.0, {"by": "Rocketeer"}, blast)
	assert_bool(pm.has_rocket_of(7)).is_true()
	var t := 0.0
	while t < 3.0 and g.blasts.is_empty():
		pm._physics_process(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_int(g.blasts.size()).is_equal(1)
	assert_float(float(g.blasts[0]["damage"])).is_equal_approx(22.0, 0.01)
	assert_float(float((g.blasts[0]["blast"] as Dictionary).get("throw", 0.0))).is_equal_approx(26.0, 0.01)
	assert_bool(pm.has_rocket_of(7)).is_false()
	assert_int(pm.alive[i]).is_equal(0)


func test_a_blast_throws_the_hero_past_a_shove() -> void:
	var p := _hero()
	p.blast(Vector3(26.0, 0, 0), 6.5)
	assert_float(p._kb.x).is_greater(20.0)
	assert_float(p.velocity.y).is_equal_approx(6.5, 0.01)
	# nothing stacks on it while he flies
	assert_bool(p.shove(Vector3(10, 0, 0))).is_false()
	# and the hit says what it came to, so an evade can leave him standing
	p.invuln = 1.0
	p.take_damage(5.0, Vector3.ZERO)
	assert_str(p.last_outcome).is_equal("immune")
	p.invuln = 0.0
	p.take_damage(5.0, Vector3.ZERO)
	assert_str(p.last_outcome).is_equal("hit")


func test_a_blast_throws_the_crowd_without_a_scratch() -> void:
	var g := _fake_game(Vector3(50, 0, 50))
	var em := _manager(g)
	var near := em.spawn("goblin", Vector3(1.0, 0, 0))
	var mid := em.spawn("goblin", Vector3(0, 0, 3.0))
	var far := em.spawn("goblin", Vector3(8.0, 0, 0))
	# one size for all three: a throw is divided by the creature's size, and the spawn rolls it (+-20%, a special 1.5x),
	# which made "closer is thrown harder" fail now and then (pass 33.10)
	for i in [near, mid, far]:
		em.size[i] = 1.2
	var hp0 := em.hp[near]
	# the crowd's grid is rebuilt every other frame in a run; here by hand
	em._rebuild_grid()
	var n := em.throw_radius(Vector3.ZERO, 4.5, 26.0)
	assert_int(n).is_equal(2)
	assert_float(em.kb[near].x).is_greater(8.0)
	assert_float(em.kb[mid].z).is_greater(4.0)
	assert_float(em.kb[far].length()).is_equal_approx(0.0, 0.001)
	assert_float(em.hp[near]).is_equal_approx(hp0, 0.001)
	# closer is thrown harder
	assert_float(em.kb[near].length()).is_greater(em.kb[mid].length())


func test_the_explosion_is_never_thinned_for_the_budget() -> void:
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	# a busy pool: past three quarters every ordinary puff is mostly skipped
	fx._n = int(Fx.MAX_P * 0.8)
	for k in range(fx._n):
		fx._life[k] = 99.0
	var before := fx._n
	fx.explosion(Vector3.ZERO, 1.6)
	# the flash, the bloom, the fireball, the sparks and the grit all made it in
	assert_int(fx._n - before).is_greater_equal(1 + 6 + 14 + 18 + 8)


# ---------------------------------------------------------------- the portal

func test_the_portal_keeps_a_green_marker() -> void:
	var g := _fake_game(Vector3(0, 0, 40))
	var em := _manager(g)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 20, 52)
	cam.look_at(Vector3(0, 0, 40))
	g.camera.camera = cam
	var portal: Node3D = auto_free(Node3D.new())
	add_child(portal)
	portal.global_position = Vector3(0, 0, -30)
	g.portal = portal
	# the HUD built first (its setup hooks the real hero's joystick), then pointed at the stand-in game
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	hud.game = g
	hud._tick_arrow()
	assert_int(hud._arrows.size()).is_equal(1)
	assert_str(str(hud._arrows[0]["text"])).starts_with("PORTAL")
	assert_bool((hud._arrows[0]["color"] as Color).is_equal_approx(HUD.PORTAL_GREEN)).is_true()
	# the boss, while it lives, keeps its red one beside it
	var b := em.spawn("tumbleweed_king", Vector3(30, 0, -20))
	assert_int(em.boss_index).is_equal(b)
	hud._tick_arrow()
	assert_int(hud._arrows.size()).is_equal(2)
	assert_str(str(hud._arrows[0]["text"])).starts_with("BOSS")


# ---------------------------------------------------------------- the skeletons

func test_the_goblins_are_back_and_the_skeletons_kept() -> void:
	# pass 33.5 brought the goblins back; pass 45 gave their places to the skeletons for good (SK-A and KN-A in play),
	# and the goblins are now the ones kept, retired
	var m: MapDef = Registry.map("red_canyon")
	var ids: Array = []
	for r in m.timeline.roster:
		ids.append(str(r["enemy"]))
	for ev in m.timeline.events:
		if ev.get("enemy") is String:
			ids.append(str(ev["enemy"]))
	assert_bool(ids.has("skeleton")).is_true()
	assert_bool(ids.has("skeleton_knight")).is_true()
	assert_bool(ids.has("goblin")).is_false()
	# (Garry, 2026-10-13: he put the goblin runt back on his stage-1 roster, row r2, so it is in play again: whichever
	# goblin is on the roster is not retired, pass66_shape_test's rule)
	if ids.has("goblin_runt"):
		assert_bool(Registry.enemy("goblin_runt").retired).override_failure_message("goblin_runt is on the roster yet retired").is_false()
	assert_str(str(m.skins.get("walker", ""))).is_equal("skeleton")
	# the King rings the hero with its minions (pass 45: tumbleweed_minion; goblins from pass 33.5 to 44)
	for a in Registry.enemy("tumbleweed_king").boss.get("attacks", []):
		if str(a.get("name", "")) == "spawn_ring":
			assert_str(str(a.get("enemy", ""))).is_equal("tumbleweed_minion")
	for id in ["goblin", "sand_crab", "jackalope"]:
		assert_bool(Registry.enemy(id).retired).override_failure_message(id + " is not retired").is_true()
	# the runt is kept either way (Garry's roster decides whether it is in play)
	assert_object(Registry.enemy("goblin_runt")).is_not_null()
	for id in ["skeleton", "skeleton_knight"]:
		assert_bool(Registry.enemy(id).retired).override_failure_message(id + " is still retired").is_false()
	# the goblin as it was before the skeletons: pass 33.2's numbers
	var w: EnemyDef = Registry.enemy("skeleton")
	var gob: EnemyDef = Registry.enemy("goblin")
	assert_float(gob.hp).is_equal_approx(6.0, 0.001)
	assert_int(gob.pack_size).is_equal(6)
	assert_float(gob.cap_share).is_equal_approx(0.5, 0.001)
	# the skeleton's health is Garry's to tune (pass 47: he raised it to 10 by hand): no weaker than the goblin it replaced
	assert_float(w.hp).is_greater_equal(gob.hp)
	# the second kind is armoured (pass 33.4: a breastplate and a helm), not quicker
	var r: EnemyDef = Registry.enemy("skeleton_knight")
	assert_float(r.damage_reduction).is_greater_equal(0.2)
	assert_float(r.hp).is_greater(w.hp)
	# they rattle
	assert_str(str(w.sfx.get("die", ""))).is_equal("en_bone_die")
	assert_bool(FileAccess.file_exists("res://content/sounds/placeholder/en_bone_die.wav")).is_true()


func test_skeletons_fall_apart_into_a_heap() -> void:
	# pass 45: in play again as SK-A / KN-A, and they fall over whole instead of dropping apart in slices
	for id in ["skeleton", "skeleton_knight"]:
		var d: EnemyDef = Registry.enemy(id)
		assert_object(d.sprite).override_failure_message(id + " has no painted strip").is_not_null()
		assert_int(d.frames_of("die")).is_greater_equal(5)
		assert_int(d.frames_of("run")).is_greater_equal(8)
