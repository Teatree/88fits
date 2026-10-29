// A tornado's skirt (pass 113, lane TWISTER; core/systems/TornadoFx.gd): the dust churning on the ground round its foot.
// One ring mesh (UV.x round it 0..1, UV.y out from the foot 0..1) raised here into a lumpy bank of dust, highest a third
// of the way out and down to the sand at its rim, billows turning round the foot and rolling outwards. `amount` (0..1)
// grows it (the first thing a forming tornado shows); `burst` (0..1, 0 = none) is the collapse's puff: the bank thrown
// out, puffed up and gone. Like the funnel only dense dust is drawn and writes depth, so the funnel's foot sorts behind
// the near side of the bank and in front of the far side.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(0.78, 0.58, 0.38, 1.0);
uniform float t = 0.0;
uniform float spin = 0.9;
uniform float r_inner = 0.5;
uniform float r_outer = 2.2;
uniform float bank = 0.9;
uniform float amount = 1.0;
uniform float burst = 0.0;
uniform float alpha_max = 0.92;

void vertex() {
	float s = UV.y;
	float a = UV.x * TAU;
	float b = burst > 0.0 ? 1.0 - (1.0 - burst) * (1.0 - burst) : 0.0;
	float r = mix(r_inner, r_outer, s) * mix(0.45, 1.0, amount) * (1.0 + 1.5 * b);
	float wob = 1.0 + 0.3 * sin(a * 5.0 + t * spin * 3.0) * sin(a * 3.0 - t * 1.7 + s * 4.0);
	float hump = pow(sin(3.14159 * clamp(s * 1.25 + 0.08, 0.0, 1.0)), 0.75);
	float y = bank * hump * wob * mix(0.25, 1.0, amount) * (1.0 + 0.8 * b);
	VERTEX = vec3(cos(a) * r, y, sin(a) * r);
}

void fragment() {
	float s = UV.y;
	float u = UV.x;
	// billows turning round the foot and rolling out
	float n1 = texture(noise_tex, vec2(u * 4.0 - t * spin * 0.8, s * 1.1 - t * 0.35)).r;
	float n2 = texture(noise_tex, vec2(u * 7.0 + t * spin * 0.5 + 0.21, s * 2.0 - t * 0.6)).r;
	float puff = smoothstep(0.35, 0.65, n1 * 0.7 + n2 * 0.3);
	vec3 base = color.rgb;
	vec3 light = mix(base, vec3(0.99, 0.88, 0.7), 0.6);
	vec3 shade = mix(base, light, 0.15) * vec3(0.84, 0.8, 0.77);
	vec3 c = mix(shade, light, puff);
	// the inside of the bank, by the foot, in the funnel's shadow
	c *= mix(0.78, 1.0, smoothstep(0.0, 0.45, s));
	// a ragged outer rim, a soft inner edge under the funnel's foot
	float rim = (1.0 - s) + (n1 - 0.5) * 0.55;
	float a = alpha_max * smoothstep(0.02, 0.16, rim) * smoothstep(0.0, 0.12, s + n2 * 0.08);
	a *= clamp(amount * 1.6, 0.0, 1.0);
	if (burst > 0.0) {
		a *= pow(1.0 - burst, 1.3);
		a *= smoothstep(burst * 0.7 - 0.1, burst * 0.7 + 0.1, n1);
	}
	if (a < 0.4) {
		discard;
	}
	ALBEDO = c;
	ALPHA = clamp(a * 1.2, 0.0, alpha_max);
}
