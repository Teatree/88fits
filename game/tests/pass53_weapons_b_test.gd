extends GdUnitTestSuite

## Pass 53, lane W2 (Garry's list): the Sabre, the Spear, the Tumbleweed and the Boomstick redone, and the companion glow.
## The Boomstick fires only with a creature in its reach (the Blunderbuss blasts blind); Flurry doubles the slices with no
## cut, Critical Thinking lifts every weapon's crit chance, the Whirlwind spins full circles and its crits refund the
## cooldown; Wide Sweep sweeps every spear in one stroke, Stunning Thrust stuns, Long Spear reaches further and slower,
## the thrust has bite (wind-back, eased out, hit-stop, flex, streak), the Thunder Lance alternates a sweep and a thrust
## and punishes the stunned; Thorny Weed is heavier, Dust Wake and the Dust Devil carry their numbers and the weed is the
## desert's own model with a dust ring under it; every dim companion material glows a little.

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
func fx_sand(_a, _b = 1.0) -> void:
	pass
func fx_ignite(_a, _b = 1.0, _c = false) -> void:
	pass
func fx_lightning(_points) -> void:
	pass
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
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func shove(_v: Vector3) -> bool:
	return true
func apply_knockback(_v: Vector3) -> void:
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
"""

const DT := 1.0 / 60.0

## the old picks hidden in place -> their family
const HIDDEN_W2 := {"flame_blade": "sabre", "venom_tip": "pike", "phalanx": "pike", "thorny_weed": "tumbleweed", "weed_storm": "tumbleweed"}
## the new picks -> [family, the slot they fill]
const NEW_W2 := {"critical_thinking": ["sabre", "element"], "stunning_thrust": ["pike", "element"], "long_spear": ["pike", "volume"],
	"thorns": ["tumbleweed", "element"], "dust_wake": ["tumbleweed", "volume"]}
## every base's path, element / volume / motion
const PATHS := {"sabre": ["critical_thinking", "flurry", "riposte"], "pike": ["stunning_thrust", "long_spear", "pike_sweep"],
	"tumbleweed": ["thorns", "dust_wake", "boomerang"]}
## base -> [the new evolution, the old one hidden in place, the behaviour]
const EVOLUTIONS := {"sabre": ["whirlwind", "zweihander", "Thruster"], "pike": ["thunder_lance", "halberd", "Thruster"],
	"tumbleweed": ["dust_devil", "stampede", "ProjectileEmitter"]}


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.base_crit = false
	Run.debug_clear_items()
	Run.end()


## A fake game round a fake hero at the origin, with the real crowd, shots, effects and ground marks.
func _world() -> Dictionary:
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	var hip := Node3D.new()
	hero.add_child(hip)
	hero.set("hip", hip)
	g.player = hero
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
	var cam := Node.new()
	cam.set_script(_script(FAKE_CAMERA))
	g.add_child(cam)
	g.camera = cam
	em._rebuild_grid()
	return {"g": g, "hero": hero, "em": em, "pm": pm, "fx": fx}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _behaviour(w: Dictionary, b: WeaponBehavior, id: String, muts: Array = [], level := 1) -> WeaponBehavior:
	(w["g"] as Node).add_child(b)
	b.setup(_inst(id, muts, level), w["g"])
	return b


func _thruster(w: Dictionary, id: String, muts: Array = [], level := 1) -> Thruster:
	return _behaviour(w, Thruster.new(), id, muts, level) as Thruster


func _emitter(w: Dictionary, id: String, muts: Array = [], level := 1) -> ProjectileEmitter:
	return _behaviour(w, ProjectileEmitter.new(), id, muts, level) as ProjectileEmitter


## A tough creature standing where it was put (a skeleton: never a boss or an Elite, so it can be stunned).
func _creature(em: EnemyManager, at: Vector3, hp_mult := 50.0, id := "skeleton") -> int:
	var i := em.spawn(id, at, null, 1.0, hp_mult)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	em.refresh_crowd_stats()
	return i


## Sets params[key][sub] on this weapon alone (a mutation's block in WeaponInstance.params is a copy, but never written into).
func _set_param(inst: WeaponInstance, key: String, sub: String, value: Variant) -> void:
	var d: Dictionary = (inst.params.get(key, {}) as Dictionary).duplicate(true)
	d[sub] = value
	inst.params[key] = d


## What a hit of `amount` takes off creature `i` (its damage reduction in).
func _taken(em: EnemyManager, i: int, amount: float) -> float:
	return amount * (1.0 - em.dr[i])


func _live_shots(pm: ProjectileManager) -> int:
	var n := 0
	for j in range(ProjectileManager.MAX):
		if pm.alive[j] == 1:
			n += 1
	return n


## Ticks the blade until its stroke is over; returns the seconds it took (-1 when it never ended).
func _run_stroke(t: Thruster, max_s := 3.0) -> float:
	var s := 0.0
	while t.stroke_running() and s < max_s:
		t._tick(DT)
		s += DT
	return s if not t.stroke_running() else -1.0


# ---------------------------------------------------------------- the content

func test_old_picks_hidden_new_picks_in_their_slots_evolutions_repointed() -> void:
	for id: String in HIDDEN_W2.keys():
		var m: MutationDef = Registry.mutation(id)
		assert_object(m).override_failure_message(id + " is gone").is_not_null()
		assert_bool(m.hidden).override_failure_message(id + " shows").is_true()
		assert_str(m.weapon).is_equal(str(HIDDEN_W2[id]))
		assert_bool(Registry.mutations_of(m.weapon).has(m)).override_failure_message(id + " is on the path").is_false()
	for id: String in NEW_W2.keys():
		var m: MutationDef = Registry.mutation(id)
		assert_object(m).override_failure_message(id + " is missing").is_not_null()
		assert_str(m.weapon).override_failure_message(id).is_equal(str(NEW_W2[id][0]))
		assert_str(m.mutation_kind).override_failure_message(id).is_equal(str(NEW_W2[id][1]))
		assert_str(m.rarity).is_equal("rare")
		assert_float(m.weight).is_equal(8.0)
		assert_str(m.text).override_failure_message(id + " says nothing").is_not_empty()
		assert_bool(m.hidden or m.is_hero()).is_false()
		# the element-slot picks carry no element: nothing burns or poisons
		for e in m.effects:
			assert_bool(str((e as Effect).stat).begins_with("fire") or str((e as Effect).stat).begins_with("poison")).override_failure_message(id + " carries an element").is_false()
	for fam: String in PATHS.keys():
		var path: Array = Registry.mutations_of(fam)
		assert_array(path.map(func(m: MutationDef) -> String: return m.id)).override_failure_message(fam).is_equal(PATHS[fam])
		assert_array(path.map(func(m: MutationDef) -> String: return m.mutation_kind)).is_equal(["element", "volume", "motion"])
	for base: String in EVOLUTIONS.keys():
		var b: WeaponDef = Registry.weapon(base)
		var new_id: String = EVOLUTIONS[base][0]
		var old_id: String = EVOLUTIONS[base][1]
		assert_str(b.evolves_into).override_failure_message(base).is_equal(new_id)
		var evo: WeaponDef = Registry.weapon(new_id)
		assert_object(evo).override_failure_message(new_id).is_not_null()
		assert_bool(evo.is_evolution).is_true()
		assert_str(evo.evolved_from).is_equal(base)
		assert_int(evo.max_level).is_equal(1)
		assert_str(evo.behavior).is_equal(str(EVOLUTIONS[base][2]))
		assert_str(evo.targeting).is_equal("priority")
		assert_bool(Registry.is_hidden(evo)).override_failure_message(new_id + " hidden").is_false()
		assert_object(evo.visual).override_failure_message(new_id + " has no visual").is_not_null()
		assert_str(evo.flavour).override_failure_message(new_id + " has no flavour").is_not_empty()
		var old: WeaponDef = Registry.weapon(old_id)
		assert_object(old).override_failure_message(old_id + " is gone").is_not_null()
		assert_bool(old.hidden).override_failure_message(old_id + " shows").is_true()
		assert_bool(Registry.is_hidden(old)).is_true()
	# Thorny Weed: same name, same image (Garry), under its new id
	var thorns: MutationDef = Registry.mutation("thorns")
	assert_str(thorns.display_name).is_equal("Thorny Weed")
	assert_bool(thorns.has_icon()).is_true()
	assert_bool(FileAccess.get_file_as_bytes("res://content/mutations/thorns/thorns_icon.png") == FileAccess.get_file_as_bytes("res://content/mutations/thorny_weed/thorny_weed_icon.png")).is_true()


func test_flurry_doubles_the_slices_without_touching_the_cut() -> void:
	var f: MutationDef = Registry.mutation("flurry")
	assert_str(f.text).is_equal("Twice the slices a stroke.")
	assert_int(f.effects.size()).is_equal(1)
	assert_str((f.effects[0] as Effect).stat).is_equal("amount")
	assert_str((f.effects[0] as Effect).op).is_equal("mul")
	Run.add_weapon(Registry.weapon("sabre"), 3)
	var w := Run.weapon_instance("sabre")
	var amount0 := w.stat_int("amount", 0)
	var dmg0 := w.stat("damage", 0.0)
	assert_bool(Run.add_mutation("flurry")).is_true()
	assert_int(w.stat_int("amount", 0)).is_equal(amount0 * 2)
	assert_float(w.stat("damage", 0.0)).is_equal_approx(dmg0, 0.0001)


func test_critical_thinking_lifts_every_weapons_crit_chance() -> void:
	var m: MutationDef = Registry.mutation("critical_thinking")
	assert_str(m.text).is_equal("+10% critical hit chance for every weapon.")
	assert_int(m.player_effects().size()).is_equal(1)
	assert_int(m.weapon_effects().size()).is_equal(0)
	# the real base crit (the suites leave it out), like pass52_test
	Run.base_crit = true
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).is_equal_approx(0.01, 0.0001)
	Run.add_weapon(Registry.weapon("sabre"), 3)
	Run.add_weapon(Registry.weapon("peashooter"), 1)
	assert_bool(Run.add_mutation("critical_thinking")).is_true()
	# on the hero's sheet, which EnemyManager.damage reads for every weapon's hit; nothing on the sabre's own sheet
	assert_float(Run.player_sheet.get_stat("crit_chance", 0.0)).is_equal_approx(0.11, 0.0001)
	assert_bool(Run.weapon_instance("sabre").sheet.has_stat("crit_chance")).is_false()
	assert_bool(Run.weapon_instance("peashooter").sheet.has_stat("crit_chance")).is_false()


# ---------------------------------------------------------------- the Boomstick

func test_the_boomstick_fires_only_with_a_creature_in_reach_the_blunderbuss_blind() -> void:
	assert_bool(FileAccess.get_file_as_string("res://core/behaviors/ProjectileEmitter.gd").contains("fires nothing when nothing is near")).is_true()
	assert_bool(Registry.weapon("boomstick").params.has("fire_blind")).is_false()
	var bb: WeaponDef = Registry.weapon("blunderbuss")
	assert_bool(bool((bb.params.get("final", {}) as Dictionary).get("fire_blind", false))).is_true()
	assert_bool(bool(_inst("blunderbuss").params.get("fire_blind", false))).is_true()
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	var boom := _emitter(w, "boomstick")
	assert_str(boom.inst.def.targeting).is_equal("forward")
	# nobody near: no shot
	assert_bool(boom._fire()).is_false()
	assert_int(_live_shots(pm)).is_equal(0)
	# a creature in reach: the whole volley
	var i := _creature(em, Vector3(3.0, 0, 0))
	assert_bool(boom._fire()).is_true()
	assert_int(_live_shots(pm)).is_equal(boom.stat_int("amount", 0))
	assert_float(boom._aim_dir.dot(Vector3(1, 0, 0))).is_greater(0.99)
	# the Blunderbuss blasts its cone on its clock with nobody there
	em.alive[i] = 0
	em._rebuild_grid()
	var pm2 := _live_shots(pm)
	var blunder := _emitter(w, "blunderbuss", ["dragons_breath", "birdshot_lane", "both_barrels"])
	assert_bool(blunder.inst.blast().is_empty()).is_false()
	assert_bool(blunder._fire()).is_true()
	assert_int(blunder.blasts).is_equal(1)
	assert_int(_live_shots(pm)).is_greater(pm2)   # the cone's ghost pellets


# ---------------------------------------------------------------- the Sabre and the Whirlwind

func test_the_whirlwind_spins_full_circles_and_a_crit_refunds_the_cooldown() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "whirlwind", ["critical_thinking", "flurry", "riposte"])
	# four swings doubled by Flurry, strokes a quarter faster by Riposte, each swing a full circle
	assert_int(t.stat_int("amount", 0)).is_equal(8)
	assert_float(t.stat("cooldown", 0.0)).is_equal_approx(0.9 * 0.75, 0.0001)
	assert_bool(t._slices()).is_true()
	assert_bool(t._blades_sweep()).is_false()
	assert_float(t._edge(0, 0.0)).is_equal_approx(-PI, 0.001)
	assert_float(t._edge(0, 1.0)).is_equal_approx(PI, 0.001)
	assert_float(t._edge(1, 0.0)).is_equal_approx(PI, 0.001)
	assert_float(float(t.inst.params.get("crit_refund", 0.0))).is_equal_approx(0.2, 0.0001)
	assert_bool(t._trail_colour().is_equal_approx(Color("#A8F0FF"))).is_true()
	for word in ["Flurry", "Riposte", "Critical Thinking"]:
		assert_str(Registry.weapon("whirlwind").flavour).contains(word)
	assert_str(t.inst.description()).contains("360°")
	# every hit a crit: every swing gives a fifth of the cooldown back
	Run.player_sheet.set_base("crit_chance", 1.0)
	var i := _creature(em, Vector3(2.5, 0, 0), 100.0)
	var hp0: float = em.hp[i]
	assert_bool(t._fire()).is_true()
	assert_int(t.sweeps).is_equal(1)
	var s := 0.0
	while t.refunds < 1 and s < 2.0:
		t._tick(DT)
		s += DT
	assert_int(t.refunds).is_equal(1)
	assert_float(t.cooldown_left).is_equal_approx(-0.2 * t.stat("cooldown", 1.0), 0.001)
	assert_float(em.hp[i]).is_less(hp0)
	assert_float(_run_stroke(t)).is_greater(0.0)
	assert_int(t.refunds).is_equal(8)
	assert_float(t.cooldown_left).is_equal_approx(-8 * 0.2 * t.stat("cooldown", 1.0), 0.001)
	# eight swings, eight crits, eight cuts
	assert_float(hp0 - em.hp[i]).is_equal_approx(_taken(em, i, 8.0 * t.stat("damage", 0.0) * Run.player_sheet.get_stat("crit_damage", 2.0)), 0.01)
	# the next stroke follows the moment this one ends when the cooldown came round first
	t.cooldown_left = -1.0
	assert_bool(t._fire()).is_true()


# ---------------------------------------------------------------- the Spear

func test_wide_sweep_sweeps_every_spear_in_one_stroke_and_cuts_each_creature_once() -> void:
	var ws: MutationDef = Registry.mutation("pike_sweep")
	assert_str(ws.text).is_equal("A 120° sweep like a sabre's, with less knockback.")
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike", ["pike_sweep"], 5)
	assert_int(t.stat_int("amount", 0)).is_equal(2)
	assert_bool(t._slices()).is_true()
	assert_bool(t._blades_sweep()).is_true()
	assert_float(deg_to_rad(float(t.inst.params["thrust"]["slice_deg"]))).is_equal_approx(deg_to_rad(120.0), 0.0001)
	# -40% knockback over the Spear's own (+30% at level 3; the sheet multiplies: 12 x 1.3 x 0.6)
	assert_float(t.stat("knockback", 0.0)).is_equal_approx(12.0 * 1.3 * 0.6, 0.001)
	var i := _creature(em, Vector3(3.0, 0, 0))
	var hp0: float = em.hp[i]
	assert_bool(t._fire()).is_true()
	assert_int(t.sweeps).is_equal(1)
	assert_int(t.thrusts).is_equal(0)
	# both spears out at once, each leaving its own crescent
	for k in range(15):
		t._tick(DT)
	assert_int(t._blades.size()).is_equal(2)
	assert_bool(t._blades[0].visible and t._blades[1].visible).is_true()
	assert_float(_run_stroke(t)).is_greater(0.0)
	assert_int(t._trails.size()).is_equal(2)
	# one stroke, one cut on the creature both blades passed
	assert_float(hp0 - em.hp[i]).is_equal_approx(_taken(em, i, t.stat("damage", 0.0)), 0.01)
	assert_int(t.strokes).is_equal(1)


func test_stunning_thrust_stuns_when_the_roll_says_so() -> void:
	var st: MutationDef = Registry.mutation("stunning_thrust")
	assert_str(st.text).is_equal("Every hit has a 15% chance to stun for a second.")
	var stun: Dictionary = st.params["thrust"]["stun"]
	assert_float(float(stun["chance"])).is_equal_approx(0.15, 0.0001)
	assert_float(float(stun["seconds"])).is_equal_approx(1.0, 0.0001)
	var w := _world()
	var em: EnemyManager = w["em"]
	if not em.has_method("stun"):
		push_warning("EnemyManager.stun is not there yet (the WD lane): the stun roll is not checked")
		return
	var i := _creature(em, Vector3(3.0, 0, 0))
	# chance 1: the thrust stuns for the second
	var t := _thruster(w, "pike", ["stunning_thrust"])
	_set_param(t.inst, "thrust", "stun", {"chance": 1.0, "seconds": 1.0})
	assert_bool(t._fire()).is_true()
	var s := 0.0
	while not t._hit_done and s < 1.0:
		t._tick(DT)
		s += DT
	assert_bool(t._hit_done).is_true()
	assert_bool(em.is_stunned(i)).is_true()
	assert_float(em.stun_t[i]).is_equal_approx(1.0, 0.01)
	assert_int(t.stuns).is_equal(1)
	assert_float(_run_stroke(t)).is_greater(0.0)
	# chance 0: never
	em.stun_t[i] = 0.0
	var t0 := _thruster(w, "pike", ["stunning_thrust"])
	_set_param(t0.inst, "thrust", "stun", {"chance": 0.0, "seconds": 1.0})
	assert_bool(t0._fire()).is_true()
	assert_float(_run_stroke(t0)).is_greater(0.0)
	assert_bool(t0._hit_done).is_true()
	assert_int(t0.stuns).is_equal(0)
	assert_bool(em.is_stunned(i)).is_false()


func test_long_spear_reaches_further_and_strokes_slower() -> void:
	var ls: MutationDef = Registry.mutation("long_spear")
	assert_str(ls.text).is_equal("+40% reach, strokes 15% slower.")
	var plain := _inst("pike")
	var long := _inst("pike", ["long_spear"])
	assert_float(long.stat("range", 0.0)).is_equal_approx(plain.stat("range", 0.0) * 1.4, 0.001)
	assert_float(long.stat("cooldown", 0.0)).is_equal_approx(plain.stat("cooldown", 0.0) * 1.15, 0.001)
	assert_float(long.stat("damage", 0.0)).is_equal_approx(plain.stat("damage", 0.0), 0.001)


func test_the_thrust_has_bite_wind_back_then_out_then_a_hit_stop() -> void:
	assert_float(Thruster.WINDBACK).is_equal_approx(0.05, 0.0001)
	assert_float(Thruster.WINDBACK_FRAC).is_equal_approx(0.2, 0.0001)
	assert_float(Thruster.HITSTOP).is_equal_approx(0.04, 0.0001)
	assert_float(Thruster.FLEX).is_equal_approx(1.06, 0.0001)
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "pike")
	assert_bool(t._slices()).is_false()
	var reach := t.stat("range", 0.0)
	var i := _creature(em, Vector3(3.0, 0, 0))
	var hp0: float = em.hp[i]
	assert_bool(t._fire()).is_true()
	assert_int(t.thrusts).is_equal(1)
	# wound back: a short length of blade pulled behind the hero's centre, nothing hit yet
	t._tick(0.02)
	var blade: Node3D = t._blades[0]
	assert_bool(blade.visible).is_true()
	assert_float(blade.scale.z).is_equal_approx(0.3 * reach, 0.01)
	assert_float(blade.global_position.x).is_less(-0.1)
	assert_bool(t._hit_done).is_false()
	assert_float(em.hp[i]).is_equal_approx(hp0, 0.0001)
	# out: the hit lands at full reach, the shaft flexes past its length, the streak hangs behind the tip, the hold grows
	var s := 0.02
	while not t._hit_done and s < 1.0:
		t._tick(DT)
		s += DT
	assert_bool(t._hit_done).is_true()
	assert_float(s).is_between(0.2, 0.26)
	# pass 62: a lone creature on the thrust is its first, so it takes the pierce drop-off's first_mult
	var first := ProjectileManager.falloff_factor(ProjectileManager.weapon_falloff(t.inst), 1)
	assert_float(hp0 - em.hp[i]).is_equal_approx(_taken(em, i, t.stat("damage", 0.0) * first), 0.01)
	assert_float(t._hold_extra).is_equal_approx(Thruster.HITSTOP, 0.0001)
	assert_float(blade.scale.z).is_greater(reach * 1.02)
	assert_float(blade.global_position.x).is_equal_approx(0.0, 0.01)
	assert_int(t._streak_p.size()).is_greater_equal(2)
	# back: the stroke ends wind-back + out + hold + hit-stop + back later, one hit in all
	var rest := _run_stroke(t)
	assert_float(rest).is_greater(0.0)
	assert_float(s + rest).is_between(0.6, 0.74)
	assert_float(hp0 - em.hp[i]).is_equal_approx(_taken(em, i, t.stat("damage", 0.0) * first), 0.01)
	# nobody in reach: no stroke at all
	em.alive[i] = 0
	em._rebuild_grid()
	assert_bool(t._fire()).is_false()


func test_the_thunder_lance_sweeps_then_thrusts_and_punishes_the_stunned() -> void:
	assert_float(Thruster.ALTERNATE_KNOCK).is_equal_approx(1.5, 0.0001)
	var w := _world()
	var em: EnemyManager = w["em"]
	var t := _thruster(w, "thunder_lance", ["stunning_thrust", "long_spear", "pike_sweep"])
	# its own numbers win over the path it carries (final.thrust): 140 degrees, every hit stuns 0.8 s, two lances a stroke
	var th: Dictionary = t.inst.params["thrust"]
	assert_float(float(th["slice_deg"])).is_equal_approx(140.0, 0.0001)
	assert_float(float(th["slice"])).is_equal_approx(0.18, 0.0001)
	assert_float(float(th["stun"]["chance"])).is_equal_approx(1.0, 0.0001)
	assert_float(float(th["stun"]["seconds"])).is_equal_approx(0.8, 0.0001)
	assert_str(str(th["amount_mode"])).is_equal("blades")
	assert_bool(bool(th["alternate"])).is_true()
	assert_bool(bool(th["crackle"])).is_true()
	assert_float(float(t.inst.params.get("stunned_mult", 0.0))).is_equal_approx(1.5, 0.0001)
	assert_float(t.stat("range", 0.0)).is_equal_approx(6.4 * 1.4, 0.001)
	assert_int(t.stat_int("amount", 0)).is_equal(2)
	assert_str(t.inst.description()).contains("140°")
	for word in ["sweep", "thrust", "stun"]:
		assert_str(Registry.weapon("thunder_lance").flavour.to_lower()).contains(word)
	if not em.has_method("stun"):
		push_warning("EnemyManager.stun is not there yet (the WD lane): the stunned_mult is not checked")
		return
	var i := _creature(em, Vector3(2.5, 0, 0), 100.0)
	var hp0: float = em.hp[i]
	assert_bool(t._fire()).is_true()
	assert_int(t.strokes).is_equal(1)
	assert_int(t.sweeps).is_equal(1)
	assert_int(t.thrusts).is_equal(0)
	assert_int(t._combo).is_equal(1)
	# the sweep: one cut at x1 (not stunned yet), the stun, one crackle from the tip
	var s := 0.0
	while t.thrusts < 1 and s < 3.0:
		t._tick(DT)
		s += DT
	assert_int(t.thrusts).is_equal(1)
	assert_int(t._combo).is_equal(2)
	assert_bool(t.stroke_running()).is_true()
	var hp1: float = em.hp[i]
	assert_float(hp0 - hp1).is_equal_approx(_taken(em, i, t.stat("damage", 0.0)), 0.01)
	assert_bool(em.is_stunned(i)).is_true()
	assert_int(t.stuns).is_equal(1)
	assert_int(t.crackles).is_equal(1)
	# the thrust straight after it: x1.5 on the stunned creature
	assert_float(_run_stroke(t)).is_greater(0.0)
	assert_int(t._combo).is_equal(0)
	var hp2: float = em.hp[i]
	# pass 62: the thrust's lone creature is its first (the pierce drop-off's first_mult); the sweep is a slice, untouched
	var first := ProjectileManager.falloff_factor(ProjectileManager.weapon_falloff(t.inst), 1)
	assert_float(hp1 - hp2).is_equal_approx(1.5 * first * (hp0 - hp1), 0.01)
	assert_int(t.strokes).is_equal(1)


# ---------------------------------------------------------------- the Tumbleweed and the Dust Devil

func test_thorny_weed_dust_wake_and_the_dust_devil_carry_their_numbers() -> void:
	var plain := _inst("tumbleweed")
	var th := _inst("tumbleweed", ["thorns"])
	assert_float(th.stat("damage", 0.0)).is_equal_approx(plain.stat("damage", 0.0) * 1.35, 0.001)
	assert_float(float(th.params.get("out_speed_mult", 0.0))).is_equal_approx(0.7, 0.0001)
	assert_float(float(th.params.get("back_speed_mult", 0.0))).is_equal_approx(1.4, 0.0001)
	assert_str(Registry.mutation("thorns").text).is_equal("Heavier and thornier: +35% damage. It rolls out slower and comes back faster.")
	var dw := _inst("tumbleweed", ["dust_wake"])
	var aura: Dictionary = dw.params["aura"]
	assert_float(float(aura["radius"])).is_equal_approx(1.6, 0.0001)
	assert_float(float(aura["slow"])).is_equal_approx(0.2, 0.0001)
	assert_float(float(aura["seconds"])).is_equal_approx(0.4, 0.0001)
	assert_float(float(aura["every"])).is_equal_approx(0.2, 0.0001)
	assert_str(str(aura["tint"])).is_equal("#1A5A1E")
	assert_str(Registry.mutation("dust_wake").text).is_equal("A faint dust wake: enemies within 1.6 m are slowed a little.")
	# the Dust Devil over the whole path: its own speed, wake and return win (final), the second pass and x2 home
	var dd := _inst("dust_devil", ["thorns", "dust_wake", "boomerang"])
	assert_bool(bool(dd.params.get("return", false))).is_true()
	assert_float(float(dd.params.get("out_speed_mult", 0.0))).is_equal_approx(0.8, 0.0001)
	assert_float(float(dd.params.get("back_speed_mult", 0.0))).is_equal_approx(1.5, 0.0001)
	var da: Dictionary = dd.params["aura"]
	assert_float(float(da["radius"])).is_equal_approx(2.6, 0.0001)
	assert_float(float(da["slow"])).is_equal_approx(0.35, 0.0001)
	assert_float(float(da["pull"])).is_equal_approx(2.5, 0.0001)
	assert_str(str(da["tint"])).is_equal("#1A5A1E")
	assert_float(float(dd.params.get("return_damage_mult", 0.0))).is_equal_approx(2.0, 0.0001)
	assert_bool(bool(dd.params.get("second_pass", false))).is_true()
	assert_float(float(dd.params.get("radius", 0.0))).is_equal_approx(0.9, 0.0001)
	assert_float(dd.stat("damage", 0.0)).is_equal_approx(30.0 * 1.35, 0.001)
	assert_int(dd.stat_int("amount", 0)).is_equal(3)
	for word in ["back", "wake", "slow", "pull"]:
		assert_str(Registry.weapon("dust_devil").flavour.to_lower()).contains(word)


func test_the_weed_is_the_deserts_own_model_with_a_dust_ring_under_it() -> void:
	# the base weapon's shot: art/props/tumbleweed.glb, drawn 0.55-0.7 m across its radius
	# pass 54: art/props/tumbleweed_dark.glb (the same tangle in dark brown with thicker wires: the tan weed vanished on
	# the sand), as wide, with a faint glow of its own colour (this needs the GLB imported)
	var vis: Node = auto_free(Registry.weapon("tumbleweed").visual.instantiate())
	var src := WeaponBehavior.projectile_source(vis)
	assert_object(src).is_not_null()
	assert_str(src.name).is_equal("tumbleweed")
	var wm := src.material_override as StandardMaterial3D
	assert_bool(wm != null and wm.albedo_color.is_equal_approx(Color8(74, 46, 24)) and wm.emission_enabled).is_true()
	assert_bool(src.mesh is ArrayMesh).is_true()
	var mesh_r: float = src.mesh.get_aabb().size.x * 0.5
	assert_float(mesh_r).is_between(0.75, 0.95)
	var drawn: float = mesh_r * (vis.get_node("Projectile") as Node3D).scale.x * src.scale.x * ProjectileManager.CHUNK
	assert_float(drawn).is_between(0.55, 0.7)
	assert_int((vis.get_node("Ring") as Node).get_child_count()).is_equal(6)
	# the Dust Devil's: the same model in jet black, as big as it hits
	var dvis: Node = auto_free(Registry.weapon("dust_devil").visual.instantiate())
	var dsrc := WeaponBehavior.projectile_source(dvis)
	assert_object(dsrc).is_not_null()
	assert_bool(dsrc.material_override is StandardMaterial3D).is_true()
	assert_bool((dsrc.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.035, 0.03, 0.03))).is_true()
	var ddrawn: float = dsrc.mesh.get_aabb().size.x * 0.5 * (dvis.get_node("Projectile") as Node3D).scale.x * ProjectileManager.CHUNK
	assert_float(ddrawn).is_between(0.8, 1.0)
	var ring: Node = dvis.get_node("Ring")
	assert_int(ring.get_child_count()).is_equal(6)
	var dash := ring.get_child(0) as MeshInstance3D
	var dm := dash.material_override as StandardMaterial3D
	assert_object(dm).is_not_null()
	assert_int(dm.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_float(dm.albedo_color.a).is_equal_approx(0.35, 0.001)
	assert_float(dm.albedo_color.g).is_greater(dm.albedo_color.r * 2.0)
	# in play: a weed with Dust Wake drags one ring per shot in flight; without the aura none
	var w := _world()
	var em: EnemyManager = w["em"]
	var pm: ProjectileManager = w["pm"]
	_creature(em, Vector3(5.0, 0, 0))
	var plain := _emitter(w, "tumbleweed")
	assert_bool(plain._fire()).is_true()
	plain._tick(DT)
	assert_int(plain.ring_count()).is_equal(0)
	assert_bool((plain.visual.get_node("Ring") as Node3D).visible).is_false()
	var wake := _emitter(w, "tumbleweed", ["dust_wake"], 3)
	assert_int(wake.stat_int("amount", 0)).is_equal(2)
	assert_bool(wake._fire()).is_true()
	wake._tick(DT)
	assert_int(wake.ring_count()).is_equal(2)
	assert_bool((wake.visual.get_node("Ring") as Node3D).visible).is_false()
	# the shot is drawn with the model's kind, at the visual's scale
	var kd: Dictionary = pm.kinds[wake.projectile_kind]
	assert_bool((kd["mm"] as MultiMesh).mesh is ArrayMesh).is_true()
	assert_float(float(kd["scale"])).is_equal_approx(0.55 * ProjectileManager.CHUNK, 0.001)


# ---------------------------------------------------------------- the companion glow

func test_dim_companion_materials_glow_and_emitting_ones_are_left_alone() -> void:
	assert_float(WeaponBehavior.GLOW).is_equal_approx(0.45, 0.0001)
	var root: Node3D = auto_free(Node3D.new())
	var held := Node3D.new()
	held.name = "Held"
	root.add_child(held)
	var dim := StandardMaterial3D.new()
	dim.albedo_color = Color(0.5, 0.3, 0.1)
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	a.material_override = dim
	held.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.material_override = dim
	held.add_child(b)
	var lit := StandardMaterial3D.new()
	lit.emission_enabled = true
	lit.emission = Color.RED
	lit.emission_energy_multiplier = 2.0
	var c := MeshInstance3D.new()
	c.mesh = BoxMesh.new()
	c.material_override = lit
	held.add_child(c)
	var surf := StandardMaterial3D.new()
	surf.albedo_color = Color(0.2, 0.6, 0.9)
	var dmesh := BoxMesh.new()
	dmesh.material = surf
	var d := MeshInstance3D.new()
	d.mesh = dmesh
	held.add_child(d)
	var fam := Node3D.new()
	fam.name = "Familiar"
	root.add_child(fam)
	var textured := StandardMaterial3D.new()
	textured.albedo_texture = PlaceholderTexture2D.new()
	var e := MeshInstance3D.new()
	e.mesh = BoxMesh.new()
	e.material_override = textured
	fam.add_child(e)
	var blade := Node3D.new()
	blade.name = "Blade"
	root.add_child(blade)
	var f := MeshInstance3D.new()
	f.mesh = BoxMesh.new()
	f.material_override = dim.duplicate()
	blade.add_child(f)
	assert_int(WeaponBehavior.glow_companions(root, 0.45)).is_equal(4)
	# a lit copy, the original untouched, shared by the parts that shared the material
	var ga := a.material_override as StandardMaterial3D
	assert_bool(ga != dim).is_true()
	assert_bool(ga.emission_enabled).is_true()
	assert_bool(ga.emission.is_equal_approx(Color(0.5, 0.3, 0.1))).is_true()
	assert_float(ga.emission_energy_multiplier).is_equal_approx(0.45, 0.0001)
	assert_bool(b.material_override == ga).is_true()
	assert_bool(dim.emission_enabled).is_false()
	# one that already emits is the very same material, as strong as it was
	assert_bool(c.material_override == lit).is_true()
	assert_float(lit.emission_energy_multiplier).is_equal_approx(2.0, 0.0001)
	# a surface material goes on as a surface override, the mesh's own untouched
	var gd := d.get_surface_override_material(0) as StandardMaterial3D
	assert_object(gd).is_not_null()
	assert_bool(gd.emission_enabled).is_true()
	assert_bool(surf.emission_enabled).is_false()
	# a textured one glows white
	assert_bool((e.material_override as StandardMaterial3D).emission.is_equal_approx(Color.WHITE)).is_true()
	# a blade is neither companion nor held gun
	assert_bool((f.material_override as StandardMaterial3D).emission_enabled).is_false()
	# through a weapon: the Boomstick's steel and wood glow (merged parts keep the lit copy); params.glow 0 turns it off
	var w := _world()
	var boom := _emitter(w, "boomstick")
	var meshes: Array = boom.visual.get_node("Held").find_children("*", "MeshInstance3D", true, false)
	assert_int(meshes.size()).is_greater(0)
	for m: MeshInstance3D in meshes:
		var sm := m.material_override as StandardMaterial3D
		assert_object(sm).override_failure_message(str(m.name)).is_not_null()
		assert_bool(sm.emission_enabled).override_failure_message(str(m.name) + " is dim").is_true()
		assert_float(sm.emission_energy_multiplier).is_equal_approx(0.45, 0.0001)
	var off_inst := _inst("boomstick")
	off_inst.params["glow"] = 0.0
	var off := ProjectileEmitter.new()
	(w["g"] as Node).add_child(off)
	off.setup(off_inst, w["g"])
	for m: MeshInstance3D in off.visual.get_node("Held").find_children("*", "MeshInstance3D", true, false):
		assert_bool((m.material_override as StandardMaterial3D).emission_enabled).override_failure_message(str(m.name) + " glows with glow 0").is_false()
	# a blade's materials are not a companion's: the Sabre's visual is left as it is
	var sabre_vis: Node = auto_free(Registry.weapon("sabre").visual.instantiate())
	assert_int(WeaponBehavior.glow_companions(sabre_vis, 0.45)).is_equal(0)
