## A chest on the ground. Walking into it calls Game.open_chest: the game pauses and the reel decides what it held.
class_name Chest
extends Node3D

## the boss's chest: bigger, purple and gold, always a mutation, and opening it calls the map in
var boss := false
var opened := false
var pulled := false        # flying to the hero (a boss kill pulls every chest in)
## Pass 118 (lane BOSSCHEST): a boss's own chest: the boss's id (its model, light and paintings: BossChest.look) and what it
## holds (BossChest.make_pack); "" and {} for every other chest
var boss_id := ""
var pack: Dictionary = {}
## a boss chest's size against its model, and its shine's against the gold chest's
const BOSS_SCALE := 1.3
const BOSS_SHINE := 1.4
## where the lid rests in its model (its bob is round it)
var _lid_y0 := 0.0
## the pool of light on the sand, and where the chest stood when its slope was last read (pass 52)
var _pool: MeshInstance3D
var _pool_at := Vector3.INF
var pull_speed := 0.0
var _lid: Node3D
var _t := 0.0
var _glint: MeshInstance3D
## the shine (pass 33): a pool of light on the sand, a sunburst behind the lid, a beam and drifting sparkles
const SHINE := preload("res://core/shaders/shine_aura.gdshader")
## How far behind the chest its beam stands (m; pass 118): past the turning chest's half diagonal, so its body hides the
## beam's bright foot from the camera and the light rises from behind the lid
const BEAM_BACK := 0.75
## The sunburst's height over the chest's foot and how far behind its middle it is drawn (m, times the purple chest's
## 1.35; pass 118): its plane clears the turning chest's back top corner (the lid's top 0.85 m up, its half diagonal
## 0.6 m), so the chest stands wholly in front of its own light
const SUN_Y := 0.9
const SUN_BACK := 0.75
## The lock's glint across at its flare (m; pass 118: a soft sparkle in place of the two white bars)
const GLINT := 0.5
var _sparkles: Array = []


func _ready() -> void:
	# the modelled chest (art/props/meta/chest.glb: a Body and a hinged Lid), the old two boxes only if it is missing
	var path := "res://art/props/meta/chest.glb"
	# pass 118 (lane BOSSCHEST): a boss's own chest is its own model in its own colours (tools/blender_boss_chests.py)
	var look: Dictionary = BossChest.look(boss_id) if boss_id != "" else {}
	if not look.is_empty() and ResourceLoader.exists(str(look["model"])):
		path = str(look["model"])
	if ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		model.scale = Vector3.ONE * (BOSS_SCALE if boss_id != "" else (1.45 if boss else 0.9))
		add_child(model)
		_lid = model.find_child("Lid", true, false)
		if _lid:
			_lid_y0 = _lid.position.y
		if boss:
			# violet lacquer over the walnut, so a boss chest is never mistaken for the ones the crowd drops
			var tint := StandardMaterial3D.new()
			tint.albedo_color = Color(0.36, 0.16, 0.5)
			tint.metallic = 0.35
			tint.roughness = 0.35
			tint.emission_enabled = true
			tint.emission = Color(0.5, 0.2, 0.7)
			tint.emission_energy_multiplier = 0.35
			for n in model.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).material_override = tint
	else:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.1, 0.7, 0.8)
		body.mesh = bm
		body.position.y = 0.35
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.33, 0.15)
		body.material_override = mat
		add_child(body)
		_lid = MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(1.15, 0.25, 0.85)
		_lid.mesh = lm
		_lid.position.y = 0.82
		_lid_y0 = 0.82
		add_child(_lid)
	# a soft gold glow under the lid line, so the chest reads from the camera's height
	var glow := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.68, 0.03, 0.48)
	glow.mesh = gm
	glow.position.y = 0.5
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(1.0, 0.8, 0.35)
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.75, 0.3)
	gmat.emission_energy_multiplier = 1.2
	glow.material_override = gmat
	add_child(glow)
	# the shine (pass 33, after Megabonk's chests): a pool of gold light on the sand, a sunburst wheeling behind the lid,
	# a tall soft beam that shows over the crowd from across the screen, sparkles drifting up, and a four-point glint
	# that wheels over the lock: a chest is a thing you cross the map for, so it is never mistaken for a rock.
	# A boss chest shines violet and bigger.
	var tint := Color(0.8, 0.5, 1.0) if boss else Color(1.0, 0.8, 0.32)
	var ks := 1.35 if boss else 1.0
	# pass 118 (lane BOSSCHEST): a boss chest shines in its boss's colour (its JSON's boss.chest.shine), bigger again
	if not look.is_empty():
		tint = look["shine"]
		ks = BOSS_SHINE
	_pool = _shine(2, Vector2(4.6, 4.6) * ks, tint, 0.7, Vector3.ZERO)
	var sun := _shine(0, Vector2(4.4, 4.4) * ks, tint, 0.8, Vector3(0, SUN_Y * ks, 0))
	# pass 118: the sunburst's plane stands behind the whole chest (its default 0.35 m cut through the lid's back, and its
	# rays were drawn across the lid; the purple chest's showed most)
	(sun.material_override as ShaderMaterial).set_shader_parameter("push_back", SUN_BACK * ks)
	var beam := _shine(1, Vector2(1.2 * ks, 9.0), tint, 0.75, Vector3.ZERO)
	# pass 118: the beam stands behind the chest, not through its middle (shine_aura.gdshader beam_back)
	(beam.material_override as ShaderMaterial).set_shader_parameter("beam_back", BEAM_BACK * ks)
	for s in range(6):
		_sparkles.append(_shine(3, Vector2(0.45, 0.45), tint.lightened(0.45), 1.0, Vector3.ZERO))
	# the glint on the lock (pass 118; Garry: "Chests have a bug where one of the rays of shine shines through the middle
	# of them"): it was two hard white bars, 0.55 m each, that flared into a white cross over the chest's whole front; now
	# the shine's own soft four-point sparkle (shine_aura.gdshader mode 3), GLINT m across at its flare, over the lock
	_glint = _shine(3, Vector2(GLINT, GLINT), Color(1.0, 1.0, 0.92), 1.0, Vector3(0.0, 0.66, 0.4) * ((1.45 / 0.9) if boss else 1.0))
	if boss_id != "":
		# over the boss chest's lock plate (its model's front face, H - 0.16 m up)
		_glint.position = Vector3(0.0, 0.46, 0.5) * BOSS_SCALE
	if Fx.want_lights():
		var light := OmniLight3D.new()
		light.light_color = tint if boss_id != "" else Color(1.0, 0.8, 0.4)
		light.omni_range = 4.0
		light.light_energy = 1.2
		light.position.y = 1.2
		add_child(light)


## The pool of light lies on the sand's slope under the chest (pass 52: on a slope half of it sank out of sight), read
## again whenever the chest has moved (a boss kill pulls it in).
func _slope_pool() -> void:
	if _pool == null or global_position.distance_squared_to(_pool_at) < 0.01:
		return
	_pool_at = global_position
	var g = get_parent().get("game") if get_parent() else null
	var map = g.get("map") if g else null
	if map == null or not map.has_method("slope_at"):
		return
	(_pool.material_override as ShaderMaterial).set_shader_parameter("slope", map.slope_at(_pool_at.x, _pool_at.z, 2.0))


## One quad of a shine, drawn by core/shaders/shine_aura.gdshader in `mode` (0 sunburst, 1 beam, 2 pool, 3 sparkle);
## the spawn beam (Game._spawn_begin) uses it too.
static func shine_quad(mode: int, size: Vector2, tint: Color, strength: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	if mode == 1:
		# the beam stands on the chest: its quad is built from the ground up
		q.center_offset = Vector3(0, size.y * 0.5, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = SHINE
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("phase", randf() * 10.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the shader moves the corners (it faces the camera, lays the pool flat, stands the beam up): cull generously
	mi.extra_cull_margin = maxf(9.0, size.y)
	return mi


## One quad of the chest's own shine at `at`.
func _shine(mode: int, size: Vector2, tint: Color, strength: float, at: Vector3) -> MeshInstance3D:
	var mi := shine_quad(mode, size, tint, strength)
	mi.position = at
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	# pass 114 (lane REPLAY): the recorded frame's delta in a replay (Lockstep.dt)
	delta = Lockstep.dt(delta)
	_t += delta
	_slope_pool()
	if not opened:
		if boss_id != "":
			# pass 118: a boss chest's lid bobs round where its model rests it
			_lid.position.y = _lid_y0 + absf(sin(_t * 4.0)) * 0.03
		else:
			# pass 118 (the lead): round where the model rests it too (chest.glb's Lid stands 0.74 up its model; this
			# used to put it at 0, sunk into the body, so the ordinary and the purple chest showed no lid)
			_lid.position.y = _lid_y0 + sin(_t * 4.0) * 0.03
		rotation.y += delta * (4.0 if pulled else 0.6)
		# sparkles rise around the chest in a loop, each one flaring and gone
		var rr := 0.8 * (1.35 if boss else 1.0)
		for k in range(_sparkles.size()):
			var sp: MeshInstance3D = _sparkles[k]
			var ph: float = fmod(_t * 0.5 + float(k) / float(_sparkles.size()), 1.0)
			var a: float = float(k) * 2.4 + _t * 0.4
			sp.position = Vector3(cos(a) * rr, 0.3 + ph * 2.4, sin(a) * rr)
			sp.scale = Vector3.ONE * maxf(sin(ph * PI), 0.001) * (0.8 + 0.35 * sin(_t * 9.0 + float(k)))
		if _glint:
			# the glint: a sharp star that flares every 1.4 s and spins while it does
			var ph := fmod(_t, 1.4)
			var f := clampf(1.0 - absf(ph - 0.25) / 0.25, 0.0, 1.0)
			_glint.scale = Vector3.ONE * maxf(1.1 * f, 0.001)


func open_anim() -> void:
	var tw := create_tween()
	if _lid:
		tw.tween_property(_lid, "rotation:x", -1.5, 0.25)
	tw.parallel().tween_property(self, "scale", Vector3(1.2, 1.2, 1.2), 0.25)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_callback(queue_free)
