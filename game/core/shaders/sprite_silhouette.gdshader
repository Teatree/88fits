// The occluded pass of sprite_billboard: the hero's outline where a prop hides him. Same vertex maths, inverted depth test.
// Single sprite-strip billboard (the player, anything that is not a MultiMesh). Same maths as
// enemy_billboard.gdshader but driven by uniforms, plus a roll (lean) around the feet.
// Pass 56: drawn after the see-through oasis, it drew his underwater legs' rim and fill untinted over the water when a
// creature stood in front of him as he waded, so it leaves out what the water's disc covers, with the very test of
// sprite_billboard_over (BillboardSprite.set_water hands both passes the disc).
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_test_inverted, depth_draw_never, blend_mix;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float frames = 8.0;
uniform float frame = 0.0;
// grid strips: frames per row and number of rows (cols = 0 means one long row)
uniform float cols = 0.0;
uniform float rows = 1.0;
uniform float flip = 0.0;
uniform float flash = 0.0;
uniform float squash = 1.0;      // vertical scale
uniform float stretch = 1.0;     // horizontal scale
uniform float roll = 0.0;        // lean in radians, pivot on the feet
uniform float height = 1.6;      // sprite height in metres
uniform float face_camera : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_cut = 0.5;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform float fill_alpha = 0.18;
uniform float rim_texels = 1.5;
// the water's disc (pass 56): x and z its centre, y its top face, w its radius; a radius of 0 is no water
uniform vec4 water = vec4(0.0, -1000.0, 0.0, 0.0);
// how far the disc's rim reaches under its top face (the Oasis is a cylinder this thick)
uniform float water_thick = 0.08;

varying vec2 v_uv;
// the point on his painting in the world (pass 56)
varying vec3 v_world;

void vertex() {
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	float f = floor(frame);
	if (cols > 0.5) {
		float c = mod(f, cols);
		float r = floor(f / cols);
		v_uv = vec2((uv.x + c) / cols, (uv.y + r) / rows);
	} else {
		v_uv = vec2((uv.x + f) / frames, uv.y);
	}
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), cam_up, face_camera));
	vec3 right = normalize(cross(up, cam_back));
	float lx = VERTEX.x * stretch * height;
	float ly = (VERTEX.y + 0.5) * squash * height;
	float c = cos(roll);
	float s = sin(roll);
	vec2 l = vec2(lx * c - ly * s, lx * s + ly * c);
	vec3 world = origin + right * l.x + up * l.y;
	v_world = world;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	// under the water's surface: left out where the disc covers it (pass 56, as sprite_billboard_over), so the water in
	// front of his legs keeps them out of the outline as it keeps them out of his painting
	if (water.w > 0.0 && v_world.y < water.y) {
		vec3 cam = CAMERA_POSITION_WORLD;
		float drop = cam.y - v_world.y;
		if (drop > 0.0001) {
			vec2 run = v_world.xz - cam.xz;
			vec2 at_top = cam.xz + run * ((cam.y - water.y) / drop);
			vec2 at_rim = cam.xz + run * ((cam.y - max(v_world.y, water.y - water_thick)) / drop);
			if (distance(at_top, water.xz) < water.w || distance(at_rim, water.xz) < water.w) {
				discard;
			}
		}
	}
	vec4 c = texture(sprite, v_uv);
	if (c.a < alpha_cut) {
		discard;
	}
	vec2 tx = rim_texels / vec2(textureSize(sprite, 0));
	float amin = min(min(texture(sprite, v_uv + vec2(tx.x, 0.0)).a, texture(sprite, v_uv - vec2(tx.x, 0.0)).a),
	                 min(texture(sprite, v_uv + vec2(0.0, tx.y)).a, texture(sprite, v_uv - vec2(0.0, tx.y)).a));
	float rim = amin < alpha_cut ? 1.0 : 0.0;
	ALBEDO = mix(c.rgb * tint.rgb, rim_color.rgb, rim);
	ALPHA = mix(fill_alpha, rim_color.a, rim);
}
