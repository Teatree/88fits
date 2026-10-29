// A dizzy star over a spent boss (pass 113, lane BOSS; BossPatternFx: the Tumbleweed King's stars circling his crown):
// a camera-facing five-point star, yellow with an ink outline, opaque (cut out), writing stencil 3 so no stage filter dims
// it. `fade` shrinks it away.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 3;

uniform vec4 color : source_color = vec4(1.0, 0.88, 0.25, 1.0);
uniform vec4 ink : source_color = vec4(0.09, 0.05, 0.04, 1.0);
uniform float fade = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 / max(fade, 0.01);
	float a = atan(p.y, p.x) + 1.5708;
	float r = length(p);
	float edge = mix(0.42, 0.95, pow(0.5 + 0.5 * cos(a * 5.0), 1.6));
	if (r > edge) {
		discard;
	}
	ALBEDO = r > edge - 0.2 ? ink.rgb : mix(vec3(1.0, 0.98, 0.8), color.rgb, smoothstep(0.1, 0.6, r));
}
