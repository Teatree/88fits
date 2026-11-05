## Pass 126 (lane DRESS; Garry: "Let's add the telephone pole generation that cuts across the whole desert. There is never
## more than 1 line, it usually bends, but not a lot. It's often broken in many places and often doesn't have a line at
## all. The line moves with the wind a bit (more in Dust Bowl), the line isn't too much of an eye sore to interfere with the
## top down view."). One line of poles a map, from the wall to the wall on a chord that bends gently, laid from the run's
## map seed (MapDressing). The numbers are the map's `timeline_data.dressing.telephone` (MapDressing.DEFAULTS):
##   span [lo, hi]     metres from one pole to the next (the stretch of the whole line is shared out so it ends on the edge)
##   edge_in           the first and last pole stand this far inside the arena's edge
##   through           the chord passes at most this share of the arena's radius from the middle (so it crosses the desert)
##   bends [lo, hi], straight_chance, bend_offset, max_bend_deg    how many bends (none with `straight_chance`), how far off
##                     the chord they swing (metres) and the sharpest turn anywhere: the offsets are shrunk until every turn
##                     between two spans is under it
##   gap_chance, gap_run [lo, hi]     a run of `gap_run` poles missing starts here with this chance
##   snap_chance, fallen_chance       a pole snapped short; its top lying beside it with this chance
##   lean_chance, lean_deg [lo, hi], stand_lean_deg   a pole leaning a lot, and how much a standing one is off true at most
##   wire_chance       a span whose two poles both stand carries wire with this chance (with the gaps and the snaps: about
##                     half of all spans have none)
##   dangle_chance     where a standing pole has no wire on a side, a loose end hangs from it with this chance
##   wires             wires a span (1 or 2, one from each end of the crossarm)
##   sag [lo, hi]      metres the catenary hangs mid span, rolled per span
##   sway, sway_speed, wire_alpha, wire_width, wire_color     the wire's look (core/shaders/telephone_wire.gdshader)
## Nothing here is a rule: a pole has no collider and no obstacle circle (Garry: "I don't want them to get stuck", a thin post
## is what a creature would snag on, and they only steer round circles), so no creature, hero or shot ever reads it. The
## poles are drawn in the map's one dressing mesh (MapDressing), the wire here, in one mesh, moved by its shader alone.
class_name TelephoneLine
extends Node3D

const WIRE_SHADER := preload("res://core/shaders/telephone_wire.gdshader")
## After the water (-10), before the stage's filter (StageLook.PRIORITY -7): the filter dims the wire with the sand under it.
const WIRE_PRIORITY := -8
## The wire's anchors on the models (tools/blender_telephone.py: the two insulators' tops), (x, height), in the file's metres.
const ANCHORS := {
	"PoleA": [Vector2(-0.58, 5.3), Vector2(0.58, 5.3)],
	"PoleB": [Vector2(-0.58, 5.25), Vector2(0.58, 5.11)],
}
const WIRE_SEGS := 8
const DANGLE_SEGS := 5
## The poles' ground shadow: an upright post with its arm's reach, a snapped one (w, d, strength; PropField).
const SHADOW_POLE := Vector3(0.95, 0.62, 0.38)
const SHADOW_SNAP := Vector3(0.62, 0.42, 0.34)
## How far a pole may shift along the line to stand clear of what is there (MapDressing's `blocked`), metres, in steps.
const NUDGE_STEP := 0.8
const NUDGE_STEPS := 3
## Times the offsets shrink, at most, to bring every turn under max_bend_deg.
const SHRINK := 0.8
const SHRINK_TRIES := 24

## The bends' way points, first and last on the edge (x, z).
var waypoints := PackedVector2Array()
## One row per spot along the line, first to last, whether a pole stands there or not: {spot: Vector2 (on the course), pos:
## Vector2 (where it stands, nudged clear of what is there), foot: Vector3, state: "standing" | "leaning" | "snapped" |
## "missing", mesh: String, xf: Transform3D, lean: degrees, fallen: bool}.
var poles: Array = []
## One row per pair of neighbouring spots: {a, b (indices in poles), wired: bool}.
var spans: Array = []
## Loose wire ends drawn ({pole, side}), for tests and captures.
var dangles: Array = []
var _mat: ShaderMaterial
var _wires: MeshInstance3D
var _wind := 1.0


## Lays the line: `rng` is the line's own stream off the map seed; `blocked` (a Vector2 -> bool Callable) says a pole cannot
## stand at a spot; `ground` (x, z -> height).
func lay(radius: float, cfg: Dictionary, rng: RandomNumberGenerator, blocked: Callable, ground: Callable) -> void:
	var spots := _roll_course(radius, cfg, rng)
	_roll_poles(spots, cfg, rng, blocked, ground)
	_roll_spans(cfg, rng)
	_build_wires(cfg, rng)


## The wind on the wire (lane STAGE's RedCanyon.set_weather, `weather.wire_sway`): 1 = the normal sway, more in a Dust Bowl.
func set_wind(mult: float) -> void:
	_wind = maxf(mult, 0.0)
	if _mat:
		_mat.set_shader_parameter("wind", _wind)


## What the wire's shader is playing now (tests).
func wind() -> float:
	return _wind


## How many poles stand in some form (not missing).
func standing_count() -> int:
	return poles.filter(func(p: Dictionary) -> bool: return p["state"] != "missing").size()


## The share of all spans with no wire.
func bare_share() -> float:
	if spans.is_empty():
		return 1.0
	return 1.0 - float(spans.filter(func(s: Dictionary) -> bool: return s["wired"]).size()) / float(spans.size())


## The chord, its bends and the spots along it. Returns the spots (Vector2s); sets `waypoints`.
func _roll_course(radius: float, cfg: Dictionary, rng: RandomNumberGenerator) -> PackedVector2Array:
	var r_edge := radius - float(cfg["edge_in"])
	var a0 := rng.randf() * TAU
	var p0 := Vector2(cos(a0), sin(a0)) * r_edge
	var ta := rng.randf() * TAU
	var t_r := sqrt(rng.randf()) * radius * float(cfg["through"])
	var d := (Vector2(cos(ta), sin(ta)) * t_r - p0).normalized()
	var p1 := p0 + d * (-2.0 * p0.dot(d))
	var perp := d.rotated(PI * 0.5)
	var bends_r: Array = cfg["bends"]
	var n_bends := 0 if rng.randf() < float(cfg["straight_chance"]) else rng.randi_range(int(bends_r[0]), int(bends_r[1]))
	var fracs := PackedFloat32Array()
	var offs := PackedFloat32Array()
	for k in n_bends:
		fracs.append(float(k + 1) / float(n_bends + 1) + rng.randf_range(-0.05, 0.05))
		var off := rng.randf_range(0.35, 1.0) * float(cfg["bend_offset"])
		offs.append(off if rng.randf() < 0.5 else -off)
	# the spans' shares: more than the line can need, rolled once, so shrinking below draws nothing more
	var span_r: Array = cfg["span"]
	var mean_span := (float(span_r[0]) + float(span_r[1])) * 0.5
	var shares := PackedFloat32Array()
	for k in int(radius * 2.0 / maxf(float(span_r[0]), 1.0)) + 8:
		shares.append(rng.randf_range(float(span_r[0]) + 0.4, float(span_r[1]) - 0.4))
	var limit := float(cfg["max_bend_deg"])
	var spots := PackedVector2Array()
	var scale_off := 1.0
	for attempt in SHRINK_TRIES:
		waypoints = PackedVector2Array([p0])
		for k in n_bends:
			waypoints.append(p0.lerp(p1, fracs[k]) + perp * offs[k] * scale_off)
		waypoints.append(p1)
		spots = _spots_along(waypoints, mean_span, shares)
		if maxf(sharpest_turn(waypoints), sharpest_turn(spots)) < limit:
			return spots
		scale_off *= SHRINK
	waypoints = PackedVector2Array([p0, p1])
	return _spots_along(waypoints, mean_span, shares)


## The sharpest turn along a run of points, in degrees.
static func sharpest_turn(pts: PackedVector2Array) -> float:
	var worst := 0.0
	for k in range(1, pts.size() - 1):
		worst = maxf(worst, absf(rad_to_deg((pts[k] - pts[k - 1]).angle_to(pts[k + 1] - pts[k]))))
	return worst


## The spots along a course: as many spans as a mean span fits, shared out by `shares`, first and last on the course's ends.
static func _spots_along(way: PackedVector2Array, mean_span: float, shares: PackedFloat32Array) -> PackedVector2Array:
	var total := 0.0
	for k in range(way.size() - 1):
		total += way[k].distance_to(way[k + 1])
	var n := clampi(roundi(total / maxf(mean_span, 1.0)), 2, shares.size())
	var sum := 0.0
	for k in n:
		sum += shares[k]
	var out := PackedVector2Array([way[0]])
	var walked := 0.0
	for k in n - 1:
		walked += shares[k] * total / sum
		out.append(_at_length(way, walked))
	out.append(way[way.size() - 1])
	return out


static func _at_length(way: PackedVector2Array, s: float) -> Vector2:
	var left := s
	for k in range(way.size() - 1):
		var len_k := way[k].distance_to(way[k + 1])
		if left <= len_k:
			return way[k].lerp(way[k + 1], left / maxf(len_k, 0.001))
		left -= len_k
	return way[way.size() - 1]


## What became of each spot. Every spot draws the same dice whatever it turns out to be, so a spot blocked by a prop changes
## nothing further along.
func _roll_poles(spots: PackedVector2Array, cfg: Dictionary, rng: RandomNumberGenerator, blocked: Callable, ground: Callable) -> void:
	poles.clear()
	var gap_left := 0
	var last := spots.size() - 1
	var run_r: Array = cfg["gap_run"]
	var lean_r: Array = cfg["lean_deg"]
	for k in spots.size():
		var r_gap := rng.randf()
		var gap_len := rng.randi_range(int(run_r[0]), int(run_r[1]))
		var r_snap := rng.randf()
		var r_lean := rng.randf()
		var lean_big := rng.randf_range(float(lean_r[0]), float(lean_r[1]))
		var lean_small := rng.randf_range(0.0, float(cfg["stand_lean_deg"]))
		var lean_axis := rng.randf() * TAU
		var size := rng.randf_range(0.94, 1.08)
		var r_mesh := rng.randf()
		var r_fall := rng.randf()
		var fall_off := Vector2(rng.randf_range(0.6, 1.3), 0).rotated(rng.randf() * TAU)
		var fall_yaw := rng.randf() * TAU
		var end := k == 0 or k == last
		var state := "standing"
		if end:
			state = "leaning" if r_lean < float(cfg["lean_chance"]) * 0.5 else "standing"
		elif gap_left > 0:
			state = "missing"
			gap_left -= 1
		elif r_gap < float(cfg["gap_chance"]):
			state = "missing"
			gap_left = gap_len - 1
		elif r_snap < float(cfg["snap_chance"]):
			state = "snapped"
		elif r_lean < float(cfg["lean_chance"]):
			state = "leaning"
		var pos := spots[k]
		var along := (spots[mini(k + 1, last)] - spots[maxi(k - 1, 0)]).normalized()
		if state != "missing":
			var clear := _clear_spot(pos, along, blocked)
			if clear.is_finite():
				pos = clear
			elif not end:
				state = "missing"
		var foot := Vector3(pos.x, float(ground.call(pos.x, pos.y)), pos.y)
		var mesh := ""
		var lean := 0.0
		var xf := Transform3D()
		if state != "missing":
			lean = lean_big if state == "leaning" else lean_small
			if state == "snapped":
				mesh = "SnapA" if r_mesh < 0.6 else "SnapB"
			else:
				mesh = "PoleA" if r_mesh < 0.65 else "PoleB"
			var yaw := atan2(along.x, along.y)
			var axis := Vector3(cos(lean_axis), 0.0, sin(lean_axis))
			xf = Transform3D(Basis(axis, deg_to_rad(lean)) * Basis(Vector3.UP, yaw) * Basis().scaled(Vector3.ONE * size), foot)
		poles.append({"spot": spots[k], "pos": pos, "foot": foot, "state": state, "mesh": mesh, "xf": xf, "lean": lean, "fallen": state == "snapped" and r_fall < float(cfg["fallen_chance"]),
			"fall_off": fall_off, "fall_yaw": fall_yaw})


## `pos`, or the nearest spot along the line a pole can stand; INF when none is near.
func _clear_spot(pos: Vector2, along: Vector2, blocked: Callable) -> Vector2:
	if not bool(blocked.call(pos)):
		return pos
	for k in range(1, NUDGE_STEPS + 1):
		for s: float in [1.0, -1.0]:
			var q := pos + along * NUDGE_STEP * float(k) * s
			if not bool(blocked.call(q)):
				return q
	return Vector2.INF


func _roll_spans(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	spans.clear()
	for k in range(poles.size() - 1):
		var r_wire := rng.randf()
		var a: Dictionary = poles[k]
		var b: Dictionary = poles[k + 1]
		var both := _carries(a) and _carries(b)
		spans.append({"a": k, "b": k + 1, "wired": both and r_wire < float(cfg["wire_chance"])})


## Does this pole hold a wire up: standing or leaning, not snapped, not gone.
static func _carries(p: Dictionary) -> bool:
	return p["state"] == "standing" or p["state"] == "leaning"


## The ends of a pole's wires in the world, one per anchor.
static func anchors_of(p: Dictionary) -> Array:
	var out: Array = []
	var xf: Transform3D = p["xf"]
	for a: Vector2 in ANCHORS.get(p["mesh"], []):
		out.append(xf * Vector3(a.x, a.y, 0.0))
	return out


## Every span's wire and every loose end in one ribbon mesh.
func _build_wires(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var sag_r: Array = cfg["sag"]
	var wires := clampi(int(cfg["wires"]), 1, 2)
	dangles.clear()
	for s: Dictionary in spans:
		var phase := rng.randf()
		var sag := rng.randf_range(float(sag_r[0]), float(sag_r[1]))
		var r_dangle := rng.randf()
		var dangle_len := rng.randf_range(1.2, 2.8)
		var pa: Dictionary = poles[s["a"]]
		var pb: Dictionary = poles[s["b"]]
		if bool(s["wired"]):
			var ea := anchors_of(pa)
			var eb := anchors_of(pb)
			for w in wires:
				# with one wire, the crossarm's far end (the one the camera sees whole)
				var side := w if wires == 2 else 1
				_ribbon(v, n, c, uv, idx, _catenary(ea[side], eb[side], sag * (1.0 + 0.12 * float(w))), phase + 0.07 * float(w))
		elif r_dangle < float(cfg["dangle_chance"]) and (_carries(pa) or _carries(pb)):
			var from: Dictionary = pa if _carries(pa) else pb
			var to: Dictionary = pb if _carries(pa) else pa
			var ends := anchors_of(from)
			var side := int(phase * 2.0) % ends.size()
			var dir := (Vector3(to["foot"]) - Vector3(from["foot"])).normalized()
			_ribbon(v, n, c, uv, idx, _dangle(ends[side], dir, dangle_len), phase, true)
			dangles.append({"pole": s["a"] if _carries(pa) else s["b"], "side": side})
	if v.is_empty():
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mat = ShaderMaterial.new()
	_mat.shader = WIRE_SHADER
	_mat.render_priority = WIRE_PRIORITY
	_mat.set_shader_parameter("wire_color", Color.html(str(cfg["wire_color"])))
	_mat.set_shader_parameter("alpha", float(cfg["wire_alpha"]))
	_mat.set_shader_parameter("width_k", float(cfg["wire_width"]))
	_mat.set_shader_parameter("sway", float(cfg["sway"]))
	_mat.set_shader_parameter("sway_speed", float(cfg["sway_speed"]))
	_mat.set_shader_parameter("wind", _wind)
	_wires = MeshInstance3D.new()
	_wires.name = "Wires"
	_wires.mesh = am
	_wires.material_override = _mat
	_wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the mesh's own box and the most the shader's swing can add
	var box := am.get_aabb()
	_wires.custom_aabb = box.grow(1.5)
	add_child(_wires)


## A hanging wire between two points: a true catenary, `sag` metres under their straight line mid span.
static func _catenary(a: Vector3, b: Vector3, sag: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var k := 1.2
	var denom := cosh(k) - 1.0
	for j in WIRE_SEGS + 1:
		var s := float(j) / float(WIRE_SEGS)
		var hang := (cosh(k * (2.0 * s - 1.0)) - cosh(k)) / denom
		out.append(a.lerp(b, s) + Vector3(0.0, hang * sag, 0.0))
	return out


## A snapped wire's loose end: from the anchor, out along `dir` a little and hanging down `length` metres.
static func _dangle(a: Vector3, dir: Vector3, length: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for j in DANGLE_SEGS + 1:
		var s := float(j) / float(DANGLE_SEGS)
		out.append(a + dir * (0.35 * length * sin(s * PI * 0.5)) + Vector3(0.0, -length * s * s, 0.0))
	return out


## One ribbon along `pts`. A wire is held at both ends; a loose end (`loose`) only at its first point.
func _ribbon(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, idx: PackedInt32Array, pts: PackedVector3Array, phase: float, loose := false) -> void:
	var base := v.size()
	var last := pts.size() - 1
	for j in pts.size():
		var s := float(j) / float(last)
		var along := (pts[mini(j + 1, last)] - pts[maxi(j - 1, 0)]).normalized()
		var w := s * 1.4 if loose else 4.0 * s * (1.0 - s)
		var col := Color(w, fposmod(phase, 1.0), s, 1.0)
		for side: float in [-1.0, 1.0]:
			v.append(pts[j])
			n.append(along)
			c.append(col)
			uv.append(Vector2(side, 0.0))
		if j < last:
			var q := base + j * 2
			idx.append_array(PackedInt32Array([q, q + 1, q + 2, q + 1, q + 3, q + 2]))
