// Personal Storm's cloud shadows (pass 119, lane LEGEND_A; core/systems/PersonalStorm.gd): a polar disc mesh of unit
// radius (UV.x 0 at the middle .. 1 at the rim) laid over the terrain round `center` from the map's height grid (the
// same bilinear step as MapBase.height_at and ground_mark.gdshader), darkened by soft cloud shapes that drift with the
// wind. The clouds come in as a front: `cover_in` 0..1 sweeps their leading edge across the circle from upwind, and
// `cover_out` 0..1 sweeps their trailing edge after it, so they pass on downwind when the storm is over. Drawn after the opaque world, no depth writes: it darkens the sand under the creatures, never them.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform, fog_disabled;

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform vec2 center = vec2(0.0);
uniform float radius = 9.0;
uniform float cover_in : hint_range(0.0, 1.0) = 0.0;
uniform float cover_out : hint_range(0.0, 1.0) = 0.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.4;
uniform vec2 wind = vec2(1.0, 0.4);
uniform vec3 shade : source_color = vec3(0.05, 0.07, 0.16);

varying vec2 v_world;
varying float v_r;

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

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec2 p = center + VERTEX.xz * radius;
	v_world = p;
	v_r = length(VERTEX.xz);
	vec3 world = vec3(p.x, ground(p) + 0.12, p.y);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec2 q = v_world * 0.11 - wind * TIME * 0.09;
	float n = vnoise(q) * 0.62 + vnoise(q * 2.3 + vec2(5.2, 1.3) - wind * TIME * 0.05) * 0.38;
	float cloud = smoothstep(0.3, 0.75, n);
	// the front: -1 upwind .. +1 downwind across the circle, its edge ragged by the clouds
	vec2 wd = normalize(wind);
	float along = dot(v_world - center, wd) / max(radius, 0.1) + (n - 0.5) * 0.45;
	float lead = -1.3 + cover_in * 2.7;
	float trail = -1.3 + cover_out * 2.7;
	float k = (1.0 - smoothstep(lead - 0.3, lead, along)) * smoothstep(trail - 0.3, trail, along);
	// a soft, ragged rim
	float rim = 1.0 - smoothstep(0.72 + (n - 0.5) * 0.2, 1.0, v_r);
	ALBEDO = shade;
	ALPHA = clamp(darkness * (0.25 + 0.75 * cloud) * k * rim, 0.0, darkness);
}
