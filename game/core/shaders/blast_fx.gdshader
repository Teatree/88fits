// The hero's explosions (pass 110, lane VFX; Garry: "Explosions - at some point became quite invisible ... for all the
// explosive weapons. Can you make them better?"). Fx's blast pool: one camera-facing quad per piece, animated entirely
// here (as the death splash is, core/shaders/blood_splash.gdshader), so the CPU writes a piece once when the blast goes
// off and never again, and nothing else on the screen can crowd a blast out. Five kinds, drawn in the cel look of the
// fire (core/shaders/fire_billboard.gdshader: hard bands, a dark rim) so they read on the pale sand as well as on the
// dark stage filters:
//   0 FLASH     a white-hot disc ringed in the blast's colour and its dark rim, popping open over a tenth of a second
//   1 FIREBALL  a lumpy ball lit from above: a hot heart that shrinks, the colour's body cooling to embers, a dark rim; it
//               pops open (an ease-out with a small overshoot) and breaks up into holes as it burns out
//   2 SMOKE     a dark cloud rising out of it, swelling and fraying (the dust puff's recipe, darker)
//   3 SPARK     a hot streak flung out and falling, drawn long along its flight, with a dark rim so it reads on sand
//   4 DEBRIS    a dark clod thrown up and falling back
// The instance's transform is data, not a placement:
//   origin = where the piece starts (world)
//   column 0 = its velocity (m/s, world)
//   column 1 = x: size at birth (m), y: size at its fullest (m), z: gravity (m/s^2, down)
//   column 2 = x: when it starts (Fx's clock, the `now` uniform), y: how long it lives (s), z: a spark's stretch per m/s;
//              for the flash and the fireball, how far up the screen its middle stands over its foot, in its own sizes
// The flash and the fireball stand on their foot on the sand like a painting: their quad faces the camera through the
// foot (lifted `toward` metres towards the camera so the sand never cuts their lower edge), so whoever stands in front of
// the blast's foot (the hero a few metres south of it) is drawn over it and whoever stands behind it is hidden.
// INSTANCE_CUSTOM: x = seed 0..1, y = kind, z = metres it is drawn towards the camera, w = drag (1/s: how fast its speed
//                  dies away)
// INSTANCE COLOR:  rgb = the blast's colour (its body; the heart, the embers and the rim are worked out from it), or the
//                  smoke's or the clod's own colour; a = opacity
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// Fx's clock in seconds (it stops with the game), set every frame while a piece lives
uniform float now = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec4 v_col;
// x = age 0..1, y = seed, z = kind
varying vec3 v_data;

void vertex() {
	v_col = COLOR;
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 vel = MODEL_MATRIX[0].xyz;
	vec3 sz = MODEL_MATRIX[1].xyz;
	vec3 tm = MODEL_MATRIX[2].xyz;
	float age = now - tm.x;
	float life = max(tm.y, 0.001);
	float f = age / life;
	float kind = INSTANCE_CUSTOM.y;
	v_data = vec3(clamp(f, 0.0, 1.0), INSTANCE_CUSTOM.x, kind);
	if (f < 0.0 || f >= 1.0) {
		// not started yet, or gone: every corner on one point, nothing drawn
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		float drag = INSTANCE_CUSTOM.w;
		float travel = drag > 0.001 ? (1.0 - exp(-drag * age)) / drag : age;
		vec3 p = p0 + vel * travel + vec3(0.0, -0.5 * sz.z * age * age, 0.0);
		vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
		vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
		float s;
		float len = 1.0;
		if (kind < 0.5) {
			s = mix(sz.x, sz.y, 1.0 - pow(1.0 - f, 3.0));
		} else if (kind < 1.5) {
			// pops open over its first fifth with a small overshoot, then keeps swelling a little as it burns
			float k = min(f * 5.0, 1.0);
			float pop = 1.0 - pow(1.0 - k, 3.0) + 0.1 * sin(k * 3.14159) * (1.0 - k);
			s = mix(sz.x, sz.y, pop) * (1.0 + 0.14 * f);
		} else if (kind < 2.5) {
			s = mix(sz.x, sz.y, 1.0 - (1.0 - f) * (1.0 - f));
		} else if (kind < 3.5) {
			// a spark: its full size at once, shrinking, drawn along its flight across the screen
			s = mix(sz.x, sz.y, f);
			vec3 v_now = vel * (drag > 0.001 ? exp(-drag * age) : 1.0) + vec3(0.0, -sz.z * age, 0.0);
			vec3 v_scr = v_now - cam_back * dot(v_now, cam_back);
			float sp = length(v_scr);
			if (sp > 0.05) {
				right = v_scr / sp;
				up = normalize(cross(cam_back, right));
				len = 1.0 + sp * tm.z;
			}
		} else {
			// a clod tumbling: turned in the screen's plane
			s = sz.x;
			float a = INSTANCE_CUSTOM.x * 6.2832 + age * (6.0 + 8.0 * INSTANCE_CUSTOM.x);
			vec3 r2 = right * cos(a) + up * sin(a);
			up = up * cos(a) - right * sin(a);
			right = r2;
		}
		float lift = kind < 1.5 ? tm.z : 0.0;
		vec3 world = p + cam_back * INSTANCE_CUSTOM.z + (right * VERTEX.x * len + up * (VERTEX.y + lift)) * s;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float f = v_data.x;
	float seed = v_data.y;
	float kind = v_data.z;
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	vec3 base = v_col.rgb;
	// the blast's palette from its colour: a pale hot heart, the body, embers on the way to smoke, a dark saturated rim
	vec3 heart = mix(base, vec3(1.0, 0.99, 0.9), 0.72);
	vec3 rim = base * base * 0.45;
	vec3 ember = mix(base, rim, 0.5);
	float a;
	vec3 col;
	if (kind < 0.5) {
		// the flash: white-hot, ringed in the colour and the rim
		float n = texture(noise_tex, UV * 0.9 + vec2(seed * 5.1, seed * 2.3)).r;
		float edge = 0.94 - r - (n - 0.5) * 0.16;
		float aa = max(fwidth(edge), 0.004) * 1.2;
		a = smoothstep(0.0, aa, edge);
		col = mix(vec3(1.0, 1.0, 0.94), heart, 1.0 - smoothstep(0.16, 0.3, edge));
		col = mix(col, base, 1.0 - smoothstep(0.1, 0.1 + aa, edge));
		col = mix(col, rim, 1.0 - smoothstep(0.035, 0.035 + aa, edge));
		a *= 1.0 - smoothstep(0.45, 1.0, f);
	} else if (kind < 1.5) {
		// the fireball
		float n1 = texture(noise_tex, UV * 0.75 + vec2(seed * 7.13, seed * 3.71 + f * 0.35)).r;
		float n2 = texture(noise_tex, UV * 1.7 + vec2(-seed * 4.37, seed * 9.11 - f * 0.6)).r;
		float ang = atan(p.y, p.x);
		// a cartoon cloud's outline: rounded bumps with notches between them
		float bumps = sqrt(abs(sin(ang * 3.5 + seed * 31.0)));
		float erode = smoothstep(0.35, 1.0, f);
		// how far inside its edge a point is (positive inside)
		float edge = 0.8 + 0.1 * bumps - r - (n1 - 0.5) * 0.22;
		// burning out: holes open from the noise and the whole thins
		edge = mix(edge, min(edge, (n2 - erode) * 0.8), smoothstep(0.32, 0.55, f)) - erode * 0.1;
		float aa = max(fwidth(edge), 0.004) * 1.2;
		a = smoothstep(0.0, aa, edge);
		// cel shading lit from the upper left: a light body and a shaded crescent low on the right
		float lit_d = length(p * 2.0 - vec2(-0.22, -0.3)) + (n2 - 0.5) * 0.25;
		float shade = smoothstep(0.78, 0.84, lit_d);
		vec3 body = mix(mix(base, heart, 0.22), mix(base, rim, 0.38), shade);
		// cooling to embers as it burns out
		body = mix(body, ember, smoothstep(0.25, 0.65, f));
		// the heart: high in the ball, most of it at first, gone by mid-life
		float hr = mix(0.6, -0.25, smoothstep(0.03, 0.42, f));
		float d = length(p * 2.0 - vec2(-0.08, -0.16)) + (n1 - 0.5) * 0.22;
		float hot = 1.0 - smoothstep(hr - 0.02, hr + 0.02, d);
		col = mix(body, heart, hot);
		// the dark rim, thinning away as it burns out (the embers have no outline)
		float rim_w = 0.065 * (1.0 - smoothstep(0.45, 0.8, f));
		col = mix(col, rim, (1.0 - smoothstep(rim_w, rim_w + aa, edge)) * step(0.001, rim_w));
		a *= 1.0 - 0.85 * smoothstep(0.55, 1.0, f);
		a *= 1.0 - smoothstep(0.88, 1.0, f);
	} else if (kind < 2.5) {
		// smoke: the dust puff's soft cloud, its edge bitten deeper as it ages, lit from above
		float n1 = texture(noise_tex, UV * 0.6 + vec2(seed * 7.13, seed * 3.7 + TIME * 0.05)).r;
		float n2 = texture(noise_tex, UV * 1.3 + vec2(-seed * 5.31, seed * 1.9 + TIME * 0.09)).r;
		float n = n1 * 0.6 + n2 * 0.4;
		float v = (1.0 - r) - n * (0.35 + 0.35 * f) - f * 0.22;
		a = smoothstep(0.0, 0.2, v);
		float lit = 1.0 - smoothstep(-0.25, 0.15, p.y);
		col = mix(base * 0.8, mix(base, vec3(1.0), 0.16), lit);
		a *= 1.0 - f * f;
	} else if (kind < 3.5) {
		// a spark: white-hot in its middle, the colour round it, a dark rim
		a = 1.0 - smoothstep(0.82, 1.0, r);
		col = mix(vec3(1.0, 1.0, 0.9), heart, smoothstep(0.1, 0.4, r));
		col = mix(col, base, smoothstep(0.42, 0.55, r));
		col = mix(col, rim, smoothstep(0.62, 0.74, r));
		col = mix(col, mix(base, rim, 0.4), smoothstep(0.5, 1.0, f) * (1.0 - smoothstep(0.62, 0.74, r)));
		a *= 1.0 - smoothstep(0.65, 1.0, f);
	} else {
		// a clod: a lumpy dark lump, a lighter top
		float ang = atan(p.y, p.x);
		float edge = 0.8 + 0.12 * sin(ang * 4.0 + seed * 20.0) + 0.06 * sin(ang * 7.0 + seed * 9.0) - r;
		a = smoothstep(0.0, 0.08, edge);
		col = mix(base, base * 1.6 + vec3(0.05), (1.0 - smoothstep(-0.2, 0.15, p.y)) * 0.6);
		a *= 1.0 - smoothstep(0.75, 1.0, f);
	}
	if (a <= 0.004) {
		discard;
	}
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = clamp(a * v_col.a, 0.0, 1.0);
}
