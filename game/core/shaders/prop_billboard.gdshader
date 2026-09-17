// One painted prop per instance (cacti, rocks, bones): a camera-facing quad pivoting on its base, like the creatures,
// but muted a touch and with a slow sway for greenery. Opaque with an alpha cut, so props and characters sort
// against each other per pixel by depth (no blend-order artefacts, no z-fighting between parallel quads).
// INSTANCE_CUSTOM: x = flip (0/1), y = sway amount (0 for rocks), z = sway phase
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_opaque;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;
uniform float mute : hint_range(0.0, 1.0) = 0.12;
uniform float face_camera : hint_range(0.0, 1.0) = 1.0;

varying vec2 v_uv;

void vertex() {
	float flip = INSTANCE_CUSTOM.x;
	float sway = INSTANCE_CUSTOM.y;
	float phase = INSTANCE_CUSTOM.z;
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	v_uv = uv;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), cam_up, face_camera));
	vec3 right = normalize(cross(up, cam_back));
	float ly = VERTEX.y + 0.5;
	// wind: the top of a plant leans a few degrees back and forth, the base stays put
	float lean = sin(TIME * 1.3 + phase) * sway * ly * ly;
	vec3 world = origin + right * (VERTEX.x * sx + lean * sy) + up * ly * sy;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(sprite, v_uv);
	if (c.a < alpha_cut) {
		discard;
	}
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(c.rgb, vec3(lum), mute) * (1.0 - mute * 0.3);
}
