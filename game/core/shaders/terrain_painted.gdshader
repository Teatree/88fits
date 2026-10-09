// Dry Gulch terrain: sand and cracked earth blended by the vertex colour's red channel (set by the map
// builder: 0 = sand, 1 = riverbed), world-space UVs so the tiling never stretches, slight vertex tint.
shader_type spatial;
render_mode cull_back;

uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cracked_tex : source_color, filter_linear_mipmap, repeat_enable;
// the rim: red rock by the vertex colour's blue channel (Red Canyon); Dry Gulch never set it
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_flat : source_color = vec3(0.62, 0.34, 0.24);
uniform float tiles_per_metre = 0.09;
uniform float tint_strength = 0.6;
// how far the painted texture is flattened towards a plain colour: busy dunes fight the sprites, so 0.4 by default
uniform float calm : hint_range(0.0, 1.0) = 0.4;
// pass 54: a little lighter and less orange (were 0.86, 0.68, 0.42 and 0.62, 0.44, 0.30); Red Canyon sets both from its
// sand_color / river_color exports, so the ground has a tuning knob. Pass 61: the sand lighter again (was 0.88, 0.72,
// 0.48) and the river bed the sand a little browner (was 0.66, 0.50, 0.36)
uniform vec3 sand_flat : source_color = vec3(0.90, 0.78, 0.58);
uniform vec3 cracked_flat : source_color = vec3(0.80, 0.67, 0.50);
// hell (pass 43): stage 3 turns the ground a shade redder and darker; the map tweens it in over a few seconds
uniform float hell : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;
varying vec4 v_col;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
}

void fragment() {
	vec2 uv = v_world.xz * tiles_per_metre;
	vec3 s = texture(sand_tex, uv).rgb;
	vec3 c = texture(cracked_tex, uv * 0.8).rgb;
	float mixw = smoothstep(0.15, 0.85, v_col.r);
	float rockw = smoothstep(0.2, 0.9, v_col.b);
	vec3 col = mix(s, c, mixw);
	vec3 rk = texture(rock_tex, uv * 0.7).rgb;
	col = mix(col, rk, rockw);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), 0.2);
	vec3 flat_col = mix(mix(sand_flat, cracked_flat, mixw), rock_flat, rockw);
	col = mix(col, flat_col * (0.7 + 0.5 * lum), calm) * 0.95;
	// vertex colour green carries the scorch/shade variation from the builder
	col *= mix(1.0, v_col.g, tint_strength);
	col = mix(col, col * vec3(0.97, 0.79, 0.72) + vec3(0.02, 0.0, 0.0), hell);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
