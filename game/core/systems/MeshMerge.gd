## Merges the plain parts of a model that share a material into one mesh (pass 33.8). The Missile Massacre's pod is
## nine boxes, tubes and fins in three materials and drew in nine calls; merged it draws in three and looks the same:
## each part's vertices move by its own transform and its normals by the inverse transpose, so the lighting is what it
## was, and a mirrored part keeps its winding. Only leaves are merged: a MeshInstance3D with no children and no script,
## one triangle surface, no skin or blend shapes, visible, and not named in KEEP (the parts the code finds by name: the
## held gun, the companion, the muzzle, the wings, the drum, the blade, the lid, the rocket cluster and its tips). A
## model with an AnimationPlayer is left alone, since its tracks name parts too.
class_name MeshMerge
extends RefCounted

const KEEP := ["Held", "Familiar", "Projectile", "Muzzle", "WingL", "WingR", "Drum", "Blade", "Lid", "Cluster", "Body", "Jaw", "Balloon", "Flame", "Gun",
		"Hammer", "Handle", "Head", "Spin", "Core", "ClawA", "ClawB", "ClawC",
		# pass 54, the Sun Scepter: the sceptre, its staff and sun, Zenith's count ring, the glint's anchor, the sunburst
		"Scepter", "Staff", "Sun", "Charge", "Glint", "SunGlow"]
## Off for a before/after capture only.
static var enabled := true


## Merges under `root` and returns how many draw calls it saved.
static func merge(root: Node) -> int:
	if root == null or not enabled:
		return 0
	if not root.find_children("*", "AnimationPlayer", true, false).is_empty():
		return 0
	# the nodes with two or more children, found before anything is merged: a merged part has no children, so none of
	# the parts freed below is ever one of them
	var parents: Array = [root]
	for n in root.find_children("*", "Node3D", true, false):
		if n.get_child_count() > 1:
			parents.append(n)
	var saved := 0
	for n in parents:
		saved += _merge_children(n)
	return saved


static func _material_of(mi: MeshInstance3D) -> Material:
	if mi.material_override:
		return mi.material_override
	var m := mi.get_surface_override_material(0)
	if m:
		return m
	return mi.mesh.surface_get_material(0)


static func _mergeable(c: Node) -> bool:
	var mi := c as MeshInstance3D
	if mi == null or mi.get_script() != null or mi.get_child_count() > 0 or not mi.visible:
		return false
	var nm := str(mi.name)
	if nm in KEEP or nm.begins_with("Tip"):
		return false
	if mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.skin != null:
		return false
	if mi.mesh is ArrayMesh:
		var am := mi.mesh as ArrayMesh
		if am.get_blend_shape_count() > 0 or am.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
			return false
	elif not (mi.mesh is PrimitiveMesh):
		# a primitive (box, cylinder, torus...) is always triangles; anything else is left alone
		return false
	if mi.material_overlay != null or mi.transparency > 0.0:
		return false
	return _material_of(mi) != null


static func _merge_children(parent: Node) -> int:
	var groups := {}
	var order: Array = []
	for c in parent.get_children():
		if not _mergeable(c):
			continue
		var mi := c as MeshInstance3D
		var key := "%d|%d|%d" % [_material_of(mi).get_instance_id(), mi.cast_shadow, mi.layers]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(mi)
	var saved := 0
	for key in order:
		var parts: Array = groups[key]
		if parts.size() < 2:
			continue
		var mesh := _combine(parts)
		if mesh == null:
			continue
		var first: MeshInstance3D = parts[0]
		var m := MeshInstance3D.new()
		m.name = "Merged_" + str(first.name)
		m.mesh = mesh
		m.material_override = _material_of(first)
		m.cast_shadow = first.cast_shadow
		m.layers = first.layers
		parent.add_child(m)
		# merged as a model loads, before it is in the tree and before anything holds its parts
		for part: MeshInstance3D in parts:
			parent.remove_child(part)
			part.free()
		saved += parts.size() - 1
	return saved


## One surface from all the parts, in the parent's space. Parts must carry the same attributes (else null: a material
## that reads a vertex colour or a UV must find it on every part).
static func _combine(parts: Array) -> ArrayMesh:
	var sig := ""
	for mi: MeshInstance3D in parts:
		var a: Array = mi.mesh.surface_get_arrays(0)
		var s := ""
		for k in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_CUSTOM0]:
			s += "1" if a[k] != null else "0"
		if sig == "":
			sig = s
		elif s != sig:
			return null
	if sig.substr(4, 3) != "000":
		# second UVs, bones or custom data: not what these models are made of, and not worth guessing at
		return null
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for mi: MeshInstance3D in parts:
		var a: Array = mi.mesh.surface_get_arrays(0)
		var xf: Transform3D = mi.transform
		var nb: Basis = xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		var base := verts.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for p in v:
			verts.append(xf * p)
		if a[Mesh.ARRAY_NORMAL] != null:
			for n in (a[Mesh.ARRAY_NORMAL] as PackedVector3Array):
				norms.append((nb * n).normalized())
		if a[Mesh.ARRAY_TANGENT] != null:
			var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
			for k in range(0, t.size(), 4):
				var tv := (xf.basis * Vector3(t[k], t[k + 1], t[k + 2])).normalized()
				tans.append(tv.x)
				tans.append(tv.y)
				tans.append(tv.z)
				tans.append(-t[k + 3] if flip else t[k + 3])
		if a[Mesh.ARRAY_COLOR] != null:
			cols.append_array(a[Mesh.ARRAY_COLOR])
		if a[Mesh.ARRAY_TEX_UV] != null:
			uvs.append_array(a[Mesh.ARRAY_TEX_UV])
		var ind: PackedInt32Array
		if a[Mesh.ARRAY_INDEX] != null:
			ind = a[Mesh.ARRAY_INDEX]
		else:
			ind = PackedInt32Array(range(v.size()))
		for k in range(0, ind.size() - 2, 3):
			idx.append(base + ind[k])
			# a mirrored part turns its triangles over when its transform is baked in: turn them back
			idx.append(base + (ind[k + 2] if flip else ind[k + 1]))
			idx.append(base + (ind[k + 1] if flip else ind[k + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not norms.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = norms
	if not tans.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = tans
	if not cols.is_empty():
		arrays[Mesh.ARRAY_COLOR] = cols
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
