// Pass 123 (lane BACKDROP): the sun's shine on the Royale menu backdrop (RoyaleBackdrop.gd), added over the painted plate:
// a warm glow that breathes slowly round the painted sun, faint rays turning behind it (only over the sky: `sky_mask`,
// the plate's sky as a small soft mask, white = sky), and a haze of light along the horizon. One rect over the top of
// the plate; nothing per frame but TIME.
shader_type canvas_item;
render_mode blend_add;

// in the rect's own px (its size in `rect_size`)
uniform vec2 rect_size = vec2(1080.0, 1400.0);
uniform vec2 sun_center = vec2(430.0, 770.0);
uniform float sun_radius = 118.0;
uniform float horizon_y = 1040.0;
uniform sampler2D sky_mask : hint_default_white, filter_linear;
uniform vec4 glow_color : source_color = vec4(1.0, 0.70, 0.36, 1.0);
uniform vec4 ray_color : source_color = vec4(1.0, 0.86, 0.58, 1.0);
uniform float glow_strength = 0.34;
uniform float ray_strength = 0.13;
uniform float haze_strength = 0.10;
// the breath (seconds a cycle) and the rays' turn (radians a second)
uniform float breath_period = 5.5;
uniform float ray_turn = 0.035;

void fragment() {
	vec2 p = UV * rect_size;
	vec2 v = p - sun_center;
	float d = length(v);
	float r = sun_radius;
	float breath = 0.5 + 0.5 * sin(TIME * 6.2831853 / breath_period);
	float sky = texture(sky_mask, UV).r;
	// the glow: a tight corona and a wide soft bloom, both breathing a little
	float corona = exp(-max(d - r * 0.92, 0.0) / (r * (0.32 + 0.06 * breath)));
	float bloom = exp(-max(d - r, 0.0) / (r * (2.4 + 0.5 * breath)));
	float glow = (corona * 0.55 + bloom * (0.55 + 0.25 * breath)) * glow_strength;
	// the rays: two fans at different counts turning opposite ways, soft, fading out with the distance, sky only
	float a = atan(v.y, v.x);
	float f1 = pow(0.5 + 0.5 * sin(a * 11.0 + TIME * ray_turn), 5.0);
	float f2 = pow(0.5 + 0.5 * sin(a * 17.0 - TIME * ray_turn * 1.6 + 1.7), 7.0);
	float rays = (f1 * 0.65 + f2 * 0.45) * smoothstep(r * 0.95, r * 1.35, d) * exp(-d / (r * 5.0));
	rays *= ray_strength * (0.8 + 0.2 * breath) * sky;
	// the haze: a warm band along the horizon, brightest under the sun
	float band = exp(-abs(p.y - horizon_y) / 70.0) * exp(-abs(v.x) / (r * 6.0));
	float haze = band * haze_strength * (0.85 + 0.15 * breath);
	vec3 col = glow_color.rgb * (glow * mix(0.55, 1.0, sky) + haze) + ray_color.rgb * rays;
	COLOR = vec4(col, 1.0);
}
