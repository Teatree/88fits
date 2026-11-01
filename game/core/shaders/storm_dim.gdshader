// Personal Storm's overcast (pass 119, lane LEGEND_A; core/systems/PersonalStorm.gd): a full-screen rect on a canvas
// layer under the HUD that multiplies the world by a cool, dim tint while the clouds are in: heavier at the screen's
// edges, with slow cloud shapes drifting through it, sweeping in from upwind as `cover_in` grows and on downwind as
// `cover_out` grows (the ground's cloud shadows' front, storm_shadow.gdshader; `wind` in screen axes: x right, y down). `flash` lifts it for a
// moment when the lightning strikes (a multiply can only darken: a strike lightens the overcast back towards none).
shader_type canvas_item;
render_mode blend_mul;

uniform float cover_in : hint_range(0.0, 1.0) = 0.0;
uniform float cover_out : hint_range(0.0, 1.0) = 0.0;
uniform vec2 wind = vec2(1.0, 0.4);
uniform float dim : hint_range(0.0, 1.0) = 0.35;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec2 drift = vec2(0.03, 0.012);
uniform vec3 tint : source_color = vec3(0.55, 0.6, 0.8);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// the screen is tall: distance from a point a little below the middle (where the hero stands), squeezed upright
	float v = length((uv - vec2(0.5, 0.56)) * vec2(1.0, 0.62)) * 2.0;
	// one octave: it covers the whole screen on a phone (the ground's cloud shadows carry the detail)
	float n = vnoise(uv * vec2(4.0, 7.0) + drift * TIME * 10.0);
	// the front sweeps across the screen from upwind, then its trailing edge after it
	vec2 wd = normalize(wind);
	float along = dot(uv - vec2(0.5), wd) * 2.0 + (n - 0.5) * 0.5;
	float lead = -1.4 + cover_in * 2.9;
	float trail = -1.4 + cover_out * 2.9;
	float swept = (1.0 - smoothstep(lead - 0.35, lead, along)) * smoothstep(trail - 0.35, trail, along);
	float k = dim * swept * (0.6 + 0.4 * smoothstep(0.2, 1.0, v)) * (0.8 + 0.4 * n);
	k *= 1.0 - flash * 0.75;
	COLOR = vec4(mix(vec3(1.0), tint, clamp(k * 1.6, 0.0, 1.0)), 1.0);
}
