// A dust devil's reach on the ground (pass 113, lane TWISTER; world/features/DustDevil.gd): where it throws the hero.
// A disc mesh (UV.x 0 middle .. 1 rim, UV.y round it) laid over the sand from the map's height grid exactly as
// ground_mark.gdshader lays Telegraphs' marks (heights, grid_n, half_size, resolution, lift: Telegraphs._ground_uniforms
// fills them; without a grid it lies flat at the node's height). At its rim a band `band` m wide of dust swirling round
// with the funnel (dark arcs turning, a pale edge line), inside it a faint dusty shade. `alpha` 0..1 (the owner's:
// faint while it forms, full while it grabs, gone as it fades).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform float lift = 0.1;
uniform vec4 color : source_color = vec4(0.78, 0.58, 0.38, 1.0);
uniform float r_out = 2.9;
uniform float band = 0.5;
uniform float alpha = 1.0;
uniform float t = 0.0;
uniform float spin = 0.9;

varying float v_r;

float ground(vec2 p, float fallback) {
	if (grid_n < 2) {
		return fallback;
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
	vec3 c = MODEL_MATRIX[3].xyz;
	float a = UV.y * TAU;
	float r = UV.x * r_out;
	vec2 p = c.xz + vec2(cos(a), sin(a)) * r;
	vec3 world = vec3(p.x, ground(p, c.y) + lift + 0.03, p.y);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	v_r = r;
}

void fragment() {
	float r = v_r;
	float u = UV.y;
	float in_band = smoothstep(r_out - band - 0.06, r_out - band + 0.06, r) * (1.0 - smoothstep(r_out - 0.05, r_out, r));
	// dark arcs of dust turning round with the funnel, broken by the noise
	float n = texture(noise_tex, vec2(u * 6.0 - t * spin * 1.2, r * 0.35 - t * 0.2)).r;
	float arcs = smoothstep(0.35, 0.55, sin(u * TAU * 7.0 - t * spin * TAU * 0.8 + r * 2.5) * 0.5 + 0.5 + (n - 0.5) * 0.6);
	vec3 dark = color.rgb * vec3(0.42, 0.34, 0.3);
	vec3 pale = mix(color.rgb, vec3(0.99, 0.88, 0.7), 0.6);
	// the outer edge line, pale, so the reach reads on dark and light sand alike
	float edge = smoothstep(r_out - 0.16, r_out - 0.09, r) * (1.0 - smoothstep(r_out - 0.05, r_out, r));
	vec3 c = mix(dark, pale, edge);
	float a = in_band * mix(0.38, 0.8, arcs);
	a = max(a, edge * 0.85);
	// a faint dusty shade inside it
	a = max(a, (1.0 - smoothstep(r_out - band - 0.1, r_out - band + 0.05, r)) * 0.14 * (0.7 + 0.6 * n));
	ALBEDO = c;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
