## A chest on the ground. Walking into it calls Game.open_chest: the game pauses and the reel decides what it held.
class_name Chest
extends Node3D

## the boss's chest: bigger, purple and gold, always a mutation, and opening it calls the map in
var boss := false
var opened := false
var pulled := false        # flying to the hero (a boss kill pulls every chest in)
var pull_speed := 0.0
var _lid: Node3D
var _t := 0.0
var _glint: Node3D
## the shine (pass 33): a pool of light on the sand, a sunburst behind the lid, a beam and drifting sparkles
const SHINE := preload("res://core/shaders/shine_aura.gdshader")
var _sparkles: Array = []


func _ready() -> void:
	# the modelled chest (art/props/meta/chest.glb: a Body and a hinged Lid), the old two boxes only if it is missing
	var path := "res://art/props/meta/chest.glb"
	if ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		model.scale = Vector3.ONE * (1.45 if boss else 0.9)
		add_child(model)
		_lid = model.find_child("Lid", true, false)
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
	_shine(2, Vector2(4.6, 4.6) * ks, tint, 0.7, Vector3.ZERO)
	_shine(0, Vector2(4.4, 4.4) * ks, tint, 0.8, Vector3(0, 1.0 * ks, 0))
	_shine(1, Vector2(1.2 * ks, 9.0), tint, 0.75, Vector3.ZERO)
	for s in range(6):
		_sparkles.append(_shine(3, Vector2(0.45, 0.45), tint.lightened(0.45), 1.0, Vector3.ZERO))
	_glint = Node3D.new()
	_glint.position = Vector3(0.0, 0.72, 0.38)
	var gmat2 := StandardMaterial3D.new()
	gmat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat2.albedo_color = Color(1.0, 1.0, 0.92)
	gmat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for k in range(2):
		var bar := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.06, 0.55, 0.06) if k == 0 else Vector3(0.55, 0.06, 0.06)
		bar.mesh = bm2
		bar.material_override = gmat2
		_glint.add_child(bar)
	add_child(_glint)
	if Fx.want_lights():
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.8, 0.4)
		light.omni_range = 4.0
		light.light_energy = 1.2
		light.position.y = 1.2
		add_child(light)


## One quad of the shine, drawn by core/shaders/shine_aura.gdshader in `mode` (0 sunburst, 1 beam, 2 pool, 3 sparkle).
func _shine(mode: int, size: Vector2, tint: Color, strength: float, at: Vector3) -> MeshInstance3D:
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
	mi.extra_cull_margin = 9.0
	mi.position = at
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	if not opened:
		_lid.position.y = (0.82 if _lid.get_parent() == self else 0.0) + sin(_t * 4.0) * 0.03
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
			_glint.scale = Vector3.ONE * (0.15 + 1.1 * f)
			_glint.rotation.z = ph * 4.0
			_glint.rotation.y = -rotation.y


func open_anim() -> void:
	var tw := create_tween()
	if _lid:
		tw.tween_property(_lid, "rotation:x", -1.5, 0.25)
	tw.parallel().tween_property(self, "scale", Vector3(1.2, 1.2, 1.2), 0.25)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_callback(queue_free)
