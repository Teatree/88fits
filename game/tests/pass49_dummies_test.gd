extends GdUnitTestSuite

## Pass 49, lane D (the debug arena, Garry's list): the field of training dummies patrols (left and right round each spot,
## turning at the ends, carrying on from where a shove lands it, the run frames while it walks); attacking dummies are
## added beside it without touching it (a melee one chases and bites, a ranged one spits like the Spit Cactus), each on a
## spot of its own, and the first turns god mode off; the Elite dummy (a crown) and the Boss dummy (a skull drawn at a
## boss's size) stand apart from the field, are big game, take their behaviour and health from the settings at once, pay
## nothing and stand up again after five seconds; a death in the arena respawns the hero at once without Down!, a blast
## or anything spent, and "Go down" asks for the real fall; the ITEMS tab stacks each weapon's mutations and evolution
## under it; the new settings round-trip and step.

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
var rings: Array = []
var lines: Array = []
var spits: Array = []
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
func telegraph_line(_a, _b, c, d, _e) -> void:
	lines.append({"length": float(c), "dur": float(d)})
func telegraph_ring(at, b, c, _d, _e = true) -> void:
	rings.append({"at": at, "r": float(b), "dur": float(c)})
func telegraph_sector(_a, _b, _c, _d, _e, _f) -> void:
	pass
func enemy_spit(_from, to, _speed, damage, splash, info = {}) -> void:
	spits.append({"to": to, "damage": float(damage), "splash": float(splash), "info": info})
func enemy_shot_straight(_a, _b, _c, _d, _e, _f = {}) -> void:
	pass
func on_creature_died_index(_i) -> void:
	pass
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
const KEYS := ["dummy_patrol", "attacker_dummy_hp", "elite_dummy_hp", "boss_dummy_hp", "elite_dummy_mode", "boss_dummy_mode", "dummy_hp", "dummy_count"]

var _keep: Dictionary = {}


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	for k: String in KEYS:
		_keep[k] = Settings.get(k)
	# the settings' own defaults, whatever an earlier run saved
	Settings.dummy_patrol = false
	Settings.attacker_dummy_hp = 0
	Settings.elite_dummy_hp = 2000
	Settings.boss_dummy_hp = 10000
	Settings.elite_dummy_mode = "stand"
	Settings.boss_dummy_mode = "stand"


func after_test() -> void:
	for k: String in _keep.keys():
		Settings.set(k, _keep[k])
	Run.arena = false


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A bare Game with the real crowd (round a fake game that records the telegraphs and the spits), a real hero and Fx.
func _bare_game() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	var em := EnemyManager.new()
	em.game = g
	g.add_child(em)
	g.enemies = em
	var game: Game = auto_free(Game.new())
	game.enemies = em
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	p.setup(Run.character)
	add_child(p)
	p.global_position = Vector3(0, 0, 0)
	game.player = p
	em.player = p
	g.player = p
	var fx: Fx = auto_free(Fx.new())
	add_child(fx)
	game.fx = fx
	em._rebuild_grid()
	return {"game": game, "em": em, "hero": p, "g": g}


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The standing creatures the arena's layout calls `role` ("field", "elite", "boss", "melee", "ranged").
func _role(game: Game, em: EnemyManager, role: String) -> Array:
	var out: Array = []
	for i in range(EnemyManager.MAX):
		if em.is_alive(i) and game.dummy_role(i) == role:
			out.append(i)
	return out


func _ticks(em: EnemyManager, n: int) -> void:
	for k in range(n):
		em._physics_process(DT)


# ---------------------------------------------------------------- the patrol

func test_the_field_patrols_left_and_right_and_turns_at_the_ends() -> void:
	Settings.dummy_patrol = true
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	game.arena_dummies(10, 0)
	var field := _role(game, em, "field")
	assert_int(field.size()).is_equal(10)
	var i: int = field[0]
	assert_int(em.dummy_mode[i]).is_equal(EnemyManager.DUMMY_PATROL)
	# the first row sets off east, the second west
	assert_float(em.patrol_dir[i]).is_equal(1.0)
	assert_float(em.patrol_dir[field[5]]).is_equal(-1.0)
	var home: Vector3 = em.home[i]
	var lo := 0.0
	var hi := 0.0
	var ran := false
	for k in range(720):
		em._physics_process(DT)
		lo = minf(lo, em.pos[i].x - home.x)
		hi = maxf(hi, em.pos[i].x - home.x)
		assert_float(absf(em.pos[i].z - home.z)).is_less(0.3)
		if em._strip_of(i, em.type_idx[i]) == EnemyManager.A_RUN:
			ran = true
	# about two metres either side, and back again: it turned at both ends
	assert_float(hi).is_between(1.6, 2.4)
	assert_float(lo).is_between(-2.4, -1.6)
	assert_bool(ran).is_true()
	# shoved three metres north, it carries on from there and comes back onto its line on the way
	em.pos[i] = em.pos[i] + Vector3(0, 0, -3.0)
	var x0: float = em.pos[i].x
	_ticks(em, 360)
	assert_float(absf(em.pos[i].z - home.z)).is_less(0.5)
	assert_float(absf(em.pos[i].x - x0)).is_greater(0.3)
	# the patrol off again: it walks home and stands
	Settings.dummy_patrol = false
	game.apply_dummy_settings()
	assert_int(em.dummy_mode[i]).is_equal(EnemyManager.DUMMY_STAND)
	_ticks(em, 360)
	assert_float(_flat(em.pos[i], home)).is_less(0.5)


# ---------------------------------------------------------------- the attacking dummies

func test_an_added_melee_dummy_chases_and_bites_and_turns_god_mode_off() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	var hero: Player = b["hero"]
	game.arena_dummies(10, 0)
	var field_before: Array = []
	for f: int in _role(game, em, "field"):
		field_before.append(em.pos[f])
	hero.god = true
	var i := game.add_attacker("melee")
	assert_int(i).is_greater_equal(0)
	assert_bool(hero.god).is_false()
	assert_str(game.dummy_role(i)).is_equal("melee")
	assert_int(em.dummy_mode[i]).is_equal(EnemyManager.DUMMY_MELEE)
	assert_float(em.size[i]).is_equal_approx(2.3, 0.01)
	assert_float(em.dmg[i]).is_equal_approx(10.0, 0.01)
	assert_int(em.undying[i]).is_equal(1)
	# the field is as it was: the same dummies on the same spots
	var field_after: Array = []
	for f: int in _role(game, em, "field"):
		field_after.append(em.pos[f])
	assert_array(field_after).is_equal(field_before)
	# its spot is by the hero, on his south side (the field stands north)
	assert_float(_flat(em.home[i], hero.global_position)).is_equal_approx(Game.ATTACKER_RING, 0.3)
	assert_float(em.home[i].z).is_greater(hero.global_position.z)
	# it walks up to him and bites
	var hp0: float = hero.hp
	for k in range(600):
		em._physics_process(DT)
		if hero.hp < hp0:
			break
	assert_float(hero.hp).is_less(hp0)
	assert_float(_flat(em.pos[i], hero.global_position)).is_less(1.5)
	# a second attacker leaves his choice alone once he turned god mode on again
	hero.god = true
	game.add_attacker("melee")
	assert_bool(hero.god).is_true()
	# out of reach of its spot it walks back
	hero.global_position = em.home[i] + Vector3(0, 0, Game.ATTACKER_RING + EnemyManager.DUMMY_CHASE)
	em.pos[i] = em.home[i] + Vector3(0, 0, 3.0)
	_ticks(em, 360)
	assert_float(_flat(em.pos[i], em.home[i])).is_less(0.5)


func test_an_added_ranged_dummy_spits_like_the_cactus() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	var g: Node = b["g"]
	var hero: Player = b["hero"]
	game.arena_dummies(10, 0)
	var i := game.add_attacker("ranged")
	assert_int(i).is_greater_equal(0)
	assert_int(em.dummy_mode[i]).is_equal(EnemyManager.DUMMY_RANGED)
	assert_float(em.dmg[i]).is_equal_approx(8.0, 0.01)
	var cactus: EnemyDef = Registry.enemy("spit_cactus")
	var def: EnemyDef = Registry.enemy("training_dummy_ranged")
	for k in ["range", "cooldown", "projectile_speed", "telegraph", "splash"]:
		assert_float(float(def.ranged.get(k, -1.0))).override_failure_message(k).is_equal(float(cactus.ranged.get(k, -2.0)))
	# the hero in range: a red ring where he stands for the telegraph, then the lob
	em.cooldown[i] = 0.0
	var home: Vector3 = em.home[i]
	for k in range(240):
		em._physics_process(DT)
		if not (g.get("spits") as Array).is_empty():
			break
	var rings: Array = g.get("rings")
	var spits: Array = g.get("spits")
	assert_int(rings.size()).is_greater_equal(1)
	assert_float(float(rings[0]["r"])).is_equal_approx(float(def.ranged["splash"]), 0.001)
	assert_float(float(rings[0]["dur"])).is_equal_approx(float(def.ranged["telegraph"]) / Run.move_pace(), 0.001)
	assert_float(_flat(rings[0]["at"], hero.global_position)).is_less(0.1)
	assert_int(spits.size()).is_equal(1)
	assert_float(float(spits[0]["damage"])).is_equal_approx(8.0, 0.001)
	assert_str(str((spits[0]["info"] as Dictionary).get("kind", ""))).is_equal("ranged")
	# it held its spot to do it
	assert_float(_flat(em.pos[i], home)).is_less(0.3)
	# out of its range it does not spit
	hero.global_position = home + Vector3(0, 0, 12.0)
	em.cooldown[i] = 0.0
	spits.clear()
	_ticks(em, 120)
	assert_int((g.get("spits") as Array).size()).is_equal(0)


func test_attackers_take_spots_of_their_own_clear_of_the_field_and_go_on_their_own() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	game.arena_dummies(15, 0)
	var spots: Array = []
	for k in range(6):
		var i := game.add_attacker("melee" if k % 2 == 0 else "ranged")
		assert_int(i).is_greater_equal(0)
		spots.append(em.home[i])
	for a in range(spots.size()):
		for c in range(a + 1, spots.size()):
			assert_float(_flat(spots[a], spots[c])).is_greater_equal(Game.ATTACKER_GAP - 0.01)
	for f: int in _role(game, em, "field") + _role(game, em, "elite") + _role(game, em, "boss"):
		for s: Vector3 in spots:
			var clear: bool = absf(s.z - em.home[f].z) >= Game.ATTACKER_GAP or absf(s.x - em.home[f].x) >= EnemyManager.DUMMY_BEAT + Game.ATTACKER_GAP
			assert_bool(clear).is_true()
	assert_int(game.attackers_standing()).is_equal(6)
	assert_int(game.attackers_standing("melee")).is_equal(3)
	assert_int(game.attackers_on_field()).is_equal(6)
	# a new field leaves them be; REMOVE ATTACKERS takes them and nothing else
	game.arena_dummies(10, 0)
	assert_int(game.attackers_standing()).is_equal(6)
	game.remove_attackers()
	assert_int(game.attackers_standing()).is_equal(0)
	assert_int(game.dummies_standing()).is_equal(10)
	assert_int(game.dummy_index("elite")).is_greater_equal(0)
	assert_int(game.dummy_index("boss")).is_greater_equal(0)
	# the arena's CLEAR takes everything, attackers too
	game.add_attacker("melee")
	em.kill_all(false)
	assert_int(game.attackers_on_field()).is_equal(0)
	game._tick_dummies(6.0)
	assert_int(game.attackers_standing()).is_equal(0)


func test_an_attacker_with_health_falls_and_stands_up_again() -> void:
	Settings.attacker_dummy_hp = 100
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	game.arena_dummies(10, 0)
	var i := game.add_attacker("ranged")
	assert_float(em.max_hp[i]).is_equal_approx(100.0, 0.001)
	assert_int(em.undying[i]).is_equal(0)
	var spot: Vector3 = em.home[i]
	assert_bool(em.damage(i, 500.0, "w49_gun")).is_true()
	assert_int(game.attackers_standing()).is_equal(0)
	game._tick_dummies(4.9)
	assert_int(game.attackers_standing()).is_equal(0)
	game._tick_dummies(0.2)
	assert_int(game.attackers_standing("ranged")).is_equal(1)
	var j: int = _role(game, em, "ranged")[0]
	assert_float(_flat(em.pos[j], spot)).is_less(0.05)
	assert_float(em.hp[j]).is_equal_approx(100.0, 0.001)
	# the setting reaches the one standing at once: undying again
	Settings.attacker_dummy_hp = 0
	game.apply_dummy_settings()
	assert_int(em.undying[j]).is_equal(1)
	assert_float(em.max_hp[j]).is_equal_approx(Registry.enemy("training_dummy_ranged").hp, 0.001)


# ---------------------------------------------------------------- the Elite and the Boss dummy

func test_the_elite_dummy_wears_a_crown_and_the_boss_dummy_a_boss_sized_skull() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	game.arena_dummies(10, 0)
	var e := game.dummy_index("elite")
	var s := game.dummy_index("boss")
	assert_int(e).is_greater_equal(0)
	assert_int(s).is_greater_equal(0)
	assert_str(em.badge_of(e)).is_equal("crown")
	assert_str(em.badge_of(s)).is_equal("skull")
	# Elites both, by their kind: big game for Big Game Hunter, Giant Slayer and the priority aim; never grabbed or bounced;
	# never the run's boss
	for i: int in [e, s]:
		assert_bool(em.is_big_game(i)).is_true()
		assert_bool(em.grabbable(i)).is_false()
		assert_bool(em.bounce(i, 1.0, 0.5)).is_false()
		assert_str(str(em.hit_info(i, "melee").get("role", ""))).is_equal("elite")
	assert_int(em.boss_index).is_equal(-1)
	var field := _role(game, em, "field")
	assert_float(em.size[e]).is_greater(em.size[field[0]])
	assert_float(em.size[s]).is_greater(em.size[e])
	# standing apart: behind the field's back row, the Elite to the left and the Boss to the right, clear of every field
	# dummy (and inside a phone's view, clear of the quick buttons' column on the right)
	var back := 0.0
	for f: int in field:
		back = minf(back, em.pos[f].z)
	for f: int in field:
		assert_float(_flat(em.pos[e], em.pos[f])).is_greater_equal(2.0)
		assert_float(_flat(em.pos[s], em.pos[f])).is_greater_equal(2.0)
	assert_float(em.pos[e].z).is_less_equal(back - Game.DUMMY_BEHIND + 0.01)
	assert_float(em.pos[s].z).is_less_equal(back - Game.DUMMY_BEHIND + 0.01)
	assert_float(em.pos[e].x).is_equal_approx(-Game.DUMMY_SIDE, 0.01)
	assert_float(em.pos[s].x).is_equal_approx(Game.DUMMY_SIDE, 0.01)
	# a bigger field moves them back with its back row
	game.arena_dummies(20, 0)
	var e2 := game.dummy_index("elite")
	assert_float(em.pos[e2].z).is_equal_approx(-Game.DUMMY_AHEAD - 3.0 * Game.DUMMY_GAP - Game.DUMMY_BEHIND, 0.01)
	game.arena_dummies(10, 0)
	e = game.dummy_index("elite")
	s = game.dummy_index("boss")
	# their health from the settings (undying shows the def's health), standing still by default
	assert_float(em.max_hp[e]).is_equal_approx(2000.0, 0.001)
	assert_float(em.max_hp[s]).is_equal_approx(10000.0, 0.001)
	assert_int(em.dummy_mode[e]).is_equal(EnemyManager.DUMMY_STAND)
	# drawn: the skull at the boss's size, the crown at the plain one
	em._render()
	var crown: MultiMesh = em._badges.get("crown")
	var skull: MultiMesh = em._badges.get("skull")
	assert_int(crown.visible_instance_count).is_equal(1)
	assert_int(skull.visible_instance_count).is_equal(1)
	var cs: float = crown.get_instance_custom_data(0).g
	var ss: float = skull.get_instance_custom_data(0).g
	assert_float(ss).is_equal_approx(cs * 1.3, 0.001)


func test_the_elite_and_boss_behaviours_and_health_apply_at_once() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	var hero: Player = b["hero"]
	game.arena_dummies(10, 0)
	var e := game.dummy_index("elite")
	var s := game.dummy_index("boss")
	hero.god = true
	assert_int(game.attackers_on_field()).is_equal(0)
	# melee: chases and bites for 20 (the Boss for 30); god mode goes off with the first attacking dummy
	Settings.elite_dummy_mode = "melee"
	game.apply_dummy_settings()
	assert_int(em.dummy_mode[e]).is_equal(EnemyManager.DUMMY_MELEE)
	assert_float(em.dmg[e]).is_equal_approx(20.0, 0.001)
	assert_bool(hero.god).is_false()
	assert_int(game.attackers_on_field()).is_equal(1)
	Settings.boss_dummy_mode = "melee"
	game.apply_dummy_settings()
	assert_float(em.dmg[s]).is_equal_approx(30.0, 0.001)
	# ranged: spits for 14 (the Boss for 22)
	Settings.elite_dummy_mode = "ranged"
	Settings.boss_dummy_mode = "ranged"
	game.apply_dummy_settings()
	assert_int(em.dummy_mode[e]).is_equal(EnemyManager.DUMMY_RANGED)
	assert_float(em.dmg[e]).is_equal_approx(14.0, 0.001)
	assert_float(em.dmg[s]).is_equal_approx(22.0, 0.001)
	# patrol and stand
	Settings.elite_dummy_mode = "patrol"
	Settings.boss_dummy_mode = "stand"
	game.apply_dummy_settings()
	assert_int(em.dummy_mode[e]).is_equal(EnemyManager.DUMMY_PATROL)
	assert_int(em.dummy_mode[s]).is_equal(EnemyManager.DUMMY_STAND)
	assert_int(game.attackers_on_field()).is_equal(0)
	# the Elite melee by the hero: its touch takes his health
	Settings.elite_dummy_mode = "melee"
	game.apply_dummy_settings()
	hero.god = false
	em.pos[e] = hero.global_position + Vector3(0.5, 0, 0)
	em.state[e] = EnemyManager.STATE_MOVE
	em.contact_cd[e] = 0.0
	var hp0: float = hero.hp
	em._rebuild_grid()
	em._physics_process(DT)
	assert_float(hero.hp).is_less(hp0)
	# a health change reaches the standing one: whole at the new health, undying again at 0
	Settings.elite_dummy_hp = 50000
	game.apply_dummy_settings()
	assert_float(em.max_hp[e]).is_equal_approx(50000.0, 0.001)
	assert_float(em.hp[e]).is_equal_approx(50000.0, 0.001)
	assert_int(em.undying[e]).is_equal(0)
	Settings.elite_dummy_hp = 0
	game.apply_dummy_settings()
	assert_int(em.undying[e]).is_equal(1)
	assert_float(em.max_hp[e]).is_equal_approx(Registry.enemy("training_dummy_elite").hp, 0.001)


func test_the_big_dummies_pay_nothing_and_stand_up_again_after_five_seconds() -> void:
	Settings.elite_dummy_hp = 500
	Settings.boss_dummy_hp = 2000
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	game.camera = auto_free(CameraRig.new())
	game.arena_dummies(10, 0)
	em.enemy_died.connect(game._on_enemy_died)
	for spec in [["elite", 500.0], ["boss", 2000.0]]:
		var role: String = spec[0]
		var i := game.dummy_index(role)
		assert_float(em.max_hp[i]).is_equal_approx(float(spec[1]), 0.001)
		assert_int(em.undying[i]).is_equal(0)
		var spot: Vector3 = em.pos[i]
		var gold0: int = Run.run_gold
		var chests0: int = em.hot_chests
		assert_bool(em.damage(i, 1000000.0, "w49_gun")).is_true()
		# no purse, no boss reward
		assert_int(Run.run_gold).is_equal(gold0)
		assert_int(em.hot_chests).is_equal(chests0)
		assert_int(game.dummy_index(role)).is_equal(-1)
		game._tick_dummies(4.9)
		assert_int(game.dummy_index(role)).is_equal(-1)
		game._tick_dummies(0.2)
		var j := game.dummy_index(role)
		assert_int(j).is_greater_equal(0)
		assert_float(_flat(em.pos[j], spot)).is_less(0.05)
		assert_float(em.hp[j]).is_equal_approx(float(spec[1]), 0.001)


# ---------------------------------------------------------------- dying in the arena

func test_an_arena_death_respawns_at_once_without_down_a_blast_or_a_spent_revive() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var em: EnemyManager = b["em"]
	var hero: Player = b["hero"]
	var map: MapBase = auto_free(MapBase.new())
	map.flats_center = Vector3(3.0, 0.0, -2.0)
	game.map = map
	Run.arena = true
	game.arena_dummies(10, 100)
	hero.died.connect(game._on_player_died)
	Run.debug_set_item("passive", "phoenix_feather", 1)
	var phoenix_before: bool = Run.phoenix_ready()
	hero.global_position = Vector3(1, 0, 1)
	# a dummy right beside him keeps its health: no revive blast
	var f: int = _role(game, em, "field")[0]
	em.pos[f] = hero.global_position + Vector3(1.0, 0, 0)
	var fhp: float = em.hp[f]
	hero.god = false
	hero.invuln = 0.0
	hero.take_damage(hero.hp + 9999.0, hero.global_position + Vector3(1, 0, 0), {"by": "w49", "kind": "melee", "fx": []})
	assert_bool(hero.dead).is_false()
	assert_float(hero.hp).is_equal(hero.max_hp)
	assert_float(hero.invuln).is_greater_equal(Game.ARENA_RESPAWN_INVULN - 0.01)
	assert_float(_flat(hero.global_position, map.player_start())).is_less(0.01)
	assert_int(game.arena_respawns).is_equal(1)
	assert_int(Run.revives_used).is_equal(0)
	assert_bool(Run.phoenix_ready()).is_equal(phoenix_before)
	assert_bool(em.is_alive(f)).is_true()
	assert_float(em.hp[f]).is_equal(fhp)
	# and again: as many times as he likes
	hero.invuln = 0.0
	hero.take_damage(hero.hp + 9999.0, hero.global_position, {"by": "w49", "kind": "melee", "fx": []})
	assert_bool(hero.dead).is_false()
	assert_int(game.arena_respawns).is_equal(2)


func test_go_down_asks_for_the_real_fall() -> void:
	var b := _bare_game()
	var game: Game = b["game"]
	var hero: Player = b["hero"]
	Run.arena = true
	var p: ArenaPanel = auto_free(ArenaPanel.new())
	p.game = game
	assert_bool(game.arena_real_down).is_false()
	# (nothing hears the death here: the real fall's Down! needs the whole game)
	p._go_down()
	assert_bool(hero.dead).is_true()
	assert_bool(game.arena_real_down).is_true()
	assert_int(game.arena_respawns).is_equal(0)


# ---------------------------------------------------------------- the ITEMS tab

func test_the_items_tab_stacks_each_weapons_mutations_and_evolution_under_it() -> void:
	var p: ArenaPanel = auto_free(ArenaPanel.new())
	var secs := p.item_sections()
	var titles: Array = []
	for s in secs:
		titles.append(str(s[0]))
	# pass 73 (lane CARDS): the lines' section says Cards
	assert_array(titles).contains_exactly(["Weapons", "Hidden weapons", "Cards", "Passives", "Perks"])
	# the Peashooter: its path by kind (element, volume, motion), the Drifter's own, its evolution, then what is hidden
	var pea: WeaponDef = Registry.weapon("peashooter")
	var st := p.weapon_stack(pea)
	var ids: Array = []
	var tags: Array = []
	for entry in st:
		ids.append(str((entry[1] as ContentDef).id))
		tags.append(str(entry[2]))
	assert_array(ids).is_equal(["toxic_peas", "big_peas", "bouncing_peas", "fan_the_hammer", "pea_cannon", "pea_hose", "bullet_hose"])
	# pass 51: the hero's own is marked optional, and the EVO toggle counts the three the evolution needs
	assert_array(tags).is_equal(["Element", "Volume", "Motion", Registry.character("drifter").display_name + " · optional", "Evolution", "hidden mutation", "hidden evolution"])
	assert_str(str(st[4][0])).is_equal("evolution")
	assert_str(ArenaPanel.stack_summary(st)).is_equal("3 + EVO")
	# the Revolver's old Golden Revolver is kept hidden at the end of its stack, the new one is its evolution
	var rv := p.weapon_stack(Registry.weapon("revolver"))
	var last: Array = rv[rv.size() - 1]
	assert_str(str((last[1] as ContentDef).id)).is_equal("golden_revolver_v47")
	assert_str(str(last[2])).is_equal("hidden evolution")
	var evo_at := -1
	for k in range(rv.size()):
		if str((rv[k][1] as ContentDef).id) == "golden_revolver":
			evo_at = k
	assert_int(evo_at).is_greater_equal(0)
	assert_str(str(rv[evo_at][2])).is_equal("Evolution")
	# every stack keeps its order: the path by kind, the heroes', the evolutions, the hidden ones
	for s in secs:
		if str(s[1]) != "weapon":
			continue
		for w: WeaponDef in s[2]:
			var rank := -1
			for entry in p.weapon_stack(w):
				var r := 4
				var tag := str(entry[2])
				if tag.begins_with("hidden"):
					r = 7
				elif str(entry[0]) == "evolution":
					r = 6
				elif (entry[1] as MutationDef).is_hero():
					r = 5
				else:
					r = int(Registry.MUTATION_ORDER.get((entry[1] as MutationDef).mutation_kind, 4))
				assert_int(r).override_failure_message("%s: %s out of order" % [w.id, (entry[1] as ContentDef).id]).is_greater_equal(rank)
				rank = r
	# each weapon, evolution and mutation exactly once; the weapons out of play in their own section
	var seen: Dictionary = {}
	for s in secs:
		for d in s[2]:
			var key := "%s/%s" % [str(s[1]), (d as ContentDef).id]
			seen[key] = int(seen.get(key, 0)) + 1
			if str(s[1]) == "weapon":
				for entry in p.weapon_stack(d):
					var k2 := "%s/%s" % [str(entry[0]), (entry[1] as ContentDef).id]
					seen[k2] = int(seen.get(k2, 0)) + 1
	for w: WeaponDef in Registry.weapons.values():
		var wk := "%s/%s" % ["evolution" if w.is_evolution else "weapon", w.id]
		assert_int(int(seen.get(wk, 0))).override_failure_message(wk).is_equal(1)
	for m: MutationDef in Registry.mutations.values():
		assert_int(int(seen.get("mutation/" + m.id, 0))).override_failure_message(m.id).is_equal(1)
	var out_of_play: Array = []
	for d in secs[1][2]:
		out_of_play.append((d as ContentDef).id)
	assert_array(out_of_play).contains(["branding_iron", "poison_dart"])
	for d in secs[0][2]:
		assert_bool(Registry.is_hidden(d)).is_false()


func test_a_weapons_toggle_opens_its_stack_under_it() -> void:
	var p: ArenaPanel = auto_free(ArenaPanel.new())
	add_child(p)
	p._tab = "items"
	p._refresh()
	var row: Control = p._content.find_child("Item_weapon_peashooter", true, false)
	assert_object(row).is_not_null()
	var tg: Button = row.find_child("Stack", true, false)
	assert_object(tg).is_not_null()
	assert_str(tg.text).starts_with("▶")
	assert_object(p._content.find_child("Item_mutation_toxic_peas", true, false)).is_null()
	tg.pressed.emit()
	# drawn again: the stack sits under its weapon, indented, in order
	var kids: Array = p._content.get_children()
	var at := -1
	for k in range(kids.size()):
		if (kids[k] as Node).name == "Item_weapon_peashooter":
			at = k
	assert_int(at).is_greater_equal(0)
	var stack := p.weapon_stack(Registry.weapon("peashooter"))
	for k in range(stack.size()):
		var under: Node = kids[at + 1 + k]
		assert_str(str(under.name)).is_equal("Under_%s_%s" % [str(stack[k][0]), (stack[k][1] as ContentDef).id])
		assert_bool(under is MarginContainer).is_true()
	var tg2: Button = (kids[at] as Node).find_child("Stack", true, false)
	assert_str(tg2.text).starts_with("▼")
	# a stack row's + hands the mutation over
	var mrow: Node = p._content.find_child("Item_mutation_toxic_peas", true, false)
	var plus: Button = null
	for c in mrow.find_children("*", "Button", true, false):
		if (c as Button).text == "+":
			plus = c
	assert_object(plus).is_not_null()
	plus.pressed.emit()
	assert_bool(Run.mutations_held("peashooter").has("toxic_peas")).is_true()
	Run.debug_clear_items()
	# the rows the redraw took out go at the end of the frame
	await get_tree().process_frame


# ---------------------------------------------------------------- the settings

func test_the_new_dummy_settings_round_trip_and_step() -> void:
	Settings.dummy_patrol = true
	Settings.attacker_dummy_hp = 500
	Settings.elite_dummy_hp = 10000
	Settings.elite_dummy_mode = "melee"
	Settings.boss_dummy_hp = 50000
	Settings.boss_dummy_mode = "ranged"
	var d := Settings.to_dict()
	assert_bool(bool(d["dummy_patrol"])).is_true()
	assert_int(int(d["attacker_dummy_hp"])).is_equal(500)
	assert_int(int(d["elite_dummy_hp"])).is_equal(10000)
	assert_str(str(d["elite_dummy_mode"])).is_equal("melee")
	assert_int(int(d["boss_dummy_hp"])).is_equal(50000)
	assert_str(str(d["boss_dummy_mode"])).is_equal("ranged")
	Settings.from_dict({"dummy_patrol": false, "attacker_dummy_hp": -5, "elite_dummy_mode": "dance", "boss_dummy_hp": 200000, "boss_dummy_mode": "patrol"})
	assert_bool(Settings.dummy_patrol).is_false()
	assert_int(Settings.attacker_dummy_hp).is_equal(0)
	assert_str(Settings.elite_dummy_mode).is_equal("stand")
	assert_int(Settings.elite_dummy_hp).is_equal(10000)
	assert_int(Settings.boss_dummy_hp).is_equal(200000)
	assert_str(Settings.boss_dummy_mode).is_equal("patrol")
	assert_str(Settings.next_mode("stand")).is_equal("patrol")
	assert_str(Settings.next_mode("ranged")).is_equal("stand")
	assert_int(Settings.next_step(Settings.BOSS_DUMMY_HP_STEPS, 10000)).is_equal(50000)
	assert_int(Settings.next_step(Settings.ATTACKER_HP_STEPS, 2000)).is_equal(0)
	assert_str(Settings.dummy_hp_label(200000)).is_equal("200,000 HP")
	assert_str(Settings.dummy_hp_label(500)).is_equal("500 HP")
	assert_str(Settings.thousands(2000)).is_equal("2,000")
	assert_str(Settings.thousands(10000)).is_equal("10,000")
	# the defaults Garry asked for
	assert_array(Settings.ELITE_DUMMY_HP_STEPS).is_equal([0, 500, 2000, 10000, 50000])
	assert_array(Settings.BOSS_DUMMY_HP_STEPS).is_equal([0, 2000, 10000, 50000, 200000])
	assert_array(Settings.ATTACKER_HP_STEPS).is_equal([0, 100, 500, 2000])


func test_the_developer_menu_steps_the_new_dummy_rows() -> void:
	var dm: Control = auto_free(load("res://ui/DevMenu.tscn").instantiate())
	add_child(dm)
	await get_tree().process_frame
	var specs := [["DummyPatrol", "dummy_patrol"], ["AttackerHealth", "attacker_dummy_hp"], ["EliteDummyHealth", "elite_dummy_hp"],
		["EliteDummyMode", "elite_dummy_mode"], ["BossDummyHealth", "boss_dummy_hp"], ["BossDummyMode", "boss_dummy_mode"]]
	for spec in specs:
		var row: WTap = dm.find_child(str(spec[0]), true, false)
		assert_object(row).override_failure_message(str(spec[0])).is_not_null()
		var was = Settings.get(str(spec[1]))
		row.pressed.emit()
		var now = Settings.get(str(spec[1]))
		assert_bool(str(now) != str(was)).override_failure_message(str(spec[0])).is_true()
		await get_tree().process_frame
	# the row says what it is now
	var mode_row: Node = dm.find_child("EliteDummyMode", true, false)
	var said := ""
	for n in mode_row.find_children("*", "", true, false):
		if n is WText:
			said += (n as WText).text + " "
	assert_str(said).contains("PATROL")
	assert_bool(Settings.dummy_patrol).is_true()
	assert_int(Settings.attacker_dummy_hp).is_equal(100)
	assert_int(Settings.elite_dummy_hp).is_equal(10000)
	assert_str(Settings.elite_dummy_mode).is_equal("patrol")
	assert_int(Settings.boss_dummy_hp).is_equal(50000)
	assert_str(Settings.boss_dummy_mode).is_equal("patrol")
