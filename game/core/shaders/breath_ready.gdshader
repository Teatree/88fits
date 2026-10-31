// Pass 116 (lane RESULTS): the Dragon's Breath's ready sign (core/systems/BreathReady.gd): a small spiky ring of flame
// that collapses into the hero's face when the next breath is ready, a white spark where it lands. A camera-facing quad,
// see-through (drawn after the stage filter, so Nightfall and Blood Moon leave its colours alone), on top of the hero.
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform float phase = 0.0;      // 0..1 over the sign's life
uniform float spikes = 9.0;
uniform vec4 hot : source_color = vec4(1.0, 0.82, 0.3, 1.0);
uniform vec4 rim : source_color = vec4(0.85, 0.25, 0.05, 1.0);
uniform vec4 ink : source_color = vec4(0.14, 0.08, 0.05, 1.0);

void vertex() {
	// billboard: the quad faces the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// the collapse: the ring from 0.95 of the quad to nothing, easing in (slow, then fast into him), turning as it goes
	float col_t = clamp(phase / 0.8, 0.0, 1.0);
	float R = 0.95 * (1.0 - col_t * col_t);
	float spin = col_t * 2.2;
	float sp = pow(max(cos(spikes * (a + spin)), 0.0), 3.0);
	float edge = R * (1.0 + 0.32 * sp);
	float w = 0.07 + 0.05 * (1.0 - col_t);
	float d = abs(r - edge * 0.86);
	float body = 1.0 - smoothstep(w * 0.55, w * 0.75, d);
	float outline = 1.0 - smoothstep(w * 0.75, w, d);
	vec3 c = mix(ink.rgb, mix(rim.rgb, hot.rgb, 1.0 - clamp(d / (w * 0.6), 0.0, 1.0)), body);
	float alpha = outline * smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.78, 0.82, phase));
	// the spark where it lands: a white-hot dot that pops and fades
	float sp_t = clamp((phase - 0.75) / 0.25, 0.0, 1.0);
	float spark = (1.0 - smoothstep(0.08, 0.08 + 0.22 * sp_t, r)) * (1.0 - sp_t) * step(0.0001, sp_t);
	c = mix(c, vec3(1.0, 0.97, 0.85), spark);
	alpha = max(alpha, spark);
	ALBEDO = c;
	ALPHA = alpha;
}
