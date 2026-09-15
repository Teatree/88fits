## Scatters the map's structures (content/structures) at run start and runs their interaction: stand inside the ring
## for `interact_time` seconds and a draped pie fills up on the ground; leave and it drains. At full, the effect fires
## once and the structure goes grey. Positions avoid the start clearing, obstacles and each other, so finding them
## means crossing the map.
class_name StructureManager
extends Node3D

var game: Node
var map: MapBase
var items: Array = []   # Structure nodes
var _rng := RandomNumberGenerator.new()


class Structure:
	extends Node3D
	var def: StructureDef
	var progress := 0.0
	var used := false
	var ring: MeshInstance3D
	var pie: MeshInstance3D
	var hand: MeshInstance3D
	var glow: OmniLight3D
	var visual: Node3D
	var _t := 0.0
	var _last_frac := -1.0


func setup(p_game: Node, p_map: MapBase, plan: Dictionary) -> void:
	game = p_game
	map = p_map
	_rng.randomize()
	var count := int(plan.get("count", 8))
	var spacing := float(plan.get("min_spacing", 16.0))
	var roster: Array = plan.get("roster", [])
	var defs: Array = []
	if roster.is_empty():
		defs = Registry.structures.values()
	else:
		for id in roster:
			var d: StructureDef = Registry.structure(str(id))
			if d:
				defs.append(d)
	if defs.is_empty() or count <= 0:
		return
	var placed: Array = []
	var tries := 0
	while placed.size() < count and tries < count * 60:
		tries += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(map.arena_radius * 0.3, map.arena_radius * 0.86)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var fc := map.flats_center
		if Vector2(p.x - fc.x, p.z - fc.z).length() < 18.0:
			continue
		var ok := true
		for q: Vector3 in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < spacing:
				ok = false
				break
		if ok:
			for o: Vector3 in map.obstacles:
				if Vector2(p.x - o.x, p.z - o.y).length() < o.z + 3.5:
					ok = false
					break
		if not ok:
			continue
		p.y = map.height_at(p.x, p.z)
		placed.append(p)
	for p: Vector3 in placed:
		var def: StructureDef = _pick(defs)
		_spawn(def, p)


func _pick(defs: Array) -> StructureDef:
	var total := 0.0
	for d: StructureDef in defs:
		total += maxf(d.weight, 0.01)
	var x := _rng.randf() * total
	for d: StructureDef in defs:
		x -= maxf(d.weight, 0.01)
		if x <= 0.0:
			return d
	return defs[0]


func _spawn(def: StructureDef, at: Vector3) -> void:
	var s := Structure.new()
	s.def = def
	add_child(s)
	s.global_position = at
	# the landmark itself
	var path := "res://art/props/%s.glb" % def.prop
	if def.prop != "" and ResourceLoader.exists(path):
		s.visual = (load(path) as PackedScene).instantiate()
	else:
		s.visual = _fallback_visual(def)
	s.add_child(s.visual)
	s.visual.rotation.y = _rng.randf() * TAU
	# the ring on the ground, in the structure's colour, always visible until used
	var tg: Telegraphs = game.telegraphs
	s.ring = MeshInstance3D.new()
	s.ring.mesh = tg.draped_ring(at, def.radius - 0.22, def.radius)
	s.ring.material_override = _mat(def.color, 0.75)
	s.ring.top_level = true
	add_child(s.ring)
	s.pie = MeshInstance3D.new()
	s.pie.material_override = _mat(def.color, 0.62)
	s.pie.top_level = true
	s.pie.visible = false
	add_child(s.pie)
	# a dark clock hand on the leading edge of the wedge, so the fill reads even where the colour matches the ground
	s.hand = MeshInstance3D.new()
	s.hand.material_override = _mat(Color(0.08, 0.06, 0.1), 0.9)
	s.hand.top_level = true
	s.hand.visible = false
	add_child(s.hand)
	s.glow = OmniLight3D.new()
	s.glow.light_color = def.color
	s.glow.omni_range = 5.0
	s.glow.light_energy = 1.1
	s.glow.position.y = def.height * 0.7
	s.add_child(s.glow)
	items.append(s)


func _mat(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## A stand-in when the GLB is missing: a plinth with a coloured shape on top, so the game never breaks on art.
func _fallback_visual(def: StructureDef) -> Node3D:
	var root := Node3D.new()
	var plinth := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.8
	cm.bottom_radius = 1.0
	cm.height = 0.5
	plinth.mesh = cm
	plinth.position.y = 0.25
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.45, 0.42, 0.4)
	plinth.material_override = pm
	root.add_child(plinth)
	var top := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, def.height - 0.5, 0.9)
	top.mesh = bm
	top.position.y = 0.5 + (def.height - 0.5) * 0.5
	var tm := StandardMaterial3D.new()
	tm.albedo_color = def.color
	tm.emission_enabled = true
	tm.emission = def.color
	tm.emission_energy_multiplier = 0.4
	top.material_override = tm
	root.add_child(top)
	return root


func _process(delta: float) -> void:
	if game == null or game.paused or game.player == null or game.player.dead:
		return
	var pp: Vector3 = game.player.global_position
	var tg: Telegraphs = game.telegraphs
	for s: Structure in items:
		if s.used:
			continue
		s._t += delta
		var d: float = Vector2(pp.x - s.global_position.x, pp.z - s.global_position.z).length()
		var inside: bool = d < s.def.radius
		if inside:
			s.progress = minf(s.progress + delta / maxf(s.def.interact_time, 0.1), 1.0)
		else:
			s.progress = maxf(s.progress - delta * 0.6, 0.0)
		# the ring breathes; the pie shows how far along the hero is
		var rm := s.ring.material_override as StandardMaterial3D
		rm.albedo_color.a = 0.55 + 0.3 * absf(sin(s._t * 2.5))
		s.glow.light_energy = 0.9 + 0.5 * absf(sin(s._t * 2.5)) + (1.5 if inside else 0.0)
		if s.progress > 0.0:
			var frac := snappedf(s.progress, 0.02)
			if frac != s._last_frac:
				s._last_frac = frac
				s.pie.mesh = tg.draped_sector(s.global_position, s.def.radius * 0.96, frac)
				var ang := -PI * 0.5 + TAU * frac
				s.hand.mesh = tg.draped_strip(s.global_position, Vector3(cos(ang), 0, sin(ang)), s.def.radius * 0.96, 0.16)
			s.pie.visible = true
			s.hand.visible = true
		else:
			s.pie.visible = false
			s.hand.visible = false
		if s.progress >= 1.0:
			_use(s)


func _use(s: Structure) -> void:
	s.used = true
	s.pie.visible = false
	s.hand.visible = false
	s.ring.visible = false
	s.glow.light_energy = 0.0
	_grey_out(s.visual)
	game.use_structure(s.def, s.global_position)


func _grey_out(n: Node) -> void:
	if n is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.4, 0.4)
		mat.roughness = 1.0
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_grey_out(c)


func used_count() -> int:
	var n := 0
	for s: Structure in items:
		if s.used:
			n += 1
	return n
