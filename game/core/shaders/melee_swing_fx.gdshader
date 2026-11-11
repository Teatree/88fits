// The Sabre's swing, pass 141 (lane MELEE; core/systems/MeleeFx.gd styles "moon" and "cyclic"; Garry's references: his
// 2D pack _REFERENCES/2d/Everything row 1 "a crescent turning", and godotshaders.com's "Procedural Cyclic Slash" by
// Alkaliii, CC0). The same quad, arc and ground fit as melee_slash.gdshader (VERTEX.xz -1..1, its -Z the arc's centre,
// `pull`), the same uniforms, so MeleeFx drives both alike.
//   style 1 "moon": the pack's crescent painted on the arc: each of its six frames unwrapped along its crescent
//     (art/fx/melee/slash_moon.png: x from its trailing end to its leading end, y from the inside to the outside; R
//     coverage, G heat, B sheath), the leading end riding at the swing's head, `fr` the frame; tinted heat 0 `edge_col`,
//     0.5 `smear_col`, 1 `core_col`, a dark sheath under it; on the way out eaten by noise.
//   style 2 "cyclic": the CC0 shader's recipe on the arc: a cellular noise (art/fx/melee/slash_noise.png) scrolled along
//     the arc by the swing's progress, minus a width mask (soft inside, hard at the rim) and a length mask (a window
//     behind the head), shown above a threshold that falls as it sweeps and rises as it goes, a bright line on the rim.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D frames : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D noise : filter_linear, repeat_enable, hint_default_black;
uniform int style = 1;
uniform float half_w = 1.3;
uniform float r_in = 0.35;
uniform float r_out = 0.89;
uniform float head = 1.0;
uniform float sweep_sign = 1.0;
uniform float fade = 1.0;
uniform float diss = 0.0;
uniform float trail = 1.4;
uniform float fr = 0.0;
uniform float frame_n = 6.0;
uniform float seed = 0.0;
uniform float pull = 0.0;
uniform vec4 edge_col : source_color = vec4(0.38, 0.66, 1.0, 1.0);
uniform vec4 smear_col : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);
uniform vec4 shade_col : source_color = vec4(0.04, 0.05, 0.12, 1.0);
uniform float shade_a = 0.8;

varying vec2 v_p;

void vertex() {
	v_p = VERTEX.xz;
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (PROJECTION_MATRIX[3][3] == 0.0) {
		v *= max(1.0 - pull / max(length(c), 0.001), 0.05);
	} else {
		v.z += pull;
	}
	VERTEX = v;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void over(inout vec3 c, inout float a, vec3 lc, float la) {
	la = clamp(la, 0.0, 1.0);
	c = lc * la + c * (1.0 - la);
	a = la + a * (1.0 - la);
}

// as the burst's: the deep end the edge colour squared (deeper, more saturated), white only in the hot middle
vec3 ramp(float h) {
	vec3 deep = edge_col.rgb * edge_col.rgb;
	return h < 0.4 ? mix(deep, edge_col.rgb, h / 0.4) : (h < 0.78 ? mix(edge_col.rgb, smear_col.rgb, (h - 0.4) / 0.38) : mix(smear_col.rgb, core_col.rgb, (h - 0.78) / 0.22));
}

vec3 frame_at(vec2 uv, float k) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec3(0.0);
	}
	float e = 0.5 / 64.0;
	return texture(frames, vec2(uv.x, (k + clamp(uv.y, e, 1.0 - e)) / frame_n)).rgb;
}

void fragment() {
	float r = length(v_p);
	float ang = atan(-v_p.x, -v_p.y);
	if (abs(ang) > half_w + 0.03 || r > 1.0) {
		discard;
	}
	// along the arc: 0 the end the sweep starts from, 1 the other
	float s = clamp((ang * sweep_sign / max(half_w, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = vec3(0.0);
	float a = 0.0;
	if (style == 2) {
		// ---- cyclic: noise scrolled along the arc, masked to the band and to a window behind the head
		float band = max(r_out - r_in, 0.02);
		float rb = (r - r_in) / band;
		float p = head < 0.999 ? head * 0.5 : 0.5 + diss * 0.5;
		float b = texture(noise, vec2(s * 1.6 - p * 1.4 + seed * 0.37, rb * 0.55 + seed * 0.11)).r;
		float wm = rb > 1.0 ? smoothstep(1.0, 1.03, rb) * 2.0 : (1.0 - smoothstep(-0.05, 0.85, rb)) * 0.9;
		float win = max(trail * 0.5, 0.2);
		float lm = max(smoothstep(0.0, 0.012, s - head), (1.0 - smoothstep(head - win, head - win * 0.3, s)) * 0.85);
		float pre = b - wm - lm;
		float th = head < 0.999 ? 0.06 + 0.2 * (1.0 - head) : 0.06 + diss * 1.0;
		float body = smoothstep(th - 0.03, th + 0.03, pre);
		float halo = smoothstep(th - 0.2, th - 0.02, pre);
		float high = (1.0 - smoothstep(0.0, 0.035, abs(rb - 0.96))) * (1.0 - lm) * (1.0 - diss);
		over(c, a, shade_col.rgb, shade_a * 0.6 * halo);
		over(c, a, ramp(clamp(pre * 1.8 + 0.15, 0.0, 1.0)), body);
		over(c, a, core_col.rgb, high * 0.9);
	} else {
		// ---- moon: the pack's crescent along the arc, its leading end at the head
		float xt = s + (1.0 - head);
		float lo = r_in - 0.06;
		float hi = r_out + 0.04;
		vec2 uv = vec2(xt, (r - lo) / max(hi - lo, 0.02));
		float k0 = floor(fr);
		float k1 = min(k0 + 1.0, frame_n - 1.0);
		vec3 t = mix(frame_at(uv, k0), frame_at(uv, k1), smoothstep(0.25, 0.75, fr - k0));
		float keep = 1.0;
		if (diss > 0.0) {
			float n = texture(noise, vec2(s * 2.2 + seed * 0.37, r * 1.7)).r;
			keep = 1.0 - smoothstep(n - 0.08, n + 0.08, diss * 1.3 - 0.15);
		}
		// soft at the frame's borders and at the arc's start (no straight cut where the sheath meets them)
		float ends = smoothstep(0.0, 0.08, xt) * (1.0 - smoothstep(0.93, 1.0, xt)) * smoothstep(0.0, 0.1, s);
		float rim = smoothstep(0.0, 0.12, uv.y) * (1.0 - smoothstep(0.88, 1.0, uv.y));
		over(c, a, shade_col.rgb, shade_a * 0.9 * t.b * keep * ends * rim);
		over(c, a, ramp(t.g), t.r * keep * ends);
	}
	float alpha = a * fade;
	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = c / max(a, 0.0001);
	ALPHA = alpha;
}
