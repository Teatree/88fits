// The Big Mouth's beam (pass 33.2): one camera-facing ribbon from the lips to the end of its reach. A white-hot core,
// the beam's colour either side of it fading to nothing at the ribbon's edges, a ripple running down the line, and a
// fade at the far end. Alpha-blended, so the pink holds its colour over bright sand (additive washed it to white).
// UV.x runs across the ribbon, UV.y from the far end (0) to the lips (1).
// Pass 61, Bad Breath: `haze` is the glow's own colour (its alpha how much of it shows over `color`), and `wobble` sets
// the line snaking from side to side and breathing wider and thinner as it runs out, still at the lips; 0 = the old beam.
// `core_color` and `glow_gain` let it keep its sickly colour to the middle of the line.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.7, 1.0);
uniform vec4 haze : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float wobble = 0.0;
// the colour the core runs to (white; Bad Breath's a pale green-yellow) and how strong the glow round it is
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float glow_gain = 1.0;

void fragment() {
	float along = 1.0 - UV.y;
	float w = wobble * smoothstep(0.0, 0.14, along);
	float sway = w * (0.2 * sin(along * 24.0 - TIME * 15.0) + 0.07 * sin(along * 57.0 + TIME * 23.0));
	float swell = 1.0 + w * 0.4 * sin(along * 10.0 - TIME * 9.0);
	float x = abs(UV.x * 2.0 - 1.0 - sway) / swell;
	float core = exp(-x * x * 55.0);
	float glow = exp(-x * x * 7.0);
	float ripple = 0.82 + 0.18 * sin(along * 70.0 - TIME * 42.0);
	float ends = smoothstep(0.0, 0.03, along) * (1.0 - smoothstep(0.86, 1.0, along));
	vec3 glow_col = mix(color.rgb, haze.rgb, haze.a * smoothstep(0.02, 0.3, x));
	ALBEDO = mix(glow_col * 1.15, core_color.rgb, clamp(core * 1.4, 0.0, 1.0));
	ALPHA = clamp((glow * 0.78 * glow_gain * ripple + core) * ends, 0.0, 1.0);
}
