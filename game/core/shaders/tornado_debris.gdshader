// A tornado's debris (pass 113, lane TWISTER; core/systems/TornadoFx.gd): small dark things riding round the funnel and
// up it, drawn as solid painted shapes facing the camera (clods, twigs, chips and a little tumbleweed), so they write
// depth and the see-through dust sorts round them: one in front of the funnel is seen on it, one behind it is lost in it.
// One MultiMesh of quads whose instance transforms are all the identity; this places every one from its custom data and
// the clock, so nothing moves on the CPU:
//   INSTANCE_CUSTOM  x = start angle 0..1, y = start height 0..1, z = its own speed/orbit 0..1, w = kind 0..1 (x4) + size
// `amount` shows them (0 none .. 1 all, scaled down from the top as it falls), `burst` flings them out and drops them.
// The shape (tw_radius, tw_axis, tw_y) is tornado_funnel.gdshader's: keep them in step.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled;

uniform vec4 color : source_color = vec4(0.78, 0.58, 0.38, 1.0);
uniform float t = 0.0;
uniform float height = 6.5;
uniform float r_bottom = 0.75;
uniform float r_top = 2.6;
uniform float flare = 1.6;
uniform float grow = 1.0;
uniform float thin = 1.0;
uniform vec2 lean = vec2(0.0);
uniform float snake = 0.45;
uniform float spin = 0.9;
uniform float rise = 0.16;
uniform float size = 1.0;
uniform float amount = 1.0;
uniform float burst = 0.0;

varying float v_kind;
varying float v_seed;

float tw_radius(float v) {
	return mix(r_bottom, r_top, pow(clamp(v, 0.0, 1.0), flare)) * mix(0.28, 1.0, thin);
}

vec2 tw_axis(float v) {
	vec2 s = vec2(sin(v * 4.0 - t * 1.7), cos(v * 3.2 - t * 1.25 + 1.3));
	return lean * pow(clamp(v, 0.0, 1.0), 1.3) + s * snake * smoothstep(0.0, 0.7, v);
}

float tw_y(float v) {
	return v * height * mix(0.4, 1.0, grow);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float kind = floor(cd.w * 4.0);
	float sz = fract(cd.w * 4.0);
	v_kind = kind;
	v_seed = cd.x * 13.7 + cd.z * 5.1;
	// up the funnel and round it, the low ones turning faster; a fresh lap from the foot when one reaches the top
	float h = fract(cd.y + t * rise * (0.65 + 0.7 * cd.z));
	float v = h * 0.92 * grow;
	float ang = cd.x * TAU + t * spin * TAU * (1.25 - 0.5 * v) * (0.85 + 0.3 * cd.z);
	float r = tw_radius(v) * (1.12 + 0.45 * cd.z) + 0.1;
	vec2 ax = tw_axis(v);
	vec3 local = vec3(ax.x + cos(ang) * r, tw_y(v) + 0.12, ax.y + sin(ang) * r);
	float b = burst > 0.0 ? 1.0 - (1.0 - burst) * (1.0 - burst) : 0.0;
	if (burst > 0.0) {
		local.xz += vec2(cos(ang), sin(ang)) * b * (1.5 + 2.5 * cd.z) * (0.5 + r_bottom);
		local.y = mix(local.y, 0.0, burst * burst);
	}
	// grow in at the foot, shrink out at the top; the tumbleweed (kind 3) bigger
	float s = (kind > 2.5 ? 0.6 : 0.2 + 0.22 * sz) * size;
	s *= smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.82, 1.0, h));
	s *= clamp(max(amount, burst > 0.0 ? 1.0 - burst : 0.0), 0.0, 1.0);
	vec3 wc = (MODEL_MATRIX * vec4(local, 1.0)).xyz;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	float rot = t * (kind > 2.5 ? 5.0 : 9.0) * (cd.z - 0.45) + cd.x * 20.0;
	vec2 cs = vec2(cos(rot), sin(rot));
	vec2 p = vec2(VERTEX.x * cs.x - VERTEX.y * cs.y, VERTEX.x * cs.y + VERTEX.y * cs.x);
	vec3 world = wc + (right * p.x + up * p.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV - 0.5;
	float k = v_kind;
	bool on = false;
	vec3 c;
	if (k < 0.5) {
		// a clod: a lumpy dark blob
		float ang = atan(p.y, p.x);
		on = length(p) < 0.36 + 0.07 * sin(ang * 5.0 + v_seed) + 0.04 * sin(ang * 3.0 - v_seed * 2.0);
		c = vec3(0.24, 0.16, 0.1);
	} else if (k < 1.5) {
		// a twig with a fork
		on = seg(p, vec2(-0.44, -0.12), vec2(0.44, 0.1)) < 0.065 || seg(p, vec2(0.08, 0.03), vec2(0.28, 0.3)) < 0.05;
		c = vec3(0.3, 0.19, 0.1);
	} else if (k < 2.5) {
		// a chip of bark
		vec2 q = vec2(p.x * 0.8 + p.y * 0.6, -p.x * 0.6 + p.y * 0.8);
		on = abs(q.x) * 1.0 + abs(q.y) * 2.2 < 0.42;
		c = vec3(0.42, 0.29, 0.17);
	} else {
		// a little tumbleweed: a scribbled ball
		float r = length(p);
		on = abs(r - 0.36) < 0.05;
		on = on || (r < 0.4 && (abs(p.x * 0.8 + p.y * 0.6) < 0.035 || abs(p.x * 0.3 - p.y * 0.95) < 0.035 || abs(p.x * 0.95 + p.y * 0.3 - 0.1) < 0.03));
		on = on || abs(length(p - vec2(0.06, -0.04)) - 0.2) < 0.035;
		c = vec3(0.46, 0.33, 0.18);
	}
	if (!on) {
		discard;
	}
	ALBEDO = c * mix(vec3(1.0), color.rgb * 1.25, 0.25);
}
