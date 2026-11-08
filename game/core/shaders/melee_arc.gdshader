// The Sabre's swing (pass 136, lane MELEE; core/systems/MeleeFx.gd): a crescent slash laid flat just above the sand
// round the Outlaw, drawn on one quad (VERTEX.xz -1..1, the node scaled to the quad's radius, its -Z the arc's centre).
// A bright edge rides the outer rim with a soft smear (`smear_a`, about 35%) behind it towards the inner rim; the
// crescent is revealed from one end to the other as `head` runs 0..1 (the hit test's own ease), thickest where the edge
// is now and tapering behind it, then the whole of it fades with `fade`. `crackle` jags the edge (the Thunder Lance),
// `tipped` gives the head a sharp bright point (the Spear's Wide Sweep). Blend mix, not added light: added light washed
// pale on the bright sand (pass 62's lesson), so the colours are saturated and only the core is white.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform float half_w = 1.3;
uniform float r_in = 0.35;
uniform float r_out = 0.87;
uniform float head = 1.0;
uniform float sweep_sign = 1.0;
uniform float fade = 1.0;
uniform float trail = 1.4;
uniform float edge_w = 0.035;
uniform float smear_a = 0.35;
uniform float crackle = 0.0;
uniform float tipped = 0.0;
uniform float seed = 0.0;
uniform vec4 edge_col : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform vec4 smear_col : source_color = vec4(0.55, 0.7, 0.95, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);
uniform vec4 shade_col : source_color = vec4(0.05, 0.08, 0.16, 1.0);
uniform float shade_a = 0.28;

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

// one layer over what lies under it (premultiplied)
void over(inout vec3 c, inout float a, vec3 lc, float la) {
	la = clamp(la, 0.0, 1.0);
	c = lc * la + c * (1.0 - la);
	a = la + a * (1.0 - la);
}

void fragment() {
	float r = length(v_p);
	// the edge angle off the centre: the Thruster's yaw sense (a point at angle a lies at (-sin a, -cos a))
	float ang = atan(-v_p.x, -v_p.y);
	if (abs(ang) > half_w + 0.02 || r > 1.0) {
		discard;
	}
	// where along the arc this is, 0 the end the sweep starts from, 1 the other
	float s = clamp((ang * sweep_sign / max(half_w, 0.001)) * 0.5 + 0.5, 0.0, 1.0);
	if (s > head + 0.002) {
		discard;
	}
	// how lit this part is: full at the head, gone `trail` behind it
	float lit = clamp(1.0 - (head - s) / max(trail, 0.001), 0.0, 1.0);
	// the crescent: thin at both ends of the arc, thickest in the middle (a full ring keeps a thin seam at its start)
	float taper = pow(sin(3.14159 * s), 0.9);
	float body = taper * mix(0.25, 1.0, lit);
	float jag = 0.0;
	if (crackle > 0.0) {
		jag = (vnoise(ang * 22.0 + seed * 7.0) - 0.5) * edge_w * 2.4 * crackle;
	}
	float rim = r_out + jag;
	float inner = mix(rim, r_in, body);
	vec3 c = vec3(0.0);
	float a = 0.0;
	// a faint dark line just outside the edge, so the slash reads on the pale sand
	float d_out = r - rim;
	float ew = edge_w * mix(0.45, 1.0, body);
	if (d_out > 0.0) {
		float sh = 1.0 - smoothstep(0.0, ew * 1.6, d_out);
		over(c, a, shade_col.rgb, shade_a * sh * lit * taper);
		// and a thin glow past the edge
		float gl = 1.0 - smoothstep(0.0, ew * 0.9, d_out);
		over(c, a, edge_col.rgb, 0.55 * gl * lit * taper);
	} else if (r >= inner) {
		float t = clamp((r - inner) / max(rim - inner, 0.001), 0.0, 1.0);
		// the smear: soft, brighter towards the edge
		over(c, a, smear_col.rgb, smear_a * pow(t, 0.8) * mix(0.35, 1.0, lit));
		// the edge: a bright band on the rim with a white core
		float de = rim - r;
		float e = 1.0 - smoothstep(ew * 0.65, ew, de);
		over(c, a, edge_col.rgb, e * mix(0.75, 1.0, lit) * taper);
		float core = 1.0 - smoothstep(ew * 0.12, ew * 0.4, de);
		over(c, a, core_col.rgb, core * mix(0.5, 1.0, lit) * taper);
	} else {
		discard;
	}
	// the head: a sharp bright point where the edge is now (the Spear's tipped sweep), a little glint for the rest
	float hd = (head - s) * half_w * r_out;
	if (head < 0.999) {
		float near = exp(-hd * hd / 0.0016) * smoothstep(r_in, rim, r);
		over(c, a, core_col.rgb, near * mix(0.45, 1.0, tipped));
	}
	if (crackle > 0.0) {
		// sparks of white along a crackling edge
		float spk = step(0.82, vnoise(ang * 60.0 + seed * 13.0)) * (1.0 - smoothstep(0.0, ew * 1.4, abs(r - rim)));
		over(c, a, core_col.rgb, spk * lit * crackle);
	}
	float a_pm = a;
	// the head is the blade's line now: a soft edge, not a cut
	a *= 1.0 - smoothstep(head - 0.025, head + 0.002, s) * step(head, 0.999);
	a *= fade;
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c / max(a_pm, 0.0001);
	ALPHA = a;
}
