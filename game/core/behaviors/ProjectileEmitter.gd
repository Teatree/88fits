## Fires projectiles. Targeting: nearest, random, or forward cone (Boomstick style). Every mode auto-aims: a forward
## weapon points its cone at the nearest enemy in range and fires nothing when nothing is near (pass 53, Garry: "Boomstick
## seems to be firing all the time, this should only happen after it's Evolved"), unless `params.fire_blind` says it
## blasts on its clock whoever is there (the Blunderbuss).
## The visual scene may carry a "Held" node (a gun at the hero's hip, forward weapons) or a "Familiar" node
## (a little companion that circles the hero and fires from where it is; child nodes "WingL"/"WingR" flap).
## Familiar tuning is data: params.familiar = {"radius": 1.25, "height": 1.35, "speed": 1.4, "bob": 0.12}.
## A burst (params.burst) leaves a round every `burst_gap` seconds (0.05), each scattered up to `scatter_deg` (else the
## volley's spread, at least 5 degrees); the companion's "Drum" turns `drum_step` radians a round about its sideways
## axis, or about the barrel with `drum_axis` "forward" (the Revolver's cylinder, pass 35); `no_shells` keeps the casings
## in (a revolver). A volley fans its shots `fan_step_deg` (8) apart (pass 46: the Spear Volley's three spread wider); a
## shot's own params (`no_spin`, `plant`, `pin`, `trail_zone`: the Spear) are the ProjectileManager's.
## A weapon with `params.aura` (pass 53: the Tumbleweed's Dust Wake, the Dust Devil) draws the visual's "Ring" node under
## every one of its shots in flight, laid on the ground at the aura's radius and turning (_tick_rings); the slow itself
## is the ProjectileManager's.
## Pass 48: "priority" targeting aims at the strong and the close (WeaponBehavior.aim_index) on every aim: the pull, the
## gun tracking between shots, the companion's own line and every round of a burst. `params.blast` (Birdshot's lane, the
## Blunderbuss's cone) hits everything in its shape at once (_blast) with pellets streaking through it only for the eye;
## `double_every` fires that pull twice: the second barrel `double_gap` seconds after the first (pass 51), aimed afresh
## with its own flash, kick and bang (both at once read as one bigger shot). `size_mult`/`radius_mult` make the shot bigger and its hit wider (Big Peas, the
## Silver Bullet), `speed_mult` faster; `tint {albedo, emission, energy}` (pass 54, Thorny Weed) draws the shots in a
## copy of the visual's kind in those colours (tint_kind); `silver` turns the rounds, their tracer and the muzzle flash pale blue with a
## harder kick and a small camera kick a shot. `hip_shot {every, volleys, gap}`: every `every`th pull fires `volleys`
## volleys `gap` seconds apart, each the whole amount at once, and then the companion twirls a full turn.
class_name ProjectileEmitter
extends WeaponBehavior

## The pale gold a blast's lane or cone washes the sand with (pass 48).
const BLAST_WASH := Color(1.0, 0.93, 0.68)
## Seconds the companion's twirl after a hip shot takes, and how hard a silver round kicks.
const HIP_SPIN := 0.35
const SILVER_RECOIL := 1.7
const SILVER_SHAKE := 0.12

var _held: Node3D
var _familiar: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _drum: Node3D          # a drum magazine on the companion gun turns a notch per round
var _recoil := 0.0
var _aim_yaw := 0.0
var _aim_dir := Vector3.ZERO
var _orbit := 0.0
var _flap := 0.0
# params.burst: the shots of one trigger pull leave one after another (a submachine gun) instead of all at once
var _burst: Array = []   # pending shots: {from, dir, speed, damage, pierce, prad, life, knock, spread}
var _burst_t := 0.0
var _shots := 0          # trigger pulls, for Both Barrels (every Nth fires twice) and Hip Shot (every Nth)
## Both Barrels (pass 51, Garry: "it's actual 2 shots in quick succession"): seconds until the second barrel of a pull
## that fires twice (-1: none waiting), DOUBLE_GAP unless params.double_gap says otherwise; and how many have gone (tests)
const DOUBLE_GAP := 0.15
var _barrel_t := -1.0
var second_barrels := 0
var _taps := 0           # Fan the Hammer: extra volleys still to fire after this one
var _tap_t := 0.0
var _tap_mult := 1.0
# Hip Shot (pass 48): volleys still to fire, the clock to the next, their gap; the twirl's clock (< 0: none)
var _hip_left := 0
var _hip_t := 0.0
var _hip_gap := 0.12
var _spin_t := -1.0
# the Silver Bullet's pale blue rounds (a kind of their own, made the first time) and muzzle flash
var _silver_kind := -1
var _muzzle_silver := false
## Diagnostics and tests (pass 48): blasts fired, hip-shot volleys fired.
var blasts := 0
var hip_volleys := 0
## The dust ring under every live shot of a weapon with an aura (pass 53, Garry on the Tumbleweed's Dust Wake: "each
## Tumbleweed has a small aura around it ... the area of effect is not huge"): the visual's "Ring" node (its merged dashes)
## drawn once per shot by one MultiMesh, flat on the sand at `params.aura.radius`, turning RING_SPIN radians a second.
const RING_MAX := 64
const RING_SPIN := 2.2
var _ring_mm: MultiMesh
var _ring_spin := 0.0


## The tracked creature between shots (pass 48): picked every TRACK_EVERY seconds, the gun turning to it in between.
const TRACK_EVERY := 0.1
var _track_i := -1
var _track_cd := 0.0

func _shows_held() -> bool:
	return inst.def.targeting == "forward"


func _on_setup() -> void:
	_held = visual.get_node_or_null("Held")
	_familiar = visual.get_node_or_null("Familiar")
	if _familiar:
		_wing_l = _familiar.get_node_or_null("WingL")
		_wing_r = _familiar.get_node_or_null("WingR")
		_drum = _familiar.find_child("Drum", true, false)
		_orbit = randf() * TAU
		_place_familiar(0.0)
	_setup_ring()


## The ring under the shots (pass 53): one MultiMesh of the visual's "Ring" mesh, for a weapon whose params carry an `aura`;
## the node itself is never shown.
func _setup_ring() -> void:
	var ring := visual.get_node_or_null("Ring") as Node3D
	if ring == null:
		return
	ring.visible = false
	if not (inst.params.get("aura") is Dictionary):
		return
	var src: MeshInstance3D = null
	for c in ring.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).mesh:
			src = c
			break
	if src == null:
		return
	_ring_mm = MultiMesh.new()
	_ring_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ring_mm.mesh = src.mesh
	_ring_mm.instance_count = RING_MAX
	_ring_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _ring_mm
	mmi.material_override = src.material_override if src.material_override else src.mesh.surface_get_material(0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.top_level = true
	mmi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(mmi)


## Every live shot of this weapon (never a blast's ghost pellets) gets a ring on the ground under it, all turning together.
func _tick_rings(delta: float) -> void:
	if _ring_mm == null:
		return
	_ring_spin = fmod(_ring_spin + delta * RING_SPIN, TAU)
	var pm: ProjectileManager = game.projectiles
	var aura = inst.params.get("aura", {})
	var r: float = float((aura as Dictionary).get("radius", 1.0)) if aura is Dictionary else 1.0
	var basis := Basis(Vector3.UP, _ring_spin).scaled(Vector3(r, 1.0, r))
	var map = game.get("map")
	var n := 0
	for j in range(ProjectileManager.MAX):
		if n >= RING_MAX:
			break
		if pm.alive[j] == 0 or pm.weapon[j] != inst:
			continue
		var ex = pm.extra[j]
		if ex is Dictionary and (ex as Dictionary).has("ghost"):
			continue
		var p: Vector3 = pm.pos[j]
		var g: float = map.height_at(p.x, p.z) if map != null else p.y - 0.5
		_ring_mm.set_instance_transform(n, Transform3D(basis, Vector3(p.x, g + 0.06, p.z)))
		n += 1
	_ring_mm.visible_instance_count = n


## How many rings are drawn right now (tests).
func ring_count() -> int:
	return _ring_mm.visible_instance_count if _ring_mm else 0


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


## The shots' speed: the sheet's, times `speed_mult` (pass 48, the Silver Bullet's, never written on a card).
func _speed() -> float:
	return stat("speed", 14.0) * float(inst.params.get("speed_mult", 1.0))


## How wide a shot hits: params.radius, times `radius_mult` (pass 48: Big Peas, the Silver Bullet, the Pea Cannon).
func _prad() -> float:
	return float(inst.params.get("radius", 0.25)) * float(inst.params.get("radius_mult", 1.0))


func _silver() -> bool:
	return bool(inst.params.get("silver", false))


## The kind a shot is drawn with: the visual's, the Silver Bullet's pale blue copy of it, or (pass 54) a copy in a
## mutation's own colours (`params.tint`, tint_kind: Thorny Weed's darker weed).
func _kind() -> int:
	if not _silver():
		var tint = inst.params.get("tint")
		if tint is Dictionary:
			return tint_kind(tint)
		return projectile_kind
	if _silver_kind < 0:
		var pm: ProjectileManager = game.projectiles
		if projectile_kind < 0 or projectile_kind >= pm.kinds.size():
			return projectile_kind
		var kd: Dictionary = pm.kinds[projectile_kind]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.86, 0.94, 1.0)
		mat.emission_enabled = true
		mat.emission = ProjectileManager.SILVER
		mat.emission_energy_multiplier = 2.2
		_silver_kind = pm.register_kind((kd["mm"] as MultiMesh).mesh, mat, float(kd["scale"]) / ProjectileManager.CHUNK)
	return _silver_kind


## A copy of the visual's kind in its own colours (pass 54, `params.tint {albedo, emission, energy}`: Thorny Weed's
## darker brown with pale warm tips): the shot's material duplicated with that albedo and a glow of `emission` at
## `energy`, registered the first time and kept by the tint's words, so a mutation picked later gets its own copy.
var _tint_kinds := {}


func tint_kind(tint: Dictionary) -> int:
	var key := str(tint)
	if _tint_kinds.has(key):
		return int(_tint_kinds[key])
	var pm: ProjectileManager = game.projectiles
	if projectile_kind < 0 or projectile_kind >= pm.kinds.size():
		return projectile_kind
	var kd: Dictionary = pm.kinds[projectile_kind]
	var mesh: Mesh = (kd["mm"] as MultiMesh).mesh
	var src: Material = (kd["mmi"] as MultiMeshInstance3D).material_override if kd.has("mmi") else null
	if src == null and mesh and mesh.get_surface_count() > 0:
		src = mesh.surface_get_material(0)
	var mat: StandardMaterial3D = (src.duplicate() as StandardMaterial3D) if src is StandardMaterial3D else StandardMaterial3D.new()
	if tint.has("albedo"):
		mat.albedo_color = Color(str(tint["albedo"]))
	if tint.has("emission"):
		mat.emission_enabled = true
		mat.emission = Color(str(tint["emission"]))
		mat.emission_energy_multiplier = float(tint.get("energy", 0.35))
	var basis: Basis = kd.get("basis", Basis())
	var k: int
	if pm.get_method_argument_count("register_kind") >= 5:
		k = pm.register_kind(mesh, mat, float(kd["scale"]) / ProjectileManager.CHUNK, false, basis)
	else:
		k = pm.register_kind(mesh, mat, float(kd["scale"]) / ProjectileManager.CHUNK)
	_tint_kinds[key] = k
	return k


## A round leaves: the companion kicks back (harder for a silver round, with a small camera kick), and the muzzle flash
## takes the round's colour.
func _kick() -> void:
	var silver := _silver()
	_recoil = SILVER_RECOIL if silver else 1.0
	if silver:
		var cam = game.get("camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(SILVER_SHAKE)
		# a silver round rings over the gun's own shot (pass 48)
		if _familiar:
			Audio.play("w_silver_fire", _familiar.global_position)
	if silver != _muzzle_silver:
		_muzzle_silver = silver
		var m := visual.get_node_or_null("Muzzle") as GeometryInstance3D
		if m:
			if silver:
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = ProjectileManager.SILVER
				mat.emission_enabled = true
				mat.emission = ProjectileManager.SILVER
				mat.emission_energy_multiplier = 2.2
				m.material_override = mat
			else:
				m.material_override = null


func _place_familiar(delta: float) -> void:
	var r := _familiar_param("radius", 1.25)
	var h := _familiar_param("height", 1.35)
	var bob := _familiar_param("bob", 0.12)
	_orbit += delta * _familiar_param("speed", 1.4)
	var t := float(Time.get_ticks_msec()) * 0.001
	var want := player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 3.1) * bob, sin(_orbit) * r)
	# recoil: the gun jumps back along its own barrel and the muzzle climbs, then settles
	var aim := Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))
	want -= aim * 0.1 * _recoil
	# eased follow, so a sprinting hero drags the companion behind him a little
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	_familiar.rotation.y = _aim_yaw
	# a hip shot's twirl (pass 48): one full turn over the trigger guard, quick out and easing in
	var twirl := 0.0
	if _spin_t >= 0.0:
		var f: float = clampf(_spin_t / HIP_SPIN, 0.0, 1.0)
		twirl = TAU * (1.0 - (1.0 - f) * (1.0 - f))
	_familiar.rotation.x = -0.28 * _recoil - twirl
	# params.familiar.roll lays a flat gun on its side, so the camera overhead sees its profile (the Revolver)
	_familiar.rotation.z = sin(t * 2.3) * 0.08 + _familiar_param("roll", 0.0)
	_flap += delta * 20.0
	var wing := 0.35 + absf(sin(_flap)) * 0.55
	if _wing_l:
		_wing_l.rotation.z = wing
	if _wing_r:
		_wing_r.rotation.z = -wing


## Whether the companion is twirling after a hip shot.
func spinning() -> bool:
	return _spin_t >= 0.0


func _fire_burst_shot() -> void:
	if _burst.is_empty():
		return
	var b: Dictionary = _burst.pop_front()
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	if _familiar:
		# every round aims from where the companion is now (pass 35: it circles a metre off the hero, and the hero's line
		# to the target sent a tight round, the Revolver's, a metre wide of it)
		dir = _from_familiar(dir)
	# Sweep Fire: the rounds walk across a fan instead of scattering
	var d: Vector3 = dir.rotated(Vector3.UP, float(b["angle"])) if b.has("angle") else dir.rotated(Vector3.UP, randf_range(-float(b["spread"]), float(b["spread"])))
	var from: Vector3 = (_familiar.global_position + dir * 0.45) if _familiar else player.aim_origin(dir)
	game.projectiles.fire(_kind(), from, d * float(b["speed"]), float(b["damage"]), int(b["pierce"]), float(b["prad"]), float(b["life"]), inst, float(b["knock"]))
	if _familiar:
		# every round: a kick, the drum turns a notch, a casing flies out to the right
		_kick()
		_turn_drum()
		if not bool(inst.params.get("no_shells", false)):
			game.fx.shell(_familiar.global_position + Vector3(0, 0.05, 0), dir.rotated(Vector3.UP, -PI * 0.5))
	muzzle_flash(from)


## The companion's drum turns a notch: a drum magazine about the axis running sideways through the gun, a revolver's
## cylinder about the barrel.
func _turn_drum() -> void:
	if _drum:
		var axis := Vector3.FORWARD if str(inst.params.get("drum_axis", "")) == "forward" else Vector3.RIGHT
		_drum.rotate_object_local(axis, float(inst.params.get("drum_step", 0.5)))


func _tick(_delta: float) -> void:
	_tick_rings(_delta)
	if not _burst.is_empty():
		_burst_t -= _delta
		if _burst_t <= 0.0:
			_burst_t = float(inst.params.get("burst_gap", 0.05))
			_fire_burst_shot()
	if _barrel_t >= 0.0:
		_barrel_t -= _delta
		if _barrel_t < 0.0:
			_second_barrel()
	if _taps > 0:
		_tap_t -= _delta
		if _tap_t <= 0.0:
			_taps -= 1
			_tap_t = 0.09
			_volley(_tap_mult)
	if _hip_left > 0:
		_hip_t -= _delta
		if _hip_t <= 0.0:
			_hip_volley()
	if _spin_t >= 0.0:
		_spin_t += _delta
		if _spin_t >= HIP_SPIN:
			_spin_t = -1.0
	if (_held and _held.visible) or _familiar:
		# the held gun (or the companion) tracks its target between shots, so it points where the shots go: the nearest,
		# or the strong and the close for a priority weapon (pass 48)
		var enemies: EnemyManager = game.enemies
		var hero := player.global_position
		# the creature the gun tracks is picked again ten times a second, not every frame (pass 48: a priority aim weighs
		# most of the crowd, and every gun asked every frame), and dropped at once when it falls
		_track_cd -= _delta
		if _track_cd <= 0.0 or _track_i < 0 or enemies.alive[_track_i] == 0 or enemies.state[_track_i] == EnemyManager.STATE_DYING:
			_track_cd = TRACK_EVERY
			if inst.def.targeting == "healthy":
				_track_i = enemies.nearest_index(hero, stat("range", 9.0), inst.element())
				if _track_i < 0:
					_track_i = enemies.nearest_index(hero, stat("range", 9.0))
			else:
				_track_i = aim_index(hero, stat("range", 9.0))
		var t := _track_i
		var want: Vector3 = (enemies.pos[t] - hero) if t >= 0 else player.forward()
		want.y = 0.0
		if want.length_squared() > 0.0001:
			_aim_yaw = lerp_angle(_aim_yaw, atan2(-want.x, -want.z), clampf(_delta * 12.0, 0.0, 1.0))
	if _held and _held.visible:
		_held.global_position = player.hip.global_position
		_held.rotation.y = _aim_yaw
		# small recoil settle
		_held.scale = _held.scale.lerp(Vector3.ONE, _delta * 10.0)
	if _familiar:
		_recoil = maxf(_recoil - _delta * 9.0, 0.0)
		_place_familiar(_delta)
		_familiar.scale = _familiar.scale.lerp(Vector3.ONE, _delta * 10.0)


## The way from the companion to creature `t` (the gun's own line of fire), else to the one it would aim at now
## (aim_index: the nearest, or the strong and the close), else `fallback`.
func _from_familiar(fallback: Vector3, t: int = -1) -> Vector3:
	var em: EnemyManager = game.enemies
	if t < 0 or t >= EnemyManager.MAX or em.alive[t] == 0:
		t = aim_index(player.global_position, stat("range", 9.0))
	if t < 0:
		return fallback
	var to: Vector3 = em.pos[t] - _familiar.global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.01 else fallback


## Half the fan a volley of `amount` spreads over: params.fan_step_deg between neighbouring shots, 8 by default (pass 46:
## the Spear Volley fans its three wider).
func _fan_half(amount: int) -> float:
	return deg_to_rad(float(inst.params.get("fan_step_deg", 8.0))) * 0.5 * float(maxi(amount - 1, 0))


## One fan of `amount` shots along `dir` from `from`.
func _volley_at(dir: Vector3, from: Vector3, amount: int, damage: float, speed: float, pierce: int, prad: float, life: float, knock: float, half_spread: float) -> void:
	var k_draw := _kind()
	for k in range(amount):
		var a := 0.0
		if amount > 1:
			a = lerp(-half_spread, half_spread, float(k) / float(amount - 1))
		var d := dir.rotated(Vector3.UP, a)
		game.projectiles.fire(k_draw, from, d * speed, damage, pierce, prad, life, inst, knock)


## Both Barrels (pass 51): when this pull is one that fires twice (every `double_every`th), the second barrel is armed to
## go `double_gap` seconds from now (DOUBLE_GAP).
func _arm_second_barrel() -> void:
	var de := int(inst.params.get("double_every", 0))
	if de <= 0 or _shots % de != 0:
		return
	if _barrel_t >= 0.0:
		# the last pull's second barrel has not gone yet (pulls closer than the gap): it goes now, never lost
		_barrel_t = -1.0
		_second_barrel()
	_barrel_t = maxf(float(inst.params.get("double_gap", DOUBLE_GAP)), 0.02)


## The second barrel (Both Barrels, pass 51): the pull once more, aimed afresh at what the gun points at now. A lane or a
## cone blasts again (its own wash and pellets), a volley flies again; a kick of the held gun, a flash, a bang.
func _second_barrel() -> void:
	second_barrels += 1
	if _held:
		_held.scale = Vector3(1.0, 1.0, 0.7)
	var bl := inst.blast()
	if bl.is_empty():
		_volley(1.0)
		return
	var hero := player.global_position
	var t := aim_index(hero, float(bl["range"]))
	var dir: Vector3 = (game.enemies.pos[t] - hero) if t >= 0 else _aim_dir
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else player.forward()
	_aim_dir = dir
	_aim_yaw = atan2(-dir.x, -dir.z)
	_blast(bl, dir, stat("damage", 5.0), maxi(stat_int("amount", 1), 1), stat("knockback", 0.0), _speed())
	var from: Vector3 = player.aim_origin(dir)
	muzzle_flash(from)
	sfx("fire", from)


## A repeat of the last volley at the current aim (Fan the Hammer), scaled.
func _volley(mult: float) -> void:
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	var from: Vector3 = (_familiar.global_position + dir * 0.45) if _familiar else player.aim_origin(dir)
	var amount: int = max(stat_int("amount", 1), 1)
	var speed := _speed()
	var half_spread := _fan_half(amount)
	if inst.def.targeting == "forward":
		half_spread = deg_to_rad(stat("spread_deg", 30.0)) * 0.5
	_volley_at(dir, from, amount, stat("damage", 5.0) * mult, speed, stat_int("pierce", 0), _prad(), stat("range", 9.0) / maxf(speed, 1.0), stat("knockback", 0.0), half_spread)
	muzzle_flash(from)
	sfx("fire", from)


## One volley of a hip shot (pass 48): every round of the amount at once, from the companion (or the hip) along a fresh
## aim, in half the volley's fan; a kick, the cylinder turns, the shot is heard. The last volley sets the companion
## twirling (HIP_SPIN).
func _hip_volley() -> void:
	_hip_left -= 1
	_hip_t = _hip_gap
	var dir: Vector3 = _aim_dir if _aim_dir.length_squared() > 0.0001 else player.forward()
	if _familiar:
		dir = _from_familiar(dir)
	var from: Vector3 = (_familiar.global_position + dir * 0.45) if _familiar else player.aim_origin(dir)
	var amount: int = maxi(stat_int("amount", 1), 1)
	var speed := _speed()
	_volley_at(dir, from, amount, stat("damage", 5.0), speed, stat_int("pierce", 0), _prad(), stat("range", 9.0) / maxf(speed, 1.0), stat("knockback", 0.0), _fan_half(amount) * 0.5)
	hip_volleys += 1
	if _familiar:
		_kick()
		_turn_drum()
	muzzle_flash(from)
	sfx("fire", from)
	if _hip_left <= 0:
		_spin_t = 0.0
		# the twirl is heard (pass 48)
		Audio.play("w_hip_spin", from)


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var amount: int = max(stat_int("amount", 1), 1)
	var speed := _speed()
	var range_m := stat("range", 9.0)
	var damage := stat("damage", 5.0)
	var pierce := stat_int("pierce", 0)
	var knock := stat("knockback", 0.0)
	var prad := _prad()
	var bl := inst.blast()
	var hero := player.global_position
	var dir := Vector3.ZERO
	var half_spread := 0.0
	var target := -1
	match inst.def.targeting:
		"forward":
			# a lane or a cone (pass 48) aims at what is within its own reach
			target = aim_index(hero, float(bl["range"]) if not bl.is_empty() else range_m)
			if target < 0 and not bool(inst.params.get("fire_blind", false)):
				# nobody in reach (pass 53, Garry: "Boomstick seems to be firing all the time, this should only happen after
				# it's Evolved"): no shot, no kick, no flash, no bang; the Blunderbuss's `fire_blind` keeps it blasting on its
				# clock along the facing
				return false
			dir = (enemies.pos[target] - hero) if target >= 0 else player.forward()
			half_spread = deg_to_rad(stat("spread_deg", 30.0)) * 0.5
			if _held:
				_held.scale = Vector3(1.0, 1.0, 0.7)
		"random":
			target = enemies.random_in_range(hero, range_m)
			if target < 0:
				return false
			dir = (enemies.pos[target] - hero)
			half_spread = _fan_half(amount)
		"healthy":
			# the nearest creature not carrying this weapon's element yet; when everyone does, the nearest one
			target = enemies.nearest_index(hero, range_m, inst.element())
			if target < 0:
				target = enemies.nearest_index(hero, range_m)
			if target < 0:
				return false
			dir = (enemies.pos[target] - hero)
			half_spread = _fan_half(amount)
		_:
			# the nearest, or (pass 48, "priority") the strong and the close
			target = aim_index(hero, range_m)
			if target < 0:
				return false
			dir = (enemies.pos[target] - hero)
			half_spread = _fan_half(amount)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = player.forward()
	dir = dir.normalized()
	_aim_dir = dir
	_aim_yaw = atan2(-dir.x, -dir.z)
	var from: Vector3 = player.aim_origin(dir)
	if _familiar:
		# shots leave the companion's mouth, wherever it is circling right now, aimed from there
		if inst.def.targeting != "random":
			dir = _from_familiar(dir, target)
			_aim_dir = dir
		from = _familiar.global_position + dir * 0.45
		_familiar.scale = Vector3(1.18, 0.86, 1.18)
	var life := range_m / maxf(speed, 1.0)
	_shots += 1
	# Drum Roll: the burst grows with Buck's momentum
	var mr := int(inst.params.get("momentum_rounds", 0))
	if mr > 0:
		amount += int(floor(Run.momentum * float(mr) + 0.0001))
	if not bl.is_empty():
		# Birdshot's lane, the Blunderbuss's cone (pass 48): all of it at once; Both Barrels fires the pull again a beat later
		_blast(bl, dir, damage, amount, knock, speed)
		_arm_second_barrel()
		muzzle_flash(from)
		sfx("fire", from)
		return true
	var hs = inst.params.get("hip_shot")
	if hs is Dictionary and int((hs as Dictionary).get("every", 0)) > 0 and _shots % int(hs["every"]) == 0:
		# Hip Shot (pass 48): this pull is `volleys` volleys `gap` apart, each the whole amount at once
		_burst.clear()
		_hip_left = maxi(int((hs as Dictionary).get("volleys", 3)), 1)
		_hip_gap = maxf(float((hs as Dictionary).get("gap", 0.12)), 0.02)
		_hip_volley()
		return true
	if bool(inst.params.get("burst", false)):
		# a burst: one shot now, the rest every 50 ms from wherever the gun is by then, each with its own scatter
		_burst.clear()
		var sweep := deg_to_rad(float(inst.params.get("sweep_deg", 0.0)))
		var scatter: float = deg_to_rad(float(inst.params["scatter_deg"])) if inst.params.has("scatter_deg") else maxf(half_spread, deg_to_rad(5.0))
		for k in range(amount):
			var shot := {"speed": speed, "damage": damage, "pierce": pierce, "prad": prad, "life": life, "knock": knock, "spread": scatter}
			if sweep > 0.0 and amount > 1:
				shot["angle"] = lerpf(-sweep * 0.5, sweep * 0.5, float(k) / float(amount - 1))
			_burst.append(shot)
		_burst_t = 0.0
		_fire_burst_shot()
	else:
		_volley_at(dir, from, amount, damage, speed, pierce, prad, life, knock, half_spread)
		# Both Barrels: every Nth pull fires the volley again a beat later; Fan the Hammer: extra volleys a beat apart, a
		# little weaker
		_arm_second_barrel()
		var dt = inst.params.get("double_tap")
		if dt is Dictionary:
			_taps = maxi(int(dt.get("count", 2)) - 1, 0)
			_tap_t = 0.09
			_tap_mult = float(dt.get("damage_mult", 0.75))
	if bool(inst.params.get("shockwave", false)):
		enemies.damage_radius(player.global_position, 1.8, damage * 0.5, inst.def.id, knock)
		game.telegraphs.flash_ring(player.global_position, 1.8, Color(1.0, 0.7, 0.3))
	muzzle_flash(from)
	sfx("fire", from)
	return true


## Pass 48, `params.blast` (Birdshot's lane, the Blunderbuss's cone; WeaponInstance.blast reads it): no pellet does the
## work. Every creature in the lane (`width` wide, `range` long ahead of the hero) or the cone (`deg` wide, `range` deep)
## takes `frac` of a full point-blank volley (damage x amount) at once, is set alight or poisoned by the weapon's element,
## and is thrown along the lane (out from the hero in a cone). Pellets streak through it for the eye (ghost shots, which
## hit nothing) and a pale wash marks it on the sand. Returns how many it hit.
func _blast(bl: Dictionary, dir: Vector3, damage: float, amount: int, knock: float, speed: float) -> int:
	var em: EnemyManager = game.enemies
	var hero := player.global_position
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	var per: float = float(bl["frac"]) * damage * float(amount)
	var wid: String = inst.def.id
	var cone: bool = str(bl["shape"]) == "cone"
	var hit := blast_targets(bl, hero, d)
	for e in hit:
		var kdir := d
		if cone:
			var out := Vector3(em.pos[e].x - hero.x, 0.0, em.pos[e].z - hero.z)
			if out.length_squared() > 0.0001:
				kdir = out.normalized()
		if inst.stat("fire_damage", 0.0) > 0.0:
			em.ignite(e, wid, inst.stat("fire_damage", 4.0), inst.stat("fire_duration", 1.8), inst.stat("fire_spread", 0.5))
		if inst.stat("poison_damage", 0.0) > 0.0:
			game.projectiles.weapon_poison(e, inst)
		var at: Vector3 = em.pos[e] + Vector3(0, 0.6, 0)
		if em.damage(e, per, wid, kdir, knock):
			inst.kills += 1
		game.fx_hit(at, inst.def)
	_blast_show(bl, hero, d, amount, speed)
	blasts += 1
	return hit.size()


## The creatures a blast from `origin` along `d` covers: in the cone (EnemyManager.indices_in_cone), or with their middle
## inside the lane's rectangle.
func blast_targets(bl: Dictionary, origin: Vector3, d: Vector3) -> PackedInt32Array:
	var em: EnemyManager = game.enemies
	var r := float(bl["range"])
	if str(bl["shape"]) == "cone":
		return em.indices_in_cone(origin, d, r, float(bl["deg"]) * 0.5)
	var half := float(bl["width"]) * 0.5
	var out := PackedInt32Array()
	for e in em.indices_in_radius(origin + d * r * 0.5, r * 0.5 + half + 0.5):
		var v := Vector3(em.pos[e].x - origin.x, 0.0, em.pos[e].z - origin.z)
		var along := v.dot(d)
		if along < 0.0 or along > r:
			continue
		if (v - d * along).length() > half:
			continue
		out.append(e)
	return out


## What a blast looks like: the wash on the sand (a pale line for 0.15 s down a lane, a pale sweep over a cone) and the
## pellets streaking through it (ghost shots of the weapon's own kind, fast, gone at its end).
func _blast_show(bl: Dictionary, hero: Vector3, d: Vector3, amount: int, speed: float) -> void:
	var r := float(bl["range"])
	var g: float = game.map.height_at(hero.x, hero.z) if game.map else hero.y
	var ground := Vector3(hero.x, g, hero.z)
	var cone: bool = str(bl["shape"]) == "cone"
	var tg = game.get("telegraphs")
	if tg:
		if cone:
			tg.wash(ground, d, r, float(bl["deg"]), 0.3, BLAST_WASH, 0.32)
		else:
			tg.line(ground, d, r, 0.15, BLAST_WASH, float(bl["width"]))
	var pm: ProjectileManager = game.projectiles
	var n: int = clampi(amount, 3, 14)
	var spd: float = maxf(speed * 2.2, 30.0)
	var start: Vector3 = player.aim_origin(d)
	var side := d.cross(Vector3.UP).normalized()
	for k in range(n):
		var f: float = (float(k) + randf()) / float(n)
		var dd := d
		var from := start
		if cone:
			dd = d.rotated(Vector3.UP, deg_to_rad(lerpf(-0.5, 0.5, f) * float(bl["deg"])))
		else:
			from = start + side * lerpf(-0.45, 0.45, f) * float(bl["width"])
		var j := pm.fire(projectile_kind, from, dd * spd, 0.0, 0, 0.0, r / spd * randf_range(0.85, 1.0), inst, 0.0)
		if j >= 0:
			pm.extra[j]["ghost"] = true
