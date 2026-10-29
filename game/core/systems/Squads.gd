## Pass 112 (lane MONK; Garry: "Group Attack - This enemy is unique in that they move at a group, meaning they all use the
## same direction logic, and try their best to keep the same distance from each other. Also they attack at the same
## time ... they fully stop for 3 seconds when attacking. They run away like the Spit Cactus as well, but they do it all
## together. Same attack distance ... They spawn in groups of 10, 20 or 30"): the `squad` brain (EnemyDef.squad, its
## numbers EnemyDef.SQUAD_DEFAULTS).
##
## Who is a squad: the creatures one EnemyManager.spawn_pack brings (spawn_pack: placed on the formation round its point);
## creatures of a squad type spawned one by one in the same tick (a ring, an arena swarm) join the squad of that tick whose
## first member stands within JOIN_R, else start their own. A squad lives while one of its members does.
##
## One movement decision per squad (tick): its anchor, the formation's centre, walks like a kiting Spit Cactus at the
## members' mean walk (the far-speed rule read at the anchor): it backs off straight away from the hero while the
## formation's near edge (`band_from` "edge": the centre's distance less the formation's radius; "center": the centre's) is
## nearer than keep_distance - 0.5, walks in while it is past `range`, and stands between; by the arena's wall it slides
## along it; a rock pushes it out; it never gets more than `leash` m ahead of its members' mean (a blocked squad waits);
## while more than half its members are still coming up out of the sand it waits for them.
## Each member steers to its own slot of a hex blob `spacing` apart round the anchor (steer: the squad's walk plus `gain` x
## the gap, at most `catch_up` x its own walk), and the separation and the rocks push it as any creature's. The slots are
## made again for the members left whenever one dies or leaves (_reshape: the centre slots first, each to the nearest
## member). A member faces the squad's heading while the squad walks (intent_of), the hero while it stands.
##
## One attack clock per squad: `cooldown` s from one volley's start to the next (the first `first` s after it forms, + up to
## 1 s at random). When it is due and the squad stands in its band, every member free to act (walking, on its feet, not
## stunned, frozen, held, buried, in the air, spinning or fleeing) stops (STATE_ATTACK: no walk; a hit's push and the
## crowd still nudge it) for `hold` plain seconds (never stretched by the map's pace; High Noon's slow-down still slows it): its hands rise (the attack strip's wind-up frames for
## `rise` s, attack_frame), then hold up (its hands-up frames, breathing at `breath_fps`); a blue glow gathers between its
## hands from `glow.from` of the sphere's size to all of it; at `release` s every one still in its pose looses one sphere
## at the hero in the same tick (EnergyOrbs.fire: aimed at where he stands, + `orb.lead` of his run over the flight; pass
## 113: by default as one cloud, every sphere on the line from the volley's centre to him, `orb.aim`). A
## stun, a launch or a flee on hit takes a member out of the volley (it never fires); the rest go on.
class_name Squads
extends RefCounted

## a creature spawned alone joins a squad of its type formed in the same tick whose first member is this near
const JOIN_R := 8.5
## the most squads a type may form in one tick out of lone spawns (a guard)
const LOOSE_MAX := 64

var em: EnemyManager
## per creature slot: its squad's id (-1 none) and its place in the squad's member list
var squad_of := PackedInt32Array()
var member_k := PackedInt32Array()
## squad id -> {id, t, members, serials, slots, anchor, vel, heading, radius, cd, atk (-1 = walking), fired, fresh, dirty}
var list: Dictionary = {}
var orbs: EnergyOrbs = null
var _next := 1
var _rng := RandomNumberGenerator.new()
var _forming := false
var _formed := PackedInt32Array()
## type index -> [tick, [squad ids formed out of lone spawns this tick]]
var _loose: Dictionary = {}
var _cfg_cache: Dictionary = {}
## diagnostics and tests
var formed := 0
var volleys_started := 0
var volleys_fired := 0
var last_fire_tick := -1
var last_fired := PackedInt32Array()
## the gathering glows this tick (x, y, z, size) and their colours, handed to EnergyOrbs
var glow_pts := PackedVector4Array()
var glow_cols := PackedColorArray()


func _init(p_em: EnemyManager = null) -> void:
	em = p_em
	Dice.seed_rng(_rng, "squads")


func _ensure() -> void:
	if squad_of.size() == em.pool_max:
		return
	var old := squad_of.size()
	squad_of.resize(em.pool_max)
	member_k.resize(em.pool_max)
	for i in range(old, em.pool_max):
		squad_of[i] = -1
		member_k[i] = -1


## Type `t`'s squad block over the defaults (cached per type).
func cfg_of(t: int) -> Dictionary:
	if not _cfg_cache.has(t):
		var def: EnemyDef = em.types[t]["def"]
		_cfg_cache[t] = def.squad_cfg()
	return _cfg_cache[t]


# ---------------------------------------------------------------- forming

## The hex lattice at unit spacing, nearest the centre first (ties by angle): the formation takes its first n points.
static var _hex := PackedVector2Array()


static func _lattice() -> PackedVector2Array:
	if not _hex.is_empty():
		return _hex
	var pts: Array = []
	var h := sqrt(3.0) * 0.5
	for r in range(-10, 11):
		for q in range(-12, 13):
			var p := Vector2(float(q) + float(r) * 0.5, float(r) * h)
			if p.length() <= 10.0:
				pts.append(p)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var la := snappedf(a.length(), 0.001)
		var lb := snappedf(b.length(), 0.001)
		if la != lb:
			return la < lb
		return a.angle() < b.angle())
	for p: Vector2 in pts:
		_hex.append(p)
	return _hex


## The formation of `n` members `spacing` m apart: the lattice's n nearest points, centred on their mean (flat offsets).
static func formation(n: int, spacing: float) -> PackedVector3Array:
	var lat := _lattice()
	var out := PackedVector3Array()
	if n <= 0:
		return out
	var c := Vector2.ZERO
	for k in range(n):
		c += lat[k % lat.size()]
	c /= float(n)
	for k in range(n):
		var p: Vector2 = (lat[k % lat.size()] - c) * spacing
		out.append(Vector3(p.x, 0.0, p.y))
	return out


## A squad of type `t` round `at` (no members yet).
func _new_squad(t: int, at: Vector3) -> Dictionary:
	var cfg := cfg_of(t)
	var sid := _next
	_next += 1
	var sq := {"id": sid, "t": t, "members": PackedInt32Array(), "serials": PackedInt32Array(), "slots": PackedVector3Array(),
		"anchor": at, "vel": Vector3.ZERO, "heading": Vector3.FORWARD, "radius": 0.0,
		"cd": float(cfg.get("first", 1.5)) + _rng.randf(), "atk": -1.0, "fired": false, "fresh": false, "dirty": true}
	list[sid] = sq
	formed += 1
	return sq


func _join(sq: Dictionary, i: int) -> void:
	_ensure()
	# (a packed array read out of a dictionary is a copy: written back)
	var m: PackedInt32Array = sq["members"]
	var s: PackedInt32Array = sq["serials"]
	m.append(i)
	s.append(em.serial[i])
	sq["members"] = m
	sq["serials"] = s
	squad_of[i] = int(sq["id"])
	member_k[i] = m.size() - 1
	sq["dirty"] = true


## spawn_pack's way for a squad creature: `n` of `def_id` on the formation round `center` (clamped to the arena), one
## squad. Returns how many came.
func spawn_pack(def_id: String, def: EnemyDef, center: Vector3, n: int, elite: EliteModDef, variant: String, overrides: Dictionary, src: Dictionary) -> int:
	var cfg := def.squad_cfg()
	var spots := formation(n, maxf(float(cfg.get("spacing", 1.4)), 0.3))
	_forming = true
	_formed = PackedInt32Array()
	for k in range(n):
		em.spawn(def_id, em._clamp_arena(center + spots[k]), elite, 1.0, 1.0, variant, overrides, src)
	_forming = false
	if _formed.is_empty():
		return 0
	var sq := _new_squad(em.type_idx[_formed[0]], Vector3(center.x, em._height(center.x, center.z), center.z))
	for i: int in _formed:
		_join(sq, i)
	_reshape(sq)
	var came := _formed.size()
	_formed = PackedInt32Array()
	return came


## Every spawn of a squad type (EnemyManager.spawn's end): spawn_pack's member, or a lone one gathered with the others of
## its tick (see the header).
func on_spawn(i: int) -> void:
	_ensure()
	squad_of[i] = -1
	member_k[i] = -1
	if _forming:
		_formed.append(i)
		return
	var t := em.type_idx[i]
	var lo = _loose.get(t)
	if not (lo is Array) or int((lo as Array)[0]) != em._tick:
		lo = [em._tick, []]
		_loose[t] = lo
	var ids: Array = (lo as Array)[1]
	for sid in ids:
		var sq = list.get(int(sid))
		if not (sq is Dictionary) or (sq["members"] as PackedInt32Array).is_empty():
			continue
		var first: int = (sq["members"] as PackedInt32Array)[0]
		if Vector2(em.pos[first].x - em.pos[i].x, em.pos[first].z - em.pos[i].z).length() <= JOIN_R:
			_join(sq, i)
			return
	if ids.size() >= LOOSE_MAX:
		var sq0 = list.get(int(ids[ids.size() - 1]))
		if sq0 is Dictionary:
			_join(sq0, i)
			return
	var nsq := _new_squad(t, em.pos[i])
	nsq["fresh"] = true
	_join(nsq, i)
	ids.append(int(nsq["id"]))


## The slots made again for the members the squad has: the formation's centre slots first, each to the nearest member
## not yet placed; its radius (the farthest slot).
func _reshape(sq: Dictionary) -> void:
	var m: PackedInt32Array = sq["members"]
	var n := m.size()
	var cfg := cfg_of(int(sq["t"]))
	var spots := formation(n, maxf(float(cfg.get("spacing", 1.4)), 0.3))
	var anchor: Vector3 = sq["anchor"]
	var taken := PackedByteArray()
	taken.resize(n)
	var slots := PackedVector3Array()
	slots.resize(n)
	var r := 0.0
	for s in range(n):
		var at: Vector3 = anchor + spots[s]
		r = maxf(r, Vector2(spots[s].x, spots[s].z).length())
		var best := -1
		var bd := INF
		for k in range(n):
			if taken[k] == 1:
				continue
			var p: Vector3 = em.pos[m[k]]
			var d := Vector2(p.x - at.x, p.z - at.z).length_squared()
			if d < bd:
				bd = d
				best = k
		taken[best] = 1
		slots[best] = spots[s]
	sq["slots"] = slots
	sq["radius"] = r
	for k in range(n):
		member_k[m[k]] = k
	sq["dirty"] = false


## Its members still with it (alive, the same creature, not dying); false once none is.
func _prune(sq: Dictionary) -> bool:
	var m: PackedInt32Array = sq["members"]
	var s: PackedInt32Array = sq["serials"]
	var sid: int = sq["id"]
	var km := PackedInt32Array()
	var ks := PackedInt32Array()
	for k in range(m.size()):
		var i := m[k]
		if em.alive[i] == 1 and em.serial[i] == s[k] and em.state[i] != EnemyManager.STATE_DYING and squad_of[i] == sid:
			km.append(i)
			ks.append(s[k])
	if km.size() != m.size():
		sq["members"] = km
		sq["serials"] = ks
		sq["dirty"] = true
	return not km.is_empty()


# ---------------------------------------------------------------- the tick (EnemyManager._physics_process, before the crowd)

func tick(delta: float, ppos: Vector3) -> void:
	_ensure()
	glow_pts.clear()
	glow_cols.clear()
	if not list.is_empty():
		var gone: Array = []
		for sid in list.keys():
			var sq: Dictionary = list[sid]
			if not _prune(sq):
				gone.append(sid)
				continue
			_tick_one(sq, delta, ppos)
		for sid in gone:
			list.erase(sid)
	if orbs != null and is_instance_valid(orbs):
		orbs.set_glows(glow_pts, glow_cols)
	elif not glow_pts.is_empty():
		orbs_node().set_glows(glow_pts, glow_cols)


func _tick_one(sq: Dictionary, delta: float, ppos: Vector3) -> void:
	var cfg := cfg_of(int(sq["t"]))
	var m: PackedInt32Array = sq["members"]
	var n := m.size()
	var mean := Vector3.ZERO
	var spd := 0.0
	var rising := 0
	for i: int in m:
		mean += em.pos[i]
		spd += em.speed[i]
		if em.state[i] == EnemyManager.STATE_SPAWN or em.rise_t[i] < 1.0:
			rising += 1
	mean /= float(n)
	spd /= float(n)
	if bool(sq["fresh"]):
		sq["fresh"] = false
		sq["anchor"] = mean
		sq["dirty"] = true
	if bool(sq["dirty"]):
		_reshape(sq)
	var anchor: Vector3 = sq["anchor"]
	var flat := Vector3(ppos.x - anchor.x, 0.0, ppos.z - anchor.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.001 else Vector3.ZERO
	# far from the hero the whole squad walks faster together (pass 111's far_speed, read at the anchor)
	if em.far_speed_on and dist > em._far_d:
		spd *= em.far_speed_k(m[0], dist)
	var edge := dist - (0.0 if str(cfg.get("band_from", "edge")) == "center" else float(sq["radius"]))
	var keep := float(cfg.get("keep_distance", 5.5))
	var rng := float(cfg.get("range", 8.0))
	var want := Vector3.ZERO
	sq["cd"] = float(sq["cd"]) - delta
	if float(sq["atk"]) >= 0.0:
		_attack_tick(sq, cfg, delta, ppos)
	elif rising * 2 > n:
		# most of it is still coming up out of the sand: it waits for its members
		want = Vector3.ZERO
	elif edge < keep - 0.5:
		want = -dir * spd
	elif edge > rng:
		want = dir * spd
	elif float(sq["cd"]) <= 0.0:
		_attack_start(sq, cfg)
	want = _along_wall(anchor, want)
	sq["vel"] = want
	if want.length_squared() > 0.0001:
		sq["heading"] = want.normalized()
	anchor += want * delta
	anchor = _off_rocks(anchor)
	var off := Vector3(anchor.x - mean.x, 0.0, anchor.z - mean.z)
	var leash := maxf(float(cfg.get("leash", 1.2)), 0.1)
	if off.length() > leash:
		var o := off / off.length() * leash
		anchor = Vector3(mean.x + o.x, anchor.y, mean.z + o.z)
	anchor = em._clamp_arena(anchor)
	anchor.y = em._height(anchor.x, anchor.z)
	sq["anchor"] = anchor


## A heading `want` at the arena's wall: the part that would take the anchor out goes, and it slides along the wall at its
## speed (a flee straight into the wall turns along it).
func _along_wall(at: Vector3, want: Vector3) -> Vector3:
	var flat := Vector2(at.x, at.z)
	var r := flat.length()
	if want.length_squared() < 0.0001 or r < em.arena_radius - 6.0 or r < 0.001:
		return want
	var out := Vector3(flat.x / r, 0.0, flat.y / r)
	var o := want.dot(out)
	if o <= 0.0:
		return want
	var tg := want - out * o
	if tg.length_squared() < 0.0001:
		tg = Vector3(-out.z, 0.0, out.x)
	return tg.normalized() * want.length()


## The anchor pushed out of any rock it stands in (the map's obstacle circles), so the slots flow round it.
func _off_rocks(at: Vector3) -> Vector3:
	var cell = em._obst_cells.get(Vector2i(floori(at.x / EnemyManager.OBST_CELL), floori(at.z / EnemyManager.OBST_CELL)))
	if cell == null:
		return at
	for k: int in cell:
		var o: Vector3 = em.obstacles[k]
		var d := Vector2(at.x - o.x, at.z - o.y)
		var r := o.z + 0.4
		if d.length_squared() < r * r:
			var l := d.length()
			var u := d / l if l > 0.001 else Vector2(1, 0)
			at = Vector3(o.x + u.x * r, at.y, o.y + u.y * r)
	return at


# ---------------------------------------------------------------- the members (EnemyManager._steer)

## Member `i`'s walk (the squad brain in _steer; `spd` its own walk now): the squad's walk plus `gain` x the gap to its
## slot, at most `catch_up` x its own walk.
func steer(i: int, spd: float) -> Vector3:
	if i >= squad_of.size():
		return Vector3.ZERO
	var sq = list.get(squad_of[i])
	if not (sq is Dictionary):
		return Vector3.ZERO
	var v: Vector3 = sq["vel"]
	var slots: PackedVector3Array = sq["slots"]
	var k := member_k[i]
	if k < 0 or k >= slots.size():
		return v
	var cfg := cfg_of(int(sq["t"]))
	var target: Vector3 = (sq["anchor"] as Vector3) + slots[k]
	var to := target - em.pos[i]
	to.y = 0.0
	var desired := v + to * float(cfg.get("gain", 2.5))
	var cap := maxf(spd, 0.0) * maxf(float(cfg.get("catch_up", 1.5)), 1.0)
	var l := desired.length()
	if l > cap and l > 0.0001:
		desired = desired / l * cap
	return desired


## What member `i` means (its facing and its walk cycle): the squad's heading while the squad walks; its own walk to its
## slot while the squad stands and it is off it; else nothing (it faces the hero).
func intent_of(i: int, desired: Vector3) -> Vector3:
	if i >= squad_of.size():
		return desired
	var sq = list.get(squad_of[i])
	if not (sq is Dictionary):
		return desired
	var v: Vector3 = sq["vel"]
	if v.length_squared() > 0.04:
		return (sq["heading"] as Vector3) * maxf(desired.length(), v.length())
	return desired if desired.length_squared() > 0.36 else Vector3.ZERO


# ---------------------------------------------------------------- the volley

## Whether member `i` can join a volley now.
func free_to_act(i: int) -> bool:
	return em.alive[i] == 1 and em.state[i] == EnemyManager.STATE_MOVE and em.stun_t[i] <= 0.0 and em.freeze_t[i] <= 0.0 \
		and em.held[i] == 0 and em.hidden[i] == 0 and em.lift_t[i] <= 0.0 and em.rise_t[i] >= 1.0 and em.spin_t[i] <= 0.0 \
		and not em.is_fleeing(i)


func _attack_start(sq: Dictionary, cfg: Dictionary) -> void:
	var started := 0
	for i: int in (sq["members"] as PackedInt32Array):
		if free_to_act(i):
			em.state[i] = EnemyManager.STATE_ATTACK
			em.vel[i] = Vector3.ZERO
			em.anim_t[i] = 0.0
			started += 1
	if started == 0:
		return
	sq["atk"] = 0.0
	sq["fired"] = false
	sq["cd"] = maxf(float(cfg.get("cooldown", 5.2)), 0.1)
	sq["vel"] = Vector3.ZERO
	volleys_started += 1
	var def: EnemyDef = em.types[int(sq["t"])]["def"]
	Audio.play(str(def.sfx.get("attack", "")), sq["anchor"])


func _attack_tick(sq: Dictionary, cfg: Dictionary, delta: float, ppos: Vector3) -> void:
	# plain seconds (Garry: hands held "about 3 seconds" on every map): the map's pace knob does not stretch the stop;
	# `delta` carries High Noon's time_scale, as every creature clock does
	var u := float(sq["atk"]) + delta
	sq["atk"] = u
	var release := float(cfg.get("release", 1.0))
	if not bool(sq["fired"]) and u >= release:
		sq["fired"] = true
		_fire(sq, cfg, ppos)
	elif not bool(sq["fired"]):
		_glows(sq, cfg, ppos, u)
	if u >= float(cfg.get("hold", 3.0)):
		for i: int in (sq["members"] as PackedInt32Array):
			if em.state[i] == EnemyManager.STATE_ATTACK:
				em.state[i] = EnemyManager.STATE_MOVE
		sq["atk"] = -1.0


## Where member `i`'s glow sits `u` s into the stop: its `hands` point (a muzzle), rising from `from_up` to `up` with the hands.
func hands_at(i: int, cfg: Dictionary, u: float, ppos: Vector3) -> Vector3:
	var h: Dictionary = cfg.get("hands", {})
	var rise := maxf(float(cfg.get("rise", 0.5)), 0.01)
	var k := clampf(u / rise, 0.0, 1.0)
	var up := lerpf(float(h.get("from_up", 1.05)), float(h.get("up", 1.75)), k * k * (3.0 - 2.0 * k))
	return em.muzzle_point(i, ppos - em.pos[i], {"up": up, "side": float(h.get("side", 0.0)), "forward": float(h.get("forward", 0.2))})


func _held(i: int) -> bool:
	return em.state[i] == EnemyManager.STATE_ATTACK and em.stun_t[i] <= 0.0 and em.freeze_t[i] <= 0.0 and em.held[i] == 0 \
		and em.lift_t[i] <= 0.0 and em.hidden[i] == 0


func _glows(sq: Dictionary, cfg: Dictionary, ppos: Vector3, u: float) -> void:
	var ob: Dictionary = cfg.get("orb", {})
	var gl: Dictionary = cfg.get("glow", {})
	var f := clampf(u / maxf(float(cfg.get("release", 1.0)), 0.01), 0.0, 1.0)
	var s := float(ob.get("size", 0.5)) * lerpf(float(gl.get("from", 0.2)), 1.0, f * f * (3.0 - 2.0 * f))
	var c := Color(str(ob.get("color", "#2F7BFF")))
	for i: int in (sq["members"] as PackedInt32Array):
		if _held(i):
			var p := hands_at(i, cfg, u, ppos)
			glow_pts.append(Vector4(p.x, p.y, p.z, s))
			glow_cols.append(c)


func _fire(sq: Dictionary, cfg: Dictionary, ppos: Vector3) -> void:
	var ob: Dictionary = cfg.get("orb", {})
	var o := orbs_node()
	var hv := Vector3.ZERO
	if em.player != null and "velocity" in em.player:
		hv = em.player.velocity
		hv.y = 0.0
	var speed := maxf(float(ob.get("speed", 4.0)), 0.1)
	var reach := maxf(float(ob.get("range", 17.5)), 0.5)
	var lead := float(ob.get("lead", 0.0))
	var u := float(cfg.get("release", 1.0))
	last_fired = PackedInt32Array()
	var shooters := PackedInt32Array()
	var froms := PackedVector3Array()
	for i: int in (sq["members"] as PackedInt32Array):
		if not _held(i):
			continue
		shooters.append(i)
		froms.append(hands_at(i, cfg, u, ppos))
	if shooters.is_empty():
		return
	# pass 113 (Garry: "these projectiles actually move as a cloud ... where the center is aiming, where the hero actually
	# is"): `aim` "cloud" (the default) flies every sphere along one line, the volley's centre's to the hero, so the volley
	# keeps the squad's shape and its middle passes over his spot; "each" aims every sphere at him on its own (pass 112)
	var cloud := str(ob.get("aim", "cloud")) != "each"
	var cloud_d := Vector3.ZERO
	if cloud:
		var c := Vector3.ZERO
		for f: Vector3 in froms:
			c += f
		c /= float(froms.size())
		cloud_d = _aim_dir(c, ppos, hv, speed, lead)
	for k in range(shooters.size()):
		var i: int = shooters[k]
		var from: Vector3 = froms[k]
		var d := cloud_d if cloud else _aim_dir(from, ppos, hv, speed, lead)
		o.fire(from, d, speed, reach, em.dmg[i] * float(ob.get("damage_mult", 1.0)), ob, em.hit_info(i, "ranged", ["energy sphere"]))
		last_fired.append(i)
	if last_fired.is_empty():
		return
	volleys_fired += 1
	last_fire_tick = em._tick
	var def: EnemyDef = em.types[int(sq["t"])]["def"]
	Audio.play(str(def.sfx.get("shot", "")), sq["anchor"])


## The flat unit line from `from` to the hero at `ppos` (+ `lead` of his run `hv` over the flight at `speed`).
func _aim_dir(from: Vector3, ppos: Vector3, hv: Vector3, speed: float, lead: float) -> Vector3:
	var aim := ppos
	if lead > 0.0:
		var fl := Vector2(ppos.x - from.x, ppos.z - from.z).length() / (speed * maxf(em.hostile_clock(), 0.05))
		aim += hv * fl * lead
	var d := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	if d.length_squared() < 0.0001:
		return Vector3.FORWARD
	return d.normalized()


## The spheres' node, made on first use under the shots (never darkened by a stage filter), or under the manager.
func orbs_node() -> EnergyOrbs:
	if orbs != null and is_instance_valid(orbs):
		return orbs
	orbs = EnergyOrbs.new()
	orbs.name = "EnergyOrbs"
	orbs.enemies = em
	orbs.game = em.game
	var parent: Node = null
	if em.game != null:
		var pm = em.game.get("projectiles")
		if pm is Node:
			parent = pm
	if parent == null:
		parent = em
	parent.add_child(orbs)
	return orbs


# ---------------------------------------------------------------- the look

## How far into its squad's stop member `i` is (seconds on the attack clock); -1 when its squad is walking.
func attack_clock_of(i: int) -> float:
	if i >= squad_of.size():
		return -1.0
	var sq = list.get(squad_of[i])
	return float(sq["atk"]) if sq is Dictionary else -1.0


## The frame of the `attack` strip (`strip`: A_ATTACK or its left copy) member `i` of type `t` shows: the strip's front
## half, or its back half while it faces away (attack_views "front_back"; an eight-direction creature by its view: back or
## back-diagonal); in that half the first half of the frames are the hands rising (played through once over `rise`), the
## rest the hands up (one after the other at `breath_fps`). Two frames a half: the first rising, the second held.
func attack_frame(i: int, t: int, strip: int) -> int:
	var n: int = em._t_cnt[t * EnemyManager.N_ANIMS + strip]
	var off: int = em._t_off[t * EnemyManager.N_ANIMS + strip]
	if n <= 1:
		return off
	var half := n
	if em._t_atkv[t] == 1:
		half = n >> 1
		if faces_away(i, t):
			off += half
	if half < 2:
		return off
	var q := half >> 1
	var cfg := cfg_of(t)
	var u := maxf(attack_clock_of(i), 0.0)
	var rise := maxf(float(cfg.get("rise", 0.5)), 0.01)
	if u < rise:
		return off + mini(int(u / rise * float(q)), q - 1)
	return off + q + (int((u - rise) * maxf(float(cfg.get("breath_fps", 2.0)), 0.0)) % maxi(half - q, 1))


## Whether member `i` shows its back half: an eight-direction creature by its view (back, back-diagonal), else `away`.
func faces_away(i: int, t: int) -> bool:
	if em._t_eight[t] == 1:
		return em.view[i] == 1 or em.view[i] == 3
	return em.away[i] == 1
