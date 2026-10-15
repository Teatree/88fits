// The tracers (pass 79, lane FX: one thin smoke line; pass 80, lane TRAIL: the styles below, after Garry's "the revolver
// trail looks awful ... I want a clear visible trail, but one that doesn't look this bad"; the research is in
// tools/dl/p80/TRAIL/research.md). One quad per segment of a shot's flight, all of them in one MultiMesh
// (ProjectileManager._tracer_*); the instance transform carries the segment, not a placement:
//   origin            = the segment's start (world)
//   basis column 0    = the segment (start to end, world)
//   basis column 1    = (the end's birth on the shots' clock, life in seconds, width in metres)
//   basis column 2    = (the start's birth, the style, hot): the shot passed the start a little before the end, so the
//                       pieces of one line meet with the same age and width (no seam where they join); the style picks
//                       the look below; hot is the part of the life (0..1) the white-hot core (or a wisp's streak) lasts
//   colour            = the tracer's colour as it should look on the screen (sRGB, as in the JSON) and its alpha
// Every quad faces the camera round its segment. Once a segment's life is out it collapses to a point and draws nothing.
// `now` is the shots' clock. The styles (ProjectileManager.TRACER_STYLE_IDS):
//   0 line    pass 79's thin line: at least min_px pixels, fades (1 - f)^fade_pow, widens by `widen`, drifts up at
//             `rise` m/s, sways, greys towards smoke
//   1 streak  the tracer round: a short streak tapering from the bullet to a point, a warm white-hot core in the
//             weapon's colour with a darker rim of the same hue (the rim is what reads on the light sand)
//   2 ribbon  a longer tapered ribbon that widens a little like a wake; its hot core lives only the first `hot` of the
//             life so the head keeps the contrast, the coloured body and rim fade after
//   3 wisp    the streak for the first `hot` of the life, under it a pale warm smoke that widens, lifts and fades
//   4 toon    hard cel bands (a white core, the flat colour, a dark outline), tapered, opaque until it shrinks away
// The head of every style but the line is at least head_px pixels wide (the floor is on the head, so the taper stays).
// No glow pass in the Compatibility renderer: the glow is painted into the cross-section. Alpha blending, never additive
// (additive washes out on the light sand).
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, depth_draw_never, blend_mix, shadows_disabled;

uniform float now = 0.0;
// the line (style 0, pass 79)
uniform float widen = 0.9;
uniform float rise = 0.45;
uniform float fade_pow = 1.5;
uniform float smoke_grey = 0.4;
uniform float sway = 0.06;
uniform float min_px = 1.5;
uniform float edge_soft = 0.45;
// the styles of pass 80
const float head_px = 3.0;          // the head's width floor in pixels
const float streak_taper = 0.75;    // width x (1 - f)^streak_taper
const float ribbon_taper = 1.0;
const float ribbon_wake = 0.7;      // the ribbon widens by this much over its life while it tapers
const float toon_taper = 0.35;
const float toon_scale = 0.6;       // toon has no halo: its band is this much of the width
const float core_size = 0.2;        // the white core's half-width (of the trail's half-width) at the head
const float inner_w = 0.42;         // the solid stroke's half-width (the rest is the halo)
const float halo_alpha = 0.42;      // the halo's opacity next to the stroke
const float head_glow = 0.8;        // how far the colour is lit to full towards the head
const float core_tint = 0.14;       // how much of the colour the white core keeps
const vec3 core_white = vec3(1.0, 0.97, 0.86);
const float rim_pow = 2.4;          // rim = colour^rim_pow x rim_gain: darker and more saturated, the same hue
const float rim_gain = 0.9;
const float rim_from = 0.45;        // where the rim starts across the half-width
const float rim_mix = 0.35;         // how far the stroke's edge goes to the rim colour
const float rim_light = 0.9;        // the same for a light colour (silver, gold)
const float light_dark = 0.3;       // a light colour's body this far towards its rim colour
const float warm_dark = 0.8;        // ... and a light saturated one's (gold: an amber body, not a cream fill)
const float warm_tip = 0.3;         // a light saturated colour's white middle lasts this share of its usual length
const float glow_soft = 0.42;       // the soft styles' outer falloff (of the half-width)
const float toon_outline = 0.62;    // toon: the outline's darkness (rim colour x this)
const float smoke_width = 2.4;      // wisp: the smoke's width at the end of its life (x the head width)
const float smoke_alpha = 0.38;
const float smoke_rise = 0.35;      // m/s
const vec3 smoke_colour = vec3(0.99, 0.97, 0.93);

varying float v_f;
varying float v_x;
varying float v_s;
varying float v_hot;
varying float v_tw;
varying float v_mw;
varying float v_px;

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 seg = MODEL_MATRIX[0].xyz;
	vec3 info = MODEL_MATRIX[1].xyz;
	vec3 info2 = MODEL_MATRIX[2].xyz;
	float life = max(info.y, 0.001);
	// the newest end decides whether the piece is drawn at all; each end fades on its own age
	float f_end = (now - info.x) / life;
	float age = now - mix(info2.x, info.x, UV.y);
	float f = clamp(age / life, 0.0, 1.0);
	float style = info2.y;
	float hot = clamp(info2.z, 0.02, 1.0);
	v_f = f;
	v_x = UV.x * 2.0 - 1.0;
	v_s = style;
	v_hot = hot;
	v_tw = 1.0;
	v_mw = 0.0;
	v_px = 1.0;
	vec3 world = p0;
	if (f_end >= -0.001 && f_end < 1.0 && dot(seg, seg) > 1e-8) {
		vec3 p = p0 + seg * UV.y;
		vec3 to_cam = INV_VIEW_MATRIX[3].xyz - p;
		vec3 sv = cross(seg, to_cam);
		float sl = length(sv);
		vec3 side = sl > 1e-6 ? sv / sl : vec3(1.0, 0.0, 0.0);
		// metres per pixel at this distance (the fov spans the viewport's height)
		// (abs: a render target flips the projection's y in the Compatibility renderer, pass 80)
		float mpp = 2.0 * length(to_cam) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
		if (style < 0.5) {
			float w = info.z * (1.0 + widen * f);
			w = max(w, min_px * mpp);
			p += side * (v_x * w * 0.5 + sin(dot(p.xz, vec2(1.7, 1.3)) + age * 4.0) * sway * f);
			p.y += rise * age;
		} else {
			float head = max(info.z, head_px * mpp);
			float tw;
			if (style < 1.5) {
				tw = head * pow(1.0 - f, streak_taper);
			} else if (style < 2.5) {
				tw = head * pow(1.0 - f, ribbon_taper) * (1.0 + ribbon_wake * f);
			} else if (style < 3.5) {
				tw = head * pow(max(1.0 - f / hot, 0.0), streak_taper);
			} else {
				tw = head * toon_scale * pow(1.0 - f, toon_taper);
			}
			float w = tw;
			if (style > 2.5 && style < 3.5) {
				float mw = head * smoke_width * (0.3 + 0.7 * f);
				w = max(tw, mw);
				v_mw = mw / max(w, 1e-5);
				p.y += smoke_rise * age;
			}
			w = max(w, 1e-5);
			v_tw = tw / w;
			v_px = w / mpp;
			p += side * (v_x * w * 0.5);
		}
		world = p;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(INV_VIEW_MATRIX[2].xyz, 0.0)).xyz);
}

// the tracer colours are written as they should look on the screen (sRGB, as in the JSON); the renderer works in linear
vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

// The colour lit up towards the head (`k` 1 at the bullet): its brightest channel pushed to full, the hue kept.
// How light and saturated a colour is, 0..1 (gold 1, Silver Bullet's pale silver 0, red 0): such a colour reads as a
// cream fill on the sand, so its body goes amber and its white middle stays at the tip.
float warm_light(vec3 c) {
	float mx = max(max(c.r, c.g), c.b);
	float sat = mx > 1e-4 ? (mx - min(min(c.r, c.g), c.b)) / mx : 0.0;
	return smoothstep(0.45, 0.85, dot(c, vec3(0.3, 0.59, 0.11))) * smoothstep(0.25, 0.55, sat);
}

vec3 head_lit(vec3 c, float k) {
	float m = max(max(c.r, c.g), max(c.b, 0.05));
	return mix(c, c / m, k * head_glow);
}

// One trail layer across its own half-width (tx 0 at the middle, 1 at the edge; px = one pixel in tx): the white core
// (core_w), the colour, the rim; rgb in .rgb, coverage in .a. `hard` = the toon bands.
vec4 trail_layer(vec3 c, float tx, float px, float core_w, bool hard) {
	vec3 core = mix(core_white, c, core_tint);
	vec3 rim = pow(max(c, vec3(0.0)), vec3(rim_pow)) * rim_gain;
	float aa = max(px, 0.02);
	vec3 col;
	float a;
	if (hard) {
		col = mix(core, c, smoothstep(core_w - aa * 0.5, core_w + aa * 0.5, tx));
		col = mix(col, rim * toon_outline, smoothstep(0.74 - aa * 0.5, 0.74 + aa * 0.5, tx));
		a = 1.0 - smoothstep(1.0 - aa, 1.0, tx);
	} else {
		// neon: a solid stroke of the colour (inner_w of the half-width) with a thin hot middle (core_w, gone once core_w
		// is), and round it a halo of the same colour fading out to the edge (the glow the renderer has no pass for)
		// a light colour (silver, gold) gets a darker body, edge and halo of its own hue: value contrast on the sand
		float light = smoothstep(0.45, 0.85, dot(c, vec3(0.3, 0.59, 0.11)));
		float iw = max(inner_w, aa);
		float inner = 1.0 - smoothstep(iw - aa * 0.5, iw + aa * 0.5, tx);
		float cw = (1.0 - smoothstep(core_w * 0.4, core_w + aa * 0.5, tx)) * smoothstep(0.0, 0.05, core_w);
		vec3 body = mix(c, rim, max(light * light_dark, warm_light(c) * warm_dark));
		vec3 stroke = mix(mix(body, rim, smoothstep(iw * 0.5, iw, tx) * mix(rim_mix, rim_light, light)), core, cw);
		float h = 1.0 - smoothstep(iw, 1.0, tx);
		float ha = halo_alpha * h * h;
		a = inner + ha * (1.0 - inner);
		col = mix(mix(c, rim, light * 0.85), stroke, a > 1e-4 ? inner / a : 0.0);
	}
	return vec4(col, a);
}

void fragment() {
	float f = clamp(v_f, 0.0, 1.0);
	vec3 c = COLOR.rgb;
	if (v_s < 0.5) {
		float edge = 1.0 - smoothstep(1.0 - edge_soft, 1.0, abs(v_x));
		float l = dot(c, vec3(0.3, 0.59, 0.11));
		ALBEDO = to_linear(mix(c, vec3(l), smoke_grey * f));
		ALPHA = COLOR.a * pow(1.0 - f, fade_pow) * edge;
	} else {
		float ax = abs(v_x);
		float pxq = 2.0 / max(v_px, 0.5);
		float tw = max(v_tw, 1e-4);
		float tx = ax / tw;
		float px = pxq / tw;
		vec3 col;
		float a;
		if (v_s < 1.5) {
			// streak: the core all the way while young, gone towards the tail; holds, then fades
			float k = 1.0 - smoothstep(0.0, v_hot * mix(1.0, warm_tip, warm_light(c)), f);
			vec4 t = trail_layer(head_lit(c, k), tx, px, core_size * k, false);
			col = t.rgb;
			a = t.a * (1.0 - smoothstep(0.55, 1.0, f));
		} else if (v_s < 2.5) {
			// ribbon: the core lives only the first `hot` of the life; the colour fades after
			float k = 1.0 - smoothstep(0.0, v_hot * mix(1.0, warm_tip, warm_light(c)), f);
			vec4 t = trail_layer(head_lit(c, k), tx, px, core_size * k, false);
			col = t.rgb;
			a = t.a * pow(1.0 - f, 1.1);
		} else if (v_s < 3.5) {
			// wisp: the streak (its own clock: f / hot) over the smoke
			float fs = f / v_hot;
			vec4 t = vec4(0.0);
			if (fs < 1.0 && v_tw > 1e-3) {
				float k = 1.0 - smoothstep(0.0, 0.8 * mix(1.0, warm_tip, warm_light(c)), fs);
				t = trail_layer(head_lit(c, k), tx, px, core_size * k, false);
				t.a *= 1.0 - smoothstep(0.6, 1.0, fs);
			}
			float mx = ax / max(v_mw, 1e-4);
			vec3 mc = mix(c, smoke_colour, 0.78);
			float ma = smoke_alpha * smoothstep(0.0, 0.25, f) * pow(1.0 - f, 1.4) * (1.0 - smoothstep(0.3, 1.0, mx));
			a = t.a + ma * (1.0 - t.a);
			col = mix(mc, t.rgb, a > 1e-4 ? t.a / a : 0.0);
		} else {
			// toon: hard bands, opaque until the end
			float k = 1.0 - smoothstep(0.0, v_hot, f) * 0.6;
			vec4 t = trail_layer(c, tx, px, 0.24 * k, true);
			col = t.rgb;
			a = t.a * (1.0 - smoothstep(0.78, 1.0, f));
		}
		ALBEDO = to_linear(col);
		ALPHA = COLOR.a * a;
	}
}
