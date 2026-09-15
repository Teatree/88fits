// Soft dark disc under characters. Used on a flat QuadMesh via MultiMesh or MeshInstance3D.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform float strength = 0.45;

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float a = (1.0 - smoothstep(0.55, 1.0, r)) * strength;
	ALBEDO = vec3(0.05, 0.03, 0.08);
	ALPHA = a;
}
