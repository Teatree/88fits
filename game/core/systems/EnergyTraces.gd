## The Golden Revolver's lines (pass 35): every shot of a weapon with params.trace leaves its path hanging in the air as a
## line of golden energy for `seconds`. A creature that walks into one takes `frac` of the shot's damage, and again every
## `tick` seconds while it stays in it. ProjectileManager owns this: start() when the shot leaves, follow() as it flies
## (a point every metre and a half, so the line keeps to the ground the shot kept to), seal() when it is gone. Drawn as
## flat ribbons in one ImmediateMesh: a wide soft glow and a hot core, flickering, fading out at the end.
class_name EnergyTraces
extends Node3D

const MAX_LINES := 48
const STEP := 1.5
const COLOR := Color(1.0, 0.8, 0.32)

var game: Node
var lines: Array = []   # {pts: PackedVector3Array, head, w, dmg, width, left, total, tick, hits: {creature: next time}}
var _mesh: ImmediateMesh
var _mi: MeshInstance3D
var _clock := 0.0
var _scan := 0.0


func _ready() -> void:
	Lockstep.join(self)
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.material_override = Fx.glow_ribbon_material()
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.custom_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	add_child(_mi)


func start(from: Vector3, w: WeaponInstance, shot_damage: float) -> Dictionary:
	var cfg: Dictionary = w.params.get("trace", {}) if w else {}
	var secs := float(cfg.get("seconds", 3.0))
	var pts := PackedVector3Array()
	pts.append(from)
	var ln := {"pts": pts, "head": from, "w": w, "dmg": shot_damage * float(cfg.get("frac", 0.35)), "width": float(cfg.get("width", 0.45)),
			"left": secs, "total": secs, "tick": maxf(float(cfg.get("tick", 0.5)), 0.1), "hits": {}}
	lines.append(ln)
	if lines.size() > MAX_LINES:
		lines.pop_front()
	return ln


func follow(ln: Dictionary, at: Vector3) -> void:
	ln["head"] = at
	var pts: PackedVector3Array = ln["pts"]
	if pts[pts.size() - 1].distance_to(at) >= STEP:
		pts.append(at)
		ln["pts"] = pts


func seal(ln: Dictionary) -> void:
	var pts: PackedVector3Array = ln["pts"]
	var head: Vector3 = ln["head"]
	if pts[pts.size() - 1].distance_to(head) > 0.05:
		pts.append(head)
		ln["pts"] = pts


func clear() -> void:
	lines.clear()
	_mesh.clear_surfaces()


func _physics_process(delta: float) -> void:
	# pass 114 (lane REPLAY): a replay's driver runs these steps itself (Lockstep)
	if Lockstep.phys_skip():
		return
	if game == null or lines.is_empty():
		return
	_clock += delta
	for k in range(lines.size() - 1, -1, -1):
		var ln: Dictionary = lines[k]
		ln["left"] = float(ln["left"]) - delta
		if float(ln["left"]) <= 0.0:
			lines.remove_at(k)
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.1
	var em: EnemyManager = game.enemies
	for ln: Dictionary in lines:
		var pts: PackedVector3Array = ln["pts"]
		var head: Vector3 = ln["head"]
		var w: WeaponInstance = ln["w"]
		var wid := w.def.id if w else ""
		var hits: Dictionary = ln["hits"]
		var half: float = float(ln["width"]) * 0.5
		for s in range(pts.size()):
			var a: Vector3 = pts[s]
			var b: Vector3 = pts[s + 1] if s + 1 < pts.size() else head
			var ab := Vector3(b.x - a.x, 0.0, b.z - a.z)
			var l := ab.length()
			if l < 0.1:
				continue
			var dir := ab / l
			for e in em.indices_in_radius((a + b) * 0.5, l * 0.5 + half + 0.6):
				if float(hits.get(e, -1.0)) > _clock:
					continue
				var d := Vector3(em.pos[e].x - a.x, 0.0, em.pos[e].z - a.z)
				var along := d.dot(dir)
				if along < 0.0 or along > l:
					continue
				if (d - dir * along).length() > half + em.radius[e]:
					continue
				hits[e] = _clock + float(ln["tick"])
				if em.damage(e, float(ln["dmg"]), wid, Vector3.ZERO, 0.0) and w:
					w.kills += 1
				game.fx.burst(em.pos[e] + Vector3(0, 0.6, 0), COLOR, 0.35)


func _process(_delta: float) -> void:
	if lines.is_empty():
		if _mi.visible:
			_mesh.clear_surfaces()
			_mi.visible = false
		return
	_mesh.clear_surfaces()
	# the surface opens with the first ribbon (pass 48): lines whose every piece is too short to draw (a round that ended
	# where it left, a ricochet's first hop) left an empty surface, which the engine refuses
	var begun := false
	var k := 0
	for ln: Dictionary in lines:
		k += 1
		var left: float = ln["left"]
		var age: float = float(ln["total"]) - left
		# a white-hot flash as it is laid, a steady flicker, and out over the last 0.6 s
		var a := clampf(left / 0.6, 0.0, 1.0) * (0.85 + 0.15 * sin(_clock * 31.0 + float(k) * 1.7)) * (1.0 + 0.8 * clampf(1.0 - age / 0.2, 0.0, 1.0))
		var width: float = ln["width"]
		var pts: PackedVector3Array = ln["pts"]
		var head: Vector3 = ln["head"]
		for s in range(pts.size()):
			var p0: Vector3 = pts[s]
			var p1: Vector3 = pts[s + 1] if s + 1 < pts.size() else head
			if p0.distance_squared_to(p1) < 0.0004:
				continue
			if not begun:
				_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				begun = true
			_ribbon(p0, p1, width, Color(COLOR.r, COLOR.g * 0.9, COLOR.b * 0.7, 0.32 * a))
			_ribbon(p0, p1, width * 0.28, Color(1.0, 0.95, 0.75, 0.9 * a))
	if begun:
		_mesh.surface_end()
	_mi.visible = begun


func _ribbon(p0: Vector3, p1: Vector3, width: float, col: Color) -> void:
	var d := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	var side := Vector3(-d.z, 0.0, d.x) * width * 0.5
	var edge := Color(col.r, col.g, col.b, 0.0)
	# soft at both edges, bright down the middle: two quads a side
	for sgn: float in [1.0, -1.0]:
		var o := side * sgn
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(p0)
		_mesh.surface_add_vertex(p1)
		_mesh.surface_set_color(edge)
		_mesh.surface_add_vertex(p1 + o)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(p0)
		_mesh.surface_set_color(edge)
		_mesh.surface_add_vertex(p1 + o)
		_mesh.surface_add_vertex(p0 + o)
