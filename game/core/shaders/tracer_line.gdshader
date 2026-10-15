// A tracer's line (pass 79, lane FX; Garry: "Make a simple line trail, similar to that of the rocket. Should be thin ...
// Then the line disappears like smoke"). One quad per segment of a shot's flight, all of them in one MultiMesh
// (ProjectileManager._tracer_*); the instance transform carries the segment, not a placement:
//   origin            = the segment's start (world)
//   basis column 0    = the segment (start to end, world)
//   basis column 1    = (the end's birth on the shots' clock, life in seconds, width in metres)
//   basis column 2    = (the start's birth, 0, 0): the shot passed the start a little before the end, so the pieces of
//                       one line meet with the same age, width and drift (no seam where they join)
// The quad is turned to face the camera round the segment, never thinner than min_px pixels on the screen. Over its
// life it fades (alpha x (1 - f)^fade_pow), widens by `widen`, drifts up at `rise` m/s, sways a little (by where it is,
// so the pieces of one line sway together) and greys towards smoke; once its life is out the quad collapses to a point
// and draws nothing. `now` is the shots' clock.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled;

uniform float now = 0.0;
uniform float widen = 0.9;
uniform float rise = 0.45;
uniform float fade_pow = 1.5;
uniform float smoke_grey = 0.4;
uniform float sway = 0.06;
uniform float min_px = 1.5;
uniform float edge_soft = 0.45;

varying float v_f;
varying float v_x;

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 seg = MODEL_MATRIX[0].xyz;
	vec3 info = MODEL_MATRIX[1].xyz;
	float life = max(info.y, 0.001);
	// the newest end decides whether the piece is drawn at all; each end fades on its own age
	float f_end = (now - info.x) / life;
	float age = now - mix(MODEL_MATRIX[2].x, info.x, UV.y);
	float f = clamp(age / life, 0.0, 1.0);
	v_f = f;
	v_x = UV.x * 2.0 - 1.0;
	vec3 world = p0;
	if (f_end >= -0.001 && f_end < 1.0 && dot(seg, seg) > 1e-8) {
		vec3 p = p0 + seg * UV.y;
		vec3 to_cam = INV_VIEW_MATRIX[3].xyz - p;
		vec3 sv = cross(seg, to_cam);
		float sl = length(sv);
		vec3 side = sl > 1e-6 ? sv / sl : vec3(1.0, 0.0, 0.0);
		float w = info.z * (1.0 + widen * f);
		// metres per pixel at this distance (the fov spans the viewport's height)
		float mpp = 2.0 * length(to_cam) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		w = max(w, min_px * mpp);
		p += side * (v_x * w * 0.5 + sin(dot(p.xz, vec2(1.7, 1.3)) + age * 4.0) * sway * f);
		p.y += rise * age;
		world = p;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(INV_VIEW_MATRIX[2].xyz, 0.0)).xyz);
}

// the tracer colours are written as they should look on the screen (sRGB, as in the JSON); the renderer works in linear
vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	float f = clamp(v_f, 0.0, 1.0);
	float edge = 1.0 - smoothstep(1.0 - edge_soft, 1.0, abs(v_x));
	vec3 c = COLOR.rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	ALBEDO = to_linear(mix(c, vec3(l), smoke_grey * f));
	ALPHA = COLOR.a * pow(1.0 - f, fade_pow) * edge;
}
