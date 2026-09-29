// The Big Mouth's beam (pass 33.2): one camera-facing ribbon from the lips to the end of its reach. A white-hot core,
// the beam's colour either side of it fading to nothing at the ribbon's edges, a ripple running down the line, and a
// fade at the far end. Alpha-blended, so the pink holds its colour over bright sand (additive washed it to white).
// UV.x runs across the ribbon, UV.y from the far end (0) to the lips (1).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.7, 1.0);

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float along = 1.0 - UV.y;
	float core = exp(-x * x * 55.0);
	float glow = exp(-x * x * 7.0);
	float ripple = 0.82 + 0.18 * sin(along * 70.0 - TIME * 42.0);
	float ends = smoothstep(0.0, 0.03, along) * (1.0 - smoothstep(0.86, 1.0, along));
	ALBEDO = mix(color.rgb * 1.15, vec3(1.0), clamp(core * 1.4, 0.0, 1.0));
	ALPHA = clamp((glow * 0.78 * ripple + core) * ends, 0.0, 1.0);
}
