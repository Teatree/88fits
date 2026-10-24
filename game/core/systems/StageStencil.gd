## What the stage's filter darkens, by the stencil each opaque thing writes (pass 105, lane LOOK; Garry, Stage 2 and 3:
## "Structures should not be darkened like the rest of the environment. The effect of darkening should be there, but
## quite a bit less. Item 3d objects should not be so dimmed ... Some Projectiles are darkened as well. Make it so they
## aren't at all ... Barrels should be highlighted a bit as well. Enemy projectiles aren't visible as well. Chests aren't
## visible either."). After the opaque pass the stencil at a pixel is the value the nearest opaque thing wrote there
## (each writes only where it passes the depth test), and StageLook's quads (core/shaders/stage_filter.gdshader) multiply
## each value by its own factor:
##   0 SAND       the sand, the water, the sky and anything that writes nothing   the filter at its strength
##   1 ACTOR      the creatures, the hero, power-ups, flowers (PickupManager.PAINTING_STENCIL)   x `actors` (0.35)
##   2 ITEM       the weapons' own models: held guns, companions, orbiters, mines, the turret, the Salt, the decoy,
##                the trampoline, and what a weapon behaviour draws itself                      x `items` (0: none)
##   3 CLEAR      every shot of the ProjectileManager (the hero's and the creatures': spit, pellets, spikes, shards,
##                harpoons, the Raider's rocket, the dynamite, the King's tumbleweeds), boulders, bomblets, boss attacks'
##                projectiles, the Tarantula Hawk, the chests, the falling Supply Drop            never darkened
##   4 SCENERY    props, signs, the wall, the cliffs (SceneryStencil.VALUE)                      the filter at its strength
##   5 STRUCTURE  the structures, the portal, the barrels (SceneryStencil.STRUCTURE)             x `structures` (0.3)
## A creature's outline reads 4 <= the stencil (scenery and structures), the gems and coins read 0: since a shot, a chest
## and a weapon's model now write their own value, a gem no longer draws over them and an outline no longer shows through
## them (before, they kept whatever lay behind them; the only change this makes to a stage without a filter).
##
## Who writes 2 and 3: a node tagged with META (tag(), or a class value_for() knows: WeaponBehavior, Mine, Turret, Decoy,
## Trampoline, Warmup -> ITEM; ProjectileManager, PickupManager, Chest, Boulder, Bomblets, BossAttackFx, TarantulaHawk ->
## CLEAR) marks every opaque material of every mesh under it (mark_tree): a BaseMaterial3D gets a custom stencil write, a
## ShaderMaterial a copy of its shader with `stencil_mode write, compare_always, V;`. A material already writing a stencil
## (the paintings, the scenery) and every see-through one (drawn after the filter, untinted already) are left alone. A
## file's material (a GLB's) is copied once per value and the copy shared, so parts that shared one still do. The game's
## StageStencil (of()) marks the tagged trees present when it starts, every mesh added under a tagged node afterwards (the
## tree's node_added, flushed once at the frame's end, so materials set after add_child are seen), and sweeps one tagged
## root every SWEEP_EVERY seconds for materials swapped later (a mutation's look). No draw call is added; the cost is a
## stencil write per pixel and a few material copies.
class_name StageStencil
extends Node

const SAND := 0
const ACTOR := 1
const ITEM := 2
const CLEAR := 3
const SCENERY := 4
const STRUCTURE := 5
const META := &"stage_stencil"
const NODE_NAME := "StageStencil"
## Seconds between two roots' sweeps (one root a sweep, round the list).
const SWEEP_EVERY := 0.1

var game: Node
var _roots: Array = []
var _pending: Array = []
var _flush_queued := false
var _sweep_t := 0.0
var _sweep_i := 0

## "<id>|<value>" -> [WeakRef to the source, its marked copy] (a file's material, a mesh of file materials)
static var _copies: Dictionary = {}
## "<shader id>|<value>" -> [WeakRef to the source shader, the copy that writes the value]
static var _shaders: Dictionary = {}


## The game's StageStencil, made on first use (a child of `game` named NODE_NAME).
static func of(p_game: Node) -> StageStencil:
	if p_game == null:
		return null
	var have := p_game.get_node_or_null(NODE_NAME)
	if have is StageStencil:
		return have
	var ss := StageStencil.new()
	ss.name = NODE_NAME
	ss.game = p_game
	p_game.add_child(ss)
	return ss


func _ready() -> void:
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	if game:
		_scan(game)


func _exit_tree() -> void:
	var tree := get_tree()
	if tree and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	prune()


## The copies whose source is gone forgotten (the run's own materials, at the game's end).
static func prune() -> void:
	for cache: Dictionary in [_copies, _shaders]:
		for key in cache.keys():
			var e = cache[key]
			if not (e is Array) or (e[0] as WeakRef).get_ref() == null:
				cache.erase(key)


## Every tagged root under `n` (n included) found, tagged and marked.
func _scan(n: Node) -> void:
	var v := value_for(n)
	if v >= 0:
		_adopt(n, v)
		mark_tree(n)
	for c in n.get_children():
		_scan(c)


func _adopt(n: Node, v: int) -> void:
	if not n.has_meta(META):
		n.set_meta(META, v)
	if not _roots.has(n):
		_roots.append(n)


func _on_node_added(n: Node) -> void:
	# every root class and every mesh is a Node3D: the UI, the sounds and the timers cost one test
	if not (n is Node3D):
		return
	var v := value_for(n)
	if v >= 0:
		_adopt(n, v)
		_queue(n)
	elif n is GeometryInstance3D and value_above(n) >= 0:
		_queue(n)


func _queue(n: Node) -> void:
	_pending.append(n)
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_flush_queued = false
	var list := _pending
	_pending = []
	for n in list:
		if is_instance_valid(n) and (n as Node).is_inside_tree():
			mark_tree(n)


func _process(delta: float) -> void:
	_sweep_t += delta
	if _sweep_t < SWEEP_EVERY or _roots.is_empty():
		return
	_sweep_t = 0.0
	# the next live root (a freed one, a shot that fell, is dropped on the way)
	while not _roots.is_empty():
		_sweep_i = _sweep_i % _roots.size()
		var r = _roots[_sweep_i]
		if not is_instance_valid(r):
			_roots.remove_at(_sweep_i)
			continue
		_sweep_i += 1
		if (r as Node).is_inside_tree():
			mark_tree(r)
		return


## The value a node's class carries (a root), -1 for none. A node's own META wins.
static func value_for(n: Node) -> int:
	if n == null:
		return -1
	if n.has_meta(META):
		return int(n.get_meta(META))
	if n is ProjectileManager or n is PickupManager or n is Chest or n is Boulder or n is Bomblets or n is BossAttackFx or n is TarantulaHawk:
		return CLEAR
	if n is WeaponBehavior or n is Mine or n is Turret or n is Decoy or n is Trampoline or n is Warmup:
		return ITEM
	return -1


## The value of the nearest tagged node at or above `n`, -1 when there is none.
static func value_above(n: Node) -> int:
	var p := n
	while p != null:
		if p.has_meta(META):
			return int(p.get_meta(META))
		p = p.get_parent()
	return -1


## `n` tagged with `value` (a root of its own: everything under it writes the value) and marked now.
static func tag(n: Node, value: int) -> void:
	if n == null:
		return
	n.set_meta(META, value)
	mark_tree(n)


## Every opaque material on every mesh under `root` (root included) writing the value of its nearest tagged node.
static func mark_tree(root: Node) -> void:
	if root == null:
		return
	var nodes: Array = []
	if root is GeometryInstance3D:
		nodes.append(root)
	nodes.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	for g in nodes:
		var v := value_above(g)
		if v == ITEM or v == CLEAR:
			mark_geometry(g, v)


## One mesh's materials marked: its override, its surfaces' (as overrides), a MultiMesh's mesh. Particles, labels and
## sprites are left alone (effects and paintings).
static func mark_geometry(g: GeometryInstance3D, value: int) -> void:
	if not (g is MeshInstance3D or g is MultiMeshInstance3D):
		return
	if g.material_override != null:
		var m := marked(g.material_override, value)
		if m != g.material_override:
			g.material_override = m
		return
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			return
		for s in range(mi.mesh.get_surface_count()):
			var cur: Material = mi.get_surface_override_material(s)
			if cur == null:
				cur = mi.mesh.surface_get_material(s)
			if cur == null:
				continue
			var m2 := marked(cur, value)
			if m2 != cur:
				mi.set_surface_override_material(s, m2)
	else:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return
		var mesh2 := marked_mesh(mm.mesh, value)
		if mesh2 != mm.mesh:
			mm.mesh = mesh2


## `mesh` with its surfaces' materials marked: the mesh itself when they need nothing or are its own (made in code, marked
## in place), else a copy wearing marked copies (one per mesh and value).
static func marked_mesh(mesh: Mesh, value: int) -> Mesh:
	var need_copy := false
	for s in range(mesh.get_surface_count()):
		var m: Material = mesh.surface_get_material(s)
		if m == null:
			continue
		var m2 := marked(m, value)
		if m2 != m:
			if mesh.resource_path == "" and mesh is ArrayMesh:
				(mesh as ArrayMesh).surface_set_material(s, m2)
			else:
				need_copy = true
	if mesh is PrimitiveMesh:
		var pm := mesh as PrimitiveMesh
		if pm.material != null:
			var pm2 := marked(pm.material, value)
			if pm2 != pm.material:
				if mesh.resource_path == "":
					pm.material = pm2
				else:
					need_copy = true
	if not need_copy:
		return mesh
	var key := "%d|%d" % [mesh.get_instance_id(), value]
	var have = _copies.get(key)
	if have is Array and (have[0] as WeakRef).get_ref() == mesh:
		return have[1]
	var out := mesh.duplicate() as Mesh
	if out is ArrayMesh:
		for s in range(out.get_surface_count()):
			var m3: Material = out.surface_get_material(s)
			if m3 != null:
				out.surface_set_material(s, marked(m3, value))
	elif out is PrimitiveMesh and (out as PrimitiveMesh).material != null:
		(out as PrimitiveMesh).material = marked((out as PrimitiveMesh).material, value)
	_copies[key] = [weakref(mesh), out]
	return out


## Whether `m` is drawn in the opaque pass (before the stage's filter), so the filter would darken it.
static func is_opaque(m: Material) -> bool:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var t := b.transparency
		if not (t == BaseMaterial3D.TRANSPARENCY_DISABLED or t == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or t == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH):
			return false
		return b.blend_mode == BaseMaterial3D.BLEND_MODE_MIX and not b.no_depth_test and b.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		return sh != null and shader_is_opaque(sh.code)
	return false


## A spatial shader's code drawn in the opaque pass: no blend but mix, depth drawn and tested, no ALPHA written (or written
## with a scissor threshold).
static func shader_is_opaque(code: String) -> bool:
	if not code.contains("shader_type spatial"):
		return false
	for word in ["blend_add", "blend_sub", "blend_mul", "blend_premul_alpha", "depth_draw_never", "depth_test_disabled"]:
		if code.contains(word):
			return false
	var re := RegEx.create_from_string("\\bALPHA\\s*(=[^=]|\\*=|\\+=|-=)")
	if re.search(code) != null and not code.contains("ALPHA_SCISSOR_THRESHOLD") and not code.contains("ALPHA_HASH_SCALE"):
		return false
	return true


## The stencil value `m` writes now: a BaseMaterial3D's custom write reference, a shader's `compare_always` write; -1 when
## it writes none (-2: a stencil it reads or writes some other way).
static func written(m: Material) -> int:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.stencil_mode == BaseMaterial3D.STENCIL_MODE_DISABLED:
			return -1
		if b.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM and (b.stencil_flags & BaseMaterial3D.STENCIL_FLAG_WRITE) != 0 and b.stencil_compare == BaseMaterial3D.STENCIL_COMPARE_ALWAYS:
			return b.stencil_reference
		return -2
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		var code := (m as ShaderMaterial).shader.code
		if not code.contains("stencil_mode"):
			return -1
		var re := RegEx.create_from_string("stencil_mode\\s+write\\s*,\\s*compare_always\\s*,\\s*(\\d+)\\s*;")
		var r := re.search(code)
		return int(r.get_string(1)) if r else -2
	return -1


## `m` writing `value` (ITEM or CLEAR): `m` itself when it is see-through, already writes a stencil of another kind (a
## painting, the scenery) or writes `value`; marked in place when it was made in code and writes nothing yet; else a copy
## (one per material and value: a file's material, or one already marked with the other of our two values).
static func marked(m: Material, value: int) -> Material:
	if m == null or not is_opaque(m):
		return m
	var w := written(m)
	if w == value:
		return m
	if w != -1 and w != ITEM and w != CLEAR:
		return m
	if w == -1 and m.resource_path == "":
		_mark_in_place(m, value)
		return m
	var key := "%d|%d" % [m.get_instance_id(), value]
	var have = _copies.get(key)
	if have is Array and (have[0] as WeakRef).get_ref() == m:
		return have[1]
	var c := m.duplicate() as Material
	_mark_in_place(c, value)
	_copies[key] = [weakref(m), c]
	return c


static func _mark_in_place(m: Material, value: int) -> void:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		b.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		b.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
		b.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
		b.stencil_reference = value
	elif m is ShaderMaterial:
		var sm := m as ShaderMaterial
		sm.shader = writing_shader(sm.shader, value)


## A copy of `base` that writes `value` where it draws (its own write line replaced when it has one of ours), built once
## per shader and value.
static func writing_shader(base: Shader, value: int) -> Shader:
	if base == null:
		return base
	var key := "%d|%d" % [base.get_instance_id(), value]
	var have = _shaders.get(key)
	if have is Array and (have[0] as WeakRef).get_ref() == base:
		return have[1]
	var code := base.code
	var line := "stencil_mode write, compare_always, %d;" % value
	var re := RegEx.create_from_string("stencil_mode\\s+write\\s*,\\s*compare_always\\s*,\\s*[23]\\s*;")
	if re.search(code) != null:
		code = re.sub(code, line)
	else:
		var at := code.find("shader_type spatial;")
		if at < 0:
			return base
		var end := at + "shader_type spatial;".length()
		code = code.substr(0, end) + "\n" + line + code.substr(end)
	var s := Shader.new()
	s.code = code
	_shaders[key] = [weakref(base), s]
	return s
