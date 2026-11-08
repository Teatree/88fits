// The aim wedge (pass 136, lane GUNS; R7 of docs/weapons_aim): a faint wedge on the sand in front of the Outlaw and a
// small chevron at his feet (core/systems/AimWedge.gd). The mesh is built flat in the node's own space (forward -Z) and
// placed by the node; here every vertex is laid on the terrain from the map's height grid (the same lookup as
// ground_mark.gdshader: Telegraphs._ground_uniforms fills the uniforms). COLOR.a is each vertex's share of the alpha (in
// near him, out at the far end); UV.x the distance from him in metres (-1 on the chevron), UV.y the angle off the facing
// (radians). The fill is a soft dark shade (a white one vanished on Sundown's pale sand), its two edges thin pale lines,
// the chevron pale; a shot's line (ray_angle) flashes pale down it for a moment. Transparent and unshaded: drawn after
// the stage filter, so it reads the same on every stage.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, world_vertex_coords, fog_disabled;

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform int grid_n = 0;
uniform float half_size = 70.0;
uniform float resolution = 1.0;
uniform float lift = 0.1;
// the fill's shade and its alpha at its fullest; the edge lines' and the chevron's colour and alpha
uniform vec3 fill_tint : source_color = vec3(0.13, 0.09, 0.06);
uniform float alpha = 0.12;
uniform vec3 line_tint : source_color = vec3(1.0, 0.95, 0.82);
uniform float line_alpha = 0.32;
uniform float chevron_alpha = 0.5;
// half the wedge's angle (radians), for its edge lines
uniform float half_angle = 0.5236;
// 1 at rest, more during a pulse
uniform float strength = 1.0;
// a shot's line: its angle off the facing and how bright it is now (0: none)
uniform float ray_angle = 0.0;
uniform float ray_strength = 0.0;

varying float v_a;

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
	v_a = COLOR.a;
	VERTEX.y = ground(VERTEX.xz) + lift;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	if (UV.x < 0.0) {
		ALBEDO = line_tint;
		ALPHA = clamp(chevron_alpha * (0.7 + 0.3 * strength), 0.0, 1.0);
	} else {
		float fill_a = alpha * v_a * strength;
		// the edge lines, about 5 cm wide
		float to_edge = (half_angle - abs(UV.y)) * UV.x;
		float line_a = line_alpha * v_a * (1.0 - smoothstep(0.025, 0.07, to_edge)) * (0.6 + 0.4 * strength);
		float ray_a = 0.0;
		if (ray_strength > 0.0) {
			// a line about 0.14 m wide down the shot's way, fading towards the wedge's far end
			float off = abs(UV.y - ray_angle) * max(UV.x, 0.3);
			ray_a = ray_strength * exp(-(off * off) / 0.005) * clamp(1.0 - UV.x / 3.4, 0.0, 1.0);
		}
		float la = clamp(line_a + ray_a, 0.0, 1.0);
		ALBEDO = mix(fill_tint, line_tint, la / max(la + fill_a, 0.0001));
		ALPHA = clamp(fill_a + la, 0.0, 1.0);
	}
}
