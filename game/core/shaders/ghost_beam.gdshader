// The Iron Horse's headlight beams (pass 119, lane LEGEND_A; core/systems/IronHorse.gd): a flat strip (UV.x across,
// UV.y 0 at the lamp .. 1 at its far end) of additive light, brightest at the lamp and soft at its sides. Drawn without
// the depth test: a beam laid over dunes would sink into them, and light washing over the creatures in its way is what
// a headlight does. fog_disabled (an additive effect takes the fog on top otherwise).
shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded, fog_disabled;

uniform vec3 color : source_color = vec3(0.45, 0.95, 0.82);
uniform float strength : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	float across = 1.0 - pow(abs(UV.x - 0.5) * 2.0, 2.0);
	float along = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.3);
	ALBEDO = color * strength;
	ALPHA = clamp(across * along * 0.45, 0.0, 1.0);
}
