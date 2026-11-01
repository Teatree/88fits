// The Iron Horse's ghost train (pass 119, lane LEGEND_A; core/systems/IronHorse.gd): one car of
// art/props/iron_horse.glb (tools/blender_iron_horse.py: the Railway Kit's locomotive, a tender, a coach) drawn as a
// see-through spectral blue-green body with a pale fresnel rim, faint bands drifting up it and a flicker, its windows
// and lamp glass glowing. Its running gear moves here, so a car is one mesh and one draw call:
//   UV.x  the part's kind: 0 body, 1 wheel, 2 coupling rod, 3 connecting rod, 4 crosshead, 5 a glowing window
//   UV.y  along a connecting rod (stored flipped by glTF: 1 - f, f 0 at the crosshead end, 1 at the crank end)
//   UV2   a wheel's hub (along, up) in the car's metres, a rod's crank pin rest offset from its hub (glTF flips v: up is
//         1 - UV2.y). A wheel turns by travel / its hub height (its rolling radius); the rods ride the crank pin round
//         at travel / drive_r; a crosshead slides with the pin's along motion only.
// Blend mix with depth writes (depth_draw_always): one see-through layer over the world, never the car's far side
// through its near side; unshaded (a soft light from above is worked out here, so the low-poly facets still read) and
// fog_disabled (a ghost is never fogged over).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, unshaded, fog_disabled;

uniform float travel = 0.0;
uniform float drive_r = 0.7;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 body_color : source_color = vec3(0.16, 0.6, 0.56);
uniform vec3 rim_color : source_color = vec3(0.86, 1.0, 0.97);
uniform vec3 glow_color : source_color = vec3(1.0, 0.97, 0.72);
uniform float body_alpha = 0.52;
// the spectral wisps: how much a drifting noise eats into the body, and how fast it streams back along the car
uniform float wisp = 0.45;
uniform vec3 deep_color : source_color = vec3(0.05, 0.36, 0.38);
uniform float rim_alpha = 0.97;
uniform float seed = 0.0;

varying float v_kind;
varying float v_h;
varying vec3 v_world;
varying vec3 v_local;

// (along, up) turned by `a` the way a wheel rolls forward: its top goes forward
float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n00 = mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x);
	float n10 = mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x);
	float n01 = mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x);
	float n11 = mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x);
	return mix(mix(n00, n10, f.y), mix(n01, n11, f.y), f.z);
}

vec2 roll(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c + p.y * s, -p.x * s + p.y * c);
}

void vertex() {
	float kind = floor(UV.x + 0.5);
	v_kind = kind;
	vec2 hub = vec2(UV2.x, 1.0 - UV2.y);
	if (kind > 0.5 && kind < 1.5) {
		float a = travel / max(hub.y, 0.05);
		vec2 q = hub + roll(vec2(VERTEX.z, VERTEX.y) - hub, a);
		VERTEX.z = q.x;
		VERTEX.y = q.y;
		vec2 n = roll(vec2(NORMAL.z, NORMAL.y), a);
		NORMAL.z = n.x;
		NORMAL.y = n.y;
	} else if (kind > 1.5 && kind < 4.5) {
		vec2 d = roll(hub, travel / drive_r) - hub;
		if (kind > 3.5) {
			d.y = 0.0;
		} else if (kind > 2.5) {
			d.y *= clamp(1.0 - UV.y, 0.0, 1.0);
		}
		VERTEX.z += d.x;
		VERTEX.y += d.y;
	}
	v_h = VERTEX.y;
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	fres = fres * fres * 1.15;
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = 0.6 + 0.55 * clamp(dot(nw, normalize(vec3(-0.4, 0.85, 0.35))), 0.0, 1.0);
	float band = 0.86 + 0.14 * sin(v_world.y * 8.0 - TIME * 6.0 + (v_world.x + v_world.z) * 0.6);
	float flick = 0.9 + 0.1 * sin(TIME * 23.0 + seed * 7.0) * sin(TIME * 7.3 + seed);
	// deep at its wheels, pale towards its roof
	vec3 body = mix(deep_color, body_color, smoothstep(0.2, 3.4, v_h)) * lit;
	vec3 col = mix(body, rim_color, clamp(fres, 0.0, 1.0));
	// smoky wisps streaming back along the car (its own z is forward): the body thins in drifting patches
	float n = vnoise3(v_local * vec3(1.3, 1.6, 0.9) + vec3(0.0, -TIME * 0.6, TIME * 2.4 + seed));
	float smoke = 1.0 - wisp * smoothstep(0.35, 0.85, n);
	float a = mix(body_alpha * smoke, rim_alpha, clamp(fres, 0.0, 1.0)) * band * flick;
	// its wheels fade into the rails
	a *= mix(0.55, 1.0, smoothstep(0.0, 0.6, v_h));
	if (v_kind > 4.5) {
		col = glow_color;
		a = 0.92 * flick;
	}
	ALBEDO = col;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
