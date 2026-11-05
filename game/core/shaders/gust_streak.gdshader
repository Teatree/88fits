// Pass 126 (lane STAGE; Garry: "Make the wind visual vfx effect stronger looking on this map only"; the lead: no hard cut ends): one streak of
// a stage's storm (DustGust.set_storm), a long thin quad of the gusts' one MultiMesh (local Y its length, UV.y along it, instance colour
// COLOR). Its alpha reaches exactly 0 at both ends and both sides, so a streak has no edge of its own. No depth test: a flat quad 20 m long
// over rolling dunes was cut off where the sand rose through it, the hard ends the first version had. It draws over the sand and the
// scenery as blowing dust and reads past the creatures and the hero (stencil 1, StageStencil.ACTOR), as the haze does. fog_disabled: the
// scene's fog on a see-through layer would turn it to a solid sheet (CLAUDE.md's gotcha). Before the stage's filter, which tints it like
// the sand. The map's ordinary gusts keep their StandardMaterial3D and painted streak, to the number.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 1;

void fragment() {
	float along = pow(sin(UV.y * PI), 1.4);
	float across = pow(sin(UV.x * PI), 2.0);
	// a few grainy lines along the streak
	float grain = 0.85 + 0.15 * sin(UV.x * 19.0 + UV.y * 7.0);
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * along * across * grain;
}
