// The hero's painting once more, over his speed trails (pass 49, Garry: "the speed up trail should be rendered underneath
// the 2.5d sprite of the hero"). The first pass (sprite_billboard) is opaque and drawn before everything see-through, so an
// additive trail running between him and the camera painted over him. This pass is the same quad and frame in the
// see-through queue at BillboardSprite.OVER_PRIORITY, after the trails (Fx.SPEED_TRAIL_PRIORITY) and before every other
// effect (priority 0), pulled PULL metres towards the camera so it passes the depth test on his own first pass and nowhere
// else: whatever really stands in front of him still hides him. Same vertex maths as sprite_billboard.
// Pass 56 (Garry: "Hero for some reason walks on water, they are not submerged at all ... Should be submerged like all the
// enemies"): the oasis is a see-through disc drawn at priority -10, so it tints the lower half of every painting that wades
// (his first pass's too) and this pass, drawn after it, painted his whole figure over it again. So the pass leaves out
// each pixel the water's disc covers on his first pass: where the line from the camera down to the point on his painting
// crosses the disc's top face inside its radius, or its rim on the way down. The water then tints him there exactly as it
// tints a creature, and stepping in or out needs no switch (BillboardSprite.set_water hands the disc over). A speed trail
// (drawn before this pass) shows across him there as it shows across the water, and his outline where something hides
// him (sprite_silhouette) leaves out the same pixels with the same test.
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix;

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
// metres towards the camera: enough to win the depth test over its own first pass, too little to show through anything
uniform float pull = 0.08;
// the water's disc (pass 56): x and z its centre, y its top face, w its radius; a radius of 0 is no water
uniform vec4 water = vec4(0.0, -1000.0, 0.0, 0.0);
// how far the disc's rim reaches under its top face (the Oasis is a cylinder this thick)
uniform float water_thick = 0.08;
// pass 87 (lane FIXES): the hero's evade: this pass alone draws him, at this alpha (his first pass steps aside below 1)
uniform float fade_alpha = 1.0;

varying vec2 v_uv;
// the point on his painting in the world, before the pull: the very point his first pass draws at this pixel
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
	// towards the camera along the view axis (view space looks down -Z), x and y scaled with it so it projects onto the
	// very same pixels as the first pass
	float z0 = min(VERTEX.z, -0.01);
	float z1 = min(z0 + pull, -0.005);
	VERTEX.xy *= z1 / z0;
	VERTEX.z = z1;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	// under the water's surface: left out where the disc covers it (pass 56), so the water's tint shows on his first pass
	if (water.w > 0.0 && v_world.y < water.y) {
		vec3 cam = CAMERA_POSITION_WORLD;
		float drop = cam.y - v_world.y;
		if (drop > 0.0001) {
			vec2 run = v_world.xz - cam.xz;
			// where the line down to the point crosses the top face, and where it has gone through the rim's depth (or
			// reached the point, if that is less deep)
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
	vec3 col = c.rgb * tint.rgb;
	col = mix(col, vec3(1.0), flash);
	ALBEDO = col;
	ALPHA = fade_alpha;
}
