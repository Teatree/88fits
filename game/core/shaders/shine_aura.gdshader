// The chest's shine (pass 33): light that says "cross the map for this", drawn additively on a few quads.
// mode 0: a sunburst behind the chest (camera-facing): rays that wheel slowly and twinkle one by one, a soft core
// mode 1: a tall soft beam standing on the chest (turns about Y only), seen from across the screen
// mode 2: a pool of light on the sand around it (the quad laid flat)
// mode 3: a sparkle, a four-point star (camera-facing)
// Billboard quads keep their own mesh offset: the beam's quad is built standing on its origin.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform int mode = 0;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.32, 1.0);
uniform float strength = 1.0;
uniform float rays = 12.0;
// mode 0: drawn this far behind the chest, so the chest stands in front of its own light
uniform float push_back = 0.35;
uniform float phase = 0.0;
// mode 2: the ground's rise per metre along x and z under the chest (pass 52), so the pool lies on a slope, not through it
uniform vec2 slope = vec2(0.0);

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 world;
	if (mode == 1) {
		vec3 flat_back = vec3(cam_back.x, 0.0, cam_back.z);
		flat_back = length(flat_back) > 0.001 ? normalize(flat_back) : vec3(0.0, 0.0, 1.0);
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), flat_back));
		world = origin + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	} else if (mode == 2) {
		float px = VERTEX.x * sx;
		float pz = VERTEX.y * sy;
		world = origin + vec3(px, 0.06 + slope.x * px + slope.y * pz, pz);
	} else {
		vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
		vec3 right = normalize(cross(up, cam_back));
		float back = mode == 0 ? push_back : -0.15;
		world = origin - cam_back * back + right * VERTEX.x * sx + up * VERTEX.y * sy;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float t = TIME + phase;
	float a = 0.0;
	if (mode == 0) {
		float r = length(p);
		float ang = atan(p.y, p.x) + t * 0.25;
		float k = ang * rays / 6.2831853;
		float id = floor(k);
		float f = fract(k) - 0.5;
		float tw = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(t * 2.1 + id * 2.7), 2.0);
		float ray = (1.0 - smoothstep(0.03, 0.13 + 0.08 * tw, abs(f))) * tw;
		float fade = 1.0 - smoothstep(0.12, 1.0, r);
		float core = exp(-r * r * 14.0);
		a = ray * fade * 0.8 + core * 0.55;
	} else if (mode == 1) {
		float x = abs(UV.x * 2.0 - 1.0);
		float y = 1.0 - UV.y;
		float core = exp(-x * x * 10.0);
		float shimmer = 0.8 + 0.2 * sin(t * 3.0 - y * 9.0);
		a = core * pow(1.0 - y, 1.3) * shimmer * 0.75;
	} else if (mode == 2) {
		float r = length(p);
		a = exp(-r * r * 3.2) * (1.0 - smoothstep(0.75, 1.0, r)) * (0.7 + 0.3 * sin(t * 3.0));
	} else {
		float star = max(0.0, 1.0 - abs(p.x) * 7.0 - abs(p.y) * 0.9) + max(0.0, 1.0 - abs(p.y) * 7.0 - abs(p.x) * 0.9);
		a = clamp(star, 0.0, 1.0) + exp(-dot(p, p) * 18.0);
	}
	ALBEDO = tint.rgb;
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
