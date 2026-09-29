// A creature's badge (pass 33.3): a crown over an Elite, a skull over a boss, a gear over the specials. One quad per
// creature in a MultiMesh (one MultiMesh per badge), turned to the camera and hung above the head from the feet.
// INSTANCE_CUSTOM: x = metres up the screen from the feet to the badge's centre, y = the badge's size in metres,
// z = a phase so neighbours do not bob in step. Drawn over the world, so a prop never hides it.
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
	float s = INSTANCE_CUSTOM.y;
	float ph = INSTANCE_CUSTOM.z;
	// a slow float and a small rock from side to side
	float bob = sin(TIME * 2.6 + ph) * 0.07 * s;
	float rock = sin(TIME * 1.7 + ph * 1.3) * 0.09;
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
