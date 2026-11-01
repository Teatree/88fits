// The Iron Horse's ghost rails (pass 119, lane LEGEND_A; core/systems/IronHorse.gd builds the mesh, laid on the sand
// along the locked line): sleepers and two rails, see-through spectral blue-green. UV.x is the metres along the line
// from its back end (where the train comes from), UV.y 0 on a sleeper and 1 on a rail.
//   build_s  the front of the wave that lays them, running from the back end to the front: behind it a sleeper has risen
//            out of the sand and a rail is drawn; a bright crest rides the front
//   gone_s   the front of the wave that takes them away after the train's tail: behind it they sink and fade
//   glow     0..1, brighter as the train comes
// No depth writes, blend mix, unshaded, fog_disabled.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

uniform float build_s = 0.0;
uniform float build_w = 5.0;
uniform float gone_s = -1000.0;
uniform float gone_w = 3.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sleeper_color : source_color = vec3(0.26, 0.70, 0.62);
uniform vec3 rail_color : source_color = vec3(0.72, 1.0, 0.94);

varying float v_s;
varying float v_rail;
varying float v_up;
varying float v_keep;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	float s = UV.x;
	v_s = s;
	v_rail = UV.y;
	// laid: 1 well behind the build front, 0 ahead of it
	float up = clamp((build_s - s) / build_w, 0.0, 1.0);
	up = up * up * (3.0 - 2.0 * up);
	// kept: 0 well behind the dissolve front, 1 ahead of it
	float keep = clamp((s - gone_s) / gone_w + 1.0, 0.0, 1.0);
	v_up = up;
	v_keep = keep;
	// a sleeper rises out of the sand as the wave passes, and sinks back when it goes; a rail lifts a little
	VERTEX.y -= (1.0 - up) * mix(0.32, 0.12, v_rail) + (1.0 - keep) * 0.22;
}

void fragment() {
	vec3 c = mix(sleeper_color, rail_color, v_rail);
	// the crest riding the build front and the train's glow
	float crest = exp(-pow((v_s - build_s + build_w * 0.35) / 1.4, 2.0)) * step(v_s, build_s + 0.5);
	c = mix(c, vec3(1.0), clamp(crest * 0.6 + glow * 0.3 * v_rail, 0.0, 1.0));
	// each sleeper shimmers on its own
	float sh = 0.85 + 0.15 * sin(TIME * 9.0 + hash(floor(v_s / 0.75)) * 40.0);
	float a = v_up * v_keep * mix(0.5, 0.85, v_rail) * sh * (0.8 + 0.2 * glow) + crest * 0.35 * v_up;
	ALBEDO = c;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
