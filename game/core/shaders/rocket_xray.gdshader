// Pass 109 (lane VFX): the Vulture Raider's rocket seen through whatever stands in front of it (the last next pass of
// core/shaders/rocket.gdshader, Game._rocket_material): drawn only where something nearer already covers the rocket (an
// inverted depth test, as the creatures' silhouettes behind scenery), a flat hot shape blinking with the nose, so a rocket
// inside a crowd of paintings is never lost. The rocket's own body and halo write stencil 3: the shape skips them
// (a fin in front of the body does not tint it), and the shape sits `lift` metres nearer the eye than the rocket, so its
// own surface never passes the inverted test.
shader_type spatial;
render_mode cull_back, unshaded, depth_test_inverted, depth_draw_never, blend_mix, fog_disabled;
stencil_mode read, compare_not_equal, 3;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.05, 0.8);
uniform float flash = 0.6;
uniform float blink_hz = 3.0;
uniform float lift = 0.08;

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz -= normalize(vp.xyz) * lift;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float blink = step(0.5, fract(TIME * blink_hz));
	ALBEDO = mix(color.rgb, vec3(1.0), flash * blink);
	ALPHA = color.a;
}
