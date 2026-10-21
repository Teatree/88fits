## Pass 95 (lane WORLD; Garry: "For that time there should be a 2d magnet icon floating around the Player and the usual
## UI elements indicating that Player is 'magnetizing' things in that moment"): the 2D magnet that floats round the hero
## while the Magnet power-up runs. PickupManager makes one as the pull starts (_magnet_show), follow()s it every tick and
## frees it when the time is up. The pickup's own icon on a camera-facing quad (BillboardSprite, ICON_M tall) orbits his
## feet at ORBIT_R m and HEIGHT m up, bobbing; from it faint dashed field lines (one ImmediateMesh, LINES of them at most)
## curve to the nearest gems and coins on their way to him or lying just past the reach, their dashes crawling towards the
## magnet, and a spark (Fx.mote) now and then flies up one of them; in the last BLINK_LAST seconds the icon blinks as a
## power-up on the ground does before it goes. Cheap: one quad, one line mesh, a mote every SPARK_EVERY s.
class_name MagnetBuff
extends Node3D

const LINES := 3
const ORBIT_R := 1.3
const ORBIT_SPEED := 1.4
const HEIGHT := 1.55
const BOB := 0.12
const BOB_SPEED := 2.6
const ICON_M := 0.8
const LINE_COLOUR := Color(1.0, 0.76, 0.3, 0.5)
const LINE_LIFT := 1.0
const DASHES := 8
const DASH_FILL := 0.55
const DASH_SPEED := 1.6
const SPARK_EVERY := 0.12
const SPARK_COLOUR := Color(1.0, 0.85, 0.45, 0.9)
const BLINK_LAST := 1.5

## The game's Fx (the sparks); nothing without it.
var fx = null
## How many field lines the last follow() drew, the last targets, the sparks made (tests, the capture).
var lines_drawn := 0
var sparks := 0
var _sprite: BillboardSprite
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _t := 0.0
var _spark_t := 0.0
var _targets := PackedVector3Array()
var _rng := RandomNumberGenerator.new()


## The pickup whose icon it wears (its placeholder when it has no painting yet).
func setup(def: PickupDef) -> void:
	_rng.randomize()
	var tex: Texture2D = def.icon if def != null and def.icon != null else PlaceholderArt.icon(def, 128)
	_sprite = BillboardSprite.new()
	add_child(_sprite)
	_sprite.setup(tex, {"idle": 1}, ["idle"], ICON_M)
	_sprite.position.y = HEIGHT - ICON_M * 0.5
	_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lines.material_override = m
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the lines are drawn in world space while the node itself orbits
	_lines.top_level = true
	add_child(_lines)


## Where the icon's middle is now (world).
func icon_at() -> Vector3:
	return _sprite.global_position + Vector3(0, ICON_M * 0.5, 0) if _sprite != null and is_inside_tree() else global_position


## One tick: the orbit round `hero`, the bob, the field lines to `targets` (up to LINES points: gems on their way or lying
## near the reach), the blink over the last BLINK_LAST s of `left`, a spark now and then.
func follow(hero: Vector3, targets: PackedVector3Array, left: float, delta: float) -> void:
	_t += delta
	var a := _t * ORBIT_SPEED
	global_position = Vector3(hero.x + cos(a) * ORBIT_R, hero.y, hero.z + sin(a) * ORBIT_R)
	if _sprite != null:
		_sprite.position.y = HEIGHT - ICON_M * 0.5 + sin(_t * BOB_SPEED) * BOB
		_sprite.visible = left > BLINK_LAST or int(left * 5.0) % 2 == 0
	_targets = targets
	_draw_lines()
	_spark(delta)


## A point of the field line from the icon to `to`: a quadratic curve lifted LINE_LIFT m at its middle.
func line_point(from: Vector3, to: Vector3, k: float) -> Vector3:
	var mid := (from + to) * 0.5 + Vector3(0, LINE_LIFT, 0)
	var u := 1.0 - k
	return from * (u * u) + mid * (2.0 * u * k) + to * (k * k)


func _draw_lines() -> void:
	_mesh.clear_surfaces()
	lines_drawn = 0
	if _targets.is_empty():
		return
	var from := icon_at()
	var shift := fmod(_t * DASH_SPEED, 1.0)
	var n := mini(_targets.size(), LINES)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for t in range(n):
		var to: Vector3 = _targets[t] + Vector3(0, 0.15, 0)
		for d in range(DASHES):
			# the dashes crawl from the gem towards the magnet
			var k0 := 1.0 - fmod(float(d) / DASHES + shift / DASHES, 1.0)
			var k1 := k0 - DASH_FILL / DASHES
			if k1 < 0.0:
				continue
			var c := LINE_COLOUR
			c.a = LINE_COLOUR.a * (0.4 + 0.6 * k0)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(line_point(from, to, k0))
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(line_point(from, to, k1))
		lines_drawn += 1
	_mesh.surface_end()


func _spark(delta: float) -> void:
	_spark_t -= delta
	if _spark_t > 0.0 or _targets.is_empty() or fx == null or not fx.has_method("mote"):
		return
	_spark_t = SPARK_EVERY
	var to: Vector3 = _targets[_rng.randi() % mini(_targets.size(), LINES)] + Vector3(0, 0.15, 0)
	var from := icon_at()
	var k := _rng.randf_range(0.15, 0.9)
	var at := line_point(from, to, k)
	var ahead := line_point(from, to, maxf(k - 0.1, 0.0))
	fx.mote(at, (ahead - at) * 6.0, 0.35, 0.14, SPARK_COLOUR)
	sparks += 1
