## A continuous beam. Every `cooldown` the mouth opens, locks onto the nearest creature and pours a line of light
## through it for `duration`: everything standing in the line takes `damage` every `beam.tick` seconds, whatever the
## crowd behind it. `params.beam`: width, tick, arch_deg (Sweep pans the line as it burns), color, width_mult,
## first_knock (Bad Breath throws whatever the beam first touches). The visual scene's "Familiar" is where the mouth
## floats; the mouth is a 3D model there (pass 34, tools/blender_mouth.py: Familiar/Mouth with a Jaw), else the painted
## two-frame sprite of pass 33.2 (tools/gen_mouth.py), and the beam is one camera-facing ribbon (core/shaders/laser_beam) from
## the lips along its own axis. The 3D mouth it replaced was a torus that read as a red doughnut, and its beam boxes
## were stretched along the world's axes, so any beam not aimed north was drawn off to one side of the mouth.
class_name LaserBeam
extends WeaponBehavior

var _familiar: Node3D
## the 3D mouth (pass 34): the visual scene's Familiar/Mouth, lips on a `Jaw` that opens while the beam pours
var _model: Node3D
var _jaw: Node3D
var _open := 0.0
var _model_scale := 1.0
var _face_yaw := 0.0
var _mouth: BillboardSprite
var _mouth_open := false
var _orbit := 0.0
var _aim_yaw := 0.0
var _beam_t := 0.0
var _tick_t := 0.0
var _yaw0 := 0.0
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _hit_once: Dictionary = {}
const MOUTH_STRIP := "res://content/weapons/big_mouth/big_mouth_sprite.png"


func _beam_param(key: String, default: float) -> float:
	var b = inst.params.get("beam", {})
	return float(b.get(key, default)) if b is Dictionary else default


func _beam_flag(key: String) -> bool:
	var b = inst.params.get("beam", {})
	return bool(b.get(key, false)) if b is Dictionary else false


func _beam_colour() -> Color:
	var b = inst.params.get("beam", {})
	var c = b.get("color") if b is Dictionary else null
	if c is Array and (c as Array).size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return Color(1.0, 0.25, 0.7)


func _on_setup() -> void:
	_familiar = visual.get_node_or_null("Familiar")
	if _familiar == null:
		_familiar = Node3D.new()
		_familiar.name = "Familiar"
		visual.add_child(_familiar)
	# the mouth is a 3D model when the visual scene has one (pass 34: Familiar/Mouth, tools/blender_mouth.py), like the
	# other familiars; the painted two-frame mouth stays as the fallback
	_model = _familiar.get_node_or_null("Mouth")
	if _model:
		_jaw = _model.find_child("Jaw", true, false)
		_model_scale = _model.scale.x
	# the painted mouth: a two-frame strip (shut, open), standing on its feet, so it hangs half its height down to put
	# the lips on the familiar's point
	elif ResourceLoader.exists(MOUTH_STRIP):
		var h := _familiar_param("size", 1.15)
		_mouth = BillboardSprite.new()
		_familiar.add_child(_mouth)
		_mouth.setup(load(MOUTH_STRIP), {"idle": 1, "open": 1}, ["idle", "open"], h)
		_mouth.position.y = -h * 0.5
		_mouth.play("idle")
	_orbit = randf() * TAU
	_place(0.0)
	_beam = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_beam.mesh = q
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = load("res://core/shaders/laser_beam.gdshader")
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	# the ribbon is placed by its transform each frame and can run twenty metres: never cull it by the unit quad
	_beam.extra_cull_margin = 24.0
	add_child(_beam)


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


func _place(delta: float) -> void:
	if _familiar == null:
		return
	var r := _familiar_param("radius", 1.25)
	var h := _familiar_param("height", 1.3)
	var bob := _familiar_param("bob", 0.09)
	# the mouth holds still while it fires, and drifts around the hero the rest of the time
	if _beam_t <= 0.0:
		_orbit += delta * _familiar_param("speed", 0.9)
	var t := float(Time.get_ticks_msec()) * 0.001
	var want: Vector3 = player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 2.4) * bob, sin(_orbit) * r)
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	if _model:
		# the jaw drops wide while the beam pours and chews slowly between shots; the lips turn to the beam's line while
		# it pours and to the nearest creature (else towards the camera) the rest of the time; a shake while it roars
		var firing: bool = _beam_t > 0.0
		_open = move_toward(_open, 1.0 if firing else 0.0, delta * 7.0)
		if _jaw:
			var chew := 0.5 + 0.5 * sin(t * 2.6)
			_jaw.rotation.x = -deg_to_rad(46.0 * _open + 7.0 * chew * (1.0 - _open))
		var face := _dir() if firing else Vector3.ZERO
		if not firing:
			var near: int = game.enemies.nearest_index(_familiar.global_position, stat("range", 12.0))
			if near >= 0:
				face = game.enemies.pos[near] - _familiar.global_position
		face.y = 0.0
		if face.length_squared() < 0.0001:
			face = Vector3(0, 0, 1)
		_face_yaw = lerp_angle(_face_yaw, atan2(-face.x, -face.z), clampf(delta * 9.0, 0.0, 1.0))
		# tipped back 32 degrees so the lips face up towards the high camera (level, they read as a red bowl)
		_model.rotation = Vector3(deg_to_rad(32.0), _face_yaw, 0.0)
		var roar: float = (1.0 + 0.04 * sin(t * 38.0)) if firing else 1.0
		_model.scale = Vector3.ONE * _model_scale * roar
	elif _mouth:
		# open wide while the beam pours, shut between shots; a shake of the lips while it roars
		var want_open: bool = _beam_t > 0.0
		if want_open != _mouth_open:
			_mouth_open = want_open
			_mouth.play("open" if want_open else "idle")
		var sc: float = (1.1 + 0.05 * sin(t * 38.0)) if want_open else 1.0
		_mouth.scale = _mouth.scale.lerp(Vector3(sc, sc, sc), clampf(delta * 14.0, 0.0, 1.0))


func muzzle() -> Vector3:
	if _familiar:
		return _familiar.global_position
	return player.aim_origin(player.forward()) + Vector3(0, 0.4, 0)


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	var t := enemies.nearest_index(player.global_position, stat("range", 12.0))
	if t < 0:
		return false
	var d: Vector3 = enemies.pos[t] - muzzle()
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return false
	_aim_yaw = atan2(-d.x, -d.z)
	_yaw0 = _aim_yaw
	_beam_t = maxf(stat("duration", 2.0), 0.2)
	_tick_t = 0.0
	_hit_once.clear()
	sfx("fire", muzzle())
	return true


func _tick(delta: float) -> void:
	if _beam_t > 0.0:
		_beam_t -= delta
		# Sweep: the line pans across while it burns, so it cuts through a crowd instead of one file
		var arch := deg_to_rad(_beam_param("arch_deg", 0.0))
		if arch > 0.0:
			var total: float = maxf(stat("duration", 2.0), 0.2)
			var f: float = clampf(1.0 - _beam_t / total, 0.0, 1.0)
			_aim_yaw = _yaw0 - arch * 0.5 + arch * f
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = maxf(_beam_param("tick", 0.18), 0.05)
			_burn()
		_draw_beam()
	elif _beam and _beam.visible:
		_beam.visible = false
	_place(delta)


func _dir() -> Vector3:
	return Vector3(-sin(_aim_yaw), 0, -cos(_aim_yaw))


## Everything standing in the line takes a tick of damage, the element it carries, and (Bad Breath) a shove the first
## time the beam touches it.
func _burn() -> void:
	var enemies: EnemyManager = game.enemies
	var from := muzzle()
	var dir := _dir()
	var reach := stat("range", 12.0)
	var width: float = _beam_param("width", 0.34) * _beam_param("width_mult", 1.0)
	var dmg := stat("damage", 9.0)
	var wid := inst.def.id
	var seen: Dictionary = {}
	var steps := int(ceil(reach / maxf(width, 0.3)))
	for k in range(steps + 1):
		var p: Vector3 = from + dir * (float(k) * reach / float(maxi(steps, 1)))
		for e in enemies.indices_in_radius(p, width + 0.45):
			if seen.has(e):
				continue
			seen[e] = true
			if stat("fire_damage", 0.0) > 0.0:
				enemies.ignite(e, wid, stat("fire_damage", 4.0), stat("fire_duration", 1.8), stat("fire_spread", 0.4))
			if stat("poison_damage", 0.0) > 0.0:
				enemies.poison(e, wid, stat("poison_damage", 3.0), maxi(stat_int("poison_stacks", 1), 1), stat("poison_duration", 8.0))
			var knock := 0.0
			if _beam_flag("first_knock") and not _hit_once.has(e):
				knock = stat("knockback", 0.0)
			_hit_once[e] = true
			if enemies.damage(e, dmg, wid, dir, knock):
				inst.kills += 1
			if randf() < 0.5:
				game.fx_hit(enemies.pos[e] + Vector3(0, enemies.size[e] * 0.4, 0), inst.def)


## The line itself: one ribbon from the lips to the end of its reach, turned about its own axis to face the camera, its
## basis built from that axis (Basis.scaled scales along the world's axes, which is how the old beam missed the mouth).
## It runs down from the lips to chest height on its way out, where the burn is.
func _draw_beam() -> void:
	var from := muzzle()
	var dir := _dir()
	var reach := stat("range", 12.0)
	var width: float = _beam_param("width", 0.34) * _beam_param("width_mult", 1.0)
	var col := _beam_colour()
	var to: Vector3 = from + dir * reach
	to.y = player.global_position.y + 0.6
	var axis := to - from
	var mid: Vector3 = from + axis * 0.5
	var cam := get_viewport().get_camera_3d()
	var to_cam: Vector3 = (cam.global_position - mid).normalized() if cam else Vector3.UP
	var along := axis.normalized()
	var side := along.cross(to_cam)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var normal := side.cross(along).normalized()
	_beam.visible = true
	_beam.global_transform = Transform3D(Basis(side * width * 3.4, axis, normal), mid)
	_beam_mat.set_shader_parameter("color", col)
	# a small spark now and then just past the lips (a burst on the mouth itself hid the painting)
	if randf() < 0.15:
		game.fx_burst(from + dir * 0.8, col, 0.2)
