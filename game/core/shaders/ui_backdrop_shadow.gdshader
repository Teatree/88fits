// Pass 124 (Garry: "Make the shadows under the environment assets ... a bit more complex than just a blob. Make them distinctly
// belonging to the assets, yet still quite blurred. Also the assets still hover over the shadows"): an object's own silhouette laid
// on the sand, away from the sun. The node's transform flips and skews the picture from its foot; here it is only the picture's
// alpha, blurred more the further it runs from the foot (a sharp contact, a soft far end) and fading out along its length.
// `region` is the part of the texture that holds the picture (a hero's strip frame; the whole texture for a prop), `foot_v` where
// its foot lies in it (0 top, 1 bottom). Twelve taps: only a few of these are ever on the screen, only on the menus.
shader_type canvas_item;

uniform vec4 shadow_color : source_color = vec4(0.10, 0.05, 0.14, 1.0);
uniform float strength = 0.6;
uniform vec4 region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float foot_v = 1.0;
uniform float blur_near = 0.006;
uniform float blur_far = 0.05;
// the prop's wind, as ui_backdrop_prop's
uniform float sway = 0.0;
uniform float speed = 1.3;
uniform float gust = 0.3;

const vec2 TAPS[12] = vec2[](vec2(1.0, 0.0), vec2(0.5, 0.866), vec2(-0.5, 0.866), vec2(-1.0, 0.0), vec2(-0.5, -0.866), vec2(0.5, -0.866),
	vec2(0.5, 0.0), vec2(0.25, 0.433), vec2(-0.25, 0.433), vec2(-0.5, 0.0), vec2(-0.25, -0.433), vec2(0.25, -0.433));

varying float v_a;

void vertex() {
	v_a = COLOR.a;
	if (sway != 0.0) {
		float ly = 1.0 - UV.y;
		float phase = MODEL_MATRIX[3].x * 0.0131 + MODEL_MATRIX[3].y * 0.0071;
		float g = 1.0 - gust + gust * sin(TIME * 0.37 + phase * 0.5);
		VERTEX.x += sin(TIME * speed + phase) * sway * g * ly * (-VERTEX.y);
	}
}

void fragment() {
	vec2 uv = (UV - region.xy) / max(region.zw, vec2(0.0001));
	float along = clamp((foot_v - uv.y) / max(foot_v, 0.001), 0.0, 1.0);
	float r = mix(blur_near, blur_far, along);
	float a = texture(TEXTURE, UV).a;
	for (int i = 0; i < 12; i++) {
		vec2 q = clamp(uv + TAPS[i] * vec2(r, r), vec2(0.0), vec2(1.0));
		a += texture(TEXTURE, region.xy + q * region.zw).a;
	}
	a /= 13.0;
	float fade = (1.0 - along) * (1.0 - along * 0.25);
	COLOR = vec4(shadow_color.rgb, shadow_color.a * strength * a * fade * v_a);
}
