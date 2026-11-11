// A swing, pass 141 (lane MELEE; core/systems/MeleeFx.gd style "cyclic", selectable, on no weapon; Garry's reference
// godotshaders.com's "Procedural Cyclic Slash" by Alkaliii, CC0). The same quad, arc and ground fit as
// melee_slash.gdshader (VERTEX.xz -1..1, its -Z the arc's centre, `pull`), the same uniforms, so MeleeFx drives both
// alike. The CC0 shader's recipe on the arc: a cellular noise (art/fx/melee/slash_noise.png) scrolled along the arc by
// the swing's progress, minus a width mask (soft inside, hard at the rim) and a length mask (a window behind the head),
// shown above a threshold that falls as it sweeps and rises as it goes, a bright line on the rim. Pass 142: pass 141's
// style 1 "moon" (the pack's row 1 painted on the arc) is gone with its frames (the Sabre swings the crescent again).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform sampler2D noise : filter_linear, repeat_enable, hint_default_black;
uniform float half_w = 1.3;
uniform float r_in = 0.35;
uniform float r_out = 0.89;
uniform float head = 1.0;
uniform float sweep_sign = 1.0;
uniform float fade = 1.0;
uniform float diss = 0.0;
uniform float trail = 1.4;
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
	float alpha = a * fade;
	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = c / max(a, 0.0001);
	ALPHA = alpha;
}
