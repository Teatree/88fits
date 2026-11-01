// Pass 120 (lane GHOST): the Undertaker's Shovel's ghost bolts (core/systems/GhostBolts.gd; Garry: "attacks ... should be
// kind of ghostly projectiles like ones in Warcraft 3 ziggurat attack"), every bolt, wisp bead and pop in one MultiMesh of
// camera-facing quads, one draw call. Mixed, not added (pale light added on the pale sand washes out: energy_orb's and
// tracer_line's lesson), so each piece carries a darker violet rim that reads on the sand and on the stage filters.
// fog_disabled all the same (pass 113's rule for effects).
//   kind 0 BOLT  a spectral orb (a white heart, the pale body colour, a violet rim) whose wispy tail streams behind it
//                along its flight across the screen and wavers; a soft halo round the head
//   kind 1 WISP  a soft bead the bolt sheds as it flies: shrinking, fading from the body colour to violet
//   kind 2 POP   a soft glow of ghost-light swelling out with a white heart and a thin edge (a hit, a fizzle, the ghost's
//                fire)
// The instance's transform is data:
//   origin   = where the piece is (world)
//   column 0 = (size m, 0, 0): the head's width for a bolt, the quad's width for a bead or a pop
//   column 1 = a bolt's velocity (world, m/s): the tail streams the other way across the screen
// INSTANCE_CUSTOM: x = age 0..1 (a bead's, a pop's), y = kind, z = seed 0..1, w = a bolt's length in head widths (>= 1)
// INSTANCE COLOR:  a = opacity (rgb white: the Compatibility renderer wants the colours on, see CLAUDE.md)
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// drawn a little towards the camera, so a bolt reaching a body is not cut by it
uniform float toward_cam = 0.3;
uniform vec3 core_col : source_color = vec3(0.95, 0.99, 1.0);
uniform vec3 body_col : source_color = vec3(0.56, 0.91, 1.0);
uniform vec3 rim_col : source_color = vec3(0.48, 0.36, 0.84);
uniform float halo_alpha = 0.45;

varying vec4 v_col;
varying vec4 v_custom;

void vertex() {
	v_col = COLOR;
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	vec3 world;
	if (INSTANCE_CUSTOM.y < 0.5) {
		// a bolt: the quad laid along its flight across the screen, the head (one width round) at the bolt's spot
		vec3 v = MODEL_MATRIX[1].xyz;
		vec3 v_scr = v - cam_back * dot(v, cam_back);
		float sp = length(v_scr);
		if (sp > 0.05) {
			right = v_scr / sp;
			up = normalize(cross(cam_back, right));
		}
		float len = max(INSTANCE_CUSTOM.w, 1.0);
		vec3 centre = origin - right * (len - 1.0) * s * 0.5;
		world = centre + cam_back * toward_cam + (right * VERTEX.x * len + up * VERTEX.y) * s;
	} else {
		world = origin + cam_back * toward_cam + (right * VERTEX.x + up * VERTEX.y) * s;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	float kind = v_custom.y;
	float f = clamp(v_custom.x, 0.0, 1.0);
	vec3 col;
	float a;
	if (kind < 0.5) {
		// the bolt, in half-widths: X along the flight (-len at the tail's end .. +len at the head's front), Y across
		float len = max(v_custom.w, 1.0);
		float X = (UV.x - 0.5) * 2.0 * len;
		float Y = (0.5 - UV.y) * 2.0;
		float hx = len - 1.0;
		float R = 0.6;
		float dh = length(vec2(X - hx, Y)) / R;
		float ball = 1.0 - smoothstep(0.9, 1.02, dh);
		// a white heart, the body colour, a violet rim that reads on the sand
		vec3 head = mix(body_col, core_col, 1.0 - smoothstep(0.2, 0.55, dh));
		head = mix(head, rim_col, smoothstep(0.7, 0.96, dh));
		// the tail: as wide as the head where it leaves it, narrowing to its end, wavering more towards the end
		float t = clamp((X + len) / max(hx + len, 0.001), 0.0, 1.0);
		float w = R * 0.95 * pow(t, 0.9);
		float y0 = sin(X * 2.4 - TIME * 11.0 + v_custom.z * 6.283) * 0.22 * (1.0 - t);
		float dt = abs(Y - y0) / max(w, 0.02);
		float tail = (1.0 - smoothstep(0.6, 1.0, dt)) * pow(t, 0.55) * step(X, hx);
		vec3 tcol = mix(rim_col, body_col, smoothstep(0.1, 0.75, t));
		tcol = mix(tcol, core_col, 0.45 * (1.0 - smoothstep(0.0, 0.5, dt)) * t);
		tcol = mix(tcol, rim_col * 0.85, smoothstep(0.55, 0.95, dt));
		float halo = pow(clamp(1.0 - (dh - 1.0) / 0.65, 0.0, 1.0), 1.6) * halo_alpha;
		col = mix(tcol, head, ball);
		a = max(max(ball, tail * 0.95), halo * (1.0 - ball));
		if (ball < 0.01 && tail < 0.01) {
			col = body_col;
		}
	} else if (kind < 1.5) {
		// a wisp bead
		float r = length(UV - 0.5) * 2.0;
		col = mix(body_col, rim_col, smoothstep(0.1, 0.8, f));
		col = mix(col, rim_col * 0.85, smoothstep(0.35, 0.9, r));
		a = pow(clamp(1.0 - r, 0.0, 1.0), 1.4) * pow(1.0 - f, 1.2) * 0.85;
	} else {
		// a pop of ghost-light: a soft glow swelling out and fading, a white heart early on, a thin bright edge with a
		// violet line outside it (what reads on the sand), gone in its life
		float r = length(UV - 0.5) * 2.0;
		float open = 1.0 - pow(1.0 - f, 3.0);
		float rr = 0.3 + 0.62 * open;
		float glow = pow(clamp(1.0 - r / max(rr, 0.01), 0.0, 1.0), 0.8) * (1.0 - f);
		float edge = 1.0 - smoothstep(0.0, 0.07, abs(r - rr));
		float heart = (1.0 - smoothstep(0.0, 0.38, r)) * pow(1.0 - f, 2.0);
		col = mix(body_col, rim_col, smoothstep(rr - 0.05, rr + 0.05, r));
		col = mix(col, core_col, heart);
		a = max(max(glow * 0.75, edge * 0.85 * (1.0 - f)), heart);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * v_col.a;
}
