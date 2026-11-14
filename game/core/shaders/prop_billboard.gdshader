// One painted prop per instance (cacti, rocks, bones): a camera-facing quad pivoting on its base, like the creatures,
// but muted a touch and with a slow sway for greenery. Opaque with an alpha cut, so props and characters sort
// against each other per pixel by depth (no blend-order artefacts, no z-fighting between parallel quads).
// INSTANCE_CUSTOM: x = flip (0/1), y = sway amount (0 for rocks), z = sway phase, w = the tint's three rolls and its
// strength (pass 85; pass 137, PropField.tint_code: r1 + 8 r2 + 64 r3 + 512 level, rolls 0..7, level 0..3 = none, a
// third, two thirds or all of the rule's reach)
shader_type spatial;
render_mode cull_disabled, unshaded, skip_vertex_transform, depth_draw_opaque;
// Every painting (the props here too) writes stencil 1 where it draws a pixel (pass 54, Garry: gems and coins drawn under every 2.5D sprite):
// the gems and coins (PickupManager, see-through, drawn after every opaque thing) skip those pixels, so they lie under
// the creatures, the hero, the props and the structures wherever they overlap, in front of a painting's plane or not.
// Pass 72 (lane SPEC): a prop is scenery and writes 2 (SceneryStencil.VALUE), so a creature it hides is outlined
// (enemy_silhouette reads 2) while one hidden by another creature (1) is not; the gems read 0 (nothing painted).
// Pass 105 (lane LOOK): scenery writes 4 now (SceneryStencil.VALUE; the table is in StageStencil's header).
stencil_mode write, compare_always, 4;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;
uniform float mute : hint_range(0.0, 1.0) = 0.12;
uniform float face_camera : hint_range(0.0, 1.0) = 1.0;
// Pass 122 (lane S3WORLD; Garry: barrels "more visible on all that red"): a pale rim light round the painting. `rim`
// 0..1 is how far it is on (0, the default: the shader is as before, every prop unchanged, no extra tap); on, a line
// rim_width (of the painting's square, times `rim`) wide in rim_color is drawn just outside the painted edge and the
// painted edge itself lightens a little towards it (eight alpha taps round the pixel). Only the barrels' materials set
// it (BarrelField.set_hell: it comes in with the Blood Moon's hell), so a barrel reads on the red ground as a moonlit
// edge, the way a creature behind a cactus reads through its outline.
uniform float rim : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float rim_width = 0.03;
// Pass 126 (lane STAGE; Garry: The Dust Bowl, "Make the trees and such bob much more from the wind"): the wind a stage's
// weather sets (PropField.set_wind): the lean x wind_mult, the sway at wind_speed, and wind_gust 0..1, a slow swell on the
// lean. These defaults are the shader as it always was. A sway of 0 (rocks, bones) stays still at any wind; the base stays
// put (the lean is 0 at the foot) and the quad only shears, so the painting cannot tear.
uniform float wind_mult = 1.0;
uniform float wind_speed = 1.3;
uniform float wind_gust = 0.0;
// Pass 135 (Garry: "Barrels aren't clear, make them glint occasionally"): a glint, a bright band sweeping corner to corner
// over the painted pixels now and then. `glint` 0..1 is its strength (0, the default: off, every prop unchanged); each
// instance glints once every glint_every seconds x 0.75..1.25 (its own, from INSTANCE_CUSTOM.z, the barrels' phase: their
// sway is 0, so z only times the glint), the band taking glint_length seconds to cross, glint_width (of the painting's
// diagonal) wide, in glint_color, with a soft lift of the whole painting at its peak. Only the barrels set it
// (BarrelField, the map's `barrels.glint`).
uniform float glint : hint_range(0.0, 1.0) = 0.0;
uniform float glint_every = 6.0;
uniform float glint_length = 0.5;
uniform float glint_width = 0.14;
uniform vec4 glint_color : source_color = vec4(1.0, 0.97, 0.86, 1.0);
// Pass 138 (lane FX; Garry: "Barrel should flicker white when Player hits ... a similar enemy flicker that they get, just
// colour it white and back with a mask or something"): with HIT_FLASH defined (only BarrelField.barrel_shader() defines
// it, so every scenery prop compiles without it and costs nothing) INSTANCE_CUSTOM.y is the hit flash 0..1 in place of
// the sway (a barrel's sway was always 0): the painted pixels go that far to white, as enemy_billboard's `v_flash`.

// Pass 148 (lane ROCKS; Garry: the painted rocks "feel a little detached from the ground"): a painting's foot, so its
// bottom meets the sand. Every default is off (foot_band 0, foot_sink 0: the shader as before, nothing computed); a kind
// opts in by its props.json `foot` (PropField._set_foot_uniforms; BALANCING 91):
//   foot_sink   the painting sinks this far (of its quad's height) below its spot, straight down: the sand in front of it
//               hides the bottom of the picture (the painted pebbles and the dark line along the base) by depth.
//   foot_band   the band (world height above the spot's ground, of the quad's height) over which the foot blends in.
//   foot_fade   0..1: how much of that band dithers away (a 4x4 ordered dither on the screen's pixels: the sand itself shows
//               through, whatever colour the stage gives it); the alpha cut stays, so depth sorting is as before.
//   foot_color  the tone the band goes towards (the sand's), .a how far at the ground line (0: no tone).
//   foot_dark   a contact darkening on the painting at the ground line, easing out over the band.
//   foot_noise  how ragged the band's top is (a few sines along the painting's width and the instance's phase).
uniform float foot_sink = 0.0;
uniform float foot_band = 0.0;
uniform float foot_fade = 0.0;
uniform vec4 foot_color : source_color = vec4(0.8, 0.66, 0.48, 0.0);
uniform float foot_dark = 0.0;
uniform float foot_noise = 0.0;

varying vec2 v_uv;
varying vec4 v_roll;
// pass 148: the pixel's height above its spot's ground, of the quad's height (the foot's band); v_phase the instance's
varying float v_above;
varying float v_phase;
varying float v_glint;
#ifdef HIT_FLASH
varying float v_flash;
#endif

// Pass 85 (lane WORLD): the natural tints, up to two parts per painting (PropField._set_tint_uniforms): hue window
// (lo, hi, sat_min, all hues), the hue shift and saturation factor ranges, the value factor range with the link and on.
uniform vec4 tint_hue_0 = vec4(0.0, 1.0, 0.1, 1.0);
uniform vec4 tint_hs_0 = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint_v_0 = vec4(1.0, 1.0, 0.5, 0.0);
uniform vec4 tint_hue_1 = vec4(0.0, 1.0, 0.1, 1.0);
uniform vec4 tint_hs_1 = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint_v_1 = vec4(1.0, 1.0, 0.5, 0.0);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// how much a pixel of hue h belongs to the window lo..hi (wrapping when lo > hi), soft by 0.03 at the edges
float in_window(float h, float lo, float hi) {
	float soft = 0.03;
	if (lo <= hi) {
		return smoothstep(lo - soft, lo, h) * (1.0 - smoothstep(hi, hi + soft, h));
	}
	return max(smoothstep(lo - soft, lo, h), 1.0 - smoothstep(hi, hi + soft, h));
}

vec3 tint_part(vec3 rgb, vec3 hsv, vec4 hue, vec4 hs, vec4 v, vec4 roll) {
	if (v.w < 0.5) {
		return rgb;
	}
	float w = hue.w > 0.5 ? 1.0 : in_window(hsv.x, hue.x, hue.y);
	// greys (outlines, bleached bone) and the darkest lines are left alone
	w *= smoothstep(hue.z * 0.5, hue.z, hsv.y) * smoothstep(0.06, 0.16, hsv.z);
	if (w <= 0.0) {
		return rgb;
	}
	float r1 = roll.x;
	float r2 = mix(roll.y, r1, v.z);
	float r3 = mix(roll.z, r1, v.z);
	// pass 137: roll.w is the strength, 0 (as painted) .. 1 (the rule's whole reach)
	float k = roll.w;
	vec3 t = vec3(fract(hsv.x + mix(hs.x, hs.y, r1) * k), clamp(hsv.y * mix(1.0, mix(hs.z, hs.w, r2), k), 0.0, 1.0),
		clamp(hsv.z * mix(1.0, mix(v.x, v.y, r3), k), 0.0, 1.0));
	return mix(rgb, hsv2rgb(t), w);
}

void vertex() {
	float flip = INSTANCE_CUSTOM.x;
	float sway = INSTANCE_CUSTOM.y;
	float phase = INSTANCE_CUSTOM.z;
#ifdef HIT_FLASH
	v_flash = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	sway = 0.0;
#endif
	vec2 uv = UV;
	if (flip > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	v_uv = uv;
	v_glint = -1.0;
	if (glint > 0.0) {
		// how far through its glint this instance is (0..1), -1 between glints
		float h = fract(sin(phase * 12.9898 + 78.233) * 43758.5453);
		float cyc = glint_every * (0.75 + 0.5 * h);
		float t = mod(TIME + h * 97.0, cyc);
		v_glint = t < glint_length ? t / glint_length : -1.0;
	}
	float code = floor(INSTANCE_CUSTOM.w + 0.5);
	v_roll = vec4(mod(code, 8.0) / 7.0, mod(floor(code / 8.0), 8.0) / 7.0, mod(floor(code / 64.0), 8.0) / 7.0, floor(code / 512.0) / 3.0);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 cam_back = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), cam_up, face_camera));
	vec3 right = normalize(cross(up, cam_back));
	float ly = VERTEX.y + 0.5;
	// wind: the top of a plant leans a few degrees back and forth, the base stays put
	float lean = sin(TIME * wind_speed + phase) * sway * ly * ly * wind_mult * (1.0 + wind_gust * sin(TIME * 0.61 + phase * 0.5));
	// pass 148: the foot's sink, straight down; PropField.add lays the spot 0.06 m above the ground
	float ground_y = origin.y - 0.06;
	origin.y -= foot_sink * sy;
	vec3 world = origin + right * (VERTEX.x * sx + lean * sy) + up * ly * sy;
	v_above = (world.y - ground_y) / max(sy, 0.001);
	v_phase = phase;
#ifdef HIT_FLASH
	// Pass 141 (lane GRAV): a barrel in the Gravity Gun's grip tumbles: INSTANCE_CUSTOM.w is its roll in radians (a
	// barrel has no tint, so w was always 0), the painting turned about its middle in the picture's plane.
	float roll = INSTANCE_CUSTOM.w;
	v_roll = vec4(0.0);
	if (roll != 0.0) {
		vec2 q = vec2(VERTEX.x * sx, (ly - 0.5) * sy);
		float cr = cos(roll);
		float sr = sin(roll);
		q = vec2(q.x * cr - q.y * sr, q.x * sr + q.y * cr);
		world = origin + up * (0.5 * sy) + right * q.x + up * q.y;
	}
#endif
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(cam_back, 0.0)).xyz);
}

void fragment() {
	vec4 c = texture(sprite, v_uv);
	// pass 122: the rim light (rim > 0 only): a pixel just outside the painted edge, or a painted one at the edge
	float rim_out = 0.0;
	float rim_in = 0.0;
	if (rim > 0.0) {
		float w = rim_width * rim;
		float hi = 0.0;
		float lo = 1.0;
		for (int k = 0; k < 8; k++) {
			float ang = float(k) * TAU / 8.0;
			float a = texture(sprite, v_uv + vec2(cos(ang), sin(ang)) * w).a;
			hi = max(hi, a);
			lo = min(lo, a);
		}
		rim_out = (c.a < alpha_cut && hi >= alpha_cut) ? 1.0 : 0.0;
		rim_in = (c.a >= alpha_cut && lo < alpha_cut) ? 1.0 : 0.0;
	}
	if (c.a < alpha_cut && rim_out < 0.5) {
		discard;
	}
	// pass 148: the foot (0 below the band's ragged top, 1 above it); off unless foot_band > 0
	float foot_t = 1.0;
	if (foot_band > 0.0) {
		float n = foot_noise * (0.6 * sin(v_uv.x * 17.0 + v_phase * 3.0) + 0.4 * sin(v_uv.x * 41.0 + v_phase * 7.0 + 1.3));
		foot_t = clamp(v_above / foot_band + n, 0.0, 1.0);
		if (foot_fade > 0.0) {
			vec2 q = mod(floor(FRAGCOORD.xy), 4.0);
			// the 4x4 Bayer matrix, worked out from the pixel's place (no table)
			float bx = mod(q.x, 2.0);
			float by = mod(q.y, 2.0);
			float hx = floor(q.x * 0.5);
			float hy = floor(q.y * 0.5);
			// 2x2: 2 |x - y| + y (0 2 / 3 1); 4x4: 4 x the low bits' + the high bits'
			float bayer = (4.0 * (2.0 * abs(bx - by) + by) + (2.0 * abs(hx - hy) + hy)) / 16.0;
			if (mix(1.0, foot_t, foot_fade) < bayer + 0.03) {
				discard;
			}
		}
	}
	if (rim_out > 0.5) {
		ALBEDO = rim_color.rgb;
	} else {
		if (tint_v_0.w > 0.5 && v_roll.w > 0.0) {
			vec3 hsv = rgb2hsv(c.rgb);
			vec3 rgb = tint_part(c.rgb, hsv, tint_hue_0, tint_hs_0, tint_v_0, v_roll);
			c.rgb = tint_v_1.w > 0.5 ? tint_part(rgb, rgb2hsv(rgb), tint_hue_1, tint_hs_1, tint_v_1, v_roll) : rgb;
		}
		float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		vec3 albedo = mix(c.rgb, vec3(lum), mute) * (1.0 - mute * 0.3);
		ALBEDO = mix(albedo, rim_color.rgb, rim_in * rim * 0.45);
		if (foot_band > 0.0) {
			float g = 1.0 - smoothstep(0.0, 1.0, foot_t);
			ALBEDO = mix(ALBEDO, foot_color.rgb, foot_color.a * g) * (1.0 - foot_dark * g * g);
		}
		if (v_glint >= 0.0) {
			float s = v_glint * 1.6 - 0.3;
			float u = (v_uv.x + (1.0 - v_uv.y)) * 0.5;
			float band = 1.0 - smoothstep(0.0, glint_width, abs(u - s));
			float peak = sin(v_glint * 3.14159);
			ALBEDO += glint_color.rgb * glint * (band * 0.9 + peak * 0.12);
		}
#ifdef HIT_FLASH
		// the hit flash: the painting's own pixels to white (its shape is the mask), as a creature's
		ALBEDO = mix(ALBEDO, vec3(1.0), v_flash);
#endif
	}
}
