// Dry Gulch terrain: sand and cracked earth blended by the vertex colour's red channel (set by the map
// builder: 0 = sand, 1 = riverbed), world-space UVs so the tiling never stretches, slight vertex tint.
shader_type spatial;
render_mode cull_back;

uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cracked_tex : source_color, filter_linear_mipmap, repeat_enable;
// the rim: red rock by the vertex colour's blue channel (Red Canyon); Dry Gulch never set it
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
// pass 81 (lane MAP): three smooth tileable noises (r, g, b; art/env/noise_rgb.png), read raw: the sand's large-scale
// light and shade (so the painting's 11 m repeat stops showing) and the oasis ground's ragged edge and its green
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// pass 79 (Garry: "Map the sides are too orange"): the rim's colour, Red Canyon's `rock_color` (was 0.62, 0.34, 0.24). The
// rock painting is recoloured to it: its luminance over its own mean (rock_tex_lum, linear) times this, so its bands and
// cracks stay as light and dark and the colour on the screen is the map's, whatever the painting's own hue
uniform vec3 rock_flat : source_color = vec3(0.47, 0.36, 0.37);
uniform float rock_tex_lum = 0.184;
uniform float tiles_per_metre = 0.09;
// pass 82 (lane SAND): the sand painting's own size on the ground, x the tiling above (the map's sand choice sets it,
// RedCanyon.SANDS; 1 = 11 m a tile like pass 81's): only the sand's, the river bed and the rock keep theirs
uniform float sand_scale = 1.0;
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
// pass 81: the sand's large-scale variation: the noise tiles every 1 / macro_scale metres and moves the light that much
// either way
uniform float macro_scale = 0.019;
uniform float macro_strength : hint_range(0.0, 0.5) = 0.07;
// pass 81 (Garry: "Do a bit of a ground texture shading around the water. Basically make it look more natural, like an
// oasis."): the vertex colour's alpha is the oasis ground (RedCanyon.oasis_wet: 1 at the water, 0 on the dry sand). Its
// edge is broken up by the noise (oasis_ragged), then: damp earth (oasis_damp, a multiplier in linear light) from
// oasis_damp_from, sparse green patches on the damp ground (oasis_grass, oasis_grass_amount), and wet sand
// (oasis_wet) from oasis_wet_from to the water and under it
uniform float oasis_ragged = 0.32;
uniform float oasis_damp_from = 0.1;
uniform float oasis_wet_from = 0.72;
uniform vec3 oasis_damp = vec3(0.93, 0.90, 0.80);
uniform vec3 oasis_wet = vec3(0.80, 0.77, 0.72);
// wet sand is darker and a little greyer, not oranger: this much of its colour goes to grey first
uniform float oasis_wet_grey : hint_range(0.0, 1.0) = 0.3;
uniform vec3 oasis_grass : source_color = vec3(0.40, 0.52, 0.27);
uniform float oasis_grass_amount : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_world;
varying vec4 v_col;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
}

void fragment() {
	vec2 uv = v_world.xz * tiles_per_metre;
	vec3 s = texture(sand_tex, uv * sand_scale).rgb;
	vec3 c = texture(cracked_tex, uv * 0.8).rgb;
	float mixw = smoothstep(0.15, 0.85, v_col.r);
	float rockw = smoothstep(0.2, 0.9, v_col.b);
	vec3 col = mix(s, c, mixw);
	vec3 rk = texture(rock_tex, uv * 0.7).rgb;
	// the painting is sampled in linear light while the Compatibility renderer hands the colour over as authored (as the
	// calm mix below has always used it), so it is brought into linear light before it recolours the painting
	rk = pow(rock_flat, vec3(2.2)) * (dot(rk, vec3(0.299, 0.587, 0.114)) / max(rock_tex_lum, 0.001));
	col = mix(col, rk, rockw);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), 0.2);
	vec3 flat_col = mix(mix(sand_flat, cracked_flat, mixw), rock_flat, rockw);
	col = mix(col, flat_col * (0.7 + 0.5 * lum), calm) * 0.95;
	// vertex colour green carries the scorch/shade variation from the builder
	col *= mix(1.0, v_col.g, tint_strength);
	// pass 81: broad light and shade over the sand (none on the rock), the painting's repeat lost under it
	vec3 big = texture(noise_tex, v_world.xz * macro_scale).rgb;
	col *= 1.0 + (big.r - 0.5) * 2.0 * macro_strength * (1.0 - rockw);
	// pass 81: the oasis ground
	vec3 fine = texture(noise_tex, v_world.xz * 0.12).rgb;
	float wet_k = clamp(v_col.a + (fine.r - 0.5) * oasis_ragged + (big.g - 0.5) * oasis_ragged * 0.6, 0.0, 1.0);
	float damp = smoothstep(oasis_damp_from, oasis_damp_from + 0.3, wet_k);
	float wet = smoothstep(oasis_wet_from, oasis_wet_from + 0.16, wet_k);
	col *= mix(vec3(1.0), oasis_damp, damp);
	float grass = damp * (1.0 - wet) * smoothstep(0.48, 0.66, fine.b * 0.7 + big.b * 0.3);
	col = mix(col, oasis_grass * (0.75 + 0.5 * fine.g), grass * oasis_grass_amount);
	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), wet * oasis_wet_grey);
	col *= mix(vec3(1.0), oasis_wet, wet);
	col = mix(col, col * vec3(0.97, 0.79, 0.72) + vec3(0.02, 0.0, 0.0), hell);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
