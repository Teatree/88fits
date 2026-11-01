// The Iron Horse's round lights (pass 119, lane LEGEND_A; core/systems/IronHorse.gd): a glow turned to the camera (the
// headlight, and the glimmer at the screen's edge where the train will come from), a hot white middle in `color`
// falling off to nothing at the quad's edge. Additive, fog_disabled (an additive effect would take the scene's fog on
// top: pass 113's lesson), no depth writes. The beams on the ground are ghost_beam.gdshader.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform vec3 color : source_color = vec3(0.7, 1.0, 0.92);
uniform float strength : hint_range(0.0, 4.0) = 1.0;

void vertex() {
	// a camera-facing quad at the node's origin, its scale kept
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 c = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(c + vec3(VERTEX.x * sx, VERTEX.y * sy, 0.0), 1.0);
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = exp(-d * d * 18.0);
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = mix(color, vec3(1.0), clamp(core, 0.0, 1.0)) * strength;
	ALPHA = clamp(core * 1.2 + halo * 0.55, 0.0, 1.0);
}
