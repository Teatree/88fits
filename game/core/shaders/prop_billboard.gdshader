// One painted prop per instance (cacti, rocks, bones): a camera-facing quad pivoting on its base, like the creatures,
// but muted a touch and with a slow sway for greenery. Opaque with an alpha cut, so props and characters sort
// against each other per pixel by depth (no blend-order artefacts, no z-fighting between parallel quads).
// INSTANCE_CUSTOM: x = flip (0/1), y = sway amount (0 for rocks), z = sway phase, w = the tint's three rolls (pass 85,
// PropField.tint_code: r1 + 12 r2 + 144 r3, each 0..11)
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_opaque;
// Every painting (the props here too) writes stencil 1 where it draws a pixel (pass 54, Garry: gems and coins drawn under every 2.5D sprite):
// the gems and coins (PickupManager, see-through, drawn after every opaque thing) skip those pixels, so they lie under
// the creatures, the hero, the props and the structures wherever they overlap, in front of a painting's plane or not.
// Pass 72 (lane SPEC): a prop is scenery and writes 2 (SceneryStencil.VALUE), so a creature it hides is outlined
// (enemy_silhouette reads 2) while one hidden by another creature (1) is not; the gems read 0 (nothing painted).
// Pass 105 (lane LOOK): scenery writes 4 now (SceneryStencil.VALUE; the table is in StageStencil's header).
stencil_mode write, compare_always, 4;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;
uniform float mute : hint_range(0.0, 1.0) = 0.12;
uniform float face_camera : hint_range(0.0, 1.0) = 1.0;

varying vec2 v_uv;
varying vec3 v_roll;

// Pass 85 (lane WORLD): the natural tints, up to two parts per painting (PropField._set_tint_uniforms): hue window
// (lo, hi, sat_min, all hues), the hue shift and saturation factor ranges, the value factor range with the link and on.
uniform vec4 tint_hue_0 = vec4(0.0, 1.0, 0.1, 1.0);
uniform vec4 tint_hs_0 = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint_v_0 = vec4(1.0, 1.0, 0.5, 0.0);
uniform vec4 tint_hue_1 = vec4(0.0, 1.0, 0.1, 1.0);
uniform vec4 tint_hs_1 = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint_v_1 = vec4(1.0, 1.0, 0.5, 0.0);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// how much a pixel of hue h belongs to the window lo..hi (wrapping when lo > hi), soft by 0.03 at the edges
float in_window(float h, float lo, float hi) {
	float soft = 0.03;
	if (lo <= hi) {
		return smoothstep(lo - soft, lo, h) * (1.0 - smoothstep(hi, hi + soft, h));
	}
	return max(smoothstep(lo - soft, lo, h), 1.0 - smoothstep(hi, hi + soft, h));
}

vec3 tint_part(vec3 rgb, vec3 hsv, vec4 hue, vec4 hs, vec4 v, vec3 roll) {
	if (v.w < 0.5) {
		return rgb;
	}
	float w = hue.w > 0.5 ? 1.0 : in_window(hsv.x, hue.x, hue.y);
	// greys (outlines, bleached bone) and the darkest lines are left alone
	w *= smoothstep(hue.z * 0.5, hue.z, hsv.y) * smoothstep(0.06, 0.16, hsv.z);
	if (w <= 0.0) {
		return rgb;
	}
	float r1 = roll.x;
	float r2 = mix(roll.y, r1, v.z);
	float r3 = mix(roll.z, r1, v.z);
	vec3 t = vec3(fract(hsv.x + mix(hs.x, hs.y, r1)), clamp(hsv.y * mix(hs.z, hs.w, r2), 0.0, 1.0),
		clamp(hsv.z * mix(v.x, v.y, r3), 0.0, 1.0));
	return mix(rgb, hsv2rgb(t), w);
}

void vertex() {
	float flip = INSTANCE_CUSTOM.x;
	float sway = INSTANCE_CUSTOM.y;
	float phase = INSTANCE_CUSTOM.z;
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	v_uv = uv;
	float code = floor(INSTANCE_CUSTOM.w + 0.5);
	v_roll = vec3(mod(code, 12.0), mod(floor(code / 12.0), 12.0), floor(code / 144.0)) / 11.0;
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
	if (tint_v_0.w > 0.5) {
		vec3 hsv = rgb2hsv(c.rgb);
		vec3 rgb = tint_part(c.rgb, hsv, tint_hue_0, tint_hs_0, tint_v_0, v_roll);
		c.rgb = tint_v_1.w > 0.5 ? tint_part(rgb, rgb2hsv(rgb), tint_hue_1, tint_hs_1, tint_v_1, v_roll) : rgb;
	}
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(c.rgb, vec3(lum), mute) * (1.0 - mute * 0.3);
}
