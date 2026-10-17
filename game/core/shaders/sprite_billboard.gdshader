// Single sprite-strip billboard (the player, anything that is not a MultiMesh). Same maths as
// enemy_billboard.gdshader but driven by uniforms, plus a roll (lean) around the feet.
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_opaque;
// Every painting (the hero, a structure, the portal, a power-up, a flower) writes stencil 1 where it draws a pixel (pass 54, Garry: gems and coins drawn under every 2.5D sprite):
// the gems and coins (PickupManager, see-through, drawn after every opaque thing) skip those pixels, so they lie under
// the creatures, the hero, the props and the structures wherever they overlap, in front of a painting's plane or not.
stencil_mode write, compare_always, 1;

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
// pass 82 (lane TOTEM): how far the painting is drained of its colour (a used Totem Pole greying over 0.4 s)
uniform float desat : hint_range(0.0, 1.0) = 0.0;
// pass 87 (lane FIXES): the hero's evade (Player._evade_ghost_start, BillboardSprite.set_fade): under 1 this pass draws
// nothing and his second pass (sprite_billboard_over, in the see-through queue) draws him at this alpha instead
uniform float fade_alpha = 1.0;

varying vec2 v_uv;

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
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	if (fade_alpha < 0.999) {
		discard;
	}
	vec4 c = texture(sprite, v_uv);
	if (c.a < alpha_cut) {
		discard;
	}
	vec3 col = mix(c.rgb, vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))), desat) * tint.rgb;
	col = mix(col, vec3(1.0), flash);
	ALBEDO = col;
}
