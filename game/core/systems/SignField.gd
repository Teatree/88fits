## Directional signs (pass 54, Garry: signposts round the map that point the way to the structures): four to six
## weathered wooden posts scattered by the run's seed, each with one to four arms pointing at the nearest structures.
## Pass 55 (Garry: "Remove the text from signs, just let them be pointers"): the arms carry no names (SHOW_NAMES); the
## tags pass 54 hung over them are still built when it is switched on. Once a structure is used, every arm that points at
## it goes a shade paler: the arm stays, blank and weathered.
## Placed after the structures and before the barrels (Game._ready): clear of the flats, the start, the water, the
## obstacles, the structures' rings and every painting's cover band (BarrelField.covers_of), at least 25 m apart (15 m
## once the map fights back). Each post is a thin collider and an obstacle circle, so the creatures steer round it and
## the barrels, the flowers and the teleport keep clear of it.
## Drawn as nodes (at most 6 posts and 24 arms, no shadows) from art/props/sign.glb (`Post`, `Arm`; tools/blender_sign.py),
## or from meshes built here while the model is missing; the materials are set here by the surfaces' names.
## Pass 60 (Garry: "Hero should render above the road sign, unless the hero is north of it, in that case it should render
## below"): every post and arm wears core/shaders/sign_depth.gdshader, which draws it where it is but at the depth of
## the sign's foot, so a sign sorts against the hero, the creatures and the props the way two paintings do (south over
## north). One set of materials per sign (`foot` is a uniform), cut from the shared templates (_mats).
class_name SignField
extends Node3D

const COUNT_MIN := 4
const COUNT_MAX := 6
const MIN_GAP := 25.0
const MIN_GAP_RELAXED := 15.0
const RELAX_AFTER := 2000
const TRIES := 6000
## the band of the arena a post may stand in, as fractions of its radius
const R_MIN := 0.2
const R_MAX := 0.9
const FLATS_CLEAR := 0.6      # x the flats' radius
const START_CLEAR := 6.0
const OBSTACLE_CLEAR := 1.2   # past an obstacle circle's own radius
const STRUCTURE_CLEAR := 2.5  # past a structure's ring
const MAX_ARMS := 4
## two arms of one sign point at least this far apart (pass 54, the lead: arms pointing the same way stacked their names into
## one blot from the run's camera, and a real sign would not carry two boards for one road); a structure that lies within
## it of a nearer one's arm is left to another sign
const ARM_APART_DEG := 35.0
## each arm's height up the post, the first (the nearest structure's) at the bottom
const ARM_HEIGHTS := [1.55, 1.85, 2.15, 2.45]
## the boards lean up and down by this much in turn, the way an old sign weathers; two arms pointing within
## SAME_WAY_DEG of each other lean the same way, so stacked boards never cross
const TILT_DEG := 8.0
const SAME_WAY_DEG := 30.0
## the whole sign's size on screen (the post and the arms; the collider and the steering circle keep theirs): 1.0 is the
## model's 2.6 m post. Pass 54 (the lead, by eye on the phone's canvas): at 1.0 the sign was a twig among the props and its
## burnt names about 5 px tall; 1.45 makes it a landmark (a 3.8 m post) and the names are drawn as tags (LABEL_* below)
const SCALE := 1.45
## Pass 61 (Garry: "Sign boards should be more tall. As in stretch them on the z axis"): the drawn sign is stretched up by
## this much on top of SCALE, the post and its boards both (Blender's z is Godot's y), their widths and the post's
## thickness unchanged: a 3.8 m post becomes a tall roadside one and every board a deeper board. Only the Look node is
## stretched: the collider, the steering circle, the arms' pointing and heights up the post (in the model's units) and
## the depth trick (sign_depth.gdshader, any vertex at its foot's depth) are as before; a board's lean is set so it still
## reads TILT_DEG after the stretch (tilt_for), and a name tag is unstretched (it is type, not wood).
const STRETCH := 1.4
const POST_H := 2.6
const POST_W := 0.14
const POST_R := 0.12          # the collider
const OBSTACLE_R := 0.2       # the steering circle (the collider plus the scenery's 0.08 m padding)
## the arm (tools/blender_sign.py): its root past the post's axis, the tip, the pointed end, the board's height and depth
const ARM_X0 := -0.12
const ARM_X1 := 0.78
const ARM_TIP := 0.14
const ARM_H := 0.16
const ARM_T := 0.05
## the name: a tag that always faces the camera (pass 54: the run's camera looks down the screen, so a board pointing up
## or down the screen is seen edge on and a name burnt into it could never be read), ink type with a paper edge, LABEL_EM
## metres tall (about 30 px on the 1080 x 1920 canvas at the run's nearest zoom), hung just past its arm's point
## (LABEL_X along the arm, before SCALE), so the names of one sign spread out the ways they point, and pulled LABEL_PULL
## metres towards the camera so its own board never hides it
## pass 55: off, the arms point and say nothing (the record keeps its structure's word in "text")
const SHOW_NAMES := false
const LABEL_EM := 0.34
const LABEL_FONT_PX := 64
const LABEL_OUTLINE_PX := 14
const LABEL_X := 0.95
const LABEL_PULL := 0.25
const PAPER := Color(0.93, 0.87, 0.76)
const POLL := 0.5             # seconds between looks at the structures
const FADE := 0.8
## one sign drawn this far under the hero for the first seconds (Warmup's pit), so its materials and its type compile
## under the spawn beam rather than the first time a sign comes into view
const WARM_PIT := Vector3(0, -8.0, 0)
const WARM_SECONDS := 1.5
const INK := Color(0.12, 0.08, 0.05)
const POST_COLOR := Color(0.329, 0.235, 0.149)      # (84, 60, 38)
const WOOD := Color(0.588, 0.463, 0.314)            # (150, 118, 80)
const WOOD_SPENT := Color(0.69, 0.60, 0.49)         # a shade paler and greyer, once its structure is used
const RIM := Color(0.392, 0.298, 0.196)             # (100, 76, 50)
const NAIL := Color(0.157, 0.133, 0.118)            # (40, 34, 30)
## the word each structure's arm carries; any other kind shows the first word of its name
const SHORT := {
	"teleport": "TELEPORT",
	"uber_magnet": "MAGNET",
	"gold_bank": "BANK",
	"hooded_figure": "STRANGER",
	"healing_well": "WELL",
	"loot_cache": "CACHE",
	"shop": "SHOP",
	"war_drum": "DRUM",
	"beacon": "BEACON",
	"totem_pole": "TOTEM",
}
const MODEL := "res://art/props/sign.glb"
## this script (spawn makes a field without naming its own class, which a fresh class is not registered as until the
## editor's next scan)
const SELF := "res://core/systems/SignField.gd"
const FONT := "res://ui/fonts/AlfaSlabOne-Regular.ttf"
## the depth material every post and arm wears (pass 60): drawn in place, sorted at the sign's foot
const DEPTH_SHADER := "res://core/shaders/sign_depth.gdshader"

var game: Node
var map: Node
## each post's foot on the ground
var spots: PackedVector3Array = PackedVector3Array()
## one record per arm: {sign (index), structure, node (MeshInstance3D), labels [front, back], text, yaw, tilt, height,
## blank}
var arms: Array = []
var _rng := RandomNumberGenerator.new()
var _poll_t := 0.0
## the template materials by surface name, and each sign's own copies by its foot ({Vector3: {name: material}})
var _mats: Dictionary = {}
var _sign_mats: Dictionary = {}
var _font: Font


## A field named "Signs" under `p_game`, set up on `p_map` (the one line Game._ready calls, through preload).
static func spawn(p_game: Node, p_map: Node) -> Node3D:
	var f: Node3D = (load(SELF) as GDScript).new()
	f.name = "Signs"
	p_game.add_child(f)
	f.setup(p_game, p_map)
	return f


## Places the posts and builds them; `meshes` ({post, arm}) stands in for the model (a tool that loads the GLB itself).
func setup(p_game: Node, p_map: Node, meshes: Dictionary = {}) -> void:
	game = p_game
	map = p_map
	_rng.seed = Run.map_seed * 29 + 3
	if map == null or structures().is_empty():
		return
	_place()
	if spots.is_empty():
		return
	var m: Dictionary = meshes if meshes.has("post") and meshes.has("arm") else _meshes()
	_make_materials()
	for k in spots.size():
		_build_sign(k, m)
	_warm(m)


## A post, an arm with its name and a spent arm in the pit under the hero for WARM_SECONDS (the Compatibility renderer
## compiles a material the first time it is drawn: a hitch on a phone).
func _warm(meshes: Dictionary) -> void:
	if arms.is_empty() or not is_inside_tree():
		return
	var hero = game.get("player") if game != null else null
	var at: Vector3 = (hero as Node3D).global_position if hero is Node3D else (map.player_start() if map.has_method("player_start") else Vector3.ZERO)
	var warm := Node3D.new()
	warm.name = "Warm"
	add_child(warm)
	warm.global_position = at + WARM_PIT
	for key in ["post", "arm"]:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_paint(mi, false, warm.global_position)
		warm.add_child(mi)
		if key == "arm":
			# the spent wood too, and the names as the arms carry them
			var spent := MeshInstance3D.new()
			spent.mesh = meshes[key]
			spent.position.y = 0.4
			_paint(spent, true, warm.global_position)
			warm.add_child(spent)
			if SHOW_NAMES:
				mi.add_child(_label(str(arms[0]["text"])))
	get_tree().create_timer(WARM_SECONDS, true, false, true).timeout.connect(warm.queue_free)


## The structures the arms can point at (StructureManager.items).
func structures() -> Array:
	return BarrelField.structures_of(game)


## The posts' spots, by the run's seed: COUNT_MIN to COUNT_MAX of them, each clear (spot_clear) and MIN_GAP from the
## others (MIN_GAP_RELAXED after RELAX_AFTER tries). Fewer when the map has no room.
func _place() -> void:
	var count := _rng.randi_range(COUNT_MIN, COUNT_MAX)
	var covers: Array = BarrelField.covers_of(game, map)
	var rings: Array = BarrelField.structure_rings(game)
	var radius := float(map.get("arena_radius")) if map.get("arena_radius") != null else 66.0
	var tries := 0
	while spots.size() < count and tries < TRIES:
		tries += 1
		var gap := MIN_GAP if tries <= RELAX_AFTER else MIN_GAP_RELAXED
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(radius * R_MIN, radius * R_MAX)
		var p := Vector2(cos(a) * r, sin(a) * r)
		if not spot_clear(p, covers, rings):
			continue
		var ok := true
		for q in spots:
			if p.distance_to(Vector2(q.x, q.z)) < gap:
				ok = false
				break
		if ok:
			spots.append(Vector3(p.x, _height(p.x, p.y), p.y))


## Could a post stand at `p` (x, z)? Clear of the flats, the start, the water, the obstacle circles, the structures'
## rings (`rings`, BarrelField.structure_rings) and the paintings' cover bands (`covers`, BarrelField.covers_of).
func spot_clear(p: Vector2, covers: Array, rings: Array) -> bool:
	var fc3 = map.get("flats_center")
	var fc := Vector2(fc3.x, fc3.z) if fc3 is Vector3 else Vector2.ZERO
	var flats_r := float(map.get("flats_radius")) if map.get("flats_radius") != null else 16.0
	if p.distance_to(fc) < flats_r * FLATS_CLEAR:
		return false
	if map.has_method("player_start"):
		var st: Vector3 = map.player_start()
		if p.distance_to(Vector2(st.x, st.z)) < START_CLEAR:
			return false
	if map.has_method("in_water") and map.in_water(Vector3(p.x, 0, p.y)):
		return false
	var obstacles = map.get("obstacles")
	if obstacles is Array:
		for o: Vector3 in obstacles:
			if p.distance_to(Vector2(o.x, o.y)) < o.z + OBSTACLE_CLEAR:
				return false
	for g: Vector3 in rings:
		if p.distance_to(Vector2(g.x, g.y)) < g.z + STRUCTURE_CLEAR:
			return false
	return not BarrelField.in_cover(covers, p, POST_R)


func _height(x: float, z: float) -> float:
	return map.height_at(x, z) if map.has_method("height_at") else 0.0


## The nearest `n` structures to `at` that are not used yet, nearest first; with `apart_deg` a structure whose bearing lies
## within that many degrees of one already chosen is skipped (the sign's arms, ARM_APART_DEG).
func nearest_unused(at: Vector3, n: int, apart_deg: float = 0.0) -> Array:
	var pool: Array = []
	for s in structures():
		if bool(s.get("used")):
			continue
		var sp := BarrelField.structure_position(s)
		pool.append([Vector2(sp.x - at.x, sp.z - at.z).length(), s])
	pool.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	var yaws: Array = []
	# pass 73: arms taken per kind, for a kind with `params.per_sign` (per_sign_cap)
	var kinds: Dictionary = {}
	for item in pool:
		if out.size() >= n:
			break
		var s: Node = item[1]
		var cap := per_sign_cap(s)
		var kid := str(s.get("def").get("id")) if s.get("def") != null else ""
		if cap >= 0 and int(kinds.get(kid, 0)) >= cap:
			continue
		var yaw := yaw_to(at, BarrelField.structure_position(s))
		var clear := true
		for y in yaws:
			if absf(rad_to_deg(angle_difference(float(y), yaw))) < apart_deg:
				clear = false
				break
		if clear:
			out.append(s)
			yaws.append(yaw)
			kinds[kid] = int(kinds.get(kid, 0)) + 1
	return out


## How many arms of one sign may point at structures of `s`'s kind (pass 73, the Totem Poles, Garry: "Signs show to them
## as well"): its JSON's `params.per_sign`, -1 (no cap) without one. Ten to twelve poles stand on a map, so without a cap
## the nearest-first arms would point at little else.
static func per_sign_cap(s: Node) -> int:
	var d = s.get("def") if s != null else null
	if d == null or not d.get("params") is Dictionary:
		return -1
	return int((d.get("params") as Dictionary).get("per_sign", -1))


## The heading an arm modelled along +X takes to point from `from` at `to`: a turn about the post (yaw) such that
## Basis(UP, yaw) * +X runs along the ground from one to the other.
static func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.z - from.z), to.x - from.x)


## A structure's short name for its arm.
static func short_name(s: Node) -> String:
	var d = s.get("def") if s != null else null
	if d == null:
		return ""
	var id := str(d.get("id"))
	if SHORT.has(id):
		return SHORT[id]
	var words := str(d.get("display_name")).strip_edges().split(" ", false)
	return words[0].to_upper() if words.size() > 0 else id.to_upper()


func _build_sign(k: int, meshes: Dictionary) -> void:
	var at := spots[k]
	var stand := Node3D.new()
	stand.name = "Sign%d" % k
	stand.position = at
	add_child(stand)
	# the sign's foot in the world: the depth every post and arm is drawn at (pass 60)
	var foot: Vector3 = stand.global_position if stand.is_inside_tree() else at
	# what is drawn, under one node SCALE sizes (the collider beside it is never scaled)
	var look := Node3D.new()
	look.name = "Look"
	look.scale = Vector3(SCALE, SCALE * STRETCH, SCALE)
	stand.add_child(look)
	var post := MeshInstance3D.new()
	post.name = "Post"
	post.mesh = meshes["post"]
	post.rotation.y = _rng.randf() * TAU
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_paint(post, false, foot)
	look.add_child(post)
	# a thin collider the hero bumps, and a circle the crowd steers round (the barrels placed next keep clear of it)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = POST_R
	shape.height = POST_H
	cs.shape = shape
	cs.position.y = POST_H * 0.5
	body.add_child(cs)
	stand.add_child(body)
	var obstacles = map.get("obstacles")
	if obstacles is Array:
		(obstacles as Array).append(Vector3(at.x, at.z, OBSTACLE_R))
	var want := _rng.randi_range(1, MAX_ARMS)
	var targets := nearest_unused(at, want, ARM_APART_DEG)
	var lean := 1.0
	var prev_yaw := 0.0
	for j in targets.size():
		var s: Node3D = targets[j]
		var yaw := yaw_to(at, BarrelField.structure_position(s))
		if j > 0 and absf(angle_difference(prev_yaw, yaw)) >= deg_to_rad(SAME_WAY_DEG):
			lean = -lean
		prev_yaw = yaw
		_build_arm(k, look, j, s, yaw, deg_to_rad(TILT_DEG) * lean, meshes, foot)
	spread_tags(arms.filter(func(r: Dictionary) -> bool: return int(r["sign"]) == k))


func _build_arm(k: int, look: Node3D, j: int, s: Node3D, yaw: float, tilt: float, meshes: Dictionary, foot: Vector3 = Vector3.ZERO) -> void:
	var arm := MeshInstance3D.new()
	arm.name = "Arm%d" % j
	arm.mesh = meshes["arm"]
	var h: float = ARM_HEIGHTS[mini(j, ARM_HEIGHTS.size() - 1)]
	# a turn about the post's axis, then the board's own lean about its face's normal (the tip up or down), set so the
	# stretched sign shows `tilt`
	arm.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt_for(tilt)), Vector3(0, h, 0))
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_paint(arm, false, foot)
	look.add_child(arm)
	var text := short_name(s)
	var labels: Array = []
	if SHOW_NAMES:
		# one tag over the outer half of the arm, facing the camera whichever way the arm points; it hangs from the sign's
		# Look node (not the arm), so the arm's yaw and lean move where it is but never turn it
		var lb := _label(text)
		lb.name = "Tag%d" % j
		var along := Basis(Vector3.UP, yaw) * Vector3(LABEL_X, 0, 0)
		var pull := Vector3(0, 0.06, 1.0).normalized() * LABEL_PULL / SCALE
		pull.y /= STRETCH
		lb.position = Vector3(along.x, h, along.z) + pull
		# the type keeps its shape: the Look node's stretch undone on the tag (pass 61)
		lb.scale = Vector3(1.0, 1.0 / STRETCH, 1.0)
		look.add_child(lb)
		labels.append(lb)
	arms.append({"sign": k, "structure": s, "node": arm, "labels": labels, "text": text, "yaw": yaw, "tilt": tilt,
		"height": h, "blank": false, "foot": foot})


## The lean an arm is given in the model's units so that, under the Look node's STRETCH, its board shows `tilt` (pass 61:
## a slope stretched up by STRETCH steepens, tan(shown) = STRETCH x tan(given)).
static func tilt_for(tilt: float) -> float:
	return atan(tan(tilt) / STRETCH)


## The run's camera looks down the screen at CAMERA_PITCH_DEG, so a tag's height and how far up the screen (north) it
## hangs both move it up the picture: two arms' tips can land on one spot. Each sign's tags are laid out on that screen
## plane (x across, height x cos(pitch) - z x sin(pitch) up) and any tag that overlaps the one below it is lifted clear,
## bottom first (pass 54, the lead: TELEPORT and DRUM printed over each other). Returns how many were lifted.
const CAMERA_PITCH_DEG := 46.0
const TAG_GAP := 0.06
static func spread_tags(recs: Array) -> int:
	var tags: Array = []
	for rec: Dictionary in recs:
		for lb: Label3D in rec["labels"]:
			tags.append(lb)
	if tags.size() < 2:
		return 0
	var c := cos(deg_to_rad(CAMERA_PITCH_DEG))
	var sn := sin(deg_to_rad(CAMERA_PITCH_DEG))
	# a height up the post counts STRETCH times in the world (pass 61); the tags themselves are unstretched
	var up_of := func(lb: Label3D) -> float: return lb.position.y * STRETCH * c - lb.position.z * sn
	tags.sort_custom(func(a: Label3D, b: Label3D) -> bool: return up_of.call(a) < up_of.call(b))
	var lifted := 0
	for i in range(1, tags.size()):
		var me: Label3D = tags[i]
		for j in i:
			var below: Label3D = tags[j]
			var half_w := (tag_width(me) + tag_width(below)) * 0.5
			if absf(me.position.x - below.position.x) >= half_w:
				continue
			var need: float = up_of.call(below) + tag_height(below) + TAG_GAP - up_of.call(me)
			if need > 0.0:
				# lift it straight up the post: only its height changes, so it stays over its own arm's side
				me.position.y += need / (c * STRETCH)
				lifted += 1
	return lifted


## A tag's width and height in the Look node's units (before SCALE), from its type.
static func tag_width(lb: Label3D) -> float:
	var f: Font = lb.font if lb.font else ThemeDB.fallback_font
	if f == null:
		return 0.0
	return f.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.font_size).x * lb.pixel_size


static func tag_height(lb: Label3D) -> float:
	return float(lb.font_size) * lb.pixel_size * 0.8


## A structure's name as a tag: ink type with a paper edge, always facing the camera, depth tested (a creature or a
## painting in front still hides it), LABEL_EM metres tall in the world (the sign's SCALE is undone, so the type keeps
## its size whatever the post's).
func _label(text: String) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	if _font == null and ResourceLoader.exists(FONT):
		_font = load(FONT)
	if _font:
		lb.font = _font
	lb.font_size = LABEL_FONT_PX
	lb.outline_size = LABEL_OUTLINE_PX
	lb.outline_modulate = PAPER
	lb.modulate = INK
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.double_sided = true
	lb.no_depth_test = false
	lb.shaded = false
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lb.pixel_size = LABEL_EM / float(LABEL_FONT_PX) / SCALE
	return lb


## How wide a label's text is on its board, in metres.
static func label_width(lb: Label3D) -> float:
	var f: Font = lb.font if lb.font else ThemeDB.fallback_font
	if f == null:
		return 0.0
	return f.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.font_size).x * lb.pixel_size


func _process(delta: float) -> void:
	if arms.is_empty():
		return
	_poll_t += delta
	if _poll_t < POLL:
		return
	_poll_t = 0.0
	check_used(true)


## Blanks every arm whose structure has been used (or is gone); `fade` lets the names fade out, else they go at once.
## Returns how many arms it blanked.
func check_used(fade: bool = true) -> int:
	var n := 0
	for rec: Dictionary in arms:
		if bool(rec["blank"]):
			continue
		var s = rec["structure"]
		if not is_instance_valid(s) or bool(s.get("used")):
			_blank(rec, fade)
			n += 1
	return n


func _blank(rec: Dictionary, fade: bool) -> void:
	rec["blank"] = true
	_paint(rec["node"] as MeshInstance3D, true, rec.get("foot", Vector3.ZERO))
	for lb: Label3D in rec["labels"]:
		if fade and lb.is_inside_tree():
			var tw := lb.create_tween()
			tw.tween_property(lb, "modulate:a", 0.0, FADE)
			tw.tween_callback(lb.hide)
		else:
			lb.modulate.a = 0.0
			lb.hide()


func _make_materials() -> void:
	_mats = {
		"post": _mat(POST_COLOR, 0.95),
		"wood": _mat(WOOD, 0.9),
		"wood_spent": _mat(WOOD_SPENT, 0.95),
		"rim": _mat(RIM, 0.9),
		"nail": _mat(NAIL, 0.6),
	}
	_sign_mats.clear()


## A template material: the depth shader (pass 60) in the colour and roughness a StandardMaterial3D had, or that plain
## material while the shader is missing.
func _mat(c: Color, rough: float) -> Material:
	var sh: Shader = load(DEPTH_SHADER) if ResourceLoader.exists(DEPTH_SHADER) else null
	if sh == null:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = c
		sm.roughness = rough
		return sm
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", rough)
	return m


## Whether `m` is the sign depth material (tests, tools).
static func depth_material(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path == DEPTH_SHADER


## The material named `key` for the sign standing at `foot`: the template, copied once per sign with its foot set
## (a StandardMaterial3D template, shader missing, is shared as it is).
func _mat_for(key: String, foot: Vector3) -> Material:
	var tpl: Material = _mats[key]
	if not tpl is ShaderMaterial:
		return tpl
	if not _sign_mats.has(foot):
		_sign_mats[foot] = {}
	var mine: Dictionary = _sign_mats[foot]
	if not mine.has(key):
		var m: ShaderMaterial = (tpl as ShaderMaterial).duplicate()
		m.set_shader_parameter("foot", foot)
		mine[key] = m
	return mine[key]


## Sets each surface's material by its name (the model's materials: post, wood, rim, nail); `spent` paints the wood
## the paler shade; `foot` is the sign's foot in the world, the depth it is drawn at (pass 60).
func _paint(mi: MeshInstance3D, spent: bool, foot: Vector3 = Vector3.ZERO) -> void:
	if _mats.is_empty():
		_make_materials()
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var key := surface_key(mesh, i)
		if key == "wood" and spent:
			key = "wood_spent"
		if _mats.has(key):
			mi.set_surface_override_material(i, _mat_for(key, foot))


## A surface's name: its material's (the GLB's), else the surface's own (the meshes built here).
static func surface_key(mesh: Mesh, i: int) -> String:
	var m := mesh.surface_get_material(i)
	if m != null and m.resource_name != "":
		return m.resource_name.to_lower()
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_name(i).to_lower()
	return ""


## The post and the arm from the model, or built here when it is missing (not imported yet).
func _meshes() -> Dictionary:
	if ResourceLoader.exists(MODEL):
		var scene: Node = (load(MODEL) as PackedScene).instantiate()
		var out := {}
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.name.begins_with("Post"):
				out["post"] = mi.mesh
			elif mi.name.begins_with("Arm"):
				out["arm"] = mi.mesh
		scene.free()
		if out.has("post") and out.has("arm"):
			return out
	return {"post": post_mesh(), "arm": arm_mesh()}


## The model's post as a plain box: POST_W square, POST_H tall, its foot at the origin (surface "post").
static func post_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := POST_W * 0.5
	_box(st, Vector3(-h, 0, -h), Vector3(h, POST_H, h))
	var mesh := st.commit()
	mesh.surface_set_name(0, "post")
	return mesh


## The model's arm without its rim and nails: the pointed board along +X from the post's axis (surface "wood" its two
## faces, "rim" its edges), so a field without the model still points and still blanks.
static func arm_mesh() -> ArrayMesh:
	var hz := ARM_H * 0.5
	var ht := ARM_T * 0.5
	var outline: Array = [Vector2(ARM_X0, -hz), Vector2(ARM_X1 - ARM_TIP, -hz), Vector2(ARM_X1, 0.0), Vector2(ARM_X1 - ARM_TIP, hz), Vector2(ARM_X0, hz)]
	var faces := SurfaceTool.new()
	faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var n := Vector3(0, 0, side)
		for i in range(1, outline.size() - 1):
			_tri(faces, _xy(outline[0], ht * side), _xy(outline[i], ht * side), _xy(outline[i + 1], ht * side), n)
	var mesh := faces.commit()
	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var e := b - a
		var n := Vector3(e.y, -e.x, 0).normalized()     # outwards for the counter-clockwise outline
		_quad(edges, _xy(a, ht), _xy(b, ht), _xy(b, -ht), _xy(a, -ht), n)
	edges.commit(mesh)
	mesh.surface_set_name(0, "wood")
	mesh.surface_set_name(1, "rim")
	return mesh


static func _xy(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)


## A triangle facing `n` (Godot draws clockwise faces: the order is swapped when it would face away).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var x0 := lo.x
	var y0 := lo.y
	var z0 := lo.z
	var x1 := hi.x
	var y1 := hi.y
	var z1 := hi.z
	_quad(st, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP)
	_quad(st, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN)
	_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK)
	_quad(st, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD)
	_quad(st, Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.RIGHT)
	_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT)
