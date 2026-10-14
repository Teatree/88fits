## A continuous beam. Every `cooldown` the mouth opens, locks onto the nearest creature and pours a line of light
## through it for `duration`: everything standing in the line takes `damage` every `beam.tick` seconds, whatever the
## crowd behind it. `params.beam`: width, tick, arch_deg (Sweep pans the line as it burns), color, width_mult,
## first_knock (Bad Breath throws whatever the beam first touches). The visual scene's "Familiar" is where the mouth
## floats; the mouth is a 3D model there (pass 34, tools/blender_mouth.py: Familiar/Mouth with a Jaw), else the painted
## two-frame sprite of pass 33.2 (tools/gen_mouth.py), and the beam is one camera-facing ribbon (core/shaders/laser_beam) from
## the lips along its own axis. The 3D mouth it replaced was a torus that read as a red doughnut, and its beam boxes
## were stretched along the world's axes, so any beam not aimed north was drawn off to one side of the mouth.
## Pass 46: every beam has a wind-up (the jaw clamps shut and the mouth squashes for WINDUP seconds), then the jaw snaps
## open to JAW_OPEN_DEG on a spring that overshoots, the upper lip lifts and the cavity glows while it pours. At the lips:
## a flash, sparks, a ring on the sand and a camera kick as it starts, the ring again every PULSE seconds while it pours.
## The beam fires straight, through hills: wherever its line runs under a dune the sand over it boils, hot cracks and
## scorches on the surface and embers and grit puffing up (boil_points, _boil). The damage line is what it was.
## Pass 61, Bad Breath (Garry chose the cheap look: "Green-yellow wobbling beam, gust puffs on hit"): `params.beam.breath`
## {color, core, haze, haze_mix, haze_over, glow, wobble, gusts, gust_color} turns the beam green-yellow (when no other path gives it a colour:
## with Slow Roast the line stays orange and the breath is its haze), sets the ribbon snaking and breathing (the shader's
## `wobble`) with its glow in `haze`, and throws gust puffs where it hits (Fx.breath_gust): a big gust on the first touch
## that knocks a creature back, up to `gusts` small ones a tick on the rest. The cavity glows the beam's colour.
class_name LaserBeam
extends WeaponBehavior

const WINDUP := 0.12
const JAW_OPEN_DEG := 80.0
## the jaw's spring (stiffness, damping): it snaps open past JAW_OPEN_DEG by about a sixth and settles
const JAW_K := 900.0
const JAW_D := 30.0
const PULSE := 0.28
const BOIL_STEP := 0.5
const BOIL_EVERY := 0.07
const CRACK_EVERY := 0.12

var _familiar: Node3D
## the 3D mouth (pass 34): the visual scene's Familiar/Mouth, lips on a `Jaw` that opens while the beam pours
var _model: Node3D
var _jaw: Node3D
var _upper: Node3D
var _upper_rest := Vector3.ZERO
var _cavity_mat: StandardMaterial3D
var _open := 0.0
var _jaw_a := 0.0   # radians; below zero is open
var _jaw_v := 0.0
var _model_scale := 1.0
var _face_yaw := 0.0
var _mouth: BillboardSprite
var _mouth_open := false
var _orbit := 0.0
var _aim_yaw := 0.0
var _windup_t := 0.0
var _beam_t := 0.0
var _tick_t := 0.0
var _pulse_t := 0.0
var _boil_t := 0.0
var _crack_t := 0.0
var _yaw0 := 0.0
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _hit_once: Dictionary = {}
## beams poured so far (tests)
var beams := 0
## Bad Breath's gusts thrown so far (tests, pass 61)
var gust_hits := 0
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
	var br := breath()
	if not br.is_empty():
		return _rgb(br.get("color"), BREATH_GREEN)
	return Color(1.0, 0.25, 0.7)


## Bad Breath's green-yellow (pass 61) when its params name none, and the most big gusts one tick throws (a crowd
## walking into the line all at once).
const BREATH_GREEN := Color(0.66, 1.0, 0.16)
const BIG_GUSTS := 4


## params.beam.breath (pass 61, Bad Breath), {} without it.
func breath() -> Dictionary:
	var b = inst.params.get("beam", {}) if inst else {}
	var br = (b as Dictionary).get("breath") if b is Dictionary else null
	return br if br is Dictionary else {}


## A colour from params: [r, g, b] or "#rrggbb", else `fallback`.
static func _rgb(v, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	if v is String and str(v) != "":
		return Color(str(v))
	return fallback


## The beam's haze (the glow round its core) and how much of it shows: Bad Breath's, else none (pass 61).
func _beam_haze() -> Color:
	var br := breath()
	if br.is_empty():
		return Color(1, 1, 1, 0)
	var h := _rgb(br.get("haze"), Color(0.86, 1.0, 0.3))
	# over another path's colour (Slow Roast's orange) the breath is only a fringe, so the orange still reads
	var b = inst.params.get("beam", {})
	var over: bool = b is Dictionary and (b as Dictionary).get("color") is Array
	var mix := float(br.get("haze_over", 0.35)) if over else float(br.get("haze_mix", 0.6))
	return Color(h.r, h.g, h.b, clampf(mix, 0.0, 1.0))


## The colour the beam's core runs to: white, or Bad Breath's own `core` while the breath is the beam's colour (with
## Slow Roast's orange the core stays white-hot).
func _beam_core() -> Color:
	var br := breath()
	var b = inst.params.get("beam", {})
	if br.is_empty() or (b is Dictionary and (b as Dictionary).get("color") is Array):
		return Color(1, 1, 1)
	return _rgb(br.get("core"), Color(0.93, 1.0, 0.62))


## How hard the line snakes and breathes (pass 61: Bad Breath's `wobble`, else 0).
func wobble() -> float:
	return maxf(float(breath().get("wobble", 0.0)), 0.0)


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
		_upper = _model.find_child("Upper", true, false) as Node3D
		if _upper:
			_upper_rest = _upper.position
		# the cavity lights up from inside while the beam pours: its own copy of its material, with emission
		var cav := _model.find_child("Cavity", true, false) as MeshInstance3D
		if cav and cav.mesh:
			var base: Material = cav.material_override if cav.material_override else cav.mesh.surface_get_material(0)
			_cavity_mat = (base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()) as StandardMaterial3D
			_cavity_mat.emission_enabled = true
			_cavity_mat.emission = _beam_colour().lightened(0.35)
			_cavity_mat.emission_energy_multiplier = 0.0
			cav.material_override = _cavity_mat
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


## On every build change (pass 61): the cavity glows the beam's colour as it is now (Bad Breath's green, Slow Roast's
## orange), not the colour it had when the mouth was made.
func refresh_marks() -> void:
	super.refresh_marks()
	if _cavity_mat:
		_cavity_mat.emission = _beam_colour().lightened(0.35)


func _familiar_param(key: String, default: float) -> float:
	var f = inst.params.get("familiar", {})
	return float(f.get(key, default)) if f is Dictionary else default


func _place(delta: float) -> void:
	if _familiar == null:
		return
	var r := _familiar_param("radius", 1.25)
	var h := _familiar_param("height", 1.3)
	var bob := _familiar_param("bob", 0.09)
	# the mouth holds still while it winds up and fires, and drifts around the hero the rest of the time
	if _beam_t <= 0.0 and _windup_t <= 0.0:
		_orbit += delta * _familiar_param("speed", 0.9)
	var t := float(Time.get_ticks_msec()) * 0.001
	var want: Vector3 = player.global_position + Vector3(cos(_orbit) * r, h + sin(t * 2.4) * bob, sin(_orbit) * r)
	_familiar.global_position = want if delta <= 0.0 else _familiar.global_position.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
	var firing: bool = _beam_t > 0.0
	var winding: bool = _windup_t > 0.0
	if _model:
		_place_model(delta, t, firing, winding)
	elif _mouth:
		# open wide while the beam pours, shut between shots (and squashed through the wind-up); a shake while it roars
		var want_open: bool = firing
		if want_open != _mouth_open:
			_mouth_open = want_open
			_mouth.play("open" if want_open else "idle")
		var sc := Vector3.ONE * ((1.1 + 0.05 * sin(t * 38.0)) if want_open else 1.0)
		if winding:
			sc = Vector3(1.12, 0.86, 1.12)
		_mouth.scale = _mouth.scale.lerp(sc, clampf(delta * 14.0, 0.0, 1.0)) if delta > 0.0 else sc


## The 3D mouth: the jaw on its spring (clamped shut through the wind-up, snapped wide while the beam pours, a slow chew
## between), the upper lip lifting with it, the cavity glowing; it faces the beam's line while it pours and the nearest
## creature (else the camera) the rest of the time, tipped back 32 degrees so the lips face up to the high camera (level,
## they read as a red bowl); squashed through the wind-up, shaking while it roars.
func _place_model(delta: float, t: float, firing: bool, winding: bool) -> void:
	var target: float
	if winding:
		target = deg_to_rad(4.0)
	elif firing:
		target = -deg_to_rad(JAW_OPEN_DEG)
	else:
		target = -deg_to_rad(7.0 * (0.5 + 0.5 * sin(t * 2.6)))
	if delta <= 0.0:
		_jaw_a = target
		_jaw_v = 0.0
	else:
		# small steps, so a long frame cannot shake the spring loose
		var n: int = clampi(int(ceil(delta * 60.0)), 1, 6)
		var hstep: float = delta / float(n)
		for k in range(n):
			_jaw_v += ((target - _jaw_a) * JAW_K - _jaw_v * JAW_D) * hstep
			_jaw_a += _jaw_v * hstep
	if _jaw:
		_jaw.rotation.x = _jaw_a
	_open = clampf(-_jaw_a / deg_to_rad(JAW_OPEN_DEG), 0.0, 1.25)
	if _upper:
		_upper.position = _upper_rest + Vector3(0, 0.05 * _open, 0)
		_upper.rotation.x = 0.18 * _open
	if _cavity_mat:
		_cavity_mat.emission_energy_multiplier = ((2.2 + 0.6 * sin(t * 40.0)) * minf(_open, 1.0)) if firing else 0.0
	var face := _dir() if (firing or winding) else Vector3.ZERO
	if not firing and not winding:
		var near: int = aim_index(_familiar.global_position, stat("range", 12.0))
		if near >= 0:
			face = game.enemies.pos[near] - _familiar.global_position
	face.y = 0.0
	if face.length_squared() < 0.0001:
		face = Vector3(0, 0, 1)
	_face_yaw = lerp_angle(_face_yaw, atan2(-face.x, -face.z), clampf(delta * 9.0, 0.0, 1.0)) if delta > 0.0 else atan2(-face.x, -face.z)
	_model.rotation = Vector3(deg_to_rad(32.0), _face_yaw, 0.0)
	var sc := Vector3.ONE * _model_scale
	if winding:
		var sq := sin((1.0 - clampf(_windup_t / WINDUP, 0.0, 1.0)) * PI * 0.5)
		sc = _model_scale * Vector3(1.0 + 0.12 * sq, 1.0 - 0.14 * sq, 1.0 + 0.12 * sq)
	elif firing:
		sc *= 1.0 + 0.04 * sin(t * 38.0)
	_model.scale = sc


func muzzle() -> Vector3:
	if _familiar:
		return _familiar.global_position
	return player.aim_origin(player.forward()) + Vector3(0, 0.4, 0)


func _fire() -> bool:
	var enemies: EnemyManager = game.enemies
	# pass 73 (lane SNIPER): aim_index, the nearest with a special, an Elite or the boss within reach first
	var t := aim_index(player.global_position, stat("range", 12.0))
	if t < 0:
		return false
	var d: Vector3 = enemies.pos[t] - muzzle()
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return false
	_aim_yaw = atan2(-d.x, -d.z)
	_yaw0 = _aim_yaw
	# the wind-up first: the beam pours when it is over
	_windup_t = WINDUP
	return true


## The beam starts: the jaw is let go (its spring snaps it open), the flash at the lips.
func _start_beam() -> void:
	_beam_t = maxf(stat("duration", 2.0), 0.2)
	_tick_t = 0.0
	_pulse_t = PULSE
	_boil_t = 0.0
	_crack_t = 0.0
	_hit_once.clear()
	beams += 1
	sfx("fire", muzzle())
	_flash()


func _tick(delta: float) -> void:
	if _windup_t > 0.0:
		_windup_t -= delta
		if _windup_t <= 0.0:
			_windup_t = 0.0
			_start_beam()
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
		_pulse_t -= delta
		if _pulse_t <= 0.0:
			_pulse_t = PULSE
			_pulse()
		_boil(delta)
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
	# Bad Breath (pass 61): a big gust on every first touch, up to `gusts` small ones a tick on the rest
	var br := breath()
	var gusts: int = int(br.get("gusts", 2)) if not br.is_empty() else 0
	var bigs := BIG_GUSTS
	var fx = game.get("fx") if not br.is_empty() else null
	var gust_col := _rgb(br.get("gust_color"), _beam_colour()) if not br.is_empty() else Color.WHITE
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
			var first := not _hit_once.has(e)
			if _beam_flag("first_knock") and first:
				knock = stat("knockback", 0.0)
			_hit_once[e] = true
			if fx and fx.has_method("breath_gust"):
				var gp: Vector3 = enemies.pos[e] + Vector3(0, enemies.size[e] * 0.45, 0)
				if first and bigs > 0:
					bigs -= 1
					fx.breath_gust(gp, dir, gust_col, true)
					gust_hits += 1
				elif gusts > 0 and randf() < 0.5:
					gusts -= 1
					fx.breath_gust(gp, dir, gust_col, false)
					gust_hits += 1
			if enemies.damage(e, dmg, wid, dir, knock):
				inst.kills += 1
			if randf() < 0.5:
				game.fx_hit(enemies.pos[e] + Vector3(0, enemies.size[e] * 0.4, 0), inst.def)


## Where the drawn line ends: its reach along the aim, down at the hero's chest height.
func _beam_end(from: Vector3) -> Vector3:
	var to: Vector3 = from + _dir() * stat("range", 12.0)
	to.y = player.global_position.y + 0.6
	return to


## The line itself: one ribbon from the lips to the end of its reach, turned about its own axis to face the camera, its
## basis built from that axis (Basis.scaled scales along the world's axes, which is how the old beam missed the mouth).
## It runs down from the lips to chest height on its way out, where the burn is.
func _draw_beam() -> void:
	var from := muzzle()
	var width: float = _beam_param("width", 0.34) * _beam_param("width_mult", 1.0)
	var col := _beam_colour()
	var to: Vector3 = _beam_end(from)
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
	_beam_mat.set_shader_parameter("haze", _beam_haze())
	_beam_mat.set_shader_parameter("wobble", wobble())
	_beam_mat.set_shader_parameter("core_color", _beam_core())
	_beam_mat.set_shader_parameter("glow_gain", maxf(float(breath().get("glow", 1.0)), 0.0))
	# a small spark now and then just past the lips (a burst on the mouth itself hid the painting)
	if randf() < 0.15:
		game.fx_burst(from + _dir() * 0.8, col, 0.2)


## The flash as the beam leaves the lips: a white-hot pop and a burst of its colour, sparks flung out along it, a ring on
## the sand under the mouth and a small kick of the camera.
func _flash() -> void:
	var at := muzzle()
	var dir := _dir()
	var col := _beam_colour()
	var fx = game.get("fx")
	if fx:
		fx.burst(at + dir * 0.25, Color(1.0, 1.0, 1.0), 0.55)
		fx.burst(at + dir * 0.45, col, 0.75)
		if fx.has_method("mote"):
			var hot := col.lightened(0.45)
			for k in range(10):
				var d := dir.rotated(Vector3.UP, randf_range(-0.9, 0.9))
				fx.mote(at + d * 0.3, d * randf_range(4.0, 8.0) + Vector3(0, randf_range(0.5, 2.5), 0), randf_range(0.25, 0.4), randf_range(0.12, 0.2), Color(hot.r, hot.g, hot.b, 1.0))
	_ground_ring(1.6, 0.35)
	var cam = game.get("camera")
	if cam and cam.has_method("shake"):
		cam.shake(0.18)


## While it pours: a puff at the lips and the ring on the sand again.
func _pulse() -> void:
	var fx = game.get("fx")
	if fx:
		fx.burst(muzzle() + _dir() * 0.3, _beam_colour(), 0.4)
	_ground_ring(1.15, 0.3)


func _ground_ring(r: float, dur: float) -> void:
	var tg = game.get("telegraphs")
	if tg == null or not tg.has_method("flash_ring"):
		return
	var at := muzzle()
	var map = game.get("map")
	at.y = map.height_at(at.x, at.z) if map else player.global_position.y
	tg.flash_ring(at, r, _beam_colour(), dur)


## The spots on the sand over the beam where its line runs underground: the drawn line from the lips to its end, sampled
## every BOIL_STEP metres; wherever the ground there stands higher than the line, the point on the surface. Empty without
## a map.
func boil_points(from: Vector3, to: Vector3) -> Array:
	var out: Array = []
	var map = game.get("map") if game else null
	if map == null:
		return out
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	if flat < BOIL_STEP:
		return out
	var n := int(floor(flat / BOIL_STEP))
	for k in range(1, n + 1):
		var p: Vector3 = from.lerp(to, float(k) * BOIL_STEP / flat)
		var h: float = map.height_at(p.x, p.z)
		if h > p.y:
			out.append(Vector3(p.x, h, p.z))
	return out


## The boiling sand, throttled: every BOIL_EVERY seconds embers fly up from spots over the buried line, with a bubble of
## hot sand or a puff of grit; every CRACK_EVERY hot cracks glow on the surface there, most with a glowing scorch.
func _boil(delta: float) -> void:
	_boil_t -= delta
	_crack_t -= delta
	if _boil_t > 0.0 and _crack_t > 0.0:
		return
	var from := muzzle()
	var pts := boil_points(from, _beam_end(from))
	if pts.is_empty():
		_boil_t = maxf(_boil_t, BOIL_EVERY)
		_crack_t = maxf(_crack_t, BOIL_EVERY)
		return
	if _boil_t <= 0.0:
		_boil_t = BOIL_EVERY
		var fx = game.get("fx")
		if fx:
			for k in range(mini(4, pts.size())):
				var p: Vector3 = pts[randi() % pts.size()]
				if fx.has_method("mote"):
					fx.mote(p + Vector3(randf_range(-0.25, 0.25), 0.05, randf_range(-0.25, 0.25)), Vector3(randf_range(-0.5, 0.5), randf_range(1.8, 3.6), randf_range(-0.5, 0.5)), randf_range(0.4, 0.7), randf_range(0.18, 0.3), Color(1.0, 0.45 + 0.35 * randf(), 0.12, 1.0))
				# a bubble of hot sand swelling and bursting
				if randf() < 0.5 and fx.has_method("burst"):
					fx.burst(p + Vector3(0, 0.12, 0), Color(1.0, 0.5, 0.15), 0.32)
				elif randf() < 0.5 and fx.has_method("sand"):
					fx.sand(p, 0.45)
	if _crack_t <= 0.0:
		_crack_t = CRACK_EVERY
		var tg = game.get("telegraphs")
		if tg:
			for k in range(mini(2, pts.size())):
				var q: Vector3 = pts[randi() % pts.size()]
				var a := _dir().rotated(Vector3.UP, randf_range(-0.7, 0.7))
				if tg.has_method("line"):
					tg.line(q - a * 0.45, a, 0.9, 0.45, Color(1.0, 0.42, 0.08), 0.22)
				if randf() < 0.7 and tg.has_method("scorch"):
					tg.scorch(q, 0.42, Color(1.0, 0.52, 0.12, 0.6), Color(0.6, 0.12, 0.0, 0.0), 0.15, 0.6)
