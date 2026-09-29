// Flame tongues for Fx (pass 33): one camera-facing quad per flame, pivoting on its base, drawn as a stylised cel fire.
// The recipe is Minionsart's stylised fire (a flame mask eaten away by scrolling noise, the erosion growing with the
// particle's age; godotshaders.com "Stylized fire (3D)") with the hard toon bands of the papaya-games devlog "How to
// make a stylized fire shader": a pale gold heart, an orange body and a dark red rim, each edge one smoothstep wide,
// so the fire sits in the game's cel look instead of glowing like a photo.
// INSTANCE_CUSTOM: x = age 0..1, y = seed 0..1
// INSTANCE COLOR:  rgb = body colour, a = opacity
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 heart : source_color = vec3(1.0, 0.95, 0.62);
uniform vec3 rim : source_color = vec3(0.8, 0.14, 0.04);
uniform float scroll = 1.5;
// drawn a little towards the camera, so a flame on a creature burns in front of its sprite instead of being cut by it
uniform float toward_cam = 0.45;

varying vec4 v_col;
varying vec2 v_custom;

void vertex() {
	v_col = COLOR;
	v_custom = INSTANCE_CUSTOM.xy;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	vec3 world = origin + cam_back * toward_cam + right * VERTEX.x * sx + up * (VERTEX.y + 0.5) * sy;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	float age = v_custom.x;
	float seed = v_custom.y;
	float y = 1.0 - UV.y;   // 0 at the base, 1 at the tip
	float t = TIME * scroll;
	// two scrolls of the noise at different sizes and speeds, running up the flame
	float n1 = texture(noise_tex, vec2(UV.x * 0.55 + seed * 7.13, y * 0.5 - t * 0.55 + seed * 3.7)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 1.1 - seed * 5.31, y * 0.9 - t * 0.95)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	// the tongue sways, more towards its tip
	float x = (UV.x - 0.5) + (n1 - 0.5) * 0.3 * y;
	// the teardrop: a round base (a circle of radius 0.34, centred 0.34 up) drawn to a point at the top
	float body;
	if (y < 0.34) {
		body = 1.0 - length(vec2(x, y - 0.34)) / 0.34;
	} else {
		float hw = 0.34 * pow(max(1.0 - (y - 0.34) / 0.66, 0.0), 0.6);
		body = 1.0 - abs(x) / max(hw, 0.0001);
	}
	body *= 1.0 - 0.5 * y;
	// erosion: the noise eats the shape, harder towards the tip and as the flame grows old
	float v = body - n * (0.26 + 0.42 * y) - age * age * 0.7;
	float aa = max(fwidth(v), 0.002) * 1.5;
	float a_rim = smoothstep(0.03, 0.03 + aa, v);
	float a_body = smoothstep(0.2, 0.2 + aa, v);
	float a_heart = smoothstep(0.42, 0.42 + aa, v);
	vec3 col = mix(rim, v_col.rgb, a_body);
	col = mix(col, heart, a_heart);
	ALBEDO = col;
	ALPHA = a_rim * v_col.a;
}
