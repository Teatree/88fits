// The bullet-heaven attacks' shots (pass 113, lane BOSS; BossAttackFx's billboard looks, one MultiMesh an attack): a
// painting that faces the camera, drawn here in code with a thick ink outline so it reads on the sand and under every
// stage filter (it writes stencil 3, the never-tinted class: StageStencil.CLEAR), with its trail behind it along its
// flight. Garry's spec (docs/concepts/boss_bullet_heaven.md): "Big and bright, with a thick ink outline".
//   look 0 burning_tumbleweed: a tan ball of twigs that rolls, a flame licking off its back, embers trailing
//   look 1 venom_blob:         a wobbling purple jelly with a gloss and bubbles, drips trailing
//   look 2 brand_fireball:     a white-hot core in an orange ball branded with a horseshoe, flames and see-through smoke trailing
// Instance: the transform's origin = (x, metres over the ground, z) and its x column's length the body's radius (m);
// INSTANCE_CUSTOM = (flight x, flight z, seed, scale 0..1: the pop out of the boss and the burn-out). The ground under it
// comes from the map's height grid, read as Telegraphs' marks read it (heights, grid_n, half_size, resolution); grid_n 0
// = the origin's y as it is. Opaque (discard outside the shape), so the depth keeps a dune from drawing over it badly:
// it is pulled `toward_cam` metres towards the eye as well.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 3;

uniform int look = 0;
uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform vec4 ink : source_color = vec4(0.09, 0.05, 0.04, 1.0);
uniform float glow = 1.0;
uniform float wobble = 0.0;
uniform float trail = 1.0;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform float toward_cam = 0.5;

// the quad's half size in body radii: room for the trail behind the body
const float QUAD = 2.7;
// the ink outline's width in body radii
const float OUT = 0.21;

varying vec2 v_q;
varying vec2 v_dir;
varying float v_seed;

float ground(vec2 p) {
	if (grid_n < 2) {
		return 0.0;
	}
	float top = float(grid_n - 1) - 0.001;
	float fx = clamp((p.x + half_size) * resolution, 0.0, top);
	float fz = clamp((p.y + half_size) * resolution, 0.0, top);
	int ix = int(fx);
	int iz = int(fz);
	float tx = fx - float(ix);
	float tz = fz - float(iz);
	float h00 = texelFetch(heights, ivec2(ix, iz), 0).r;
	float h10 = texelFetch(heights, ivec2(ix + 1, iz), 0).r;
	float h01 = texelFetch(heights, ivec2(ix, iz + 1), 0).r;
	float h11 = texelFetch(heights, ivec2(ix + 1, iz + 1), 0).r;
	return mix(mix(h00, h10, tx), mix(h01, h11, tx), tz);
}

void vertex() {
	// a QuadMesh 2 x 2: corners at -1..1
	v_q = VERTEX.xy;
	vec3 c = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec4 k = INSTANCE_CUSTOM;
	v_seed = k.z;
	float g = grid_n >= 2 ? ground(c.xz) : 0.0;
	vec4 vc = VIEW_MATRIX * vec4(c.x, g + c.y, c.z, 1.0);
	vec2 d = (VIEW_MATRIX * vec4(k.x, 0.0, k.y, 0.0)).xy;
	v_dir = dot(d, d) > 0.000001 ? normalize(d) : vec2(1.0, 0.0);
	vc.xyz += normalize(-vc.xyz) * toward_cam;
	float hs = s * QUAD * clamp(k.w, 0.0, 1.0);
	VERTEX = vc.xyz + vec3(v_q.x * hs, v_q.y * hs, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

// A teardrop off the back of the body: round at the front (radius w), narrowing to a point `len` behind (fb.x < 0 is
// behind). Negative inside, in body radii (near enough a distance for the outline).
float tear(vec2 fb, float len, float w) {
	if (fb.x >= 0.0) {
		return length(fb) - w;
	}
	if (fb.x < -len) {
		return 10.0;
	}
	float hw = w * pow(max(1.0 + fb.x / max(len, 0.001), 0.0), 0.75);
	return abs(fb.y) - hw;
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void fragment() {
	vec2 b = v_q * QUAD;
	vec2 side = vec2(-v_dir.y, v_dir.x);
	// along the flight (x: + ahead) and across it (y), in body radii
	vec2 fb = vec2(dot(b, v_dir), dot(b, side));
	float sd = v_seed;
	float ang = atan(b.y, b.x);
	vec3 col = vec3(0.0);
	bool hit = false;
	if (look == 1) {
		// ---- the venom blob: a jelly that wobbles and stretches along its flight
		float wb = 0.5 + wobble;
		float st = 1.0 + 0.11 * wb * sin(TIME * 7.0 + sd * 3.1);
		vec2 bs = vec2(fb.x / st, fb.y * st);
		float r_edge = 1.0 + wb * (0.08 * sin(ang * 3.0 + TIME * 6.0 + sd) + 0.05 * sin(ang * 5.0 - TIME * 4.3 + sd * 2.0));
		float d_body = length(bs) - r_edge;
		// drips trailing
		float d_drip = 10.0;
		if (trail > 0.0) {
			float wig = 0.08 * sin(TIME * 8.0 + sd);
			d_drip = min(length(fb - vec2(-1.55, wig)) - 0.34, length(fb - vec2(-2.2, -wig)) - 0.21);
		}
		float d = min(d_body, d_drip);
		if (d < 0.0) {
			hit = true;
			if (d > -OUT || (d_body >= 0.0 && d_drip > -OUT)) {
				col = ink.rgb;
			} else if (d_body < 0.0) {
				float l = length(bs) / r_edge;
				vec3 core = min(tint.rgb * 1.25 + vec3(0.18, 0.08, 0.2), vec3(1.0));
				vec3 rim = tint.rgb * 0.5;
				col = mix(core, rim, smoothstep(0.15, 1.0, l));
				// bubbles
				if (length(b - vec2(0.32, -0.22)) < 0.15 || length(b - vec2(-0.12, -0.48)) < 0.1) {
					col = mix(col, vec3(1.0), 0.35);
				}
				// the gloss, up and to the left on the screen
				if (length((b - vec2(-0.36, 0.4)) * vec2(1.0, 1.65)) < 0.27 || length(b - vec2(0.06, 0.62)) < 0.09) {
					col = vec3(0.98, 0.94, 1.0);
				}
			} else {
				col = tint.rgb * 0.75;
			}
		}
	} else if (look == 2) {
		// ---- the branded fireball: a hot core, flames off its back, smoke puffs behind them
		float r_edge = 1.0 + 0.045 * sin(ang * 9.0 + TIME * 11.0 + sd * 4.0);
		float d_body = length(b) - r_edge;
		float d_fl = 10.0;
		float d_smoke = 10.0;
		float fl_len = 1.25 + 0.25 * sin(TIME * 14.0 + sd * 5.0);
		if (trail > 0.0) {
			vec2 ff = vec2(fb.x + 0.2, fb.y + 0.12 * sin(TIME * 17.0 + fb.x * 4.0 + sd));
			d_fl = tear(ff, fl_len, 1.02);
			float drift = mod(TIME * 1.4 + sd * 0.37, 0.4);
			d_smoke = min(length(fb - vec2(-1.75 - drift, 0.1 * sin(TIME * 3.0 + sd))) - (0.3 + drift * 0.2),
				length(fb - vec2(-2.2 - drift, -0.12 * sin(TIME * 2.6 + sd))) - (0.2 + drift * 0.2));
		}
		float d = min(min(d_body, d_fl), d_smoke);
		if (d < 0.0) {
			hit = true;
			if (d_body < 0.0) {
				if (d_body > -OUT) {
					col = ink.rgb;
				} else {
					float l = length(b);
					vec3 hot = vec3(1.0, 0.98, 0.86);
					vec3 yel = vec3(1.0, 0.84, 0.28);
					col = mix(hot, yel, smoothstep(0.2, 0.5, l));
					col = mix(col, tint.rgb, smoothstep(0.5, 0.78, l));
					col = mix(col, tint.rgb * 0.62, smoothstep(0.7, 0.8, l));
					// the brand: a horseshoe burnt into it (an open ring, its gap down), rocking a little
					vec2 br = rot(b, 0.35 * sin(TIME * 2.0 + sd));
					float ring = abs(length(br) - 0.42);
					float ha = atan(br.x, -br.y);
					if (ring < 0.07 && abs(ha) > 0.62) {
						col = vec3(0.62, 0.2, 0.05);
					}
				}
			} else if (d_fl < 0.0) {
				if (d_fl > -OUT * 0.8) {
					col = ink.rgb;
				} else {
					float u = clamp(-fb.x / fl_len, 0.0, 1.0);
					col = mix(vec3(1.0, 0.9, 0.35), tint.rgb, smoothstep(0.0, 0.55, u + abs(fb.y) * 0.35));
					col = mix(col, vec3(0.75, 0.1, 0.03), smoothstep(0.55, 1.0, u));
				}
			} else {
				// smoke: see-through (every other pixel), no ink, so it never reads as a shot
				if (mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) < 1.0) {
					discard;
				}
				col = vec3(0.42, 0.38, 0.37);
			}
		}
	} else {
		// ---- the burning tumbleweed: a rolling ball of twigs, a flame off its back, embers behind
		float r_edge = 1.0 + 0.07 * sin(ang * 7.0 + sd * 3.0) + 0.04 * sin(ang * 13.0 + sd);
		float d_body = length(b) - r_edge;
		float d_fl = 10.0;
		float fl_len = 1.45 + 0.3 * sin(TIME * 13.0 + sd * 5.0) + 0.15 * sin(TIME * 23.0 + sd);
		if (trail > 0.0) {
			vec2 ff = vec2(fb.x + 0.1, fb.y + 0.14 * sin(TIME * 9.0 + fb.x * 3.0 + sd));
			d_fl = tear(ff, fl_len, 1.12);
		}
		float d = min(d_body, d_fl);
		if (d < 0.0) {
			hit = true;
			if (d_body < 0.0) {
				if (d_body > -OUT) {
					col = ink.rgb;
				} else {
					// the twigs: tan with dark brown strands, rolling the way it flies
					float roll = TIME * 5.0 * (v_dir.x >= 0.0 ? -1.0 : 1.0) + sd;
					vec2 rb = rot(b, roll);
					vec3 tan_c = vec3(0.84, 0.66, 0.38);
					vec3 twig = vec3(0.34, 0.2, 0.09);
					col = tan_c;
					float s1 = abs(sin(rb.x * 4.2 + sin(rb.y * 3.1 + sd) * 1.6));
					float s2 = abs(sin(rb.y * 4.7 + cos(rb.x * 2.7) * 1.8 + 1.3));
					float s3 = abs(sin((rb.x + rb.y) * 3.3 + sd * 2.0));
					if (s1 < 0.2 || s2 < 0.18 || s3 < 0.13) {
						col = twig;
					}
					// burning: its back half catches the flame's colour
					float burn = smoothstep(0.35, -0.7, fb.x);
					col = mix(col, mix(tint.rgb, vec3(1.0, 0.85, 0.3), 0.35), burn * 0.55);
				}
			} else {
				if (d_fl > -OUT * 0.8) {
					col = ink.rgb;
				} else {
					float u = clamp(-fb.x / fl_len, 0.0, 1.0);
					col = mix(vec3(1.0, 0.93, 0.45), tint.rgb, smoothstep(0.0, 0.6, u + abs(fb.y) * 0.4));
					col = mix(col, vec3(0.8, 0.16, 0.04), smoothstep(0.6, 1.0, u));
				}
			}
		} else if (trail > 0.0) {
			// embers: bright dots drifting off behind it, no outline, flickering
			for (int k = 0; k < 3; k++) {
				float fk = float(k);
				float drift = mod(TIME * 2.2 + fk * 0.37 + sd * 0.13, 0.6);
				vec2 ec = vec2(-1.9 - fk * 0.32 - drift, 0.55 * sin(TIME * 6.0 + fk * 2.1 + sd));
				float er = 0.17 - 0.035 * fk;
				if (length(fb - ec) < er && sin(TIME * 21.0 + fk * 3.0 + sd * 7.0) > -0.4) {
					hit = true;
					col = fk < 1.0 ? vec3(1.0, 0.9, 0.4) : vec3(1.0, 0.55, 0.12);
				}
			}
		}
	}
	if (!hit) {
		discard;
	}
	// the glow: brighter colours (ink stays ink)
	ALBEDO = col == ink.rgb ? col : min(col * (0.82 + 0.18 * glow), vec3(1.0));
}
