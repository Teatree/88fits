extends GdUnitTestSuite

## Pass 120, lane GHOST: the Undertaker's Shovel's ghost reworked (Garry: "Let's make him run in a circle around the
## grave ... an actual floating ghost ... the same visual for every hero. It's a 2 sided sprite ... attacks ... kind of
## ghostly projectiles like ones in Warcraft 3 ziggurat attack ... The count of those projectiles as well as the damage
## scale with hero power ... Cap is 6 projectiles at the same time ... The attacks carry no knockback to the enemies"):
## - the ghost circles its grave (circle_radius m, a lap every lap_seconds s, the way round alternating grave by grave);
## - it shows its front while it comes across or towards the camera and its back while it goes away (want_face);
## - a volley every volley_every s: bolt_count(power) bolts (1 below power 2, 6 from 17.2, never more) at the nearest distinct
##   creatures, each for bolt_damage(power); fewer creatures: the rest go round them again, fanned out;
## - a bolt never pushes and never crits, and is recorded as the item's own source;
## - in the run sim nothing is drawn, the bolts still fly and hit.

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
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var max_hp := 100.0
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
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
func heal(_a: float, _s: String = "", _c: String = "") -> void:
	pass
"""

const FAKE_PICKUPS := """extends Node
func spawn(_kind: int, _at: Vector3, _v: float) -> int:
	return 0
func spawn_chest(_at: Vector3, _boss: bool = false) -> void:
	pass
func add_attractor(_p: Vector3, _r: float) -> void:
	pass
func mark_coin(_i: int, _s: String) -> void:
	pass
"""

const DT := 1.0 / 60.0
const GRAVE := Vector3(60, 0, 50)


func before_test() -> void:
	Save.data = Save._default()
	Run.arena = false
	Run.sim_mode = false
	CardPool.rng = null


func after_test() -> void:
	Run.sim_mode = false
	CardPool.rng = null
	Run.arena = false
	Run.end()


func _start() -> void:
	var c: CharacterDef = Registry.character("drifter")
	Run.start(c, Registry.map("red_canyon"))
	Run.add_weapon(Registry.start_weapon_for(c), 1)
	Run.add_or_level_passive("undertakers_shovel")


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
	hero.global_position = Vector3(60, 0, 60)
	g.player = hero
	var em := EnemyManager.new()
	em.game = g
	em.player = hero
	g.add_child(em)
	g.enemies = em
	var pk := Node.new()
	pk.set_script(_script(FAKE_PICKUPS))
	g.add_child(pk)
	g.pickups = pk
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	em._rebuild_grid()
	var gy := Graveyard.new()
	g.add_child(gy)
	gy.setup(g)
	return {"g": g, "em": em, "gy": gy}


## Skeletons standing at `spots` (tough: a test's bolts never kill them), the grid rebuilt; their indices.
func _stand(em: EnemyManager, spots: Array, hp_mult: float = 500.0) -> Array:
	var out: Array = []
	for at: Vector3 in spots:
		var i := em.spawn("skeleton", at, null, 1.0, hp_mult)
		assert_int(i).is_greater_equal(0)
		em.state[i] = EnemyManager.STATE_MOVE
		em.rise_t[i] = 1.0
		out.append(i)
	em._rebuild_grid()
	return out


## Ticks the graveyard until its first grave's phase reaches `phase` (or `limit` s pass); the seconds it took.
func _until(gy: Graveyard, phase: int, limit: float = 20.0) -> float:
	var t := 0.0
	while t < limit and not gy.graves.is_empty() and int((gy.graves[0] as Dictionary)["phase"]) < phase:
		gy.tick(DT)
		t += DT
	return t


# ---------------------------------------------------------------- the data

func test_the_item_names_the_painted_ghost_and_lends_no_weapon() -> void:
	var p: PassiveDef = Registry.passive("undertakers_shovel")
	var g: Dictionary = p.params.get("grave", {})
	for key: String in ["ghost_front", "ghost_back"]:
		var path := "res://content/passives/undertakers_shovel/" + str(g.get(key, ""))
		assert_bool(ResourceLoader.exists(path)).override_failure_message(path).is_true()
	# nothing of the borrowed weapon is left: no damage share of the first weapon, no gun's pace or range
	for e in p.effects_at_level(1):
		assert_str((e as Effect).stat).is_not_equal("grave_damage_pct")
	for key: String in ["fire_min", "fire_max", "range_min", "range_max", "round"]:
		assert_bool(g.has(key)).override_failure_message(key).is_false()
	var t := TextGen.passive_text(p)
	assert_str(t).contains("circles it for 8 s")
	assert_str(t).contains("up to 6")
	assert_str(t).contains("no knockback")


# ---------------------------------------------------------------- power

func test_the_bolts_grow_with_power_and_never_pass_six() -> void:
	_start()
	var gy: Graveyard = auto_free(Graveyard.new())
	add_child(gy)
	gy.setup(null)
	# round(power ^ 0.6), 1 to 6
	assert_int(gy.bolt_count(0.2)).is_equal(1)
	assert_int(gy.bolt_count(1.0)).is_equal(1)
	assert_int(gy.bolt_count(2.0)).is_equal(2)
	assert_int(gy.bolt_count(5.0)).is_equal(3)
	assert_int(gy.bolt_count(10.0)).is_equal(4)
	assert_int(gy.bolt_count(16.0)).is_equal(5)
	assert_int(gy.bolt_count(20.0)).is_equal(6)
	assert_int(gy.bolt_count(50.0)).is_equal(6)
	assert_int(gy.bolt_count(500.0)).is_equal(6)
	var last := 0
	var p := 0.5
	while p < 200.0:
		var n := gy.bolt_count(p)
		assert_int(n).is_greater_equal(last)
		assert_int(n).is_less_equal(6)
		last = n
		p *= 1.1


func test_each_bolt_hits_harder_with_power_and_past_six_carries_the_rest() -> void:
	_start()
	var gy: Graveyard = auto_free(Graveyard.new())
	add_child(gy)
	gy.setup(null)
	# 3.2 x power ^ 0.9 below the cap
	assert_float(gy.bolt_damage(1.0)).is_equal_approx(3.2, 0.0001)
	assert_float(gy.bolt_damage(10.0)).is_equal_approx(3.2 * pow(10.0, 0.9), 0.0001)
	# past the cap the six carry the bolts it holds back: x (power ^ 0.6 / 6)
	assert_float(gy.bolt_damage(50.0)).is_equal_approx(3.2 * pow(50.0, 0.9) * pow(50.0, 0.6) / 6.0, 0.001)
	# every bolt and every volley grows with power
	var last_d := 0.0
	var last_v := 0.0
	var p := 0.5
	while p < 200.0:
		var d := gy.bolt_damage(p)
		var v := d * float(gy.bolt_count(p))
		assert_float(d).is_greater(last_d)
		assert_float(v).is_greater(last_v)
		last_d = d
		last_v = v
		p *= 1.05


func test_the_power_is_the_heros_own() -> void:
	_start()
	var gy: Graveyard = auto_free(Graveyard.new())
	add_child(gy)
	gy.setup(null)
	var want: float = HeroPower.measure(Run.weapons, Run.player_sheet)["power"]
	assert_float(gy.power()).is_equal_approx(want, 0.0001)
	gy.power_override = 12.0
	assert_float(gy.power()).is_equal_approx(12.0, 0.0001)


# ---------------------------------------------------------------- the circling

func test_the_ghost_climbs_out_then_circles_its_grave_a_lap_every_4_s() -> void:
	_start()
	var gy: Graveyard = auto_free(Graveyard.new())
	add_child(gy)
	gy.setup(null)
	assert_bool(gy.dig(GRAVE)).is_true()
	var g: Dictionary = gy.graves[0]
	# out in front of its grave (towards the camera), close
	_until(gy, Graveyard.FIGHT)
	var s0 := gy.ghost_spot(g)
	assert_float(s0.z - GRAVE.z).is_greater(0.0)
	assert_float(Vector2(s0.x - GRAVE.x, s0.z - GRAVE.z).length()).is_less(0.5)
	# past the spiral: on its 1.5 m circle
	for _k in range(60):
		gy.tick(DT)
	var a0 := 0.0
	var turned := 0.0
	var prev := Vector2.ZERO
	for k in range(240):
		gy.tick(DT)
		var s := gy.ghost_spot(g)
		var v := Vector2(s.x - GRAVE.x, s.z - GRAVE.z)
		assert_float(v.length()).is_equal_approx(1.5, 0.01)
		if k > 0:
			turned += prev.angle_to(v)
		prev = v
	# 239 frames of a lap every 4 s, the first grave anticlockwise from above (+X towards -Z: the angle in x,z falls)
	assert_float(absf(turned)).is_equal_approx(TAU * 239.0 / 240.0, 0.02)
	assert_float(turned).is_less(0.0)
	# the next grave goes round the other way
	assert_bool(gy.dig(GRAVE + Vector3(5, 0, 0))).is_true()
	assert_float(float((gy.graves[1] as Dictionary)["spin"])).is_equal(-float(g["spin"]))
	# it circles the whole fight, then vanishes and the grave sinks as before
	var fight := _until(gy, Graveyard.VANISH)
	assert_float(fight).is_less_equal(8.0)
	assert_int(int(g["phase"])).is_equal(Graveyard.VANISH)


func test_front_while_it_comes_back_while_it_goes_away_never_flickering() -> void:
	# the rule: past FACE_HYST either way of sideways
	assert_int(Graveyard.want_face(1, 0.0)).is_equal(1)
	assert_int(Graveyard.want_face(1, -0.1)).is_equal(1)
	assert_int(Graveyard.want_face(1, -0.3)).is_equal(-1)
	assert_int(Graveyard.want_face(-1, 0.1)).is_equal(-1)
	assert_int(Graveyard.want_face(-1, 0.3)).is_equal(1)
	assert_int(Graveyard.want_face(-1, -0.9)).is_equal(-1)
	# in a scene: a painted ghost going round shows its back going away (-Z) and its front coming back (+Z)
	_start()
	var w := _world()
	var gy: Graveyard = w["gy"]
	assert_bool(gy.dig(GRAVE)).is_true()
	var g: Dictionary = gy.graves[0]
	_until(gy, Graveyard.FIGHT)
	assert_object(g["ghost"]).is_not_null()
	assert_int(int(g["face"])).is_equal(1)
	var saw_back := false
	var saw_front := false
	var swaps := 0
	var last := int(g["face"])
	for _k in range(300):
		gy.tick(DT)
		var way := Graveyard.circle_way(g)
		var face := int(g["face"])
		if face != last:
			swaps += 1
			last = face
		if float(g["turn"]) < 0.0:
			if way.z < -0.6:
				assert_int(face).is_equal(-1)
				saw_back = true
			elif way.z > 0.6:
				assert_int(face).is_equal(1)
				saw_front = true
	assert_bool(saw_back).is_true()
	assert_bool(saw_front).is_true()
	# five seconds round a 4 s lap: two turns a lap, never more
	assert_int(swaps).is_less_equal(3)
	# the painting on the sprite is the side it shows
	while float(g["turn"]) >= 0.0:
		gy.tick(DT)
	var mat := (g["ghost"] as BillboardSprite).material_override as ShaderMaterial
	assert_object(mat.get_shader_parameter("sprite")).is_same(gy.ghost_texture(0 if int(g["face"]) > 0 else 1))
	assert_object(gy.ghost_texture(1)).is_not_same(gy.ghost_texture(0))


# ---------------------------------------------------------------- the volleys

func test_a_volley_sends_a_bolt_at_each_of_the_nearest_up_to_the_count() -> void:
	_start()
	var w := _world()
	var gy: Graveyard = w["gy"]
	var em: EnemyManager = w["em"]
	assert_bool(gy.dig(GRAVE)).is_true()
	var g: Dictionary = gy.graves[0]
	_until(gy, Graveyard.FIGHT)
	var at := gy.ghost_spot(g)
	# eight creatures at 2..9 m from the ghost, one past its 9 m reach
	var spots: Array = []
	for k in range(8):
		var a := TAU * float(k) / 8.0
		spots.append(at + Vector3(cos(a), 0, sin(a)) * (2.0 + float(k)))
	spots.append(at + Vector3(0, 0, -9.6))
	var all := _stand(em, spots)
	gy.power_override = 20.0
	var near := gy.nearest_targets(at, 9.0, 6)
	assert_array(Array(near)).is_equal(all.slice(0, 6))
	# the volley: six bolts, one each at the six nearest
	g["fire_t"] = 0.0
	gy.tick(DT)
	assert_int(gy.volleys).is_equal(1)
	assert_int(gy.bolts.count).is_equal(6)
	var aimed: Array = []
	for k in range(GhostBolts.MAX):
		if gy.bolts.live[k] == 1:
			aimed.append(gy.bolts.tgt[k])
			assert_float(gy.bolts.dmg[k]).is_equal_approx(gy.bolt_damage(20.0), 0.0001)
	aimed.sort()
	var want: Array = all.slice(0, 6)
	want.sort()
	assert_array(aimed).is_equal(want)
	# at power 1: one bolt, at the nearest
	gy.bolts.clear()
	gy.power_override = 1.0
	g["fire_t"] = 0.0
	gy.tick(DT)
	assert_int(gy.bolts.count).is_equal(1)


func test_with_fewer_creatures_the_bolts_fan_out_and_go_round_them_again() -> void:
	_start()
	var w := _world()
	var gy: Graveyard = w["gy"]
	var em: EnemyManager = w["em"]
	assert_bool(gy.dig(GRAVE)).is_true()
	var g: Dictionary = gy.graves[0]
	_until(gy, Graveyard.FIGHT)
	var at := gy.ghost_spot(g)
	var two := _stand(em, [at + Vector3(4, 0, 0), at + Vector3(0, 0, -5)])
	gy.power_override = 30.0
	g["fire_t"] = 0.0
	gy.tick(DT)
	assert_int(gy.bolts.count).is_equal(6)
	var per := {}
	var dirs: Array = []
	for k in range(GhostBolts.MAX):
		if gy.bolts.live[k] == 1:
			per[gy.bolts.tgt[k]] = int(per.get(gy.bolts.tgt[k], 0)) + 1
			var v: Vector3 = gy.bolts.vel[k]
			dirs.append(Vector2(v.x, v.z).normalized())
	assert_int(int(per.get(two[0], 0))).is_equal(3)
	assert_int(int(per.get(two[1], 0))).is_equal(3)
	# every bolt left in its own direction
	for a in range(dirs.size()):
		for b in range(a + 1, dirs.size()):
			assert_float((dirs[a] as Vector2).dot(dirs[b])).is_less(0.999)
	# the angles: 14 degrees out to alternate sides, 32 more each round
	assert_float(gy.bolt_angle(0, 2)).is_equal_approx(14.0, 0.001)
	assert_float(gy.bolt_angle(1, 2)).is_equal_approx(-14.0, 0.001)
	assert_float(gy.bolt_angle(2, 2)).is_equal_approx(46.0, 0.001)
	assert_float(gy.bolt_angle(5, 2)).is_equal_approx(-78.0, 0.001)


func test_a_volley_every_second_while_it_circles() -> void:
	_start()
	var w := _world()
	var gy: Graveyard = w["gy"]
	var em: EnemyManager = w["em"]
	assert_bool(gy.dig(GRAVE)).is_true()
	_stand(em, [GRAVE + Vector3(4, 0, 0), GRAVE + Vector3(-4, 0, 2), GRAVE + Vector3(0, 0, -5)], 5000.0)
	_until(gy, Graveyard.STONE_DOWN)
	# out at 0.35 s, then every 1 s through the 8 s fight: 8 volleys
	assert_int(gy.volleys).is_equal(8)


func test_bolts_land_with_no_knockback_and_no_crit_as_the_items_own() -> void:
	_start()
	Run.player_sheet.add_effects([Effect.make("crit_chance", "add", 1.0, "player")], "test crits")
	var w := _world()
	var gy: Graveyard = w["gy"]
	var em: EnemyManager = w["em"]
	em.refresh_player_stats()
	var one := _stand(em, [Vector3(60, 0, 44)])
	var i: int = one[0]
	var hp0: float = em.hp[i]
	gy._tune_bolts()
	assert_bool(gy.bolts.fire(Vector3(60, 1.2, 50), Vector3(1, 0.3, 0).normalized(), i, 25.0)).is_true()
	var t := 0.0
	while t < 3.0 and gy.bolts.count > 0:
		gy.tick(DT)
		t += DT
	assert_int(gy.bolts.hits).is_equal(1)
	# exactly its damage (no crit), no push at all
	assert_float(hp0 - em.hp[i]).is_equal_approx(25.0 * (1.0 - em.dr[i]), 0.001)
	assert_bool(em.last_crit).is_false()
	assert_vector(em.kb[i]).is_equal(Vector3.ZERO)
	assert_float(float(Run.damage_by_weapon.get("undertakers_shovel", 0.0))).is_greater(0.0)
	assert_float(gy.bolts.dealt).is_equal_approx(25.0 * (1.0 - em.dr[i]), 0.001)


func test_a_bolt_whose_creature_is_gone_flies_to_where_it_was_and_fizzles() -> void:
	_start()
	var w := _world()
	var gy: Graveyard = w["gy"]
	var em: EnemyManager = w["em"]
	var one := _stand(em, [Vector3(60, 0, 40)])
	gy._tune_bolts()
	gy.bolts.fire(Vector3(60, 1.2, 50), Vector3(0, 0.3, -1).normalized(), one[0], 10.0)
	em._free(one[0])
	em._rebuild_grid()
	var t := 0.0
	while t < 4.0 and gy.bolts.count > 0:
		gy.tick(DT)
		t += DT
	# it flew on to where its creature stood and popped there
	assert_int(gy.bolts.hits).is_equal(0)
	assert_int(gy.bolts.fizzles).is_equal(1)
	assert_float(t).is_less(2.0)


func test_in_the_run_sim_nothing_is_drawn_but_the_bolts_still_hit() -> void:
	_start()
	Run.sim_mode = true
	var w := _world()
	var gy: Graveyard = w["gy"]
	var em: EnemyManager = w["em"]
	_stand(em, [GRAVE + Vector3(3, 0, 0), GRAVE + Vector3(-3, 0, 1)], 5000.0)
	gy.power_override = 8.0
	assert_bool(gy.dig(GRAVE)).is_true()
	_until(gy, Graveyard.STONE_DOWN)
	var t := 0.0
	while t < 3.0 and gy.bolts.count > 0:
		gy.tick(DT)
		t += DT
	assert_int(gy.get_child_count()).is_equal(0)
	assert_int(gy.bolts.drawn()).is_equal(0)
	assert_int(gy.bolts.hits).is_greater(0)
	assert_float(float(Run.damage_by_weapon.get("undertakers_shovel", 0.0))).is_greater(0.0)
