// Dust puffs for Fx (pass 50, the Bull Beetle's charge): one camera-facing quad per puff, centred on its point, drawn as
// a soft cel cloud. A round body has its edge bitten by the flames' noise (art/fx/fire_noise.png), and the bite grows with
// age, so the puff frays and thins out instead of fading as a flat disc. A paler top and a shaded underside sit it in the
// game's look. (The pooled spheres it replaces read as eight-sided see-through bubbles.)
// INSTANCE_CUSTOM: x = age 0..1, y = seed 0..1
// INSTANCE COLOR:  rgb = colour, a = opacity
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// drawn a little towards the camera, so a puff low on the sand is not cut in half by the ground
uniform float toward_cam = 0.4;

varying vec4 v_col;
varying vec2 v_custom;

void vertex() {
	v_col = COLOR;
	v_custom = INSTANCE_CUSTOM.xy;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	vec3 world = origin + cam_back * toward_cam + (right * VERTEX.x + up * VERTEX.y) * s;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	float age = v_custom.x;
	float seed = v_custom.y;
	vec2 p = UV - 0.5;
	// 0 at the centre, 1 at the quad's edge
	float r = length(p) * 2.0;
	// two looks at the noise, placed by the seed and drifting slowly, so no two puffs are alike and a slow one churns
	float n1 = texture(noise_tex, UV * 0.6 + vec2(seed * 7.13, seed * 3.7 + TIME * 0.05)).r;
	float n2 = texture(noise_tex, UV * 1.3 + vec2(-seed * 5.31, seed * 1.9 + TIME * 0.09)).r;
	float n = n1 * 0.6 + n2 * 0.4;
	// the body: a disc whose edge the noise bites, deeper as it ages
	float v = (1.0 - r) - n * (0.35 + 0.35 * age) - age * 0.22;
	float a = smoothstep(0.0, 0.22, v);
	// lit from above: the top paler, the underside a shade darker (UV.y runs down the quad)
	float lit = 1.0 - smoothstep(-0.25, 0.15, p.y);
	vec3 col = mix(v_col.rgb * 0.84, mix(v_col.rgb, vec3(1.0), 0.28), lit);
	ALBEDO = col;
	ALPHA = a * v_col.a;
}
