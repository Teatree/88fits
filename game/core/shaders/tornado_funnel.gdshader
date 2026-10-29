// A tornado's funnel (pass 113, lane TWISTER; core/systems/TornadoFx.gd). One tube mesh (UV.x round it 0..1, UV.y up
// it 0..1), shaped here every frame from the uniforms, so nothing is rebuilt on the CPU: narrow at the foot, flaring to
// the top (r_bottom..r_top, `flare` the curve), leaning (`lean`, metres the top is pushed, the node's own motion and a
// slow wander) and snaking (`snake`, metres the middle waves), with lumps of dust rolling up it. Helical bands climb
// it (`bands` up its height, one band spacing a turn, turning with `spin`, warped by the noise): dark bands, the dust's
// colour and pale streaks (the pale keeps the sand's hue, so a stage's filter tints it like the sand), shaded round (a
// lit side, a shaded side, an inked silhouette). The outside (front faces) is the dust, the inside (back faces, seen
// through the open top) its far wall in shadow.
//   layer 0  the funnel: dense (hard painted edges), its top frays into the air, the rising edge while forming (`grow`)
//   layer 1  the wisps: a looser shell round it (radius x wisp_scale) of pale streaks only, turning faster
// `thin` (1 full .. 0 gone) ropes the funnel out (narrower) and opens holes in it as it collapses. Only the dense dust
// writes depth (depth_draw_always, the rest discarded), so the ground marks, shadows and gems drawn after the stage's
// filter never show through it and the skirt and the debris sort against it.
// It writes the scenery's stencil (4, SceneryStencil.VALUE): the stage's filter tints it as it tints the sand, and a
// creature behind the funnel (one it spins round it) shows its outline through the dust as one behind a cactus does.
// The skirt writes none, so a gem lying in front of the dust at its foot is never cut (gems draw only on stencil 0).
// The shape (tw_radius, tw_axis, tw_y) is repeated in tornado_debris.gdshader: keep them in step.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix, shadows_disabled;
stencil_mode write, compare_always, 4;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(0.78, 0.58, 0.38, 1.0);
uniform int layer = 0;
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
uniform float wisp_scale = 1.22;
uniform float alpha_max = 0.94;
// helical bands up its height
uniform float bands = 4.0;

varying float v_rim;

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
	float v = UV.y;
	float a = UV.x * TAU;
	float lump = 1.0 + 0.1 * sin(a * 2.0 + v * 9.0 - t * spin * 6.3) + 0.05 * sin(a * 5.0 - v * 13.0 + t * 2.3);
	float scale = layer == 1 ? wisp_scale + 0.12 * sin(a * 2.0 + v * 5.0 - t * spin * 4.0) : 1.0;
	float r = tw_radius(v) * lump * scale;
	vec2 ax = tw_axis(v);
	VERTEX = vec3(ax.x + cos(a) * r, tw_y(v), ax.y + sin(a) * r);
	// out from the axis, tipped down as the funnel flares
	float dy = 0.03 * height * mix(0.4, 1.0, grow);
	float dr = (tw_radius(v + 0.03) - tw_radius(v - 0.03)) / max(dy * 2.0, 0.001);
	NORMAL = normalize(vec3(cos(a), -dr, sin(a)));
	v_rim = v;
}

void fragment() {
	float v = UV.y;
	float u = UV.x;
	float sp = t * spin;
	float fast = layer == 1 ? 1.6 : 1.0;
	// the noise that roughens everything (u x 2: seamless round the tube)
	float n1 = texture(noise_tex, vec2(u * 2.0 - sp * 0.5 * fast + v * 0.7, v * 0.9 - t * 0.15)).r;
	float n2 = texture(noise_tex, vec2(u * 3.0 - sp * 1.1 * fast + v * 1.9 + 0.37, v * 2.6 - t * 0.3)).r;
	// helical bands climbing round it: one band spacing a turn, turning with the spin, warped by the noise
	float ph = v * bands + u - sp * fast + (n1 - 0.5) * 0.7;
	float wave = sin(TAU * ph);
	float stripe = smoothstep(-0.25, 0.3, wave);
	float hl = smoothstep(0.55, 0.85, sin(TAU * (ph * 2.0 + 0.3)) * 0.5 + 0.5 + (n2 - 0.5) * 0.9);
	vec3 base = color.rgb;
	vec3 dark = base * vec3(0.55, 0.47, 0.42);
	// the pale dust keeps the sand's hue, so a stage's filter tints it as it tints the sand
	vec3 light = mix(base, vec3(0.99, 0.88, 0.7), 0.7);
	vec3 n = normalize(NORMAL);
	float a;
	vec3 c;
	if (layer == 1) {
		// the wisps: thin pale streaks winding round outside, gone high up
		c = mix(light, vec3(1.0, 0.93, 0.8), 0.3);
		a = smoothstep(0.78, 0.9, sin(TAU * (ph * 1.5 + 0.1)) * 0.5 + 0.5 + (n2 - 0.5) * 0.5) * 0.85;
		a *= smoothstep(0.05, 0.2, v) * (1.0 - smoothstep(grow * 0.55, grow * 0.9, v));
	} else {
		c = mix(dark, base, stripe);
		c = mix(c, light, hl * 0.7);
		if (FRONT_FACING) {
			// round: the screen's upper left lit, the other side shaded, the silhouette inked a touch darker
			float lit = dot(normalize(n.xy + vec2(0.0001)), normalize(vec2(-0.75, 0.55))) * 0.5 + 0.5;
			c *= 0.76 + 0.36 * lit;
			float facing = abs(dot(n, normalize(VIEW)));
			c *= mix(0.52, 1.0, smoothstep(0.05, 0.5, facing));
		} else {
			// the far wall seen through the open top: the same bands, in its own shadow
			c *= 0.8;
		}
		// darker at the foot (in its own dust), paler higher up
		c *= mix(0.84, 1.05, smoothstep(0.0, 0.55, v));
		// the top breaks up along the bands into the air (and, while forming, the rising edge); the foot melts into the skirt
		float edge = grow - v + wave * 0.12 + (n2 - 0.5) * 0.2;
		a = alpha_max * smoothstep(0.02, 0.3, edge) * smoothstep(0.0, 0.06, v);
	}
	// collapsing: holes open by the noise until nothing is left
	float hole = 1.0 - thin;
	a *= smoothstep(hole - 0.06, hole + 0.06, n1 * 0.55 + n2 * 0.45 + 0.04);
	// painted, not a haze: a hard edge, and only dense dust is drawn (and writes depth)
	if (a < 0.42) {
		discard;
	}
	ALBEDO = c;
	ALPHA = clamp(a * 1.25, 0.0, layer == 1 ? min(0.85, alpha_max) : alpha_max);
}
