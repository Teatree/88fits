// The Sabre's swing, pass 138 (lane MELEE; core/systems/MeleeFx.gd, `params.fx_style`; Garry: "Sword is barely visible,
// should be wider and more noticeable"; the references in tools/dl/p138/MELEE/status.md). A bold crescent laid flat
// just above the sand round the Outlaw, on one quad (VERTEX.xz -1..1, the node scaled to the quad's radius, its -Z the
// arc's centre); the arc's own `melee_arc.gdshader` stays for the "classic" style.
//   style 1 "crescent": a flag-shaped band, thickest at the leading edge and tapering to a point behind it (and to both
//     ends once the swing is done), a white-hot cutting edge on the rim over a saturated colour band that darkens and
//     breaks into streaks towards the inside, a dark outline outside the rim and along the leading edge, a few sparks
//     thrown off the rim behind the edge; on the way out it erodes with noise (the inside first, the edge last).
//   style 2 "cel": the same shape hard-edged like a comic smear frame: a white body, a saturated band, a thick dark
//     outline all round, two thin echo arcs inside; on the way out it breaks into chunks.
// `head` 0..1 reveals it from the `sweep_sign` end (the hit test's own ease); `diss` 0..1 is the time past the sweep
// over the fade; `fade` the strength left. `crackle` jags the rim (the Thunder Lance), `tipped` a sharp bright point at
// the head (the Spear's Wide Sweep). Blend mix (added light washed pale on the sand, pass 62's lesson).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform int style = 1;
uniform float half_w = 1.3;
uniform float r_in = 0.35;
uniform float r_out = 0.89;
uniform float head = 1.0;
uniform float sweep_sign = 1.0;
uniform float fade = 1.0;
uniform float diss = 0.0;
uniform float trail = 1.4;
uniform float edge_w = 0.035;
uniform float smear_a = 0.35;
uniform float crackle = 0.0;
uniform float tipped = 0.0;
uniform float seed = 0.0;
uniform vec4 edge_col : source_color = vec4(0.38, 0.66, 1.0, 1.0);
uniform vec4 smear_col : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);
uniform vec4 shade_col : source_color = vec4(0.04, 0.05, 0.12, 1.0);
uniform float shade_a = 0.8;

varying vec2 v_p;

void vertex() {
	v_p = VERTEX.xz;
}

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void over(inout vec3 c, inout float a, vec3 lc, float la) {
	la = clamp(la, 0.0, 1.0);
	c = lc * la + c * (1.0 - la);
	a = la + a * (1.0 - la);
}

void fragment() {
	float r = length(v_p);
	float ang = atan(-v_p.x, -v_p.y);
	if (abs(ang) > half_w + 0.03 || r > 1.0) {
		discard;
	}
	// along the arc: 0 the end the sweep starts from, 1 the other; lengths in units of the quad's radius
	float s = clamp((ang * sweep_sign / max(half_w, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
	float arc_len = 2.0 * half_w * r_out;
	float jag = 0.0;
	if (crackle > 0.0) {
		jag = (vnoise(ang * 22.0 + seed * 7.0) - 0.5) * 0.05 * crackle;
	}
	float rim = r_out + jag;
	float dr = rim - r;
	float band = max(rim - r_in, 0.02);
	// the leading edge: the outer part leads (the blade's tip moves fastest), a slanted cut
	float lead = 0.12 * band / max(arc_len, 0.001);
	float front = head - lead * clamp(dr / band, 0.0, 1.0);
	float behind = (front - s) * arc_len;
	bool sweeping = head < 0.999;
	if (sweeping && behind < -0.035) {
		discard;
	}
	// 1 behind the leading edge, 0 past it
	float ahead = sweeping ? smoothstep(-0.003, 0.003, behind) : 1.0;
	// how lit this part is: full at the head, gone `trail` behind it
	float lit = clamp(1.0 - max(behind, 0.0) / max(trail * arc_len * 0.5, 0.001), 0.0, 1.0);
	// thickness: the flag (thick at the head, thin behind), the whole arc's ends pointed, thickest ~62% along
	float ends = pow(max(sin(3.14159 * pow(s, 1.45)), 0.0), 0.6);
	if (half_w > 3.0) {
		ends = mix(0.35, 1.0, ends);
	}
	float flag = mix(0.12, 1.0, pow(lit, 0.8));
	float thick = max(band * ends * flag, 0.004);
	float q = dr / thick;
	float ow = 0.022 + 0.012 * flag;
	vec3 c = vec3(0.0);
	float a = 0.0;
	float keep = 1.0;
	if (style == 2) {
		// ---- cel: hard bands, a thick dark outline, two echo arcs inside
		float inside = step(0.0, dr) * step(q, 1.0) * step(0.5, ahead);
		float o_rim = step(-ow * 1.4, dr) * step(dr, 0.0);
		float o_in = step(1.0, q) * step(dr, thick + ow * 1.2);
		float o_front = sweeping ? step(ahead, 0.5) * step(-0.03, behind) * step(0.0, dr) * step(dr, thick + ow) : 0.0;
		float outl = max(max(o_rim * step(0.5, ahead), o_in * step(0.5, ahead)), o_front) * step(0.03, ends * flag);
		over(c, a, shade_col.rgb, outl * 0.92);
		if (inside > 0.5) {
			vec3 col = edge_col.rgb;
			if (q < 0.4 + 0.12 * lit) {
				col = core_col.rgb;
			} else if (q > 0.8) {
				col = edge_col.rgb * 0.6;
			}
			over(c, a, col, 1.0);
		}
		// echo arcs: thin, inside, shorter behind
		for (int k = 0; k < 2; k++) {
			float fk = float(k);
			float re = rim - thick - (0.05 + 0.055 * fk) * band * (0.6 + ends);
			float le = step(0.06, ends * flag) * step(behind, 0.55 * arc_len * (1.0 - 0.35 * fk)) * step(0.5, ahead);
			float lw = 0.011 * (1.0 - 0.3 * fk) * (0.5 + flag);
			float dd = abs(r - re);
			over(c, a, shade_col.rgb, 0.85 * le * step(dd, lw + 0.014));
			over(c, a, mix(edge_col.rgb, core_col.rgb, 0.3), le * step(dd, lw));
		}
		if (diss > 0.0) {
			float n = vnoise2(vec2(s * arc_len * 2.5, r * 16.0));
			keep = step(diss * 1.25 - (1.0 - clamp(q, 0.0, 1.0)) * 0.3, n);
		}
	} else {
		// ---- crescent
		float erode = 0.0;
		if (diss > 0.0) {
			// the way out: noise eats the inside first, the edge last, the tail before the head
			// streaks along the arc (long along it, fine across): it comes apart along its own motion
			float n = vnoise2(vec2(s * arc_len * 3.0, r * 38.0));
			erode = smoothstep(n - 0.06, n + 0.06, diss * 1.35 - (1.0 - clamp(q, 0.0, 1.0)) * 0.45 - lit * 0.15);
		}
		if (dr < 0.0) {
			// the dark outline outside the rim, a thin glow past it
			float sh = 1.0 - smoothstep(ow * 0.6, ow * 1.5, -dr);
			over(c, a, shade_col.rgb, shade_a * sh * smoothstep(0.0, 0.25, ends * flag) * ahead);
			float gl = 1.0 - smoothstep(0.0, ow * 0.5, -dr);
			over(c, a, edge_col.rgb, 0.5 * gl * lit * ends * ahead);
		} else if (q <= 1.3) {
			// the inner edge breaks into streaks running along the arc
			float streak = vnoise(r * 46.0 + seed) * 0.6 + vnoise(r * 13.0 - seed) * 0.4;
			float inner_cut = 1.0 - smoothstep(0.6, 1.0, q + (streak - 0.5) * 0.6);
			vec3 deep = edge_col.rgb * 0.5;
			vec3 col = mix(edge_col.rgb, deep, smoothstep(0.25, 0.95, q));
			over(c, a, col, inner_cut * mix(0.7, 1.0, lit) * mix(0.8, 1.0, smear_a) * ahead);
			// the halo just inside the edge
			float halo = 1.0 - smoothstep(0.05, 0.22, q);
			over(c, a, mix(smear_col.rgb, core_col.rgb, 0.3), halo * 0.75 * mix(0.6, 1.0, lit) * ahead);
			// the white-hot cutting edge on the rim, wider at the head
			float cw = (edge_w * 0.6 + 0.02) * mix(0.55, 1.0, lit) * (1.0 - 0.7 * diss);
			float core = 1.0 - smoothstep(cw * 0.55, cw, dr);
			over(c, a, core_col.rgb, core * smoothstep(0.0, 0.18, ends * flag) * ahead);
			// the leading edge's own dark line, just past it
			if (sweeping) {
				float lf = (1.0 - smoothstep(0.012, 0.03, -behind)) * (1.0 - ahead) * step(q, 1.0);
				over(c, a, shade_col.rgb, 0.75 * lf);
			}
		}
		// sparks thrown off the rim behind the edge: short dashes along the arc, out from the rim as they age
		if (head > 0.02 && dr < 0.02) {
			float N = 26.0;
			float cell = floor(s * N);
			float sc = (cell + 0.2 + 0.6 * hash(cell)) / N;
			float age = (head - sc) * arc_len;
			if (hash(cell + 31.0) > 0.45 && age > 0.0 && age < 0.9) {
				float rr = rim + 0.025 + age * mix(0.05, 0.14, hash(cell + 7.0));
				float ds = abs(s - sc) * arc_len;
				float dash = (1.0 - smoothstep(0.004, 0.009, abs(r - rr))) * (1.0 - smoothstep(0.02, 0.045, ds));
				over(c, a, mix(core_col.rgb, edge_col.rgb, 0.3), dash * (1.0 - age / 0.9) * (1.0 - diss));
			}
		}
		keep = 1.0 - erode;
	}
	// the head: a sharp bright point where the edge is now (the Spear's tipped sweep), a little glint else
	if (sweeping) {
		float hd = (head - s) * arc_len;
		float near = exp(-hd * hd / 0.0012) * (1.0 - smoothstep(0.0, band * 0.5, abs(dr)));
		over(c, a, core_col.rgb, near * mix(0.4, 1.0, tipped));
	}
	if (crackle > 0.0) {
		float spk = step(0.82, vnoise(ang * 60.0 + seed * 13.0)) * (1.0 - smoothstep(0.0, 0.03, abs(dr)));
		over(c, a, core_col.rgb, spk * lit * crackle);
	}
	float alpha = a * keep * fade;
	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = c / max(a, 0.0001);
	ALPHA = alpha;
}
