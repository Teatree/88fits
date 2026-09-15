## Cheap visual effects: bursts, hit sparks, lightning strips. Node-based but short-lived and capped.
class_name Fx
extends Node3D

const MAX_LIVE := 140
var _live := 0


func burst(at: Vector3, color: Color, size: float = 1.0) -> void:
	if _live >= MAX_LIVE:
		return
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 10
	s.rings = 5
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	m.material_override = mat
	m.position = at
	m.scale = Vector3.ONE * 0.2
	add_child(m)
	_live += 1
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * size * 2.2, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.36)
	tw.chain().tween_callback(func(): m.queue_free(); _live -= 1)
	# a hot white core that pops first, so the burst has a snap and not just a fade
	if _live < MAX_LIVE:
		var core := MeshInstance3D.new()
		core.mesh = s
		var cm := StandardMaterial3D.new()
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cm.albedo_color = Color(1, 1, 1, 0.95)
		core.material_override = cm
		core.position = at
		core.scale = Vector3.ONE * 0.1
		add_child(core)
		_live += 1
		var tc := create_tween()
		tc.set_parallel(true)
		tc.tween_property(core, "scale", Vector3.ONE * size * 1.1, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tc.tween_property(cm, "albedo_color:a", 0.0, 0.18)
		tc.chain().tween_callback(func(): core.queue_free(); _live -= 1)


## A poison tick: two small green puffs drifting up, so the damage is seen.
func poison(at: Vector3) -> void:
	if _live >= MAX_LIVE:
		return
	for k in range(2):
		if _live >= MAX_LIVE:
			return
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sm.radial_segments = 6
		sm.rings = 3
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.5, 1.0, 0.4, 0.85)
		m.material_override = mat
		m.position = at + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3))
		m.scale = Vector3.ONE * 0.5
		add_child(m)
		_live += 1
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "position:y", m.position.y + 1.1, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3.ONE * 1.3, 0.5)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tw.chain().tween_callback(func(): m.queue_free(); _live -= 1)


func hit(at: Vector3, color: Color) -> void:
	if _live >= MAX_LIVE or randf() > 0.7:
		return
	# two bright shards flung out of the impact, plus a tiny flash
	for k in range(2):
		if _live >= MAX_LIVE:
			return
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.26, 0.26, 0.26)
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color.lightened(0.25)
		m.material_override = mat
		m.position = at
		m.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		add_child(m)
		_live += 1
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "position", at + Vector3(randf_range(-1.1, 1.1), randf_range(0.6, 1.8), randf_range(-1.1, 1.1)), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3.ONE * 0.05, 0.3)
		tw.chain().tween_callback(func(): m.queue_free(); _live -= 1)
	if _live < MAX_LIVE:
		var f := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.35
		s.height = 0.7
		s.radial_segments = 8
		s.rings = 4
		f.mesh = s
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.albedo_color = Color(1, 1, 1, 0.8)
		f.material_override = fm
		f.position = at
		f.scale = Vector3.ONE * 0.3
		add_child(f)
		_live += 1
		var tf := create_tween()
		tf.set_parallel(true)
		tf.tween_property(f, "scale", Vector3.ONE, 0.1)
		tf.tween_property(fm, "albedo_color:a", 0.0, 0.12)
		tf.chain().tween_callback(func(): f.queue_free(); _live -= 1)


func lightning(points: Array, color: Color = Color(0.6, 0.85, 1.0)) -> void:
	if points.size() < 2 or _live >= MAX_LIVE:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for k in range(points.size() - 1):
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var segs := 5
		for s in range(segs + 1):
			var p := a.lerp(b, float(s) / segs)
			if s > 0 and s < segs:
				p += Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
			im.surface_add_vertex(p)
	im.surface_end()
	var m := MeshInstance3D.new()
	m.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	add_child(m)
	_live += 1
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.omni_range = 6.0
	glow.light_energy = 3.0
	glow.position = points[1]
	add_child(glow)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_property(glow, "light_energy", 0.0, 0.18)
	tw.chain().tween_callback(func(): m.queue_free(); glow.queue_free(); _live -= 1)
