// The thrust's tip flash (pass 136, lane MELEE; core/systems/MeleeFx.gd): a camera-facing star where the point lands, a
// round glow with four long thin rays (two along the thrust's line on screen, `rot`) and four short diagonal ones,
// popping out and gone over `t` 0..1. One quad, VERTEX.xy -1..1, `size` metres across its half.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled, shadows_disabled, skip_vertex_transform;

uniform float t = 0.0;
uniform float size = 0.8;
uniform float rot = 0.0;
uniform vec4 col : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(1.0);

varying vec2 v_p;

void vertex() {
	v_p = VERTEX.xy;
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float grow = mix(0.45, 1.15, 1.0 - pow(1.0 - clamp(t, 0.0, 1.0), 3.0));
	VERTEX = c + vec3(VERTEX.xy * size * grow, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void over(inout vec3 c, inout float a, vec3 lc, float la) {
	la = clamp(la, 0.0, 1.0);
	c = lc * la + c * (1.0 - la);
	a = la + a * (1.0 - la);
}

float ray(vec2 p, float len, float w) {
	float x = abs(p.x) / len;
	if (x > 1.0) {
		return 0.0;
	}
	return (1.0 - smoothstep(w * (1.0 - x) * 0.4, w * (1.0 - x), abs(p.y))) * (1.0 - x);
}

void fragment() {
	float cs = cos(rot);
	float sn = sin(rot);
	vec2 p = vec2(cs * v_p.x - sn * v_p.y, sn * v_p.x + cs * v_p.y);
	float life = clamp(t, 0.0, 1.0);
	float k = 1.0 - smoothstep(0.25, 1.0, life);
	float d = length(p);
	vec3 c = vec3(0.0);
	float a = 0.0;
	float glow = exp(-d * d * 9.0);
	over(c, a, col.rgb, glow * 0.85 * k);
	float rays = max(ray(p, 1.0, 0.16), ray(vec2(p.y, p.x), 0.62, 0.12));
	vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	rays = max(rays, 0.7 * max(ray(q, 0.42, 0.1), ray(vec2(q.y, q.x), 0.42, 0.1)));
	over(c, a, mix(col.rgb, core_col.rgb, 0.5), rays * k);
	float core = exp(-d * d * 60.0);
	over(c, a, core_col.rgb, core * k);
	if (a < 0.004) {
		discard;
	}
	ALBEDO = c / max(a, 0.0001);
	ALPHA = a;
}
