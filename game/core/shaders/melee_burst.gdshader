// The Spear's thrust, pass 141 (lane MELEE; core/systems/MeleeFx.gd style "burst"; Garry: "Still look bad ... it's the
// spear that's the real problem", his 2D pack _REFERENCES/2d/Everything, row 4 "a thrust"). A flipbook of the pack's
// Classic row 4 (art/fx/melee/thrust_burst.png, tools/dl/p141/MELEE/make_melee_fx.py: six frames stacked top to bottom,
// each turned so the stroke runs +x, its head (the arrowhead with the flames streaming back from it) on the right, its
// long thin tail on the left; R coverage, G heat, B a soft sheath) tinted by the weapon's colours: heat 0 `glow_col`,
// 0.5 `body_col`, 1 `core_col` (the pack's orange its deep / yellow / pale), a dark sheath under it so it reads on the
// pale sand. One quad (VERTEX.z 0 .. -1 down the thrust, VERTEX.x -1..1 across, the node scaled to `quad_len` x
// `quad_half` metres) at the Outlaw's waist: laid flat (`face_cam` 0) or turned to the camera round its own line
// (`face_cam` 1: the same length on the ground, its width square to the eye). Measured in metres along (s, 0 at `s0`
// into the quad: his hand) and across (x).
//   tail_s  where the stroke's tail starts (metres from the hand); pt where its head (the point) is now (the dart eases
//           it out to the reach, the hit lands as it arrives; the last big frame grows on a little past it); half_w the
//           stroke's half width; glint_s where the glint sparkles
//   fr      the frame (0..5.999, two frames mixed); fade the strength left; glint the hand's / the landing's sparkle;
//           pierce a hit's flare at the head; heat / heat_col Heartseeker's warming; crackle the Thunder Lance's zigzag
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D frames : filter_linear, repeat_disable, hint_default_black;
uniform float face_cam = 0.0;
uniform float quad_len = 4.5;
uniform float quad_half = 0.8;
uniform float s0 = 0.3;
uniform float tail_s = 0.12;
uniform float pt = 3.0;
uniform float pt_a = 1.0;
uniform float half_w = 0.5;
// the texture's own: where the tail and the head lie along it (0..1), its frame count
uniform float tail_u = 0.035;
uniform float head_u = 0.954;
uniform float frame_n = 6.0;
uniform float fr = 0.0;
uniform float fade = 1.0;
uniform float glint = 0.0;
uniform float glint_s = 0.12;
uniform float pierce = 0.0;
uniform float heat = 0.0;
uniform float crackle = 0.0;
uniform float seed = 0.0;
uniform vec4 glow_col : source_color = vec4(0.36, 0.6, 1.0, 1.0);
uniform vec4 body_col : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);
uniform vec4 heat_col : source_color = vec4(1.0, 0.35, 0.1, 1.0);
uniform vec4 shade_col : source_color = vec4(0.04, 0.05, 0.12, 1.0);
uniform float shade_a = 0.75;

varying vec2 v_p;

void vertex() {
	v_p = vec2(VERTEX.x, -VERTEX.z);
	vec3 o = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 flat_p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (face_cam > 0.5) {
		// turned round its own line to face the eye: the line as laid, the width square to it and to the eye's ray
		vec3 ax = (MODELVIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz;
		vec3 xs = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
		vec3 mid = o + ax * 0.5;
		vec3 w = cross(normalize(ax), normalize(mid));
		if (dot(w, xs) < 0.0) {
			w = -w;
		}
		w = normalize(w) * length(xs);
		VERTEX = o + ax * (-VERTEX.z) + w * VERTEX.x;
	} else {
		VERTEX = flat_p;
	}
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

void over(inout vec3 c, inout float a, vec3 lc, float la) {
	la = clamp(la, 0.0, 1.0);
	c = lc * la + c * (1.0 - la);
	a = la + a * (1.0 - la);
}

// a thin ray of `len` along p.x, `w` wide at its root, fading to its end
float ray(vec2 p, float len, float w) {
	float x = abs(p.x) / len;
	if (x > 1.0) {
		return 0.0;
	}
	return (1.0 - smoothstep(w * (1.0 - x) * 0.4, w * (1.0 - x), abs(p.y))) * (1.0 - x);
}

vec3 tex_at(vec2 uv, float k) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec3(0.0);
	}
	float e = 0.5 / 192.0;
	return texture(frames, vec2(uv.x, (k + clamp(uv.y, e, 1.0 - e)) / frame_n)).rgb;
}

void fragment() {
	float s = v_p.y * quad_len - s0;
	float x = v_p.x * quad_half;
	vec3 c = vec3(0.0);
	float a = 0.0;
	vec3 glow = mix(glow_col.rgb, heat_col.rgb, heat);
	vec3 body = mix(body_col.rgb, mix(heat_col.rgb, vec3(1.0, 0.9, 0.75), 0.5), heat);
	if (fr >= 0.0) {
		// the texture's tail at tail_s, its head at pt
		float u = tail_u + (s - tail_s) / max(pt - tail_s, 0.05) * (head_u - tail_u);
		vec2 uv = vec2(u, x / max(2.0 * half_w, 0.01) + 0.5);
		float k0 = floor(fr);
		float k1 = min(k0 + 1.0, frame_n - 1.0);
		float m = smoothstep(0.25, 0.75, fr - k0);
		vec3 t = mix(tex_at(uv, k0), tex_at(uv, k1), m);
		float cov = t.r;
		float hot = t.g;
		// a hit flares the head (the last third of the stroke), white-hot
		float near_head = smoothstep(head_u - 0.35, head_u, u) * (1.0 - smoothstep(head_u, head_u + 0.06, u));
		hot = clamp(hot + pierce * 0.6 * near_head, 0.0, 1.0);
		cov = clamp(cov * (1.0 + pierce * 0.5 * near_head), 0.0, 1.0);
		// the light starts a little out from his hand (it would draw over him)
		float from_hand = smoothstep(0.05, 0.35, s);
		// the sheath soft at the frame's borders (no straight cut along the stroke)
		float border = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.88, 1.0, uv.y)) * smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.96, 1.0, u));
		over(c, a, shade_col.rgb, shade_a * t.b * from_hand * border);
		// the pack's deep orange is most of a frame: the deep end a deeper, more saturated glow (each channel squared),
		// so the stroke keeps its colour on the pale sand; the pale and the white only in its hot middle
		vec3 deep = glow * glow;
		vec3 col = hot < 0.4 ? mix(deep, glow, hot / 0.4) : (hot < 0.78 ? mix(glow, body, (hot - 0.4) / 0.38) : mix(body, core_col.rgb, (hot - 0.78) / 0.22));
		over(c, a, col, cov * from_hand);
		// the Thunder Lance: a broken zigzag of light along both edges of the stroke's body
		if (crackle > 0.001 && s > 0.2 && s < pt) {
			float seg = floor(s / 0.22);
			float f = fract(s / 0.22);
			float zig = mix(hash(seg + 40.0), hash(seg + 41.0), f) * 2.0 - 1.0;
			float y = half_w * 0.48 + zig * 0.07;
			float on = step(0.3, hash(seg + 77.0));
			float l = 1.0 - smoothstep(0.014, 0.032, abs(abs(x) - y));
			float lo = 1.0 - smoothstep(0.03, 0.06, abs(abs(x) - y));
			float life = clamp(1.5 - fr * 0.3, 0.0, 1.0);
			over(c, a, shade_col.rgb, crackle * on * lo * 0.4 * life);
			over(c, a, mix(core_col.rgb, glow, 0.6), crackle * on * l * life);
		}
	}
	float al = a * fade;
	vec3 gc = c / max(a, 0.0001);
	// the glint: a small four-point sparkle at `glint_s` (the gathering at his hand)
	if (glint > 0.001) {
		vec2 p = vec2(s - glint_s, x);
		float st = max(ray(p, 0.5, 0.08), ray(vec2(p.y, p.x), 0.32, 0.07));
		float dot_ = exp(-dot(p, p) * 220.0);
		vec3 pc = gc * al;
		over(pc, al, mix(glow, core_col.rgb, 0.6), glint * st);
		over(pc, al, core_col.rgb, glint * dot_);
		gc = pc / max(al, 0.0001);
	}
	if (al < 0.004) {
		discard;
	}
	ALBEDO = gc;
	ALPHA = al;
}
