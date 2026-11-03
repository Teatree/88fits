// The Royale rays (pass 122, lane UIKIT_B; README section 3: `repeating-conic-gradient(from 0deg, c 0 8deg,
// transparent 8deg 20deg)` masked to a disc, one turn in 30 s): `on_deg` lit of every `period_deg` round the middle of
// the Control's rect, in `color` (ffe696 at .35 by default), whole inside `mask_in` of the disc's radius and gone by
// `mask_out`, turning clockwise once every `turn_s` seconds on TIME (so it keeps turning while the run is paused, as
// the level-up and the chest are). Drawn with draw_rect in white over a square rect; `size` is its side in px (the ray
// edges are anti-aliased by the pixel's share of the angle). Behind a pressed card's item and behind the chest's and
// the mutation offer's frames (WPlate.rays).
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float size = 400.0;
uniform vec4 color : source_color = vec4(1.0, 0.902, 0.588, 0.35);
uniform float on_deg = 8.0;
uniform float period_deg = 20.0;
uniform float mask_in = 0.3;
uniform float mask_out = 0.7;
uniform float turn_s = 30.0;
uniform float phase = 0.0;
uniform float alpha = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.x, -p.y) + phase;
	if (turn_s > 0.0) {
		a += TIME / turn_s * 6.2831853;
	}
	float period = radians(max(period_deg, 0.01));
	float f = mod(a, period);
	float on = radians(on_deg);
	// the pixel's share of the angle at this radius, for an edge a pixel wide
	float px = 1.0 / max(r * size * 0.5, 1.0);
	float lit = smoothstep(-px, px, f) * (1.0 - smoothstep(on - px, on + px, f));
	float mask = 1.0 - smoothstep(mask_in, mask_out, r);
	float strength = lit * mask * color.a * alpha;
	COLOR = vec4(color.rgb, strength) * COLOR;
}
