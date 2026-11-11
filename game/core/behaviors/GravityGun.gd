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
## Pass 141 (lane GRAV; Garry, "Polish #4" item 6: the gun "seems to perform a very sad looking brief shot on the ground
## when there are no targets ... make it do a kind of a 'search', it shoots its beam occasionally at the ground, so like a
## 1 second. But it's a continuous beam 'feeling out' the ground (searching)", and "Throw barrels towards me ... grab,
## pause, throw. But it throws at the hero and when it lands it automatically breaks ... this only works around 75% of
## the distance that is required for the initial enemy reach. And this range never increases with Upgrades"; BALANCING
## 82.GRAV):
##   the search (params.gravity.search, SEARCH): pass 136's dry shot at the sand is gone. A pull that finds nothing to take
##   spends nothing (the gun asks again every 0.15 s, as before pass 136); now and then (`every` s after its last search or
##   grab) it feels out the sand instead: for `seconds` a thin beam from the Core sweeps an arc `sweep_deg` wide across his
##   facing, `reach` m ahead of him and wandering `wander` m in and out, a soft glow `glow` m wide where it touches and a
##   few specks left on the sand. Looks only: it grabs and hurts nothing; whatever comes into the gun's reach is taken by
##   its own pull, which ends the search at once (the beam swings from the sand onto it). The Singularity never searches.
##   the barrels (params.gravity.barrel, BARREL): a standing barrel within `reach_frac` x the family's level-1 `range` (the
##   Gravity Gun's JSON base: 0.75 x 7 = 5.25 m; no level, mutation, item, evolution or Trail node changes it) is taken
##   first, in place of one creature of the pull (the nearest such barrel, one at a time). It rises `lift` m off the sand,
##   drawn `pull` of the way towards the gun, in the gun's own grab, hold and throw times and arc, then flies to land
##   `ahead` m in front of the Outlaw (where his walk puts him by then, x `lead`), turning `spin` times, and breaks there
##   as a round's last hit breaks one (BarrelField.land_carried: debris, gems, coins, a power-up). It never hurts him.
##   While it is carried, walking into it, rounds and knocks pass it by (BarrelField.carried). The Singularity takes it
##   the same way, in place of that pull's black hole. No text tells of it (Garry).
## Pass 142 (Garry: "Currently the Barrels are higher prio than an enemy. That should not be the case ever, if there is an
## enemy that is within range +10% the Gravity Gun will not try to pick up barrels"; BALANCING 83.GRAV): a creature always
## comes first. While any creature stands within `guard` (1.1) x the gun's range of him (its range now, with its levels,
## mutations and items; the Singularity's own; on the screen or off: any a weapon may choose, _creature_near), the gun
## takes no barrel. One in the grip when a creature comes that near is let go: still rising or held, it falls back to the
## sand standing, unbroken (PH_DROP, DROP_S); already thrown, it flies on and breaks as before. Either way the pull it took
## is given back (cooldown_left 0), so the gun turns to the creature at once.
class_name GravityGun
extends WeaponBehavior

const PH_GRAB := 0
const PH_HOLD := 1
const PH_THROW := 2
## pass 142: a barrel let go for a creature, falling back to the sand in DROP_S seconds
const PH_DROP := 3
const DROP_S := 0.2
## Repulsor's blast
const PURPLE := Color(0.62, 0.3, 0.95)
## Pass 141 (lane GRAV): the search's and the barrel throw's numbers where the JSON names none (see the header).
const SEARCH := {"every": 3.0, "seconds": 1.0, "sweep_deg": 50.0, "reach": 3.4, "wander": 0.5, "glow": 1.2}
const BARREL := {"reach_frac": 0.75, "lift": 1.3, "pull": 0.3, "ahead": 1.3, "lead": 1.0, "spin": 1.25, "guard": 1.1}
## the search beam reaches the sand in this long and draws back in the last SEARCH_OUT seconds
const SEARCH_IN := 0.12
const SEARCH_OUT := 0.16
const SEARCH_COLOR := Color(0.55, 0.95, 1.0)

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
## pass 141 (lane GRAV): the barrel in the grip ({} for none: {i, phase, t, from, hold, p0, target, dur, roll, roll0}) and
## the barrels thrown and broken at his feet so far (tests, the capture)
var _bgrip: Dictionary = {}
var barrel_throws := 0
## the search: seconds before the next may start, the one running ({} for none: {t, yaw, dir, end}), searches so far,
## how far the gun leans into it (0..1: claws, spin, glow, its nose down), its glow on the sand and the specks' clock
var _search_wait := 0.0
var _search: Dictionary = {}
var searches := 0
var _scan := 0.0
var _glow: MeshInstance3D
var _speck_t := 0.0
static var _glow_tex: GradientTexture2D


func _on_setup() -> void:
	_search_wait = float(_block("search", SEARCH)["every"]) * 0.5
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
		_orbit = Dice.r.randf() * TAU
		_place(0.0)


func _g(key: String, default: float) -> float:
	var s = inst.params.get("gravity", {})
	return float(s.get(key, default)) if s is Dictionary else default


func _gdict(key: String) -> Dictionary:
	var s = inst.params.get("gravity", {})
	if s is Dictionary and s.get(key) is Dictionary:
		return s[key]
	return {}


## Pass 141 (lane GRAV): params.gravity's `key` block over `defaults`: the weapon's own, else (the Singularity names none)
## its family's, the Gravity Gun's.
func _block(key: String, defaults: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	var own := _gdict(key)
	if own.is_empty() and inst != null and inst.def != null and inst.def.is_evolution:
		var fam: WeaponDef = Registry.weapon(inst.family_id())
		var g = fam.params.get("gravity", {}) if fam != null else {}
		if g is Dictionary and (g as Dictionary).get(key) is Dictionary:
			own = g[key]
	for k in own.keys():
		out[k] = own[k]
	return out


## Pass 141 (lane GRAV): how near a barrel must stand to be taken: `reach_frac` x the family's level-1 range as its JSON's
## base says, so no level, mutation, item, evolution or Trail node moves it (5.25 m today).
func barrel_reach() -> float:
	var d: WeaponDef = Registry.weapon(inst.family_id()) if inst != null else null
	if d == null and inst != null:
		d = inst.def
	var base_r := float(d.base.get("range", 7.0)) if d != null else 7.0
	return base_r * float(_block("barrel", BARREL)["reach_frac"])


## Pass 142: whether a creature stands within `guard` x the gun's range of him (its range now: levels, mutations and items
## count; the Singularity's own), on the screen or off: any a weapon may choose (alive, up out of the sand, not dying,
## hidden or in a grip: the crowd's grid and EnemyManager.nearest_index). While one does, the gun leaves the barrels be.
func _creature_near() -> bool:
	var em = game.get("enemies") if game != null and is_instance_valid(game) else null
	if not (em is EnemyManager) or player == null:
		return false
	var r := stat("range", 7.0) * float(_block("barrel", BARREL)["guard"])
	return (em as EnemyManager).nearest_index(player.global_position, r, "", true) >= 0


## Pass 142: whether the barrel in the grip still keeps the gun from pulling (not once it was let go for a creature).
func _barrel_busy() -> bool:
	return not _bgrip.is_empty() and not bool(_bgrip.get("free", false))


## The map's barrels (null in a game without them).
func _barrels() -> BarrelField:
	var b = game.get("barrels") if game != null and is_instance_valid(game) else null
	return b if b is BarrelField else null


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
	if not _grips.is_empty() or _barrel_busy():
		return false
	var em: EnemyManager = game.enemies
	var reach := stat("range", 7.0)
	var n: int = maxi(stat_int("amount", 1), 1)
	# pass 141 (lane GRAV): a barrel he came up to is taken, in place of one creature of the pull; pass 142: only while no
	# creature stands within `guard` x the gun's range (a creature always comes first)
	var barrel := false
	if not _creature_near():
		barrel = _take_barrel()
	if barrel:
		n -= 1
	var took := false
	if n > 0:
		took = _fire_aimed(em, reach, n) if Aim.covers(inst) else _fire_plain(em, reach, n)
	if not took and not barrel:
		# nothing to take: the pull is not spent (asked again in 0.15 s), and now and then the gun searches the sand
		_maybe_search()
		return false
	_found()
	if not took:
		sfx("fire", _core_pos())
	return true


## The pull without "Aim where you face": the nearest creatures the gun may take, each thrown at a crowd of its own.
## False when there is none.
func _fire_plain(em: EnemyManager, reach: float, n: int) -> bool:
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
			target += Vector3(Dice.r.randf_range(-1.0, 1.0), 0.0, Dice.r.randf_range(-1.0, 1.0)) * 0.8
		_grips.append({"i": e, "phase": PH_GRAB, "t": 0.0, "from": em.pos[e], "rel": float(k) - float(taken.size() - 1) * 0.5,
				"target": target, "bounced": false, "flip_t": 0.0, "slam": spots.is_empty()})
		k += 1
	sfx("fire", _core_pos())
	return true


## Pass 136 (lane GUNS; Garry: the Gravity Gun "is a weapon that fires at the ground, and nothing happens to it"): under
## "Aim where you face" (Aim.covers) it grabs the best grabbable creatures in its cone (`params.aim.cone`, 60), ranked by
## R4's score (Aim.cone_score), and throws each at a spot in the circle round him (Aim.circle_spots, R6; picked again as
## the throw leaves, _retarget). Pass 141 (lane GRAV): with nothing to grab in the cone it returns false and spends
## nothing (pass 136's dry shot at the sand is the search now, see the header).
func _fire_aimed(em: EnemyManager, reach: float, n: int) -> bool:
	var pp := player.global_position
	var f := Aim.facing(player)
	var cone := float(Aim.cfg(inst).get("cone", Aim.DEFAULT_CONE))
	var ranked: Array = []
	for e in em.indices_in_radius(pp, reach):
		if not em.grabbable(e) or not em.screen_ok(e):
			continue
		var sc := Aim.cone_score(em, e, pp, f, cone)
		if sc < INF:
			ranked.append([sc, e])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	# pass 137 (lane AIM): the soft rule (Aim.soft_target): a near threat outside the cone is grabbed first; with the cone
	# empty, the lone creature within `lone_reach`
	if Aim.soft(inst):
		var ok := func(e: int) -> bool: return em.grabbable(e) and em.screen_ok(e)
		var s := Aim.soft_target(em, pp, f, reach, cone, int(ranked[0][1]) if not ranked.is_empty() else -1, Aim.cfg(inst), false, "", [], ok)
		if int(s["i"]) >= 0:
			ranked.push_front([0.0, int(s["i"])])
			Aim.note_soft(inst, s)
	if ranked.is_empty():
		return false
	var taken := {}
	for k in range(mini(n, ranked.size())):
		taken[int(ranked[k][1])] = true
	var spots := Aim.circle_spots(em, pp, 2.0, reach + 2.0, taken.size(), _blast_r(), float(Aim.cfg(inst).get("best_chance", Aim.BEST_CHANCE)), "", [], Aim.arena_ok(game))
	var k := 0
	for e: int in taken.keys():
		em.grab(e)
		var target: Vector3 = spots[k % spots.size()] if not spots.is_empty() else em.pos[e]
		_grips.append({"i": e, "phase": PH_GRAB, "t": 0.0, "from": em.pos[e], "rel": float(k) - float(taken.size() - 1) * 0.5,
				"target": target, "bounced": false, "flip_t": 0.0, "slam": spots.is_empty()})
		k += 1
	AimWedge.pulse_dir(f)
	sfx("fire", _core_pos())
	return true


## The Singularity: the claws open, the core swells, and a moment later the black hole goes.
func _fire_hole() -> bool:
	# pass 141 (lane GRAV): a barrel he came up to takes this pull, thrown as the gun throws one (no black hole this time);
	# pass 142: only while no creature stands within `guard` x its range
	if not _creature_near() and _take_barrel():
		sfx("fire", _core_pos())
		return true
	var em: EnemyManager = game.enemies
	var reach := stat("range", 9.0)
	# a crowd no bomb is headed for or has just come down on (pass 36), else the thickest one
	var r := float(_hole().get("radius", 3.2)) * stat("area", 1.0)
	if Aim.covers(inst):
		# pass 136 (lane GUNS): the black hole lands at a spot in the circle round him (Aim.circle_spots, R6), always
		var hs := Aim.circle_spots(em, player.global_position, 2.0, reach, 1, r, float(Aim.cfg(inst).get("best_chance", Aim.BEST_CHANCE)), "", game.projectiles.claimed_spots(), Aim.arena_ok(game))
		if not hs.is_empty():
			_charge = float(_hole().get("charge", 0.35))
			_charge_to = hs[0]
			sfx("fire", _core_pos())
			return true
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
			var a := TAU * float(k) / float(amount) + Dice.r.randf() * 0.5
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
	# pass 141 (lane GRAV): the barrel in the grip, and the search when the gun has nothing
	if _tick_barrel(delta, grab_s, hold_s, throw_s):
		holding = true
	_tick_search(delta)
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
	if Aim.covers(inst):
		# pass 136 (lane GUNS): a spot in the circle round him from the crowd as it is now (R6)
		var cs := Aim.circle_spots(game.enemies, player.global_position, 2.0, stat("range", 7.0) + 2.0, 1, _blast_r(), float(Aim.cfg(inst).get("best_chance", Aim.BEST_CHANCE)), "", avoid, Aim.arena_ok(game))
		if not cs.is_empty():
			g["target"] = cs[0]
		return
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


# ---------------------------------------------------------------- the barrels (pass 141, lane GRAV)

## The nearest standing barrel within barrel_reach() of him taken into the grip (one at a time): it will rise to a spot
## `lift` m over the sand, `pull` of the way from where it stood towards the gun. False when there is none.
func _take_barrel() -> bool:
	if not _bgrip.is_empty():
		return false
	var bf := _barrels()
	if bf == null:
		return false
	var i := bf.nearest_standing(player.global_position, barrel_reach())
	if i < 0 or not bf.carry(i):
		return false
	var b := _block("barrel", BARREL)
	var from: Vector3 = bf.pos[i]
	var core := _core_pos()
	var hold := from.lerp(Vector3(core.x, from.y, core.z), clampf(float(b["pull"]), 0.0, 0.9))
	hold.y = _ground(hold) + float(b["lift"])
	_bgrip = {"i": i, "phase": PH_GRAB, "t": 0.0, "from": from, "hold": hold, "p0": hold, "target": Vector3.INF, "dur": 0.0,
			"roll": 0.0, "roll0": 0.0}
	return true


## The barrel in the grip, a tick: it rises (grab), hangs wobbling (hold), flies to his feet turning (throw) and breaks
## where it lands. The gun's own grab, hold and throw times and arc. True while it is lifted or held.
func _tick_barrel(delta: float, grab_s: float, hold_s: float, throw_s: float) -> bool:
	if _bgrip.is_empty():
		return false
	var bf := _barrels()
	var i: int = _bgrip["i"]
	if bf == null or i >= bf.alive.size() or bf.alive[i] == 0 or not bf.is_carried(i):
		# taken from the gun (the field laid out again)
		_bgrip = {}
		return false
	var b := _block("barrel", BARREL)
	# pass 142: a creature come within the guard: the gun lets the barrel go (still rising or held, it falls back to the
	# sand standing; thrown, it flies on) and the pull it took is given back, so the gun turns to the creature this tick
	if not bool(_bgrip.get("free", false)) and _creature_near():
		_bgrip["free"] = true
		cooldown_left = 0.0
		if int(_bgrip["phase"]) != PH_THROW:
			_bgrip["phase"] = PH_DROP
			_bgrip["t"] = 0.0
			_bgrip["p0"] = bf.pos[i]
			_bgrip["roll0"] = float(_bgrip["roll"])
	var t: float = float(_bgrip["t"]) + delta
	_bgrip["t"] = t
	match int(_bgrip["phase"]):
		PH_DROP:
			var p0: Vector3 = _bgrip["p0"]
			var u := clampf(t / DROP_S, 0.0, 1.0)
			var gy := _ground(p0)
			bf.carry_to(i, Vector3(p0.x, lerpf(p0.y, gy, u * u), p0.z), float(_bgrip["roll0"]) * (1.0 - u), 0.0)
			if u >= 1.0:
				bf.uncarry(i)
				_bgrip = {}
			return false
		PH_GRAB:
			var u := clampf(t / grab_s, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			_bgrip["roll"] = 0.22 * sin(t * 26.0) * u
			bf.carry_to(i, (_bgrip["from"] as Vector3).lerp(_bgrip["hold"], e), float(_bgrip["roll"]), 0.6 * sin(t * 30.0) * (1.0 - u))
			if u >= 1.0:
				_bgrip["phase"] = PH_HOLD
				_bgrip["t"] = 0.0
			return true
		PH_HOLD:
			var wob := Vector3(sin(t * 17.0), sin(t * 23.0) * 0.6, cos(t * 19.0)) * 0.06
			_bgrip["roll"] = 0.2 * sin(t * 13.0)
			bf.carry_to(i, (_bgrip["hold"] as Vector3) + wob, float(_bgrip["roll"]), 0.25 * sin(t * 21.0))
			if t >= hold_s:
				var p0: Vector3 = (_bgrip["hold"] as Vector3) + wob
				var to := _barrel_target(p0, throw_s, b)
				_bgrip["phase"] = PH_THROW
				_bgrip["t"] = 0.0
				_bgrip["p0"] = p0
				_bgrip["target"] = to
				_bgrip["dur"] = throw_s * clampf(Vector2(to.x - p0.x, to.z - p0.z).length() / 6.0, 0.6, 1.3)
				_bgrip["roll0"] = float(_bgrip["roll"])
				_recoil = 1.0
				sfx("hit", p0)
			return true
		PH_THROW:
			var p0: Vector3 = _bgrip["p0"]
			var tgt: Vector3 = _bgrip["target"]
			var u := clampf(t / maxf(float(_bgrip["dur"]), 0.05), 0.0, 1.0)
			var flat := p0.lerp(tgt, u)
			var h := lerpf(p0.y, tgt.y, u) + _g("arc", 2.2) * 4.0 * u * (1.0 - u)
			# it turns `spin` times on the way, forwards the way it flies (thrown to the right it turns clockwise)
			var side := 1.0 if tgt.x - p0.x >= -0.05 else -1.0
			_bgrip["roll"] = float(_bgrip["roll0"]) - side * TAU * float(b["spin"]) * u
			bf.carry_to(i, Vector3(flat.x, h, flat.z), float(_bgrip["roll"]), 0.0)
			if u >= 1.0:
				bf.land_carried(i, tgt, p0)
				barrel_throws += 1
				_bgrip = {}
	return false


## Where a thrown barrel comes down: `ahead` m in front of the Outlaw (his facing) from where his walk puts him by the time
## it lands (x `lead`); at those feet, or his own, when that is past the arena's rim. On the sand.
func _barrel_target(p0: Vector3, throw_s: float, b: Dictionary) -> Vector3:
	var hero := player.global_position
	var v = player.get("velocity")
	var vel: Vector3 = v if v is Vector3 else Vector3.ZERO
	vel.y = 0.0
	var ahead := Aim.facing(player) * float(b["ahead"])
	# the flight lasts as the throw's own rule says for its length (_tick_barrel), so the lead is found in two steps
	var feet := hero
	var at := hero + ahead
	for _k in range(2):
		var fly := throw_s * clampf(Vector2(at.x - p0.x, at.z - p0.z).length() / 6.0, 0.6, 1.3)
		feet = hero + vel * fly * float(b["lead"])
		at = feet + ahead
	var ok := Aim.arena_ok(game)
	if ok.is_valid() and not bool(ok.call(at)):
		at = feet if bool(ok.call(feet)) else hero
	at.y = _ground(at)
	return at


# ---------------------------------------------------------------- the search (pass 141, lane GRAV)

## The gun has something: the search ends and the next waits `every` s from now.
func _found() -> void:
	_search = {}
	_search_wait = float(_block("search", SEARCH)["every"])


## The pull found nothing: a search starts when its clock is up (none running, nothing in the grip).
func _maybe_search() -> void:
	if not _search.is_empty() or _search_wait > 0.0 or not _grips.is_empty() or not _bgrip.is_empty() or _charge > 0.0:
		return
	if float(_block("search", SEARCH)["seconds"]) <= 0.0:
		return
	var f := Aim.facing(player)
	searches += 1
	# each sweep goes the other way from the last
	_search = {"t": 0.0, "yaw": atan2(f.x, f.z), "dir": 1.0 if searches % 2 == 1 else -1.0, "end": Vector3.INF}


## The search, a tick (looks only): the touch point sweeps across his facing (the arc turning with him, slowly) and
## wanders in and out; done after `seconds` (or at once when the gun takes something: _found).
func _tick_search(delta: float) -> void:
	if _search.is_empty():
		_search_wait = maxf(_search_wait - delta, 0.0)
		_scan = move_toward(_scan, 0.0, delta * 4.0)
		return
	var s := _block("search", SEARCH)
	var secs := maxf(float(s["seconds"]), 0.1)
	var t := float(_search["t"]) + delta
	_search["t"] = t
	if t >= secs:
		_search = {}
		_search_wait = float(s["every"])
		return
	_scan = move_toward(_scan, 1.0, delta * 6.0)
	var f := Aim.facing(player)
	_search["yaw"] = lerp_angle(float(_search["yaw"]), atan2(f.x, f.z), clampf(delta * 3.0, 0.0, 1.0))
	var u := t / secs
	var half := deg_to_rad(float(s["sweep_deg"])) * 0.5
	var a := float(_search["yaw"]) + float(_search["dir"]) * lerpf(-half, half, 0.5 - 0.5 * cos(u * PI))
	var d := float(s["reach"]) + float(s["wander"]) * sin(u * TAU * 1.5 + float(searches)) + 0.06 * sin(t * 41.0)
	var at := player.global_position + Vector3(sin(a), 0.0, cos(a)) * maxf(d, 0.5)
	at.y = _ground(at)
	_search["end"] = at
	# a few specks left where it touches, and now and then a grain of sand
	_speck_t -= delta
	var fx = game.get("fx")
	if _speck_t <= 0.0 and fx != null and fx.has_method("mote") and _search_reach() > 0.9:
		_speck_t = 0.06
		fx.mote(at + Vector3(0, 0.06, 0), Vector3(randf_range(-0.25, 0.25), randf_range(0.35, 0.7), randf_range(-0.25, 0.25)), 0.45, 0.11, Color(SEARCH_COLOR.r, SEARCH_COLOR.g, SEARCH_COLOR.b, 0.85))
		if randf() < 0.25:
			fx.mote(at + Vector3(0, 0.04, 0), Vector3(randf_range(-0.5, 0.5), randf_range(0.5, 0.9), randf_range(-0.5, 0.5)), 0.4, 0.09, Color(0.86, 0.74, 0.52, 0.7))


## How far the search beam reaches from the Core to the sand now (0..1: out over SEARCH_IN, back over the last SEARCH_OUT).
func _search_reach() -> float:
	if _search.is_empty():
		return 0.0
	var secs := maxf(float(_block("search", SEARCH)["seconds"]), 0.1)
	var t := float(_search["t"])
	return clampf(t / SEARCH_IN, 0.0, 1.0) * clampf((secs - t) / SEARCH_OUT, 0.0, 1.0)


## Whether a search is running (tests, the capture).
func searching() -> bool:
	return not _search.is_empty()


## The search beam's tip: from the Core out to where it touches the sand, and back.
func _search_tip() -> Vector3:
	var k := _search_reach()
	return _core_pos().lerp(_search["end"], 1.0 - pow(1.0 - k, 2.0))


## The soft glow where the search beam touches the sand (looks only): a flat see-through quad of a radial gradient, `w` m
## wide, `a` strong, tilted to the ground under it.
func _draw_glow(at: Vector3, a: float, w: float) -> void:
	if a <= 0.01 or at == Vector3.INF:
		if _glow:
			_glow.visible = false
		return
	if _glow == null:
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.set("disable_fog", true)
		m.albedo_texture = _glow_texture()
		_glow = MeshInstance3D.new()
		_glow.mesh = pm
		_glow.material_override = m
		_glow.top_level = true
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_glow)
	_glow.visible = true
	(_glow.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, clampf(a, 0.0, 1.0))
	# the ground's slope under it
	var e := 0.35
	var n := Vector3(_ground(at - Vector3(e, 0, 0)) - _ground(at + Vector3(e, 0, 0)), 2.0 * e, _ground(at - Vector3(0, 0, e)) - _ground(at + Vector3(0, 0, e))).normalized()
	var x := (Vector3.RIGHT - n * n.x).normalized()
	var z := x.cross(n)
	_glow.global_transform = Transform3D(Basis(x * w, n, z * w), at + n * 0.04)


static func _glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.16, 0.5, 1.0])
		g.colors = PackedColorArray([Color(0.93, 1.0, 1.0, 0.95), Color(0.6, 0.96, 1.0, 0.85), Color(0.25, 0.78, 1.0, 0.38), Color(0.25, 0.78, 1.0, 0.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_glow_tex = tex
	return _glow_tex


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
	# pass 141 (lane GRAV): at the barrel it lifts and holds, then at where it throws it; at the sand it searches
	if want == Vector3.ZERO and not _bgrip.is_empty():
		var bf := _barrels()
		var bi: int = _bgrip["i"]
		if int(_bgrip["phase"]) == PH_THROW:
			want = Vector3(_bgrip["target"]) - from
		elif int(_bgrip["phase"]) != PH_DROP and bf != null and bi < bf.pos.size():
			want = bf.pos[bi] - from
	if want == Vector3.ZERO and _charge > 0.0 and _charge_to != Vector3.INF:
		want = _charge_to - from
	if want == Vector3.ZERO and not _search.is_empty() and Vector3(_search["end"]) != Vector3.INF:
		want = Vector3(_search["end"]) - from
	if want == Vector3.ZERO and Aim.covers(inst):
		# pass 136 (lane GUNS): idle, it points where he faces
		want = player.forward()
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
		want += Vector3(Dice.r.randf_range(-1.0, 1.0), Dice.r.randf_range(-1.0, 1.0), Dice.r.randf_range(-1.0, 1.0)) * 0.025 * _open
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	# pass 141 (lane GRAV): the nose dips towards the sand while it searches
	_familiar.rotation = Vector3(-0.3 * _recoil + 0.12 * _open - 0.3 * _scan, _aim_yaw, sin(t * 2.1) * 0.06)
	_recoil = maxf(_recoil - delta * 5.0, 0.0)


func _animate(delta: float) -> void:
	var t := float(Time.get_ticks_msec()) * 0.001
	# pass 141 (lane GRAV): a search half opens the claws, quickens the ring and lights the core a little (_scan)
	if _spin:
		_spin.rotate_object_local(Vector3.FORWARD, delta * (lerpf(1.2, 11.0, _open) + 4.0 * _scan))
	for c: Node3D in _claws:
		c.rotation.x = lerpf(0.0, 0.8, maxf(_open, 0.4 * _scan)) + 0.04 * sin(t * 3.0)
	if _core:
		var pulse := 1.0 + 0.07 * sin(t * 7.0)
		_core.scale = Vector3.ONE * (pulse + 0.45 * _open + 0.15 * _scan)
	if _core_mat:
		_core_mat.emission_energy_multiplier = 1.2 + 3.5 * _open + 1.4 * _scan + 0.4 * sin(t * 9.0)


## The beam: a wavering ribbon from the Core to each creature it lifts or holds, facing the camera. Pass 141 (lane GRAV):
## and to the barrel it lifts or holds; while it searches a thinner, fainter, slower ribbon reaching to the sand and back,
## with the glow where it touches. Each end: [point, width x, strength x, waver (m), waver speed].
func _draw_beam() -> void:
	var em: EnemyManager = game.enemies
	var ends: Array = []
	for g: Dictionary in _grips:
		if int(g["phase"]) == PH_THROW:
			continue
		var i: int = g["i"]
		ends.append([em.pos[i] + Vector3(0, em.lift_h[i] + em.size[i] * 0.45, 0), 1.0, 1.0, 0.12, 22.0])
	if not _bgrip.is_empty() and int(_bgrip["phase"]) != PH_THROW and int(_bgrip["phase"]) != PH_DROP:
		var bf := _barrels()
		var bi: int = _bgrip["i"]
		if bf != null and bi < bf.pos.size():
			ends.append([bf.pos[bi] + Vector3(0, 0.55, 0), 1.0, 1.0, 0.12, 22.0])
	var reach := _search_reach()
	if reach > 0.0 and Vector3(_search["end"]) != Vector3.INF:
		var st := float(_search["t"])
		var w := float(_block("search", SEARCH)["glow"])
		ends.append([_search_tip(), 0.65, 0.95, 0.07, 8.0])
		_draw_glow(_search["end"], smoothstep(0.7, 1.0, reach) * (0.85 + 0.15 * sin(st * 12.0)), w * (0.92 + 0.08 * sin(st * 9.0)))
	else:
		_draw_glow(Vector3.INF, 0.0, 0.0)
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
	for end: Array in ends:
		var to: Vector3 = end[0]
		var wk: float = end[1]
		var ak: float = end[2]
		var amp: float = end[3]
		var hz: float = end[4]
		var seg := 14
		var dir := to - from
		var side0 := dir.cross(eye - from).normalized()
		var prev_a := Vector3.ZERO
		var prev_b := Vector3.ZERO
		for s in range(seg + 1):
			var u := float(s) / float(seg)
			var p := from.lerp(to, u) + side0 * sin(u * PI) * amp * sin(t * hz + u * 9.0)
			var w := (0.09 + 0.06 * sin(u * PI)) * wk
			var a := p + side0 * w
			var b := p - side0 * w
			if s > 0:
				# the edges soft cyan, the middle near white
				var mid_p := (prev_a + prev_b) * 0.5
				var mid := (a + b) * 0.5
				var edge := Color(col.r, col.g, col.b, 0.35 * ak)
				var core := Color(0.85, 1.0, 1.0, 0.95 * ak)
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


## Whatever it still holds goes back to the crowd when the gun goes (a swap, the end of the run); a barrel it carries is
## set down standing (pass 141).
func _exit_tree() -> void:
	if not _bgrip.is_empty():
		var bf := _barrels()
		if bf != null and is_instance_valid(bf):
			bf.uncarry(int(_bgrip["i"]))
		_bgrip = {}
	var em = game.get("enemies") if game and is_instance_valid(game) else null
	if em == null or not is_instance_valid(em):
		return
	for g: Dictionary in _grips:
		em.release(int(g["i"]))
	_grips.clear()
