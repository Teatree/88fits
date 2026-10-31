// A piece of a smashed barrel's painting (Garry, 2026-10-31: "the breaking isn't clear ... make the break more obvious
// looking. Complete with some debris that lingers for a bit"; core/systems/BarrelDebris.gd). One camera-facing quad per
// piece that shows its own rectangle of the barrel's picture, turned in the picture's plane by its spin.
// The instance transform carries the piece: origin = its centre, column 0 = (cos a, sin a) * width, column 1's length =
// its height (the angle and the sizes, not a real basis). INSTANCE_CUSTOM = the rectangle (u0, v0, u1, v1).
// COLOR.rgb = which of its edges are cuts (top, bottom, sides); COLOR.a = how solid it still is: below 1 it dissolves in a ragged pattern (the linger's end).
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_opaque;
// the barrels' own stencil (SceneryStencil.STRUCTURE): the stage filter treats the pieces as it treats the barrels
stencil_mode write, compare_always, 5;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;
uniform float mute = 0.04;

varying vec2 v_uv;
varying vec2 v_local;
varying float v_solid;
varying vec2 v_piece;
varying vec3 v_cut;

void vertex() {
	vec4 rect = INSTANCE_CUSTOM;
	v_uv = mix(rect.xy, rect.zw, UV);
	v_local = UV * vec2(rect.z - rect.x, rect.w - rect.y) * 40.0;
	v_solid = COLOR.a;
	v_piece = UV;
	v_cut = COLOR.rgb;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 ax = MODEL_MATRIX[0].xy;
	float w = length(ax);
	float h = length(MODEL_MATRIX[1].xyz);
	float a = atan(ax.y, ax.x);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 right = normalize(cross(up, cam_back));
	vec2 v = vec2(VERTEX.x * w, VERTEX.y * h);
	float c = cos(a);
	float s = sin(a);
	v = vec2(c * v.x - s * v.y, s * v.x + c * v.y);
	vec3 world = origin + right * v.x + up * v.y;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(sprite, v_uv);
	if (c.a < alpha_cut || hash(v_local * 3.0) > v_solid) {
		discard;
	}
	// splintered cuts: the piece's edges eaten away in jagged steps (wood breaks along its grain: deeper across the
	// top and bottom of a stave than down its sides)
	float jag_y = hash(vec2(floor(v_piece.x * 9.0), 3.0)) * 0.16;
	float jag_x = hash(vec2(7.0, floor(v_piece.y * 7.0))) * 0.07;
	// COLOR.rgb says which edges are cuts (r the top, g the bottom, b the sides); the barrel's own outline stays whole
	if ((v_cut.r > 0.5 && v_piece.y < jag_y) || (v_cut.g > 0.5 && v_piece.y > 1.0 - jag_y * 0.8)
			|| (v_cut.b > 0.5 && (v_piece.x < jag_x || v_piece.x > 1.0 - jag_x))) {
		discard;
	}
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(c.rgb, vec3(lum), mute) * (1.0 - mute * 0.3);
}
