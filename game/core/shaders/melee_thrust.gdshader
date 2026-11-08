// The Spear's thrust (pass 136, lane MELEE; core/systems/MeleeFx.gd): a fighting-game stab streak laid flat at the
// Outlaw's waist, on one quad running down local -Z (VERTEX.z 0 at the base .. -1 at the tip, VERTEX.x -1..1 across; the
// node scaled to the streak's length and its quad's half width). A tapered lance of light (thin at his hand, widest
// short of the point, a sharp point), a white-hot core, a coloured glow, speed lines raking forward on both sides while
// it shoots out, and a wider afterimage that lingers as the lance itself thins away from the base to the point.
//   head   0..1 how far out the point is (of the full length)
//   tail   0..1 how much of the base has gone (the fade eats it from the hand to the point)
//   thin   0..1 how much the body has thinned (the fade)
//   ghost  the afterimage's strength, spread its widening
//   lines  the speed lines' strength
//   body_w the lane's half width over the quad's (the lance's widest)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform float head = 1.0;
uniform float tail = 0.0;
uniform float thin = 0.0;
uniform float fade = 1.0;
uniform float ghost = 0.0;
uniform float spread = 0.0;
uniform float lines = 1.0;
uniform float body_w = 0.34;
uniform float seed = 0.0;
uniform vec4 glow_col : source_color = vec4(0.45, 0.68, 1.0, 1.0);
uniform vec4 body_col : source_color = vec4(0.8, 0.92, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);
uniform vec4 shade_col : source_color = vec4(0.05, 0.08, 0.16, 1.0);
uniform float shade_a = 0.25;

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

// the lance's half width at u (0 the base .. 1 the point) of a lance `w` wide at its widest
float lance(float u, float w) {
	if (u < 0.0 || u > 1.0) {
		return -1.0;
	}
	float body = mix(0.3, 1.0, smoothstep(0.0, 0.72, u));
	float point = clamp((1.0 - u) / 0.32, 0.0, 1.0);
	return w * body * pow(point, 0.85);
}

void fragment() {
	float u = v_p.y;
	float v = abs(v_p.x);
	if (u > head + 0.002) {
		discard;
	}
	vec3 c = vec3(0.0);
	float a = 0.0;
	// along the streak as it stands now (its point at `head`)
	float un = u / max(head, 0.001);
	// the fade eats it from the base: a soft cut at `tail`
	float cut = smoothstep(tail * head, tail * head + 0.12, u);
	// brighter towards the point
	float lift = mix(0.55, 1.0, un);
	// speed lines: thin rakes on both sides of the lance, each its own length and place, sliding forward
	if (lines > 0.001) {
		float rows = 9.0;
		float rv = v_p.x / (body_w * 2.9);
		if (abs(rv) < 1.0) {
			float row = floor((rv * 0.5 + 0.5) * rows);
			float centre = ((row + 0.5) / rows) * 2.0 - 1.0;
			float h1 = hash(row + 1.0);
			float h2 = hash(row + 11.0);
			// the middle rows are the lance itself: the lines rake outside it
			float off = abs(centre);
			if (off > 0.22) {
				float y_line = abs(rv - centre) * rows;
				float lw = 1.0 - smoothstep(0.08, 0.2, y_line);
				float len = mix(0.25, 0.6, h1);
				float start = mix(0.0, 0.5, h2);
				float end = min(start + len, head);
				float along = smoothstep(start, start + 0.05, u) * (1.0 - smoothstep(end - 0.12, end, u));
				over(c, a, mix(glow_col.rgb, core_col.rgb, 0.55), lines * lw * along * (1.0 - off * 0.6) * 0.85);
			}
		}
	}
	// the afterimage: a wider, fainter lance that lingers
	if (ghost > 0.001) {
		float gw = lance(un, body_w * (1.35 + spread));
		if (gw > 0.0 && v < gw) {
			float k = 1.0 - v / gw;
			over(c, a, glow_col.rgb, ghost * 0.3 * k * k * lift);
		}
	}
	float w = lance(un, body_w * (1.0 - 0.75 * thin));
	if (w > 0.0) {
		// a faint dark sheath, so it reads on the pale sand
		float sw = w * 1.45 + 0.02;
		if (v < sw) {
			over(c, a, shade_col.rgb, shade_a * (1.0 - smoothstep(w, sw, v)) * cut * (1.0 - thin));
		}
		float gw2 = w * 1.25;
		if (v < gw2) {
			over(c, a, glow_col.rgb, 0.85 * (1.0 - smoothstep(w * 0.85, gw2, v)) * cut * lift);
		}
		if (v < w) {
			over(c, a, body_col.rgb, 0.92 * (1.0 - smoothstep(w * 0.6, w * 0.85, v)) * cut * lift);
			over(c, a, core_col.rgb, (1.0 - smoothstep(w * 0.14, w * 0.3, v)) * cut);
		}
	}
	float a_pm = a;
	a *= fade;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c / max(a_pm, 0.0001);
	ALPHA = a;
}
