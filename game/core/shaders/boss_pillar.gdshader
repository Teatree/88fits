// The Brander's pillar of fire (pass 113, lane BOSS; BossPatternFx's shell "pillar"): an open cylinder round him while
// he is guarded through his Hellbrand Mandala, tongues of flame licking up it, drawn additive after the stage filter.
// `strength` 0..1 grows it up from the ground (the tell), holds it (the bullets) and gutters it out (spent). The height
// share comes from the mesh's own y (`height` m, the cylinder centred on its origin), the way round from its x and z; the
// far side glows at half strength so the column reads as flames round him, not a glass tube.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.42, 0.1, 1.0);
uniform float strength = 1.0;
uniform float height = 7.0;
uniform float tongues = 9.0;

varying float v_h;
varying float v_a;

void vertex() {
	v_h = clamp(VERTEX.y / max(height, 0.01) + 0.5, 0.0, 1.0);
	v_a = atan(VERTEX.z, VERTEX.x);
}

void fragment() {
	float h = v_h;
	float u = v_a;
	// flame tongues: each a column whose top rises and falls, drifting round
	float t1 = 0.5 + 0.5 * sin(u * tongues + TIME * 1.7 + 2.0 * sin(TIME * 0.9 + u * 3.0));
	float t2 = 0.5 + 0.5 * sin(u * (tongues * 2.0 + 1.0) - TIME * 2.6);
	float tongue = pow(0.65 * t1 + 0.35 * t2, 2.6);
	float top = strength * (0.12 + 0.88 * tongue);
	float a = smoothstep(top, top - 0.12, h);
	// licks of flame breaking off above the tongues
	float lick = step(0.82, fract(h * 3.0 - TIME * 1.8 + u * 0.5)) * smoothstep(top + 0.25, top, h) * step(top, h);
	a = max(a, lick * 0.6 * strength);
	// the core of each tongue brighter, its edges dimmer; brightest at the ground
	float core = 0.55 + 0.45 * tongue;
	vec3 c = mix(vec3(1.0, 0.92, 0.55), color.rgb, smoothstep(0.0, 0.45, h / max(top, 0.05)));
	c = mix(c, vec3(0.75, 0.1, 0.02), smoothstep(0.6, 1.0, h / max(top, 0.05)));
	float side = FRONT_FACING ? 1.0 : 0.35;
	// a glow at his feet whatever the tongues do
	float base = pow(1.0 - h, 3.0) * 0.5;
	ALBEDO = c * max(a * core, base) * side * strength * (1.0 - 0.5 * h) * 1.6;
}
