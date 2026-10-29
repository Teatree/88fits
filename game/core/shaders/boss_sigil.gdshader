// The Brander's brand sigil (pass 113, lane BOSS; BossPatternFx): a glowing mark a dozen metres across burnt into the
// sand under him for his Hellbrand Mandala. A subdivided plane laid over the terrain vertex by vertex from the map's
// height grid (as Telegraphs' marks: heights, grid_n, half_size, resolution), drawn additive after the stage filter so
// the Blood Moon's red never swallows it. Its rings, a five-point star, ticks between the rings and the iron's mark in the
// middle burn in round the circle as `fill` goes 0 -> 1 and brighten with `power`.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.42, 0.1, 1.0);
uniform float fill = 1.0;
uniform float power = 1.0;
uniform float radius = 6.0;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform float lift = 0.07;

varying vec2 v_p;

float ground(vec2 p) {
	if (grid_n < 2) {
		return 0.0;
	}
	float top = float(grid_n - 1) - 0.001;
	float fx = clamp((p.x + half_size) * resolution, 0.0, top);
	float fz = clamp((p.y + half_size) * resolution, 0.0, top);
	int ix = int(fx);
	int iz = int(fz);
	float tx = fx - float(ix);
	float tz = fz - float(iz);
	float h00 = texelFetch(heights, ivec2(ix, iz), 0).r;
	float h10 = texelFetch(heights, ivec2(ix + 1, iz), 0).r;
	float h01 = texelFetch(heights, ivec2(ix, iz + 1), 0).r;
	float h11 = texelFetch(heights, ivec2(ix + 1, iz + 1), 0).r;
	return mix(mix(h00, h10, tx), mix(h01, h11, tx), tz);
}

void vertex() {
	v_p = VERTEX.xz / max(radius, 0.01);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float g = grid_n >= 2 ? ground(w.xz) : MODEL_MATRIX[3].y;
	VERTEX = (VIEW_MATRIX * vec4(w.x, g + lift, w.z, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = v_p;
	float r = length(p);
	if (r > 1.02) {
		discard;
	}
	float a = atan(p.y, p.x);
	// how far round it has burnt in: the angle's share from the top, clockwise
	float share = fract((a + 1.5708) / 6.28318 + 1.0);
	float lit = smoothstep(fill + 0.02, fill - 0.02, share);
	if (fill >= 0.999) {
		lit = 1.0;
	}
	// distance to the nearest line of the mark (in units of the radius)
	float d = abs(r - 0.95) - 0.028;
	d = min(d, abs(r - 0.8) - 0.018);
	d = min(d, abs(r - 0.2) - 0.03);
	// the star: each point to the one two along
	for (int k = 0; k < 5; k++) {
		float a0 = 1.5708 + 6.28318 * float(k) / 5.0;
		float a1 = 1.5708 + 6.28318 * float(k + 2) / 5.0;
		d = min(d, seg(p, vec2(cos(a0), sin(a0)) * 0.78, vec2(cos(a1), sin(a1)) * 0.78) - 0.016);
	}
	// ticks between the rings
	float tick = abs(fract(a * 30.0 / 6.28318) - 0.5) * 6.28318 / 30.0 * r;
	if (r > 0.82 && r < 0.93) {
		d = min(d, tick - 0.012);
	}
	// the iron's bar in the middle
	d = min(d, max(abs(p.y) - 0.035, abs(p.x) - 0.17));
	float line = smoothstep(0.012, -0.004, d);
	float halo = exp(-max(d, 0.0) * 28.0) * 0.45;
	float flick = 0.88 + 0.12 * sin(TIME * 9.0 + r * 13.0) * sin(TIME * 5.3 + a * 3.0);
	float k = (line + halo) * lit * flick;
	// a scorched glow inside the outer ring
	k += smoothstep(1.0, 0.0, r) * 0.12 * power * lit;
	vec3 c = color.rgb * (0.45 + 1.1 * power) + vec3(0.25, 0.18, 0.08) * line * power;
	ALBEDO = c * k;
}
