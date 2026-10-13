## The scenery's stencil mark (pass 72, lane SPEC; Garry: "Make the outline of the enemies not appear when they're
## behind other enemies, only when they're behind environmental things"). Every opaque thing that stands in the world
## writes a stencil value where it draws a pixel, and the last one drawn at a pixel is the nearest (each passes the depth
## test only in front of what is there), so after the opaque pass the stencil says what is nearest the camera there:
##   0          the sand, the water, the sky (nothing written)
##   1          a painting that is not scenery (PickupManager.PAINTING_STENCIL: every creature, the hero, a power-up, a
##              flower; enemy_billboard and sprite_billboard)
##   VALUE (2)  scenery: the painted props (prop_billboard), the painted structures and the portal
##              (BillboardSprite.scenery, scenery_shader), the signs (sign_depth), the barrels, the boundary wall and the
##              cliffs (mark / mark_tree on their StandardMaterial3Ds)
## A creature's outline (enemy_silhouette.gdshader, its see-through second pass) draws only where the stencil is VALUE: a
## creature hidden by a cactus, a structure, a barrel, a sign or the wall is outlined; one hidden by another creature (or
## by the hero) is not. The gems, the coins and their glints draw only where it is 0 (under every painting and every
## piece of scenery). Stencil tests cost nothing measurable; no extra draw.
class_name SceneryStencil
extends RefCounted

const VALUE := 2

static var _shader_cache: Dictionary = {}


## `m` marked as scenery (a BaseMaterial3D: custom stencil, write, always, VALUE) and returned; a ShaderMaterial is
## returned as it is (its shader says what it writes), and so is a see-through material (it draws after the outlines'
## stencil is read, and the water must never outline what wades in it).
static func mark(m: Material) -> Material:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			return m
		b.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		b.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
		b.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
		b.stencil_reference = VALUE
	return m


## Whether `m` writes the scenery's stencil (tests, tools).
static func is_marked(m: Material) -> bool:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return b.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM and (b.stencil_flags & BaseMaterial3D.STENCIL_FLAG_WRITE) != 0 and b.stencil_compare == BaseMaterial3D.STENCIL_COMPARE_ALWAYS and b.stencil_reference == VALUE
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		return (m as ShaderMaterial).shader.code.contains("stencil_mode write, compare_always, %d;" % VALUE)
	return false


## Every opaque BaseMaterial3D drawn under `root` (root included) marked as scenery: a material override, a surface's
## override, a mesh's own surface material and a primitive mesh's material. A material loaded from a file (a GLB's) is
## copied first and the copy set on this node, so the shared resource stays as it was for anyone else who draws it.
## Returns `root`.
static func mark_tree(root: Node) -> Node:
	if root == null:
		return root
	var nodes: Array = [root]
	nodes.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for n in nodes:
		if not (n is GeometryInstance3D):
			continue
		var g := n as GeometryInstance3D
		if g.material_override != null:
			g.material_override = _own(g.material_override)
			continue
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			continue
		if mesh is PrimitiveMesh:
			var pm := mesh as PrimitiveMesh
			if pm.material != null and pm.material.resource_path == "":
				mark(pm.material)
				continue
		for s in range(mesh.get_surface_count()):
			if g is MeshInstance3D:
				var mi := g as MeshInstance3D
				var o: Material = mi.get_surface_override_material(s)
				if o != null:
					mi.set_surface_override_material(s, _own(o))
				else:
					var sm: Material = mesh.surface_get_material(s)
					if sm != null:
						mi.set_surface_override_material(s, _own(sm))
			else:
				# a MultiMesh has no per-surface override: its mesh's material, copied when it came from a file
				var sm2: Material = mesh.surface_get_material(s)
				if sm2 != null and sm2.resource_path == "":
					mark(sm2)
	return root


## `m` marked, or a marked copy of it when it is a file's (shared) resource.
static func _own(m: Material) -> Material:
	if m is BaseMaterial3D and m.resource_path != "":
		return mark(m.duplicate())
	return mark(m)


## The scenery copy of a painting's shader (pass 72): `base`'s code with its stencil write set to VALUE (the painted
## structures and the portal draw through sprite_billboard.gdshader, the hero's shader, which writes
## PickupManager.PAINTING_STENCIL). Built once per shader and shared; `base` itself when it writes no stencil.
static func scenery_shader(base: Shader) -> Shader:
	if base == null:
		return base
	var key := base.resource_path if base.resource_path != "" else str(base.get_instance_id())
	if _shader_cache.has(key):
		return _shader_cache[key]
	var from := "stencil_mode write, compare_always, %d;" % PickupManager.PAINTING_STENCIL
	if not base.code.contains(from):
		push_warning("SceneryStencil: %s writes no painting stencil" % key)
		return base
	var s := Shader.new()
	s.code = base.code.replace(from, "stencil_mode write, compare_always, %d;" % VALUE)
	_shader_cache[key] = s
	return s
