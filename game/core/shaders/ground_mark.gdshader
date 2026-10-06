// Ground marks drawn from ready-made shapes (pass 33.8): every ring, disc, cone, line and spill is one instance of a
// MultiMesh whose unit mesh is laid over the terrain here, vertex by vertex, from the map's height grid (the same grid
// and the same bilinear step as MapBase.height_at, so a mark sits on the dunes exactly as the old per-mark meshes did).
// The instance transform only places it (its origin is the mark's centre, or a line's start).
//   shape 0, polar (rings, discs, cones): UV.x = 0 inner .. 1 outer edge, UV.y = 0..1 round the sweep;
//            INSTANCE_CUSTOM = inner radius, outer radius, start angle, sweep (radians)
//   shape 1, strip (lines):   UV.x = 0..1 along, UV.y = -0.5..0.5 across; INSTANCE_CUSTOM = dir x, dir z, length, width
//   shape 2, spill (blobs):   UV.x = 0 centre .. 1 rim, UV.y = 0..1 round; INSTANCE_CUSTOM.x = radius, .y = seed
//            (the lobed rim of Telegraphs.draped_blob); colour runs from inner_color to outer_color by UV.x squared
// COLOR (the instance colour): rgb tint, a = alpha, taken as a StandardMaterial3D albedo would be.
// The basis is the identity, except for a mark floated over the ground (pass 54, Telegraphs._lift_basis: the ripples on
// the lake): its y column's length is 1 + the lift in metres.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform;

uniform int shape = 0;
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform float lift = 0.1;
uniform vec4 inner_color = vec4(1.0);
uniform vec4 outer_color = vec4(1.0);

varying vec4 v_color;

float ground(vec2 p) {
	if (grid_n < 2) {
		return 0.0;
	}
	float top = float(grid_n - 1) - 0.001;
	float fx = clamp((p.x + half_size) * resolution, 0.0, top);
	float fz = clamp((p.y + half_size) * resolution, 0.0, top);
	int ix = int(fx);
	int iz = int(fz);
	float tx = fx - float(ix);
	float tz = fz - float(iz);
	float h00 = texelFetch(heights, ivec2(ix, iz), 0).r;
	float h10 = texelFetch(heights, ivec2(ix + 1, iz), 0).r;
	float h01 = texelFetch(heights, ivec2(ix, iz + 1), 0).r;
	float h11 = texelFetch(heights, ivec2(ix + 1, iz + 1), 0).r;
	return mix(mix(h00, h10, tx), mix(h01, h11, tx), tz);
}

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec4 k = INSTANCE_CUSTOM;
	vec2 p;
	v_color = COLOR;
	if (shape == 1) {
		vec2 d = k.xy;
		p = c.xz + d * (UV.x * k.z) + vec2(-d.y, d.x) * (UV.y * k.w);
	} else if (shape == 2) {
		float a = UV.y * TAU;
		float rim = k.x * (1.0 + 0.13 * sin(a * 3.0 + k.y * 17.0) + 0.07 * sin(a * 5.0 + k.y * 31.0));
		p = c.xz + vec2(cos(a), sin(a)) * (rim * UV.x);
		v_color = mix(inner_color, outer_color, UV.x * UV.x) * COLOR;
	} else {
		float a = k.z + UV.y * k.w;
		p = c.xz + vec2(cos(a), sin(a)) * mix(k.x, k.y, UV.x);
	}
	if (shape != 2) {
		// the per-mark meshes these replace carried every triangle twice (both windings), so a ring, disc, cone or line
		// blended over the sand twice: the same colour at 1 - (1 - a)^2, measured against the old ones
		v_color.a = 1.0 - (1.0 - v_color.a) * (1.0 - v_color.a);
	}
	// a mark floated over the ground (pass 54): the lift rides in the basis's y column, 1 + metres (1 for every other mark)
	float extra = max(MODEL_MATRIX[1].y - 1.0, 0.0);
	vec3 world = vec3(p.x, ground(p) + lift + extra, p.y);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	ALBEDO = v_color.rgb;
	ALPHA = v_color.a;
}
