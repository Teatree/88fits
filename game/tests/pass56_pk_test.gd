extends GdUnitTestSuite

## Pass 56, lane PK (Garry: the XP gems "more of a Rhombohedron shape, but 3d obviously", then "I mean octahedron";
## "just 5% bigger"; "an occasional, very rare, little extra hop to the idle float that they are doing right now", each
## gem once every 40-60 s; the medium and large gems "glint now and then"): the gem mesh is a faceted octahedron wound
## the way Godot draws it, 5 % bigger than the pass-54 wedge as the run's camera sees them, the float as it was, the
## rare extra hop only for gems lying on the sand, and throttled glints on the medium and large gems only.
## The fix round (the lead): each kind's own look factor measured with the sand cutting both shapes (the vacuum the size
## it was), no more than one hop on the screen every HOP_EXTRA_GAP s, a drop falling as far after its pop as in v0.41,
## and glints only below the HUD's strip.

const FAKE_GAME := """extends Node
var player: Node3D
var map = null
var enemies = null
var camera = null
var telegraphs = null
var projectiles = null
var pickups = null
var fx = null
var paused := false
func toast(_t, _c = null) -> void:
	pass
"""

const FAKE_HERO := """extends Node3D
var dead := false
var facing := 0.0
var velocity := Vector3.ZERO
var character = null
var max_hp := 100.0
var last_outcome := "hit"
func take_damage(_a: float, _f: Vector3, _i: Dictionary = {}) -> void:
	pass
func max_speed() -> float:
	return 5.0
"""

const DT := 1.0 / 60.0
## pass 54's gem radii (the wedge), before Garry's 5 %
const OLD_R := [0.11, 0.16, 0.225]


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## A fake game with a fake hero at the origin, no map (the sand flat at 0) and a real PickupManager.
func _pickups() -> Dictionary:
	Run.start(Registry.character("astro"), Registry.map("red_canyon"))
	var g: Node = auto_free(Node.new())
	g.set_script(_script(FAKE_GAME))
	add_child(g)
	var hero := Node3D.new()
	hero.set_script(_script(FAKE_HERO))
	g.add_child(hero)
	g.player = hero
	var pm: PickupManager = auto_free(PickupManager.new())
	pm.game = g
	add_child(pm)
	g.pickups = pm
	return {"g": g, "hero": hero, "pm": pm}


## The run's camera (a real CameraRig, as pass336_test builds it) on the fake game, bolted to the hero at the origin.
func _camera(w: Dictionary) -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	add_child(rig)
	rig.snap_to(w["hero"])
	w["g"].camera = rig
	return rig


## A pickup of `k` lying on the sand at (x, z), far past the hero's magnet unless placed near him.
func _resting(pm: PickupManager, k: int, x: float, z: float = 0.0) -> int:
	var i := pm.spawn(k, Vector3(x, 0, z), 1.0)
	pm.pos[i] = Vector3(x, PickupManager.rest_of(k), z)
	pm.vel[i] = Vector3.ZERO
	return i


func _tick(pm: PickupManager, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		pm._physics_process(DT)
		t += DT


## How pickup `i` is drawn now: what _render hands its kind's MultiMesh (kept in drawn_xf while record_draws is on; a
## MultiMesh gives nothing back headless).
func _drawn(pm: PickupManager, i: int) -> Transform3D:
	pm.record_draws = true
	pm._render()
	return pm.drawn_xf[i]


## A mesh's corners, each once (a mesh repeats a corner for every face that meets there).
func _corners(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		var seen := false
		for q in out:
			if q.is_equal_approx(p):
				seen = true
				break
		if not seen:
			out.append(p)
	return out


func _hull_area(flat: PackedVector2Array) -> float:
	if flat.size() < 3:
		return 0.0
	var hull := Geometry2D.convex_hull(flat)
	var a := 0.0
	for h in range(hull.size()):
		var q0: Vector2 = hull[h]
		var q1: Vector2 = hull[(h + 1) % hull.size()]
		a += q0.x * q1.y - q1.x * q0.y
	return absf(a) * 0.5


## What the run's camera shows of a convex pickup with these corners (about its middle) resting `rest` m over flat sand:
## the mean area of its outline as it spins about its upright axis and floats (float_y over the whole float), seen from
## `pitch_deg` above the horizon (an orthographic look: a gem is tiny against the camera's 22.5 m), with whatever dips
## under the sand hidden, as the sand hides it.
func _visible_area(points: PackedVector3Array, rest: float, pitch_deg: float, spins := 120, floats := 24) -> float:
	var corners := _corners(points)
	var p := deg_to_rad(pitch_deg)
	var up := Vector3(0.0, cos(p), -sin(p))
	var total := 0.0
	for f in range(floats):
		var lift := 0.06 + sin(TAU * float(f) / float(floats)) * PickupManager.BOB
		for s in range(spins):
			var b := Basis(Vector3.UP, TAU * float(s) / float(spins))
			var w := PackedVector3Array()
			for v in corners:
				w.append(b * v + Vector3(0.0, rest + lift, 0.0))
			# the part over the sand: the corners over it, and where each line from a corner over it to one under it
			# meets it (for a convex shape the outline of these is the outline of what shows)
			var flat := PackedVector2Array()
			for a in w:
				if a.y >= 0.0:
					flat.append(Vector2(a.x, a.dot(up)))
			for a in w:
				if a.y <= 0.0:
					continue
				for c in w:
					if c.y < 0.0:
						var x: Vector3 = a + (c - a) * (a.y / (a.y - c.y))
						flat.append(Vector2(x.x, x.dot(up)))
			total += _hull_area(flat)
	return total / float(spins * floats)


## The octahedron of kind `k` as the camera sees it, drawn `r` across instead of its own radius when r > 0.
func _gem_seen(k: int, pitch: float, r := 0.0) -> float:
	var rr: float = r if r > 0.0 else PickupManager.gem_radius(k)
	var rest: float = maxf(PickupManager.REST, rr * PickupManager.GEM_TALL * 0.5 + PickupManager.GEM_CLEAR - (0.06 - PickupManager.BOB))
	if r <= 0.0:
		assert_float(rest).is_equal_approx(PickupManager.rest_of(k), 0.000001)
	return _visible_area(PickupManager.octahedron_mesh(rr).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], rest, pitch)


## The pass-54 wedge's corners, as pass 54 built it (a PrismMesh 2 r wide, 2.4 r tall, 2 r deep, its ridge on top).
func _wedge(r: float) -> PackedVector3Array:
	var m := PrismMesh.new()
	m.size = Vector3(r * 2.0, r * 2.4, r * 2.0)
	return m.get_mesh_arrays()[Mesh.ARRAY_VERTEX]


# ---------------------------------------------------------------- 1. the octahedron

func test_the_gem_is_a_faceted_octahedron_wound_the_way_godot_draws() -> void:
	# Godot's own primitives: (b - a) x (c - a) points into the mesh on a front face
	var box: Array = BoxMesh.new().get_mesh_arrays()
	var bv: PackedVector3Array = box[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = box[Mesh.ARRAY_NORMAL]
	var bi: PackedInt32Array = box[Mesh.ARRAY_INDEX]
	var godot_sign := signf((bv[bi[1]] - bv[bi[0]]).cross(bv[bi[2]] - bv[bi[0]]).dot(bn[bi[0]]))
	assert_float(godot_sign).is_equal(-1.0)
	var pm: PickupManager = _pickups()["pm"]
	for k in [PickupManager.KIND_GEM_S, PickupManager.KIND_GEM_M, PickupManager.KIND_GEM_L, PickupManager.KIND_VACUUM]:
		var r := PickupManager.gem_radius(k)
		var m: Mesh = (pm._mms[k] as MultiMesh).mesh
		assert_bool(m is ArrayMesh).override_failure_message("kind %d is not an ArrayMesh" % k).is_true()
		assert_int(m.get_surface_count()).is_equal(1)
		var arr: Array = m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		# eight faces, each its own three corners (flat normals)
		assert_int(v.size()).is_equal(24)
		var distinct: Array = []
		for p in v:
			var seen := false
			for q: Vector3 in distinct:
				if q.is_equal_approx(p):
					seen = true
			if not seen:
				distinct.append(p)
		assert_int(distinct.size()).is_equal(6)
		# a tip on top and at the bottom, four round the middle
		var tall := r * PickupManager.GEM_TALL
		var tips := 0
		var ring := 0
		for q: Vector3 in distinct:
			if absf(absf(q.y) - tall * 0.5) < 0.0001 and Vector2(q.x, q.z).length() < 0.0001:
				tips += 1
			elif absf(q.y) < 0.0001 and absf(Vector2(q.x, q.z).length() - r) < 0.0001:
				ring += 1
		assert_int(tips).is_equal(2)
		assert_int(ring).is_equal(4)
		# 2.4 r tall and 2 r wide (the wedge's proportions)
		var box_size := m.get_aabb().size
		assert_float(box_size.y).is_equal_approx(2.4 * r, 0.0001)
		assert_float(box_size.x).is_equal_approx(2.0 * r, 0.0001)
		assert_float(box_size.z).is_equal_approx(2.0 * r, 0.0001)
		var normals: Array = []
		for f in range(8):
			var a := v[f * 3]
			var b := v[f * 3 + 1]
			var c := v[f * 3 + 2]
			# one normal for the whole face, at right angles to it, pointing out of the gem
			assert_bool(n[f * 3].is_equal_approx(n[f * 3 + 1]) and n[f * 3].is_equal_approx(n[f * 3 + 2])).is_true()
			var face_n: Vector3 = n[f * 3]
			assert_float(face_n.length()).is_equal_approx(1.0, 0.0001)
			assert_float(absf(face_n.dot((b - a).normalized()))).is_less(0.0001)
			assert_float(absf(face_n.dot((c - a).normalized()))).is_less(0.0001)
			assert_float(face_n.dot((a + b + c) / 3.0)).is_greater(0.0)
			# wound like Godot's own front faces
			assert_float(signf((b - a).cross(c - a).dot(face_n))).is_equal(godot_sign)
			normals.append(face_n)
		# eight different facets
		for f in range(8):
			for g in range(f + 1, 8):
				assert_bool((normals[f] as Vector3).is_equal_approx(normals[g])).is_false()


# ---------------------------------------------------------------- 2. 5 % bigger

func test_each_kind_looks_its_old_size_times_its_growth_with_the_sand_cutting_both() -> void:
	assert_float(PickupManager.GEM_GROW).is_equal_approx(1.05, 0.0001)
	for k in range(3):
		assert_float(float(PickupManager.GEM_R[k])).is_equal_approx(float(OLD_R[k]) * 1.05, 0.0001)
	# the vacuum and the coin as they were
	assert_float(PickupManager.VACUUM_R).is_equal_approx(0.38, 0.0001)
	assert_float(PickupManager.COIN_R).is_equal_approx(0.21, 0.0001)
	# the run's camera looks down at this angle (CameraRig's fixed pitch)
	var rig := CameraRig.new()
	var pitch: float = rig.fixed_pitch_deg
	rig.free()
	assert_float(pitch).is_equal_approx(46.0, 0.001)
	# what the camera shows, spinning and floating, the sand hiding what dips into it: the old wedge at REST, the
	# octahedron at its own rest. Each gem 5 % bigger than its wedge showed (the square root of the area), the vacuum
	# the size its wedge showed
	var old_seen: Array = []
	for k in range(4):
		var r: float = float(OLD_R[k]) if k < 3 else 0.38
		old_seen.append(_visible_area(_wedge(r), PickupManager.REST, pitch))
	for k in range(3):
		var grow := sqrt(_gem_seen(k, pitch) / float(old_seen[k]))
		assert_float(grow).override_failure_message("gem %d looks %.4f times its old size" % [k, grow]).is_between(1.045, 1.055)
	var vk := PickupManager.KIND_VACUUM
	var vgrow := sqrt(_gem_seen(vk, pitch) / float(old_seen[3]))
	assert_float(vgrow).override_failure_message("the vacuum looks %.4f times its old size" % vgrow).is_between(0.995, 1.005)
	# the sand hid part of the old large gem and more of the old vacuum (why their factors are smaller), and the octahedra
	# never dip into it
	assert_float(float(old_seen[2]) / _visible_area(_wedge(0.225), 100.0, pitch, 120, 1)).is_less(0.97)
	assert_float(float(old_seen[3]) / _visible_area(_wedge(0.38), 100.0, pitch, 120, 1)).is_less(0.8)
	assert_float(PickupManager.VACUUM_LOOK).is_less(float(PickupManager.GEM_LOOK[2]))
	assert_float(float(PickupManager.GEM_LOOK[2])).is_less(float(PickupManager.GEM_LOOK[0]))
	# one factor of 1.64 for every kind (the first round) made the large gem and the vacuum too big
	assert_float(sqrt(_gem_seen(2, pitch, 0.225 * 1.05 * 1.64) / float(old_seen[2]))).is_greater(1.07)
	assert_float(sqrt(_gem_seen(vk, pitch, 0.38 * 1.64) / float(old_seen[3]))).is_greater(1.12)
	# the vacuum no longer stands as tall as the hero (round one: 1.5 m from tip to tip, its top at 1.72 m): under 1.4 m
	# from tip to tip, its top under 1.6 m at the float's highest
	var vr := PickupManager.gem_radius(vk)
	assert_float(vr * PickupManager.GEM_TALL).is_less(1.4)
	assert_float(PickupManager.rest_of(vk) + 0.06 + PickupManager.BOB + vr * PickupManager.GEM_TALL * 0.5).is_less(1.6)
	# an octahedron as wide and tall as the wedge would look far smaller: the reason for the factors
	var same_box: PackedVector3Array = PickupManager.octahedron_mesh(0.11).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_float(_visible_area(same_box, 100.0, pitch, 120, 1) / _visible_area(_wedge(0.11), 100.0, pitch, 120, 1)).is_less(0.4)


func test_a_big_gem_rests_high_enough_that_its_tip_clears_the_sand() -> void:
	assert_float(PickupManager.rest_of(PickupManager.KIND_COIN)).is_equal_approx(PickupManager.REST, 0.0001)
	for k in [PickupManager.KIND_GEM_S, PickupManager.KIND_GEM_M, PickupManager.KIND_GEM_L, PickupManager.KIND_VACUUM]:
		var rest := PickupManager.rest_of(k)
		assert_float(rest).is_greater_equal(PickupManager.REST)
		var half := PickupManager.gem_radius(k) * PickupManager.GEM_TALL * 0.5
		# at the bottom of the float (0.06 - BOB) the lower tip is GEM_CLEAR over the sand, never more than it needs
		assert_float(rest + 0.06 - PickupManager.BOB - half).is_equal_approx(PickupManager.GEM_CLEAR, 0.0001)
	# a gem dropped on the sand settles there, the big one higher
	var pm: PickupManager = _pickups()["pm"]
	var s := pm.spawn(PickupManager.KIND_GEM_S, Vector3(20, 0, 0), 1.0)
	var l := pm.spawn(PickupManager.KIND_GEM_L, Vector3(-20, 0, 0), 25.0)
	# the big one starts DROP_FROM - REST over its own rest and pops up out of the kill before it lands
	assert_float(pm.pos[l].y).is_equal_approx(PickupManager.rest_of(PickupManager.KIND_GEM_L) + PickupManager.DROP_FROM - PickupManager.REST, 0.0001)
	_tick(pm, 0.1)
	assert_float(pm.pos[l].y).is_greater(PickupManager.rest_of(PickupManager.KIND_GEM_L) + 0.1)
	_tick(pm, 1.5)
	assert_float(pm.pos[s].y).is_equal_approx(PickupManager.rest_of(PickupManager.KIND_GEM_S), 0.0001)
	assert_float(pm.pos[l].y).is_equal_approx(PickupManager.rest_of(PickupManager.KIND_GEM_L), 0.0001)
	assert_float(pm.pos[l].y).is_greater(pm.pos[s].y)


# ---------------------------------------------------------------- 3. the float and the extra hop

func test_the_float_is_as_it_was() -> void:
	assert_float(PickupManager.BOB).is_equal_approx(0.09, 0.0001)
	assert_float(PickupManager.REST).is_equal_approx(0.22, 0.0001)
	for i in [0, 1, 7, 333]:
		for t in [0.0, 0.4, 3.3, 61.0]:
			assert_float(PickupManager.float_y(i, t)).is_equal_approx(0.06 + sin(t * 2.4 + float(i) * 0.9) * 0.09, 0.000001)
	# drawn: a resting gem that is not hopping sits at its spot plus the float, upright, its own size
	var pm: PickupManager = _pickups()["pm"]
	var i := _resting(pm, PickupManager.KIND_GEM_M, 20.0)
	pm._physics_process(DT)
	var xf := _drawn(pm, i)
	assert_float(xf.origin.y).is_equal_approx(pm.pos[i].y + PickupManager.float_y(i, pm._time), 0.0001)
	assert_float(xf.basis.get_scale().y).is_equal_approx(1.0, 0.0001)


func test_the_extra_hop_comes_every_40_to_60_seconds_and_is_a_little_quick_hop() -> void:
	# the numbers Garry's words set: "very rare", "little"
	assert_float(PickupManager.HOP_EXTRA_MIN).is_equal(40.0)
	assert_float(PickupManager.HOP_EXTRA_MAX).is_equal(60.0)
	assert_float(PickupManager.HOP_EXTRA_HEIGHT).is_between(0.25, 0.3)
	assert_float(PickupManager.HOP_EXTRA_TIME).is_between(0.35, 0.4)
	assert_float(PickupManager.HOP_EXTRA_SQUASH_Y).is_equal_approx(0.85, 0.0001)
	assert_float(PickupManager.HOP_EXTRA_SQUASH_XZ).is_equal_approx(1.1, 0.0001)
	assert_float(PickupManager.HOP_EXTRA_SQUASH_TIME).is_less(0.1)
	# the parabola: nothing at either end, the full height halfway
	assert_float(PickupManager.hop_extra_y(0.0)).is_equal(0.0)
	assert_float(PickupManager.hop_extra_y(PickupManager.HOP_EXTRA_TIME * 0.5)).is_equal_approx(PickupManager.HOP_EXTRA_HEIGHT, 0.0001)
	assert_float(PickupManager.hop_extra_y(PickupManager.HOP_EXTRA_TIME)).is_equal(0.0)
	# the spin ends a half turn on (the four-sided gem's quarter-turn symmetry hides the step back to the float's spin)
	assert_float(fmod(PickupManager.HOP_EXTRA_SPIN, PI * 0.5)).is_equal_approx(0.0, 0.0001)
	assert_float(PickupManager.hop_extra_spin(PickupManager.HOP_EXTRA_TIME * 0.999)).is_equal_approx(PickupManager.HOP_EXTRA_SPIN, 0.001)
	# stretched on the fast way up (eased in, no snap as it leaves), its own shape at the top
	assert_vector(PickupManager.hop_extra_scale(0.0)).is_equal(Vector2.ONE)
	assert_float(PickupManager.hop_extra_scale(PickupManager.HOP_EXTRA_TIME * 0.25).y).is_equal_approx(PickupManager.HOP_EXTRA_STRETCH, 0.0001)
	assert_float(PickupManager.hop_extra_scale(PickupManager.HOP_EXTRA_TIME * 0.5).y).is_equal_approx(1.0, 0.0001)
	# squashed as it lands, back to its shape inside the squash time
	var landed := PickupManager.hop_extra_scale(PickupManager.HOP_EXTRA_TIME)
	assert_float(landed.y).is_equal_approx(0.85, 0.0001)
	assert_float(landed.x).is_equal_approx(1.1, 0.0001)
	assert_vector(PickupManager.hop_extra_scale(PickupManager.HOP_EXTRA_TIME + PickupManager.HOP_EXTRA_SQUASH_TIME)).is_equal(Vector2.ONE)
	# every gem's first hop waits 40-60 s from its landing, each at its own moment
	var pm: PickupManager = _pickups()["pm"]
	var gems: Array = []
	for g in range(40):
		gems.append(_resting(pm, g % 3, -30.0 + float(g) * 1.5, -25.0))
	var t0: float = pm._time
	pm._physics_process(DT)
	var waits: Array = []
	for i: int in gems:
		assert_float(pm.hop_t[i]).is_less(0.0)
		var w: float = pm.hop_next[i] - t0
		assert_float(w).is_between(40.0, 60.0 + DT)
		waits.append(w)
	waits.sort()
	assert_float(float(waits[waits.size() - 1]) - float(waits[0])).is_greater(5.0)
	# lying still, a gem is looked at again only when its next hop (or a medium or large one's glint) is due
	for i: int in gems:
		var due: float = pm.hop_next[i]
		if pm.kind[i] != PickupManager.KIND_GEM_S:
			due = minf(due, pm.glint_next[i])
		assert_float(pm.idle_due[i]).is_equal_approx(due, 0.0001)
	# one gem's hop, watched: nothing until its moment, then up and down in HOP_EXTRA_TIME, the full height at the top
	# (the others' turns put off, so no hop of theirs holds it back with the gap)
	var i: int = gems[0]
	for j: int in gems:
		if j != i:
			pm.hop_next[j] = 1.0e9
			pm.idle_due[j] = 1.0e9
	pm._time = pm.hop_next[i] - 3.0 * DT
	var base := pm.pos[i].y
	var top := 0.0
	var airborne := 0.0
	var started := -1.0
	for step in range(60):
		pm._physics_process(DT)
		if pm.hop_t[i] >= 0.0 and started < 0.0:
			started = pm._time
		if pm.hop_t[i] >= 0.0:
			# looked at every tick while it hops
			assert_float(pm.idle_due[i]).is_equal(0.0)
		var extra := _drawn(pm, i).origin.y - base - PickupManager.float_y(i, pm._time)
		top = maxf(top, extra)
		if extra > 0.001:
			airborne += DT
		# it never leaves its spot: the hop is drawn only
		assert_float(pm.pos[i].y).is_equal_approx(base, 0.0001)
	assert_float(started).is_greater(0.0)
	assert_float(top).is_between(PickupManager.HOP_EXTRA_HEIGHT - 0.01, PickupManager.HOP_EXTRA_HEIGHT + 0.0001)
	assert_float(airborne).is_between(PickupManager.HOP_EXTRA_TIME - 3.0 * DT, PickupManager.HOP_EXTRA_TIME + DT)
	# over, and the next one 40-60 s after it
	assert_float(pm.hop_t[i]).is_less(0.0)
	assert_float(pm.hop_next[i] - started).is_between(40.0, 60.0 + 1.0)


func test_hops_on_the_screen_come_no_closer_than_the_gap() -> void:
	# Garry: "an occasional, very rare, little extra hop"; the lead: about one every 0.75 s across the screen at most
	assert_float(PickupManager.HOP_EXTRA_GAP).is_between(0.7, 0.8)
	var pm: PickupManager = _pickups()["pm"]
	var gems: Array = []
	for g in range(180):
		gems.append(_resting(pm, g % 3, -40.0 + float(g % 30) * 2.7, -20.0 - floorf(float(g) / 30.0) * 3.0))
	pm._physics_process(DT)
	# every gem's turn comes inside the same four seconds (no camera: all of them on the screen)
	var rng := RandomNumberGenerator.new()
	rng.seed = 56
	var t0: float = pm._time
	var turn := {}
	for i: int in gems:
		pm.hop_next[i] = t0 + rng.randf_range(0.0, 4.0)
		pm.idle_due[i] = minf(pm.hop_next[i], pm.glint_next[i]) if pm.kind[i] != PickupManager.KIND_GEM_S else pm.hop_next[i]
		turn[i] = pm.hop_next[i]
	var starts: Array = []
	var hopped := {}
	for step in range(int(6.0 / DT)):
		pm._physics_process(DT)
		for i: int in gems:
			if pm.hop_t[i] >= 0.0 and pm.hop_t[i] < DT * 0.5:
				starts.append(pm._time)
				hopped[i] = true
	# never two hops on the screen inside the gap: about one every 0.75 s, against 180 in four seconds without it
	for s in range(1, starts.size()):
		assert_float(float(starts[s]) - float(starts[s - 1])).is_greater_equal(PickupManager.HOP_EXTRA_GAP - 0.0001)
	assert_int(starts.size()).is_between(5, int(4.0 / PickupManager.HOP_EXTRA_GAP) + 2)
	# every gem whose turn came inside the gap let it pass and waits a whole new 40-60 s from its turn
	for i: int in gems:
		if hopped.has(i):
			continue
		var wait: float = pm.hop_next[i] - float(turn[i])
		assert_float(wait).override_failure_message("gem %d waits %.2f s" % [i, wait]).is_between(PickupManager.HOP_EXTRA_MIN, PickupManager.HOP_EXTRA_MAX + DT)
		assert_float(pm.hop_t[i]).is_less(0.0)


func test_a_field_at_its_own_pace_hops_about_once_a_second() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var gems: Array = []
	for g in range(180):
		gems.append(_resting(pm, g % 3, -40.0 + float(g % 30) * 2.7, -20.0 - floorf(float(g) / 30.0) * 3.0))
	pm._physics_process(DT)
	# their first turns fall 40-60 s after they landed: jump to the start of that and watch twenty seconds of it
	pm._time += PickupManager.HOP_EXTRA_MIN - 0.5
	var starts := 0
	var last := -INF
	var each := {}
	for step in range(int(20.0 / DT)):
		pm._physics_process(DT)
		for i: int in gems:
			if pm.hop_t[i] >= 0.0 and pm.hop_t[i] < DT * 0.5:
				starts += 1
				assert_float(pm._time - last).is_greater_equal(PickupManager.HOP_EXTRA_GAP - 0.0001)
				last = pm._time
				# a gem hops once in this stretch at most: its next turn is 40-60 s on
				assert_bool(each.has(i)).is_false()
				each[i] = true
	# about one a second (90 turns in these twenty seconds, at most one every gap), not the four or more without the gap
	assert_int(starts).is_between(14, int(20.0 / PickupManager.HOP_EXTRA_GAP) + 1)


func test_off_the_screen_a_gem_hops_on_its_own_clock() -> void:
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var rig := _camera(w)
	var on_i := _resting(pm, PickupManager.KIND_GEM_S, 2.5, -2.0)
	var off_i := _resting(pm, PickupManager.KIND_GEM_S, 150.0, 0.0)
	assert_bool(rig.on_screen(pm.pos[on_i])).is_true()
	assert_bool(rig.on_screen(pm.pos[off_i])).is_false()
	assert_bool(pm._in_view(pm.pos[on_i])).is_true()
	assert_bool(pm._in_view(pm.pos[off_i])).is_false()
	pm._physics_process(DT)
	# a hop on the screen has just started: both turns come inside its gap
	var hop0: float = pm._time
	pm._hop_last = hop0
	for i in [on_i, off_i]:
		pm.hop_next[i] = pm._time
		pm.idle_due[i] = pm._time
	pm._physics_process(DT)
	# the one on the screen lets its turn pass and waits a new 40-60 s; the one nobody sees hops, and the gap is not its
	assert_float(pm.hop_t[on_i]).is_less(0.0)
	assert_float(pm.hop_next[on_i] - pm._time).is_between(PickupManager.HOP_EXTRA_MIN, PickupManager.HOP_EXTRA_MAX)
	assert_float(pm.hop_t[off_i]).is_greater_equal(0.0)
	assert_float(pm._hop_last).is_equal(hop0)
	# past the gap, the one on the screen hops at its next turn and starts the gap again
	_tick(pm, PickupManager.HOP_EXTRA_GAP)
	pm.hop_next[on_i] = pm._time
	pm.idle_due[on_i] = pm._time
	pm._physics_process(DT)
	assert_float(pm.hop_t[on_i]).is_greater_equal(0.0)
	assert_float(pm._hop_last).is_equal(pm._time)


func test_a_drop_falls_as_far_after_its_pop_as_in_v041() -> void:
	assert_float(PickupManager.DROP_FROM).is_equal_approx(0.4, 0.0001)
	var pm: PickupManager = _pickups()["pm"]
	# v0.41: a drop started DROP_FROM over the creature's feet and rested at REST, so after its pop (3 m/s up under
	# HOP_GRAV) it fell DROP_FROM - REST + 3^2 / (2 HOP_GRAV) m
	var v041 := PickupManager.DROP_FROM - PickupManager.REST + 9.0 / (2.0 * PickupManager.HOP_GRAV)
	var falls := {}
	for k in [PickupManager.KIND_GEM_S, PickupManager.KIND_GEM_M, PickupManager.KIND_GEM_L, PickupManager.KIND_COIN, PickupManager.KIND_VACUUM]:
		var i := pm.spawn(k, Vector3(-20.0 + 10.0 * float(k), 0.0, 30.0), 1.0)
		# DROP_FROM - REST over its own rest, whatever its size (a coin as before: its rest is REST)
		assert_float(pm.pos[i].y).is_equal_approx(PickupManager.rest_of(k) + PickupManager.DROP_FROM - PickupManager.REST, 0.0001)
		var top: float = pm.pos[i].y
		var landed := false
		for step in range(120):
			pm._physics_process(DT)
			top = maxf(top, pm.pos[i].y)
			if pm.vel[i] == Vector3.ZERO:
				landed = true
				break
		assert_bool(landed).is_true()
		assert_float(pm.pos[i].y).is_equal_approx(PickupManager.rest_of(k), 0.0001)
		falls[k] = top - pm.pos[i].y
	# every size falls as far as the coin, which fell as every drop did in v0.41
	for k in falls:
		assert_float(float(falls[k])).override_failure_message("kind %d fell %.3f m" % [k, falls[k]]).is_equal_approx(float(falls[PickupManager.KIND_COIN]), 0.001)
		assert_float(float(falls[k])).is_equal_approx(v041, 0.04)
	# let go above the sand (a barrel's burst lifts its gems 0.3-0.5 m), it keeps that height on top, as it always did;
	# let go under it, it starts from the sand
	var hi := pm.spawn(PickupManager.KIND_GEM_M, Vector3(5.0, 0.5, 30.0), 1.0)
	assert_float(pm.pos[hi].y).is_equal_approx(0.5 + PickupManager.rest_of(PickupManager.KIND_GEM_M) + PickupManager.DROP_FROM - PickupManager.REST, 0.0001)
	var lo := pm.spawn(PickupManager.KIND_GEM_M, Vector3(-5.0, -1.0, 30.0), 1.0)
	assert_float(pm.pos[lo].y).is_equal_approx(PickupManager.rest_of(PickupManager.KIND_GEM_M) + PickupManager.DROP_FROM - PickupManager.REST, 0.0001)


func test_a_falling_flying_or_called_gem_never_hops_and_never_pops() -> void:
	var pm: PickupManager = _pickups()["pm"]
	# falling from a kill: no clock until it lands
	var i := pm.spawn(PickupManager.KIND_GEM_S, Vector3(25, 0, 0), 1.0)
	pm._physics_process(DT)
	assert_float(pm.vel[i].y).is_greater(0.0)
	assert_float(pm.hop_next[i]).is_less(0.0)
	var landed := false
	for step in range(120):
		pm._physics_process(DT)
		if pm.vel[i] == Vector3.ZERO:
			landed = true
			break
		assert_float(pm.hop_next[i]).is_less(0.0)
		assert_float(pm.hop_t[i]).is_less(0.0)
	assert_bool(landed).is_true()
	assert_float(pm.hop_next[i]).is_greater(pm._time + 39.0)
	# a merged gem pops up out of its cluster and only counts once it is down again
	for g in range(4):
		_resting(pm, PickupManager.KIND_GEM_S, 40.0, 0.0)
	pm._merge(10)
	var merged := -1
	for j in range(PickupManager.MAX):
		if pm.alive[j] == 1 and pm.kind[j] == PickupManager.KIND_GEM_L:
			merged = j
	assert_int(merged).is_greater_equal(0)
	assert_float(pm.hop_next[merged]).is_less(0.0)
	pm._physics_process(DT)
	assert_float(pm.hop_next[merged]).is_less(0.0)
	# on its trip to the hero: no hop, no clock, however long it is out
	var f := _resting(pm, PickupManager.KIND_GEM_M, 30.0, 5.0)
	pm._physics_process(DT)
	pm._start_trip(f, Vector3.ZERO)
	assert_float(pm.hop_t[f]).is_less(0.0)
	assert_float(pm.hop_next[f]).is_less(0.0)
	for step in range(10):
		pm._physics_process(DT)
		assert_float(pm.hop_t[f]).is_less(0.0)
		assert_float(pm.hop_next[f]).is_less(0.0)
	# called at the top of a hop: it sets off from the height it was drawn at
	var c := _resting(pm, PickupManager.KIND_GEM_L, -30.0, 5.0)
	pm._physics_process(DT)
	pm.hop_t[c] = PickupManager.HOP_EXTRA_TIME * 0.5
	var before := _drawn(pm, c).origin.y
	pm._start_trip(c, Vector3.ZERO)
	var after := _drawn(pm, c).origin.y
	assert_float(after).is_equal_approx(before, 0.0001)
	assert_float(pm.hop_t[c]).is_less(0.0)


func test_coins_and_the_vacuum_keep_the_plain_float() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var coin := _resting(pm, PickupManager.KIND_COIN, 25.0)
	var vac := _resting(pm, PickupManager.KIND_VACUUM, -25.0)
	pm._physics_process(DT)
	pm._time += 200.0
	_tick(pm, 1.0)
	for i in [coin, vac]:
		assert_float(pm.hop_next[i]).is_less(0.0)
		assert_float(pm.hop_t[i]).is_less(0.0)
		assert_float(pm.glint_next[i]).is_less(0.0)
		assert_float(pm.glint_t[i]).is_less(0.0)
	# the vacuum floats as a gem does, the coin lying flat and spinning as it did
	var xf := _drawn(pm, vac)
	assert_float(xf.origin.y).is_equal_approx(pm.pos[vac].y + PickupManager.float_y(vac, pm._time), 0.0001)


# ---------------------------------------------------------------- 4. glints

func test_only_medium_and_large_gems_glint_each_on_its_own_clock() -> void:
	assert_float((PickupManager.GLINT_EVERY[PickupManager.KIND_GEM_L] as Vector2).y).is_less_equal((PickupManager.GLINT_EVERY[PickupManager.KIND_GEM_M] as Vector2).y)
	var pm: PickupManager = _pickups()["pm"]
	var s := _resting(pm, PickupManager.KIND_GEM_S, 20.0)
	var m := _resting(pm, PickupManager.KIND_GEM_M, 22.0)
	var l := _resting(pm, PickupManager.KIND_GEM_L, 24.0)
	var t0: float = pm._time
	pm._physics_process(DT)
	assert_float(pm.glint_next[s]).is_less(0.0)
	var wm: Vector2 = PickupManager.GLINT_EVERY[PickupManager.KIND_GEM_M]
	var wl: Vector2 = PickupManager.GLINT_EVERY[PickupManager.KIND_GEM_L]
	assert_float(pm.glint_next[m] - t0).is_between(wm.x, wm.y + DT)
	assert_float(pm.glint_next[l] - t0).is_between(wl.x, wl.y + DT)
	# "now and then": a few seconds apart, not a twinkle every frame
	assert_float(wm.x).is_greater_equal(3.0)
	assert_float(wl.x).is_greater_equal(2.5)
	assert_float(wm.y).is_less_equal(8.0)
	# over half a minute the medium and large ones glint several times, the small one never
	var seen := {s: 0, m: 0, l: 0}
	for step in range(int(30.0 / DT)):
		pm._physics_process(DT)
		for i in [s, m, l]:
			if pm.glint_t[i] >= 0.0 and pm.glint_t[i] < DT * 0.5:
				seen[i] += 1
	assert_int(seen[s]).is_equal(0)
	assert_int(seen[m]).is_between(3, 8)
	assert_int(seen[l]).is_between(4, 11)


func test_a_sea_of_gems_never_floods_the_screen_with_glints() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var gems: Array = []
	for g in range(120):
		gems.append(_resting(pm, PickupManager.KIND_GEM_M if g % 2 == 0 else PickupManager.KIND_GEM_L, -30.0 + float(g % 20) * 3.0, -20.0 - floorf(float(g) / 20.0) * 3.0))
	pm._physics_process(DT)
	# every one's turn comes at once
	for i: int in gems:
		pm.glint_next[i] = pm._time
		pm.idle_due[i] = pm._time
	pm._physics_process(DT)
	assert_int(pm.glint_count()).is_equal(1)
	var started := 0
	var most := 0
	var seconds := 5.0
	for step in range(int(seconds / DT)):
		for i: int in gems:
			if pm.glint_next[i] > pm._time:
				pm.glint_next[i] = pm._time
				pm.idle_due[i] = pm._time
		pm._physics_process(DT)
		for i: int in gems:
			if pm.glint_t[i] >= 0.0 and pm.glint_t[i] < DT * 0.5:
				started += 1
		most = maxi(most, pm.glint_count())
	# at most one start every GLINT_GAP s and never more than GLINT_MAX showing
	assert_int(started).is_less_equal(int(ceil(seconds / PickupManager.GLINT_GAP)) + 1)
	assert_int(started).is_greater(int(seconds / PickupManager.GLINT_GAP * 0.8))
	assert_int(most).is_less_equal(PickupManager.GLINT_MAX)
	# the count stays true as gems go: a glinting gem taken or merged takes its glint with it
	var live := 0
	for i: int in gems:
		if pm.glint_t[i] >= 0.0:
			live += 1
	assert_int(pm.glint_count()).is_equal(live)
	pm.clear_all()
	assert_int(pm.glint_count()).is_equal(0)


func test_a_glint_waits_for_its_gem_to_be_seen_below_the_hud_strip() -> void:
	var keep_band := HUD.band_h
	HUD.band_h = float(HUD.BAND_H)
	var w := _pickups()
	var pm: PickupManager = w["pm"]
	var rig := _camera(w)
	var cam: Camera3D = rig.camera
	var vp := rig.get_viewport().get_visible_rect().size
	var edge: float = HUD.band_h * vp.x / 1080.0
	# a spot up the screen under the strip: northwards from the hero until it shows above the strip's lower edge
	var under := Vector3.INF
	var d := 3.0
	while d < 300.0:
		var p := Vector3(0.0, PickupManager.rest_of(PickupManager.KIND_GEM_L), -d)
		var y: float = cam.unproject_position(p).y
		if rig.on_screen(p) and y < edge * 0.6 and y > 4.0:
			under = p
			break
		d += 0.25
	assert_bool(under != Vector3.INF).override_failure_message("no spot under the strip (viewport %s, edge %.0f)" % [vp, edge]).is_true()
	var mid := _resting(pm, PickupManager.KIND_GEM_L, 2.5, -2.0)
	var top := _resting(pm, PickupManager.KIND_GEM_L, under.x, under.z)
	var off := _resting(pm, PickupManager.KIND_GEM_L, 150.0, 0.0)
	# seen: on the screen and below the strip; the one under the strip is on the screen (a hop there counts) but unseen
	assert_bool(pm._on_screen(pm.pos[mid])).is_true()
	assert_bool(pm._on_screen(pm.pos[top])).is_false()
	assert_bool(pm._in_view(pm.pos[top])).is_true()
	assert_bool(pm._on_screen(pm.pos[off])).is_false()
	assert_bool(pm._in_view(pm.pos[off])).is_false()
	# the strip's edge scales with the canvas's width, as the thumb zone's does
	HUD.band_h = 0.0
	assert_bool(pm._on_screen(pm.pos[top])).is_true()
	HUD.band_h = float(HUD.BAND_H)
	pm._physics_process(DT)
	# the turns of the gems under the strip and off the screen come: no glint, and the field's allowance is not spent
	var last: float = pm._glint_last
	for i in [top, off]:
		pm.glint_next[i] = pm._time
		pm.idle_due[i] = pm._time
	pm._physics_process(DT)
	assert_float(pm.glint_t[top]).is_less(0.0)
	assert_float(pm.glint_t[off]).is_less(0.0)
	assert_float(pm._glint_last).is_equal(last)
	assert_int(pm.glint_count()).is_equal(0)
	# the one below the strip glints when its turn comes
	pm.glint_next[mid] = pm._time
	pm.idle_due[mid] = pm._time
	pm._physics_process(DT)
	assert_float(pm.glint_t[mid]).is_greater_equal(0.0)
	assert_int(pm.glint_count()).is_equal(1)
	HUD.band_h = keep_band


func test_a_glint_is_a_star_drawn_after_its_gem_and_under_the_paintings() -> void:
	var pm: PickupManager = _pickups()["pm"]
	var mm: MultiMesh = pm._glint_mm
	var mmi: MultiMeshInstance3D = null
	for c in pm.get_children():
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh == mm:
			mmi = c
	assert_object(mmi).is_not_null()
	var mat: ShaderMaterial = mmi.material_override
	assert_str(mat.shader.resource_path).is_equal("res://core/shaders/gem_glint.gdshader")
	assert_int(mat.render_priority).is_equal(PickupManager.PICKUP_PRIORITY + 1)
	assert_int(mat.render_priority).is_less_equal(BillboardSprite.OVER_PRIORITY)
	var code: String = mat.shader.code
	assert_str(code).contains("blend_add")
	assert_str(code).contains("stencil_mode read, compare_not_equal, %d;" % PickupManager.PAINTING_STENCIL)
	# one gem glinting: one star over its upper facets, paled from its colour, brightest a third of the way in
	var i := _resting(pm, PickupManager.KIND_GEM_L, 20.0)
	pm._physics_process(DT)
	pm._render()
	assert_int(mm.visible_instance_count).is_equal(0)
	pm.start_glint(i)
	pm.glint_t[i] = PickupManager.GLINT_TIME * 0.37
	var gem := _drawn(pm, i)
	assert_int(mm.visible_instance_count).is_equal(1)
	var star := pm.glint_xform(i, gem.origin)
	assert_float(star.origin.y).is_greater(gem.origin.y)
	assert_float(star.basis.get_scale().x).is_between(PickupManager.GLINT_SIZE * PickupManager.gem_radius(PickupManager.KIND_GEM_L) * 0.9, PickupManager.GLINT_SIZE * PickupManager.gem_radius(PickupManager.KIND_GEM_L) * 1.0001)
	var col := pm.glint_color(i)
	assert_float(col.a).is_greater(0.95)
	assert_float(col.r).is_greater(0.9)
	assert_float(PickupManager.glint_level(0.0)).is_equal(0.0)
	assert_float(PickupManager.glint_level(PickupManager.GLINT_TIME)).is_equal(0.0)
	# over: the star goes
	_tick(pm, PickupManager.GLINT_TIME)
	pm._render()
	assert_int(mm.visible_instance_count).is_equal(0)
	assert_int(pm.glint_count()).is_equal(0)
