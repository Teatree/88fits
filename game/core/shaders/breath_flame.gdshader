// Pass 109 (lane VFX): one puff of the Dragon's Breath (core/systems/BreathFlames.gd: CPUParticles3D, so it runs the same on
// the phone's Compatibility renderer). A camera-facing quad (the particle billboard Godot's own particle material builds),
// a soft round blob whose edge flickers with a little value noise, eaten away from the edge as the puff ages, so a flame
// tongue breaks up into wisps of smoke. Its colour is the particle's (the emitter's colour ramp: white-hot at the mouth,
// orange, red, dark smoke); its hot middle burns brighter while it is young.
// INSTANCE_CUSTOM (CPUParticles3D): x = the puff's turn, y = its age 0..1, z = its own seed (anim offset, random 0..1).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float edge_noise = 0.6;
uniform float hot_core = 0.7;

varying float v_age;
varying float v_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.z;
	mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// the flickering edge: noise that drifts through the puff as it lives
	float n = vnoise(p * 2.6 + vec2(v_seed * 37.0, v_seed * 11.0 - v_age * 3.5));
	float shape = 1.0 - smoothstep(0.25, 1.0, r + (n - 0.5) * edge_noise);
	// eaten from the edge as it ages: a young tongue is full, an old one wisps
	float erode = v_age * 0.55;
	float a = smoothstep(erode, erode + 0.45, shape) * (1.0 - smoothstep(0.6, 1.0, r));
	vec3 col = COLOR.rgb * (1.0 + hot_core * (1.0 - r) * (1.0 - v_age));
	ALBEDO = clamp(col, 0.0, 1.0);
	ALPHA = clamp(COLOR.a * a, 0.0, 1.0);
}
