// The Spear's thrust, pass 138 (lane MELEE; core/systems/MeleeFx.gd, `params.fx_style`; Garry: "Spear tip looks
// childish ... Look for actually good looking VFX effects that show the Spear Thrusts"; the references in
// tools/dl/p138/MELEE/status.md). No spearhead: a thrust of light. One quad laid flat at the Outlaw's waist, running
// down local -Z from his hand (VERTEX.z 0 .. -1, VERTEX.x -1..1 across), the node scaled to `quad_len` x `quad_half`
// metres; measured in metres along (s, 0 at `s0` into the quad: his hand) and across (x). pass 137's spearhead shader
// (melee_thrust.gdshader) stays for the "spearhead" style.
//   style 1 "lance": a long narrow spindle of light from the hand to a needle-bright point (widest a little behind the
//     point, thinning to the hand), a white core over a saturated band in a dark sheath, striated as it fades from the
//     hand; air rings (bows across the lane) left behind as it darts; speed lines both sides; on a hit the light runs
//     on through the point (`pierce`).
//   style 2 "wind": a thin white needle with two wind ribbons twisting round it, widening to the front, an energy
//     diamond at the point; the same rings, lines and pierce.
//   pt      where the point is (metres); pt_a its strength; front -1 while only the gathering glint shows
//   tail    0..1 how much has gone from the hand; thin; fade; lines; glint; ring_t seconds since the dart began
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled, shadows_disabled;

uniform int style = 1;
uniform float quad_len = 4.5;
uniform float quad_half = 0.8;
uniform float s0 = 0.3;
uniform float pt = 3.0;
uniform float pt_a = 1.0;
uniform float front = 3.0;
uniform float full = 3.0;
uniform float tail = 0.0;
uniform float thin = 0.0;
uniform float fade = 1.0;
uniform float lines = 1.0;
uniform float glint = 0.0;
uniform float ring_t = -1.0;
uniform float pierce = 0.0;
uniform float lance_w = 0.2;
uniform float needle = 0.5;
uniform float heat = 0.0;
uniform float crackle = 0.0;
uniform float seed = 0.0;
uniform vec4 glow_col : source_color = vec4(0.36, 0.6, 1.0, 1.0);
uniform vec4 body_col : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);
uniform vec4 heat_col : source_color = vec4(1.0, 0.35, 0.1, 1.0);
uniform vec4 shade_col : source_color = vec4(0.04, 0.05, 0.12, 1.0);
uniform float shade_a = 0.7;

varying vec2 v_p;

void vertex() {
	v_p = vec2(VERTEX.x, -VERTEX.z);
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

// the lance's half width `d` metres behind the point: a needle to the shoulder, widest a little behind, thinning to the
// hand
float profile(float d, float len) {
	if (d < 0.0) {
		return 0.0;
	}
	float nd = max(needle, 0.05);
	if (d < nd) {
		return lance_w * 0.5 * pow(d / nd, 0.85);
	}
	if (d < nd * 1.9) {
		return lance_w * mix(0.5, 1.0, smoothstep(nd, nd * 1.9, d));
	}
	return lance_w * mix(1.0, 0.22, smoothstep(nd * 1.9, max(len, nd * 2.0), d));
}

void fragment() {
	float s = v_p.y * quad_len - s0;
	float x = v_p.x * quad_half;
	float v = abs(x);
	vec3 c = vec3(0.0);
	float a = 0.0;
	vec3 glow = mix(glow_col.rgb, heat_col.rgb, heat);
	vec3 body = mix(body_col.rgb, mix(heat_col.rgb, vec3(1.0, 0.9, 0.75), 0.5), heat);
	bool shown = front >= 0.0;
	float len = max(pt, 0.05);
	float d = pt - s;
	// the light starts a little out from his hand (it drew over him) and goes from the hand as `tail` grows
	float cut = smoothstep(tail * len + 0.12, tail * len + 0.5, s) * step(0.0, s);

	// ---- air rings: bows across the lane left behind as the point darts past, widening and fading
	if (shown && ring_t >= 0.0) {
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			float p = 0.28 + 0.24 * fk;
			if (style == 1 && k == 2) {
				break;
			}
			float born = 0.012 + 0.014 * fk;
			float age = (ring_t - born) / 0.2;
			if (age > 0.0 && age < 1.0) {
				float sk = full * p;
				float hs = mix(0.12, lance_w * 3.0 + 0.16, 1.0 - pow(1.0 - age, 2.0));
				if (v < hs) {
					float bow = sk + hs * 0.45 * (1.0 - (x / hs) * (x / hs));
					float dl = abs(s - bow);
					float lw = mix(0.045, 0.016, age);
					float edge_fade = 1.0 - smoothstep(0.7, 1.0, v / hs);
					over(c, a, shade_col.rgb, 0.6 * (1.0 - age) * edge_fade * (1.0 - smoothstep(lw, lw + 0.03, dl)));
					over(c, a, mix(glow, core_col.rgb, 0.45), (1.0 - age) * edge_fade * (1.0 - smoothstep(lw * 0.5, lw, dl)));
				}
			}
		}
	}

	// ---- speed lines riding with the front, thrown back behind it
	if (shown && lines > 0.001 && s >= 0.0) {
		float rows = 9.0;
		float side = quad_half * 0.9;
		float rv = x / side;
		if (abs(rv) < 1.0) {
			float row = floor((rv * 0.5 + 0.5) * rows);
			float centre = ((row + 0.5) / rows) * 2.0 - 1.0;
			float off = abs(centre) * side;
			if (off > lance_w * 1.4) {
				float yl = abs(x - centre * side);
				float lw = 1.0 - smoothstep(0.016, 0.034, yl);
				float l0 = front - mix(0.1, 0.9, hash(row + 1.0));
				float ll = mix(0.5, 1.5, hash(row + 11.0));
				float along = smoothstep(l0 - ll, l0 - ll + 0.3, s) * (1.0 - smoothstep(l0 - 0.1, l0, s));
				over(c, a, mix(glow, core_col.rgb, 0.4), lines * lw * along * (1.0 - abs(centre) * 0.5) * step(0.3, hash(row + 5.0)));
			}
		}
	}

	if (shown && pt_a > 0.001) {
		float w = profile(d, len) * (1.0 - 0.65 * thin);
		if (style == 2) {
			// ---- wind: a needle with two ribbons twisting round it, an energy diamond at the point
			float amp = w * 1.35;
			float ph = s * 7.5 - ring_t * 40.0 + seed;
			float in_len = step(0.0, d) * cut;
			// the dark sheath round the whole twist
			if (v < amp + 0.05 && d > 0.0) {
				over(c, a, shade_col.rgb, shade_a * 0.55 * (1.0 - smoothstep(amp * 0.7, amp + 0.05, v)) * in_len * smoothstep(0.0, 0.4, d));
			}
			for (int k = 0; k < 2; k++) {
				float yk = amp * sin(ph + float(k) * 3.14159);
				float depth = cos(ph + float(k) * 3.14159);
				float lw = mix(0.018, 0.045, depth * 0.5 + 0.5) * smoothstep(0.0, 0.6, d / max(len, 0.1) + 0.1);
				float dl = abs(x - yk);
				over(c, a, shade_col.rgb, 0.8 * in_len * (1.0 - smoothstep(lw, lw + 0.028, dl)) * step(0.15, d));
				vec3 rc = mix(glow * 0.8, mix(body, core_col.rgb, 0.4), depth * 0.5 + 0.5);
				over(c, a, rc, in_len * (1.0 - smoothstep(lw * 0.6, lw, dl)) * step(0.15, d));
			}
			// the needle
			float nw = 0.022 + 0.02 * smoothstep(len, 0.0, d);
			over(c, a, glow, in_len * (1.0 - smoothstep(nw, nw * 2.4, v)) * 0.9);
			over(c, a, core_col.rgb, in_len * (1.0 - smoothstep(nw * 0.5, nw, v)));
			// the energy diamond at the point
			float dd = abs(d - 0.2) / 0.32 + v / max(lance_w * 0.62, 0.05);
			if (dd < 1.25) {
				over(c, a, shade_col.rgb, pt_a * (1.0 - smoothstep(1.08, 1.25, dd)));
				over(c, a, glow, pt_a * (1.0 - smoothstep(0.95, 1.05, dd)));
				over(c, a, core_col.rgb, pt_a * (1.0 - smoothstep(0.45, 0.62, dd)));
			}
		} else {
			// ---- lance: the sheath, the band, the body, the white core
			float ink_w = w + 0.045;
			if (v < ink_w && d > -0.04) {
				float ink_l = smoothstep(-0.04, 0.0, d) * cut;
				over(c, a, shade_col.rgb, shade_a * ink_l * (1.0 - smoothstep(w + 0.02, ink_w, v)) * mix(0.55, 1.0, smoothstep(len, len * 0.4, d)));
			}
			if (v < w && d >= 0.0) {
				float q = d / len;
				// striations as the hand's end goes: rows across, each its own length back from the point
				float rows = 9.0;
				float rv = clamp(x / max(w, 0.001), -1.0, 1.0);
				float row = floor((rv * 0.5 + 0.5) * rows);
				float centre = abs(((row + 0.5) / rows) * 2.0 - 1.0);
				float row_len = mix(1.0, mix(0.35, 0.9, hash(row + 3.0)), smoothstep(0.15, 0.6, centre));
				float striate = mix(1.0, 1.0 - smoothstep(row_len - 0.15, row_len, q), clamp(thin * 1.5 + 0.25, 0.0, 1.0));
				float k = v / w;
				over(c, a, glow, cut * (1.0 - smoothstep(0.75, 1.0, k)) * mix(striate, 1.0, 0.3));
				over(c, a, body, cut * (1.0 - smoothstep(0.38, 0.62, k)) * striate);
				// the core: white, wider and hotter towards the point
				float cw = mix(0.16, 0.3, smoothstep(len, 0.0, d));
				over(c, a, core_col.rgb, cut * (1.0 - smoothstep(cw * 0.6, cw, k)) * mix(0.75, 1.0, smoothstep(len * 0.7, 0.0, d)));
			}
			// the Thunder Lance: a broken zigzag of light along both edges
			if (crackle > 0.001 && d > 0.0 && s > 0.0) {
				float seg = floor(s / 0.22);
				float f = fract(s / 0.22);
				float zig = mix(hash(seg + 40.0), hash(seg + 41.0), f) * 2.0 - 1.0;
				float y = w * 1.3 + 0.06 + zig * 0.07;
				float on = step(0.3, hash(seg + 77.0));
				float l = 1.0 - smoothstep(0.014, 0.032, abs(v - y));
				float lo = 1.0 - smoothstep(0.03, 0.06, abs(v - y));
				over(c, a, shade_col.rgb, crackle * on * lo * cut * 0.4);
				over(c, a, mix(core_col.rgb, glow, 0.6), crackle * on * l * cut);
			}
		}
		// ---- the pierce: on a hit the light runs on through the point, thin and white
		if (pierce > 0.001 && d < 0.0) {
			float run = -d / (0.25 + 0.75 * pierce);
			if (run < 1.0) {
				float pw = 0.03 * (1.0 - run) + 0.006;
				over(c, a, glow, pierce * (1.0 - run) * (1.0 - smoothstep(pw, pw * 2.6, v)));
				over(c, a, core_col.rgb, pierce * (1.0 - run) * (1.0 - smoothstep(pw * 0.4, pw, v)));
			}
		}
	}
	float al = a * fade;
	// ---- the glint: a small four-point sparkle at the point (the gathering, the landing)
	if (glint > 0.001) {
		vec2 p = vec2(s - pt, x);
		float st = max(ray(p, 0.5, 0.08), ray(vec2(p.y, p.x), 0.32, 0.07));
		float dot_ = exp(-dot(p, p) * 220.0);
		vec3 gc = (c / max(a, 0.0001)) * al;
		float ga = al;
		over(gc, ga, mix(glow, core_col.rgb, 0.6), glint * st);
		over(gc, ga, core_col.rgb, glint * dot_);
		if (ga < 0.004) {
			discard;
		}
		ALBEDO = gc / max(ga, 0.0001);
		ALPHA = ga;
	} else {
		if (al < 0.004) {
			discard;
		}
		ALBEDO = c / max(a, 0.0001);
		ALPHA = al;
	}
}
