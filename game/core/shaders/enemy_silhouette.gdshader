// The occluded pass of enemy_billboard: drawn only where something nearer (a prop) already covers the creature, as a
// rim and a faint fill, so a goblin behind a cactus is still read. Same vertex maths, inverted depth test.
// Sprite-strip billboard for MultiMesh enemies. Faces the camera fully (face_camera = 1), pivoting on the feet,
// so a sprite is never seen edge-on from the high camera. face_camera = 0 gives the old upright Y-billboard.
// INSTANCE_CUSTOM: x = frame index, y = flip (0/1), z = flash (-1..1, negative = poison green), w = squash (1 = normal)
// INSTANCE COLOR:  rgb = tint (elite colour), a = tint strength
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_test_inverted, depth_draw_never, blend_mix;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
// grid strips: frames per row and number of rows (cols = 0 means one long row)
uniform float cols = 0.0;
uniform float rows = 1.0;
uniform float alpha_cut = 0.5;
uniform float face_camera : hint_range(0.0, 1.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.8, 0.55);
uniform float fill_alpha = 0.1;
uniform float rim_texels = 1.5;

varying vec2 v_uv;
varying vec4 v_tint;
varying float v_flash;

void vertex() {
	float frame = floor(INSTANCE_CUSTOM.x);
	float flip = INSTANCE_CUSTOM.y;
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
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), cam_up, face_camera));
	vec3 right = normalize(cross(up, cam_back));
	float w = sx * (1.0 + (1.0 - squash) * 0.5);
	float h = sy * squash;
	vec3 world = origin + right * VERTEX.x * w + up * (VERTEX.y + 0.5) * h;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(sprite, v_uv);
	if (c.a < alpha_cut) {
		discard;
	}
	// a rim wherever a neighbouring texel is empty: the outline of whatever part of the creature is hidden
	vec2 tx = rim_texels / vec2(textureSize(sprite, 0));
	float amin = min(min(texture(sprite, v_uv + vec2(tx.x, 0.0)).a, texture(sprite, v_uv - vec2(tx.x, 0.0)).a),
	                 min(texture(sprite, v_uv + vec2(0.0, tx.y)).a, texture(sprite, v_uv - vec2(0.0, tx.y)).a));
	float rim = amin < alpha_cut ? 1.0 : 0.0;
	vec3 col = mix(c.rgb, v_tint.rgb, v_tint.a * 0.65);
	ALBEDO = mix(col, rim_color.rgb, rim);
	ALPHA = mix(fill_alpha, rim_color.a, rim);
}
