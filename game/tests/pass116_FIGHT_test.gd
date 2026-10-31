extends GdUnitTestSuite

## Pass 116, lane FIGHT (Garry: Monks "Double the Range that they shoot at ... Double the range of projectiles as well";
## the Bull Beetle's charge starts 20% further, the Scorpion Elite's at the Beetle's +10%; the Gila "a red circle warning
## for at least 3 seconds" before she pops out; May's Invisible Box "functions like the Shield Power-up").

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
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
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
var max_hp := 100.0
var hits := 0
var shield_t := 0.0
var box_t := 0.0
var box_hits := 0
var box_hit_from := Vector3.ZERO
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	hits += 1
func shove(_v: Vector3, _c := true) -> bool:
	return true
func apply_knockback(_v: Vector3, _h := true) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0, _h := true) -> void:
	pass
func knock_immune() -> bool:
	return false
func trampoline_launch(_d: Vector3, _h: float, _di: float, _a: float, _c: float) -> bool:
	return true
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
"""

const FAKE_FX := """extends Node
func pop_dust(_a, _b) -> void:
	pass
func dig_ring(_a, _b) -> void:
	pass
func dig_spray(_a, _b, _k = 0.0) -> void:
	pass
func emerge_dust(_a, _b, _c = false) -> void:
	pass
func sand(_a, _b = 1.0) -> void:
	pass
func burst(_a, _b, _c = 1.0, _d = 1.0) -> void:
	pass
func hit(_a, _b) -> void:
	pass
"""

const FAKE_TG := """extends Node
var held: Dictionary = {}
var released: Array = []
var next := 1
func hold_disc(at, r, c) -> int:
	next += 1
	held[next] = {"at": at, "r": float(r), "kind": "disc", "a": float(c.a)}
	return next
func hold_ring(at, r, c) -> int:
	next += 1
	held[next] = {"at": at, "r": float(r), "kind": "ring", "a": float(c.a)}
	return next
func move_held(id, at, r = -1.0) -> void:
	if held.has(id):
		held[id]["at"] = at
		if r > 0.0:
			held[id]["r"] = float(r)
func set_alpha(id, a) -> void:
	if held.has(id):
		held[id]["a"] = float(a)
func release(id) -> void:
	if held.has(id):
		held.erase(id)
		released.append(id)
func flash_ring(_a, _b, _c, _d = 0.35, _e = 0.0) -> void:
	pass
func ring(_a, _b, _c, _d, _e = false, _f = 0.0) -> void:
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


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("may"), Registry.map("red_canyon"))
	Run.arena = false


func after_test() -> void:
	Run.arena = false
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _world(hero_at := Vector3.ZERO) -> Dictionary:
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
	return {"g": g, "hero": hero, "em": em, "tg": t}


# ---------------------------------------------------------------- 1. Monks

func test_the_monks_stand_and_shoot_from_twice_as_far() -> void:
	var sq: Dictionary = _json("res://content/enemies/monk/monk.json")["squad"]
	# pass 115's band 4..6 m (edge distance) x2, the spheres' 26.25 m x2
	assert_float(float(sq["keep_distance"])).is_equal_approx(8.0, 0.0001)
	assert_float(float(sq["range"])).is_equal_approx(12.0, 0.0001)
	assert_float(float(sq["orb"]["range"])).is_equal_approx(52.5, 0.0001)
	# the game reads the same numbers
	var d: EnemyDef = Registry.enemy("monk")
	assert_float(float(d.squad["range"])).is_equal_approx(12.0, 0.0001)
	assert_float(float(d.squad["orb"]["range"])).is_equal_approx(52.5, 0.0001)


# ---------------------------------------------------------------- 2. charges

func test_the_beetle_charges_from_a_fifth_further_and_the_scorpion_elite_a_tenth_past_it() -> void:
	var beetle := float(_json("res://content/enemies/bull_beetle/bull_beetle.json")["charge"]["trigger_range"])
	var scorp := float(_json("res://content/enemies/dune_scorpion/dune_scorpion.json")["charge"]["trigger_range"])
	assert_float(beetle).is_equal_approx(7.5 * 1.2, 0.0001)
	assert_float(scorp).is_equal_approx(beetle * 1.1, 0.0001)
	assert_float(float(Registry.enemy("bull_beetle").charge["trigger_range"])).is_equal_approx(beetle, 0.0001)
	assert_float(float(Registry.enemy("dune_scorpion").charge["trigger_range"])).is_equal_approx(scorp, 0.0001)


# ---------------------------------------------------------------- 3. the Gila's warning

func _gila_burrow() -> Dictionary:
	for a in Registry.enemy("gila_grande").boss.get("attacks", []):
		if str((a as Dictionary).get("name", "")) == "burrow":
			return a
	return {}


func _burrow_index() -> int:
	var attacks: Array = Registry.enemy("gila_grande").boss.get("attacks", [])
	for k in range(attacks.size()):
		if str((attacks[k] as Dictionary).get("name", "")) == "burrow":
			return k
	return -1


func test_the_gila_shows_a_filling_red_circle_for_three_seconds_where_she_will_come_up() -> void:
	var atk := _gila_burrow()
	assert_float(float(atk["warn"])).is_greater_equal(3.0)
	var w := _world(Vector3(0, 0, 8))
	var em: EnemyManager = w["em"]
	var hero: Node3D = w["hero"]
	var tg: Node = w["tg"]
	var i := em.spawn("gila_grande", Vector3.ZERO)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	em.hold_t[i] = 0.0
	em.atk_i[i] = _burrow_index()
	em.atk_t[i] = 0.0
	em._update_attacks(i, DT, hero.global_position)
	assert_int(em.state[i]).is_equal(EnemyManager.STATE_ATTACK)
	hero.velocity = Vector3(4.0, 0, 0)
	var t := 0.0
	var warn_at := -1.0
	var spot := Vector3.ZERO
	var r_mid := -1.0
	while em.state[i] == EnemyManager.STATE_ATTACK and t < 12.0:
		hero.global_position += hero.velocity * DT
		em._physics_process(DT)
		t += DT
		if warn_at < 0.0 and em.warn_shown > 0:
			warn_at = t
			spot = em.atk_target[i]
			# locked where he will be `predict` s on, from the warning's start
			var want: Vector3 = hero.global_position + hero.velocity * float(atk["predict"])
			assert_float(Vector2(spot.x - want.x, spot.z - want.z).length()).is_less(0.2)
			# the ring is the real hit's radius; the disc starts tiny
			var ring_r := -1.0
			for id in tg.held:
				if tg.held[id]["kind"] == "ring":
					ring_r = float(tg.held[id]["r"])
			assert_float(ring_r).is_equal_approx(float(atk["radius"]), 0.001)
		if warn_at > 0.0 and r_mid < 0.0 and t - warn_at > 1.5:
			for id in tg.held:
				if tg.held[id]["kind"] == "disc":
					r_mid = float(tg.held[id]["r"])
			# the spot does not follow him
			assert_float((em.atk_target[i] - spot).length()).is_less(0.001)
	assert_float(warn_at).is_greater(0.0)
	var shown := t - warn_at
	# at least 3 s of warning (warn / pace: longer at Red Canyon's slower pace)
	assert_float(shown).is_greater_equal(3.0)
	assert_float(shown).is_equal_approx(float(atk["warn"]) / em.pace, 0.05)
	# the disc was filling toward the ring and everything is off the ground once she is up
	assert_float(r_mid).is_between(0.2 * float(atk["radius"]), 0.8 * float(atk["radius"]))
	assert_int(tg.held.size()).is_equal(0)
	assert_int(tg.released.size()).is_equal(2)
	# she came up on the locked spot
	assert_float(Vector2(em.pos[i].x - spot.x, em.pos[i].z - spot.z).length()).is_less(0.01)


func test_a_dropped_burrow_takes_its_warning_away() -> void:
	var w := _world(Vector3(0, 0, 8))
	var em: EnemyManager = w["em"]
	var tg: Node = w["tg"]
	var i := em.spawn("gila_grande", Vector3.ZERO)
	em.state[i] = EnemyManager.STATE_MOVE
	em.rise_t[i] = 1.0
	em.rise_v[i] = 0.0
	em.atk_i[i] = _burrow_index()
	em.atk_t[i] = 0.0
	em._update_attacks(i, DT, (w["hero"] as Node3D).global_position)
	var t := 0.0
	while em.warn_shown == 0 and t < 12.0:
		em._physics_process(DT)
		t += DT
	assert_int(tg.held.size()).is_equal(2)
	em.alive[i] = 0
	em._physics_process(DT)
	assert_int(tg.held.size()).is_equal(0)


# ---------------------------------------------------------------- 4. May's Invisible Box

func test_the_invisible_box_is_mays_and_its_card_text_comes_from_its_numbers() -> void:
	var def: PerkDef = Registry.perk("invisible_box")
	assert_object(def).is_not_null()
	assert_str(def.hero).is_equal("may")
	assert_str(def.special).is_equal("box")
	var txt := TextGen.perk_text(def)
	assert_str(txt).contains("Every %d s" % int(def.params["every"]))
	assert_str(txt).contains("%d s" % int(def.params["seconds"]))
	assert_str(txt).contains("Shield")


func test_the_box_rises_on_its_clock_blocks_hits_and_folds_away() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	Run.perks.append("invisible_box")
	var def: PerkDef = Registry.perk("invisible_box")
	var box: MimeBox = MimeBox.new()
	w["g"].add_child(box)
	box.setup(w["g"])
	var t := 0.0
	while box.shown == 0 and t < 30.0:
		box.tick(DT)
		t += DT
	assert_float(t).is_equal_approx(float(def.params["first"]), 0.05)
	assert_float(float(hero.box_t)).is_greater(0.0)
	# a blocked hit on the Player shows on the box
	hero.box_hits += 1
	hero.box_hit_from = Vector3(3, 0, 0)
	box.tick(DT)
	assert_int(box.hits_blocked).is_equal(1)
	assert_float(box.flash).is_greater(0.5)
	var up := 0.0
	while box.is_up() and up < 10.0:
		box.tick(DT)
		up += DT
	assert_float(up).is_equal_approx(Run.buff_seconds(float(def.params["seconds"])), 0.05)
	assert_float(float(hero.box_t)).is_equal(0.0)
	# then the clock starts again from `every`
	assert_float(box.clock).is_equal_approx(float(def.params["every"]), 0.001)


func test_with_the_shield_up_the_box_stands_round_the_bubble_and_draws_after_it() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	Run.perks.append("invisible_box")
	var box: MimeBox = MimeBox.new()
	w["g"].add_child(box)
	box.setup(w["g"])
	var plain := box.box_size()
	hero.shield_t = 5.0
	var round_bubble := box.box_size()
	assert_float(round_bubble.x * 0.5).is_greater(MimeBox.BUBBLE_R)
	assert_float(round_bubble.y).is_greater(MimeBox.BUBBLE_Y + MimeBox.BUBBLE_R)
	assert_float(round_bubble.x).is_greater_equal(plain.x)
	assert_int(MimeBox.PRIORITY).is_greater(0)


func test_the_player_takes_no_damage_inside_the_box() -> void:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Run.character)
	p.hp = p.max_hp
	p.box_t = 2.0
	p.take_damage(30.0, Vector3(2, 0, 0), {"by": "Goblin", "kind": "melee"})
	assert_float(p.hp).is_equal(p.max_hp)
	assert_str(p.last_outcome).is_equal("shield")
	assert_int(p.box_hits).is_equal(1)
	assert_bool(p.knock_immune()).is_true()
	p.box_t = 0.0
	p.take_damage(30.0, Vector3(2, 0, 0), {"by": "Goblin", "kind": "melee"})
	assert_float(p.hp).is_less(p.max_hp)
