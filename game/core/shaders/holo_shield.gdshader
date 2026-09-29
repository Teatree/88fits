// The shield power-up: a hollow holographic sphere around the hero. A fresnel rim, a scrolling hex grid and a scan
// band, alpha-blended (additive washed to white over the sand), pulsing; `hit` flashes it white for a moment when something bounces off.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform vec3 tint : source_color = vec3(0.25, 0.62, 1.0);
uniform float strength = 1.0;
uniform float hit = 0.0;

varying vec3 v_normal;
varying vec3 v_view;
varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
	v_normal = normalize(NORMAL);
	v_view = normalize((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	NORMAL = v_normal;
}

float hex(vec2 p) {
	// distance to the nearest hexagon edge on a hex lattice
	p = abs(p);
	float d = max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
	return d;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - abs(dot(n, -normalize(VIEW))), 2.2);
	// a hex grid in the sphere's own longitude/latitude, scrolling upwards
	float lon = atan(v_local.z, v_local.x) * 4.0;
	float lat = v_local.y * 5.0 - TIME * 0.6;
	vec2 g = vec2(lon, lat);
	vec2 cell = mod(g, 1.0) - 0.5;
	float h = hex(cell);
	float lines = smoothstep(0.42, 0.5, h);
	// a scan band sweeping down
	float band = smoothstep(0.08, 0.0, abs(fract(v_local.y * 0.5 - TIME * 0.7) - 0.5));
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0);
	float a = (0.14 + fres * 0.6 + lines * 0.3 + band * 0.22) * strength * pulse;
	vec3 col = mix(tint, vec3(1.0), hit * 0.9 + fres * 0.35 + lines * 0.3);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.85);
}
