// The Big Mouth's glow (pass 88; Garry: "when the attack is happening there is a mesh that appears that is as big as all
// of those together, and glows bright white as it used to, this will be our 'Glow' from now on"): the model's `Glow`
// egg filling the throat, unshaded, so it reads bright white whatever the light. LaserBeam.gd sets `color` (white at
// full, the throat's dark as it fades out while the jaw shuts) and `rim_color` / `rim` (the beam's colour as a faint
// edge, params.beam.throat.rim, scaled by how bright it burns).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.25, 0.7, 1.0);
uniform float rim = 0.0;

void fragment() {
	float edge = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = mix(color.rgb, rim_color.rgb, clamp(rim * edge * edge, 0.0, 1.0));
}
