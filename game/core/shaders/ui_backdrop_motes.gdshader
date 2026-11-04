// Pass 123 (lane BACKDROP): dust motes drifting in the evening light on the Royale menu backdrop (RoyaleBackdrop.gd): a
// grid of cells sliding with the breeze, a speck in some of them that bobs and twinkles, brightest towards the sun's
// light. Added over the scene; one rect, nothing per frame but TIME.
shader_type canvas_item;
render_mode blend_add;

uniform vec2 rect_size = vec2(1080.0, 900.0);
// where the light comes from, in the rect's px, and how far it reaches
uniform vec2 light_center = vec2(430.0, 0.0);
uniform float light_reach = 900.0;
uniform vec4 mote_color : source_color = vec4(1.0, 0.86, 0.6, 1.0);
uniform float cell = 96.0;
uniform float density = 0.4;
uniform vec2 drift = vec2(14.0, -5.0);
uniform float strength = 0.95;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 q = p - drift * TIME;
	vec2 c = floor(q / cell);
	vec2 l = q - c * cell;
	float h = hash(c);
	float glow = 0.0;
	if (h < density) {
		float h2 = hash(c + 17.3);
		float h3 = hash(c + 41.9);
		vec2 at = vec2(0.15 + 0.7 * h2, 0.15 + 0.7 * h3) * cell;
		at += vec2(sin(TIME * (0.6 + h2) + h * 30.0), cos(TIME * (0.45 + h3) + h * 20.0)) * cell * 0.12;
		float size = 2.4 + 3.0 * h3;
		float d = length(l - at);
		float tw = 0.55 + 0.45 * sin(TIME * (1.1 + 2.0 * h2) + h * 50.0);
		glow = (1.0 - smoothstep(size * 0.4, size, d)) * tw;
	}
	float light = exp(-length(p - light_center) / light_reach);
	// fade in from the rect's edges
	float edge = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.85, UV.y);
	COLOR = vec4(mote_color.rgb * glow * light * edge * strength, 1.0);
}
