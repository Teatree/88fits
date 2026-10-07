// A gem's glint (pass 56, Garry: the medium and large XP gems "glint now and then"): the chest's four-point sparkle
// (shine_aura mode 3) on a camera-facing quad, added to what is behind it. Drawn on PickupManager's glint MultiMesh:
// INSTANCE COLOR rgb = its tint (a pale shade of the gem's colour), a = how bright it is now; INSTANCE_CUSTOM.x = how
// far the star is turned (radians). Like the gems it lies under every painting: it draws only where no painting wrote
// stencil 1 (PickupManager.PAINTING_STENCIL). Its gem never covers it because it draws after the gems
// (PickupManager.GLINT_PRIORITY, one past theirs, and the gems write no depth); `toward_cam` pushes it a little towards
// the camera so the depth of the sand behind and under the gem never cuts into its rays.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, skip_vertex_transform, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform float toward_cam = 0.3;   // metres towards the camera (above)

varying vec4 v_col;
varying float v_turn;

void vertex() {
	v_col = COLOR;
	v_turn = INSTANCE_CUSTOM.x;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	float c = cos(v_turn);
	float sn = sin(v_turn);
	vec2 q = vec2(VERTEX.x * c - VERTEX.y * sn, VERTEX.x * sn + VERTEX.y * c);
	vec3 world = origin + cam_back * toward_cam + (right * q.x + up * q.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// two thin rays crossing, each tapering to nothing at the quad's edge, and a soft hot core
	float star = max(0.0, 1.0 - abs(p.x) * 7.0 - abs(p.y)) + max(0.0, 1.0 - abs(p.y) * 7.0 - abs(p.x));
	float a = clamp(star, 0.0, 1.0) + exp(-dot(p, p) * 18.0);
	ALBEDO = v_col.rgb;
	ALPHA = clamp(a * v_col.a, 0.0, 1.0);
}
