// Pass 83 (lane SCENE; Garry: "add a simple shadow underneath the environment 2.5d things ... barrels, signs, and
// structures too. Want them to feel like they are part of the world"): the scenery's ground shadows, one MultiMesh of
// flat metre quads (PropField: every painted prop, and the barrels, the signs and the structures through add_shadow),
// each a soft ellipse in the creatures' blob colour (blob_shadow.gdshader), its darkest at the middle and gone by the
// rim. Drawn see-through after every opaque thing at the creatures' shadow priority, so a creature, the hero or a pickup
// standing on one is drawn over it (the depth test hides the shadow behind an upright figure), the gems and coins after.
// INSTANCE_CUSTOM.r = strength (0..1); a lone MeshInstance3D uses `strength` (no custom data: r reads 0 there).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform float strength = 0.38;
uniform float use_custom = 1.0;
uniform vec3 tint : source_color = vec3(0.05, 0.03, 0.08);
// where the falloff starts and how round its shoulder is
uniform float inner = 0.45;
uniform float soft = 0.9;

varying float v_a;

void vertex() {
	v_a = use_custom > 0.5 ? INSTANCE_CUSTOM.r : strength;
}

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float k = 1.0 - smoothstep(inner, 1.0, r);
	ALBEDO = tint;
	ALPHA = pow(k, soft) * v_a;
}
