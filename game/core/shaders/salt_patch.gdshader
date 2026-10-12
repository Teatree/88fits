// The Salt weapon's patches (pass 69, core/systems/SaltPatches.gd): every patch is one instance of a MultiMesh of a
// unit disc that is laid over the terrain here vertex by vertex from the map's height grid, exactly as
// ground_mark.gdshader lays the telegraphs (the same grid, the same bilinear step as MapBase.height_at), so the dunes
// never cut through a patch. The rim is lobed like a spill; the fragment sprinkles grains of salt on a see-through base
// (a speckle on a world-space grid, so the grains stay put on the sand while the camera moves), and the rim breaks up
// into loose grains.
//   UV.x = 0 centre .. 1 rim, UV.y = 0..1 round; INSTANCE_CUSTOM.x = radius (m), .y = seed
//   COLOR (the instance colour): rgb the salt, a = alpha (the patch's fade in and out times its look's alpha)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform;

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform float lift = 0.1;
// grains a metre across the sand, and how bright a grain is over the base (0 = no grains)
uniform float grain_scale = 12.0;
uniform float grain_boost = 1.0;

varying vec4 v_color;
varying vec2 v_world;
varying float v_rim;
varying float v_seed;

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
	float a = UV.y * TAU;
	float rim = k.x * (1.0 + 0.09 * sin(a * 3.0 + k.y * 17.0) + 0.06 * sin(a * 5.0 + k.y * 31.0) + 0.03 * sin(a * 9.0 + k.y * 7.0));
	vec2 p = c.xz + vec2(cos(a), sin(a)) * (rim * UV.x);
	v_color = COLOR;
	v_world = p;
	v_rim = UV.x;
	v_seed = k.y;
	vec3 world = vec3(p.x, ground(p) + lift, p.y);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

float hash(vec2 p) {
	p = mod(p, 289.0);
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 on a grain, 0 between them: one jittered dot in some cells of a grid `scale` cells a metre, `fill` of the cells
float grains(vec2 w, float scale, float fill, float size) {
	vec2 g = w * scale;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(cell);
	vec2 off = vec2(hash(cell + 3.7), hash(cell + 11.3)) - 0.5;
	float d = length(f - off * 0.55);
	return (1.0 - smoothstep(size * 0.8, size, d)) * step(1.0 - fill, h);
}

void fragment() {
	// two sizes of grain: fine ones packed close, coarse ones scattered (the coarse set shifted per patch)
	float fine = grains(v_world, grain_scale, 0.6, 0.22);
	float coarse = grains(v_world + v_seed * 3.0, grain_scale * 0.42, 0.4, 0.2);
	float g = max(fine, coarse);
	// the body: solid to about 80% of the radius with a crisp edge, then loose coarse grains out to the rim
	float body = 1.0 - smoothstep(0.78, 0.92, v_rim);
	float loose = (1.0 - smoothstep(0.9, 1.0, v_rim)) * coarse;
	float a = v_color.a * max(body * (0.6 + 0.4 * g), loose * 1.1);
	vec3 col = v_color.rgb;
	// a grain is a lighter fleck of the salt (white stays white, pink goes pale, black salt glints grey), the bed between a
	// shade deeper
	float light = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 fleck = mix(col, vec3(1.0), light > 0.4 ? 0.55 : 0.0) + vec3(light > 0.4 ? 0.0 : 0.3);
	ALBEDO = mix(col * (light > 0.4 ? 0.93 : 1.0), fleck, g * grain_boost);
	ALPHA = clamp(a, 0.0, 1.0);
}
