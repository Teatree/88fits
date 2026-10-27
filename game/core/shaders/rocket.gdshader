// The Vulture Raider's rocket (pass 45, its look pass 48, made to pop in pass 109), one MultiMesh kind. The mesh carries its
// paint in vertex colours (art/props/enemy_rocket.glb, or Game._rocket_mesh_drawn): COLOR.rgb is the paint (a near-black
// body, dark red warhead band and fins, a steel nozzle) and the hot exhaust cup is marked by 1 - COLOR.a, or by its own
// bright orange paint when the file carries no alpha.
// Pass 109 (lane VFX; Garry: "It's still very easy to miss ... make it pop, all the time ... with a material on the 3d
// object of the projectile itself. I want it to be very very visible"): the material makes it a warning sign rather than a
// dark shape:
//  - unshaded and out of the fog: no sun, no shade, no haze, no stage filter (the body writes stencil 3,
//    StageStencil.CLEAR) can dim it; a fixed fake light keeps it round;
//  - hazard stripes: the black body wears diagonal black and hot-yellow bands (black and yellow read "danger" on any
//    ground: the yellow lights up against the blue Nightfall and the red Blood Moon, the black against the pale sand);
//  - a warning beacon: the nose cone and the red parts blink red and white at `blink_hz`;
//  - a bright rim (fresnel) round its edge, so it glows at its outline even where it is dark;
//  - next passes (Game._rocket_material): a hot glowing halo and a black edge round the whole rocket (rocket_outline:
//    two grown copies drawn behind it, so it reads on light sand and on dark ground alike) and an x-ray of it through
//    anything that stands in front of it (rocket_xray: it is never hidden in a crowd).
// INSTANCE_CUSTOM.x = heat 0..1: a loose rocket (its thrower is dead) blinks between its paint and white-hot at 8 Hz,
// then burns near 1 through its climb and dive. ProjectileManager writes it from glow[].
shader_type spatial;
render_mode cull_disabled, unshaded, fog_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.96, 0.9);
uniform vec3 exhaust : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 hazard : source_color = vec3(1.0, 0.84, 0.0);
uniform vec3 warhead : source_color = vec3(1.0, 0.07, 0.03);
uniform float blink_hz = 3.0;
// stripes per metre along the body, and how far round they lean
uniform float stripes = 7.5;
uniform float lean = 0.14;
// where the body starts behind the nose cone and ends at the tail (the model's own z, nose down -Z)
uniform float body_front = -0.24;
uniform float body_back = 0.4;
uniform float rim = 0.35;

varying float v_heat;
varying vec3 v_paint;
varying float v_mask;
varying vec3 v_local;

void vertex() {
	v_heat = clamp(INSTANCE_CUSTOM.x, 0.0, 1.0);
	v_paint = COLOR.rgb;
	v_local = VERTEX;
	// the exhaust: alpha 0 when the model says so, else its hot orange paint (a red channel near full and some green)
	float by_paint = clamp((COLOR.r - 0.6) * 4.0, 0.0, 1.0) * clamp((COLOR.g - 0.25) * 6.0, 0.0, 1.0);
	v_mask = max(1.0 - COLOR.a, by_paint);
}

void fragment() {
	float blink = step(0.5, fract(TIME * blink_hz));
	vec3 beacon = mix(warhead, vec3(1.0), blink);
	float lum = max(v_paint.r, max(v_paint.g, v_paint.b));
	float dark = 1.0 - step(0.13, lum);
	float radial = length(v_local.xy);
	// the body's hazard bands (the near-black paint between the nose cone and the tail, not the fins' outer half)
	float body = dark * step(body_front, v_local.z) * step(v_local.z, body_back) * (1.0 - step(0.2, radial));
	float ang = atan(v_local.y, v_local.x) / 6.28318;
	float stripe = step(0.5, fract((v_local.z + ang * lean) * stripes));
	vec3 col = v_paint;
	col = mix(col, mix(vec3(0.03), hazard, stripe), body);
	// the nose cone, the red band and ring: the blinking beacon; the fins' outer half a steady red
	float nose = dark * (1.0 - step(body_front, v_local.z));
	float red = step(0.2, v_paint.r) * (1.0 - step(0.15, v_paint.g)) * (1.0 - v_mask);
	float fin = dark * step(0.2, radial);
	col = mix(col, beacon, clamp(nose + red, 0.0, 1.0));
	col = mix(col, warhead * 0.8, fin);
	// a fixed light from above (it is unshaded: no sun can darken it), then the rim
	vec3 L = normalize((VIEW_MATRIX * vec4(0.3, 0.9, 0.35, 0.0)).xyz);
	float ndl = clamp(dot(NORMAL, L), 0.0, 1.0);
	col *= 0.7 + 0.45 * ndl;
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	col += vec3(1.0, 0.92, 0.6) * fres * rim;
	// the exhaust burns white-hot at its heart
	col = mix(col, mix(exhaust, hot, 0.55), v_mask);
	col = mix(col, hot, v_heat);
	ALBEDO = clamp(col, 0.0, 1.0);
}
