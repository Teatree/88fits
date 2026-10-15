// The oasis water (pass 81, lane MAP; Garry: "Make the water look more like water. Maybe a cheap (in terms of
// performance) shader."). One material for every lake, on the lake's flat disc (RedCanyon._build_lake, a CylinderMesh):
// a deep teal middle shading to a light shallow rim, the wet sand showing through at the shore, which fades out along a
// ragged line (no hard disc edge), slow ripples from two noise layers panned against each other (the bright web where
// they cross reads as sunlit ripples), a lapping line at the shore, small sun glints, and a little sky in the far water.
// Unshaded, no screen or depth reads, three samples of one 256 px noise texture (art/env/noise_rgb.png). Pass 31's wave
// shader read as "a patterned disc lying on the sand": every pattern here stays faint, irregular and slow.
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;

// r, g, b: three independent smooth tileable noises, read raw
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.04, 0.34, 0.50);
uniform vec3 shallow_color : source_color = vec3(0.20, 0.62, 0.66);
// the wet sand seen through the thin water at the shore
uniform vec3 shore_color : source_color = vec3(0.58, 0.62, 0.48);
uniform vec3 foam_color : source_color = vec3(0.93, 0.96, 0.92);
uniform vec3 sky_color : source_color = vec3(0.78, 0.88, 0.94);
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.9;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.62;
// where the water ends, as a fraction of the disc's radius, and how much the noise moves it either way
uniform float shore_at = 0.95;
uniform float shore_wobble = 0.05;
// the ripples: noise tiles a metre, how fast the two layers drift, how bright and how sharp their web is
uniform float ripple_scale = 0.085;
uniform float ripple_speed = 0.022;
uniform float ripple_light : hint_range(0.0, 1.0) = 0.08;
uniform float ripple_sharp = 2.2;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.35;
// the glints: a finer layer (noise tiles a metre) drifting faster; a glint where it peaks past glint_from
uniform float glint_scale = 1.1;
uniform float glint_from = 0.955;
uniform float glint_strength : hint_range(0.0, 2.0) = 0.7;
uniform float sky_strength : hint_range(0.0, 1.0) = 0.35;
// stage 3 (hell): the water takes the red light like the ground (RedCanyon._apply_hell)
uniform float hell : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// the CylinderMesh's top cap maps its disc onto UV (0.25, 0.75) +- 0.25; the sides (v below 0.5) and the bottom cap (u
	// past 0.5) are never water: only the top face is drawn
	if (UV.y < 0.5 || UV.x > 0.5) {
		discard;
	}
	float rn = length(UV - vec2(0.25, 0.75)) * 4.0;
	vec2 wp = v_world.xz;
	// the shore line: a slow, still noise moves it in and out, so the water's edge is ragged, never the disc's circle
	vec3 still = texture(noise_tex, wp * 0.045).rgb;
	// (kept inside the disc: its 40 straight sides reach in to 0.997 of its radius between the corners)
	float edge = min(shore_at + (still.b - 0.5) * 2.0 * shore_wobble, 0.985);
	// two layers drifting across each other
	float t = TIME * ripple_speed;
	vec3 a = texture(noise_tex, wp * ripple_scale + vec2(t, t * 0.63)).rgb;
	vec3 b = texture(noise_tex, wp.yx * (ripple_scale * 1.41) + vec2(-t * 0.71, t * 0.93)).rgb;
	float h = a.r + b.g;
	// the web where the two meet in the middle: soft bright lines that wander as the layers drift
	float web = 1.0 - clamp(abs(h - 1.0) * ripple_sharp, 0.0, 1.0);
	web *= web;
	// depth: deep in the middle, shallow out to the shore
	float depth = 1.0 - smoothstep(0.18, edge, rn);
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 0.85, depth));
	// a slow swell of light and shade over the whole surface
	col *= 0.93 + 0.14 * a.g;
	// the shore: the sand shows through the last stretch of thin water
	float thin = smoothstep(edge - 0.2, edge - 0.02, rn);
	col = mix(col, shore_color, thin * 0.35);
	col += vec3(0.9, 0.97, 1.0) * web * ripple_light * (0.35 + 0.65 * depth);
	// a little sky in the far water (grazing view)
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	col = mix(col, sky_color, clamp(fres * fres * 2.2, 0.0, 1.0) * sky_strength);
	// the lapping line: a band just inside the edge, broken by the noise, breathing slowly
	float lap = smoothstep(edge - 0.085, edge - 0.04, rn) * (1.0 - smoothstep(edge - 0.035, edge, rn));
	lap *= smoothstep(0.35, 0.6, a.b) * (0.65 + 0.35 * sin(TIME * 1.4 + still.r * 9.0));
	col = mix(col, foam_color, lap * foam_strength);
	// sun glints: small, sparse, only where the slow layer is light too, twinkling as the fine layer drifts
	float f = texture(noise_tex, wp * glint_scale + vec2(t * 3.1, -t * 2.3)).b;
	float glint = smoothstep(glint_from, glint_from + 0.05, f) * smoothstep(0.45, 0.75, a.b) * (1.0 - thin);
	col += foam_color * glint * glint_strength;
	col = mix(col, col * vec3(1.05, 0.72, 0.66) + vec3(0.06, 0.0, 0.0), hell * 0.7);
	ALBEDO = col;
	// clear at the shore, deep in the middle; the edge fades over the last stretch
	float alpha = mix(shallow_alpha, deep_alpha, smoothstep(0.0, 0.6, depth));
	alpha *= 1.0 - smoothstep(edge - 0.05, edge, rn);
	ALPHA = clamp(alpha + lap * foam_strength * 0.3 + glint * 0.3, 0.0, 1.0) * step(rn, edge);
}
