// A boss's barrier (pass 115, lane BOSS; core/systems/BossBarrier.gd lays BarrierMeshes' pieces round the ring, one
// MultiMesh a piece and a stretch of the ring). Lit by the scene like any prop, painted by vertex colours times `tint`;
// with `glow` 1 a piece is its own light instead (black albedo, its vertex colour a heat 0..1 turned into `glow_color`,
// white-hot at 1, breathing with `pulse`). It writes the structures' stencil (5: the stage filter tints it a little,
// a creature behind it shows its outline).
// The whole animation runs here, so a barrier of a few hundred pieces costs the CPU two numbers a frame:
//   INSTANCE_CUSTOM = (rise delay s, fall delay s, seed 0..1, the piece's origin height over the sand m)
//   the rise:  t_rise s since it began; each piece comes up out of the sand over rise_s s after its delay, from `depth` m
//              down, overshooting a little and wobbling as it settles
//   the fall:  t_fall s since it began (< 0: standing); after its delay each piece topples over about the fence line
//              (one way or the other by its seed) while it sinks and shrinks, over fall_s s; with `roll` 1 (the
//              tumbleweeds) it rolls away across the line instead, bounces once and sinks
// The ring's middle (`center`) gives each piece its fence line (the tangent through its foot).
shader_type spatial;
render_mode skip_vertex_transform, cull_back, depth_draw_opaque;
stencil_mode write, compare_always, 5;

uniform vec4 tint : source_color = vec4(1.0);
uniform float glow = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.54, 0.12, 1.0);
uniform float glow_energy = 1.5;
uniform float pulse = 1.0;
uniform vec3 center = vec3(0.0);
uniform float t_rise = 100.0;
uniform float t_fall = -1.0;
uniform float rise_s = 0.8;
uniform float fall_s = 1.0;
uniform float depth = 2.4;
uniform float roll = 0.0;

vec3 turn(vec3 v, vec3 axis, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

void vertex() {
	vec4 k = INSTANCE_CUSTOM;
	vec3 o = MODEL_MATRIX[3].xyz;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 foot = vec3(o.x, o.y - k.w, o.z);
	vec2 r2 = o.xz - center.xz;
	vec3 outd = normalize(vec3(r2.x, 0.0, r2.y) + vec3(0.00001, 0.0, 0.0));
	vec3 tang = vec3(-outd.z, 0.0, outd.x);
	// the rise: out of the sand, overshooting a little (an ease-out-back), a wobble about the fence line as it settles
	float u = clamp((t_rise - k.x) / max(rise_s, 0.01), 0.0, 1.0);
	float um = u - 1.0;
	float e = 1.0 + 2.2 * um * um * um + 1.2 * um * um;
	float wob = sin(u * 10.0 + k.z * 6.2832) * (1.0 - u) * 0.16;
	w = foot + turn(w - foot, tang, wob);
	n = turn(n, tang, wob);
	w.y -= depth * (1.0 - e);
	// the fall
	if (t_fall >= 0.0) {
		float f = clamp((t_fall - k.y) / max(fall_s, 0.01), 0.0, 1.0);
		float sgn = k.z < 0.5 ? -1.0 : 1.0;
		if (roll > 0.5) {
			// rolls away across the line, spinning on itself, one bounce, then down into the sand
			float dist = sgn * (1.6 + 2.2 * fract(k.z * 3.71)) * f;
			float spin = -dist / 0.6;
			w = o + turn(w - o, tang, spin);
			n = turn(n, tang, spin);
			w += outd * dist;
			w.y += sin(f * 3.14159) * 0.45;
			w.y -= depth * smoothstep(0.55, 1.0, f);
		} else {
			// topples over about the fence line (a little askew), faster and faster, sinking as it goes
			vec3 axis = normalize(tang + vec3(sin(k.z * 41.0), 0.0, cos(k.z * 41.0)) * 0.35);
			float ang = sgn * (1.2 + 0.5 * fract(k.z * 7.3)) * f * f;
			w = foot + turn(w - foot, axis, ang);
			n = turn(n, axis, ang);
			w.y -= depth * smoothstep(0.3, 1.0, f);
		}
		w = foot + (w - foot) * (1.0 - 0.45 * smoothstep(0.45, 1.0, f));
	}
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}

// (the pieces' paint is sRGB, as Color8 wrote it; the lighting is linear)
vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	if (glow > 0.5) {
		float h = COLOR.r;
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = mix(glow_color.rgb * (0.35 + 0.65 * h), vec3(1.0, 0.94, 0.78), smoothstep(0.9, 1.0, h) * 0.55) * glow_energy * pulse;
	} else {
		ALBEDO = to_linear(COLOR.rgb) * tint.rgb;
		ROUGHNESS = 0.82;
		SPECULAR = 0.3;
	}
}
