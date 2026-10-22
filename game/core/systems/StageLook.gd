## A stage's look (pass 87, lane SLOOK; Garry: "Stages now look different a bit (there is a blueish dim filter on the map
## for Stage 2 to indicate evening, and a redish filter on Stage 3 to indicate hell / bloodmoon). This should look good
## and not mess up how elements 'read' during the game."). Each entry of the map's `timeline_data.stage_list` may carry
## `filter` {color "#rrggbb", strength 0..1, actors 0..1} and `hell` (true: pass 43's red ground, RedCanyon.set_hell).
##
## The filter multiplies the drawn world by white.lerp(color, strength): a coloured glass of that strength over the
## view (black dims, a blue cools and dims, a red warms and dims). It is two quads over the whole view
## (core/shaders/stage_filter.gdshader, one draw each, nothing else to hook), drawn after the opaque world and the
## water but before the ground marks, the shadows, the gems, the coins, the outlines, the effects and the projectiles,
## which stay as they are on top of it:
##  - the world: where the nearest thing is the sand, the water, the sky or scenery (stencil 0 and 2), at `strength`;
##  - the creatures and the hero (and power-ups, flowers: the paintings that write stencil 1), at `strength` x `actors`
##    (ACTORS_DEFAULT when the filter names none), so they stay brighter than the ground and still read.
## A white factor hides the quads (stage 1 costs nothing). A map without stage_list plays as before pass 87: no
## filter and hell from the third stage on (s >= 2).
##
## Game makes one at its first stage_started (StageLook.of) and hands it every stage that starts (show_stage): the
## run's first stage takes its look at once, a later one (the old flow, endless) over FADE_SECONDS.
## Pass 100 (lane SMALL): Game shows the run's stage before the spawn beam's landing (Game._show_stage_look_now, at
## once), so the intro plays in the stage's light; the stage_started that follows finds it shown.
class_name StageLook
extends Node

const SHADER := preload("res://core/shaders/stage_filter.gdshader")
## After the water (-10, RedCanyon._water_material), before the spawn beam (pass 100: -6, Game.SPAWN_BEAM_PRIORITY, a
## light over the stage's look), the Salt's patches (-6), the ground
## marks (Telegraphs.PRIO_SCORCH -5 .. PRIO_BAND -1), the shadows (EnemyManager.SHADOW_PRIORITY -3), the pickups
## (PickupManager.PICKUP_PRIORITY -2) and everything at 0 and above (outlines, effects, projectiles, badges).
const PRIORITY := -7
## The share of the filter's strength the creatures and the hero take when the filter names no `actors`.
const ACTORS_DEFAULT := 0.35
## Seconds a stage's look takes to come in when the stage changes during a run (the first stage's is there at once).
const FADE_SECONDS := 3.0
## The stencil the paintings that are not scenery write (PickupManager.PAINTING_STENCIL).
const ACTOR_STENCIL := 1
const NODE_NAME := "StageLook"

var game: Node
## The camera the quads ride on (their shader covers any camera's view: a capture's own camera sees them too).
var camera: Camera3D
## The stage shown (-1 before the first) and its stage_list entry ({} on a map without one).
var stage := -1
var entry: Dictionary = {}
## The factors drawn now (white = none) and the ones being faded to.
var env_mult := Color.WHITE
var actor_mult := Color.WHITE
var _from_env := Color.WHITE
var _from_actor := Color.WHITE
var _to_env := Color.WHITE
var _to_actor := Color.WHITE
var _tween: Tween
var _env_quad: MeshInstance3D
var _actor_quad: MeshInstance3D
static var _actor_shader: Shader


## The game's StageLook, made on first use (a child of `game` named NODE_NAME).
static func of(p_game: Node) -> StageLook:
	if p_game == null:
		return null
	var have := p_game.get_node_or_null(NODE_NAME)
	if have is StageLook:
		return have
	var sl := StageLook.new()
	sl.name = NODE_NAME
	sl.game = p_game
	p_game.add_child(sl)
	return sl


## Stage `s` (0-based) has started: its filter and its hell. The run's first stage at once, a later one faded. (The sky
## takes the filter like everything else; it is never seen in play, only in the Stages menu's pictures.)
func show_stage(s: int, seconds: float = -1.0) -> void:
	# pass 100 (lane SMALL): the stage shown already (Game._show_stage_look_now put it on before the landing) is left as
	# it is when the director starts it; an explicit `seconds` (the arena's choice, a tool) always shows it again
	if s == stage and seconds < 0.0:
		return
	var first := stage < 0
	stage = s
	var tl: WaveTimeline = _timeline()
	entry = entry_of(tl, s)
	var fade: float = (0.0 if first else FADE_SECONDS) if seconds < 0.0 else seconds
	var mults: Array = filter_mults(entry)
	set_mults(mults[0], mults[1], fade)
	var map: Node = game.get("map") if game else null
	if map and map.has_method("set_hell"):
		map.set_hell(1.0 if hell_of(tl, s) else 0.0, maxf(fade, 0.01))


## The run's timeline (Run.map's).
func _timeline() -> WaveTimeline:
	var tree := Engine.get_main_loop() as SceneTree
	var run: Node = tree.root.get_node_or_null("Run") if tree else null
	if run and run.get("map") and run.map.timeline:
		return run.map.timeline
	return null


# ---------------------------------------------------------------- the data

## The map's stage list (timeline_data.stage_list; [] when it has none).
static func stage_list_of(tl: WaveTimeline) -> Array:
	if tl == null:
		return []
	var v = tl.get("stage_list")
	return v if v is Array else []


## Stage `s`'s entry (past the last: the last's, so an endless after it keeps its look); {} without a stage list.
static func entry_of(tl: WaveTimeline, s: int) -> Dictionary:
	var list := stage_list_of(tl)
	if list.is_empty():
		return {}
	var e = list[clampi(s, 0, list.size() - 1)]
	return e if e is Dictionary else {}


## Whether stage `s` is hell: its entry's `hell`; without a stage list the third stage on (pass 43).
static func hell_of(tl: WaveTimeline, s: int) -> bool:
	if stage_list_of(tl).is_empty():
		return s >= 2
	return bool(entry_of(tl, s).get("hell", false))


## [world factor, creatures' factor] for a stage entry: white.lerp(color, strength) and white.lerp(color, strength x
## actors). No filter, a bad colour or strength 0: white (nothing drawn).
static func filter_mults(e: Dictionary) -> Array:
	var f = e.get("filter", {})
	if not (f is Dictionary):
		return [Color.WHITE, Color.WHITE]
	var c: Color = WaveTimeline.color_of(f.get("color", "#ffffff"), Color.WHITE)
	c.a = 1.0
	var k := clampf(float(f.get("strength", 0.0)), 0.0, 1.0)
	var a := clampf(float(f.get("actors", ACTORS_DEFAULT)), 0.0, 1.0)
	return [Color.WHITE.lerp(c, k), Color.WHITE.lerp(c, k * a)]


# ---------------------------------------------------------------- the quads

## Draws the world at `env` and the creatures at `actors`, fading from what is drawn over `seconds`.
func set_mults(env: Color, actors: Color, seconds: float = 0.0) -> void:
	if _tween:
		_tween.kill()
		_tween = null
	_from_env = env_mult
	_from_actor = actor_mult
	_to_env = env
	_to_actor = actors
	if seconds <= 0.0 or not is_inside_tree():
		_blend(1.0)
		return
	_tween = create_tween()
	_tween.tween_method(_blend, 0.0, 1.0, seconds)


func _blend(t: float) -> void:
	env_mult = _from_env.lerp(_to_env, t)
	actor_mult = _from_actor.lerp(_to_actor, t)
	_show(env_mult, actor_mult)


func _show(env: Color, actors: Color) -> void:
	var need_env := not _is_white(env)
	var need_actor := not _is_white(actors)
	if (need_env or need_actor) and _env_quad == null:
		_build()
	if _env_quad:
		_env_quad.visible = need_env
		(_env_quad.material_override as ShaderMaterial).set_shader_parameter("mult", screen_mult(env))
	if _actor_quad:
		_actor_quad.visible = need_actor
		(_actor_quad.material_override as ShaderMaterial).set_shader_parameter("mult", screen_mult(actors))


static func _is_white(c: Color) -> bool:
	return c.r >= 0.999 and c.g >= 0.999 and c.b >= 0.999


## The factor as the shader takes it. The renderer writes the quad's colour to the screen in sRGB (linear light in, the
## screen's encoding out), so the colour is handed in linear light: on the screen each channel is then multiplied by the
## colour as authored (measured: 0.8 leaves about 80% of a channel), the factor Garry picks in the Level Editor.
static func screen_mult(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


## The two quads on the camera (the game's CameraRig's Camera3D, or a capture's).
func _build() -> void:
	if camera == null:
		var rig = game.get("camera") if game else null
		if rig is CameraRig:
			camera = (rig as CameraRig).camera
		elif rig is Camera3D:
			camera = rig
	if camera == null:
		camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	_env_quad = _quad("StageFilter", SHADER)
	_actor_quad = _quad("StageFilterActors", actor_shader())


func _quad(qname: String, shader: Shader) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = qname
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = PRIORITY
	m.set_shader_parameter("mult", Vector3.ONE)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	mi.ignore_occlusion_culling = true
	mi.position = Vector3(0, 0, -1.0)
	mi.visible = false
	camera.add_child(mi)
	return mi


## The creatures' copy of the filter's shader: the same code drawn only on stencil ACTOR_STENCIL.
static func actor_shader() -> Shader:
	if _actor_shader == null:
		var s := Shader.new()
		s.code = SHADER.code.replace("stencil_mode read, compare_not_equal, %d;" % ACTOR_STENCIL, "stencil_mode read, compare_equal, %d;" % ACTOR_STENCIL)
		_actor_shader = s
	return _actor_shader


## The quads (tests, tools): [world, creatures], null before the first filter.
func quads() -> Array:
	return [_env_quad, _actor_quad]
