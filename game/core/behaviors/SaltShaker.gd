## The Salt (pass 69, Garry: "Leaves a white half transparent patch in hero's wake, which damages enemies as long as
## they are walking or standing in it ... Increasing number of projectiles increases the number of patches that hero
## leaves in their way. Kind of like with mines ... a little salt shaker floats around the hero, shaking occasionally to
## pour some more salt down on the floor").
##
## Every cooldown the shaker pours `amount` patches (core/systems/SaltPatches.gd) along the hero's recent path: the first
## a little behind his heels, the next `salt.spacing` metres further back along the way he came; standing still, they
## go round his feet instead. A patch is `salt.radius` x area x `salt.area_mult` metres across its middle, lasts
## `duration` x `salt.duration_mult` seconds, and every `salt.tick` seconds each creature standing in any patch takes
## one hit of damage x `salt.damage_mult` through the weapon's own path (crits, might, the kill counted for the Salt): a
## creature in two patches at once is hit once. At most `salt.max_patches` lie at once (the oldest fades first).
##
## The path (`params.salt`, merged from the mutations, then an evolution's `final`):
##   Sea Salt         color/contents pink, duration_mult 1.75, damage_mult 0.95
##   Salt Spill       area_mult 1.6
##   Thing About Luck luck_mult 3: a creature killed standing in a patch rolls the power-up drop at 3x (Game asks
##                    powerup_luck_at at the kill)
##   Salt Flats       momentum_on_enter (Buck/Jezyk): walking INTO a patch from outside it puts his charge at full
##                    (Player.max_momentum); a patch laid round his feet waits for him to walk out and back in
##   Hiwa Kai         black salt, `crystals` {count, color} strewn on each patch, the three above amplified, `crunch`
##                    {mult}: a creature that walks into the salt takes one extra hit of mult x a tick's damage, and
##                    `slow`: it moves that much slower while it stands in the salt
## The shaker is art/props/salt_shaker.glb (tools/blender_salt.py) under the visual's "Shaker" node: it floats
## `shaker.distance` from the hero, circling slowly and bobbing, and tips over and shakes at every pour while grains fall
## from its cap. Its "Contents" mesh takes the salt's colour.
class_name SaltShaker
extends WeaponBehavior

## the hero's way behind him: points newest first, one every PATH_STEP metres he walks, at most PATH_MAX of them
const PATH_STEP := 0.3
const PATH_MAX := 80
## how far behind his heels the first patch of a pour lies while he walks
const FIRST_BACK := 0.4
## a pour's tip-and-shake, seconds
const SHAKE_TIME := 0.45
## a frame in which the hero moved less than this (metres) does not count as walking into a patch (Salt Flats)
const MOVE_EPS := 0.0005

var patches: SaltPatches
var shaker: Node3D
var _contents: MeshInstance3D
var _spout: Node3D
var _path: Array = []
var _tick_t := 0.0
var _orbit := 0.0
var _shake_t := -1.0
var _last_hero := Vector3.INF
## the creatures (by spawn serial) that stood in the salt at the last tick: Hiwa Kai's crunch is for the ones walking in
var _in_salt: Dictionary = {}
## the shaker's own size (the visual's scale on its Shaker node), kept when the behaviour sets its basis
var _shaker_scale := Vector3.ONE
## pours so far, patches laid, damage ticks dealt, crunches, Salt Flats charges (tests, the arena)
var pours := 0
var laid := 0
var ticks_dealt := 0
var crunches := 0
var flats := 0


func _uses_projectiles() -> bool:
	return false


func _on_setup() -> void:
	patches = SaltPatches.new()
	patches.name = "SaltPatches"
	add_child(patches)
	var map = game.get("map")
	var hf := Callable()
	if map != null and map.has_method("height_at"):
		hf = Callable(map, "height_at")
	patches.setup(game.get("telegraphs"), hf, int(_salt().get("max_patches", 40)))
	shaker = visual.get_node_or_null("Shaker") as Node3D
	if shaker == null:
		shaker = _fallback_shaker()
		visual.add_child(shaker)
	_shaker_scale = shaker.scale if shaker.scale.length_squared() > 0.0001 else Vector3.ONE
	shaker.top_level = true
	for c in shaker.find_children("*", "MeshInstance3D", true, false):
		if str(c.name) == "Contents":
			_contents = c
	for c in shaker.find_children("Spout", "", true, false):
		_spout = c as Node3D
	_orbit = randf() * TAU
	refresh_marks()
	if player:
		_last_hero = player.global_position
		_fly(0.0)


## The look follows the path: Game calls refresh_marks on every build change (a mutation, the evolution's own setup).
func refresh_marks() -> void:
	super.refresh_marks()
	if patches == null:
		return
	var s := _salt()
	var col := Color(str(s.get("color", "#FFFFFF")))
	var cr = s.get("crystals")
	var ccol := Color(str((cr as Dictionary).get("color", "#0B0B0D"))) if cr is Dictionary else Color(0.04, 0.04, 0.05)
	patches.set_look(col, float(s.get("alpha", 0.5)), ccol)
	patches.cap = maxi(int(s.get("max_patches", 40)), 1)
	if _contents:
		var m := StandardMaterial3D.new()
		var cc := Color(str(s.get("contents", s.get("color", "#F4F4F0"))))
		m.albedo_color = cc
		m.roughness = 0.9
		# it glows a little in its own colour, so the salt reads through the glass from the high camera; black salt glints
		m.emission_enabled = true
		m.emission = cc if cc.v > 0.3 else Color(0.18, 0.18, 0.2)
		m.emission_energy_multiplier = 0.35
		_contents.material_override = m


## params.salt with its defaults.
func _salt() -> Dictionary:
	var s = inst.params.get("salt", {})
	return s if s is Dictionary else {}


## A patch's radius now: salt.radius x area x salt.area_mult.
func patch_radius() -> float:
	var s := _salt()
	return float(s.get("radius", 1.4)) * stat("area", 1.0) * float(s.get("area_mult", 1.0))


## How long a patch lies: duration x salt.duration_mult.
func patch_seconds() -> float:
	return stat("duration", 4.0) * float(_salt().get("duration_mult", 1.0))


## One tick's damage: damage x salt.damage_mult.
func tick_damage() -> float:
	return stat("damage", 6.0) * float(_salt().get("damage_mult", 1.0))


func tick_seconds() -> float:
	return maxf(float(_salt().get("tick", 0.5)), 0.1)


## Thing About Luck: the factor on the power-up drop for a creature killed at `at` (salt.luck_mult while it stood in a
## patch, else 1). Game._drop_from_kill asks every weapon behaviour that has this.
func powerup_luck_at(at: Vector3) -> float:
	var m := float(_salt().get("luck_mult", 1.0))
	if m <= 1.0 or patches == null:
		return 1.0
	return m if patches.contains(at) else 1.0


# ---------------------------------------------------------------- the pour

func _fire() -> bool:
	if player == null:
		return false
	var n: int = maxi(stat_int("amount", 1), 1)
	var r := patch_radius()
	var secs := patch_seconds()
	var cr = _salt().get("crystals")
	var cn := int((cr as Dictionary).get("count", 0)) if cr is Dictionary else 0
	var hero: Vector3 = player.global_position
	var col := Color(str(_salt().get("color", "#FFFFFF")))
	for at: Vector3 in pour_spots(n):
		patches.add(at, r, secs, hero, cn)
		laid += 1
		var fx = game.get("fx")
		if fx != null and fx.has_method("salt_land"):
			fx.salt_land(Vector3(at.x, patches.ground_at(at.x, at.z), at.z), col, r)
	pours += 1
	_shake_t = 0.0
	sfx("fire", hero)
	return true


## Where this pour's `n` patches go: back along the hero's way, the first FIRST_BACK metres behind his heels and each
## next one `salt.spacing` further; the ones the way is too short for (he stood still) go round his feet, the first on
## them.
func pour_spots(n: int) -> Array:
	var spacing := maxf(float(_salt().get("spacing", 1.2)), 0.2)
	var hero: Vector3 = player.global_position
	var out: Array = []
	var pts: Array = [hero] + _path
	var k := 0
	var want := FIRST_BACK
	var walked := 0.0
	var seg := 0
	while k < n and seg < pts.size() - 1:
		var a: Vector3 = pts[seg]
		var b: Vector3 = pts[seg + 1]
		var l := Vector2(b.x - a.x, b.z - a.z).length()
		if walked + l >= want and l > 0.0001:
			var f := (want - walked) / l
			out.append(a.lerp(b, f))
			k += 1
			want += spacing
			continue
		walked += l
		seg += 1
	# standing (or a way too short): round his feet, on a sunflower spiral
	var left := n - k
	for q in range(left):
		if q == 0 and k == 0:
			out.append(hero)
			continue
		var j := float(q + k)
		var a2 := j * 2.39996
		var rr := spacing * 0.8 * sqrt(j)
		out.append(hero + Vector3(cos(a2) * rr, 0.0, sin(a2) * rr))
	return out


# ---------------------------------------------------------------- every frame

func _tick(delta: float) -> void:
	if player == null or patches == null:
		return
	_note_path()
	patches.advance(delta)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = tick_seconds()
		_bite()
	if bool(_salt().get("momentum_on_enter", false)):
		_salt_flats()
	else:
		_track_hero()
	_fly(delta)
	patches.draw()


## The hero's way: a point every PATH_STEP metres he walks, newest first.
func _note_path() -> void:
	var p: Vector3 = player.global_position
	if _path.is_empty():
		_path.append(p)
		return
	var last: Vector3 = _path[0]
	if Vector2(p.x - last.x, p.z - last.z).length() >= PATH_STEP:
		_path.push_front(p)
		if _path.size() > PATH_MAX:
			_path.resize(PATH_MAX)


## One tick: every creature standing in a working patch takes one hit (Hiwa Kai: a crunch more for the ones that walked
## in since the last tick, and the slow).
func _bite() -> void:
	var em: EnemyManager = game.get("enemies")
	if em == null or patches.patches.is_empty():
		_in_salt.clear()
		return
	var s := _salt()
	var dmg := tick_damage()
	var crunch = s.get("crunch")
	var crunch_mult := float((crunch as Dictionary).get("mult", 0.0)) if crunch is Dictionary else 0.0
	var slow_f := clampf(float(s.get("slow", 0.0)), 0.0, 0.95)
	var seen: Dictionary = {}
	var now: Dictionary = {}
	for q in patches.patches:
		if q["dying"]:
			continue
		var c: Vector3 = q["at"]
		var r := float(q["r"])
		for i in em.indices_in_radius(c, r):
			if seen.has(i):
				continue
			seen[i] = true
	var wid := inst.def.id
	for i: int in seen.keys():
		if em.alive[i] == 0 or em.state[i] == EnemyManager.STATE_DYING:
			continue
		var ser: int = em.serial[i]
		now[ser] = true
		if slow_f > 0.0:
			em.slow(i, slow_f, tick_seconds() + 0.15, false)
		if crunch_mult > 0.0 and not _in_salt.has(ser):
			crunches += 1
			if em.damage(i, dmg * crunch_mult, wid):
				inst.kills += 1
				continue
		ticks_dealt += 1
		if em.damage(i, dmg, wid):
			inst.kills += 1
	_in_salt = now


## Salt Flats: the hero walked into a patch he was outside of on the last frame (and moved): his charge to full.
func _salt_flats() -> void:
	var p: Vector3 = player.global_position
	var moved := _last_hero != Vector3.INF and Vector2(p.x - _last_hero.x, p.z - _last_hero.z).length() > MOVE_EPS
	var hit := false
	for q in patches.patches:
		var inside: bool = SaltPatches._inside_xz(q["at"], float(q["r"]), p) and not bool(q["dying"])
		if inside and not q["hero_in"] and moved:
			hit = true
		q["hero_in"] = inside
	_last_hero = p
	if hit and player.has_method("max_momentum"):
		if player.max_momentum():
			flats += 1
			var fx = game.get("fx")
			if fx != null and fx.has_method("salt_land"):
				fx.salt_land(p, Color(str(_salt().get("color", "#FFFFFF"))), 0.9)


## Without Salt Flats the patches still note whether he stands in them, so taking the mutation later never counts a
## patch he already stood in.
func _track_hero() -> void:
	var p: Vector3 = player.global_position
	for q in patches.patches:
		q["hero_in"] = SaltPatches._inside_xz(q["at"], float(q["r"]), p) and not q["dying"]
	_last_hero = p


# ---------------------------------------------------------------- the shaker

## Floats the shaker round the hero (shaker.distance out, shaker.height up, circling at orbit_speed and bobbing), turned
## a little as it goes; at a pour it tips over away from him and shakes, and grains fall from its cap.
func _fly(delta: float) -> void:
	if shaker == null:
		return
	var sh = inst.params.get("shaker", {})
	var d: Dictionary = sh if sh is Dictionary else {}
	var r := float(d.get("distance", 1.2))
	var h := float(d.get("height", 1.25))
	_orbit += delta * float(d.get("orbit_speed", 0.55))
	var t := Run.rule_seconds()  # pass 77 (lane SIMRUN): real time in play, the run's clock in a run sim
	var want: Vector3 = player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 2.3) * float(d.get("bob", 0.08)), sin(_orbit) * r)
	shaker.global_position = want if delta <= 0.0 else shaker.global_position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	# upright, turning slowly about itself; at a pour, tipped outwards (away from the hero) and shaken
	var out := Vector3(cos(_orbit), 0.0, sin(_orbit))
	var tip := 0.0
	var jiggle := 0.0
	if _shake_t >= 0.0:
		_shake_t += delta
		var f := clampf(_shake_t / SHAKE_TIME, 0.0, 1.0)
		tip = sin(f * PI) * 1.9
		jiggle = sin(_shake_t * 46.0) * 0.18 * sin(f * PI)
		if f > 0.2 and f < 0.8:
			_grains(out)
		if f >= 1.0:
			_shake_t = -1.0
	var axis := Vector3(-out.z, 0.0, out.x)
	var b := Basis(Vector3.UP, t * 0.7)
	if tip > 0.0:
		b = Basis(axis, -(tip + jiggle)) * b
	shaker.global_basis = b.scaled(_shaker_scale)


## A few grains falling from the shaker's cap while it shakes.
func _grains(out: Vector3) -> void:
	var fx = game.get("fx")
	if fx == null or not fx.has_method("salt_grains"):
		return
	var from: Vector3 = _spout.global_position if _spout else shaker.global_position + out * 0.15
	fx.salt_grains(from, Color(str(_salt().get("contents", _salt().get("color", "#FFFFFF")))))


## The shaker when the visual has none (tests, a missing model): a glass-white cylinder with a grey cap.
func _fallback_shaker() -> Node3D:
	var root := Node3D.new()
	root.name = "Shaker"
	var body := MeshInstance3D.new()
	body.name = "Contents"
	var c := CylinderMesh.new()
	c.top_radius = 0.07
	c.bottom_radius = 0.08
	c.height = 0.24
	body.mesh = c
	root.add_child(body)
	var cap := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.075
	s.height = 0.08
	cap.mesh = s
	cap.position = Vector3(0, 0.13, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.82, 0.86)
	m.metallic = 0.8
	cap.material_override = m
	root.add_child(cap)
	return root
