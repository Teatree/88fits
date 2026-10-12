// Last Stand's look (pass 69, ui/LastStandFx.gd): the world drained to a cold blue-grey while time runs slow, and a red
// rim round the screen's edges that swells with a heartbeat. Drawn on its own CanvasLayer under the HUD, so the bars,
// the numbers and the screens keep their colours. Nothing like High Noon's warm gold flash.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// 0..1: how much of the look shows (it fades in and out)
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// 0..1: the heartbeat's swell right now
uniform float beat : hint_range(0.0, 1.0) = 0.0;
// the screen's width over its height (the rim is as wide at the top and bottom as at the sides)
uniform float aspect = 0.5625;
// the rim's width at rest, in screen widths, and how much a beat adds
uniform float rim_width = 0.085;
uniform float rim_swell = 0.045;
uniform vec3 cold = vec3(0.60, 0.70, 0.86);
uniform vec3 rim = vec3(0.74, 0.03, 0.06);

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// drained and cooled, a touch of contrast so the creatures still read
	vec3 grey = mix(vec3(0.5), vec3(l) * cold * 1.12, 1.1);
	vec3 graded = mix(c, clamp(grey, 0.0, 1.0), 0.88);
	// the rim: how far in from the nearest side, in screen widths; the corners deepest
	float dx = min(SCREEN_UV.x, 1.0 - SCREEN_UV.x);
	float dy = min(SCREEN_UV.y, 1.0 - SCREEN_UV.y) / max(aspect, 0.01);
	float w = rim_width + rim_swell * beat;
	float inside = smoothstep(0.0, w, dx) * smoothstep(0.0, w, dy);
	// the lead's review (pass 69): a thin rim the eye still sees through, so creatures coming in from the edges stay
	// visible for the two seconds; the beat swells it
	float edge = 1.0 - inside;
	float red = edge * edge * (0.3 + 0.5 * beat);
	vec3 outc = mix(graded, rim, clamp(red, 0.0, 0.62));
	COLOR = vec4(mix(c, outc, strength), 1.0);
}
