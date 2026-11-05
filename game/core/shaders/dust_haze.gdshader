// Pass 126 (lane STAGE; Garry: The Dust Bowl, "Add a brown fog effect (without damping the view distance too much or killing
// performance) to imitate a dust storm"): one rolling layer of blown dust over the ground, the cheap half of the storm
// (the scene's Environment fog is the other half). One full-screen quad (a clip-space quad like stage_filter's), one small
// tiling noise sampled twice, no loop: the two samples slide along the wind at different speeds and scales and are
// stretched along it, so soft bands of dust roll past. Each pixel finds the ground under it (a straight line from the
// camera), so the bands lie on the world, not on the glass, and thin out round the hero (`hero_xz`).
// DustHaze.gd owns it and hides the node on any stage without a haze (nothing drawn, nothing set).
// Drawn before the stage's filter (StageLook.PRIORITY) and under the gusts and the tornado, so the filter tints it like the
// sand, and read past the creatures and the hero (stencil 1, StageStencil.ACTOR): the crowd is never veiled. fog_disabled:
// the scene's fog added on top of a see-through layer would turn it to a solid sheet (CLAUDE.md's gotcha).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 color : source_color = vec3(0.66, 0.49, 0.29);
// how thick the bands are at their thickest (the layer's alpha), and the share of that left between the bands
uniform float strength = 0.3;
uniform float floor_share = 0.35;
// the wind on the ground (a unit vector) and how fast the bands slide (m/s for the broad band; the fine one 2.1 x it)
uniform vec2 wind = vec2(0.958, 0.287);
uniform float speed = 6.0;
// metres of ground one tile of the broad band covers along and across the wind; the fine band is 0.43 of those
uniform vec2 tile = vec2(110.0, 42.0);
// where the hero stands, the share of the layer left on him and the metres over which it comes back
uniform vec2 hero_xz = vec2(0.0);
uniform float hero_clear = 0.45;
uniform vec2 clear_r = vec2(5.0, 16.0);
// the layer's own clock (DustHaze: it stops with the game's pause)
uniform float clock = 0.0;
// 0..1: the fade in and out as a stage's weather comes and goes
uniform float amount = 1.0;

varying vec3 v_ray;
varying vec3 v_cam;

void vertex() {
	vec2 ndc = VERTEX.xy * 2.0;
	POSITION = vec4(ndc, 0.0, 1.0);
	vec4 p = INV_PROJECTION_MATRIX * vec4(ndc, 0.0, 1.0);
	v_ray = (INV_VIEW_MATRIX * vec4(p.xyz / p.w, 0.0)).xyz;
	v_cam = INV_VIEW_MATRIX[3].xyz;
}

void fragment() {
	// the ground under this pixel (a flat ground is near enough for a veil); a ray over the horizon reads far away
	float dy = min(v_ray.y, -0.0005);
	vec2 g = v_cam.xz + v_ray.xz * (-v_cam.y / dy);
	// along and across the wind
	vec2 u = vec2(dot(g, wind), dot(g, vec2(-wind.y, wind.x)));
	float a = texture(noise_tex, (u - vec2(speed * clock, 0.0)) / tile).r;
	float b = texture(noise_tex, (u - vec2(speed * 2.1 * clock, speed * 0.2 * clock)) / (tile * 0.43)).r;
	float bands = smoothstep(0.28, 0.82, a * 0.62 + b * 0.38);
	float near = smoothstep(clear_r.x, clear_r.y, distance(g, hero_xz));
	ALBEDO = color;
	ALPHA = amount * strength * mix(floor_share, 1.0, bands) * mix(hero_clear, 1.0, near);
}
