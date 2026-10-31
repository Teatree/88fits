extends GdUnitTestSuite

## Pass 87, lane FIXES: the Dynamite Bandit faces the hero from behind too (his look SC-A's back set turns left:
## `back_faces: "left"`, and the throw's back half reads the back key and holds the stick in the painted hand,
## EnemyManager._face_strip); an evaded hit says EVADE in its own colour and turns the hero see-through for a second
## (Player.evade_ghost_*, BillboardSprite.set_fade, the hero's two passes' `fade_alpha`); the black barrels drop 1-5 coins,
## two more of them a map (each black barrel's count rolled with the map), and the creatures' coins pay back as much as the
## map's black barrels hold (PickupManager.coin_debt, COIN_DEBT_SHARE of their coins while it is owed).

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
func telegraph_ring(_a, _b, _c, _d, _e := true) -> void:
	pass
func telegraph_line(_a, _b, _c, _d, _e) -> void:
	pass
func barrel_rush_fx(_fresh: bool) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return true
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
"""


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	DamageNumbers.I = null
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em}


func _bandit(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("spit_cactus", at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em.rise_t[i] = 1.0
	em.flash[i] = 0.0
	return i


# ---------------------------------------------------------------- the bandit's facing

func test_the_bandit_faces_right_from_the_front_and_left_from_the_back() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/enemies/spit_cactus/spit_cactus.json"))
	# (pass 115: Garry plays the Bombmaker SC-B, made like SC-A with the same keys; whichever thrower he plays)
	assert_array(["SC-A", "SC-B", "SC-C"]).contains([str(raw["variant"])])
	var entry: Dictionary = raw["variants"][str(raw["variant"])]
	# the key lives in the look's own entry (the green cactus SC-0 keeps the default)
	assert_str(str(entry.get("back_faces", ""))).is_equal("left")
	assert_bool(entry.has("front_faces")).is_false()
	var def: EnemyDef = Registry.enemy("spit_cactus")
	assert_str(def.front_faces).is_equal("right")
	assert_str(def.back_faces).is_equal("left")
	assert_str(def.variant_def("SC-0").back_faces).is_equal("right")


func test_the_throws_back_half_reads_the_back_key() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _bandit(em, Vector3.ZERO)
	var t: int = em.type_idx[i]
	assert_int(em._t_atkv[t]).is_equal(1)
	# the attack strip from behind is the back set; from the front it is itself; every other strip is itself
	em.away[i] = 1
	assert_int(em._face_strip(i, t, EnemyManager.A_ATTACK)).is_equal(5)
	assert_int(em._face_strip(i, t, EnemyManager.A_RUN)).is_equal(EnemyManager.A_RUN)
	assert_int(em._face_strip(i, t, 6)).is_equal(6)
	em.away[i] = 0
	assert_int(em._face_strip(i, t, EnemyManager.A_ATTACK)).is_equal(EnemyManager.A_ATTACK)
	# the mirror bit: heading screen-right (flip 0) the front throw shows as painted, the back throw mirrored (it aims
	# up-left as painted), like the back walk
	for away in [0, 1]:
		em.away[i] = away
		var s: int = em._face_strip(i, t, EnemyManager.A_ATTACK)
		assert_float(em._face_bit(0, t, s)).is_equal(float(away))
		assert_float(em._face_bit(1, t, s)).is_equal(float(1 - away))
	assert_float(em._face_bit(0, t, 5)).is_equal(1.0)
	assert_float(em._face_bit(0, t, EnemyManager.A_RUN)).is_equal(0.0)
	# a creature whose attack strip is one view (no front_back) never reads the back key for it
	em._t_atkv[t] = 0
	em.away[i] = 1
	assert_int(em._face_strip(i, t, EnemyManager.A_ATTACK)).is_equal(EnemyManager.A_ATTACK)
	em._t_atkv[t] = 1


func test_the_stick_leaves_the_painted_hand_from_behind_too() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var i := _bandit(em, Vector3.ZERO)
	var hand: Dictionary = EnemyManager.throw_block(Registry.enemy("spit_cactus"))["hand"]
	assert_float(float(hand["side"])).is_greater(0.0)
	em.state[i] = EnemyManager.STATE_WINDUP
	var scr := Vector3(-em._cf_tick.z, 0, em._cf_tick.x)
	var side := func(flip: int, away: int) -> float:
		em.flip[i] = flip
		em.away[i] = away
		return (em.muzzle_point(i, Vector3(1, 0, 0), hand) - em.pos[i]).dot(scr)
	# the front wind-up as painted holds the stick on the picture's left; mirrored, on its right
	assert_float(side.call(0, 0)).is_less(0.0)
	assert_float(side.call(1, 0)).is_greater(0.0)
	# the back wind-up as painted holds it on the picture's right: heading screen-left (flip 1) it shows as painted
	# (back_faces "left"), so the stick is on the right; heading screen-right it is mirrored, on the left
	assert_float(side.call(1, 1)).is_greater(0.0)
	assert_float(side.call(0, 1)).is_less(0.0)


# ---------------------------------------------------------------- the evade

func test_an_evade_says_evade_in_its_own_colour() -> void:
	var n := DamageNumbers.Num.new()
	n.kind = DamageNumbers.KIND_DODGE
	assert_str(DamageNumbers.label_of(n)).is_equal("EVADE")
	assert_bool(DamageNumbers.colour_of(n) == DamageNumbers.EVADE).is_true()
	assert_bool(DamageNumbers.EVADE == DamageNumbers.PALE).is_false()
	# the same word as BLOCK otherwise: its size, and BLOCK keeps its pale
	var b := DamageNumbers.Num.new()
	b.kind = DamageNumbers.KIND_BLOCK
	assert_str(DamageNumbers.label_of(b)).is_equal("BLOCK")
	assert_bool(DamageNumbers.colour_of(b) == DamageNumbers.PALE).is_true()
	assert_int(DamageNumbers.size_of(n)).is_equal(DamageNumbers.size_of(b))


func test_the_see_through_holds_half_then_fades_back_within_a_second() -> void:
	assert_float(Player.EVADE_GHOST_TIME).is_equal_approx(1.0, 0.0001)
	assert_float(Player.EVADE_GHOST_ALPHA).is_equal_approx(0.5, 0.0001)
	assert_float(Player.evade_ghost_alpha(0.0)).is_equal(1.0)
	assert_float(Player.evade_ghost_alpha(Player.EVADE_GHOST_TIME)).is_equal_approx(0.5, 0.0001)
	# never fainter than half, never more than whole, and only ever coming back as the second runs out
	var last := 0.0
	for k in range(101):
		var left := Player.EVADE_GHOST_TIME * (1.0 - float(k) / 100.0)
		var a := Player.evade_ghost_alpha(left)
		assert_float(a).is_greater_equal(0.5 - 0.0001)
		assert_float(a).is_less_equal(1.0)
		assert_float(a).is_greater_equal(last - 0.0001)
		last = a
	# half through the hold
	assert_float(Player.evade_ghost_alpha(Player.EVADE_GHOST_TIME - Player.EVADE_GHOST_HOLD + 0.01)).is_equal_approx(0.5, 0.0001)


func test_an_evaded_hit_turns_the_hero_see_through_and_another_never_adds_up() -> void:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.hp = p.max_hp
	assert_float(p.sprite.fade()).is_equal(1.0)
	Run.player_sheet.add_effects([Effect.make("evade", "add", 1.0, "player")], "p87")
	seed(87)
	var evaded := false
	for k in range(40):
		p.invuln = 0.0
		p.take_damage(5.0, Vector3.ZERO, {"by": "Goblin", "kind": "melee"})
		if str(p.last_outcome) == "evaded":
			evaded = true
			break
	assert_bool(evaded).is_true()
	assert_float(p.evade_ghost_t).is_equal_approx(Player.EVADE_GHOST_TIME, 0.0001)
	assert_float(p.sprite.fade()).is_equal_approx(0.5, 0.0001)
	# half a second on: still half
	p._tick_evade_ghost(0.5)
	assert_float(p.sprite.fade()).is_equal_approx(0.5, 0.0001)
	# another evade starts the second again from the top, never fainter
	p._evade_ghost_start()
	assert_float(p.evade_ghost_t).is_equal_approx(Player.EVADE_GHOST_TIME, 0.0001)
	assert_float(p.sprite.fade()).is_equal_approx(0.5, 0.0001)
	# fading back, then whole
	p._tick_evade_ghost(0.85)
	assert_float(p.sprite.fade()).is_greater(0.5)
	assert_float(p.sprite.fade()).is_less(1.0)
	p._tick_evade_ghost(0.5)
	assert_float(p.evade_ghost_t).is_equal(0.0)
	assert_float(p.sprite.fade()).is_equal(1.0)
	# a hero who goes down mid-second is whole again
	p._evade_ghost_start()
	p._die()
	assert_float(p.sprite.fade()).is_equal(1.0)
	Run.player_sheet.remove_source("p87")


func test_the_heros_two_passes_carry_the_fade() -> void:
	var first: String = (load("res://core/shaders/sprite_billboard.gdshader") as Shader).code
	var over: String = (load("res://core/shaders/sprite_billboard_over.gdshader") as Shader).code
	assert_str(first).contains("uniform float fade_alpha = 1.0;")
	assert_str(first).contains("if (fade_alpha < 0.999) {")
	# the first pass stays opaque (it writes no ALPHA): the see-through is the second pass's
	assert_bool(first.contains("ALPHA")).is_false()
	assert_str(over).contains("uniform float fade_alpha = 1.0;")
	assert_str(over).contains("ALPHA = fade_alpha;")
	# a sprite with the second pass takes it on both; one without stays whole
	var s: BillboardSprite = auto_free(BillboardSprite.new())
	add_child(s)
	s.enable_outline()
	s.enable_over_trails()
	s.set_fade(0.5)
	assert_float(float(s._mat.get_shader_parameter("fade_alpha"))).is_equal_approx(0.5, 0.0001)
	assert_float(float(s._over.get_shader_parameter("fade_alpha"))).is_equal_approx(0.5, 0.0001)
	assert_float(s.fade()).is_equal_approx(0.5, 0.0001)
	var plain: BillboardSprite = auto_free(BillboardSprite.new())
	add_child(plain)
	plain.set_fade(0.5)
	assert_float(plain.fade()).is_equal(1.0)
	assert_object(plain._mat.get_shader_parameter("fade_alpha")).is_null()


# ---------------------------------------------------------------- the black barrels

func _flat_field(seed_v: int) -> BarrelField:
	Run.map_seed = seed_v
	var ms := GDScript.new()
	ms.source_code = "extends MapBase\nvar flats_radius := 16.0\n"
	ms.reload()
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(ms)
	add_child(map)
	var game: Node = auto_free(Node.new())
	add_child(game)
	var field: BarrelField = auto_free(BarrelField.new())
	add_child(field)
	field.setup(game, map)
	return field


func test_two_more_black_barrels_on_top_of_the_random_ones() -> void:
	assert_int(BarrelField.COUNT).is_equal(35)
	assert_int(BarrelField.EXTRA_DARK).is_equal(2)
	assert_float(BarrelField.LIGHT_FRAC).is_equal_approx(0.22, 0.0001)
	var blacks := 0
	for sd in [3, 11, 87]:
		var f := _flat_field(sd)
		assert_int(f.pos.size()).is_equal(BarrelField.COUNT)
		# the last EXTRA_DARK are always black
		for k in range(BarrelField.COUNT - BarrelField.EXTRA_DARK, BarrelField.COUNT):
			assert_int(f.light[k]).is_equal(1)
		var n := 0
		for k in range(f.pos.size()):
			# pass 116: kind 1 is the coins barrel (2 the power-up one)
			n += 1 if f.light[k] == 1 else 0
		assert_int(n).is_greater_equal(BarrelField.EXTRA_DARK)
		blacks += n
	# about 33 x 0.22 + 2 = 9.3 a map
	assert_float(float(blacks) / 3.0).is_between(4.0, 16.0)


func _one_barrel(black: bool) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var pm: PickupManager = auto_free(PickupManager.new())
	add_child(pm)
	g.pickups = pm
	var bf: BarrelField = auto_free(BarrelField.new())
	bf.game = g
	bf.pos.append(Vector3.ZERO)
	bf.light.append(1 if black else 0)
	bf.alive.append(1)
	bf._index_in.append(0)
	for name in ["_body_dark", "_body_light", "_hoops", "_hoops_light"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = 1
		bf.set(name, mm)
	return {"bf": bf, "pm": pm}


func _coins(pm: PickupManager) -> Array:
	var out: Array = []
	for i in range(pm.alive.size()):
		if pm.alive[i] == 1 and pm.kind[i] == PickupManager.KIND_COIN:
			out.append(i)
	return out


func test_a_black_barrel_bursts_into_one_to_five_coins_and_a_brown_one_none() -> void:
	assert_int(BarrelField.COIN_MIN).is_equal(1)
	assert_int(BarrelField.COIN_MAX).is_equal(5)
	assert_float(BarrelField.COIN_VALUE).is_equal_approx(1.0, 0.0001)
	seed(87)
	var seen := {}
	for k in range(60):
		var b := _one_barrel(true)
		var bf: BarrelField = b["bf"]
		var pm: PickupManager = b["pm"]
		bf._break(0)
		var coins := _coins(pm)
		assert_int(coins.size()).is_between(BarrelField.COIN_MIN, BarrelField.COIN_MAX)
		assert_int(bf.coins_dropped).is_equal(coins.size())
		seen[coins.size()] = true
		for c: int in coins:
			assert_float(pm.value[c]).is_equal_approx(BarrelField.COIN_VALUE, 0.0001)
			assert_str(str(pm.coin_from.get(c, ""))).is_equal("barrel")
		# its gems as before: ten small and four medium
		var gems := 0
		for i in range(pm.alive.size()):
			if pm.alive[i] == 1 and pm.kind[i] != PickupManager.KIND_COIN:
				gems += 1
		assert_int(gems).is_equal(14)
	# every count from 1 to 5 comes up
	assert_int(seen.size()).is_equal(5)
	var brown := _one_barrel(false)
	(brown["bf"] as BarrelField)._break(0)
	assert_int(_coins(brown["pm"]).size()).is_equal(0)
	assert_int((brown["bf"] as BarrelField).coins_dropped).is_equal(0)
	# the barrel's coins are a gold source the boards know
	assert_bool(RunAnalytics.GOLD_SOURCES.has("barrel")).is_true()


func test_the_creatures_coins_pay_back_what_the_black_barrels_hold() -> void:
	assert_float(PickupManager.COIN_DEBT_SHARE).is_equal_approx(0.4, 0.0001)
	var pm: PickupManager = auto_free(PickupManager.new())
	add_child(pm)
	# a coin the bill takes: whole while more is owed, then the last one's share, then nothing (the share forced to 1)
	pm.set_coin_debt(5.0)
	assert_float(pm._after_coin_debt(3.0, 1.0)).is_equal(0.0)
	assert_float(pm.coin_debt).is_equal(2.0)
	assert_float(pm._after_coin_debt(3.0, 1.0)).is_equal(1.0)
	assert_float(pm.coin_debt).is_equal(0.0)
	assert_float(pm._after_coin_debt(2.0, 1.0)).is_equal(2.0)
	assert_float(pm.coin_debt_paid).is_equal(5.0)
	# and never when the share says no
	pm.set_coin_debt(5.0)
	assert_float(pm._after_coin_debt(3.0, 0.0)).is_equal(3.0)
	assert_float(pm.coin_debt).is_equal(5.0)
	# from the kills: while anything is owed, COIN_DEBT_SHARE of the coins go to the bill
	var def := EnemyDef.new()
	def.id = "p87_coin"
	def.drops = {"gold": 1.0}
	var p2: PickupManager = auto_free(PickupManager.new())
	add_child(p2)
	p2.set_coin_debt(1.0e9)
	seed(870)
	var n := 1500
	for k in range(n):
		p2.drop_from(def, Vector3(float(k % 40), 0, float(k / 40)), 1.0, false)
	var luck: float = Run.player_sheet.get_stat("luck", 0.0)
	var rolled := float(n) * minf(1.0 + luck, 1.0)
	assert_float(float(_coins(p2).size()) / rolled).is_equal_approx(1.0 - PickupManager.COIN_DEBT_SHARE, 0.05)
	# a bill of 17 is paid off in full, then the coins drop as before
	var p3: PickupManager = auto_free(PickupManager.new())
	add_child(p3)
	p3.set_coin_debt(17.0)
	for k in range(200):
		p3.drop_from(def, Vector3(float(k % 20), 0, float(k / 20)), 1.0, false)
	assert_float(p3.coin_debt).is_equal(0.0)
	assert_float(p3.coin_debt_paid).is_equal(17.0)


func test_the_maps_black_barrels_hold_their_coins_from_the_start_and_set_the_debt() -> void:
	var game: Node = auto_free(Node.new())
	game.set_script(_script(FAKE_GAME))
	add_child(game)
	var pm: PickupManager = auto_free(PickupManager.new())
	add_child(pm)
	game.pickups = pm
	Run.map_seed = 87
	var ms := GDScript.new()
	ms.source_code = "extends MapBase
var flats_radius := 16.0
"
	ms.reload()
	var map: Node3D = auto_free(Node3D.new())
	map.set_script(ms)
	add_child(map)
	var bf: BarrelField = auto_free(BarrelField.new())
	add_child(bf)
	bf.setup(game, map)
	assert_int(bf.coins.size()).is_equal(bf.pos.size())
	var sum := 0
	for k in range(bf.pos.size()):
		if bf.light[k] == 1:
			assert_int(bf.coins[k]).is_between(BarrelField.COIN_MIN, BarrelField.COIN_MAX)
		else:
			assert_int(bf.coins[k]).is_equal(0)
		sum += bf.coins[k]
	assert_int(bf.coins_total()).is_equal(sum)
	assert_float(pm.coin_debt).is_equal(float(sum))
	# the same map holds the same coins
	var again: BarrelField = auto_free(BarrelField.new())
	add_child(again)
	again.setup(auto_free(Node.new()), map)
	assert_array(Array(again.coins)).is_equal(Array(bf.coins))
	# breaking a black one drops what it holds
	for k in range(bf.pos.size()):
		if bf.light[k] == 1:
			var held: int = bf.coins[k]
			var before := _coins(pm).size()
			bf._break(k)
			assert_int(_coins(pm).size() - before).is_equal(held)
			break
