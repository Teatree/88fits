// Pass 109 (lane VFX): a grown copy round the Vulture Raider's rocket (a next pass of core/shaders/rocket.gdshader, set up
// by Game._rocket_material): the rocket's own mesh pushed out by `grow` metres from its long axis and past its nose and
// tail (by position only, so the copy has no cracks between the model's flat faces), drawn flat in `color` and pushed
// `depth_push` metres back along the line of sight, so the rocket itself always draws in front of it and only a band of
// it shows round the whole silhouette (whatever way the model's faces are wound). Two of them: a hot glowing halo
// (blinking with the nose's beacon, `flash`) and, a little wider, a black edge round that halo, so the rocket stands out
// on the pale sand (the black) and on the dark Nightfall and Blood Moon ground (the glow).
// It writes stencil 3 (StageStencil.CLEAR) as the body does: the stage filter never dims it.
shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 3;

uniform vec3 color : source_color = vec3(0.0);
uniform float grow = 0.06;
// the share of white the band takes while the beacon is lit (0 = steady)
uniform float flash = 0.0;
uniform float blink_hz = 3.0;
// the rocket's middle along its length (the model's z): the copy reaches past the nose and the tail from here
uniform float center_z = -0.08;
// metres back along the line of sight (behind the rocket's own far side)
uniform float depth_push = 0.6;

void vertex() {
	vec3 v = VERTEX;
	float rl = length(v.xy);
	if (rl > 0.0001) {
		v.xy += v.xy / rl * grow;
	}
	v.z += sign(v.z - center_z) * grow;
	vec4 vp = MODELVIEW_MATRIX * vec4(v, 1.0);
	vp.xyz += normalize(vp.xyz) * depth_push;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float blink = step(0.5, fract(TIME * blink_hz));
	ALBEDO = mix(color, vec3(1.0), flash * blink);
}
