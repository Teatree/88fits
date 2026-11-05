// The telephone line's wire (pass 126, lane DRESS; Garry: "The line moves with the wind a bit (more in Dust Bowl), the line
// isn't too much of an eye sore to interfere with the top down view"): every span in one mesh (TelephoneLine._build_wires), a
// ribbon that always faces the camera, about the same thin width on the screen at every zoom (`width_k` of the distance),
// its edges soft and the whole of it see-through, drawn before the stage's filter (TelephoneLine.WIRE_PRIORITY) so it dims
// with the ground under it. It writes no depth and no stencil: creatures' outlines and the gems never react to it.
// NORMAL = the wire's direction at the vertex; UV.x = the ribbon's side (-1, 1); COLOR.r = how far this point may swing (0 at
// a pole, 1 mid span), COLOR.g = the span's phase (0..1), COLOR.b = how far along the span.
// The sway needs no script: `wind` (1 = the normal sway, TelephoneLine.set_wind) only scales amplitudes, never a phase, so
// changing it is never a jump; above 1 a quicker flutter comes in as well.
shader_type spatial;
render_mode unshaded, skip_vertex_transform, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 wire_color : source_color = vec4(0.17, 0.135, 0.11, 1.0);
uniform float alpha = 0.5;
// the ribbon's width over the distance to the camera
uniform float width_k = 0.0016;
// the swing mid span at wind 1, metres, and its speed
uniform float sway = 0.07;
uniform float sway_speed = 1.1;
uniform float wind = 1.0;

varying float v_side;

void vertex() {
	vec3 along = normalize(NORMAL);
	vec3 across = normalize(cross(along, vec3(0.0, 1.0, 0.0)));
	float w = COLOR.r;
	float ph = COLOR.g * TAU;
	float t = TIME * sway_speed;
	// a long lazy swing and a smaller travelling one; a flutter only when the wind is up
	float slow = sin(t * 0.61 + ph) * 0.65 + sin(t + ph * 1.7 + COLOR.b * 3.0) * 0.35;
	float gust = sin(t * 3.1 + ph * 2.3 + COLOR.b * 7.0) * 0.3 * max(wind - 1.0, 0.0);
	vec3 p = VERTEX + (across * (slow + gust) + vec3(0.0, 0.3, 0.0) * slow) * sway * wind * w;
	vec3 view = (MODELVIEW_MATRIX * vec4(p, 1.0)).xyz;
	vec3 vt = normalize((MODELVIEW_MATRIX * vec4(along, 0.0)).xyz);
	vec3 side = normalize(cross(vt, view));
	v_side = UV.x;
	view += side * UV.x * 0.5 * width_k * max(-view.z, 0.1);
	VERTEX = view;
}

void fragment() {
	ALBEDO = wire_color.rgb;
	ALPHA = alpha * (1.0 - smoothstep(0.3, 1.0, abs(v_side)));
}
