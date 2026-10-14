## The Gravity Gun (pass 35): a floating gun that lifts a creature off the ground and throws it into the thickest crowd
## within reach. The throw lands as a small blast: `damage` to everything inside params.gravity.blast (times `area`),
## thrown outwards; the creature thrown takes `self_frac` of it when it hits the ground and may die of that, never
## before: in the grip it is out of the fight (EnemyManager.grab: no hits, no bites, no steering). `amount` creatures are
## taken at once, each thrown at a crowd of its own while there are crowds enough. With nobody else to throw it at, it
## is slammed down where it was taken. Never a boss, an Elite or a special (EnemyManager.grabbable). The spot is picked
## as the throw leaves, where the crowd will be when it lands, at the front of a pack walking in (_lead_target).
## The visual's "Familiar" carries the gun: a "Spin" node (the claw ring, turning slowly, fast while it holds), claws
## "ClawA".."ClawC" under it (they open while it holds) and a "Core" (it glows and swells). A beam joins the Core to
## whatever it holds.
## params.gravity: blast, grab (seconds to lift), hold, throw (seconds in the air), height (of the hold), arc (of the
## throw), self_frac; `bounce` {frac}: the thrown creature bounces once on to the next crowd for a second blast.
## `black_hole` {...} (the Singularity): no grabbing; the gun charges a black hole between its claws and lobs it at
## the thickest crowd, where it lands as a Vortex (the numbers in the block, see Vortex.gd).
## Pass 48, Repulsor (params.gravity {knock_mult, throw_mult, purple}): a landing throws the crowd `knock_mult` times as
## hard over a blast `throw_mult` times as wide (the spot it picks counts the wider blast), and its flash ring, burst and
## dust are purple; on the Singularity it is the black hole's pop that throws harder and wider.
class_name GravityGun
extends WeaponBehavior

const PH_GRAB := 0
const PH_HOLD := 1
const PH_THROW := 2
## Repulsor's blast
const PURPLE := Color(0.62, 0.3, 0.95)

var _familiar: Node3D
var _spin: Node3D
var _core: Node3D
var _core_mat: StandardMaterial3D
var _claws: Array = []
var _orbit := 0.0
var _aim_yaw := 0.0
var _recoil := 0.0
var _open := 0.0
var _charge := 0.0      # the Singularity: seconds left charging the next black hole
var _charge_to := Vector3.INF
var _grips: Array = []  # {i, phase, t, from, rel, target, bounced, flip_t, land_t}
var _beam: MeshInstance3D
var _beam_mesh: ImmediateMesh
# how the throws land, for the tests and tuning: blasts so far and the creatures they caught
var blasts := 0
var blast_hits := 0


func _on_setup() -> void:
	_familiar = visual.get_node_or_null("Familiar")
	if _familiar:
		_familiar.top_level = true
		_spin = _familiar.find_child("Spin", true, false)
		_core = _familiar.find_child("Core", true, false)
		for n in ["ClawA", "ClawB", "ClawC"]:
			var c := _familiar.find_child(n, true, false)
			if c:
				_claws.append(c)
		if _core is MeshInstance3D:
			var mi := _core as MeshInstance3D
			var m: Material = mi.get_active_material(0)
			if m is StandardMaterial3D:
				_core_mat = (m as StandardMaterial3D).duplicate()
				_core_mat.emission_enabled = true
				mi.material_override = _core_mat
		_orbit = randf() * TAU
		_place(0.0)


func _g(key: String, default: float) -> float:
	var s = inst.params.get("gravity", {})
	return float(s.get(key, default)) if s is Dictionary else default


func _gdict(key: String) -> Dictionary:
	var s = inst.params.get("gravity", {})
	if s is Dictionary and s.get(key) is Dictionary:
		return s[key]
	return {}


func _blast_r() -> float:
	return _g("blast", 1.9) * stat("area", 1.0) * maxf(_g("throw_mult", 1.0), 0.1)


## Whether the blast is Repulsor's purple.
func _purple() -> bool:
	var s = inst.params.get("gravity", {})
	return s is Dictionary and bool((s as Dictionary).get("purple", false))


## The landing's colour: Repulsor's purple, the poison's green, else the gun's cyan.
func blast_colour() -> Color:
	if _purple():
		return PURPLE
	if stat("poison_damage", 0.0) > 0.0:
		return Color(0.45, 0.95, 0.35)
	return Color(0.45, 0.85, 1.0)


func _hole() -> Dictionary:
	return _gdict("black_hole")


# ---------------------------------------------------------------- firing

func _fire() -> bool:
	if not _hole().is_empty():
		return _fire_hole()
	if not _grips.is_empty():
		return false
	var em: EnemyManager = game.enemies
	var reach := stat("range", 7.0)
	var n: int = maxi(stat_int("amount", 1), 1)
	# the nearest creatures the gun may take
	var cands: Array = []
	for e in em.indices_in_radius(player.global_position, reach):
		# only what is on the screen (pass 54, Settings.ranged_on_screen)
		if em.grabbable(e) and em.screen_ok(e):
			cands.append(e)
	if cands.is_empty():
		return false
	var pp := player.global_position
	cands.sort_custom(func(a: int, b: int) -> bool: return em.pos[a].distance_squared_to(pp) < em.pos[b].distance_squared_to(pp))
	var taken := {}
	for k in range(mini(n, cands.size())):
		taken[cands[k]] = true
	var spots := crowd_spots(taken.size(), reach + 2.0, _blast_r(), taken)
	var k := 0
	for e: int in taken.keys():
		em.grab(e)
		# with no crowd to throw at it goes back down where it was, hard
		var target: Vector3 = spots[k % spots.size()] if not spots.is_empty() else em.pos[e]
		if spots.size() > 0 and k >= spots.size():
			target += Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.8
		_grips.append({"i": e, "phase": PH_GRAB, "t": 0.0, "from": em.pos[e], "rel": float(k) - float(taken.size() - 1) * 0.5,
				"target": target, "bounced": false, "flip_t": 0.0, "slam": spots.is_empty()})
		k += 1
	sfx("fire", _core_pos())
	return true


## The Singularity: the claws open, the core swells, and a moment later the black hole goes.
func _fire_hole() -> bool:
	var em: EnemyManager = game.enemies
	var reach := stat("range", 9.0)
	# a crowd no bomb is headed for or has just come down on (pass 36), else the thickest one
	var r := float(_hole().get("radius", 3.2)) * stat("area", 1.0)
	# pass 73 (lane SNIPER): a special, an Elite or the boss within reach takes the black hole
	var pt: int = priority_pick(player.global_position, reach)
	var target: Vector3 = em.pos[pt] if pt >= 0 else em.densest_point(player.global_position, reach, "", game.projectiles.claimed_spots(), r)
	if target == Vector3.INF:
		target = em.densest_point(player.global_position, reach)
	if target == Vector3.INF:
		return false
	_charge = float(_hole().get("charge", 0.35))
	_charge_to = target
	sfx("fire", _core_pos())
	return true


func _throw_hole() -> void:
	var hb := _hole()
	var amount: int = maxi(stat_int("amount", 1), 1)
	var from := _core_pos()
	for k in range(amount):
		var to := _charge_to
		if k > 0:
			# the next ones land round the first, a hole's width apart
			var a := TAU * float(k) / float(amount) + randf() * 0.5
			to += Vector3(cos(a), 0.0, sin(a)) * _g("blast", 1.9) * stat("area", 1.0) * 1.2
		var lp: Dictionary = {"vortex": hb.duplicate(true)}
		# Repulsor on the Singularity: the pop throws harder and wider
		lp["vortex"]["knock_mult"] = _g("knock_mult", 1.0)
		lp["vortex"]["throw_mult"] = _g("throw_mult", 1.0)
		game.projectiles.lob(projectile_kind, from, to, stat("speed", 10.0), stat("damage", 12.0), stat("area", 1.0) * float(hb.get("radius", 3.2)), inst, 0.0, lp)
	_recoil = 1.0
	sfx("hit", from)


# ---------------------------------------------------------------- the grip

func _core_pos() -> Vector3:
	if _core:
		return _core.global_position
	if _familiar:
		return _familiar.global_position
	return player.global_position + Vector3(0, 1.4, 0)


func _aim_dir() -> Vector3:
	return Vector3(-sin(_aim_yaw), 0.0, -cos(_aim_yaw))


## Where a held creature floats: out in front of the gun, side by side when there are several.
func _hold_point(g: Dictionary) -> Vector3:
	var ad := _aim_dir()
	var side := Vector3(-ad.z, 0.0, ad.x)
	return _core_pos() + ad * 1.5 + side * float(g["rel"]) * 1.1 + Vector3(0, _g("height", 1.8) - 1.4, 0)


func _ground(p: Vector3) -> float:
	return game.map.height_at(p.x, p.z) if game.map else 0.0


func _put(i: int, at: Vector3, wriggle: float = -1.0, turn: bool = false) -> void:
	game.enemies.place_held(i, at, wriggle, turn)


func _tick(delta: float) -> void:
	var em: EnemyManager = game.enemies
	var grab_s := maxf(_g("grab", 0.32), 0.05)
	var hold_s := _g("hold", 0.28)
	var throw_s := maxf(_g("throw", 0.5), 0.1)
	var holding := false
	for k in range(_grips.size() - 1, -1, -1):
		var g: Dictionary = _grips[k]
		var i: int = g["i"]
		if em.alive[i] == 0 or em.held[i] == 0 or em.state[i] == em.STATE_DYING:
			# taken from the gun (the stage ended, the arena cleared the field)
			_grips.remove_at(k)
			continue
		g["t"] = float(g["t"]) + delta
		var t: float = g["t"]
		g["flip_t"] = float(g["flip_t"]) + delta
		match int(g["phase"]):
			PH_GRAB:
				holding = true
				var u := clampf(t / grab_s, 0.0, 1.0)
				var e := 1.0 - pow(1.0 - u, 3.0)
				var from: Vector3 = g["from"]
				_put(i, from.lerp(_hold_point(g), e), 1.0 + 0.15 * sin(t * 30.0))
				if u >= 1.0:
					g["phase"] = PH_HOLD
					g["t"] = 0.0
					_retarget(g)
			PH_HOLD:
				holding = true
				var wob := Vector3(sin(t * 17.0), sin(t * 23.0) * 0.6, cos(t * 19.0)) * 0.06
				var turn := float(g["flip_t"]) > 0.12
				if turn:
					g["flip_t"] = 0.0
				_put(i, _hold_point(g) + wob, -1.0, turn)
				if t >= hold_s:
					g["phase"] = PH_THROW
					g["t"] = 0.0
					g["p0"] = _hold_point(g)
					_retarget(g)
					var tgt: Vector3 = g["target"]
					var p0v: Vector3 = g["p0"]
					var dist := Vector2(tgt.x - p0v.x, tgt.z - p0v.z).length()
					g["dur"] = throw_s * clampf(dist / 6.0, 0.6, 1.3)
					_recoil = 1.0
					sfx("hit", g["p0"])
			PH_THROW:
				var p0: Vector3 = g["p0"]
				var tgt: Vector3 = g["target"]
				var dur: float = g["dur"]
				var u := clampf(t / dur, 0.0, 1.0)
				var gy := _ground(tgt)
				var arc := _g("arc", 2.2) * (0.5 if bool(g["slam"]) else 1.0)
				var h := lerpf(p0.y, gy + 0.05, u) + arc * 4.0 * u * (1.0 - u)
				var flat := p0.lerp(tgt, u)
				var turn2 := float(g["flip_t"]) > 0.07
				if turn2:
					g["flip_t"] = 0.0
				_put(i, Vector3(flat.x, h, flat.z), -1.0, turn2)
				if u >= 1.0:
					if _land(g):
						_grips.remove_at(k)
	_open = move_toward(_open, 1.0 if (holding or _charge > 0.0) else 0.0, delta * (7.0 if holding else 4.0))
	if _charge > 0.0:
		_charge -= delta
		if _charge <= 0.0:
			_throw_hole()
	_aim(delta)
	_place(delta)
	_animate(delta)
	_draw_beam()


## A grip's landing spot, picked again from where the crowd is now (a slam stays a slam; nobody to throw at, it stays).
func _retarget(g: Dictionary) -> void:
	if bool(g["slam"]):
		return
	var avoid: Array = []
	for o: Dictionary in _grips:
		if o != g and int(o["phase"]) == PH_THROW:
			avoid.append(o["target"])
	var lt := _lead_target(_hold_point(g), player.global_position, stat("range", 7.0) + 2.0, {}, avoid)
	if lt != Vector3.INF:
		g["target"] = lt


## Where a throw from `p0` should come down: where the crowd will be when it lands (pass 35b: the spot picked when the
## creature was grabbed was a second behind a walking pack by the time the throw landed, and caught its stragglers).
## Every creature within `reach` of `around`, and a little past it (a pack walking in), is moved on by its own velocity
## for the flight, stopping a metre short of the hero; the spot catching the most of them in the blast wins, and of the
## spots catching as many the one nearest the hero: the front of the pack coming at him. `skip` holds creatures to leave
## out, `avoid` spots other throws are already headed for. Vector3.INF when there is nobody.
func _lead_target(p0: Vector3, around: Vector3, reach: float, skip: Dictionary, avoid: Array) -> Vector3:
	var em: EnemyManager = game.enemies
	var r := _blast_r()
	var hero := player.global_position
	var throw_s := maxf(_g("throw", 0.5), 0.1)
	var pred: Array = []
	for e in em.indices_in_radius(around, reach + 3.0):
		if skip.has(e) or em.state[e] == EnemyManager.STATE_DYING:
			continue
		var p: Vector3 = em.pos[e]
		var fly := throw_s * clampf(Vector2(p.x - p0.x, p.z - p0.z).length() / 6.0, 0.6, 1.3)
		var v: Vector3 = em.vel[e]
		v.y = 0.0
		var step := v * fly
		var to_hero := Vector3(hero.x - p.x, 0.0, hero.z - p.z)
		var room := maxf(to_hero.length() - 1.0, 0.0)
		if step.dot(to_hero) > 0.0 and step.length() > room:
			step = step.normalized() * room
		pred.append(p + step)
	if pred.is_empty():
		return Vector3.INF
	var r2 := r * r * 0.81
	var stride: int = maxi(1, pred.size() / 48)
	var spots: Array = []   # [count, distance to the hero, point]
	var best := 0
	for pass_k in range(2):
		for k in range(0, pred.size(), stride):
			var c: Vector3 = pred[k]
			var blocked := false
			if pass_k == 0:
				for a: Vector3 in avoid:
					if Vector2(c.x - a.x, c.z - a.z).length() < r:
						blocked = true
						break
			if blocked:
				continue
			var n := 0
			for q: Vector3 in pred:
				var dx := q.x - c.x
				var dz := q.z - c.z
				if dx * dx + dz * dz <= r2:
					n += 1
			best = maxi(best, n)
			spots.append([n, Vector2(c.x - hero.x, c.z - hero.z).length(), c])
		if not spots.is_empty():
			break
	var pick: Vector3 = Vector3.INF
	var near := INF
	# the most caught wins outright: leaning further forward caught fewer (a pack of twelve walking in: 9.8 a throw at
	# the most, 9.1 one creature short of it, 8.8 at 85%, 5.4 before the lead)
	var need := best
	for s: Array in spots:
		if int(s[0]) >= need and float(s[1]) < near:
			near = float(s[1])
			pick = s[2]
	if pick == Vector3.INF:
		return pick
	return Vector3(pick.x, _ground(pick), pick.z)


## The throw comes down: the blast, then the creature's own fall. Returns false while a Slingshot bounce carries on.
func _land(g: Dictionary) -> bool:
	var em: EnemyManager = game.enemies
	var i: int = g["i"]
	var at: Vector3 = g["target"]
	at.y = _ground(at)
	var r := _blast_r()
	var dmg := stat("damage", 18.0)
	var frac := 1.0
	if bool(g["bounced"]):
		frac = float(_gdict("bounce").get("frac", 0.6))
	_blast(at, r, dmg * frac)
	var bn := _gdict("bounce")
	if not bn.is_empty() and not bool(g["bounced"]) and not bool(g["slam"]):
		# Slingshot: it skips on to the next crowd for a second, smaller blast
		var skip := {i: true}
		for e in em.indices_in_radius(at, r):
			skip[e] = true
		var next := _lead_target(Vector3(at.x, at.y + 0.3, at.z), at, float(bn.get("reach", 6.0)), skip, [])
		if next != Vector3.INF:
			g["bounced"] = true
			g["phase"] = PH_THROW
			g["t"] = 0.0
			g["p0"] = Vector3(at.x, at.y + 0.3, at.z)
			g["target"] = next
			g["dur"] = _g("throw", 0.5) * 0.7
			return false
	em.release(i)
	# the fall: it takes its share of the blast, and this is where it may die
	if em.damage(i, dmg * _g("self_frac", 1.5), inst.def.id, Vector3.ZERO, 0.0):
		inst.kills += 1
	return true


func _blast(at: Vector3, r: float, dmg: float) -> void:
	var em: EnemyManager = game.enemies
	var wid := inst.def.id
	var knock := stat("knockback", 9.0) * _g("knock_mult", 1.0)
	var pdmg := stat("poison_damage", 0.0)
	var fdmg := stat("fire_damage", 0.0)
	var caught := em.indices_in_radius(at, r)
	blasts += 1
	blast_hits += caught.size()
	for e in caught:
		var away: Vector3 = em.pos[e] - at
		away.y = 0.0
		if pdmg > 0.0:
			em.poison(e, wid, pdmg, maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
		if fdmg > 0.0:
			em.ignite(e, wid, fdmg, stat("fire_duration", 1.8), stat("fire_spread", 0.4))
		if em.damage(e, dmg, wid, away, knock):
			inst.kills += 1
	var col := blast_colour()
	if _purple():
		_purple_dust(at, r)
	else:
		game.fx.sand(at, 1.0)
	game.fx.burst(at + Vector3(0, 0.4, 0), col, r * 0.7)
	game.telegraphs.flash_ring(at, r, col, 0.3)
	game.camera.shake(0.3)
	Audio.play(str(inst.def.sfx.get("land", "w_lob_boom")), at)


## Repulsor's dust: a purple ring of it thrown out low along the ground, as far as the blast reaches.
func _purple_dust(at: Vector3, r: float) -> void:
	var fx = game.get("fx")
	if fx == null or not fx.has_method("mote"):
		return
	for k in range(12):
		var a := TAU * float(k) / 12.0 + randf() * 0.3
		var out := Vector3(cos(a), 0.0, sin(a))
		fx.mote(at + out * 0.3 + Vector3(0, 0.25, 0), out * r * 2.4 + Vector3(0, 0.5, 0), 0.45, 0.55, Color(PURPLE.r, PURPLE.g, PURPLE.b, 0.8))


# ---------------------------------------------------------------- the gun

func _aim(delta: float) -> void:
	var em: EnemyManager = game.enemies
	var want := Vector3.ZERO
	var from := _familiar.global_position if _familiar else player.global_position
	for g: Dictionary in _grips:
		# lifting: at the creature; holding and throwing: at where it is going
		var to: Vector3 = em.pos[int(g["i"])] if int(g["phase"]) == PH_GRAB else Vector3(g["target"])
		want = to - from
		break
	if want == Vector3.ZERO and _charge > 0.0 and _charge_to != Vector3.INF:
		want = _charge_to - from
	if want == Vector3.ZERO:
		var t := em.nearest_index(player.global_position, stat("range", 7.0))
		want = (em.pos[t] - from) if t >= 0 else player.forward()
	want.y = 0.0
	if want.length_squared() > 0.0001:
		_aim_yaw = lerp_angle(_aim_yaw, atan2(-want.x, -want.z), clampf(delta * 10.0, 0.0, 1.0))


func _place(delta: float) -> void:
	if _familiar == null:
		return
	var f = inst.params.get("familiar", {})
	var fam: Dictionary = f if f is Dictionary else {}
	var r := float(fam.get("radius", 1.3))
	var h := float(fam.get("height", 1.45))
	# it hangs still while it strains to hold something
	_orbit += delta * float(fam.get("speed", 1.0)) * (0.25 if _open > 0.5 else 1.0)
	var t := Run.rule_seconds()  # pass 77 (lane SIMRUN): real time in play, the run's clock in a run sim
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 2.7) * float(fam.get("bob", 0.08)), sin(_orbit) * r)
	want -= _aim_dir() * 0.18 * _recoil
	if _open > 0.3:
		want += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.025 * _open
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	_familiar.rotation = Vector3(-0.3 * _recoil + 0.12 * _open, _aim_yaw, sin(t * 2.1) * 0.06)
	_recoil = maxf(_recoil - delta * 5.0, 0.0)


func _animate(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	if _spin:
		_spin.rotate_object_local(Vector3.FORWARD, delta * lerpf(1.2, 11.0, _open))
	for c: Node3D in _claws:
		c.rotation.x = lerpf(0.0, 0.8, _open) + 0.04 * sin(t * 3.0)
	if _core:
		var pulse := 1.0 + 0.07 * sin(t * 7.0)
		_core.scale = Vector3.ONE * (pulse + 0.45 * _open)
	if _core_mat:
		_core_mat.emission_energy_multiplier = 1.2 + 3.5 * _open + 0.4 * sin(t * 9.0)


## The beam: a wavering ribbon from the Core to each creature it lifts or holds, facing the camera.
func _draw_beam() -> void:
	var em: EnemyManager = game.enemies
	var ends: Array = []
	for g: Dictionary in _grips:
		if int(g["phase"]) == PH_THROW:
			continue
		var i: int = g["i"]
		ends.append(em.pos[i] + Vector3(0, em.lift_h[i] + em.size[i] * 0.45, 0))
	if ends.is_empty():
		if _beam:
			_beam.visible = false
		return
	if _beam == null:
		_beam_mesh = ImmediateMesh.new()
		_beam = MeshInstance3D.new()
		_beam.mesh = _beam_mesh
		_beam.top_level = true
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beam.material_override = Fx.tint_ribbon_material()
		add_child(_beam)
		_beam.global_transform = Transform3D.IDENTITY
	_beam.visible = true
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else player.global_position + Vector3(0, 20, 10)
	var from := _core_pos()
	var t := float(Time.get_ticks_msec()) * 0.001
	var col := Color(0.2, 0.8, 1.0)
	_beam_mesh.clear_surfaces()
	_beam_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for to: Vector3 in ends:
		var seg := 14
		var dir := to - from
		var side0 := dir.cross(eye - from).normalized()
		var prev_a := Vector3.ZERO
		var prev_b := Vector3.ZERO
		for s in range(seg + 1):
			var u := float(s) / float(seg)
			var p := from.lerp(to, u) + side0 * sin(u * PI) * 0.12 * sin(t * 22.0 + u * 9.0)
			var w := 0.09 + 0.06 * sin(u * PI)
			var a := p + side0 * w
			var b := p - side0 * w
			if s > 0:
				# the edges soft cyan, the middle near white
				var mid_p := (prev_a + prev_b) * 0.5
				var mid := (a + b) * 0.5
				var edge := Color(col.r, col.g, col.b, 0.35)
				var core := Color(0.85, 1.0, 1.0, 0.95)
				for side: Array in [[prev_a, a], [prev_b, b]]:
					_beam_mesh.surface_set_color(core)
					_beam_mesh.surface_add_vertex(mid_p)
					_beam_mesh.surface_add_vertex(mid)
					_beam_mesh.surface_set_color(edge)
					_beam_mesh.surface_add_vertex(side[1])
					_beam_mesh.surface_set_color(core)
					_beam_mesh.surface_add_vertex(mid_p)
					_beam_mesh.surface_set_color(edge)
					_beam_mesh.surface_add_vertex(side[1])
					_beam_mesh.surface_add_vertex(side[0])
			prev_a = a
			prev_b = b
	_beam_mesh.surface_end()


## Whatever it still holds goes back to the crowd when the gun goes (a swap, the end of the run).
func _exit_tree() -> void:
	var em = game.get("enemies") if game and is_instance_valid(game) else null
	if em == null or not is_instance_valid(em):
		return
	for g: Dictionary in _grips:
		em.release(int(g["i"]))
	_grips.clear()
