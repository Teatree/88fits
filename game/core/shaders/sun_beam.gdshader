// The Sun Scepter's pillars of sunlight (pass 54, SunBeams): every pillar on the field is one instance of one MultiMesh,
// a tall soft beam standing on its spot and turning about Y only to face the camera, as shine_aura's mode 1 draws the
// chest's beam, with a white-hot thread down its middle. Drawn additively.
// INSTANCE COLOR:  rgb = the pillar's tint, a = its alpha (params.sun.beam_alpha)
// INSTANCE_CUSTOM: x = strength 0.. (it brightens over the warning and flashes as it lands), y = a phase for the shimmer
// The instance basis is scaled to (width, height, 1); the quad is built standing on its origin (QuadMesh 1 x 1 with its
// centre half a unit up).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, skip_vertex_transform, fog_disabled;

varying vec4 v_tint;
varying float v_strength;
varying float v_phase;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 flat_back = vec3(cam_back.x, 0.0, cam_back.z);
	flat_back = length(flat_back) > 0.001 ? normalize(flat_back) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), flat_back));
	vec3 world = origin + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
	v_tint = COLOR;
	v_strength = INSTANCE_CUSTOM.x;
	v_phase = INSTANCE_CUSTOM.y;
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float y = 1.0 - UV.y;
	float t = TIME + v_phase;
	float core = exp(-x * x * 10.0);
	float hot = exp(-x * x * 70.0);
	float shimmer = 0.8 + 0.2 * sin(t * 3.0 - y * 9.0);
	float fall = pow(1.0 - y, 1.3);
	float a = (core * 0.8 + hot * 0.45) * fall * shimmer;
	ALBEDO = mix(v_tint.rgb, vec3(1.0, 1.0, 0.92), hot * 0.65);
	ALPHA = clamp(a * v_strength * v_tint.a, 0.0, 1.0);
}
