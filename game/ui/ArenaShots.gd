## The debug arena's screenshot crowds (pass 110, lane ARENA; Garry: "Ability to Spawn more than 1500 enemies in Arena (at
## once) + Ability to Spawn a variety of enemies at once (in chunks of types of enemies, and in scatter as well as an
## option)", and the ring of his reference picture screenshots/scorpions.png: scorpions over the whole screen but a clear
## circle round the hero). Where the spots go, apart from the panel so a tool (game/tools/store_shots.gd) and the tests
## lay crowds out the same way. ArenaPanel.mass_spawn spawns on them.
##
## Three layouts, every spot on the sand the camera sees (`footprint`: the screen's corners, grown by a margin, laid on
## the ground at the hero's height), out of the arena's wall, off the rocks' paintings and out of the lakes (`ok`):
##   ring     an even cover (a jittered hex grid) from the clear circle's edge out to the screen's edges, or a band
##            `depth` metres deep round it; the kinds mixed.
##   scatter  spread at random over the same ground (natural clumps and gaps), the kinds mixed.
##   chunks   each kind its own clustered group: a disc holding its share at `density` creatures a square metre, the
##            discs round the hero from screen-up, just past the clear circle, squeezed to the portrait screen's width
##            and pushed up and down until no two touch.
extends RefCounted

## The share of the screen's width the footprint is grown by on every side, so the crowd runs past the edges.
const MARGIN := 0.12
## Metres a ray that misses the ground (above the horizon) is cut at.
const FAR := 45.0
## The jitter of an even cover, a share of its spacing (0 = a perfect lattice).
const JITTER := 0.32


## The ground the camera sees, as an XZ polygon (four points, clockwise from the top left): the viewport's corners grown
## by MARGIN of its width, each ray laid on the plane at `ground_y`. A square 30 m across round `center` without a camera.
static func footprint(cam: Camera3D, center: Vector3, margin: float = MARGIN) -> PackedVector2Array:
	var out := PackedVector2Array()
	if cam == null or not cam.is_inside_tree():
		for c: Vector2 in [Vector2(-15, -20), Vector2(15, -20), Vector2(15, 12), Vector2(-15, 12)]:
			out.append(Vector2(center.x, center.z) + c)
		return out
	var vs := cam.get_viewport().get_visible_rect().size
	var m := vs.x * margin
	for sp: Vector2 in [Vector2(-m, -m), Vector2(vs.x + m, -m), Vector2(vs.x + m, vs.y + m), Vector2(-m, vs.y + m)]:
		var o := cam.project_ray_origin(sp)
		var d := cam.project_ray_normal(sp)
		var t := FAR
		if d.y < -0.01:
			t = minf((center.y - o.y) / d.y, FAR * 2.0)
		var hit := o + d * t
		# a ray past the horizon: as far out as FAR along its ground direction
		if d.y >= -0.01:
			var g := Vector2(d.x, d.z).normalized() * FAR
			hit = Vector3(center.x + g.x, center.y, center.z + g.y)
		out.append(Vector2(hit.x, hit.z))
	return out


## Whether `p` lies inside the convex polygon `poly` (either winding).
static func in_poly(poly: PackedVector2Array, p: Vector2) -> bool:
	var n := poly.size()
	if n < 3:
		return true
	var side := 0.0
	for k in range(n):
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var c := (b - a).cross(p - a)
		if absf(c) < 1e-6:
			continue
		if side == 0.0:
			side = signf(c)
		elif signf(c) != side:
			return false
	return true


## Half the footprint's width across `c`'s row (the nearer side), 0 when the row misses it.
static func half_width(poly: PackedVector2Array, c: Vector2) -> float:
	var left := -INF
	var right := INF
	var n := poly.size()
	var hit := false
	for k in range(n):
		var a := poly[k]
		var b := poly[(k + 1) % n]
		if (a.y - c.y) * (b.y - c.y) > 0.0 or absf(b.y - a.y) < 1e-6:
			continue
		var x := a.x + (b.x - a.x) * (c.y - a.y) / (b.y - a.y)
		hit = true
		if x <= c.x:
			left = maxf(left, x)
		else:
			right = minf(right, x)
	if not hit or left == -INF or right == INF:
		return 0.0
	return minf(c.x - left, right - c.x)


static func _bbox(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


## [kind, Vector2 spot] pairs: `n` spots for `kinds` kinds in `layout` ("ring", "scatter" or "chunks") round `c` (XZ), on
## the footprint `poly`, never within `clear_r` m of `c`; `depth` > 0 keeps a ring that deep (0 = to the screen's edges);
## `density` creatures a square metre in a chunk; `ok` (Callable(Vector2) -> bool) says a spot is on open sand; `weights`
## (one a kind) splits the count by them instead of evenly. Fewer than `n` come back only when there is no room for them.
static func layout(n: int, kinds: int, mode: String, c: Vector2, poly: PackedVector2Array, clear_r: float, depth: float,
		density: float, ok: Callable, rng: RandomNumberGenerator, weights: Array = []) -> Array:
	var out: Array = []
	kinds = maxi(kinds, 1)
	if n <= 0:
		return out
	var cr2 := clear_r * clear_r
	var outer := clear_r + depth if depth > 0.0 else INF
	var outer2 := outer * outer
	if mode == "chunks":
		var shares := split(n, kinds, weights)
		var dens := maxf(density, 0.05)
		var rg: Array = []
		var rmax := 0.0
		for k in range(kinds):
			var r := sqrt(float(shares[k]) / (PI * dens)) + 0.4
			rg.append(r)
			rmax = maxf(rmax, r)
		# the groups' centres round the hero from screen-up (north, -z), just past the clear circle: on a circle, squeezed
		# across to the portrait screen's width at the hero (half_width) and stretched up and down until no two
		# neighbours touch
		var ring_r := clear_r + rmax
		var rx := ring_r
		var hw := half_width(poly, c)
		if hw > 0.0:
			rx = clampf(hw - rmax * 0.35, minf(clear_r + rmax * 0.5, ring_r), ring_r)
		var rz := ring_r
		var centres: Array = []
		for attempt in range(60):
			centres.clear()
			for k in range(kinds):
				var a := -PI * 0.5 + TAU * float(k) / float(kinds)
				centres.append(c + Vector2(cos(a) * rx, sin(a) * rz))
			var apart := true
			if kinds >= 2:
				for k in range(kinds):
					var k2 := (k + 1) % kinds
					if k2 == k:
						continue
					if (centres[k] as Vector2).distance_to(centres[k2]) < (float(rg[k]) + float(rg[k2])) * 1.05:
						apart = false
						break
			if apart:
				break
			rz *= 1.06
			rx = minf(rx * 1.02, maxf(ring_r, rx))
		for k in range(kinds):
			var gc: Vector2 = centres[k]
			var r: float = rg[k]
			var r2 := r * r
			var test := func(p: Vector2) -> bool:
				return p.distance_squared_to(gc) <= r2 and p.distance_squared_to(c) >= cr2 and ok.call(p)
			for p: Vector2 in even_fill(int(shares[k]), test, Rect2(gc - Vector2(r, r), Vector2(r, r) * 2.0), rng):
				out.append([k, p])
		return out
	var box := _bbox(poly)
	if depth > 0.0:
		box = box.intersection(Rect2(c - Vector2(outer, outer), Vector2(outer, outer) * 2.0))
	var test2 := func(p: Vector2) -> bool:
		var d2 := p.distance_squared_to(c)
		return d2 >= cr2 and d2 <= outer2 and in_poly(poly, p) and ok.call(p)
	var spots: Array = even_fill(n, test2, box, rng) if mode == "ring" else random_fill(n, test2, box, rng)
	# the kinds mixed, each its even share
	var order: Array = []
	var shares2 := split(spots.size(), kinds, weights)
	for k in range(kinds):
		for j in range(int(shares2[k])):
			order.append(k)
	_shuffle(order, rng)
	for j in range(spots.size()):
		out.append([int(order[j]), spots[j]])
	return out


## `n` split into `k` shares: by `weights` (one a share) when given, else as even as they come (the first ones one more);
## the shares always add up to `n`.
static func split(n: int, k: int, weights: Array = []) -> PackedInt32Array:
	var out := PackedInt32Array()
	var total := 0.0
	if weights.size() == k:
		for w in weights:
			total += maxf(float(w), 0.0)
	if total <= 0.0:
		for j in range(k):
			out.append(n / k + (1 if j < n % k else 0))
		return out
	var given := 0
	for j in range(k):
		var sj := int(floor(float(n) * maxf(float(weights[j]), 0.0) / total))
		out.append(sj)
		given += sj
	# what flooring left over goes to the biggest weights first
	var order: Array = range(k)
	order.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
	var j2 := 0
	while given < n and k > 0:
		out[int(order[j2 % k])] += 1
		given += 1
		j2 += 1
	return out


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for j in range(a.size() - 1, 0, -1):
		var k := rng.randi_range(0, j)
		var t = a[j]
		a[j] = a[k]
		a[k] = t


## `n` spots spread evenly over where `test` holds inside `box`: a hex lattice with a little jitter whose spacing fits
## the open area (measured by sampling), tightened until it holds `n`, the extra ones dropped at random.
static func even_fill(n: int, test: Callable, box: Rect2, rng: RandomNumberGenerator) -> Array:
	if n <= 0 or box.get_area() <= 0.0:
		return []
	var hits := 0
	var tries := 1500
	for j in range(tries):
		if test.call(box.position + Vector2(rng.randf() * box.size.x, rng.randf() * box.size.y)):
			hits += 1
	var area := box.get_area() * float(maxi(hits, 1)) / float(tries)
	var s := sqrt(2.0 * area / (sqrt(3.0) * float(n)))
	var best: Array = []
	for attempt in range(10):
		var pts: Array = []
		var row := 0
		var dy := s * 0.8660254
		var y := box.position.y + dy * 0.5
		while y < box.end.y:
			var x := box.position.x + (s * 0.5 if row % 2 == 1 else 0.0) + s * 0.25
			while x < box.end.x:
				var p := Vector2(x + rng.randf_range(-JITTER, JITTER) * s, y + rng.randf_range(-JITTER, JITTER) * dy)
				if test.call(p):
					pts.append(p)
				x += s
			y += dy
			row += 1
		if pts.size() > best.size():
			best = pts
		if pts.size() >= n:
			_shuffle(pts, rng)
			pts.resize(n)
			return pts
		s *= sqrt(float(maxi(pts.size(), 1)) / float(n)) * 0.97 if not pts.is_empty() else 0.7
		if s < 0.05:
			break
	return best


## `n` spots at random where `test` holds inside `box` (natural clumps and gaps), as many as it finds in 40 tries a spot.
static func random_fill(n: int, test: Callable, box: Rect2, rng: RandomNumberGenerator) -> Array:
	var pts: Array = []
	var tries := 0
	while pts.size() < n and tries < n * 40:
		tries += 1
		var p := box.position + Vector2(rng.randf() * box.size.x, rng.randf() * box.size.y)
		if test.call(p):
			pts.append(p)
	return pts
