## Pass 126 (lane DRESS; Garry: "I would like to avoid any kinds of generation elements that create big obstacles for
## players to have trouble traversing. Our enemies don't think ... I don't want them to get stuck."): the map's small
## dressing, laid at the end of RedCanyon's scatter from its own dice off the run's map seed (so a replay lays the same, and
## the scatter's stream draws nothing more: every other thing on a seed's map stands where it stood):
##   the telephone line (TelephoneLine: a child of the map named "TelephoneLine"),
##   the toppled cart (a painted prop `cart_toppled`, 75% of runs) with one or two 3D wheels lying near it,
##   the grave crosses: 2-6 sites, each one cross or a lump of three.
## Only the cart has a collider and an obstacle circle (as any painting with a radius). The poles, the wheels and the crosses
## are walked through: nothing reads them, so no rule changes.
## The map's `timeline_data.dressing` {telephone, cart, graves}; DEFAULTS fill every key it leaves out (no block = the
## defaults; TelephoneLine's header names the telephone keys). `enabled` false leaves a thing out.
##   cart: chance; scale (of the painting's props.json size); flat_radius, flat_max: the land under the cart and its wheels: over
##     a disc this wide the ground may rise and fall this many metres at most (tries spots drawn, the flattest kept if no spot
##     passes); keep: metres its footprint keeps from what stands there (Garry: "pretty close to other environment
##     assets, just as long as it doesn't interfere"); wheels [1, 2]; wheel_dist [lo, hi] metres from the cart's foot, two
##     wheels at least wheel_apart metres different; wheel_lean_deg [lo, hi] from lying flat, towards the camera give or take
##     wheel_face_deg; wheel_sink [lo, hi] the share of its height under the sand, wheel_scale [lo, hi]
##   graves: sites [2, 6]; lump_chance a site is a lump of lump_count crosses within lump_spread metres; site_apart metres
##     between sites; stick_chance a cross is only a bare stick; tilt_deg [lo, hi] every cross's lean, crooked_chance
##     for crooked_deg instead; size [lo, hi]; sink [lo, hi] metres; yaw_deg how far off facing south a cross turns, so
##     none shows the camera only its edge
## The 3D things are one merged mesh, one draw call (core/shaders/dress_depth.gdshader, stencil 4 scenery), built here
## when the map builds from the models' own vertices (tools/blender_telephone.py, blender_wheel.py, blender_grave_cross.py).
class_name MapDressing
extends Node3D

const LINE := preload("res://core/systems/TelephoneLine.gd")
const SHADER := preload("res://core/shaders/dress_depth.gdshader")
const KITS := ["res://art/props/telephone_pole.glb", "res://art/props/wagon_wheel.glb", "res://art/props/grave_cross.glb"]
const CART_ID := "cart_toppled"
## The wheel's radius in its file (tools/blender_wheel.py RADIUS), metres.
const WHEEL_R := 0.62
const CROSSES := ["Cross0", "Cross1", "Cross2", "Cross3", "Cross4", "Cross5", "Cross6", "Cross7", "Cross8", "Cross9"]
const STICKS := ["Stick0", "Stick1"]
const WHEELS := ["WheelA", "WheelB", "WheelC"]
const DEFAULTS := {
	"telephone": {
		"enabled": true, "span": [9.0, 12.0], "edge_in": 2.6, "through": 0.45,
		"bends": [1, 3], "straight_chance": 0.1, "bend_offset": 9.0, "max_bend_deg": 14.0,
		"gap_chance": 0.15, "gap_run": [1, 3], "snap_chance": 0.12, "fallen_chance": 0.55,
		"lean_chance": 0.3, "lean_deg": [9.0, 26.0], "stand_lean_deg": 3.0,
		"wire_chance": 0.9, "dangle_chance": 0.35, "wires": 2, "sag": [0.55, 1.0],
		"sway": 0.07, "sway_speed": 1.1, "wire_alpha": 0.5, "wire_width": 0.0016, "wire_color": "#2b221c",
	},
	"cart": {
		"enabled": true, "chance": 0.75, "scale": 1.0, "flat_radius": 5.0, "flat_max": 0.55, "tries": 900, "keep": 1.8,
		"wheels": [1, 2], "wheel_dist": [1.9, 5.0], "wheel_apart": 0.9,
		"wheel_lean_deg": [15.0, 70.0], "wheel_face_deg": 70.0, "wheel_sink": [0.05, 0.5], "wheel_scale": [1.0, 1.2],
	},
	"graves": {
		"enabled": true, "sites": [2, 6], "lump_chance": 0.25, "lump_count": 3, "lump_spread": [1.1, 1.9], "site_apart": 12.0,
		"stick_chance": 0.05, "tilt_deg": [3.0, 9.0], "crooked_chance": 0.4, "crooked_deg": [10.0, 18.0],
		"size": [1.0, 1.35], "sink": [0.0, 0.12], "yaw_deg": 50.0,
	},
}

## What came of the dice (tests, captures).
## The cart: {} when the run has none, else {pos: Vector2, foot: Vector3, radius, drawn_h, flat (metres of rise and fall measured),
## wheels: [{pos: Vector2, dist, lean, sink, mesh, xf}]}.
var cart: Dictionary = {}
## The grave sites: [{center: Vector2, crosses: [{pos: Vector2, mesh, stick: bool, lean, yaw, size, sink, xf}]}].
var graves: Array = []
var line: LINE
## (x, z, r) of everything here without a collider: what a structure placed later keeps off (RedCanyon.dress_clear).
var keep_spots: Array = []
var map: Node3D
var cfg: Dictionary = {}
var _taken: Array = []
var _free: Callable
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()
var _idx := PackedInt32Array()

## name -> {v, n, c, i}: the models' own vertices, read once per process.
static var _kit: Dictionary = {}


## A block whole: DEFAULTS with `block`'s keys laid over, section by section.
static func config_of(block) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	if not block is Dictionary:
		return out
	for section: String in DEFAULTS:
		var given = (block as Dictionary).get(section)
		if not given is Dictionary:
			continue
		for k in (given as Dictionary).keys():
			if (out[section] as Dictionary).has(k):
				out[section][k] = (given as Dictionary)[k]
	return out


## A stream of dice of its own for each thing, so re-tuning one never moves another.
static func stream(run_seed: int, what: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, "dressing", what])
	return rng


## Whether a map seed's run has a cart (the stream's first draw).
static func rolls_cart(run_seed: int, chance: float) -> bool:
	return stream(run_seed, "cart").randf() < chance


## Lays everything on `p_map` (RedCanyon: its height_at, props, lakes, river). `taken` and `free` are its scatter's (Vector3(x,
## z, keep-out) rows and the check over them), and what is laid here joins `taken`.
func lay(p_map: Node3D, taken: Array, free: Callable, run_seed: int, block) -> void:
	map = p_map
	_taken = taken
	_free = free
	cfg = config_of(block)
	if bool(cfg["cart"]["enabled"]):
		_lay_cart(cfg["cart"], stream(run_seed, "cart"))
	if bool(cfg["telephone"]["enabled"]):
		_lay_line(cfg["telephone"], stream(run_seed, "telephone"))
	if bool(cfg["graves"]["enabled"]):
		_lay_graves(cfg["graves"], stream(run_seed, "graves"))
	_build_mesh()


## Clear of everything here by `r` metres? (Things placed later: RedCanyon.dress_clear.)
func clear_of(p: Vector2, r: float) -> bool:
	for s: Vector3 in keep_spots:
		if p.distance_to(Vector2(s.x, s.y)) < s.z + r:
			return false
	return true


func _props() -> PropField:
	return map.get("props") as PropField


func _ground_h(x: float, z: float) -> float:
	return float(map.call("height_at", x, z))


# ---------------------------------------------------------------- the cart

## The ground's rise and fall over a disc: its middle and two rings of eight points, in metres.
func flatness(pt: Vector2, radius: float) -> float:
	var lo := _ground_h(pt.x, pt.y)
	var hi := lo
	for ring: float in [0.5, 1.0]:
		for k in 8:
			var a := TAU * (float(k) + ring) / 8.0
			var h := _ground_h(pt.x + cos(a) * radius * ring, pt.y + sin(a) * radius * ring)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


## Could the cart's footprint stand here? `free` (the flats, the wall, the river bed, the lakes, what is there) with the keep,
## then the same places again by the whole footprint's width.
func _cart_ground_ok(pt: Vector2, keep: float) -> bool:
	if not bool(_free.call(pt, keep)):
		return false
	var fc3: Vector3 = map.get("flats_center")
	if pt.distance_to(Vector2(fc3.x, fc3.z)) < float(map.get("flats_radius")) + 3.0 + keep:
		return false
	if pt.length() > float(map.get("arena_radius")) - 5.0 - keep:
		return false
	if float(map.call("_river_dist", pt)) < float(map.get("river_width")) * 0.5 + 1.0 + keep:
		return false
	return float(map.call("_lake_edge", pt)) >= 1.2 + keep


func _lay_cart(c: Dictionary, rng: RandomNumberGenerator) -> void:
	if rng.randf() >= float(c["chance"]):
		return
	var props := _props()
	if props == null or not props.has(CART_ID):
		return
	var want: int = rng.randi_range(int(c["wheels"][0]), int(c["wheels"][1]))
	var keep := float(c["keep"])
	var rmin := float(map.get("flats_radius")) + 4.0
	var rmax := float(map.get("arena_radius")) - 5.0 - keep
	var best := Vector2.INF
	var best_flat := INF
	var best_wheels: Array = []
	var radius := float(c["flat_radius"])
	for k in int(c["tries"]):
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var pt := Vector2(cos(a) * r, sin(a) * r)
		if not _cart_ground_ok(pt, keep):
			continue
		var flat := flatness(pt, radius)
		if flat >= best_flat:
			continue
		var wheels := _roll_wheels(c, rng, pt, want)
		if wheels.size() < want:
			continue
		best = pt
		best_flat = flat
		best_wheels = wheels
		if flat <= float(c["flat_max"]):
			break
	if not best.is_finite():
		return
	var g := Vector3(best.x, _ground_h(best.x, best.y), best.y)
	var sc := float(c["scale"])
	var drawn := props.height_of(CART_ID) * sc
	var r_col := props.radius_of(CART_ID) * sc
	props.add(CART_ID, g, sc, rng.randf() < 0.5, 0.0)
	if map.has_method("_sprite_collider"):
		map.call("_sprite_collider", g, r_col, drawn)
	_taken.append(Vector3(best.x, best.y, maxf(r_col, keep)))
	cart = {"pos": best, "foot": g, "radius": r_col, "drawn_h": drawn, "flat": best_flat, "wheels": best_wheels}
	for w: Dictionary in best_wheels:
		_add(str(w["mesh"]), w["xf"], w["foot"], 0.0)
		var p: Vector2 = w["pos"]
		_taken.append(Vector3(p.x, p.y, 0.7))
		keep_spots.append(Vector3(p.x, p.y, 0.7))
		var lean_c := cos(deg_to_rad(float(w["lean"])))
		var across := 2.0 * WHEEL_R * float(w["size"]) * (0.5 + 0.5 * lean_c)
		props.add_shadow(w["foot"], across, across * 0.72, 0.36, WHEEL_R)


## `want` wheels near the cart at `pt`, or fewer when the spot leaves no room. Every distance is its own roll and two wheels
## differ by at least wheel_apart.
func _roll_wheels(c: Dictionary, rng: RandomNumberGenerator, pt: Vector2, want: int) -> Array:
	var out: Array = []
	var lo := float(c["wheel_dist"][0])
	var hi := float(c["wheel_dist"][1])
	var apart := float(c["wheel_apart"])
	var half_w := _props().height_of(CART_ID) * float(c["scale"]) * 0.5
	for w in want:
		var found := false
		for k in 24:
			var d := rng.randf_range(lo, hi)
			if not out.is_empty() and absf(d - float(out[0]["dist"])) < apart:
				continue
			var a := rng.randf() * TAU
			var p := pt + Vector2(cos(a), sin(a)) * d
			# not behind the painting: the camera looks north, so a wheel just north of the cart would be hidden by it
			if p.y < pt.y and absf(p.x - pt.x) < half_w:
				continue
			if not out.is_empty() and p.distance_to(out[0]["pos"]) < WHEEL_R * 2.2:
				continue
			if not _wheel_ground_ok(p):
				continue
			out.append(_make_wheel(c, rng, p, d))
			found = true
			break
		if not found:
			break
	return out


func _wheel_ground_ok(p: Vector2) -> bool:
	if float(map.call("_lake_edge", p)) < 1.5:
		return false
	if float(map.call("_river_dist", p)) < float(map.get("river_width")) * 0.5 + 1.0:
		return false
	if p.length() > float(map.get("arena_radius")) - 4.0:
		return false
	for t: Vector3 in _taken:
		if p.distance_to(Vector2(t.x, t.y)) < t.z + WHEEL_R:
			return false
	return true


## A wheel lying at `p`: leaning `lean` degrees up from flat, `sink` of its height under the sand (some half sunk, some nearly
## out), its hub on the line that gives; the terrain hides what is under it.
func _make_wheel(c: Dictionary, rng: RandomNumberGenerator, p: Vector2, dist: float) -> Dictionary:
	var lean := rng.randf_range(float(c["wheel_lean_deg"][0]), float(c["wheel_lean_deg"][1]))
	var sink := rng.randf_range(float(c["wheel_sink"][0]), float(c["wheel_sink"][1]))
	var size := rng.randf_range(float(c["wheel_scale"][0]), float(c["wheel_scale"][1]))
	# it leans towards the camera, give or take wheel_face_deg (a wheel leaning away shows only its rim, no spokes), and is
	# spun on its own axle
	var face := deg_to_rad(float(c["wheel_face_deg"]))
	var yaw := rng.randf_range(-face, face)
	var spin := rng.randf() * TAU
	var mesh: String = WHEELS[rng.randi() % WHEELS.size()]
	var h := _ground_h(p.x, p.y)
	var hub_y := h + WHEEL_R * size * sin(deg_to_rad(lean)) * (1.0 - 2.0 * sink)
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(lean)) * Basis(Vector3.UP, spin) * Basis().scaled(Vector3.ONE * size)
	return {"pos": p, "foot": Vector3(p.x, h, p.y), "dist": dist, "lean": lean, "sink": sink, "size": size, "mesh": mesh, "xf": Transform3D(turn, Vector3(p.x, hub_y, p.y))}


# ---------------------------------------------------------------- the line

func _lay_line(c: Dictionary, rng: RandomNumberGenerator) -> void:
	line = LINE.new()
	line.name = "TelephoneLine"
	map.add_child(line)
	var ground := func(x: float, z: float) -> float: return _ground_h(x, z)
	line.lay(float(map.get("arena_radius")), c, rng, _pole_blocked, ground)
	var props := _props()
	for p: Dictionary in line.poles:
		if p["state"] == "missing":
			continue
		var pos: Vector2 = p["pos"]
		_add(str(p["mesh"]), p["xf"], p["foot"], 1.0)
		_taken.append(Vector3(pos.x, pos.y, 0.5))
		keep_spots.append(Vector3(pos.x, pos.y, 0.4))
		var sh: Vector3 = LINE.SHADOW_SNAP if p["state"] == "snapped" else LINE.SHADOW_POLE
		if props:
			props.add_shadow(p["foot"], sh.x, sh.y, sh.z, 1.5 if p["state"] == "snapped" else 5.6)
		if bool(p["fallen"]):
			_add_fallen(p)


## The snapped-off top lying by its pole: flat on the sand along its length, whichever way the ground slopes.
func _add_fallen(p: Dictionary) -> void:
	var pos: Vector2 = Vector2(p["pos"]) + Vector2(p["fall_off"])
	var yaw := float(p["fall_yaw"])
	var run := Vector2(cos(yaw), -sin(yaw)) * 3.0
	if float(map.call("_lake_edge", pos + run * 0.5)) < 1.0 or float(map.call("_lake_edge", pos)) < 1.0 or (pos + run).length() > float(map.get("arena_radius")) - 2.0:
		p["fallen"] = false
		return
	var h0 := _ground_h(pos.x, pos.y)
	var h1 := _ground_h(pos.x + run.x, pos.y + run.y)
	var pitch := atan2(h1 - h0, 3.0)
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch)
	var foot := Vector3(pos.x + run.x * 0.5, (h0 + h1) * 0.5, pos.y + run.y * 0.5)
	_add("Fallen", Transform3D(turn, Vector3(pos.x, h0, pos.y)), foot, 0.0)
	keep_spots.append(Vector3(foot.x, foot.z, 1.2))


## A pole keeps out of the water, off the hero's start and off what stands on the map. The dry river's bed may carry one.
func _pole_blocked(pt: Vector2) -> bool:
	if float(map.call("_lake_edge", pt)) < 0.8:
		return true
	if map.has_method("player_start"):
		var st: Vector3 = map.call("player_start")
		if pt.distance_to(Vector2(st.x, st.z)) < 5.0:
			return true
	for t: Vector3 in _taken:
		if pt.distance_to(Vector2(t.x, t.y)) < t.z + 0.35:
			return true
	return false


# ---------------------------------------------------------------- the graves

func _lay_graves(c: Dictionary, rng: RandomNumberGenerator) -> void:
	var bag: Array = []
	var count: int = rng.randi_range(int(c["sites"][0]), int(c["sites"][1]))
	var apart := float(c["site_apart"])
	var rmin := float(map.get("flats_radius")) + 4.0
	var rmax := float(map.get("arena_radius")) - 6.0
	var props := _props()
	for s in count:
		var centre := Vector2.INF
		for k in 500:
			var a := rng.randf() * TAU
			var r := rng.randf_range(rmin, rmax)
			var pt := Vector2(cos(a) * r, sin(a) * r)
			if not bool(_free.call(pt, 0.5)):
				continue
			# past half the tries the sites may close in on each other
			var need := apart if k < 250 else apart * 0.5
			var ok := true
			for g: Dictionary in graves:
				if pt.distance_to(g["center"]) < need:
					ok = false
					break
			if ok:
				centre = pt
				break
		if not centre.is_finite():
			continue
		var lump: bool = rng.randf() < float(c["lump_chance"])
		var n := int(c["lump_count"]) if lump else 1
		var site := {"center": centre, "crosses": []}
		for j in n:
			var at := centre if j == 0 else _lump_spot(c, rng, centre, site["crosses"])
			var cross := _make_cross(c, rng, at, bag)
			(site["crosses"] as Array).append(cross)
			_add(str(cross["mesh"]), cross["xf"], cross["foot"], 1.0)
			_taken.append(Vector3(at.x, at.y, 0.5))
			keep_spots.append(Vector3(at.x, at.y, 0.5))
			if props:
				var size := float(cross["size"])
				var w := 0.42 if bool(cross["stick"]) else 0.72
				props.add_shadow(cross["foot"], w * size, w * size * 0.62, 0.34, 1.2 * size)
		graves.append(site)


## A spot in a lump: lump_spread metres from the first cross, clear of the others. A crowded place takes the last roll: a
## cross overlapping a bush harms nothing, as long as it is out of the water.
func _lump_spot(c: Dictionary, rng: RandomNumberGenerator, centre: Vector2, others: Array) -> Vector2:
	var at := centre
	for k in 24:
		var a := rng.randf() * TAU
		var r := rng.randf_range(float(c["lump_spread"][0]), float(c["lump_spread"][1]))
		var q := centre + Vector2(cos(a), sin(a)) * r
		if float(map.call("_lake_edge", q)) < 1.2:
			continue
		at = q
		var clear := true
		for o: Dictionary in others:
			if q.distance_to(o["pos"]) < 0.9:
				clear = false
		if clear and bool(_free.call(q, 0.2)):
			return q
	return at


func _make_cross(c: Dictionary, rng: RandomNumberGenerator, at: Vector2, bag: Array) -> Dictionary:
	var stick: bool = rng.randf() < float(c["stick_chance"])
	var crooked: bool = rng.randf() < float(c["crooked_chance"])
	var range_d: Array = c["crooked_deg"] if crooked else c["tilt_deg"]
	var lean := rng.randf_range(float(range_d[0]), float(range_d[1]))
	var axis_a := rng.randf() * TAU
	var yaw := deg_to_rad(rng.randf_range(-float(c["yaw_deg"]), float(c["yaw_deg"])))
	var back: bool = rng.randf() < 0.5
	var size := rng.randf_range(float(c["size"][0]), float(c["size"][1]))
	var sink := rng.randf_range(float(c["sink"][0]), float(c["sink"][1]))
	var mesh := ""
	if stick:
		mesh = STICKS[rng.randi() % STICKS.size()]
	else:
		if bag.is_empty():
			bag.append_array(CROSSES)
			for k in range(bag.size() - 1, 0, -1):
				var j := rng.randi() % (k + 1)
				var tmp = bag[k]
				bag[k] = bag[j]
				bag[j] = tmp
		mesh = str(bag.pop_back())
	var h := _ground_h(at.x, at.y)
	var axis := Vector3(cos(axis_a), 0.0, sin(axis_a))
	var turn := Basis(axis, deg_to_rad(lean)) * Basis(Vector3.UP, yaw + (PI if back else 0.0)) * Basis().scaled(Vector3.ONE * size)
	return {"pos": at, "foot": Vector3(at.x, h, at.y), "mesh": mesh, "stick": stick, "lean": lean, "yaw": yaw, "size": size, "sink": sink,
		"xf": Transform3D(turn, Vector3(at.x, h - sink, at.y))}


# ---------------------------------------------------------------- the mesh

## The models' vertices by object name, read once per process; {} when the files are not imported yet (then nothing is drawn
## and the layout stands).
static func kit() -> Dictionary:
	if not _kit.is_empty():
		return _kit
	for path: String in KITS:
		if not ResourceLoader.exists(path):
			continue
		var scene: Node = (load(path) as PackedScene).instantiate()
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (n as MeshInstance3D).mesh
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var v := PackedVector3Array()
			var nrm := PackedVector3Array()
			var col := PackedColorArray()
			var idx := PackedInt32Array()
			for s in mesh.get_surface_count():
				var arr: Array = mesh.surface_get_arrays(s)
				var base := v.size()
				var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				v.append_array(sv)
				nrm.append_array(arr[Mesh.ARRAY_NORMAL])
				if arr[Mesh.ARRAY_COLOR] is PackedColorArray and (arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() == sv.size():
					col.append_array(arr[Mesh.ARRAY_COLOR])
				else:
					for k in sv.size():
						col.append(Color(0.1, 0.07, 0.04))
				var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				for i in si:
					idx.append(base + i)
			_kit[str(n.name)] = {"v": v, "n": nrm, "c": col, "i": idx}
		scene.free()
	return _kit


## One model into the merged mesh at `xf`, its foot `foot`, `upright` 1 (a post, a cross) or 0 (a thing lying low): see
## dress_depth.gdshader.
func _add(id: String, xf: Transform3D, foot: Vector3, upright: float) -> void:
	var src: Dictionary = kit().get(id, {})
	if src.is_empty():
		return
	var base := _v.size()
	var verts: PackedVector3Array = src["v"]
	var norms: PackedVector3Array = src["n"]
	var cols: PackedColorArray = src["c"]
	var b := xf.basis
	var foot_uv := Vector2(foot.x, foot.z)
	var foot_uv2 := Vector2(foot.y, 0.0)
	for k in verts.size():
		_v.append(xf * verts[k])
		_n.append((b * norms[k]).normalized())
		var col := cols[k]
		col.a = upright
		_c.append(col)
		_uv.append(foot_uv)
		_uv2.append(foot_uv2)
	var si: PackedInt32Array = src["i"]
	for i in si:
		_idx.append(base + i)


func _build_mesh() -> void:
	if _v.is_empty():
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_TEX_UV] = _uv
	arr[Mesh.ARRAY_TEX_UV2] = _uv2
	arr[Mesh.ARRAY_INDEX] = _idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var mi := MeshInstance3D.new()
	mi.name = "DressMesh"
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	_uv = PackedVector2Array()
	_uv2 = PackedVector2Array()
	_idx = PackedInt32Array()
