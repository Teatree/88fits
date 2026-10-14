// Wick flames (pass 76, lane MOLO; Garry: "Regenerate the Molotov Visuals, the flame looks weird"): the fire that burns
// on a thrown bottle's wick (core/systems/WickFlames.gd). Every piece is a quad standing on its base along an axis, the
// instance's Y column (base -> tip, any direction, its length the piece's height; the X column's length is its width),
// turned about that axis to face the camera, so a flame stays upright on the wick and leans back as the bottle flies,
// whatever the bottle under it does. One shader for every style (the style rides in the instance), one draw call for
// every flame, ember and spark in the air.
// INSTANCE_CUSTOM: x = phase (an ember's age 0..1, a pool flame's; a streamer piece's start along its tail 0..1;
//                      0 for a flame on a wick, which never ages)
//                  y = seed 0..1 (where it reads the noise, so no two burn alike)
//                  z = a streamer piece's share of its tail (du); 1 for a pool's torch flame (a flat foot fading into
//                      the spill instead of the round foot a flame on a rag has)
//                  w = style + 8 x blue: 0 torch flame, 1 streamer piece, 2 cartoon flame, 3 ember, 4 cartoon spark,
//                      5 heat glow
// COLOR: a = opacity (rgb unused: the palette is the shader's, orange or blue)
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// every piece is drawn this far towards the camera on top of what WickFlames already moved it (each style places its
// own depth: a flame sits a little behind its bottle, so the bottle stays in front of its own fire)
uniform float toward_cam = 0.0;
// the orange fire: a pale gold heart, an orange body, a red rim, a dark brown ink (the cartoon flame's outline)
uniform vec3 heart : source_color = vec3(1.0, 0.95, 0.62);
uniform vec3 body : source_color = vec3(1.0, 0.56, 0.12);
uniform vec3 rim : source_color = vec3(0.86, 0.17, 0.04);
uniform vec3 ink : source_color = vec3(0.36, 0.07, 0.02);
// the blue fire (Methanol, the Moonshine): a white heart, a sky-blue body, an indigo rim, a navy ink. Fire, not water:
// the flame's licking tongues, its glow and its sparks say so
uniform vec3 heart_b : source_color = vec3(0.8, 0.95, 1.0);
uniform vec3 body_b : source_color = vec3(0.22, 0.52, 1.0);
uniform vec3 rim_b : source_color = vec3(0.36, 0.14, 0.86);
uniform vec3 ink_b : source_color = vec3(0.1, 0.03, 0.3);

varying vec4 v_col;
// flat: the instance's own words, never blended across the quad (an interpolated 8.0 came out 7.99 on some pixels)
varying flat vec4 v_cus;

void vertex() {
	v_col = COLOR;
	v_cus = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	float h = length(ax);
	ax = h > 0.00001 ? ax / h : vec3(0.0, 1.0, 0.0);
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 right = cross(ax, cam_back);
	float rl = length(right);
	right = rl > 0.0001 ? right / rl : normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 world = origin + cam_back * toward_cam + right * VERTEX.x * w + ax * (VERTEX.y + 0.5) * h;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

// One tongue of the cartoon flame: positive inside. It rises from the base (y 0.2) to `top`, `w` wide at its foot,
// bending from x 0 at its foot to `cx` at its tip.
float tongue(vec2 p, float cx, float top, float w) {
	float f = clamp((p.y - 0.18) / max(top - 0.18, 0.001), 0.0, 1.0);
	float centre = cx * f * f;
	float hw = w * pow(max(1.0 - f, 0.0), 0.85);
	float inside = hw - abs(p.x - centre);
	// continuous past both ends (a jump there made fwidth huge along a whole row: a thin dark line over the flame)
	return inside - max(0.18 - p.y, 0.0) * 2.0 - max(p.y - top, 0.0) * 2.0;
}

// The cartoon flame's silhouette at `p` (x centred, y 0 at the base, 1 the quad's top): a fat round foot and three
// tongues, their tips swaying on the stepped clock `ph`. Positive inside.
float cartoon_shape(vec2 p, float ph) {
	float foot = 0.25 - length(vec2(p.x * 1.05, p.y - 0.29));
	float c = tongue(p, 0.03 * sin(ph * 1.3), 0.86 + 0.04 * sin(ph), 0.19);
	float l = tongue(p, -0.17 - 0.03 * sin(ph * 1.7 + 1.0), 0.6 + 0.06 * cos(ph * 0.9), 0.12);
	float r = tongue(p, 0.17 + 0.03 * cos(ph * 1.1 + 2.0), 0.66 + 0.06 * sin(ph * 1.5), 0.12);
	return max(max(foot, c), max(l, r));
}

void fragment() {
	float code = floor(v_cus.w + 0.5);
	float blue = step(7.5, code);
	float style = code - 8.0 * blue;
	vec3 c_heart = mix(heart, heart_b, blue);
	vec3 c_body = mix(body, body_b, blue);
	vec3 c_rim = mix(rim, rim_b, blue);
	vec3 c_ink = mix(ink, ink_b, blue);
	float sd = v_cus.y;
	float y = 1.0 - UV.y;   // 0 at the base, 1 at the tip
	float x = UV.x - 0.5;
	vec3 col = c_body;
	float a = 0.0;
	if (style < 0.5) {
		// the torch: a steady flame licking up off the rag, two tongues of noise racing up it, a soft glow round it
		float t = TIME;
		float n1 = texture(noise_tex, vec2(x * 0.7 + sd * 7.13, y * 0.6 - t * 1.9 + sd * 3.7)).r;
		float n2 = texture(noise_tex, vec2(x * 1.4 - sd * 5.31, y * 1.2 - t * 3.1)).r;
		float n = n1 * 0.6 + n2 * 0.4;
		float xs = x + (n1 - 0.5) * 0.3 * y;
		float r0 = 0.3;
		float grounded = step(0.5, v_cus.z);
		// a rag's flame swells from a round foot; a pool's rises out of the spill on a flat foot nearly as wide as it is,
		// widest a little above the ground
		float y0 = mix(r0, 0.14, grounded);
		float shape;
		if (y < y0 && grounded < 0.5) {
			shape = 1.0 - length(vec2(xs, y - r0)) / r0;
		} else if (y < y0) {
			shape = 1.0 - abs(xs) / max(r0 * (0.86 + 0.14 * y / y0), 0.0001);
		} else {
			float hw = r0 * pow(max(1.0 - (y - y0) / (0.97 - y0), 0.0), 0.62);
			shape = 1.0 - abs(xs) / max(hw, 0.0001);
		}
		shape *= 1.0 - 0.25 * y;
		// a pool's flame is eaten away as it ages (as Fx's tongues are); a wick's never ages
		float age = clamp(v_cus.x, 0.0, 1.0);
		float v = shape - n * (0.05 + (0.62 + 0.12 * grounded) * y * y + 0.1 * y) - age * age * 0.75;
		float aa = max(fwidth(v), 0.002) * 1.5;
		float a_rim = smoothstep(0.03, 0.03 + aa, v);
		float a_body = smoothstep(0.15, 0.15 + aa, v);
		// a blue flame's white heart is smaller, so the flame reads blue
		// and a pool's flame shows more of its body, as the creatures' burning flames beside it do
		float hh = 0.33 + 0.14 * blue + 0.12 * grounded;
		float a_heart = smoothstep(hh, hh + aa, v);
		col = mix(c_rim, c_body, a_body);
		col = mix(col, c_heart, a_heart);
		// the glow: the fire's light on the air round it, brightest at its foot (fading with a pool flame's age)
		float g = exp(-length(vec2(x * 2.2, (y - 0.3) * 1.3)) * 3.2) * 0.45 * (1.0 - age);
		col = mix(c_body, col, a_rim);
		a = max(a_rim, g);
		// a pool's flame rises out of the spill: its foot fades in
		a *= mix(1.0, smoothstep(0.0, 0.08, y), grounded);
	} else if (style < 1.5) {
		// a piece of the streamer: the fire the wick leaves in the air behind it, hottest at the wick, thinning to a
		// ragged red tail; `u` runs 0 at the wick to 1 at the tail's end, continuous from one piece to the next
		float u = v_cus.x + y * v_cus.z;
		float t = TIME;
		float hw = 0.5 * pow(max(1.0 - u, 0.0), 0.55) * (u < 0.08 ? sqrt(max(u / 0.08, 0.0)) * 0.5 + 0.5 : 1.0);
		float n1 = texture(noise_tex, vec2(x * 0.8 + sd * 4.1, u * 1.6 - t * 2.4)).r;
		float n2 = texture(noise_tex, vec2(x * 1.6 - sd * 2.7, u * 3.1 - t * 3.6)).r;
		float n = n1 * 0.55 + n2 * 0.45;
		float shape = 1.0 - abs(x + (n1 - 0.5) * 0.18 * u) / max(hw, 0.0001);
		float v = shape * (1.0 - 0.45 * u) - n * (0.12 + 0.6 * u) - u * u * 0.25;
		float aa = max(fwidth(v), 0.002) * 1.5;
		float a_rim = smoothstep(0.02, 0.02 + aa, v);
		float a_body = smoothstep(0.16 + 0.1 * u, 0.16 + 0.1 * u + aa, v);
		float a_heart = smoothstep(0.32 + 0.25 * u, 0.32 + 0.25 * u + aa, v);
		col = mix(c_rim, c_body, a_body);
		col = mix(col, c_heart, a_heart);
		// the tail's end darkens to smoke-red and fades
		col = mix(col, c_rim * 0.75, smoothstep(0.55, 1.0, u) * (1.0 - a_heart));
		a = a_rim * (1.0 - smoothstep(0.75, 1.0, u));
	} else if (style < 2.5) {
		// the cartoon flame: a bold, hand-drawn fire in three layers inside a dark ink line, its tongues jumping on a
		// stepped clock (twelve drawings a second, as a cartoon is drawn), never eaten by noise
		float ts = floor(TIME * 12.0 + sd * 12.0);
		float ph = ts * 1.9 + sd * 6.28;
		float jig = fract(sin(ts * 12.9898 + sd * 78.233) * 43758.5453) - 0.5;
		vec2 p = vec2(x - jig * 0.03 * y, y);
		float d0 = cartoon_shape(p, ph);
		float d1 = cartoon_shape(vec2(p.x / 0.7, (p.y - 0.02) / 0.74), ph + 1.3);
		float d2 = cartoon_shape(vec2(p.x / 0.42, (p.y - 0.04) / 0.46), ph + 2.6);
		float aa = max(fwidth(d0), 0.002) * 1.2;
		float a_out = smoothstep(-0.045 - aa, -0.045, d0);
		float a_rim = smoothstep(0.0, aa, d0);
		float a_mid = smoothstep(0.0, aa, d1);
		float a_in = smoothstep(0.0, aa, d2);
		col = mix(c_ink, c_rim, a_rim);
		col = mix(col, c_body, a_mid);
		col = mix(col, c_heart, a_in);
		a = a_out;
	} else if (style < 3.5) {
		// an ember: a hot dot that cools from the heart's colour to the rim's as it ages, and fades
		float age = clamp(v_cus.x, 0.0, 1.0);
		float d = length(vec2(x, y - 0.5)) * 2.0;
		float core = 1.0 - smoothstep(0.15, 0.45, d);
		col = mix(mix(c_body, c_rim, age), mix(c_heart, c_body, age), core);
		a = (1.0 - smoothstep(0.45, 1.0, d)) * (1.0 - age * age);
	} else if (style < 4.5) {
		// a cartoon spark: a round blob of fire in an ink ring, shrinking as it ages
		float age = clamp(v_cus.x, 0.0, 1.0);
		float r = 0.42 * (1.0 - 0.5 * age);
		vec2 q = abs(vec2(x, y - 0.5)) / max(r, 0.001);
		float d = (sqrt(q.x) + sqrt(q.y)) * r;   // a four-pointed star: d < r inside
		float aa = max(fwidth(d), 0.002) * 1.2;
		float a_out = 1.0 - smoothstep(r, r + aa, d);
		float a_fill = 1.0 - smoothstep(r * 0.72, r * 0.72 + aa, d);
		float a_hot = 1.0 - smoothstep(r * 0.42, r * 0.42 + aa, d);
		col = mix(c_ink, c_body, a_fill);
		col = mix(col, c_heart, a_hot);
		a = a_out;
	} else {
		// the heat glow: a soft round light, faint
		float d = length(vec2(x, y - 0.5)) * 2.0;
		col = c_body;
		a = (1.0 - smoothstep(0.0, 1.0, d)) * 0.5;
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * v_col.a;
}
