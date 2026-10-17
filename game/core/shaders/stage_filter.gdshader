// Pass 87 (lane SLOOK; Garry: "a blueish dim filter on the map for Stage 2 to indicate evening, and a redish filter on
// Stage 3 to indicate hell / bloodmoon ... This should look good and not mess up how elements 'read' during the game"):
// a stage's filter, one quad over the whole view that multiplies what is already drawn by `mult` (StageLook). The
// vertex shader puts the quad in clip space, so it covers any camera's view whatever its transform; its node is never
// culled (StageLook gives it the largest cull margin).
// StageLook draws it at a render priority after the opaque world and the water but BEFORE the ground marks (telegraphs),
// the shadows, the gems and coins, the outlines, the effects and the projectiles, so those are drawn on top untinted.
// Two copies by the stencil the paintings write (SceneryStencil): this one where the nearest thing is NOT a creature, the
// hero, a power-up or a flower (stencil 0 the sand, the water, the sky; 2 the scenery), at the filter's full strength;
// StageLook's copy with `compare_equal, 1` on those paintings, at the filter's `actors` share, so they stay brighter
// than the world and read. One draw each; no material elsewhere knows about it. Unshaded and fog-free, so `mult` is the
// factor as given (StageLook hands it in the screen's terms, see StageLook.screen_mult).
shader_type spatial;
render_mode unshaded, blend_mul, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

uniform vec3 mult = vec3(1.0);

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	ALBEDO = mult;
}
