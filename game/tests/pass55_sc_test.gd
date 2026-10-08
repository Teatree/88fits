extends GdUnitTestSuite

## Pass 55, lane SC: the Sun Scepter's looks (Garry, 2026-10-06). The sceptre is 30% smaller; every strike called shakes
## the whole of it and flares its sunburst, which is hidden at rest on the plain sceptre (the shine at 45% of its old
## size is the glint now; no crossed bars) and shines all the time on Zenith, flaring harder on a strike and hardest on
## the sweep. No floating emblems on the family: Heat Stroke warms the handle a little, Flicker hangs a ring round the
## handle that loads round and round, Gold Dust shows nothing. SunScepter is reached by its path: a class added since the
## editor last scanned has no global name in a headless run.

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
func toast(_t, _c = null) -> void:
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
func blast(_v: Vector3, _u: float = 0.0) -> void:
	pass
func apply_knockback(_v: Vector3) -> void:
	pass
func max_speed() -> float:
	return 5.0
func forward() -> Vector3:
	return Vector3.FORWARD
func aim_origin(d: Vector3) -> Vector3:
	return global_position + Vector3(0, 0.8, 0) + Vector3(d.x, 0, d.z).normalized() * 0.5
"""

const DT := 1.0 / 60.0


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


func before_test() -> void:
	Save.data = Save._default()
	Run.start(Registry.character("solenne"), Registry.map("red_canyon"))


func after_test() -> void:
	Run.debug_clear_items()
	Run.end()


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
	return {"g": g, "hero": hero, "em": em}


func _inst(id: String, muts: Array = [], level := 1) -> WeaponInstance:
	var inst := WeaponInstance.new(Registry.weapon(id), level)
	for m: String in muts:
		var md: MutationDef = Registry.mutation(m)
		assert_object(md).override_failure_message("no mutation " + m).is_not_null()
		inst.mutations.append(md)
	inst.rebuild(Run.player_sheet, [inst])
	return inst


func _scepter(w: Dictionary, id := "sun_scepter", muts: Array = []):
	var b = SCEPTER.new()
	(w["g"] as Node).add_child(b)
	b.setup(_inst(id, muts), w["g"])
	return b


## A creature standing where it was put, on the screen (so a strike has something to call down on).
func _creature(em: EnemyManager, at: Vector3) -> int:
	var i := em.spawn("skeleton", at, null, 1.0, 50.0)
	assert_int(i).is_greater_equal(0)
	em.state[i] = EnemyManager.STATE_MOVE
	em.vel[i] = Vector3.ZERO
	em._rebuild_grid()
	em.refresh_crowd_stats()
	return i


func _ticks(b, seconds: float) -> void:
	for k in range(int(round(seconds / DT))):
		b._tick(DT)


## The same build change Game._sync_weapons makes: the instance re-folded with a new set of mutations, then the marks.
func _rebuild_with(b, muts: Array) -> void:
	b.inst.mutations.clear()
	for m: String in muts:
		b.inst.mutations.append(Registry.mutation(m))
	b.inst.rebuild(Run.player_sheet, [b.inst])
	b.refresh_marks()


func _near(a: Color, c: Color, eps := 0.003) -> bool:
	return absf(a.r - c.r) < eps and absf(a.g - c.g) < eps and absf(a.b - c.b) < eps


## A node's transform as the packed scene sets it (read off the scene's state).
func _scene_xf(ps: PackedScene, path: String) -> Transform3D:
	var st := ps.get_state()
	for i in range(st.get_node_count()):
		if str(st.get_node_path(i)) != path:
			continue
		for j in range(st.get_node_property_count(i)):
			if str(st.get_node_property_name(i, j)) == "transform":
				return st.get_node_property_value(i, j)
	return Transform3D.IDENTITY


# ---------------------------------------------------------------- the size

func test_the_sceptre_and_zenith_fly_thirty_percent_smaller() -> void:
	for id in ["sun_scepter", "zenith"]:
		var xf := _scene_xf(Registry.weapon(id).visual, "./Familiar")
		# pass 54 flew them at 1.7
		assert_float(xf.basis.get_scale().x).override_failure_message(id).is_equal_approx(1.7 * 0.7, 0.001)
	# the plain sceptre's sunburst, the glint now: 45% of its old 1.7 m across
	var glow := _scene_xf(Registry.weapon("sun_scepter").visual, "./Familiar/SunGlow")
	assert_float(glow.basis.get_scale().x * 1.19).is_equal_approx(0.45 * 1.7, 0.01)
	# Zenith's keeps its quad (it shrinks with the sceptre)
	var zglow := _scene_xf(Registry.weapon("zenith").visual, "./Familiar/SunGlow")
	assert_float(zglow.basis.get_scale().x).is_equal_approx(1.0, 0.001)
	var w := _world()
	var b = _scepter(w)
	assert_float(b._familiar.scale.x).is_equal_approx(1.19, 0.001)


# ---------------------------------------------------------------- the glint

func test_the_sceptre_shines_only_when_it_strikes() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(4, 0, 0))
	var b = _scepter(w)
	# no crossed bars, and at rest no sunburst at all (hidden, not drawn at zero)
	assert_object(b._glint).is_null()
	assert_object(b._glow).is_not_null()
	_ticks(b, 0.5)
	assert_bool(b._glow.visible).is_false()
	assert_float(b.glow_now()).is_equal(0.0)
	# a strike called: up in 0.06 s to its flare
	assert_bool(b._fire()).is_true()
	_ticks(b, SCEPTER.FLARE_UP)
	assert_bool(b._glow.visible).is_true()
	assert_float(b.glow_now()).is_greater(0.9)
	# and gone again 0.3 s later
	_ticks(b, SCEPTER.FLARE_DOWN + 0.05)
	assert_bool(b._glow.visible).is_false()
	# the flare's shape
	assert_float(SCEPTER.flare_at(-0.1)).is_equal(0.0)
	assert_float(SCEPTER.flare_at(SCEPTER.FLARE_UP)).is_equal_approx(1.0, 0.0001)
	assert_float(SCEPTER.flare_at(SCEPTER.FLARE_UP + 0.15)).is_between(0.1, 0.5)
	assert_float(SCEPTER.flare_at(SCEPTER.FLARE_UP + SCEPTER.FLARE_DOWN)).is_equal(0.0)


func test_zenith_keeps_its_shine_and_flares_harder_on_a_strike_hardest_on_the_sweep() -> void:
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(4, 0, 0))
	var b = _scepter(w, "zenith")
	# its bars and its constant sunburst
	assert_object(b._glint).is_not_null()
	_ticks(b, 0.5)
	assert_bool(b._glow.visible).is_true()
	var rest: float = b.glow_now()
	assert_float(rest).is_equal_approx(0.4, 0.01)
	var rest_scale: float = b._glow.scale.x
	# a strike: brighter than the plain sceptre's flare, and it swells
	assert_bool(b._fire()).is_true()
	_ticks(b, SCEPTER.FLARE_UP)
	var strike: float = b.glow_now()
	assert_float(strike).is_greater(1.5)
	assert_float(b._glow.scale.x).is_greater(rest_scale * 1.15)
	_ticks(b, 0.6)
	# the tenth strike is the sweep: the strongest flare of all
	b.count = 9
	assert_bool(b._fire()).is_true()
	assert_bool(b._strikes[0]["sweep"]).is_true()
	_ticks(b, SCEPTER.FLARE_UP)
	assert_float(b.glow_now()).is_greater(strike + 0.5)
	assert_float(SCEPTER.glow_strength(b._shine(), 0.0, 0.0, 1.0, 0.0)).is_greater(strike)


# ---------------------------------------------------------------- the shake

func test_a_strike_shakes_the_whole_sceptre_and_the_shake_dies_away() -> void:
	assert_object(SCEPTER.shake_at(-0.01)).is_equal(Vector3.ZERO)
	assert_object(SCEPTER.shake_at(SCEPTER.SHAKE_TIME)).is_equal(Vector3.ZERO)
	var early: Vector3 = SCEPTER.shake_at(0.03)
	assert_float(absf(early.x) + absf(early.y)).is_greater(0.02)
	assert_float(early.z).is_greater(0.0)
	# quieter as it goes: the jitter's reach shrinks
	var peak_early := 0.0
	var peak_late := 0.0
	for k in range(50):
		var t := SCEPTER.SHAKE_TIME * float(k) / 50.0
		var s: Vector3 = SCEPTER.shake_at(t)
		if t < SCEPTER.SHAKE_TIME * 0.3:
			peak_early = maxf(peak_early, absf(s.x))
		elif t > SCEPTER.SHAKE_TIME * 0.7:
			peak_late = maxf(peak_late, absf(s.x))
	assert_float(peak_late).is_less(peak_early * 0.3)
	# a sweep's is harder and longer
	assert_float(SCEPTER.shake_time(SCEPTER.SWEEP_POWER)).is_greater(SCEPTER.SHAKE_TIME)
	assert_float(SCEPTER.shake_at(0.03, SCEPTER.SWEEP_POWER).z).is_greater(early.z)
	# on the sceptre: pitched, rolled and kicked off its flight while it shakes, exactly on it after
	var w := _world()
	var em: EnemyManager = w["em"]
	_creature(em, Vector3(4, 0, 0))
	var b = _scepter(w)
	_ticks(b, 0.3)
	var tilt := -deg_to_rad(SCEPTER.TILT_DEG)
	assert_float(b._familiar.rotation.x).is_equal_approx(tilt, 0.0001)
	assert_bool(b._fire()).is_true()
	var off := 0.0
	var kick := 0.0
	for k in range(8):
		b._tick(DT)
		off = maxf(off, absf(b._familiar.rotation.x - tilt))
		kick = maxf(kick, b._familiar.global_position.distance_to(b._fly_at))
	assert_float(off).is_greater(0.03)
	assert_float(kick).is_greater(0.02)
	_ticks(b, SCEPTER.SHAKE_TIME)
	assert_float(b._familiar.rotation.x).is_equal_approx(tilt, 0.0001)
	assert_float(b._familiar.global_position.distance_to(b._fly_at)).is_less(0.0001)


# ---------------------------------------------------------------- its path on the sceptre

func test_the_family_hangs_no_emblems() -> void:
	var w := _world()
	for id in ["sun_scepter", "zenith"]:
		var b = _scepter(w, id, ["heat_stroke", "flicker", "gold_dust"])
		# pass 60: no weapon hangs emblems (WeaponBehavior.refresh_marks frees any "MutationMarks" node and builds none)
		assert_object(b.get_node_or_null("MutationMarks")).override_failure_message(id).is_null()
		assert_bool(bool(Registry.weapon(id).params.get("marks", true))).is_false()


func test_heat_stroke_warms_the_handle_a_little_and_only_the_handle() -> void:
	var w := _world()
	var plain = _scepter(w)
	assert_bool(plain.staff_tinted()).is_false()
	var rest: Color = plain.lacquer_color()
	var b = _scepter(w, "sun_scepter", ["heat_stroke"])
	assert_bool(b.staff_tinted()).is_true()
	var warm: Color = b.lacquer_color()
	# a quarter of the way to the orange: redder and less blue, a gentle shift
	var p: Dictionary = b.inst.params["staff_tint"]
	var target := Color(str(p["color"]))
	assert_bool(_near(warm, rest.lerp(target, float(p["amount"])), 0.01)).override_failure_message(str(warm)).is_true()
	assert_float(warm.r).is_greater(rest.r)
	assert_float(warm.b).is_less(rest.b + 0.001)
	assert_float(float(p["amount"])).is_less_equal(0.35)
	# a faint warm emission, not a glow
	var staff: MeshInstance3D = b._staff()
	var m := (staff.material_override if b._lacquer_surf < 0 else staff.get_active_material(b._lacquer_surf)) as StandardMaterial3D
	assert_bool(m.emission_enabled).is_true()
	assert_float(m.emission_energy_multiplier).is_less_equal(0.5)
	# the brass bands and the sun keep their colours
	if staff.mesh and staff.mesh.get_surface_count() > 1:
		for k in range(staff.mesh.get_surface_count()):
			if k == b._lacquer_surf:
				continue
			assert_bool(_near((staff.get_active_material(k) as BaseMaterial3D).albedo_color,
				(plain._staff().get_active_material(k) as BaseMaterial3D).albedo_color)).is_true()
	# Flicker and Gold Dust leave the handle alone; dropping Heat Stroke puts it back exactly
	assert_bool(_scepter(w, "sun_scepter", ["flicker"]).staff_tinted()).is_false()
	assert_bool(_scepter(w, "sun_scepter", ["gold_dust"]).staff_tinted()).is_false()
	_rebuild_with(b, [])
	assert_bool(b.staff_tinted()).is_false()
	assert_bool(_near(b.lacquer_color(), rest)).is_true()


func test_flicker_hangs_a_ring_round_the_handle_that_loads_round() -> void:
	var w := _world()
	assert_bool(_scepter(w).has_ring()).is_false()
	assert_bool(_scepter(w, "sun_scepter", ["heat_stroke"]).has_ring()).is_false()
	var b = _scepter(w, "sun_scepter", ["flicker"])
	assert_bool(b.has_ring()).is_true()
	# round the handle: on the staff's line, in its lower half, a third of the way up or so, in the sceptre's own model
	var ring: Node3D = b._ring
	assert_object(ring.get_parent()).is_same(b._model)
	assert_float(ring.position.x).is_equal(0.0)
	assert_float(ring.position.z).is_equal(0.0)
	var staff: MeshInstance3D = b._staff()
	var box: AABB = staff.transform * staff.mesh.get_aabb()
	var up := (ring.position.y - box.position.y) / box.size.y
	assert_float(up).is_between(0.25, 0.5)
	# wider than the staff at its widest (the collar under the sun), so the staff runs through its middle
	var p: Dictionary = b.inst.params["handle_ring"]
	assert_float(float(p["radius"])).is_greater(box.size.x * 0.5)
	# its light grows round over the period, then starts again
	assert_float(SCEPTER.ring_fill_at(0.0)).is_equal(0.0)
	assert_float(SCEPTER.ring_fill_at(0.3)).is_less(SCEPTER.ring_fill_at(0.6))
	assert_float(SCEPTER.ring_fill_at(0.9)).is_equal(1.0)
	_ticks(b, 0.5)
	var f1: float = b.ring_fill
	var n1: int = b.ring_pieces
	# the track and the light in one strip (one draw, the light over the track)
	assert_int(b._ring_mesh.get_surface_count()).is_equal(1)
	_ticks(b, 1.0)
	assert_float(b.ring_fill).is_greater(f1)
	assert_int(b.ring_pieces).is_greater(n1)
	var period := float(p["period"])
	assert_float(period).is_between(2.0, 3.0)
	_ticks(b, period - 1.5 + 0.3)
	assert_float(b.ring_fill).is_less(f1 + 0.05)
	# it flies, tilts and shakes with the sceptre: it is under the familiar
	assert_bool(b._familiar.is_ancestor_of(ring)).is_true()
	# taken mid-run (a build change), and gone with the mutation
	var c = _scepter(w)
	_rebuild_with(c, ["flicker"])
	assert_bool(c.has_ring()).is_true()
	_rebuild_with(c, ["gold_dust"])
	assert_bool(c.has_ring()).is_false()


func test_gold_dust_shows_nothing_on_the_sceptre() -> void:
	var w := _world()
	var plain = _scepter(w)
	var b = _scepter(w, "sun_scepter", ["gold_dust"])
	assert_bool(b.has_ring()).is_false()
	assert_bool(b.staff_tinted()).is_false()
	assert_object(b.get_node_or_null("MutationMarks")).is_null()
	assert_int(b._model.get_child_count()).is_equal(plain._model.get_child_count())
	assert_int(b._familiar.get_child_count()).is_equal(plain._familiar.get_child_count())


func test_zenith_carries_the_whole_path_on_its_staff() -> void:
	var w := _world()
	var b = _scepter(w, "zenith", ["heat_stroke", "flicker", "gold_dust"])
	assert_object(b._staff()).is_not_null()
	assert_bool(b.staff_tinted()).is_true()
	assert_bool(b.has_ring()).is_true()
	assert_object(b.get_node_or_null("MutationMarks")).is_null()
	# and its count ring still lights on the sun head
	assert_bool(b._charge != null and b._charge.visible).is_true()
