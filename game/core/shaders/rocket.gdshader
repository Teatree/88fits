// The Vulture Raider's rocket (pass 45, its look pass 48), one MultiMesh kind. The mesh carries its paint in vertex
// colours (art/props/enemy_rocket.glb, or Game._rocket_mesh_drawn): COLOR.rgb is the paint (a near-black body, dark red
// warhead band and fins, a steel nozzle) and the hot exhaust cup is marked by 1 - COLOR.a, or by its own bright orange
// paint when the file carries no alpha. Only that cup glows, so the rocket reads dark on the sand.
// INSTANCE_CUSTOM.x = heat 0..1: a loose rocket (its thrower is dead) blinks between its paint and white-hot at 8 Hz,
// then burns near 1 through its climb and dive. ProjectileManager writes it from glow[].
shader_type spatial;
render_mode cull_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.96, 0.9);
uniform vec3 exhaust : source_color = vec3(1.0, 0.45, 0.12);
uniform float energy = 2.4;

varying float v_heat;
varying vec3 v_paint;
varying float v_mask;

void vertex() {
	v_heat = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	v_paint = COLOR.rgb;
	// the exhaust: alpha 0 when the model says so, else its hot orange paint (a red channel near full and some green)
	float by_paint = clamp((COLOR.r - 0.6) * 4.0, 0.0, 1.0) * clamp((COLOR.g - 0.25) * 6.0, 0.0, 1.0);
	v_mask = max(1.0 - COLOR.a, by_paint);
}

void fragment() {
	ALBEDO = mix(v_paint, hot, v_heat);
	EMISSION = exhaust * v_mask * energy + hot * v_heat * (energy + 5.0 * v_heat);
	ROUGHNESS = 0.75;
	METALLIC = 0.0;
}
