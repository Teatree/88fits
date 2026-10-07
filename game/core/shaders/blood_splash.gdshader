// The death splash (pass 58, Garry: "a red splash VFX ... a kind of a puff ... make it easier to tell when an enemy
// died. It should[n't] be a lot, but it should be noticeable saturated colour that is visible on enemies when they die.
// The animation is brief"): Fx's blood pool, one camera-facing quad per piece, animated entirely here so the CPU writes
// a piece once, when it is thrown, and never again. Two kinds: the splat (a lobed blob whose edge the flames' noise bites,
// popping open with a pale hot middle, a dark rim round it and a wet highlight, breaking into spatter as it fades) and
// the drops flung out of it (round, drawn long along their flight, falling).
// The instance's transform is data, not a placement:
//   origin = where the piece starts (world)
//   column 0 = its velocity (m/s, world)
//   column 1 = x: size at birth (m), y: size at its fullest / at its end (m), z: gravity (m/s^2, down)
//   column 2 = x: when it was thrown (Fx's clock, the `now` uniform), y: how long it lives (s), z: how much longer a
//              drop is drawn per m/s of its speed across the screen
// (Birth and life ride on the transform, which is full float precision on every renderer, not on the custom data.)
// INSTANCE_CUSTOM: x = seed 0..1, y = kind (0 the splat, 1 a drop), z = metres it is drawn towards the camera, so it
//                  lies over the dying creature's painting
// INSTANCE COLOR:  rgb = the creature's blood, a = opacity
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// Fx's clock in seconds (it stops with the game), set every frame
uniform float now = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// The run's camera stands base_dist m from the hero and backs off with his speed and level (CameraRig, up to about 2x):
// a piece grows by zoom_keep of how far out the camera is from it, so a splash keeps reading when everything shrinks
// (0.3 since the pass 58 review: at 0.5 a crowd's splats grew half again at the late zoom and merged into one sheet).
uniform float base_dist = 22.5;
uniform float zoom_keep = 0.3;

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
		// not thrown yet, or gone: every corner on one point, nothing drawn
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else {
		vec3 p = p0 + vel * age + vec3(0.0, -0.5 * sz.z * age * age, 0.0);
		vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
		vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
		float s;
		float len = 1.0;
		if (kind < 0.5) {
			// the splat pops open over its first fifth (an ease-out with a small overshoot), holds, and shrinks a
			// little as it breaks up
			float k = min(f * 5.0, 1.0);
			float pop = 1.0 - pow(1.0 - k, 3.0) + 0.12 * sin(k * 3.14159) * (1.0 - k);
			s = mix(sz.x, sz.y, pop) * (1.0 - 0.18 * smoothstep(0.55, 1.0, f));
		} else {
			// a drop: its full size at once, shrinking as it flies, drawn along its flight across the screen
			s = mix(sz.x, sz.y, f);
			vec3 v_now = vel + vec3(0.0, -sz.z * age, 0.0);
			vec3 v_scr = v_now - cam_back * dot(v_now, cam_back);
			float sp = length(v_scr);
			if (sp > 0.05) {
				right = v_scr / sp;
				up = normalize(cross(cam_back, right));
				len = 1.0 + sp * tm.z;
			}
		}
		float zoom = max(length(INV_VIEW_MATRIX[3].xyz - p) / base_dist, 1.0);
		s *= 1.0 + zoom_keep * (zoom - 1.0);
		vec3 world = p + cam_back * INSTANCE_CUSTOM.z + (right * VERTEX.x * len + up * VERTEX.y) * s;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float f = v_data.x;
	float seed = v_data.y;
	vec2 p = UV - 0.5;
	vec3 base = v_col.rgb;
	// the outline: the colour much darker, so the splash reads on bright sand and on a painting alike
	vec3 dark = base * 0.32;
	vec3 pale = mix(base, vec3(1.0), 0.62);
	float a;
	vec3 col;
	if (v_data.z < 0.5) {
		// the splat: a disc with lobes, its edge bitten by the noise, deeper as it ages
		float r = length(p) * 2.0;
		float ang = atan(p.y, p.x);
		float lobes = 0.09 * sin(ang * 5.0 + seed * 37.0) + 0.06 * sin(ang * 8.0 + seed * 19.0);
		float n = texture(noise_tex, UV * 0.7 + vec2(seed * 7.13, seed * 3.71)).r;
		float edge = 0.8 + lobes * (0.6 + 0.6 * f) - r - (n - 0.5) * (0.2 + 0.3 * f) - f * f * 0.3;
		// as it fades it breaks into spatter: holes open up in its body (eased in, so no dark specks show before)
		float n2 = texture(noise_tex, UV * 1.6 + vec2(-seed * 4.37, seed * 9.11)).r;
		float holes = smoothstep(0.5, 1.0, f) * 0.7;
		edge = mix(edge, min(edge, (n2 - holes) * 0.6), smoothstep(0.45, 0.6, f));
		a = smoothstep(0.0, 0.035, edge);
		float rim = 1.0 - smoothstep(0.04, 0.11, edge);
		col = mix(base, dark, rim);
		// a wet highlight up on the left
		float hl = 1.0 - smoothstep(0.05, 0.16, length(p - vec2(-0.13, -0.15)));
		col = mix(col, pale, hl * 0.75 * (1.0 - rim));
		// the pop: a pale hot middle that cools into the colour over the first fifth
		float hot = (1.0 - smoothstep(0.0, 0.22, f)) * (1.0 - smoothstep(0.0, 0.55, r));
		col = mix(col, pale, hot * 0.85);
		a *= 1.0 - smoothstep(0.72, 1.0, f);
	} else {
		// a drop: round in its own frame (the vertex stretched it along its flight), a dark rim and a glint
		float r = length(p) * 2.0;
		a = 1.0 - smoothstep(0.86, 1.0, r);
		col = mix(base, dark, smoothstep(0.5, 0.78, r));
		col = mix(col, pale, (1.0 - smoothstep(0.0, 0.32, length(p - vec2(-0.1, -0.12)) * 2.0)) * 0.8);
		a *= 1.0 - smoothstep(0.7, 1.0, f);
	}
	if (a <= 0.004) {
		discard;
	}
	ALBEDO = col;
	ALPHA = a * v_col.a;
}
