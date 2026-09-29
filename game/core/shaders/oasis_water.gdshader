// The oasis: a still pool with slow ripples, lighter and clearer towards the shore, a little emissive so it reads
// under the harsh sun. Drawn on a flat disc; `radius` is the disc's, for the shore fade.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 deep : source_color = vec3(0.03, 0.3, 0.52);
uniform vec3 shallow : source_color = vec3(0.24, 0.7, 0.82);
uniform float alpha : hint_range(0.0, 1.0) = 0.97;
uniform float radius = 6.5;

varying vec3 v_world;
varying vec2 v_local;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX.xz;
}

void fragment() {
	// three slow waves at odd angles and a faint ring from the centre: no grid, just water moving
	float r1 = sin(dot(v_world.xz, vec2(0.83, 0.55)) * 1.7 + TIME * 0.9);
	float r2 = sin(dot(v_world.xz, vec2(-0.4, 0.92)) * 2.6 - TIME * 1.3);
	float r3 = sin(dot(v_world.xz, vec2(0.3, -0.95)) * 4.1 + TIME * 0.6);
	float rings = sin(length(v_local) * 3.0 - TIME * 1.6);
	float w = 0.5 + 0.13 * r1 + 0.1 * r2 + 0.06 * r3 + 0.07 * rings;
	float edge = smoothstep(radius * 0.72, radius, length(v_local));
	vec3 col = mix(deep, shallow, w);
	col = mix(col, shallow, edge * 0.7);
	ALBEDO = col;
	ALPHA = alpha * (1.0 - edge * 0.3);
	ROUGHNESS = 0.12;
	METALLIC = 0.25;
	SPECULAR = 0.7;
	EMISSION = col * 0.12 + vec3(0.9, 0.95, 1.0) * smoothstep(0.8, 0.95, w) * 0.16;
}
