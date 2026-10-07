## A turning shine (pass 58, Garry: "can you add a kind of animated shine effect behind the Level N header part? Like a
## rotating shine or something, make it look good and fitting with our UI style. Do the Same for the loot Chest visual
## of the Chest Opening Screen. Do the same for the Version of Level up that is for a Specific Weapon Mutation"): a
## wanted-poster sunburst behind a title, a weapon's plate or a chest. Wide brass rays turn one way, narrow paper rays
## the other, both fading out from the middle, over a warm glow; the whole shine breathes (BREATH seconds a breath) and a
## few paper glints twinkle in it. One canvas shader on one square (the code is in this file: no shader file to import),
## the glints a few small polygons a frame. It ignores the mouse, runs while the run is paused and lives as long as it is
## in the tree (it is freed with its host).
##
## Use (a new class_name is known only after the next import: by path from other scripts):
##   const WShineScript := preload("res://ui/wanted/WShine.gd")
##   var s: WShineScript = WShineScript.make(centre, radius)     # brass and paper; make(c, r, colour, colour2) to tint
##   s.put(host, index)        # into `host` at child `index` (-1 = on top): over the dim, under what it shines behind
##   s.pop_in()                # grows in with a little overshoot; fade_out(seconds, free_after) takes it away
## `center` and `radius` are in the host's pixels (the shine fills its host's rect) and may change at any time;
## `tint(colour)` recolours both layers (the boss chest's purple); `strength` scales its opacity, `speed` its turning.
## `WShine.warm(host)` draws one all but unseen so its shader is compiled before the first level-up needs it (Warmup).
class_name WShine
extends Control

## The wide rays and the narrow ones, and how fast each layer turns (radians a second; the narrow ones the other way).
const RAYS_A := 12
const RAYS_B := 12
const TURN_A := 0.22
const TURN_B := -0.13
## Each wide ray fills this share of its slice of the circle, each narrow one this.
const WIDTH_A := 0.42
const WIDTH_B := 0.15
## Their opacity at full strength, and the glow's in the middle.
const ALPHA_A := 0.5
const ALPHA_B := 0.34
const GLOW := 0.42
## A breath: its length, and how much the opacity and the size swell with it.
const BREATH := 2.6
const BREATH_ALPHA := 0.12
const BREATH_SIZE := 0.025
## The twinkling glints: how many at once, the longest a glint's arm, a glint's life.
const GLINTS := 4
const GLINT_PX := 24.0
const GLINT_LIFE := 0.9

## The middle and the reach of the shine, in the host's pixels.
var center := Vector2(540.0, 300.0):
	set(v):
		center = v
		queue_redraw()
var radius := 480.0:
	set(v):
		radius = maxf(v, 1.0)
		queue_redraw()
## The wide rays' and the glow's colour, and the narrow rays' (brass and paper by default).
var color := W.BRASS:
	set(v):
		color = v
		_sync_colours()
var color2 := W.PAPER:
	set(v):
		color2 = v
		_sync_colours()
## Opacity (1 = as designed) and turning speed (1 = as designed).
var strength := 1.0
var speed := 1.0
## Glints at once (0 = none).
var glints := GLINTS
## The pop's scale and the fade's opacity (pop_in / fade_out tween them).
var grow := 1.0
var fade := 1.0

var _t := 0.0
var _turn_a := 0.0
var _turn_b := 0.0
var _mat: ShaderMaterial
var _glint_layer: Control
## [angle, distance (share of the radius), age, size share, spin]
var _glints: Array = []
var _rng := RandomNumberGenerator.new()
var _fade_tw: Tween

static var _shader: Shader

const SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform vec4 color_a : source_color = vec4(0.788, 0.576, 0.184, 1.0);
uniform vec4 color_b : source_color = vec4(0.953, 0.902, 0.784, 1.0);
uniform float turn_a = 0.0;
uniform float turn_b = 0.0;
uniform float rays_a = 12.0;
uniform float rays_b = 12.0;
uniform float width_a = 0.42;
uniform float width_b = 0.15;
uniform float alpha_a = 0.5;
uniform float alpha_b = 0.34;
uniform float glow = 0.42;
uniform float strength = 1.0;
uniform float radius_px = 480.0;

// How much of a ray covers this pixel: 0 between the rays, 1 inside, an antialiased edge a pixel wide (the pixel's
// share of the angle is worked out from the radius, so the seam of atan never shows).
float ray(float ang, float turn, float n, float w, float r) {
	float f = fract((ang - turn) * n / TAU);
	float d = min(f, 1.0 - f) * 2.0;
	float px = n / (TAU * max(r * radius_px, 1.0)) * 2.0;
	return 1.0 - smoothstep(w * 0.82 - px, w + px, d);
}

void fragment() {
	vec4 base = COLOR;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// the glow: warm in the middle, paler at its heart, gone by nine tenths of the reach
	float ga = glow * pow(1.0 - smoothstep(0.0, 0.9, r), 1.8);
	vec3 gc = mix(color_a.rgb, color_b.rgb, 0.4 * (1.0 - smoothstep(0.0, 0.35, r)));
	vec3 c = gc * ga;
	float a = ga;
	// the wide rays: out of the glow's heart, fading to nothing at the reach
	float inner = smoothstep(0.03, 0.22, r);
	float ma = ray(ang, turn_a, rays_a, width_a, r) * inner * pow(1.0 - smoothstep(0.18, 1.0, r), 1.4) * alpha_a;
	vec3 ca = mix(color_a.rgb, color_b.rgb, 0.25 * (1.0 - smoothstep(0.0, 0.4, r)));
	c = ca * ma + c * (1.0 - ma);
	a = ma + a * (1.0 - ma);
	// the narrow rays, turning the other way, a little shorter
	float mb = ray(ang, turn_b, rays_b, width_b, r) * inner * (1.0 - smoothstep(0.12, 0.82, r)) * alpha_b;
	c = color_b.rgb * mb + c * (1.0 - mb);
	a = mb + a * (1.0 - mb);
	a = clamp(a * strength, 0.0, 1.0);
	vec3 rgb = a > 0.0001 ? c * strength / a : vec3(0.0);
	COLOR = vec4(clamp(rgb, 0.0, 1.0), a) * base;
}
"""


## This script's path: it makes its own copies through it (its class_name is known only after the next import).
const SCRIPT_PATH := "res://ui/wanted/WShine.gd"


## A shine at `at` reaching `r`, in `col` (the wide rays and the glow) and `col2` (the narrow rays); put() it somewhere.
static func make(at: Vector2, r: float = 480.0, col: Color = W.BRASS, col2: Color = W.PAPER) -> Control:
	var s = (load(SCRIPT_PATH) as GDScript).new()
	s.center = at
	s.radius = r
	s.color = col
	s.color2 = col2
	return s


## One small shine drawn all but unseen under `host` (pass 58 review): the Compatibility renderer compiles a canvas shader
## the first time something draws with it, a hitch on a phone, so Warmup draws this under the spawn beam and the first
## level-up's reveal (or the first chest's) does not pay for it. It goes with `host`, or after `seconds` when given.
static func warm(host: Node, seconds: float = 0.0) -> Control:
	var s = make(Vector2(32.0, 32.0), 32.0)
	s.name = "ShineWarm"
	s.glints = 0
	# drawn (its _draw skips a shine fainter than 0.002), but never seen
	s.strength = 0.01
	s.show_now()
	s.put(host)
	if seconds > 0.0 and host.is_inside_tree():
		host.get_tree().create_timer(seconds, true, false, true).timeout.connect(func():
			if is_instance_valid(s):
				s.queue_free())
	return s


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the level-up and the chest pause the run: the shine turns on
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	material = _mat
	_sync_colours()
	_rng.randomize()
	_turn_a = _rng.randf() * TAU
	_turn_b = _rng.randf() * TAU
	# the glints draw on a layer of their own (the shader would take them too)
	_glint_layer = Control.new()
	_glint_layer.name = "Glints"
	_glint_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glint_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glint_layer.draw.connect(_draw_glints)
	add_child(_glint_layer)


## Into `host` at child `index` (-1 = on top); returns itself.
func put(host: Node, index: int = -1) -> Control:
	host.add_child(self)
	if index >= 0:
		host.move_child(self, clampi(index, 0, host.get_child_count() - 1))
	return self


## Both layers in `col`: the wide rays and the glow in it, the narrow rays in a paler copy of it (the boss chest's
## purple; brass is the default).
func tint(col: Color) -> void:
	color = col
	color2 = col.lerp(W.PAPER, 0.62)


## Grows in from nothing with a little overshoot over `seconds`, fading in.
func pop_in(seconds: float = 0.4) -> void:
	_kill_fade()
	grow = 0.0
	fade = 0.0
	_fade_tw = create_tween().set_parallel(true)
	_fade_tw.tween_property(self, "grow", 1.0, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fade_tw.tween_property(self, "fade", 1.0, seconds * 0.5)


## Fades out over `seconds`, shrinking a little; freed after when `free_after`, else left hidden (pop_in brings it back).
func fade_out(seconds: float = 0.2, free_after: bool = false) -> void:
	_kill_fade()
	_fade_tw = create_tween().set_parallel(true)
	_fade_tw.tween_property(self, "fade", 0.0, seconds)
	_fade_tw.tween_property(self, "grow", 0.9, seconds)
	_fade_tw.chain().tween_callback(func():
		if free_after:
			queue_free())


## Straight to its full look, no pop (a capture, a test).
func show_now() -> void:
	_kill_fade()
	grow = 1.0
	fade = 1.0


func _kill_fade() -> void:
	if _fade_tw and _fade_tw.is_valid():
		_fade_tw.kill()
	_fade_tw = null


## How far the wide rays have turned (radians; the tests watch it move).
func angle() -> float:
	return _turn_a


## The seconds it has been turning.
func age() -> float:
	return _t


func _sync_colours() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("color_a", color)
	_mat.set_shader_parameter("color_b", color2)
	queue_redraw()


func _breath() -> float:
	return sin(TAU * _t / BREATH)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_turn_a = fposmod(_turn_a + TURN_A * speed * delta, TAU)
	_turn_b = fposmod(_turn_b + TURN_B * speed * delta, TAU)
	_tick_glints(delta)
	queue_redraw()
	_glint_layer.queue_redraw()


## The radius drawn now: the reach, the pop and the breath.
func drawn_radius() -> float:
	return radius * grow * (1.0 + BREATH_SIZE * _breath())


func _draw() -> void:
	var r := drawn_radius()
	var a := strength * fade * (1.0 + BREATH_ALPHA * _breath())
	if r <= 1.0 or a <= 0.002:
		return
	_mat.set_shader_parameter("turn_a", _turn_a)
	_mat.set_shader_parameter("turn_b", _turn_b)
	_mat.set_shader_parameter("rays_a", float(RAYS_A))
	_mat.set_shader_parameter("rays_b", float(RAYS_B))
	_mat.set_shader_parameter("width_a", WIDTH_A)
	_mat.set_shader_parameter("width_b", WIDTH_B)
	_mat.set_shader_parameter("alpha_a", ALPHA_A)
	_mat.set_shader_parameter("alpha_b", ALPHA_B)
	_mat.set_shader_parameter("glow", GLOW)
	_mat.set_shader_parameter("strength", a)
	_mat.set_shader_parameter("radius_px", r)
	draw_rect(Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), Color.WHITE)


## The glints: each one lives GLINT_LIFE seconds somewhere between a third and three quarters of the reach, swelling
## and shrinking as it turns a little; a new one takes its place elsewhere.
func _tick_glints(delta: float) -> void:
	while _glints.size() < glints:
		# staggered, so they never twinkle together
		_glints.append([_rng.randf() * TAU, _rng.randf_range(0.34, 0.76), -_rng.randf() * GLINT_LIFE * float(_glints.size() + 1) / float(maxi(glints, 1)),
			_rng.randf_range(0.6, 1.0), _rng.randf_range(-1.5, 1.5)])
	while _glints.size() > glints:
		_glints.pop_back()
	for g in _glints:
		g[2] += delta
		if g[2] >= GLINT_LIFE:
			g[0] = _rng.randf() * TAU
			g[1] = _rng.randf_range(0.34, 0.76)
			g[2] = 0.0
			g[3] = _rng.randf_range(0.6, 1.0)
			g[4] = _rng.randf_range(-1.5, 1.5)


func _draw_glints() -> void:
	var r := drawn_radius()
	var a := clampf(strength * fade, 0.0, 1.0)
	if r <= 1.0 or a <= 0.01:
		return
	for g in _glints:
		var age_g: float = g[2]
		if age_g < 0.0:
			continue
		var k := sin(PI * clampf(age_g / GLINT_LIFE, 0.0, 1.0))
		var arm: float = GLINT_PX * float(g[3]) * k * grow
		if arm < 1.0:
			continue
		var at := center + Vector2.from_angle(float(g[0])) * r * float(g[1])
		var spin: float = float(g[4]) * age_g
		var pts := PackedVector2Array()
		for i in 8:
			var rr := arm if i % 2 == 0 else arm * 0.2
			pts.append(at + Vector2.from_angle(spin + PI * 0.25 * i) * rr)
		_glint_layer.draw_colored_polygon(pts, Color(color2, 0.85 * a * k))
		_glint_layer.draw_circle(at, arm * 0.16, Color(1, 1, 1, 0.9 * a * k), true, -1.0, true)
