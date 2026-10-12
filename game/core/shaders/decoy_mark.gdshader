// Pass 69 (lane HERO): the pink "?" over a creature May's inflatable double fooled (core/systems/Decoy.gd). One quad per
// creature in one MultiMesh, turned to the camera and hung above the head from the feet, like the badges
// (badge.gdshader), but alive: it bobs, pulses and rocks, and pops in when the creature is first fooled.
// INSTANCE_CUSTOM: x = metres up the screen from the feet to the mark's centre, y = its size in metres, z = a phase so
// neighbours do not move in step, w = 0..1 how far it has popped in.
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_test_disabled, depth_draw_never, blend_mix;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	float lift = INSTANCE_CUSTOM.x;
	float ph = INSTANCE_CUSTOM.z;
	float pop = clamp(INSTANCE_CUSTOM.w, 0.0, 1.0);
	// pop in with a little overshoot, then a quick pulse and a bob
	float over = 1.0 + 0.35 * sin(pop * 3.14159) * (1.0 - pop * 0.5);
	float pulse = 1.0 + 0.14 * sin(TIME * 7.0 + ph);
	float s = INSTANCE_CUSTOM.y * pop * over * pulse;
	float bob = (0.5 + 0.5 * sin(TIME * 4.2 + ph)) * 0.16;
	float rock = sin(TIME * 3.1 + ph * 1.3) * 0.22;
	vec2 v = VERTEX.xy;
	v = vec2(v.x * cos(rock) - v.y * sin(rock), v.x * sin(rock) + v.y * cos(rock));
	vec3 world = origin + cam_right * v.x * s + cam_up * (lift + bob + v.y * s);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(INV_VIEW_MATRIX[2].xyz, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(tex, v_uv);
	if (c.a < 0.02) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
