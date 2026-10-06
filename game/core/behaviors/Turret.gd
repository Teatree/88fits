## A stationary turret dropped by Spawner. Shoots the nearest enemy; expires after `lifetime`.
## The model (pass 46) is the visual scene's "Turret" node, an instance of art/props/turret_buddy.glb (the gold
## turret_family.glb for the evolution): three stands, each with an empty on top (Base/BaseTop, the tripod's Tripod/
## TripodTop for a "tower" stance (the Watchtower's, shelved in pass 47), the Bunker's Sandbags/SandbagsTop), and one
## head, Yaw, that turns about its origin; Yaw/Gun pitches and holds one Barrel, or the Bunker's twin BarrelL and
## BarrelR, each with a Muzzle at its tip. Only the stance's stand and barrels show, and the head sits on that stand's
## top. Every shot kicks the barrel back and eases it home, flashes and smokes at the muzzle, throws a casing and leaves
## a tracer (the weapon's params.tracer). Without the model it builds the old primitive shapes from the visual's "Held"
## mesh. Pass 47 (Garry: the barrel "shouldn't just snap to aiming at the enemy, it should actually move its head, which
## adds delay to how fast it can shoot them too"): the head turns towards its target at params.turret.turn degrees a
## second (TURN_DEFAULT; the Bunker's is slower), the gun's tilt eases after it, and a round leaves only once the barrel
## points within AIM_TOLERANCE_DEG of the target; it keeps a target while it lives and stays in range.
## Pass 48: a new target is the weapon's WeaponBehavior.aim_index: with `"targeting": "priority"` (the Turret Buddy and
## the Turret Family) the strong and the close before the merely close, else the nearest.
## Pass 53: Last Stand (params.turret.boom) blows a turret up as it goes (_last_stand); the Iron Bastion's model is
## art/props/iron_bastion.glb (tools/blender_turret.py), the bunker stance made heavy, with the same node names.
class_name Turret
extends Node3D

## how far a barrel kicks back along itself, and how fast it comes home (1/s)
const KICK := 0.12
const KICK_RETURN := 7.0
## it pops up out of the sand over this long, and fires once it is up
const POP_IN := 0.25
## the head's traverse when the stance names none (degrees a second), how close the barrel must point before a round
## leaves, how fast the gun's tilt eases to its target's (1/s), and how often a turret with nothing to shoot looks again
const TURN_DEFAULT := 240.0
const AIM_TOLERANCE_DEG := 6.0
const PITCH_EASE := 8.0
const LOOK_EVERY := 0.1

var owner_behavior: WeaponBehavior
var life := 12.0
var fire_rate := 0.35
var _fire_t := 0.0
var _head: MeshInstance3D
var _magnet := false
var _expiring := false
# the stance (pass 29): "tower" stands on a tall tripod, "bunker" digs in behind sandbags with twin barrels and a
# slow traverse; params.turret {style, barrels, turn (degrees a second, pass 47)}
var _style := ""
var _barrels := 1
var _turn := TURN_DEFAULT
var _head_h := 0.85
var _look_t := 0.0
var _pitch_want := 0.0
# the model (pass 46)
var _model: Node3D
var _yaw: Node3D
var _gun: Node3D
var _barrel_nodes: Array = []   # {node, rest, muzzle}
var _kick := 0.0
var _target := -1
## shots fired (tests)
var shots := 0


func setup(b: WeaponBehavior, proto: Node3D, mesh: Mesh, mat: Material) -> void:
	owner_behavior = b
	life = b.stat("lifetime", 12.0)
	fire_rate = float(b.inst.params.get("turret_fire_rate", 0.35))
	_magnet = bool(b.inst.params.get("magnet", false))
	var tp = b.inst.params.get("turret", {})
	if tp is Dictionary:
		_style = str(tp.get("style", ""))
		_barrels = int(tp.get("barrels", 1))
		_turn = maxf(float(tp.get("turn", TURN_DEFAULT)), 1.0)
	if proto:
		_build_model(proto)
	else:
		_build_primitive(mesh, mat)
	# it opens up before the first shot, so that one leaves the muzzle at its full height
	_fire_t = POP_IN
	scale = Vector3(0.1, 0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, POP_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The model: the stance's stand shown, the others hidden, the head moved onto the stand's top, one barrel or two.
func _build_model(proto: Node3D) -> void:
	_model = proto.duplicate()
	_model.visible = true
	add_child(_model)
	var stand := "Base"
	var top := "BaseTop"
	match _style:
		"tower":
			stand = "Tripod"
			top = "TripodTop"
		"bunker":
			stand = "Sandbags"
			top = "SandbagsTop"
	for s in ["Base", "Tripod", "Sandbags"]:
		var n := _model.get_node_or_null(s) as Node3D
		if n:
			n.visible = s == stand
	_yaw = _model.get_node_or_null("Yaw") as Node3D
	var top_n := _model.get_node_or_null(top) as Node3D
	if _yaw and top_n:
		_yaw.position = top_n.position
	_gun = _yaw.get_node_or_null("Gun") as Node3D if _yaw else null
	if _gun == null:
		return
	var twin := _barrels >= 2
	for bn in ["Barrel", "BarrelL", "BarrelR"]:
		var bar := _gun.get_node_or_null(bn) as Node3D
		if bar == null:
			continue
		var used: bool = (bn != "Barrel") == twin
		bar.visible = used
		if used:
			_barrel_nodes.append({"node": bar, "rest": bar.position, "muzzle": _muzzle_of(bar)})
	if _barrel_nodes.is_empty():
		# a model with one barrel only: the bunker fires it twice
		var bar0 := _gun.get_node_or_null("Barrel") as Node3D
		if bar0:
			bar0.visible = true
			_barrel_nodes.append({"node": bar0, "rest": bar0.position, "muzzle": _muzzle_of(bar0)})
	_head_h = top_n.position.y + 0.1 if top_n else 0.85


## The barrel's Muzzle, put at the barrel's far end: the end of its mesh's long axis that points down the gun (its -Z).
## The model's own empties sat above the barrels instead of at their tips, so the tip is found from the mesh.
func _muzzle_of(bar: Node3D) -> Node3D:
	var m := bar.find_child("Muzzle*", false, false) as Node3D
	if m == null:
		m = Node3D.new()
		m.name = "Muzzle"
		bar.add_child(m)
	if bar is MeshInstance3D and (bar as MeshInstance3D).mesh:
		var box: AABB = (bar as MeshInstance3D).get_aabb()
		var c := box.get_center()
		var axis := 0
		for k in [1, 2]:
			if box.size[k] > box.size[axis]:
				axis = k
		var a := c
		var b := c
		a[axis] = box.position[axis]
		b[axis] = box.end[axis]
		# the end further down the gun's -Z
		var tip: Vector3 = a if (bar.transform * a).z < (bar.transform * b).z else b
		m.position = tip + (tip - c).normalized() * 0.02
	return m


## The primitive turret (before pass 46, and the fallback without the model): a box, or a tripod tower, or a bunker of
## sandbags with twin barrels.
func _build_primitive(mesh: Mesh, mat: Material) -> void:
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.25, 0.25, 0.3)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.34, 0.18)
	wood.roughness = 1.0
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.72, 0.6, 0.4)
	sand.roughness = 1.0
	match _style:
		"tower":
			# three legs to a platform, the gun on top: higher, further
			_head_h = 1.95
			for k in range(3):
				var a := TAU * float(k) / 3.0
				var leg := MeshInstance3D.new()
				var lm := CylinderMesh.new()
				lm.top_radius = 0.05
				lm.bottom_radius = 0.07
				lm.height = 1.9
				lm.radial_segments = 6
				leg.mesh = lm
				leg.material_override = wood
				leg.position = Vector3(cos(a) * 0.22, 0.9, sin(a) * 0.22)
				leg.rotation = Vector3(-sin(a) * 0.22, 0, cos(a) * 0.22)
				add_child(leg)
			var plat := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.42
			pm.bottom_radius = 0.42
			pm.height = 0.08
			pm.radial_segments = 8
			plat.mesh = pm
			plat.material_override = wood
			plat.position.y = 1.75
			add_child(plat)
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.36, 0.3, 0.36)
			box.mesh = bm
			box.material_override = mat if mat else hmat
			box.position.y = 1.94
			add_child(box)
			_head_h = 2.05
		"bunker":
			# a ring of sandbags, the body low inside, twin barrels
			_head_h = 0.55
			var bags := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.42
			tm.outer_radius = 0.78
			tm.rings = 16
			tm.ring_segments = 6
			bags.mesh = tm
			bags.material_override = sand
			bags.position.y = 0.16
			bags.scale = Vector3(1, 0.55, 1)
			add_child(bags)
			var body := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(0.5, 0.36, 0.5)
			body.mesh = bm2
			body.material_override = mat if mat else hmat
			body.position.y = 0.2
			add_child(body)
		_:
			var base := MeshInstance3D.new()
			base.mesh = mesh
			if mat:
				base.material_override = mat
			base.position.y = 0.35
			add_child(base)
	_head = MeshInstance3D.new()
	if _barrels >= 2:
		# two barrels side by side on one mount
		var mount := BoxMesh.new()
		mount.size = Vector3(0.42, 0.2, 0.3)
		_head.mesh = mount
		for side in [-1.0, 1.0]:
			var bar := MeshInstance3D.new()
			var bmm := BoxMesh.new()
			bmm.size = Vector3(0.12, 0.12, 0.8)
			bar.mesh = bmm
			bar.material_override = hmat
			bar.position = Vector3(side * 0.13, 0.0, -0.25)
			_head.add_child(bar)
	else:
		var hm := BoxMesh.new()
		hm.size = Vector3(0.25, 0.25, 0.7)
		_head.mesh = hm
	_head.material_override = hmat
	_head.position.y = _head_h
	add_child(_head)


func expire() -> void:
	if _expiring:
		return
	_expiring = true
	_last_stand()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.3)
	tw.tween_callback(queue_free)


## Last Stand (pass 53, params.turret.boom {radius, damage_mult, knockback}; Garry: "when a turret is supposed to despawn
## it explodes in a small explosion causing decent amount of damage"): the turret going, its time up or the oldest making
## room for a new drop, blows: `radius` metres for `damage_mult` times its shot's damage, thrown with `knockback`, a
## fireball and the lob's boom, then the shrink. A turret without the block just shrinks away as before.
func _last_stand() -> void:
	if owner_behavior == null or not is_instance_valid(owner_behavior) or owner_behavior.game == null or owner_behavior.inst == null:
		return
	var tp = owner_behavior.inst.params.get("turret", {})
	var boom = (tp as Dictionary).get("boom") if tp is Dictionary else null
	if not (boom is Dictionary):
		return
	var game: Node = owner_behavior.game
	var em: EnemyManager = game.get("enemies")
	var r: float = float((boom as Dictionary).get("radius", 3.0))
	var dmg: float = owner_behavior.stat("damage", 4.0) * float((boom as Dictionary).get("damage_mult", 4.0))
	if em:
		var before := Run.kills
		em.damage_radius(global_position, r, dmg, owner_behavior.inst.def.id, float((boom as Dictionary).get("knockback", 9.0)))
		owner_behavior.inst.kills += Run.kills - before
	var fx = game.get("fx")
	if fx and fx.has_method("explosion"):
		fx.explosion(global_position, r * 0.45)
	if game.has_method("fx_burst"):
		game.fx_burst(global_position + Vector3(0, 0.4, 0), Color(1.0, 0.62, 0.25), r * 0.6)
	Audio.play("w_lob_boom", global_position)
	booms += 1


## Last Stand blasts so far (tests).
var booms := 0


## The head's turn now (the model's Yaw, else the primitive head).
func _head_yaw() -> float:
	if _yaw:
		return _yaw.rotation.y
	return _head.rotation.y if _head else 0.0


func _set_head_yaw(y: float) -> void:
	if _yaw:
		_yaw.rotation.y = y
	elif _head:
		_head.rotation.y = y


## Where the shots leave: each barrel's muzzle (the head's height over the turret without the model).
func _muzzles() -> Array:
	var out: Array = []
	for b: Dictionary in _barrel_nodes:
		var m: Node3D = b["muzzle"]
		if is_instance_valid(m) and m.is_inside_tree():
			out.append(m.global_position)
	if out.is_empty():
		out.append(global_position + Vector3(0, _head_h, 0))
	return out


func _process(delta: float) -> void:
	if owner_behavior == null or owner_behavior.game == null or owner_behavior.game.paused:
		return
	if _expiring:
		return
	life -= delta
	if life <= 0.0:
		expire()
		return
	var game = owner_behavior.game
	if _magnet:
		game.pickups.add_attractor(global_position, 4.0)
	_tick_model(delta)
	_fire_t -= delta
	var enemies: EnemyManager = game.enemies
	var rng := owner_behavior.stat("range", 8.0)
	# the target it has, while that lives and stays in range (a head that swapped to the nearest at every shot would
	# spend its time turning), else the weapon's pick (pass 48: the strongest close one for a priority turret, else the
	# nearest), looked for every LOOK_EVERY seconds
	if not _target_ok(enemies, rng):
		_target = -1
		_look_t -= delta
		if _look_t > 0.0:
			return
		_look_t = LOOK_EVERY
		_target = owner_behavior.aim_index(global_position, rng)
		if _target < 0:
			return
	var aim_at: Vector3 = enemies.pos[_target] + Vector3(0, 0.4, 0)
	var from: Vector3 = global_position + Vector3(0, _head_h, 0)
	var dir := (aim_at - from).normalized()
	var want_yaw := atan2(-dir.x, -dir.z)
	# the head turns at its traverse (Berserk turns it faster, as it fires faster), and the gun's tilt follows
	var cur := _head_yaw()
	var step: float = deg_to_rad(_turn) * maxf(Run.haste, 1.0) * delta
	_set_head_yaw(cur + clampf(angle_difference(cur, want_yaw), -step, step))
	_pitch_want = _pitch_to(aim_at)
	if _fire_t > 0.0:
		return
	if absf(angle_difference(_head_yaw(), want_yaw)) > deg_to_rad(AIM_TOLERANCE_DEG):
		# not lined up yet: the round waits for the barrel
		return
	# Berserk: a turret's own clock runs with the hero's weapon speed
	_fire_t = fire_rate / maxf(Run.haste, 1.0)
	var speed := owner_behavior.stat("speed", 16.0)
	var pierce := owner_behavior.stat_int("pierce", 0)
	var kb := owner_behavior.stat("knockback", 0.3)
	var muzzles := _muzzles()
	var side := Vector3(-dir.z, 0, dir.x).normalized()
	for b in range(maxi(_barrels, 1)):
		var p: Vector3
		if muzzles.size() > b:
			p = muzzles[b]
		else:
			# one muzzle for two barrels (the primitive bunker): side by side
			var off: Vector3 = side * ((float(b) - float(_barrels - 1) * 0.5) * 0.26) if _barrels > 1 else Vector3.ZERO
			p = muzzles[0] + off
		# lined up within a few degrees: the round goes at the target
		var d := (aim_at - p).normalized()
		# the round keeps the height it left at (a tower's flies at the tower's height, not dropped to a man's)
		game.projectiles.fire(owner_behavior.projectile_kind, p, d * speed, owner_behavior.stat("damage", 4.0), pierce, 0.2, rng / speed, owner_behavior.inst, kb, p.y - global_position.y + 0.1)
		_shot_fx(game, p, d)
	shots += 1
	_kick = 1.0
	owner_behavior.sfx("fire", from)


## Whether the target it has is still worth turning for: alive and within `rng` (pass 47).
func _target_ok(enemies: EnemyManager, rng: float) -> bool:
	if _target < 0 or not enemies.is_alive(_target) or enemies.hidden[_target] == 1 or enemies.held[_target] == 1:
		return false
	var d: Vector3 = enemies.pos[_target] - global_position
	d.y = 0.0
	return d.length_squared() <= rng * rng


## The tilt the gun wants for a target at `at`: up or down at it, a little.
func _pitch_to(at: Vector3) -> float:
	var p: Vector3 = _gun.global_position if _gun and _gun.is_inside_tree() else global_position + Vector3(0, _head_h, 0)
	var flat := Vector2(at.x - p.x, at.z - p.z).length()
	return clampf(atan2(at.y - p.y, maxf(flat, 0.1)), -0.5, 0.35)


## The creature it is turning to or shooting at (-1 for none). Tests read it.
func target() -> int:
	return _target


## How far off its target the barrel points, in degrees (pass 47; -1 with no target). Tests read it.
func aim_error() -> float:
	var enemies = owner_behavior.game.enemies if owner_behavior and owner_behavior.game else null
	if enemies == null or _target < 0 or not enemies.is_alive(_target):
		return -1.0
	var to: Vector3 = enemies.pos[_target] - global_position
	return rad_to_deg(absf(angle_difference(_head_yaw(), atan2(-to.x, -to.z))))


## The head's traverse in degrees a second (pass 47: params.turret.turn, TURN_DEFAULT without one).
func turn_rate() -> float:
	return _turn


## A shot from `at` along `dir`: a flash and a white-hot pop at the muzzle, a smoke puff drifting up off it, a casing
## out of the right side.
func _shot_fx(game: Node, at: Vector3, dir: Vector3) -> void:
	var fx = game.get("fx")
	if fx == null:
		return
	fx.burst(at + dir * 0.08, Color(1.0, 0.82, 0.4), 0.32)
	if fx.has_method("mote"):
		fx.mote(at + dir * 0.2, dir * 1.4 + Vector3(0, 0.7, 0), 0.55, 0.32, Color(0.62, 0.6, 0.57, 0.55))
	if fx.has_method("shell"):
		var right := Vector3(-dir.z, 0, dir.x).normalized()
		fx.shell(at - dir * 0.35, -right)


## Every frame: the barrels ease home from their kick, and the gun's tilt eases to its target's (the head's turn is
## _process's, pass 47).
func _tick_model(delta: float) -> void:
	if _kick > 0.0:
		_kick = maxf(_kick - delta * KICK_RETURN, 0.0)
	var back := _kick * _kick * (3.0 - 2.0 * _kick)
	for b: Dictionary in _barrel_nodes:
		var n: Node3D = b["node"]
		# back along the gun's +Z, the way a barrel recoils
		n.position = (b["rest"] as Vector3) + Vector3(0, 0, KICK * back)
	var tilt: Node3D = _gun if _gun else (_head if _model == null else null)
	if tilt:
		tilt.rotation.x = lerpf(tilt.rotation.x, _pitch_want, clampf(delta * PITCH_EASE, 0.0, 1.0))
