## The scenery's stencil mark (pass 72, lane SPEC; Garry: "Make the outline of the enemies not appear when they're
## behind other enemies, only when they're behind environmental things"). Every opaque thing that stands in the world
## writes a stencil value where it draws a pixel, and the last one drawn at a pixel is the nearest (each passes the depth
## test only in front of what is there), so after the opaque pass the stencil says what is nearest the camera there:
##   0          the sand, the water, the sky (nothing written)
##   1          a painting that is not scenery (PickupManager.PAINTING_STENCIL: every creature, the hero, a power-up, a
##              flower; enemy_billboard and sprite_billboard)
##   VALUE (4)  scenery: the painted props (prop_billboard), the signs (sign_depth), the boundary wall and the cliffs
##              (mark / mark_tree on their StandardMaterial3Ds)
##   STRUCTURE (5)  the scenery the stage's filter darkens less (pass 105): the painted structures and the portal
##              (BillboardSprite.scenery, scenery_shader), a structure's model, the barrels
## A creature's outline (enemy_silhouette.gdshader, its see-through second pass) draws only where the stencil is VALUE or
## above (`compare_less_or_equal, VALUE`: VALUE <= the stencil): a creature hidden by a cactus, a structure, a barrel, a
## sign or the wall is outlined; one hidden by another creature (or by the hero) is not. The gems, the coins and their
## glints draw only where it is 0 (under every painting and every piece of scenery). Stencil tests cost nothing
## measurable; no extra draw.
## Pass 105 (lane LOOK): the values moved (scenery 2 -> 4, structures 5) so the stage's filter can tell the structures,
## the weapons' models (StageStencil.ITEM 2) and the shots and chests (StageStencil.CLEAR 3) apart; the whole table is in
## StageStencil's header.
class_name SceneryStencil
extends RefCounted

const VALUE := 4
## Pass 105 (lane LOOK): the structures, the portal and the barrels: scenery the stage's filter darkens less.
const STRUCTURE := 5

static var _shader_cache: Dictionary = {}


## `m` marked as scenery (a BaseMaterial3D: custom stencil, write, always, `value`: VALUE or STRUCTURE) and returned; a
## ShaderMaterial is returned as it is (its shader says what it writes), and so is a see-through material (it draws after
## the outlines' stencil is read, and the water must never outline what wades in it).
static func mark(m: Material, value: int = VALUE) -> Material:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and b.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			return m
		b.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		b.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
		b.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
		b.stencil_reference = value
	return m


## Whether `m` writes the scenery's stencil `value` (tests, tools).
static func is_marked(m: Material, value: int = VALUE) -> bool:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return b.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM and (b.stencil_flags & BaseMaterial3D.STENCIL_FLAG_WRITE) != 0 and b.stencil_compare == BaseMaterial3D.STENCIL_COMPARE_ALWAYS and b.stencil_reference == value
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		return (m as ShaderMaterial).shader.code.contains("stencil_mode write, compare_always, %d;" % value)
	return false


## Every opaque BaseMaterial3D drawn under `root` (root included) marked as scenery: a material override, a surface's
## override, a mesh's own surface material and a primitive mesh's material. A material loaded from a file (a GLB's) is
## copied first and the copy set on this node, so the shared resource stays as it was for anyone else who draws it.
## Returns `root`. `value`: VALUE (scenery) or STRUCTURE (pass 105).
static func mark_tree(root: Node, value: int = VALUE) -> Node:
	if root == null:
		return root
	var nodes: Array = [root]
	nodes.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for n in nodes:
		if not (n is GeometryInstance3D):
			continue
		var g := n as GeometryInstance3D
		if g.material_override != null:
			g.material_override = _own(g.material_override, value)
			continue
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			continue
		# pass 105 (lane LOOK): a MultiMesh drawing a file's materials (the barrels' hoops, a GLB's) gets a copy of its mesh
		# wearing marked copies (it has no per-surface override; the hoops wrote no stencil at all before)
		if g is MultiMeshInstance3D and mesh is ArrayMesh and _has_file_material(mesh):
			var copy := (mesh as ArrayMesh).duplicate() as ArrayMesh
			for s2 in range(copy.get_surface_count()):
				var fm: Material = copy.surface_get_material(s2)
				if fm != null:
					copy.surface_set_material(s2, _own(fm, value))
			(g as MultiMeshInstance3D).multimesh.mesh = copy
			continue
		if mesh is PrimitiveMesh:
			var pm := mesh as PrimitiveMesh
			if pm.material != null and pm.material.resource_path == "":
				mark(pm.material, value)
				continue
		for s in range(mesh.get_surface_count()):
			if g is MeshInstance3D:
				var mi := g as MeshInstance3D
				var o: Material = mi.get_surface_override_material(s)
				if o != null:
					mi.set_surface_override_material(s, _own(o, value))
				else:
					var sm: Material = mesh.surface_get_material(s)
					if sm != null:
						mi.set_surface_override_material(s, _own(sm, value))
			else:
				# a MultiMesh has no per-surface override: its mesh's material, copied when it came from a file
				var sm2: Material = mesh.surface_get_material(s)
				if sm2 != null and sm2.resource_path == "":
					mark(sm2, value)
	return root


## Whether one of `mesh`'s surfaces wears a file's material (pass 105).
static func _has_file_material(mesh: Mesh) -> bool:
	for s in range(mesh.get_surface_count()):
		var m: Material = mesh.surface_get_material(s)
		if m is BaseMaterial3D and m.resource_path != "":
			return true
	return false


## `m` marked, or a marked copy of it when it is a file's (shared) resource.
static func _own(m: Material, value: int = VALUE) -> Material:
	if m is BaseMaterial3D and m.resource_path != "":
		return mark(m.duplicate(), value)
	return mark(m, value)


## The scenery copy of a painting's shader (pass 72): `base`'s code with its stencil write set to `value` (the painted
## structures and the portal draw through sprite_billboard.gdshader, the hero's shader, which writes
## PickupManager.PAINTING_STENCIL; since pass 105 they write STRUCTURE). Built once per shader and value and shared;
## `base` itself when it writes no stencil.
static func scenery_shader(base: Shader, value: int = VALUE) -> Shader:
	if base == null:
		return base
	var key := "%s|%d" % [base.resource_path if base.resource_path != "" else str(base.get_instance_id()), value]
	if _shader_cache.has(key):
		return _shader_cache[key]
	var from := "stencil_mode write, compare_always, %d;" % PickupManager.PAINTING_STENCIL
	if not base.code.contains(from):
		push_warning("SceneryStencil: %s writes no painting stencil" % key)
		return base
	var s := Shader.new()
	s.code = base.code.replace(from, "stencil_mode write, compare_always, %d;" % value)
	_shader_cache[key] = s
	return s
