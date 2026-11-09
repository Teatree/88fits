// The Spear's thrust (pass 136, lane MELEE; redrawn in pass 137, lane SPEAR; core/systems/MeleeFx.gd). One quad laid
// flat at the Outlaw's waist, running down local -Z from his hand (VERTEX.z 0 .. -1, VERTEX.x -1..1 across), the node
// scaled to `quad_len` x `quad_half` metres; everything below is measured in metres along (s, 0 at `s0` into the quad:
// the base the streak starts from, the quad reaching behind it for the head pulled back at his hand) and across (x).
// Layers, back to front (Garry, pass 137: "add a Spear tip among the VFX to really sell the point"; the references in
// tools/dl/p137/SPEAR/status.md):
//   a dark sheath under the streak (it reads on the pale sand and under every stage filter),
//   the streak: a comet of light widest just behind the head, breaking into striations towards the hand, a white core,
//   speed lines riding with the head on both sides (Thunder Lance: a crackle along its edges),
//   the afterimage: a flat glowing copy of the head left at the full reach as the head snaps back,
//   the spearhead: a leaf-shaped steel blade (a lit and a shaded bevel, a bright midrib, a bright lit edge), a brass
//   collar and a dark shaft stub fading behind, all outlined dark, a soft glow round it; heated by `heat`,
//   a glint: a small four-point sparkle at the point (the wind-up, the landing).
// Drawn over the sprites (no depth test, like the tip's star): the head reads through the creature it runs into.
//   pt      where the head's point is (metres along the quad); pt_a the head's strength
//   front   where the streak's front is (metres); tail 0..1 how much of it has gone from the hand; thin; fade
//   ghost_pt, ghost  the afterimage's place and strength
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled, shadows_disabled;

uniform float quad_len = 4.5;
uniform float quad_half = 0.8;
uniform float s0 = 1.2;
uniform float pt = 4.0;
uniform float pt_a = 1.0;
uniform float front = 3.6;
uniform float tail = 0.0;
uniform float thin = 0.0;
uniform float fade = 1.0;
uniform float lines = 1.0;
uniform float ghost_pt = 4.0;
uniform float ghost = 0.0;
uniform float glint = 0.0;
uniform float streak_w = 0.17;
uniform float tip_len = 0.78;
uniform float tip_w = 0.19;
uniform float heat = 0.0;
uniform float crackle = 0.0;
uniform float seed = 0.0;
uniform vec4 glow_col : source_color = vec4(0.36, 0.6, 1.0, 1.0);
uniform vec4 body_col : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);
uniform vec4 heat_col : source_color = vec4(1.0, 0.35, 0.1, 1.0);
uniform vec4 shade_col : source_color = vec4(0.06, 0.07, 0.12, 1.0);
uniform float shade_a = 0.3;

const vec3 STEEL_LIT = vec3(0.9, 0.95, 1.0);
const vec3 STEEL_MID = vec3(0.56, 0.63, 0.75);
const vec3 STEEL_DARK = vec3(0.25, 0.29, 0.4);
const vec3 BRASS = vec3(0.98, 0.74, 0.26);
const vec3 BRASS_DARK = vec3(0.62, 0.38, 0.1);
const vec3 WOOD = vec3(0.36, 0.22, 0.12);
const vec3 INK = vec3(0.07, 0.05, 0.05);

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

// the spearhead's half width at `d` metres behind its point (a leaf: a straight sharp point, widest 62% back, curving in
// to the collar); -1 off the blade
float leaf(float d) {
	if (d < 0.0 || d > tip_len) {
		return -1.0;
	}
	float pb = d / tip_len;
	if (pb < 0.62) {
		return tip_w * pow(pb / 0.62, 0.82);
	}
	return tip_w * mix(1.0, 0.36, smoothstep(0.62, 1.0, pb));
}

// a thin ray of `len` along p.x, `w` wide at its root, fading to its end
float ray(vec2 p, float len, float w) {
	float x = abs(p.x) / len;
	if (x > 1.0) {
		return 0.0;
	}
	return (1.0 - smoothstep(w * (1.0 - x) * 0.4, w * (1.0 - x), abs(p.y))) * (1.0 - x);
}

void fragment() {
	float s = v_p.y * quad_len - s0;
	float x = v_p.x * quad_half;
	float v = abs(x);
	vec3 c = vec3(0.0);
	float a = 0.0;

	// ---- the streak (behind the head; its front hidden under the blade)
	float len_s = max(front, 0.01);
	float b = front - s;
	if (b >= 0.0 && s >= 0.0) {
		float q = b / len_s;
		float cut = smoothstep(tail * len_s, tail * len_s + 0.25, s);
		float ws = streak_w * (1.0 - 0.7 * thin) * pow(clamp(1.0 - q, 0.0, 1.0), 0.55);
		// striations: rows across, each its own length back from the front (the centre ones the longest)
		float rows = 11.0;
		float rv = clamp(x / max(streak_w * 1.7, 0.001), -1.0, 1.0);
		float row = floor((rv * 0.5 + 0.5) * rows);
		float centre = abs(((row + 0.5) / rows) * 2.0 - 1.0);
		float row_len = mix(1.0, mix(0.25, 0.85, hash(row + 3.0)), smoothstep(0.1, 0.5, centre));
		float striate = 1.0 - smoothstep(row_len - 0.18, row_len, q);
		if (v < ws * 2.0 + 0.04) {
			over(c, a, shade_col.rgb, shade_a * (1.0 - smoothstep(ws * 1.2, ws * 2.0 + 0.04, v)) * (1.0 - q) * cut);
		}
		if (v < ws * 1.7) {
			over(c, a, glow_col.rgb, 0.9 * (1.0 - smoothstep(ws * 0.7, ws * 1.7, v)) * cut * mix(striate, 1.0, 0.35) * (1.0 - 0.5 * q));
		}
		if (v < ws) {
			over(c, a, body_col.rgb, 0.95 * (1.0 - smoothstep(ws * 0.45, ws, v)) * cut * striate);
			over(c, a, core_col.rgb, (1.0 - smoothstep(ws * 0.12, ws * 0.3, v)) * cut * (1.0 - smoothstep(0.75, 1.0, q)));
		}
		// the Thunder Lance: a broken zigzag of light along both edges
		if (crackle > 0.001) {
			float seg = floor(s / 0.22);
			float f = fract(s / 0.22);
			float zig = mix(hash(seg + 40.0), hash(seg + 41.0), f) * 2.0 - 1.0;
			float y = ws * 1.25 + 0.05 + zig * 0.07;
			float on = step(0.3, hash(seg + 77.0));
			float l = 1.0 - smoothstep(0.016, 0.036, abs(v - y));
			float lo = 1.0 - smoothstep(0.03, 0.06, abs(v - y));
			over(c, a, shade_col.rgb, crackle * on * lo * cut * 0.35 * (1.0 - q * 0.6));
			over(c, a, mix(core_col.rgb, glow_col.rgb, 0.7), crackle * on * l * cut * (1.0 - q * 0.6));
		}
	}
	// ---- speed lines riding with the front, thrown back behind it
	if (lines > 0.001 && s >= 0.0) {
		float rows = 8.0;
		float side = quad_half * 0.92;
		float rv = x / side;
		if (abs(rv) < 1.0) {
			float row = floor((rv * 0.5 + 0.5) * rows);
			float centre = ((row + 0.5) / rows) * 2.0 - 1.0;
			float off = abs(centre) * side;
			if (off > streak_w * 1.5) {
				float yl = abs(x - centre * side);
				float lw = 1.0 - smoothstep(0.018, 0.04, yl);
				float l0 = front - mix(0.0, 0.7, hash(row + 1.0)) - 0.1;
				float ll = mix(0.6, 1.6, hash(row + 11.0));
				float along = smoothstep(l0 - ll, l0 - ll + 0.3, s) * (1.0 - smoothstep(l0 - 0.1, l0, s));
				over(c, a, mix(glow_col.rgb, core_col.rgb, 0.35), lines * lw * along * (1.0 - abs(centre) * 0.45));
			}
		}
	}
	c *= fade;
	a *= fade;

	// ---- the afterimage: a flat glowing head left at the full reach
	if (ghost > 0.001) {
		float wg = leaf(ghost_pt - s);
		if (wg > 0.0) {
			float wgg = wg * 1.3 + 0.03;
			if (v < wgg) {
				over(c, a, mix(glow_col.rgb, core_col.rgb, 0.3), ghost * 0.6 * (1.0 - smoothstep(wg * 0.6, wgg, v)));
			}
		}
	}
	// ---- the spearhead
	if (pt_a > 0.001) {
		float d = pt - s;
		float col_len = tip_len * 0.16;
		float shaft_len = tip_len * 0.45;
		float col_w = tip_w * 0.42;
		float sh_w = tip_w * 0.24;
		float ol = 0.055;
		// a soft glow round the head
		if (d > -0.2 && d < tip_len + col_len) {
			float wl = max(leaf(clamp(d, 0.0, tip_len)), col_w);
			float r = max(v - wl, 0.0) + max(-d, 0.0);
			over(c, a, glow_col.rgb, pt_a * 0.45 * (1.0 - smoothstep(0.0, 0.14, r)) * (1.0 - smoothstep(tip_len * 0.5, tip_len + col_len, d)));
		}
		// the shaft stub (dark wood) fading behind the collar
		float ds = d - tip_len - col_len;
		if (ds > 0.0 && ds < shaft_len) {
			float fs = 1.0 - ds / shaft_len;
			if (v < sh_w + ol) {
				over(c, a, INK, pt_a * fs * 0.9);
			}
			if (v < sh_w) {
				vec3 wc = mix(WOOD, WOOD * 1.6, step(0.0, x) * (1.0 - smoothstep(0.0, sh_w, v)));
				over(c, a, wc, pt_a * fs);
			}
		}
		// the collar (brass, two dark rings)
		float dc = d - tip_len;
		if (dc > -0.01 && dc < col_len + ol) {
			if (v < col_w + ol) {
				over(c, a, INK, pt_a);
			}
			if (dc > 0.0 && dc < col_len && v < col_w) {
				vec3 bc = mix(BRASS_DARK, BRASS, smoothstep(-col_w, col_w * 0.6, x));
				float ring = step(abs(dc - col_len * 0.5), col_len * 0.12);
				bc = mix(bc, BRASS_DARK * 0.6, ring);
				over(c, a, bc, pt_a);
			}
		}
		// the blade: outline first (the leaf grown by `ol`, a cap in front of the point), then the steel
		float wo = leaf(clamp(d, 0.0, tip_len));
		if (d > -ol && d < tip_len + 0.005 && v < wo + ol * (d < 0.0 ? 1.0 + d / ol : 1.0)) {
			over(c, a, INK, pt_a);
		}
		float w = leaf(d);
		if (w > 0.0 && v < w) {
			float k = v / w;
			vec3 steel = STEEL_MID;
			// the bevels: the lit side bright, the shaded side dark, the flat between
			if (k > 0.42) {
				steel = x > 0.0 ? mix(STEEL_MID, STEEL_LIT, 0.85) : STEEL_DARK;
			}
			// the bright lit edge
			if (x > 0.0 && k > 0.82) {
				steel = vec3(1.0);
			}
			// the midrib
			float pb = d / tip_len;
			float rib = (1.0 - smoothstep(0.06, 0.13, k)) * smoothstep(0.04, 0.12, pb) * (1.0 - smoothstep(0.85, 0.98, pb));
			steel = mix(steel, vec3(1.0), rib * 0.9);
			// heat: the blade glows with the stroke's colour, white-hot at the edges
			vec3 hot = mix(heat_col.rgb, vec3(1.0, 0.95, 0.85), smoothstep(0.55, 1.0, k) * 0.7 + rib * 0.5);
			steel = mix(steel, hot, heat);
			over(c, a, steel, pt_a);
		}
		// the glint: a small four-point sparkle at the point
		if (glint > 0.001) {
			vec2 p = vec2(s - pt, x);
			float st = max(ray(p, 0.42, 0.07), ray(vec2(p.y, p.x), 0.3, 0.06));
			float dot_ = exp(-dot(p, p) * 260.0);
			over(c, a, mix(glow_col.rgb, core_col.rgb, 0.6), glint * st);
			over(c, a, core_col.rgb, glint * dot_);
		}
	}
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c / max(a, 0.0001);
	ALPHA = a;
}
