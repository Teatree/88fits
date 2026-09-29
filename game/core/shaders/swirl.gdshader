// A turning spiral (pass 35). The Singularity's black hole lays one flat on the ground (a PlaneMesh, billboard 0); the
// Teleport stands one in its ring's hole, facing the camera like the painting round it (a QuadMesh, billboard 1, the
// centre `lift` metres up the camera's up and `shift` along its right, `push` metres behind the painting so the stone
// frame covers its edge). Arms of colour_b over colour_a, a middle of colour_eye, fading out at the rim; `energy`
// brightens it and `speed` turns it (the Teleport speeds up while the hero charges it).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled;

uniform vec4 color_a : source_color = vec4(0.12, 0.03, 0.22, 0.9);
uniform vec4 color_b : source_color = vec4(0.8, 0.35, 1.0, 1.0);
uniform vec4 color_eye : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float arms = 3.0;
uniform float twist = 2.2;
uniform float speed = 2.0;
uniform float energy = 1.0;
uniform float alpha = 1.0;
uniform float eye = 0.2;
uniform float billboard = 0.0;
uniform float size = 1.0;
uniform float lift = 0.0;
uniform float shift = 0.0;
uniform float push = 0.0;

void vertex() {
	if (billboard > 0.5) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
		vec3 world = origin + cam_up * lift + cam_right * shift + cam_right * VERTEX.x * size + cam_up * VERTEX.y * size;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	} else {
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
	VERTEX.z -= push;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	// the spiral arms wind in towards the middle and turn with time
	float s = sin(arms * a + twist * 6.2831 * r - TIME * speed);
	float arm = smoothstep(0.1, 0.95, s * 0.5 + 0.5);
	vec3 col = mix(color_a.rgb, color_b.rgb, arm) * energy;
	float body_a = mix(color_a.a, color_b.a, arm);
	float eye_m = smoothstep(eye, eye + 0.14, r);
	col = mix(color_eye.rgb * energy, col, eye_m);
	float rim = 1.0 - smoothstep(0.78, 1.0, r);
	ALBEDO = col;
	ALPHA = clamp(alpha * rim * mix(color_eye.a, body_a, eye_m), 0.0, 1.0);
}
