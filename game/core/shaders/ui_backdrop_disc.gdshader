// Pass 123 (lane BACKDROP): the hero's spot on the Royale main menu's backdrop (RoyaleBackdrop.gd, kind "title"): a warm
// pool of evening light on the sand, breathing with the sun. Garry on the first version: no white rings (the barrels'
// lesson), and shadows that match: so no rim and no dark patch by default (his shadow is RoyaleBackdrop's, one way with
// every other). One rect round the disc; the ellipse fills `disc` (its half axes in the rect's px) about the rect's middle.
shader_type canvas_item;

uniform vec2 rect_size = vec2(860.0, 300.0);
uniform vec2 disc = vec2(270.0, 57.0);
uniform vec4 sand_color : source_color = vec4(1.0, 0.8, 0.55, 0.1);
uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.78, 0.0);
uniform vec4 pool_color : source_color = vec4(1.0, 0.72, 0.42, 0.22);
uniform vec4 shade_color : source_color = vec4(0.24, 0.10, 0.16, 0.0);
uniform float rim_width = 0.045;
uniform float breath_period = 5.5;

void fragment() {
	vec2 p = UV * rect_size - rect_size * 0.5;
	float e = length(p / disc);
	float breath = 0.5 + 0.5 * sin(TIME * 6.2831853 / breath_period);
	// the pool: light spilling round the disc, a little wider when the sun breathes out
	float pool = exp(-max(e - 0.2, 0.0) * (1.9 - 0.2 * breath)) * smoothstep(1.75, 1.2, e);
	vec4 col = vec4(pool_color.rgb, pool_color.a * pool);
	// the disc: pale sand, its edge soft inside and a thin rim
	float inside = 1.0 - smoothstep(0.9, 1.0, e);
	col = mix(col, vec4(sand_color.rgb, 1.0), sand_color.a * inside * (1.0 - 0.35 * e * e));
	col.a = max(col.a, sand_color.a * inside);
	float rim = 1.0 - smoothstep(0.0, rim_width, abs(e - 1.0));
	col = mix(col, vec4(rim_color.rgb, 1.0), rim_color.a * rim);
	col.a = max(col.a, rim_color.a * rim);
	// where he stands: a soft darker patch, wider than deep
	float s = length(p / (disc * vec2(0.36, 0.42)));
	float shade = (1.0 - smoothstep(0.35, 1.0, s)) * shade_color.a;
	col.rgb = mix(col.rgb, shade_color.rgb, shade / max(col.a + shade, 0.001));
	col.a = clamp(col.a + shade, 0.0, 1.0);
	COLOR = col;
}
