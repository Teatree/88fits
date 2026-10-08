extends GdUnitTestSuite

## Pass 60, lane WP (Garry's list): no emblem hangs over any weapon after a mutation any more (the Sun Scepter's ring and
## tint, which live on the sceptre, stay); the Pressure Cooker is about standing still (the pod's pressure climbs to
## +200% attack speed over 15 s of stillness, moving lets it out, a hit vents half, the pod glows with it); no mutation
## can be banished anywhere (the boss chest's hero option included); the Invincibility power-up's bubble nulls every
## hostile knock (the Energy Shield line and the hit blink do not); a creature's knock throws the hero out of the crowd
## (Player.escape_dir) and never straight back within KNOCK_SETTLE (settle_knock), a shot's shove keeps its line; the
## Tommy Gun's rounds and the Boomstick's pellets are cored streaks (WeaponBehavior.streak_mesh) with their own tracer
## beads, the pellets fly nose first and fade over the last quarter of their range, and the muzzle's sparks, flash and
## smoke turn along the aim.

const SCEPTER := preload("res://core/behaviors/SunScepter.gd")

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
var bursts: Array = []
func toast(_t, _c = null) -> void:
	pass
func fx_burst(at, col, size) -> void:
	bursts.append({"at": at, "col": col, "size": size})
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
func shockwave(_a, _b) -> void:
	pass
func spawn_zone(_at, _r, _s, _dps, _tick, _w, _slow = 0.0, _col = null):
	return null
func spawn_cloud(_at, _w, _r, _el = "poison", _p = {}) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var last_outcome := "hit"
var hip: Node3D = null
var max_hp := 100.0
var still := false
signal hit
signal shield_hit(broke: bool)
func is_still() -> bool:
	return still
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
	pass
func blast(_v: Vector3, _up: float = 0.0) -> void:
	pass
func heal(_a: float, _s: String = "") -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
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


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("drifter"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game round a fake hero, with the real crowd, shots, effects and ground marks (the behaviours' world).
func _world(hero_at := Vector3.ZERO) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	hero.global_position = hero_at
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
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
	var fx := Fx.new()
	g.add_child(fx)
	g.fx = fx
	var tg := Telegraphs.new()
	g.add_child(tg)
	g.telegraphs = tg
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx, "tg": tg, "cam": cam}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, inst: WeaponInstance) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(inst, w["g"])
	return b


func _pod(w: Dictionary, inst: WeaponInstance) -> MissilePod:
	return _behaviour(w, MissilePod.new(), inst) as MissilePod


func _emitter(w: Dictionary, inst: WeaponInstance) -> ProjectileEmitter:
	return _behaviour(w, ProjectileEmitter.new(), inst) as ProjectileEmitter


## The same build change Game._sync_weapons makes: the instance re-folded with a new set of mutations, then refresh_marks.
func _rebuild_with(b: WeaponBehavior, muts: Array) -> void:
	b.inst.mutations.clear()
	for m: String in muts:
		b.inst.mutations.append(Registry.mutation(m))
	b.inst.rebuild(Run.player_sheet, [b.inst])
	b.refresh_marks()


## The real hero (Player.tscn) on his own under the suite: no crowd to read.
func _hero() -> Player:
	var p: Player = auto_free(load("res://player/Player.tscn").instantiate())
	add_child(p)
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	p.global_position = Vector3.ZERO
	p._kb = Vector3.ZERO
	p._knock_grace = 0.0
	p._settle_t = 0.0
	return p


## The real hero with a real crowd round him: a fake game (its `enemies` is what Player._crowd finds) holding the hero
## and an EnemyManager, with creatures standing at `spots`.
func _hero_in_crowd(spots: Array) -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var mb := MapBase.new()
	g.add_child(mb)
	g.map = mb
	var p: Player = load("res://player/Player.tscn").instantiate()
	g.add_child(p)
	g.player = p
	p.setup(Registry.character("astro"))
	p.refresh_stats()
	p.hp = p.max_hp
	p.global_position = Vector3.ZERO
	p._kb = Vector3.ZERO
	p._knock_grace = 0.0
	p._settle_t = 0.0
	var em := EnemyManager.new()
	em.game = g
	em.player = p
	em.colour_after_kills = 999999
	g.add_child(em)
	g.enemies = em
	var ids: Array = []
	for at: Vector3 in spots:
		var i := em.spawn("skeleton", at, null, 1.0, 50.0)
		assert_int(i).is_greater_equal(0)
		em.state[i] = EnemyManager.STATE_MOVE
		em.vel[i] = Vector3.ZERO
		ids.append(i)
	em._rebuild_grid()
	return {"g": g, "p": p, "em": em, "ids": ids}


func _card(m: MutationDef, extra: Dictionary = {}) -> Dictionary:
	var c := {"type": "mutation", "id": m.id, "def": m, "level_from": 0, "level_to": 1}
	c.merge(extra, true)
	return c


# ---------------------------------------------------------------- 1. emblems

func test_no_weapon_hangs_an_emblem_after_a_mutation() -> void:
	var w := _world()
	var g: Node = w["g"]
	# the emblem builder is gone from the base class
	var bare: WeaponBehavior = auto_free(WeaponBehavior.new())
	assert_bool(bare.has_method("shows_marks")).is_false()
	assert_bool(bare.has_method("_tick_marks")).is_false()
	assert_bool(bare.has_method("_mark_for")).is_false()
	# three shapes of weapon, each with its path: nothing named MutationMarks anywhere under the game
	var pea := _emitter(w, _inst("peashooter", ["toxic_peas", "big_peas", "bouncing_peas"], 3))
	var lob := _behaviour(w, Lobber.new(), _inst("lob_grenade", ["frag"]))
	var pod := _pod(w, _inst("rocket_pod", ["heavy_warhead", "cluster_munitions"]))
	for b: WeaponBehavior in [pea, lob, pod]:
		assert_object(b.get_node_or_null("MutationMarks")).is_null()
	assert_int(g.find_children("MutationMarks", "", true, false).size()).is_equal(0)
	# a pick taken mid-run (Game._sync_weapons re-folds the instance and calls refresh_marks): still none
	_rebuild_with(pea, ["toxic_peas", "big_peas", "bouncing_peas", "fan_the_hammer"])
	_rebuild_with(pod, ["heavy_warhead", "cluster_munitions", "pressure_cooker"])
	assert_int(g.find_children("MutationMarks", "", true, false).size()).is_equal(0)
	# one left hanging from an older build is taken down
	var old := Node3D.new()
	old.name = "MutationMarks"
	pea.add_child(old)
	pea.refresh_marks()
	assert_object(pea.get_node_or_null("MutationMarks")).is_null()


func test_the_sun_scepter_keeps_flickers_ring_and_heat_strokes_tint() -> void:
	var w := _world()
	var b = _behaviour(w, SCEPTER.new(), _inst("sun_scepter", ["heat_stroke", "flicker"]))
	# the looks that live on the sceptre itself stay (Garry: "the Flicker's halo that is really more of a ring around
	# the scepter"); no floating emblem
	assert_bool(b.has_ring()).is_true()
	assert_bool(b.staff_tinted()).is_true()
	assert_object(b.find_child("HandleRing", true, false)).is_not_null()
	assert_object(b.get_node_or_null("MutationMarks")).is_null()
	# Flicker taken mid-run builds the ring through the same hook
	var plain = _behaviour(w, SCEPTER.new(), _inst("sun_scepter"))
	assert_bool(plain.has_ring()).is_false()
	_rebuild_with(plain, ["flicker"])
	assert_bool(plain.has_ring()).is_true()
	assert_object(plain.get_node_or_null("MutationMarks")).is_null()


# ---------------------------------------------------------------- 2. the Pressure Cooker

func test_the_pressure_cooker_is_about_standing_still() -> void:
	var m: MutationDef = Registry.mutation("pressure_cooker")
	assert_object(m).is_not_null()
	assert_str(m.weapon).is_equal("rocket_pod")
	assert_str(m.mutation_kind).is_equal("motion")
	var pr: Dictionary = m.params.get("pressure", {})
	assert_float(float(pr.get("max", 0.0))).is_equal_approx(2.0, 0.0001)
	assert_float(float(pr.get("seconds", 0.0))).is_equal_approx(15.0, 0.0001)
	assert_float(float(pr.get("hit_vent", 0.0))).is_equal_approx(0.5, 0.0001)
	assert_bool(pr.has("hit_keeps")).is_false()
	assert_str(m.text.to_lower()).contains("standing still")
	assert_str(m.text).contains("+200%")
	assert_str(m.text).contains("15 s")
	assert_str(m.text.to_lower()).not_contains("unhit")


func test_pressure_builds_standing_still_to_plus_200_and_moving_lets_it_out() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var inst := _inst("rocket_pod", ["pressure_cooker"])
	var mp := _pod(w, inst)
	var cd := inst.stat("cooldown")
	assert_float(mp.pressure).is_equal_approx(0.0, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd, 0.0001)
	# walking: nothing builds
	hero.set("still", false)
	for k in range(60):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.0, 0.0001)
	# standing still: linear, a third of the way at 5 s, the top at 15 (+200%: three volleys where one went)
	hero.set("still", true)
	for k in range(300):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(1.0 / 3.0, 0.01)
	assert_float(mp.pressure_bonus()).is_equal_approx(2.0 / 3.0, 0.02)
	for k in range(600):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(1.0, 0.0001)
	assert_float(mp.pressure_bonus()).is_equal_approx(2.0, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd / 3.0, 0.0001)
	# longer still: it holds at the top
	for k in range(120):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(1.0, 0.0001)
	# one step: all of it out at once, the sheet's cooldown again
	hero.set("still", false)
	mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.0, 0.0001)
	assert_float(mp.pressure_bonus()).is_equal_approx(0.0, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd, 0.0001)
	# a pod without the pick never builds any
	var plain := _pod(w, _inst("rocket_pod"))
	hero.set("still", true)
	for k in range(120):
		plain._tick(DT)
	assert_float(plain.pressure).is_equal_approx(0.0, 0.0001)
	assert_float(plain.pressure_bonus()).is_equal_approx(0.0, 0.0001)


func test_a_hit_vents_half_a_shield_hit_too_and_the_pod_puffs_steam() -> void:
	var w := _world()
	var g: Node = w["g"]
	var hero: Node3D = w["hero"]
	var inst := _inst("rocket_pod", ["pressure_cooker"])
	var mp := _pod(w, inst)
	var cd := inst.stat("cooldown")
	# nothing built: a hit vents nothing and puffs nothing
	hero.emit_signal("hit")
	assert_int(mp.vents).is_equal(0)
	assert_int((g.get("bursts") as Array).size()).is_equal(0)
	# full: a bite on his health vents half, with a puff of steam off the pod
	mp.pressure = 1.0
	hero.emit_signal("hit")
	assert_float(mp.pressure).is_equal_approx(0.5, 0.0001)
	assert_float(mp.fire_interval()).is_equal_approx(cd / 2.0, 0.0001)
	assert_int(mp.vents).is_equal(1)
	var bursts: Array = g.get("bursts")
	assert_int(bursts.size()).is_equal(1)
	var col: Color = bursts[0]["col"]
	assert_bool(col.is_equal_approx(MissilePod.STEAM)).is_true()
	# a hit the Energy Shield line took vents too: the hero was touched
	hero.emit_signal("shield_hit", false)
	assert_float(mp.pressure).is_equal_approx(0.25, 0.0001)
	assert_int(mp.vents).is_equal(2)
	# the vented pod goes on building while he stands, once the hit's hold (VENT_HOLD) is over
	hero.set("still", true)
	for k in range(int(MissilePod.VENT_HOLD / DT)):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.25, 0.002)
	for k in range(60):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.25 + 1.0 / 15.0, 0.01)


func test_the_pod_glows_with_the_pressure() -> void:
	var w := _world()
	var mp := _pod(w, _inst("rocket_pod", ["pressure_cooker"]))
	assert_int(mp._heat_mats.size()).is_greater_equal(2)
	mp.pressure = 0.0
	mp._tick_heat()
	assert_float(mp.heat_shown()).is_equal_approx(0.0, 0.0001)
	var m0: StandardMaterial3D = mp._heat_mats[0]
	var base: Dictionary = mp._heat_base[0]
	assert_float(m0.emission_energy_multiplier).is_equal_approx(float(base["energy"]), 0.0001)
	# halfway: warming
	mp.pressure = 0.5
	mp._tick_heat()
	assert_float(mp.heat_shown()).is_equal_approx(0.5, 0.0001)
	assert_float(m0.emission_energy_multiplier).is_greater(float(base["energy"]))
	# the top: clearly hot, HEAT_COLOR at HEAT_ENERGY (hotter than pass 53's 0.9: the glow is the only gauge)
	mp.pressure = 1.0
	mp._tick_heat()
	assert_float(mp.heat_shown()).is_equal_approx(1.0, 0.0001)
	assert_bool(m0.emission.is_equal_approx(MissilePod.HEAT_COLOR)).is_true()
	assert_float(m0.emission_energy_multiplier).is_equal_approx(maxf(MissilePod.HEAT_ENERGY, float(base["energy"])), 0.0001)
	assert_float(MissilePod.HEAT_ENERGY).is_greater_equal(1.2)
	assert_bool(m0.emission_enabled).is_true()


func test_the_weapon_text_says_the_pressure_is_built_standing_still() -> void:
	var inst := _inst("rocket_pod", ["pressure_cooker"])
	var text := TextGen.weapon_description(inst.def, inst.sheet, inst.params)
	assert_str(text).contains("Standing still builds pressure")
	assert_str(text).contains("200%")
	assert_str(text).contains("15 s")
	assert_str(text).contains("a hit vents half")
	assert_str(text.to_lower()).not_contains("unhit")
	# the Hellfire Battery's own numbers (its final keeps a pressure block) read the same way
	var hb := _inst("hellfire_battery")
	var ht := TextGen.weapon_description(hb.def, hb.sheet, hb.params)
	assert_str(ht).contains("Standing still builds pressure")
	assert_str(ht.to_lower()).not_contains("unhit")


# ---------------------------------------------------------------- 3. no banish on a mutation

func test_no_mutation_can_be_banished_anywhere() -> void:
	var seen_hero := false
	var n := 0
	for m: MutationDef in Registry.mutations.values():
		n += 1
		seen_hero = seen_hero or m.is_hero()
		var card := _card(m)
		assert_str(Run.banish_refusal(card)).override_failure_message(m.id).is_equal("mutation")
		assert_bool(Run.can_banish_card(card)).override_failure_message(m.id).is_false()
		# the boss chest's roll (its own shape, no level keys), the hero option included
		var roll := {"type": "mutation", "id": m.id, "def": m, "boss": true}
		assert_bool(ChestScreen.can_banish(roll)).override_failure_message(m.id).is_false()
		assert_str(ChestScreen.banish_refusal(roll)).is_equal("A mutation cannot be banished.")
	assert_int(n).is_greater(40)
	assert_bool(seen_hero).is_true()
	# a card that only carries the def says the same; CardPool.banishable lets none through, held family or not
	var path_m: MutationDef = Registry.mutations_of("boomstick")[0]
	assert_str(Run.banish_refusal({"type": "card", "id": path_m.id, "def": path_m})).is_equal("mutation")
	Run.add_weapon(Registry.weapon("boomstick"), 1)
	var hero_m: MutationDef = Registry.hero_mutations("drifter")[0]
	assert_int(CardPool.banishable([_card(path_m), _card(hero_m)]).size()).is_equal(0)
	# the level-up's lock, by contrast, still lets a new passive item go
	var fresh: PassiveDef = null
	for pd: PassiveDef in Registry.sorted_passives_only():
		if not Run.passives.has(pd.id) and not Registry.is_hidden(pd):
			fresh = pd
			break
	assert_object(fresh).is_not_null()
	assert_str(Run.banish_refusal({"type": "passive", "id": fresh.id, "def": fresh, "level_from": 0, "level_to": 1})).is_equal("")


func test_a_banish_is_never_spent_on_a_mutation() -> void:
	Run.banishes_left = 1
	var m: MutationDef = Registry.mutations_of("rocket_pod")[2]
	var hero_m: MutationDef = Registry.hero_mutations("drifter")[0]
	for md: MutationDef in [m, hero_m]:
		# the level-up route
		assert_bool(Run.banish_card(_card(md))).is_false()
		assert_int(Run.banishes_left).is_equal(1)
		assert_bool(Run.banished.has(md.id)).is_false()
		# the chest route: nothing spent, no new roll
		var r := Run.chest_banish({"type": "mutation", "id": md.id, "def": md, "boss": true})
		assert_bool(r.is_empty()).is_true()
		assert_int(Run.banishes_left).is_equal(1)
		assert_bool(Run.banished.has(md.id)).is_false()
	# with the family held, the same
	Run.add_weapon(Registry.weapon("rocket_pod"), 1)
	assert_bool(Run.banish_card(_card(m))).is_false()
	assert_bool(Run.chest_banish({"type": "mutation", "id": m.id, "def": m, "boss": true}).is_empty()).is_true()
	assert_int(Run.banishes_left).is_equal(1)


# ---------------------------------------------------------------- 4. the Invincibility bubble

func test_the_invincibility_bubble_nulls_every_hostile_knock() -> void:
	var p := _hero()
	assert_bool(p.knock_immune()).is_false()
	p.shield(6.0)
	assert_bool(p.knock_immune()).is_true()
	# a bite's knock, a charge's shove, a pull, a blast: none moves him
	p.hit_knock(Vector3(8, 0, 0))
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	assert_bool(p.shove(Vector3(5, 0, 0))).is_false()
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	p.apply_knockback(Vector3(3, 0, 0))
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	var vy := p.velocity.y
	p.blast(Vector3(10, 0, 0), 4.0)
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	assert_float(p.velocity.y).is_equal_approx(vy, 0.0001)
	# a landed hit under the bubble: taken by the bubble, nothing shoves him, however many land
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 4.0})
	assert_str(p.last_outcome).is_equal("shield")
	p.take_damage(5.0, Vector3(0, 0, -1), {"knock": 4.0})
	assert_vector(p._kb).is_equal(Vector3.ZERO)
	# his own movement is not a hostile knock: the Sabre's lunge and Astro's thruster burst still carry him
	p.apply_knockback(Vector3(3, 0, 0), false)
	assert_float(p._kb.x).is_equal_approx(3.0, 0.0001)
	p.blast(Vector3(10, 0, 0), 0.0, false)
	assert_float(p._kb.x).is_equal_approx(13.0, 0.0001)
	# the bubble gone: knocks land again
	p.shield_t = 0.0
	p._kb = Vector3.ZERO
	p.hit_knock(Vector3(4, 0, 0))
	assert_float(p._kb.x).is_equal_approx(4.0, 0.0001)


func test_invuln_or_the_energy_shield_alone_is_no_knock_immunity() -> void:
	var p := _hero()
	# the blink after a hit or a revive
	p.invuln = 2.0
	assert_bool(p.knock_immune()).is_false()
	p.hit_knock(Vector3(4, 0, 0))
	assert_float(p._kb.x).is_equal_approx(4.0, 0.0001)
	# the Energy Shield line's points
	p.invuln = 0.0
	p._kb = Vector3.ZERO
	p.shield_pts = 30.0
	assert_bool(p.knock_immune()).is_false()
	p.take_damage(5.0, Vector3(-1, 0, 0), {"knock": 3.0})
	assert_str(p.last_outcome).is_equal("shield")
	assert_float(p._kb.x).is_equal_approx(3.0, 0.0001)
	# god mode is no bubble either
	p.god = true
	assert_bool(p.knock_immune()).is_false()
	# only the power-up's seconds
	p.shield_t = 0.1
	assert_bool(p.knock_immune()).is_true()


# ---------------------------------------------------------------- 5. out of the crowd, no ping-pong

func test_a_creature_knock_goes_out_through_the_gap() -> void:
	# a creature on each side, 1.2 m off: the push (away from the right one) goes out up or down the screen instead
	var w := _hero_in_crowd([Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0)])
	var p: Player = w["p"]
	assert_object(p._crowd()).is_not_null()
	var out := p.escape_dir(Vector3(-5, 0, 0))
	assert_float(out.length()).is_equal_approx(5.0, 0.001)
	assert_float(absf(out.x)).is_less(1.5)
	assert_float(absf(out.z)).is_greater(4.5)
	assert_float(out.y).is_equal_approx(0.0, 0.0001)
	# through hit_knock too
	p.hit_knock(Vector3(-5, 0, 0))
	assert_float(absf(p._kb.z)).is_greater(4.5)
	assert_float(absf(p._kb.x)).is_less(1.5)
	# a lone biter: straight away from it, as before
	var em: EnemyManager = w["em"]
	em.alive[int(w["ids"][1])] = 0
	em._rebuild_grid()
	var away := p.escape_dir(Vector3(-5, 0, 0))
	assert_float(away.x).is_less(-4.5)
	assert_float(absf(away.z)).is_less(1.5)
	# a hidden or a held creature is not a wall
	em.alive[int(w["ids"][1])] = 1
	em.hidden[int(w["ids"][1])] = 1
	em._rebuild_grid()
	assert_float(p.escape_dir(Vector3(-5, 0, 0)).x).is_less(-4.5)
	# no crowd to read (a bare hero, the title): the push as it was
	var lone := _hero()
	assert_object(lone._crowd()).is_null()
	assert_vector(lone.escape_dir(Vector3(-5, 0, 0))).is_equal_approx(Vector3(-5, 0, 0), Vector3(0.0001, 0.0001, 0.0001))
	assert_vector(lone.escape_dir(Vector3.ZERO)).is_equal(Vector3.ZERO)


func test_a_second_knock_within_the_settle_never_reverses_the_first() -> void:
	# the rule on its own: the part against the last knock dropped, at least SETTLE_KEEP of the push kept
	assert_float(Player.KNOCK_SETTLE).is_equal_approx(0.45, 0.0001)
	assert_float(Player.SETTLE_KEEP).is_equal_approx(0.35, 0.0001)
	var back := Player.settle_knock(Vector3(-4, 0, 0), Vector3(1, 0, 0))
	assert_float(back.dot(Vector3(1, 0, 0))).is_greater_equal(0.0)
	assert_float(back.length()).is_equal_approx(4.0 * Player.SETTLE_KEEP, 0.001)
	var across := Player.settle_knock(Vector3(0, 0, 4), Vector3(1, 0, 0))
	assert_vector(across).is_equal_approx(Vector3(0, 0, 4), Vector3(0.0001, 0.0001, 0.0001))
	var slant := Player.settle_knock(Vector3(-3, 0, 3), Vector3(1, 0, 0))
	assert_vector(slant).is_equal_approx(Vector3(0, 0, 3), Vector3(0.0001, 0.0001, 0.0001))
	var along := Player.settle_knock(Vector3(2, 0, 1), Vector3(1, 0, 0))
	assert_vector(along).is_equal_approx(Vector3(2, 0, 1), Vector3(0.0001, 0.0001, 0.0001))
	# on the hero: a bite from the left, then one from the right a moment later
	var p := _hero()
	p.hit_knock(Vector3(6, 0, 0))
	assert_float(p._kb.x).is_equal_approx(6.0, 0.0001)
	assert_float(p._settle_t).is_equal_approx(Player.KNOCK_SETTLE, 0.0001)
	p._kb = Vector3.ZERO
	p.hit_knock(Vector3(-6, 0, 0))
	assert_float(p._kb.x).is_greater_equal(0.0)
	assert_float(p._kb.length()).is_greater_equal(6.0 * Player.SETTLE_KEEP - 0.001)
	# the settle over: the next knock is free again
	p._settle_t = 0.0
	p._kb = Vector3.ZERO
	p.hit_knock(Vector3(-6, 0, 0))
	assert_float(p._kb.x).is_equal_approx(-6.0, 0.0001)


func test_a_shots_shove_keeps_its_line() -> void:
	var w := _hero_in_crowd([Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0)])
	var p: Player = w["p"]
	# a hostile shot's push (ProjectileManager passes from_creature false): the way it flew
	assert_bool(p.shove(Vector3(-5, 0, 0), false)).is_true()
	assert_vector(p._kb).is_equal_approx(Vector3(-5, 0, 0), Vector3(0.0001, 0.0001, 0.0001))
	# a creature's (the default): out of the crowd
	p._knock_grace = 0.0
	p._settle_t = 0.0
	p._kb = Vector3.ZERO
	assert_bool(p.shove(Vector3(-5, 0, 0))).is_true()
	assert_float(absf(p._kb.z)).is_greater(4.5)
	# a landed hit: a ranged one keeps its line, a melee one goes out
	p._settle_t = 0.0
	p._kb = Vector3.ZERO
	p._knock_from(Vector3(1, 0, 0), {"knock": 5.0, "kind": "ranged"})
	assert_vector(p._kb).is_equal_approx(Vector3(-5, 0, 0), Vector3(0.0001, 0.0001, 0.0001))
	p._settle_t = 0.0
	p._kb = Vector3.ZERO
	p._knock_from(Vector3(1, 0, 0), {"knock": 5.0, "kind": "melee"})
	assert_float(absf(p._kb.z)).is_greater(4.5)


# ---------------------------------------------------------------- 6. the Tommy Gun's rounds and the Boomstick's pellets

func test_the_pellets_fly_nose_first_and_the_rounds_are_cored_streaks() -> void:
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	# the Boomstick's kind: the Projectile node is turned so the capsule's long axis (Y) lies along the flight (Z),
	# and the mesh is two surfaces, the hot core and its halo, each with its own material (no override)
	var boom := _emitter(w, _inst("boomstick"))
	var bk: Dictionary = pm.kinds[boom.projectile_kind]
	assert_bool(bool(bk["turned"])).is_true()
	var by: Vector3 = (bk["basis"] as Basis).y
	assert_float(absf(by.z)).is_greater(0.99)
	assert_int((bk["mm"] as MultiMesh).mesh.get_surface_count()).is_equal(2)
	assert_object((bk["mmi"] as MultiMeshInstance3D).material_override).is_null()
	# the Tommy Gun's: a box core along -Z inside a capsule halo turned along it
	var tommy := _emitter(w, _inst("tommy_gun"))
	var tk: Dictionary = pm.kinds[tommy.projectile_kind]
	var tmesh: Mesh = (tk["mm"] as MultiMesh).mesh
	assert_int(tmesh.get_surface_count()).is_equal(2)
	var aabb := tmesh.get_aabb()
	assert_float(aabb.size.z).is_greater(aabb.size.x * 4.0)
	assert_float(aabb.size.z).is_greater(aabb.size.y * 4.0)
	# the evolutions share the look
	var chicago := _emitter(w, _inst("chicago_typewriter"))
	assert_int((pm.kinds[chicago.projectile_kind]["mm"] as MultiMesh).mesh.get_surface_count()).is_equal(2)
	var blunder := _emitter(w, _inst("blunderbuss"))
	assert_bool(bool(pm.kinds[blunder.projectile_kind]["turned"])).is_true()
	assert_int((pm.kinds[blunder.projectile_kind]["mm"] as MultiMesh).mesh.get_surface_count()).is_equal(2)
	# streak_mesh on its own: the halo's vertices take the Halo node's turn, and each surface keeps its material
	var core := BoxMesh.new()
	core.size = Vector3(0.1, 0.1, 0.9)
	var halo := CapsuleMesh.new()
	halo.radius = 0.1
	halo.height = 1.1
	var m1 := StandardMaterial3D.new()
	var m2 := StandardMaterial3D.new()
	var turn := Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3.ZERO)
	var out := WeaponBehavior.streak_mesh(core, m1, halo, m2, turn)
	assert_int(out.get_surface_count()).is_equal(2)
	assert_object(out.surface_get_material(0)).is_same(m1)
	assert_object(out.surface_get_material(1)).is_same(m2)
	var hb := out.get_aabb()
	assert_float(hb.size.z).is_greater(1.0)
	assert_float(hb.size.y).is_less(0.3)


func test_tracers_take_the_weapons_step_life_and_size_and_the_pellets_fade_at_the_end() -> void:
	var tp: Dictionary = Registry.weapon("tommy_gun").params
	assert_bool(bool(tp.get("tracer", false))).is_true()
	assert_float(float(tp.get("tracer_step", 0.0))).is_equal_approx(0.016, 0.0001)
	assert_float(float(tp.get("tracer_life", 0.0))).is_equal_approx(0.2, 0.0001)
	assert_float(float(tp.get("tracer_size", 0.0))).is_equal_approx(0.4, 0.0001)
	var bp: Dictionary = Registry.weapon("boomstick").params
	assert_bool(bool(bp.get("tracer", false))).is_true()
	assert_float(float(bp.get("tracer_step", 0.0))).is_equal_approx(0.02, 0.0001)
	assert_float(float(bp.get("tracer_life", 0.0))).is_equal_approx(0.16, 0.0001)
	assert_float(float(bp.get("tracer_size", 0.0))).is_equal_approx(0.32, 0.0001)
	assert_float(float(bp.get("tail_fade", 0.0))).is_equal_approx(0.25, 0.0001)
	# live: a Tommy round drops beads with its own life and size, and they are gone after it
	var w := _world()
	var pm: ProjectileManager = w["pm"]
	var tommy := _emitter(w, _inst("tommy_gun"))
	var i := pm.fire(tommy.projectile_kind, Vector3(0, 0.8, 0), Vector3(0, 0, -22), 3.0, 0, 0.16, 0.5, tommy.inst, 0.0)
	assert_int(i).is_greater_equal(0)
	for k in range(6):
		pm._physics_process(DT)
	var beads := 0
	for k in range(ProjectileManager.TRAIL_MAX):
		if pm.trail_age[k] < pm.trail_life[k]:
			beads += 1
			assert_float(pm.trail_life[k]).is_equal_approx(0.2, 0.0001)
			assert_float(pm.trail_size[k]).is_equal_approx(0.4, 0.0001)
	assert_int(beads).is_greater_equal(3)
	pm._tick_trail(0.1)
	assert_int(pm._trail_mm.visible_instance_count).is_equal(beads)
	pm._tick_trail(0.15)
	assert_int(pm._trail_mm.visible_instance_count).is_equal(0)
	# a spit trail's bead keeps the long life
	pm._drop_trail(Vector3.ZERO)
	var long_lived := 0
	for k in range(ProjectileManager.TRAIL_MAX):
		if pm.trail_age[k] < pm.trail_life[k]:
			long_lived += 1
			assert_float(pm.trail_life[k]).is_equal_approx(ProjectileManager.TRAIL_LIFE, 0.0001)
	assert_int(long_lived).is_equal(1)
	# a pellet: full size until the last quarter of its flight, then shrinking, never under a quarter
	var boom := _emitter(w, _inst("boomstick"))
	var j := pm.fire(boom.projectile_kind, Vector3(0, 0.8, 0), Vector3(0, 0, -16), 6.0, 0, 0.1, 0.4, boom.inst, 0.0)
	assert_int(j).is_greater_equal(0)
	assert_float(float(pm.extra[j]["fade0"])).is_equal_approx(0.4, 0.0001)
	for k in range(6):
		pm._physics_process(DT)
	assert_int(pm.alive[j]).is_equal(1)
	assert_float(pm.psize[j]).is_equal_approx(1.0, 0.0001)
	pm.life[j] = 0.05
	pm._physics_process(DT)
	assert_float(pm.psize[j]).is_equal_approx((0.05 - DT) / 0.1, 0.02)
	pm.life[j] = 0.03
	pm._physics_process(DT)
	assert_int(pm.alive[j]).is_equal(1)
	assert_float(pm.psize[j]).is_equal_approx(0.25, 0.0001)
	# the Tommy round has no fade key: its size never moves
	assert_bool(pm.extra[i].has("fade0")).is_false()


func test_the_muzzle_turns_along_the_aim_and_the_boomstick_flashes_and_smokes() -> void:
	var w := _world()
	var boom := _emitter(w, _inst("boomstick"))
	for nm: String in ["Muzzle", "Flash", "Smoke"]:
		assert_object(boom.visual.get_node_or_null(nm)).override_failure_message(nm).is_not_null()
		assert_bool(boom.visual.get_node(nm) is CPUParticles3D).is_true()
	var at := Vector3(2, 0.8, 1)
	boom.muzzle_flash(at, Vector3(1, 0, 0))
	for nm: String in ["Muzzle", "Flash", "Smoke"]:
		var m: CPUParticles3D = boom.visual.get_node(nm)
		assert_vector(m.global_position).is_equal_approx(at, Vector3(0.001, 0.001, 0.001))
		# look_at points the node's -Z (the particles' direction) along the aim
		var fwd := -m.global_transform.basis.z
		assert_float(fwd.dot(Vector3(1, 0, 0))).override_failure_message(nm).is_greater(0.99)
		assert_bool(m.emitting).is_true()
	# turned again for the next shot the other way
	boom.muzzle_flash(at, Vector3(0, 0, -1))
	var mz: CPUParticles3D = boom.visual.get_node("Muzzle")
	assert_float((-mz.global_transform.basis.z).dot(Vector3(0, 0, -1))).is_greater(0.99)
	# no direction given: moved, left turned as it was
	boom.muzzle_flash(Vector3(0, 0.8, 0))
	assert_float((-mz.global_transform.basis.z).dot(Vector3(0, 0, -1))).is_greater(0.99)
	assert_vector(mz.global_position).is_equal_approx(Vector3(0, 0.8, 0), Vector3(0.001, 0.001, 0.001))
	# the Tommy Gun has its sparks and a flash, no smoke; the Blunderbuss the Boomstick's three
	var tommy := _emitter(w, _inst("tommy_gun"))
	assert_object(tommy.visual.get_node_or_null("Muzzle")).is_not_null()
	assert_object(tommy.visual.get_node_or_null("Flash")).is_not_null()
	assert_object(tommy.visual.get_node_or_null("Smoke")).is_null()
	var blunder := _emitter(w, _inst("blunderbuss"))
	for nm: String in ["Muzzle", "Flash", "Smoke"]:
		assert_object(blunder.visual.get_node_or_null(nm)).override_failure_message(nm).is_not_null()


## After a hit the ramp holds for VENT_HOLD (pass 60, the review: a bite's knock carried the hero a step, which the
## stillness rule read as moving, so the pressure dumped to 0 instead of venting half), then the rule runs again.
func test_a_hit_vents_half_and_the_knock_step_does_not_dump_the_rest() -> void:
	var w := _world()
	var hero: Node3D = w["hero"]
	var inst := _inst("rocket_pod", ["pressure_cooker"])
	var mp := _pod(w, inst)
	hero.set("still", true)
	mp.pressure = 1.0
	mp.note_hit()
	assert_float(mp.pressure).is_equal_approx(0.5, 0.0001)
	# the knock's step: not still for a third of a second, the pressure keeps
	hero.set("still", false)
	for k in range(20):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.5, 0.0001)
	# standing again before the hold ends: it neither climbs nor dumps until the hold is over
	hero.set("still", true)
	for k in range(20):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.5, 0.0001)
	# the hold over and still standing: it climbs again
	for k in range(60):
		mp._tick(DT)
	assert_float(mp.pressure).is_greater(0.5)
	# the hold over and walking: out
	hero.set("still", false)
	mp.note_hit()
	for k in range(int(MissilePod.VENT_HOLD / DT) + 2):
		mp._tick(DT)
	assert_float(mp.pressure).is_equal_approx(0.0, 0.0001)
	# a vent never leaves a sliver that puffs steam for ever
	mp.pressure = 0.03
	mp.note_hit()
	assert_float(mp.pressure).is_equal_approx(0.0, 0.0001)
