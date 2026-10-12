// Sprite-strip billboard for MultiMesh enemies. Faces the camera fully (face_camera = 1), pivoting on the feet,
// so a sprite is never seen edge-on from the high camera. face_camera = 0 gives the old upright Y-billboard.
// INSTANCE_CUSTOM: x = frame index (+ 0.5 in its fraction while the creature rises out of the sand, pass 60: floored
// here, read by enemy_silhouette, which draws nothing then), y = flip (0/1) + 2 x glow level (0..16, pass 33.10: the
// harpooner's red outline while it holds the hero on its rope) + 64 x special glow level (0..16, pass 69: a variance
// special's emissive rim in its own tint's colour, EnemyManager.special_glow_code), z = flash (-1..1, negative = poison
// green), w = squash (1 = normal)
// INSTANCE COLOR:  rgb = tint (elite colour), a = tint strength
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_opaque;
// Every painting writes stencil 1 where it draws a pixel (pass 54, Garry: gems and coins drawn under every 2.5D sprite):
// the gems and coins (PickupManager, see-through, drawn after every opaque thing) skip those pixels, so they lie under
// the creatures, the hero, the props and the structures wherever they overlap, in front of a painting's plane or not.
stencil_mode write, compare_always, 1;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
// grid strips: frames per row and number of rows (cols = 0 means one long row)
uniform float cols = 0.0;
uniform float rows = 1.0;
uniform float alpha_cut = 0.5;
uniform float face_camera : hint_range(0.0, 1.0) = 1.0;
// far zoom (pass 33.2): 0 at twice the base camera distance, 1 by 2.4x; a thicker dark-red rim round the figure and a
// faint warm tint, so a crowd of specks stays readable (EnemyManager._update_mark sets it)
uniform float mark : hint_range(0.0, 1.0) = 0.0;

varying vec2 v_uv;
varying vec4 v_tint;
varying float v_flash;
varying float v_glow;
// pass 69: the special's glow 0..1 and its rim colour (the tint's hue at full brightness, in linear light), with a slow
// breath (0.8..1) so a special reads at a glance in a crowd
varying float v_sglow;
varying vec3 v_rim;

void vertex() {
	float frame = floor(INSTANCE_CUSTOM.x);
	float sg = floor(INSTANCE_CUSTOM.y / 64.0);
	float rest = INSTANCE_CUSTOM.y - sg * 64.0;
	float flip = mod(rest, 2.0);
	v_glow = floor(rest * 0.5) / 16.0;
	v_sglow = sg / 16.0;
	v_flash = INSTANCE_CUSTOM.z;
	float squash = max(INSTANCE_CUSTOM.w, 0.2);
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	if (cols > 0.5) {
		float c = mod(frame, cols);
		float r = floor(frame / cols);
		v_uv = vec2((uv.x + c) / cols, (uv.y + r) / rows);
	} else {
		v_uv = vec2((uv.x + frame) / frames, uv.y);
	}
	v_tint = COLOR;
	vec3 origin = MODEL_MATRIX[3].xyz;
	if (v_sglow > 0.01) {
		vec3 hue = COLOR.rgb / max(max(COLOR.r, COLOR.g), max(COLOR.b, 0.001));
		v_rim = pow(hue, vec3(2.2)) * (0.8 + 0.2 * sin(TIME * 3.2 + origin.x * 0.7 + origin.z * 0.5));
	} else {
		v_rim = vec3(0.0);
	}
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), cam_up, face_camera));
	vec3 right = normalize(cross(up, cam_back));
	float w = sx * (1.0 + (1.0 - squash) * 0.5);
	float h = sy * squash;
	// a roll about the feet (pass 50: a charger's rock and lean), read off the angle of the instance's x column; a plain
	// scaled basis rolls 0
	float roll = atan(MODEL_MATRIX[0].y, MODEL_MATRIX[0].x);
	vec2 q = vec2(VERTEX.x * w, (VERTEX.y + 0.5) * h);
	q = vec2(q.x * cos(roll) - q.y * sin(roll), q.x * sin(roll) + q.y * cos(roll));
	vec3 world = origin + right * q.x + up * q.y;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(sprite, v_uv);
	if (c.a < alpha_cut) {
		// the rim: a pixel just outside the figure takes a dark red, up to two screen pixels out at full mark; a glowing
		// creature (the harpooner on its rope) gets a wider rim in bright red that swells and fades with the glow
		if (mark > 0.01 || v_glow > 0.01 || v_sglow > 0.01) {
			vec2 px = fwidth(v_uv) * (0.8 + 1.4 * mark + 2.6 * v_glow + 4.2 * v_sglow);
			float a = 0.0;
			// pass 69: a special's glow has a bright core ring hugging the figure (it also fills the gaps a wide ring's far
			// samples leave by thin limbs)
			float ai = 0.0;
			if (v_sglow > 0.01) {
				vec2 pin = fwidth(v_uv) * (0.6 + 1.0 * v_sglow);
				ai = max(ai, texture(sprite, v_uv + vec2(pin.x, 0.0)).a);
				ai = max(ai, texture(sprite, v_uv - vec2(pin.x, 0.0)).a);
				ai = max(ai, texture(sprite, v_uv + vec2(0.0, pin.y)).a);
				ai = max(ai, texture(sprite, v_uv - vec2(0.0, pin.y)).a);
				ai = max(ai, texture(sprite, v_uv + pin * 0.7).a);
				ai = max(ai, texture(sprite, v_uv - pin * 0.7).a);
				ai = max(ai, texture(sprite, v_uv + vec2(pin.x, -pin.y) * 0.7).a);
				ai = max(ai, texture(sprite, v_uv + vec2(-pin.x, pin.y) * 0.7).a);
				a = ai;
				vec2 pm = px * 0.55;
				a = max(a, texture(sprite, v_uv + vec2(pm.x, 0.0)).a);
				a = max(a, texture(sprite, v_uv - vec2(pm.x, 0.0)).a);
				a = max(a, texture(sprite, v_uv + vec2(0.0, pm.y)).a);
				a = max(a, texture(sprite, v_uv - vec2(0.0, pm.y)).a);
			}
			a = max(a, texture(sprite, v_uv + vec2(px.x, 0.0)).a);
			a = max(a, texture(sprite, v_uv - vec2(px.x, 0.0)).a);
			a = max(a, texture(sprite, v_uv + vec2(0.0, px.y)).a);
			a = max(a, texture(sprite, v_uv - vec2(0.0, px.y)).a);
			a = max(a, texture(sprite, v_uv + px * 0.7).a);
			a = max(a, texture(sprite, v_uv - px * 0.7).a);
			a = max(a, texture(sprite, v_uv + vec2(px.x, -px.y) * 0.7).a);
			a = max(a, texture(sprite, v_uv + vec2(-px.x, px.y) * 0.7).a);
			if (a < alpha_cut) {
				discard;
			}
			ALBEDO = mix(vec3(0.42, 0.04, 0.05), vec3(1.0, 0.1, 0.06), clamp(v_glow * 1.4, 0.0, 1.0));
			if (v_sglow > 0.01 && v_glow <= 0.01) {
				// pass 69: a special's rim in its own colour, a lighter core next to the figure (the tether's red wins while
				// it holds the rope)
				ALBEDO = ai >= alpha_cut ? mix(v_rim, vec3(1.0), 0.45) : v_rim;
			}
		} else {
			discard;
		}
	} else {
	vec3 col = mix(c.rgb, v_tint.rgb, v_tint.a * 0.65);
	// a negative flash is a poison tick: green-white instead of white
	// white flash; negative = the green-white of a poison tick; above 1.5 = the orange of a fire tick (2 + flash)
	vec3 flash_col = vec3(1.0);
	float fl = abs(v_flash);
	if (v_flash < 0.0) {
		flash_col = vec3(0.62, 1.0, 0.5);
	} else if (v_flash > 1.5) {
		flash_col = vec3(1.0, 0.62, 0.25);
		fl = v_flash - 2.0;
	}
	col = mix(col, flash_col, clamp(fl, 0.0, 1.0));
	// the far-zoom tint: a touch of warm red over the whole figure
	col = mix(col, vec3(1.0, 0.32, 0.26), mark * 0.16);
	if (v_glow > 0.01) {
		// the painted outline turns red too: a dark pixel within a few texels of the figure's edge is outline
		vec2 tp = 4.0 / vec2(textureSize(sprite, 0));
		float edge = 1.0;
		edge = min(edge, texture(sprite, v_uv + vec2(tp.x, 0.0)).a);
		edge = min(edge, texture(sprite, v_uv - vec2(tp.x, 0.0)).a);
		edge = min(edge, texture(sprite, v_uv + vec2(0.0, tp.y)).a);
		edge = min(edge, texture(sprite, v_uv - vec2(0.0, tp.y)).a);
		edge = min(edge, texture(sprite, v_uv + tp * 0.7).a);
		edge = min(edge, texture(sprite, v_uv - tp * 0.7).a);
		edge = min(edge, texture(sprite, v_uv + vec2(tp.x, -tp.y) * 0.7).a);
		edge = min(edge, texture(sprite, v_uv + vec2(-tp.x, tp.y) * 0.7).a);
		float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		if (edge < alpha_cut && lum < 0.3) {
			col = mix(col, vec3(1.0, 0.1, 0.06), v_glow);
		}
	} else if (v_sglow > 0.01) {
		// pass 69: a special's painted outline lights up in its rim's colour too, as far as its glow says
		vec2 tp = 3.0 / vec2(textureSize(sprite, 0));
		float edge = 1.0;
		edge = min(edge, texture(sprite, v_uv + vec2(tp.x, 0.0)).a);
		edge = min(edge, texture(sprite, v_uv - vec2(tp.x, 0.0)).a);
		edge = min(edge, texture(sprite, v_uv + vec2(0.0, tp.y)).a);
		edge = min(edge, texture(sprite, v_uv - vec2(0.0, tp.y)).a);
		float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		if (edge < alpha_cut && lum < 0.3) {
			col = mix(col, v_rim, 0.85 * v_sglow);
		}
	}
	ALBEDO = col;
	}
}
