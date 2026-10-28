// Pass 112 (lane MONK): the Monk's energy spheres (core/systems/EnergyOrbs.gd), one camera-facing quad each, every sphere,
// gathering glow and trail bead in one MultiMesh. Garry: "a bright, very noticeable blue energy sphere".
// A sphere (INSTANCE_CUSTOM.y = 0): a solid ball filling the inner half of the quad, a white-hot core fading into the
// colour, a darker rim of the same hue at its edge (what reads on the light sand: no additive glow, it washes out there,
// see tracer_line.gdshader), and a soft halo of the colour out to the quad's edge, brighter on the pulse.
// A bead (INSTANCE_CUSTOM.y = 1): a soft round puff of the colour, for the trail.
// INSTANCE_CUSTOM: x = pulse 0..1, y = kind
// INSTANCE COLOR:  rgb = the colour as it should look on the screen (sRGB, as in the JSON), a = opacity
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// drawn a little towards the camera, so a sphere near a body is not cut by it
uniform float toward_cam = 0.25;
uniform vec3 core_white = vec3(0.92, 0.98, 1.0);
uniform float halo_alpha = 0.55;
uniform float rim_pow = 2.2;
uniform float rim_gain = 0.75;

varying vec4 v_col;
varying vec2 v_custom;

void vertex() {
	v_col = COLOR;
	v_custom = INSTANCE_CUSTOM.xy;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	vec3 world = origin + cam_back * toward_cam + (right * VERTEX.x + up * VERTEX.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	vec3 c = v_col.rgb;
	float pulse = v_custom.x;
	if (v_custom.y > 0.5) {
		// a trail bead: a soft puff
		float a = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
		ALBEDO = to_linear(mix(c, vec3(1.0), 0.25));
		ALPHA = a * v_col.a;
	} else {
		// the ball (r < 0.5): white core -> lit colour -> the colour -> a dark rim
		float body = 1.0 - smoothstep(0.47, 0.51, r);
		float core = 1.0 - smoothstep(0.0, 0.2 + 0.05 * pulse, r);
		vec3 lit = mix(c, vec3(1.0), 0.45);
		vec3 ball = mix(lit, c, smoothstep(0.12, 0.38, r));
		vec3 rim = pow(max(c, vec3(0.0)), vec3(rim_pow)) * rim_gain;
		ball = mix(ball, rim, smoothstep(0.38, 0.49, r));
		ball = mix(ball, core_white, core);
		// the halo outside it, fading to the quad's edge
		float halo = pow(clamp((1.0 - r) / 0.5, 0.0, 1.0), 1.8) * halo_alpha * (0.7 + 0.3 * pulse);
		vec3 col = mix(c, ball, body);
		ALBEDO = to_linear(col);
		ALPHA = max(body, halo) * v_col.a;
	}
}
