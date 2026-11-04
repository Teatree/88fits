// Pass 123 (lane BACKDROP): one of the title scene's paintings standing on the Royale menu backdrop (RoyaleBackdrop.gd),
// the game's own prop picture graded for the sunset behind it, and swaying from its base like prop_billboard's wind.
// A Sprite2D with its origin on the painting's base (centered off, offset (-w / 2, -h)), so VERTEX.y is minus the
// height above the base in the picture's px. Shared by every painting with the same sway; the phase comes from where
// the painting stands.
// mode "shadow" (is_shadow = true): the same picture flipped down the sand towards the viewer as its long evening
// shadow (the node's scale.y negative and its skew away from the sun), a flat dusk colour that fades along its length.
shader_type canvas_item;

// the top's lean, a share of the picture's height (title_scene.json's `sway`), its speed, and a slow gust over it
uniform float sway = 0.0;
uniform float speed = 1.3;
uniform float gust = 0.3;
// the sun, in the canvas's px (the backdrop sets it after laying out): the rim light faces it
uniform vec2 sun_pos = vec2(540.0, 600.0);
// backlit: the side the viewer sees is in the evening's shade, a touch warm
uniform vec3 shade : source_color = vec3(0.76, 0.62, 0.68);
uniform float shade_mix = 1.0;
// the day's saturation taken down towards the evening's (0 none, 1 grey)
uniform float desat = 0.22;
// the light along the edges that face the sun
uniform vec4 rim_color : source_color = vec4(1.0, 0.78, 0.42, 1.0);
uniform float rim_width = 0.018;
uniform float rim_strength = 0.9;
// a warm glow over the top, fading to the shade at the base
uniform vec3 top_glow : source_color = vec3(1.0, 0.72, 0.45);
uniform float top_glow_k = 0.24;
// the evening haze: a painting standing nearer the horizon fades towards it (its base's canvas y between the hero's
// soles, none, and the horizon, haze_k), as the plate's own far scatter does
uniform vec4 haze_color : source_color = vec4(0.86, 0.62, 0.70, 1.0);
uniform float haze_k = 0.28;
uniform float haze_near_y = 1130.0;
uniform float haze_far_y = 800.0;
uniform bool is_shadow = false;
uniform vec4 shadow_color : source_color = vec4(0.20, 0.08, 0.20, 0.5);

varying vec2 v_world;
varying float v_ly;
// the node's modulate (the fragment's COLOR already holds the texture's colour too)
varying vec4 v_mod;
varying float v_haze;

void vertex() {
	float ly = 1.0 - UV.y;
	float phase = MODEL_MATRIX[3].x * 0.0131 + MODEL_MATRIX[3].y * 0.0071;
	float g = 1.0 - gust + gust * sin(TIME * 0.37 + phase * 0.5);
	// the game's wind (prop_billboard): the top leans sway x its height, the base stays put
	float lean = sin(TIME * speed + phase) * sway * g * ly * (-VERTEX.y);
	VERTEX.x += lean;
	v_ly = ly;
	v_mod = COLOR;
	float far = clamp((haze_near_y - MODEL_MATRIX[3].y) / max(haze_near_y - haze_far_y, 1.0), 0.0, 1.0);
	v_haze = haze_k * pow(far, 1.3);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (is_shadow) {
		// softer the further from the base: three taps spread with the length
		vec2 px = TEXTURE_PIXEL_SIZE * (1.5 + 10.0 * v_ly);
		float a = c.a * 0.4 + texture(TEXTURE, UV + vec2(px.x, 0.0)).a * 0.3 + texture(TEXTURE, UV - vec2(px.x, 0.0)).a * 0.3;
		float fade = (1.0 - v_ly) * (1.0 - v_ly * 0.35);
		COLOR = vec4(shadow_color.rgb, shadow_color.a * a * fade * v_mod.a);
	} else {
		vec3 col = mix(c.rgb, vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))), desat);
		col = mix(col, col * shade, shade_mix);
		col = mix(col, col * top_glow * 1.35, top_glow_k * v_ly);
		// the edge towards the sun: a painted pixel whose neighbour that way is empty
		vec2 dir = sun_pos - v_world;
		float len = max(length(dir), 1.0);
		vec2 d = dir / len * rim_width;
		float a1 = texture(TEXTURE, UV + vec2(d.x, d.y)).a;
		float a2 = texture(TEXTURE, UV + vec2(d.x, d.y) * 0.5).a;
		// and a softer light a little further in, so the lit side reads as lit, not outlined
		float a3 = texture(TEXTURE, UV + vec2(d.x, d.y) * 2.6).a;
		float rim = c.a * max(clamp(1.0 - min(a1, a2) * 1.2, 0.0, 1.0), 0.42 * (1.0 - a3));
		col = mix(col, haze_color.rgb, v_haze);
		col = mix(col, rim_color.rgb, rim * rim_strength);
		COLOR = vec4(col, c.a) * v_mod;
	}
}
