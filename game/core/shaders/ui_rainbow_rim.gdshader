// The Evolved rim on its own (pass 122, lane UIKIT_B; README section 1: a rainbow conic rim with a soft white glow): a
// ring of `rim_px` round a rounded box (or a disc, `shape` 1) `inset` px inside the Control's rect less `pad` on every
// side, swept clockwise from the top through `rainbow[8]` (ff4b3e, ffb13b, ffe13b, 5fd13c, 2fb8ff, 8a5cff, ff4bd1 and
// back), the glow outside it over `glow_px` in `glow_color`, nothing inside the ring. Drawn with draw_rect in white
// over the rect (`size` in px). The item frame (WPlate) paints its rainbow inside ui_radial_fill (rim_mode 2), so its
// rim and its face share one pass with no seam; this one rings anything else (a hero tile, a chest, a sheet sample).
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 size = vec2(100.0, 100.0);
uniform float pad = 0.0;
uniform float inset = 4.0;
uniform float rim_px = 7.0;
uniform float radius = 6.0;
uniform int shape = 0;
uniform vec4 rainbow[8] : source_color;
uniform float glow_px = 26.0;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
uniform float turn = 0.0;
uniform float alpha = 1.0;

float sd(vec2 p, vec2 h, float r) {
	if (shape == 1) {
		return length(p) - min(h.x, h.y);
	}
	vec2 q = abs(p) - h + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float inside(float d) {
	return 1.0 - smoothstep(-0.5, 0.5, d);
}

void fragment() {
	vec2 px = UV * size;
	vec2 fsize = size - vec2(2.0 * pad);
	vec2 c = vec2(pad) + fsize * 0.5;
	vec2 p = px - c;
	vec2 half = fsize * 0.5 - vec2(inset);
	float d_out = sd(p, half, radius);
	float d_in = sd(p, half - vec2(rim_px), max(radius - rim_px, 0.0));
	vec4 col = vec4(0.0);
	if (glow_px > 0.0 && glow_color.a > 0.0) {
		float g = 1.0 - smoothstep(0.0, glow_px, max(d_out, 0.0));
		col = vec4(glow_color.rgb, glow_color.a * g * g);
	}
	float ring = inside(d_out) * (1.0 - inside(d_in));
	float a = atan(p.x, -p.y) + turn;
	float t = fract(a / 6.2831853);
	float seg = t * 7.0;
	int k = int(floor(seg));
	vec4 rimc = mix(rainbow[k], rainbow[min(k + 1, 7)], fract(seg));
	col = mix(col, rimc, ring);
	col.a *= alpha;
	COLOR = col * COLOR;
}
