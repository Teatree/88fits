// A black hole (pass 35: the Singularity's shot and the Vortex's core): black where it faces the camera, a violet rim
// round its edge.
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(0.78, 0.38, 1.0, 1.0);
uniform float rim_power = 2.2;
uniform float energy = 2.2;

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * f * energy;
}
